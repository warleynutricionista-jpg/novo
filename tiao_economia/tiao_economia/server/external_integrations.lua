--============================================================
-- space_economy - server/external_integrations.lua
-- Integrações com recursos externos do servidor
-- Author: Space Economy Team v5.0
--============================================================
SE = SE or {}
SE.External = SE.External or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config.Integrations or {}

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^5[external_integrations]^7', ...) end
end

local function err(...) print('^1[external_integrations ERROR]^7', ...) end

--============================================================
-- 1. PS-BANKING INTEGRATION
-- Sistema bancário: taxar transferências, depósitos, saques
--============================================================
SE.External.Banking = {
  Enabled = false,
  TaxTransfers = true,
  TaxRate = 0.5, -- 0.5% em transferências
  MinTaxAmount = 10, -- Mínimo de $10 para taxar
}

local function initPsBanking()
  if GetResourceState('ps-banking') ~= 'started' then
    dbg('ps-banking não encontrado')
    return false
  end

  SE.External.Banking.Enabled = true

  -- Hook em transferências bancárias
  AddEventHandler('ps-banking:server:transfer', function(source, data)
    if not SE.External.Banking.TaxTransfers then return end

    local amount = tonumber(data.amount) or 0
    if amount <= 0 then return end

    local taxAmount = math.floor(amount * (SE.External.Banking.TaxRate / 100))

    if taxAmount < SE.External.Banking.MinTaxAmount then return end

    local cid = B.GetCitizenId(source)
    if not cid then return end

    -- Cria dívida de taxa de transferência (IOF)
    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, taxAmount, 'IOF - Transferência Bancária', os.time() + (7 * 24 * 60 * 60), {
        transfer_amount = amount,
        tax_rate = SE.External.Banking.TaxRate,
        to_account = data.target or 'unknown'
      })

      B.Notify(source, ('Taxa IOF: $%d (%.1f%% de $%d)'):format(taxAmount, SE.External.Banking.TaxRate, amount), 'inform')
      dbg(('IOF cobrado: %s | $%d sobre transferência de $%d'):format(cid, taxAmount, amount))
    end
  end)

  -- Hook em saques de caixa eletrônico (ATM)
  AddEventHandler('ps-banking:server:withdraw', function(source, data)
    local amount = tonumber(data.amount) or 0
    if amount <= 0 or amount < 5000 then return end -- Só taxa saques grandes

    local taxAmount = 50 -- Taxa fixa de $50 para saques acima de $5000
    local cid = B.GetCitizenId(source)
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, taxAmount, 'Taxa de Saque ATM', os.time() + (7 * 24 * 60 * 60), {
        withdraw_amount = amount
      })

      B.Notify(source, 'Taxa de saque ATM: $50', 'inform')
    end
  end)

  dbg('✓ ps-banking integrado (Taxação em transferências e saques)')
  return true
end

--============================================================
-- 2. OX_INVENTORY INTEGRATION
-- Inventário e lojas: taxar todas as compras (ICMS)
--============================================================
SE.External.Inventory = {
  Enabled = false,
  TaxPurchases = true,
  TaxRate = 12.0, -- ICMS 12%
  ExemptItems = {}, -- Items isentos de imposto
}

