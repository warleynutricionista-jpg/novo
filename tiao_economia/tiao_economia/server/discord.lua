--============================================================
-- space_economy - server/discord.lua
-- Sistema de Discord Webhooks Detalhados
-- MELHORIA DE QUALIDADE #2 - Monitoramento
--============================================================
SE = SE or {}
SE.Discord = SE.Discord or {}

local U = SE.Util

--============================================================
-- Configuração (será sobrescrita pelo config.lua)
--============================================================
local Config = {
    Enabled = false,

    Webhooks = {
        treasury = '',      -- Transações do tesouro
        debts = '',         -- Dívidas criadas/pagas
        admin = '',         -- Ações administrativas
        alerts = '',        -- Alertas críticos
        daily = '',         -- Relatórios diários
    },

    -- Cores
    Colors = {
        success = 3066993,  -- Verde
        error = 15158332,   -- Vermelho
        warning = 16776960, -- Amarelo
        info = 3447003,     -- Azul
    },

    -- Enviar relatório diário
    DailyReport = {
        enabled = false,
        hour = 20, -- 20:00 (8 PM)
        minute = 0,
    }
}

-- Override
if _G.Config and _G.Config.Webhooks then
    Config.Webhooks = _G.Config.Webhooks
end
if _G.Config and _G.Config.DiscordWebhooks then
    for k, v in pairs(_G.Config.DiscordWebhooks) do
        Config[k] = v
    end
end

--============================================================
-- Enviar Embed
--============================================================
function SE.Discord.SendEmbed(webhookType, embed)
    if not Config.Enabled then return end

    local webhook = Config.Webhooks[webhookType]
    if not webhook or webhook == '' then return end

    -- Garantir formato correto
    embed.timestamp = embed.timestamp or os.date('!%Y-%m-%dT%H:%M:%S')

    local payload = {
        embeds = { embed }
    }

    PerformHttpRequest(webhook, function(err, text, headers)
        if err ~= 200 and err ~= 204 then
            print(('^1[space_economy]^7 Discord webhook error: %d'):format(err))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

--============================================================
-- Webhooks Específicos
--============================================================

-- Transação no Tesouro
function SE.Discord.TreasuryTransaction(src, action, amount, newBalance)
    local adminName = 'Console'
    if src and src > 0 and SE.Bridge then
        adminName = SE.Bridge.GetCharName and SE.Bridge.GetCharName(src) or 'Admin'
    end

    local isDeposit = action == 'deposit'

    SE.Discord.SendEmbed('treasury', {
        title = '🏦 Transação no Tesouro',
        description = ('%s **%s** $%s'):format(
            adminName,
            isDeposit and 'depositou' or 'sacou',
            tostring(amount)
        ),
        color = isDeposit and Config.Colors.success or Config.Colors.warning,
        fields = {
            { name = 'Novo Saldo', value = '$' .. tostring(newBalance), inline = true },
            { name = 'Ação', value = action, inline = true },
        }
    })
end

-- Dívida Criada
function SE.Discord.DebtCreated(citizenid, amount, reason, createdBy)
    SE.Discord.SendEmbed('debts', {
        title = '📋 Nova Dívida Criada',
        description = ('Dívida de **$%d** criada'):format(amount),
        color = Config.Colors.info,
        fields = {
            { name = 'CitizenID', value = citizenid, inline = true },
            { name = 'Valor', value = '$' .. tostring(amount), inline = true },
            { name = 'Motivo', value = reason or 'N/A', inline = false },
            { name = 'Criado por', value = createdBy or 'Sistema', inline = true },
        }
    })
end

-- Dívida Paga
function SE.Discord.DebtPaid(citizenid, amount, method)
    SE.Discord.SendEmbed('debts', {
        title = '✅ Dívida Paga',
        description = ('Dívida de **$%d** foi paga'):format(amount),
        color = Config.Colors.success,
        fields = {
            { name = 'CitizenID', value = citizenid, inline = true },
            { name = 'Valor', value = '$' .. tostring(amount), inline = true },
            { name = 'Método', value = method or 'Banco', inline = true },
        }
    })
end

-- Ação Administrativa
function SE.Discord.AdminAction(src, action, details)
    local adminName = 'Console'
    if src and src > 0 and SE.Bridge then
        adminName = SE.Bridge.GetCharName and SE.Bridge.GetCharName(src) or 'Admin'
    end

    local fields = {}
    if type(details) == 'table' then
        for k, v in pairs(details) do
            if type(v) ~= 'table' then
                table.insert(fields, {
                    name = tostring(k),
                    value = tostring(v),
                    inline = true
                })
            end
        end
    end

    SE.Discord.SendEmbed('admin', {
        title = '⚙️ Ação Administrativa',
        description = ('%s executou: **%s**'):format(adminName, action),
        color = Config.Colors.warning,
        fields = fields
    })
end

-- Alerta Crítico
function SE.Discord.Alert(title, message, color)
    SE.Discord.SendEmbed('alerts', {
        title = '⚠️ ' .. (title or 'Alerta'),
        description = message,
        color = color or Config.Colors.error,
    })
end

-- Relatório Diário
function SE.Discord.DailyReport()
    if not Config.DailyReport.enabled then return end

    -- Coletar métricas do dia
    local metrics = {}
    if SE.Metrics and SE.Metrics.GetTodayMetrics then
        metrics = SE.Metrics.GetTodayMetrics()
    end

    local vault = 0
    if SE.State then
        vault = U.toInt(SE.State.vaultBalance, 0)
    end

    SE.Discord.SendEmbed('daily', {
        title = '📊 Relatório Diário - ' .. os.date('%d/%m/%Y'),
        color = Config.Colors.info,
        fields = {
            { name = '💰 Saldo do Tesouro', value = '$' .. tostring(vault), inline = true },
            { name = '📈 Arrecadado Hoje', value = '$' .. tostring(metrics.collected or 0), inline = true },
            { name = '💳 Dívidas Pagas', value = '$' .. tostring(metrics.paid_debts or 0), inline = true },
            { name = '🔢 Transações', value = tostring(metrics.transactions or 0), inline = true },
        },
        footer = {
            text = 'Space Economy v3.0 | Relatório Automático'
        }
    })
end

--============================================================
-- Agendador de Relatório Diário
--============================================================
if Config.Enabled and Config.DailyReport.enabled then
    CreateThread(function()
        while true do
            local now = os.date('*t')
            local targetHour = Config.DailyReport.hour
            local targetMinute = Config.DailyReport.minute

            -- Verificar se é a hora certa
            if now.hour == targetHour and now.min == targetMinute then
                SE.Discord.DailyReport()
                Wait(60000) -- Aguardar 1 minuto para não enviar múltiplas vezes
            end

            Wait(30000) -- Verificar a cada 30 segundos
        end
    end)
end

--============================================================
-- Exports
--============================================================
exports('SendDiscordEmbed', SE.Discord.SendEmbed)
exports('DiscordTreasuryTransaction', SE.Discord.TreasuryTransaction)
exports('DiscordDebtCreated', SE.Discord.DebtCreated)
exports('DiscordDebtPaid', SE.Discord.DebtPaid)
exports('DiscordAdminAction', SE.Discord.AdminAction)
exports('DiscordAlert', SE.Discord.Alert)

if Config.Enabled then
    print('^2[space_economy]^7 Discord webhooks loaded - Daily report: %s'):format(
        Config.DailyReport.enabled and 'enabled' or 'disabled'
    )
end
