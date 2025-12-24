--============================================================
-- space_economy - server/debts.lua (MELHORADO)
-- Sistema completo de dívidas com juros, parcelamento e cobranças
--============================================================
SE = SE or {}
SE.Debts = SE.Debts or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config or {}

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[debts]^7', ...) end 
end

--============================================================
-- SCHEMA: Garante tabela com todas as colunas necessárias
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Tabela principal de dívidas
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_debts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL DEFAULT 0,
      original_amount BIGINT NOT NULL DEFAULT 0,
      reason VARCHAR(200) NOT NULL DEFAULT 'Imposto',
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      interest_rate DECIMAL(10,4) NOT NULL DEFAULT 0.01,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      due_at TIMESTAMP NULL,
      grace_until TIMESTAMP NULL,
      paid_at TIMESTAMP NULL,
      last_interest_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_status_due (status, due_at),
      INDEX idx_grace (grace_until)
    )
  ]])

  -- Adiciona colunas se tabela antiga não as tem
  local cols = {'original_amount', 'last_interest_at', 'grace_until'}
  for _, col in ipairs(cols) do
    local hasCol = MySQL.single.await([[
      SELECT COLUMN_NAME 
      FROM information_schema.COLUMNS 
      WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'space_economy_debts' 
        AND COLUMN_NAME = ?
    ]], {col})
    
    if not hasCol then
      if col == 'original_amount' then
        MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN original_amount BIGINT NOT NULL DEFAULT 0 AFTER amount')
      elseif col == 'last_interest_at' then
        MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN last_interest_at TIMESTAMP NULL')
      elseif col == 'grace_until' then
        MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN grace_until TIMESTAMP NULL AFTER due_at')
      end
    end
  end

  -- Tabela de histórico de pagamentos/parcelamentos
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_debt_payments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      debt_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL,
      payment_type VARCHAR(20) NOT NULL DEFAULT 'full',
      installment_number INT NULL,
      paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      meta LONGTEXT NULL,
      INDEX idx_debt (debt_id),
      INDEX idx_citizen (citizenid)
    )
  ]])

  dbg('Schema de dívidas garantido')
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
end)

--============================================================
-- CORE API
--============================================================

