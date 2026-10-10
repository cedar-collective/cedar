# transform-to-cedar.R
#
# Transforms parsed MyReports data files into the CEDAR data model.
# Runs after parse-data.R (PII removal already done) and writes cedar_* files.
#
# IMPORTANT: This does NOT modify any existing source files.
# Output files are named cedar_sections.qs, cedar_students.qs, etc.
#
# ⚠️  SCHEMA SYNC REQUIREMENT:
# When adding columns to cedar_* tables, you MUST also update:
# 1. tests/testthat/fixtures/designed_test_data.R — mirror the columns in the
#    hand-crafted test fixtures (and update its pinned expected-value header)
# 2. global.R validation_specs — update if new columns are required
# 3. docs/data-model.md — document the new columns
# Verify after changes: Rscript -e "testthat::test_dir('tests/testthat')"
#
# Recent schema changes:
# - Apr 2026: Refactored: each table now has its own transform_*() function
# - Apr 2026: Added cedar_applicants (from admissions_applicants)
# - Mar 2026: Added residency, academic_standing, inst_gpa to cedar_programs
# - Mar 2026: Added is_pre_major to cedar_programs
# - Mar 2026: Added is_topics to cedar_sections
# - Jan 2026: Removed duplicate 'grade' column; use 'final_grade'
# - Jan 2026: Added subject_code, level, instructor_id to cedar_students
# - Jan 2026: Added student_level, student_college, student_campus to cedar_programs
#
# To add a new table: write a transform_<name>() function below,
# add the name to all_tables in transform_to_cedar(), wire it in the orchestrator.

library(tidyverse)
library(digest)

source("R/trunk/utils.R")        # academic_period_to_term, add_next_term_col, etc.
source("R/lists/grades.R")       # GRADES_DFW, GRADES_PASS
source("R/lists/status_codes.R") # STATUS_REGISTERED, STATUS_DROP_EARLY
source("R/lists/course_numbering.R") # COURSE_LEVEL_BY_LEADING_DIGIT


# ── Helper functions ──────────────────────────────────────────────────────────

load_file <- function(path, ext) {
  if (ext == ".qs") qs2::qs_read(path) else readRDS(path)
}

save_cedar_file <- function(data, table_name, data_dir, ext) {
  filename <- paste0("cedar_", table_name, ext)
  filepath <- file.path(data_dir, filename)
  message("Saving: ", filepath)
  if (ext == ".qs") {
    qs2::qs_save(data, filepath)
  } else {
    saveRDS(data, filepath)
  }
  file_size_mb <- file.size(filepath) / 1024^2
  if (is.data.frame(data)) {
    message("  ✅ Saved (", round(file_size_mb, 1), " MB, ",
            format(nrow(data), big.mark = ","), " rows)")
  } else if (is.list(data)) {
    sizes <- vapply(data, function(x) {
      if (is.data.frame(x)) paste0(format(nrow(x), big.mark = ","), " rows")
      else if (is.vector(x) || is.character(x)) paste0(format(length(x), big.mark = ","), " entries")
      else class(x)[1]
    }, character(1))
    message("  ✅ Saved (", round(file_size_mb, 1), " MB, ",
            length(data), " tables: ",
            paste(names(data), sizes, sep = "=", collapse = ", "), ")")
  } else {
    message("  ✅ Saved (", round(file_size_mb, 1), " MB)")
  }
  as_of <- if ("as_of_date" %in% names(data)) {
    tryCatch(format(max(data$as_of_date, na.rm = TRUE)), error = function(e) NA_character_)
  } else NA_character_
  min_term <- if ("term" %in% names(data)) {
    tryCatch(as.character(min(data$term, na.rm = TRUE)), error = function(e) NA_character_)
  } else NA_character_
  max_term <- if ("term" %in% names(data)) {
    tryCatch(as.character(max(data$term, na.rm = TRUE)), error = function(e) NA_character_)
  } else NA_character_
  list(
    filename = filename, filepath = filepath,
    rows = if (is.data.frame(data)) nrow(data) else NA_integer_,
    size_mb = file_size_mb,
    as_of_date = as_of, min_term = min_term, max_term = max_term
  )
}

build_cedar_status_payload <- function(saved_files, generated = Sys.time()) {
  tables <- lapply(saved_files, function(info) {
    list(
      file = info$filename,
      rows = info$rows,
      size_mb = round(info$size_mb, 1),
      as_of_date = info$as_of_date,
      min_term = info$min_term,
      max_term = info$max_term
    )
  })

  list(
    generated = if (inherits(generated, "POSIXt")) {
      format(generated, "%Y-%m-%d %H:%M:%S")
    } else {
      as.character(generated)
    },
    tables = tables
  )
}

write_cedar_status_file <- function(saved_files, status_file, generated = Sys.time()) {
  status <- build_cedar_status_payload(saved_files, generated)
  jsonlite::write_json(status, status_file, auto_unbox = TRUE,
                       pretty = TRUE, na = "null")
  invisible(status)
}

# Encrypt a student ID vector if not already hashed (64-char hex = already encrypted)
encrypt_if_needed <- function(id) {
  id_chr <- as.character(id)
  if (all(nchar(id_chr) == 64)) return(id_chr)
  salt <- Sys.getenv("CEDAR_STUDENT_SALT")
  if (salt == "") salt <- "cedar_default_salt_change_me"
  # Hash unique IDs only — students appear in thousands of rows each
  unique_ids <- unique(id_chr)
  enc <- setNames(
    vapply(unique_ids, function(x) digest(paste0(x, salt), algo = "sha256"), character(1)),
    unique_ids
  )
  unname(enc[id_chr])
}

# Convert a character vector of column names to snake_case
to_snake <- function(x) {
  x <- gsub("[^a-zA-Z0-9]+", "_", x)  # non-alphanumeric → underscore
  x <- gsub("_{2,}", "_", x)           # collapse consecutive underscores
  x <- gsub("^_|_$", "", x)            # strip leading/trailing underscores
  tolower(x)
}


# The ADR-002 mapping files (read_institution_mappings()) that decide every
# unit. Required: a transform that cannot read them stops, rather than naming
# departments after codes as the old lookup chain did (ISSUES.md I7).
.require_mapping_files <- function(maps, caller, tables) {
  files <- maps$mapping_files
  missing <- tables[vapply(tables, function(t) is.null(files[[t]]), logical(1))]
  if (length(missing)) {
    stop("[", caller, "] maps$mapping_files must carry ", paste(missing, collapse = ", "),
         ": the institution mapping files decide every unit (ADR-002 Stage 3).")
  }
  files
}

# A course's reported college (ADR-002 Stage 3b): its subject row's
# college_code, else its unit's home college. A subject with no confirmed row
# reports Banner's section college instead, translated through colleges.csv
# (ED -> EH) and labelled college_basis = "banner" until the subject is decided
# (decided 2026-10-10: nothing drops out of college totals meanwhile).
.course_colleges <- function(course_units, source_college, files) {
  banner <- translate_source_college(source_college, files)
  undecided <- is.na(course_units$unit_code)
  tibble::tibble(
    college = dplyr::if_else(undecided, banner, course_units$college_code),
    college_basis = dplyr::case_when(
      !undecided & !is.na(course_units$college_code) ~ "mapped",
      undecided & !is.na(banner)                      ~ "banner",
      TRUE                                            ~ NA_character_))
}

