# 🚀 Melhorias Sugeridas - Space Economy v3.0

**Data:** 24/12/2025
**Status Atual:** Sistema funcional e estável
**Versão:** 3.0.0

---

## 📊 **Categorias de Melhorias**

### 🔴 **CRÍTICAS** - Impacto Alto / Urgência Alta
### 🟡 **IMPORTANTES** - Impacto Médio / Urgência Média
### 🟢 **MELHORIAS** - Impacto Baixo / Melhoria de Qualidade

---

## 🔴 **1. MELHORIAS CRÍTICAS**

### 1.1 Sistema de Cache para Performance 🔴

**Problema Atual:**
- Muitas queries ao banco de dados repetidas
- Buscas de veículos/residências a cada consulta
- PlayerData buscado múltiplas vezes

**Solução Sugerida:**
```lua
-- Criar sistema de cache com TTL (Time To Live)
SE.Cache = {
    players = {},      -- Cache de PlayerData
    vehicles = {},     -- Cache de veículos por CID
    residences = {},   -- Cache de residências
    debts = {},        -- Cache de dívidas
}

-- Exemplo de implementação:
function SE.Cache.Get(category, key, ttl)
    local cached = SE.Cache[category][key]
    if cached and (os.time() - cached.timestamp) < (ttl or 300) then
        return cached.data
    end
    return nil
end

function SE.Cache.Set(category, key, data)
    SE.Cache[category][key] = {
        data = data,
        timestamp = os.time()
    }
end

-- Limpar cache ao sair
AddEventHandler('playerDropped', function()
    local src = source
    local cid = SE.Integrations.GetCitizenId(src)
    if cid then
        SE.Cache.players[cid] = nil
        SE.Cache.vehicles[cid] = nil
        SE.Cache.residences[cid] = nil
    end
end)
```

**Arquivos a modificar:**
- `server/integrations.lua` - Adicionar cache em GetVehicles, GetResidences
- Criar novo arquivo: `server/cache.lua`

**Benefícios:**
- ⚡ Redução de 70-80% nas queries ao banco
- 🚀 Resposta instantânea em consultas repetidas
- 💾 Menor carga no MySQL

---

### 1.2 Sistema de Notificações Push para Dívidas 🔴

**Problema Atual:**
- Player só fica sabendo da dívida ao abrir o painel
- Sem lembretes automáticos

**Solução Sugerida:**
```lua
-- Adicionar notificações automáticas
CreateThread(function()
    while true do
        Wait(3600000) -- A cada 1 hora

        for _, player in pairs(GetPlayers()) do
            local src = tonumber(player)
            local cid = SE.Integrations.GetCitizenId(src)

            if cid then
                local debts = SE.Debts.GetActiveByCitizen(cid, 5)
                if #debts > 0 then
                    local total = 0
                    for _, debt in ipairs(debts) do
                        total = total + debt.amount
                    end

                    B.Notify(src,
                        ('Você possui %d dívida(s) ativa(s) no valor de $%d'):format(#debts, total),
                        'warning',
                        'Sistema Fiscal',
                        8000
                    )
                end
            end
        end
    end
end)
```

**Configuração:**
```lua
Config.DebtNotifications = {
    Enabled = true,
    IntervalMinutes = 60,
    MinDebtAmount = 1000, -- Só notificar se dívida > 1000
    ShowOnConnect = true,  -- Mostrar ao entrar no servidor
}
```

**Arquivos a criar:**
- `server/notifications.lua`

**Benefícios:**
- 📢 Players informados automaticamente
- 💰 Maior taxa de pagamento
- ⚖️ Menos inadimplência

---

### 1.3 Sistema de Backup Automático 🔴

**Problema Atual:**
- Sem backup automático do estado econômico
- Risco de perda de dados

