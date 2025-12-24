SE = SE or {}
SE.Util = SE.Util or {}

local U = SE.Util

function U.dbg(...)
  if Config and Config.Debug then
    print('^3[space_economy]^7', ...)
  end
end

function U.toNumber(v, default)
  local n = tonumber(v)
  if n == nil then return default or 0 end
  if n ~= n or n == math.huge or n == -math.huge then return default or 0 end
  return n
end

function U.toInt(v, default)
  return math.floor(U.toNumber(v, default))
end

function U.safeStr(v, default)
  if v == nil then return default or '' end
  if type(v) == 'string' then
    if v == '' then return default or '' end
    return v
  end
  return tostring(v)
end

function U.trim(s)
  s = U.safeStr(s, '')
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  return s
end

function U.safeJsonDecode(s)
  if type(s) ~= 'string' or s == '' then return nil end
  local ok, res = pcall(json.decode, s)
  if not ok then return nil end
  return res
end

function U.safeJsonEncode(t)
  if t == nil then return '{}' end
  local ok, res = pcall(json.encode, t)
  if not ok then return '{}' end
  return res
end

function U.now()
  return os.time()
end

function U.tsToIso(ts)
  ts = U.toInt(ts, os.time())
  return os.date('!%Y-%m-%d %H:%M:%S', ts)
end

function U.clamp(n, a, b)
  n = U.toNumber(n, a)
  if n < a then return a end
  if n > b then return b end
  return n
end

-- deep access seguro: U.cfg("Inflation.MinRate", 0.8)
function U.cfg(path, default, root)
  root = root or Config
  if type(root) ~= 'table' then return default end
  if type(path) ~= 'string' or path == '' then return default end

  local cur = root
  for seg in path:gmatch('[^%.]+') do
    if type(cur) ~= 'table' then return default end
    cur = cur[seg]
    if cur == nil then return default end
  end
  return cur
end

-- Guard padrão: sempre usar para obter PlayerData sem nil
function U.GetPlayerDataSafe(src)
  if not src then return nil end

  if exports and exports.qbx_core then
    local p = exports.qbx_core:GetPlayer(src)
    if p and p.PlayerData then return p.PlayerData end
  end

  if exports and exports['qb-core'] then
    local QBCore = exports['qb-core']:GetCoreObject()
    local p = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer(src)
    if p and p.PlayerData then return p.PlayerData end
  end

  return nil
end
