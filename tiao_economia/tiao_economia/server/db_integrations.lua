-- ============================================
-- SPACE ECONOMY - DATABASE DIRECT INTEGRATIONS
-- ============================================
-- Sistema de integração que consulta diretamente os bancos de dados
-- dos recursos externos ao invés de depender de eventos
-- Versão: 3.1.0
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
    BatchSize = 100, -- Processar 100 transações por vez
    MaxRetries = 3,
    DebugMode = true,

    -- Configuração de cada sistema
    Systems = {
        ['ps-banking'] = {
            enabled = true,
            table = 'phone_transactions',
            interval = 60000,
            processor = 'ProcessBankingTransactions'
        },
        ['ox_inventory'] = {
            enabled = true,
            table = 'ox_inventory_transactions',
            interval = 60000,
            processor = 'ProcessInventoryTransactions'
        },
        ['vehicles'] = {
            enabled = true,
            table = 'player_vehicles',
            interval = 120000,
            processor = 'ProcessVehicleTransactions'
        },
        ['housing'] = {
            enabled = true,
            table = 'player_houses',
            interval = 120000,
            processor = 'ProcessHousingTransactions'
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

--- Log de debug
---@param message string
---@param data table|nil
function DBInt.Debug(message, data)
    if DBInt.Config.DebugMode then
        print(('[^3SPACE ECONOMY DB-INT^7] %s'):format(message))
        if data then
            print(json.encode(data, {indent = true}))
        end
    end
end

--- Log de erro
---@param message string
---@param error any
function DBInt.Error(message, error)
    print(('[^1SPACE ECONOMY DB-INT ERROR^7] %s'):format(message))
    if error then
        print(json.encode(error, {indent = true}))
    end
end

--- Verifica se uma transação já foi processada
---@param sourceSystem string
---@param transactionId string
---@return boolean
function DBInt.IsProcessed(sourceSystem, transactionId)
    local result = MySQL.single.await([[
        SELECT COUNT(*) as count
        FROM space_economy_processed_transactions
        WHERE source_system = ? AND transaction_id = ?
    ]], {sourceSystem, transactionId})

    return result and result.count > 0
end

--- Marca uma transação como processada
---@param data table
---@return boolean
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

--- Atualiza estatísticas de integração
---@param sourceSystem string
---@param success boolean
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

--- Cria uma dívida no sistema
---@param citizenid string
---@param amount number
---@param reason string
---@param taxType string
---@param metadata table
---@return number|nil debtId
function DBInt.CreateDebt(citizenid, amount, reason, taxType, metadata)
    if not SE.Debts or not SE.Debts.Upsert then
        DBInt.Error('SE.Debts.Upsert não está disponível')
        return nil
    end

    -- Calcular data de vencimento (7 dias a partir de agora)
    local dueTimestamp = os.time() + (7 * 24 * 60 * 60)

    -- Adicionar tipo de imposto aos metadados
    metadata = metadata or {}
    metadata.tax_type = taxType
    metadata.auto_generated = true
    metadata.source = 'db_integration'

    -- Criar dívida usando o sistema existente
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

--- Processa transações bancárias (IOF)
---@return number processadas
function DBInt.ProcessBankingTransactions()
    local systemName = 'ps-banking'
    DBInt.Debug('Iniciando processamento de transações bancárias...')

    local processed = 0

    -- Buscar última transação processada
    local lastCheck = MySQL.scalar.await([[
        SELECT last_transaction_date
        FROM space_economy_integration_config
        WHERE source_system = ?
    ]], {systemName}) or '2024-01-01 00:00:00'

    -- Consultar novas transações do ps-banking
    -- NOTA: A estrutura exata da tabela pode variar, ajuste conforme necessário
    local transactions = MySQL.query.await([[
        SELECT
            id,
            citizenid,
            type,
            amount,
            receiver,
            created_at
        FROM phone_transactions
        WHERE type IN ('transfer', 'withdraw')
            AND created_at > ?
            AND amount > 0
        ORDER BY created_at ASC
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    if not transactions or #transactions == 0 then
        DBInt.Debug('Nenhuma transação bancária nova encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d transações bancárias para processar'):format(#transactions))

    for _, tx in ipairs(transactions) do
        local transactionId = tostring(tx.id)

        -- Verificar se já foi processada
        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Calcular IOF
            local taxRate = 0.5 -- 0.5%
            local minTax = 10 -- Mínimo $10
            local taxAmount = math.max(math.floor(tx.amount * (taxRate / 100)), minTax)

            -- Criar dívida
            local reason = tx.type == 'transfer'
                and 'IOF - Transferência Bancária'
                or 'IOF - Saque Bancário'

            local metadata = {
                original_amount = tx.amount,
                transaction_type = tx.type,
                receiver = tx.receiver,
                tax_rate = taxRate,
                transaction_date = tx.created_at
            }

            local debtId = DBInt.CreateDebt(
                tx.citizenid,
                taxAmount,
                reason,
                'IOF',
                metadata
            )

            -- Marcar como processada
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
                    transaction_date = tx.created_at,
                    metadata = metadata
                })

                processed = processed + 1
            end
        end
    end

    DBInt.Debug(('Processadas %d transações bancárias'):format(processed))
    return processed
end

--- Processa transações de inventário (ICMS)
---@return number processadas
function DBInt.ProcessInventoryTransactions()
    local systemName = 'ox_inventory'
    DBInt.Debug('Iniciando processamento de transações de inventário...')

    local processed = 0

    -- Lista de itens isentos
    local exemptItems = {
        ['bread'] = true,
        ['water'] = true,
        ['sandwich'] = true
    }

    local lastCheck = MySQL.scalar.await([[
        SELECT last_transaction_date
        FROM space_economy_integration_config
        WHERE source_system = ?
    ]], {systemName}) or '2024-01-01 00:00:00'

    -- Buscar compras em lojas
    -- NOTA: ox_inventory pode armazenar isso de diferentes formas
    -- Esta é uma implementação genérica que precisa ser ajustada
    local transactions = MySQL.query.await([[
        SELECT
            id,
            owner as citizenid,
            item,
            count as quantity,
            price,
            created as created_at
        FROM ox_inventory_transactions
        WHERE type = 'shop_purchase'
            AND created > ?
            AND price > 0
        ORDER BY created ASC
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    if not transactions or #transactions == 0 then
        DBInt.Debug('Nenhuma transação de inventário nova encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d transações de inventário para processar'):format(#transactions))

    for _, tx in ipairs(transactions) do
        local transactionId = tostring(tx.id)

        -- Verificar se já foi processada
        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Verificar se item é isento
            if not exemptItems[tx.item] then
                -- Calcular ICMS (12%)
                local taxRate = 12.0
                local taxAmount = math.floor(tx.price * (taxRate / 100))

                if taxAmount > 0 then
                    local reason = ('ICMS - Compra de %dx %s'):format(tx.quantity or 1, tx.item)

                    local metadata = {
                        item = tx.item,
                        quantity = tx.quantity,
                        price = tx.price,
                        tax_rate = taxRate,
                        transaction_date = tx.created_at
                    }

                    local debtId = DBInt.CreateDebt(
                        tx.citizenid,
                        taxAmount,
                        reason,
                        'ICMS',
                        metadata
                    )

                    if debtId then
                        DBInt.MarkAsProcessed({
                            source_system = systemName,
                            transaction_id = transactionId,
                            transaction_type = 'shop_purchase',
                            citizenid = tx.citizenid,
                            amount = tx.price,
                            tax_amount = taxAmount,
                            tax_type = 'ICMS',
                            debt_id = debtId,
                            transaction_date = tx.created_at,
                            metadata = metadata
                        })

                        processed = processed + 1
                    end
                end
            end
        end
    end

    DBInt.Debug(('Processadas %d transações de inventário'):format(processed))
    return processed
end

--- Processa compras de veículos (IPVA)
---@return number processadas
function DBInt.ProcessVehicleTransactions()
    local systemName = 'vehicles'
    DBInt.Debug('Iniciando processamento de compras de veículos...')

    local processed = 0

    local lastCheck = MySQL.scalar.await([[
        SELECT last_transaction_date
        FROM space_economy_integration_config
        WHERE source_system = ?
    ]], {systemName}) or '2024-01-01 00:00:00'

    -- Buscar veículos comprados recentemente
    local vehicles = MySQL.query.await([[
        SELECT
            id,
            citizenid,
            vehicle,
            plate,
            price,
            created_at
        FROM player_vehicles
        WHERE created_at > ?
            AND price > 0
        ORDER BY created_at ASC
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    if not vehicles or #vehicles == 0 then
        DBInt.Debug('Nenhuma compra de veículo nova encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d compras de veículos para processar'):format(#vehicles))

    for _, veh in ipairs(vehicles) do
        local transactionId = tostring(veh.id)

        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Calcular IPVA (1.5%)
            local taxRate = 1.5
            local taxAmount = math.floor(veh.price * (taxRate / 100))

            if taxAmount > 0 then
                local reason = ('IPVA - Veículo %s (%s)'):format(veh.vehicle or 'Desconhecido', veh.plate)

                local metadata = {
                    vehicle = veh.vehicle,
                    plate = veh.plate,
                    price = veh.price,
                    tax_rate = taxRate,
                    transaction_date = veh.created_at
                }

                local debtId = DBInt.CreateDebt(
                    veh.citizenid,
                    taxAmount,
                    reason,
                    'IPVA',
                    metadata
                )

                if debtId then
                    DBInt.MarkAsProcessed({
                        source_system = systemName,
                        transaction_id = transactionId,
                        transaction_type = 'vehicle_purchase',
                        citizenid = veh.citizenid,
                        amount = veh.price,
                        tax_amount = taxAmount,
                        tax_type = 'IPVA',
                        debt_id = debtId,
                        transaction_date = veh.created_at,
                        metadata = metadata
                    })

                    processed = processed + 1
                end
            end
        end
    end

    DBInt.Debug(('Processadas %d compras de veículos'):format(processed))
    return processed
end

--- Processa compras de propriedades (IPTU)
---@return number processadas
function DBInt.ProcessHousingTransactions()
    local systemName = 'housing'
    DBInt.Debug('Iniciando processamento de compras de propriedades...')

    local processed = 0

    local lastCheck = MySQL.scalar.await([[
        SELECT last_transaction_date
        FROM space_economy_integration_config
        WHERE source_system = ?
    ]], {systemName}) or '2024-01-01 00:00:00'

    -- Buscar propriedades compradas recentemente
    local properties = MySQL.query.await([[
        SELECT
            id,
            citizenid,
            house,
            price,
            created_at
        FROM player_houses
        WHERE created_at > ?
            AND price > 0
        ORDER BY created_at ASC
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    if not properties or #properties == 0 then
        DBInt.Debug('Nenhuma compra de propriedade nova encontrada')
        return 0
    end

    DBInt.Debug(('Encontradas %d compras de propriedades para processar'):format(#properties))

    for _, prop in ipairs(properties) do
        local transactionId = tostring(prop.id)

        if not DBInt.IsProcessed(systemName, transactionId) then
            -- Calcular IPTU (0.3%)
            local taxRate = 0.3
            local taxAmount = math.floor(prop.price * (taxRate / 100))

            if taxAmount > 0 then
                local reason = ('IPTU - Propriedade %s'):format(prop.house or 'Desconhecida')

                local metadata = {
                    house = prop.house,
                    price = prop.price,
                    tax_rate = taxRate,
                    transaction_date = prop.created_at
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
                        transaction_type = 'property_purchase',
                        citizenid = prop.citizenid,
                        amount = prop.price,
                        tax_amount = taxAmount,
                        tax_type = 'IPTU',
                        debt_id = debtId,
                        transaction_date = prop.created_at,
                        metadata = metadata
                    })

                    processed = processed + 1
                end
            end
        end
    end

    DBInt.Debug(('Processadas %d compras de propriedades'):format(processed))
    return processed
end

-- ============================================
-- SCHEDULER E INICIALIZAÇÃO
-- ============================================

--- Executa verificação de um sistema específico
---@param systemName string
function DBInt.CheckSystem(systemName)
    local system = DBInt.Config.Systems[systemName]

    if not system or not system.enabled then
        return
    end

    -- Evitar execução simultânea
    if DBInt.State.running[systemName] then
        DBInt.Debug(('Sistema %s já está em execução, pulando...'):format(systemName))
        return
    end

    DBInt.State.running[systemName] = true

    -- Executar processador
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

--- Inicia todos os schedulers
function DBInt.StartSchedulers()
    if not DBInt.Config.Enabled then
        print('[^3SPACE ECONOMY DB-INT^7] Sistema de integração DB DESABILITADO')
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Iniciando schedulers de integração...')

    for systemName, system in pairs(DBInt.Config.Systems) do
        if system.enabled then
            -- Criar thread para cada sistema
            CreateThread(function()
                -- Aguardar 10 segundos antes de iniciar
                Wait(10000)

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

            Wait(300000) -- A cada 5 minutos
        end
    end)
end

--- Inicializa o sistema de integração
function DBInt.Initialize()
    if DBInt.State.initialized then
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Inicializando sistema de integração com banco de dados...')

    -- Verificar se as tabelas existem
    CreateThread(function()
        Wait(5000) -- Aguardar banco de dados carregar

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

--- Comando para forçar verificação manual
RegisterCommand('se:checkintegrations', function(source, args)
    if source ~= 0 then
        -- Apenas console pode executar
        return
    end

    print('[^2SPACE ECONOMY DB-INT^7] Executando verificação manual de todas as integrações...')

    for systemName, _ in pairs(DBInt.Config.Systems) do
        DBInt.CheckSystem(systemName)
    end

    print('[^2SPACE ECONOMY DB-INT^7] Verificação manual concluída!')
end, true)

--- Comando para ver estatísticas
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

print('[^2SPACE ECONOMY^7] Módulo db_integrations.lua carregado')
