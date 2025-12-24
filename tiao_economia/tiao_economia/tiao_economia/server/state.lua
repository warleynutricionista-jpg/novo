SE = SE or {}
SE.Server = SE.Server or {}
SE.State = SE.State or {}

local U = SE.Util
local S = SE.State

S.dirty = S.dirty == true
S.vaultBalance = U.toInt(S.vaultBalance, (Config.Treasury and Config.Treasury.StartBalance) or 0)
S.inflationRate = U.toNumber(S.inflationRate, (Config.Inflation and Config.Inflation.DefaultRate) or 1.0)
S.taxMultiplier = U.toNumber(S.taxMultiplier, Config.TaxMultiplierDefault or 1.0)
S.settings = type(S.settings) == 'table' and S.settings or {}

local ensured = false
local saving = false

local function tableExists(t)
  local r = MySQL.single.await('SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1', { t })
  return r ~= nil
end

local function colExists(t, c)
  local r = MySQL.single.await('SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1', { t, c })
  return r ~= nil
end

local function ensureSchema()
  if ensured then return end
  ensured = true

  -- ===== state KV (key/value) =====
  if not tableExists('space_economy_state') then
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_state (
        `key` VARCHAR(64) PRIMARY KEY,
        `value` LONGTEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      )
    ]])
  else
    -- migra k/v -> key/value se precisar
    if colExists('space_economy_state', 'k') and not colExists('space_economy_state', 'key') then
      MySQL.query.await('ALTER TABLE `space_economy_state` CHANGE COLUMN `k` `key` VARCHAR(64) NOT NULL')
    end
    if colExists('space_economy_state', 'v') and not colExists('space_economy_state', 'value') then
      MySQL.query.await('ALTER TABLE `space_economy_state` CHANGE COLUMN `v` `value` LONGTEXT NULL')
    end
    if colExists('space_economy_state', 'value') then
      MySQL.query.await('ALTER TABLE `space_economy_state` MODIFY COLUMN `value` LONGTEXT')
    end
  end

  -- ===== global row =====
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy (
      id INT PRIMARY KEY,
      vaultBalance BIGINT NOT NULL DEFAULT 0,
      inflationRate DOUBLE NOT NULL DEFAULT 1.0,
      taxMultiplier DOUBLE NOT NULL DEFAULT 1.0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])

  -- adiciona colunas se a tabela já existia sem elas
  if not colExists('space_economy', 'vaultBalance') then
    MySQL.query.await('ALTER TABLE `space_economy` ADD COLUMN `vaultBalance` BIGINT NOT NULL DEFAULT 0')
  end
  if not colExists('space_economy', 'inflationRate') then
    MySQL.query.await('ALTER TABLE `space_economy` ADD COLUMN `inflationRate` DOUBLE NOT NULL DEFAULT 1.0')
  end
  if not colExists('space_economy', 'taxMultiplier') then
    MySQL.query.await('ALTER TABLE `space_economy` ADD COLUMN `taxMultiplier` DOUBLE NOT NULL DEFAULT 1.0')
  end

  -- garante row id=1
  MySQL.update.await([[
    INSERT INTO space_economy (id, vaultBalance, inflationRate, taxMultiplier)
    VALUES (1, ?, ?, ?)
    ON DUPLICATE KEY UPDATE id = id
  ]], {
    U.toInt((Config.Treasury and Config.Treasury.StartBalance) or 0, 0),
    U.toNumber((Config.Inflation and Config.Inflation.DefaultRate) or 1.0, 1.0),
    U.toNumber(Config.TaxMultiplierDefault or 1.0, 1.0),
  })
end

function SE.Server.MarkDirty()
  S.dirty = true
end

function SE.Server.SetInflationRate(rate)
  rate = U.toNumber(rate, S.inflationRate)
  local minR = (Config.Inflation and Config.Inflation.MinRate) or 0.80
  local maxR = (Config.Inflation and Config.Inflation.MaxRate) or 1.50
  rate = U.clamp(rate, minR, maxR)
  if rate ~= S.inflationRate then
    S.inflationRate = rate
    SE.Server.MarkDirty()
  end
  return S.inflationRate
end

function SE.Server.SetTaxMultiplier(mult)
  mult = U.toNumber(mult, S.taxMultiplier)
  mult = U.clamp(mult, 0.10, 5.00)
  if mult ~= S.taxMultiplier then
    S.taxMultiplier = mult
    SE.Server.MarkDirty()
  end
  return S.taxMultiplier
end

function SE.Server.LoadState()
  ensureSchema()

  local r = MySQL.single.await('SELECT vaultBalance, inflationRate, taxMultiplier FROM space_economy WHERE id = 1 LIMIT 1')
  if r then
    S.vaultBalance = U.toInt(r.vaultBalance, S.vaultBalance)
    S.inflationRate = U.toNumber(r.inflationRate, S.inflationRate)
    S.taxMultiplier = U.toNumber(r.taxMultiplier, S.taxMultiplier)
  end

  local st = MySQL.single.await('SELECT `value` FROM space_economy_state WHERE `key` = "settings" LIMIT 1')
  if st and st.value then
    S.settings = U.safeJsonDecode(st.value) or {}
  end

  S.dirty = false
  U.dbg('State carregado:', S.vaultBalance, S.inflationRate, S.taxMultiplier)
end

function SE.Server.SaveState(force)
  if saving then return end
  if not force and not S.dirty then return end

  saving = true
  S.dirty = false

  S.vaultBalance = U.toInt(S.vaultBalance, 0)
  S.inflationRate = U.toNumber(S.inflationRate, 1.0)
  S.taxMultiplier = U.toNumber(S.taxMultiplier, 1.0)
  if type(S.settings) ~= 'table' then S.settings = {} end

  MySQL.update.await('UPDATE space_economy SET vaultBalance = ?, inflationRate = ?, taxMultiplier = ? WHERE id = 1', {
    S.vaultBalance, S.inflationRate, S.taxMultiplier
  })

  MySQL.update.await([[
    INSERT INTO space_economy_state (`key`, `value`)
    VALUES ("settings", ?)
    ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)
  ]], { U.safeJsonEncode(S.settings) })

  saving = false
end

CreateThread(function()
  while not MySQL do Wait(200) end
  SE.Server.LoadState()

  local interval = U.toInt(U.cfg('Persistence.IntervalMs', 60000), 60000)
  if interval < 15000 then interval = 15000 end

  while true do
    Wait(interval)
    SE.Server.SaveState(false)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  SE.Server.SaveState(true)
end)
