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

test_that("the demo institution's files load and validate on their own", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  files <- read_institution_mappings(dir)
  expect_gt(nrow(files$programs), 0)
  expect_equal(files$units$unit_code[!nzchar(files$units$college_code)], character(0))
  expect_silent(validate_source_departments(read_institution_file("source_departments", dir), files$units))
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


# ---- Configuration files: campuses.csv and course_levels.csv ------------------

test_that("the campus constants are the institution's campuses.csv", {
  files <- validate_campuses(read_institution_file("campuses", cedar_institution_dir(cedar_base_dir, "unm")))
  expect_equal(CEDAR_CAMPUS_MAIN, files$campus_code[files$kind == "main"])
  expect_length(CEDAR_CAMPUS_MAIN, 1L)
  expect_equal(CEDAR_CAMPUS_ONLINE, files$campus_code[files$kind == "online"])
  expect_setequal(CEDAR_CAMPUS_BRANCH, files$campus_code[files$kind == "branch"])
  expect_equal(CEDAR_CAMPUS_DEFAULT, files$campus_code[files$default_scope])
  # A documented name labels the code; an undocumented one leaves the bare code.
  named <- files$campus_code[nzchar(files$campus_name)]
  expect_setequal(names(CEDAR_CAMPUS_LABELS), named)
  bare <- setdiff(files$campus_code, named)
  if (length(bare)) {
    choices <- cedar_campus_choices()
    expect_equal(unname(names(choices)[choices %in% bare]), bare)
  }
  # No campus code is written into the platform file that reads the CSV
  # (comments may name one to explain the rule; code may not).
  code_lines <- grep("^\\s*#", readLines("../../R/lists/campuses.R"), value = TRUE, invert = TRUE)
  expect_false(any(grepl(paste0('"', files$campus_code, '"', collapse = "|"), code_lines)))
})

test_that("the course-level rule is the institution's course_levels.csv", {
  levels <- validate_course_levels(read_institution_file("course_levels", cedar_institution_dir(cedar_base_dir, "unm")))
  expect_equal(unname(COURSE_LEVEL_BY_LEADING_DIGIT[levels$leading_digit]), levels$level)
  expect_setequal(names(COURSE_LEVEL_BY_LEADING_DIGIT), as.character(0:9))
})

test_that("the demo institution's configuration files load and validate", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  campuses <- validate_campuses(read_institution_file("campuses", dir))
  expect_true(all(c("ABQ", "EA", "GA", "VA") %in% campuses$campus_code))
  expect_equal(nrow(validate_course_levels(read_institution_file("course_levels", dir))), 10L)
})

test_that("the configuration validators report every problem at once", {
  dir <- write_config_dir(
    campuses = data.frame(campus_code = c("ABQ", "EA", "GA", "GA"),
                          campus_name = c("Main", "Online", "Gallup", "Gallup"),
                          kind = c("main", "main", "satellite", "branch"),
                          default_scope = c("TRUE", "yes", "FALSE", "FALSE"),
                          source_names = c("Albuquerque/Main", "Albuquerque/Main", "", "")),
    course_levels = data.frame(leading_digit = c(as.character(0:8), "9", "9"),
                               level = c(rep("lower", 3), rep("upper", 2), rep("grad", 4), "doctoral", "grad"))
  )
  err <- tryCatch(validate_campuses(read_institution_file("campuses", dir)), error = conditionMessage)
  expect_match(err, "duplicate campus_code GA")
  expect_match(err, "kind must be main, online, branch; found satellite")
  expect_match(err, "exactly one campus must have kind main; found 2")
  expect_match(err, "default_scope must be TRUE or FALSE for EA")
  expect_match(err, "names more than one campus: Albuquerque/Main")

  err <- tryCatch(validate_course_levels(read_institution_file("course_levels", dir)), error = conditionMessage)
  expect_match(err, "duplicate leading_digit 9")
  expect_match(err, "level must be lower, upper, grad; found doctoral")

  short <- write_config_dir(
    campuses = data.frame(campus_code = "ABQ", campus_name = "Main", kind = "main", default_scope = "TRUE"),
    course_levels = good_levels[-1, ]
  )
  expect_error(validate_course_levels(read_institution_file("course_levels", short)),
               "no row for leading_digit 0")
  # One main campus with no online campus is a valid institution.
  one <- validate_campuses(read_institution_file("campuses", short))
  expect_equal(one$campus_code[one$kind == "online"], character(0))
  expect_true(one$default_scope)
})

