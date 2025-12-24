--============================================================
-- space_economy - server/installments.lua (NOVO)
-- Sistema completo de parcelamento de dívidas
--============================================================
SE = SE or {}
SE.Installments = SE.Installments or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config or {}

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[installments]^7', ...) end 
end

--============================================================
-- SCHEMA
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Tabela de planos de parcelamento
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_installment_plans (
      id INT AUTO_INCREMENT PRIMARY KEY,
      debt_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      original_amount BIGINT NOT NULL,
      total_amount BIGINT NOT NULL,
      installments INT NOT NULL,
      installment_value BIGINT NOT NULL,
      paid_installments INT NOT NULL DEFAULT 0,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      fee_percent DECIMAL(10,4) NOT NULL DEFAULT 0.05,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      next_due_at TIMESTAMP NULL,
      completed_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_debt (debt_id),
      INDEX idx_next_due (next_due_at)
    )
  ]])

  -- Tabela de parcelas individuais
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_installments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      plan_id INT NOT NULL,
      installment_number INT NOT NULL,
      amount BIGINT NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'pending',
      due_at TIMESTAMP NOT NULL,
      paid_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_plan (plan_id),
      INDEX idx_status_due (status, due_at)
    )
  ]])

  dbg('Schema de parcelamento garantido')
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
end)

--============================================================
-- CORE API
--============================================================

-- Calcula plano de parcelamento
function SE.Installments.Calculate(amount, installments)
  amount = U.toInt(amount, 0)
  installments = U.toInt(installments, 1)
  
  if amount <= 0 then return nil, 'invalid_amount' end
  
  local maxInst = (cfg.DebtSystem and cfg.DebtSystem.MaxInstallments) or 12
  local minValue = (cfg.DebtSystem and cfg.DebtSystem.MinInstallmentValue) or 100
  local feePercent = (cfg.DebtSystem and cfg.DebtSystem.InstallmentFee) or 0.05
  
  if installments < 1 then installments = 1 end
  if installments > maxInst then installments = maxInst end
  
  -- Calcula taxa administrativa
  local fee = math.floor(amount * feePercent + 0.5)
  local totalAmount = amount + fee
  
  -- Calcula valor da parcela
  local installmentValue = math.ceil(totalAmount / installments)
  
  -- Verifica mínimo
  if installmentValue < minValue then
    installments = math.floor(totalAmount / minValue)
    if installments < 1 then installments = 1 end
    installmentValue = math.ceil(totalAmount / installments)
  end
  
  -- Ajusta última parcela (resto)
  local lastInstallment = totalAmount - (installmentValue * (installments - 1))
  
  return {
    original = amount,
    fee = fee,
    feePercent = feePercent * 100,
    total = totalAmount,
    installments = installments,
    installmentValue = installmentValue,
    lastInstallment = lastInstallment,
  }
end

