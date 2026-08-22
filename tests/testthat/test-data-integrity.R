# Tests for data-integrity.R
# Tests R/cones/data-integrity.R
#
# Uses the IDS01 fixtures in designed_test_data.R. See the block comment there
# for the layout; the short version is that the fixture contains one genuinely
# split table and one table that merely covers a wider population, because
# telling those apart is the whole job of this cone.

context("Data Integrity")

ids_tables <- function() {
  list(
    ids_clean   = test_ids_clean,
    ids_split   = test_ids_split,
    ids_partial = test_ids_partial,
    ids_orphan  = test_ids_orphan
  )
}

ids_result <- function() {
  check_student_id_integrity(test_ids_spine, ids_tables(),
                             opt = list(spine_name = "ids_spine"))
}

verdict_for <- function(res, tbl) {
  res$by_table$verdict[res$by_table$table == tbl]
}


test_that("check_student_id_integrity reports the spine it compared against", {
  res <- ids_result()

  expect_equal(res$spine$name, "ids_spine")
  expect_equal(res$spine$n_ids, 4L)
  expect_equal(res$spine$n_terms, 2L)
})

test_that("check_student_id_integrity flags a table with two ID spaces", {
  res <- ids_result()

  expect_equal(verdict_for(res, "ids_split"), "split")
  expect_equal(res$n_tables_split, 1L)
})

test_that("check_student_id_integrity does not flag a merely wider population", {
  res <- ids_result()

  # ids_partial matches half its rows in every term. That is what an applicants
  # table looks like, and calling it broken would bury the real defect.
  expect_equal(verdict_for(res, "ids_partial"), "consistent")

  partial_terms <- res$by_term %>% filter(table == "ids_partial")
  expect_true(all(partial_terms$term_status == "partial"))
  expect_false(any(partial_terms$n_matched == 0))
})

test_that("check_student_id_integrity separates 'no overlap' from 'split'", {
  res <- ids_result()

  # Every term failing is as consistent with a separate population as with a bad
  # hash. The cone reports what it sees rather than guessing which.
  expect_equal(verdict_for(res, "ids_orphan"), "no overlap")
  expect_equal(verdict_for(res, "ids_clean"), "consistent")
})

test_that("check_student_id_integrity marks the exact failing terms", {
  res <- ids_result()
  none_terms <- res$by_term %>% filter(term_status == "none")

  # ids_split at 202410, ids_orphan at both terms.
  expect_equal(nrow(none_terms), 3L)
  expect_equal(
    none_terms %>% filter(table == "ids_split") %>% pull(term),
    202410L
  )
  expect_setequal(
    none_terms %>% filter(table == "ids_orphan") %>% pull(term),
    c(202410L, 202480L)
  )
})

test_that("check_student_id_integrity counts term statuses per table", {
  res <- ids_result()
  split_row <- res$by_table %>% filter(table == "ids_split")

  expect_equal(split_row$n_terms, 2L)
  expect_equal(split_row$n_terms_full, 1L)
  expect_equal(split_row$n_terms_none, 1L)
  expect_equal(split_row$n_terms_partial, 0L)
  expect_equal(split_row$pct_ids_matched, 50)
})

test_that("check_student_id_integrity stops on a table missing a required column", {
  bad <- ids_tables()
  bad$ids_clean <- bad$ids_clean %>% select(-term)

  expect_error(
    check_student_id_integrity(test_ids_spine, bad),
    "ids_clean"
  )
})

test_that("check_student_id_integrity stops on unnamed or empty table lists", {
  expect_error(check_student_id_integrity(test_ids_spine, list()), "empty")
  expect_error(
    check_student_id_integrity(test_ids_spine, list(test_ids_clean)),
    "named"
  )
})

test_that("check_student_id_integrity stops when the spine lacks the id column", {
  expect_error(
    check_student_id_integrity(test_ids_spine %>% select(-student_id), ids_tables()),
    "student_id"
  )
})