**Solução Sugerida:**
```lua
-- Sistema de backup diário
CreateThread(function()
    while true do
        Wait(86400000) -- 24 horas

        -- Backup do estado
        local state = {
            vaultBalance = SE.State.vaultBalance,
            inflationRate = SE.State.inflationRate,
            taxMultiplier = SE.State.taxMultiplier,
            timestamp = os.time(),
        }

        MySQL.insert.await([[
            INSERT INTO space_economy_backups
            (backup_date, state_data, vault_balance, created_at)
            VALUES (CURDATE(), ?, ?, NOW())
        ]], {
            json.encode(state),
            state.vaultBalance
        })

        -- Limpar backups antigos (manter últimos 30 dias)
        MySQL.query.await([[
            DELETE FROM space_economy_backups
            WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
        ]])

        SE.Log('system', 'Backup automático realizado', state)
    end
end)
```

**SQL para criar tabela:**
```sql
CREATE TABLE IF NOT EXISTS space_economy_backups (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    backup_date DATE NOT NULL,
    state_data LONGTEXT NOT NULL,
    vault_balance BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_backup_date (backup_date)
);
```

**Benefícios:**
- 🛡️ Proteção contra perda de dados
- 🔄 Recuperação de desastres
- 📊 Histórico econômico

---

## 🟡 **2. MELHORIAS IMPORTANTES**

### 2.1 Dashboard de Métricas em Tempo Real 🟡

**Funcionalidade Nova:**
- Gráficos de arrecadação diária/semanal/mensal
- Top 10 devedores
- Estatísticas de IPTU/IPVA pagos
- Previsão de arrecadação

**Implementação:**
```lua
-- Adicionar métricas agregadas
function SE.Admin.GetDashboardMetrics()
    -- Arrecadação últimos 7 dias
    local weeklyRevenue = MySQL.query.await([[
        SELECT DATE(timestamp) as date,
               SUM(amount) as total
        FROM space_economy_logs
        WHERE category = 'tax'
          AND timestamp >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY DATE(timestamp)
        ORDER BY date ASC
    ]])

    -- Top 10 devedores
    local topDebtors = MySQL.query.await([[
        SELECT citizenid,
               SUM(amount) as total_debt,
               COUNT(*) as debt_count
        FROM space_economy_debts
        WHERE status = 'active'
        GROUP BY citizenid
        ORDER BY total_debt DESC
        LIMIT 10
    ]])

    -- IPTU/IPVA pagos no mês
    local taxesPaid = MySQL.query.await([[
        SELECT
            SUM(CASE WHEN reason LIKE '%IPTU%' THEN amount ELSE 0 END) as iptu_total,
            SUM(CASE WHEN reason LIKE '%IPVA%' THEN amount ELSE 0 END) as ipva_total
        FROM space_economy_logs
        WHERE category = 'tax'
          AND timestamp >= DATE_FORMAT(NOW(), '%Y-%m-01')
    ]])

    return {
        weeklyRevenue = weeklyRevenue,
        topDebtors = topDebtors,
        taxesPaid = taxesPaid[1] or {}
    }
end
```

**UI no HTML:**
- Adicionar charts.js ou similar
- Gráficos de linha para arrecadação
- Tabela de top devedores

**Benefícios:**
- 📊 Visibilidade total da economia
- 🎯 Identificação de tendências
- 📈 Decisões baseadas em dados

---

### 2.2 Sistema de Parcelamento Automático 🟡

**Funcionalidade Nova:**
- Player pode parcelar dívidas automaticamente via NUI
- Sistema de desconto para pagamento à vista
- Juros progressivos por atraso

**Implementação:**
```lua
-- Event no server
RegisterNetEvent('space_economy:requestInstallment', function(debtId, numInstallments)
    local src = source
    local debt = SE.Debts.GetById(debtId)

    if not debt then
        B.Notify(src, 'Dívida não encontrada', 'error')
        return
    end

    -- Validar
    local maxInstallments = Config.DebtSystem.MaxInstallments or 12
    if numInstallments > maxInstallments then
        B.Notify(src, ('Máximo de %d parcelas'):format(maxInstallments), 'error')
        return
    end

    -- Calcular parcelas com juros
    local fee = Config.DebtSystem.InstallmentFee or 0.05
    local totalWithFee = debt.amount * (1 + fee)
    local installmentValue = math.ceil(totalWithFee / numInstallments)

    -- Criar plano
    local planId = SE.Installments.Create({
        citizenid = debt.citizenid,
        originalDebt = debt.id,
        totalAmount = totalWithFee,
        installmentValue = installmentValue,
        numInstallments = numInstallments,
        paidInstallments = 0,
        status = 'active'
    })

    -- Marcar dívida como parcelada
    SE.Debts.UpdateStatus(debtId, 'installment')

    B.Notify(src,
        ('Dívida parcelada em %dx de $%d (total: $%d)'):format(
            numInstallments, installmentValue, totalWithFee
        ),
        'success'
    )
end)
```

