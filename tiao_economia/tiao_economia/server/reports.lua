--============================================================
-- space_economy - server/reports.lua (NOVO)
-- Sistema de relatórios e analytics econômicos
--============================================================
SE = SE or {}
SE.Reports = SE.Reports or {}

local U = SE.Util

--============================================================
-- MÉTRICAS DIÁRIAS
--============================================================
local function ensureDailyMetrics()
  if not MySQL then return end
  
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_daily_metrics (
      id INT AUTO_INCREMENT PRIMARY KEY,
      date DATE NOT NULL UNIQUE,
      vault_balance BIGINT NOT NULL DEFAULT 0,
      total_collected BIGINT NOT NULL DEFAULT 0,
      total_debts BIGINT NOT NULL DEFAULT 0,
      active_debtors INT NOT NULL DEFAULT 0,
      transactions_count INT NOT NULL DEFAULT 0,
      avg_transaction BIGINT NOT NULL DEFAULT 0,
      inflation_rate DECIMAL(10,4) NOT NULL DEFAULT 1.0,
      tax_multiplier DECIMAL(10,4) NOT NULL DEFAULT 1.0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_date (date)
    )
  ]])
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureDailyMetrics()
end)

-- Snapshot diário (executar à meia-noite ou a cada 24h)
function SE.Reports.CreateDailySnapshot()
  ensureDailyMetrics()
  
  local today = os.date('%Y-%m-%d')
  
  -- Busca métricas atuais
  local vault = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or 0
  
  local debtStats = MySQL.single.await([[
    SELECT 
      COALESCE(SUM(amount), 0) as total,
      COUNT(DISTINCT citizenid) as debtors
    FROM space_economy_debts
    WHERE status = 'active'
  ]]) or {}
  
  local todayStats = MySQL.single.await([[
    SELECT 
      COUNT(*) as tx_count,
      COALESCE(SUM(amount), 0) as collected
    FROM space_economy_debt_payments
    WHERE DATE(paid_at) = ?
  ]], {today}) or {}
  
  local avgTx = (todayStats.tx_count or 0) > 0 
    and math.floor((todayStats.collected or 0) / todayStats.tx_count) 
    or 0
  
  -- Insere snapshot
  MySQL.insert.await([[
    INSERT INTO space_economy_daily_metrics 
      (date, vault_balance, total_collected, total_debts, active_debtors, 
       transactions_count, avg_transaction, inflation_rate, tax_multiplier)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      vault_balance = VALUES(vault_balance),
      total_collected = VALUES(total_collected),
      total_debts = VALUES(total_debts),
      active_debtors = VALUES(active_debtors),
      transactions_count = VALUES(transactions_count),
      avg_transaction = VALUES(avg_transaction),
      inflation_rate = VALUES(inflation_rate),
      tax_multiplier = VALUES(tax_multiplier)
  ]], {
    today,
    vault,
    todayStats.collected or 0,
    debtStats.total or 0,
    debtStats.debtors or 0,
    todayStats.tx_count or 0,
    avgTx,
    SE.State.inflationRate or 1.0,
    SE.State.taxMultiplier or 1.0,
  })
  
  if U and U.dbg then
    U.dbg(('Snapshot diário criado: %s'):format(today))
  end
  
  return true
end

-- Thread para snapshot automático (executa à meia-noite)
CreateThread(function()
  while not MySQL do Wait(1000) end
  
  while true do
    local now = os.time()
    local nextMidnight = os.time({
      year = os.date('%Y', now),
      month = os.date('%m', now),
      day = os.date('%d', now),
      hour = 0, min = 0, sec = 0
    }) + 86400 -- próxima meia-noite
    
    local waitMs = (nextMidnight - now) * 1000
    if waitMs < 0 then waitMs = 1000 end
    
    Wait(waitMs)
    SE.Reports.CreateDailySnapshot()
  end
end)

--============================================================
-- RELATÓRIOS
--============================================================

-- Relatório de arrecadação (últimos X dias)
function SE.Reports.CollectionReport(days)
  ensureDailyMetrics()
  days = U.toInt(days or 7, 7)
  
  local rows = MySQL.query.await([[
    SELECT date, total_collected, transactions_count, avg_transaction
    FROM space_economy_daily_metrics
    WHERE date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
    ORDER BY date DESC
  ]], {days}) or {}
  
  return rows
end

