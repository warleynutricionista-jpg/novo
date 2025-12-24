-- KLB Management • Boss (Empregos) — Client
-- Compatível com qbx-core e qb-core. Envia rótulos PT-BR à NUI.
-- Fecha a tablet ao abrir o cofre e REABRE quando o cofre (ox_inventory) é fechado.

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------
local QBCore = (function()
    local ok, obj = pcall(function() return exports['qbx-core']:GetCoreObject() end)
    if ok and obj then return obj end
    ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then return obj end
    error('KLB Boss: não foi possível obter CoreObject (qbx-core / qb-core).')
end)()

--------------------------------------------------------------------------------
-- Estado local
--------------------------------------------------------------------------------
local PlayerJob = (QBCore.Functions.GetPlayerData() or {}).job or {}
local shownBossMenu = false
local DynamicMenuItems = {}
local nuiOpen = false

-- stash que abrimos por último (para reabrir a tablet quando fechar)
local lastBossStashId = nil

-- rótulos PT-BR enviados para a NUI (se ela suportar)
local LABELS_PT = {
    economy        = 'Banco',
    employees      = 'Funcionários',
    stash          = 'Cofre',
    transactions   = 'Transações',
    deposit        = 'Depositar',
    withdraw       = 'Sacar',
    exit           = 'Sair',
    jobPrefix      = 'Emprego',
    searchHint     = 'Pesquisar por nome / ID / cargo...',
    playerId       = 'ID do Jogador',
    name           = 'Nome',
    grade          = 'Cargo',
    status         = 'Status',
    actions        = 'Ações',
    online         = 'Online',
    offline        = 'Offline',
    promote        = 'Promover',
    fire           = 'Demitir',
    hireEmployee   = 'Contratar',
    defaultGrade   = 'Cargo Padrão',
    serverIdHint   = 'ID do Servidor (ex.: 42)',
    you            = 'Você',
}

--------------------------------------------------------------------------------
-- Utilitários
--------------------------------------------------------------------------------
local function safeDeepcopy(val)
    if type(deepcopy) == 'function' then
        return deepcopy(val)
    end
    if type(val) ~= 'table' then return val end
    local res = {}
    for k, v in pairs(val) do
        res[k] = type(v) == 'table' and safeDeepcopy(v) or v
    end
    return res
end

local function CoreDrawText(msg, side)
    if GetResourceState('qb-core') == 'started' and exports['qb-core'] and exports['qb-core'].DrawText then
        exports['qb-core']:DrawText(msg, side or 'left')
    elseif GetResourceState('qbx-core') == 'started' and exports['qbx-core'] and exports['qbx-core'].DrawText then
        exports['qbx-core']:DrawText(msg, side or 'left')
    end
end

local function CoreHideText()
    if GetResourceState('qb-core') == 'started' and exports['qb-core'] and exports['qb-core'].HideText then
        exports['qb-core']:HideText()
    elseif GetResourceState('qbx-core') == 'started' and exports['qbx-core'] and exports['qbx-core'].HideText then
        exports['qbx-core']:HideText()
    end
end

local function LT(key)
    if Lang and Lang.t then return Lang:t(key) end
    return key
end

local function setNui(state)
    nuiOpen = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function CloseMenuFull()
    SendNUIMessage({ page = 'boss', action = 'close' })
    setNui(false)
    CoreHideText()
    shownBossMenu = false
end

local function AddBossMenuItem(data, id)
    local menuID = id or (#DynamicMenuItems + 1)
    DynamicMenuItems[menuID] = safeDeepcopy(data)
    return menuID
end
exports('AddBossMenuItem', AddBossMenuItem)

local function RemoveBossMenuItem(id)
    DynamicMenuItems[id] = nil
end
exports('RemoveBossMenuItem', RemoveBossMenuItem)

--------------------------------------------------------------------------------
-- Eventos de player
--------------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        local pdata = QBCore.Functions.GetPlayerData() or {}
        PlayerJob = pdata.job or {}
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local pdata = QBCore.Functions.GetPlayerData() or {}
    PlayerJob = pdata.job or {}
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerJob = JobInfo or {}
end)