local function initOxInventory()
  if GetResourceState('ox_inventory') ~= 'started' then
    dbg('ox_inventory não encontrado')
    return false
  end

  SE.External.Inventory.Enabled = true

  -- Hook em compras de lojas
  AddEventHandler('ox_inventory:server:buyItem', function(playerId, itemName, count, price, shopName)
    if not SE.External.Inventory.TaxPurchases then return end

    -- Verifica se item é isento
    for _, exempt in ipairs(SE.External.Inventory.ExemptItems) do
      if itemName == exempt then return end
    end

    local totalPrice = (price or 0) * (count or 1)
    if totalPrice <= 0 then return end

    local taxAmount = math.floor(totalPrice * (SE.External.Inventory.TaxRate / 100))
    if taxAmount <= 0 then return end

    local cid = B.GetCitizenId(playerId)
    if not cid then return end

    -- Cria dívida de ICMS
    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, taxAmount, ('ICMS - Compra: %s'):format(itemName), os.time() + (30 * 24 * 60 * 60), {
        item = itemName,
        quantity = count,
        base_price = totalPrice,
        tax_rate = SE.External.Inventory.TaxRate,
        shop = shopName
      })

      dbg(('ICMS: %s comprou %dx %s por $%d | ICMS: $%d'):format(cid, count, itemName, totalPrice, taxAmount))
    end
  end)

  -- Hook alternativo para ox_inventory shops (formato diferente)
  AddEventHandler('ox_inventory:shopPurchase', function(source, data)
    if not SE.External.Inventory.TaxPurchases then return end

    local itemName = data.name or data.item
    local price = data.price or 0
    local count = data.count or data.amount or 1

    local totalPrice = price * count
    if totalPrice <= 0 then return end

    local taxAmount = math.floor(totalPrice * (SE.External.Inventory.TaxRate / 100))
    if taxAmount <= 0 then return end

    local cid = B.GetCitizenId(source)
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, taxAmount, ('ICMS - %s'):format(itemName), os.time() + (30 * 24 * 60 * 60), {
        item = itemName,
        quantity = count,
        base_price = totalPrice,
        tax_rate = SE.External.Inventory.TaxRate
      })
    end
  end)

  dbg('✓ ox_inventory integrado (ICMS em compras)')
  return true
end

--============================================================
-- 3. VEHICLE SYSTEMS INTEGRATION (rhd_garage + rm-dealership)
-- Garagens e concessionárias: IPVA automático
--============================================================
SE.External.Vehicles = {
  Enabled = false,
  TaxRate = 1.5, -- IPVA 1.5%
  MinVehiclePrice = 1000,
  AnnualIPVA = true, -- Cobrar IPVA anualmente
}

local function calculateIPVA(vehiclePrice)
  local price = tonumber(vehiclePrice) or 0
  if price < SE.External.Vehicles.MinVehiclePrice then return 0 end

  return math.floor(price * (SE.External.Vehicles.TaxRate / 100))
end

local function initVehicleSystems()
  local hasGarage = GetResourceState('rhd_garage') == 'started'
  local hasDealership = GetResourceState('rm-dealership') == 'started'

  if not hasGarage and not hasDealership then
    dbg('Sistemas de veículos não encontrados')
    return false
  end

  SE.External.Vehicles.Enabled = true

  -- RHD GARAGE - Hook em compra de veículos
  if hasGarage then
    AddEventHandler('rhd_garage:server:vehiclePurchased', function(source, vehicleData)
      local price = tonumber(vehicleData.price or vehicleData.value) or 0
      local ipva = calculateIPVA(price)

      if ipva <= 0 then return end

      local cid = B.GetCitizenId(source)
      if not cid then return end

      if SE.Debts and SE.Debts.Upsert then
        SE.Debts.Upsert(cid, ipva, ('IPVA - %s'):format(vehicleData.model or vehicleData.vehicle), os.time() + (30 * 24 * 60 * 60), {
          vehicle_model = vehicleData.model or vehicleData.vehicle,
          vehicle_plate = vehicleData.plate,
          vehicle_price = price,
          tax_rate = SE.External.Vehicles.TaxRate
        })

        B.Notify(source, ('IPVA devido: $%d (%.1f%% de $%d)'):format(ipva, SE.External.Vehicles.TaxRate, price), 'inform')
        dbg(('IPVA: %s | Veículo %s | $%d'):format(cid, vehicleData.plate or 'N/A', ipva))
      end
    end)

    dbg('✓ rhd_garage integrado')
  end

  -- RM DEALERSHIP - Hook em compra de veículos
  if hasDealership then
    AddEventHandler('rm-dealership:server:buyVehicle', function(source, data)
      local price = tonumber(data.price) or 0
      local ipva = calculateIPVA(price)

      if ipva <= 0 then return end

      local cid = B.GetCitizenId(source)
      if not cid then return end

      if SE.Debts and SE.Debts.Upsert then
        SE.Debts.Upsert(cid, ipva, ('IPVA - %s'):format(data.vehicle or data.model), os.time() + (30 * 24 * 60 * 60), {
          vehicle_model = data.vehicle or data.model,
          vehicle_price = price,
          tax_rate = SE.External.Vehicles.TaxRate,
          dealership = data.dealership
        })

        B.Notify(source, ('IPVA devido: $%d (%.1f%%)'):format(ipva, SE.External.Vehicles.TaxRate), 'inform')
        dbg(('IPVA (dealership): %s | $%d'):format(cid, ipva))
      end
    end)

    dbg('✓ rm-dealership integrado')
  end

  -- Export para cobrar IPVA manualmente
  SE.External.Vehicles.ChargeIPVA = function(src, plate, vehiclePrice)
    local ipva = calculateIPVA(vehiclePrice)
    if ipva <= 0 then return false end

    local cid = B.GetCitizenId(src)
    if not cid then return false end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, ipva, ('IPVA Anual - %s'):format(plate), os.time() + (30 * 24 * 60 * 60), {
        vehicle_plate = plate,
        vehicle_price = vehiclePrice,
        tax_rate = SE.External.Vehicles.TaxRate,
        annual = true
      })

      return true, ipva
    end

    return false
  end

  return true
