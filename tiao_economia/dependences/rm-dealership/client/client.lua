local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}

-- Initialize Locale table
Locale = Locale or {}

-- Translation function
local function GetTranslation(key, ...)
    if not Locale[Config.Language] then return key end
    if not Locale[Config.Language][key] then return key end
    return string.format(Locale[Config.Language][key], ...)
end
local isInDealership = false
local currentPreviewVehicle = nil
local dealershipBlips = {}
local isInPreview = false
local originalBucket = nil
local previewCam = nil

-- Initialize
CreateThread(function()
    Wait(1000)
    PlayerData = QBCore.Functions.GetPlayerData()
    
    -- Clean up any orphaned preview vehicles from previous sessions
    CleanupOrphanedPreviewVehicles()
    
    CreateDealershipBlips()
    SetupDealershipZones()
    SpawnShowroomVehicles()
end)

-- Clean up orphaned preview vehicles
function CleanupOrphanedPreviewVehicles()
    CleanupAllPreviewVehicles()
    
    -- Reset all preview state
    isInPreview = false
    currentPreviewVehicle = nil
    originalBucket = nil
    previewLock = false
end

-- Player loaded event
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

-- Job update event
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

-- NUI Callback Handlers
RegisterNUICallback('closeDealership', function(data, cb)
    isInDealership = false
    SetNuiFocus(false, false)
    
    -- Hide any text UI that might be showing
    if GetResourceState('ox_lib') == 'started' then
        lib.hideTextUI()
    end
    
    cb('ok')
end)

-- Emergency close with ESC key (client-side backup)
CreateThread(function()
    while true do
        Wait(0)
        if isInDealership then
            if IsControlJustPressed(0, 322) then -- ESC key
                isInDealership = false
                SetNuiFocus(false, false)
                
                -- Hide any text UI that might be showing
                if GetResourceState('ox_lib') == 'started' then
                    lib.hideTextUI()
                end
                
                SendNUIMessage({
                    action = 'closeDealership'
                })
            end
        else
            Wait(500)
        end
    end
end)

RegisterNUICallback('previewVehicle', function(data, cb)
    if data.model then
        PreviewVehicle(data.model)
    end
    cb('ok')
end)

RegisterNUICallback('testDriveVehicle', function(data, cb)
    if data.model then
        StartTestDrive(data.model)
    end
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(data, cb)
    if data.model then
        QBCore.Functions.TriggerCallback('rm-dealership:server:buyVehicle', function(success, message)
            if success then
                lib.notify({
                    title = GetTranslation('success'),
                    description = message or GetTranslation('purchase_success'),
                    type = 'success',
                    duration = 5000
                })
                -- Refresh dealership data
                isInDealership = false
                SetNuiFocus(false, false)
                Wait(500)
            else
                lib.notify({
                    title = GetTranslation('error'),
                    description = message or GetTranslation('purchase_failed'),
                    type = 'error',
                    duration = 5000
                })
            end
            cb('ok')
        end, data)
    else
        cb('error')
    end
end)

