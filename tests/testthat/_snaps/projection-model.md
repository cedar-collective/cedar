# an unavailable target schedule produces a planning recommendation

    Code
      cat(result$recommendation)
    Output
      Plan at least 4 sections; last year was near full

# an always-full course gets a pressure bump on its plan, never on its forecast

    Code
      cat(full$pressure_bump_note, "\n\n")
    Output
      Pressure bump +10: near full on the first day in every recent Fall with a first-day count (Fall 2021, Fall 2022, Fall 2023), so its registrations stopped at its seats; the bump is 5% of last Fall's 200 registrations 
      
    Code
      cat(waiting$pressure_bump_note, "\n\n")
    Output
      Pressure bump +31: near full on the first day in every recent Fall with a first-day count (Fall 2021, Fall 2022, Fall 2023), so its registrations stopped at its seats; the bump is the 31 students left waiting, more than 5% of last Fall's 200 registrations 
      
    Code
      cat(floored$pressure_bump_note, "\n\n")
    Output
      Pressure bump +3: near full on the first day in every recent Fall with a first-day count (Fall 2021, Fall 2022, Fall 2023), so its registrations stopped at its seats; the bump is 5% of last Fall's 200 registrations (7 students were left waiting); the published projection already adds 7 of them 
      
    Code
      cat(roomy$pressure_bump_note, "\n")
    Output
      No pressure bump: Fall 2023 filled 85.0% of its seats on the first day, below the 90% near-full line 

# a past miss is the schedule's only when a full course's seats moved the way it missed

    Code
      cat(reading, sep = "\n\n")
    Output
      Past forecasts missed by more than 20%, mostly in terms when the course was near full and its seats moved the way of the miss or held: the schedule set those numbers, so the projection holds if the seats do.
      
      Past forecasts missed by more than 20% while the course had seats to spare, or its seats moved against the miss, so the misses were the forecast's: enrollment changed on its own. Where the seats moved with it, the department saw the change coming; ask what it expects before planning to this number.
      
      Past forecasts missed by more than 20%, in terms whose seats or first day are not known, so the cause cannot be told.
      
      Past forecasts landed close, so the projection can be planned to.
      
      Too few past forecasts to say how reliable this course's projection is.
      
      Past forecasts were 10% to 20% off, mostly when the course was near full and its seats moved the way of the miss or held.

# past error is summed by whose miss each term was

    Code
      cat(paste0(sources$source, ": ", sources$label), sep = "\n")
    Output
      schedule: Near full; seats moved 10% or more the way of the miss
      seats_full: Near full; seats held
      forecast_seats_moved: Seats moved 10% or more, but did not set the number
      forecast_seats_held: Seats held; course had room
      unknown: Seat or first-day data missing
    Code
      cat("\n", summary$sentence, "\n", sep = "")
    Output
      
      Across 7 past forecasts, 45% of the error came when the course was near full and its seats moved the way of the miss (40%) or held (5%): the schedule set those numbers. 35% was the forecast's own, with seats to spare or seats moving against the miss (3 past forecasts), and 20% came from terms whose seats or first day are not known.

# Fall deltas scale enrollment changes by the historical carry-through

    Code
      cat(far$delta_basis)
    Output
      Preceding term Fall 2024 is not observed yet, so no change from it is added

# a feeder earns its place by lift, not by size

    Code
      cat(none$delta_basis)
    Output
      retakes: (12 - 8) x 0.25 = +1.0; feeders: none met the evidence threshold

# a listed sequence carries its own change and leaves the pooled feeders

    Code
      cat(result$delta_basis)
    Output
      retakes: (12 - 8) x 0.25 = +1.0; taken just before, SEQ 1: (4 - 8) x 0.5 = -2.0; feeders (FEED 1 7.9x the market's 0.064): (20 - 10) x 0.5 = +5.0

# a prior term full on the first day adds its unserved waitlist to the spine

    Code
      cat("floor:", result$floor_basis, "\n\n")
    Output
      floor: Spring 2023 was near full (first-day fill 90.9%); last year's 24 + 3 still waiting = 27 
      
    Code
      cat("undated:", undated$floor_basis, "\n\n")
    Output
      undated: Spring 2023's class lists carry no registration status dates, so its first day cannot be counted and whether it was near full cannot be judged; re-pulling that term's class list restores it 
      
    Code
      cat("settled pending:", settled$floor_basis, "\n\n")
    Output
      settled pending: Spring 2023 was near full (first-day fill at least 90.9%, from the sessions that had begun when the class list was pulled); last year's 24 + 3 still waiting = 27 
      
    Code
      cat("open pending:", open$floor_basis, "\n\n")
    Output
      open pending: Some of Spring 2023's sessions had not begun when its class list was pulled, so its first day is not yet complete; the sessions that had begun fill 68.2% of its seats, short of the 90% that would count as full 
      
    Code
      cat("no waitlist rows:", none$floor_basis, "\n\n")
    Output
      no waitlist rows: Spring 2023 was near full (first-day fill 90.9%); no waitlist rows retained for that term, so nothing is added to last year's count 
      
    Code
      cat("no capacity:", unknown$floor_basis, "\n")
    Output
      no capacity: No usable seat count for Spring 2023 so whether it was near full cannot be judged 

# selection is rolling: a challenger wins only on earlier shared aftcasts, and accuracy is its realised record

    Code
      cat(selected$selection_reason)
    Output
      Last year's registrations, adjusted beat Last year's registrations on 4 earlier terms both were made for (2.0% vs 10.0% off on average)

# a challenger inside the margin leaves the default in place

    Code
      cat(selected$selection_reason)
    Output
      Last year's registrations is the default; no other forecast beat it by 2.0% or more of average error on 3 or more earlier terms both were made for

# capacity-bounded fit retains fit confidence with a demand caveat

    Code
      cat(selected$accuracy_reason, "\n\n")
    Output
      1.5% off on average across 4 past forecasts, varying 1.8% term to term 
      
    Code
      cat(explanation, "\n")
    Output
      Own history: Fall enrollment varies 8.0% across 5 comparable terms — enough movement to matter for planning, not enough to make the course unpredictable. Evidence: 4 past Fall forecasts stand behind its reliability. Reliability: past forecasts, each made with only the evidence available then, landed within 1.5% on average, varying 1.8% term to term. Capacity caveat: the course filled its seats on the first day in 3 of 4 past forecast terms whose first day is known, so its reliability measures the students it had room for, not everyone who wanted it. Method caveat: the two forecasts differ materially, so which one is used matters. 

# variable term errors are reported without downgrading accuracy

    Code
      cat(selected$accuracy_reason)
    Output
      4.0% off on average across 4 past forecasts, varying 4.8% term to term

# backtests separate raw from registration-cap-censored accuracy

    Code
      cat(result$capacity_miss_assessment)
    Output
      Capacity likely explains most of the apparent error

# rows with no applicable method remain explicit

    Code
      cat(selected$accuracy_reason)
    Output
      No applicable method

