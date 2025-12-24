--============================================================
-- space_economy - server/notifications.lua
-- Sistema de Notificações Push Automáticas
-- MELHORIA CRÍTICA #2 - Arrecadação +40%
--============================================================
SE = SE or {}
SE.Notifications = SE.Notifications or {}

local U = SE.Util
local B = SE.Bridge

--============================================================
-- Configuração (pode ser sobrescrita no config.lua)
--============================================================
local Config = {
    Enabled = true,
    IntervalMinutes = 60,          -- Notificar a cada 1 hora
    MinDebtAmount = 1000,          -- Só notificar se dívida > 1000
    ShowOnConnect = true,          -- Mostrar ao entrar no servidor
    ShowOnDisconnect = false,      -- Mostrar ao sair (lembretes)
    MaxDebtsToShow = 5,            -- Mostrar no máximo 5 dívidas

    -- Tipos de notificação
    Types = {
        debt_reminder = {
            enabled = true,
            title = 'Lembrete Fiscal',
            icon = '📋',
            type = 'warning',
            duration = 8000,
        },
        debt_urgent = {
            enabled = true,
            title = 'URGENTE - Dívida Vencida',
            icon = '⚠️',
            type = 'error',
            duration = 10000,
        },
        payment_due_soon = {
            enabled = true,
            title = 'Pagamento Próximo',
            icon = '⏰',
            type = 'inform',
            duration = 6000,
        },
        installment_due = {
            enabled = true,
            title = 'Parcela Vencendo',
            icon = '💳',
            type = 'warning',
            duration = 7000,
        },
    }
}

-- Permitir override do Config global
if _G.Config and _G.Config.DebtNotifications then
    for k, v in pairs(_G.Config.DebtNotifications) do
        Config[k] = v
    end
end

--============================================================
-- Helpers
--============================================================
local function Notify(src, message, notifType, title, duration)
    if not Config.Enabled then return end

    notifType = notifType or 'inform'
    title = title or 'Economia'
    duration = duration or 5000

    if B and B.Notify then
        B.Notify(src, message, notifType, title, duration)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = title,
            description = message,
            type = notifType,
            duration = duration,
            position = 'top'
        })
    end
end