-- Cria/Atualiza dívida (UPSERT idempotente)
function SE.Debts.Upsert(citizenid, amount, reason, dueTs, meta)
  ensureSchema()
  
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return false, 'citizenid_invalid' end
  
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'amount_invalid' end
  
  reason = U.trim(U.safeStr(reason or 'Imposto', 'Imposto'))
  meta = type(meta) == 'table' and meta or {}
  
  -- Configuração de datas
  local now = os.time()
  local graceHours = (cfg.DebtSystem and cfg.DebtSystem.GraceHours) or 24
  local graceDays = math.floor(graceHours / 24)
  
  local dueAt = dueTs and U.tsToIso(dueTs) or U.tsToIso(now + (7 * 24 * 60 * 60)) -- 7 dias
  local graceUntil = U.tsToIso(now + (graceDays * 24 * 60 * 60))
  
  local interestRate = (cfg.DebtSystem and cfg.DebtSystem.InterestDailyRate) or 0.01
  
  -- Busca dívida ativa existente
  local existing = MySQL.single.await([[
    SELECT id, amount 
    FROM space_economy_debts 
    WHERE citizenid = ? AND status = 'active' AND reason = ?
    LIMIT 1
  ]], {citizenid, reason})
  
  if existing then
    -- Atualiza dívida existente (acumula valor)
    local newAmount = U.toInt(existing.amount, 0) + amount
    MySQL.update.await([[
      UPDATE space_economy_debts 
      SET amount = ?, 
          due_at = ?,
          grace_until = ?,
          meta = ?
      WHERE id = ?
    ]], {newAmount, dueAt, graceUntil, U.safeJsonEncode(meta), existing.id})
    
    dbg(('Dívida atualizada: %s | %d -> %d'):format(citizenid, existing.amount, newAmount))
    
    -- Log
    if SE.Log then
      SE.Log('debt', ('Dívida atualizada: %s +%d = %d'):format(reason, amount, newAmount), {
        citizenid = citizenid,
        debt_id = existing.id
      })
    end
    
    return true, existing.id
  else
    -- Cria nova dívida
    local insertId = MySQL.insert.await([[
      INSERT INTO space_economy_debts 
        (citizenid, amount, original_amount, reason, interest_rate, due_at, grace_until, meta)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {citizenid, amount, amount, reason, interestRate, dueAt, graceUntil, U.safeJsonEncode(meta)})
    
    dbg(('Nova dívida: %s | %d | %s'):format(citizenid, amount, reason))
    
    if SE.Log then
      SE.Log('debt', ('Nova dívida: %s = %d'):format(reason, amount), {
        citizenid = citizenid,
        debt_id = insertId
      })
    end
    
    -- Notifica player se online
    local src = B.GetSourceByCitizenId(citizenid)
    if src then
      B.Notify(src, ('Nova dívida lançada: $%d - %s'):format(amount, reason), 'inform')
    end
    
    return true, insertId
  end
end

-- Lista dívidas ativas (com paginação)
function SE.Debts.ListActive(limit, offset)
  ensureSchema()
  limit = U.toInt(limit or 150, 150)
  offset = U.toInt(offset or 0, 0)
  
  local rows = MySQL.query.await([[
    SELECT d.*, 
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.status = 'active'
    ORDER BY d.amount DESC
    LIMIT ? OFFSET ?
  ]], {limit, offset}) or {}
  
  -- Enriquece com dados online
  for _, row in ipairs(rows) do
    row.isOnline = B.GetSourceByCitizenId(row.citizenid) ~= nil
    row.amount = U.toInt(row.amount, 0)
    row.original_amount = U.toInt(row.original_amount, 0)
  end
  
  return rows
end

-- Busca dívida por ID
function SE.Debts.GetById(id)
  ensureSchema()
  id = U.toInt(id, 0)
  if id <= 0 then return nil end
  
  local row = MySQL.single.await([[
    SELECT d.*, 
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.id = ?
    LIMIT 1
  ]], {id})
  
  if row then
    row.isOnline = B.GetSourceByCitizenId(row.citizenid) ~= nil
    row.amount = U.toInt(row.amount, 0)
    row.original_amount = U.toInt(row.original_amount, 0)
  end
  
  return row
end

-- Busca dívidas ativas de um cidadão
function SE.Debts.GetActiveByCitizen(citizenid, limit)
  ensureSchema()
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return {} end
  
  limit = U.toInt(limit or 50, 50)
  
  local rows = MySQL.query.await([[
    SELECT d.*, 
           COALESCE(c.name, 'Desconhecido') as playerName
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.citizenid = ? AND d.status = 'active'
    ORDER BY d.created_at DESC
    LIMIT ?
  ]], {citizenid, limit}) or {}
  
  for _, row in ipairs(rows) do
    row.amount = U.toInt(row.amount, 0)
    row.original_amount = U.toInt(row.original_amount, 0)
    row.isOnline = true -- já sabemos que estamos buscando específico
  end
  
  return rows
end

-- Totaliza dívidas de um cidadão
function SE.Debts.GetTotalByCitizen(citizenid)
  ensureSchema()
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return 0 end
  
  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(amount), 0) as total
    FROM space_economy_debts
    WHERE citizenid = ? AND status = 'active'
  ]], {citizenid})
  
  return row and U.toInt(row.total, 0) or 0
end

-- Pagar dívida (total ou parcial)
function SE.Debts.Pay(debtId, src, amountToPay)
  ensureSchema()
  
  debtId = U.toInt(debtId, 0)
  if debtId <= 0 then return false, 'invalid_debt_id' end
  
  -- Lock por dívida
  local lockKey = ('debt:%d'):format(debtId)
  local owner = ('src_%d'):format(src or 0)
  
  if SE.Locks and not SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50) then
    return false, 'lock_timeout'
  end
  
  -- Busca dívida
  local debt = SE.Debts.GetById(debtId)
  if not debt or debt.status ~= 'active' then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'debt_not_found'
  end
  
  local amountOwed = U.toInt(debt.amount, 0)
  amountToPay = amountToPay and U.toInt(amountToPay, 0) or amountOwed
  
  if amountToPay <= 0 then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'invalid_amount'
  end
  
  if amountToPay > amountOwed then
    amountToPay = amountOwed
  end
  
  -- Remove dinheiro
  local success = false
  if SE.Integrations and SE.Integrations.RemoveMoney then
    success = SE.Integrations.RemoveMoney(src, amountToPay, 'bank')
  end
  
  if not success then
    if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
    return false, 'insufficient_funds'
  end
  
  -- Atualiza dívida
  local remaining = amountOwed - amountToPay
  
  if remaining <= 0 then
    -- Quitada
    MySQL.update.await([[
      UPDATE space_economy_debts 
      SET status = 'paid', 
          paid_at = NOW(), 
          amount = 0 
      WHERE id = ?
    ]], {debtId})
  else
    -- Parcial
    MySQL.update.await([[
      UPDATE space_economy_debts 
      SET amount = ? 
      WHERE id = ?
    ]], {remaining, debtId})
  end
  
  -- Registra pagamento
  MySQL.insert.await([[
    INSERT INTO space_economy_debt_payments 
      (debt_id, citizenid, amount, payment_type)
    VALUES (?, ?, ?, ?)
  ]], {debtId, debt.citizenid, amountToPay, remaining <= 0 and 'full' or 'partial'})
  
  -- Adiciona ao tesouro
  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(amountToPay, 'pagamento_divida', {
      debt_id = debtId,
      citizenid = debt.citizenid
    })
  end
  
  if SE.Locks then SE.Locks.Release(lockKey, owner, true) end
  
  -- Log
  if SE.Log then
    SE.Log('debt', ('Pagamento: %d de %d | restante: %d'):format(amountToPay, amountOwed, remaining), {
      debt_id = debtId,
      citizenid = debt.citizenid,
      src = src
    })
  end
  
  return true, remaining
