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
})();
