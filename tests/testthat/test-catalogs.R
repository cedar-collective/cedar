# Tests for the institution mapping files and the lookups built from them
# Covers: institution_files.R, subj_dept_map.R, catalog_lookups.R
#
# These tests verify:
#   1. subj_dept_map structure, and the mapping files' validation
#   2. Program and course units resolved from the files, including the
#      decided facts that must not drift (HLAD -> PADM, CRIM by college, ...)
#   3. Lookup vector contents and known spot-check values
#   4. dept-trends.R uses major_to_dept for its reverse lookup
# program_map.qs and the lists that fed it were retired at ADR-002 Stage 4.

context("Catalog Architecture")

# =============================================================================
# Prerequisites
# =============================================================================

skip_if_no_catalogs <- function() {
  if (!exists("subj_dept_map") || !exists("cedar_institution_files")) {
    skip("subj_dept_map / cedar_institution_files not loaded — run load_funcs() first")
  }
}

skip_if_no_lookups <- function() {
  if (!exists("major_to_dept") || !exists("subj_to_dept")) {
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
program_rows <- function(program_code, unit_code = "HIST", in_college = "",
                         college_code = "", is_pre_major = "FALSE", leads_to = "",
                         basis = "decided", status = "confirmed") {
  data.frame(program_code, in_college, program_name = program_code, unit_code,
             college_code, is_pre_major, leads_to, basis, status, evidence = "", notes = "")
}

unm_settings <- data.frame(
  setting = c("mapping_files_url", "source_files_url"),
  value   = c("https://github.com/org/repo/blob/main/institution/x",
              "https://github.com/org/repo/blob/main"))

# Scaffolding: subjects.csv rows, defaults filled in.
subject_rows <- function(subject_code, unit_code = "HIST", in_college = "AS", in_level = "",
                         college_code = "", status = "confirmed") {
  data.frame(subject_code, in_college, in_level, unit_code, college_code, status,
             evidence = "", notes = "")
}

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
  colleges = data.frame(college_code = c("AS", "AD"), college_name = c("Arts and Sciences", "Branch"),
                        source_names = c("", "Branch Campuses|ED")),
  units    = data.frame(unit_code = c("HIST", "SOCI", "CJUS"),
                        unit_name = c("History", "Sociology", "Criminal Justice"),
                        college_code = c("AS", "AS", "AD"), kind = "department", notes = ""),
  subjects = subject_rows("HIST")
)

test_that("UNM mapping files load into the subject-unit-college table", {
  files <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "unm"))
  built <- build_subj_dept_map(files)
  expect_equal(nrow(built), sum(files$subjects$status == "confirmed"))
  expect_false(anyNA(built$dept_name))
  expect_false(anyNA(built$college_name))
  # Branch campuses reuse subject codes for different units: the key is
  # subject AND college, and the same subject may resolve differently.
  hled <- built[built$subject_code == "HLED", ]
  expect_gt(length(unique(hled$dept_code)), 1)
})

test_that("institution files are found from the base load_funcs() was given", {
  # ISSUES.md I14: production's config.R sets a global cedar_base_dir to the
  # host path, which does not exist inside the container. While a list file is
  # sourced, that global environment is a calling frame, so a lookup by name
  # found it before load_funcs()'s own argument. The recorded base must win.
  withr::local_options(cedar.base_dir = normalizePath(cedar_base_dir))
  frame_with_host_path <- list2env(list(cedar_base_dir = "/host/path/not/in/the/container"))
  dir <- evalq(cedar_institution_dir(), envir = frame_with_host_path)
  expect_equal(dir, file.path(normalizePath(cedar_base_dir), "institution", cedar_institution_id()))
})

test_that("the mapping validator reports every problem at once", {
  # Scaffolding: a three-row institution with three deliberate faults.
  dir <- write_mapping_dir(
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences", source_names = ""),
    units    = data.frame(unit_code = c("HIST", "HIST"), unit_name = c("History", "History"),
                          college_code = "AS", kind = "department", notes = ""),
    subjects = subject_rows(c("HIST", "ANTH"), unit_code = c("HIST", "ANTH"), in_college = c("AS", "XX"))
  )
  err <- tryCatch(read_institution_mappings(dir), error = conditionMessage)
  expect_match(err, "duplicate unit_code HIST")
  expect_match(err, "unit_code not in units.csv: ANTH")
  expect_match(err, "in_college not in colleges.csv: XX")
})