# Colleges on cedar_programs (ADR-002 Stage 3b; decided 2026-10-10).
#
# - program_college: each row's own program's college -- program -> unit ->
#   college through the files; a concentration takes its primary major's.
# - college_code / student_college: the STUDENT's college that term, the
#   program_college of their primary major, on every one of their rows, so
#   "students in a college" and a college filter mean what they always have.
# - When the primary major's code is not yet decided in programs.csv, or the
#   student has no primary major that term, the student's college is Banner's
#   (Translated College, else Actual College), translated through colleges.csv
#   and labelled college_basis = "banner". A decided code that names no college
#   (Non-Degree) has none.
# - Banner's values stay beside them: source_college (Translated College) and
#   source_college_code (Actual College).
add_program_colleges <- function(programs, files) {
  needed <- c("student_id", "term", "program_type", "major_code", "student_college", "college_code")
  missing <- setdiff(needed, names(programs))
  if (length(missing)) {
    stop("[add_program_colleges] programs lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  programs <- programs %>%
    dplyr::rename(source_college = student_college, source_college_code = college_code) %>%
    dplyr::mutate(
      program_college = resolve_program_colleges(major_code, dplyr::coalesce(source_college_code, ""), files),
      .decided = !is.na(.confirmed_program_rows(major_code, dplyr::coalesce(source_college_code, ""),
                                                files$programs, no_unit = TRUE)),
      .banner = dplyr::coalesce(translate_source_college(source_college, files),
                                translate_source_college(source_college_code, files)))
  primary <- programs %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::arrange(student_id, term, major_code) %>%
    dplyr::distinct(student_id, term, .keep_all = TRUE) %>%
    dplyr::select(student_id, term, .primary_college = program_college, .primary_decided = .decided)
  programs %>%
    dplyr::left_join(primary, by = c("student_id", "term")) %>%
    dplyr::mutate(
      program_college = dplyr::if_else(grepl("Concentration", program_type),
                                       .primary_college, program_college),
      .primary_decided = dplyr::coalesce(.primary_decided, FALSE),
      college_code = dplyr::if_else(.primary_decided, .primary_college, .banner),
      college_basis = dplyr::case_when(
        .primary_decided & !is.na(.primary_college) ~ "mapped",
        !.primary_decided & !is.na(.banner)         ~ "banner",
        TRUE                                        ~ NA_character_),
      student_college = college_names(college_code, files)) %>%
    dplyr::select(-".decided", -".banner", -".primary_college", -".primary_decided")
}

# ── 1. transform_sections: DESRs → cedar_sections ────────────────────────────

#' @param desrs    Raw DESRs data frame (output of parse-data.R + parse-DESR.R)
#' @param data_dir Path to data directory (used for HR merge file lookup)
#' @param ext      File extension: ".qs" or ".Rds"
#' @param maps     Named list of lookup vectors from transform_to_cedar()
#' @return list(saved = list(sections = <meta>), table = cedar_sections)
transform_sections <- function(desrs, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("1. Transforming DESRs → cedar_sections")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(desrs), " rows, ", ncol(desrs), " columns")
  message("  Input columns: ", paste(names(desrs), collapse = ", "))

  files  <- .require_mapping_files(maps, "transform_sections", c("subjects", "units", "colleges"))
  gen_ed <- maps$gen_ed

  # ── Pre-processing: derive helper columns ────────────────────────────────
  message("  Pre-processing: deriving helper columns...")

  desrs <- desrs %>%
    unite(SUBJ_CRSE, c("SUBJ", "CRSE"),               sep = " ",  remove = FALSE) %>%
    unite(INST_NAME, c("PRIM_INST_LAST", "PRIM_INST_FIRST"), sep = ", ", remove = FALSE) %>%
    mutate(
      total_enrl = as.numeric(pmax(ENROLLED, XL_ENRL, na.rm = TRUE)),
      level      = course_level_from_number(SUBJ_CRSE),
      term_type  = dplyr::case_when(
        substr(as.character(TERM), 5, 6) == "80" ~ "fall",
        substr(as.character(TERM), 5, 6) == "10" ~ "spring",
        substr(as.character(TERM), 5, 6) == "60" ~ "summer",
        TRUE ~ NA_character_
      )
    )

  if (length(gen_ed[["1"]]) > 0) {
    desrs <- desrs %>%
      mutate(gen_ed_area = dplyr::case_when(
        SUBJ_CRSE %in% gen_ed[["1"]] ~ 1L,
        SUBJ_CRSE %in% gen_ed[["2"]] ~ 2L,
        SUBJ_CRSE %in% gen_ed[["3"]] ~ 3L,
        SUBJ_CRSE %in% gen_ed[["4"]] ~ 4L,
        SUBJ_CRSE %in% gen_ed[["5"]] ~ 5L,
        SUBJ_CRSE %in% gen_ed[["7"]] ~ 7L
      ))
  } else {
    desrs$gen_ed_area <- NA_integer_
    message("  ⚠️  gen_ed vectors not found — gen_ed_area will be NA")
  }

  # Unit from subjects.csv (ADR-002): the most specific confirmed row for the
  # subject, the section's college and the course level. A subject with no
  # confirmed row has no unit -- never a department named after itself. The
  # end-of-transform mapping audit and Admin > Mappings list each one.
  course_units <- resolve_course_units(desrs$SUBJ, desrs$COLLEGE, desrs$level, files)
  desrs$DEPT <- course_units$unit_code
  course_colleges <- .course_colleges(course_units, desrs$COLLEGE, files)
  desrs$COLLEGE_REPORTED <- course_colleges$college
  desrs$COLLEGE_BASIS    <- course_colleges$college_basis
  rm(course_units, course_colleges)
  no_unit <- sort(unique(desrs$SUBJ[is.na(desrs$DEPT)]))
  if (length(no_unit) > 0)
    message("  ⚠️  ", length(no_unit), " subject code(s) have no confirmed subjects.csv row, so no unit: ",
            paste(no_unit, collapse = ", "))

  # ── HR merge (job_cat / title enrichment) ────────────────────────────────
  hr_file <- file.path(data_dir, paste0("hr_data", ext))
  if (file.exists(hr_file)) {
    message("  Pre-processing: merging HR data for job_cat/title fields...")
    hr_desrs <- load_file(hr_file, ext)
    hr_desrs  <- hr_desrs %>% dplyr::select(-dplyr::any_of("as_of_date"))
    desrs$PRIM_INST_ID <- as.character(desrs$PRIM_INST_ID)
    desrs$TERM         <- as.character(desrs$TERM)
    desrs <- desrs %>%
      dplyr::left_join(hr_desrs,
                       by     = c("TERM" = "term_code", "PRIM_INST_ID" = "UNM ID"),
                       suffix = c("", ".hr")) %>%
      dplyr::select(-dplyr::any_of("DEPT.hr"))
    rm(hr_desrs); gc(verbose = FALSE)
    message("  ✅ HR merge complete: ", nrow(desrs), " rows")
  } else {
    desrs$job_cat <- NA_character_
    message("  ⚠️  hr_data not found: ", hr_file, " — job_cat will be NA")
  }

  # ── Transmute to CEDAR model ─────────────────────────────────────────────
  message("  Transforming to CEDAR model...")

  .comments_col <- intersect(c("COMMENTS", "Comments", "comments", "COMMENT"), names(desrs))
  .comments_col <- if (length(.comments_col) > 0) .comments_col[[1]] else NA_character_

  .census1_col <- intersect(c("CENSUS1", "CENSUS_1", "CENSUS1_DATE", "census1"), names(desrs))
  .census1_col <- if (length(.census1_col) > 0) .census1_col[[1]] else NA_character_

  .parse_desr_date <- function(x) {
    if (inherits(x, "Date")) return(x)
    as.Date(x, tryFormats = c("%m/%d/%Y", "%Y-%m-%d"))
  }

  cedar_sections <- desrs %>%
    transmute(
      section_id   = paste0(TERM, "-", CRN),
      term         = as.integer(TERM),
      crn          = as.character(CRN),
      subject      = SUBJ,
      course_number    = CRSE,
      subject_course   = SUBJ_CRSE,
      section          = SECT,
      course_title     = SECT_TITLE,
      part_term    = if ("PT" %in% names(.)) PT else NA_character_,
      campus       = CAMP,
      # The mapped college (Stage 3b); Banner's own value stays beside it.
      college        = COLLEGE_REPORTED,
      source_college = COLLEGE,
      college_basis  = COLLEGE_BASIS,
      department   = DEPT,
      instructor_id   = as.character(PRIM_INST_ID),
      instructor_name = INST_NAME,
      job_cat      = if ("job_cat" %in% names(.)) job_cat else NA_character_,
      enrolled     = as.integer(ENROLLED),
      total_enrl   = as.integer(total_enrl),
      capacity     = if ("SECT_CAP" %in% names(.)) as.integer(SECT_CAP) else as.integer(ROOM_CAP),
      available    = as.integer(SEATS_AVAIL),
      crosslist_code    = if ("XL_CODE" %in% names(.)) as.character(XL_CODE) else "0",
      crosslist_subject = if ("XL_SUBJ" %in% names(.)) as.character(XL_SUBJ) else "",
      status           = STATUS,
      comments         = if (!is.na(.comments_col)) as.character(.data[[.comments_col]]) else NA_character_,
      delivery_method  = INST_METHOD,
      level        = level,
      term_type    = term_type,
      gen_ed_area  = gen_ed_area,
      # is_combined: TRUE for integrated lecture+lab courses (C suffix, e.g. BIOL 2110C).
      # Combined courses share one subject_course across multiple CRNs.
      # Use n_distinct(subject_course) not n_distinct(crn) when counting course offerings.
      is_combined      = grepl("[Cc]$", CRSE),
      waitlist_count   = if ("WAIT_COUNT"    %in% names(.)) as.integer(coalesce(WAIT_COUNT,    0)) else NA_integer_,
      waitlist_capacity = if ("WAIT_CAPACITY" %in% names(.)) as.integer(coalesce(WAIT_CAPACITY, 0)) else NA_integer_,
      start_date   = if ("START_DATE" %in% names(.)) as.Date(START_DATE, format = "%m/%d/%Y") else NA_Date_,
      end_date     = if ("END_DATE"   %in% names(.)) as.Date(END_DATE,   format = "%m/%d/%Y") else NA_Date_,
      census1      = if (!is.na(.census1_col)) .parse_desr_date(.data[[.census1_col]]) else NA_Date_,
      credits_min  = if ("MIN_CR" %in% names(.)) as.numeric(MIN_CR) else NA_real_,
      credits_max  = if ("MAX_CR" %in% names(.)) as.numeric(MAX_CR) else NA_real_,
      as_of_date   = as.Date(as_of_date),
      # Temporary: preserved for home-section detection below; dropped after post-processing
      xl_home_text = if ("SHORT_TEXT" %in% names(.)) as.character(SHORT_TEXT) else NA_character_
    )

  # ── Post-processing: crosslist enrichment and split-level detection ──────
  message("  Enriching crosslist fields and detecting split-level courses...")

  cedar_sections <- cedar_sections %>%
    mutate(crosslist_group = ifelse(
      is.na(crosslist_code) | crosslist_code == "" | crosslist_code == "0",
      NA_character_, crosslist_code
    ))

  # crosslist_primary: marks the "home" section for each crosslist group.
  # Non-crosslisted sections are always primary (TRUE).
  # For crosslisted groups, home is determined by:
  #   1. SHORT_TEXT field (pattern "[SUBJECT] home [TERM]") — most reliable signal.
  #   2. Fallback: section with highest section-level enrollment; ties broken by subject.

  cedar_sections <- cedar_sections %>%
    mutate(
      .xl_home_subj = ifelse(
        !is.na(xl_home_text) & grepl("^[A-Z]+ home ", xl_home_text, ignore.case = TRUE),
        sub("^([A-Z]+) home .*", "\\1", xl_home_text, ignore.case = TRUE),
        NA_character_
      )
    )

  xl_primary_by_text <- cedar_sections %>%
    filter(!is.na(crosslist_group), !is.na(.xl_home_subj), subject == .xl_home_subj) %>%
    group_by(term, campus, crosslist_group) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    pull(section_id)

  xl_groups_needing_fallback <- cedar_sections %>%
    filter(!is.na(crosslist_group)) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(has_text_primary = any(section_id %in% xl_primary_by_text), .groups = "drop") %>%
    filter(!has_text_primary) %>%
    select(term, campus, crosslist_group)

  xl_primary_by_enrl <- cedar_sections %>%
    semi_join(xl_groups_needing_fallback, by = c("term", "campus", "crosslist_group")) %>%
    group_by(term, campus, crosslist_group) %>%
    arrange(desc(enrolled), subject, .by_group = TRUE) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    pull(section_id)

  cedar_sections <- cedar_sections %>%
    mutate(
      crosslist_primary = is.na(crosslist_group) |
        section_id %in% xl_primary_by_text |
        section_id %in% xl_primary_by_enrl,
      crosslist_role = case_when(
        is.na(crosslist_group) ~ NA_character_,
        crosslist_primary      ~ "home",
        TRUE                   ~ "partner"
      )
    ) %>%
    select(-.xl_home_subj, -xl_home_text)

  # Internal crosslists: all sections share the same subject (e.g., STAT 427 / STAT 527).
  # Mark all as "internal" so the home filter keeps all of them.
  xl_internal_groups <- cedar_sections %>%
    filter(!is.na(crosslist_group)) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(n_subjects = dplyr::n_distinct(subject), .groups = "drop") %>%
    filter(n_subjects == 1) %>%
    select(term, campus, crosslist_group)

  cedar_sections <- cedar_sections %>%
    left_join(xl_internal_groups %>% mutate(.is_internal = TRUE),
              by = c("term", "campus", "crosslist_group")) %>%
    mutate(
      crosslist_role = if_else(
        coalesce(.is_internal, FALSE) & !is.na(crosslist_group),
        "internal", crosslist_role
      )
    ) %>%
    select(-.is_internal)

  # is_split: crosslist groups spanning the undergrad/grad boundary.
  # Preserves original level (upper/grad) rather than overwriting to "split".
  split_groups <- cedar_sections %>%
    filter(!is.na(crosslist_group)) %>%
    distinct(term, campus, crosslist_group, section_id, level) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(
      .is_split = any(level %in% c("lower", "upper")) & any(level == "grad"),
      .groups = "drop"
    ) %>%
    filter(.is_split) %>%
    select(term, campus, crosslist_group)

  cedar_sections <- cedar_sections %>%
    left_join(split_groups %>% mutate(.is_split = TRUE),
              by = c("term", "campus", "crosslist_group")) %>%
    mutate(is_split = coalesce(.is_split, FALSE)) %>%
    select(-.is_split)

  split_labels <- cedar_sections %>%
    filter(is_split) %>%
    distinct(term, campus, crosslist_group, subject_course) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(split_sections = paste(sort(subject_course), collapse = " / "), .groups = "drop")

  cedar_sections <- cedar_sections %>%
    left_join(split_labels, by = c("term", "campus", "crosslist_group")) %>%
    mutate(split_sections = coalesce(split_sections, NA_character_))

  # Sanitize course_title: Banner exports occasionally contain invalid UTF-8 bytes.
  cedar_sections <- cedar_sections %>%
    mutate(course_title = iconv(course_title, from = "UTF-8", to = "UTF-8", sub = "?"))

  # is_topics: TRUE if course_title begins with "T:" (Banner convention for rotating-topics slots).
  cedar_sections <- cedar_sections %>%
    mutate(is_topics = grepl("^T:", trimws(course_title)))

  # Deduplicate: DESR source has one row per crosslist partner; collapse to one row per section.
  n_before_dedup <- nrow(cedar_sections)
  cedar_sections <- cedar_sections %>% distinct(section_id, .keep_all = TRUE)

  # crosslist_external: TRUE if crosslist group involves sections from multiple departments.
  xlist_dept_scope <- cedar_sections %>%
    filter(!is.na(crosslist_group)) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(crosslist_external = n_distinct(department) > 1, .groups = "drop")
  cedar_sections <- cedar_sections %>%
    left_join(xlist_dept_scope, by = c("term", "campus", "crosslist_group"))

  # crosslist_partners: all subject_course values in the same external crosslist group.
  xl_partner_labels <- cedar_sections %>%
    filter(!is.na(crosslist_group), coalesce(crosslist_external, FALSE)) %>%
    distinct(term, campus, crosslist_group, subject_course) %>%
    group_by(term, campus, crosslist_group) %>%
    summarize(crosslist_partners = paste(sort(subject_course), collapse = " / "), .groups = "drop")
  cedar_sections <- cedar_sections %>%
    left_join(xl_partner_labels, by = c("term", "campus", "crosslist_group")) %>%
    mutate(crosslist_partners = coalesce(crosslist_partners, NA_character_))

  message("  ✅ Crosslist groups detected: ",
          n_distinct(na.omit(cedar_sections$crosslist_group)), " groups")
  message("  ✅   Primaries resolved via SHORT_TEXT: ", length(xl_primary_by_text))
  message("  ✅   Primaries resolved via enrollment fallback: ", length(xl_primary_by_enrl))
  message("  ✅ Split-level groups: ", nrow(split_groups))
  message("  ✅ Deduplicated: ", n_before_dedup, " → ", nrow(cedar_sections),
          " rows (", n_before_dedup - nrow(cedar_sections), " partner-expansion duplicates removed)")
  message("  ✅ Created cedar_sections: ", nrow(cedar_sections), " rows, ", ncol(cedar_sections), " columns")
  message("  Output columns: ", paste(names(cedar_sections), collapse = ", "))

  # Units come from the mapping files: stamp which files, so the rebuild gate
  # can tell when they move (ISSUES.md M26), as for cedar_programs.
  attr(cedar_sections, "cedar_mapping_provenance") <- cedar_mapping_provenance()
  saved_meta <- save_cedar_file(cedar_sections, "sections", data_dir, ext)

  # Slim to only the columns build_lookups needs (subject_lookup).
  # Avoids holding 30+ cols × all rows in memory through all subsequent transforms.
  sections_for_lookups <- cedar_sections %>%
    distinct(subject, department, college) %>%
    filter(!is.na(subject), subject != "", !is.na(department), department != "")
  rm(cedar_sections); gc(verbose = FALSE)

  list(saved = list(sections = saved_meta), table = sections_for_lookups)
}


# ── 2. transform_students: class_lists → cedar_students ──────────────────────

#' @param class_lists Raw class_lists data frame (output of parse-data.R)
#' @param data_dir    Path to data directory
#' @param ext         File extension
#' @param maps        Named list of lookup vectors
#' @return list(saved = list(students, grades, student_term_credits, next_term), major_code_name_raw)
transform_students <- function(class_lists, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("2. Transforming class_lists → cedar_students")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(class_lists), " rows, ", ncol(class_lists), " columns")
  message("  Input columns: ", paste(names(class_lists), collapse = ", "))

  major_name_to_major_code <- maps$major_name_to_major_code

  # ── Pre-processing ────────────────────────────────────────────────────────
  message("  Pre-processing: deriving helper columns...")

  # Capture Major Code → name mapping from the full frame before any slimming.
  if ("Major Code" %in% names(class_lists) && "Major" %in% names(class_lists)) {
    major_code_name_raw <- class_lists %>%
      dplyr::select(`Major Code`, `Major`, as_of_date) %>%
      dplyr::filter(!is.na(`Major Code`), `Major Code` != "",
                    !is.na(`Major`),      `Major`      != "") %>%
      dplyr::arrange(dplyr::desc(as_of_date)) %>%
      dplyr::distinct(`Major Code`, .keep_all = TRUE) %>%
      dplyr::select(`Major Code`, `Major`)
    message("  Captured ", nrow(major_code_name_raw), " major code → name pairs for cedar_lookups")
  } else {
    stop("[transform_students] 'Major Code' and/or 'Major' columns absent from class lists export. ",
         "These are required to build cedar_lookups. Check the Banner class list export format.")
  }

  # Slim early: drop unused columns before mutations so all subsequent operations
  # work on a smaller frame. Subject Code and Course Number are kept for the unite below.
  class_lists <- class_lists %>%
    dplyr::select(dplyr::any_of(c(
      "Academic Period Code", "Course Reference Number", "Student ID",
      "Subject Code", "Course Number", "Short Course Title",
      "Primary Instructor ID", "Primary Instructor Last Name", "Primary Instructor First Name",
      "Course Campus Code", "Course College Code",
      "Registration Status", "Registration Status Code", "Registration Status Date",
      "Final Grade", "Course Credits", "Total Credits",
      "Student Level Code", "Student Classification", "Major Code", "Major",
      "Student College Code", "Student Campus Code",
      "Sub-Academic Period Code", "Residency", "Dual Credit",
      "as_of_date"
    )))
  gc(verbose = FALSE)
  message("  Slimmed class_lists to ", ncol(class_lists), " columns before pre-processing")

  if ("Subject Code" %in% names(class_lists) && "Course Number" %in% names(class_lists)) {
    class_lists <- class_lists %>%
      unite(SUBJ_CRSE, c("Subject Code", "Course Number"), sep = " ", remove = FALSE)
  }

  if ("Academic Period Code" %in% names(class_lists)) {
    class_lists <- class_lists %>%
      mutate(term_type = dplyr::case_when(
        substr(as.character(`Academic Period Code`), 5, 6) == "80" ~ "fall",
        substr(as.character(`Academic Period Code`), 5, 6) == "10" ~ "spring",
        substr(as.character(`Academic Period Code`), 5, 6) == "60" ~ "summer",
        TRUE ~ NA_character_
      ))
  }

  if ("Subject Code" %in% names(class_lists)) {
    # Unit from subjects.csv, as for sections (ADR-002): no confirmed row, no
    # unit -- never a department named after the subject.
    # The course level is derived once here, and reused for the level column
    # below: one classifier, called once per course table (ISSUES.md I5).
    files <- .require_mapping_files(maps, "transform_students", c("subjects", "units", "colleges"))
    class_lists$COURSE_LEVEL <- course_level_from_number(class_lists$SUBJ_CRSE)
    course_units <- resolve_course_units(
      class_lists$`Subject Code`, class_lists$`Course College Code`,
      class_lists$COURSE_LEVEL, files)
    class_lists$DEPT <- course_units$unit_code
    course_colleges <- .course_colleges(course_units, class_lists$`Course College Code`, files)
    class_lists$COURSE_COLLEGE <- course_colleges$college
    class_lists$COLLEGE_BASIS  <- course_colleges$college_basis
    rm(course_units, course_colleges)
  }

  # Drop Subject Code and Course Number (now encoded in SUBJ_CRSE); keep transmute inputs.
  class_lists <- class_lists %>%
    dplyr::select(dplyr::any_of(c(
      "Academic Period Code", "Course Reference Number", "Student ID",
      "SUBJ_CRSE", "Short Course Title",
      "Primary Instructor ID", "Primary Instructor Last Name", "Primary Instructor First Name",
      "Course Campus Code", "Course College Code", "DEPT", "COURSE_LEVEL",
      "COURSE_COLLEGE", "COLLEGE_BASIS",
      "Registration Status", "Registration Status Code", "Registration Status Date",
      "Final Grade", "Course Credits", "Total Credits",
      "Student Level Code", "Student Classification", "Major Code", "Major",
      "Student College Code", "Student Campus Code",
      "Sub-Academic Period Code", "Residency", "Dual Credit",
      "term_type", "level", "as_of_date"
    )))
  gc(verbose = FALSE)
  message("  Slimmed class_lists to ", ncol(class_lists), " columns before transmute")

  message("  Transforming to CEDAR model...")

  cedar_students <- class_lists %>% transmute(
      enrollment_id  = row_number(),
      crn            = as.character(`Course Reference Number`),
      student_id     = encrypt_if_needed(`Student ID`),
      term           = as.integer(`Academic Period Code`),
      subject_course = SUBJ_CRSE,
      subject_code   = sub(" .*", "", SUBJ_CRSE),
      course_title   = if ("Short Course Title" %in% names(.)) `Short Course Title` else NA_character_,
      level = dplyr::coalesce(COURSE_LEVEL, "unknown"),
      instructor_id         = if ("Primary Instructor ID"         %in% names(.)) `Primary Instructor ID`         else NA_character_,
      instructor_last_name  = if ("Primary Instructor Last Name"  %in% names(.)) `Primary Instructor Last Name`  else NA_character_,
      instructor_first_name = if ("Primary Instructor First Name" %in% names(.)) `Primary Instructor First Name` else NA_character_,
      instructor_name = case_when(
        !is.na(instructor_last_name) & !is.na(instructor_first_name) ~ paste0(instructor_last_name, ", ", instructor_first_name),
        !is.na(instructor_last_name) ~ instructor_last_name,
        TRUE ~ NA_character_
      ),
      campus     = `Course Campus Code`,
      # The mapped college (Stage 3b); Banner's own value stays beside it.
      college        = COURSE_COLLEGE,
      source_college = `Course College Code`,
      college_basis  = COLLEGE_BASIS,
      department = if ("DEPT" %in% names(.)) DEPT else Department,
      registration_status      = `Registration Status`,
      registration_status_code = `Registration Status Code`,
      registration_date = if ("Registration Status Date" %in% names(.)) {
        as.Date(`Registration Status Date`, format = "%m/%d/%Y")
      } else NA_Date_,
      final_grade   = `Final Grade`,
      credits       = if ("Course Credits" %in% names(.)) as.numeric(`Course Credits`) else NA_real_,
      total_credits = if ("Total Credits"  %in% names(.)) as.numeric(`Total Credits`)  else NA_real_,
      student_level          = `Student Level Code`,
      student_classification = `Student Classification`,
      # major_code: Banner code (e.g., HIST) — join key across tables.
      # major_name: Banner display name (e.g., "History") — carried forward from "Major" column.
      # NOTE: cedar_degrees$major holds the major NAME; cedar_degrees$major_code is the join key.
      major_code     = if ("Major Code" %in% names(.)) `Major Code` else NA_character_,
      major_name     = if ("Major"      %in% names(.)) `Major`      else NA_character_,
      student_college = `Student College Code`,
      student_campus  = `Student Campus Code`,
      term_type  = if ("term_type"          %in% names(.)) term_type          else NA_character_,
      residency  = if ("Residency"          %in% names(.)) Residency          else NA_character_,
      dual_credit = if ("Dual Credit"       %in% names(.)) (`Dual Credit` == "Y") else NA,
      part_term  = if ("Sub-Academic Period Code" %in% names(.)) `Sub-Academic Period Code` else NA_character_,
      as_of_date = as.Date(as_of_date)
    ) %>%
    # The component name fields are only needed to construct instructor_name.
    # Keeping all three strings on ~1.7M rows adds substantial runtime memory.
    select(-instructor_last_name, -instructor_first_name)

  # ── cedar_grades ─────────────────────────────────────────────────────────
  # Built from pre-dedup cedar_students (CRN-level) so topics courses sharing
  # a subject_course code are preserved as separate rows.
  # Outcome classification is the canonical CEDAR pass/DFW policy from
  # classify_enrollment_outcomes() (trunk/utils.R): A+ through C and CR pass;
  # every other recorded non-audit outcome plus non-audit late drops is DFW. Early drops
  # are NEVER DFW (see AGENTS.md, "CEDAR-wide DFW policy").
  message("  Computing cedar_grades (pre-classified outcomes, CRN-level dedup)...")
  # classify first (it restricts to registered + late-drop rows), THEN dedup —
  # otherwise an excluded row (e.g. an early drop) could win the CRN dedup and
  # shadow the student's real outcome row.
  #
  # Dedup key MUST include term: Banner recycles CRNs across terms, so a retake
  # of a course under a recycled CRN is a distinct outcome, not a duplicate
  # (~20k student-crn pairs span multiple terms in real data).
  #
  # Tie-break within (student, crn, term): a late-drop row wins over a
  # coexisting registered row — the withdrawal is the outcome of record.
  # arrange() makes the previously data-order-dependent choice deterministic.
  cedar_grades_tbl <- cedar_students %>%
    classify_enrollment_outcomes() %>%
    arrange(student_id, term, crn,
            desc(registration_status_code %in% STATUS_DROP_LATE)) %>%
    distinct(student_id, crn, term, .keep_all = TRUE) %>%
    select(student_id, term, subject_course, outcome, campus, level)
  # Stamp only newly classified rows. Consumers reject unversioned/old artifacts
  # because the saved table no longer carries the raw grade/status needed to fix it.
  attr(cedar_grades_tbl, "cedar_outcome_policy_version") <- CEDAR_OUTCOME_POLICY_VERSION
  grades_meta <- save_cedar_file(cedar_grades_tbl, "grades", data_dir, ext)
  message("  ✅ cedar_grades: ", nrow(cedar_grades_tbl), " rows, ", ncol(cedar_grades_tbl), " columns")
  rm(cedar_grades_tbl)

  # Deduplicate: Banner emits one row per CRN, so students in combined courses
  # (e.g. BIOL 302C = lecture CRN + lab CRN) appear twice. Keep one row per
  # student-course-campus per term. Campus is part of delivery identity: the
  # same student can legitimately take the same course at two campuses.
  # cedar_grades is computed above (pre-dedup) to preserve topics enrollments.
  #
  # Tie-break within (student, term, campus, course): a registered row wins over
  # a coexisting waitlist row — a student holding a seat is enrolled, not
  # waiting. Same reasoning as the cedar_grades dedup above: arrange() makes a
  # previously data-order-dependent choice deterministic. Without it the WL row
  # could win and delete the evidence that the student ever registered, which is
  # exactly what the class-list waitlist-demand rule needs in order to exclude
  # them (R/branches/waitlist-demand.R). Rare but real: 7 student-course-campus
  # terms in the current data hold both statuses.
  n_before_dedup <- nrow(cedar_students)
  cedar_students <- cedar_students %>%
    arrange(student_id, term, campus, subject_course,
            desc(registration_status_code %in% STATUS_REGISTERED)) %>%
    distinct(student_id, term, campus, subject_course, .keep_all = TRUE)
  n_removed <- n_before_dedup - nrow(cedar_students)
  if (n_removed > 0)
    message("  Removed ", n_removed, " duplicate section rows (combined lecture+lab courses)")

  # Fill missing major_codes via name → code map
  if (length(major_name_to_major_code) > 0) {
    cedar_students <- cedar_students %>%
      dplyr::mutate(
        major_code = dplyr::if_else(
          is.na(major_code) & !is.na(major_name) & nzchar(major_name),
          major_name_to_major_code[stringr::str_trim(
            sub("^Pre[- ]+", "", major_name, ignore.case = TRUE)
          )],
          major_code
        )
      )
  }

  message("  ✅ Created cedar_students: ", nrow(cedar_students), " rows, ", ncol(cedar_students), " columns")
  message("  Output columns: ", paste(names(cedar_students), collapse = ", "))
  rm(class_lists); gc(verbose = FALSE)

  # Units come from the mapping files: stamp which files, so the rebuild gate
  # can tell when they move (ISSUES.md M26), as for cedar_programs.
  attr(cedar_students, "cedar_mapping_provenance") <- cedar_mapping_provenance()
  students_meta <- save_cedar_file(cedar_students, "students", data_dir, ext)

  # ── cedar_student_term_credits ────────────────────────────────────────────
  # Observed UNM-only credits from class lists, one row per student-term.
  # These are derived from course rows instead of Academic Studies cumulative
  # credit fields, which can repeat current totals backward across old program
  # records. Attempted credits include registered enrollments with a credit value;
  # completed credits use the canonical grade set that earns credit hours.
  message("  Computing cedar_student_term_credits (observed class-list credits)...")
  cedar_student_term_credits_tbl <- cedar_students %>%
    filter(
      registration_status_code %in% STATUS_REGISTERED,
      !is.na(credits)
    ) %>%
    # CAMPUS_ROLLUP: this is one curriculum credit load per student-term, not a
    # delivery metric. A repeated course counts once even if campus changed.
    distinct(student_id, term, subject_course, course_title, credits,
             final_grade, registration_status_code) %>%
    mutate(
      attempted_credit = credits,
      completed_credit = if_else(final_grade %in% passing_grades, credits, 0),
      dfw_credit = if_else(
        !is.na(final_grade) & nzchar(final_grade) &
          !final_grade %in% c(GRADES_PASS, GRADES_EXCLUDED_FROM_OUTCOMES),
        credits,
        0
      ),
      w_credit = if_else(final_grade == "W", credits, 0),
      completed_course = final_grade %in% passing_grades
    ) %>%
    group_by(student_id, term) %>%
    summarize(
      attempted_unm_credits = sum(attempted_credit, na.rm = TRUE),
      completed_unm_credits = sum(completed_credit, na.rm = TRUE),
      dfw_unm_credits = sum(dfw_credit, na.rm = TRUE),
      w_unm_credits = sum(w_credit, na.rm = TRUE),
      registered_courses = n_distinct(subject_course),
      completed_courses = sum(completed_course, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(student_id, term) %>%
    group_by(student_id) %>%
    mutate(
      cumulative_attempted_unm_credits = cumsum(attempted_unm_credits),
      cumulative_completed_unm_credits = cumsum(completed_unm_credits),
      cumulative_dfw_unm_credits = cumsum(dfw_unm_credits),
      cumulative_w_unm_credits = cumsum(w_unm_credits)
    ) %>%
    ungroup()
  student_term_credits_meta <- save_cedar_file(
    cedar_student_term_credits_tbl, "student_term_credits", data_dir, ext
  )
  message("  ✅ cedar_student_term_credits: ", nrow(cedar_student_term_credits_tbl), " rows, ",
          ncol(cedar_student_term_credits_tbl), " columns")
  rm(cedar_student_term_credits_tbl)

  # ── cedar_next_term ───────────────────────────────────────────────────────
  # Pre-compute the student × term → returned_next_term lookup once,
  # so Roadblocks doesn't rebuild it from raw enrollment rows on every query.
  message("  Computing cedar_next_term (return lookup)...")
  # A return means census participation: registered rows plus late drops, which
  # were enrolled at census. Waitlists and early drops are not enrollment.
  student_terms_tbl <- cedar_students %>%
    filter(registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)) %>%
    select(student_id, term) %>%
    distinct()
  rm(cedar_students); gc(verbose = FALSE)
  cedar_next_term_tbl <- student_terms_tbl %>%
    add_next_term_col("term", summer = FALSE) %>%
    left_join(
      student_terms_tbl %>% rename(next_term = term) %>% mutate(returned = TRUE),
      by = c("student_id", "next_term")
    ) %>%
    mutate(returned_next_term = !is.na(returned)) %>%
    select(student_id, term, returned_next_term)
  next_term_meta <- save_cedar_file(cedar_next_term_tbl, "next_term", data_dir, ext)
  message("  ✅ cedar_next_term: ", nrow(cedar_next_term_tbl), " rows")
  rm(student_terms_tbl, cedar_next_term_tbl)

  list(
    saved = list(
      students = students_meta,
      grades = grades_meta,
      student_term_credits = student_term_credits_meta,
      next_term = next_term_meta
    ),
    major_code_name_raw = major_code_name_raw
  )
}


# ── 3. transform_programs: academic_studies → cedar_programs ─────────────────

#' @param academic_studies Raw academic_studies data frame
#' @param data_dir         Path to data directory
#' @param ext              File extension
#' @param maps             Named list of lookup vectors
#' @return list(saved = list(programs = <meta>), table = cedar_programs)
transform_programs <- function(academic_studies, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("3. Transforming academic_studies → cedar_programs")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(academic_studies), " rows, ", ncol(academic_studies), " columns")
  message("  Input columns: ", paste(names(academic_studies), collapse = ", "))

  files                    <- .require_mapping_files(maps, "transform_programs", c("programs", "units", "colleges"))
  major_name_to_major_code <- maps$major_name_to_major_code

  # ── Pre-processing: derive term ───────────────────────────────────────────
  message("  Pre-processing: deriving helper columns...")

  if ("Academic Period" %in% names(academic_studies)) {
    academic_studies <- academic_studies %>%
      dplyr::mutate(term_code = as.character(academic_period_to_term(`Academic Period`)))
    n_ok  <- sum(!is.na(academic_studies$term_code))
    n_bad <- sum( is.na(academic_studies$term_code))
    message("  ✅ term_code derived from 'Academic Period': ", n_ok, " rows OK",
            if (n_bad > 0) paste0(", ", n_bad, " NA (unrecognised labels)") else "")
  } else if ("term_code" %in% names(academic_studies) &&
             any(!is.na(academic_studies$term_code))) {
    message("  term_code column present and non-empty — using as-is")
  } else {
    stop("  Cannot derive term: 'Academic Period' column missing and no usable term_code column")
  }

  message("  Transforming to CEDAR model (pivot_longer wide → long)...")

  # Slim to only columns used in the base transmute and prog_pairs map below.
  academic_studies <- academic_studies %>%
    dplyr::select(dplyr::any_of(c(
      "term_code", "ID", "Program Classification", "Degree", "Student Classification",
      "Student Level", "Student Campus", "Translated College", "Actual College",
      "Student Population", "Institution Credits Attempted",
      "Institution Credits Earned",
      "Overall Credits Attempted", "Overall Credits Earned",
      # Per-term credit load. Unlike the cumulative columns beside them these
      # are genuine per-term values and survive a re-pull — see the field
      # reliability contract in AGENTS.md. They are what the trustworthy
      # cumulative series is built from.
      "Semester Credits Attempted", "Semester Credits Earned", "Semester GPA",
      "Pell Eligible Indicator", "First Generation Indicator", "IPEDS Race", "Gender",
      "Current Time Status Code", "Residency", "Academic Standing", "Institution GPA",
      "as_of_date",
      "Major Code", "Second Major Code", "First Minor Code", "Second Minor Code",
      "Major", "Second Major", "First Minor", "Second Minor",
      "First Concentration", "Second Concentration", "Third Concentration",
      "Program Code"
    )))
  gc(verbose = FALSE)
  message("  Slimmed academic_studies to ", ncol(academic_studies), " columns")

  # Program name columns and their corresponding code columns (paired)
  prog_pairs <- list(
    list(type = "Major",                name_col = "Major",                code_col = "Major Code",        prog_code_col = "Program Code"),
    list(type = "Second Major",         name_col = "Second Major",         code_col = "Second Major Code"),
    list(type = "First Minor",          name_col = "First Minor",          code_col = "First Minor Code"),
    list(type = "Second Minor",         name_col = "Second Minor",         code_col = "Second Minor Code"),
    list(type = "First Concentration",  name_col = "First Concentration",  code_col = NULL),
    list(type = "Second Concentration", name_col = "Second Concentration", code_col = NULL),
    list(type = "Third Concentration",  name_col = "Third Concentration",  code_col = NULL)
  )

  academic_studies_base <- academic_studies %>%
    transmute(
      student_id             = encrypt_if_needed(ID),
      term                   = as.integer(term_code),
      program_classification = `Program Classification`,
      degree                 = Degree,
      student_classification = `Student Classification`,
      student_level          = `Student Level`,
      student_campus         = `Student Campus`,
      student_college        = `Translated College`,
      # Banner's Actual College as a code, through colleges.csv (its names and
      # source_names), so a renamed college still resolves.
      college_code           = translate_source_college(`Actual College`, files),
      student_population     = if ("Student Population"             %in% names(.)) `Student Population`             else NA_character_,
      # ── Cumulative credit hours — NOT a per-term series ────────────────────
      # Reported by Academic Studies as running totals AS OF THE PULL, stamped
      # identically onto every historical row the report returns. Within a single
      # full historical re-pull they move across a student's own terms only 16%
      # of the time; the per-term columns below move 98% of the time. See the
      # field reliability contract in AGENTS.md before using these for anything
      # keyed on term — they are a current snapshot, not history.
      #   inst_*    = UNM-only hours; overall_* = UNM + transfer hours.
      inst_credits_attempted    = if ("Institution Credits Attempted" %in% names(.)) as.numeric(`Institution Credits Attempted`) else NA_real_,
      inst_credits_earned       = if ("Institution Credits Earned"    %in% names(.)) as.numeric(`Institution Credits Earned`)    else NA_real_,
      overall_credits_attempted = if ("Overall Credits Attempted"     %in% names(.)) as.numeric(`Overall Credits Attempted`)     else NA_real_,
      overall_credits_earned    = if ("Overall Credits Earned"        %in% names(.)) as.numeric(`Overall Credits Earned`)        else NA_real_,
      # ── Per-term credit load — safe for term-keyed claims ─────────────────
      sem_credits_attempted     = if ("Semester Credits Attempted" %in% names(.)) as.numeric(`Semester Credits Attempted`) else NA_real_,
      sem_credits_earned        = if ("Semester Credits Earned"    %in% names(.)) as.numeric(`Semester Credits Earned`)    else NA_real_,
      sem_gpa                   = if ("Semester GPA"               %in% names(.)) as.numeric(`Semester GPA`)               else NA_real_,
      pell_eligible = if ("Pell Eligible Indicator"   %in% names(.)) dplyr::if_else(`Pell Eligible Indicator`   == "Y",   TRUE, FALSE, missing = NA) else NA,
      first_gen     = if ("First Generation Indicator" %in% names(.)) dplyr::if_else(`First Generation Indicator` == "Yes", TRUE, FALSE, missing = NA) else NA,
      ipeds_race    = if ("IPEDS Race"                 %in% names(.)) `IPEDS Race` else NA_character_,
      gender        = if ("Gender"                     %in% names(.)) Gender       else NA_character_,
      time_status   = if ("Current Time Status Code"   %in% names(.)) `Current Time Status Code` else NA_character_,
      residency         = if ("Residency"         %in% names(.)) `Residency`         else NA_character_,
      academic_standing = if ("Academic Standing" %in% names(.)) `Academic Standing` else NA_character_,
      inst_gpa          = if ("Institution GPA"   %in% names(.)) as.numeric(`Institution GPA`) else NA_real_,
      as_of_date         = as.Date(as_of_date),
      dplyr::across(dplyr::any_of(c("Major Code", "Second Major Code", "First Minor Code", "Second Minor Code")))
    )

  cedar_programs <- purrr::map(prog_pairs, function(p) {
    name_col <- p$name_col
    if (!name_col %in% names(academic_studies)) return(NULL)
    df <- academic_studies_base
    df$program_name <- academic_studies[[name_col]]
    df$major_code   <- if (!is.null(p$code_col) && p$code_col %in% names(academic_studies))
                         academic_studies[[p$code_col]] else NA_character_
    df$program_code <- if (!is.null(p$prog_code_col) && p$prog_code_col %in% names(academic_studies))
                         academic_studies[[p$prog_code_col]] else NA_character_
    df %>%
      filter(!is.na(program_name), program_name != "") %>%
      transmute(
        student_id, term,
        program_type = p$type,
        program_name,
        major_code   = as.character(major_code),
        program_code,
        program_classification, degree,
        student_classification, student_level, student_campus, student_college, college_code,
        student_population, inst_credits_attempted, inst_credits_earned,
        overall_credits_attempted, overall_credits_earned,
        sem_credits_attempted, sem_credits_earned, sem_gpa,
        pell_eligible, first_gen, ipeds_race, gender, time_status,
        residency, academic_standing, inst_gpa,
        as_of_date
      )
  }) %>%
    purrr::compact() %>%
    dplyr::bind_rows() %>%
    # Fill missing major_codes via name → code map before dept lookup.
    # Concentrations (code_col = NULL) and some older formats lack a Banner code column.
    # Strip "Pre-" prefix so "Pre-History" resolves the same as "History".
    dplyr::mutate(
      # unname(): the lookup's names otherwise ride along on the whole column,
      # and a named column reaches the browser as a JSON object, not an array.
      major_code = unname(dplyr::if_else(
        is.na(major_code) & !is.na(program_name) & nzchar(program_name),
        major_name_to_major_code[stringr::str_trim(
          sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)
        )],
        major_code
      ))
    ) %>%
    dplyr::mutate(
      # Unit from programs.csv (ADR-002): the confirmed row for (code, college)
      # if there is one, else the code's every-college row. One tier. A code
      # with no confirmed row -- including a Banner organisation ID leaked into
      # the major code column -- has no unit, never a department named after
      # itself (ISSUES.md I7). Concentrations are resolved below.
      dept_code = resolve_program_units(major_code, college_code, files$programs),
      # is_pre_major comes from programs.csv, stated per code (ADR-002 Stage 4),
      # not inferred from an F prefix. Banner's own program records name every
      # F and XF code the old rule exempted or missed "Pre-" (BS Pre-Exercise
      # Science, BBA Pre-Business Admin), and the branch "Pre-" programs (AS
      # Pre-Engineering) are associate degrees students are admitted to, so not
      # pre-majors (reviewed 2026-10-10). A code with no programs.csv row falls
      # back to Banner's own word, a "Pre-" program name, and says so in
      # pre_major_basis.
      .pre_in_file = program_pre_major_flags(major_code, files$programs),
      .pre_by_name = grepl("^Pre[- ]", program_name, ignore.case = TRUE),
      # PHRD was the code for undergraduate pre-pharmacy before 202580 (FPHS
      # since): a row-level fact a per-code flag cannot state. Recorded in
      # CEDAR_DATA_SEMANTICS as phrd-undergraduate-pre-pharmacy.
      .pre_by_phrd = major_code %in% "PHRD" & student_level %in% c("UG", "NG"),
      is_pre_major = dplyr::case_when(
        .pre_by_phrd         ~ TRUE,
        !is.na(.pre_in_file) ~ .pre_in_file,
        TRUE                 ~ .pre_by_name),
      # Why the flag is set, so it can be traced to its source.
      pre_major_basis = dplyr::case_when(
        !is_pre_major        ~ NA_character_,
        .pre_by_phrd         ~ "phrd_undergraduate",
        !is.na(.pre_in_file) ~ "programs_csv",
        TRUE                 ~ "name_prefix"
      ),
      # Strip "Pre-" prefix from program_name for clean display
      program_name = dplyr::if_else(
        grepl("^Pre[- ]", program_name, ignore.case = TRUE),
        stringr::str_trim(sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)),
        program_name
      ),
      # Normalize variant/historical Banner names to canonical display names.
      # Catches X-prefix variants and program renames that left a different text
      # string in the Major column even though the dept resolves correctly.
      # unname(): as for major_code above, the lookup's names would otherwise
      # ride along on the whole column.
      program_name = unname(dplyr::coalesce(
        program_name_aliases[program_name],
        program_name
      ))
    ) %>%
    # Working columns; pre_major_basis carries what they decided.
    dplyr::select(-dplyr::any_of(c(".pre_in_file", ".pre_by_name", ".pre_by_phrd")))

  # Concentrations take the unit of the student's primary major that term
  # (ADR-002): a concentration sits under a major, and matching its name to a
  # major's instead lent PADM Political Science students (ISSUES.md I11). A
  # student-term with two primary-major rows takes the first by major code, so
  # the choice does not depend on row order.
  primary_unit <- cedar_programs %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::arrange(student_id, term, major_code) %>%
    dplyr::distinct(student_id, term, .keep_all = TRUE) %>%
    dplyr::select(student_id, term, .primary_unit = dept_code)
  cedar_programs <- cedar_programs %>%
    dplyr::left_join(primary_unit, by = c("student_id", "term")) %>%
    dplyr::mutate(dept_code = dplyr::if_else(grepl("Concentration", program_type),
                                             .primary_unit, dept_code)) %>%
    dplyr::select(-".primary_unit")

  cedar_programs <- add_program_colleges(cedar_programs, files)

  # Warn about Major/Second Major rows with no major_code
  still_no_code <- cedar_programs %>%
    dplyr::filter(program_type %in% c("Major", "Second Major"),
                  is.na(major_code), !is.na(program_name), nzchar(program_name)) %>%
    dplyr::distinct(program_type, program_name) %>%
    dplyr::arrange(program_type, program_name)
  if (nrow(still_no_code) > 0) {
    message("  ⚠️  ", nrow(still_no_code),
            " Major/Second Major row(s) have no major_code — Banner code column may be missing:")
    for (i in seq_len(nrow(still_no_code)))
      message("      [", still_no_code$program_type[i], "] ", still_no_code$program_name[i])
  }

  na_dept_prgm <- cedar_programs %>%
    filter(is.na(dept_code), program_type == "Major") %>%
    distinct(major_code) %>% pull(major_code)
  if (length(na_dept_prgm) > 0)
    message("  ⚠️  Major rows with NA dept_code: ",
            format(length(na_dept_prgm), big.mark = ","), " distinct values: ",
            paste(na_dept_prgm[1:min(5, length(na_dept_prgm))], collapse = ", "))

  message("  ✅ Created cedar_programs: ", nrow(cedar_programs), " rows, ", ncol(cedar_programs), " columns")
  message("  Output columns: ", paste(names(cedar_programs), collapse = ", "))
  message("  Program type breakdown:")
  for (pt in unique(cedar_programs$program_type))
    message("     ", pt, ": ", sum(cedar_programs$program_type == pt))

  # Stamp the mapping source that produced these departments, so a later deploy
  # can tell whether this table was built by the code that is now deployed. The
  # gap between editing a mapping list and rebuilding the table is invisible
  # otherwise: dept_code stays plausible and every report keeps using it.
  # Unconditional: a guard here once skipped the stamp silently whenever the
  # transform ran as a script, and every refresh then read as STALE (ISSUES.md I13).
  attr(cedar_programs, "cedar_mapping_provenance") <- cedar_mapping_provenance()
  saved_meta <- save_cedar_file(cedar_programs, "programs", data_dir, ext)

  # Slim to only the columns build_lookups needs.
  # Avoids holding 25+ cols × millions of rows through all subsequent transforms.
  programs_for_lookups <- cedar_programs %>%
    distinct(program_name, dept_code, major_code, college_code) %>%
    filter(!is.na(program_name), program_name != "")
  rm(cedar_programs); gc(verbose = FALSE)

  list(saved = list(programs = saved_meta), table = programs_for_lookups)
}


