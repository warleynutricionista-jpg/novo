-- ============================================
-- SPACE ECONOMY - DATABASE DIRECT INTEGRATIONS v2.0
-- ============================================
-- Sistema atualizado baseado na estrutura REAL do banco de dados
-- Versão: 3.1.0-DB
-- ============================================

if not SE then SE = {} end
if not SE.DBIntegrations then SE.DBIntegrations = {} end

local DBInt = SE.DBIntegrations

-- ============================================
-- CONFIGURAÇÕES
-- ============================================
DBInt.Config = {
    Enabled = true,
    CheckInterval = 60000, -- 60 segundos
    BatchSize = 100,
    MaxRetries = 3,
    DebugMode = true,

    -- Configuração de cada sistema
    Systems = {
        ['ps-banking'] = {
            enabled = true,
            table = 'ps_banking_transactions',
            interval = 60000,
            processor = 'ProcessBankingTransactions'
        },
        ['dealership'] = {
            enabled = true,
            table = 'player_vehicles',
            interval = 120000,
            processor = 'ProcessVehiclePurchases'
        },
        ['properties'] = {
            enabled = true,
            table = 'properties',
            interval = 120000,
            processor = 'ProcessPropertyPurchases'
        }
    }
}

-- ============================================
-- CACHE DE ESTADO
-- ============================================
DBInt.State = {
    initialized = false,
    running = {},
    lastCheck = {},
    stats = {
        totalProcessed = 0,
        totalErrors = 0,
        bySystem = {}
    }
}

-- ============================================
-- FUNÇÕES AUXILIARES
-- ============================================

function DBInt.Debug(message, data)
    if DBInt.Config.DebugMode then
        print(('[^3SPACE ECONOMY DB-INT^7] %s'):format(message))
        if data then
            print(json.encode(data, {indent = true}))
        end
    end
end

function DBInt.Error(message, error)
    print(('[^1SPACE ECONOMY DB-INT ERROR^7] %s'):format(message))
    if error then
        print(json.encode(error, {indent = true}))
    end
end

function DBInt.IsProcessed(sourceSystem, transactionId)
    local result = MySQL.single.await([[
        SELECT COUNT(*) as count
        FROM space_economy_processed_transactions
        WHERE source_system = ? AND transaction_id = ?
    ]], {sourceSystem, transactionId})

    return result and result.count > 0
end

