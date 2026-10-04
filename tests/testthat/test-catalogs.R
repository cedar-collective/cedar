# Tests for catalog-based lookup architecture
# Covers: subj_dept_map.R, program_map.qs, catalog_lookups.R
#
# These tests verify:
#   1. Catalog tibble structure (required columns, no NAs in key fields)
#   2. Cross-catalog integrity (every dept/college in program_map exists in subj_dept_map)
#   3. Lookup vector contents and known spot-check values
#   4. Branch campus disambiguation via compound key (major_college_to_dept)
#   5. dept-trends.R uses major_to_dept vector for reverse lookup

context("Catalog Architecture")

# =============================================================================
# Prerequisites
# =============================================================================

skip_if_no_catalogs <- function() {
  if (!exists("subj_dept_map") || !exists("program_map")) {
    skip("subj_dept_map / program_map not loaded — run load_funcs() first")
  }
}

skip_if_no_lookups <- function() {
  if (!exists("major_college_to_dept") || !exists("subj_to_dept")) {
    skip("catalog_lookups.R vectors not available")
  }
}

# =============================================================================
# 1. subj_dept_map structure
# =============================================================================

test_that("subj_dept_map has required columns", {
  skip_if_no_catalogs()
  required <- c("college_code", "college_name", "dept_code", "dept_name", "subject_code")
  missing  <- setdiff(required, colnames(subj_dept_map))
  expect_equal(missing, character(0),
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("subj_dept_map has no NA in key columns", {
  skip_if_no_catalogs()
  for (col in c("college_code", "dept_code", "subject_code")) {
    n_na <- sum(is.na(subj_dept_map[[col]]))
    expect_equal(n_na, 0L,
                 info = paste("subj_dept_map$", col, "has", n_na, "NA values"))
  }
})

test_that("subj_dept_map subject_codes are unique within each college", {
  skip_if_no_catalogs()
  # Subject codes can appear in multiple colleges (e.g., ARTS in FA and AD).
  # Within a single college, each subject code should map to exactly one dept.
  conflicts <- subj_dept_map |>
    group_by(college_code, subject_code) |>
    summarise(n_depts = n_distinct(dept_code), .groups = "drop") |>
    filter(n_depts > 1)
  expect_equal(nrow(conflicts), 0L,
               info = paste("subject_code maps to multiple depts within same college:",
                            paste(paste(conflicts$college_code, conflicts$subject_code, sep=":"),
                                  collapse = ", ")))
})

test_that("subj_dept_map contains expected colleges", {
  skip_if_no_catalogs()
  for (code in c("AS", "AD", "EN", "EH", "FA", "MG", "NU", "PA", "ME")) {
    expect_true(code %in% subj_dept_map$college_code,
                info = paste("College code missing from subj_dept_map:", code))
  }
})

test_that("subj_dept_map AD section includes required branch campus depts", {
  skip_if_no_catalogs()
  ad_depts <- subj_dept_map$dept_code[subj_dept_map$college_code == "AD"]
  # NURS is NOT here — branch campus NURS programs map to the NU:NURS dept entry
  for (dept in c("BUSA", "CJUS", "EDUC", "ECED", "APTE", "ASPE", "LART")) {
    expect_true(dept %in% ad_depts,
                info = paste("Branch campus dept missing from subj_dept_map AD:", dept))
  }
})

# =============================================================================
# 2. program_map structure
# =============================================================================

# ── Institution mapping files (ADR-002) ──────────────────────────────────────
# subj_dept_map is built from institution/<id>/ CSVs. The validator is what
# stops a malformed file from silently moving students between units.

# Scaffolding: one programs.csv row per argument value, defaults filled in.
program_rows <- function(program_code, unit_code = "HIST", college_code = "",
                         is_pre_major = "FALSE", leads_to = "", basis = "decided",
                         status = "confirmed") {
  data.frame(program_code, college_code, program_name = program_code, unit_code,
             is_pre_major, leads_to, basis, status, evidence = "", notes = "")
}

unm_settings <- data.frame(setting = "mapping_files_url",
                           value = "https://github.com/org/repo/blob/main/institution/x")

write_mapping_dir <- function(colleges, units, subjects, programs = program_rows("X")[0, ],
                              settings = unm_settings) {
  dir <- tempfile("institution-")
  dir.create(dir)
  utils::write.csv(colleges, file.path(dir, "colleges.csv"), row.names = FALSE)
  utils::write.csv(units, file.path(dir, "units.csv"), row.names = FALSE)
  utils::write.csv(subjects, file.path(dir, "subjects.csv"), row.names = FALSE)
  utils::write.csv(programs, file.path(dir, "programs.csv"), row.names = FALSE)
  utils::write.csv(settings, file.path(dir, "settings.csv"), row.names = FALSE)
  dir
}

one_unit <- list(
  colleges = data.frame(college_code = c("AS", "AD"), college_name = c("Arts and Sciences", "Branch")),
  units    = data.frame(unit_code = c("HIST", "SOCI", "CJUS"), unit_name = c("History", "Sociology", "Criminal Justice")),
  subjects = data.frame(subject_code = "HIST", college_code = "AS", unit_code = "HIST", notes = "")
)

test_that("UNM mapping files load into the subject-unit-college table", {
  files <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "unm"))
  built <- build_subj_dept_map(files)
  expect_equal(nrow(built), nrow(files$subjects))
  expect_false(anyNA(built$dept_name))
  expect_false(anyNA(built$college_name))
  # Branch campuses reuse subject codes for different units: the key is
  # subject AND college, and the same subject may resolve differently.
  hled <- built[built$subject_code == "HLED", ]
  expect_gt(length(unique(hled$dept_code)), 1)
})

test_that("the mapping validator reports every problem at once", {
  # Scaffolding: a three-row institution with three deliberate faults.
  dir <- write_mapping_dir(
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences"),
    units    = data.frame(unit_code = c("HIST", "HIST"), unit_name = c("History", "History")),
    subjects = data.frame(subject_code = c("HIST", "ANTH"), college_code = c("AS", "XX"),
                          unit_code = c("HIST", "ANTH"), notes = "")
  )
  err <- tryCatch(read_institution_mappings(dir), error = conditionMessage)
  expect_match(err, "duplicate unit_code HIST")
  expect_match(err, "unit_code not in units.csv: ANTH")
  expect_match(err, "college_code not in colleges.csv: XX")
})

test_that("a mapping file with the wrong columns, or an unknown institution, stops", {
  dir <- write_mapping_dir(
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences"),
    units    = data.frame(code = "HIST", name = "History"),
    subjects = data.frame(subject_code = "HIST", college_code = "AS", unit_code = "HIST", notes = "")
  )
  expect_error(read_institution_mappings(dir), "units.csv must have columns unit_code, unit_name")
  expect_error(cedar_institution_dir(cedar_base_dir, "no-such-place"), "No mapping files for institution 'no-such-place'")
  withr::with_envvar(c(CEDAR_INSTITUTION = "../etc"),
                     expect_error(cedar_institution_id(), "lowercase directory name"))
})

test_that("UNM programs.csv and source_departments.csv load and validate", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  files <- read_institution_mappings(dir)
  expect_gt(sum(files$programs$status == "confirmed"), 0)
  # No confirmed program is reported under a unit named after its own code
  # unless that unit really exists: the I7 failure, now impossible by file.
  conf <- files$programs[files$programs$status == "confirmed" & nzchar(files$programs$unit_code), ]
  expect_true(all(conf$unit_code %in% files$units$unit_code))
  sd <- validate_source_departments(read_institution_file("source_departments", dir), files$units)
  expect_true(all(c("department", "split", "bucket", "non_degree") %in% sd$kind))
})

