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
  cedar_sections <- data_objects[["cedar_sections"]]
  cedar_students <- data_objects[["cedar_students"]]
  cedar_programs <- data_objects[["cedar_programs"]]
  cedar_degrees <- data_objects[["cedar_degrees"]]
  cedar_faculty <- data_objects[["cedar_faculty"]]
  forecasts <- data_objects[["forecasts"]]

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

  
  # Parse URL query parameters and update inputs dynamically
  # Use observeEvent with once=TRUE to only trigger on initial page load
  observeEvent(session$clientData$url_search, {
    query <- parseQueryString(session$clientData$url_search)
    
    # Only process if there are actual query parameters
    if (length(query) == 0) return()
    
    # Map URL-friendly tab names to actual tab titles
    tab_aliases <- list(
      "seatfinder" = "Seatfinder",
      "waitlists" = "Waitlists",
      "enrollment" = "Enrollment",
      "headcount" = "Headcount",
      "course-reports" = "Course Reports",
      "department-reports" = "Department Reports"
    )
    
    # Switch to specific tab if requested
    tab_param <- tolower(query$tab)  # Make case-insensitive
    tab_name <- if (!is.null(tab_param) && !is.null(tab_aliases[[tab_param]])) {
      tab_aliases[[tab_param]]
    } else {
      query$tab  # Use as-is if not in aliases
    }
    
    # Only update navbar and close dropdowns if we have a tab parameter
    if (!is.null(tab_name)) {
      updateNavbarPage(session, "main_navbar", selected = tab_name)
    }
    
    # Map tab names to their input prefixes
    tab_prefixes <- list(
      "Seatfinder" = "sf",
      "Waitlists" = "wl",
      "Enrollment" = "enrl",
      "Headcount" = "hc",
      "Course Reports" = "cr",
      "Department Reports" = "dr"
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
      
      param_value <- query[[param_name]]
      
      # Try to update the input
      tryCatch({
        updateSelectizeInput(session, input_id, selected = param_value)
      }, error = function(e) {
        # Input doesn't exist, that's OK
      })
    }
    
    # Auto-run functionality if requested
    if (!is.null(query$autorun) && query$autorun == "true" && !is.null(prefix)) {
      button_id <- paste0(prefix, "_button")
      isolate({
        tryCatch({
          updateActionButton(session, button_id, label = "Loading...")
        }, error = function(e) {
          # Button doesn't exist
        })
      })
    }
  }, once = TRUE) # end URL parameter parsing - only run once on page load


  # Helper function for consistent error logging and notifications
  handle_error <- function(e, context = "general", notification_id = NULL) {
    # Extract error message - try multiple fields
    error_msg <- if(!is.null(e$message) && nzchar(e$message)) {
      e$message
    } else if(!is.null(e$parent$message) && nzchar(e$parent$message)) {
      e$parent$message
    } else {
      # Fall back to converting the error object to string
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
    message("[server.R] User's last seen version: ", last_seen)
    
    # Get current latest version from changelog
    changelog <- load_changelog()
    if (length(changelog) == 0) {
      message("[server.R] No changelog entries found, skipping modal")
      return()
    }
    
    current_version <- changelog[[1]]$version
    message("[server.R] Current CEDAR version: ", current_version)
    
    # Show modal if user hasn't seen this version yet
    if (last_seen != current_version) {
      message("[server.R] New version detected, showing changelog modal")
      
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
      
      message("[server.R] Modal shown and sent version ", current_version, " to client")
    } else {
      message("[server.R] User has already seen version ", current_version, ", skipping modal")
    }
  }) # end observeEvent for welcome modal


  # configure selectize inputs
  updateSelectizeInput(session, 'enrl_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'enrl_inst', choices = sort(unique(cedar_sections$instructor_name)), server = TRUE)
  updateSelectizeInput(session, 'cr_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'wl_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)
  updateSelectizeInput(session, 'rs_course', choices = sort(unique(cedar_sections$subject_course)), server = TRUE)



  #####################
  ##### HEADCOUNT #####
  #####################

  # Helper function to update downstream filters (major/minor/concentration)
  update_downstream_filters <- function(filtered_data) {
    # Update major choices (CEDAR: program_name filtered by program_type)
    available_majors <- filtered_data %>%
      filter(!is.na(program_name), program_name != "",
             program_type %in% c("Major", "Second Major")) %>%
      distinct(program_name) %>%
      arrange(program_name) %>%
      pull(program_name)

    updateSelectizeInput(session, "hc_major",
                        choices = available_majors,
                        selected = NULL,
                        server = TRUE)

    # Update minor choices (CEDAR: program_name filtered by program_type)
    available_minors <- filtered_data %>%
      filter(!is.na(program_name), program_name != "",
             program_type %in% c("First Minor", "Second Minor")) %>%
      distinct(program_name) %>%
      arrange(program_name) %>%
      pull(program_name)

    updateSelectizeInput(session, "hc_minor",
                        choices = available_minors,
                        selected = NULL,
                        server = TRUE)

    # Update concentration choices (CEDAR: program_name filtered by program_type)
    available_concentrations <- filtered_data %>%
      filter(!is.na(program_name), program_name != "",
             program_type %in% c("First Concentration", "Second Concentration", "Third Concentration")) %>%
      distinct(program_name) %>%
      arrange(program_name) %>%
      pull(program_name)

    updateSelectizeInput(session, "hc_conc",
                        choices = available_concentrations,
                        selected = NULL,
                        server = TRUE)
  } # end update_downstream_filters function


  # College changes should reset department and downstream filters (hierarchical filtering)
  observeEvent(input$hc_college, {
    if (cedar_logging_enabled) {
      write_log("INFO", "data_filter", "headcount_college", session$token, list(
        college = input$hc_college
      ))
    }

    # Filter data by college first
    filtered_data <- cedar_programs
    if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
      filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
    }

    # Update department choices based on selected college
    available_departments <- filtered_data %>%
      filter(!is.na(department), department != "") %>%
      distinct(department) %>%
      arrange(department) %>%
      pull(department)

    updateSelectizeInput(session, "hc_dept",
                        choices = available_departments,
                        selected = NULL,
                        server = TRUE)

    # Update all downstream filters
    update_downstream_filters(filtered_data)
  }, ignoreInit = FALSE) # end observeEvent for COLLEGE


# Department changes should update downstream filters (major/minor/concentration)
observeEvent(input$hc_dept, {
  if (cedar_logging_enabled) {
    write_log("INFO", "data_filter", "headcount_dept", session$token, list(
      dept = input$hc_dept
    ))
  }

  # Filter by college and department
  filtered_data <- cedar_programs
  if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
    filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
  }
  if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
    filtered_data <- filtered_data %>% filter(department %in% input$hc_dept)
  }

  # Update downstream program filters
  update_downstream_filters(filtered_data)

}, ignoreInit = TRUE) # en



  # Initialize headcount filter choices with all available options
  updateSelectizeInput(session, 'hc_college',
                      choices = sort(unique(cedar_programs$student_college[!is.na(cedar_programs$student_college) & cedar_programs$student_college != ""])),
                      server = TRUE)
  updateSelectizeInput(session, 'hc_dept',
                      choices = sort(unique(cedar_programs$department[!is.na(cedar_programs$department) & cedar_programs$department != ""])),
                      server = TRUE)
  updateSelectizeInput(session, 'hc_campus',
                      choices = sort(unique(cedar_programs$student_campus[!is.na(cedar_programs$student_campus) & cedar_programs$student_campus != ""])),
                      server = TRUE)
  updateSelectizeInput(session, 'hc_major',
                      choices = sort(unique(cedar_programs$program_name[!is.na(cedar_programs$program_name) & cedar_programs$program_type %in% c("Major", "Second Major")])),
                      server = TRUE)
  updateSelectizeInput(session, 'hc_minor',
                      choices = sort(unique(cedar_programs$program_name[!is.na(cedar_programs$program_name) & cedar_programs$program_type %in% c("First Minor", "Second Minor")])),
                      server = TRUE)
  updateSelectizeInput(session, 'hc_conc',
                      choices = sort(unique(cedar_programs$program_name[!is.na(cedar_programs$program_name) & cedar_programs$program_type %in% c("First Concentration", "Second Concentration", "Third Concentration")])),
                      server = TRUE)

  
  hc_data <- eventReactive(input$hc_button, {

    # Log headcount button click
    log_report_generation(session, "headcount", list(
      college = input$hc_college,
      dept = input$hc_dept,
      campus = input$hc_campus,
      major = input$hc_major,
      minor = input$hc_minor,
      concentration = input$hc_conc
    ))

    message("[server.R] Update button pressed!")
    showNotification("Counting heads...", type = "message", duration = 3)

    if (is.null(cedar_programs)) {
      showNotification("cedar_programs data is NULL!", type = "error", duration = 5)
      message("[server.R] cedar_programs is NULL!")
      return(NULL)
    }

    message("[server.R] Counting heads with major:", toString(input$hc_major),
            " minor:", toString(input$hc_minor),
            " concentration:", toString(input$hc_conc))


    opt <- list()
    opt[["shiny"]] <- TRUE
    opt[["college"]] <- input$hc_college
    opt[["dept"]] <- input$hc_dept
    opt[["campus"]] <- input$hc_campus
    opt[["major"]] <- input$hc_major
    opt[["minor"]] <- input$hc_minor
    opt[["concentration"]] <- input$hc_conc

    result <- tryCatch({  
      get_headcount(cedar_programs, opt)
    }, error = function(e) {
      handle_error(e, "[server.R] headcount_calculation")
      return(NULL)
    })

    result
  }, ignoreNULL = TRUE, ignoreInit = TRUE)


  hc_plots <- reactive({
    data <- hc_data()
    req(data)
    make_headcount_plots_by_level(data)
  })

  output$hc_undergrad_plot <- renderPlotly({  
    hc_plots()$undergrad
  })

  output$hc_grad_plot <- renderPlotly({  
    hc_plots()$graduate
  })




