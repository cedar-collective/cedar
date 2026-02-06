# Two main functions:
# 1. compute accuracy stats for already completed forecasts using the forecast_data.Rda file
# 2. generate a formatted HTML/ASPX report 


####### TESTING, INCOMPLETE ########
find_major_enrl_correlations <- function(courses, opt) {

  # uncomment for studio testing
  # courses <- load_courses()
  # opt <- list()
  
  # aggregate course enrollments across sections
  # get enrollment data for courses in forecast_data
  myopt <- opt
  myopt$aggregate <- "course"
  myopt[["term"]] <- NULL
  #myopt[["course"]] <- list('ENGL 1110',"ENGL 1120")
  
  # test majors and enrollment correlations
  message("getting enrollment data...")
  enrls <- get_enrl(courses,myopt)
  
  # find any correlation between changing numbers of majors and course enrollment
  # ends up being too messy
  majors <- get_agg_major(students)
  merged <- merge(enrls, majors, by.y=c("Academic Period Code"), by.x="TERM", keep = TRUE )
  merged <- merged %>% group_by(SUBJ_CRSE,Major)  
  cor <- merged %>% summarize(cor=cor(enrolled,count)) %>%  arrange(desc(cor))
  
}


#### INcOMPLETE LINEAR MODEL WORK
# summary <- get_enrl(courses,myopt)
# summary <- add_term_bins(summary,"TERM")
# 
# options(scipen=999)
# 
# # returns tidy tibble with summary stats
# stats <- summary %>% group_by(SUBJ_CRSE,term_type)  %>% group_modify(~ broom::tidy(lm(enrolled ~ term_bin, data = .x)))
# 
# # can also use standard lm functionality
# #lms <- enrls %>% group_by(SUBJ_CRSE,term_type)  %>% group_map(~ (lm(enrolled ~ term_bin, data = .x)))
# 
# stats$estimate <- round(stats$estimate, digits=2)
# 
# stats_sorted <- stats %>% filter(term == "term_bin") %>% arrange(desc(estimate))
# 




# calc_forecast_accuracy loads previously generated forecasting data from the forecasts.Rda file
# and merges enrollment data with forecast data to display together and compute accuracy of forecasts
# OPTIONAL param: opt$course for filtering returned data

