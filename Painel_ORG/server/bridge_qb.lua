-- server/bridge_qb.lua
local QBCore
CreateThread(function()
    local cands = { 'qbx_core', 'qbx-core', 'qb-core', 'qb_core', 'qbcore' }
    for _,res in ipairs(cands) do
        if GetResourceState(res) == 'started' then
            local ex = exports[res]
            for _,fn in ipairs({ 'GetCoreObject','getCoreObject','GetQBCore','getQBCore','GetCore','getCore' }) do
                if ex and ex[fn] then QBCore = ex[fn]() break end
            end
        end
        if QBCore then break end
    end
    if not QBCore then print('^3[orgs-bridge]^7 QBCore não encontrado; inicie qb/qbx antes.') end
end)

-- armazenamos as prepares como o vRP fazia
local _prepares = {}
vRP = vRP or {}

function vRP.prepare(name, sql)
    _prepares[name] = sql
end

function vRP.query(name, params)
    local sql = _prepares[name]
    if not sql then
        print(('[orgs-bridge] query() prepare ausente: %s'):format(name))
        return {}
    end
    return MySQL.query.await(sql, params or {}) or {}
end

function vRP.execute(name, params)
    local sql = _prepares[name]
    if not sql then
        print(('[orgs-bridge] execute() prepare ausente: %s'):format(name))
        return 0
    end
    -- usamos update.await, que retorna linhas afetadas
    return MySQL.update.await(sql, params or {}) or 0
end

-- =========================
-- MAPEAMENTO citizenid <-> user_id(INT)
-- =========================
local function ensureUserIdByCitizen(citizenid)
    if not citizenid then return nil end
    local row = MySQL.single.await('SELECT user_id FROM mirtin_uidmap WHERE citizenid = ?', { citizenid })
    if row and row.user_id then return row.user_id end
    local id = MySQL.insert.await('INSERT INTO mirtin_uidmap (citizenid) VALUES (?)', { citizenid })
    return id
end

local function getCitizenByUserId(user_id)
    return MySQL.single.await('SELECT citizenid FROM mirtin_uidmap WHERE user_id = ?', { user_id })
end

function getUserId(source)
    if not QBCore then return nil end
    local P = QBCore.Functions.GetPlayer(source)
    if not P then return nil end
    return ensureUserIdByCitizen(P.PlayerData.citizenid)
end

function getUserSource(user_id)
    if not QBCore then return nil end
    local map = getCitizenByUserId(user_id)
    if not map or not map.citizenid then return nil end
    for _,src in ipairs(QBCore.Functions.GetPlayers()) do
        local P = QBCore.Functions.GetPlayer(src)
        if P and P.PlayerData.citizenid == map.citizenid then
            return src
        end
    end
    return nil
end

function getUserIdentity(user_id)
    local map = getCitizenByUserId(user_id)
    if not map or not map.citizenid then return nil end
    -- tabela padrão do qb: players(charinfo json)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { map.citizenid })
    if not row or not row.charinfo then return nil end
    local info = json.decode(row.charinfo) or {}
    return {
        name = info.firstname or info.first or '',
        firstname = info.lastname or info.last or ''
    }
end

-- =========================
-- GRUPOS / PERMISSÕES
-- =========================
function vRP.getUserGroups(user_id)
    local src = getUserSource(user_id)
    if not src then return {} end
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return {} end
    local t = {}
    -- job
    if P.PlayerData.job and P.PlayerData.job.name then
        t[P.PlayerData.job.name] = true
        local g = P.PlayerData.job.grade and (P.PlayerData.job.grade.name or P.PlayerData.job.grade.level or P.PlayerData.job.grade)
        if g then t[tostring(g)] = true end
    end
    -- gang (opcional)
    if P.PlayerData.gang and P.PlayerData.gang.name then
        t[P.PlayerData.gang.name] = true
        local gg = P.PlayerData.gang.grade and (P.PlayerData.gang.grade.name or P.PlayerData.gang.grade.level or P.PlayerData.gang.grade)
        if gg then t[tostring(gg)] = true end
    end
    return t
end

function vRP.hasGroup(user_id, group)
    local g = vRP.getUserGroups(user_id)
    return g[group] == true
end

-- =========================
-- BANCO ($) – equivalente a vRP.giveBankMoney usado em metas
-- =========================
function vRP.giveBankMoney(user_id, amount)
    local src = getUserSource(user_id)
    if not src then return end
    local P = QBCore.Functions.GetPlayer(src)
    if P then
        P.Functions.AddMoney('bank', math.floor(amount or 0), 'orgs-reward')
    end
end
