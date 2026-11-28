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
      No student here has a start on record as a first-time or transfer student at this level, so no path can begin. The one student with courses was already here when the records begin, readmitted, or started at another level.
    Code
      payload <- list(paths = p, plans = "Spanish B.A.", department_subjects = "SPAN",
        description = "MC test population", level = "Undergraduate")
      str(course_paths_scope_facts(payload))
    Output
      List of 6
       $ Population                      : chr "MC test population"
       $ Started first-time              : chr "4"
       $ Transferred in                  : chr "1"
       $ No undergraduate start on record: chr "1"
       $ Through                         : chr "Spring 2021"
       $ Degree plans                    : chr "Spanish B.A."
    Code
      cat(course_paths_method_notes(payload, first), sep = "\n")
    Output
      Their department's courses are those in SPAN.
      The degree plans read are Spanish B.A. A plan compiled from the catalog is a draft until a reviewer signs it off.
      1 of the population's students with courses has no undergraduate start on record: they were here before the records begin, were readmitted, or started at another level, as a non-degree student for one. They are left out.
      A term needs 2 students on a campus to be shown, and a cell, a course or a subject 3 students; 4 cells are withheld.
      Through Spring 2021, the last term whose enrollment is settled.

