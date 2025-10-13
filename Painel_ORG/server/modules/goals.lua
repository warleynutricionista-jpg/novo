-- server/modules/goals.lua
-- Painel_ORG – Metas diárias (thunder_orgs_goals)
-- Compatível com Qbox/QBCore (opcional), ox_lib e DB.* (bridge_core)
-- ATENÇÃO: Nenhum acesso MySQL direto neste arquivo.

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
-- Helpers: DB-safe (chamadas dinâmicas)
---------------------------------------
local function db_call(path, ...)
    local ctx = rawget(_G, 'DB')
    if not ctx then return nil end
    local ref = ctx
    for part in string.gmatch(path, "[^.]+") do
        ref = (type(ref) == 'table') and ref[part] or nil
        if not ref then break end
    end
    if type(ref) == 'function' then
        local ok, res = pcall(ref, ...)
        if ok then return res end
    end
    return nil
end

-- Wrappers com fallback de nomes (não quebra se o método não existir)
local function DB_GetMyGoals(citizenid, org, day, month)
    return db_call('Goals.GetMy', citizenid, org, day, month)
        or db_call('GetMyGoals', citizenid, org, day, month)
        or {}
end

local function DB_AddProgress(org, citizenid, item, amount, day, month)
    return db_call('Goals.AddProgress', org, citizenid, item, amount, day, month)
        or db_call('AddPlayerFarm', org, citizenid, item, amount, day, month)
        or false
end

local function DB_GetDailyByUser(org, day, month, citizenid)
    return db_call('Goals.GetDailyByUser', org, day, month, citizenid)
        or db_call('GetDailyFarmsByUser', org, day, month, citizenid)
        or {}
end

local function DB_UpdateStep(citizenid, org, day, month, step, reward_step)
    return db_call('Goals.UpdateStep', citizenid, org, day, month, step, reward_step)
        or db_call('UpdGoalStep', citizenid, org, day, month, step, reward_step)
        or false
end

local function DB_GetOrgInfo(org)
    return db_call('Orgs.GetInfo', org)
        or db_call('GetOrgInfo', org)
        or nil
end

local function DB_UpdateOrgBank(org, newBank, historicJson)
    return db_call('Orgs.UpdateBank', org, newBank, historicJson)
        or db_call('UpdateOrgBank', org, newBank, historicJson)
        or false
end

local function DB_UpdateOrgGoals(org, cfgJson)
    return db_call('Orgs.UpdateGoals', org, cfgJson)
        or db_call('UpdateOrgGoals', org, cfgJson)
        or false
end

local function DB_GetDailyTotals(org, day, month)
    return db_call('Goals.GetDailyTotals', org, day, month)
        or {}
end

---------------------------------------
-- Helpers de identidade/org
---------------------------------------
local function getCitizenId(src)
    if type(getUserId) == 'function' then -- do bridge_core (preferencial)
        return getUserId(src)
    end
    if Core and Core.Functions then
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid then
            return Ply.PlayerData.citizenid
        end
    end
    -- fallback: license
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:') then return id end
    end
    return nil
end

local function getSourceByCitizenId(citizenid)
    if type(getUserSource) == 'function' then -- do bridge_core
        return getUserSource(citizenid)
    end
    if not Core or not Core.Functions then return nil end
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        local Ply = Core.Functions.GetPlayer(s)
        if Ply and Ply.PlayerData and Ply.PlayerData.citizenid == citizenid then
            return s
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
    return ('CID:%s'):format(citizenid or '?')
end

local function addBankMoney(src, amount, reason)
    if not Core or not Core.Functions then return false end
    local Ply = Core.Functions.GetPlayer(src)
    if not Ply then return false end
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    return Ply.Functions.AddMoney('bank', amount, reason or 'org-goal')
end

local function deepcopy(tbl)
    local t = {}
    for k, v in pairs(tbl or {}) do
        t[k] = type(v) == "table" and deepcopy(v) or v
    end
    return t
