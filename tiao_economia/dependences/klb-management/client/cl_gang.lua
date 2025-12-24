-- KLB Management • Gang (Facções) — Client
-- Compatível com qbx-core e qb-core. Envia rótulos PT-BR à NUI.

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------
local QBCore = (function()
    local ok, obj = pcall(function() return exports['qbx-core']:GetCoreObject() end)
    if ok and obj then return obj end
    ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then return obj end
    error('KLB Gang: não foi possível obter CoreObject (qbx-core / qb-core).')
end)()

--------------------------------------------------------------------------------
-- Estado local
--------------------------------------------------------------------------------
local PlayerGang = (QBCore.Functions.GetPlayerData() or {}).gang or {}
local shownGangMenu = false
local nuiOpen = false
local DynamicMenuItems = {}

-- rótulos PT-BR enviados para a NUI (se ela suportar)
local LABELS_PT = {
    economy        = 'Banco',
    employees      = 'Membros',
    stash          = 'Cofre',
    transactions   = 'Transações',
    deposit        = 'Depositar',
    withdraw       = 'Sacar',
    exit           = 'Sair',
    jobPrefix      = 'Facção',
    searchHint     = 'Pesquisar por nome / ID / cargo...',
    playerId       = 'ID do Jogador',
    name           = 'Nome',
    grade          = 'Cargo',
    status         = 'Status',
    actions        = 'Ações',
    online         = 'Online',
    offline        = 'Offline',
    promote        = 'Promover',
    fire           = 'Expulsar',
    hireEmployee   = 'Convidar',
    defaultGrade   = 'Cargo Padrão',
    serverIdHint   = 'ID do Servidor (ex.: 42)',
    you            = 'Você',
}

--------------------------------------------------------------------------------
-- Utilitários
--------------------------------------------------------------------------------
local function safeDeepcopy(val)
    if type(deepcopy) == 'function' then
        return deepcopy(val)
    end
    if type(val) ~= 'table' then return val end
    local res = {}
    for k, v in pairs(val) do
        res[k] = (type(v) == 'table') and safeDeepcopy(v) or v
    end
    return res
end

local function CoreDrawText(msg, side)
    if GetResourceState('qb-core') == 'started' and exports['qb-core'] and exports['qb-core'].DrawText then
        exports['qb-core']:DrawText(msg, side or 'left')
    elseif GetResourceState('qbx-core') == 'started' and exports['qbx-core'] and exports['qbx-core'].DrawText then
        exports['qbx-core']:DrawText(msg, side or 'left')
    end
end

local function CoreHideText()
    if GetResourceState('qb-core') == 'started' and exports['qb-core'] and exports['qb-core'].HideText then
        exports['qb-core']:HideText()
    elseif GetResourceState('qbx-core') == 'started' and exports['qbx-core'] and exports['qbx-core'].HideText then
        exports['qbx-core']:HideText()
    end
end

local function setNui(state)
    nuiOpen = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function CloseMenuFullGang()
    SendNUIMessage({ page = 'gang', action = 'close' })
    setNui(false)
    CoreHideText()
    shownGangMenu = false
end

--------------------------------------------------------------------------------
-- Exports dinâmicos (se você usar)
--------------------------------------------------------------------------------
local function AddGangMenuItem(data, id)
    local menuID = id or (#DynamicMenuItems + 1)
    DynamicMenuItems[menuID] = safeDeepcopy(data)
    return menuID
end
exports('AddGangMenuItem', AddGangMenuItem)

local function RemoveGangMenuItem(id)
    DynamicMenuItems[id] = nil
end
exports('RemoveGangMenuItem', RemoveGangMenuItem)

--------------------------------------------------------------------------------
-- Eventos de player
--------------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        Wait(200)
        local pdata = QBCore.Functions.GetPlayerData() or {}
        PlayerGang = pdata.gang or {}
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local pdata = QBCore.Functions.GetPlayerData() or {}
    PlayerGang = pdata.gang or {}
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(InfoGang)
    PlayerGang = InfoGang or {}
end)

-- aceitar tanto o evento com typo quanto o correto
RegisterNetEvent('qb-gangmenu:client:Warbobe', function()
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end)
RegisterNetEvent('qb-gangmenu:client:Wardrobe', function()
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end)

--------------------------------------------------------------------------------
-- Abrir NUI
--------------------------------------------------------------------------------
local function collectGrades(gangName)
    local out = {}
    if QBCore.Shared and QBCore.Shared.Gangs and QBCore.Shared.Gangs[gangName] and QBCore.Shared.Gangs[gangName].grades then
        for k, v in pairs(QBCore.Shared.Gangs[gangName].grades) do
            out[#out+1] = { level = tonumber(k) or 0, name = v.name }
        end
        table.sort(out, function(a,b) return a.level < b.level end)
    end
    return out
end

RegisterNetEvent('qb-gangmenu:client:OpenMenu', function()
    if not PlayerGang or not PlayerGang.name or not PlayerGang.isboss then return end

    local gangName  = PlayerGang.name
    local gangLabel = PlayerGang.label or gangName
    local grades    = collectGrades(gangName)

    shownGangMenu = true
    setNui(true)
    SendNUIMessage({
        page   = 'gang',
        action = 'open',
        gang   = { name = gangName, label = gangLabel },
        grades = grades,
        labels = LABELS_PT
    })

    -- Pré-carrega lista de membros
    QBCore.Functions.TriggerCallback('qb-gangmenu:server:GetEmployeesNUI', function(list)
        SendNUIMessage({ page = 'gang', action = 'members', members = list or {} })
    end, gangName)
end)

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------
RegisterNUICallback('gang:sync', function(_, cb)
    local gangName  = (PlayerGang and PlayerGang.name) or 'none'
    local gangLabel = (PlayerGang and PlayerGang.label) or 'Facção'
    local grades    = collectGrades(gangName)

    QBCore.Functions.TriggerCallback('qb-gangmenu:server:GetDashboard', function(result)
        result = result or {}
        result.gang   = result.gang   or { name = gangName, label = gangLabel }
        result.grades = result.grades or grades
        result.labels = LABELS_PT
        cb(result)
    end, gangName)
end)

-- opcional (se sua NUI listar jogadores próximos)
RegisterNUICallback('gang:getplayers', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-gangmenu:getplayers', function(players)
        cb(players or {})
    end)
end)

