// "How this is counted" as a dialog.
//
// cedar_method_panel() (R/modules/ui-helpers.R) leaves each section's method
// text in the page as a <details class="cedar-method-panel">; the stylesheet
// draws its summary as a small link and, open, lifts its body into a centred
// box over a backdrop. This file gives that box a dialog's manners: one open
// at a time, focus on open, and Close, Escape or a click on the backdrop to
// dismiss, with focus back on the link.
(function () {
  var SELECTOR = 'details.cedar-method-panel';

  function close(panel) {
    if (!panel || !panel.open) return;
    panel.open = false;
    var link = panel.querySelector('summary');
    if (link) link.focus();
  }

  document.addEventListener('toggle', function (event) {
    var panel = event.target;
    if (!panel.matches || !panel.matches(SELECTOR) || !panel.open) return;
    document.querySelectorAll(SELECTOR + '[open]').forEach(function (other) {
      if (other !== panel) other.open = false;
    });
    var body = panel.querySelector('.panel-body');
    if (body) body.focus();
    // An output Shiny had treated as hidden is drawn now.
    if (window.jQuery) window.jQuery(panel).trigger('shown');
  }, true);

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (target.closest && target.closest('.cedar-method-close')) {
      close(target.closest(SELECTOR));
      return;
    }
    // The backdrop is the panel's own pseudo-element: a click on it lands on
    // the <details> itself, not on its link or its box.
    if (target.matches && target.matches(SELECTOR + '[open]')) close(target);
  });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    document.querySelectorAll(SELECTOR + '[open]').forEach(close);
  });
})();
