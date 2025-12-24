--============================================================
-- space_economy - server/events.lua
-- Roteador server -> módulos | NUI/admin_requestData | compat legado
--============================================================
SE = SE or {}
SE.Server = SE.Server or {}

local U = SE.Util
local B = SE.Bridge

--============================================================
-- Logs (compat com sua tabela atual: usa "metadata" se existir)
--============================================================
local logsReady = false
local logsMetaCol = 'metadata'

local function ensureLogs()
  if logsReady or not MySQL then return end
  logsReady = true

  -- Se não existir, cria no formato "flexível"
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_logs (
      id BIGINT NOT NULL AUTO_INCREMENT,
      timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      category VARCHAR(50) NOT NULL,
      message TEXT NOT NULL,
      actor_citizenid VARCHAR(50) NULL,
      target_citizenid VARCHAR(50) NULL,
      amount BIGINT NULL,
      metadata LONGTEXT NULL,
      meta LONGTEXT NULL,
      PRIMARY KEY (id),
      INDEX idx_timestamp (timestamp),
      INDEX idx_category (category)
    )
  ]])

  -- Detecta coluna disponível
  local cols = MySQL.query.await('SHOW COLUMNS FROM space_economy_logs') or {}
  local has = {}
  for _, c in ipairs(cols) do
    has[c.Field] = true
  end
  if has.metadata then logsMetaCol = 'metadata'
  elseif has.meta then logsMetaCol = 'meta'
  else logsMetaCol = nil end
end

SE.Log = SE.Log or function(kind, msg, meta)
  kind = tostring(kind or 'system')
  msg = tostring(msg or '')

  if MySQL then
    ensureLogs()
    local payload = U.safeJsonEncode(meta or {})

    if logsMetaCol then
      MySQL.insert.await(
        ('INSERT INTO space_economy_logs (category, message, %s) VALUES (?, ?, ?)'):format(logsMetaCol),
        { kind, msg, payload }
      )
    else
      MySQL.insert.await(
        'INSERT INTO space_economy_logs (category, message) VALUES (?, ?)',
        { kind, msg }
      )
    end
  end

  if Config and Config.Debug then
    print(('[space_economy][%s] %s'):format(kind, msg))
  end
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureLogs()
end)

--============================================================
-- Helpers
--============================================================
local function AdminAllowed(src)
  return (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) == true
end

local function SendAdminData(src, key, payload)
  TriggerClientEvent('space_economy:client_adminData', src, key, payload)
end

local function Notify(src, msg, typ)
  if B and B.Notify then
    B.Notify(src, msg, typ or 'inform', 'Economia')
  else
    TriggerClientEvent('space_economy:client_notify', src, msg, typ or 'inform')
  end
end

local function TreasuryDeposit(amount, reason, meta)
  if SE.Treasury and SE.Treasury.Deposit then
    return SE.Treasury.Deposit(amount, reason, meta)
  end
  if SE.Treasury and SE.Treasury.Modify then
    return SE.Treasury.Modify(amount, reason, meta)
  end
  return 0
end

local function TreasuryWithdraw(amount, reason, meta)
  amount = U.toInt(amount, 0)
  if amount <= 0 then return 0 end

  if SE.Treasury and SE.Treasury.Withdraw then
    return SE.Treasury.Withdraw(amount, reason, meta)
  end
  if SE.Treasury and SE.Treasury.Modify then
    return SE.Treasury.Modify(-amount, reason, meta)
  end
  return 0
end

--============================================================
-- Abertura de painéis
--============================================================
RegisterNetEvent('space_economy:server_openTaxPanel', function()
  local src = source
  TriggerClientEvent('space_economy:client_open', src, 'tax', {})
end)

RegisterNetEvent('space_economy:server_openAdminPanel', function()
  local src = source

  if not AdminAllowed(src) then
    SE.Log('admin', 'Acesso negado (permissão)', { src = src })
    Notify(src, 'Acesso negado.', 'error')
    return
  end

  local st = (SE.Admin and SE.Admin.GetStatePayload and SE.Admin.GetStatePayload()) or {}
  TriggerClientEvent('space_economy:client_open', src, 'admin', st)
end)

