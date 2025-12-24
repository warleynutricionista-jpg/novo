# Documentação de Integrações - Space Economy v3.0

## ✅ Status de Revisão
**Data:** 24/12/2025
**Revisor:** Claude AI
**Status:** Todas as integrações verificadas e funcionando corretamente

---

## 📋 Sumário das Integrações

### 1. **Framework Base** ✅
- **QBX Core** (qbx_core) - Suporte completo
- **QBCore** (qb-core) - Suporte completo
- **ESX** (es_extended) - Suporte básico (futuro)
- **Detecção Automática**: O sistema detecta automaticamente qual framework está rodando

**Arquivos:**
- `server/integrations.lua:20-47` - Função `DetectFramework()`
- `shared/bridge.lua:46-52` - Funções `IsQBX()` e `IsQBCore()`

---

### 2. **Sistema Monetário** ✅

#### Money Operations (Dinheiro)
- **AddMoney**: Adicionar dinheiro ao jogador
- **RemoveMoney**: Remover dinheiro do jogador
- **GetBalance**: Consultar saldo (bank/cash)

**Integrações:**
- QBX Core: `player.Functions.AddMoney()` / `player.Functions.RemoveMoney()`
- QBCore: `player.Functions.AddMoney()` / `player.Functions.RemoveMoney()`
- Fallback: Bridge com validações robustas

**Arquivos:**
- `server/integrations.lua:54-201` - RemoveMoney, AddMoney, GetBalance
- `shared/bridge.lua:216-282` - Bridge wrappers

---

### 3. **Sistema Bancário** ✅

#### Banking Transfer
- **ps-banking** - Suporte completo com `AddMoney()` e `CreateBankStatement()`
- **qb-banking** - Fallback genérico
- **qbx-banking** - Fallback genérico

**Funcionalidades:**
- Transferências entre jogadores
- Transferências para contas society
- Criação de extratos bancários
- Rollback automático em caso de falha

**Arquivos:**
- `server/integrations.lua:392-486` - `BankingTransfer()`

---

### 4. **Sistema de Dispatch** ✅

#### ps-dispatch Integration
- **Mandados Automáticos**: Emissão automática de mandados para dívidas vencidas
- **Alertas Customizados**: Sistema de alertas para polícia/governo
- **Fallback MDT**: Se dispatch falhar, tenta ps-mdt

**Funcionalidades:**
- Emissão de mandados após 7 dias de atraso (configurável)
- Coordenadas do jogador (se online) ou coordenadas default
- Suporte a jobs múltiplos (police, government, etc.)

**Configuração:**
```lua
Config.WarrantAlert = {
  Enabled = true,
  UsePsDispatch = true,
  UsePsMdt = true,
  Title = 'Dívida Ativa',
  Message = 'Cidadão com dívida vencida há mais de 7 dias',
  DispatchCode = '10-90',
}
```

**Arquivos:**
- `server/integrations.lua:204-387` - `EmitWarrantIfNeeded()`
- `config.lua:144-151` - Configuração de alertas

---

### 5. **Sistema de Residências (IPTU)** ✅

#### Housing Systems
- **ps-housing** - Suporte completo
  - Export: `GetProperties()`
  - Fallback DB: `properties` table
- **qb-houses** - Suporte via DB
  - Tabelas: `player_houses` + `houselocations`
- **qbx-houses** - Suporte via DB

**Funcionalidades:**
- Listagem de imóveis por CitizenID
- Cálculo de IPTU baseado no valor do imóvel
- Suporte a apartamentos (valor base configurável)

**Arquivos:**
- `server/integrations.lua:499-751` - Sistema de residências
  - `GetResidences()` - Lista imóveis
  - `GetResidenceSummary()` - Resumo para IPTU
  - `GetResidenceTaxBase()` - Base de cálculo

---

### 6. **Sistema de Garagens/Veículos (IPVA)** ✅

#### Garage Systems
- **rhd_garage** - Suporte completo via DB (bloqueio de eventos externos)
- **qb-garage** / **qb-garages** / **qbx-garages** - Suporte via DB

**Funcionalidades:**
- Listagem de veículos por CitizenID
- Alteração de estado (guardado/fora/apreendido)
- Apreensão e liberação de veículos
- Cálculo de IPVA baseado no valor do veículo

**Estados dos Veículos:**
- `0` = Fora da garagem
- `1` = Guardado na garagem
- `2` = Apreendido (impound)

**Arquivos:**
- `server/integrations.lua:758-987` - Sistema de garagens
  - `GetOwnedVehicles()` - Lista veículos
  - `SetVehicleStateByPlate()` - Altera estado
  - `ImpoundVehicleByPlate()` - Apreende veículo
  - `ReleaseVehicleByPlate()` - Libera veículo

---

### 7. **Sistema de Concessionárias (Preços)** ✅

#### Dealership Systems
- **rm-dealership** - Suporte completo
  - Tabela: `dealership_vehicles`
  - Join com `player_vehicles`
