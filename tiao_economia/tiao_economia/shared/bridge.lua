--============================================================
-- space_economy - shared/bridge.lua
-- Bridge QBOX/QBCore | Permissões | Money | Notify
-- Safe em client/server (guards com IsDuplicityVersion)
--============================================================
SE = SE or {}
SE.Bridge = SE.Bridge or {}

local B = SE.Bridge
local U = SE.Util

local IS_SERVER = IsDuplicityVersion() == true

-- Fallbacks caso utils ainda não tenha
local function safeStr(v, fallback)
  if U and U.safeStr then return U.safeStr(v, fallback) end
  if v == nil then return fallback or '' end
  return tostring(v)
end

local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d) end
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return d or 0 end
  return math.floor(v)
end

--============================================================
-- QBCore getter (cache)
--============================================================
local QBCore = nil
local function GetQBCore()
  if QBCore then return QBCore end
  if exports and exports['qb-core'] then
    local ok, core = pcall(function()
      return exports['qb-core']:GetCoreObject()
    end)
    if ok then QBCore = core end
  end
  return QBCore
end

--============================================================
-- Player getters
--============================================================
function B.IsQBX()
  return exports and exports.qbx_core ~= nil
end

function B.IsQBCore()
  return exports and exports['qb-core'] ~= nil
end

function B.GetPlayer(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end

  if exports and exports.qbx_core then
    return exports.qbx_core:GetPlayer(src)
  end

  local core = GetQBCore()
  if core and core.Functions and core.Functions.GetPlayer then
    return core.Functions.GetPlayer(src)
  end

  return nil
end

function B.GetPlayerData(src)
  if U and U.GetPlayerDataSafe then
    return U.GetPlayerDataSafe(src)
  end
  return nil
end

function B.GetCitizenId(src)
  local pd = B.GetPlayerData(src)
  return pd and pd.citizenid or nil
end

function B.GetCharNameFromPlayerData(pd)
  if not pd then return 'Desconhecido' end
  local ci = pd.charinfo or {}

  local fn = ci.firstname or ci.firstName or ci.nome
  local ln = ci.lastname  or ci.lastName  or ci.sobrenome

  if fn and ln then
    return (tostring(fn) .. ' ' .. tostring(ln))
  end

  return (pd.name or pd.PlayerName or ci.name or 'Desconhecido')
end

function B.GetCharName(src)
  return B.GetCharNameFromPlayerData(B.GetPlayerData(src))
end

-- Online only: busca player por citizenid (server tem varredura, client retorna nil)
function B.GetPlayerByCitizenId(citizenid)
  if not IS_SERVER then return nil end

  citizenid = tostring(citizenid or '')
  if citizenid == '' then return nil end

  local core = GetQBCore()
  if core and core.Functions and core.Functions.GetPlayerByCitizenId then
    return core.Functions.GetPlayerByCitizenId(citizenid)
  end

  -- fallback: varrer players online
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    local pd = B.GetPlayerData(src)
    if pd and tostring(pd.citizenid) == citizenid then
      return B.GetPlayer(src)
    end
  end

  return nil
end

function B.GetSourceByCitizenId(citizenid)
  if not IS_SERVER then return nil end
  local p = B.GetPlayerByCitizenId(citizenid)
  if not p then return nil end
  if p.PlayerData and p.PlayerData.source then return p.PlayerData.source end
  if p.source then return p.source end
  return nil
end

--============================================================
-- Permissões granulares (ACE + staff meta + job/grade)
--============================================================
function B.HasAce(src, ace)
  if not IS_SERVER then return false end
  src = tonumber(src)
  if not src or src == 0 then return true end -- console
  ace = tostring(ace or '')
  if ace == '' then return false end
  return IsPlayerAceAllowed(src, ace) == true
end

function B.IsStaffMeta(src)
  local pd = B.GetPlayerData(src)
  if not pd or not pd.metadata then return false end
  return pd.metadata.isstaff == true
end

function B.HasJobGrade(src, jobName, minGrade)
  local pd = B.GetPlayerData(src)
  if not pd or not pd.job then return false end

  jobName = tostring(jobName or '')
  if jobName == '' then return false end
  if tostring(pd.job.name or '') ~= jobName then return false end

  local grade = 0
  if type(pd.job.grade) == 'table' then
    grade = tonumber(pd.job.grade.level or pd.job.grade.grade or 0) or 0
  else
    grade = tonumber(pd.job.grade or 0) or 0
  end

  return grade >= (tonumber(minGrade) or 0)
end

function B.CanAdmin(src)
  if not IS_SERVER then return false end
  src = tonumber(src)
  if not src or src == 0 then return true end -- console

  local perm = Config and Config.Permissions or {}

  -- 1) ACE
  if perm.Ace and B.HasAce(src, perm.Ace) then
    return true
  end

  -- 2) Staff meta
  if perm.AllowStaffMeta and B.IsStaffMeta(src) then
    return true
  end

  -- 3) Job + grade
  if perm.Jobs and type(perm.Jobs) == 'table' then
    for jobName, rule in pairs(perm.Jobs) do
      if type(rule) == 'table' and B.HasJobGrade(src, jobName, rule.minGrade or 0) then
        return true
      end
    end
  end

  -- 4) QBCore legacy permission group (se existir)
  local core = GetQBCore()
  if core and core.Functions and core.Functions.HasPermission then
    if core.Functions.HasPermission(src, 'admin') or core.Functions.HasPermission(src, 'god') then
      return true
    end
  end

  return false
