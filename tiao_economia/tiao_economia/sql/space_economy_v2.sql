CREATE TABLE IF NOT EXISTS space_economy_state (
  k VARCHAR(64) PRIMARY KEY,
  v LONGTEXT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS space_economy (
  id INT PRIMARY KEY,
  vaultBalance BIGINT NOT NULL DEFAULT 0,
  inflationRate DOUBLE NOT NULL DEFAULT 1.0,
  taxMultiplier DOUBLE NOT NULL DEFAULT 1.0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT IGNORE INTO space_economy (id, vaultBalance, inflationRate, taxMultiplier)
VALUES (1, 0, 1.0, 1.0);

CREATE TABLE IF NOT EXISTS space_economy_charcache (
  citizenid VARCHAR(64) PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS space_economy_debts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  amount BIGINT NOT NULL DEFAULT 0,
  reason VARCHAR(120) NOT NULL DEFAULT 'Imposto',
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  due_at TIMESTAMP NULL,
  grace_until TIMESTAMP NULL,
  meta LONGTEXT NULL,
  INDEX idx_citizen_status (citizenid, status),
  INDEX idx_status_due (status, due_at)
);