test_that("a mapping file with the wrong columns, or an unknown institution, stops", {
  dir <- write_mapping_dir(
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences", source_names = ""),
    units    = data.frame(code = "HIST", name = "History"),
    subjects = subject_rows("HIST")
  )
  expect_error(read_institution_mappings(dir), "units.csv must have columns unit_code, unit_name, college_code, kind, notes")
  expect_error(cedar_institution_dir(cedar_base_dir, "no-such-place"), "No mapping files for institution 'no-such-place'")
  withr::with_envvar(c(CEDAR_INSTITUTION = "../etc"),
                     expect_error(cedar_institution_id(), "lowercase directory name"))
})

test_that("UNM programs.csv and source_departments.csv load and validate", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  files <- read_institution_mappings(dir)
  expect_gt(sum(files$programs$status == "confirmed"), 0)
  # Every unit has a home college: programs reach their college through it.
  expect_equal(files$units$unit_code[!nzchar(files$units$college_code)], character(0))
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
    program_rows("LEAD", leads_to = "HIST"),                        # target on a non-pre-major
    program_rows("SOCI", unit_code = "SOCI"),
    program_rows("FSOC", is_pre_major = "TRUE", leads_to = "SOCI"), # target in another unit
    program_rows("FSOX", is_pre_major = "TRUE", leads_to = "SOCI",  # ...but only once confirmed
                 basis = "course_taking", status = "proposed")
  )
  dir <- do.call(write_mapping_dir, c(one_unit, list(programs = programs)))
  err <- tryCatch(read_institution_mappings(dir), error = conditionMessage)
  expect_match(err, "duplicate program/in_college HIST / ")
  expect_match(err, "leads_to is not a program_code: NOPE")
  expect_match(err, "unit_code not in units.csv: ANTH")
  expect_match(err, "confirmed with no unit_code \\(use basis no_unit if nothing owns it\\): NOND")
  expect_match(err, "basis unresolved must be a proposed row with no unit_code: GUES")
  expect_match(err, "unknown basis vibes")
  expect_match(err, "unknown status maybe")
  expect_match(err, "leads_to set on a row that is not a pre-major: LEAD")
  expect_match(err, "pre-major in a different unit from its leads_to target \\(a department code for a program code\\?\\): FSOC \\(HIST\\) -> SOCI \\(SOCI\\)")
  expect_false(grepl("FSOX", err))
})

test_that("settings.csv must name a GitHub location for the mapping files", {
  bad <- unm_settings; bad$value[1] <- "my laptop"
  dir <- do.call(write_mapping_dir, c(one_unit, list(settings = bad)))
  expect_error(read_institution_mappings(dir), "mapping_files_url must be a GitHub blob URL")
  dir <- do.call(write_mapping_dir, c(one_unit, list(settings = unm_settings[1, ])))
  expect_error(read_institution_mappings(dir), "missing setting source_files_url")

  files <- read_institution_mappings(do.call(write_mapping_dir, one_unit))
  expect_equal(mapping_file_url(files, "programs"),
               "https://github.com/org/repo/edit/main/institution/x/programs.csv")
  expect_equal(source_file_url(files, "R/lists/mappings.R"),
               "https://github.com/org/repo/blob/main/R/lists/mappings.R")
})

test_that("a program's college: its own, else its target's, else its unit's", {
  # Scaffolding. BCHM is owned by HIST (college AS) but sets its own college
  # AD, as UNM's Biochemistry is taught by Medicine but its majors are in Arts
  # & Sciences. Its pre-major FBCH sets none, so it follows BCHM to AD, not its
  # unit's AS. CRIM resolves its unit, and so its college, per in_college row.
  programs <- rbind(
    program_rows("CRIM", unit_code = "SOCI"),
    program_rows("CRIM", unit_code = "CJUS", in_college = "AD", basis = "override"),
    program_rows("BCHM", college_code = "AD"),
    program_rows("FBCH", is_pre_major = "TRUE", leads_to = "BCHM"),
    program_rows("GUES", unit_code = "", basis = "unresolved", status = "proposed"),
    # Nothing owns these; UNDC names a college (as UNM's Undecided names UC),
    # NOND names none.
    program_rows("UNDC", unit_code = "", basis = "no_unit", college_code = "AS"),
    program_rows("NOND", unit_code = "", basis = "no_unit")
  )
  files <- read_institution_mappings(do.call(write_mapping_dir, c(one_unit, list(programs = programs))))
  expect_equal(
    resolve_program_colleges(c("CRIM", "CRIM", "BCHM", "FBCH", "GUES", "NOPE", "UNDC", "NOND"),
                             c("AS",   "AD",   "AS",   "AS",   "AS",   "AS",   "AD",   "AD"), files),
    c("AS", "AD", "AD", "AD", NA, NA, "AS", NA))
  # A no_unit row names a college, never a unit.
  expect_equal(resolve_program_units(c("UNDC", "NOND"), c("AD", "AD"), files$programs),
               c(NA_character_, NA_character_))
  expect_equal(college_names(c("AD", NA, "AS"), files), c("Branch", NA, "Arts and Sciences"))
})