end

local function getOrgFromMember(citizenid)
    if not citizenid or not Organizations or not Organizations.Members then return nil end
    local m = Organizations.Members[citizenid]
    return m and m.groupType or nil
end

local function ensureGoalsConfig(org)
    if Organizations and Organizations.goalsConfig and Organizations.goalsConfig[org] then
        return Organizations.goalsConfig[org]
    end

    -- tenta buscar do DB (via Orgs.GetInfo -> config_goals)
    local info = DB_GetOrgInfo(org)
    local cfg = { info = { defaultReward = 0, itens = {} } }
    if info and info.config_goals and info.config_goals ~= '' then
        local ok, parsed = pcall(json.decode, info.config_goals)
        if ok and type(parsed) == 'table' then
            cfg = parsed
        end
    end

    Organizations.goalsConfig = Organizations.goalsConfig or {}
    Organizations.goalsConfig[org] = cfg
    return cfg
end

---------------------------------------
-- Cooldown simples
---------------------------------------
local GOALS = { cooldown = {} }
local function cooldownCheck(key, seconds)
    local now = os.time()
    local untilTs = GOALS.cooldown[key]
    if untilTs and (untilTs - now) > 0 then
        return (untilTs - now)
    end
    GOALS.cooldown[key] = now + (seconds or 5)
    return 0
end

---------------------------------------
-- Blocos de montagem de payloads
---------------------------------------
local function buildMyGoalsList(org, citizenid, cfg, day, month)
    local myRows = DB_GetMyGoals(citizenid, org, day, month) or {}
    local byItem = {}
    for _, row in ipairs(myRows) do
        local item  = row.item
        local amount= tonumber(row.amount) or 0
        local step  = tonumber(row.step) or 1
        if cfg.info and cfg.info.itens and cfg.info.itens[item] then
            byItem[item] = { amount = amount, step = step }
        end
    end

    local out = {}
    for item, def in pairs((cfg.info and cfg.info.itens) or {}) do
        local mine = byItem[item]
        local step = (mine and mine.step or 1)
        out[#out + 1] = {
            name    = item, -- se quiser label real, mapeie pelo seu inventário aqui
            item    = item,
            needed  = (def.needed and true) or false,
            current = mine and mine.amount or 0,
            max     = (tonumber(def.max) or 0) * step
        }
    end
    return out
end

