# 🔗 Integrações Externas - Space Economy v5.0

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [ps-banking (Sistema Bancário)](#ps-banking)
3. [ox_inventory (Inventário e Lojas)](#ox_inventory)
4. [rhd_garage + rm-dealership (Veículos)](#veículos)
5. [ps-housing (Casas)](#ps-housing)
6. [klb-management (Empresas)](#klb-management)
7. [ps-mdt (Polícia)](#ps-mdt)
8. [Configuração Avançada](#configuração-avançada)
9. [Exports Disponíveis](#exports-disponíveis)
10. [Troubleshooting](#troubleshooting)

---

## Visão Geral

O sistema de economia agora possui **integração automática** com os principais recursos do servidor:

✅ **ps-banking** - Taxa IOF em transferências e saques
✅ **ox_inventory** - ICMS automático em compras de lojas
✅ **rhd_garage + rm-dealership** - IPVA automático em compras de veículos
✅ **ps-housing** - IPTU automático em compras de propriedades
✅ **klb-management** - ISS em serviços prestados por empresas
✅ **ps-mdt** - Multas policiais convertidas em dívidas automaticamente

### Como Funciona

Todas as integrações funcionam **automaticamente** quando os recursos estão presentes no servidor. Não é necessário configuração adicional para o funcionamento básico.

Quando uma ação é realizada (ex: compra de veículo), o sistema:
1. Detecta automaticamente o evento
2. Calcula o imposto devido
3. Cria uma dívida no sistema econômico
4. Notifica o jogador

---

## ps-banking

### Funcionalidades

#### 1. Taxa IOF em Transferências
- **Taxa**: 0.5% do valor transferido
- **Mínimo**: $10 para aplicar a taxa
- **Vencimento**: 7 dias

**Exemplo**:
```lua
Transferência de $10,000
IOF: $50 (0.5%)
Dívida criada automaticamente
```

#### 2. Taxa de Saque ATM
- **Taxa**: $50 fixo para saques acima de $5,000
- **Vencimento**: 7 dias

### Hooks Automáticos

O sistema escuta os seguintes eventos:
- `ps-banking:server:transfer` - Transferências
- `ps-banking:server:withdraw` - Saques

### Configuração

```lua
-- Editar em server/external_integrations.lua
SE.External.Banking = {
  Enabled = true,
  TaxTransfers = true,    -- Taxar transferências
  TaxRate = 0.5,          -- 0.5% de taxa
  MinTaxAmount = 10,      -- Mínimo $10
}
```

---

## ox_inventory

### Funcionalidades

#### ICMS Automático em Compras
- **Taxa**: 12% sobre o valor da compra
- **Vencimento**: 30 dias
- **Items Isentos**: Configurável

**Exemplo**:
```lua
Compra: 5x Água por $25 cada = $125
ICMS: $15 (12%)
Dívida: "ICMS - Compra: water"
```

### Hooks Automáticos

- `ox_inventory:server:buyItem` - Compras em lojas
- `ox_inventory:shopPurchase` - Formato alternativo

### Configuração

```lua
SE.External.Inventory = {
  Enabled = true,
  TaxPurchases = true,
  TaxRate = 12.0,         -- ICMS 12%
  ExemptItems = {         -- Items isentos
    'bread',
    'water'
  }
}
```

### Adicionar Item Isento

```lua
table.insert(SE.External.Inventory.ExemptItems, 'nome_do_item')
```

---

## Veículos

### Funcionalidades

#### IPVA Automático
- **Taxa**: 1.5% do valor do veículo
- **Mínimo**: Veículos acima de $1,000
- **Vencimento**: 30 dias
- **Recursos Suportados**: rhd_garage, rm-dealership

**Exemplo**:
```lua
Compra de veículo: $50,000
IPVA: $750 (1.5%)
Notificação ao jogador
```

### Hooks Automáticos

**rhd_garage**:
- `rhd_garage:server:vehiclePurchased`

**rm-dealership**:
- `rm-dealership:server:buyVehicle`

### Configuração

```lua
SE.External.Vehicles = {
  Enabled = true,
  TaxRate = 1.5,          -- IPVA 1.5%
  MinVehiclePrice = 1000,
  AnnualIPVA = true,      -- Suporte para IPVA anual
}
```

### IPVA Anual (Manual)

```lua
-- Cobrar IPVA anualmente de um jogador
exports['tiao_economia']:ChargeIPVA(source, plate, vehiclePrice)

-- Exemplo
exports['tiao_economia']:ChargeIPVA(1, 'ABC1234', 50000)
-- Retorna: true, 750 (sucesso e valor do IPVA)
```

---

## ps-housing

### Funcionalidades

#### IPTU Automático
- **Taxa**: 0.3% do valor da propriedade
- **Mínimo**: Propriedades acima de $5,000
- **Vencimento**: 30 dias

**Exemplo**:
```lua
Compra de casa: $200,000
IPTU: $600 (0.3%)
Dívida: "IPTU - Rua das Flores, 123"
```

### Hooks Automáticos

- `ps-housing:server:purchaseProperty`
- `ps-housing:buyProperty` - Formato alternativo

### Configuração

```lua
SE.External.Housing = {
  Enabled = true,
  TaxRate = 0.3,          -- IPTU 0.3%
  MinPropertyPrice = 5000,
  AnnualIPTU = true,
}
```

### IPTU Anual (Manual)

```lua
-- Cobrar IPTU anualmente
exports['tiao_economia']:ChargeIPTU(source, propertyId, propertyPrice)

-- Exemplo
exports['tiao_economia']:ChargeIPTU(1, 'house_123', 200000)
-- Retorna: true, 600
```

---

## klb-management

### Funcionalidades

#### 1. ISS em Serviços
- **Taxa**: 2% sobre serviços prestados
- **Mínimo**: Serviços acima de $100
- **Vencimento**: 15 dias

**Exemplo**:
```lua
Serviço mecânico: $1,500
ISS: $30 (2%)
```

#### 2. IRPF sobre Salários
- **Taxa**: 2% sobre salários
- **Automático**: Ao processar folha de pagamento
- **Vencimento**: 15 dias

### Hooks Automáticos

- `klb-management:server:payService` - Pagamento de serviços
- `klb-management:server:payroll` - Folha de pagamento

### Configuração

```lua
SE.External.Management = {
  Enabled = true,
  TaxRate = 2.0,          -- ISS 2%
  MinServiceValue = 100,
}
```

---

## ps-mdt

### Funcionalidades

#### Multas Automáticas
- **Conversão**: Multas do MDT → Dívidas no sistema econômico
- **Multiplicador**: Configurável (padrão 1.0x)
- **Vencimento**: 15 dias

**Exemplo**:
```lua
Policial aplica multa de $500 por excesso de velocidade
Sistema cria dívida automaticamente
Jogador recebe notificação
```

### Hooks Automáticos

- `ps-mdt:server:createFine` - Criação de multas
- `ps-mdt:server:addCharge` - Adição de acusações

### Configuração

```lua
SE.External.Police = {
  Enabled = true,
  AutoCreateDebt = true,   -- Criar dívida automaticamente
  FineMultiplier = 1.0,    -- Multiplicador (1.5x = multas 50% maiores)
}
```

### Multa Manual

```lua
-- Criar multa manualmente
exports['tiao_economia']:CreateFine(citizenid, amount, reason, officerSource)

-- Exemplo
exports['tiao_economia']:CreateFine('ABC12345', 500, 'Excesso de velocidade', source)
-- Retorna: true, 500
```

---

## Configuração Avançada

### Desabilitar Integrações Específicas

Edite `server/external_integrations.lua`:

```lua
-- Desabilitar taxação em transferências bancárias
SE.External.Banking.TaxTransfers = false

-- Desabilitar ICMS em compras
SE.External.Inventory.TaxPurchases = false

-- Desabilitar conversão automática de multas
SE.External.Police.AutoCreateDebt = false
```

### Alterar Taxas

```lua
-- Aumentar IPVA para 3%
SE.External.Vehicles.TaxRate = 3.0

-- Reduzir ICMS para 8%
SE.External.Inventory.TaxRate = 8.0

-- Aumentar multas em 50%
SE.External.Police.FineMultiplier = 1.5
```

### Ajustar Vencimentos

Edite os valores em dias nos hooks. Exemplo:

```lua
-- Mudar vencimento de IPVA de 30 para 60 dias
SE.Debts.Upsert(cid, ipva, reason, os.time() + (60 * 24 * 60 * 60), data)
--                                              ^^
--                                              60 dias
```

---

## Exports Disponíveis

### 1. Taxar Compra Manualmente

```lua
exports['tiao_economia']:TaxPurchase(source, itemName, price, quantity)

-- Exemplo
local success, taxAmount = exports['tiao_economia']:TaxPurchase(1, 'laptop', 5000, 1)
if success then
  print('ICMS:', taxAmount)
end
```

### 2. Taxar Transferência

```lua
exports['tiao_economia']:TaxTransfer(source, amount, targetAccount)

-- Exemplo
local success, iof = exports['tiao_economia']:TaxTransfer(1, 10000, 'bank-123')
```

### 3. Cobrar IPVA

```lua
exports['tiao_economia']:ChargeIPVA(source, plate, vehiclePrice)

-- Exemplo
local success, ipva = exports['tiao_economia']:ChargeIPVA(1, 'ABC1234', 50000)
```

### 4. Cobrar IPTU

```lua
exports['tiao_economia']:ChargeIPTU(source, propertyId, propertyPrice)

-- Exemplo
local success, iptu = exports['tiao_economia']:ChargeIPTU(1, 'house_15', 200000)
```

### 5. Criar Multa

```lua
exports['tiao_economia']:CreateFine(citizenid, amount, reason, officerSource)

-- Exemplo
local success = exports['tiao_economia']:CreateFine('ABC12345', 500, 'Condução perigosa', source)
```

### 6. Verificar Status das Integrações

```lua
local status = exports['tiao_economia']:GetIntegrationStatus()

print(json.encode(status))
-- {
--   "banking": true,
--   "inventory": true,
--   "vehicles": true,
--   "housing": true,
--   "management": false,
--   "police": true
-- }
```

---

## Troubleshooting

### Problema: Tributos não estão sendo criados

**Soluções**:

1. Verifique se o recurso está ativo:
```lua
-- No console F8
GetResourceState('ps-banking')
-- Deve retornar 'started'
```

2. Verifique os logs do servidor:
```
[external_integrations] ✓ ps-banking integrado
```

3. Ative o debug:
```lua
-- Em server/external_integrations.lua
local DEBUG = true
```

### Problema: Taxas muito altas/baixas

Ajuste as taxas em `server/external_integrations.lua`:

```lua
SE.External.Banking.TaxRate = 0.5  -- Ajuste conforme necessário
SE.External.Inventory.TaxRate = 12.0
SE.External.Vehicles.TaxRate = 1.5
-- etc
```

### Problema: Integração não detectada

Certifique-se de que o recurso está carregado **antes** do `tiao_economia`:

```cfg
# Em server.cfg
ensure ps-banking
ensure ox_inventory
ensure rhd_garage
ensure ps-housing
ensure tiao_economia  # <-- Deve vir depois
```

### Problema: Eventos não estão sendo capturados

Alguns recursos podem usar nomes de eventos diferentes. Verifique a documentação do recurso e adicione hooks alternativos:

```lua
-- Adicione em server/external_integrations.lua
AddEventHandler('nome_do_evento_alternativo', function(data)
  -- Seu código aqui
end)
```

---

## 🎯 Resumo

✅ **6 integrações completas** prontas para usar
✅ **Detecção automática** de recursos
✅ **Configuração flexível** por integração
✅ **Exports** para uso manual
✅ **Logs detalhados** para debug
✅ **Compatível** com os principais frameworks

### Início Rápido

1. Certifique-se de que os recursos estão instalados
2. Inicie o servidor
3. Verifique os logs: `[external_integrations] X/6 integrações ativadas`
4. Teste fazendo uma compra/transferência
5. Verifique a dívida criada: `/economia debts`

### Suporte

Para problemas ou dúvidas:
- Verifique os logs do servidor
- Ative o modo debug
- Consulte a documentação de cada recurso integrado
- Abra uma issue no GitHub

---

**Space Economy v5.0** - Sistema Econômico Completo 🚀
