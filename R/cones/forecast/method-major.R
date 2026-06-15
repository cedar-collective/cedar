###################### MAJOR METHOD ##########################
# Instead of just looking at course enrollments as the CONDUIT method does,
# this MAJOR method looks at how MAJORS changed from prev conduit term to conduit term 
# (the conduit term is just the term before the target term)
# Then, apply the change in majors percentage to prev_target_term enrollments
# compute how much that will contribute to target term enrollment based composition of majors in target course

# This function only handles a single course and term at a time. 
# Current logic is likely to work better for spring than fall for LD courses

major_forecast <- function(students, courses, opt) {
  message("\n FORECASTING VIA MAJOR!")
  
  #for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "CHEM 1225"
  # opt[["term"]] <- "202510"
  # opt[["custom_conduit"]]  <- "202480"
  # opt[["conduit_for_term"]] <- "202560"
  
  target_course <- opt[["course"]]
  target_term <- opt[["term"]]
  
  target_term_type <- get_term_type(target_term)
  message("target term type set to: ",target_term_type)
  
  
  # see if user has supplied a conduit term besides default of target-1. (for projecting summer from fall...)
  # note: subtract_term defaults to ignoring summer, which is almost always want to do
  if (!is.null(opt[["custom_conduit"]]) && target_term == opt[["conduit_for_term"]]) {
    message("target term matches conduit_for_term; using custom_conduit.")
    conduit_term <- opt[["custom_conduit"]]  
  } else {
    # no special conduits; business as usual
    message("setting conduit term to be target_term - 1.")
    conduit_term <- subtract_term(target_term)   
  }
  
  message("conduit term set to ",conduit_term,".")
  
  #subtract one academic year for each target and conduit terms
  prev_target_term <- as.integer(target_term)-100
  prev_conduit_term <- as.integer(conduit_term)-100
  
  
  # determine how conduit enrollments changed from one year to the next
  message("finding conduit enrollments...")
  
  conduits_contributions <- get_course_feeders(students, opt) %>%
    rename(term_type = source_term_type, SUBJ_CRSE = subject_course)
  
  # keep only term_type of conduit course
  message("filtering conduit contributions by conduit term type...")
  conduits_contributions <- conduits_contributions %>% filter (term_type == get_term_type(conduit_term))
  
  
  # get enrollments from prev_conduit and conduit and use lag to see diff
  myopt <- opt
  myopt[["course"]] <- as.list(conduits_contributions$SUBJ_CRSE)
  myopt[["term"]] <- paste0(conduit_term,",",prev_conduit_term)
  myopt[["group_cols"]] <- c("CAMP","COLLEGE","TERM", "term_type", "SUBJ","SUBJ_CRSE","level","gen_ed_area")
  
  # the summarize here combines enrolled col for same SUBJ_CRSE (like topics courses)
  # NOTE: we can't forecast via conduits if we don't have prior semester enrollments
  conduit_enrls <- get_enrl(courses,myopt) %>% 
    group_by(CAMP, COLLEGE, SUBJ_CRSE, TERM) %>% 
    #summarize (enrolled = sum(enrolled)) %>% 
    select(CAMP, COLLEGE, SUBJ_CRSE, TERM, enrolled)

  #TODO:  if no conduit data, (ie we're forecasting for summer in the fall), make the conduits be one earlier semester
  if (nrow( conduit_enrls %>% filter (TERM == conduit_term)) == 0) {
    message("can't find any enrollment data for true conduit term. Using the closest term...")
    conduit_term <- subtract_term(conduit_term)
    prev_conduit_term <- subtract_term(prev_conduit_term)
  }
  

  message("processing ", target_course, " for ", target_term,".")
  
  # NOTE: basically everything is course agnostic until applying change in majors to target course
  
  # TODO: all instances of getting student list, then class count, should be done all at once w/o term filtering
  
  exclude_reg_codes <- c(STATUS_DROP_EARLY, STATUS_DROP_OTHER)
  
  # get all distinct students in previous conduit term
  # since we're counting majors, we need DISTINCT students across ALL classes.
  # TODO: better to use academic study guided ad hoc report (no course duplication...)?
  prev_conduit_student_list <- students %>% 
    filter (`Academic Period Code` == prev_conduit_term ) %>% 
    filter(!`Registration Status Code` %in% exclude_reg_codes) %>% 
    select(`Course Campus Code`, `Course College Code`, `Academic Period Code`,`Student ID`,`Major`,`Student Classification`) %>% 
    distinct()
  
  # tally students in previous conduit term by majors and classifications
  prev_conduit_class_count <- prev_conduit_student_list %>% group_by() %>%  
    count(`Course Campus Code`, `Course College Code`,`Academic Period Code`,Major, `Student Classification`)
  
  # get number of majors in conduit_term
  conduit_student_list <- students %>% 
    filter (`Academic Period Code` == conduit_term ) %>% 
    filter(!`Registration Status Code` %in% exclude_reg_codes) %>% 
    select(`Course Campus Code`, `Course College Code`,`Academic Period Code`,`Student ID`,Major,`Student Classification`) %>% 
    distinct()
  
  # tally students in previous target term by majors and classifications  
  conduit_class_count <- conduit_student_list %>% group_by() %>%  
    count(`Course Campus Code`, `Course College Code`,`Academic Period Code`,Major,`Student Classification`)
  
  # combine pre_conduit and prev_target counts
  conduits <- rbind(prev_conduit_class_count,conduit_class_count)
  
  # this is a nice display of how the number of Major/Classification changed over conduit semesters
  message("convert to wide format, so each row is a major/classification combination and terms are cols: ")
  conduits_wide <- spread(conduits, `Academic Period Code`, n)
  
  term_cols <- c(as.character(prev_conduit_term), as.character(conduit_term))
  if (any(is.na(conduits_wide[term_cols]))) {
    conduits_wide[term_cols][is.na(conduits_wide[term_cols])] <- 0
  }

  # compute differences between conduit terms
  conduits_wide$abs_diff <- conduits_wide[[as.character(conduit_term)]] - conduits_wide[[as.character(prev_conduit_term)]]
  conduits_wide$pct_diff <- conduits_wide[[as.character(conduit_term)]] / conduits_wide[[as.character(prev_conduit_term)]] * 100
  
  # for testing and inspection, order by greatest change
  conduits_wide <- conduits_wide %>% arrange(desc(abs_diff))
  
  # TODO: Be careful with fall->spring vs spring->fall projections
  # Don't factor in increases in majors for when students are already past a course.
  
  # Now that we know how conduits have changed in composition, see what prev_target was like for our course
  # get courses/enrollments from prev_target_term and apply pct diff to conduit_term enrollments
  prev_target_student_list <- students %>% 
    filter (`Academic Period Code` == prev_target_term & SUBJ_CRSE == target_course) %>%
    filter(!`Registration Status Code` %in% exclude_reg_codes) %>% 
    select(`Course Campus Code`, `Course College Code`, `Academic Period Code`,`Student ID` ,Major,`Student Classification`)  %>% 
    distinct()
  
  # count total students in previous conduit term (ie collapse students into majors and classifications)
  prev_target_class_count <- prev_target_student_list %>% group_by() %>% 
    count(name="prev_target_enrl",`Course Campus Code`, `Course College Code`, `Academic Period Code`,Major, `Student Classification`)
  

  # # filter out freshman if forecasting for fall, since those can be better estimated from nosedive
  # # for now, we only have nso data for fall 2024; don't use nosedive if forecasting earlier terms
  # if (opt$nso && target_term_type == "fall" && target_term == 202580) {
  #   message("term type detected as Fall 2024..." )
  #   prev_target_class_count <- prev_target_student_list %>% 
  #     filter (`Student Classification` != 'Freshman, 1st Yr, 1st Sem') %>% 
  #     filter (`Student Classification` != 'Freshman, 1st Yr, 2nd Sem') %>% 
  #     count(`Course Campus Code`, `Course College Code`, `Academic Period Code`,Major, `Student Classification`)
  # 
  #   # use nosedive to find out freshman contribution to course we're reporting on
  #   
  #   # load NSO data
  #   NSOers <- load_NSO_data()
  #   
  #   # calculate NSO Freshman contribution to course
  #   # use opt, which should have target term specified
  #   # forecast_enrl_from_majors uses rollcall, so make sure necessary params are set
  #   myopt <- opt
  #   myopt[["aggregate"]] <- "course_classification_major"
  #   prog_NSO_enrl <- forecast_enrl_from_majors(NSOers,students,myopt)
  #   message("results from forecast_enrl_from_majors:")
  #   print(prog_NSO_enrl)
  #   
  #   # get just course for report 
  #   prog_NSO_enrl <- prog_NSO_enrl %>% 
  #     filter (SUBJ_CRSE == opt$course) 
  # }
  # 
  
  
  # merge target_demographics with conduits
  conduits_w_prev_target <- merge(prev_target_class_count,conduits_wide,by=c("Course Campus Code", "Course College Code", "Major","Student Classification"))
  
  # if forecast term is current or past (not future), Academic Period Code col will have both prev_target_term and target_term
  # otherwise just the prev_target_term
  prev_term_enrls <- conduits_w_prev_target %>% mutate(proj_enrl = prev_target_enrl * (pct_diff/100) *1)

  # if enrollment doesn't change, the percent diff is INF, so just project the same number of students 
  prev_term_enrls$proj_enrl <- ifelse(is.finite(prev_term_enrls$proj_enrl), prev_term_enrls$proj_enrl, prev_term_enrls$prev_target_enrl)
  
  
  projections <- prev_term_enrls %>% 
    group_by(`Course Campus Code`, `Course College Code`, `Student Classification`, `Academic Period Code`) %>% 
    summarize(prev_target_enrl=sum(prev_target_enrl), target_proj_enrl=sum(proj_enrl), .groups = "keep")

  projections <- projections %>% group_by(`Course Campus Code`, `Course College Code`, `Academic Period Code`) %>% 
    summarise(target_proj_enrl = sum(target_proj_enrl), .groups = "keep")

  # add SUBJ_CRSE back into DF for reference and merging
  projections$SUBJ_CRSE <- opt[["course"]]
  
  # # if fall term, merge freshman projection, else placehold with NA
  # if (opt$nso && target_term_type == "fall" && target_term == 202480) {
  #   message("merging nso_enrl_projections from nosedive with forecast data...")
  #   enrl_projs <- merge (enrl_projs, prog_NSO_enrl[ , c("SUBJ_CRSE","fresh_proj")], by = "SUBJ_CRSE")
  # } else {
  #   enrl_projs$fresh_proj <- 0
  # }
  # 
  # as a continuation of above, APC is both prev_target and target (provided target is in the past)
  # i think only the prev_target rows make any sense
  #message("Enrollment projections by classification:")
  #enrl_projs %>% tibble::as_tibble() %>% print(n = 20, width=Inf)
  
  
  if (nrow(projections) != 0) {
    message("creating new forecast rows...")
    continuing_fc <- round(projections$target_proj_enrl,digits=0)
    incoming_fc <- round(0,digits=0) # disabled for now
    total_fc <- round(continuing_fc + incoming_fc, digits=0)
    
    # better column names
    new_summary <- data.frame(
      "CAMP" = projections$`Course Campus Code`,
      "COLLEGE" = projections$`Course College Code`,
      "TERM" = target_term,
      "SUBJ_CRSE" = projections$SUBJ_CRSE, 
      "method"="major", 
      "forecast" = total_fc,
      "continuing_forecast" = continuing_fc,
      "incoming_forecast" = incoming_fc
    )
    
  } else {
    message("unable to forecast because no previous target data...")
    new_summary <- data.frame()
  }                          
  
  message("major forecast complete! returning new rows...\n")
  
  # return new row
  return (new_summary) 
} 
