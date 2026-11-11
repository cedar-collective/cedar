# RW01: a focal gap is placed among the benchmark's gaps

    Code
      cat(format_course_cohort_context(p), sep = "\n")
    Output
      HIST 1110 against the Arts lower-division courses: Sophomore, each home campus its own row
      Population: 9 student-terms; enrollment settled through Spring 2021, grades through Spring 2021; a group needs 1 student, and a benchmark course 1 in both its passed and its never-took groups; 5 candidate courses.
      Return is enrollment the next regular term; the next-term DFW share is DFW over that term's classified attempts. Both gaps are passed minus never took, in points, and describe who takes the course before they describe the course.
      
      Fall 2020, ABQ: 6 students; 16.7% returned; next-term DFW share has no classified attempt.
        HIST 1110: passed 2 (33% of the population), returned 50.0%; never took it 1, returned 0.0%: +50.0 points. DFW'd it 2, returned 0.0%.
        In no group: 0 early drops, 1 registered with no posted grade.
        Benchmark: 1 Arts course. Passing one: median return 50.0% (quartiles 50.0% to 50.0%); median gap +50.0 points (quartiles +50.0 points to +50.0 points); HIST 1110's gap is above 0% of them.
      
      Spring 2021, ABQ: 3 students; return not yet observable; next-term DFW share not yet observable.
        HIST 1110: passed 0 (0% of the population), returned —; never took it 3, returned —: —. DFW'd it 0, returned —.
        Benchmark: no Arts course clears 1 in both groups.

# the MC02 words

    Code
      cat(format_course_cohort_context(mc02_context()), sep = "\n")
    Output
      SPAN 101 against the ARTS lower-division courses: Freshman, each home campus its own row
      Population: 12 student-terms; enrollment settled through Spring 2021, grades through Spring 2021; a group needs 1 student, and a benchmark course 1 in both its passed and its never-took groups; 4 candidate courses.
      Return is enrollment the next regular term; the next-term DFW share is DFW over that term's classified attempts. Both gaps are passed minus never took, in points, and describe who takes the course before they describe the course.
      
      Spring 2020, ABQ: 4 students; 100.0% returned; next-term DFW share 25.0% over 4 attempts.
        SPAN 101: passed 4 (100% of the population), returned 100.0%; never took it 0, returned —: —. DFW'd it 0, returned —.
        Next-term DFW share: passed 25.0%, never took it —: —; DFW'd it —.
        Benchmark: 1 ARTS course. Passing one: median return 100.0% (quartiles 100.0% to 100.0%); median gap +0.0 points (quartiles +0.0 points to +0.0 points).
        Next-term DFW share after passing one: median 50.0%; median gap +50.0 points (quartiles +50.0 points to +50.0 points).
      
      Spring 2020, GA: 2 students; 50.0% returned; next-term DFW share 0.0% over 1 attempt.
        SPAN 101: passed 2 (100% of the population), returned 50.0%; never took it 0, returned —: —. DFW'd it 0, returned —.
        Next-term DFW share: passed 0.0%, never took it —: —; DFW'd it —.
        Benchmark: no ARTS course clears 1 in both groups.
      
      Fall 2020, ABQ: 5 students; 20.0% returned; next-term DFW share 0.0% over 1 attempt.
        SPAN 101: passed 0 (0% of the population), returned —; never took it 5, returned 20.0%: —. DFW'd it 0, returned —.
        Next-term DFW share: passed —, never took it 0.0%: —; DFW'd it —.
        Benchmark: 2 ARTS courses. Passing one: median return 0.0% (quartiles 0.0% to 0.0%); median gap -12.5 points (quartiles -18.8 points to -6.2 points).
      
      Spring 2021, ABQ: 1 student; return not yet observable; next-term DFW share not yet observable.
        SPAN 101: passed 0 (0% of the population), returned —; never took it 1, returned —: —. DFW'd it 0, returned —.
        Benchmark: no ARTS course clears 1 in both groups.

# the headline reads the latest term, one paragraph per home campus

    Code
      cat(course_cohort_context_headline(p), sep = "\n")
    Output
      In Fall 2020, 2 of 6 ABQ students (Sophomore) passed HIST 1110 and 50.0% of them returned the next regular term; 1 never took it and 0.0% returned, a gap of +50.0 points. Passing one of the 1 other Arts lower-division courses went with a median gap of +50.0 points, and HIST 1110's gap is above 0% of them.

---

    Code
      cat(course_cohort_context_headline(mc02_context()), sep = "\n")
    Output
      In Spring 2021, of 1 ABQ students (Freshman), SPAN 101 has no passed and never-took groups of 1 with an observable return, so there is no gap to read.

