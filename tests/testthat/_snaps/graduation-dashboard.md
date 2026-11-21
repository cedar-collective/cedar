# XC01: with attempts and boards the payload counts each plan's required courses

    Code
      cat(format_graduation_dashboard(p)[-(1:25)], sep = "\n")
    Output
      ## By major
                                                   Left     120+  Standards   Pell
        Anthropology                                  2        0          0      2
        History                                       2        2          1      1
      
      ## The courses their plan names, and what they did in them here
      Half of these students left with 119 credits or more, and half had earned 119 or fewer of them here. 1 of 4 earned most of their credits somewhere else, so a course with no attempt here may have been met there.
      4 of the 4 students who left without a degree with 90 credits or more were in a program with a degree plan on file; 0 were not. Plans with fewer than 2 such students are not listed: 0 (0 students).
      Passed: a passing grade here in the course. Tried: a grade or late withdrawal here, never a pass.
      None: no attempt here, which is not the same as still required. -- : no one had taken a course under this code by then.
      
      ### Anthropology B.A.
      2 students in this program left without a degree with 90 credits or more, 1 of them pre-majors. Not read: 0 choices and elective slots.
        Course                   Passed    Tried     None
        ANTH 101                      0        1        1
      
      ### History B.A.
      2 students in this program left without a degree with 90 credits or more, 0 of them pre-majors. Not read: 2 choices and elective slots; 1 course no one had taken under the plan's number by then.
        Course                   Passed    Tried     None
        HIST 1101                     2        0        0
        HIST 201                      1        0        1
        HIST 201L                     0        1        1
        HIST 900                     --       --       --
      
      ## Each fall's first-time students: still here, and at what pace
      
      No entering class can be read at the start of its second year yet.
      
      No entering class can be read at the start of its third year yet.
      
      No entering class can be read at the start of its fourth year yet.
      
      No entering class can be read at the start of its fifth year yet.
      
      ### Credits earned here by the middle enrolled student, before each regular term since entering
        No class has credits on record.
      
      ## Passing 160 attempted credits with no degree yet
      No student in this scope passed 160 attempted credits where it can be seen.
      Not placed: 0 whose record began before the class lists, 0 already past it in their first term on record, 0 who already held a degree.

# XC01: the page's words

    Code
      cat(format_graduation_dashboard(p), sep = "\n")
    Output
      # Graduation: students who left without a degree
      Enrollment settled through Fall 2022; degrees posted through Fall 2022. 2 last terms are too recent to judge (everyone still enrolled is among them).
      
      Of the 8 students whose last term was between Fall 2020 and Spring 2021, 1 holds a degree and 7 left without one. 4 of those who left had 90 credits or more, 2 of them 120 or more.
      
      ## By credits when they stopped
        Credits           Left   Share    Pell     GPA <2  160+ att.   Either
        Under 30             1   14.3%      --       0.0%       0.0%     0.0%
        30 to 59             0    0.0%      --         --         --       --
        60 to 89             1   14.3%    0.0%       0.0%       0.0%     0.0%
        90 to 114            1   14.3%  100.0%       0.0%       0.0%     0.0%
        115 to 119           1   14.3%  100.0%         --       0.0%       --
        120 or more          2   28.6%   50.0%      50.0%      50.0%    50.0%
        Not recorded         1   14.3%      --         --         --       --
        1 total includes the last term's own credits, added because the record was pulled before the next term began.
      
      ## Left with 90 credits or more, by last term
        Term            90+     120+      All
        Fall 2020         0        0        1
        Spring 2021       4        2        6
      
      ## By college
                                                   Left     120+  Standards   Pell
        College of Arts and Sciences                  4        2          1      3
      
      ## By major
                                                   Left     120+  Standards   Pell
        Anthropology                                  2        0          0      2
        History                                       2        2          1      1
      
      ## Each fall's first-time students: still here, and at what pace
      
      No entering class can be read at the start of its second year yet.
      
      No entering class can be read at the start of its third year yet.
      
      No entering class can be read at the start of its fourth year yet.
      
      No entering class can be read at the start of its fifth year yet.
      
      ### Credits earned here by the middle enrolled student, before each regular term since entering
        No class has credits on record.
      
      ## Passing 160 attempted credits with no degree yet
      No student in this scope passed 160 attempted credits where it can be seen.
      Not placed: 0 whose record began before the class lists, 0 already past it in their first term on record, 0 who already held a degree.
    Code
      cat("\n", graduation_headline(none), "\n")
    Output
      
       No student in this scope has a last term that can be judged yet. 

# EC01: the entering classes' pace, as the page shows it

    Code
      cat(format_graduation_pace(pace), sep = "\n")
    Output
      
      ## Each fall's first-time students: still here, and at what pace
      
      At the start of their second year, 66.7% of the Fall 2020 class were still enrolled or had a degree, and 16.7% were enrolled on pace for four years. For the Fall 2021 class it was 33.3% and 0.0%.
        Class       Entered   Degree   4-year   6-year   Slower  Unknown     Gone
        Fall 2020         6    16.7%    16.7%     0.0%    33.3%     0.0%    33.3%
        Fall 2021         3     0.0%     0.0%     0.0%    33.3%     0.0%    66.7%
      
      At the start of their third year, 33.3% of the Fall 2020 class were still enrolled or had a degree, and 16.7% were enrolled on pace for four years.
        Class       Entered   Degree   4-year   6-year   Slower  Unknown     Gone
        Fall 2020         6    16.7%    16.7%     0.0%     0.0%     0.0%    66.7%
      
      No entering class can be read at the start of its fourth year yet.
      
      No entering class can be read at the start of its fifth year yet.
      
      ### Credits earned here by the middle enrolled student, before each regular term since entering
        Fall 2020    15  18  45  60
        Fall 2021    14  15

