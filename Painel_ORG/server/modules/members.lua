-- server/modules/members.lua
-- Painel_ORG – Membros (lista, convite, promover, rebaixar, demitir)
-- Compatível com Qbox/QBCore (opcional), ox_lib e oxmysql.
-- Evita MySQL.prepare; usa .await com tabela de parâmetros.

---------------------------------------
-- Core (opcional)
---------------------------------------
local Core = nil
do
    local ok, obj = pcall(function()
        if GetResourceState('qbx-core') == 'started'
            and exports['qbx-core']
            and exports['qbx-core'].GetCoreObject
        then
            return exports['qbx-core']:GetCoreObject()
        end
        if GetResourceState('qb-core') == 'started'
            and exports['qb-core']
            and exports['qb-core'].GetCoreObject
        then
            return exports['qb-core']:GetCoreObject()
        end
        return nil
    end)
    if ok and obj then Core = obj end
end

---------------------------------------
-- Tabelas
---------------------------------------
local TBL_PINFO = 'thunder_orgs_player_infos' -- citizenid (PK), organization, role, joindate, lastlogin, timeplayed
local TBL_BL    = 'thunder_orgs_blacklist'    -- citizenid (PK), expires_at

-- Garante blacklist; player_infos já é criada no bridge_core (EnsureSchema)
-- IMPORTANTE: usar MySQL.query.await para DDL
MySQL.query.await(([[ 
    CREATE TABLE IF NOT EXISTS `%s` (
        `citizenid`  VARCHAR(80) NOT NULL,
        `expires_at` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]):format(TBL_BL), {})

---------------------------------------
-- Helpers
---------------------------------------
local function getPlayer(srcOrCid)
    if type(srcOrCid) == 'number' then
        return (Core and Core.Functions and Core.Functions.GetPlayer(srcOrCid)) or nil
    end
    if Core and Core.Functions then
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local Ply = Core.Functions.GetPlayer(src)
            if Ply and Ply.PlayerData and Ply.PlayerData.citizenid == srcOrCid then
                return Ply
            end
        end
    end
    return nil
end

local function getCitizenId(srcOrCid)
    if type(srcOrCid) == 'string' then return srcOrCid end
    if type(getUserId) == 'function' then return getUserId(srcOrCid) end -- do bridge_core
    local Ply = getPlayer(srcOrCid)
    return Ply and Ply.PlayerData and Ply.PlayerData.citizenid or nil
end

local function getSourceByCitizenId(citizenid)
    if type(getUserSource) == 'function' then
        return getUserSource(citizenid) -- do bridge_core
    end
    if not Core or not Core.Functions then return nil end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid == citizenid then
            return src
        end
    end
    return nil
end

local function getNameByCitizenId(citizenid)
    -- via helper do bridge_core
    if type(getUserIdentity) == 'function' then
        local src = getSourceByCitizenId(citizenid)
        if src then
            local idt = getUserIdentity(src)
            if idt then
                local first = idt.firstname or ''
                local last  = idt.lastname or ''
                local composed = ('%s %s'):format(first, last):gsub('%s+$','')
                if composed ~= '' then return composed end
                if idt.name and idt.name ~= '' then return idt.name end
            end
        end
    end
    -- online
    local Ply = getPlayer(citizenid)
    if Ply and Ply.PlayerData and Ply.PlayerData.charinfo then
        local c = Ply.PlayerData.charinfo
        return (c.firstname or 'Sem') .. ' ' .. (c.lastname or 'Nome')
    end
    -- offline
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if row and row.charinfo then
        local ok, data = pcall(json.decode, row.charinfo)
        if ok and type(data) == 'table' then
            return (data.firstname or 'Sem') .. ' ' .. (data.lastname or 'Nome')
        end
    end
    return ('CID:%s'):format(citizenid or '?')
end

local function fmtDate(ts)
    ts = tonumber(ts) or os.time()
    return os.date('%d/%m/%Y %X', ts)
end

---------------------------------------
-- BLACKLIST
---------------------------------------
BLACKLIST = BLACKLIST or {}

function BLACKLIST:checkUser(citizenid)
    local row = MySQL.single.await(('SELECT `expires_at` FROM `%s` WHERE citizenid = ? LIMIT 1'):format(TBL_BL), { citizenid })
    if not row or not row.expires_at then return 0 end
    return tonumber(row.expires_at) or 0
end

function BLACKLIST:addUser(citizenid)
    local days = (Config and Config.Main and Config.Main.blackList) or 15
    local expires = os.time() + (days * 86400)
    MySQL.update.await(('REPLACE INTO `%s` (citizenid, expires_at) VALUES (?, ?)'):format(TBL_BL), { citizenid, expires })
end

function BLACKLIST:remUser(citizenid)
    MySQL.update.await(('DELETE FROM `%s` WHERE citizenid = ?'):format(TBL_BL), { citizenid })
end

exports('remBL', function(idOrCitizenId)
    local cid = getCitizenId(idOrCitizenId)
    if cid then BLACKLIST:remUser(cid) end
end)

---------------------------------------
-- RegisterTunnel (compat com sua NUI)
---------------------------------------
RegisterTunnel = RegisterTunnel or {}

-- LISTA DE MEMBROS
function RegisterTunnel.getMembers()
    local src = source
    local cid = getCitizenId(src)
    if not cid or not Organizations or not Organizations.Members or not Organizations.Members[cid] then
        return {}
    end

    local me  = Organizations.Members[cid]
    local org = me.groupType
    local membersSet = (Organizations.MembersList and Organizations.MembersList[org]) or {}
    local out = {}

    for memberCid, _ in pairs(membersSet) do
        local m = Organizations.Members[memberCid]
        if m then
            -- garantir dados base na tabela (joindate/lastlogin/timeplayed)
            if not m.joindate or not m.lastlogin then
                local now = os.time()
                local row = MySQL.single.await(('SELECT * FROM `%s` WHERE citizenid = ? LIMIT 1'):format(TBL_PINFO), { memberCid })
                if row then
                    m.joindate   = tonumber(row.joindate) or now
                    m.lastlogin  = tonumber(row.lastlogin) or now
                    m.timeplayed = tonumber(row.timeplayed) or 0
                else
                    m.joindate   = now
                    m.lastlogin  = now
                    m.timeplayed = 0
                    MySQL.update.await(
                        ('INSERT IGNORE INTO `%s` (citizenid, organization, role, joindate, lastlogin, timeplayed) VALUES (?, ?, ?, ?, ?, ?)'):format(TBL_PINFO),
                        { memberCid, org, (m.group or ''), m.joindate, m.lastlogin, m.timeplayed }
                    )
                end
            end

            local rolePrefix, tier = "Membro", 10
            if Config and Config.Groups and Config.Groups[m.groupType]
               and Config.Groups[m.groupType].List
               and Config.Groups[m.groupType].List[m.group]
            then
                rolePrefix = Config.Groups[m.groupType].List[m.group].prefix or rolePrefix
                tier       = Config.Groups[m.groupType].List[m.group].tier   or tier
            end

            out[#out+1] = {
                id        = memberCid, -- citizenid (estável)
                avatar    = 'https://cdn.discordapp.com/icons/1220512491793289297/037858079290922918506b8a9714d8ca.webp',
                name      = getNameByCitizenId(memberCid),
                role      = rolePrefix,
                role_id   = tier,
                status    = (getSourceByCitizenId(memberCid) ~= nil),
                joinedAt  = fmtDate(Organizations.Members[memberCid].joindate),
                lastLogin = fmtDate(Organizations.Members[memberCid].lastlogin),
                hours     = Organizations.Members[memberCid].timeplayed or 0
            }
        end
    end

    return out
end

-- CONVITE
function RegisterTunnel.inviteMember(playerId)
    local src = source
    local cid = getCitizenId(src)
    if not cid then return false end

    local me = Organizations.Members[cid]
    if not me then return false end

    local canInvite = Organizations.Permissions
        and Organizations.Permissions[me.groupType]
        and Organizations.Permissions[me.groupType][me.group]
        and Organizations.Permissions[me.groupType][me.group].invite

    if not canInvite then return false end

    local targetCid = getCitizenId(playerId)
    local tSrc = targetCid and getSourceByCitizenId(targetCid) or nil
    if not targetCid or not tSrc then
        if Config and Config.Langs and Config.Langs['offlinePlayer'] then
            Config.Langs['offlinePlayer'](src)
        end
        return false
    end

    if Organizations.Members[targetCid] then
        if Config and Config.Langs and Config.Langs['alreadyFaction'] then
            Config.Langs['alreadyFaction'](src)
        end
        return false
    end

    if cid == targetCid then return false end

    local bl = BLACKLIST:checkUser(targetCid)
    if bl > 0 and (bl - os.time()) > 0 then
        if Config and Config.Langs then
            if Config.Langs['alreadyBlacklist'] then Config.Langs['alreadyBlacklist'](tSrc) end
            if Config.Langs['alreadyUserBlacklist'] then Config.Langs['alreadyUserBlacklist'](src) end
        end
        return false
    end

    if Config and Config.Langs and Config.Langs['sendInvite'] then
        Config.Langs['sendInvite'](src)
    end

    -- Confirmação pelo cliente do convidado (implemente no client)
    local accepted = (lib and lib.callback and lib.callback.await)
        and lib.callback.await('Painel_ORG:members:confirmInvite', tSrc, me.groupType)
        or true
    if not accepted then return false end

    -- menor hierarquia (maior tier)
    local maxTier, setGroup = -1, nil
    for group, v in pairs(Config.Groups[me.groupType].List) do
        if v.tier and v.tier > maxTier then
            maxTier = v.tier
            setGroup = group
        end
    end
    if not setGroup then return false end

    -- aplica
    Organizations:AddUserGroup(targetCid, { group = setGroup, groupType = me.groupType })

    local now = os.time()
    MySQL.update.await(
        ('INSERT IGNORE INTO `%s` (citizenid, organization, role, joindate, lastlogin, timeplayed) VALUES (?, ?, ?, ?, ?, ?)'):format(TBL_PINFO),
        { targetCid, me.groupType, setGroup, now, now, 0 }
    )
    MySQL.update.await(
        ('UPDATE `%s` SET organization = ?, role = ? WHERE citizenid = ?'):format(TBL_PINFO),
        { me.groupType, setGroup, targetCid }
    )

    if Config and Config.Langs then
        if Config.Langs['acceptInvite'] then Config.Langs['acceptInvite'](tSrc) end
        if Config.Langs['acceptedInvite'] then Config.Langs['acceptedInvite'](src, tSrc) end
    end

    return true
end

-- PROMOVER / REBAIXAR / DEMITIR
function RegisterTunnel.genMember(data)
    local src = source
    if not data or not data.action or not data.memberId then return false end

    local cid = getCitizenId(src)
    if not cid then return false end

    local me = Organizations.Members[cid]
    if not me then return false end

    local targetCid = getCitizenId(data.memberId)
    local target    = targetCid and Organizations.Members[targetCid] or nil
    if not target then return false end

    if me.groupType ~= target.groupType then return false end

    local myTier  = (Config.Groups[me.groupType] and Config.Groups[me.groupType].List[me.group] and Config.Groups[me.groupType].List[me.group].tier) or 999
    local tarTier = (Config.Groups[target.groupType] and Config.Groups[target.groupType].List[target.group] and Config.Groups[target.groupType].List[target.group].tier) or 999

    -- PROMOTE
    if data.action == 'promote' then
        local can = Organizations.Permissions
            and Organizations.Permissions[me.groupType]
            and Organizations.Permissions[me.groupType][me.group]
            and Organizations.Permissions[me.groupType][me.group].promote
        if not can then return false end

        if myTier >= tarTier then return false end

        local newTier = tarTier - 1
        if newTier <= 0 then newTier = 1 end
        if myTier >= newTier then
            if Config and Config.Langs and Config.Langs['bestTier'] then Config.Langs['bestTier'](src) end
            return false
        end

        for grp, v in pairs(Config.Groups[me.groupType].List) do
            if v.tier == newTier then
                Organizations:AddUserGroup(targetCid, { group = grp, groupType = target.groupType })
                MySQL.update.await(
                    ('UPDATE `%s` SET organization = ?, role = ? WHERE citizenid = ?'):format(TBL_PINFO),
                    { target.groupType, grp, targetCid }
                )

                local tSrc = getSourceByCitizenId(targetCid)
                if tSrc and Config and Config.Langs and Config.Langs['youPromoved'] then
                    Config.Langs['youPromoved'](tSrc)
                end
                if Config and Config.Langs and Config.Langs['youPromovedUser'] then
                    Config.Langs['youPromovedUser'](src, tSrc or 0, Config.Groups[target.groupType].List[grp].prefix)
                end

                return {
                    role    = Config.Groups[target.groupType].List[grp].prefix,
                    role_id = newTier
                }
            end
        end
        return false
    end

    -- DEMOTE
    if data.action == 'demote' then
        local can = Organizations.Permissions
            and Organizations.Permissions[me.groupType]
            and Organizations.Permissions[me.groupType][me.group]
            and Organizations.Permissions[me.groupType][me.group].demote
        if not can then return false end

        if myTier >= tarTier then
            if Config and Config.Langs and Config.Langs['bestTier'] then Config.Langs['bestTier'](src) end
            return false
        end

        local newTier = tarTier + 1
        local maxTier = 0
        for _, v in pairs(Config.Groups[me.groupType].List) do
            if v.tier and v.tier > maxTier then maxTier = v.tier end
        end
        if newTier > maxTier then newTier = maxTier end

        for grp, v in pairs(Config.Groups[me.groupType].List) do
            if v.tier == newTier then
                Organizations:AddUserGroup(targetCid, { group = grp, groupType = target.groupType })
                MySQL.update.await(
                    ('UPDATE `%s` SET organization = ?, role = ? WHERE citizenid = ?'):format(TBL_PINFO),
                    { target.groupType, grp, targetCid }
                )

                local tSrc = getSourceByCitizenId(targetCid)
                if tSrc and Config and Config.Langs and Config.Langs['youDemote'] then
                    Config.Langs['youDemote'](tSrc)
                end
                if Config and Config.Langs and Config.Langs['youDemoteUser'] then
                    Config.Langs['youDemoteUser'](src, tSrc or 0, Config.Groups[target.groupType].List[grp].prefix)
                end

                return {
                    role    = Config.Groups[target.groupType].List[grp].prefix,
                    role_id = newTier
                }
            end
        end
        return false
    end

    -- DISMISS
    if data.action == 'dismiss' then
        local can = Organizations.Permissions
            and Organizations.Permissions[me.groupType]
            and Organizations.Permissions[me.groupType][me.group]
            and Organizations.Permissions[me.groupType][me.group].dismiss
        if not can then return false end

        if targetCid == cid then
            if Config and Config.Langs and Config.Langs['bestTier'] then Config.Langs['bestTier'](src) end
            return false
        end

        if myTier > tarTier then return false end

        Organizations:RemUserGroup(targetCid)
        MySQL.update.await(('DELETE FROM `%s` WHERE citizenid = ?'):format(TBL_PINFO), { targetCid })

        BLACKLIST:addUser(targetCid)

        local tSrc = getSourceByCitizenId(targetCid)
        if tSrc and Config and Config.Langs and Config.Langs['youDismiss'] then
            Config.Langs['youDismiss'](tSrc)
        end
        if Config and Config.Langs and Config.Langs['youDemoteUser'] then
            Config.Langs['youDemoteUser'](src, tSrc or 0, target.group)
        end

        return true
    end

    return false
end

---------------------------------------
-- ox_lib callbacks (opcionais/espelho)
---------------------------------------
if lib and lib.callback and lib.callback.register then
    lib.callback.register('Painel_ORG:members:get', function(source)
        return RegisterTunnel.getMembers()
    end)

    lib.callback.register('Painel_ORG:members:invite', function(source, playerId)
        return RegisterTunnel.inviteMember(playerId)
    end)

    lib.callback.register('Painel_ORG:members:action', function(source, data)
        return RegisterTunnel.genMember(data)
    end)
end
