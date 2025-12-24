--============================================================
-- space_economy - server/rewards.lua
-- Sistema de Recompensas por Pagamento em Dia
-- MELHORIA DE QUALIDADE #1 - Gamificação
--============================================================
SE = SE or {}
SE.Rewards = SE.Rewards or {}

local U = SE.Util
local B = SE.Bridge

--============================================================
-- Configuração
--============================================================
local Config = {
    Enabled = true,

    -- Níveis de desconto baseados em pagamentos em dia
    DiscountTiers = {
        { paymentsOnTime = 5,  discount = 0.02, label = 'Bronze' },   -- 2%
        { paymentsOnTime = 10, discount = 0.05, label = 'Prata' },    -- 5%
        { paymentsOnTime = 20, discount = 0.10, label = 'Ouro' },     -- 10%
        { paymentsOnTime = 50, discount = 0.15, label = 'Platina' },  -- 15%
    },

    -- Resetar streak após X dias sem pagar
    StreakResetDays = 14,

    -- Notificar ao subir de nível
    NotifyLevelUp = true,
}

-- Override do config global
if _G.Config and _G.Config.PaymentRewards then
    for k, v in pairs(_G.Config.PaymentRewards) do
        Config[k] = v
    end
end

--============================================================
-- Helpers
--============================================================
local function GetRewardRecord(citizenid)
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT * FROM space_economy_rewards
            WHERE citizenid = ?
            LIMIT 1
        ]], { citizenid })
    end)

    return ok and row or nil
end

local function CreateRewardRecord(citizenid)
    local ok, insertId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO space_economy_rewards
            (citizenid, payments_on_time, payments_late, current_streak, best_streak, total_paid, discount_level)
            VALUES (?, 0, 0, 0, 0, 0, 0)
        ]], { citizenid })
    end)

    if ok and insertId then
        return GetRewardRecord(citizenid)
    end

    return nil
end

local function UpdateRewardRecord(citizenid, fields)
    local sets = {}
    local params = {}

    for k, v in pairs(fields) do
        table.insert(sets, k .. ' = ?')
        table.insert(params, v)
    end

    table.insert(params, citizenid)

    local ok = pcall(function()
        MySQL.update.await(([[
            UPDATE space_economy_rewards
            SET %s, updated_at = NOW()
            WHERE citizenid = ?
        ]]):format(table.concat(sets, ', ')), params)
    end)

    return ok
end

--============================================================
-- Calcular Nível de Desconto
--============================================================
function SE.Rewards.CalculateDiscountLevel(paymentsOnTime)
    local level = 0
    local discount = 0.0
    local label = 'Nenhum'

    for i, tier in ipairs(Config.DiscountTiers) do
        if paymentsOnTime >= tier.paymentsOnTime then
            level = i
            discount = tier.discount
            label = tier.label
        end
    end

    return level, discount, label
end

--============================================================
-- Registrar Pagamento
--============================================================
function SE.Rewards.RecordPayment(citizenid, amount, onTime)
    if not Config.Enabled then return end

    citizenid = tostring(citizenid or '')
    if citizenid == '' then return end

    amount = U.toInt(amount, 0)
    onTime = onTime ~= false -- Default: true

    -- Buscar ou criar registro
    local record = GetRewardRecord(citizenid)
    if not record then
        record = CreateRewardRecord(citizenid)
        if not record then return end
    end

    -- Atualizar contadores
    local newOnTime = U.toInt(record.payments_on_time, 0)
    local newLate = U.toInt(record.payments_late, 0)
    local newStreak = U.toInt(record.current_streak, 0)
    local newBestStreak = U.toInt(record.best_streak, 0)
    local newTotalPaid = U.toInt(record.total_paid, 0) + amount

    if onTime then
        newOnTime = newOnTime + 1
        newStreak = newStreak + 1

        if newStreak > newBestStreak then
            newBestStreak = newStreak
        end
    else
        newLate = newLate + 1
        newStreak = 0 -- Resetar streak
    end

    -- Calcular novo nível
    local newLevel, newDiscount, newLabel = SE.Rewards.CalculateDiscountLevel(newOnTime)
    local oldLevel = U.toInt(record.discount_level, 0)

    -- Atualizar banco
    UpdateRewardRecord(citizenid, {
        payments_on_time = newOnTime,
        payments_late = newLate,
        current_streak = newStreak,
        best_streak = newBestStreak,
        total_paid = newTotalPaid,
        discount_level = newLevel,
        last_payment_date = 'NOW()'
    })

    -- Notificar subida de nível
    if Config.NotifyLevelUp and newLevel > oldLevel then
        local src = B and B.GetSourceByCitizenId and B.GetSourceByCitizenId(citizenid)
        if src then
            B.Notify(src,
                ('🎉 Parabéns! Você subiu para o nível %s! Desconto: %.0f%%'):format(newLabel, newDiscount * 100),
                'success',
                'Sistema de Recompensas',
                10000
            )
        end

        -- Log
        SE.Log('rewards', 'Subida de nível', {
            citizenid = citizenid,
            old_level = oldLevel,
            new_level = newLevel,
            new_discount = newDiscount,
            label = newLabel
        })
    end