test_that("the programs validator reports every program problem at once", {
  programs <- rbind(
    program_rows("HIST"), program_rows("HIST"),                    # duplicate
    program_rows("FHIS", is_pre_major = "TRUE", leads_to = "NOPE"),  # target not a program
    program_rows("ANTH", unit_code = "ANTH"),                       # unit not in units.csv
    program_rows("NOND", unit_code = ""),                           # confirmed, no unit, not no_unit
    program_rows("GUES", unit_code = "", basis = "unresolved"),     # unresolved but confirmed
    program_rows("ODD",  basis = "vibes", status = "maybe"),
    program_rows("LEAD", leads_to = "HIST")                         # target on a non-pre-major
  )
  dir <- do.call(write_mapping_dir, c(one_unit, list(programs = programs)))
  err <- tryCatch(read_institution_mappings(dir), error = conditionMessage)
  expect_match(err, "duplicate program/college HIST / ")
  expect_match(err, "leads_to is not a program_code: NOPE")
  expect_match(err, "unit_code not in units.csv: ANTH")
  expect_match(err, "confirmed with no unit_code \\(use basis no_unit if nothing owns it\\): NOND")
  expect_match(err, "basis unresolved must be a proposed row with no unit_code: GUES")
  expect_match(err, "unknown basis vibes")
  expect_match(err, "unknown status maybe")
  expect_match(err, "leads_to set on a row that is not a pre-major: LEAD")
})

