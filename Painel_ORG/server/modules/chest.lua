-- server/modules/chest.lua
-- Painel_ORG – Logs do baú (thunder_orgs_logs)
-- Compatível com Qbox/QBCore (opcional), ox_lib e oxmysql (via DB.* do bridge_core)
-- NENHUM CREATE TABLE e NENHUM MySQL.* direto aqui.

---------------------------------------
-- Core (opcional)
---------------------------------------
local Core = nil
do
    local ok, obj = pcall(function()
        if GetResourceState('qbx-core') == 'started' and exports['qbx-core'] and exports['qbx-core'].GetCoreObject then
            return exports['qbx-core']:GetCoreObject()
        end
        if GetResourceState('qb-core') == 'started' and exports['qb-core'] and exports['qb-core'].GetCoreObject then
            return exports['qb-core']:GetCoreObject()
        end
        return nil
    end)
    if ok and obj then Core = obj end
end

---------------------------------------
-- Helpers (usam os helpers do bridge se existirem)
---------------------------------------
local function getCitizenId(src)
    if type(getUserId) == 'function' then
        return getUserId(src) -- do bridge_core (pref.)
    end
    if Core and Core.Functions then
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid then
            return Ply.PlayerData.citizenid
        end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:') then return id end
    end
    return nil
end

local function getSourceByCitizenId(citizenid)
    if type(getUserSource) == 'function' then
        return getUserSource(citizenid) -- do bridge_core (pref.)
    end
    if not Core or not Core.Functions then return nil end
    -- fallback: varre online
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid == citizenid then
            return src
        end
    end
    return nil
end

local function getIdentityNameByCitizenId(citizenid)
    local src = getSourceByCitizenId(citizenid)
    if src and type(getUserIdentity) == 'function' then
        local idt = getUserIdentity(src)
        if idt then
            local first = idt.firstname or ''
            local last  = idt.lastname or ''
            local composed = ('%s %s'):format(first, last):gsub('%s+$','')
            return (composed ~= '' and composed) or (idt.name or 'N/A')
        end
    end
    if src and Core and Core.Functions then
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.charinfo then
            local c = Ply.PlayerData.charinfo
            return ('%s %s'):format(c.firstname or 'N/A', c.lastname or '')
        end
    end
    -- offline: use um placeholder legível
    return ('CID:%s'):format(citizenid or '?')
end

---------------------------------------
-- Cache
---------------------------------------
local chestLogCache   = {} -- [org] = { {id,name,role,message,time,expire_at}, ... }
local pendingToFlush  = {} -- [org] = { entries pendentes de gravar }

---------------------------------------
-- Legacy Tunnel (compat com client antigo)
---------------------------------------
RegisterTunnel = RegisterTunnel or {}

function RegisterTunnel.getLogs()
    local src = source
    local cid = getCitizenId(src)
    if not cid then return {} end

    if not Organizations or not Organizations.Members or not Organizations.Members[cid] then
        return {}
    end

    local org = Organizations.Members[cid].groupType
    if not org or org == '' then return {} end

    -- cache hit
    if chestLogCache[org] then
        return chestLogCache[org]
    end

    -- carrega do banco
    local list = {}
    if DB and DB.GetChestLogs then
        local rows = DB.GetChestLogs(org) or {}
        for i = 1, #rows do
            local r = rows[i]
            list[#list+1] = {
                id        = r.user_identifier,
                name      = r.name or 'Desconhecido',
                role      = r.role or 'Sem cargo',
                message   = r.description or '',
                time      = r.date or '',
                expire_at = tonumber(r.expire_at) or 0
            }
        end
    end

    chestLogCache[org] = list
    return list
end

---------------------------------------
-- ox_lib callback (client novo)
---------------------------------------
if lib and lib.callback and lib.callback.register then
    lib.callback.register('Painel_ORG:chest:getLogs', function(source)
        return RegisterTunnel.getLogs()
    end)
end

---------------------------------------
-- Export para registrar logs do baú
-- action = 'withdraw' | 'deposit' (qualquer outra vira 'deposit')
-- item   = label do item
-- amount = number
---------------------------------------
exports('addLogChest', function(user_ref, action, item, amount)
    -- user_ref pode ser source (number) ou citizenid (string)
    local citizenid = nil
    if type(user_ref) == 'number' then
        citizenid = getCitizenId(user_ref)
    elseif type(user_ref) == 'string' then
        citizenid = user_ref
    end
    if not citizenid then
        print('[Painel_ORG:chest] addLogChest: citizenid inválido')
        return
    end
    if not action or not item or not amount then
        print('[Painel_ORG:chest] addLogChest: parâmetros ausentes')
        return
    end

    local member = Organizations and Organizations.Members and Organizations.Members[citizenid]
    if not member or not member.groupType then return end

    local org  = member.groupType
    local role = 'Sem cargo'
    if Config and Config.Groups and Config.Groups[org] and Config.Groups[org].List and member.group then
        local cfg = Config.Groups[org].List[member.group]
        if cfg and cfg.prefix then role = cfg.prefix end
    end

    local fullName = getIdentityNameByCitizenId(citizenid)
    local act = (tostring(action) == 'withdraw') and 'Retirou' or 'Guardou'
    local msg = ('%s %dx %s'):format(act, tonumber(amount) or 0, item or 'desconhecido')

    local entry = {
        id        = citizenid,
        name      = fullName,
        role      = role,
        message   = msg,
        time      = os.date('%d/%m/%Y %X'),
        expire_at = os.time() + (((Config and Config.Main and Config.Main.clearChestLogs) or 15) * 86400)
    }

    chestLogCache[org]  = chestLogCache[org] or {}
    pendingToFlush[org] = pendingToFlush[org] or {}

    chestLogCache[org][#chestLogCache[org] + 1] = entry
    pendingToFlush[org][#pendingToFlush[org] + 1] = entry
end)

---------------------------------------
-- Flush periódico (grava pendências no DB)
---------------------------------------
local function flushChestLogs()
    if not DB or not DB.AddChestLog then return end
    for org, logs in pairs(pendingToFlush) do
        if logs and #logs > 0 then
            for _, e in ipairs(logs) do
                DB.AddChestLog(
                    org,
                    tostring(e.id or ''),
                    e.role or 'Sem cargo',
                    e.name or 'Desconhecido',
                    e.message or '',
                    e.time or os.date('%d/%m/%Y %X'),
                    tonumber(e.expire_at) or (os.time() + 15 * 86400)
                )
            end
            pendingToFlush[org] = {}
        end
    end
end

CreateThread(function()
    while true do
        flushChestLogs()
        Wait(30000) -- 30s
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        print(('^2[%s]^0 Salvando logs de baú pendentes...'):format(res))
        flushChestLogs()
    end
end)
