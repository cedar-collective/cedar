context("Named population groups")

# HP01 in fixtures/designed_test_data.R holds the program rows these assert on.
# Its header explains what each declared/pre-major pair proves.

test_that("a group resolves through both name matching and the canon map", {
  codes <- population_group_major_codes(
    "Health Professions (Clinical)", test_programs_hp
  )

  # FRAD shares "Radiologic Sciences" with RADS but is a different code. A group
  # built from declared codes alone loses 3 of the program's 5 students -- the
  # real-data version of this cost 1,281 seats. See ISSUES.md I7.
  expect_true(all(c("RADS", "FRAD") %in% codes))
  expect_true(all(c("NURS", "FNRS") %in% codes))
  # MEDL's pre-major has a drifted name and no premaj_canon entry. It resolves
  # only because the registry lists both spellings -- remove that entry and two
  # students disappear with no error. See ISSUES.md I7.
  expect_true(all(c("MEDL", "FMDL") %in% codes))
  # The same drift with no registry entry stays out. Guessing at it would make
  # every plural-ish program name a silent member of some group.
  expect_false("XRAD" %in% codes)
  # A non-health control never resolves into a health group.
  expect_false("BIOL" %in% codes)
})

test_that("the audit reports the near miss it cannot resolve", {
  audit <- population_group_audit(
    "Health Professions (Clinical)", test_programs_hp
  )

  # The whole point: an unreachable pre-major is REPORTED, not guessed at and
  # not silently dropped.
  expect_true("Radiologic Science" %in% audit$near_miss$program_name)
  expect_true("XRAD" %in% audit$near_miss$major_code)
  # A drift the registry already covers is resolved, so it is not a near miss.
  expect_false("FMDL" %in% audit$near_miss$major_code)
  # Names in the group that match no program row are listed too.
  expect_true("Physical Therapy" %in% audit$unmatched_names)
  expect_false("Nursing" %in% audit$unmatched_names)
})

test_that("include_pre_majors splits declared from pre-major codes", {
  declared <- population_group_major_codes(
    "Health Professions (Clinical)", test_programs_hp, "majors_only"
  )
  pre <- population_group_major_codes(
    "Health Professions (Clinical)", test_programs_hp, "pre_only"
  )

  expect_true(all(c("RADS", "NURS", "MEDL") %in% declared))
  expect_false(any(c("FRAD", "FNRS") %in% declared))
  expect_true(all(c("FRAD", "FNRS") %in% pre))
  expect_setequal(
    population_group_major_codes("Health Professions (Clinical)", test_programs_hp),
    union(declared, pre)
  )
  expect_error(
    population_group_major_codes("Health Professions (Clinical)",
                                 test_programs_hp, "everyone"),
    "lump, majors_only, or pre_only"
  )
})

test_that("group lookup and required columns fail loudly", {
  expect_error(
    population_group_major_codes("No Such Group", test_programs_hp),
    "Unknown population group"
  )
  expect_error(
    population_group_major_codes(
      "Health Professions (Clinical)",
      dplyr::select(test_programs_hp, -is_pre_major)
    ),
    "programs is missing: is_pre_major"
  )
})

test_that("the registry is shared, not tab-specific", {
  expect_true(all(c("Health Professions (Clinical)", "All Health Programs") %in%
                    population_group_ids()))
  # Every declared entry must carry programs and a description, or the Pathways
  # selector renders a group that selects nothing.
  for (id in population_group_ids()) {
    group <- CEDAR_POPULATION_GROUPS[[id]]
    expect_true(length(group$programs) > 0, info = id)
    expect_true(nzchar(group$description %||% ""), info = id)
  }
})
