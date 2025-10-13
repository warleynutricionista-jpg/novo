-- client/modules/members.lua
-- NUI <-> Client (Membros da organização)

---------------------------------------------------------------------
-- LISTAR MEMBROS
---------------------------------------------------------------------
RegisterNUICallback("GetMembers", function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:members:get', false)
    end)
    cb(ok and (result or {}) or {})
end)

---------------------------------------------------------------------
-- CONVIDAR (CONTRATAR) MEMBRO
---------------------------------------------------------------------
RegisterNUICallback('ContractMember', function(data, cb)
    local id = data and (data.id or data.playerId)
    if not id then return cb(false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:members:invite', false, tonumber(id))
    end)
    cb(ok and result or false)
end)

---------------------------------------------------------------------
-- REBAIXAR MEMBRO
---------------------------------------------------------------------
RegisterNUICallback('DemoteMember', function(data, cb)
    local id = data and (data.id or data.playerId)
    if not id then return cb(false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, {
            memberId = tonumber(id),
            action = 'demote'
        })
    end)
    cb(ok and (result or false) or false)
end)

---------------------------------------------------------------------
-- PROMOVER MEMBRO
---------------------------------------------------------------------
RegisterNUICallback('PromoteMember', function(data, cb)
    local id = data and (data.id or data.playerId)
    if not id then return cb(false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, {
            memberId = tonumber(id),
            action = 'promote'
        })
    end)
    cb(ok and (result or false) or false)
end)

---------------------------------------------------------------------
-- DEMITIR MEMBRO
---------------------------------------------------------------------
RegisterNUICallback('DimissMember', function(data, cb)
    local id = data and (data.id or data.playerId)
    if not id then return cb(false) end

    local ok, result = pcall(function()
        return lib.callback.await('Painel_ORG:members:action', false, {
            memberId = tonumber(id),
            action = 'dismiss'
        })
    end)
    cb(ok and (result or false) or false)
end)