test_that("source college values translate through colleges.csv, one college each", {
  files <- read_institution_mappings(do.call(write_mapping_dir, one_unit))
  expect_equal(translate_source_college(c("ED", "Branch Campuses", "Arts and Sciences", "AS", "Nope"), files),
               c("AD", "AD", "AS", "AS", NA))
  bad <- one_unit; bad$colleges$source_names[1] <- "Branch"
  expect_error(read_institution_mappings(do.call(write_mapping_dir, bad)),
               "colleges.csv: names more than one college: Branch")
  settings <- rbind(unm_settings, data.frame(setting = "colour", value = "blue"))
  expect_error(read_institution_mappings(do.call(write_mapping_dir, c(one_unit, list(settings = settings)))),
               "unknown setting colour")
  settings <- rbind(unm_settings, data.frame(setting = "source_values_without_college", value = "Non-Degree"))
  files <- read_institution_mappings(do.call(write_mapping_dir, c(one_unit, list(settings = settings))))
  expect_equal(college_value_is_known(c("Non-Degree", "ED", "Nope"), files), c(TRUE, TRUE, FALSE))
})

test_that("a proposed subject maps nothing until it is confirmed", {
  # Scaffolding: HIST is confirmed; ANTH is the assistant's proposal, with a
  # suggested unit; GEX is a proposal nothing settled; a confirmed row with no
  # unit is refused.
  subjects <- rbind(one_unit$subjects,
    subject_rows(c("ANTH", "GEX"), unit_code = c("SOCI", ""), status = "proposed"))
  with_subjects <- one_unit; with_subjects$subjects <- subjects
  files <- read_institution_mappings(do.call(write_mapping_dir, with_subjects))
  expect_equal(build_subj_dept_map(files)$subject_code, "HIST")
  expect_equal(mapping_file_line(files, "subjects", c("GEX", "HIST", "NOPE")), c(4L, 2L, NA))
  with_subjects$subjects$status[3] <- "confirmed"
  expect_error(read_institution_mappings(do.call(write_mapping_dir, with_subjects)),
               "subjects.csv: confirmed with no unit_code: GEX")
})

test_that("a course's unit and college come from the most specific subject row", {
  # Scaffolding mirroring UNM's GLNS: one unit (SOCI here, home college AS)
  # whose graduate courses keep the unit's college but whose other courses are
  # credited to AD -- a director sees one unit, each college its own credits.
  # HIST has a row for section college AS, and one for graduate courses in any
  # college: a graduate HIST course in AS takes the college row (subject +
  # college beats subject + level). ANTH has no row at all. A section college
  # is first translated through colleges.csv: ED is a former name of AD here,
  # as UNM's ED is of EH, so an ED section takes the AD row.
  subjects <- rbind(
    subject_rows("HIST"),
    subject_rows("HIST", unit_code = "SOCI", in_college = "", in_level = "grad"),
    subject_rows("GLNS", unit_code = "SOCI", in_college = "", in_level = "grad"),
    subject_rows("GLNS", unit_code = "SOCI", in_college = "", college_code = "AD"),
    subject_rows("GLNS", unit_code = "CJUS", in_college = "AD", in_level = "lower"))
  with_subjects <- one_unit; with_subjects$subjects <- subjects
  files <- read_institution_mappings(do.call(write_mapping_dir, with_subjects))
  got <- resolve_course_units(
    subject = c("GLNS", "GLNS",  "GLNS", "GLNS",  "HIST",  "HIST", "HIST", "HIST", "ANTH",  "GLNS"),
    college = c("AS",   "AS",    "AD",   "AD",    "AS",    "AD",   "AS",   "AD",   "AS",    "ED"),
    level   = c("grad", "upper", "lower", "grad", "lower", "lower", "grad", "grad", "lower", "lower"),
    files = files)
  expect_equal(got$unit_code,    c("SOCI", "SOCI", "CJUS", "SOCI", "HIST", NA, "HIST", "SOCI", NA, "CJUS"))
  expect_equal(got$college_code, c("AS",   "AD",   "AD",   "AS",   "AS",   NA, "AS",   "AS",   NA, "AD"))
})

test_that("subject levels and unit kinds are checked", {
  bad <- one_unit
  bad$subjects <- rbind(subject_rows("HIST"), subject_rows("HIST", in_level = "senior"))
  bad$units$kind[1] <- "faculty"
  err <- tryCatch(read_institution_mappings(do.call(write_mapping_dir, bad)), error = conditionMessage)
  expect_match(err, "in_level must be lower, upper, grad: senior")
  expect_match(err, "units.csv: kind must be department, program, college: faculty")
})