-- Create blips for dealerships
function CreateDealershipBlips()
    for i = 1, #Config.DealershipLocations do
        local dealership = Config.DealershipLocations[i]
        local blip = AddBlipForCoord(dealership.coords.x, dealership.coords.y, dealership.coords.z)
        
        SetBlipSprite(blip, dealership.blip.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, dealership.blip.scale)
        SetBlipAsShortRange(blip, true)
        SetBlipColour(blip, dealership.blip.color)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(dealership.blip.label)
        EndTextCommandSetBlipName(blip)
        
        dealershipBlips[#dealershipBlips + 1] = blip
    end
end

-- Setup interaction zones
function SetupDealershipZones()
    if Config.UseTarget and GetResourceState('ox_target') == 'started' then
        for i = 1, #Config.DealershipLocations do
            local dealership = Config.DealershipLocations[i]
            exports.ox_target:addSphereZone({
                coords = dealership.coords,
                radius = 2.0,
                options = {
                    {
                        name = 'dealership_browse',
                        icon = 'fas fa-car',
                        label = GetTranslation('dealership'),
                        onSelect = function()
                            OpenDealership()
                        end
                    }
                }
            })
        end
    elseif Config.UseSleeplessInteract and GetResourceState('sleepless_interact') == 'started' then
        for i, dealership in pairs(Config.DealershipLocations) do
            -- Add interaction point using sleepless_interact
            exports.sleepless_interact:addCoords(dealership.coords, {
                {
                    name = 'dealership_' .. i,
                    label = GetTranslation('dealership'),
                    icon = 'fas fa-car',
                    distance = 4.5,
                    onSelect = function()
                        OpenDealership()
                    end,
                    canInteract = function()
                        return not isInDealership and not isInPreview and not isInTestDrive
                    end
                }
            })
        end
    else
        -- Use 3D text and key press
        CreateThread(function()
            while true do
                local sleep = 1000
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                
                for i = 1, #Config.DealershipLocations do
                    local dealership = Config.DealershipLocations[i]
                    local distance = #(coords - dealership.coords)
                    
                    if distance < Config.DrawDistance then
                        sleep = 0
                        if distance < Config.MarkerDistance then
                            -- Draw marker
                            DrawMarker(25, dealership.coords.x, dealership.coords.y, dealership.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 1.0, 255, 255, 255, 100, false, true, 2, nil, nil, false)
                            
                            if distance < 2.0 then
                                lib.showTextUI('[E] - ' .. GetTranslation('dealership'), {
                                    position = "left-center",
                                    icon = 'car',
                                    style = {
                                        borderRadius = 10,
                                        backgroundColor = '#00000080',
                                        color = 'white'
                                    }
                                })
                                
                                if IsControlJustPressed(0, 38) then -- E key
                                    lib.hideTextUI()
                                    OpenDealership()
                                end
                            else
                                lib.hideTextUI()
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end

-- Spawn showroom vehicles
function SpawnShowroomVehicles()
    for i = 1, #Config.ShowroomVehicles do
        local vehicle = Config.ShowroomVehicles[i]
        local model = GetHashKey(vehicle.model)
        
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(100)
        end
        
        local veh = CreateVehicle(model, vehicle.coords.x, vehicle.coords.y, vehicle.coords.z, vehicle.coords.w, false, false)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleDoorsLocked(veh, 2)
        SetVehicleEngineOn(veh, false, true, true)
        FreezeEntityPosition(veh, true)
        SetVehicleNumberPlateText(veh, 'PREVIEW')
    end
end

-- Function to open dealership interface
function OpenDealership()
    if isInDealership then return end
    
    isInDealership = true
    
    -- Get all dealership data with single callback
    QBCore.Functions.TriggerCallback('rm-dealership:server:getVehicleData', function(vehicles, playerMoney, vipInfo)
        local vehicleData = vehicles or {}
        local money = playerMoney or 0
        local vipData = vipInfo or { hasVip = false, vipType = nil, vipDiscount = 0 }
        
        -- Get player's owned vehicles
        QBCore.Functions.TriggerCallback('rm-dealership:server:getPlayerVehicles', function(ownedVehicles)
        
        -- Admin functionality disabled
        local isAdmin = false
        
        -- Get language and translations
        local language = Config.Language or 'pt-br'
        local translations = Locale[language] or {}
        
        -- Set NUI focus
        SetNuiFocus(true, true)
        
            -- Send data to HTML interface with language support
            SendNUIMessage({
                action = 'openDealership',
                vehicles = vehicleData,
                playerMoney = money,
                vipInfo = vipData,
                isAdmin = isAdmin,
                ownedVehicles = ownedVehicles or {},
                language = language,
                translations = translations
            })
        
            -- Show notification with translation
            lib.notify({
                title = GetTranslation('dealership'),
                description = GetTranslation('welcome_message'),
                type = 'success',
                duration = 3000
            })
        end)
    end)
end

-- Global preview lock to prevent multiple instances
local previewLock = false

-- Simplified preview vehicle system
function PreviewVehicle(vehicleModel)
    -- Check if preview is locked or already active
    if previewLock or isInPreview then
        return
    end
    
    -- Lock preview system
    previewLock = true
    
    -- Validate input
    if not vehicleModel or vehicleModel == "" then
        previewLock = false
        return
    end
    
    -- Clean up any existing preview vehicles first
    CleanupAllPreviewVehicles()
    Wait(500)
    
    -- Close interface immediately
    isInDealership = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeDealership'
    })
    
    local ped = PlayerPedId()
    local model = GetHashKey(vehicleModel)
    
    -- Request model
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(model) then
        lib.notify({
            title = 'Erro',
            description = 'Modelo não encontrado: ' .. vehicleModel,
            type = 'error'
        })
        previewLock = false
        return
    end
    
    -- Set preview state
    isInPreview = true
    
    -- Get bucket and setup preview
    QBCore.Functions.TriggerCallback('rm-dealership:server:getPlayerBucket', function(bucket)
        originalBucket = bucket
        
        -- Move to preview bucket
        local previewBucket = math.random(1000, 9999)
        TriggerServerEvent('rm-dealership:server:setPlayerBucket', previewBucket)
        Wait(300)
        
        -- Teleport to preview location
        if Config.PreviewLocation then
            SetEntityCoords(ped, Config.PreviewLocation.x, Config.PreviewLocation.y, Config.PreviewLocation.z, false, false, false, true)
            SetEntityHeading(ped, Config.PreviewLocation.w or 0.0)
            Wait(500)
        end
        
        -- Spawn vehicle
        if Config.PreviewVehicleSpawn then
            local veh = CreateVehicle(model, Config.PreviewVehicleSpawn.x, Config.PreviewVehicleSpawn.y, Config.PreviewVehicleSpawn.z, Config.PreviewVehicleSpawn.w or 0.0, true, true)
            
            if veh and DoesEntityExist(veh) then
                currentPreviewVehicle = veh
                
                -- Setup vehicle
                SetEntityAsMissionEntity(veh, true, true)
                SetVehicleOnGroundProperly(veh)
                SetVehicleEngineOn(veh, true, true, true)
                SetVehicleNumberPlateText(veh, 'PREVIEW')
                SetVehicleFuelLevel(veh, 100.0)
                
                -- Put player in vehicle and make invisible
                Wait(200)
                TaskWarpPedIntoVehicle(ped, veh, -1)
                Wait(500)
                SetEntityAlpha(ped, 0)
                
                -- Notification
                lib.notify({
                    title = 'Preview Ativo',
                    description = 'BACKSPACE/DELETE/ENTER para sair',
                    type = 'success'
                })
                
                -- Start simple control loop
                CreateThread(SimplePreviewControl)
                
            else
                EndPreviewMode()
            end
        else
            EndPreviewMode()
        end
        
        SetModelAsNoLongerNeeded(model)
        previewLock = false
    end)
