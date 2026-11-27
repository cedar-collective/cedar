# conflicting total-credit mentions are flagged without claiming which number is right

    Code
      cat(format_catalog_questions(catalog_question_rows(item), "All open questions"))
    Output
      # Open questions in the catalog readings
      
      All open questions. 1 question in 1 program, each with the start of the catalog passage it is about.
      
      ## Biology B.S.
      
      https://catalog.example.invalid/#/programs/biology
      
      1. Degree total: The catalog gives this degree two totals. Which is right?
         Total credits: "Degree Hours field: 120; Grand Total Credits: 130"
         (The catalog; the catalog page, then a new catalog scan)

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

