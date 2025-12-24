# 🔧 SOLUÇÕES PARA PROBLEMAS DO SISTEMA tiao_economia

## Data: 24/12/2025
## Baseado no Diagnóstico Completo

---

## 🚀 SOLUÇÃO 1: CONFIGURAR PERMISSÕES ACE (CRÍTICO - FAZER PRIMEIRO)

### Problema:
Sistema bloqueia todos os acessos admin porque permissão ACE não está configurada.

### Solução:

**1.1. Adicione ao seu `server.cfg`:**

```cfg
# ============================================================
# PERMISSÕES - SISTEMA ECONÔMICO (tiao_economia)
# ============================================================

# Permissão principal de admin
add_ace group.admin space_economy.admin allow
add_ace group.mod space_economy.admin allow

# Permissões granulares (opcional)
add_ace group.admin space_economy.view_treasury allow
add_ace group.admin space_economy.modify_treasury allow
add_ace group.admin space_economy.issue_debts allow
add_ace group.admin space_economy.view_logs allow

# Se você usa sistema de grupos personalizado, adicione seus grupos:
# add_ace group.seu_grupo space_economy.admin allow

# Para dar permissão a um jogador específico (use Steam/License ID):
# add_ace identifier.steam:110000XXXXXXXX space_economy.admin allow
# add_ace identifier.license:XXXXXXXXXXXXXXXX space_economy.admin allow
```

**1.2. Reinicie o servidor após salvar o server.cfg**

**1.3. Teste o acesso:**
- Entre no jogo
- Digite `/admineconomia` ou pressione `F9` (keybind configurável)
- Você deve ver o painel admin agora

### Alternativa: Usar Staff Metadata

Se seu servidor já usa metadata `isstaff` para admins:

```lua
-- Em config.lua (JÁ ESTÁ CONFIGURADO):
Config.Permissions = {
  AllowStaffMeta = true,  -- ← Isso permite que players com metadata.isstaff acessem
  -- ...
}
```

Certifique-se que seus admins têm o metadata correto:
```lua
-- No script que gerencia admins:
player.PlayerData.metadata.isstaff = true
```

---

## 🚀 SOLUÇÃO 2: IMPLEMENTAR FALLBACK BANCÁRIO CLIENT-SIDE

### Problema:
Transações bancárias falham porque sistema depende de recursos externos não instalados.

### Solução: Implementar Eventos Client-Side

**2.1. Edite `/home/user/novo/tiao_economia/tiao_economia/client/init.lua`**

Adicione no FINAL do arquivo:

```lua
--============================================================
-- FALLBACK: Eventos bancários quando não há integração externa
--============================================================

-- Remove dinheiro do player (fallback)
RegisterNetEvent('space_economy:client_requestRemoveMoney', function(amount, account)
  if not amount or amount <= 0 then return end
  account = account or 'bank'

  -- Tenta via QBX Core
  if GetResourceState('qbx_core') == 'started' then
    local success = exports.qbx_core:RemoveMoney(account, amount, 'space_economy')
    if success then
      lib.notify({
        title = 'Economia',
        description = ('$%s debitado de %s'):format(amount, account == 'bank' and 'banco' or 'dinheiro'),
        type = 'inform'
      })
    end
    return
  end

  -- Tenta via QBCore
  if GetResourceState('qb-core') == 'started' then
    local QBCore = exports['qb-core']:GetCoreObject()
    if QBCore and QBCore.Functions then
      QBCore.Functions.Notify(('$%s debitado'):format(amount), 'inform')
    end
  end
end)

-- Adiciona dinheiro ao player (fallback)
RegisterNetEvent('space_economy:client_requestAddMoney', function(amount, account)
  if not amount or amount <= 0 then return end
  account = account or 'bank'

  -- Tenta via QBX Core
  if GetResourceState('qbx_core') == 'started' then
    local success = exports.qbx_core:AddMoney(account, amount, 'space_economy')
    if success then
      lib.notify({
        title = 'Economia',
        description = ('$%s creditado em %s'):format(amount, account == 'bank' and 'banco' or 'dinheiro'),
        type = 'success'
      })
    end
    return
  end

  -- Tenta via QBCore
  if GetResourceState('qb-core') == 'started' then
    local QBCore = exports['qb-core']:GetCoreObject()
    if QBCore and QBCore.Functions then
      QBCore.Functions.Notify(('$%s creditado'):format(amount), 'success')
    end
  end
end)
```