end

-- Simple preview control loop
function SimplePreviewControl()
    while isInPreview do
        Wait(0)
        
        local ped = PlayerPedId()
        
        -- Ensure player is invisible
        SetEntityAlpha(ped, 0)
        
        -- Ensure player is in vehicle
        if currentPreviewVehicle and DoesEntityExist(currentPreviewVehicle) then
            if GetVehiclePedIsIn(ped, false) ~= currentPreviewVehicle then
                TaskWarpPedIntoVehicle(ped, currentPreviewVehicle, -1)
            end
        else
            -- Vehicle was deleted, end preview
            EndPreviewMode()
            break
        end
        
        -- Draw instructions
        DrawSimplePreviewInstructions()
        
        -- Control restrictions
        DisableControlAction(0, 75, true) -- Exit vehicle
        DisableControlAction(0, 23, true) -- Enter vehicle
        DisableControlAction(0, 322, true) -- ESC key
        
        -- Allow vehicle controls
        EnableControlAction(0, 71, true) -- Accelerate
        EnableControlAction(0, 72, true) -- Brake
        EnableControlAction(0, 59, true) -- Steer left
        EnableControlAction(0, 60, true) -- Steer right
        EnableControlAction(0, 1, true) -- Look left/right
        EnableControlAction(0, 2, true) -- Look up/down
        
        -- Check exit keys
        if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 178) or IsControlJustPressed(0, 18) then
            EndPreviewMode()
            break
        end
    end
end

-- Simple preview instructions
function DrawSimplePreviewInstructions()
    -- Background
    DrawRect(0.5, 0.92, 0.25, 0.06, 0, 0, 0, 150)
    
    -- Title
    SetTextFont(1)
    SetTextScale(0.0, 0.4)
    SetTextColour(255, 255, 255, 255)
    SetTextCentre(1)
    SetTextEntry("STRING")
    AddTextComponentString("PREVIEW MODE")
    DrawText(0.5, 0.90)
    
    -- Instructions
    SetTextFont(0)
    SetTextScale(0.0, 0.3)
    SetTextColour(200, 200, 200, 255)
    SetTextCentre(1)
    SetTextEntry("STRING")
    AddTextComponentString("BACKSPACE/DELETE/ENTER to exit")
    DrawText(0.5, 0.93)
end



-- Clean up all preview vehicles
function CleanupAllPreviewVehicles()
    local vehicles = GetGamePool('CVehicle')
    local cleaned = 0
    
    for i = 1, #vehicles do
        local veh = vehicles[i]
        if DoesEntityExist(veh) then
            local plate = GetVehicleNumberPlateText(veh)
            if plate and string.find(plate, "PREVIEW") then
                DeleteEntity(veh)
                cleaned = cleaned + 1
            end
        end
    end
    
    currentPreviewVehicle = nil
end

-- End preview mode
function EndPreviewMode()
    if not isInPreview then 
        return 
    end
    
    isInPreview = false
    
    local ped = PlayerPedId()
    
    -- Restore player
    SetEntityAlpha(ped, 255)
    ClearPedTasks(ped)
    
    -- Clean up vehicle
    if currentPreviewVehicle and DoesEntityExist(currentPreviewVehicle) then
        DeleteEntity(currentPreviewVehicle)
    end
    currentPreviewVehicle = nil
    
    -- Return to original bucket
    if originalBucket then
        TriggerServerEvent('rm-dealership:server:setPlayerBucket', originalBucket)
        originalBucket = nil
        Wait(500)
    end
    
    -- Teleport back
    if Config.DealershipLocations and Config.DealershipLocations[1] then
        local loc = Config.DealershipLocations[1].coords
        SetEntityCoords(ped, loc.x, loc.y, loc.z, false, false, false, true)
        SetEntityHeading(ped, Config.DealershipLocations[1].heading or 0.0)
    end
    
    -- Reset dealership state
    isInDealership = false
    
    lib.notify({
        title = 'Preview Finalizado',
        description = 'Interaja novamente para abrir a concessionária',
        type = 'success'
    })