-- Cria plano de parcelamento
function SE.Installments.CreatePlan(debtId, citizenid, installments)
  ensureSchema()
  
  debtId = U.toInt(debtId, 0)
  if debtId <= 0 then return false, 'invalid_debt_id' end
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return false, 'invalid_citizenid' end
  
  installments = U.toInt(installments, 1)
  
  -- Busca dívida
  local debt = SE.Debts and SE.Debts.GetById(debtId)
  if not debt or debt.status ~= 'active' then
    return false, 'debt_not_found'
  end
  
  if debt.citizenid ~= citizenid then
    return false, 'debt_not_owned'
  end
  
  local amount = U.toInt(debt.amount, 0)
  
  -- Calcula plano
  local plan = SE.Installments.Calculate(amount, installments)
  if not plan then return false, 'calculation_failed' end
  
  -- Cria plano
  local planId = MySQL.insert.await([[
    INSERT INTO space_economy_installment_plans 
      (debt_id, citizenid, original_amount, total_amount, installments, 
       installment_value, fee_percent, next_due_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 30 DAY))
  ]], {
    debtId,
    citizenid,
    plan.original,
    plan.total,
    plan.installments,
    plan.installmentValue,
    plan.feePercent / 100,
  })
  
  if not planId then return false, 'plan_creation_failed' end
  
  -- Cria parcelas
  local now = os.time()
  for i = 1, plan.installments do
    local dueTs = now + (i * 30 * 24 * 60 * 60) -- 30 dias por parcela
    local value = (i == plan.installments) and plan.lastInstallment or plan.installmentValue
    
    MySQL.insert.await([[
      INSERT INTO space_economy_installments 
        (plan_id, installment_number, amount, due_at)
      VALUES (?, ?, ?, ?)
    ]], {
      planId,
      i,
      value,
      U.tsToIso(dueTs)
    })
  end
  
  -- Marca dívida como parcelada
  MySQL.update.await([[
    UPDATE space_economy_debts 
    SET status = 'installment', 
        meta = JSON_SET(COALESCE(meta, '{}'), '$.plan_id', ?)
    WHERE id = ?
  ]], {planId, debtId})
  
  dbg(('Plano criado: %d parcelas de %d para %s'):format(plan.installments, plan.installmentValue, citizenid))
  
  if SE.Log then
    SE.Log('installment', ('Plano criado: %d x %d'):format(plan.installments, plan.installmentValue), {
      plan_id = planId,
      debt_id = debtId,
      citizenid = citizenid
    })
  end
  
  return true, planId, plan
end

-- Busca planos ativos de um cidadão
function SE.Installments.GetActivePlans(citizenid)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return {} end
  
  local plans = MySQL.query.await([[
    SELECT p.*,
           d.reason as debt_reason,
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_installment_plans p
    LEFT JOIN space_economy_debts d ON d.id = p.debt_id
    LEFT JOIN space_economy_charcache c ON c.citizenid = p.citizenid
    WHERE p.citizenid = ? AND p.status = 'active'
    ORDER BY p.created_at DESC
  ]], {citizenid}) or {}
  
  return plans
end

-- Busca próxima parcela a vencer
function SE.Installments.GetNextInstallment(planId)
  ensureSchema()
  
  planId = U.toInt(planId, 0)
  if planId <= 0 then return nil end
  
  local installment = MySQL.single.await([[
    SELECT * FROM space_economy_installments
    WHERE plan_id = ? AND status = 'pending'
    ORDER BY installment_number ASC
    LIMIT 1
  ]], {planId})
  
  return installment
end

-- Paga parcela
function SE.Installments.PayInstallment(planId, src)
  ensureSchema()
  
  planId = U.toInt(planId, 0)
  if planId <= 0 then return false, 'invalid_plan_id' end
  
  -- Lock
  local lockKey = ('installment_plan:%d'):format(planId)
  local owner = ('src_%d'):format(src or 0)
  
  if SE.Locks and not SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50) then
    return false, 'lock_timeout'
  end
  
  -- Busca plano
  local plan = MySQL.single.await([[
    SELECT * FROM space_economy_installment_plans
    WHERE id = ? AND status = 'active'
    LIMIT 1
  ]], {planId})
  
  if not plan then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'plan_not_found'
  end
  
  -- Busca próxima parcela
  local installment = SE.Installments.GetNextInstallment(planId)
  if not installment then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'no_pending_installment'
  end
  
  local amount = U.toInt(installment.amount, 0)
  
  -- Remove dinheiro
  local success = false
  if SE.Integrations and SE.Integrations.RemoveMoney then
    success = SE.Integrations.RemoveMoney(src, amount, 'bank')
  end
  
  if not success then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'insufficient_funds'
  end
  
  -- Marca parcela como paga
  MySQL.update.await([[
    UPDATE space_economy_installments
    SET status = 'paid', paid_at = NOW()
    WHERE id = ?
  ]], {installment.id})
  
  -- Atualiza plano
  local newPaidCount = U.toInt(plan.paid_installments, 0) + 1
  local totalInst = U.toInt(plan.installments, 0)
  
  if newPaidCount >= totalInst then
    -- Completo
    MySQL.update.await([[
      UPDATE space_economy_installment_plans
      SET paid_installments = ?,
          status = 'completed',
          completed_at = NOW()
      WHERE id = ?
    ]], {newPaidCount, planId})
    
    -- Marca dívida como paga
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET status = 'paid', paid_at = NOW()
      WHERE id = ?
    ]], {plan.debt_id})
  else
    -- Ainda tem parcelas
    local nextInst = SE.Installments.GetNextInstallment(planId)
    local nextDue = nextInst and nextInst.due_at or nil
    
    MySQL.update.await([[
      UPDATE space_economy_installment_plans
      SET paid_installments = ?,
          next_due_at = ?
      WHERE id = ?
    ]], {newPaidCount, nextDue, planId})
  end
  
  -- Adiciona ao tesouro
  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(amount, 'pagamento_parcela', {
      plan_id = planId,
      installment_id = installment.id,
      citizenid = plan.citizenid
    })
  end
  
  if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
  
  local remaining = totalInst - newPaidCount
  
  if SE.Log then
    SE.Log('installment', ('Parcela paga: %d/%d | restam %d'):format(newPaidCount, totalInst, remaining), {
      plan_id = planId,
      citizenid = plan.citizenid
    })
  end
  
  return true, {
    paid = newPaidCount,
    total = totalInst,
    remaining = remaining,
    completed = newPaidCount >= totalInst
  }
