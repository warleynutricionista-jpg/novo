--============================================================
-- space_economy - server/auto_tax.lua (NOVO)
-- Integração automática para taxar compras, veículos e propriedades
--============================================================
SE = SE or {}
SE.AutoTax = SE.AutoTax or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config.Integrations or {}

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[auto_tax]^7', ...) end 
end

--============================================================
-- HOOKS PARA SHOPS (qb-shops, ox_inventory, etc)
--============================================================

-- Hook genérico para compras
local function hookShopPurchase(src, item, price, quantity)
  quantity = quantity or 1
  price = U.toInt(price, 0) * quantity
  
  if price <= 0 then return true end
  
  -- Calcula imposto (ICMS)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'ICMS' then return t end
      end
      return nil
    end)()
  
  if not taxCfg or not cfg.Shops or not cfg.Shops.TaxPurchases then
    return true -- Sem taxação
  end
  
  local taxRate = taxCfg.percent or 12
  local taxAmount = math.floor(price * (taxRate / 100))
  
  if taxAmount <= 0 then return true end
  
  -- Cria dívida de imposto
  local cid = B.GetCitizenId(src)
  if not cid then return true end
  
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, 'ICMS - Compra', os.time() + (30 * 24 * 60 * 60), {
      item = item,
      base_price = price,
      tax_rate = taxRate,
      quantity = quantity
    })
  end
  
  dbg(('ICMS sobre compra: %s | $%d (base: $%d)'):format(cid, taxAmount, price))
  
  return true
end

-- Integração com qb-shops / qbx-shops
if GetResourceState('qb-shops') == 'started' or GetResourceState('qbx-shops') == 'started' then
  -- Hook no evento de compra
  AddEventHandler('qb-shops:server:purchaseItem', function(src, data)
    hookShopPurchase(src, data.item, data.price, data.amount)
  end)
  
  dbg('Hooked: qb-shops')
end

-- Integração com ox_inventory shops
if GetResourceState('ox_inventory') == 'started' then
  AddEventHandler('ox_inventory:server:shopPurchase', function(src, data)
    hookShopPurchase(src, data.name, data.price, data.count)
  end)
  
  dbg('Hooked: ox_inventory')
end

--============================================================
-- IPVA AUTOMÁTICO (Garages)
--============================================================

-- Calcula IPVA baseado no valor do veículo
local function calculateIPVA(vehiclePrice)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'IPVA' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return 0 end
  
  local rate = taxCfg.percent or 1.5
  return math.floor(vehiclePrice * (rate / 100))
end

-- Hook para quando player compra veículo
function SE.AutoTax.OnVehiclePurchase(src, vehicleData)
  if not (cfg.Garages and cfg.Garages.AutoIPVA) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local price = U.toInt(vehicleData.price, 0)
  if price <= 0 then return end
  
  local ipva = calculateIPVA(price)
  if ipva <= 0 then return end
  
  -- Cria dívida de IPVA (vence em 30 dias)
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, ipva, 'IPVA - ' .. (vehicleData.model or 'Veículo'), 
      os.time() + (30 * 24 * 60 * 60), {
      vehicle_model = vehicleData.model,
      vehicle_plate = vehicleData.plate,
      base_price = price,
      ipva_rate = 1.5
    })
    
    B.Notify(src, ('IPVA lançado: $%d (vence em 30 dias)'):format(ipva), 'inform')
  end
  
  dbg(('IPVA lançado: %s | $%d (veículo: %s)'):format(cid, ipva, vehicleData.plate or '?'))
end

-- Integração com qb-vehicleshop / qbx-vehicleshop
if GetResourceState('qb-vehicleshop') == 'started' or GetResourceState('qbx-vehicleshop') == 'started' then
  AddEventHandler('qb-vehicleshop:server:buyVehicle', function(src, data)
    SE.AutoTax.OnVehiclePurchase(src, data)
  end)
  
  dbg('Hooked: qb-vehicleshop (IPVA)')
end

