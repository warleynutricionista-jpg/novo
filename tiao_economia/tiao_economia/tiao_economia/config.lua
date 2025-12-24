Config = Config or {}

-- ============================================================
-- Geral
-- ============================================================
Config.Debug = false

-- ============================================================
-- Impostos
-- ============================================================
Config.TaxMultiplierDefault = 1.0

-- Imposto progressivo (rate em decimal: 0.10 = 10%)
Config.TaxBrackets = {
  { min = 0,      max = 5000,    rate = 0.10 },
  { min = 5000,   max = 25000,   rate = 0.15 },
  { min = 25000,  max = 100000,  rate = 0.20 },
  { min = 100000, max = nil,     rate = 0.25 },
}

-- (stub) IVA / taxa de transação (quando integrar ps-banking/shops)
Config.TransactionTax = {
  Enabled = false,
  Percent = 1.0,     -- 1% (em porcentagem)
  Min = 0,
  Max = 50000
}

-- ============================================================
-- Permissões
-- ============================================================
Config.Permissions = {
  -- ACE: add_ace group.admin space_economy.admin allow
  Ace = 'space_economy.admin',

  -- QBOX staff metadata: PlayerData.metadata.isstaff == true
  AllowStaffMeta = true,

  -- Permissão por job/grade (QBCore/QBX)
  Jobs = {
    -- ['government'] = { minGrade = 3 },
    -- ['police'] = { minGrade = 5 },
  }
}

-- ============================================================
-- Dívidas
-- ============================================================
Config.DebtSystem = {
  Enabled = true,
  InterestDailyRate = 0.01,      -- 1% ao dia (decimal)
  GraceHours = 24,               -- carência
  WarnEveryHours = 12,           -- aviso recorrente
  WarrantAfterDaysOverdue = 7,   -- stub (ps-dispatch/ps-mdt)
  LockThreshold = 50000,         -- stub (bloqueios por dívida)
}

Config.WarrantAlert = {
  Enabled = true,
  UsePsDispatch = true,
  UsePsMdt = true,
  Title = 'Dívida Ativa',
  Message = 'Cidadão com dívida ativa em aberto. Verifique pendências tributárias.'
}

-- ============================================================
-- Tesouro
-- ============================================================
Config.Treasury = {
  StartBalance = 0
}

-- ============================================================
-- Inflação
-- ============================================================
Config.Inflation = {
  Enabled = true,
  DefaultRate = 1.0,
  MinRate = 0.80,
  MaxRate = 1.50
}

-- ============================================================
-- Persistência
-- ============================================================
Config.Persistence = {
  IntervalMs = 60000
}

-- ============================================================
-- Logs
-- ============================================================
Config.Logging = {
  Enabled = true
}
