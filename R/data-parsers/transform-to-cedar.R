# transform-to-cedar.R
#
# Transforms existing MyReports-based data files to CEDAR data model
# This runs AFTER parse-data.R and creates cedar_* files alongside existing files
#
# IMPORTANT: This does NOT modify existing workflow - all current files remain unchanged
# New CEDAR files are created in parallel with names: cedar_sections.qs, cedar_students.qs, etc.
#
# ⚠️  SCHEMA SYNC REQUIREMENT:
# When adding columns to cedar_* tables here, you MUST also update:
# 1. tests/testthat/create-test-fixtures.R - Add same columns to test fixtures
# 2. global.R validation_specs - Update if new columns are required
# 3. docs/data-model.md - Document the new columns
#
# Run after changes: Rscript tests/testthat/create-test-fixtures.R
#
# Recent schema changes:
# - Mar 2026: Added residency, academic_standing, inst_gpa to cedar_programs (from academic_studies)
# - Mar 2026: Added is_pre_major to cedar_programs (F-prefix major_code + "Pre-" name prefix)
# - Mar 2026: PHRD + student_level UG/NG → is_pre_major = TRUE (UNM used PHRD for pre-pharmacy UGs until 202580, then switched to FPHS)
# - Mar 2026: Added is_topics to cedar_sections (TRUE when course_title starts with "T:")
# - Jan 2026: Removed duplicate 'grade' column; use 'final_grade' as standard column name
# - Jan 2026: Added subject_code, level, instructor_id to cedar_students (for credit-hours)
# - Jan 2026: Added student_level, student_college, student_campus to cedar_programs (for headcount)
# - Jan 2026: Removed alias columns to reduce confusion:
#     - cedar_students: removed 'primary_major' alias (use 'major' only)
#     - cedar_degrees: removed 'degree_term' (use 'term'), 'degree_type' (use 'degree'),
#                      'program' (use 'major_code'), 'actual_college' (use 'student_college')

library(tidyverse)
library(digest)

source("R/trunk/utils.R")  # for term_code_lookup and term_diff functions

