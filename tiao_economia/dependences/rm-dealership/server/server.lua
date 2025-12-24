-- [rm-dealership]/server/main.lua
-- Sistema de concessionária otimizado (oxmysql + QBCore/qbx_core)
-- Ajustes principais:
--  - NÃO limpa mais a tabela a cada restart (seed inteligente apenas se vazia)
--  - Evita queries desnecessárias e lentas
--  - Remove duplicações de callbacks/eventos
--  - Centraliza lógica de VIP e auxiliares

local QBCore = exports['qb-core']:GetCoreObject()

----------------------------------------------------------------------
-- HELPERS BÁSICOS
----------------------------------------------------------------------

local function Log(msg)
    print(('[rm-dealership] %s'):format(msg))
end

-- oxmysql, em versões mais novas, pode devolver number OU table.
-- Normalizamos aqui pra evitar erro "attempt to compare number with table".
local function GetAffectedCount(result)
    local t = type(result)
    if t == 'number' then
        return result
    elseif t == 'table' then
        if type(result.affectedRows) == 'number' then
            return result.affectedRows
        elseif type(result.rowCount) == 'number' then
            return result.rowCount
        elseif type(result.changedRows) == 'number' then
            return result.changedRows
        end
    end
    return 0
end

----------------------------------------------------------------------
-- BANCO: CRIAÇÃO DE TABELA + SEED INTELIGENTE
----------------------------------------------------------------------

local function SeedDealershipVehicles()
    if not Config or not Config.Vehicles then
        Log('ERRO: Config.Vehicles não encontrado. Verifique o config.lua.')
        return
    end

    -- Só faz seed se a tabela estiver VAZIA
    MySQL.scalar('SELECT COUNT(*) FROM dealership_vehicles', {}, function(count)
        count = tonumber(count) or 0

        if count > 0 then
            Log(('Tabela dealership_vehicles já possui %d veículos, seed ignorado.'):format(count))
            return
        end

        Log('Tabela dealership_vehicles vazia, iniciando seed de veículos padrão...')

        for i = 1, #Config.Vehicles do
            local v = Config.Vehicles[i]
            if v and v.model then
                MySQL.insert(
                    'INSERT INTO dealership_vehicles (model, name, price, category, stock, description) VALUES (?, ?, ?, ?, ?, ?)',
                    {
                        v.model,
                        v.label or v.name or v.model,
                        v.price or 0,
                        v.category or 'compacts',
                        v.stock or 0,
                        v.description or 'A premium vehicle available at our dealership.',
                    },
                    function(insertId)
                        -- log leve opcional:
                        -- if insertId then
                        --     Log(('Veículo seedado: %s (%s), id=%s'):format(v.label or v.model, v.model, tostring(insertId)))
                        -- end
                    end
                )
            end
        end

        Log('Seed de veículos concluído.')
    end)
end

