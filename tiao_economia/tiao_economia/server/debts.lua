SE = SE or {}
SE.Debts = SE.Debts or {}

local U = SE.Util
local B = SE.Bridge
local DS = Config.DebtSystem or {}

local ensured = false
local function ensureSchema()
  if ensured then return end
  ensured = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_debts (
      citizenid VARCHAR(50) NOT NULL,
      amount BIGINT NOT NULL DEFAULT 0,
      reason VARCHAR(255) NULL,
      principal BIGINT NOT NULL DEFAULT 0,
      paid BIGINT NOT NULL DEFAULT 0,
      status VARCHAR(16) NOT NULL DEFAULT 'active',
      strikes INT NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      due_at TIMESTAMP NULL,
      grace_until TIMESTAMP NULL,
      last_payment_at TIMESTAMP NULL,
      last_notice_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      PRIMARY KEY (citizenid),
      INDEX idx_status (status),
      INDEX idx_due (due_at)
    )
  ]])
end

local function isEnabled()
  return DS.Enabled ~= false
end

local function decodeMeta(s)
  local t = U.safeJsonDecode(s) or {}
  if type(t) ~= 'table' then t = {} end
  return t
end

local function encodeMeta(t)
  if type(t) ~= 'table' then t = {} end
  return U.safeJsonEncode(t)
end

local function dayIndex(ts)
  ts = U.toInt(ts, U.now())
  return math.floor(ts / 86400)
end

function SE.Debts.Upsert(citizenid, amount, reason, dueTs, meta)
  if not isEnabled() then return false end
  ensureSchema()

  citizenid = tostring(citizenid or '')
  if citizenid == '' then return false end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false end

  local now = U.now()
  local graceHours = U.toInt(DS.GraceHours or 24, 24)
  if graceHours < 0 then graceHours = 0 end

  local dueIso = U.tsToIso(dueTs or now)
  local graceIso = U.tsToIso(now + (graceHours * 3600))

  local m = type(meta) == 'table' and meta or {}
  m.created_ts = m.created_ts or now

  MySQL.update.await([[
    INSERT INTO space_economy_debts (citizenid, amount, reason, principal, paid, status, due_at, grace_until, meta)
    VALUES (?, ?, ?, ?, 0, 'active', ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      status = 'active',
      amount = amount + VALUES(amount),
      principal = principal + VALUES(principal),
      reason = VALUES(reason),
      due_at = VALUES(due_at),
      grace_until = VALUES(grace_until),
      meta = VALUES(meta)
  ]], {
    citizenid, amount, tostring(reason or 'Imposto'), amount, dueIso, graceIso, encodeMeta(m)
  })

  return true
end

function SE.Debts.ListActive(limit)
  ensureSchema()
  limit = U.toInt(limit or 200, 200)
  if limit < 1 then limit = 1 end
  if limit > 500 then limit = 500 end

  local rows = MySQL.query.await([[
    SELECT d.citizenid, d.amount, d.reason, d.meta,
           UNIX_TIMESTAMP(d.due_at) AS due_ts,
           UNIX_TIMESTAMP(d.grace_until) AS grace_ts,
           UNIX_TIMESTAMP(d.last_notice_at) AS last_notice_at_ts,
           COALESCE(c.name, 'Desconhecido') AS playerName
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.status = 'active'
    ORDER BY d.due_at ASC
    LIMIT ?
  ]], { limit }) or {}

  return rows
end

function SE.Debts.GetActiveByCitizen(citizenid, limit)
  ensureSchema()
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return {} end

  limit = U.toInt(limit or 10, 10)
  if limit < 1 then limit = 1 end
  if limit > 50 then limit = 50 end

  local rows = MySQL.query.await([[
    SELECT d.citizenid, d.amount, d.reason, d.meta,
           UNIX_TIMESTAMP(d.due_at) AS due_ts,
           UNIX_TIMESTAMP(d.grace_until) AS grace_ts,
           UNIX_TIMESTAMP(d.last_notice_at) AS last_notice_at_ts,
           COALESCE(c.name, 'Desconhecido') AS playerName
    FROM space_economy_debts d
    LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
    WHERE d.status = 'active' AND d.citizenid = ?
    LIMIT ?
  ]], { citizenid, limit }) or {}

  return rows
end

function SE.Debts.TotalActive(citizenid)
  ensureSchema()
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return 0 end

  local row = MySQL.single.await([[
    SELECT COALESCE(amount,0) AS total
    FROM space_economy_debts
    WHERE status = 'active' AND citizenid = ?
    LIMIT 1
  ]], { citizenid })

  return U.toInt(row and row.total or 0, 0)
end

function SE.Debts.IsLocked(citizenid)
  local threshold = U.toInt(DS.LockThreshold or 0, 0)
  if threshold <= 0 then return false end
  return SE.Debts.TotalActive(citizenid) >= threshold
end

function SE.Debts.PayFromSource(src, citizenid, payAmount)
  ensureSchema()
  citizenid = tostring(citizenid or '')
  if citizenid == '' then return false, 'CitizenID inválido.' end

  local debt = MySQL.single.await([[
    SELECT citizenid, amount, reason, meta
    FROM space_economy_debts
    WHERE status = 'active' AND citizenid = ?
    LIMIT 1
  ]], { citizenid })

  if not debt then
    return false, 'Nenhuma dívida ativa para este CitizenID.'
  end

  local remaining = U.toInt(debt.amount, 0)
  if remaining <= 0 then
    MySQL.update.await('UPDATE space_economy_debts SET status="settled", amount=0 WHERE citizenid=?', { citizenid })
    return true, 0
  end

  payAmount = U.toInt(payAmount, remaining)
  payAmount = math.min(payAmount, remaining)
  if payAmount <= 0 then return false, 'Valor inválido.' end

  if (B.GetBankBalance(src) or 0) < payAmount then
    return false, 'Saldo bancário insuficiente.'
  end

  if not B.RemoveBankMoney(src, payAmount, ('Pagamento de dívida (%s)'):format(citizenid)) then
    return false, 'Falha ao debitar no banco.'
  end

  if SE.Treasury and SE.Treasury.Modify then
    SE.Treasury.Modify(payAmount, 'pagamento_divida', { citizenid = citizenid })
  end

  local newRemaining = remaining - payAmount
  if newRemaining <= 0 then
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET amount=0, status="settled", paid = paid + ?, last_payment_at = NOW()
      WHERE citizenid=?
    ]], { payAmount, citizenid })
    return true, 0
  end

  MySQL.update.await([[
    UPDATE space_economy_debts
    SET amount = ?, paid = paid + ?, last_payment_at = NOW()
    WHERE citizenid=?
  ]], { newRemaining, payAmount, citizenid })

  return true, newRemaining
