-- client/main.lua
-- Painel_ORG - client bootstrap + NUI bridge (ox_lib)
-- Endpoints mapeados: GetPainelInfos, Chat, Avisos, Membros, Goals, Parceiros,
-- Banco (GetExtracts/Deposit/Withdraw), Permissões, Config, Rádio.

local uiOpen = false
local RES_NAME = GetCurrentResourceName()

---------------------------------------------------------------------
-- Utils
---------------------------------------------------------------------
local function notify(msg, typ)
    if lib and lib.notify then
        lib.notify({ description = msg, type = typ or 'inform' })
    else
        print(('[%s] %s'):format(RES_NAME, msg))
    end
end

local function openUI(payload)
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', data = payload or {} })
end

local function closeUI()
    if not uiOpen then return end
    pcall(function() lib.callback.await('Painel_ORG:close', false) end)
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- bloqueio de controles enquanto a NUI estiver aberta
CreateThread(function()
    while true do
        if uiOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 18, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 106, true)
        end
        Wait(0)
    end
end)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function fetchAndOpen(orgOverride)
    local ok, payload = pcall(function()
        return lib.callback.await('Painel_ORG:getFaction', false, orgOverride)
    end)
    if not ok or not payload then
        return notify('Não foi possível carregar sua organização ou você não pertence a uma.', 'error')
    end
    openUI(payload)
end

-- Normaliza CONFIG de metas para ARRAY
local function normalizeGoalsConfig(cfg)
    if type(cfg) == 'table' and cfg[1] then return cfg end        -- já é array
    if type(cfg) == 'table' and type(cfg.items) == 'table' then
        return cfg.items
    end
    local out, itens = {}, cfg and cfg.info and cfg.info.itens
    if type(itens) == 'table' then
        for item, def in pairs(itens) do
            out[#out+1] = {
                item   = item,
                name   = item,
                amount = tonumber(def.max) or 0,
                needed = def.needed and true or false,
            }
        end
    end
    return out
end

-- Normaliza PAYLOAD de metas
local function normalizeGoalsPayload(p)
    if type(p) ~= 'table' then p = {} end
    p.prize   = tonumber(p.prize) or 0
    p.my      = type(p.my) == 'table' and p.my or {}
    p.faction = type(p.faction) == 'table' and p.faction or {}
    return p
end

-- Normaliza ARRAY de extratos do banco
local function asString(v)
    if v == nil then return '' end
    return tostring(v)
end
local function asNumber(v)
    return tonumber(v or 0) or 0
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
    for i=1,#tmp do
        out[i] = tmp[i].value
    end
    return out
end

local function normalizeExtractArray(any)
    -- se já vier um array, usa; se vier objeto {extracts=...}, pega a lista; se vier nada, []
    local arr = {}
    if type(any) == 'table' and any[1] then
        arr = toSequentialArray(any)
    elseif type(any) == 'table' and type(any.extracts) == 'table' then
        arr = toSequentialArray(any.extracts)
    else
        arr = {}
    end

    -- garantir tipos por lançamento: evita 'slice/map' crash no React
    for i=1,#arr do
        local e = arr[i] or {}
        e.date        = asString(e.date or e.created_at or e.time or os.date('%d/%m/%Y %H:%M'))
        e.value       = asNumber(e.value)
        e.action      = asString(e.action or e.type or 'TRANSACAO')
        e.org_balance = asNumber(e.org_balance or e.bank or e.balance)
        e.balance     = asNumber(e.balance) -- alguns bundles usam 'balance' por item
        arr[i] = e
    end
    return arr
end

local function absInt(n)
    n = tonumber(n or 0) or 0
    if n < 0 then n = -n end
    return math.floor(n + 0.5)
end

---------------------------------------------------------------------
-- Abrir/Fechar
---------------------------------------------------------------------
RegisterNetEvent('Painel_ORG:open', function(orgOverrideOrPayload)
    if type(orgOverrideOrPayload) == 'table' then
        openUI(orgOverrideOrPayload)
    else
        fetchAndOpen(orgOverrideOrPayload)
    end
end)

RegisterNetEvent('Painel_ORG:client:open', function(payload)
    if payload then openUI(payload) else fetchAndOpen(nil) end
end)

---------------------------------------------------------------------
-- NUI Callbacks
---------------------------------------------------------------------

-- Painel inicial
RegisterNUICallback('GetPainelInfos', function(data, cb)
    local ok, payload = pcall(function()
        return lib.callback.await('Painel_ORG:getFaction', false, data and data.org or nil)
    end)
    cb(ok and payload or nil)
end)

-- Chat
RegisterNUICallback('New:Message', function(data, cb)
    local msg = data and data.message
    if not msg or msg == '' then return cb({ ok = false }) end
    local ok, sent = pcall(function()
        return lib.callback.await('Painel_ORG:sendMessage', false, msg)
    end)
    cb({ ok = ok and sent == true })
end)

RegisterNUICallback('GetChatMessages', function(_, cb)
    local ok, list = pcall(function()
        return lib.callback.await('Painel_ORG:getChatMessages', false)
    end)
    cb(ok and (list or {}) or {})
end)

