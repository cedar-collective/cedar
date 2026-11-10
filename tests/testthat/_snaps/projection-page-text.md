# the three axes are explained separately and may disagree

    Code
      cat(explanation)
    Output
      Own history: this course's Spring enrollment has moved only 4.0% across 5 comparable terms, so its history alone supports a forecast. Evidence: only 2 past Spring forecasts, so its reliability rests on very little. Reliability: past forecasts, each made with only the evidence available then, landed within 4.5% on average.

---

    Code
      cat(volatile)
    Output
      Own history: Spring enrollment swings 55.0% across 5 comparable terms, typically 48.0% term to term. No method forecasts a course like this reliably; the swing itself is the thing worth investigating. Evidence: 4 past Spring forecasts stand behind its reliability. Reliability: past forecasts, each made with only the evidence available then, were 42.0% off on average. Treat this projection as a rough scale, not a number to schedule to.

# the axis summary stays compact and names the main caveat

    Code
      cat(brief, "\n")
    Output
      Stable history · Deep evidence · High reliability · capacity-limited 
    Code
      cat(projection_axis_brief("Stable", "Deep", "High", regime_alarm = TRUE), "\n")
    Output
      Stable history · Deep evidence · High reliability · sharp change 

# the forecast's record is stated beside last year's number alone

    Code
      cat("sentence:", record$sentence, "\n\n")
    Output
      sentence: When the seats stayed within 10% of the year before, past forecasts were 7.5% off on average (2 of 4 past Spring forecasts); when the seats moved more than that, 15.0% off (1). Over all 4, the published forecast was 12.5% off, and last year's number alone 16.0%. They ran 10.0% low on average: a course that filled registers only as many students as it had seats, so when seats were added the next year, more registered than last year's count said. 
      
    Code
      cat("headline:", record$headline, "\n\n")
    Output
      headline: Past Spring forecasts were within 7.5% where the seats held (2 of 4) and 15.0% off where they moved 10% or more (1): most of the error follows the schedule, not the forecast. 
      
    Code
      cat("ran high:", high$sentence, "\n\n")
    Output
      ran high: When the seats stayed within 10% of the year before, past forecasts were 7.5% off on average (2 of 4 past Spring forecasts); when the seats moved more than that, 15.0% off (1). Over all 4, the published forecast was 12.5% off, and last year's number alone 16.0%. They ran 10.0% high on average. 
      
    Code
      cat("even:", even$sentence, "\n\n")
    Output
      even: When the seats stayed within 10% of the year before, past forecasts were 7.5% off on average (2 of 4 past Spring forecasts); when the seats moved more than that, 15.0% off (1). Over all 4, the published forecast was 12.5% off, and last year's number alone 16.0%. 
      
    Code
      cat("none saved:", none$sentence, "\n")
    Output
      none saved: No past forecasts are saved for this target, so the forecast's record cannot be shown. 

# the ledger of ideas tried is complete and in the page's words

    Code
      cat(paste0(ledger$status, " | ", ledger$idea), sep = "\n")
    Output
      In the model | Repeat last year's registrations, same season
      In the model | Add the students still waiting when last year was near full
      In the model for Spring | Follow enrollment changes in the term just finished (retakes, the course taken just before, feeder courses)
      In the plan | A 5% planning allowance for a course near full every recent year
      Dropped | Average two or more past years, or a damped trend
      Dropped | Blend the two forecasts, or pick one for the whole course set
      Dropped | Forecast from student populations (majors, classifications, feeder transitions)
      Waiting on data | Correct a forecast's bias after the fact
      Dropped | A DFW or repeat multiplier for every course
      By rule, not done | Use the schedule's seats as the forecast
      Next | Read next year's schedule where a draft exists

# students left waiting in the term just finished are flagged from half a section and stated for every course

    Code
      cat(notes, sep = "\n")
    Output
      12 students were left waiting in Fall 2026 on no class list for the course. The plan does not add them: how many register in Spring 2027 cannot be measured until its class lists arrive.
      11 students were left waiting in Fall 2026 on no class list for the course. The plan does not add them: how many register in Spring 2027 cannot be measured until its class lists arrive.
      No student was left waiting in Fall 2026.
      Fall 2026 kept no waitlist rows for these courses, so who was left waiting is unknown.
    Code
      cat("\n", summary$sentence, "\n", sep = "")
    Output
      
      In Fall 2026, 23 students were left waiting in 2 of the 4 courses shown, on no class list for the course. The plan does not add them: how many register in Spring 2027 cannot be measured until its class lists arrive.

---

    Code
      cat(unseen)
    Output
      Spring 2027 is not observed yet, so who it leaves waiting cannot be shown.

