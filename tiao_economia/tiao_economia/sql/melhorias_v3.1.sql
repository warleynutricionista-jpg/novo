-- ============================================================
-- Space Economy v3.1 - Melhorias SQL
-- Tabelas para: Backups, Auditoria, Métricas, Recompensas
-- ============================================================

-- ============================================================
-- 1. TABELA DE BACKUPS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_backups` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `backup_date` DATE NOT NULL,
    `state_data` LONGTEXT NOT NULL COMMENT 'JSON do estado econômico',
    `vault_balance` BIGINT DEFAULT 0 COMMENT 'Saldo do tesouro',
    `metrics` LONGTEXT NULL COMMENT 'JSON com métricas do momento',
    `reason` VARCHAR(100) DEFAULT 'auto' COMMENT 'Motivo do backup (auto, manual, shutdown, etc)',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_backup_date` (`backup_date`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 2. TABELA DE AUDITORIA
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_audit_log` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `admin_citizenid` VARCHAR(50) NOT NULL,
    `admin_name` VARCHAR(100) NULL,
    `action` VARCHAR(100) NOT NULL COMMENT 'Ação realizada',
    `details` LONGTEXT NULL COMMENT 'JSON com detalhes da ação',
    `ip_address` VARCHAR(50) NULL,
    `target_citizenid` VARCHAR(50) NULL COMMENT 'CitizenID afetado (se houver)',
    `amount` BIGINT NULL COMMENT 'Valor envolvido (se aplicável)',
    `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_admin` (`admin_citizenid`),
    INDEX `idx_action` (`action`),
    INDEX `idx_timestamp` (`timestamp`),
    INDEX `idx_target` (`target_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 3. TABELA DE MÉTRICAS DIÁRIAS
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_daily_metrics` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `metric_date` DATE NOT NULL,
    `total_collected` BIGINT DEFAULT 0 COMMENT 'Total arrecadado',
    `total_paid_debts` BIGINT DEFAULT 0 COMMENT 'Total de dívidas pagas',
    `total_new_debts` BIGINT DEFAULT 0 COMMENT 'Total de novas dívidas',
    `total_tax_iptu` BIGINT DEFAULT 0 COMMENT 'Total de IPTU',
    `total_tax_ipva` BIGINT DEFAULT 0 COMMENT 'Total de IPVA',
    `total_tax_other` BIGINT DEFAULT 0 COMMENT 'Outros impostos',
    `vault_balance_start` BIGINT DEFAULT 0 COMMENT 'Saldo inicial do dia',
    `vault_balance_end` BIGINT DEFAULT 0 COMMENT 'Saldo final do dia',
    `active_debtors` INT DEFAULT 0 COMMENT 'Devedores ativos',
    `transactions_count` INT DEFAULT 0 COMMENT 'Número de transações',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_metric_date` (`metric_date`),
    INDEX `idx_metric_date` (`metric_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 4. TABELA DE RECOMPENSAS (BOM PAGADOR)
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_rewards` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `payments_on_time` INT DEFAULT 0 COMMENT 'Pagamentos em dia',
    `payments_late` INT DEFAULT 0 COMMENT 'Pagamentos atrasados',
    `current_streak` INT DEFAULT 0 COMMENT 'Sequência atual de pagamentos em dia',
    `best_streak` INT DEFAULT 0 COMMENT 'Melhor sequência',
    `total_paid` BIGINT DEFAULT 0 COMMENT 'Total pago até agora',
    `discount_level` INT DEFAULT 0 COMMENT 'Nível de desconto (0-3)',
    `last_payment_date` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_citizenid` (`citizenid`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_discount_level` (`discount_level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 5. TABELA DE HISTÓRICO DE PARCELAS (MELHORADA)
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_installment_history` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `plan_id` BIGINT NOT NULL COMMENT 'ID do plano de parcelamento',
    `citizenid` VARCHAR(50) NOT NULL,
    `installment_number` INT NOT NULL COMMENT 'Número da parcela (1, 2, 3...)',
    `amount` BIGINT NOT NULL COMMENT 'Valor da parcela',
    `paid_amount` BIGINT DEFAULT 0 COMMENT 'Valor efetivamente pago',
    `due_date` DATE NOT NULL COMMENT 'Data de vencimento',
    `paid_date` TIMESTAMP NULL COMMENT 'Data de pagamento',
    `status` ENUM('pending', 'paid', 'late', 'canceled') DEFAULT 'pending',
    `late_fee` BIGINT DEFAULT 0 COMMENT 'Multa por atraso',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_plan_id` (`plan_id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`),
    INDEX `idx_due_date` (`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 6. TABELA DE NOTIFICAÇÕES ENVIADAS (TRACKING)
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_notifications_sent` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `notification_type` VARCHAR(50) NOT NULL COMMENT 'debt_reminder, installment_due, etc',
    `content` TEXT NULL COMMENT 'Conteúdo da notificação',
    `sent_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_type` (`notification_type`),
    INDEX `idx_sent_at` (`sent_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 7. ÍNDICES ADICIONAIS EM TABELAS EXISTENTES
-- ============================================================

-- Melhorar performance em space_economy_debts
ALTER TABLE `space_economy_debts`
    ADD INDEX IF NOT EXISTS `idx_status_citizenid` (`status`, `citizenid`),
    ADD INDEX IF NOT EXISTS `idx_due_at` (`due_at`),
    ADD INDEX IF NOT EXISTS `idx_amount` (`amount`);

-- Melhorar performance em space_economy_logs
ALTER TABLE `space_economy_logs`
    ADD INDEX IF NOT EXISTS `idx_category_timestamp` (`category`, `timestamp`),
    ADD INDEX IF NOT EXISTS `idx_actor` (`actor_citizenid`),
    ADD INDEX IF NOT EXISTS `idx_target` (`target_citizenid`);

-- ============================================================
-- 8. VIEWS ÚTEIS PARA RELATÓRIOS
-- ============================================================

-- View: Top Devedores
CREATE OR REPLACE VIEW `vw_space_economy_top_debtors` AS
SELECT
    citizenid,
    SUM(amount) as total_debt,
    COUNT(*) as debt_count,
    MAX(due_at) as latest_due_date,
    MIN(created_at) as oldest_debt_date
FROM space_economy_debts
WHERE status = 'active'
GROUP BY citizenid
ORDER BY total_debt DESC
LIMIT 100;

-- View: Métricas do Mês Atual
CREATE OR REPLACE VIEW `vw_space_economy_current_month` AS
SELECT
    DATE_FORMAT(metric_date, '%Y-%m') as month,
    SUM(total_collected) as month_collected,
    SUM(total_paid_debts) as month_paid_debts,
    SUM(total_new_debts) as month_new_debts,
    SUM(transactions_count) as month_transactions,
    AVG(active_debtors) as avg_debtors
FROM space_economy_daily_metrics
WHERE metric_date >= DATE_FORMAT(NOW(), '%Y-%m-01')
GROUP BY DATE_FORMAT(metric_date, '%Y-%m');

-- View: Bons Pagadores (Top Recompensas)
CREATE OR REPLACE VIEW `vw_space_economy_good_payers` AS
SELECT
    citizenid,
    payments_on_time,
    payments_late,
    current_streak,
    best_streak,
    total_paid,
    discount_level,
    last_payment_date,
    ROUND((payments_on_time / NULLIF(payments_on_time + payments_late, 0)) * 100, 2) as payment_rate
FROM space_economy_rewards
WHERE payments_on_time > 0
ORDER BY discount_level DESC, current_streak DESC
LIMIT 100;

-- ============================================================
-- 9. STORED PROCEDURES ÚTEIS
-- ============================================================

-- Procedure: Atualizar métricas diárias
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS `sp_update_daily_metrics`()
BEGIN
    DECLARE current_date DATE;
    SET current_date = CURDATE();

    -- Inserir ou atualizar métricas do dia
    INSERT INTO space_economy_daily_metrics (
        metric_date,
        total_collected,
        total_paid_debts,
        total_new_debts,
        total_tax_iptu,
        total_tax_ipva,
        transactions_count,
        active_debtors
    )
    SELECT
        current_date,
        COALESCE(SUM(CASE WHEN category = 'tax' AND amount > 0 THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN category = 'debt' AND message LIKE '%pago%' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN category = 'debt' AND message LIKE '%criada%' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN message LIKE '%IPTU%' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN message LIKE '%IPVA%' THEN amount ELSE 0 END), 0),
        COUNT(*),
        (SELECT COUNT(DISTINCT citizenid) FROM space_economy_debts WHERE status = 'active')
    FROM space_economy_logs
    WHERE DATE(timestamp) = current_date
    ON DUPLICATE KEY UPDATE
        total_collected = VALUES(total_collected),
        total_paid_debts = VALUES(total_paid_debts),
        total_new_debts = VALUES(total_new_debts),
        total_tax_iptu = VALUES(total_tax_iptu),
        total_tax_ipva = VALUES(total_tax_ipva),
        transactions_count = VALUES(transactions_count),
        active_debtors = VALUES(active_debtors),
        updated_at = NOW();
END$$
DELIMITER ;

-- ============================================================
-- 10. EVENTOS AUTOMÁTICOS (LIMPEZA)
-- ============================================================

-- Evento: Limpar notificações antigas (>90 dias)
CREATE EVENT IF NOT EXISTS `evt_cleanup_old_notifications`
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY
DO
    DELETE FROM space_economy_notifications_sent
    WHERE sent_at < DATE_SUB(NOW(), INTERVAL 90 DAY);

-- Evento: Atualizar métricas diárias
CREATE EVENT IF NOT EXISTS `evt_update_daily_metrics`
ON SCHEDULE EVERY 1 HOUR
DO
    CALL sp_update_daily_metrics();

-- ============================================================
-- FIM
-- ============================================================