end

--============================================================
-- 4. PS-HOUSING INTEGRATION
-- Sistema de casas: IPTU automático
--============================================================
SE.External.Housing = {
  Enabled = false,
  TaxRate = 0.3, -- IPTU 0.3%
  MinPropertyPrice = 5000,
  AnnualIPTU = true,
}

local function calculateIPTU(propertyPrice)
  local price = tonumber(propertyPrice) or 0
  if price < SE.External.Housing.MinPropertyPrice then return 0 end

  return math.floor(price * (SE.External.Housing.TaxRate / 100))
end

local function initPsHousing()
  if GetResourceState('ps-housing') ~= 'started' then
    dbg('ps-housing não encontrado')
    return false
  end

  SE.External.Housing.Enabled = true

  -- Hook em compra de propriedade
  AddEventHandler('ps-housing:server:purchaseProperty', function(source, propertyData)
    local price = tonumber(propertyData.price) or 0
    local iptu = calculateIPTU(price)

    if iptu <= 0 then return end

    local cid = B.GetCitizenId(source)
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, iptu, ('IPTU - %s'):format(propertyData.address or propertyData.street or 'Propriedade'), os.time() + (30 * 24 * 60 * 60), {
        property_address = propertyData.address or propertyData.street,
        property_price = price,
        property_type = propertyData.type or 'house',
        tax_rate = SE.External.Housing.TaxRate
      })

      B.Notify(source, ('IPTU devido: $%d (%.1f%% de $%d)'):format(iptu, SE.External.Housing.TaxRate, price), 'inform')
      dbg(('IPTU: %s | Propriedade %s | $%d'):format(cid, propertyData.address or 'N/A', iptu))
    end
  end)

  -- Hook alternativo (alguns servidores usam evento diferente)
  AddEventHandler('ps-housing:buyProperty', function(src, data)
    local price = tonumber(data.price) or 0
    local iptu = calculateIPTU(price)

    if iptu <= 0 then return end

    local cid = B.GetCitizenId(src)
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, iptu, ('IPTU - %s'):format(data.label or 'Propriedade'), os.time() + (30 * 24 * 60 * 60), {
        property_id = data.property,
        property_price = price,
        tax_rate = SE.External.Housing.TaxRate
      })
    end
  end)

  -- Export para cobrar IPTU anual
  SE.External.Housing.ChargeAnnualIPTU = function(src, propertyId, propertyPrice)
    local iptu = calculateIPTU(propertyPrice)
    if iptu <= 0 then return false end

    local cid = B.GetCitizenId(src)
    if not cid then return false end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, iptu, ('IPTU Anual - Propriedade #%s'):format(propertyId), os.time() + (30 * 24 * 60 * 60), {
        property_id = propertyId,
        property_price = propertyPrice,
        tax_rate = SE.External.Housing.TaxRate,
        annual = true
      })

      return true, iptu
    end

    return false
  end

  dbg('✓ ps-housing integrado (IPTU em compras)')
  return true
end

--============================================================
-- 5. KLB-MANAGEMENT INTEGRATION
-- Empresas e contratações: ISS em serviços prestados
--============================================================
SE.External.Management = {
  Enabled = false,
  TaxRate = 2.0, -- ISS 2%
  MinServiceValue = 100,
}

