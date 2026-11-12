# outcomes are compared inside HS GPA bands and standardized to the treatment mix

    Code
      cat(course_sequence_headline(result), sep = "\n")
    Output
      Students who passed SEQ 101 before SEQ 201 did not pass SEQ 201 100.0% of the time (2 of 2); students who took SEQ 201 without a prior pass in SEQ 101, 25.0% (1 of 4): a higher rate, by 75.0 points.
      The groups differ substantially on 1 of 2 measured covariates, most on ACT score (20.00 against 19.00), so the gap describes who took each path before it describes SEQ 101.
      Within the same high-school GPA bands, students without the prior pass did not pass 16.7% of the time against 100.0% for the 2 who passed SEQ 101 first: a gap of 83.3 points once the two groups have the same GPA mix.

# several later-course codes are one course: each student once, at the earliest attempt

    Code
      cat(course_sequence_headline(family)[1], sep = "\n")
    Output
      Students who passed SEQ 101 before SEQ 201 or SEQ 201X did not pass SEQ 201 or SEQ 201X 66.7% of the time (2 of 3); students who took SEQ 201 or SEQ 201X without a prior pass in SEQ 101, 25.0% (1 of 4): a higher rate, by 41.7 points.

# course_sequence_headline says the two rates, their counts and the balance verdict

    Code
      cat(headline, sep = "\n")
    Output
      Students who passed SPAN 101 before SPAN 201 did not pass SPAN 201 33.3% of the time (1 of 3); students who took SPAN 201 without a prior pass in SPAN 101, 0.0% (0 of 1): a higher rate, by 33.3 points.
      The groups differ substantially on 2 of 2 measured covariates, most on Pell eligibility (33.3% against 100.0%), so the gap describes who took each path before it describes SPAN 101.