# ── 4. transform_degrees: degrees → cedar_degrees ────────────────────────────

#' @param degrees  Raw degrees data frame
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @param maps     Named list of lookup vectors
#' @return list(saved = list(degrees = <meta>))
transform_degrees <- function(degrees, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("4. Transforming degrees → cedar_degrees")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(degrees), " rows, ", ncol(degrees), " columns")
  message("  Input columns: ", paste(names(degrees), collapse = ", "))
  message("  Transforming to CEDAR model...")

  files                 <- .require_mapping_files(maps, "transform_degrees", c("programs", "units", "colleges"))

  required_cols <- c("Major", "Program Code", "Academic Period Code", "ID", "Degree", "Graduation Status")
  missing_cols  <- setdiff(required_cols, names(degrees))
  if (length(missing_cols) > 0)
    stop("[transform_degrees] Required columns missing from degrees export: ",
         paste(missing_cols, collapse = ", "), ". Check the Banner degrees export format.")

  cedar_degrees <- degrees %>%
    transmute(
      degree_id      = paste0(`Academic Period Code`, "-", ID, "-", `Program Code`),
      student_id     = encrypt_if_needed(ID),
      term           = as.integer(`Academic Period Code`),
      student_college = if ("Actual College" %in% names(.)) `Actual College` else NA_character_,
      degree         = Degree,
      award_category = if ("Award Category" %in% names(.)) `Award Category` else NA_character_,
      program_code   = `Program Code`,
      program_name   = Program,
      college        = `Translated College`,
      department     = Department,
      graduation_status = `Graduation Status`,
      campus         = if ("Campus" %in% names(.)) Campus else NA_character_,
      # cedar_degrees$major: Banner MAJOR NAME (display); cedar_degrees$major_code: the join key.
      major      = if ("Major"      %in% names(.)) Major      else NA_character_,
      major_code = dplyr::case_when(
        "Major Code" %in% names(.) & !is.na(`Major Code`) & `Major Code` != "" ~ `Major Code`,
        TRUE ~ stringr::str_extract(`Program Code`, "(?<=-)[A-Z0-9]+(?=-[A-Z]{2,3}$)")
      ),
      second_major = if ("Second Major" %in% names(.)) `Second Major` else NA_character_,
      first_minor  = if ("First Minor"  %in% names(.)) `First Minor`  else NA_character_,
      second_minor = if ("Second Minor" %in% names(.)) `Second Minor` else NA_character_,
      cumulative_gpa     = if ("Cumulative GPA"             %in% names(.)) as.numeric(`Cumulative GPA`)             else NA_real_,
      cumulative_credits = if ("Cumulative Credits Earned"  %in% names(.)) as.numeric(`Cumulative Credits Earned`)  else NA_real_,
      honors             = if ("Honor"                      %in% names(.)) Honor                                    else NA_character_,
      admitted_term      = if ("Academic Period Admitted"   %in% names(.)) suppressWarnings(as.integer(`Academic Period Admitted`)) else NA_integer_,
      as_of_date = as.Date(as_of_date)
    ) %>%
    dplyr::mutate(
      # Unit from programs.csv, as for cedar_programs (ADR-002): a code with
      # no confirmed row has no unit.
      .college_code = translate_source_college(student_college, files),
      dept_code = resolve_program_units(major_code, unname(.college_code), files$programs),
      # College (ADR-002 Stage 3b): the degree program's college through the
      # files; for a code not yet decided, Banner's (Translated College, else
      # Actual College), labelled "banner". Banner's values stay beside it.
      .decided = !is.na(.confirmed_program_rows(major_code, dplyr::coalesce(unname(.college_code), ""),
                                                files$programs, no_unit = TRUE)),
      .mapped  = resolve_program_colleges(major_code, dplyr::coalesce(unname(.college_code), ""), files),
      .banner  = dplyr::coalesce(translate_source_college(college, files),
                                 translate_source_college(student_college, files)),
      source_college         = college,
      source_student_college = student_college,
      college_code  = dplyr::if_else(.decided, .mapped, .banner),
      college_basis = dplyr::case_when(.decided & !is.na(.mapped) ~ "mapped",
                                       !.decided & !is.na(.banner) ~ "banner",
                                       TRUE ~ NA_character_),
      college         = college_names(college_code, files),
      student_college = college,
      degree_abbr = sub("^([A-Za-z]+)-.*$", "\\1", program_code)
    ) %>%
    dplyr::select(-.college_code, -.decided, -.mapped, -.banner)

  message("  ✅ Created cedar_degrees: ", nrow(cedar_degrees), " rows, ", ncol(cedar_degrees), " columns")
  message("  Output columns: ", paste(names(cedar_degrees), collapse = ", "))

  # Units come from the mapping files: stamp which files, so the rebuild gate
  # can tell when they move (ISSUES.md M26), as for cedar_programs.
  attr(cedar_degrees, "cedar_mapping_provenance") <- cedar_mapping_provenance()
  saved_meta <- save_cedar_file(cedar_degrees, "degrees", data_dir, ext)
  list(saved = list(degrees = saved_meta))
}


