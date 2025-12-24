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
-- MANDADOS / DISPATCH (ps-dispatch / ps-mdt) - REESCRITO
--============================================================

local function vec3FromCfg(v)
  if type(v) == 'vector3' then return v end
  if type(v) == 'table' then
    local x = tonumber(v.x or v[1]) or 0.0
    local y = tonumber(v.y or v[2]) or 0.0
    local z = tonumber(v.z or v[3]) or 0.0
    return vector3(x, y, z)
  end
  return vector3(0.0, 0.0, 0.0)
end

local function FindOnlineSrcByCitizenId(citizenid)
  if not citizenid or citizenid == '' then return nil end
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    if src then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid == citizenid then
        return src
      end
    end
  end
  return nil
end

local function GetPlayerCoordsSafe(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end

  local ok, coords = pcall(function()
    return GetEntityCoords(ped)
  end)

  if ok and coords then
    return vector3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0)
  end
  return nil
end

local function SendPsDispatchAlert(data)
  if GetResourceState('ps-dispatch') ~= 'started' then
    return false, 'ps_dispatch_not_started'
  end

  -- Preferência: handler oficial do ps-dispatch (server)
  -- (é o caminho mais compatível entre forks/versões) :contentReference[oaicite:1]{index=1}
  local ok = pcall(function()
    TriggerEvent('dispatch:server:notify', data)
  end)

  if ok then return true end

  -- Fallback extra: tenta CustomAlert se existir no SERVER nessa build
  if exports['ps-dispatch'] and type(exports['ps-dispatch'].CustomAlert) == 'function' then
    local ok2 = pcall(function()
      exports['ps-dispatch']:CustomAlert({
        coords       = data._coords or vector3(data.origin.x, data.origin.y, data.origin.z),
        message      = data.dispatchMessage,
        dispatchCode = data.dispatchCode,
        description  = data.description or data.firstStreet,
        radius       = 0,
        sprite       = data.blipSprite,
        color        = data.blipColour,
        scale        = data.blipScale,
        length       = data.blipLength,
        recipientList= data.job,
      })
    end)
    if ok2 then return true end
  end

  return false, 'ps_dispatch_failed'
end

