--============================================================
-- space_economy - client/init.lua
-- Bootstrap do client + helpers NUI (safe)
--============================================================
SE = SE or {}
SE.Client = SE.Client or {}

local C = SE.Client

C.Resource = GetCurrentResourceName()
C.isOpen = false
C.lastOpenAt = 0

--============================================================
-- Helpers NUI (boas práticas)
--============================================================
function C.SetNuiFocusSafe(state, keepInput)
  state = state == true
  keepInput = keepInput == true

  SetNuiFocus(state, state)
  -- QBOX/QBCore: manter false por padrão (evita “tecla presa”)
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(keepInput)
  end
end

function C.Send(action, payload)
  payload = payload or {}
  payload.action = action
  SendNUIMessage(payload)
end

function C.OpenUI(view, data)
  C.isOpen = true
  C.lastOpenAt = GetGameTimer()
  C.SetNuiFocusSafe(true, false)
  C.Send(view or 'open', data or {})
end

function C.CloseUI()
  C.isOpen = false
  C.SetNuiFocusSafe(false, false)
  C.Send('close', {})
end

--============================================================
-- Key fallback (se necessário) - ESC fecha
--============================================================
CreateThread(function()
  while true do
    Wait(0)
    if C.isOpen and IsControlJustReleased(0, 200) then -- ESC
      C.CloseUI()
      TriggerServerEvent('space_economy:server_forceClose') -- opcional (se existir)
    end
  end
end)
