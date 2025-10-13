-- server/bridge_core.lua
-- Bridge Core + Banco (oxmysql) para Painel_ORG (tabelas thunder_*)

local RES_NAME = GetCurrentResourceName()

-- ===== Core (qbx-core preferido, fallback qb-core) =====
local Core = (function()
    local ok, obj = pcall(function()
        if GetResourceState('qbx-core') == 'started'
            and exports['qbx-core']
            and exports['qbx-core'].GetCoreObject
        then
            return exports['qbx-core']:GetCoreObject()
        end
        if GetResourceState('qb-core') == 'started'
            and exports['qb-core']
            and exports['qb-core'].GetCoreObject
        then
            return exports['qb-core']:GetCoreObject()
        end
        return nil
    end)
    if not ok or not obj then
        print(('[%s] ^3QBCore/Qbox não encontrado.^0 O recurso carrega, mas integrações de core ficam limitadas.'):format(RES_NAME:upper()))
        return nil
    end
    return obj
end)()

-- ===== Helpers de Identidade =====
local function GetCitizenId(src)
    if Core and Core.Functions then
        local Player = Core.Functions.GetPlayer(src)
        if Player and Player.PlayerData and Player.PlayerData.citizenid then
            return Player.PlayerData.citizenid
        end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:') then
            return id
        end
    end
    return nil
end

local function buildIdentity(first, last, fallback)
    first = first or ''
    last = last or ''

    local composed
    if first ~= '' or last ~= '' then
        composed = ('%s %s'):format(first, last):gsub('%s+$', '')
    end

    local display = (composed and composed ~= '' and composed)
        or (fallback and fallback ~= '' and fallback)
        or 'Jogador'

    return {
        firstname = first,
        lastname = last,
        name = display,
    }
end

local function GetIdentity(src)
    if Core and Core.Functions then
        local Player = Core.Functions.GetPlayer(src)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            local ci = Player.PlayerData.charinfo
            return buildIdentity(ci.firstname, ci.lastname, nil)
        end
    end
    local name = GetPlayerName(src) or 'Jogador'
    return buildIdentity(name, '', name)
end

getUserId       = GetCitizenId
getUserIdentity = GetIdentity
getUserSource   = function(citizenid)
    if not citizenid then return nil end
    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if GetCitizenId(src) == citizenid then
            return src
        end
    end
    return nil
end

-- ===== Esperar MySQL global (injetado por @oxmysql/lib/MySQL.lua) =====
local function WaitForMySQL(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 15000)
    while not MySQL do
        if GetGameTimer() > deadline then break end
        Wait(50)
    end
    return MySQL ~= nil
end