end

-- ============================================================
-- Motor: juros/avisos/mandado (stub)
-- ============================================================
local function maybeNotifyOnline(citizenid, msg, typ)
  local p = B.GetPlayerByCitizenId and B.GetPlayerByCitizenId(citizenid) or nil
  if not p then return end
  local src = p.PlayerData and p.PlayerData.source
  if not src then return end
  if B.Notify then B.Notify(src, msg, typ or 'inform', 'Dívida Ativa') end
end

local function processRow(row)
  local now = U.now()
  local meta = decodeMeta(row.meta)

  local dueTs = U.toInt(row.due_ts, 0)
  local graceTs = U.toInt(row.grace_ts, 0)
  if graceTs <= 0 then return end
  if now < graceTs then return end

  -- juros diário
  local ir = U.toNumber(DS.InterestDailyRate or 0, 0)
  if ir > 0 then
    local today = dayIndex(now)
    local lastDay = U.toInt(meta.last_interest_day or 0, 0)

    if lastDay == 0 then
      meta.last_interest_day = today
      MySQL.update.await('UPDATE space_economy_debts SET meta=? WHERE citizenid=?', { encodeMeta(meta), row.citizenid })
    elseif today > lastDay then
      local days = today - lastDay
      if days > 30 then days = 30 end

      local curAmount = U.toInt(row.amount, 0)
      if curAmount > 0 then
        local factor = (1.0 + ir) ^ days
        local newAmount = math.floor(curAmount * factor)
        if newAmount < curAmount then newAmount = curAmount end
        if newAmount ~= curAmount then
          MySQL.update.await('UPDATE space_economy_debts SET amount=? WHERE citizenid=?', { newAmount, row.citizenid })
          row.amount = newAmount
        end
      end

      meta.last_interest_day = today
      MySQL.update.await('UPDATE space_economy_debts SET meta=? WHERE citizenid=?', { encodeMeta(meta), row.citizenid })
    end
  end

  -- avisos
  local warnHours = U.toInt(DS.WarnEveryHours or 0, 0)
  if warnHours > 0 then
    local lastWarn = U.toInt(row.last_notice_at_ts or 0, 0)
    if lastWarn == 0 or (now - lastWarn) >= (warnHours * 3600) then
      local msg = ('Você possui dívida ativa: $%d (%s). Regularize no banco.'):format(U.toInt(row.amount, 0), tostring(row.reason or 'Imposto'))
      maybeNotifyOnline(row.citizenid, msg, 'warn')
      MySQL.update.await('UPDATE space_economy_debts SET last_notice_at = NOW() WHERE citizenid=?', { row.citizenid })
    end
  end

  -- mandado (stub)
  local warrantDays = U.toInt(DS.WarrantAfterDaysOverdue or 0, 0)
  if warrantDays > 0 and meta.warranted ~= true then
    local overdueDays = 0
    if dueTs > 0 and now > dueTs then
      overdueDays = math.floor((now - dueTs) / 86400)
    end
    if overdueDays >= warrantDays then
      meta.warranted = true
      meta.warranted_at = now
      MySQL.update.await('UPDATE space_economy_debts SET meta=? WHERE citizenid=?', { encodeMeta(meta), row.citizenid })

      if SE.Integrations and SE.Integrations.EmitWarrantIfNeeded then
        SE.Integrations.EmitWarrantIfNeeded(row)
      end
    end
  end
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
  if not isEnabled() then return end

  while true do
    Wait(60000)
    local rows = MySQL.query.await([[
      SELECT d.citizenid, d.amount, d.reason, d.meta,
             UNIX_TIMESTAMP(d.due_at) AS due_ts,
             UNIX_TIMESTAMP(d.grace_until) AS grace_ts,
             UNIX_TIMESTAMP(d.last_notice_at) AS last_notice_at_ts,
             COALESCE(c.name, 'Desconhecido') AS playerName
      FROM space_economy_debts d
      LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
      WHERE d.status = 'active'
        AND d.grace_until IS NOT NULL
        AND d.grace_until <= NOW()
      ORDER BY d.due_at ASC
      LIMIT 200
    ]]) or {}

    for _, row in ipairs(rows) do
      processRow(row)
    end
  end
end)
