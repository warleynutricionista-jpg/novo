--============================================================
-- space_economy - server/treasury.lua
-- Gestão do tesouro da cidade (persistente)
--============================================================
SE = SE or {}
SE.Treasury = SE.Treasury or {}
local U = SE.Util
local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][treasury]^7', ...) end end

-- Garante existência do vaultBalance
SE.State = SE.State or {}
SE.State.vaultBalance = tonumber(SE.State.vaultBalance) or 0

local function persistVault()
  if not MySQL then
    dbg('MySQL não disponível, persistência do tesouro falhada')
    return
  end
  local balance = tonumber(SE.State.vaultBalance) or 0
  MySQL.execute('INSERT INTO se_treasury (id, balance) VALUES (1, ?) ON DUPLICATE KEY UPDATE balance = VALUES(balance)', { balance }, function() dbg('Tesouro persistido:', balance) end)
end

function SE.Treasury.GetBalance()
  return tonumber(SE.State.vaultBalance) or 0
end

function SE.Treasury.Add(amount, opts)
  amount = tonumber(amount) or 0
  if amount == 0 then return false end
  SE.State.vaultBalance = (tonumber(SE.State.vaultBalance) or 0) + amount
  SE.State.MarkDirty()
  persistVault()
  dbg(('Adicionar ao tesouro: %s | novo saldo: %s'):format(tostring(amount), tostring(SE.State.vaultBalance)))
  return true
end

function SE.Treasury.Remove(amount, opts)
  amount = tonumber(amount) or 0
  if amount == 0 then return false end
  local bal = tonumber(SE.State.vaultBalance) or 0
  if amount > bal then return false, 'InsufficientFunds' end
  SE.State.vaultBalance = bal - amount
  SE.State.MarkDirty()
  persistVault()
  dbg(('Remover do tesouro: %s | novo saldo: %s'):format(tostring(amount), tostring(SE.State.vaultBalance)))
  return true
end

-- Carregar saldo inicial do DB (chamado pela state loader opcionalmente)
CreateThread(function()
  Wait(800)
  if not MySQL then return end
  MySQL.query('SELECT balance FROM se_treasury WHERE id = 1 LIMIT 1', {}, function(result)
    if result and result[1] and result[1].balance then
      SE.State.vaultBalance = tonumber(result[1].balance) or SE.State.vaultBalance
      dbg('Tesouro carregado do DB:', SE.State.vaultBalance)
    end
  end)
end)
