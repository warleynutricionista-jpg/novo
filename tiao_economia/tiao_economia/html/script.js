(() => {
  const RESOURCE =
    (typeof GetParentResourceName === "function" && GetParentResourceName()) ||
    "space_economy";

  const DEBUG = false;
  const log = (...a) => DEBUG && console.log("[SpaceEco UI]", ...a);

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const safeText = (el, text) => {
    if (!el) return;
    el.textContent = String(text ?? "");
  };

  const fmtMoney = (v) => {
    const n = Number(v);
    return Number.isFinite(n) ? Math.floor(n).toLocaleString("pt-BR") : "0";
  };

  const fmtFixed = (v, d = 2) => {
    const n = Number(v);
    return Number.isFinite(n) ? n.toFixed(d) : (0).toFixed(d);
  };

  const parsePositiveInt = (value) => {
    const raw = String(value ?? "").replace(/[^\d]/g, "");
    const n = Number(raw);
    return Number.isFinite(n) && Math.floor(n) > 0 ? Math.floor(n) : null;
  };

  const parseNumber = (value) => {
    const n = Number(String(value ?? "").replace(",", "."));
    return Number.isFinite(n) ? n : null;
  };

  const deepClone = (v) => {
    try {
      return JSON.parse(JSON.stringify(v));
    } catch {
      return v;
    }
  };

  const setByPath = (obj, path, value) => {
    if (!obj || !path) return;
    const parts = String(path).split(".").filter(Boolean);
    let cur = obj;
    for (let i = 0; i < parts.length; i++) {
      const k = parts[i];
      if (i === parts.length - 1) {
        cur[k] = value;
        return;
      }
      if (!cur[k] || typeof cur[k] !== "object") cur[k] = {};
      cur = cur[k];
    }
  };

  const getByPath = (obj, path) => {
    if (!obj || !path) return undefined;
    const parts = String(path).split(".").filter(Boolean);
    let cur = obj;
    for (const k of parts) {
      if (!cur || typeof cur !== "object") return undefined;
      cur = cur[k];
    }
    return cur;
  };

  // -----------------------------
  // Networking (NUI callbacks)
  // -----------------------------
  const post = (event, data = {}) => {
    log("POST:", event, data);
    return fetch(`https://${RESOURCE}/${event}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    }).catch(() => {});
  };

  // -----------------------------
  // Busy lock
  // -----------------------------
  const Busy = (() => {
    let locked = false;
    let timer = null;

    const apply = (state) => {
      $$("[data-busy-control]").forEach((btn) => {
        btn.disabled = state;
        btn.style.opacity = state ? "0.7" : "1";
        btn.style.pointerEvents = state ? "none" : "auto";
      });
    };

    return {
      get: () => locked,
      set: (state, timeoutMs = 0) => {
        locked = !!state;
        apply(locked);

        if (timer) clearTimeout(timer);
        timer = null;

        if (locked && timeoutMs > 0) {
          timer = setTimeout(() => {
            locked = false;
            apply(false);
          }, timeoutMs);
        }
      },
    };
  })();

  // -----------------------------
  // UI core
  // -----------------------------
  const showUI = (show) => {
    const body = document.body;
    const overlay = $(".overlay");

    if (show) {
      body.style.display = "block";
      requestAnimationFrame(() => overlay && overlay.classList.add("is-active"));
      overlay && overlay.setAttribute("aria-hidden", "false");
    } else {
      overlay && overlay.classList.remove("is-active");
      overlay && overlay.setAttribute("aria-hidden", "true");
      setTimeout(() => {
        body.style.display = "none";
      }, 250);
    }
  };

  const hideAllCards = () => {
    $$(".card").forEach((c) => (c.style.display = "none"));
  };

  const focusFirstInput = (root) => {
    setTimeout(() => {
      const el =
        root.querySelector("[data-autofocus]") ||
        root.querySelector("input:not([disabled]), button.primary:not([disabled]), select");
      if (el && typeof el.focus === "function") el.focus();
    }, 40);
  };

  const openPanel = (cardId) => {
    hideAllCards();
    const el = document.getElementById(cardId);
    if (!el) return console.error(`[SpaceEco UI] Card inexistente: ${cardId}`);

    const isAdmin = cardId === "admin-dashboard-container";
    el.style.display = isAdmin ? "grid" : "flex";
    showUI(true);
    focusFirstInput(el);
    Busy.set(false);
  };

  const closeAllPanels = (notifyLua = true) => {
    showUI(false);
    hideAllCards();
    Busy.set(false);
    if (notifyLua) post("forceClose");
  };

  // -----------------------------
  // Renderers
  // -----------------------------
  const renderDebtList = (debts) => {
    const tbody = $("#debt-table tbody");
    if (!tbody) return;

    tbody.innerHTML = "";
    if (!Array.isArray(debts) || debts.length === 0) return;

    debts.forEach((d) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${String(d.playerName || "Desconhecido")}</td>
        <td>${String(d.citizenid || "-")}</td>
        <td>$${fmtMoney(d.amount)}</td>
        <td>${String(d.reason || "-")}</td>
      `;
      tbody.appendChild(tr);
    });
  };

  const renderAdminLogs = (logs) => {
    const body = $("#admin-logs-table tbody");
    if (!body) return;

    body.innerHTML = "";
    if (!Array.isArray(logs) || logs.length === 0) {
      body.innerHTML =
        '<tr><td colspan="3" class="muted">Sem dados carregados.</td></tr>';
      return;
    }

    logs.forEach((l) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${String(l.timestamp || "-")}</td>
        <td>${String(l.category || "-")}</td>
        <td>${String(l.message || "-")}</td>
      `;
      body.appendChild(tr);
    });
  };

  // -----------------------------
  // Payment state
  // -----------------------------
  const Payment = { tax: 0, reason: "—" };

  // -----------------------------
  // Admin module
  // -----------------------------
  const Admin = (() => {
    const state = {
      ready: false,
      dirty: false,
      draft: null,
      activeView: "overview",
      taxCatalog: null,
    };

    const root = () => $("#admin-dashboard-container");

    const DEFAULT_TAX_CATALOG = [
      { key: "IPTU", label: "IPTU", mode: "base_percent", percent: 0.3 },
      { key: "IPVA", label: "IPVA", mode: "base_percent", percent: 1.5 },
      { key: "IRPF", label: "Imposto de Renda", mode: "base_percent", percent: 2.0 },
      { key: "ADMIN_FINE", label: "Multa Administrativa", mode: "fixed", fixed: 1000 },
      { key: "GOV_FEE", label: "Taxa Governamental", mode: "fixed", fixed: 500 },
      { key: "OUTRO", label: "Outro", mode: "fixed", fixed: 0 },
    ];

    const setStatus = (msg, kind = "") => {
      const el = $("#issue-status", root());
      if (!el) return;
      el.textContent = msg || "";
      el.className = `inline-status ${kind}`.trim();
      el.style.display = msg ? "block" : "none";
    };

    const setDirty = (v) => {
      state.dirty = !!v;

      const saveBtn = $('[data-action="saveAdminSettings"]', root());
      if (saveBtn) {
        saveBtn.disabled = !state.dirty;
        saveBtn.style.opacity = state.dirty ? "1" : "0.5";
      }

      const tag = $("#admin-unsaved-tag", root());
      if (tag) tag.style.display = state.dirty ? "inline-flex" : "none";
    };

    const setActiveView = (viewName) => {
      state.activeView = viewName || "overview";
      const r = root();
      if (!r) return;

      $$(".view", r).forEach((v) => v.classList.remove("is-active"));
      const view = $(`.view[data-view="${state.activeView}"]`, r);
      if (view) view.classList.add("is-active");

      $$(".nav-item", r).forEach((n) => n.classList.remove("is-active"));
      const nav = $(`.nav-item[data-nav="${state.activeView}"]`, r);
      if (nav) nav.classList.add("is-active");
    };

    const applyMetrics = (m = {}) => {
      safeText($("#metric-vault"), `$${fmtMoney(m.vault ?? 0)}`);
      safeText($("#metric-inflation"), fmtFixed(m.inflation ?? 1, 2));
      safeText($("#metric-taxrate"), `${fmtFixed(m.taxrate ?? 0, 1)}%`);
      safeText($("#metric-today"), `$${fmtMoney(m.today ?? 0)}`);
    };

    const applySettings = (s = {}) => {
      state.draft = deepClone(s);

      const r = root();
      if (!r) return;

      ["inflation", "taxrate"].forEach((k) => {
        const mode = String(getByPath(state.draft, `mode.${k}`) || "auto").toLowerCase();
        const btns = $$(`.seg[data-setting="mode.${k}"]`, r);
        btns.forEach((b) => b.classList.remove("is-active"));
        const active = btns.find((b) => String(b.dataset.mode || "").toLowerCase() === mode);
        active && active.classList.add("is-active");

        const inputId = k === "inflation" ? "manual-inflation" : "manual-taxrate";
        const input = document.getElementById(inputId);
        if (input) {
          input.disabled = mode !== "manual";
          input.style.opacity = mode === "manual" ? "1" : "0.5";
        }
      });

      const mi = document.getElementById("manual-inflation");
      if (mi) mi.value = String(getByPath(state.draft, "manual.inflation") ?? "");

      const mt = document.getElementById("manual-taxrate");
      if (mt) mt.value = String(getByPath(state.draft, "manual.taxrate") ?? "");

      state.ready = true;
      setDirty(false);
    };

    const populateTaxSelect = () => {
      const r = root();
      const sel = $("#issue-tax-type", r);
      if (!sel) return;

      const catalog = state.taxCatalog || DEFAULT_TAX_CATALOG;
      const prev = sel.value;

      sel.innerHTML = "";
      catalog.forEach((it) => {
        const opt = document.createElement("option");
        opt.value = it.key;
        opt.textContent = it.label;
        sel.appendChild(opt);
      });

      if (prev && catalog.some((x) => x.key === prev)) sel.value = prev;
      else sel.value = catalog[0]?.key || "OUTRO";
    };

    const calculatePreview = () => {
      const r = root();
      const taxKey = $("#issue-tax-type", r)?.value;
      const catalog = state.taxCatalog || DEFAULT_TAX_CATALOG;
      const type = catalog.find((x) => x.key === taxKey);

      const base = parsePositiveInt($("#issue-base", r)?.value);
      if (!type || !base) {
        setStatus("");
        safeText($("#issue-preview", r), "—");
        return;
      }

      let amount = 0;
      if (type.mode === "base_percent") {
        const pct = Number(type.percent || 0);
        amount = Math.floor(base * (pct / 100));
        safeText(
          $("#issue-preview", r),
          `Base $${fmtMoney(base)} × ${fmtFixed(pct, 2)}% = $${fmtMoney(amount)}`
        );
      } else {
        amount = Math.floor(Number(type.fixed || 0));
        safeText($("#issue-preview", r), `Valor fixo = $${fmtMoney(amount)}`);
      }

      const amountEl = $("#issue-amount", r);
      if (amountEl) amountEl.value = String(amount);

      const reasonEl = $("#issue-reason", r);
      if (reasonEl && !reasonEl.value) reasonEl.value = type.label;
      setStatus("");
    };

    const request = (dataType, payload) => {
      if (Busy.get()) return;
      Busy.set(true, 2500);
      post("admin_requestData", { dataType, payload });
    };

    const save = () => {
      if (!state.ready || !state.draft || Busy.get()) return;
      Busy.set(true, 5000);
      post("admin_requestData", { dataType: "admin_saveSettings", payload: state.draft });
      setDirty(false);
    };

    const submitTax = () => {
      if (Busy.get()) return;

      const r = root();
      const targetMode = $("#issue-target-mode", r)?.value || "citizenid";
      const citizenid = String($("#issue-citizenid", r)?.value || "").trim();

      const payload = {
        targetMode,
        citizenid,
        type: $("#issue-tax-type", r)?.value || "OUTRO",
        base: parsePositiveInt($("#issue-base", r)?.value),
        amount: parsePositiveInt($("#issue-amount", r)?.value),
        reason: String($("#issue-reason", r)?.value || "").trim(),
      };

      if (!payload.amount) return setStatus("Valor inválido.", "error");
      if (targetMode === "citizenid" && !citizenid) return setStatus("Informe o CitizenID.", "error");

      Busy.set(true, 5000);
      setStatus("Enviando...", "warn");
      request("admin_issueTaxDebt", payload);

      setTimeout(() => {
        setStatus("Solicitação enviada.", "ok");
        Busy.set(false);
      }, 450);
    };

    const bind = () => {
      const r = root();
      if (!r) return;

      r.addEventListener("click", (e) => {
        const nav = e.target.closest("[data-nav]");
        if (nav) return setActiveView(nav.dataset.nav);

        const seg = e.target.closest(".seg");
        if (seg && state.draft) {
          const key = seg.dataset.setting;
          const mode = seg.dataset.mode;
          if (key && mode) {
            setByPath(state.draft, key, mode);
            applySettings(state.draft);
            setDirty(true);
          }
          return;
        }

        const action = e.target.closest("[data-action]")?.dataset?.action;
        if (action) {
          if (action === "refreshAdmin") request("admin_state");
          if (action === "saveAdminSettings" && state.dirty) save();
          if (action === "fetchLogs") request("admin_logs", { limit: 80 });

          if (action === "issueCalc") calculatePreview();
          if (action === "issueSubmit") submitTax();

          if (["viewVault", "addVault", "withdrawVault", "viewDebts"].includes(action)) request(action);

          if (action === "viewSpecificDebt") showDebtInput("specific_debt", "Buscar Dívida");
          if (action === "collectDebt") showDebtInput("collect_debt", "Cobrar Dívida");
        }

        const chip = e.target.closest("[data-tax]");
        if (chip) {
          const sel = $("#issue-tax-type", r);
          if (sel) sel.value = chip.dataset.tax;
          calculatePreview();
        }
      });

      r.addEventListener("input", (e) => {
        const el = e.target;
        const path = el?.dataset?.setting;
        if (!path || !state.draft) return;

        let val = el.value;
        if (el.type === "number") val = parseNumber(val);
        setByPath(state.draft, path, val);
        setDirty(true);
      });

      $("#issue-target-mode", r)?.addEventListener("change", (e) => {
        const wrap = $("#issue-citizenid-wrap", r);
        if (wrap) wrap.style.display = e.target.value === "citizenid" ? "block" : "none";
      });
    };

    const applyState = (data) => {
      const metrics = data.metrics || {};
      const settings = data.settings || {};

      if (data.taxCatalog || settings.taxCatalog) state.taxCatalog = data.taxCatalog || settings.taxCatalog;

      applyMetrics(metrics);
      populateTaxSelect();
      if (!state.dirty) applySettings(settings);
    };

    const open = (payload) => {
      openPanel("admin-dashboard-container");
      setActiveView("overview");
      state.ready = false;
      state.dirty = false;
      if (payload) applyState(payload);
      request("admin_state");
    };

    return { bind, open, applyState, renderLogs: renderAdminLogs };
  })();

  // -----------------------------
  // Generic modal input (Debt)
  // -----------------------------
  function showDebtInput(action, title) {
    safeText($("#debt-input-title"), title);
    const input = $("#debt-citizenid-input");
    if (input) input.value = "";

    const cont = $("#debt-input-container");
    if (cont) cont.dataset.action = action;

    openPanel("debt-input-container");
    Busy.set(false);
  }

  $("#debt-input-confirm")?.addEventListener("click", () => {
    const cont = $("#debt-input-container");
    const action = cont?.dataset?.action;
    const cid = String($("#debt-citizenid-input")?.value || "").trim();
    if (!action || !cid || Busy.get()) return;

    Busy.set(true, 5000);
    post("admin_requestData", { dataType: action, payload: cid });
    closeAllPanels(true);
  });

  // -----------------------------
  // NUI messages (lua -> js)
  // -----------------------------
  window.addEventListener("message", (event) => {
    const data = event.data || {};
    const action = data.action;

    if (action) log("MSG:", action, data);

    switch (action) {
      case "close":
        closeAllPanels(false);
        break;

      case "open": {
        post("ready", { ok: true });

        const mode = String(data.mode || "");
        const payload = data.payload || {};

        if (mode === "admin") {
          Admin.open(payload);
          break;
        }

        if (mode === "vault_view") {
          safeText($("#vault-balance-value"), `$${fmtMoney(payload.balance)}`);
          openPanel("vault-view-container");
          break;
        }

        if (mode === "vault_add") {
          $("#add-amount-input") && ($("#add-amount-input").value = "");
          openPanel("vault-add-container");
          break;
        }

        if (mode === "vault_withdraw") {
          $("#withdraw-amount-input") && ($("#withdraw-amount-input").value = "");
          openPanel("vault-withdraw-container");
          break;
        }

        if (mode === "tax") {
          $("#calculator-input") && ($("#calculator-input").value = "");
          openPanel("calculator-container");
          break;
        }

        if (mode === "payment") {
          Payment.tax = Number(payload.tax || 0);
          Payment.reason = String(payload.reason || "—");
          safeText($("#tax-value"), `$${fmtMoney(Payment.tax)}`);
          safeText($("#tax-reason"), Payment.reason);
          openPanel("payment-container");
          break;
        }

        break;
      }

      case "adminData": {
        const key = data.key;
        const d = data.data;

        if (key === "admin_state") {
          Admin.applyState(d || {});
          Busy.set(false);
          break;
        }

        if (key === "admin_logs") {
          Admin.renderLogs((d && d.logs) || []);
          Busy.set(false);
          break;
        }

        if (key === "debts_active") {
          renderDebtList(d || []);
          openPanel("debt-list-container");
          Busy.set(false);
          break;
        }

        if (key === "debt_specific") {
          const row = d || {};
          safeText($("#debt-detail-name"), row.playerName || "Desconhecido");
          safeText($("#debt-detail-citizenid"), row.citizenid || "-");
          safeText($("#debt-detail-amount"), `$${fmtMoney(row.amount || 0)}`);
          safeText($("#debt-detail-reason"), row.reason || "-");
          openPanel("debt-detail-container");
          Busy.set(false);
          break;
        }

        Busy.set(false);
        break;
      }

      default:
        break;
    }
  });

  // -----------------------------
  // Global bindings
  // -----------------------------
  $$("[data-close-button]").forEach((btn) => {
    btn.addEventListener("click", () => closeAllPanels(true));
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeAllPanels(true);
    if (e.key === "Enter") {
      const active = document.activeElement;
      if (active && active.tagName === "TEXTAREA") return;

      const visible = $$(".card").find((c) => getComputedStyle(c).display !== "none");
      if (!visible) return;

      const primary = visible.querySelector(".button.primary:not([disabled])");
      if (primary) primary.click();
    }
  });

  // Payment
  $("#pay")?.addEventListener("click", () => {
    if (Busy.get()) return;
    Busy.set(true, 5000);
    post("payTax", { tax: Payment.tax, reason: Payment.reason });
    setTimeout(() => {
      safeText($("#success-message"), `Taxa de $${fmtMoney(Payment.tax)} paga com sucesso.`);
      openPanel("success-container");
      Busy.set(false);
    }, 250);
  });

  $("#refuse")?.addEventListener("click", () => {
    if (Busy.get()) return;
    post("refuseTax", { tax: Payment.tax, reason: Payment.reason });
    closeAllPanels(true);
  });

  // Vault
  $("#add-vault-confirm")?.addEventListener("click", () => {
    const amt = parsePositiveInt($("#add-amount-input")?.value);
    if (!amt || Busy.get()) return;
    Busy.set(true, 5000);
    post("admin_requestData", { dataType: "addVault", payload: { amount: amt } });
    closeAllPanels(true);
  });

  $("#withdraw-vault-confirm")?.addEventListener("click", () => {
    const amt = parsePositiveInt($("#withdraw-amount-input")?.value);
    if (!amt || Busy.get()) return;
    Busy.set(true, 5000);
    post("admin_requestData", { dataType: "withdrawVault", payload: { amount: amt } });
    closeAllPanels(true);
  });

  // Calculator
  $("#calculator-confirm")?.addEventListener("click", () => {
    const amount = parsePositiveInt($("#calculator-input")?.value);
    if (!amount || Busy.get()) return;
    Busy.set(true, 2500);
    post("calculateTax", { amount });
    setTimeout(() => Busy.set(false), 300);
  });

  // Init
  Admin.bind();
  showUI(false);
})();