calc_forecast_accuracy <- function(students, courses, opt) {
  message("\nWelcome to calc_forecast_accuracy!")
  
  #uncomment for studio testing
  # courses <- load_courses()
  # students <- load_students()
  # 
  #opt <- list()
  #opt$course <- "SOCI 1110"
  #opt$term <- "202560"

  # load existing forecast data
  forecast_data <- load_datafile("forecasts")
  
  # if empty data, return empty list
  if (nrow(forecast_data) == 0) {
    message("incoming forecasts is empty. returning empty tibble.")
    return (tibble())
  }
  
  # earlier forecast code didn't round
  forecast_data$forecast <- round(forecast_data$forecast, digits=2)
  
  # filter for course
  if (!is.null(opt$course)) {
    message("filtering forecast data for course...")
    course_list <- convert_param_to_list(opt$course)
    forecast_data <- forecast_data %>% filter (SUBJ_CRSE %in% course_list)
  }
  
  # filter for college
  if (!is.null(opt$course_college)) {
    message("filtering forecast data for college...")
    college_list <- convert_param_to_list(opt$course_college)
    forecast_data <- forecast_data %>% filter (COLLEGE %in% college_list)
  }

  # check to see if we have any data
  if (!is.null(forecast_data) && nrow(forecast_data) == 0) {
    message("no forecast data for that course! returning NULL from calc_forecast_accuracy()...")
    return(NULL)
  } else {
    message("found ", nrow(forecast_data), " rows of forecast data for course(s) in forecast_data")
  }
  
  # make easier to read with wide format, so forecast methods have their own column
  message("pivoting to wide...")
  forecast_data <- forecast_data %>% select (-c(continuing_forecast,incoming_forecast)) 
  forecast_data_wide <- forecast_data %>% pivot_wider(names_from = method, values_from = forecast)
  
  # get DESR enrollment data for courses in forecast_data, esp SEATS_AVAIL for later calcs (summarized as avail)
  myopt <- opt
  myopt[["group_cols"]] <- c("CAMP","COLLEGE", "TERM", "term_type", "SUBJ", "SUBJ_CRSE")
  #myopt$aop <- "compress" # not working with null term?
  myopt[["term"]] <- NULL # remove any term filtering for now to get all enrollments
  myopt[["course"]] <- as.list(unique(forecast_data$SUBJ_CRSE))
  
  message("getting DESR enrollment data...")
  enrls <- get_enrl(courses,myopt)
  
  # merge enrl data with forecast data; 
  # merge TO forecast data to prevent data loss, esp future terms not present in enrls
  message("merging forecast summary data with enrollment summary data...")
  enrl_w_forecast <- merge (forecast_data_wide, enrls, by=c("CAMP", "COLLEGE", "SUBJ_CRSE", "TERM"),all.x=T)
  
  # even tho col already exists, adding it here replaces NA values from terms when course wasn't offered
  enrl_w_forecast <- add_term_type_col(enrl_w_forecast,"TERM")
  
  # fill in missing values if not matched in merge (without term dependence)
  # removing level and gen_ed_area from select
  selected <- enrls %>% ungroup() %>% select (c(CAMP,COLLEGE,SUBJ_CRSE)) %>% distinct(SUBJ_CRSE, .keep_all = T)
  enrl_w_forecast <- rows_patch(enrl_w_forecast, selected, by=c("SUBJ_CRSE") )
  
  # filter students according to courses in forecast table
  filtered_students <- students %>% filter (SUBJ_CRSE %in% myopt[["course"]])
  
  # calc_cl_enrls get registration stats (drop data for different accuracy calcs)
  message("getting class list data w/ drop data for accuracy calcs...")
  cl_enrls <- calc_cl_enrls(filtered_students)
  
  message("merging forecast summary data with cl_enrls summary data...")
  enrl_w_forecast <- merge (enrl_w_forecast, cl_enrls, by.x=c("CAMP", "COLLEGE", "SUBJ_CRSE", "TERM","term_type"), by.y=c("Course Campus Code", "Course College Code", "SUBJ_CRSE", "Academic Period Code","term_type") ,all.x=T)
  
  selected <- enrl_w_forecast %>% group_by(CAMP,COLLEGE,SUBJ_CRSE,term_type) %>% 
    select (c(CAMP,COLLEGE,SUBJ_CRSE,term_type, dr_early_mean,dr_late_mean,dr_all_mean)) %>% 
    distinct(CAMP,COLLEGE,SUBJ_CRSE,term_type, .keep_all = T)
  
  
  message("patching enrl_w_forecast with selected to get drop means...")
  enrl_w_forecast <- rows_patch(enrl_w_forecast, selected, by=c("CAMP","COLLEGE", "SUBJ_CRSE","term_type") )
  print(enrl_w_forecast)
  
  
  # return empty data frame if no forecast data available
  if (nrow(enrl_w_forecast) == 0) {
    message("no forecast data available; no stats to compute. returning empty data frame...")
    return (data.frame())
  }
  
  # ensure conduit and major columns exist
  # if not, set to 0
  message("ensuring conduit and major columns exist...")
  if (!"conduit" %in% names(enrl_w_forecast)) {
    enrl_w_forecast$conduit <- 0
  }
  if (!"major" %in% names(enrl_w_forecast)) {
    enrl_w_forecast$major <- 0
  }

  message("computing conduit and major forecasts when accounting for drops...")
  enrl_w_forecast <- enrl_w_forecast %>% mutate (conduit_wo_dr = round(conduit - (dr_early), digits=0), .after = conduit )
  enrl_w_forecast <- enrl_w_forecast %>% mutate (major_wo_dr = round(major - (dr_early), digits=0), .after = major )

  forecast_summary <- enrl_w_forecast
  
  message("computing enrl accuracy...")
  forecast_summary <- forecast_summary %>% 
    mutate (c_enrl_accr = round(conduit/enrolled,digits=2), 
            c_dr_enrl_accr = round(conduit_wo_dr/enrolled,digits=2), 
            m_enrl_accr = round(major/enrolled,digits=2), 
            m_dr_enrl_accr = round(major_wo_dr/enrolled,digits=2),
            ) 
  
  
  message("computing cl accuracy...")
  forecast_summary <- forecast_summary %>% 
    mutate (c_cl_accr = round(conduit/cl_total,digits=2), 
            c_dr_cl_accr = round(conduit_wo_dr/cl_total,digits=2), 
            m_cl_accr = round(major/cl_total,digits=2),
            m_dr_cl_accr = round(major_wo_dr/cl_total,digits=2)
    ) 
  

  # calc group summary stats
  message("computing summary stats...")
  
  forecast_summary_enrl_avgs <- forecast_summary %>%
    group_by(SUBJ_CRSE,term_type) %>%
    summarize(
      avg_c_enrl_accr = round(abs( 1 - mean(c_enrl_accr, na.rm=TRUE)),digits=2),
      avg_c_dr_enrl_accr = round(abs( 1 - mean(c_dr_enrl_accr, na.rm=TRUE)),digits=2),
      avg_m_enrl_accr = round(abs( 1 - mean(m_enrl_accr, na.rm=TRUE)),digits=2),
      avg_m_dr_enrl_accr = round(abs( 1 - mean(m_dr_enrl_accr, na.rm=TRUE)),digits=2), .groups="keep"
    )
  

  forecast_summary_cl_avgs <- forecast_summary %>%
    group_by(SUBJ_CRSE,term_type) %>%
    summarize(
      avg_c_cl_accr = round(abs( 1 - mean(c_cl_accr, na.rm=TRUE)),digits=2),
      avg_c_dr_cl_accr = round(abs( 1 - mean(c_dr_cl_accr, na.rm=TRUE)),digits=2),
      avg_m_cl_accr = round(abs( 1 - mean(m_cl_accr, na.rm=TRUE)),digits=2),
      avg_m_dr_cl_accr = round(abs( 1 - mean(m_dr_cl_accr, na.rm=TRUE)),digits=2), .groups="keep"
    )

  # convert NAs to 0 for calcs
   forecast_summary_cl_avgs[is.na(forecast_summary_cl_avgs)] <- 0
   forecast_summary_enrl_avgs[is.na(forecast_summary_enrl_avgs)] <- 0
  
  message("identifying the best method...")
  forecast_summary_enrl_avgs$pref_enrl_method <- colnames(forecast_summary_enrl_avgs)[apply(forecast_summary_enrl_avgs,1,which.min)]
  forecast_summary_enrl_avgs$pref_enrl_method <- substring(forecast_summary_enrl_avgs$pref_enrl_method,5)
  forecast_summary_enrl_avgs$pref_enrl_method <- substr(forecast_summary_enrl_avgs$pref_enrl_method,1,nchar(forecast_summary_enrl_avgs$pref_enrl_method)-5)
  
  
  
  forecast_summary_cl_avgs$pref_cl_method <- colnames(forecast_summary_cl_avgs)[apply(forecast_summary_cl_avgs,1,which.min)]
  forecast_summary_cl_avgs$pref_cl_method <- substring(forecast_summary_cl_avgs$pref_cl_method,5)
  forecast_summary_cl_avgs$pref_cl_method <- substr(forecast_summary_cl_avgs$pref_cl_method,1,nchar(forecast_summary_cl_avgs$pref_cl_method)-5)
  
  
  forecast_summary <- merge(forecast_summary,forecast_summary_enrl_avgs)
  forecast_summary <- merge(forecast_summary,forecast_summary_cl_avgs)
  
  forecast_summary <- forecast_summary %>% select(-c(avg_c_enrl_accr,avg_c_cl_accr,avg_c_dr_enrl_accr,avg_c_dr_cl_accr,avg_m_enrl_accr,avg_m_dr_enrl_accr,avg_m_cl_accr,avg_m_dr_cl_accr))
  
  # group according to SUBJ_CRSE and term_type so that lag function can get previous term_type enrollment
  forecast_summary <- forecast_summary %>% group_by(SUBJ_CRSE,term_type) %>% arrange(SUBJ_CRSE,TERM)

  
  # if major method forecasts 0 b/c of no prior enrollment data, set pref_method to conduit variant
  # forecast_summary %>%  filter (major == 0 & conduit != 0) %>% mutate(pref_method = case_when(
  #   pref_method == "m" ~ "c",
  #   pref_method == "m_cl" ~ "c_cl",
  #   pref_method == "m_dr" ~ "c_dr"
  # ))
  # 
  # create col of forecast to use based on preferred method
  forecast_summary <- forecast_summary %>% mutate(use_enrl_vals = case_when(
    pref_enrl_method == "m_enrl" ~ major,
    pref_enrl_method == "m_dr_enrl" ~ major_wo_dr,
    pref_enrl_method == "c_enrl" ~ conduit,
    pref_enrl_method == "c_dr_enrl" ~ conduit_wo_dr
  ))

  forecast_summary <- forecast_summary %>% mutate(use_cl_vals = case_when(
    pref_cl_method == "m_cl" ~ major,
    pref_cl_method == "m_dr_cl" ~ major_wo_dr,
    pref_cl_method == "c_cl" ~ conduit,
    pref_cl_method == "c_dr_cl" ~ conduit_wo_dr
  ))
  
  
  forecast_summary <- forecast_summary %>% group_by(SUBJ_CRSE,term_type)
  
  forecast_summary <- forecast_summary %>% mutate(avg_c_enrl_accr = round(mean(c_enrl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_c_cl_accr = round(mean(c_cl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_c_dr_enrl_accr = round(mean(c_dr_enrl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_c_dr_cl_accr = round(mean(c_dr_cl_accr, na.rm=TRUE),digits=2))
  
  forecast_summary <- forecast_summary %>% mutate(avg_m_enrl_accr = round(mean(m_enrl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_m_cl_accr = round(mean(m_cl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_m_dr_enrl_accr = round(mean(m_dr_enrl_accr, na.rm=TRUE),digits=2))
  forecast_summary <- forecast_summary %>% mutate(avg_m_dr_cl_accr = round(mean(m_dr_cl_accr, na.rm=TRUE),digits=2))
  
  forecast_summary <- forecast_summary %>% mutate(avg_enrl_accr = case_when(
    pref_enrl_method == "m_enrl" ~ avg_m_enrl_accr,
    pref_enrl_method == "m_dr_enrl" ~ avg_m_dr_enrl_accr,
    pref_enrl_method == "c_enrl" ~ avg_c_enrl_accr,
    pref_enrl_method == "c_dr_enrl" ~ avg_c_dr_enrl_accr
  ))
  
  forecast_summary <- forecast_summary %>% mutate(avg_cl_accr = case_when(
    pref_cl_method == "m_cl" ~ avg_m_cl_accr,
    pref_cl_method == "m_dr_cl" ~ avg_m_dr_cl_accr,
    pref_cl_method == "c_cl" ~ avg_c_cl_accr,
    pref_cl_method == "c_dr_cl" ~ avg_c_dr_cl_accr
  ))
  
  
  # closest_column <- function(df) {
  #   differences <- sapply(df, function(col) min(abs(col - 1)))
  #   closest_col <- names(differences)[which.min(differences)]
  #   return(closest_col)
  # }
  # 
  # # Apply the function to your dataframe
  # closest_column(df)
  # 
  # group and arrange for lag calcs
  forecast_summary <- forecast_summary %>% group_by (CAMP,COLLEGE,SUBJ_CRSE, term_type) %>% 
    arrange(CAMP,COLLEGE,SUBJ_CRSE,term_type,TERM) 

  # try to fractionally estimate how many sections are needed based on sections size from previous term type
  # why not calc sections as use_enrl_vals / 
  message("estimating section needs...")
  forecast_summary <- forecast_summary %>% 
    mutate (rec_enrl_sections = round( use_enrl_vals / ((lag(enrolled) + lag(avail)) / lag(sections)),digits=2))

  forecast_summary <- forecast_summary %>% 
    mutate (rec_cl_sections = round( use_cl_vals / ((lag(cl_total) + lag(avail)) / lag(sections)),digits=2))
  
  # calc how much section need differs from prev term_type
  forecast_summary <- forecast_summary %>% 
    mutate (diff_fr_prev_enrl = round( rec_enrl_sections - lag(sections),digits=2),
            diff_fr_prev_cl = round( rec_cl_sections - lag(sections),digits=2)) 

  
  # reorder by course; can use opt$arrange to order by something else
  forecast_summary <- forecast_summary %>% arrange(SUBJ_CRSE,TERM)
  
  # filter now (at very end) so previous enrollments are available for earlier calculations
  if (!is.null(opt$term)) {
    message("filtering for term...")
    term_list <- convert_param_to_list(opt$term)
    forecast_summary <- forecast_summary %>%  filter_by_term(opt$term,"TERM") 
  }
  
  # use thresholds for adjusting computed recommendations
  # forecast_summarhy <- process_recommendations(forecast_summary)
  
  forecast_summary_short <- forecast_summary %>% ungroup() %>% select(CAMP,COLLEGE,SUBJ_CRSE,TERM,enrolled,cl_total,dr_early_mean,dr_late_mean,sections,avg_size,avail,
                                                                      conduit,major,pref_enrl_method,pref_cl_method,use_enrl_vals,use_cl_vals,avg_enrl_accr,avg_cl_accr,
                                                                      rec_enrl_sections,rec_cl_sections,diff_fr_prev_cl,diff_fr_prev_enrl)
  
  forecast_summary <- forecast_summary %>% ungroup() %>% select(CAMP,COLLEGE,SUBJ_CRSE,TERM,enrolled,cl_total,dr_early,dr_early_mean,dr_late,dr_late_mean,sections,avg_size,avail,
                                                                conduit,conduit_wo_dr,c_enrl_accr,avg_c_enrl_accr, c_dr_enrl_accr, avg_c_dr_enrl_accr,c_cl_accr, avg_c_cl_accr, c_dr_cl_accr, avg_c_dr_cl_accr, 
                                                                major, major_wo_dr, m_enrl_accr, avg_m_enrl_accr, m_dr_enrl_accr, avg_m_dr_enrl_accr, m_cl_accr, avg_m_cl_accr, m_dr_cl_accr, avg_m_dr_cl_accr,
                                                                pref_enrl_method,pref_cl_method,use_enrl_vals,use_cl_vals,avg_enrl_accr,avg_cl_accr,
                                                                rec_enrl_sections,rec_cl_sections,diff_fr_prev_enrl,diff_fr_prev_cl)
  
  payload <- list()
  payload[["forecast_short"]] <- forecast_summary_short
  payload[["forecast_long"]] <- forecast_summary
  
  message("forecast-report done and returning forecast_summary...")
  return(payload)
}



process_recommendations <- function(forecast_summary) {

    # flag any courses that need more investigation because they are on the bubble of needing more or less
  # if within .3 of integer, round up or down to it.
  # otherwise section recommendation to -1 to flag for further analysis
  forecast_summary <- forecast_summary %>% mutate (recommendation =
                                                     ifelse(ceiling(rec_sections) -  rec_sections < cedar_regstats_thresholds[["section_proximity"]], ceiling(rec_sections),
                                                            ifelse(rec_sections - floor(rec_sections) < cedar_regstats_thresholds[["section_proximity"]], floor(rec_sections), -100)
                                                            )
                                                   )

  # flag any courses with large diff_fr_prev (large is more than 1 section)
  # these can be smoothed over time based on other course data, but for now we need manual inspection
  forecast_summary <- forecast_summary %>% mutate (recommendation =
                                                     ifelse(diff_fr_prev > 1, -101, recommendation))

  
  return(forecast_summary)
}






############### GENERAL FUNCTION START ##################
# this function generates a report, and first computes accuracy stats

create_forecast_report <- function(forecast_data, opt) {
  message("welcome to forecast-report!")

  timing_log <- file.path(getwd(), "forecast_crunch_times.csv")
  crunch_start_time <- Sys.time()

  if (!is.null(opt[["arrange"]])) {
    arrange_col <- opt[["arrange"]]
    forecast_data <- forecast_data %>%  arrange(get({{arrange_col}}) )
  }
  
  # payload
  d_params <- list(
    "opt" = opt,
    "tables" = list(
      "forecasts" = forecast_data
      #"forecast_next_term" = forecast_next_term
    )
  )
  
  # Save crunch timing to log file
  crunch_end_time <- Sys.time()
  crunch_elapsed_sec <- as.numeric(difftime(crunch_end_time, crunch_start_time, units = "secs"))
  timing_row <- data.frame(
    timestamp = format(crunch_start_time, "%Y-%m-%d %H:%M:%S"),
    crunch_sec = crunch_elapsed_sec,
    stringsAsFactors = FALSE
  )
  if (!file.exists(timing_log)) {
    write.table(timing_row, timing_log, sep = ",", row.names = FALSE, col.names = TRUE, append = FALSE)
  } else {
    write.table(timing_row, timing_log, sep = ",", row.names = FALSE, col.names = FALSE, append = TRUE)
  }
  message(sprintf("[create_forecast_report] Data crunch: %.2f s (logged to %s)", crunch_elapsed_sec, timing_log))

  message("rendering forecast report...")
  
  # set output data
  output_filename <- "forecast-report"
  d_params$output_filename <- output_filename
  d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "forecast-report.Rmd")
  d_params$output_dir_base <- file.path(cedar_output_dir, "forecast-reports")
  
  create_report(opt,d_params)
  
  message("all done in forecast-report!")
}
