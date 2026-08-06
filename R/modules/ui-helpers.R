# Shared UI helper functions available to all Shiny modules.
# Sourced by load-funcs.R before any module files.

# Sentinel value for the "all follow-on courses in this department" option in
# the Sequence Effect / Downstream Success course pickers. A reserved string
# rather than a real course code so it can never collide with one.
CR_ROLLUP_SENTINEL <- "__cedar_dept_rollup__"


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

CEDAR_DOCS_BASE_URL <- "https://cedarplatform.org"

cedar_docs_url <- function(path) {
  if (is.null(path)) path <- ""
  path <- sub("^/+", "", path)
  paste0(CEDAR_DOCS_BASE_URL, "/", path)
}

cedar_docs_link <- function(path, label = "Full methodology \u2192") {
  htmltools::tags$a(label, href = cedar_docs_url(path), target = "_blank", rel = "noopener")
}

# Standard informational modal. Use for explanations, warnings, and read-only
# detail views that can be dismissed without taking an app action.
cedar_info_modal <- function(title, ..., size = "m", close_label = "Close",
                             easyClose = TRUE) {
  modalDialog(
    title = title,
    ...,
    size = size,
    easyClose = easyClose,
    footer = modalButton(close_label)
  )
}

# Standard confirmation modal. Use for destructive or expensive actions where
# clicking outside the modal should not be treated as an intentional choice.
cedar_confirm_modal <- function(title, ..., confirm_button,
                                cancel_label = "Cancel", easyClose = FALSE) {
  modalDialog(
    title = title,
    ...,
    easyClose = easyClose,
    footer = tagList(
      modalButton(cancel_label),
      confirm_button
    )
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

# Title for a SUBTAB (a nav_panel/tabPanel inside a tab), plus one line saying
# what the subtab shows. Sits above any dashboard_section()s.
#
# This is a distinct level from dashboard_section_header(): a subtab title is
# near-black plain type, larger but visually lighter than the filled green
# section bars beneath it, so hierarchy reads as size-then-fill. Before this
# existed, every subtab opened with a section bar, which made the subtab's own
# title indistinguishable from a divider inside it.
#
# Usage: subtab_header("Rollcall", "Who takes this course, by classification and major.")
subtab_header <- function(title, description = NULL, ..., class = NULL) {
  description_parts <- Filter(Negate(is.null), c(list(description), list(...)))
  description_tag <- NULL
  if (length(description_parts) > 0) {
    description <- if (length(description_parts) == 1) {
      description_parts[[1]]
    } else if (all(vapply(description_parts, is.character, logical(1)))) {
      paste0(unlist(description_parts), collapse = "")
    } else {
      do.call(tagList, description_parts)
    }
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      tags$div(class = "cedar-subtab-description", description)
    } else {
      tags$p(class = "cedar-subtab-description", description)
    }
  }

  div(
    class = paste(c("cedar-subtab-header", class), collapse = " "),
    tags$h2(class = "cedar-subtab-title", title),
    description_tag
  )
}

# Dashboard sections need a stronger hierarchy than regular tab sections:
# a broad group heading, optional short copy, then one or more compact panels.
dashboard_section_header <- function(title, description = NULL, ..., class = NULL) {
  description_parts <- Filter(Negate(is.null), c(list(description), list(...)))
  description_tag <- NULL
  if (length(description_parts) > 0) {
    description <- if (length(description_parts) == 1) {
      description_parts[[1]]
    } else if (all(vapply(description_parts, is.character, logical(1)))) {
      paste0(unlist(description_parts), collapse = "")
    } else {
      do.call(tagList, description_parts)
    }

    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      tags$div(class = "cedar-dashboard-section-description", description)
    } else {
      tags$p(class = "cedar-dashboard-section-description", description)
    }
  }

  div(
    class = paste(c("cedar-dashboard-section-header", class), collapse = " "),
    tags$h2(class = "cedar-dashboard-section-title", title),
    description_tag
  )
}

dashboard_section <- function(title, description = NULL, ..., class = NULL) {
  div(
    class = paste(c("cedar-dashboard-section", class), collapse = " "),
    dashboard_section_header(title, description),
    div(class = "cedar-dashboard-section-body", ...)
  )
}

