server <- function(input, output, session) {

  # ============================================================================
  # Server Logic for Cedar Analytics Application
  # ============================================================================
  #
  # DEPENDENCIES (loaded via global.R):
  #   - data_objects[["cedar_sections"]]  - Course sections (DESRs)
  #   - data_objects[["cedar_students"]]  - Student enrollments (class lists)
  #   - data_objects[["cedar_student_term_credits"]] - Observed UNM credits by student-term
  #   - data_objects[["cedar_programs"]]  - Student programs (academic studies)
  #   - data_objects[["cedar_degrees"]]   - Degree completions
  #   - data_objects[["cedar_faculty"]]   - Faculty information
  #
  # DATA MODEL: CEDAR (lowercase column names, no backticks)
  #   - All data uses CEDAR naming conventions (e.g., campus, department, term)
  #   - No legacy column names (e.g., CAMP, DEPT, TERM)
  #
  # ============================================================================

  # Convenience variables for server logic (all from data_objects loaded in global.R)
  cedar_sections  <- data_objects[["cedar_sections"]]
  cedar_students  <- data_objects[["cedar_students"]]
  cedar_programs  <- data_objects[["cedar_programs"]]
  cedar_degrees   <- data_objects[["cedar_degrees"]]
  cedar_faculty   <- data_objects[["cedar_faculty"]]
  # Optional pre-computed tables — NULL/empty if files don't exist yet (before transform runs)
  cedar_grades    <- data_objects[["cedar_grades"]]
  cedar_student_term_credits <- data_objects[["cedar_student_term_credits"]]
  cedar_next_term <- data_objects[["cedar_next_term"]]

  # Initialize session logging within reactive context. Client data arrives
  # reactively, so guard this observer to one session_start row per Shiny token.
  session_start_logged <- FALSE
  observe({
    if (session_start_logged) return()

    # Access reactive values for session start logging
    user_agent <- session$clientData$user_agent
    url_hostname <- session$clientData$url_hostname
    url_protocol <- session$clientData$url_protocol
    url_port <- session$clientData$url_port
    url_pathname <- session$clientData$url_pathname
    if (is.null(user_agent) && is.null(url_hostname) && is.null(url_pathname)) return()
    
    # Log session start with reactive data
    session_id <- session$token
    details <- list(
      url = url_hostname,
      protocol = url_protocol, 
      port = url_port,
      pathname = url_pathname
    )
    
    write_log("INFO", "session_start", details, session_id, user_agent)
    session_start_logged <<- TRUE
  }) # end observe for session start logging
  

  # Log session end when session ends
  session$onSessionEnded(function() {
    session_id <- session$token
    write_log("INFO", "session_end", NULL, session_id, NULL)
  }) # end onSessionEnded

  # Log main tab changes
  observeEvent(input$main_navbar, {
    if (cedar_logging_enabled && !is.null(input$main_navbar)) {
      log_tab_change(session, input$main_navbar)
    }
  }, ignoreInit = TRUE)

  # Loading overlays request current timing estimates when a report starts.
  # Reading them here, instead of embedding them only when ui.R is sourced,
  # makes an Admin timing reset visible immediately to every active session on
  # its next report run.
  observeEvent(input$cedar_timing_estimate_request, {
    req <- input$cedar_timing_estimate_request
    if (is.null(req$prefix) || is.null(req$report_type) ||
        !nzchar(req$prefix) || !nzchar(req$report_type)) return()

    scalar_default <- function(x) {
      if (is.null(x) || length(x) != 1L) return(NULL)
      value <- suppressWarnings(as.numeric(x))
      if (!is.finite(value)) NULL else value
    }

    estimates <- report_time_estimates(
      req$report_type,
      fresh_default = scalar_default(req$fresh_default),
      cached_default = scalar_default(req$cached_default)
    )
    session$sendCustomMessage(
      paste0(req$prefix, "_timing_estimates"),
      estimates
    )
  }, ignoreInit = TRUE)

  # Browser telemetry complements the R calculation timer with the time until
  # the output has been delivered and painted. It records aggregate report type
  # and size/timing data only — no filter values or query contents.
  observeEvent(input$cedar_client_render_timing, {
    tryCatch(
      log_client_render_timing(input$cedar_client_render_timing),
      error = function(e) message("[server.R] Could not record client timing: ", e$message)
    )
  }, ignoreInit = TRUE)

  # One controller owns initial URL parsing, field restoration, and autorun for
  # every registered tab. The browser starts it only after link handlers exist.
  cedar_link_server(input, session)

  observeEvent(session$userData$cedar_link_state(), {
    state <- session$userData$cedar_link_state()
    if (identical(tolower(state$query$tab %||% ""), "low-enrollment")) {
      nav_select("enrl_output_tabs", selected = "low_enrl", session = session)
    }
  }, once = TRUE, priority = 50)


  # Helper function for consistent error logging and notifications
  handle_error <- function(e, context = "general", notification_id = NULL) {
    # Build a full error message including any parent (root cause) errors
    # dplyr 1.1+ wraps errors: e$message = context ("In argument: `x == y`"),
    # e$parent$message = actual cause. Show both so the notification is useful.
    parts <- character(0)
    if (!is.null(e$message) && nzchar(e$message))        parts <- c(parts, e$message)
    if (!is.null(e$parent$message) && nzchar(e$parent$message)) parts <- c(parts, e$parent$message)
    error_msg <- if (length(parts) > 0) {
      paste(parts, collapse = " — ")
    } else {
      as.character(e)
    }
    
    # Log the error with full details
    error_details <- list(
      error_message = error_msg,
      error_call = if(!is.null(e$call)) as.character(e$call) else "unknown",
      error_trace = if(!is.null(e$trace)) as.character(e$trace) else NULL,
      context = context,
      timestamp = Sys.time()
    )
    
    # Write to log file
    write_log("ERROR", context, error_details, session$token, session$clientData$user_agent)
    
    # Also log to console for immediate visibility during development
    message("[ERROR] ", context, ": ", error_msg)
    if(!is.null(e$call)) {
      message("[ERROR] Call: ", paste(as.character(e$call), collapse = " "))
    }
    
    # Remove any existing notification if specified
    if (!is.null(notification_id)) {
      removeNotification(notification_id)
    }
    
    # Show user-friendly notification
    showNotification(
      paste("Error in", context, ":", error_msg), 
      type = "error", 
      duration = 8
    )
  } # end handle_error function




  # ── Changelog modal — set to FALSE to suppress without removing code ─────────
  CHANGELOG_MODAL_ENABLED <- FALSE

  if (CHANGELOG_MODAL_ENABLED) {
    # Show changelog modal when user visits with a new version.
    # Compares last seen version (from localStorage) with current latest version.
    observeEvent(input$cedar_last_seen_version, {
      req(input$cedar_last_seen_version)

      last_seen <- input$cedar_last_seen_version
      cedar_debug("[server.R] User's last seen version: ", last_seen)

      version_info <- get_cedar_version_info()
      if (identical(version_info$version, "unknown")) {
        cedar_debug("[server.R] No changelog entries found, skipping modal")
        return()
      }

      current_version <- version_info$version
      cedar_debug("[server.R] Current CEDAR version: ", current_version)

      if (last_seen != current_version) {
        cedar_debug("[server.R] New version detected, showing changelog modal")

        changelog_html <- format_changelog_html(max_entries = 2)

        showModal(cedar_info_modal(
          title = "Latest CEDAR Updates",
          HTML(paste0(
            "<style>",
            ".changelog-title { margin-top: 0; margin-bottom: 0rem; }",
            ".changelog-entry { margin-bottom: 0; }",
            ".changelog-date { font-size: 1.5rem; color: #666; margin-bottom: 5px; }",
            "</style>",
            changelog_html,
            "<hr>",
            "<p>Please make suggestions or report problems: fwgibbs@unm.edu</p>"
          )),
          close_label = "Got it"
        ))

        session$sendCustomMessage('cedar_mark_changelog_version', list(version = current_version))
        cedar_debug("[server.R] Modal shown and sent version ", current_version, " to client")
      } else {
        cedar_debug("[server.R] User has already seen version ", current_version, ", skipping modal")
      }
    }) # end observeEvent for changelog modal
  } # end if (CHANGELOG_MODAL_ENABLED)


  # configure selectize inputs
  updateSelectizeInput(session, 'enrl_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'enrl_inst', choices = sort(unique(cedar_sections$instructor_name)), server = TRUE)
  cedar_linked_server_selectize(
    session = session,
    root_session = session,
    input_id = "cr_course",
    choices = sort(unique(cedar_sections$subject_course)),
    spec_title = "Course Dynamics",
    key = "course"
  )



  # ===========================================================================
  # Headcount tab (Shiny module)
  # ===========================================================================
  headcountServer("headcount", cedar_programs, data_objects[["cedar_lookups"]],
                  error_handler = handle_error)

  enrollment_projection_bundle <- tryCatch(
    load_latest_enrollment_projection_bundle(
      file.path(cedar_base_dir, "output", "projections")
    ),
    error = function(e) {
      cedar_debug(
        "[server.R] Enrollment projection bundle unavailable: ",
        conditionMessage(e)
      )
      NULL
    }
  )
  enrollmentProjectionsServer(
    "enrollment_projections", bundle = enrollment_projection_bundle
  )

#    ENROLLMENT    #
#####################
.format_enrl_desr_rows <- function(data, grouped = FALSE) {
  if (is.null(data) || nrow(data) == 0 || isTRUE(grouped)) return(data)

  if ("crosslist_partners" %in% names(data) || "split_sections" %in% names(data)) {
    data <- data %>% mutate(
      Partners = coalesce(
        if ("split_sections" %in% names(data)) split_sections else NA_character_,
        if ("crosslist_partners" %in% names(data)) crosslist_partners else NA_character_
      )
    )
  }

  base_select <- c(
    Camp = "campus",
    Col = "college",
    Term = "term",
    TermType = "term_type",
    Course = "subject_course",
    Sec = "section"
  )
  if ("part_term" %in% names(data)) base_select <- c(base_select, PoT = "part_term")

  base_select <- c(
    base_select,
    Title = "course_title",
    SectionEnrl = "enrolled",
    TotalEnrl = "total_enrl",
    Inst = "instructor_name",
    IM = "delivery_method",
    GenEd = "gen_ed_area"
  )
  if ("Partners" %in% names(data)) base_select <- c(base_select, Partners = "Partners")
  if ("crosslist_role" %in% names(data)) base_select <- c(base_select, XlistRole = "crosslist_role")
  if ("crosslist_external" %in% names(data)) base_select <- c(base_select, XlistExternal = "crosslist_external")
  if ("crosslist_primary" %in% names(data)) base_select <- c(base_select, XlistPrimary = "crosslist_primary")
  if ("is_split" %in% names(data)) base_select <- c(base_select, IsSplit = "is_split")

  data %>%
    ungroup() %>%
    select(all_of(base_select)) %>%
    distinct() %>%
    arrange(Course, TermType)
}


enrl_run <- cedar_run_trigger(input, session, "enrl_button", "Enrollment")

enrl_data <- eventReactive(enrl_run(), {
  # Log enrollment button click
  log_report_generation(session, "enrollment", list(
    dept = input$enrl_dept,
    campus = input$enrl_campus,
    college = input$enrl_college,
    term = input$enrl_term,
    level = input$enrl_level,
    agg_by = input$enrl_agg_by
  ))

  timer <- start_report_timer("enrollment", list(
    dept = input$enrl_dept,
    term = input$enrl_term
  ))
  
  opt <- list()
  opt[["status"]] <- "A"
  opt[["uel"]] <- input$enrl_uel
  opt[["group_cols"]] <- enforce_course_campus_grouping(input$enrl_agg_by)
  opt[["course_campus"]] <- input$enrl_campus
  opt[["course_college"]] <- input$enrl_college
  opt[["dept_code"]] <- input$enrl_dept
  opt[["subj"]] <- input$enrl_subj
  opt[["inst"]] <- input$enrl_inst
  opt[["pt"]] <- input$enrl_pt
  opt[["im"]] <- input$enrl_im
  opt[["term"]] <- input$enrl_term
  opt[["level"]] <- input$enrl_level
  opt[["gen_ed"]] <- input$enrl_gen_ed
  opt[["course"]] <- input$enrl_course
  opt[["facet_field"]] <- input$enrl_facet_field
  opt[["crosslist"]] <- "all"  # fetch all sections; crosslist tab in UI filters post-query

  # Ensure facet column survives aggregation by adding it to group_cols.
  # summarize_courses() drops columns not in group_cols, so if the user
  # facets by "level" but doesn't include it in "Group by", the column
  # vanishes and faceting silently fails.
  facet <- input$enrl_facet_field
  if (!is.null(facet) && nchar(facet) > 0 && !(facet %in% opt[["group_cols"]])) {
    opt[["group_cols"]] <- enforce_course_campus_grouping(c(opt[["group_cols"]], facet))
  }

# Add enrollment min/max from numeric inputs
  opt[["enrl_min"]] <- input$enrl_min
  opt[["enrl_max"]] <- input$enrl_max

# Get enrollment data based on the options
  cedar_debug("[server.R] getting enrollment data with options: ", toString(opt))

  # Keep section rows through the shared query. DESR subtabs filter these rows
  # first and aggregate second, so crosslist classification is never lost and
  # hidden metadata never fragments the user's requested grouping.
  opt_for_enrl <- opt
  opt_for_enrl[["enrl_min"]] <- NULL
  opt_for_enrl[["enrl_max"]] <- NULL
  raw_opt <- opt_for_enrl
  raw_opt[["group_cols"]] <- NULL

  timer_enrl <- start_report_timer("get_enrl", list(dept_code = opt[["dept_code"]], term = opt[["term"]]))
  desr_raw <- get_enrl(cedar_sections, raw_opt)
  data <- if (!is.null(opt_for_enrl[["group_cols"]]) && length(opt_for_enrl[["group_cols"]]) > 0) {
    aggregate_courses(desr_raw, opt_for_enrl)
  } else {
    desr_raw
  }
  end_report_timer(timer_enrl)

  rows_before_enrl_filter <- nrow(data)

  # Apply enrollment min/max post-call (same logic as special_filters_desr in filter.R)
  if (!is.null(opt[["enrl_min"]]) && !is.na(opt[["enrl_min"]])) {
    data <- data %>% dplyr::filter(enrolled >= as.integer(opt[["enrl_min"]]))
  }
  if (!is.null(opt[["enrl_max"]]) && !is.na(opt[["enrl_max"]])) {
    data <- data %>% dplyr::filter(enrolled <= as.integer(opt[["enrl_max"]]))
  }

  cedar_debug("[server.R] get_enrl() returned ", nrow(data), " rows (", rows_before_enrl_filter, " before enrollment filter)")
  if (nrow(data) > 0) {
    cedar_debug("[server.R] Sample courses returned: ", paste(unique(data$subject_course)[1:min(5, length(unique(data$subject_course)))], collapse=", "))
  }

  # Detect if enrollment filter eliminated all data
  filter_warning <- ""
  if (nrow(data) == 0 && rows_before_enrl_filter > 0 && (!is.null(input$enrl_min) || !is.null(input$enrl_max))) {
    filter_warning <- paste0("⚠️ No sections matched your enrollment filter (min: ", input$enrl_min, ", max: ", input$enrl_max, "). ",
                            "There were ", rows_before_enrl_filter, " sections before filtering. ",
                            "For future/proposed schedules, try setting Min Enrollment to 0.")
    cedar_debug("[server.R] FILTER WARNING: ", filter_warning)
  }

  # Filter students to match the filtered sections for classlist stats.
  # When group_cols are set, get_enrl() aggregates away the crn column, so
  # CRN-based matching returns zero rows. Fall back to filter_class_list()
  # with the same opt in that case.
  if ("crn" %in% colnames(data) && nrow(data) > 0) {
    filtered_crns <- unique(data$crn)
    filtered_terms <- unique(data$term)
    cedar_debug("[server.R] Filtered to ", length(filtered_crns), " CRNs across terms: ", paste(filtered_terms, collapse = ", "))
    filtered_students <- cedar_students[
      cedar_students$crn  %in% filtered_crns &
      cedar_students$term %in% filtered_terms, ]
    # Crosslisted courses share CRNs — restrict to the dept(s) in the query so
    # partner-dept rows (e.g. CIOL, CRP crosslisted with CHST) are excluded.
    dept_filter <- opt[["dept_code"]]
    if (length(dept_filter) > 0 && any(nzchar(dept_filter))) {
      filtered_students <- filtered_students[filtered_students$department %in% dept_filter, ]
    }
  } else {
    cedar_debug("[server.R] CRN not in aggregated data; filtering students via filter_class_list()")
    filtered_students <- tryCatch(
      filter_class_list(cedar_students, opt),
      error = function(e) {
        cedar_debug("[server.R] filter_class_list() failed for classlist: ", e$message)
        cedar_students[integer(0), ]
      }
    )
  }
  cedar_debug("[server.R] Filtered students to ", nrow(filtered_students), " rows for class list stats")

  timer_cl <- start_report_timer("calc_cl_enrls")
  cl_data <- calc_cl_enrls(filtered_students)
  end_report_timer(timer_cl)


  data <- .format_enrl_desr_rows(
    data,
    grouped = !is.null(opt[["group_cols"]]) && length(opt[["group_cols"]]) > 0
  )

  duration_sec <- end_report_timer(timer)
  signal_load_complete(session, "enrl", duration_sec = duration_sec)

  list(
    data = data,
    desr_raw = desr_raw,
    cl_data = cl_data,
    opt = opt,
    filter_warning = filter_warning
  )
}, ignoreNULL = TRUE, ignoreInit = TRUE)

.enrl_desr_view_ids <- c(
  home = "home",
  split = "split",
  crosslisted = "xl-home",
  away = "away",
  all = "all"
)

# Prepare every DESR slice once per Gather action. The table, scope count, and
# downloads read this shared result so display/export cannot diverge and hidden
# tab controls do not repeat aggregation work.
.enrl_desr_views_data <- reactive({
  out <- enrl_data()
  if (is.null(out) || is.null(out$desr_raw)) return(list())

  views <- unique(unname(.enrl_desr_view_ids))
  prepared <- lapply(views, function(view) {
    data <- filter_enrollment_crosslist_view(out$desr_raw, view)
    grouped <- !is.null(out$opt[["group_cols"]]) && length(out$opt[["group_cols"]]) > 0
    if (nrow(data) > 0 && grouped) {
      data <- aggregate_courses(data, list(group_cols = out$opt[["group_cols"]]))
    }

    if (nrow(data) > 0 && !is.null(out$opt[["enrl_min"]]) && !is.na(out$opt[["enrl_min"]])) {
      data <- data %>% dplyr::filter(enrolled >= as.integer(out$opt[["enrl_min"]]))
    }
    if (nrow(data) > 0 && !is.null(out$opt[["enrl_max"]]) && !is.na(out$opt[["enrl_max"]])) {
      data <- data %>% dplyr::filter(enrolled <= as.integer(out$opt[["enrl_max"]]))
    }

    data %>%
      .format_enrl_desr_rows(grouped = grouped) %>%
      strip_enrollment_crosslist_metadata()
  })
  stats::setNames(prepared, views)
})

.enrl_desr_view_data <- function(view = input$enrl_crosslist_tabs) {
  view <- as.character(view %||% "home")[[1]]
  .enrl_desr_views_data()[[view]]
}

# Helper: derive dept display info from enrl_data() opt — used by both the
# summary box and the modal so the logic doesn't have to be duplicated.
.enrl_dept_info <- function(out) {
  dept_filter <- out$opt$dept_code
  if (is.null(dept_filter) || length(dept_filter) == 0 || all(!nzchar(dept_filter)))
    return(NULL)

  lkp <- data_objects[["cedar_lookups"]][["dept_name_lookup"]]
  dept_display <- if (!is.null(lkp)) {
    nms <- lkp$dept_name[lkp$dept_code %in% dept_filter]
    if (length(nms) > 0) paste(nms, collapse = ", ") else paste(dept_filter, collapse = ", ")
  } else {
    paste(dept_filter, collapse = ", ")
  }
  dept_code_label <- paste(dept_filter, collapse = ", ")

  matched_sections <- cedar_sections %>% filter(department %in% dept_filter)
  subjects_included <- sort(unique(matched_sections$subject))

  campus_filter  <- out$opt$course_campus
  college_filter <- out$opt$course_college
  term_filter    <- out$opt$term
  scoped <- matched_sections
  if (length(campus_filter)  > 0) scoped <- scoped %>% filter(campus  %in% campus_filter)
  if (length(college_filter) > 0) scoped <- scoped %>% filter(college %in% college_filter)
  if (length(term_filter)    > 0) scoped <- scoped %>% filter(term %in% term_filter | term_type %in% term_filter)

  list(
    dept_display    = dept_display,
    dept_code_label = dept_code_label,
    subjects        = subjects_included,
    n_courses       = length(unique(scoped$subject_course)),
    n_sections      = nrow(scoped)
  )
}

output$enrl_filter_summary <- renderUI({
  out <- enrl_data()
  if (is.null(out) || is.null(out$opt)) {
    return(div(class = "enrl-scope-bar",
      tags$span(style = "opacity:0.6;", icon("filter"), " Select filters above and click Gather Enrollments")
    ))
  }

  opt  <- out$opt
  data <- out$data

  # Build filter label list — only show filters that are set
  labels <- list()
  if (length(opt$course_campus)  > 0) labels[["Campus"]]  <- paste(opt$course_campus,  collapse = ", ")
  if (length(opt$course_college) > 0) labels[["College"]] <- paste(opt$course_college, collapse = ", ")
  if (length(opt$dept_code)      > 0) labels[["Dept"]]    <- paste(opt$dept_code,      collapse = ", ")
  if (length(opt$term)           > 0) labels[["Term"]]    <- paste(opt$term,            collapse = ", ")
  if (length(opt$level)          > 0) labels[["Level"]]   <- paste(opt$level,           collapse = ", ")
  if (length(opt$pt)             > 0) labels[["PoT"]]     <- paste(opt$pt,              collapse = ", ")

  filter_chips <- if (length(labels) > 0) {
    lapply(names(labels), function(k) {
      tags$span(class = "scope-chip",
        tags$span(class = "scope-chip-key", k), ": ",
        tags$span(class = "scope-chip-val", labels[[k]])
      )
    })
  } else {
    list(tags$span(style = "opacity:0.7;", "All sections"))
  }

  tab <- input$enrl_crosslist_tabs
  data_shown <- .enrl_desr_view_data(tab)

  n_s_total <- if (!is.null(data)) nrow(data) else 0
  course_col <- intersect(c("subject_course", "Course"), names(data_shown))[1]
  n_c <- if (!is.null(data_shown) && !is.na(course_col)) length(unique(data_shown[[course_col]])) else 0
  n_s <- if (!is.null(data_shown)) nrow(data_shown) else 0
  count_str <- paste0(n_c, " course", if (n_c != 1) "s" else "",
                      ", ", n_s, " section", if (n_s != 1) "s" else "")

  dedup_note <- if (n_s < n_s_total) {
    n_hidden <- n_s_total - n_s
    tab_label <- switch(tab,
      home      = "home view hides crosslist partners",
      split     = "split view shows split-level only",
      `xl-home` = "crosslist view shows external home sections only",
      away      = "partner view shows external partner sections only",
      "tab filter applied"
    )
    tags$span(class = "scope-dedup-note",
      paste0(n_s_total, " total · ", n_hidden, " not shown: ", tab_label)
    )
  } else NULL

  info     <- .enrl_dept_info(out)
  dept_btn <- if (!is.null(info)) {
    actionButton("enrl_dept_info_btn", label = NULL, icon = icon("circle-question"),
                 class = "btn-link btn-sm",
                 title = "How does the dept → subject mapping work?")
  }

  div(class = "enrl-scope-bar",
    tagList(filter_chips),
    tags$span(class = "scope-count", count_str),
    dedup_note,
    dept_btn
  )
})

observeEvent(input$enrl_dept_info_btn, {
  out <- enrl_data()
  if (is.null(out) || is.null(out$opt)) return()
  info <- .enrl_dept_info(out)
  if (is.null(info)) return()

  subj_list <- if (length(info$subjects) > 0)
    tagList("Subject code", if (length(info$subjects) != 1) "s" else "",
            " in ", tags$code("cedar_sections"), " for this dept code: ",
            tags$strong(paste(info$subjects, collapse = ", ")), ".")
  else
    tags$em("No subject codes found in cedar_sections for this dept code.")

  showModal(cedar_info_modal(
    title = paste0("Department filter: how \"", info$dept_display, "\" maps to data"),
    size = "m",
    tagList(
      h5("Name → code", style = "margin-top: 0;"),
      p("The department dropdown displays human-readable names but passes the short dept code
        to the filter. ", tags$code("R/lists/subj_dept_map.R"), " is the authoritative source:
        it defines the full hierarchy of college → department → subject codes, and
        provides the human-readable name for each dept code. When a dept code has no entry in
        that file, CEDAR falls back to deriving a name from ", tags$code("cedar_programs"), "."),
      p(tags$strong(paste0('"', info$dept_display, '" → "', info$dept_code_label, '"')),
        " (from ", tags$code("subj_dept_map.R"), ")."),
      hr(),
      h5("Subject codes"),
      p(tags$code("subj_dept_map.R"), " also maps subject codes to dept codes — the relationship
        is many-to-one, so a single dept code can cover sections offered under multiple subject
        prefixes (for example, a joint program or a department that absorbed another unit).
        Subject codes are stored in ", tags$code("cedar_sections$subject"), "."),
      p("The filter itself matches ", tags$code("cedar_sections$department"), ", not the subject
        code. Subject codes are shown here so you can see which course prefixes are grouped under
        the selected department — useful when a department's courses appear under more than one prefix."),
      subj_list,
      hr(),
      h5("How the filter runs"),
      p("CEDAR filters ", tags$code("cedar_sections$department == \"", info$dept_code_label, "\""),
        " directly at query time. No further translation happens. Summarized course views
        keep campus automatically whenever ", tags$code("subject_course"), " is in Group by,
        so ABQ, EA, and branch-campus course histories are not merged.")
    )
  ))
})

# Build and copy a shareable URL for the current enrollment view to the clipboard.
# Standard copy_cedar_url wiring (see R/trunk/url-state.R). Enrollment is top-level
# (not a module), so the button id stays unnamespaced and the slug varies by the
# active sub-tab (Low Enrollment vs. Enrollment).
cedar_copy_url_observer(
  input, session, "enrl_copy_url", button_id = "enrl_copy_url",
  slug = function() if (identical(input$enrl_output_tabs, "low_enrl")) "low-enrollment" else "enrollment",
  values_fn = function() list(
    campus  = input$enrl_campus,
    college = input$enrl_college,
    dept    = input$enrl_dept,
    term    = input$enrl_term,
    level   = input$enrl_level
  )
)

# Course Dynamics is top-level (not a module), so keep the button id
# unnamespaced while using the shared Course Dynamics URL spec.
cedar_copy_url_observer(
  input, session, "cr_copy_url", button_id = "cr_copy_url",
  spec_title = "Course Dynamics",
  values_fn = function() list(
    campus = input$cr_campus,
    course = input$cr_course
  )
)

  # Enrollment trends — computed alongside main query, but only for single dept.
  # Enrollment trend helpers live with the enrollment branch.
  enrl_trends_data <- eventReactive(enrl_run(), {
    dept <- input$enrl_dept
    if (is.null(dept) || length(dept) != 1) return(NULL)

    campus <- if (!is.null(input$enrl_campus) && length(input$enrl_campus) > 0)
      input$enrl_campus else NULL

    term_scope <- resolve_enrollment_trend_term_scope(input$enrl_term, cedar_current_term)

    tryCatch({
      # campus in group_cols: campuses are never merged — each campus trends
      # against its own history (see CAMPUS RULE in dept-dashboard.R).
      opt <- list(dept_code = dept, status = "A", crosslist = "home", uel = TRUE,
                  group_cols = c("subject_course", "course_title", "campus", "term", "is_topics"))
      if (!is.null(term_scope$term_types)) opt$term <- term_scope$term_types
      if (!is.null(campus)) opt$course_campus  <- campus
      raw_history <- get_enrl(cedar_sections, opt) %>%
        ungroup() %>%
        filter_enrollment_trend_scope(term_scope) %>%
        filter(enrolled > 0)
      history <- prepare_enrollment_trend_history(raw_history)
      momentum <- get_enrollment_momentum(history)
      list(
        growing = momentum$growing,
        investigate = momentum$investigate,
        history = history,
        scope = term_scope
      )
    }, error = function(e) {
      cedar_debug("[server.R] enrl_trends_data error: ", conditionMessage(e))
      NULL
    })
  }, ignoreInit = TRUE)

  output$enrl_trends_scope <- renderUI({
    trends <- enrl_trends_data()
    if (is.null(trends)) {
      return(p("Trends are available after gathering data for a single department.",
               class = "cedar-body text-muted"))
    }
    scope <- trends$scope %||% resolve_enrollment_trend_term_scope(NULL, cedar_current_term)
    p(
      tags$strong("Trend scope: "),
      "single selected department, selected campus filters, active home sections, exclude list, and the last 6 offerings per course. ",
      scope$description,
      scope$exact_note,
      " Regular-course title changes are collapsed; rotating topics remain separate.",
      class = "cedar-body text-muted"
    )
  })

  # Helper: empty plotly with a centred message (used when no data is available)
  .empty_trend_plot <- function(msg) {
    plot_ly(type = "scatter", mode = "text") %>%
      layout(
        annotations = list(text = msg, x = 0.5, y = 0.5,
                           xref = "paper", yref = "paper",
                           showarrow = FALSE, font = list(size = 13, color = "#999")),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)"
      )
  }

  # Helper: line chart for top-n courses from a momentum list
  .make_course_trend_plot <- function(courses, history, n = 5) {
    if (is.null(courses) || nrow(courses) == 0 || is.null(history) || nrow(history) == 0)
      return(NULL)
    plot_data <- prepare_enrollment_trend_plot_series(courses, history, n)
    if (is.null(plot_data) || nrow(plot_data) == 0) return(NULL)
    plot_ly(plot_data, x = ~term_label, y = ~enrolled,
            split = ~series_key, color = ~trace_name,
            colors = cedar_plotly_palette(plot_data$trace_name),
            type = "scatter", mode = "lines+markers",
            hovertemplate = "%{y:,} enrolled<extra>%{fullData.name}</extra>") %>%
      layout(
        xaxis  = list(title = "", tickangle = -45),
        yaxis  = list(title = "Enrolled"),
        legend = list(orientation = "h", x = 0, y = -0.35, font = list(size = 10)),
        margin = list(b = 120),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)"
      )
  }

  output$enrl_trends_growth_plot <- renderPlotly({
    trends <- enrl_trends_data()
    if (is.null(trends)) return(.empty_trend_plot("Select a single department to see trends."))
    p <- .make_course_trend_plot(trends$growing, trends$history)
    if (is.null(p)) .empty_trend_plot("No growing courses found.") else p
  })

  output$enrl_trends_decline_plot <- renderPlotly({
    trends <- enrl_trends_data()
    if (is.null(trends)) return(.empty_trend_plot("Select a single department to see trends."))
    p <- .make_course_trend_plot(trends$investigate, trends$history)
    if (is.null(p)) .empty_trend_plot("No declining courses found.") else p
  })

  # Auto campus-by-level plot — uses the same filters as the main query.
  output$enrl_level_plot <- renderPlotly({
    req(enrl_data())
    base_opt <- enrl_data()$opt
    req(!is.null(base_opt))

    opt <- base_opt
    opt$group_cols  <- c("term", "level", "campus")
    opt$level       <- NULL
    opt$facet_field <- NULL
    opt$enrl_min    <- NULL
    opt$enrl_max    <- NULL

    level_data <- tryCatch(get_enrl(cedar_sections, opt), error = function(e) NULL)
    req(!is.null(level_data) && nrow(level_data) > 0)

    plot <- build_enrollment_level_trend_plot(level_data)
    req(!is.null(plot))
    plot
  })


.enrl_col_defs <- function(df) {
  # Header labels match the rest of the site: whole words rather than squeezed
  # camelCase (Campus not Camp, Term Type not TermType, Gen Ed not GenEd), and
  # the shared table theme uppercases them. The two enrollment columns wrap onto
  # two lines on purpose, the same treatment used by the low-enrollment tables,
  # so "Sect Enrl" and "Total Enrl" stay narrow and read as a pair.
  header_nowrap <- list(whiteSpace = "nowrap")
  header_wrap   <- list(whiteSpace = "normal", lineHeight = "1.1")

  defs <- list(
    # Unaggregated (renamed) columns
    Camp        = reactable::colDef(name = "Campus",    maxWidth = 70,  headerStyle = header_nowrap),
    Col         = reactable::colDef(name = "College",   maxWidth = 72,  headerStyle = header_nowrap),
    Term        = reactable::colDef(name = "Term",      maxWidth = 75,  headerStyle = header_nowrap,
                                    cell = function(value) as.character(value)),
    TermType    = reactable::colDef(name = "Term Type", maxWidth = 82,  headerStyle = header_wrap),
    Course      = reactable::colDef(name = "Course",    minWidth = 90,  headerStyle = header_nowrap),
    Sec         = reactable::colDef(name = "Sec",       maxWidth = 55,  headerStyle = header_nowrap),
    PoT         = cedar_pot_coldef(),
    Title       = reactable::colDef(name = "Title",     minWidth = 180, headerStyle = header_nowrap),
    SectionEnrl = reactable::colDef(name = "Sect Enrl", width = 78, align = "right", headerStyle = header_wrap),
    TotalEnrl   = reactable::colDef(name = "Total Enrl", width = 78, align = "right", headerStyle = header_wrap),
    Inst        = reactable::colDef(name = "Instructor", minWidth = 160, headerStyle = header_nowrap),
    IM          = reactable::colDef(name = "Method",    maxWidth = 72,  headerStyle = header_nowrap),
    GenEd       = reactable::colDef(name = "Gen Ed",    maxWidth = 80,  headerStyle = header_nowrap),
    Partners    = reactable::colDef(name = "Partners",  minWidth = 120, headerStyle = header_nowrap),
    XlistRole   = reactable::colDef(show = FALSE),
    # Aggregated (original) column names
    campus          = reactable::colDef(name = "Campus",    maxWidth = 70,  headerStyle = header_nowrap),
    college         = reactable::colDef(name = "College",   maxWidth = 72,  headerStyle = header_nowrap),
    term            = reactable::colDef(name = "Term",      maxWidth = 75,  headerStyle = header_nowrap,
                                        cell = function(value) as.character(value)),
    term_type       = reactable::colDef(name = "Term Type", maxWidth = 82,  headerStyle = header_wrap),
    subject_course  = reactable::colDef(name = "Course",    minWidth = 90,  headerStyle = header_nowrap),
    course_title    = reactable::colDef(name = "Title",     minWidth = 180, headerStyle = header_nowrap),
    gen_ed_area     = reactable::colDef(name = "Gen Ed",    maxWidth = 80,  headerStyle = header_nowrap),
    delivery_method = reactable::colDef(name = "Method",    maxWidth = 72,  headerStyle = header_nowrap),
    part_term       = cedar_pot_coldef(),
    instructor_name = reactable::colDef(name = "Instructor", minWidth = 160, headerStyle = header_nowrap),
    first_day_proxy = reactable::colDef(
      name = "First Day / Ever Registered", minWidth = 125, align = "right",
      headerStyle = header_wrap
    ),
    census_enrl = reactable::colDef(
      name = "Census", minWidth = 78, align = "right", headerStyle = header_nowrap
    ),
    last_day_or_current_enrl = reactable::colDef(
      name = "Last Day / Current", minWidth = 110, align = "right",
      headerStyle = header_wrap
    ),
    early_drops = reactable::colDef(
      name = "Early Drops", minWidth = 82, align = "right", headerStyle = header_wrap
    ),
    late_drops = reactable::colDef(
      name = "Late Drops", minWidth = 82, align = "right", headerStyle = header_wrap
    ),
    waitlisted = reactable::colDef(
      name = "Waitlisted", minWidth = 82, align = "right", headerStyle = header_nowrap
    )
  )
  defs[intersect(names(defs), names(df))]
}

output$enrl_summary <- reactable::renderReactable({
  # Summary table works with or without grouping variables.
  # Crosslist classification is applied to section rows before aggregation.
  tryCatch({
    enrl_out <- enrl_data()
    data <- .enrl_desr_view_data(input$enrl_crosslist_tabs)

    if (!is.null(enrl_out$filter_warning) && nchar(enrl_out$filter_warning) > 0) {
      showNotification(HTML(enrl_out$filter_warning), type = "warning",
                       duration = 10, id = "enrl_filter_warning")
    }

    if (is.null(data) || nrow(data) == 0) return(NULL)

    # Default sort: by course (asc), then term (desc, so recent terms first).
    # Handles both the renamed (Course/Term) and aggregated (subject_course/term)
    # column naming.
    course_col <- intersect(c("Course", "subject_course"), names(data))[1]
    term_col   <- intersect(c("Term", "term"), names(data))[1]
    default_sorted <- list()
    if (!is.na(course_col)) default_sorted[[course_col]] <- "asc"
    if (!is.na(term_col))   default_sorted[[term_col]]   <- "desc"

    reactable::reactable(data, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE,
                         compact = TRUE, resizable = TRUE, defaultPageSize = 50,
                         showPageSizeOptions = TRUE, pageSizeOptions = c(25, 50, 100),
                         defaultSorted = default_sorted,
                         columns = .enrl_col_defs(data))
  }, error = function(e) NULL)
})

# Class list enrollment summary table
.enrl_classlist_view_data <- reactive({
  prepare_enrollment_classlist_table(enrl_data()$cl_data)
})

output$enrl_cl_summary <- reactable::renderReactable({
  tryCatch({
    cl_data <- .enrl_classlist_view_data()
    if (is.null(cl_data) || nrow(cl_data) == 0) return(NULL)
    reactable::reactable(cl_data, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE,
                         compact = TRUE, resizable = TRUE, defaultPageSize = 50,
                         showPageSizeOptions = TRUE, pageSizeOptions = c(25, 50, 100),
                         defaultSorted = list(term = "desc", subject_course = "asc"),
                         columns = .enrl_col_defs(cl_data))
  }, error = function(e) NULL)
})


# Each DESR subtab owns a contextual download directly under its description.
# A fixed view per handler also means a click cannot race a tab change.
for (.download_key in names(.enrl_desr_view_ids)) {
  local({
    download_key <- .download_key
    view <- .enrl_desr_view_ids[[download_key]]
    ui_id <- paste0("enrl_desr_download_", download_key, "_ui")
    download_id <- paste0("enrl_desr_download_", download_key)

    output[[ui_id]] <- renderUI({
      data <- .enrl_desr_view_data(view)
      if (is.null(data) || nrow(data) == 0) return(NULL)
      downloadLink(
        download_id,
        tagList(icon("download"), " Download CSV"),
        style = "font-size: 0.85em; color: #666; display: inline-block; margin-bottom: 8px;"
      )
    })

    output[[download_id]] <- downloadHandler(
      filename = function() {
        paste0("enrollment_desr_", gsub("-", "_", view), "_", Sys.Date(), ".csv")
      },
      content = function(file) {
        data <- isolate(.enrl_desr_view_data(view))
        if (is.null(data) || nrow(data) == 0) {
          data <- data.frame(message = "No enrollment data available for this DESR view")
        }
        write.csv(data, file, row.names = FALSE)
      }
    )
  })
}

output$enrl_classlist_download_ui <- renderUI({
  data <- .enrl_classlist_view_data()
  if (is.null(data) || nrow(data) == 0) return(NULL)
  downloadLink(
    "enrl_classlist_download",
    tagList(icon("download"), " Download CSV"),
    style = "font-size: 0.85em; color: #666; display: inline-block; margin-bottom: 8px;"
  )
})

output$enrl_classlist_download <- downloadHandler(
  filename = function() paste0("enrollment_classlist_", Sys.Date(), ".csv"),
  content = function(file) {
    data <- isolate(.enrl_classlist_view_data())
    if (is.null(data) || nrow(data) == 0) {
      data <- data.frame(message = "No classlist data available for selected filters")
    }
    write.csv(data, file, row.names = FALSE)
  }
)



  # Update subject choices when college or department changes
  observeEvent(list(input$enrl_college, input$enrl_dept), {
    secs <- cedar_sections
    if (!is.null(input$enrl_college) && length(input$enrl_college) > 0)
      secs <- secs[secs$college %in% input$enrl_college, ]
    if (!is.null(input$enrl_dept) && length(input$enrl_dept) > 0)
      secs <- secs[secs$department %in% input$enrl_dept, ]
    updateSelectizeInput(session, "enrl_subj",
                         choices = sort(unique(secs$subject)), server = TRUE)
  }, ignoreNULL = FALSE)

  # Update course choices when department or subject changes
  observeEvent(list(input$enrl_dept, input$enrl_subj), {
    log_data_filter(session, "enrollment_dept", input$enrl_dept)
    secs <- cedar_sections
    if (!is.null(input$enrl_dept) && length(input$enrl_dept) > 0)
      secs <- secs[secs$department %in% input$enrl_dept, ]
    if (!is.null(input$enrl_subj) && length(input$enrl_subj) > 0)
      secs <- secs[secs$subject %in% input$enrl_subj, ]
    updateSelectizeInput(session, "enrl_course",
                         choices = sort(unique(secs$subject_course)), server = TRUE)
  }, ignoreNULL = FALSE)
  
  

  #########################################
  #    LOW ENROLLMENT ALERT DASHBOARD    #
  #########################################

  # Mode tracker: "alerts" for current/past terms, "concerns" for future terms
  enrl_mode <- reactiveVal("alerts")

  # Reactive for low enrollment course data - uses main enrollment filters.
  # Fetches all courses below the highest threshold in one pass, then level-specific
  # reactives filter down to each section's own threshold.
  # When a future term is selected, switches to "concerns" mode using historical averages.
  # Fires when Gather Enrollments is clicked (same trigger as enrl_data), so data
  # is available as soon as the user navigates to this tab.
  # Thresholds are isolated so changing them only re-runs the fast per-level
  # filtering reactives, not this full fetch.
  low_enrl_data <- eventReactive(enrl_run(), {
    # Build opt directly from inputs — same filters as the DESR tab but without
    # group_cols, enrl_min/max, or other DESR-only options that don't apply here.
    # Level is excluded so all four levels are fetched in one pass; level-specific
    # filtering happens in the per-level reactives below.
    opt <- list(
      term           = input$enrl_term,
      course_campus  = input$enrl_campus,
      course_college = input$enrl_college,
      dept_code      = input$enrl_dept,
      im             = input$enrl_im,
      pt             = input$enrl_pt,
      gen_ed         = input$enrl_gen_ed,
      inst           = input$enrl_inst,
      course         = input$enrl_course,
      status         = "A",
      uel            = input$enrl_uel
    )

    log_report_generation(session, "low_enrollment", list(
      threshold_lower = isolate(input$low_enrl_threshold_lower),
      threshold_upper = isolate(input$low_enrl_threshold_upper),
      threshold_split = isolate(input$low_enrl_threshold_split),
      threshold_grad  = isolate(input$low_enrl_threshold_grad),
      term   = opt$term,
      campus = opt$course_campus,
      college = opt$course_college,
      dept_code = opt$dept_code
    ))

    # --- Detect future vs current/past terms ---
    selected_terms <- opt$term
    # A term is "future" (concerns mode) only if it's beyond cedar_current_term AND
    # has no actual enrollment yet. Once registration is active, use per-section alerts.
    future_flags <- sapply(selected_terms, function(t) {
      if (!grepl("^\\d+$", t)) return(FALSE)
      t_int <- as.integer(t)
      if (t_int <= cedar_current_term) return(FALSE)
      !any(cedar_sections$term == t_int & cedar_sections$enrolled > 0, na.rm = TRUE)
    })
    has_future <- any(future_flags)
    has_past   <- any(!future_flags)

    # Mixed terms (future + current/past) not supported
    if (has_future && has_past) {
      showNotification(
        paste("You selected both future and current/past terms.",
              "The alert dashboard works differently for future terms (historical analysis)",
              "vs current terms (actual enrollment). Please select only one type."),
        type = "error", duration = 10
      )
      return(NULL)
    }

    # Set mode for downstream reactives
    if (has_future) {
      enrl_mode("concerns")
    } else {
      enrl_mode("alerts")
    }

    low_enrl_timer <- start_report_timer("low_enrollment", list(
      term = opt$term,
      dept_code = opt$dept_code
    ))

    # =====================================================================
    # FUTURE TERM: Historical enrollment concerns
    # =====================================================================
    if (has_future) {
      cedar_debug("[server.R] Future term detected — switching to concerns mode")
      result <- get_enrollment_concerns(cedar_sections, opt, n_history_terms = 4)

      if (is.null(result) || nrow(result) == 0) {
        cedar_debug("[server.R] No courses found on future schedule")
        end_report_timer(low_enrl_timer)
        return(NULL)
      }

      cedar_debug("[server.R] Enrollment concerns ready: ", nrow(result), " courses")
      end_report_timer(low_enrl_timer)
      return(result)
    }

    # =====================================================================
    # CURRENT/PAST TERM: Actual low enrollment alerts (existing logic)
    # =====================================================================

    thresholds <- isolate(c(
      lower = input$low_enrl_threshold_lower,
      upper = input$low_enrl_threshold_upper,
      split = input$low_enrl_threshold_split,
      grad  = input$low_enrl_threshold_grad
    ))
    min_enrl_val <- isolate(input$low_enrl_min_enrl)

    all_low <- build_low_enrollment_alerts(
      cedar_sections, opt,
      thresholds     = thresholds,
      include_buffer = TRUE,
      min_enrl       = min_enrl_val,
      add_history    = TRUE,
      history_limit  = 500L,
      max_term       = cedar_current_term
    )
    if (is.null(all_low) || nrow(all_low) == 0) {
      cedar_debug("[server.R] No low enrollment courses found")
      return(NULL)
    }

    cedar_debug("[server.R] Low enrollment base data ready: ", nrow(all_low), " rows")
    end_report_timer(low_enrl_timer)
    return(all_low)
  })

  # Level-specific filtered reactives (applied after button press, using per-level thresholds).
  # Split-level courses are excluded from the per-level tabs (they appear in the split tab).
  # In concerns mode, filters on avg_enrl with buffer zone instead of total_enrl.
  .filter_by_level <- function(data, level_val, threshold, is_split_filter = FALSE) {
    filter_low_enrollment_level(
      data, level_val, threshold,
      is_split_filter = is_split_filter,
      mode = enrl_mode()
    )
  }

  .low_enrl_thresholds <- function() {
    c(
      lower = input$low_enrl_threshold_lower,
      upper = input$low_enrl_threshold_upper,
      split = input$low_enrl_threshold_split,
      grad  = input$low_enrl_threshold_grad
    )
  }

  .low_enrl_combined <- function() {
    collect_low_enrollment_threshold_rows(
      low_enrl_data(),
      thresholds = .low_enrl_thresholds(),
      mode = enrl_mode()
    )
  }

  low_enrl_lower <- reactive({
    req(low_enrl_data())
    .filter_by_level(low_enrl_data(), "lower", input$low_enrl_threshold_lower)
  })
  low_enrl_upper <- reactive({
    req(low_enrl_data())
    .filter_by_level(low_enrl_data(), "upper", input$low_enrl_threshold_upper)
  })
  low_enrl_split <- reactive({
    req(low_enrl_data())
    .filter_by_level(low_enrl_data(), NA, input$low_enrl_threshold_split, is_split_filter = TRUE)
  })
  low_enrl_grad <- reactive({
    req(low_enrl_data())
    .filter_by_level(low_enrl_data(), "grad", input$low_enrl_threshold_grad)
  })


  # Mode banner — shown above summary cards when in concerns mode
  output$enrl_mode_banner <- renderUI({
    req(low_enrl_data())
    if (enrl_mode() != "concerns") return(NULL)

    future_term_str <- tryCatch(
      term_code_to_str(input$enrl_term),
      error = function(e) input$enrl_term
    )
    term_type <- get_term_type(input$enrl_term)

    div(
      class = "alert alert-info",
      style = "margin: 10px 0; padding: 12px 20px;",
      icon("clock"),
      strong("FUTURE MODE! "),
      paste0("Showing historical enrollment concerns for ", future_term_str, ". "),
      paste0("Color coding is based on average enrollment from the last 4 same-type (",
             term_type, ") terms, not current enrollment. "),
      "Courses in the green band have historically met the threshold but are near the boundary."
    )
  })

  # Summary statistics output — aggregates across all four levels using per-level thresholds.
  # A course is "critical/warning/watch" relative to its own level's threshold.
  # In concerns mode, severity is based on avg_enrl instead of total_enrl.
  output$low_enrl_summary <- renderUI({
    if (is.null(low_enrl_data())) {
      return(div(
        class = "alert alert-info",
        style = "margin: 12px 0;",
        icon("exclamation-triangle"), " ",
        "Click ", tags$strong("Gather Enrollments"), " above to load data, then open this tab."
      ))
    }
    base <- low_enrl_data()

    if (nrow(base) == 0) {
      no_results_msg <- if (enrl_mode() == "concerns") {
        "No courses found on the future schedule with these filters."
      } else {
        "No courses were found with enrollment below any threshold."
      }
      return(div(
        class = "alert alert-info",
        style = "margin: 20px; padding: 20px; text-align: center;",
        icon("circle-check", style = "font-size: 2em; margin-bottom: 10px;"),
        h4("No Courses Found", class = "my-2"),
        p(no_results_msg, style = "margin: 5px 0; font-size: 1.1em;"),
        p("Try adjusting your filters or thresholds.",
          style = "margin-top: 15px; color: #666;")
      ))
    }

    combined <- .low_enrl_combined()

    if (nrow(combined) == 0) {
      # "All clear" is a result, not an error — same centered empty-state
      # treatment as every other tab, with a check glyph above the copy.
      return(div(
        class = "empty-state",
        div(class = "text-success", style = "font-size: 2em;", icon("circle-check")),
        tags$p("No courses of concern. Nothing matches the current thresholds and filters.")
      ))
    }

    if (enrl_mode() == "concerns") {
      # Concerns mode: severity based on avg_enrl
      combined <- combined %>%
        mutate(
          enrl_val = coalesce(avg_enrl, 0),
          severity = case_when(
            n_prior_terms == 0              ~ "no_history",
            enrl_val < .threshold * 0.5     ~ "critical",
            enrl_val < .threshold * 0.75    ~ "warning",
            enrl_val < .threshold           ~ "watch",
            TRUE                            ~ "buffer"
          )
        )

      critical      <- sum(combined$severity == "critical")
      warning_count <- sum(combined$severity == "warning")
      watch         <- sum(combined$severity == "watch")
      buffer        <- sum(combined$severity == "buffer")
      no_history    <- sum(combined$severity == "no_history")
      total_courses <- nrow(combined)

      div(
        class = "row",
        class = "mb-4",
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--critical",
                h4(critical, class = "my-2"),
                p("Historically Low (< 50%)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--warning",
                h4(warning_count, class = "my-2"),
                p("Borderline (50–75%)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--info",
                h4(watch, class = "my-2"),
                p("Watch (75–100%)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--success",
                h4(buffer, class = "my-2"),
                p("Near Threshold (≥ 100%)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--neutral",
                h4(no_history, class = "my-2"),
                p("No Prior History", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_courses, class = "my-2"),
                p("Total Courses", class = "my-1")
            )
        )
      )
    } else {
      # Alerts mode: severity relative to per-level threshold; buffer zone shows
      # courses above threshold that could still drop below it.
      combined <- combined %>%
        mutate(
          severity = case_when(
            enrolled < .threshold * 0.5  ~ "critical",
            enrolled < .threshold * 0.75 ~ "warning",
            enrolled <= .threshold       ~ "watch",
            TRUE                         ~ "buffer"
          )
        )

      critical      <- sum(combined$severity == "critical")
      warning_count <- sum(combined$severity == "warning")
      watch         <- sum(combined$severity == "watch")
      buffer        <- sum(combined$severity == "buffer")
      total_courses <- nrow(combined)
      total_students <- sum(combined$enrolled, na.rm = TRUE)
      avg_enrollment <- round(mean(combined$enrolled, na.rm = TRUE), 1)

      div(
        class = "row",
        class = "mb-4",
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--critical",
                h4(critical, class = "my-2"),
                p("Critical (< 50% of threshold)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--warning",
                h4(warning_count, class = "my-2"),
                p("Warning (50–75% of threshold)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--info",
                h4(watch, class = "my-2"),
                p("Watch (75–100% of threshold)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--buffer",
                h4(buffer, class = "my-2"),
                p("Monitor (above threshold)", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_courses, class = "my-2"),
                p("Total Courses", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_students, class = "my-2"),
                p("Total Students", class = "my-1")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(avg_enrollment, class = "my-2"),
                p("Avg Enrollment", class = "my-1")
            )
        )
      )
    }
  })


  # Shared helper: apply proportional color-banding to an enrollment column in a DT.
  # include_buffer adds a green zone for courses at/above threshold (concerns mode).
  # Returns a reactable style function that colors a numeric enrollment column
  # by distance from threshold: red < 50%, yellow 50-75%, blue 75-100%,
  # green >= 100% (only when include_buffer = TRUE).
  .enrl_col_style <- function(threshold, include_buffer = FALSE) {
    critical <- threshold * 0.50
    warn_lvl <- threshold * 0.75
    function(value, ...) {
      if (is.na(value) || !is.numeric(value)) return(NULL)
      bg <- if      (value < critical)  "#f8d7da"
            else if (value < warn_lvl)  "#fff3cd"
            else if (value < threshold) "#d1ecf1"
            else if (include_buffer)    "#d4edda"
            else                        "#d1ecf1"
      list(background = bg, fontWeight = "bold")
    }
  }

  # Helper: build a reactable for a low-enrollment dataset given a threshold.
  # show_split_info: if TRUE, includes a "Split Partners" column.
  .make_low_enrl_rt <- function(data, threshold, show_split_info = FALSE) {
    if (is.null(data) || nrow(data) == 0) return(NULL)

    if (!"history_text" %in% names(data)) data$history_text <- NA_character_
    data <- data %>% mutate(history_text = ifelse(is.na(history_text), "—", history_text))
    if (!"n_sections" %in% names(data)) data$n_sections <- 1L
    if (!"course_enrl" %in% names(data)) data$course_enrl <- data$total_enrl

    if (show_split_info && "split_sections" %in% names(data)) {
      display_data <- data %>%
        select(
          Campus = campus, Dept = department, Course = subject_course,
          `Sect#` = section, `Split Partners` = split_sections,
          Title = course_title, Term = term, Sects = n_sections,
          Enrolled = enrolled, `XL Total` = total_enrl,
          `Course Total` = course_enrl, `Prior History` = history_text
        ) %>% arrange(Enrolled)
    } else {
      display_data <- data %>%
        select(
          Campus = campus, Dept = department, Course = subject_course,
          `Sect#` = section, Title = course_title, Term = term,
          Sects = n_sections, Enrolled = enrolled, `XL Total` = total_enrl,
          `Course Total` = course_enrl, `Prior History` = history_text
        ) %>% arrange(Enrolled)
    }

    enrl_style  <- .enrl_col_style(threshold, include_buffer = TRUE)
    header_nowrap <- list(whiteSpace = "nowrap")
    split_cols  <- if (show_split_info)
      list(`Split Partners` = reactable::colDef(minWidth = 120, headerStyle = header_nowrap)) else list()

    reactable::reactable(
      display_data,
      theme           = cedar_tbl_theme,
      striped         = TRUE,
      highlight       = TRUE,
      defaultPageSize = 25,
      columns = c(
        list(
          Campus  = reactable::colDef(minWidth = 76, maxWidth = 90, headerStyle = header_nowrap),
          Dept    = reactable::colDef(minWidth = 62, maxWidth = 78, headerStyle = header_nowrap),
          Course  = reactable::colDef(minWidth = 90, headerStyle = header_nowrap,
            cell = function(v) htmltools::span(class = "fw-semibold", v)),
          `Sect#` = reactable::colDef(minWidth = 68, maxWidth = 78, align = "right", headerStyle = header_nowrap),
          Title   = reactable::colDef(minWidth = 150, headerStyle = header_nowrap)
        ),
        split_cols,
        list(
          Term           = reactable::colDef(minWidth = 76, maxWidth = 90, align = "right", headerStyle = header_nowrap),
          Sects          = reactable::colDef(minWidth = 66, maxWidth = 76, align = "right", headerStyle = header_nowrap),
          Enrolled       = reactable::colDef(minWidth = 88, maxWidth = 104, align = "right", style = enrl_style, headerStyle = header_nowrap),
          `XL Total`     = reactable::colDef(minWidth = 86, maxWidth = 100, align = "right", headerStyle = header_nowrap),
          `Course Total` = reactable::colDef(minWidth = 104, maxWidth = 116, align = "right", headerStyle = header_nowrap),
          `Prior History`= reactable::colDef(minWidth = 150, headerStyle = header_nowrap)
        )
      )
    )
  }

  # Helper: build a reactable for enrollment concerns (future term, historical averages).
  .make_concern_rt <- function(data, threshold, show_split_info = FALSE) {
    if (is.null(data) || nrow(data) == 0) return(NULL)

    data <- data %>% mutate(
      avg_enrl_display = coalesce(avg_enrl, 0),
      history_text     = coalesce(history_text, "No prior history")
    )

    if (show_split_info && "split_sections" %in% names(data)) {
      display_data <- data %>%
        select(
          Campus = campus, Department = department, Course = subject_course,
          `Split Partners` = split_sections, Title = course_title,
          Sects = n_sections, `Sect Enrl` = current_enrl,
          `Hist Avg` = avg_enrl_display, Trend = trend,
          `# Terms` = n_prior_terms, `Prior History` = history_text
        ) %>% arrange(`Hist Avg`)
    } else {
      display_data <- data %>%
        select(
          Campus = campus, Department = department, Course = subject_course,
          Title = course_title, Sects = n_sections, `Sect Enrl` = current_enrl,
          `Hist Avg` = avg_enrl_display, Trend = trend,
          `# Terms` = n_prior_terms, `Prior History` = history_text
        ) %>% arrange(`Hist Avg`)
    }

    hist_style   <- .enrl_col_style(threshold, include_buffer = TRUE)
    header_nowrap <- list(whiteSpace = "nowrap")
    trend_colors <- c("↑ up" = "#28a745", "↓ down" = "#dc3545",
                      "↔ stable" = "#6c757d")
    split_cols   <- if (show_split_info)
      list(`Split Partners` = reactable::colDef(minWidth = 120, headerStyle = header_nowrap)) else list()

    reactable::reactable(
      display_data,
      theme           = cedar_tbl_theme,
      striped         = TRUE,
      highlight       = TRUE,
      defaultPageSize = 25,
      columns = c(
        list(
          Campus     = reactable::colDef(minWidth = 76, maxWidth = 90, headerStyle = header_nowrap),
          Department = reactable::colDef(minWidth = 104, maxWidth = 118, headerStyle = header_nowrap),
          Course     = reactable::colDef(minWidth = 90, headerStyle = header_nowrap,
            cell = function(v) htmltools::span(class = "fw-semibold", v)),
          Title      = reactable::colDef(minWidth = 150, headerStyle = header_nowrap)
        ),
        split_cols,
        list(
          Sects       = reactable::colDef(minWidth = 66, maxWidth = 76, align = "right", headerStyle = header_nowrap),
          `Sect Enrl` = reactable::colDef(minWidth = 90, maxWidth = 104, align = "right", headerStyle = header_nowrap),
          `Hist Avg`  = reactable::colDef(minWidth = 86, maxWidth = 100, align = "right", style = hist_style, headerStyle = header_nowrap),
          Trend       = reactable::colDef(maxWidth = 80, align = "center", headerStyle = header_nowrap,
            cell = function(v) {
              color <- trend_colors[v]
              color <- if (!is.na(color)) unname(color) else "#adb5bd"
              htmltools::span(style = paste0("color:", color, "; font-weight:500"), v)
            }),
          `# Terms`       = reactable::colDef(minWidth = 78, maxWidth = 90, align = "right", headerStyle = header_nowrap),
          `Prior History` = reactable::colDef(minWidth = 150, headerStyle = header_nowrap)
        )
      )
    )
  }

  # Dispatch to the correct builder based on current enrl_mode()
  .render_enrl_rt <- function(data, threshold, show_split_info = FALSE) {
    if (enrl_mode() == "concerns") {
      .make_concern_rt(data, threshold, show_split_info)
    } else {
      .make_low_enrl_rt(data, threshold, show_split_info)
    }
  }

  # suspendWhenHidden = FALSE ensures Shiny renders all four subtabs even when
  # not visible, so changing filters and clicking Gather updates all tabs at once.
  output$low_enrl_table_lower <- reactable::renderReactable({
    req(low_enrl_data())
    .render_enrl_rt(low_enrl_lower(), input$low_enrl_threshold_lower)
  })

  output$low_enrl_table_upper <- reactable::renderReactable({
    req(low_enrl_data())
    .render_enrl_rt(low_enrl_upper(), input$low_enrl_threshold_upper)
  })

  output$low_enrl_table_split <- reactable::renderReactable({
    req(low_enrl_data())
    .render_enrl_rt(low_enrl_split(), input$low_enrl_threshold_split, show_split_info = TRUE)
  })

  output$low_enrl_table_grad <- reactable::renderReactable({
    req(low_enrl_data())
    .render_enrl_rt(low_enrl_grad(), input$low_enrl_threshold_grad)
  })

  outputOptions(output, "low_enrl_table_lower", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_upper", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_split", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_grad",  suspendWhenHidden = FALSE)

  output$low_enrl_download_ui <- renderUI({
    req(low_enrl_data())
    downloadLink("low_enrl_download", "Download CSV", style = "font-size: 0.85em; color: #888;")
  })

  output$low_enrl_download <- downloadHandler(
    filename = function() {
      dept <- isolate(input$enrl_dept)
      term <- isolate(input$enrl_term)
      parts <- c("low_enrollment")
      if (!is.null(dept) && length(dept) > 0) parts <- c(parts, paste(dept, collapse = "-"))
      if (!is.null(term) && length(term) > 0) parts <- c(parts, paste(term, collapse = "-"))
      paste0(paste(c(parts, as.character(Sys.Date())), collapse = "_"), ".csv")
    },
    content = function(file) {
      combined <- .low_enrl_combined() %>%
        select(-any_of("history"))
      write.csv(combined, file, row.names = FALSE)
    }
  )


  #################################
  #         COURSE REPORT         #
  #################################

  # Reactive values for every manually computed Course Dynamics result. Keeping
  # them together makes scope invalidation complete when the course or campus
  # changes; otherwise a result can remain on screen under a new selection.
  course_report_data <- reactiveVal(NULL)
  cr_retention_data <- reactiveVal(NULL)
  cr_dept_retention_data <- reactiveVal(NULL)
  cr_college_retention_data <- reactiveVal(NULL)
  cr_course_retention_data <- reactiveVal(NULL)
  cr_impact_sequence_data <- reactiveVal(NULL)
  cr_impact_instructor_data <- reactiveVal(NULL)

  invalidate_course_dynamics_results <- function() {
    course_report_data(NULL)
    cr_retention_data(NULL)
    cr_dept_retention_data(NULL)
    cr_college_retention_data(NULL)
    cr_course_retention_data(NULL)
    cr_impact_sequence_data(NULL)
    cr_impact_instructor_data(NULL)
    invisible(NULL)
  }

  # Course Dynamics DFW authentication state. Named-instructor DFW content is
  # sensitive, so this gate is owned by Course Dynamics rather than Dept Trends.
  dfw_authenticated <- reactiveVal(FALSE)
  dfw_password <- trimws(Sys.getenv("CEDAR_DFW_PASSWORD", unset = ""))
  dfw_password_configured <- nzchar(dfw_password)

  create_password_gate_ui <- function(password_input_id, submit_button_id,
                                      message_text = "This section contains sensitive academic performance data and requires authentication. Enter the password below to continue.") {
    if (!isTRUE(dfw_password_configured)) {
      return(div(
        class = "alert alert-warning",
        style = "margin: 20px 0;",
        h5(icon("lock"), " Access Unavailable"),
        p("Instructor-level outcomes are disabled because CEDAR_DFW_PASSWORD is not configured. Course-level results remain available.")
      ))
    }
    div(
      class = "alert alert-warning",
      style = "margin: 20px 0;",
      h5(icon("lock"), " Access Restricted"),
      p(message_text),
      br(),
      div(
        style = "display: flex; gap: 10px; align-items: flex-start;",
        div(
          style = "flex: 1; max-width: 300px;",
          passwordInput(password_input_id, "", placeholder = "Enter password")
        ),
        actionButton(submit_button_id, "Access", class = "btn-primary",
                     style = "margin-top: 0px; white-space: nowrap;")
      )
    )
  }

  observeEvent(input$cr_dfw_submit_btn, {
    if (!isTRUE(dfw_password_configured)) {
      dfw_authenticated(FALSE)
      showNotification("Instructor outcomes are disabled until CEDAR_DFW_PASSWORD is configured.", type = "error", duration = 5)
    } else if (identical(input$cr_dfw_password, dfw_password)) {
      dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
    } else {
      showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
    }
  }, ignoreInit = TRUE)
  
  # Selecting a course prepares the workspace but does not run it. Manual and
  # linked analysis share cr_run below, avoiding a second execution path here.
  observeEvent(input$cr_course, {
    course <- input$cr_course
    req(course, nzchar(course))
    log_data_filter(session, "course_report_course", course)
    invalidate_course_dynamics_results()
  }, ignoreInit = TRUE)

  # Log campus filter changes
  observeEvent(input$cr_campus, {
    log_data_filter(session, "cr_campus", input$cr_campus)
    invalidate_course_dynamics_results()
  }, ignoreInit = TRUE)

  # Helper function for campus filtering
  get_campus_filter <- function() {
    if (!is.null(input$cr_campus) && length(input$cr_campus) > 0) {
      return(list(
        column = "campus",  # CEDAR column name
        values = input$cr_campus
      ))
    }
    return(NULL)
  }
  
  # Helper function for rollcall pie charts (fall/spring)
  # Reduces 40+ lines of repeated code to single function calls
  render_rollcall_pie_plot <- function(data_table_name, fill_column, term_type, plot_name) {
    data <- course_report_data()
    cedar_debug("[server.R] ", plot_name, " renderer called")

    if (!is.null(data) && "tables" %in% names(data) && data_table_name %in% names(data$tables)) {

      campus_filter <- get_campus_filter()
      if (!is.null(campus_filter)) {
        cedar_debug("[server.R] Regenerating plots with campus filter for ", plot_name, ": ", paste(campus_filter$values, collapse = ", "))
      }

      plots <- plot_demographics_with_consistent_colors(
        data$tables[[data_table_name]],
        fill_column,
        filter_column = campus_filter
      )

      if (!is.null(plots[[term_type]])) {
        return(plots[[term_type]])
      }
    }

    return(NULL)
  }
  
  # Helper function for rollcall time series plots
  # Reduces 25+ lines of repeated code to single function calls
  render_rollcall_time_plot <- function(data_table_name, fill_column, plot_name) {
    data <- course_report_data()
    cedar_debug("[server.R] ", plot_name, " renderer called")

    if (!is.null(data) && "tables" %in% names(data) && data_table_name %in% names(data$tables)) {

      campus_filter <- get_campus_filter()
      if (!is.null(campus_filter)) {
        cedar_debug("[server.R] Regenerating time series with campus filter for ", plot_name, ": ", paste(campus_filter$values, collapse = ", "))
      }

      rollcall_data <- data$tables[[data_table_name]]
      if (!is.null(campus_filter)) {
        rollcall_data <- rollcall_data %>%
          filter(!!sym(campus_filter$column) %in% campus_filter$values)
      }

      time_plot <- plot_time_series(rollcall_data, fill_column = fill_column)
      if (!is.null(time_plot)) {
        return(time_plot)
      }
    }

    return(NULL)
  }
  
  # Helper function for rollcall data tables
  # Reduces 15+ lines of repeated code to single function calls
  render_rollcall_table <- function(data_table_name, table_name) {
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables[[data_table_name]])) {
      
      # Get campus filter and apply to table data
      campus_filter <- get_campus_filter()
      table_data <- data$tables[[data_table_name]]
      if (!is.null(campus_filter)) {
        table_data <- table_data %>%
          filter(!!sym(campus_filter$column) %in% campus_filter$values)
        cedar_debug("[server.R] Applied campus filter for ", table_name, ": ", paste(campus_filter$values, collapse = ", "))
      }
      
      return(table_data)
    }
    return(NULL)
  }

  output$cr_rollcall_scope_note <- renderUI({
    campus_filter <- get_campus_filter()
    scope_label <- if (is.null(campus_filter)) {
      "all delivery campuses"
    } else {
      paste(campus_filter$values, collapse = ", ")
    }
    div(
      class = "alert alert-info alert-compact",
      tags$strong("Campus rollup: "),
      "Donuts and trend lines combine ", scope_label,
      " into one course composition. The detailed major table retains campus rows."
    )
  })


  # Shared helper — generates the Course Dynamics payload for a given course code.
  # Manual runs and deep-link autoruns both reach it through the Analyze button.
  run_course_report <- function(course) {
    req(course, nzchar(course))
    log_report_generation(session, "course_report", list(course = course))

    timer <- start_report_timer("course_report", list(course = course))

    tryCatch({
      opt <- list(
        shiny = TRUE,
        course = course,
        course_campus = if (length(input$cr_campus) > 0) input$cr_campus else NULL
      )
      cedar_debug("[server.R] Generating interactive report data for: ", course)
      c_params <- create_course_base_data(data_objects, opt)

      duration_sec <- end_report_timer(timer)
      course_report_data(c_params)
      cr_load_tab(isolate(input$cr_tabs), c_params)
      signal_load_complete(session, "cr", duration_sec = duration_sec)
    }, error = function(e) {
      signal_load_complete(session, "cr", error = TRUE)
      handle_error(e, "course_report")
      tryCatch(end_report_timer(timer), error = function(te) NULL)
    })
  }

  # Manual and linked runs share one event source and one report path.
  cr_run <- cedar_run_trigger(input, session, "cr_generate_button", "Course Dynamics")
  observeEvent(cr_run(), {
    course <- input$cr_course
    req(course, nzchar(course))
    course_report_data(NULL)
    run_course_report(course)
  }, ignoreInit = TRUE)

  with_cr_tab_loading <- function(message_text, expr) {
    showNotification(message_text, type = "message", duration = NULL, id = "cr_tab_loading")
    on.exit(removeNotification("cr_tab_loading"), add = TRUE)
    force(expr)
  }

  # Shared helper — compute one tab's data and merge it into course_report_data().
  # Called from both the tab-click observer and the "Analyze Course" handler
  # (for the case where the user was already on a non-Enrollment tab).
  cr_load_tab <- function(tab, base = course_report_data()) {
    if (is.null(base) || is.null(tab)) return()

    if (tab == "Course Flows" && !isTRUE(base$flows_loaded)) {
      flow_payload <- with_cr_tab_loading(
        "Computing course flows...",
        compute_cr_flows_tab(base, data_objects)
      )
      base$plots <- c(base$plots, flow_payload$plots)
      base$tables <- c(base$tables, flow_payload$tables)
      base$flows_loaded <- TRUE
      course_report_data(base)

    }

    # Outcomes (dfw_trend, instructor_dfw, persistence) are needed by both the
    # DFW and Retention tabs.
    if (tab %in% c("DFW", "Retention")) {
      base <- course_report_data() %||% base
      if (is.null(base$outcomes)) {
        outcomes <- with_cr_tab_loading(
          "Computing outcomes...",
          compute_cr_outcomes_tab(base, data_objects)
        )
        base$outcomes <- outcomes
        course_report_data(base)
      }
    }
  }

  # Lazy-load per-tab data when user clicks a Course Dynamics tab for the first time.
  observeEvent(input$cr_tabs, {
    cr_load_tab(input$cr_tabs)
  }, ignoreInit = TRUE)

  # "Update Flow Diagrams" button — recompute Sankey with current min/max settings.
  observeEvent(input$cr_update_flows, {
    base <- course_report_data()
    req(!is.null(base))
    min_contrib <- as.integer(input$cr_flow_min_contrib %||% 2L)
    max_courses <- as.integer(input$cr_flow_max_courses %||% 6L)
    base$opt$course_campus <- if (length(input$cr_campus) > 0) input$cr_campus else NULL
    flow_payload <- with_cr_tab_loading(
      "Recomputing flow diagrams...",
      compute_cr_flows_tab(base, data_objects, min_contrib = min_contrib, max_courses = max_courses)
    )
    existing <- base$plots[
      !grepl("^sankey_|^concurrent_treemap_plot$", names(base$plots))
    ]
    base$plots <- c(existing, flow_payload$plots)
    base$tables$concurrent_courses <- flow_payload$tables$concurrent_courses
    base$flows_loaded <- TRUE
    course_report_data(base)
  }, ignoreInit = TRUE)

  # NOTE: output$cr_report (a legacy full-page course report renderer) was
  # removed 2026-08-01. It was defined here but referenced by no UI — the
  # Course Dynamics nav_panels render their own outputs directly. It carried a
  # duplicate copy of the Student Flow description and the only references to
  # cr_rollcall_class_table / cr_rollcall_major_table, which are also unused.

  # Render individual Course Dynamics plot outputs. Overview term choices are
  # derived from the assembled payload and reset only when the course changes.
  observeEvent({
    data <- course_report_data()
    if (is.null(data)) NULL else data$course_code
  }, {
    data <- course_report_data()
    req(!is.null(data$overview))
    available <- course_overview_term_types(data$overview)
    req(length(available) > 0)
    labels <- c(all = "All", fall = "Fall", spring = "Spring", summer = "Summer")
    current_term <- if (exists("cedar_current_term")) cedar_current_term else NULL
    selected <- default_course_overview_term_type(data$overview, current_term)
    updateRadioButtons(
      session,
      "cr_overview_term_type",
      choices = stats::setNames(c("all", available), labels[c("all", available)]),
      selected = selected,
      inline = TRUE
    )
  }, ignoreInit = TRUE)

  cr_overview_data <- reactive({
    data <- course_report_data()
    if (is.null(data) || is.null(data$overview)) return(NULL)
    filter_course_overview(
      data$overview,
      campuses = input$cr_campus,
      term_type = input$cr_overview_term_type
    )
  })

  cr_enrollment_lifecycle_data <- reactive({
    data <- course_report_data()
    if (is.null(data) || is.null(data$overview)) return(NULL)
    filter_course_overview(data$overview, campuses = input$cr_campus)$lifecycle
  })

  output$cr_overview_scope_note <- renderUI({
    overview <- cr_overview_data()
    req(!is.null(overview))
    selected_type <- input$cr_overview_term_type %||% "all"
    type_label <- if (identical(selected_type, "all")) {
      "All term types"
    } else {
      paste0(stringr::str_to_title(selected_type), " terms")
    }
    campuses <- sort(unique(c(
      overview$lifecycle$campus %||% character(0),
      overview$sections$campus %||% character(0)
    )))
    tags$p(
      class = "cedar-body text-hint",
      tags$strong(paste0(type_label, ";")),
      paste0(" campuses shown separately: ", paste(campuses, collapse = ", "), ".")
    )
  })

  output$cr_overview_metrics <- renderUI({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$overview))
    snapshot <- course_overview_snapshot(
      data$overview,
      campuses = input$cr_campus,
      term_type = input$cr_overview_term_type
    )
    req(nrow(snapshot) > 0)

    fmt_count <- function(x, digits = 0) {
      if (length(x) == 0 || is.na(x)) return("\u2014")
      format(round(x, digits), big.mark = ",", nsmall = digits, trim = TRUE)
    }
    fmt_changes <- function(item, metric) {
      values <- vapply(1:3, function(years_back) {
        col <- paste0(metric, "_change_", years_back, "y")
        if (!col %in% names(item)) return(NA_real_)
        suppressWarnings(as.numeric(item[[col]][[1]]))
      }, numeric(1))
      htmltools::tagList(lapply(1:3, function(years_back) {
        value <- values[[years_back]]
        label <- if (is.na(value)) {
          "n/a"
        } else {
          paste0(
            if (value >= 0) "+" else "",
            formatC(value, format = "f", digits = 1), "%"
          )
        }
        tags$span(
          class = "stat-change-line",
          paste0(years_back, " yr: ", label)
        )
      }))
    }

    rows <- lapply(seq_len(nrow(snapshot)), function(i) {
      item <- snapshot[i, , drop = FALSE]
      div(
        class = "stat-row course-overview-stat-row",
        div(
          class = "stat-row-label",
          paste0(item$campus, " \u00b7 ", fmt_term(item$term))
        ),
        div(
          class = "course-overview-card-grid",
          cedar_stat_card(fmt_count(item$census_enrl), "Census enrollment", fmt_changes(item, "census_enrl")),
          cedar_stat_card(fmt_count(item$current_enrl), "Current enrollment", fmt_changes(item, "current_enrl")),
          cedar_stat_card(fmt_count(item$sections), "Active sections", fmt_changes(item, "sections")),
          cedar_stat_card(fmt_count(item$avg_section_size, 1), "Avg section size", fmt_changes(item, "avg_section_size")),
          cedar_stat_card(fmt_count(item$early_drops), "Early drops", fmt_changes(item, "early_drops")),
          cedar_stat_card(fmt_count(item$late_drops), "Late drops", fmt_changes(item, "late_drops")),
          cedar_stat_card(fmt_count(item$waitlisted), "Waitlisted", fmt_changes(item, "waitlisted"))
        )
      )
    })
    do.call(tagList, rows)
  })

  output$cr_overview_enrollment_plot <- renderPlotly({
    overview <- cr_overview_data()
    req(!is.null(overview))
    plot <- build_course_enrollment_history_plot(overview$lifecycle)
    req(!is.null(plot))
    plot
  })

  output$cr_overview_sections_plot <- renderPlotly({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$overview))
    plot <- build_course_overview_metric_plot(
      data$overview,
      source = "sections",
      metric = "sections",
      y_label = "Active sections",
      term_type = input$cr_overview_term_type,
      campuses = input$cr_campus
    )
    req(!is.null(plot))
    plot
  })

  output$cr_overview_avg_size_plot <- renderPlotly({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$overview))
    plot <- build_course_overview_metric_plot(
      data$overview,
      source = "sections",
      metric = "avg_section_size",
      y_label = "Average section size",
      term_type = input$cr_overview_term_type,
      campuses = input$cr_campus
    )
    req(!is.null(plot))
    plot
  })

  output$cr_enrollment_pressure_plot <- renderPlotly({
    plot <- build_course_enrollment_history_plot(cr_enrollment_lifecycle_data())
    req(!is.null(plot))
    plot
  })

  output$cr_enrollment_drop_plot <- renderPlotly({
    plot <- build_course_drop_plot(cr_enrollment_lifecycle_data())
    req(!is.null(plot))
    plot
  })

  output$cr_flow_scope_note <- renderUI({
    campus_vals <- input$cr_campus
    campus_text <- if (!is.null(campus_vals) && length(campus_vals) > 0) {
      paste(campus_vals, collapse = ", ")
    } else {
      "all campuses"
    }

    tags$p(
      class = "cedar-body text-hint",
      tags$strong("Current scope: "),
      paste0(
        "campus = ", campus_text,
        ". Counts use registered class-list rows (RE/RS/RR); waitlists and drops are excluded."
      ),
      tags$br(),
      cedar_longitudinal_edge_note(
        data_objects[["cedar_edges"]], grade_dependent = FALSE
      )
    )
  })

  output$cr_concurrent_treemap_plot <- renderPlotly({
    data <- course_report_data()
    req(
      !is.null(data),
      !is.null(data$plots),
      !is.null(data$plots$concurrent_treemap_plot)
    )
    data$plots$concurrent_treemap_plot
  })

  output$cr_concurrent_courses_ui <- renderUI({
    data <- course_report_data()
    if (is.null(data) || !isTRUE(data$flows_loaded)) {
      return(tags$p("Open Course Flows to compute same-term course patterns.",
                    class = "text-hint"))
    }

    concurrent <- data$tables$concurrent_courses
    if (is.null(concurrent) || nrow(concurrent) == 0L) {
      return(empty_state(
        "No other registered courses were found in the same campus and term."
      ))
    }

    fluidRow(
      column(7, plotlyOutput("cr_concurrent_treemap_plot", height = "520px")),
      column(5, reactable::reactableOutput("cr_concurrent_courses_table"))
    )
  })

  # Generate UI for flow plots
  output$cr_flow_plots_ui <- renderUI({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data)) {
      sankey_plot_names <- names(data$plots)[grepl("sankey_.*_plot", names(data$plots))]
      
      if (length(sankey_plot_names) > 0) {
        plot_list <- list()
        
        for (plot_name in sankey_plot_names) {
          term_type <- gsub("sankey_(.*)_plot", "\\1", plot_name)
          output_name <- paste0("cr_sankey_", term_type, "_plot")
          
          # One diagram per term type. dashboard_subsection() rather than a bare
          # h5 so these headings match every other block on the tab.
          plot_list[[length(plot_list) + 1]] <- dashboard_subsection(
            paste(stringr::str_to_title(term_type), "Terms"),
            paste0("Courses taken before, after, and alongside this one in ",
                   term_type, " terms. Band thickness is average students per term."),
            plotlyOutput(output_name, height = "500px")
          )
        }
        
        do.call(tagList, plot_list)
      } else {
        p("No flow data available for this course.", style = "color: #666;")
      }
    } else {
      p("Generate a report to see student flow diagrams.", style = "color: #666;")
    }
  })

  # Render sankey plots dynamically
  observe({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data)) {
      sankey_plot_names <- names(data$plots)[grepl("sankey_.*_plot", names(data$plots))]
      
      for (plot_name in sankey_plot_names) {
        term_type <- gsub("sankey_(.*)_plot", "\\1", plot_name)
        output_name <- paste0("cr_sankey_", term_type, "_plot")
        
        # Use local() to capture the current values
        local({
          current_plot_name <- plot_name
          output[[output_name]] <- renderPlotly({
            current_data <- course_report_data()
            if (!is.null(current_data) && "plots" %in% names(current_data) && current_plot_name %in% names(current_data$plots)) {
              current_data$plots[[current_plot_name]]
            }
          })
        })
      }
    }
  })

  cr_cedar_reactable <- function(d, columns = list(), default_page_size = 15L,
                                 default_sorted = NULL, searchable = TRUE) {
    reactable::reactable(
      d,
      theme               = cedar_tbl_theme,
      striped             = TRUE,
      highlight           = TRUE,
      compact             = TRUE,
      searchable          = searchable,
      defaultPageSize     = default_page_size,
      showPageSizeOptions = TRUE,
      pageSizeOptions     = c(10, 15, 25, 50),
      defaultSorted       = default_sorted,
      columns             = columns[intersect(names(columns), names(d))]
    )
  }
  cr_dfw_reactable <- cr_cedar_reactable

  cr_title_case <- function(x) {
    tools::toTitleCase(gsub("_", " ", x))
  }

  cr_humanize_columns <- function(d) {
    if (is.null(d)) return(NULL)
    label_lookup <- c(
      campus = "Campus",
      college = "College",
      term = "Term",
      year = "Year",
      term_type = "Term Type",
      subject_course = "Course",
      course_title = "Course Title",
      registered = "Current Enrollment",
      census_enrl = "Census Enrollment",
      registered_mean = "Current Enrl Avg",
      cl_total = "Classlist Total",
      cl_total_mean = "Classlist Total Avg",
      dr_early = "Early Drops",
      dr_early_mean = "Early Drop Avg",
      dr_late = "Late Drops",
      dr_late_mean = "Late Drop Avg",
      dr_all = "All Drops",
      dr_all_mean = "All Drop Avg",
      student_classification = "Classification",
      major_code = "Major Code",
      major_name = "Major",
      n = "Students",
      pct = "Percent",
      dfw_pct = "DFW %",
      passed = "Passed",
      failed = "Non-Passing",
      early_dropped = "Early Drops",
      late_dropped = "Late Drops",
      covariate = "Covariate",
      type = "Type",
      n_treatment = "Treatment N",
      n_control = "Control N",
      value_treatment = "Treatment Value",
      value_control = "Control Value",
      unit = "Unit",
      smd = "SMD",
      group = "Group",
      outcome = "Outcome",
      n = "Students",
      pct = "Percent",
      mean_cum_gpa = "Mean Cum GPA (entering)",
      mean_current_gpa = "Mean Current UNM GPA",
      mean_hs_gpa = "Mean HS GPA",
      mean_act = "Mean ACT",
      mean_credits_earned = "Mean Credits Earned",
      n_total_in_x = "Students in X",
      students_taking_x = "Students Taking X",
      passed_y_before_x = "Passed Y Before X",
      passed_y_same_term = "Passed Y Same Term",
      passed_y_before_or_same = "Passed Y Before or Same",
      pct_before_or_same = "% Before or Same",
      n_took_y = "Took Y",
      pct_took_y = "% Took Y",
      n_pass = "Passed",
      pct_pass = "% Passed",
      n_failed = "Failed",
      pct_failed = "% Failed",
      n_dropped = "Late Drops",
      pct_dropped = "% Late Drops",
      pct_dfw = "DFW %",
      selected_course = "Selected Course",
      coenrolled_student_terms = "Co-enrolled Student-Terms",
      target_student_terms = "Selected-Course Student-Terms",
      target_terms = "Selected-Course Terms",
      avg_students_per_target_term = "Average Students per Term",
      pct_selected_student_terms = "% Taking Both"
    )
    labels <- unname(label_lookup[names(d)])
    missing_labels <- is.na(labels)
    labels[missing_labels] <- cr_title_case(names(d)[missing_labels])
    names(d) <- labels
    d
  }

  cr_basic_reactable <- function(d, default_page_size = 10L, searchable = TRUE,
                                 default_sorted = NULL) {
    if (is.null(d) || nrow(d) == 0) return(NULL)
    pct_cols <- grep("%|Percent|Pct", names(d), value = TRUE)
    avg_cols <- grep("Avg|Average|Mean", names(d), value = TRUE)
    numeric_cols <- setdiff(
      names(d)[vapply(d, is.numeric, logical(1))],
      c("Term", "Year")
    )
    columns <- stats::setNames(
      lapply(names(d), function(col) {
        if (col %in% pct_cols) {
          reactable::colDef(
            align = "right",
            format = reactable::colFormat(digits = 1, suffix = "%")
          )
        } else if (col %in% avg_cols) {
          reactable::colDef(
            align = "right",
            format = reactable::colFormat(digits = 1)
          )
        } else if (col %in% numeric_cols) {
          reactable::colDef(
            align = "right",
            format = reactable::colFormat(digits = 0, separators = TRUE)
          )
        } else {
          reactable::colDef(minWidth = if (col %in% c("Course Title", "Major")) 180 else 90)
        }
      }),
      names(d)
    )
    cr_cedar_reactable(
      d,
      columns = columns,
      default_page_size = default_page_size,
      default_sorted = default_sorted,
      searchable = searchable
    )
  }

  cr_pct_count_coldef <- function(counts) {
    force(counts)
    reactable::colDef(
      align = "right",
      minWidth = 125,
      cell = function(value, index) {
        count <- counts[[index]]
        if (is.na(value) || is.na(count)) return("—")
        tags$span(
          class = "text-nowrap",
          paste0(
            formatC(value, format = "f", digits = 1), "% (",
            format(as.integer(count), big.mark = ",", scientific = FALSE,
                   trim = TRUE),
            ")"
          )
        )
      }
    )
  }

  # Render Course Dynamics data tables
  output$cr_concurrent_courses_table <- reactable::renderReactable({
    data <- course_report_data()
    if (is.null(data) || is.null(data$tables$concurrent_courses)) return(NULL)

    table_data <- data$tables$concurrent_courses %>%
      dplyr::select(
        campus,
        subject_course,
        college,
        coenrolled_student_terms,
        pct_selected_student_terms,
        avg_students_per_target_term,
        target_terms
      )

    cr_basic_reactable(
      cr_humanize_columns(table_data),
      default_page_size = 20L,
      searchable = FALSE,
      default_sorted = list("% Taking Both" = "desc")
    )
  })

  output$cr_enrollment_table <- reactable::renderReactable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$cl_enrls)) {
      cl_enrls_data <- data$tables$cl_enrls

      campus_vals <- input$cr_campus
      if (!is.null(campus_vals) && length(campus_vals) > 0) {
        cl_enrls_data <- cl_enrls_data %>% filter(campus %in% campus_vals)
      }

      cl_enrls_data <- cl_enrls_data %>%
        add_census_enrl() %>%
        ungroup() %>%
        select(
        campus,
        college,
        term,
        term_type,
        subject_course,
        registered,
        census_enrl,
        registered_mean,
        cl_total,
        cl_total_mean,
        dr_early,
        dr_early_mean,
        dr_late,
        dr_late_mean,
        dr_all,
        dr_all_mean
      ) %>% arrange(subject_course, campus, term)

      return(cr_basic_reactable(
        cr_humanize_columns(cl_enrls_data),
        default_page_size = 15L,
        searchable = TRUE
      ))
    }
    return(NULL)
  })
  



  output$cr_rollcall_by_class_plot <- renderPlotly({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_class_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_class_plot
      if (!is.null(plots$fall))   return(plots$fall)
      if (!is.null(plots$spring)) return(plots$spring)
      if (!is.null(plots$main))   return(plots$main)
    }
    return(NULL)
  })
  
  output$cr_rollcall_by_class_other_plot <- renderPlotly({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_class_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_class_plot
      if (!is.null(plots$spring)) return(plots$spring)
      if (!is.null(plots$summer)) return(plots$summer)
    }
    return(NULL)
  })


  output$cr_rollcall_by_major_plot <- renderPlotly({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_major_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_major_plot
      if (!is.null(plots$fall))   return(plots$fall)
      if (!is.null(plots$spring)) return(plots$spring)
      if (!is.null(plots$main))   return(plots$main)
    }
    return(NULL)
  })
  
  output$cr_rollcall_by_major_other_plot <- renderPlotly({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_major_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_major_plot
      if (!is.null(plots$spring)) return(plots$spring)
      if (!is.null(plots$summer)) return(plots$summer)
    }
    return(NULL)
  })

  
  # ================================================================================
  # ROLLCALL PLOT OUTPUTS with separate fall and spring rollcall plots for side-by-side display
  # ================================================================================
  
  # Fall classification plot with campus filtering
  output$cr_rollcall_by_class_fall_plot <- renderPlotly({
    render_rollcall_pie_plot("rollcall_by_class_plot_data", "student_classification", "fall", "fall classification plot")
  })
  
  # Spring classification plot with campus filtering
  output$cr_rollcall_by_class_spring_plot <- renderPlotly({
    render_rollcall_pie_plot("rollcall_by_class_plot_data", "student_classification", "spring", "spring classification plot")
  })
  
  # Fall major plot with campus filtering
  output$cr_rollcall_by_major_fall_plot <- renderPlotly({
    render_rollcall_pie_plot("rollcall_by_major_plot_data", "major_code", "fall", "fall major plot")
  })

  # Spring major plot with campus filtering
  output$cr_rollcall_by_major_spring_plot <- renderPlotly({
    render_rollcall_pie_plot("rollcall_by_major_plot_data", "major_code", "spring", "spring major plot")
  })

  # Classification time series plot with campus filtering
  output$cr_rollcall_by_class_time_plot <- renderPlotly({
    render_rollcall_time_plot("rollcall_by_class_plot_data", "student_classification", "classification time series")
  })

  # Major time series plot with campus filtering
  output$cr_rollcall_by_major_time_plot <- renderPlotly({
    render_rollcall_time_plot("rollcall_by_major_plot_data", "major_code", "major time series")
  })
  
  # The by-classification rollcall tables were removed from the Rollcall subtab:
  # they pivot one column per term (very wide) to restate what the classification
  # donut and trend chart already show. The by-classification data is still
  # rendered on the Detailed Data panel (cr_rollcall_class_table).

  # Single major table (combining all terms) with campus filtering
  output$cr_rollcall_major_fall_table <- reactable::renderReactable({
    cr_basic_reactable(
      cr_humanize_columns(render_rollcall_table("rollcall_by_major", "major table")),
      default_page_size = 10L
    )
  })


  # Passing grades vector for DFW calculation — driven by cr_dfw_threshold input.
  # "below_c": canonical default — A+ through C and CR pass.
  # "f_only": legacy input id retained for bookmarked URLs; explicitly opts in
  # to adding C- and D-range grades to passing. P/S remain nonpassing.
  dfw_passing_grades <- reactive({
    threshold <- input$cr_dfw_threshold %||% "below_c"
    if (identical(threshold, "f_only")) {
      GRADES_PASS_SUB_C_OPT_IN
    } else {
      GRADES_PASS
    }
  })

  cr_dfw_status_exclusions_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$opt))
    d <- summarize_outcome_status_exclusions(data_objects[["cedar_students"]], data$opt)
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter) && nrow(d) > 0) {
      d <- d %>% filter(campus %in% campus_filter$values)
    }
    d
  })

  cr_dfw_by_term_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$opt))
    opt <- data$opt
    opt$passing_grades <- dfw_passing_grades()
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) opt$course_campus <- campus_filter$values

    get_course_outcome_rates(
      data_objects[["cedar_students"]],
      opt = opt,
      group_cols = c("campus", "college", "term", "subject_course"),
      min_n = 1L
    )
  })

  cr_dfw_demographics_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$opt))
    students <- data_objects[["cedar_students"]]
    opt <- data$opt
    opt$passing_grades <- dfw_passing_grades()
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) opt$course_campus <- campus_filter$values

    major_col <- if ("major_name" %in% names(students)) {
      "major_name"
    } else if ("major" %in% names(students)) {
      "major"
    } else {
      NA_character_
    }

    list(
      classification = if ("student_classification" %in% names(students)) {
        get_course_dfw_demographics(
          students, opt,
          group_col = "student_classification",
          min_n = 1L
        )
      } else {
        tibble()
      },
      major = if (!is.na(major_col)) {
        get_course_dfw_demographics(
          students, opt,
          group_col = major_col,
          min_n = 1L,
          max_groups = 25L
        )
      } else {
        tibble()
      }
    )
  })

  cr_dfw_context_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), !is.null(data$opt))
    opt <- data$opt
    opt$passing_grades <- dfw_passing_grades()
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) opt$course_campus <- campus_filter$values

    get_course_dfw_context(
      data_objects[["cedar_students"]],
      opt = opt,
      min_cell = 5L
    )
  })

  # DFW by term plot
  output$dfw_by_term_plot <- renderPlotly({
    d <- cr_dfw_by_term_reactive()
    req(!is.null(d), nrow(d) > 0)

    td <- d %>%
      dplyr::arrange(term, campus, subject_course) %>%
      dplyr::mutate(
        term_label = term_code_to_axis_label(term),
        attempts = n_attempts,
        dfw_rate = dfw_pct,
        late_withdrawal_rate = dplyr::if_else(
          n_attempts > 0,
          round(100 * n_w / n_attempts, 1),
          NA_real_
        ),
        early_drop_rate = dplyr::if_else(
          n_attempts + n_early_drop > 0,
          round(100 * n_early_drop / (n_attempts + n_early_drop), 1),
          NA_real_
        )
      )

    term_levels <- unique(td$term_label)
    campuses <- sort(unique(td$campus))
    metrics <- tibble::tribble(
      ~metric, ~label, ~color, ~dash,
      "dfw_rate", "DFW %", "#7a2e2e", "solid",
      "late_withdrawal_rate", "Late withdrawal %", "#b06b2f", "dot",
      "early_drop_rate", "Early drop %", "#486f84", "dash"
    )

    p <- plotly::plot_ly()
    for (camp in campuses) {
      cd <- td %>% dplyr::filter(campus == camp)
      for (i in seq_len(nrow(metrics))) {
        metric <- metrics$metric[[i]]
        label <- metrics$label[[i]]
        trace_name <- if (length(campuses) > 1) paste(camp, label) else label
        cd_metric <- cd
        cd_metric$.value <- cd_metric[[metric]]
        cd_metric <- cd_metric %>%
          dplyr::filter(!is.na(.value)) %>%
          dplyr::arrange(term)
        if (nrow(cd_metric) == 0) next

        p <- plotly::add_trace(
          p,
          x = cd_metric$term_label,
          y = cd_metric$.value,
          type = "scatter",
          mode = "lines+markers",
          name = trace_name,
          legendgroup = label,
          line = list(color = metrics$color[[i]], dash = metrics$dash[[i]],
                      width = 3, shape = "linear"),
          marker = list(color = metrics$color[[i]], size = 6),
          customdata = paste0(
            "Attempts: ", cd_metric$attempts,
            "<br>DFW count: ", cd_metric$n_dfw,
            "<br>Late withdrawals: ", cd_metric$n_w,
            "<br>Early drops: ", cd_metric$n_early_drop
          ),
          hovertemplate = paste0(
            "Term: %{x}<br>Campus: ", camp,
            "<br>", label, ": %{y:.1f}%",
            "<br>%{customdata}<extra></extra>"
          )
        )
      }
    }

    p %>% plotly::layout(
      xaxis = list(title = "Term", tickangle = -45,
                   categoryorder = "array",
                   categoryarray = term_levels),
      yaxis = list(title = "Rate %"),
      legend = list(orientation = "h", x = 0, y = 1.12,
                    xanchor = "left", yanchor = "bottom"),
      margin = list(t = 60, b = 80)
    )
  })

  output$dfw_instructor_summary_plot <- renderPlotly({
    req(dfw_authenticated())
    data <- course_report_data()
    req(!is.null(data), !is.null(data$outcomes), !is.null(data$outcomes$instructor_dfw))
    d <- data$outcomes$instructor_dfw
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) d <- d %>% dplyr::filter(campus %in% campus_filter$values)
    multi_campus <- dplyr::n_distinct(d$campus) > 1L
    d <- d %>%
      dplyr::filter(!is.na(instructor_name), instructor_name != "", !is.na(dfw_diff)) %>%
      dplyr::arrange(dfw_diff, instructor_name) %>%
      dplyr::mutate(
        instructor_label = if (multi_campus) {
          paste0(instructor_name, " (", campus, ")")
        } else {
          instructor_name
        },
        instructor_label = factor(instructor_label, levels = unique(instructor_label)),
        direction = ifelse(dfw_diff >= 0, "Above course average", "Below course average"),
        bar_color = ifelse(dfw_diff >= 0, "#7a2e2e", "#2f6f5e")
      )
    req(nrow(d) > 0)

    plotly::plot_ly(
      data = d,
      x = ~dfw_diff,
      y = ~instructor_label,
      type = "bar",
      orientation = "h",
      marker = list(color = d$bar_color),
      customdata = paste0(
        "Instructor DFW: ", round(d$dfw_pct, 1), "%",
        "<br>Course average: ", round(d$course_avg_dfw, 1), "%",
        "<br>Attempts: ", d$n_attempts,
        "<br>DFW count: ", d$n_dfw
      ),
      hovertemplate = paste0(
        "%{y}<br>Difference: %{x:.1f} percentage points",
        "<br>%{customdata}<extra></extra>"
      )
    ) %>%
      plotly::layout(
        xaxis = list(title = "Difference from course DFW average (percentage points)"),
        yaxis = list(title = "", automargin = TRUE),
        shapes = list(list(
          type = "line", x0 = 0, x1 = 0, y0 = 0, y1 = 1,
          xref = "x", yref = "paper",
          line = list(color = "#666666", width = 1, dash = "dot")
        )),
        margin = list(t = 25, b = 65, l = 140, r = 20),
        showlegend = FALSE
      )
  })

  # Course Dynamics DFW tab content
  output$cr_dfw_tab_content <- renderUI({
    tryCatch({

    data <- course_report_data()

    if (is.null(data)) {
      return(empty_state("Select a course, then click Analyze Course to view DFW data."))
    }

    {
      dfw_edge_note <- cedar_longitudinal_edge_note(
        data_objects[["cedar_edges"]], grade_dependent = TRUE
      )

      threshold <- input$cr_dfw_threshold %||% "below_c"
      tagList(
        subtab_header(
          "DFW",
          cedar_definition_summary("dfw"), " ",
          "The term chart plots DFW, late-withdrawal, and early-drop rates as ",
          "connected lines — read them together to see whether a high DFW rate is ",
          "students failing or students leaving. The box below sets what counts as ",
          "non-passing and shows the full grade and status rules."
        ),
        # Kept as an always-open box rather than folded away: it holds the
        # threshold control that drives every chart on the tab, not just prose.
        div(class = "alert alert-info", style = "font-size: 0.85em;",
          icon("circle-info"), " ",
          tags$strong("Data window: "), dfw_edge_note,
          tags$br(), tags$br(),
          tags$strong("What counts as non-passing?"),
          tags$span(style = "font-size: 0.85em; color: #555; margin-left: 8px;",
            "Affects all course-level charts and tables below."),
          radioButtons("cr_dfw_threshold", label = NULL,
            choices = c(
              "Standard: only A+ through C and CR pass; all other recorded outcomes count as DFW" = "below_c",
              "Opt in: also treat C−, D+, D, and D− as passing" = "f_only"
            ),
            selected = threshold,
            inline = FALSE
          )
        ),
        cedar_definition_panel("dfw", "How grades and registration statuses are counted"),
        dashboard_subsection(
          "DFW and Drop Rates by Term",
          "Tracks DFW, late-withdrawal, and early-drop rates as separate term lines. Late withdrawals count in DFW; early drops are shown separately because they are registration churn, not final course outcomes.",
          plotlyOutput("dfw_by_term_plot", height = "400px")
        ),
        uiOutput("cr_dfw_context_ui"),
        uiOutput("cr_dfw_demographics_ui"),
        hr(),
        dashboard_subsection(
          "DFW by Term",
          "Reference table for the term chart. Attempts exclude early drops, and DFW % uses the selected non-passing grade rule above.",
          uiOutput("cr_dfw_trend_ui")
        ),
        hr(),
        dashboard_subsection(
          "Restricted Instructor DFW",
          "Descriptive section outcomes by instructor, shown only behind authentication. These rows are for context and review, not causal instructor evaluation.",
          if (dfw_authenticated()) {
            tagList(
              plotlyOutput("dfw_instructor_summary_plot", height = "400px"),
              uiOutput("cr_instructor_dfw_ui")
            )
          } else {
            create_password_gate_ui(
              "cr_dfw_password",
              "cr_dfw_submit_btn",
              "Instructor-level DFW data requires authentication. Course-level DFW rates and methodology remain visible above."
            )
          }
        )
      )
    }
  }, error = function(e) {
    write_log("ERROR", "cr_dfw_tab_content",
              list(error = conditionMessage(e)), session$token)
    div(class = "alert alert-danger", class = "m-4",
      icon("circle-exclamation"), " ",
      "Error rendering DFW tab: ", conditionMessage(e))
  }) # end tryCatch
  }) # end renderUI cr_dfw_tab_content

  output$cr_dfw_trend_ui <- renderUI({
    by_term <- cr_dfw_by_term_reactive()
    if (is.null(by_term))
      return(p("Loading...", class = "text-muted"))
    status_exclusions <- cr_dfw_status_exclusions_reactive()
    status_note <- NULL
    if (!is.null(status_exclusions) && nrow(status_exclusions) > 0) {
      has_grade_signal <- any(status_exclusions$nonblank_grade_rows > 0, na.rm = TRUE)
      status_note <- div(
        class = if (has_grade_signal) "alert alert-warning" else "alert alert-info",
        style = "font-size: 0.85em;",
        icon(if (has_grade_signal) "triangle-exclamation" else "circle-info"), " ",
        tags$strong("Excluded registration status rows found."), " ",
        "The DFW table only counts registered rows and official drops. ",
        "Rows with other status codes are excluded and summarized below. ",
        if (has_grade_signal) {
          tags$span(
            tags$strong("At least one excluded row has a nonblank final grade; "),
            "review those rows before interpreting this course's DFW history."
          )
        } else {
          "No excluded rows have nonblank final grades."
        },
        reactable::reactableOutput("cr_dfw_status_exclusions")
      )
    }
    if (nrow(by_term) == 0)
      tagList(
        status_note,
        p("No DFW trend data available for this course.", class = "text-muted")
      )
    else
      tagList(
        status_note,
        info_panel(
          "Explain Columns",
          tags$ul(
            tags$li(tags$b("Campus / College / Term / Course"), ": the course offering represented by the row."),
            tags$li(tags$b("Attempts"), ": passed records, non-passing grade records, and late withdrawals; early drops are excluded."),
            tags$li(tags$b("Passed"), ": records counted as passing under the selected grade rule."),
            tags$li(tags$b("Non-Passing Grades"), ": grade outcomes counted as unsuccessful under the selected grade rule."),
            tags$li(tags$b("Late Withdrawals"), ": W outcomes after the add/drop period; these count in DFW."),
            tags$li(tags$b("DFW Count"), ": Non-Passing Grades plus Late Withdrawals."),
            tags$li(tags$b("DFW %"), ": DFW Count divided by Attempts."),
            tags$li(tags$b("Early Drops"), ": DR/DD drops before the grade-consequence deadline; shown separately and excluded from DFW.")
          ),
          description = "How to read the DFW by term table."
        ),
        reactable::reactableOutput("cr_outcomes_dfw_trend")
      )
  })

  output$cr_dfw_demographics_ui <- renderUI({
    demo <- cr_dfw_demographics_reactive()
    has_class <- !is.null(demo$classification) && nrow(demo$classification) > 0
    has_major <- !is.null(demo$major) && nrow(demo$major) > 0

    if (!has_class && !has_major) {
      return(NULL)
    }

    dfw_demo_column_guide <- function(group_label) {
      info_panel(
        "Explain columns",
        tags$ul(
          tags$li(tags$b(group_label), ": the student group represented by the row."),
          tags$li(tags$b("Attempts"), ": passed records, non-passing grade records, and late withdrawals. Early drops are not included."),
          tags$li(tags$b("DFW Count"), ": non-passing grades plus late withdrawals for the group."),
          tags$li(tags$b("DFW %"), ": DFW Count divided by Attempts; this is the group's own rate."),
          tags$li(tags$b("Share of DFW"), ": the group's DFW Count divided by all DFW outcomes in the selected course."),
          tags$li(tags$b("Late Withdrawals"), ": late drop/withdrawal outcomes counted in DFW."),
          tags$li(tags$b("Early Drops"), ": DR/DD early drops, shown separately and excluded from DFW.")
        ),
        description = paste("How to read the", tolower(group_label), "DFW table.")
      )
    }

    tagList(
      hr(),
      dashboard_subsection(
        "Who Is DFWing?",
        "These tables show which student groups account for DFW outcomes in the selected course. Use DFW % to see risk within a group, and Share of DFW to see how much that group contributes to the course's total DFW count."
      ),
      if (has_class) {
        div(class = "mb-4",
          tags$h4(class = "cedar-dashboard-subsection-title cedar-dashboard-subsection-title--minor", "By Classification"),
          dfw_demo_column_guide("Classification"),
          reactable::reactableOutput("cr_dfw_demo_classification")
        )
      },
      if (has_major) {
        div(class = "mb-4",
          tags$h4(class = "cedar-dashboard-subsection-title cedar-dashboard-subsection-title--minor", "By Major"),
          dfw_demo_column_guide("Major"),
          reactable::reactableOutput("cr_dfw_demo_major")
        )
      }
    )
  })

  output$cr_dfw_context_ui <- renderUI({
    ctx <- cr_dfw_context_reactive()
    if (is.null(ctx)) return(NULL)

    if (isTRUE(ctx$suppressed)) {
      return(tagList(
        hr(),
        dashboard_subsection(
          "DFW Term Context",
          "Shows whether DFW in this course appears isolated or part of broader same-term difficulty.",
          div(
            class = "alert alert-info alert-compact",
            icon("circle-info"), " ",
            ctx$suppression_reason %||%
              "DFW context is hidden because there are too few DFW student-terms."
          )
        )
      ))
    }

    d <- ctx$summary
    if (is.null(d) || nrow(d) == 0) return(NULL)

    tagList(
      hr(),
      dashboard_subsection(
        "DFW Term Context",
        "For students who DFW this course, this shows whether the selected course was their only DFW outcome that term or part of broader same-term difficulty.",
        info_panel(
          "How to read this",
          tags$ul(
            tags$li(tags$b("Unit counted"), ": one student in one term where they DFW the selected course. If the same student appears in multiple terms, each term is counted separately."),
            tags$li(tags$b("DFW only in this course"), ": the student passed all other classifiable course attempts that term."),
            tags$li(tags$b("Some broader difficulty"), ": the student had another DFW/non-pass outcome, but fewer than half of their classifiable attempts were DFW/non-pass."),
            tags$li(tags$b("DFW/non-pass in most courses"), ": at least half of the student's classifiable attempts that term were DFW/non-pass."),
            tags$li(tags$b("Only course attempted"), ": the selected course was the only classifiable course attempt CEDAR sees for that student that term."),
            tags$li(tags$b("Same-term context"), ": other courses are counted across the student's loaded class-list records for that term, not just the selected course campus.")
          ),
          description = "Whether DFW in this course was isolated or part of the student's broader term."
        ),
        if (isTRUE(ctx$merged_buckets)) {
          div(
            class = "alert alert-info alert-compact",
            icon("circle-info"), " ",
            sprintf(
              paste0("Categories holding fewer than %d student-terms are combined with ",
                     "their nearest neighbour, so a thin category does not hide the ",
                     "rest of the breakdown. Combined categories are named for their parts."),
              as.integer(ctx$min_cell %||% 5L)
            )
          )
        },
        plotlyOutput("cr_dfw_context_plot", height = "240px"),
        reactable::reactableOutput("cr_dfw_context_table")
      )
    )
  })

  output$cr_dfw_context_plot <- renderPlotly({
    ctx <- cr_dfw_context_reactive()
    req(!is.null(ctx), !isTRUE(ctx$suppressed))
    d <- ctx$summary
    req(!is.null(d), nrow(d) > 0)

    colors <- c(
      "DFW only in this course" = "#2f6f5e",
      "Some broader difficulty" = "#486f84",
      "DFW/non-pass in most courses" = "#7a2e2e",
      "Only course attempted" = "#8a7a4a"
    )

    p <- plotly::plot_ly()
    for (bucket_name in as.character(d$bucket)) {
      bd <- d %>% dplyr::filter(as.character(bucket) == bucket_name)
      # Single-bracket lookup: merged buckets carry a combined label that is not
      # in `colors`, and `[[` would error on the missing name rather than fall
      # through to the default.
      bucket_color <- unname(colors[bucket_name])
      if (is.na(bucket_color)) bucket_color <- "#666666"
      p <- plotly::add_trace(
        p,
        x = bd$pct_student_terms,
        y = "DFW student-terms",
        type = "bar",
        orientation = "h",
        name = bucket_name,
        marker = list(color = bucket_color),
        text = paste0(bd$pct_student_terms, "%"),
        textposition = "auto",
        customdata = paste0(
          "Student-terms: ", bd$n_student_terms,
          "<br>Median attempted courses: ", bd$median_attempted_courses,
          "<br>Median DFW/non-pass courses: ", bd$median_dfw_courses
        ),
        hovertemplate = paste0(
          bucket_name,
          "<br>Share: %{x:.1f}%",
          "<br>%{customdata}<extra></extra>"
        )
      )
    }

    p %>% plotly::layout(
      barmode = "stack",
      xaxis = list(title = "Share of DFW student-terms", range = c(0, 100), ticksuffix = "%"),
      yaxis = list(title = "", showticklabels = FALSE),
      legend = list(orientation = "h", x = 0, y = 1.16,
                    xanchor = "left", yanchor = "bottom"),
      margin = list(t = 60, b = 50, l = 10, r = 10)
    )
  })

  output$cr_dfw_context_table <- reactable::renderReactable({
    ctx <- cr_dfw_context_reactive()
    req(!is.null(ctx), !isTRUE(ctx$suppressed))
    d <- ctx$summary
    req(!is.null(d), nrow(d) > 0)

    display <- d %>%
      dplyr::transmute(
        Context = as.character(bucket),
        `Student-Terms` = n_student_terms,
        `Share` = pct_student_terms,
        `Median Courses Attempted` = median_attempted_courses,
        `Median DFW/Non-Pass Courses` = median_dfw_courses
      )

    cr_dfw_reactable(
      display,
      default_page_size = 5L,
      searchable = FALSE,
      columns = list(
        Context = reactable::colDef(minWidth = 190),
        `Student-Terms` = reactable::colDef(align = "right"),
        Share = reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")
        ),
        `Median Courses Attempted` = reactable::colDef(align = "right"),
        `Median DFW/Non-Pass Courses` = reactable::colDef(align = "right")
      )
    )
  })

  output$cr_instructor_dfw_ui <- renderUI({
    req(dfw_authenticated())
    outcomes <- course_report_data()$outcomes
    if (is.null(outcomes))
      return(p("Loading…", class = "text-muted"))
    if (!is.null(outcomes$instructor_dfw) && nrow(outcomes$instructor_dfw) > 0)
      reactable::reactableOutput("cr_outcomes_instructor_dfw")
    else
      p("No instructor comparison data available for this course.", class = "text-muted")
  })

  # Recomputes persistence reactively so campus filter is always respected.
  # next_term_persistence() has no campus column in its output, so post-filtering
  # is not possible — we must apply the campus filter before calling it.
  cr_persistence_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data))
    course <- data$opt[["course"]]
    req(!is.null(course) && nzchar(course))
    students <- data_objects[["cedar_students"]]
    campus_filter <- get_campus_filter()
    filtered <- students %>%
      filter(
        subject_course %in% course,
        registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE)
      )
    if (!is.null(campus_filter))
      filtered <- filtered %>% filter(campus %in% campus_filter$values)
    filtered <- dedup_enrollment(filtered, level = "course")
    if (nrow(filtered) == 0) return(tibble())
    next_term_persistence(filtered, students,
                          opt = list(
                            min_n = 5L,
                            passing_grades = cr_ret_passing_grades(),
                            data_edges = data_objects[["cedar_edges"]]
                          ))
  })

  cr_ret_passing_grades <- reactive({
    threshold <- input$cr_ret_threshold %||% "below_c"
    if (identical(threshold, "f_only")) {
      GRADES_PASS_SUB_C_OPT_IN
    } else {
      GRADES_PASS
    }
  })

  output$cr_outcomes_persistence <- reactable::renderReactable({
    d <- cr_persistence_reactive()
    req(!is.null(d) && nrow(d) > 0)
    display <- d %>%
      dplyr::transmute(
        Campus = campus,
        Outcome = outcome,
        Students = n_students,
        Returned = n_returned,
        `Returned %` = round(pct_returned * 100, 1)
      )
    cr_cedar_reactable(
      display,
      default_page_size = 10L,
      searchable = FALSE,
      columns = list(
        Campus = reactable::colDef(maxWidth = 90),
        Outcome = reactable::colDef(minWidth = 110),
        Students = reactable::colDef(align = "right", maxWidth = 90),
        Returned = reactable::colDef(align = "right", maxWidth = 90),
        `Returned %` = reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")
        )
      )
    )
  })

  output$cr_outcomes_dfw_trend <- reactable::renderReactable({
    d <- cr_dfw_by_term_reactive()
    req(nrow(d) > 0)
    d <- d %>%
      dplyr::arrange(term, campus, subject_course) %>%
      dplyr::transmute(
        Campus = campus,
        College = college,
        Term = term,
        Course = subject_course,
        Attempts = n_attempts,
        Passed = n_pass,
        `Non-Passing Grades` = failed,
        `Late Withdrawals` = n_w,
        `DFW Count` = n_dfw,
        `DFW %` = dfw_pct,
        `Early Drops` = n_early_drop
      )

    cr_dfw_reactable(
      d,
      default_page_size = 15L,
      columns = list(
        Campus = reactable::colDef(maxWidth = 90),
        College = reactable::colDef(maxWidth = 90),
        Term = reactable::colDef(maxWidth = 85),
        Course = reactable::colDef(minWidth = 100,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        Attempts = reactable::colDef(align = "right"),
        Passed = reactable::colDef(align = "right"),
        `Non-Passing Grades` = reactable::colDef(align = "right"),
        `Late Withdrawals` = reactable::colDef(align = "right"),
        `DFW Count` = reactable::colDef(align = "right"),
        `DFW %` = reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")
        ),
        `Early Drops` = reactable::colDef(align = "right")
      )
    )
  })

  output$cr_dfw_status_exclusions <- reactable::renderReactable({
    d <- cr_dfw_status_exclusions_reactive()
    req(!is.null(d), nrow(d) > 0)
    display <- d %>%
      dplyr::transmute(
        Campus = campus,
        College = college,
        Term = term,
        Course = subject_course,
        `Status Code` = status_code,
        `Status` = status_label,
        Rows = rows,
        Students = students,
        `Rows With Grade` = nonblank_grade_rows,
        `Grade Values` = grade_values
      )
    cr_dfw_reactable(
      display,
      default_page_size = 10L,
      columns = list(
        Campus = reactable::colDef(maxWidth = 90),
        College = reactable::colDef(maxWidth = 90),
        Term = reactable::colDef(maxWidth = 85),
        Course = reactable::colDef(minWidth = 100),
        `Status Code` = reactable::colDef(maxWidth = 95),
        Rows = reactable::colDef(align = "right"),
        Students = reactable::colDef(align = "right"),
        `Rows With Grade` = reactable::colDef(align = "right")
      )
    )
  })

  output$cr_dfw_demo_classification <- reactable::renderReactable({
    demo <- cr_dfw_demographics_reactive()
    d <- demo$classification
    req(!is.null(d), nrow(d) > 0)
    display <- d %>%
      dplyr::transmute(
        Classification = group,
        Attempts = n_attempts,
        `DFW Count` = n_dfw,
        `DFW %` = dfw_pct,
        `Share of DFW` = share_of_dfw,
        `Late Withdrawals` = n_late_withdrawal,
        `Early Drops` = n_early_drop
      )
    cr_dfw_reactable(
      display,
      default_page_size = 10L,
      default_sorted = list(`DFW Count` = "desc"),
      columns = list(
        Classification = reactable::colDef(minWidth = 130),
        Attempts = reactable::colDef(align = "right"),
        `DFW Count` = reactable::colDef(align = "right"),
        `DFW %` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Share of DFW` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Late Withdrawals` = reactable::colDef(align = "right"),
        `Early Drops` = reactable::colDef(align = "right")
      )
    )
  })

  output$cr_dfw_demo_major <- reactable::renderReactable({
    demo <- cr_dfw_demographics_reactive()
    d <- demo$major
    req(!is.null(d), nrow(d) > 0)
    display <- d %>%
      dplyr::transmute(
        Major = group,
        Attempts = n_attempts,
        `DFW Count` = n_dfw,
        `DFW %` = dfw_pct,
        `Share of DFW` = share_of_dfw,
        `Late Withdrawals` = n_late_withdrawal,
        `Early Drops` = n_early_drop
      )
    cr_dfw_reactable(
      display,
      default_page_size = 10L,
      default_sorted = list(`DFW Count` = "desc"),
      columns = list(
        Major = reactable::colDef(minWidth = 180),
        Attempts = reactable::colDef(align = "right"),
        `DFW Count` = reactable::colDef(align = "right"),
        `DFW %` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Share of DFW` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Late Withdrawals` = reactable::colDef(align = "right"),
        `Early Drops` = reactable::colDef(align = "right")
      )
    )
  })

  output$cr_outcomes_instructor_dfw <- reactable::renderReactable({
    req(dfw_authenticated())
    req(course_report_data())
    d <- course_report_data()$outcomes$instructor_dfw
    req(!is.null(d) && nrow(d) > 0)
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) d <- d %>% filter(campus %in% campus_filter$values)
    display <- d %>%
      dplyr::select(dplyr::any_of(c(
        "campus", "college", "subject_course", "instructor_name",
        "n_attempts", "n_dfw", "dfw_pct", "course_avg_dfw", "dfw_diff"
      ))) %>%
      dplyr::rename(
        Campus = campus,
        College = college,
        Course = subject_course,
        Instructor = instructor_name,
        Attempts = n_attempts,
        `DFW Count` = n_dfw,
        `DFW %` = dfw_pct,
        `Course Avg DFW %` = course_avg_dfw,
        `Diff From Course` = dfw_diff
      )
    cr_dfw_reactable(
      display,
      default_page_size = 15L,
      columns = list(
        Campus = reactable::colDef(maxWidth = 90),
        College = reactable::colDef(maxWidth = 90),
        Course = reactable::colDef(minWidth = 100),
        Instructor = reactable::colDef(minWidth = 150),
        Attempts = reactable::colDef(align = "right"),
        `DFW Count` = reactable::colDef(align = "right"),
        `DFW %` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Course Avg DFW %` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")),
        `Diff From Course` = reactable::colDef(align = "right",
          format = reactable::colFormat(digits = 1))
      )
    )
  })

  # ── Course Impact: Retention, Sequence, Instructor ───────────────────────────
  # These three tabs share the cr_course selector at the top of Course Dynamics
  # and run on-demand (separate run buttons per tab) because each is slow and
  # may not be relevant for every course the user looks up.

  # Shared helper: renders the SMD bands classified by compute_balance().
  # It does not infer comparability from the absence of a >0.25 warning.
  .render_balance_table <- function(
    balance,
    group_labels = c("Treatment", "Control")
  ) {
    smd <- balance$smd_table
    if (is.null(smd) || nrow(smd) == 0) return(p("No balance data.", style = "color:#888;"))
    group_a <- group_labels[[1]]
    group_b <- group_labels[[2]]

    smd_display <- smd %>%
      dplyr::mutate(
        value_treatment = cedar_format_balance_value(value_treatment, type),
        value_control = cedar_format_balance_value(value_control, type),
        smd_value = dplyr::if_else(is.na(smd), "—", sprintf("%.3f", smd)),
        smd_fmt = dplyr::case_when(
          balance_band == "substantial" ~ paste0(smd_value, " ⚠"),
          balance_band == "review" ~ paste0(smd_value, " △"),
          TRUE ~ smd_value
        ),
        interpretation = dplyr::recode(
          balance_band,
          small = "Small difference",
          review = "Review",
          substantial = "Substantial difference",
          unavailable = "Unavailable"
        )
      ) %>%
      dplyr::select(covariate, type, n_treatment, n_control,
                    value_treatment, value_control, unit, smd = smd_fmt,
                    interpretation)
    names(smd_display) <- c(
      "Covariate", "Type", paste0(group_a, " N"), paste0(group_b, " N"),
      paste0(group_a, " Value"), paste0(group_b, " Value"), "Unit", "SMD",
      "Interpretation"
    )

    # Categorical distributions — one mini-table per variable, side by side
    cat_panels <- NULL
    cats <- balance$categorical
    if (!is.null(cats) && length(cats) > 0) {
      cat_panels <- tagList(
        h6("Categorical Covariates", style = "margin-top: 16px; color: #555;"),
        p(style = "font-size: 0.78em; color: #888; margin-bottom: 8px;",
          "Proportions within each group. Categorical variables are not reduced to a
           single SMD — review distributions directly for meaningful differences."),
        fluidRow(
          lapply(names(cats), function(varname) {
            df <- cats[[varname]] %>%
              tidyr::pivot_wider(
                id_cols    = "value",
                names_from = "group",
                values_from = "pct",
                values_fill = 0
              ) %>%
              dplyr::rename(
                Value = value,
                !!paste0(group_a, " (%)") := treatment,
                !!paste0(group_b, " (%)") := control
              ) %>%
              dplyr::arrange(dplyr::desc(dplyr::across(dplyr::ends_with("(%)"))))
            column(
              width = 4,
              div(
                style = "margin-bottom: 16px;",
                tags$strong(style = "font-size: 0.82em;", varname),
                cr_basic_reactable(
                  cr_humanize_columns(df),
                  default_page_size = 20L,
                  searchable = FALSE
                )
              )
            )
          })
        )
      )
    }

    balance_summary <- switch(
      balance$overall_balance,
      substantial =
        div(class = "alert alert-warning",
            style = "font-size: 0.85em;",
            icon("triangle-exclamation"), " ",
            "One or more measured covariates have substantial observed differences (|SMD| > 0.25). ",
            "Outcome gaps may partly reflect who entered each group."),
      review =
        div(class = "alert alert-warning",
            style = "font-size: 0.85em;",
            icon("circle-info"), " ",
            "Review the measured covariate differences: at least one |SMD| is 0.10–0.25, ",
            "even though none exceeds 0.25. Do not describe these groups as well-balanced."),
      small =
        div(class = "alert alert-success", style = "font-size: 0.85em;",
            icon("circle-check"), " All estimated continuous and binary covariates have small ",
            "observed differences (|SMD| < 0.10). This does not establish comparability on ",
            "unmeasured factors."),
      unavailable =
        div(class = "alert alert-secondary", style = "font-size: 0.85em;",
            icon("circle-info"), " No continuous or binary SMD could be estimated. ",
            "Observed balance is unavailable; review the group descriptions and categorical distributions."),
      div(class = "alert alert-secondary", style = "font-size: 0.85em;",
          "Observed balance status is unavailable.")
    )

    tagList(
      balance_summary,
      h6("Continuous & Binary Covariates", style = "color: #555;"),
      p(style = "font-size: 0.78em; color: #888; margin-bottom: 6px;",
        strong(paste0(group_a, " / ", group_b, " values:")),
        " For ", strong("binary"), " covariates (first_gen, pell_eligible) these are the ",
        "percentage of students in each group with that characteristic. For ", strong("continuous"),
        " covariates (cum_gpa_entering, high_school_cum_gpa, etc.) these are the group means — ",
        "for example, a value of 3.21 means that group's average high-school GPA was 3.21.",
        br(),
        strong("SMD"), " (standardized mean difference) expresses the gap between groups in ",
        "units of the pooled standard deviation, so it's comparable across variables with ",
        "different scales. CEDAR labels |SMD| < 0.10 as a small observed difference, ",
        "0.10–0.25 as review (△), and >0.25 as a substantial difference (⚠). These bands ",
        "describe measured covariates; they do not adjust the comparison or certify that the ",
        "groups are otherwise comparable. ",
        "Example: SMD = 0.40 on HS GPA means ", group_a, " students averaged 0.4 standard ",
        "deviations higher than ", group_b,
        " students — a meaningful difference that the analysis does not adjust for."),
      cr_basic_reactable(
        smd_display,
        default_page_size = 15L,
        searchable = FALSE
      ),
      cat_panels
    )
  }

  # ── Retention tab (Course Dynamics) ─────────────────────────────────────────
  # For the selected course, shows how T+1 to T+N retention has changed
  # term-over-term, optionally broken out by instructor.
  # Uses get_retention_trend() from R/modules/retention.R.
  # (The cross-course comparable-groups analysis lives in the full Retention
  #  module and is hidden from Explore until that work is ready.)

  output$cr_impact_retention_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(empty_state("Select a course and click Analyze Course first, then open this tab."))
    tagList(
      subtab_header(
        "Retention",
        "Of the students who took this course, how many enrolled again the next ",
        "fall or spring — split by how they did here. Read the bars against each ",
        "other: if students who failed return at close to the same rate as those ",
        "who passed, the course is not where they are leaving. A wide gap says ",
        "the opposite. This describes who came back, not why; students leave for ",
        "reasons no course-level view can see."
      ),
      div(class = "mb-3",
        tags$strong("What counts as failing?"),
        tags$span(style = "font-size: 0.85em; color: #555; margin-left: 8px;",
          "Affects how grades are split between 'fail' and 'pass'."),
        radioButtons("cr_ret_threshold", label = NULL,
          choices = c(
            "Standard: only A+ through C and CR pass; all other recorded outcomes count as fail" = "below_c",
            "Opt in: also treat C−, D+, D, and D− as passing" = "f_only"
          ),
          selected = input$cr_ret_threshold %||% "below_c",
          inline = FALSE
        )
      ),
      uiOutput("cr_persistence_ui"),
      br(),
      hr(),
      dashboard_subsection(
        "Retention Over Time",
        "Primary rows pool like term types across the data window; a collapsed semester view remains available for auditing individual terms.",
        info_panel(
          "How retention is calculated",
          div(
            class = "alert alert-info",
            tags$strong("Data window: "),
            cedar_longitudinal_edge_note(
              data_objects[["cedar_edges"]], grade_dependent = FALSE
            )
          ),
          tags$ul(
            tags$li("The starting cohort is every student officially registered in the selected course in each term."),
            tags$li("Primary tables pool Fall, Spring, and Summer cohorts separately across the data window, weighted by cohort size."),
            tags$li("When instructor breakout is enabled, all terms taught by the same instructor ID are pooled before the minimum-student threshold is applied."),
            tags$li("The +1, +2, and later columns show the share of that cohort still enrolled anywhere at UNM the given number of fall/spring semesters later."),
            tags$li("Graduates count as retained if they graduated after taking the course; they are not treated as stop-outs."),
            tags$li("Summer terms are skipped when counting semesters forward, so +1 means the next fall or spring term."),
            tags$li("Blank cells mean the target term is beyond the latest available data, not that retention was 0%.")
          ),
          cedar_definition_note("course-retention"),
          description = "Cohort, graduation, summer-term, and blank-cell rules."
        ),

        fluidRow(
          # Campus is a scope control, not a nicety: a course taught on six
          # campuses otherwise reports one blended cohort. Defaults to main +
          # online. Results stay split by campus regardless of what is selected.
          column(3,
            selectInput("cr_ret_campus", "Campus", multiple = TRUE,
              choices  = cedar_campus_choices(data_objects[["cedar_students"]]),
              selected = cedar_campus_default(data_objects[["cedar_students"]]))
          ),
          column(2,
            numericInput("cr_ret_n_terms", "Semesters to track:", value = 4, min = 1, max = 8)
          ),
          column(2,
            numericInput("cr_ret_min_n", "Min students per summary:", value = 10, min = 1)
          ),
          column(3,
            div(style = "margin-top: 24px;",
              checkboxInput("cr_ret_by_instructor", "Break out by instructor", value = FALSE)
            )
          ),
          column(2,
            div(class = "mt-4",
              actionButton("cr_ret_run", "Run", icon = icon("play"), class = "btn-primary")
            )
          )
        ),
        br(),
        uiOutput("cr_retention_results")
      )
    )
  })

  output$cr_persistence_ui <- renderUI({
    data <- course_report_data()
    if (is.null(data)) return(NULL)
    d <- tryCatch(cr_persistence_reactive(), error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0)
      return(p("Insufficient graded students to compute persistence (need 5+ per outcome).",
               class = "text-muted"))
    plot_height <- max(250L, 52L + 38L * nrow(d))
    fluidRow(
      column(6, plotlyOutput("cr_persistence_plot", height = paste0(plot_height, "px"))),
      column(6, reactable::reactableOutput("cr_outcomes_persistence"))
    )
  })

  output$cr_persistence_plot <- renderPlotly({
    d <- cr_persistence_reactive()
    req(!is.null(d), nrow(d) > 0)
    plot <- build_course_persistence_plot(d)
    req(!is.null(plot))
    plot
  })

  cr_retention_benchmark_diff_data <- reactive({
    course_result  <- cr_course_retention_data()
    dept_result    <- cr_dept_retention_data()
    college_result <- cr_college_retention_data()
    if (is.null(course_result) || nrow(course_result) == 0) return(tibble::tibble())
    compare_retention_to_benchmarks(course_result, dept_result, college_result)
  })

  observeEvent(input$cr_ret_run, {
    req(input$cr_course, nzchar(input$cr_course))
    cr_retention_data(NULL)
    cr_dept_retention_data(NULL)
    cr_college_retention_data(NULL)
    cr_course_retention_data(NULL)

    students  <- data_objects[["cedar_students"]]
    degrees   <- data_objects[["cedar_degrees"]]
    course    <- input$cr_course
    n_terms   <- as.integer(input$cr_ret_n_terms %||% 4L)
    min_n     <- as.integer(input$cr_ret_min_n   %||% 10L)

    campus_sel <- input$cr_ret_campus
    if (length(campus_sel) == 0) campus_sel <- NULL

    opt <- list(
      course        = course,
      n_terms       = n_terms,
      min_n         = min_n,
      campus        = campus_sel,
      by_instructor = isTRUE(input$cr_ret_by_instructor),
      data_edges    = data_objects[["cedar_edges"]]
    )

    notify_id <- "cr_ret_loading"
    showNotification("Computing retention trend…", type = "warning",
                     duration = NULL, id = notify_id)
    on.exit(removeNotification(notify_id))

    tryCatch({
      # The primary tables pool terms by term type. Keep every instructor-term
      # cohort for that pooling step; the requested minimum is applied to the
      # pooled denominator below. Small cells remain suppressed in the optional
      # individual-semester drill-down.
      result <- get_retention_trend(
        students,
        modifyList(opt, list(min_n = 1L)),
        degrees = degrees
      )
      cr_retention_data(result)
      course_result <- get_retention_trend(
        students,
        modifyList(opt, list(by_instructor = FALSE)),
        degrees = degrees
      )
      cr_course_retention_data(course_result)

      # Derive dept, college, and course level from actual student rows for this
      # course. Level ("lower"/"upper"/"grad") ensures benchmarks only include
      # students in courses at the same level — comparing a 100-level course
      # against all dept students including grad cohorts would be misleading.
      course_meta <- students %>%
        filter(subject_course == course, !is.na(department))
      if (!is.null(campus_sel)) {
        course_meta <- course_meta %>% filter(campus %in% campus_sel)
      }
      course_meta <- course_meta %>% slice(1)

      dept_val    <- if (nrow(course_meta) > 0) course_meta$department[[1]] else NULL
      college_val <- if (nrow(course_meta) > 0) course_meta$college[[1]]    else NULL
      level_val   <- if (nrow(course_meta) > 0) course_meta$level[[1]]      else NULL
      # "unknown" means the course number pattern didn't match — don't filter on it.
      if (!is.null(level_val) && (is.na(level_val) || level_val == "unknown")) level_val <- NULL

      # Restrict benchmark to the same anchor terms as the course result so
      # the tables align row-for-row.
      anchor_terms <- if (!is.null(course_result) && nrow(course_result) > 0) course_result$term else NULL

      # Same campus scope as the course trend — a benchmark drawn from different
      # campuses is a comparison against a different institution.
      bench_opt <- list(n_terms = n_terms, min_n = 5L, terms = anchor_terms,
                        level = level_val, campus = campus_sel,
                        data_edges = data_objects[["cedar_edges"]])

      if (!is.null(dept_val) && nzchar(dept_val)) {
        dept_result <- tryCatch(
          get_dept_retention_trend(students, c(bench_opt, list(dept_code = dept_val)), degrees = degrees),
          error = function(e) { message("[server.R] dept benchmark error: ", e$message); NULL }
        )
        cr_dept_retention_data(dept_result)
      }

      if (!is.null(college_val) && nzchar(college_val)) {
        college_result <- tryCatch(
          get_dept_retention_trend(students, c(bench_opt, list(college = college_val)), degrees = degrees),
          error = function(e) { message("[server.R] college benchmark error: ", e$message); NULL }
        )
        cr_college_retention_data(college_result)
      }

    }, error = function(e) {
      showNotification(paste("Retention trend failed:", conditionMessage(e)),
                       type = "error", duration = 10)
      message("[server.R] cr_retention error: ", conditionMessage(e))
    })
  })

  output$cr_retention_results <- renderUI({
    result <- cr_retention_data()
    if (is.null(result)) return(NULL)
    by_instructor <- isTRUE(input$cr_ret_by_instructor)
    min_n <- as.integer(input$cr_ret_min_n %||% 10L)
    aggregate <- summarize_retention_by_term_type(
      result,
      by_instructor = by_instructor,
      min_n = min_n
    )
    if (nrow(aggregate) == 0)
      return(div(class = "alert alert-warning",
                 "No term-type summaries met the minimum student threshold for this course."))
    retention_column_guide <- info_panel(
      "Explain Columns",
      tags$ul(
        tags$li(tags$b("Campus"), ": rates are computed per campus. A course taught in Albuquerque and at a branch is two cohorts, never one blended rate."),
        tags$li(tags$b("Term Type"), ": Fall, Spring, or Summer cohorts combined across the selected data window."),
        tags$li(tags$b("Instructor"), ": shown only when instructor breakout is enabled; each row summarizes that instructor within one term type."),
        tags$li(tags$b("Terms"), ": every distinct term in which this instructor taught the selected course for that campus and term type, including small terms pooled into the summary."),
        tags$li(tags$b("Cohort Enrollments"), ": sum of the starting cohort sizes across those terms."),
        tags$li(tags$b("+1 sem, +2 sem, ..."), ": percent of the starting cohort enrolled anywhere at UNM the given number of fall/spring semesters later, with later graduation also counted as retained."),
        tags$li(tags$b("Weighted rates"), ": larger term cohorts contribute proportionally more than smaller cohorts. Each +N rate uses only terms whose future outcome is observable."),
        tags$li(tags$b("Blank cells"), ": no term in that group has an observable future outcome at that horizon.")
      ),
      description = "How to read the term-type retention summary."
    )
    tagList(
      uiOutput("cr_retention_benchmark_diff_ui"),
      if (isTRUE(input$cr_ret_by_instructor)) uiOutput("cr_retention_instructor_highlights"),
      h5("Retention Rates by Term Type", style = "margin-top: 1em; color: #555;"),
      p(
        "These data-window rates combine like terms to emphasize persistent patterns that are more useful for planning than a single-semester result.",
        style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"
      ),
      retention_column_guide,
      reactable::reactableOutput("cr_retention_table"),
      tags$details(
        style = "margin-top: 1em;",
        tags$summary(
          "Show individual-semester detail",
          style = "cursor: pointer; color: #555; font-weight: 600;"
        ),
        p(
          "Use these rows to audit unusual terms or explain a change in the trend chart; they are not used for the primary summary or instructor ranking.",
          style = "font-size: 0.85em; color: #777; margin: 8px 0 6px;"
        ),
        reactable::reactableOutput("cr_retention_term_table")
      ),
      br(),
      uiOutput("cr_retention_benchmarks")
    )
  })

  output$cr_retention_benchmark_diff_ui <- renderUI({
    diff_data <- cr_retention_benchmark_diff_data()
    if (is.null(diff_data) || nrow(diff_data) == 0) return(NULL)
    campus_n <- max(
      1L,
      dplyr::n_distinct(stats::na.omit(diff_data$campus))
    )
    plot_height <- max(280L, 220L * campus_n + 60L)
    tagList(
      h5("Next-Term Retention Compared With Benchmarks", style = "margin-top: 1em; color: #555;"),
      p(
        "Each campus has its own panel. The lines show +1 semester retention percentages by term against department and college benchmarks from that same campus and course level.",
        style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"
      ),
      plotlyOutput(
        "cr_retention_benchmark_diff_plot",
        height = paste0(plot_height, "px")
      )
    )
  })

  output$cr_retention_benchmark_diff_plot <- renderPlotly({
    diff_data <- cr_retention_benchmark_diff_data()
    req(!is.null(diff_data), nrow(diff_data) > 0)
    build_retention_benchmark_plot(diff_data)
  })

  output$cr_retention_instructor_highlights <- renderUI({
    result <- cr_retention_data()
    ranked <- summarize_instructor_retention_rows(
      result,
      top_n = 10L,
      min_n = as.integer(input$cr_ret_min_n %||% 10L)
    )
    if ((is.null(ranked$top) || nrow(ranked$top) == 0) &&
        (is.null(ranked$bottom) || nrow(ranked$bottom) == 0)) {
      return(NULL)
    }
    tagList(
      h5("Instructor Patterns To Review", style = "margin-top: 1em; color: #555;"),
      p(
        "These are instructor-by-term-type summaries ranked across the available +N retention rates, weighted by the observable cohort at each horizon. Use them as a triage view, then check the number of terms and cohort enrollments before interpreting.",
        style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"
      ),
      fluidRow(
        column(6,
          tags$strong("Highest"),
          reactable::reactableOutput("cr_retention_instructor_top_table")
        ),
        column(6,
          tags$strong("Lowest"),
          reactable::reactableOutput("cr_retention_instructor_bottom_table")
        )
      )
    )
  })

  .retention_display_table <- function(tbl, by_instructor = FALSE, include_avg = FALSE) {
    if (is.null(tbl) || nrow(tbl) == 0) return(NULL)
    ret_cols <- grep("^ret_\\d+$", names(tbl), value = TRUE)
    ret_cols <- intersect(ret_cols, names(tbl))
    instructor_col <- if (by_instructor && "instructor_name" %in% names(tbl)) {
      "instructor_name"
    } else if (by_instructor && "instructor_id" %in% names(tbl)) {
      "instructor_id"
    } else {
      NULL
    }
    # Campus leads the row: these tables are one row per campus and time grain, and a
    # reader who cannot see which campus a rate belongs to will read every row
    # as main campus.
    campus_col <- if ("campus" %in% names(tbl)) "campus" else NULL
    period_col <- if ("term_type_label" %in% names(tbl)) {
      "term_type_label"
    } else {
      "term_label"
    }
    terms_col <- if ("terms" %in% names(tbl)) "terms" else NULL
    display_cols <- c(campus_col, period_col, instructor_col, terms_col, "n",
                      if (include_avg) "avg_retention", ret_cols)
    display <- tbl %>%
      dplyr::select(dplyr::all_of(display_cols))
    if (identical(period_col, "term_type_label")) {
      display <- display %>%
        dplyr::rename(`Term Type` = term_type_label,
                      `Cohort Enrollments` = n)
    } else {
      display <- display %>% dplyr::rename(Term = term_label, Students = n)
    }
    if (!is.null(terms_col)) {
      display <- display %>% dplyr::rename(Terms = terms)
    }
    if (!is.null(campus_col)) {
      display <- display %>% dplyr::rename(Campus = dplyr::all_of(campus_col))
    }
    if (!is.null(instructor_col)) {
      display <- display %>% dplyr::rename(Instructor = dplyr::all_of(instructor_col))
    }
    if (include_avg && "avg_retention" %in% names(display)) {
      display <- display %>% dplyr::rename(Avg = avg_retention)
    }
    for (i in seq_along(ret_cols)) {
      old <- ret_cols[[i]]
      new <- paste0("+", i, " sem")
      names(display)[names(display) == old] <- new
    }
    pct_cols <- c(if (include_avg) "Avg", paste0("+", seq_along(ret_cols), " sem"))
    for (col in intersect(pct_cols, names(display))) {
      display[[col]] <- round(display[[col]] * 100, 1)
    }
    display
  }

  .render_retention_reactable <- function(display, default_page_size = 10L,
                                          searchable = FALSE) {
    if (is.null(display) || nrow(display) == 0) return(NULL)
    pct_cols <- grep("^(Avg|\\+\\d+ sem)$", names(display), value = TRUE)
    pct_defs <- stats::setNames(
      lapply(pct_cols, function(col) {
        reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 1, suffix = "%")
        )
      }),
      pct_cols
    )
    cr_cedar_reactable(
      display,
      default_page_size = default_page_size,
      searchable = searchable,
      columns = c(
        list(
          Campus = reactable::colDef(maxWidth = 90),
          Term = reactable::colDef(maxWidth = 95),
          `Term Type` = reactable::colDef(maxWidth = 95),
          Instructor = reactable::colDef(minWidth = 150),
          Terms = reactable::colDef(align = "right", maxWidth = 70),
          Students = reactable::colDef(align = "right", maxWidth = 90),
          `Cohort Enrollments` = reactable::colDef(align = "right", minWidth = 110)
        ),
        pct_defs
      )
    )
  }

  output$cr_retention_instructor_top_table <- reactable::renderReactable({
    ranked <- summarize_instructor_retention_rows(
      cr_retention_data(),
      top_n = 10L,
      min_n = as.integer(input$cr_ret_min_n %||% 10L)
    )
    display <- .retention_display_table(ranked$top, by_instructor = TRUE, include_avg = TRUE)
    .render_retention_reactable(display, default_page_size = 10L)
  })

  output$cr_retention_instructor_bottom_table <- reactable::renderReactable({
    ranked <- summarize_instructor_retention_rows(
      cr_retention_data(),
      top_n = 10L,
      min_n = as.integer(input$cr_ret_min_n %||% 10L)
    )
    display <- .retention_display_table(ranked$bottom, by_instructor = TRUE, include_avg = TRUE)
    .render_retention_reactable(display, default_page_size = 10L)
  })

  output$cr_retention_table <- reactable::renderReactable({
    result <- cr_retention_data()
    req(!is.null(result) && nrow(result) > 0)

    by_instructor <- isTRUE(input$cr_ret_by_instructor)
    aggregate <- summarize_retention_by_term_type(
      result,
      by_instructor = by_instructor,
      min_n = as.integer(input$cr_ret_min_n %||% 10L)
    )
    display <- .retention_display_table(aggregate, by_instructor = by_instructor)
    .render_retention_reactable(display, default_page_size = 15L, searchable = FALSE)
  })

  output$cr_retention_term_table <- reactable::renderReactable({
    result <- cr_retention_data()
    req(!is.null(result) && nrow(result) > 0)

    by_instructor <- isTRUE(input$cr_ret_by_instructor)
    min_n <- as.integer(input$cr_ret_min_n %||% 10L)
    display <- .retention_display_table(
      result %>% dplyr::filter(n >= min_n),
      by_instructor = by_instructor
    )
    .render_retention_reactable(display, default_page_size = 15L, searchable = FALSE)
  })

  # ── Retention benchmark tables (dept / college) ───────────────────────────
  # Helper: render one benchmark table given a data frame.
  .render_benchmark_reactable <- function(bmark, n_terms_course) {
    if (is.null(bmark) || nrow(bmark) == 0) return(NULL)

    n_terms   <- min(n_terms_course, sum(startsWith(names(bmark), "ret_")))
    ret_cols  <- paste0("ret_", seq_len(n_terms))
    aggregate <- summarize_retention_by_term_type(bmark, by_instructor = FALSE)
    display <- .retention_display_table(
      aggregate %>%
        dplyr::select(
          dplyr::any_of(c("campus", "term_type_label", "terms", "n")),
          dplyr::all_of(intersect(ret_cols, names(aggregate)))
        ),
      by_instructor = FALSE
    )
    .render_retention_reactable(display, default_page_size = 10L)
  }

  output$cr_retention_benchmarks <- renderUI({
    course_result  <- cr_course_retention_data()
    dept_result    <- cr_dept_retention_data()
    college_result <- cr_college_retention_data()
    req(!is.null(course_result) && nrow(course_result) > 0)

    # Reconstruct the level and dept/college labels for display.
    course_row <- tryCatch(
      data_objects[["cedar_students"]] %>%
        filter(subject_course == input$cr_course, !is.na(department)) %>%
        slice(1),
      error = function(e) data.frame()
    )
    dept_code    <- if (nrow(course_row) > 0) course_row$department[[1]] else "department"
    college_code <- if (nrow(course_row) > 0) course_row$college[[1]]    else "college"
    level_raw    <- if (nrow(course_row) > 0) course_row$level[[1]]      else NULL
    level_label  <- switch(level_raw %||% "",
      lower = "lower-division", upper = "upper-division", grad = "graduate", NULL)

    level_phrase <- if (!is.null(level_label)) paste0(level_label, " ") else ""

    n_terms_course <- sum(startsWith(names(course_result), "ret_"))
    items <- list()

    if (!is.null(dept_result) && nrow(dept_result) > 0) {
      items <- c(items, list(
        h5(paste0("Department Average — ", dept_code),
           style = "margin-top: 1em; color: #555;"),
        p(paste0("Retention for all students registered in any ", level_phrase,
                 dept_code, " course, summarized by term type across the data window."),
          style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"),
        reactable::reactableOutput("cr_retention_dept_table")
      ))
    }

    if (!is.null(college_result) && nrow(college_result) > 0) {
      items <- c(items, list(
        h5(paste0("College Average — ", college_code),
           style = "margin-top: 1.5em; color: #555;"),
        p(paste0("Retention for all students registered in any ", level_phrase,
                 "course in the ", college_code,
                 " college, summarized by term type across the data window."),
          style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"),
        reactable::reactableOutput("cr_retention_college_table")
      ))
    }

    if (length(items) == 0) return(NULL)
    info_panel(
      "Benchmark Rate Tables",
      p(
        paste0("These tables show retention rates for other ", level_phrase,
               "courses in the same department and college, using cohort-size-weighted
                Fall, Spring, and Summer summaries across the same data window.
                Restricting to the same course level makes the comparison meaningful
                because lower-division and graduate cohorts have very different
                retention patterns.")
      ),
      tagList(items),
      description = "Data-window department and college rates behind the comparison chart."
    )
  })

  output$cr_retention_dept_table <- reactable::renderReactable({
    bmark <- cr_dept_retention_data()
    course_result <- cr_course_retention_data()
    req(!is.null(bmark), !is.null(course_result))
    n_terms_course <- sum(startsWith(names(course_result), "ret_"))
    .render_benchmark_reactable(bmark, n_terms_course)
  })

  output$cr_retention_college_table <- reactable::renderReactable({
    bmark <- cr_college_retention_data()
    course_result <- cr_course_retention_data()
    req(!is.null(bmark), !is.null(course_result))
    n_terms_course <- sum(startsWith(names(course_result), "ret_"))
    .render_benchmark_reactable(bmark, n_terms_course)
  })

  # Department of the currently selected course, for labelling the picker groups.
  cr_course_dept <- reactive({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course)) return(NA_character_)
    d <- data_objects[["cedar_students"]] %>%
      dplyr::filter(subject_course == course, !is.na(department)) %>%
      dplyr::slice(1) %>%
      dplyr::pull(department)
    if (length(d) == 0) NA_character_ else d[[1]]
  })

  # ── Downstream course choices, shared by Course Sequence and Instructor Patterns
  #
  # These choices come from courses students actually took after X. Department
  # ownership is retained only as a navigation aid and for the optional rollup;
  # it is not evidence for or against a curricular sequence. Valid pathways
  # routinely cross department boundaries.
  cr_downstream_options <- reactive({
    course <- input$cr_course
    req(course, nzchar(course))
    get_downstream_course_options(
      data_objects[["cedar_students"]],
      course,
      list(campus = if (length(input$cr_campus) > 0) input$cr_campus else NULL,
           min_n  = 15L,
           data_edges = data_objects[["cedar_edges"]])
    )
  })

  # Grouped selectize choices, each labelled with how many of X's students
  # continued into it. The group labels describe ownership, not relevance.
  cr_downstream_choices <- function(opts, include_rollup = FALSE, dept = NULL) {
    if (is.null(opts) || nrow(opts) == 0) return(list())
    lab <- function(d) stats::setNames(
      d$subject_course,
      paste0(d$subject_course, " \u2014 ",
             format(d$n_students, big.mark = ",", trim = TRUE),
             " students (", d$pct_of_x, "%)")
    )
    same  <- opts[opts$same_dept %in% TRUE, , drop = FALSE]
    other <- opts[!(opts$same_dept %in% TRUE), , drop = FALSE]
    out <- list()
    if (include_rollup && nrow(same) > 0) {
      out[["Summary"]] <- stats::setNames(
        CR_ROLLUP_SENTINEL,
        paste0("All follow-on courses in this department (", nrow(same), ")")
      )
    }
    if (nrow(same) > 0)
      out[[paste0("Same department", if (!is.na(dept) && nzchar(dept))
                  paste0(" (", dept, ")") else "")]] <- lab(same)
    if (nrow(other) > 0) out[["Different department"]] <- lab(utils::head(other, 40))
    out
  }

  # ── Combined Downstream tab ─────────────────────────────────────────────────
  output$cr_impact_downstream_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(empty_state("Select a course, then click Analyze Course to view this tab."))

    tagList(
      subtab_header(
        "Downstream",
        paste0(
          "Two views of what happens after ", course, ". Course Sequence asks whether ",
          "students who passed it before a later course differ from students who reached ",
          "that course without it. Instructor Patterns starts with students in ", course,
          " and groups their later continuation and outcomes by their first instructor here."
        )
      ),
      navset_tab(
        id = "cr_downstream_view",
        nav_panel(
          "Course Sequence",
          icon = icon("shuffle"),
          uiOutput("cr_impact_sequence_ui")
        ),
        nav_panel(
          "Instructor Patterns",
          icon = icon("chalkboard-teacher"),
          uiOutput("cr_impact_instructor_ui")
        )
      )
    )
  })

  # ── Course Sequence view ────────────────────────────────────────────────────
  # One interpretation panel for the sequence comparison. Keep this guidance
  # together so readers do not have to reconcile two nearly identical warnings.
  # The result-specific "Who is being counted" panel remains separate because it
  # documents the actual groups and sample produced by the selected comparison.
  cr_impact_limits_panel <- function() {
    info_panel(
      "What this comparison can and cannot show",
      tagList(
        tags$p(class = "cedar-body",
          "This is a ", tags$strong("descriptive contrast between two groups of students"),
          ", not a measured effect of the course. Students choose their own courses and
           sequences, so the two groups differ in ways CEDAR cannot see — motivation,
           advising, schedule constraints, what else they were carrying that term."),
        tags$p(class = "cedar-body",
          tags$strong("The balance measures describe where students started."),
          " Prior GPA and credits are reconstructed from term records and measured before
           the relevant course. They can reveal observed differences between the groups,
           but they cannot remove differences CEDAR does not observe."),
        tags$ul(
          tags$li(tags$strong("Check the balance table under the results."),
                  " If the groups differ on entering GPA or credits, the outcome gap is
                   partly describing who took each path."),
          tags$li(tags$strong("Use the HS GPA filter as a sensitivity check."),
                  " A gap that remains when both groups are restricted to the same band is
                   more interesting, but it is still not causal evidence."),
          tags$li(tags$strong("Use the result as a prompt, not a verdict."),
                  " It can identify a sequence worth examining with advisors, students,
                   or a more rigorous study."))
      ),
      description = "How self-selection, balance, and the GPA filter affect interpretation.",
      class = "cedar-detail-panel"
    )
  }

  output$cr_impact_sequence_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(empty_state("Select a course, then click Analyze Course to view this tab."))
    tagList(
      subtab_header(
        "Course Sequence",
        cedar_definition_summary("course-sequence")
      ),
      cedar_definition_panel("course-sequence"),
      cr_impact_limits_panel(),
      fluidRow(
        column(5,
          selectizeInput("cr_impact_seq_course_y", "Later course:",
                         choices  = cr_downstream_choices(
                           cr_downstream_options(), include_rollup = FALSE,
                           dept = cr_course_dept()),
                         options = list(placeholder = "Choose a later course...")),
          helpText("The list includes courses students actually took later across departments. Department ownership and continuation share do not establish — or rule out — an intended sequence; use curricular context.")
        ),
        column(2,
          numericInput("cr_impact_seq_min_n", "Min students:", value = 15, min = 5, max = 100)
        )
      ),
      fluidRow(
        column(2,
          numericInput("cr_impact_seq_gpa_min", "HS GPA min:", value = NA, min = 0, max = 5, step = 0.1)
        ),
        column(2,
          numericInput("cr_impact_seq_gpa_max", "HS GPA max:", value = NA, min = 0, max = 5, step = 0.1)
        ),
        column(4,
          br(),
          p(style = "font-size: 0.8em; color: #888;",
            "Restrict both groups to a HS GPA window to reduce self-selection bias.
             Leave blank to include all students regardless of GPA.")
        ),
        column(2,
          br(),
          actionButton("cr_impact_seq_run", "Compare Groups",
                       icon = icon("play"), class = "btn-primary")
        )
      ),
      uiOutput("cr_impact_sequence_results")
    )
  })

  observe({
    updateSelectizeInput(session, "cr_impact_seq_course_y",
                         choices = sort(unique(cedar_sections$subject_course)),
                         server  = TRUE)
  })

  observeEvent(input$cr_impact_seq_run, {
    req(input$cr_course, nzchar(input$cr_course),
        input$cr_impact_seq_course_y, nzchar(input$cr_impact_seq_course_y))
    cr_impact_sequence_data(NULL)

    gpa_min <- input$cr_impact_seq_gpa_min
    gpa_max <- input$cr_impact_seq_gpa_max
    opt <- list(
      course_x    = input$cr_course,
      course_y    = input$cr_impact_seq_course_y,
      min_n       = as.integer(input$cr_impact_seq_min_n %||% 15L),
      hs_gpa_min  = if (!is.na(gpa_min) && is.numeric(gpa_min)) gpa_min else NULL,
      hs_gpa_max  = if (!is.na(gpa_max) && is.numeric(gpa_max)) gpa_max else NULL,
      campus      = if (length(input$cr_campus) > 0) input$cr_campus else NULL
    )

    withProgress(message = "Building sequence comparison...", value = 0.3, {
      tryCatch({
        result <- get_course_sequence_effect(
          students     = data_objects[["cedar_students"]],
          programs     = data_objects[["cedar_programs"]],
          applicants   = data_objects[["cedar_applicants"]],
          opt          = opt,
          term_credits = data_objects[["cedar_student_term_credits"]],
          data_edges   = data_objects[["cedar_edges"]]
        )
        cr_impact_sequence_data(result)
        setProgress(1)
      }, error = function(e) {
        showNotification(paste("Sequence analysis failed:", conditionMessage(e)),
                         type = "error", duration = 10)
        message("[server.R] cr_impact_seq error: ", conditionMessage(e))
      })
    })
  })

  output$cr_impact_sequence_results <- renderUI({
    result <- cr_impact_sequence_data()
    if (is.null(result)) return(NULL)

    fmt_term <- function(t) {
      yr <- t %/% 100
      ss <- t %% 100
      season <- dplyr::case_when(ss == 10 ~ "Spring", ss == 60 ~ "Summer",
                                 ss == 80 ~ "Fall",   TRUE ~ as.character(ss))
      paste(season, yr)
    }

    tagList(
      # Methodology, not a warning — collapsible per the explain-box standard.
      info_panel(
        "Who is being counted",
        description = "Group definitions, sample sizes, and term ranges.",
        div(
          class = "alert alert-info",
          tags$strong("Data window: "), result$edge_note
        ),
        tags$ul(class = "mb-0",
          tags$li(
            strong("Treatment"), paste0(" (“passed ", result$course_x, " first”): "),
            "Students who (1) registered for and ", strong("passed"), paste0(" ", result$course_x),
            " at any point, and (2) later took ", result$course_y, " in a subsequent term. ",
            "Any gap between the two courses qualifies — consecutive or not. ",
            paste0(result$n_took_x_before_y, " students met this definition across "),
            fmt_term(result$term_range_x[1]), "–", fmt_term(result$term_range_x[2]), ". ",
            if (result$n_dropped_by_programs > 0)
              paste0(result$n_dropped_by_programs,
                     " were dropped for missing program records, leaving ",
                     result$n_treatment, " in the final comparison.")
            else
              paste0("All ", result$n_treatment, " appear in the final comparison.")
          ),
          tags$li(
            strong("Control"), paste0(" (“took ", result$course_y, " without prior ",
                                      result$course_x, "”): "),
            paste0("Students who took ", result$course_y, " but had no prior passing record in ",
                   result$course_x, ". "),
            paste0(result$n_took_y_without_x, " students across "),
            fmt_term(result$term_range_y[1]), "–", fmt_term(result$term_range_y[2]),
            paste0("; ", result$n_control, " in final comparison after program matching.")
          ),
          tags$li(
            strong("Outcome attempt: "),
            paste0("Each student contributes once, using their ", result$y_attempt_rule,
                   ". A later retake cannot move a student between groups or overwrite that outcome.")
          ),
          if (result$n_missing_hs_gpa_excluded > 0L) tags$li(
            result$n_missing_hs_gpa_excluded,
            " students with no HS GPA were excluded because a GPA window was active."
          )
        )
      ),
      fluidRow(
        column(6,
          h5(paste0("Grade Outcomes in ", result$course_y)),
          cr_basic_reactable(
            cr_humanize_columns(result$outcomes),
            default_page_size = 10L,
            searchable = FALSE
          )
        ),
        column(6,
          h5("Group Profile"),
          p(style = "font-size: 0.78em; color: #888; margin-bottom: 4px;",
            strong("mean_cum_gpa"), " and ", strong("mean_credits_earned"),
            " describe each student's record ", em("entering"), " the term they took ",
            "course X (treatment) or course Y (control), so they exclude that term's ",
            "own grade — which is the outcome being measured. Both are rebuilt from the ",
            "per-term class list, and these are the figures the balance table matches on. ",
            br(),
            strong("mean_current_gpa"), " is the registrar's UNM cumulative GPA ",
            em("as of the data pull"), " — where each group stands today, after the ",
            "courses being compared. It covers far more students than the rebuilt ",
            "figure, so it is the better summary of overall academic strength, but it ",
            "is deliberately kept out of the balance table: it is measured after the ",
            "outcome, and matching on it would partly match on the very thing being ",
            "measured. Read it as description, not as evidence the groups were alike. ",
            br(),
            strong("mean_hs_gpa"), " and ", strong("mean_act"),
            " are fixed pre-enrollment values from admissions records."),
          cr_basic_reactable(
            cr_humanize_columns(result$group_profile),
            default_page_size = 10L,
            searchable = FALSE
          )
        )
      ),
      hr(),
      h5("Covariate Balance"),
      p(style = "font-size: 0.8em; color: #666;",
        "Review the observed-difference band for every measured covariate before ",
        "interpreting grade differences. Even small measured differences do not address ",
        "unobserved ways the groups may differ. ",
        "Use the HS GPA band inputs above to compare students within the same GPA range."),
      .render_balance_table(result$balance)
    )
  })

  # ── Instructor Patterns view ────────────────────────────────────────────────
  output$cr_impact_instructor_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(empty_state("Select a course, then click Analyze Course to view this tab."))
    tagList(
      subtab_header(
        "Instructor Patterns",
        paste0("How do students do later on, grouped by who taught them ", course,
               "? Pick one or more later courses below, or use the optional department ",
               "summary when the question is specifically about same-department ",
               "follow-ons.")
      ),
      info_panel(
        "What this can and cannot tell you",
        description = "Worth reading once before acting on a result.",
        tags$p(tags$strong("This is not a measure of teaching quality, and is ",
                           "not a basis for evaluating instructors.")),
        tags$ul(
          tags$li(tags$strong("Start with the balance table."),
                  " Students choose sections by schedule, reputation, and what ",
                  "they have already taken, so two sections often begin with ",
                  "different kinds of students. Where the balance table is ",
                  "flagged, a later grade gap is partly telling you who enrolled."),
          tags$li(tags$strong("Continuation rate is about the course, not the ",
                              "instructor."), " A section full of majors ",
                  "continues at a different rate than one full of students ",
                  "filling a requirement, whoever teaches it."),
          tags$li(tags$strong("Small groups move a lot."),
                  " Raise the minimum student count if a rate looks extreme; ",
                  "a handful of students can swing a percentage several points."),
          tags$li(tags$strong("The grade window ends before advance registration."),
                  " CEDAR may already contain students registered for the current ",
                  "term even though none has a posted grade. Those rows are not ",
                  "failures: outcomes stop at the most recent term with grades, ",
                  "and students too recent to have a complete follow-up term are ",
                  "excluded from the continuation denominator. The exact terms ",
                  "and exclusion counts appear in the methodology after you run ",
                  "the comparison.")
        )
      ),
      fluidRow(
        column(5,
          selectizeInput("cr_impact_inst_course_y", "Later course(s):",
                         choices  = cr_downstream_choices(
                           cr_downstream_options(), include_rollup = TRUE,
                           dept = cr_course_dept()),
                         multiple = TRUE,
                         options = list(placeholder = "Choose one or more later courses...")),
          helpText("The list includes courses students actually took later across departments; department ownership and continuation share do not determine whether a sequence is intended. Dropdown percentages and the blue course-wide continuation rate use the same eligibility-adjusted denominator: students with a complete follow-up window, excluding those who had already passed a single selected later course. Select multiple courses to audit combined prior, concurrent, and later enrollment patterns.")
        ),
        column(2,
          numericInput("cr_impact_inst_min_n", "Min students per instructor:", value = 15, min = 5, max = 100)
        ),
        column(3,
          br(),
          actionButton("cr_impact_inst_run", "Compare Outcomes",
                       icon = icon("play"), class = "btn-primary")
        )
      ),
      uiOutput("cr_impact_instructor_results")
    )
  })

  observeEvent(input$cr_impact_inst_run, {
    req(input$cr_course, nzchar(input$cr_course),
        length(input$cr_impact_inst_course_y) > 0,
        all(nzchar(input$cr_impact_inst_course_y)))
    cr_impact_instructor_data(NULL)

    # The picker's first entry is a sentinel meaning "every follow-on course in
    # this department". Resolve it to the actual course list here so the cone
    # only ever sees course codes.
    y_sel <- input$cr_impact_inst_course_y
    if (CR_ROLLUP_SENTINEL %in% y_sel) {
      same_dept <- cr_downstream_options() %>% dplyr::filter(same_dept %in% TRUE)
      if (nrow(same_dept) == 0) {
        showNotification(
          "No follow-on courses in this department cleared the minimum student count.",
          type = "warning", duration = 8)
        return(NULL)
      }
      y_sel <- same_dept$subject_course
    }

    opt <- list(
      course_x = input$cr_course,
      course_y = y_sel,
      min_n    = as.integer(input$cr_impact_inst_min_n %||% 15L),
      campus   = if (length(input$cr_campus) > 0) input$cr_campus else NULL
    )

    withProgress(message = "Comparing downstream success...", value = 0.3, {
      tryCatch({
        result <- get_instructor_effect(
          students     = data_objects[["cedar_students"]],
          programs     = data_objects[["cedar_programs"]],
          applicants   = data_objects[["cedar_applicants"]],
          opt          = opt,
          term_credits = data_objects[["cedar_student_term_credits"]],
          data_edges   = data_objects[["cedar_edges"]]
        )
        cr_impact_instructor_data(result)
        setProgress(1)
      }, error = function(e) {
        showNotification(paste("Downstream success analysis failed:", conditionMessage(e)),
                         type = "error", duration = 10)
        message("[server.R] cr_impact_inst error: ", conditionMessage(e))
      })
    })
  })

  output$cr_impact_instructor_results <- renderUI({
    result <- cr_impact_instructor_data()
    if (is.null(result)) return(NULL)

    fmt_term <- function(t) {
      yr <- t %/% 100; ss <- t %% 100
      paste(dplyr::case_when(ss==10~"Spring", ss==60~"Summer", ss==80~"Fall",
                             TRUE~as.character(ss)), yr)
    }

    x_period <- paste0(fmt_term(result$term_range_x[1]), "–", fmt_term(result$term_range_x[2]))
    y_period <- paste0(fmt_term(result$term_range_y[1]), "–", fmt_term(result$term_range_y[2]))

    # In rollup mode course_y is a vector, so every piece of prose below uses the
    # label rather than the raw value.
    y_label <- result$course_y_label %||% result$course_y
    audit <- result$course_summary
    continuation_avg <- audit$pct_took_y[[1]]
    dfw_avg <- round(100 * (sum(result$outcomes$n_failed) +
                             sum(result$outcomes$n_dropped)) /
                       sum(result$outcomes$n_outcome_observed), 1)
    outcomes_display <- prepare_downstream_outcomes_display(result$outcomes)
    outcome_counts <- attr(outcomes_display, "pct_count_n")
    outcome_columns <- c(
      list(
        Instructor = reactable::colDef(minWidth = 180),
        `Students in X` = reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 0, separators = TRUE)
        ),
        `Eligible for Y` = reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 0, separators = TRUE)
        )
      ),
      stats::setNames(
        lapply(outcome_counts, cr_pct_count_coldef),
        names(outcome_counts)
      )
    )

    tagList(
      if (isTRUE(result$rollup)) div(
        class = "alert alert-info", style = "font-size: 0.88em;",
        icon("layer-group"), " ",
        tags$strong("Department summary."), " Each student is counted once, at ",
        "the first of these courses they took after ", result$course_x, ". ",
        "Courses included (", result$n_courses_y, "): ",
        paste(result$course_y, collapse = ", "), "."
      ),
      # Methodology, not a warning — collapsible per the explain-box standard.
      info_panel(
        paste0("How to read this table — ", result$course_x, " \u2192 ", y_label),
        description = "What the comparison does, and what each column means.",
        div(class = "alert alert-info", style = "font-size: 0.9em;",
          icon("calendar-check"), " ",
          tags$strong("Data window: "), result$edge_note,
          " Students taking ", result$course_x,
          " too recently to have one complete subsequent regular term are excluded ",
          "from the continuation denominator."
        ),
        tags$b("What the analysis does:"), " For each instructor who taught ",
        strong(result$course_x), " (", x_period, "), this shows how their students ",
        "performed later when those students took ", strong(y_label),
        " (", y_period, "). Any gap between the two courses counts — it does not have ",
        "to be the immediately following term. A student who repeated ", result$course_x,
        " under more than one instructor is assigned once, to the first instructor, ",
        "in the downstream outcomes table. Course-order totals are aggregated by year ",
        "and never attributed to an instructor.", br(), br(),
        tags$b("Column definitions:"), br(),
        tags$ul(style = "margin-bottom: 4px;",
          tags$li(strong("Students in X"), " — students attributed to this instructor at their ",
                  "first ", result$course_x, " attempt through ",
                  paste0(fmt_term(result$observation_end_term),
                         ". Current or otherwise incomplete terms are not included.")),
          tags$li(strong("Eligible for Y"), " — Students in X after removing students without ",
                  "a complete follow-up opportunity",
                  if (isTRUE(result$prior_pass_exclusion_applied)) {
                    paste0(" and students who had already passed ", y_label, ".")
                  } else {
                    "."
                  },
                  " This is the continuation denominator."),
          tags$li(strong("Continued to Y % (n)"), " — share of eligible students who later ",
                  "enrolled in ", y_label, "; the count is in parentheses. Course-wide average: ",
                  strong(paste0(continuation_avg, "%")),
                  ". Wide variation usually reflects section composition (time-of-day, major vs. requirement-filler mix) ",
                  "rather than instructor influence — treat outliers as a prompt to investigate, not a verdict."),
          tags$li(strong("Classified outcomes % (n)"), " — share and count of later ",
                  "enrollments with a classifiable final outcome. Blank, incomplete, audit, ",
                  "and otherwise unknown outcomes stay in Continued to Y but are not failures."),
          tags$li(strong("Passed / Failed / Late drops % (n)"), " — mutually exclusive shares ",
                  "of classified outcomes, with counts in parentheses. Passing is C− or better, ",
                  "CR, P, or S; Failed is a canonical D/F/W grade; Late drops are DG or DW statuses."),
          tags$li(strong("DFW % (n)"), " — failed grades plus late drops divided by classified ",
                  "outcomes, with their combined count in parentheses.")
        ),
        tags$b("How to read a combined cell:"), " ",
        tags$span(class = "text-nowrap", "76.0% (45)"),
        " means 76.0% and 45 students."
      ),

      dashboard_subsection(
        "Who was actually eligible to continue?",
        paste0("This audit reconciles persistence with course progression. Returning to UNM ",
               "the next term does not imply taking ", y_label,
               ", and passing a course before or concurrently with ", result$course_x,
               " is not evidence of later progression from X to Y."),
        div(class = "alert alert-info", style = "font-size: 0.9em; margin-bottom: 10px;",
          tags$strong(format(audit$n_total_in_x, big.mark = ",")),
          " students took ", result$course_x, " in the selected campus scope. ",
          tags$strong(format(audit$n_right_censored, big.mark = ",")),
          " were too close to the right edge for a complete follow-up window; ",
          tags$strong(format(audit$n_passed_y_before_x, big.mark = ",")),
          " had passed ", y_label, " in a strictly earlier term; and ",
          tags$strong(format(audit$n_passed_y_same_term, big.mark = ",")),
          " passed one or more selected courses concurrently. The continuation denominator is ",
          tags$strong(format(audit$n_eligible_for_y, big.mark = ",")), ".",
          tags$br(),
          tags$strong("Instructor table scope: "),
          "Students in X includes first-attributed students through ",
          paste0(fmt_term(result$observation_end_term),
                 ", not the current or an incomplete term. Eligible for Y removes students "),
          "without a complete follow-up opportunity",
          if (isTRUE(result$prior_pass_exclusion_applied)) {
            paste0(" and those who had already passed ", y_label, ".")
          } else {
            "."
          },
          " Right-edge and course-order counts are summarized here rather than repeated ",
          "for every instructor."
        ),
        h5("Students taking the courses out of order, by year"),
        p(style = "font-size: 0.82em; color: #666;",
          "Each student appears once, in the calendar year of their first ",
          result$course_x, " attempt. A strictly earlier pass is genuinely out of order; ",
          "a same-term pass is concurrent and is shown separately. Before-or-same is ",
          "their student-level union, not their sum."),
        cr_basic_reactable(
          cr_humanize_columns(result$order_audit_by_year),
          default_page_size = 25L,
          searchable = FALSE
        )
      ),

      dashboard_subsection(
        paste0("Downstream Outcomes in ", y_label,
               " by Instructor in ", result$course_x),
        "Compares downstream outcomes for students grouped by their instructor in the selected course. Use the course-wide averages as context, and treat differences as prompts for review rather than causal effects.",
        div(class = "alert alert-info", style = "font-size: 0.88em; margin-bottom: 10px;",
          icon("lightbulb"), " ",
          tags$strong("Course-wide averages for context:"), tags$br(),
          tags$b("Continuation rate"), " (% of ", result$course_x, " students who took ",
          y_label, "): ",
          tags$span(style = "font-size: 1.1em;",
            strong(paste0(continuation_avg, "%"))), tags$br(),
          tags$b("DFW rate in ", y_label), " (across instructors shown): ",
          tags$span(style = "font-size: 1.1em;",
            strong(paste0(dfw_avg, "%"))),
          tags$br(),
          tags$span(style = "font-size: 0.85em;",
            "Compare each instructor's Continued to Y and DFW cells against these baselines. ",
            "Large departures are worth investigating but may reflect section composition, not instructor effect.")
        )
      ),
      cr_cedar_reactable(
        outcomes_display,
        columns = outcome_columns,
        default_page_size = 25L,
        searchable = TRUE
      ),

      # This is optional context for interpreting differences between two
      # instructor rows. It does not define or adjust the descriptive course-
      # level continuation and downstream-outcome measures above.
      dashboard_subsection(
        "Optional context: were the two largest instructor groups similar?",
        paste0("The continuation and downstream-outcome counts above use all eligible ",
               "students and do not require instructor groups to be similar. This ",
               "diagnostic matters only if you want to interpret a difference between ",
               "two instructor rows as possibly instructor-related rather than a ",
               "difference in who enrolled."),
        div(class = "alert alert-info", style = "font-size: 0.88em; margin-bottom: 10px;",
          icon("circle-info"), " ",
          tags$strong("Why only two instructors?"), " Balance is a pairwise question, ",
          "so the app automatically uses the two instructors with the most downstream ",
          "students for the most stable, readable comparison.", tags$br(),
          tags$strong("Instructor A: "),
          result$reference_instructor %||% "\u2014", " (n = ", result$n_treatment, "); ",
          tags$strong("Instructor B: "),
          result$comparison_instructor %||% "\u2014", " (n = ", result$n_control, ").",
          if (!is.null(result$instructor_counts) &&
              nrow(result$instructor_counts) > 2) {
            tagList(" The other ", tags$strong(nrow(result$instructor_counts) - 2L),
                    " instructor groups remain in the outcomes table above; they are ",
                    "not sampled away, but this diagnostic says nothing about their comparability.")
          },
          tags$br(),
          tags$strong("What this changes: "),
          "nothing in the rates above. It neither matches students nor adjusts outcomes. ",
          "Use it only as a caution when comparing Instructor A with Instructor B. ",
          "The Course Sequence view is where comparable groups are central to comparing ",
          "students who did versus did not take a precursor course."
        ),
        .render_balance_table(
          result$balance,
          group_labels = c("Instructor A", "Instructor B")
        )
      ),

    )
  })

  # Debug outputs for Course Dynamics
  output$cr_debug_tables <- renderPrint({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data)) {
      cat("Table names:\n")
      print(names(data$tables))
      cat("\nTable structures:\n")
      for(i in 1:min(3, length(data$tables))) {
        if (!is.null(data$tables[[i]])) {
          cat(paste("\n", names(data$tables)[i], ":\n"))
          print(str(data$tables[[i]]))
        }
      }
    } else {
      "No tables found"
    }
  })

  output$cr_debug_plots <- renderPrint({
    data <- course_report_data()
    if (!is.null(data) && "plots" %in% names(data)) {
      cat("Plot names:\n")
      print(names(data$plots))
      
      cat("\nSankey plots specifically:\n")
      sankey_names <- names(data$plots)[grepl("sankey_.*_plot", names(data$plots))]
      if (length(sankey_names) > 0) {
        print(sankey_names)
      } else {
        cat("NO SANKEY PLOTS FOUND\n")
      }
      
      cat("\nPlot types:\n")
      for(i in 1:min(5, length(data$plots))) {
        cat(paste("\n", names(data$plots)[i], ": ", class(data$plots[[i]])[1], "\n"))
      }
      
      # Check if course-neighbors data exists
      if ("tables" %in% names(data)) {
        cat("\nCourse-neighbors data availability:\n")
        cat("where_from exists: ", !is.null(data$tables$where_from), "\n")
        cat("where_to exists: ", !is.null(data$tables$where_to), "\n")
        if (!is.null(data$tables$where_from)) {
          cat("where_from rows: ", nrow(data$tables$where_from), "\n")
        }
        if (!is.null(data$tables$where_to)) {
          cat("where_to rows: ", nrow(data$tables$where_to), "\n")  
        }
      }
    } else {
      "No plots found"
    }
  })



  # ===========================================================================
  # Open Seats tab (Shiny module)
  # ===========================================================================
  seatfinderServer("seatfinder", cedar_students, cedar_sections, cedar_faculty,
                   error_handler = handle_error)

  # ===========================================================================
  # Cancellations tab (Shiny module)
  # ===========================================================================
  cancellationsServer("cancellations", cedar_sections, error_handler = handle_error)

  # ===========================================================================
  # Waitlists tab (Shiny module)
  # ===========================================================================
  waitlistServer("waitlist", cedar_students, session,
                 sections = data_objects[["cedar_sections"]])


  # ===========================================================================
  # Regstats tab (Shiny module)
  # ===========================================================================
  regstatsServer("regstats",
    students     = cedar_students,
    sections     = cedar_sections,
    course_flows = cedar_course_flows,
    data_summary = cedar_data_summary,
    thresholds   = cedar_regstats_thresholds
  )

  # ===========================================================================
  # Gen Ed tab (Shiny module)
  # ===========================================================================
  genEdExploreServer("gen_ed",
    students = cedar_students,
    sections = cedar_sections,
    programs = cedar_programs,
    degrees = cedar_degrees,
    current_term = cedar_current_term
  )

  #################################
  ##### EXPLORE YOUR UNIT DASHBOARD
  #################################

  dashboard_data <- reactiveVal(NULL)
  dashboard_loaded_key <- reactiveVal(NULL)

  dashboard_filter_key <- function(dept, campus, term) {
    dept <- if (is.null(dept) || length(dept) == 0) "" else as.character(dept[[1]])
    campus <- if (is.null(campus) || length(campus) == 0) "" else paste(sort(as.character(campus)), collapse = ",")
    term <- suppressWarnings(as.integer(term))
    term <- if (length(term) == 0 || is.na(term)) "" else as.character(term[[1]])
    paste(dept, campus, term, sep = "|")
  }

  # Dashboard color palette and table constants
  .dash_up       <- "#2e7d32"  # green — above average / positive trend
  .dash_down     <- "#c62828"  # red   — below average / negative trend
  .dash_neu      <- "#777777"  # grey  — neutral / no trend
  .dash_max_rows <- 8L         # max rows shown per course table

  # Render a single trend line: "1yr: ↑ 12%" with the arrow colored
  trend_line <- function(period_label, pct) {
    if (is.na(pct)) return(tags$span(
      style = "color: #aaa; white-space: nowrap;",
      paste0(period_label, ": —")
    ))
    color <- if (pct > 0) .dash_up else if (pct < 0) .dash_down else .dash_neu
    arrow <- if (pct > 0) "↑" else if (pct < 0) "↓" else "→"
    tags$span(
      style = "white-space: nowrap;",
      tags$span(class = "text-muted", paste0(period_label, ": ")),
      tags$span(style = paste0("color: ", color, "; font-weight: 600;"),
                paste0(arrow, " ", abs(pct), "%"))
    )
  }

  # Filter department choices to only depts with sections at the selected campus(es).
  # When no campus is selected, show all departments.
  # ignoreInit = TRUE: .dept_choices is already pre-filtered to the default ABQ+EA
  # campuses in ui.R, so an on-init update is a no-op that still triggers a
  # selectize round-trip, which briefly emits value="" and blanks the dashboard.
  observeEvent(input$dashboard_campus, {
    campus <- input$dashboard_campus
    if (is.null(campus) || length(campus) == 0) {
      choices <- c("Select a department..." = "", .dept_choices)
    } else {
      depts_at_campus <- sort(unique(cedar_sections$department[
        !is.na(cedar_sections$department) &
        cedar_sections$department != "" &
        cedar_sections$campus %in% campus
      ]))
      # Filter .dept_choices to those present at the selected campus
      filtered <- .dept_choices[.dept_choices %in% depts_at_campus]
      choices <- c("Select a department..." = "", filtered)
    }
    # Preserve the user's current dept selection when updating choices.
    # Passing only choices (no selected) can still cause selectize.js to briefly
    # fire inputchanged with value="" during the widget update, which triggers the
    # data-loading observer, sets dashboard_data(NULL), and blanks the dashboard.
    # Explicitly re-passing the current selection prevents this. Use isolate() to
    # avoid adding input$dashboard_dept as a reactive dependency of this observer.
    # Only set selected if the current dept is still valid in the new choices;
    # if the campus changed and the dept is gone, let selectize.js deselect naturally.
    current_dept <- isolate(input$dashboard_dept)
    if (!is.null(current_dept) && nchar(current_dept) > 0 &&
        current_dept %in% unname(choices)) {
      updateSelectizeInput(session, "dashboard_dept", choices = choices,
                           selected = current_dept)
    } else {
      updateSelectizeInput(session, "dashboard_dept", choices = choices)
    }
  }, ignoreInit = TRUE)

  # Load dashboard data on demand — the user picks campus, department, and term,
  # then clicks "Gather Data" (input$dashboard_button). No auto-fire on selection
  # change: nothing loads until the button is pressed, so the term choice is
  # applied together with campus/dept in a single pass.
  dashboard_run <- cedar_run_trigger(input, session, "dashboard_button", "Dept Dashboard")
  observeEvent(dashboard_run(), {
    dept   <- input$dashboard_dept
    campus <- input$dashboard_campus
    term   <- suppressWarnings(as.integer(input$dashboard_term))
    request_key <- dashboard_filter_key(dept, campus, term)

    # Guard: without a department there is nothing to build. Clear the overlay
    # (a button click always raises it) and prompt rather than hanging.
    if (is.null(dept) || dept == "") {
      dashboard_data(NULL)
      dashboard_loaded_key(NULL)
      signal_load_complete(session, "dashboard")
      showNotification("Select a department first.", type = "warning", duration = 4)
      return()
    }

    log_data_filter(session, "dashboard_dept", dept)
    log_report_generation(session, "dept_dashboard", list(
      dept_code = dept,
      campus = campus,
      term = term
    ))
    dashboard_data(NULL)
    dashboard_loaded_key(NULL)

    timer <- start_report_timer("dept_dashboard", list(dept_code = dept, term = term))

    tryCatch({
      campus_val <- if (is.null(campus) || length(campus) == 0) NULL else campus
      term_val   <- if (length(term) == 0 || is.na(term)) NULL else term
      opt <- list(dept_code = dept, campus = campus_val, term = term_val, shiny = TRUE)
      cached <- load_dept_dashboard_cache(opt, data_objects)
      if (!is.null(cached)) {
        d <- cached
        duration_sec <- end_report_timer(timer, cached = TRUE)
      } else {
        d <- create_dept_dashboard_data(data_objects, opt)
        save_dept_dashboard_cache(opt, d, data_objects)
        duration_sec <- end_report_timer(timer, cached = FALSE)
      }
      # DEBUG: uncomment to diagnose false-positive "new this term" courses
      # course_history <- get_dept_course_enrl_history(data_objects[["cedar_sections"]], d$dept_code)
      # diagnose_new_this_term(course_history, if (exists("cedar_current_term")) cedar_current_term else max(course_history$term))
      dashboard_data(d)
      dashboard_loaded_key(request_key)
      signal_load_complete(session, "dashboard", duration_sec = duration_sec,
                           cached = !is.null(cached))
    }, error = function(e) {
      tryCatch(end_report_timer(timer), error = function(e2) NULL)
      dashboard_loaded_key(NULL)
      signal_load_complete(session, "dashboard", error = TRUE)
      showNotification(paste("Dashboard error:", conditionMessage(e)), type = "error", duration = 5)
      message("[server.R] Dashboard error: ", conditionMessage(e))
    })
  })

  # Subject selector — populated from cedar_sections for the selected dept
  # Subject dropdown removed: dashboard now only uses campus and department selectors

  # Program transparency info box — shows which subject and program codes are
  # matched for the selected department. Purely reactive; no heavy data load.
  dept_scope_info_ui <- function(dept) {
    dept_name_label <- if (exists("dept_code_to_name") && dept %in% names(dept_code_to_name))
      dept_code_to_name[[dept]] else dept

    # Subject codes: course prefixes in cedar_sections that map to this dept
    subj_codes <- if (exists("subj_dept_map")) {
      sort(subj_dept_map$subject_code[!is.na(subj_dept_map$dept_code) &
                                        subj_dept_map$dept_code == dept])
    } else character(0)

    # Program codes: Banner program codes in cedar_programs for this dept
    prog_rows <- if (exists("program_map")) {
      pm <- program_map[!is.na(program_map$dept_code) & program_map$dept_code == dept, ]
      pm[!is.na(pm$program_code), ]
    } else NULL

    degree_codes  <- if (!is.null(prog_rows)) sort(prog_rows$program_code[prog_rows$program_type == "degree"])   else character(0)
    variant_codes <- if (!is.null(prog_rows)) sort(prog_rows$program_code[prog_rows$program_type == "variant"])  else character(0)
    premaj_codes  <- if (!is.null(prog_rows)) sort(prog_rows$program_code[prog_rows$program_type == "pre_major"]) else character(0)

    code_pill <- function(code) {
      tags$code(
        class = "filter-context-code",
        code
      )
    }

    row_item <- function(label, codes) {
      if (length(codes) == 0) return(NULL)
      tags$div(
        class = "filter-context-row filter-context-row-inline",
        tags$span(label, class = "filter-context-label"),
        lapply(codes, code_pill)
      )
    }

    filter_scope_stripe(
      div(
        class = "scope-bar scope-bar--stacked",
        div(
          class = "filter-context-title",
          paste0("Data scope for ", dept_name_label, " (dept code: ", dept, ")")
        ),
        div(
          class = "filter-context-inline-list",
          row_item("Course subject codes (cedar_sections):", subj_codes),
          row_item("Degree program codes (cedar_programs):",  degree_codes),
          row_item("Variant codes (X-prefix):",               variant_codes),
          row_item("Pre-major codes (F-prefix):",             premaj_codes)
        )
      )
    )
  }

  deptTrendsServer(
    "dept_trends",
    data_objects = data_objects,
    dept_choices = .dept_choices,
    current_term = cedar_current_term,
    error_handler = handle_error,
    scope_info_ui = dept_scope_info_ui,
    dfw_password = dfw_password
  )

  # TRUE only when dashboard_data() was produced by the filters currently on
  # screen. Changing any filter invalidates it until Gather Data runs again.
  # Single definition so the scope strip and the content panel can never
  # disagree about whether the dashboard is showing real results.
  dashboard_data_is_current <- reactive({
    loaded_key <- dashboard_loaded_key()
    current_key <- dashboard_filter_key(input$dashboard_dept, input$dashboard_campus, input$dashboard_term)
    !is.null(dashboard_data()) && !is.null(loaded_key) && identical(loaded_key, current_key)
  })

  # Scope strip stays hidden until Gather Data has actually returned results.
  # It used to appear the moment a department was picked, which read as "the
  # page is loading" when in fact nothing had been requested yet.
  output$dashboard_program_info <- renderUI({
    req(dashboard_data_is_current())
    dept <- input$dashboard_dept
    req(dept, dept != "")
    dept_scope_info_ui(dept)
  })

  output$dashboard_has_loaded_data <- renderText({
    if (dashboard_data_is_current()) "true" else "false"
  })
  outputOptions(output, "dashboard_has_loaded_data", suspendWhenHidden = FALSE)

  # Headcount stat cards — count alone (no arrow), then 6yr and 3yr pct trends.
  # When a subject is selected, show current-term enrollment summary for that subject
  # instead of the multi-year headcount cards.
  output$dashboard_headcount_cards <- renderUI({
    subj <- input$dashboard_subject

    # Subject mode: quick stats from cedar_sections for the selected subject
    if (!is.null(subj) && nchar(subj) > 0) {
      ct    <- if (exists("cedar_current_term")) cedar_current_term else NA_integer_
      stats <- get_subject_current_stats(cedar_sections, subj, ct)

      make_simple_card <- function(count, label) {
        div(
          style = paste0(
            "background: #f8f9fa; border-radius: 8px; padding: 14px 18px; ",
            "text-align: center; border-top: 3px solid #dee2e6;"
          ),
          div(style = "font-size: 2rem; font-weight: 700; color: #222;", count),
          div(style = "font-size: 0.85rem; color: #444; margin-top: 4px; font-weight: 600;", label)
        )
      }

      return(fluidRow(
        column(3, make_simple_card(stats$total_enrl, paste0(subj, " enrolled (current term)"))),
        column(3, make_simple_card(stats$n_sections, paste0(subj, " sections (current term)")))
      ))
    }

    # Department mode: normal multi-year headcount summary cards
    d <- dashboard_data()
    req(d)

    hc <- d$headcount_summary
    if (is.null(hc) || nrow(hc) == 0) return(NULL)

    make_card <- function(label, count, pct_1yr, pct_3yr, pct_6yr, transparent = FALSE) {
      opacity_style <- if (transparent) "opacity: 0.65;" else ""
      div(
        style = paste0(
          "background: #f8f9fa; border-radius: 8px; padding: 14px 18px; ",
          "text-align: center; border-top: 3px solid #dee2e6; ", opacity_style
        ),
        div(style = "font-size: 2rem; font-weight: 700; color: #222;", count),
        div(style = "font-size: 0.85rem; color: #444; margin-top: 4px; font-weight: 600;",
            label),
        div(
          style = paste(
            "font-size: 0.72rem; margin-top: 8px; line-height: 1.2;",
            "display: flex; justify-content: center; gap: 8px;",
            "white-space: nowrap;"
          ),
          trend_line("1yr", pct_1yr),
          trend_line("3yr", pct_3yr),
          trend_line("6yr", pct_6yr)
        )
      )
    }

    render_tier_row <- function(tier_label) {
      tier_rows <- hc %>%
        dplyr::filter(tier == tier_label) %>%
        dplyr::filter(is_total | current_count > 0)

      cards <- lapply(seq_len(nrow(tier_rows)), function(i) {
        row <- tier_rows[i, ]
        column(3, make_card(
          row$group, row$current_count,
          row$pct_change_1yr, row$pct_change_3yr, row$pct_change_6yr,
          transparent = !isTRUE(row$is_total)
        ))
      })
      fluidRow(!!!cards)
    }

    tagList(
      render_tier_row("undergrad"),
      render_tier_row("grad"),
      div(
        style = "font-size: 0.75rem; color: #999; margin-top: 6px; padding-left: 2px;",
        "Counts reflect the selected term. Trend percentages compare that term to the same term in prior years."
      )
    )
  })

  # Headcount sparkline (static ggplot — no hover).
  # Hidden when a subject is selected (sparklines show dept-level trends, not subject).
  output$dashboard_headcount_sparkline <- renderPlot({
    subj <- input$dashboard_subject
    if (!is.null(subj) && nchar(subj) > 0) return(NULL)
    d <- dashboard_data()
    req(d)
    req(d$headcount_series)
    make_headcount_sparklines(d$headcount_series)
  }, bg = "transparent", height = 200)

  output$dashboard_credit_hour_shifts <- renderUI({
    d <- dashboard_data()
    req(d)
    shifts <- d$credit_hour_shifts
    if (is.null(shifts) || nrow(shifts) == 0) {
      return(p(
        "No credit-hour shifts clear the dashboard threshold for this term.",
        class = "cedar-dashboard-empty-note"
      ))
    }

    fmt_ch <- function(x) {
      ifelse(is.na(x), "-", scales::comma(round(x)))
    }
    fmt_diff <- function(diff, pct) {
      if (is.na(diff)) return("-")
      sign_chr <- if (diff > 0) "+" else ""
      pct_txt <- if (!is.na(pct)) paste0(" (", sign_chr, round(pct, 1), "%)") else ""
      paste0(sign_chr, scales::comma(round(diff)), pct_txt)
    }
    diff_color <- function(x) {
      ifelse(is.na(x), "#666", ifelse(x > 0, "#7A5010", "#2e7d32"))
    }
    cell_left <- "padding: 4px 10px 4px 0; font-weight: 600;"
    cell_num <- "padding: 4px 10px; text-align: right; white-space: nowrap;"
    hint_style <- "margin-top: 6px;"

    rows <- lapply(seq_len(nrow(shifts)), function(i) {
      r <- shifts[i, ]
      tags$tr(
        tags$td(style = cell_left, r$level),
        tags$td(style = cell_num,
                fmt_ch(r$current_credit_hours)),
        tags$td(style = paste0(cell_num, " color: #666;"),
                fmt_ch(r$hist_avg_credit_hours)),
        tags$td(
          style = paste0(
            "padding: 4px 0 4px 10px; text-align: right; white-space: nowrap;",
            " font-weight: 700; color: ", diff_color(r$diff), ";"
          ),
          fmt_diff(r$diff, r$pct_diff)
        )
      )
    })

    tagList(
      tags$table(
        class = "table table-sm",
        style = "font-size: 0.84em; margin-bottom: 0;",
        tags$thead(tags$tr(
          tags$th("Level"),
          tags$th(style = "text-align: right;", "Current SCH"),
          tags$th(style = "text-align: right;", "Recent Norm"),
          tags$th(style = "text-align: right;", "Difference")
        )),
        tags$tbody(rows)
      ),
      p(
        "Dashboard threshold: at least 25 SCH and 10% away from the prior three same-season terms. Full trendlines are in Dept Trends > Enrollment.",
        class = "text-hint",
        style = hint_style
      )
    )
  })

  output$dashboard_composition_shifts <- renderUI({
    d <- dashboard_data()
    req(d)
    shifts <- d$composition_shifts
    if (is.null(shifts) || nrow(shifts) == 0) {
      return(p(
        "No audience shifts clear the dashboard threshold for this term.",
        class = "text-hint"
      ))
    }

    fmt_share <- function(x) ifelse(is.na(x), "-", paste0(round(x, 1), "%"))
    fmt_diff <- function(x) {
      ifelse(
        is.na(x), "-",
        paste0(ifelse(x > 0, "+", ""), round(x, 1), " pts")
      )
    }
    diff_color <- function(x) {
      ifelse(is.na(x), "#666", ifelse(x > 0, "#7A5010", "#2e7d32"))
    }
    cell_signal <- "padding: 4px 10px 4px 0; font-weight: 600; white-space: nowrap;"
    cell_text <- "padding: 4px 10px; color: #555;"
    cell_num <- "padding: 4px 10px; text-align: right; white-space: nowrap;"

    rows <- lapply(seq_len(min(nrow(shifts), 10L)), function(i) {
      r <- shifts[i, ]
      tags$tr(
        tags$td(style = cell_signal, r$signal),
        tags$td(style = cell_text, r$group),
        tags$td(style = paste0(cell_text, " color: #333;"), r$category),
        tags$td(style = cell_num,
                fmt_share(r$current_share)),
        tags$td(style = paste0(cell_num, " color: #666;"),
                fmt_share(r$hist_avg_share)),
        tags$td(
          style = paste0(
            "padding: 4px 0 4px 10px; text-align: right; white-space: nowrap;",
            " font-weight: 700; color: ", diff_color(r$diff_pp), ";"
          ),
          fmt_diff(r$diff_pp)
        )
      )
    })

    tagList(
      tags$table(
        class = "table table-sm",
        style = "font-size: 0.84em; margin-bottom: 0;",
        tags$thead(tags$tr(
          tags$th("Signal"),
          tags$th("Group"),
          tags$th("Category"),
          tags$th(style = "text-align: right;", "Current"),
          tags$th(style = "text-align: right;", "Recent Norm"),
          tags$th(style = "text-align: right;", "Difference")
        )),
        tags$tbody(rows)
      )
    )
  })

  # Helper: format an enrollment diff as "↑34% (+12)" or "↓8% (−5)"
  fmt_enrl_diff <- function(diff, pct) {
    if (is.na(diff)) return("")
    arrow_chr <- if (diff > 0) "↑" else if (diff < 0) "↓" else "→"
    sign_chr  <- if (diff >= 0) "+" else "−"
    count_str <- paste0(" (", sign_chr, abs(diff), ")")
    if (!is.na(pct)) paste0(arrow_chr, abs(pct), "%", count_str) else paste0(sign_chr, abs(diff))
  }

  fmt_enrl_avg_context <- function(r) {
    label <- if ("hist_window_label" %in% names(r) && !is.na(r$hist_window_label)) {
      r$hist_window_label
    } else {
      "avg"
    }
    paste0(label, " ", round(r$hist_avg_enrl, 0))
  }

  # Current enrollment vs historical avg — above average
  # Helper: build a <table class="table table-sm"> from a list of tags$tr() items.
  # Each column gets a td_style vector element. empty_msg shown when rows is empty.
  .make_dashboard_table <- function(rows, empty_msg = "No data available.") {
    if (length(rows) == 0)
      return(p(empty_msg, style = "color: #999; font-size: 0.85em;"))
    tags$table(
      class = "table table-sm",
      style = "font-size: 0.82em; margin-bottom: 0;",
      lapply(rows, identity)
    )
  }

  # Campus tag for dashboard course rows. Course history is per-campus (campuses
  # are never merged), so in an "all campuses" view the same course can appear
  # once per campus — tag the rows whenever a table spans more than one campus.
  .campus_suffix <- function(r, x) {
    if (!"campus" %in% names(x) || dplyr::n_distinct(x$campus) <= 1) return("")
    paste0(" (", r$campus, ")")
  }

  # Render a standard dashboard course table, capping at max_rows (default: .dash_max_rows).
  # Pass max_rows = Inf to render all rows without a cap.
  # row_fn(i, data) should return a tags$tr() for row i.
  .render_course_table <- function(data, row_fn, empty_msg = "No courses to display", max_rows = .dash_max_rows) {
    if (is.null(data) || nrow(data) == 0) {
      return(p(empty_msg, class = "cedar-dashboard-empty-note"))
    }
    .make_dashboard_table(lapply(seq_len(min(max_rows, nrow(data))), function(i) row_fn(i, data)))
  }

  output$dashboard_above_avg_courses <- renderUI({
    d <- dashboard_data(); req(d)
    .render_course_table(d$current_enrl_vs_avg$above,
                         empty_msg = "No courses running above their historical average.",
                         function(i, x) {
      r        <- x[i, ]
      diff_str <- fmt_enrl_diff(r$diff, r$pct_diff)
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_up, ";"),
                paste0(diff_str, " vs ", fmt_enrl_avg_context(r)))
      )
    })
  })

  # Current enrollment vs historical avg — below average
  output$dashboard_below_avg_courses <- renderUI({
    d <- dashboard_data(); req(d)
    .render_course_table(d$current_enrl_vs_avg$below,
                         empty_msg = "No courses running below their historical average.",
                         function(i, x) {
      r        <- x[i, ]
      diff_str <- fmt_enrl_diff(r$diff, r$pct_diff)
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_down, ";"),
                paste0(diff_str, " vs ", fmt_enrl_avg_context(r)))
      )
    })
  })

  output$dashboard_high_waitlist_table <- reactable::renderReactable({
    d <- dashboard_data(); req(d)
    flags <- d$enrollment_flags$high_waitlist

    make_waitlist_course_overview_reactable(
      flags,
      empty_msg = "No selected-term courses with waitlists.",
      include_supply = FALSE,
      include_hist_terms = FALSE,
      searchable = TRUE,
      defaultPageSize = 10,
      showPageSizeOptions = TRUE,
      pageSizeOptions = c(10, 25, 50)
    )
  })

  output$dashboard_early_drop_watch <- renderUI({
    d <- dashboard_data(); req(d)
    flags <- format_dashboard_early_drop_watch(d$regstats_flags)
    .render_course_table(flags,
                         empty_msg = "No selected-term courses with elevated early drops under dashboard thresholds.",
                         function(i, x) {
      r <- x[i, ]
      diff_txt <- if (!is.na(r$diff)) paste0("+", r$diff, " vs hist") else ""
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$drop_early, " early drops")),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap; color: #666;",
                paste0("hist ", r$hist_avg)),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_down, ";"),
                diff_txt)
      )
    })
  })

  output$dashboard_late_drop_watch <- renderUI({
    d <- dashboard_data(); req(d)
    flags <- format_dashboard_late_drop_watch(d$regstats_flags)
    .render_course_table(flags,
                         empty_msg = "No selected-term courses with elevated late drops under dashboard thresholds.",
                         function(i, x) {
      r <- x[i, ]
      diff_txt <- if (!is.na(r$diff)) paste0("+", r$diff, " vs hist") else ""
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$drop_late, " late drops")),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap; color: #666;",
                paste0("hist ", r$hist_avg)),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_down, ";"),
                diff_txt)
      )
    })
  })

  output$dashboard_low_enrollment_review_summary <- renderUI({
    d <- dashboard_data(); req(d)
    flags <- d$enrollment_flags$low_enrollment
    if (is.null(flags) || nrow(flags) == 0) {
      return(p("No selected-term sections are under the low-enrollment thresholds.",
               class = "text-hint"))
    }
    NULL
  })

  output$dashboard_low_enrollment_review_table <- reactable::renderReactable({
    d <- dashboard_data(); req(d)
    flags <- d$enrollment_flags$low_enrollment
    display <- format_dashboard_low_enrollment_review(flags)

    if (nrow(display) == 0) {
      return(reactable::reactable(
        tibble(Message = "No selected-term sections are under the low-enrollment thresholds."),
        columns = list(Message = reactable::colDef(minWidth = 280)),
        pagination = FALSE,
        theme = cedar_tbl_theme
      ))
    }

    header_nowrap <- list(whiteSpace = "nowrap")
    header_wrap <- list(whiteSpace = "normal", lineHeight = "1.1")
    priority_badge <- function(value) {
      cfg <- switch(as.character(value),
        Critical = list(bg = "#F2E3DE", fg = "#A15D4E"),
        Warning  = list(bg = "#F4E9D2", fg = "#7A5010"),
        Watch    = list(bg = "#E3ECF2", fg = "#3A5A7A"),
        Buffer   = list(bg = "#E4EEE7", fg = "#2E7D32"),
        list(bg = "#eeeeee", fg = "#555555")
      )
      htmltools::span(
        style = paste0(
          "display:inline-block;border-radius:8px;padding:1px 7px;",
          "font-size:0.78em;font-weight:700;white-space:nowrap;",
          "background:", cfg$bg, ";color:", cfg$fg, ";"
        ),
        value
      )
    }
    row_style <- function(index) {
      rank <- display$.priority_rank[index]
      if (identical(rank, 1L)) {
        list(background = "#FFF7F5", borderLeft = "3px solid #A15D4E")
      } else if (identical(rank, 2L)) {
        list(background = "#FFF9EC", borderLeft = "3px solid #C7A96B")
      } else if (identical(rank, 3L)) {
        list(background = "#F7FAFD", borderLeft = "3px solid #7FA3C3")
      } else {
        list(background = "#FAFCFA", borderLeft = "3px solid #8AB091")
      }
    }
    enrl_style <- function(value) {
      if (is.na(value)) return(NULL)
      if (value < 6) list(fontWeight = "700", color = "#A15D4E")
      else if (value < 10) list(fontWeight = "700", color = "#7A5010")
      else list(fontWeight = "600")
    }
    # Recent History has no fixed max length, so size it to the longest
    # value actually present rather than a static minWidth that either
    # truncates real content or leaves unused blank space.
    history_chars <- max(nchar(display$recent_history), nchar("Recent History"), na.rm = TRUE)
    history_width <- min(max(history_chars * 7 + 24, 140), 320)

    reactable::reactable(
      display,
      columns = list(
        campus = reactable::colDef(name = "Campus", minWidth = 76, maxWidth = 86, headerStyle = header_nowrap),
        course = reactable::colDef(name = "Course", minWidth = 112, maxWidth = 130, headerStyle = header_nowrap),
        section = reactable::colDef(name = "S#", width = 40, align = "center", headerStyle = header_nowrap),
        title = reactable::colDef(name = "Title", minWidth = 260, headerStyle = header_nowrap),
        sections = reactable::colDef(name = "Sects", width = 58, align = "right", headerStyle = header_nowrap),
        level = reactable::colDef(show = FALSE),
        enrolled = reactable::colDef(name = "Sect Enrl", width = 78, align = "right", style = enrl_style, headerStyle = header_wrap),
        course_total = reactable::colDef(name = "Total Enrl", width = 68, align = "right", headerStyle = header_wrap),
        threshold = reactable::colDef(name = "Target", minWidth = 66, maxWidth = 78, align = "right", headerStyle = header_nowrap),
        priority = reactable::colDef(name = "Priority", minWidth = 84, maxWidth = 96, cell = priority_badge, headerStyle = header_nowrap),
        repeated = reactable::colDef(name = "Rpt", minWidth = 54, maxWidth = 62, align = "center", headerStyle = header_nowrap),
        recent_history = reactable::colDef(name = "Recent History", width = history_width, style = list(whiteSpace = "nowrap"), headerStyle = header_nowrap),
        .priority_rank = reactable::colDef(show = FALSE)
      ),
      defaultSorted = list(.priority_rank = "asc", enrolled = "asc"),
      defaultPageSize = 12,
      striped = TRUE,
      highlight = TRUE,
      rowStyle = row_style,
      searchable = TRUE,
      theme = cedar_tbl_theme
    )
  })

  # New this term — T: topics courses also show slot average across all prior T: offerings
  output$dashboard_new_courses <- renderUI({
    d <- dashboard_data(); req(d)
    .render_course_table(d$new_this_term,
                         empty_msg = "No new courses found for this term.",
                         max_rows = Inf,
                         function(i, x) {
      r        <- x[i, ]
      has_slot <- !is.na(r$slot_avg_enrl)
      slot_txt <- if (has_slot)
        paste0("slot avg: ", r$slot_avg_enrl, " (", r$n_slot_prior, " prior topics)")
        else ""
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap; color: #1565c0;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = "padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: #888;",
                slot_txt)
      )
    })
  })

  # Missing from two years ago — shows last 3 prior appearances with enrollment
  output$dashboard_dormant_courses <- renderUI({
    d <- dashboard_data(); req(d)
    .render_course_table(d$missing_from_earlier,
                         empty_msg = "No courses missing vs. two years ago.",
                         max_rows = Inf,
                         function(i, x) {
      r        <- x[i, ]
      hist_txt <- if (!is.na(r$recent_history)) r$recent_history else paste0("last seen: ", r$prior_enrl)
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: #888;",
                hist_txt)
      )
    })
  })

  # Recurring topics courses running this term
  output$dashboard_repeated_topics <- renderUI({
    d <- dashboard_data(); req(d)
    .render_course_table(d$repeated_topics,
                         empty_msg = "No recurring topics courses this term.",
                         max_rows = Inf,
                         function(i, x) {
      r <- x[i, ]
      hist_txt <- if (!is.null(r$recent_history) && !is.na(r$recent_history))
        r$recent_history else paste0("avg ", r$avg_prior_enrl)
      tags$tr(
        tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                paste0(r$subject_course, .campus_suffix(r, x))),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = "padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: #888;",
                hist_txt)
      )
    })
  })


  ##############################
  ##### DEPARTMENT TRENDS #####
  ##############################

  # Dept Trends is implemented in R/modules/dept-trends.R.

  #########################
  ##### DATA & USAGE TAB #####
  #########################

  .admin_reactable <- function(d, columns = list(), page_size = 15L,
                               searchable = TRUE, pagination = TRUE,
                               default_sorted = NULL) {
    if (is.null(d)) d <- data.frame(Message = "No data available")
    d <- as.data.frame(d, stringsAsFactors = FALSE)
    numeric_cols <- names(d)[vapply(d, is.numeric, logical(1))]
    default_columns <- stats::setNames(
      lapply(names(d), function(col) {
        if (col %in% numeric_cols) {
          reactable::colDef(
            align = "right",
            format = reactable::colFormat(separators = TRUE, digits = 1)
          )
        } else {
          reactable::colDef(minWidth = if (col %in% c("Details", "Summary")) 260 else 110)
        }
      }),
      names(d)
    )
    reactable::reactable(
      d,
      theme               = cedar_tbl_theme,
      striped             = TRUE,
      highlight           = TRUE,
      compact             = TRUE,
      searchable          = searchable,
      pagination          = pagination,
      defaultPageSize     = page_size,
      showPageSizeOptions = pagination,
      pageSizeOptions     = c(10, 15, 25, 50, 100),
      defaultSorted       = default_sorted,
      columns             = utils::modifyList(default_columns, columns)[names(d)]
    )
  }

  .admin_humanize_columns <- function(d) {
    if (is.null(d)) return(d)
    label_lookup <- c(
      issue_type = "Issue Type",
      severity = "Severity",
      review_status = "Review Status",
      program_code = "Program Code",
      major_code = "Major Code",
      college_code = "College Code",
      dept_code = "Dept Code",
      degree_level = "Degree Level",
      program_type = "Program Type",
      canonical_code = "Canonical Code",
      subject_code = "Subject Code",
      dept_name = "Dept Name",
      details = "Details"
    )
    labels <- unname(label_lookup[names(d)])
    missing_labels <- is.na(labels)
    labels[missing_labels] <- tools::toTitleCase(gsub("_", " ", names(d)[missing_labels]))
    names(d) <- labels
    d
  }

  # ── Tab 1: Data Summary (uses pre-computed data from global.R) ────────────
  output$cedar_version_summary <- renderUI({
    version_info <- get_cedar_version_info()
    date_text <- version_info$date
    if (is.na(date_text) || !nzchar(date_text)) {
      date_text <- "date unavailable"
    }
    title_text <- version_info$title
    if (!nzchar(title_text)) {
      title_text <- "Latest changelog entry"
    }

    div(
      class = "alert alert-info alert-compact",
      tags$div(
        icon("code-branch"),
        tags$strong(" CEDAR version: "),
        tags$span(version_info$version),
        tags$span(class = "text-muted-sm", paste0(" · ", date_text))
      ),
      tags$div(class = "text-hint", title_text),
      tags$div(
        class = "text-muted-sm",
        "Source: newest entry in config/changelog.yml."
      )
    )
  })

  # Data Status Table - uses pre-computed cedar_data_summary from global.R
  output$data_status_table <- reactable::renderReactable({
    cedar_debug("[server.R] DATA STATUS TABLE rendering")
    tryCatch({
      display_terms <- cedar_data_summary$display_terms
      term_cols <- vapply(display_terms, .term_label,
                          FUN.VALUE = character(1))

      datasets <- list(
        list(name = "Sections", key = "sections", count = cedar_data_summary$sections_count),
        list(name = "Students", key = "students", count = cedar_data_summary$students_count),
        list(name = "Programs", key = "programs", count = cedar_data_summary$programs_count),
        list(name = "Degrees",  key = "degrees",  count = cedar_data_summary$degrees_count),
        list(name = "Faculty",  key = "faculty",  count = cedar_data_summary$faculty_count)
      )

      rows <- lapply(datasets, function(ds) {
        if (ds$count == 0) return(NULL)
        term_dates <- cedar_data_summary[[paste0(ds$key, "_term_dates")]]
        date_vals <- vapply(as.character(display_terms), function(t) {
          val <- term_dates[[t]]
          if (is.null(val) || (length(val) == 1 && is.na(val))) "-" else as.character(val)
        }, character(1))
        as.data.frame(
          t(c(Dataset = ds$name, Rows = format(ds$count, big.mark = ","), date_vals)),
          stringsAsFactors = FALSE
        )
      })
      rows <- rows[!sapply(rows, is.null)]

      if (length(rows) == 0) {
        .admin_reactable(data.frame(Message = "No data loaded"), pagination = FALSE, searchable = FALSE)
      } else {
        display_data <- do.call(rbind, rows)
        colnames(display_data) <- c("Dataset", "Rows", term_cols)
        curr_col <- .term_label(cedar_current_term)
        .admin_reactable(
          display_data,
          pagination = FALSE,
          searchable = FALSE,
          columns = stats::setNames(
            list(reactable::colDef(style = list(fontWeight = "700"))),
            curr_col
          )
        )
      }
    }, error = function(e) {
      message("[server.R] *** ERROR in data_status_table: ", e$message, " ***")
      .admin_reactable(
        data.frame(Error = paste("Error loading data status:", e$message)),
        pagination = FALSE,
        searchable = FALSE
      )
    })
  })

  # ── Tab 2: Mapping Transparency ───────────────────────────────────────
  .named_lookup_table <- function(x, key_col, value_col) {
    if (is.null(x) || length(x) == 0) {
      return(data.frame(Message = "Lookup not available", stringsAsFactors = FALSE))
    }
    data.frame(
      key = names(x),
      value = as.character(x),
      stringsAsFactors = FALSE
    ) %>%
      rename(!!key_col := key, !!value_col := value) %>%
      filter(!is.na(.data[[key_col]]), nzchar(.data[[key_col]])) %>%
      arrange(.data[[key_col]])
  }

  .mapping_issues <- function() {
    issues <- get0("cedar_mapping_issues", ifnotfound = NULL)
    if (is.null(issues) || nrow(issues) == 0) {
      return(data.frame(
        issue_type = character(),
        severity = character(),
        review_status = character(),
        program_code = character(),
        major_code = character(),
        college_code = character(),
        dept_code = character(),
        degree_level = character(),
        program_type = character(),
        details = character(),
        stringsAsFactors = FALSE
      ))
    }
    as.data.frame(issues, stringsAsFactors = FALSE)
  }

  # ── Join integrity ────────────────────────────────────────────────────────
  # Computed once per session and cached. The check scans every student table,
  # so it is not free, but it only changes when the stored data changes.
  .id_integrity <- reactive({
    students <- data_objects[["cedar_students"]]
    if (is.null(students) || nrow(students) == 0) return(NULL)

    candidates <- c("cedar_programs", "cedar_degrees", "cedar_applicants",
                    "cedar_student_term_credits", "cedar_grades")
    tables <- Filter(
      function(d) !is.null(d) && nrow(d) > 0 &&
        all(c("student_id", "term") %in% names(d)),
      stats::setNames(lapply(candidates, function(k) data_objects[[k]]), candidates)
    )
    if (length(tables) == 0) return(NULL)

    check_student_id_integrity(students, tables,
                               opt = list(spine_name = "cedar_students"))
  })

  output$id_integrity_summary <- renderUI({
    res <- .id_integrity()
    if (is.null(res)) {
      return(div(class = "alert alert-info",
                 "Join integrity cannot be checked: cedar_students is not loaded."))
    }

    spine_note <- paste0(
      "Compared against ", format(res$spine$n_ids, big.mark = ","), " ",
      res$spine$name, " IDs across ", res$spine$n_terms, " terms."
    )

    if (res$n_tables_split == 0) {
      return(div(class = "alert alert-success",
        tags$strong("All loaded tables share one student ID space."),
        " ", spine_note))
    }

    split_tables <- res$by_table$table[res$by_table$verdict == "split"]
    bad_terms <- res$by_term %>% filter(term_status == "none")

    div(class = "alert alert-danger",
      tags$strong(paste0(res$n_tables_split,
                         if (res$n_tables_split == 1) " table holds" else " tables hold",
                         " two student ID spaces: ")),
      paste(split_tables, collapse = ", "), ". ",
      paste0(nrow(bad_terms), " table-terms cannot join to ", res$spine$name,
             " at all. "),
      spine_note,
      tags$div(class = "mt-1",
        "Affected records are invisible to any cross-table analysis. This cannot be ",
        "fixed downstream — the source reports must be repulled for those terms. ",
        "See ISSUES.md I1.")
    )
  })

  output$id_integrity_table <- reactable::renderReactable({
    res <- .id_integrity()
    if (is.null(res)) {
      return(.admin_reactable(
        data.frame(Message = "cedar_students not loaded", stringsAsFactors = FALSE),
        pagination = FALSE, searchable = FALSE))
    }
    .admin_reactable(
      res$by_table %>% .admin_humanize_columns(),
      page_size = 15L, pagination = FALSE, searchable = FALSE
    )
  })

  output$id_integrity_term_table <- reactable::renderReactable({
    res <- .id_integrity()
    if (is.null(res)) {
      return(.admin_reactable(
        data.frame(Message = "cedar_students not loaded", stringsAsFactors = FALSE),
        pagination = FALSE, searchable = FALSE))
    }
    .admin_reactable(
      res$by_term %>%
        # Failures first: this table is read to find out what to repull, not to
        # admire the terms that work.
        arrange(match(term_status, c("none", "partial", "full")), table, term) %>%
        .admin_humanize_columns(),
      page_size = 25L
    )
  })

  output$mapping_issues_summary <- renderUI({
    issues <- .mapping_issues()
    needs_review <- sum(issues$review_status == "needs_review", na.rm = TRUE)
    reviewed <- sum(issues$review_status == "reviewed_exception", na.rm = TRUE)

    if (nrow(issues) == 0) {
      return(div(
        class = "alert alert-success",
        tags$strong("No mapping issues found at startup."),
        " Program and department lookup vectors loaded without exclusions."
      ))
    }

    alert_class <- if (needs_review > 0) "alert alert-warning" else "alert alert-info"
    div(
      class = alert_class,
      tags$strong("Mapping issues found at startup: "),
      paste0(nrow(issues), " total; ", needs_review, " need review; ", reviewed, " reviewed exceptions."),
      " Affected rows are excluded from runtime lookup vectors so they do not leak into calculations."
    )
  })

  output$mapping_issues_table <- reactable::renderReactable({
    issues <- .mapping_issues()
    if (nrow(issues) == 0) {
      return(.admin_reactable(
        data.frame(Message = "No mapping issues found at startup", stringsAsFactors = FALSE),
        pagination = FALSE,
        searchable = FALSE
      ))
    }
    .admin_reactable(
      issues %>%
        select(issue_type, severity, review_status, program_code, major_code,
               college_code, dept_code, degree_level, program_type, details) %>%
        .admin_humanize_columns(),
      page_size = 25L
    )
  })

  output$program_dept_mapping_table <- reactable::renderReactable({
    .admin_reactable(
      .named_lookup_table(get0("major_to_dept", ifnotfound = NULL),
                          "major_code", "dept_code") %>%
        .admin_humanize_columns(),
      page_size = 25L
    )
  })

  output$subject_dept_mapping_table <- reactable::renderReactable({
    .admin_reactable(
      .named_lookup_table(get0("subj_to_dept", ifnotfound = NULL),
                          "subject_code", "dept_code") %>%
        .admin_humanize_columns(),
      page_size = 25L
    )
  })

  output$dept_name_mapping_table <- reactable::renderReactable({
    .admin_reactable(
      .named_lookup_table(get0("dept_code_to_name", ifnotfound = NULL),
                          "dept_code", "dept_name") %>%
        .admin_humanize_columns(),
      page_size = 25L
    )
  })

  output$allowed_unmapped_mapping_table <- reactable::renderReactable({
    codes <- get0("allowed_unmapped_program_codes", ifnotfound = character())
    if (length(codes) == 0) {
      return(.admin_reactable(
        data.frame(Message = "No reviewed unmapped program-code exceptions configured", stringsAsFactors = FALSE),
        pagination = FALSE,
        searchable = FALSE
      ))
    }

    out <- data.frame(program_code = codes, stringsAsFactors = FALSE)
    pm <- get0("program_map", ifnotfound = NULL)
    if (!is.null(pm) && "program_code" %in% names(pm)) {
      keep_cols <- intersect(
        c("program_code", "major_code", "college_code", "dept_code", "degree_level", "program_type", "canonical_code"),
        names(pm)
      )
      out <- merge(out, as.data.frame(pm[, keep_cols, drop = FALSE]), by = "program_code", all.x = TRUE, sort = FALSE)
    }

    .admin_reactable(
      out %>% .admin_humanize_columns(),
      page_size = 25L
    )
  })

  # ── Tab 2: Usage Overview (lazy loaded) ────────────────────────────────
  usage_overview_data <- reactiveVal(NULL)

  # Helper to (re)load overview data
  .load_usage_overview <- function() {
    tryCatch({
      start_date <- if(!is.null(input$usage_start_date)) as.character(input$usage_start_date) else as.character(Sys.Date())
      end_date   <- if(!is.null(input$usage_end_date))   as.character(input$usage_end_date)   else as.character(Sys.Date())
      cedar_debug("[server.R] Loading usage overview for date range: ", start_date, " to ", end_date)
      usage_overview_data(get_usage_overview(start_date, end_date))
    }, error = function(e) {
      message("[server.R] Error loading usage overview: ", e$message)
      usage_overview_data(list(message = paste("Error loading usage data:", e$message)))
    })
  }

  .usage_label <- function(x) {
    x <- gsub("[-_]+", " ", as.character(x))
    tools::toTitleCase(x)
  }

  # Auto-load when this tab becomes active
  observeEvent(input$data_usage_tabs, {
    if (isTRUE(input$data_usage_tabs == "Usage Overview")) .load_usage_overview()
  })

  # Also reload on explicit Refresh click
  observeEvent(input$refresh_usage_overview, {
    .load_usage_overview()
    showNotification("Usage overview refreshed", type = "message")
  })

  # Render usage overview UI
  output$usage_overview_ui <- renderUI({
    overview <- usage_overview_data()

    if (is.null(overview)) {
      return(div(
        class = "text-center p-3",
        p("Click 'Refresh' to load usage overview")
      ))
    }

    if ("message" %in% names(overview)) {
      return(div(
        style = "padding: 20px;",
        p(overview$message)
      ))
    }

    fmt_count <- function(x) {
      if (is.null(x) || length(x) == 0 || is.na(x)) return("0")
      format(as.integer(x), big.mark = ",")
    }
    top_label <- function(df, label_col, pretty = identity) {
      if (is.null(df) || nrow(df) == 0) return("None yet")
      paste0(pretty(df[[label_col]][[1]]), " (", fmt_count(df$count[[1]]), ")")
    }
    metric_card <- function(value, label, note = NULL) {
      div(
        class = "stat-card stat-card--left",
        tags$h4(value),
        tags$p(label, class = "text-muted m-0"),
        if (!is.null(note)) tags$p(note, class = "text-note")
      )
    }

    range_label <- "Selected date range"
    if (!is.null(overview$date_range)) {
      start_day <- as.Date(overview$date_range$start)
      end_day <- as.Date(overview$date_range$end)
      if (!is.na(start_day) && !is.na(end_day)) {
        range_label <- if (identical(start_day, end_day)) {
          format(start_day, "%b %d, %Y")
        } else {
          paste(format(start_day, "%b %d, %Y"), "to", format(end_day, "%b %d, %Y"))
        }
      }
    }

    busiest_note <- NULL
    if (!is.null(overview$busiest_day) && nrow(overview$busiest_day) > 0) {
      busiest_note <- paste0(
        "Busiest day: ", format(overview$busiest_day$date[[1]], "%b %d"),
        " (", fmt_count(overview$busiest_day$events[[1]]), " events)"
      )
    }

    tagList(
      div(class = "scope-bar scope-bar--stacked",
        strong(range_label),
        tags$span(overview$user_identity_note %||%
                    "CEDAR logs browser sessions, not authenticated user identities.")
      ),
      fluidRow(
        column(3, metric_card(fmt_count(overview$unique_sessions), "Active sessions",
                              "Sessions with tab, report, or download activity; not unique users.")),
        column(3, metric_card(fmt_count(overview$total_reports), "Reports run",
                              top_label(overview$report_type_usage, "report_type", .usage_label))),
        column(3, metric_card(fmt_count(overview$total_tab_views), "Tab views",
                              top_label(overview$tab_usage, "tab"))),
        column(3, metric_card(fmt_count(overview$errors_count), "Errors logged",
                              if (overview$errors_count > 0) "Check Feature Details." else "No logged errors."))
      ),
      fluidRow(
        column(3, metric_card(fmt_count(overview$total_events), "Total events", busiest_note)),
        column(3, metric_card(fmt_count(overview$total_downloads), "Downloads")),
        column(3, metric_card(top_label(overview$dept_reports, "department"), "Top department")),
        column(3, metric_card(top_label(overview$course_reports, "course"), "Top course"))
      )
    )
  })

  # Tab usage table
  output$tab_usage_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$tab_usage) || nrow(overview$tab_usage) == 0) {
      return(.admin_reactable(data.frame(Message = "No tab usage data available"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$tab_usage
    names(display) <- c("Tab/Feature", "Usage Count")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # Report type table
  output$report_type_usage_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$report_type_usage) || nrow(overview$report_type_usage) == 0) {
      return(.admin_reactable(data.frame(Message = "No report runs logged for this date range"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$report_type_usage
    display$report_type <- .usage_label(display$report_type)
    names(display) <- c("Report Type", "Runs")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # Department reports table
  output$dept_reports_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$dept_reports) || nrow(overview$dept_reports) == 0) {
      return(.admin_reactable(data.frame(Message = "No department reports data available"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$dept_reports
    names(display) <- c("Department", "Report Count")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # Course reports table
  output$course_reports_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$course_reports) || nrow(overview$course_reports) == 0) {
      return(.admin_reactable(data.frame(Message = "No course reports data available"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$course_reports
    names(display) <- c("Course", "Report Count")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # Campus scope table
  output$campus_usage_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$campus_usage) || nrow(overview$campus_usage) == 0) {
      return(.admin_reactable(data.frame(Message = "No campus-scoped report data available"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$campus_usage
    names(display) <- c("Campus", "Report Count")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # Daily activity table
  output$usage_daily_table <- reactable::renderReactable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$daily_activity) || nrow(overview$daily_activity) == 0) {
      return(.admin_reactable(data.frame(Message = "No daily usage data available"), pagination = FALSE, searchable = FALSE))
    }

    display <- overview$daily_activity %>%
      dplyr::mutate(date = format(date, "%Y-%m-%d")) %>%
      dplyr::arrange(dplyr::desc(date))
    names(display) <- c("Date", "Sessions", "Events", "Reports", "Errors")
    .admin_reactable(display, page_size = 10L, searchable = FALSE)
  })

  # ── Tab 3: Feature Details ──────────────────────────────────────────────

  # Human-readable labels for event types
  .event_labels <- c(
    session_start    = "Session started",
    session_end      = "Session ended",
    report_generated = "Report generated",
    tab_change       = "Tab viewed",
    data_filter      = "Filter applied",
    query_executed   = "Query run",
    error            = "Error"
  )

  # Parse a JSON details string into a short human-readable summary
  .format_details <- function(details_str, event_type) {
    tryCatch({
      d <- jsonlite::fromJSON(details_str)
      p <- d$parameters %||% d
      if (event_type == "report_generated") {
        rt <- d[["report_type"]] %||% "report"
        if (!is.null(p[["department"]]))  return(paste0(rt, ": ", p[["department"]]))
        if (!is.null(p[["dept_code"]]))   return(paste0(rt, ": ", p[["dept_code"]]))
        if (!is.null(p[["course"]]))      return(paste0(rt, ": ", p[["course"]]))
        if (!is.null(p[["subject_course"]])) return(paste0(rt, ": ", p[["subject_course"]]))
        if (!is.null(p[["dept"]]))        return(paste0(rt, ": ", p[["dept"]]))
        if (!is.null(p[["college"]]))     return(paste0(rt, ": ", p[["college"]]))
        return(rt)
      }
      if (event_type == "tab_change")   return(d[["tab"]]   %||% details_str)
      if (event_type == "data_filter")  return(d[["filter_type"]] %||% details_str)
      if (event_type == "session_start") {
        return(paste0(d[["url"]] %||% "", if (!is.null(d[["port"]]) && nchar(d[["port"]]) > 0) paste0(":", d[["port"]]) else ""))
      }
      details_str
    }, error = function(e) details_str)
  }

  # Stats summary card — auto-renders reactively from log inputs
  output$usage_stats_output <- renderUI({
    start_date <- if (!is.null(input$feature_start_date)) as.character(input$feature_start_date) else as.character(Sys.Date())
    end_date   <- if (!is.null(input$feature_end_date))   as.character(input$feature_end_date)   else as.character(Sys.Date())
    tryCatch({
      stats <- get_usage_stats(start_date, end_date)
      if ("message" %in% names(stats)) return(p(stats$message, style = "color:#888;"))
      date_label <- if (start_date == end_date) start_date else paste(start_date, "–", end_date)
      tagList(
        fluidRow(
          column(3, div(class = "well well-sm text-center",
            h4(stats$total_sessions),  p("Sessions", class = "text-muted m-0"))),
          column(3, div(class = "well well-sm text-center",
            h4(stats$total_session_starts), p("Session starts", class = "text-muted m-0"))),
          column(3, div(class = "well well-sm text-center",
            h4(if (!is.null(stats$reports_generated)) stats$reports_generated else 0),
            p("Reports generated", class = "text-muted m-0"))),
          column(3, div(class = "well well-sm text-center",
            h4(stats$error_count),  p("Errors", class = "text-muted m-0")))
        )
      )
    }, error = function(e) p(paste("Error loading stats:", e$message), style = "color:red;"))
  })

  # Event log table — shows all events, rendered reactively (no refresh needed)
  output$feature_usage_table <- reactable::renderReactable({
    cedar_debug("[server.R] FEATURE USAGE TABLE rendering")
    tryCatch({
      start_date <- if (!is.null(input$feature_start_date)) as.character(input$feature_start_date) else as.character(Sys.Date())
      end_date   <- if (!is.null(input$feature_end_date))   as.character(input$feature_end_date)   else as.character(Sys.Date())

      logs <- read_logs(start_date, end_date)
      cedar_debug("[server.R] Read ", nrow(logs), " log entries for feature usage table")

      if (nrow(logs) == 0) {
        return(.admin_reactable(data.frame(Message = "No log data found for this date range"), pagination = FALSE, searchable = FALSE))
      }

      display <- logs %>%
        arrange(desc(timestamp)) %>%
        mutate(
          Time = format(
            lubridate::with_tz(as.POSIXct(timestamp, tz = "UTC"), "America/Denver"),
            "%b %d %I:%M %p"
          ),
          Event = .event_labels[event_type] %||% event_type,
          Summary = mapply(.format_details, details, event_type)
        ) %>%
        select(Time, Event, Summary)

      .admin_reactable(display, page_size = 20L)
    }, error = function(e) {
      message("[server.R] *** ERROR in feature_usage_table: ", e$message, " ***")
      .admin_reactable(
        data.frame(Error = paste("Error loading data:", e$message)),
        pagination = FALSE,
        searchable = FALSE
      )
    })
  })


  # ===========================================================================
  # Changelog tab (Shiny module)
  # ===========================================================================
  changelogServer("changelog")

  # ===========================================================================
  # Cache Management (Shiny module)
  # ===========================================================================
  cacheServer("cache")

  # =============================================================================
  # Pathways tab — population-aware curriculum analytics (Shiny module)
  # =============================================================================
  pathwaysServer("pathways", cedar_students, cedar_programs, degrees = cedar_degrees,
                 cedar_grades = cedar_grades,
                 cedar_student_term_credits = cedar_student_term_credits,
                 cedar_next_term = cedar_next_term,
                 lookups = data_objects[["cedar_lookups"]],
                 program_choices = cedar_pathways_choices$program_choices,
                 dept_choices = cedar_pathways_choices$dept_choices)

  # =============================================================================
  # Retention tab — institution-level retention by course (Shiny module)
  # =============================================================================
  # Parked with its UI: retentionUI() is commented out in ui.R pending the
  # cross-course comparison work. The server was still running on every session,
  # registering outputs nothing rendered. Re-enable both together.
  # retentionServer("retention", students = cedar_students)

} # end server
