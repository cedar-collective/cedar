# What the tests in test-data-integrity.R share: builders, option lists, constants.

ids_result <- function() {
  check_student_id_integrity(test_ids_spine, ids_tables,
                             opt = list(spine_name = "ids_spine"))
}

verdict_for <- function(res, tbl) {
  res$by_table$verdict[res$by_table$table == tbl]
}
