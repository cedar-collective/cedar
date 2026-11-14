# the Topics payload reads as text

    Code
      cat(format_course_topics(tp_topics()), sep = "\n")
    Output
      FYEX 1110 by topic, Fall and Spring terms
      Terms run through Spring 2022. A term after Fall 2021, the most recent whose registration has settled, is in progress and counts current registration. Grades are read through Fall 2021, and return to the next regular term once that term has settled.
      A rate is shown for 1 or more students.
      
      FYEX 1110 taught on ABQ
        All topics: 3 terms (Fall 2020 to Fall 2021), 9 sections, 24 students at census, 6 instructors; DFW 29.2% (7 of 24); returned 60.0% (9 of 15)
        Success Starts Here: 2 terms (Fall 2020 to Fall 2021), 3 sections, 10 students at census, 2 instructors; DFW withheld; returned withheld
        Intro to UNM & Higher Ed: 2 terms (Fall 2020 to Fall 2021), 3 sections, 8 students at census, 2 instructors; DFW 25.0% (1 of 4), over 1 of its 2 graded terms; returned not observable yet
        Math Learning Strategies: 1 term (Spring 2021), 2 sections, 4 students at census, 1 instructor; DFW withheld; returned withheld
        Black Minds Matter: 1 term (Fall 2021), 1 section, 2 students at census, 1 instructor; DFW withheld; returned withheld
      
      FYEX 1110 taught on EA
        All topics: 1 term (Fall 2020), 1 section, 2 students at census, 1 instructor; DFW 50.0% (1 of 2); returned 50.0% (1 of 2)
        Success Starts Here: 1 term (Fall 2020), 1 section, 2 students at census, 1 instructor; DFW withheld; returned withheld
      
      Titles counted under a topic worded differently:
        ABQ "Sem: Intro to UNM & HED" -> Intro to UNM & Higher Ed (topic_titles.csv)
        ABQ "Sem: Intro to UNM and Higher Ed" -> Intro to UNM & Higher Ed (the same words)
        ABQ "Sem: Math Learning Stategies" -> Math Learning Strategies (topic_titles.csv)

---

    Code
      cat(format_course_topics(tp_topics(), unlocked = TRUE), sep = "\n")
    Output
      FYEX 1110 by topic, Fall and Spring terms
      Terms run through Spring 2022. A term after Fall 2021, the most recent whose registration has settled, is in progress and counts current registration. Grades are read through Fall 2021, and return to the next regular term once that term has settled.
      A rate is shown for 1 or more students.
      
      FYEX 1110 taught on ABQ
        All topics: 3 terms (Fall 2020 to Fall 2021), 9 sections, 24 students at census, 6 instructors; DFW 29.2% (7 of 24); returned 60.0% (9 of 15)
        Success Starts Here: 2 terms (Fall 2020 to Fall 2021), 3 sections, 10 students at census, 2 instructors; DFW 40.0% (4 of 10); returned 57.1% (4 of 7)
        Intro to UNM & Higher Ed: 2 terms (Fall 2020 to Fall 2021), 3 sections, 8 students at census, 2 instructors; DFW 25.0% (2 of 8); returned 75.0% (3 of 4)
        Math Learning Strategies: 1 term (Spring 2021), 2 sections, 4 students at census, 1 instructor; DFW 25.0% (1 of 4); returned 50.0% (2 of 4)
        Black Minds Matter: 1 term (Fall 2021), 1 section, 2 students at census, 1 instructor; DFW 0.0% (0 of 2); returned not observable yet
      
      FYEX 1110 taught on EA
        All topics: 1 term (Fall 2020), 1 section, 2 students at census, 1 instructor; DFW 50.0% (1 of 2); returned 50.0% (1 of 2)
        Success Starts Here: 1 term (Fall 2020), 1 section, 2 students at census, 1 instructor; DFW 50.0% (1 of 2); returned 50.0% (1 of 2)
      
      Titles counted under a topic worded differently:
        ABQ "Sem: Intro to UNM & HED" -> Intro to UNM & Higher Ed (topic_titles.csv)
        ABQ "Sem: Intro to UNM and Higher Ed" -> Intro to UNM & Higher Ed (the same words)
        ABQ "Sem: Math Learning Stategies" -> Math Learning Strategies (topic_titles.csv)