local function initKlbManagement()
  if GetResourceState('klb-management') ~= 'started' then
    dbg('klb-management não encontrado')
    return false
  end

  SE.External.Management.Enabled = true

  -- Hook em pagamento de serviços
  AddEventHandler('klb-management:server:payService', function(source, serviceData)
    local amount = tonumber(serviceData.amount or serviceData.value) or 0

    if amount < SE.External.Management.MinServiceValue then return end

    local iss = math.floor(amount * (SE.External.Management.TaxRate / 100))
    if iss <= 0 then return end

    local cid = B.GetCitizenId(source)
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, iss, ('ISS - Serviço: %s'):format(serviceData.service or serviceData.type or 'Serviço'), os.time() + (15 * 24 * 60 * 60), {
        service_type = serviceData.service or serviceData.type,
        service_amount = amount,
        tax_rate = SE.External.Management.TaxRate,
        company = serviceData.company or serviceData.business
      })

      B.Notify(source, ('ISS devido: $%d (%.1f%%)'):format(iss, SE.External.Management.TaxRate), 'inform')
      dbg(('ISS: %s | Serviço $%d | ISS $%d'):format(cid, amount, iss))
    end
  end)

  -- Hook em pagamentos de folha de empresa
  AddEventHandler('klb-management:server:payroll', function(companyId, employeeData)
    local salary = tonumber(employeeData.salary) or 0
    if salary <= 0 then return end

    -- IRPF sobre salário (simplificado - 2%)
    local irpf = math.floor(salary * 0.02)
    if irpf <= 0 then return end

    local cid = employeeData.citizenid
    if not cid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(cid, irpf, 'IRPF - Salário', os.time() + (15 * 24 * 60 * 60), {
        salary = salary,
        tax_rate = 2.0,
        company = companyId
      })
    end
  end)

  dbg('✓ klb-management integrado (ISS e IRPF)')
  return true
end

--============================================================
-- 6. PS-MDT INTEGRATION
-- Polícia: Multas automáticas
--============================================================
SE.External.Police = {
  Enabled = false,
  AutoCreateDebt = true,
  FineMultiplier = 1.0, -- Multiplicador de multas
}

local function initPsMdt()
  if GetResourceState('ps-mdt') ~= 'started' then
    dbg('ps-mdt não encontrado')
    return false
  end

  SE.External.Police.Enabled = true

  -- Hook em criação de multas
  AddEventHandler('ps-mdt:server:createFine', function(source, targetData, fineData)
    if not SE.External.Police.AutoCreateDebt then return end

    local amount = tonumber(fineData.amount or fineData.fine) or 0
    if amount <= 0 then return end

    -- Aplica multiplicador
    amount = math.floor(amount * SE.External.Police.FineMultiplier)

    local targetCid = targetData.citizenid or targetData.cid
    if not targetCid then return end

    local reason = fineData.reason or fineData.description or 'Multa Administrativa'

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(targetCid, amount, ('Multa: %s'):format(reason), os.time() + (15 * 24 * 60 * 60), {
        fine_type = fineData.type or 'ADMIN_FINE',
        officer_cid = B.GetCitizenId(source),
        mdt_report = fineData.reportId
      })

      dbg(('Multa criada: %s | $%d | Motivo: %s'):format(targetCid, amount, reason))
    end
  end)

  -- Hook em adição de charges (acusações)
  AddEventHandler('ps-mdt:server:addCharge', function(source, targetData, chargeData)
    local fine = tonumber(chargeData.fine or chargeData.amount) or 0
    if fine <= 0 then return end

    fine = math.floor(fine * SE.External.Police.FineMultiplier)

    local targetCid = targetData.citizenid or targetData.cid
    if not targetCid then return end

    if SE.Debts and SE.Debts.Upsert then
      SE.Debts.Upsert(targetCid, fine, ('Acusação: %s'):format(chargeData.label or chargeData.charge), os.time() + (15 * 24 * 60 * 60), {
        charge = chargeData.charge or chargeData.label,
        officer_cid = B.GetCitizenId(source)
      })
    end
  end)

  dbg('✓ ps-mdt integrado (Multas automáticas)')
  return true
end

--============================================================
-- EXPORTS PARA USO MANUAL
--============================================================

