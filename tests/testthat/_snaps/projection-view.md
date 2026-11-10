# historical-method plot compares one term type with lifecycle actuals

    Code
      cat(trace_names, sep = "\n")
    Output
      Ever registered (model target)
      First day (seats judged here)
      Census
      Final / last day
      Last year's registrations
      Last year's registrations, adjusted (selected)

# the range's rolling coverage is reported by whether seats held

    Code
      cat(summary$sentence, "\n\n")
    Output
      The range assumes seats like last year's. Rebuilt for each past forecast from the course's earlier ones only, it held 3 of 3 times when seats stayed within 10% of the year before, and 0 of 1 when they moved. Of its 1 miss, 1 had registrations above it. 
      
    Code
      cat(none$sentence, "\n")
    Output
      The range assumes seats like last year's. No past forecast has an earlier one to build a range from, so how often it held cannot be shown yet. 

# the draft comparison separates short of day one from short of the plan

    Code
      cat(paste0(table$course, ": ", table$verdict), sep = "\n")
    Output
      DAY 1: Short of day-one seats by 30 (1 section); 50 short of the plan (2 sections)
      PLAN 1: Covers day one; 10 short of the plan (1 section)
      MISSING 1: Not in the draft schedule
      COVER 1: Covers the plan, 5 to spare
      SPARE 1: 90 seats beyond the plan
    Code
      cat("\n", draft$sentence, "\n\n", sep = "")
    Output
      
      The draft schedule (pulled October 8, 2026) has 475 seats in 4 of the 5 courses shown, against 440 planned registrations. 1 course is short of the students expected on day one (by 30 seats); 1 covers day one but not the plan; 1 covers the plan; 1 has more than a section to spare. 1 monitored course is not in the draft. For the 2 courses near full last year, the draft's seats would hold about 272 registrations if they fill as last year's did, against 220 planned.
      
    Code
      cat(none$sentence, "\n")
    Output
      No schedule for Spring 2027 is in the data yet. It appears here after a refresh pulls the target term's DESR from MyReports, and the bundle rebuilds with it. 

# Course Dynamics reads one course's outlook off the saved bundle and says why a course has none

    Code
      cat(outside$sentence, "\n\n")
    Output
      ENGL 1110 is not in the monitored course groups the Fall 2020 projections cover. Projections are made only for monitored courses. 
      
    Code
      cat(left_out$sentence, "\n\n")
    Output
      TEST 999 is monitored but was not projected for Fall 2020. 0 of 3 recent fall terms at or above 90% of scheduled capacity. 
      
    Code
      cat(no_row$sentence, "\n")
    Output
      TEST 998 is in the Fall 2020 projection scope, but the saved projection holds no row for it. 

# the view adds a needs-a-look filter without changing a number

    Code
      cat(moved_note, "\n\n")
    Output
      Draft seats +50% on Spring 2020: the range assumes steady seats 
      
    Code
      cat(drafted_view$meta$range_coverage$sentence, "\n")
    Output
      The range assumes seats like last year's. No past forecast has an earlier one to build a range from, so how often it held cannot be shown yet. 