test_that("settings.csv must name a GitHub location for the mapping files", {
  dir <- do.call(write_mapping_dir, c(one_unit, list(
    settings = data.frame(setting = "mapping_files_url", value = "my laptop"))))
  expect_error(read_institution_mappings(dir), "mapping_files_url must be a GitHub blob URL")
  dir <- do.call(write_mapping_dir, c(one_unit, list(
    settings = data.frame(setting = "other", value = "x"))))
  expect_error(read_institution_mappings(dir), "missing setting mapping_files_url")

  files <- read_institution_mappings(do.call(write_mapping_dir, one_unit))
  expect_equal(mapping_file_url(files, "programs"),
               "https://github.com/org/repo/edit/main/institution/x/programs.csv")
})

test_that("a mapping file row must be exactly one line", {
  # Line links and one-line diffs both depend on it; a quoted line break in a
  # notes field would silently shift every link below it.
  programs <- program_rows("HIST")
  programs$notes <- "decided\nby IR"
  dir <- do.call(write_mapping_dir, c(one_unit, list(programs = programs)))
  expect_error(read_institution_mappings(dir), "programs.csv has 3 lines for 1 rows")
})

test_that("resolve_program_units: one tier, college rows first, proposals assign nothing", {
  # Scaffolding mirroring UNM's CRIM: Sociology on main campus, Criminal
  # Justice at the branches (college AD).
  programs <- rbind(
    program_rows("CRIM", unit_code = "SOCI"),
    program_rows("CRIM", unit_code = "CJUS", college_code = "AD", basis = "override"),
    program_rows("ART",  unit_code = "HIST", status = "proposed", basis = "course_taking"),
    program_rows("NOND", unit_code = "", basis = "no_unit")
  )
  got <- resolve_program_units(
    program_code = c("CRIM", "CRIM", "CRIM", "ART", "NOND", "UNSEEN"),
    college_code = c("AS",   "AD",   NA,     "AS",  "AS",   "AS"),
    programs     = programs)
  expect_equal(got, c("SOCI", "CJUS", "SOCI", NA, NA, NA))
  # Never the code itself: an unseen code gets no unit, not a unit named UNSEEN.
  expect_false("UNSEEN" %in% got)
})

test_that("source_departments: kinds must carry the right number of units", {
  sd <- data.frame(
    source_name = c("History", "Theatre & Dance", "*Interdisciplinary", "Lonely Split"),
    unit_code   = c("HIST", "HIST|SOCI", "HIST", "HIST"),
    kind        = c("department", "split", "bucket", "split"), notes = "")
  err <- tryCatch(validate_source_departments(sd, one_unit$units), error = conditionMessage)
  expect_match(err, "\\*Interdisciplinary, Lonely Split")
  sd$kind[3:4] <- c("bucket", "department"); sd$unit_code[3] <- ""
  expect_silent(validate_source_departments(sd, one_unit$units))
})

