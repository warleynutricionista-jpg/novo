--============================================================
-- space_economy - server/loans.lua (NOVO)
-- Sistema de empréstimos governamentais com juros
--============================================================
SE = SE or {}
SE.Loans = SE.Loans or {}

local U = SE.Util
local B = SE.Bridge

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[loans]^7', ...) end 
end

--============================================================
-- CONFIGURAÇÃO
--============================================================
local LOAN_CONFIG = {
  -- Limites por faixa de score
  LIMITS = {
    { minScore = 850, maxAmount = 500000, interestRate = 0.05 },  -- 5% a.m.
    { minScore = 740, maxAmount = 300000, interestRate = 0.08 },  -- 8% a.m.
    { minScore = 670, maxAmount = 150000, interestRate = 0.12 },  -- 12% a.m.
    { minScore = 580, maxAmount = 75000,  interestRate = 0.15 },  -- 15% a.m.
    { minScore = 0,   maxAmount = 25000,  interestRate = 0.20 },  -- 20% a.m.
  },
  
  MAX_ACTIVE_LOANS = 3,
  MIN_LOAN_AMOUNT = 1000,
  MAX_TERM_MONTHS = 24,
  ORIGINATION_FEE = 0.02, -- 2% taxa de abertura
}

--============================================================
-- SCHEMA
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_loans (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL,
      disbursed_amount BIGINT NOT NULL,
      balance BIGINT NOT NULL,
      interest_rate DECIMAL(10,4) NOT NULL,
      term_months INT NOT NULL,
      monthly_payment BIGINT NOT NULL,
      paid_installments INT NOT NULL DEFAULT 0,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      credit_score_at_approval INT NOT NULL,
      purpose VARCHAR(200) NULL,
      approved_by VARCHAR(64) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      disbursed_at TIMESTAMP NULL,
      completed_at TIMESTAMP NULL,
      defaulted_at TIMESTAMP NULL,
      next_due_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_status (status),
      INDEX idx_next_due (next_due_at)
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_loan_payments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      loan_id INT NOT NULL,
      installment_number INT NOT NULL,
      amount BIGINT NOT NULL,
      principal BIGINT NOT NULL,
      interest BIGINT NOT NULL,
      balance_after BIGINT NOT NULL,
      paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_loan (loan_id)
    )
  ]])

  dbg('Schema de empréstimos garantido')
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
end)

--============================================================
-- CÁLCULO DE EMPRÉSTIMOS
--============================================================