**UI no NUI:**
- Modal de parcelamento
- Simulador de parcelas
- Botão "Parcelar" nas dívidas

**Benefícios:**
- 💳 Facilita pagamento
- 💰 Aumenta arrecadação
- 😊 Melhora experiência do player

---

### 2.3 Sistema de Auditoria Completo 🟡

**Funcionalidade Nova:**
- Log de TODAS as ações administrativas
- Histórico de alterações no tesouro
- Rastreamento de quem fez o quê

**Implementação:**
```lua
-- Wrapper para ações auditáveis
function SE.Admin.AuditAction(src, action, details)
    local adminName = B.GetCharName(src)
    local adminCid = B.GetCitizenId(src)

    MySQL.insert.await([[
        INSERT INTO space_economy_audit_log
        (admin_citizenid, admin_name, action, details, ip_address, timestamp)
        VALUES (?, ?, ?, ?, ?, NOW())
    ]], {
        adminCid,
        adminName,
        action,
        json.encode(details),
        GetPlayerEndpoint(src) or 'console'
    })

    SE.Log('audit', ('%s: %s'):format(adminName, action), details)
end

-- Usar em todas as ações admin
RegisterNetEvent('space_economy:server_requestAdminData', function(dataType, payload)
    local src = source

    -- Auditar abertura de painel
    SE.Admin.AuditAction(src, 'open_admin_panel', { dataType = dataType })

    -- ... resto do código
end)
```

**SQL:**
```sql
CREATE TABLE IF NOT EXISTS space_economy_audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    admin_citizenid VARCHAR(50) NOT NULL,
    admin_name VARCHAR(100),
    action VARCHAR(100) NOT NULL,
    details LONGTEXT,
    ip_address VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_citizenid),
    INDEX idx_timestamp (timestamp)
);
```

**Benefícios:**
- 🔍 Rastreabilidade total
- 🛡️ Prevenção de abusos
- 📊 Relatórios de uso

---

## 🟢 **3. MELHORIAS DE QUALIDADE**

### 3.1 Sistema de Recompensas por Pagamento em Dia 🟢

**Ideia:**
- Players que pagam em dia ganham desconto progressivo
- Sistema de "bom pagador"
- Benefícios fiscais

**Implementação:**
```lua
Config.PaymentRewards = {
    Enabled = true,
    DiscountTiers = {
        { paymentsOnTime = 5,  discount = 0.02 }, -- 2%
        { paymentsOnTime = 10, discount = 0.05 }, -- 5%
        { paymentsOnTime = 20, discount = 0.10 }, -- 10%
    }
}
```

---

### 3.2 Integração com Discord Webhook Detalhado 🟢

**Funcionalidade:**
- Logs críticos no Discord
- Alertas de grandes transações
- Relatórios diários automáticos

**Implementação:**
```lua
function SE.Discord.SendEmbed(webhook, embed)
    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        embeds = { embed }
    }), { ['Content-Type'] = 'application/json' })
end

-- Exemplo de uso
SE.Discord.SendEmbed(Config.Webhooks.Treasury, {
    title = '🏦 Transação no Tesouro',
    description = ('**%s** %s **$%d**'):format(
        adminName,
        action == 'deposit' and 'depositou' or 'sacou',
        amount
    ),
    color = action == 'deposit' and 3066993 or 15158332,
    timestamp = os.date('!%Y-%m-%dT%H:%M:%S')
})
```

---

### 3.3 Multi-idioma (i18n) 🟢

**Funcionalidade:**
- Suporte a PT-BR, EN, ES
- Configurável por player