local function buildMembersWeeklyStatus(org)
    local weekOrder = {2,3,4,5,6,7,1} -- Mon..Sun
    local todayWday = os.date("*t").wday
    local out = {}

    local membersSet = (Organizations.MembersList and Organizations.MembersList[org]) or {}
    for memberCid, _ in pairs(membersSet) do
        local name = getIdentityNameByCitizenId(memberCid)
        local rolePrefix = "Membro"
        local md = Organizations.Members[memberCid]
        if md and md.group and Config and Config.Groups and Config.Groups[org] and Config.Groups[org].List then
            local role = Config.Groups[org].List[md.group]
            if role and role.prefix then rolePrefix = role.prefix end
        end

        local status = {2,2,2,2,2,2,2} -- 1=ok | 2=pendente | 3=hoje pendente
        for i = 0, 6 do
            local offset = (i - (todayWday - 1)) * 86400
            local dt     = os.date("*t", os.time() + offset)
            local rows   = DB_GetDailyByUser(org, dt.day, dt.month, memberCid) or {}
            if rows[1] and tonumber(rows[1].reward_step or 0) >= 1 then
                status[i+1] = 1
            end
        end
        if status[todayWday] ~= 1 then status[todayWday] = 3 end

        local reordered = {}
        for _, idx in ipairs(weekOrder) do
            reordered[#reordered+1] = status[idx]
        end

        out[#out+1] = {
            name   = name,
            role   = rolePrefix,
            status = reordered
        }
    end

    return out
end

---------------------------------------
-- Legacy Tunnel (compat com client antigo)
---------------------------------------
RegisterTunnel = RegisterTunnel or {}

function RegisterTunnel.getGoals()
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return { prize = 0, my = {}, faction = {}, members = {} } end

    local org = getOrgFromMember(citizenid)
    if not org then return { prize = 0, my = {}, faction = {}, members = {} } end

    local cfg   = ensureGoalsConfig(org)
    local day   = tonumber(os.date('%d'))
    local month = tonumber(os.date('%m'))

    local payload = {
        prize   = tonumber((cfg.info and cfg.info.defaultReward) or 0) or 0,
        my      = buildMyGoalsList(org, citizenid, cfg, day, month),
        faction = {},
        members = buildMembersWeeklyStatus(org)
    }
    return payload
end

function RegisterTunnel.rewardGoal()
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return false end

    local org = getOrgFromMember(citizenid)
    if not org then return false end

    local cfg = ensureGoalsConfig(org)
    local reward = tonumber((cfg.info and cfg.info.defaultReward) or 0) or 0
    if reward <= 0 then return false end

    -- cooldown
    if cooldownCheck(citizenid, 5) > 0 then
        if Config and Config.Langs and Config.Langs['waitCooldown'] then
            Config.Langs['waitCooldown'](src)
        end
        return false
    end

    local day   = tonumber(os.date('%d'))
    local month = tonumber(os.date('%m'))

    local myRows = DB_GetMyGoals(citizenid, org, day, month) or {}
    if not myRows[1] then return false end

    -- progresso por item
    local progress = {}
    for _, row in ipairs(myRows) do
        progress[row.item] = {
            amount      = tonumber(row.amount) or 0,
            step        = tonumber(row.step) or 1,
            reward_step = tonumber(row.reward_step) or 0
        }
    end

    -- checar concluídos (apenas itens needed)
    local concluded, needed = 0, 0
    for item, def in pairs((cfg.info and cfg.info.itens) or {}) do
        if def.needed then
            needed = needed + 1
            local row  = progress[item]
            local step = (row and row.step) or 1
            local req  = (tonumber(def.max) or 0) * step
            local have = (row and row.amount) or 0
            if have >= req then concluded = concluded + 1 end
        end
    end
    if concluded < needed then return false end

    -- saldo da organização
    local info = DB_GetOrgInfo(org)
    if not info then return false end
    local orgBank = tonumber(info.bank or 0)
    if orgBank < reward then
        if Config and Config.Langs and Config.Langs['bankNotMoney'] then
            Config.Langs['bankNotMoney'](src)
        end
        return false
    end

    -- atualizar step/reward_step
    local base = myRows[1]
    local newRewardStep = (tonumber(base.reward_step or 0) + 1)
    local newStep       = (tonumber(base.step or 1) + 1)
    DB_UpdateStep(citizenid, org, day, month, newStep, newRewardStep)

    -- histórico do banco (org)
    local historic = {}
    if info.bank_historic and info.bank_historic ~= '' then
        local ok, data = pcall(json.decode, info.bank_historic)
        if ok and type(data) == 'table' then historic = data end
    end
    table.insert(historic, 1, {
        name  = getIdentityNameByCitizenId(citizenid),
        type  = 'META DIARIA',
        value = reward,
        date  = os.date('%d/%m/%Y %X')
    })
    if #historic > 100 then
        while #historic > 100 do table.remove(historic) end
    end

    DB_UpdateOrgBank(org, (orgBank - reward), json.encode(historic))

    -- pagar player
    addBankMoney(src, reward, 'org-goal')

    if Config and Config.Langs and Config.Langs['rewardedGoal'] then
        Config.Langs['rewardedGoal'](src, reward)
    end

    return true
end

function RegisterTunnel.saveGoals(data)
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return false end

    local org = getOrgFromMember(citizenid)
    if not org then return false end

    local mem = Organizations.Members[citizenid]
    if not mem then return false end

    local isLeader = Organizations.Permissions
        and Organizations.Permissions[org]
        and Organizations.Permissions[org][mem.group]
        and Organizations.Permissions[org][mem.group].leader

    if not isLeader then return false end

    local t = { info = { defaultReward = tonumber(data and data.payment) or 0, itens = {} } }
    if data and type(data.items) == 'table' then
        for _, it in ipairs(data.items) do
            if it.item and it.max then
                t.info.itens[it.item] = { max = tonumber(it.max) or 0, needed = (it.needed and true) or false }
            end
        end
    end

    Organizations.goalsConfig = Organizations.goalsConfig or {}
    Organizations.goalsConfig[org] = deepcopy(t)
    DB_UpdateOrgGoals(org, json.encode(t))
    return true
end

---------------------------------------
-- ox_lib callbacks (NOVOS endpoints pro client atual)
---------------------------------------
if lib and lib.callback and lib.callback.register then
    -- Config bruta das metas (carrega do cache/DB)
    lib.callback.register('Painel_ORG:goals:getConfig', function(source, orgOverride)
        local cid = getCitizenId(source); if not cid then return {} end
        local org = orgOverride or getOrgFromMember(cid); if not org then return {} end
        local cfg = ensureGoalsConfig(org)
        return cfg or {}
    end)

    -- Payload completo (minhas metas + membros/semana + prêmio)
    lib.callback.register('Painel_ORG:goals:get', function(source)
        return RegisterTunnel.getGoals()
    end)

    -- “Farms” do dia: ranking (se DB tiver agregado), senão lista vazia segura
    lib.callback.register('Painel_ORG:goals:getFarms', function(source)
        local cid = getCitizenId(source); if not cid then return {} end
        local org = getOrgFromMember(cid); if not org then return {} end
        local day   = tonumber(os.date('%d'))
        local month = tonumber(os.date('%m'))
        local rows  = DB_GetDailyTotals(org, day, month) or {}
        -- rows sugeridos: { { name="", citizenid="", item="", amount=0 }, ... }
        return rows
    end)

    -- Resgatar recompensa
    lib.callback.register('Painel_ORG:goals:redeem', function(source, _)
        return RegisterTunnel.rewardGoal()
    end)

    -- Fallback do client (quando RedeemGoals não existir)
    lib.callback.register('Painel_ORG:goals:addProgress', function(source, data)
        local cid = getCitizenId(source); if not cid then return false end
        local org = getOrgFromMember(cid); if not org then return false end
        local item   = data and data.item
        local amount = tonumber(data and data.amount or 0) or 0
        if not item or amount <= 0 then return false end
        local day   = tonumber(os.date('%d'))
        local month = tonumber(os.date('%m'))
        return DB_AddProgress(org, cid, item, amount, day, month) and true or false
    end)

    -- Salvar config (líder)
    lib.callback.register('Painel_ORG:goals:save', function(source, data)
        return RegisterTunnel.saveGoals(data)
    end)
end

---------------------------------------
-- Export público: addGoal(idOrCid, item, amount)
---------------------------------------
exports('addGoal', function(idOrCitizenId, item, amount)
    if not idOrCitizenId or not item then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local citizenid
    if type(idOrCitizenId) == 'number' then
        citizenid = getCitizenId(idOrCitizenId)
    else
        citizenid = idOrCitizenId
    end
    if not citizenid then return end

    local org = getOrgFromMember(citizenid)
    if not org then return end

    local cfg = ensureGoalsConfig(org)
    if not (cfg and cfg.info and cfg.info.itens and cfg.info.itens[item]) then
        -- item não configurado nas metas da org; ignorar silenciosamente
        return
    end

    local day   = tonumber(os.date('%d'))
    local month = tonumber(os.date('%m'))

    DB_AddProgress(org, citizenid, item, amount, day, month)
end)