function SE.Integrations.EmitWarrantIfNeeded(debt)
  if not debt then return false end

  local cfg = Config.WarrantAlert or {}
  if not cfg.Enabled then return false end

  local days = (Config.DebtSystem and Config.DebtSystem.WarrantAfterDaysOverdue) or 7
  if not debt.due_at then return false end

  -- Parse ISO "YYYY-MM-DD" (compat simples)
  local dueTs = 0
  if type(debt.due_at) == 'string' then
    local year, month, day = debt.due_at:match('(%d+)-(%d+)-(%d+)')
    if year then
      dueTs = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=0, min=0, sec=0})
    end
  end
  if dueTs == 0 then return false end

  local now = os.time()
  local overdueDays = math.floor((now - dueTs) / (24 * 60 * 60))
  if overdueDays < days then return false end

  --==========================================================
  -- ps-dispatch
  --==========================================================
  if cfg.UsePsDispatch and GetResourceState('ps-dispatch') == 'started' then
    local jobs = cfg.Jobs or cfg.RecipientList or {'police'} -- compat com seus configs

    -- tenta usar coords do cidadão se ele estiver online
    local onlineSrc = FindOnlineSrcByCitizenId(debt.citizenid)
    local coords = onlineSrc and GetPlayerCoordsSafe(onlineSrc) or nil

    -- fallback: coordenada default configurável
    if not coords then
      coords = vec3FromCfg(cfg.DefaultCoords or cfg.DefaultDispatchCoords or { x = 0.0, y = 0.0, z = 0.0 })
    end

    local amount = U.toInt(debt.amount, 0)
    local reason = tostring(debt.reason or '')
    local title  = cfg.Title or 'Dívida Ativa'
    local msg    = cfg.Message or 'Cidadão com dívida ativa'

    local payload = {
      -- obrigatório pro handler do ps-dispatch:
      dispatchcodename = cfg.DispatchCodeName or 'spaceeconomy_warrant', -- se você cadastrar no sv_dispatchcodes.lua, melhor
      dispatchCode     = cfg.DispatchCode or '10-90',
      firstStreet      = title,
      priority         = cfg.Priority or 2,
      origin           = { x = coords.x, y = coords.y, z = coords.z },
      dispatchMessage  = msg,

      -- extras (aparecem em MDT/dispatch dependendo da build):
      description      = ('%s | Dívida: $%d | CID: %s | %s'):format(title, amount, tostring(debt.citizenid or ''), reason),
      name             = tostring(debt.citizenid or ''),
      callsign         = 'Fiscal',

      -- lista de jobs (ps-dispatch usa "job" no notify) :contentReference[oaicite:2]{index=2}
      job              = jobs,

      -- blip info (seu sv_dispatchcodes.lua pode sobrescrever isso):
      blipSprite       = cfg.Sprite or 457,
      blipColour       = cfg.Color or 1,
      blipScale        = cfg.Scale or 1.0,
      blipLength       = cfg.Length or 3,

      -- guardamos coords pra fallback CustomAlert:
      _coords           = coords,
    }

    local okSend, errSend = SendPsDispatchAlert(payload)
    if okSend then
      dbg('Mandado emitido via ps-dispatch para:', debt.citizenid, 'coords:', coords.x, coords.y, coords.z)
      return true
    end

    dbg('Falha ao emitir mandado via ps-dispatch:', errSend or 'unknown')
    -- não retorna ainda: deixa tentar ps-mdt abaixo, se habilitado
  end

  --==========================================================
  -- ps-mdt (criar report)
  --==========================================================
  if cfg.UsePsMdt and GetResourceState('ps-mdt') == 'started' then
    pcall(function()
      exports['ps-mdt']:NewReport({
        author = 'Sistema Fiscal',
        title = cfg.Title or 'Dívida Ativa',
        description = ('%s\nValor: $%d\nCitizenID: %s\nMotivo: %s'):format(
          cfg.Message or '',
          U.toInt(debt.amount, 0),
          tostring(debt.citizenid or ''),
          tostring(debt.reason or '')
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
  fromSrc = tonumber(fromSrc)
  if not fromSrc or fromSrc <= 0 then return false, 'invalid_source' end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  reason = reason or 'Transferência'

  --==========================================================
  -- ps-banking (CORRETO): não existe export "Transfer".
  -- Aqui: debita do player (framework) e credita na conta society do ps-banking.
  --==========================================================
  if GetResourceState('ps-banking') == 'started' and exports['ps-banking'] then
    local holder = toAccount

    -- Aceita passar ID numérico (conta por id) OU holder string (ex: "police")
    local toId = tonumber(toAccount)
    if toId then
      local okAcc, acc = pcall(function()
        return exports['ps-banking']:GetAccountById(toId)
      end)
      if okAcc and acc and acc.holder then
        holder = acc.holder
      else
        return false, 'invalid_target_account'
      end
    else
      holder = tostring(holder or '')
      if holder == '' then return false, 'invalid_target_account' end
    end

    -- 1) Debita do player (bank)
    local okRemove, errRemove = SE.Integrations.RemoveMoney(fromSrc, amount, 'bank')
    if not okRemove then
      return false, errRemove or 'could_not_debit_player'
    end

    -- 2) Credita no ps-banking (society account)
    local okAdd = false
    local okAddCall, addRes = pcall(function()
      return exports['ps-banking']:AddMoney(holder, amount, reason)
    end)
    okAdd = okAddCall and addRes == true

    if not okAdd then
      -- rollback: devolve ao player pra não sumir dinheiro
      SE.Integrations.AddMoney(fromSrc, amount, 'bank')
      return false, 'ps_banking_add_failed'
    end

    -- (Opcional) criar extrato “com motivo” no ps-banking para o player
    -- Observação: o ps-banking também pode logar automaticamente via logClient,
    -- então use isso só se você quiser MUITO o "reason" personalizado.
    pcall(function()
      exports['ps-banking']:CreateBankStatement(
        fromSrc,
        'bank',
        amount,
        (reason .. ' | destino=' .. holder),
        'withdraw',
        'bank'
      )
    end)

    dbg(('Transfer ps-banking OK: src %d -> %s ($%d)'):format(fromSrc, holder, amount))
    return true
  end

  --==========================================================
  -- qb-banking / qbx-banking (fallback genérico)
  --==========================================================
  local bankingRes =
    (GetResourceState('qb-banking') == 'started' and 'qb-banking')
    or (GetResourceState('qbx-banking') == 'started' and 'qbx-banking')
    or nil

  if bankingRes and exports[bankingRes] then
    -- IMPORTANTE: chamar export de forma segura (simulando ":")
    local ok, res = pcall(function()
      local ex = exports[bankingRes]
      if ex and ex.Transfer then
        return ex.Transfer(ex, fromSrc, toAccount, amount, reason)
      end
      return false
    end)

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
-- RESIDÊNCIAS / HOUSING (ps-housing / qb-houses / qbx-houses)
-- Base para IPTU e afins
--============================================================

local HousingDetected = nil

local function DetectHousing()
  if HousingDetected then return HousingDetected end

  if GetResourceState('ps-housing') == 'started' then
    HousingDetected = 'ps-housing'
    dbg('Housing detectado: ps-housing')
    return HousingDetected
  end

  if GetResourceState('qb-houses') == 'started' then
    HousingDetected = 'qb-houses'
    dbg('Housing detectado: qb-houses')
    return HousingDetected
  end

  if GetResourceState('qbx-houses') == 'started' then
    HousingDetected = 'qbx-houses'
    dbg('Housing detectado: qbx-houses')
    return HousingDetected
  end

  HousingDetected = 'none'
  dbg('Housing não detectado (nenhum recurso conhecido)')
  return HousingDetected
end

-- Pequeno helper pra query (oxmysql / MySQL.*)
local function dbFetchAll(sql, params)
  params = params or {}

  if MySQL and MySQL.query and MySQL.query.await then
    local ok, res = pcall(function()
      return MySQL.query.await(sql, params)
    end)
    if ok and res then return res end
  end

  if MySQL and MySQL.Sync and MySQL.Sync.fetchAll then
    local ok, res = pcall(function()
      return MySQL.Sync.fetchAll(sql, params)
    end)
    if ok and res then return res end
  end

  if exports and exports.oxmysql and exports.oxmysql.query_async then
    local ok, res = pcall(function()
      return exports.oxmysql:query_async(sql, params)
    end)
    if ok and res then return res end
  end

  -- mysql-async (callback) -> promise
  if MySQL and MySQL.Async and MySQL.Async.fetchAll then
    local p = promise.new()
    MySQL.Async.fetchAll(sql, params, function(res)
      p:resolve(res or {})
    end)
    local res = Citizen.Await(p)
    return res or {}
  end

  return nil
end

-- Resolve CitizenId a partir de src (se vier número)
function SE.Integrations.GetCitizenId(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end

  if B and B.GetCitizenId then
    local ok, cid = pcall(B.GetCitizenId, src)
    if ok and cid and cid ~= '' then return cid end
  end

  local framework = DetectFramework()

  if framework == 'qbx' and exports.qbx_core then
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData then
      return player.PlayerData.citizenid
    end
  end

  if framework == 'qbcore' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if ok and QBCore then
      local player = QBCore.Functions.GetPlayer(src)
      if player and player.PlayerData then
        return player.PlayerData.citizenid
      end
    end
  end

  return nil
end

local function normalizeCitizenId(cidOrSrc)
  if cidOrSrc == nil then return nil end

  if type(cidOrSrc) == 'number' then
    return SE.Integrations.GetCitizenId(cidOrSrc)
  end

  if type(cidOrSrc) == 'string' then
    -- se vier "123" é provável src; se vier "E9T4S24I" é citizenid
    if cidOrSrc:match('^%d+$') then
      return SE.Integrations.GetCitizenId(tonumber(cidOrSrc))
    end
    return cidOrSrc
  end

  return nil
end

-- Retorna lista de imóveis do cidadão:
-- { {id=..., street=..., region=..., price=..., apartment=...}, ... }
function SE.Integrations.GetResidences(cidOrSrc)
  local citizenid = normalizeCitizenId(cidOrSrc)
  if not citizenid or citizenid == '' then return {} end

  local housing = DetectHousing()

  --==========================================================
  -- ps-housing
  --==========================================================
  if housing == 'ps-housing' and exports['ps-housing'] then
    -- 1) Tenta pegar cache interno (PropertiesTable) se existir export
    if exports['ps-housing'].GetProperties then
      local ok, props = pcall(function()
        return exports['ps-housing']:GetProperties()
      end)

      if ok and type(props) == 'table' then
        local out = {}
        for _, v in pairs(props) do
          local pd = (type(v) == 'table' and v.propertyData) or v
          if pd and pd.owner == citizenid then
            out[#out+1] = {
              id = tostring(pd.property_id or ''),
              street = tostring(pd.street or ''),
              region = tostring(pd.region or ''),
              price = U.toInt(pd.price, 0),
              apartment = pd.apartment, -- pode ser label/string ou boolean dependendo da impl.
            }
          end
        end
        return out
      end
    end

    -- 2) Fallback DB (mesma fonte que o ps-housing usa pra carregar)
    local rows = dbFetchAll(
      'SELECT property_id, street, region, price, apartment FROM properties WHERE owner_citizenid = ?',
      { citizenid }
    ) or {}

    local out = {}
    for _, r in ipairs(rows) do
      out[#out+1] = {
        id = tostring(r.property_id or ''),
        street = tostring(r.street or ''),
        region = tostring(r.region or ''),
        price = U.toInt(r.price, 0),
        apartment = r.apartment,
      }
    end
    return out
  end

  --==========================================================
  -- qb-houses / qbx-houses (fallback por DB)
  --==========================================================
  if (housing == 'qb-houses' or housing == 'qbx-houses') then
    -- Tentativa “boa”: join com houselocations pra puxar preço/label.
    local rows = dbFetchAll([[
      SELECT
        ph.house as house,
        ph.citizenid as citizenid,
        hl.label as label,
        hl.price as price
      FROM player_houses ph
      LEFT JOIN houselocations hl ON hl.name = ph.house
      WHERE ph.citizenid = ?
    ]], { citizenid })

    if rows and type(rows) == 'table' then
      local out = {}
      for _, r in ipairs(rows) do
        out[#out+1] = {
          id = tostring(r.house or ''),
          street = tostring(r.label or ''),
          region = '',
          price = U.toInt(r.price, 0),
          apartment = false,
        }
      end
      return out
    end

    -- Fallback simples (sem preço)
    local rows2 = dbFetchAll('SELECT house FROM player_houses WHERE citizenid = ?', { citizenid }) or {}
    local out2 = {}
    for _, r in ipairs(rows2) do
      out2[#out2+1] = {
        id = tostring(r.house or ''),
        street = '',
        region = '',
        price = 0,
        apartment = false,
      }
    end
    return out2
  end

  return {}
end

-- Resumo (pra IPTU):
-- count, totalValue, e lista (opcional)
function SE.Integrations.GetResidenceSummary(cidOrSrc)
  local props = SE.Integrations.GetResidences(cidOrSrc)

  -- Se apartamento vier com price=0 no ps-housing, você pode dar um “valor mínimo” pra entrar no IPTU.
  -- Pode configurar em Config.Residences.ApartmentBaseValue, senão usa 50000.
  local aptBase = (Config.Residences and Config.Residences.ApartmentBaseValue) or 50000

  local total = 0
  for _, p in ipairs(props) do
    local v = U.toInt(p.price, 0)
    if v <= 0 and p.apartment then
      v = aptBase
    end
    total = total + v
  end

  return {
    count = #props,
    totalValue = total,
    properties = props
  }
end

-- Só a base numérica (pra cálculo rápido)
function SE.Integrations.GetResidenceTaxBase(cidOrSrc)
  local s = SE.Integrations.GetResidenceSummary(cidOrSrc)
  return U.toInt(s.totalValue, 0), U.toInt(s.count, 0)
end
--============================================================
-- GARAGENS / VEÍCULOS (rhd_garage + fallback DB)
-- Observação importante:
--   rhd_garage bloqueia TriggerEvent/TriggerServerEvent vindo de outro resource:
--   RegisterNetEvent("rhd_garage:server:updateState", ...) -> if GetInvokingResource() then return end
--   então aqui fazemos atualização por SQL (server-side) para funcionar offline também.
--============================================================

local GarageDetected = nil

local function DetectGarage()
  if GarageDetected then return GarageDetected end

  if GetResourceState('rhd_garage') == 'started' then
    GarageDetected = 'rhd_garage'
    dbg('Garagem detectada: rhd_garage')
    return GarageDetected
  end

  if GetResourceState('qb-garage') == 'started' then
    GarageDetected = 'qb-garage'
    dbg('Garagem detectada: qb-garage')
    return GarageDetected
  end

  if GetResourceState('qb-garages') == 'started' then
    GarageDetected = 'qb-garages'
    dbg('Garagem detectada: qb-garages')
    return GarageDetected
  end

  if GetResourceState('qbx-garages') == 'started' then
    GarageDetected = 'qbx-garages'
    dbg('Garagem detectada: qbx-garages')
    return GarageDetected
  end

  GarageDetected = 'none'
  dbg('Garagem não detectada (nenhum recurso conhecido)')
  return GarageDetected
end

local function normPlate(plate)
  if not plate then return nil end
  plate = tostring(plate)
  plate = plate:gsub('^%s*(.-)%s*$', '%1')
  if plate == '' then return nil end
  return plate:upper()
end

-- Exec helper (oxmysql / mysql-async / MySQL.*)
local function dbExec(sql, params)
  params = params or {}

  if MySQL and MySQL.update and MySQL.update.await then
    local ok, res = pcall(function()
      return MySQL.update.await(sql, params)
    end)
    if ok then return res end
  end

  if MySQL and MySQL.Sync and MySQL.Sync.execute then
    local ok, res = pcall(function()
      return MySQL.Sync.execute(sql, params)
    end)
    if ok then return res end
  end

  if exports and exports.oxmysql and exports.oxmysql.update_async then
    local ok, res = pcall(function()
      return exports.oxmysql:update_async(sql, params)
    end)
    if ok then return res end
  end

  if MySQL and MySQL.Async and MySQL.Async.execute then
    local p = promise.new()
    MySQL.Async.execute(sql, params, function(affected)
      p:resolve(affected or 0)
    end)
    return Citizen.Await(p) or 0
  end

  return 0
end

local function tryUpdate(sql, params)
  local ok, affected = pcall(function()
    return dbExec(sql, params)
  end)
  if not ok then return 0 end
  return tonumber(affected) or 0
end

--============================================================
-- OWNER por PLATE
--============================================================
function SE.Integrations.GetVehicleOwnerByPlate(plate)
  plate = normPlate(plate)
  if not plate then return nil end

  local framework = DetectFramework()

  -- QB/QBX padrão: player_vehicles (citizenid)
  if framework == 'qbcore' or framework == 'qbx' then
    local rows = dbFetchAll('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) or {}
    if rows[1] and rows[1].citizenid then
      return tostring(rows[1].citizenid)
    end
  end

  -- ESX padrão: owned_vehicles (owner/identifier)
  if framework == 'esx' then
    local rows = dbFetchAll('SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate }) or {}
    if rows[1] and rows[1].owner then
      return tostring(rows[1].owner)
    end
  end

  return nil
end

--============================================================
-- LISTA veículos do cidadão (para impostos, bloqueios, etc.)
-- Retorno: { {plate=, state=, garage=, model=, raw=}, ... }
--============================================================
function SE.Integrations.GetOwnedVehicles(cidOrSrc)
  local framework = DetectFramework()
  local out = {}

  if framework == 'qbcore' or framework == 'qbx' then
    local citizenid = normalizeCitizenId(cidOrSrc)
    if not citizenid or citizenid == '' then return {} end

    -- tenta pegar colunas comuns
    local rows = dbFetchAll([[
      SELECT plate, state, garage, vehicle
      FROM player_vehicles
      WHERE citizenid = ?
    ]], { citizenid })

    if not rows then
      -- fallback mínimo
      rows = dbFetchAll('SELECT plate, state, garage FROM player_vehicles WHERE citizenid = ?', { citizenid }) or {}
    end

    for _, r in ipairs(rows or {}) do
      out[#out+1] = {
        plate = normPlate(r.plate),
        state = U.toInt(r.state, 0),      -- 0=fora / 1=garagem / 2=impound (padrão QB)
        garage = tostring(r.garage or ''),
        model = nil,
        raw = r,
      }
    end

    return out
  end

  if framework == 'esx' then
    -- Se você quiser suportar ESX de verdade aqui, ideal é passar o identifier em cidOrSrc.
    local identifier = (type(cidOrSrc) == 'string' and cidOrSrc) or nil
    if not identifier or identifier == '' then return {} end

    local rows = dbFetchAll('SELECT plate, stored, vehicle FROM owned_vehicles WHERE owner = ?', { identifier }) or {}
    for _, r in ipairs(rows) do
      out[#out+1] = {
        plate = normPlate(r.plate),
        state = (U.toInt(r.stored, 0) == 1) and 1 or 0,
        garage = '',
        model = nil,
        raw = r,
      }
    end
    return out
  end

  return {}
end

--============================================================
-- SET estado do veículo por PLATE (server-side)
-- state (QB): 0 fora | 1 guardado | 2 impound
--============================================================
function SE.Integrations.SetVehicleStateByPlate(plate, state, garage)
  plate = normPlate(plate)
  if not plate then return false, 'invalid_plate' end

  state = U.toInt(state, -1)
  if state < 0 then return false, 'invalid_state' end

  garage = tostring(garage or '')

  local framework = DetectFramework()
  DetectGarage() -- só pra log/detecção

  -- QB/QBX: player_vehicles
  if framework == 'qbcore' or framework == 'qbx' then
    local affected = 0

    -- tenta com garage
    if garage ~= '' then
      affected = tryUpdate('UPDATE player_vehicles SET state = ?, garage = ? WHERE plate = ?', { state, garage, plate })
      if affected > 0 then return true end
    end

    -- fallback: só state
    affected = tryUpdate('UPDATE player_vehicles SET state = ? WHERE plate = ?', { state, plate })
    if affected > 0 then return true end

    return false, 'vehicle_not_found'
  end

  -- ESX: owned_vehicles (stored = 1/0). Impound normalmente é custom, então aqui só stored.
  if framework == 'esx' then
    local stored = (state == 1) and 1 or 0
    local affected = tryUpdate('UPDATE owned_vehicles SET stored = ? WHERE plate = ?', { stored, plate })
    if affected > 0 then return true end
    return false, 'vehicle_not_found'
  end

  return false, 'no_garage_integration'
end

--============================================================
-- IMPOUND / RELEASE helpers
--============================================================
function SE.Integrations.ImpoundVehicleByPlate(plate, impoundGarage)
  impoundGarage = impoundGarage or 'impound'
  return SE.Integrations.SetVehicleStateByPlate(plate, 2, impoundGarage)
end

function SE.Integrations.ReleaseVehicleByPlate(plate, targetGarage)
  targetGarage = targetGarage or 'pillbox' -- padrão qualquer; ajuste no seu Config se quiser
  return SE.Integrations.SetVehicleStateByPlate(plate, 1, targetGarage)
end
--============================================================
-- CONCESSIONÁRIA / VEHICLESHOP (rm-dealership / qb-vehicleshop / qbx-vehicleshop)
-- Base para IPVA e afins
--============================================================

local DealershipDetected = nil

local function DetectDealership()
  if DealershipDetected then return DealershipDetected end

  if GetResourceState('rm-dealership') == 'started' then
    DealershipDetected = 'rm-dealership'
    dbg('Concessionária detectada: rm-dealership')
    return DealershipDetected
  end

  if GetResourceState('qb-vehicleshop') == 'started' then
    DealershipDetected = 'qb-vehicleshop'
    dbg('Concessionária detectada: qb-vehicleshop')
    return DealershipDetected
  end

  if GetResourceState('qbx-vehicleshop') == 'started' then
    DealershipDetected = 'qbx-vehicleshop'
    dbg('Concessionária detectada: qbx-vehicleshop')
    return DealershipDetected
  end

  DealershipDetected = 'none'
  dbg('Concessionária não detectada (nenhum recurso conhecido)')
  return DealershipDetected
end

-- Helper: tenta pegar preço do veículo por model
-- Retorna: price (number), name (string|nil), source (string)
function SE.Integrations.GetVehiclePriceByModel(model)
  model = tostring(model or '')
  if model == '' then return 0, nil, 'invalid_model' end

  local dealership = DetectDealership()

  -- 1) rm-dealership por DB (dealership_vehicles)
  if dealership == 'rm-dealership' then
    local rows = dbFetchAll('SELECT price, name FROM dealership_vehicles WHERE model = ? LIMIT 1', { model })
    if rows and rows[1] then
      return U.toInt(rows[1].price, 0), rows[1].name, 'rm-dealership:dealership_vehicles'
    end
  end

  -- 2) Tenta Shared Vehicles do framework (quando existir)
  local framework = DetectFramework()

  if framework == 'qbcore' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if ok and QBCore and QBCore.Shared and QBCore.Shared.Vehicles then
      local v = QBCore.Shared.Vehicles[model]
      if v then
        return U.toInt(v.price, 0), (v.name or v.label), 'qbcore:shared_vehicles'
      end
    end
  end

  if framework == 'qbx' and exports.qbx_core then
    -- qbx pode variar; tenta alguns formatos comuns via pcall
    local ok, data = pcall(function()
      if exports.qbx_core.GetVehicleData then
        return exports.qbx_core:GetVehicleData(model)
      end
      if exports.qbx_core.GetVehiclesByName then
        return exports.qbx_core:GetVehiclesByName(model)
      end
      return nil
    end)
    if ok and type(data) == 'table' then
      return U.toInt(data.price, 0), (data.name or data.label), 'qbx:vehicle_data'
    end
  end

  -- 3) Fallback DB genérico (caso exista tabela "vehicles" ou similares)
  local tryTables = {
    { sql = 'SELECT price, name FROM vehicles WHERE model = ? LIMIT 1', tag = 'db:vehicles' },
    { sql = 'SELECT price, name FROM vehicle_shop WHERE model = ? LIMIT 1', tag = 'db:vehicle_shop' },
    { sql = 'SELECT price, name FROM dealership_vehicles WHERE model = ? LIMIT 1', tag = 'db:dealership_vehicles' },
  }

  for _, t in ipairs(tryTables) do
    local rows = dbFetchAll(t.sql, { model })
    if rows and rows[1] then
      return U.toInt(rows[1].price, 0), rows[1].name, t.tag
    end
  end

  return 0, nil, 'not_found'
