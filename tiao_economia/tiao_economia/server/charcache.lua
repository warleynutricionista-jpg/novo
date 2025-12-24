--============================================================
-- space_economy - server/charcache.lua
-- Cache de nomes (citizenid -> nome personagem) persistente
--============================================================
SE = SE or {}
SE.CharCache = SE.CharCache or {}

local U = SE.Util
local B = SE.Bridge

local ready = false

local function ensureSchema()
  if ready then return end
  ready = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_charcache (
      citizenid VARCHAR(64) PRIMARY KEY,
      name VARCHAR(120) NOT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])
end

local function normalizeName(name)
  name = U.trim(U.safeStr(name, ''))
  if name == '' then name = 'Desconhecido' end
  if #name > 120 then name = name:sub(1, 120) end
  return name
end

--============================================================
-- API
--============================================================
function SE.CharCache.Upsert(src)
  if not src or src == 0 then return false end
  ensureSchema()

  local cid = B.GetCitizenId(src)
  if not cid then return false end
  cid = tostring(cid)

  local pd = U.GetPlayerDataSafe(src)
  local name = normalizeName(B.GetCharNameFromPlayerData(pd))

  MySQL.update.await([[
    INSERT INTO space_economy_charcache (citizenid, name)
    VALUES (?, ?)
    ON DUPLICATE KEY UPDATE name = VALUES(name)
  ]], { cid, name })

  return true
end

function SE.CharCache.GetName(citizenid)
  ensureSchema()

  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return nil end

  local row = MySQL.single.await('SELECT name FROM space_economy_charcache WHERE citizenid = ?', { citizenid })
  return row and row.name or nil
end

-- Resolve: tenta online -> cache -> fallback
function SE.CharCache.ResolveName(citizenid)
  citizenid = U.trim(U.safeStr(citizenid, ''))
  if citizenid == '' then return 'Desconhecido' end

  -- tenta online
  local p = B.GetPlayerByCitizenId(citizenid)
  if p then
    local src = p.PlayerData and p.PlayerData.source
    if src then
      local pd = U.GetPlayerDataSafe(src)
      local name = normalizeName(B.GetCharNameFromPlayerData(pd))
      -- atualiza cache em background
      CreateThread(function()
        SE.CharCache.Upsert(src)
      end)
      return name
    end
  end

  -- cache
  local cached = SE.CharCache.GetName(citizenid)
  if cached and cached ~= '' then return cached end

  return 'Desconhecido'
end

-- Prefetch: recebe uma lista de citizenid e retorna map {citizenid=name}
function SE.CharCache.Prefetch(citizenids)
  ensureSchema()
  local out = {}

  if type(citizenids) ~= 'table' or #citizenids == 0 then
    return out
  end

  -- monta IN (?, ?, ?)
  local params = {}
  local marks = {}
  for _, cid in ipairs(citizenids) do
    cid = U.trim(U.safeStr(cid, ''))
    if cid ~= '' then
      params[#params+1] = cid
      marks[#marks+1] = '?'
    end
  end

  if #params == 0 then return out end

  local q = ('SELECT citizenid, name FROM space_economy_charcache WHERE citizenid IN (%s)'):format(table.concat(marks, ','))
  local rows = MySQL.query.await(q, params) or {}

  for _, r in ipairs(rows) do
    out[tostring(r.citizenid)] = normalizeName(r.name)
  end

  return out
end

--============================================================
-- Hooks de atualização automática
--============================================================

-- QBCore
AddEventHandler('QBCore:Server:OnPlayerLoaded', function(src)
  -- alguns cores chamam sem param (source), garantimos:
  src = src or source
  CreateThread(function()
    Wait(500)
    SE.CharCache.Upsert(src)
  end)
end)

-- QBX (fallback genérico)
AddEventHandler('playerJoining', function()
  local src = source
  CreateThread(function()
    Wait(3000)
    SE.CharCache.Upsert(src)
  end)
end)

-- Segurança: em restart de resource, garante tabela
CreateThread(function()
  while not MySQL do Wait(200) end
  ensureSchema()
end)
