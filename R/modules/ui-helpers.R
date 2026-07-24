# Shared UI helper functions available to all Shiny modules.
# Sourced by load-funcs.R before any module files.

# Collapsible info panel for column guides, methodology notes, and detail tables.
# Usage: info_panel("Title", p("..."), tags$ul(tags$li(...)))
info_panel <- function(title, ..., description = NULL, class = NULL) {
  classes <- paste(c("cedar-info-panel", class), collapse = " ")
  tags$details(
    class = classes,
    tags$summary(
      tags$span(
        class = "cedar-info-summary-copy",
        tags$span(class = "cedar-info-summary-title", title),
        if (!is.null(description)) {
          tags$span(class = "cedar-info-summary-description", description)
        }
      )
    ),
    tags$div(class = "panel-body", ...)
  )
}

# Standard empty-state prompt shown before a user action (button click, selection).
# msg: instruction text shown to the user.
empty_state <- function(msg = "Set filters and click the button to load data.") {
  div(
    class = "empty-state",
    tags$p(msg)
  )
}

# Standard in-flow section heading for tab bodies. Replaces the ad-hoc
# h5(..., class = "text-secondary mb-1") pattern so spacing/size are uniform.
# level = "h6" renders the smaller subsection variant.
# Usage: section_heading("DFW Rates by Course")  /  section_heading("Changes by Term", level = "h6")
section_heading <- function(title, ..., level = "h5", class = NULL) {
  tag <- match.fun(level)
  base <- if (identical(level, "h6")) "cedar-section-heading--sub" else "cedar-section-heading"
  tag(class = paste(c(base, class), collapse = " "), title, ...)
}

# Shared heading + explanatory copy + body block.
# Use this when a section has a heading followed by a short description so the
# heading/paragraph/table spacing is consistent across modules.
section_block <- function(title, description = NULL, ..., level = "h5", class = NULL) {
  classes <- paste(c("cedar-section-block", class), collapse = " ")
  description_tag <- NULL
  if (!is.null(description)) {
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      description
    } else {
      tags$p(class = "text-hint", description)
    }
  }

  div(
    class = classes,
    section_heading(title, level = level),
    description_tag,
    ...
  )
}

# Primary explanatory paragraph ("what this tab/section does"). rem-based so it
# escapes the global body 0.9em shrink. Use for the lead copy under a heading.
lead_text <- function(...) tags$p(class = "cedar-lead", ...)

# Standard top filter band used by Cedar tabs and modules.
filter_bar <- function(title, subtitle = NULL, ..., class = NULL) {
  classes <- paste(c("filters-compact", class), collapse = " ")
  div(
    class = classes,
    h1(title),
    if (!is.null(subtitle)) tags$p(subtitle, class = "filter-subtitle"),
    ...
  )
}

# Aligns run/download/copy buttons with compact filter inputs.
filter_actions <- function(..., class = NULL) {
  classes <- paste(c("filter-actions", class), collapse = " ")
  div(class = classes, ...)
}

# Light green scope strip shown at the bottom of a filter bar.
filter_scope_stripe <- function(...) {
  div(class = "filter-scope-strip", ...)
}

# Shared campus + single-department selector formulation for department tabs.
dept_selector_bar <- function(title, subtitle, campus_input, dept_input,
                              actions = NULL, scope_output = NULL) {
  filter_bar(
    title,
    subtitle,
    fluidRow(
      column(3, campus_input),
      column(4, dept_input),
      if (!is.null(actions)) column(3, actions)
    ),
    scope_output
  )
}

# Shared reactable theme — used by all cedar tables for consistent styling.
cedar_tbl_theme <- reactable::reactableTheme(
  color           = "#232826",
  backgroundColor = "#ffffff",
  borderColor     = "#d4c5b0",
  stripedColor    = "#faf5ee",
  highlightColor  = "#f0e8d8",
  cellPadding     = "5px 10px",
  style           = list(fontSize = "0.87rem"),
  headerStyle     = list(
    background    = "#6B4A2A",
    color         = "#f5eedf",
    fontWeight    = "600",
    fontSize      = "0.73rem",
    textTransform = "uppercase",
    letterSpacing = "0.05em",
    borderBottom  = "2px solid #8B6240"
  ),
  paginationStyle = list(fontSize = "0.82rem")
)

