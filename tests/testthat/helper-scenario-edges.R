# The right edges each designed scenario is read through: one list per scenario,
# for every test file that reads it. The designed fixtures are pulled within
# days of their last term, so cedar_data_edges() settles none of them; a test
# states the edges it observes through, as the list a cone takes in
# opt$data_edges (AGENTS.md, Right edges).

# RP01: Spring 2021 is settled and graded.
rp01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L, last_graded = 202110L)

# MC02: Spring 2021 is settled and graded; Fall 2021 is the newest term named.
mc02_edges <- list(last_enrolled = 202180L, last_enrolled_complete = 202110L, last_graded = 202110L)

# MC02 as the observational machinery reads it: the same edges, with the first
# term and no degree edge.
.impact_edges <- list(
  first_enrolled = 202010L,
  last_enrolled = 202180L,
  last_enrolled_complete = 202110L,
  last_graded = 202110L,
  last_degree = NULL
)

# DS01: Fall 2022 is settled and Summer 2022 is the last graded term, so a
# Fall 2022 enrollment counts as taken and is not graded yet.
ds01_edges <- list(
  first_enrolled = 202010L,
  last_enrolled = 202310L,
  last_enrolled_complete = 202280L,
  last_graded = 202260L,
  last_degree = NULL
)

# RW01: Spring 2021 is in registration, so Fall 2020 is the settled and graded
# edge. rw01_settled_edges reads the same rows once Spring 2021 has settled.
rw01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202080L, last_graded = 202080L)
rw01_settled_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L, last_graded = 202110L)

# ST01: Spring 2021 is settled; no test on it reads a grade.
st01_edges <- list(last_enrolled = 202110L, last_enrolled_complete = 202110L)

# EC-11 and EC-11b (course planning history, and the Degree Explorer popup that
# shows it): Fall 2020 is settled, Fall 2021 is the newest term named.
history_edges <- list(last_enrolled_complete = 202080L, last_enrolled = 202180L)

# The seatfinder fixtures: their terms run to 202580, past the designed
# fixtures' own edge, so the cone is handed edges that match the terms
# with_seatfinder_test_terms() sets (helper-seatfinder.R).
seatfinder_test_edges <- list(
  last_graded = 202580L, last_enrolled = 202680L,
  last_enrolled_complete = 202580L
)
