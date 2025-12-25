# 🔄 Sistema de Integração Direta com Banco de Dados

## 📋 Visão Geral

Este sistema revoluciona a forma como o **Space Economy** integra com outros recursos do servidor, eliminando a dependência de eventos externos e consultando **diretamente os bancos de dados** dos recursos para detectar e processar transações automaticamente.

### ✅ Vantagens da Nova Abordagem

1. **Precisão Total**: Não perde nenhuma transação, mesmo se eventos falharem
2. **Independência**: Não depende de recursos externos dispararem eventos corretamente
3. **Retroativo**: Pode processar transações antigas que não foram taxadas
4. **Controle Total**: Você tem controle completo sobre quando e como processar
5. **Debug Fácil**: Logs detalhados de tudo que está sendo processado
6. **Performance**: Processamento em lotes otimizado

---

## 📦 Instalação

### Passo 1: Executar o SQL

Execute o arquivo SQL para criar as tabelas necessárias:

```bash
# No seu cliente MySQL (HeidiSQL, phpMyAdmin, etc)
# Execute o arquivo:
sql/db_integrations.sql
```

Isso criará:
- ✅ `space_economy_processed_transactions` - Rastreia transações já processadas
- ✅ `space_economy_integration_config` - Configurações de cada integração
- ✅ Views de análise e estatísticas

### Passo 2: Reiniciar o Recurso

```bash
# No console do servidor
restart tiao_economia
```

### Passo 3: Verificar se Iniciou

```bash
# Você deve ver no console:
[SPACE ECONOMY DB-INT] Iniciando schedulers de integração...
[SPACE ECONOMY DB-INT] Sistema de integração inicializado com sucesso!
```

---

## 🎯 Como Funciona

### Fluxo de Processamento

```
┌─────────────────────┐
│  SCHEDULER (60s)    │
│  Verifica novos     │
│  registros no DB    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Consulta SQL       │
│  phone_transactions │
│  ox_inventory_trans │
│  player_vehicles    │
│  player_houses      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Verifica se já     │
│  foi processada     │
│  (evita duplicação) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Calcula Imposto    │
│  IOF / ICMS / IPVA  │
│  IPTU               │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Cria Dívida        │
│  SE.Debts.Upsert    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Marca como         │
│  Processada         │
│  (nunca repete)     │
└─────────────────────┘
```

---

## 🔧 Sistemas Integrados

### 1. 🏦 PS-Banking (IOF)

**Tabela**: `phone_transactions`
**Imposto**: IOF 0.5% (mínimo $10)
**Tipos**: Transferências e Saques

```sql
-- Exemplo de consulta
SELECT id, citizenid, type, amount, receiver, created_at
FROM phone_transactions
WHERE type IN ('transfer', 'withdraw')
  AND created_at > '2024-12-01'
  AND amount > 0
```

**Processamento**:
- Transferências acima de $2.000 → IOF 0.5%
- Saques grandes → IOF mínimo $10

---

### 2. 🛒 OX Inventory (ICMS)

**Tabela**: `ox_inventory_transactions`
**Imposto**: ICMS 12%
**Tipos**: Compras em lojas

```sql
-- Exemplo de consulta
SELECT id, owner as citizenid, item, count, price, created
FROM ox_inventory_transactions
WHERE type = 'shop_purchase'
  AND created > '2024-12-01'
  AND price > 0
```

**Itens Isentos**:
- bread
- water
- sandwich

---

### 3. 🚗 Veículos (IPVA)

**Tabela**: `player_vehicles`
**Imposto**: IPVA 1.5%
**Tipos**: Compras de veículos

```sql
-- Exemplo de consulta
SELECT id, citizenid, vehicle, plate, price, created_at
FROM player_vehicles
WHERE created_at > '2024-12-01'
  AND price > 0
```

**Cálculo**:
- Veículo de $50.000 → IPVA $750

---

### 4. 🏠 Housing (IPTU)

**Tabela**: `player_houses`
**Imposto**: IPTU 0.3%
**Tipos**: Compras de propriedades

```sql
-- Exemplo de consulta
SELECT id, citizenid, house, price, created_at
FROM player_houses
WHERE created_at > '2024-12-01'
  AND price > 0
```

**Cálculo**:
- Casa de $100.000 → IPTU $300/mês

