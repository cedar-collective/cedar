# Shareable-URL round-trip: one registry + helpers that BOTH build copy-links and
# restore them, so the two directions can never drift. Replaces the former
# hand-maintained tab_prefixes / button_overrides maps that lived in server.R
# (whose drift is exactly what silently broke the Waitlists deep link).
#
# Each CEDAR_SHARE_SPECS entry is keyed by the exact navbar tab title and
# describes that tab's deep-link contract:
#   slug    — the ?tab= value (must also exist in CEDAR_TAB_SLUGS below).
#   prefix  — fully-namespaced input prefix. An input's id is paste0(prefix, sep, key).
#             Short-prefixed modules use e.g. "waitlist-wl"; a module whose inputs
#             are bare under its namespace (headcount) uses just "headcount".
#   sep     — separator between prefix and key: "_" for short-prefixed modules,
#             "-" for bare-under-namespace modules.
#   run     — input id (relative to prefix) whose ordinary server-side run
#             trigger also consumes autorun events. Regstats uses
#             "dashboard_button" rather than "button".
#   fields  — URL keys this tab accepts, in restoration order. Only declared
#             fields are restored; this is both the public link schema and the
#             dependency order for cascading controls (campus before dept).
#   types   — named list of per-key RESTORE overrides, for exceptions only. Keys
#             not listed default to a client-side select/selectize input.
#             Recognized types:
#               "select"        (default) client selectize/selectInput
#               "select_server" server-side selectize — restored by the owning
#                               module through cedar_linked_server_selectize();
#                               the controller waits but never writes it
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
    slug = "open-seats", prefix = "seatfinder-sf", sep = "_", run = "button",
    fields = c("campus", "college", "dept", "term", "pt", "im", "level"),
    overlay = "seatfinder-loading-overlay"
  ),
  "Cancellations" = list(
    slug = "cancellations", prefix = "cancellations-cn", sep = "_", run = "button",
    fields = c("campus", "college", "dept", "term", "pt", "im", "level"),
    overlay = "cancellations-loading-overlay"
  ),
  "Waitlists" = list(
    slug = "waitlists", prefix = "waitlist-wl", sep = "_", run = "button",
    fields = c("campus", "college", "dept", "level", "term", "pt", "course"),
    overlay = "waitlist-loading-overlay",
    types = list(course = "select_server")
  ),
  # Headcount is deliberately NOT deep-linkable in 1.0. Its six filters cascade
  # (college -> dept -> major/minor/concentration), so restoring them all at once
  # races the dependent updateSelectizeInput calls and can leave the table showing
  # data that does not match the filter labels. A partial restore is worse than
  # none, so there is no spec and no copy-URL button (see R/modules/headcount.R).
  # Revisit in 1.1 by restoring the cascade level-by-level rather than in one pass.
  "Regstats" = list(
    slug = "registration", prefix = "regstats-rs", sep = "_", run = "dashboard_button",
    fields = c("campus", "college", "dept", "term", "level", "pt",
               "min_impacted", "pct_sd", "chronic_fill_rate", "min_wait",
               "min_sat_terms"),
    overlay = "regstats-loading-overlay",
    types = list(min_impacted = "numeric", pct_sd = "numeric",
                 chronic_fill_rate = "numeric", min_wait = "numeric",
                 min_sat_terms = "numeric")
  ),
  "Enrollment" = list(
    slug = "enrollment", prefix = "enrl", sep = "_", run = "button",
    fields = c("campus", "college", "dept", "term", "level"),
    overlay = "enrl-loading-overlay"
  ),

  # Restore-only tabs (no copy button, but reachable via hand-crafted URLs).
  "Dept Dashboard"      = list(
    slug = "dept-dashboard", prefix = "dashboard", sep = "_", run = "button",
    fields = c("campus", "dept", "term"),
    overlay = "dashboard-loading-overlay"
  ),
  "Course Dynamics"     = list(
    slug = "course-dynamics", prefix = "cr", sep = "_", run = "generate_button",
    fields = c("campus", "course"),
    overlay = "cr-loading-overlay",
    types = list(course = "select_server")
  ),
  "Gen Ed"              = list(
    slug = "gen-ed", prefix = "gen_ed-ge", sep = "_", run = "button",
    fields = c("campus", "college", "from_term", "to_term", "dept", "gen_ed_area"),
    overlay = "gen_ed-loading-overlay"
  ),

  # Dept Trends has NO run button — selecting a department fires the analysis
  # (observeEvent(input$dept) in R/modules/dept-trends.R), and the "Reload"
  # button only appears after data has loaded. So `run` is NULL: restoring
  # ?dept= is itself the trigger. cedar_restore_from_query() guards the autorun
  # click on !is.null(spec$run), so no button is clicked.
  #
  # This entry previously read prefix = "dr" — a leftover from the retired
  # legacy Rmd Dept Report. The module is namespaced "dept_trends", so no
  # `dr_*` input has existed since 2026-07-26 and the deep link silently
  # restored nothing.
  "Dept Trends"         = list(
    slug = "dept-trends", prefix = "dept_trends", sep = "-", run = NULL,
    fields = c("campus", "dept")
  )
)