--------------------------------------------------------------------------------
-- Abrir menu
--------------------------------------------------------------------------------
local function collectGrades(jobName)
    local out = {}
    if QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[jobName] and QBCore.Shared.Jobs[jobName].grades then
        for k, v in pairs(QBCore.Shared.Jobs[jobName].grades) do
            out[#out+1] = { level = tonumber(k) or 0, name = v.name }
        end
        table.sort(out, function(a,b) return a.level < b.level end)
    end
    return out
end

RegisterNetEvent('qb-bossmenu:client:OpenMenu', function()
    if not PlayerJob or not PlayerJob.name or not PlayerJob.isboss then return end

    local jobName  = PlayerJob.name
    local jobLabel = PlayerJob.label or jobName
    local grades   = collectGrades(jobName)

    setNui(true)
    SendNUIMessage({
        page   = 'boss',
        action = 'open',
        mode   = 'boss',
        gang   = { name = jobName, label = jobLabel },  -- mantém chave 'gang' usada pelo HTML
        grades = grades,
        labels = LABELS_PT
    })

    -- Pré-carrega a lista de membros (para UI mais rápida)
    QBCore.Functions.TriggerCallback('qb-bossmenu:server:GetEmployeesNUI', function(list)
        SendNUIMessage({ page = 'boss', action = 'members', members = list or {} })
    end, jobName)
end)

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------
RegisterNUICallback('boss:sync', function(_, cb)
    local jobName  = (PlayerJob and PlayerJob.name) or 'none'
    local jobLabel = (PlayerJob and PlayerJob.label) or 'Emprego'
    local grades   = collectGrades(jobName)

    QBCore.Functions.TriggerCallback('qb-bossmenu:server:GetDashboard', function(result)
        result = result or {}
        result.gang   = result.gang   or { name = jobName, label = jobLabel }
        result.grades = result.grades or grades
        result.labels = LABELS_PT
        cb(result)
    end, jobName)
end)

-- opcional: lista jogadores próximos (se sua NUI usar)
RegisterNUICallback('boss:getplayers', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-bossmenu:getplayers', function(players)
        cb(players or {})
    end)
end)