-- Thread: IPVA anual recorrente
if cfg.Garages and cfg.Garages.AutoIPVA then
  CreateThread(function()
    while not MySQL do Wait(1000) end
    
    local intervalMs = 24 * 60 * 60 * 1000 -- Diário
    
    while true do
      Wait(intervalMs)
      
      -- Busca veículos que precisam renovar IPVA
      -- Requer tabela player_vehicles com colunas: citizenid, vehicle, plate, price, last_ipva_at
      
      local vehicles = MySQL.query.await([[
        SELECT citizenid, vehicle, plate, 
               COALESCE(price, 50000) as price
        FROM player_vehicles
        WHERE (last_ipva_at IS NULL OR last_ipva_at < DATE_SUB(NOW(), INTERVAL 365 DAY))
        LIMIT 100
      ]])
      
      if vehicles then
        for _, v in ipairs(vehicles) do
          local ipva = calculateIPVA(U.toInt(v.price, 50000))
          
          if ipva > 0 and SE.Debts and SE.Debts.Upsert then
            SE.Debts.Upsert(v.citizenid, ipva, 'IPVA - ' .. (v.vehicle or 'Veículo'),
              os.time() + (30 * 24 * 60 * 60), {
              vehicle_plate = v.plate,
              base_price = v.price,
              ipva_rate = 1.5,
              annual = true
            })
            
            -- Atualiza última cobrança
            MySQL.update.await([[
              UPDATE player_vehicles
              SET last_ipva_at = NOW()
              WHERE plate = ?
            ]], {v.plate})
            
            dbg(('IPVA anual: %s | $%d (placa: %s)'):format(v.citizenid, ipva, v.plate))
          end
        end
      end
    end
  end)
end

--============================================================
-- IPTU AUTOMÁTICO (Real Estate)
--============================================================

-- Calcula IPTU baseado no valor da propriedade
local function calculateIPTU(propertyPrice)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'IPTU' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return 0 end
  
  local rate = taxCfg.percent or 0.3
  return math.floor(propertyPrice * (rate / 100))
end

-- Hook para quando player compra propriedade
function SE.AutoTax.OnPropertyPurchase(src, propertyData)
  if not (cfg.RealEstate and cfg.RealEstate.AutoIPTU) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local price = U.toInt(propertyData.price, 0)
  if price <= 0 then return end
  
  local iptu = calculateIPTU(price)
  if iptu <= 0 then return end
  
  -- Cria dívida de IPTU (vence em 30 dias)
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, iptu, 'IPTU - ' .. (propertyData.label or 'Propriedade'),
      os.time() + (30 * 24 * 60 * 60), {
      property_id = propertyData.id,
      property_label = propertyData.label,
      base_price = price,
      iptu_rate = 0.3
    })
    
    B.Notify(src, ('IPTU lançado: $%d (vence em 30 dias)'):format(iptu), 'inform')
  end
  
  dbg(('IPTU lançado: %s | $%d (propriedade: %s)'):format(cid, iptu, propertyData.label or '?'))
end

-- Integração com qb-houses / ps-housing
if GetResourceState('qb-houses') == 'started' or GetResourceState('ps-housing') == 'started' then
  AddEventHandler('qb-houses:server:buyProperty', function(src, data)
    SE.AutoTax.OnPropertyPurchase(src, data)
  end)
  
  AddEventHandler('ps-housing:server:buyProperty', function(src, data)
    SE.AutoTax.OnPropertyPurchase(src, data)
  end)
  
  dbg('Hooked: housing (IPTU)')
end