# the administrator summary says the decision in one sentence and flags why to look

    Code
      cat("full:", sentence, "\n\n")
    Output
      full: Plan at least 99 sections for 2,397 registrations: 2,179 projected plus a pressure bump of 218 (about 2,080 of the projected 2,179 in seats on the first day). The forecast matches last Spring's 2,179. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand; the pressure bump allows for that. Past forecasts for this course missed by 10.0% on average. 
      
    Code
      cat("with feeders:", fed, "\n\n")
    Output
      with feeders: Plan at least 99 sections for 2,337 registrations: 2,179 projected, -60 for the change in its feeder courses, plus a pressure bump of 218 (about 2,080 of the projected 2,179 in seats on the first day). The forecast matches last Spring's 2,179. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand; the pressure bump allows for that. Past forecasts for this course missed by 10.0% on average. 
      
    Code
      cat("bump denied:", denied_sentence, "\n\n")
    Output
      bump denied: Plan at least 99 sections for 2,179 registrations (about 2,080 in seats on the first day). The forecast matches last Spring's 2,179. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand. No pressure bump: Spring 2026 filled 85.0% of its seats. Past forecasts for this course missed by 10.0% on average. 
      
    Code
      cat("below last year:", lower, "\n\n")
    Output
      below last year: Plan at least 99 sections for 2,273 registrations: 2,164 projected plus a pressure bump of 109 (about 2,058 of the projected 2,164 in seats on the first day). The forecast is 0.7% below last Spring's 2,179: the changes in Fall 2026 point lower. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand; the pressure bump allows for that. Past forecasts for this course missed by 10.0% on average. 
      
    Code
      cat("low reliability:", low, "\n\n")
    Output
      low reliability: Plan at least 99 sections for 2,397 registrations: 2,179 projected plus a pressure bump of 218 (about 2,080 of the projected 2,179 in seats on the first day). The forecast matches last Spring's 2,179. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand; the pressure bump allows for that. Past forecasts for this course missed by 26.4% on average; treat it as a rough scale. 
      
    Code
      cat("unrated:", unrated, "\n\n")
    Output
      unrated: Plan at least 99 sections for 2,397 registrations: 2,179 projected plus a pressure bump of 218 (about 2,080 of the projected 2,179 in seats on the first day). The forecast matches last Spring's 2,179. Last Spring filled 98.8% of its seats on the first day with 15 students waiting, so its count stopped at its seats and understates demand; the pressure bump allows for that. Too few past forecasts to say how reliable this is. 
      
    Code
      cat("sharp change:", moved_sentence, "\n\n")
    Output
      sharp change: Plan 99 sections for 2,400 registrations (about 2,080 in seats on the first day). The forecast is 10% above last Spring's 2,179. Enrollment in Fall 2026 moved +91% from the year before; review before scheduling to this number. Past forecasts for this course missed by 10.0% on average; treat it as a rough scale. 
      
    Code
      cat("sparse:", projection_summary_sentence(sparse), "\n")
    Output
      sparse: Not enough comparable history to project this course. 

# the page says which of the worst misses the schedule set and names the forecast's own

    Code
      cat(projection_miss_sentence(rows, config), "\n\n")
    Output
      3 of the 5 courses shown had past forecasts more than 20% off. For 2, most of the miss came when the course was near full and its seats moved the way of the miss or held, so the schedule set the number. For 1 (FYEX 1110), the course had seats to spare or its seats moved against the miss, so the miss was the forecast's own. 
      
    Code
      cat(projection_miss_sentence(rows[1:2, ], config), "\n\n")
    Output
      2 of the 2 courses shown had past forecasts more than 20% off. For all 2, most of the miss came when the course was near full and its seats moved the way of the miss or held, so the schedule set the number. None was the forecast's own. 
      
    Code
      cat(projection_miss_sentence(dplyr::mutate(rows[1, ], miss_cause = NA), config),
      "\n\n")
    Output
      1 of the 1 course shown had past forecasts more than 20% off. None was the forecast's own. For 1, the seats or first day of those terms are not known. 
      
    Code
      cat(projection_miss_sentence(many, config), "\n\n")
    Output
      6 of the 6 courses shown had past forecasts more than 20% off. For all 6, the course had seats to spare or its seats moved against the miss, so the miss was the forecast's own. 
      
    Code
      cat(projection_miss_sentence(rows[4:5, ], config), "\n\n")
    Output
      None of the 2 courses shown has had past forecasts more than 20% off. 
      
    Code
      cat(projection_miss_sentence(rows[4, ], config), "\n\n")
    Output
      The course shown has not had past forecasts more than 20% off. 
      
    Code
      cat(projection_miss_sentence(rows, list(accuracy_fair_max_wape = 0.25)), "\n")
    Output
      3 of the 5 courses shown had past forecasts more than 25% off. For 2, most of the miss came when the course was near full and its seats moved the way of the miss or held, so the schedule set the number. For 1 (FYEX 1110), the course had seats to spare or its seats moved against the miss, so the miss was the forecast's own. 

# a plan's steps add up from last year's class list to its sections

    Code
      cat(paste0(steps$label, ": ", dplyr::coalesce(steps$detail, "")), sep = "\n")
    Output
      Registered in Spring 2026: Everyone on last Spring's class lists, including students who later dropped
      Students still waiting: Waitlisted last Spring without a seat in any section, because the course was near full
      Enrollment change in Fall 2026: students retaking this course +3; SEQ 1, taken just before −7; other feeder courses +1 (each rounded)
      Forecast registrations: Past forecasts for this course missed by 6.8% on average (4 terms, Spring 2023 to Spring 2026)
      Pressure bump: Near full on the first day in every recent Spring
      Planned registrations: What the sections are sized for
      Sections: 214 registrations at 25.0 per section (the draft schedule's average), rounded up; the draft schedule has 8 sections

# the feeder summary says how many plans it moved, and why when none

    Code
      cat(summary$sentence, "\n\n")
    Output
      Feeder courses in Fall 2026 raise 1 course's plan by 12 registrations and lower 2 courses' plans by 38. A course's listed predecessor, taken the term before, always counts; its other feeder courses count when they moved 5% or more. 1 course's published projection already includes those changes. 
      
    Code
      cat(still$sentence, "\n\n")
    Output
      No plan shown has a feeder adjustment: where the forecast is last year's number, feeder courses moved less than 5% in Fall 2026 and no listed predecessor changed it. 
      
    Code
      cat(unseen$sentence, "\n\n")
    Output
      No plan has a feeder adjustment: Fall 2026 is not observed yet, so its feeder courses cannot be read. They count once it settles. 
      
    Code
      cat(fall$sentence, "\n")
    Output
      No plan has a feeder adjustment: only Spring plans follow their feeder courses. 