---

## 📊 Comandos Administrativos

### Verificar Integrações Manualmente

```bash
# No console do servidor
se:checkintegrations
```

Força uma verificação imediata de todos os sistemas.

### Ver Estatísticas

```bash
# No console do servidor
se:dbstats
```

Mostra:
- Total de transações processadas
- Total de erros
- Estatísticas por sistema
- Última verificação de cada sistema

**Exemplo de saída**:
```
[SPACE ECONOMY DB-INT] === ESTATÍSTICAS DE INTEGRAÇÃO ===
Total Processadas: 1547
Total Erros: 3
Por Sistema:
  - ps-banking: 823 transações (última verificação: 2024-12-25 14:30:45)
  - ox_inventory: 456 transações (última verificação: 2024-12-25 14:30:50)
  - vehicles: 187 transações (última verificação: 2024-12-25 14:28:15)
  - housing: 81 transações (última verificação: 2024-12-25 14:28:20)
```

---

## ⚙️ Configuração Avançada

### Alterar Intervalos de Verificação

Edite `/server/db_integrations.lua`:

```lua
DBInt.Config = {
    Enabled = true,
    CheckInterval = 60000, -- 60 segundos (padrão)
    BatchSize = 100,       -- Processar 100 por vez

    Systems = {
        ['ps-banking'] = {
            enabled = true,
            interval = 60000,  -- Altere aqui (em milissegundos)
        },
        ['vehicles'] = {
            enabled = true,
            interval = 120000, -- 2 minutos
        },
    }
}
```

### Desabilitar um Sistema

```lua
Systems = {
    ['ps-banking'] = {
        enabled = false, -- Desabilitado
    },
}
```

### Ativar/Desativar Debug

```lua
DBInt.Config = {
    DebugMode = true, -- Logs detalhados
}
```

---

## 🔍 Consultas SQL Úteis

### Ver Transações Processadas Hoje

```sql
SELECT
    source_system,
    tax_type,
    COUNT(*) as total,
    SUM(tax_amount) as total_tax
FROM space_economy_processed_transactions
WHERE DATE(processed_at) = CURDATE()
GROUP BY source_system, tax_type;
```

### Ver Maior Contribuinte de IOF

```sql
SELECT
    citizenid,
    COUNT(*) as transactions,
    SUM(tax_amount) as total_iof
FROM space_economy_processed_transactions
WHERE tax_type = 'IOF'
GROUP BY citizenid
ORDER BY total_iof DESC
LIMIT 10;
```

### Ver Transações Não Processadas

```sql
-- Banco (exemplo - ajuste conforme sua estrutura)
SELECT t.*
FROM phone_transactions t
LEFT JOIN space_economy_processed_transactions p
    ON p.source_system = 'ps-banking'
    AND p.transaction_id = t.id
WHERE p.id IS NULL
  AND t.type IN ('transfer', 'withdraw')
  AND t.amount > 0;
```

### Verificar Duplicações (não deve retornar nada)

```sql
SELECT
    source_system,
    transaction_id,
    COUNT(*) as duplicates
FROM space_economy_processed_transactions
GROUP BY source_system, transaction_id
HAVING COUNT(*) > 1;
```

---

## 🛠️ Personalização

### Adicionar Novo Sistema de Integração

**1. Adicionar configuração em `db_integrations.lua`:**

```lua
Systems = {
    ['meu-sistema'] = {
        enabled = true,
        table = 'minha_tabela',
        interval = 60000,
        processor = 'ProcessMeuSistema'
    }
}
```

**2. Criar função processadora:**

```lua
function DBInt.ProcessMeuSistema()
    local systemName = 'meu-sistema'
    local processed = 0

    -- Buscar transações
    local transactions = MySQL.query.await([[
        SELECT * FROM minha_tabela
        WHERE created_at > ?
        LIMIT ?
    ]], {lastCheck, DBInt.Config.BatchSize})

    for _, tx in ipairs(transactions) do
        if not DBInt.IsProcessed(systemName, tostring(tx.id)) then
            -- Calcular imposto
            local tax = tx.amount * 0.05 -- 5%

            -- Criar dívida
            local debtId = DBInt.CreateDebt(
                tx.citizenid,
                tax,
                'Descrição do imposto',
                'TIPO',
                {custom_data = tx.extra}
            )

            -- Marcar como processada
            if debtId then
                DBInt.MarkAsProcessed({
                    source_system = systemName,
                    transaction_id = tostring(tx.id),
                    transaction_type = 'custom',
                    citizenid = tx.citizenid,
                    amount = tx.amount,
                    tax_amount = tax,
                    tax_type = 'TIPO',
                    debt_id = debtId,
                    transaction_date = tx.created_at,
                    metadata = {}
                })
                processed = processed + 1
            end
        end
    end

    return processed
end
```

