# the trend is said in words

    Code
      cat(later_course_trend_sentences(later_course_trend_payload), sep = "\n")
    Output
      ABQ, Fall terms of STAT 145: the share taking STAT 245 within 3 regular terms was 40.0% for Fall 2018 and 60.0% for Fall 2022. Across the 5 terms the fitted line moves +5.0 points a year, where chance and the terms' own scatter give about 3.2: an upward trend.
      ABQ, Fall terms of STAT 145: the pass rate in STAT 245 among those graded was 75.0% for Fall 2018 and 75.0% for Fall 2022. Across the 5 terms the fitted line moves +0.1 points a year, where chance and the terms' own scatter give about 4.0: no trend beyond that.
      ABQ, Spring terms of STAT 145: the share taking STAT 245 within 3 regular terms has a rate in 2 terms; a trend is read from 3 or more.
      ABQ, Spring terms of STAT 145: the pass rate in STAT 245 among those graded has a rate in 2 terms; a trend is read from 3 or more.
      EA, Fall terms of STAT 145: the share taking STAT 245 within 3 regular terms was 50.0% for Fall 2018 and 56.0% for Fall 2022. Across the 5 terms the fitted line moves +2.4 points a year, where chance and the terms' own scatter give about 4.1: no trend beyond that.
      EA, Fall terms of STAT 145: the pass rate in STAT 245 among those graded was 75.0% for Fall 2018 and 75.0% for Fall 2022. Across the 5 terms the fitted line moves +0.0 points a year, where chance and the terms' own scatter give about 0.4: no trend beyond that.
      GA, Fall terms of STAT 145: the share taking STAT 245 within 3 regular terms was 60.0% for Fall 2018 and 40.0% for Fall 2022. Across the 5 terms the fitted line moves -5.0 points a year, where chance and the terms' own scatter give about 3.2: a downward trend.
      GA, Fall terms of STAT 145: the pass rate in STAT 245 among those graded was 75.0% for Fall 2018 and 75.0% for Fall 2022. Across the 5 terms the fitted line moves -0.1 points a year, where chance and the terms' own scatter give about 4.0: no trend beyond that.

# the page's text preview

    Code
      cat(format_later_course(ds_later_course(min_n = 5L)), sep = "\n")
    Output
      STAT 145 -> STAT 245, within 3 regular terms
      Enrollment in STAT 145 and in STAT 245 is followed through Fall 2022, the most recent term whose registration has settled; grades are read through Summer 2022. A student counts only when 3 regular terms after STAT 145 had passed by Fall 2022.
      A rate is shown for 5 or more students.
      
      STAT 145 taught on ABQ
             15  took STAT 145 through Fall 2022, counted at their first attempt
              2  too recent to have had 3 regular terms to take STAT 245
              1  had already passed STAT 245 before STAT 145
             12  could have taken STAT 245 within 3 regular terms (took STAT 145 Fall 2020 to Spring 2021)
              9  took STAT 245 within 3 regular terms
              4  passed it
              4  DFW, including withdrawals
              1  of them withdrew (late drop or W)
              1  took it after Summer 2022, not yet graded
              0  no recorded outcome (blank or audit)
        Took STAT 245: 75.0% (9 of 12); passed, of those graded: 50.0% (4 of 8)
      
      By term of STAT 145:
        ABQ  Fall 2020    in X    12  could    11  took 72.7% (8 of 11)         passed 50.0% (4 of 8)          not graded 0
        ABQ  Spring 2021  in X     1  could     1  took — (1 of 1)            passed — (0 of 0)            not graded 1
        ABQ  Spring 2022  in X     2  could     0  took — (0 of 0)            passed — (0 of 0)            not graded 0
        ABQ, Fall terms of STAT 145: the share taking STAT 245 within 3 regular terms has a rate in 1 term; a trend is read from 3 or more.
        ABQ, Fall terms of STAT 145: the pass rate in STAT 245 among those graded has a rate in 1 term; a trend is read from 3 or more.
      
      By grade in STAT 145:
        ABQ  A                 could     3  took — (3 of 3)            passed — (2 of 3)
        ABQ  B                 could     4  took — (3 of 4)            passed — (1 of 2)
        ABQ  C                 could     2  took — (1 of 2)            passed — (0 of 1)
        ABQ  C- to F           could     2  took — (2 of 2)            passed — (1 of 2)
        ABQ  Withdrew          could     1  took — (0 of 1)            passed — (0 of 0)
      
      When they took STAT 245:
        ABQ  The next regular term        5  55.6% of continuers, 41.7% of all who could by then
        ABQ  2 regular terms later        3  33.3% of continuers, 66.7% of all who could by then
        ABQ  3 regular terms later        1  11.1% of continuers, 75.0% of all who could by then
      
      Passed STAT 245 before or with STAT 145, by academic year:
        ABQ  2020-2021 took X    13  before    1  same term    1  either    2
        ABQ  2021-2022 took X     2  before    1  same term    0  either    1