-- Criação da tabela + seed em thread de inicialização
CreateThread(function()
    -- Cria tabela se não existir (com UNIQUE em model pra evitar duplicatas)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `dealership_vehicles` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `model` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `price` int(11) NOT NULL,
            `category` varchar(50) NOT NULL,
            `stock` int(11) NOT NULL,
            `description` text,
            PRIMARY KEY (`id`),
            UNIQUE KEY `model` (`model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        Log('Tabela dealership_vehicles verificada/criada.')
        SeedDealershipVehicles()
    end)
end)

----------------------------------------------------------------------
-- HELPERS DE LÓGICA: VIP, PLACAS, PROPRIEDADE DE VEÍCULO
----------------------------------------------------------------------

--- Calcula desconto VIP de um player (metadata, zonas ou grupo).
-- @return vipDiscount (number), vipType (string|nil)
local function GetVipDiscount(Player)
    if not Player or not Player.PlayerData then
        return 0, nil
    end

    local vipDiscount = 0
    local vipType = nil
    local metadata = Player.PlayerData.metadata or {}

    -- Estrutura padrão: metadata.vip = 'vip1' / 'vip2' / etc.
    if metadata.vip and Config.VIPDiscounts[metadata.vip] then
        vipDiscount = Config.VIPDiscounts[metadata.vip]
        vipType = metadata.vip
    end

    -- Se ainda não encontrou VIP, checa por zonas (zonaoeste / zonanorte / etc.)
    if vipDiscount == 0 then
        local zoneVips = {'zonaoeste', 'zonanorte', 'zonasul', 'cristo', 'reidorio'}
        for _, zone in ipairs(zoneVips) do
            if metadata[zone] and Config.VIPDiscounts[zone] then
                vipDiscount = Config.VIPDiscounts[zone]
                vipType = zone
                break
            end
        end
    end

    -- Se ainda nada, tentar pelo grupo (admin, vip, staff, etc.)
    if vipDiscount == 0 and Player.PlayerData.group and Config.VIPDiscounts[Player.PlayerData.group] then
        vipDiscount = Config.VIPDiscounts[Player.PlayerData.group]
        vipType = Player.PlayerData.group
    end

    return vipDiscount, vipType
end

--- Verifica se o player já possui um veículo pelo model (não pela placa)
local function PlayerOwnsVehicle(citizenid, vehicleModel)
    if not citizenid or not vehicleModel then
        return false
    end

    local success, result = pcall(function()
        return MySQL.scalar.await(
            'SELECT COUNT(*) FROM player_vehicles WHERE citizenid = ? AND vehicle = ?',
            { citizenid, vehicleModel },
            5000
        )
    end)

    if not success then
        -- Em caso de erro de DB, retornamos false pra NÃO travar a compra.
        return false
    end

    result = tonumber(result) or 0
    return result > 0
end

--- Gera placa única com limite de tentativas e fallback em timestamp
local function GenerateVehiclePlate(retryCount)
    retryCount = retryCount or 0

    -- Evita recursão infinita
    if retryCount >= 50 then
        local timestamp = os.time()
        return 'ER' .. string.sub(tostring(timestamp), -6)
    end

    local plate = ''
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    for i = 1, 8 do
        local rand = math.random(#chars)
        plate = plate .. string.sub(chars, rand, rand)
    end

    -- Confere se já existe
    local success, result = pcall(function()
        return MySQL.scalar.await(
            'SELECT COUNT(*) FROM player_vehicles WHERE plate = ?',
            { plate },
            5000
        )
    end)

    if not success then
        local timestamp = os.time()
        return 'DB' .. string.sub(tostring(timestamp), -6)
    end

    result = tonumber(result) or 0
    if result > 0 then
        return GenerateVehiclePlate(retryCount + 1)
    end

    return plate
end

--- Envia webhook de compra
local function SendDiscordWebhook(Player, vehicle, price, plate)
    if not Config.UseWebhook or not Config.WebhookURL or Config.WebhookURL == '' then
        return
    end

    local name = 'Desconhecido'
    if Player.PlayerData and Player.PlayerData.charinfo then
        name = (Player.PlayerData.charinfo.firstname or '') .. ' ' .. (Player.PlayerData.charinfo.lastname or '')
    end

    local embed = {
        {
            title = "🚗 Vehicle Purchase",
            color = 3447003,
            fields = {
                { name = "Player",     value = name,                         inline = true },
                { name = "Citizen ID", value = Player.PlayerData.citizenid, inline = true },
                { name = "Vehicle",    value = vehicle.name .. " (" .. vehicle.model .. ")", inline = true },
                { name = "Price",      value = "$" .. tostring(price),     inline = true },
                { name = "Plate",      value = plate,                      inline = true },
                { name = "Time",       value = os.date("%Y-%m-%d %H:%M:%S"), inline = true },
            },
            footer = { text = "RM Dealership System" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }

    PerformHttpRequest(
        Config.WebhookURL,
        function() end,
        'POST',
        json.encode({ username = "Dealership Bot", embeds = embed }),
        { ['Content-Type'] = 'application/json' }
    )
end

----------------------------------------------------------------------
-- BUCKET / INSTÂNCIA (TEST DRIVE)
----------------------------------------------------------------------

QBCore.Functions.CreateCallback('rm-dealership:server:getPlayerBucket', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb(0)
        return
    end

    cb(GetPlayerRoutingBucket(source))
end)

RegisterNetEvent('rm-dealership:server:setPlayerBucket', function(bucket)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    bucket = tonumber(bucket) or 0
    SetPlayerRoutingBucket(src, bucket)
end)

----------------------------------------------------------------------
-- CALLBACK: VEÍCULOS DO PLAYER (pra checar se já possui algum model)
----------------------------------------------------------------------

QBCore.Functions.CreateCallback('rm-dealership:server:getPlayerVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({})
        return
    end

    local success, result = pcall(function()
        return MySQL.query.await(
            'SELECT vehicle FROM player_vehicles WHERE citizenid = ?',
            { Player.PlayerData.citizenid },
            5000
        )
    end)

    if not success or not result then
        cb({})
        return
    end

    local owned = {}
    for i = 1, #result do
        owned[result[i].vehicle] = true
    end

    cb(owned)
end)

----------------------------------------------------------------------
-- CALLBACK: DADOS DE VEÍCULOS PARA O PLAYER (loja)
----------------------------------------------------------------------

QBCore.Functions.CreateCallback('rm-dealership:server:getVehicleData', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({}, 0, {})
        return
    end

    local vipDiscount, vipType = GetVipDiscount(Player)

    MySQL.query('SELECT * FROM dealership_vehicles WHERE stock > 0', {}, function(result)
        local vehicles = {}

        if result then
            for i = 1, #result do
                local vehicle = result[i]

                -- Busca extra no Config.Vehicles pra pegar img, stats, etc.
                local configVehicle
                if Config.Vehicles then
                    for j = 1, #Config.Vehicles do
                        if Config.Vehicles[j].model == vehicle.model then
                            configVehicle = Config.Vehicles[j]
                            break
                        end
                    end
                end

                local originalPrice = vehicle.price
                local vipPrice = originalPrice
                if vipDiscount > 0 then
                    vipPrice = math.floor(originalPrice * (100 - vipDiscount) / 100)
                end

                vehicles[#vehicles + 1] = {
                    model       = vehicle.model,
                    name        = vehicle.name,
                    price       = originalPrice,
                    vipPrice    = vipPrice,
                    category    = vehicle.category,
                    stock       = vehicle.stock,
                    description = vehicle.description,
                    img         = configVehicle and configVehicle.img or 'https://docs.fivem.net/vehicles/adder.webp',
                    information = configVehicle and configVehicle.information or {
                        TopSpeed     = 100,
                        Braking      = 50,
                        Acceleration = 50,
                        Suspension   = 50,
                        Handling     = 50,
                    },
                    discount    = configVehicle and configVehicle.discount or 0
                }
            end
        end

        local playerMoney = Player.PlayerData.money['bank'] or 0
        local vipInfo = {
            hasVip      = vipDiscount > 0,
            vipType     = vipType,
            vipDiscount = vipDiscount
        }

        cb(vehicles, playerMoney, vipInfo)
    end)
end)

----------------------------------------------------------------------
-- CALLBACK: DADOS ADMIN (lista completa de veículos)
----------------------------------------------------------------------

QBCore.Functions.CreateCallback('rm-dealership:server:getAdminData', function(source, cb)
    MySQL.query('SELECT * FROM dealership_vehicles', {}, function(result)
        local vehicles = {}

        if result then
            for i = 1, #result do
                local vehicle = result[i]

                local configVehicle
                if Config.Vehicles then
                    for j = 1, #Config.Vehicles do
                        if Config.Vehicles[j].model == vehicle.model then
                            configVehicle = Config.Vehicles[j]
                            break
                        end
                    end
                end

                vehicles[#vehicles + 1] = {
                    model       = vehicle.model,
                    name        = vehicle.name,
                    price       = vehicle.price,
                    category    = vehicle.category,
                    stock       = vehicle.stock,
                    description = vehicle.description,
                    img         = configVehicle and configVehicle.img or 'https://docs.fivem.net/vehicles/adder.webp',
                    information = configVehicle and configVehicle.information or {
                        TopSpeed     = 100,
                        Braking      = 50,
                        Acceleration = 50,
                        Suspension   = 50,
                        Handling     = 50,
                    },
                    discount    = configVehicle and configVehicle.discount or 0
                }
            end
        end

        cb({ vehicles = vehicles })
    end)
end)

----------------------------------------------------------------------
-- CALLBACK: COMPRA DE VEÍCULO
----------------------------------------------------------------------

QBCore.Functions.CreateCallback('rm-dealership:server:buyVehicle', function(source, cb, vehicleData)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb(false, 'Jogador não encontrado')
        return
    end

    if not vehicleData or not vehicleData.model then
        cb(false, 'Dados de veículo inválidos')
        return
    end

    -- Checa se o player já possui esse modelo
    if PlayerOwnsVehicle(Player.PlayerData.citizenid, vehicleData.model) then
        cb(false, 'Você já possui este modelo de veículo. Verifique sua garagem.')
        return
    end

    -- Busca veículo na tabela da concessionária
    local success, result = pcall(function()
        return MySQL.query.await(
            'SELECT * FROM dealership_vehicles WHERE model = ?',
            { vehicleData.model },
            5000
        )
    end)

    if not success or not result or #result == 0 then
        cb(false, 'Veículo não encontrado na concessionária ou erro de conexão')
        return
    end

    local vehicle = result[1]
    if vehicle.stock <= 0 then
        cb(false, 'Veículo fora de estoque')
        return
    end

    local finalPrice = vehicle.price
    local vipDiscount, vipType = GetVipDiscount(Player)

    if vipDiscount > 0 then
        finalPrice = math.floor(finalPrice * (100 - vipDiscount) / 100)
    end

    local bankMoney = Player.PlayerData.money['bank'] or 0
    if bankMoney < finalPrice then
        cb(false, 'Fundos insuficientes. Você precisa de $' .. finalPrice)
        return
    end

    local plate = GenerateVehiclePlate()

    -- Cobra do player
    Player.Functions.RemoveMoney('bank', finalPrice, 'rm-dealership-purchase')

    -- Registra veículo no player_vehicles (state 1 = fora da garagem)
    local insertSuccess, insertId = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            {
                Player.PlayerData.license,
                Player.PlayerData.citizenid,
                vehicleData.model,
                GetHashKey(vehicleData.model),
                '{}',
                plate,
                Config.DefaultGarage or 'legion',
                1
            },
            5000
        )
    end)

    if not insertSuccess or not insertId then
        -- Falhou: devolve dinheiro
        Player.Functions.AddMoney('bank', finalPrice, 'rm-dealership-refund')
        cb(false, 'Falha ao registrar veículo')
        return
    end

    -- Diminui estoque (pcall pra não travar em caso de erro de DB)
    pcall(function()
        MySQL.update.await(
            'UPDATE dealership_vehicles SET stock = stock - 1 WHERE model = ?',
            { vehicleData.model },
            5000
        )
    end)

    -- Webhook
    SendDiscordWebhook(Player, vehicle, finalPrice, plate)

    -- Chaves permanentes (compra)
    if GetResourceState('mri_Qcarkeys') == 'started' then
        -- vehiclekeys:client:SetOwner já cuida de chaves locais
        TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate, true)
    elseif Config.VehicleKeys == 'qb-vehiclekeys' and GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    elseif Config.VehicleKeys == 'qbx-vehiclekeys' and GetResourceState('qbx-vehiclekeys') == 'started' then
        TriggerClientEvent('rm-dealership:client:giveQBXKeysForPlate', source, plate)
    end

    -- Spawn + mensagem
    TriggerClientEvent('rm-dealership:client:spawnPurchasedVehicle', source, {
        model = vehicleData.model,
        plate = plate,
        name  = vehicle.name
    })

    local purchaseMessage = ('Seu %s (Placa: %s) foi entregue com as chaves. Aproveite seu novo veículo!'):format(vehicle.name, plate)
    local successMessage  = ('Veículo comprado com sucesso! Seu %s foi entregue com as chaves (Placa: %s)'):format(vehicle.name, plate)

    if vipDiscount > 0 then
        local discountAmount = vehicle.price - finalPrice
        local vipInfo = string.format(
            ' (Desconto VIP %s: -%d%% = -R$%s)',
            (vipType or 'VIP'):upper(),
            vipDiscount,
            tostring(discountAmount)
        )
        purchaseMessage = purchaseMessage + vipInfo
        successMessage  = successMessage + vipInfo
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title       = 'Compra Realizada!',
        description = purchaseMessage,
        type        = 'success',
        duration    = 8000
    })

    cb(true, successMessage)
end)

----------------------------------------------------------------------
-- ADMIN: ADD / REMOVE / UPDATE VEÍCULOS
----------------------------------------------------------------------

local function PlayerHasAdminAccess(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then
        return false
    end

    if not Config.AdminJobs then
        return false
    end

    for i = 1, #Config.AdminJobs do
        if Player.PlayerData.job.name == Config.AdminJobs[i] then
            return true
        end
    end

    return false
end

RegisterNetEvent('rm-dealership:server:addVehicle', function(vehicleData)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not PlayerHasAdminAccess(Player) then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Acesso Negado',
            description = 'Você não tem permissão para adicionar veículos',
            type        = 'error'
        })
        return
    end

    if not vehicleData or not vehicleData.model then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Erro',
            description = 'Dados de veículo inválidos',
            type        = 'error'
        })
        return
    end

    MySQL.insert(
        'INSERT INTO dealership_vehicles (model, name, price, category, stock, description) VALUES (?, ?, ?, ?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE name = VALUES(name), price = VALUES(price), category = VALUES(category), stock = VALUES(stock), description = VALUES(description)',
        {
            vehicleData.model,
            vehicleData.name,
            vehicleData.price,
            vehicleData.category,
            vehicleData.stock,
            vehicleData.description
        },
        function(id)
            TriggerClientEvent('ox_lib:notify', src, {
                title       = id and 'Sucesso' or 'Erro',
                description = id and 'Veículo adicionado/atualizado com sucesso' or 'Falha ao adicionar veículo',
                type        = id and 'success' or 'error'
            })
        end
    )
end)

RegisterNetEvent('rm-dealership:server:removeVehicle', function(model)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not PlayerHasAdminAccess(Player) then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Acesso Negado',
            description = 'Você não tem permissão para remover veículos',
            type        = 'error'
        })
        return
    end

    if not model or model == '' then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Erro',
            description = 'Modelo inválido',
            type        = 'error'
        })
        return
    end

    MySQL.update('DELETE FROM dealership_vehicles WHERE model = ?', { model }, function(result)
        local affected = GetAffectedCount(result)
        if affected > 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'Sucesso',
                description = 'Veículo removido com sucesso',
                type        = 'success'
            })
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'Erro',
                description = 'Veículo não encontrado',
                type        = 'error'
            })
        end
    end)
end)

RegisterNetEvent('rm-dealership:server:updateVehicle', function(vehicleData)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not PlayerHasAdminAccess(Player) then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Acesso Negado',
            description = 'Você não tem permissão para atualizar veículos',
            type        = 'error'
        })
        return
    end

    if not vehicleData or not vehicleData.model then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Erro',
            description = 'Dados de veículo inválidos',
            type        = 'error'
        })
        return
    end

    MySQL.update(
        'UPDATE dealership_vehicles SET name = ?, price = ?, category = ?, stock = ?, description = ? WHERE model = ?',
        {
            vehicleData.name,
            vehicleData.price,
            vehicleData.category,
            vehicleData.stock,
            vehicleData.description,
            vehicleData.model
        },
        function(result)
            local affected = GetAffectedCount(result)
            if affected > 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title       = 'Sucesso',
                    description = 'Veículo atualizado com sucesso',
                    type        = 'success'
                })
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title       = 'Erro',
                    description = 'Falha ao atualizar veículo',
                    type        = 'error'
                })
            end
        end
    )
end)

----------------------------------------------------------------------
-- TEST DRIVE: CHAVES E LIMPEZA
----------------------------------------------------------------------

-- Dar chaves temporárias para test drive
RegisterNetEvent('rm-dealership:server:giveTestDriveKeys', function(plate, vehicle)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if Config.VehicleKeys == 'mri_Qcarkeys' and GetResourceState('mri_Qcarkeys') == 'started' then
        local ok = pcall(function()
            exports['mri_Qcarkeys']:GiveTempKeys(src, plate)
        end)

        if not ok then
            TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate, true)
        end
    elseif Config.VehicleKeys == 'qb-vehiclekeys' and GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    elseif Config.VehicleKeys == 'qbx-vehiclekeys' and GetResourceState('qbx-vehiclekeys') == 'started' then
        -- Se usar qbx-vehiclekeys baseado em entidade:
        if type(vehicle) == 'number' then
            exports['qbx-vehiclekeys']:GiveKeys(src, vehicle, false)
        else
            TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
        end
    else
        -- Fallback genérico
        TriggerClientEvent('rm-dealership:client:ensureVehicleAccess', src)
    end
end)

-- Remover chaves do test drive
RegisterNetEvent('rm-dealership:server:removeTestDriveKeys', function(plate, vehicle)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    pcall(function()
        if Config.VehicleKeys == 'mri_Qcarkeys' and GetResourceState('mri_Qcarkeys') == 'started' then
            exports['mri_Qcarkeys']:RemoveTempKeys(src, plate)
            TriggerClientEvent('mri_Qcarkeys:client:RemoveKeys', src, plate)
        elseif Config.VehicleKeys == 'qb-vehiclekeys' and GetResourceState('qb-vehiclekeys') == 'started' then
            TriggerClientEvent('vehiclekeys:client:RemoveKeys', src, plate)
        elseif Config.VehicleKeys == 'qbx-vehiclekeys' and GetResourceState('qbx-vehiclekeys') == 'started' then
            if type(vehicle) == 'number' then
                exports['qbx-vehiclekeys']:RemoveKeys(src, vehicle, false)
            end
        end
    end)

    -- Limpa itens de chave no inventário (ox_inventory + QBCore)
    pcall(function()
        if GetResourceState('ox_inventory') == 'started' then
            exports.ox_inventory:RemoveItem(src, 'vehiclekey_' .. plate, 1)
            exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1)
            exports.ox_inventory:RemoveItem(src, 'car_keys', 1)
        end
    end)

    pcall(function()
        if Player.Functions.RemoveItem then
            Player.Functions.RemoveItem('vehiclekey_' .. plate, 1)
            Player.Functions.RemoveItem('vehiclekey', 1)
            Player.Functions.RemoveItem('car_keys', 1)
        end
    end)
end)

-- Debug de chaves (test drive / inventário)
RegisterNetEvent('rm-dealership:server:debugPlayerKeys', function(plate)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    pcall(function()
        if GetResourceState('ox_inventory') == 'started' then
            local inventory = exports.ox_inventory:GetInventory(src)
            if inventory and inventory.items then
                for slot, item in pairs(inventory.items) do
                    if item.name and (string.find(item.name, 'key') or string.find(item.name, plate or '')) then
                        if item.metadata and item.metadata.plate == plate then
                            exports.ox_inventory:RemoveItem(src, item.name, 1, item.metadata, slot)
                        end
                    end
                end
            end
        end
    end)

    pcall(function()
        if GetResourceState('mri_Qcarkeys') == 'started' then
            if exports['mri_Qcarkeys'].HasKeys then
                local _ = exports['mri_Qcarkeys']:HasKeys(src, plate)
                -- apenas para debug interno; você pode logar se quiser
            end
        end
    end)
end)

-- Dar chaves permanentes quando usando qbx-vehiclekeys diretamente por placa
RegisterNetEvent('rm-dealership:server:giveVehicleKeys', function(plate)
    local src = source
    if Config.VehicleKeys == 'qbx-vehiclekeys' and GetResourceState('qbx-vehiclekeys') == 'started' then
        TriggerClientEvent('rm-dealership:client:giveQBXKeysForPlate', src, plate)
    end
end)