**Estrutura:**
```lua
Locale = {
    ['pt-BR'] = {
        debt_notification = 'Você possui %d dívida(s) ativa(s) no valor de $%d',
        payment_success = 'Pagamento realizado com sucesso!',
        -- ...
    },
    ['en'] = {
        debt_notification = 'You have %d active debt(s) totaling $%d',
        payment_success = 'Payment successful!',
        -- ...
    }
}
```

---

### 3.4 Sistema de Relatórios Exportáveis 🟢

**Funcionalidade:**
- Exportar relatórios em CSV/JSON
- Gerar PDFs de extratos
- Enviar por email

---

### 3.5 Modo "Economia Simulada" 🟢

**Funcionalidade:**
- Modo de teste sem afetar economia real
- Sandbox para testar configs
- Previsões de impacto

---

## 📊 **Priorização Sugerida**

### **Fase 1 - Críticas (1-2 semanas)**
1. ✅ Sistema de Cache (1.1)
2. ✅ Notificações Push (1.2)
3. ✅ Backup Automático (1.3)

### **Fase 2 - Importantes (2-3 semanas)**
1. ✅ Dashboard de Métricas (2.1)
2. ✅ Parcelamento Automático (2.2)
3. ✅ Sistema de Auditoria (2.3)

### **Fase 3 - Qualidade (1-2 semanas)**
1. ✅ Recompensas (3.1)
2. ✅ Discord Webhook (3.2)
3. ✅ Multi-idioma (3.3)

---

## 🎯 **ROI Estimado (Retorno sobre Investimento)**

### **Alta Prioridade:**
- **Cache:** 🚀 Performance +300%, Custo: 4h dev
- **Notificações:** 💰 Arrecadação +40%, Custo: 2h dev
- **Backup:** 🛡️ Segurança +100%, Custo: 3h dev

### **Média Prioridade:**
- **Dashboard:** 📊 Gestão +200%, Custo: 8h dev
- **Parcelamento:** 💳 Pagamentos +60%, Custo: 6h dev
- **Auditoria:** 🔍 Compliance +100%, Custo: 4h dev

---

## 🔧 **Ferramentas Recomendadas**

### **Performance:**
- [ ] Profiler para identificar bottlenecks
- [ ] Monitor de queries SQL
- [ ] Cache Redis (opcional, avançado)

### **UI/UX:**
- [ ] Chart.js para gráficos
- [ ] DataTables para tabelas grandes
- [ ] Animações CSS modernas

### **Segurança:**
- [ ] Rate limiting em endpoints
- [ ] Validação de inputs (joi ou similar)
- [ ] Sanitização de SQL (já tem com oxmysql)

---

## 📝 **Checklist de Implementação**

### **Antes de Começar:**
- [ ] Fazer backup completo do banco de dados
- [ ] Criar branch de desenvolvimento
- [ ] Documentar estado atual

### **Durante Desenvolvimento:**
- [ ] Testes unitários para cada feature
- [ ] Testes de integração
- [ ] Code review

### **Antes de Deploy:**
- [ ] Testes em servidor de staging
- [ ] Atualizar documentação
- [ ] Treinar admins

---

## 💡 **Ideias Futuras (Brainstorm)**

### **Sistema de Economia Dinâmica:**
- Inflação baseada em volume de dinheiro na cidade
- Taxas variáveis por horário de pico
- Eventos econômicos aleatórios

### **Integração com Empresas:**
- Impostos sobre lucro de empresas
- Incentivos fiscais para contratação
- Multas por sonegação

### **Gamificação:**
- Conquistas por pagamento em dia
- Ranking de "melhores cidadãos"
- Recompensas exclusivas

### **IA/ML (Muito Avançado):**
- Previsão de inadimplência
- Detecção de padrões suspeitos
- Recomendações automáticas de ajustes

---

## ✅ **Conclusão**

**Tempo Total Estimado:** 6-8 semanas (desenvolvedor experiente)
**Impacto Esperado:** +200% em funcionalidade e UX
**Risco:** Baixo (melhorias incrementais)

**Recomendação:** Começar pelas melhorias críticas (Fase 1) e avaliar resultado antes de prosseguir.

---

**Elaborado por:** Claude AI
**Data:** 24/12/2025
**Versão Base:** Space Economy v3.0.0
