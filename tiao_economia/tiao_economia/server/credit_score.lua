--============================================================
-- space_economy - server/credit_score.lua (NOVO)
-- Sistema de pontuação de crédito (score 0-1000)
--============================================================
SE = SE or {}
SE.CreditScore = SE.CreditScore or {}

local U = SE.Util
local B = SE.Bridge

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[credit_score]^7', ...) end 
end

--============================================================
-- CONFIGURAÇÃO DO SISTEMA DE SCORE
--============================================================
local SCORE_CONFIG = {
  -- Pesos dos fatores (total = 100%)
  WEIGHTS = {
    payment_history = 0.35,    -- 35% - Histórico de pagamento
    debt_ratio = 0.30,         -- 30% - Relação dívida/renda estimada
    credit_age = 0.15,         -- 15% - Tempo de histórico
    credit_mix = 0.10,         -- 10% - Diversidade de crédito
    recent_activity = 0.10,    -- 10% - Atividade recente
  },
  
  -- Faixas de classificação
  RATINGS = {
    { min = 850, max = 1000, label = 'Excelente', color = 'green' },
    { min = 740, max = 849,  label = 'Muito Bom', color = 'lightgreen' },
    { min = 670, max = 739,  label = 'Bom', color = 'yellow' },
    { min = 580, max = 669,  label = 'Regular', color = 'orange' },
    { min = 300, max = 579,  label = 'Ruim', color = 'red' },
    { min = 0,   max = 299,  label = 'Péssimo', color = 'darkred' },
  },
  
  -- Penalidades
  PENALTIES = {
    overdue_payment = -50,      -- Por pagamento atrasado
    defaulted_debt = -150,      -- Por dívida não paga
    bankruptcy = -300,          -- Por falência
  },
  
  -- Bônus
  BONUSES = {
    on_time_payment = 10,       -- Por pagamento em dia
    early_payment = 15,         -- Por pagamento antecipado
    full_installment = 25,      -- Por quitação de parcelamento
  }
}

--============================================================
-- SCHEMA
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Tabela principal de scores
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_credit_scores (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL UNIQUE,
      score INT NOT NULL DEFAULT 500,
      rating VARCHAR(20) NOT NULL DEFAULT 'Regular',
      payment_history_score DECIMAL(5,2) NOT NULL DEFAULT 0,
      debt_ratio_score DECIMAL(5,2) NOT NULL DEFAULT 0,
      credit_age_score DECIMAL(5,2) NOT NULL DEFAULT 0,
      credit_mix_score DECIMAL(5,2) NOT NULL DEFAULT 0,
      recent_activity_score DECIMAL(5,2) NOT NULL DEFAULT 0,
      total_payments INT NOT NULL DEFAULT 0,
      on_time_payments INT NOT NULL DEFAULT 0,
      late_payments INT NOT NULL DEFAULT 0,
      total_borrowed BIGINT NOT NULL DEFAULT 0,
      total_paid BIGINT NOT NULL DEFAULT 0,
      active_debts INT NOT NULL DEFAULT 0,
      credit_age_days INT NOT NULL DEFAULT 0,
      last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      meta LONGTEXT NULL,
      INDEX idx_score (score),
      INDEX idx_rating (rating)
    )
  ]])

  -- Histórico de mudanças de score
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_score_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      old_score INT NOT NULL,
      new_score INT NOT NULL,
      change_reason VARCHAR(200) NOT NULL,
      event_type VARCHAR(50) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_citizen (citizenid),
      INDEX idx_date (created_at)
    )
  ]])

  dbg('Schema de credit score garantido')
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
end)

--============================================================
-- CÁLCULO DE SCORE
--============================================================

-- Calcula score de histórico de pagamento (0-350)
local function calculatePaymentHistory(data)
  local total = U.toInt(data.total_payments, 0)
  if total == 0 then return 0 end
  
  local onTime = U.toInt(data.on_time_payments, 0)
  local late = U.toInt(data.late_payments, 0)
  
  local ratio = onTime / total
  local base = ratio * 350
  
  -- Penalidade por atrasos
  local penalty = late * 15
  
  return math.max(0, math.min(350, base - penalty))
end

-- Calcula score de relação dívida/renda (0-300)
local function calculateDebtRatio(data)
  -- Estimativa: assume renda baseada em atividade econômica
  local totalPaid = U.toInt(data.total_paid, 0)
  local activeDebts = U.toInt(data.active_debts, 0)
  local totalBorrowed = U.toInt(data.total_borrowed, 0)
  
  if totalPaid == 0 and activeDebts == 0 then
    return 150 -- Neutro
  end
  
  -- Renda estimada mensal (baseado em pagamentos)
  local estimatedIncome = math.max(5000, totalPaid / 12) -- Mínimo 5k/mês
  
  -- Dívida ativa vs renda
  local debtRatio = activeDebts > 0 and (totalBorrowed / estimatedIncome) or 0
  
  if debtRatio <= 0.2 then return 300 end      -- Excelente
  if debtRatio <= 0.35 then return 250 end     -- Muito bom
  if debtRatio <= 0.50 then return 200 end     -- Bom
  if debtRatio <= 0.75 then return 150 end     -- Regular
  return math.max(0, 100 - (debtRatio * 50))  -- Ruim