-- Busca configuração baseada em score
local function getLoanConfig(score)
  score = U.toInt(score, 0)
  
  for _, cfg in ipairs(LOAN_CONFIG.LIMITS) do
    if score >= cfg.minScore then
      return cfg
    end
  end
  
  return LOAN_CONFIG.LIMITS[#LOAN_CONFIG.LIMITS]
end

-- Calcula parcela mensal (sistema PRICE)
local function calculateMonthlyPayment(principal, monthlyRate, months)
  if monthlyRate == 0 then
    return math.ceil(principal / months)
  end
  
  local rate = monthlyRate
  local payment = principal * (rate * math.pow(1 + rate, months)) / 
                  (math.pow(1 + rate, months) - 1)
  
  return math.ceil(payment)
end

-- Simula empréstimo
function SE.Loans.Simulate(citizenid, amount, months, purpose)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return nil, 'invalid_citizenid' end
  
  amount = U.toInt(amount, 0)
  if amount < LOAN_CONFIG.MIN_LOAN_AMOUNT then
    return nil, 'amount_too_low'
  end
  
  months = U.toInt(months, 12)
  if months < 1 or months > LOAN_CONFIG.MAX_TERM_MONTHS then
    return nil, 'invalid_term'
  end
  
  -- Busca score
  local score = SE.CreditScore and SE.CreditScore.Get(citizenid)
  local scoreValue = score and U.toInt(score.score, 0) or 500
  
  -- Configuração baseada em score
  local cfg = getLoanConfig(scoreValue)
  
  if amount > cfg.maxAmount then
    return nil, ('max_amount_exceeded:' .. cfg.maxAmount)
  end
  
  -- Verifica empréstimos ativos
  local activeLoans = MySQL.single.await([[
    SELECT COUNT(*) as cnt
    FROM space_economy_loans
    WHERE citizenid = ? AND status = 'active'
  ]], {citizenid}) or {}
  
  if U.toInt(activeLoans.cnt, 0) >= LOAN_CONFIG.MAX_ACTIVE_LOANS then
    return nil, 'max_loans_reached'
  end
  
  -- Calcula taxa de abertura
  local originationFee = math.floor(amount * LOAN_CONFIG.ORIGINATION_FEE)
  local disbursedAmount = amount - originationFee
  
  -- Calcula parcela
  local monthlyRate = cfg.interestRate
  local monthlyPayment = calculateMonthlyPayment(amount, monthlyRate, months)
  
  local totalPayment = monthlyPayment * months
  local totalInterest = totalPayment - amount
  
  return {
    amount = amount,
    disbursedAmount = disbursedAmount,
    originationFee = originationFee,
    interestRate = cfg.interestRate,
    interestRatePercent = cfg.interestRate * 100,
    termMonths = months,
    monthlyPayment = monthlyPayment,
    totalPayment = totalPayment,
    totalInterest = totalInterest,
    creditScore = scoreValue,
    rating = score and score.rating or 'Regular',
    approved = scoreValue >= 580, -- Mínimo Regular
  }
end

-- Solicita empréstimo
function SE.Loans.Request(src, amount, months, purpose)
  ensureSchema()
  
  local cid = B.GetCitizenId(src)
  if not cid then return false, 'invalid_source' end
  
  -- Simula
  local simulation, err = SE.Loans.Simulate(cid, amount, months, purpose)
  if not simulation then
    return false, err
  end
  
  if not simulation.approved then
    return false, 'credit_score_too_low'
  end
  
  -- Verifica se tesouro tem saldo
  local treasury = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or 0
  if treasury < simulation.disbursedAmount then
    return false, 'insufficient_treasury'
  end
  
  -- Cria empréstimo
  local loanId = MySQL.insert.await([[
    INSERT INTO space_economy_loans
      (citizenid, amount, disbursed_amount, balance, interest_rate, 
       term_months, monthly_payment, credit_score_at_approval, purpose, 
       disbursed_at, next_due_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY))
  ]], {
    cid,
    simulation.amount,
    simulation.disbursedAmount,
    simulation.amount, -- balance inicial = total
    simulation.interestRate,
    simulation.termMonths,
    simulation.monthlyPayment,
    simulation.creditScore,
    purpose or 'Uso pessoal'
  })
  
  if not loanId then
    return false, 'loan_creation_failed'
  end
  
  -- Remove do tesouro
  if SE.Treasury and SE.Treasury.Withdraw then
    SE.Treasury.Withdraw(simulation.disbursedAmount, 'emprestimo_concedido', {
      loan_id = loanId,
      citizenid = cid
    })
  end
  
  -- Adiciona dinheiro ao player
  if SE.Integrations and SE.Integrations.AddMoney then
    SE.Integrations.AddMoney(src, simulation.disbursedAmount, 'bank')
  end
  
  -- Registra evento no score
  if SE.CreditScore then
    SE.CreditScore.RecordEvent(cid, 'loan_approved', {
      amount = simulation.amount,
      loan_id = loanId
    })
  end
  
  if SE.Log then
    SE.Log('loan', ('Empréstimo aprovado: %d x %d = %d'):format(
      simulation.termMonths, 
      simulation.monthlyPayment, 
      simulation.totalPayment
    ), {
      loan_id = loanId,
      citizenid = cid
    })
  end
  
  dbg(('Empréstimo concedido: %s | $%d em %d meses'):format(cid, simulation.amount, simulation.termMonths))
  
  return true, loanId, simulation
end