end

--============================================================
-- THREAD: Avisos de vencimento
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  
  local checkIntervalMs = 60 * 60 * 1000 -- 1 hora
  
  while true do
    Wait(checkIntervalMs)
    
    -- Busca parcelas vencendo em 3 dias
    local upcoming = MySQL.query.await([[
      SELECT i.*, p.citizenid
      FROM space_economy_installments i
      INNER JOIN space_economy_installment_plans p ON p.id = i.plan_id
      WHERE i.status = 'pending'
        AND i.due_at BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 3 DAY)
        AND p.status = 'active'
    ]])
    
    if upcoming then
      for _, inst in ipairs(upcoming) do
        local src = B.GetSourceByCitizenId(inst.citizenid)
        if src then
          B.Notify(src, ('Parcela %d/%d vence em breve: $%d'):format(
            inst.installment_number,
            inst.installments,
            U.toInt(inst.amount, 0)
          ), 'warn')
        end
      end
    end
    
    -- Parcelas vencidas (marca como atrasada)
    MySQL.update.await([[
      UPDATE space_economy_installments
      SET status = 'overdue'
      WHERE status = 'pending' AND due_at < NOW()
    ]])
  end
end)

--============================================================
-- EVENTOS DE REDE
--============================================================
RegisterNetEvent('space_economy:server_createInstallmentPlan', function(debtId, installments)
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local success, planId, plan = SE.Installments.CreatePlan(debtId, cid, installments)
  
  if success then
    B.Notify(src, ('Parcelamento criado: %d x $%d'):format(plan.installments, plan.installmentValue), 'success')
    TriggerClientEvent('space_economy:client_installmentPlanCreated', src, planId, plan)
  else
    B.Notify(src, 'Falha ao criar parcelamento: ' .. tostring(planId), 'error')
  end
end)

RegisterNetEvent('space_economy:server_payInstallment', function(planId)
  local src = source
  
  local success, result = SE.Installments.PayInstallment(planId, src)
  
  if success then
    if result.completed then
      B.Notify(src, 'Parcelamento quitado com sucesso!', 'success')
    else
      B.Notify(src, ('Parcela paga! Restam %d de %d'):format(result.remaining, result.total), 'success')
    end
    TriggerClientEvent('space_economy:client_installmentPaid', src, planId, result)
  else
    B.Notify(src, 'Falha ao pagar parcela: ' .. tostring(result), 'error')
  end
end)

RegisterNetEvent('space_economy:server_getMyInstallments', function()
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local plans = SE.Installments.GetActivePlans(cid)
  TriggerClientEvent('space_economy:client_receiveInstallments', src, plans)
end)