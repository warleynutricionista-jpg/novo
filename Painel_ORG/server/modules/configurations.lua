--------------------------------------------
-- Painel_ORG - server/modules/configurations.lua (QBX/QBCore)
-- Sem vRP / Sem RegisterTunnel
-- Usa: ox_lib (callbacks) + oxmysql (MySQL.*.await)
-- Permite: ler/alterar permissões, discord, rádio, presets
-- Tabelas: thunder_orgs_info (columns: organization, discord, radio, presets, permissions, ...)
--------------------------------------------

--------------------------------------------
-- Core detection (qbx-core / qb-core)
--------------------------------------------
local Core = (function()
    local function try(res)
        if GetResourceState(res) == 'started' then
            local ok, obj = pcall(function() return exports[res]:GetCoreObject() end)
            if ok and obj then return obj end
        end
    end
    return try('qbx-core') or try('qb-core') or nil
end)()

local function GetPlayerObject(src)
    if not Core then return nil end
    if Core.Functions and Core.Functions.GetPlayer then
        return Core.Functions.GetPlayer(src)
    elseif Core.GetPlayer then
        return Core.GetPlayer(src)
    end
    return nil
end

local function GetCitizenId(src)
    local ply = GetPlayerObject(src)
    return ply and ply.PlayerData and ply.PlayerData.citizenid or nil
end

--------------------------------------------
-- DB helpers (oxmysql via MySQL.*.await)
--------------------------------------------
local function db_insert(q, p)
    local ok, r = pcall(function() return MySQL.insert.await(q, p or {}) end)
    return ok and r or nil
end

local function db_update(q, p)
    local ok, r = pcall(function() return MySQL.update.await(q, p or {}) end)
    return ok and (r or 0) or 0
end

local function db_single(q, p)
    local ok, r = pcall(function() return MySQL.single.await(q, p or {}) end)
    return ok and r or nil
end

--------------------------------------------
-- Defaults/Helpers
--------------------------------------------
local DEFAULT_PERMS = {
    promote  = false, demote   = false, dismiss  = false,
    withdraw = false, deposit  = false, message  = false,
    alerts   = false, invite   = false, chat     = false,
    leader   = false,
}

local function ensureOrgRow(org)
    if not org or org == '' then return end
    db_insert('INSERT IGNORE INTO thunder_orgs_info (organization) VALUES (?)', { org })
end

local function sanitizePerms(perms)
    local out = {}
    for k, v in pairs(DEFAULT_PERMS) do
        out[k] = (perms and (perms[k] == true)) or false
    end
    return out
end

local function getOrgFromSource(src)
    local cid = GetCitizenId(src)
    if not cid or not Organizations or not Organizations.Members then return nil, nil end
    local m = Organizations.Members[cid]
    return (m and m.groupType) or nil, cid
end

local function isLeader(cid)
    if not cid or not Organizations or not Organizations.Members then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    local org, role = m.groupType, m.group
    if not org or not role then return false end
    local perms = Organizations.Permissions[org] and Organizations.Permissions[org][role]
    return perms and perms.leader == true or false
end