end

-- Test Drive System
local isInTestDrive = false
local testDriveVehicle = nil
local testDriveTimer = nil
local testDriveBlip = nil
local originalBucketForTestDrive = nil

function StartTestDrive(vehicleModel)
    if isInTestDrive then
        lib.notify({
            title = 'Test Drive Ativo',
            description = 'Você já está fazendo um test drive',
            type = 'error'
        })
        return
    end
    
    local ped = PlayerPedId()
    isInTestDrive = true
    
    -- Store original bucket and get a unique test drive bucket
    QBCore.Functions.TriggerCallback('rm-dealership:server:getPlayerBucket', function(bucket)
        originalBucketForTestDrive = bucket
        
        -- Create unique test drive bucket
        local testDriveBucket = math.random(2000, 9999)
        
        -- Move player to test drive bucket
        TriggerServerEvent('rm-dealership:server:setPlayerBucket', testDriveBucket)
        
        Wait(100)
        
        -- Teleport player to test drive location
        local testDriveLocation = Config.TestDrive.Location
        SetEntityCoords(ped, testDriveLocation.x, testDriveLocation.y, testDriveLocation.z)
        SetEntityHeading(ped, testDriveLocation.w)
        
        Wait(500)
        
        -- Spawn test drive vehicle
        local model = GetHashKey(vehicleModel)
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(100)
        end
        
        -- Generate unique plate for test drive
        local testPlate = 'TEST' .. math.random(100, 999)
        
        testDriveVehicle = CreateVehicle(model, testDriveLocation.x, testDriveLocation.y, testDriveLocation.z, testDriveLocation.w, true, true)
        SetEntityAsMissionEntity(testDriveVehicle, true, true)
        SetVehicleNumberPlateText(testDriveVehicle, testPlate)
        
        -- Wait for vehicle to be properly created
        Wait(100)
        
        -- Set vehicle properties
        SetVehicleOnGroundProperly(testDriveVehicle)
        SetVehicleEngineOn(testDriveVehicle, true, true, false)
        SetVehicleDoorsLocked(testDriveVehicle, 1) -- Unlocked
        SetVehicleFuelLevel(testDriveVehicle, 100.0)
        SetVehicleBodyHealth(testDriveVehicle, 1000.0)
        SetVehicleEngineHealth(testDriveVehicle, 1000.0)
        
        -- Close dealership interface during test drive
        isInDealership = false
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = 'closeDealership'
        })
        
        -- Put player in driver seat
        TaskWarpPedIntoVehicle(ped, testDriveVehicle, -1)
        
        -- Wait for player to be in vehicle
        Wait(500)
        
        -- Give keys through server (safer method)
        TriggerServerEvent('rm-dealership:server:giveTestDriveKeys', testPlate, testDriveVehicle)
        
        -- Create test drive blip
        testDriveBlip = AddBlipForCoord(testDriveLocation.x, testDriveLocation.y, testDriveLocation.z)
        SetBlipSprite(testDriveBlip, Config.TestDrive.Blip.sprite)
        SetBlipDisplay(testDriveBlip, 4)
        SetBlipScale(testDriveBlip, Config.TestDrive.Blip.scale)
        SetBlipColour(testDriveBlip, Config.TestDrive.Blip.color)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.TestDrive.Blip.label)
        EndTextCommandSetBlipName(testDriveBlip)
        
        -- Start test drive timer
        testDriveTimer = Config.TestDrive.Duration
        
        lib.notify({
            title = 'Test Drive Iniciado!',
            description = 'Você tem ' .. Config.TestDrive.Duration .. ' segundos para testar este veículo. Pressione ESPAÇO para retornar.',
            type = 'success',
            duration = 5000
        })
        
        -- Start test drive countdown with on-screen timer
        CreateThread(function()
            while isInTestDrive and testDriveTimer and testDriveTimer > 0 do
                Wait(1000)
                
                -- Safety check before decrementing
                if not testDriveTimer or testDriveTimer <= 0 then
                    break
                end
                
                testDriveTimer = testDriveTimer - 1
                
                -- Show countdown notifications
                if testDriveTimer == 30 then
                    lib.notify({
                        title = 'Test Drive',
                        description = '30 segundos restantes',
                        type = 'warning',
                        duration = 3000
                    })
                elseif testDriveTimer == 10 then
                    lib.notify({
                        title = 'Test Drive',
                        description = '10 segundos restantes',
                        type = 'warning',
                        duration = 3000
                    })
                end
            end
            
            -- Only end test drive if it's still active and timer reached 0
            if isInTestDrive and testDriveTimer ~= nil and testDriveTimer <= 0 then
                EndTestDrive()
            end
        end)
        
        -- Display professional test drive UI
        CreateThread(function()
            while isInTestDrive do
                Wait(0)
                
                -- Safety check to prevent nil errors
                local currentTimer = testDriveTimer
                if not currentTimer or currentTimer <= 0 then
                    break
                end
                
                local minutes = math.floor(currentTimer / 60)
                local seconds = currentTimer % 60
                local timeString = string.format("%02d:%02d", minutes, seconds)
                
                -- Calculate progress percentage (inverted for countdown)
                local progress = currentTimer / Config.TestDrive.Duration
                local progressBarWidth = 0.11 -- Fit within container
                local progressWidth = progressBarWidth * progress
                
                -- Main container settings
                local containerX, containerY = 0.02, 0.02  -- Top left corner
                local containerW, containerH = 0.13, 0.09
                
                -- Draw main background with modern glass effect
                DrawRect(containerX + containerW/2, containerY + containerH/2, containerW, containerH, 15, 15, 20, 200)
                
                -- Draw subtle border with gradient
                DrawRect(containerX + containerW/2, containerY + 0.001, containerW, 0.002, 99, 102, 241, 255) -- Blue top
                DrawRect(containerX + containerW/2, containerY + containerH - 0.001, containerW, 0.002, 99, 102, 241, 255) -- Blue bottom
                DrawRect(containerX + 0.001, containerY + containerH/2, 0.002, containerH, 99, 102, 241, 255) -- Blue left
                DrawRect(containerX + containerW - 0.001, containerY + containerH/2, 0.002, containerH, 99, 102, 241, 255) -- Blue right
                
                -- Header section
                SetTextFont(1)
                SetTextProportional(1)
                SetTextScale(0.0, 0.32)
                SetTextColour(99, 102, 241, 255) -- Blue accent
                SetTextDropShadow(0, 0, 0, 0, 255)
                SetTextEdge(1, 0, 0, 0, 255)
                SetTextEntry("STRING")
                AddTextComponentString("TEST DRIVE")
                DrawText(containerX + 0.01, containerY + 0.01)
                
                -- Time display with better positioning
                SetTextFont(1)
                SetTextProportional(1)
                SetTextScale(0.0, 0.45)
                
                -- Dynamic color for urgency
                if currentTimer <= 10 then
                    SetTextColour(239, 68, 68, 255) -- Red
                elseif currentTimer <= 30 then
                    SetTextColour(245, 158, 11, 255) -- Amber
                else
                    SetTextColour(255, 255, 255, 255) -- White
                end
                
                SetTextDropShadow(0, 0, 0, 0, 255)
                SetTextEdge(1, 0, 0, 0, 255)
                SetTextEntry("STRING")
                AddTextComponentString(timeString)
                DrawText(containerX + 0.01, containerY + 0.03)
                
                -- Progress bar background (contained within box)
                local progressY = containerY + 0.055
                local progressX = containerX + 0.01
                DrawRect(progressX + progressBarWidth/2, progressY, progressBarWidth, 0.006, 40, 40, 45, 255)
                
                -- Progress bar fill with smooth color transition
                local r, g, b = 34, 197, 94 -- Green
                if currentTimer <= 30 then
                    r, g, b = 245, 158, 11 -- Amber
                end
                if currentTimer <= 10 then
                    r, g, b = 239, 68, 68 -- Red
                end
                
                if progressWidth > 0 then
                    DrawRect(progressX + progressWidth/2, progressY, progressWidth, 0.006, r, g, b, 255)
                end
                
                -- Instruction text (better visibility)
                SetTextFont(1)
                SetTextProportional(1)
                SetTextScale(0.0, 0.28)
                SetTextColour(220, 220, 220, 255) -- Brighter gray
                SetTextDropShadow(0, 0, 0, 0, 255)
                SetTextEdge(2, 0, 0, 0, 255) -- Stronger edge
                SetTextEntry("STRING")
                AddTextComponentString("ESPAÇO para retornar")
                DrawText(containerX + 0.01, containerY + 0.07)
            end
        end)
        
        -- Handle SPACE key to end test drive early
        CreateThread(function()
            while isInTestDrive do
                Wait(0)
                if IsControlJustPressed(0, Config.TestDrive.ReturnKey) then -- SPACE key
                    EndTestDrive()
                    break
                end
            end
        end)
        
        -- Block player from exiting vehicle during test drive
        CreateThread(function()
            while isInTestDrive do
                Wait(0)
                
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                
                -- If player is in the test drive vehicle, disable exit controls
                if vehicle == testDriveVehicle then
                    DisableControlAction(0, 75, true) -- Disable exit vehicle (F key)
                    DisableControlAction(0, 23, true) -- Disable enter/exit vehicle (F key alternative)
                    
                    -- Also disable some other controls that might allow exiting
                    DisableControlAction(0, 32, true) -- Disable W (forward) when trying to exit
                    DisableControlAction(0, 33, true) -- Disable S (backward) when trying to exit
                    DisableControlAction(0, 34, true) -- Disable A (left) when trying to exit
                    DisableControlAction(0, 35, true) -- Disable D (right) when trying to exit
                    
                    -- Re-enable the movement controls for driving
                    EnableControlAction(0, 32, true) -- Re-enable W for driving
                    EnableControlAction(0, 33, true) -- Re-enable S for driving
                    EnableControlAction(0, 34, true) -- Re-enable A for driving
                    EnableControlAction(0, 35, true) -- Re-enable D for driving
                    
                    -- Keep other vehicle controls enabled
                    EnableControlAction(0, 71, true) -- Accelerate
                    EnableControlAction(0, 72, true) -- Brake/Reverse
                    EnableControlAction(0, 59, true) -- Steering left
                    EnableControlAction(0, 60, true) -- Steering right
                    EnableControlAction(0, 85, true) -- Radio wheel
                    EnableControlAction(0, 86, true) -- Horn
                    EnableControlAction(0, 1, true)  -- Mouse look left/right
                    EnableControlAction(0, 2, true)  -- Mouse look up/down
                end
                
                -- If player somehow gets out of the vehicle, put them back in
                if testDriveVehicle and DoesEntityExist(testDriveVehicle) and vehicle ~= testDriveVehicle then
                    TaskWarpPedIntoVehicle(ped, testDriveVehicle, -1)
                    lib.notify({
                        title = 'Test Drive',
                        description = 'Você deve permanecer no veículo durante o test drive!',
                        type = 'warning',
                        duration = 3000
                    })
                end
            end
        end)
        
        -- Ensure vehicle stays accessible during test drive
        CreateThread(function()
            while isInTestDrive and testDriveVehicle do
                Wait(3000) -- Check every 3 seconds
                if DoesEntityExist(testDriveVehicle) then
                    -- Keep engine on and doors unlocked
                    SetVehicleEngineOn(testDriveVehicle, true, true, false)
                    SetVehicleDoorsLocked(testDriveVehicle, 1)
                    -- Ensure player can still access the vehicle
                    SetVehicleHasBeenOwnedByPlayer(testDriveVehicle, true)
                    -- Prevent fuel depletion
                    SetVehicleFuelLevel(testDriveVehicle, 100.0)
                    -- Keep vehicle in good condition
                    SetVehicleBodyHealth(testDriveVehicle, 1000.0)
                    SetVehicleEngineHealth(testDriveVehicle, 1000.0)
                end
            end
        end)
        
        SetModelAsNoLongerNeeded(model)
    end)