-- Taxar compra manualmente
function SE.External.TaxPurchase(src, itemName, price, quantity)
  if not SE.External.Inventory.Enabled then return false, 'inventory_not_enabled' end

  local totalPrice = (price or 0) * (quantity or 1)
  if totalPrice <= 0 then return false, 'invalid_price' end

  local taxAmount = math.floor(totalPrice * (SE.External.Inventory.TaxRate / 100))
  if taxAmount <= 0 then return false, 'no_tax' end

  local cid = B.GetCitizenId(src)
  if not cid then return false, 'no_citizenid' end

  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, ('ICMS - %s'):format(itemName), os.time() + (30 * 24 * 60 * 60), {
      item = itemName,
      quantity = quantity,
      base_price = totalPrice,
      tax_rate = SE.External.Inventory.TaxRate
    })

    return true, taxAmount
  end

  return false, 'debt_system_unavailable'
end

-- Taxar transferência bancária manualmente
function SE.External.TaxTransfer(src, amount, targetAccount)
  if not SE.External.Banking.Enabled then return false, 'banking_not_enabled' end

  local taxAmount = math.floor(amount * (SE.External.Banking.TaxRate / 100))
  if taxAmount < SE.External.Banking.MinTaxAmount then return false, 'below_minimum' end

  local cid = B.GetCitizenId(src)
  if not cid then return false, 'no_citizenid' end

  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, 'IOF - Transferência', os.time() + (7 * 24 * 60 * 60), {
      transfer_amount = amount,
      tax_rate = SE.External.Banking.TaxRate,
      to_account = targetAccount
    })

    return true, taxAmount
  end

  return false, 'debt_system_unavailable'
end

-- Cobrar IPVA manualmente
function SE.External.ChargeIPVA(src, plate, vehiclePrice)
  return SE.External.Vehicles.ChargeIPVA and SE.External.Vehicles.ChargeIPVA(src, plate, vehiclePrice) or false
end

-- Cobrar IPTU manualmente
function SE.External.ChargeIPTU(src, propertyId, propertyPrice)
  return SE.External.Housing.ChargeAnnualIPTU and SE.External.Housing.ChargeAnnualIPTU(src, propertyId, propertyPrice) or false
end

-- Criar multa manualmente
function SE.External.CreateFine(targetCid, amount, reason, officerSrc)
  if not SE.External.Police.Enabled then return false, 'police_not_enabled' end

  amount = tonumber(amount) or 0
  if amount <= 0 then return false, 'invalid_amount' end

  amount = math.floor(amount * SE.External.Police.FineMultiplier)

  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(targetCid, amount, ('Multa: %s'):format(reason or 'Administrativa'), os.time() + (15 * 24 * 60 * 60), {
      fine_type = 'MANUAL',
      officer_cid = officerSrc and B.GetCitizenId(officerSrc) or 'SYSTEM'
    })

    return true, amount
  end

  return false, 'debt_system_unavailable'
end

--============================================================
-- INICIALIZAÇÃO
--============================================================
CreateThread(function()
  Wait(2000) -- Aguarda outros recursos carregarem

  dbg('==========================================================')
  dbg('Inicializando Integrações Externas...')
  dbg('==========================================================')

  local integrations = {
    { name = 'ps-banking', init = initPsBanking },
    { name = 'ox_inventory', init = initOxInventory },
    { name = 'vehicle systems', init = initVehicleSystems },
    { name = 'ps-housing', init = initPsHousing },
    { name = 'klb-management', init = initKlbManagement },
    { name = 'ps-mdt', init = initPsMdt },
  }

  local successCount = 0

  for _, integration in ipairs(integrations) do
    local success = integration.init()
    if success then
      successCount = successCount + 1
    end
  end

  dbg('==========================================================')
  dbg(('%d/%d integrações ativadas com sucesso'):format(successCount, #integrations))
  dbg('==========================================================')
end)

--============================================================
-- EXPORTS
--============================================================
exports('TaxPurchase', SE.External.TaxPurchase)
exports('TaxTransfer', SE.External.TaxTransfer)
exports('ChargeIPVA', SE.External.ChargeIPVA)
exports('ChargeIPTU', SE.External.ChargeIPTU)
exports('CreateFine', SE.External.CreateFine)

-- Status das integrações
exports('GetIntegrationStatus', function()
  return {
    banking = SE.External.Banking.Enabled,
    inventory = SE.External.Inventory.Enabled,
    vehicles = SE.External.Vehicles.Enabled,
    housing = SE.External.Housing.Enabled,
    management = SE.External.Management.Enabled,
    police = SE.External.Police.Enabled,
  }
end)
