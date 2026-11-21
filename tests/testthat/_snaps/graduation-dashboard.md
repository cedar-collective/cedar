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
    Code
      cat("\n", graduation_headline(none), "\n")
    Output
      
       No student in this scope has a last term that can be judged yet. 

