-- ============================================
-- TABELA DE TRACKING DE TRANSAÇÕES PROCESSADAS
-- ============================================
-- Esta tabela mantém registro de todas as transações já processadas
-- para evitar duplicação de impostos

CREATE TABLE IF NOT EXISTS `space_economy_processed_transactions` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `source_system` VARCHAR(50) NOT NULL COMMENT 'Sistema de origem: ps-banking, ox_inventory, vehicles, housing, etc',
    `transaction_id` VARCHAR(100) NOT NULL COMMENT 'ID da transação no sistema de origem',
    `transaction_type` VARCHAR(50) NOT NULL COMMENT 'Tipo: transfer, withdraw, purchase, vehicle_buy, property_buy, etc',
    `citizenid` VARCHAR(64) NOT NULL COMMENT 'ID do cidadão que fez a transação',
    `amount` BIGINT NOT NULL COMMENT 'Valor da transação original',
    `tax_amount` BIGINT NOT NULL COMMENT 'Valor do imposto cobrado',
    `tax_type` VARCHAR(20) NOT NULL COMMENT 'Tipo de imposto: IOF, ICMS, IPVA, IPTU, ISS, IRPF',
    `debt_id` INT NULL COMMENT 'ID da dívida criada em space_economy_debts',
    `transaction_date` TIMESTAMP NOT NULL COMMENT 'Data da transação original',
    `processed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Data/hora do processamento',
    `metadata` LONGTEXT NULL COMMENT 'Dados adicionais da transação em JSON',

    -- Índices para performance
    INDEX `idx_source_transaction` (`source_system`, `transaction_id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_transaction_date` (`transaction_date`),
    INDEX `idx_processed_at` (`processed_at`),
    INDEX `idx_tax_type` (`tax_type`),
    UNIQUE KEY `unique_transaction` (`source_system`, `transaction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- TABELA DE CONFIGURAÇÃO DE INTEGRAÇÃO
-- ============================================
CREATE TABLE IF NOT EXISTS `space_economy_integration_config` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `source_system` VARCHAR(50) NOT NULL UNIQUE,
    `enabled` TINYINT(1) DEFAULT 1 COMMENT '1=Ativo, 0=Desabilitado',
    `table_name` VARCHAR(100) NOT NULL COMMENT 'Nome da tabela no banco do recurso',
    `query_interval` INT DEFAULT 60 COMMENT 'Intervalo de verificação em segundos',
    `last_check` TIMESTAMP NULL COMMENT 'Última verificação realizada',
    `last_transaction_id` VARCHAR(100) NULL COMMENT 'Último ID de transação processado',
    `last_transaction_date` TIMESTAMP NULL COMMENT 'Data da última transação processada',
    `total_processed` INT DEFAULT 0 COMMENT 'Total de transações processadas',
    `total_errors` INT DEFAULT 0 COMMENT 'Total de erros encontrados',
    `config_json` LONGTEXT NULL COMMENT 'Configurações específicas em JSON',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- INSERIR CONFIGURAÇÕES PADRÃO
-- ============================================
INSERT INTO `space_economy_integration_config`
(`source_system`, `enabled`, `table_name`, `query_interval`, `config_json`)
VALUES
-- PS-Banking: Transferências e saques
('ps-banking', 1, 'phone_transactions', 60, JSON_OBJECT(
    'tax_type', 'IOF',
    'tax_rate', 0.5,
    'min_tax', 10,
    'transaction_types', JSON_ARRAY('transfer', 'withdraw'),
    'amount_field', 'amount',
    'player_field', 'citizenid'
)),

-- OX Inventory: Compras em lojas
('ox_inventory', 1, 'ox_inventory_transactions', 60, JSON_OBJECT(
    'tax_type', 'ICMS',
    'tax_rate', 12.0,
    'exempt_items', JSON_ARRAY('bread', 'water'),
    'transaction_types', JSON_ARRAY('purchase', 'buy'),
    'amount_field', 'price',
    'player_field', 'owner'
)),

-- Veículos: Compra de veículos
('vehicles', 1, 'player_vehicles', 60, JSON_OBJECT(
    'tax_type', 'IPVA',
    'tax_rate', 1.5,
    'amount_field', 'price',
    'player_field', 'citizenid',
    'vehicle_field', 'plate'
)),

-- Housing: Compra de propriedades
('housing', 1, 'player_houses', 60, JSON_OBJECT(
    'tax_type', 'IPTU',
    'tax_rate', 0.3,
    'amount_field', 'price',
    'player_field', 'citizenid',
    'property_field', 'house'
))
ON DUPLICATE KEY UPDATE
    `table_name` = VALUES(`table_name`),
    `config_json` = VALUES(`config_json`);

-- ============================================
-- VIEWS ÚTEIS PARA ANÁLISE
-- ============================================

-- View para ver transações processadas agrupadas por tipo
CREATE OR REPLACE VIEW `v_space_economy_transactions_summary` AS
SELECT
    `source_system`,
    `tax_type`,
    COUNT(*) as `total_transactions`,
    SUM(`amount`) as `total_amount`,
    SUM(`tax_amount`) as `total_tax_collected`,
    MIN(`transaction_date`) as `first_transaction`,
    MAX(`transaction_date`) as `last_transaction`,
    DATE(`transaction_date`) as `transaction_day`
FROM `space_economy_processed_transactions`
GROUP BY `source_system`, `tax_type`, DATE(`transaction_date`)
ORDER BY `transaction_date` DESC;

-- View para status das integrações
CREATE OR REPLACE VIEW `v_space_economy_integration_status` AS
SELECT
    i.`source_system`,
    i.`enabled`,
    i.`last_check`,
    i.`total_processed`,
    i.`total_errors`,
    TIMESTAMPDIFF(SECOND, i.`last_check`, NOW()) as `seconds_since_check`,
    COUNT(t.`id`) as `transactions_today`
FROM `space_economy_integration_config` i
LEFT JOIN `space_economy_processed_transactions` t
    ON t.`source_system` = i.`source_system`
    AND DATE(t.`transaction_date`) = CURDATE()
GROUP BY i.`source_system`;
