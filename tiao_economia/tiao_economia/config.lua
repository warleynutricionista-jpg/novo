Config = Config or {}

-- ============================================================
-- GERAL
-- ============================================================
Config.Debug = false
Config.Locale = 'pt-BR'

-- ============================================================
-- IMPOSTOS
-- ============================================================
Config.TaxMultiplierDefault = 1.0

-- Sistema de alíquotas progressivas (brasileiro)
Config.TaxBrackets = {
  { min = 0,      max = 2112,    rate = 0.00 },  -- Isento
  { min = 2112,   max = 2826,    rate = 0.075 }, -- 7,5%
  { min = 2826,   max = 3751,    rate = 0.15 },  -- 15%
  { min = 3751,   max = 4664,    rate = 0.225 }, -- 22,5%
  { min = 4664,   max = nil,     rate = 0.275 }, -- 27,5%
}

-- Catálogo de tributos (usado no painel admin)
Config.TaxCatalog = {
  {
    key = 'IPTU',
    label = 'IPTU (Imóvel)',
    mode = 'base_percent',
    percent = 0.3,
    description = 'Imposto sobre propriedade imobiliária'
  },
  {
    key = 'IPVA',
    label = 'IPVA (Veículo)',
    mode = 'base_percent',
    percent = 1.5,
    description = 'Imposto sobre veículos automotores'
  },
  {
    key = 'IRPF',
    label = 'Imposto de Renda',
    mode = 'progressive',
    description = 'Imposto progressivo sobre renda'
  },
  {
    key = 'ISS',
    label = 'ISS (Serviços)',
    mode = 'base_percent',
    percent = 2.0,
    description = 'Imposto sobre serviços prestados'
  },
  {
    key = 'ICMS',
    label = 'ICMS (Mercadorias)',
    mode = 'base_percent',
    percent = 12.0,
    description = 'Imposto sobre circulação de mercadorias'
  },
  {
    key = 'MULTA',
    label = 'Multa Administrativa',
    mode = 'fixed',
    fixed = 1000,
    description = 'Multas governamentais'
  },
  {
    key = 'TAXA_GOV',
    label = 'Taxa Governamental',
    mode = 'fixed',
    fixed = 500,
    description = 'Taxas diversas do governo'
  },
  {
    key = 'OUTRO',
    label = 'Outro Tributo',
    mode = 'fixed',
    fixed = 0,
    description = 'Lançamento manual'
  },
}

-- IVA / Taxa transacional (futuro: integrar com shops/banking)
Config.TransactionTax = {
  Enabled = false,
  Percent = 1.0,
  Min = 0,
  Max = 50000,
  ExemptAccounts = { 'cash' }, -- Isentar cash, taxar apenas bank
}

-- ============================================================
-- PERMISSÕES (Granular)
-- ============================================================
Config.Permissions = {
  -- ACE Permission
  Ace = 'space_economy.admin',
  
  -- QBOX Staff Metadata
  AllowStaffMeta = true,
  
  -- Permissões por Job + Grade mínimo
  Jobs = {
    ['government'] = { minGrade = 3 },
    ['police'] = { minGrade = 5 },
  },
  
  -- Permissões específicas (futuro)
  Granular = {
    ViewTreasury = { ace = 'space_economy.view_treasury' },
    ModifyTreasury = { ace = 'space_economy.modify_treasury' },
    IssueDebts = { ace = 'space_economy.issue_debts' },
    ViewLogs = { ace = 'space_economy.view_logs' },
  }
}

-- ============================================================
-- DÍVIDAS
-- ============================================================
Config.DebtSystem = {
  Enabled = true,
  
  -- Juros
  InterestDailyRate = 0.01, -- 1% ao dia
  CompoundInterest = false,  -- Juros compostos (false = simples)
  
  -- Períodos
  GraceHours = 24,              -- Carência antes de juros
  WarnEveryHours = 12,          -- Avisar player a cada X horas
  WarrantAfterDaysOverdue = 7,  -- Mandado após X dias de atraso
  
  -- Restrições (futuro)
  LockThreshold = 50000,        -- Acima disso, pode bloquear CNH, etc
  BlockVehicleSpawn = false,    -- Bloquear spawn de veículos se devedor
  BlockPropertyAccess = false,  -- Bloquear acesso a propriedades
  
  -- Parcelamento
  AllowInstallments = true,
  MaxInstallments = 12,
  MinInstallmentValue = 100,
  InstallmentFee = 0.05, -- 5% de taxa administrativa
}

