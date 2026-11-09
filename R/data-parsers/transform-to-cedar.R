# transform-to-cedar.R
#
# Transforms parsed MyReports data files into the CEDAR data model.
# Runs after parse-data.R (PII removal already done) and writes cedar_* files.
#
# IMPORTANT: This does NOT modify any existing source files.
# Output files are named cedar_sections.qs, cedar_registrations.qs, etc.
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
# - Nov 2026: Units and colleges are no longer written (ADR-001 step 3). Every
#             table carries its keys -- subject, program code, the source's
#             college -- and the loader attaches department / college /
#             dept_code / college_code at every start (R/branches/dims.R).
# - Apr 2026: Refactored: each table now has its own transform_*() function
# - Apr 2026: Added cedar_applicants (from admissions_applicants)
# - Mar 2026: Added residency, academic_standing, inst_gpa to cedar_programs
# - Mar 2026: Added is_pre_major to cedar_programs
# - Mar 2026: Added is_topics to cedar_sections
# - Jan 2026: Removed duplicate 'grade' column; use 'final_grade'
# - Jan 2026: Added subject_code, level, instructor_id to cedar_registrations
# - Jan 2026: Added student_level, student_college, student_campus to cedar_programs
#
# To add a new table: write a transform_<name>() function below,
# add the name to all_tables in transform_to_cedar(), wire it in the orchestrator.

library(tidyverse)
library(digest)

source("R/trunk/utils.R")        # academic_period_to_term, add_next_term_col, etc.
source("R/lists/grades.R")       # GRADES_DFW, GRADES_PASS
source("R/lists/status_codes.R") # STATUS_REGISTERED, STATUS_DROP_EARLY
# course_level_from_number() and its COURSE_LEVEL_BY_LEADING_DIGIT lookup come
# from institution/<id>/course_levels.csv through load_funcs()
# (R/lists/institution_files.R then course_numbering.R).


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
  # The range of a column with no non-missing value is NA, not Inf with a
  # warning: a table can be legitimately empty (a measure over a window with
  # nothing to count).
  known <- function(column) {
    if (!is.data.frame(data) || !column %in% names(data)) return(NULL)
    values <- data[[column]]
    values[!is.na(values)]
  }
  as_of_values <- known("as_of_date")
  as_of <- if (length(as_of_values)) format(max(as_of_values)) else NA_character_
  term_values <- known("term")
  min_term <- if (length(term_values)) as.character(min(term_values)) else NA_character_
  max_term <- if (length(term_values)) as.character(max(term_values)) else NA_character_
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

# Hash an instructor ID the way parse-data.R hashes the class list's and the
# HR report's (md5 of the ID), unless it already is a hash. The DESR's report
# spec hashes nothing, so its PRIM_INST_ID arrived as the employee ID: the HR
# merge below never matched (job_cat was NA on every section) and the saved
# sections joined neither the class list nor cedar_faculty (ISSUES I52).
# Applied to all four sources, so files that never went through parse-data
# (the synthetic institution's) come out the same way. NA stays NA.
hash_instructor_id <- function(id) {
  id_chr <- as.character(id)
  todo <- !is.na(id_chr) & !grepl("^[0-9a-f]{32}$", id_chr)
  if (!any(todo)) return(id_chr)
  raw <- unique(id_chr[todo])
  hashed <- vapply(raw, digest::digest, character(1), algo = "md5", USE.NAMES = FALSE)
  id_chr[todo] <- hashed[match(id_chr[todo], raw)]
  id_chr
}

# Convert a character vector of column names to snake_case
to_snake <- function(x) {
  x <- gsub("[^a-zA-Z0-9]+", "_", x)  # non-alphanumeric → underscore
  x <- gsub("_{2,}", "_", x)           # collapse consecutive underscores
  x <- gsub("^_|_$", "", x)            # strip leading/trailing underscores
  tolower(x)
}


# The ADR-002 mapping files (read_institution_mappings()). Since ADR-001 step 3
# the transform writes no unit: the loader attaches every one at start from
# the keys each table carries (R/branches/dims.R). The files are still read
# here for what a row records about its own program (the pre-major flag), and
# a transform that cannot read them stops rather than guess.
.require_mapping_files <- function(maps, caller, tables) {
  files <- maps$mapping_files
  missing <- tables[vapply(tables, function(t) is.null(files[[t]]), logical(1))]
  if (length(missing)) {
    stop("[", caller, "] maps$mapping_files must carry ", paste(missing, collapse = ", "),
         ": the institution mapping files decide every unit (ADR-002 Stage 3).")
  }
  files
}

# ── 1. transform_sections: DESRs → cedar_sections ────────────────────────────

