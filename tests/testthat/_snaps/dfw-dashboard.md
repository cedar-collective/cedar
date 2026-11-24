# one course's sections can draw together on one campus and apart on another

    Code
      cat(.dfw_dash_spread(p$sections, 15L), sep = "\n")
    Output
        How far apart, in points beyond what chance gives sections of their sizes (Fall 2019 to Fall 2022; a direction is read from 4 or more terms):
          Every course, by term: 17.0, 16.3, 17.0, 19.0 (3, 3, 3, 3 courses): no clear change, the fitted line from 16.3 to 18.3.
          MATH 1220 (ABQ)    24.9 over 4 terms (3.0 sections a term; lowest 17.5%, highest 57.5% on average): spreading, the fitted line from 0.0 to 39.9.
          MATH 1220 (GA)     24.9 over 4 terms (3.0 sections a term; lowest 17.5%, highest 57.5% on average): consolidating, the fitted line from 39.9 to 0.0.
          ENGL 1110 (ABQ)    0.0 over 4 terms (4.0 sections a term; lowest 15.0%, highest 22.5% on average): no clear change, the fitted line from 0.0 to 0.0.

# a short history has an average and no direction, and an unreadable term is left out

    Code
      cat(.dfw_dash_spread(three_falls, 15L), sep = "\n")
    Output
        How far apart, in points beyond what chance gives sections of their sizes (Fall 2020 to Fall 2022; a direction is read from 4 or more terms):
          Every course, by term: 0.0, 22.1, 23.8 (2, 2, 2 courses): too few terms for a direction.
          Not listed: 2 courses read in fewer than 4 terms.

---

    Code
      cat(.dfw_dash_spread(ea, 15L), sep = "\n")
    Output
        How far apart: no course-term in scope has a spread between sections to read.

---

    Code
      cat(.dfw_dash_spread(s, 15L), sep = "\n")
    Output
        How far apart, in points beyond what chance gives sections of their sizes (Fall 2019 to Fall 2022; a direction is read from 4 or more terms):
          Every course, by term: 0.0, 0.0, 22.1, 38.5 (2, 2, 2, 1 courses): spreading, the fitted line from 0.0 to 35.4.
          MATH 1220 (ABQ)    24.9 over 4 terms (3.0 sections a term; lowest 17.5%, highest 57.5% on average): spreading, the fitted line from 0.0 to 39.9.
          Not listed: 1 course read in fewer than 4 terms.
          Left out: 1 course-term in which no student, or every student, got a DFW grade.

# the DFW dashboard's text preview

    Code
      cat(format_dfw_dashboard(p))
    Output
      DFW: lower-division courses, fall terms, every campus, graded through Fall 2022. DFW is every grade but A+ to C and CR, plus late withdrawals; early drops are left out.
      
      1. How UNM is doing
        Fall 2019     22.9%  32 of 140 DFW  (W 11, F 13, D or C- 8, other 0)
        Fall 2020     31.4%  44 of 140 DFW  (W 15, F 17, D or C- 12, other 0)
        Fall 2021     22.9%  32 of 140 DFW  (W 10, F 15, D or C- 7, other 0)
        Fall 2022     32.1%  45 of 140 DFW  (W 13, F 19, D or C- 12, other 1)
        Trend: 22.9% for Fall 2019, 32.1% for Fall 2022. Across the 4 terms the fitted line moves +1.9 points a year, where chance and the terms' own scatter give about 5.0: steady.
      
      2. Where the DFW grades are (Fall 2020, Fall 2021, Fall 2022)
        121 DFW grades in 420 attempts (28.8%) over 4 campus-courses. The top 1 hold a quarter of them; the top 2 hold half.
          #  course             college                          tries    DFW   rate  share    cum  trend
          1  MATH 1220 (ABQ)    College of Arts and Sciences        90     37  41.1%  30.6%  30.6%  rising (worse)
          2  PSYC 1110 (ABQ)    College of Arts and Sciences       120     36  30.0%  29.8%  60.3%  steady, swings
          3  MATH 1220 (EA)     College of Arts and Sciences        90     30  33.3%  24.8%  85.1%  steady
          4  ENGL 1110 (ABQ)    University College                 120     18  15.0%  14.9% 100.0%  falling (better)
      
      3. What is changing (every fall term with 30 or more attempts; the courses listed in 2)
        Rising: 1 listed course, most DFW grades first:
          MATH 1220 (ABQ)     20.0% ->  53.3% (Fall 2019 to Fall 2022), +11.0 points a year
        Falling: 1 listed course, most DFW grades first:
          ENGL 1110 (ABQ)     30.0% ->   7.5% (Fall 2019 to Fall 2022), -7.5 points a year
        Swinging more than courses usually do (a typical course moves 0.0 points a term beyond chance; 4 courses tested at once): 1, most DFW grades first:
          PSYC 1110 (ABQ)    19.0 points a term around its line
      
      4. Sections that disagree (Fall 2020, Fall 2021, Fall 2022)
        6 course-terms had 3 or more sections of 10+ attempts; in 2 the sections' rates differed more than chance allows.
        Uneven in two or more terms: 1 course:
          MATH 1220 (ABQ)    uneven in 2 of 3 terms: Fall 2021 0-80% across 3; Fall 2022 20-100% across 3
        How far apart, in points beyond what chance gives sections of their sizes (Fall 2019 to Fall 2022; a direction is read from 4 or more terms):
          Every course, by term: 0.0, 0.0, 22.1, 23.8 (2, 2, 2, 2 courses): spreading, the fitted line from 0.0 to 24.8.
          MATH 1220 (ABQ)    24.9 over 4 terms (3.0 sections a term; lowest 17.5%, highest 57.5% on average): spreading, the fitted line from 0.0 to 39.9.
          ENGL 1110 (ABQ)    0.0 over 4 terms (4.0 sections a term; lowest 15.0%, highest 22.5% on average): no clear change, the fitted line from 0.0 to 0.0.
      
      5. By campus, every campus (first term -> last, trend)
        ABQ                                   20.0% ->  31.8%  steady
        EA                                    33.3% ->  33.3%  steady
      
      6. By college (first term -> last, trend)
        College of Arts and Sciences          20.0% ->  42.0%  steady
        University College                    30.0% ->   7.5%  falling (better)