-- Alertas de mandado
Config.WarrantAlert = {
  Enabled = true,
  UsePsDispatch = true,
  UsePsMdt = true,
  Title = 'Dívida Ativa',
  Message = 'Cidadão com dívida vencida há mais de 7 dias. Verificar pendências tributárias.',
  DispatchCode = '10-90',
}

-- ============================================================
-- TESOURO
-- ============================================================
Config.Treasury = {
  StartBalance = 0,
  MaxBalance = 999999999999, -- Limite máximo
  
  -- Auditoria
  LogAllTransactions = true,
  RequireReason = true,
  
  -- Notificações
  NotifyOnLowBalance = true,
  LowBalanceThreshold = 100000,
}

-- ============================================================
-- INFLAÇÃO
-- ============================================================
Config.Inflation = {
  Enabled = true,
  DefaultRate = 1.0,
  MinRate = 0.70,
  MaxRate = 2.00,
  
  -- Auto-ajuste (futuro: baseado em economia da cidade)
  AutoAdjust = false,
  AdjustIntervalHours = 24,
  TargetRange = { min = 0.95, max = 1.05 },
}

-- ============================================================
-- PERSISTÊNCIA
-- ============================================================
Config.Persistence = {
  IntervalMs = 60000, -- 1 minuto
  SaveOnShutdown = true,
  BackupOnStart = true,
}

-- ============================================================
-- LOGS
-- ============================================================
Config.Logging = {
  Enabled = true,
  MaxAge = 30, -- dias
  Categories = {
    'system', 'tax', 'debt', 'vault', 'admin', 'player'
  },
  
  -- Discord Webhook (opcional)
  Discord = {
    Enabled = false,
    Webhook = '',
    LogLevels = { 'admin', 'vault' }, -- Apenas críticos
  }
}

-- ============================================================
-- NUI / INTERFACE
-- ============================================================
Config.UI = {
  DefaultCurrency = 'BRL',
  CurrencySymbol = 'R$',
  DateFormat = '%d/%m/%Y %H:%M',
  
  -- Keybinds padrão
  Keybinds = {
    OpenTax = 'F7',
    OpenAdmin = 'F9',
  },
  
  -- Temas (futuro)
  Theme = 'dark',
}

-- ============================================================
-- INTEGRAÇÕES
-- ============================================================
Config.Integrations = {
  -- Banking
  Banking = {
    Enabled = true,
    Resource = 'auto', -- auto-detect ou 'ps-banking', 'qb-banking'
  },
  
  -- Dispatch
  Dispatch = {
    Enabled = true,
    Resource = 'ps-dispatch',
  },
  
  -- MDT
  MDT = {
    Enabled = true,
    Resource = 'ps-mdt',
  },
  
  -- Shops (futuro: taxar compras)
  Shops = {
    Enabled = false,
    TaxPurchases = false,
    TaxRate = 1.0,
  },
  
  -- Real Estate (futuro: IPTU automático)
  RealEstate = {
    Enabled = false,
    AutoIPTU = false,
    IPTUFrequencyDays = 30,
  },
  
  -- Garages (futuro: IPVA automático)
  Garages = {
    Enabled = false,
    AutoIPVA = false,
    IPVAFrequencyDays = 365,
  },
}

-- ============================================================
-- WEBHOOKS / NOTIFICAÇÕES EXTERNAS
-- ============================================================
Config.Webhooks = {
  Treasury = '',
  Debts = '',
  Admin = '',
}

-- ============================================================
-- SISTEMAS AVANÇADOS (Agora Ativos)
-- ============================================================
Config.AdvancedSystems = {
  -- Sistema de crédito/score
  CreditScore = true,
  
  -- Empréstimos governamentais
  GovernmentLoans = true,
  
  -- Parcelamento de dívidas
  Installments = true,
  
  -- Taxação automática
  AutoTax = true,
}

-- ============================================================
-- EXPERIMENTAL (Recursos futuros)
-- ============================================================
Config.Experimental = {
  -- Programas sociais (bolsa família, etc)
  SocialPrograms = false,
  
  -- Mercado de títulos públicos
  PublicBonds = false,
  
  -- Previdência social
  SocialSecurity = false,
}