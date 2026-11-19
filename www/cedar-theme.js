// Light and dark mode.
//
// The mode is html[data-bs-theme]: the reader's choice, remembered in this
// browser, or until they choose, the system setting (and it follows a change
// to the system setting until then). Loaded first in <head>, so the page
// paints in its mode. Every CSS colour is a token (www/cedar-custom.css);
// plotly figures carry their colours in their layout, so each one is
// re-coloured from the --chart-* tokens when it draws and when the mode
// changes.
(function () {
  var KEY = 'cedar-theme';
  var root = document.documentElement;
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  function stored() {
    try { var v = window.localStorage.getItem(KEY); return v === 'dark' || v === 'light' ? v : null; }
    catch (e) { return null; }
  }
  function system() { return media && media.matches ? 'dark' : 'light'; }
  function mode() { return root.getAttribute('data-bs-theme') === 'dark' ? 'dark' : 'light'; }

  function set(m) {
    root.setAttribute('data-bs-theme', m);
    var b = document.querySelector('.cedar-theme-toggle');
    if (b) {
      var label = m === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';
      b.setAttribute('aria-label', label);
      b.setAttribute('title', label);
      b.setAttribute('aria-pressed', m === 'dark' ? 'true' : 'false');
    }
    themeAllPlots();
  }

  set(stored() || system());
  if (media && media.addEventListener) {
    media.addEventListener('change', function () { if (!stored()) set(system()); });
  }

  // ── Plotly figures ────────────────────────────────────────────────────────
  function token(name) { return getComputedStyle(root).getPropertyValue(name).trim(); }
  function isDarkColor(c) {
    if (!c || typeof c !== 'string') return true;
    var m = c.match(/^#([0-9a-f]{6})$/i);
    if (!m) return false;
    var n = parseInt(m[1], 16), r = n >> 16, g = (n >> 8) & 255, bl = n & 255;
    return (0.2126 * r + 0.7152 * g + 0.0722 * bl) / 255 < 0.35;
  }

  // The figure's own colours are kept the first time it is themed, so light
  // mode restores exactly what the server drew.
  function themePlot(gd) {
    if (!window.Plotly || !gd || !gd.layout || !gd._fullLayout) return;
    var m = mode();
    if (gd._cedarMode === m) return;
    var L = gd.layout;
    if (!gd._cedarOrig) {
      var orig = { paper_bgcolor: L.paper_bgcolor, plot_bgcolor: L.plot_bgcolor,
                   font: L.font && L.font.color, legend: L.legend && L.legend.bgcolor, axes: {}, ann: [] };
      Object.keys(L).forEach(function (k) {
        if (/^[xy]axis\d*$/.test(k)) orig.axes[k] = { grid: L[k].gridcolor, zero: L[k].zerolinecolor, line: L[k].linecolor };
      });
      (L.annotations || []).forEach(function (a) { orig.ann.push(a.font && a.font.color); });
      gd._cedarOrig = orig;
    }
    var o = gd._cedarOrig, dark = m === 'dark', u = {};
    u.paper_bgcolor = dark ? 'rgba(0,0,0,0)' : (o.paper_bgcolor === undefined ? null : o.paper_bgcolor);
    u.plot_bgcolor = dark ? 'rgba(0,0,0,0)' : (o.plot_bgcolor === undefined ? null : o.plot_bgcolor);
    u['font.color'] = dark ? token('--chart-text') : (o.font === undefined ? null : o.font);
    u['legend.bgcolor'] = dark ? 'rgba(0,0,0,0)' : (o.legend === undefined ? null : o.legend);
    Object.keys(o.axes).forEach(function (k) {
      var a = o.axes[k];
      u[k + '.gridcolor'] = dark ? token('--chart-grid') : (a.grid === undefined ? null : a.grid);
      u[k + '.zerolinecolor'] = dark ? token('--chart-line') : (a.zero === undefined ? null : a.zero);
      u[k + '.linecolor'] = dark ? token('--chart-line') : (a.line === undefined ? null : a.line);
    });
    // An annotation coloured dark for a light page reads in the dark too;
    // one given a deliberate light or brand colour keeps it.
    o.ann.forEach(function (c, i) {
      if (dark && isDarkColor(c)) u['annotations[' + i + '].font.color'] = token('--chart-text');
      else if (!dark) u['annotations[' + i + '].font.color'] = c === undefined ? null : c;
    });
    gd._cedarMode = m;
    window.Plotly.relayout(gd, u);
  }
  function themeAllPlots() {
    if (!document.querySelectorAll) return;
    var plots = document.querySelectorAll('.js-plotly-plot');
    for (var i = 0; i < plots.length; i++) themePlot(plots[i]);
  }
  window.cedarThemePlots = themeAllPlots;

  document.addEventListener('DOMContentLoaded', function () {
    set(mode());
    document.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('.cedar-theme-toggle');
      if (!b) return;
      e.preventDefault();
      var next = mode() === 'dark' ? 'light' : 'dark';
      try { window.localStorage.setItem(KEY, next); } catch (err) { /* private window: this page only */ }
      set(next);
    });
    // A figure drawn by the server arrives in light colours: theme it once
    // drawn. Re-renders replace the element, so each new one is themed.
    if (window.jQuery) {
      window.jQuery(document).on('shiny:value', function (e) {
        // A re-render redraws into the same element: forget its theming.
        var el = e.target, figs = el && el.querySelectorAll ? el.querySelectorAll('.js-plotly-plot') : [];
        var all = el && el.classList && el.classList.contains('js-plotly-plot') ? [el] : [];
        for (var i = 0; i < figs.length; i++) all.push(figs[i]);
        all.forEach(function (gd) { delete gd._cedarMode; delete gd._cedarOrig; });
        setTimeout(themeAllPlots, 60);
        setTimeout(themeAllPlots, 600);
      });
      window.jQuery(document).on('shown.bs.tab', function () { setTimeout(themeAllPlots, 60); });
    }
  });
})();
