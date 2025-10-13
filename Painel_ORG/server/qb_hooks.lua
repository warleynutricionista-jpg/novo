-- server/qb_hooks.lua
local function safeAddUserToOrg(src)
    if not Organizations or not Config or not QBCore then return end
    local uid = getUserId(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not uid or not P then return end

    -- mapeia job -> groupType (nome da organização)
    local job = P.PlayerData.job and P.PlayerData.job.name
    if job and Config.Groups and Config.Groups[job] then
        local cargo = (P.PlayerData.job.grade and (P.PlayerData.job.grade.name or P.PlayerData.job.grade)) or job
        if Organizations.AddUserGroup then
            Organizations:AddUserGroup(uid, { group = tostring(cargo), groupType = job })
        end
    end

    -- opcional: gang como outra organização
    local gang = P.PlayerData.gang and P.PlayerData.gang.name
    if gang and Config.Groups and Config.Groups[gang] then
        local cargo = (P.PlayerData.gang.grade and (P.PlayerData.gang.grade.name or P.PlayerData.gang.grade)) or gang
        if Organizations.AddUserGroup then
            Organizations:AddUserGroup(uid, { group = tostring(cargo), groupType = gang })
        end
    end
end

-- atualizar quando jogador entra / troca de job/gang
AddEventHandler('QBCore:Server:OnPlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then safeAddUserToOrg(src) end
end)

RegisterNetEvent('QBCore:Server:OnJobUpdate', function(src, job)
    if type(src) ~= 'number' then
        -- algumas bases disparam (Player, job), outras (src, job)
        local Player = src
        src = Player and Player.PlayerData and Player.PlayerData.source
    end
    if src then safeAddUserToOrg(src) end
end)

-- fallback: ao iniciar o recurso, varre online
CreateThread(function()
    Wait(1000)
    if not QBCore then return end
    for _,src in ipairs(QBCore.Functions.GetPlayers()) do
        safeAddUserToOrg(src)
    end
end)
