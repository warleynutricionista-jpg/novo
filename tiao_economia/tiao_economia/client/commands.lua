--============================================================
-- space_economy - client/commands.lua
-- Comandos + keymapping | Diagnóstico (test UI) | Server valida permissões
--============================================================

local function n(msg, typ)
  if lib and lib.notify then
    lib.notify({ title = 'Economia', description = msg, type = typ or 'inform' })
  else
    print(('[space_economy] %s'):format(msg))
  end
end

local function openTax()
  n('Solicitado: painel de impostos.', 'inform')
  TriggerServerEvent('space_economy:server_openTaxPanel')
end

local function openAdmin()
  n('Solicitado: painel administrativo (server vai validar permissão).', 'inform')
  TriggerServerEvent('space_economy:server_openAdminPanel')
end

-- TESTE: abre a NUI localmente (ignora permissão) pra diagnosticar se NUI está ok
local function testAdminUI()
  n('Teste: abrindo NUI ADMIN local (sem permissão).', 'inform')
  TriggerEvent('space_economy:client_open', 'admin', {})
end

-- /taxas
RegisterCommand('taxas', function()
  openTax()
end, false)

-- /economia (admin)
RegisterCommand('economia', function()
  openAdmin()
end, false)

-- /eco_testui (diagnóstico)
RegisterCommand('eco_testui', function()
  testAdminUI()
end, false)

-- Keymapping (evite F8 porque conflita com console do FiveM)
RegisterKeyMapping('taxas', 'Economia: abrir painel de impostos', 'keyboard', 'F7')
RegisterKeyMapping('economia', 'Economia: abrir painel administrativo', 'keyboard', 'F9')
RegisterKeyMapping('eco_testui', 'Economia: TESTE abrir NUI admin local', 'keyboard', 'F10')

CreateThread(function()
  Wait(1000)
  -- sugestões (se chat resource existir)
  pcall(function()
    TriggerEvent('chat:addSuggestion', '/taxas', 'Abrir painel de impostos/pagamentos')
    TriggerEvent('chat:addSuggestion', '/economia', 'Abrir painel administrativo (requer permissão)')
    TriggerEvent('chat:addSuggestion', '/eco_testui', 'TESTE: abrir painel admin local (diagnóstico NUI)')
  end)
end)
