fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'space_economy (QBOX Advanced v3.0)'
description 'Sistema econômico completo: impostos, dívidas, parcelamento, crédito, empréstimos, taxação automática'
version '3.0.0'

-- ============================================================
-- SHARED (Client + Server)
-- ============================================================
shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'shared/bridge.lua',
}

-- ============================================================
-- SERVER
-- ============================================================
server_scripts {
  '@oxmysql/lib/MySQL.lua',

  -- Core
  'server/init.lua',
  'server/state.lua',
  'server/locks.lua',
  
  -- Sistemas Base
  'server/treasury.lua',
  'server/tax.lua',
  'server/charcache.lua',
  'server/integrations.lua',
  
  -- Sistemas Avançados (NOVOS)
  'server/debts.lua',           -- Melhorado
  'server/installments.lua',    -- NOVO: Parcelamento
  'server/credit_score.lua',    -- NOVO: Score de crédito
  'server/loans.lua',           -- NOVO: Empréstimos
  'server/auto_tax.lua',        -- NOVO: Taxação automática
  'server/reports.lua',         -- NOVO: Relatórios e analytics
  
  -- Admin & Events
  'server/admin.lua',
  'server/events.lua',
}

-- ============================================================
-- CLIENT
-- ============================================================
client_scripts {
  'client/init.lua',
  'client/nui.lua',
  'client/commands.lua',
}

-- ============================================================
-- NUI
-- ============================================================
ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
}

-- ============================================================
-- DEPENDENCIES
-- ============================================================
dependencies {
  'ox_lib',
  'oxmysql',
  'qbx_core',
}

-- ============================================================
-- EXPORTS (Para outros recursos)
-- ============================================================

-- Treasury
exports {
  'GetTreasuryBalance',
  'AddToTreasury',
  'RemoveFromTreasury',
}

-- Tax
exports {
  'CalculateTax',
  'ApplyTax',
}

-- Debts
exports {
  'CreateDebt',
  'PayDebt',
  'GetPlayerDebts',
}

-- Installments
exports {
  'CreateInstallmentPlan',
  'PayInstallment',
}

-- Credit Score
exports {
  'GetCreditScore',
  'UpdateCreditScore',
}

-- Loans
exports {
  'SimulateLoan',
  'RequestLoan',
  'GetPlayerLoans',
}

-- Auto Tax
exports {
  'TaxVehiclePurchase',
  'TaxPropertyPurchase',
  'TaxService',
  'TaxShopPurchase',
}

-- Reports
exports {
  'GetEconomyReport',
  'GetDailyMetrics',
}