#' Transform MyReports data to CEDAR model
#'
#' Reads existing parsed data files (DESRs, class_lists, etc.) and creates
#' new CEDAR model files (cedar_sections, cedar_students, etc.)
#'
#' This script is designed to run daily after parse-data.R completes.
#' It will OVERWRITE existing cedar_* files with the latest data.
#'
#' @param data_dir Path to data directory (default: from config)
#' @param use_qs Use .qs format (default: from config)
#' @return List of CEDAR data objects
transform_to_cedar <- function(data_dir = NULL, use_qs = NULL, tables = NULL) {

  message("\n")
  message("═══════════════════════════════════════════════════════")
  message("  CEDAR Data Model Transformation (Daily Update)")
  message("═══════════════════════════════════════════════════════")
  message("\n")

  # Check if we're running inside a Docker container (detect early)
  is_docker <- Sys.getenv("docker") == "TRUE" || file.exists("/.dockerenv")

  # Get data directory from config if not provided
  if (is.null(data_dir)) {
    if (is_docker) {
      message("No data_dir provided, using config cedar_data_docker_dir (Docker environment)...")
      data_dir <- if (exists("cedar_data_docker_dir")) cedar_data_docker_dir else "data/"
    } else {
      message("No data_dir provided, using config cedar_shared_data_dir ...")
      data_dir <- if (exists("cedar_shared_data_dir")) cedar_shared_data_dir else "data/"
    }
  } else {
    message("Using provided data_dir: ", data_dir)
  }

  # Get qs preference from config if not provided
  if (is.null(use_qs)) {
    use_qs <- if (exists("cedar_use_qs")) cedar_use_qs else TRUE
  }

  ext <- if (use_qs && requireNamespace("qs", quietly = TRUE)) ".qs" else ".Rds"

  # Resolve which tables to transform
  all_tables <- c("sections", "students", "programs", "degrees", "faculty", "lookups")
  if (is.null(tables)) {
    run_tables <- all_tables
  } else {
    unknown <- setdiff(tables, all_tables)
    if (length(unknown) > 0)
      message("  ⚠️  Unknown table(s) ignored: ", paste(unknown, collapse = ", "))
    run_tables <- intersect(all_tables, tables)
    # Auto-include lookups when sections/programs/degrees are being transformed
    if (any(c("sections", "programs", "degrees") %in% run_tables) && !"lookups" %in% run_tables) {
      run_tables <- c(run_tables, "lookups")
      message("  Note: Adding lookups (auto-included when sections/programs/degrees are transformed)")
    }
  }

  message("Configuration:")
  message("  Data directory: ", data_dir)
  message("  File format: ", ext)
  message("  Tables: ", paste(run_tables, collapse = ", "))
  message("\n")

  # Initialize tracking for saved files
  saved_files <- list()
  
  # Helper function to save a CEDAR file immediately and free memory
  save_cedar_file <- function(data, table_name, data_dir, ext) {
    filename <- paste0("cedar_", table_name, ext)
    filepath <- file.path(data_dir, filename)
    
    message("Saving: ", filepath)
    
    if (ext == ".qs") {
      qs::qsave(data, filepath, preset = "fast")
    } else {
      saveRDS(data, filepath)
    }
    
    # Get file size
    file_size_mb <- file.size(filepath) / 1024^2
    row_count <- nrow(data)
    message("  ✅ Saved (", round(file_size_mb, 1), " MB, ",
            format(row_count, big.mark = ","), " rows)")
    
    # Extract metadata from data while still in memory (cheap scalar ops)
    as_of <- if ("as_of_date" %in% names(data)) {
      tryCatch(format(max(data$as_of_date, na.rm = TRUE)), error = function(e) NA_character_)
    } else NA_character_
    min_term <- if ("term" %in% names(data)) {
      tryCatch(as.character(min(data$term, na.rm = TRUE)), error = function(e) NA_character_)
    } else NA_character_
    max_term <- if ("term" %in% names(data)) {
      tryCatch(as.character(max(data$term, na.rm = TRUE)), error = function(e) NA_character_)
    } else NA_character_

    # Return metadata for tracking
    list(
      filename = filename,
      filepath = filepath,
      rows = row_count,
      size_mb = file_size_mb,
      as_of_date = as_of,
      min_term = min_term,
      max_term = max_term
    )
  }

  # Initialize cedar_data for temporary storage (used by lookups generation)
  cedar_data <- list()

  # Helper: encrypt student IDs if not already hashed (64-char hex = already encrypted)
  encrypt_if_needed <- function(id) {
    if (all(nchar(as.character(id)) == 64)) return(as.character(id))
    salt <- Sys.getenv("CEDAR_STUDENT_SALT")
    if (salt == "") salt <- "cedar_default_salt_change_me"
    sapply(id, function(x) digest(paste0(x, salt), algo = "sha256"))
  }

  # ── Load helper maps (once, before any pre-processing steps) ─────────────────
  # When running standalone (Rscript), these may not be in the environment yet.
  # When called from parse-data.R, they're already sourced — the exists() guards
  # prevent double-sourcing.
  #
  # Resolve the cedar project root: prefer the script's own directory (two levels up
  # from R/data-parsers/), fall back to getwd(). This works whether data_dir is
  # inside or outside the cedar project (e.g., a shared-data sibling directory).
  script_path <- tryCatch(
    normalizePath(sys.frame(0)$ofile, mustWork = TRUE),
    error = function(e) NULL
  )
  if (!is.null(script_path)) {
    cedar_root <- dirname(dirname(dirname(script_path)))  # R/data-parsers → R → project root
  } else {
    cedar_root <- getwd()
  }
  catalog_file   <- file.path(cedar_root, "R", "lists", "unit_catalog.R")
  prog_cat_file  <- file.path(cedar_root, "R", "lists", "major_dept_map.R")
  cat_lookups_file <- file.path(cedar_root, "R", "lists", "catalog_lookups.R")
  mappings_file  <- file.path(cedar_root, "R", "lists", "mappings.R")
  gen_ed_file    <- file.path(cedar_root, "R", "lists", "gen_ed_courses.R")

  # Load unit_catalog + major_dept_map, then derive all lookup vectors from them.
  # catalog_lookups.R does the derivation; it must be sourced after both catalog files.
  if (!exists("unit_catalog") && file.exists(catalog_file)) {
    message("  Loading unit_catalog from: ", catalog_file)
    source(catalog_file)
  }
  if (!exists("major_dept_map") && file.exists(prog_cat_file)) {
    message("  Loading major_dept_map from: ", prog_cat_file)
    source(prog_cat_file)
  }
  if (exists("unit_catalog") && exists("major_dept_map")) {
    message("  Deriving lookup vectors from catalogs...")
    source(cat_lookups_file)
    # Alias for the lookups section below
    dept_code_to_name_catalog <- dept_code_to_name
    message("  unit_catalog: ", nrow(unit_catalog), " rows, ",
            length(unique(unit_catalog$subject_code)), " subject codes, ",
            length(unique(unit_catalog$dept_code)), " dept codes, ",
            length(unique(unit_catalog$college_code)), " colleges")
    message("  major_dept_map: ", nrow(major_dept_map), " rows, ",
            length(major_college_to_dept), " compound lookup keys")
  } else {
    message("  ⚠️  unit_catalog or major_dept_map not found — falling back to mappings.R")
    major_college_to_dept <- setNames(character(0), character(0))
    if (!exists("subj_to_dept") && file.exists(mappings_file)) source(mappings_file)
  }

  # Load mappings.R for text/name maps not derivable from catalogs:
  #   major_to_program, hr_org_desc_to_dept.
  if (!exists("hr_org_desc_to_dept") && file.exists(mappings_file)) {
    message("  Loading text mappings from: ", mappings_file)
    source(mappings_file)
  }
  if (!exists("gen_ed_1_communication") && file.exists(gen_ed_file)) {
    message("  Loading gen_ed courses from: ", gen_ed_file)
    source(gen_ed_file)
  }

  # ========================================
  # 1. Transform DESRs → cedar_sections
  # ========================================
  message("──────────────────────────────────────────────────────")
  message("1. Transforming DESRs → cedar_sections")
  message("──────────────────────────────────────────────────────")

  desr_file <- file.path(data_dir, paste0("DESRs", ext))

  if (!"sections" %in% run_tables) {
    message("  ⏭  Skipping cedar_sections (not in --tables)")
  } else if (file.exists(desr_file)) {
    message("Loading: ", desr_file)

    if (ext == ".qs") {
      desrs <- qs::qread(desr_file)
    } else {
      desrs <- readRDS(desr_file)
    }

    message("  Loaded ", nrow(desrs), " rows, ", ncol(desrs), " columns")
    message("  Input columns: ", paste(names(desrs), collapse=", "))

    # ── Pre-processing: derive helper columns from raw DESR data ─────────────
    # parse-DESR.R is now a pure aggregator (renames + dedup only).
    # All column derivation lives here so the full pipeline is in one place.
    message("  Pre-processing: deriving helper columns...")

    # Display/join unites
    desrs <- desrs %>%
      unite(SUBJ_CRSE, c("SUBJ", "CRSE"),       sep = " ",  remove = FALSE) %>%
      unite(INST_NAME, c("PRIM_INST_LAST", "PRIM_INST_FIRST"), sep = ", ", remove = FALSE)

    # Lab detection and numeric course base
    desrs <- desrs %>%
      mutate(
        lab      = grepl("[[:alpha:]]", CRSE),
        crse_base = as.integer(ifelse(lab,
                      substr(CRSE, 1, nchar(CRSE) - 1),
                      CRSE))
      )

    # Total enrollment: max(section, crosslist total) — effective enrollment
    desrs <- desrs %>%
      mutate(total_enrl = as.numeric(pmax(ENROLLED, XL_ENRL, na.rm = TRUE)))

    # Course level
    desrs <- desrs %>%
      mutate(level = dplyr::case_when(
        crse_base < 300                        ~ "lower",
        crse_base >= 1000                      ~ "lower",
        crse_base >= 500 & crse_base < 700     ~ "grad",
        crse_base >= 300 & crse_base < 500     ~ "upper"
      ))

    # Term type (from last two digits of term code)
    desrs <- desrs %>%
      mutate(term_type = dplyr::case_when(
        substr(as.character(TERM), 5, 6) == "80" ~ "fall",
        substr(as.character(TERM), 5, 6) == "10" ~ "spring",
        substr(as.character(TERM), 5, 6) == "60" ~ "summer",
        TRUE ~ NA_character_
      ))

    # Gen ed area (requires gen_ed_* vectors from gen_ed_courses.R)
    if (exists("gen_ed_1_communication")) {
      desrs <- desrs %>%
        mutate(gen_ed_area = dplyr::case_when(
          SUBJ_CRSE %in% gen_ed_1_communication ~ 1L,
          SUBJ_CRSE %in% gen_ed_2_math_stat     ~ 2L,
          SUBJ_CRSE %in% gen_ed_3_phys_nat_sci  ~ 3L,
          SUBJ_CRSE %in% gen_ed_4_soc_behav_sci ~ 4L,
          SUBJ_CRSE %in% gen_ed_5_humanities    ~ 5L,
          SUBJ_CRSE %in% gen_ed_7_arts_design   ~ 7L
        ))
    } else {
      desrs$gen_ed_area <- NA_integer_
      message("  ⚠️  gen_ed_* vectors not found — gen_ed_area will be NA")
    }

    # Department: subject code → dept code via subj_to_dept, with fallback to SUBJ.
    # subj_to_dept handles two cases:
    #   1. AS aggregations: multiple subjects roll up to one dept (GEOG + SUST → GES, etc.)
    #   2. Cross-code gaps: SUBJ ≠ Major Code for the same dept (e.g., CSCI → CS)
    # For all other subjects (mostly non-AS), SUBJ IS the dept code — the coalesce fallback
    # handles these automatically without requiring manual map entries.
    if (exists("subj_to_dept") && length(subj_to_dept) > 0) {
      desrs <- desrs %>% mutate(DEPT = dplyr::coalesce(subj_to_dept[SUBJ], SUBJ))
      # Only warn about AS subjects not in the map — non-AS fallback to SUBJ is expected.
      unmapped_as_subj <- desrs %>%
        filter(COLLEGE == "AS", DEPT == SUBJ, !SUBJ %in% names(subj_to_dept)) %>%
        distinct(SUBJ) %>%
        pull(SUBJ)
      if (length(unmapped_as_subj) > 0)
        message("  ⚠️  AS subject codes not in subj_to_dept (using SUBJ as dept): ",
                paste(unmapped_as_subj, collapse = ", "),
                "\n      Add to subj_to_dept in R/lists/mappings.R if dept aggregation is needed")
    } else {
      desrs <- desrs %>% mutate(DEPT = SUBJ)
      message("  ⚠️  subj_to_dept not found — using SUBJ as DEPT for all rows")
    }

    # ── HR merge (isolated step for job_cat / title enrichment) ──────────────
    # Used downstream for SFR calculations and load reporting.
    # Joins on TERM + PRIM_INST_ID; brings in job_cat, Academic Title, etc.
    hr_file_desrs <- file.path(data_dir, paste0("hr_data", ext))
    if (file.exists(hr_file_desrs)) {
      message("  Pre-processing: merging HR data for job_cat/title fields...")
      hr_desrs <- if (ext == ".qs") qs::qread(hr_file_desrs) else readRDS(hr_file_desrs)
      hr_desrs  <- hr_desrs %>% dplyr::select(-dplyr::any_of("as_of_date"))
      desrs$PRIM_INST_ID <- as.character(desrs$PRIM_INST_ID)
      desrs$TERM         <- as.character(desrs$TERM)
      desrs <- desrs %>%
        dplyr::left_join(hr_desrs,
                         by     = c("TERM" = "term_code", "PRIM_INST_ID" = "UNM ID"),
                         suffix = c("", ".hr")) %>%
        dplyr::select(-dplyr::any_of("DEPT.hr"))
      rm(hr_desrs)
      gc(verbose = FALSE)
      message("  ✅ HR merge complete: ", nrow(desrs), " rows")
    } else {
      desrs$job_cat <- NA_character_
      message("  ⚠️  hr_data not found: ", hr_file_desrs, " — job_cat will be NA")
    }
    # ─────────────────────────────────────────────────────────────────────────

    message("  Transforming to CEDAR model...")

    cedar_sections <- desrs %>%
      transmute(
        # Core identifiers
        section_id = paste0(TERM, "-", CRN),
        term = as.integer(TERM),
        crn = as.character(CRN),

        # Course info
        subject = SUBJ,
        course_number = CRSE,
        subject_course = SUBJ_CRSE,  # Created in pre-processing above
        section = SECT,
        course_title = SECT_TITLE,
        part_term = if ("PT" %in% names(.)) PT else NA_character_,  # Part of term (e.g., "1H", "2H", "FT")

        # Organizational
        campus = CAMP,
        college = COLLEGE,
        department = DEPT,

        # Instructor
        instructor_id = as.character(PRIM_INST_ID),
        instructor_name = INST_NAME,  # Created in pre-processing above
        job_cat = if ("job_cat" %in% names(.)) job_cat else NA_character_,  # From HR merge above

        # Enrollment
        enrolled = as.integer(ENROLLED),  # Section-level enrollment
        total_enrl = as.integer(total_enrl),  # max(enrolled, crosslist total) from pre-processing
        capacity = if ("SECT_CAP" %in% names(.)) as.integer(SECT_CAP) else as.integer(ROOM_CAP),  # Use SECT_CAP if available, else ROOM_CAP
        available = as.integer(SEATS_AVAIL),  # Use direct SEATS_AVAIL from source data

        # Crosslist information
        crosslist_code = if ("XL_CODE" %in% names(.)) as.character(XL_CODE) else "0",
        crosslist_subject = if ("XL_SUBJ" %in% names(.)) as.character(XL_SUBJ) else "",

        # Status
        status = STATUS,

        # Methods & characteristics (derived in pre-processing above)
        delivery_method = INST_METHOD,
        level = level,
        term_type = term_type,
        gen_ed_area = gen_ed_area,
        is_lab = lab,

        # Optional fields if they exist
        waitlist_count = if ("WAIT_COUNT" %in% names(.)) as.integer(coalesce(WAIT_COUNT, 0)) else NA_integer_,
        waitlist_capacity = if ("WAIT_CAPACITY" %in% names(.)) as.integer(coalesce(WAIT_CAPACITY, 0)) else NA_integer_,
        start_date = if ("START_DATE" %in% names(.)) as.Date(START_DATE, format = "%m/%d/%Y") else NA_Date_,
        end_date = if ("END_DATE" %in% names(.)) as.Date(END_DATE, format = "%m/%d/%Y") else NA_Date_,
        credits_min = if ("MIN_CR" %in% names(.)) as.numeric(MIN_CR) else NA_real_,
        credits_max = if ("MAX_CR" %in% names(.)) as.numeric(MAX_CR) else NA_real_,

        # Metadata
        as_of_date = as.Date(as_of_date),

        # Temporary: preserve SHORT_TEXT for home-section detection below (dropped after post-processing)
        xl_home_text = if ("SHORT_TEXT" %in% names(.)) as.character(SHORT_TEXT) else NA_character_
      )

    # ── Post-processing: crosslist enrichment and split-level detection ─────────
    message("  Enriching crosslist fields and detecting split-level courses...")

    # crosslist_group: NA for non-crosslisted sections (blank/NA/0 XL code), group code otherwise
    cedar_sections <- cedar_sections %>%
      mutate(crosslist_group = ifelse(
        is.na(crosslist_code) | crosslist_code == "" | crosslist_code == "0",
        NA_character_,
        crosslist_code
      ))

    # crosslist_primary: marks the "home" section for each crosslist group.
    # Non-crosslisted sections are always primary (TRUE).
    #
    # For crosslisted groups, home is determined by:
    #   1. SHORT_TEXT field (pattern "[SUBJECT] home [TERM]"): the section whose subject
    #      matches the extracted home subject is the primary. This is the most reliable
    #      signal — it reflects which department administratively owns the crosslist.
    #   2. Fallback (no SHORT_TEXT, or no section matches the home subject):
    #      section with highest section-level enrollment; ties broken alphabetically by subject.
    #
    # Consumed by .xlist_filter("home") in R/branches/filter.R.

    # Extract home subject from SHORT_TEXT ("HIST home 202580" or "HIST Home 202580" → "HIST")
    # Case-insensitive: MyReports produces both "home" and "Home"
    cedar_sections <- cedar_sections %>%
      mutate(
        .xl_home_subj = ifelse(
          !is.na(xl_home_text) & grepl("^[A-Z]+ home ", xl_home_text, ignore.case = TRUE),
          sub("^([A-Z]+) home .*", "\\1", xl_home_text, ignore.case = TRUE),
          NA_character_
        )
      )

    # Primary via SHORT_TEXT: section whose subject matches the home subject
    xl_primary_by_text <- cedar_sections %>%
      filter(!is.na(crosslist_group), !is.na(.xl_home_subj), subject == .xl_home_subj) %>%
      group_by(term, crosslist_group) %>%
      slice_head(n = 1) %>%   # guard against malformed data with multiple home-subject rows
      ungroup() %>%
      pull(section_id)

    # Groups where SHORT_TEXT didn't resolve a primary: fall back to enrollment
    xl_groups_needing_fallback <- cedar_sections %>%
      filter(!is.na(crosslist_group)) %>%
      group_by(term, crosslist_group) %>%
      summarize(has_text_primary = any(section_id %in% xl_primary_by_text), .groups = "drop") %>%
      filter(!has_text_primary) %>%
      select(term, crosslist_group)

    xl_primary_by_enrl <- cedar_sections %>%
      semi_join(xl_groups_needing_fallback, by = c("term", "crosslist_group")) %>%
      group_by(term, crosslist_group) %>%
      arrange(desc(enrolled), subject, .by_group = TRUE) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      pull(section_id)

    cedar_sections <- cedar_sections %>%
      mutate(
        crosslist_primary = is.na(crosslist_group) |
          section_id %in% xl_primary_by_text |
          section_id %in% xl_primary_by_enrl
      ) %>%
      mutate(
        crosslist_role = case_when(
          is.na(crosslist_group) ~ NA_character_,
          crosslist_primary      ~ "home",
          TRUE                   ~ "partner"
        )
      ) %>%
      select(-.xl_home_subj, -xl_home_text)

    # is_split: boolean flag for crosslist groups that span the undergrad/grad boundary.
    # A group is split if it contains at least one section with level %in% c("lower","upper")
    # AND at least one section with level == "grad".
    # Unlike the old approach (overwriting level to "split"), this preserves the original
    # level (upper/grad) so sections retain their academic level identity.
    split_groups <- cedar_sections %>%
      filter(!is.na(crosslist_group)) %>%
      distinct(term, crosslist_group, section_id, level) %>%
      group_by(term, crosslist_group) %>%
      summarize(
        .is_split = any(level %in% c("lower", "upper")) & any(level == "grad"),
        .groups = "drop"
      ) %>%
      filter(.is_split) %>%
      select(term, crosslist_group)

    cedar_sections <- cedar_sections %>%
      left_join(split_groups %>% mutate(.is_split = TRUE),
                by = c("term", "crosslist_group")) %>%
      mutate(is_split = coalesce(.is_split, FALSE)) %>%
      select(-.is_split)

    # split_sections: display string showing all courses in a split-level group
    # (e.g., "BIOL 402 / BIOL 502"). Only populated for split-level sections.
    split_labels <- cedar_sections %>%
      filter(is_split) %>%
      distinct(term, crosslist_group, subject_course) %>%
      group_by(term, crosslist_group) %>%
      summarize(split_sections = paste(sort(subject_course), collapse = " / "), .groups = "drop")

    cedar_sections <- cedar_sections %>%
      left_join(split_labels, by = c("term", "crosslist_group")) %>%
      mutate(split_sections = coalesce(split_sections, NA_character_))

    # Sanitize course_title: Banner exports occasionally contain invalid UTF-8
    # bytes (e.g., curly quotes, degree symbols stored in latin-1). Coerce to
    # valid UTF-8, replacing bad bytes with "?", before any string operations.
    cedar_sections <- cedar_sections %>%
      mutate(course_title = iconv(course_title, from = "UTF-8", to = "UTF-8", sub = "?"))

    # is_topics: TRUE if course_title begins with "T:" — Banner convention for
    # rotating-topics slots (e.g. "T: Black Sports History", "T: Topics in AI").
    # Used downstream to distinguish new topics offerings from title-drift on
    # permanent courses when computing "new this term" course lists.
    cedar_sections <- cedar_sections %>%
      mutate(is_topics = grepl("^T:", trimws(course_title)))

    # ── Deduplicate partner-expansion rows ────────────────────────────────────────
    # DESR source data has one row per crosslist partner (e.g., an 11-way crosslist
    # produces 10 duplicate rows per section, differing only in crosslist_subject).
    # Collapse to one row per section now that crosslist enrichment is complete.
    n_before_dedup <- nrow(cedar_sections)
    cedar_sections <- cedar_sections %>%
      distinct(section_id, .keep_all = TRUE)

    # crosslist_external: TRUE if the crosslist group involves sections from multiple departments.
    # Used to distinguish "internal" crosslists (e.g., 400/500 split within same dept)
    # from "external" crosslists that span departments (e.g., HIST 300 / ANTH 300).
    xlist_dept_scope <- cedar_sections %>%
      filter(!is.na(crosslist_group)) %>%
      group_by(term, crosslist_group) %>%
      summarize(crosslist_external = n_distinct(department) > 1, .groups = "drop")
    cedar_sections <- cedar_sections %>%
      left_join(xlist_dept_scope, by = c("term", "crosslist_group"))

    # crosslist_partners: all subject_course values in the same external crosslist group,
    # sorted and collapsed (e.g., "AMST 480 / HIST 480 / WGSS 480").
    # Only populated for external (cross-department) crosslists; NA for split-level and non-XL.
    xl_partner_labels <- cedar_sections %>%
      filter(!is.na(crosslist_group), coalesce(crosslist_external, FALSE)) %>%
      distinct(term, crosslist_group, subject_course) %>%
      group_by(term, crosslist_group) %>%
      summarize(crosslist_partners = paste(sort(subject_course), collapse = " / "), .groups = "drop")
    cedar_sections <- cedar_sections %>%
      left_join(xl_partner_labels, by = c("term", "crosslist_group")) %>%
      mutate(crosslist_partners = coalesce(crosslist_partners, NA_character_))

    message("  ✅ Crosslist groups detected: ",
            n_distinct(na.omit(cedar_sections$crosslist_group)), " groups")
    message("  ✅   Primaries resolved via SHORT_TEXT: ", length(xl_primary_by_text))
    message("  ✅   Primaries resolved via enrollment fallback: ", length(xl_primary_by_enrl))
    message("  ✅ Split-level groups: ", nrow(split_groups))
    message("  ✅ Split-level sections: ",
            sum(cedar_sections$is_split, na.rm = TRUE))
    message("  ✅ Crosslist primary sections: ",
            sum(cedar_sections$crosslist_primary, na.rm = TRUE))
    message("  ✅ Deduplicated: ", n_before_dedup, " → ", nrow(cedar_sections),
            " rows (", n_before_dedup - nrow(cedar_sections), " partner-expansion duplicates removed)")

    message("  ✅ Created cedar_sections: ", nrow(cedar_sections), " rows, ", ncol(cedar_sections), " columns")
    message("  Output columns: ", paste(names(cedar_sections), collapse=", "))
    message("  Size reduction: ", ncol(desrs), " → ", ncol(cedar_sections), " columns (",
            round(100 * (1 - ncol(cedar_sections)/ncol(desrs))), "% reduction)")

    # Save immediately but keep in memory for lookups generation
    saved_files$sections <- save_cedar_file(cedar_sections, "sections", data_dir, ext)
    cedar_data$sections <- cedar_sections  # Keep for lookups (freed after lookups)
    rm(desrs)
    gc(verbose = FALSE)

  } else {
    message("  ⚠️  DESRs file not found: ", desr_file)
    message("  Skipping cedar_sections transformation")
  }

  # ========================================
  # 2. Transform class_lists → cedar_students
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("2. Transforming class_lists → cedar_students")
  message("──────────────────────────────────────────────────────")

  cl_file <- file.path(data_dir, paste0("class_lists", ext))

  if (!"students" %in% run_tables) {
    message("  ⏭  Skipping cedar_students (not in --tables)")
  } else if (file.exists(cl_file)) {
    message("Loading: ", cl_file)

    if (ext == ".qs") {
      class_lists <- qs::qread(cl_file)
    } else {
      class_lists <- readRDS(cl_file)
    }

    message("  Loaded ", nrow(class_lists), " rows, ", ncol(class_lists), " columns")
    message("  Input columns: ", paste(names(class_lists), collapse=", "))

    # ── Pre-processing: derive helper columns from raw class_list data ────────
    # parse-class-list.R is now a pure aggregator (PII removal + dedup only).
    message("  Pre-processing: deriving helper columns...")

    # SUBJ_CRSE (used for subject_course and subject_code in transmute below)
    if ("Subject Code" %in% names(class_lists) && "Course Number" %in% names(class_lists)) {
      class_lists <- class_lists %>%
        unite(SUBJ_CRSE, c("Subject Code", "Course Number"), sep = " ", remove = FALSE)
    }

    # Term type (from last two digits of Academic Period Code)
    if ("Academic Period Code" %in% names(class_lists)) {
      class_lists <- class_lists %>%
        mutate(term_type = dplyr::case_when(
          substr(as.character(`Academic Period Code`), 5, 6) == "80" ~ "fall",
          substr(as.character(`Academic Period Code`), 5, 6) == "10" ~ "spring",
          substr(as.character(`Academic Period Code`), 5, 6) == "60" ~ "summer",
          TRUE ~ NA_character_
        ))
    }

    # Department: subject code → dept code (falls back to subject code)
    if ("Subject Code" %in% names(class_lists)) {
      if (exists("subj_to_dept") && length(subj_to_dept) > 0) {
        class_lists <- class_lists %>%
          mutate(DEPT = dplyr::coalesce(subj_to_dept[`Subject Code`], `Subject Code`))
      } else {
        class_lists$DEPT <- class_lists$`Subject Code`
      }
    }
    # ─────────────────────────────────────────────────────────────────────────

    # Capture Major Code → Major name mapping NOW, before cedar_students is
    # created. Doing it afterward means both class_lists (74 cols × 1.9M rows)
    # and cedar_students (31 cols × 1.9M rows) are in memory simultaneously,
    # which can cause a silent OOM kill. Capturing here avoids that.
    if ("Major Code" %in% names(class_lists) && "Major" %in% names(class_lists)) {
      major_code_name_raw <- class_lists %>%
        dplyr::filter(!is.na(`Major Code`), `Major Code` != "",
                      !is.na(`Major`),      `Major`      != "") %>%
        dplyr::arrange(dplyr::desc(as_of_date)) %>%
        dplyr::distinct(`Major Code`, .keep_all = TRUE) %>%
        dplyr::select(`Major Code`, `Major`)
      message("  Captured ", nrow(major_code_name_raw),
              " major code → name pairs for cedar_lookups")
    } else {
      stop("[transform-to-cedar.R:cedar_lookups] 'Major Code' and/or 'Major' columns are absent ",
           "from the class lists export. These columns are required to build cedar_lookups. ",
           "Check the Banner academic_studies export format.")
    }

    # Drop columns not used in the transmute below.
    # class_lists has 74 columns but the transmute only needs ~25.
    # Slimming it down here halves peak memory before the expensive operation.
    class_lists <- class_lists %>%
      dplyr::select(dplyr::any_of(c(
        "Academic Period Code", "Course Reference Number", "Student ID",
        "SUBJ_CRSE", "Short Course Title",
        "Primary Instructor ID", "Primary Instructor Last Name", "Primary Instructor First Name",
        "Course Campus Code", "Course College Code", "DEPT",
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

    cedar_students <- class_lists %>%
      transmute(
        # Identifiers
        enrollment_id = row_number(),
        section_id = paste0(`Academic Period Code`, "-", `Course Reference Number`),
        crn = as.character(`Course Reference Number`),  # For backward compatibility with gradebook.R
        student_id = encrypt_if_needed(`Student ID`),
        term = as.integer(`Academic Period Code`),

        # Course info (denormalized for performance)
        subject_course = SUBJ_CRSE,  # Created in pre-processing above
        subject_code = sub(" .*", "", SUBJ_CRSE),  # Extract subject (e.g., "HIST 101" → "HIST")
        course_title = if ("Short Course Title" %in% names(.)) `Short Course Title` else NA_character_,
        level = case_when(
          grepl("^[A-Z]+ [0-2][0-9]{2}", SUBJ_CRSE) ~ "lower",  # 000-299
          grepl("^[A-Z]+ [3-4][0-9]{2}", SUBJ_CRSE) ~ "upper",  # 300-499
          grepl("^[A-Z]+ [5-9][0-9]{2}", SUBJ_CRSE) ~ "grad",   # 500+
          TRUE ~ "unknown"
        ),
        instructor_id = if ("Primary Instructor ID" %in% names(.)) {
          `Primary Instructor ID`
        } else NA_character_,
        instructor_last_name = if ("Primary Instructor Last Name" %in% names(.)) {
          `Primary Instructor Last Name`
        } else NA_character_,
        instructor_first_name = if ("Primary Instructor First Name" %in% names(.)) {
          `Primary Instructor First Name`
        } else NA_character_,
        instructor_name = case_when(
          !is.na(instructor_last_name) & !is.na(instructor_first_name) ~ paste0(instructor_last_name, ", ", instructor_first_name),
          !is.na(instructor_last_name) ~ instructor_last_name,
          TRUE ~ NA_character_
        ),
        campus = `Course Campus Code`,
        college = `Course College Code`,
        department = if ("DEPT" %in% names(.)) DEPT else Department,

        # Registration status
        registration_status = `Registration Status`,
        registration_status_code = `Registration Status Code`,
        registration_date = if ("Registration Status Date" %in% names(.)) {
          as.Date(`Registration Status Date`, format = "%m/%d/%Y")
        } else NA_Date_,

        # Academic performance
        final_grade = `Final Grade`,
        credits = if ("Course Credits" %in% names(.)) as.numeric(`Course Credits`) else NA_real_,
        total_credits = if ("Total Credits" %in% names(.)) as.numeric(`Total Credits`) else NA_real_,

        # Student demographics
        student_level = `Student Level Code`,
        student_classification = `Student Classification`,
        # major: Banner MAJOR CODE (e.g., HIST, FNAP, NURS) — join key across tables.
        # major_name: Banner display name (e.g., "History", "Pre-Nursing", "Nursing") —
        #   carried forward directly from the "Major" column in class list exports.
        #   This eliminates the need for the major_code_to_name lookup downstream.
        #   Names are sourced from Banner and agree 100% with major_code_to_name.
        # NOTE: cedar_degrees$major (below) holds the major NAME, not the code —
        #   and cedar_degrees$major_code is the join key there. In cedar_students,
        #   major_code is the code and major_name is the display name — consistent naming.
        major_code = if ("Major Code" %in% names(.)) `Major Code` else NA_character_,
        major_name = if ("Major"      %in% names(.)) `Major`      else NA_character_,
        student_college = `Student College Code`,
        student_campus = `Student Campus Code`,

        # Characteristics
        term_type = if ("term_type" %in% names(.)) term_type else NA_character_,  # Created in pre-processing above
        residency = if ("Residency" %in% names(.)) Residency else NA_character_,
        dual_credit = if ("Dual Credit" %in% names(.)) (`Dual Credit` == "Y") else NA,
        part_term = if ("Sub-Academic Period Code" %in% names(.)) `Sub-Academic Period Code` else NA_character_,  # Part of term from class_lists

        # Metadata
        as_of_date = as.Date(as_of_date)
      )

    # Deduplicate: Banner exports one row per section CRN, so students in
    # combined courses (e.g., BIOL 302C = lecture CRN + lab CRN) appear twice
    # with identical credit values. Keep one row per student-course per term.
    n_before_dedup <- nrow(cedar_students)
    cedar_students <- cedar_students %>%
      distinct(student_id, term, subject_course, .keep_all = TRUE)
    n_removed <- n_before_dedup - nrow(cedar_students)
    if (n_removed > 0)
      message("  Removed ", n_removed, " duplicate section rows (combined lecture+lab courses)")

    message("  ✅ Created cedar_students: ", nrow(cedar_students), " rows, ", ncol(cedar_students), " columns")
    message("  Output columns: ", paste(names(cedar_students), collapse=", "))
    message("  Size reduction: ", ncol(class_lists), " → ", ncol(cedar_students), " columns (",
            round(100 * (1 - ncol(cedar_students)/ncol(class_lists))), "% reduction)")

    # Save immediately and free memory
    saved_files$students <- save_cedar_file(cedar_students, "students", data_dir, ext)
    rm(class_lists, cedar_students)
    gc(verbose = FALSE)

  } else {
    message("  ⚠️  class_lists file not found: ", cl_file)
    message("  Skipping cedar_students transformation")
  }

  # ========================================
  # 3. Transform academic_studies → cedar_programs
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("3. Transforming academic_studies → cedar_programs")
  message("──────────────────────────────────────────────────────")

  as_file <- file.path(data_dir, paste0("academic_studies", ext))

  if (!"programs" %in% run_tables) {
    message("  ⏭  Skipping cedar_programs (not in --tables)")
  } else if (file.exists(as_file)) {
    message("Loading: ", as_file)

    if (ext == ".qs") {
      academic_studies <- qs::qread(as_file)
    } else {
      academic_studies <- readRDS(as_file)
    }

    message("  Loaded ", nrow(academic_studies), " rows, ", ncol(academic_studies), " columns")
    message("  Input columns: ", paste(names(academic_studies), collapse=", "))

    # ── Pre-processing: derive helper columns from raw academic_studies data ──
    # parse-academic-study.R is now a pure aggregator (noise removal + PII + dedup).
    message("  Pre-processing: deriving helper columns...")

    # term: derive from "Academic Period" text label using academic_period_to_term() (utils.R).
    # Always re-derive when "Academic Period" is present — older parsed files may carry a
    # stale or all-NA term_code column from a previous parse-academic-studies version,
    # and the column-existence guard would silently skip derivation and leave term as NA.
    # The standard CEDAR column is `term` (integer); term_code is dropped after this step.
    if ("Academic Period" %in% names(academic_studies)) {
      academic_studies <- academic_studies %>%
        dplyr::mutate(term_code = as.character(
          academic_period_to_term(`Academic Period`)
        ))
      n_ok  <- sum(!is.na(academic_studies$term_code))
      n_bad <- sum(is.na(academic_studies$term_code))
      message("  ✅ term_code derived from 'Academic Period': ", n_ok, " rows OK",
              if (n_bad > 0) paste0(", ", n_bad, " NA (unrecognised labels)") else "")
    } else if ("term_code" %in% names(academic_studies) &&
               any(!is.na(academic_studies$term_code))) {
      message("  term_code column present and non-empty — using as-is")
    } else {
      stop("  Cannot derive term: 'Academic Period' column missing and no usable term_code column")
    }

    # Pre-major flag and Major field cleanup ("Pre History" → "History")
    if ("Major" %in% names(academic_studies)) {
      academic_studies <- academic_studies %>%
        mutate(
          pre   = grepl("Pre", Major),
          Major = stringr::str_remove(Major, "^Pre-?\\s*")
        )
      message("  ✅ Pre-major flag set; 'Pre'/'Pre-' prefix removed from Major")
    }
    # ─────────────────────────────────────────────────────────────────────────

    message("  Transforming to CEDAR model (pivot_longer wide → long)...")

    # Program name columns and their corresponding code columns (paired)
    prog_pairs <- list(
      list(type = "Major",               name_col = "Major",               code_col = "Major Code"),
      list(type = "Second Major",        name_col = "Second Major",        code_col = "Second Major Code"),
      list(type = "First Minor",         name_col = "First Minor",         code_col = "First Minor Code"),
      list(type = "Second Minor",        name_col = "Second Minor",        code_col = "Second Minor Code"),
      list(type = "First Concentration", name_col = "First Concentration", code_col = NULL),
      list(type = "Second Concentration",name_col = "Second Concentration",code_col = NULL),
      list(type = "Third Concentration", name_col = "Third Concentration", code_col = NULL)
    )

    # Base columns shared across all program type rows
    base_cols <- c("program_id_key", "student_id", "term", "program_classification",
                   "degree", "student_classification", "student_level",
                   "student_campus", "student_college", "college_code",
                   "student_population", "inst_credits_attempted", "overall_credits_earned",
                   "residency", "academic_standing", "inst_gpa", "as_of_date")

    academic_studies_base <- academic_studies %>%
      transmute(
        program_id_key        = paste0(term_code, "-", ID),
        student_id            = encrypt_if_needed(ID),
        term                  = as.integer(term_code),
        program_classification = `Program Classification`,
        degree                = Degree,
        student_classification = `Student Classification`,
        student_level         = `Student Level`,
        student_campus        = `Student Campus`,
        student_college       = `Translated College`,
        # college_code: Banner 2-letter code (matches COLLEGE in cedar_sections/DESRs).
        # Derived from "Actual College" via college_name_to_code map in mappings.R.
        # Enables college-level filtering without HR data.
        college_code          = {
          if (!exists("college_name_to_code"))
            stop("[transform-to-cedar.R:cedar_students] 'college_name_to_code' lookup is not loaded. ",
                 "Ensure mappings.R has been sourced before running transform-to-cedar.R.")
          college_name_to_code[`Actual College`]
        },
        student_population    = if ("Student Population" %in% names(.))
                                  `Student Population`
                                else NA_character_,
        inst_credits_attempted = if ("Institution Credits Attempted" %in% names(.))
                                   as.numeric(`Institution Credits Attempted`)
                                 else NA_real_,
        overall_credits_earned = if ("Overall Credits Earned" %in% names(.))
                                    as.numeric(`Overall Credits Earned`)
                                  else NA_real_,
        # Demographic indicators — stored per-term; cohort building resolves to "ever"
        pell_eligible = if ("Pell Eligible Indicator" %in% names(.))
                          dplyr::if_else(`Pell Eligible Indicator` == "Y", TRUE, FALSE, missing = NA)
                        else NA,
        first_gen     = if ("First Generation Indicator" %in% names(.))
                          dplyr::if_else(`First Generation Indicator` == "Yes", TRUE, FALSE, missing = NA)
                        else NA,
        ipeds_race    = if ("IPEDS Race" %in% names(.)) `IPEDS Race` else NA_character_,
        gender        = if ("Gender" %in% names(.)) Gender else NA_character_,
        time_status   = if ("Current Time Status Code" %in% names(.))
                          `Current Time Status Code`
                        else NA_character_,
        residency         = if ("Residency" %in% names(.))
                              `Residency`
                            else NA_character_,
        academic_standing = if ("Academic Standing" %in% names(.))
                              `Academic Standing`
                            else NA_character_,
        inst_gpa          = if ("Institution GPA" %in% names(.))
                              as.numeric(`Institution GPA`)
                            else NA_real_,
        as_of_date            = as.Date(as_of_date),
        # Carry raw code columns for pairing below
        dplyr::across(dplyr::any_of(c("Major Code", "Second Major Code",
                                      "First Minor Code", "Second Minor Code")))
      )

    cedar_programs <- purrr::map(prog_pairs, function(p) {
      name_col <- p$name_col
      if (!name_col %in% names(academic_studies)) return(NULL)
      df <- academic_studies_base
      df$program_name <- academic_studies[[name_col]]
      df$major_code <- if (!is.null(p$code_col) && p$code_col %in% names(academic_studies))
        academic_studies[[p$code_col]] else NA_character_
      df %>%
        filter(!is.na(program_name), program_name != "") %>%
        transmute(
          program_id   = paste0(program_id_key, "-", p$type),
          student_id, term,
          program_type = p$type,
          program_name,
          major_code = as.character(major_code),
          program_classification, degree,
          student_classification, student_level, student_campus, student_college, college_code,
          student_population, inst_credits_attempted, overall_credits_earned,
          pell_eligible, first_gen, ipeds_race, gender, time_status,
          residency, academic_standing, inst_gpa,
          as_of_date
        )
    }) %>%
      purrr::compact() %>%
      dplyr::bind_rows() %>%
      dplyr::mutate(
        # Dept code lookup — three-tier priority:
        #   1. major_college_to_dept["major_code:college_code"] — compound key from major_dept_map;
        #      correctly disambiguates same major_code in multiple colleges
        #      (e.g., CRIM → SOCI for AS, CJUS for AD; EDUC → EDUC for EH, EDUC for AD).
        #   2. subj_to_dept[major_code] — subject_code fallback from unit_catalog;
        #      handles language/subject codes used as major codes (ARBC→LCL, FREN→LCL, etc.).
        #   3. major_code — last resort identity mapping.
        dept_code = dplyr::coalesce(
          major_college_to_dept[paste(major_code, college_code, sep = ":")],
          subj_to_dept[major_code],
          major_code
        ),
        # Nullify numeric dept_codes — these are Banner internal org IDs (e.g., "1051",
        # "059") that leaked into major_code in source data. The identity fallback
        # would produce a numeric dept_code, which is never a valid org unit code.
        dept_code = dplyr::if_else(grepl("^[0-9]+$", dept_code), NA_character_, dept_code),
        # Detect pre-major via two complementary signals:
        #   1. "Pre " or "Pre-" prefix in program_name — catches most CAS pre-majors
        #      when Banner stores them as "Pre-History", "Pre-Spanish", etc.
        #      "Premedical Studies" does NOT match (requires space or hyphen after "Pre").
        #   2. F-prefix in major_code — catches pre-majors that Banner stores without
        #      a "Pre-" name prefix (e.g. FNAP = pre-Nursing, stored as "Nursing").
        #      Banner's F-prefix convention is consistent: F + abbreviated subject code.
        #      Excluded: known non-pre-major F codes that are real programs in their own right.
        is_pre_major = grepl("^Pre[- ]", program_name, ignore.case = TRUE) |
          (grepl("^F[A-Z]", major_code) & !major_code %in% c(
            "FA",   # Fine Arts (real major)
            "FLA",  # Flamenco (real major)
            "FILM", # Film (real major)
            "FDMA", # Film and Digital Arts (real major)
            "FFDA", # FDMA variant (Fine Arts)
            "FFDM", # IFDM (Fine Arts)
            "FMAR", # Media Arts (Fine Arts)
            "FIDA", # Interdisciplinary Arts (Fine Arts)
            "FLHC", # Film Hist & Critic
            "FLPR", # Film Production
            "FLAI", # Liberal Arts & Integrative Studies
            "FS",   # Family Studies (single-letter variant)
            "FES",  # Exercise Science (not a pre-major)
            "FPE",  # Physical Education (not a pre-major)
            "FAT",  # Athletic Training (not a pre-major)
            "FNE"   # Nuclear Engineering (not a pre-major)
          )) |
          # PHRD (Doctor of Pharmacy) is used for both actual PharmD students
          # (student_level = "PH") and undergraduate pre-pharmacy students
          # (student_level = "UG") who are completing prerequisites before
          # admission. UNM switched to FPHS for pre-pharmacy in 202580, but
          # prior to that all pre-pharmacy students were coded as PHRD.
          # UG-level PHRD rows are functionally pre-major.
          (major_code == "PHRD" & student_level %in% c("UG", "NG")),
        # Strip "Pre-" prefix from program_name so "Pre-History" and "History" share
        # one clean name. F-prefix pre-majors (FNAP → "Nursing") are already clean.
        program_name = dplyr::if_else(
          grepl("^Pre[- ]", program_name, ignore.case = TRUE),
          stringr::str_trim(sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)),
          program_name
        )
      )

    # Warn about Major rows with NA dept_code (indicates unmapped major_code in source data)
    na_dept_prgm <- cedar_programs %>%
      filter(is.na(dept_code), program_type == "Major") %>%
      distinct(major_code) %>% pull(major_code)
    if (length(na_dept_prgm) > 0)
      message("  ⚠️  Major rows with NA dept_code (NA or numeric major_code in source data): ",
              format(length(na_dept_prgm), big.mark = ","), " distinct values: ",
              paste(na_dept_prgm[1:min(5, length(na_dept_prgm))], collapse = ", "))

    message("  ✅ Created cedar_programs: ", nrow(cedar_programs), " rows, ", ncol(cedar_programs), " columns")
    message("  Output columns: ", paste(names(cedar_programs), collapse=", "))
    message("  Program type breakdown:")
    for (pt in unique(cedar_programs$program_type)) {
      message("     ", pt, ": ", sum(cedar_programs$program_type == pt))
    }
    message("  Size reduction: ", ncol(academic_studies), " → ", ncol(cedar_programs), " columns (",
            round(100 * (1 - ncol(cedar_programs)/ncol(academic_studies))), "% reduction)")

    # Save immediately but keep in memory for lookups generation
    saved_files$programs <- save_cedar_file(cedar_programs, "programs", data_dir, ext)
    cedar_data$programs <- cedar_programs  # Keep for lookups (freed after lookups)
    rm(academic_studies)
    gc(verbose = FALSE)

  } else {
    message("  ⚠️  academic_studies file not found: ", as_file)
    message("  Skipping cedar_programs transformation")
  }

  # ========================================
  # 4. Transform degrees → cedar_degrees
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("4. Transforming degrees → cedar_degrees")
  message("──────────────────────────────────────────────────────")

  deg_file <- file.path(data_dir, paste0("degrees", ext))

  if (!"degrees" %in% run_tables) {
    message("  ⏭  Skipping cedar_degrees (not in --tables)")
  } else if (file.exists(deg_file)) {
    message("Loading: ", deg_file)

    if (ext == ".qs") {
      degrees <- qs::qread(deg_file)
    } else {
      degrees <- readRDS(deg_file)
    }

    message("  Loaded ", nrow(degrees), " rows, ", ncol(degrees), " columns")
    message("  Input columns: ", paste(names(degrees), collapse=", "))
    message("  Transforming to CEDAR model...")

    required_deg_cols <- c("Major", "Program Code", "Academic Period Code",
                           "ID", "Degree", "Graduation Status")
    missing_deg_cols <- setdiff(required_deg_cols, names(degrees))
    if (length(missing_deg_cols) > 0)
      stop("[transform-to-cedar.R:cedar_degrees] Required columns missing from degrees export: ",
           paste(missing_deg_cols, collapse = ", "),
           ". Check the Banner degrees export format.")

    cedar_degrees <- degrees %>%
      transmute(
        # Identifiers
        degree_id = paste0(`Academic Period Code`, "-", ID, "-", `Program Code`),
        student_id = encrypt_if_needed(ID),
        term = as.integer(`Academic Period Code`),

        # Student info
        student_college = if ("Actual College" %in% names(.)) `Actual College` else NA_character_,

        # Degree info
        degree = Degree,
        award_category = if ("Award Category" %in% names(.)) `Award Category` else NA_character_,
        # program_code: full Banner compound code ("BA-HIST-AS"); used to derive degree_abbr.
        # major_code: the catalog key ("HIST") — matches major_dept_map$major_code.
        program_code = `Program Code`,
        program_name = Program,
        college = `Translated College`,
        department = Department,
        graduation_status = `Graduation Status`,

        # Major/minor fields
        campus = if ("Campus" %in% names(.)) Campus else NA_character_,
        # NOTE: cedar_degrees$major holds the Banner MAJOR NAME (e.g., "History", "Pre-Nursing"),
        # sourced from the "Major" column of degree completion exports. This is a display name.
        # cedar_degrees$major_code (immediately below) holds the corresponding Banner code.
        # cedar_students uses major_code (code) + major_name (display name) — consistent naming.
        major = if ("Major" %in% names(.)) Major else NA_character_,
        major_code = dplyr::case_when(
          "Major Code" %in% names(.) & !is.na(`Major Code`) & `Major Code` != "" ~ `Major Code`,
          TRUE ~ stringr::str_extract(`Program Code`, "(?<=-)[A-Z0-9]+(?=-[A-Z]{2,3}$)")
        ),
        second_major = if ("Second Major" %in% names(.)) `Second Major` else NA_character_,
        first_minor = if ("First Minor" %in% names(.)) `First Minor` else NA_character_,
        second_minor = if ("Second Minor" %in% names(.)) `Second Minor` else NA_character_,

        # Academic info
        cumulative_gpa = if ("Cumulative GPA" %in% names(.)) as.numeric(`Cumulative GPA`) else NA_real_,
        cumulative_credits = if ("Cumulative Credits Earned" %in% names(.)) {
          as.numeric(`Cumulative Credits Earned`)
        } else NA_real_,
        honors = if ("Honor" %in% names(.)) Honor else NA_character_,
        admitted_term = if ("Academic Period Admitted" %in% names(.)) {
          suppressWarnings(as.integer(`Academic Period Admitted`))
        } else NA_integer_,

        # Metadata
        as_of_date = as.Date(as_of_date)
      ) %>%
      dplyr::mutate(
        # Dept code — same three-tier lookup as cedar_programs.
        # major_code ("HIST") matches major_dept_map keys; college_code disambiguates
        # programs that exist in multiple colleges (e.g., CRIM, EDUC).
        .college_code = {
          if (!exists("college_name_to_code"))
            stop("[transform-to-cedar.R:cedar_degrees] 'college_name_to_code' lookup is not loaded. ",
                 "Ensure mappings.R has been sourced before running transform-to-cedar.R.")
          college_name_to_code[student_college]
        },
        dept_code = dplyr::coalesce(
          major_college_to_dept[paste(major_code, .college_code, sep = ":")],
          subj_to_dept[major_code],
          major_to_dept[major_code]
        ),
        # degree_abbr: first segment of program_code ("BA-HIST-AS" → "BA").
        # Allows filtering to a specific degree when a dept offers both BA and BS, etc.
        degree_abbr = sub("^([A-Za-z]+)-.*$", "\\1", program_code)
      ) %>%
      dplyr::select(-.college_code)

    message("  ✅ Created cedar_degrees: ", nrow(cedar_degrees), " rows, ", ncol(cedar_degrees), " columns")
    message("  Output columns: ", paste(names(cedar_degrees), collapse=", "))
    message("  Size reduction: ", ncol(degrees), " → ", ncol(cedar_degrees), " columns (",
            round(100 * (1 - ncol(cedar_degrees)/ncol(degrees))), "% reduction)")

    # Save immediately and free memory
    saved_files$degrees <- save_cedar_file(cedar_degrees, "degrees", data_dir, ext)
    rm(degrees, cedar_degrees)
    gc(verbose = FALSE)

  } else {
    message("  ⚠️  degrees file not found: ", deg_file)
    message("  Skipping cedar_degrees transformation")
  }

  # ========================================
  # 5. Transform hr_data → cedar_faculty
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("5. Transforming hr_data → cedar_faculty")
  message("──────────────────────────────────────────────────────")

  hr_file <- file.path(data_dir, paste0("hr_data", ext))

  if (!"faculty" %in% run_tables) {
    message("  ⏭  Skipping cedar_faculty (not in --tables)")
  } else if (file.exists(hr_file)) {
    message("Loading: ", hr_file)

    if (ext == ".qs") {
      hr_data <- qs::qread(hr_file)
    } else {
      hr_data <- readRDS(hr_file)
    }

    message("  Loaded ", nrow(hr_data), " rows, ", ncol(hr_data), " columns")
    message("  Input columns: ", paste(names(hr_data), collapse=", "))
    message("  Transforming to CEDAR model...")

    cedar_faculty <- hr_data %>%
      transmute(
        # Identifiers
        instructor_id = as.character(`UNM ID`),
        term = as.integer(term_code),
        instructor_name = Name,
        department = DEPT,

        # Optional fields
        academic_title = if ("Academic Title" %in% names(.)) `Academic Title` else NA_character_,
        job_title = if ("Job Title" %in% names(.)) `Job Title` else NA_character_,
        job_category = if ("job_cat" %in% names(.)) job_cat else NA_character_,
        appointment_pct = if ("Appt %" %in% names(.)) as.numeric(`Appt %`) else NA_real_,
        college = if ("Home Organization Desc" %in% names(.)) `Home Organization Desc` else NA_character_,

        # Metadata
        as_of_date = if ("as_of_date" %in% names(.)) as.Date(as_of_date) else NA_Date_
      )

    message("  ✅ Created cedar_faculty: ", nrow(cedar_faculty), " rows, ", ncol(cedar_faculty), " columns")
    message("  Output columns: ", paste(names(cedar_faculty), collapse=", "))
    message("  Size reduction: ", ncol(hr_data), " → ", ncol(cedar_faculty), " columns (",
            round(100 * (1 - ncol(cedar_faculty)/ncol(hr_data))), "% reduction)")

    # Save immediately and free memory
    saved_files$faculty <- save_cedar_file(cedar_faculty, "faculty", data_dir, ext)
    rm(hr_data, cedar_faculty)
    gc(verbose = FALSE)

  } else {
    message("  ⚠️  hr_data file not found: ", hr_file)
    message("  Skipping cedar_faculty transformation")
  }

  # ========================================
  # 6. Generate cedar_lookups (Auto-generated normalization tables)
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("6. Generating cedar_lookups (normalization tables)")
  message("──────────────────────────────────────────────────────")

  if (!"lookups" %in% run_tables) {
    message("  ⏭  Skipping cedar_lookups (not in --tables)")
  } else {

  # For partial runs (e.g., deg-only), programs/sections may not be in cedar_data.
  # Load them from existing saved files so lookups are complete regardless of which
  # tables were built in this run.
  if (!"programs" %in% names(cedar_data)) {
    prog_file <- file.path(data_dir, paste0("cedar_programs", ext))
    if (file.exists(prog_file)) {
      message("  Loading cedar_programs from disk for lookups...")
      cedar_data$programs <- qs::qread(prog_file)
    }
  }
  if (!"sections" %in% names(cedar_data)) {
    sec_file <- file.path(data_dir, paste0("cedar_sections", ext))
    if (file.exists(sec_file)) {
      message("  Loading cedar_sections from disk for lookups...")
      cedar_data$sections <- qs::qread(sec_file)
    }
  }

  # Handcoded mappings from mappings.R — sourced early in this function (see top of
  # transform_to_cedar). Verify they exist; create empty fallbacks if still missing.
  if (!exists("major_to_program")) {
    message("  ⚠️  major_to_program not found — using empty fallback")
    major_to_program <- c()
  }
  if (!exists("major_college_to_dept")) major_college_to_dept <- setNames(character(0), character(0))
  if (!exists("college_name_to_code")) college_name_to_code <- c()

  # 6a. Program name → dept_code lookup (combines handcoded + data-derived)
  message("  Building program_name → dept_code lookup...")
  if ("programs" %in% names(cedar_data)) {

    # Start with handcoded major_to_program (program_name → dept_code)
    if (length(major_to_program) > 0) {
      handcoded_program_lookup <- tibble(
        program_name = names(major_to_program),
        dept_code = as.character(major_to_program)
      )
      message("    Handcoded mappings: ", nrow(handcoded_program_lookup), " entries")
    } else {
      handcoded_program_lookup <- tibble(program_name = character(), dept_code = character())
    }

    # Build data-derived mappings for programs not in handcoded list
    # Uses dept_code directly (cedar_programs no longer has a 'department' column)
    data_derived_lookup <- cedar_data$programs %>%
      filter(!is.na(program_name) & program_name != "" & !is.na(dept_code) & dept_code != "") %>%
      # For each program_name, get the most common dept_code association
      count(program_name, dept_code, sort = TRUE) %>%
      group_by(program_name) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      # Only keep entries NOT already in handcoded list
      filter(!(program_name %in% handcoded_program_lookup$program_name)) %>%
      select(program_name, dept_code)

    message("    Data-derived mappings: ", nrow(data_derived_lookup), " additional entries")

    # Combine handcoded (priority) with data-derived
    program_name_lookup <- bind_rows(handcoded_program_lookup, data_derived_lookup) %>%
      distinct(program_name, .keep_all = TRUE)

    message("    ✅ program_name_lookup: ", nrow(program_name_lookup), " total entries")
    message("    Sample: ", paste(head(program_name_lookup$program_name, 10), collapse = ", "))

    # 6b. Department string → dept_code mapping
    # Maps the raw department values (like "AS Anthropology") to standard codes
    message("  Building department → dept_code lookup...")

    # Start with handcoded hr_org_desc_to_dept if available
    if (exists("hr_org_desc_to_dept") && length(hr_org_desc_to_dept) > 0) {
      handcoded_dept_lookup <- tibble(
        department = names(hr_org_desc_to_dept),
        dept_code = as.character(hr_org_desc_to_dept)
      )
      message("    Handcoded dept mappings: ", nrow(handcoded_dept_lookup), " entries")
    } else {
      handcoded_dept_lookup <- tibble(department = character(), dept_code = character())
    }

    # Data-derived: unique department strings from programs not already handcoded.
    # These are raw HR org descriptions (e.g., "EN Computer Science") — kept as-is
    # since the dashboard now uses dept_code from cedar_programs$dept_code instead.
    unique_departments <- cedar_data$programs %>%
      filter(!is.na(dept_code) & dept_code != "") %>%
      distinct(dept_code) %>%
      filter(!(dept_code %in% handcoded_dept_lookup$department)) %>%
      transmute(department = dept_code, dept_code)

    message("    Data-derived dept mappings: ", nrow(unique_departments), " additional entries")

    dept_lookup <- bind_rows(handcoded_dept_lookup, unique_departments) %>%
      distinct(department, .keep_all = TRUE)

    # 6c. Dept code → human-readable name
    # Priority order:
    #   1. unit_catalog dept_name (authoritative, from schedule key + overrides)
    #   2. Data-derived from cedar_programs (program_name where major_code == dept_code)
    # The catalog covers all known depts; data-derived catches anything not yet in the catalog.
    n_overrides <- 0L
    if (exists("dept_code_to_name_catalog") && length(dept_code_to_name_catalog) > 0) {
      dept_name_lookup <- tibble(
        dept_code = names(dept_code_to_name_catalog),
        dept_name = as.character(dept_code_to_name_catalog)
      ) %>%
        # Only include dept_codes that actually exist in the data
        filter(dept_code %in% cedar_data$programs$dept_code |
               dept_code %in% cedar_data$sections$department)
      n_overrides <- nrow(dept_name_lookup)
      # Supplement with data-derived names for any dept_codes not in catalog.
      # Exclude numeric dept_codes — they are Banner internal org IDs that leaked
      # into major_code in source data and are not valid organizational units.
      data_derived_names <- cedar_data$programs %>%
        filter(!is.na(major_code), major_code != "",
               !is.na(dept_code), dept_code != "",
               !grepl("^[0-9]+$", dept_code),
               major_code == dept_code,
               !dept_code %in% dept_name_lookup$dept_code) %>%
        distinct(dept_code, program_name) %>%
        group_by(dept_code) %>% slice_head(n = 1) %>% ungroup() %>%
        rename(dept_name = program_name)
      if (nrow(data_derived_names) > 0) {
        dept_name_lookup <- bind_rows(dept_name_lookup, data_derived_names)
        message("    Supplemented with ", nrow(data_derived_names),
                " data-derived names for dept_codes not in unit_catalog")
      }
      # Deduplicate by dept_name: when a data-derived code shares a name with a
      # catalog entry (e.g. legacy F-prefix/X-prefix aliases), keep the catalog
      # entry. Catalog rows come first so slice_head keeps them.
      n_before <- nrow(dept_name_lookup)
      dept_name_lookup <- dept_name_lookup %>%
        group_by(dept_name) %>%
        slice_head(n = 1) %>%
        ungroup()
      n_dropped <- n_before - nrow(dept_name_lookup)
      if (n_dropped > 0)
        message("    Removed ", n_dropped, " dept_name duplicates (legacy alias codes superseded by catalog entries)")
      dept_name_lookup <- arrange(dept_name_lookup, dept_code)
    } else {
      # No catalog — fall back to data-derived only
      dept_name_lookup <- cedar_data$programs %>%
        filter(!is.na(major_code), major_code != "",
               !is.na(dept_code), dept_code != "",
               major_code == dept_code) %>%
        distinct(dept_code, program_name) %>%
        group_by(dept_code) %>% slice_head(n = 1) %>% ungroup() %>%
        rename(dept_name = program_name) %>%
        arrange(dept_code)
    }

    # Warn about any dept_codes active in the data that have no display name.
    # Codes are categorized to distinguish mapping gaps (which need code fixes) from
    # genuinely unknown codes (which need a new unit_catalog.R entry):
    #   F-prefix — Banner pre-major program codes (e.g., FNRS, FBIO) surfacing as
    #              dept_codes; indicates major_to_dept is not resolving them.
    #   X-prefix — extended/cross-listed program codes (e.g., XECO, XELE) surfacing
    #              as dept_codes; same mapping gap as F-prefix.
    #   Other    — genuinely unknown dept codes; add to unit_catalog.R.
    active_dept_codes <- unique(c(
      cedar_data$programs$dept_code,
      cedar_data$sections$department
    ))
    active_dept_codes <- active_dept_codes[!is.na(active_dept_codes) & active_dept_codes != ""]
    unnamed_active <- sort(setdiff(active_dept_codes, dept_name_lookup$dept_code))
    if (length(unnamed_active) > 0) {
      f_codes <- unnamed_active[grepl("^F[A-Z]", unnamed_active)]
      x_codes <- unnamed_active[grepl("^X[A-Z]", unnamed_active)]
      other_codes <- unnamed_active[!grepl("^[FX][A-Z]", unnamed_active)]
      if (length(f_codes) > 0)
        message("    ⚠️  F-prefix codes (pre-major program codes surfacing as dept — mapping gap): ",
                paste(f_codes, collapse = ", "))
      if (length(x_codes) > 0)
        message("    ⚠️  X-prefix codes (extended/cross-listed codes surfacing as dept — mapping gap): ",
                paste(x_codes, collapse = ", "))
      if (length(other_codes) > 0)
        message("    ⚠️  Unknown dept codes (investigate and add to unit_catalog.R if valid): ",
                paste(other_codes, collapse = ", "))
    }

    n_data_only <- nrow(dept_name_lookup) - n_overrides
    message("    ✅ dept_name_lookup: ", nrow(dept_name_lookup), " entries (",
            n_data_only, " data-derived, ", n_overrides, " display overrides)")

    # college_code_to_name: "MG" → "Anderson Schools of Management" (for display)
    # Derived from unit_catalog if available, else inverted from college_name_to_code
    college_code_to_name <- if (exists("unit_catalog")) {
      .clu <- dplyr::distinct(unit_catalog, college_code, college_name)
      setNames(.clu$college_name, .clu$college_code)
    } else if (exists("college_name_to_code") && length(college_name_to_code) > 0) {
      setNames(names(college_name_to_code), college_name_to_code)
    } else {
      character(0)
    }

    cedar_data$lookups <- list(
      program_name_lookup  = program_name_lookup,  # program_name → dept_code
      dept_lookup          = dept_lookup,           # department string → dept_code
      dept_name_lookup     = dept_name_lookup,      # dept_code → human-readable name
      college_code_to_name = college_code_to_name  # "MG" → "Anderson Schools of Management"
    )

  } else {
    message("  ⚠️  cedar_programs not available, skipping program lookup")
  }

  # 6c. Subject code lookup - maps subject codes to departments
  message("  Building subject_code lookup from cedar_students/cedar_sections...")
  if ("sections" %in% names(cedar_data)) {
    # Get subject codes from sections (which have DEPT column from DESRs)
    subject_lookup <- cedar_data$sections %>%
      filter(!is.na(subject) & subject != "" & !is.na(department) & department != "") %>%
      count(subject, department, college, sort = TRUE) %>%
      group_by(subject) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      rename(subject_code = subject, dept_code = department) %>%
      select(subject_code, dept_code, college)

    message("    ✅ subject_lookup: ", nrow(subject_lookup), " unique subject codes")
    message("    Sample: ", paste(head(subject_lookup$subject_code, 15), collapse = ", "))

    # Add to lookups
    if ("lookups" %in% names(cedar_data)) {
      cedar_data$lookups$subject_lookup <- subject_lookup
    } else {
      cedar_data$lookups <- list(subject_lookup = subject_lookup)
    }
  } else {
    message("  ⚠️  cedar_sections not available, skipping subject lookup")
  }

  # 6d. Major code → human-readable name lookup
  # Named character vector: "HIST" → "History", "BIOL" → "Biology", etc.
  # Derived from class_lists (Banner source) in step 2; ~100% coverage.
  # global.R loads this into major_code_to_name at app startup so all
  # downstream code (credit-hours.R, dept-dashboard.R, etc.) benefits automatically.
  message("  Building major_code_to_name lookup...")
  if (exists("major_code_name_raw") && !is.null(major_code_name_raw) && nrow(major_code_name_raw) > 0) {
    major_code_to_name <- setNames(
      major_code_name_raw[["Major"]],
      major_code_name_raw[["Major Code"]]
    )
    if ("lookups" %in% names(cedar_data)) {
      cedar_data$lookups$major_code_to_name <- major_code_to_name
    } else {
      cedar_data$lookups <- list(major_code_to_name = major_code_to_name)
    }
    message("    ✅ major_code_to_name: ", length(major_code_to_name), " entries")
  } else {
    message("    ⚠️  major_code_name_raw not available — skipping major_code_to_name")
  }

  # 6f. Save lookups as a separate file
  if ("lookups" %in% names(cedar_data)) {
    cedar_lookups <- cedar_data$lookups
    saved_files$lookups <- save_cedar_file(cedar_lookups, "lookups", data_dir, ext)
    rm(cedar_lookups)
    gc(verbose = FALSE)

    message("    ✅ Saved cedar_lookups with ", length(cedar_data$lookups),
            " tables (", paste(names(cedar_data$lookups), collapse = ", "), ")")
  }
  } # end lookups else block

  # Now that lookups are done, free sections and programs from memory
  if ("sections" %in% names(cedar_data)) {
    cedar_data$sections <- NULL
  }
  if ("programs" %in% names(cedar_data)) {
    cedar_data$programs <- NULL
  }
  gc(verbose = FALSE)
  message("  ✅ Freed sections and programs from memory")

  # ========================================
  # 7. Summary of saved files
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("7. CEDAR Transformation Complete")
  message("──────────────────────────────────────────────────────")
  message("Saved ", length(saved_files), " CEDAR files:")
  for (name in names(saved_files)) {
    info <- saved_files[[name]]
    message("  ✅ cedar_", name, ": ",
            format(info$rows, big.mark = ","), " rows, ",
            round(info$size_mb, 1), " MB")
  }

  # ========================================
  # Write cedar-status.json for fast CLI queries
  # ========================================
  status_file <- file.path(data_dir, "cedar-status.json")
  tryCatch({
    null_or_str <- function(x) {
      if (is.null(x) || (length(x) == 1 && is.na(x))) "null"
      else paste0('"', x, '"')
    }
    json_tables <- paste(sapply(names(saved_files), function(name) {
      info <- saved_files[[name]]
      sprintf(
        '    "%s": { "file": "%s", "rows": %d, "size_mb": %.1f, "as_of_date": %s, "min_term": %s, "max_term": %s }',
        name, info$filename, info$rows, info$size_mb,
        null_or_str(info$as_of_date),
        null_or_str(info$min_term),
        null_or_str(info$max_term)
      )
    }), collapse = ",\n")
    json <- sprintf('{\n  "generated": "%s",\n  "tables": {\n%s\n  }\n}\n',
                    format(Sys.time(), "%Y-%m-%d %H:%M:%S"), json_tables)
    writeLines(json, status_file)
    message("  ✅ Wrote ", status_file)
  }, error = function(e) {
    message("  ⚠️  Could not write status file: ", conditionMessage(e))
  })


  # ========================================
  # 8. Copy to local data (non-Docker)
  # ========================================

  # Use config variables for shared-data and local data locations
  # (config.R is sourced in MAIN section if running standalone)
  shared_data_dir <- if (exists("cedar_shared_data_dir")) cedar_shared_data_dir else ""
  local_data_dir <- if (exists("cedar_data_dir")) cedar_data_dir else ""

  # Only copy if NOT in Docker and both directories exist
  if (!is_docker && shared_data_dir != "" && local_data_dir != "" &&
      dir.exists(shared_data_dir) && dir.exists(local_data_dir)) {
    message("\n──────────────────────────────────────────────────────")
    message("8. Copying CEDAR files to local data (non-Docker)")
    message("──────────────────────────────────────────────────────")
    message("Source: ", shared_data_dir)
    message("Destination: ", local_data_dir)

    for (name in names(saved_files)) {
      info <- saved_files[[name]]
      source_path <- info$filepath
      dest_path <- file.path(local_data_dir, info$filename)

      message("Copying: ", info$filename, " → local data/")

      if (file.copy(source_path, dest_path, overwrite = TRUE)) {
        message("  ✅ Copied")
      } else {
        message("  ⚠️  Copy failed")
      }
    }
  } else if (is_docker) {
    message("\n  ⏭  Skipping local data copy (running inside Docker container)")
  } else {
    message("\n  ⏭  Skipping local data copy (directories not configured or not found)")
    if (shared_data_dir != "") {
      message("     shared_data_dir = ", shared_data_dir)
    } else {
      message("     Hint: Ensure config/config.R defines cedar_shared_data_dir")
    }
    if (local_data_dir != "") {
      message("     cedar_data_dir = ", local_data_dir)
    } else {
      message("     Hint: Ensure config/config.R defines cedar_data_dir")
    }
  }

  # ========================================
  # 9. Summary
  # ========================================
  message("\n")
  message("═══════════════════════════════════════════════════════")
  message("  Transformation Complete!")
  message("═══════════════════════════════════════════════════════")
  message("\n")
  message("CEDAR model files created:")
  for (name in names(saved_files)) {
    info <- saved_files[[name]]
    message("  ✅ cedar_", name, ext, " (",
            format(info$rows, big.mark = ","), " rows, ",
            round(info$size_mb, 1), " MB)")
  }
  message("\n")
  message("Original MyReports files remain unchanged.")
  message("To use CEDAR model, set cedar_use_new_model <- TRUE in config.R")
  message("\n")

  invisible(saved_files)
}


# ---- MAIN (if run directly) ----
if (!interactive() && !exists("SOURCED_FROM_PARSE_DATA")) {
  message("[transform-to-cedar.R] Running as standalone script")

  # Load config if available
  if (file.exists("config/config.R")) {
    source("config/config.R")
  }

  # Check for command-line arguments
  # Usage: Rscript transform-to-cedar.R --data-dir /path/to/data
  args <- commandArgs(trailingOnly = TRUE)
  data_dir_arg <- NULL
  tables_arg <- NULL

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

  # Run transformation with provided data_dir (or NULL to use config)
  transform_to_cedar(data_dir = data_dir_arg, tables = tables_arg)
}
