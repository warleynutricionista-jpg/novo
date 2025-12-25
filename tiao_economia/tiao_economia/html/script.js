/**
 * ==========================================================
 * Space Economy v5.0 - Modern UI Controller
 * Author: Space Economy Team
 * Description: Complete client-side controller with modern architecture
 * ==========================================================
 */

(() => {
  'use strict';

  // ===========================
  // CONFIGURATION & CONSTANTS
  // ===========================
  const RESOURCE_NAME = (typeof GetParentResourceName === 'function' && GetParentResourceName()) || 'space_economy';
  const DEBUG = false;

  const log = (...args) => DEBUG && console.log('[SpaceEco]', ...args);
  const error = (...args) => console.error('[SpaceEco Error]', ...args);

  // ===========================
  // UTILITY FUNCTIONS
  // ===========================
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  const formatMoney = (value) => {
    const num = Number(value);
    return Number.isFinite(num) ? `$${Math.floor(num).toLocaleString('pt-BR')}` : '$0';
  };

  const formatDecimal = (value, decimals = 2) => {
    const num = Number(value);
    return Number.isFinite(num) ? num.toFixed(decimals) : (0).toFixed(decimals);
  };

  const parsePositiveInt = (value) => {
    const str = String(value ?? '').replace(/[^\d]/g, '');
    const num = Number(str);
    return Number.isFinite(num) && Math.floor(num) > 0 ? Math.floor(num) : null;
  };

  const parseNumber = (value) => {
    const num = Number(String(value ?? '').replace(',', '.'));
    return Number.isFinite(num) ? num : null;
  };

  const setElementText = (element, text) => {
    if (element) element.textContent = String(text ?? '');
  };

  const deepClone = (obj) => {
    try {
      return JSON.parse(JSON.stringify(obj));
    } catch {
      return obj;
    }
  };

  const setByPath = (obj, path, value) => {
    if (!obj || !path) return;
    const parts = String(path).split('.').filter(Boolean);
    let current = obj;
    for (let i = 0; i < parts.length; i++) {
      const key = parts[i];
      if (i === parts.length - 1) {
        current[key] = value;
        return;
      }
      if (!current[key] || typeof current[key] !== 'object') {
        current[key] = {};
      }
      current = current[key];
    }
  };

  const getByPath = (obj, path) => {
    if (!obj || !path) return undefined;
    const parts = String(path).split('.').filter(Boolean);
    let current = obj;
    for (const key of parts) {
      if (!current || typeof current !== 'object') return undefined;
      current = current[key];
    }
    return current;
  };

  // ===========================
  // NUI COMMUNICATION
  // ===========================
  const postNUI = (event, data = {}, retries = 2) => {
    log('POST:', event, data);
    return fetch(`https://${RESOURCE_NAME}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    })
    .then(resp => resp.json())
    .catch((err) => {
      error('POST failed:', event, err);
      if (retries > 0) {
        log(`Retrying ${event}... (${retries} attempts left)`);
        return new Promise(resolve =>
          setTimeout(() => resolve(postNUI(event, data, retries - 1)), 500)
        );
      }
      // Notificar erro ao usuário
      Notification.show('Erro de comunicação com o servidor. Tente novamente.', 'error');
      UI.setBusy(false);
      LoadingIndicator.hide();
      throw err;
    });
  };

  // ===========================
  // STATE MANAGEMENT
  // ===========================
  const State = {
    uiOpen: false,
    currentView: 'overview',
    adminDraft: null,
    taxCatalog: [],
    isDirty: false,
    busy: false,
    payment: { amount: 0, reason: '' },
    inputModal: { callback: null, type: 'text' },
    pendingRequests: 0,
  };

  // ===========================
  // LOADING INDICATOR
  // ===========================
  const LoadingIndicator = {
    show(message = 'Processando...') {
      State.pendingRequests++;
      const indicator = $('#loading-overlay') || this.create();
      const msgEl = indicator.querySelector('.loading-message');
      if (msgEl) msgEl.textContent = message;
      indicator.style.display = 'flex';
    },

    hide() {
      State.pendingRequests = Math.max(0, State.pendingRequests - 1);
      if (State.pendingRequests === 0) {
        const indicator = $('#loading-overlay');
        if (indicator) indicator.style.display = 'none';
      }
    },

    create() {
      const overlay = document.createElement('div');
      overlay.id = 'loading-overlay';
      overlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.7);
        display: none;
        align-items: center;
        justify-content: center;
        z-index: 10000;
      `;

      overlay.innerHTML = `
        <div style="background: #1e1e2e; padding: 2rem; border-radius: 12px; text-align: center; min-width: 300px;">
          <div style="width: 48px; height: 48px; border: 4px solid #3b82f6; border-top-color: transparent; border-radius: 50%; margin: 0 auto 1rem; animation: spin 1s linear infinite;"></div>
          <div class="loading-message" style="color: #fff; font-size: 1rem;">Processando...</div>
        </div>
      `;

      document.body.appendChild(overlay);

      // Add animation
      if (!$('#loading-animation-style')) {
        const style = document.createElement('style');
        style.id = 'loading-animation-style';
        style.textContent = '@keyframes spin { to { transform: rotate(360deg); } }';
        document.head.appendChild(style);
      }

      return overlay;
    },
  };

  // ===========================
  // NOTIFICATION SYSTEM
  // ===========================
  const Notification = {
    show(message, type = 'info', duration = 4000) {
      const notification = this.create(message, type);
      document.body.appendChild(notification);

      requestAnimationFrame(() => {
        notification.style.transform = 'translateX(0)';
        notification.style.opacity = '1';
      });

      setTimeout(() => {
        notification.style.transform = 'translateX(400px)';
        notification.style.opacity = '0';
        setTimeout(() => notification.remove(), 300);
      }, duration);
    },

    create(message, type) {
      const colors = {
        success: { bg: '#10b981', icon: '✓' },
        error: { bg: '#ef4444', icon: '✕' },
        warning: { bg: '#f59e0b', icon: '⚠' },
        info: { bg: '#3b82f6', icon: 'ℹ' },
      };

      const config = colors[type] || colors.info;

      const notification = document.createElement('div');
      notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${config.bg};
        color: white;
        padding: 1rem 1.5rem;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        display: flex;
        align-items: center;
        gap: 0.75rem;
        max-width: 400px;
        z-index: 10001;
        transform: translateX(400px);
        opacity: 0;
        transition: all 0.3s ease;
        font-size: 0.95rem;
      `;

      notification.innerHTML = `
        <span style="font-size: 1.25rem; font-weight: bold;">${config.icon}</span>
        <span>${message}</span>
      `;

      return notification;
    },
  };

  // ===========================
  // UI CONTROLLER
  // ===========================
  const UI = {
    show(visible) {
      const body = document.body;
      const overlay = $('.overlay');

      if (visible) {
        body.style.display = 'block';
        requestAnimationFrame(() => {
          if (overlay) overlay.classList.add('is-active');
        });
      } else {
        if (overlay) overlay.classList.remove('is-active');
        setTimeout(() => {
          body.style.display = 'none';
        }, 300);
      }

      State.uiOpen = visible;
    },

    hideAllCards() {
      $$('.card').forEach((card) => (card.style.display = 'none'));
    },

    showCard(cardId, displayType = 'flex') {
      this.hideAllCards();
      const card = $(`#${cardId}`);
      if (!card) return error('Card not found:', cardId);

      card.style.display = displayType;
      this.show(true);

      // Auto-focus first input
      setTimeout(() => {
        const input = card.querySelector('.form-input, .form-select');
        if (input && !input.disabled) input.focus();
      }, 100);
    },

    close() {
      this.show(false);
      this.hideAllCards();
      postNUI('forceClose');
    },

    setBusy(busy) {
      State.busy = !!busy;

      $$('[data-action], .btn').forEach((btn) => {
        btn.disabled = State.busy;
        btn.style.opacity = State.busy ? '0.6' : '1';
        btn.style.pointerEvents = State.busy ? 'none' : 'auto';
      });
    },

    setDirty(dirty) {
      State.isDirty = !!dirty;
      const badge = $('#unsaved-badge');
      const saveBtn = $('#save-settings-btn');

      if (badge) badge.classList.toggle('hidden', !State.isDirty);
      if (saveBtn) {
        saveBtn.disabled = !State.isDirty;
        saveBtn.style.opacity = State.isDirty ? '1' : '0.5';
      }
    },

    switchView(viewName) {
      State.currentView = viewName;

      $$('.view').forEach((v) => v.classList.remove('is-active'));
      const view = $(`.view[data-view="${viewName}"]`);
      if (view) view.classList.add('is-active');

      $$('.nav-item').forEach((n) => n.classList.remove('is-active'));
      const navItem = $(`.nav-item[data-view="${viewName}"]`);
      if (navItem) navItem.classList.add('is-active');
    },
  };

  // ===========================
  // ADMIN MODULE
  // ===========================
  const Admin = {
    DEFAULT_TAX_CATALOG: [
      { key: 'IPTU', label: 'IPTU', mode: 'base_percent', percent: 0.3 },
      { key: 'IPVA', label: 'IPVA', mode: 'base_percent', percent: 1.5 },
      { key: 'IRPF', label: 'Imposto de Renda', mode: 'base_percent', percent: 2.0 },
      { key: 'ICMS', label: 'ICMS', mode: 'base_percent', percent: 12.0 },
      { key: 'ISS', label: 'ISS', mode: 'base_percent', percent: 2.0 },
      { key: 'ADMIN_FINE', label: 'Multa Administrativa', mode: 'fixed', fixed: 1000 },
      { key: 'GOV_FEE', label: 'Taxa Governamental', mode: 'fixed', fixed: 500 },
      { key: 'OUTRO', label: 'Outro', mode: 'fixed', fixed: 0 },
    ],

    open(payload = {}) {
      UI.showCard('admin-container', 'grid');
      UI.switchView('overview');

      this.applyState(payload);
      this.requestData('admin_state');
    },

    applyState(data = {}) {
      const metrics = data.metrics || {};
      const settings = data.settings || {};

      State.taxCatalog = data.taxCatalog || settings.taxCatalog || this.DEFAULT_TAX_CATALOG;

      // Update metrics
      setElementText($('#metric-vault'), formatMoney(metrics.vault || 0));
      setElementText($('#metric-inflation'), formatDecimal(metrics.inflation || 1, 2));
      setElementText($('#metric-taxrate'), `${formatDecimal(metrics.taxrate || 0, 1)}%`);
      setElementText($('#metric-today'), formatMoney(metrics.today || 0));

      // Apply settings
      if (!State.isDirty) {
        State.adminDraft = deepClone(settings);
        this.applySettings(settings);
      }

      this.populateTaxSelect();
    },

    applySettings(settings = {}) {
      // Inflation mode
      const inflationMode = String(getByPath(settings, 'mode.inflation') || 'auto').toLowerCase();
      $$('.segmented-btn[data-setting="mode.inflation"]').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.value === inflationMode);
      });

      const inflationInput = $('#manual-inflation');
      if (inflationInput) {
        inflationInput.disabled = inflationMode !== 'manual';
        inflationInput.value = String(getByPath(settings, 'manual.inflation') ?? '');
      }

      // Tax rate mode
      const taxrateMode = String(getByPath(settings, 'mode.taxrate') || 'auto').toLowerCase();
      $$('.segmented-btn[data-setting="mode.taxrate"]').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.value === taxrateMode);
      });

      const taxrateInput = $('#manual-taxrate');
      if (taxrateInput) {
        taxrateInput.disabled = taxrateMode !== 'manual';
        taxrateInput.value = String(getByPath(settings, 'manual.taxrate') ?? '');
      }
    },

    populateTaxSelect() {
      const select = $('#tax-type');
      if (!select) return;

      const catalog = State.taxCatalog;
      const currentValue = select.value;

      select.innerHTML = '';
      catalog.forEach((item) => {
        const option = document.createElement('option');
        option.value = item.key;
        option.textContent = item.label;
        select.appendChild(option);
      });

      if (currentValue && catalog.some((x) => x.key === currentValue)) {
        select.value = currentValue;
      } else {
        select.value = catalog[0]?.key || 'OUTRO';
      }
    },

    calculateTaxPreview() {
      const taxKey = $('#tax-type')?.value;
      const baseValue = parsePositiveInt($('#tax-base')?.value);

      const taxType = State.taxCatalog.find((x) => x.key === taxKey);
      const preview = $('#tax-preview');
      const previewText = $('#tax-preview-text');

      if (!taxType || !baseValue) {
        if (preview) preview.classList.add('hidden');
        return;
      }

      let amount = 0;
      let text = '';

      if (taxType.mode === 'base_percent') {
        const percent = Number(taxType.percent || 0);
        amount = Math.floor(baseValue * (percent / 100));
        text = `Base ${formatMoney(baseValue)} × ${formatDecimal(percent, 2)}% = ${formatMoney(amount)}`;
      } else {
        amount = Math.floor(Number(taxType.fixed || 0));
        text = `Valor fixo = ${formatMoney(amount)}`;
      }

      const amountInput = $('#tax-amount');
      if (amountInput) amountInput.value = String(amount);

      const reasonInput = $('#tax-reason');
      if (reasonInput && !reasonInput.value) reasonInput.value = taxType.label;

      if (preview && previewText) {
        previewText.textContent = text;
        preview.classList.remove('hidden');
      }
    },

    submitTax() {
      if (State.busy) return;

      const targetMode = $('#tax-target-mode')?.value || 'citizenid';
      const citizenid = String($('#tax-citizenid')?.value || '').trim();
      const type = $('#tax-type')?.value || 'OUTRO';
      const base = parsePositiveInt($('#tax-base')?.value);
      const amount = parsePositiveInt($('#tax-amount')?.value);
      const reason = String($('#tax-reason')?.value || '').trim();

      // Validations
      if (!amount || amount <= 0) {
        Notification.show('Valor inválido', 'error');
        return;
      }
      if (targetMode === 'citizenid' && !citizenid) {
        Notification.show('Informe o CitizenID', 'error');
        return;
      }
      if (!reason || reason.length < 3) {
        Notification.show('Informe um motivo válido (mín. 3 caracteres)', 'error');
        return;
      }

      UI.setBusy(true);
      LoadingIndicator.show('Lançando tributo...');

      postNUI('admin_requestData', {
        dataType: 'admin_issueTaxDebt',
        payload: { targetMode, citizenid, type, base, amount, reason },
      })
      .then(() => {
        // Clear form after successful submission
        ['#tax-base', '#tax-amount', '#tax-reason'].forEach((selector) => {
          const input = $(selector);
          if (input) input.value = '';
        });
        const preview = $('#tax-preview');
        if (preview) preview.classList.add('hidden');

        Notification.show('Tributo lançado com sucesso!', 'success');
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    saveSettings() {
      if (!State.adminDraft || State.busy) return;

      UI.setBusy(true);
      LoadingIndicator.show('Salvando configurações...');

      postNUI('admin_requestData', {
        dataType: 'admin_saveSettings',
        payload: State.adminDraft,
      })
      .then(() => {
        UI.setDirty(false);
        Notification.show('Configurações salvas com sucesso!', 'success');
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    requestData(dataType, payload = null) {
      if (State.busy) return;
      UI.setBusy(true);
      LoadingIndicator.show('Carregando dados...');
      postNUI('admin_requestData', { dataType, payload })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },
  };

  // ===========================
  // LOANS MODULE
  // ===========================
  const Loans = {
    simulateLoan() {
      const citizenid = String($('#loan-citizenid')?.value || '').trim();
      const amount = parsePositiveInt($('#loan-amount')?.value);
      const installments = parsePositiveInt($('#loan-installments')?.value);

      const resultContainer = $('#loan-simulation-result');
      const detailsContainer = $('#loan-sim-details');

      if (!citizenid || !amount || !installments) {
        if (resultContainer) resultContainer.classList.add('hidden');
        return alert('Preencha todos os campos');
      }

      // Mock calculation (can be connected to backend)
      const interestRate = 2.5; // 2.5% per month
      const totalInterest = amount * (interestRate / 100) * installments;
      const totalAmount = amount + totalInterest;
      const monthlyPayment = Math.floor(totalAmount / installments);

      if (resultContainer && detailsContainer) {
        detailsContainer.innerHTML = `
          <div class="info-item">
            <span class="info-label">Valor Solicitado</span>
            <span class="money">${formatMoney(amount)}</span>
          </div>
          <div class="info-item">
            <span class="info-label">Taxa de Juros (${formatDecimal(interestRate, 1)}% a.m.)</span>
            <span class="money">${formatMoney(totalInterest)}</span>
          </div>
          <div class="info-item">
            <span class="info-label">Total a Pagar</span>
            <span class="money">${formatMoney(totalAmount)}</span>
          </div>
          <div class="info-item">
            <span class="info-label">Parcela Mensal</span>
            <span class="info-value">${formatMoney(monthlyPayment)} × ${installments} meses</span>
          </div>
        `;
        resultContainer.classList.remove('hidden');
      }
    },
  };

  // ===========================
  // DEBT MODULE
  // ===========================
  const Debts = {
    showList(debts = []) {
      const tbody = $('#debt-list-tbody');
      if (!tbody) return;

      if (!Array.isArray(debts) || debts.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Nenhuma dívida encontrada</td></tr>';
      } else {
        tbody.innerHTML = debts.map((d) => `
          <tr>
            <td>${String(d.playerName || 'Desconhecido')}</td>
            <td>${String(d.citizenid || '-')}</td>
            <td>${formatMoney(d.amount || 0)}</td>
            <td>${String(d.reason || '-')}</td>
          </tr>
        `).join('');
      }

      UI.showCard('debt-list-modal');
    },

    showDetail(debt = {}) {
      setElementText($('#debt-detail-name'), debt.playerName || 'Desconhecido');
      setElementText($('#debt-detail-citizenid'), debt.citizenid || '-');
      setElementText($('#debt-detail-amount'), formatMoney(debt.amount || 0));
      setElementText($('#debt-detail-reason'), debt.reason || '-');

      UI.showCard('debt-detail-modal');
    },
  };

  // ===========================
  // INPUT MODAL HELPER
  // ===========================
  const InputModal = {
    show(title, label, placeholder, callback, inputType = 'text') {
      setElementText($('#input-modal-title'), title);
      setElementText($('#input-modal-label'), label);

      const input = $('#input-modal-field');
      if (input) {
        input.type = inputType;
        input.placeholder = placeholder;
        input.value = '';
      }

      State.inputModal.callback = callback;
      State.inputModal.type = inputType;

      UI.showCard('input-modal');
    },

    confirm() {
      const input = $('#input-modal-field');
      const value = input?.value?.trim() || '';

      if (!value) {
        Notification.show('Preencha o campo', 'error');
        return;
      }

      if (State.inputModal.callback) {
        State.inputModal.callback(value);
      }

      // Não fecha UI aqui - deixa a callback decidir quando fechar
      // ou o loading indicator cuidar disso
    },
  };

  // ===========================
  // LOGS MODULE
  // ===========================
  const Logs = {
    render(logs = []) {
      const tbody = $('#logs-table tbody');
      if (!tbody) return;

      if (!Array.isArray(logs) || logs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" class="text-center text-muted">Nenhum log disponível</td></tr>';
      } else {
        tbody.innerHTML = logs.map((l) => `
          <tr>
            <td>${String(l.timestamp || '-')}</td>
            <td>${String(l.category || '-')}</td>
            <td>${String(l.message || '-')}</td>
          </tr>
        `).join('');
      }
    },
  };

  // ===========================
  // ACTION ROUTER
  // ===========================
  const Actions = {
    // Admin actions
    'refresh-admin'() { Admin.requestData('admin_state'); },
    'reset-settings'() {
      if (confirm('Restaurar configurações padrão?')) {
        UI.setDirty(true);
        State.adminDraft = {};
        Admin.applySettings({});
      }
    },

    // Tax actions
    'calc-tax'() { Admin.calculateTaxPreview(); },
    'submit-tax'() { Admin.submitTax(); },

    // Treasury quick actions
    'quick-vault'() { Admin.requestData('viewVault'); },
    'quick-deposit'() {
      InputModal.show('Depositar no Tesouro', 'Valor', 'Digite o valor', (value) => {
        const amount = parsePositiveInt(value);
        if (amount) {
          LoadingIndicator.show('Processando depósito...');
          Admin.requestData('addVault', { amount });
        } else {
          Notification.show('Valor inválido', 'error');
        }
      }, 'number');
    },
    'quick-withdraw'() {
      InputModal.show('Sacar do Tesouro', 'Valor', 'Digite o valor', (value) => {
        const amount = parsePositiveInt(value);
        if (amount) {
          LoadingIndicator.show('Processando saque...');
          Admin.requestData('withdrawVault', { amount });
        } else {
          Notification.show('Valor inválido', 'error');
        }
      }, 'number');
    },
    'quick-debts'() { Admin.requestData('debts_active'); },

    // Debt actions
    'refresh-debts'() { Admin.requestData('debts_stats'); },
    'list-all-debts'() { Admin.requestData('debts_active'); },
    'search-debt'() {
      const citizenid = String($('#debt-search-citizenid')?.value || '').trim();
      if (!citizenid) return alert('Informe o CitizenID');
      Admin.requestData('specific_debt', citizenid);
    },

    // Loan actions
    'refresh-loans'() { Admin.requestData('loans_stats'); },
    'list-all-loans'() { Admin.requestData('loans_list'); },
    'simulate-loan'() { Loans.simulateLoan(); },

    // Installment actions
    'refresh-installments'() { Admin.requestData('installments_stats'); },
    'list-all-installments'() { Admin.requestData('installments_list'); },
    'search-installment'() {
      const citizenid = String($('#installment-search-citizenid')?.value || '').trim();
      if (!citizenid) return alert('Informe o CitizenID');
      Admin.requestData('search_installment', { citizenid });
    },

    // Treasury actions
    'treasury-deposit'() { this['quick-deposit'](); },
    'treasury-withdraw'() { this['quick-withdraw'](); },
    'treasury-history'() { alert('Funcionalidade em desenvolvimento'); },

    // Logs
    'refresh-logs'() { Admin.requestData('admin_logs', { limit: 100 }); },

    // Payment modal
    'confirm-payment'() {
      if (State.busy) return;
      UI.setBusy(true);
      LoadingIndicator.show('Processando pagamento...');
      postNUI('payTax', { tax: State.payment.amount, reason: State.payment.reason })
      .then(() => {
        Notification.show('Pagamento realizado com sucesso!', 'success');
        UI.close();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },
    'refuse-payment'() {
      postNUI('refuseTax', { tax: State.payment.amount, reason: State.payment.reason });
      Notification.show('Pagamento recusado', 'info');
      UI.close();
    },
  };

  // ===========================
  // EVENT LISTENERS
  // ===========================
  function initEventListeners() {
    // Global close buttons
    $$('[data-close]').forEach((btn) => {
      btn.addEventListener('click', () => UI.close());
    });

    // Navigation
    $$('.nav-item[data-view]').forEach((btn) => {
      btn.addEventListener('click', () => UI.switchView(btn.dataset.view));
    });

    // Action buttons
    document.addEventListener('click', (e) => {
      const actionBtn = e.target.closest('[data-action]');
      if (actionBtn) {
        const action = actionBtn.dataset.action;
        if (Actions[action]) {
          log('Action:', action);
          Actions[action]();
        } else {
          error('Unknown action:', action);
        }
      }

      // Dashboard cards
      const dashCard = e.target.closest('.dashboard-card[data-action]');
      if (dashCard) {
        const action = dashCard.dataset.action;
        if (Actions[action]) Actions[action]();
      }

      // Tax chips
      const chip = e.target.closest('.chip[data-tax]');
      if (chip) {
        $$('.chip').forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        const select = $('#tax-type');
        if (select) select.value = chip.dataset.tax;
        Admin.calculateTaxPreview();
      }

      // Segmented control
      const segBtn = e.target.closest('.segmented-btn[data-setting]');
      if (segBtn && State.adminDraft) {
        const setting = segBtn.dataset.setting;
        const value = segBtn.dataset.value;

        setByPath(State.adminDraft, setting, value);
        Admin.applySettings(State.adminDraft);
        UI.setDirty(true);
      }
    });

    // Form inputs for settings
    ['#manual-inflation', '#manual-taxrate'].forEach((selector) => {
      const input = $(selector);
      if (input) {
        input.addEventListener('input', (e) => {
          const path = selector.includes('inflation') ? 'manual.inflation' : 'manual.taxrate';
          const value = parseNumber(e.target.value);
          if (State.adminDraft) {
            setByPath(State.adminDraft, path, value);
            UI.setDirty(true);
          }
        });
      }
    });

    // Tax target mode change
    const taxTargetMode = $('#tax-target-mode');
    if (taxTargetMode) {
      taxTargetMode.addEventListener('change', (e) => {
        const group = $('#tax-citizenid-group');
        if (group) {
          group.style.display = e.target.value === 'citizenid' ? 'block' : 'none';
        }
      });
    }

    // Save settings button
    const saveBtn = $('#save-settings-btn');
    if (saveBtn) {
      saveBtn.addEventListener('click', () => Admin.saveSettings());
    }

    // Input modal confirm
    const inputConfirm = $('#input-modal-confirm');
    if (inputConfirm) {
      inputConfirm.addEventListener('click', () => InputModal.confirm());
    }

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && State.uiOpen) {
        UI.close();
      }

      if (e.key === 'Enter' && State.uiOpen) {
        const activeElement = document.activeElement;
        if (activeElement && activeElement.tagName === 'TEXTAREA') return;

        // Find visible card with primary button
        const visibleCard = $$('.card').find((c) => {
          const style = window.getComputedStyle(c);
          return style.display !== 'none';
        });

        if (visibleCard) {
          const primaryBtn = visibleCard.querySelector('.btn-primary:not([disabled])');
          if (primaryBtn) primaryBtn.click();
        }
      }
    });
  }

  // ===========================
  // NUI MESSAGE HANDLER
  // ===========================
  window.addEventListener('message', (event) => {
    const data = event.data || {};
    const action = data.action;

    if (!action) return;
    log('NUI Message:', action, data);

    switch (action) {
      case 'close':
        UI.close();
        break;

      case 'open': {
        postNUI('ready', { ok: true });

        const mode = String(data.mode || '');
        const payload = data.payload || {};

        if (mode === 'admin') {
          Admin.open(payload);
        } else if (mode === 'payment') {
          State.payment.amount = Number(payload.tax || 0);
          State.payment.reason = String(payload.reason || '—');
          setElementText($('#payment-amount'), formatMoney(State.payment.amount));
          setElementText($('#payment-reason'), State.payment.reason);
          UI.showCard('payment-modal');
        }
        break;
      }

      case 'adminData': {
        const key = data.key;
        const d = data.data;

        // Tratamento de erro do servidor
        if (key === 'error') {
          const errorMsg = (d && d.message) || 'Erro desconhecido';
          Notification.show(errorMsg, 'error');
          UI.setBusy(false);
          LoadingIndicator.hide();
          break;
        }

        if (key === 'admin_state') {
          Admin.applyState(d || {});
        } else if (key === 'admin_logs') {
          Logs.render((d && d.logs) || []);
        } else if (key === 'debts_active') {
          Debts.showList(d || []);
        } else if (key === 'specific_debt' || key === 'debt_specific') {
          Debts.showDetail(d || {});
        } else if (key === 'loans_stats') {
          const stats = d || {};
          setElementText($('#loans-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#loans-avg-rate'), `${formatDecimal(stats.avgRate || 0, 1)}%`);
          setElementText($('#loans-count'), stats.count || 0);
        } else if (key === 'installments_stats') {
          const stats = d || {};
          setElementText($('#installments-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#installments-count'), stats.count || 0);
        } else if (key === 'debts_stats') {
          const stats = d || {};
          setElementText($('#debts-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#debts-count'), stats.count || 0);
        }

        UI.setBusy(false);
        LoadingIndicator.hide();
        break;
      }

      default:
        log('Unhandled action:', action);
    }
  });

  // ===========================
  // INITIALIZATION
  // ===========================
  function init() {
    log('Initializing Space Economy UI v5.0...');
    initEventListeners();
    UI.show(false);
    log('UI Ready!');
  }

  // Start when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