-- Paga parcela do empréstimo
function SE.Loans.PayInstallment(loanId, src)
  ensureSchema()
  
  loanId = U.toInt(loanId, 0)
  if loanId <= 0 then return false, 'invalid_loan_id' end
  
  -- Lock
  local lockKey = ('loan:%d'):format(loanId)
  local owner = ('src_%d'):format(src or 0)
  
  if SE.Locks and not SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50) then
    return false, 'lock_timeout'
  end
  
  -- Busca empréstimo
  local loan = MySQL.single.await([[
    SELECT * FROM space_economy_loans
    WHERE id = ? AND status = 'active'
    LIMIT 1
  ]], {loanId})
  
  if not loan then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'loan_not_found'
  end
  
  local monthlyPayment = U.toInt(loan.monthly_payment, 0)
  local balance = U.toInt(loan.balance, 0)
  local interestRate = U.toNumber(loan.interest_rate, 0)
  
  -- Calcula juros da parcela
  local interest = math.floor(balance * interestRate)
  local principal = monthlyPayment - interest
  
  if principal < 0 then principal = 0 end
  
  -- Remove dinheiro
  local success = false
  if SE.Integrations and SE.Integrations.RemoveMoney then
    success = SE.Integrations.RemoveMoney(src, monthlyPayment, 'bank')
  end
  
  if not success then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'insufficient_funds'
  end
  
  -- Atualiza empréstimo
  local newBalance = balance - principal
  local newPaidCount = U.toInt(loan.paid_installments, 0) + 1
  local totalInstallments = U.toInt(loan.term_months, 0)
  
  if newBalance <= 0 or newPaidCount >= totalInstallments then
    -- Quitado
    MySQL.update.await([[
      UPDATE space_economy_loans
      SET balance = 0,
          paid_installments = ?,
          status = 'completed',
          completed_at = NOW()
      WHERE id = ?
    ]], {newPaidCount, loanId})
    
    -- Registra no score
    if SE.CreditScore then
      SE.CreditScore.RecordEvent(loan.citizenid, 'loan_completed', {
        loan_id = loanId
      })
    end
  else
    -- Ainda tem parcelas
    MySQL.update.await([[
      UPDATE space_economy_loans
      SET balance = ?,
          paid_installments = ?,
          next_due_at = DATE_ADD(NOW(), INTERVAL 30 DAY)
      WHERE id = ?
    ]], {newBalance, newPaidCount, loanId})
  end
  
  -- Registra pagamento
  MySQL.insert.await([[
    INSERT INTO space_economy_loan_payments
      (loan_id, installment_number, amount, principal, interest, balance_after)
    VALUES (?, ?, ?, ?, ?, ?)
  ]], {
    loanId,
    newPaidCount,
    monthlyPayment,
    principal,
    interest,
    newBalance
  })
  
  -- Adiciona ao tesouro
  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(monthlyPayment, 'pagamento_emprestimo', {
      loan_id = loanId,
      citizenid = loan.citizenid
    })
  end
  
  if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
  
  local remaining = totalInstallments - newPaidCount
  
  if SE.Log then
    SE.Log('loan', ('Parcela paga: %d/%d | principal: %d | juros: %d'):format(
      newPaidCount, totalInstallments, principal, interest
    ), {
      loan_id = loanId,
      citizenid = loan.citizenid
    })
  end
  
  return true, {
    paid = newPaidCount,
    total = totalInstallments,
    remaining = remaining,
    balance = newBalance,
    completed = newBalance <= 0 or newPaidCount >= totalInstallments
  }
end

-- Lista empréstimos ativos
function SE.Loans.GetActiveLoans(citizenid)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return {} end
  
  local loans = MySQL.query.await([[
    SELECT l.*,
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_loans l
    LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
    WHERE l.citizenid = ? AND l.status = 'active'
    ORDER BY l.created_at DESC
  ]], {citizenid}) or {}
  
  return loans
end

