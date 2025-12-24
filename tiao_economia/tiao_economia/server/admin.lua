--============================================================
-- space_economy - server/admin.lua
-- Admin: permissões, state payload, logs, cofre, dívidas, settings
-- (eventos NUI ficam em server/events.lua)
--============================================================
SE = SE or {}
SE.Admin = SE.Admin or {}

local U = SE.Util
local B = SE.Bridge
local S = SE.State

--============================================================
-- Permissões
--============================================================
function SE.Admin.IsAllowed(src)
  if not src or src == 0 then return true end -- console

  -- preferir bridge (granular: ACE + staff meta + job/grade + legacy)
  if B and B.CanAdmin then
    return B.CanAdmin(src) == true
  end

  -- fallback mínimo (não recomendado, mas não quebra)
  if Config and Config.Permissions and Config.Permissions.Ace and IsPlayerAceAllowed(src, Config.Permissions.Ace) then
    return true
  end

  local pd = U.GetPlayerDataSafe(src)
  if not pd then return false end

  if Config and Config.Permissions and Config.Permissions.AllowStaffMeta and pd.metadata and pd.metadata.isstaff then
    return true
  end

  local jobs = (Config and Config.Permissions and Config.Permissions.Jobs) or {}
  if pd.job and jobs[pd.job.name] then
    local req = jobs[pd.job.name]
    local grade = 0
    if type(pd.job.grade) == 'table' then
      grade = tonumber(pd.job.grade.level or pd.job.grade.grade or 0) or 0
    else
      grade = tonumber(pd.job.grade or 0) or 0
    end
    if grade >= (req.minGrade or 0) then return true end
  end

  return false
end

--============================================================
-- Helpers (settings)
--============================================================
local function deepMerge(dst, src)
  if type(dst) ~= 'table' then dst = {} end
  if type(src) ~= 'table' then return dst end

  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      dst[k] = deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end

  return dst
end

local function ensureSettingsShape(t)
  if type(t) ~= 'table' then t = {} end
  t.mode = type(t.mode) == 'table' and t.mode or {}
  t.manual = type(t.manual) == 'table' and t.manual or {}
  t.ui = type(t.ui) == 'table' and t.ui or {}
  return t
end

-- aceita tanto "1.0" quanto "100" (percentual)
local function normalizeMultiplier(v)
  v = U.toNumber(v, nil)
  if v == nil then return nil end
  if v > 10 then v = v / 100 end -- 100 => 1.0
  return U.clamp(v, 0.10, 5.00)
end

local function normalizeInflation(v)
  v = U.toNumber(v, nil)
  if v == nil then return nil end
  if v > 10 then v = v / 100 end -- segurança
  local minR = (Config and Config.Inflation and Config.Inflation.MinRate) or 0.80
  local maxR = (Config and Config.Inflation and Config.Inflation.MaxRate) or 1.50
  return U.clamp(v, minR, maxR)
end

--============================================================
-- Admin: Metrics/State
--============================================================
local function fetchDebtTotals()
  local ok, row = pcall(function()
    return MySQL.single.await([[
      SELECT COALESCE(SUM(amount),0) AS total,
             COALESCE(COUNT(DISTINCT citizenid),0) AS debtors
      FROM space_economy_debts
      WHERE status = 'active'
    ]])
  end)
  if not ok or not row then return 0, 0 end
  return U.toInt(row.total, 0), U.toInt(row.debtors, 0)
end

local function fetchTodayMetrics()
  -- Se você tiver tabela diária (futuro), plugamos aqui.
  -- Por enquanto, retorna 0 sem quebrar.
  return 0, 0, 0 -- todayCollected, washToday, opsToday
end

function SE.Admin.GetStatePayload()
  local vault = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or U.toInt(S.vaultBalance, 0)
  local debtsTotal, debtors = fetchDebtTotals()
  local todayCollected, washToday, opsToday = fetchTodayMetrics()

  local settings = ensureSettingsShape(S.settings or {})

  -- Mantém compat com NUI:
  -- inflation = rate (1.00)
  -- taxrate = % (100.0 = neutro)
  local metrics = {
    vault = vault,
    inflation = U.toNumber(S.inflationRate, 1.0),
    taxrate = U.toNumber(S.taxMultiplier, 1.0) * 100.0,
    today = U.toInt(todayCollected, 0),
    debtsTotal = debtsTotal,
    debtors = debtors,
    washToday = U.toInt(washToday, 0),
    opsToday = U.toInt(opsToday, 0),
  }

  return {
    metrics = metrics,
    settings = settings,
    taxCatalog = settings.taxCatalog or nil
  }
end

