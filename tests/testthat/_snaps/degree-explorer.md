# checking a reading names every problem at once, by node or block, before it is committed

    Code
      cat(format_catalog_reading_check(clean), sep = "\n")
    Output
      biology.v1.json: ready to commit; 15 open items (Not sorted yet 15)
        rule:rule-1 [Not sorted yet]: Complete all of the following
        rule:rule-2 [Not sorted yet]: Complete at least 1 of the following:
        rule:rule-3 [Not sorted yet]: Complete the following:
        rule:rule-4 [Not sorted yet]: BIOL2110 - Biology I (3)
        rule:rule-5 [Not sorted yet]: BIOL2110L - Biology I Lab (1)
        rule:rule-6 [Not sorted yet]: BIOL200 - Combined Biology (4)
        rule:rule-7 [Not sorted yet]: At least two upper-level courses and department permission.
        rule:rule-8 [Not sorted yet]: "Biology B.S."
        rule:rule-9 [Not sorted yet]: "BS Biology"
        rule:rule-10 [Not sorted yet]: "undergraduateProgram"
        rule:rule-11 [Not sorted yet]: {"name":"Bachelor of Science"}
        rule:rule-12 [Not sorted yet]: "120"
        rule:rule-13 [Not sorted yet]: Complete the following:
        rule:rule-14 [Not sorted yet]: BIOL200 - Combined Biology (4)
        rule:rule-15 [Not sorted yet]: "Cellular Biology"
    Code
      cat(format_catalog_reading_check(check), sep = "\n")
    Output
      biology.v1.json: 4 problems
        node rule-1: Citation does not match its requested source block: b-7dcbcb97cd7ee63e0e5368a9 does not contain "A quotation the catalog never published"
        node rule-3: Unknown or duplicate course reference: courses:not-captured
        block b-d393fa921001d2c885dde016: Coverage must account for every requested block exactly once (it has no coverage)
        Biology B.S.: the triage names no open item, or names one twice: rule:no-such-rule

# the board's math sentence names the route's math course, or says what the start adds (I97)

    Code
      roadmap_view(BIOLOGY, "algebra")$math_note
    Output
      [1] "MATH 1512 starts in semester 3."
    Code
      roadmap_view(HISTORY, "intermediate")$math_note
    Output
      [1] "This math starting point adds MATH 1215 in semester 1, as preparation."
    Code
      roadmap_view(HISTORY, "algebra")$math_note
    Output
      [1] "This math starting point adds no math course to the plan."

# a board compiled from the catalog says so in the degree list and on the board

    Code
      names(degree_catalog_choices(test_degree_catalog, degree_board_status_demo))
    Output
      [1] "Biology B.S. (synthetic) · 2026-2027 · draft"
      [2] "History B.A. (synthetic) · 2026-2027"        
    Code
      chip(degree_board_status_demo[1, ])
    Output
      [1] "<span class=\"cedar-roadmap-prototype\" title=\"Its catalog reading is not signed off in Catalog Review.\">Planning prototype · draft from the catalog, not yet reviewed</span>"
    Code
      chip(reviewed[1, ])
    Output
      [1] "<span class=\"cedar-roadmap-prototype\" title=\"Its catalog reading was signed off in Catalog Review on 2026-11-16.\">Planning prototype · from the catalog, reviewed</span>"
    Code
      chip(degree_board_status_demo[2, ])
    Output
      [1] "<span class=\"cedar-roadmap-prototype\">Planning prototype</span>"

