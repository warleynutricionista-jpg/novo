--============================================================
-- space_economy - server/integrations.lua (MELHORADO)
-- Multi-framework wrapper com fallbacks robustos
--============================================================
SE = SE or {}
SE.Integrations = SE.Integrations or {}

local U = SE.Util
local B = SE.Bridge

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[integrations]^7', ...) end 
end

--============================================================
-- DETECÇÃO DE FRAMEWORKS
--============================================================
local FrameworkDetected = nil

local function DetectFramework()
  if FrameworkDetected then return FrameworkDetected end
  
  -- QBX Core
  if GetResourceState('qbx_core') == 'started' and exports.qbx_core then
    FrameworkDetected = 'qbx'
    dbg('Framework detectado: QBX Core')
    return 'qbx'
  end
  
  -- QBCore
  if GetResourceState('qb-core') == 'started' and exports['qb-core'] then
    FrameworkDetected = 'qbcore'
    dbg('Framework detectado: QBCore')
    return 'qbcore'
  end
  
  -- ESX (futuro)
  if GetResourceState('es_extended') == 'started' then
    FrameworkDetected = 'esx'
    dbg('Framework detectado: ESX')
    return 'esx'
  end
  
  FrameworkDetected = 'unknown'
  dbg('AVISO: Framework não detectado')
  return 'unknown'
end

--============================================================
-- MONEY OPERATIONS (Melhoradas)
--============================================================

-- Remove money com validações robustas
function SE.Integrations.RemoveMoney(src, amount, account)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end
  
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end
  
  account = account or 'bank'
  
  local framework = DetectFramework()
  
  -- Tenta via Bridge primeiro (mais confiável)
  if B and B.RemoveMoney then
    local ok = B.RemoveMoney(src, account, amount, 'space_economy')
    if ok then
      dbg(('RemoveMoney via Bridge: %d removeu $%d de %s'):format(src, amount, account))
      return true
    end
  end
  
  -- QBX Core direto
  if framework == 'qbx' and exports.qbx_core then
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.Functions and player.Functions.RemoveMoney then
      local ok, err = pcall(function()
        return player.Functions.RemoveMoney(account, amount, 'space_economy')
      end)
      if ok then
        dbg(('RemoveMoney via QBX: %d removeu $%d'):format(src, amount))
        return true
      end
    end
  end
  
  -- QBCore direto
  if framework == 'qbcore' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if ok and QBCore then
      local player = QBCore.Functions.GetPlayer(src)
      if player and player.Functions and player.Functions.RemoveMoney then
        local ok2, err = pcall(function()
          return player.Functions.RemoveMoney(account, amount, 'space_economy')
        end)
        if ok2 then
          dbg(('RemoveMoney via QBCore: %d removeu $%d'):format(src, amount))
          return true
        end
      end
    end
  end
  
  -- Fallback: evento client-side (requer implementação no client)
  dbg(('FALLBACK RemoveMoney para src %d: $%d'):format(src, amount))
  TriggerClientEvent('space_economy:client_requestRemoveMoney', src, amount, account)
  
  return false, 'no_integration'
end

-- Add money com validações robustas
function SE.Integrations.AddMoney(src, amount, account)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end
  
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end
  
  account = account or 'bank'
  
  local framework = DetectFramework()
  
  -- Bridge primeiro
  if B and B.AddMoney then
    local ok = B.AddMoney(src, account, amount, 'space_economy')
    if ok then
      dbg(('AddMoney via Bridge: %d recebeu $%d em %s'):format(src, amount, account))
      return true
    end
  end
  
  -- QBX
  if framework == 'qbx' and exports.qbx_core then
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.Functions and player.Functions.AddMoney then
      local ok, err = pcall(function()
        return player.Functions.AddMoney(account, amount, 'space_economy')
      end)
      if ok then
        dbg(('AddMoney via QBX: %d recebeu $%d'):format(src, amount))
        return true
      end
    end
  end
  
  -- QBCore
  if framework == 'qbcore' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if ok and QBCore then
      local player = QBCore.Functions.GetPlayer(src)
      if player and player.Functions and player.Functions.AddMoney then
        local ok2, err = pcall(function()
          return player.Functions.AddMoney(account, amount, 'space_economy')
        end)
        if ok2 then
          dbg(('AddMoney via QBCore: %d recebeu $%d'):format(src, amount))
          return true
        end
      end
    end
  end
  
  dbg(('FALLBACK AddMoney para src %d: $%d'):format(src, amount))
  TriggerClientEvent('space_economy:client_requestAddMoney', src, amount, account)
  
  return false, 'no_integration'
end