# Standardized "Part of Term" (PoT) column for cedar tables. Reuse this everywhere a
# table shows part_term so the label and cell treatment stay identical across tabs.
#   - Full-term ("1") is the common case, dimmed to "Full".
#   - Missing/blank shows an em dash.
#   - Half-term / nonstandard variants (1H, 2H, INT, …) stand out in semibold, because
#     they are analyzed as distinct offerings rather than folded into the course.
# The header opts out of the theme's uppercase transform so it reads "PoT" (lowercase
# o), not "POT".
cedar_pot_coldef <- function(name = "PoT", maxWidth = 52, align = "center") {
  reactable::colDef(
    name        = name,
    maxWidth    = maxWidth,
    align       = align,
    headerStyle = list(textTransform = "none"),
    cell = function(v) {
      if (is.na(v) || v == "" || v == "1")
        htmltools::span(class = "text-sub", if (is.na(v) || v == "") "—" else "Full")
      else htmltools::span(class = "fw-semibold", v)
    }
  )
}

# ── Shared loading overlay ───────────────────────────────────────────────────
# Data-heavy tabs show the standard dash-loader spinner box while a report runs.
# cedar_loading_overlay() renders that box plus the JS that shows it the instant
# the run button is pressed and hides it when the server calls
# signal_load_complete(). Both sides share one contract: the message channel is
# paste0(id, "_load_complete") and the DOM ids are prefixed with `id`, so the UI
# `id` MUST equal the module id the server runs under.
#
#   id           module id — also the overlay id prefix and the message channel.
#   run_button   run button's id relative to the module (e.g. "cn_button"); the
#                overlay shows on a capture-phase click of "#<id>-<run_button>",
#                which also catches the programmatic btn.click() from URL autorun.
#   trigger_input  alternative to run_button for non-module tabs (dashboard,
#                  enrollment): a Shiny input name watched via shiny:inputchanged.
#                  The overlay shows when that input changes — use it when the run
#                  signal is a select or actionButton whose DOM id is not
#                  namespaced as "<id>-<run_button>". Supply exactly one of
#                  run_button / trigger_input.
#   hide_on_empty  with trigger_input, also hide the overlay when the watched
#                  input clears to empty (e.g. deselecting a dashboard department).
#   ...            the tab body placed under the overlay (typically a uiOutput()).
#   emoji          glyph shown over the spinner (defaults to the cedar tree).
#   report_type    optional timing-log key; when given, fresh/cached estimates are
#                  looked up (see report_time_estimates) and shown in the label.
#   fresh_default  fallback fresh estimate (seconds) until the log has fresh runs.
#   cached_default fallback cache-hit estimate; leave NULL for tabs that never
#                  cache so the label stays a single "(est. Ns)".
#
# Labels: with both a fresh and cached estimate the run is bimodal, so the label
# reads "Loading… (~Cs if cached, ~Fs if not)"; with only fresh it reads
# "Loading… (est. Fs)"; with neither, plain "Loading…". On completion the server
# passes `cached` (see signal_load_complete) so the timing line names which path
# ran: "Loaded from cache in Ns" / "Generated in Ns" / "Loaded in Ns".
cedar_loading_overlay <- function(id, run_button = NULL, ..., emoji = "\U0001f332",
                                  trigger_input = NULL, hide_on_empty = FALSE,
                                  report_type = NULL, fresh_default = NULL,
                                  cached_default = NULL) {
  if (is.null(run_button) && is.null(trigger_input)) {
    stop("cedar_loading_overlay(): supply run_button (click trigger) or trigger_input (input-change trigger).")
  }
  fresh_sec <- fresh_default
  cached_sec <- cached_default
  if (!is.null(report_type)) {
    est <- report_time_estimates(report_type, fresh_default, cached_default)
    fresh_sec  <- est$fresh
    cached_sec <- est$cached
  }
  expected_js <- if (is.null(fresh_sec))  "null" else as.integer(fresh_sec)
  cached_js   <- if (is.null(cached_sec)) "null" else as.integer(cached_sec)
  runbtn_js   <- if (is.null(run_button))    "" else run_button
  trigger_js  <- if (is.null(trigger_input)) "" else trigger_input
  hide_js     <- if (isTRUE(hide_on_empty))  "true" else "false"
  div(
    class = "loader-anchor",
    div(
      id = paste0(id, "-loading-overlay"),
      class = "dash-loader-overlay",
      style = "display: none;",
      div(class = "dash-loader-backdrop"),
      div(class = "dash-loader-box",
        div(class = "dash-loader-icon",
          div(class = "dash-spinner"),
          tags$span(emoji, class = "dash-tree-icon")
        ),
        div(id = paste0(id, "-loading-label"), class = "dash-loader-msg", "Loading…"),
        div(id = paste0(id, "-timing-msg"),    class = "dash-timing-msg")
      )
    ),
    tags$script(HTML(sprintf(
'(function() {
  var PREFIX = "%s", RUNBTN = "%s", TRIGGER = "%s", HIDE_EMPTY = %s, EXPECTED = %s, CACHED = %s;
  var hideTimer = null;
  function el(suffix) { return document.getElementById(PREFIX + suffix); }

  if (TRIGGER) {
    // Input-change trigger for non-module tabs whose run signal is a select or
    // actionButton input (no namespaced run button to click).
    $(document).on("shiny:inputchanged", function(e) {
      if (e.name !== TRIGGER) return;
      if (HIDE_EMPTY) {
        if (e.value !== null && e.value !== undefined && e.value !== "") showOverlay();
        else hideOverlay();
      } else {
        showOverlay();
      }
    });
  } else {
    // Capture-phase click so it fires for real clicks AND the programmatic
    // btn.click() dispatched by URL autorun / cross-tab navigation.
    document.addEventListener("click", function(e) {
      if (e.target && e.target.closest && e.target.closest("#" + PREFIX + "-" + RUNBTN)) showOverlay();
    }, true);
  }

  Shiny.addCustomMessageHandler(PREFIX + "_load_complete", function(msg) { completeOverlay(msg || {}); });

  function loadingLabel() {
    if (EXPECTED && CACHED) return "Loading… (~" + CACHED + "s if cached, ~" + EXPECTED + "s if not)";
    if (EXPECTED) return "Loading… (est. " + EXPECTED + "s)";
    return "Loading…";
  }

  function showOverlay() {
    clearTimeout(hideTimer);
    var box = el("-loading-overlay");
    if (!box) return;
    el("-loading-label").textContent = loadingLabel();
    el("-timing-msg").textContent = "";
    box.style.opacity = "0";
    box.style.display = "flex";
    box.style.transition = "opacity 0.2s ease";
    box.offsetWidth;
    box.style.opacity = "1";
  }

  function completeOverlay(msg) {
    var box = el("-loading-overlay");
    if (!box || box.style.display === "none") return;
    if (msg.error) { fadeOut(0); return; }
    var verb = msg.cached === true ? "Loaded from cache in "
             : msg.cached === false ? "Generated in "
             : "Loaded in ";
    var txt = "";
    if (msg.duration_sec !== null && msg.duration_sec !== undefined) txt = verb + msg.duration_sec + "s";
    el("-timing-msg").textContent = txt;
    fadeOut(800);
  }

  function hideOverlay() {
    clearTimeout(hideTimer);
    var box = el("-loading-overlay");
    if (!box) return;
    box.style.transition = "";
    box.style.opacity = "1";
    box.style.display = "none";
  }

  function fadeOut(delay) {
    var box = el("-loading-overlay");
    hideTimer = setTimeout(function() {
      box.style.transition = "opacity 0.4s ease";
      box.style.opacity = "0";
      setTimeout(function() {
        box.style.display = "none";
        box.style.transition = "";
        box.style.opacity = "1";
      }, 400);
    }, delay);
  }
})();',
      id, runbtn_js, trigger_js, hide_js, expected_js, cached_js
    ))),
    ...
  )
}

# Server companion to cedar_loading_overlay(): hides the overlay for module `id`
# by sending the "<id>_load_complete" message its script listens for.
#   error  = TRUE dismisses with no timing readout.
#   cached = TRUE  → "Loaded from cache in Ns"; FALSE → "Generated in Ns";
#            NULL (default, non-caching tabs) → "Loaded in Ns".
# Rounding is handled here.
signal_load_complete <- function(session, id, duration_sec = NULL,
                                 cached = NULL, error = FALSE) {
  session$sendCustomMessage(paste0(id, "_load_complete"), list(
    duration_sec = if (!is.null(duration_sec)) round(duration_sec, 1) else NULL,
    cached       = if (is.null(cached)) NULL else isTRUE(cached),
    error        = isTRUE(error)
  ))
}