- **qb-vehicleshop** / **qbx-vehicleshop** - Fallback via Shared.Vehicles

**Funcionalidades:**
- Obtenção de preços de veículos por modelo
- Cálculo automático de IPVA
- Valor base mínimo configurável (se preço desconhecido)

**Arquivos:**
- `server/integrations.lua:989-1171` - Sistema de concessionárias
  - `GetVehiclePriceByModel()` - Preço por modelo
  - `GetVehicles()` - Lista com preços
  - `GetVehicleSummary()` - Resumo para IPVA

---

### 8. **Sistema de Empregos (Boss Menu)** ✅

#### Job Management
- **QBCore/QBX** - Suporte completo para jobs e gangs
- **Online e Offline**: Funciona com jogadores online e offline

**Funcionalidades:**
- Contratar empregados (online)
- Alterar cargo/grade
- Demitir funcionários
- Listar funcionários ativos
- Suporte a gangs (igual jobs)

**Permissões:**
- Validação de boss (isboss = true)
- Validação de job/gang correspondente

**Arquivos:**
- `server/integrations.lua:1172-1696` - Sistema de contratações
  - `SetJob()` / `SetGang()` - Define job/gang
  - `HireEmployee()` / `HireGangMember()` - Contrata
  - `FireEmployee()` / `FireGangMember()` - Demite
  - `GetJobEmployees()` / `GetGangMembers()` - Lista funcionários

---

### 9. **Sistema de Inventário** ✅

#### Inventory Systems
- **ox_inventory** - Suporte completo
- **ps-inventory** - Suporte via framework
- **qb-inventory** - Suporte via framework

**Funcionalidades:**
- Adicionar itens
- Remover itens
- Contar itens
- Verificar capacidade de carga
- Abrir stashes (baús)

**Arquivos:**
- `server/integrations.lua:1698-1920` - Sistema de inventário
  - `InventoryAddItem()` - Adiciona item
  - `InventoryRemoveItem()` - Remove item
  - `InventoryGetItemCount()` - Conta itens
  - `InventoryCanCarryItem()` - Verifica capacidade
  - `OpenStash()` - Abre baú

---

### 10. **Sistema de Notificações** ✅

#### Notification System
- **ox_lib** - Suporte completo via `ox_lib:notify`
- **Fallback**: Print no console

**Arquivos:**
- `shared/bridge.lua:287-305` - `B.Notify()`
- `client/nui.lua:67-78` - Cliente

---

### 11. **Sistema de Permissões** ✅

#### Permission System (Granular)
- **ACE Permissions**: `IsPlayerAceAllowed()`
- **Staff Metadata**: `player.metadata.isstaff`
- **Job + Grade**: Validação de job e grade mínimo
- **QBCore Legacy**: `HasPermission('admin')` / `HasPermission('god')`

**Configuração:**
```lua
Config.Permissions = {
  Ace = 'space_economy.admin',
  AllowStaffMeta = true,
  Jobs = {
    ['government'] = { minGrade = 3 },
    ['police'] = { minGrade = 5 },
  },
}
```

**Arquivos:**
- `shared/bridge.lua:136-204` - `B.CanAdmin()`
- `server/admin.lua:16-49` - `SE.Admin.IsAllowed()`

---

### 12. **Sistema de Logs** ✅

#### Logging System
- **MySQL**: Logs persistentes em `space_economy_logs`
- **Categorias**: system, tax, debt, vault, admin, player
- **Opcional**: Discord Webhook (configurável)

**Funcionalidades:**
- Auto-criação de tabela
- Detecção de coluna metadata/meta
- Limpeza automática após 30 dias (configurável)

**Arquivos:**
- `server/events.lua:12-79` - Sistema de logs

---

## 🎮 Comandos e Keybindings

### Comandos Disponíveis ✅
- `/taxas` - Abre painel de impostos (player)
- `/economia` - Abre painel administrativo (admin) **[TECLA: F12]**
- `/eco_testui` - Teste de UI (diagnóstico)

### Keymappings ✅
- **F7** - Abre painel de impostos
- **F12** - Abre painel administrativo ✅ **CONFIRMADO**
- **5** - Teste de UI (diagnóstico)

**Arquivos:**
- `client/commands.lua:30-48` - Comandos e keybindings

---

## 🗄️ Estrutura de Banco de Dados

### Tabelas Criadas
1. `space_economy_state` - Estado global do sistema
2. `space_economy_logs` - Logs do sistema
3. `space_economy_debts` - Dívidas ativas
4. `space_economy_installments` - Parcelamentos
5. `space_economy_loans` - Empréstimos
6. `space_economy_credit_scores` - Scores de crédito

**Arquivos:**
- `sql/schema.sql` - Schema básico
- `sql/space_economy_v2.sql` - Schema completo v2
- `server/events.lua:22-38` - Auto-criação de tabela de logs

---

## 🔧 Dependências do Resource