test_that("student_levels.csv translates the exports' spellings to one code each", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  levels <- validate_student_levels(read_institution_file("student_levels", dir))
  expect_equal(CEDAR_STUDENT_LEVELS, levels)
  # a code, its name and a source spelling all resolve to the code; an unlisted
  # value is NA, never a guess
  expect_equal(cedar_level_code_from_source(c(levels$level_code[1], levels$level_name[1], "not a level")),
               c(levels$level_code[1], levels$level_code[1], NA))
  with_source <- levels[nzchar(levels$source_names), ][1, ]
  expect_equal(cedar_level_code_from_source(with_source$source_names), with_source$level_code)
  campuses <- validate_campuses(read_institution_file("campuses", dir))
  with_source <- campuses[nzchar(campuses$source_names), ][1, ]
  expect_equal(cedar_campus_code_from_source(c(with_source$source_names, with_source$campus_name,
                                               with_source$campus_code, "nowhere")),
               c(rep(with_source$campus_code, 3), NA))

  bad <- write_config_dir(
    campuses = data.frame(campus_code = "ABQ", campus_name = "Main", kind = "main", default_scope = "TRUE"),
    course_levels = good_levels,
    student_levels = data.frame(level_code = c("UG", "GR", "GR", ""),
                                level_name = c("Undergraduate", "Graduate", "Graduate", "Law"),
                                source_names = c("Graduate", "Graduate/GASM", "", "")))
  err <- tryCatch(validate_student_levels(read_institution_file("student_levels", bad)), error = conditionMessage)
  expect_match(err, "blank level_code")
  expect_match(err, "duplicate level_code GR")
  expect_match(err, "names more than one level: Graduate")
})


# ---- Configuration files: gen_ed_courses.csv and excluded_courses.csv --------

test_that("the Gen Ed table and the excluded list are the institution's files", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  ge <- validate_gen_ed_courses(read_institution_file("gen_ed_courses", dir))
  expect_equal(CEDAR_GEN_ED_COURSES$subject_course, ge$subject_course)
  expect_equal(CEDAR_GEN_ED_COURSES$area, ge$area)
  expect_equal(CEDAR_GEN_ED_COURSES$area_label, paste0(ge$area, ": ", ge$area_name))
  expect_setequal(unlist(gen_ed_all), unique(ge$subject_course))
  lu <- gen_ed_course_lookup()
  expect_equal(nrow(lu), length(unique(ge$subject_course)))
  expect_true(all(c("subject_course", "area", "area_label") %in% names(lu)))

  ex <- validate_excluded_courses(read_institution_file("excluded_courses", dir))
  expect_equal(excluded_courses, ex$subject_course)
  expect_false(any(duplicated(excluded_courses)))
  # The platform files name no course.
  for (f in c("gen_ed_courses.R", "excluded_courses.R")) {
    code_lines <- grep("^\\s*#", readLines(file.path("../../R/lists", f)), value = TRUE, invert = TRUE)
    expect_false(any(grepl("\"[A-Z]{2,4} [0-9]{3,4}[A-Z]?\"", code_lines)), info = f)
  }
})

test_that("the demo institution's Gen Ed and excluded files load and cover fixture courses", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  ge <- validate_gen_ed_courses(read_institution_file("gen_ed_courses", dir))
  expect_true(all(c("HIST 1110", "MATH 1430", "ENGL 1120") %in% ge$subject_course))
  # The demo's areas are UNM's, restricted to courses the fixtures use.
  unm <- validate_gen_ed_courses(read_institution_file("gen_ed_courses", cedar_institution_dir(cedar_base_dir, "unm")))
  expect_true(all(paste(ge$area, ge$subject_course) %in% paste(unm$area, unm$subject_course)))
  expect_lt(nrow(ge), nrow(unm))
  ex <- validate_excluded_courses(read_institution_file("excluded_courses", dir))
  expect_true("AMST 499" %in% ex$subject_course)
})