# a set of later courses is named as any of them, with its pass rule

    Code
      cat(format_later_course(set, instructors = TRUE), sep = "\n")
    Output
      SPAN 101 -> any of 2 later courses, within 2 regular terms
      Later courses: SPAN 101L, SPAN 201
      Enrollment in SPAN 101 and in any of 2 later courses is followed through Spring 2021, the most recent term whose registration has settled; grades are read through Spring 2021. A student counts only when 2 regular terms after SPAN 101 had passed by Spring 2021.
      A rate is shown for 1 or more students.
      
      SPAN 101 taught on ABQ
              4  took SPAN 101 through Spring 2021, counted at their first attempt
              0  too recent to have had 2 regular terms to take any of 2 later courses
              4  could have taken any of 2 later courses within 2 regular terms (took SPAN 101 Spring 2020 to Spring 2020)
              3  took any of 2 later courses within 2 regular terms
              2  passed what they took
              1  DFW, including withdrawals
              0  of them withdrew (late drop or W)
              0  took it after Spring 2021, not yet graded
              0  no recorded outcome (blank or audit)
        Took any of 2 later courses: 75.0% (3 of 4); passed, of those graded: 66.7% (2 of 3)
      
      SPAN 101 taught on GA
              2  took SPAN 101 through Spring 2021, counted at their first attempt
              0  too recent to have had 2 regular terms to take any of 2 later courses
              2  could have taken any of 2 later courses within 2 regular terms (took SPAN 101 Spring 2020 to Spring 2020)
              1  took any of 2 later courses within 2 regular terms
              1  passed what they took
              0  DFW, including withdrawals
              0  of them withdrew (late drop or W)
              0  took it after Spring 2021, not yet graded
              0  no recorded outcome (blank or audit)
        Took any of 2 later courses: 50.0% (1 of 2); passed, of those graded: 100.0% (1 of 1)
      
      By term of SPAN 101:
        ABQ  Spring 2020  in X     4  could     4  took 75.0% (3 of 4)          passed 66.7% (2 of 3)          not graded 0
        GA   Spring 2020  in X     2  could     2  took 50.0% (1 of 2)          passed 100.0% (1 of 1)         not graded 0
        ABQ, Spring terms of SPAN 101: the share taking any of 2 later courses within 2 regular terms has a rate in 1 term; a trend is read from 3 or more.
        ABQ, Spring terms of SPAN 101: the pass rate among those graded in what they took has a rate in 1 term; a trend is read from 3 or more.
        GA, Spring terms of SPAN 101: the share taking any of 2 later courses within 2 regular terms has a rate in 1 term; a trend is read from 3 or more.
        GA, Spring terms of SPAN 101: the pass rate among those graded in what they took has a rate in 1 term; a trend is read from 3 or more.
      
      By grade in SPAN 101:
        ABQ  A                 could     2  took 100.0% (2 of 2)         passed 50.0% (1 of 2)
        ABQ  B                 could     2  took 50.0% (1 of 2)          passed 100.0% (1 of 1)
        GA   A                 could     1  took 100.0% (1 of 1)         passed 100.0% (1 of 1)
        GA   C                 could     1  took 0.0% (0 of 1)           passed — (0 of 0)
      
      When they took any of 2 later courses:
        ABQ  The next regular term        3  100.0% of continuers, 75.0% of all who could by then
        ABQ  2 regular terms later        0  0.0% of continuers, 75.0% of all who could by then
        GA   The next regular term        1  100.0% of continuers, 50.0% of all who could by then
        GA   2 regular terms later        0  0.0% of continuers, 50.0% of all who could by then
      
      Passed any of 2 later courses before or with SPAN 101, by academic year:
        ABQ  2019-2020 took X     4  before    0  same term    2  either    2
        GA   2019-2020 took X     2  before    0  same term    0  either    0
      
      By instructor in SPAN 101:
        ABQ  MC_I1                      could     4  passed X 100.0%  A or B 100.0%  took 75.0% (3 of 4)          passed 66.7% (2 of 3)
        GA   MC_I2                      could     2  passed X 100.0%  A or B  50.0%  took 50.0% (1 of 2)          passed 100.0% (1 of 1)