end

-- Calcula score de idade do crédito (0-150)
local function calculateCreditAge(data)
  local days = U.toInt(data.credit_age_days, 0)
  
  if days >= 365 * 3 then return 150 end      -- 3+ anos
  if days >= 365 * 2 then return 120 end      -- 2+ anos
  if days >= 365 then return 90 end           -- 1+ ano
  if days >= 180 then return 60 end           -- 6+ meses
  if days >= 90 then return 30 end            -- 3+ meses
  return math.min(30, days / 3)               -- Proporcional
end

-- Calcula score de mix de crédito (0-100)
local function calculateCreditMix(citizenid)
  -- Verifica tipos de crédito utilizados
  local types = {}
  
  -- Dívidas
  local debts = MySQL.query.await([[
    SELECT DISTINCT reason FROM space_economy_debts
    WHERE citizenid = ? AND status IN ('active', 'paid')
    LIMIT 10
  ]], {citizenid}) or {}
  
  for _, d in ipairs(debts) do
    types[d.reason] = true
  end
  
  -- Empréstimos (se existir)
  if SE.Loans then
    local loans = MySQL.query.await([[
      SELECT COUNT(*) as cnt FROM space_economy_loans
      WHERE citizenid = ?
    ]], {citizenid})
    if loans and loans[1] and U.toInt(loans[1].cnt, 0) > 0 then
      types['loan'] = true
    end
  end
  
  local diversity = 0
  for _ in pairs(types) do diversity = diversity + 1 end
  
  if diversity >= 4 then return 100 end
  if diversity >= 3 then return 75 end
  if diversity >= 2 then return 50 end
  if diversity >= 1 then return 25 end
  return 0
end

-- Calcula score de atividade recente (0-100)
local function calculateRecentActivity(citizenid)
  -- Atividade nos últimos 90 dias
  local recent = MySQL.single.await([[
    SELECT 
      COUNT(*) as payments,
      COALESCE(SUM(amount), 0) as total
    FROM space_economy_debt_payments
    WHERE citizenid = ? AND paid_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
  ]], {citizenid}) or {}
  
  local payments = U.toInt(recent.payments, 0)
  
  if payments >= 5 then return 100 end
  if payments >= 3 then return 75 end
  if payments >= 1 then return 50 end
  return 0
end

-- Calcula score completo
function SE.CreditScore.Calculate(citizenid)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return nil end
  
  -- Busca dados do cidadão
  local data = MySQL.single.await([[
    SELECT * FROM space_economy_credit_scores
    WHERE citizenid = ?
    LIMIT 1
  ]], {citizenid})
  
  if not data then
    -- Cria registro inicial
    MySQL.insert.await([[
      INSERT INTO space_economy_credit_scores 
        (citizenid, score, rating, credit_age_days)
      VALUES (?, 500, 'Regular', 0)
    ]], {citizenid})
    
    data = {
      citizenid = citizenid,
      total_payments = 0,
      on_time_payments = 0,
      late_payments = 0,
      total_borrowed = 0,
      total_paid = 0,
      active_debts = 0,
      credit_age_days = 0,
    }
  end
  
  -- Calcula componentes
  local paymentHistory = calculatePaymentHistory(data)
  local debtRatio = calculateDebtRatio(data)
  local creditAge = calculateCreditAge(data)
  local creditMix = calculateCreditMix(citizenid)
  local recentActivity = calculateRecentActivity(citizenid)
  
  -- Score total
  local totalScore = math.floor(
    paymentHistory + 
    debtRatio + 
    creditAge + 
    creditMix + 
    recentActivity
  )
  
  totalScore = math.max(0, math.min(1000, totalScore))
  
  -- Determina rating
  local rating = 'Regular'
  for _, r in ipairs(SCORE_CONFIG.RATINGS) do
    if totalScore >= r.min and totalScore <= r.max then
      rating = r.label
      break
    end
  end
  
  return {
    score = totalScore,
    rating = rating,
    components = {
      payment_history = paymentHistory,
      debt_ratio = debtRatio,
      credit_age = creditAge,
      credit_mix = creditMix,
      recent_activity = recentActivity,
    }
  }
end

-- Atualiza score do cidadão
function SE.CreditScore.Update(citizenid, reason, eventType)
  ensureSchema()
  
  local result = SE.CreditScore.Calculate(citizenid)
  if not result then return false end
  
  -- Busca score anterior
  local old = MySQL.single.await([[
    SELECT score FROM space_economy_credit_scores
    WHERE citizenid = ?
    LIMIT 1
  ]], {citizenid}) or {}
  
  local oldScore = U.toInt(old.score, 500)
  
  -- Atualiza
  MySQL.update.await([[
    UPDATE space_economy_credit_scores
    SET score = ?,
        rating = ?,
        payment_history_score = ?,
        debt_ratio_score = ?,
        credit_age_score = ?,
        credit_mix_score = ?,
        recent_activity_score = ?
    WHERE citizenid = ?
  ]], {
    result.score,
    result.rating,
    result.components.payment_history,
    result.components.debt_ratio,
    result.components.credit_age,
    result.components.credit_mix,
    result.components.recent_activity,
    citizenid
  })
  
  -- Registra histórico se mudou significativamente
  if math.abs(result.score - oldScore) >= 5 then
    MySQL.insert.await([[
      INSERT INTO space_economy_score_history
        (citizenid, old_score, new_score, change_reason, event_type)
      VALUES (?, ?, ?, ?, ?)
    ]], {
      citizenid,
      oldScore,
      result.score,
      reason or 'Recalculo automático',
      eventType or 'update'
    })
  end
  
  dbg(('Score atualizado: %s | %d -> %d (%s)'):format(citizenid, oldScore, result.score, result.rating))
  
  return true, result
