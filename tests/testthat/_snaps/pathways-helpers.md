# the course grid's cells read as text, one arrival at a time

    Code
      cat(format_degree_path_course_grid(first, "MC test population"), sep = "\n")
    Output
      MC test population: 4 first-time students of 6 in the population, through Spring 2021. Term 1 is the term they started.
      A cell is the share of the campus's students that term who took a course of that kind, then its 3 most-taken courses (subjects for Everything else), each with its own share; "+N more" counts the rest.
      No degree plan has been compiled for these majors.
      
      ABQ
        Their department's courses
          Term 1  100.0% of 3: SPAN 101 100.0%, +1 more course
          Term 2  100.0% of 4: SPAN 201 100.0%
          Term 3  Fewer than 2 students this term
        Named in their degree plan
          Term 1  None took one
          Term 2  None took one
          Term 3  Fewer than 2 students this term
      
      GA
        Their department's courses
          Term 1  Fewer than 2 students this term
        Named in their degree plan
          Term 1  Fewer than 2 students this term
    Code
      cat(format_degree_path_course_grid(degree_path_course_grid(path_entry_slice(p,
        "transfer")), "MC test population"), sep = "\n")
    Output
      MC test population: 1 transfer student of 6 in the population, through Spring 2021. Term 1 is the term they started.
      A cell is the share of the campus's students that term who took a course of that kind, then its 3 most-taken courses (subjects for Everything else), each with its own share; "+N more" counts the rest.
      No degree plan has been compiled for these majors.
      
      ABQ
        Their department's courses
          Term 1  Fewer than 2 students this term
        Named in their degree plan
          Term 1  Fewer than 2 students this term
    Code
      cat(format_degree_path_course_grid(spread, "MC test population", plans = "Spanish B.A."),
      sep = "\n")
    Output
      MC test population: 6 observed students of 6 in the population, through Spring 2021. Term 1 is each student's first observed enrolled term.
      A cell is the share of the campus's students that term who took a course of that kind, then its 3 most-taken courses (subjects for Everything else), each with its own share; "+N more" counts the rest.
      Degree plans read: Spanish B.A.
      
      ABQ
        Their department's courses
          Term 1  Fewer than 5 students took one
          Term 2  100.0% of 5: 2 courses, each taken by fewer than 5 students
          Term 3  Fewer than 5 students took one
      
      GA
        Their department's courses
          Term 1  Fewer than 5 students took one
    Code
      cat(course_paths_empty_note(p$meta, "transfer"), sep = "\n")
    Output
      This population has no transfer students.
    Code
      cat(course_paths_empty_note(modifyList(p$meta, list(n_observed_by_entry = c(
        first_time = 0L, transfer = 0L))), "transfer"), sep = "\n")
    Output
      No student here has a start on record as a first-time or transfer student, so no path can begin. The one student with courses was already here when the records begin, readmitted, or started at another level.

