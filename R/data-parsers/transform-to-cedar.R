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


# ── generate_program_map ──────────────────────────────────────────────────────

#' Build program_map from academic_studies
#'
#' Parses Banner program codes from raw academic_studies data and resolves each
#' to college_code, dept_code, degree_level, program_type, and canonical_code.
#' Called by transform_to_cedar() when program_map.qs is absent.
#'
#' @param as_file       Path to academic_studies file (qs or Rds)
#' @param ext           File extension: ".qs" or ".Rds"
#' @param subj_dept_map Data frame from subj_dept_map.R
#' @param premaj_canon  Named character vector from program_code_maps.R
#' @param xvar_explicit Named character vector from program_code_maps.R
#' @param extra_p2d     Named character vector from program_code_maps.R
#' @param known_suffixes Character vector of valid college suffixes
#' @param real_F_progs  Character vector of F-prefix codes that are not pre-majors
#' @param get_lev       Function that maps degree description → degree level string
#' @return A tibble with columns: program_code, college_code, dept_code, major_code,
#'         degree_abbr, degree_level, program_type, canonical_code
generate_program_map <- function(as_file, ext, subj_dept_map,
                                 premaj_canon, xvar_explicit, extra_p2d,
                                 known_suffixes, real_F_progs, get_lev,
                                 ad_major_to_dept = NULL,
                                 allowed_unmapped_program_codes = character()) {
  ap <- if (ext == ".qs") qs2::qs_read(as_file) else readRDS(as_file)

  uc  <- subj_dept_map
  p2d <- setNames(uc$dept_code, uc$subject_code)
  .col_lu    <- dplyr::distinct(uc, college_code, college_name)
  cname2code <- setNames(.col_lu$college_code, .col_lu$college_name)
  d2c        <- { u <- uc[!duplicated(uc$dept_code), ]; setNames(u$college_code, u$dept_code) }

  for (nm in names(extra_p2d))   if (is.na(p2d[nm])) p2d[nm] <- extra_p2d[nm]
  for (d  in unique(uc$dept_code)) if (is.na(p2d[d]))  p2d[d]  <- d
  for (nm in names(premaj_canon)) {
    can <- premaj_canon[nm]
    if (is.na(p2d[nm]) && !is.na(p2d[can])) p2d[nm] <- p2d[can]
  }

  progs        <- unique(ap[, c("Program Code", "Program", "Degree", "Actual College")])
  names(progs) <- c("full", "name", "deg", "col_text")
  parts        <- strsplit(progs$full, "-")
  progs$d_abbr <- sapply(parts, `[`, 1)
  progs$p_mid  <- sapply(parts, `[`, 2)
  progs$c_suff <- sapply(parts, function(x) if (length(x) >= 3) x[3] else NA_character_)
  progs        <- progs[is.na(progs$c_suff) | progs$c_suff %in% known_suffixes, ]
  progs        <- progs[!is.na(progs$p_mid) & progs$deg != "Non-Degree Program", ]

  progs$prog_type <- ifelse(
    grepl("^X", progs$p_mid), "variant",
    ifelse(
      progs$p_mid %in% names(premaj_canon) |
        (grepl("Pre", progs$name, fixed = TRUE) & !(progs$p_mid %in% real_F_progs)),
      "pre_major", "degree"
    )
  )

  progs$canonical <- NA_character_
  pm_idx <- progs$prog_type == "pre_major" & progs$p_mid %in% names(premaj_canon)
  progs$canonical[pm_idx] <- premaj_canon[progs$p_mid[pm_idx]]
  v_idx  <- progs$prog_type == "variant"
  progs$canonical[v_idx]  <- ifelse(
    !is.na(xvar_explicit[progs$p_mid[v_idx]]),
    xvar_explicit[progs$p_mid[v_idx]],
    sub("^X", "", progs$p_mid[v_idx])
  )

  lookup_dept <- function(code) {
    if (is.na(code)) return(NA_character_)
    d <- p2d[code]
    if (!is.na(d)) return(d)
    if (code %in% unique(uc$dept_code)) return(code)
    NA_character_
  }
  progs$dept     <- sapply(progs$p_mid, lookup_dept)
  need_can       <- is.na(progs$dept) & !is.na(progs$canonical)
  progs$dept[need_can] <- sapply(progs$canonical[need_can], lookup_dept)
  progs$col      <- d2c[progs$dept]
  fb             <- is.na(progs$col)
  progs$col[fb]  <- cname2code[progs$col_text[fb]]

  # Branch campus programs (GA/LA/TA/VA suffix) always belong to the AD college.
  # The dept→college lookup above assigns them to their main-campus equivalent college
  # (e.g. CRIM → SOCI → AS, MATH → AS, CS → EN). Force college_code = "AD".
  # For programs where the main-campus dept is also wrong (CRIM should map to CJUS
  # not SOCI at branch campus), apply explicit overrides from ad_major_to_dept.
  branch_campus_suffixes <- c("GA", "LA", "TA", "VA")
  branch_mask <- !is.na(progs$c_suff) & progs$c_suff %in% branch_campus_suffixes
  if (any(branch_mask) && !is.null(ad_major_to_dept) && length(ad_major_to_dept) > 0) {
    override_depts <- ad_major_to_dept[progs$p_mid[branch_mask]]
    has_override   <- !is.na(override_depts)
    progs$dept[branch_mask][has_override] <- override_depts[has_override]
  }
  progs$col[branch_mask] <- "AD"

  progs$lev <- mapply(get_lev, progs$deg, progs$d_abbr)
  progs$lev[progs$d_abbr == "PMS"]                     <- "Graduate"
  progs$lev[grepl("ME in Mfg|ME in Manuf", progs$deg)] <- "Graduate"

  unmapped <- progs[is.na(progs$dept), ]
  if (nrow(unmapped) > 0) {
    unexpected <- unmapped[!(unmapped$full %in% allowed_unmapped_program_codes), ]
    if (nrow(unexpected) > 0) {
      display <- utils::capture.output(print(
        unexpected[, c("full", "name", "deg", "col_text", "p_mid", "c_suff")],
        row.names = FALSE
      ))
      stop("[generate_program_map] Unmapped program codes found.\n",
           "Add a dept mapping in R/lists/program_code_maps.R or explicitly list a reviewed exception in ",
           "allowed_unmapped_program_codes.\n",
           paste(display, collapse = "\n"))
    }
    message("  Reviewed unmapped program codes retained without dept_code: ", nrow(unmapped))
  }

  progs %>%
    dplyr::transmute(
      program_code   = full,
      college_code   = col,
      dept_code      = dept,
      major_code     = p_mid,
      degree_abbr    = d_abbr,
      degree_level   = lev,
      program_type   = prog_type,
      canonical_code = canonical
    )
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

  subj_to_dept <- maps$subj_to_dept
  gen_ed       <- maps$gen_ed

  # ── Pre-processing: derive helper columns ────────────────────────────────
  message("  Pre-processing: deriving helper columns...")

  desrs <- desrs %>%
    unite(SUBJ_CRSE, c("SUBJ", "CRSE"),               sep = " ",  remove = FALSE) %>%
    unite(INST_NAME, c("PRIM_INST_LAST", "PRIM_INST_FIRST"), sep = ", ", remove = FALSE) %>%
    mutate(
      lab        = grepl("[[:alpha:]]", CRSE),
      crse_base  = as.integer(ifelse(lab, substr(CRSE, 1, nchar(CRSE) - 1), CRSE)),
      total_enrl = as.numeric(pmax(ENROLLED, XL_ENRL, na.rm = TRUE)),
      level      = dplyr::case_when(
        crse_base < 300                    ~ "lower",
        crse_base >= 1000                  ~ "lower",
        crse_base >= 500 & crse_base < 700 ~ "grad",
        crse_base >= 300 & crse_base < 500 ~ "upper"
      ),
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

  if (length(subj_to_dept) > 0) {
    desrs <- desrs %>% mutate(DEPT = dplyr::coalesce(subj_to_dept[SUBJ], SUBJ))
    unmapped_as_subj <- desrs %>%
      filter(COLLEGE == "AS", DEPT == SUBJ, !SUBJ %in% names(subj_to_dept)) %>%
      distinct(SUBJ) %>% pull(SUBJ)
    if (length(unmapped_as_subj) > 0)
      message("  ⚠️  AS subject codes not in subj_to_dept (using SUBJ as dept): ",
              paste(unmapped_as_subj, collapse = ", "),
              "\n      Add to subj_to_dept in R/lists/mappings.R if dept aggregation is needed")
  } else {
    desrs <- desrs %>% mutate(DEPT = SUBJ)
    message("  ⚠️  subj_to_dept not found — using SUBJ as DEPT for all rows")
  }

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
      college      = COLLEGE,
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
    group_by(term, crosslist_group) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    pull(section_id)

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
    group_by(term, crosslist_group) %>%
    summarize(n_subjects = dplyr::n_distinct(subject), .groups = "drop") %>%
    filter(n_subjects == 1) %>%
    select(term, crosslist_group)

  cedar_sections <- cedar_sections %>%
    left_join(xl_internal_groups %>% mutate(.is_internal = TRUE),
              by = c("term", "crosslist_group")) %>%
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
    distinct(term, crosslist_group, section_id, level) %>%
    group_by(term, crosslist_group) %>%
    summarize(
      .is_split = any(level %in% c("lower", "upper")) & any(level == "grad"),
      .groups = "drop"
    ) %>%
    filter(.is_split) %>%
    select(term, crosslist_group)

  cedar_sections <- cedar_sections %>%
    left_join(split_groups %>% mutate(.is_split = TRUE), by = c("term", "crosslist_group")) %>%
    mutate(is_split = coalesce(.is_split, FALSE)) %>%
    select(-.is_split)

  split_labels <- cedar_sections %>%
    filter(is_split) %>%
    distinct(term, crosslist_group, subject_course) %>%
    group_by(term, crosslist_group) %>%
    summarize(split_sections = paste(sort(subject_course), collapse = " / "), .groups = "drop")

  cedar_sections <- cedar_sections %>%
    left_join(split_labels, by = c("term", "crosslist_group")) %>%
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
    group_by(term, crosslist_group) %>%
    summarize(crosslist_external = n_distinct(department) > 1, .groups = "drop")
  cedar_sections <- cedar_sections %>%
    left_join(xlist_dept_scope, by = c("term", "crosslist_group"))

  # crosslist_partners: all subject_course values in the same external crosslist group.
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
  message("  ✅ Deduplicated: ", n_before_dedup, " → ", nrow(cedar_sections),
          " rows (", n_before_dedup - nrow(cedar_sections), " partner-expansion duplicates removed)")
  message("  ✅ Created cedar_sections: ", nrow(cedar_sections), " rows, ", ncol(cedar_sections), " columns")
  message("  Output columns: ", paste(names(cedar_sections), collapse = ", "))

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

  subj_to_dept            <- maps$subj_to_dept
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
    if (length(subj_to_dept) > 0) {
      class_lists <- class_lists %>%
        mutate(DEPT = dplyr::coalesce(subj_to_dept[`Subject Code`], `Subject Code`))
    } else {
      class_lists$DEPT <- class_lists$`Subject Code`
    }
  }

  # Drop Subject Code and Course Number (now encoded in SUBJ_CRSE); keep transmute inputs.
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

  cedar_students <- class_lists %>% transmute(
      enrollment_id  = row_number(),
      crn            = as.character(`Course Reference Number`),
      student_id     = encrypt_if_needed(`Student ID`),
      term           = as.integer(`Academic Period Code`),
      subject_course = SUBJ_CRSE,
      subject_code   = sub(" .*", "", SUBJ_CRSE),
      course_title   = if ("Short Course Title" %in% names(.)) `Short Course Title` else NA_character_,
      level = case_when(
        grepl("^[A-Z]+ [0-2][0-9]{2}", SUBJ_CRSE) ~ "lower",
        grepl("^[A-Z]+ [3-4][0-9]{2}", SUBJ_CRSE) ~ "upper",
        grepl("^[A-Z]+ [5-9][0-9]{2}", SUBJ_CRSE) ~ "grad",
        TRUE ~ "unknown"
      ),
      instructor_id         = if ("Primary Instructor ID"         %in% names(.)) `Primary Instructor ID`         else NA_character_,
      instructor_last_name  = if ("Primary Instructor Last Name"  %in% names(.)) `Primary Instructor Last Name`  else NA_character_,
      instructor_first_name = if ("Primary Instructor First Name" %in% names(.)) `Primary Instructor First Name` else NA_character_,
      instructor_name = case_when(
        !is.na(instructor_last_name) & !is.na(instructor_first_name) ~ paste0(instructor_last_name, ", ", instructor_first_name),
        !is.na(instructor_last_name) ~ instructor_last_name,
        TRUE ~ NA_character_
      ),
      campus     = `Course Campus Code`,
      college    = `Course College Code`,
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
  # classify_enrollment_outcomes() (trunk/utils.R): DFW = D/F/W grades plus
  # late drops; early drops are NEVER DFW (see AGENTS.md, "CEDAR-wide DFW policy").
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
  grades_meta <- save_cedar_file(cedar_grades_tbl, "grades", data_dir, ext)
  message("  ✅ cedar_grades: ", nrow(cedar_grades_tbl), " rows, ", ncol(cedar_grades_tbl), " columns")
  rm(cedar_grades_tbl)

  # Deduplicate: Banner emits one row per CRN, so students in combined courses
  # (e.g. BIOL 302C = lecture CRN + lab CRN) appear twice. Keep one row per
  # student-course per term. cedar_grades is computed above (pre-dedup) to
  # preserve topics course enrollments.
  n_before_dedup <- nrow(cedar_students)
  cedar_students <- cedar_students %>%
    distinct(student_id, term, subject_course, .keep_all = TRUE)
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
    distinct(student_id, term, subject_course, course_title, credits,
             final_grade, registration_status_code) %>%
    mutate(
      attempted_credit = credits,
      completed_credit = if_else(final_grade %in% passing_grades, credits, 0),
      dfw_credit = if_else(final_grade %in% GRADES_DFW, credits, 0),
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
  student_terms_tbl <- cedar_students %>% select(student_id, term) %>% distinct()
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

  major_college_to_dept    <- maps$major_college_to_dept
  subj_to_dept             <- maps$subj_to_dept
  major_to_dept            <- maps$major_to_dept
  major_name_to_major_code <- maps$major_name_to_major_code
  college_name_to_code     <- maps$college_name_to_code
  real_F_progs             <- maps$real_F_progs

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
      college_code           = {
        if (length(college_name_to_code) == 0)
          stop("[transform_programs] 'college_name_to_code' lookup is not loaded. ",
               "Ensure mappings.R has been sourced before running transform-to-cedar.R.")
        college_name_to_code[`Actual College`]
      },
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
      major_code = dplyr::if_else(
        is.na(major_code) & !is.na(program_name) & nzchar(program_name),
        major_name_to_major_code[stringr::str_trim(
          sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)
        )],
        major_code
      )
    ) %>%
    dplyr::mutate(
      # Dept code lookup — four-tier priority:
      #   1. major_college_to_dept["major_code:college_code"] — disambiguates same code in multiple colleges
      #   2. subj_to_dept[major_code] — handles language/subject codes used as major codes
      #   3. major_to_dept[major_code] — catches grad programs whose Banner college_code differs
      #      from the program_map-inferred college (e.g. SPLP grad students: college "GP" vs "AS")
      #   4. major_code — last-resort identity mapping
      dept_code = dplyr::coalesce(
        major_college_to_dept[paste(major_code, college_code, sep = ":")],
        subj_to_dept[major_code],
        major_to_dept[major_code],
        major_code
      ),
      # Nullify numeric dept_codes — Banner internal org IDs that leaked into major_code
      dept_code = dplyr::if_else(grepl("^[0-9]+$", dept_code), NA_character_, dept_code),
      # is_pre_major: two complementary signals:
      #   1. "Pre " or "Pre-" prefix in program_name
      #   2. F-prefix in major_code (Banner's pre-major convention), excluding known real programs
      is_pre_major = grepl("^Pre[- ]", program_name, ignore.case = TRUE) |
        (grepl("^F[A-Z]", major_code) & !major_code %in% c(
          "FA", "FLA", "FILM", "FDMA", "FFDA", "FFDM", "FMAR", "FIDA",
          "FLHC", "FLPR", "FLAI", "FS", "FES", "FPE", "FAT", "FNE"
        )) |
        # PHRD used for UG pre-pharmacy students before 202580 (switched to FPHS)
        (major_code == "PHRD" & student_level %in% c("UG", "NG")),
      # Strip "Pre-" prefix from program_name for clean display
      program_name = dplyr::if_else(
        grepl("^Pre[- ]", program_name, ignore.case = TRUE),
        stringr::str_trim(sub("^Pre[- ]+", "", program_name, ignore.case = TRUE)),
        program_name
      ),
      # Normalize variant/historical Banner names to canonical display names.
      # Catches X-prefix variants and program renames that left a different text
      # string in the Major column even though the dept resolves correctly.
      program_name = dplyr::coalesce(
        program_name_aliases[program_name],
        program_name
      )
    )

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

  major_college_to_dept <- maps$major_college_to_dept
  subj_to_dept          <- maps$subj_to_dept
  major_to_dept         <- maps$major_to_dept
  college_name_to_code  <- maps$college_name_to_code

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
      # Dept code — three-tier lookup (see catalog_lookups.R for the full priority chain).
      # cedar_degrees omits the Tier-4 identity fallback; unknown codes get NA.
      .college_code = {
        if (length(college_name_to_code) == 0)
          stop("[transform_degrees] 'college_name_to_code' lookup is not loaded. ",
               "Ensure mappings.R has been sourced before running transform-to-cedar.R.")
        college_name_to_code[student_college]
      },
      dept_code = dplyr::coalesce(
        major_college_to_dept[paste(major_code, .college_code, sep = ":")],
        subj_to_dept[major_code],
        major_to_dept[major_code]
      ),
      degree_abbr = sub("^([A-Za-z]+)-.*$", "\\1", program_code)
    ) %>%
    dplyr::select(-.college_code)

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
  major_college_to_dept     <- maps$major_college_to_dept

  cedar_lookups <- list()

  # 7a. Program name → dept_code lookup (data-derived from cedar_programs)
  message("  Building program_name → dept_code lookup...")
  if (!is.null(cedar_programs)) {
    .extra_p2d <- if (length(maps$extra_p2d) > 0) maps$extra_p2d else character(0)

    program_name_lookup <- cedar_programs %>%
      filter(!is.na(program_name) & program_name != "" & !is.na(dept_code) & dept_code != "") %>%
      count(program_name, dept_code, sort = TRUE) %>%
      group_by(program_name) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      select(program_name, dept_code) %>%
      # Correct identity-fallback dept_codes: minor/concentration Banner codes that
      # aren't in subj_dept_map get set to dept_code = major_code during transform.
      # Apply extra_p2d overrides here so a lookups-only regeneration picks them up
      # without needing a full cedar_programs rebuild.
      dplyr::mutate(dept_code = dplyr::coalesce(.extra_p2d[dept_code], dept_code))
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
      if (length(other_codes) > 0) message("    ⚠️  Unknown dept codes (add to subj_dept_map.R if valid): ", paste(other_codes, collapse = ", "))
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
  # Resolve cedar project root from this script's location, falling back to getwd().
  script_path <- tryCatch(
    normalizePath(sys.frame(0)$ofile, mustWork = TRUE),
    error = function(e) NULL
  )
  cedar_root <- if (!is.null(script_path)) {
    dirname(dirname(dirname(script_path)))  # R/data-parsers → R → project root
  } else {
    getwd()
  }
  catalog_file            <- file.path(cedar_root, "R", "lists", "subj_dept_map.R")
  program_code_maps_file  <- file.path(cedar_root, "R", "lists", "program_code_maps.R")
  program_map_file        <- file.path(data_dir, "program_map.qs")
  cat_lookups_file        <- file.path(cedar_root, "R", "lists", "catalog_lookups.R")
  mappings_file           <- file.path(cedar_root, "R", "lists", "mappings.R")
  gen_ed_file             <- file.path(cedar_root, "R", "lists", "gen_ed_courses.R")

  if (!exists("subj_dept_map") && file.exists(catalog_file)) {
    message("  Loading subj_dept_map from: ", catalog_file)
    source(catalog_file)
  }
  if (file.exists(program_code_maps_file)) {
    source(program_code_maps_file, local = environment())
  }

  if (!exists("program_map") && file.exists(program_map_file)) {
    message("  Loading program_map from: ", program_map_file)
    program_map <- qs2::qs_read(program_map_file)
  } else if (!exists("program_map") && exists("subj_dept_map") &&
             exists("premaj_canon") && exists("xvar_explicit") && exists("extra_p2d")) {
    as_file_for_pm <- file.path(data_dir, paste0("academic_studies", ext))
    if (!file.exists(as_file_for_pm)) {
      stop("[transform-to-cedar.R] program_map.qs not found and academic_studies not available at: ",
           as_file_for_pm,
           "\n  Cannot build program_map. Place academic_studies in data_dir and re-run.")
    }
    message("  program_map.qs not found — generating from academic_studies...")
    program_map <- generate_program_map(as_file_for_pm, ext, subj_dept_map,
                                        premaj_canon, xvar_explicit, extra_p2d,
                                        known_suffixes, real_F_progs, get_lev,
                                        ad_major_to_dept,
                                        allowed_unmapped_program_codes)
    qs2::qs_save(program_map, program_map_file)
    message("  Generated and saved program_map.qs: ", nrow(program_map), " rows → ", program_map_file)
  }

  if (exists("subj_dept_map") && exists("program_map")) {
    message("  Deriving lookup vectors from catalogs...")
    source(cat_lookups_file, local = environment())
    dept_code_to_name_catalog <- dept_code_to_name
    message("  subj_dept_map: ", nrow(subj_dept_map), " rows, ",
            length(unique(subj_dept_map$subject_code)), " subject codes, ",
            length(unique(subj_dept_map$dept_code)), " dept codes, ",
            length(unique(subj_dept_map$college_code)), " colleges")
    message("  program_map: ", nrow(program_map), " rows, ",
            length(major_college_to_dept), " compound lookup keys")
  } else {
    message("  ⚠️  subj_dept_map or program_map not found — falling back to mappings.R")
    major_college_to_dept <- setNames(character(0), character(0))
    if (!exists("subj_to_dept") && file.exists(mappings_file)) source(mappings_file)
  }
  if (!exists("hr_org_desc_to_dept") && file.exists(mappings_file)) {
    message("  Loading text mappings from: ", mappings_file)
    source(mappings_file)
  }
  if (!exists("gen_ed_1_communication") && file.exists(gen_ed_file)) {
    message("  Loading gen_ed courses from: ", gen_ed_file)
    source(gen_ed_file)
  }

  # Bundle all loaded lookup vectors into a single list for passing to transform functions
  maps <- list(
    subj_to_dept              = if (exists("subj_to_dept"))              subj_to_dept              else character(0),
    major_college_to_dept     = if (exists("major_college_to_dept"))     major_college_to_dept     else character(0),
    major_name_to_major_code  = if (exists("major_name_to_major_code"))  major_name_to_major_code  else character(0),
    major_to_dept             = if (exists("major_to_dept"))             major_to_dept             else character(0),
    extra_p2d                 = if (exists("extra_p2d"))                 extra_p2d                 else character(0),
    college_name_to_code      = if (exists("college_name_to_code"))      college_name_to_code      else character(0),
    real_F_progs              = if (exists("real_F_progs"))              real_F_progs              else character(0),
    subj_dept_map             = if (exists("subj_dept_map"))             subj_dept_map             else NULL,
    hr_org_desc_to_dept       = if (exists("hr_org_desc_to_dept"))       hr_org_desc_to_dept       else character(0),
    dept_code_to_name_catalog = if (exists("dept_code_to_name_catalog")) dept_code_to_name_catalog else character(0),
    gen_ed = list(
      `1` = if (exists("gen_ed_1_communication")) gen_ed_1_communication else character(0),
      `2` = if (exists("gen_ed_2_math_stat"))     gen_ed_2_math_stat     else character(0),
      `3` = if (exists("gen_ed_3_phys_nat_sci"))  gen_ed_3_phys_nat_sci  else character(0),
      `4` = if (exists("gen_ed_4_soc_behav_sci")) gen_ed_4_soc_behav_sci else character(0),
      `5` = if (exists("gen_ed_5_humanities"))    gen_ed_5_humanities    else character(0),
      `7` = if (exists("gen_ed_7_arts_design"))   gen_ed_7_arts_design   else character(0)
    )
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

  if (!is_docker && shared_data_dir != "" && local_data_dir != "" &&
      dir.exists(shared_data_dir) && dir.exists(local_data_dir)) {
    message("\n──────────────────────────────────────────────────────")
    message("Copying CEDAR files to local data directory")
    message("  Source:      ", shared_data_dir)
    message("  Destination: ", local_data_dir)
    for (name in names(saved_files)) {
      info      <- saved_files[[name]]
      dest_path <- file.path(local_data_dir, info$filename)
      message("  Copying: ", info$filename, " → local data/")
      if (file.copy(info$filepath, dest_path, overwrite = TRUE)) {
        message("    ✅ Copied")
      } else {
        message("    ⚠️  Copy failed")
      }
    }
  } else if (is_docker) {
    message("\n  ⏭  Skipping local data copy (running inside Docker)")
  } else {
    message("\n  ⏭  Skipping local data copy (directories not configured or not found)")
    if (shared_data_dir != "") message("     cedar_shared_data_dir = ", shared_data_dir)
    else message("     Hint: ensure config/config.R defines cedar_shared_data_dir")
    if (local_data_dir  != "") message("     cedar_data_dir = ", local_data_dir)
    else message("     Hint: ensure config/config.R defines cedar_data_dir")
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

  if (file.exists("config/config.R")) source("config/config.R")

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