test_that("the Gen Ed and excluded validators report every problem at once", {
  dir <- tempfile("institution-config-")
  dir.create(dir)
  utils::write.csv(data.frame(area = c("1", "1", "one", "2", "2"),
                              area_name = c("Communication", "Communications", "Math", "Math", ""),
                              subject_course = c("ENGL 1120", "ENGL 1120", "MATH 1430", "MATH 1220", "MATH 1250")),
                   file.path(dir, "gen_ed_courses.csv"), row.names = FALSE)
  utils::write.csv(data.frame(subject_course = c("HIST 499", "HIST 499", ""), notes = ""),
                   file.path(dir, "excluded_courses.csv"), row.names = FALSE)
  err <- tryCatch(validate_gen_ed_courses(read_institution_file("gen_ed_courses", dir)), error = conditionMessage)
  expect_match(err, "area must be a whole number; found one")
  expect_match(err, "blank area_name")
  expect_match(err, "more than one area_name for area 1, 2")
  expect_match(err, "duplicate course in an area: ENGL 1120")
  err <- tryCatch(validate_excluded_courses(read_institution_file("excluded_courses", dir)), error = conditionMessage)
  expect_match(err, "blank subject_course")
  expect_match(err, "duplicate subject_course HIST 499")
})


# ---- Configuration file: population_groups.csv ------------------------------

test_that("the population group registry is the institution's population_groups.csv", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  pg <- validate_population_groups(read_institution_file("population_groups", dir))
  expect_equal(names(CEDAR_POPULATION_GROUPS), unique(pg$group))
  for (id in names(CEDAR_POPULATION_GROUPS)) {
    rows <- pg[pg$group == id, ]
    expect_equal(CEDAR_POPULATION_GROUPS[[id]]$programs, unique(rows$program_name), info = id)
    expect_equal(CEDAR_POPULATION_GROUPS[[id]]$description, rows$description[[1]], info = id)
  }
  # The preselected groups come from default_for, one per surface.
  defaults <- pg[!duplicated(pg$group) & nzchar(pg$default_for), c("group", "default_for")]
  for (i in seq_len(nrow(defaults))) {
    for (surface in strsplit(defaults$default_for[[i]], "|", fixed = TRUE)[[1]]) {
      expect_equal(population_group_default(surface), defaults$group[[i]])
    }
  }
  expect_error(population_group_default("sidebar"), "Unknown population group surface")
  # The platform file names no group and no program.
  code_lines <- grep("^\\s*#", readLines("../../R/lists/population-presets.R"), value = TRUE, invert = TRUE)
  expect_false(any(grepl(paste0('"', unique(pg$group), '"', collapse = "|"), code_lines)))
})

test_that("the demo institution's population groups load and name fixture programs", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  pg <- validate_population_groups(read_institution_file("population_groups", dir))
  expect_true(all(pg$program_name %in% test_programs$program_name))
  expect_true(all(c("pathways", "scenario") %in% unlist(strsplit(pg$default_for, "|", fixed = TRUE))))
})

test_that("the population group validator reports every problem at once", {
  dir <- tempfile("institution-config-")
  dir.create(dir)
  utils::write.csv(data.frame(group = c("A", "A", "A", "B", "B", "C"),
                              description = c("Group A", "Group A", "Group A", "Group B", "Group B!", ""),
                              default_for = c("pathways", "pathways", "pathways", "pathways|sidebar", "pathways|sidebar", ""),
                              program_name = c("History", "History", "", "Nursing", "Biology", "Mathematics")),
                   file.path(dir, "population_groups.csv"), row.names = FALSE)
  err <- tryCatch(validate_population_groups(read_institution_file("population_groups", dir)), error = conditionMessage)
  expect_match(err, "blank program_name")
  expect_match(err, "more than one description for group B")
  expect_match(err, "blank description")
  expect_match(err, "duplicate program in a group: A / History")
  expect_match(err, "default_for must be pathways, scenario .*found sidebar")
  expect_match(err, "more than one group is default_for pathways")
})


# ---- Configuration files: projection_groups.csv and projection_courses.csv ---

