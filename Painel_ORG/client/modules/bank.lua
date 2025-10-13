-- client/modules/bank.lua
-- NUI <-> Client para extratos e transações do banco da organização
-- Endpoints novos:   Painel_ORG:bank:get | :deposit | :withdraw
-- Endpoints legados: Painel_ORG:bank:getInfos | :bank:transaction

-- Evita registrar duas vezes caso este arquivo seja incluído mais de uma vez
if _G.__PAINEL_ORG_BANK_CB_REGISTERED then return end
_G.__PAINEL_ORG_BANK_CB_REGISTERED = true

-------------------------------------------------
-- Normalizadores + util
-------------------------------------------------
local function asNumber(v) return tonumber(v or 0) or 0 end
local function asString(v) if v == nil then return '' end return tostring(v) end

local function normalizeEntry(e)
    e = type(e) == 'table' and e or {}
    return {
        date        = asString(e.date or e.created_at or e.time or os.date('%d/%m/%Y %H:%M')),
        action      = asString(e.action or e.type or 'TRANSACAO'),
        value       = asNumber(e.value),
        org_balance = asNumber(e.org_balance or e.bank or e.balance),
        balance     = asNumber(e.balance), -- compat com alguns bundles
        name        = asString(e.name or e.author or '')
    }
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

-- resp pode ser array OU { extracts=[...], balance, playerBalance }
local function normalizeExtractArray(resp)
    local list
    if type(resp) == 'table' and resp[1] then
        list = toSequentialArray(resp)
    elseif type(resp) == 'table' and type(resp.extracts) == 'table' then
        list = toSequentialArray(resp.extracts)
    else
        list = {}
    end

    local out = {}
    for i = 1, #list do out[i] = normalizeEntry(list[i]) end

    local balance       = 0
    local playerBalance = 0
    if type(resp) == 'table' then
        balance       = asNumber(resp.balance)
        playerBalance = asNumber(resp.playerBalance or resp.player_balance)
    end

    return out, balance, playerBalance
end

local function cleanAmount(v)
    local n = asNumber(v)
    if n < 0 then n = -n end
    n = math.floor(n + 0.5) -- inteiro
    if n > 1000000000 then n = 1000000000 end -- trava anti-absurdo
    return n
end

local function cb_ok(cb, val) if cb then cb(val) end end

-------------------------------------------------
-- NUI Callbacks
-------------------------------------------------

-- A NUI espera um **ARRAY** para preencher o extrato (usa .map)
RegisterNUICallback('GetExtracts', function(_, cb)
    local ok, resp = pcall(function()
        return lib.callback.await('Painel_ORG:bank:get', false)
    end)
    if not ok then
        ok, resp = pcall(function()
            return lib.callback.await('Painel_ORG:bank:getInfos', false) -- legado
        end)
    end

    local extracts, balance, playerBalance = normalizeExtractArray(ok and resp or {})

    -- 1) resposta do próprio fetch (array puro p/ .map da NUI)
    cb_ok(cb, extracts)

    -- 2) alguns bundles atualizam saldos por mensagens separadas
    SendNUIMessage({ action = 'UpdateBalance',       data = balance })
    SendNUIMessage({ action = 'UpdatePlayerBalance', data = playerBalance })
end)

RegisterNUICallback('Withdraw', function(data, cb)
    local amount = cleanAmount(data and (data.amount or data.value))
    if amount <= 0 then return cb_ok(cb, false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:bank:withdraw', false, amount)
    end)
    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:bank:transaction', false, { type = 'withdraw', amount = amount })
        end)
    end
    cb_ok(cb, ok and (result == true or result == 1))
end)

RegisterNUICallback('Deposit', function(data, cb)
    local amount = cleanAmount(data and (data.amount or data.value))
    if amount <= 0 then return cb_ok(cb, false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:bank:deposit', false, amount)
    end)
    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:bank:transaction', false, { type = 'deposit', amount = amount })
        end)
    end
    cb_ok(cb, ok and (result == true or result == 1))
end)

-------------------------------------------------
-- Push do servidor após transações
-------------------------------------------------
-- Aceita bundle completo OU array, e repassa em:
-- (a) unificado: updateExtract
-- (b) fragmentado: UpdateExtracts/UpdateBalance/UpdatePlayerBalance
RegisterNetEvent('updateExtract', function(data)
    if not data then return end
    local extracts, balance, playerBalance = normalizeExtractArray(data)

    SendNUIMessage({ action = 'updateExtract', data = {
        extracts = extracts, balance = balance, playerBalance = playerBalance
    }})

    SendNUIMessage({ action = 'UpdateExtracts',      data = extracts })
    SendNUIMessage({ action = 'UpdateBalance',       data = balance })
    SendNUIMessage({ action = 'UpdatePlayerBalance', data = playerBalance })
end)
