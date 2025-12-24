-- ps-dispatch/client/eventhandlers.lua
-- versão revisada p/ qbx_core + ox_lib
-- melhorias:
--  - evita erro quando PlayerData ou PlayerData.job é nil
--  - evita chamadas com vehicle nil
--  - timers mais seguros
--  - validações de witnesses, armas, etc.

local timers = {}

--- Aguarda cooldown por tipo de alerta antes de disparar novamente
---@param name string nome do alerta (ex: 'Shooting')
---@param action function função a executar se permitido
---@vararg any args extra pra função
local function WaitTimer(name, action, ...)
    -- segurança caso config esteja incompleto
    if not Config or not Config.DefaultAlerts or not Config.DefaultAlerts[name] then
        return
    end

    if timers[name] then
        return
    end

    timers[name] = true

    -- roda a ação agora
    action(...)

    -- cooldown em thread separada pra não travar handler
    CreateThread(function()
        local delay = (Config.DefaultAlertsDelay or 5) * 1000
        Wait(delay)
        timers[name] = false
    end)
end

--- Verifica se um ped está na lista de testemunhas
---@param witnesses table|nil lista de peds
---@param ped number ped a checar
---@return boolean
local function isPedAWitness(witnesses, ped)
    if not witnesses or not ped then
        return false
    end
    for _, v in pairs(witnesses) do
        if v == ped then
            return true
        end
    end
    return false
end

--- Verifica se o ped está usando uma arma liberada (whitelist)
---@param ped number
---@return boolean isWhitelisted
local function IsWeaponWhitelisted(ped)
    if not Config or not Config.WeaponWhitelist then
        return false
    end

    local currentWeapon = GetSelectedPedWeapon(ped)
    for i = 1, #Config.WeaponWhitelist do
        local weaponHash = joaat(Config.WeaponWhitelist[i])
        if currentWeapon == weaponHash then
            return true
        end
    end
    return false
end

--- Helper pra pegar o tipo do emprego do player com segurança
---@return string|nil jobType ("leo","ems",etc) ou nil
local function GetPlayerJobType()
    -- PlayerData costuma vir do framework (qbx_core / qbcore)
    if not PlayerData or not PlayerData.job then
        return nil
    end
    return PlayerData.job.type
end

--- Helper pra saber se o ped atual é o nosso player
---@param ped number
---@return boolean
local function IsLocalPed(ped)
    return ped ~= nil and cache and cache.ped and ped == cache.ped
end

--- Helper pra pegar o veículo atual do jogador com segurança
---@return number|nil veh entityId ou nil
local function GetLocalVehicle()
    if cache and cache.vehicle and cache.vehicle ~= 0 then
        return cache.vehicle
    end
    return nil
end


-------------------------------------------------
-- DISPARO DE ARMA
-------------------------------------------------
AddEventHandler('CEventGunShot', function(witnesses, ped)
    -- silenciada? não reporta
    if IsPedCurrentWeaponSilenced(cache.ped) then return end

    -- zonas onde não manda dispatch (definida em outro script)
    if inNoDispatchZone then return end

    -- arma liberada? (ex: policial com arma de serviço)
    if IsWeaponWhitelisted(cache.ped) then return end

    WaitTimer('Shooting', function()
        -- só reporta se o ped que atirou for o jogador local
        if not IsLocalPed(ped) then return end

        local jobType = GetPlayerJobType()

        -- policiais não disparam alerta de tiro normal (a não ser em modo debug)
        if jobType == 'leo' and not Config.Debug then
            return
        end

        -- área de caça: manda alerta de caça, não de tiro urbano
        if inHuntingZone then
            exports['ps-dispatch']:Hunting()
            return
        end

        -- precisa ter testemunha válida (NPC viu)
        if witnesses and not isPedAWitness(witnesses, ped) then
            return
        end

        local veh = GetLocalVehicle()
        if veh then
            exports['ps-dispatch']:VehicleShooting()
        else
            exports['ps-dispatch']:Shooting()
        end
    end)
end)


