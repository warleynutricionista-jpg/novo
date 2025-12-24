--============================================================
-- space_economy - server/backup.lua
-- Sistema de Backup Automático com Restauração
-- MELHORIA CRÍTICA #3 - Segurança +100%
--============================================================
SE = SE or {}
SE.Backup = SE.Backup or {}

local U = SE.Util

--============================================================
-- Configuração
--============================================================
local Config = {
    Enabled = true,
    IntervalHours = 24,            -- Backup a cada 24 horas
    RetentionDays = 30,            -- Manter backups por 30 dias
    BackupOnShutdown = true,       -- Backup ao desligar servidor
    BackupOnStart = false,         -- Backup ao iniciar (opcional)
    MinIntervalMinutes = 60,       -- Intervalo mínimo entre backups (segurança)
}

-- Permitir override
if _G.Config and _G.Config.Backup then
    for k, v in pairs(_G.Config.Backup) do
        Config[k] = v
    end
end

--============================================================
-- Variáveis
--============================================================
local LastBackupTime = 0

--============================================================
-- Funções Principais
--============================================================

-- Criar backup
function SE.Backup.Create(reason)
    if not Config.Enabled then return false, 'Backup desabilitado' end

    -- Verificar intervalo mínimo
    local now = os.time()
    if (now - LastBackupTime) < (Config.MinIntervalMinutes * 60) then
        return false, 'Intervalo mínimo não atingido'
    end

    -- Coletar dados do estado atual
    local state = {
        vaultBalance = (SE.State and SE.State.vaultBalance) or 0,
        inflationRate = (SE.State and SE.State.inflationRate) or 1.0,
        taxMultiplier = (SE.State and SE.State.taxMultiplier) or 1.0,
        settings = (SE.State and SE.State.settings) or {},
        timestamp = now,
        reason = reason or 'auto',
        version = SE.Version or '3.0.0',
    }

    -- Coletar métricas adicionais
    local metrics = {}

    -- Total de dívidas
    local ok, debtRow = pcall(function()
        return MySQL.single.await([[
            SELECT COALESCE(SUM(amount),0) AS total,
                   COALESCE(COUNT(DISTINCT citizenid),0) AS debtors
            FROM space_economy_debts
            WHERE status = 'active'
        ]])
    end)
    if ok and debtRow then
        metrics.totalDebt = U.toInt(debtRow.total, 0)
        metrics.totalDebtors = U.toInt(debtRow.debtors, 0)
    end

    -- Total de logs
    local ok2, logRow = pcall(function()
        return MySQL.single.await('SELECT COUNT(*) as total FROM space_economy_logs')
    end)
    if ok2 and logRow then
        metrics.totalLogs = U.toInt(logRow.total, 0)
    end

    -- Preparar payload
    local stateJson = json.encode(state)
    local metricsJson = json.encode(metrics)

    -- Inserir no banco
    local ok3, insertId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO space_economy_backups
            (backup_date, state_data, vault_balance, metrics, reason, created_at)
            VALUES (CURDATE(), ?, ?, ?, ?, NOW())
        ]], {
            stateJson,
            state.vaultBalance,
            metricsJson,
            state.reason
        })
    end)

    if not ok3 or not insertId then
        SE.Log('backup', 'Falha ao criar backup', { error = 'MySQL insert failed' })
        return false, 'Falha ao inserir no banco'
    end

    LastBackupTime = now

    -- Log
    SE.Log('backup', 'Backup criado com sucesso', {
        id = insertId,
        vault = state.vaultBalance,
        reason = state.reason,
        metrics = metrics
    })

    print(('^2[space_economy]^7 Backup #%d criado: Vault=$%d | Reason=%s'):format(
        insertId,
        state.vaultBalance,
        state.reason
    ))

    return true, insertId
end

-- Restaurar backup
function SE.Backup.Restore(backupId)
    if not backupId or backupId <= 0 then
        return false, 'ID de backup inválido'
    end

    -- Buscar backup
    local ok, backup = pcall(function()
        return MySQL.single.await([[
            SELECT id, state_data, vault_balance, metrics, reason, created_at
            FROM space_economy_backups
            WHERE id = ?
            LIMIT 1
        ]], { backupId })
    end)

    if not ok or not backup then
        return false, 'Backup não encontrado'
    end

    -- Decodificar estado
    local state = json.decode(backup.state_data)
    if not state then
        return false, 'Falha ao decodificar backup'
    end

    -- CRIAR BACKUP ATUAL ANTES DE RESTAURAR (segurança)
    SE.Backup.Create('pre_restore_safety')

    -- Restaurar estado
    if SE.State then
        SE.State.vaultBalance = U.toInt(state.vaultBalance, 0)
        SE.State.inflationRate = U.toNumber(state.inflationRate, 1.0)
        SE.State.taxMultiplier = U.toNumber(state.taxMultiplier, 1.0)
        SE.State.settings = state.settings or {}
        SE.State.dirty = true
    end

    -- Salvar imediatamente
    if SE.Server and SE.Server.SaveState then
        SE.Server.SaveState()
    end

    -- Log
    SE.Log('backup', 'Backup restaurado', {
        backup_id = backupId,
        backup_date = backup.created_at,
        vault_restored = state.vaultBalance,
        reason = backup.reason
    })

    print(('^3[space_economy]^7 Backup #%d restaurado! Vault=$%d | Date=%s'):format(
        backupId,
        state.vaultBalance,
        backup.created_at
    ))

    return true, state
