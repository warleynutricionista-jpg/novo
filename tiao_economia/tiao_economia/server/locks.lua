--============================================================
-- space_economy - server/locks.lua
-- Mutex simples em memória para operações críticas
--============================================================
SE = SE or {}
SE.Locks = SE.Locks or {}

local locks = {}

local function nowMs()
  return math.floor(os.time() * 1000)
end

-- Tenta obter lock sem bloquear. Retorna true se obteve.
function SE.Locks.TryLock(key, owner, ttlMs)
  key = tostring(key)
  owner = tostring(owner or 'unknown')
  ttlMs = tonumber(ttlMs) or 30000
  local entry = locks[key]
  if entry then
    -- expirada?
    if entry.expire_at and nowMs() > entry.expire_at then
      locks[key] = { owner = owner, expire_at = nowMs() + ttlMs }
      return true
    end
    return false
  end
  locks[key] = { owner = owner, expire_at = nowMs() + ttlMs }
  return true
end

-- Libera lock se for o owner (ou força se force==true)
function SE.Locks.Release(key, owner, force)
  key = tostring(key)
  local entry = locks[key]
  if not entry then return false end
  if force or tostring(owner) == tostring(entry.owner) then
    locks[key] = nil
    return true
  end
  return false
end

-- Acquire blocking com timeout (não bloqueante real, mas poll com Wait)
function SE.Locks.AcquireBlocking(key, owner, ttlMs, waitTimeoutMs, pollMs)
  key = tostring(key)
  owner = tostring(owner or 'unknown')
  ttlMs = tonumber(ttlMs) or 30000
  waitTimeoutMs = tonumber(waitTimeoutMs) or 5000
  pollMs = tonumber(pollMs) or 50
  local start = nowMs()
  while true do
    local ok = SE.Locks.TryLock(key, owner, ttlMs)
    if ok then return true end
    if nowMs() - start > waitTimeoutMs then return false end
    Wait(pollMs)
  end
end

-- Helper que executa um callback dentro do lock (retorna boolean, result)
function SE.Locks.WithLock(key, owner, ttlMs, waitTimeoutMs, cb)
  local ok = SE.Locks.AcquireBlocking(key, owner, ttlMs, waitTimeoutMs)
  if not ok then return false, 'lock_timeout' end
  local ok2, res = pcall(cb)
  SE.Locks.Release(key, owner, true)
  if not ok2 then return false, res end
  return true, res
end

-- Debug helper
function SE.Locks._dump()
  return locks
end
