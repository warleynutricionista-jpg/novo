local config = require 'config.server'
local logger = require 'modules.logger'
local storage = require 'server.storage.main'
local sharedConfig = require 'config.shared'

local starterItems = sharedConfig.starterItems or {}

-- Nome do item que libera slots extras (ex: segundo personagem)
local secondCharacterItemName = (config.characters and config.characters.secondCharacterItem) or 'personagem'

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

---@param source number
---@return string? license2, string? license
local function getPlayerLicenses(source)
    local license2 = GetPlayerIdentifierByType(source, 'license2')
    local license = GetPlayerIdentifierByType(source, 'license')
    return license2, license
end

---@param license2? string
---@param license? string
---@return integer
local function getBaseAllowedCharacters(license2, license)
    local specific = (config.characters and config.characters.playersNumberOfCharacters) or {}
    local defaultAmount = (config.characters and config.characters.defaultNumberOfCharacters) or 1

    if license2 and specific[license2] then
        return specific[license2]
    end

    if license and specific[license] then
        return specific[license]
    end

    return defaultAmount
end

---@param source number
---@return boolean
local function hasSecondCharacterItem(source)
    if not secondCharacterItemName or secondCharacterItemName == '' then
        return false
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        -- Sem ox_inventory: não usa item, fica só 1 slot mesmo
        return false
    end

    local count = exports.ox_inventory:Search(source, 'count', secondCharacterItemName) or 0
    return count > 0
end

---@param source number
---@param license2? string
---@param license? string
---@return integer
local function getMaxCharactersForSource(source, license2, license)
    local base = getBaseAllowedCharacters(license2, license)

    -- Se o jogador NÃO tiver o item, força 1 slot (apenas o personagem inicial)
    if not hasSecondCharacterItem(source) then
        return 1
    end

    -- Se tiver o item, libera o total definido pelo config/licenças
    if base < 1 then base = 1 end
    return base
end

---@param source number
local function giveStarterItems(source)
    if GetResourceState('ox_inventory') == 'missing' then
        return
    end

    -- Garante que o inventário do player esteja pronto
    while not exports.ox_inventory:GetInventory(source) do
        Wait(100)
    end

    for i = 1, #starterItems do
        local item = starterItems[i]
        if not item or not item.name or not item.amount or item.amount <= 0 then
            goto continue
        end

        if item.metadata and type(item.metadata) == 'function' then
            exports.ox_inventory:AddItem(source, item.name, item.amount, item.metadata(source))
        else
            exports.ox_inventory:AddItem(source, item.name, item.amount, item.metadata)
        end

        ::continue::
    end
end

---------------------------------------------------------------------
-- CALLBACKS: GET CHARACTERS / PREVIEW / LOAD / CREATE
---------------------------------------------------------------------

lib.callback.register('qbx_core:server:getCharacters', function(source)
    local license2, license = getPlayerLicenses(source)

    local ok, characters = pcall(function()
        return storage.fetchAllPlayerEntities(license2, license)
    end)

    if not ok then
        lib.print.error(('[qbx_core] Erro ao buscar personagens do jogador %s: %s'):format(source, tostring(characters)))
        characters = {}
    end

    characters = characters or {}

    local maxCharacters = getMaxCharactersForSource(source, license2, license)

    -- Segurança extra: nunca retornar menos slots do que personagens já existentes
    if #characters > maxCharacters then
        maxCharacters = #characters
    end

    return characters, maxCharacters
end)

lib.callback.register('qbx_core:server:getPreviewPedData', function(_, citizenId)
    if not citizenId then return end

    local ok, ped = pcall(function()
        return storage.fetchPlayerSkin(citizenId)
    end)

    if not ok then
        lib.print.error(('[qbx_core] Erro ao buscar skin do cidadão %s: %s'):format(citizenId, tostring(ped)))
        return
    end

    if not ped then return end

    -- ped.skin é JSON, ped.model é string; joaat converte para hash
    return ped.skin, ped.model and joaat(ped.model)
end)

lib.callback.register('qbx_core:server:loadCharacter', function(source, citizenId)
    if not citizenId then
        lib.print.warn(('[qbx_core] loadCharacter chamado sem citizenId (src: %s)'):format(source))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', source)
        return
    end

    local success, err = pcall(function()
        return Login(source, citizenId)
    end)

    if not success or not err then
        lib.print.error(('[qbx_core] Falha em Login para src %s citizenId %s: %s'):format(source, citizenId, tostring(err)))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', source)
        return
    end

    local name = GetPlayerName(source)
    local discord = GetPlayerIdentifierByType(source, 'discord') or 'undefined'
    local ip = GetPlayerIdentifierByType(source, 'ip') or 'undefined'
    local license2, license = getPlayerLicenses(source)
    local rockstar = license2 or license or 'undefined'

    logger.log({
        source = 'qbx_core',
        webhook = config.logging.webhook['joinleave'],
        event = 'Loaded',
        color = 'green',
        message = ('**%s** (%s |  ||%s|| | %s | %s | %s) loaded')
            :format(name, discord, ip, rockstar, citizenId, source)
    })

    lib.print.info(('%s (Citizen ID: %s | ID: %s) has successfully loaded!'):format(name, citizenId, source))
end)

---@param data table
---@return table? newData
lib.callback.register('qbx_core:server:createCharacter', function(source, data)
    if type(data) ~= 'table' then
        lib.print.error(('[qbx_core] createCharacter: dados inválidos do player %s'):format(source))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', source)
        return
    end

    local newData = {
        charinfo = data
    }

    local ok, loginResult = pcall(function()
        return Login(source, nil, newData)
    end)

    if not ok or not loginResult then
        lib.print.error(('[qbx_core] Falha em Login (createCharacter) para src %s: %s'):format(source, tostring(loginResult)))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', source)
        return
    end

    giveStarterItems(source)

    lib.print.info(('%s has created a character'):format(GetPlayerName(source)))
    return newData
end)

---------------------------------------------------------------------
-- DELETE DE PERSONAGEM
---------------------------------------------------------------------

RegisterNetEvent('qbx_core:server:deleteCharacter', function(citizenId)
    local src = source
    if not citizenId then
        lib.print.warn(('[qbx_core] deleteCharacter chamado sem citizenId (src: %s)'):format(src))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', src)
        return
    end

    local ok, err = pcall(function()
        DeleteCharacter(src --[[@as number]], citizenId)
    end)

    if not ok then
        lib.print.error(('[qbx_core] Erro ao deletar personagem %s (src: %s): %s'):format(citizenId, src, tostring(err)))
        TriggerClientEvent('qbx_core:client:forceCharacterMenu', src)
        return
    end

    Notify(src, locale('success.character_deleted'), 'success')

    local name = GetPlayerName(src)
    lib.print.info(('[qbx_core] %s (%s) deletou o personagem %s'):format(name, src, citizenId))

    -- Depois de deletar, manda o client voltar pro menu
    TriggerClientEvent('qbx_core:client:forceCharacterMenu', src)
end)
