# terms of both kinds give no rows, and a term type is named as one

    Code
      cat(low_enrollment_mixed_terms_note(mixed))
    Output
      These terms need two different lists. Nobody has registered for Spring 2021 yet: that gets a schedule check, each scheduled course against its own history. Registrations are in for Fall 2020 and fall terms: that gets a list of sections. Choose one kind and run again.

# a scope with nothing small lists nothing, and says so as a result

    Code
      cat(low_enrollment_empty_note(none))
    Output
      Nothing to review. No active section in this scope is at its threshold, under it, or within a quarter above it.

---

    Code
      cat(low_enrollment_empty_note(list(mode = "concerns")))
    Output
      Nothing to review. No course scheduled in this scope has averaged under its threshold, or within five students of it, and none is without same-season history.

# the cards say what each band is, in each view's own words

    Code
      as.data.frame(low_enrollment_summary_cards(summarize_low_enrollment_bands(page),
      "alerts"))
    Output
                  key value          label                   note     tone
      1      critical     0       Critical under 50% of threshold critical
      2       warning     0        Warning    50–75% of threshold  warning
      3         watch     2          Watch   75–100% of threshold     info
      4        buffer     2        Monitor         over threshold  success
      5         total     4 Total Sections           in this list     <NA>
      6      students    45 Total Students     each section's own     <NA>
      7 mean_enrolled 11.25 Avg Enrollment own students a section     <NA>

---

    Code
      as.data.frame(low_enrollment_summary_cards(summarize_low_enrollment_bands(
        schedule), "concerns"))
    Output
               key value                  label                    note     tone
      1   critical     0       Historically Low  under 50% of threshold critical
      2    warning     0             Borderline     50–75% of threshold  warning
      3      watch     0                  Watch    75–100% of threshold     info
      4     buffer     0         Near Threshold    at or over threshold  success
      5 no_history     5 No Same-Season History nothing to compare with  neutral
      6      total     5          Total Courses            in this list     <NA>

# a list too long for history lines says so, and its sections show a dash

    Code
      notes[[length(notes)]]
    Output
      $lead
      [1] "This list is too long for each section's history. "
      
      $text
      [1] "A run that lists more than 2 sections leaves the Prior History column empty. Choose a college or a department to see it."
      

# counts still moving, and a schedule check, are said above the list; settled counts need no note

    Code
      low_enrollment_view_notes(moving)
    Output
      [[1]]
      [[1]]$lead
      [1] "Registration had not settled when these counts were pulled. "
      
      [[1]]$text
      [1] "Counts for Fall 2020 (pulled Aug 17, 2020) come from a pull made before registration settled, so sections can still gain or lose students. Compare each section with its history before acting."
      
      

---

    Code
      low_enrollment_view_notes(schedule)
    Output
      [[1]]
      [[1]]$lead
      [1] "Schedule check: Spring 2021 has no registrations yet. "
      
      [[1]]$text
      [1] "Each scheduled course is compared with its own enrollment in its last 4 spring terms on the same campus. Courses in the green band have met the threshold but sit near it. A course with no spring history there lists where else it has run."
      
      

# the scope bar states the view, the run's filters, the pulls, the thresholds and how many are listed

    Code
      str(describe_low_enrollment_scope(page))
    Output
      List of 5
       $ View      : chr "Sections, by registrations"
       $ Scope     : chr "All campuses · All departments"
       $ Terms     : chr "Spring 2020 (pulled Jan 13, 2020)"
       $ Thresholds: chr "Lower 12, Upper 15, Split 10, Graduate 5 · smallest section listed 0"
       $ Listed    : chr "5 sections"

---

    Code
      str(describe_low_enrollment_scope(schedule))
    Output
      List of 5
       $ View      : chr "Schedule check, by each course's history"
       $ Scope     : chr "All campuses · All departments"
       $ Terms     : chr "Spring 2021 (pulled Jan 19, 2021)"
       $ Thresholds: chr "Lower 12, Upper 12, Split 10, Graduate 5"
       $ Listed    : chr "5 courses"