# ── 5. transform_faculty: hr_data → cedar_faculty ────────────────────────────

#' @param hr_data  Raw hr_data data frame
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @return list(saved = list(faculty = <meta>))
transform_faculty <- function(hr_data, data_dir, ext) {
  message("──────────────────────────────────────────────────────")
  message("5. Transforming hr_data → cedar_faculty")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(hr_data), " rows, ", ncol(hr_data), " columns")
  message("  Input columns: ", paste(names(hr_data), collapse = ", "))
  message("  Transforming to CEDAR model...")

  cedar_faculty <- hr_data %>%
    transmute(
      instructor_id   = as.character(`UNM ID`),
      term            = as.integer(term_code),
      instructor_name = Name,
      department      = DEPT,
      academic_title  = if ("Academic Title"       %in% names(.)) `Academic Title`       else NA_character_,
      job_title       = if ("Job Title"            %in% names(.)) `Job Title`            else NA_character_,
      job_category    = if ("job_cat"              %in% names(.)) job_cat                else NA_character_,
      appointment_pct = if ("Appt %"              %in% names(.)) as.numeric(`Appt %`)   else NA_real_,
      college         = if ("Home Organization Desc" %in% names(.)) `Home Organization Desc` else NA_character_,
      as_of_date      = if ("as_of_date"           %in% names(.)) as.Date(as_of_date)   else NA_Date_
    )

  message("  ✅ Created cedar_faculty: ", nrow(cedar_faculty), " rows, ", ncol(cedar_faculty), " columns")
  message("  Output columns: ", paste(names(cedar_faculty), collapse = ", "))

  saved_meta <- save_cedar_file(cedar_faculty, "faculty", data_dir, ext)
  list(saved = list(faculty = saved_meta))
}


