context("Named population groups")

# HP01 in fixtures/designed_test_data.R holds the program rows these assert on.
# Its header explains what each declared/pre-major pair proves. A group lists
# declared codes; pre-majors join by leads_to, renames by code_history.csv.

test_that("a group resolves its codes, their renames and their pre-majors", {
  codes <- population_group_major_codes("Health Professions (Clinical)")

  # Pre-majors through leads_to (UNM's programs.csv): FRAD -> RADS,
  # FNRS -> NURS, and FMDL -> MEDL despite its drifted name (ISSUES.md I7).
  expect_true(all(c("RADS", "FRAD", "NURS", "FNRS", "MEDL", "FMDL") %in% codes))
  # Neither a name nor a resemblance joins a group.
  expect_false(any(c("XRAD", "XNUR", "BIOL") %in% codes))

  renamed <- population_group_major_codes("Health Professions (Clinical)",
                                          successions = population_group_rename_successions)
  expect_setequal(setdiff(renamed, codes), "HSCI")
})

test_that("the audit reports the codes a code list leaves out", {
  audit <- population_group_audit("Health Professions (Clinical)", test_programs_hp)

  # A pre-major with no leads_to whose name resembles a group program's, and
  # a declared code sharing a group program's Banner name: reported, not taken.
  expect_setequal(audit$near_miss$major_code, c("XRAD", "XNUR"))
  # A drift a leads_to covers is resolved, so it is not a near miss.
  expect_false("FMDL" %in% audit$near_miss$major_code)
  # Codes the group lists that no student holds are listed too.
  expect_true("PT" %in% audit$unheld_codes)
  expect_false("NURS" %in% audit$unheld_codes)
})

test_that("include_pre_majors splits declared from pre-major codes", {
  declared <- population_group_major_codes("Health Professions (Clinical)", "majors_only")
  pre <- population_group_major_codes("Health Professions (Clinical)", "pre_only")

  expect_true(all(c("RADS", "NURS", "MEDL") %in% declared))
  expect_false(any(c("FRAD", "FNRS") %in% declared))
  expect_true(all(c("FRAD", "FNRS") %in% pre))
  expect_setequal(population_group_major_codes("Health Professions (Clinical)"),
                  union(declared, pre))
  expect_error(population_group_major_codes("Health Professions (Clinical)", "everyone"),
               "lump, majors_only, or pre_only")
})

test_that("group lookup and required columns fail loudly", {
  expect_error(population_group_major_codes("No Such Group"), "Unknown population group")
  expect_error(
    population_group_audit("Health Professions (Clinical)",
                           dplyr::select(test_programs_hp, -is_pre_major)),
    "programs is missing: is_pre_major"
  )
})

test_that("the registry is shared, not tab-specific", {
  expect_true(all(c("Health Professions (Clinical)", "All Health Programs") %in%
                    population_group_ids()))
  # Every declared entry must carry codes and a description, or the Pathways
  # selector renders a group that selects nothing.
  for (id in population_group_ids()) {
    group <- CEDAR_POPULATION_GROUPS[[id]]
    expect_true(length(group$codes) > 0, info = id)
    expect_true(nzchar(group$description %||% ""), info = id)
  }
})
