# Shareable-URL round-trip: one registry + helpers that BOTH build copy-links and
# restore them, so the two directions can never drift. Replaces the former
# hand-maintained tab_prefixes / button_overrides maps that lived in server.R
# (whose drift is exactly what silently broke the Waitlists deep link).
#
# Each CEDAR_SHARE_SPECS entry is keyed by the exact navbar tab title and
# describes that tab's deep-link contract:
#   slug    — the ?tab= value (must also exist in ui.R's tabMap and the
#             tab_aliases map in server.R so the tab actually switches).
#   prefix  — fully-namespaced input prefix. An input's id is paste0(prefix, sep, key).
#             Short-prefixed modules use e.g. "waitlist-wl"; a module whose inputs
#             are bare under its namespace (headcount) uses just "headcount".
#   sep     — separator between prefix and key: "_" for short-prefixed modules,
#             "-" for bare-under-namespace modules.
#   run     — input id (relative to prefix) of the button clicked on autorun.
#             Defaults to "button"; Regstats runs "dashboard_button".
#   types   — named list of per-key RESTORE overrides, for exceptions only. Keys
#             not listed default to a client-side select/selectize input.
#             Recognized types:
#               "select"        (default) client selectize/selectInput
#               "select_server" server-side selectize — restored via the
#                               selectize_set_value custom message (the value
#                               isn't in the client-loaded option set yet)
#               "numeric"       numericInput
#               "checkbox"      checkboxInput
#               "slider"        sliderInput
#               "radio"         radioButtons
#               "text"          textInput
#   aliases — optional named list mapping a legacy URL param name to its input key
#             (e.g. headcount's short "conc" -> "concentration").
#
# Tabs that support deep-link RESTORE but have no copy button (Dept Dashboard,
# Gen Ed, Dept Trends) are listed too, so a hand-crafted URL
# keeps working exactly as before.

CEDAR_SHARE_SPECS <- list(
  "Open Seats" = list(
    slug = "open-seats", prefix = "seatfinder-sf", sep = "_", run = "button"
  ),
  "Cancellations" = list(
    slug = "cancellations", prefix = "cancellations-cn", sep = "_", run = "button"
  ),
  "Waitlists" = list(
    slug = "waitlists", prefix = "waitlist-wl", sep = "_", run = "button",
    types = list(course = "select_server")
  ),
  "Headcount" = list(
    slug = "headcount", prefix = "headcount", sep = "-", run = "button",
    # every headcount filter is a server-side selectize
    types = list(campus = "select_server", college = "select_server",
                 dept = "select_server", major = "select_server",
                 minor = "select_server", concentration = "select_server"),
    aliases = list(conc = "concentration")
  ),
  "Regstats" = list(
    slug = "registration", prefix = "regstats-rs", sep = "_", run = "dashboard_button",
    types = list(min_impacted = "numeric", pct_sd = "numeric",
                 chronic_fill_rate = "numeric", min_wait = "numeric",
                 min_sat_terms = "numeric")
  ),
  "Enrollment" = list(
    slug = "enrollment", prefix = "enrl", sep = "_", run = "button"
  ),

  # Restore-only tabs (no copy button, but reachable via hand-crafted URLs).
  "Dept Dashboard"      = list(slug = "dept-dashboard",     prefix = "dashboard", sep = "_", run = "button"),
  "Course Dynamics"     = list(
    slug = "course-dynamics", prefix = "cr", sep = "_", run = "generate_button",
    types = list(course = "select_server")
  ),
  "Gen Ed"              = list(slug = "gen-ed",             prefix = "gen_ed-ge", sep = "_", run = "button"),
  "Dept Trends"         = list(slug = "dept-trends",        prefix = "dr",        sep = "_", run = "button"),
  "Department Profile"  = list(slug = "department-profile", prefix = "dr",        sep = "_", run = "button")
)

# Build a "tab=<slug>&autorun=true&k=v&..." query string from a named list of
# key -> input value(s). NULL/empty values are dropped, multiple values are
# comma-joined, and every value is URL-encoded (parseQueryString decodes on the
# way back, so this is a no-op for plain codes and safe for names with spaces/&).
cedar_share_query <- function(slug, values, autorun = TRUE) {
  parts <- paste0("tab=", slug)
  if (autorun) parts <- c(parts, "autorun=true")
  for (k in names(values)) {
    v <- values[[k]]
    if (!is.null(v) && length(v) > 0 && any(nzchar(as.character(v)))) {
      parts <- c(parts, paste0(
        k, "=",
        paste(utils::URLencode(as.character(v), reserved = TRUE), collapse = ",")
      ))
    }
  }
  paste(parts, collapse = "&")
}