test_that("program_map has required columns", {
  skip_if_no_catalogs()
  required <- c("program_code", "college_code", "dept_code", "major_code",
                "degree_abbr", "degree_level", "program_type")
  missing  <- setdiff(required, colnames(program_map))
  expect_equal(missing, character(0),
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("program_map has no NA in program_code or major_code", {
  skip_if_no_catalogs()
  for (col in c("program_code", "major_code")) {
    n_na <- sum(is.na(program_map[[col]]))
    expect_equal(n_na, 0L,
                 info = paste("program_map$", col, "has", n_na, "NA values"))
  }
})

test_that("each (major_code, college_code) maps to exactly one dept_code", {
  skip_if_no_catalogs()
  # A program can have multiple degree types (BA, MA, PhD) in the same college,
  # but they must all belong to the same dept. This is the invariant major_college_to_dept relies on.
  # Exclude rows with NA dept_code (unmapped programs) from this check.
  conflicts <- program_map |>
    filter(!is.na(dept_code)) |>
    group_by(major_code, college_code) |>
    summarise(n_depts = n_distinct(dept_code), .groups = "drop") |>
    filter(n_depts > 1)
  expect_equal(nrow(conflicts), 0L,
               info = paste("program:college → multiple depts:",
                            paste(paste(conflicts$major_code, conflicts$college_code, sep=":"),
                                  collapse = ", ")))
})

test_that("program_map contains branch campus (AD) programs", {
  skip_if_no_catalogs()
  ad_rows <- program_map[!is.na(program_map$college_code) & program_map$college_code == "AD", ]
  expect_true(nrow(ad_rows) >= 40,
              info = paste("Expected >=40 AD rows, found", nrow(ad_rows)))
  # Spot check specific programs
  ad_programs <- ad_rows$major_code
  for (prog in c("CRIM", "CRJS", "ECED", "AASN", "BADM", "NURS")) {
    expect_true(prog %in% ad_programs,
                info = paste("Branch campus program missing:", prog))
  }
})

# =============================================================================
# 3. Cross-catalog integrity
# =============================================================================

test_that("all mapped dept_codes in program_map exist in subj_dept_map", {
  skip_if_no_catalogs()
  # UNDC is a pseudo-dept for undeclared/non-degree students — no subj_dept_map entry by design
  known_pseudo_depts <- c("UNDC")
  valid_depts   <- unique(subj_dept_map$dept_code)
  catalog_depts <- unique(program_map$dept_code[!is.na(program_map$dept_code)])
  orphans       <- setdiff(catalog_depts, c(valid_depts, known_pseudo_depts))
  expect_equal(orphans, character(0),
               info = paste("program_map dept_codes not in subj_dept_map:", paste(orphans, collapse = ", ")))
})

test_that("all mapped college_codes in program_map exist in subj_dept_map", {
  skip_if_no_catalogs()
  valid_colleges   <- unique(subj_dept_map$college_code)
  catalog_colleges <- unique(program_map$college_code[!is.na(program_map$college_code)])
  orphans          <- setdiff(catalog_colleges, valid_colleges)
  expect_equal(orphans, character(0),
               info = paste("program_map college_codes not in subj_dept_map:", paste(orphans, collapse = ", ")))
})

# =============================================================================
# 3b. No numeric dept_codes in catalogs (Banner internal org ID leak prevention)
# =============================================================================

test_that("subj_dept_map has no numeric dept_codes", {
  skip_if_no_catalogs()
  numeric_depts <- subj_dept_map$dept_code[grepl("^[0-9]+$", subj_dept_map$dept_code)]
  expect_equal(length(numeric_depts), 0L,
               info = paste("Numeric dept_codes found:", paste(numeric_depts, collapse = ", ")))
})

test_that("program_map has no numeric dept_codes or major_codes", {
  skip_if_no_catalogs()
  numeric_dept <- program_map$dept_code[!is.na(program_map$dept_code) & grepl("^[0-9]+$", program_map$dept_code)]
  expect_equal(length(numeric_dept), 0L,
               info = paste("Numeric dept_codes:", paste(numeric_dept, collapse = ", ")))
  numeric_prog <- program_map$major_code[grepl("^[0-9]+$", program_map$major_code)]
  expect_equal(length(numeric_prog), 0L,
               info = paste("Numeric major_codes:", paste(numeric_prog, collapse = ", ")))
})

# =============================================================================
# 4. Lookup vector structure
# =============================================================================

test_that("subj_to_dept is a named character vector", {
  skip_if_no_lookups()
  expect_type(subj_to_dept, "character")
  expect_false(is.null(names(subj_to_dept)))
  expect_true(length(subj_to_dept) >= 200,
              info = paste("Expected >=200 entries, found", length(subj_to_dept)))
})

test_that("major_college_to_dept is a named character vector with compound keys", {
  skip_if_no_lookups()
  expect_type(major_college_to_dept, "character")
  expect_false(is.null(names(major_college_to_dept)))
  expect_false(any(is.na(major_college_to_dept)))
  expect_false(any(is.na(names(major_college_to_dept))))
  expect_true(all(nzchar(names(major_college_to_dept))))
  # Keys should contain ":"
  expect_true(all(grepl(":", names(major_college_to_dept))),
              info = "All major_college_to_dept keys should be in 'major_code:college_code' format")
  expect_true(length(major_college_to_dept) >= 300,
              info = paste("Expected >=300 entries, found", length(major_college_to_dept)))
})

test_that("major_to_dept is a named character vector", {
  skip_if_no_lookups()
  expect_type(major_to_dept, "character")
  expect_false(is.null(names(major_to_dept)))
  expect_false(any(is.na(major_to_dept)))
  expect_false(any(is.na(names(major_to_dept))))
  expect_true(all(nzchar(names(major_to_dept))))
  expect_true(length(major_to_dept) >= 300,
              info = paste("Expected >=300 entries, found", length(major_to_dept)))
})

test_that("Health Administration maps to the PADM reporting unit", {
  skip_if_no_catalogs()
  skip_if_no_lookups()

  hlad_program <- program_map |>
    filter(program_code == "MHA-HLAD")

  expect_equal(nrow(hlad_program), 1L)
  expect_equal(unname(hlad_program$major_code), "HLAD")
  expect_equal(unname(hlad_program$dept_code), "PADM")
  expect_equal(unname(major_to_dept["HLAD"]), "PADM")
  expect_equal(unname(major_college_to_dept["HLAD:AS"]), "PADM")
  expect_false("MHA-HLAD" %in% allowed_unmapped_program_codes)
})

# GitHub #100: East Asian Studies (EAST) had no map row and fell to the identity
# fallback, reporting its majors under a nonexistent EAST department instead of
# LCL. Its pre-major FEAS already resolved to LCL.
test_that("East Asian Studies maps to LCL, not to a department named after itself", {
  skip_if_no_catalogs()
  skip_if_no_lookups()

  east <- program_map |> filter(program_code == "BA-EAST-AS")
  expect_equal(nrow(east), 1L)
  expect_equal(unname(east$dept_code), "LCL")
  expect_equal(unname(major_to_dept["EAST"]), "LCL")
  expect_equal(unname(major_to_dept["FEAS"]), "LCL")
  expect_false("BA-EAST-AS" %in% allowed_unmapped_program_codes)
})

# GitHub #100: Comparative Literature & Cultural Studies is LCL's (BA, MA, and
# pre-major FCLC); it had been mapped to ENGL.
test_that("Comparative Literature maps to LCL, with its pre-major", {
  skip_if_no_catalogs()
  skip_if_no_lookups()

  clcs <- program_map |> filter(program_code %in% c("BA-CLCS-AS", "MA-CLCS", "BA-FCLC-AS"))
  expect_equal(nrow(clcs), 3L)
  expect_true(all(clcs$dept_code == "LCL"))
  expect_equal(unname(major_to_dept["CLCS"]), "LCL")
})

test_that("program_map lookup issues are surfaced without polluting lookup vectors", {
  skip_if_no_catalogs()
  skip_if_no_lookups()
  expect_true(exists("allowed_unmapped_program_codes"))
  expect_true(exists("cedar_mapping_issues"))

  invalid_for_lookup <- program_map |>
    filter(
      is.na(major_code) | !nzchar(major_code) |
        is.na(college_code) | !nzchar(college_code) |
        is.na(dept_code) | !nzchar(dept_code)
    )

  unexpected_unmapped <- program_map |>
    filter(
      !(is.na(major_code) | !nzchar(major_code) |
          is.na(college_code) | !nzchar(college_code)),
      is.na(dept_code) | !nzchar(dept_code)
    ) |>
    filter(!(program_code %in% allowed_unmapped_program_codes))

  expect_gte(nrow(cedar_mapping_issues), nrow(invalid_for_lookup))
  expect_true(all(invalid_for_lookup$program_code %in% cedar_mapping_issues$program_code))
  expect_true(all(unexpected_unmapped$program_code %in%
                    cedar_mapping_issues$program_code[cedar_mapping_issues$review_status == "needs_review"]))
})

test_that("dept_code_to_name is a named character vector", {
  skip_if_no_lookups()
  expect_type(dept_code_to_name, "character")
  expect_false(is.null(names(dept_code_to_name)))
})

test_that("college_name_to_code is a named character vector", {
  skip_if_no_lookups()
  expect_type(college_name_to_code, "character")
  expect_false(is.null(names(college_name_to_code)))
})

# =============================================================================
# 5. Lookup spot checks — known correct values
# =============================================================================

test_that("subj_to_dept returns correct dept for known subjects", {
  skip_if_no_lookups()
  expect_equal(unname(subj_to_dept["HIST"]),  "HIST")
  expect_equal(unname(subj_to_dept["MATH"]),  "MATH")
  expect_equal(unname(subj_to_dept["ARBC"]),  "LCL",
               info = "Arabic subject belongs to LCL dept")
  expect_equal(unname(subj_to_dept["ANTH"]),  "ANTH")
  expect_equal(unname(subj_to_dept["BIOL"]),  "BIOL")
  expect_equal(unname(subj_to_dept["CHEM"]),  "CHEM")
})

test_that("dept_code_to_name returns human-readable names for known depts", {
  skip_if_no_lookups()
  expect_equal(unname(dept_code_to_name["HIST"]), "History")
  expect_equal(unname(dept_code_to_name["MATH"]), "Mathematics and Statistics")
  expect_equal(unname(dept_code_to_name["ANTH"]), "Anthropology")
})

test_that("college_name_to_code maps college names to codes", {
  skip_if_no_lookups()
  expect_equal(unname(college_name_to_code["Associate Degree"]),        "AD")
  expect_equal(unname(college_name_to_code["College of Arts and Sciences"]), "AS")
})

test_that("major_to_dept returns main-campus dept for ambiguous program codes", {
  skip_if_no_lookups()
  # CRIM exists in AS (→ SOCI) and AD (→ CJUS); main campus (AS) wins simple lookup
  expect_equal(unname(major_to_dept["CRIM"]), "SOCI",
               info = "Simple major_to_dept uses main-campus-first ordering")
  expect_equal(unname(major_to_dept["HIST"]), "HIST")
  expect_equal(unname(major_to_dept["MATH"]), "MATH")
})

# =============================================================================
# 6. Branch campus disambiguation via major_college_to_dept (compound key)
# =============================================================================

test_that("a pre-major resolves to the department it leads to, not its own code", {
  skip_if_no_lookups()
  # FCS is Banner's pre-Computer-Science code AND the department code for Family
  # and Child Studies. A direct lookup on the code finds a real department -- the
  # wrong one -- so 6,121 pre-CS students were filed under Family and Child
  # Studies with nothing to notice. The canonical target has to win.
  expect_equal(unname(premaj_canon[["FCS"]]), "CS")
  expect_equal(unname(major_to_dept["FCS"]), "CS",
               info = "pre-CS students belong to Computer Science")
  # And the actual Family and Child Studies programs are untouched: they use
  # FCST and FFCS, which must still resolve to the FCS department.
  expect_equal(unname(major_to_dept["FCST"]), "FCS")
  expect_equal(unname(dept_code_to_name["FCS"]), "Family and Child Studies")
})

test_that("major_college_to_dept disambiguates CRIM: AS→SOCI, AD→CJUS", {
  skip_if_no_lookups()
  expect_equal(unname(major_college_to_dept["CRIM:AS"]), "SOCI",
               info = "Main-campus CRIM belongs to Sociology dept")
  expect_equal(unname(major_college_to_dept["CRIM:AD"]), "CJUS",
               info = "Branch campus CRIM belongs to Criminal Justice dept")
})

test_that("major_college_to_dept disambiguates CS: EN→CS, AD→CS", {
  skip_if_no_lookups()
  # CS in Engineering and in branch campuses — both map to CS dept
  expect_equal(unname(major_college_to_dept["CS:EN"]), "CS")
  expect_equal(unname(major_college_to_dept["CS:AD"]), "CS")
})

test_that("major_college_to_dept has correct mappings for other branch campus programs", {
  skip_if_no_lookups()
  expect_equal(unname(major_college_to_dept["EDUC:EH"]), "EDUC",
               info = "Education in Education college → EDUC dept")
  expect_equal(unname(major_college_to_dept["MATH:AS"]), "MATH")
  expect_equal(unname(major_college_to_dept["MATH:AD"]), "MATH")
  expect_equal(unname(major_college_to_dept["ENGL:AS"]), "ENGL")
  expect_equal(unname(major_college_to_dept["ECED:AD"]), "ECED",
               info = "Early Childhood Ed only at branch campuses")
  expect_equal(unname(major_college_to_dept["AASN:AD"]), "NURS",
               info = "Associate of Applied Science in Nursing → NURS dept")
  expect_equal(unname(major_college_to_dept["BADM:AD"]), "BUSA",
               info = "Branch campus BADM → Business Admin dept")
})

test_that("major_college_to_dept lookup returns NA for unknown keys (not an error)", {
  skip_if_no_lookups()
  result <- major_college_to_dept["XXXUNKNOWN:ZZ"]
  expect_true(is.na(result),
              info = "Unknown compound key should return NA, not error")
})

# =============================================================================
# 7. set_payload returns correct prog_codes via major_to_dept
# =============================================================================

test_that("set_payload returns prog_codes from major_to_dept for known depts", {
  skip_if_no_catalogs()
  skip_if_no_lookups()
  if (!exists("set_payload")) skip("set_payload not loaded")
  if (!exists("cedar_report_start_term")) skip("cedar config not loaded")

  d <- set_payload("HIST")
  expect_true("HIST" %in% d$prog_codes,
              info = "HIST dept should include HIST program code")
  expect_false(any(is.na(d$prog_codes)))
  expect_true(all(nzchar(d$prog_codes)))

  d_math <- set_payload("MATH")
  expect_true("MATH" %in% d_math$prog_codes)

  d_padm <- set_payload("PADM")
  expect_true("HLAD" %in% d_padm$prog_codes,
              info = "PADM dept should include the Health Administration program code")

  d_lcl <- set_payload("LCL")
  # LCL dept should include multiple foreign language program codes
  expect_true(length(d_lcl$prog_codes) > 1,
              info = "LCL dept should have multiple program codes")
})

test_that("set_payload prog_focus restricts to single program code", {
  skip_if_no_catalogs()
  skip_if_no_lookups()
  if (!exists("set_payload")) skip("set_payload not loaded")
  if (!exists("cedar_report_start_term")) skip("cedar config not loaded")

  d <- set_payload("HIST", prog_focus = "HIST")
  expect_equal(d$prog_codes, "HIST")
  expect_equal(d$prog_focus, "HIST")
})
