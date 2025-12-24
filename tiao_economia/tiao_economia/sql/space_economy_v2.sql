-- ============================================================
-- space_economy v3.0 - Instalação Completa
-- Sistema econômico avançado para QBox/QBCore
-- ============================================================

-- ============================================================
-- TABELAS CORE
-- ============================================================

-- Estado global da economia
CREATE TABLE IF NOT EXISTS `space_economy` (
  `id` INT PRIMARY KEY,
  `vaultBalance` BIGINT NOT NULL DEFAULT 0,
  `inflationRate` DOUBLE NOT NULL DEFAULT 1.0,
  `taxMultiplier` DOUBLE NOT NULL DEFAULT 1.0,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Estado key-value (settings, etc)
CREATE TABLE IF NOT EXISTS `space_economy_state` (
  `key` VARCHAR(64) PRIMARY KEY,
  `value` LONGTEXT,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insere registro inicial
INSERT IGNORE INTO `space_economy` (`id`, `vaultBalance`, `inflationRate`, `taxMultiplier`)
VALUES (1, 0, 1.0, 1.0);

-- ============================================================
-- CACHE DE PERSONAGENS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_charcache` (
  `citizenid` VARCHAR(64) PRIMARY KEY,
  `name` VARCHAR(120) NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE DÍVIDAS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_debts` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL DEFAULT 0,
  `original_amount` BIGINT NOT NULL DEFAULT 0,
  `reason` VARCHAR(200) NOT NULL DEFAULT 'Imposto',
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `interest_rate` DECIMAL(10,4) NOT NULL DEFAULT 0.01,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `due_at` TIMESTAMP NULL,
  `grace_until` TIMESTAMP NULL,
  `paid_at` TIMESTAMP NULL,
  `last_interest_at` TIMESTAMP NULL,
  `meta` LONGTEXT NULL,
  INDEX `idx_citizen_status` (`citizenid`, `status`),
  INDEX `idx_status_due` (`status`, `due_at`),
  INDEX `idx_grace` (`grace_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_debt_payments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `debt_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL,
  `payment_type` VARCHAR(20) NOT NULL DEFAULT 'full',
  `installment_number` INT NULL,
  `paid_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `meta` LONGTEXT NULL,
  INDEX `idx_debt` (`debt_id`),
  INDEX `idx_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE PARCELAMENTO
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_installment_plans` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `debt_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `original_amount` BIGINT NOT NULL,
  `total_amount` BIGINT NOT NULL,
  `installments` INT NOT NULL,
  `installment_value` BIGINT NOT NULL,
  `paid_installments` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `fee_percent` DECIMAL(10,4) NOT NULL DEFAULT 0.05,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `next_due_at` TIMESTAMP NULL,
  `completed_at` TIMESTAMP NULL,
  `meta` LONGTEXT NULL,
  INDEX `idx_citizen_status` (`citizenid`, `status`),
  INDEX `idx_debt` (`debt_id`),
  INDEX `idx_next_due` (`next_due_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_installments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `plan_id` INT NOT NULL,
  `installment_number` INT NOT NULL,
  `amount` BIGINT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `due_at` TIMESTAMP NOT NULL,
  `paid_at` TIMESTAMP NULL,
  `meta` LONGTEXT NULL,
  INDEX `idx_plan` (`plan_id`),
  INDEX `idx_status_due` (`status`, `due_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE CREDIT SCORE
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_credit_scores` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL UNIQUE,
  `score` INT NOT NULL DEFAULT 500,
  `rating` VARCHAR(20) NOT NULL DEFAULT 'Regular',
  `payment_history_score` DECIMAL(5,2) NOT NULL DEFAULT 0,
  `debt_ratio_score` DECIMAL(5,2) NOT NULL DEFAULT 0,
  `credit_age_score` DECIMAL(5,2) NOT NULL DEFAULT 0,
  `credit_mix_score` DECIMAL(5,2) NOT NULL DEFAULT 0,
  `recent_activity_score` DECIMAL(5,2) NOT NULL DEFAULT 0,
  `total_payments` INT NOT NULL DEFAULT 0,
  `on_time_payments` INT NOT NULL DEFAULT 0,
  `late_payments` INT NOT NULL DEFAULT 0,
  `total_borrowed` BIGINT NOT NULL DEFAULT 0,
  `total_paid` BIGINT NOT NULL DEFAULT 0,
  `active_debts` INT NOT NULL DEFAULT 0,
  `credit_age_days` INT NOT NULL DEFAULT 0,
  `last_updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `meta` LONGTEXT NULL,
  INDEX `idx_score` (`score`),
  INDEX `idx_rating` (`rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_score_history` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `old_score` INT NOT NULL,
  `new_score` INT NOT NULL,
  `change_reason` VARCHAR(200) NOT NULL,
  `event_type` VARCHAR(50) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_citizen` (`citizenid`),
  INDEX `idx_date` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE EMPRÉSTIMOS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_loans` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL,
  `disbursed_amount` BIGINT NOT NULL,
  `balance` BIGINT NOT NULL,
  `interest_rate` DECIMAL(10,4) NOT NULL,
  `term_months` INT NOT NULL,
  `monthly_payment` BIGINT NOT NULL,
  `paid_installments` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `credit_score_at_approval` INT NOT NULL,
  `purpose` VARCHAR(200) NULL,
  `approved_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `disbursed_at` TIMESTAMP NULL,
  `completed_at` TIMESTAMP NULL,
  `defaulted_at` TIMESTAMP NULL,
  `next_due_at` TIMESTAMP NULL,
  `meta` LONGTEXT NULL,
  INDEX `idx_citizen_status` (`citizenid`, `status`),
  INDEX `idx_status` (`status`),
  INDEX `idx_next_due` (`next_due_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_loan_payments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `loan_id` INT NOT NULL,
  `installment_number` INT NOT NULL,
  `amount` BIGINT NOT NULL,
  `principal` BIGINT NOT NULL,
  `interest` BIGINT NOT NULL,
  `balance_after` BIGINT NOT NULL,
  `paid_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_loan` (`loan_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE RELATÓRIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_daily_metrics` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `date` DATE NOT NULL UNIQUE,
  `vault_balance` BIGINT NOT NULL DEFAULT 0,
  `total_collected` BIGINT NOT NULL DEFAULT 0,
  `total_debts` BIGINT NOT NULL DEFAULT 0,
  `active_debtors` INT NOT NULL DEFAULT 0,
  `transactions_count` INT NOT NULL DEFAULT 0,
  `avg_transaction` BIGINT NOT NULL DEFAULT 0,
  `inflation_rate` DECIMAL(10,4) NOT NULL DEFAULT 1.0,
  `tax_multiplier` DECIMAL(10,4) NOT NULL DEFAULT 1.0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SISTEMA DE LOGS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_logs` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `category` VARCHAR(50) NOT NULL,
  `message` TEXT NOT NULL,
  `actor_citizenid` VARCHAR(50) NULL,
  `target_citizenid` VARCHAR(50) NULL,
  `amount` BIGINT NULL,
  `metadata` LONGTEXT NULL,
  `meta` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_timestamp` (`timestamp`),
  INDEX `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- MIGRAÇÃO: Adiciona colunas faltantes em tabelas existentes
-- ============================================================

-- Adiciona last_ipva_at na tabela de veículos (se existir)
SET @dbname = DATABASE();
SET @tablename = 'player_vehicles';
SET @columnname = 'last_ipva_at';
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname
   AND TABLE_NAME = @tablename
   AND COLUMN_NAME = @columnname) > 0,
  'SELECT 1',
  CONCAT('ALTER TABLE ', @tablename, ' ADD COLUMN ', @columnname, ' TIMESTAMP NULL')
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- Adiciona last_iptu_at na tabela de propriedades (se existir)
SET @tablename = 'player_houses';
SET @columnname = 'last_iptu_at';
SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname
   AND TABLE_NAME = @tablename
   AND COLUMN_NAME = @columnname) > 0,
  'SELECT 1',
  CONCAT('ALTER TABLE ', @tablename, ' ADD COLUMN ', @columnname, ' TIMESTAMP NULL')
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- ============================================================
-- VIEWS (Facilitam consultas complexas)
-- ============================================================

-- View: Devedores ativos com totais
CREATE OR REPLACE VIEW `v_active_debtors` AS
SELECT 
  d.citizenid,
  COALESCE(c.name, 'Desconhecido') as player_name,
  COUNT(DISTINCT d.id) as debt_count,
  SUM(d.amount) as total_owed,
  MIN(d.due_at) as earliest_due,
  MAX(d.created_at) as last_debt_created
FROM space_economy_debts d
LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
WHERE d.status = 'active'
GROUP BY d.citizenid;

-- View: Resumo de empréstimos ativos
CREATE OR REPLACE VIEW `v_active_loans` AS
SELECT 
  l.citizenid,
  COALESCE(c.name, 'Desconhecido') as player_name,
  COUNT(*) as loan_count,
  SUM(l.balance) as total_balance,
  SUM(l.monthly_payment) as total_monthly_payment
FROM space_economy_loans l
LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
WHERE l.status = 'active'
GROUP BY l.citizenid;

-- ============================================================
-- TRIGGERS (Automação)
-- ============================================================

-- Trigger: Atualiza cache de nome ao criar dívida
DELIMITER $$
CREATE TRIGGER IF NOT EXISTS `trg_debt_update_cache`
AFTER INSERT ON `space_economy_debts`
FOR EACH ROW
BEGIN
  -- Atualiza timestamp no cache (força refresh)
  UPDATE space_economy_charcache 
  SET updated_at = CURRENT_TIMESTAMP
  WHERE citizenid = NEW.citizenid;
END$$
DELIMITER ;

-- ============================================================
-- PROCEDURES (Facilitam operações complexas)
-- ============================================================

-- Procedure: Limpa logs antigos
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS `sp_cleanup_old_logs`(IN days INT)
BEGIN
  DELETE FROM space_economy_logs
  WHERE timestamp < DATE_SUB(NOW(), INTERVAL days DAY);
  
  SELECT ROW_COUNT() as deleted_rows;
END$$
DELIMITER ;

-- Procedure: Relatório de arrecadação mensal
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS `sp_monthly_collection_report`(IN year INT, IN month INT)
BEGIN
  SELECT 
    DATE(paid_at) as date,
    COUNT(*) as transactions,
    SUM(amount) as total_collected
  FROM space_economy_debt_payments
  WHERE YEAR(paid_at) = year 
    AND MONTH(paid_at) = month
  GROUP BY DATE(paid_at)
  ORDER BY date;
END$$
DELIMITER ;

-- ============================================================
-- ÍNDICES ADICIONAIS (Performance)
-- ============================================================

-- Otimiza consultas por data
CREATE INDEX IF NOT EXISTS `idx_debts_created` ON `space_economy_debts`(`created_at`);
CREATE INDEX IF NOT EXISTS `idx_payments_paid` ON `space_economy_debt_payments`(`paid_at`);
CREATE INDEX IF NOT EXISTS `idx_loans_created` ON `space_economy_loans`(`created_at`);

-- ============================================================
-- DADOS INICIAIS (Opcional)
-- ============================================================

-- Insere settings padrão
INSERT IGNORE INTO `space_economy_state` (`key`, `value`)
VALUES ('settings', '{"mode":{"inflation":"auto","taxrate":"auto"},"manual":{"inflation":1.0,"taxrate":100},"ui":{}}');

-- ============================================================
-- FIM DA INSTALAÇÃO
-- ============================================================
SELECT 'Instalação completa do space_economy v3.0 concluída!' as status;