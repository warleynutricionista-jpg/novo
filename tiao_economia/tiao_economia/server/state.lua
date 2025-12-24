--============================================================
-- space_economy - server/state.lua
-- Carrega e persiste SE.State no banco (oxmysql)
--============================================================
SE = SE or {}
SE.State = SE.State or {}

local U = SE.Util
local cfg = Config or {}

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[space_economy][state]^7', ...) end
end

local STATE_KEY = 'space_economy_state_v1'

-- Serializa o SE.State para JSON (guardas simples)
local function serializeState()
  local ok, json = pcall(function() return json.encode(SE.State) end)
  if ok then return json end
  return '{}'
end

-- Desserializa JSON para SE.State (merge)
local function deserializeState(j)
  if not j or j == '' then return end
  local ok, tbl = pcall(function() return json.decode(j) end)
  if not ok or type(tbl) ~= 'table' then return end
  for k,v in pairs(tbl) do SE.State[k] = v end
end

function SE.State.LoadState()
  dbg('Loading state from DB...')
  if not MySQL then
    dbg('MySQL não disponível, abortando LoadState')
    return
  end

  MySQL.query('SELECT `value` FROM se_state WHERE `key_name` = ? LIMIT 1', {STATE_KEY}, function(result)
    if result and result[1] and result[1].value then
      deserializeState(result[1].value)
      dbg('State loaded from DB')
    else
      dbg('Nenhum state persistido encontrado, usando defaults em memória')
    end
  end)
end

function SE.State.SaveState()
  if not MySQL then
    dbg('MySQL não disponível, abortando SaveState')
    return
  end
  local payload = serializeState()
  -- Upsert: tenta atualizar, se não existir insere
  MySQL.execute('INSERT INTO se_state (id, key_name, value) VALUES (1, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', {STATE_KEY, payload}, function(affected)
    SE.State.dirty = false
    dbg('State salvo no DB')
  end)
end

-- Periodic persistence
CreateThread(function()
  local interval = (Config and Config.Persistence and Config.Persistence.IntervalMs) or 60000
  while true do
    Wait(interval)
    if SE.State.dirty then
      pcall(function() SE.State.SaveState() end)
    end
  end
end)

-- Expor helper para marcar dirty
function SE.State.MarkDirty()
  SE.State.dirty = true
end

-- Auto-load on resource start
CreateThread(function()
  Wait(500)
  SE.State.LoadState()
end)
