--============================================================
-- space_economy - client/nui.lua
-- Ponte Client <-> NUI (fetch callbacks do HTML)
-- Protocolo ÚNICO: SendNUIMessage({ action="open", mode, payload })
--============================================================

SE = SE or {}
SE.Client = SE.Client or {}

local uiOpen = false
local uiAck = false

-- usado quando abrimos modo "payment" (opcional)
local lastPayment = { tax = 0, reason = 'Imposto' }

local function setFocus(state)
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(false)
end

local function openUI(mode, payload)
  uiOpen = true
  uiAck = false

  payload = payload or {}

  -- guarda pagamento (se vier)
  if mode == 'payment' then
    lastPayment.tax = tonumber(payload.tax or 0) or 0
    lastPayment.reason = tostring(payload.reason or 'Imposto')
  end

  setFocus(true)

  -- Protocolo único (compat com html/script.js novo)
  SendNUIMessage({
    action = 'open',
    mode = tostring(mode or ''),
    payload = payload
  })

  -- watchdog: se a NUI não responder, fecha
  CreateThread(function()
    Wait(2500)
    if uiOpen and not uiAck then
      uiOpen = false
      setFocus(false)
      SendNUIMessage({ action = 'close' })
    end
  end)
end

local function closeUI()
  if not uiOpen then return end
  uiOpen = false
  setFocus(false)
  SendNUIMessage({ action = 'close' })
end

--============================================================
-- Eventos vindos do server
--============================================================
RegisterNetEvent('space_economy:client_open', function(mode, payload)
  openUI(mode, payload or {})
end)

RegisterNetEvent('space_economy:client_notify', function(msg, typ)
  if lib and lib.notify then
    lib.notify({
      title = 'Economia',
      description = msg or '...',
      type = typ or 'inform'
    })
  else
    -- fallback simples
    print(('[space_economy] %s'):format(msg or '...'))
  end
end)

-- server -> NUI (roteador único)
RegisterNetEvent('space_economy:client_adminData', function(key, data)
  SendNUIMessage({
    action = 'adminData',
    key = key,
    data = data
  })
end)

--============================================================
-- NUI callbacks (fetch -> client)
--============================================================

-- handshake / ACK (script.js chama post("ready"))
RegisterNUICallback('ready', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

-- compat extra (se você usar ACK por token em algum momento)
RegisterNUICallback('nui_ack', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

-- fechar forçado (script.js chama post("forceClose"))
RegisterNUICallback('forceClose', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

-- fechar normal
RegisterNUICallback('close', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

-- admin router (script.js chama post("admin_requestData"))
RegisterNUICallback('admin_requestData', function(data, cb)
  local dataType = data and data.dataType
  local payload = data and data.payload
  TriggerServerEvent('space_economy:server_requestAdminData', dataType, payload)
  cb({ ok = true })
end)

-- pagamento UI (script.js chama post("payTax"))
RegisterNUICallback('payTax', function(data, cb)
  local tax = tonumber((data and data.tax) or lastPayment.tax or 0) or 0
  local reason = tostring((data and data.reason) or lastPayment.reason or 'Imposto')
  TriggerServerEvent('space_economy:server_payTax', tax, reason)
  cb({ ok = true })
end)

RegisterNUICallback('refuseTax', function(data, cb)
  TriggerServerEvent('space_economy:server_refuseTax', data and data.tax, data and data.reason)
  cb({ ok = true })
end)

-- calculadora (script.js chama post("calculateTax"))
RegisterNUICallback('calculateTax', function(data, cb)
  TriggerServerEvent('space_economy:server_calculateTax', data and data.amount)
  cb({ ok = true })
end)

-- lavagem (script.js chama post("washMoney"))
RegisterNUICallback('washMoney', function(data, cb)
  TriggerServerEvent('space_economy:server_washMoney',
    data and data.businessId,
    data and data.amount,
    data and (data.fee_percent or data.feePercent)
  )
  cb({ ok = true })
end)
