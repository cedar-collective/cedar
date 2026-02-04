########### COMMAND HANDLER ##############
# this function is called from either cedar.R, CLI, or from cedar() if running interactively
# no data loading should occur here; it should already be loaded globally

command_handler <- function(opt) {
  
  if (is.null(opt$func)){
    return("No function (-f or --func) specified. Specify '-f guide' to see options. ")
  }
  else {
    message("[command-handler.R] looking up function: ", opt$func)  
  }
  

  ############### CREDIT HOURS ############### 
  if (opt$func == "credit-hours") {
    message("[command-handler.R] CREDIT HOURS!")
    if (opt$guide == TRUE) {
      message ("
            credit-hours uses specified filter params to create a simple report of earned credit hours.
            
            Usually, filter for a single dept (-d), but can also filter by college (with --coursecollege AS).
                        
            Use -h to see filtering params. ")
      stop("no error")
    }
    
    filtered_students <- filter_class_list(students, opt)
    credit_hours_data <- get_credit_hours(filtered_students)
    process_output(credit_hours_data, "credit_hours", opt) 
    
    return("[command-handler.R] done processing credit-hours!")
  }
  
  
  
  ############### COURSE REPORT ############### 
  if (opt$func == "course-report") {
    if (opt$guide == TRUE || ( is.null(opt$course))) {
      message ("
            course-report provides a broad overview of a course over time.
            Required params: 
            -c: a course like 'HIST 413' (WITH single quotes because of the space).
            
            Optional params:
            -t term code to forecast for. Default is term following current term (specified in config.R).
            --output-format: aspx or html. Use html (default) unless needing to publish via OneDrive.
            
            Reports are saved in CEDAR_OUTPUT_DIR/course-reports. 
            ")
      return("no error, but missing params.")
    }
    
    
    # if no term specified, use next term (for forecasting)
    if (is.null(opt[["term"]])) {
      # TODO: handle summer, both from --summer opt param and default
      next_term <- add_term(cedar_current_term)
      message("no opt$term param found. setting opt$term to: ",next_term)
      opt[["term"]] <- next_term
    }  
    
    # process course param
    message("processing course param...")
    course <- opt[["course"]]
    
    # handle special case of getting courses from forecast table  
    if (course == "forecasts") {
      message("creating course reports for courses in forecasts table...")
      
      # temp for redoing course reports based on courses in forecast-data
      forecast_data <- load_datafile("forecasts")
      course_list <- as.list(unique(forecast_data$SUBJ_CRSE))
      opt[["course"]] <- course_list
      
      # filter by target term so we don't create reports for old forecasting concerns
      message("filtering forecast_courses for target term: ",opt[["term"]]  ,"...")
      #print(opt)
      course_list <- filter_course_list(courses, course_list, opt)
      
    } # end if courses = forecasts
    # check for name of csv file
    else if (substring(course,nchar(course)-3,nchar(course)) == ".csv") {
      message("course set as CSV file...")
      
      filename <- paste0(cedar_output_dir,"/csv/",course)
      message("attempting to load: ", filename)
      
      if (file.exists(filename)) {
        message("loading CSV data...")
        csv_courses <- read.csv(filename)
      }
      else {
        stop("Sorry, cannot find CSV file.")
      }
      
      # check for basic SUBJ_CRSE column to provide helpful error message.
      if(!"SUBJ_CRSE" %in% colnames(csv_courses)) {
        stop("CSV file loaded, but no SUBJ_CRSE column.")
      }
      else {  
        # convert to list from tibble
        course_list <- as.list(csv_courses$SUBJ_CRSE)
        
        # pretend input param is a list of courses
        # term should remain as user opt original
        opt[["course"]] <- course_list
        
        message("finished loading CSV file as course list!")
        print(course_list)
      }
    } # end if csv file
    else { 
      message("regular opt course param found.")
      course_list <- convert_param_to_list(course)
    } # opt$course not null
    
    
    # loop through course_list 
    total_courses <- length(course_list)
    message("about to loop through ",total_courses ," courses:")
    print(course_list)
    counter <- 1
    
    # save exisiting opt params, including default term set earlier
    myopt <- opt
    myopt[["aggregate"]] <- "course"
    myopt[["nso"]] <- FALSE
    
    # load forecasts just once here before looping through reports and loading for each report
    # BUT, calc_forecast_accuracy loads file anyway to pick up new forecasts
    message("loading forecasts for command_handler...")
    forecasts <- load_datafile("forecasts")

    for (course in course_list) {
      myopt[["course"]] <- course
      message("\nNow processing course ",counter," of ",total_courses,": ",course,"...")
      create_course_report(students,courses,forecasts,myopt)
      counter <- counter + 1
    } # end course loop
    
    return("[command-handler.R] done processing course-report!")
  }
  
  
  
  ############### DATA STATUS  ############### 
  if (opt$func == "data-status") {
    if (opt$guide == TRUE) {
      message ("
            data-status reports on how recent data has been updated. No required params. ")
      stop("no error")
    }
    
    data_status_out <- get_data_status(students=students, 
                                       courses=courses, 
                                       academic_studies=academic_studies, 
                                       degrees=degrees, 
                                       fac_by_term=fac_by_term)
    
    process_output(data_status_out,"data_status",opt) #.csv is added in process_output
    
    return("[command-handler.R] done processing data_status!")
  }
  
  
  
  ############### DEPARTMENT REPORT ############### 
  if (opt$func == "dept-report") {
    if (!is.null(opt$guide) && is.null(opt$dept)) {
      message("Specify at least -d DEPT. In addition, you can ALSO use --prog PROG to focus on a particular degree program. 
      Otherwise data reflects aggregate of all degree programs.
            -d can also specify a pre-set list/vector of depts, defined in includes/lists.R.
            --output_format: html (default) or aspx")
      return("no error, but missing params.")
    }
    
    create_dept_report(data_objects, opt)
    return("[command-handler.R] done processing dept-report!")
  }
  
  
  
  ############### ENROLLMENT FROM DESR ############### 
  if (opt$func == "enrl") {
    if (!is.null(opt$guide) && opt$guide == TRUE) {
      message ("
             -a, --aggregate: [course, course_type, dept, dept_level, college_level]
             --aop: compress makes single DESR row from the AOP and ONL rows for same course
             -c, --course: specify SUBJ NUMB in single quotes, like 'MATH 1220'
                OR a comma-separated list like 'MATH 1215,MATH 1220'
                OR a named list as defined in lists.R 
             --campus: use standard abbreviation, like 'ABQ'
             --classification: student classification
             --college: use standard abbreviation, like 'AS'
             --crn: course reference number
             -d, --dept: department code, like HIST
             --gen-ed: gen ed area number
             -i, --inst: instructor LAST name
             --im: instruction method [0, ENH, MOP, HYB, ONL, f2f] 
             -l, --level: [undergrad, grad, lower, upper]
             --job_cat: job category
             --pt: part of term [1, 1H, 2H]
             --registration_status: student registration status
             -s, --subj: subject code, like GRMN
             -t, --term: term code (ie 202480)
                OR a comma-separated list like '202380,202410'
                OR a named list as defined in lists.R (like 'tl_springs') 
             --uel: use exclude course list (in includes/lists.R)
             -x, --crosslist: 'exclude' removes XLed courses; 'compress' compresses all XLed sections into a single row, with the subject code of the largest section
             ")
      stop("no error")
    }
    
    get_enrl_out <- get_enrl(courses,opt)
    process_output(get_enrl_out,"enrollments",opt)
  }
  
  
  
  ############### FORECAST ############### 
  if (opt$func == "forecast") {
    
    if (!is.null(opt[["forecast_conduit_term"]]) && is.null(opt[["term"]])) {
      stop("You must specify a target term (-t) if you specify a conduit term.")
    } 
    
    # if course, but no term, default to recent terms
    if (is.null(opt$term) && !is.null(opt$course)) {
      message("defaulting opt$term  to 'tl_recents'...")
      opt[["term"]] <- "tl_recents"
    }
    
    if (opt$guide){
      message("Forecasting 
      Required params: -c (course) AND  -t (term).
            Both can be either single values, comma-separated strings, or named lists.  
            Course can also be 'existing', which uses courses in forecast table,
              OR 'dimps', which looks for courses of concern.
            
            Output is basic forecast data for methods specified.
            
            ")
      return("no error, but missing params.")
    }
    
    forecasts <- forecast(students, courses, opt)
    
    # since it's almost always useful to see results right away, calc accuracy and recommendations
    forecast_data <- calc_forecast_accuracy(students, courses, opt)
    process_output(forecast_data, "forecasts", opt) #.csv is added in process_output
  }
  
  
  
  ############### FORECAST REPORT ############### 
  if (opt$func == "forecast-report") {
    
    # if course, but no term, default to recent terms
    if (is.null(opt$term) && !is.null(opt$course)) {
      message("setting opt$term  to 'tl_recents'...")
      opt[["term"]] <- "tl_recents"
    }
    
    if (opt$guide){
      message("Forecast-report 
      Optional params: -c (course) AND  -t (term).
            Both can be either single values, comma-separated strings, or named lists.  
            ")
      quit()
    }
    
    # display forecast report for opt params
    forecast_data <- calc_forecast_accuracy(students,courses,opt)
    
    # calc and show accuracy and recommendations
    process_output(forecast_data,"none",opt)
    
    # check for output flog 
    if (!is.null(opt[["output"]]) && (opt[["output"]] == "html" || opt[["output"]] == "aspx")) {
      create_forecast_report(forecast_data, opt)
    }
  }
  
  
  
  ########### GRADEBOOK ##############
  if (opt$func == "gradebook") {
    if (opt$guide == TRUE) {
      message ("
            Gradebook uses specified filter params to show student grades and DFW rates, but also more specifically the number of drops, withdraws, and fails.
            
            Usually, you'll at least want to filter for a class or small subset of classes.
            Example: -f gradebook -c 'MATH 1130'
            
            use the -a param to aggregate by some combination of course, term, and instructor
            options: course, course_term_avg, course_avg, all (default)
            the all param doesn't return anything, but prints everything in the terminal
            
            Use -h (instead of --guide) to see course filtering params. ")
      stop("no error")
    }
    # example standard output for a specific course 
    # summarized by course WITHOUT instructor data
    # `Academic Period Code` SUBJ_CRSE level `Long Course Title`    `DFW %`   `A+`    A   `A-`  `B+`    B  `B-`   `C+`    C  `C-`  `D+`     D     W passed failed dropped
    # 1 202110                 HIST 1105 lower Making History        36.8      2     6     4     3     5     1     2     0     1     0     0    14     24     14       8
    # 2 202180                 HIST 1105 lower Making History        27.6      0     1     1     2     5     0     3     4     4     1     0     8     21      8       2
    # 3 202210                 HIST 1105 lower Making History         9.52     2    10     2     1     0     1     0     2     0     0     1     2     19      2       3
    # 
    
    grades_out <- get_grades(data_objects,opt)
    process_output(grades_out,"csv/grades.csv",opt)
    
  }
  
  
  
  ########### HEADCOUNT ##############
  if (opt$func == "headcount") {
    if (opt$guide == TRUE) {
      message ("
            headcount uses specified filter params to show number of students in a unit.
            
            Optional param -a (aggregate) can be set to 'level' to provide undergrad and grad totals for all degrees.

            Usually, you'll at least want to filter for a dept.
            Example: Rscript cedar.R -f headcount -d ECON --group_cols level")
      stop("no error")
    }
    
    headcount_out <- get_headcount(data_objects[["cedar_programs"]], opt)
    process_output(headcount_out,"csv/headcount.csv", opt)

    return("[command-handler.R] done processing headcount!")
  }
  
  
  
  ########### LOOKOUT ##############
  if (opt$func == "lookout") {
    if (opt$guide == TRUE) {
      message ("
            lookout uses specified filter params to display for a specific course the most popular:
            - other courses that students are in at the same time
            - courses that students take the semester prior
            - courses that students take the next semester
            when run via CEDAR, it provides terminal output and saves output to 3 .Rda files in CEDAR_OUTPUT_DIR.
            
            This functionality is also used by dept-report and course-report.
            
            Required params: -c (course)
            For example: -c 'ENGL 1120'
             ")
      stop("no error")
    }
    
    # lookout controller doesn't yet return values, but saves 3 Rda files in the output/lookout folder
    lookout_out <- lookout(students, opt)
    process_output(lookout_out,"", opt) # don't need to supply csv name since we'll use list names
  }
  
  
  
  ########### NOSEDIVE ##############
  if (opt$func == "nosedive") {
    nosedive_out <- nosedive(courses, students, opt)  
  }
  

  
  ########### REGSTATS ##############
  if (opt$func == "regstats") {
    if (opt$guide == TRUE) {
      message ("
            regstats identifies courses with statistical enrollment anomalies using configurable thresholds.
            Analyzes enrollment bumps, dips, early/late drops, waitlists, and capacity squeezes.

            Output options (--output):
            csv: Save detailed tables as CSV files (default)
            html: Generate interactive HTML report  
            aspx: Generate ASPX format report
            shiny: Save dashboard data as .rds for Shiny app preloading

            Examples:
            ./cedar.R -f regstats --output shiny  # Generate data for Shiny dashboard
            ./cedar.R -f regstats --output html   # Create full HTML report
            ./cedar.R -f regstats -d HIST         # Analyze HIST department only
            
            For Shiny dashboard preloading (cron usage):
            ./cedar.R -f regstats --output shiny
            # Saves to data/regstats_dashboard.rds for app startup loading
            ")
      stop("no error")
    }
    
    # check if wanting report
    if (!is.null(opt[["output"]]) && (opt[["output"]] == "html" || opt[["output"]] == "aspx")) {
      create_regstat_report(students, courses, opt)
    }
    # check if wanting shiny dashboard data
    else if (!is.null(opt[["output"]]) && opt[["output"]] == "shiny") {
      message("[command-handler.R] Generating regstats data for Shiny dashboard...")
      
      # Ensure thresholds are set up exactly like server.R does for consistency
      if (is.null(opt[["thresholds"]])) {
        opt[["thresholds"]] <- list()
        opt[["thresholds"]][["min_impacted"]] <- cedar_regstats_thresholds[["min_impacted"]]
        opt[["thresholds"]][["min_wait"]] <- cedar_regstats_thresholds[["min_wait"]]
        opt[["thresholds"]][["pct_sd"]] <- cedar_regstats_thresholds[["pct_sd"]]
        opt[["thresholds"]][["min_squeeze"]] <- cedar_regstats_thresholds[["min_squeeze"]]
      }
      
      regstat_out <- get_reg_stats(students, courses, opt)
      
      # Create dashboard-ready data structure (matches server.R format exactly)
      dashboard_data <- list(
        flagged = regstat_out,
        opt = opt,
        generated_at = Sys.time()
      )
      
      # Save to data directory as .rds for Shiny app to load
      output_file <- file.path(cedar_base_dir, "data", "regstats_dashboard.rds")
      saveRDS(dashboard_data, output_file)
      
      message("[command-handler.R] Regstats dashboard data saved to: ", output_file)
      message("[command-handler.R] Total flagged courses: ", length(regstat_out$all_flagged_courses))
      
      return(paste("Regstats dashboard data generated and saved to", output_file))
    }
    else {
      regstat_out <- get_reg_stats(students, courses, opt)  
      process_output(regstat_out,"",opt) # don't need to supply csv name since we'll use list names
    }
  }
  

  
  ########### ROLLCALL ##############
  if (opt$func == "rollcall") {
    if (opt$guide == TRUE) {
      message ("
            rollcall uses specified filter params to show the classification (junior,senior,etc) and major of students.

            Use the -a flag to control summary groups and output: 
            course_major, course_classification, course_classification_major, major, major_wide, classification_wide, all (default)

            Usually, you'll at least want to filter for a class or small subset of classes.
            Example: -f rollcall -c 'MATH 1130'
            
            Use -h (instead of --guide) to see course filtering params. ")
      stop("no error")
    }
    
    rollcall_out <- rollcall(students, opt)
    process_output(rollcall_out,"rollcall", opt) 
  }
  
  
  
  ########### SEATFINDER REPORT ##############
  if (opt$func == "seatfinder-report") {
    if (opt$guide == TRUE || is.null(opt[["term"]]) ) {
      message ("seat_finder_report compares course offerings from two semesters and creates a simple report about similarities and differences and where there are open seats.\n
              Required params: -t param should be set with a pair of semester codes like  '202380,202480'.

              You should also set some filtering params, like level, dept, gen_ed, to make the comparison report readable.
             Use -h to see filtering params. ")
      stop("no error")
    }

    # Load cedar_faculty for grades calculation
    cedar_faculty <- load_datafile("cedar_faculty")
    create_seatfinder_report(students, courses, cedar_faculty, opt)
  }
  
  
  
  ############### WAITLIST  ############### 
  if (opt$func == "waitlist") {
    if (opt$guide == TRUE || (is.null(opt$course) && is.null(opt$term)) ) {
      message ("
            waitlist finds the number of students waitlisted for a course who are not also registered.
            Usually, filter by a specific course and term, like:
            -f waitlist -c 'ENGL 1110' -t 202480
            
            Most of the output is terminal only. Students waiting and NOT registered are saved in waitlist_demand.csv
            Use -h to see filtering params. ")
      stop("no error")
    }
    
    waitlist_out <- inspect_waitlist(students, opt)
    process_output(waitlist_out,"waitlist", opt)
  }
  
} ############ END PROCESS FUNCTION PARAM ################