test_that("the projection groups and overrides are the institution's files", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  pj <- validate_projection_groups(read_institution_file("projection_groups", dir),
                                   read_institution_file("projection_courses", dir),
                                   known_campuses = c(CEDAR_CAMPUS_MAIN, CEDAR_CAMPUS_ONLINE, CEDAR_CAMPUS_BRANCH))
  expect_equal(names(CEDAR_ENROLLMENT_PROJECTION_GROUPS), pj$groups$group_id)
  for (i in seq_len(nrow(pj$groups))) {
    g <- CEDAR_ENROLLMENT_PROJECTION_GROUPS[[pj$groups$group_id[[i]]]]
    rows <- pj$courses[pj$courses$group_id == pj$groups$group_id[[i]], ]
    expect_equal(g$label, pj$groups$label[[i]])
    expect_equal(g$market_id, pj$groups$market_id[[i]])
    expect_equal(g$campuses, pj$groups$campuses[[i]])
    expect_setequal(g$always_monitored_courses, rows$subject_course[rows$always_monitored])
    expect_true(all(rows$subject_course %in% g$courses))
    if (pj$groups$include_gen_ed[[i]]) {
      kept <- CEDAR_GEN_ED_COURSES$subject_course[!CEDAR_GEN_ED_COURSES$area %in% pj$groups$exclude_gen_ed_areas[[i]]]
      expect_true(all(kept %in% g$courses))
    }
  }
  overrides <- pj$courses[!is.na(pj$courses$history_start_term), ]
  expect_equal(unname(CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS[overrides$subject_course]),
               overrides$history_start_term)
  settings <- read_institution_file("settings", dir)
  expect_equal(CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM,
               as.integer(settings$value[settings$setting == "projection_history_start_term"]))
  # The platform file names no course, campus or term.
  code_lines <- grep("^\\s*#", readLines("../../R/lists/enrollment_projection_groups.R"), value = TRUE, invert = TRUE)
  expect_false(any(grepl("\"[A-Z]{2,4} [0-9]{3,4}[A-Z]?\"|\\b20[0-9]{4}L?\\b|\"(ABQ|EA)\"", code_lines)))
})

test_that("the demo institution's projection files load and name fixture courses", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  campuses <- validate_campuses(read_institution_file("campuses", dir))
  pj <- validate_projection_groups(read_institution_file("projection_groups", dir),
                                   read_institution_file("projection_courses", dir),
                                   known_campuses = campuses$campus_code)
  expect_equal(pj$groups$group_id, "critical_courses")
  expect_true(all(pj$courses$always_monitored))
})

test_that("the projection validator reports every problem at once", {
  dir <- tempfile("institution-config-")
  dir.create(dir)
  utils::write.csv(data.frame(group_id = c("critical_courses", "critical_courses", "Bad-Id"),
                              label = c("A", "A", ""), description = "d",
                              market_id = "m", campuses = c("ABQ|XX", "ABQ", "EA"),
                              include_gen_ed = c("TRUE", "maybe", "FALSE"),
                              exclude_gen_ed_areas = c("6|six", "", "6")),
                   file.path(dir, "projection_groups.csv"), row.names = FALSE)
  utils::write.csv(data.frame(group_id = c("critical_courses", "critical_courses", "ghost", "Bad-Id"),
                              subject_course = c("MATH 1215", "MATH 1215", "ENGL 1110", "MATH 1215"),
                              always_monitored = c("TRUE", "TRUE", "sometimes", "TRUE"),
                              history_start_term = c("202580", "202580", "2025", "202480"),
                              retention_min_terms = c("1", "1", "one", "1")),
                   file.path(dir, "projection_courses.csv"), row.names = FALSE)
  err <- tryCatch(validate_projection_groups(read_institution_file("projection_groups", dir),
                                             read_institution_file("projection_courses", dir),
                                             known_campuses = c("ABQ", "EA")),
                  error = conditionMessage)
  expect_match(err, "blank label")
  expect_match(err, "duplicate group_id critical_courses")
  expect_match(err, "group_id must be lowercase")
  expect_match(err, "campuses not in campuses.csv: XX")
  expect_match(err, "include_gen_ed must be TRUE or FALSE")
  expect_match(err, "exclude_gen_ed_areas must be whole area numbers separated by |; found six", fixed = TRUE)
  expect_match(err, "exclude_gen_ed_areas is set on a group whose include_gen_ed is not TRUE")
  expect_match(err, "group_id not in projection_groups.csv: ghost")
  expect_match(err, "duplicate course in a group: critical_courses / MATH 1215")
  expect_match(err, "always_monitored must be TRUE or FALSE")
  expect_match(err, "history_start_term must be a term code YYYYSS; found 2025")
  expect_match(err, "retention_min_terms must be a whole number; found one")
  expect_match(err, "history_start_term differs between groups for MATH 1215")
})