test_that("program_line_url links a code to its every-college row's line", {
  # CRIM's college-specific row comes first in this file, on purpose: the link
  # must still land on the every-college row (line 4), not the first match.
  programs <- rbind(
    program_rows("CRIM", unit_code = "CJUS", in_college = "AD", basis = "override"),
    program_rows("HIST"),
    program_rows("CRIM", unit_code = "SOCI")
  )
  files <- read_institution_mappings(do.call(write_mapping_dir, c(one_unit, list(programs = programs))))
  base <- "https://github.com/org/repo/blob/main/institution/x/programs.csv?plain=1#L"
  expect_equal(program_line_url(files, c("CRIM", "HIST", "NOPE")),
               c(paste0(base, 4), paste0(base, 3), NA))
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
    program_rows("CRIM", unit_code = "CJUS", in_college = "AD", basis = "override"),
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

# =============================================================================
# 2. Program units from programs.csv -- decided facts that must not drift
# =============================================================================
# program_map.qs was retired at ADR-002 Stage 4. These read the files through
# resolve_program_units(), the function the transform uses.

unm_programs <- function() {
  read_institution_mappings(cedar_institution_dir(cedar_base_dir, "unm"))$programs
}
unit_of <- function(code, college = rep("", length(code))) {
  resolve_program_units(code, college, unm_programs())
}

test_that("decided program units hold in programs.csv", {
  expect_equal(unit_of("HLAD"), "PADM")                      # Health Administration
  # GitHub #100: East Asian Studies and its pre-major, and Comparative
  # Literature with its pre-major, are LCL's.
  expect_equal(unit_of(c("EAST", "FEAS", "CLCS", "FCLC")), rep("LCL", 4))
  # FCS is Banner's pre-Computer-Science code AND the Family and Child Studies
  # department code (ISSUES.md I9): the program goes to CS; FCS's own
  # programs, FCST and its pre-major FFCS, to the department.
  expect_equal(unit_of("FCS"), "CS")
  expect_equal(unit_of(c("FCST", "FFCS")), c("FCS", "FCS"))
  expect_equal(unname(dept_code_to_name["FCS"]), "Family and Child Studies")
})

test_that("a college-specific row wins in its college: the branch campuses", {
  expect_equal(unit_of(c("CRIM", "CRIM"), c("AS", "AD")), c("SOCI", "CJUS"))
  expect_equal(unit_of(c("BADM", "BADM"), c("MG", "AD")), c("MGMT", "BUSA"))
  expect_equal(unit_of(c("CS", "CS"), c("EN", "AD")), c("CS", "CS"))
  expect_equal(unit_of(c("EDUC", "MATH", "MATH", "ENGL", "ECED", "AASN"),
                       c("EH",   "AS",   "AD",   "AS",   "AD",   "AD")),
               c("EDUC", "MATH", "MATH", "ENGL", "ECED", "NURS"))
  expect_true(is.na(unit_of("XXXUNKNOWN", "ZZ")))
})

test_that("major_to_dept and premajor_leads_to are read from programs.csv", {
  skip_if_no_lookups()
  pr <- unm_programs()
  every <- pr[pr$status == "confirmed" & !nzchar(pr$in_college) & nzchar(pr$unit_code), ]
  expect_equal(unname(major_to_dept[every$program_code]), every$unit_code)
  expect_setequal(names(major_to_dept), every$program_code)
  # The every-college row: the branch campus's CRIM row is not in it.
  expect_equal(unname(major_to_dept["CRIM"]), "SOCI")
  pre <- pr[pr$is_pre_major == "TRUE" & nzchar(pr$leads_to) & !nzchar(pr$in_college), ]
  expect_equal(unname(premajor_leads_to[pre$program_code]), pre$leads_to)
  expect_equal(unname(premajor_leads_to["FFCS"]), "FCST")
})

test_that("subj_dept_map has no numeric dept_codes", {
  skip_if_no_catalogs()
  numeric_depts <- subj_dept_map$dept_code[grepl("^[0-9]+$", subj_dept_map$dept_code)]
  expect_equal(length(numeric_depts), 0L,
               info = paste("Numeric dept_codes found:", paste(numeric_depts, collapse = ", ")))
})

# =============================================================================
# 3. Lookup vector structure and spot checks
# =============================================================================

test_that("subj_to_dept is a named character vector", {
  skip_if_no_lookups()
  expect_type(subj_to_dept, "character")
  expect_false(is.null(names(subj_to_dept)))
  expect_true(length(subj_to_dept) >= 200,
              info = paste("Expected >=200 entries, found", length(subj_to_dept)))
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

# =============================================================================
# 4. set_payload returns correct prog_codes via major_to_dept
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
