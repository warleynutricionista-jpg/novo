--============================================================
-- space_economy - server/tax.lua
-- Motor de cálculo de impostos e handlers para pagamento
--============================================================
SE = SE or {}
SE.Tax = SE.Tax or {}
local U = SE.Util
local cfg = Config or {}

local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][tax]^7', ...) end end

-- Calcula imposto progressivo com base em Config.TaxBrackets
function SE.Tax.Calculate(amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then return 0 end
  local brackets = cfg.TaxBrackets or {}
  local tax = 0
  local remaining = amount
  for i, b in ipairs(brackets) do
    local minv = tonumber(b.min) or 0
    local maxv = b.max and tonumber(b.max) or nil
    local rate = tonumber(b.rate) or 0
    if (not maxv and amount > minv) or (maxv and amount > minv) then
      local taxable
      if not maxv then
        taxable = math.max(0, amount - minv)
      else
        taxable = math.max(0, math.min(amount, maxv) - minv)
      end
      tax = tax + (taxable * rate)
    end
  end

  -- aplicar multiplicador e inflação
  local mult = tonumber(SE.State.taxMultiplier) or (cfg.TaxMultiplierDefault or 1.0)
  local inf = tonumber(SE.State.inflationRate) or (cfg.Inflation and cfg.Inflation.DefaultRate) or 1.0
  tax = tax * mult * inf
  return math.floor(tax + 0.5)
end

-- Integração genérica para remover dinheiro do jogador (tentativa multi-framework)
local function removePlayerMoney(src, amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then return false end
  -- QBCore
  if global and global.QBCore then
    local Player = global.QBCore.Functions.GetPlayer(src)
    if Player then
      if Player.Functions.RemoveMoney then
        Player.Functions.RemoveMoney('bank', amount)
        return true
      end
    end
  end
  -- fallback: disparar evento para o client que deve tratar
  TriggerClientEvent('space_economy:client_notify', src, 'Remova manualmente '..tostring(amount)..' (integração não configurada)', 'error')
  return false
end

-- Handler: calcular imposto (retorna para o player via notificação ou evento)
RegisterNetEvent('space_economy:server_calculateTax', function(amount)
  local src = source
  local tax = 0
  pcall(function() tax = SE.Tax.Calculate(amount) end)
  TriggerClientEvent('space_economy:client_notify', src, ('Imposto estimado: %s'):format(tostring(tax)), 'inform')
end)

-- Handler: pagar imposto
RegisterNetEvent('space_economy:server_payTax', function(amount, reason)
  local src = source
  amount = tonumber(amount) or 0
  reason = tostring(reason or 'Imposto')
  if amount <= 0 then
    TriggerClientEvent('space_economy:client_notify', src, 'Valor inválido para pagamento', 'error')
    return
  end

  -- tentar deduzir do jogador (integração) - se falhar, avisar
  local ok = removePlayerMoney(src, amount)
  if not ok then
    TriggerClientEvent('space_economy:client_notify', src, 'Pagamento não concluído: integração de economia ausente', 'error')
    return
  end

  -- adicionar ao tesouro
  SE.Treasury.Add(amount)
  -- log (persistir em se_logs)
  if MySQL then
    MySQL.execute('INSERT INTO se_logs (level, source, message, data) VALUES (?, ?, ?, ?)', { 'info', 'tax', ('Pagamento: %s por %s'):format(tostring(amount), reason), json.encode({source = src}) })
  end

  TriggerClientEvent('space_economy:client_notify', src, ('Pagamento confirmado: %s'):format(tostring(amount)), 'success')
end)

-- Handler: recusar imposto (ex: abrir dívida)
RegisterNetEvent('space_economy:server_refuseTax', function(amount, reason)
  local src = source
  amount = tonumber(amount) or 0
  reason = tostring(reason or 'Imposto')
  if amount <= 0 then
    TriggerClientEvent('space_economy:client_notify', src, 'Valor inválido para recusa', 'error')
    return
  end

  -- registrar dívida para o jogador (precisa de integration para id)
  local citizen = tostring(src)
  if SE.Debts and SE.Debts.CreateDebt then
    SE.Debts.CreateDebt(citizen, amount, Config.DebtSystem and Config.DebtSystem.InterestDailyRate or 0.01)
    TriggerClientEvent('space_economy:client_notify', src, 'Dívida registrada: '..tostring(amount), 'inform')
  else
    TriggerClientEvent('space_economy:client_notify', src, 'Não foi possível registrar a dívida (módulo debts ausente)', 'error')
  end
end)
