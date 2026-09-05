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
