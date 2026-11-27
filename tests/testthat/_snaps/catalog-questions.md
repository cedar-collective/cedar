# the questions read as a document for the catalog office

    Code
      cat(format_catalog_questions(catalog_question_rows(q), catalog_question_scope()))
    Output
      # Open questions in the catalog readings
      
      All open questions. 3 questions in 2 programs, each with the start of the catalog passage it is about.
      
      ## Bachelor of Arts in History
      
      https://catalog.example.invalid/#/programs/history
      
      1. Unresolved source treatment: The credit wording restates the elective requirement; read as the elective pool.
         Major requirements: "Earned at least 12 credits from HIST 300 - 499."
         (CEDAR's reading; catalog_interpretations/2026-2027/history.v1.json · passage b-hist-pool)
      
      ## Bachelor of Science in Biology
      
      https://catalog.example.invalid/#/programs/biology
      
      1. Does Combined Biology replace both Biology I and its lab? The list offers BIOL200 beside the pair without saying it covers the lab.
         Program requirements: "BIOL200 - Combined Biology (4)"
         (The catalog; catalog_interpretations/2026-2027/biology.v1.json · rule combined-scope)
      
      2. Is department permission required for admission, or only advised?
         Admission: "Admission to the major requires at least two upper-level courses and department permission. Students should meet with an advisor before applying, and the department reviews each application in the term after it is received. Students who are not admitted may apply again the following term after compl…"
         (Not sorted yet; catalog_interpretations/2026-2027/biology.v1.json · question 1)

---

    Code
      cat(format_catalog_questions(catalog_question_rows(q, "catalog"),
      catalog_question_scope("catalog")))
    Output
      # Open questions in the catalog readings
      
      Who can settle them: The catalog. 1 question in 1 program, each with the start of the catalog passage it is about.
      
      ## Bachelor of Science in Biology
      
      https://catalog.example.invalid/#/programs/biology
      
      1. Does Combined Biology replace both Biology I and its lab? The list offers BIOL200 beside the pair without saying it covers the lab.
         Program requirements: "BIOL200 - Combined Biology (4)"
         (The catalog; catalog_interpretations/2026-2027/biology.v1.json · rule combined-scope)

---

    Code
      cat(format_catalog_questions(catalog_question_rows(q, "capture",
        "Bachelor of Arts in History"), catalog_question_scope("capture",
        "Bachelor of Arts in History")))
    Output
      # Open questions in the catalog readings
      
      Who can settle them: CEDAR's copy of the catalog. Program: Bachelor of Arts in History
      
      No open questions.

