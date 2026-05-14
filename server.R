server <- function(input, output, session) {

  # ============================================================================
  # Server Logic for Cedar Analytics Application
  # ============================================================================
  #
  # DEPENDENCIES (loaded via global.R):
  #   - data_objects[["cedar_sections"]]  - Course sections (DESRs)
  #   - data_objects[["cedar_students"]]  - Student enrollments (class lists)
  #   - data_objects[["cedar_programs"]]  - Student programs (academic studies)
  #   - data_objects[["cedar_degrees"]]   - Degree completions
  #   - data_objects[["cedar_faculty"]]   - Faculty information
  #   - data_objects[["forecasts"]]       - Enrollment forecasts
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
  forecasts       <- data_objects[["forecasts"]]
  # Optional pre-computed tables — NULL/empty if files don't exist yet (before transform runs)
  cedar_grades    <- data_objects[["cedar_grades"]]
  cedar_next_term <- data_objects[["cedar_next_term"]]

  # Initialize session logging within reactive context
  observe({
    # Access reactive values for session start logging
    user_agent <- session$clientData$user_agent
    url_hostname <- session$clientData$url_hostname
    url_protocol <- session$clientData$url_protocol
    url_port <- session$clientData$url_port
    url_pathname <- session$clientData$url_pathname
    
    # Log session start with reactive data
    session_id <- session$token
    details <- list(
      url = url_hostname,
      protocol = url_protocol, 
      port = url_port,
      pathname = url_pathname
    )
    
    write_log("INFO", "session_start", details, session_id, user_agent)
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

  # Parse URL query parameters and update inputs dynamically
  # Use observeEvent with once=TRUE to only trigger on initial page load
  observeEvent(session$clientData$url_search, {
    query <- parseQueryString(session$clientData$url_search)
    
    # Only process if there are actual query parameters
    if (length(query) == 0) return()
    
    # Map URL-friendly tab names to actual tab titles
    tab_aliases <- list(
      "open-seats" = "Open Seats",
      "waitlists" = "Waitlists",
      "enrollment" = "Enrollment",
      "low-enrollment" = "Enrollment",  # sub-tab of Enrollment; handled below
      "headcount" = "Headcount",
      "course-dynamics" = "Course Dynamics",
      "department-profile" = "Department Profile"
    )
    
    # Switch to specific tab if requested
    tab_param <- tolower(query$tab)  # Make case-insensitive
    tab_name <- if (!is.null(tab_param) && !is.null(tab_aliases[[tab_param]])) {
      tab_aliases[[tab_param]]
    } else {
      query$tab  # Use as-is if not in aliases
    }
    
    # Tab switching is handled client-side in ui.R (DOMContentLoaded JS) so the
    # correct tab appears immediately without waiting for the Shiny session.
    # Only handle the low-enrollment sub-tab here since it can't be reached by
    # clicking a top-level nav link.
    if (!is.null(tab_param) && tab_param == "low-enrollment") {
      nav_select("enrl_output_tabs", selected = "low_enrl", session = session)
    }
    
    # Map tab names to their input prefixes
    tab_prefixes <- list(
      "Open Seats" = "sf",
      "Waitlists" = "wl",
      "Enrollment" = "enrl",
      "Headcount" = "hc",
      "Course Dynamics" = "cr",
      "Department Profile" = "dr"
      # Add more tabs as needed
    )
    
    # Get the prefix for the current tab
    prefix <- if (!is.null(tab_name) && !is.null(tab_prefixes[[tab_name]])) {
      tab_prefixes[[tab_name]]
    } else {
      NULL
    }
    
    # Update inputs based on tab prefix
    for (param_name in names(query)) {
      # Skip special control params
      if (param_name %in% c("tab", "autorun")) next
      
      # Construct the actual input ID
      input_id <- if (!is.null(prefix)) {
        paste0(prefix, "_", param_name)  # e.g., "sf_term"
      } else {
        param_name  # Use as-is if no prefix
      }
      
      # Split comma-joined multi-values (e.g. "HIST,MATH") back into a vector
      param_value <- unlist(strsplit(query[[param_name]], ","))

      # Try to update the input
      tryCatch({
        updateSelectizeInput(session, input_id, selected = param_value)
      }, error = function(e) {
        # Input doesn't exist, that's OK
      })
    }
    
    # Auto-run functionality if requested
    if (!is.null(query$autorun) && query$autorun == "true") {
      button_id <- if (!is.null(tab_param) && tab_param == "low-enrollment") {
        "low_enrl_button"
      } else if (!is.null(prefix)) {
        paste0(prefix, "_button")
      } else {
        NULL
      }
      if (!is.null(button_id)) {
        # Delay the click so updateSelectizeInput round-trips complete before the
        # observer reads input$* values. Without the delay, the button handler
        # fires with stale inputs even though the UI shows the correct values.
        later::later(function() session$sendCustomMessage("click_button", button_id),
                     delay = 0.5)
      }
    }
  }, once = TRUE) # end URL parameter parsing - only run once on page load


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


  # Helper function to create formatted regstats datatables with concern tier styling
  create_regstats_datatable <- function(table_data) {
    if(is.null(table_data)) return(NULL)

    # Rename sd_deviation so it visually matches the "Min SDs" input label
    if ("sd_deviation" %in% names(table_data)) {
      table_data <- table_data %>% dplyr::rename(`SDs from mean` = sd_deviation)
    }

    # Format concern tier labels if column exists
    if("concern_tier" %in% names(table_data)) {
      table_data <- table_data %>%
        mutate(concern_tier = case_when(
          concern_tier == "critical_high" ~ "🔴 Critical High",
          concern_tier == "critical_low" ~ "🔴 Critical Low",
          concern_tier == "moderate_high" ~ "🟡 Moderate High",
          concern_tier == "moderate_low" ~ "🟡 Moderate Low",
          concern_tier == "marginally_high" ~ "🟠 Marginally High",
          concern_tier == "marginally_low" ~ "🟠 Marginally Low",
          concern_tier == "normal" ~ "🟢 Normal",
          TRUE ~ concern_tier
        )) %>%
        relocate(concern_tier, .after = subject_course)
    }

    # Create the datatable
    dt <- DT::datatable(table_data, options = list(pageLength = 10, scrollX = TRUE))
    
    # Apply color formatting if concern_tier column exists
    if("concern_tier" %in% names(table_data)) {
      dt <- dt %>% DT::formatStyle(
        "concern_tier",
        backgroundColor = DT::styleEqual(
          c("🔴 Critical High", "🔴 Critical Low", "🟡 Moderate High", "🟡 Moderate Low", 
            "🟠 Marginally High", "🟠 Marginally Low", "🟢 Normal"),
          c("#f8d7da", "#f8d7da", "#fff3cd", "#fff3cd", "#ffe4b5", "#ffe4b5", "#d4edda")
        )
      )
    }
    
    return(dt)
  } # end create_regstats_datatable function


  # Show changelog modal when user visits with a new version
  # Compares last seen version (from localStorage) with current latest version
  observeEvent(input$cedar_last_seen_version, {
    req(input$cedar_last_seen_version)
    
    last_seen <- input$cedar_last_seen_version
    cedar_debug("[server.R] User's last seen version: ", last_seen)

    # Get current latest version from changelog
    changelog <- load_changelog()
    if (length(changelog) == 0) {
      cedar_debug("[server.R] No changelog entries found, skipping modal")
      return()
    }

    current_version <- changelog[[1]]$version
    cedar_debug("[server.R] Current CEDAR version: ", current_version)

    # Show modal if user hasn't seen this version yet
    if (last_seen != current_version) {
      cedar_debug("[server.R] New version detected, showing changelog modal")
      
      # Load recent changelog entries from YAML
      changelog_html <- format_changelog_html(max_entries = 2)
      
      showModal(modalDialog(
        title = "Latest CEDAR updates!",
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
        easyClose = TRUE,
        footer = modalButton("Got it!")
      ))
      
      # Send message to client to update localStorage with current version
      session$sendCustomMessage('cedar_mark_changelog_version', list(version = current_version))
      
      cedar_debug("[server.R] Modal shown and sent version ", current_version, " to client")
    } else {
      cedar_debug("[server.R] User has already seen version ", current_version, ", skipping modal")
    }
  }) # end observeEvent for welcome modal


  # Dept profile campus filter — populate from actual campus values in data,
  # defaulting to ABQ and EA (the main campus codes for most analyses).
  dept_campus_choices <- sort(unique(cedar_students$campus[!is.na(cedar_students$campus)]))
  default_campuses    <- intersect(c("ABQ", "EA"), dept_campus_choices)
  updateSelectizeInput(session, "dept_report_campus",
                       choices  = dept_campus_choices,
                       selected = default_campuses,
                       server   = TRUE)

  # configure selectize inputs
  updateSelectizeInput(session, 'enrl_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'enrl_inst', choices = sort(unique(cedar_sections$instructor_name)), server = TRUE)
  updateSelectizeInput(session, 'cr_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'rs_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)



  # ===========================================================================
  # Headcount tab (Shiny module)
  # ===========================================================================
  headcountServer("headcount", cedar_programs, data_objects[["cedar_lookups"]])

#    ENROLLMENT    #
#####################
enrl_data <- eventReactive(input$enrl_button, {
  # Log enrollment button click
  log_report_generation(session, "enrollment", list(
    dept = input$enrl_dept,
    campus = input$enrl_campus,
    college = input$enrl_college,
    term = input$enrl_term,
    level = input$enrl_level,
    agg_by = input$enrl_agg_by
  ))

  # Show loading notification with average time
  status_message <- create_timing_status_message("enrollment", "Gathering enrollments")
  showNotification(status_message, type = "warning", duration = NULL, id = "enrl_loading")
  timer <- start_report_timer("enrollment", list(
    dept = input$enrl_dept,
    term = input$enrl_term
  ))
  
  opt <- list()
  opt[["status"]] <- "A"
  opt[["uel"]] <- input$enrl_uel
  opt[["group_cols"]] <- input$enrl_agg_by
  opt[["course_campus"]] <- input$enrl_campus
  opt[["course_college"]] <- input$enrl_college
  opt[["dept"]] <- input$enrl_dept
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
    opt[["group_cols"]] <- c(opt[["group_cols"]], facet)
  }

# Add enrollment min/max from numeric inputs
  opt[["enrl_min"]] <- input$enrl_min
  opt[["enrl_max"]] <- input$enrl_max

# Get enrollment data based on the options
  cedar_debug("[server.R] getting enrollment data with options: ", toString(opt))

  # Run get_enrl() once without enrl_min/enrl_max, then apply those filters
  # here. This avoids running the full pipeline twice just to count pre-filter rows.
  opt_for_enrl <- opt
  opt_for_enrl[["enrl_min"]] <- NULL
  opt_for_enrl[["enrl_max"]] <- NULL

  timer_enrl <- start_report_timer("get_enrl", list(dept = opt[["dept"]], term = opt[["term"]]))
  data <- get_enrl(cedar_sections, opt_for_enrl)
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
    cedar_debug("[server.R] Filtered to ", length(filtered_crns), " CRNs")
    filtered_students <- cedar_students[cedar_students$crn %in% filtered_crns, ]
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


  # if not grouping, select and rename columns for clarity
  # keep only distinct rows of display columns; this discards dupes from crosslist info
  if (is.null(input$enrl_agg_by) || length(input$enrl_agg_by) == 0) {
    # Derive unified Partners display column before selecting:
    #   - split-level courses use split_sections ("BIOL 402 / BIOL 502")
    #   - external crosslisted sections use crosslist_partners (all subjects in group)
    if ("crosslist_partners" %in% colnames(data) || "split_sections" %in% colnames(data)) {
      data <- data %>% mutate(
        Partners = coalesce(
          if ("split_sections" %in% colnames(data)) split_sections else NA_character_,
          if ("crosslist_partners" %in% colnames(data)) crosslist_partners else NA_character_
        )
      )
    }

    base_select <- c(
      Camp = "campus",
      Col = "college",
      Term = "term",
      TermType = "term_type",
      Course = "subject_course",
      Sec = "section",
      Title = "course_title",
      SectionEnrl = "enrolled",
      TotalEnrl = "total_enrl",
      Inst = "instructor_name",
      IM = "delivery_method",
      GenEd = "gen_ed_area"
    )

    # Add part_term (CEDAR standard column name)
    if ("part_term" %in% colnames(data)) {
      base_select <- c(base_select, PoT = "part_term")
    }
    # Partners column (displayed; only present when not NA)
    if ("Partners" %in% colnames(data)) {
      base_select <- c(base_select, Partners = "Partners")
    }
    # Crosslist role and split flag: used for tab filtering in output$enrl_summary, then hidden
    if ("crosslist_role" %in% colnames(data)) {
      base_select <- c(base_select, XlistRole = "crosslist_role")
    }
    if ("crosslist_external" %in% colnames(data)) {
      base_select <- c(base_select, XlistExternal = "crosslist_external")
    }
    if ("is_split" %in% colnames(data)) {
      base_select <- c(base_select, IsSplit = "is_split")
    }

    data <- data %>% ungroup() %>% select(all_of(base_select)) %>% distinct() %>% arrange(Course, TermType)
  }

  duration_sec <- end_report_timer(timer)
  removeNotification("enrl_loading")
  showNotification(paste("Enrollment data ready (", round(duration_sec, 1), "s)"),
                   type = "message", duration = 5)

  list(data = data, cl_data = cl_data, opt = opt, filter_warning = filter_warning)
}, ignoreNULL = TRUE, ignoreInit = TRUE)

# Helper: derive dept display info from enrl_data() opt — used by both the
# summary box and the modal so the logic doesn't have to be duplicated.
.enrl_dept_info <- function(out) {
  dept_filter <- out$opt$dept
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
  if (is.null(out) || is.null(out$opt)) return(NULL)
  info <- .enrl_dept_info(out)
  if (is.null(info)) return(NULL)

  subj_str <- if (length(info$subjects) > 0) paste(info$subjects, collapse = ", ") else "none found"
  n_c <- info$n_courses; n_s <- info$n_sections

  div(class = "alert alert-info",
      style = "font-size: 0.85em; margin: 6px 0 0 0; display: flex; align-items: center; gap: 8px;",
    icon("circle-info"),
    tags$span(
      tags$strong(info$dept_display), " maps to dept code ",
      tags$strong(info$dept_code_label), " (from ",
      tags$code("subj_dept_map.R"), "); subject code",
      if (length(info$subjects) != 1) "s" else "", ": ",
      tags$strong(subj_str), ". ",
      paste0(n_c, " course", if (n_c != 1) "s" else "",
             ", ", n_s, " section", if (n_s != 1) "s" else "",
             " with current filters.")
    ),
    actionButton("enrl_dept_info_btn", label = NULL, icon = icon("circle-question"),
                 class = "btn-link btn-sm",
                 style = "padding: 0; margin-left: auto; flex-shrink: 0;",
                 title = "How does this mapping work?")
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

  showModal(modalDialog(
    title = paste0("Department filter: how \"", info$dept_display, "\" maps to data"),
    easyClose = TRUE,
    footer = modalButton("Close"),
    size = "m",
    tagList(
      h5("Name \u2192 code", style = "margin-top: 0;"),
      p("The department dropdown displays human-readable names but passes the short dept code
        to the filter. ", tags$code("R/lists/subj_dept_map.R"), " is the authoritative source:
        it defines the full hierarchy of college \u2192 department \u2192 subject codes, and
        provides the human-readable name for each dept code. When a dept code has no entry in
        that file, CEDAR falls back to deriving a name from ", tags$code("cedar_programs"), "."),
      p(tags$strong(paste0('"', info$dept_display, '" \u2192 "', info$dept_code_label, '"')),
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
        " directly at query time. No further translation happens. The summarized result
        (table and plot) only retains columns included in Group by, which is why this box
        reads from ", tags$code("cedar_sections"), " directly rather than from the result.")
    )
  ))
})

enrl_plots <- reactive({
  # Only proceed if button has been pressed and data exists
  req(input$enrl_button)
  
  enrl_data_out <- enrl_data()
  req(enrl_data_out)
  req(enrl_data_out$data)
  req(nrow(enrl_data_out$data) > 0)
  
  # Additional check for proper grouping before plotting
  if (is.null(input$enrl_agg_by) || !("term" %in% input$enrl_agg_by) || length(input$enrl_agg_by) < 2) {
    return(NULL)
  }
  
  make_enrl_plot(enrl_data_out$data, enrl_data_out$opt)
})

# Conditional enrollment plot card - only show when TERM is selected for trends
output$enrl_plot_card <- renderUI({
  group_by <- input$enrl_agg_by

  # Plot requires TERM for time series visualization
  if (is.null(group_by) || !("term" %in% group_by) || length(group_by) < 2) {
    return(div(
      class = "alert alert-info",
      style = "margin: 30px; padding: 20px;",
      icon("chart-line", style = "font-size: 1.5em; margin-right: 10px;"),
      tags$strong("To display an enrollment plot:"),
      " select ", tags$code("term"), " and at least one other variable in the ",
      tags$strong("Group by"), " field, then click ", tags$strong("Gather Enrollments"), "."
    ))
  }

  # Render the enrollment plot card with data
  card(
    card_header("Enrollment Plot"),
    style = "height:100vh; min-height:100vh; overflow-y:auto;",
    plotlyOutput("enrl_plot", height = "100vh")
  )

})

# Conditional download button - enabled only when data exists
output$enrl_download_button_ui <- renderUI({
  ed <- NULL
  try(ed <- enrl_data(), silent = TRUE)
  has_data <- !is.null(ed) && !is.null(ed$data) && nrow(ed$data) > 0

  if (has_data) {
    downloadLink("enrl_summary_download", "Download CSV",
                 style = "font-size: 0.85em; color: #888;")
  }
})



# Build and copy a shareable URL for the current enrollment view to the clipboard.
# Encodes the active sub-tab plus the shared filter inputs as comma-joined query params.
observeEvent(input$enrl_copy_url, {
  tab_param <- if (identical(input$enrl_output_tabs, "low_enrl")) "low-enrollment" else "enrollment"

  params <- list(tab = tab_param, autorun = "true")

  add_param <- function(key, val) {
    if (!is.null(val) && length(val) > 0 && any(nzchar(as.character(val)))) {
      params[[key]] <<- paste(val, collapse = ",")
    }
  }
  add_param("campus", input$enrl_campus)
  add_param("college", input$enrl_college)
  add_param("dept",    input$enrl_dept)
  add_param("term",    input$enrl_term)
  add_param("level",   input$enrl_level)

  query_str <- paste(
    mapply(function(k, v) paste0(k, "=", v), names(params), params, USE.NAMES = FALSE),
    collapse = "&"
  )

  session$sendCustomMessage("copy_enrl_url", query_str)
}, ignoreInit = TRUE)


output$enrl_plot <- renderPlotly({
  # Early exit if no proper grouping selected
  group_by <- input$enrl_agg_by
  if (is.null(group_by) || !("term" %in% group_by) || length(group_by) < 2) return(NULL)
  
  # Check if enrollment data exists before trying to plot
  tryCatch({
    plot_data <- enrl_plots()
    if (!is.null(plot_data) && "enrl" %in% names(plot_data)) {
      return(plot_data$enrl)
    }
    return(NULL)
  }, error = function(e) {
    return(NULL)
  })
})


  # Enrollment trends — computed alongside main query, but only for single dept.
  # Uses get_dept_course_enrl_history + get_enrollment_momentum from dept-dashboard.R.
  enrl_trends_data <- eventReactive(input$enrl_button, {
    dept <- input$enrl_dept
    if (is.null(dept) || length(dept) != 1) return(NULL)

    campus <- if (!is.null(input$enrl_campus) && length(input$enrl_campus) > 0)
      input$enrl_campus else NULL

    term <- if (!is.null(input$enrl_term) && length(input$enrl_term) > 0) input$enrl_term else NULL

    tryCatch({
      opt <- list(dept = dept, status = "A", crosslist = "home", uel = TRUE,
                  group_cols = c("subject_course", "course_title", "term"))
      if (!is.null(term))   opt$term          <- term
      if (!is.null(campus)) opt$course_campus  <- campus
      history <- get_enrl(cedar_sections, opt) %>% dplyr::filter(enrolled > 0)
      get_enrollment_momentum(history)
    }, error = function(e) {
      message("[server.R] enrl_trends_data error: ", conditionMessage(e))
      NULL
    })
  }, ignoreInit = TRUE)

  fmt_enrl_change <- function(change_abs, change_pct) {
    if (is.na(change_abs)) return("")
    arrow_chr <- if (change_abs > 0) "\u2191" else if (change_abs < 0) "\u2193" else "\u2192"
    sign_chr  <- if (change_abs >= 0) "+" else "\u2212"
    count_str <- paste0(" (", sign_chr, abs(change_abs), ")")
    if (!is.na(change_pct)) paste0(arrow_chr, abs(change_pct), "%", count_str) else paste0(sign_chr, abs(change_abs))
  }

  make_trend_list <- function(courses, color) {
    if (is.null(courses) || nrow(courses) == 0) return(NULL)
    tags$ul(
      style = "list-style: none; padding: 0;",
      lapply(seq_len(min(15, nrow(courses))), function(i) {
        row <- courses[i, ]
        change_str <- fmt_enrl_change(row$change_abs, row$change_pct)
        tags$li(
          style = "padding: 6px 0; border-bottom: 1px solid #eee;",
          tags$span(style = "font-weight: 600;", row$subject_course), " ",
          tags$span(style = "color: #555; font-size: 0.88em;", row$course_title),
          tags$div(
            style = paste0("font-size: 0.82em; color: ", color, "; margin-top: 2px;"),
            paste0("avg ", round(row$avg_enrl, 0), " enrolled  \u2022  ",
                   change_str, " over window")
          )
        )
      })
    )
  }

  output$enrl_trends_growing <- renderUI({
    trends <- enrl_trends_data()
    if (is.null(trends)) {
      msg <- if (is.null(input$enrl_dept) || length(input$enrl_dept) != 1)
        "Select a single department to see enrollment trends."
      else
        "No growing courses found."
      return(p(msg, style = "color: #999;"))
    }
    result <- make_trend_list(trends$growing, "#2e7d32")
    if (is.null(result)) p("No courses with sustained growth found.", style = "color: #999;") else result
  })

  output$enrl_trends_investigate <- renderUI({
    trends <- enrl_trends_data()
    if (is.null(trends)) {
      msg <- if (is.null(input$enrl_dept) || length(input$enrl_dept) != 1)
        "Select a single department to see enrollment trends."
      else
        "No declining courses found."
      return(p(msg, style = "color: #999;"))
    }
    result <- make_trend_list(trends$investigate, "#c62828")
    if (is.null(result)) p("No courses with sustained decline found.", style = "color: #999;") else result
  })


output$enrl_summary <- DT::renderDataTable({
  # Summary table works with or without grouping variables.
  # Crosslist tab (input$enrl_crosslist_tabs) filters the data post-query.
  tryCatch({
    enrl_out <- enrl_data()
    data <- enrl_out$data

    # Show filter warning if enrollment filter eliminated all data
    if (!is.null(enrl_out$filter_warning) && nchar(enrl_out$filter_warning) > 0) {
      showNotification(
        HTML(enrl_out$filter_warning),
        type = "warning",
        duration = 10,
        id = "enrl_filter_warning"
      )
    }

    if (is.null(data) || nrow(data) == 0) return(NULL)

    # Apply crosslist tab filter (only when section-level data has XlistRole)
    tab <- input$enrl_crosslist_tabs
    if (!is.null(tab) && tab != "all" && "XlistRole" %in% colnames(data)) {
      if (tab == "home") {
        data <- data %>% filter(is.na(XlistRole) | XlistRole %in% c("home", "internal"))
      } else if (tab == "split") {
        data <- data %>% filter(coalesce(IsSplit, FALSE))
      } else if (tab == "xl-home") {
        data <- data %>% filter(XlistRole == "home" & coalesce(XlistExternal, FALSE))
      } else if (tab == "away") {
        data <- data %>% filter(XlistRole == "partner" & coalesce(XlistExternal, FALSE))
      }
    }

    # Filtering helper columns — hide from the displayed table
    data <- data %>% select(-any_of(c("XlistExternal", "IsSplit")))

    return(data)
  }, error = function(e) {
    return(NULL)
  })
}, options = list(
  pageLength = 50,
  scrollX = TRUE,
  scrollY = "100vh",
  scrollCollapse = TRUE
))

# Class list enrollment summary table
output$enrl_cl_summary <- DT::renderDataTable({
  tryCatch({
    cl_data <- enrl_data()$cl_data
    if (is.null(cl_data) || nrow(cl_data) == 0) return(NULL)
    return(cl_data)
  }, error = function(e) {
    return(NULL)
  })
}, options = list(
  pageLength = 50,
  scrollX = TRUE,         # Enable horizontal scrolling with fixed headers
  scrollY = "100vh",
  scrollCollapse = TRUE
))


# Download handler for enrollment summary CSV
output$enrl_summary_download <- downloadHandler(
  filename = function() {
    paste0("enrollment_summary_", Sys.Date(), ".csv")
  },
  content = function(file) {
    data <- NULL
    try({
      ed <- enrl_data()
      if (!is.null(ed) && !is.null(ed$data)) data <- ed$data
    }, silent = TRUE)

    # Apply the same crosslist tab filter as the displayed table
    if (!is.null(data) && nrow(data) > 0 && "XlistRole" %in% colnames(data)) {
      tab <- isolate(input$enrl_crosslist_tabs)
      if (!is.null(tab) && tab != "all") {
        if (tab == "home") {
          data <- data %>% filter(is.na(XlistRole) | XlistRole %in% c("home", "internal"))
        } else if (tab == "split") {
          data <- data %>% filter(coalesce(IsSplit, FALSE))
        } else if (tab == "xl-home") {
          data <- data %>% filter(XlistRole == "home" & coalesce(XlistExternal, FALSE))
        } else if (tab == "away") {
          data <- data %>% filter(XlistRole == "partner" & coalesce(XlistExternal, FALSE))
        }
      }
      data <- data %>% select(-any_of(c("XlistExternal", "IsSplit")))
    }

    if (is.null(data) || nrow(data) == 0) {
      write.csv(data.frame(message = "No enrollment data available for selected filters"), file, row.names = FALSE)
    } else {
      write.csv(data, file, row.names = FALSE)
    }
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
  low_enrl_data <- eventReactive(input$low_enrl_button, {
    # Log low enrollment report generation
    log_report_generation(session, "low_enrollment", list(
      threshold_lower = input$low_enrl_threshold_lower,
      threshold_upper = input$low_enrl_threshold_upper,
      threshold_split = input$low_enrl_threshold_split,
      threshold_grad  = input$low_enrl_threshold_grad,
      term = input$enrl_term,
      campus = input$enrl_campus,
      college = input$enrl_college,
      dept = input$enrl_dept,
      im = input$enrl_im,
      pt = input$enrl_pt,
      level = input$enrl_level
    ))

    # Set up options for filtering - use main enrollment filters.
    # Note: level filter is intentionally excluded here so all four levels are
    # fetched in one pass; level-specific filtering happens in the per-level reactives.
    opt <- list()
    opt$term <- input$enrl_term
    opt$course_campus <- input$enrl_campus
    opt$course_college <- input$enrl_college
    opt$dept <- input$enrl_dept
    opt$subj <- input$enrl_subj
    opt$im <- input$enrl_im
    opt$pt <- input$enrl_pt
    opt$gen_ed <- input$enrl_gen_ed
    opt$inst <- input$enrl_inst
    opt$course <- input$enrl_course

    # --- Detect future vs current/past terms ---
    selected_terms <- input$enrl_term
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

    # Show loading notification
    mode_label <- if (has_future) "enrollment concerns" else "low enrollment alerts"
    status_message <- create_timing_status_message("low_enrollment", paste("Gathering", mode_label))
    showNotification(status_message, type = "warning", duration = NULL, id = "low_enrl_loading")
    low_enrl_timer <- start_report_timer("low_enrollment", list(
      term = input$enrl_term,
      dept = input$enrl_dept
    ))

    # =====================================================================
    # FUTURE TERM: Historical enrollment concerns
    # =====================================================================
    if (has_future) {
      cedar_debug("[server.R] Future term detected — switching to concerns mode")
      result <- get_enrollment_concerns(cedar_sections, opt, n_history_terms = 4)

      if (is.null(result) || nrow(result) == 0) {
        cedar_debug("[server.R] No courses found on future schedule")
        low_enrl_duration <- end_report_timer(low_enrl_timer)
        removeNotification("low_enrl_loading")
        return(NULL)
      }

      cedar_debug("[server.R] Enrollment concerns ready: ", nrow(result), " courses")
      low_enrl_duration <- end_report_timer(low_enrl_timer)
      removeNotification("low_enrl_loading")
      showNotification(paste0("Enrollment concerns data ready (", round(low_enrl_duration, 1), "s)"),
                       type = "message", duration = 5)
      return(result)
    }

    # =====================================================================
    # CURRENT/PAST TERM: Actual low enrollment alerts (existing logic)
    # =====================================================================

    # Fetch up to 25% above the highest threshold so the buffer zone is included;
    # each level-specific reactive applies its own threshold + buffer for final filtering.
    max_threshold <- ceiling(max(
      input$low_enrl_threshold_lower,
      input$low_enrl_threshold_upper,
      input$low_enrl_threshold_split,
      input$low_enrl_threshold_grad,
      na.rm = TRUE
    ) * 1.25)

    cedar_debug("[server.R] Fetching all low enrollment courses (max threshold: ", max_threshold, ")")
    all_low <- get_low_enrollment_courses(cedar_sections, opt, threshold = max_threshold)

    if (is.null(all_low) || nrow(all_low) == 0) {
      cedar_debug("[server.R] No low enrollment courses found")
      return(NULL)
    }

    # Respect the low-enrl-specific min filter (overrides main enrl_min for this tab).
    if (!is.null(input$low_enrl_min_enrl) && !is.na(input$low_enrl_min_enrl) && input$low_enrl_min_enrl > 0) {
      min_enrl_val <- as.integer(input$low_enrl_min_enrl)
      all_low <- all_low %>% filter(enrolled >= min_enrl_val)
      cedar_debug("[server.R] After min enrl filter (enrolled >= ", min_enrl_val, "): ", nrow(all_low), " rows")
    }

    if (nrow(all_low) == 0) return(NULL)

    # Count active home sections and total enrollment per course/term for context.
    section_counts <- get_course_section_counts(cedar_sections)

    all_low <- all_low %>%
      left_join(section_counts, by = c("term", "subject_course", "course_title", "campus")) %>%
      mutate(
        n_sections  = coalesce(n_sections, 1L),
        course_enrl = coalesce(course_enrl, total_enrl)
      )

    # Determine the current term for excluding from history
    current_term <- max(all_low$term, na.rm = TRUE)

    # Add enrollment history — but skip for large result sets since rowwise is slow
    # (each row triggers a full-table filter of cedar_sections)
    history_limit <- 500
    if (nrow(all_low) <= history_limit) {
      cedar_debug("[server.R] Adding enrollment history for ", nrow(all_low), " courses...")
      all_low <- all_low %>%
        rowwise() %>%
        mutate(
          history = list(get_course_enrollment_history(
            cedar_sections, campus, department, subject_course, course_title, delivery_method,
            n_terms = 4, exclude_term = current_term
          )),
          history_text = format_enrollment_history(history)
        ) %>%
        ungroup()
    } else {
      cedar_debug("[server.R] Skipping enrollment history (", nrow(all_low),
              " rows exceeds limit of ", history_limit, ")")
      all_low$history_text <- NA_character_
      showNotification(
        paste0("Enrollment history skipped (", nrow(all_low),
               " courses exceed ", history_limit, " row limit). ",
               "Add filters to narrow results and enable history."),
        type = "warning", duration = 8
      )
    }

    cedar_debug("[server.R] Low enrollment base data ready: ", nrow(all_low), " rows")

    low_enrl_duration <- end_report_timer(low_enrl_timer)
    removeNotification("low_enrl_loading")
    showNotification(paste0("Low enrollment data ready (", round(low_enrl_duration, 1), "s)"),
                     type = "message", duration = 5)

    return(all_low)
  }, ignoreNULL = TRUE, ignoreInit = TRUE)

  # Level-specific filtered reactives (applied after button press, using per-level thresholds).
  # Split-level courses are excluded from the per-level tabs (they appear in the split tab).
  # In concerns mode, filters on avg_enrl with buffer zone instead of total_enrl.
  .filter_by_level <- function(data, level_val, threshold, is_split_filter = FALSE) {
    if (enrl_mode() == "concerns") {
      # Concerns mode: show courses with avg below threshold + buffer, plus no-history courses
      if (is_split_filter) {
        data %>% filter(is_split == TRUE,
                        n_prior_terms == 0 | avg_enrl < threshold + 5)
      } else {
        data %>% filter(level == level_val, !is_split,
                        n_prior_terms == 0 | avg_enrl < threshold + 5)
      }
    } else {
      # Alerts mode: include 25% buffer above threshold so near-threshold courses
      # appear as "buffer" (green) rather than being excluded entirely.
      fetch_limit <- ceiling(threshold * 1.25)
      if (is_split_filter) {
        data %>% filter(is_split == TRUE, enrolled <= fetch_limit)
      } else {
        data %>% filter(level == level_val, !is_split, enrolled <= fetch_limit)
      }
    }
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
        "Set your filters above, then click ", tags$strong("Calculate"), " to find low enrollment courses."
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
        h4("No Courses Found", style = "margin: 10px 0;"),
        p(no_results_msg, style = "margin: 5px 0; font-size: 1.1em;"),
        p("Try adjusting your filters or thresholds.",
          style = "margin-top: 15px; color: #666;")
      ))
    }

    # Combine all four level-filtered sets, tagging each row with its level threshold.
    combined <- bind_rows(
      .filter_by_level(base, "lower", input$low_enrl_threshold_lower) %>%
        mutate(.threshold = input$low_enrl_threshold_lower),
      .filter_by_level(base, "upper", input$low_enrl_threshold_upper) %>%
        mutate(.threshold = input$low_enrl_threshold_upper),
      .filter_by_level(base, NA, input$low_enrl_threshold_split, is_split_filter = TRUE) %>%
        mutate(.threshold = input$low_enrl_threshold_split),
      .filter_by_level(base, "grad", input$low_enrl_threshold_grad) %>%
        mutate(.threshold = input$low_enrl_threshold_grad)
    )

    if (nrow(combined) == 0) {
      return(div(
        class = "alert alert-info",
        style = "margin: 20px; padding: 20px; text-align: center;",
        icon("circle-check", style = "font-size: 2em; margin-bottom: 10px;"),
        h4("No Courses of Concern", style = "margin: 10px 0;"),
        p("No courses match the current thresholds and filters.",
          style = "margin: 5px 0; font-size: 1.1em;")
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
        style = "margin-bottom: 20px;",
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--critical",
                h4(critical, style = "margin: 10px 0;"),
                p("Historically Low (< 50%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--warning",
                h4(warning_count, style = "margin: 10px 0;"),
                p("Borderline (50\u201375%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--info",
                h4(watch, style = "margin: 10px 0;"),
                p("Watch (75\u2013100%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--success",
                h4(buffer, style = "margin: 10px 0;"),
                p("Near Threshold (\u2265 100%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--neutral",
                h4(no_history, style = "margin: 10px 0;"),
                p("No Prior History", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_courses, style = "margin: 10px 0;"),
                p("Total Courses", style = "margin: 5px 0;")
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
        style = "margin-bottom: 20px;",
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--critical",
                h4(critical, style = "margin: 10px 0;"),
                p("Critical (< 50% of threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--warning",
                h4(warning_count, style = "margin: 10px 0;"),
                p("Warning (50\u201375% of threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--info",
                h4(watch, style = "margin: 10px 0;"),
                p("Watch (75\u2013100% of threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center alert-box--buffer",
                h4(buffer, style = "margin: 10px 0;"),
                p("Monitor (above threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_courses, style = "margin: 10px 0;"),
                p("Total Courses", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(total_students, style = "margin: 10px 0;"),
                p("Total Students", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                h4(avg_enrollment, style = "margin: 10px 0;"),
                p("Avg Enrollment", style = "margin: 5px 0;")
            )
        )
      )
    }
  })


  # Shared helper: apply proportional color-banding to an enrollment column in a DT.
  # include_buffer adds a green zone for courses at/above threshold (concerns mode).
  .style_enrl_col <- function(dt, enrl_col, threshold, include_buffer = FALSE) {
    critical <- threshold * 0.5
    warning  <- threshold * 0.75
    if (include_buffer) {
      dt %>% formatStyle(enrl_col,
        backgroundColor = styleInterval(
          c(critical, warning, threshold),
          c('#f8d7da', '#fff3cd', '#d1ecf1', '#d4edda')  # Red/Yellow/Blue/Green
        ),
        fontWeight = 'bold')
    } else {
      dt %>% formatStyle(enrl_col,
        backgroundColor = styleInterval(
          c(critical, warning),
          c('#f8d7da', '#fff3cd', '#d1ecf1')  # Red/Yellow/Blue
        ),
        fontWeight = 'bold')
    }
  }

  # Helper: build a formatted DT for a low-enrollment dataset given a threshold.
  # show_split_info: if TRUE, adds a "Sections" column showing all partner courses
  # in the split-level group (e.g., "BIOL 402 / BIOL 502").
  .make_low_enrl_dt <- function(data, threshold, show_split_info = FALSE) {
    if (is.null(data) || nrow(data) == 0) return(NULL)

    # Ensure history_text exists (may be absent if history was skipped for large result sets)
    if (!"history_text" %in% names(data)) {
      data$history_text <- NA_character_
    }
    data <- data %>% mutate(history_text = ifelse(is.na(history_text), "\u2014", history_text))

    # Ensure n_sections and course_enrl exist
    if (!"n_sections" %in% names(data)) data$n_sections <- 1L
    if (!"course_enrl" %in% names(data)) data$course_enrl <- data$total_enrl

    if (show_split_info && "split_sections" %in% names(data)) {
      display_data <- data %>%
        select(
          Campus = campus,
          Dept = department,
          Course = subject_course,
          `Sect#` = section,
          `Split Partners` = split_sections,
          Title = course_title,
          Term = term,
          Sects = n_sections,
          Enrolled = enrolled,
          `XL Total` = total_enrl,
          `Course Total` = course_enrl,
          `Prior History` = history_text
        ) %>%
        arrange(Enrolled)
      center_targets <- c(3, 6, 7, 8, 9, 10)  # Sect#, Term, Sects, Enrolled, XL Total, Course Total
      enrl_col <- "Enrolled"
    } else {
      display_data <- data %>%
        select(
          Campus = campus,
          Dept = department,
          Course = subject_course,
          `Sect#` = section,
          Title = course_title,
          Term = term,
          Sects = n_sections,
          Enrolled = enrolled,
          `XL Total` = total_enrl,
          `Course Total` = course_enrl,
          `Prior History` = history_text
        ) %>%
        arrange(Enrolled)
      center_targets <- c(3, 5, 6, 7, 8, 9)  # Sect#, Term, Sects, Enrolled, XL Total, Course Total
      enrl_col <- "Enrolled"
    }

    datatable(
      display_data,
      rownames = FALSE,
      options = list(
        pageLength = 25,
        columnDefs = list(
          list(className = 'dt-center', targets = center_targets)
        ),
        scrollX = TRUE
      ),
      class = 'cell-border stripe hover'
    ) %>%
      .style_enrl_col(enrl_col, threshold, include_buffer = TRUE)
  }

  # Helper: build a formatted DT for enrollment concerns (future term, historical averages).
  .make_concern_dt <- function(data, threshold, show_split_info = FALSE) {
    if (is.null(data) || nrow(data) == 0) return(NULL)

    # Replace NA avg_enrl with 0 for display/styling (no-history courses)
    data <- data %>%
      mutate(
        avg_enrl_display = coalesce(avg_enrl, 0),
        history_text = coalesce(history_text, "No prior history")
      )

    if (show_split_info && "split_sections" %in% names(data)) {
      display_data <- data %>%
        select(
          Campus = campus,
          Department = department,
          Course = subject_course,
          `Split Partners` = split_sections,
          Title = course_title,
          Sects = n_sections,
          `Sect Enrl` = current_enrl,
          `Hist Avg` = avg_enrl_display,
          Trend = trend,
          `# Terms` = n_prior_terms,
          `Prior History` = history_text
        ) %>%
        arrange(`Hist Avg`)
      center_targets <- c(5, 6, 7, 8, 9)  # Sects, Enrolled, Hist Avg, Trend, # Terms
      enrl_col <- "Hist Avg"
    } else {
      display_data <- data %>%
        select(
          Campus = campus,
          Department = department,
          Course = subject_course,
          Title = course_title,
          Sects = n_sections,
          `Sect Enrl` = current_enrl,
          `Hist Avg` = avg_enrl_display,
          Trend = trend,
          `# Terms` = n_prior_terms,
          `Prior History` = history_text
        ) %>%
        arrange(`Hist Avg`)
      center_targets <- c(4, 5, 6, 7, 8)  # Sects, Enrolled, Hist Avg, Trend, # Terms
      enrl_col <- "Hist Avg"
    }

    datatable(
      display_data,
      rownames = FALSE,
      options = list(
        pageLength = 25,
        columnDefs = list(
          list(className = 'dt-center', targets = center_targets)
        ),
        scrollX = TRUE
      ),
      class = 'cell-border stripe hover'
    ) %>%
      .style_enrl_col(enrl_col, threshold, include_buffer = TRUE) %>%
      formatStyle('Trend',
        color = styleEqual(
          c("\u2191 up", "\u2193 down", "\u2194 stable", "\u2014"),
          c("#28a745", "#dc3545", "#6c757d", "#adb5bd")
        )
      )
  }

  # Four level-specific DataTable outputs
  # Helper: pick the right DT builder based on mode
  .render_enrl_dt <- function(data, threshold, show_split_info = FALSE) {
    if (enrl_mode() == "concerns") {
      .make_concern_dt(data, threshold, show_split_info)
    } else {
      .make_low_enrl_dt(data, threshold, show_split_info)
    }
  }

  # server = FALSE: embed full data in the Shiny output payload instead of
  # using DataTables AJAX (server = TRUE default). With server-mode DT, hidden
  # tab instances never issue the AJAX request for new data, so changing dept
  # and clicking Gather only updates the currently visible subtab. With
  # server = FALSE the complete dataset is sent with each re-render, so all
  # four subtabs receive fresh data regardless of which one is active.
  # suspendWhenHidden = FALSE ensures Shiny actually executes the render for
  # hidden tabs rather than deferring until the tab is navigated to.
  output$low_enrl_table_lower <- DT::renderDataTable(server = FALSE, {
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_lower(), input$low_enrl_threshold_lower)
  })

  output$low_enrl_table_upper <- DT::renderDataTable(server = FALSE, {
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_upper(), input$low_enrl_threshold_upper)
  })

  output$low_enrl_table_split <- DT::renderDataTable(server = FALSE, {
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_split(), input$low_enrl_threshold_split, show_split_info = TRUE)
  })

  output$low_enrl_table_grad <- DT::renderDataTable(server = FALSE, {
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_grad(), input$low_enrl_threshold_grad)
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
      combined <- bind_rows(
        low_enrl_lower(),
        low_enrl_upper(),
        low_enrl_split(),
        low_enrl_grad()
      ) %>%
        select(-any_of("history"))
      write.csv(combined, file, row.names = FALSE)
    }
  )


  #################################
  #         COURSE REPORT         #
  #################################

  # Reactive value to store course report data
  course_report_data <- reactiveVal(NULL)
  
  # Clear cached data when course selection changes
  observeEvent(input$cr_course, {
    # Log course selection
    log_data_filter(session, "course_report_course", input$cr_course)
    
    # Only clear if there's actually cached data and it's for a different course
    cached_data <- course_report_data()
    if (!is.null(cached_data) && 
        !is.null(cached_data$course_code) && 
        cached_data$course_code != input$cr_course) {
      cedar_debug("[server.R] Course changed from ", cached_data$course_code, " to ", input$cr_course, ". Clearing cached data.")
      course_report_data(NULL)
    }
  }, ignoreInit = TRUE)

  # Log campus filter changes
  observeEvent(input$cr_campus, {
    log_data_filter(session, "cr_campus", input$cr_campus)
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


  # Course Report Interactive Generation
  observeEvent(input$cr_generate_button, {
    course <- input$cr_course
    req(course, course != "")

    # Clear cached course report data to force fresh generation
    course_report_data(NULL)
    
    # Log course report generation
    log_report_generation(session, "course_report", list(
      course = course,
      skip_forecast = TRUE
    ))

    # Show loading notification with average time
    avg_time <- get_average_report_time("course_report")
    status_message <- if (is.null(avg_time)) {
      "Analyzing course data... This may take a few moments."
    } else {
      paste0("Analyzing course data... Average time: ", avg_time, " seconds.")
    }
    showNotification(status_message, type = "default", duration = NULL, id = "course_loading")

    # Start timing
    timer <- start_report_timer("course_report", list(
      course = course,
      skip_forecast = TRUE
    ))

    tryCatch({
      opt <- list()
      opt[["shiny"]] <- TRUE
      opt[["course"]] <- course
      opt[["skip_forecast"]] <- TRUE
      # DO NOT set course_campus here - it would filter ALL data generation
      # Campus filtering is applied only at the display level for rollcall plots

      cedar_debug("[server.R] Generating interactive report data for: ", course)
      c_params <- create_course_base_data(data_objects, opt)

      duration_sec <- end_report_timer(timer)
      course_report_data(c_params)

      removeNotification("course_loading")
      showNotification(paste0("Course analysis complete! (", round(duration_sec, 1), "s)"),
                      type = "message", duration = 5)

      # If the user was already on a non-Enrollment tab, lazy-load it now.
      cr_load_tab(isolate(input$cr_tabs), c_params)

    }, error = function(e) {
      handle_error(e, "course_report", "course_loading")

      # End timer even on error
      tryCatch(end_report_timer(timer), error = function(timer_error) {
        message("[server.R] Error ending timer: ", timer_error$message)
      })
    })
  }, ignoreInit = TRUE) # end observeEvent for cr_generate_button

  # Shared helper — compute one tab's data and merge it into course_report_data().
  # Called from both the tab-click observer and the "Analyze Course" handler
  # (for the case where the user was already on a non-Enrollment tab).
  cr_load_tab <- function(tab, base = course_report_data()) {
    if (is.null(base) || is.null(tab)) return()

    .safe <- function(expr, label) {
      tryCatch(expr, error = function(e) {
        write_log("ERROR", paste0("cr_load_tab_", label),
                  list(error = e$message, tab = tab), session$token)
        NULL
      })
    }

    if (tab == "Course Flows" && length(grep("^sankey_", names(base$plots))) == 0) {
      showNotification("Computing course flows...", type = "message", duration = NULL, id = "cr_tab_loading")
      sankey_plots <- .safe(compute_cr_flows_tab(base, data_objects), "Course Flows")
      removeNotification("cr_tab_loading")
      if (!is.null(sankey_plots) && length(sankey_plots) > 0) {
        base$plots <- c(base$plots, sankey_plots)
        course_report_data(base)
      }

    } else if (tab == "DFW" && !"dfw_summary_plot" %in% names(base$plots)) {
      showNotification("Computing DFW data...", type = "message", duration = NULL, id = "cr_tab_loading")
      dfw_plots <- .safe(compute_cr_dfw_tab(base), "DFW")
      removeNotification("cr_tab_loading")
      if (!is.null(dfw_plots) && length(dfw_plots) > 0) {
        base$plots <- c(base$plots, dfw_plots)
        course_report_data(base)
      }
    }

    # Outcomes (dfw_trend, instructor_dfw, persistence) are needed by both the
    # DFW and Retention tabs. Computed as a separate block — not else-if — so
    # that they load on the FIRST DFW tab visit even after DFW plots are computed.
    if (tab %in% c("DFW", "Retention")) {
      base <- course_report_data() %||% base   # refresh after possible DFW plot update above
      if (is.null(base$outcomes)) {
        showNotification("Computing outcomes...", type = "message", duration = NULL, id = "cr_tab_loading")
        outcomes <- .safe(compute_cr_outcomes_tab(base, data_objects), "Outcomes")
        removeNotification("cr_tab_loading")
        base$outcomes <- outcomes
        course_report_data(base)
      }
    }
  }

  # Lazy-load per-tab data when user clicks a course report tab for the first time.
  observeEvent(input$cr_tabs, {
    tryCatch(
      cr_load_tab(input$cr_tabs),
      error = function(e) {
        write_log("ERROR", "cr_tabs_observer",
                  list(error = e$message, tab = input$cr_tabs), session$token)
      }
    )
  }, ignoreInit = TRUE)

  # "Update Flow Diagrams" button — recompute Sankey with current min/max settings.
  observeEvent(input$cr_update_flows, {
    base <- course_report_data()
    req(!is.null(base))
    min_contrib <- as.integer(input$cr_flow_min_contrib %||% 2L)
    max_courses <- as.integer(input$cr_flow_max_courses %||% 6L)
    showNotification("Recomputing flow diagrams...", type = "message", duration = NULL, id = "cr_tab_loading")
    sankey_plots <- tryCatch(
      compute_cr_flows_tab(base, data_objects, min_contrib = min_contrib, max_courses = max_courses),
      error = function(e) { message("[server.R] cr_update_flows error: ", e$message); list() }
    )
    removeNotification("cr_tab_loading")
    if (length(sankey_plots) > 0) {
      existing <- base$plots[!grepl("^sankey_", names(base$plots))]
      base$plots <- c(existing, sankey_plots)
      course_report_data(base)
    }
  }, ignoreInit = TRUE)

  # Render course report UI
  output$cr_report <- renderUI({
    data <- course_report_data()
    if (is.null(data)) {
      return(div(
        class = "empty-state",
        h4("Select a course and click 'Generate Course Report' to view data.")
      ))
    }
    
    # Check if we have meaningful enrollment data
    has_enrollment_plot <- !is.null(data$plots) && "enrollment_plot" %in% names(data$plots) && !is.null(data$plots$enrollment_plot)
    has_enrollment_table <- !is.null(data$tables) && "enrls" %in% names(data$tables) && !is.null(data$tables$enrls) && nrow(data$tables$enrls) > 0
    
    # Create a tabbed interface for different report sections
    tabsetPanel(
      tabPanel("Enrollment", 
        fluidRow(
          column(12,
            h3(paste("Course:", data$course_code, "-", data$course_name)),
            
            if(has_enrollment_plot || has_enrollment_table) {
              tagList(
                div(
                  style = "display: flex; align-items: center; gap: 10px;",
                  h4("Enrollment Trends", style = "margin: 0;"),
                  tags$i(
                    class = "fa fa-info-circle text-info",
                    style = "cursor: pointer;",
                    title = "Shows enrollment patterns over time. Data includes total enrollment, capacity, and trends across academic periods. Helps identify enrollment peaks, declining interest, or seasonal patterns.",
                    `data-toggle` = "tooltip",
                    `data-placement` = "right"
                  )
                ),
                
                # Enrollment plot section
                if(has_enrollment_plot) {
                  div(
                    class = "card card-default",
                    div(class = "card-header", h5("Enrollment Over Time")),
                    div(class = "card-body", plotlyOutput("cr_enrollment_plot"))
                  )
                },
                
                # Enrollment data table section
                if(has_enrollment_table) {
                  div(
                    class = "card card-default",
                    style = "margin-top: 20px;",
                    div(class = "card-header", h5("Enrollment Data")),
                    div(class = "card-body", DT::DTOutput("cr_enrollment_table"))
                  )
                }
              )
            } else {
              div(
                class = "alert alert-info",
                style = "margin-top: 20px;",
                icon("info-circle"),
                " No enrollment data available for this course."
              )
            }
          )
        )
      ),
      tabPanel("Student Flow", 
        fluidRow(
          column(12,
            h3(paste("Course:", data$course_code, "-", data$course_name)),
            
            # Check for sankey plots and create tabs for each term type
            if(any(grepl("sankey_.*_plot", names(data$plots)))) {
              sankey_plot_names <- names(data$plots)[grepl("sankey_.*_plot", names(data$plots))]
              term_types <- gsub("sankey_(.*)_plot", "\\1", sankey_plot_names)
              
              tagList(
                h4("Student Flow Patterns"),
                p("Shows where students come from before taking this course and where they go after."),
                
                # Create sub-tabs for each term type
                tabsetPanel(
                  id = "sankey_subtabs",
                  lapply(term_types, function(term_type) {
                    tabPanel(
                      title = toupper(term_type),
                      div(
                        style = "margin-top: 20px;",
                        plotlyOutput(paste0("cr_sankey_", term_type, "_plot"))
                      )
                    )
                  })
                )
              )
            } else {
              div(
                style = "text-align: center; padding: 20px;",
                h4("No Student Flow Diagrams Available"),
                p("This course primarily has students who retake the same course, or insufficient cross-course enrollment patterns."),
                p("Student flow diagrams require meaningful enrollment flows between different courses."),
                br(),
                p(style = "font-size: 0.9em; color: #666;", 
                  "Try selecting a different course that is part of a sequence or has prerequisite relationships.")
              )
            }
          )
        )
      ),
      tabPanel("Detailed Data",
        fluidRow(
          column(12,
            h3(paste("Course:", data$course_code, "-", data$course_name)),
            
            # Show available data tables
            tabsetPanel(
              tabPanel("Forecasts",
                if(!is.null(data$tables$forecasts) && nrow(data$tables$forecasts) > 0) {
                  DT::DTOutput("cr_forecasts_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No forecast data available.")
                }
              ),
              tabPanel("Rollcall by Classification",
                if(!is.null(data$tables$rollcall_by_class) && nrow(data$tables$rollcall_by_class) > 0) {
                  DT::DTOutput("cr_rollcall_class_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No rollcall data by classification available.")
                }
              ),
              tabPanel("Rollcall by Major",
                if(!is.null(data$tables$rollcall_by_major) && nrow(data$tables$rollcall_by_major) > 0) {
                  DT::DTOutput("cr_rollcall_major_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No rollcall data by major available.")
                }
              ),
              tabPanel("Grades",
                if(!is.null(data$tables$grades) && nrow(data$tables$grades) > 0) {
                  DT::DTOutput("cr_grades_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No grade data available.")
                }
              )
            )
          )
        )
      ),
      tabPanel("Debug", 
        fluidRow(
          column(6,
            h4("Available Tables:"),
            verbatimTextOutput("cr_debug_tables")
          ),
          column(6,
            h4("Available Plots:"),
            verbatimTextOutput("cr_debug_plots")
          )
        )
      )
    )
  })

  # Render individual plot outputs for course report
  output$cr_enrollment_plot <- renderPlotly({
    data <- course_report_data()
    cedar_debug("[server.R] cr_enrollment_plot renderer called. Data is null: ", is.null(data))

    if (is.null(data) || !("tables" %in% names(data)) || is.null(data$tables$cl_enrls)) {
      return(NULL)
    }

    campus_vals <- input$cr_campus
    cl_enrls <- data$tables$cl_enrls
    if (!is.null(campus_vals) && length(campus_vals) > 0) {
      cl_enrls <- cl_enrls %>% filter(campus %in% campus_vals)
    }

    if (nrow(cl_enrls) == 0) return(NULL)

    result <- make_enrl_plot_from_cls(cl_enrls, list())
    result$cl_enrl
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
          
          # Create a titled plot output
          plot_list[[length(plot_list) + 1]] <- div(
            h5(paste("Student Flow -", stringr::str_to_title(term_type), "Terms")),
            plotlyOutput(output_name, height = "500px"),
            br()
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

  # Render data tables for course report
  output$cr_enrollment_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$cl_enrls)) {
      cl_enrls_data <- data$tables$cl_enrls

      campus_vals <- input$cr_campus
      if (!is.null(campus_vals) && length(campus_vals) > 0) {
        cl_enrls_data <- cl_enrls_data %>% filter(campus %in% campus_vals)
      }

      cl_enrls_data <- cl_enrls_data %>% ungroup() %>% select(
        campus,
        college,
        term,
        term_type,
        subject_course,
        registered,
        registered_mean,
        cl_total,
        cl_total_mean,
        dr_early,
        dr_early_mean,
        dr_late,
        dr_late_mean,
        dr_all,
        dr_all_mean
      ) %>% arrange(subject_course, campus, term_type)

      return(cl_enrls_data)
    }
    return(NULL)
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  output$cr_forecasts_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$forecasts)) {
      data$tables$forecasts
    }
  }, options = list(pageLength = 10, scrollX = TRUE))

  output$cr_rollcall_class_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$rollcall_by_class)) {
      data$tables$rollcall_by_class
    }
  }, options = list(pageLength = 10, scrollX = TRUE))

  output$cr_rollcall_major_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$rollcall_by_major)) {
      data$tables$rollcall_by_major
    }
  }, options = list(pageLength = 10, scrollX = TRUE))


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
  
  # Single classification table (combining all terms) with campus filtering
  output$cr_rollcall_class_fall_table <- DT::renderDataTable({
    render_rollcall_table("rollcall_by_class", "classification table")
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  # Single classification table (same as fall table for consistency with UI)
  output$cr_rollcall_class_spring_table <- DT::renderDataTable({
    render_rollcall_table("rollcall_by_class", "classification table")
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  # Single major table (combining all terms) with campus filtering
  output$cr_rollcall_major_fall_table <- DT::renderDataTable({
    render_rollcall_table("rollcall_by_major", "major table")
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  # Single major table (same as fall table for consistency with UI)
  output$cr_rollcall_major_spring_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$rollcall_by_major)) {
      data$tables$rollcall_by_major
    }
  }, options = list(pageLength = 10, scrollX = TRUE))


  # Passing grades vector for DFW calculation — driven by cr_dfw_threshold input.
  # "below_c": current global passing_grades (A+ through C, CR) — C- and D grades are DFW.
  # "f_only":  adds C-, D+, D, D- to passing — only F grade (plus W, I, NC, etc.) is DFW.
  dfw_passing_grades <- reactive({
    threshold <- input$cr_dfw_threshold %||% "below_c"
    if (identical(threshold, "f_only")) {
      c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "CR", "P", "S")
    } else {
      passing_grades  # global from grades.R: A+ through C, CR
    }
  })

  # Recompute categorized grade data from raw counts whenever threshold or course changes.
  # Raw counts are cached in course_report_data(); only categorization reruns on threshold change.
  dfw_grade_data_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), "tables" %in% names(data), !is.null(data$tables$grade_data))
    grade_data <- data$tables$grade_data
    counts <- grade_data$counts
    if (is.null(counts) || nrow(counts) == 0) return(grade_data)
    pg <- dfw_passing_grades()
    group_cols <- c("campus", "college", "term", "subject_course", "instructor_last_name")
    categorized <- categorize_grades(counts, group_cols, pg)
    dfw_sum <- calculate_dfw(categorized)
    grades_list <- build_aggregation_list(dfw_sum, counts)
    grades_list$counts <- counts
    grades_list$dfw_summary <- dfw_sum
    grades_list
  })

  # Grades table
  output$cr_grades_table <- DT::renderDataTable({
    gd <- dfw_grade_data_reactive()
    req(!is.null(gd), !is.null(gd$dfw_summary))
    d <- gd$dfw_summary %>% dplyr::select(-dplyr::any_of("job_category"))
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) d <- d %>% filter(campus %in% campus_filter$values)
    d
  }, options = list(pageLength = 10, scrollX = TRUE))


  # Reactive: regenerate DFW plots from grade data whenever campus filter or threshold changes.
  dfw_plots_reactive <- reactive({
    data <- course_report_data()
    req(!is.null(data), "tables" %in% names(data))
    gd <- dfw_grade_data_reactive()
    req(!is.null(gd))
    campus_filter <- get_campus_filter()
    opt <- data$opt
    if (!is.null(campus_filter)) opt$course_campus <- campus_filter$values
    tryCatch(
      plot_grades_for_course_report(gd, opt),
      error = function(e) {
        write_log("ERROR", "dfw_plots_reactive", list(error = e$message), session$token)
        list()
      }
    )
  })

  # DFW Summary Plot
  output$dfw_summary_plot <- renderPlotly({
    plots <- dfw_plots_reactive()
    req("dfw_summary_plot" %in% names(plots))
    plots[["dfw_summary_plot"]]
  })

  # DFW by term plot
  output$dfw_by_term_plot <- renderPlotly({
    plots <- dfw_plots_reactive()
    req("dfw_by_term_plot" %in% names(plots))
    plots[["dfw_by_term_plot"]]
  })

  # DFW by instructor type plot
  output$dfw_by_inst_type_plot <- renderPlotly({
    plots <- dfw_plots_reactive()
    req("dfw_by_inst_type_plot" %in% names(plots))
    plots[["dfw_by_inst_type_plot"]]
  })

  # Course Report DFW Tab Content (password protected)
  output$cr_dfw_tab_content <- renderUI({
    tryCatch({

    data <- course_report_data()

    if (is.null(data)) {
      return(div(
        class = "alert alert-info", style = "margin: 30px;",
        icon("chart-bar"), " ",
        "Select a course and click ", tags$strong("Analyze Course"), " to view DFW data."
      ))
    }

    if (dfw_authenticated()) {
      # Build a human-readable label for the end term
      end_term_label <- local({
        t  <- as.integer(cedar_report_end_term)
        yr <- t %/% 100L; ss <- t %% 100L
        season <- switch(as.character(ss), "10" = "Spring", "80" = "Fall", "60" = "Summer",
                         paste0("Term ", ss))
        paste0(season, " ", yr)
      })

      # DFW content is visible only after authentication
      threshold <- input$cr_dfw_threshold %||% "below_c"
      if (identical(threshold, "f_only")) {
        passing_label   <- "A+, A, A−, B+, B, B−, C+, C, C−, D+, D, D− (earn credit), CR"
        failed_label    <- "F only"
        dfw_label       <- "F, W (late withdrawal), I, NC, NR, and other non-final grades"
      } else {
        passing_label   <- "A+, A, A−, B+, B, B−, C+, C, CR"
        failed_label    <- "C−, D+, D, D−, F"
        dfw_label       <- "C−, D+, D, D−, F, W (late withdrawal), I, NC, NR, and other non-final grades"
      }

      tagList(
        div(class = "alert alert-info", style = "font-size: 0.85em;",
          icon("circle-info"), " ",
          tags$strong("About DFW rates."), " ",
          "DFW rates indicate the fraction of enrolled students who did not pass a course. ",
          tags$strong("Early drops are excluded"), " — students who withdrew during the add/drop ",
          "period (DR status) never appear on the final grade roster and are not counted. ",
          "All other students — including late withdrawals (W) and incompletes (I) — are counted.",
          tags$br(), tags$br(),
          "Data covers ", tags$strong("Fall 2019 through ", end_term_label), ". The current term ",
          "is excluded because grades are not yet finalized.",
          tags$br(), tags$br(),
          tags$em("This data is intended to help departments understand patterns and support
           instructors — not to evaluate individual instructors punitively. DFW rates reflect
           many factors beyond instructor control, including course level, student preparation,
           and time of day.")
        ),
        div(style = "margin-bottom: 20px;",
          tags$strong("What counts as non-passing?"),
          tags$span(style = "font-size: 0.85em; color: #555; margin-left: 8px;",
            "Affects all charts and the table below."),
          radioButtons("cr_dfw_threshold", label = NULL,
            choices = c(
              "Below C  (C−, D+, D, D− count as DFW — use for courses requiring C or better)" = "below_c",
              "F grade only  (D grades count as passing — use for courses where D earns credit)" = "f_only"
            ),
            selected = threshold,
            inline = FALSE
          )
        ),
        div(class = "alert alert-info", style = "font-size: 0.85em;",
          icon("circle-info"), " ",
          tags$strong("How each grade is counted under the current selection:"), tags$br(), tags$br(),
          tags$table(style = "width: 100%; border-collapse: collapse; font-size: 0.95em;",
            tags$thead(
              tags$tr(
                tags$th(style = "text-align: left; padding: 4px 8px; border-bottom: 1px solid #bee5eb;", "Outcome"),
                tags$th(style = "text-align: left; padding: 4px 8px; border-bottom: 1px solid #bee5eb;", "Grades / Status"),
                tags$th(style = "text-align: left; padding: 4px 8px; border-bottom: 1px solid #bee5eb;", "Counted in DFW?")
              )
            ),
            tags$tbody(
              tags$tr(
                tags$td(style = "padding: 4px 8px;", tags$b("passed")),
                tags$td(style = "padding: 4px 8px;", passing_label),
                tags$td(style = "padding: 4px 8px; color: #155724;", tags$b("No — not counted"))
              ),
              tags$tr(style = "background: #f8f9fa;",
                tags$td(style = "padding: 4px 8px;", tags$b("failed")),
                tags$td(style = "padding: 4px 8px;", failed_label),
                tags$td(style = "padding: 4px 8px; color: #721c24;", tags$b("Yes — numerator + denominator"))
              ),
              tags$tr(
                tags$td(style = "padding: 4px 8px;", tags$b("late_dropped")),
                tags$td(style = "padding: 4px 8px;", "W grade (withdrew after add/drop deadline)"),
                tags$td(style = "padding: 4px 8px; color: #721c24;", tags$b("Yes — numerator + denominator"))
              ),
              tags$tr(style = "background: #f8f9fa;",
                tags$td(style = "padding: 4px 8px;", tags$b("early_dropped")),
                tags$td(style = "padding: 4px 8px;", "DR status (dropped before add/drop deadline)"),
                tags$td(style = "padding: 4px 8px; color: #856404;", tags$b("No — excluded entirely"))
              ),
              tags$tr(
                tags$td(style = "padding: 4px 8px;", tags$b("I, NC, NR, other")),
                tags$td(style = "padding: 4px 8px;", "Incomplete, no credit, no record"),
                tags$td(style = "padding: 4px 8px; color: #721c24;", tags$b("Yes — counted in failed"))
              )
            )
          ),
          tags$br(),
          tags$b("Formula: "),
          tags$code("dfw_pct = (failed + late_dropped) ÷ (passed + failed + late_dropped) × 100")
        ),
        h4("DFW Means"),
        plotlyOutput("dfw_summary_plot", height = "400px"),
        h4("DFW Rates By Term"),
        plotlyOutput("dfw_by_term_plot", height = "400px"),
        h4("Grade Distribution Details"),
        DT::DTOutput("cr_grades_table"),
        hr(),
        h4("DFW by Term — Data Table"),
        uiOutput("cr_dfw_trend_ui"),
        hr(),
        h4("Instructor DFW vs. Course Average"),
        p("dfw_diff = instructor DFW rate minus course-wide average. Positive = above average.",
          style = "font-size: 0.85em; color: #666;"),
        uiOutput("cr_instructor_dfw_ui")
      )
    } else {
      # Show password gate
      fluidRow(
        column(12,
          create_password_gate_ui("cr_dfw_password", "cr_dfw_submit_btn")
        )
      )
    }
  }, error = function(e) {
    write_log("ERROR", "cr_dfw_tab_content",
              list(error = conditionMessage(e)), session$token)
    div(class = "alert alert-danger", style = "margin: 30px;",
      icon("circle-exclamation"), " ",
      "Error rendering DFW tab: ", conditionMessage(e))
  }) # end tryCatch
  }) # end renderUI cr_dfw_tab_content

  output$cr_dfw_trend_ui <- renderUI({
    outcomes <- course_report_data()$outcomes
    if (is.null(outcomes))
      return(p("Loading…", style = "color: #888;"))
    if (!is.null(outcomes$dfw_trend) && nrow(outcomes$dfw_trend) > 0)
      DT::DTOutput("cr_outcomes_dfw_trend")
    else
      p("No DFW trend data available for this course.", style = "color: #888;")
  })

  output$cr_instructor_dfw_ui <- renderUI({
    outcomes <- course_report_data()$outcomes
    if (is.null(outcomes))
      return(p("Loading…", style = "color: #888;"))
    if (!is.null(outcomes$instructor_dfw) && nrow(outcomes$instructor_dfw) > 0)
      DT::DTOutput("cr_outcomes_instructor_dfw")
    else
      p("No instructor comparison data available for this course.", style = "color: #888;")
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
                          opt = list(min_n = 5L, passing_grades = cr_ret_passing_grades()))
  })

  cr_ret_passing_grades <- reactive({
    threshold <- input$cr_ret_threshold %||% "below_c"
    if (identical(threshold, "f_only")) {
      c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "CR", "P", "S")
    } else {
      passing_grades   # A+ through C, CR — same as DFW tab "below_c" default
    }
  })

  output$cr_outcomes_persistence <- DT::renderDT({
    d <- cr_persistence_reactive()
    req(!is.null(d) && nrow(d) > 0)
    DT::datatable(d, rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
  })

  output$cr_outcomes_dfw_trend <- DT::renderDT({
    req(course_report_data())
    d <- course_report_data()$outcomes$dfw_trend
    req(!is.null(d) && nrow(d) > 0)
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) d <- d %>% filter(campus %in% campus_filter$values)
    DT::datatable(d, rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
  })

  output$cr_outcomes_instructor_dfw <- DT::renderDT({
    req(course_report_data())
    d <- course_report_data()$outcomes$instructor_dfw
    req(!is.null(d) && nrow(d) > 0)
    campus_filter <- get_campus_filter()
    if (!is.null(campus_filter)) d <- d %>% filter(campus %in% campus_filter$values)
    DT::datatable(d, rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
  })

  # ── Course Impact: Retention, Sequence, Instructor ───────────────────────────
  # These three tabs share the cr_course selector at the top of Course Dynamics
  # and run on-demand (separate run buttons per tab) because each is slow and
  # may not be relevant for every course the user looks up.

  # Shared helper: renders an SMD balance table with flagging
  .render_balance_table <- function(balance) {
    smd <- balance$smd_table
    if (is.null(smd) || nrow(smd) == 0) return(p("No balance data.", style = "color:#888;"))

    smd_display <- smd %>%
      dplyr::mutate(
        smd_fmt = dplyr::case_when(
          is.na(smd)  ~ "—",
          flagged     ~ paste0(smd, " \u26a0"),
          TRUE        ~ as.character(smd)
        )
      ) %>%
      dplyr::select(covariate, type, n_treatment, n_control,
                    value_treatment, value_control, unit, smd = smd_fmt)

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
              dplyr::rename_with(~ paste0(.x, " (%)"), -"value") %>%
              dplyr::arrange(dplyr::desc(dplyr::across(dplyr::ends_with("(%)"))))
            column(
              width = 4,
              div(
                style = "margin-bottom: 16px;",
                tags$strong(style = "font-size: 0.82em;", varname),
                DT::renderDT(
                  DT::datatable(df, rownames = FALSE,
                                options = list(dom = "t", pageLength = 20,
                                               columnDefs = list(
                                                 list(className = "dt-right",
                                                      targets = seq_len(ncol(df) - 1))
                                               )),
                                width = "100%"),
                  server = FALSE
                )
              )
            )
          })
        )
      )
    }

    tagList(
      if (any(smd$flagged, na.rm = TRUE))
        div(class = "alert alert-warning",
            style = "font-size: 0.85em;",
            icon("triangle-exclamation"), " ",
            "One or more covariates are imbalanced (|SMD| > 0.25). ",
            "Interpret outcome differences with caution — the groups may not be comparable on these dimensions.")
      else
        div(class = "alert alert-success", style = "font-size: 0.85em;",
            icon("circle-check"), " Groups appear well-balanced (all |SMD| \u2264 0.25)."),
      h6("Continuous & Binary Covariates", style = "color: #555;"),
      p(style = "font-size: 0.78em; color: #888; margin-bottom: 6px;",
        strong("value_treatment / value_control:"),
        " For ", strong("binary"), " covariates (first_gen, pell_eligible) these are the ",
        "percentage of students in each group with that characteristic — e.g., value_treatment = 38.2 ",
        "means 38.2% of treatment students are first-generation. For ", strong("continuous"),
        " covariates (inst_gpa, high_school_cum_gpa, etc.) these are the group means — ",
        "e.g., value_treatment = 3.21 means the average HS GPA for treatment students was 3.21.",
        br(),
        strong("SMD"), " (standardized mean difference) expresses the gap between groups in ",
        "units of the pooled standard deviation, so it's comparable across variables with ",
        "different scales. |SMD| < 0.10 is well-balanced; |SMD| > 0.25 (\u26a0) means the groups ",
        "differ enough on that dimension that it could confound your outcome comparison. ",
        "Example: SMD = 0.40 on HS GPA means treatment students averaged 0.4 standard deviations ",
        "higher GPA than controls — a meaningful difference that the analysis does not adjust for."),
      DT::renderDT(
        DT::datatable(smd_display, rownames = FALSE,
                      options = list(pageLength = 15, dom = "t")),
        server = FALSE
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

  cr_retention_data <- reactiveVal(NULL)

  output$cr_impact_retention_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(div(
        class = "alert alert-info", style = "margin: 30px;",
        icon("arrow-left"), " ",
        "Select a course and click ", tags$strong("Analyze Course"), " first, then open this tab."
      ))
    tagList(
      h4("Retention Over Time"),
      div(class = "alert alert-info", style = "font-size: 0.85em;",
        icon("circle-info"), " ",
        tags$strong("How retention is calculated."), " ",
        "Each row covers one term the course was offered. The cohort for that row is every
         student who was officially registered in this course that term (registration status
         codes that count as enrolled). The +1, +2 \u2026 columns show the share of that cohort
         still enrolled ", tags$em("anywhere"), " at UNM the given number of semesters later.",
        tags$br(), tags$br(),
        "A student is counted as retained if they are registered at UNM in the target term ",
        tags$strong("or"), " if they graduated at any point after the term they took this course.
         Graduates are not treated as stop-outs.",
        tags$br(), tags$br(),
        "Summer terms are skipped when counting semesters forward\u2014+1 means the next Fall
         or Spring, not the following Summer.",
        tags$br(), tags$br(),
        "Cells are left ", tags$strong("blank"), " (not 0%) when the target term is beyond the
         latest data available. A 0% for a recent cohort would be misleading\u2014those students
         have simply not yet had the chance to re-enroll."
      ),

      fluidRow(
        column(3,
          numericInput("cr_ret_n_terms", "Semesters to track:", value = 4, min = 1, max = 8)
        ),
        column(3,
          numericInput("cr_ret_min_n", "Min students per row:", value = 10, min = 1)
        ),
        column(4,
          div(style = "margin-top: 24px;",
            checkboxInput("cr_ret_by_instructor", "Break out by instructor", value = FALSE)
          )
        ),
        column(2,
          div(style = "margin-top: 20px;",
            actionButton("cr_ret_run", "Run", icon = icon("play"), class = "btn-primary")
          )
        )
      ),
      br(),
      uiOutput("cr_retention_results"),
      br(),
      hr(),
      h4("Next-Term Persistence by Grade Outcome"),
      p("Of students who received each grade outcome, what fraction enrolled again the following fall or spring?",
        style = "font-size: 0.85em; color: #666;"),
      div(style = "margin-bottom: 12px;",
        tags$strong("What counts as failing?"),
        tags$span(style = "font-size: 0.85em; color: #555; margin-left: 8px;",
          "Affects how grades are split between 'fail' and 'pass'."),
        radioButtons("cr_ret_threshold", label = NULL,
          choices = c(
            "Below C  (C−, D+, D, D− count as fail — use for courses requiring C or better)" = "below_c",
            "F grade only  (D grades count as passing — use for courses where D earns credit)" = "f_only"
          ),
          selected = input$cr_ret_threshold %||% "below_c",
          inline = FALSE
        )
      ),
      uiOutput("cr_persistence_ui")
    )
  })

  output$cr_persistence_ui <- renderUI({
    data <- course_report_data()
    if (is.null(data)) return(NULL)
    d <- tryCatch(cr_persistence_reactive(), error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0)
      return(p("Insufficient graded students to compute persistence (need 5+ per outcome).",
               style = "color: #888;"))
    DT::DTOutput("cr_outcomes_persistence")
  })

  cr_dept_retention_data    <- reactiveVal(NULL)
  cr_college_retention_data <- reactiveVal(NULL)

  observeEvent(input$cr_ret_run, {
    req(input$cr_course, nzchar(input$cr_course))
    cr_retention_data(NULL)
    cr_dept_retention_data(NULL)
    cr_college_retention_data(NULL)

    students  <- data_objects[["cedar_students"]]
    degrees   <- data_objects[["cedar_degrees"]]
    course    <- input$cr_course
    n_terms   <- as.integer(input$cr_ret_n_terms %||% 4L)
    min_n     <- as.integer(input$cr_ret_min_n   %||% 10L)

    opt <- list(
      course        = course,
      n_terms       = n_terms,
      min_n         = min_n,
      by_instructor = isTRUE(input$cr_ret_by_instructor)
    )

    notify_id <- "cr_ret_loading"
    showNotification("Computing retention trend\u2026", type = "warning",
                     duration = NULL, id = notify_id)
    on.exit(removeNotification(notify_id))

    tryCatch({
      result <- get_retention_trend(students, opt, degrees = degrees)
      cr_retention_data(result)

      # Derive dept, college, and course level from actual student rows for this
      # course. Level ("lower"/"upper"/"grad") ensures benchmarks only include
      # students in courses at the same level — comparing a 100-level course
      # against all dept students including grad cohorts would be misleading.
      course_meta <- students %>%
        filter(subject_course == course, !is.na(department)) %>%
        slice(1)

      dept_val    <- if (nrow(course_meta) > 0) course_meta$department[[1]] else NULL
      college_val <- if (nrow(course_meta) > 0) course_meta$college[[1]]    else NULL
      level_val   <- if (nrow(course_meta) > 0) course_meta$level[[1]]      else NULL
      # "unknown" means the course number pattern didn't match — don't filter on it.
      if (!is.null(level_val) && (is.na(level_val) || level_val == "unknown")) level_val <- NULL

      # Restrict benchmark to the same anchor terms as the course result so
      # the tables align row-for-row.
      anchor_terms <- if (!is.null(result) && nrow(result) > 0) result$term else NULL

      bench_opt <- list(n_terms = n_terms, min_n = 5L, terms = anchor_terms,
                        level = level_val)

      if (!is.null(dept_val) && nzchar(dept_val)) {
        dept_result <- tryCatch(
          get_dept_retention_trend(students, c(bench_opt, list(dept = dept_val)), degrees = degrees),
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
    if (nrow(result) == 0)
      return(div(class = "alert alert-warning",
                 "No terms met the minimum student threshold for this course."))
    tagList(
      DTOutput("cr_retention_table"),
      br(),
      uiOutput("cr_retention_benchmarks")
    )
  })

  output$cr_retention_table <- renderDT({
    result <- cr_retention_data()
    req(!is.null(result) && nrow(result) > 0)

    by_instructor <- isTRUE(input$cr_ret_by_instructor)
    n_terms       <- sum(startsWith(names(result), "ret_"))
    ret_cols      <- paste0("ret_", seq_len(n_terms))
    id_cols       <- c("term_label", if (by_instructor) "instructor_id", "n")
    disp_cols     <- c(id_cols, intersect(ret_cols, names(result)))
    display_df    <- result %>% select(all_of(disp_cols))
    col_names     <- c("Term", if (by_instructor) "Instructor", "Students",
                       paste0("+", seq_len(n_terms), " sem"))

    # rowCallback clears background on NA (null) retention cells —
    # styleInterval mis-colors them red because JS treats null <= 0.40 as true.
    ret_start_idx <- length(id_cols)      # 0-indexed column of first ret_ col
    n_ret_disp    <- length(intersect(ret_cols, names(display_df)))
    null_clear_cb <- JS(sprintf(
      "function(row, data) {
        for (var c = %d; c < %d; c++) {
          if (data[c] === null || data[c] === undefined) {
            $('td:eq(' + c + ')', row).css('background-color', '');
          }
        }
      }",
      ret_start_idx,
      ret_start_idx + n_ret_disp
    ))

    dt_obj <- datatable(
      display_df,
      rownames  = FALSE,
      selection = "none",
      options   = list(
        pageLength  = 20,
        rowCallback = null_clear_cb,
        columnDefs  = list(list(className = "dt-right",
                                targets   = seq(length(id_cols), length(disp_cols) - 1)))
      ),
      colnames = col_names
    ) %>%
      formatPercentage(intersect(ret_cols, names(display_df)), digits = 1)

    breaks  <- seq(0.40, 0.95, by = 0.05)
    palette <- colorRampPalette(c("#f44336", "#ff9800", "#8bc34a", "#4caf50"))(length(breaks) + 1)
    for (col in intersect(ret_cols, names(display_df))) {
      dt_obj <- dt_obj %>% formatStyle(col, backgroundColor = styleInterval(breaks, palette))
    }
    dt_obj
  }, server = FALSE)

  # ── Retention benchmark tables (dept / college) ───────────────────────────
  # Helper: render one benchmark DT given a data frame and a label.
  .render_benchmark_dt <- function(bmark, label, n_terms_course) {
    if (is.null(bmark) || nrow(bmark) == 0) return(NULL)

    n_terms   <- min(n_terms_course, sum(startsWith(names(bmark), "ret_")))
    ret_cols  <- paste0("ret_", seq_len(n_terms))
    id_cols   <- c("term_label", "n")
    disp_cols <- c(id_cols, intersect(ret_cols, names(bmark)))
    display_df <- bmark %>% select(all_of(disp_cols))
    col_names  <- c("Term", "Students", paste0("+", seq_len(n_terms), " sem"))

    ret_start_idx <- length(id_cols)
    n_ret_disp    <- length(intersect(ret_cols, names(display_df)))
    null_clear_cb <- JS(sprintf(
      "function(row, data) {
        for (var c = %d; c < %d; c++) {
          if (data[c] === null || data[c] === undefined) {
            $('td:eq(' + c + ')', row).css('background-color', '');
          }
        }
      }",
      ret_start_idx,
      ret_start_idx + n_ret_disp
    ))

    dt_obj <- datatable(
      display_df,
      caption   = tags$caption(style = "caption-side: top; font-weight: bold; font-size: 0.9em;",
                                label),
      rownames  = FALSE,
      selection = "none",
      options   = list(
        pageLength  = 20,
        dom         = "t",          # table only — no search/length controls
        rowCallback = null_clear_cb,
        columnDefs  = list(list(className = "dt-right",
                                targets   = seq(length(id_cols), length(disp_cols) - 1)))
      ),
      colnames = col_names
    ) %>%
      formatPercentage(intersect(ret_cols, names(display_df)), digits = 1)

    breaks  <- seq(0.40, 0.95, by = 0.05)
    palette <- colorRampPalette(c("#f44336", "#ff9800", "#8bc34a", "#4caf50"))(length(breaks) + 1)
    for (col in intersect(ret_cols, names(display_df))) {
      dt_obj <- dt_obj %>% formatStyle(col, backgroundColor = styleInterval(breaks, palette))
    }
    dt_obj
  }

  output$cr_retention_benchmarks <- renderUI({
    course_result  <- cr_retention_data()
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
        h5(paste0("Department Average \u2014 ", dept_code),
           style = "margin-top: 1em; color: #555;"),
        p(paste0("Retention for all students registered in any ", level_phrase,
                 dept_code, " course that term."),
          style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"),
        DTOutput("cr_retention_dept_table")
      ))
    }

    if (!is.null(college_result) && nrow(college_result) > 0) {
      items <- c(items, list(
        h5(paste0("College Average \u2014 ", college_code),
           style = "margin-top: 1.5em; color: #555;"),
        p(paste0("Retention for all students registered in any ", level_phrase,
                 "course in the ", college_code, " college that term."),
          style = "font-size: 0.85em; color: #777; margin-bottom: 6px;"),
        DTOutput("cr_retention_college_table")
      ))
    }

    if (length(items) == 0) return(NULL)
    div(
      div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 1em;",
        icon("circle-info"), " ",
        tags$strong("Benchmark context."), " ",
        paste0("These tables show retention rates for other ", level_phrase,
               "courses in the same department and college, using the same terms and
                calculation method. Restricting to the same course level makes the
                comparison meaningful \u2014 lower-division and graduate cohorts have
                very different retention patterns. Use these figures to judge whether
                this course\u2019s trend is distinctive or mirrors the broader pattern.")
      ),
      tagList(items)
    )
  })

  output$cr_retention_dept_table <- renderDT({
    bmark <- cr_dept_retention_data()
    course_result <- cr_retention_data()
    req(!is.null(bmark), !is.null(course_result))
    n_terms_course <- sum(startsWith(names(course_result), "ret_"))
    .render_benchmark_dt(bmark, "Department average", n_terms_course)
  }, server = FALSE)

  output$cr_retention_college_table <- renderDT({
    bmark <- cr_college_retention_data()
    course_result <- cr_retention_data()
    req(!is.null(bmark), !is.null(course_result))
    n_terms_course <- sum(startsWith(names(course_result), "ret_"))
    .render_benchmark_dt(bmark, "College average", n_terms_course)
  }, server = FALSE)

  # ── Sequence Effect tab ─────────────────────────────────────────────────────
  cr_impact_sequence_data <- reactiveVal(NULL)

  output$cr_impact_sequence_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(div(
        class = "alert alert-info", style = "margin: 30px;",
        icon("arrow-left"), " ",
        "Select a course and click ", tags$strong("Analyze Course"), " first, then open this tab."
      ))
    tagList(
      h4("Course Sequence Effect"),
      p(paste0("Compares grades in a downstream course (Y) between students who ",
               "passed ", course, " first versus students who took Y without prior ", course, "."),
        style = "font-size: 0.88em; color: #555;"),
      fluidRow(
        column(4,
          selectizeInput("cr_impact_seq_course_y", "Downstream course (Y):",
                         choices = sort(unique(cedar_sections$subject_course)),
                         options = list(placeholder = "Type to search...", maxOptions = 20))
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
          students   = data_objects[["cedar_students"]],
          programs   = data_objects[["cedar_programs"]],
          applicants = data_objects[["cedar_applicants"]],
          opt        = opt
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
      div(
        class = "alert alert-info", style = "font-size: 0.85em;",
        tags$b("Who is being counted:"), br(),
        tags$ul(style = "margin-bottom: 0;",
          tags$li(
            strong("Treatment"), paste0(" (\u201cpassed ", result$course_x, " first\u201d): "),
            "Students who (1) registered for and ", strong("passed"), paste0(" ", result$course_x),
            " at any point, and (2) later took ", result$course_y, " in a subsequent term. ",
            "Any gap between the two courses qualifies — consecutive or not. ",
            paste0(result$n_took_x_before_y, " students met this definition across "),
            fmt_term(result$term_range_x[1]), "\u2013", fmt_term(result$term_range_x[2]), ". ",
            if (result$n_dropped_by_programs > 0)
              paste0(result$n_dropped_by_programs,
                     " were dropped for missing program records, leaving ",
                     result$n_treatment, " in the final comparison.")
            else
              paste0("All ", result$n_treatment, " appear in the final comparison.")
          ),
          tags$li(
            strong("Control"), paste0(" (\u201ctook ", result$course_y, " without prior ",
                                      result$course_x, "\u201d): "),
            paste0("Students who took ", result$course_y, " but had no prior passing record in ",
                   result$course_x, ". "),
            paste0(result$n_took_y_without_x, " students across "),
            fmt_term(result$term_range_y[1]), "\u2013", fmt_term(result$term_range_y[2]),
            paste0("; ", result$n_control, " in final comparison after program matching.")
          )
        )
      ),
      fluidRow(
        column(6,
          h5(paste0("Grade Outcomes in ", result$course_y)),
          DT::renderDT(DT::datatable(result$outcomes, rownames = FALSE,
                                     options = list(dom = "t")), server = FALSE)
        ),
        column(6,
          h5("Group Profile"),
          p(style = "font-size: 0.78em; color: #888; margin-bottom: 4px;",
            strong("mean_inst_gpa"), " and ", strong("mean_credits_earned"),
            " are measured at the term each student took course X (treatment) ",
            "or course Y (control) — not at their entry term. This gives a snapshot ",
            "of academic standing at the point of comparison, not years earlier. ",
            strong("mean_hs_gpa"), " and ", strong("mean_act"),
            " are fixed pre-enrollment values from admissions records."),
          DT::renderDT(DT::datatable(result$group_profile, rownames = FALSE,
                                     options = list(dom = "t")), server = FALSE)
        )
      ),
      hr(),
      h5("Covariate Balance"),
      p(style = "font-size: 0.8em; color: #666;",
        "Large imbalances suggest the two groups were different kinds of students ",
        "before taking either course — interpret grade differences cautiously. ",
        "Use the HS GPA band inputs above to restrict to comparable students."),
      .render_balance_table(result$balance)
    )
  })

  # ── Instructor Prep tab ─────────────────────────────────────────────────────
  cr_impact_instructor_data <- reactiveVal(NULL)

  output$cr_impact_instructor_ui <- renderUI({
    course <- input$cr_course
    if (is.null(course) || !nzchar(course))
      return(div(
        class = "alert alert-info", style = "margin: 30px;",
        icon("arrow-left"), " ",
        "Select a course and click ", tags$strong("Analyze Course"), " first, then open this tab."
      ))
    tagList(
      h4("Instructor Preparation Effect"),
      p(paste0("Among students who took ", course, " and later took a downstream course, ",
               "compares their downstream grades by which instructor taught them in ", course, ". ",
               "The balance table reveals whether sections self-selected different kinds of students."),
        style = "font-size: 0.88em; color: #555;"),
      div(class = "alert alert-info", style = "font-size: 0.82em;",
          icon("circle-info"), " ",
          "Section self-selection is the primary confounder here. Students often choose instructors
           based on schedule, reputation, or prior experience. Check the balance table before
           drawing conclusions about instructor effectiveness."),
      fluidRow(
        column(4,
          selectizeInput("cr_impact_inst_course_y", "Downstream course (Y):",
                         choices = sort(unique(cedar_sections$subject_course)),
                         options = list(placeholder = "Type to search...", maxOptions = 20))
        ),
        column(2,
          numericInput("cr_impact_inst_min_n", "Min students per instructor:", value = 15, min = 5, max = 100)
        ),
        column(3,
          br(),
          actionButton("cr_impact_inst_run", "Compare Instructors",
                       icon = icon("play"), class = "btn-primary")
        )
      ),
      uiOutput("cr_impact_instructor_results")
    )
  })

  observeEvent(input$cr_impact_inst_run, {
    req(input$cr_course, nzchar(input$cr_course),
        input$cr_impact_inst_course_y, nzchar(input$cr_impact_inst_course_y))
    cr_impact_instructor_data(NULL)

    opt <- list(
      course_x = input$cr_course,
      course_y = input$cr_impact_inst_course_y,
      min_n    = as.integer(input$cr_impact_inst_min_n %||% 15L),
      campus   = if (length(input$cr_campus) > 0) input$cr_campus else NULL
    )

    withProgress(message = "Comparing instructors...", value = 0.3, {
      tryCatch({
        result <- get_instructor_effect(
          students   = data_objects[["cedar_students"]],
          programs   = data_objects[["cedar_programs"]],
          applicants = data_objects[["cedar_applicants"]],
          opt        = opt
        )
        cr_impact_instructor_data(result)
        setProgress(1)
      }, error = function(e) {
        showNotification(paste("Instructor analysis failed:", conditionMessage(e)),
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

    x_period <- paste0(fmt_term(result$term_range_x[1]), "\u2013", fmt_term(result$term_range_x[2]))
    y_period <- paste0(fmt_term(result$term_range_y[1]), "\u2013", fmt_term(result$term_range_y[2]))

    tagList(
      div(
        class = "alert alert-info", style = "font-size: 0.85em;",
        tags$b(paste0("How to read this table — ",
                      result$course_x, " \u2192 ", result$course_y)), br(), br(),
        tags$b("What the analysis does:"), " For each instructor who taught ",
        strong(result$course_x), " (", x_period, "), this shows how their students ",
        "performed later when those students took ", strong(result$course_y),
        " (", y_period, "). Any gap between the two courses counts — it does not have ",
        "to be the immediately following term.", br(), br(),
        tags$b("Column definitions:"), br(),
        tags$ul(style = "margin-bottom: 4px;",
          tags$li(strong("n_total_in_x"), " — total students this instructor has taught in ",
                  result$course_x, " across the whole data period, regardless of whether ",
                  "those students went on to take ", result$course_y, "."),
          tags$li(strong("n_took_y"), " — students taught by this instructor in ",
                  result$course_x, " who later enrolled in ", result$course_y,
                  " in a subsequent term. This is the \u201cpipeline\u201d count."),
          tags$li(strong("pct_took_y"), " — n_took_y ÷ n_total_in_x: share of this instructor's students who continued to ",
                  result$course_y, ". Course-wide average: ",
                  strong(paste0(round(100 * sum(result$outcomes$n_took_y) /
                                      sum(result$outcomes$n_total_in_x), 1), "%")),
                  ". Wide variation usually reflects section composition (time-of-day, major vs. requirement-filler mix) ",
                  "rather than instructor influence — treat outliers as a prompt to investigate, not a verdict."),
          tags$li(strong("n_pass / pct_pass"), " — students with a passing grade ",
                  "(C\u2212 or better, CR, P, S) in ", result$course_y, "."),
          tags$li(strong("n_failed / pct_failed"), " — stayed registered to end of term but earned a non-passing grade ",
                  "(D, F, W, I, NR, NC, or similar) in ", result$course_y, "."),
          tags$li(strong("n_dropped / pct_dropped"), " — late drop (DG or DW registration status) in ", result$course_y, "."),
          tags$li(strong("pct_dfw"), " — (n_failed + n_dropped) \u00f7 n_took_y. ",
                  "pct_pass + pct_failed + pct_dropped = 100%.")
        ),
        tags$b("Example:"), " An instructor with n_took_y\u202f=\u202f87, pct_pass\u202f=\u202f68%, ",
        "pct_failed\u202f=\u202f22%, pct_dropped\u202f=\u202f10% has a DFW rate of 32% for students who later took ",
        result$course_y, "."
      ),

      h5(paste0("Downstream Outcomes in ", result$course_y,
                " by Instructor in ", result$course_x)),
      div(class = "alert alert-warning", style = "font-size: 0.88em; margin-bottom: 10px;",
        icon("lightbulb"), " ",
        tags$strong("Course-wide averages for context:"), tags$br(),
        tags$b("Continuation rate"), " (% of ", result$course_x, " students who took ",
        result$course_y, "): ",
        tags$span(style = "font-size: 1.1em;",
          strong(paste0(round(100 * sum(result$outcomes$n_took_y) /
                              sum(result$outcomes$n_total_in_x), 1), "%"))), tags$br(),
        tags$b("DFW rate in ", result$course_y), " (across all instructors): ",
        tags$span(style = "font-size: 1.1em;",
          strong(paste0(round(100 * (sum(result$outcomes$n_failed) + sum(result$outcomes$n_dropped)) /
                              sum(result$outcomes$n_took_y), 1), "%"))),
        tags$br(),
        tags$span(style = "color: #856404; font-size: 0.85em;",
          "Compare each instructor's pct_took_y and pct_dfw against these baselines. ",
          "Large departures are worth investigating but may reflect section composition, not instructor effect.")
      ),
      DT::renderDT(
        DT::datatable(result$outcomes, rownames = FALSE,
                      options = list(pageLength = 25, dom = "tip")),
        server = FALSE
      ),

    )
  })

  # Debug outputs for course report
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
  seatfinderServer("seatfinder", cedar_students, cedar_sections, cedar_faculty)

  # ===========================================================================
  # Waitlists tab (Shiny module)
  # ===========================================================================
  waitlistServer("waitlist", cedar_students, session)

  ####################
  ##### REGSTATS #####
  ####################

  # Reactive value to store regstats data
  regstats_data    <- reactiveVal(NULL)
  signals_data     <- reactiveVal(NULL)
  rs_selected_tab  <- reactiveVal(NULL)  # remembers active tab across regenerations

  observeEvent(input$rs_tabs, {
    rs_selected_tab(input$rs_tabs)
  }, ignoreInit = TRUE, ignoreNULL = TRUE)
  
  # Load pre-generated regstats data on app startup (if available)
  # tryCatch({
  #   preloaded_file <- file.path("data", "regstats", "regstats_AS_202580_lower.Rds")
  #   if (file.exists(preloaded_file)) {
  #     preloaded_data <- readRDS(preloaded_file)
      
  #     # Debug the structure of preloaded data
  #     message("[server.R] Preloaded data structure:")
  #     message("[server.R] - names: ", paste(names(preloaded_data), collapse=", "))
  #     message("[server.R] - class: ", class(preloaded_data))
      
  #     # Check if it has the expected structure
  #     if ("flagged" %in% names(preloaded_data)) {
  #       message("[server.R] - flagged exists with names: ", paste(names(preloaded_data$flagged), collapse=", "))

  #       # Check if cache_info has opt_params and use them
  #       if ("cache_info" %in% names(preloaded_data) && 
  #           "opt_params" %in% names(preloaded_data$cache_info)) {
  #         message("[server.R] - Using opt_params from cache_info")
  #         preloaded_data$opt <- preloaded_data$cache_info$opt_params
  #       } else if (is.null(preloaded_data$opt)) {
  #         # Fallback if no opt exists
  #         message("[server.R] - No opt or cache_info$opt_params found, using defaults")
  #         preloaded_data$opt <- list(
  #           preloaded = TRUE,
  #           thresholds = cedar_regstats_thresholds
  #         )
  #       }
  #     } else if (is.list(preloaded_data) && "bumps" %in% names(preloaded_data)) {
  #       # If the file contains just the flagged data directly, wrap it properly
  #       message("[server.R] - Wrapping direct flagged data in proper structure")
  #       preloaded_data <- list(
  #         flagged = preloaded_data,
  #         opt = list(preloaded = TRUE, thresholds = cedar_regstats_thresholds),
  #         generated_at = file.mtime(preloaded_file)
  #       )
  #     }
      
  #     regstats_data(preloaded_data)
  #     message("[server.R] Loaded pre-generated regstats data from ", preloaded_file)
      
  #     # Force UI refresh by invalidating outputs
  #     session$sendCustomMessage("regstats_preloaded", TRUE)
      
  #     # Show notification to users that data is pre-loaded
  #     if (!is.null(preloaded_data$generated_at)) {
  #       showNotification(
  #         paste("Dashboard pre-loaded with regstats data from", 
  #               format(preloaded_data$generated_at, "%Y-%m-%d %H:%M")),
  #         type = "message",
  #         duration = 5
  #       )
  #     } else {
  #       showNotification("Dashboard pre-loaded with regstats data", type = "message", duration = 5)
  #     }
  #   }
  #   else {
  #     message("[server.R] No pre-generated regstats data found at ", preloaded_file)
  #   }
  # }, error = function(e) {
  #   handle_error(e, "regstats_preload")
  # }) # end tryCatch for preloading regstats data
  

  # REGSTATS DASHBOARD generation
  observeEvent(input$rs_dashboard_button, {
    
    # Log regstats dashboard generation
    log_report_generation(session, "regstats_dashboard", list(
      campus = input$rs_campus,
      college = input$rs_college,
      dept = input$rs_dept,
      term = input$rs_term,
      thresholds = list(
        min_impacted = input$rs_min_impacted,
        min_wait = input$rs_min_wait,
        pct_sd = input$rs_pct_sd,
        chronic_fill_rate = input$rs_chronic_fill_rate
      )
    ))

    # Build options from inputs
    opt <- list()
    opt[["shiny"]] <- TRUE
    opt[["course_campus"]] <- input$rs_campus
    opt[["course_college"]] <- input$rs_college
    opt[["dept"]] <- input$rs_dept
    opt[["term"]] <- input$rs_term
    opt[["pt"]] <- input$rs_pt
    opt[["im"]] <- input$rs_im
    opt[["level"]] <- input$rs_level
    opt[["course"]] <- input$rs_course
    if (is.null(opt[["course"]]) || opt[["course"]] == "") {
      opt[["course"]] <- NULL
    }

    # Initialize thresholds list
    opt[["thresholds"]] <- list()
    opt[["thresholds"]][["min_impacted"]] <- input$rs_min_impacted
    opt[["thresholds"]][["min_wait"]] <-  input$rs_min_wait
    opt[["thresholds"]][["pct_sd"]] <- input$rs_pct_sd
    opt[["thresholds"]][["chronic_fill_rate"]] <- input$rs_chronic_fill_rate
    
    # Show loading notification with average time
    status_message <- create_timing_status_message("regstats_dashboard", "Generating regstats")
    showNotification(status_message, type = "message", duration = NULL, id = "regstats_loading")

    # Start timing
    timer <- start_report_timer("regstats_dashboard", list(
      campus = input$rs_campus,
      college = input$rs_college, 
      term = input$rs_term
    ))
  
    tryCatch({
      # Get regstats data (without generating report)
      result <- get_reg_stats(cedar_students, cedar_sections, opt)

      # End timing and log
      duration_sec <- end_report_timer(timer)

      # Store the data in reactive values; signals are loaded on demand via button
      signals_data(NULL)
      regstats_data(list(
        flagged = result,
        opt = opt,
        generated_at = Sys.time()
      ))

      removeNotification("regstats_loading")
      showNotification(paste0("Registration statistics ready (", round(duration_sec, 1), "s)"),
                      type = "message", duration = 5)
    }, error = function(e) {
      handle_error(e, "regstats_dashboard", "regstats_loading")
    })
  }, ignoreInit = TRUE) # end observeEvent for rs_dashboard_button

  # Regenerate: same as dashboard button but bypasses the cache
  observeEvent(input$rs_regenerate, {
    opt <- list()
    opt[["shiny"]] <- TRUE
    opt[["bypass_cache"]] <- TRUE
    opt[["course_campus"]] <- input$rs_campus
    opt[["course_college"]] <- input$rs_college
    opt[["dept"]] <- input$rs_dept
    opt[["term"]] <- input$rs_term
    opt[["pt"]] <- input$rs_pt
    opt[["im"]] <- input$rs_im
    opt[["level"]] <- input$rs_level
    opt[["course"]] <- input$rs_course
    if (is.null(opt[["course"]]) || opt[["course"]] == "") opt[["course"]] <- NULL
    opt[["thresholds"]] <- list(
      min_impacted      = input$rs_min_impacted,
      min_wait          = input$rs_min_wait,
      pct_sd            = input$rs_pct_sd,
      chronic_fill_rate = input$rs_chronic_fill_rate
    )

    showNotification("Regenerating regstats (bypassing cache)...",
                     type = "message", duration = NULL, id = "regstats_loading")
    tryCatch({
      result  <- get_reg_stats(cedar_students, cedar_sections, opt)
      signals_data(NULL)
      regstats_data(list(flagged = result, opt = opt, generated_at = Sys.time()))
      removeNotification("regstats_loading")
      showNotification("Regstats regenerated.", type = "message", duration = 4)
    }, error = function(e) {
      handle_error(e, "regstats_regenerate", "regstats_loading")
    })
  }, ignoreInit = TRUE) # end observeEvent for rs_regenerate

  # Load downstream signals on demand (slow — separate button on the tab)
  observeEvent(input$rs_load_signals, {
    data <- regstats_data()
    if (is.null(data)) return()
    showNotification("Computing downstream concerns...", type = "message", duration = NULL, id = "signals_loading")
    tryCatch({
      signals_result <- get_next_term_signals(data$flagged, cedar_students)

      # Filter dest_courses to only those offered at the selected campus(es).
      # cedar_course_flows has no campus column, so bump dest_courses are
      # unfiltered by default; cross-reference cedar_sections to fix that.
      campus_filter <- data$opt$course_campus
      log_data_filter(session, "downstream_campus_filter",
                      paste0("[", paste(campus_filter, collapse = ","), "] rows_before=",
                             nrow(signals_result$downstream)))
      if (!is.null(campus_filter) && length(campus_filter) > 0 &&
          !is.null(signals_result$downstream) && nrow(signals_result$downstream) > 0) {
        campus_courses <- cedar_sections %>%
          filter(campus %in% campus_filter) %>%
          pull(subject_course) %>%
          unique()
        signals_result$downstream <- signals_result$downstream %>%
          filter(dest_course %in% campus_courses)
        log_data_filter(session, "downstream_campus_filter",
                        paste0("campus_courses=", length(campus_courses),
                               " rows_after=", nrow(signals_result$downstream)))
      }

      signals_data(signals_result)
      removeNotification("signals_loading")
      updateTabsetPanel(session, "rs_tabs", selected = "Downstream Concerns")
    }, error = function(e) {
      removeNotification("signals_loading")
      handle_error(e, "rs_load_signals", "signals_loading")
    })
  }, ignoreInit = TRUE)

  # Download report handler
  output$rs_report_download <- downloadHandler(
    filename = function() {
      paste0("regstats-report-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".html")
    },
    content = function(file) {
      # Build options from inputs
      opt <- list()
      opt[["shiny"]] <- TRUE
      opt[["course_campus"]] <- input$rs_campus
      opt[["course_college"]] <- input$rs_college
      opt[["dept"]] <- input$rs_dept
      opt[["term"]] <- input$rs_term
      opt[["pt"]] <- input$rs_pt
      opt[["im"]] <- input$rs_im
      opt[["level"]] <- input$rs_level
      opt[["course"]] <- input$rs_course
      if (is.null(opt[["course"]]) || opt[["course"]] == "") {
        opt[["course"]] <- NULL
      }

      # Initialize thresholds list
      opt[["thresholds"]] <- list()
      opt[["thresholds"]][["min_impacted"]] <- input$rs_min_impacted
      opt[["thresholds"]][["min_wait"]] <-  input$rs_min_wait
      opt[["thresholds"]][["pct_sd"]] <- input$rs_pct_sd
      opt[["thresholds"]][["chronic_fill_rate"]] <- input$rs_chronic_fill_rate
      
      # Show loading notification with average time
      status_message <- create_timing_status_message("regstats_report", "Generating regstats")
      showNotification(status_message, type = "message", duration = NULL, id = "regstats_report_loading")
      
      # Start timing
      timer <- start_report_timer("regstats_report", list(
        campus = input$rs_campus,
        college = input$rs_college,
        term = input$rs_term
      ))
      
      tryCatch({
        # Generate the full RMarkdown report
        create_regstat_report(cedar_students, cedar_sections, opt)
        
        # End timing and log
        duration_sec <- end_report_timer(timer)
        
        # Copy the generated report to download location
        report_path <- file.path(getwd(), "www", "output.html")
        if (file.exists(report_path)) {
          file.copy(report_path, file, overwrite = TRUE)
        } else {
          stop("Report file was not generated")
        }
        
        removeNotification("regstats_report_loading")
        showNotification(paste("Regstats report downloaded! (", round(duration_sec, 1), "s)"), 
                        type = "message", duration = 5)
      }, error = function(e) {
        handle_error(e, "regstats_report", "regstats_report_loading")
      })
    }
  ) # end downloadHandler
  
  # Render regstats dashboard
  output$rs_dashboard <- renderUI({
    data    <- regstats_data()
    signals <- signals_data()
    cedar_debug("[server.R] rs_dashboard renderUI called. Data is null: ", is.null(data))

    if (is.null(data)) {
      return(div(
        class = "alert alert-info", style = "margin: 30px;",
        icon("chart-line"), " ",
        "Set your filters and click ", tags$strong("Generate Dashboard"),
        " to view registration anomalies for the selected term.",
        tags$br(), tags$br(),
        tags$small(
          "Registration statistics flag courses with unusual enrollment bumps, high waitlists,
           near-capacity squeezes, or elevated drop rates — compared against each course's own
           historical pattern. Use this to identify where demand is outpacing supply before
           the end of registration."
        )
      ))
    }
    
    cedar_debug("[server.R] Rendering dashboard with data. Names: ", paste(names(data), collapse=", "))
    flagged <- data$flagged

    thresholds <- if (is.null(data$opt$thresholds)) {
      cedar_debug("[server.R] No data$opt$thresholds, using cedar_regstats_thresholds.")
      cedar_regstats_thresholds
    } else {
      data$opt$thresholds
    }

    # Category counts for summary tab
    bumps_count       <- if ("bumps"       %in% names(flagged)) nrow(flagged$bumps)       else 0
    waits_count       <- if ("waits"       %in% names(flagged)) nrow(flagged$waits)       else 0
    emerging_sat_count <- if ("emerging_sat" %in% names(flagged)) nrow(flagged$emerging_sat) else 0
    chronic_sat_count  <- if ("chronic_sat"  %in% names(flagged)) nrow(flagged$chronic_sat)  else 0
    early_drops_count <- if ("early_drops" %in% names(flagged)) nrow(flagged$early_drops) else 0
    late_drops_count  <- if ("late_drops"  %in% names(flagged)) nrow(flagged$late_drops)  else 0

    # Downstream signals — optionally filtered to dest courses in selected dept
    downstream_df <- filter_downstream_by_dept(
      if (!is.null(signals$downstream)) signals$downstream else tibble(),
      data$opt$dept,
      cedar_sections
    )
    downstream_count <- nrow(downstream_df)
    downstream_scope_note <- if (length(data$opt$dept) > 0)
      paste0("Showing destinations within ", paste(data$opt$dept, collapse = ", "), ". Run without a dept filter to see all.")
    else
      "Showing all destination courses. Select a dept to narrow to a specific unit."


    # Scope labels for summary
    scope_campus  <- if (length(data$opt$course_campus)  == 0) "All" else paste(data$opt$course_campus,  collapse = ", ")
    scope_college <- if (length(data$opt$course_college) == 0) "All" else paste(data$opt$course_college, collapse = ", ")
    scope_dept    <- if (length(data$opt$dept)           == 0) "All" else paste(data$opt$dept,           collapse = ", ")
    scope_term    <- if (length(data$opt$term)           == 0) "All" else paste(data$opt$term,           collapse = ", ")

    # Data age — use cache_info$generated_at (file mtime for cache hits, Sys.time() for fresh runs)
    data_as_of <- flagged$cache_info$generated_at %||% data$generated_at
    data_age_hours <- as.numeric(difftime(Sys.time(), data_as_of, units = "hours"))
    age_label <- format(data_as_of, "%b %d, %Y %H:%M")
    age_class <- if (data_age_hours < 24) "rs-age-fresh" else if (data_age_hours < 168) "rs-age-warn" else "rs-age-stale"

    tagList(
      fluidRow(
        column(12,
          card(
            card_body(class = "rs-summary-bar",
              div(class = "rs-summary-scope",
                tags$span(class = "text-hint", "Scope: "),
                tags$span(scope_campus, class = "rs-scope-val"), " \u00b7 ",
                tags$span(scope_college, class = "rs-scope-val"), " \u00b7 ",
                tags$span(scope_dept, class = "rs-scope-val"), " \u00b7 ",
                tags$span(scope_term, class = "rs-scope-val")
              ),
              div(class = "text-note",
                paste0("Thresholds \u2014 min impacted: ", thresholds$min_impacted,
                       " \u00b7 min SDs: ", thresholds$pct_sd,
                       " \u00b7 chronic fill rate: ", thresholds$chronic_fill_rate,
                       " \u00b7 min wait: ", thresholds$min_wait)
              ),
              div(class = "rs-summary-counts",
                tags$span(class = "rs-count-item rs-count-bump",
                  tags$strong(bumps_count), " bumps"),
                tags$span(class = "rs-count-sep", "\u00b7"),
                tags$span(class = "rs-count-item rs-count-wait",
                  tags$strong(waits_count), " waitlists"),
                tags$span(class = "rs-count-sep", "\u00b7"),
                tags$span(class = "rs-count-item rs-count-squeeze",
                  tags$strong(emerging_sat_count), " emerging saturation"),
                tags$span(class = "rs-count-sep", "·"),
                tags$span(class = "rs-count-item rs-count-squeeze",
                  tags$strong(chronic_sat_count), " chronic saturation"),
                tags$span(class = "rs-count-sep", "\u00b7"),
                tags$span(class = "rs-count-item rs-count-drop",
                  tags$strong(early_drops_count), " early drop anomalies"),
                tags$span(class = "rs-count-sep", "\u00b7"),
                tags$span(class = "rs-count-item rs-count-drop",
                  tags$strong(late_drops_count), " late drop anomalies")
              ),
              div(class = "rs-summary-footer",
                tags$span(class = paste("rs-data-age", age_class),
                  paste0("Stats compiled ", age_label)),
                tags$span(class = "rs-count-sep", "\u00b7"),
                actionLink("rs_regenerate", "Regenerate", class = "rs-regenerate-link")
              )
            )
          )
        )
      ), # end summary row

      fluidRow(
        column(12,
          tabsetPanel(
            id = "rs_tabs",
            selected = rs_selected_tab(),
            tabPanel("Enrollment Bumps",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("Enrollment bumps"), " — courses with higher registration than their historical average for the same term type (fall vs. fall, etc.). ",
                tags$strong("Column calculations: "),
                tags$em("registered_mean"), " = mean enrollment across prior terms of the same type, excluding the current term. ",
                tags$em("SDs from mean"), " = (registered − registered_mean) ÷ pop_sd. ",
                tags$em("impacted"), " = (registered − registered_mean) − (Min SDs × pop_sd): students above the mean beyond what normal variance explains. ",
                tags$strong("Filtering: "),
                tags$em("Min SDs"), " filters rows by SDs from mean. ",
                tags$em("Min Impacted"), " filters by the raw difference (registered − registered_mean), independent of Min SDs. Both only control which rows are shown."),
              if (bumps_count > 0) DT::DTOutput("rs_bumps_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No enrollment bumps found with the current filters and thresholds.")
            ),
            tabPanel("High Waitlists",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("High waitlists"), " flag courses where the waitlist count exceeds the
                minimum threshold. A large waitlist indicates demand that the current number of seats
                cannot meet — consider opening an additional section or increasing capacity."),
              if (waits_count > 0) DT::DTOutput("rs_waits_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No high waitlist courses found with the current filters.")
            ),
            tabPanel("Emerging Saturation",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("Emerging saturation"), " — courses whose current fill rate is significantly
                above their own historical average for the same term type. Flagged when the fill rate
                deviation exceeds the Min SDs threshold. A course appearing here is filling faster than
                its own norm, which may indicate growing demand before capacity has been adjusted. ",
                tags$em("fill_rate"), " = enrolled ÷ (enrolled + available seats). ",
                tags$em("sd_above_mean"), " = SDs above the course's historical mean fill rate."),
              if (emerging_sat_count > 0) DT::DTOutput("rs_emerging_sat_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No emerging saturation found with the current filters.")
            ),
            tabPanel("Chronic Saturation",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("Chronic saturation"), " — courses that have run above the chronic fill rate
                threshold for 3 or more past same-type terms and are above that threshold now. These
                courses have never had meaningful slack; low attrition rates here are the strongest
                available signal of sustained unmet demand. Consider adding a section or raising capacity."),
              if (chronic_sat_count > 0) DT::DTOutput("rs_chronic_sat_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No chronic saturation found with the current filters.")
            ),
            tabPanel("Early Drops",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("Early drops"), " (pre-census DR) — courses with more withdrawals before the census date than their historical average. No academic penalty for the student, so high rates often reflect scheduling conflicts or prereq mismatches. ",
                tags$strong("Column calculations: "),
                tags$em("dr_early_mean"), " = mean early drops across prior terms of the same type. ",
                tags$em("SDs from mean"), " = (drop_early − dr_early_mean) ÷ pop_sd. ",
                tags$em("impacted"), " = (drop_early − dr_early_mean) − (Min SDs × pop_sd): extra drops beyond what normal variance explains. ",
                tags$strong("Filtering: "),
                tags$em("Min SDs"), " filters rows by SDs from mean. ",
                tags$em("Min Impacted"), " filters by the raw difference (drop_early − dr_early_mean), independent of Min SDs. Both only control which rows are shown."),
              if (early_drops_count > 0) DT::DTOutput("rs_early_drops_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No early drop anomalies found with the current filters.")
            ),
            tabPanel("Late Drops",
              div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                icon("circle-info"), " ",
                tags$strong("Late drops"), " (DW/DG) — courses with more post-census withdrawals than their historical average. These appear on transcripts and may affect financial aid, making them a stronger signal of course difficulty or student support gaps than early drops. ",
                tags$strong("Column calculations: "),
                tags$em("dr_late_mean"), " = mean late drops across prior terms of the same type. ",
                tags$em("SDs from mean"), " = (drop_late − dr_late_mean) ÷ pop_sd. ",
                tags$em("impacted"), " = (drop_late − dr_late_mean) − (Min SDs × pop_sd): extra drops beyond what normal variance explains. ",
                tags$strong("Filtering: "),
                tags$em("Min SDs"), " filters rows by SDs from mean. ",
                tags$em("Min Impacted"), " filters by the raw difference (drop_late − dr_late_mean), independent of Min SDs. Both only control which rows are shown."),
              if (late_drops_count > 0) DT::DTOutput("rs_late_drops_table")
              else div(class = "alert alert-info", style = "margin-top: 8px;",
                icon("circle-check"), " No late drop anomalies found with the current filters.")
            ),
            tabPanel("Downstream Concerns",
              if (is.null(signals)) {
                div(style = "margin: 24px 0;",
                  tags$p(class = "text-muted-sm",
                    "Downstream analysis requires scanning the full enrollment history and may take 30+ seconds."),
                  actionButton("rs_load_signals", "Load Downstream Concerns",
                    class = "btn-primary", icon = icon("arrow-right"))
                )
              } else if (downstream_count > 0) {
                tagList(
                  div(class = "alert alert-info", style = "font-size: 0.85em; margin-top: 12px;",
                    icon("circle-info"), " ",
                    tags$strong("Dest course"), " — course expected to see extra demand next term. ",
                    tags$strong("Reason"), ": ",
                    tags$em("Bump"), " = course is commonly taken after a bump course; ",
                    tags$em("Drop"), " = course has unmet demand from students who dropped it and may re-enroll. ",
                    tags$strong("Top feeders"), " — up to 3 upstream bump courses by historical flow volume (Bump), or drop signal types (Drop)."
                  ),
                  tags$p(class = "text-muted-sm", downstream_scope_note),
                  DT::DTOutput("rs_signals_downstream_table")
                )
              } else {
                div(class = "empty-state", p("No downstream concerns found for the current scope."))
              }
            )
          ) # end tabsetPanel
        ) # end column
      ) # end fluidRow
    ) # end tagList
  })  # end renderUI
  
  # Render individual data tables for the tabbed interface
  output$rs_bumps_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "bumps" %in% names(data$flagged)) {
      create_regstats_datatable(data$flagged$bumps)
    }
  })
  
  output$rs_early_drops_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "early_drops" %in% names(data$flagged)) {
      create_regstats_datatable(data$flagged$early_drops)
    }
  })
  
  output$rs_late_drops_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "late_drops" %in% names(data$flagged)) {
      create_regstats_datatable(data$flagged$late_drops)
    }
  })
  
  output$rs_waits_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "waits" %in% names(data$flagged)) {
      data$flagged$waits %>%
        mutate(waiting = ifelse(
          waiting > 0,
          sprintf('<a href="javascript:void(0)" onclick="Shiny.setInputValue(\'waitlist-wl_navigate\', {course:\'%s\', term:\'%s\'}, {priority:\'event\'})">%d</a>',
                  htmltools::htmlEscape(subject_course), htmltools::htmlEscape(as.character(term)), waiting),
          as.character(waiting)
        ))
    }
  }, escape = FALSE, options = list(pageLength = 10, scrollX = TRUE))
  
  output$rs_emerging_sat_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "emerging_sat" %in% names(data$flagged)) {
      data$flagged$emerging_sat
    }
  }, options = list(pageLength = 10, scrollX = TRUE))

  output$rs_chronic_sat_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "chronic_sat" %in% names(data$flagged)) {
      data$flagged$chronic_sat
    }
  }, options = list(pageLength = 10, scrollX = TRUE))

  output$rs_signals_downstream_table <- DT::renderDataTable({
    signals <- signals_data()
    data    <- regstats_data()
    df <- filter_downstream_by_dept(signals$downstream, data$opt$dept, cedar_sections)
    if (is.null(df) || nrow(df) == 0) return(NULL)
    df %>%
      dplyr::rename(
        `Dest course` = dest_course,
        `Reason`      = reason,
        `Top feeders` = top_feeders
      ) %>%
      dplyr::select(`Dest course`, `Reason`, `Top feeders`)
  }, options = list(pageLength = 25, scrollX = TRUE))



  # Dashboard color palette
  .dash_up   <- "#2e7d32"   # green — above average / positive trend
  .dash_down <- "#c62828"   # red   — below average / negative trend
  .dash_neu  <- "#777777"   # grey  — neutral / no trend

  .dash_max_rows <- 8L       # max rows shown per course table

  # Render a single trend line: "6yr: ↑ 12%" with the arrow colored
  trend_line <- function(period_label, pct) {
    if (is.na(pct)) return(tags$div(
      style = "color: #aaa;",
      paste0(period_label, ": \u2014")
    ))
    color <- if (pct > 0) .dash_up else if (pct < 0) .dash_down else .dash_neu
    arrow <- if (pct > 0) "\u2191" else if (pct < 0) "\u2193" else "\u2192"
    tags$div(
      tags$span(style = "color: #888;", paste0(period_label, ": ")),
      tags$span(style = paste0("color: ", color, "; font-weight: 600;"),
                paste0(arrow, " ", abs(pct), "%"))
    )
  }

  # Render growing/declining outside-major SCH trend cards for one division level.
  # trends: list(growing, declining) from compute_major_sch_trends() in credit-hours.R
  render_sch_trend_cards <- function(trends, level_label) {
    if (is.null(trends)) return(NULL)

    fmt_pct_inline <- function(label, pct) {
      if (is.na(pct)) return(tagList(
        tags$span(style = "color: #888; font-size: 0.8em;", paste0(label, ": ")),
        tags$span(style = "color: #aaa; font-size: 0.8em;", "\u2014\u2002")
      ))
      color <- if (pct > 0) .dash_up else if (pct < 0) .dash_down else .dash_neu
      arrow <- if (pct > 0) "\u2191" else if (pct < 0) "\u2193" else "\u2192"
      tagList(
        tags$span(style = "color: #888; font-size: 0.8em;", paste0(label, ": ")),
        tags$span(style = paste0("color: ", color, "; font-weight: 600; font-size: 0.8em;"),
                  paste0(arrow, abs(pct), "%\u2002"))
      )
    }

    make_major_list <- function(majors, color, icon, header) {
      if (is.null(majors) || nrow(majors) == 0) return(div(
        h5(paste0(icon, " ", header), style = paste0("color: ", color, ";")),
        p("None in this window.", style = "color: #888; font-size: 0.88em;")
      ))
      div(
        h5(paste0(icon, " ", header), style = paste0("color: ", color, "; margin-bottom: 6px;")),
        tags$ul(
          style = "list-style: none; padding: 0; margin: 0;",
          lapply(seq_len(nrow(majors)), function(i) {
            r <- majors[i, ]
            tags$li(
              style = "padding: 6px 0; border-bottom: 1px solid #eee;",
              tags$div(
                tags$span(style = "font-weight: 600;", r$major_name),
                tags$span(style = "color: #888; font-size: 0.82em; margin-left: 6px;",
                          paste0("avg ", round(r$avg_sch, 0), " SCH/term")),
                if (!is.na(r$abs_change_1yr)) tags$span(
                  style = paste0("color: ", if (r$abs_change_1yr > 0) .dash_up else .dash_down,
                                 "; font-size: 0.82em; margin-left: 6px; font-weight: 600;"),
                  paste0(if (r$abs_change_1yr > 0) "+" else "", r$abs_change_1yr, " SCH")
                )
              ),
              tags$div(
                style = "margin-top: 2px;",
                fmt_pct_inline("1yr",  r$pct_1yr),
                fmt_pct_inline("2yr",  r$pct_2yr),
                fmt_pct_inline("4yr",  r$pct_4yr)
              )
            )
          })
        )
      )
    }

    # Emerging programs render differently: no pct columns (not computable from zero),
    # just current size. Shown only when there are rows.
    make_emerging_list <- function(majors, header) {
      if (is.null(majors) || nrow(majors) == 0) return(NULL)
      div(
        style = "margin-top: 12px;",
        h5(paste0("\u2605 ", header), style = paste0("color: #8b6914; margin-bottom: 6px;")),
        tags$ul(
          style = "list-style: none; padding: 0; margin: 0;",
          lapply(seq_len(nrow(majors)), function(i) {
            r <- majors[i, ]
            tags$li(
              style = "padding: 6px 0; border-bottom: 1px solid #eee;",
              tags$span(style = "font-weight: 600;", r$major_name),
              tags$span(style = "color: #888; font-size: 0.82em; margin-left: 6px;",
                        paste0("avg ", round(r$avg_sch, 0), " SCH/term")),
              tags$span(style = "color: #8b6914; font-size: 0.82em; margin-left: 6px;",
                        "new this year")
            )
          })
        )
      )
    }

    div(
      style = "margin-bottom: 20px;",
      fluidRow(
        column(6, make_major_list(trends$growing,   .dash_up,   "\u2191", paste0("Growing (", level_label, ")"))),
        column(6, make_major_list(trends$declining, .dash_down, "\u2193", paste0("Declining (", level_label, ")")))
      ),
      make_emerging_list(trends$emerging, paste0("New Programs (", level_label, ")"))
    )
  }

  # Drop rate stats — helper renders one directional subset (above or below avg),
  # grouped by course level with a table per level, rows sorted by rate descending.
  # Level avg appears in the section header; diff vs course avg appears per row.
  .render_drop_level_table <- function(courses, rate_col, diff_col, level_avg_col) {
    if (is.null(courses) || nrow(courses) == 0)
      return(p("None.", style = "color: #999; font-size: 0.85em; padding: 4px 0;"))

    lvl_name  <- function(x) switch(as.character(x),
                   lower = "Lower Division", upper = "Upper Division",
                   grad = "Graduate", as.character(x))
    fmt_diff  <- function(d) if (!is.na(d)) paste0(if (d > 0) "+" else "", d, "%") else "\u2014"
    d_color   <- function(d) if (!is.na(d) && d > 0) .dash_down else .dash_up

    level_order  <- c("lower", "upper", "grad")
    present_lvls <- unique(courses$course_level)
    known        <- intersect(level_order, present_lvls[!is.na(present_lvls)])
    other        <- setdiff(present_lvls[!is.na(present_lvls)], level_order)
    ordered_lvls <- c(known, other)
    if (any(is.na(present_lvls))) ordered_lvls <- c(ordered_lvls, NA_character_)

    tagList(lapply(ordered_lvls, function(lvl) {
      grp <- if (is.na(lvl)) courses[is.na(courses$course_level), ]
             else             courses[!is.na(courses$course_level) & courses$course_level == lvl, ]
      if (nrow(grp) == 0) return(NULL)

      # Sort by rate descending within each level section
      grp <- grp[order(-grp[[rate_col]]), ]

      lvl_avg  <- grp[[level_avg_col]][1]
      avg_text <- if (!is.na(lvl_avg)) paste0(" \u2014 level avg: ", lvl_avg, "%") else ""
      hdr      <- paste0(if (!is.na(lvl)) lvl_name(lvl) else "Other", avg_text)

      tagList(
        tags$p(style = paste0("font-size: 0.78em; font-weight: 700; color: #888;",
                              " text-transform: uppercase; letter-spacing: 0.06em;",
                              " margin: 10px 0 3px;"),
               hdr),
        tags$table(
          class = "table table-sm", style = "font-size: 0.82em; margin-bottom: 0;",
          lapply(seq_len(nrow(grp)), function(i) {
            r     <- grp[i, ]
            title <- if (!is.na(r$course_title)) r$course_title else ""
            d     <- r[[diff_col]]
            tags$tr(
              tags$td(style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                      r$subject_course),
              tags$td(style = "padding: 2px 4px; color: #555;", title),
              tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap; color: #333;",
                      paste0(r[[rate_col]], "%")),
              tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right;",
                                     " white-space: nowrap; color: ", d_color(d), ";"),
                      fmt_diff(d))
            )
          })
        )
      )
    }))
  }

  #################################
  ##### EXPLORE YOUR UNIT DASHBOARD
  #################################

  dashboard_data <- reactiveVal(NULL)

  # Filter department choices to only depts with sections at the selected campus(es).
  # When no campus is selected, show all departments.
  observe({
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
  })

  # Auto-load dashboard data when department or campus selection changes
  observe({
    dept   <- input$dashboard_dept
    campus <- input$dashboard_campus
    req(dept, dept != "")

    log_data_filter(session, "dashboard_dept", dept)
    dashboard_data(NULL)

    avg <- get_average_report_time("dept_dashboard")
    timer <- start_report_timer("dept_dashboard", list(dept = dept))

    tryCatch({
      campus_val <- if (is.null(campus) || length(campus) == 0) NULL else campus
      opt <- list(dept = dept, campus = campus_val, shiny = TRUE)
      d <- create_dept_dashboard_data(data_objects, opt)
      # DEBUG: uncomment to diagnose false-positive "new this term" courses
      # course_history <- get_dept_course_enrl_history(data_objects[["cedar_sections"]], d$dept_code)
      # diagnose_new_this_term(course_history, if (exists("cedar_current_term")) cedar_current_term else max(course_history$term))
      dashboard_data(d)
      duration_sec <- end_report_timer(timer)
      session$sendCustomMessage("dashboard_load_complete", list(
        duration_sec = round(duration_sec, 1),
        avg_sec      = if (!is.null(avg)) round(avg, 1) else NULL
      ))
    }, error = function(e) {
      tryCatch(end_report_timer(timer), error = function(e2) NULL)
      showNotification(paste("Dashboard error:", conditionMessage(e)), type = "error", duration = 5)
      message("[server.R] Dashboard error: ", conditionMessage(e))
    })
  })

  # Subject selector — populated from cedar_sections for the selected dept
  # Subject dropdown removed: dashboard now only uses campus and department selectors

  # Program transparency info box — shows which subject and program codes are matched
  # for the selected department. Purely reactive on the dept input; no heavy data load.
  output$dashboard_program_info <- renderUI({
    dept <- input$dashboard_dept
    req(dept, dept != "")

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
        style = paste0(
          "display:inline-block; background:#dbeafe; color:#1e3a5f; ",
          "border-radius:4px; padding:1px 7px; margin:2px 3px 2px 0; ",
          "font-size:0.82em; font-family:monospace;"
        ),
        code
      )
    }

    row_item <- function(label, codes) {
      if (length(codes) == 0) return(NULL)
      tags$div(
        style = "margin-bottom: 4px; line-height: 1.8;",
        tags$span(label, style = "font-size:0.82em; color:#374151; font-weight:600; margin-right:6px;"),
        lapply(codes, code_pill)
      )
    }

    div(
      style = paste0(
        "background:#eff6ff; border:1px solid #bfdbfe; border-left:4px solid #1d4ed8; ",
        "border-radius:6px; padding:10px 14px; margin-bottom:16px;"
      ),
      div(
        style = "font-size:0.82em; color:#1e3a5f; font-weight:700; margin-bottom:6px;",
        paste0("\u2139\ufe0f  Data scope for \u201c", dept_name_label, "\u201d (dept code: ", dept, ")")
      ),
      row_item("Course subject codes (cedar_sections):", subj_codes),
      row_item("Degree program codes (cedar_programs):",  degree_codes),
      row_item("Variant codes (X-prefix):",               variant_codes),
      row_item("Pre-major codes (F-prefix):",             premaj_codes),
      div(
        style = "font-size:0.77em; color:#4b5563; margin-top:6px;",
        "Headcount counts students with any matching ",
        tags$code(style="font-size:0.95em;", "dept_code"),
        " row in ",
        tags$code(style="font-size:0.95em;", "cedar_programs"),
        ". Variant and pre-major codes are resolved to their canonical dept at transform time."
      )
    )
  })

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
          style = "font-size: 0.78rem; margin-top: 8px; line-height: 1.8;",
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
        "Counts reflect the most recent term. Trend percentages compare the most recent fall to prior fall terms."
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
  }, bg = "transparent")

  # Cross-dept minor donut
  output$dashboard_cross_dept_minors <- renderPlotly({
    d <- dashboard_data()
    req(d)
    req(d$plots$cross_dept_minors)
    d$plots$cross_dept_minors
  })

  # Majors-of-minors donut (inverse: who majors elsewhere but minors here?)
  output$dashboard_majors_with_minor <- renderPlotly({
    d <- dashboard_data()
    req(d)
    req(d$plots$majors_with_minor)
    d$plots$majors_with_minor
  })

  # Credit hours by level trendlines
  output$dashboard_credit_hours <- renderPlotly({
    d <- dashboard_data()
    req(d)
    req(d$plots$credit_hours_by_level)
    d$plots$credit_hours_by_level
  })

  # Student composition — current-term donuts (left column)
  for (.donut_key in c(
    "lower_major_current", "upper_major_current",
    "lower_class_current", "upper_class_current"
  )) {
    local({
      key <- .donut_key
      output[[paste0("dashboard_", key)]] <- renderPlotly({
        d <- dashboard_data()
        req(d)
        p <- d$plots$student_donuts[[key]]
        req(p)
        p
      })
    })
  }

  # Composition comparison tables (right column) — major and class by level.
  # Renders a color-swatch + label + current / avg / pct-change table.
  .render_composition_table <- function(df, lvl_label) {
    if (is.null(df) || nrow(df) == 0)
      return(p("No data available.", style = "color: #999; font-size: 0.85em;"))

    header <- tags$tr(
      tags$th(style = "padding: 2px 6px 4px 0; font-weight: 600; color: #555; font-size: 0.8em;", ""),
      tags$th(style = "padding: 2px 4px 4px; font-weight: 600; color: #555; font-size: 0.8em; text-align: right;", "Current"),
      tags$th(style = "padding: 2px 4px 4px; font-weight: 600; color: #555; font-size: 0.8em; text-align: right;", "Avg"),
      tags$th(style = "padding: 2px 0 4px 6px; font-weight: 600; color: #555; font-size: 0.8em; text-align: right;", "Chg")
    )

    rows <- lapply(seq_len(nrow(df)), function(i) {
      r     <- df[i, ]
      color <- if (!is.na(r$color) && nzchar(r$color)) r$color else "#aaaaaa"

      cur_str <- if (!is.na(r$n) && r$n > 0) as.character(round(r$n)) else "\u2014"
      avg_str <- if (!is.na(r$avg_n)) as.character(round(r$avg_n, 1)) else "\u2014"

      pct <- r$pct_change
      chg_color <- if (!is.na(pct) && pct > 0) .dash_up else if (!is.na(pct) && pct < 0) .dash_down else .dash_neu
      chg_str   <- if (!is.na(pct)) {
        arrow <- if (pct > 0) "\u2191" else if (pct < 0) "\u2193" else "\u2192"
        paste0(arrow, abs(pct), "%")
      } else "\u2014"

      tags$tr(
        tags$td(
          style = "padding: 2px 6px 2px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 180px;",
          tags$span(style = paste0("display:inline-block; width:9px; height:9px; border-radius:2px; background:", color, "; margin-right:5px; flex-shrink:0; vertical-align:middle;")),
          tags$span(r$label, style = "font-size: 0.85em; vertical-align: middle;")
        ),
        tags$td(style = "padding: 2px 4px; text-align: right; font-size: 0.85em; white-space: nowrap;", cur_str),
        tags$td(style = "padding: 2px 4px; text-align: right; font-size: 0.85em; white-space: nowrap; color: #777;", avg_str),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; font-size: 0.85em; white-space: nowrap; font-weight: 600; color: ", chg_color, ";"), chg_str)
      )
    })

    tags$table(
      class = "table table-sm",
      style = "font-size: 0.82em; margin-bottom: 0; table-layout: fixed; width: 100%;",
      tags$thead(header),
      tags$tbody(rows)
    )
  }

  for (.lvl in c("lower", "upper")) {
    local({
      lvl       <- .lvl
      lvl_label <- if (lvl == "lower") "Lower Div" else "Upper Div"

      output[[paste0("dashboard_", lvl, "_major_table")]] <- renderUI({
        d <- dashboard_data(); req(d)
        df            <- d$plots$student_donuts[[paste0(lvl, "_major_table_df")]]
        n_hist        <- d$plots$student_donuts[[paste0(lvl, "_n_hist")]]
        cur_term_type <- d$plots$student_donuts[["cur_term_type"]]
        term_label    <- if (!is.null(cur_term_type) && !is.na(cur_term_type))
          paste0(n_hist, " ", cur_term_type, " terms") else paste0(n_hist, " terms")
        tagList(
          p(paste0(lvl_label, " Majors \u2014 avg over last ", term_label, " vs current"),
            style = "font-size: 0.8em; color: #666; margin-bottom: 4px;"),
          .render_composition_table(df, lvl_label)
        )
      })

      output[[paste0("dashboard_", lvl, "_class_table")]] <- renderUI({
        d <- dashboard_data(); req(d)
        df            <- d$plots$student_donuts[[paste0(lvl, "_class_table_df")]]
        n_hist        <- d$plots$student_donuts[[paste0(lvl, "_n_hist")]]
        cur_term_type <- d$plots$student_donuts[["cur_term_type"]]
        term_label    <- if (!is.null(cur_term_type) && !is.na(cur_term_type))
          paste0(n_hist, " ", cur_term_type, " terms") else paste0(n_hist, " terms")
        tagList(
          p(paste0(lvl_label, " Class Standing \u2014 avg over last ", term_label, " vs current"),
            style = "font-size: 0.8em; color: #666; margin-bottom: 4px;"),
          .render_composition_table(df, lvl_label)
        )
      })
    })
  }

  # Helper: format an enrollment diff as "↑34% (+12)" or "↓8% (−5)"
  fmt_enrl_diff <- function(diff, pct) {
    if (is.na(diff)) return("")
    arrow_chr <- if (diff > 0) "\u2191" else if (diff < 0) "\u2193" else "\u2192"
    sign_chr  <- if (diff >= 0) "+" else "\u2212"
    count_str <- paste0(" (", sign_chr, abs(diff), ")")
    if (!is.na(pct)) paste0(arrow_chr, abs(pct), "%", count_str) else paste0(sign_chr, abs(diff))
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

  # Render a standard dashboard course table, capping at max_rows (default: .dash_max_rows).
  # Pass max_rows = Inf to render all rows without a cap.
  # row_fn(i, data) should return a tags$tr() for row i.
  .render_course_table <- function(data, row_fn, empty_msg = "No courses to display", max_rows = .dash_max_rows) {
    if (is.null(data) || nrow(data) == 0) {
      return(p(empty_msg, style = "color: #888; font-size: 0.9em; padding: 4px 0;"))
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
                r$subject_course),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_up, ";"),
                paste0(diff_str, " vs avg ", round(r$hist_avg_enrl, 0)))
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
                r$subject_course),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = paste0("padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: ", .dash_down, ";"),
                paste0(diff_str, " vs avg ", round(r$hist_avg_enrl, 0)))
      )
    })
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
                r$subject_course),
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
                r$subject_course),
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
                r$subject_course),
        tags$td(style = "padding: 2px 4px; color: #555;", r$course_title),
        tags$td(style = "padding: 2px 4px; text-align: right; white-space: nowrap;",
                paste0(r$total_enrl, " enrolled")),
        tags$td(style = "padding: 2px 0 2px 6px; text-align: right; white-space: nowrap; color: #888;",
                hist_txt)
      )
    })
  })

  # Early drop rates: below avg (left) | above avg (right), grouped by course level
  output$dashboard_early_drops <- renderUI({
    d <- dashboard_data()
    req(d)
    ds <- d$drop_stats
    if (is.null(ds) || is.null(ds$early_drops))
      return(p("No early drop data available for this term.", style = "color: #999;"))
    ed <- ds$early_drops
    fluidRow(
      column(6,
        tags$span(style = paste0("color: ", .dash_up, "; font-weight: 600;"), "\u2193 Below average"),
        .render_drop_level_table(ed$below, "early_rate", "diff_early", "level_avg_early_rate")
      ),
      column(6,
        tags$span(style = paste0("color: ", .dash_down, "; font-weight: 600;"), "\u2191 Above average"),
        .render_drop_level_table(ed$above, "early_rate", "diff_early", "level_avg_early_rate")
      )
    )
  })

  # Late drop rates: below avg (left) | above avg (right), grouped by course level
  output$dashboard_late_drops <- renderUI({
    d <- dashboard_data()
    req(d)
    ds <- d$drop_stats
    if (is.null(ds) || is.null(ds$late_drops))
      return(p("No late drop data available for this term.", style = "color: #999;"))
    ld <- ds$late_drops
    fluidRow(
      column(6,
        tags$span(style = paste0("color: ", .dash_up, "; font-weight: 600;"), "\u2193 Below average"),
        .render_drop_level_table(ld$below, "late_rate", "diff_late", "level_avg_late_rate")
      ),
      column(6,
        tags$span(style = paste0("color: ", .dash_down, "; font-weight: 600;"), "\u2191 Above average"),
        .render_drop_level_table(ld$above, "late_rate", "diff_late", "level_avg_late_rate")
      )
    )
  })


  ##############################
  ##### DEPARTMENT REPORT #####
  ##############################

  # Reactive value to store department report data
  dept_report_data <- reactiveVal(NULL)
  dr_enrl_data     <- reactiveVal(NULL)
  dr_deg_data      <- reactiveVal(NULL)
  dr_ch_data       <- reactiveVal(NULL)
  dr_dfw_data      <- reactiveVal(NULL)
  dr_demo_data     <- reactiveVal(NULL)
  dr_ge_data       <- reactiveVal(NULL)

  # Reactive value to track DFW authentication status (per session)
  # Shared across dept report and course report DFW tabs
  dfw_authenticated <- reactiveVal(FALSE)

  # Helper function to create password gate UI (used by both dept report and course report DFW tabs)
  create_password_gate_ui <- function(password_input_id, submit_button_id) {
    div(
      class = "alert alert-warning",
      style = "margin: 20px 0;",
      h5(icon("lock"), " Access Restricted"),
      p("This section contains sensitive academic performance data and requires authentication. Enter the password below to continue."),
      br(),
      div(
        style = "display: flex; gap: 10px; align-items: flex-start;",
        div(
          style = "flex: 1; max-width: 300px;",
          passwordInput(password_input_id, "", placeholder = "Enter password")
        ),
        actionButton(submit_button_id, "Access", class = "btn-primary", style = "margin-top: 0px; white-space: nowrap;")
      )
    )
  }

  # Track selected tab so UI re-renders keep the same tab active
  dept_report_tab_selected <- reactiveVal("Headcount")

  # DFW password from environment variable or config
  dfw_password <- Sys.getenv("CEDAR_DFW_PASSWORD", unset = "cedar-dfw-2025")
  
  # Auto-generate profile when department or campus selection changes
  observe({
    dept   <- input$dept_report_dept
    campus <- input$dept_report_campus
    req(dept, dept != "")

    log_data_filter(session, "dept_report_dept", dept)
    log_report_generation(session, "dept_report", list(department = dept, campus = campus))
    dept_report_data(NULL)
    dr_enrl_data(NULL)
    dr_deg_data(NULL)
    dr_ch_data(NULL)
    dr_dfw_data(NULL)
    dr_demo_data(NULL)
    dr_ge_data(NULL)

    avg_time     <- get_average_report_time("dept_report")
    avg_msg      <- if (is.null(avg_time)) "This may take a moment." else paste0("Avg: ", avg_time, " s.")
    showNotification(paste("Assembling Unit Profile\u2026", avg_msg),
                     type = "message", duration = NULL, id = "dept_loading")

    timer <- start_report_timer("dept_report", list(department = dept))

    tryCatch({
      cedar_debug("[server.R] Checking dept report cache for: ", dept)
      opt <- list(shiny = TRUE, dept = dept,
                  campus = if (length(campus) > 0) campus else NULL)

      # Plot-name groupings for splitting cached data into per-tab reactiveVals
      .hc_plots   <- c("hc_progs_under_long_majors_plot", "hc_progs_under_long_minors_plot",
                       "hc_progs_grad_long_majors_plot",  "hc_progs_grad_long_minors_plot")
      .enrl_plots <- c("highest_total_enrl_plot", "highest_mean_enrl_plot", "highest_mean_histo_plot")
      .deg_plots  <- c("degree_summary_faceted_by_major_plot", "degree_summary_filtered_program_stacked_plot")
      .ch_plots   <- c("chd_by_year_facet_subj_plot", "chd_by_year_subj_plot", "chd_by_year_plot",
                       "sch_outside_pct_lower_plot", "sch_outside_pct_upper_plot",
                       "sch_dept_pct_lower_plot", "sch_dept_pct_upper_plot",
                       "sch_top_majors_lower_plot", "sch_top_majors_upper_plot",
                       "chd_by_fac_facet_plot", "chd_by_fac_plot", "college_dept_dual_plot")
      .dfw_plots  <- c("grades_summary_for_ld_abq_ea_plot")
      .sp         <- function(plots, keys) plots[intersect(names(plots), keys)]

      cached <- load_dept_headcount_cache(dept, data_objects)
      if (!is.null(cached)) {
        message("[server.R] Headcount cache hit for: ", dept)
        hc_plots     <- rebuild_dept_hc_plots(cached)
        duration_sec <- end_report_timer(timer, cached = TRUE)

        # Reconstruct data_objects_filt so lazy tab observers can compute their tabs
        do_filt <- filter_data_objects(data_objects, if (length(campus) > 0) campus else NULL)

        base <- c(
          cached[c("dept_code", "dept_raw", "dept_name", "subj_codes", "prog_codes",
                   "prog_focus", "palette", "term_start", "term_end")],
          list(plots             = .sp(hc_plots, .hc_plots),
               tables            = cached$tables["hc_progs_under_long_majors"],
               data_objects_filt = do_filt)
        )
        dept_report_data(base)
        # Other tabs remain NULL and lazy-load on first click

        removeNotification("dept_loading")
        showNotification(paste0("Unit Profile ready (cached, ", round(duration_sec, 1), " s)"),
                         type = "message", duration = 3)
      } else {
        cedar_debug("[server.R] Computing headcount for: ", dept)
        base <- create_dept_report_base(data_objects, opt)
        cedar_debug("[server.R] Headcount ready for: ", dept)

        duration_sec <- end_report_timer(timer)
        dept_report_data(base)

        # Write headcount to disk so the next user gets a cache hit.
        # Other tabs cache independently when first computed (not yet wired).
        cache_dept_headcount(dept, base, data_objects)

        removeNotification("dept_loading")
        showNotification(paste0("Unit Profile ready (", round(duration_sec, 1), " s)"),
                         type = "message", duration = 3)
      }
    }, error = function(e) {
      handle_error(e, "dept_report", "dept_loading")
    })
  }) # end observe dept_report_dept

  # Persist selected tab across re-renders
  observeEvent(input$dept_report_tabs, {
    if (!is.null(input$dept_report_tabs)) {
      dept_report_tab_selected(input$dept_report_tabs)
    }
  }, ignoreInit = TRUE)

  # Lazy-load per-tab data when user clicks a tab for the first time
  observeEvent(input$dept_profile_tabs, {
    tab  <- input$dept_profile_tabs
    base <- dept_report_data()
    req(!is.null(base))

    .safe <- function(expr, label) {
      tryCatch(expr, error = function(e) {
        message("[server.R] ", label, " tab error: ", e$message)
        list(plots = list(), tables = list())
      })
    }

    if (tab == "Enrollment" && is.null(dr_enrl_data())) {
      dr_enrl_data(.safe(compute_dept_enrl_tab(base), "Enrollment"))

    } else if (tab == "Demographics" && is.null(dr_demo_data())) {
      dr_demo_data(tryCatch(
        make_population_trend(cedar_programs, dept_code = base$dept_code),
        error = function(e) { message("[server.R] Demographics tab error: ", e$message); NULL }
      ))

    } else if (tab == "Degrees" && is.null(dr_deg_data())) {
      dr_deg_data(.safe(compute_dept_degrees_tab(base), "Degrees"))

    } else if (tab == "Credit Hours" && is.null(dr_ch_data())) {
      dr_ch_data(.safe(compute_dept_credit_hours_tab(base), "Credit Hours"))

    } else if (tab == "DFW" && is.null(dr_dfw_data()) && dfw_authenticated()) {
      dr_dfw_data(.safe(compute_dept_dfw_tab(base), "DFW"))
    }
  }, ignoreInit = TRUE)

  # Inline DFW password submission for dept report (keeps the DFW tab active)
  observeEvent(input$dfw_submit_inline_btn, {
    if (input$dfw_password_inline == dfw_password) {
      dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
      base <- dept_report_data()
      if (!is.null(base) && is.null(dr_dfw_data())) {
        dr_dfw_data(tryCatch(
          compute_dept_dfw_tab(base),
          error = function(e) { message("[server.R] DFW tab error: ", e$message); list(plots = list(), tables = list()) }
        ))
      }
    } else {
      showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
    }
  }, ignoreInit = TRUE)

  # Inline DFW password submission for course report
  observeEvent(input$cr_dfw_submit_btn, {
    if (input$cr_dfw_password == dfw_password) {
      dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
    } else {
      showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
    }
  }, ignoreInit = TRUE)



  # Small download link shown inline next to "Assemble Profile" after data is ready
  output$dept_download_link <- renderUI({
    if (is.null(dept_report_data())) return(NULL)
    tags$span(
      style = "margin-left: 12px; font-size: 0.85em; vertical-align: middle;",
      downloadLink("dept_report_html_download", label = "download report \u2193")
    )
  })

  ########################################
  # Department HTML Report Generation/Download (via RMarkdown)
  #########################################
  output$dept_report_html_download <- downloadHandler(
  
    filename = function() {
      paste0(input$dept_report_dept, ".html")
    },
    
    content = function(file) {
      req(input$dept_report_dept)
      if (input$dept_report_dept == "") {
        showNotification("Please select a department.", type = "error")
        return()
      }

      dept <- input$dept_report_dept
      cedar_debug("[downloadHandler] dept_report_html requested for: ", dept)

      # Log download request
      log_download(session, "dept_report_html", paste0(dept, ".html"))

      # Show loading notification
      status_message <- create_timing_status_message("dept_report_html", "Generating HTML department")
      showNotification(status_message, type = "message", duration = NULL, id = "html_loading")
      
      # Start timing
      timer <- start_report_timer("dept_report_html", list(department = dept))

      tryCatch({
        # Check for cached data
        cached_data <- dept_report_data()
        use_cached_data <- !is.null(cached_data) && 
                          !is.null(cached_data$dept_code) && 
                          cached_data$dept_code == dept

        if (use_cached_data) {
          message("[downloadHandler] Cache hit: using cached dept report data")
          d_params <- cached_data
          d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
          d_params$output_dir_base <- file.path(cedar_output_dir, "dept-reports")
          d_params$output_filename <- dept

          create_report(opt = list(shiny = TRUE, dept = dept), d_params)
        } else {
          message("[downloadHandler] Cache miss: generating fresh dept report data")
          opt <- list(shiny = TRUE, dept = dept)
          create_dept_report(data_objects, opt)
        }
              
        # In Docker, create_report saves to data/ directory
        # Sanitize filename same way as dept-report.R
        report_filename <- gsub(" ", "_", dept)
        output_path <- file.path(getwd(), "data", paste0(report_filename, ".html"))
        cedar_debug("[downloadHandler] looking for file at: ", output_path)
        
        if (!file.exists(output_path)) {
          stop("Report file not found at: ", output_path)
        }
        
        file.copy(output_path, file, overwrite = TRUE)
        cedar_debug("[downloadHandler] copied to download location: ", file)

        # End timing
        duration_sec <- end_report_timer(timer)
        removeNotification("html_loading")
        showNotification(paste0("Report downloaded (", round(duration_sec, 1), "s)"), 
                        type = "message", duration = 5)

      }, error = function(e) {
        handle_error(e, "dept_report_download", "html_loading")
        tryCatch(end_report_timer(timer), error = function(timer_error) {
          message("[downloadHandler] timer error: ", timer_error$message)
        })
      })
    }
  )



  ##################################
  # Render department report outputs
  output$dept_report <- renderUI({
    data <- dept_report_data()
    if (is.null(data)) {
      return(div(
        class = "empty-state",
        h4("Select a department to view its profile.")
      ))
    }
    
    # Create a tabbed interface for different report sections
    tabsetPanel(
      id = "dept_profile_tabs",
      tabPanel("Headcount",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Undergrad Majors"),
            plotlyOutput("hc_progs_under_long_majors_plot"),
            h4("Undergrad Minors"),
            plotlyOutput("hc_progs_under_long_minors_plot"),
            h4("Grad Majors"),
            plotlyOutput("hc_progs_grad_long_majors_plot"),
            h4("Grad Minors"),
            plotlyOutput("hc_progs_grad_long_minors_plot")
          )
        )
      ),
      tabPanel("Enrollment",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Highest Total Enrollment"),
            plotlyOutput("highest_total_enrl_plot"),
            h4("Highest Mean Enrollment"),
            plotlyOutput("highest_mean_enrl_plot"),
            h4("Mean Enrollment Distribution"),
            plotlyOutput("highest_mean_histo_plot")
          )
        )
      ),
      tabPanel("Demographics",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            p("How the mix of new entrants (First-Time Freshman, Transfer, Continuing, etc.) has shifted
               over time for declared majors and pre-majors in this department. Each student is counted
               once \u2014 at their first term in the program.",
              style = "font-size: 0.85em; color: #666; margin-top: 8px;"),
            plotOutput("dept_pt_plot", height = "520px")
          )
        )
      ),
      tabPanel("Degrees",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Degree Summary by Major"),
            plotlyOutput("degree_summary_faceted_by_major_plot"),
            h4("Degree Summary by Program (Stacked)"),
            plotlyOutput("degree_summary_filtered_program_stacked_plot")
          )
        )
      ),
      tabPanel("Credit Hours",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),

            # ── Methodology ────────────────────────────────────────────────
            div(
              style = "background: #f8f9fa; border-left: 4px solid #6c757d; padding: 14px 18px; margin-bottom: 20px; font-size: 0.88em; color: #333;",
              tags$strong("How credit hours are counted on this tab"),
              tags$p(style = "margin-top: 8px; margin-bottom: 6px;",
                "Every number on this tab is a count of ", tags$strong("Student Credit Hours (SCH)"),
                " — the sum of course credit values across qualifying enrollments. A student",
                " enrolled in a 3-credit course contributes 3 SCH; a 4-credit lab contributes 4.",
                " SCH is the standard measure of instructional load and is what drives departmental",
                " budget allocations."
              ),
              tags$p(style = "margin-bottom: 6px;",
                tags$strong("Source: "), "Banner class lists, stored in cedar_students. Each row is one",
                " student registered in one course section in one term. The ",
                tags$code("credits"), " column is the course's credit-hour value",
                " (Banner field: Course Credits)."
              ),
              tags$p(style = "margin-bottom: 6px;",
                tags$strong("Passing grades only. "), "Only enrollments with a final grade of",
                " A+, A, A\u2212, B+, B, B\u2212, C+, C, or CR are counted.",
                " D grades (D+, D, D\u2212), F, W, and Incomplete are excluded.",
                " This matches the standard definition of \u2018earned\u2019 SCH used in academic reporting."
              ),
              tags$p(style = "margin-bottom: 6px;",
                tags$strong("Course department, not student department. "),
                "The ", tags$code("department"), " column on each row identifies the",
                " course\u2019s home department \u2014 not the student\u2019s major.",
                " All rows on this tab are filtered to courses taught by ", tags$strong(data$dept_name), ".",
                " A Psychology major sitting in BIOL 2310 contributes 3 SCH to Biology\u2019s totals."
              ),
              tags$p(style = "margin-bottom: 6px;",
                tags$strong("How student majors are identified. "),
                "Each enrollment row carries the student\u2019s Banner major ", tags$em("code"),
                " at the time of enrollment (e.g., HIST, NURS, PSYC, BIOL).",
                " This is the ", tags$code("major"), " column in cedar_students.",
                " Display names (e.g., \u201cNursing\u201d, \u201cHistory\u201d) are looked up from a",
                " standardized code\u2013name table; if a code has no entry the raw code is shown."
              ),
              tags$p(style = "margin-bottom: 6px;",
                tags$strong("Pre-majors and declared majors are shown separately. "),
                "UNM Banner uses F-prefix codes for pre-major students:",
                " FBIO = pre-Biology, FHIS = pre-History, FNAP and FNRS = pre-Nursing,",
                " FPHS = pre-Pharmacy, and so on. These are distinct codes from their",
                " declared counterparts (BIOL, HIST, NURS, PHRM).",
                " A pre-nursing student (FNAP or FNRS) taking BIOL 2310 appears as \u201cPre-Nursing\u201d",
                " in the outside-major charts \u2014 separate from declared Nursing (NURS) students.",
                " Multiple Banner codes that share the same display name (e.g., FNAP and FNRS",
                " both labeled \u201cPre-Nursing\u201d) are combined into one slice so their",
                " collective volume is visible."
              ),
              # HIDDEN: instructor type note disabled — HR data no longer updated
              # tags$p(style = "margin-bottom: 0;",
              #   tags$strong("Instructor type charts require HR data. "),
              #   "The \u201cCredit Hours by Instructor Type\u201d charts at the bottom of this tab are built",
              #   " by joining enrollment records to HR data (cedar_faculty) on instructor ID and term.",
              #   " If HR data has not been loaded, those charts will not appear.",
              #   " Instructor job categories \u2014 Professor, Associate Professor, Assistant Professor,",
              #   " Lecturer, Term Teacher, TPT (temporary part-time: adjuncts, visiting faculty),",
              #   " and Grad (graduate teaching assistants) \u2014 are derived from the Academic Title",
              #   " field in Banner HR reports and standardized during data processing.",
              #   " Enrollments in courses whose instructor does not appear in the HR data",
              #   " are attributed to NA and may show as a separate bar segment."
              # )
            ),
            # ───────────────────────────────────────────────────────────────

            h4("Credit Hours by Level and Subject Code"),
            p("Total SCH earned in this department\u2019s courses each term, broken down by course",
              " level (lower-division 100\u2013299, upper-division 300\u2013499, graduate 500+) and by",
              " subject code prefix. Departments that teach under multiple subject codes",
              " (e.g., a department offering both BIOL and BIOC courses) will show multiple",
              " facets. Summer terms appear where data exists.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            plotlyOutput("chd_by_year_facet_subj_plot"),
            h4("Credit Hours by Subject Code (Combined)"),
            p("Same data as above, collapsed across levels, to show total SCH per subject code",
              " over time as a single stacked bar.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            plotlyOutput("chd_by_year_subj_plot"),

            h4("Student Credit Hours by Major"),
            p(
              "The charts below answer: ", tags$em("whose students are taking these courses?"),
              " Each enrollment row carries the student\u2019s Banner major code at the time of",
              " enrollment. Codes are converted to display names, and codes that share a name",
              " (e.g., FNAP and FNRS \u2192 \u201cPre-Nursing\u201d) are combined before ranking,",
              " so multi-code programs appear as a single group rather than splitting their volume.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 4px;"),
            p(
              tags$strong("Home majors"), " are students whose major code matches one of this",
              " department\u2019s program codes (", tags$code(paste(data$prog_codes, collapse = ", ")), ").",
              " ", tags$strong("Outside majors"), " are everyone else \u2014 students from other programs,",
              " pre-majors, undeclared students, and students from other colleges.",
              " Example: for Biology, a student with major code NURS (Nursing) or FNAP (Pre-Nursing)",
              " taking BIOL 2310 is an outside major. A student with major code BIOL is a home major.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            fluidRow(
              column(6,
                h5("Outside Majors (Lower Division)"),
                plotlyOutput("sch_outside_pct_lower_plot")
              ),
              column(6,
                h5("Outside Majors (Upper Division)"),
                plotlyOutput("sch_outside_pct_upper_plot")
              )
            ),
            p("Top 9 outside-major groups by total SCH across the date range.",
              " Groups with the same display name (e.g., all pre-nursing codes combined as \u201cPre-Nursing\u201d)",
              " are ranked together. All remaining groups are collapsed into \u201cOther.\u201d",
              " Pre-majors (e.g., Pre-Nursing) are a separate slice from their declared counterparts (Nursing).",
              style = "color: #555; font-size: 0.85em; margin-top: 4px; margin-bottom: 16px;"),
            fluidRow(
              column(6,
                h5("Majors vs Non-Majors (Lower Division)"),
                plotlyOutput("sch_dept_pct_lower_plot")
              ),
              column(6,
                h5("Majors vs Non-Majors (Upper Division)"),
                plotlyOutput("sch_dept_pct_upper_plot")
              )
            ),
            p("Share of total SCH in this division earned by home majors vs all outside majors combined.",
              style = "color: #555; font-size: 0.85em; margin-top: 4px; margin-bottom: 16px;"),

            h4("Outside Majors \u2014 Credit Hours Over Time"),
            p("Term-by-term SCH for the top 5 outside-major groups (same ranking as the donut charts above),",
              " plus an \u201cOther\u201d stack for all remaining outside majors.",
              " Summer terms are included. Colors match the outside-major donut charts above.",
              " This view reveals whether the \u201cOther\u201d category is growing and, if so, which",
              " specific groups are driving it.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            fluidRow(
              column(6,
                h5("Lower Division"),
                plotlyOutput("sch_top_majors_lower_plot")
              ),
              column(6,
                h5("Upper Division"),
                plotlyOutput("sch_top_majors_upper_plot")
              )
            ),
            h4("All Outside Majors \u2014 Full Breakdown"),
            p("Complete ranked list of all outside-major groups by total SCH across the date range.",
              " The top 9 appear as named slices in the donut charts above; everything below rank 9",
              " is the \u201cOther\u201d slice.",
              style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            fluidRow(
              column(6,
                h5("Lower Division \u2014 All Outside Majors"),
                DT::DTOutput("sch_outside_full_lower_table")
              ),
              column(6,
                h5("Upper Division \u2014 All Outside Majors"),
                DT::DTOutput("sch_outside_full_upper_table")
              )
            ),

            h4("Outside Major Trends"),
            p(
              "Top 5 outside-major groups ranked by absolute SCH change (not percentage), shown",
              " separately for lower and upper division. Ranking by absolute change ensures large",
              " programs driving real volume are surfaced over small programs with high % growth.",
              " Each entry shows avg SCH/term (last fall+spring average) and the SCH delta",
              " vs the same two-term window one year earlier.",
              " Percentages compare the most recent fall+spring pair against the same window",
              " 1, 2, or 4 years earlier. Summer is excluded from all comparisons.",
              " New Programs lists programs absent a year ago but now sending \u226530 avg SCH/term.",
              " Shown only when sufficient term history is available",
              " (4 terms for 1yr, 6 for 2yr, 10 for 4yr).",
              style = "color: #555; font-size: 0.88em; margin-bottom: 12px;"),
            fluidRow(
              column(6, render_sch_trend_cards(dr_ch_data()$tables$sch_major_trends_lower, "Lower Division")),
              column(6, render_sch_trend_cards(dr_ch_data()$tables$sch_major_trends_upper, "Upper Division"))
            ),
            # HIDDEN: instructor type charts disabled — HR data no longer updated
            # h4("Credit Hours by Instructor Type"),
            # p(
            #   "These charts show total SCH broken down by the job category of the instructor",
            #   " who taught the course. Categories are: ",
            #   tags$strong("Professor"), ", ",
            #   tags$strong("Associate Professor"), ", ",
            #   tags$strong("Assistant Professor"), " (all tenure-track), ",
            #   tags$strong("Lecturer"), " (non-tenure-track permanent), ",
            #   tags$strong("Term Teacher"), " (fixed-term appointment), ",
            #   tags$strong("TPT"), " (temporary part-time: adjuncts, visiting faculty, part-time instructors), and ",
            #   tags$strong("Grad"), " (graduate teaching assistants).",
            #   " This is not a per-instructor count \u2014 each bar shows the total SCH delivered by all",
            #   " instructors in that category that term.",
            #   style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            # h5("By Instructor Type and Course Level"),
            # p("SCH per term broken down by both instructor job category and course level",
            #   " (lower-division, upper-division, graduate). Each panel shows one course level;",
            #   " bars within a panel are grouped side-by-side by instructor type so you can",
            #   " compare who is teaching each tier of the curriculum.",
            #   style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            # plotlyOutput("chd_by_fac_facet_plot"),
            # h5("By Instructor Type (All Levels Combined)"),
            # p("Same data as above, collapsed across course levels into a single stacked bar per term.",
            #   " The total bar height equals total departmental SCH for that term.",
            #   " The color breakdown shows how SCH production is distributed across instructor types",
            #   " and whether that mix has shifted over time \u2014 for example, a growing TPT or Grad",
            #   " segment relative to tenure-track bars reflects a change in who is delivering instruction.",
            #   style = "color: #555; font-size: 0.88em; margin-bottom: 8px;"),
            # plotlyOutput("chd_by_fac_plot"),
            h4("College vs Department Comparison"),
            plotlyOutput("college_dept_dual_plot")
          )
        )
      ),
      tabPanel("Gen Ed",
        fluidRow(
          column(12,
            p("Where students who took gen ed courses in this department's subject codes ended up,",
              " based on their last recorded major. Source (left) = declared major at time of enrollment;",
              " target (right) = last recorded major.",
              " Pre-major students are labelled [Pre]. Flows below Min. flow size are collapsed into Other.",
              class = "text-muted")
          )
        ),
        fluidRow(
          column(3,
            {
              dept_subj_codes <- sort(unique(
                data_objects[["cedar_sections"]]$subject[
                  !is.na(data_objects[["cedar_sections"]]$department) &
                  data_objects[["cedar_sections"]]$department == data$dept_code
                ]
              ))
              selectizeInput("dr_ge_subject", "Subject Code",
                choices  = dept_subj_codes,
                selected = if (length(dept_subj_codes) == 1) dept_subj_codes else NULL,
                multiple = FALSE,
                options  = list(placeholder = "Select a subject…")
              )
            }
          ),
          column(2,
            checkboxInput("dr_ge_gen_ed_only", "Gen Ed courses only", value = TRUE)
          ),
          column(2,
            numericInput("dr_ge_min_n", "Min. flow size", value = 5, min = 1, max = 100)
          ),
          column(2,
            {
              all_terms  <- sort(unique(data_objects[["cedar_students"]]$term))
              hist_terms <- all_terms[all_terms < cedar_current_term]
              term_labels <- setNames(
                hist_terms,
                vapply(hist_terms, .term_label, cedar_current_term, FUN.VALUE = character(1))
              )
              selectizeInput("dr_ge_from_term", "From term",
                choices  = term_labels,
                selected = if (length(hist_terms)) min(hist_terms) else NULL
              )
            }
          ),
          column(2,
            {
              all_terms  <- sort(unique(data_objects[["cedar_students"]]$term))
              hist_terms <- all_terms[all_terms < cedar_current_term]
              term_labels <- setNames(
                hist_terms,
                vapply(hist_terms, .term_label, cedar_current_term, FUN.VALUE = character(1))
              )
              selectizeInput("dr_ge_to_term", "To term",
                choices  = term_labels,
                selected = if (length(hist_terms)) max(hist_terms) else NULL
              )
            }
          ),
          column(1,
            br(),
            actionButton("dr_ge_run", "Run", class = "btn-primary btn-sm")
          )
        ),
        fluidRow(
          column(12,
            uiOutput("dr_ge_sankey_ui")
          )
        )
      ),
      tabPanel("DFW",
        if (dfw_authenticated()) {
          # DFW content is visible only after authentication
          fluidRow(
            column(12,
              h3(paste("Department:", data$dept_name)),
              h4("DFW Grades Summary"),
              plotlyOutput("grades_summary_for_ld_abq_ea_plot")
            )
          )
        } else {
          # Access denied - show password gate using shared helper
          fluidRow(
            column(12,
              create_password_gate_ui("dfw_password_inline", "dfw_submit_inline_btn")
            )
          )
        }
      ),
      tabPanel("Debug", 
        fluidRow(
          column(6,
            h4("Available Tables:"),
            verbatimTextOutput("dept_debug_tables")
          ),
          column(6,
            h4("Available Plots:"),
            verbatimTextOutput("dept_debug_plots")
          )
        )
      )
    )
  })

  # ── Gen Ed Conversion (Department Profile tab) ────────────────────────────────
  observeEvent(input$dr_ge_run, {
    req(nzchar(input$dr_ge_subject %||% ""))
    dr_ge_data(NULL)

    from_term <- as.integer(input$dr_ge_from_term)
    to_term   <- as.integer(input$dr_ge_to_term)
    all_terms <- sort(unique(data_objects[["cedar_students"]]$term))
    sel_terms <- all_terms[all_terms >= from_term & all_terms <= to_term &
                            all_terms < cedar_current_term]

    opt <- list(
      subject_code   = input$dr_ge_subject,
      gen_ed_only    = isTRUE(input$dr_ge_gen_ed_only),
      gen_ed_courses = unlist(gen_ed_all),
      terms          = if (length(sel_terms) > 0) sel_terms else NULL,
      min_n          = as.integer(input$dr_ge_min_n)
    )

    result <- tryCatch(
      get_gen_ed_conversion(data_objects[["cedar_students"]],
                            data_objects[["cedar_programs"]], opt),
      error = function(e) { message("[server.R] dept gen ed conversion error: ", e$message); NULL }
    )
    dr_ge_data(result)
  })

  output$dr_ge_sankey_ui <- renderUI({
    result <- dr_ge_data()
    if (is.null(result)) {
      if (isTruthy(input$dr_ge_run) && input$dr_ge_run > 0)
        p("No qualifying students found for the selected filters.", style = "color: #888;")
      else
        p("Select a subject code and click Run.", style = "color: #888;")
    } else {
      m <- result$metadata
      undecl_note <- if (m$n_undeclared_end > 0)
        paste0(" | ", m$n_undeclared_end, " ended without a declared major — ",
               m$n_never_declared, " were never declared (not shown)")
      else ""
      tagList(
        p(paste0(result$n_students, " qualifying students", undecl_note,
                 " | subject: ", m$subject_code,
                 if (m$gen_ed_only) " (gen ed only)" else "",
                 " | min flow: ", m$min_n),
          style = "color: #888; font-size: 0.88em;"),
        plotlyOutput("dr_ge_sankey", height = "600px")
      )
    }
  })

  output$dr_ge_sankey <- renderPlotly({
    result <- dr_ge_data()
    req(!is.null(result), nrow(result$nodes) > 0, nrow(result$links) > 0)

    node_colors <- ifelse(result$nodes$is_pre, "#4e79a7", "#59a14f")

    plot_ly(
      type        = "sankey",
      orientation = "h",
      arrangement = "snap",
      node = list(
        label     = result$nodes$label,
        color     = node_colors,
        x         = result$nodes$x_pos,
        y         = result$nodes$y_pos,
        thickness = 20,
        line      = list(color = "black", width = 0.5)
      ),
      link = list(
        source = result$links$source,
        target = result$links$target,
        value  = result$links$value,
        label  = result$links$hover
      )
    ) %>%
      layout(
        title  = list(text = paste0("Gen Ed Conversion — ", result$metadata$subject_code,
                                    "  (n = ", result$n_students, ")"), x = 0),
        font   = list(size = 11),
        margin = list(l = 10, r = 10, t = 60, b = 10)
      )
  })

  # Map each plot name to its source reactiveVal.
  # Plots render NULL until their tab is clicked and data is computed.
  .tab_plot_map <- list(
    hc_progs_under_long_majors_plot              = "hc",
    hc_progs_under_long_minors_plot              = "hc",
    hc_progs_grad_long_majors_plot               = "hc",
    hc_progs_grad_long_minors_plot               = "hc",
    highest_total_enrl_plot                      = "enrl",
    highest_mean_enrl_plot                       = "enrl",
    highest_mean_histo_plot                      = "enrl",
    degree_summary_faceted_by_major_plot         = "deg",
    degree_summary_filtered_program_stacked_plot = "deg",
    chd_by_year_facet_subj_plot                  = "ch",
    chd_by_year_subj_plot                        = "ch",
    chd_by_year_plot                             = "ch",
    sch_outside_pct_lower_plot                   = "ch",
    sch_outside_pct_upper_plot                   = "ch",
    sch_dept_pct_lower_plot                      = "ch",
    sch_dept_pct_upper_plot                      = "ch",
    sch_top_majors_lower_plot                    = "ch",
    sch_top_majors_upper_plot                    = "ch",
    chd_by_fac_facet_plot                        = "ch",
    chd_by_fac_plot                              = "ch",
    college_dept_dual_plot                       = "ch",
    grades_summary_for_ld_abq_ea_plot            = "dfw"
  )

  lapply(names(.tab_plot_map), function(plot_name) {
    output[[plot_name]] <- renderPlotly({
      tab_data <- switch(.tab_plot_map[[plot_name]],
        hc   = dept_report_data(),
        enrl = dr_enrl_data(),
        deg  = dr_deg_data(),
        ch   = dr_ch_data(),
        dfw  = dr_dfw_data()
      )
      if (!is.null(tab_data) && plot_name %in% names(tab_data$plots))
        tab_data$plots[[plot_name]]
      else NULL
    })
  })

  # Full outside-major breakdown tables (all groups, ranked by total SCH)
  output$sch_outside_full_lower_table <- DT::renderDataTable({
    tbl <- dr_ch_data()$tables$sch_outside_full_lower
    if (is.null(tbl)) return(NULL)
    tbl %>%
      rename(`Outside Major` = major_name, `Total SCH` = total_hours) %>%
      mutate(`Total SCH` = round(`Total SCH`, 0))
  }, options = list(pageLength = 15, scrollX = TRUE, dom = "tip"), rownames = FALSE)

  output$sch_outside_full_upper_table <- DT::renderDataTable({
    tbl <- dr_ch_data()$tables$sch_outside_full_upper
    if (is.null(tbl)) return(NULL)
    tbl %>%
      rename(`Outside Major` = major_name, `Total SCH` = total_hours) %>%
      mutate(`Total SCH` = round(`Total SCH`, 0))
  }, options = list(pageLength = 15, scrollX = TRUE, dom = "tip"), rownames = FALSE)

  # Render the specific headcount table
  output$hc_progs_under_long_majors <- DT::renderDataTable({
    data <- dept_report_data()
    if (!is.null(data) && "tables" %in% names(data) && "hc_progs_under_long_majors" %in% names(data$tables)) {
      data$tables[["hc_progs_under_long_majors"]]
      }
    }, options = list(pageLength = 15, scrollX = TRUE))

  # Debug outputs to see what's available
  output$dept_debug_tables <- renderPrint({
    data <- dept_report_data()
    if (!is.null(data) && "tables" %in% names(data)) {
      cat("Table names:\n")
      print(names(data$tables))
      cat("\nTable structures:\n")
      for(i in 1:min(3, length(data$tables))) {
        cat(paste("\n", names(data$tables)[i], ":\n"))
        print(str(data$tables[[i]]))
      }
    } else {
      "No tables found"
    }
  })

  output$dept_debug_plots <- renderPrint({
    data <- dept_report_data()
    if (!is.null(data) && "plots" %in% names(data)) {
      cat("Plot names:\n")
      print(names(data$plots))
      cat("\nPlot types:\n")
      for(i in 1:min(3, length(data$plots))) {
        cat(paste("\n", names(data$plots)[i], ": ", class(data$plots[[i]])[1], "\n"))
      }
    } else {
      "No plots found"
    }
  })

  #########################
  ##### DATA & USAGE TAB #####
  #########################

  # ── Tab 1: Data Summary (uses pre-computed data from global.R) ────────────
  # Data Status Table - uses pre-computed cedar_data_summary from global.R
  output$data_status_table <- DT::renderDataTable({
    cedar_debug("[server.R] DATA STATUS TABLE rendering")
    tryCatch({
      display_terms <- cedar_data_summary$display_terms
      term_cols <- vapply(display_terms, .term_label,
                          current_term = cedar_current_term,
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
        DT::datatable(data.frame(Message = "No data loaded"), rownames = FALSE)
      } else {
        display_data <- do.call(rbind, rows)
        colnames(display_data) <- c("Dataset", "Rows", term_cols)
        curr_col <- .term_label(cedar_current_term, cedar_current_term)
        DT::datatable(display_data,
                      rownames = FALSE,
                      class = "compact",
                      options = list(dom = "t", paging = FALSE, scrollX = TRUE)) %>%
          DT::formatStyle(curr_col, fontWeight = "bold")
      }
    }, error = function(e) {
      message("[server.R] *** ERROR in data_status_table: ", e$message, " ***")
      DT::datatable(data.frame(Error = paste("Error loading data status:", e$message)), rownames = FALSE)
    })
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
        style = "text-align: center; padding: 20px;",
        p("Click 'Refresh' to load usage overview")
      ))
    }

    if ("message" %in% names(overview)) {
      return(div(
        style = "padding: 20px;",
        p(overview$message)
      ))
    }

    # Build summary text
    summary_html <- tagList()

    if (!is.null(overview$date_range)) {
      summary_html <- tagList(
        summary_html,
        p(strong("Date Range: "), format(overview$date_range$start, "%Y-%m-%d"), " to ", format(overview$date_range$end, "%Y-%m-%d"))
      )
    }

    if (!is.null(overview$summary_text) && length(overview$summary_text) > 0) {
      summary_html <- tagList(
        summary_html,
        tags$ul(
          lapply(overview$summary_text, function(item) tags$li(item))
        )
      )
    } else {
      summary_html <- tagList(summary_html, p("No usage data available for this date range"))
    }

    div(style = "padding: 10px;", summary_html)
  })

  # Tab usage table
  output$tab_usage_table <- DT::renderDataTable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$tab_usage) || nrow(overview$tab_usage) == 0) {
      return(DT::datatable(data.frame(Message = "No tab usage data available"), rownames = FALSE))
    }

    DT::datatable(overview$tab_usage,
                  colnames = c("Tab/Feature", "Usage Count"),
                  rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE))
  })

  # Department reports table
  output$dept_reports_table <- DT::renderDataTable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$dept_reports) || nrow(overview$dept_reports) == 0) {
      return(DT::datatable(data.frame(Message = "No department reports data available"), rownames = FALSE))
    }

    DT::datatable(overview$dept_reports,
                  colnames = c("Department", "Report Count"),
                  rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE))
  })

  # Course reports table
  output$course_reports_table <- DT::renderDataTable({
    overview <- usage_overview_data()

    if (is.null(overview) || is.null(overview$course_reports) || nrow(overview$course_reports) == 0) {
      return(DT::datatable(data.frame(Message = "No course reports data available"), rownames = FALSE))
    }

    DT::datatable(overview$course_reports,
                  colnames = c("Course", "Report Count"),
                  rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE))
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
        rt <- d$report_type %||% "report"
        if (!is.null(p$department))  return(paste0(rt, ": ", p$department))
        if (!is.null(p$course))      return(paste0(rt, ": ", p$course))
        if (!is.null(p$dept))        return(paste0(rt, ": ", p$dept))
        if (!is.null(p$college))     return(paste0(rt, ": ", p$college))
        return(rt)
      }
      if (event_type == "tab_change")   return(d$tab   %||% details_str)
      if (event_type == "data_filter")  return(d$filter_type %||% details_str)
      if (event_type == "session_start") {
        return(paste0(d$url %||% "", if (!is.null(d$port) && nchar(d$port) > 0) paste0(":", d$port) else ""))
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
            h4(stats$total_sessions),  p("Sessions", style = "color:#888; margin:0;"))),
          column(3, div(class = "well well-sm text-center",
            h4(stats$total_session_starts), p("Session starts", style = "color:#888; margin:0;"))),
          column(3, div(class = "well well-sm text-center",
            h4(if (!is.null(stats$reports_generated)) stats$reports_generated else 0),
            p("Reports generated", style = "color:#888; margin:0;"))),
          column(3, div(class = "well well-sm text-center",
            h4(stats$error_count),  p("Errors", style = "color:#888; margin:0;")))
        )
      )
    }, error = function(e) p(paste("Error loading stats:", e$message), style = "color:red;"))
  })

  # Event log table — shows all events, rendered reactively (no refresh needed)
  output$feature_usage_table <- DT::renderDataTable({
    cedar_debug("[server.R] FEATURE USAGE TABLE rendering")
    tryCatch({
      start_date <- if (!is.null(input$feature_start_date)) as.character(input$feature_start_date) else as.character(Sys.Date())
      end_date   <- if (!is.null(input$feature_end_date))   as.character(input$feature_end_date)   else as.character(Sys.Date())

      logs <- read_logs(start_date, end_date)
      cedar_debug("[server.R] Read ", nrow(logs), " log entries for feature usage table")

      if (nrow(logs) == 0) {
        return(DT::datatable(data.frame(Message = "No log data found for this date range"), rownames = FALSE))
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

      DT::datatable(display,
                    rownames = FALSE,
                    class = "compact",
                    options = list(pageLength = 20, scrollX = TRUE, dom = "tip"))
    }, error = function(e) {
      message("[server.R] *** ERROR in feature_usage_table: ", e$message, " ***")
      DT::datatable(data.frame(Error = paste("Error loading data:", e$message)), rownames = FALSE)
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

  output$dept_pt_plot <- renderPlot({
    req(!is.null(dr_demo_data()))
    dr_demo_data()
  })

  # =============================================================================
  # Pathways tab — cohort-aware curriculum analytics (Shiny module)
  # =============================================================================
  pathwaysServer("pathways", cedar_students, cedar_programs, degrees = cedar_degrees,
                 cedar_grades = cedar_grades, cedar_next_term = cedar_next_term,
                 lookups = data_objects[["cedar_lookups"]])

  # =============================================================================
  # Healthcare tab — enrollment what-if analysis (Shiny module)
  # =============================================================================
  healthWhatIfServer("health_whatif",
                     programs = cedar_programs,
                     students = cedar_students,
                     sections = cedar_sections)

  # =============================================================================
  # Retention tab — institution-level retention by course (Shiny module)
  # =============================================================================
  retentionServer("retention", students = cedar_students)

} # end server