# ── 6. transform_applicants: admissions_applicants → cedar_applicants ─────────

#' Transforms admissions applicant data to the CEDAR model.
#' Encrypts student ID, derives term, renames columns to snake_case, and keeps
#' only the admissions covariates consumed by comparison analyses.
#'
#' @param applicants Raw admissions_applicants data frame (output of parse-data.R)
#' @param data_dir   Path to data directory
#' @param ext        File extension
#' @return list(saved = list(applicants = <meta>))
transform_applicants <- function(applicants, data_dir, ext) {
  message("──────────────────────────────────────────────────────")
  message("6. Transforming admissions_applicants → cedar_applicants")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(applicants), " rows, ", ncol(applicants), " columns")
  message("  Input columns: ", paste(names(applicants), collapse = ", "))

  # Derive integer term
  if ("Academic Period" %in% names(applicants)) {
    applicants <- applicants %>%
      mutate(term = as.integer(academic_period_to_term(`Academic Period`)))
  } else if ("Academic Period Code" %in% names(applicants)) {
    applicants <- applicants %>% mutate(term = as.integer(`Academic Period Code`))
  } else {
    warning("[transform_applicants] No term column found — term will be NA")
    applicants$term <- NA_integer_
  }

  # Encrypt student ID
  if ("ID" %in% names(applicants)) {
    applicants <- applicants %>%
      mutate(student_id = encrypt_if_needed(ID)) %>%
      select(-ID)
  } else {
    warning("[transform_applicants] No ID column found — student_id will be NA")
    applicants$student_id <- NA_character_
  }

  # Normalize as_of_date
  applicants <- applicants %>% mutate(as_of_date = as.Date(as_of_date))

  # Rename all columns to snake_case
  names(applicants) <- to_snake(names(applicants))

  # This table previously preserved all ~82 source columns even though runtime
  # analyses use only the fields below. Keeping the explicit contract here cuts
  # applicant memory by roughly 80% and prevents new source columns from being
  # loaded into every Shiny worker by accident.
  runtime_cols <- c(
    "student_id", "term", "as_of_date", "admissions_population",
    "high_school_cum_gpa", "unm_act_combined_score", "transfer_gpa",
    "high_school_self_reported_gpa", "current_age", "state_admit"
  )
  cedar_applicants <- applicants %>% select(any_of(runtime_cols))

  message("  ✅ Created cedar_applicants: ", nrow(cedar_applicants), " rows, ", ncol(cedar_applicants), " columns")
  message("  Output columns: ", paste(names(cedar_applicants), collapse = ", "))

  saved_meta <- save_cedar_file(cedar_applicants, "applicants", data_dir, ext)
  list(saved = list(applicants = saved_meta))
}


