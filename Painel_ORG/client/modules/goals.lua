-- client/modules/goals.lua
-- NUI <-> Client para metas diárias das organizações

-- Farms do dia (se o servidor não implementar, retorna tabela vazia)
RegisterNUICallback('GetFarms', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:goals:getFarms', false)
    end)
    cb(ok and (result or {}) or {})
end)

-- Metas do jogador/org
RegisterNUICallback('GetGoals', function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:goals:get', false)
    end)
    if not ok then
        ok, result = pcall(function()
            return lib.callback.await('Painel_ORG:goals:getGoals', false)
        end)
    end
    cb(ok and (result or {}) or {})
end)

-- Resgatar recompensa da meta diária
RegisterNUICallback('RedeemPrize', function(data, cb)
    local ok, reward = pcall(function()
        return lib.callback.await('Painel_ORG:goals:redeem', false)
    end)
    if not ok then
        ok, reward = pcall(function()
            return lib.callback.await('Painel_ORG:goals:reward', false)
        end)
    end

    if ok and reward then
        if type(DeletarObjeto) == "function" then
            DeletarObjeto()
        end
        SendNUIMessage({ action = 'close' })
        SetNuiFocus(false, false)
    end

    cb(ok and reward or false)
end)

-- Salvar/editar configuração da meta (lider)
RegisterNUICallback('EditMyGoal', function(data, cb)
    -- fecha a NUI primeiro (mantém UX original)
    if type(DeletarObjeto) == "function" then
        DeletarObjeto()
    end
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)

    local ok, saved = pcall(function()
        return lib.callback.await('Painel_ORG:goals:save', false, data)
    end)
    if not ok then
        ok, saved = pcall(function()
            return lib.callback.await('Painel_ORG:goals:edit', false, data)
        end)
    end

    cb(ok and saved or false)
end)

-- Caso futuramente precise expor a lista de configuração:
-- RegisterNuiCallback('GetGoalsConfig', function(data, cb)
--     local ok, result = pcall(function()
--         return lib.callback.await('Painel_ORG:goals:getList', false)
--     end)
--     cb(ok and (result or {}) or {})
-- end)