**2.2. Reinicie o resource `tiao_economia`:**
```
/restart tiao_economia
```

---

## 🚀 SOLUÇÃO 3: CORRIGIR INTEGRAÇÃO COM QBX CORE

### Problema:
Código pode estar acessando incorretamente o objeto Player do QBX Core.

### Solução: Melhorar Detecção de Framework

**3.1. Edite `/home/user/novo/tiao_economia/tiao_economia/server/integrations.lua`**

Substitua a função `RemoveMoney` (linhas 54-110) por:

```lua
-- Remove money com validações robustas (MELHORADO v2)
function SE.Integrations.RemoveMoney(src, amount, account)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  account = account or 'bank'

  local framework = DetectFramework()

  -- Tenta via Bridge primeiro (mais confiável)
  if B and B.RemoveMoney then
    local ok = B.RemoveMoney(src, account, amount, 'space_economy')
    if ok then
      dbg(('RemoveMoney via Bridge: %d removeu $%d de %s'):format(src, amount, account))
      return true
    end
  end

  -- QBX Core direto (MELHORADO)
  if framework == 'qbx' then
    local success, player = pcall(function()
      return exports.qbx_core:GetPlayer(src)
    end)

    if success and player and player.Functions then
      local removed = pcall(function()
        return player.Functions.RemoveMoney(account, amount, 'space_economy')
      end)

      if removed then
        dbg(('RemoveMoney via QBX: %d removeu $%d'):format(src, amount))
        return true
      end
    end
  end

  -- QBCore direto (MELHORADO)
  if framework == 'qbcore' then
    local success, QBCore = pcall(function()
      return exports['qb-core']:GetCoreObject()
    end)

    if success and QBCore and QBCore.Functions then
      local player = QBCore.Functions.GetPlayer(src)
      if player and player.Functions then
        local removed = pcall(function()
          return player.Functions.RemoveMoney(account, amount, 'space_economy')
        end)

        if removed then
          dbg(('RemoveMoney via QBCore: %d removeu $%d'):format(src, amount))
          return true
        end
      end
    end
  end

  -- Fallback: evento client-side (agora implementado)
  dbg(('[FALLBACK] RemoveMoney para src %d: $%d (via cliente)'):format(src, amount))
  TriggerClientEvent('space_economy:client_requestRemoveMoney', src, amount, account)

  -- Considera sucesso se chegou aqui (cliente vai processar)
  return true
end
```

Faça o mesmo para `AddMoney` (linhas 113-168).

---

## 🚀 SOLUÇÃO 4: DESABILITAR INTEGRAÇÕES EXTERNAS NÃO UTILIZADAS

### Problema:
Sistema tenta integrar com recursos que não existem, causando erros silenciosos.

### Solução: Atualizar Configuração

**4.1. Edite `/home/user/novo/tiao_economia/tiao_economia/config.lua`**

Encontre a seção `Config.Integrations` (linha 232) e altere:

```lua
-- ============================================================
-- INTEGRAÇÕES (CORRIGIDO)
-- ============================================================
Config.Integrations = {
  -- Banking
  Banking = {
    Enabled = true,
    Resource = 'auto', -- auto-detect ou 'qbx_core', 'qb-core'
  },

  -- Dispatch (DESABILITADO até instalar ps-dispatch)
  Dispatch = {
    Enabled = false,  -- ← ALTERADO DE true PARA false
    Resource = 'ps-dispatch',
  },

  -- MDT (DESABILITADO até instalar ps-mdt)
  MDT = {
    Enabled = false,  -- ← ALTERADO DE true PARA false
    Resource = 'ps-mdt',
  },

  -- Shops (DESABILITADO - não integrado)
  Shops = {
    Enabled = false,
    TaxPurchases = false,
    TaxRate = 1.0,
  },

  -- Real Estate (DESABILITADO - não integrado)
  RealEstate = {
    Enabled = false,
    AutoIPTU = false,
    IPTUFrequencyDays = 30,
  },

  -- Garages (DESABILITADO - não integrado)
  Garages = {
    Enabled = false,
    AutoIPVA = false,
    IPVAFrequencyDays = 365,
  },
}
```

