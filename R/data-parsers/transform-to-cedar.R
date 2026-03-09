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
# - Mar 2026: Added is_topics to cedar_sections (TRUE when course_title starts with "T:")
# - Jan 2026: Removed duplicate 'grade' column; use 'final_grade' as standard column name
# - Jan 2026: Added subject_code, level, instructor_id to cedar_students (for credit-hours)
# - Jan 2026: Added student_level, student_college, student_campus to cedar_programs (for headcount)
# - Jan 2026: Removed alias columns to reduce confusion:
#     - cedar_students: removed 'primary_major' alias (use 'major' only)
#     - cedar_degrees: removed 'degree_term' (use 'term'), 'degree_type' (use 'degree'),
#                      'program' (use 'program_code'), 'actual_college' (use 'student_college')

library(tidyverse)
library(digest)

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
transform_to_cedar <- function(data_dir = NULL, use_qs = NULL) {

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

  message("Configuration:")
  message("  Data directory: ", data_dir)
  message("  File format: ", ext)
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
    
    # Return metadata for tracking
    list(
      filename = filename,
      filepath = filepath,
      rows = row_count,
      size_mb = file_size_mb
    )
  }

  # Initialize cedar_data for temporary storage (used by lookups generation)
  cedar_data <- list()

  # ========================================
  # 1. Transform DESRs → cedar_sections
  # ========================================
  message("──────────────────────────────────────────────────────")
  message("1. Transforming DESRs → cedar_sections")
  message("──────────────────────────────────────────────────────")

  desr_file <- file.path(data_dir, paste0("DESRs", ext))

  if (file.exists(desr_file)) {
    message("Loading: ", desr_file)

    if (ext == ".qs") {
      desrs <- qs::qread(desr_file)
    } else {
      desrs <- readRDS(desr_file)
    }

    message("  Loaded ", nrow(desrs), " rows, ", ncol(desrs), " columns")
    message("  Input columns: ", paste(names(desrs), collapse=", "))
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
        subject_course = SUBJ_CRSE,  # Already created by parser
        section = SECT,
        course_title = SECT_TITLE,
        part_term = if ("PT" %in% names(.)) PT else NA_character_,  # Part of term (e.g., "1H", "2H", "FT")

        # Organizational
        campus = CAMP,
        college = COLLEGE,
        department = DEPT,

        # Instructor
        instructor_id = as.character(PRIM_INST_ID),
        instructor_name = INST_NAME,  # Already created by parser
        job_cat = if ("job_cat" %in% names(.)) job_cat else NA_character_,  # From HR data join

        # Enrollment
        enrolled = as.integer(ENROLLED),  # Section-level enrollment
        total_enrl = as.integer(total_enrl),  # Total including crosslisted (parser creates this)
        capacity = if ("SECT_CAP" %in% names(.)) as.integer(SECT_CAP) else as.integer(ROOM_CAP),  # Use SECT_CAP if available, else ROOM_CAP
        available = as.integer(SEATS_AVAIL),  # Use direct SEATS_AVAIL from source data

        # Crosslist information
        crosslist_code = if ("XL_CODE" %in% names(.)) as.character(XL_CODE) else "0",
        crosslist_subject = if ("XL_SUBJ" %in% names(.)) as.character(XL_SUBJ) else "",

        # Status
        status = STATUS,

        # Methods & characteristics (from parser)
        delivery_method = INST_METHOD,
        level = level,  # Parser-created
        term_type = term_type,  # Parser-created
        gen_ed_area = gen_ed_area,  # Parser-created
        is_lab = lab,  # Parser calls it 'lab' not 'is_lab'

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

  if (file.exists(cl_file)) {
    message("Loading: ", cl_file)

    if (ext == ".qs") {
      class_lists <- qs::qread(cl_file)
    } else {
      class_lists <- readRDS(cl_file)
    }

    message("  Loaded ", nrow(class_lists), " rows, ", ncol(class_lists), " columns")
    message("  Input columns: ", paste(names(class_lists), collapse=", "))
    message("  Transforming to CEDAR model...")

    # Helper function for student ID encryption (if not already encrypted)
    encrypt_if_needed <- function(id) {
      # Check if already looks like a hash (64 char hex string)
      if (all(nchar(as.character(id)) == 64)) {
        return(as.character(id))
      }
      # Otherwise encrypt
      salt <- Sys.getenv("CEDAR_STUDENT_SALT")
      if (salt == "") salt <- "cedar_default_salt_change_me"
      sapply(id, function(x) digest(paste0(x, salt), algo = "sha256"))
    }

    cedar_students <- class_lists %>%
      transmute(
        # Identifiers
        enrollment_id = row_number(),
        section_id = paste0(`Academic Period Code`, "-", `Course Reference Number`),
        crn = as.character(`Course Reference Number`),  # For backward compatibility with gradebook.R
        student_id = encrypt_if_needed(`Student ID`),
        term = as.integer(`Academic Period Code`),

        # Course info (denormalized for performance)
        subject_course = SUBJ_CRSE,  # Parser-created
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

        # Student demographics
        student_level = `Student Level Code`,
        student_classification = `Student Classification`,
        major = if ("Major Code" %in% names(.)) `Major Code` else NA_character_,
        student_college = `Student College Code`,
        student_campus = `Student Campus Code`,

        # Characteristics
        term_type = if ("term_type" %in% names(.)) term_type else NA_character_,  # Parser-created
        residency = if ("Residency" %in% names(.)) Residency else NA_character_,
        dual_credit = if ("Dual Credit" %in% names(.)) (`Dual Credit` == "Y") else NA,
        part_term = if ("Sub-Academic Period Code" %in% names(.)) `Sub-Academic Period Code` else NA_character_,  # Part of term from class_lists

        # Metadata
        as_of_date = as.Date(as_of_date)
      )

    message("  ✅ Created cedar_students: ", nrow(cedar_students), " rows, ", ncol(cedar_students), " columns")
    message("  Output columns: ", paste(names(cedar_students), collapse=", "))
    message("  Size reduction: ", ncol(class_lists), " → ", ncol(cedar_students), " columns (",
            round(100 * (1 - ncol(cedar_students)/ncol(class_lists))), "% reduction)")

    # Capture Major Code → Major name mapping before freeing class_lists.
    # class_lists is the Banner source of truth for this mapping (~100% coverage).
    # Stored in function scope; consumed in step 6 when building cedar_lookups.
    # arrange(desc(as_of_date)) ensures the most recent name wins when a program
    # was renamed (e.g., "Biochemistry" → "Chemical Biology" for code CHBI).
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
      major_code_name_raw <- NULL
      message("  ⚠️  Major Code/Major columns not found — skipping major name capture")
    }

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

  if (file.exists(as_file)) {
    message("Loading: ", as_file)

    if (ext == ".qs") {
      academic_studies <- qs::qread(as_file)
    } else {
      academic_studies <- readRDS(as_file)
    }

    message("  Loaded ", nrow(academic_studies), " rows, ", ncol(academic_studies), " columns")
    message("  Input columns: ", paste(names(academic_studies), collapse=", "))
    message("  Transforming to CEDAR model (pivot_longer wide → long)...")

    # Program name columns - column name becomes program_type, value becomes program_name
    program_name_cols <- c("Major", "Second Major", "First Minor", "Second Minor",
                           "First Concentration", "Second Concentration", "Third Concentration")

    # Simple pivot: column names become program_type, values become program_name
    cedar_programs <- academic_studies %>%
      pivot_longer(
        cols = any_of(program_name_cols),
        names_to = "program_type",
        values_to = "program_name",
        values_drop_na = TRUE
      ) %>%
      filter(program_name != "") %>%
      transmute(
        program_id = paste0(term_code, "-", ID, "-", program_type),
        student_id = encrypt_if_needed(ID),
        term = as.integer(term_code),
        program_type,
        program_name,
        program_classification = `Program Classification`,      
        department = Department,
        degree = Degree,
        student_classification = `Student Classification`,
        student_level = `Student Level`,
        student_campus = `Student Campus`,
        student_college = `Translated College`,
        as_of_date = as.Date(as_of_date)
      )

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

  if (file.exists(deg_file)) {
    message("Loading: ", deg_file)

    if (ext == ".qs") {
      degrees <- qs::qread(deg_file)
    } else {
      degrees <- readRDS(deg_file)
    }

    message("  Loaded ", nrow(degrees), " rows, ", ncol(degrees), " columns")
    message("  Input columns: ", paste(names(degrees), collapse=", "))
    message("  Transforming to CEDAR model...")

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
        program_code = `Program Code`,
        program_name = Program,
        college = `Translated College`,
        department = Department,
        graduation_status = `Graduation Status`,

        # Major/minor fields
        campus = if ("Campus" %in% names(.)) Campus else NA_character_,
        major = if ("Major" %in% names(.)) Major else NA_character_,
        major_code = if ("Major Code" %in% names(.)) `Major Code` else NA_character_,
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
          as.integer(`Academic Period Admitted`)
        } else NA_integer_,

        # Metadata
        as_of_date = as.Date(as_of_date)
      )

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

  if (file.exists(hr_file)) {
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

  # Load handcoded mappings from mappings.R (primary source of truth for A&S)
  mappings_file <- file.path(dirname(data_dir), "R", "lists", "mappings.R")
  if (file.exists(mappings_file)) {
    message("  Loading handcoded mappings from: ", mappings_file)
    source(mappings_file)
  } else {
    message("  ⚠️  mappings.R not found at: ", mappings_file)
    message("      Will use data-derived mappings only")
    # Create empty maps if file not found
    major_to_program_map <- c()
    prgm_to_dept_map <- c()
    dept_code_to_name <- c()
  }

  # 6a. Program name → dept_code lookup (combines handcoded + data-derived)
  message("  Building program_name → dept_code lookup...")
  if ("programs" %in% names(cedar_data)) {

    # Start with handcoded major_to_program_map (program_name → dept_code)
    if (length(major_to_program_map) > 0) {
      handcoded_program_lookup <- tibble(
        program_name = names(major_to_program_map),
        dept_code = as.character(major_to_program_map)
      )
      message("    Handcoded mappings: ", nrow(handcoded_program_lookup), " entries")
    } else {
      handcoded_program_lookup <- tibble(program_name = character(), dept_code = character())
    }

    # Build data-derived mappings for programs not in handcoded list
    # Uses the department column directly (most reliable)
    data_derived_lookup <- cedar_data$programs %>%
      filter(!is.na(program_name) & program_name != "" & !is.na(department) & department != "") %>%
      # For each program_name, get the most common department association
      count(program_name, department, sort = TRUE) %>%
      group_by(program_name) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      # Only keep entries NOT already in handcoded list
      filter(!(program_name %in% handcoded_program_lookup$program_name)) %>%
      transmute(program_name, dept_code = department)  # Use department as dept_code for now

    message("    Data-derived mappings: ", nrow(data_derived_lookup), " additional entries")

    # Combine handcoded (priority) with data-derived
    program_name_lookup <- bind_rows(handcoded_program_lookup, data_derived_lookup) %>%
      distinct(program_name, .keep_all = TRUE)

    message("    ✅ program_name_lookup: ", nrow(program_name_lookup), " total entries")
    message("    Sample: ", paste(head(program_name_lookup$program_name, 10), collapse = ", "))

    # 6b. Department string → dept_code mapping
    # Maps the raw department values (like "AS Anthropology") to standard codes
    message("  Building department → dept_code lookup...")

    # Start with handcoded hr_org_desc_to_dept_map if available
    if (exists("hr_org_desc_to_dept_map") && length(hr_org_desc_to_dept_map) > 0) {
      handcoded_dept_lookup <- tibble(
        department = names(hr_org_desc_to_dept_map),
        dept_code = as.character(hr_org_desc_to_dept_map)
      )
      message("    Handcoded dept mappings: ", nrow(handcoded_dept_lookup), " entries")
    } else {
      handcoded_dept_lookup <- tibble(department = character(), dept_code = character())
    }

    # Data-derived: unique department values from programs
    unique_departments <- cedar_data$programs %>%
      filter(!is.na(department) & department != "") %>%
      distinct(department) %>%
      # Only keep entries NOT already in handcoded list
      filter(!(department %in% handcoded_dept_lookup$department)) %>%
      # For unknown departments, use the department string as the code
      mutate(dept_code = department)

    message("    Data-derived dept mappings: ", nrow(unique_departments), " additional entries")

    dept_lookup <- bind_rows(handcoded_dept_lookup, unique_departments) %>%
      distinct(department, .keep_all = TRUE)

    # 6c. Dept code → human-readable name (from handcoded dept_code_to_name)
    if (length(dept_code_to_name) > 0) {
      dept_name_lookup <- tibble(
        dept_code = names(dept_code_to_name),
        dept_name = as.character(dept_code_to_name)
      )
      message("    ✅ dept_name_lookup: ", nrow(dept_name_lookup), " human-readable names")
    } else {
      dept_name_lookup <- tibble(dept_code = character(), dept_name = character())
    }

    cedar_data$lookups <- list(
      program_name_lookup = program_name_lookup,  # program_name → dept_code
      dept_lookup = dept_lookup,                   # department string → dept_code
      dept_name_lookup = dept_name_lookup          # dept_code → human-readable name
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
  # Derived from class_lists (Banner source) in step 2; ~100% coverage vs.
  # the hand-coded program_code_to_name in mappings.R which covers ~24%.
  # global.R uses this to override program_code_to_name at app startup so all
  # downstream code (credit-hours.R, dept-dashboard.R, etc.) benefits automatically.
  message("  Building major_code_to_name lookup...")
  if (!is.null(major_code_name_raw) && nrow(major_code_name_raw) > 0) {
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
  
  # Now that lookups are done, free sections and programs from memory
  if ("sections" %in% names(cedar_data)) {
    rm(list = "cedar_sections", envir = .GlobalEnv)
    cedar_data$sections <- NULL
  }
  if ("programs" %in% names(cedar_data)) {
    rm(list = "cedar_programs", envir = .GlobalEnv)
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
  
  if (length(args) > 0) {
    for (i in seq_along(args)) {
      if (args[i] == "--data-dir" && i < length(args)) {
        data_dir_arg <- args[i + 1]
        message("Command-line data_dir: ", data_dir_arg)
      }
    }
  }

  # Run transformation with provided data_dir (or NULL to use config)
  transform_to_cedar(data_dir = data_dir_arg)
}
