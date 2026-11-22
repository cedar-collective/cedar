# MT01: entrants by how they arrived

    Code
      cat(major_tenure_lead(first, "Undecided", min_n = 1L))
    Output
      2 students entered Undecided in their first term at UNM, as first-time students, between Fall 2020 and Fall 2021. By their third semester, 0.0% were still in it, 100.0% were enrolled in another major and 0.0% were not enrolled (of 1 who can be followed that far).

# MT01: the page's view of it

    Code
      cat(format_major_tenure(r, "Undecided"), sep = "\n")
    Output
      ## Semester by semester after entering Undecided
      5 students entered Undecided between Fall 2020 and Fall 2021. By their third semester, 25.0% were still in it, 25.0% were enrolled in another major and 25.0% were not enrolled (of 4 who can be followed that far).
      Not followed: 1 already in it when the data begin.
        When                Followed    In it    Other  No major   Degree     Away
        Entering semester          5   100.0%     0.0%      0.0%     0.0%     0.0%
        Semester 2                 5    40.0%    20.0%     20.0%     0.0%    20.0%
        Semester 3                 4    25.0%    25.0%      0.0%    25.0%    25.0%
        Semester 4                 4     0.0%    25.0%      0.0%    25.0%    50.0%