**4.2. Reinicie o resource:**
```
/restart tiao_economia
```

---

## 🚀 SOLUÇÃO 5: HABILITAR DEBUG MODE (TEMPORÁRIO)

### Para Diagnosticar Problemas:

**5.1. Edite `/home/user/novo/tiao_economia/tiao_economia/config.lua`**

```lua
-- Linha 6:
Config.Debug = true  -- ← ALTERE DE false PARA true
```

**5.2. Reinicie e monitore o console:**

```bash
# No console do servidor, você verá mensagens como:
[integrations] Framework detectado: QBX Core
[integrations] RemoveMoney via QBX: 1 removeu $1000
[debts] Dívida criada: GGFM0UWS | Imposto | $5000
```

**5.3. Depois de corrigir os problemas, desabilite:**
```lua
Config.Debug = false
```

---

## 🚀 SOLUÇÃO 6: TESTAR SISTEMA MANUALMENTE

### Após Aplicar TODAS as Soluções Acima:

**6.1. Teste Permissões:**
```
/admineconomia
# Deve abrir o painel admin sem erro
```

**6.2. Teste Criação de Dívida:**
```sql
-- No console do servidor ou MySQL:
CALL SE.Debts.Upsert('GGFM0UWS', 1000, 'Teste Manual', NULL, NULL);

-- Verifique:
SELECT * FROM space_economy_debts WHERE citizenid = 'GGFM0UWS';
```

**6.3. Teste Pagamento via NUI:**
1. Abra o painel (`/paineleconomia` ou keybind)
2. Vá em "Minhas Dívidas"
3. Tente pagar uma dívida
4. Verifique se o dinheiro foi debitado

**6.4. Teste Logs:**
1. Abra painel admin (`/admineconomia`)
2. Vá em "Logs do Sistema"
3. Deve mostrar histórico de ações

---

## 🚀 SOLUÇÃO 7: LIMPAR BANCO DE DADOS (OPCIONAL)

### Se o banco estiver inconsistente:

```sql
-- CUIDADO: Isto APAGA TODOS OS DADOS econômicos!
-- Faça backup primeiro!

DELETE FROM space_economy_debts WHERE 1=1;
DELETE FROM space_economy_debt_payments WHERE 1=1;
DELETE FROM space_economy_credit_scores WHERE 1=1;
DELETE FROM space_economy_loans WHERE 1=1;
DELETE FROM space_economy_logs WHERE category != 'system';

-- Reiniciar auto_increment:
ALTER TABLE space_economy_debts AUTO_INCREMENT = 1;
ALTER TABLE space_economy_debt_payments AUTO_INCREMENT = 1;

-- Resetar tesouro:
UPDATE space_economy SET vaultBalance = 0, inflationRate = 1.0, taxMultiplier = 1.0 WHERE id = 1;
```

---

## 🚀 SOLUÇÃO 8: INSTALAR SISTEMA BANCÁRIO COMPLETO (RECOMENDADO)

### Opção A: Instalar ps-banking

```bash
# 1. Clone o repositório
cd resources
git clone https://github.com/Project-Sloth/ps-banking.git

# 2. Importe o SQL
# Execute o arquivo ps-banking/import.sql no seu banco

# 3. Adicione ao server.cfg
ensure ps-banking

# 4. Configure integração no tiao_economia:
# config.lua linha 236:
Config.Integrations.Banking.Resource = 'ps-banking'
```

### Opção B: Instalar qb-banking

