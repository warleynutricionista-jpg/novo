-- client/modules/chest.lua
-- Obtém os registros (logs) do baú da organização via callback do servidor.

-- NUI -> Client
RegisterNUICallback('GetRegisters', function(_, cb)
    -- Chama o servidor e aguarda os logs
    local ok, logs = pcall(function()
        return lib.callback.await('Painel_ORG:chest:getLogs', false)
    end)

    if not ok or type(logs) ~= 'table' then
        logs = {}
    end

    -- Retorna para a NUI no formato esperado
    cb(logs)
end)