test_that("course sequences are the institution's file and the validator reports every problem", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  sequences <- validate_projection_sequences(read_institution_file("projection_sequences", dir))
  expect_equal(CEDAR_ENROLLMENT_PROJECTION_SEQUENCES, sequences)
  expect_equal(names(sequences), c("from_course", "to_course"))
  expect_true(nrow(sequences) > 0L)
  # A model default, so the bundle signature changes when the list does.
  expect_equal(enrollment_projection_defaults()$sequences, sequences)
  demo <- validate_projection_sequences(
    read_institution_file("projection_sequences", cedar_institution_dir(cedar_base_dir, "demo"))
  )
  expect_true(nrow(demo) > 0L)

  bad <- tempfile("institution-config-")
  dir.create(bad)
  utils::write.csv(data.frame(from_course = c("ENGL 1110", "ENGL 1110", "MATH 1512", ""),
                              to_course = c("ENGL 1120", "ENGL 1120", "MATH 1512", "MATH 1522"),
                              notes = ""),
                   file.path(bad, "projection_sequences.csv"), row.names = FALSE)
  err <- tryCatch(validate_projection_sequences(read_institution_file("projection_sequences", bad)),
                  error = conditionMessage)
  expect_match(err, "blank from_course")
  expect_match(err, "a course cannot precede itself: MATH 1512")
  expect_match(err, "duplicate pair ENGL 1110 -> ENGL 1120")
})

test_that("a settings.csv without a projection window stops the builder, not the app", {
  withr::local_options(list())
  old <- CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM
  rlang::local_bindings(CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM = NA_integer_, .env = .GlobalEnv)
  expect_error(enrollment_projection_model_config(), "projection_history_start_term")
  expect_error(projection_course_history_starts("MATH 1215"), "projection_history_start_term")
  expect_equal(enrollment_projection_model_config(list(history_start_term = old))$history_start_term, old)
  # And the settings validator rejects a malformed value.
  dir <- write_mapping_dir(one_unit$colleges, one_unit$units, one_unit$subjects,
                           settings = data.frame(setting = c(unm_settings$setting),
                                                 value = c(unm_settings$value[1:2], "Spring 2022")))
  expect_error(read_institution_mappings(dir), "projection_history_start_term must be a term code")
})


# ---- Configuration files: the three text maps ---------------------------------

test_that("the text maps are the institution's files, and every HR unit exists (M28)", {
  dir <- cedar_institution_dir(cedar_base_dir, "unm")
  units <- read_institution_file("units", dir)$unit_code
  tm <- validate_text_maps(read_institution_file("program_names", dir),
                           read_institution_file("program_name_aliases", dir),
                           read_institution_file("source_organizations", dir),
                           known_units = units)
  expect_equal(names(major_name_to_major_code), tm$program_names$program_name)
  expect_equal(unname(major_name_to_major_code), tm$program_names$program_code)
  expect_equal(names(program_name_aliases), tm$aliases$source_name)
  expect_equal(unname(program_name_aliases), tm$aliases$program_name)
  expect_equal(names(hr_org_desc_to_dept), tm$organizations$source_name)
  expect_equal(unname(hr_org_desc_to_dept), tm$organizations$unit_code)
  expect_true(all(hr_org_desc_to_dept %in% units))
  # Names with commas survive the round trip through the one-row-per-line file.
  expect_true(any(grepl(",", names(major_name_to_major_code))))
  # The platform file names no program, code or organisation.
  code_lines <- grep("^\\s*#", readLines("../../R/lists/mappings.R"), value = TRUE, invert = TRUE)
  expect_false(any(grepl("\"[A-Z]{2,4}\"|\"[A-Z][a-z]+( [A-Za-z&]+)*\"", code_lines)))
})

test_that("the demo institution's text maps load empty", {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  tm <- validate_text_maps(read_institution_file("program_names", dir),
                           read_institution_file("program_name_aliases", dir),
                           read_institution_file("source_organizations", dir),
                           known_units = read_institution_file("units", dir)$unit_code)
  expect_equal(nrow(tm$program_names), 0L)
  expect_equal(nrow(tm$organizations), 0L)
})

test_that("the text-map validator reports every problem at once", {
  dir <- tempfile("institution-config-")
  dir.create(dir)
  utils::write.csv(data.frame(program_name = c("History", "History", ""), program_code = c("HIST", "HIST", "X")),
                   file.path(dir, "program_names.csv"), row.names = FALSE)
  utils::write.csv(data.frame(source_name = c("Hist", "History"), program_name = c("History", "History")),
                   file.path(dir, "program_name_aliases.csv"), row.names = FALSE)
  utils::write.csv(data.frame(source_name = c("AS History", "AS Basketry"), unit_code = c("HIST", "BSKT")),
                   file.path(dir, "source_organizations.csv"), row.names = FALSE)
  err <- tryCatch(validate_text_maps(read_institution_file("program_names", dir),
                                     read_institution_file("program_name_aliases", dir),
                                     read_institution_file("source_organizations", dir),
                                     known_units = "HIST"),
                  error = conditionMessage)
  expect_match(err, "program_names.csv: blank program_name")
  expect_match(err, "program_names.csv: duplicate program_name History")
  expect_match(err, "source_name equals program_name for History")
  expect_match(err, "unit_code not in units.csv: BSKT")
})

