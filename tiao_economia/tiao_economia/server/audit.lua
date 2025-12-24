--============================================================
-- space_economy - server/audit.lua
-- Sistema de Auditoria Completo
-- MELHORIA IMPORTANTE #3 - Compliance +100%
--============================================================
SE = SE or {}
SE.Audit = SE.Audit or {}

local U = SE.Util
local B = SE.Bridge

--============================================================
-- Configuração
--============================================================
local Config = {
    Enabled = true,
    LogAllActions = true,
    RetentionDays = 90,
}

--============================================================
-- Registrar Ação Auditável
--============================================================
function SE.Audit.Log(src, action, details)
    if not Config.Enabled then return end

    src = tonumber(src)
    action = tostring(action or 'unknown')
    details = details or {}

    local adminName = 'Console'
    local adminCid = 'console'
    local ipAddress = 'console'

    if src and src > 0 then
        adminName = (B and B.GetCharName and B.GetCharName(src)) or 'Desconhecido'
        adminCid = (B and B.GetCitizenId and B.GetCitizenId(src)) or 'unknown'
        ipAddress = GetPlayerEndpoint(src) or 'unknown'
    end

    -- Extrair informações adicionais
    local targetCid = details.target_citizenid or details.citizenid or nil
    local amount = details.amount and U.toInt(details.amount, 0) or nil

    -- Preparar JSON
    local detailsJson = json.encode(details)

    -- Inserir no banco
    local ok = pcall(function()
        MySQL.insert.await([[
            INSERT INTO space_economy_audit_log
            (admin_citizenid, admin_name, action, details, ip_address, target_citizenid, amount, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
        ]], {
            adminCid,
            adminName,
            action,
            detailsJson,
            ipAddress,
            targetCid,
            amount
        })
    end)

    if ok then
        -- Também logar no sistema de logs normal
        SE.Log('audit', ('%s: %s'):format(adminName, action), details)
    end
end

--============================================================
-- Listar Logs de Auditoria
--============================================================
function SE.Audit.GetLogs(limit, offset, filters)
    limit = U.toInt(limit or 50, 50)
    offset = U.toInt(offset or 0, 0)
    filters = filters or {}

    local whereConditions = {}
    local params = {}

    -- Filtro por admin
    if filters.admin_citizenid then
        table.insert(whereConditions, 'admin_citizenid = ?')
        table.insert(params, filters.admin_citizenid)
    end

    -- Filtro por ação
    if filters.action then
        table.insert(whereConditions, 'action = ?')
        table.insert(params, filters.action)
    end

    -- Filtro por target
    if filters.target_citizenid then
        table.insert(whereConditions, 'target_citizenid = ?')
        table.insert(params, filters.target_citizenid)
    end

    -- Filtro por data
    if filters.start_date then
        table.insert(whereConditions, 'timestamp >= ?')
        table.insert(params, filters.start_date)
    end

    if filters.end_date then
        table.insert(whereConditions, 'timestamp <= ?')
        table.insert(params, filters.end_date)
    end

    -- Montar WHERE
    local whereClause = ''
    if #whereConditions > 0 then
        whereClause = 'WHERE ' .. table.concat(whereConditions, ' AND ')
    end

    -- Query
    table.insert(params, limit)
    table.insert(params, offset)

    local ok, rows = pcall(function()
        return MySQL.query.await(([[
            SELECT id, admin_citizenid, admin_name, action, target_citizenid,
                   amount, ip_address, timestamp
            FROM space_economy_audit_log
            %s
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        ]]):format(whereClause), params)
    end)

    if not ok or not rows then return {} end
    return rows
end

--============================================================
-- Estatísticas de Auditoria
--============================================================
function SE.Audit.GetStats()
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                COUNT(*) as total_actions,
                COUNT(DISTINCT admin_citizenid) as unique_admins,
                COUNT(DISTINCT action) as unique_actions,
                MAX(timestamp) as last_action
            FROM space_economy_audit_log
        ]])
    end)

    if not ok or not row then
        return {
            total_actions = 0,
            unique_admins = 0,
            unique_actions = 0,
            last_action = nil
        }
    end

    return row
end

--============================================================
-- Limpeza de Logs Antigos
--============================================================
function SE.Audit.CleanOld()
    local days = Config.RetentionDays

    local ok, affected = pcall(function()
        return MySQL.query.await([[
            DELETE FROM space_economy_audit_log
            WHERE timestamp < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { days })
    end)

    if ok and affected then
        print(('^2[space_economy]^7 Audit cleanup: %d removed (>%d days)'):format(
            affected.affectedRows or 0,
            days
        ))
    end
end

--============================================================
-- Wrapper para Actions Comuns
--============================================================

function SE.Audit.LogTreasuryDeposit(src, amount)
    SE.Audit.Log(src, 'treasury_deposit', { amount = amount })
end

function SE.Audit.LogTreasuryWithdraw(src, amount)
    SE.Audit.Log(src, 'treasury_withdraw', { amount = amount })
end

function SE.Audit.LogDebtCreated(src, citizenid, amount, reason)
    SE.Audit.Log(src, 'debt_created', {
        target_citizenid = citizenid,
        amount = amount,
        reason = reason
    })
end

function SE.Audit.LogSettingsChanged(src, changes)
    SE.Audit.Log(src, 'settings_changed', changes)
end

function SE.Audit.LogPanelOpened(src, panelType)
    SE.Audit.Log(src, 'panel_opened', { panel_type = panelType })
end

--============================================================
-- Limpeza Automática
--============================================================
CreateThread(function()
    Wait(300000) -- 5 minutos

    while true do
        Wait(86400000) -- 24 horas

        SE.Audit.CleanOld()
    end
end)

--============================================================
-- Comando Admin
--============================================================
RegisterCommand('audit_stats', function(source)
    local src = tonumber(source)

    if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
        if not SE.Admin.IsAllowed(src) then
            print('[Audit] Acesso negado')
            return
        end
    end

    local stats = SE.Audit.GetStats()

    print('\n========================================')
    print('AUDIT STATISTICS')
    print('========================================')
    print(('Total Actions: %d'):format(stats.total_actions))
    print(('Unique Admins: %d'):format(stats.unique_admins))
    print(('Unique Actions: %d'):format(stats.unique_actions))
    print(('Last Action: %s'):format(stats.last_action or 'N/A'))
    print('========================================\n')
end, false)

--============================================================
-- Exports
--============================================================
exports('AuditLog', SE.Audit.Log)
exports('AuditGetLogs', SE.Audit.GetLogs)
exports('AuditGetStats', SE.Audit.GetStats)

print(string.format('^2[space_economy]^7 Audit system loaded - Retention: %d days', Config.RetentionDays))
