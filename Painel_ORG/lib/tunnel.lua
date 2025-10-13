-- lib/tunnel.lua
-- RPC simples Client <-> Server para o Painel_ORG

vTunnel = vTunnel or {}       -- usado no client para chamar funções do server
RegisterTunnel = RegisterTunnel or {} -- onde o server registra os handlers chamados pelo client
ClientTunnel = ClientTunnel or {}     -- (opcional) o client pode registrar funções que o server chama

local RES_NAME = GetCurrentResourceName()

if IsDuplicityVersion() then
    ----------------------------------------------------------------
    -- SERVER
    ----------------------------------------------------------------

    -- Recebe chamada do client e encaminha para RegisterTunnel[method]
    RegisterNetEvent('Painel_ORG:tunnel:call', function(method, args, cbId)
        local src = source
        local fn = RegisterTunnel[method]
        if type(fn) ~= "function" then
            TriggerClientEvent('Painel_ORG:tunnel:cb', src, cbId, nil, ('method_not_found: %s'):format(tostring(method)))
            return
        end

        -- Garante que as funções no seu server vejam "source"
        local prev = _G.source
        _G.source = src
        local ok, ret = pcall(fn, table.unpack(args or {}))
        _G.source = prev

        if not ok then
            TriggerClientEvent('Painel_ORG:tunnel:cb', src, cbId, nil, tostring(ret))
        else
            TriggerClientEvent('Painel_ORG:tunnel:cb', src, cbId, ret, nil)
        end
    end)

    -- Atalho que seu server usa: vTunnel._OpenPainel(source)
    function vTunnel._OpenPainel(targetSrc)
        TriggerClientEvent('Painel_ORG:OpenPanel', targetSrc)
    end

    -- (Opcional) server -> client RPC "nomeado"
    function vTunnel._CallClient(targetSrc, method, ...)
        TriggerClientEvent('Painel_ORG:tunnel:client', targetSrc, method, { ... })
    end

else
    ----------------------------------------------------------------
    -- CLIENT
    ----------------------------------------------------------------

    local pending = {}
    local reqId = 0

    -- Promessa muito simples (sem Citizen promises)
    local function newPromise()
        local P = { done = false, value = nil, err = nil }
        function P:resolve(v) self.done = true; self.value = v end
        function P:reject(e) self.done = true; self.err = e end
        function P:await()
            while not self.done do Wait(0) end
            return self.value, self.err
        end
        return P
    end

    RegisterNetEvent('Painel_ORG:tunnel:cb', function(id, result, err)
        local p = pending[id]
        if not p then return end
        if err then p:reject(err) else p:resolve(result) end
        pending[id] = nil
    end)

    local function callServer(method, ...)
        reqId = reqId + 1
        local p = newPromise()
        pending[reqId] = p
        TriggerServerEvent('Painel_ORG:tunnel:call', method, { ... }, reqId)
        local result, err = p:await()
        if err then
            print(('[%s] Tunnel error calling %s: %s'):format(RES_NAME, tostring(method), tostring(err)))
            return nil
        end
        return result
    end

    -- Faz vTunnel.<qualquerCoisa>(...) chamar o server: RegisterTunnel.<qualquerCoisa>(...)
    setmetatable(vTunnel, {
        __index = function(_, k)
            return function(...)
                return callServer(k, ...)
            end
        end
    })

    -- (Opcional) client registra handlers que o server pode chamar
    RegisterNetEvent('Painel_ORG:tunnel:client', function(method, args)
        local fn = ClientTunnel[method]
        if type(fn) == "function" then
            fn(table.unpack(args or {}))
        end
    end)
end