#' @param desrs    Raw DESRs data frame (output of parse-data.R + parse-DESR.R)
#' @param data_dir Path to data directory (used for HR merge file lookup)
#' @param ext      File extension: ".qs" or ".Rds"
#' @param maps     Named list of lookup vectors from transform_to_cedar()
#' @return list(saved = list(sections = <meta>))
transform_sections <- function(desrs, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("1. Transforming DESRs → cedar_sections")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(desrs), " rows, ", ncol(desrs), " columns")
  message("  Input columns: ", paste(names(desrs), collapse = ", "))

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

  # Gen Ed area from the institution's gen_ed_courses.csv; a course listed
  # under two areas counts under the first listed, every other course is NA.
  if (!is.null(gen_ed) && nrow(gen_ed) > 0) {
    first_area <- gen_ed[!duplicated(gen_ed$subject_course), ]
    desrs$gen_ed_area <- as.integer(first_area$area[match(desrs$SUBJ_CRSE, first_area$subject_course)])
  } else {
    desrs$gen_ed_area <- NA_integer_
    message("  ⚠️  gen_ed_courses.csv has no rows — gen_ed_area will be NA")
  }

  # No unit is written: the section's subject and Banner's section college
  # are its keys, and the loader attaches department, college and
  # college_basis from subjects.csv at every start (ADR-001 step 3). A
  # subject with no confirmed row is listed by the end-of-transform mapping
  # audit and on Admin > Mappings.

  # The instructor ID is hashed as the class list's and cedar_faculty's are,
  # so a section joins both (I52). A section carries no faculty attribute: a
  # reader that wants one joins cedar_faculty on term and instructor_id. (The
  # HR merge that stood here joined the employee ID to hashed IDs, matched
  # nothing, and left job_cat NA on every section; an instructor holding
  # several appointments a term would also have duplicated the section.)
  desrs$PRIM_INST_ID <- hash_instructor_id(desrs$PRIM_INST_ID)

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
      # Banner's section college: the key the loader resolves the subject
      # under. The mapped college and department are attached at load.
      source_college = COLLEGE,
      instructor_id   = as.character(PRIM_INST_ID),
      instructor_name = INST_NAME,
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

  # crosslist_external (does the group span more than one department) and
  # crosslist_partners (the courses in such a group) follow the department,
  # so the loader attaches them with it (attach_section_units()).

  message("  ✅ Crosslist groups detected: ",
          n_distinct(na.omit(cedar_sections$crosslist_group)), " groups")
  message("  ✅   Primaries resolved via SHORT_TEXT: ", length(xl_primary_by_text))
  message("  ✅   Primaries resolved via enrollment fallback: ", length(xl_primary_by_enrl))
  message("  ✅ Split-level groups: ", nrow(split_groups))
  message("  ✅ Deduplicated: ", n_before_dedup, " → ", nrow(cedar_sections),
          " rows (", n_before_dedup - nrow(cedar_sections), " partner-expansion duplicates removed)")
  message("  ✅ Created cedar_sections: ", nrow(cedar_sections), " rows, ", ncol(cedar_sections), " columns")
  message("  Output columns: ", paste(names(cedar_sections), collapse = ", "))

  saved_meta <- save_cedar_file(cedar_sections, "sections", data_dir, ext)
  rm(cedar_sections); gc(verbose = FALSE)

  list(saved = list(sections = saved_meta))
}


# ── 2a. dedup_class_list_rows: one row per student-course-campus-term ───────

#' Keep one class-list row per student, course, campus and term
#'
#' Banner emits one row per CRN, so a student in a combined course (BIOL 302C:
#' a lecture CRN and a lab CRN), a student who switched sections, or one in two
#' sections of a topics course appears more than once. Campus is part of
#' delivery identity: the same student can take one course at two campuses.
#'
#' The row kept is the one STATUS_PRECEDENCE (R/lists/status_codes.R) ranks
#' first: registered (any registered code), then a late drop (the withdrawal
#' is the outcome of record), then a waitlist row, then an early drop. Within
#' a status, a row with a posted grade beats one without (a combined course's
#' graded lecture over its ungraded lab; a credit attempt over an audit in a
#' second section of a topics course), then the lowest CRN, so the choice
#' never depends on row order. Before 2026-11-07 only "registered first" was
#' applied, so a student who early-dropped one section and withdrew late from
#' another could keep the early drop and lose the W: 703 student-course-terms
#' on the 2026-10-08 pull (ISSUES I50).
#'
#' @param students Pre-dedup cedar_registrations rows.
#' @return The rows, one per student_id, term, campus and subject_course.
dedup_class_list_rows <- function(students) {
  missing <- setdiff(c("student_id", "term", "campus", "subject_course", "crn",
                       "registration_status_code", "final_grade"), names(students))
  if (length(missing)) {
    stop("[transform-to-cedar.R] dedup_class_list_rows(): students lacks ",
         paste(missing, collapse = ", "))
  }
  status <- students$registration_status_code
  # An audit is no outcome: a credit attempt in another section beats it.
  grade <- trimws(students$final_grade)
  graded <- !is.na(grade) & nzchar(grade) & !grade %in% GRADES_EXCLUDED_FROM_OUTCOMES
  # Every registered code is one tier; an unlisted status ranks last.
  tier <- match(status, STATUS_PRECEDENCE)
  tier[status %in% STATUS_REGISTERED] <- 0L
  tier[is.na(tier)] <- length(STATUS_PRECEDENCE) + 1L
  keys <- c("student_id", "term", "campus", "subject_course")
  ranked <- students %>%
    dplyr::mutate(.tier = tier, .ungraded = !graded) %>%
    dplyr::arrange(student_id, term, campus, subject_course, .tier, .ungraded, crn)
  kept_first <- !duplicated(ranked[keys])
  # What the ranking decided, for the transform log: a key whose rows hold more
  # than one rank had its row chosen by the ranking, not by being alone.
  in_dup <- duplicated(ranked[keys]) | duplicated(ranked[keys], fromLast = TRUE)
  decided <- ranked[in_dup, , drop = FALSE] %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::filter(dplyr::n_distinct(.tier) > 1L) %>%
    dplyr::summarize(kept = dplyr::first(.tier), .groups = "drop")
  out <- ranked[kept_first, , drop = FALSE] %>% dplyr::select(-.tier, -.ungraded)
  n_removed <- nrow(students) - nrow(out)
  if (n_removed > 0) {
    kept <- ifelse(decided$kept == 0L, "registered",
                   ifelse(decided$kept > length(STATUS_PRECEDENCE), "other",
                          STATUS_PRECEDENCE[pmax(decided$kept, 1L)]))
    kinds <- table(kept)
    kinds <- kinds[kinds > 0]
    message("  Removed ", n_removed, " duplicate section rows; ", nrow(decided),
            " student-course-terms held rows of different statuses; kept: ",
            paste0(names(kinds), " ", as.integer(kinds), collapse = ", "))
  }
  out
}