--============================================================
-- Router admin_requestData (NUI)
--============================================================
RegisterNetEvent('space_economy:server_requestAdminData', function(dataType, payload, forcedSrc)
  local src = forcedSrc or source
  if not AdminAllowed(src) then
    Notify(src, 'Acesso negado.', 'error')
    return
  end

  dataType = tostring(dataType or '')

  if dataType == 'admin_state' then
    local st = (SE.Admin and SE.Admin.GetStatePayload and SE.Admin.GetStatePayload()) or {}
    SendAdminData(src, 'admin_state', st)
    return
  end

  if dataType == 'admin_logs' then
    local limit = 80
    if type(payload) == 'table' and payload.limit then
      limit = U.toInt(payload.limit, 80)
    end
    local logs = (SE.Admin and SE.Admin.FetchLogs and SE.Admin.FetchLogs(limit)) or {}
    SendAdminData(src, 'admin_logs', { logs = logs })
    return
  end

  if dataType == 'admin_saveSettings' then
    if SE.Admin and SE.Admin.ApplySettings then
      SE.Admin.ApplySettings(payload or {})
    end
    TriggerEvent('space_economy:server_requestAdminData', 'admin_state', nil, src)
    return
  end

  if dataType == 'admin_issueTaxDebt' then
    if not (SE.Admin and SE.Admin.IssueTaxDebt) then
      Notify(src, 'Admin indisponível.', 'error')
      return
    end

    local ok, msg = SE.Admin.IssueTaxDebt(src, payload or {})
    Notify(src, msg or (ok and 'Lançamento registrado.' or 'Falha ao lançar.'), ok and 'success' or 'error')

    TriggerEvent('space_economy:server_requestAdminData', 'admin_state', nil, src)
    local debts = (SE.Admin and SE.Admin.ListDebts and SE.Admin.ListDebts(200)) or {}
    SendAdminData(src, 'debts_active', debts)
    return
  end

  if dataType == 'viewVault' then
    local bal = (SE.Admin and SE.Admin.ViewVault and SE.Admin.ViewVault()) or 0
    TriggerClientEvent('space_economy:client_open', src, 'vault_view', { balance = bal })
    return
  end

  if dataType == 'addVault' then
    local amt = type(payload) == 'table' and payload.amount or payload
    amt = U.toInt(amt, 0)

    if amt <= 0 then
      TriggerClientEvent('space_economy:client_open', src, 'vault_add', {})
      return
    end

    local newBal = TreasuryDeposit(amt, 'admin_deposito', { by = src })
    Notify(src, ('Depósito realizado. Saldo: $%d'):format(U.toInt(newBal, 0)), 'success')
    TriggerEvent('space_economy:server_requestAdminData', 'admin_state', nil, src)
    return
  end

  if dataType == 'withdrawVault' then
    local amt = type(payload) == 'table' and payload.amount or payload
    amt = U.toInt(amt, 0)

    if amt <= 0 then
      TriggerClientEvent('space_economy:client_open', src, 'vault_withdraw', {})
      return
    end

    local newBal = TreasuryWithdraw(amt, 'admin_saque', { by = src })
    Notify(src, ('Saque realizado. Saldo: $%d'):format(U.toInt(newBal, 0)), 'success')
    TriggerEvent('space_economy:server_requestAdminData', 'admin_state', nil, src)
    return
  end

  if dataType == 'viewDebts' or dataType == 'debts_active' then
    local debts = (SE.Admin and SE.Admin.ListDebts and SE.Admin.ListDebts(200)) or {}
    SendAdminData(src, 'debts_active', debts)
    return
  end

  if dataType == 'specific_debt' then
    local cid = type(payload) == 'table' and payload.citizenid or payload
    cid = tostring(cid or '')
    if cid == '' then
      Notify(src, 'Informe um CitizenID.', 'error')
      return
    end

    local list = (SE.Admin and SE.Admin.GetDebtsByCitizen and SE.Admin.GetDebtsByCitizen(cid, 50)) or {}
    local first = list[1]
    if not first then
      SendAdminData(src, 'debt_specific', {
        citizenid = cid,
        playerName = 'Desconhecido',
        amount = 0,
        reason = 'Nenhuma dívida ativa.'
      })
    else
      SendAdminData(src, 'debt_specific', first)
    end
    return
  end

  if dataType == 'collect_debt' then
    local cid = type(payload) == 'table' and payload.citizenid or payload
    cid = tostring(cid or '')
    if cid == '' then
      Notify(src, 'Informe um CitizenID.', 'error')
      return
    end

    local list = (SE.Admin and SE.Admin.GetDebtsByCitizen and SE.Admin.GetDebtsByCitizen(cid, 50)) or {}
    local first = list[1]
    if not first then
      Notify(src, 'Nenhuma dívida ativa para este CitizenID.', 'inform')
      return
    end

    if SE.Integrations and SE.Integrations.EmitWarrantIfNeeded then
      SE.Integrations.EmitWarrantIfNeeded(first)
    end

    Notify(src, ('Cobrança iniciada para %s.'):format(first.playerName or cid), 'success')
    SendAdminData(src, 'debt_specific', first)
    return
  end

  SE.Log('admin', 'admin_requestData: dataType desconhecido', { src = src, dataType = dataType })
end)

