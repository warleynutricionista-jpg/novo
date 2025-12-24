--============================================================
-- space_economy - server/tax.lua
-- Imposto progressivo configurável (Config.TaxBrackets)
-- Exports: CalculateTax / GetInflationRate / GetTaxMultiplier
--============================================================
SE = SE or {}
SE.Tax = SE.Tax or {}

local U = SE.Util
local S = SE.State

local function defaultBrackets()
  return {
    { min = 0,      max = 5000,    rate = 0.10 },
    { min = 5000,   max = 25000,   rate = 0.15 },
    { min = 25000,  max = 100000,  rate = 0.20 },
    { min = 100000, max = nil,     rate = 0.25 },
  }
end

local function sanitizeBrackets(brackets)
  if type(brackets) ~= 'table' or #brackets == 0 then
    return defaultBrackets()
  end

  local out = {}
  for _, br in ipairs(brackets) do
    if type(br) == 'table' then
      local minv = U.toNumber(br.min, 0)
      local maxv = br.max ~= nil and U.toNumber(br.max, nil) or nil
      local rate = U.toNumber(br.rate, 0)

      if minv < 0 then minv = 0 end
      if maxv ~= nil and maxv <= minv then maxv = nil end
      if rate < 0 then rate = 0 end

      out[#out+1] = { min = minv, max = maxv, rate = rate }
    end
  end

  if #out == 0 then return defaultBrackets() end

  table.sort(out, function(a, b)
    return (a.min or 0) < (b.min or 0)
  end)

  return out
end

local function getBrackets()
  return sanitizeBrackets(Config and Config.TaxBrackets)
end

--============================================================
-- Cálculo progressivo (faixa por faixa)
--============================================================
function SE.Tax.Calculate(amount)
  amount = U.toNumber(amount, 0)
  if amount <= 0 then return 0 end

  local tax = 0.0
  local brackets = getBrackets()

  for i = 1, #brackets do
    local br = brackets[i]
    local minv = U.toNumber(br.min, 0)
    local maxv = br.max ~= nil and U.toNumber(br.max, nil) or nil
    local rate = U.toNumber(br.rate, 0)

    if amount > minv and rate > 0 then
      local upper = maxv or amount
      local taxable = math.min(amount, upper) - minv
      if taxable > 0 then
        tax = tax + (taxable * rate)
      end
    end
  end

  local mult = U.toNumber(S.taxMultiplier, Config and Config.TaxMultiplierDefault or 1.0)
  tax = tax * mult

  return U.toInt(tax, 0)
end

--============================================================
-- Exports (compatibilidade)
--============================================================
exports('CalculateTax', function(v)
  return SE.Tax.Calculate(v)
end)

exports('GetInflationRate', function()
  return U.toNumber(S.inflationRate, 1.0)
end)

exports('GetTaxMultiplier', function()
  return U.toNumber(S.taxMultiplier, 1.0)
end)