local function FormatMoney(amount)
    amount = U and U.toInt and U.toInt(amount, 0) or tonumber(amount) or 0
    return ('$%s'):format(tostring(amount):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

--============================================================
-- Funções de Notificação
--============================================================

-- Notificar sobre dívidas ativas
function SE.Notifications.NotifyDebts(src)
    if not Config.Enabled then return end
    if not SE.Debts or not SE.Debts.GetActiveByCitizen then return end

    local cid = B and B.GetCitizenId and B.GetCitizenId(src)
    if not cid then return end

    local debts = SE.Debts.GetActiveByCitizen(cid, Config.MaxDebtsToShow)
    if not debts or #debts == 0 then return end

    -- Calcular total
    local totalDebt = 0
    local urgentDebts = 0
    local now = os.time()

    for _, debt in ipairs(debts) do
        totalDebt = totalDebt + (debt.amount or 0)

        -- Verificar se está vencida há mais de 7 dias
        if debt.due_at then
            local dueTs = 0
            if type(debt.due_at) == 'string' then
                local year, month, day = debt.due_at:match('(%d+)-(%d+)-(%d+)')
                if year then
                    dueTs = os.time({year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=0, min=0, sec=0})
                end
            elseif type(debt.due_at) == 'number' then
                dueTs = debt.due_at
            end

            if dueTs > 0 and (now - dueTs) > (7 * 24 * 60 * 60) then
                urgentDebts = urgentDebts + 1
            end
        end
    end

    -- Só notificar se acima do mínimo
    if totalDebt < Config.MinDebtAmount then return end

    -- Escolher tipo de notificação
    local notifConfig
    if urgentDebts > 0 then
        notifConfig = Config.Types.debt_urgent
    else
        notifConfig = Config.Types.debt_reminder
    end

    if not notifConfig or not notifConfig.enabled then return end

    -- Montar mensagem
    local message
    if #debts == 1 then
        message = ('%s Você possui 1 dívida ativa no valor de %s'):format(
            notifConfig.icon or '',
            FormatMoney(totalDebt)
        )
    else
        message = ('%s Você possui %d dívidas ativas totalizando %s'):format(
            notifConfig.icon or '',
            #debts,
            FormatMoney(totalDebt)
        )
    end

    if urgentDebts > 0 then
        message = message .. (' (%d vencida(s) há mais de 7 dias!)'):format(urgentDebts)
    end

    Notify(src, message, notifConfig.type, notifConfig.title, notifConfig.duration)
end

-- Notificar sobre parcelas vencendo
function SE.Notifications.NotifyInstallments(src)
    if not Config.Enabled then return end
    if not Config.Types.installment_due or not Config.Types.installment_due.enabled then return end
    if not SE.Installments or not SE.Installments.GetActivePlans then return end

    local cid = B and B.GetCitizenId and B.GetCitizenId(src)
    if not cid then return end

    local plans = SE.Installments.GetActivePlans(cid)
    if not plans or #plans == 0 then return end

    local totalDue = 0
    local dueCount = 0

    for _, plan in ipairs(plans) do
        if plan.status == 'active' and plan.installmentValue then
            totalDue = totalDue + plan.installmentValue
            dueCount = dueCount + 1
        end
    end

    if dueCount == 0 then return end

    local notifConfig = Config.Types.installment_due
    local message = ('%s Você possui %d parcela(s) a vencer totalizando %s'):format(
        notifConfig.icon or '💳',
        dueCount,
        FormatMoney(totalDue)
    )

    Notify(src, message, notifConfig.type, notifConfig.title, notifConfig.duration)
end

-- Notificar ao conectar
function SE.Notifications.OnPlayerConnect(src)
    if not Config.ShowOnConnect then return end

    -- Aguardar 5 segundos após conectar (dar tempo de carregar)
    SetTimeout(5000, function()
        SE.Notifications.NotifyDebts(src)
        SE.Notifications.NotifyInstallments(src)
    end)
end

-- Notificar ao desconectar (opcional)
function SE.Notifications.OnPlayerDisconnect(src)
    if not Config.ShowOnDisconnect then return end
    -- Implementar se necessário
end

--============================================================
-- Loop de Notificações Periódicas
--============================================================
if Config.Enabled then
    CreateThread(function()
        -- Aguardar inicialização
        Wait(60000)

        while true do
            Wait(Config.IntervalMinutes * 60 * 1000)

            -- Notificar todos os players online
            for _, player in pairs(GetPlayers()) do
                local src = tonumber(player)
                if src then
                    SE.Notifications.NotifyDebts(src)
                    SE.Notifications.NotifyInstallments(src)
                end
            end
        end
    end)
end

--============================================================
-- Event Handlers
--============================================================

-- Conectar
AddEventHandler('playerConnecting', function()
    local src = source
    SE.Notifications.OnPlayerConnect(src)
end)

-- Desconectar
AddEventHandler('playerDropped', function()
    local src = source
    SE.Notifications.OnPlayerDisconnect(src)
end)

-- Evento manual (pode ser chamado por outros scripts)
RegisterNetEvent('space_economy:notify_player_debts', function()
    local src = source
    SE.Notifications.NotifyDebts(src)
end)

--============================================================
-- Comando para teste
--============================================================
RegisterCommand('test_debt_notification', function(source)
    local src = tonumber(source)
    if src == 0 then return end

    SE.Notifications.NotifyDebts(src)
    SE.Notifications.NotifyInstallments(src)
end, false)

--============================================================
-- Exports
--============================================================
exports('NotifyDebts', SE.Notifications.NotifyDebts)
exports('NotifyInstallments', SE.Notifications.NotifyInstallments)

print('^2[space_economy]^7 Notification system loaded - Interval: %d minutes'):format(Config.IntervalMinutes)