RegisterNUICallback('gang:setrank', function(data, cb)
    local cid   = data and data.cid
    local grade = data and data.grade
    if cid ~= nil and grade ~= nil then
        local gangName = (PlayerGang and PlayerGang.name) or 'none'
        local grades   = (QBCore.Shared.Gangs[gangName] and QBCore.Shared.Gangs[gangName].grades) or {}
        local gname    = (grades[tostring(grade)] and grades[tostring(grade)].name) or tostring(grade)
        TriggerServerEvent('qb-gangmenu:server:GradeUpdate', { cid = cid, grade = tonumber(grade) or 0, gradename = gname })
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('gang:fire', function(data, cb)
    local cid = data and data.cid
    if cid then
        TriggerServerEvent('qb-gangmenu:server:FireMember', cid)
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('gang:invite', function(data, cb)
    local id    = data and data.id
    local grade = tonumber(data and data.grade) or 0
    if id then
        TriggerServerEvent('qb-gangmenu:server:HireMember', tonumber(id), grade)
        cb({ ok = true })
        return
    end
    cb({ ok = false, error = 'invalid_args' })
end)

RegisterNUICallback('gang:transfer', function(data, cb)
    local payload = {
        type   = (data and data.type) or 'deposit',
        amount = tonumber(data and data.amount or 0) or 0,
        gang   = (PlayerGang and PlayerGang.name) or 'none',
        note   = (data and data.note) or '',
        target = (data and data.target) or ''
    }
    QBCore.Functions.TriggerCallback('qb-gangmenu:server:Transfer', function(res)
        cb(res or { ok = false, error = 'failed' })
    end, payload)
end)

RegisterNUICallback('gang:stash', function(_, cb)
    TriggerServerEvent('qb-gangmenu:server:stash')
    cb({ ok = true })
end)

RegisterNUICallback('gang:notify', function(data, cb)
    local message = data and data.message
    if message and message ~= '' then
        local nType  = (data and data.type) or 'primary'
        local length = tonumber(data and (data.length or data.duration))
        QBCore.Functions.Notify(message, nType, length)
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('gang:close', function(_, cb)
    CloseMenuFullGang()
    cb({ ok = true })
end)

RegisterNetEvent('klb-management:client:closeGangMenu', function()
    CloseMenuFullGang()
end)

--------------------------------------------------------------------------------
-- Loop / Target
--------------------------------------------------------------------------------
CreateThread(function()
    if Config.UseTarget then
        for gang, zones in pairs(Config.GangMenus or {}) do
            for index, coords in ipairs(zones) do
                local zoneName = ('%s_gangmenu_%s'):format(gang, index)
                exports['qb-target']:AddCircleZone(zoneName, coords, 0.5, {
                    name = zoneName,
                    debugPoly = false,
                    useZ = true
                }, {
                    options = {
                        {
                            type  = 'client',
                            event = 'qb-gangmenu:client:OpenMenu',
                            icon  = 'fas fa-people-group',
                            label = (Lang and Lang.t and Lang:t('targetgang.label')) or 'Abrir Painel da Gangue',
                            canInteract = function()
                                return gang == (PlayerGang.name or '') and PlayerGang.isboss == true
                            end,
                        },
                    },
                    distance = 2.5
                })
            end
        end
        return
    end

    -- modo "E para abrir"
    while true do
        local wait = 2500
        local ped  = PlayerPedId()
        local pos  = GetEntityCoords(ped)
        local inRangeGang, nearGangmenu = false, false

        if PlayerGang and PlayerGang.name then
            for k, menus in pairs(Config.GangMenus or {}) do
                for _, coords in ipairs(menus) do
                    if k == PlayerGang.name and PlayerGang.isboss then
                        local dist = #(pos - coords)
                        if dist < 5.0 then
                            wait = 0
                            inRangeGang = true
                            if dist <= 1.5 then
                                nearGangmenu = true
                                if not shownGangMenu then
                                    CoreDrawText((Lang and Lang.t and Lang:t('drawtextgang.label')) or '[E] Abrir Painel da Gangue', 'left')
                                    shownGangMenu = true
                                end
                                if IsControlJustReleased(0, 38) then
                                    CoreHideText()
                                    TriggerEvent('qb-gangmenu:client:OpenMenu')
                                end
                            end
                        end
                    end
                end
            end

            if not inRangeGang then
                Wait(1500)
                if shownGangMenu then
                    CloseMenuFullGang()
                    shownGangMenu = false
                end
            elseif shownGangMenu and not nearGangmenu then
                CloseMenuFullGang()
                shownGangMenu = false
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Segurança de foco ao parar
--------------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if nuiOpen then setNui(false) end
    CoreHideText()
end)