RegisterNUICallback('GetMessages', function(_, cb)
    local ok, list = pcall(function()
        return lib.callback.await('Painel_ORG:getChatMessages', false)
    end)
    cb(ok and (list or {}) or {})
end)

-- Avisos
RegisterNUICallback('NewWarn', function(data, cb)
    local msg = (data and (data.message or data.title)) or ''
    if msg == '' then return cb({ ok = false, data = {} }) end
    local ok, hist = pcall(function()
        return lib.callback.await('Painel_ORG:addWarn', false, msg)
    end)
    cb(ok and (hist or {}) or {})
end)

RegisterNUICallback('DeleteWarning', function(data, cb)
    local ok, hist = pcall(function()
        return lib.callback.await('Painel_ORG:warns:delete', false, data and (data.id or data.date))
    end)
    if ok and hist then return cb(hist) end
    local ok2, payload = pcall(function()
        return lib.callback.await('Painel_ORG:getFaction', false)
    end)
    cb((ok2 and payload and payload.warnings) or {})
end)

-- Membros
RegisterNUICallback('GetMembers', function(_, cb)
    local ok, members = pcall(function()
        return lib.callback.await('Painel_ORG:members:get', false)
    end)
    cb(ok and (members or {}) or {})
end)

RegisterNUICallback('ContractMember', function(data, cb)
    local id = data and (data.id or data.playerId)
    if not id then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:members:invite', false, id)
    end)
    cb(ok and res == true)
end)

RegisterNUICallback('PromoteMember', function(data, cb)
    local id = data and data.id; if not id then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, { action = 'promote', memberId = id })
    end)
    cb(ok and res or false)
end)

RegisterNUICallback('DemoteMember', function(data, cb)
    local id = data and data.id; if not id then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, { action = 'demote', memberId = id })
    end)
    cb(ok and res or false)
end)

RegisterNUICallback('DimissMember', function(data, cb)
    local id = data and data.id; if not id then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, { action = 'dismiss', memberId = id })
    end)
    cb(ok and (res == true) or false)
end)

-- Metas (Goals)
RegisterNUICallback('GetGoalsConfig', function(data, cb)
    local ok, cfg = pcall(function()
        return lib.callback.await('Painel_ORG:goals:getConfig', false, data and data.org or nil)
    end)
    cb(normalizeGoalsConfig(ok and cfg or {}))
end)

RegisterNUICallback('GetGoals', function(_, cb)
    local ok, payload = pcall(function()
        return lib.callback.await('Painel_ORG:goals:get', false)
    end)
    cb(normalizeGoalsPayload(ok and payload or {}))
end)

RegisterNUICallback('GetFarms', function(_, cb)
    local ok, list = pcall(function()
        return lib.callback.await('Painel_ORG:goals:getFarms', false)
    end)
    cb(ok and (list or {}) or {})
end)

RegisterNUICallback('RedeemGoals', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:goals:redeem', false, data or {})
    end)
    cb(ok and (res or false) or false)
end)

-- Parceiros
RegisterNUICallback('GetPartners', function(_, cb)
    local ok, list = pcall(function()
        return lib.callback.await('Painel_ORG:partners:get', false)
    end)
    if ok and list then return cb(list) end
    TriggerServerEvent('getPartners') -- fallback
    cb({})
end)

RegisterNUICallback('DeletePartner', function(data, cb)
    if not data or not data.id then return cb(false) end
    TriggerServerEvent('deletePartner', tonumber(data.id))
    cb(true)
end)

RegisterNUICallback('GetCDS', function(_, cb)
    TriggerServerEvent('mirtin_partners:server:GetAllCoords')
    cb(true)
end)

RegisterNUICallback('MarkLocal', function(data, cb)
    local coords = data and data.coords
    if type(coords) == 'table' and coords.x and coords.y then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        cb(true)
    else
        cb(false)
    end
end)

RegisterNUICallback('MarkFaction', function(_, cb)
    cb(true)
end)

-- Banco (FAÇA APENAS AQUI – não duplique em outro arquivo)
RegisterNUICallback('GetExtracts', function(_, cb)
    local ok, resp = pcall(function()
        return lib.callback.await('Painel_ORG:bank:get', false)
    end)
    if not ok then resp = {} end
    cb(normalizeExtractArray(resp))  -- <<< SEMPRE ARRAY
end)

RegisterNUICallback('Deposit', function(data, cb)
    local amount = absInt(data and (data.amount or data.value))
    if amount <= 0 then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:bank:deposit', false, amount)
    end)
    cb(ok and res == true)
end)

RegisterNUICallback('Withdraw', function(data, cb)
    local amount = absInt(data and (data.amount or data.value))
    if amount <= 0 then return cb(false) end
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:bank:withdraw', false, amount)
    end)
    cb(ok and res == true)
end)

-- Permissões / Config / Rádio
RegisterNUICallback('GetPermissions', function(_, cb)
    local ok, perms = pcall(function()
        return lib.callback.await('Painel_ORG:perms:get', false)
    end)
    cb(ok and (perms or {}) or {})
end)