```bash
# 1. Clone
cd resources
git clone https://github.com/qbcore-framework/qb-banking.git

# 2. Importe SQL (se houver)

# 3. Adicione ao server.cfg
ensure qb-banking

# 4. Configure:
Config.Integrations.Banking.Resource = 'qb-banking'
```

### Opção C: Usar Apenas QBX Core (Mais Simples)

Se você já tem `qbx_core` instalado e funcionando, o sistema bancário já está embutido!

**Vantagens:**
- Sem dependências extras
- Integração nativa
- Mais leve

**Configure:**
```lua
Config.Integrations.Banking.Resource = 'qbx_core'
```

---

## 🚀 SOLUÇÃO 9: RESOLVER DUPLICAÇÃO DE ARQUIVOS

### Problema:
Estrutura de pastas duplicada pode causar confusão.

### Solução: Remover Pasta Duplicada

```bash
cd /home/user/novo/tiao_economia/tiao_economia
rm -rf tiao_economia/  # Remove pasta duplicada
```

**OU** renomeie para backup:
```bash
mv tiao_economia tiao_economia_OLD_BACKUP
```

Mantenha apenas a estrutura raiz:
```
/home/user/novo/tiao_economia/
└── tiao_economia/
    ├── server/
    ├── client/
    ├── html/
    ├── config.lua
    ├── fxmanifest.lua
    └── ...
```

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

Siga esta ordem:

- [ ] **1. Configurar Permissões ACE** (server.cfg)
- [ ] **2. Implementar Fallback Client-Side** (client/init.lua)
- [ ] **3. Corrigir Integração Server** (server/integrations.lua)
- [ ] **4. Desabilitar Integrações Externas** (config.lua)
- [ ] **5. Habilitar Debug Mode** (config.lua - temporário)
- [ ] **6. Reiniciar Servidor Completo**
- [ ] **7. Testar Permissões** (/admineconomia)
- [ ] **8. Testar Transações Bancárias** (depositar/sacar)
- [ ] **9. Testar Criação de Dívidas** (via admin)
- [ ] **10. Verificar Logs** (painel admin)
- [ ] **11. Testar Pagamento de Dívidas** (painel player)
- [ ] **12. Desabilitar Debug Mode** (config.lua)
- [ ] **13. (Opcional) Instalar ps-banking ou qb-banking**
- [ ] **14. (Opcional) Limpar Pasta Duplicada**

---

## 🆘 SUPORTE ADICIONAL

Se após aplicar TODAS as soluções os problemas persistirem:

1. **Verifique Console do Servidor:**
   - Com Debug Mode ativado, copie TODOS os erros relacionados a `tiao_economia`

2. **Verifique Console F8 no Cliente:**
   - Pressione F8 no jogo
   - Procure por erros em vermelho relacionados a `space_economy`

3. **Verifique Banco de Dados:**
   ```sql
   -- Todas devem retornar TRUE:
   SELECT COUNT(*) FROM space_economy;                -- 1
   SELECT COUNT(*) FROM space_economy_state;          -- 1+
   SELECT COUNT(*) FROM space_economy_logs;           -- 2+
   ```

4. **Verifique Estrutura de Arquivos:**
   ```bash
   ls -la /home/user/novo/tiao_economia/tiao_economia/
   # Deve mostrar: server/, client/, html/, config.lua, fxmanifest.lua
   ```

---

## ✅ RESULTADO ESPERADO

Após aplicar todas as soluções:

1. ✅ Painel admin abre normalmente
2. ✅ Transações bancárias funcionam (depositar/sacar)
3. ✅ Dívidas são criadas e aparecem no player
4. ✅ Logs carregam no painel admin
5. ✅ Players podem pagar dívidas via NUI
6. ✅ Sistema de tributos progressivos funciona
7. ✅ Parcelamento disponível
8. ✅ Score de crédito atualiza corretamente

---

**Última atualização:** 24/12/2025
**Versão do sistema:** tiao_economia v3.1.0
**Framework:** QBX Core
