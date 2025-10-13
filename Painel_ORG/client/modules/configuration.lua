-- client/modules/configuration.lua
-- NUI <-> Client para permissões e configurações da organização

-- Fallback caso o Config.defaultPermissions não esteja disponível no client
local permLabels = {
    invite  = { name = "Convidar",          description = "Permite convidar jogadores para a facção." },
    demote  = { name = "Rebaixar",          description = "Pode rebaixar um cargo inferior." },
    promote = { name = "Promover",          description = "Pode promover cargos." },
    dismiss = { name = "Demitir",           description = "Pode demitir membros." },
    withdraw= { name = "Sacar dinheiro",    description = "Pode sacar do banco da organização." },
    deposit = { name = "Depositar dinheiro",description = "Pode depositar no banco da organização." },
    message = { name = "Escrever anotações",description = "Pode escrever anotações." },
    alerts  = { name = "Escrever Alertas",  description = "Pode enviar alertas para todos." },
    chat    = { name = "Escrever no chat",  description = "Pode usar o chat da facção." },
    leader  = { name = "Líder",             description = "Indica que o cargo é líder." }
}

local function labelFor(perm)
    if Config and Config.defaultPermissions and Config.defaultPermissions[perm] then
        return {
            name = Config.defaultPermissions[perm].name,
            description = Config.defaultPermissions[perm].description
        }
    end
    return permLabels[perm] or { name = perm, description = "" }
end

-- Buscar permissões do cargo selecionado
RegisterNUICallback('GetPermissions', function(data, cb)
    local role = data and data.roleEdit
    if not role or role == "" then
        cb({})
        return
    end

    local ok, payload = pcall(function()
        return lib.callback.await('Painel_ORG:perms:get', false)
    end)

    if (not ok) or type(payload) ~= 'table' then
        ok, payload = pcall(function()
            return lib.callback.await('Painel_ORG:getPermissions', false, role)
        end)
    end

    if not ok or type(payload) ~= 'table' then
        cb({})
        return
    end

    local perms = (payload.map and payload.map[role]) or payload[role] or payload

    local t = {}
    for perm, status in pairs(perms) do
        if perm ~= 'leader' then
            local info = labelFor(perm)
            t[perm] = {
                name = info.name,
                description = info.description,
                status = not not status
            }
        end
    end

    cb(t)
end)

-- Salvar permissões do cargo
RegisterNUICallback('SetPermissions', function(data, cb)
    local role = data and data.role
    local incoming = data and data.permissions
    if not role or type(incoming) ~= 'table' then
        cb(false)
        return
    end

    local toSend = {}
    for perm, v in pairs(incoming) do
        toSend[perm] = (v and v.status) and true or false
    end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:perms:set', false, { role = role, perms = toSend })
    end)

    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:updatePermissions', false, role, toSend)
        end)
    end

    cb(ok and result or false)
end)

-- Atualizar frequência do rádio
RegisterNUICallback('SetRadio', function(data, cb)
    local freq = data and (data.frequency or data.freq or data.radio) or data
    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:config:setRadio', false, tostring(freq or ''))
    end)

    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:updateRadio', false, { frequency = freq })
        end)
    end
    cb(ok and result or false)
end)

-- Atualizar preset (male/female)
RegisterNUICallback('SetPreset', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:config:setPresets', false, data)
    end)

    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:updatePreset', false, data)
        end)
    end
    cb(ok and result or false)
end)

-- Atualizar configurações gerais (discord/logo/etc)
RegisterNUICallback('SetConfig', function(data, cb)
    if not data or not data.discord or not tostring(data.discord):find('https://', 1, true) then
        print('Discord: Insira um URL válido. Exemplo: https://discord.gg/xxxxx')
        cb(false)
        return
    end

    -- Caso queira validar logo futuramente:
    -- if data.logo and not tostring(data.logo):find('https://', 1, true) then
    --     print('Logo: URL inválido. Exemplo: https://site.com/imagem.png')
    --     cb(false)
    --     return
    -- end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:config:set', false, data)
    end)

    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:config:update', false, data)
        end)
    end

    cb(ok and result or false)
end)