-- Busca detalhes do empréstimo
function SE.Loans.GetDetails(loanId)
  ensureSchema()
  
  loanId = U.toInt(loanId, 0)
  if loanId <= 0 then return nil end
  
  local loan = MySQL.single.await([[
    SELECT l.*,
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_loans l
    LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
    WHERE l.id = ?
    LIMIT 1
  ]], {loanId})
  
  if not loan then return nil end
  
  -- Busca histórico de pagamentos
  local payments = MySQL.query.await([[
    SELECT * FROM space_economy_loan_payments
    WHERE loan_id = ?
    ORDER BY installment_number ASC
  ]], {loanId}) or {}
  
  loan.payments = payments
  
  return loan
end

--============================================================
-- THREAD: Avisos e inadimplência
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  
  local checkIntervalMs = 60 * 60 * 1000 -- 1 hora
  
  while true do
    Wait(checkIntervalMs)
    
    -- Avisos de vencimento (3 dias antes)
    local upcoming = MySQL.query.await([[
      SELECT * FROM space_economy_loans
      WHERE status = 'active'
        AND next_due_at BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 3 DAY)
    ]])
    
    if upcoming then
      for _, loan in ipairs(upcoming) do
        local src = B.GetSourceByCitizenId(loan.citizenid)
        if src then
          B.Notify(src, ('Parcela de empréstimo vence em breve: $%d'):format(
            U.toInt(loan.monthly_payment, 0)
          ), 'warn')
        end
      end
    end
    
    -- Marca como inadimplente (30 dias após vencimento)
    local defaulted = MySQL.query.await([[
      SELECT * FROM space_economy_loans
      WHERE status = 'active'
        AND next_due_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
    ]])
    
    if defaulted then
      for _, loan in ipairs(defaulted) do
        MySQL.update.await([[
          UPDATE space_economy_loans
          SET status = 'defaulted', defaulted_at = NOW()
          WHERE id = ?
        ]], {loan.id})
        
        -- Penaliza score
        if SE.CreditScore then
          SE.CreditScore.RecordEvent(loan.citizenid, 'loan_defaulted', {
            loan_id = loan.id,
            amount = loan.balance
          })
        end
        
        dbg(('Empréstimo inadimplente: %d | %s'):format(loan.id, loan.citizenid))
      end
    end
  end
end)

--============================================================
-- EVENTOS DE REDE
--============================================================
RegisterNetEvent('space_economy:server_simulateLoan', function(amount, months, purpose)
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local simulation, err = SE.Loans.Simulate(cid, amount, months, purpose)
  
  if simulation then
    TriggerClientEvent('space_economy:client_loanSimulation', src, simulation)
  else
    B.Notify(src, 'Falha na simulação: ' .. tostring(err), 'error')
  end
end)

RegisterNetEvent('space_economy:server_requestLoan', function(amount, months, purpose)
  local src = source
  
  local success, loanId, simulation = SE.Loans.Request(src, amount, months, purpose)
  
  if success then
    B.Notify(src, ('Empréstimo aprovado! $%d depositados.'):format(simulation.disbursedAmount), 'success')
    TriggerClientEvent('space_economy:client_loanApproved', src, loanId, simulation)
  else
    B.Notify(src, 'Empréstimo negado: ' .. tostring(loanId), 'error')
  end
end)

RegisterNetEvent('space_economy:server_payLoanInstallment', function(loanId)
  local src = source
  
  local success, result = SE.Loans.PayInstallment(loanId, src)
  
  if success then
    if result.completed then
      B.Notify(src, 'Empréstimo quitado com sucesso!', 'success')
    else
      B.Notify(src, ('Parcela paga! Restam %d de %d'):format(result.remaining, result.total), 'success')
    end
    TriggerClientEvent('space_economy:client_loanPaymentMade', src, loanId, result)
  else
    B.Notify(src, 'Falha ao pagar: ' .. tostring(result), 'error')
  end
end)

RegisterNetEvent('space_economy:server_getMyLoans', function()
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local loans = SE.Loans.GetActiveLoans(cid)
  TriggerClientEvent('space_economy:client_receiveLoans', src, loans)
end)