local config = require 'config.client'
local defaultSpawn = require 'config.shared'.defaultSpawn

-- Se estiver usando recurso externo de personagens, não carrega este script
if config.characters.useExternalCharacters then return end

-- Inicia sessão de tutorial (usado pelo multichar/câmera)
NetworkStartSoloTutorialSession()

-- Estado local
local previewCam = nil
local randomLocation = config.characters.locations[math.random(1, #config.characters.locations)]
local nationalities = {}

-- Lista de peds aleatórios para a tela de seleção
local randomPeds = {
    {
        model = `mp_m_freemode_01`,
        headOverlays = {
            beard = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            complexion = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            bodyBlemishes = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            blush = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            lipstick = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            blemishes = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            eyebrows = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            makeUp = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            sunDamage = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            moleAndFreckles = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            chestHair = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            ageing = { color = 0, style = 0, secondColor = 0, opacity = 1 },
        },
        components = {
            { texture = 0, drawable = 0, component_id = 0 },
            { texture = 0, drawable = 0, component_id = 1 },
            { texture = 0, drawable = 0, component_id = 2 },
            { texture = 0, drawable = 0, component_id = 5 },
            { texture = 0, drawable = 0, component_id = 7 },
            { texture = 0, drawable = 0, component_id = 9 },
            { texture = 0, drawable = 0, component_id = 10 },
            { texture = 0, drawable = 15, component_id = 11 },
            { texture = 0, drawable = 15, component_id = 8 },
            { texture = 0, drawable = 15, component_id = 3 },
            { texture = 0, drawable = 34, component_id = 6 },
            { texture = 0, drawable = 61, component_id = 4 },
        },
        props = {
            { prop_id = 0, drawable = -1, texture = -1 },
            { prop_id = 1, drawable = -1, texture = -1 },
            { prop_id = 2, drawable = -1, texture = -1 },
            { prop_id = 6, drawable = -1, texture = -1 },
            { prop_id = 7, drawable = -1, texture = -1 },
        }
    },
    {
        model = `mp_f_freemode_01`,
        headBlend = {
            shapeMix = 0.3,
            skinFirst = 0,
            shapeFirst = 31,
            skinSecond = 0,
            shapeSecond = 0,
            skinMix = 0,
            thirdMix = 0,
            shapeThird = 0,
            skinThird = 0,
        },
        hair = {
            color = 0,
            style = 15,
            texture = 0,
            highlight = 0
        },
        headOverlays = {
            chestHair = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            bodyBlemishes = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            beard = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            lipstick = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            complexion = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            blemishes = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            moleAndFreckles = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            makeUp = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            ageing = { secondColor = 0, opacity = 1, color = 0, style = 0 },
            eyebrows = { secondColor = 0, opacity = 1, color = 0, style = 0 },
            blush = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            sunDamage = { secondColor = 0, opacity = 0, color = 0, style = 0 },
        },
        components = {
            { drawable = 0, component_id = 0, texture = 0 },
            { drawable = 0, component_id = 1, texture = 0 },
            { drawable = 0, component_id = 2, texture = 0 },
            { drawable = 0, component_id = 5, texture = 0 },
            { drawable = 0, component_id = 7, texture = 0 },
            { drawable = 0, component_id = 9, texture = 0 },
            { drawable = 0, component_id = 10, texture = 0 },
            { drawable = 15, component_id = 3, texture = 0 },
            { drawable = 15, component_id = 11, texture = 3 },
            { drawable = 14, component_id = 8, texture = 0 },
            { drawable = 15, component_id = 4, texture = 3 },
            { drawable = 35, component_id = 6, texture = 0 },
        },
        props = {
            { prop_id = 0, drawable = -1, texture = -1 },
            { prop_id = 1, drawable = -1, texture = -1 },
            { prop_id = 2, drawable = -1, texture = -1 },
            { prop_id = 6, drawable = -1, texture = -1 },
            { prop_id = 7, drawable = -1, texture = -1 },
        }
    }
}

-- Carrega lista de nacionalidades (se estiver habilitado no config)
if config.characters.limitNationalities then
    local nationalityList = lib.load('data.nationalities')

    CreateThread(function()
        for i = 1, #nationalityList do
            nationalities[#nationalities + 1] = { value = nationalityList[i] }
        end
    end)
end

local ScenarioType = { 'WORLD_HUMAN_COP_IDLES' }

---------------------------------------------------------------------
-- NOTIFY SEGURO
---------------------------------------------------------------------

local function safeNotify(msg, nType, duration)
    if not msg then return end

    if Notify then
        Notify(msg, nType or 'inform', duration or 8000)
        return
    end

    if lib and lib.notify then
        lib.notify({
            description = msg,
            type = nType or 'inform',
            duration = duration or 8000
        })
        return
    end

    print(('[qbx_core] Notify: %s'):format(msg))
end

local function fmtMoney(value)
    if not value then return '0' end
    if lib and lib.math and lib.math.groupdigits then
        return lib.math.groupdigits(value)
    end
    return tostring(value)
end

---------------------------------------------------------------------
-- CÂMERA E PREVIEW
---------------------------------------------------------------------

local function destroyPreviewCam()
    if not previewCam then return end

    SetTimecycleModifier('default')
    SetCamActive(previewCam, false)
    DestroyCam(previewCam, true)
    previewCam = nil

    ClearPedTasks(PlayerPedId())
    RenderScriptCams(false, false, 1, true, true)
    FreezeEntityPosition(cache.ped, false)
end

local function setupPreviewCam()
    SetTimecycleModifierStrength(1.0)
    FreezeEntityPosition(cache.ped, false)
    ClearPedTasks(PlayerPedId())

    if IsEntityVisible(cache.ped) then
        TaskStartScenarioInPlace(cache.ped, ScenarioType[math.random(1, #ScenarioType)], 0, true)
    end

    local coords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.6, 0.0)

    previewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 1250, 1, 0)

    SetCamCoord(previewCam, coords.x, coords.y, coords.z + 0.65)
    SetCamFov(previewCam, 38.0)
    SetCamRot(previewCam, 0.0, 0.0, GetEntityHeading(cache.ped) + 180.0)

    PointCamAtPedBone(previewCam, cache.ped, 31086, -0.4, 0.0, 0.03, true)

    local camCoords = GetCamCoord(previewCam)
    TaskLookAtCoord(cache.ped, camCoords.x, camCoords.y, camCoords.z, 5000, 1, 1)

    SetCamUseShallowDofMode(previewCam, true)
    SetCamNearDof(previewCam, 1.2)
    SetCamFarDof(previewCam, 12.0)
    SetCamDofStrength(previewCam, 1.0)
    SetCamDofMaxNearInFocusDistance(previewCam, 1.0)

    Wait(500)
    DoScreenFadeIn(1000)

    CreateThread(function()
        while DoesCamExist(previewCam) do
            SetUseHiDof()
            Wait(0)
        end
    end)
end

local function randomPed()
    local pedData = randomPeds[math.random(1, #randomPeds)]
    lib.requestModel(pedData.model, config.loadingModelsTimeout)

    SetPlayerModel(cache.playerId, pedData.model)

    pcall(function()
        exports['illenium-appearance']:setPedAppearance(PlayerPedId(), pedData)
    end)

    SetModelAsNoLongerNeeded(pedData.model)
    SetEntityVisible(PlayerPedId(), false, 0)

    destroyPreviewCam()
    Wait(100)
    setupPreviewCam()
end

---@param citizenId? string
local function previewPed(citizenId)
    DoScreenFadeOut(500)
    Wait(500)

    if not citizenId then
        randomPed()
        return
    end

    local clothing, model = lib.callback.await('qbx_core:server:getPreviewPedData', false, citizenId)
    if model and clothing then
        lib.requestModel(model, config.loadingModelsTimeout)
        SetPlayerModel(cache.playerId, model)
        SetEntityVisible(PlayerPedId(), true)

        pcall(function()
            exports['illenium-appearance']:setPedAppearance(PlayerPedId(), json.decode(clothing))
        end)

        SetModelAsNoLongerNeeded(model)
    else
        randomPed()
        return
    end

    destroyPreviewCam()
    Wait(100)
    setupPreviewCam()
end

---------------------------------------------------------------------
-- FORMULÁRIO DE CRIAÇÃO
---------------------------------------------------------------------

---@return CharacterRegistration?
local function characterDialog()
    local nationalityOption = config.characters.limitNationalities and {
        type = 'select',
        required = true,
        icon = 'user-shield',
        label = locale('info.nationality'),
        default = 'Brasileiro',
        searchable = true,
        options = nationalities
    } or {
        type = 'input',
        required = true,
        icon = 'user-shield',
        label = locale('info.nationality'),
        placeholder = 'Brasileiro'
    }

    return lib.inputDialog(locale('info.character_registration_title'), {
        {
            type = 'input',
            required = true,
            icon = 'user-pen',
            label = locale('info.first_name'),
            placeholder = 'Murai'
        },
        {
            type = 'input',
            required = true,
            icon = 'user-pen',
            label = locale('info.last_name'),
            placeholder = 'Dev'
        },
        nationalityOption,
        {
            type = 'select',
            required = true,
            icon = 'circle-user',
            label = locale('info.gender'),
            placeholder = locale('info.select_gender'),
            options = {
                { value = locale('info.char_male') },
                { value = locale('info.char_female') }
            }
        },
        {
            type = 'date',
            required = true,
            icon = 'calendar-days',
            label = locale('info.birth_date'),
            format = config.characters.dateFormat,
            returnString = true,
            default = config.characters.dateMax
        }
    })
end

---@param dialog string[]
---@param input integer
---@return boolean
local function checkStrings(dialog, input)
    local str = dialog[input]
    if not str or str == '' then return false end

    if config.characters.profanityWords[str:lower()] then return false end

    local split = { string.strsplit(' ', str) }
    if #split > 5 then return false end

    for i = 1, #split do
        local word = split[i]
        if config.characters.profanityWords[word:lower()] then
            return false
        end
    end

    return true
end

---@param str string
---@return string
local function capString(str)
    return str:gsub("(%w)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

---------------------------------------------------------------------
-- SPAWNS
---------------------------------------------------------------------

local function spawnDefault()
    DoScreenFadeOut(500)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    destroyPreviewCam()

    pcall(function()
        exports.spawnmanager:spawnPlayer({
            x = defaultSpawn.x,
            y = defaultSpawn.y,
            z = defaultSpawn.z,
            heading = defaultSpawn.w
        })
    end)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)

    while not IsScreenFadedIn() do
        Wait(0)
    end

    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end

local function spawnLastLocation()
    DoScreenFadeOut(500)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    destroyPreviewCam()

    pcall(function()
        exports.spawnmanager:spawnPlayer({
            x = QBX.PlayerData.position.x,
            y = QBX.PlayerData.position.y,
            z = QBX.PlayerData.position.z,
            heading = QBX.PlayerData.position.w
        })
    end)

    local insideMeta = QBX.PlayerData.metadata.inside or {}
    if GetResourceState('ps-housing') == 'started' and insideMeta.propertyId then
        TriggerServerEvent('ps-housing:server:enterProperty', tostring(insideMeta.propertyId))
    end

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)

    while not IsScreenFadedIn() do
        Wait(0)
    end
end

---------------------------------------------------------------------
-- CRIAÇÃO DE PERSONAGEM
---------------------------------------------------------------------

---@param cid integer
---@return boolean
local function createCharacter(cid)
    previewPed()

    ::noMatch::

    local dialog = characterDialog()
    if not dialog then
        return false
    end

    for input = 1, 3 do
        if not checkStrings(dialog, input) then
            safeNotify(locale('error.no_match_character_registration'), 'error', 10000)
            goto noMatch
        end
    end

    DoScreenFadeOut(150)

    local ok, result = pcall(function()
        return lib.callback.await('qbx_core:server:createCharacter', false, {
            firstname = capString(dialog[1]),
            lastname = capString(dialog[2]),
            nationality = capString(dialog[3]),
            gender = dialog[4] == locale('info.char_male') and 0 or 1,
            birthdate = dialog[5],
            cid = cid
        })
    end)

    if not ok then
        print('[qbx_core] Erro em createCharacter callback: ' .. tostring(result))
        safeNotify('Erro ao criar o personagem. Avise a staff.', 'error', 8000)
        destroyPreviewCam()
        DoScreenFadeIn(250)
        return false
    end

    local newData = result
    if not newData then
        safeNotify('Não foi possível criar o personagem. Tente novamente ou contate a staff.', 'error', 8000)
        destroyPreviewCam()
        DoScreenFadeIn(250)
        return false
    end

    if GetResourceState('qbx_spawn') == 'missing' then
        spawnDefault()
    else
        if config.characters.startingApartment then
            TriggerEvent('apartments:client:setupSpawnUI', newData)
        else
            TriggerEvent('qbx_core:client:spawnNoApartments')
        end
    end

    destroyPreviewCam()
    return true
end

---------------------------------------------------------------------
-- MENU MULTICHAR
---------------------------------------------------------------------

local function chooseCharacter()
    local characters, amount

    local ok, c, a = pcall(function()
        return lib.callback.await('qbx_core:server:getCharacters', false)
    end)

    if not ok then
        print('[qbx_core] Erro ao obter personagens: ' .. tostring(c))
        safeNotify('Erro ao carregar personagens. Tente novamente.', 'error', 8000)
        characters, amount = {}, 1
    else
        characters, amount = c, a
    end

    characters = characters or {}
    amount = amount or 1

    -- Nunca tenha menos slots que personagens existentes
    if #characters > amount then
        amount = #characters
    end

    local firstCharacterCitizenId = characters[1] and characters[1].citizenid or nil

    previewPed(firstCharacterCitizenId)

    randomLocation = config.characters.locations[math.random(1, #config.characters.locations)]

    DoScreenFadeOut(500)

    while not IsScreenFadedOut() and cache.ped ~= PlayerPedId() do
        Wait(0)
    end

    FreezeEntityPosition(cache.ped, true)
    Wait(1000)

    RequestCollisionAtCoord(randomLocation.pedCoords.x, randomLocation.pedCoords.y, randomLocation.pedCoords.z)
    while not HasCollisionLoadedAroundEntity(cache.ped) do
        Wait(0)
    end

    SetEntityCoords(cache.ped, randomLocation.pedCoords.x, randomLocation.pedCoords.y, randomLocation.pedCoords.z, false, false, false, false)
    SetEntityHeading(cache.ped, randomLocation.pedCoords.w)

    NetworkStartSoloTutorialSession()

    while not NetworkIsInTutorialSession() do
        Wait(0)
    end

    Wait(1500)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    setupPreviewCam()

    local options = {}

    for i = 1, amount do
        local character = characters[i]
        local title
        local metadata
        local icon = 'user'

        if character then
            local charinfo = character.charinfo or {}
            local money = character.money or {}
            local job = character.job or {}
            local gang = character.gang or {}
            local gangGrade = gang.grade or {}

            local name = ('%s %s'):format(charinfo.firstname or 'N/A', charinfo.lastname or '')

            title = ('%s %s - %s'):format(
                charinfo.firstname or 'N/A',
                charinfo.lastname or '',
                character.citizenid or 'N/A'
            )

            metadata = {
                ['Nome'] = name,
                ['Gênero'] = charinfo.gender == 0 and locale('info.char_male') or locale('info.char_female'),
                ['Data de Nascimento'] = charinfo.birthdate or 'N/A',
                ['Nacionalidade'] = charinfo.nationality or 'N/A',
                ['Número da conta'] = charinfo.account or 'N/A',
                ['Banco'] = fmtMoney(money.bank),
                ['Carteira'] = fmtMoney(money.cash),
                ['Emprego'] = job.label or 'Nenhum',
                ['Nível de emprego'] = (type(job.grade) ~= "table" and job.grade) or (job.grade and job.grade.name) or 'N/A',
                ['Gangue'] = gang.label or 'Nenhuma',
                ['Patente'] = gangGrade.name or 'N/A',
                ['Telefone'] = charinfo.phone or 'N/A'
            }

            options[#options + 1] = {
                title = title,
                metadata = metadata,
                icon = icon,
                iconAnimation = config.characters.iconAnimation,
                onSelect = function()
                    lib.showContext('qbx_core_multichar_character_' .. i)
                    previewPed(character.citizenid)
                end
            }

            -- Menu interno de cada personagem
            lib.registerContext({
                id = 'qbx_core_multichar_character_' .. i,
                title = ('%s %s'):format(charinfo.firstname or 'N/A', charinfo.lastname or ''),
                description = ('%s'):format(character.citizenid or 'N/A'),
                background = true,
                canClose = false,
                menu = 'qbx_core_multichar_characters',
                options = {
                    {
                        title = locale('info.play'),
                        description = locale('info.play_description', name),
                        icon = 'play',
                        iconAnimation = config.characters.iconAnimation,
                        onSelect = function()
                            if not GetResourceState('mri_Qspawn'):find('start') then
                                DoScreenFadeOut(10)
                            end

                            lib.callback.await('qbx_core:server:loadCharacter', false, character.citizenid)

                            if GetResourceState('mri_Qspawn'):find('start') then
                                exports['mri_Qspawn']:chooseSpawn()
                            elseif GetResourceState('qbx_apartments'):find('start') and config.characters.startingApartment then
                                TriggerEvent('apartments:client:setupSpawnUI', character.citizenid)
                            elseif GetResourceState('qbx_spawn'):find('start') then
                                TriggerEvent('qb-spawn:client:setupSpawns', character.citizenid)
                                TriggerEvent('qb-spawn:client:openUI', true)
                            else
                                spawnLastLocation()
                            end

                            destroyPreviewCam()
                        end
                    },
                    config.characters.enableDeleteButton and {
                        title = locale('info.delete_character'),
                        description = locale('info.delete_character_description', name),
                        icon = 'trash',
                        onSelect = function()
                            local alert = lib.alertDialog({
                                header = locale('info.delete_character'),
                                content = locale('info.confirm_delete'),
                                centered = true,
                                cancel = true
                            })

                            if alert == 'confirm' then
                                TriggerServerEvent('qbx_core:server:deleteCharacter', character.citizenid)
                            else
                                lib.showContext('qbx_core_multichar_character_' .. i)
                            end
                        end
                    } or nil
                }
            })
        else
            -- Slot vazio: só aparece se o servidor mandou amount > #characters
            title = locale('info.multichar_new_character', i)
            icon = 'plus'

            options[#options + 1] = {
                title = title,
                icon = icon,
                iconAnimation = config.characters.iconAnimation,
                onSelect = function()
                    local success = createCharacter(i)
                    if not success then
                        lib.showContext('qbx_core_multichar_characters')
                    end
                end
            }
        end
    end

    -- Monta o título do menu com ou sem logo, sem quebrar se imageURL estiver nil
    local menuTitle = locale('info.multichar_title')
    if config.characters.imageURL and config.characters.imageURL ~= '' then
        menuTitle = ('![logo](%s) %s'):format(config.characters.imageURL, menuTitle)
    end

    lib.registerContext({
        id = 'qbx_core_multichar_characters',
        title = menuTitle,
        background = true,
        description = 'Seleção de Personagem',
        canClose = false,
        options = options
    })

    SetTimecycleModifier('default')
    lib.showContext('qbx_core_multichar_characters')
end

---------------------------------------------------------------------
-- EVENTOS / THREADS
---------------------------------------------------------------------

RegisterNetEvent('qbx_core:client:spawnNoApartments', function()
    DoScreenFadeOut(500)
    Wait(2000)

    SetEntityCoords(cache.ped, defaultSpawn.x, defaultSpawn.y, defaultSpawn.z, false, false, false, false)
    SetEntityHeading(cache.ped, defaultSpawn.w)

    Wait(500)
    destroyPreviewCam()
    SetEntityVisible(cache.ped, true, false)

    Wait(500)
    DoScreenFadeIn(250)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)
    TriggerEvent('qb-weathersync:client:EnableSync')
    TriggerEvent('qb-clothes:client:CreateFirstCharacter')
end)

-- Forçar volta ao menu (usado pelo server quando dá erro)
RegisterNetEvent('qbx_core:client:forceCharacterMenu', function()
    destroyPreviewCam()
    chooseCharacter()
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if GetInvokingResource() then return end
    chooseCharacter()
end)

CreateThread(function()
    -- Espera o início da sessão e abre seleção de personagem
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            pcall(function()
                exports.spawnmanager:setAutoSpawn(false)
            end)
            Wait(250)
            chooseCharacter()
            break
        end
    end

    -- Deixa o player invencível enquanto estiver na sessão de tutorial/seleção
    while NetworkIsInTutorialSession() do
        SetEntityInvincible(PlayerPedId(), true)
        Wait(250)
    end

    SetEntityInvincible(PlayerPedId(), false)
end)
