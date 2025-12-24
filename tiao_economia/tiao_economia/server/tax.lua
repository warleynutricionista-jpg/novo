--============================================================
-- space_economy - server/tax.lua (ATUALIZADO)
-- Motor de cálculo de impostos e handlers para pagamento (usa SE.Integrations e locks)
--============================================================
SE = SE or {}
SE.Tax = SE.Tax or {}
local U = SE.Util
local cfg = Config or {}

local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][tax]^7', ...) end end

local locks = SE.Locks or nil
local integ = SE.Integrations or nil

-- Calcula imposto progressivo com base em Config.TaxBrackets
function SE.Tax.Calculate(amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then return 0 end
  local brackets = cfg.TaxBrackets or {}
  local tax = 0
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

-- Handler: calcular imposto (retorna para o player via notificação)
RegisterNetEvent('space_economy:server_calculateTax', function(amount)
  local src = source
  local tax = 0
  pcall(function() tax = SE.Tax.Calculate(amount) end)
  TriggerClientEvent('space_economy:client_notify', src, ('Imposto estimado: %s'):format(tostring(tax)), 'inform')
end)

-- Handler: pagar imposto (usa lock por jogador e integração)
RegisterNetEvent('space_economy:server_payTax', function(amount, reason)
  local src = source
  amount = tonumber(amount) or 0
  reason = tostring(reason or 'Imposto')
  if amount <= 0 then
    TriggerClientEvent('space_economy:client_notify', src, 'Valor inválido para pagamento', 'error')
    return
  end

  local lockKey = ('pay_tax:%s'):format(tostring(src))
  local owner = ('src_%s'):format(tostring(src))
  local lk = SE.Locks
  if lk then
    local ok = lk.AcquireBlocking(lockKey, owner, 30000, 5000, 50)
    if not ok then
      TriggerClientEvent('space_economy:client_notify', src, 'Outra operação financeira está em andamento, tente novamente.', 'error')
      return
    end
  end

  local success, err = false, nil
  if SE.Integrations and SE.Integrations.RemoveMoney then
    local res, rerr = SE.Integrations.RemoveMoney(src, amount, 'bank')
    success = res == true
    err = rerr
  else
    err = 'no_integration'
  end

  -- liberar lock
  if lk then lk.Release(lockKey, owner, true) end

  if not success then
    TriggerClientEvent('space_economy:client_notify', src, 'Pagamento não concluído: '..tostring(err or 'unknown'), 'error')
    return
  end

  -- adicionar ao tesouro
  if SE.Treasury and SE.Treasury.Add then
    SE.Treasury.Add(amount)
  end

  -- log
  if MySQL then
    pcall(function()
      MySQL.execute('INSERT INTO se_logs (level, source, message, data) VALUES (?, ?, ?, ?)', {
        'info',
        'tax',
        ('Pagamento: %s por %s'):format(tostring(amount), reason),
        json.encode({ source = src })
      })
    end)
  end

  TriggerClientEvent('space_economy:client_notify', src, ('Pagamento confirmado: %s'):format(tostring(amount)), 'success')
end)