RegisterNUICallback('boss:setrank', function(data, cb)
    local cid   = data and data.cid
    local grade = data and data.grade
    if cid ~= nil and grade ~= nil then
        local jobName = (PlayerJob and PlayerJob.name) or 'none'
        local grades = (QBCore.Shared.Jobs[jobName] and QBCore.Shared.Jobs[jobName].grades) or {}
        local gname  = (grades[tostring(grade)] and grades[tostring(grade)].name) or tostring(grade)
        TriggerServerEvent('qb-bossmenu:server:GradeUpdate', { cid = cid, grade = tonumber(grade) or 0, gradename = gname })
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('boss:fire', function(data, cb)
    local cid = data and data.cid
    if cid then
        TriggerServerEvent('qb-bossmenu:server:FireEmployee', cid)
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('boss:invite', function(data, cb)
    local id    = data and data.id
    local grade = tonumber(data and data.grade) or 0
    if id then
        TriggerServerEvent('qb-bossmenu:server:HireEmployee', tonumber(id), grade)
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('boss:transfer', function(data, cb)
    local payload = {
        type   = (data and data.type) or 'deposit',
        amount = tonumber(data and data.amount or 0) or 0,
        job    = (PlayerJob and PlayerJob.name) or 'none',
        note   = (data and data.note) or '',
        target = (data and data.target) or ''
    }
    QBCore.Functions.TriggerCallback('qb-bossmenu:server:Transfer', function(res)
        cb(res or { ok = false, error = 'failed' })
    end, payload)
end)

-- ABRIR COFRE: fecha a tablet e marca qual stash foi aberto
RegisterNUICallback('boss:stash', function(_, cb)
    -- calcula/guarda o stashId usado no servidor (boss_<job>)
    if PlayerJob and PlayerJob.name then
        lastBossStashId = ('boss_%s'):format(PlayerJob.name)
    else
        lastBossStashId = nil
    end

    -- fecha a tablet para não atrapalhar a UI do inventário
    SendNUIMessage({ page = 'boss', action = 'close' })
    setNui(false)
    CoreHideText()
    shownBossMenu = false

    -- abre via servidor (ox/qs/ps conforme instalado)
    SetTimeout(100, function()
        TriggerServerEvent('qb-bossmenu:server:stash')
    end)

    cb({ ok = true })
end)

RegisterNUICallback('boss:notify', function(data, cb)
    local message = data and data.message
    if message and message ~= '' then
        local nType  = (data and data.type) or 'primary'
        local length = tonumber(data and (data.length or data.duration))
        QBCore.Functions.Notify(message, nType, length)
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('boss:close', function(_, cb)
    CloseMenuFull()
    cb({ ok = true })
end)

RegisterNetEvent('klb-management:client:closeBossMenu', function()
    CloseMenuFull()
end)

--------------------------------------------------------------------------------
-- Reabrir a tablet ao FECHAR o cofre (ox_inventory)
--------------------------------------------------------------------------------
-- ox_inventory dispara: AddEventHandler('ox_inventory:closeInventory', function(type, id) ... end)
-- Reabrimos a tablet do boss somente se fechar o stash que abrimos.
AddEventHandler('ox_inventory:closeInventory', function(invType, id)
    if invType ~= 'stash' then return end
    if not lastBossStashId or id ~= lastBossStashId then return end
    lastBossStashId = nil
    -- pequena folga para o foco do ox soltar
    SetTimeout(50, function()
        TriggerEvent('qb-bossmenu:client:OpenMenu')
    end)
end)

--------------------------------------------------------------------------------
-- Extras (guarda-roupa)
--------------------------------------------------------------------------------
RegisterNetEvent('qb-bossmenu:client:Wardrobe', function()
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end)

--------------------------------------------------------------------------------
-- Loop / Target
--------------------------------------------------------------------------------
CreateThread(function()
    if Config.UseTarget then
        for job, zones in pairs(Config.BossMenus or {}) do
            for index, coords in ipairs(zones) do
                local zoneName = ('%s_bossmenu_%s'):format(job, index)
                exports['qb-target']:AddCircleZone(zoneName, coords, 0.5, {
                    name = zoneName,
                    debugPoly = false,
                    useZ = true
                }, {
                    options = {
                        {
                            type  = 'client',
                            event = 'qb-bossmenu:client:OpenMenu',
                            icon  = 'fas fa-briefcase',
                            label = (Lang and Lang.t and Lang:t('target.label')) or 'Abrir Painel do Chefe',
                            canInteract = function()
                                return job == (PlayerJob.name or '') and PlayerJob.isboss == true
                            end,
                        },
                    },
                    distance = 2.5
                })
            end
        end
        return
    end

    -- modo "E para abrir"
    while true do
        local wait = 2500
        local ped  = PlayerPedId()
        local pos  = GetEntityCoords(ped)
        local inRangeBoss, nearBossmenu = false, false

        if PlayerJob and PlayerJob.name then
            for k, menus in pairs(Config.BossMenus or {}) do
                for _, coords in ipairs(menus) do
                    if k == PlayerJob.name and PlayerJob.isboss then
                        local dist = #(pos - coords)
                        if dist < 5.0 then
                            wait = 0
                            inRangeBoss = true
                            if dist <= 1.5 then
                                nearBossmenu = true
                                if not shownBossMenu then
                                    CoreDrawText((Lang and Lang.t and Lang:t('drawtext.label')) or '[E] Abrir Painel do Chefe', 'left')
                                    shownBossMenu = true
                                end
                                if IsControlJustReleased(0, 38) then
                                    CoreHideText()
                                    TriggerEvent('qb-bossmenu:client:OpenMenu')
                                end
                            end
                        end
                    end
                end
            end
            if not inRangeBoss then
                Wait(1500)
                if shownBossMenu then
                    CloseMenuFull()
                    shownBossMenu = false
                end
            elseif shownBossMenu and not nearBossmenu then
                CloseMenuFull()
                shownBossMenu = false
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Segurança de foco ao parar
--------------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if nuiOpen then setNui(false) end
    CoreHideText()
end)