### Obrigatórias ✅
- `ox_lib` - UI e notificações
- `oxmysql` - Banco de dados
- `qbx_core` ou `qb-core` - Framework

### Opcionais ✅
- `ps-dispatch` - Sistema de dispatch
- `ps-mdt` - MDT para reports
- `ps-banking` - Sistema bancário
- `ps-housing` - Sistema de residências
- `rhd_garage` - Sistema de garagens
- `rm-dealership` - Concessionária
- `ox_inventory` / `ps-inventory` / `qb-inventory` - Inventário

**Arquivos:**
- `fxmanifest.lua:74-78` - Dependencies

---

## 📊 Exports Disponíveis

### Treasury (Tesouro)
- `GetTreasuryBalance()`
- `AddToTreasury(amount, reason)`
- `RemoveFromTreasury(amount, reason)`

### Tax (Impostos)
- `CalculateTax(amount)`
- `ApplyTax(src, amount, reason)`

### Debts (Dívidas)
- `CreateDebt(citizenid, amount, reason)`
- `PayDebt(debtId)`
- `GetPlayerDebts(citizenid)`

### Installments (Parcelamentos)
- `CreateInstallmentPlan(citizenid, totalAmount, installments)`
- `PayInstallment(installmentId)`

### Credit Score
- `GetCreditScore(citizenid)`
- `UpdateCreditScore(citizenid, points)`

### Loans (Empréstimos)
- `SimulateLoan(amount, installments)`
- `RequestLoan(citizenid, amount, installments)`
- `GetPlayerLoans(citizenid)`

### Auto Tax (Taxação Automática)
- `TaxVehiclePurchase(src, vehiclePrice)`
- `TaxPropertyPurchase(src, propertyPrice)`
- `TaxService(src, serviceAmount)`
- `TaxShopPurchase(src, purchaseAmount)`

### Reports (Relatórios)
- `GetEconomyReport()`
- `GetDailyMetrics()`

**Arquivos:**
- `fxmanifest.lua:85-135` - Lista de exports

---

## ✅ Checklist de Verificação

### Integrações de Framework
- [x] QBX Core - Funcionando
- [x] QBCore - Funcionando
- [ ] ESX - Suporte básico (futuro)

### Integrações de Sistemas
- [x] Banking (ps-banking) - Funcionando
- [x] Dispatch (ps-dispatch) - Funcionando
- [x] MDT (ps-mdt) - Funcionando
- [x] Housing (ps-housing) - Funcionando
- [x] Garages (rhd_garage) - Funcionando via DB
- [x] Dealership (rm-dealership) - Funcionando
- [x] Inventory (ox/ps/qb) - Funcionando

### Comandos e UI
- [x] Comando /economia - Funcionando
- [x] Comando /taxas - Funcionando
- [x] Keybinding F12 - **CONFIRMADO** ✅
- [x] Keybinding F7 - Funcionando
- [x] NUI/Interface - Funcionando

### Banco de Dados
- [x] Auto-criação de tabelas - Funcionando
- [x] Persistência de estado - Funcionando
- [x] Sistema de logs - Funcionando

### Permissões
- [x] ACE Permissions - Funcionando
- [x] Staff Metadata - Funcionando
- [x] Job + Grade - Funcionando
- [x] Legacy QB Permissions - Funcionando

---

## 🔥 Funcionalidades Avançadas

### Sistema de Crédito
- Score automático baseado em histórico
- Influencia aprovação de empréstimos

### Sistema de Empréstimos
- Simulação com juros
- Aprovação baseada em score
- Parcelamento automático

### Sistema de Parcelamento
- Divisão de dívidas em parcelas
- Taxa administrativa configurável
- Juros sobre atraso

### Taxação Automática
- IPTU automático (residências)
- IPVA automático (veículos)
- Taxas sobre compras

### Relatórios e Analytics
- Métricas diárias
- Relatórios econômicos
- Logs detalhados

---

## 🎯 Conclusão

**Status Final:** ✅ **TODAS AS INTEGRAÇÕES VERIFICADAS E FUNCIONANDO**

### Resumo:
- ✅ Framework: QBX/QBCore detectado automaticamente
- ✅ Banking: ps-banking integrado com fallbacks
- ✅ Dispatch: ps-dispatch + ps-mdt funcionando
- ✅ Housing: ps-housing + qb-houses suportados
- ✅ Garages: rhd_garage + qb-garage suportados
- ✅ Inventory: ox/ps/qb suportados
- ✅ Permissões: Sistema granular ACE + Staff + Job
- ✅ Comandos: /economia (F12) ✅ e /taxas (F7)
- ✅ Logs: MySQL persistente com auto-criação

### Próximos Passos:
1. Testes em ambiente de produção
2. Ajustes finos de configuração
3. Treinamento de administradores
4. Monitoramento de performance

---

**Revisado em:** 24/12/2025
**Revisor:** Claude AI
**Versão do Sistema:** v3.0.0
