# Diagnóstico: Acesso Negado no Painel Admin

## Problema
Ao tentar abrir o painel administrativo (`/economia` ou F12), você recebe a mensagem "Acesso negado".

## ✅ SOLUÇÃO RÁPIDA: Use o Comando de Diagnóstico

### 1. Entre no jogo
Entre no servidor com o personagem que deve ter acesso admin.

### 2. Execute o comando de diagnóstico
Digite no chat:
```
/eco_checkperm
```

### 3. Verifique o console (F8)
O comando vai mostrar um relatório completo com:
- Seus identifiers (license, fivem, etc)
- Configuração atual de permissões
- Seus dados de jogador (job, grade, metadata)
- Resultado da verificação ACE
- **RESULTADO FINAL: PERMITIDO ✓ ou NEGADO ✗**

### 4. Se aparecer NEGADO, use o comando auxiliar
```
/eco_grantme
```

Este comando vai mostrar no console (F8) exatamente quais linhas você precisa adicionar no seu `permissions.cfg` ou `server.cfg`.

## Logs de Debug Adicionados
Adicionamos logs detalhados automáticos sempre que você tenta abrir o painel. Procure por mensagens começando com `[space_economy]`.

## Como Testar (Método Manual)

### 1. Reinicie o servidor
```bash
restart tiao_economia
```

### 2. Tente abrir o painel admin
- Digite `/economia` no chat OU
- Pressione F12

### 3. Verifique o console do servidor (F8)
Você verá algo como:

```
[space_economy] Verificando permissões admin para source 1
[space_economy] Checking ACE "space_economy.admin" for source 1
[space_economy] Player identifiers:
  - license:xxxxxxxx
  - fivem:10607547
  - ...
[space_economy] IsPlayerAceAllowed(1, "space_economy.admin") = false
[space_economy] ACE check: space_economy.admin = false
[space_economy] Staff Meta check: false
[space_economy] Job check: government (minGrade 3) = false
[space_economy] Job check: police (minGrade 5) = false
[space_economy] Source 1 NÃO TEM permissão admin
```

### 4. Analise os resultados

#### Se o identifier correto aparece mas a ACE retorna false:
O problema está na configuração de permissões do servidor. Verifique:

1. **Arquivo permissions.cfg ou server.cfg**
   ```cfg
   # Adicione estas linhas (substitua com seu identifier correto)
   add_principal identifier.fivem:10607547 group.admin
   add_ace group.admin space_economy.admin allow
   ```

2. **Verifique se o arquivo está sendo executado**
   - Se usar `permissions.cfg`, certifique-se que tem `exec permissions.cfg` no server.cfg
   - Ou adicione as permissões diretamente no server.cfg

3. **Ordem importa!**
   - As linhas devem vir ANTES de `ensure tiao_economia`
   - Exemplo:
   ```cfg
   # Permissões primeiro
   add_principal identifier.fivem:10607547 group.admin
   add_ace group.admin space_economy.admin allow

   # Resources depois
   ensure tiao_economia
   ```

#### Se o identifier NÃO aparece ou está diferente:
1. Copie o identifier correto que aparece nos logs (o que começa com `fivem:`)
2. Atualize suas permissões com o identifier correto
3. Reinicie o servidor

## Soluções Alternativas

### Solução 1: Usar metadata de staff (QBOX)
Se você usa QBOX, pode adicionar metadata de staff:

```lua
-- No banco de dados ou via comando admin
UPDATE players SET metadata = JSON_SET(metadata, '$.isstaff', true) WHERE citizenid = 'SEU_CITIZENID';
```

### Solução 2: Usar permissão por job
Configure um job com acesso admin no config.lua:

```lua
Config.Permissions = {
  Jobs = {
    ['admin'] = { minGrade = 0 },  -- Qualquer grade do job 'admin'
  },
}
```

### Solução 3: Usar QBCore permission groups (legacy)
Se você usa QBCore antigo com sistema de permissões, certifique-se que você tem:

```lua
-- qb-core/shared/permissions.lua ou similar
['admin'] = {
  [1] = 'fivem:10607547',
}
```

## Próximos Passos

Após seguir os passos acima:
1. Envie os logs que aparecem no console
2. Informo qual solução funcionou (ou não funcionou)
3. Podemos ajustar conforme necessário

## Teste Rápido da Interface (sem permissão)
Para verificar se a interface em si está funcionando, você pode usar:

```
/eco_testui
```

Isso abre a interface localmente SEM verificação de permissão (apenas para teste).
