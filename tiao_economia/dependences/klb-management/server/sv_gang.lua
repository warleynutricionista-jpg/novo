-- server/sv_gang.lua (KLB Management) — Qbox/QBCore compat + offline-safe

-- Core (tenta qbx-core, cai para qb-core)
local QBCore = (function()
    local ok, obj = pcall(function() return exports['qbx-core']:GetCoreObject() end)
    if ok and obj then return obj end
    ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then return obj end
    error('Unable to get Core object (qbx-core or qb-core)')
end)()

-- ========= Segurança / Utilidades =========

local function ExploitBan(id, reason)
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
---@param groups table|nil
---@param coords vector3|nil
local function OpenSharedStash(src, name, label, slots, weight, groups, coords)
    if INV.ox then
        pcall(function()
            exports.ox_inventory:RegisterStash(name, label, slots, weight, false, groups, coords)
        end)
        TriggerClientEvent('ox_inventory:openInventory', src, 'stash', name)
        return true
    end

    if INV.ps or INV.qb then
        TriggerClientEvent('inventory:client:SetCurrentStash', src, name)
        TriggerClientEvent('inventory:client:OpenInventory', src, 'stash', {
            id = name,
            slots = slots,
            weight = weight
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

MySQL.ready(function()
    TableExistsCache = {}
    TransactionsTableChecked = nil
    TransactionCache = {}
end)

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
    local gang = entry.gang_name or entry.job_name
    if not gang then return end
    local key = gang:lower()
    local list = TransactionCache[key] or {}
    list[#list+1] = {
        amount = entry.amount,
        type = entry.type,
        name = entry.name,
        citizenid = entry.citizenid,
        note = entry.note,
        created_at = os.date('%Y-%m-%d %H:%M:%S')
    }
    if #list > 25 then table.remove(list, 1) end
    TransactionCache[key] = list
end

local function GetCachedTransactions(gangName)
    if not gangName then return nil end
    return TransactionCache[gangName:lower()]
end

-- ========= Contas (compat com qb-management e fallback em bank_accounts) =========

local function GetBankAccountRow(accountName, accountType)
    if not accountName or accountName == '' then return nil end
    if not HasTable('bank_accounts') then return nil end
    local rows = SafeQuery('SELECT id, account_balance FROM bank_accounts WHERE account_name = ? AND account_type = ? LIMIT 1', { accountName, accountType })
    if rows and rows[1] then
        local row = rows[1]
        local id = row.id
        if type(id) == 'string' then id = tonumber(id) or id end
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

local function GetGangAccountRow(gangName)
    if not gangName or gangName == '' then return nil end
    return GetBankAccountRow(gangName, 'gang') or GetBankAccountRow(gangName, 'job')
end

local function EnsureGangAccount(gangName)
    return GetGangAccountRow(gangName) or EnsureBankAccount(gangName, 'gang')
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

local function InsertGangTransaction(entry, includeNote)
    if not entry or not entry.amount or not entry.type then return false end
    if not entry.gang_name and not entry.job_name then return false end
    local columns, placeholders, values = {}, {}, {}
    local function add(col, val) columns[#columns+1]=col; placeholders[#placeholders+1]='?'; values[#values+1]=val end
    if entry.job_name  then add('job_name',  entry.job_name)  end
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

local function RecordGangTransaction(entry)
    if not entry then return end
    entry.amount = tonumber(entry.amount) or 0
    if entry.amount <= 0 then return end
    entry.type = tostring(entry.type or 'unknown')
    local inserted = false
    if EnsureTransactionsTable() then
        local ok, err = InsertGangTransaction(entry, true)
        if not ok and entry.note and entry.note ~= '' then
            ok, err = InsertGangTransaction(entry, false)
        end
        if not ok and err then
            print(('^1[klb-management]^0 failed to insert gang transaction: %s'):format(err))
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
            local ref   = entry.ref or entry.reference or entry.id or entry.transactionId or entry.log_id or ''
            local by    = entry.by or entry.author or entry.name or entry.player or entry.citizenid or entry.source or ''
            local status= entry.status or (entry.complete == false and 'Pending' or 'Done')
            local tv    = entry.time or entry.timestamp or entry.created_at or entry.date or entry.logged_at
            local tstr
            if type(tv) == 'number' then
                tstr = os.date('%H:%M', tv)
            elseif type(tv) == 'string' then
                tstr = (#tv >= 16) and tv:sub(12, 16) or tv
            else
                tstr = os.date('%H:%M')
            end
            output[#output+1] = {
                ref = ref,
                type = isWithdraw and 'Withdraw' or 'Deposit',
                by = by,
                amount = math.abs(amount),
                status = status,
                time = tstr
            }
            if #output >= 25 then break end
        end
    end
    return output
end

-- ========= Members / Dashboard =========

local function FetchGangMembers(gangname, viewerCitizenId)
    local members = {}
    if not gangname or gangname == '' then return members end

    local rows = SafeQuery("SELECT citizenid, charinfo, gang FROM `players` WHERE `gang` LIKE ?", { '%' .. gangname .. '%' })
    if rows then
        for _, value in pairs(rows) do
            local online = QBCore.Functions.GetPlayerByCitizenId(value.citizenid)
            local gangObj
            local charinfo
            if online and online.PlayerData then
                gangObj  = online.PlayerData.gang
                charinfo = online.PlayerData.charinfo
            else
                gangObj  = value.gang and json.decode(value.gang or '{}') or {}
                charinfo = value.charinfo and json.decode(value.charinfo or '{}') or {}
            end
            if gangObj and gangObj.name == gangname then
                members[#members + 1] = {
                    empSource = value.citizenid,
                    grade     = gangObj.grade or {},
                    isboss    = gangObj.isboss or false,
                    name      = FormatFullName(charinfo),
                    online    = online ~= nil,
                    source    = online and online.PlayerData and online.PlayerData.source or nil,
                    isSelf    = value.citizenid == viewerCitizenId
                }
            end
        end
    end
    table.sort(members, function(a, b)
        return (a.grade and a.grade.level or 0) > (b.grade and b.grade.level or 0)
    end)
    return members
end

local function GetGangAccountData(gangName)
    local balance = 0
    local transactions = {}
    if not gangName or gangName == '' then
        return { balance = balance, transactions = transactions }
    end

    -- qb-management (ou forks)
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function()
            return exports['qb-management']:GetGangAccount(gangName)
        end)
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
            local okBal, val = pcall(function()
                return exports['qb-management']:GetGangAccountBalance(gangName)
            end)
            if okBal and val then balance = tonumber(val) or balance end
        end

        if #transactions == 0 then
            local okTx, list = pcall(function()
                return exports['qb-management']:GetGangAccountTransactions(gangName)
            end)
            if okTx and type(list) == 'table' then transactions = list end
        end
    end

    -- Fallback: bank_accounts
    if balance == 0 then
        local account = GetGangAccountRow(gangName)
        if account then balance = account.balance end
    end

    -- Logs internos
    if #transactions == 0 and EnsureTransactionsTable() then
        local rows = SafeQuery(
            'SELECT id, amount, type, name, citizenid, created_at FROM management_transactions WHERE job_name = ? OR gang_name = ? ORDER BY id DESC LIMIT 25',
            { gangName, gangName }
        )
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
        local cached = GetCachedTransactions(gangName)
        if cached and #cached > 0 then transactions = cached end
    end

    return { balance = balance, transactions = NormaliseTransactions(transactions) }
end

local function AddGangMoney(gangName, amount)
    if not gangName or amount <= 0 then return false end
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function() return exports['qb-management']:AddGangMoney(gangName, amount) end)
        if ok and res ~= false then return true end
        local okAlt, resAlt = pcall(function() return exports['qb-management']:AddMoney(gangName, amount, true) end)
        if okAlt and resAlt ~= false then return true end
    end
    local account = EnsureGangAccount(gangName)
    if not account or not account.id then return false end
    local ok, result = pcall(function()
        return MySQL.query.await('UPDATE bank_accounts SET account_balance = account_balance + ? WHERE id = ?', { amount, account.id })
    end)
    if not ok then
        print(('^1[klb-management]^0 failed to update gang account for %s: %s'):format(gangName, result))
        return false
    end
    if type(result) == 'table' then return (result.affectedRows or result.changedRows or 0) > 0 end
    if type(result) == 'number' then return result > 0 end
    return true
end

local function RemoveGangMoney(gangName, amount)
    if not gangName or amount <= 0 then return false end
    if GetResourceState('qb-management') == 'started' then
        local ok, res = pcall(function() return exports['qb-management']:RemoveGangMoney(gangName, amount) end)
        if ok and res ~= false then return true end
        local okAlt, resAlt = pcall(function() return exports['qb-management']:RemoveMoney(gangName, amount, true) end)
        if okAlt and resAlt ~= false then return true end
    end
    local account = GetGangAccountRow(gangName)
    if not account or not account.id then return false end
    if account.balance < amount then return false end
    local ok, result = pcall(function()
        return MySQL.query.await('UPDATE bank_accounts SET account_balance = account_balance - ? WHERE id = ? AND account_balance >= ?', { amount, account.id, amount })
    end)
    if not ok then
        print(('^1[klb-management]^0 failed to remove funds for gang %s: %s'):format(gangName, result))
        return false
    end
    if type(result) == 'table' then return (result.affectedRows or result.changedRows or 0) > 0 end
    if type(result) == 'number' then return result > 0 end
    return true
end

-- ========= Helpers OFFLINE (Qbox: SetGang para players offline) =========

local function SetGangOffline(citizenid, gangName, gradeLevel)
    if not citizenid or not gangName then return false, 'bad_args' end
    local gangs    = QBCore.Shared.Gangs or {}
    local gangDef  = gangs[gangName]
    local gradeKey = tostring(gradeLevel or 0)
    if not gangDef or not gangDef.grades or not gangDef.grades[gradeKey] then
        return false, 'invalid_gang_or_grade'
    end

    local row  = MySQL.single.await('SELECT gang FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    local gang = row and row.gang and json.decode(row.gang) or {}

    gang.name   = gangName
    gang.label  = gangDef.label or gangName
    gang.isboss = gangDef.grades[gradeKey].isboss or false
    gang.grade  = {
        level   = tonumber(gradeKey) or 0,
        name    = gangDef.grades[gradeKey].name or tostring(gradeKey),
        payment = gangDef.grades[gradeKey].payment or 0
    }

    MySQL.update.await('UPDATE players SET gang = ? WHERE citizenid = ?', { json.encode(gang), citizenid })
    return true
end

-- ========= Depósito / Saque =========

local function ComposeLogSuffix(note, target)
    local parts = {}
    if target and target ~= '' then parts[#parts+1] = 'target ' .. target end
    if note and note ~= ''   then parts[#parts+1] = 'note: ' .. note end
    if #parts > 0 then return ' (' .. table.concat(parts, ', ') .. ')' end
    return ''
end

local function HandleGangDeposit(Player, amount, note, target)
    if not Player.Functions.RemoveMoney('bank', amount, 'gang-deposit') then
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Saldo bancário insuficiente', 'error')
        return false, 'Insufficient bank funds'
    end
    if not AddGangMoney(Player.PlayerData.gang.name, amount) then
        Player.Functions.AddMoney('bank', amount, 'gang-deposit-refund')
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Não foi possível depositar', 'error')
        return false, 'Unable to deposit funds'
    end
    local info = Player.PlayerData
    local fullName = FormatFullName(info.charinfo or {})
    TriggerClientEvent('QBCore:Notify', info.source, ('Depositou $%s na conta da gangue'):format(amount), 'success')
    TriggerEvent('qb-log:server:CreateLog', 'gangmenu', 'Gang Deposit', 'green',
        string.format('%s deposited $%s into %s%s', fullName, amount, info.gang.name, ComposeLogSuffix(note, target)), false)
    RecordGangTransaction({
        gang_name = info.gang.name,
        amount = amount,
        type = 'deposit',
        name = fullName,
        citizenid = info.citizenid,
        note = note
    })
    return true
end

local function HandleGangWithdraw(Player, amount, note, target)
    if not RemoveGangMoney(Player.PlayerData.gang.name, amount) then
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Não foi possível sacar', 'error')
        return false, 'Unable to withdraw funds'
    end
    Player.Functions.AddMoney('bank', amount, 'gang-withdraw')
    local info = Player.PlayerData
    local fullName = FormatFullName(info.charinfo or {})
    TriggerClientEvent('QBCore:Notify', info.source, ('Sacou $%s da conta da gangue'):format(amount), 'success')
    TriggerEvent('qb-log:server:CreateLog', 'gangmenu', 'Gang Withdraw', 'red',
        string.format('%s withdrew $%s from %s%s', fullName, amount, info.gang.name, ComposeLogSuffix(note, target)), false)
    RecordGangTransaction({
        gang_name = info.gang.name,
        amount = amount,
        type = 'withdraw',
        name = fullName,
        citizenid = info.citizenid,
        note = note
    })
    return true
end

-- ========= Callbacks / Eventos =========

-- Get Members (legacy qb-menu)
QBCore.Functions.CreateCallback('qb-gangmenu:server:GetEmployees', function(source, cb, gangname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        ExploitBan(src, 'GetEmployees Exploiting')
        return
    end
    local list = {}
    for _, data in ipairs(FetchGangMembers(gangname or Player.PlayerData.gang.name, Player.PlayerData.citizenid)) do
        list[#list+1] = {
            empSource = data.empSource,
            grade = data.grade,
            isboss = data.isboss,
            name = (data.online and '🟢 ' or '❌ ') .. data.name
        }
    end
    cb(list)
end)

-- Cofre da gangue (compatível com ox/qb/ps-inventory)
RegisterNetEvent('qb-gangmenu:server:stash', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local playerGang = Player.PlayerData.gang
    if not playerGang or not playerGang.isboss then return end
    if not Config.GangMenus[playerGang.name] then return end

    local playerPed    = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local bossCoords   = Config.GangMenus[playerGang.name]

    for i = 1, #bossCoords do
        local coords = bossCoords[i]
        if #(playerCoords - coords) < 2.5 then
            local stashName  = 'boss_' .. playerGang.name
            local stashLabel = ('Cofre • %s'):format(playerGang.label or playerGang.name)
            local slots      = 25
            local weight     = 4000000
            local groups     = { [playerGang.name] = 0 }
            OpenSharedStash(src, stashName, stashLabel, slots, weight, groups, coords)
            return
        end
    end
end)

RegisterNetEvent('qb-gangmenu:server:GradeUpdate', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        ExploitBan(src, 'GradeUpdate Exploiting')
        return
    end

    local requestedGrade = tonumber(data.grade)
    if not requestedGrade then
        TriggerClientEvent('QBCore:Notify', src, 'Patente inválida.', 'error')
        return
    end
    data.grade = requestedGrade

    if data.cid == Player.PlayerData.citizenid and requestedGrade < (Player.PlayerData.gang.grade.level or 0) then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode rebaixar a si mesmo.', 'error')
        return
    end
    if requestedGrade > (Player.PlayerData.gang.grade.level or 0) then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode promover para essa patente.', 'error')
        return
    end

    local gangName = Player.PlayerData.gang.name
    local TargetOnline = QBCore.Functions.GetPlayerByCitizenId(data.cid)
    local success = false

    if TargetOnline then
        success = TargetOnline.Functions.SetGang(gangName, tostring(requestedGrade)) and true or false
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
        -- OFFLINE
        success = SetGangOffline(data.cid, gangName, requestedGrade)
        if success then
            TriggerClientEvent('QBCore:Notify', src, 'Promoção realizada (offline)!', 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'Patente inexistente.', 'error')
        end
    end

    TriggerClientEvent('qb-gangmenu:client:OpenMenu', src)
end)

RegisterNetEvent('qb-gangmenu:server:FireMember', function(target)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        ExploitBan(src, 'FireEmployee Exploiting')
        return
    end

    if target == Player.PlayerData.citizenid then
        TriggerClientEvent('QBCore:Notify', src, 'Você não pode se expulsar da gangue.', 'error')
        return
    end

    local TargetOnline = QBCore.Functions.GetPlayerByCitizenId(target)
    if TargetOnline then
        if (TargetOnline.PlayerData.gang.grade.level or 0) > (Player.PlayerData.gang.grade.level or 0) then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode expulsar essa pessoa.', 'error')
            return
        end
        local ok = TargetOnline.Functions.SetGang('none', '0')
        if ok then
            TargetOnline.Functions.Save()
            TriggerEvent('qb-log:server:CreateLog', 'gangmenu', 'Gang Fire', 'orange',
                Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname ..
                ' successfully fired ' .. TargetOnline.PlayerData.charinfo.firstname .. ' ' .. TargetOnline.PlayerData.charinfo.lastname ..
                ' (' .. Player.PlayerData.gang.name .. ')', false)
            TriggerClientEvent('QBCore:Notify', src, 'Membro da gangue expulso!', 'success')
            if TargetOnline.PlayerData.source then
                TriggerClientEvent('QBCore:Notify', TargetOnline.PlayerData.source, 'Você foi expulso(a) da gangue.', 'error')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Erro.', 'error')
        end
    else
        -- OFFLINE
        local name = GetNameByCitizenId(target)
        local row = MySQL.single.await('SELECT gang FROM players WHERE citizenid = ? LIMIT 1', { target })
        local currentGang = row and row.gang and json.decode(row.gang) or {}
        local targetGrade = (currentGang.grade and tonumber(currentGang.grade.level)) or 0
        local myGrade = (Player.PlayerData.gang.grade and Player.PlayerData.gang.grade.level) or 0
        if targetGrade > myGrade then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode expulsar essa pessoa.', 'error')
            return
        end

        local ok = SetGangOffline(target, 'none', 0)
        if ok then
            TriggerEvent('qb-log:server:CreateLog', 'gangmenu', 'Gang Fire', 'orange',
                Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname ..
                ' successfully fired ' .. name .. ' (' .. Player.PlayerData.gang.name .. ')', false)
            TriggerClientEvent('QBCore:Notify', src, 'Membro da gangue expulso (offline)!', 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'Erro.', 'error')
        end
    end

    TriggerClientEvent('qb-gangmenu:client:OpenMenu', src)
end)

RegisterNetEvent('qb-gangmenu:server:HireMember', function(recruit, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        ExploitBan(src, 'HireMember Exploiting')
        return
    end

    local Target = QBCore.Functions.GetPlayer(recruit)
    if not Target then
        TriggerClientEvent('QBCore:Notify', src, 'Jogador não encontrado.', 'error')
        TriggerClientEvent('qb-gangmenu:client:OpenMenu', src)
        return
    end

    local gangName   = Player.PlayerData.gang.name
    local gangLabel  = Player.PlayerData.gang.label
    local gangGrades = (QBCore.Shared.Gangs[gangName] and QBCore.Shared.Gangs[gangName].grades) or {}
    local requestedGrade = tonumber(grade)
    local hireGrade = 0

    if requestedGrade then
        local requestedInfo = gangGrades[tostring(requestedGrade)]
        if not requestedInfo then
            TriggerClientEvent('QBCore:Notify', src, 'Patente inválida.', 'error'); return
        end
        if requestedGrade > ((Player.PlayerData.gang.grade and Player.PlayerData.gang.grade.level) or 0) then
            TriggerClientEvent('QBCore:Notify', src, 'Você não pode convidar para essa patente.', 'error'); return
        end
        hireGrade = requestedGrade
    end

    local gradeInfo = gangGrades[tostring(hireGrade)]
    local gradeName = gradeInfo and gradeInfo.name or nil

    if Target.Functions.SetGang(gangName, hireGrade) then
        Target.Functions.Save()
        TriggerClientEvent('QBCore:Notify', src,
            ('Você convidou %s %s para %s%s'):format(
                Target.PlayerData.charinfo.firstname,
                Target.PlayerData.charinfo.lastname,
                gangLabel,
                gradeName and (' como ' .. gradeName) or ''
            ), 'success')
        local targetMessage = gradeName and ('Você foi convidado como ' .. gradeName .. ' na ' .. gangLabel)
            or ('Você foi convidado para a ' .. gangLabel)
        TriggerClientEvent('QBCore:Notify', Target.PlayerData.source, targetMessage, 'success')
        TriggerEvent('qb-log:server:CreateLog', 'gangmenu', 'Recruit', 'yellow',
            (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname) ..
            ' successfully recruited ' .. Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname ..
            ' (' .. Player.PlayerData.gang.name .. ')', false)
    else
        TriggerClientEvent('QBCore:Notify', src, 'Não foi possível convidar o jogador.', 'error')
    end

    TriggerClientEvent('qb-gangmenu:client:OpenMenu', src)
end)

QBCore.Functions.CreateCallback('qb-gangmenu:getplayers', function(source, cb)
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
                coords = tCoords,
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

QBCore.Functions.CreateCallback('qb-gangmenu:server:GetEmployeesNUI', function(source, cb, gangname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        ExploitBan(src, 'GetEmployees Exploiting')
        return
    end
    cb(FetchGangMembers(gangname or Player.PlayerData.gang.name, Player.PlayerData.citizenid))
end)

QBCore.Functions.CreateCallback('qb-gangmenu:server:GetDashboard', function(source, cb, gangname)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
        cb({ ok = false, error = 'Not authorized' })
        return
    end
    gangname = gangname or Player.PlayerData.gang.name
    cb({
        ok = true,
        members = FetchGangMembers(gangname, Player.PlayerData.citizenid),
        account = GetGangAccountData(gangname),
        gang = { name = gangname, label = Player.PlayerData.gang.label }
    })
end)

QBCore.Functions.CreateCallback('qb-gangmenu:server:Transfer', function(source, cb, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.gang or not Player.PlayerData.gang.isboss then
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
        local account = GetGangAccountData(Player.PlayerData.gang.name)
        if (account.balance or 0) < amount then
            cb({ ok = false, error = 'Insufficient gang funds' })
            return
        end
        local success, err = HandleGangWithdraw(Player, amount, note, target)
        if not success then
            cb({ ok = false, error = err or 'Withdrawal failed' })
            return
        end
    else
        local success, err = HandleGangDeposit(Player, amount, note, target)
        if not success then
            cb({ ok = false, error = err or 'Deposit failed' })
            return
        end
    end

    cb({ ok = true, account = GetGangAccountData(Player.PlayerData.gang.name) })
end)