# ── ?tab= slug vocabulary — the public URL contract ─────────────────────────
#
# ONE source for slug -> navbar tab title. Three places consume it:
#   1. ui.R's DOM-ready script (switches tabs before Shiny connects)
#   2. server.R's tab resolution (drives restore + autorun)
#   3. CEDAR_SHARE_SPECS above (builds copy-links)
# These were hand-maintained copies that drifted — the same failure mode that
# silently broke the Waitlists deep link and the Dept Trends one.
#
# THIS TABLE IS APPEND-ONLY. Shared links, bookmarks, and emailed URLs outlive
# any rename, so a slug that has ever shipped must keep resolving forever.
# To rename a tab: add the new slug, keep the old one pointing at the same
# title, and change CEDAR_CANONICAL_SLUGS below so new copy-links use the new
# name. Never delete a row.
CEDAR_TAB_SLUGS <- c(
  # canonical
  "home"               = "Home",
  "dept-dashboard"     = "Dept Dashboard",
  "dept-trends"        = "Dept Trends",
  "enrollment"         = "Enrollment",
  "headcount"          = "Headcount",
  "course-dynamics"    = "Course Dynamics",
  "gen-ed"             = "Gen Ed",
  "pathways"           = "Pathways",
  "registration"       = "Regstats",
  "open-seats"         = "Open Seats",
  "waitlists"          = "Waitlists",
  "projections"        = "Projections",
  "cancellations"      = "Cancellations",
  "data-usage"         = "Data & Usage",
  "changelog"          = "Changelog",

  # legacy aliases — permanent, never removed
  "cedar"              = "Home",            # original landing slug
  "dashboard"          = "Dept Dashboard",
  "data"               = "Data & Usage",
  "low-enrollment"     = "Enrollment",      # an Enrollment sub-tab, not its own tab
  "department-profile" = "Dept Trends"      # pre-2026-07 name for Dept Trends
)

# Slug a tab's own copy-URL button should emit. Derived from CEDAR_SHARE_SPECS
# so a tab can never advertise a slug it cannot restore.
CEDAR_CANONICAL_SLUGS <- vapply(CEDAR_SHARE_SPECS, function(s) s$slug, character(1))

CEDAR_AUTORUN_OVERLAYS <- local({
  specs <- Filter(function(spec) !is.null(spec$overlay), CEDAR_SHARE_SPECS)
  stats::setNames(
    vapply(specs, function(spec) spec$overlay, character(1)),
    vapply(specs, function(spec) spec$slug, character(1))
  )
})

# Resolve any ?tab= value (case-insensitive) to a navbar tab title, or NULL for
# an unrecognized slug. Must never error: this runs on whatever a user pasted
# into the address bar, and `[[` on a named vector throws for a missing name.
cedar_tab_from_slug <- function(slug) {
  if (is.null(slug) || length(slug) != 1 || is.na(slug) || !nzchar(slug)) return(NULL)
  key <- tolower(slug)
  if (!key %in% names(CEDAR_TAB_SLUGS)) return(NULL)
  unname(CEDAR_TAB_SLUGS[[key]])
}

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