end

--============================================================
-- Obter Desconto do Player
--============================================================
function SE.Rewards.GetDiscount(citizenid)
    if not Config.Enabled then return 0.0 end

    citizenid = tostring(citizenid or '')
    if citizenid == '' then return 0.0 end

    local record = GetRewardRecord(citizenid)
    if not record then return 0.0 end

    local level, discount = SE.Rewards.CalculateDiscountLevel(U.toInt(record.payments_on_time, 0))
    return discount
end

--============================================================
-- Aplicar Desconto em Valor
--============================================================
function SE.Rewards.ApplyDiscount(citizenid, baseAmount)
    local discount = SE.Rewards.GetDiscount(citizenid)
    if discount <= 0 then return baseAmount end

    local discountAmount = math.floor(baseAmount * discount)
    local finalAmount = baseAmount - discountAmount

    return finalAmount, discountAmount
end

--============================================================
-- Obter Informações do Player
--============================================================
function SE.Rewards.GetPlayerInfo(citizenid)
    if not Config.Enabled then return nil end

    citizenid = tostring(citizenid or '')
    if citizenid == '' then return nil end

    local record = GetRewardRecord(citizenid)
    if not record then return nil end

    local level, discount, label = SE.Rewards.CalculateDiscountLevel(U.toInt(record.payments_on_time, 0))

    return {
        citizenid = citizenid,
        payments_on_time = U.toInt(record.payments_on_time, 0),
        payments_late = U.toInt(record.payments_late, 0),
        current_streak = U.toInt(record.current_streak, 0),
        best_streak = U.toInt(record.best_streak, 0),
        total_paid = U.toInt(record.total_paid, 0),
        discount_level = level,
        discount_percent = discount,
        discount_label = label,
        payment_rate = record.payments_on_time > 0 and
            math.floor((record.payments_on_time / (record.payments_on_time + record.payments_late)) * 100) or 0
    }
end

--============================================================
-- Top Bons Pagadores
--============================================================
function SE.Rewards.GetTopPayers(limit)
    limit = U.toInt(limit or 10, 10)

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT citizenid, payments_on_time, current_streak, best_streak,
                   total_paid, discount_level
            FROM space_economy_rewards
            WHERE payments_on_time > 0
            ORDER BY discount_level DESC, current_streak DESC
            LIMIT ?
        ]], { limit })
    end)

    if not ok or not rows then return {} end

    -- Enriquecer com nomes e labels
    for i, row in ipairs(rows) do
        local name = 'Desconhecido'
        if SE.CharCache and SE.CharCache.GetName then
            name = SE.CharCache.GetName(row.citizenid) or name
        end

        local level, discount, label = SE.Rewards.CalculateDiscountLevel(U.toInt(row.payments_on_time, 0))

        rows[i].playerName = name
        rows[i].discount_label = label
        rows[i].discount_percent = discount
    end

    return rows
end

--============================================================
-- Comando para ver recompensas
--============================================================
RegisterCommand('minhas_recompensas', function(source)
    local src = tonumber(source)
    if src == 0 then return end

    local cid = B and B.GetCitizenId and B.GetCitizenId(src)
    if not cid then return end

    local info = SE.Rewards.GetPlayerInfo(cid)
    if not info then
        B.Notify(src, 'Você ainda não possui recompensas', 'inform')
        return
    end

    local message = ([[
🏆 Suas Recompensas:
━━━━━━━━━━━━━━━━━━━━
Nível: %s
Desconto: %.0f%%
━━━━━━━━━━━━━━━━━━━━
✅ Pagamentos em dia: %d
❌ Pagamentos atrasados: %d
🔥 Sequência atual: %d
⭐ Melhor sequência: %d
💰 Total pago: $%d
📊 Taxa de sucesso: %d%%
    ]]):format(
        info.discount_label,
        info.discount_percent * 100,
        info.payments_on_time,
        info.payments_late,
        info.current_streak,
        info.best_streak,
        info.total_paid,
        info.payment_rate
    )

    B.Notify(src, message, 'inform', 'Sistema de Recompensas', 15000)
end, false)

--============================================================
-- Exports
--============================================================
exports('RecordPayment', SE.Rewards.RecordPayment)
exports('GetDiscount', SE.Rewards.GetDiscount)
exports('ApplyDiscount', SE.Rewards.ApplyDiscount)
exports('GetPlayerRewardInfo', SE.Rewards.GetPlayerInfo)
exports('GetTopPayers', SE.Rewards.GetTopPayers)

print('^2[space_economy]^7 Rewards system loaded - Tiers: %d'):format(#Config.DiscountTiers)