-------------------------------------------------
-- BRIGA / AGRESSÃO FÍSICA
-------------------------------------------------
AddEventHandler('CEventShockingSeenMeleeAction', function(witnesses, ped)
    WaitTimer('Melee', function()
        if not IsLocalPed(ped) then return end
        if witnesses and not isPedAWitness(witnesses, ped) then return end
        if not IsPedInMeleeCombat(ped) then return end

        exports['ps-dispatch']:Fight()
    end)
end)


-------------------------------------------------
-- CARJACK / ROUBO DE VEÍCULO
-------------------------------------------------
AddEventHandler('CEventPedJackingMyVehicle', function(_, ped)
    WaitTimer('Autotheft', function()
        if not IsLocalPed(ped) then return end
        local vehicle = GetVehiclePedIsUsing(ped, true)
        if vehicle and vehicle ~= 0 then
            exports['ps-dispatch']:CarJacking(vehicle)
        end
    end)
end)

AddEventHandler('CEventShockingCarAlarm', function(_, ped)
    WaitTimer('Autotheft', function()
        if not IsLocalPed(ped) then return end
        local vehicle = GetVehiclePedIsUsing(ped, true)
        if vehicle and vehicle ~= 0 then
            exports['ps-dispatch']:VehicleTheft(vehicle)
        end
    end)
end)


-------------------------------------------------
-- EXPLOSÃO
-------------------------------------------------
AddEventHandler('CEventExplosionHeard', function(witnesses, ped)
    -- só dispara se houver testemunha que seja o ped local ou que viu o ped local?
    -- lógica original: se há witnesses e o ped local NÃO tá na lista, sai
    if witnesses and not isPedAWitness(witnesses, ped) then return end

    WaitTimer('Explosion', function()
        exports['ps-dispatch']:Explosion()
    end)
end)


-------------------------------------------------
-- PLAYER ABATIDO / DOWNED
-------------------------------------------------
AddEventHandler('gameEventTriggered', function(eventName, args)
    -- este evento é usado pelo GTA pra dano em entidades de rede
    if eventName ~= 'CEventNetworkEntityDamage' then return end

    -- args[1] = vítima
    -- args[6] = está morto (1) ou não
    local victim = args[1]
    local isDead = (args[6] == 1)

    WaitTimer('PlayerDowned', function()
        if not victim or not IsLocalPed(victim) then return end
        if not isDead then return end

        local jobType = GetPlayerJobType()

        if jobType == 'leo' then
            exports['ps-dispatch']:OfficerDown()
        elseif jobType == 'ems' then
            exports['ps-dispatch']:EmsDown()
        else
            exports['ps-dispatch']:InjuriedPerson()
        end
    end)
end)


-------------------------------------------------
-- EXCESSO DE VELOCIDADE / DIREÇÃO PERIGOSA
-------------------------------------------------

local SpeedingEvents = {
    'CEventShockingCarChase',
    'CEventShockingDrivingOnPavement',
    'CEventShockingBicycleOnPavement',
    'CEventShockingMadDriverBicycle',
    'CEventShockingMadDriverExtreme',
    'CEventShockingEngineRevved',
    'CEventShockingInDangerousVehicle'
}

local lastSpeedDispatch = 0

for i = 1, #SpeedingEvents do
    local evName = SpeedingEvents[i]

    AddEventHandler(evName, function(_, ped)
        WaitTimer('Speeding', function()
            -- limita spam: só manda um alerta a cada 10s
            local now = GetGameTimer()
            if (now - lastSpeedDispatch) < 10000 then
                return
            end

            if not IsLocalPed(ped) then return end

            local jobType = GetPlayerJobType()
            -- policiais não geram alerta de velocidade por padrão
            if jobType == 'leo' and not Config.Debug then
                return
            end

            local veh = GetLocalVehicle()
            if not veh then return end

            -- velocidade em km/h
            local speed = GetEntitySpeed(veh) * 3.6
            -- limite aleatório 80-100 km/h
            if speed < (80 + math.random(0, 20)) then
                return
            end

            -- só motorista gera alerta
            if ped ~= GetPedInVehicleSeat(veh, -1) then
                return
            end

            exports['ps-dispatch']:SpeedingVehicle()
            lastSpeedDispatch = now
        end)
    end)
end
