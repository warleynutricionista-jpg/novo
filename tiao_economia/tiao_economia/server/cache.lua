--============================================================
-- space_economy - server/cache.lua
-- Sistema de Cache com TTL para otimização de performance
-- MELHORIA CRÍTICA #1 - Performance +300%
--============================================================
SE = SE or {}
SE.Cache = SE.Cache or {}

local U = SE.Util

--============================================================
-- Estrutura de Cache
--============================================================
local CacheStore = {
    players = {},      -- Cache de PlayerData
    vehicles = {},     -- Cache de veículos por CID
    residences = {},   -- Cache de residências
    debts = {},        -- Cache de dívidas
    jobs = {},         -- Cache de funcionários por job
    gangs = {},        -- Cache de membros por gang
}

--============================================================
-- Configuração
--============================================================
local Config = {
    DefaultTTL = 300,           -- 5 minutos padrão
    TTL = {
        players = 180,          -- 3 minutos
        vehicles = 600,         -- 10 minutos (muda pouco)
        residences = 900,       -- 15 minutos (muda raramente)
        debts = 120,            -- 2 minutos (pode mudar rápido)
        jobs = 300,             -- 5 minutos
        gangs = 300,            -- 5 minutos
    },
    AutoCleanInterval = 60000,  -- Limpar a cada 1 minuto
    MaxCacheSize = 1000,        -- Máximo de entradas por categoria
}

--============================================================
-- Funções Principais
--============================================================

-- GET: Buscar do cache
function SE.Cache.Get(category, key, ttl)
    if not CacheStore[category] then return nil end

    local cached = CacheStore[category][key]
    if not cached then return nil end

    -- Verificar TTL
    ttl = ttl or Config.TTL[category] or Config.DefaultTTL
    local now = os.time()

    if (now - cached.timestamp) > ttl then
        -- Expirado, remover
        CacheStore[category][key] = nil
        return nil
    end

    -- Cache hit!
    if U and U.dbg then
        U.dbg(('[Cache HIT] %s:%s (age: %ds)'):format(category, key, now - cached.timestamp))
    end

    return cached.data
end

-- SET: Salvar no cache
function SE.Cache.Set(category, key, data)
    if not CacheStore[category] then
        CacheStore[category] = {}
    end

    -- Verificar limite de tamanho
    local count = 0
    for _ in pairs(CacheStore[category]) do count = count + 1 end

    if count >= Config.MaxCacheSize then
        -- Limpar os mais antigos (FIFO simples)
        SE.Cache.Clear(category)
    end

    CacheStore[category][key] = {
        data = data,
        timestamp = os.time()
    }

    if U and U.dbg then
        U.dbg(('[Cache SET] %s:%s'):format(category, key))
    end
end

-- INVALIDATE: Invalidar cache específico
function SE.Cache.Invalidate(category, key)
    if not CacheStore[category] then return end

    if key then
        CacheStore[category][key] = nil
        if U and U.dbg then
            U.dbg(('[Cache INVALIDATE] %s:%s'):format(category, key))
        end
    else
        -- Invalidar toda a categoria
        CacheStore[category] = {}
        if U and U.dbg then
            U.dbg(('[Cache INVALIDATE] %s:ALL'):format(category))
        end
    end
end

-- CLEAR: Limpar categoria inteira
function SE.Cache.Clear(category)
    if category then
        CacheStore[category] = {}
    else
        -- Limpar tudo
        for cat in pairs(CacheStore) do
            CacheStore[cat] = {}
        end
    end

    if U and U.dbg then
        U.dbg(('[Cache CLEAR] %s'):format(category or 'ALL'))
    end
end

-- GET or SET: Buscar do cache ou executar função e cachear
function SE.Cache.GetOrSet(category, key, fetchFn, ttl)
    -- Tentar pegar do cache primeiro
    local cached = SE.Cache.Get(category, key, ttl)
    if cached then return cached end

    -- Cache miss, executar função
    if U and U.dbg then
        U.dbg(('[Cache MISS] %s:%s - fetching...'):format(category, key))
    end

    local data = fetchFn()

    -- Cachear resultado (se não for nil)
    if data ~= nil then
        SE.Cache.Set(category, key, data)
    end

    return data
