-- server/modules/bank.lua
-- Painel_ORG – Banco da organização (thunder_orgs_info)
-- Compat: Qbox/QBCore + ox_lib + oxmysql (via MySQL.*.await / DB.* do bridge_core)
-- Agora com callbacks para a NUI: GetExtracts / Deposit / Withdraw

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
-- Helpers de identidade & core
---------------------------------------
local function getCitizenId(src)
    if type(getUserId) == 'function' then
        return getUserId(src) -- do bridge_core
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

local function getIdentity(src)
    if type(getUserIdentity) == 'function' then
        return getUserIdentity(src) -- do bridge_core
    end
    if Core and Core.Functions then
        local Ply = Core.Functions.GetPlayer(src)
        if Ply and Ply.PlayerData and Ply.PlayerData.charinfo then
            local c = Ply.PlayerData.charinfo
            local first = c.firstname or 'N/A'
            local last  = c.lastname or ''
            local full  = ("%s %s"):format(first, last):gsub('%s+$','')
            return { name = full, firstname = first, lastname = last }
        end
    end
    local fallback = GetPlayerName(src) or ('Jogador %s'):format(src or '?')
    return { name = fallback, firstname = fallback, lastname = '' }
end

local function getPlayer(src)
    if not Core or not Core.Functions then return nil end
    return Core.Functions.GetPlayer(src)
end

-- Adapter “conta bancária” do player (QBCore)
local function getPlayerBankBalance(ply)
    if not ply then return 0 end
    local ok, val = pcall(function() return ply.Functions.GetMoney('bank') end)
    if ok then return tonumber(val) or 0 end
    return 0
end

local function addPlayerBank(ply, amount, reason)
    if ply and amount and amount > 0 then
        pcall(function() ply.Functions.AddMoney('bank', amount, reason or 'ORG:CRÉDITO') end)
    end
end

local function removePlayerBank(ply, amount, reason)
    if not ply or not amount or amount <= 0 then return false end
    local ok = pcall(function() ply.Functions.RemoveMoney('bank', amount, reason or 'ORG:DÉBITO') end)
    return ok
end

---------------------------------------
-- Helpers de organização (usam DB.* do bridge_core)
---------------------------------------
local function getPlayerOrganization(src)
    local cid = getCitizenId(src)
    if not cid then return nil, nil end

    -- 1) cache em memória
    if Organizations and Organizations.Members and Organizations.Members[cid] then
        local org = Organizations.Members[cid].groupType
        if org and org ~= '' then return org, cid end
    end

    -- 2) fallback DB (bridge_core)
    if DB and DB.GetUserInfo then
        local row = DB.GetUserInfo(cid)
        if row and row.organization and row.organization ~= '' then
            return row.organization, cid
        end
    end

    return nil, cid
end