end

-- Lista veículos do cidadão:
-- { {plate=..., model=..., name=..., price=..., garage=..., state=...}, ... }
function SE.Integrations.GetVehicles(cidOrSrc)
  local citizenid = normalizeCitizenId(cidOrSrc)
  if not citizenid or citizenid == '' then return {} end

  local dealership = DetectDealership()
  local out = {}

  -- QBCore/QBX padrão: player_vehicles
  -- rm-dealership registra compra em player_vehicles (vehicle=model) e mantém preços em dealership_vehicles:contentReference[oaicite:3]{index=3}:contentReference[oaicite:4]{index=4}
  if dealership == 'rm-dealership' then
    local rows = dbFetchAll([[
      SELECT
        pv.plate,
        pv.vehicle as model,
        pv.garage,
        pv.state,
        dv.price,
        dv.name
      FROM player_vehicles pv
      LEFT JOIN dealership_vehicles dv ON dv.model = pv.vehicle
      WHERE pv.citizenid = ?
    ]], { citizenid }) or {}

    for _, r in ipairs(rows) do
      out[#out+1] = {
        plate  = tostring(r.plate or ''),
        model  = tostring(r.model or ''),
        name   = r.name,
        price  = U.toInt(r.price, 0),
        garage = tostring(r.garage or ''),
        state  = U.toInt(r.state, 0),
      }
    end

    return out
  end

  -- Fallback genérico: só player_vehicles, e resolve preço por model (Shared/DB)
  local rows = dbFetchAll([[
    SELECT plate, vehicle as model, garage, state
    FROM player_vehicles
    WHERE citizenid = ?
  ]], { citizenid }) or {}

  for _, r in ipairs(rows) do
    local model = tostring(r.model or '')
    local price, name = SE.Integrations.GetVehiclePriceByModel(model)
    out[#out+1] = {
      plate  = tostring(r.plate or ''),
      model  = model,
      name   = name,
      price  = U.toInt(price, 0),
      garage = tostring(r.garage or ''),
      state  = U.toInt(r.state, 0),
    }
  end

  return out