--============================================================
-- Admin: Apply/Save Settings
-- payload pode ser:
--  - novo: { mode={}, manual={}, ui={} }
--  - legado: { taxMultiplier=, inflationRate=, settings={} }
--============================================================
function SE.Admin.ApplySettings(payload)
  payload = payload or {}

  -- base atual
  local current = ensureSettingsShape(S.settings or {})

  -- legado (se vier)
  if payload.settings and type(payload.settings) == 'table' then
    current = deepMerge(current, payload.settings)
  end

  -- novo formato (se vier direto)
  current = deepMerge(current, payload)
  current = ensureSettingsShape(current)

  -- aplica manual (se modo manual)
  local inflMode = tostring(current.mode.inflation or 'auto'):lower()
  local taxMode  = tostring(current.mode.taxrate or 'auto'):lower()

  if inflMode == 'manual' then
    local infl = normalizeInflation(current.manual.inflation)
    if infl and SE.Server and SE.Server.SetInflationRate then
      SE.Server.SetInflationRate(infl)
    else
      -- fallback
      S.inflationRate = infl or S.inflationRate
    end
  end

  if taxMode == 'manual' then
    local mult = normalizeMultiplier(current.manual.taxrate)
    if mult and SE.Server and SE.Server.SetTaxMultiplier then
      SE.Server.SetTaxMultiplier(mult)
    else
      S.taxMultiplier = mult or S.taxMultiplier
    end
  end

  -- compat legado direto
  if payload.inflationRate ~= nil then
    local infl = normalizeInflation(payload.inflationRate)
    if infl and SE.Server and SE.Server.SetInflationRate then
      SE.Server.SetInflationRate(infl)
    else
      S.inflationRate = infl or S.inflationRate
    end
  end

  if payload.taxMultiplier ~= nil then
    local mult = normalizeMultiplier(payload.taxMultiplier)
    if mult and SE.Server and SE.Server.SetTaxMultiplier then
      SE.Server.SetTaxMultiplier(mult)
    else
      S.taxMultiplier = mult or S.taxMultiplier
    end
  end

  -- salva settings
  S.settings = current

  if SE.Server and SE.Server.MarkDirty then
    SE.Server.MarkDirty()
  else
    S.dirty = true
  end

  return true
end

--============================================================
-- Admin: Logs
--============================================================
function SE.Admin.FetchLogs(limit)
  limit = U.toInt(limit or 80, 80)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end

  local ok, rows = pcall(function()
    return MySQL.query.await([[
      SELECT timestamp, category, message
      FROM space_economy_logs
      ORDER BY id DESC
      LIMIT ?
    ]], { limit })
  end)

  if not ok or type(rows) ~= 'table' then
    return {}
  end

  return rows
end

--============================================================
-- Admin: Cofre
--============================================================
function SE.Admin.ViewVault()
  if SE.Treasury and SE.Treasury.GetBalance then
    return SE.Treasury.GetBalance()
  end
  return U.toInt(S.vaultBalance, 0)
end

function SE.Admin.AddVault(amount, reason, meta)
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'Valor inválido.' end
  if not (SE.Treasury and SE.Treasury.Deposit) then
    return false, 'Tesouro indisponível.'
  end
  local bal = SE.Treasury.Deposit(amount, reason or 'admin_deposito', meta)
  return true, bal
end

function SE.Admin.WithdrawVault(amount, reason, meta)
  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'Valor inválido.' end
  if not (SE.Treasury and SE.Treasury.Withdraw) then
    return false, 'Tesouro indisponível.'
  end
  local bal = SE.Treasury.Withdraw(amount, reason or 'admin_saque', meta)
  return true, bal
end

--============================================================
-- Admin: Dívidas / Cobrança
--============================================================
function SE.Admin.ListDebts(limit)
  if not SE.Debts or not SE.Debts.ListActive then return {} end
  return SE.Debts.ListActive(limit or 150)
end

function SE.Admin.GetDebtById(id)
  if not SE.Debts or not SE.Debts.GetById then return nil end
  return SE.Debts.GetById(id)
end

function SE.Admin.GetDebtsByCitizen(citizenid, limit)
  if not SE.Debts or not SE.Debts.GetActiveByCitizen then return {} end
  return SE.Debts.GetActiveByCitizen(citizenid, limit or 50)
end

-- Lançar dívida/imposto via painel (corrigido concat "..")
function SE.Admin.IssueTaxDebt(src, payload)
  if not SE.Debts or not SE.Debts.Upsert then
    return false, 'Módulo de dívidas indisponível.'
  end

  payload = payload or {}
  local mode = tostring(payload.targetMode or 'citizenid')
  local citizenid = tostring(payload.citizenid or '')
  local amount = U.toInt(payload.amount, 0)
  local reason = tostring(payload.reason or payload.type or 'Imposto')

  if amount <= 0 then
    return false, 'Valor inválido.'
  end

  local now = U.now()
  local dueTs = now -- vencimento imediato por padrão

  local meta = {
    issued_by = src and tonumber(src) or 0,
    issued_by_name = (src and B and B.GetCharName and B.GetCharName(src)) or 'Console',
    tax_type = tostring(payload.type or 'OUTRO'),
    base = U.toInt(payload.base or 0, 0),
    created_ts = now,
  }

  if mode == 'all_online' then
    local count = 0
    for _, s in ipairs(GetPlayers()) do
      local cid = (B and B.GetCitizenId and B.GetCitizenId(tonumber(s))) or nil
      if cid then
        SE.Debts.Upsert(cid, amount, reason, dueTs, meta)
        count = count + 1
      end
    end
    return true, ('Lançado para %d jogadores online.'):format(count)
  end

  if citizenid == '' then
    return false, 'Informe o CitizenID.'
  end

  SE.Debts.Upsert(citizenid, amount, reason, dueTs, meta)
  return true, ('Dívida lançada para %s'):format(citizenid)
end