end

function EndTestDrive()
    if not isInTestDrive then return end
    
    isInTestDrive = false
    testDriveTimer = nil
    local ped = PlayerPedId()
    local vehicleToDelete = testDriveVehicle
    local plateToRemove = nil
    
    -- Get plate before deleting vehicle
    if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
        plateToRemove = GetVehicleNumberPlateText(vehicleToDelete)
        if plateToRemove then
            plateToRemove = string.gsub(plateToRemove, "^%s*(.-)%s*$", "%1") -- Trim whitespace
        end
    end
    
    -- Remove blip
    if testDriveBlip then
        RemoveBlip(testDriveBlip)
        testDriveBlip = nil
    end
    
    -- Remove temporary keys BEFORE deleting vehicle
    if plateToRemove then
        -- Try to remove keys through server first
        TriggerServerEvent('rm-dealership:server:removeTestDriveKeys', plateToRemove, testDriveVehicle)
        
        -- Wait a moment for server processing
        Wait(500)
        
        -- Also try multiple client-side removal methods with error handling
        pcall(function()
            if GetResourceState('mri_Qcarkeys') == 'started' then
                
                -- Try multiple removal methods for mri_Qcarkeys
                TriggerEvent('mri_Qcarkeys:client:RemoveKeys', plateToRemove)
                TriggerEvent('vehiclekeys:client:RemoveKeys', plateToRemove)
                -- Try export method if available
                if exports['mri_Qcarkeys'] and exports['mri_Qcarkeys'].RemoveKeys then
                    exports['mri_Qcarkeys']:RemoveKeys(plateToRemove)
                end
            end
            
            if GetResourceState('qb-vehiclekeys') == 'started' then
                TriggerEvent('vehiclekeys:client:RemoveKeys', plateToRemove)
                TriggerEvent('qb-vehiclekeys:client:RemoveKeys', plateToRemove)
            end
            
            if GetResourceState('qbx-vehiclekeys') == 'started' then
                exports['qbx-vehiclekeys']:RemoveKeys(plateToRemove)
            end
            
            -- Additional fallback removal methods
            TriggerEvent('vehiclekeys:client:removeKeys', plateToRemove) -- lowercase variant
            TriggerEvent('keys:remove', plateToRemove) -- generic variant
        end)
        
        -- Force remove from player inventory if it's an item
        pcall(function()
            if exports.ox_inventory then
                exports.ox_inventory:RemoveItem('vehiclekey_' .. plateToRemove, 1)
                exports.ox_inventory:RemoveItem('vehiclekey', 1) -- Generic vehiclekey
            end
        end)
    end
    
    -- Delete test drive vehicle
    if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
        DeleteEntity(vehicleToDelete)
    end
    testDriveVehicle = nil
    
    -- Return player to original bucket
    if originalBucketForTestDrive then
        TriggerServerEvent('rm-dealership:server:setPlayerBucket', originalBucketForTestDrive)
    end
    
    Wait(100)
    
    -- Teleport player back to dealership
    local dealershipLocation = Config.DealershipLocations[1].coords
    SetEntityCoords(ped, dealershipLocation.x, dealershipLocation.y, dealershipLocation.z)
    SetEntityHeading(ped, Config.DealershipLocations[1].heading or 0.0)
    
    -- Reset dealership state but don't auto-open interface (like preview)
    isInDealership = false
    
    lib.notify({
        title = 'Test Drive Encerrado',
        description = 'Você retornou à concessionária. Interaja novamente para abrir a interface.',
        type = 'success',
        duration = 5000
    })
    
    originalBucketForTestDrive = nil