-- Thread: IPTU mensal recorrente
if cfg.RealEstate and cfg.RealEstate.AutoIPTU then
  CreateThread(function()
    while not MySQL do Wait(1000) end
    
    local intervalMs = 24 * 60 * 60 * 1000 -- Diário
    
    while true do
      Wait(intervalMs)
      
      -- Busca propriedades que precisam pagar IPTU
      -- Requer tabela player_houses/properties com: citizenid, label, price, last_iptu_at
      
      local properties = MySQL.query.await([[
        SELECT citizenid, label, 
               COALESCE(price, 100000) as price
        FROM player_houses
        WHERE (last_iptu_at IS NULL OR last_iptu_at < DATE_SUB(NOW(), INTERVAL 30 DAY))
        LIMIT 100
      ]])
      
      if properties then
        for _, p in ipairs(properties) do
          local iptu = calculateIPTU(U.toInt(p.price, 100000))
          
          if iptu > 0 and SE.Debts and SE.Debts.Upsert then
            SE.Debts.Upsert(p.citizenid, iptu, 'IPTU - ' .. (p.label or 'Propriedade'),
              os.time() + (30 * 24 * 60 * 60), {
              property_label = p.label,
              base_price = p.price,
              iptu_rate = 0.3,
              monthly = true
            })
            
            -- Atualiza última cobrança
            MySQL.update.await([[
              UPDATE player_houses
              SET last_iptu_at = NOW()
              WHERE label = ?
            ]], {p.label})
            
            dbg(('IPTU mensal: %s | $%d (propriedade: %s)'):format(p.citizenid, iptu, p.label))
          end
        end
      end
    end
  end)
end

--============================================================
-- ISS (Imposto sobre Serviços)
--============================================================

-- Hook para prestação de serviços
function SE.AutoTax.OnServiceProvided(src, serviceData)
  if not (cfg.Shops and cfg.Shops.TaxPurchases) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local amount = U.toInt(serviceData.amount, 0)
  if amount <= 0 then return end
  
  -- Calcula ISS (2%)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'ISS' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return end
  
  local rate = taxCfg.percent or 2
  local taxAmount = math.floor(amount * (rate / 100))
  
  if taxAmount <= 0 then return end
  
  -- Cria dívida de ISS
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, 'ISS - ' .. (serviceData.service or 'Serviço'),
      os.time() + (30 * 24 * 60 * 60), {
      service = serviceData.service,
      base_amount = amount,
      tax_rate = rate
    })
  end
  
  dbg(('ISS sobre serviço: %s | $%d (base: $%d)'):format(cid, taxAmount, amount))
end

-- Exports para outros recursos
exports('TaxVehiclePurchase', SE.AutoTax.OnVehiclePurchase)
exports('TaxPropertyPurchase', SE.AutoTax.OnPropertyPurchase)
exports('TaxService', SE.AutoTax.OnServiceProvided)
exports('TaxShopPurchase', hookShopPurchase)

--============================================================
-- COMANDOS ADMIN
--============================================================
RegisterCommand('eco_tax_vehicle', function(source, args)
  if not SE.Admin.IsAllowed(source) then return end
  
  local targetId = tonumber(args[1])
  local price = tonumber(args[2]) or 50000
  
  if not targetId then
    TriggerClientEvent('chat:addMessage', source, {
      args = {'[Economia]', 'Uso: /eco_tax_vehicle [id] [preço]'}
    })
    return
  end
  
  SE.AutoTax.OnVehiclePurchase(targetId, {
    price = price,
    model = 'Admin',
    plate = 'ADMIN'
  })
  
  TriggerClientEvent('chat:addMessage', source, {
    args = {'[Economia]', ('IPVA de $%d lançado para ID %d'):format(calculateIPVA(price), targetId)}
  })
end, false)

RegisterCommand('eco_tax_property', function(source, args)
  if not SE.Admin.IsAllowed(source) then return end
  
  local targetId = tonumber(args[1])
  local price = tonumber(args[2]) or 100000
  
  if not targetId then
    TriggerClientEvent('chat:addMessage', source, {
      args = {'[Economia]', 'Uso: /eco_tax_property [id] [preço]'}
    })
    return
  end
  
  SE.AutoTax.OnPropertyPurchase(targetId, {
    price = price,
    label = 'Propriedade Admin',
    id = 'admin_property'
  })
  
  TriggerClientEvent('chat:addMessage', source, {
    args = {'[Economia]', ('IPTU de $%d lançado para ID %d'):format(calculateIPTU(price), targetId)}
  })
end, false)