end

-- Busca score
function SE.CreditScore.Get(citizenid)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return nil end
  
  local data = MySQL.single.await([[
    SELECT * FROM space_economy_credit_scores
    WHERE citizenid = ?
    LIMIT 1
  ]], {citizenid})
  
  if not data then
    SE.CreditScore.Update(citizenid, 'Criação inicial', 'create')
    return SE.CreditScore.Get(citizenid)
  end
  
  return data
end

-- Registra evento que afeta score
function SE.CreditScore.RecordEvent(citizenid, eventType, details)
  ensureSchema()
  
  local bonus = 0
  local penalty = 0
  
  if eventType == 'payment_on_time' then
    bonus = SCORE_CONFIG.BONUSES.on_time_payment
    MySQL.update.await([[
      UPDATE space_economy_credit_scores
      SET on_time_payments = on_time_payments + 1,
          total_payments = total_payments + 1,
          total_paid = total_paid + ?
      WHERE citizenid = ?
    ]], {U.toInt(details.amount, 0), citizenid})
    
  elseif eventType == 'payment_late' then
    penalty = SCORE_CONFIG.PENALTIES.overdue_payment
    MySQL.update.await([[
      UPDATE space_economy_credit_scores
      SET late_payments = late_payments + 1,
          total_payments = total_payments + 1,
          total_paid = total_paid + ?
      WHERE citizenid = ?
    ]], {U.toInt(details.amount, 0), citizenid})
    
  elseif eventType == 'debt_created' then
    MySQL.update.await([[
      UPDATE space_economy_credit_scores
      SET active_debts = active_debts + 1,
          total_borrowed = total_borrowed + ?
      WHERE citizenid = ?
    ]], {U.toInt(details.amount, 0), citizenid})
    
  elseif eventType == 'debt_paid' then
    bonus = SCORE_CONFIG.BONUSES.full_installment
    MySQL.update.await([[
      UPDATE space_economy_credit_scores
      SET active_debts = GREATEST(0, active_debts - 1)
      WHERE citizenid = ?
    ]], {citizenid})
  end
  
  -- Atualiza score
  Wait(100)
  SE.CreditScore.Update(citizenid, eventType, eventType)
end

-- Ranking de melhores scores
function SE.CreditScore.GetTopScores(limit)
  ensureSchema()
  limit = U.toInt(limit or 10, 10)
  
  local rows = MySQL.query.await([[
    SELECT 
      s.citizenid,
      s.score,
      s.rating,
      COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_credit_scores s
    LEFT JOIN space_economy_charcache c ON c.citizenid = s.citizenid
    ORDER BY s.score DESC
    LIMIT ?
  ]], {limit}) or {}
  
  return rows
end

--============================================================
-- HOOKS (Integração automática)
--============================================================

-- Hook: pagamento de dívida
if SE.Debts then
  local originalPay = SE.Debts.Pay
  SE.Debts.Pay = function(debtId, src, amountToPay)
    local success, remaining = originalPay(debtId, src, amountToPay)
    
    if success then
      local cid = B.GetCitizenId(src)
      if cid then
        local eventType = (remaining and remaining > 0) and 'payment_on_time' or 'debt_paid'
        SE.CreditScore.RecordEvent(cid, eventType, {amount = amountToPay})
      end
    end
    
    return success, remaining
  end
end

--============================================================
-- THREAD: Recalculo periódico
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  
  local intervalMs = 6 * 60 * 60 * 1000 -- 6 horas
  
  while true do
    Wait(intervalMs)
    
    -- Atualiza idade do crédito
    MySQL.update.await([[
      UPDATE space_economy_credit_scores
      SET credit_age_days = DATEDIFF(NOW(), created_at)
    ]])
    
    dbg('Credit age atualizado para todos os usuários')
  end
end)

--============================================================
-- EVENTOS DE REDE
--============================================================
RegisterNetEvent('space_economy:server_getMyScore', function()
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local score = SE.CreditScore.Get(cid)
  TriggerClientEvent('space_economy:client_receiveScore', src, score)
end)

RegisterNetEvent('space_economy:server_recalculateScore', function()
  local src = source
  if not SE.Admin.IsAllowed(src) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  SE.CreditScore.Update(cid, 'Recalculo manual', 'manual')
  B.Notify(src, 'Score recalculado', 'success')
end)