end

-- Buy vehicle
function BuyVehicle(vehicleData)
    QBCore.Functions.TriggerCallback('rm-dealership:server:buyVehicle', function(success, message)
        if success then
            -- Server already sends notification via TriggerClientEvent
            -- Just close the dealership interface
            CloseDealership()
        else
            lib.notify({
                title = 'Compra Falhou',
                description = message,
                type = 'error',
                duration = 5000
            })
        end
    end, vehicleData)
end

-- Close dealership
function CloseDealership()
    isInDealership = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeDealership'
    })
    
    if currentPreviewVehicle then
        DeleteEntity(currentPreviewVehicle)
        currentPreviewVehicle = nil
    end
end

-- Admin menu
function OpenAdminMenu()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local hasAccess = false
    
    for i = 1, #Config.AdminJobs do
        if PlayerData.job.name == Config.AdminJobs[i] then
            hasAccess = true
            break
        end
    end
    
    if not hasAccess then
        lib.notify({
            title = GetTranslation('access_denied'),
            description = GetTranslation('no_permission'),
            type = 'error'
        })
        return
    end
    
    QBCore.Functions.TriggerCallback('rm-dealership:server:getAdminData', function(adminData)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openAdmin',
            vehicles = adminData.vehicles,
            categories = Config.VehicleCategories,
            language = Config.Language,
            translations = Locale[Config.Language]
        })
    end)
