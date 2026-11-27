# the text preview reads as a reviewer's checklist

    Code
      cat(format_compiled_degree_preview("Biology B.S.", compiled,
        compare_compiled_degree(compiled, test_degree_roadmaps, BIOLOGY)))
    Output
      Biology B.S.
      Board tiles (2):
        Choice: Biology I with its lab, or Combined Biology [BIOL 2110, BIOL 2110L, BIOL 200] · 2 tiles · 4 credits
      Credit rules the reading cannot place on the board (1)
        At least 120 degree credits
      Conditions (2)
        admission: At least two upper-level courses
        admission: Department permission
      Unresolved, for a reviewer (1)
        Does Combined Biology replace both Biology I and its lab?
      Concentrations not compiled (1)
        Cellular Biology concentration (2 rules)
      Against the hand-built board:
        Tiles: 2 compiled, 12 on the board
        Elective credits: 0 compiled, 3 on the board
        Required and on the board: none
        Required, on the shared math and English routes: none
        Required, missing from the board: none
        On the board, not in the reading: BIOL 2110C, BIOL 2120C, BIOL 2305, BIOL 300C, BIOL 304C, BIOL 3200, BIOL 499, CHEM 1215, CHEM 1215L, CHEM 1225, CHEM 1225L, ENVS 1110C, GEOL 1110, GEOL 1110L, PHYS 1230, PHYS 1230L, PHYS 1310
        Choice Biology I with its lab, or Combined Biology: 3 options; the board shows none

# the board comparison reads as a semester-by-semester checklist

    Code
      cat(format_degree_board_comparison("Biology B.S.", "calculus", placed, hand,
        draft$held))
    Output
      Biology B.S. · math start: calculus
        Semesters: 8 draft, 8 on the board
        Arrows: 1 draft, 11 on the board; 0 held for a reviewer
        Conditions: 0 course-count (0 wait on a choice), 0 standing, admission or permission; 0 on the board
        Courses on both: 2, same semester for 2
          ENGL 1110         draft 1 · board 1
          BIOL 2110C        draft — · board 1
          CHEM 1215 + 1215L draft — · board 1
          MATH 1512         draft — · board 1
          ENGL 1120         draft 2 · board 2
          BIOL 2120C        draft — · board 2
          CHEM 1225 + 1225L draft — · board 2
          PHYS 1310         draft — · board 2
          BIOL 2305         draft — · board 3
          BIOL 300C         draft — · board 5
          BIOL 304C         draft — · board 5
          BIOL 3200         draft — · board 5
          BIOL 499          draft — · board 8
          MATH 1350         draft 1 · board —

---

    Code
      cat(format_degree_board_comparison("Biology B.S.", "calculus", placed, NULL,
        draft$held))
    Output
      Biology B.S. · math start: calculus
        Semesters: 8 draft; no hand-built board to compare
        Arrows: 1 draft; 0 held for a reviewer
        Conditions: 0 course-count (0 wait on a choice), 0 standing, admission or permission
        Courses: 3; choices: 2
          ENGL 1110    draft 1
          MATH 1350    draft 1
          ENGL 1120    draft 2