# ── 7. build_lookups: generate cedar_lookups ──────────────────────────────────

#' @param cedar_sections    cedar_sections data frame (or NULL if not available)
#' @param cedar_programs    cedar_programs data frame (or NULL if not available)
#' @param data_dir          Path to data directory
#' @param ext               File extension
#' @param maps              Named list of lookup vectors
#' @param major_code_name_raw Data frame of Major Code / Major pairs from transform_students
#' @return list(saved = list(lookups = <meta>))
build_lookups <- function(cedar_sections, cedar_programs, data_dir, ext, maps,
                          major_code_name_raw = NULL) {
  message("──────────────────────────────────────────────────────")
  message("7. Generating cedar_lookups (normalization tables)")
  message("──────────────────────────────────────────────────────")

  subj_dept_map             <- maps$subj_dept_map
  hr_org_desc_to_dept       <- maps$hr_org_desc_to_dept
  dept_code_to_name_catalog <- maps$dept_code_to_name_catalog
  college_name_to_code      <- maps$college_name_to_code

  cedar_lookups <- list()

  # 7a. Program name → dept_code lookup (data-derived from cedar_programs)
  message("  Building program_name → dept_code lookup...")
  if (!is.null(cedar_programs)) {
    # dept_code is a unit from the mapping files (ADR-002): no self-named
    # department reaches here, so nothing needs correcting after the fact.
    program_name_lookup <- cedar_programs %>%
      filter(!is.na(program_name) & program_name != "" & !is.na(dept_code) & dept_code != "") %>%
      count(program_name, dept_code, sort = TRUE) %>%
      group_by(program_name) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      select(program_name, dept_code)
    message("    ✅ program_name_lookup: ", nrow(program_name_lookup), " entries")
    message("    Sample: ", paste(head(program_name_lookup$program_name, 10), collapse = ", "))
    cedar_lookups$program_name_lookup <- program_name_lookup

    # 7b. Department string → dept_code mapping
    message("  Building department → dept_code lookup...")
    if (length(hr_org_desc_to_dept) > 0) {
      handcoded_dept_lookup <- tibble(
        department = names(hr_org_desc_to_dept),
        dept_code  = as.character(hr_org_desc_to_dept)
      )
      message("    Handcoded dept mappings: ", nrow(handcoded_dept_lookup), " entries")
    } else {
      handcoded_dept_lookup <- tibble(department = character(), dept_code = character())
    }
    unique_departments <- cedar_programs %>%
      filter(!is.na(dept_code) & dept_code != "") %>%
      distinct(dept_code) %>%
      filter(!(dept_code %in% handcoded_dept_lookup$department)) %>%
      transmute(department = dept_code, dept_code)
    message("    Data-derived dept mappings: ", nrow(unique_departments), " additional entries")
    cedar_lookups$dept_lookup <- bind_rows(handcoded_dept_lookup, unique_departments) %>%
      distinct(department, .keep_all = TRUE)

    # 7c. Dept code → human-readable name
    # Priority: subj_dept_map (authoritative) → data-derived from cedar_programs
    n_overrides <- 0L
    if (length(dept_code_to_name_catalog) > 0) {
      # Precompute valid dept codes outside filter() — the if() expression
      # inside %in% is evaluated in dplyr's vectorized context and fails.
      .valid_dept_codes <- unique(c(
        cedar_programs$dept_code,
        if (!is.null(cedar_sections)) cedar_sections$department else character(0)
      ))
      dept_name_lookup <- tibble(
        dept_code = names(dept_code_to_name_catalog),
        dept_name = as.character(dept_code_to_name_catalog)
      ) %>%
        filter(dept_code %in% .valid_dept_codes)
      n_overrides <- nrow(dept_name_lookup)
      data_derived_names <- cedar_programs %>%
        filter(!is.na(major_code), major_code != "",
               !is.na(dept_code),  dept_code  != "",
               !grepl("^[0-9]+$", dept_code),
               major_code == dept_code,
               !dept_code %in% dept_name_lookup$dept_code) %>%
        distinct(dept_code, program_name) %>%
        group_by(dept_code) %>% slice_head(n = 1) %>% ungroup() %>%
        rename(dept_name = program_name)
      if (nrow(data_derived_names) > 0) {
        dept_name_lookup <- bind_rows(dept_name_lookup, data_derived_names)
        message("    Supplemented with ", nrow(data_derived_names),
                " data-derived names for dept_codes not in subj_dept_map")
      }
      n_before <- nrow(dept_name_lookup)
      dept_name_lookup <- dept_name_lookup %>%
        group_by(dept_name) %>% slice_head(n = 1) %>% ungroup()
      n_dropped <- n_before - nrow(dept_name_lookup)
      if (n_dropped > 0)
        message("    Removed ", n_dropped, " dept_name duplicates (legacy alias codes)")
      dept_name_lookup <- arrange(dept_name_lookup, dept_code)
    } else {
      dept_name_lookup <- cedar_programs %>%
        filter(!is.na(major_code), major_code != "",
               !is.na(dept_code),  dept_code  != "",
               major_code == dept_code) %>%
        distinct(dept_code, program_name) %>%
        group_by(dept_code) %>% slice_head(n = 1) %>% ungroup() %>%
        rename(dept_name = program_name) %>%
        arrange(dept_code)
    }

    # Warn about active dept_codes with no display name
    active_dept_codes <- unique(c(
      cedar_programs$dept_code,
      if (!is.null(cedar_sections)) cedar_sections$department else character(0)
    ))
    active_dept_codes <- active_dept_codes[!is.na(active_dept_codes) & active_dept_codes != ""]
    unnamed_active <- sort(setdiff(active_dept_codes, dept_name_lookup$dept_code))
    if (length(unnamed_active) > 0) {
      f_codes     <- unnamed_active[grepl("^F[A-Z]", unnamed_active)]
      x_codes     <- unnamed_active[grepl("^X[A-Z]", unnamed_active)]
      other_codes <- unnamed_active[!grepl("^[FX][A-Z]", unnamed_active)]
      if (length(f_codes)     > 0) message("    ⚠️  F-prefix codes (pre-major mapping gap): ",     paste(f_codes,     collapse = ", "))
      if (length(x_codes)     > 0) message("    ⚠️  X-prefix codes (extended/crosslist mapping gap): ", paste(x_codes, collapse = ", "))
      if (length(other_codes) > 0) message("    ⚠️  Unknown dept codes (add to institution/<id>/units.csv if valid): ", paste(other_codes, collapse = ", "))
    }
    n_data_only <- nrow(dept_name_lookup) - n_overrides
    message("    ✅ dept_name_lookup: ", nrow(dept_name_lookup), " entries (",
            n_data_only, " data-derived, ", n_overrides, " display overrides)")
    cedar_lookups$dept_name_lookup <- dept_name_lookup

  } else {
    message("  ⚠️  cedar_programs not available — skipping program and dept lookups")
  }

  # 7d. College code → name (for display)
  college_code_to_name <- if (!is.null(subj_dept_map)) {
    .clu <- dplyr::distinct(subj_dept_map, college_code, college_name)
    setNames(.clu$college_name, .clu$college_code)
  } else if (length(college_name_to_code) > 0) {
    setNames(names(college_name_to_code), college_name_to_code)
  } else {
    character(0)
  }
  cedar_lookups$college_code_to_name <- college_code_to_name

  # 7e. Subject code lookup (subject code → dept code + college)
  message("  Building subject_code lookup from cedar_sections...")
  if (!is.null(cedar_sections)) {
    subject_lookup <- cedar_sections %>%
      filter(!is.na(subject) & subject != "" & !is.na(department) & department != "") %>%
      count(subject, department, college, sort = TRUE) %>%
      group_by(subject) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      rename(subject_code = subject, dept_code = department) %>%
      select(subject_code, dept_code, college)
    message("    ✅ subject_lookup: ", nrow(subject_lookup), " unique subject codes")
    message("    Sample: ", paste(head(subject_lookup$subject_code, 15), collapse = ", "))
    cedar_lookups$subject_lookup <- subject_lookup
  } else {
    message("  ⚠️  cedar_sections not available — skipping subject lookup")
  }

  # 7f. Major code → human-readable name
  # Derived from class_lists in transform_students; ~100% coverage.
  message("  Building major_code_to_name lookup...")
  if (!is.null(major_code_name_raw) && nrow(major_code_name_raw) > 0) {
    cedar_lookups$major_code_to_name <- setNames(
      major_code_name_raw[["Major"]],
      major_code_name_raw[["Major Code"]]
    )
    message("    ✅ major_code_to_name: ", length(cedar_lookups$major_code_to_name), " entries")
  } else {
    existing_lookup_file <- file.path(data_dir, paste0("cedar_lookups", ext))
    existing_lookups <- if (file.exists(existing_lookup_file)) {
      tryCatch(load_file(existing_lookup_file, ext), error = function(e) NULL)
    } else {
      NULL
    }

    if (!is.null(existing_lookups$major_code_to_name)) {
      cedar_lookups$major_code_to_name <- existing_lookups$major_code_to_name
      message("    ✅ major_code_to_name preserved from existing cedar_lookups: ",
              length(cedar_lookups$major_code_to_name), " entries")
    } else {
      message("    ⚠️  major_code_name_raw not available — skipping major_code_to_name")
    }
  }

  saved_meta <- save_cedar_file(cedar_lookups, "lookups", data_dir, ext)
  list(saved = list(lookups = saved_meta))
}


