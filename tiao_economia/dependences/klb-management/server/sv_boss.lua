-- server/sv_boss.lua (KLB Management) — Qbox/QBCore compat + offline-safe
-- Feito para funcionar com qbx-core ou qb-core e com inventários ox/qb/ps

-- Core (tenta qbx-core, cai para qb-core)
local QBCore = (function()
    local ok, obj = pcall(function() return exports['qbx-core']:GetCoreObject() end)
    if ok and obj then return obj end
    ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then return obj end
    error('Unable to get Core object (qbx-core or qb-core)')
end)()

-- ========= Segurança / Utilidades =========

function ExploitBan(id, reason)
    MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        GetPlayerName(id),
        QBCore.Functions.GetIdentifier(id, 'license'),
        QBCore.Functions.GetIdentifier(id, 'discord'),
        QBCore.Functions.GetIdentifier(id, 'ip'),
        reason,
        2147483647,
        'klb-management'
    })
    TriggerEvent('qb-log:server:CreateLog', 'bans', 'Player Banned', 'red',
        string.format('%s was banned by %s for %s', GetPlayerName(id), 'klb-management', reason), true)
    DropPlayer(id, 'You were permanently banned by the server for: Exploiting')
end

local function SafeQuery(query, params)
    local ok, result = pcall(function()
        return MySQL.query.await(query, params)
    end)
    if not ok then
        print(('^1[klb-management]^0 SQL error: %s'):format(result))
        return nil
    end
    return result
end

-- ========= Inventário compatível (ox / qb / ps) =========

local INV = {
    ox = GetResourceState('ox_inventory') == 'started',
    ps = GetResourceState('ps-inventory') == 'started',
    qb = GetResourceState('qb-inventory') == 'started',
}

--- Abre/Registra um stash de forma compatível com o inventário em uso.
---@param src number
---@param name string
---@param label string
---@param slots number
---@param weight number
---@param groups table|nil   -- restrição por grupos (ox_inventory)
---@param coords vector3|nil -- coords (ox_inventory pode usar p/ auditoria)
local function OpenSharedStash(src, name, label, slots, weight, groups, coords)
    -- Fechar o tablet antes de abrir o cofre (o client reabre após fechar o inventário)
    TriggerClientEvent('klb-management:client:closeBossMenu', src)

    if INV.ox then
        pcall(function()
            -- RegisterStash(name, label, slots, weight, owner, groups, coords)
            exports.ox_inventory:RegisterStash(name, label, slots, weight, false, groups, coords)
        end)
        TriggerClientEvent('ox_inventory:openInventory', src, 'stash', name)
        return true
    end

    if INV.ps then
        local ok = pcall(function()
            exports['ps-inventory']:OpenInventory(src, name, {
                maxweight = weight, weight = weight, slots = slots, label = label
            })
        end)
        if not ok then
            print('^1[klb-management]^0 ps-inventory OpenInventory falhou; tentando evento QB…')
            TriggerClientEvent('inventory:client:SetCurrentStash', src, name)
            TriggerClientEvent('inventory:client:OpenInventory', src, 'stash', {
                id = name, name = name, stash = name, maxweight = weight, weight = weight, slots = slots
            })
        end
        return true
    end

    if INV.qb then
        TriggerClientEvent('inventory:client:SetCurrentStash', src, name)
        TriggerClientEvent('inventory:client:OpenInventory', src, 'stash', {
            id = name, name = name, stash = name, maxweight = weight, weight = weight, slots = slots, label = label
        })
        return true
    end

    print('^1[klb-management]^0 Nenhum inventário compatível encontrado (ox_inventory/qb-inventory/ps-inventory).')
    return false
end

-- ========= Cache de tabelas / transações =========

local TableExistsCache = {}
local TransactionsTableChecked
local TransactionCache = {}

local function HasTable(tableName)
    if not tableName or tableName == '' then return false end
    local cacheKey = tableName:lower()
    if TableExistsCache[cacheKey] ~= nil then
        return TableExistsCache[cacheKey]
    end
    local ok, result = pcall(function()
        return MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { tableName })
    end)
    local exists = ok and result and tonumber(result) and tonumber(result) > 0
    TableExistsCache[cacheKey] = exists or false
    return TableExistsCache[cacheKey]
end

MySQL.ready(function()
    TableExistsCache = {}
    TransactionsTableChecked = nil
    TransactionCache = {}
end)