-- Relatório de inadimplência
function SE.Reports.DebtReport()
  ensureDailyMetrics()
  
  local summary = MySQL.single.await([[
    SELECT 
      COUNT(*) as total_debts,
      COUNT(DISTINCT citizenid) as unique_debtors,
      COALESCE(SUM(amount), 0) as total_owed,
      COALESCE(AVG(amount), 0) as avg_debt,
      COALESCE(MIN(amount), 0) as min_debt,
      COALESCE(MAX(amount), 0) as max_debt
    FROM space_economy_debts
    WHERE status = 'active'
  ]]) or {}
  
  local byReason = MySQL.query.await([[
    SELECT 
      reason, 
      COUNT(*) as count, 
      COALESCE(SUM(amount), 0) as total
    FROM space_economy_debts
    WHERE status = 'active'
    GROUP BY reason
    ORDER BY total DESC
    LIMIT 10
  ]]) or {}
  
  local overdue = MySQL.query.await([[
    SELECT 
      citizenid,
      COALESCE(c.name, 'Desconhecido') as playerName,
      amount,
      reason,
      due_at,
      DATEDIFF(NOW(), due_at) as days_overdue
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE status = 'active' AND due_at < NOW()
    ORDER BY days_overdue DESC, amount DESC
    LIMIT 20
  ]]) or {}
  
  return {
    summary = summary,
    byReason = byReason,
    overdue = overdue,
  }
end

-- Top contribuintes (quem mais pagou)
function SE.Reports.TopContributors(limit, days)
  limit = U.toInt(limit or 10, 10)
  days = U.toInt(days or 30, 30)
  
  local rows = MySQL.query.await([[
    SELECT 
      p.citizenid,
      COALESCE(c.name, 'Desconhecido') as playerName,
      COUNT(*) as payment_count,
      COALESCE(SUM(p.amount), 0) as total_paid
    FROM space_economy_debt_payments p
    LEFT JOIN space_economy_charcache c ON c.citizenid = p.citizenid
    WHERE p.paid_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
    GROUP BY p.citizenid
    ORDER BY total_paid DESC
    LIMIT ?
  ]], {days, limit}) or {}
  
  return rows
end

-- Top inadimplentes
function SE.Reports.TopDebtors(limit)
  limit = U.toInt(limit or 10, 10)
  
  local rows = MySQL.query.await([[
    SELECT 
      d.citizenid,
      COALESCE(c.name, 'Desconhecido') as playerName,
      COUNT(*) as debt_count,
      COALESCE(SUM(d.amount), 0) as total_owed
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.status = 'active'
    GROUP BY d.citizenid
    ORDER BY total_owed DESC
    LIMIT ?
  ]], {limit}) or {}
  
  return rows
end

-- Dashboard completo (métricas + tendências)
function SE.Reports.Dashboard()
  local vault = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or 0
  
  local today = MySQL.single.await([[
    SELECT total_collected, transactions_count
    FROM space_economy_daily_metrics
    WHERE date = CURDATE()
    LIMIT 1
  ]]) or {}
  
  local yesterday = MySQL.single.await([[
    SELECT total_collected
    FROM space_economy_daily_metrics
    WHERE date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    LIMIT 1
  ]]) or {}
  
  local debtSummary = MySQL.single.await([[
    SELECT 
      COALESCE(SUM(amount), 0) as total,
      COUNT(DISTINCT citizenid) as debtors
    FROM space_economy_debts
    WHERE status = 'active'
  ]]) or {}
  
  local week = SE.Reports.CollectionReport(7)
  
  return {
    vault = vault,
    inflation = SE.State.inflationRate or 1.0,
    taxMultiplier = SE.State.taxMultiplier or 1.0,
    today = {
      collected = U.toInt(today.total_collected, 0),
      transactions = U.toInt(today.transactions_count, 0),
    },
    yesterday = {
      collected = U.toInt(yesterday.total_collected, 0),
    },
    debts = {
      total = U.toInt(debtSummary.total, 0),
      debtors = U.toInt(debtSummary.debtors, 0),
    },
    week = week,
  }
end

--============================================================
-- EXPORT DE RELATÓRIOS (CSV/JSON)
--============================================================
function SE.Reports.ExportCSV(reportType, params)
  -- Implementar exports futuros
  return nil, 'not_implemented'
end

--============================================================
-- COMANDOS ADMIN
--============================================================
RegisterCommand('eco_snapshot', function(source)
  if not SE.Admin.IsAllowed(source) then return end
  SE.Reports.CreateDailySnapshot()
  TriggerClientEvent('chat:addMessage', source, {
    args = {'[Economia]', 'Snapshot diário criado com sucesso'}
  })
end, false)

RegisterCommand('eco_report', function(source, args)
  if not SE.Admin.IsAllowed(source) then return end
  
  local reportType = args[1] or 'dashboard'
  local data = nil
  
  if reportType == 'dashboard' then
    data = SE.Reports.Dashboard()
  elseif reportType == 'debt' then
    data = SE.Reports.DebtReport()
  elseif reportType == 'top' then
    data = SE.Reports.TopContributors(10, 30)
  elseif reportType == 'debtors' then
    data = SE.Reports.TopDebtors(10)
  end
  
  if data then
    print(U.safeJsonEncode(data))
    TriggerClientEvent('chat:addMessage', source, {
      args = {'[Economia]', 'Relatório gerado (veja console F8)'}
    })
  end
end, false)