# the gen_ed comparison reads the Gen Ed list and says whom it compared

    Code
      cat(course_similar_students_headline(payload), sep = "\n")
    Output
      Of 1 students who took HIST 499, 100.0% returned the next regular term, against 0.0% expected from students of the same term, home campus, high-school GPA band and time status who took a Gen Ed course and not this one: a gap of +100.0 points, where chance alone moves it about 0.0.
      In their other courses that term they did not pass 100.0% of attempts against 25.0% expected (+75.0 points).
      The compared students come from the 3 of 4 student-terms in this population with a Gen Ed course that term (75%).
      Taking almost any course goes with returning: across the 1 other courses these students took, the median return gap is -100.0 points, and HIST 499's is larger than 100% of them.

# the payload carries the focal row, the benchmark and the instructors; the text preview reads it

    Code
      cat(format_course_similar_students(payload), sep = "\n")
    Output
      HIST 101 against similar students who did not take it: Freshman
      Population: 11 student-terms; cells of term, home campus, high-school GPA band and time status with at least 1 non-takers; rows with at least 1 covered takers.
      
      Of 5 students who took HIST 101, 60.0% returned the next regular term, against 10.0% expected from non-takers of the same term, home campus, high-school GPA band and time status: a gap of +50.0 points, where chance alone moves it about 24.5.
      In their other courses that term they did not pass 20.0% of attempts against 0.0% expected (+20.0 points); those who returned earned a next-term GPA of 2.50 against 4.00 expected.
      Taking almost any course goes with returning: across the 2 other courses these students took, the median return gap is +0.0 points, and HIST 101's is larger than 50% of them.
      Its 2 instructors with 1 or more takers differ by 22.1 points in return gap (standard deviation) where chance alone gives about 27.1; 0 sit more than two standard errors from the instructors' average.
      
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
      HIST 101 has 5 takers in this population with comparable non-takers, under the 50 this comparison needs.

---

    Code
      cat(tail(course_similar_students_headline(trended), 2), sep = "\n")
    Output
      Fall to fall, the return gap went from +0.0 points in Fall 2019 to +6.0 in Fall 2022 over 4 terms: rising (+2.0 a year; a trend needs more than ±0.4).
      The other-course DFW gap went from +0.0 points in Fall 2019 to +6.0 in Fall 2022 over 4 terms: rising (+2.0 a year; a trend needs more than ±0.4).