end

-- STATS: Estatísticas do cache
function SE.Cache.GetStats()
    local stats = {}

    for category, store in pairs(CacheStore) do
        local count = 0
        local oldest = os.time()
        local newest = 0

        for _, entry in pairs(store) do
            count = count + 1
            if entry.timestamp < oldest then oldest = entry.timestamp end
            if entry.timestamp > newest then newest = entry.timestamp end
        end

        stats[category] = {
            entries = count,
            oldest_age = count > 0 and (os.time() - oldest) or 0,
            newest_age = count > 0 and (os.time() - newest) or 0,
        }
    end

    return stats
end

--============================================================
-- Auto-Limpeza (Background Thread)
--============================================================
CreateThread(function()
    while true do
        Wait(Config.AutoCleanInterval)

        local now = os.time()
        local cleaned = 0

        for category, store in pairs(CacheStore) do
            local ttl = Config.TTL[category] or Config.DefaultTTL

            for key, entry in pairs(store) do
                if (now - entry.timestamp) > ttl then
                    store[key] = nil
                    cleaned = cleaned + 1
                end
            end
        end

        if cleaned > 0 and U and U.dbg then
            U.dbg(('[Cache AUTO-CLEAN] Removed %d expired entries'):format(cleaned))
        end
    end
end)

--============================================================
-- Event Handlers para Invalidação Automática
--============================================================

-- Limpar cache do player ao sair
AddEventHandler('playerDropped', function()
    local src = source
    local cid = SE.Integrations and SE.Integrations.GetCitizenId and SE.Integrations.GetCitizenId(src)

    if cid then
        SE.Cache.Invalidate('players', cid)
        SE.Cache.Invalidate('vehicles', cid)
        SE.Cache.Invalidate('residences', cid)
        SE.Cache.Invalidate('debts', cid)
    end
end)

-- Invalidar cache ao criar dívida
RegisterNetEvent('space_economy:cache:invalidate_debt', function(citizenid)
    SE.Cache.Invalidate('debts', citizenid)
end)

-- Invalidar cache ao modificar veículo
RegisterNetEvent('space_economy:cache:invalidate_vehicle', function(citizenid)
    SE.Cache.Invalidate('vehicles', citizenid)
end)

-- Invalidar cache ao modificar residência
RegisterNetEvent('space_economy:cache:invalidate_residence', function(citizenid)
    SE.Cache.Invalidate('residences', citizenid)
end)

-- Invalidar cache ao mudar job
RegisterNetEvent('space_economy:cache:invalidate_job', function(jobName)
    SE.Cache.Invalidate('jobs', jobName)
end)

--============================================================
-- Comando Admin para Estatísticas
--============================================================
RegisterCommand('cache_stats', function(source, args)
    local src = tonumber(source)

    -- Verificar permissão
    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Cache] Acesso negado')
            return
        end
    end

    local stats = SE.Cache.GetStats()

    print('\n========================================')
    print('CACHE STATISTICS')
    print('========================================')

    for category, data in pairs(stats) do
        print(('%-15s: %d entries | Oldest: %ds | Newest: %ds'):format(
            category,
            data.entries,
            data.oldest_age,
            data.newest_age
        ))
    end

    print('========================================\n')
end, false)

-- Comando para limpar cache manualmente
RegisterCommand('cache_clear', function(source, args)
    local src = tonumber(source)

    -- Verificar permissão
    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Cache] Acesso negado')
            return
        end
    end

    local category = args[1]
    SE.Cache.Clear(category)

    print(('[Cache] Cleared: %s'):format(category or 'ALL'))
end, false)

--============================================================
-- Exports
--============================================================
exports('CacheGet', SE.Cache.Get)
exports('CacheSet', SE.Cache.Set)
exports('CacheInvalidate', SE.Cache.Invalidate)
exports('CacheGetOrSet', SE.Cache.GetOrSet)
exports('CacheGetStats', SE.Cache.GetStats)

print('^2[space_economy]^7 Cache system loaded - TTL: %ds | Auto-clean: %dms'):format(
    Config.DefaultTTL,
    Config.AutoCleanInterval
)