RegisterNUICallback('SetPermissions', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:perms:set', false, data or {})
    end)
    cb(ok and (res == true) or false)
end)

RegisterNUICallback('SetConfig', function(data, cb)
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:config:set', false, data or {})
    end)
    cb(ok and (res == true) or false)
end)

RegisterNUICallback('ConnectRadio', function(data, cb)
    local freq = tonumber(data and (data.freq or data.frequency)) or 0
    -- pcall(function() exports['pma-voice']:setRadioChannel(freq) end) -- opcional
    cb(true)
end)

RegisterNUICallback('SetRadio', function(data, cb)
    local freq = data and (data.freq or data.frequency) or ''
    local ok, res = pcall(function()
        return lib.callback.await('Painel_ORG:config:setRadio', false, tostring(freq))
    end)
    cb(ok and (res == true) or false)
end)

-- Fechar pela NUI
RegisterNUICallback('close',      function(_, cb) closeUI(); if cb then cb(true) end end)
RegisterNUICallback('forceClose', function(_, cb) closeUI(); if cb then cb(true) end end)

---------------------------------------------------------------------
-- Eventos -> NUI
---------------------------------------------------------------------
RegisterNetEvent('updateWarnings', function(historic)
    if uiOpen then SendNUIMessage({ action = 'UpdateWarnings', data = historic or {} }) end
end)

RegisterNetEvent('updateChatMessage', function(message)
    if uiOpen then SendNUIMessage({ action = 'UpdateChat', data = message }) end
end)

RegisterNetEvent('Painel_ORG:updateMembers', function(list)
    if uiOpen then SendNUIMessage({ action = 'UpdateMembers', data = list or {} }) end
end)

-- Atualização do banco: cobre ambos formatos
RegisterNetEvent('updateExtract', function(bundle)
    if not uiOpen then return end
    local arr = normalizeExtractArray(bundle)
    SendNUIMessage({ action = 'UpdateExtracts',      data = arr })
    if type(bundle) == 'table' then
        if bundle.balance ~= nil       then SendNUIMessage({ action = 'UpdateBalance',       data = tonumber(bundle.balance) or 0 }) end
        if bundle.playerBalance ~= nil then SendNUIMessage({ action = 'UpdatePlayerBalance', data = tonumber(bundle.playerBalance) or 0 }) end
    end
    -- alguns bundles usam um único action consolidado
    SendNUIMessage({ action = 'updateExtract', data = { extracts = arr, balance = (bundle and bundle.balance) or 0, playerBalance = (bundle and bundle.playerBalance) or 0 } })
end)

-- Legado
RegisterNetEvent('receivePartners', function(partners)
    if uiOpen then SendNUIMessage({ action = 'receivePartners', data = partners or {} }) end
end)
RegisterNetEvent('partnerAdded', function(success)
    if uiOpen then SendNUIMessage({ action = 'partnerAdded', data = success and true or false }) end
end)
RegisterNetEvent('partnerDeleted', function(partnerId)
    if uiOpen then SendNUIMessage({ action = 'partnerDeleted', data = partnerId }) end
end)
RegisterNetEvent('mirtin_partners:client:ReceiveAllCoords', function(list)
    if uiOpen then SendNUIMessage({ action = 'partners:coords', data = list or {} }) end
end)
RegisterNetEvent('mirtin_partners:client:ReceiveData', function(rows)
    if uiOpen then SendNUIMessage({ action = 'historico:data', data = rows or {} }) end
end)

---------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------
local function togglePanel()
    if uiOpen then
        closeUI()
    else
        fetchAndOpen(nil)
    end
end

local function sanitizeCommand(name)
    if type(name) ~= 'string' then return nil end
    local sanitized = name:match('^%s*(.-)%s*$')
    if not sanitized or sanitized == '' then return nil end
    return sanitized
end

local registeredCommands = {}

local function registerPanelCommand(cmdName, toggle)
    local command = sanitizeCommand(cmdName)
    if not command or registeredCommands[command] then return command end
    RegisterCommand(command, toggle and togglePanel or function(_, args)
        local override = sanitizeCommand(args and args[1])
        fetchAndOpen(override)
    end, false)
    registeredCommands[command] = true
    return command
end

local configured = Config and Config.Main or {}
local mainCmd = registerPanelCommand(configured.cmd or 'painel', true) or 'painel'

if mainCmd then
    RegisterKeyMapping(mainCmd, 'Abrir Painel de Organizações', 'keyboard', 'F6')
end

-- Comando alternativo legado
if mainCmd ~= 'painel' then
    registerPanelCommand('painel', true)
end

-- Comando direto para forçar abertura (permite override por argumento)
registerPanelCommand('org_ui', false)

-- Comando administrativo configurável
if configured.cmdAdm and configured.cmdAdm ~= '' then
    registerPanelCommand(configured.cmdAdm, false)
end

---------------------------------------------------------------------
-- Limpeza
---------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == RES_NAME and uiOpen then closeUI() end
end)