# ── Orchestrator ──────────────────────────────────────────────────────────────

#' Transform MyReports data to CEDAR model
#'
#' Loads parsed source files, calls each transform function, and saves cedar_* files.
#' Runs daily after parse-data.R. Overwrites existing cedar_* files.
#'
#' @param data_dir Path to data directory (default: from config)
#' @param use_qs   Use .qs format (default: from config)
#' @param tables   Character vector of tables to run (default: all)
#'                 Options: "sections", "students", "programs", "degrees",
#'                          "faculty", "applicants", "lookups"
#' @return Invisibly: named list of save metadata for each table written
transform_to_cedar <- function(data_dir = NULL, use_qs = NULL, tables = NULL) {

  message("\n═══════════════════════════════════════════════════════")
  message("  CEDAR Data Model Transformation")
  message("═══════════════════════════════════════════════════════\n")

  is_docker <- Sys.getenv("docker") == "TRUE" || file.exists("/.dockerenv")

  # Resolve data directory
  if (is.null(data_dir)) {
    data_dir <- if (is_docker) {
      if (exists("cedar_data_docker_dir")) cedar_data_docker_dir else "data/"
    } else {
      if (exists("cedar_shared_data_dir")) cedar_shared_data_dir else "data/"
    }
    message("Using data_dir from config: ", data_dir)
  } else {
    message("Using provided data_dir: ", data_dir)
  }

  if (is.null(use_qs)) use_qs <- if (exists("cedar_use_qs")) cedar_use_qs else TRUE
  ext <- if (use_qs && requireNamespace("qs2", quietly = TRUE)) ".qs" else ".Rds"

  # Resolve which tables to run
  all_tables <- c("sections", "students", "programs", "degrees", "faculty", "applicants", "lookups")
  if (is.null(tables)) {
    run_tables <- all_tables
  } else {
    unknown <- setdiff(tables, all_tables)
    if (length(unknown) > 0)
      message("  ⚠️  Unknown table(s) ignored: ", paste(unknown, collapse = ", "))
    run_tables <- intersect(all_tables, tables)
    if (any(c("sections", "programs", "degrees") %in% run_tables) && !"lookups" %in% run_tables) {
      run_tables <- c(run_tables, "lookups")
      message("  Note: Adding lookups (auto-included when sections/programs/degrees are transformed)")
    }
  }

  message("Configuration:")
  message("  Data directory: ", data_dir)
  message("  File format:    ", ext)
  message("  Tables:         ", paste(run_tables, collapse = ", "))
  message("")

  # ── Load helper maps ───────────────────────────────────────────────────────
  # Every lookup comes from the lists load_funcs() sources, and those read the
  # institution mapping files (ADR-002). program_map.qs and the lists that fed
  # it were retired at Stage 4. Script mode, the deploy gate and the demo
  # generator all load CEDAR's functions first; anything else must too.
  gen_ed_names <- paste0("gen_ed_", c("1_communication", "2_math_stat", "3_phys_nat_sci",
                                      "4_soc_behav_sci", "5_humanities", "7_arts_design"))
  needed <- c("read_institution_mappings", "subj_dept_map", "college_name_to_code",
              "dept_code_to_name", "major_name_to_major_code", "hr_org_desc_to_dept", gen_ed_names)
  missing <- needed[!vapply(needed, exists, logical(1))]
  if (length(missing)) {
    stop("[transform-to-cedar.R] CEDAR's lists are not loaded (run load_funcs() first); missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  message("  subj_dept_map: ", nrow(subj_dept_map), " rows, ",
          length(unique(subj_dept_map$subject_code)), " subject codes, ",
          length(unique(subj_dept_map$dept_code)), " dept codes, ",
          length(unique(subj_dept_map$college_code)), " colleges")

  # The mapping files decide every unit and college. Read once, validated on
  # read: a malformed file stops the transform with every problem listed. The
  # directory comes from the base load_funcs() recorded, as at app startup --
  # a path guessed inside the container is how the deploy's mapping rebuild
  # once failed (ISSUES.md I14).
  mapping_files <- read_institution_mappings(cedar_institution_dir())
  message("  Mapping files: ", nrow(mapping_files$programs), " program rows, ",
          nrow(mapping_files$subjects), " subject rows, ", nrow(mapping_files$units), " units")

  maps <- list(
    mapping_files             = mapping_files,
    major_name_to_major_code  = major_name_to_major_code,
    college_name_to_code      = college_name_to_code,
    subj_dept_map             = subj_dept_map,
    hr_org_desc_to_dept       = hr_org_desc_to_dept,
    dept_code_to_name_catalog = dept_code_to_name,
    gen_ed = stats::setNames(lapply(gen_ed_names, get), c("1", "2", "3", "4", "5", "7"))
  )

  # Initialize results tracking
  saved_files       <- list()
  cedar_for_lookups <- list()  # sections + programs held in memory for build_lookups
  major_code_name_raw <- NULL  # captured in transform_students, used in build_lookups

  # ── 1. cedar_sections ─────────────────────────────────────────────────────
  if ("sections" %in% run_tables) {
    desr_file <- file.path(data_dir, paste0("DESRs", ext))
    if (file.exists(desr_file)) {
      message("\nLoading: ", desr_file)
      desrs  <- load_file(desr_file, ext)
      result <- transform_sections(desrs, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      cedar_for_lookups$sections <- result$table
      rm(desrs); gc(verbose = FALSE)
    } else {
      message("  ⚠️  DESRs file not found: ", desr_file, " — skipping cedar_sections")
    }
  } else {
    message("  ⏭  Skipping cedar_sections (not in --tables)")
  }

  # ── 2. cedar_students ─────────────────────────────────────────────────────
  if ("students" %in% run_tables) {
    cl_file <- file.path(data_dir, paste0("class_lists", ext))
    if (file.exists(cl_file)) {
      message("\nLoading: ", cl_file)
      class_lists <- load_file(cl_file, ext)
      result      <- transform_students(class_lists, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      major_code_name_raw <- result$major_code_name_raw
      rm(class_lists); gc(verbose = FALSE)
    } else {
      message("  ⚠️  class_lists file not found: ", cl_file, " — skipping cedar_students")
    }
  } else {
    message("  ⏭  Skipping cedar_students (not in --tables)")
  }

  # ── 3. cedar_programs ─────────────────────────────────────────────────────
  if ("programs" %in% run_tables) {
    as_file <- file.path(data_dir, paste0("academic_studies", ext))
    if (file.exists(as_file)) {
      message("\nLoading: ", as_file)
      academic_studies <- load_file(as_file, ext)
      result           <- transform_programs(academic_studies, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      cedar_for_lookups$programs <- result$table
      rm(academic_studies); gc(verbose = FALSE)
    } else {
      message("  ⚠️  academic_studies file not found: ", as_file, " — skipping cedar_programs")
    }
  } else {
    message("  ⏭  Skipping cedar_programs (not in --tables)")
  }

  # ── 4. cedar_degrees ──────────────────────────────────────────────────────
  if ("degrees" %in% run_tables) {
    deg_file <- file.path(data_dir, paste0("degrees", ext))
    if (file.exists(deg_file)) {
      message("\nLoading: ", deg_file)
      degrees <- load_file(deg_file, ext)
      result  <- transform_degrees(degrees, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      rm(degrees); gc(verbose = FALSE)
    } else {
      message("  ⚠️  degrees file not found: ", deg_file, " — skipping cedar_degrees")
    }
  } else {
    message("  ⏭  Skipping cedar_degrees (not in --tables)")
  }

  # ── 5. cedar_faculty ──────────────────────────────────────────────────────
  if ("faculty" %in% run_tables) {
    hr_file <- file.path(data_dir, paste0("hr_data", ext))
    if (file.exists(hr_file)) {
      message("\nLoading: ", hr_file)
      hr_data <- load_file(hr_file, ext)
      result  <- transform_faculty(hr_data, data_dir, ext)
      saved_files <- c(saved_files, result$saved)
      rm(hr_data); gc(verbose = FALSE)
    } else {
      message("  ⚠️  hr_data file not found: ", hr_file, " — skipping cedar_faculty")
    }
  } else {
    message("  ⏭  Skipping cedar_faculty (not in --tables)")
  }

  # ── 6. cedar_applicants ───────────────────────────────────────────────────
  if ("applicants" %in% run_tables) {
    aa_file <- file.path(data_dir, paste0("admissions_applicants", ext))
    if (file.exists(aa_file)) {
      message("\nLoading: ", aa_file)
      applicants <- load_file(aa_file, ext)
      result     <- transform_applicants(applicants, data_dir, ext)
      saved_files <- c(saved_files, result$saved)
      rm(applicants); gc(verbose = FALSE)
    } else {
      message("  ⚠️  admissions_applicants file not found: ", aa_file, " — skipping cedar_applicants")
    }
  } else {
    message("  ⏭  Skipping cedar_applicants (not in --tables)")
  }

  # ── 7. cedar_lookups ──────────────────────────────────────────────────────
  if ("lookups" %in% run_tables) {
    message("\n──────────────────────────────────────────────────────")
    # Load sections/programs from disk if not already in memory from this run
    if (is.null(cedar_for_lookups$sections)) {
      sec_file <- file.path(data_dir, paste0("cedar_sections", ext))
      if (file.exists(sec_file)) {
        message("  Loading cedar_sections from disk for lookups (slimming)...")
        cedar_for_lookups$sections <- load_file(sec_file, ext) %>%
          distinct(subject, department, college) %>%
          filter(!is.na(subject), subject != "", !is.na(department), department != "")
      }
    }
    if (is.null(cedar_for_lookups$programs)) {
      prog_file <- file.path(data_dir, paste0("cedar_programs", ext))
      if (file.exists(prog_file)) {
        message("  Loading cedar_programs from disk for lookups (slimming)...")
        cedar_for_lookups$programs <- load_file(prog_file, ext) %>%
          distinct(program_name, dept_code, major_code, college_code) %>%
          filter(!is.na(program_name), program_name != "")
      }
    }
    result <- build_lookups(cedar_for_lookups$sections, cedar_for_lookups$programs,
                            data_dir, ext, maps, major_code_name_raw)
    saved_files <- c(saved_files, result$saved)
    rm(cedar_for_lookups); gc(verbose = FALSE)
  } else {
    message("  ⏭  Skipping cedar_lookups (not in --tables)")
  }

  # ── Summary ───────────────────────────────────────────────────────────────
  message("\n──────────────────────────────────────────────────────")
  message("CEDAR Transformation Complete — ", length(saved_files), " files saved:")
  for (name in names(saved_files)) {
    info <- saved_files[[name]]
    message("  ✅ cedar_", name, ": ",
            format(info$rows, big.mark = ","), " rows, ",
            round(info$size_mb, 1), " MB")
  }

  # ── Mapping audit ─────────────────────────────────────────────────────────
  # Every value in the data the mapping files do not cover, the day it arrives
  # (ADR-002). Runs over the stored tables, so a run that rebuilt only some of
  # them still checks all of them. Never blocks the refresh: the list is for a
  # person, and Admin > Mappings shows the same audit live.
  message("\n──────────────────────────────────────────────────────")
  audit_tables <- lapply(
    c(sections = "cedar_sections", students = "cedar_students",
      programs = "cedar_programs", degrees = "cedar_degrees"),
    function(name) {
      path <- file.path(data_dir, paste0(name, ext))
      if (file.exists(path)) load_file(path, ext) else NULL
    })
  mapping_audit <- do.call(audit_mapping_coverage,
                           c(list(files = read_institution_mappings()), audit_tables))
  message("  ", summarize_mapping_audit(mapping_audit))
  for (i in which(mapping_audit$status == "unmapped")) {
    message(sprintf("    %-14s %-10s %s rows, %s", mapping_audit$kind[i], mapping_audit$value[i],
                    format(mapping_audit$rows[i], big.mark = ","), mapping_audit$context[i]))
  }
  rm(audit_tables, mapping_audit); gc(verbose = FALSE)

  # Write cedar-status.json for fast CLI queries
  status_file <- file.path(data_dir, "cedar-status.json")
  tryCatch({
    write_cedar_status_file(saved_files, status_file)
    message("  ✅ Wrote ", status_file)
  }, error = function(e) {
    message("  ⚠️  Could not write status file: ", conditionMessage(e))
  })

  # Copy cedar_* files to local data directory (non-Docker only)
  shared_data_dir <- if (exists("cedar_shared_data_dir")) cedar_shared_data_dir else ""
  local_data_dir  <- if (exists("cedar_data_dir"))        cedar_data_dir        else ""

  if (is_docker) {
    # The container writes straight into ./data, so there is nothing to copy.
    message("\n  ⏭  Skipping local data copy (running inside Docker)")

  } else if (shared_data_dir == "" || local_data_dir == "") {
    # Genuinely unconfigured: no local copy was ever asked for. A quiet skip is
    # the right answer here, unlike the case below.
    message("\n  ⏭  Skipping local data copy (no local data directory configured)")
    if (shared_data_dir == "") message("     Hint: ensure config/config.R defines cedar_shared_data_dir")
    if (local_data_dir  == "") message("     Hint: ensure config/config.R defines cedar_data_dir")

  } else {
    # Both configured. A configured path that does not exist is a typo, not a
    # valid state — and skipping it quietly is how a fully green pipeline run
    # leaves the app reading stale tables while every step reports success.
    # That is exactly what happened on 2026-08-12: a repull that correctly fixed
    # the student ID spaces never reached the app, and the run said ✅ four
    # times. Fail here instead. See ISSUES.md I3.
    absent <- c(
      if (!dir.exists(shared_data_dir)) paste0("cedar_shared_data_dir = ", shared_data_dir),
      if (!dir.exists(local_data_dir))  paste0("cedar_data_dir = ", local_data_dir)
    )
    if (length(absent) > 0) {
      stop("[transform-to-cedar.R] ERROR: configured data directory does not exist:\n  ",
           paste(absent, collapse = "\n  "),
           "\n\nThe CEDAR tables WERE written to ", shared_data_dir,
           " — no work was lost — but they could not be copied to the app's data",
           " directory, so the app is still reading whatever was there before.",
           "\nFix the path in config/config.R and re-run the transform.",
           call. = FALSE)
    }

    message("\n──────────────────────────────────────────────────────")
    message("Copying CEDAR files to local data directory")
    message("  Source:      ", shared_data_dir)
    message("  Destination: ", local_data_dir)
    # A failed copy is also fatal. Half a refresh is worse than none: the app
    # would run with some tables current and some not, which is unjoinable in
    # precisely the way this whole issue was about.
    failed <- character(0)
    for (name in names(saved_files)) {
      info      <- saved_files[[name]]
      dest_path <- file.path(local_data_dir, info$filename)
      message("  Copying: ", info$filename, " → local data/")
      if (file.copy(info$filepath, dest_path, overwrite = TRUE)) {
        message("    ✅ Copied")
      } else {
        message("    ❌ Copy failed")
        failed <- c(failed, info$filename)
      }
    }
    if (length(failed) > 0) {
      stop("[transform-to-cedar.R] ERROR: could not copy ", length(failed),
           " file(s) to ", local_data_dir, ":\n  ", paste(failed, collapse = "\n  "),
           "\nThe local data directory is now a mix of refreshed and stale tables.",
           call. = FALSE)
    }
  }

  message("\n═══════════════════════════════════════════════════════")
  message("  Transformation Complete!")
  message("═══════════════════════════════════════════════════════\n")
  message("CEDAR files created:")
  for (name in names(saved_files)) {
    info <- saved_files[[name]]
    message("  ✅ cedar_", name, ext, " (",
            format(info$rows, big.mark = ","), " rows, ",
            round(info$size_mb, 1), " MB)")
  }
  message("\nOriginal MyReports files remain unchanged.\n")

  invisible(saved_files)
}


# ── MAIN (if run directly) ────────────────────────────────────────────────────
if (!interactive() && !exists("SOURCED_FROM_PARSE_DATA")) {
  message("[transform-to-cedar.R] Running as standalone script")

  # Work from the repository root, found from this script's own path:
  # update-data.sh runs it by absolute path from wherever it was started.
  script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  setwd(normalizePath(file.path(dirname(script_path), "..", "..")))
  if (file.exists("config/config.R")) source("config/config.R")
  # Load CEDAR's functions as scripts/rebuild-programs-if-mappings-changed.R
  # does. Without them the provenance stamp on cedar_programs and the mapping
  # audit have nothing to call (ISSUES.md I13).
  source(file.path("R", "trunk", "load-funcs.R"))
  load_funcs(getwd(), modules = FALSE)

  args         <- commandArgs(trailingOnly = TRUE)
  data_dir_arg <- NULL
  tables_arg   <- NULL

  if (length(args) > 0) {
    for (i in seq_along(args)) {
      if (args[i] == "--data-dir" && i < length(args)) {
        data_dir_arg <- args[i + 1]
        message("Command-line data_dir: ", data_dir_arg)
      }
      if (args[i] == "--tables" && i < length(args)) {
        tables_arg <- strsplit(args[i + 1], ",")[[1]]
        message("Command-line tables: ", paste(tables_arg, collapse = ", "))
      }
    }
  }

  transform_to_cedar(data_dir = data_dir_arg, tables = tables_arg)
}
