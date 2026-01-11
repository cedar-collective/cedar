# transform-to-cedar.R
#
# Transforms existing MyReports-based data files to CEDAR data model
# This runs AFTER parse-data.R and creates cedar_* files alongside existing files
#
# IMPORTANT: This does NOT modify existing workflow - all current files remain unchanged
# New CEDAR files are created in parallel with names: cedar_sections.qs, cedar_enrollments.qs, etc.

library(tidyverse)
library(digest)

#' Transform MyReports data to CEDAR model
#'
#' Reads existing parsed data files (DESRs, class_lists, etc.) and creates
#' new CEDAR model files (cedar_sections, cedar_enrollments, etc.)
#'
#' @param data_dir Path to data directory (default: from config)
#' @param use_qs Use .qs format (default: from config)
#' @return List of CEDAR data objects
transform_to_cedar <- function(data_dir = NULL, use_qs = NULL) {

  message("\n")
  message("═══════════════════════════════════════════════════════")
  message("  CEDAR Data Model Transformation")
  message("═══════════════════════════════════════════════════════")
  message("\n")

  # Get data directory from config if not provided
  if (is.null(data_dir)) {
    data_dir <- if (exists("cedar_data_dir")) cedar_data_dir else "data/"
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

  # Initialize result list
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

        # Organizational
        campus = CAMP,
        college = COLLEGE,
        department = DEPT,

        # Instructor
        instructor_id = as.character(PRIM_INST_ID),
        instructor_name = INST_NAME,  # Already created by parser

        # Enrollment
        enrolled = as.integer(total_enrl),  # Parser creates this
        capacity = as.integer(MAX_ENROLLED),

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
        as_of_date = as.Date(as_of_date)
      )

    message("  ✅ Created cedar_sections: ", nrow(cedar_sections), " rows, ", ncol(cedar_sections), " columns")
    message("  Size reduction: ", ncol(desrs), " → ", ncol(cedar_sections), " columns (",
            round(100 * (1 - ncol(cedar_sections)/ncol(desrs))), "% reduction)")

    cedar_data$sections <- cedar_sections

  } else {
    message("  ⚠️  DESRs file not found: ", desr_file)
    message("  Skipping cedar_sections transformation")
  }

  # ========================================
  # 2. Transform class_lists → cedar_enrollments
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("2. Transforming class_lists → cedar_enrollments")
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

    cedar_enrollments <- class_lists %>%
      transmute(
        # Identifiers
        enrollment_id = row_number(),
        section_id = paste0(`Academic Period Code`, "-", `Course Reference Number`),
        student_id = encrypt_if_needed(`Student ID`),
        term = as.integer(`Academic Period Code`),

        # Course info (denormalized for performance)
        subject_course = SUBJ_CRSE,  # Parser-created
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
        grade = `Final Grade`,
        credits = if ("Course Credits" %in% names(.)) as.numeric(`Course Credits`) else NA_real_,

        # Student demographics
        student_level = `Student Level Code`,
        student_classification = `Student Classification`,
        primary_major = if ("Major Code" %in% names(.)) `Major Code` else NA_character_,
        student_college = `Student College Code`,
        student_campus = `Student Campus Code`,

        # Characteristics
        term_type = if ("term_type" %in% names(.)) term_type else NA_character_,  # Parser-created
        residency = if ("Residency" %in% names(.)) Residency else NA_character_,
        dual_credit = if ("Dual Credit" %in% names(.)) (`Dual Credit` == "Y") else NA,

        # Metadata
        as_of_date = as.Date(as_of_date)
      )

    message("  ✅ Created cedar_enrollments: ", nrow(cedar_enrollments), " rows, ", ncol(cedar_enrollments), " columns")
    message("  Size reduction: ", ncol(class_lists), " → ", ncol(cedar_enrollments), " columns (",
            round(100 * (1 - ncol(cedar_enrollments)/ncol(class_lists))), "% reduction)")

    cedar_data$enrollments <- cedar_enrollments

  } else {
    message("  ⚠️  class_lists file not found: ", cl_file)
    message("  Skipping cedar_enrollments transformation")
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
    message("  Transforming to CEDAR model (expanding majors/minors)...")

    # Process primary majors
    programs_primary <- academic_studies %>%
      filter(!is.na(`Program Code`)) %>%
      transmute(
        program_id = paste0(term_code, "-", ID, "-M1"),  # M1 = Major 1
        student_id = encrypt_if_needed(ID),
        term = as.integer(term_code),
        program_type = "Major",
        program_code = `Program Code`,
        program_name = Program,
        college = `Translated College`,
        department = if ("major_DEPT" %in% names(.)) major_DEPT else Department,
        degree = Degree,
        classification = `Program Classification`,
        as_of_date = as.Date(as_of_date)
      )

    # Process second majors
    programs_second_major <- academic_studies %>%
      filter(!is.na(`Second Major Code`)) %>%
      transmute(
        program_id = paste0(term_code, "-", ID, "-M2"),  # M2 = Major 2
        student_id = encrypt_if_needed(ID),
        term = as.integer(term_code),
        program_type = "Major",
        program_code = `Second Major Code`,
        program_name = `Second Major`,
        college = `Translated College`,
        department = if ("sec_major_DEPT" %in% names(.)) sec_major_DEPT else NA_character_,
        degree = Degree,
        classification = if ("Second Program Classification" %in% names(.)) {
          `Second Program Classification`
        } else NA_character_,
        as_of_date = as.Date(as_of_date)
      )

    # Process first minors
    programs_minor1 <- academic_studies %>%
      filter(!is.na(`First Minor Code`)) %>%
      transmute(
        program_id = paste0(term_code, "-", ID, "-m1"),  # m1 = minor 1
        student_id = encrypt_if_needed(ID),
        term = as.integer(term_code),
        program_type = "Minor",
        program_code = `First Minor Code`,
        program_name = `First Minor`,
        college = `Translated College`,
        department = if ("minor_DEPT" %in% names(.)) minor_DEPT else NA_character_,
        degree = NA_character_,
        classification = NA_character_,
        as_of_date = as.Date(as_of_date)
      )

    # Process second minors
    programs_minor2 <- academic_studies %>%
      filter(!is.na(`Second Minor Code`)) %>%
      transmute(
        program_id = paste0(term_code, "-", ID, "-m2"),  # m2 = minor 2
        student_id = encrypt_if_needed(ID),
        term = as.integer(term_code),
        program_type = "Minor",
        program_code = `Second Minor Code`,
        program_name = `Second Minor`,
        college = `Translated College`,
        department = if ("sec_minor_DEPT" %in% names(.)) sec_minor_DEPT else NA_character_,
        degree = NA_character_,
        classification = NA_character_,
        as_of_date = as.Date(as_of_date)
      )

    # Combine all programs
    cedar_programs <- bind_rows(
      programs_primary,
      programs_second_major,
      programs_minor1,
      programs_minor2
    )

    message("  ✅ Created cedar_programs: ", nrow(cedar_programs), " rows, ", ncol(cedar_programs), " columns")
    message("     Primary majors: ", nrow(programs_primary))
    message("     Second majors: ", nrow(programs_second_major))
    message("     First minors: ", nrow(programs_minor1))
    message("     Second minors: ", nrow(programs_minor2))
    message("  Size reduction: ", ncol(academic_studies), " → ", ncol(cedar_programs), " columns (",
            round(100 * (1 - ncol(cedar_programs)/ncol(academic_studies))), "% reduction)")

    cedar_data$programs <- cedar_programs

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
    message("  Transforming to CEDAR model...")

    cedar_degrees <- degrees %>%
      transmute(
        # Identifiers
        degree_id = paste0(`Academic Period Code`, "-", ID, "-", `Program Code`),
        student_id = encrypt_if_needed(ID),
        degree_term = as.integer(`Academic Period Code`),

        # Degree info
        degree_type = Degree,
        program_code = `Program Code`,
        program_name = Program,
        college = `Translated College`,
        department = Department,
        graduation_status = `Graduation Status`,

        # Optional fields
        campus = if ("Campus" %in% names(.)) Campus else NA_character_,
        major = if ("Major" %in% names(.)) Major else NA_character_,
        second_major = if ("Second Major" %in% names(.)) `Second Major` else NA_character_,
        minor = if ("First Minor" %in% names(.)) `First Minor` else NA_character_,
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
    message("  Size reduction: ", ncol(degrees), " → ", ncol(cedar_degrees), " columns (",
            round(100 * (1 - ncol(cedar_degrees)/ncol(degrees))), "% reduction)")

    cedar_data$degrees <- cedar_degrees

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
        appt_percent = if ("Appt %" %in% names(.)) as.numeric(`Appt %`) else NA_real_,
        college = if ("Home Organization Desc" %in% names(.)) `Home Organization Desc` else NA_character_,

        # Metadata
        as_of_date = if ("as_of_date" %in% names(.)) as.Date(as_of_date) else NA_Date_
      )

    message("  ✅ Created cedar_faculty: ", nrow(cedar_faculty), " rows, ", ncol(cedar_faculty), " columns")
    message("  Size reduction: ", ncol(hr_data), " → ", ncol(cedar_faculty), " columns (",
            round(100 * (1 - ncol(cedar_faculty)/ncol(hr_data))), "% reduction)")

    cedar_data$faculty <- cedar_faculty

  } else {
    message("  ⚠️  hr_data file not found: ", hr_file)
    message("  Skipping cedar_faculty transformation")
  }

  # ========================================
  # 6. Save CEDAR model files
  # ========================================
  message("\n──────────────────────────────────────────────────────")
  message("6. Saving CEDAR model files")
  message("──────────────────────────────────────────────────────")

  for (table_name in names(cedar_data)) {
    filename <- paste0("cedar_", table_name, ext)
    filepath <- file.path(data_dir, filename)

    message("Saving: ", filepath)

    if (ext == ".qs") {
      qs::qsave(cedar_data[[table_name]], filepath, preset = "fast")
    } else {
      saveRDS(cedar_data[[table_name]], filepath)
    }

    # Get file size
    file_size_mb <- file.size(filepath) / 1024^2
    message("  ✅ Saved (", round(file_size_mb, 1), " MB)")
  }

  # ========================================
  # 7. Summary
  # ========================================
  message("\n")
  message("═══════════════════════════════════════════════════════")
  message("  Transformation Complete!")
  message("═══════════════════════════════════════════════════════")
  message("\n")
  message("CEDAR model files created:")
  for (table_name in names(cedar_data)) {
    message("  ✅ cedar_", table_name, ext, " (",
            format(nrow(cedar_data[[table_name]]), big.mark = ","), " rows)")
  }
  message("\n")
  message("Original MyReports files remain unchanged.")
  message("To use CEDAR model, set cedar_use_new_model <- TRUE in config.R")
  message("\n")

  invisible(cedar_data)
}


# ---- MAIN (if run directly) ----
if (!interactive() && !exists("SOURCED_FROM_PARSE_DATA")) {
  message("[transform-to-cedar.R] Running as standalone script")

  # Load config if available
  if (file.exists("config/config.R")) {
    source("config/config.R")
  }

  # Run transformation
  transform_to_cedar()
}