---

    Code
      str(describe_low_enrollment_scope(mixed))
    Output
      List of 3
       $ View : chr "None: terms of two kinds"
       $ Scope: chr "All campuses · All departments"
       $ Terms: chr "Fall 2020 (pulled Aug 17, 2020); Spring 2021 (pulled Jan 19, 2021)"

---

    Code
      str(scope_of(list(course_campus = c("ABQ", "EA"), dept_code = "HIST", level = c(
        "upper", "grad"))))
    Output
      List of 5
       $ View      : chr "Sections, by registrations"
       $ Scope     : chr "Campus ABQ, EA · Department HIST · Level Upper, Graduate"
       $ Terms     : chr "Spring 2020 (pulled Jan 13, 2020)"
       $ Thresholds: chr "Lower 12, Upper 12, Split 10, Graduate 5 · smallest section listed 1"
       $ Listed    : chr "4 sections"

---

    Code
      str(scope_of(list(course_college = "ARTS", pt = "1", im = "ONL")))
    Output
      List of 5
       $ View      : chr "Sections, by registrations"
       $ Scope     : chr "All campuses · College ARTS · Part of term 1 · Method ONL"
       $ Terms     : chr "Spring 2020 (pulled Jan 13, 2020)"
       $ Thresholds: chr "Lower 12, Upper 12, Split 10, Graduate 5 · smallest section listed 1"
       $ Listed    : chr "1 section"

# each view's section says what it lists and how it is counted

    Code
      str(low_enrollment_section_words("alerts"))
    Output
      List of 2
       $ title   : chr "Sections at or near their threshold"
       $ sentence: chr "Each active section whose class is at, under or just over the threshold for its level, smallest first."

---

    Code
      cat(low_enrollment_method_notes(page), sep = "\n\n")
    Output
      One row per active section, after the excluded-course list. Thresholds for this run: lower 12, upper 12, split 10, graduate 5. Sections with no students are left out.
      
      XL Total is the number judged: the section's own students, or for a crosslisted section the combined class across its partners. A section is listed when that is at or under its threshold, or within a quarter above it.
      
      The bands are shares of the row's own threshold: red under 50%, yellow 50% to 75%, blue 75% up to and at it, green over it.
      
      Enrolled is the section's own students, and the cards' Total Students and Avg Enrollment add those up. Sects is the number of active home sections of the course that term, and Course Total their combined classes.
      
      Prior History is the course's enrollment in its last 4 earlier terms. A run that lists more than 500 sections leaves it out.

---

    Code
      str(low_enrollment_section_words("concerns"))
    Output
      List of 2
       $ title   : chr "Scheduled courses that have run small"
       $ sentence: chr "Each scheduled course whose earlier terms averaged at or near the threshold for its level, smallest first."

---

    Code
      cat(low_enrollment_method_notes(schedule), sep = "\n\n")
    Output
      One row per scheduled course and campus, from active sections on the schedule after the excluded-course list. Thresholds for this run: lower 12, upper 12, split 10, graduate 5.
      
      Hist Avg is the course's average combined enrollment over its last 4 terms of the same season on the same campus, and is the number judged. A course is listed when that average is under its threshold or within five students of it, or when it has no such history.
      
      The bands are shares of the row's own threshold: red under 50%, yellow 50% to 75%, blue 75% up to it, green at or over it. A course with no same-season history has no average: it is gray, counted on its own card, and its Prior History lists its latest offerings in other seasons, on other campuses or as other topics, which never set the average.
      
      Sects is the number of scheduled home sections. Trend is the direction of a straight line through the earlier terms. # Terms is how many of them there were.

---

    Code
      cat(LOW_ENROLLMENT_SPLIT_NOTE)
    Output
      Crosslisted courses that span the undergraduate and graduate levels: at least one section numbered 499 or lower and one numbered 500 or higher. Split Partners names every course in the group, and XL Total is the group's combined class.