local function toSequentialArray(list)
    if type(list) ~= 'table' then return {} end

    local tmp = {}
    for k, v in pairs(list) do
        local idx
        if type(k) == 'number' then
            idx = k
        elseif type(k) == 'string' then
            idx = tonumber(k)
        end
        if idx then
            tmp[#tmp+1] = { index = idx, value = v }
        end
    end

    if #tmp == 0 then return {} end

    table.sort(tmp, function(a, b) return a.index < b.index end)

    local out = {}
    for i=1,#tmp do out[i] = tmp[i].value end
    return out
end

local function readOrgBank(org)
    if not (DB and DB.GetOrgBank) or not org then return 0, {} end
    local info = DB.GetOrgBank(org)
    if not info then return 0, {} end
    local bank = tonumber(info.bank) or 0
    local hist = {}
    if type(info.bank_historic) == 'string' and info.bank_historic ~= '' then
        local ok, val = pcall(json.decode, info.bank_historic)
        if ok and type(val) == 'table' then hist = val end
    end
    return bank, toSequentialArray(hist)
end

local function writeOrgBank(org, bank, hist)
    if not (DB and DB.UpdateOrgBank) or not org then return 0 end
    local payload = json.encode(hist or {})
    local affected = DB.UpdateOrgBank(org, tonumber(bank) or 0, payload)
    if (affected or 0) == 0 and MySQL and MySQL.insert and MySQL.insert.await then
        MySQL.insert.await(
            "INSERT IGNORE INTO thunder_orgs_info (organization, bank, bank_historic) VALUES (?, ?, ?)",
            { org, tonumber(bank) or 0, payload }
        )
        affected = DB.UpdateOrgBank(org, tonumber(bank) or 0, payload)
    end
    return affected or 0
end

-- controla o tamanho do extrato
local function pushHistoric(historic, data, cap)
    historic = historic or {}
    cap = cap or 40
    while #historic >= cap do table.remove(historic, 1) end
    historic[#historic+1] = data
    return historic
end

---------------------------------------
-- Cooldown simples por organização
---------------------------------------
BANK = BANK or { cooldown = {} }

local function checkCooldown(key, seconds)
    local now = os.time()
    local cd = BANK.cooldown[key] or 0
    if cd > now then return false, (cd - now) end
    BANK.cooldown[key] = now + (seconds or 5)
    return true, 0
end

---------------------------------------
-- API legado (túnel) - opcional
---------------------------------------
RegisterTunnel = RegisterTunnel or {}

function RegisterTunnel.getBankInfos()
    local src = source
    local org = getPlayerOrganization(src)
    if not org then return {} end
    local _, hist = readOrgBank(org)
    return hist
end

function RegisterTunnel.transactionBank(payload)
    local src = source
    if type(payload) ~= 'table' then return false end
    local ttype  = payload.type              -- 'deposit' | 'withdraw'
    local amount = tonumber(payload.amount or 0) or 0
    if (ttype ~= 'deposit' and ttype ~= 'withdraw') or amount <= 0 then
        return false
    end

    local org, cid = getPlayerOrganization(src)
    if not org then return false end

    local ok = select(1, checkCooldown(org, 5))
    if not ok then
        if Config and Config.Langs and Config.Langs['waitCooldown'] then
            Config.Langs['waitCooldown'](src)
        end
        return false
    end

    local bankValue, hist = readOrgBank(org)
    local idt = getIdentity(src)
    local first = idt and idt.firstname or ''
    local last  = idt and idt.lastname or ''
    local composed = ('%s %s'):format(first, last):gsub('%s+$','')
    local fullName = (composed ~= '' and composed) or (idt and idt.name) or 'Desconhecido'
    local ply = getPlayer(src) -- pode ser nil

    -- checagem de permissão (se Organizations estiver populado)
    local hasPerm = true
    if Organizations and Organizations.Permissions and Organizations.Members and Organizations.Members[cid] then
        local gtype = Organizations.Members[cid].groupType
        local group = Organizations.Members[cid].group
        hasPerm = Organizations.Permissions[gtype]
              and Organizations.Permissions[gtype][group]
              and ((ttype == 'deposit' and Organizations.Permissions[gtype][group].deposit)
                or (ttype == 'withdraw' and Organizations.Permissions[gtype][group].withdraw)) or false
    end
    if not hasPerm then
        if Config and Config.Langs and Config.Langs['notPermission'] then
            Config.Langs['notPermission'](src)
        end
        return false
    end

    if ttype == 'deposit' then
        if ply then
            local myBank = getPlayerBankBalance(ply)
            if myBank < amount then
                if Config and Config.Langs and Config.Langs['notMoneyDeposit'] then
                    Config.Langs['notMoneyDeposit'](src)
                end
                return false
            end
            removePlayerBank(ply, amount, ('ORG:%s DEPÓSITO'):format(org))
        end
        local newBank = bankValue + amount
        hist = pushHistoric(hist, {
            name  = fullName,
            type  = 'DEPÓSITO',
            value = amount,
            date  = os.date('%d/%m/%Y %X'),
        })
        writeOrgBank(org, newBank, hist)

        TriggerClientEvent('updateExtract', src, {
            balance       = newBank,
            extracts      = hist,
            playerBalance = ply and getPlayerBankBalance(ply) or 0
        })
        return true
    end

    if ttype == 'withdraw' then
        if amount > bankValue then
            if Config and Config.Langs and Config.Langs['bankNotMoney'] then
                Config.Langs['bankNotMoney'](src)
            end
            return false
        end
        local newBank = bankValue - amount
        hist = pushHistoric(hist, {
            name  = fullName,
            type  = 'SAQUE',
            value = amount,
            date  = os.date('%d/%m/%Y %X'),
        })
        writeOrgBank(org, newBank, hist)

        if ply then addPlayerBank(ply, amount, ('ORG:%s SAQUE'):format(org)) end
        TriggerClientEvent('updateExtract', src, {
            balance       = newBank,
            extracts      = hist,
            playerBalance = ply and getPlayerBankBalance(ply) or 0
        })
        return true
    end

    return false
end

---------------------------------------
-- ox_lib callbacks (para a NUI via client)
---------------------------------------
if lib and lib.callback and lib.callback.register then
    -- NUI: GetExtracts
    lib.callback.register('Painel_ORG:bank:get', function(source)
        local org = getPlayerOrganization(source)
        if not org then return { balance = 0, extracts = {}, playerBalance = 0 } end
        local bankValue, hist = readOrgBank(org)
        local ply = getPlayer(source)
        return {
            balance       = bankValue,
            extracts      = hist,
            playerBalance = ply and getPlayerBankBalance(ply) or 0
        }
    end)

    -- NUI: Deposit
    lib.callback.register('Painel_ORG:bank:deposit', function(source, amount)
        amount = tonumber(amount or 0) or 0
        if amount <= 0 then return false end
        return RegisterTunnel.transactionBank({ type = 'deposit', amount = amount }) or false
    end)

    -- NUI: Withdraw
    lib.callback.register('Painel_ORG:bank:withdraw', function(source, amount)
        amount = tonumber(amount or 0) or 0
        if amount <= 0 then return false end
        return RegisterTunnel.transactionBank({ type = 'withdraw', amount = amount }) or false
    end)

    -- compat: request “transação genérica”
    lib.callback.register('Painel_ORG:bank:transaction', function(source, data)
        return RegisterTunnel.transactionBank(data or {}) or false
    end)
end