end

-- Resumo (pra IPVA):
-- count, totalValue, e lista (opcional)
function SE.Integrations.GetVehicleSummary(cidOrSrc)
  local vehicles = SE.Integrations.GetVehicles(cidOrSrc)

  -- se algum preço vier 0, pode usar “base mínima”
  local baseMin = (Config.Vehicles and Config.Vehicles.BaseValueIfUnknown) or 25000

  local total = 0
  for _, v in ipairs(vehicles) do
    local p = U.toInt(v.price, 0)
    if p <= 0 then p = baseMin end
    total = total + p
  end

  return {
    count = #vehicles,
    totalValue = total,
    vehicles = vehicles
  }
end

-- Só a base numérica (pra cálculo rápido)
function SE.Integrations.GetVehicleTaxBase(cidOrSrc)
  local s = SE.Integrations.GetVehicleSummary(cidOrSrc)
  return U.toInt(s.totalValue, 0), U.toInt(s.count, 0)
end
--============================================================
-- CONTRATAÇÕES / MANAGEMENT (boss + gang)
-- Suporta: online (SetJob/SetGang) e offline (DB)
-- QB-Core: players.job / players.gang (JSON)
-- QBX/Qbox: player_groups (type='job'/'gang') + fallback players.job/gang
--============================================================

