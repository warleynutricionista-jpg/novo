--============================================================
-- space_economy - server/integrations.lua
-- Tentáculos (ps-dispatch / ps-mdt / banking / shops / housing / garages)
-- Tudo SAFE: se recurso não existir, não quebra.
--============================================================
SE = SE or {}
SE.Integrations = SE.Integrations or {}

local I = SE.Integrations
local U = SE.Util
local B = SE.Bridge

local function resStarted(name)
  return GetResourceState(name) == 'started'
end

local function safePcall(fn)
  local ok, res = pcall(fn)
  if not ok then U.dbg('Integrations erro:', res) end
  return ok, res
end

-- Anti-duplicação em runtime (sessão atual)
local issuedWarrants = {} -- [debtId] = true

--============================================================
-- Export helpers (shops / external)
--============================================================
function I.GetInflationMultiplier()
  return U.toNumber((SE.State and SE.State.inflationRate) or 1.0, 1.0)
end

exports('GetInflationMultiplier', function()
  return I.GetInflationMultiplier()
end)

--============================================================
-- SPC/Serasa - bloqueios por dívida
-- service: 'bank' | 'garage' | 'housing' | 'dealership' | etc
--============================================================
function I.CanUseService(src, service)
  local cid = (B and B.GetCitizenId and B.GetCitizenId(src)) or nil
  if not cid then return true end

  if not (SE.Debts and SE.Debts.IsLocked) then return true end
  if not SE.Debts.IsLocked(cid) then return true end

  service = tostring(service or 'serviço'):lower()
  local msg = ('Acesso bloqueado por dívida ativa. Regularize no banco. Serviço: %s'):format(service)
  return false, msg
end

exports('CanUseService', function(src, service)
  local ok, msg = I.CanUseService(src, service)
  return ok, msg
end)

--============================================================
-- Taxa em transação (IVA/Taxa)
-- Usar em integrações (ps-banking/management/etc).
-- mode:
--  - "percent" -> percent em 0..100 (ex: 1.5)
--  - "calculate" -> usa SE.Tax.Calculate(baseAmount)
--============================================================
function I.ApplyTransactionTax(src, baseAmount, opts)
  opts = opts or {}
  baseAmount = U.toInt(baseAmount, 0)
  if baseAmount <= 0 then return true, 0 end

  local account = tostring(opts.account or 'bank')
  local reason = tostring(opts.reason or 'Taxa de transação')
  local mode = tostring(opts.mode or 'percent'):lower()
  local percent = U.toNumber(opts.percent or 0.0, 0.0)

  local tax = 0
  if mode == 'calculate' and SE.Tax and SE.Tax.Calculate then
    tax = U.toInt(SE.Tax.Calculate(baseAmount), 0)
  else
    if percent < 0 then percent = 0 end
    tax = U.toInt(math.floor(baseAmount * (percent / 100.0)), 0)
  end

  if tax <= 0 then return true, 0 end

  -- bloqueio opcional por dívida (se quiser aplicar antes de debitar)
  if opts.blockIfLocked then
    local okUse, msg = I.CanUseService(src, 'bank')
    if not okUse then
      if B and B.Notify then B.Notify(src, msg, 'error', 'Economia') end
      return false, 0
    end
  end

  -- debita do player
  local okDebit = true
  if B and B.RemoveMoney then
    okDebit = B.RemoveMoney(src, account, tax, reason)
  elseif B and B.RemoveBankMoney then
    okDebit = B.RemoveBankMoney(src, tax, reason)
  end

  if not okDebit then
    return false, 0
  end

  -- deposita no cofre
  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(tax, 'taxa_transacao', { src = src, base = baseAmount, reason = reason })
  elseif SE.Treasury and SE.Treasury.Modify then
    SE.Treasury.Modify(tax, 'taxa_transacao', { src = src, base = baseAmount, reason = reason })
  end

  if SE.Log then
    SE.Log('tax', ('Taxa de transação: %d (base=%d)'):format(tax, baseAmount), { src = src, account = account, mode = mode, percent = percent })
  end

  return true, tax
end

exports('ApplyTransactionTax', function(src, baseAmount, opts)
  return I.ApplyTransactionTax(src, baseAmount, opts)
end)

--============================================================
-- Polícia: Mandado/alerta por dívida (ps-dispatch / ps-mdt)
-- (stub seguro + idempotente por debtId)
--============================================================
function I.EmitWarrantIfNeeded(debtRow)
  if not (Config and Config.WarrantAlert and Config.WarrantAlert.Enabled) then return false end
  if type(debtRow) ~= 'table' then return false end

  local debtId = U.toInt(debtRow.id or 0, 0)
  if debtId > 0 and issuedWarrants[debtId] then return true end

  local citizenid = tostring(debtRow.citizenid or '')
  if citizenid == '' then return false end

  local amount = U.toInt(debtRow.amount or 0, 0)
  local reason = tostring(debtRow.reason or 'Dívida ativa')
  local playerName = tostring(debtRow.playerName or (SE.CharCache and SE.CharCache.ResolveName and SE.CharCache.ResolveName(citizenid)) or 'Desconhecido')

  local title = tostring(Config.WarrantAlert.Title or 'Mandado por Dívida')
  local message = ('%s (%s) | Valor: $%d | Motivo: %s'):format(playerName, citizenid, amount, reason)

  -- ========= ps-dispatch =========
  if resStarted('ps-dispatch') then
    -- Tentativas comuns (não quebra se não existir)
    -- 1) server notify
    TriggerEvent('ps-dispatch:server:notify', {
      title = title,
      message = message,
      codeName = 'warrant',
      code = '10-99',
      priority = 2,
      coords = nil,
      jobs = Config.WarrantAlert.Jobs or { 'police' }
    })

    -- 2) fallback client broadcast (alguns forks escutam isso)
    TriggerClientEvent('ps-dispatch:client:notify', -1, {
      title = title,
      message = message,
      code = '10-99',
      priority = 2
    })
  end

  -- ========= ps-mdt =========
  if resStarted('ps-mdt') then
    -- Tentativas comuns (não quebra se não existir)
    TriggerEvent('ps-mdt:server:createWarrant', {
      citizenid = citizenid,
      name = playerName,
      reporttitle = title,
      reporttype = 'Warrant',
      reportdetails = message,
      author = 'Governo',
      charges = { 'Dívida ativa' }
    })

    TriggerEvent('ps-mdt:server:addWarrant', citizenid, playerName, message)
  end

  -- marca emitido nesta sessão
  if debtId > 0 then issuedWarrants[debtId] = true end

  if SE.Log then
    SE.Log('police', ('Mandado emitido (stub): %s'):format(citizenid), { debtId = debtId, amount = amount })
  end

  U.dbg('Warrant emitido (stub safe):', citizenid, amount)
  return true
end

--============================================================
-- Hooks futuros (ps-banking/shops/housing/garages)
-- Mantemos a API, mas não registramos listeners sem config.
--============================================================
function I.Init()
  -- Placeholder: aqui a gente vai registrar eventos/listeners baseado em Config.Integrations.*
  -- Ex: Config.Integrations.Banking.ListenEvents = { 'ps-banking:server:transfer', ... }
  U.dbg('Integrations.Init OK')
end

CreateThread(function()
  -- inicializa quando MySQL e State já estiverem
  Wait(0)
  if I.Init then I.Init() end
end)