# The browser sends the original query string only after all CEDAR link message
# handlers exist. This one event is the authoritative start of restoration; it
# replaces timing assumptions around clientData$url_search and DOM readiness.
cedar_parse_link_state <- function(search) {
  search <- as.character(search %||% "")
  query <- shiny::parseQueryString(search)
  slug <- tolower(query$tab %||% "")
  list(
    search = search,
    query = query,
    tab_name = cedar_tab_from_slug(slug) %||% query$tab %||% NULL
  )
}

cedar_link_server <- function(input, session) {
  link_state <- shiny::reactiveVal(NULL)
  link_run <- shiny::reactiveVal(NULL)
  session$userData$cedar_link_state <- link_state
  session$userData$cedar_link_run <- link_run

  shiny::observeEvent(input$cedar_link_bootstrap, {
    payload <- input$cedar_link_bootstrap
    search <- if (is.list(payload)) payload$search else payload
    link_state(cedar_parse_link_state(search))
  }, once = TRUE, priority = 200)

  shiny::observeEvent(link_state(), {
    state <- link_state()
    cedar_restore_from_query(
      session, input, state$query, state$tab_name,
      run_event = link_run
    )
  }, once = TRUE, priority = -100)

  invisible(link_state)
}

# Return one event source for a tab's ordinary run observer. Manual button
# presses and a completed deep-link restore both increment the same signal, so
# report code has one entry point and URL handling never has to synthesize a DOM
# click. Module sessions resolve their root session through rootScope().
cedar_run_trigger <- function(input, session, input_id, spec_title) {
  spec <- CEDAR_SHARE_SPECS[[spec_title]]
  if (is.null(spec) || is.null(spec$run)) {
    stop("No runnable CEDAR link spec for: ", spec_title)
  }
  local_prefix <- sub(".*-", "", spec$prefix)
  expected_id <- paste0(local_prefix, spec$sep %||% "_", spec$run)
  if (!identical(input_id, expected_id)) {
    stop(
      "Run input does not match CEDAR_SHARE_SPECS for ", spec_title,
      ": expected ", expected_id, ", got ", input_id
    )
  }

  root_session <- if (is.function(session$rootScope)) session$rootScope() else session
  link_run <- root_session$userData$cedar_link_run
  if (!is.function(link_run)) {
    stop("cedar_link_server() must be installed before run triggers")
  }

  signal <- shiny::reactiveVal(NULL)
  counter <- 0L
  emit <- function() {
    counter <<- counter + 1L
    signal(counter)
  }
  shiny::observeEvent(input[[input_id]], {
    emit()
  }, ignoreInit = TRUE, priority = 100)
  shiny::observeEvent(link_run(), {
    event <- link_run()
    if (!is.null(event) && identical(event$tab_name, spec_title)) {
      emit()
    }
  }, priority = 100)

  signal
}

cedar_link_value <- function(state, spec_title, key) {
  if (is.null(state)) return(NULL)
  spec <- CEDAR_SHARE_SPECS[[spec_title]]
  if (is.null(spec) || !identical(state$tab_name, spec_title)) return(NULL)

  raw <- state$query[[key]]
  if (is.null(raw)) {
    aliases <- spec$aliases %||% list()
    legacy <- names(aliases)[vapply(aliases, identical, logical(1), key)]
    legacy <- legacy[legacy %in% names(state$query)]
    if (length(legacy) > 0) raw <- state$query[[legacy[[1]]]]
  }
  if (is.null(raw) || !nzchar(raw)) return(NULL)
  unlist(strsplit(raw, ",", fixed = TRUE), use.names = FALSE)
}

# Initialize a server-side selectize exactly once, after the shared link state
# arrives. Linked sessions initialize directly to the declared value; ordinary
# sessions initialize empty. This avoids racing an unselected choices update
# against a later selected update in the browser.
cedar_linked_server_selectize <- function(session, root_session, input_id, choices,
                                          spec_title, key) {
  link_state <- root_session$userData$cedar_link_state
  if (!is.function(link_state)) {
    stop("cedar_link_server() must be installed before linked selectizes")
  }

  shiny::observeEvent(link_state(), {
    selected <- cedar_link_value(link_state(), spec_title, key)
    shiny::updateSelectizeInput(
      session, input_id, choices = choices,
      selected = selected %||% character(0), server = TRUE
    )
  }, once = TRUE, priority = 100)

  invisible()
}

