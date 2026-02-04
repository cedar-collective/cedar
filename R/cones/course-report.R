# course_report produces a basic report for a particular course.
# This calls and gathers various other reporting functions, such as enrl, forecast, rollout, lookout, gradebook,
# Designed to be run from the command line via cedar.R -f course-report -d DEPTCODE
# Reports are saved in CEDAR_OUTPUT_DIR/course-reports (in either.
# REQUIRES: opt$course and opt$term
# OPTIONAL: output-format: html (default) or aspx

# TODO: create loops to manage and accept course and term lists for batch processing
# some already in cedar.R; need to separate processing from actual report call as with forecast, regstats, etc

get_course_data <- function(data_objects, opt) {
  # for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "MATH 1350"
  # opt[["term"]] <- 202580
  # opt[["skip_forecast"]] <- TRUE

  message("[course_report.R] Welcome to get_course_data!")

  # Extract CEDAR data objects (no legacy fallbacks)
  students <- data_objects[["cedar_students"]]
  courses <- data_objects[["cedar_sections"]]
  forecasts <- data_objects[["forecasts"]]
  hr_data <- data_objects[["cedar_faculty"]]

  # Bail out early with a clear error if required datasets are missing
  if (is.null(courses)) {
    stop("[course_report.R] cedar_sections dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(students)) {
    stop("[course_report.R] cedar_students dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(hr_data)) {
    stop("[course_report.R] cedar_faculty dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  
  # print out counts of data objects
  message("[course_report.R] Students data has ", nrow(students), " rows and ", ncol(students), " columns")
  message("[course_report.R] Courses data has ", nrow(courses), " rows and ", ncol(courses), " columns")
  message("[course_report.R] Forecasts data has ", nrow(forecasts), " rows and ", ncol(forecasts), " columns")
  message("[course_report.R] cedar_faculty data has ", nrow(hr_data), " rows and ", ncol(hr_data), " columns")

  # init payload list for return value
  course_data <- list()
  
  # Set term range for filtering (parallel to dept-report.R)
  course_data[["term_start"]] <- cedar_report_start_term
  course_data[["term_end"]] <- cedar_report_end_term
  
  # these should always be set this way
  opt$status <- "A"
  opt$uel <- TRUE
  
  # Apply term filtering to courses data (parallel to headcount.R line 427)
  message("[course_report.R] Filtering courses by term range: ", cedar_report_start_term, " to ", cedar_report_end_term, "...")
  courses_filtered <- courses %>% filter(term >= cedar_report_start_term & term <= cedar_report_end_term)
  message("[course_report.R] Courses after term filter: ", nrow(courses), " rows")
  
  # Apply term filtering to students data
  message("[course_report.R] Filtering students by term range: ", cedar_report_start_term, " to ", cedar_report_end_term, "...")
  filtered_students <- students %>% filter(term >= cedar_report_start_term & term <= cedar_report_end_term)
  message("[course_report.R] Students after term filter: ", nrow(students), " rows")
  
  # Pre-filter courses for most analyses
  message("[course_report.R] Pre-filtering courses for course ", opt[["course"]], "...")
  courses_filtered <- courses %>% filter(subject_course == opt[["course"]]) 
  
  # get filtered students for course - use pre-filtered data
  # keep students as is for lookout analysis
  message("[course_report.R] Filtering students (via filter_class_list) for course-report...")
  filtered_students <- students %>% filter_class_list(opt)

  # Check for no students after filtering
  if (is.null(filtered_students) || nrow(filtered_students) == 0) {
    message("[course_report.R] WARNING: No students found after filtering with opt parameters!")
  }

  # create term agnostic opt param for getting historic enrollments from DESRs
  myopt <- opt
  myopt[["term"]] <- NULL
  myopt[["group_cols"]] <- c("campus","college","term", "term_type", "subject", "subject_course", "course_title")
  
  # get basic enrollment data for forecast logic below
  # DO NOT pre-filter courses here - let get_enrl() do its own filtering
  message("[course_report.R] Getting basic cedar_sections data for course-report...")
  enrls <- get_enrl(courses, myopt)  # Use FULL courses dataset
  
  # get registration stats
  message("[course_report.R] Calling calc_cl_enrls to get registration stats data...")
  course_data[["cl_enrls"]] <- calc_cl_enrls(filtered_students)
  

  ####################
  # check if skipping new forecasts for shiny speed
  if (is.null(opt[["skip_forecast"]]) || opt[["skip_forecast"]] == FALSE) {
    
    # get forecast data for course to see if we need to do more...
    message("[course_report.R] Getting and filtering forecast data for course-report...")
    forecast_data <- forecasts
    
    # check for rows in case forecasts file doesn't exist
    if (!is.null(forecast_data) && nrow(forecast_data) > 0) {
      forecast_data <- forecast_data %>% filter (subject_course == myopt[["course"]])
      forecast_data <- add_term_type_col(forecast_data,"term") 
    } # end forecast table exists
    else {
      message("[course_report.R] No forecasting file found. Creating empty table...")
      forecast_data <- data.frame() 
    }
    
    # TODO: need better way to determine if we have enough rows now that we have campus data
    # don't forecast in case we never offer a course for that semester_type, since there's no previous target data
    message("[course_report.R] Checking forecast data for fall, spring, summer...")
    
    if (nrow(enrls %>% filter(term_type == "fall")) > 0 && nrow(forecast_data[forecast_data$term_type=="fall",]) < 6  ) {
      message("[course_report.R] Need more fall forecasts. Retroactively forecasting!")
      message("[course_report.R] Setting myopt$term to 'tl_falls' (from includes/lists.R)")
      myopt$term <- "tl_falls"
      forecast(students, courses, myopt)
    }
    
    if (nrow(enrls %>% filter(term_type == "spring")) > 0 && nrow(forecast_data[forecast_data$term_type=="spring",]) < 6) {
      message("need more spring forecasts. retroactively forecasting!")
      message("setting  myopt$term to 'tl_springs' (from includes/lists.R)")
      myopt$term <- "tl_springs"
      forecast(students, courses, myopt)
    }
    
    if (nrow(enrls %>% filter(term_type == "summer")) > 0 && nrow(forecast_data[forecast_data$term_type=="summer",]) < 6) {
      message("need more summer forecasts. retroactively forecasting!")
      message("setting  myopt$term to 'tl_summers' (from includes/lists.R)")
      myopt$term <- "tl_summers"
      forecast(students, courses, myopt)
    } 
  } # end check if skip forecasting
  else {
    message("[course_report.R] Skipping forecasting as per opt$skip_forecast=TRUE.")
  } 
  
  # reset term after forecasting
  myopt$term <- NULL

  # get forecast stats (w enrollments and accuracy) - skip if skip_forecast is TRUE
  if (is.null(opt[["skip_forecast"]]) || opt[["skip_forecast"]] == FALSE) {
    forecasts <- calc_forecast_accuracy(students, courses, myopt) # returns a list with short and long versions

    if (!is.null(forecasts)) {
      message("[course_report.R] Getting forecast_short data...")
      forecast_short <- forecasts[["forecast_short"]]

      # if any forecast short data, select cols
      if (!is.null(forecast_short) && nrow(forecast_short) > 0) {
        course_data[["forecasts"]] <- forecast_short %>%
          select(-c(dr_early_mean,dr_late_mean,use_enrl_vals,use_cl_vals))  %>%
          filter (subject_course %in% opt[["course"]])
      }
      else {
        course_data[["forecasts"]] <- forecast_short
      }
    }
  } else {
    message("[course_report.R] Skipping forecast accuracy calculation as per opt$skip_forecast=TRUE.")
    course_data[["forecasts"]] <- NULL
  }
  

  
  #################### 
  # run LOOKOUT functions to see where students are coming and going from
  # Use caching to avoid expensive recomputation
  message("[course_report.R] Getting lookout data...")
  
  # Check if we should skip cache (opt$skip_cache = TRUE to force recalculation)
  use_cache <- is.null(opt[["skip_cache"]]) || !opt[["skip_cache"]]
  
  if (use_cache) {
    # Try to load from cache
    lookout_cache <- load_lookout_cache(opt[["course"]], students, courses)
    
    if (!is.null(lookout_cache)) {
      message("[course_report.R] Using cached lookout data")
      course_data[["where_from"]] <- lookout_cache$where_from
      course_data[["where_to"]] <- lookout_cache$where_to
      course_data[["where_at"]] <- lookout_cache$where_at
    } else {
      message("[course_report.R] No cache found, calculating lookout data...")
      course_data[["where_from"]] <- where_from(students, myopt)  # Use ALL students for flow analysis
      course_data[["where_to"]] <- where_to(students, myopt)      # Use ALL students for flow analysis
      course_data[["where_at"]] <- where_at(students, myopt)      # Use ALL students for flow analysis
      
      # Save to cache
      lookout_data <- list(
        where_from = course_data[["where_from"]],
        where_to = course_data[["where_to"]],
        where_at = course_data[["where_at"]]
      )
      save_lookout_cache(opt[["course"]], lookout_data, students, courses)
    }
  } else {
    message("[course_report.R] Cache disabled (opt$skip_cache=TRUE), calculating fresh lookout data...")
    course_data[["where_from"]] <- where_from(students, myopt)  # Use ALL students for flow analysis
    course_data[["where_to"]] <- where_to(students, myopt)      # Use ALL students for flow analysis
    course_data[["where_at"]] <- where_at(students, myopt)      # Use ALL students for flow analysis
  }
  
  
  ################### 
  # get ROLLCALL data (and pivot to wide for report display)
  ####################
  message("[course_report.R] Getting rollcall data...")
  
  # Only get registered students
  message("[course_report.R] Setting myopt to look for RE and RS registration status codes only.")
  myopt[["registration_status_code"]] <- c("RE","RS")
  
  # rollcall by classification
  message("[course_report.R] Getting rollcall by classification...")
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "student_classification", "subject_course", "level")
  rollcall_by_class_raw <- rollcall(filtered_students, myopt)  # Use filtered data
  
  message("[course_report.R] rollcall_by_class_raw has ", nrow(rollcall_by_class_raw), " rows and ", ncol(rollcall_by_class_raw), " columns")
  if (nrow(rollcall_by_class_raw) > 0) {
    message("[course_report.R] rollcall_by_class_raw columns: ", paste(colnames(rollcall_by_class_raw), collapse = ", "))
    message("[course_report.R] First few rows of rollcall_by_class_raw:")
    print(head(rollcall_by_class_raw, 3))
  }
  
  # Keep raw data for plotting (long format) - avoid unnecessary copies
  rollcall_by_class_for_plot <- rollcall_by_class_raw
  message("[course_report.R] rollcall_by_class_for_plot has ", nrow(rollcall_by_class_for_plot), " rows")
  
  # Create wide format for table display - optimize pivot operation
  tryCatch({
    rollcall_by_class_table <- rollcall_by_class_for_plot %>%
      pivot_wider(names_from = term, values_from = term_type_pct, values_fill = 0)
  }, error = function(e) {
    message("[course_report.R] Error in pivot_wider for rollcall_by_class: ", e$message)
    rollcall_by_class_table <- rollcall_by_class_for_plot  # fallback to original data
  })
  
  message("[course_report.R] storing rollcall_by_class data...")
  course_data[["rollcall_by_class"]] <- rollcall_by_class_table
  course_data[["rollcall_by_class_plot_data"]] <- rollcall_by_class_for_plot
  
  
  # rollcall by major
  message("[course_report.R] Getting rollcall by major...")
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "major", "subject_course", "level")
  rollcall_by_major_raw <- rollcall(filtered_students, myopt)  # Use filtered data
  
  message("[course_report.R] rollcall_by_major_raw has ", nrow(rollcall_by_major_raw), " rows and ", ncol(rollcall_by_major_raw), " columns")
  if (nrow(rollcall_by_major_raw) > 0) {
    message("[course_report.R] rollcall_by_major_raw columns: ", paste(colnames(rollcall_by_major_raw), collapse = ", "))
    message("[course_report.R] First few rows of rollcall_by_major_raw:")
    print(head(rollcall_by_major_raw, 3))
  }
  
  # Keep raw data for plotting (long format) - avoid unnecessary copies
  rollcall_by_major_for_plot <- rollcall_by_major_raw
  
  message("[course_report.R] rollcall_by_major_for_plot has ", nrow(rollcall_by_major_for_plot), " rows")
  
  # Create wide format for table display - optimize pivot operation
  tryCatch({
    rollcall_by_major_table <- rollcall_by_major_for_plot %>%
      pivot_wider(names_from = term, values_from = term_type_pct, values_fill = 0)
  }, error = function(e) {
    message("[course_report.R] Error in pivot_wider for rollcall_by_major: ", e$message)
    rollcall_by_major_table <- rollcall_by_major_for_plot  # fallback to original data
  })
  

  message("[course_report.R] storing rollcall_by_major data...")
  course_data[["rollcall_by_major"]] <- rollcall_by_major_table
  course_data[["rollcall_by_major_plot_data"]] <- rollcall_by_major_for_plot


  #####################
  # Get GRADE DATA; opt term should be null to get all data
  message("[course_report.R] Getting grades data...")
  course_data[["grade_data"]] <- get_grades(filtered_students, hr_data, myopt)  # Use filtered data

  message("[course_report.R] Data gathering complete! Returning course data object...")
  return (course_data)
}


use_NSO_data_for_forecasts <- function() {
  ############### 
  # UNFINISHED: use nosedive to find out freshman contribution to course we're reporting on
  ###############
  message("looking for NSO flog and if target term type is fall...")
  if (opt$nso && get_term_type(opt[["term"]]) == "fall") {
    
    # load NSO data
    NSOers <- load_NSO_data()
    
    # calculate NSO Freshman contribution to course
    # use opt, which should have target term specified
    # forecast_enrl_from_majors uses rollcall, so make sure necessary params are set
    # TODO: needs to fit new rollcall code
    myopt[["group_col"]] <- c("campus", "college", "term", "student_classification", "major", "subject_course")
    prog_NSO_enrl <- forecast_enrl_from_majors(NSOers,students,opt)
    message("results from forecast_enrl_from_majors:")
    print(prog_NSO_enrl)
    
    # get just course for report 
    prog_NSO_enrl <- prog_NSO_enrl %>%
      filter (subject_course == opt$course) 
    
    # merge freshman projection
    message("merging nso_enrl_projections from nosedive with forecast data...")
    forecast_next_term <- merge (forecast_next_term, prog_NSO_enrl[ , c("subject_course","fresh_proj")], by = "subject_course")
    forecast_next_term %>% tibble::as_tibble() %>% print(n = nrow(.), width=Inf)
    
    # look up how many current NSOers are registered for specified target term (from opt)
    filtered_students <- students %>% filter_class_list(opt)
    
    message("getting number of NSOers registered in courses...")
    NSOers_in_course <- get_NSOers_in_courses(NSOers, filtered_students, opt)
    
    forecast_next_term <- merge (forecast_next_term, NSOers_in_course[ , c("subject_course","count")], by = "subject_course")
    forecast_next_term %>% tibble::as_tibble() %>% print(n = nrow(.), width=Inf)
  } else {
    message("ignoring nso data.")
  }  
}


# Interactive course report data generation (for Shiny)
create_course_report_data <- function(data_objects, opt) {
  message("[course_report.R] Welcome to create_course_report_data!")
  message("[course_report.R] Course: ", opt[["course"]])
    
  # display info about data objects
  if (is.null(data_objects) || length(data_objects) == 0) {
    message("[course_report.R] WARNING: data_objects is NULL or empty!")
  } else {
    message("[course_report.R] data_objects contains: ", paste(names(data_objects), collapse = ", "))
  }

  gc() # Clean up before starting

  # Extract CEDAR data objects (no legacy fallbacks)
  students <- data_objects[["cedar_students"]]
  courses <- data_objects[["cedar_sections"]]
  forecasts <- data_objects[["forecasts"]]
  

  # Get base course data
  message("[course_report.R] About to get_course_data for ", opt[["course"]], "...")
  course_data <- get_course_data(data_objects, opt)

  message("[course_report.R] Course data gathered. Data elements are: ", paste(names(course_data), collapse = ", "))
  
  
  # Create plots list
  plots <- list()
  message("[course_report.R] Creating plots and visualizations...")

  ####################
  # ENROLLMENT PLOT
  if (!is.null(course_data$cl_enrls) && nrow(course_data$cl_enrls) > 0) {
    message("[course_report.R] Creating enrollment plot...")
    tryCatch({
      
      message("[course_report.R] Calling make_enrl_plot_from_cls...")
      enrl_plot <- make_enrl_plot_from_cls(course_data$cl_enrls, opt)

      if (!is.null(enrl_plot) && "cl_enrl" %in% names(enrl_plot)) {
        plots$enrollment_plot <- enrl_plot$cl_enrl
        message("[course_report.R] Enrollment plot created successfully")
      } else {
        message("[course_report.R] Enrollment plot returned NULL or missing 'cl_enrl' component")
      }
    }, error = function(e) {
      message("[course_report.R] Error creating enrollment plot: ", e$message)
    })
  } else {
    message("[course_report.R] No enrollment data available for plotting")
  }
  

  ######################
  # SANKEY FLOW DIAGRAMS
  message("[course_report.R] Creating sankey flow diagrams...")
  tryCatch({
    if (!is.null(course_data$where_to) && !is.null(course_data$where_from)) {
      message("[course_report.R] where_to has ", nrow(course_data$where_to), " rows")
      message("[course_report.R] where_from has ", nrow(course_data$where_from), " rows")
      
      sankey_opt <- opt
      sankey_opt$min_contrib <- 2
      sankey_opt$max_courses <- 8
      
      # Debug: check contribution thresholds
      message("[course_report.R] Checking where_to contributions...")
      if (nrow(course_data$where_to) > 0) {
        where_to_contribs <- course_data$where_to$avg_contrib
        message("[course_report.R] where_to max contrib: ", max(where_to_contribs, na.rm=TRUE))
        message("[course_report.R] where_to >= 2: ", sum(where_to_contribs >= 2, na.rm=TRUE), " courses")
      }
      
      message("[course_report.R] Checking where_from contributions...")
      if (nrow(course_data$where_from) > 0) {
        where_from_contribs <- course_data$where_from$avg_contrib
        message("[course_report.R] where_from max contrib: ", max(where_from_contribs, na.rm=TRUE))
        message("[course_report.R] where_from >= 2: ", sum(where_from_contribs >= 2, na.rm=TRUE), " courses")
      }
      
      message("[course_report.R] Calling plot_course_sankey_by_term_with_flow_counts...")
      sankey_plots <- plot_course_sankey_by_term_with_flow_counts(
        course_data$where_to, 
        course_data$where_from, 
        sankey_opt
      )
      
      message("[course_report.R] Sankey function returned ", length(sankey_plots), " plots")
      if (length(sankey_plots) > 0) {
        message("[course_report.R] Sankey plot term types: ", paste(names(sankey_plots), collapse = ", "))
      }
      
      # Add individual sankey plots
      if (length(sankey_plots) > 0) {
        for (term_type in names(sankey_plots)) {
          plot_name <- paste0("sankey_", term_type, "_plot")
          plots[[plot_name]] <- sankey_plots[[term_type]]
          message("[course_report.R] Added plot: ", plot_name)
        }
      } else {
        message("[course_report.R] No sankey plots returned from function")
        message("[course_report.R] This usually means student flow is primarily self-referential (students retaking the same course)")
        message("[course_report.R] or insufficient cross-course enrollment patterns exist")
      }
    } else {
      message("[course_report.R] No lookout data available for sankey plots")
      message("[course_report.R] where_to is null: ", is.null(course_data$where_to))
      message("[course_report.R] where_from is null: ", is.null(course_data$where_from))
    }
  }, error = function(e) {
    message("[course_report.R] Error creating sankey plots: ", e$message)
    message("[course_report.R] Full error: ", toString(e))
  })
  

  # 3. Rollcall plots with consistent colors across term types
  message("[course_report.R] Creating rollcall plots with consistent colors...")

  # Use new helper function for consistent colors across fall, spring, summer
  class_plots <- plot_rollcall_with_consistent_colors(
    course_data[["rollcall_by_class_plot_data"]],
    fill_column = "student_classification",
    top_n = 6
  )
  plots$rollcall_by_class_plot <- class_plots
  
  major_plots <- plot_rollcall_with_consistent_colors(
    course_data[["rollcall_by_major_plot_data"]],
    fill_column = "major",
    top_n = 6
  )
  plots$rollcall_by_major_plot <- major_plots
  
  ##################
  # Rollcall plots
  message("[course_report.R] Creating rollcall time series plots...")
  plots$rollcall_by_class_time_plot <- plot_time_series(course_data[["rollcall_by_class_plot_data"]], fill_column = "student_classification")
  plots$rollcall_by_major_time_plot <- plot_time_series(course_data[["rollcall_by_major_plot_data"]], fill_column = "major")


  ##################
  # GRADE PLOTS
  message("[course_report.R] Creating grade plots...")
  plots_from_gradebook <- plot_grades_for_course_report(course_data[["grade_data"]], opt)
  message("[course_report.R] Grade plotting function returned ", length(plots_from_gradebook), " plots.")

  message("[course_report.R] Loading plots into course report data structure...")
  plots[["dfw_summary_plot"]] <- plots_from_gradebook[["dfw_summary_plot"]]
  plots[["dfw_by_term_plot"]] <- plots_from_gradebook[["dfw_by_term_plot"]]
  plots[["dfw_by_inst_type_plot"]] <- plots_from_gradebook[["dfw_by_inst_type_plot"]]

  message("[course_report.R] Added ", length(plots_from_gradebook), " grade plots.")

  
  # Prepare return data structure
  result <- list(
    course_code = opt[["course"]],
    course_name = opt[["course"]],
    plots = plots,
    tables = course_data,  # All the raw data tables
    opt = opt,
    generated_at = Sys.time()
  )
  
  message("[course_report.R] Interactive course report data complete!")
  message("[course_report.R] Generated ", length(plots), " plots")
  message("[course_report.R] Available plots: ", paste(names(plots), collapse = ", "))
  
  return(result)
}



# Original RMarkdown report function (unchanged)
create_course_report <- function(data_objects, opt) {
  message("[course_report.R] Welcome to create_course_report!")

  gc() # Clean up before starting

  message("[course_report.R] Gathering course data for ", opt[["course"]], "...")
  course_data <- get_course_data(data_objects, opt)
  
  # payload
  d_params <- list("opt" = opt,
                   "course_data" = course_data
  )

  message("[course_report.R] Rendering report for ", opt[["course"]], "...")

  # set output data
  message("[course_report.R] Setting output parameters...")
  d_params$output_filename  <- sub(" ", "_", opt[["course"]])
  message("[course_report.R] d_params$output_filename set to: ", d_params$output_filename)
  d_params$rmd_file <- paste0(cedar_base_dir,"/Rmd/course-report.Rmd")
  message("[course_report.R] d_params$rmd_file set to: ", d_params$rmd_file)
  d_params$output_dir_base <- paste0(cedar_output_dir,"course-reports/")
  message("[course_report.R] d_params$output_dir_base set to: ", d_params$output_dir_base)

  message("[course_report.R] Calling create_report...")
  create_report(opt,d_params)
}