#####################
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
  message("getting enrollment data with options: ", toString(opt))
  
  # Get unfiltered data first to detect if filtering eliminated everything
  opt_unfiltered <- opt
  opt_unfiltered[["enrl_min"]] <- NULL
  opt_unfiltered[["enrl_max"]] <- NULL
  data_unfiltered <- get_enrl(cedar_sections, opt_unfiltered)
  rows_before_enrl_filter <- nrow(data_unfiltered)
  
  data <- get_enrl(cedar_sections, opt)
  
  message("[server.R] get_enrl() returned ", nrow(data), " rows (", rows_before_enrl_filter, " before enrollment filter)")
  if (nrow(data) > 0) {
    message("[server.R] Sample courses returned: ", paste(unique(data$subject_course)[1:min(5, length(unique(data$subject_course)))], collapse=", "))
  }

  # Detect if enrollment filter eliminated all data
  filter_warning <- ""
  if (nrow(data) == 0 && rows_before_enrl_filter > 0 && (!is.null(input$enrl_min) || !is.null(input$enrl_max))) {
    filter_warning <- paste0("⚠️ No sections matched your enrollment filter (min: ", input$enrl_min, ", max: ", input$enrl_max, "). ",
                            "There were ", rows_before_enrl_filter, " sections before filtering. ",
                            "For future/proposed schedules, try setting Min Enrollment to 0.")
    message("[server.R] FILTER WARNING: ", filter_warning)
  }

  # Filter students to only those in the filtered sections (by CRN)
  # This ensures student data matches the filtered course sections
  filtered_crns <- if(nrow(data) > 0) unique(data$crn) else character(0)
  message("[server.R] Filtered to ", length(filtered_crns), " CRNs")
  filtered_students <- cedar_students[cedar_students$crn %in% filtered_crns, ]
  message("[server.R] Filtered students to ", nrow(filtered_students), " rows for class list stats")
  cl_data <- calc_cl_enrls(filtered_students)


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
        data <- data %>% filter(is.na(XlistRole) | XlistRole == "home")
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
          data <- data %>% filter(is.na(XlistRole) | XlistRole == "home")
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



  observeEvent(input$enrl_dept, {
    # Log enrollment department filter
    log_data_filter(session, "enrollment_dept", input$enrl_dept)

    deptsToShow = cedar_sections %>%
      filter(department %in% input$enrl_dept) %>% ungroup() %>% select(subject_course) %>% arrange(subject_course)
    updateSelectInput(session, "enrl_course", choices = deptsToShow)
  })
  
  

  #########################################
  #    LOW ENROLLMENT ALERT DASHBOARD    #
  #########################################

  # Mode tracker: "alerts" for current/past terms, "concerns" for future terms
  enrl_mode <- reactiveVal("alerts")

  # Reactive for low enrollment course data - uses main enrollment filters.
  # Fetches all courses below the highest threshold in one pass, then level-specific
  # reactives filter down to each section's own threshold.
  # When a future term is selected, switches to "concerns" mode using historical averages.
  low_enrl_data <- eventReactive(input$enrl_button, {
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
    opt$im <- input$enrl_im
    opt$pt <- input$enrl_pt
    opt$gen_ed <- input$enrl_gen_ed
    opt$inst <- input$enrl_inst
    opt$course <- input$enrl_course

    # --- Detect future vs current/past terms ---
    selected_terms <- input$enrl_term
    # Check each numeric term code against cedar_current_term from config
    future_flags <- sapply(selected_terms, function(t) {
      if (grepl("^\\d+$", t)) as.integer(t) > cedar_current_term else FALSE
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
      message("[server.R] Future term detected — switching to concerns mode")
      result <- get_enrollment_concerns(cedar_sections, opt, n_history_terms = 4)

      if (is.null(result) || nrow(result) == 0) {
        message("[server.R] No courses found on future schedule")
        low_enrl_duration <- end_report_timer(low_enrl_timer)
        removeNotification("low_enrl_loading")
        return(NULL)
      }

      message("[server.R] Enrollment concerns ready: ", nrow(result), " courses")
      low_enrl_duration <- end_report_timer(low_enrl_timer)
      removeNotification("low_enrl_loading")
      showNotification(paste("Concerns analysis ready (", round(low_enrl_duration, 1), "s)"),
                       type = "message", duration = 5)
      return(result)
    }

    # =====================================================================
    # CURRENT/PAST TERM: Actual low enrollment alerts (existing logic)
    # =====================================================================

    # Use the highest threshold so all potentially low-enrolled courses are included;
    # each level-specific reactive then applies its own threshold.
    max_threshold <- max(
      input$low_enrl_threshold_lower,
      input$low_enrl_threshold_upper,
      input$low_enrl_threshold_split,
      input$low_enrl_threshold_grad,
      na.rm = TRUE
    )

    message("[server.R] Fetching all low enrollment courses (max threshold: ", max_threshold, ")")
    all_low <- get_low_enrollment_courses(cedar_sections, opt, threshold = max_threshold)

    if (is.null(all_low) || nrow(all_low) == 0) {
      message("[server.R] No low enrollment courses found")
      return(NULL)
    }

    # Respect min enrollment filter — applied to total_enrl (combined XL enrollment),
    # not section-level enrolled. Default min is 1, excluding zero-enrollment sections
    # which typically represent forced-distribution or pre-open-registration artifacts.
    if (!is.null(input$enrl_min) && !is.na(input$enrl_min)) {
      min_enrl_val <- as.integer(input$enrl_min)
      all_low <- all_low %>% filter(total_enrl >= min_enrl_val)
      message("[server.R] After min enrl filter (total_enrl >= ", min_enrl_val, "): ", nrow(all_low), " rows")
    }

    if (nrow(all_low) == 0) return(NULL)

    # Count active home sections and total enrollment per course/term for context.
    # Uses crosslist_code to avoid double-counting crosslisted partner rows.
    # A crosslist_code of "0" means it's not crosslisted (primary section).
    # Groups by term + subject_course + course_title + campus to differentiate
    # topics courses with same subject_course but different titles.
    section_counts <- cedar_sections %>%
      filter(status == "A", crosslist_code == "0") %>%
      group_by(term, subject_course, course_title, campus) %>%
      summarize(
        n_sections = n(),
        course_enrl = sum(total_enrl, na.rm = TRUE),
        .groups = "drop"
      )

    all_low <- all_low %>%
      left_join(section_counts, by = c("term", "subject_course", "course_title", "campus")) %>%
      mutate(
        n_sections = coalesce(n_sections, 1L),
        course_enrl = coalesce(course_enrl, total_enrl)
      )

    # Determine the current term for excluding from history
    current_term <- max(all_low$term, na.rm = TRUE)

    # Add enrollment history — but skip for large result sets since rowwise is slow
    # (each row triggers a full-table filter of cedar_sections)
    history_limit <- 500
    if (nrow(all_low) <= history_limit) {
      message("[server.R] Adding enrollment history for ", nrow(all_low), " courses...")
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
      message("[server.R] Skipping enrollment history (", nrow(all_low),
              " rows exceeds limit of ", history_limit, ")")
      all_low$history_text <- NA_character_
      showNotification(
        paste0("Enrollment history skipped (", nrow(all_low),
               " courses exceed ", history_limit, " row limit). ",
               "Add filters to narrow results and enable history."),
        type = "warning", duration = 8
      )
    }

    message("[server.R] Low enrollment base data ready: ", nrow(all_low), " rows")

    low_enrl_duration <- end_report_timer(low_enrl_timer)
    removeNotification("low_enrl_loading")
    showNotification(paste("Alert data ready (", round(low_enrl_duration, 1), "s)"),
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
      # Alerts mode: show courses with actual enrollment below threshold
      if (is_split_filter) {
        data %>% filter(is_split == TRUE, total_enrl < threshold)
      } else {
        data %>% filter(level == level_val, !is_split, total_enrl < threshold)
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
    req(low_enrl_data())
    base <- low_enrl_data()

    if (nrow(base) == 0) {
      no_results_msg <- if (enrl_mode() == "concerns") {
        "No courses found on the future schedule with these filters."
      } else {
        "No courses were found with enrollment below any threshold."
      }
      return(div(
        class = "alert alert-success",
        style = "margin: 20px; padding: 20px; text-align: center;",
        icon("check-circle", style = "font-size: 2em; margin-bottom: 10px;"),
        h4("No Results", style = "margin: 10px 0;"),
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
        class = "alert alert-success",
        style = "margin: 20px; padding: 20px; text-align: center;",
        icon("check-circle", style = "font-size: 2em; margin-bottom: 10px;"),
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
            div(class = "well text-center",
                style = "background-color: #f8d7da; border-color: #f5c6cb;",
                h4(critical, style = "margin: 10px 0;"),
                p("Historically Low (< 50%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #fff3cd; border-color: #ffeeba;",
                h4(warning_count, style = "margin: 10px 0;"),
                p("Borderline (50\u201375%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #d1ecf1; border-color: #bee5eb;",
                h4(watch, style = "margin: 10px 0;"),
                p("Watch (75\u2013100%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #d4edda; border-color: #c3e6cb;",
                h4(buffer, style = "margin: 10px 0;"),
                p("Near Threshold (\u2265 100%)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #e9ecef; border-color: #dee2e6;",
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
      # Alerts mode: severity based on total_enrl (existing logic)
      combined <- combined %>%
        mutate(
          severity = case_when(
            total_enrl < .threshold * 0.5  ~ "critical",
            total_enrl < .threshold * 0.75 ~ "warning",
            TRUE                            ~ "watch"
          )
        )

      critical      <- sum(combined$severity == "critical")
      warning_count <- sum(combined$severity == "warning")
      watch         <- sum(combined$severity == "watch")
      total_courses <- nrow(combined)
      total_students <- sum(combined$total_enrl, na.rm = TRUE)
      avg_enrollment <- round(mean(combined$total_enrl, na.rm = TRUE), 1)

      div(
        class = "row",
        style = "margin-bottom: 20px;",
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #f8d7da; border-color: #f5c6cb;",
                h4(critical, style = "margin: 10px 0;"),
                p("Critical (< 50% of threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #fff3cd; border-color: #ffeeba;",
                h4(warning_count, style = "margin: 10px 0;"),
                p("Warning (50\u201375% of threshold)", style = "margin: 5px 0;")
            )
        ),
        div(class = "col-sm-2",
            div(class = "well text-center",
                style = "background-color: #d1ecf1; border-color: #bee5eb;",
                h4(watch, style = "margin: 10px 0;"),
                p("Watch (75\u201399% of threshold)", style = "margin: 5px 0;")
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
          Enrolled = total_enrl,
          `Course Total` = course_enrl,
          `Prior History` = history_text
        ) %>%
        arrange(Enrolled)
      center_targets <- c(3, 6, 7, 8, 9)  # Sect#, Term, Sects, Enrolled, Course Total
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
          Enrolled = total_enrl,
          `Course Total` = course_enrl,
          `Prior History` = history_text
        ) %>%
        arrange(Enrolled)
      center_targets <- c(3, 5, 6, 7, 8)  # Sect#, Term, Sects, Enrolled, Course Total
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
      .style_enrl_col(enrl_col, threshold)
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
          `Hist Avg` = avg_enrl_display,
          Trend = trend,
          `# Terms` = n_prior_terms,
          `Prior History` = history_text
        ) %>%
        arrange(`Hist Avg`)
      center_targets <- c(5, 6, 7, 8)  # Sects, Hist Avg, Trend, # Terms
      enrl_col <- "Hist Avg"
    } else {
      display_data <- data %>%
        select(
          Campus = campus,
          Department = department,
          Course = subject_course,
          Title = course_title,
          Sects = n_sections,
          `Hist Avg` = avg_enrl_display,
          Trend = trend,
          `# Terms` = n_prior_terms,
          `Prior History` = history_text
        ) %>%
        arrange(`Hist Avg`)
      center_targets <- c(4, 5, 6, 7)  # Sects, Hist Avg, Trend, # Terms
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

  output$low_enrl_table_lower <- DT::renderDataTable({
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_lower(), input$low_enrl_threshold_lower)
  })

  output$low_enrl_table_upper <- DT::renderDataTable({
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_upper(), input$low_enrl_threshold_upper)
  })

  output$low_enrl_table_split <- DT::renderDataTable({
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_split(), input$low_enrl_threshold_split, show_split_info = TRUE)
  })

  output$low_enrl_table_grad <- DT::renderDataTable({
    req(low_enrl_data())
    .render_enrl_dt(low_enrl_grad(), input$low_enrl_threshold_grad)
  })

  # Must explicitly disable suspendWhenHidden (default is TRUE in Shiny).
  # Shiny's visibility detection is unreliable inside nested navset tabs — DTs
  # suspended on button press never unsuspend when the outer tab is clicked.
  # With FALSE, outputs render on button press and display immediately when
  # the user navigates to the Low Enrollment tab.
  outputOptions(output, "low_enrl_table_lower", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_upper", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_split", suspendWhenHidden = FALSE)
  outputOptions(output, "low_enrl_table_grad",  suspendWhenHidden = FALSE)


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
      message("Course changed from ", cached_data$course_code, " to ", input$cr_course, ". Clearing cached data.")
      course_report_data(NULL)
    }
  }, ignoreInit = TRUE)

  # Log rollcall campus filter changes
  observeEvent(input$cr_rollcall_campus, {
    log_data_filter(session, "rollcall_campus", input$cr_rollcall_campus)
  }, ignoreInit = TRUE)

  # Helper function for campus filtering
  get_campus_filter <- function() {
    if (!is.null(input$cr_rollcall_campus) && length(input$cr_rollcall_campus) > 0) {
      return(list(
        column = "campus",  # CEDAR column name
        values = input$cr_rollcall_campus
      ))
    }
    return(NULL)
  }
  
  # Helper function for rollcall pie charts (fall/spring)
  # Reduces 40+ lines of repeated code to single function calls
  render_rollcall_pie_plot <- function(data_table_name, fill_column, term_type, plot_name) {
    data <- course_report_data()
    message("[server.R] ", plot_name, " renderer called")
    
    if (!is.null(data) && "tables" %in% names(data) && data_table_name %in% names(data$tables)) {
      
      # Get campus filter for plot generation
      campus_filter <- get_campus_filter()
      if (!is.null(campus_filter)) {
        message("[server.R] Regenerating plots with campus filter for ", plot_name, ": ", paste(campus_filter$values, collapse = ", "))
      } else {
        message("[server.R] No campus filter applied for ", plot_name)
      }
      
      # Regenerate plots with campus filtering
      plots <- plot_rollcall_with_consistent_colors(
        data$tables[[data_table_name]], 
        fill_column, 
        filter_column = campus_filter
      )
      
      if (!is.null(plots[[term_type]])) {
        message("[server.R] Returning filtered ", plot_name)
        return(plots[[term_type]])
      }
    }
    
    message("[server.R] ", plot_name, " not found")
    return(NULL)
  }
  
  # Helper function for rollcall time series plots
  # Reduces 25+ lines of repeated code to single function calls
  render_rollcall_time_plot <- function(data_table_name, fill_column, plot_name) {
    data <- course_report_data()
    message("[server.R] ", plot_name, " renderer called")
    
    if (!is.null(data) && "tables" %in% names(data) && data_table_name %in% names(data$tables)) {
      
      # Get campus filter for plot generation
      campus_filter <- get_campus_filter()
      if (!is.null(campus_filter)) {
        message("[server.R] Regenerating time series with campus filter for ", plot_name, ": ", paste(campus_filter$values, collapse = ", "))
      }
      
      # Check if plot_time_series function accepts filter_column parameter
      # For now, apply filter to data since plot_time_series may not have filter support yet
      rollcall_data <- data$tables[[data_table_name]]
      if (!is.null(campus_filter)) {
        rollcall_data <- rollcall_data %>% 
          filter(!!sym(campus_filter$column) %in% campus_filter$values)
      }
      
      # Generate time series plot
      time_plot <- plot_time_series(rollcall_data, fill_column = fill_column)
      if (!is.null(time_plot)) {
        message("[server.R] Returning filtered ", plot_name)
        return(time_plot)
      }
    }
    
    message("[server.R] ", plot_name, " not found")
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
        message("[server.R] Applied campus filter for ", table_name, ": ", paste(campus_filter$values, collapse = ", "))
      }
      
      return(table_data)
    }
    return(NULL)
  }


  # Course Report Interactive Generation 
  observeEvent(input$cr_generate_button, {
    req(input$cr_course)
    if (input$cr_course == "") {
      showNotification("Please select a course.", type = "error")
      return()
    }
    
    # Clear cached course report data to force fresh generation
    message("[server.R] Clearing cached course report data for fresh generation...")
    course_report_data(NULL)
    
    # Log course report generation
    log_report_generation(session, "course_report", list(
      course = input$cr_course,
      skip_forecast = input$cr_skip_forecast
    ))
    
    # Show loading notification with average time
    status_message <- create_timing_status_message("course_report", "Generating interactive course")
    showNotification(status_message, type = "default", duration = NULL, id = "course_loading")
    
    # Start timing
    timer <- start_report_timer("course_report", list(
      course = input$cr_course,
      skip_forecast = input$cr_skip_forecast
    ))
    
    tryCatch({
      opt <- list()
      opt[["shiny"]] <- TRUE
      opt[["course"]] <- input$cr_course
      opt[["skip_forecast"]] <- input$cr_skip_forecast
      # DO NOT set course_campus here - it would filter ALL data generation
      # Campus filtering is applied only at the display level for rollcall plots
      
      # Generate course data using the data preparation function
      message("[server.R] Generating interactive report data for: ", input$cr_course)
      c_params <- create_course_report_data(data_objects, opt)
      gc() # Clean up after report generation
      message("[server.R] Interactive course report data generated!")
      
      # End timing and log
      duration_sec <- end_report_timer(timer)
      
      # Store the data in the reactive value
      message("[server.R] Storing course report data in reactive value...")
      course_report_data(c_params)
      
      removeNotification("course_loading")
      showNotification(paste("Interactive course report generated successfully! (", round(duration_sec, 1), "s)"), 
                      type = "message", duration = 5)
      
    }, error = function(e) {
      handle_error(e, "course_report", "course_loading")
      
      # End timer even on error
      tryCatch(end_report_timer(timer), error = function(timer_error) {
        message("[server.R] Error ending timer: ", timer_error$message)
      })
    })
  }, ignoreInit = TRUE) #end observeEvent for cr_button

  # Course HTML Report Generation/Download (via RMarkdown)
  output$cr_report_html_download <- downloadHandler(
    filename = function() {
      paste0(gsub(" ", "_", input$cr_course), ".html")
    },
    content = function(file) {
      req(input$cr_course)
      if (input$cr_course == "") {
        showNotification("Please select a course.", type = "error")
        return()
      }
      
      # Log download request
      log_download(session, "course_report_html", paste0(input$cr_course, ".html"))
      
      # Show loading notification
      status_message <- create_timing_status_message("course_report_html", "Generating HTML course")
      showNotification(status_message, type = "default", duration = NULL, id = "html_course_loading")
      
      # Start timing
      timer <- start_report_timer("course_report_html", list(course = input$cr_course))
      
      tryCatch({
        opt <- list()
        opt[["shiny"]] <- TRUE
        opt[["use_rmarkdown"]] <- TRUE
        opt[["course"]] <- input$cr_course
        opt[["skip_forecast"]] <- input$cr_skip_forecast
        
        # Generate the full RMarkdown report
        create_course_report(cedar_students, cedar_sections, forecasts, opt)
        
        # End timing and log
        duration_sec <- end_report_timer(timer)
        
        # Copy the generated report to download location
        report_path <- file.path(getwd(), "www", paste0(gsub(" ", "_", input$cr_course), ".html"))
        if (file.exists(report_path)) {
          file.copy(report_path, file, overwrite = TRUE)
        } else {
          stop("Report file was not generated")
        }
        
        removeNotification("html_course_loading")
        showNotification(paste("HTML course report downloaded! (", round(duration_sec, 1), "s)"), 
                        type = "message", duration = 5)
      }, error = function(e) {
        handle_error(e, "course_report_download", "html_course_loading")
        
        # End timer even on error
        tryCatch(end_report_timer(timer), error = function(timer_error) {
          message("[server.R] Error ending timer: ", timer_error$message)
        })
      })
    }
  )

  # Render course report UI
  output$cr_report <- renderUI({
    data <- course_report_data()
    if (is.null(data)) {
      return(div(
        style = "text-align: center; margin-top: 50px;",
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
    message("[server.R] cr_enrollment_plot renderer called. Data is null: ", is.null(data))
    
    if (!is.null(data)) {
      message("[server.R] Data structure: ", paste(names(data), collapse = ", "))
      if ("plots" %in% names(data)) {
        message("[server.R] Plots structure: ", paste(names(data$plots), collapse = ", "))
        if ("enrollment_plot" %in% names(data$plots)) {
          message("[server.R] Enrollment plot found, returning it")
          return(data$plots$enrollment_plot)
        } else {
          message("[server.R] enrollment_plot not found in plots")
        }
      } else {
        message("[server.R] plots not found in data")
      }
    }
    
    # Return empty plot if no data
    message("[server.R] Returning NULL for enrollment plot")
    return(NULL)
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
    message("[server.R] cr_rollcall_by_class_plot renderer called. Data is null: ", is.null(data))
    
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_class_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_class_plot
      message("[server.R] Rollcall by class plots found")
      
      # Return fall plot if available, otherwise spring, otherwise first available
      if (!is.null(plots$fall)) {
        message("[server.R] Returning fall classification plot")
        return(plots$fall)
      } else if (!is.null(plots$spring)) {
        message("[server.R] Returning spring classification plot")
        return(plots$spring)
      } else if (!is.null(plots$main)) {
        message("[server.R] Returning main classification plot")
        return(plots$main)
      }
    }
    
    message("[server.R] Rollcall by class plot not found")
    return(NULL)
  })
  
  output$cr_rollcall_by_class_other_plot <- renderPlotly({
    data <- course_report_data()
    message("[server.R] cr_rollcall_by_class_other_plot renderer called")
    
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_class_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_class_plot
      
      # Return spring plot if available (to show alongside fall)
      if (!is.null(plots$spring)) {
        message("[server.R] Returning spring classification plot")
        return(plots$spring)
      } else if (!is.null(plots$summer)) {
        message("[server.R] Returning summer classification plot")
        return(plots$summer)
      }
    }
    
    message("[server.R] Rollcall by class other plot not found")
    return(NULL)
  })


  output$cr_rollcall_by_major_plot <- renderPlotly({
    data <- course_report_data()
    message("[server.R] cr_rollcall_by_major_plot renderer called. Data is null: ", is.null(data))
    
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_major_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_major_plot
      message("[server.R] Rollcall by major plots found")
      
      # Return fall plot if available, otherwise spring, otherwise first available
      if (!is.null(plots$fall)) {
        message("[server.R] Returning fall major plot")
        return(plots$fall)
      } else if (!is.null(plots$spring)) {
        message("[server.R] Returning spring major plot")
        return(plots$spring)
      } else if (!is.null(plots$main)) {
        message("[server.R] Returning main major plot")
        return(plots$main)
      }
    }
    
    message("[server.R] Rollcall by major plot not found")
    return(NULL)
  })
  
  output$cr_rollcall_by_major_other_plot <- renderPlotly({
    data <- course_report_data()
    message("[server.R] cr_rollcall_by_major_other_plot renderer called")
    
    if (!is.null(data) && "plots" %in% names(data) && "rollcall_by_major_plot" %in% names(data$plots)) {
      plots <- data$plots$rollcall_by_major_plot
      
      # Return spring plot if available (to show alongside fall)
      if (!is.null(plots$spring)) {
        message("[server.R] Returning spring major plot")
        return(plots$spring)
      } else if (!is.null(plots$summer)) {
        message("[server.R] Returning summer major plot")
        return(plots$summer)
      }
    }
    
    message("[server.R] Rollcall by major other plot not found")
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
    render_rollcall_pie_plot("rollcall_by_major_plot_data", "major", "fall", "fall major plot")
  })
  
  # Spring major plot with campus filtering
  output$cr_rollcall_by_major_spring_plot <- renderPlotly({
    render_rollcall_pie_plot("rollcall_by_major_plot_data", "major", "spring", "spring major plot")
  })
  
  # Classification time series plot with campus filtering
  output$cr_rollcall_by_class_time_plot <- renderPlotly({
    render_rollcall_time_plot("rollcall_by_class_plot_data", "student_classification", "classification time series")
  })
  
  # Major time series plot with campus filtering  
  output$cr_rollcall_by_major_time_plot <- renderPlotly({
    render_rollcall_time_plot("rollcall_by_major_plot_data", "major", "major time series")
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


  # Grades table
  output$cr_grades_table <- DT::renderDataTable({
    data <- course_report_data()
    if (!is.null(data) && "tables" %in% names(data) && !is.null(data$tables$grade_data$dfw_summary)) {
      data$tables$grade_data$dfw_summary
    }
  }, options = list(pageLength = 10, scrollX = TRUE))


  # DFW Summary Plot
  output$dfw_summary_plot <- renderPlotly({
    data <- course_report_data()
    message("[server.R] dfw_summary_plot renderer called. Data is null: ", is.null(data))
    
    if (!is.null(data)) {
      if ("plots" %in% names(data) && "dfw_summary_plot" %in% names(data$plots)) {
        message("[server.R] dfw_summary_plot found in plots, returning it")
        return(data$plots$dfw_summary_plot)
      } else {
        message("[server.R] dfw_summary_plot not found in plots")
      }
    }

    message("[server.R] Returning NULL for dfw_summary_plot")
    return(NULL)
  })

# DFW by term plot
  output$dfw_by_term_plot <- renderPlotly({
    data <- course_report_data()
    return(data$plots$dfw_by_term_plot)
  })

# DFW by instructor plot
  output$dfw_by_inst_type_plot <- renderPlotly({
    data <- course_report_data()
    return(data$plots$dfw_by_inst_type_plot)
  })

  # Course Report DFW Tab Content (password protected)
  output$cr_dfw_tab_content <- renderUI({
    data <- course_report_data()

    if (is.null(data)) {
      return(div(
        style = "text-align: center; margin-top: 50px;",
        h4("Generate a course report to view DFW data.")
      ))
    }

    if (dfw_authenticated()) {
      # DFW content is visible only after authentication
      tagList(
        h4("DFW Means"),
        plotlyOutput("dfw_summary_plot", height = "400px"),
        h4("DFW Rates By Term"),
        plotlyOutput("dfw_by_term_plot", height = "400px"),
        h4("DFW Rates by Instructor Category"),
        plotlyOutput("dfw_by_inst_type_plot", height = "400px"),
        h4("Grade Distribution Details"),
        DT::DTOutput("cr_grades_table")
      )
    } else {
      # Show password gate
      fluidRow(
        column(12,
          create_password_gate_ui("cr_dfw_password", "cr_dfw_submit_btn")
        )
      )
    }
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
      
      # Check if lookout data exists
      if ("tables" %in% names(data)) {
        cat("\nLookout data availability:\n")
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



  ########################### 
  #       SEATFINDER        #
  ###########################
  observeEvent(input$sf_button,{
    # Log seatfinder button click
    log_report_generation(session, "seatfinder", list(
      campus = input$sf_campus,
      college = input$sf_college,
      dept = input$sf_dept,
      term = input$sf_term,
      pt = input$sf_pt,
      im = input$sf_im,
      level = input$sf_level
    ))
    
    # Show loading notification
    status_message <- create_timing_status_message("seatfinder", "Generating seatfinder analysis")
    showNotification(status_message, type = "warning", duration = NULL, id = "seatfinder_loading")
    
    # Start timing
    timer <- start_report_timer("seatfinder", list(
      dept = input$sf_dept,
      term = input$sf_term
    ))
    
    tryCatch({
      #RV$data<-myCustomFunction(RV$data)
      
      # get seatfinder data
      opt <- list()
      opt[["course_campus"]] <- input$sf_campus
      opt[["course_college"]] <- input$sf_college
      opt[["dept"]] <- input$sf_dept
      opt[["term"]] <- input$sf_term
      opt[["pt"]] <- input$sf_pt
      opt[["im"]] <- input$sf_im
      opt[["level"]] <- input$sf_level
      opt[["group_cols"]] <- input$sf_agg_by
      
      courses_list <- seatfinder(cedar_students, cedar_sections, cedar_faculty, opt)
      
      # Type Summary: has ENRL, avail, avail_diff, DFW %
      output$type_summary = DT::renderDataTable({
        create_seatfinder_datatable(
          courses_list[["type_summary"]],
          color_avail = TRUE,          
          color_dfw = TRUE
        )
      }, options = list(pageLength = 50))
      
      # Common Courses: has enrolled, avail, enrl_diff_from_last_year, DFW %
      output$courses_common = DT::renderDataTable({
        create_styled_datatable(
          courses_list[["courses_common"]],
          column_schemes = list(
            "avail" = "availability",
            "DFW %" = "dfw"
          )
        )
      }, options = list(pageLength = 50))
      
      # Previously Offered: has enrolled, avail, DFW %
      output$courses_prev = DT::renderDataTable({
        create_styled_datatable(courses_list[["courses_prev"]])  # Auto-detect columns
      }, options = list(pageLength = 50))
      
      # Newly Offered: has enrolled, avail, DFW %
      output$courses_new = DT::renderDataTable({
        create_styled_datatable(courses_list[["courses_new"]])  # Auto-detect columns
      }, options = list(pageLength = 50))
      
      # Gen Ed Summary: has enrolled, avail, DFW %
      output$gen_ed_summary = DT::renderDataTable({
        create_styled_datatable(courses_list[["gen_ed_summary"]])  # Auto-detect columns
      }, options = list(pageLength = 50))
      
      # Gen Ed Likely: has enrolled (=0), avail (=0) - no color coding needed
      output$gen_ed_likely = DT::renderDataTable({
        courses_list[["gen_ed_likely"]]
      }, options = list(pageLength = 50))
      
      # End timing and show success
      duration_sec <- end_report_timer(timer)
      removeNotification("seatfinder_loading")
      showNotification(paste("Seatfinder analysis generated successfully! (", round(duration_sec, 1), "s)"), 
                      type = "message", duration = 3)
      
    }, error = function(e) {
      handle_error(e, "seatfinder", "seatfinder_loading")
      
      # End timer even on error
      tryCatch(end_report_timer(timer), error = function(timer_error) {
        message("[server.R] Error ending timer: ", timer_error$message)
      })
    })
    
  },ignoreInit = TRUE) # end observeEvent for sf_button
  


  ####################
  ##### WAITLIST #####
  #####################
  observeEvent(input$wl_button,{
    # Log waitlist button click
    log_report_generation(session, "waitlist", list(
      course = input$wl_course
    ))
    
    #RV$data<-myCustomFunction(RV$data)
    
    opt <- list()
    opt[["course"]] <- input$wl_course
    
    # Set course to NULL if empty
    if (length(opt[["course"]]) == 1 && opt[["course"]] == "") {
      opt[["course"]] <- NULL
    }
    waitlist_data <- inspect_waitlist(cedar_students, opt)
    
    output$wl_majors = DT::renderDataTable({
      data <- waitlist_data[["majors"]]
    })
    
    output$wl_classifications = DT::renderDataTable({
      data <- waitlist_data[["classifications"]]
    })
    
    output$wl_count = DT::renderDataTable({
      data <- waitlist_data[["count"]]
    })
    
    output$courses_new = DT::renderDataTable({
      data <- courses_list[["courses_new"]]
    })
    
  },ignoreInit = TRUE) # end observeEvent for waitlist button
  
  


  ####################
  ##### REGSTATS #####
  ####################

  # Reactive value to store regstats data
  regstats_data <- reactiveVal(NULL)
  
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
      term = input$rs_term,
      thresholds = list(
        min_impacted = input$rs_min_impacted,
        min_wait = input$rs_min_wait,
        pct_sd = input$rs_pct_sd,
        min_squeeze = input$rs_min_squeeze
      )
    ))
    
    # Build options from inputs
    opt <- list()
    opt[["shiny"]] <- TRUE
    opt[["course_campus"]] <- input$rs_campus
    opt[["course_college"]] <- input$rs_college
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
    opt[["thresholds"]][["min_squeeze"]] <- input$rs_min_squeeze
    
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
      
      # Store the data in reactive value
      regstats_data(list(
        flagged = result,
        opt = opt,
        generated_at = Sys.time()
      ))
      
      removeNotification("regstats_loading")
      showNotification(paste("Regstats dashboard generated! (", round(duration_sec, 1), "s)"), 
                      type = "message", duration = 5)
    }, error = function(e) {
      handle_error(e, "regstats_dashboard", "regstats_loading")
    })
  }, ignoreInit = TRUE) # end observeEvent for rs_dashboard_button
  
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
      opt[["thresholds"]][["min_squeeze"]] <- input$rs_min_squeeze
      
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
    data <- regstats_data()
    message("[server.R] rs_dashboard renderUI called. Data is null: ", is.null(data))
    
    if (is.null(data)) {
      message("[server.R] No regstats data available - showing default message")
      return(div(
        style = "text-align: center; margin-top: 50px;",
        h4("Set your filters and click 'Generate Dashboard' to view regstats data.")
      ))
    }
    
    message("[server.R] Rendering dashboard with data. Names: ", paste(names(data), collapse=", "))
    if ("flagged" %in% names(data)) {
      message("[server.R] Flagged data names: ", paste(names(data$flagged), collapse=", "))
    }
    
    flagged <- data$flagged

    thresholds <- if(is.null(data$opt$thresholds)) {
      # Use default thresholds if none provided in preloaded data
      message("[server.R] No data$opt$thresholds, so using cedar_regstats_thresholds.")
      cedar_regstats_thresholds
    } else {
      data$opt$thresholds
    }
    
    # Create summary metrics for cards
    bumps_count <- if("bumps" %in% names(flagged)) nrow(flagged$bumps) else 0
    dips_count <- if("dips" %in% names(flagged)) nrow(flagged$dips) else 0
    waits_count <- if("waits" %in% names(flagged)) nrow(flagged$waits) else 0
    squeezes_count <- if("squeezes" %in% names(flagged)) nrow(flagged$squeezes) else 0
    early_drops_count <- if("early_drops" %in% names(flagged)) nrow(flagged$early_drops) else 0
    late_drops_count <- if("late_drops" %in% names(flagged)) nrow(flagged$late_drops) else 0
    
    # Create tier-based metrics for enhanced cards
    get_tier_counts <- function(data, tier) {
      if("concern_tier" %in% names(data)) {
        sum(data$concern_tier == tier, na.rm = TRUE)
      } else { 0 }
    }
    
    # Critical tier counts (red alerts)
    critical_bumps <- get_tier_counts(flagged$bumps, "critical_high")
    critical_dips <- get_tier_counts(flagged$dips, "critical_low") 
    critical_early_drops <- get_tier_counts(flagged$early_drops, "critical_high")
    critical_late_drops <- get_tier_counts(flagged$late_drops, "critical_high")
    
    # Total critical concerns
    total_critical <- critical_bumps + critical_dips + critical_early_drops + critical_late_drops
    
    # Create a 3x3 grid of cards wrapped in tagList
    tagList(
      fluidRow(
        column(4,
          card(
            card_header("Enrollment Bumps"),
            card_body(
              div(
                style = "text-align: center;",
                h2(bumps_count, style = "color: #f0ad4e; margin: 0;"),
                p("Higher than usual enrollment", style = "margin: 2px 0; color: #666; font-size: 0.9em;"),
                if(critical_bumps > 0) {
                  div(style = "margin-top: 6px; color: #d9534f; font-size: 0.8em;", 
                      paste("🔴", critical_bumps, "Critical"))
                } else if(bumps_count > 0) {
                  div(style = "margin-top: 6px; color: #f0ad4e; font-size: 0.8em;", "🟡 Moderate")
                }
              )
            )
          )
        ),
        column(4,
          card(
            card_header("Enrollment Dips"), 
            card_body(
              div(
                style = "text-align: center;",
                h2(dips_count, style = "color: #5bc0de; margin: 0;"),
                p("Lower than usual enrollment", style = "margin: 2px 0; color: #666; font-size: 0.9em;"),
                if(critical_dips > 0) {
                  div(style = "margin-top: 6px; color: #d9534f; font-size: 0.8em;", 
                      paste("🔴", critical_dips, "Critical"))
                } else if(dips_count > 0) {
                  div(style = "margin-top: 6px; color: #f0ad4e; font-size: 0.8em;", "🟡 Moderate")
                }
              )
            )
          )
        ),
        column(4,
        card(
          card_header("High Waitlist"),
          card_body(
            div(
              style = "text-align: center;",
              h2(waits_count, style = "color: #d9534f; margin: 0;"),
              p(paste("Waitlist >", thresholds$min_wait), style = "margin: 5px 0 0 0; color: #666;")
            )
          )
        )
      )
      ), # end first fluidRow
      fluidRow(      
      column(4,
        card(
          card_header("Early Drops"),
          card_body(
            div(
              style = "text-align: center;",
              h2(early_drops_count, style = "color: #5bc0de; margin: 0;"),
              p("Early-drop heavy courses", style = "margin: 5px 0 0 0; color: #666;")
            )
          )
        )
      ),
      column(4,
        card(
          card_header("Late Drops"),
          card_body(
            div(
              style = "text-align: center;",
              h2(late_drops_count, style = "color: #5cb85c; margin: 0;"),
              p("Late-drop heavy courses", style = "margin: 5px 0 0 0; color: #666;")
            )
          )
        )
      ),
      column(4,
        card(
          card_header("Squeezes"),
          card_body(
            div(
              style = "text-align: center;",
              h2(squeezes_count, style = "color: #f0ad4e; margin: 0;"),
              p(paste("minimal capacity courses <", thresholds$min_squeeze), style = "margin: 5px 0 0 0; color: #666;")
            )
          )
        )
      )
    ), # end second fluidRow
    # Analysis Summary - Third row taking full width
    fluidRow(
      column(12,
        card(
          card_header("Analysis Summary"),
          card_body(
            div(
              style = "text-align: center; padding: 10px;",
              paste(
                "Campus:", if(is.null(data$opt$course_campus) || length(data$opt$course_campus) == 0) "All" else paste(data$opt$course_campus, collapse = ", "), " | ",
                "College:", if(is.null(data$opt$course_college) || length(data$opt$course_college) == 0) "All" else paste(data$opt$course_college, collapse = ", "), " | ",
                "Term:", if(is.null(data$opt$term) || length(data$opt$term) == 0) "All" else paste(data$opt$term, collapse = ", "), " | ",
                "Min Impacted:", data$opt$thresholds$min_impacted, " | ",
                "Min Wait:", data$opt$thresholds$min_wait, " | ",
                "Pct SD:", data$opt$thresholds$pct_sd, " | ", 
                "Min Squeeze:", data$opt$thresholds$min_squeeze, " | ",
                "Generated:", format(data$generated_at, "%Y-%m-%d %H:%M")
              ),
              style = "font-size: 1em; color: #555;"
            )
          )
        )
      )
    ), # end third fluidRow
    
    # Add detailed tables below the cards
    fluidRow(
      column(12,
        card(
          card_header("Flagged Courses Details"),
          card_body(
            tabsetPanel(
              tabPanel("Enrollment Bumps",
                if(bumps_count > 0) {
                  DT::DTOutput("rs_bumps_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No enrollment bumps found.")
                }
              ),
              tabPanel("Enrollment Dips",
                if(dips_count > 0) {
                  DT::DTOutput("rs_dips_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No enrollment dips found.")
                }
              ),
              tabPanel("Early Drops",
                if(early_drops_count > 0) {
                  DT::DTOutput("rs_early_drops_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No early drops found.")
                }
              ),
              tabPanel("Late Drops",
                if(late_drops_count > 0) {
                  DT::DTOutput("rs_late_drops_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No late drops found.")
                }
              ),

              tabPanel("High Waitlists",
                if(waits_count > 0) {
                  DT::DTOutput("rs_waits_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No high waitlist courses found.")
                }
              ),
              tabPanel("Squeezes",
                if(squeezes_count > 0) {
                  DT::DTOutput("rs_squeezes_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "No low squeeze courses found.")
                }
              ),
              tabPanel("All Flagged",
                DT::DTOutput("rs_all_flagged_table")
              ),
              tabPanel("Concern Tiers",
                if(!is.null(flagged$tiered_summary)) {
                  DT::DTOutput("rs_tiered_summary_table")
                } else {
                  div(style = "text-align: center; padding: 20px;", "Tier analysis not available for this data.")
                }
              )
            ) # end tabsetPanel
          ) # end card_body
        ) # end card
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
  
  output$rs_dips_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "dips" %in% names(data$flagged)) {
      create_regstats_datatable(data$flagged$dips)
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
      data$flagged$waits
    }
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  output$rs_squeezes_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "squeezes" %in% names(data$flagged)) {
      data$flagged$squeezes
    }
  }, options = list(pageLength = 10, scrollX = TRUE))
  
  output$rs_all_flagged_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "all_flagged_courses" %in% names(data$flagged)) {
      data.frame(Course = data$flagged$all_flagged_courses)
    }
  }, options = list(pageLength = 15, scrollX = TRUE))
  
  output$rs_tiered_summary_table <- DT::renderDataTable({
    data <- regstats_data()
    if (!is.null(data) && "tiered_summary" %in% names(data$flagged)) {
      summary_data <- data$flagged$tiered_summary %>%
        mutate(
          anomaly_type = case_when(
            anomaly_type == "early_drops" ~ "Early Drops",
            anomaly_type == "late_drops" ~ "Late Drops", 
            anomaly_type == "dips" ~ "Low Enrollment",
            anomaly_type == "bumps" ~ "High Enrollment",
            TRUE ~ anomaly_type
          )
        ) %>%
        select(
          `Anomaly Type` = anomaly_type,
          `Critical High` = critical_high,
          `Critical Low` = critical_low, 
          `Moderate High` = moderate_high,
          `Moderate Low` = moderate_low,
          `Marginal High` = marginally_high,
          `Marginal Low` = marginally_low,
          `Normal` = normal,
          `Total` = total_flagged
        )
      
      # Create the datatable
      dt <- DT::datatable(summary_data, options = list(
        pageLength = 10, 
        scrollX = TRUE,
        dom = 't'  # Hide search/pagination for small table
      ))
      
      # Apply formatting
      dt <- dt %>%
        DT::formatStyle(
          c("Critical High", "Critical Low"),
          backgroundColor = "#f8d7da",
          color = "#721c24"
        ) %>%
        DT::formatStyle(
          c("Moderate High", "Moderate Low"), 
          backgroundColor = "#fff3cd",
          color = "#856404"
        )
        # return formatted table
        dt    
    }
  }) # end renderDataTable for tiered summary
  



  ##############################
  ##### DEPARTMENT REPORT #####
  ##############################

  # Reactive value to store department report data
  dept_report_data <- reactiveVal(NULL)
  
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
  
  # Clear cached data when department selection changes
  observeEvent(input$dept_report_dept, {
    # Log department selection
    log_data_filter(session, "dept_report_dept", input$dept_report_dept)
    
    # Only clear if there's actually cached data and it's for a different department
    cached_data <- dept_report_data()
    if (!is.null(cached_data) && 
        !is.null(cached_data$dept_code) && 
        cached_data$dept_code != input$dept_report_dept) {
      message("Department changed from ", cached_data$dept_code, " to ", input$dept_report_dept, ". Clearing cached data.")
      dept_report_data(NULL)
    }
  }, ignoreInit = TRUE)
  

  # Dept Report Interactive Generation 
  observeEvent(input$dept_report_button, {
    req(input$dept_report_dept)
    if (input$dept_report_dept == "") {
      showNotification("Please select a department.", type = "error")
      return()
    }

    # Log department report generation
    log_report_generation(session, "dept_report", list(
      department = input$dept_report_dept
    ))

    # Show loading notification with average time
    status_message <- create_timing_status_message("dept_report", "Generating interactive department")
    showNotification(status_message, type = "message", duration = NULL, id = "dept_loading")

    # Start timing
    timer <- start_report_timer("dept_report", list(department = input$dept_report_dept))

    tryCatch({
      opt <- list()
      opt[["shiny"]] <- TRUE
      opt[["dept"]] <- input$dept_report_dept

      # Generate department data using the data preparation function (not the full RMarkdown report)
      message("[server.R] Generating interactive report data for: ", input$dept_report_dept)
      d_params <- create_dept_report_data(data_objects, opt)
      message("[server.R] Interactive report data generated!")

      # save RDS; SUPER SLOW
      # message("Saving department report data to RDS...")
      # output_path <- paste0(cedar_data_dir, input$dept_report_dept, "_data.rds")
      # message("Output path for RDS: ", output_path)
      # saveRDS(d_params, file = output_path)
      # message("Department report data saved!")

      # End timing and log
      duration_sec <- end_report_timer(timer)

      # Store the data in the reactive value
      message("Storing department report data in reactive value---i.e. sending d_params to dept_report_data...")
      dept_report_data(d_params)

      removeNotification("dept_loading")
      showNotification(paste("Interactive department report generated successfully! (", round(duration_sec, 1), "s)"), 
                      type = "message", duration = 3)
      
    }, error = function(e) {
      handle_error(e, "dept_report", "dept_loading")
    })
  }, ignoreInit = TRUE) # end observeEvent(input$dept_report_button

  # Persist selected tab across re-renders
  observeEvent(input$dept_report_tabs, {
    if (!is.null(input$dept_report_tabs)) {
      dept_report_tab_selected(input$dept_report_tabs)
    }
  }, ignoreInit = TRUE)

  # Inline DFW password submission for dept report (keeps the DFW tab active)
  observeEvent(input$dfw_submit_inline_btn, {
    if (input$dfw_password_inline == dfw_password) {
      dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
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
      message("[downloadHandler] dept_report_html requested for: ", dept)

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
          message("[downloadHandler]   using cached data")
          d_params <- cached_data
          d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
          d_params$output_dir_base <- file.path(cedar_output_dir, "dept-reports")
          d_params$output_filename <- dept

          create_report(opt = list(shiny = TRUE, dept = dept), d_params)
        } else {
          message("[downloadHandler]   generating fresh data")
          opt <- list(shiny = TRUE, dept = dept)
          create_dept_report(data_objects, opt)
        }
              
        # In Docker, create_report saves to data/ directory
        # Sanitize filename same way as dept-report.R
        report_filename <- gsub(" ", "_", dept)
        output_path <- file.path(getwd(), "data", paste0(report_filename, ".html"))
        message("[downloadHandler]   looking for file at: ", output_path)
        
        if (!file.exists(output_path)) {
          stop("Report file not found at: ", output_path)
        }
        
        file.copy(output_path, file, overwrite = TRUE)
        message("[downloadHandler]   copied to download location: ", file)

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
        style = "text-align: center; margin-top: 50px;",
        h4("Select a department and click 'Generate Department Report' to view data.")
      ))
    }
    
    # Create a tabbed interface for different report sections
    tabsetPanel(
      tabPanel("Headcount", 
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            
            h4("Undergrad Majors"),
            # Display headcount plot if it exists
            if("hc_progs_under_long_majors_plot" %in% names(data$plots)) {                
                plotlyOutput("hc_progs_under_long_majors_plot")
            },
            
            h4("Undergrad Minors"),
            if("hc_progs_under_long_minors_plot" %in% names(data$plots)) {            
                plotlyOutput("hc_progs_under_long_minors_plot")
            },
            
            h4("Grad Majors"),
            # Display headcount plot if it exists
            if("hc_progs_grad_long_majors_plot" %in% names(data$plots)) {
                plotlyOutput("hc_progs_grad_long_majors_plot")
            },
            
            h4("Grad Minors"),
            if("hc_progs_grad_long_minors_plot" %in% names(data$plots)) {            
                plotlyOutput("hc_progs_grad_long_minors_plot")
            },
            # Display headcount table if it exists
            # if("hc_progs_under_long_majors" %in% names(data$tables)) {
            #   DT::DTOutput("hc_progs_under_long_majors")
            # } else {
            #   p("No headcount table available")
            # }
          )
        )
      ),
      tabPanel("Enrollment",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Highest Total Enrollment"),
            if("highest_total_enrl_plot" %in% names(data$plots)) {                
                plotlyOutput("highest_total_enrl_plot")
            },
            h4("Highest Mean Enrollment"),
            if("highest_mean_enrl_plot" %in% names(data$plots)) {            
                plotlyOutput("highest_mean_enrl_plot")
            },
            h4("Mean Enrollment Distribution"),
            if("highest_mean_histo_plot" %in% names(data$plots)) {            
                plotlyOutput("highest_mean_histo_plot")
            }
          )
        )
      ),
      tabPanel("Degrees",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Degree Summary by Major"),
            if("degree_summary_faceted_by_major_plot" %in% names(data$plots)) {                
                plotlyOutput("degree_summary_faceted_by_major_plot")
            },
            h4("Degree Summary by Program (Stacked)"),
            if("degree_summary_filtered_program_stacked_plot" %in% names(data$plots)) {            
                plotlyOutput("degree_summary_filtered_program_stacked_plot")
            }
          )
        )
      ),
      tabPanel("Credit Hours",
        fluidRow(
          column(12,
            h3(paste("Department:", data$dept_name)),
            h4("Credit Hours by Term (Faceted by Subject)"),
            if("chd_by_year_facet_subj_plot" %in% names(data$plots)) {
              plotlyOutput("chd_by_year_facet_subj_plot")
            },
            h4("Credit Hours by Term by Subject"),
            if("chd_by_year_subj_plot" %in% names(data$plots)) {
              plotlyOutput("chd_by_year_subj_plot")
            },
            h4("Credit Hours by Term"),
            if("chd_by_year_plot" %in% names(data$plots)) {
              plotlyOutput("chd_by_year_plot")
            },
            h4("Student Credit Hours by Major - Course Level Breakdown"),
            fluidRow(
              column(6,
                h5("Outside Majors (Lower Division)"),
                if("sch_outside_pct_lower_plot" %in% names(data$plots)) {
                  plotlyOutput("sch_outside_pct_lower_plot")
                }
              ),
              column(6,
                h5("Outside Majors (Upper Division)"),
                if("sch_outside_pct_upper_plot" %in% names(data$plots)) {
                  plotlyOutput("sch_outside_pct_upper_plot")
                }
              )
            ),
            fluidRow(
              column(6,
                h5("Majors vs Non-Majors (Lower Division)"),
                if("sch_dept_pct_lower_plot" %in% names(data$plots)) {
                  plotlyOutput("sch_dept_pct_lower_plot")
                }
              ),
              column(6,
                h5("Majors vs Non-Majors (Upper Division)"),
                if("sch_dept_pct_upper_plot" %in% names(data$plots)) {
                  plotlyOutput("sch_dept_pct_upper_plot")
                }
              )
            ),
            h4("Credit Hours by Faculty (Faceted)"),
            if("chd_by_fac_facet_plot" %in% names(data$plots)) {
              plotlyOutput("chd_by_fac_facet_plot")
            },
            h4("Credit Hours by Faculty"),
            if("chd_by_fac_plot" %in% names(data$plots)) {
              plotlyOutput("chd_by_fac_plot")
            },
            h4("College vs Department Comparison"),
            if("college_dept_dual_plot" %in% names(data$plots)) {
              plotlyOutput("college_dept_dual_plot")
            }
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
              if("grades_summary_for_ld_abq_ea_plot" %in% names(data$plots)) {
                plotlyOutput("grades_summary_for_ld_abq_ea_plot")
              } else {
                p("No DFW data available for lower division courses. This may occur if the department has no lower division courses or no grade data in the selected time period.")
              }
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

  # List of plot output variable names used in individual output definitions
  plot_names <- c(
    "chd_by_year_facet_subj_plot",
    "chd_by_year_subj_plot",
    "chd_by_year_plot",
    "sch_outside_pct_lower_plot",
    "sch_outside_pct_upper_plot",
    "sch_dept_pct_lower_plot",
    "sch_dept_pct_upper_plot",
    "hc_progs_under_long_majors_plot",
    "hc_progs_under_long_minors_plot",
    "hc_progs_grad_long_majors_plot",
    "hc_progs_grad_long_minors_plot",
    "highest_total_enrl_plot",
    "highest_mean_enrl_plot",
    "highest_mean_histo_plot",
    "degree_summary_faceted_by_major_plot",
    "degree_summary_filtered_program_stacked_plot",
    "chd_by_fac_facet_plot",
    "chd_by_fac_plot",
    "college_dept_dual_plot",
    "grades_summary_for_ld_abq_ea_plot"
  )

  # Dynamically create output renderers for each plot
  lapply(plot_names, function(plot_name) {
    output[[plot_name]] <- renderPlotly({
      data <- dept_report_data()
      if (!is.null(data) && "plots" %in% names(data) && plot_name %in% names(data$plots)) {
        data$plots[[plot_name]]
      }
    })
  })

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
    message("[server.R] *** DATA STATUS TABLE rendering (using pre-computed cedar_data_summary) ***")
    tryCatch({
      # Build display data from pre-computed summary
      display_data <- data.frame(
        Dataset = character(),
        `Total Rows` = integer(),
        `Last Updated` = character(),
        `Unique Terms/Records` = character(),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )

      # Sections
      if (!is.null(cedar_data_summary$sections_count) && cedar_data_summary$sections_count > 0) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Sections",
          `Total Rows` = cedar_data_summary$sections_count,
          `Last Updated` = format(cedar_data_summary$sections_last_updated, "%Y-%m-%d"),
          `Unique Terms/Records` = paste0(cedar_data_summary$sections_active_count, " active, ",
                                          cedar_data_summary$sections_cancelled_count, " cancelled"),
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      # Students
      if (!is.null(cedar_data_summary$students_count) && cedar_data_summary$students_count > 0) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Students",
          `Total Rows` = cedar_data_summary$students_count,
          `Last Updated` = format(cedar_data_summary$students_last_updated, "%Y-%m-%d"),
          `Unique Terms/Records` = paste0(cedar_data_summary$students_unique_count, " unique students"),
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      # Programs
      if (!is.null(cedar_data_summary$programs_count) && cedar_data_summary$programs_count > 0) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Programs",
          `Total Rows` = cedar_data_summary$programs_count,
          `Last Updated` = format(cedar_data_summary$programs_last_updated, "%Y-%m-%d"),
          `Unique Terms/Records` = paste0(cedar_data_summary$programs_unique_students, " unique students"),
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      # Degrees
      if (!is.null(cedar_data_summary$degrees_count) && cedar_data_summary$degrees_count > 0) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Degrees",
          `Total Rows` = cedar_data_summary$degrees_count,
          `Last Updated` = format(cedar_data_summary$degrees_last_updated, "%Y-%m-%d"),
          `Unique Terms/Records` = cedar_data_summary$degrees_terms,
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      # Faculty
      if (!is.null(cedar_data_summary$faculty_count) && cedar_data_summary$faculty_count > 0) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Faculty",
          `Total Rows` = cedar_data_summary$faculty_count,
          `Last Updated` = format(cedar_data_summary$faculty_last_updated, "%Y-%m-%d"),
          `Unique Terms/Records` = paste0(cedar_data_summary$faculty_unique_count, " unique instructors"),
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      # Forecasts
      if (!is.null(cedar_data_summary$forecasts_available) && cedar_data_summary$forecasts_available) {
        display_data <- rbind(display_data, data.frame(
          Dataset = "Forecasts",
          `Total Rows` = cedar_data_summary$forecasts_count,
          `Last Updated` = "N/A",
          `Unique Terms/Records` = "Forecast data",
          stringsAsFactors = FALSE,
          check.names = FALSE
        ))
      }

      if (nrow(display_data) > 0) {
        DT::datatable(display_data,
                      rownames = FALSE,
                      options = list(dom = 't', paging = FALSE, scrollX = TRUE))
      } else {
        DT::datatable(data.frame(Message = "No data loaded"), rownames = FALSE)
      }
    }, error = function(e) {
      message("[server.R] *** ERROR in data_status_table: ", e$message, " ***")
      DT::datatable(data.frame(Error = paste("Error loading data status:", e$message)), rownames = FALSE)
    })
  })

  # ── Tab 2: Usage Overview (lazy loaded) ────────────────────────────────
  usage_overview_data <- reactiveVal(NULL)

  # Load usage overview when tab is accessed or refresh button clicked
  observeEvent(input$refresh_usage_overview, {
    tryCatch({
      start_date <- if(!is.null(input$usage_start_date)) as.character(input$usage_start_date) else NULL
      end_date <- if(!is.null(input$usage_end_date)) as.character(input$usage_end_date) else NULL

      message("[server.R] Loading usage overview for date range: ", start_date, " to ", end_date)
      overview <- get_usage_overview(start_date, end_date)
      usage_overview_data(overview)

      showNotification("Usage overview refreshed", type = "message")
    }, error = function(e) {
      message("[server.R] Error loading usage overview: ", e$message)
      usage_overview_data(list(message = paste("Error loading usage data:", e$message)))
    })
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

  # ── Tab 3: Feature Details (lazy loaded) ───────────────────────────────
  feature_details_data <- reactiveVal(NULL)

  # Load feature details when refresh button clicked
  observeEvent(input$refresh_feature_details, {
    tryCatch({
      start_date <- if(!is.null(input$feature_start_date)) as.character(input$feature_start_date) else NULL
      end_date <- if(!is.null(input$feature_end_date)) as.character(input$feature_end_date) else NULL

      message("[server.R] Loading feature details for date range: ", start_date, " to ", end_date)
      stats <- get_usage_stats(start_date, end_date)
      feature_details_data(stats)

      showNotification("Feature details refreshed", type = "message")
    }, error = function(e) {
      message("[server.R] Error loading feature details: ", e$message)
      feature_details_data(list(message = paste("Error loading data:", e$message)))
    })
  })

  # Usage Statistics Output (detailed text summary)
  output$usage_stats_output <- renderText({
    stats <- feature_details_data()

    if (is.null(stats)) {
      return("Click 'Refresh' to load detailed statistics")
    }

    if ("message" %in% names(stats)) {
      return(stats$message)
    }

    # Format the statistics as text
    output_lines <- c(
      "CEDAR Usage Statistics",
      "======================",
      paste("Date Range:", format(stats$date_range$start, "%Y-%m-%d"), "to", format(stats$date_range$end, "%Y-%m-%d")),
      paste("Total Sessions:", stats$total_sessions),
      paste("Session Starts:", stats$total_session_starts)
    )

    if ("reports_generated" %in% names(stats)) {
      output_lines <- c(output_lines, paste("Reports Generated:", stats$reports_generated))
    }

    if ("error_count" %in% names(stats)) {
      output_lines <- c(output_lines, paste("Errors:", stats$error_count))
    }

    if ("most_popular_tabs" %in% names(stats)) {
      output_lines <- c(output_lines, "", "Most Popular Tabs:")
      for (i in 1:min(5, length(stats$most_popular_tabs))) {
        output_lines <- c(output_lines, paste("  ", names(stats$most_popular_tabs)[i], ":", stats$most_popular_tabs[i]))
      }
    }

    paste(output_lines, collapse = "\n")
  })

  # Feature Usage Table (detailed event log)
  output$feature_usage_table <- DT::renderDataTable({
    message("[server.R] *** FEATURE USAGE TABLE rendering ***")
    tryCatch({
      start_date <- if(!is.null(input$feature_start_date)) as.character(input$feature_start_date) else NULL
      end_date <- if(!is.null(input$feature_end_date)) as.character(input$feature_end_date) else NULL

      logs <- read_logs(start_date, end_date)
      message("[server.R] Read ", nrow(logs), " log entries for feature usage table")

      if (nrow(logs) == 0) {
        return(DT::datatable(data.frame(Message = "No log data found for this date range"), rownames = FALSE))
      }

      # Filter to relevant events
      feature_logs <- logs[logs$event_type %in% c("tab_change", "report_generated", "query_executed"), ]

      if (nrow(feature_logs) > 0) {
        # Select columns
        feature_summary <- feature_logs %>%
          select(timestamp, event_type, details) %>%
          arrange(desc(timestamp))

        # Format timestamp for Mountain Time display
        feature_summary <- feature_summary %>%
          mutate(timestamp = format(
            as.POSIXct(timestamp, tz = "UTC") %>%
              lubridate::with_tz("America/Denver"),
            "%b %d, %Y %I:%M %p MST"
          ))

        DT::datatable(feature_summary,
                      colnames = c("Timestamp", "Event Type", "Details"),
                      rownames = FALSE,
                      options = list(pageLength = 15, scrollX = TRUE))
      } else {
        DT::datatable(data.frame(Message = "No feature usage events found"), rownames = FALSE)
      }
    }, error = function(e) {
      message("[server.R] *** ERROR in feature_usage_table: ", e$message, " ***")
      DT::datatable(data.frame(Error = paste("Error loading data:", e$message)), rownames = FALSE)
    })
  })


  #########################
  ##### CHANGELOG TAB #####
  #########################
  
  # Recent changelog (last 3 entries)
  output$changelog_recent <- renderUI({
    tryCatch({
      recent_entries <- get_recent_changelog(max_entries = 1)
      changelog_html <- format_changelog_html(recent_entries)
      
      if (changelog_html == "<p>No changelog entries available.</p>") {
        div(
          style = "text-align: center; padding: 20px; color: #666;",
          h4("No Recent Changes Available"),
          p("Changelog entries will appear here when available.")
        )
      } else {
        HTML(changelog_html)
      }
    }, error = function(e) {
      handle_error(e, "changelog_recent")
      div(
        style = "color: #d9534f; padding: 20px;",
        h4("Error Loading Changelog"),
        p(paste("Unable to load changelog:", e$message))
      )
    })
  })
  
  # Full changelog (all entries)
  output$changelog_full <- renderUI({
    tryCatch({
      all_entries <- load_changelog()
      if (length(all_entries) == 0) {
        div(
          style = "text-align: center; padding: 20px; color: #666;",
          h4("No Changelog Available"),
          p("Complete changelog will appear here when available.")
        )
      } else {
        changelog_html <- format_changelog_html(all_entries, max_entries = length(all_entries))
        HTML(changelog_html)
      }
    }, error = function(e) {
      handle_error(e, "changelog_full")
      div(
        style = "color: #d9534f; padding: 20px;",
        h4("Error Loading Full Changelog"),
        p(paste("Unable to load full changelog:", e$message))
      )
    })
  })


  #########################
  ##### CACHE MANAGEMENT #####
  #########################
  
  # Cache statistics table
  cache_stats_data <- reactiveVal(NULL)
  
  # Load cache stats initially when Data & Usage tab is accessed
  observe({
    if (!is.null(input$tabs) && input$tabs == "Data & Usage" && is.null(cache_stats_data())) {
      tryCatch({
        stats <- get_cache_stats()
        cache_stats_data(stats)
        message("[server.R] Initial cache stats loaded")
      }, error = function(e) {
        message("[server.R] Error loading cache stats: ", e$message)
        cache_stats_data(data.frame(message = "Error loading cache statistics"))
      })
    }
  })
  
  # Refresh cache stats
  observeEvent(input$refresh_cache_stats, {
    tryCatch({
      stats <- get_cache_stats()
      cache_stats_data(stats)
      showNotification("Cache statistics refreshed", type = "message")
      message("[server.R] Cache stats refreshed")
    }, error = function(e) {
      showNotification(paste("Error refreshing cache:", e$message), type = "error")
      message("[server.R] Error refreshing cache stats: ", e$message)
    })
  })
  
  # Clear all cache
  observeEvent(input$clear_all_cache, {
    showModal(modalDialog(
      title = "Confirm Clear All Cache",
      "Are you sure you want to clear all cached course report data? This will slow down the next request for each course.",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_clear_cache", "Clear Cache", class = "btn-danger")
      )
    ))
  })
  
  # Confirm clear cache
  observeEvent(input$confirm_clear_cache, {
    tryCatch({
      clear_all_caches()
      removeModal()
      stats <- get_cache_stats()
      cache_stats_data(stats)
      showNotification("All cache cleared successfully", type = "message")
      message("[server.R] All cache cleared")
    }, error = function(e) {
      showNotification(paste("Error clearing cache:", e$message), type = "error")
      message("[server.R] Error clearing cache: ", e$message)
    })
  })
  
  # Render cache stats table
  output$cache_stats_table <- DT::renderDataTable({
    stats <- cache_stats_data()
    
    if (is.null(stats)) {
      return(DT::datatable(data.frame(Message = "Loading cache statistics..."), rownames = FALSE))
    }
    
    if ("message" %in% colnames(stats)) {
      return(DT::datatable(stats, rownames = FALSE, options = list(dom = 't')))
    }
    
    # Format the stats nicely
    display_stats <- stats
    display_stats$size_mb <- round(display_stats$size_mb, 2)
    display_stats$age_days <- round(display_stats$age_days, 1)
    display_stats$modified <- format(display_stats$modified, "%Y-%m-%d %H:%M")
    
    DT::datatable(
      display_stats,
      rownames = FALSE,
      colnames = c("Cache File", "Size (MB)", "Last Modified", "Age (days)"),
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        order = list(list(2, 'desc'))  # Sort by modified date (descending)
      )
    )
  })

} # end server
