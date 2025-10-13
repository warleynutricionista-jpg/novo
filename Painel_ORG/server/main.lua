----------------------------------------------- 
-- Painel_ORG - Server (QBX/QBCore)
-- Sem vRP / MySQL.*.await (oxmysql)
-- Auto-descoberta via management_funds (QBCore)
-- Tabelas thunder_* (bridge_core garante o schema)
-- Callbacks: ox_lib (lib.callback.register)
-----------------------------------------------

local RES_NAME = GetCurrentResourceName()

-- =============== Core Detection (qbx-core / qb-core) ===============
local Core = (function()
    local ok, obj = pcall(function()
        if GetResourceState('qbx-core') == 'started'
            and exports['qbx-core'] and exports['qbx-core'].GetCoreObject
        then return exports['qbx-core']:GetCoreObject() end

        if GetResourceState('qb-core') == 'started'
            and exports['qb-core'] and exports['qb-core'].GetCoreObject
        then return exports['qb-core']:GetCoreObject() end

        return nil
    end)
    return (ok and obj) or nil
end)()

-- =============== Espera MySQL global ===============
local function WaitForMySQL(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 15000)
    while not MySQL do
        if GetGameTimer() > deadline then break end
        Wait(50)
    end
    return MySQL ~= nil
end

-- =============== Helpers Core/Identidade ===============
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
    local p = GetPlayerObject(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function GetIdentityOnline(src)
    local p = GetPlayerObject(src)
    if p and p.PlayerData and p.PlayerData.charinfo then
        local c = p.PlayerData.charinfo
        local first = c.firstname or c.first or ""
        local last  = c.lastname or c.last or ""
        local full  = (first ~= "" or last ~= "") and ("%s %s"):format(first, last):gsub('%s+$','') or nil
        return { firstname = first, lastname = last, name = full or first or last or "" }
    end
    return nil
end

local function GetIdentityByCitizenId(citizenid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if row and row.charinfo then
        local ok, data = pcall(json.decode, row.charinfo)
        if ok and type(data) == 'table' then
            local first = data.firstname or data.first or ""
            local last  = data.lastname or data.last or ""
            local full = (first ~= "" or last ~= "") and ("%s %s"):format(first, last):gsub('%s+$','') or nil
            return { firstname = first, lastname = last, name = full or first or last or "" }
        end
    end
    return { firstname = "", lastname = "", name = "" }
end

local function GetNameTagged(citizenid, src)
    local id = (src and GetIdentityOnline(src)) or GetIdentityByCitizenId(citizenid)
    local first = id.firstname or ""
    local last  = id.lastname or ""
    local full  = id.name or (("%s %s"):format(first, last):gsub('%s+$',''))
    return (full and full ~= "" and full) or ("CID:"..tostring(citizenid))
end

local function now() return os.time() end

-- =============== Estruturas em memória ===============
Organizations = {
    List         = {},   -- roleName -> orgName
    Permissions  = {},   -- orgName -> { [groupName] = {perms} }
    Members      = {},   -- citizenid -> { group, groupType, joindate, lastlogin, timeplayed }
    MembersList  = {},   -- orgName -> { [citizenid] = true }
    timePlayed   = {},   -- citizenid -> os.time()
    hasOppenedOrg= {},   -- orgName -> { [citizenid] = src }
    payDayOrg    = {},   -- orgName -> { time, amount, salaryTime, salarySetTime }
    goalsConfig  = {},   -- orgName -> cfg (cache opcional)
    Chat         = {},   -- orgName -> mensagens recentes em memória
}

-- =============== Permissões a partir do Config.Groups ===============
local function BuildPermissionsFromConfig()
    Organizations.Permissions, Organizations.List = {}, {}
    if not (Config and Config.Groups) then return end

    for orgName, orgData in pairs(Config.Groups) do
        local permsByGroup = {}
        if orgData.List then
            for groupName, role in pairs(orgData.List) do
                local tier = tonumber(role.tier) or 999
                permsByGroup[groupName] = {
                    leader   = role.leader   or (tier == 1),
                    invite   = role.invite   or (tier <= 2),
                    promote  = role.promote  or (tier <= 2),
                    demote   = role.demote   or (tier <= 2),
                    dismiss  = role.dismiss  or (tier <= 2),
                    withdraw = role.withdraw or (tier <= 2),
                    deposit  = true,
                    message  = true,
                    alerts   = true,
                    chat     = true,
                    -- permite configurar presets/rádio (líder e tiers altos por padrão)
                    config   = (role.config == true) or (tier <= 2) or (role.leader == true),
                }
                Organizations.List[groupName] = orgName
            end
        end
        Organizations.Permissions[orgName] = permsByGroup
    end
end

local function pickLowestRole(orgName)
    if not (Config and Config.Groups and Config.Groups[orgName] and Config.Groups[orgName].List) then
        return nil
    end
    local maxTier, sel = -1, nil
    for group, v in pairs(Config.Groups[orgName].List) do
        local t = tonumber(v.tier) or 999
        if t > maxTier then maxTier, sel = t, group end
    end
    return sel
end

-- =============== Orgs via management_funds ===============
local function fetchOrganizationsFromDB()
    local orgs = {} -- set
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT DISTINCT job_name, type FROM management_funds', {})
    end)
    if ok and rows then
        for _, r in ipairs(rows) do
            if r.job_name and r.job_name ~= '' then orgs[r.job_name] = true end
        end
    end
    return orgs
end

-- Garante linha em thunder_orgs_info
local function ensureOrgsInfo(orgs)
    for orgName in pairs(orgs) do
        MySQL.insert.await('INSERT IGNORE INTO thunder_orgs_info (organization) VALUES (?)', { orgName })
    end
end

-- =============== API usada por módulos ===============
function Organizations:AddUserGroup(citizenid, data)
    if not citizenid or not data or not data.groupType or not data.group then return end
    local old = Organizations.Members[citizenid]
    if old and old.groupType and Organizations.MembersList[old.groupType] then
        Organizations.MembersList[old.groupType][citizenid] = nil
    end
    Organizations.Members[citizenid] = Organizations.Members[citizenid] or {}
    Organizations.Members[citizenid].groupType = data.groupType
    Organizations.Members[citizenid].group     = data.group

    Organizations.MembersList[data.groupType] = Organizations.MembersList[data.groupType] or {}
    Organizations.MembersList[data.groupType][citizenid] = true
end

function Organizations:RemUserGroup(citizenid)
    local m = Organizations.Members[citizenid]
    if not m then return end
    if m.groupType and Organizations.MembersList[m.groupType] then
        Organizations.MembersList[m.groupType][citizenid] = nil
    end
    Organizations.Members[citizenid] = nil
    Organizations.timePlayed[citizenid] = nil
end

-- =============== Cache inicial ===============
local function GenerateCache()
    print(('[%s] Carregando organizações (Config.Groups + management_funds)...'):format(RES_NAME))

    BuildPermissionsFromConfig()

    local discovered = fetchOrganizationsFromDB()
    if next(discovered) ~= nil then
        ensureOrgsInfo(discovered)
        for orgName in pairs(discovered) do
            Organizations.Permissions[orgName] = Organizations.Permissions[orgName] or {}
            Organizations.MembersList[orgName] = Organizations.MembersList[orgName] or {}
        end
    else
        print(('[%s] Nenhuma organização em management_funds (ok, usando apenas Config.Groups).'):format(RES_NAME))
    end

    -- Popular jogadores online
    local i = 0
    for _, sid in ipairs(GetPlayers()) do
        i = i + 1
        if (i % 25) == 0 then Wait(0) end  -- alivia tick de boot

        local src = tonumber(sid)
        local cid = GetCitizenId(src)
        if cid then
            local ply = GetPlayerObject(src)
            local jobName  = ply and ply.PlayerData and ply.PlayerData.job  and ply.PlayerData.job.name  or nil
            local gangName = ply and ply.PlayerData and ply.PlayerData.gang and ply.PlayerData.gang.name or nil
            local orgName  = gangName or jobName

            if orgName and Organizations.Permissions[orgName] then
                local defaultGroup = pickLowestRole(orgName) or (next(Organizations.Permissions[orgName]) and next(Organizations.Permissions[orgName])) or nil
                defaultGroup = defaultGroup or ('Membro ['..orgName:upper()..']')
                Organizations:AddUserGroup(cid, { group = defaultGroup, groupType = orgName })

                local tNow = now()
                local row = MySQL.single.await('SELECT * FROM thunder_orgs_player_infos WHERE citizenid = ? LIMIT 1', { cid })
                if row then
                    Organizations.Members[cid].joindate   = tonumber(row.joindate) or tNow
                    Organizations.Members[cid].lastlogin  = tonumber(row.lastlogin) or tNow
                    Organizations.Members[cid].timeplayed = tonumber(row.timeplayed) or 0
                else
                    Organizations.Members[cid].joindate   = tNow
                    Organizations.Members[cid].lastlogin  = tNow
                    Organizations.Members[cid].timeplayed = 0
                    MySQL.insert.await([[
                        INSERT IGNORE INTO thunder_orgs_player_infos
                        (citizenid, organization, joindate, lastlogin, timeplayed)
                        VALUES (?, ?, ?, ?, ?)
                    ]], { cid, orgName, tNow, tNow, 0 })
                end
                Organizations.timePlayed[cid] = tNow
            end
        end
    end

    local totalOrgs = 0; for _ in pairs(Organizations.Permissions) do totalOrgs = totalOrgs + 1 end
    print(('[%s] Organizações ativas no cache: %d.'):format(RES_NAME, totalOrgs))
end

-- =============== Payday (crédito no banco da org) ===============
local function LoadPaydays()
    local rows = MySQL.query.await('SELECT organization, salary FROM thunder_orgs_info', {})
    for _, r in ipairs(rows or {}) do
        if r.salary and r.salary ~= '' then
            local ok, data = pcall(json.decode, r.salary)
            if ok and type(data) == 'table' and (data.time or data.salaryTime) and data.amount then
                Organizations.payDayOrg[r.organization] = {
                    salaryTime    = data.salaryTime or data.time or 30,
                    salarySetTime = data.salaryTime or data.time or 30,
                    amount        = tonumber(data.amount) or 0,
                    time          = now() + ((data.salaryTime or data.time or 30) * 60),
                }
            end
        end
    end

    CreateThread(function()
        while true do
            local t = now()
            for org, st in pairs(Organizations.payDayOrg) do
                if (st.time - t) <= 0 then
                    local inf = MySQL.single.await('SELECT bank, bank_historic FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { org })
                    if inf then
                        local bank = (tonumber(inf.bank) or 0) + (tonumber(st.amount) or 0)
                        local logs = {}
                        if inf.bank_historic and inf.bank_historic ~= '' then
                            local ok2, arr = pcall(json.decode, inf.bank_historic)
                            if ok2 and type(arr) == 'table' then logs = arr end
                        end
                        logs[#logs+1] = { name = org, type = 'SALÁRIO FAC', value = st.amount, date = os.date('%d/%m/%Y %X') }
                        MySQL.update.await('UPDATE thunder_orgs_info SET bank = ?, bank_historic = ? WHERE organization = ?',
                            { bank, json.encode(logs), org })
                    end
                    Organizations.payDayOrg[org].time = now() + ((st.salarySetTime or st.salaryTime or 30) * 60)
                end
            end
            Wait(1000)
        end
    end)
end

-- =============== WARNINGS ===============
local function addWarning(organization, data)
    local row = MySQL.single.await('SELECT alerts FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { organization })
    if not row then return {} end
    local historic = {}
    if row.alerts and row.alerts ~= '' then
        local ok, dataJ = pcall(json.decode, row.alerts)
        if ok and type(dataJ) == 'table' then historic = dataJ end
    end
    historic.data = historic.data or {}
    table.insert(historic.data, 1, data)
    if #historic.data > 30 then table.remove(historic.data, 31) end
    MySQL.update.await('UPDATE thunder_orgs_info SET alerts = ? WHERE organization = ?', { json.encode(historic), organization })
    return historic
end

-- (opcional) deletar aviso pelo date/id simples (se a NUI chamar)
lib.callback.register('Painel_ORG:warns:delete', function(source, key)
    local cid = GetCitizenId(source); if not cid then return nil end
    local m = Organizations.Members[cid]; if not m then return nil end
    local row = MySQL.single.await('SELECT alerts FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { m.groupType })
    if not row then return nil end
    local historic = {}
    if row.alerts and row.alerts ~= '' then
        local ok, dataJ = pcall(json.decode, row.alerts)
        if ok and type(dataJ) == 'table' then historic = dataJ end
    end
    if historic.data then
        for i = #historic.data, 1, -1 do
            local it = historic.data[i]
            if it and (it.date == key or it.id == key) then table.remove(historic.data, i) break end
        end
    end
    MySQL.update.await('UPDATE thunder_orgs_info SET alerts = ? WHERE organization = ?', { json.encode(historic), m.groupType })
    return historic
end)

-- =============== CHAT ===============
local function insertChatMessage(org, citizenid, author, message)
    MySQL.insert.await([[
        INSERT INTO thunder_orgs_chat (organization, user_identifier, message, author, created_at)
        VALUES (?, ?, ?, ?, NOW())
    ]], { org, citizenid, message, author })
end

local function loadChatMessages(org)
    local rows = MySQL.query.await([[
        SELECT user_identifier, message, author, created_at
        FROM thunder_orgs_chat
        WHERE organization = ?
        ORDER BY created_at DESC
        LIMIT 100
    ]], { org }) or {}
    local list = {}
    for _, m in ipairs(rows) do
        list[#list+1] = { message = m.message, author = m.author, author_id = m.user_identifier }
    end
    return list
end

-- =============== Helpers membros ===============
local function ensureMemberCache(citizenid, org)
    Organizations.Members[citizenid] = Organizations.Members[citizenid] or { groupType = org }
    Organizations.MembersList[org] = Organizations.MembersList[org] or {}
    Organizations.MembersList[org][citizenid] = true
end

-- =============== Permissão de Config (presets/radio) ===============
local function hasConfigPerm(citizenid)
    local m = Organizations.Members[citizenid]
    if not m then return false end
    local perms = Organizations.Permissions[m.groupType] and Organizations.Permissions[m.groupType][m.group]
    if not perms then return false end
    return (perms.config == true) or (perms.leader == true)
end

-- =========================================================
-- ================== OX_LIB CALLBACKS =====================
-- =========================================================

-- Abrir painel
lib.callback.register('Painel_ORG:getFaction', function(source, orgOverride)
    local cid = GetCitizenId(source); if not cid then return end

    local ply = GetPlayerObject(source)
    local jobName  = ply and ply.PlayerData and ply.PlayerData.job  and ply.PlayerData.job.name  or nil
    local gangName = ply and ply.PlayerData and ply.PlayerData.gang and ply.PlayerData.gang.name or nil

    local orgName = orgOverride or gangName or jobName
    if not orgName or not Organizations.Permissions[orgName] then return nil end

    ensureMemberCache(cid, orgName)
    Organizations.hasOppenedOrg[orgName] = Organizations.hasOppenedOrg[orgName] or {}
    Organizations.hasOppenedOrg[orgName][cid] = source

    -- lista de cargos (exclui líder)
    local leaderRole; local rolesList = {}
    for roleName, perm in pairs(Organizations.Permissions[orgName]) do
        if perm.leader then leaderRole = roleName else
            rolesList[#rolesList+1] = { prefix = roleName, group = roleName }
        end
    end

    -- contagem membros (onlineSet)
    local total = MySQL.single.await('SELECT COUNT(*) AS total FROM thunder_orgs_player_infos WHERE organization = ?', { orgName })
    local totalMembers = (total and total.total) or 0

    local membersRows = MySQL.query.await('SELECT citizenid FROM thunder_orgs_player_infos WHERE organization = ?', { orgName }) or {}
    local onlineSet = {}
    for _, pid in ipairs(GetPlayers()) do
        local ocid = GetCitizenId(tonumber(pid))
        if ocid then onlineSet[ocid] = true end
    end
    local onlineCount = 0
    for _, r in ipairs(membersRows) do
        if onlineSet[r.citizenid] then onlineCount = onlineCount + 1 end
    end

    local info = MySQL.single.await('SELECT * FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { orgName }) or {}
    local presets, salaryO, alerts = {}, nil, {}
    if info.presets and info.presets ~= '' then local ok,d=pcall(json.decode, info.presets); if ok then presets=d end end
    if info.salary  and info.salary  ~= '' then local ok,d=pcall(json.decode, info.salary ); if ok then salaryO=d end end
    if info.alerts  and info.alerts  ~= '' then local ok,d=pcall(json.decode, info.alerts ); if ok then alerts=d end end

    local leaderName = "Sem Líder"
    local ml = Organizations.MembersList[orgName]
    if ml then
        for mcid,_ in pairs(ml) do
            local mm = Organizations.Members[mcid]
            if mm and mm.group == leaderRole then
                leaderName = ("%s #%s"):format(GetNameTagged(mcid), mcid)
                break
            end
        end
    end

    local meName = GetNameTagged(cid, source)

    return {
        user_id        = cid,
        preset         = { male = (presets.male or ""), female = (presets.female or "") },
        logo           = info.logo,
        radio          = info.radio,
        serverIcon     = info.logo,
        store          = "",
        orgName        = orgName,
        orgBalance     = info.bank or 0,
        name           = meName,
        playerBalance  = 0,
        roles          = rolesList,
        salary         = Organizations.payDayOrg[orgName] and Organizations.payDayOrg[orgName].amount or (salaryO and salaryO.amount) or false,
        nextPayment    = Organizations.payDayOrg[orgName] and (Organizations.payDayOrg[orgName].time - now()) or false,
        nextPaymentMax = Organizations.payDayOrg[orgName] and ((Organizations.payDayOrg[orgName].salaryTime or 0) * 60) or false,
        goalReward     = (Organizations.goalsConfig[orgName] and Organizations.goalsConfig[orgName].info and Organizations.goalsConfig[orgName].info.defaultReward) or 1000,
        discord        = info.discord or "",
        leader         = leaderName,
        members        = totalMembers,
        membersOnline  = onlineCount,
        warnings       = alerts,
        permissions    = (leaderRole and Organizations.Permissions[orgName] and Organizations.Permissions[orgName][leaderRole]) or {},
    }
end)

-- Aviso
lib.callback.register('Painel_ORG:addWarn', function(source, message)
    local cid = GetCitizenId(source); if not cid then return end
    local m = Organizations.Members[cid]; if not m then return end
    if not message or #message < 2 then return end

    local author = GetNameTagged(cid, source)
    local historic = addWarning(m.groupType, {
        author        = author,
        author_id     = cid,
        message       = message,
        author_avatar = '',
        date          = os.date('%d/%m/%Y %X'),
    })

    local opened = Organizations.hasOppenedOrg[m.groupType]
    if opened then
        for _, osrc in pairs(opened) do
            if GetPlayerPed(osrc) ~= 0 then
                TriggerClientEvent('updateWarnings', osrc, historic)
            end
        end
    end
    return historic
end)

-- Chat
lib.callback.register('Painel_ORG:sendMessage', function(source, message)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    if not message or message == "" then return false end

    local author = GetNameTagged(cid, source)
    Organizations.Chat[m.groupType] = Organizations.Chat[m.groupType] or {}
    local gen_id = #Organizations.Chat[m.groupType] + 1
    Organizations.Chat[m.groupType][gen_id] = { message = message, author = author, author_id = cid }

    insertChatMessage(m.groupType, cid, author, message)

    local opened = Organizations.hasOppenedOrg[m.groupType] or {}
    for _, osrc in pairs(opened) do
        if GetPlayerPed(osrc) ~= 0 then
            TriggerClientEvent("updateChatMessage", osrc, Organizations.Chat[m.groupType][gen_id])
        end
    end
    return true
end)

lib.callback.register('Painel_ORG:getChatMessages', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    return loadChatMessages(m.groupType)
end)

-- Fechar painel
lib.callback.register('Painel_ORG:close', function(source)
    local cid = GetCitizenId(source); if not cid then return end
    local m = Organizations.Members[cid]; if not m then return end
    if Organizations.hasOppenedOrg[m.groupType] then
        Organizations.hasOppenedOrg[m.groupType][cid] = nil
    end
end)

-- ========== CONFIG (Presets + Rádio) ==========
lib.callback.register('Painel_ORG:config:getPresets', function(source)
    local cid = GetCitizenId(source); if not cid then return { male = "", female = "" } end
    local m = Organizations.Members[cid]; if not m then return { male = "", female = "" } end
    local row = MySQL.single.await('SELECT presets FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { m.groupType }) or {}
    local male, female = "", ""
    if row.presets and row.presets ~= '' then
        local ok, d = pcall(json.decode, row.presets); if ok and type(d) == 'table' then
            male, female = d.male or "", d.female or ""
        end
    end
    return { male = male, female = female }
end)

lib.callback.register('Painel_ORG:config:setPresets', function(source, data)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    if not hasConfigPerm(cid) then return false end

    local male   = (data and data.male) or ""
    local female = (data and data.female) or ""
    local js = json.encode({ male = tostring(male), female = tostring(female) })
    MySQL.update.await('UPDATE thunder_orgs_info SET presets = ? WHERE organization = ?', { js, m.groupType })
    return true
end)

lib.callback.register('Painel_ORG:config:getRadio', function(source)
    local cid = GetCitizenId(source); if not cid then return { channel = "" } end
    local m = Organizations.Members[cid]; if not m then return { channel = "" } end
    local row = MySQL.single.await('SELECT radio FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { m.groupType }) or {}
    return { channel = row.radio or "" }
end)

lib.callback.register('Painel_ORG:config:setRadio', function(source, value)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    if not hasConfigPerm(cid) then return false end
    local ch = tostring(value or "")
    MySQL.update.await('UPDATE thunder_orgs_info SET radio = ? WHERE organization = ?', { ch, m.groupType })
    return true
end)

-- ========== PARTNERS (callback + eventos de legado) ==========
lib.callback.register('Painel_ORG:partners:get', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    local all = MySQL.query.await('SELECT * FROM thunder_partners', {}) or {}
    local filtered = {}
    for _, p in ipairs(all) do
        if not p.groups or p.groups == '' or (p.groups and p.groups:find(m.groupType, 1, true)) then
            filtered[#filtered+1] = { id=p.id, cds=p.cds, name=p.name, note=p.note, description=p.description, icon=p.icon }
        end
    end
    return filtered
end)

RegisterNetEvent('getPartners', function()
    local src = source
    local list = lib.callback.await('Painel_ORG:partners:get', src)
    TriggerClientEvent('receivePartners', src, list or {})
end)

RegisterNetEvent('addPartner', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return TriggerClientEvent('partnerAdded', src, false) end
    local m = Organizations.Members[cid]
    if not m then return TriggerClientEvent('partnerAdded', src, false) end

    MySQL.insert.await([[
        INSERT INTO thunder_partners (cds, name, note, description, icon, groups)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        data.cds or '[]',
        data.name or '',
        tonumber(data.note) or 0,
        data.description or '',
        data.icon or '',
        m.groupType
    })

    TriggerClientEvent('partnerAdded', src, true)
    local list = lib.callback.await('Painel_ORG:partners:get', src)
    TriggerClientEvent('receivePartners', src, list or {})
end)

RegisterNetEvent('deletePartner', function(partnerId)
    local src = source
    local cid = GetCitizenId(src); if not cid then return end
    if not partnerId then
        return TriggerClientEvent('notifications', src, 'error', 'ID inválido.')
    end
    MySQL.update.await('DELETE FROM thunder_partners WHERE id = ?', { tonumber(partnerId) })
    TriggerClientEvent('partnerDeleted', src, tonumber(partnerId))
end)

-- ========== Partners Map (coords) ==========
RegisterNetEvent('mirtin_partners:server:GetAllCoords', function()
    local src = source
    local rows = MySQL.query.await('SELECT id, cds, name FROM thunder_partners', {}) or {}
    local list = {}
    for _, r in ipairs(rows) do
        local coords = {}
        if r.cds and r.cds ~= '' then
            local ok, d = pcall(json.decode, r.cds)
            if ok then coords = d end
        end
        list[#list+1] = { id = r.id, coords = coords, name = r.name }
    end
    TriggerClientEvent('mirtin_partners:client:ReceiveAllCoords', src, list)
end)

-- ========== Histórico (itens/quantidade) ==========
RegisterNetEvent('mirtin_historico:getHistorico', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return TriggerClientEvent('mirtin_partners:client:ReceiveData', src, {}) end

    local m = Organizations.Members[cid]
    if not m then return TriggerClientEvent('mirtin_partners:client:ReceiveData', src, {}) end

    local rows = MySQL.query.await([[
        SELECT citizenid, group_type, member_data, item, amount, day, month, created_at
        FROM thunder_organization_members
        ORDER BY created_at DESC
    ]], {}) or {}

    local out = {}
    for _, r in ipairs(rows) do
        if r.group_type and r.group_type:find("%["..(m.groupType:upper()).."%]") then
            local dateStr = string.format("%02d/%02d/%s", tonumber(r.day) or 1, tonumber(r.month) or 1, os.date("%Y"))
            out[#out+1] = {
                name   = r.member_data or 'DESCONHECIDO',
                id     = r.citizenid or '',
                date   = dateStr,
                role   = string.upper(r.group_type or 'DESCONHECIDO'),
                amount = tonumber(r.amount) or 0,
                status = true,
                item   = r.item or 'DESCONHECIDO'
            }
        end
    end

    TriggerClientEvent('mirtin_partners:client:ReceiveData', src, out)
end)

-- ========== REGISTERS / LOGS (para NUI) ==========
lib.callback.register('Painel_ORG:registers:get', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    local rows = MySQL.query.await(
        'SELECT user_identifier, role, name, description, date FROM thunder_orgs_logs WHERE organization = ? ORDER BY date DESC LIMIT 150',
        { m.groupType }
    ) or {}
    return rows
end)

-- ========== GOALS / METAS (mínimo necessário p/ NUI não travar) ==========
lib.callback.register('Painel_ORG:goals:getConfig', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    local row = MySQL.single.await('SELECT config_goals FROM thunder_orgs_info WHERE organization = ? LIMIT 1', { m.groupType }) or {}
    local cfg = {}
    if row.config_goals and row.config_goals ~= '' then
        local ok, d = pcall(json.decode, row.config_goals); if ok and type(d) == 'table' then cfg = d end
    end
    return cfg
end)

lib.callback.register('Painel_ORG:goals:setConfig', function(source, cfg)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    if not hasConfigPerm(cid) then return false end
    local js = json.encode(cfg or {})
    MySQL.update.await('UPDATE thunder_orgs_info SET config_goals = ? WHERE organization = ?', { js, m.groupType })
    Organizations.goalsConfig[m.groupType] = cfg or {}
    return true
end)

lib.callback.register('Painel_ORG:goals:getDaily', function(source, day, month)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    day, month = tonumber(day) or tonumber(os.date('%d')), tonumber(month) or tonumber(os.date('%m'))
    local rows = MySQL.query.await([[
        SELECT user_identifier, item, amount
        FROM thunder_orgs_goals
        WHERE organization = ? AND day = ? AND month = ?
        ORDER BY amount DESC
    ]], { m.groupType, day, month }) or {}
    return rows
end)

lib.callback.register('Painel_ORG:goals:getMine', function(source, day, month)
    local cid = GetCitizenId(source); if not cid then return {} end
    local m = Organizations.Members[cid]; if not m then return {} end
    day, month = tonumber(day) or tonumber(os.date('%d')), tonumber(month) or tonumber(os.date('%m'))
    local rows = MySQL.query.await([[
        SELECT item, amount, step, reward_step
        FROM thunder_orgs_goals
        WHERE organization = ? AND user_identifier = ? AND day = ? AND month = ?
    ]], { m.groupType, cid, day, month }) or {}
    return rows
end)

lib.callback.register('Painel_ORG:goals:addProgress', function(source, item, amount, day, month)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = Organizations.Members[cid]; if not m then return false end
    if not item or not amount then return false end
    day, month = tonumber(day) or tonumber(os.date('%d')), tonumber(month) or tonumber(os.date('%m'))
    MySQL.update.await([[
        INSERT INTO thunder_orgs_goals (organization, user_identifier, item, amount, day, month)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], { m.groupType, cid, tostring(item), tonumber(amount) or 0, day, month })
    return true
end)

-- ========== Conexão/Desconexão ==========
AddEventHandler('playerDropped', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    if Organizations.timePlayed[cid] and Organizations.Members[cid] then
        local extra = (now() - Organizations.timePlayed[cid])
        local cur = Organizations.Members[cid].timeplayed or 0
        local sum = cur + extra
        MySQL.update.await('UPDATE thunder_orgs_player_infos SET timeplayed = ? WHERE citizenid = ?', { sum, cid })
        Organizations.Members[cid].timeplayed = sum
        Organizations.timePlayed[cid] = nil
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local ply = GetPlayerObject(src)
    local jobName  = ply and ply.PlayerData and ply.PlayerData.job  and ply.PlayerData.job.name  or nil
    local gangName = ply and ply.PlayerData and ply.PlayerData.gang and ply.PlayerData.gang.name or nil
    local orgName  = gangName or jobName
    if orgName and Organizations.Permissions[orgName] then
        ensureMemberCache(cid, orgName)
        Organizations.Members[cid].lastlogin = now()
        Organizations.timePlayed[cid] = now()
        MySQL.update.await('UPDATE thunder_orgs_player_infos SET lastlogin = ?, organization = ? WHERE citizenid = ?',
            { Organizations.Members[cid].lastlogin, orgName, cid })
    end
end)

-- ========== Bootstrap ==========
CreateThread(function()
    if not Core then
        print(('[%s] ^3QBCore/Qbox não encontrado. O recurso carrega, mas integrações de core ficam limitadas.^0'):format(RES_NAME:upper()))
    end

    if not WaitForMySQL(20000) then
        print(('[%s] ^1ERRO:^0 MySQL global indisponível. Confira se @oxmysql/lib/MySQL.lua está primeiro no fxmanifest.'):format(RES_NAME))
        return
    end

    GenerateCache()
    LoadPaydays()

    local border = string.rep("=", 35)
    print(("^2%s\n[%s] Pronto (QBX) — Painel_ORG\n%s^0"):format(border, RES_NAME, border))
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES_NAME then return end
    local border = string.rep("=", 35)
    print(("^1%s\n[%s] Script Finalizado\n%s^0"):format(border, RES_NAME, border))
end)