local QBCoreCached = nil
local function GetQBCore()
  if QBCoreCached then return QBCoreCached end
  if exports and exports['qb-core'] and exports['qb-core'].GetCoreObject then
    local ok, core = pcall(exports['qb-core'].GetCoreObject)
    if ok and core then QBCoreCached = core end
  end
  return QBCoreCached
end

local function dbExec(sql, params)
  params = params or {}

  if MySQL and MySQL.update and MySQL.update.await then
    local ok, res = pcall(function()
      return MySQL.update.await(sql, params)
    end)
    if ok then return res end
  end

  if MySQL and MySQL.Sync and MySQL.Sync.execute then
    local ok, res = pcall(function()
      return MySQL.Sync.execute(sql, params)
    end)
    if ok then return res end
  end

  if exports and exports.oxmysql and exports.oxmysql.update_async then
    local ok, res = pcall(function()
      return exports.oxmysql:update_async(sql, params)
    end)
    if ok then return res end
  end

  if MySQL and MySQL.Async and MySQL.Async.execute then
    local p = promise.new()
    MySQL.Async.execute(sql, params, function(res)
      p:resolve(res)
    end)
    return Citizen.Await(p)
  end

  return nil
end

local function formatName(charinfo)
  if type(charinfo) == 'string' then
    local ok, decoded = pcall(json.decode, charinfo)
    if ok then charinfo = decoded end
  end
  charinfo = charinfo or {}
  local fn = tostring(charinfo.firstname or charinfo.firstName or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local ln = tostring(charinfo.lastname  or charinfo.lastName  or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local full = (fn .. ' ' .. ln):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if full == '' then full = 'Desconhecido' end
  return full
end

local function getPlayerByCitizenId(cid)
  local core = GetQBCore()
  if core and core.Functions and core.Functions.GetPlayerByCitizenId then
    return core.Functions.GetPlayerByCitizenId(cid)
  end
  return nil
end

local function getPlayer(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end

  local fw = DetectFramework()

  if fw == 'qbx' and exports.qbx_core and exports.qbx_core.GetPlayer then
    local p = exports.qbx_core:GetPlayer(src)
    return p
  end

  local core = GetQBCore()
  if core and core.Functions and core.Functions.GetPlayer then
    return core.Functions.GetPlayer(src)
  end

  return nil
end

local function upsertPlayerGroup(citizenid, groupType, groupName, grade)
  -- Qbox/QBX: player_groups(citizenid, `group`, type, grade)
  if not citizenid or citizenid == '' then return false end
  groupType = tostring(groupType or '')
  groupName = tostring(groupName or '')
  grade = tonumber(grade) or 0
  if groupType == '' or groupName == '' then return false end

  -- remove antigo do mesmo tipo e seta novo
  pcall(function()
    dbExec('DELETE FROM player_groups WHERE citizenid = ? AND type = ?', { citizenid, groupType })
  end)
  local res = dbExec('INSERT INTO player_groups (citizenid, `group`, type, grade) VALUES (?, ?, ?, ?)', {
    citizenid, groupName, groupType, grade
  })
  return res ~= nil
end

local function buildJobObject(jobName, gradeLevel)
  local core = GetQBCore()
  if not core or not core.Shared or not core.Shared.Jobs then return nil, 'no_job_defs' end

  jobName = tostring(jobName or '')
  gradeLevel = tonumber(gradeLevel) or 0

  local def = core.Shared.Jobs[jobName]
  if not def or not def.grades then return nil, 'invalid_job' end

  local gkey = tostring(gradeLevel)
  local gdef = def.grades[gkey]
  if not gdef then return nil, 'invalid_grade' end

  local payment = tonumber(gdef.payment or def.payment or 0) or 0
  local isboss  = (gdef.isboss == true)

  local job = {
    name   = jobName,
    label  = def.label or jobName,
    type   = def.type or 'job',
    onduty = true,
    isboss = isboss,
    payment = payment,
    grade = {
      name    = gdef.name or gkey,
      level   = gradeLevel,
      payment = payment,
      isboss  = isboss,
    }
  }

  return job
end

local function buildGangObject(gangName, gradeLevel)
  local core = GetQBCore()
  if not core or not core.Shared or not core.Shared.Gangs then return nil, 'no_gang_defs' end

  gangName = tostring(gangName or '')
  gradeLevel = tonumber(gradeLevel) or 0

  local def = core.Shared.Gangs[gangName]
  if not def or not def.grades then return nil, 'invalid_gang' end

  local gkey = tostring(gradeLevel)
  local gdef = def.grades[gkey]
  if not gdef then return nil, 'invalid_grade' end

  local isboss = (gdef.isboss == true)

  local gang = {
    name   = gangName,
    label  = def.label or gangName,
    isboss = isboss,
    grade  = {
      level   = gradeLevel,
      name    = gdef.name or gkey,
      payment = tonumber(gdef.payment or 0) or 0,
    }
  }

  return gang
end

local function setJobOffline(citizenid, jobName, gradeLevel)
  local job, err = buildJobObject(jobName, gradeLevel)
  if not job then return false, err end

  -- Atualiza players.job (QBCore compat / seu bossmenu faz assim também)
  local ok = pcall(function()
    dbExec('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(job), citizenid })
  end)

  -- Atualiza player_groups (QBX/Qbox)
  pcall(function()
    upsertPlayerGroup(citizenid, 'job', jobName, gradeLevel)
  end)

  return ok
end

local function setGangOffline(citizenid, gangName, gradeLevel)
  local gang, err = buildGangObject(gangName, gradeLevel)
  if not gang then return false, err end

  local ok = pcall(function()
    dbExec('UPDATE players SET gang = ? WHERE citizenid = ?', { json.encode(gang), citizenid })
  end)

  pcall(function()
    upsertPlayerGroup(citizenid, 'gang', gangName, gradeLevel)
  end)

  return ok
end

local function isBoss(src, kind, expectedName)
  local P = getPlayer(src)
  if not P or not P.PlayerData then return false end

  kind = kind or 'job'
  if kind == 'gang' then
    local g = P.PlayerData.gang
    if not g or not g.name then return false end
    if expectedName and g.name ~= expectedName then return false end
    return g.isboss == true or (g.grade and g.grade.isboss == true)
  end

  local j = P.PlayerData.job
  if not j or not j.name then return false end
  if expectedName and j.name ~= expectedName then return false end
  return j.isboss == true or (j.grade and j.grade.isboss == true)
end

--============================================================
-- API PRINCIPAL (Jobs)
--============================================================

function SE.Integrations.SetJob(targetCidOrSrc, jobName, gradeLevel)
  local citizenid = normalizeCitizenId(targetCidOrSrc)
  if not citizenid then return false, 'invalid_target' end
  jobName = tostring(jobName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  local online = getPlayerByCitizenId(citizenid)
  if online and online.Functions and online.Functions.SetJob then
    local ok = pcall(function()
      online.Functions.SetJob(jobName, gradeLevel)
    end)
    if ok then
      -- também sincroniza player_groups no Qbox (não atrapalha qb-core)
      pcall(function() upsertPlayerGroup(citizenid, 'job', jobName, gradeLevel) end)
      return true
    end
  end

  local ok2, err2 = setJobOffline(citizenid, jobName, gradeLevel)
  if ok2 then return true end
  return false, err2 or 'set_job_failed'
end

function SE.Integrations.HireEmployee(bossSrc, targetSrc, jobName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  targetSrc = tonumber(targetSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end
  if not targetSrc or targetSrc <= 0 then return false, 'invalid_target' end

  jobName = tostring(jobName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  -- permissão: boss do job
  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end

  local targetCid = SE.Integrations.GetCitizenId(targetSrc)
  if not targetCid then return false, 'target_no_citizenid' end

  return SE.Integrations.SetJob(targetCid, jobName, gradeLevel)
end

function SE.Integrations.SetEmployeeGrade(bossSrc, targetCidOrSrc, jobName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  jobName = tostring(jobName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  return SE.Integrations.SetJob(cid, jobName, gradeLevel)
end

function SE.Integrations.FireEmployee(bossSrc, targetCidOrSrc, unemployedJob, unemployedGrade)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  local bossP = getPlayer(bossSrc)
  local jobName = bossP and bossP.PlayerData and bossP.PlayerData.job and bossP.PlayerData.job.name or nil
  if not jobName then return false, 'boss_no_job' end

  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  unemployedJob = unemployedJob or 'unemployed'
  unemployedGrade = tonumber(unemployedGrade) or 0
  return SE.Integrations.SetJob(cid, unemployedJob, unemployedGrade)
end

-- Lista funcionários (útil p/ relatórios / impostos / auditoria)
function SE.Integrations.GetJobEmployees(jobName, viewerCidOrSrc)
  jobName = tostring(jobName or '')
  if jobName == '' then return {} end

  local viewerCid = normalizeCitizenId(viewerCidOrSrc)
  local out = {}

  -- Qbox: player_groups primeiro (mais “correto”)
  local rows = dbFetchAll([[
    SELECT pg.citizenid, pg.grade, p.charinfo
    FROM player_groups pg
    LEFT JOIN players p ON p.citizenid = pg.citizenid
    WHERE pg.type = 'job' AND pg.`group` = ?
  ]], { jobName })

  local core = GetQBCore()
  local grades = core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName] and core.Shared.Jobs[jobName].grades or {}

  if rows and type(rows) == 'table' and #rows > 0 then
    for _, r in ipairs(rows) do
      local cid = r.citizenid
      local online = getPlayerByCitizenId(cid)
      local gradeLevel = tonumber(r.grade) or 0
      local gdef = grades[tostring(gradeLevel)] or {}
      out[#out+1] = {
        citizenid = cid,
        name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
        grade = { level = gradeLevel, name = gdef.name or tostring(gradeLevel), isboss = gdef.isboss == true },
        isboss = (gdef.isboss == true),
        online = online ~= nil,
        source = online and online.PlayerData and online.PlayerData.source or nil,
        isSelf = (viewerCid ~= nil and cid == viewerCid)
      }
    end
    table.sort(out, function(a,b) return (a.grade.level or 0) > (b.grade.level or 0) end)
    return out
  end

  -- Fallback QB: procurar no JSON players.job (igual seu bossmenu faz)【sv_boss.lua†L11-L48】
  local rows2 = dbFetchAll("SELECT citizenid, charinfo, job FROM players WHERE job LIKE ?", { '%' .. jobName .. '%' }) or {}
  for _, r in ipairs(rows2) do
    local jobObj = {}
    if r.job then
      local ok, decoded = pcall(json.decode, r.job)
      if ok and decoded then jobObj = decoded end
    end
    if jobObj and jobObj.name == jobName then
      local cid = r.citizenid
      local online = getPlayerByCitizenId(cid)
      out[#out+1] = {
        citizenid = cid,
        name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
        grade = jobObj.grade or {},
        isboss = jobObj.isboss == true,
        online = online ~= nil,
        source = online and online.PlayerData and online.PlayerData.source or nil,
        isSelf = (viewerCid ~= nil and cid == viewerCid)
      }
    end
  end

  table.sort(out, function(a,b)
    local ga = (a.grade and (a.grade.level or a.grade.grade or 0)) or 0
    local gb = (b.grade and (b.grade.level or b.grade.grade or 0)) or 0
    return ga > gb
  end)

  return out
end

--============================================================
-- API (Gangs)
--============================================================

function SE.Integrations.SetGang(targetCidOrSrc, gangName, gradeLevel)
  local citizenid = normalizeCitizenId(targetCidOrSrc)
  if not citizenid then return false, 'invalid_target' end
  gangName = tostring(gangName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  local online = getPlayerByCitizenId(citizenid)
  if online and online.Functions and online.Functions.SetGang then
    local ok = pcall(function()
      online.Functions.SetGang(gangName, gradeLevel)
    end)
    if ok then
      pcall(function() upsertPlayerGroup(citizenid, 'gang', gangName, gradeLevel) end)
      return true
    end
  end

  local ok2, err2 = setGangOffline(citizenid, gangName, gradeLevel)
  if ok2 then return true end
  return false, err2 or 'set_gang_failed'
end

function SE.Integrations.HireGangMember(bossSrc, targetSrc, gangName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  targetSrc = tonumber(targetSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end
  if not targetSrc or targetSrc <= 0 then return false, 'invalid_target' end

  gangName = tostring(gangName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end

  local targetCid = SE.Integrations.GetCitizenId(targetSrc)
  if not targetCid then return false, 'target_no_citizenid' end

  return SE.Integrations.SetGang(targetCid, gangName, gradeLevel)
end

function SE.Integrations.SetGangGrade(bossSrc, targetCidOrSrc, gangName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  gangName = tostring(gangName or '')
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  return SE.Integrations.SetGang(cid, gangName, gradeLevel)
end

function SE.Integrations.FireGangMember(bossSrc, targetCidOrSrc, defaultGang, defaultGrade)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  local bossP = getPlayer(bossSrc)
  local gangName = bossP and bossP.PlayerData and bossP.PlayerData.gang and bossP.PlayerData.gang.name or nil
  if not gangName then return false, 'boss_no_gang' end

  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  defaultGang = defaultGang or 'none'
  defaultGrade = tonumber(defaultGrade) or 0
  return SE.Integrations.SetGang(cid, defaultGang, defaultGrade)
end

function SE.Integrations.GetGangMembers(gangName, viewerCidOrSrc)
  gangName = tostring(gangName or '')
  if gangName == '' then return {} end

  local viewerCid = normalizeCitizenId(viewerCidOrSrc)
  local out = {}

  -- Qbox: player_groups
  local rows = dbFetchAll([[
    SELECT pg.citizenid, pg.grade, p.charinfo
    FROM player_groups pg
    LEFT JOIN players p ON p.citizenid = pg.citizenid
    WHERE pg.type = 'gang' AND pg.`group` = ?
  ]], { gangName })

  local core = GetQBCore()
  local grades = core and core.Shared and core.Shared.Gangs and core.Shared.Gangs[gangName] and core.Shared.Gangs[gangName].grades or {}

  if rows and type(rows) == 'table' and #rows > 0 then
    for _, r in ipairs(rows) do
      local cid = r.citizenid
      local online = getPlayerByCitizenId(cid)
      local gradeLevel = tonumber(r.grade) or 0
      local gdef = grades[tostring(gradeLevel)] or {}
      out[#out+1] = {
        citizenid = cid,
        name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
        grade = { level = gradeLevel, name = gdef.name or tostring(gradeLevel), isboss = gdef.isboss == true },
        isboss = (gdef.isboss == true),
        online = online ~= nil,
        source = online and online.PlayerData and online.PlayerData.source or nil,
        isSelf = (viewerCid ~= nil and cid == viewerCid)
      }
    end
    table.sort(out, function(a,b) return (a.grade.level or 0) > (b.grade.level or 0) end)
    return out
  end

  -- Fallback QB: JSON players.gang (se existir no seu schema)
  local rows2 = dbFetchAll("SELECT citizenid, charinfo, gang FROM players WHERE gang LIKE ?", { '%' .. gangName .. '%' }) or {}
  for _, r in ipairs(rows2) do
    local gangObj = {}
    if r.gang then
      local ok, decoded = pcall(json.decode, r.gang)
      if ok and decoded then gangObj = decoded end
    end
    if gangObj and gangObj.name == gangName then
      local cid = r.citizenid
      local online = getPlayerByCitizenId(cid)
      out[#out+1] = {
        citizenid = cid,
        name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
        grade = gangObj.grade or {},
        isboss = gangObj.isboss == true,
        online = online ~= nil,
        source = online and online.PlayerData and online.PlayerData.source or nil,
        isSelf = (viewerCid ~= nil and cid == viewerCid)
      }
    end
  end

  table.sort(out, function(a,b)
    local ga = (a.grade and (a.grade.level or a.grade.grade or 0)) or 0
    local gb = (b.grade and (b.grade.level or b.grade.grade or 0)) or 0
    return ga > gb
  end)

  return out
end
--============================================================
-- INVENTÁRIO / INVENTORY (ox_inventory / qb-inventory / ps-inventory)
-- Wrapper para itens (multas, boletos, docs etc.) + Stashes
--============================================================

local InventoryDetected = nil

local function DetectInventory()
  if InventoryDetected then return InventoryDetected end

  if GetResourceState('ox_inventory') == 'started' then
    InventoryDetected = 'ox'
    dbg('Inventário detectado: ox_inventory')
    return InventoryDetected
  end

  if GetResourceState('ps-inventory') == 'started' then
    InventoryDetected = 'ps'
    dbg('Inventário detectado: ps-inventory')
    return InventoryDetected
  end

  if GetResourceState('qb-inventory') == 'started' then
    InventoryDetected = 'qb'
    dbg('Inventário detectado: qb-inventory')
    return InventoryDetected
  end

  InventoryDetected = 'none'
  dbg('Inventário não detectado (ox_inventory / qb-inventory / ps-inventory)')
  return InventoryDetected
end

-- Adiciona item
function SE.Integrations.InventoryAddItem(src, item, amount, metadata, slot)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  item = tostring(item or '')
  if item == '' then return false, 'invalid_item' end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local inv = DetectInventory()

  -- Preferência: Bridge (se você tiver)
  if B and B.InventoryAddItem then
    local ok, res = pcall(B.InventoryAddItem, src, item, amount, metadata, slot)
    if ok and res then return true end
  end

  -- ox_inventory
  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function()
      return exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
    end)
    if ok and res then return true end
    return false, 'ox_add_failed'
  end

  -- qb/ps (via framework player funcs)
  local fw = DetectFramework()
  if (inv == 'qb' or inv == 'ps') and fw == 'qbcore' and exports['qb-core'] then
    local okCore, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if okCore and QBCore then
      local ply = QBCore.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.AddItem then
        local okAdd, res = pcall(function()
          return ply.Functions.AddItem(item, amount, slot, metadata)
        end)
        if okAdd and res then return true end
        return false, 'qb_add_failed'
      end
    end
  end

  -- Fallback client-side (se quiser implementar)
  TriggerClientEvent('space_economy:client_requestAddItem', src, item, amount, metadata, slot)
  return false, 'no_inventory_integration'
end

-- Remove item
function SE.Integrations.InventoryRemoveItem(src, item, amount, metadata, slot)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  item = tostring(item or '')
  if item == '' then return false, 'invalid_item' end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local inv = DetectInventory()

  if B and B.InventoryRemoveItem then
    local ok, res = pcall(B.InventoryRemoveItem, src, item, amount, metadata, slot)
    if ok and res then return true end
  end

  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function()
      return exports.ox_inventory:RemoveItem(src, item, amount, metadata, slot)
    end)
    if ok and res then return true end
    return false, 'ox_remove_failed'
  end

  local fw = DetectFramework()
  if (inv == 'qb' or inv == 'ps') and fw == 'qbcore' and exports['qb-core'] then
    local okCore, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if okCore and QBCore then
      local ply = QBCore.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.RemoveItem then
        local okRem, res = pcall(function()
          return ply.Functions.RemoveItem(item, amount, slot)
        end)
        if okRem and res then return true end
        return false, 'qb_remove_failed'
      end
    end
  end

  TriggerClientEvent('space_economy:client_requestRemoveItem', src, item, amount, metadata, slot)
  return false, 'no_inventory_integration'
end

-- Contagem de item
function SE.Integrations.InventoryGetItemCount(src, item, metadata)
  src = tonumber(src)
  if not src or src <= 0 then return 0 end

  item = tostring(item or '')
  if item == '' then return 0 end

  local inv = DetectInventory()

  if B and B.InventoryGetItemCount then
    local ok, res = pcall(B.InventoryGetItemCount, src, item, metadata)
    if ok and type(res) == 'number' then return U.toInt(res, 0) end
  end

  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function()
      return exports.ox_inventory:GetItemCount(src, item, metadata, true)
    end)
    if ok and res then return U.toInt(res, 0) end
    return 0
  end

  -- qb/ps (via player data)
  local fw = DetectFramework()
  if (inv == 'qb' or inv == 'ps') and fw == 'qbcore' and exports['qb-core'] then
    local okCore, QBCore = pcall(exports['qb-core'].GetCoreObject)
    if okCore and QBCore then
      local ply = QBCore.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.GetItemByName then
        local data = ply.Functions.GetItemByName(item)
        return U.toInt(data and data.amount or 0, 0)
      end
    end
  end

  return 0
end

function SE.Integrations.InventoryHasItem(src, item, amount, metadata)
  amount = U.toInt(amount, 1)
  return SE.Integrations.InventoryGetItemCount(src, item, metadata) >= amount
end

function SE.Integrations.InventoryCanCarryItem(src, item, amount, metadata)
  src = tonumber(src)
  if not src or src <= 0 then return false end

  item = tostring(item or '')
  if item == '' then return false end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false end

  local inv = DetectInventory()

  if inv == 'ox' and exports.ox_inventory and exports.ox_inventory.CanCarryItem then
    local ok, res = pcall(function()
      return exports.ox_inventory:CanCarryItem(src, item, amount, metadata)
    end)
    if ok then return res == true end
  end

  -- qb/ps normalmente não tem um "CanCarry" confiável -> assume true
  return true
end

-- Abre (e registra) stash compatível
function SE.Integrations.OpenStash(src, name, label, slots, weight, groups, coords)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  name = tostring(name or '')
  if name == '' then return false, 'invalid_stash' end

  label = tostring(label or name)
  slots = U.toInt(slots, 20)
  weight = U.toInt(weight, 100000)

  local inv = DetectInventory()

  if inv == 'ox' then
    pcall(function()
      exports.ox_inventory:RegisterStash(name, label, slots, weight, false, groups, coords)
    end)
    TriggerClientEvent('ox_inventory:openInventory', src, 'stash', name)
    return true
  end

  if inv == 'qb' or inv == 'ps' then
    TriggerClientEvent('inventory:client:SetCurrentStash', src, name)
    TriggerClientEvent('inventory:client:OpenInventory', src, 'stash', { id = name, slots = slots, weight = weight })
    return true
  end

  return false, 'no_inventory_integration'
end

--============================================================
-- EXPORTS
--============================================================
exports('RemoveMoney', SE.Integrations.RemoveMoney)
exports('AddMoney', SE.Integrations.AddMoney)
exports('GetBalance', SE.Integrations.GetBalance)
exports('EmitWarrant', SE.Integrations.EmitWarrantIfNeeded)
exports('BankingTransfer', SE.Integrations.BankingTransfer)
exports('GetResidences', SE.Integrations.GetResidences)
exports('GetResidenceSummary', SE.Integrations.GetResidenceSummary)
exports('GetResidenceTaxBase', SE.Integrations.GetResidenceTaxBase)
exports('GetVehicleOwnerByPlate', SE.Integrations.GetVehicleOwnerByPlate)
exports('GetOwnedVehicles', SE.Integrations.GetOwnedVehicles)
exports('SetVehicleStateByPlate', SE.Integrations.SetVehicleStateByPlate)
exports('ImpoundVehicleByPlate', SE.Integrations.ImpoundVehicleByPlate)
exports('ReleaseVehicleByPlate', SE.Integrations.ReleaseVehicleByPlate)
exports('GetVehiclePriceByModel', SE.Integrations.GetVehiclePriceByModel)
exports('GetVehicles', SE.Integrations.GetVehicles)
exports('GetVehicleSummary', SE.Integrations.GetVehicleSummary)
exports('GetVehicleTaxBase', SE.Integrations.GetVehicleTaxBase)
exports('SetJob', SE.Integrations.SetJob)
exports('HireEmployee', SE.Integrations.HireEmployee)
exports('FireEmployee', SE.Integrations.FireEmployee)
exports('SetEmployeeGrade', SE.Integrations.SetEmployeeGrade)
exports('GetJobEmployees', SE.Integrations.GetJobEmployees)
exports('SetGang', SE.Integrations.SetGang)
exports('HireGangMember', SE.Integrations.HireGangMember)
exports('FireGangMember', SE.Integrations.FireGangMember)
exports('SetGangGrade', SE.Integrations.SetGangGrade)
exports('GetGangMembers', SE.Integrations.GetGangMembers)
exports('InventoryAddItem', SE.Integrations.InventoryAddItem)
exports('InventoryRemoveItem', SE.Integrations.InventoryRemoveItem)
exports('InventoryGetItemCount', SE.Integrations.InventoryGetItemCount)
exports('InventoryHasItem', SE.Integrations.InventoryHasItem)
exports('InventoryCanCarryItem', SE.Integrations.InventoryCanCarryItem)
exports('OpenStash', SE.Integrations.OpenStash)
