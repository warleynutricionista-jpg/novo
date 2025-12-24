--============================================================
-- space_economy - server/metrics.lua
-- Dashboard de Métricas em Tempo Real
-- MELHORIA IMPORTANTE #1 - Gestão +200%
--============================================================
SE = SE or {}
SE.Metrics = SE.Metrics or {}

local U = SE.Util

--============================================================
-- Cache de métricas (atualizado periodicamente)
--============================================================
local MetricsCache = {
    lastUpdate = 0,
    cacheTTL = 60, -- 60 segundos
    data = {}
}

--============================================================
-- Funções de Coleta
--============================================================

-- Arrecadação últimos 7 dias
function SE.Metrics.GetWeeklyRevenue()
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT DATE(timestamp) as date,
                   SUM(amount) as total
            FROM space_economy_logs
            WHERE category = 'tax'
              AND amount > 0
              AND timestamp >= DATE_SUB(NOW(), INTERVAL 7 DAY)
            GROUP BY DATE(timestamp)
            ORDER BY date ASC
        ]])
    end)

    if not ok or not rows then return {} end
    return rows
end

-- Top 10 devedores
function SE.Metrics.GetTopDebtors()
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT citizenid,
                   SUM(amount) as total_debt,
                   COUNT(*) as debt_count
            FROM space_economy_debts
            WHERE status = 'active'
            GROUP BY citizenid
            ORDER BY total_debt DESC
            LIMIT 10
        ]])
    end)

    if not ok or not rows then return {} end

    -- Enriquecer com nomes
    for i, row in ipairs(rows) do
        local name = 'Desconhecido'
        if SE.CharCache and SE.CharCache.GetName then
            name = SE.CharCache.GetName(row.citizenid) or name
        end
        rows[i].playerName = name
    end

    return rows
end

-- IPTU/IPVA pagos no mês
function SE.Metrics.GetMonthlyTaxes()
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                SUM(CASE WHEN (message LIKE '%IPTU%' OR reason LIKE '%IPTU%') THEN amount ELSE 0 END) as iptu_total,
                SUM(CASE WHEN (message LIKE '%IPVA%' OR reason LIKE '%IPVA%') THEN amount ELSE 0 END) as ipva_total,
                SUM(CASE WHEN (message NOT LIKE '%IPTU%' AND message NOT LIKE '%IPVA%') THEN amount ELSE 0 END) as other_total,
                COUNT(*) as transactions
            FROM space_economy_logs
            WHERE category = 'tax'
              AND timestamp >= DATE_FORMAT(NOW(), '%Y-%m-01 00:00:00')
        ]])
    end)

    if not ok or not row then
        return {
            iptu_total = 0,
            ipva_total = 0,
            other_total = 0,
            transactions = 0
        }
    end

    return {
        iptu_total = U.toInt(row.iptu_total, 0),
        ipva_total = U.toInt(row.ipva_total, 0),
        other_total = U.toInt(row.other_total, 0),
        transactions = U.toInt(row.transactions, 0),
    }
end

-- Métricas do dia atual
function SE.Metrics.GetTodayMetrics()
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                SUM(CASE WHEN category = 'tax' AND amount > 0 THEN amount ELSE 0 END) as collected,
                SUM(CASE WHEN category = 'debt' AND message LIKE '%pago%' THEN amount ELSE 0 END) as paid_debts,
                COUNT(*) as transactions
            FROM space_economy_logs
            WHERE DATE(timestamp) = CURDATE()
        ]])
    end)

    if not ok or not row then
        return {
            collected = 0,
            paid_debts = 0,
            transactions = 0
        }
    end

    return {
        collected = U.toInt(row.collected, 0),
        paid_debts = U.toInt(row.paid_debts, 0),
        transactions = U.toInt(row.transactions, 0),
    }
end

-- Estatísticas de empréstimos (se existir)
function SE.Metrics.GetLoanStats()
    -- Verificar se tabela existe
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                COUNT(*) as total_loans,
                SUM(CASE WHEN status = 'active' THEN amount ELSE 0 END) as active_amount,
                SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active_count,
                AVG(interest_rate) as avg_rate
            FROM space_economy_loans
        ]])
    end)

    if not ok or not row then
        return {
            total_loans = 0,
            active_amount = 0,
            active_count = 0,
            avg_rate = 0
        }
    end

    return {
        total_loans = U.toInt(row.total_loans, 0),
        active_amount = U.toInt(row.active_amount, 0),
        active_count = U.toInt(row.active_count, 0),
        avg_rate = U.toNumber(row.avg_rate, 0),
    }
end

-- Estatísticas de parcelamentos
function SE.Metrics.GetInstallmentStats()
    -- Será implementado quando installments.lua estiver pronto
    return {
        total_plans = 0,
        active_plans = 0,
        total_amount = 0,
    }
end

--============================================================
-- Dashboard Completo
--============================================================
function SE.Metrics.GetDashboardData()
    -- Verificar cache
    local now = os.time()
    if (now - MetricsCache.lastUpdate) < MetricsCache.cacheTTL and MetricsCache.data then
        return MetricsCache.data
    end

    -- Coletar dados
    local dashboard = {
        weeklyRevenue = SE.Metrics.GetWeeklyRevenue(),
        topDebtors = SE.Metrics.GetTopDebtors(),
        monthlyTaxes = SE.Metrics.GetMonthlyTaxes(),
        todayMetrics = SE.Metrics.GetTodayMetrics(),
        loanStats = SE.Metrics.GetLoanStats(),
        installmentStats = SE.Metrics.GetInstallmentStats(),

        -- Métricas gerais
        general = {
            vault = (SE.State and U.toInt(SE.State.vaultBalance, 0)) or 0,
            inflation = (SE.State and U.toNumber(SE.State.inflationRate, 1.0)) or 1.0,
            taxMultiplier = (SE.State and U.toNumber(SE.State.taxMultiplier, 1.0)) or 1.0,
        },

        timestamp = now
    }

    -- Atualizar cache
    MetricsCache.data = dashboard
    MetricsCache.lastUpdate = now

    return dashboard
end

--============================================================
-- Exportar para CSV (opcional)
--============================================================
function SE.Metrics.ExportToCSV(dataType)
    -- Implementação futura
    -- Retornar string CSV para download
    return "Not implemented yet"
end

--============================================================
-- Event para NUI solicitar dashboard
--============================================================
RegisterNetEvent('space_economy:server_getDashboardMetrics', function()
    local src = source

    -- Verificar permissão
    if SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            return
        end
    end

    local dashboard = SE.Metrics.GetDashboardData()

    TriggerClientEvent('space_economy:client_dashboardMetrics', src, dashboard)
end)

--============================================================
-- Atualização periódica do cache
--============================================================
CreateThread(function()
    Wait(120000) -- 2 minutos

    while true do
        -- Atualizar cache a cada 1 minuto
        Wait(60000)

        -- Forçar atualização
        MetricsCache.lastUpdate = 0
        SE.Metrics.GetDashboardData()
    end
end)

--============================================================
-- Exports
--============================================================
exports('GetDashboardData', SE.Metrics.GetDashboardData)
exports('GetWeeklyRevenue', SE.Metrics.GetWeeklyRevenue)
exports('GetTopDebtors', SE.Metrics.GetTopDebtors)

print('^2[space_economy]^7 Metrics system loaded - Cache TTL: %ds'):format(MetricsCache.cacheTTL)