# ── 2. transform_students: class_lists → cedar_registrations ──────────────────────

#' @param class_lists Raw class_lists data frame (output of parse-data.R)
#' @param data_dir    Path to data directory
#' @param ext         File extension
#' @param maps        Named list of lookup vectors
#' @return list(saved = list(students))
transform_students <- function(class_lists, data_dir, ext, maps) {
  message("──────────────────────────────────────────────────────")
  message("2. Transforming class_lists → cedar_registrations")
  message("──────────────────────────────────────────────────────")
  message("  Loaded ", nrow(class_lists), " rows, ", ncol(class_lists), " columns")
  message("  Input columns: ", paste(names(class_lists), collapse = ", "))

  major_name_to_major_code <- maps$major_name_to_major_code

  # ── Pre-processing ────────────────────────────────────────────────────────
  message("  Pre-processing: deriving helper columns...")

  # The roster's Major Code becomes cedar_registrations$major_code: the student-term
  # table's primary major wherever the student has no declaration that term,
  # and what the mapping audit checks against programs.csv. Its name beside it
  # (major_name) is the audit's context for a code the file does not carry.
  if (!all(c("Major Code", "Major") %in% names(class_lists))) {
    stop("[transform_students] 'Major Code' and/or 'Major' columns absent from class lists export. ",
         "cedar_registrations$major_code and major_name are read from them. Check the Banner class list export format.")
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
    # The course level is derived once here, and reused for the level column
    # below: one classifier, called once per course table (ISSUES.md I5). No
    # unit is written: the subject, Banner's course college and the level are
    # the keys the loader resolves at every start (ADR-001 step 3).
    class_lists$COURSE_LEVEL <- course_level_from_number(class_lists$SUBJ_CRSE)
  }

  # Drop Subject Code and Course Number (now encoded in SUBJ_CRSE); keep transmute inputs.
  class_lists <- class_lists %>%
    dplyr::select(dplyr::any_of(c(
      "Academic Period Code", "Course Reference Number", "Student ID",
      "SUBJ_CRSE", "Short Course Title",
      "Primary Instructor ID", "Primary Instructor Last Name", "Primary Instructor First Name",
      "Course Campus Code", "Course College Code", "COURSE_LEVEL",
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

  cedar_registrations <- class_lists %>% transmute(
      enrollment_id  = row_number(),
      crn            = as.character(`Course Reference Number`),
      student_id     = encrypt_if_needed(`Student ID`),
      term           = as.integer(`Academic Period Code`),
      subject_course = SUBJ_CRSE,
      subject_code   = sub(" .*", "", SUBJ_CRSE),
      course_title   = if ("Short Course Title" %in% names(.)) `Short Course Title` else NA_character_,
      level = dplyr::coalesce(COURSE_LEVEL, "unknown"),
      instructor_id         = if ("Primary Instructor ID"         %in% names(.)) hash_instructor_id(`Primary Instructor ID`) else NA_character_,
      instructor_last_name  = if ("Primary Instructor Last Name"  %in% names(.)) `Primary Instructor Last Name`  else NA_character_,
      instructor_first_name = if ("Primary Instructor First Name" %in% names(.)) `Primary Instructor First Name` else NA_character_,
      instructor_name = case_when(
        !is.na(instructor_last_name) & !is.na(instructor_first_name) ~ paste0(instructor_last_name, ", ", instructor_first_name),
        !is.na(instructor_last_name) ~ instructor_last_name,
        TRUE ~ NA_character_
      ),
      campus     = `Course Campus Code`,
      # Banner's course college: the key the loader resolves the subject
      # under. The mapped college and department are attached at load.
      source_college = `Course College Code`,
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

  # One row per student, course, campus and term (dedup_class_list_rows()).
  # Every outcome is classified from this table at load (cedar_attempts,
  # R/branches/attempts.R); nothing classified is saved.
  cedar_registrations <- dedup_class_list_rows(cedar_registrations)

  # Fill missing major_codes via name → code map
  if (length(major_name_to_major_code) > 0) {
    cedar_registrations <- cedar_registrations %>%
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

  message("  ✅ Created cedar_registrations: ", nrow(cedar_registrations), " rows, ", ncol(cedar_registrations), " columns")
  message("  Output columns: ", paste(names(cedar_registrations), collapse = ", "))
  rm(class_lists); gc(verbose = FALSE)

  # The student's description is saved once per student-term and pull, and the
  # class list without it (ADR-001 step 5): each description column repeated
  # on every course row cost about 14 MB loaded, and every reader takes the
  # student-term table's value. cedar_student_terms is built from the two.
  descriptions_meta <- save_cedar_file(build_class_list_descriptions(cedar_registrations),
                                       "class_list_descriptions", data_dir, ext)
  cedar_registrations <- thin_class_list(cedar_registrations)
  # The file carries the table's name since 2026-11-09 (it was
  # cedar_students.qs); the deploy gate renames a directory's old file once
  # (migrate_class_list_file()).
  students_meta <- save_cedar_file(cedar_registrations, "registrations", data_dir, ext)

  # The per-term and running credit totals that cedar_student_term_credits
  # used to carry are columns of cedar_student_terms (build_student_terms(),
  # ADR-001 step 2), rebuilt whenever this table is.

  rm(cedar_registrations); gc(verbose = FALSE)

  list(
    saved = list(
      students = students_meta,
      class_list_descriptions = descriptions_meta
    )
  )
}


# ── 2b. transform_student_terms: students + programs + degrees → cedar_student_terms

#' One row per student-term, built from the saved CEDAR tables (ADR-001 step 2;
#' contract in docs/developers/student-terms.md). The build itself is
#' build_student_terms() in R/branches/student-terms.R; this stage only loads
#' its inputs, computes the data edges it needs, and saves the result.
#'
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @return list(saved = list(student_terms = <meta>))
transform_student_terms <- function(data_dir, ext) {
  message("──────────────────────────────────────────────────────")
  message("4b. Transforming cedar_registrations + cedar_programs + cedar_degrees → cedar_student_terms")
  message("──────────────────────────────────────────────────────")
  load_saved <- function(name) {
    path <- file.path(data_dir, paste0("cedar_", name, ext))
    if (!file.exists(path)) {
      stop("[transform-to-cedar.R] cedar_student_terms needs ", path, ", which has not been built.")
    }
    message("  Loading: ", path)
    load_file(path, ext)
  }
  students <- load_saved("registrations")
  descriptions_path <- file.path(data_dir, paste0("cedar_class_list_descriptions", ext))
  descriptions <- resolve_class_list_descriptions(
    if (file.exists(descriptions_path)) load_file(descriptions_path, ext) else NULL,
    students, "transform_student_terms()")
  students <- thin_class_list(students)
  programs <- load_saved("programs")
  degrees  <- load_saved("degrees")
  edges <- cedar_data_edges(students, degrees = degrees)
  student_terms <- build_student_terms(students, programs, degrees, edges = edges,
                                       class_list_descriptions = descriptions)
  rm(students, descriptions, programs, degrees); gc(verbose = FALSE)
  meta <- save_cedar_file(student_terms, "student_terms", data_dir, ext)
  message("  ✅ cedar_student_terms: ", nrow(student_terms), " rows, ", ncol(student_terms), " columns")
  list(saved = list(student_terms = meta))
}

#' Why cedar_student_terms needs rebuilding, or NULL when it does not
#'
#' The table is built from three saved tables, so it can be missing (a deploy
#' before any refresh has run this stage), older than a source rebuilt
#' without it, or built by an older builder that wrote fewer columns than the
#' code now deployed reads. The deploy gate
#' (scripts/rebuild-programs-if-mappings-changed.R) asks this and builds the
#' table, as it does a stale mapped table, so the app, which requires the file
#' and its columns, never starts without them.
#'
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @return A one-line reason, or NULL when the file exists, is newer than
#'   every saved source it reads, and carries every column the builder writes.
cedar_student_terms_staleness <- function(data_dir, ext = ".qs") {
  target <- file.path(data_dir, paste0("cedar_student_terms", ext))
  if (!file.exists(target)) return("cedar_student_terms has not been built")
  sources <- file.path(data_dir, paste0("cedar_", c("registrations", "class_list_descriptions",
                                                    "programs", "degrees"), ext))
  sources <- sources[file.exists(sources)]
  newer <- sources[file.mtime(sources) > file.mtime(target)]
  if (length(newer) > 0L) {
    return(paste0(paste(sub(ext, "", basename(newer), fixed = TRUE), collapse = ", "),
                  " newer than cedar_student_terms"))
  }
  # A column the builder gained since the file was written (the completed-credit
  # running total, 2026-11-04) is a schema change no file time records: the app
  # would start and the first reader of that column would fail. Compare the
  # saved names with what build_student_terms() writes today.
  saved <- load_file(target, ext)
  missing <- setdiff(STUDENT_TERMS_COLUMNS, names(saved))
  if (length(missing) > 0L) {
    return(paste0("saved cedar_student_terms lacks column(s) the builder now writes: ",
                  paste(missing, collapse = ", ")))
  }
  # A rule change that moves values without adding a column (the class-list
  # primary major, 2026-11-04) is recorded only by the stamp the builder
  # writes. A table with no stamp predates stamping.
  built_under <- attr(saved, "cedar_student_terms_build_version")
  if (is.null(built_under) || as.integer(built_under) < STUDENT_TERMS_BUILD_VERSION) {
    return(paste0("saved cedar_student_terms was built under rule version ",
                  if (is.null(built_under)) "1 (unstamped)" else built_under,
                  "; the builder is at ", STUDENT_TERMS_BUILD_VERSION))
  }
  NULL
}


# ── 2c. transform_measures: the keyed class list → the measure tables ────────

#' The three measure tables, built as the app would have built them (ADR-001
#' step 6)
#'
#' cedar_attempts (build_attempts()), cedar_course_terms (build_course_terms())
#' and cedar_course_flows (build_course_flows()) are counted over the class
#' list exactly as global.R loads it: trimmed to the app's first term, keyed
#' on the course and carrying the default units from the same mapping files.
#' Each is stamped with the fingerprint of those files and the first term, so
#' the loader can refuse one built from other files or over another window
#' (cedar_load_measure_table()); the builders' own stamps (build version,
#' outcome policy, edge, course-code renames) are on it too. The app never
#' builds one: a restart is a load.
#'
#' Built one at a time, each saved and dropped before the next: the refresh
#' runs this beside the live app on the production host.
#'
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @param min_term The first term the app loads (cedar_min_term in
#'   config/shiny_config.R); required, because the renames stamped on each
#'   table are those the trimmed class list shows.
#' @param dims     The dimensions (build_cedar_dims()); a parameter so a test
#'   can pass its own.
#' @param edges    The data edges to count to; by default cedar_report_edges()
#'   over the trimmed class list and the saved degrees, which stops when the
#'   settled or graded edge cannot be determined. A parameter so a test can
#'   state its edge, as the course-flow tests do.
#' @return list(saved = list(attempts = <meta>, course_terms = <meta>,
#'   course_flows = <meta>))
transform_measures <- function(data_dir, ext, min_term, dims = build_cedar_dims(), edges = NULL) {
  message("──────────────────────────────────────────────────────")
  message("4c. Transforming the keyed class list → cedar_attempts, cedar_course_terms, cedar_course_flows")
  message("──────────────────────────────────────────────────────")
  if (!is.numeric(min_term) || length(min_term) != 1L || is.na(min_term)) {
    stop("[transform-to-cedar.R] transform_measures() needs min_term, the first term the app ",
         "loads (cedar_min_term in config/shiny_config.R): the course-code renames stamped on ",
         "each measure table are those the trimmed class list shows.")
  }
  min_term <- as.integer(min_term)
  load_saved <- function(name) {
    path <- file.path(data_dir, paste0(cedar_table_file(paste0("cedar_", name)), ext))
    if (!file.exists(path)) {
      stop("[transform-to-cedar.R] the measure tables need ", path, ", which has not been built.")
    }
    message("  Loading: ", path)
    load_file(path, ext)
  }
  # As global.R loads them: trimmed first, then the default units and the
  # course ids attached from the files the app reads.
  students <- thin_class_list(load_saved("registrations"))
  students <- students[students$term >= min_term, , drop = FALSE]
  sections <- load_saved("sections")
  sections <- sections[sections$term >= min_term, , drop = FALSE]
  message(sprintf("  Class list trimmed to term >= %d: %s rows", min_term,
                  format(nrow(students), big.mark = ",")))
  keyed    <- attach_default_units(list(cedar_registrations = students, cedar_sections = sections), dims)
  courses  <- build_cedar_courses(keyed$cedar_sections, keyed$cedar_registrations, dims)
  keyed    <- attach_course_ids(keyed, courses)
  students <- keyed$cedar_registrations
  sections <- keyed$cedar_sections
  rm(keyed, courses); gc(verbose = FALSE)
  if (is.null(edges)) {
    degrees <- load_saved("degrees")
    degrees <- degrees[degrees$term >= min_term, , drop = FALSE]
    edges <- cedar_report_edges(students, degrees = degrees)$edges
    rm(degrees)
  }
  message(sprintf("  Edges: graded through %s, settled through %s",
                  edges$last_graded, edges$last_enrolled_complete))

  fingerprint <- cedar_dims_fingerprint(dims)
  stamp <- function(tbl) {
    attr(tbl, "cedar_dims_fingerprint") <- fingerprint
    attr(tbl, "cedar_min_term") <- min_term
    tbl
  }
  saved <- list()
  attempts <- stamp(build_attempts(students, edges))
  saved$attempts <- save_cedar_file(attempts, "attempts", data_dir, ext)
  course_terms <- stamp(build_course_terms(students, attempts, sections))
  saved$course_terms <- save_cedar_file(course_terms, "course_terms", data_dir, ext)
  rm(attempts, course_terms, sections); gc(verbose = FALSE)
  flows <- stamp(build_course_flows(students, edges))
  saved$course_flows <- save_cedar_file(flows, "course_flows", data_dir, ext)
  rm(flows, students); gc(verbose = FALSE)
  message("  ✅ The measure tables are built; the app loads them and never builds them.")
  list(saved = saved)
}

#' Why the measure tables need rebuilding, or NULL when they do not
#'
#' The deploy gate's question (scripts/rebuild-programs-if-mappings-changed.R),
#' answered without loading the class list: each table must exist, be newer
#' than the saved class list, carry its builder's current build version (and,
#' for cedar_attempts, the outcome policy) and columns, and be stamped with
#' the fingerprint of the mapping files now deployed and the first term the
#' app loads. A mapping PR therefore rebuilds the measures at deploy, in the
#' gate's own process, before the app starts: their unit columns are the
#' files'. The loader's full check (the edge and the course-code renames
#' against the loaded class list) stays in cedar_load_measure_table().
#'
#' @param data_dir Path to data directory
#' @param ext      File extension
#' @param dims     The dimensions now deployed (build_cedar_dims()).
#' @param min_term The first term the app loads (cedar_min_term).
#' @return A one-line reason, or NULL.
cedar_measures_staleness <- function(data_dir, ext = ".qs", dims = build_cedar_dims(), min_term) {
  if (missing(min_term) || !is.numeric(min_term) || length(min_term) != 1L || is.na(min_term)) {
    stop("[transform-to-cedar.R] cedar_measures_staleness() needs min_term (cedar_min_term)")
  }
  class_list_name <- cedar_table_file("cedar_registrations")
  class_list <- file.path(data_dir, paste0(class_list_name, ext))
  if (!file.exists(class_list)) return(paste0(class_list_name, " has not been built"))
  fingerprint <- cedar_dims_fingerprint(dims)
  contracts <- list(
    cedar_attempts = list(version_attr = "attempts_build_version",
                          version = ATTEMPTS_BUILD_VERSION, columns = ATTEMPTS_COLUMNS),
    cedar_course_terms = list(version_attr = "course_terms_build_version",
                              version = COURSE_TERMS_BUILD_VERSION, columns = COURSE_TERMS_COLUMNS),
    cedar_course_flows = list(version_attr = "course_flows_build_version",
                              version = COURSE_FLOWS_BUILD_VERSION,
                              columns = names(empty_next_course_pairs()))
  )
  for (name in CEDAR_MEASURE_TABLES) {
    contract <- contracts[[name]]
    path <- file.path(data_dir, paste0(name, ext))
    if (!file.exists(path)) return(paste0(name, " has not been built"))
    if (file.mtime(path) < file.mtime(class_list)) {
      return(paste0(class_list_name, " newer than ", name))
    }
    saved <- load_file(path, ext)
    built_under <- attr(saved, contract$version_attr, exact = TRUE)
    if (!identical(built_under, contract$version)) {
      return(paste0("saved ", name, " was built under build version ",
                    if (is.null(built_under)) "unknown (unstamped)" else built_under,
                    "; the builder is at ", contract$version))
    }
    if (name == "cedar_attempts") {
      policy <- attr(saved, "cedar_outcome_policy_version", exact = TRUE)
      if (!identical(policy, CEDAR_OUTCOME_POLICY_VERSION)) {
        return(paste0("saved cedar_attempts was classified under outcome policy ",
                      if (is.null(policy)) "unknown (unstamped)" else policy,
                      "; the policy is at ", CEDAR_OUTCOME_POLICY_VERSION))
      }
    }
    if (!identical(names(saved), contract$columns)) {
      missing <- setdiff(contract$columns, names(saved))
      return(paste0("saved ", name, if (length(missing)) " lacks column(s) the builder now writes: "
                    else " carries other columns than the builder now writes: ",
                    paste(if (length(missing)) missing else names(saved), collapse = ", ")))
    }
    if (!identical(attr(saved, "cedar_dims_fingerprint", exact = TRUE), fingerprint)) {
      return(paste0("saved ", name, " was built from other mapping files"))
    }
    built_from <- attr(saved, "cedar_min_term", exact = TRUE)
    if (!identical(as.integer(built_from), as.integer(min_term))) {
      return(paste0("saved ", name, " starts at term ",
                    if (is.null(built_from)) "unknown (unstamped)" else built_from,
                    "; the app starts at ", min_term))
    }
    rm(saved)
  }
  NULL
}


# ── 3. transform_programs: academic_studies → cedar_programs ─────────────────

#' @param academic_studies Raw academic_studies data frame
#' @param data_dir         Path to data directory
#' @param ext              File extension
#' @param maps             Named list of lookup vectors
#' @return list(saved = list(programs = <meta>))
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
      # Banner's two college values, the keys the loader resolves each
      # program under (ADR-001 step 3): the Translated College as recorded,
      # and the Actual College as a code, through colleges.csv (its names and
      # source_names), so a renamed college still resolves. The mapped
      # program_college, college_code and student_college are attached at load.
      source_college         = `Translated College`,
      source_college_code    = translate_source_college(`Actual College`, files),
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
        student_classification, student_level, student_campus, source_college, source_college_code,
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
    # Fill missing major_codes via name → code map before dept lookup, for
    # older formats that lack a Banner code column. Never for a concentration:
    # it has no code (code_col = NULL), and a concentration named like a major
    # is not that major (ISSUES.md I21).
    # Strip "Pre-" prefix so "Pre-History" resolves the same as "History".
    dplyr::mutate(
      .concentration = grepl("Concentration", program_type),
      # unname(): the lookup's names otherwise ride along on the whole column,
      # and a named column reaches the browser as a JSON object, not an array.
      major_code = unname(dplyr::if_else(
        !.concentration & is.na(major_code) & !is.na(program_name) & nzchar(program_name),
        major_name_to_major_code[stringr::str_trim(
          sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)
        )],
        major_code
      ))
    ) %>%
    dplyr::mutate(
      # No unit is written here (ADR-001 step 3): the loader resolves each
      # row's major_code under its source_college_code through programs.csv
      # at every start, a concentration under its primary major, and a code
      # with no confirmed row to NA, never a department named after itself
      # (ISSUES.md I7).
      # is_pre_major comes from programs.csv, stated per code (ADR-002 Stage 4),
      # not inferred from an F prefix. Banner's own program records name every
      # F and XF code the old rule exempted or missed "Pre-" (BS Pre-Exercise
      # Science, BBA Pre-Business Admin), and the branch "Pre-" programs (AS
      # Pre-Engineering) are associate degrees students are admitted to, so not
      # pre-majors (reviewed 2026-10-10). A code with no programs.csv row falls
      # back to Banner's own word, a "Pre-" program name, and says so in
      # pre_major_basis. A concentration is never a pre-major: it is a track
      # within a major, not a program a student is admitted to, so Banner's
      # "Pre-Law" concentration keeps its name and its own row stays FALSE
      # (ISSUES.md I21). A pre-major student's major row still says so.
      .pre_in_file = program_pre_major_flags(major_code, files$programs),
      .pre_by_name = grepl("^Pre[- ]", program_name, ignore.case = TRUE),
      # PHRD was the code for undergraduate pre-pharmacy before 202580 (FPHS
      # since): a row-level fact a per-code flag cannot state. Recorded in
      # CEDAR_DATA_SEMANTICS as phrd-undergraduate-pre-pharmacy.
      .pre_by_phrd = major_code %in% "PHRD" & student_level %in% c("UG", "NG"),
      is_pre_major = dplyr::case_when(
        .concentration       ~ FALSE,
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
      # Strip "Pre-" prefix from a program's name for clean display; a
      # concentration keeps Banner's name.
      program_name = dplyr::if_else(
        !.concentration & grepl("^Pre[- ]", program_name, ignore.case = TRUE),
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
    dplyr::select(-dplyr::any_of(c(".concentration", ".pre_in_file", ".pre_by_name", ".pre_by_phrd")))

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

  message("  ✅ Created cedar_programs: ", nrow(cedar_programs), " rows, ", ncol(cedar_programs), " columns")
  message("  Output columns: ", paste(names(cedar_programs), collapse = ", "))
  message("  Program type breakdown:")
  for (pt in unique(cedar_programs$program_type))
    message("     ", pt, ": ", sum(cedar_programs$program_type == pt))

  saved_meta <- save_cedar_file(cedar_programs, "programs", data_dir, ext)
  rm(cedar_programs); gc(verbose = FALSE)

  list(saved = list(programs = saved_meta))
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
      # Banner's two college values, the keys the loader resolves the degree's
      # program under (ADR-001 step 3); dept_code, college_code, college and
      # student_college are attached at load.
      source_student_college = if ("Actual College" %in% names(.)) `Actual College` else NA_character_,
      source_college = `Translated College`,
      degree         = Degree,
      award_category = if ("Award Category" %in% names(.)) `Award Category` else NA_character_,
      program_code   = `Program Code`,
      program_name   = Program,
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
    dplyr::mutate(degree_abbr = sub("^([A-Za-z]+)-.*$", "\\1", program_code))

  message("  ✅ Created cedar_degrees: ", nrow(cedar_degrees), " rows, ", ncol(cedar_degrees), " columns")
  message("  Output columns: ", paste(names(cedar_degrees), collapse = ", "))

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
      instructor_id   = hash_instructor_id(`UNM ID`),
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
#'                          "faculty", "applicants"
#' @return Invisibly: named list of save metadata for each table written
transform_to_cedar <- function(data_dir = NULL, use_qs = NULL, tables = NULL,
                               include_student_terms = TRUE, min_term = NULL) {

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
  all_tables <- c("sections", "students", "programs", "degrees", "student_terms", "measures",
                  "faculty", "applicants")
  if (is.null(tables)) {
    run_tables <- all_tables
  } else {
    unknown <- setdiff(tables, all_tables)
    if (length(unknown) > 0)
      message("  ⚠️  Unknown table(s) ignored: ", paste(unknown, collapse = ", "))
    run_tables <- intersect(all_tables, tables)
    # The derived tables read the saved tables, so each is rebuilt whenever a
    # table it reads is: the student-term table on students, programs or
    # degrees; the measure tables on students (ADR-001 step 6). A caller that
    # will build them in later runs of its own (the deploy gate, one stage per
    # process so no process carries four tables' heap into these) says so.
    if (isTRUE(include_student_terms) &&
        any(c("students", "programs", "degrees") %in% run_tables) && !"student_terms" %in% run_tables) {
      run_tables <- c(run_tables, "student_terms")
      message("  Note: Adding student_terms (auto-included when students/programs/degrees are transformed)")
    }
    if (isTRUE(include_student_terms) && "students" %in% run_tables && !"measures" %in% run_tables) {
      run_tables <- c(run_tables, "measures")
      message("  Note: Adding measures (auto-included when students are transformed)")
    }
  }
  # The measure tables are counted over the class list as the app loads it,
  # from its first term; that term is a setting the stage must be given.
  if ("measures" %in% run_tables) {
    min_term <- min_term %||% (if (exists("cedar_min_term")) cedar_min_term else NULL)
    if (is.null(min_term)) {
      stop("[transform-to-cedar.R] The measure tables need min_term, the first term the app loads: ",
           "pass min_term, or define cedar_min_term (config/shiny_config.R) before calling.")
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
  needed <- c("read_institution_mappings", "major_name_to_major_code", "CEDAR_GEN_ED_COURSES")
  missing <- needed[!vapply(needed, exists, logical(1))]
  if (length(missing)) {
    stop("[transform-to-cedar.R] CEDAR's lists are not loaded (run load_funcs() first); missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

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
    gen_ed = CEDAR_GEN_ED_COURSES
  )

  # Initialize results tracking
  saved_files       <- list()

  # ── 1. cedar_sections ─────────────────────────────────────────────────────
  if ("sections" %in% run_tables) {
    desr_file <- file.path(data_dir, paste0("DESRs", ext))
    if (file.exists(desr_file)) {
      message("\nLoading: ", desr_file)
      desrs  <- load_file(desr_file, ext)
      result <- transform_sections(desrs, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      rm(desrs); gc(verbose = FALSE)
    } else {
      message("  ⚠️  DESRs file not found: ", desr_file, " — skipping cedar_sections")
    }
  } else {
    message("  ⏭  Skipping cedar_sections (not in --tables)")
  }

  # ── 2. cedar_registrations ─────────────────────────────────────────────────────
  if ("students" %in% run_tables) {
    cl_file <- file.path(data_dir, paste0("class_lists", ext))
    if (file.exists(cl_file)) {
      message("\nLoading: ", cl_file)
      class_lists <- load_file(cl_file, ext)
      result      <- transform_students(class_lists, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
      rm(class_lists); gc(verbose = FALSE)
    } else {
      message("  ⚠️  class_lists file not found: ", cl_file, " — skipping cedar_registrations")
    }
  } else {
    message("  ⏭  Skipping cedar_registrations (not in --tables)")
  }

  # ── 3. cedar_programs ─────────────────────────────────────────────────────
  if ("programs" %in% run_tables) {
    as_file <- file.path(data_dir, paste0("academic_studies", ext))
    if (file.exists(as_file)) {
      message("\nLoading: ", as_file)
      academic_studies <- load_file(as_file, ext)
      result           <- transform_programs(academic_studies, data_dir, ext, maps)
      saved_files <- c(saved_files, result$saved)
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

  # ── 4b. cedar_student_terms ───────────────────────────────────────────────
  # Reads the SAVED students, programs and degrees, whichever of them this run
  # rebuilt, so a --tables programs run still produces a table that matches
  # every stored source.
  if ("student_terms" %in% run_tables) {
    result <- transform_student_terms(data_dir, ext)
    saved_files <- c(saved_files, result$saved)
  } else {
    message("  ⏭  Skipping cedar_student_terms (not in --tables)")
  }

  # ── 4c. the measure tables ────────────────────────────────────────────────
  # Reads the SAVED class list, sections and degrees, so a --tables students
  # run produces measures that match the stored class list (ADR-001 step 6).
  if ("measures" %in% run_tables) {
    result <- transform_measures(data_dir, ext, min_term = min_term)
    saved_files <- c(saved_files, result$saved)
  } else {
    message("  ⏭  Skipping the measure tables (not in --tables)")
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
    c(sections = "cedar_sections", students = "cedar_registrations",
      programs = "cedar_programs", degrees = "cedar_degrees"),
    function(name) {
      path <- file.path(data_dir, paste0(name, ext))
      if (file.exists(path)) load_file(path, ext) else NULL
    })
  # The roster's majors are on the description table (or, in a class list
  # saved before 2026-11-07, on the class list itself).
  descriptions_path <- file.path(data_dir, paste0("cedar_class_list_descriptions", ext))
  audit_majors <- if (!is.null(audit_tables$students)) {
    summarize_class_list_majors(resolve_class_list_descriptions(
      if (file.exists(descriptions_path)) load_file(descriptions_path, ext) else NULL,
      audit_tables$students, "mapping audit"))
  }
  audit_tables$students <- if (!is.null(audit_tables$students)) thin_class_list(audit_tables$students)
  mapping_audit <- do.call(audit_mapping_coverage,
                           c(list(files = read_institution_mappings()), audit_tables,
                             list(class_list_majors = audit_majors)))
  message("  ", summarize_mapping_audit(mapping_audit))
  for (i in which(mapping_audit$status == "unmapped")) {
    message(sprintf("    %-14s %-10s %s rows, %s", mapping_audit$kind[i], mapping_audit$value[i],
                    format(mapping_audit$rows[i], big.mark = ","), mapping_audit$context[i]))
  }
  rm(audit_tables, audit_majors, mapping_audit); gc(verbose = FALSE)

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
      # A run over the local directory itself (--data-dir data/) saved the file
      # where the copy would put it: file.copy() onto its own source truncates
      # it to nothing (three empty measure tables, 2026-11-08), so leave it.
      if (identical(normalizePath(info$filepath, mustWork = FALSE),
                    normalizePath(dest_path, mustWork = FALSE))) {
        message("  ", info$filename, " is already in local data/")
        next
      }
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
    # The file's own name: the class list is saved under the table's name,
    # cedar_registrations, while its stage is still called "students".
    message("  ✅ ", info$filename %||% paste0("cedar_", name, ext), " (",
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
  # does. Without them the mapping files, the dimension tables and the mapping
  # audit have nothing to call (ISSUES.md I13).
  source(file.path("R", "trunk", "load-funcs.R"))
  load_funcs(getwd(), modules = FALSE)
  # The measure tables start at the app's first term, a setting in the app's
  # config. Read that one value without the file's other side effects.
  if (file.exists("config/shiny_config.R")) {
    shiny_settings <- new.env()
    sys.source("config/shiny_config.R", envir = shiny_settings)
    if (exists("cedar_min_term", envir = shiny_settings, inherits = FALSE)) {
      cedar_min_term <- get("cedar_min_term", envir = shiny_settings)
    }
    rm(shiny_settings)
  }

  args         <- commandArgs(trailingOnly = TRUE)
  data_dir_arg <- NULL
  tables_arg   <- NULL
  include_student_terms <- !"--without-student-terms" %in% args

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

  transform_to_cedar(data_dir = data_dir_arg, tables = tables_arg,
                     include_student_terms = include_student_terms)
}
