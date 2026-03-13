# Tests for catalog-based lookup architecture
# Covers: unit_catalog.R, program_catalog.R, catalog_lookups.R
#
# These tests verify:
#   1. Catalog tibble structure (required columns, no NAs in key fields)
#   2. Cross-catalog integrity (every dept/college in program_catalog exists in unit_catalog)
#   3. Lookup vector contents and known spot-check values
#   4. Branch campus disambiguation via compound key (pc_dept_lu)
#   5. dept-report.R uses program_catalog, not prgm_to_dept_map, for reverse lookup

context("Catalog Architecture")

# =============================================================================
# Prerequisites
# =============================================================================

skip_if_no_catalogs <- function() {
  if (!exists("unit_catalog") || !exists("program_catalog")) {
    skip("unit_catalog / program_catalog not loaded — run load_funcs() first")
  }
}

skip_if_no_lookups <- function() {
  if (!exists("pc_dept_lu") || !exists("subj_to_dept_map")) {
    skip("catalog_lookups.R vectors not available")
  }
}

# =============================================================================
# 1. unit_catalog structure
# =============================================================================

test_that("unit_catalog has required columns", {
  skip_if_no_catalogs()
  required <- c("college_code", "college_name", "dept_code", "dept_name", "subject_code")
  missing  <- setdiff(required, colnames(unit_catalog))
  expect_equal(missing, character(0),
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("unit_catalog has no NA in key columns", {
  skip_if_no_catalogs()
  for (col in c("college_code", "dept_code", "subject_code")) {
    n_na <- sum(is.na(unit_catalog[[col]]))
    expect_equal(n_na, 0L,
                 info = paste("unit_catalog$", col, "has", n_na, "NA values"))
  }
})

test_that("unit_catalog subject_codes are unique within each college", {
  skip_if_no_catalogs()
  # Subject codes can appear in multiple colleges (e.g., ARTS in FA and AD).
  # Within a single college, each subject code should map to exactly one dept.
  conflicts <- unit_catalog |>
    dplyr::group_by(college_code, subject_code) |>
    dplyr::summarise(n_depts = dplyr::n_distinct(dept_code), .groups = "drop") |>
    dplyr::filter(n_depts > 1)
  expect_equal(nrow(conflicts), 0L,
               info = paste("subject_code maps to multiple depts within same college:",
                            paste(paste(conflicts$college_code, conflicts$subject_code, sep=":"),
                                  collapse = ", ")))
})

test_that("unit_catalog contains expected colleges", {
  skip_if_no_catalogs()
  for (code in c("AS", "AD", "EN", "EH", "FA", "MG", "NU", "PA", "ME")) {
    expect_true(code %in% unit_catalog$college_code,
                info = paste("College code missing from unit_catalog:", code))
  }
})

test_that("unit_catalog AD section includes required branch campus depts", {
  skip_if_no_catalogs()
  ad_depts <- unit_catalog$dept_code[unit_catalog$college_code == "AD"]
  # NURS is NOT here — branch campus NURS programs map to the NU:NURS dept entry
  for (dept in c("BUSA", "CJUS", "EDUC", "ECED", "APTE", "ASPE", "LART")) {
    expect_true(dept %in% ad_depts,
                info = paste("Branch campus dept missing from unit_catalog AD:", dept))
  }
})

# =============================================================================
# 2. program_catalog structure
# =============================================================================

test_that("program_catalog has required columns", {
  skip_if_no_catalogs()
  required <- c("college_code", "dept_code", "program_code",
                "degree_abbr", "degree_level", "program_type")
  missing  <- setdiff(required, colnames(program_catalog))
  expect_equal(missing, character(0),
               info = paste("Missing columns:", paste(missing, collapse = ", ")))
})

test_that("program_catalog has no NA in key columns", {
  skip_if_no_catalogs()
  for (col in c("college_code", "dept_code", "program_code")) {
    n_na <- sum(is.na(program_catalog[[col]]))
    expect_equal(n_na, 0L,
                 info = paste("program_catalog$", col, "has", n_na, "NA values"))
  }
})

test_that("each (program_code, college_code) maps to exactly one dept_code", {
  skip_if_no_catalogs()
  # A program can have multiple degree types (BA, MA, PhD) in the same college,
  # but they must all belong to the same dept. This is the invariant pc_dept_lu relies on.
  conflicts <- program_catalog |>
    dplyr::group_by(program_code, college_code) |>
    dplyr::summarise(n_depts = dplyr::n_distinct(dept_code), .groups = "drop") |>
    dplyr::filter(n_depts > 1)
  expect_equal(nrow(conflicts), 0L,
               info = paste("program:college → multiple depts:",
                            paste(paste(conflicts$program_code, conflicts$college_code, sep=":"),
                                  collapse = ", ")))
})

test_that("program_catalog contains branch campus (AD) programs", {
  skip_if_no_catalogs()
  ad_rows <- program_catalog[program_catalog$college_code == "AD", ]
  expect_true(nrow(ad_rows) >= 40,
              info = paste("Expected >=40 AD rows, found", nrow(ad_rows)))
  # Spot check specific programs
  ad_programs <- ad_rows$program_code
  for (prog in c("CRIM", "CRJS", "ECED", "AASN", "BADM", "NURS")) {
    expect_true(prog %in% ad_programs,
                info = paste("Branch campus program missing:", prog))
  }
})

# =============================================================================
# 3. Cross-catalog integrity
# =============================================================================

test_that("all dept_codes in program_catalog exist in unit_catalog", {
  skip_if_no_catalogs()
  # UNDC is a pseudo-dept for undeclared/non-degree students — no unit_catalog entry by design
  known_pseudo_depts <- c("UNDC")
  valid_depts   <- unique(unit_catalog$dept_code)
  catalog_depts <- unique(program_catalog$dept_code)
  orphans       <- setdiff(catalog_depts, c(valid_depts, known_pseudo_depts))
  expect_equal(orphans, character(0),
               info = paste("program_catalog dept_codes not in unit_catalog:", paste(orphans, collapse = ", ")))
})

test_that("all college_codes in program_catalog exist in unit_catalog", {
  skip_if_no_catalogs()
  valid_colleges   <- unique(unit_catalog$college_code)
  catalog_colleges <- unique(program_catalog$college_code)
  orphans          <- setdiff(catalog_colleges, valid_colleges)
  expect_equal(orphans, character(0),
               info = paste("program_catalog college_codes not in unit_catalog:", paste(orphans, collapse = ", ")))
})

# =============================================================================
# 3b. No numeric dept_codes in catalogs (Banner internal org ID leak prevention)
# =============================================================================

test_that("unit_catalog has no numeric dept_codes", {
  skip_if_no_catalogs()
  numeric_depts <- unit_catalog$dept_code[grepl("^[0-9]+$", unit_catalog$dept_code)]
  expect_equal(length(numeric_depts), 0L,
               info = paste("Numeric dept_codes found:", paste(numeric_depts, collapse = ", ")))
})

test_that("program_catalog has no numeric dept_codes or program_codes", {
  skip_if_no_catalogs()
  numeric_dept <- program_catalog$dept_code[grepl("^[0-9]+$", program_catalog$dept_code)]
  expect_equal(length(numeric_dept), 0L,
               info = paste("Numeric dept_codes:", paste(numeric_dept, collapse = ", ")))
  numeric_prog <- program_catalog$program_code[grepl("^[0-9]+$", program_catalog$program_code)]
  expect_equal(length(numeric_prog), 0L,
               info = paste("Numeric program_codes:", paste(numeric_prog, collapse = ", ")))
})

# =============================================================================
# 4. Lookup vector structure
# =============================================================================

test_that("subj_to_dept_map is a named character vector", {
  skip_if_no_lookups()
  expect_type(subj_to_dept_map, "character")
  expect_false(is.null(names(subj_to_dept_map)))
  expect_true(length(subj_to_dept_map) >= 200,
              info = paste("Expected >=200 entries, found", length(subj_to_dept_map)))
})

test_that("pc_dept_lu is a named character vector with compound keys", {
  skip_if_no_lookups()
  expect_type(pc_dept_lu, "character")
  expect_false(is.null(names(pc_dept_lu)))
  # Keys should contain ":"
  expect_true(all(grepl(":", names(pc_dept_lu))),
              info = "All pc_dept_lu keys should be in 'program_code:college_code' format")
  expect_true(length(pc_dept_lu) >= 300,
              info = paste("Expected >=300 entries, found", length(pc_dept_lu)))
})

test_that("prgm_to_dept_map is a named character vector", {
  skip_if_no_lookups()
  expect_type(prgm_to_dept_map, "character")
  expect_false(is.null(names(prgm_to_dept_map)))
  expect_true(length(prgm_to_dept_map) >= 300,
              info = paste("Expected >=300 entries, found", length(prgm_to_dept_map)))
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

test_that("subj_to_dept_map returns correct dept for known subjects", {
  skip_if_no_lookups()
  expect_equal(unname(subj_to_dept_map["HIST"]),  "HIST")
  expect_equal(unname(subj_to_dept_map["MATH"]),  "MATH")
  expect_equal(unname(subj_to_dept_map["ARBC"]),  "LCL",
               info = "Arabic subject belongs to LCL dept")
  expect_equal(unname(subj_to_dept_map["ANTH"]),  "ANTH")
  expect_equal(unname(subj_to_dept_map["BIOL"]),  "BIOL")
  expect_equal(unname(subj_to_dept_map["CHEM"]),  "CHEM")
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

test_that("prgm_to_dept_map returns main-campus dept for ambiguous program codes", {
  skip_if_no_lookups()
  # CRIM exists in AS (→ SOCI) and AD (→ CJUS); main campus (AS) wins simple lookup
  expect_equal(unname(prgm_to_dept_map["CRIM"]), "SOCI",
               info = "Simple prgm_to_dept_map uses main-campus-first ordering")
  expect_equal(unname(prgm_to_dept_map["HIST"]), "HIST")
  expect_equal(unname(prgm_to_dept_map["MATH"]), "MATH")
})

# =============================================================================
# 6. Branch campus disambiguation via pc_dept_lu (compound key)
# =============================================================================

test_that("pc_dept_lu disambiguates CRIM: AS→SOCI, AD→CJUS", {
  skip_if_no_lookups()
  expect_equal(unname(pc_dept_lu["CRIM:AS"]), "SOCI",
               info = "Main-campus CRIM belongs to Sociology dept")
  expect_equal(unname(pc_dept_lu["CRIM:AD"]), "CJUS",
               info = "Branch campus CRIM belongs to Criminal Justice dept")
})

test_that("pc_dept_lu disambiguates CS: EN→CS, AD→CS", {
  skip_if_no_lookups()
  # CS in Engineering and in branch campuses — both map to CS dept
  expect_equal(unname(pc_dept_lu["CS:EN"]), "CS")
  expect_equal(unname(pc_dept_lu["CS:AD"]), "CS")
})

test_that("pc_dept_lu has correct mappings for other branch campus programs", {
  skip_if_no_lookups()
  expect_equal(unname(pc_dept_lu["EDUC:EH"]), "EDUC",
               info = "Education in Education college → EDUC dept")
  expect_equal(unname(pc_dept_lu["MATH:AS"]), "MATH")
  expect_equal(unname(pc_dept_lu["MATH:AD"]), "MATH")
  expect_equal(unname(pc_dept_lu["ENGL:AS"]), "ENGL")
  expect_equal(unname(pc_dept_lu["ECED:AD"]), "ECED",
               info = "Early Childhood Ed only at branch campuses")
  expect_equal(unname(pc_dept_lu["AASN:AD"]), "NURS",
               info = "Associate of Applied Science in Nursing → NURS dept")
  expect_equal(unname(pc_dept_lu["BADM:AD"]), "BUSA",
               info = "Branch campus BADM → Business Admin dept")
})

test_that("pc_dept_lu lookup returns NA for unknown keys (not an error)", {
  skip_if_no_lookups()
  result <- pc_dept_lu["XXXUNKNOWN:ZZ"]
  expect_true(is.na(result),
              info = "Unknown compound key should return NA, not error")
})

# =============================================================================
# 7. dept-report.R uses program_catalog reverse lookup (not prgm_to_dept_map)
# =============================================================================

test_that("dept-report.R uses program_catalog for reverse dept → program lookup", {
  source_lines <- readLines(
    file.path(getwd(), "../../R/cones/dept-report.R")
  )
  # Should reference program_catalog$program_code
  expect_true(
    any(grepl("program_catalog\\$program_code", source_lines)),
    info = "dept-report.R should use program_catalog for prog_codes lookup"
  )
  # Should NOT use prgm_to_dept_map reverse lookup pattern
  expect_false(
    any(grepl("which\\(prgm_to_dept_map == dept_code\\)", source_lines)),
    info = "dept-report.R should not reverse-index prgm_to_dept_map (use program_catalog)"
  )
})

# =============================================================================
# 8. set_payload returns correct prog_codes via program_catalog
# =============================================================================

test_that("set_payload returns prog_codes from program_catalog for known depts", {
  skip_if_no_catalogs()
  skip_if_no_lookups()
  if (!exists("set_payload")) skip("set_payload not loaded")
  if (!exists("cedar_report_start_term")) skip("cedar config not loaded")

  d <- set_payload("HIST")
  expect_true("HIST" %in% d$prog_codes,
              info = "HIST dept should include HIST program code")

  d_math <- set_payload("MATH")
  expect_true("MATH" %in% d_math$prog_codes)

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