# ── Dimensions and attach_unit() (ADR-001 step 3) ────────────────────────────
# The mapping files are read as dimension tables and the default unit is
# attached at load, under the names every reader has always read. These tests
# guard the one function that resolves a unit and the two rules it wraps.

test_that("dims wraps the validated mapping files, and refuses anything else", {
  dims <- demo_dims()
  expect_s3_class(dims, "cedar_dims")
  expect_setequal(names(dims), c("colleges", "units", "subjects", "programs", "code_history", "settings"))
  expect_error(validate_cedar_dims(unclass(dims)), "build_cedar_dims")
  expect_error(build_cedar_dims(unclass(dims)[c("units", "colleges")]), "missing mapping table")
  broken <- dims; broken$units$unit_name <- NULL
  expect_error(validate_cedar_dims(broken), "dims\\$units lacks column")
})

test_that("attach_unit() reproduces the subject rule under the readers' column names", {
  dims <- demo_dims()
  # The designed sections as the fact table keeps them: subject, the source's
  # college and the level are keys; the unit columns are what attach adds.
  rows <- test_sections %>% select(-department) %>% rename(source_college = college)
  got <- attach_unit(rows, dims, "subject", keys = c(subject = "subject"))
  expect_equal(got$department, test_sections$department)
  expect_true(all(got$college_basis == "mapped"))
  expect_equal(got$college, dims$units$college_code[match(got$department, dims$units$unit_code)])
  # Scaffolding. GEOG is Geography and Environmental Studies' (GES) in the
  # demo files, so a unit is never the subject's own code; ZZZZ has no row, so
  # NA with the source's college translated and labelled; an unknown source
  # college with no row has nothing. Reintroducing the self-named fallback
  # (EC-14) fails the first; a unit read off the subject fails it too.
  probe <- rows[1:3, ] %>%
    mutate(subject = c("GEOG", "ZZZZ", "ZZZZ"),
           source_college = c("STEM", "STEM", "Nowhere"), level = "lower")
  got <- attach_unit(probe, dims, "subject", keys = c(subject = "subject"))
  expect_equal(got$department, c("GES", NA, NA))
  expect_equal(got$college, c("AS", "AS", NA))
  expect_equal(got$college_basis, c("mapped", "banner", NA))
  # The class list keys on subject_code by default.
  cl <- test_students %>% select(-department) %>% rename(source_college = college)
  expect_equal(attach_unit(cl, dims, "subject")$department, test_students$department)
  # Refuses rows missing a key, rows already carrying an output column, and
  # an override that names nothing the rule reads or writes.
  expect_error(attach_unit(select(rows, -level), dims, "subject", keys = c(subject = "subject")),
               "lack key column\\(s\\) level")
  expect_error(attach_unit(mutate(rows, department = "x"), dims, "subject", keys = c(subject = "subject")),
               "already carry department")
  expect_error(attach_unit(rows, dims, "subject", keys = c(subj = "subject")), "unknown keys subj")
  expect_error(attach_unit(rows, dims, "subject", keys = c(subject = "subject"), cols = c(dept = "d")),
               "unknown cols dept")
  # Another hierarchy writes its own names, never the defaults.
  other <- attach_unit(test_sections, dims, "subject",
                       keys = c(subject = "subject", college = "college"),
                       cols = c(unit = "subject_unit", college = "subject_college", basis = "subject_basis"))
  expect_equal(other$subject_unit, test_sections$department)
  expect_equal(other$department, test_sections$department)
})

