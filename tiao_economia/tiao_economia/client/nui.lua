--============================================================
-- space_economy - client/nui.lua
-- Ponte Client <-> NUI (versão com sanitização e uso do helper de focus)
--============================================================
SE = SE or {}
SE.Client = SE.Client or {}
local C = SE.Client

local uiOpen = false
local uiAck = false
local lastPayment = { tax = 0, reason = 'Imposto' }

local function setFocus(state)
  if C and type(C.SetNuiFocusSafe) == 'function' then
    C.SetNuiFocusSafe(state, false)
    return
  end
  -- fallback
  SetNuiFocus(state, state)
  if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
end

local function openUI(mode, payload)
  uiOpen = true
  uiAck = false
  payload = payload or {}

  if mode == 'payment' then
    lastPayment.tax = tonumber(payload.tax or lastPayment.tax) or 0
    lastPayment.reason = tostring(payload.reason or lastPayment.reason or 'Imposto')
  end

  setFocus(true)

  SendNUIMessage({
    action = 'open',
    mode = tostring(mode or ''),
    payload = payload
  })

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
    print(('[space_economy] %s'):format(msg or '...'))
  end
end)

RegisterNetEvent('space_economy:client_adminData', function(key, data)
  SendNUIMessage({
    action = 'adminData',
    key = key,
    data = data
  })
end)

-- NUI callbacks com sanitização
RegisterNUICallback('ready', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

RegisterNUICallback('nui_ack', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

RegisterNUICallback('forceClose', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

RegisterNUICallback('admin_requestData', function(data, cb)
  local dataType = data and tostring(data.dataType or '')
  local payload = data and data.payload or {}
  pcall(function()
    TriggerServerEvent('space_economy:server_requestAdminData', dataType, payload)
  end)
  cb({ ok = true })
end)

RegisterNUICallback('payTax', function(data, cb)
  local tax = tonumber((data and data.tax) or lastPayment.tax) or 0
  local reason = tostring((data and data.reason) or lastPayment.reason or 'Imposto')
  pcall(function()
    TriggerServerEvent('space_economy:server_payTax', tax, reason)
  end)
  cb({ ok = true })
end)

RegisterNUICallback('refuseTax', function(data, cb)
  local tax = tonumber(data and data.tax) or nil
  local reason = data and tostring(data.reason) or nil
  pcall(function()
    TriggerServerEvent('space_economy:server_refuseTax', tax, reason)
  end)
  cb({ ok = true })
end)

RegisterNUICallback('calculateTax', function(data, cb)
  local amount = tonumber(data and data.amount) or 0
  pcall(function()
    TriggerServerEvent('space_economy:server_calculateTax', amount)
  end)
  cb({ ok = true })
end)

RegisterNUICallback('washMoney', function(data, cb)
  local businessId = data and data.businessId
  local amount = tonumber(data and data.amount) or 0
  local fee = tonumber(data and (data.fee_percent or data.feePercent)) or nil
  pcall(function()
    TriggerServerEvent('space_economy:server_washMoney', businessId, amount, fee)
  end)
  cb({ ok = true })
end)