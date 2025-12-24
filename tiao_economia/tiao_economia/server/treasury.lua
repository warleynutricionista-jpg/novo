--============================================================
-- space_economy - server/treasury.lua
-- Cofre Público (tesouro) | Ajustes idempotentes | Logs
--============================================================
SE = SE or {}
SE.Treasury = SE.Treasury or {}

local U = SE.Util
local S = SE.State

local function markDirty()
  if SE.Server and SE.Server.MarkDirty then
    SE.Server.MarkDirty()
  else
    S.dirty = true -- fallback
  end
end

local function logVault(reason, amount, before, after, meta)
  if SE.Log then
    SE.Log('vault', ('Cofre %s %d (antes=%d depois=%d)'):format(reason or 'ajuste', amount, before, after), meta)
  else
    U.dbg(('Cofre %s %d (antes=%d depois=%d)'):format(reason or 'ajuste', amount, before, after))
  end
end

--============================================================
-- API
--============================================================
function SE.Treasury.GetBalance()
  return U.toInt(S.vaultBalance, 0)
end

function SE.Treasury.SetBalance(value, reason, meta)
  value = U.toInt(value, 0)
  if value < 0 then value = 0 end

  local before = U.toInt(S.vaultBalance, 0)
  if before == value then return value end

  S.vaultBalance = value
  markDirty()

  logVault(reason or 'set', (value - before), before, value, meta)
  return value
end

function SE.Treasury.Modify(amount, reason, meta)
  amount = U.toInt(amount, 0)
  if amount == 0 then return U.toInt(S.vaultBalance, 0) end

  local before = U.toInt(S.vaultBalance, 0)
  local after = before + amount
  if after < 0 then after = 0 end

  if after == before then return before end

  S.vaultBalance = after
  markDirty()

  logVault(reason or 'ajuste', amount, before, after, meta)

  -- métrica diária opcional (módulo future-proof)
  if SE.Metrics and SE.Metrics.Add then
    SE.Metrics.Add('vault_ops', 1)
    if amount > 0 then SE.Metrics.Add('vault_in', amount) end
  end

  return after
end

function SE.Treasury.Deposit(amount, reason, meta)
  return SE.Treasury.Modify(U.toInt(amount, 0), reason or 'deposito', meta)
end

function SE.Treasury.Withdraw(amount, reason, meta)
  amount = U.toInt(amount, 0)
  if amount <= 0 then return SE.Treasury.GetBalance() end
  return SE.Treasury.Modify(-amount, reason or 'saque', meta)
end