end

-- NUI Callbacks
RegisterNUICallback('closeDealership', function(data, cb)
    isInDealership = false
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('previewVehicle', function(data, cb)
    PreviewVehicle(data.model)
    cb('ok')
end)



RegisterNUICallback('testDriveVehicle', function(data, cb)
    StartTestDrive(data.model)
    cb('ok')
end)

-- Fallback event to ensure vehicle access during test drive
RegisterNetEvent('rm-dealership:client:ensureVehicleAccess', function()
    if isInTestDrive and testDriveVehicle then
        SetVehicleEngineOn(testDriveVehicle, true, true, false)
        SetVehicleDoorsLocked(testDriveVehicle, 1)
        SetVehicleHasBeenOwnedByPlayer(testDriveVehicle, true)
        
        lib.notify({
            title = 'Acesso ao Veículo',
            description = 'Chaves do veículo ativadas via método alternativo',
            type = 'success',
            duration = 3000
        })
    end
end)

RegisterNUICallback('getVehicleStats', function(data, cb)
    local model = GetHashKey(data.model)
    RequestModel(model)
    
    -- Add timeout to prevent infinite loop
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 50 do -- Max 5 seconds timeout
        Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(model) then
        -- Return default stats if model fails to load
        cb({
            topSpeed = 0,
            acceleration = 0,
            braking = 0,
            handling = 0
        })
        return
    end
    
    local tempVeh = CreateVehicle(model, 0.0, 0.0, 0.0, 0.0, false, false)
    SetEntityVisible(tempVeh, false)
    SetEntityCollision(tempVeh, false)
    
    local stats = {
        topSpeed = GetVehicleModelMaxSpeed(model),
        acceleration = GetVehicleModelAcceleration(model),
        braking = GetVehicleModelMaxBraking(model),
        handling = GetVehicleModelMaxTraction(model)
    }
    
    DeleteEntity(tempVeh)
    SetModelAsNoLongerNeeded(model)
    cb(stats)
end)

-- Admin NUI Callbacks
RegisterNUICallback('addVehicle', function(data, cb)
            TriggerServerEvent('rm-dealership:server:addVehicle', data)
    cb('ok')
end)

RegisterNUICallback('removeVehicle', function(data, cb)
            TriggerServerEvent('rm-dealership:server:removeVehicle', data.model)
    cb('ok')
end)

RegisterNUICallback('updateVehicle', function(data, cb)
    TriggerServerEvent('rm-dealership:server:updateVehicle', data)
    cb('ok')
end)

-- Spawn purchased vehicle and teleport player
RegisterNetEvent('rm-dealership:client:spawnPurchasedVehicle', function(vehicleData)
    local ped = PlayerPedId()
    local model = GetHashKey(vehicleData.model)
    
    -- Close dealership interface if still open
    if isInDealership then
        CloseDealership()
    end
    
    -- Request vehicle model with timeout
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do -- Max 10 seconds timeout
        Wait(100)
        timeout = timeout + 1
    end
    
    -- Check if model loaded successfully
    if not HasModelLoaded(model) then
        lib.notify({
            title = 'Erro',
            description = 'Falha ao carregar modelo do veículo: ' .. vehicleData.model,
            type = 'error',
            duration = 5000
        })
        return
    end
    
    -- Teleport player to delivery location
    local deliveryLocation = Config.DeliveryLocation
    if deliveryLocation then
        SetEntityCoords(ped, deliveryLocation.x, deliveryLocation.y, deliveryLocation.z)
        SetEntityHeading(ped, deliveryLocation.w)
        
        Wait(500) -- Small delay to ensure player is positioned
        
        -- Spawn vehicle at delivery spawn location
        local deliveryVehicleSpawn = Config.DeliveryVehicleSpawn
        if deliveryVehicleSpawn then
            local vehicle = CreateVehicle(model, deliveryVehicleSpawn.x, deliveryVehicleSpawn.y, deliveryVehicleSpawn.z, deliveryVehicleSpawn.w, true, false)
            
            -- Set vehicle properties
            SetEntityAsMissionEntity(vehicle, true, true)
            SetVehicleNumberPlateText(vehicle, vehicleData.plate)
            SetVehicleEngineOn(vehicle, true, true, false)
            SetVehicleDoorsLocked(vehicle, 1) -- Unlocked
            
            -- Give player keys based on configured system
            if Config.VehicleKeys == 'qb-vehiclekeys' then
                TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
            elseif Config.VehicleKeys == 'qbx-vehiclekeys' then
                -- For QBX, we use the server export to give keys
                TriggerServerEvent('rm-dealership:server:giveVehicleKeys', GetVehicleNumberPlateText(vehicle))
            elseif Config.VehicleKeys == 'mri_Qcarkeys' then
                TriggerServerEvent('mri_Qcarkeys:server:AcquireVehicleKeys', GetVehicleNumberPlateText(vehicle))
            end
            
            -- Put player in driver seat
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
            
            -- Show delivery notification
            lib.notify({
                title = GetTranslation('purchase_success'),
                description = GetTranslation('vehicle_spawned') .. ' - ' .. vehicleData.name,
                type = 'success',
                duration = 8000
            })
        else
            lib.notify({
                title = 'Erro de Configuração',
                description = 'Local de entrega não configurado',
                type = 'error',
                duration = 5000
            })
        end
    else
        lib.notify({
            title = 'Erro de Configuração',
            description = 'Local de entrega não configurado',
            type = 'error',
            duration = 5000
        })
    end
    
    -- Clean up model
    SetModelAsNoLongerNeeded(model)
end)

-- Admin command disabled
-- RegisterCommand('dealershipmenu', function()
--     OpenAdminMenu()
-- end, false)

-- Admin command to clean up preview vehicles
RegisterCommand('cleanuppreview', function()
    if PlayerData and PlayerData.job and (PlayerData.job.name == 'admin' or PlayerData.job.grade.level >= 4) then
        CleanupOrphanedPreviewVehicles()
        lib.notify({
            title = 'Admin',
            description = 'Preview vehicles cleaned up',
            type = 'success',
            duration = 3000
        })
    else
        lib.notify({
            title = 'Erro',
            description = 'Sem permissão',
            type = 'error',
            duration = 3000
        })
    end
end, false)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for i = 1, #dealershipBlips do
            RemoveBlip(dealershipBlips[i])
        end
        
        if currentPreviewVehicle then
            DeleteEntity(currentPreviewVehicle)
        end
        
        -- Cleanup test drive
        if isInTestDrive then
            EndTestDrive()
        end
        
        SetNuiFocus(false, false)
    end
end) 