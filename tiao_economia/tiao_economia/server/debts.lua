--============================================================
-- space_economy - server/debts.lua (ATUALIZADO)
-- Registro de dívidas e aplicação de juros (usa locks e integrações)
--============================================================
SE = SE or {}
SE.Debts = SE.Debts or {}
local U = SE.Util
local cfg = Config or {}

local function dbg(...) if U and U.dbg then U.dbg(...) else print('^3[space_economy][debts]^7', ...) end end

function SE.Debts.CreateDebt(citizenId, amount, interestRate, days)
  if not citizenId then return false end
  amount = tonumber(amount) or 0
  interestRate = tonumber(interestRate) or (cfg.DebtSystem and cfg.DebtSystem.InterestDailyRate) or 0.01
  local due_at = nil
  if days and tonumber(days) then
    due_at = os.date('%Y-%m-%d %H:%M:%S', os.time() + (tonumber(days) * 24 * 60 * 60))
  end
  if MySQL then
    MySQL.execute('INSERT INTO se_debts (citizen_id, amount, interest_rate, due_at, status) VALUES (?, ?, ?, ?, ?)', { citizenId, amount, interestRate, due_at, 'open' })
  end
  dbg('Dívida criada:', citizenId, amount, interestRate)
  return true
end

-- Aplica juros periodicamente (executa a cada hora por padrão)
CreateThread(function()
  local interval = 60 * 60 * 1000 -- 1 hora
  while true do
    Wait(interval)
    if not (Config and Config.DebtSystem and Config.DebtSystem.Enabled) then goto continue end
    if MySQL then
      MySQL.query('SELECT id, amount, interest_rate FROM se_debts WHERE status = "open"', {}, function(rows)
        if rows then
          for _, r in ipairs(rows) do
            local id = r.id
            local amt = tonumber(r.amount) or 0
            local ir = tonumber(r.interest_rate) or 0
            local interest = math.floor(amt * ir + 0.5)
            local newamt = amt + interest
            MySQL.execute('UPDATE se_debts SET amount = ? WHERE id = ?', { newamt, id })
            dbg(('Applied interest on debt %s : +%s -> %s'):format(tostring(id), tostring(interest), tostring(newamt)))
          end
        end
      end)
    end
    ::continue::
  end
end)

-- Pagar dívida (usa lock por dívida e integração)
RegisterNetEvent('space_economy:server_payDebt', function(debtId)
  local src = source
  if not debtId then
    TriggerClientEvent('space_economy:client_notify', src, 'ID de dívida inválido', 'error')
    return
  end

  local lockKey = ('debt:%s'):format(tostring(debtId))
  local owner = ('src_%s'):format(tostring(src))
  local lk = SE.Locks
  if lk then
    local ok = lk.AcquireBlocking(lockKey, owner, 30000, 5000, 50)
    if not ok then
      TriggerClientEvent('space_economy:client_notify', src, 'Outra operação está bloqueando essa dívida, tente novamente.', 'error')
      return
    end
  end

  -- buscar dívida
  if not MySQL then
    if lk then lk.Release(lockKey, owner, true) end
    TriggerClientEvent('space_economy:client_notify', src, 'MySQL indisponível', 'error')
    return
  end

  MySQL.query('SELECT * FROM se_debts WHERE id = ? LIMIT 1', { debtId }, function(rows)
    if not rows or not rows[1] then
      if lk then lk.Release(lockKey, owner, true) end
      TriggerClientEvent('space_economy:client_notify', src, 'Dívida não encontrada', 'error')
      return
    end
    local d = rows[1]
    local amount = tonumber(d.amount) or 0

    local success, serr = false, nil
    if SE.Integrations and SE.Integrations.RemoveMoney then
      local res, rerr = SE.Integrations.RemoveMoney(src, amount, 'bank')
      success = res == true
      serr = rerr
    else
      serr = 'no_integration'
    end

    if not success then
      if lk then lk.Release(lockKey, owner, true) end
      TriggerClientEvent('space_economy:client_notify', src, 'Falha ao pagar dívida: '..tostring(serr), 'error')
      return
    end

    -- marcar como paga e adicionar ao tesouro
    MySQL.execute('UPDATE se_debts SET status = ?, paid_at = NOW() WHERE id = ?', { 'paid', debtId })
    if SE.Treasury and SE.Treasury.Add then SE.Treasury.Add(amount) end

    if lk then lk.Release(lockKey, owner, true) end
    TriggerClientEvent('space_economy:client_notify', src, 'Dívida paga: '..tostring(amount), 'success')
  end)
end)