--------------------------------------------
-- ================ PERMISSÕES ================
--------------------------------------------
-- Retorna o mapa completo de permissões por cargo da organização atual
-- Formato:
-- {
--   org = "police",
--   map = { ["Líder"]={...}, ["Tenente"]={...}, ... },
--   roles = { {id="Líder", prefix="Líder"}, ... } -- útil para UI
-- }
lib.callback.register('Painel_ORG:perms:get', function(source)
    local org = getOrgFromSource(source)
    if not org then return { org = nil, map = {}, roles = {} } end

    Organizations.Permissions[org] = Organizations.Permissions[org] or {}

    -- montar lista de cargos (com prefix do Config se existir)
    local roles = {}
    if Config and Config.Groups and Config.Groups[org] and Config.Groups[org].List then
        for roleName, roleData in pairs(Config.Groups[org].List) do
            roles[#roles+1] = { id = roleName, prefix = roleData.prefix or roleName }
            -- garantir entrada no mapa
            Organizations.Permissions[org][roleName] = Organizations.Permissions[org][roleName] or sanitizePerms({})
        end
    else
        -- fallback: o que estiver em cache
        for roleName, _ in pairs(Organizations.Permissions[org]) do
            roles[#roles+1] = { id = roleName, prefix = roleName }
        end
    end

    return { org = org, map = Organizations.Permissions[org], roles = roles }
end)

-- Atualiza permissões. Aceita:
--  - data = { role="Tenente", perms={...} }  (um cargo)
--  - data = { ["Tenente"]={...}, ["Soldado"]={...} } (vários)
lib.callback.register('Painel_ORG:perms:set', function(source, data)
    local org, cid = getOrgFromSource(source)
    if not org or not cid then return false end
    if not isLeader(cid) then return false end

    Organizations.Permissions[org] = Organizations.Permissions[org] or {}

    local function applyOne(role, perms)
        if not role or role == '' then return end
        local cleaned = sanitizePerms(perms)
        Organizations.Permissions[org][role] = cleaned
    end

    if type(data) == 'table' and data.role then
        applyOne(data.role, data.perms or {})
    elseif type(data) == 'table' then
        for role, perms in pairs(data) do
            if type(perms) == 'table' then applyOne(role, perms) end
        end
    else
        return false
    end

    -- Persiste no DB (se a coluna "permissions" não existir, não quebra)
    ensureOrgRow(org)
    local ok = db_update('UPDATE thunder_orgs_info SET permissions = ? WHERE organization = ?',
        { json.encode(Organizations.Permissions[org]), org })

    return ok >= 0 -- mesmo que não atualize linhas, consideramos sucesso (cache já refletiu)
end)

--------------------------------------------
-- ================ CONFIG (GENÉRICO) ================
--------------------------------------------
-- data pode conter qualquer um dos campos: discord (string),
-- radio (string/number), presets (table {male,female})
lib.callback.register('Painel_ORG:config:set', function(source, data)
    local org, cid = getOrgFromSource(source)
    if not org or not cid then return false end
    if not isLeader(cid) then return false end
    if type(data) ~= 'table' then return false end

    ensureOrgRow(org)

    local changed = false

    if data.discord ~= nil then
        db_update('UPDATE thunder_orgs_info SET discord = ? WHERE organization = ?', { tostring(data.discord or ''), org })
        changed = true
    end
    if data.radio ~= nil then
        db_update('UPDATE thunder_orgs_info SET radio = ? WHERE organization = ?', { tostring(data.radio or ''), org })
        changed = true
    end
    if type(data.presets) == 'table' then
        local payload = { male = data.presets.male or '', female = data.presets.female or '' }
        db_update('UPDATE thunder_orgs_info SET presets = ? WHERE organization = ?', { json.encode(payload), org })
        changed = true
    end

    return changed
end)

--------------------------------------------
-- ================ CONFIG (ESPECIALIZADOS) ================
--------------------------------------------
-- Somente rádio
lib.callback.register('Painel_ORG:config:setRadio', function(source, freqStr)
    local org, cid = getOrgFromSource(source)
    if not org or not cid then return false end
    if not isLeader(cid) then return false end
    ensureOrgRow(org)
    local freq = tostring(freqStr or '')
    db_update('UPDATE thunder_orgs_info SET radio = ? WHERE organization = ?', { freq, org })
    return true
end)

-- Somente presets
lib.callback.register('Painel_ORG:config:setPresets', function(source, data)
    local org, cid = getOrgFromSource(source)
    if not org or not cid then return false end
    if not isLeader(cid) then return false end
    ensureOrgRow(org)
    local payload = { male = (data and data.male) or '', female = (data and data.female) or '' }
    db_update('UPDATE thunder_orgs_info SET presets = ? WHERE organization = ?', { json.encode(payload), org })
    return true
end)

--------------------------------------------
-- (Opcional) Legacy compat: nomes antigos
--------------------------------------------
lib.callback.register('Painel_ORG:getPermissions', function(source, role)
    -- devolve só as permissões de um cargo específico (se pedirem por compat)
    local org = getOrgFromSource(source)
    if not org then return DEFAULT_PERMS end
    Organizations.Permissions[org] = Organizations.Permissions[org] or {}
    return Organizations.Permissions[org][role] or DEFAULT_PERMS
end)

lib.callback.register('Painel_ORG:updatePermissions', function(source, role_id, perms)
    -- atalho antigo: atualiza um único cargo
    return lib.callback.await('Painel_ORG:perms:set', false, { role = role_id, perms = perms })
end)

lib.callback.register('Painel_ORG:updateRadio', function(source, data)
    return lib.callback.await('Painel_ORG:config:setRadio', false, data and data.frequency)
end)

lib.callback.register('Painel_ORG:updatePreset', function(source, data)
    return lib.callback.await('Painel_ORG:config:setPresets', false, data or {})
end)
