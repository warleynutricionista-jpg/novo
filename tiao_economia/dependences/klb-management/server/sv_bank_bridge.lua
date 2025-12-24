-- KLB x PS-Banking Bridge
-- Garante tabela + contas compartilhadas p/ jobs e gangs (ps-banking compat)
-- Carregue este arquivo ANTES de sv_boss.lua e sv_gang.lua no fxmanifest

local QBCore = (function()
    local ok, obj = pcall(function() return exports['qbx-core']:GetCoreObject() end)
    if ok and obj then return obj end
    ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then return obj end
    error('Unable to get Core object (qbx-core or qb-core)')
end)()

local TableExistsCache = {}

local function HasTable(name)
    if not name or name == '' then return false end
    local key = name:lower()
    if TableExistsCache[key] ~= nil then return TableExistsCache[key] end
    local ok, res = pcall(function()
        return MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
            { name }
        )
    end)
    local exists = ok and res and tonumber(res) and tonumber(res) > 0
    TableExistsCache[key] = exists or false
    return TableExistsCache[key]
end

local function EnsureBankAccountsTable()
    if HasTable('bank_accounts') then return true end
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `bank_accounts` (
              `id` INT NOT NULL AUTO_INCREMENT,
              `citizenid` VARCHAR(50) NULL,
              `account_name` VARCHAR(50) NOT NULL,
              `account_balance` INT NOT NULL DEFAULT 0,
              `account_type` VARCHAR(20) NOT NULL,
              `users` LONGTEXT DEFAULT '[]',
              PRIMARY KEY (`id`),
              KEY `idx_account_name` (`account_name`),
              KEY `idx_account_type` (`account_type`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
    end)
    if not ok then
        print(('^1[KLB]^0 erro criando bank_accounts: %s'):format(err))
        return false
    end
    TableExistsCache['bank_accounts'] = true
    print('^2[KLB]^0 Tabela bank_accounts criada (compatível com ps-banking).')
    return true
end

local function GetAccount(accountName, accountType)
    if not HasTable('bank_accounts') then return nil end
    local row = MySQL.single.await(
        'SELECT id, account_balance FROM bank_accounts WHERE account_name = ? AND account_type = ? LIMIT 1',
        { accountName, accountType }
    )
    if not row then return nil end
    local id = tonumber(row.id) or row.id
    return { id = id, balance = tonumber(row.account_balance) or 0 }
end

local function EnsureAccount(accountName, accountType)
    if not accountName or accountName == '' then return end
    local acc = GetAccount(accountName, accountType)
    if acc then return acc end
    local ok, err = pcall(function()
        MySQL.insert.await(
            'INSERT INTO bank_accounts (citizenid, account_name, account_balance, account_type, users) VALUES (?, ?, ?, ?, ?)',
            { nil, accountName, 0, accountType, '[]' }
        )
    end)
    if not ok then
        print(('^1[KLB]^0 erro criando conta %s/%s: %s'):format(accountType, accountName, err))
        return nil
    end
    return GetAccount(accountName, accountType)
end

-- cria contas para todos os jobs/gangs conhecidos
local function SeedSharedAccounts()
    if not EnsureBankAccountsTable() then return end

    local created, exists = 0, 0

    -- Preferimos as listas de locais onde você realmente tem bossmenu/gangmenu no mapa
    local bossList = (Config and Config.BossMenus) or {}
    local gangList = (Config and Config.GangMenus) or {}

    -- Fallback: se não tiver Config definido, percorre todos do Shared.
    if next(bossList) == nil and QBCore.Shared and QBCore.Shared.Jobs then
        for jobName, job in pairs(QBCore.Shared.Jobs) do
            if type(jobName) == 'string' then
                bossList[jobName] = bossList[jobName] or { vec3(0,0,0) } -- marcador fake p/ criar conta
            end
        end
    end
    if next(gangList) == nil and QBCore.Shared and QBCore.Shared.Gangs then
        for gangName, _ in pairs(QBCore.Shared.Gangs) do
            if type(gangName) == 'string' then
                gangList[gangName] = gangList[gangName] or { vec3(0,0,0) }
            end
        end
    end

    -- Jobs -> account_type = 'job'
    for jobName, _ in pairs(bossList) do
        local acc = GetAccount(jobName, 'job')
        if acc then exists = exists + 1 else
            if EnsureAccount(jobName, 'job') then created = created + 1 end
        end
    end

    -- Gangs -> account_type = 'gang'
    for gangName, _ in pairs(gangList) do
        local acc = GetAccount(gangName, 'gang')
        if acc then exists = exists + 1 else
            if EnsureAccount(gangName, 'gang') then created = created + 1 end
        end
    end

    print(('[KLB] Contas compartilhadas ps-banking -> criadas: %d | existentes: %d'):format(created, exists))
end

-- comando manual para (re)popular
RegisterCommand('klb:init-accounts', function(src)
    if src ~= 0 then
        -- opcional: só permita console
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player or not Player.PlayerData or not Player.PlayerData.group or (Player.PlayerData.group ~= 'admin' and Player.PlayerData.group ~= 'god') then
            TriggerClientEvent('QBCore:Notify', src, 'Sem permissão.', 'error')
            return
        end
    end
    SeedSharedAccounts()
    if src ~= 0 then TriggerClientEvent('QBCore:Notify', src, 'Contas de empresa/gang sincronizadas.', 'success') end
end, false)

-- roda ao iniciar
CreateThread(function()
    -- dá um tempinho pro MySQL/Shared carregar
    Wait(2000)
    SeedSharedAccounts()
end)
