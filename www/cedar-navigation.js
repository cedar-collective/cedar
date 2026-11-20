// A start page: a link a reader chose with "Make this my start page" (the
// link menu beside a page's filters). Opening CEDAR with nothing in the address
// goes there; any address with its own page or scope wins, and the CEDAR title
// still opens Home. Kept in this browser only. Runs before the page builds.
(() => {
  if (window.location.search && window.location.search !== '?') return;
  try {
    const saved = JSON.parse(window.localStorage.getItem('cedar-start-page') || 'null');
    if (saved && typeof saved.query === 'string' && /^tab=[a-z0-9-]+(&|$)/.test(saved.query)) {
      window.location.replace(window.location.pathname + '?' + saved.query + window.location.hash);
    }
  } catch (e) { /* storage blocked or unreadable: open Home */ }
})();

// A run button waits for its inputs (cedar_requires() in
// R/modules/ui-helpers.R): disabled, its hint as the tooltip, until each input
// it names holds a value. Every such button is checked whenever any input
// changes, so a restored link or a server update enables it too.
(() => {
  const valueOf = (id) => {
    const el = document.getElementById(id);
    if (!el) return null;
    if (el.classList.contains('shiny-input-radiogroup') || el.classList.contains('shiny-input-checkboxgroup')) {
      return [...el.querySelectorAll('input:checked')].map((i) => i.value);
    }
    if (el.type === 'checkbox') return el.checked;
    if (el.selectize) return el.selectize.getValue();
    if (el.multiple) return [...el.selectedOptions].map((o) => o.value);
    return el.value;
  };
  // The value Shiny holds, which a programmatic setInputValue() changes
  // without touching the DOM; its key may carry a ":type" suffix.
  const shinyValueOf = (id) => {
    const values = window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$inputValues;
    if (!values) return null;
    if (id in values) return values[id];
    const key = Object.keys(values).find((k) => k.startsWith(id + ':'));
    return key ? values[key] : null;
  };
  const hasValue = (v) => {
    if (Array.isArray(v)) return v.some((x) => x !== null && String(x).trim() !== '');
    if (typeof v === 'boolean') return v;
    return v !== null && v !== undefined && String(v).trim() !== '';
  };
  const filled = (id) => hasValue(valueOf(id)) || hasValue(shinyValueOf(id));
  const sync = () => {
    document.querySelectorAll('button[data-cedar-requires]').forEach((button) => {
      let spec;
      try { spec = JSON.parse(button.getAttribute('data-cedar-requires')); } catch (e) { return; }
      let ids = spec.inputs || [];
      if (spec.when) {
        const w = shinyValueOf(spec.when) ?? valueOf(spec.when);
        ids = (spec.cases || {})[Array.isArray(w) ? w[0] : w] || [];
      }
      const ready = ids.length === 0 || (spec.any ? ids.some(filled) : ids.every(filled));
      if (!button.hasAttribute('data-cedar-title')) button.setAttribute('data-cedar-title', button.title || '');
      button.disabled = !ready;
      button.setAttribute('aria-disabled', ready ? 'false' : 'true');
      button.title = ready ? button.getAttribute('data-cedar-title') : (button.getAttribute('data-cedar-requires-hint') || '');
    });
  };
  window.cedarSyncRunButtons = sync;
  $(document).on('change input', sync);
  $(document).on('shiny:inputchanged shiny:connected shiny:value', () => setTimeout(sync, 0));
  document.addEventListener('DOMContentLoaded', sync);
})();

// Home says what the start page is and offers to clear it.
(() => {
  window.cedarShowStartPage = () => {
    const status = document.getElementById('cedar_start_page_status');
    const clear = document.getElementById('cedar_start_page_clear');
    if (!status) return;
    let saved = null;
    try { saved = JSON.parse(window.localStorage.getItem('cedar-start-page') || 'null'); } catch (e) { saved = null; }
    status.textContent = '';
    if (saved && saved.query) {
      status.append('This browser opens CEDAR on ');
      const link = document.createElement('a');
      link.href = '?' + saved.query;
      link.textContent = saved.label || saved.query;
      status.append(link, '.');
    } else {
      status.append('No start page is set, so CEDAR opens here.');
    }
    if (clear) clear.hidden = !(saved && saved.query);
  };
  document.addEventListener('click', event => {
    if (!event.target.closest('#cedar_start_page_clear')) return;
    try { window.localStorage.removeItem('cedar-start-page'); } catch (e) { /* nothing kept */ }
    window.cedarShowStartPage();
  });
  document.addEventListener('DOMContentLoaded', () => window.cedarShowStartPage());
})();

// bslib's independently generated menu prefixes can collide. Resolve primary
// panels by their data-value before Bootstrap or URL navigation follows an ID.
(() => {
  window.cedarEnsureNavTargets = id => {
    const navbar = document.getElementById(id);
    if (!navbar) throw new Error(`Missing primary navbar: ${id}`);
    const links = [...navbar.querySelectorAll('a[data-value]:not(.dropdown-toggle)')];
    const values = links.map(link => link.dataset.value);
    if (!values.length || new Set(values).size !== values.length) {
      throw new Error('Primary navbar values must be unique');
    }
    const contents = [...document.querySelectorAll('.tab-content')].filter(content => {
      const labels = [...content.children].map(panel => panel.dataset.value);
      return content.dataset.tabsetid === navbar.dataset.tabsetid && values.every(value => labels.includes(value));
    });
    if (contents.length !== 1) throw new Error('Expected one primary navigation content container');
    const panels = [...contents[0].children];
    links.forEach((link, index) => {
      const matches = panels.filter(panel => panel.dataset.value === link.dataset.value);
      if (matches.length !== 1) throw new Error(`Ambiguous primary panel: ${link.dataset.value}`);
      const target = `${id}-panel-${index + 1}`;
      matches[0].id = target;
      link.setAttribute('href', `#${target}`);
      for (const attr of ['data-bs-target', 'data-target']) {
        if (link.hasAttribute(attr)) link.setAttribute(attr, `#${target}`);
      }
      if (link.hasAttribute('aria-controls')) link.setAttribute('aria-controls', target);
    });
  };
  document.addEventListener('DOMContentLoaded', () => window.cedarEnsureNavTargets('main_navbar'));

  // The navbar title goes home: it clicks the hidden Home tab link, so the
  // switch is the same tab change (and address-bar update) as any other.
  document.addEventListener('click', event => {
    const brand = event.target.closest('.cedar-brand-home');
    if (!brand) return;
    const home = document.querySelector('#main_navbar a[data-value="Home"]');
    if (!home) return;
    event.preventDefault();
    home.click();
  });
})();
