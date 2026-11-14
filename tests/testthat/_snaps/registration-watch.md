# the chart's note says what it leaves out

    Code
      cat(registration_watch_plot_note(prepare_registration_watch_plot_data(
        watch_payload)))
    Output
      1 course is more than 4 times or less than 1/4 of its usual, drawn at the chart's edge. 2 listed courses are not drawn: 1 with no earlier offering to compare and 1 with no usable seats. The list has every course.

# the text preview names each pattern and its courses

    Code
      cat(format_registration_watch(watch_payload), sep = "\n")
    Output
      Registration watch: Fall 2026 · ABQ, EA
      12 courses flagged by at least one Regstats screen; 1 usually near full and not listed.
      Near full means at least 90% of seats filled at census.
      
      Seats cut (2): fewer students than usual, and its sections are near full.
        SPAN 1110 (ABQ · AS): 445 enrolled against a usual 548; 456 seats, 97.6% filled at census; 3 screens.
        FDMA 1520 (ABQ · FA): 12 enrolled against a usual 62; 13 seats, 92.3% filled at census; 3 screens.
      
      Students waiting (3): students are still waiting for a seat.
        BIOL 2210 (ABQ · AS): 165 enrolled against a usual 160; 69 waiting; 168 seats, 98.2% filled at census; 3 screens.
        SPAN 1110 (EA · AS): 80 enrolled against a usual 50; 12 waiting; 80 seats, 100.0% filled at census; 4 screens.
        MATH 1350 (EA · AS): 9 waiting; 1 screen.
      
      Growth near capacity (1): more students than usual, and its sections are now near full.
        BIOL 2305 (ABQ · AS): 285 enrolled against a usual 210; 288 seats, 99.0% filled at census; 4 screens.
      
      Growth with churn (1): more students than usual, and more of them dropping.
        CHEM 1215 (ABQ · AS): 700 enrolled against a usual 500; 15 drops beyond the usual range; 2 screens.
      
      Falling demand (1): fewer students than usual, with seats to spare.
        HIST 1110 (ABQ · AS): 60 enrolled against a usual 110; 150 seats, 40.0% filled at census; 1 screen.
      
      Rising demand (1): more students than usual, with seats to spare.
        PSYC 1110 (ABQ · AS): 300 enrolled against a usual 250; 400 seats, 75.0% filled at census; 1 screen.
      
      Drop spike (1): more drops than usual.
        MATH 1215 (ABQ · AS): 340 enrolled against a usual 330; 400 seats, 85.0% filled at census; 22 drops beyond the usual range; 2 screens.
      
      Fuller than usual (1): fuller than its usual pattern.
        ARTH 1120 (ABQ · FA): 178 enrolled against a usual 170; 180 seats, 98.9% filled at census; 2 screens.
      
      By college:
        AS: seats cut 1, students waiting 3, growth near capacity 1, growth with churn 1, falling demand 1, rising demand 1, drop spike 1
        FA: seats cut 1, fuller than usual 1