end

--============================================================
-- Money wrappers (bank/cash)
--============================================================
local function tryCall(fn)
  local ok, res = pcall(fn)
  if not ok then return false end
  if res == nil then return true end
  return res
end

function B.RemoveMoney(src, account, amount, reason)
  amount = toInt(amount, 0)
  if amount <= 0 then return true end

  local p = B.GetPlayer(src)
  if not p then return false end

  account = account or 'bank'
  reason = reason or 'space_economy'

  -- QBX
  if p.RemoveMoney then
    return tryCall(function() return p:RemoveMoney(account, amount, reason) end)
  end

  -- QBCore
  if p.Functions and p.Functions.RemoveMoney then
    return tryCall(function() return p.Functions.RemoveMoney(account, amount, reason) end)
  end

  return false
end

function B.AddMoney(src, account, amount, reason)
  amount = toInt(amount, 0)
  if amount <= 0 then return true end

  local p = B.GetPlayer(src)
  if not p then return false end

  account = account or 'bank'
  reason = reason or 'space_economy'

  if p.AddMoney then
    return tryCall(function() return p:AddMoney(account, amount, reason) end)
  end

  if p.Functions and p.Functions.AddMoney then
    return tryCall(function() return p.Functions.AddMoney(account, amount, reason) end)
  end

  return false
end

function B.RemoveBankMoney(src, amount, reason)
  return B.RemoveMoney(src, 'bank', amount, reason)
end

function B.AddBankMoney(src, amount, reason)
  return B.AddMoney(src, 'bank', amount, reason)
end

function B.GetBalance(src, account)
  local pd = B.GetPlayerData(src)
  local m = pd and pd.money or nil
  if not m then return 0 end
  account = account or 'bank'
  return toInt(m[account] or 0, 0)
end

function B.GetBankBalance(src)
  return B.GetBalance(src, 'bank')
end

function B.GetCashBalance(src)
  return B.GetBalance(src, 'cash')
end

--============================================================
-- Notify (server -> client)
--============================================================
function B.Notify(src, msg, ntype, title, duration)
  if not IS_SERVER then return end
  src = tonumber(src)
  if not src or src == 0 then return end

  msg = safeStr(msg, '...')
  ntype = ntype or 'inform'
  title = title or 'Economia'
  duration = toInt(duration or 3500, 3500)

  -- ox_lib notify (server -> client)
  TriggerClientEvent('ox_lib:notify', src, {
    title = title,
    description = msg,
    type = ntype,
    duration = duration,
    position = 'top'
  })
end