dashboard_subsection <- function(title, description = NULL, ..., class = NULL,
                                 tone = NULL) {
  description_tag <- NULL
  if (!is.null(description)) {
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      description
    } else {
      tags$p(class = "cedar-dashboard-subsection-description", description)
    }
  }

  div(
    class = paste(c("cedar-dashboard-subsection", class), collapse = " "),
    tags$h3(class = paste(c("cedar-dashboard-subsection-title", tone), collapse = " "), title),
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
                              term_input = NULL, actions = NULL, scope_output = NULL) {
  # When a term picker is present the dept column narrows to make room for it,
  # so campus/term/dept/actions still fit one row. Callers without a term input
  # (e.g. Dept Trends) keep the original two-column widths unchanged.
  dept_width <- if (is.null(term_input)) 4 else 3
  actions_width <- if (is.null(term_input)) 3 else 2
  filter_bar(
    title,
    subtitle,
    fluidRow(
      column(3, campus_input),
      if (!is.null(term_input)) column(2, term_input),
      column(dept_width, dept_input),
      if (!is.null(actions)) column(actions_width, actions)
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
    background    = "#706858", # trunk-bark — matches --trunk-bark in cedar-custom.css
    color         = "#f5eedf",
    fontWeight    = "600",
    fontSize      = "0.73rem",
    textTransform = "uppercase",
    letterSpacing = "0.05em",
    borderBottom  = "2px solid #8C8474" # matches --trunk-bark-border
  ),
  paginationStyle = list(fontSize = "0.82rem")
)

# Standardized "Part of Term" (PoT) column for cedar tables. Reuse this everywhere a
# ── Sparkline / trend cell renderers ─────────────────────────────────────────
# Inline SVG history sparkline and the trend-cell HTML that wraps it. Shared by
# the regstats bumps/dips/drops/saturation tables and the waitlists course
# overview so a course's current value reads against its own history the same way
# everywhere. Pure (htmltools + base R only), so they render outside a Shiny
# reactive as well.

# Inline sparkline of `values` (a numeric history, ordered oldest→newest). The
# term being viewed can be marked with a dot via current_idx. Returns an empty
# span when there is too little variation to plot.
make_sparkline <- function(values, current_idx = NULL, width = 80, height = 20,
                           col = "#8BAF99", cur_col = "#3F5E4B") {
  vals <- suppressWarnings(as.numeric(values))
  vals <- vals[!is.na(vals)]
  if (length(vals) < 2) return(htmltools::span())
  n    <- length(vals)
  vmin <- min(vals); vmax <- max(vals)
  if (vmax == vmin) return(htmltools::span())
  pad <- 2
  xs  <- round((seq_len(n) - 1) / (n - 1) * (width - pad * 2) + pad, 1)
  ys  <- round((1 - (vals - vmin) / (vmax - vmin)) * (height - pad * 2) + pad, 1)
  pts <- paste(xs, ys, sep = ",", collapse = " ")
  dot <- if (!is.null(current_idx) && current_idx >= 1 && current_idx <= n)
    paste0('<circle cx="', xs[current_idx], '" cy="', ys[current_idx],
           '" r="2.5" fill="', cur_col, '"/>')
  else ""
  htmltools::HTML(paste0(
    '<svg width="', width, '" height="', height,
    '" style="display:inline-block;vertical-align:middle;margin-left:4px;">',
    '<polyline points="', pts, '" fill="none" stroke="', col,
    '" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>',
    dot, '</svg>'
  ))
}

# Linear (scaled) units-per-term slope; NA when fewer than 3 points.
# Wraps the canonical compute_trend() (R/trunk/utils.R) with this cell's display
# conventions: a scale factor (points vs. rate metrics), a 3-point minimum, and
# rounding to one decimal.
trend_slope <- function(v, scale = 1) {
  round(unname(compute_trend(v * scale, min_n = 3)$slope), 1)
}
fmt_slope <- function(s, unit) if (is.na(s)) "n/a" else
  paste0(if (s >= 0) "+" else "", formatC(s, format = "f", digits = 1), unit)

# Renders a metric's same-term-type history as a sparkline with the viewed term dotted,
# a ▲/▼ chip for the trend *heading into* that term, and a tooltip carrying the full-arc
# trend and historic average. pct = TRUE for rate metrics (fill rate 0–1, shown as
# points/term); FALSE for counts (enrollment, drops — shown as units/term).
trend_cell_html <- function(series, terms, cur_term, pct = FALSE) {
  if (is.null(series) || length(series) < 2) return("")
  cur   <- match(cur_term, terms)
  scale <- if (pct) 100 else 1
  unit  <- if (pct) " pts/term" else "/term"
  todot <- if (!is.na(cur)) trend_slope(series[seq_len(cur)], scale) else NA_real_
  arc   <- trend_slope(series, scale)
  avg_v <- if (!is.na(cur) && cur > 1) mean(series[-cur], na.rm = TRUE) else mean(series, na.rm = TRUE)
  avg_t <- if (pct) paste0(round(avg_v * 100), "%") else formatC(avg_v, format = "f", digits = 1)
  spark <- as.character(make_sparkline(series, cur, width = 66, height = 18, cur_col = "#A15D4E"))
  tip   <- paste0("Trend into ", cur_term, ": ", fmt_slope(todot, unit),
                  " · full-arc: ", fmt_slope(arc, unit),
                  " · historic avg ", avg_t, " over ", length(series), " terms")
  chip  <- if (!is.na(todot) && abs(todot) >= 1) {
    up <- todot > 0
    sprintf('<span style="font-size:0.72rem;font-weight:600;margin-left:3px;color:%s">%s%s</span>',
            if (up) "#A15D4E" else "#6F8B78", if (up) "▲" else "▼",
            formatC(abs(todot), format = "f", digits = 1))
  } else ""
  sprintf('<div title="%s" style="display:flex;align-items:center;gap:2px">%s%s</div>',
          htmltools::htmlEscape(tip, attribute = TRUE), spark, chip)
}

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
  # Defaults are embedded for the first paint. The browser requests current
  # timing-history estimates from the server whenever the overlay opens, so an
  # Admin reset takes effect immediately without an application restart.
  fresh_sec <- fresh_default
  cached_sec <- cached_default
  expected_js <- if (is.null(fresh_sec))  "null" else as.integer(fresh_sec)
  cached_js   <- if (is.null(cached_sec)) "null" else as.integer(cached_sec)
  report_js   <- if (is.null(report_type)) "" else report_type
  fresh_default_js <- if (is.null(fresh_default))  "null" else as.integer(fresh_default)
  cached_default_js <- if (is.null(cached_default)) "null" else as.integer(cached_default)
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
  var PREFIX = "%s", RUNBTN = "%s", TRIGGER = "%s", HIDE_EMPTY = %s;
  var REPORT_TYPE = "%s", FRESH_DEFAULT = %s, CACHED_DEFAULT = %s;
  var EXPECTED = %s, CACHED = %s;
  var hideTimer = null, finalizeTimer = null;
  var measurementActive = false, runStartedAt = null, completionMsg = null;
  var payloadBytes = 0, outputNames = {};
  function el(suffix) { return document.getElementById(PREFIX + suffix); }

  // Track only output values belonging to this overlay. This approximates the
  // JSON payload Shiny delivers; it deliberately excludes query contents and
  // is not presented as an exact websocket byte count.
  $(document).on("shiny:value", function(e) {
    if (!measurementActive || !REPORT_TYPE || !e.name) return;
    var output = document.getElementById(e.name);
    var box = el("-loading-overlay");
    var anchor = box && box.closest ? box.closest(".loader-anchor") : null;
    if (!output || !anchor || !anchor.contains(output)) return;
    try {
      var encoded = JSON.stringify(e.value);
      if (encoded !== undefined) {
        payloadBytes += window.TextEncoder
          ? new TextEncoder().encode(encoded).length
          : new Blob([encoded]).size;
      }
    } catch (ignore) {}
    outputNames[e.name] = true;
  });

  // Shiny idle means its output queue has been processed. Two paint frames and
  // a short settle period include the browser work that follows value delivery.
  $(document).on("shiny:idle", function() { scheduleFinalize(); });

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

  Shiny.addCustomMessageHandler(PREFIX + "_load_start", function(msg) { showOverlay(); });
  Shiny.addCustomMessageHandler(PREFIX + "_load_complete", function(msg) { completeOverlay(msg || {}); });
  Shiny.addCustomMessageHandler(PREFIX + "_timing_estimates", function(msg) {
    EXPECTED = msg && msg.fresh !== null && msg.fresh !== undefined ? msg.fresh : FRESH_DEFAULT;
    CACHED = msg && msg.cached !== null && msg.cached !== undefined ? msg.cached : CACHED_DEFAULT;
    var box = el("-loading-overlay");
    if (box && box.style.display !== "none") el("-loading-label").textContent = loadingLabel();
  });

  function loadingLabel() {
    if (EXPECTED && CACHED) return "Loading… (~" + CACHED + "s if cached, ~" + EXPECTED + "s if not)";
    if (EXPECTED) return "Loading… (est. " + EXPECTED + "s)";
    return "Loading…";
  }

  function showOverlay() {
    clearTimeout(hideTimer);
    clearTimeout(finalizeTimer);
    if (!measurementActive && REPORT_TYPE) {
      measurementActive = true;
      runStartedAt = performance.now();
      completionMsg = null;
      payloadBytes = 0;
      outputNames = {};
    }
    if (REPORT_TYPE && window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("cedar_timing_estimate_request", {
        prefix: PREFIX,
        report_type: REPORT_TYPE,
        fresh_default: FRESH_DEFAULT,
        cached_default: CACHED_DEFAULT,
        nonce: Date.now()
      }, {priority: "event"});
    }
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
    if (msg.error) {
      stopMeasurement();
      fadeOut(0);
      return;
    }
    completionMsg = msg;
    // Start a paint-based settle immediately. If Shiny still has output work,
    // its subsequent idle event calls scheduleFinalize() again and extends the
    // measurement from that later boundary.
    scheduleFinalize();
    // Defensive fallback for a disconnected or older Shiny client that never
    // emits an idle event after the custom completion message.
    finalizeTimer = setTimeout(finalizeMeasurement, 5000);
  }

  function scheduleFinalize() {
    if (!measurementActive || !completionMsg) return;
    clearTimeout(finalizeTimer);
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        finalizeTimer = setTimeout(finalizeMeasurement, 100);
      });
    });
  }

  function finalizeMeasurement() {
    if (!measurementActive || !completionMsg || runStartedAt === null) return;
    clearTimeout(finalizeTimer);
    var totalSec = Math.max((performance.now() - runStartedAt) / 1000, 0);
    var computeSec = Number(completionMsg.duration_sec);
    if (!isFinite(computeSec) || computeSec < 0) computeSec = null;
    var postComputeSec = computeSec === null ? null : Math.max(totalSec - computeSec, 0);

    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("cedar_client_render_timing", {
        report_type: REPORT_TYPE,
        overlay_id: PREFIX,
        compute_sec: computeSec,
        total_sec: Math.round(totalSec * 1000) / 1000,
        post_compute_sec: postComputeSec === null ? null : Math.round(postComputeSec * 1000) / 1000,
        payload_bytes: payloadBytes,
        output_count: Object.keys(outputNames).length,
        cached: completionMsg.cached === true ? true : completionMsg.cached === false ? false : null,
        viewport_width: window.innerWidth,
        viewport_height: window.innerHeight,
        nonce: Date.now()
      }, {priority: "event"});
    }

    var verb = completionMsg.cached === true ? "Loaded from cache"
             : completionMsg.cached === false ? "Generated"
             : "Loaded";
    var txt = verb + " — ready in " + totalSec.toFixed(1) + "s";
    if (computeSec !== null) txt += " (" + computeSec + "s calculation)";
    el("-timing-msg").textContent = txt;
    stopMeasurement();
    fadeOut(800);
  }

  function stopMeasurement() {
    clearTimeout(finalizeTimer);
    measurementActive = false;
    runStartedAt = null;
    completionMsg = null;
  }

  function hideOverlay() {
    clearTimeout(hideTimer);
    stopMeasurement();
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
      id, runbtn_js, trigger_js, hide_js, report_js,
      fresh_default_js, cached_default_js, expected_js, cached_js
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
signal_load_start <- function(session, id) {
  session$sendCustomMessage(paste0(id, "_load_start"), list())
}

signal_load_complete <- function(session, id, duration_sec = NULL,
                                 cached = NULL, error = FALSE) {
  session$sendCustomMessage(paste0(id, "_load_complete"), list(
    duration_sec = if (!is.null(duration_sec)) round(duration_sec, 1) else NULL,
    cached       = if (is.null(cached)) NULL else isTRUE(cached),
    error        = isTRUE(error)
  ))
}