test_that("attach_unit() reproduces the program rule, and a student's college follows the primary major", {
  # Scaffolding institution: HIST and CRIM (SOCI, but CJUS at the branch
  # college AD), BCHM owned by HIST but credited to AD, its pre-major FBCH,
  # and UNDC that nothing owns but University-College-like AS reports.
  programs <- rbind(
    program_rows("HIST"),
    program_rows("CRIM", unit_code = "SOCI"),
    program_rows("CRIM", unit_code = "CJUS", in_college = "AD", basis = "override"),
    program_rows("BCHM", college_code = "AD"),
    program_rows("FBCH", is_pre_major = "TRUE", leads_to = "BCHM"),
    program_rows("UNDC", unit_code = "", basis = "no_unit", college_code = "AS"))
  dims <- build_cedar_dims(read_institution_mappings(
    do.call(write_mapping_dir, c(one_unit, list(programs = programs)))))
  # Declarations, as cedar_programs keeps them: the code, academic studies'
  # Translated College (source_college) and Actual College as a code
  # (source_college_code). Expected values, row by row, beside each student.
  decl <- tibble::tribble(
    ~student_id, ~term,   ~program_type,         ~major_code, ~source_college,     ~source_college_code,
    # S1: a decided major; the minor and the concentration take its college,
    # the concentration its unit too.
    "S1",        202080L, "Major",               "HIST",      "Arts and Sciences", "AS",
    "S1",        202080L, "First Minor",         "CRIM",      "Arts and Sciences", "AS",
    "S1",        202080L, "First Concentration", "HISC",      "Arts and Sciences", "AS",
    # S2: an undecided major; the student's college is Banner's, labelled,
    # on the decided minor too. CRIM at AD is CJUS.
    "S2",        202080L, "Major",               "NOPE",      "Branch Campuses",   "AD",
    "S2",        202080L, "First Minor",         "CRIM",      "Branch Campuses",   "AD",
    # S3: nothing owns UNDC, but the file names its college.
    "S3",        202080L, "Major",               "UNDC",      "Branch Campuses",   "AD",
    # S4: a minor and no major: no primary, so Banner's college.
    "S4",        202080L, "First Minor",         "CRIM",      "Arts and Sciences", "AS",
    # S5: BCHM's own college, not its unit's.
    "S5",        202080L, "Major",               "BCHM",      "Arts and Sciences", "AS",
    # S6: a pre-major follows its target's college; no source college at all.
    "S6",        202080L, "Major",               "FBCH",      NA,                  NA,
    # S7: undecided, and a source college no file names: nothing, labelled nothing.
    "S7",        202080L, "Major",               "NOPE",      "Nowhere",           NA,
    # S8: two majors; the primary is the first by code (BCHM before HIST).
    "S8",        202080L, "Major",               "HIST",      "Arts and Sciences", "AS",
    "S8",        202080L, "Second Major",        "BCHM",      "Arts and Sciences", "AS",
    "S8",        202080L, "Major",               "BCHM",      "Arts and Sciences", "AS")
  got <- attach_program_units(decl, dims)
  expect_equal(got$dept_code,
               c("HIST", "SOCI", "HIST",  NA, "CJUS",  NA,  "SOCI", "HIST", "HIST", NA, "HIST", "HIST", "HIST"))
  expect_equal(got$program_college,
               c("AS",   "AS",   "AS",    NA, "AD",    "AS", "AS",  "AD",   "AD",   NA, "AS",   "AD",   "AD"))
  expect_equal(got$college_code,
               c("AS",   "AS",   "AS",    "AD", "AD",  "AS", "AS",  "AD",   "AD",   NA, "AD",   "AD",   "AD"))
  expect_equal(got$college_basis,
               c("mapped", "mapped", "mapped", "banner", "banner", "mapped", "banner", "mapped", "mapped", NA,
                 "mapped", "mapped", "mapped"))
  expect_equal(got$student_college[c(1, 4, 6, 8, 10)],
               c("Arts and Sciences", "Branch", "Arts and Sciences", "Branch", NA))
  expect_false(any(grepl("^\\.", names(got))))
  # Degrees: keyed on the Actual College, with the Translated College
  # preferred for the Banner label; college and student_college are names.
  awards <- tibble::tribble(
    ~student_id, ~term,   ~major_code, ~source_college,     ~source_student_college,
    "S5",        202110L, "BCHM",      "Arts and Sciences", "AS",
    "S2",        202110L, "NOPE",      "Arts and Sciences", "ED",
    "S9",        202110L, "CRIM",      NA,                  "ED")
  got <- attach_degree_units(awards, dims)
  expect_equal(got$dept_code, c("HIST", NA, "CJUS"))
  expect_equal(got$college_code, c("AD", "AS", "AD"))
  expect_equal(got$college_basis, c("mapped", "banner", "mapped"))
  expect_equal(got$college, c("Branch", "Arts and Sciences", "Branch"))
  expect_equal(got$student_college, got$college)
})

