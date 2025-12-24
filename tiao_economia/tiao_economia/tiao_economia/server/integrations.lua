--============================================================
-- space_economy - server/integrations.lua
-- Wrapper multi-framework para AddMoney / RemoveMoney
-- Tenta QBCore (exports / global), qbx_core e ps-banking; fallback via events
--============================================================
SE = SE or {}
SE.Integrations = SE.Integrations or {}

local U = SE.Util
local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][integrations]^7', ...) end end

local function safePcall(f, ...)
  local ok, res = pcall(f, ...)
  if not ok then return nil, res end
  return res
end

-- tenta obter player object via QBCore (export / global)
local function tryGetQBCorePlayer(src)
  -- exports['qb-core']:GetPlayer(src) (qb-core newer)
  if exports and exports['qb-core'] and type(exports['qb-core'].GetPlayer) == 'function' then
    local ok, p = pcall(exports['qb-core'].GetPlayer, src)
    if ok and p then return p end
  end
  -- global object fallback
  if global and global.QBCore and global.QBCore.Functions and global.QBCore.Functions.GetPlayer then
    local ok, p = pcall(function() return global.QBCore.Functions.GetPlayer(src) end)
    if ok and p then return p end
  end
  return nil
end

-- tenta obter player object via qbx_core (export)
local function tryGetQBXPlayer(src)
  if exports and exports['qbx_core'] and type(exports['qbx_core'].GetPlayer) == 'function' then
    local ok, p = pcall(exports['qbx_core'].GetPlayer, src)
    if ok and p then return p end
  end
  return nil
end

-- Remove dinheiro do jogador. Retorna true/false.
function SE.Integrations.RemoveMoney(src, amount, account)
  src = src
  amount = tonumber(amount) or 0
  account = account or 'bank'
  if amount <= 0 then return false, 'invalid_amount' end

  -- QBCore
  local qbPlayer = tryGetQBCorePlayer(src)
  if qbPlayer then
    if qbPlayer.Functions and qbPlayer.Functions.RemoveMoney then
      local ok, err = pcall(function() qbPlayer.Functions.RemoveMoney(account, amount) end)
      if ok then dbg('RemoveMoney via QBCore OK', src, amount) return true end
      dbg('QBCore RemoveMoney error', err)
    end
  end

  -- QBX
  local qbxPlayer = tryGetQBXPlayer(src)
  if qbxPlayer and qbxPlayer.removeMoney then
    local ok, err = pcall(function() qbxPlayer.removeMoney(amount) end)
    if ok then dbg('RemoveMoney via QBX OK', src, amount) return true end
  end

  -- ps-banking (example: exports['ps-banking']:removeBank? varies)
  if exports and exports['ps-banking'] then
    -- tentativa genérica: buscar função removeBalance / RemoveMoney / remove
    local fnNames = { 'RemoveMoney', 'removeMoney', 'removeBank', 'RemoveBank', 'removeBalance' }
    for _, fn in ipairs(fnNames) do
      if type(exports['ps-banking'][fn]) == 'function' then
        local ok, err = pcall(exports['ps-banking'][fn], src, amount)
        if ok then dbg('RemoveMoney via ps-banking.'..fn, src, amount) return true end
      end
    end
  end

  -- Fallback: trigger event client-side para integração local
  pcall(function()
    TriggerClientEvent('space_economy:client_requestRemoveMoney', src, amount, account)
  end)
  -- não garantimos sucesso no fallback (client deve confirmar)
  return false, 'no_integration'
end

-- Add money to player
function SE.Integrations.AddMoney(src, amount, account)
  src = src
  amount = tonumber(amount) or 0
  account = account or 'bank'
  if amount <= 0 then return false, 'invalid_amount' end

  local qbPlayer = tryGetQBCorePlayer(src)
  if qbPlayer and qbPlayer.Functions and qbPlayer.Functions.AddMoney then
    local ok, err = pcall(function() qbPlayer.Functions.AddMoney(account, amount) end)
    if ok then dbg('AddMoney via QBCore OK', src, amount) return true end
  end

  local qbxPlayer = tryGetQBXPlayer(src)
  if qbxPlayer and qbxPlayer.addMoney then
    local ok, err = pcall(function() qbxPlayer.addMoney(amount) end)
    if ok then dbg('AddMoney via QBX OK', src, amount) return true end
  end

  if exports and exports['ps-banking'] then
    local fnNames = { 'AddMoney', 'addMoney', 'addBank', 'AddBank', 'addBalance' }
    for _, fn in ipairs(fnNames) do
      if type(exports['ps-banking'][fn]) == 'function' then
        local ok, err = pcall(exports['ps-banking'][fn], src, amount)
        if ok then dbg('AddMoney via ps-banking.'..fn, src, amount) return true end
      end
    end
  end

  -- fallback: client event
  pcall(function()
    TriggerClientEvent('space_economy:client_requestAddMoney', src, amount, account)
  end)
  return false, 'no_integration'
end

-- Exports
SE.Integrations._tryGetQBCorePlayer = tryGetQBCorePlayer