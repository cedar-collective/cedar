# What the tests in test-data-integrity.R share: builders, option lists, constants.

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