--============================================================
-- Player endpoints (NUI / legacy)
--============================================================
RegisterNetEvent('space_economy:server_payOnlyTax', function(amount, reason)
  local src = source
  amount = U.toNumber(amount, 0)

  local tax = (SE.Tax and SE.Tax.Calculate and SE.Tax.Calculate(amount)) or 0
  if tax <= 0 then
    Notify(src, 'Nenhum imposto calculado.', 'inform')
    return
  end

  if (B.GetBankBalance(src) or 0) < tax then
    Notify(src, 'Saldo bancário insuficiente.', 'error')
    return
  end

  if not B.RemoveBankMoney(src, tax, reason or 'Pagamento de imposto') then
    Notify(src, 'Falha ao debitar.', 'error')
    return
  end

  TreasuryDeposit(tax, 'imposto', { src = src, base = amount, reason = reason })
  Notify(src, ('Imposto pago: $%d'):format(tax), 'success')
end)

RegisterNetEvent('space_economy:server_payTax', function(tax, reason)
  local src = source
  tax = U.toInt(tax, 0)
  reason = tostring(reason or 'Imposto')

  if tax <= 0 then
    Notify(src, 'Nenhum valor para pagar.', 'error')
    return
  end

  if (B.GetBankBalance(src) or 0) < tax then
    Notify(src, 'Saldo bancário insuficiente.', 'error')
    return
  end

  if not B.RemoveBankMoney(src, tax, ('Pagamento: %s'):format(reason)) then
    Notify(src, 'Falha ao debitar.', 'error')
    return
  end

  TreasuryDeposit(tax, 'imposto_pagamento_ui', { src = src, reason = reason })
  Notify(src, ('Imposto pago: $%d'):format(tax), 'success')
end)

RegisterNetEvent('space_economy:server_refuseTax', function()
  local src = source
  SE.Log('tax', 'Imposto recusado', { src = src })
end)

RegisterNetEvent('space_economy:server_calculateTax', function(amount)
  local src = source
  amount = U.toNumber(amount, 0)
  local tax = (SE.Tax and SE.Tax.Calculate and SE.Tax.Calculate(amount)) or 0
  Notify(src, ('Simulação: Base $%d → Imposto $%d'):format(U.toInt(amount, 0), U.toInt(tax, 0)), 'inform')
end)

RegisterNetEvent('space_economy:server_washMoney', function(businessId, amount, feePercent)
  local src = source
  if SE.Integrations and SE.Integrations.WashMoney then
    return SE.Integrations.WashMoney(src, businessId, amount, feePercent)
  end
  Notify(src, 'Lavagem não configurada neste servidor.', 'error')
end)