**3. Adicionar na config do banco:**

```sql
INSERT INTO space_economy_integration_config
(source_system, enabled, table_name, query_interval, config_json)
VALUES
('meu-sistema', 1, 'minha_tabela', 60, JSON_OBJECT(
    'tax_type', 'TIPO',
    'tax_rate', 5.0
));
```

---

## 🐛 Troubleshooting

### Problema: Não está processando transações

**Verificar**:
1. Tabelas foram criadas? (execute o SQL)
2. Sistema está habilitado?
3. Nome da tabela está correto?
4. Campos das consultas existem no seu banco?

**Debug**:
```lua
DBInt.Config.DebugMode = true
```

### Problema: Duplicando impostos

**Verificar**:
```sql
SELECT * FROM space_economy_processed_transactions
WHERE transaction_id = 'SEU_ID'
  AND source_system = 'ps-banking';
```

Se retornar vazio, não foi processada.
Se retornar algo, já foi processada (não deveria duplicar).

### Problema: Tabelas não existem

**Solução**:
```bash
# Execute novamente o SQL
mysql -u seu_usuario -p seu_banco < sql/db_integrations.sql
```

---

## 📈 Monitoramento

### Estatísticas em Tempo Real

```lua
-- Exportado para outros recursos
local stats = exports['tiao_economia']:GetDBIntegrationStats()
print(json.encode(stats, {indent = true}))
```

### Forçar Verificação de um Sistema

```lua
-- Exportado para outros recursos
exports['tiao_economia']:ForceCheckSystem('ps-banking')
```

---

## 🎯 Ajustes Recomendados

### Estrutura de Tabelas Pode Variar

⚠️ **IMPORTANTE**: As consultas SQL assumem uma estrutura de tabela específica. Você pode precisar ajustar:

#### PS-Banking

Se sua tabela `phone_transactions` tiver campos diferentes, ajuste em `ProcessBankingTransactions()`:

```lua
-- Exemplo: Se o campo for 'player' ao invés de 'citizenid'
SELECT
    id,
    player as citizenid,  -- Ajuste aqui
    type,
    amount,
    created_at
FROM phone_transactions
```

#### OX Inventory

Diferentes versões do ox_inventory podem usar:
- `ox_inventory_transactions`
- `ox_inventory` com coluna `type`
- Logs em JSON

**Ajuste conforme necessário!**

---

## 📝 Notas Finais

### Coexistência com Sistema de Eventos

Este sistema **pode coexistir** com o sistema antigo de eventos (`external_integrations.lua`).

**Recomendação**:
1. Desabilite os eventos antigos para evitar duplicação
2. Ou use este sistema apenas para processar retroativamente
3. Monitore a tabela `space_economy_processed_transactions` para garantir que não há duplicação

### Performance

- ✅ Processa em **lotes de 100** transações
- ✅ **Não bloqueia** o servidor (usa threads separadas)
- ✅ **Cache** de transações processadas
- ✅ **Índices otimizados** no banco

### Backup

Sempre faça backup antes de executar:
```bash
mysqldump -u root -p seu_banco space_economy_processed_transactions > backup.sql
```

---

## 🆘 Suporte

Se tiver problemas:

1. Ative o debug: `DBInt.Config.DebugMode = true`
2. Verifique os logs do console
3. Execute `se:dbstats` para ver estatísticas
4. Verifique se as tabelas dos recursos externos existem
5. Ajuste as queries SQL conforme sua estrutura de banco

---

## 📜 Licença

Este módulo é parte do **Space Economy v3.1** e segue a mesma licença do projeto principal.

---

**Desenvolvido com ❤️ para precisão e confiabilidade máximas!**