test_that("attach_default_units() replaces whatever a file stamped and keeps the table's attributes", {
  dims <- demo_dims()
  stamped <- test_sections %>%
    mutate(source_college = college, department = "WRONG", college = "WRONG", college_basis = "x")
  attr(stamped, "cedar_example_stamp") <- list(combined = "abc")
  objs <- suppressMessages(attach_default_units(
    list(cedar_sections = stamped, cedar_degrees = tibble::tibble()), dims))
  expect_equal(objs$cedar_sections$department, test_sections$department)
  expect_true(all(objs$cedar_sections$college %in% dims$colleges$college_code))
  expect_equal(attr(objs$cedar_sections, "cedar_example_stamp"), list(combined = "abc"))
  expect_setequal(names(objs$cedar_sections), c(names(test_sections), "source_college", "college_basis"))
  # The crosslist columns follow the department, so they are attached with
  # it and agree with the fixture's pinned values (XL01-XL06).
  expect_equal(objs$cedar_sections$crosslist_external, test_sections$crosslist_external)
  expect_equal(objs$cedar_sections$crosslist_partners, test_sections$crosslist_partners)
  # A table that is not loaded is left alone, and said so.
  expect_equal(ncol(objs$cedar_degrees), 0L)
  expect_message(attach_default_units(list(cedar_registrations = NULL), dims), "cedar_registrations is not loaded")
  expect_error(attach_default_units(list(cedar_sections = stamped), unclass(dims)), "build_cedar_dims")
})

test_that("the code-history validator reports every problem at once", {
  history <- rbind(
    history_rows("SOCI 371", "SOCI 371"),                                  # a code does not succeed itself
    history_rows("MATH 120", "MATH 1215"), history_rows("MATH 120", "MATH 1215"),  # duplicate
    history_rows("MATH 121", "MATH 1220"), history_rows("MATH 121", "MATH 1230"),  # a confirmed split
    history_rows("MATH 122", "MATH 1240", status = "proposed"),           # ...a proposed one is fine
    history_rows("MATH 122", "MATH 1250", status = "proposed"),
    history_rows("PSY", "PSYC", kind = "subject", scope = "undergraduate"),# scope on a subject row
    history_rows("ALB", "ALBS", kind = "subject", effective_term = "2020"),# not a term code
    history_rows("A", "B", kind = "subject"), history_rows("B", "A", kind = "subject"),  # a cycle
    history_rows("soci 371", "SOCI 3710"),                                # a lower-case code
    history_rows("RADS", "FRAD", kind = "major", basis = "vibes", status = "maybe")
  )
  dir <- do.call(write_mapping_dir, c(one_unit, list(code_history = history)))
  err <- tryCatch(read_institution_mappings(dir), error = conditionMessage)
  expect_match(err, "a code does not succeed itself: course SOCI 371 -> SOCI 371")
  expect_match(err, "duplicate succession course MATH 120 -> MATH 1215")
  expect_match(err, "a confirmed course code succeeds to more than one code \\(a split cannot give it one id\\): MATH 121")
  expect_false(grepl("MATH 122", err))
  expect_match(err, "scope must be blank on a subject or course row .*: subject PSY -> PSYC")
  expect_match(err, "effective_term must be a term code YYYYSS \\(SS = 10, 60 or 80\\): 2020")
  expect_match(err, "confirmed subject successions form a cycle, starting at: A, B")
  expect_match(err, "a course row's codes must look like SOCI 371: course soci 371 -> SOCI 3710")
  expect_match(err, "unknown kind major")
  expect_match(err, "unknown basis vibes")
  expect_match(err, "unknown status maybe")
})

test_that("the demo and UNM code histories load, and every confirmed subject rename is section-evidenced", {
  demo <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "demo"))$code_history
  expect_true(all(c("subject", "course") %in% demo$kind))
  expect_true(any(demo$status == "proposed"))
  unm <- read_institution_mappings(cedar_institution_dir(cedar_base_dir, "unm"))$code_history
  confirmed_subjects <- unm[unm$kind == "subject" & unm$status == "confirmed", ]
  expect_gt(nrow(confirmed_subjects), 0)
  expect_true(all(confirmed_subjects$basis == "section_crn"))
  expect_true(all(nzchar(unm$evidence)))
})