function DBInt.MarkAsProcessed(data)
    local success = pcall(function()
        MySQL.insert.await([[
            INSERT INTO space_economy_processed_transactions
            (source_system, transaction_id, transaction_type, citizenid, amount, tax_amount, tax_type, debt_id, transaction_date, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            data.source_system,
            data.transaction_id,
            data.transaction_type,
            data.citizenid,
            data.amount,
            data.tax_amount,
            data.tax_type,
            data.debt_id or nil,
            data.transaction_date,
            json.encode(data.metadata or {})
        })
    end)

    return success
end

function DBInt.UpdateStats(sourceSystem, success)
    MySQL.update.await([[
        UPDATE space_economy_integration_config
        SET last_check = NOW(),
            total_processed = total_processed + ?,
            total_errors = total_errors + ?
        WHERE source_system = ?
    ]], {
        success and 1 or 0,
        success and 0 or 1,
        sourceSystem
    })
end

function DBInt.CreateDebt(citizenid, amount, reason, taxType, metadata)
    if not SE.Debts or not SE.Debts.Upsert then
        DBInt.Error('SE.Debts.Upsert não está disponível')
        return nil
    end

    local dueTimestamp = os.time() + (7 * 24 * 60 * 60)

    metadata = metadata or {}
    metadata.tax_type = taxType
    metadata.auto_generated = true
    metadata.source = 'db_integration'

    local debtId = SE.Debts.Upsert(citizenid, amount, reason, dueTimestamp, metadata)

    if debtId then
        DBInt.Debug(('Dívida criada: ID=%d, Cidadão=%s, Valor=$%d, Tipo=%s'):format(
            debtId, citizenid, amount, taxType
        ))
    end

    return debtId
end

-- ============================================
-- PROCESSADORES DE TRANSAÇÕES
-- ============================================

--- Processa transações bancárias (IOF) - ESTRUTURA REAL
function DBInt.ProcessBankingTransactions()
    local systemName = 'ps-banking'
    DBInt.Debug('Iniciando processamento de transações bancárias...')

    local processed = 0

    -- Buscar última data processada
    local lastCheck = MySQL.scalar.await([[
        SELECT COALESCE(last_transaction_date, '2024-01-01')
        FROM space_economy_integration_config
        WHERE source_system = ?
    ]], {systemName})

    -- ESTRUTURA REAL: ps_banking_transactions
    -- Campos: id, identifier, description, type, amount, date, isIncome
    local transactions = MySQL.query.await([[
        SELECT
            id,
            identifier as citizenid,
            type,
            amount,
            date as transaction_date,
            description
        FROM ps_banking_transactions
        WHERE date > ?
            AND amount > 0
            AND type = 'bank'
            AND isIncome = 0
        ORDER BY date ASC
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    if not transactions or #transactions == 0 then
        DBInt.Debug('Nenhuma transação bancária nova encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d transações bancárias para processar'):format(#transactions))

    for _, tx in ipairs(transactions) do
        local transactionId = tostring(tx.id)

        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Calcular IOF (0.5% com mínimo de $10)
            local taxRate = 0.5
            local minTax = 10
            local taxAmount = math.max(math.floor(tx.amount * (taxRate / 100)), minTax)

            -- Apenas cobrar IOF em transações acima de $100
            if tx.amount >= 100 and taxAmount > 0 then
                local reason = 'IOF - Transação Bancária'

                local metadata = {
                    original_amount = tx.amount,
                    transaction_type = tx.type,
                    description = tx.description,
                    tax_rate = taxRate,
                    transaction_date = tx.transaction_date
                }

                local debtId = DBInt.CreateDebt(
                    tx.citizenid,
                    taxAmount,
                    reason,
                    'IOF',
                    metadata
                )

                if debtId then
                    DBInt.MarkAsProcessed({
                        source_system = systemName,
                        transaction_id = transactionId,
                        transaction_type = tx.type,
                        citizenid = tx.citizenid,
                        amount = tx.amount,
                        tax_amount = taxAmount,
                        tax_type = 'IOF',
                        debt_id = debtId,
                        transaction_date = tx.transaction_date,
                        metadata = metadata
                    })

                    processed = processed + 1
                end
            else
                -- Marcar como processada mas sem cobrar imposto (valor muito baixo)
                DBInt.MarkAsProcessed({
                    source_system = systemName,
                    transaction_id = transactionId,
                    transaction_type = tx.type,
                    citizenid = tx.citizenid,
                    amount = tx.amount,
                    tax_amount = 0,
                    tax_type = 'IOF',
                    debt_id = nil,
                    transaction_date = tx.transaction_date,
                    metadata = {note = 'Valor abaixo do mínimo para IOF'}
                })
            end
        end
    end

    DBInt.Debug(('Processadas %d transações bancárias'):format(processed))
    return processed
end

--- Processa compras de veículos (IPVA) - ESTRUTURA REAL
function DBInt.ProcessVehiclePurchases()
    local systemName = 'dealership'
    DBInt.Debug('Iniciando processamento de compras de veículos...')

    local processed = 0

    -- ESTRUTURA REAL: player_vehicles
    -- Campos: id, license, citizenid, vehicle, plate, garage, state, last_ipva_at
    -- NOTA: Não há campo 'price' ou 'created_at' padrão
    -- Vamos usar a data de última modificação ou outro critério

    local vehicles = MySQL.query.await([[
        SELECT
            pv.id,
            pv.citizenid,
            pv.vehicle,
            pv.plate,
            pv.last_ipva_at
        FROM player_vehicles pv
        WHERE pv.citizenid IS NOT NULL
            AND pv.citizenid != ''
            AND (pv.last_ipva_at IS NULL OR pv.last_ipva_at < DATE_SUB(NOW(), INTERVAL 30 DAY))
        LIMIT ?
    ]], {DBInt.Config.BatchSize})

    if not vehicles or #vehicles == 0 then
        DBInt.Debug('Nenhum veículo pendente de IPVA encontrado')
        return 0
    end

    DBInt.Debug(('Encontrados %d veículos para IPVA'):format(#vehicles))

    for _, veh in ipairs(vehicles) do
        local transactionId = 'ipva_' .. veh.plate

        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Como não temos o preço no banco, vamos usar um valor fixo
            -- ou buscar de uma tabela de preços de veículos
            local basePrice = 50000 -- Valor base padrão

            -- Tentar buscar preço da dealership_vehicles
            local vehicleData = MySQL.single.await([[
                SELECT price
                FROM dealership_vehicles
                WHERE model = ?
                LIMIT 1
            ]], {veh.vehicle})

            if vehicleData and vehicleData.price then
                basePrice = vehicleData.price
            end

            -- Calcular IPVA (1.5%)
            local taxRate = 1.5
            local taxAmount = math.floor(basePrice * (taxRate / 100))

            if taxAmount > 0 then
                local reason = ('IPVA - Veículo %s (%s)'):format(veh.vehicle, veh.plate)

                local metadata = {
                    vehicle = veh.vehicle,
                    plate = veh.plate,
                    base_price = basePrice,
                    tax_rate = taxRate
                }

                local debtId = DBInt.CreateDebt(
                    veh.citizenid,
                    taxAmount,
                    reason,
                    'IPVA',
                    metadata
                )

                if debtId then
                    -- Atualizar last_ipva_at
                    MySQL.update.await([[
                        UPDATE player_vehicles
                        SET last_ipva_at = NOW()
                        WHERE id = ?
                    ]], {veh.id})

                    DBInt.MarkAsProcessed({
                        source_system = systemName,
                        transaction_id = transactionId,
                        transaction_type = 'ipva_annual',
                        citizenid = veh.citizenid,
                        amount = basePrice,
                        tax_amount = taxAmount,
                        tax_type = 'IPVA',
                        debt_id = debtId,
                        transaction_date = os.date('%Y-%m-%d'),
                        metadata = metadata
                    })

                    processed = processed + 1
                end
            end
        end
    end

    DBInt.Debug(('Processados %d IPVAs'):format(processed))
    return processed
end

--- Processa compras de propriedades (IPTU) - ESTRUTURA REAL
function DBInt.ProcessPropertyPurchases()
    local systemName = 'properties'
    DBInt.Debug('Iniciando processamento de propriedades...')

    local processed = 0

    -- ESTRUTURA REAL: properties (do tiao_properties)
    -- Campos: id, address, label, type, owner_citizenid, price
    local properties = MySQL.query.await([[
        SELECT
            id,
            owner_citizenid as citizenid,
            address,
            label,
            price
        FROM properties
        WHERE owner_citizenid IS NOT NULL
            AND owner_citizenid != ''
            AND price > 0
        LIMIT ?
    ]], {DBInt.Config.BatchSize})

    if not properties or #properties == 0 then
        DBInt.Debug('Nenhuma propriedade encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d propriedades para IPTU'):format(#properties))

    for _, prop in ipairs(properties) do
        local transactionId = 'iptu_' .. prop.id

        -- Verificar se já cobrou IPTU este mês
        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Calcular IPTU (0.3%)
            local taxRate = 0.3
            local taxAmount = math.floor(prop.price * (taxRate / 100))

            if taxAmount > 0 then
                local reason = ('IPTU - Propriedade %s'):format(prop.address or prop.label or prop.id)

                local metadata = {
                    property_id = prop.id,
                    address = prop.address,
                    label = prop.label,
                    price = prop.price,
                    tax_rate = taxRate
                }

                local debtId = DBInt.CreateDebt(
                    prop.citizenid,
                    taxAmount,
                    reason,
                    'IPTU',
                    metadata
                )

                if debtId then
                    DBInt.MarkAsProcessed({
                        source_system = systemName,
                        transaction_id = transactionId,
                        transaction_type = 'iptu_monthly',
                        citizenid = prop.citizenid,
                        amount = prop.price,
                        tax_amount = taxAmount,
                        tax_type = 'IPTU',
                        debt_id = debtId,
                        transaction_date = os.date('%Y-%m-%d'),
                        metadata = metadata
                    })

                    processed = processed + 1
                end
            end
        end
    end

    DBInt.Debug(('Processados %d IPTUs'):format(processed))
    return processed
end

-- ============================================
-- SCHEDULER E INICIALIZAÇÃO
-- ============================================

function DBInt.CheckSystem(systemName)
    local system = DBInt.Config.Systems[systemName]

    if not system or not system.enabled then
        return
    end

    if DBInt.State.running[systemName] then
        DBInt.Debug(('Sistema %s já está em execução, pulando...'):format(systemName))
        return
    end

    DBInt.State.running[systemName] = true

    local success, result = pcall(function()
        if DBInt[system.processor] then
            return DBInt[system.processor]()
        else
            DBInt.Error(('Processador %s não encontrado'):format(system.processor))
            return 0
        end
    end)

    if success then
        DBInt.UpdateStats(systemName, true)
        DBInt.State.stats.totalProcessed = DBInt.State.stats.totalProcessed + (result or 0)

        if not DBInt.State.stats.bySystem[systemName] then
            DBInt.State.stats.bySystem[systemName] = 0
        end
        DBInt.State.stats.bySystem[systemName] = DBInt.State.stats.bySystem[systemName] + (result or 0)
    else
        DBInt.Error(('Erro ao processar sistema %s'):format(systemName), result)
        DBInt.UpdateStats(systemName, false)
        DBInt.State.stats.totalErrors = DBInt.State.stats.totalErrors + 1
    end

    DBInt.State.running[systemName] = false
    DBInt.State.lastCheck[systemName] = os.time()
end

function DBInt.StartSchedulers()
    if not DBInt.Config.Enabled then
        print('[^3SPACE ECONOMY DB-INT^7] Sistema de integração DB DESABILITADO')
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Iniciando schedulers de integração...')

    for systemName, system in pairs(DBInt.Config.Systems) do
        if system.enabled then
            CreateThread(function()
                Wait(10000) -- Aguardar 10 segundos antes de iniciar

                DBInt.Debug(('Scheduler iniciado para %s (intervalo: %dms)'):format(
                    systemName, system.interval
                ))

                while true do
                    DBInt.CheckSystem(systemName)
                    Wait(system.interval)
                end
            end)
        end
    end

    -- Thread de estatísticas
    CreateThread(function()
        Wait(300000) -- 5 minutos

        while true do
            print(('[^2SPACE ECONOMY DB-INT^7] Estatísticas: Processadas=%d, Erros=%d'):format(
                DBInt.State.stats.totalProcessed,
                DBInt.State.stats.totalErrors
            ))

            for system, count in pairs(DBInt.State.stats.bySystem) do
                print(('  - %s: %d transações'):format(system, count))
            end

            Wait(300000)
        end
    end)
end

function DBInt.Initialize()
    if DBInt.State.initialized then
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Inicializando sistema de integração com banco de dados...')

    CreateThread(function()
        Wait(5000)

        local exists = MySQL.scalar.await([[
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
                AND table_name = 'space_economy_processed_transactions'
        ]])

        if not exists or exists == 0 then
            print('[^1SPACE ECONOMY DB-INT^7] ERRO: Tabela space_economy_processed_transactions não encontrada!')
            print('[^1SPACE ECONOMY DB-INT^7] Execute o SQL: sql/db_integrations.sql')
            return
        end

        DBInt.State.initialized = true
        DBInt.StartSchedulers()

        print('[^2SPACE ECONOMY DB-INT^7] Sistema de integração inicializado com sucesso!')
    end)
end

-- ============================================
-- COMANDOS ADMINISTRATIVOS
-- ============================================

RegisterCommand('se:checkintegrations', function(source, args)
    if source ~= 0 then
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Executando verificação manual de todas as integrações...')

    for systemName, _ in pairs(DBInt.Config.Systems) do
        DBInt.CheckSystem(systemName)
    end

    print('[^2SPACE ECONOMY DB-INT^7] Verificação manual concluída!')
end, true)

RegisterCommand('se:dbstats', function(source, args)
    if source ~= 0 then
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] === ESTATÍSTICAS DE INTEGRAÇÃO ===')
    print(('Total Processadas: %d'):format(DBInt.State.stats.totalProcessed))
    print(('Total Erros: %d'):format(DBInt.State.stats.totalErrors))
    print('Por Sistema:')

    for system, count in pairs(DBInt.State.stats.bySystem) do
        local lastCheck = DBInt.State.lastCheck[system]
        local lastCheckStr = lastCheck and os.date('%Y-%m-%d %H:%M:%S', lastCheck) or 'Nunca'
        print(('  - %s: %d transações (última verificação: %s)'):format(system, count, lastCheckStr))
    end
end, true)

-- ============================================
-- AUTO-INICIALIZAÇÃO
-- ============================================
CreateThread(function()
    Wait(1000)
    DBInt.Initialize()
end)

-- Exportar para uso externo
exports('GetDBIntegrationStats', function()
    return DBInt.State.stats
end)

exports('ForceCheckSystem', function(systemName)
    if DBInt.Config.Systems[systemName] then
        DBInt.CheckSystem(systemName)
        return true
    end
    return false
end)

print('[^2SPACE ECONOMY^7] Módulo db_integrations.lua v2.0 carregado (estrutura real do BD)')
