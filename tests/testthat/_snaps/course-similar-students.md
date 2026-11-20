# the gen_ed comparison reads the Gen Ed list and says whom it compared

    Code
      cat(course_similar_students_headline(payload), sep = "\n")
    Output
      100.0% of the 1 students who took HIST 499 came back the next semester, against 0.0% of similar students who did not take it. Too few similar students to tell this difference from chance.
      In their other courses that semester they did not pass 100.0% of attempts (a D, an F or a withdrawal), against 25.0% for similar students. About the same as similar students: the difference is within what chance alone produces.
      The similar students are those who took a Gen Ed course that semester and not HIST 499: 3 of the 4 student-terms in this population (75%).
      Taking almost any course goes with coming back, so read HIST 499 against the other courses these students take, not against zero: its gap of +100.0 points is larger than 100% of the 1 other courses' gaps, where the typical course's is -100.0.

# the payload carries the focal row, the benchmark and the instructors; the text preview reads it

    Code
      cat(format_course_similar_students(payload), sep = "\n")
    Output
      HIST 101 against similar students who did not take it: Freshman
      Population: 11 student-terms; cells of term, home campus, high-school GPA band and full- or part-time status with at least 1 non-takers; rows with at least 1 covered takers.
      
      60.0% of the 5 students who took HIST 101 came back the next semester, against 10.0% of similar students who did not take it. Better than similar students, by more than chance alone produces.
      In their other courses that semester they did not pass 20.0% of attempts (a D, an F or a withdrawal), against 0.0% for similar students. Too few similar students to tell this difference from chance.
      The 2 who came back earned a 2.50 GPA the next semester, against 4.00 for similar students. Too few similar students to tell this difference from chance.
      Taking almost any course goes with coming back, so read HIST 101 against the other courses these students take, not against zero: its gap of +50.0 points is larger than 50% of the 2 other courses' gaps, where the typical course's is +0.0.
      Across its 2 instructors with 1 or more students, the return gap varies by 22.1 points (standard deviation), against about 27.1 from chance alone; 0 instructors stand apart from the rest by more than chance.
      
      Every course (3), by return gap:
        HIST 499                     n     1  return 100.0 vs 0.0 (100.0)  other DFW 100.0 vs 20.0 (80.0)  next GPA — vs —
        HIST 101 *                   n     5  return 60.0 vs 10.0 (50.0)  other DFW 20.0 vs 0.0 (20.0)  next GPA 2.50 vs 4.00
        HIST 300                     n     3  return 0.0 vs 100.0 (-100.0)  other DFW 50.0 vs 50.0 (0.0)  next GPA — vs —
      
      HIST 101 term by term:
        Spring 2020                  n     2  return 100.0 vs 25.0 (75.0)  other DFW 50.0 vs 0.0 (50.0)  next GPA 2.50 vs 4.00
        Fall 2020                    n     3  return 33.3 vs 0.0 (33.3)  other DFW 0.0 vs 0.0 (0.0)  next GPA — vs —
      
      HIST 101 by instructor, against the course's non-takers:
        RP_I3                        n     1  return 100.0 vs 25.0 (75.0)  other DFW 100.0 vs 0.0 (100.0)  next GPA 2.00 vs 4.00
        RP_I1                        n     4  return 50.0 vs 6.2 (43.8)  other DFW 0.0 vs 0.0 (0.0)  next GPA 3.00 vs 4.00

---

    Code
      cat(course_similar_students_headline(thin), sep = "\n")
    Output
      HIST 101 has 5 students in this population who can be compared with similar students; this comparison needs 50.

---

    Code
      cat(tail(course_similar_students_headline(trended), 2), sep = "\n")
    Output
      Fall to fall, the return gap went from +0.0 points in Fall 2019 to +6.0 in Fall 2022 over 4 terms: rising 2.0 a year, more than chance alone (±0.4).
      The gap in other courses not passed went from +0.0 points in Fall 2019 to +6.0 in Fall 2022 over 4 terms: rising 2.0 a year, more than chance alone (±0.4).

# the alike verdict follows the gap in standard deviations

    Code
      cat(course_similar_students_alike(build(ss_app_act))$sentence,
      course_similar_students_alike(build(ss_app_act_alike))$sentence,
      course_similar_students_alike(few)$sentence, sep = "\n")
    Output
      A check on the matching: of the 2 students who took HIST 101, the 2 with an ACT score on file averaged 19.0, against 24.0 for the similar students: 5.0 points lower. The matching does not use ACT and the course cannot have changed it, so the two groups were not alike before the course, and part of every gap here is the students, not the course.
      A check on the matching: of the 2 students who took HIST 101, the 2 with an ACT score on file averaged 24.0, against 24.0 for the similar students. The matching does not use ACT and the course cannot have changed it, so on a measure outside the matching the two groups look alike.
      Only 1 of the students who took HIST 101 has an ACT score on file, too few to check whether they and the similar students were alike before the course.

