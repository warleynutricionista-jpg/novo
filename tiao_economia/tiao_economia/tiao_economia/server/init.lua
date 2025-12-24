--============================================================
-- space_economy - server/init.lua
-- Bootstrap do servidor (namespace + defaults + guards) - versão corrigida
--============================================================
SE = SE or {}

-- Namespaces
SE.Server = SE.Server or {}
SE.State  = SE.State  or {}
SE.Admin  = SE.Admin  or {}
SE.Debts  = SE.Debts  or {}
SE.Tax    = SE.Tax    or {}
SE.Treasury = SE.Treasury or {}
SE.Integrations = SE.Integrations or {}
SE.CharCache = SE.CharCache or {}
SE.Metrics = SE.Metrics or {}

-- Meta
SE.Resource = GetCurrentResourceName()
SE.Version = (GetResourceMetadata(SE.Resource, 'version', 0) or '0.0.0')

-- Utility reference (pode ser nil, usamos guardas)
local U = SE.Util

-- Defaults mínimos (não duplicar lógica do state.lua; só garante existência)
SE.State.dirty = SE.State.dirty == true
SE.State.vaultBalance = (U and U.toInt and U.toInt(SE.State.vaultBalance, 0)) or (SE.State.vaultBalance or 0)
SE.State.inflationRate = (U and U.toNumber and U.toNumber(SE.State.inflationRate, 1.0)) or (SE.State.inflationRate or 1.0)
SE.State.taxMultiplier = (U and U.toNumber and U.toNumber(SE.State.taxMultiplier, 1.0)) or (SE.State.taxMultiplier or 1.0)
SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}

-- Ready flag (útil pra integrações que esperam load state)
SE.Server._ready = false
function SE.Server.IsReady()
  return SE.Server._ready == true
end

function SE.Server.SetReady(v)
  SE.Server._ready = (v == true)
end

-- Helper: log de boot
function SE.Server.BootLog(...)
  if U and U.dbg then
    U.dbg(...)
  else
    print('^3[space_economy]^7', ...)
  end
end

-- Marcar ready assim que o state.lua carregar (state.lua chama LoadState no thread)
CreateThread(function()
  -- aguarda MySQL existir (timeout) - espera por até 15s
  local waited = 0
  local timeout = 15000
  while not MySQL do
    Wait(200)
    waited = waited + 200
    if waited > timeout then
      SE.Server.BootLog('Aviso: MySQL não disponível após '..tostring(timeout/1000)..'s, prosseguindo (algumas funções podem falhar).')
      break
    end
  end

  -- pequena espera para o state carregar (state.lua deverá definir e limpar dirty)
  Wait(500)

  SE.Server.SetReady(true)
  SE.Server.BootLog(('Server init pronto | %s v%s'):format(SE.Resource, SE.Version))
end)