cedar_restore_values_match <- function(actual, expected) {
  if (is.null(actual)) return(FALSE)
  actual <- as.character(unlist(actual, use.names = FALSE))
  expected <- as.character(unlist(expected, use.names = FALSE))
  length(actual) == length(expected) && setequal(actual, expected)
}

cedar_restore_item <- function(spec, query, key) {
  raw <- query[[key]]
  if (is.null(raw)) {
    aliases <- spec$aliases %||% list()
    legacy <- names(aliases)[vapply(aliases, identical, logical(1), key)]
    legacy <- legacy[legacy %in% names(query)]
    if (length(legacy) > 0) raw <- query[[legacy[[1]]]]
  }
  if (is.null(raw) || !nzchar(raw)) return(NULL)

  values <- unlist(strsplit(raw, ",", fixed = TRUE), use.names = FALSE)
  type <- (spec$types %||% list())[[key]] %||% "select"
  if (identical(type, "numeric")) {
    values <- suppressWarnings(as.numeric(values[[1]]))
    if (is.na(values)) return(NULL)
  } else if (identical(type, "slider")) {
    values <- suppressWarnings(as.numeric(values))
    if (any(is.na(values))) return(NULL)
  } else if (identical(type, "checkbox")) {
    values <- tolower(values[[1]]) %in% c("true", "1", "yes", "t")
  }

  list(
    id = paste0(spec$prefix, spec$sep %||% "_", key),
    key = key,
    type = type,
    value = values
  )
}

cedar_apply_restore_item <- function(session, item) {
  switch(item$type,
    "select_server" = invisible(),
    "numeric" = shiny::updateNumericInput(session, item$id, value = item$value),
    "checkbox" = shiny::updateCheckboxInput(session, item$id, value = item$value),
    "slider" = shiny::updateSliderInput(session, item$id, value = item$value),
    "radio" = shiny::updateRadioButtons(session, item$id, selected = item$value[[1]]),
    "text" = shiny::updateTextInput(session, item$id, value = item$value[[1]]),
    shiny::updateSelectizeInput(session, item$id, selected = item$value)
  )
}

# Restore one declared field at a time. Running at low priority lets a tab's own
# dependency observers (for example campus -> department choices) process each
# field before the next is applied. Autorun publishes one server-side run event
# only after every restored value has round-tripped to the server.
cedar_schedule_link_restore <- function(session, input, items, autorun = FALSE,
                                        tab_name = NULL,
                                        run_event = NULL) {
  item_index <- shiny::reactiveVal(1L)
  restore_observer <- NULL
  restore_observer <- shiny::observe({
    i <- item_index()
    if (i <= length(items)) {
      item <- items[[i]]
      if (cedar_restore_values_match(input[[item$id]], item$value)) {
        item_index(i + 1L)
      } else {
        cedar_apply_restore_item(session, item)
      }
      return()
    }

    restore_observer$destroy()
    if (isTRUE(autorun) && is.function(run_event)) {
      run_event(list(tab_name = tab_name, nonce = as.numeric(Sys.time())))
    }
  }, priority = -100)

  invisible()
}

cedar_restore_from_query <- function(session, input, query, tab_name,
                                     run_event = NULL) {
  if (is.null(tab_name) || length(tab_name) != 1 || is.na(tab_name) ||
      !nzchar(tab_name) || !tab_name %in% names(CEDAR_SHARE_SPECS)) {
    return(invisible())
  }
  spec <- CEDAR_SHARE_SPECS[[tab_name]]

  items <- Filter(Negate(is.null), lapply(spec$fields %||% character(0), function(key) {
    cedar_restore_item(spec, query, key)
  }))
  autorun <- identical(tolower(query$autorun %||% ""), "true") && !is.null(spec$run)
  cedar_schedule_link_restore(
    session, input, items, autorun,
    tab_name = tab_name, run_event = run_event
  )
}