end

--============================================================
-- JUROS AUTOMÁTICOS (Thread)
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  
  local intervalMs = 60 * 60 * 1000 -- 1 hora
  
  while true do
    Wait(intervalMs)
    
    if not (cfg.DebtSystem and cfg.DebtSystem.Enabled) then
      goto continue
    end
    
    -- Busca dívidas que precisam de juros
    local debts = MySQL.query.await([[
      SELECT id, amount, interest_rate, last_interest_at, grace_until
      FROM space_economy_debts
      WHERE status = 'active'
        AND (grace_until IS NULL OR grace_until < NOW())
        AND (last_interest_at IS NULL OR last_interest_at < DATE_SUB(NOW(), INTERVAL 24 HOUR))
    ]])
    
    if debts then
      for _, d in ipairs(debts) do
        local amount = U.toInt(d.amount, 0)
        local rate = U.toNumber(d.interest_rate, 0.01)
        local interest = math.floor(amount * rate + 0.5)
        
        if interest > 0 then
          local newAmount = amount + interest
          MySQL.update.await([[
            UPDATE space_economy_debts 
            SET amount = ?, last_interest_at = NOW() 
            WHERE id = ?
          ]], {newAmount, d.id})
          
          dbg(('Juros aplicados: dívida %d | +%d = %d'):format(d.id, interest, newAmount))
        end
      end
    end
    
    ::continue::
  end
end)

--============================================================
-- AVISOS PERIÓDICOS (Thread)
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  
  local warnIntervalMs = ((cfg.DebtSystem and cfg.DebtSystem.WarnEveryHours) or 12) * 60 * 60 * 1000
  
  while true do
    Wait(warnIntervalMs)
    
    if not (cfg.DebtSystem and cfg.DebtSystem.Enabled) then
      goto continue
    end
    
    -- Busca dívidas vencidas
    local debts = MySQL.query.await([[
      SELECT citizenid, SUM(amount) as total
      FROM space_economy_debts
      WHERE status = 'active' 
        AND due_at < NOW()
      GROUP BY citizenid
    ]])
    
    if debts then
      for _, d in ipairs(debts) do
        local src = B.GetSourceByCitizenId(d.citizenid)
        if src then
          B.Notify(src, ('Você possui $%d em dívidas vencidas. Regularize sua situação.'):format(U.toInt(d.total, 0)), 'error')
        end
      end
    end
    
    ::continue::
  end
end)

--============================================================
-- EVENTOS DE REDE
--============================================================
RegisterNetEvent('space_economy:server_payDebt', function(debtId, amount)
  local src = source
  local success, remaining = SE.Debts.Pay(debtId, src, amount)
  
  if success then
    if remaining and remaining > 0 then
      B.Notify(src, ('Pagamento parcial realizado. Restante: $%d'):format(remaining), 'success')
    else
      B.Notify(src, 'Dívida quitada com sucesso!', 'success')
    end
  else
    B.Notify(src, 'Falha ao pagar dívida: ' .. tostring(remaining or 'erro'), 'error')
  end
end)

RegisterNetEvent('space_economy:server_listMyDebts', function()
  local src = source
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local debts = SE.Debts.GetActiveByCitizen(cid, 50)
  TriggerClientEvent('space_economy:client_receiveMyDebts', src, debts)
end)