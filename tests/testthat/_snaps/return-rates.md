# RT01: the sentence names the semester students come back least often after, and the semesters moving

    Code
      cat(retention_stage_sentence(st, "first_time", "fall"),
      retention_stage_sentence(st, "transfer", "fall"), retention_stage_sentence(
        steady, "first_time", "fall"), retention_stage_sentence(few, "first_time",
        "fall"), retention_stage_sentence(spring_low, "first_time", "fall"), sep = "\n")
    Output
      First-time students came back least often after their 1st semester: in 3 of the 4 fall terms read. Their share coming back is falling after their 5th semester and rising after their 1st semester, and not clearly moving after the other 2.
      Only transfer students' return after their 1st semester can be read. Their share coming back is not clearly rising or falling after any semester.
      First-time students came back least often after their 1st semester: in 3 of the 4 fall terms read. Their share coming back is not clearly rising or falling after any semester.
      First-time students came back least often after their 1st semester: in 3 of the 4 fall terms read. Too few fall terms are read to say whether their share is rising or falling after any semester.
      First-time students came back least often after their 8th semester (those who started in a spring): in every one of the 4 fall terms read. Their share coming back is falling after their 5th semester and rising after their 1st semester, and not clearly moving after the other 2.

# RT01: the dashboard as text carries each semester's line and who has none

    Code
      cat(lines[grepl("semester|no start", lines)], sep = "\n")
    Output
      First-time students, 1st semester: 82.0% in Fall 2023; rising.
      First-time students, 3rd semester: 85.0% in Fall 2023; steady.
      First-time students, 5th semester: 74.0% in Fall 2023; falling.
      First-time students, 8th semester (spring start): 83.3% in Fall 2023; steady.
      Transfer students, 1st semester: 75.0% in Fall 2023; steady.
      In no semester's line: 16 with no start on record, 24 after their 8th semester, 0 in a semester reaching back before the arrival records (Spring 2016).
      First-time students, semesters not read in the latest term, left out: 1.

# RS01: the page says who it counts: the level's students by how they started, other levels left out

    Code
      describe_retention_scope(who)
    Output
                                                Counted, Fall 2022 
                       "7 Undergraduate students, home campus ABQ" 
                                                  New in Fall 2022 
                               "2 first-time students, 1 transfer" 
                                          Started before Fall 2022 
                                "1 first-time student, 1 transfer" 
                                               Start not on record 
                                                      "2 students" 
                                                       Not counted 
      "students at another level: Graduate 2; no level recorded 1" 
    Code
      describe_retention_scope(everywhere)
    Output
                                                Counted, Fall 2022 
                     "8 Undergraduate students, every home campus" 
                                                  New in Fall 2022 
                              "2 first-time students, 2 transfers" 
                                          Started before Fall 2022 
                                "1 first-time student, 1 transfer" 
                                               Start not on record 
                                                      "2 students" 
                                                       Not counted 
      "students at another level: Graduate 2; no level recorded 1" 
    Code
      describe_retention_scope(every_level)
    Output
                                 Counted, Fall 2022 
      "10 students at every level, home campus ABQ" 
                                   New in Fall 2022 
                "2 first-time students, 1 transfer" 
                           Started before Fall 2022 
                 "1 first-time student, 1 transfer" 
                                Start not on record 
                                       "5 students" 
    Code
      describe_retention_scope(graduate)
    Output
                                                     Counted, Fall 2022 
                                 "2 Graduate students, home campus ABQ" 
                                                    Start not on record 
                                                           "2 students" 
                                                            Not counted 
      "students at another level: Undergraduate 7; no level recorded 1" 
    Code
      cat(retention_who_note(who))
    Output
      A transfer student is counted like any other, from their first term here. A student at another level is not counted: choose that level above to read them. Of the 7 counted in Fall 2022, 3 are new that term (2 first-time students and 1 transfer, counting any who started the summer before); 2 started before it (1 first-time student and 1 transfer); and the other 2 the record never calls new in the terms on record (readmitted after time away, moved from another campus or level, or here before the records begin). A student who arrived more than once is read by the latest.
    Code
      cat(retention_who_note(graduate))
    Output
      A transfer student is counted like any other, from their first term here. A student at another level is not counted: choose that level above to read them. None of the 2 counted in Fall 2022 has a start on record at this level: the record never calls them first-time students or new transfers here, so which of them are new that term cannot be told.
    Code
      cat(retention_who_note(NULL))
    Output
      A transfer student is counted like any other, from their first term here. A student at another level is not counted: choose that level above to read them.

# RR01: the dashboard as text

    Code
      cat(format_retention_dashboard(rr01$dashboard), sep = "\n")
    Output
      Return to the next regular term, fall terms, level UG; settled through Fall 2024, grades through Fall 2022.
      Left out: 8 awarded a degree that term or before the next regular term (0 in between, 0 applied for one not yet posted). Not read yet: 10 in Fall 2024, whose next term, Spring 2025, has not settled.
      Overall: 71.7% for Fall 2020, 81.7% for Fall 2023. Across the 4 terms the fitted line moves +3.3 points a year, where chance and the terms' own scatter give about 4.9: steady.
        Fall 2020: 43 of 60 returned, 71.7%.
        Fall 2021: 45 of 60 returned, 75.0%.
        Fall 2022: 47 of 60 returned, 78.3%.
        Fall 2023: 49 of 60 returned, 81.7%.
      A late withdrawal, Fall 2023: 6 students, 0.0% returned against 90.7% without; 54.5% of those who did not return.
      A DFW grade, Fall 2022: 7 students, 28.6% returned against 86.5% without; 41.7% of those who did not return.
      College AS: 85.0% in Fall 2023; steady.
      College EN: 75.0% in Fall 2023; steady.
      Entered Fall 2021 (62): 0.0% 2nd semester (spring); 0.0% 3rd semester (fall); 0.0% 4th semester (spring); 0.0% 5th semester (fall).
      Entered Fall 2022 (62): 0.0% 2nd semester (spring); 0.0% 3rd semester (fall); 0.0% 4th semester (spring); 0.0% 5th semester (fall).
      Entered Fall 2023 (62): 0.0% 2nd semester (spring); 0.0% 3rd semester (fall); — 4th semester (spring); — 5th semester (fall).
      Entered Fall 2024 (10): — 2nd semester (spring); — 3rd semester (fall); — 4th semester (spring); — 5th semester (fall).
      Course MATH 101 (ABQ): 21 with a DFW, 9.5% back against 91.7% after passing; 17.2 beyond the passers' rate.

# RR01: the first section's sentence gives the verdict over the terms, and says when too few can be read

    Code
      cat(retention_lead_sentence(t, "fall"), retention_trend_arithmetic(t),
      retention_lead_sentence(few, "fall"), sep = "\n")
    Output
      The share of fall students who came back the next regular term is not clearly rising or falling: 71.7% for Fall 2020, 81.7% for Fall 2023, a difference within the terms' usual swings.
      Across the 4 terms the fitted line moves +3.3 points a year, where chance and the terms' own scatter give about 4.9: steady.
      Too few fall terms can be read to say whether the share coming back is rising or falling: 2 of the 3 a trend needs.