local function EnsureTransactionsTable()
    if TransactionsTableChecked ~= nil then
        return TransactionsTableChecked
    end
    if not HasTable('management_transactions') then
        local ok = pcall(function()
            MySQL.query.await([[CREATE TABLE IF NOT EXISTS `management_transactions` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `job_name` varchar(50) DEFAULT NULL,
                `gang_name` varchar(50) DEFAULT NULL,
                `amount` int(11) NOT NULL DEFAULT 0,
                `type` varchar(32) NOT NULL,
                `name` varchar(100) DEFAULT NULL,
                `citizenid` varchar(50) DEFAULT NULL,
                `note` text DEFAULT NULL,
                `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `idx_job_name` (`job_name`),
                KEY `idx_gang_name` (`gang_name`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
        end)
        if not ok then
            TransactionsTableChecked = false
            return false
        end
        TableExistsCache['management_transactions'] = true
    end
    TransactionsTableChecked = HasTable('management_transactions')
    return TransactionsTableChecked
end

local function CacheTransaction(entry)
    if not entry then return end
    local job = entry.job_name or entry.gang_name
    if not job then return end
    local key = job:lower()
    local list = TransactionCache[key] or {}
    list[#list+1] = {
        amount = entry.amount,
        type = entry.type,
        name = entry.name,
        citizenid = entry.citizenid,
        note = entry.note,
        created_at = os.date('%Y-%m-%d %H:%M:%S')
    }
    if #list > 25 then
        table.remove(list, 1)
    end
    TransactionCache[key] = list
end

local function GetCachedTransactions(jobName)
    if not jobName then return nil end
    return TransactionCache[jobName:lower()]
end

-- ========= Contas (compat com qb-management e fallback em bank_accounts) =========

local function GetBankAccountRow(accountName, accountType)
    if not accountName or accountName == '' then return nil end
    if not HasTable('bank_accounts') then return nil end
    local rows = SafeQuery('SELECT id, account_balance FROM bank_accounts WHERE account_name = ? AND account_type = ? LIMIT 1', { accountName, accountType })
    if rows and rows[1] then
        local row = rows[1]
        local id = row.id
        if type(id) == 'string' then
            local numeric = tonumber(id)
            if numeric then id = numeric end
        end
        return { id = id, balance = tonumber(row.account_balance) or 0 }
    end
    return nil
end

local function EnsureBankAccount(accountName, accountType)
    if not HasTable('bank_accounts') then return nil end
    local account = GetBankAccountRow(accountName, accountType)
    if account then return account end
    local ok = pcall(function()
        MySQL.insert.await('INSERT INTO bank_accounts (citizenid, account_name, account_balance, account_type, users) VALUES (?, ?, ?, ?, ?)', {
            nil, accountName, 0, accountType, '[]'
        })
    end)
    if not ok then return nil end
    return GetBankAccountRow(accountName, accountType)
end

-- ========= Helpers de nomes =========

local function FormatFullName(charinfo)
    charinfo = charinfo or {}
    local first = charinfo.firstname or 'Unknown'
    local last  = charinfo.lastname or ''
    local name  = (first .. ' ' .. last):gsub('%s+$', '')
    return name ~= '' and name or first
end

local function GetNameByCitizenId(citizenid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row or not row.charinfo then return 'Unknown' end
    local ci = json.decode(row.charinfo or '{}') or {}
    return FormatFullName(ci)
end

-- ========= Transações (log interno) =========

local function InsertManagementTransaction(entry, includeNote)
    if not entry or (not entry.job_name and not entry.gang_name) then return false end
    if not entry.amount or not entry.type then return false end
    local columns, placeholders, values = {}, {}, {}
    local function add(column, value)
        columns[#columns+1] = column
        placeholders[#placeholders+1] = '?'
        values[#values+1] = value
    end
    if entry.job_name then add('job_name', entry.job_name) end
    if entry.gang_name then add('gang_name', entry.gang_name) end
    add('amount', entry.amount)
    add('type', entry.type)
    add('name', entry.name or '')
    add('citizenid', entry.citizenid or '')
    if includeNote and entry.note and entry.note ~= '' then add('note', entry.note) end
    local query = ('INSERT INTO management_transactions (%s, created_at) VALUES (%s, NOW())')
        :format(table.concat(columns, ', '), table.concat(placeholders, ', '))
    local ok, result = pcall(function() return MySQL.insert.await(query, values) end)
    return ok, result
end

local function RecordJobTransaction(entry)
    if not entry then return end
    entry.amount = tonumber(entry.amount) or 0
    if entry.amount <= 0 then return end
    entry.type = tostring(entry.type or 'unknown')
    local inserted = false
    if EnsureTransactionsTable() then
        local ok, err = InsertManagementTransaction(entry, true)
        if not ok and entry.note and entry.note ~= '' then ok, err = InsertManagementTransaction(entry, false) end
        if not ok and err then
            print(('^1[klb-management]^0 failed to insert transaction: %s'):format(err))
        else
            inserted = ok
        end
    end
    if not inserted then CacheTransaction(entry) end
end

local function NormaliseTransactions(transactions)
    local output = {}
    if type(transactions) ~= 'table' then return output end
    for _, entry in ipairs(transactions) do
        if type(entry) == 'table' then
            local amount  = tonumber(entry.amount or entry.value or entry.transactionAmount or entry.money or 0) or 0
            local rawType = entry.type or entry.action or entry.transactionType
            if not rawType and amount < 0 then rawType = 'withdraw' end
            rawType = type(rawType) == 'string' and rawType:lower() or ''
            local isWithdraw = rawType == 'withdraw' or rawType == 'remove' or rawType == 'out' or amount < 0
            local ref     = entry.ref or entry.reference or entry.id or entry.transactionId or entry.log_id or ''
            local by      = entry.by or entry.author or entry.name or entry.player or entry.citizenid or entry.source or ''
            local status  = entry.status or (entry.complete == false and 'Pending' or 'Done')
            local tv      = entry.time or entry.timestamp or entry.created_at or entry.date or entry.logged_at
            local time
            if type(tv) == 'number' then
                time = os.date('%H:%M', tv)
            elseif type(tv) == 'string' then
                time = (#tv >= 16) and tv:sub(12, 16) or tv
            else
                time = os.date('%H:%M')
            end
            output[#output+1] = {
                ref = ref, type = isWithdraw and 'Withdraw' or 'Deposit',
                by = by, amount = math.abs(amount), status = status, time = time
            }
            if #output >= 25 then break end
        end
    end
    return output
end

-- ========= Dashboard / Employees =========

local function FetchJobEmployees(jobname, viewerCitizenId)
    local employees = {}
    if not jobname or jobname == '' then return employees end

    local players = SafeQuery("SELECT citizenid, charinfo, job FROM `players` WHERE `job` LIKE ?", { '%' .. jobname .. '%' })
    if players then
        for _, value in pairs(players) do
            local online  = QBCore.Functions.GetPlayerByCitizenId(value.citizenid)
            local jobObj  = nil
            local charinfo = nil

            if online and online.PlayerData then
                jobObj   = online.PlayerData.job
                charinfo = online.PlayerData.charinfo
            else
                jobObj   = value.job and json.decode(value.job or '{}') or {}
                charinfo = value.charinfo and json.decode(value.charinfo or '{}') or {}
            end

            if jobObj and jobObj.name == jobname then
                employees[#employees + 1] = {
                    empSource = value.citizenid,
                    grade = jobObj.grade or {},
                    isboss = jobObj.isboss or false,
                    name = FormatFullName(charinfo),
                    online = online ~= nil,
                    source = online and online.PlayerData and online.PlayerData.source or nil,
                    isSelf = value.citizenid == viewerCitizenId
                }
            end
        end
    end

    table.sort(employees, function(a, b)
        return (a.grade and a.grade.level or 0) > (b.grade and b.grade.level or 0)
    end)
    return employees
end

local function GetJobAccountData(jobName)
    local balance = 0
    local transactions = {}
    if not jobName or jobName == '' then
        return { balance = balance, transactions = transactions }
    end

    -- Tenta qb-management (quando presente)
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function() return exports['qb-management']:GetAccount(jobName) end)
        if ok and res then
            if type(res) == 'table' then
                if res.balance then balance = tonumber(res.balance) or balance
                elseif res.amount then balance = tonumber(res.amount) or balance
                elseif res.money  then balance = tonumber(res.money ) or balance
                elseif res[1]     then balance = tonumber(res[1])    or balance end

                if type(res.transactions) == 'table' and #res.transactions > 0 then
                    transactions = res.transactions
                elseif type(res.history) == 'table' then
                    transactions = res.history
                elseif res.account and type(res.account) == 'table' then
                    balance = tonumber(res.account.balance or balance) or balance
                    if type(res.account.transactions) == 'table' then
                        transactions = res.account.transactions
                    elseif type(res.account.history) == 'table' then
                        transactions = res.account.history
                    end
                end
            elseif type(res) == 'number' then
                balance = res
            end
        end

        if balance == 0 then
            local okBal, val = pcall(function() return exports['qb-management']:GetAccountBalance(jobName) end)
            if okBal and val then balance = tonumber(val) or balance end
        end

        if #transactions == 0 then
            local okTx, list = pcall(function() return exports['qb-management']:GetAccountTransactions(jobName) end)
            if okTx and type(list) == 'table' then transactions = list end
        end
    end

    -- Fallback para tabela bank_accounts (usada por ps-banking)
    if balance == 0 then
        local account = GetBankAccountRow(jobName, 'job')
        if account then balance = account.balance end
    end

    -- Logs internos
    if #transactions == 0 and HasTable('management_transactions') then
        local rows = SafeQuery('SELECT id, amount, type, name, citizenid, created_at FROM management_transactions WHERE job_name = ? ORDER BY id DESC LIMIT 25', { jobName })
        if rows then
            transactions = {}
            for _, entry in ipairs(rows) do
                transactions[#transactions+1] = {
                    id = entry.id, amount = entry.amount, type = entry.type, name = entry.name,
                    citizenid = entry.citizenid, created_at = entry.created_at, status = 'Done'
                }
            end
        end
    end

    if #transactions == 0 then
        local cached = GetCachedTransactions(jobName)
        if cached and #cached > 0 then transactions = cached end
    end

    return { balance = balance, transactions = NormaliseTransactions(transactions) }
end

local function AddJobMoney(jobName, amount)
    if not jobName or amount <= 0 then return false end
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function() return exports['qb-management']:AddMoney(jobName, amount) end)
        if ok and res ~= false then return true end
    end

    local account = EnsureBankAccount(jobName, 'job')
    if not account or not account.id then return false end
    local ok, result = pcall(function()
        return MySQL.query.await('UPDATE bank_accounts SET account_balance = account_balance + ? WHERE id = ?', { amount, account.id })
    end)
    if not ok then
        print(('^1[klb-management]^0 failed to update bank account for %s: %s'):format(jobName, result))
        return false
    end
    if type(result) == 'table' then return (result.affectedRows or result.changedRows or 0) > 0 end
    if type(result) == 'number' then return result > 0 end
    return true
end

local function RemoveJobMoney(jobName, amount)
    if not jobName or amount <= 0 then return false end
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function() return exports['qb-management']:RemoveMoney(jobName, amount) end)
        if ok and res ~= false then return true end
    end

    local account = GetBankAccountRow(jobName, 'job')
    if not account or not account.id then return false end
    if account.balance < amount then return false end
    local ok, result = pcall(function()
        return MySQL.query.await('UPDATE bank_accounts SET account_balance = account_balance - ? WHERE id = ? AND account_balance >= ?', { amount, account.id, amount })
    end)
    if not ok then
        print(('^1[klb-management]^0 failed to remove funds for %s: %s'):format(jobName, result))
        return false
    end
    if type(result) == 'table' then return (result.affectedRows or result.changedRows or 0) > 0 end
    if type(result) == 'number' then return result > 0 end
    return true
end

-- ========= Helpers OFFLINE (Qbox: SetJob para players offline) =========

local function SetJobOffline(citizenid, jobName, gradeLevel)
    if not citizenid or not jobName then return false, 'bad_args' end
    local jobs    = QBCore.Shared.Jobs or {}
    local jobDef  = jobs[jobName]
    local gradeKey = tostring(gradeLevel or 0)
    if not jobDef or not jobDef.grades or not jobDef.grades[gradeKey] then
        return false, 'invalid_job_or_grade'
    end

    local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    local job = row and row.job and json.decode(row.job) or {}

    job.name   = jobName
    job.label  = jobDef.label or jobName
    job.isboss = jobDef.grades[gradeKey].isboss or false
    job.onduty = false
    job.grade  = {
        level   = tonumber(gradeKey) or 0,
        name    = jobDef.grades[gradeKey].name or tostring(gradeKey),
        payment = jobDef.grades[gradeKey].payment or 0
    }

    MySQL.update.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(job), citizenid })
    return true
end

-- ========= Depósito / Saque =========

local function ComposeLogSuffix(note, target)
    local parts = {}
    if target and target ~= '' then parts[#parts+1] = 'target ' .. target end
    if note and note ~= '' then parts[#parts+1] = 'note: ' .. note end
    if #parts > 0 then return ' (' .. table.concat(parts, ', ') .. ')' end
    return ''
end

local function HandleJobDeposit(Player, amount, note, target)
    if not Player.Functions.RemoveMoney('bank', amount, 'job-deposit') then
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Saldo bancário insuficiente', 'error')
        return false, 'Insufficient bank funds'
    end
    if not AddJobMoney(Player.PlayerData.job.name, amount) then
        Player.Functions.AddMoney('bank', amount, 'job-deposit-refund')
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Não foi possível depositar', 'error')
        return false, 'Unable to deposit funds'
    end
    local info = Player.PlayerData
    local fullName = FormatFullName(info.charinfo or {})
    TriggerClientEvent('QBCore:Notify', info.source, ('Depositou $%s na conta da empresa'):format(amount), 'success')
    TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Deposit', 'green',
        string.format('%s deposited $%s into %s%s', fullName, amount, info.job.name, ComposeLogSuffix(note, target)), false)
    RecordJobTransaction({
        job_name = info.job.name, amount = amount, type = 'deposit',
        name = fullName, citizenid = info.citizenid, note = note
    })
    return true
end

local function HandleJobWithdraw(Player, amount, note, target)
    if not RemoveJobMoney(Player.PlayerData.job.name, amount) then
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Não foi possível sacar', 'error')
        return false, 'Unable to withdraw funds'
    end
    Player.Functions.AddMoney('bank', amount, 'job-withdraw')
    local info = Player.PlayerData
    local fullName = FormatFullName(info.charinfo or {})
    TriggerClientEvent('QBCore:Notify', info.source, ('Sacou $%s da conta da empresa'):format(amount), 'success')
    TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Withdraw', 'red',
        string.format('%s withdrew $%s from %s%s', fullName, amount, info.job.name, ComposeLogSuffix(note, target)), false)
    RecordJobTransaction({
        job_name = info.job.name, amount = amount, type = 'withdraw',
        name = fullName, citizenid = info.citizenid, note = note
    })
    return true
end

-- ========= Callbacks / Eventos =========

QBCore.Functions.CreateCallback('qb-bossmenu:server:GetEmployees', function(source, cb, jobname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        ExploitBan(src, 'GetEmployees Exploiting')
        return
    end
    local employees = {}
    for _, data in ipairs(FetchJobEmployees(jobname or Player.PlayerData.job.name, Player.PlayerData.citizenid)) do
        employees[#employees + 1] = {
            empSource = data.empSource,
            grade = data.grade,
            isboss = data.isboss,
            name = (data.online and '🟢 ' or '❌ ') .. data.name
        }
    end
    cb(employees)
end)

-- Cofre (compatível com ox/qb/ps-inventory)
RegisterNetEvent('qb-bossmenu:server:stash', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local playerJob = Player.PlayerData.job
    if not playerJob or not playerJob.isboss then return end
    if not Config.BossMenus[playerJob.name] then return end

    local playerPed    = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local bossCoords   = Config.BossMenus[playerJob.name]

    for i = 1, #bossCoords do
        local coords = bossCoords[i]
        if #(playerCoords - coords) < 2.5 then
            local stashName  = ('boss_%s'):format(playerJob.name)
            local stashLabel = ('Cofre • %s'):format(playerJob.label or playerJob.name)
            local slots      = 25
            local weight     = 4000000
            local groups     = { [playerJob.name] = 0 } -- restrição ox_inventory

            OpenSharedStash(src, stashName, stashLabel, slots, weight, groups, coords)
            return
        end
    end
end)

RegisterNetEvent('qb-bossmenu:server:GradeUpdate', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        ExploitBan(src, 'GradeUpdate Exploiting')
        return
    end

    local requestedGrade = tonumber(data.grade)
    if not requestedGrade then
        TriggerClientEvent('QBCore:Notify', src, 'Patente inválida.', 'error')
        return
    end
    data.grade = requestedGrade

    if data.cid == Player.PlayerData.citizenid and requestedGrade < Player.PlayerData.job.grade.level then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode rebaixar a si mesmo.', 'error')
        return
    end
    if requestedGrade > Player.PlayerData.job.grade.level then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode promover para essa patente.', 'error')
        return
    end

    local jobName = Player.PlayerData.job.name
    local TargetOnline = QBCore.Functions.GetPlayerByCitizenId(data.cid)
    local success = false

    if TargetOnline then
        success = TargetOnline.Functions.SetJob(jobName, tostring(requestedGrade)) and true or false
        if success then
            TargetOnline.Functions.Save()
            TriggerClientEvent('QBCore:Notify', src, 'Promoção realizada!', 'success')
            if TargetOnline.PlayerData.source then
                TriggerClientEvent('QBCore:Notify', TargetOnline.PlayerData.source, 'Você foi promovido para ' .. (data.gradename or requestedGrade) .. '.', 'success')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Patente inexistente.', 'error')
        end
    else
        -- OFFLINE (Qbox-safe)
        success = SetJobOffline(data.cid, jobName, requestedGrade)
        if success then
            TriggerClientEvent('QBCore:Notify', src, 'Promoção realizada (offline)!', 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'Patente inexistente.', 'error')
        end
    end

    TriggerClientEvent('qb-bossmenu:client:OpenMenu', src)
end)

RegisterNetEvent('qb-bossmenu:server:FireEmployee', function(target)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        ExploitBan(src, 'FireEmployee Exploiting')
        return
    end

    if target == Player.PlayerData.citizenid then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode se demitir.', 'error')
        return
    end

    local TargetOnline = QBCore.Functions.GetPlayerByCitizenId(target)
    if TargetOnline then
        if TargetOnline.PlayerData.job.grade.level > Player.PlayerData.job.grade.level then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode demitir essa pessoa.', 'error')
            return
        end
        local ok = TargetOnline.Functions.SetJob('unemployed', '0')
        if ok then
            TargetOnline.Functions.Save()
            TriggerClientEvent('QBCore:Notify', src, 'Funcionário demitido!', 'success')
            TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Fire', 'red',
                Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname ..
                ' successfully fired ' .. TargetOnline.PlayerData.charinfo.firstname .. ' ' .. TargetOnline.PlayerData.charinfo.lastname ..
                ' (' .. Player.PlayerData.job.name .. ')', false)
            if TargetOnline.PlayerData.source then
                TriggerClientEvent('QBCore:Notify', TargetOnline.PlayerData.source, 'Você foi demitido(a).', 'error')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Erro.', 'error')
        end
    else
        -- OFFLINE (Qbox-safe)
        local name = GetNameByCitizenId(target)
        local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', { target })
        local currentJob = row and row.job and json.decode(row.job) or {}
        local targetGrade = (currentJob.grade and tonumber(currentJob.grade.level)) or 0
        local myGrade = Player.PlayerData.job.grade.level or 0
        if targetGrade > myGrade then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode demitir essa pessoa.', 'error')
            return
        end

        local ok = SetJobOffline(target, 'unemployed', 0)
        if ok then
            TriggerClientEvent('QBCore:Notify', src, 'Funcionário demitido (offline)!', 'success')
            TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Job Fire', 'red',
                Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname ..
                ' successfully fired ' .. name .. ' (' .. Player.PlayerData.job.name .. ')', false)
        else
            TriggerClientEvent('QBCore:Notify', src, 'Erro.', 'error')
        end
    end

    TriggerClientEvent('qb-bossmenu:client:OpenMenu', src)
end)

RegisterNetEvent('qb-bossmenu:server:HireEmployee', function(recruit, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        ExploitBan(src, 'HireEmployee Exploiting')
        return
    end

    local Target = QBCore.Functions.GetPlayer(recruit)
    local jobName = Player.PlayerData.job.name
    local jobGrades = QBCore.Shared.Jobs[jobName] and QBCore.Shared.Jobs[jobName].grades or {}

    local requestedGrade = tonumber(grade)
    local hireGrade = 0
    if requestedGrade then
        local requestedInfo = jobGrades[tostring(requestedGrade)]
        if not requestedInfo then
            TriggerClientEvent('QBCore:Notify', src, 'Patente inválida.', 'error')
            return
        end
        if requestedGrade > Player.PlayerData.job.grade.level then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode contratar nessa patente.', 'error')
            return
        end
        hireGrade = requestedGrade
    end
    local gradeInfo = jobGrades[tostring(hireGrade)]
    local gradeName = gradeInfo and gradeInfo.name or nil

    if Target and Target.Functions.SetJob(jobName, hireGrade) then
        Target.Functions.Save()
        TriggerClientEvent('QBCore:Notify', src,
            ('Você contratou %s %s para %s%s'):format(
                Target.PlayerData.charinfo.firstname,
                Target.PlayerData.charinfo.lastname,
                Player.PlayerData.job.label,
                gradeName and (' como ' .. gradeName) or ''
            ), 'success')
        local targetMessage = gradeName and ('Você foi contratado como ' .. gradeName .. ' em ' .. Player.PlayerData.job.label)
            or ('Você foi contratado em ' .. Player.PlayerData.job.label)
        TriggerClientEvent('QBCore:Notify', Target.PlayerData.source, targetMessage, 'success')
        TriggerEvent('qb-log:server:CreateLog', 'bossmenu', 'Recruit', 'lightgreen',
            (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname) ..
            ' successfully recruited ' .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) ..
            ' (' .. Player.PlayerData.job.name .. ')', false)
    else
        TriggerClientEvent('QBCore:Notify', src, 'Não foi possível contratar o jogador.', 'error')
    end

    TriggerClientEvent('qb-bossmenu:client:OpenMenu', src)
end)

QBCore.Functions.CreateCallback('qb-bossmenu:getplayers', function(source, cb)
    local src = source
    local players = {}
    local PlayerPed = GetPlayerPed(src)
    local pCoords = GetEntityCoords(PlayerPed)
    for _, v in pairs(QBCore.Functions.GetPlayers()) do
        local targetped = GetPlayerPed(v)
        local tCoords = GetEntityCoords(targetped)
        local dist = #(pCoords - tCoords)
        if PlayerPed ~= targetped and dist < 10 then
            local ped = QBCore.Functions.GetPlayer(v)
            players[#players + 1] = {
                id = v,
                coords = GetEntityCoords(targetped),
                name = ped.PlayerData.charinfo.firstname .. ' ' .. ped.PlayerData.charinfo.lastname,
                citizenid = ped.PlayerData.citizenid,
                sources = GetPlayerPed(ped.PlayerData.source),
                sourceplayer = ped.PlayerData.source
            }
        end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    cb(players)
end)

QBCore.Functions.CreateCallback('qb-bossmenu:server:GetEmployeesNUI', function(source, cb, jobname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        ExploitBan(src, 'GetEmployees Exploiting')
        return
    end
    cb(FetchJobEmployees(jobname or Player.PlayerData.job.name, Player.PlayerData.citizenid))
end)

QBCore.Functions.CreateCallback('qb-bossmenu:server:GetDashboard', function(source, cb, jobname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        cb({ ok = false, error = 'Not authorized' })
        return
    end
    jobname = jobname or Player.PlayerData.job.name
    cb({
        ok = true,
        members  = FetchJobEmployees(jobname, Player.PlayerData.citizenid),
        account  = GetJobAccountData(jobname),
        gang     = { name = jobname, label = Player.PlayerData.job.label }
    })
end)

QBCore.Functions.CreateCallback('qb-bossmenu:server:Transfer', function(source, cb, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job or not Player.PlayerData.job.isboss then
        cb({ ok = false, error = 'Not authorized' })
        return
    end
    local amount = tonumber(data and data.amount or 0) or 0
    if amount <= 0 then
        cb({ ok = false, error = 'Invalid amount' })
        return
    end
    local note = tostring(data and data.note or '')
    if #note > 120 then note = note:sub(1, 120) end
    local target = tostring(data and data.target or '')
    if #target > 60 then target = target:sub(1, 60) end

    if data and data.type == 'withdraw' then
        local account = GetJobAccountData(Player.PlayerData.job.name)
        if (account.balance or 0) < amount then
            cb({ ok = false, error = 'Insufficient company funds' })
            return
        end
        local success, err = HandleJobWithdraw(Player, amount, note, target)
        if not success then
            cb({ ok = false, error = err or 'Withdrawal failed' })
            return
        end
    else
        local success, err = HandleJobDeposit(Player, amount, note, target)
        if not success then
            cb({ ok = false, error = err or 'Deposit failed' })
            return
        end
    end

    cb({ ok = true, account = GetJobAccountData(Player.PlayerData.job.name) })
end)
