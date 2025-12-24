# 🔐 CONFIGURAR PERMISSÕES - URGENTE

## ⚠️ PROBLEMA CRÍTICO

O sistema `tiao_economia` está bloqueando TODOS os acessos por falta de permissões ACE configuradas.

**Evidência:**
```sql
SELECT * FROM space_economy_logs ORDER BY id DESC LIMIT 2;
-- Resultado:
-- | timestamp           | category | message                    |
-- | 2025-12-24 12:12:38 | admin    | Acesso negado (permissão)  |
-- | 2025-12-24 21:54:40 | admin    | Acesso negado (permissão)  |
```

---

## 🚨 SOLUÇÃO RÁPIDA (COPIAR E COLAR)

### 1. Localize seu arquivo `server.cfg`

**Localização comum:**
- `/home/user/novo/server.cfg` (Linux)
- `C:\FXServer\server.cfg` (Windows)
- Ou na pasta raiz do seu servidor FiveM

### 2. Adicione estas linhas NO FINAL do `server.cfg`:

```cfg
# ============================================================
# PERMISSÕES - SISTEMA ECONÔMICO (tiao_economia)
# Adicionado em: 24/12/2025
# ============================================================

# Permissão principal de admin
add_ace group.admin space_economy.admin allow

# Se você tem grupo "mod" ou "moderator":
add_ace group.mod space_economy.admin allow

# Permissões granulares (opcional mas recomendado)
add_ace group.admin space_economy.view_treasury allow
add_ace group.admin space_economy.modify_treasury allow
add_ace group.admin space_economy.issue_debts allow
add_ace group.admin space_economy.view_logs allow

# ============================================================
# PERMISSÕES INDIVIDUAIS (Opcional)
# Se você quer dar permissão a jogadores específicos:
# ============================================================

# Exemplo usando Steam ID:
# add_ace identifier.steam:110000XXXXXXXX space_economy.admin allow

# Exemplo usando License:
# add_ace identifier.license:72b6567475f8452256ac755095e78e87298998a3 space_economy.admin allow

# ============================================================
# PARA SEUS ADMINS ATUAIS (Substitua pelos IDs corretos)
# ============================================================

# Admin 1: Thomas (Steam/License dele)
add_ace identifier.license:72b6567475f8452256ac755095e78e87298998a3 space_economy.admin allow

# Admin 2: MAKA (Steam/License dele)
add_ace identifier.license:b3e08103e05d260def1c3fdb26ce015692dc57cf space_economy.admin allow

# Se precisar adicionar mais, use o formato acima
```

### 3. Salve o arquivo `server.cfg`

### 4. Reinicie o servidor COMPLETO

```bash
# No console do servidor:
quit

# Ou se estiver rodando via txAdmin:
# Clique em "Restart Server"
```

**⚠️ IMPORTANTE:** Um simples `/restart tiao_economia` NÃO vai carregar as novas permissões!
Você PRECISA reiniciar o servidor inteiro.

---

## 🧪 TESTAR SE FUNCIONOU

### Após reiniciar o servidor:

1. **Entre no jogo**
2. **Teste o comando:**
   ```
   /admineconomia
   ```
3. **Ou pressione a tecla configurada:**
   - Padrão: `F9`

### Resultado Esperado:

✅ **SUCESSO:** Painel admin abre normalmente
❌ **FALHA:** Mensagem "Acesso negado"

---

## 🆘 SE AINDA NÃO FUNCIONAR

### Verificação 1: Confirme que você está no grupo admin

```bash
# No console do servidor:
sv_admins

# Ou no F8 do cliente:
/getgroups
```

Se você NÃO estiver no grupo `admin`, adicione-se:

```cfg
# No server.cfg:
add_principal identifier.license:SEU_LICENSE_ID group.admin
```

**Como descobrir seu License ID:**
1. Entre no servidor
2. Pressione F8
3. Digite: `license`
4. Copie o valor mostrado

### Verificação 2: Certifique-se que o recurso está iniciado

```bash
# No console do servidor:
ensure tiao_economia

# Ou adicione no server.cfg:
ensure tiao_economia
```

### Verificação 3: Verifique console por erros

```bash
# Procure por linhas como:
[ERROR] [tiao_economia] ...
[SCRIPT ERROR] ...
```

---

## 📝 ALTERNATIVA: Usar Staff Metadata

Se seu servidor já usa sistema de metadata para staff:

### 1. Verifique se `AllowStaffMeta` está ativado:

```lua
-- Em /home/user/novo/tiao_economia/tiao_economia/config.lua (linha 99):
Config.Permissions = {
  AllowStaffMeta = true,  -- ← Deve estar TRUE (já está)
  -- ...
}
```

### 2. Certifique-se que seu player tem o metadata:

```lua
-- No script que gerencia admins do seu servidor:
player.PlayerData.metadata.isstaff = true
```

---

## 🔍 ENTENDENDO AS PERMISSÕES

### Estrutura:

```
space_economy.admin          → Permissão principal (acessa tudo)
space_economy.view_treasury  → Ver saldo do tesouro
space_economy.modify_treasury → Modificar tesouro
space_economy.issue_debts    → Criar dívidas para players
space_economy.view_logs      → Ver logs do sistema
```

### Você pode criar permissões personalizadas:

```cfg
# Dar apenas visualização (sem modificação):
add_ace identifier.license:ID_DO_PLAYER space_economy.view_treasury allow
add_ace identifier.license:ID_DO_PLAYER space_economy.view_logs allow
# (Não dar modify_treasury nem issue_debts)
```

---

## ✅ CHECKLIST FINAL

Após configurar as permissões:

- [ ] `server.cfg` editado com permissões ACE
- [ ] Servidor reiniciado COMPLETO (não apenas /restart resource)
- [ ] Testado comando `/admineconomia` - painel abre ✅
- [ ] Testado criar dívida via painel - funciona ✅
- [ ] Testado ver logs - mostra registros ✅

---

## 🎯 RESULTADO ESPERADO

Com as permissões configuradas:

1. ✅ Painel admin abre normalmente
2. ✅ Você consegue ver métricas econômicas
3. ✅ Pode criar/gerenciar dívidas
4. ✅ Logs aparecem corretamente
5. ✅ Todas as funcionalidades admin funcionam

---

**IMPORTANTE:** Depois de configurar as permissões, você ainda precisa:
1. Verificar que o sistema bancário está funcionando (ver arquivo SOLUCOES_PROBLEMAS.md)
2. Testar transações (depositar/sacar)

**Última atualização:** 24/12/2025