# Standard copy-URL wiring. Call once in a module (or top-level) server.
#   copy_id    — the copy button's input id (relative to the caller's namespace).
#   values_fn  — function() returning the named list of key -> input value(s).
#   slug       — the ?tab= slug, or a function() computing it (Enrollment varies
#                its slug by active sub-tab). If NULL, taken from spec_title.
#   spec_title — registry key to source the slug from when `slug` is NULL.
#   button_id  — DOM id used for the green-flash feedback; defaults to
#                session$ns(copy_id). Pass explicitly for top-level (non-module)
#                buttons whose id must stay unnamespaced.
cedar_copy_url_observer <- function(input, session, copy_id, values_fn,
                                    slug = NULL, spec_title = NULL, button_id = NULL) {
  if (is.null(slug) && !is.null(spec_title)) slug <- CEDAR_SHARE_SPECS[[spec_title]]$slug
  if (is.null(button_id)) button_id <- session$ns(copy_id)
  observeEvent(input[[copy_id]], {
    this_slug <- if (is.function(slug)) slug() else slug
    session$sendCustomMessage("copy_cedar_url", list(
      queryStr = cedar_share_query(this_slug, values_fn()),
      buttonId = button_id
    ))
  }, ignoreInit = TRUE)
}

# Restore a tab's inputs from parsed URL query params and, if autorun=true, click
# its run button. `tab_name` is the resolved navbar title (from tab_aliases in
# server.R). Tabs with no spec restore nothing, matching the old behavior for
# tabs that weren't in tab_prefixes.
cedar_restore_from_query <- function(session, query, tab_name) {
  spec <- CEDAR_SHARE_SPECS[[tab_name]]
  if (is.null(spec)) return(invisible())

  prefix  <- spec$prefix
  sep     <- spec$sep %||% "_"
  types   <- spec$types %||% list()
  aliases <- spec$aliases %||% list()

  for (param_name in names(query)) {
    if (param_name %in% c("tab", "autorun")) next
    key      <- aliases[[param_name]] %||% param_name
    input_id <- paste0(prefix, sep, key)
    vals     <- unlist(strsplit(query[[param_name]], ","))
    type     <- types[[param_name]] %||% types[[key]] %||% "select"

    switch(type,
      "select_server" = session$sendCustomMessage(
        "selectize_set_value", list(id = input_id, value = vals)
      ),
      "numeric" = {
        num <- suppressWarnings(as.numeric(vals[1]))
        if (!is.na(num)) updateNumericInput(session, input_id, value = num)
      },
      "checkbox" = updateCheckboxInput(
        session, input_id, value = tolower(vals[1]) %in% c("true", "1", "yes", "t")
      ),
      "slider" = {
        num <- suppressWarnings(as.numeric(vals))
        if (!any(is.na(num))) updateSliderInput(session, input_id, value = num)
      },
      "radio" = updateRadioButtons(session, input_id, selected = vals[1]),
      "text"  = updateTextInput(session, input_id, value = vals[1]),
      # default "select": legacy dual-attempt — set as a selectize value, and
      # also as a numeric if the value happens to parse (harmless if neither fits).
      {
        tryCatch(updateSelectizeInput(session, input_id, selected = vals),
                 error = function(e) NULL)
        num <- suppressWarnings(as.numeric(vals[1]))
        if (!is.na(num)) {
          tryCatch(updateNumericInput(session, input_id, value = num),
                   error = function(e) NULL)
        }
      }
    )
  }

  if (!is.null(query$autorun) && query$autorun == "true" && !is.null(spec$run)) {
    button_id <- paste0(prefix, sep, spec$run)
    # Delay the click so the updateSelectizeInput / selectize_set_value round-trips
    # complete before the button handler reads input$* values.
    later::later(function() session$sendCustomMessage("click_button", button_id),
                 delay = 0.5)
  }

  invisible()
}

# Value(s) for a restore `key` taken directly from the current URL, but only when
# the URL targets this spec's tab. A module uses this to preselect a server-side
# selectize in its OWN init, so a deep-linked value survives the widget's
# server-side (re)initialization — which would otherwise wipe a value injected
# separately by cedar_restore_from_query()'s selectize_set_value round-trip (the
# value flashes in, then vanishes, and the run reads an empty input).
# `root_session` is the top-level session (it carries clientData$url_search).
# Returns a character vector (comma-split, already URL-decoded) or NULL.
cedar_url_restore_value <- function(root_session, spec_title, key) {
  spec <- CEDAR_SHARE_SPECS[[spec_title]]
  if (is.null(spec)) return(NULL)
  q <- parseQueryString(root_session$clientData$url_search %||% "")
  if (length(q) == 0) return(NULL)
  if (!identical(tolower(q$tab %||% ""), spec$slug)) return(NULL)
  raw <- q[[key]]
  if (is.null(raw) || !nzchar(raw)) return(NULL)
  unlist(strsplit(raw, ","))
}
