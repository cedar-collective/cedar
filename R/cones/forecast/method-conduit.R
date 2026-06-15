###################### CONDUIT METHOD ##########################
# For a given "target" course and term: 
# 0) Get Student IDs for students in previous (1 year ago) target course 
# 1) Identify what courses students are coming from before taking the given course. These are the "conduit" courses.
# 2) Identify how enrollments in the conduit courses changed from a year prior to target course.
# 3) Apply that pct diff to student demographics in target course

# TODO: does this count the same student multiple times in different conduit courses?
# TODO: this uses only last year's data; it should use an average of past years


# create a get_avg_enrl func in enrl.R that returns avg enrollment for set of courses and term type
# 
# use  weighted avg of conduit courses
# get enrl diff from each course to get average diff, but weight the conduit courses by contribution to target to get a composite enrollment diff
# then apply diff to total enrollment from prior year
# REQUIRES: course and term

conduit_forecast <- function(students, courses, opt) {
  message("\nFORECASTING VIA CONDUIT...")
  
  #for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "HIST 1160"
  # opt[["term"]] <- "202560"

  # opt[["custom_conduit"]]  <- "202480"
  # opt[["conduit_for_term"]] <- "202560"
  
  target_course <- opt[["course"]]
  target_term <- opt[["term"]]
  
  message("target course: ",target_course,"; target_term: ",target_term,".")
  
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
  
  message("subtracting year from target and conduit terms for getting previous enrollment data...")
  prev_target_term <- as.integer(target_term) - 100
  prev_conduit_term <- as.integer(conduit_term) - 100
  
  # get unique ids from students in prev target course (1 year previous to target course/term)
  # in other words: who was in the this course a year prior to when we're forecasting?
  # this is the "baseline" enrollment to which we will apply adjustments
  # NOTE: get_course_feeders is term agnostic, so it gets mean of contributing enrollments

  conduits_contributions <- get_course_feeders(students, opt) %>%
    rename(term_type = source_term_type, SUBJ_CRSE = subject_course)
  
  # keep only term_type of conduit course
  message("filtering conduit contributions by conduit term type...")
  conduits_contributions <- conduits_contributions %>% filter (term_type == get_term_type(conduit_term))
  
  # determine how conduit enrollments changed from one year to the next
  message("finding conduit enrollments...")
  
  # get enrollments from prev_conduit and conduit and use lag to see diff
  myopt <- opt
  myopt[["course"]] <- as.list(conduits_contributions$SUBJ_CRSE)
  myopt[["term"]] <- paste0(conduit_term,",",prev_conduit_term)
  myopt[["group_cols"]] <- c("CAMP","COLLEGE","TERM", "term_type", "SUBJ","SUBJ_CRSE","level","gen_ed_area")
  
  # the summarize here combines enrolled col for same SUBJ_CRSE (like topics courses)
  # note that we can't forecast via conduits if we don't have prior term_type enrollments
  conduit_enrls <- get_enrl(courses,myopt) %>% 
    group_by(CAMP, COLLEGE, SUBJ_CRSE, TERM) %>% 
    select(CAMP, COLLEGE, SUBJ_CRSE, TERM, enrolled)
  
  # if no conduit data, (ie we're forecasting for summer in the fall), make the conduits be one earlier semester
  if (nrow( conduit_enrls %>% filter (TERM == conduit_term)) == 0) {
    message("\n can't find any enrollment data for true conduit term. Trying one term back from original conduit term...")
    conduit_term <- subtract_term(conduit_term)
    prev_target_term <- as.integer(target_term) - 100
    prev_conduit_term <- subtract_term(prev_conduit_term)
    
    myopt[["term"]] <- paste0(conduit_term,",",prev_conduit_term)
    
    conduit_enrls <- get_enrl(courses,myopt) %>% 
      group_by(CAMP,COLLEGE,SUBJ_CRSE,TERM) %>% 
      select(CAMP,COLLEGE,SUBJ_CRSE, TERM, enrolled)
  }
  
  if (nrow(conduit_enrls > 0)) {
    
    # make sure each course has an enrollment (even if 0) for both terms
    conduit_enrls <- conduit_enrls %>% ungroup() %>% complete(CAMP,COLLEGE,SUBJ_CRSE, TERM, fill=list(enrolled=0))
    
    # calc enrollment differences between conduit terms
    message("calcuating differences between conduit terms...")
    conduit_enrl_diffs <- conduit_enrls %>% group_by(CAMP,COLLEGE,SUBJ_CRSE) %>% 
      arrange(CAMP,COLLEGE,SUBJ_CRSE) %>% 
      mutate(conduit_enrl_diff = enrolled/lag(enrolled))
    
    
    # filter out meaningless diffs (NAs and Infs)
    # these result from one of the semesters having 0 enrollment; hard to forecast if a course wasn't offered 
    conduit_enrl_diffs <- conduit_enrl_diffs %>% filter (TERM == conduit_term & is.finite(conduit_enrl_diff) & !is.na(conduit_enrl_diff) & enrolled > 0)
    
    # merge conduit contributions with enrl_diffs
    message("merging conduit contributions with enrl_diffs")
    conduit_enrl_diffs <- merge(conduits_contributions, conduit_enrl_diffs, by.x=c("Course Campus Code", "Course College Code","SUBJ_CRSE"), by.y=c("CAMP","COLLEGE","SUBJ_CRSE"))
    
    # TODO: provide option to use mean or previous_target_term options; maybe more accurate to use last year's enrollment only
    # but this would mean finding change from mean conduit enrollment as well
    # for now, just use previous_target_course enrollment 
    myopt <- opt
    myopt[["course"]] <- target_course
    # myopt[["term"]] <- get_term_type(target_term) # use term type if getting mean or last instance of course
    myopt[["term"]] <- prev_target_term 
    myopt[["group_cols"]] <- c("CAMP","COLLEGE", "TERM", "SUBJ_CRSE")
    prev_target_enrls <- get_enrl(courses,myopt)
    
    message("getting enrollment of previous target course...")
    prev_target_enrls <- get_enrl(courses,myopt) %>%
      #mutate (mean_enrl = avg_size) %>% # in case we want to do mean at some point
      select (CAMP,COLLEGE,prev_target_term = TERM,SUBJ_CRSE, prev_target_enrl = enrolled)
    
  
    conduit_enrls_prev_target_enrl <- merge(conduit_enrl_diffs, prev_target_enrls, by.x=c("Course Campus Code", "Course College Code","to_crse"), by.y=c("CAMP","COLLEGE","SUBJ_CRSE"), all=T )
    
    # TODO: if we don't have rows from prev_target, get enrls from closest term?
    # TODO: since enabling campuses, we need to check more carefully than just nrow.
    # check to make sure we have some rows
    message("checking for prior enrollments...")
    if (nrow(conduit_enrls_prev_target_enrl) > 0) {
      message("previous conduit and previous target enrollments found.")
    } 
    else {
      message("no conduit or previous target enrollments found.")
      conduit_enrls_prev_target_enrl$prev_target_enrl <- 0
      message("prev_target_enrl (in target term type) set to 0.")
    }
    
    message("forecasting target enrollment from previous semester and weighted mean of contributions...")
    conduit_enrls_prev_target_enrl <- conduit_enrls_prev_target_enrl %>% mutate(pct_from_conduit = avg_contrib / prev_target_enrl)   
    
    conduit_enrls_prev_target_enrl  <- conduit_enrls_prev_target_enrl %>%  group_by(`Course Campus Code`, `Course College Code`) %>%  
      mutate (mean_weighted = weighted.mean(conduit_enrl_diff, w = pct_from_conduit))
    
    conduit_enrls_prev_target_enrl  <- conduit_enrls_prev_target_enrl %>%  group_by(`Course Campus Code`, `Course College Code`) %>% 
      mutate(proj = prev_target_enrl*mean_weighted)
    
    projections <- conduit_enrls_prev_target_enrl %>% select (`Course Campus Code`,`Course College Code`, to_crse,TERM,proj) %>% 
      distinct()
    
  } else { # could not find conduit enrollments
    message("no projection! could not find conduit enrollments.")
  }
  
  
  if (nrow(projections) > 0) {
    message("combining incoming and continuing forecasts...")
    
    # continuing and incoming columns used by major method, so use here to be consistent with columns
    continuing_fc <- round(projections$proj,digits=0)
    incoming_fc <- 0
    total_fc <- round(continuing_fc + incoming_fc,digits=0)
    
    new_summary <- data.frame(
      "CAMP" = projections$`Course Campus Code`,
      "COLLEGE" = projections$`Course College Code`,
      "TERM" = target_term,
      "SUBJ_CRSE" = projections$to_crse, 
      "method" = "conduit", 
      "forecast" = total_fc,
      "continuing_forecast" = continuing_fc,
      "incoming_forecast" = incoming_fc
    )
    
  } else {
    message("unable to forecast because no previous target data.")
    new_summary <- data.frame()
  }                          
  
  message("conduit forecast complete! returning new rows...\n")
  
  # return new rows
  return (new_summary) 
} 