end

-- Listar backups recentes
function SE.Backup.List(limit)
    limit = U.toInt(limit or 10, 10)
    if limit > 100 then limit = 100 end

    local ok, backups = pcall(function()
        return MySQL.query.await([[
            SELECT id, backup_date, vault_balance, reason, created_at
            FROM space_economy_backups
            ORDER BY id DESC
            LIMIT ?
        ]], { limit })
    end)

    if not ok or not backups then return {} end

    return backups
end

-- Limpar backups antigos
function SE.Backup.CleanOld()
    local days = Config.RetentionDays

    local ok, affected = pcall(function()
        return MySQL.query.await([[
            DELETE FROM space_economy_backups
            WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { days })
    end)

    if ok and affected then
        print(('^2[space_economy]^7 Limpeza de backups: %d removidos (>%d dias)'):format(
            affected.affectedRows or 0,
            days
        ))

        SE.Log('backup', 'Limpeza de backups antigos', {
            removed = affected.affectedRows or 0,
            retention_days = days
        })
    end
end

--============================================================
-- Loop de Backup Automático
--============================================================
if Config.Enabled then
    CreateThread(function()
        -- Aguardar inicialização
        Wait(120000) -- 2 minutos

        -- Backup inicial (se configurado)
        if Config.BackupOnStart then
            SE.Backup.Create('auto_start')
        end

        -- Loop periódico
        while true do
            Wait(Config.IntervalHours * 60 * 60 * 1000)

            SE.Backup.Create('auto_periodic')
            SE.Backup.CleanOld()
        end
    end)
end

--============================================================
-- Event Handlers
--============================================================

-- Backup ao desligar servidor
if Config.BackupOnShutdown then
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName ~= GetCurrentResourceName() then return end

        print('^3[space_economy]^7 Creating shutdown backup...')
        SE.Backup.Create('shutdown')
    end)
end

--============================================================
-- Comandos Admin
--============================================================

-- Criar backup manual
RegisterCommand('economy_backup', function(source, args)
    local src = tonumber(source)

    -- Verificar permissão
    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Backup] Acesso negado')
            return
        end
    end

    local ok, result = SE.Backup.Create('manual_command')
    if ok then
        print(('[Backup] Backup #%d criado com sucesso'):format(result))
    else
        print(('[Backup] Erro: %s'):format(result))
    end
end, false)

-- Listar backups
RegisterCommand('economy_backup_list', function(source, args)
    local src = tonumber(source)

    -- Verificar permissão
    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Backup] Acesso negado')
            return
        end
    end

    local backups = SE.Backup.List(20)

    print('\n========================================')
    print('BACKUPS RECENTES')
    print('========================================')

    for _, b in ipairs(backups) do
        print(('ID: %d | Date: %s | Vault: $%d | Reason: %s'):format(
            b.id,
            b.created_at,
            b.vault_balance,
            b.reason
        ))
    end

    print('========================================\n')
end, false)

-- Restaurar backup
RegisterCommand('economy_backup_restore', function(source, args)
    local src = tonumber(source)

    -- Verificar permissão
    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Backup] Acesso negado')
            return
        end
    end

    local backupId = tonumber(args[1])
    if not backupId then
        print('[Backup] Usage: economy_backup_restore <backup_id>')
        return
    end

    print('^3[Backup] ATENÇÃO: Restaurar backup irá SOBRESCREVER o estado atual!^7')
    print('^3[Backup] Um backup de segurança será criado antes da restauração.^7')

    local ok, result = SE.Backup.Restore(backupId)
    if ok then
        print(('^2[Backup] Backup #%d restaurado com sucesso!^7'):format(backupId))
    else
        print(('^1[Backup] Erro: %s^7'):format(result))
    end
end, false)

--============================================================
-- Exports
--============================================================
exports('CreateBackup', SE.Backup.Create)
exports('RestoreBackup', SE.Backup.Restore)
exports('ListBackups', SE.Backup.List)

print(string.format('^2[space_economy]^7 Backup system loaded - Interval: %dh | Retention: %d days',
    Config.IntervalHours,
    Config.RetentionDays
))