-- Verifica saldo
function SE.Integrations.GetBalance(src, account)
  src = tonumber(src)
  if not src or src <= 0 then return 0 end
  
  account = account or 'bank'
  
  if B and B.GetBalance then
    return B.GetBalance(src, account)
  end
  
  local framework = DetectFramework()
  
  if framework == 'qbx' and exports.qbx_core then
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.money then
      return U.toInt(player.PlayerData.money[account], 0)
    end
  end
  
  if framework == 'qbcore' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if ok and QBCore then
      local player = QBCore.Functions.GetPlayer(src)
      if player and player.PlayerData and player.PlayerData.money then
        return U.toInt(player.PlayerData.money[account], 0)
      end
    end
  end
  
  return 0
end

--============================================================
-- MANDADOS / DISPATCH (Integração ps-dispatch / ps-mdt)
--============================================================
function SE.Integrations.EmitWarrantIfNeeded(debt)
  if not debt then return false end
  
  local cfg = Config.WarrantAlert or {}
  if not cfg.Enabled then return false end
  
  local days = (Config.DebtSystem and Config.DebtSystem.WarrantAfterDaysOverdue) or 7
  
  -- Verifica se vencida há X dias
  if not debt.due_at then return false end
  
  local dueTs = 0
  if type(debt.due_at) == 'string' then
    -- Parse ISO timestamp (simplificado)
    local year, month, day = debt.due_at:match('(%d+)-(%d+)-(%d+)')
    if year then
      dueTs = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=0, min=0, sec=0})
    end
  end
  
  if dueTs == 0 then return false end
  
  local now = os.time()
  local overdueDays = math.floor((now - dueTs) / (24 * 60 * 60))
  
  if overdueDays < days then return false end
  
  -- ps-dispatch
  if cfg.UsePsDispatch and GetResourceState('ps-dispatch') == 'started' then
    local coords = vector3(0.0, 0.0, 0.0) -- Ajustar se souber posição
    
    pcall(function()
      exports['ps-dispatch']:CustomAlert({
        coords = coords,
        message = cfg.Message or 'Cidadão com dívida ativa',
        dispatchCode = '10-90',
        description = ('Dívida: $%d | %s'):format(U.toInt(debt.amount, 0), debt.reason or ''),
        radius = 0,
        sprite = 457,
        color = 1,
        scale = 1.0,
        length = 3,
      })
    end)
    
    dbg('Mandado emitido via ps-dispatch para:', debt.citizenid)
    return true
  end
  
  -- ps-mdt (criar report/warrant)
  if cfg.UsePsMdt and GetResourceState('ps-mdt') == 'started' then
    pcall(function()
      exports['ps-mdt']:NewReport({
        author = 'Sistema Fiscal',
        title = cfg.Title or 'Dívida Ativa',
        description = ('%s\nValor: $%d\nCitizenID: %s'):format(
          cfg.Message or '',
          U.toInt(debt.amount, 0),
          debt.citizenid
        ),
        tags = {'fiscal', 'divida'},
        officers = {},
      })
    end)
    
    dbg('Report criado via ps-mdt para:', debt.citizenid)
    return true
  end
  
  return false
end

--============================================================
-- BANKING (ps-banking / qb-banking / qbx-banking)
--============================================================
function SE.Integrations.BankingTransfer(fromSrc, toAccount, amount, reason)
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end
  
  -- ps-banking
  if GetResourceState('ps-banking') == 'started' and exports['ps-banking'] then
    local methods = {'Transfer', 'transfer', 'TransferMoney'}
    for _, m in ipairs(methods) do
      if type(exports['ps-banking'][m]) == 'function' then
        local ok, res = pcall(exports['ps-banking'][m], fromSrc, toAccount, amount, reason or 'Transferência')
        if ok and res then
          dbg('Transfer via ps-banking:', fromSrc, '->', toAccount, amount)
          return true
        end
      end
    end
  end
  
  -- qb-banking / qbx-banking
  local bankingRes = GetResourceState('qb-banking') == 'started' and 'qb-banking' or 
                     GetResourceState('qbx-banking') == 'started' and 'qbx-banking' or nil
  
  if bankingRes and exports[bankingRes] then
    local ok, res = pcall(exports[bankingRes].Transfer, fromSrc, toAccount, amount)
    if ok and res then
      dbg('Transfer via', bankingRes, ':', fromSrc, '->', toAccount, amount)
      return true
    end
  end
  
  return false, 'no_banking_integration'
end

--============================================================
-- LAVAGEM (Stub para futuro)
--============================================================
function SE.Integrations.WashMoney(src, businessId, amount, feePercent)
  -- Implementar integração com sistemas de lavagem
  -- Por enquanto, apenas placeholder
  B.Notify(src, 'Sistema de lavagem não configurado', 'error')
  return false
end

--============================================================
-- EXPORTS
--============================================================
exports('RemoveMoney', SE.Integrations.RemoveMoney)
exports('AddMoney', SE.Integrations.AddMoney)
exports('GetBalance', SE.Integrations.GetBalance)
exports('EmitWarrant', SE.Integrations.EmitWarrantIfNeeded)