-- ===== DDL / Schema (usar query.await, NÃO execute.await) =====
local function EnsureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_orgs_info` (
            `organization`    VARCHAR(50)  NOT NULL,
            `alerts`          TEXT         DEFAULT '[]',
            `logo`            TEXT         NULL,
            `discord`         VARCHAR(150) DEFAULT '',
            `salary`          TEXT         DEFAULT '{}',
            `bank`            INT          DEFAULT 0,
            `bank_historic`   TEXT         DEFAULT '[]',
            `permissions`     TEXT         DEFAULT '{}',
            `config_goals`    TEXT         DEFAULT '{}',
            `radio`           VARCHAR(64)  DEFAULT '',
            `presets`         TEXT         DEFAULT '{}',
            PRIMARY KEY (`organization`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_orgs_logs` (
            `id`              INT AUTO_INCREMENT PRIMARY KEY,
            `organization`    VARCHAR(50)  NOT NULL,
            `user_identifier` VARCHAR(80)  NOT NULL,
            `role`            VARCHAR(50)  NULL,
            `name`            VARCHAR(100) NULL,
            `description`     VARCHAR(255) NULL,
            `date`            VARCHAR(50)  NULL,
            `expire_at`       INT          NULL,
            KEY `org_idx` (`organization`),
            KEY `user_idx` (`user_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_orgs_player_infos` (
            `citizenid`   VARCHAR(80) NOT NULL,
            `organization` VARCHAR(50) NULL,
            `joindate`    INT DEFAULT 0,
            `lastlogin`   INT DEFAULT 0,
            `timeplayed`  INT DEFAULT 0,
            PRIMARY KEY (`citizenid`),
            KEY `org_idx` (`organization`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_orgs_chat` (
            `id`              INT AUTO_INCREMENT PRIMARY KEY,
            `organization`    VARCHAR(50) NOT NULL,
            `user_identifier` VARCHAR(80) NOT NULL,
            `message`         TEXT NOT NULL,
            `author`          VARCHAR(100) NOT NULL,
            `created_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY `org_idx` (`organization`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_orgs_goals` (
            `user_identifier` VARCHAR(80)  NOT NULL,
            `organization`    VARCHAR(50)  NOT NULL,
            `item`            VARCHAR(100) NOT NULL,
            `amount`          INT          NOT NULL DEFAULT 0,
            `day`             INT          NOT NULL,
            `month`           INT          NOT NULL,
            `step`            INT          DEFAULT 1,
            `reward_step`     INT          DEFAULT 0,
            UNIQUE KEY `uniq_user_org_item_day_month` (`user_identifier`,`organization`,`item`,`day`,`month`),
            KEY `org_idx` (`organization`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `thunder_partners` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `cds` TEXT NULL,
            `name` VARCHAR(100) NULL,
            `note` INT NULL DEFAULT 0,
            `description` TEXT NULL,
            `icon` TEXT NULL,
            `groups` TEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

-- ===== DB API =====
DB = {}

function DB.GetOrgInfo(organization)
    return MySQL.single.await(
        'SELECT bank, bank_historic, discord, salary, radio, presets, alerts FROM thunder_orgs_info WHERE organization = ? LIMIT 1',
        { organization }
    )
end

function DB.GetOrgBank(organization)
    return MySQL.single.await(
        'SELECT bank, bank_historic FROM thunder_orgs_info WHERE organization = ? LIMIT 1',
        { organization }
    )
end

function DB.UpdateOrgBank(organization, bank, historic_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET bank = ?, bank_historic = ? WHERE organization = ?',
        { tonumber(bank) or 0, historic_json or '[]', organization }
    )
end

function DB.UpdateOrgDiscord(organization, discord)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET discord = ? WHERE organization = ?',
        { discord or '', organization }
    )
end

function DB.UpdateOrgRadio(organization, radio)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET radio = ? WHERE organization = ?',
        { radio or '', organization }
    )
end

function DB.UpdateOrgPresets(organization, presets_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET presets = ? WHERE organization = ?',
        { presets_json or '{}', organization }
    )
end

function DB.UpdateOrgPermissions(organization, permissions_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET permissions = ? WHERE organization = ?',
        { permissions_json or '{}', organization }
    )
end

function DB.UpdateOrgGoals(organization, goals_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET config_goals = ? WHERE organization = ?',
        { goals_json or '{}', organization }
    )
end

function DB.UpdateOrgSalary(organization, salary_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET salary = ? WHERE organization = ?',
        { salary_json or '{}', organization }
    )
end

function DB.UpdateOrgAlerts(organization, alerts_json)
    return MySQL.update.await(
        'UPDATE thunder_orgs_info SET alerts = ? WHERE organization = ?',
        { alerts_json or '[]', organization }
    )
end

function DB.ChatSaveMessage(organization, citizenid, message, author)
    return MySQL.insert.await([[
        INSERT INTO thunder_orgs_chat (organization, user_identifier, message, author, created_at)
        VALUES (?, ?, ?, ?, NOW())
    ]], { organization, citizenid, message, author })
end

function DB.ChatGetMessages(organization)
    return MySQL.query.await([[
        SELECT user_identifier, message, author, created_at
        FROM thunder_orgs_chat
        WHERE organization = ?
        ORDER BY created_at DESC
        LIMIT 100
    ]], { organization })
end

function DB.GetMyGoals(citizenid, organization, day, month)
    return MySQL.query.await([[
        SELECT *
        FROM thunder_orgs_goals
        WHERE user_identifier = ? AND organization = ? AND day = ? AND month = ?
    ]], { citizenid, organization, day, month })
end

function DB.UpdGoalStep(citizenid, organization, day, month, step, reward_step)
    return MySQL.update.await([[
        UPDATE thunder_orgs_goals
        SET step = ?, reward_step = ?
        WHERE user_identifier = ? AND organization = ? AND day = ? AND month = ?
    ]], { step, reward_step, citizenid, organization, day, month })
end

function DB.GetDailyFarms(organization, day, month)
    return MySQL.query.await([[
        SELECT *
        FROM thunder_orgs_goals
        WHERE organization = ? AND day = ? AND month = ?
        ORDER BY amount DESC
    ]], { organization, day, month })
end

function DB.GetDailyFarmsByUser(organization, day, month, citizenid)
    return MySQL.query.await([[
        SELECT *
        FROM thunder_orgs_goals
        WHERE organization = ? AND day = ? AND month = ? AND user_identifier = ?
        ORDER BY amount DESC
    ]], { organization, day, month, citizenid })
end

function DB.AddPlayerFarm(organization, citizenid, item, amount, day, month)
    return MySQL.update.await([[
        INSERT INTO thunder_orgs_goals (organization, user_identifier, item, amount, day, month)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], { organization, citizenid, item, tonumber(amount) or 0, day, month })
end

function DB.GetChestLogs(organization)
    return MySQL.query.await(
        'SELECT user_identifier, role, name, description, date, expire_at FROM thunder_orgs_logs WHERE organization = ? ORDER BY expire_at DESC LIMIT 150',
        { organization }
    )
end

function DB.AddChestLog(organization, citizenid, role, name, description, date_str, expire_at)
    return MySQL.insert.await(
        'INSERT INTO thunder_orgs_logs (organization, user_identifier, role, name, description, date, expire_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { organization, citizenid, role or 'Sem cargo', name or 'N/A', description or '', date_str or os.date('%d/%m/%Y %X'), expire_at or (os.time() + 7*86400) }
    )
end

function DB.GetAllUsersInfo()
    return MySQL.query.await('SELECT * FROM thunder_orgs_player_infos', {})
end

function DB.GetUserInfo(citizenid)
    return MySQL.single.await('SELECT * FROM thunder_orgs_player_infos WHERE citizenid = ? LIMIT 1', { citizenid })
end

function DB.DeleteUserInfo(citizenid)
    return MySQL.update.await('DELETE FROM thunder_orgs_player_infos WHERE citizenid = ?', { citizenid })
end

function DB.DeleteUserInfoByOrg(citizenid, organization)
    return MySQL.update.await('DELETE FROM thunder_orgs_player_infos WHERE citizenid = ? AND organization = ?', { citizenid, organization })
end

function DB.InsertPlayerOrganization(citizenid, organization, joindate, lastlogin, timeplayed)
    return MySQL.insert.await([[
        INSERT IGNORE INTO thunder_orgs_player_infos (citizenid, organization, joindate, lastlogin, timeplayed)
        VALUES (?, ?, ?, ?, ?)
    ]], { citizenid, organization, tonumber(joindate) or os.time(), tonumber(lastlogin) or os.time(), tonumber(timeplayed) or 0 })
end

function DB.CreatePartnersTable()
    return MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS thunder_partners (
            id INT AUTO_INCREMENT PRIMARY KEY,
            cds TEXT NULL,
            name VARCHAR(100) NULL,
            note INT NULL DEFAULT 0,
            description TEXT NULL,
            icon TEXT NULL,
            groups TEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]], {})
end

function DB.InsertPartner(cds, name, note, description, icon, groups)
    return MySQL.insert.await([[
        INSERT INTO thunder_partners (cds, name, note, description, icon, groups)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { cds or '[]', name or '', tonumber(note) or 0, description or '', icon or '', groups or '' })
end

function DB.GetPartners()
    return MySQL.query.await('SELECT * FROM thunder_partners', {})
end

function DB.DeletePartner(id)
    return MySQL.update.await('DELETE FROM thunder_partners WHERE id = ?', { tonumber(id) or 0 })
end

function DB.GetPartner(id)
    return MySQL.single.await('SELECT * FROM thunder_partners WHERE id = ? LIMIT 1', { tonumber(id) or 0 })
end

-- Exports úteis
exports('GetOrgInfo',        DB.GetOrgInfo)
exports('GetOrgBank',        DB.GetOrgBank)
exports('UpdateOrgBank',     DB.UpdateOrgBank)
exports('GetChestLogs',      DB.GetChestLogs)
exports('AddChestLog',       DB.AddChestLog)
exports('InsertPlayerOrg',   DB.InsertPlayerOrganization)

-- Bootstrap
CreateThread(function()
    if not WaitForMySQL(20000) then
        print(('[%s] ^1ERRO:^0 oxmysql (MySQL global) não disponível. Confira o fxmanifest e a ordem dos recursos.'):format(RES_NAME:upper()))
        return
    end
    EnsureSchema()
    local using = Core and (GetResourceState('qbx-core') == 'started' and 'qbx-core' or 'qb-core') or 'sem core'
    print(('[%s] Bridge carregada. Core: %s | Banco: oxmysql (MySQL.*.await)'):format(RES_NAME:upper(), using))
end)
