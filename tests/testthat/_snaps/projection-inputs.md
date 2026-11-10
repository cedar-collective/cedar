# Gen Ed and FYEX monitoring group has an explicit campus scope

    Code
      cat(guide$summary, "\n\n")
    Output
      2 forecasts: Last year's registrations, and Last year's registrations, adjusted 
      
    Code
      cat(guide$selection_process, "\n")
    Output
      Last year's registrations is the default for every course. Another forecast replaces it only after beating it by a margin on earlier past forecasts the two share, and the rule is replayed at every past term with only the evidence available then, so the reliability shown is what that rule would actually have delivered. 

# movement diagnostics attach upstream, capacity, and canonical DFW context

    Code
      cat("schedule:", detail$schedule_summary, "\n\n")
    Output
      schedule: There are too few comparable movements for a stable correlation. First-day enrollment reached scheduled capacity (98% of seats or more) in 1 of 1 terms where first day and capacity are both known. 
      
    Code
      cat("upstream:", detail$upstream_summary, "\n\n")
    Output
      upstream: The largest observed move was Fall 2023 (+30.0%). In the preceding Spring 2023, enrolled-student population changed +5.0%, first-semester freshman population changed +14.3%, and the projection market changed +5.0%. 
      
    Code
      cat("dfw:", detail$dfw_summary, "\n\n")
    Output
      dfw: For that move, 16 students had a DFW in the course during the preceding term (20.0%). 10 of them then enrolled in the course in Fall 2023—7.7% of that term's course enrollment. 
      
    Code
      cat("caveat:", detail$caveat, "\n")
    Output
      caveat: These are upstream and post-hoc diagnostics, not causal attribution. Schedules may respond to anticipated demand, and DFW repeaters are observed after the following term begins. 

# pressure screen retains forced courses and records why

    Code
      cat(screen$inclusion_reason)
    Output
      Always monitored; Historical demand exceeds scheduled capacity by 20 registrations; 3 of 3 recent fall terms with first-day enrollment at or above 90% of scheduled capacity; Trend demand exceeds scheduled capacity by 30 registrations

# pressure exclusions report the comparable-term evidence

    Code
      cat(screen$inclusion_reason)
    Output
      Not selected: 1 of 3 recent fall terms with first-day enrollment at or above 90% of scheduled capacity; historical and trend demand remain within 10 seats of scheduled capacity

# a trend exactly at the seat gap counts on every platform (I34)

    Code
      cat(screen$inclusion_reason)
    Output
      Trend demand exceeds scheduled capacity by 10 registrations

# the pressure screen reads first-day fill, so neither seat churn nor census drops decide pressure

    Code
      cat(screen$inclusion_reason)
    Output
      Not selected: 0 of 3 recent fall terms with first-day enrollment at or above 90% of scheduled capacity; no usable target-term capacity for shortfall or growth checks

# target class-list snapshot drives the active seat check

    Code
      cat("status:", result$capacity_limit_status, "\n\n")
    Output
      status: Seat ceiling likely limits observed enrollment 
      
    Code
      cat("note, registration open:", result$capacity_limit_note, "\n\n")
    Output
      note, registration open: Planned registrations exceed capacity by 100; 0 seats are currently unoccupied 
      
    Code
      cat("note, before registration:", early$capacity_limit_note, "\n")
    Output
      note, before registration: Planned registrations exceed capacity by 100 

# the expansion response reads what saturated courses did when given room

    Code
      cat(response$note, "\n\n")
    Output
      When near-full courses in this market were given at least 10% more seats (5 cases before Spring 2024), class-list demand grew by 90% of the added seats 
      
    Code
      cat(thin$note, "\n")
    Output
      Only 5 near-full courses given more seats before Spring 2024; needs 6 

