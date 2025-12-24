--============================================================
-- space_economy - server/admin.lua
-- Endpoints/checagens de permissão para painel administrativo
--============================================================
SE = SE or {}
SE.Admin = SE.Admin or {}
local cfg = Config or {}
local U = SE.Util
local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][admin]^7', ...) end end

local function hasAce(src, ace)
  if not ace then return false end
  if type(global) == 'table' and global.IsPlayerAceAllowed then
    -- fallback (provavelmente indefinido) - IsPlayerAceAllowed espera player endpoint
  end
  -- FiveM native server-side
  if type(src)=='number' and IsPlayerAceAllowed and type(IsPlayerAceAllowed) == 'function' then
    local playerName = GetPlayerName(src) or ('src_'..tostring(src))
    -- IsPlayerAceAllowed espera string do player como first arg? native signature in server: IsPlayerAceAllowed(identifier, ace)
    -- Tentamos com playerName
    local ok = pcall(function() return IsPlayerAceAllowed(playerName, ace) end)
    if ok then
      local res = IsPlayerAceAllowed(playerName, ace)
      if res then return true end
    end
  end
  return false
end

local function isStaffByMeta(src)
  if cfg.Permissions and cfg.Permissions.AllowStaffMeta then
    -- tentativa QBCore/QBX: buscar metadata via export/event
    -- QBCore: QBCore.Functions.GetPlayer(source).PlayerData.metadata
    if global and global.QBCore and global.QBCore.Functions and global.QBCore.Functions.GetPlayer then
      local ok, p = pcall(function() return global.QBCore.Functions.GetPlayer(src) end)
      if ok and p and p.PlayerData and p.PlayerData.metadata and p.PlayerData.metadata.isstaff then
        return true
      end
    end
    -- fallback: consultar via TriggerEvent sync não confiável
  end
  return false
end

local function hasJobPermission(src)
  if cfg.Permissions and cfg.Permissions.Jobs then
    -- tentar obter job/grade via QBCore
    if global and global.QBCore and global.QBCore.Functions and global.QBCore.Functions.GetPlayer then
      local ok, p = pcall(function() return global.QBCore.Functions.GetPlayer(src) end)
      if ok and p and p.PlayerData and p.PlayerData.job then
        local job = p.PlayerData.job.name
        local grade = p.PlayerData.job.grade or p.PlayerData.job.grade.level or 0
        local rule = cfg.Permissions.Jobs[job]
        if rule then
          local minG = rule.minGrade or rule.mingrade or 0
          if tonumber(grade) >= tonumber(minG) then return true end
        end
      end
    end
  end
  return false
end

function SE.Admin.HasPermission(src)
  if not src then return false end
  if cfg and cfg.Permissions and cfg.Permissions.Ace then
    if hasAce(src, cfg.Permissions.Ace) then return true end
  end
  if isStaffByMeta(src) then return true end
  if hasJobPermission(src) then return true end
  return false
end

-- Abrir painel admin: valida permissão e envia client_open admin
RegisterNetEvent('space_economy:server_openAdminPanel', function()
  local src = source
  if SE.Admin.HasPermission(src) then
    TriggerClientEvent('space_economy:client_open', src, 'admin', {})
  else
    TriggerClientEvent('space_economy:client_notify', src, 'Sem permissão para abrir painel administrativo', 'error')
  end
end)

-- Request admin data (somente se tiver permissão)
RegisterNetEvent('space_economy:server_requestAdminData', function(dataType, payload)
  local src = source
  if not SE.Admin.HasPermission(src) then
    TriggerClientEvent('space_economy:client_notify', src, 'Permissão negada', 'error')
    return
  end
  dataType = tostring(dataType or '')
  if dataType == 'state' then
    TriggerClientEvent('space_economy:client_adminData', src, 'state', SE.State)
  elseif dataType == 'treasury' then
    TriggerClientEvent('space_economy:client_adminData', src, 'treasury', { balance = SE.Treasury.GetBalance() })
  elseif dataType == 'debts' then
    -- listar dívidas (um exemplo simples)
    if MySQL then
      MySQL.query('SELECT * FROM se_debts ORDER BY created_at DESC LIMIT 100', {}, function(rows)
        TriggerClientEvent('space_economy:client_adminData', src, 'debts', rows or {})
      end)
    else
      TriggerClientEvent('space_economy:client_adminData', src, 'debts', {})
    end
  else
    TriggerClientEvent('space_economy:client_adminData', src, 'unknown', {})
  end
end)
