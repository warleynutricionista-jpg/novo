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

--============================================================
-- FALLBACK: Eventos bancários quando não há integração externa
-- (Adicionado em 24/12/2025 - Correção de bugs)
--============================================================

-- Remove dinheiro do player (fallback quando servidor não consegue)
RegisterNetEvent('space_economy:client_requestRemoveMoney', function(amount, account)
  if not amount or amount <= 0 then return end
  account = account or 'bank'

  -- Tenta via QBX Core
  if GetResourceState('qbx_core') == 'started' then
    local success, result = pcall(function()
      return exports.qbx_core:RemoveMoney(account, amount, 'space_economy')
    end)

    if success and result then
      local accountLabel = account == 'bank' and 'banco' or 'dinheiro'
      lib.notify({
        title = 'Economia',
        description = ('$%s debitado de %s'):format(amount, accountLabel),
        type = 'inform'
      })

      -- Notifica servidor que operação foi concluída
      TriggerServerEvent('space_economy:client_moneyRemoved', amount, account, true)
    else
      lib.notify({
        title = 'Erro',
        description = 'Não foi possível debitar o valor',
        type = 'error'
      })
      TriggerServerEvent('space_economy:client_moneyRemoved', amount, account, false)
    end
    return
  end

  -- Tenta via QBCore
  if GetResourceState('qb-core') == 'started' then
    local success, QBCore = pcall(function()
      return exports['qb-core']:GetCoreObject()
    end)

    if success and QBCore and QBCore.Functions then
      QBCore.Functions.Notify(('$%s debitado'):format(amount), 'inform')
      TriggerServerEvent('space_economy:client_moneyRemoved', amount, account, true)
    else
      QBCore.Functions.Notify('Erro ao debitar', 'error')
      TriggerServerEvent('space_economy:client_moneyRemoved', amount, account, false)
    end
    return
  end

  -- Se chegou aqui, não há framework disponível
  print('[space_economy] ERRO: Nenhum framework disponível para processar RemoveMoney')
  TriggerServerEvent('space_economy:client_moneyRemoved', amount, account, false)
end)

-- Adiciona dinheiro ao player (fallback quando servidor não consegue)
RegisterNetEvent('space_economy:client_requestAddMoney', function(amount, account)
  if not amount or amount <= 0 then return end
  account = account or 'bank'

  -- Tenta via QBX Core
  if GetResourceState('qbx_core') == 'started' then
    local success, result = pcall(function()
      return exports.qbx_core:AddMoney(account, amount, 'space_economy')
    end)

    if success and result then
      local accountLabel = account == 'bank' and 'banco' or 'dinheiro'
      lib.notify({
        title = 'Economia',
        description = ('$%s creditado em %s'):format(amount, accountLabel),
        type = 'success'
      })

      -- Notifica servidor que operação foi concluída
      TriggerServerEvent('space_economy:client_moneyAdded', amount, account, true)
    else
      lib.notify({
        title = 'Erro',
        description = 'Não foi possível creditar o valor',
        type = 'error'
      })
      TriggerServerEvent('space_economy:client_moneyAdded', amount, account, false)
    end
    return
  end

  -- Tenta via QBCore
  if GetResourceState('qb-core') == 'started' then
    local success, QBCore = pcall(function()
      return exports['qb-core']:GetCoreObject()
    end)

    if success and QBCore and QBCore.Functions then
      QBCore.Functions.Notify(('$%s creditado'):format(amount), 'success')
      TriggerServerEvent('space_economy:client_moneyAdded', amount, account, true)
    else
      QBCore.Functions.Notify('Erro ao creditar', 'error')
      TriggerServerEvent('space_economy:client_moneyAdded', amount, account, false)
    end
    return
  end

  -- Se chegou aqui, não há framework disponível
  print('[space_economy] ERRO: Nenhum framework disponível para processar AddMoney')
  TriggerServerEvent('space_economy:client_moneyAdded', amount, account, false)
end)
