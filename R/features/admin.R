# Small display payloads for Admin. Never load or scan institutional tables here.
build_admin_data_status <- function(summary, current_term) {
  terms <- summary$display_terms
  datasets <- c(sections = "Sections", students = "Students", programs = "Programs",
                degrees = "Degrees", faculty = "Faculty")
  rows <- lapply(names(datasets), function(key) {
    count <- summary[[paste0(key, "_count")]]
    dates <- summary[[paste0(key, "_term_dates")]]
    values <- vapply(as.character(terms), function(term) {
      value <- dates[[term]]
      if (is.null(value) || length(value) != 1L || is.na(value) ||
          value %in% c("-Inf", "Inf", "NA", "")) "Not available" else as.character(value)
    }, character(1))
    c(Dataset = datasets[[key]],
      Rows = if (is.null(count) || is.na(count) || count == 0L) "Not loaded" else
        format(count, big.mark = ",", scientific = FALSE, trim = TRUE), values)
  })
  display <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(display) <- c("Dataset", "Rows", vapply(terms, fmt_term, character(1)))
  # Terms whose class lists carry no status dates have no first-day counts.
  coverage <- summary$students_status_dates
  undated <- if (is.null(coverage)) integer() else coverage$term[coverage$coverage == "none"]
  partial <- if (is.null(coverage)) integer() else coverage$term[coverage$coverage == "partial"]
  list(table = display, current_column = match(current_term, terms) + 2L,
       computed_at = summary$computed_at,
       undated_terms = vapply(undated, fmt_term, character(1)),
       partly_dated_terms = vapply(partial, fmt_term, character(1)))
}


# Short names for what each mapping-issue screen found, for the Problem column.
# The screens' own text is long and ends in advice for the old lists; it stays
# available as the column's hover text. identity_fallback_department has no
# label: the Today column already says "phantom".
ADMIN_PROBLEM_LABELS <- c(
  pre_major_self_mapped_department       = "pre-major mapped to itself",
  declared_majors_far_exceed_graduates   = "far more majors than graduates",
  identity_fallback_department           = NA
)

#' Every program awaiting a person's decision, for Admin > Mappings
#'
#' One row per program to decide: each `proposed` row of programs.csv, plus any
#' program a mapping issue names that has no row in the file at all. Each
#' carries the department CEDAR reports for it today -- from the files since
#' ADR-002 Stage 3, so NA ("none") until the row is confirmed and the tables
#' rebuilt; a phantom department named after the code only in tables built
#' before Stage 3 -- and the problem the issue screens found with it.
#'
#' Decisions are edits to the file in the repository, reviewed as a diff, never
#' to the app: the running container holds a copy of the source that the next
#' deploy replaces. Issues on a program already confirmed in the file are not
#' listed -- there is nothing left to decide -- but are counted, because they
#' persist in the stored tables until the next rebuild.
#'
#' @param files The list read_institution_mappings() returns.
#' @param programs cedar_programs.
#' @param issues build_admin_mapping_issues() output.
#' @param known_units Real unit codes (units.csv); any other "today" department
#'   is a phantom.
#' @return List: `queue`, a tibble (line_url, line, program_code, program_name,
#'   students, last_term, today, suggested_unit, basis, problem,
#'   problem_detail, evidence),
#'   most students first; and `n_decided_issues`, issues on confirmed programs.
build_program_mapping_queue <- function(files, programs, issues, known_units) {
  needed <- c("student_id", "term", "major_code", "program_type", "program_name", "dept_code")
  missing <- setdiff(needed, names(programs))
  if (length(missing)) {
    stop("[admin.R] build_program_mapping_queue: cedar_programs lacks ",
         paste(missing, collapse = ", "))
  }
  if (length(known_units) == 0) stop("[admin.R] build_program_mapping_queue: known_units is required")
  pr <- files$programs
  # Row i of the file is line i + 1; read_institution_file() guarantees it.
  # Its own line, not program_line_url(): a college-specific row is proposed
  # separately from its code's every-college row.
  pr$line <- seq_len(nrow(pr)) + 1L

  issues <- tibble::as_tibble(issues) %>%
    dplyr::mutate(code = dplyr::coalesce(major_code, program_code)) %>%
    dplyr::filter(!is.na(code))
  confirmed <- unique(pr$program_code[pr$status == "confirmed"])
  pending   <- pr[pr$status == "proposed", ]
  no_row    <- setdiff(issues$code, pr$program_code)
  codes     <- union(pending$program_code, no_row)

  held <- programs %>%
    dplyr::filter(!grepl("Concentration", program_type), major_code %in% codes)
  counts <- held %>% dplyr::group_by(major_code) %>%
    dplyr::summarize(students = dplyr::n_distinct(student_id), last_term = max(term),
                     data_name = names(sort(table(program_name), decreasing = TRUE))[1],
                     .groups = "drop")
  # The department most of the code's rows carry today.
  today <- held %>% dplyr::count(major_code, dept_code) %>%
    dplyr::group_by(major_code) %>% dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(major_code, today = dplyr::case_when(
      is.na(dept_code)                ~ "none",
      !dept_code %in% known_units     ~ paste(dept_code, "(phantom)"),
      TRUE                            ~ dept_code))
  # A student whose primary major is still undecided reports Banner's college,
  # labelled (ADR-002 Stage 3b): say so, so nobody mistakes it for a decision.
  # Tables built before Stage 3b have no college_basis and nothing to add.
  if ("college_basis" %in% names(held)) {
    banner <- held %>% dplyr::filter(college_basis %in% "banner", !is.na(college_code)) %>%
      dplyr::count(major_code, college_code) %>%
      dplyr::group_by(major_code) %>% dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
      dplyr::ungroup() %>% dplyr::select(major_code, banner_college = college_code)
    today <- today %>% dplyr::left_join(banner, by = "major_code") %>%
      dplyr::mutate(today = dplyr::if_else(is.na(banner_college), today,
                                           paste0(today, "; college ", banner_college, " from Banner"))) %>%
      dplyr::select(-banner_college)
  }
  unknown <- setdiff(issues$issue_type, names(ADMIN_PROBLEM_LABELS))
  if (length(unknown)) {
    stop("[admin.R] No Problem label for issue type(s): ", paste(unknown, collapse = ", "),
         ". Add them to ADMIN_PROBLEM_LABELS.")
  }
  problems <- issues %>% dplyr::filter(code %in% codes) %>%
    dplyr::mutate(label = dplyr::if_else(
      issue_type == "unmapped_program_code" & review_status == "reviewed_exception",
      "reviewed exception: no owner yet", unname(ADMIN_PROBLEM_LABELS[issue_type]))) %>%
    dplyr::group_by(code) %>%
    dplyr::summarize(
      problem = paste(unique(stats::na.omit(label)), collapse = "; "),
      problem_detail = paste(unique(details), collapse = "\n\n"), .groups = "drop") %>%
    dplyr::mutate(problem = dplyr::na_if(problem, ""))

  from_file <- tibble::tibble(
    program_code = pending$program_code, program_name = pending$program_name,
    suggested_unit = pending$unit_code, basis = pending$basis,
    evidence = pending$evidence, line = pending$line,
    line_url = mapping_file_url(files, "programs", pending$line))
  # A code with no row is named by the Banner program codes the issue came
  # from: the old parser can read a code out of the wrong part ("FPMD-UC" gave
  # major code "UC"), and the full code shows what the row really is.
  banner_codes <- issues %>% dplyr::filter(code %in% no_row) %>%
    dplyr::group_by(code) %>%
    dplyr::summarize(banner = paste(sort(unique(stats::na.omit(program_code))), collapse = ", "),
                     .groups = "drop")
  missing_rows <- tibble::tibble(
    program_code = no_row, suggested_unit = "",
    basis = "no row in programs.csv", evidence = "", line = NA_integer_,
    line_url = NA_character_) %>%
    dplyr::left_join(banner_codes, by = c("program_code" = "code")) %>%
    dplyr::mutate(program_name = dplyr::if_else(nzchar(banner),
                                                 paste("Banner program", banner), NA_character_)) %>%
    dplyr::select(-banner)

  queue <- dplyr::bind_rows(from_file, missing_rows) %>%
    dplyr::left_join(counts, by = c("program_code" = "major_code")) %>%
    dplyr::left_join(today, by = c("program_code" = "major_code")) %>%
    dplyr::left_join(problems, by = c("program_code" = "code")) %>%
    dplyr::mutate(
      program_name = dplyr::coalesce(program_name, data_name),
      # A code in the file but not in cedar_programs (degrees only) holds no
      # program-table students: zero is measured, not missing.
      students = dplyr::coalesce(students, 0L),
      today = dplyr::coalesce(today, "none")) %>%
    dplyr::arrange(dplyr::desc(students), program_code) %>%
    dplyr::select(line_url, line, program_code, program_name, students, last_term, today,
                  suggested_unit, basis, problem, problem_detail, evidence)

  list(queue = queue,
       n_decided_issues = sum(issues$code %in% confirmed & !issues$code %in% codes))
}


#' Every mapping issue the Admin > Mappings panel shows
#'
#' Startup exclusions from cedar_mapping_issues, plus the runtime screens that
#' find what a clean program_map cannot: a program whose dept_code fell back to
#' its own major code is "mapped" as far as the map knows, and names a
#' department that does not exist.
#'
#' A screen that fails must fail loudly. This used to sit in server.R inside a
#' tryCatch that returned only the startup rows on error, so a broken screen
#' read as "no mapping issues" -- the page meant to catch silent failures
#' would itself have failed silently.
#'
#' @param startup cedar_mapping_issues, or NULL/empty.
#' @param programs cedar_programs, or NULL/empty when not loaded.
#' @param known_departments Real department codes, normally
#'   `subj_dept_map$dept_code`. Never `dept_name_lookup`: it lists self-named
#'   codes as departments, so the screen would pass them.
#' @return Data frame in the cedar_mapping_issues shape.
build_admin_mapping_issues <- function(startup, programs, known_departments) {
  startup <- if (is.null(startup) || nrow(startup) == 0) {
    as.data.frame(.anomaly_frame(), stringsAsFactors = FALSE)
  } else {
    as.data.frame(startup, stringsAsFactors = FALSE)
  }
  if (is.null(programs) || nrow(programs) == 0) return(startup)
  if (length(known_departments) == 0) {
    stop("[admin.R] known_departments is required to screen for identity-fallback departments.")
  }

  detected <- dplyr::bind_rows(
    detect_pre_major_self_mapping(programs, known_departments),
    detect_identity_fallback_departments(programs, known_departments)
  )
  dplyr::bind_rows(startup, as.data.frame(detected, stringsAsFactors = FALSE))
}



#' The mapping work list for Admin > Mappings and scripts/mapping-review.R
#'
#' Two lists, by the kind of work. `decisions`: everything settled by editing a
#' mapping file -- programs and subjects awaiting a decision, codes the data
#' uses with no row, college values no file names, units with no college, and
#' mapped colleges Banner disagrees with. `other`: problems no mapping can fix,
#' such as Banner organisation IDs leaking into the major-code column, and codes
#' only the old program_map checks report. Expected differences (pre-majors
#' reporting under the college they lead to) are not work; they are counted.
#'
#' @param files The list read_institution_mappings() returns.
#' @param programs cedar_programs.
#' @param issues build_admin_mapping_issues() output.
#' @param audit audit_mapping_coverage() output.
#' @param source_departments source_departments.csv: which source departments
#'   are catch-all "bucket" departments, whose programs' course-taking says
#'   little about an owner.
#' @return List: `decisions` (needs, file, line, kind, code, name, size,
#'   size_unit, reported_today, reported_detail, suggested, suggested_name,
#'   confidence, evidence), `other` (kind, code, context, size, needs),
#'   `n_expected`.
build_mapping_worklist <- function(files, programs, issues, audit, source_departments) {
  queue <- build_program_mapping_queue(files, programs, issues,
                                       known_units = files$units$unit_code)$queue
  from_file <- queue %>% dplyr::filter(!is.na(line))
  pr_row <- files$programs[from_file$line - 1L, ]
  unit_name <- function(code) files$units$unit_name[match(code, files$units$unit_code)]
  programs_part <- tibble::tibble(
    group = "programs",
    needs = dplyr::if_else(nzchar(from_file$suggested_unit),
                           paste0("Confirm the suggested department, ", from_file$suggested_unit, ", or replace it"),
                           "A department: nothing settled it"),
    file = "programs", line = from_file$line,
    kind = .program_kind(from_file$program_code, pr_row$is_pre_major, programs),
    code = from_file$program_code, name = from_file$program_name,
    size = from_file$students, size_unit = "students",
    reported_today = from_file$today, reported_detail = from_file$problem_detail,
    suggested = from_file$suggested_unit,
    suggested_name = unit_name(dplyr::na_if(from_file$suggested_unit, "")),
    confidence = .suggestion_confidence(from_file$basis, from_file$evidence,
                                        from_file$suggested_unit, source_departments),
    evidence = paste0(from_file$basis, ": ", from_file$evidence))

  org_id <- audit$kind == "program_code" & grepl("organisation ID", audit$context)
  work <- audit[audit$status != "expected" & !org_id, ]
  kind_label <- c(subject = "Course subject", section_college = "Section college",
                  program_code = "Program code", source_college = "College name",
                  college_disagreement = "College check", unit_college = "Unit college")
  sj <- files$subjects
  proposed_row <- ifelse(work$kind == "subject" & !is.na(work$line), work$line - 1L, NA_integer_)
  # A subject's context is "college AD" or "college AS, EH", plus a note.
  taught_codes <- sub("^college ([^;]+).*$", "\\1", work$context)
  # Sections carry the college code Banner used that term, so translate it as
  # the transform does: ED, Education before 2021, is named as EH.
  college_label <- function(codes) {
    vapply(strsplit(codes, ", ", fixed = TRUE), function(cc) {
      code <- dplyr::coalesce(translate_source_college(cc, files), cc)
      nm <- files$colleges$college_name[match(code, files$colleges$college_code)]
      paste(ifelse(is.na(nm), cc, paste0(cc, " (", nm, ")")), collapse = ", ")
    }, character(1))
  }
  disagreement <- "^mapped (\\S+), Banner Translated College (.+)$"
  audit_part <- tibble::tibble(
    group = dplyr::case_when(
      work$kind == "subject" ~ "subjects",
      work$kind %in% c("program_code", "college_disagreement") ~ "programs",
      TRUE ~ "colleges"),
    needs = work$needs, file = work$file, line = work$line,
    kind = unname(kind_label[work$kind]), code = work$value,
    # Name is the code's own name, or nothing: a program's from programs.csv
    # (else the name its records most often carry), a unit's from units.csv. A
    # course subject has none, and a college value no file names has none yet.
    name = dplyr::case_when(
      work$kind == "college_disagreement" ~
        files$programs$program_name[match(work$value, files$programs$program_code)],
      work$kind == "program_code" ~ .program_data_names(work$value, programs),
      work$kind == "unit_college" ~ unit_name(work$value),
      TRUE ~ NA_character_),
    taught_in = dplyr::if_else(work$kind == "subject", college_label(taught_codes), NA_character_),
    size = work$rows,
    size_unit = dplyr::if_else(work$kind == "subject", "enrollments", "rows"),
    # A subject with no confirmed row has no department (ADR-002 Stage 3), and
    # reports the college Banner gives its sections, labelled (Stage 3b). A
    # college check reports the mapped college, which Banner's differs from.
    reported_today = dplyr::case_when(
      work$kind == "subject" ~ paste0("none; college ", taught_codes, " from Banner"),
      work$kind == "college_disagreement" ~ sub(disagreement, "college \\1; Banner: \\2", work$context),
      TRUE ~ NA_character_),
    reported_detail = NA_character_,
    # Where the audit found it, for rows the name and kind do not place.
    detail = dplyr::if_else(work$kind %in% c("subject", "college_disagreement"),
                            NA_character_, work$context),
    suggested = dplyr::case_when(
      !is.na(proposed_row) ~ dplyr::na_if(sj$unit_code[proposed_row], ""),
      work$kind == "college_disagreement" ~ sub("^mapped (\\S+),.*$", "\\1", work$context),
      TRUE ~ NA_character_),
    evidence = dplyr::if_else(!is.na(proposed_row), sj$evidence[proposed_row], work$consequence)) %>%
    dplyr::mutate(
      suggested_name = dplyr::if_else(
        kind == "College check",
        files$colleges$college_name[match(suggested, files$colleges$college_code)],
        unit_name(suggested)),
      # A subject's suggestion comes only from the source's own department for
      # its courses; a college check is a decision by nature.
      confidence = dplyr::case_when(
        kind == "College check" ~ "Review: mapped college differs from Banner's",
        kind == "Course subject" & !is.na(suggested) ~ "Strong: the source's own department for its courses",
        kind == "Course subject" ~ "None: the source names no single department",
        TRUE ~ NA_character_))

  # A code with no programs.csv row is a decision the audit lists itself
  # ("A programs.csv row"); the old program_map checks that also reported such
  # codes were retired at ADR-002 Stage 4.
  other <- tibble::tibble(kind = "Program code", code = audit$value[org_id],
                          context = audit$context[org_id], size = audit$rows[org_id],
                          needs = audit$needs[org_id])

  # No names on any column: a named vector reaches the browser as a JSON object,
  # not an array, and the table built from it renders nothing, silently.
  plain <- function(df) dplyr::mutate(df, dplyr::across(dplyr::everything(), unname))
  list(decisions = dplyr::bind_rows(programs_part, audit_part) %>%
         dplyr::arrange(dplyr::desc(dplyr::coalesce(size, 0L))) %>% plain(),
       other = plain(other),
       n_expected = sum(audit$status == "expected"))
}


# The name a program code's records most often carry, for codes with no
# programs.csv row to name them; NA for a code with no program rows.
.program_data_names <- function(codes, programs) {
  named <- programs %>%
    dplyr::filter(major_code %in% codes, !grepl("Concentration", program_type),
                  !is.na(program_name)) %>%
    dplyr::count(major_code, program_name) %>%
    dplyr::group_by(major_code) %>% dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup()
  named$program_name[match(codes, named$major_code)]
}


#' The mapping files as three code-to-department tables, with names
#'
#' What Admin > Mappings shows beneath the decisions: every confirmed program
#' row and every confirmed subject row with the department (unit) it names,
#' and every unit with its college. Read from the files, so each code carries
#' its name -- a program its programs.csv name, a department its units.csv
#' name. A course subject has no name. A row that applies only in one college
#' (a branch campus's BADM) or at one level says so; a program no department
#' owns (`basis = no_unit`) is listed with none.
#'
#' @param files Mapping files from read_institution_mappings().
#' @return List of `programs`, `subjects`, `units` and `colleges` data frames.
build_mapping_reference_tables <- function(files) {
  unit_name <- function(code) files$units$unit_name[match(code, files$units$unit_code)]
  college_label <- function(code) {
    nm <- files$colleges$college_name[match(code, files$colleges$college_code)]
    dplyr::case_when(!nzchar(code) ~ NA_character_,
                     is.na(nm)     ~ code,
                     TRUE          ~ paste0(code, " (", nm, ")"))
  }
  pr <- files$programs[files$programs$status == "confirmed", ]
  sj <- files$subjects[files$subjects$status == "confirmed", ]
  un <- files$units
  plain <- function(df) dplyr::mutate(df, dplyr::across(dplyr::everything(), unname))
  list(
    programs = tibble::tibble(
      program_code = pr$program_code, program_name = pr$program_name,
      in_college = college_label(pr$in_college),
      dept_code = dplyr::na_if(pr$unit_code, ""),
      dept_name = dplyr::if_else(nzchar(pr$unit_code), unit_name(pr$unit_code),
                                 "None: no department owns it")) %>%
      dplyr::arrange(program_code, !is.na(in_college), in_college) %>% plain(),
    subjects = tibble::tibble(
      subject_code = sj$subject_code, in_college = college_label(sj$in_college),
      in_level = dplyr::na_if(sj$in_level, ""),
      dept_code = sj$unit_code, dept_name = unit_name(sj$unit_code)) %>%
      dplyr::arrange(subject_code, !is.na(in_college), in_college, in_level) %>% plain(),
    units = tibble::tibble(
      dept_code = un$unit_code, dept_name = un$unit_name,
      college = college_label(un$college_code), kind = un$kind) %>%
      dplyr::arrange(dept_code) %>% plain(),
    # Each college with the other values sources use for it (source_names),
    # which the transform translates to its code: ED is EH.
    colleges = tibble::tibble(
      college_code = files$colleges$college_code, college_name = files$colleges$college_name,
      also_matches = dplyr::na_if(gsub("|", ", ", files$colleges$source_names, fixed = TRUE), ""),
      depts = as.integer(table(factor(un$college_code, levels = files$colleges$college_code)))) %>%
      dplyr::arrange(college_code) %>% plain())
}


#' The counting rules CEDAR applies without a mapping-file row
#'
#' Admin > Mappings lists every decision the files hold. These are the rules
#' that place or drop rows without one: a concentration's department, a
#' pre-major read off its name, Banner's college for an undecided code, course
#' level, the crosslist home, the excluded-course list, students with no
#' program record, the two vocabularies for a home campus, and the hand-kept
#' name lists. Each says what CEDAR does, how many rows it touches in the
#' loaded tables, and where it is coded, so a count can be traced past the
#' files to the rule that placed it.
#'
#' @param files Mapping files from read_institution_mappings().
#' @param programs,sections,students cedar_programs, cedar_sections,
#'   cedar_students as loaded.
#' @return A tibble: rule, what, affects, coded_in.
build_counting_rules <- function(files, programs, sections, students) {
  need <- function(df, cols, what) {
    missing <- setdiff(cols, names(df))
    if (length(missing)) stop("[admin.R] build_counting_rules: ", what, " lacks ",
                              paste(missing, collapse = ", "))
  }
  need(programs, c("student_id", "term", "program_type", "program_name", "major_code", "dept_code",
                   "is_pre_major", "pre_major_basis", "college_basis", "student_campus"),
       "cedar_programs")
  need(sections, c("term", "campus", "subject", "subject_course", "level", "department",
                   "college_basis", "crosslist_group", "crosslist_role"), "cedar_sections")
  need(students, c("student_id", "term", "student_campus", "college_basis"), "cedar_students")
  n <- function(x) format(x, big.mark = ",")
  pct <- function(a, b) if (b == 0) "—" else sprintf("%.1f%%", 100 * a / b)
  some <- function(codes, k = 6) {
    codes <- sort(unique(codes))
    if (length(codes) > k) paste0(paste(head(codes, k), collapse = ", "), ", ...") else
      paste(codes, collapse = ", ")
  }

  conc <- programs[grepl("Concentration", programs$program_type), ]
  by_name <- programs[programs$pre_major_basis %in% "name_prefix" & programs$is_pre_major %in% TRUE, ]
  phrd <- programs[programs$pre_major_basis %in% "phrd_undergraduate", ]
  banner_pr <- programs[programs$college_basis %in% "banner", ]
  banner_sec <- sections[sections$college_basis %in% "banner", ]
  levels <- table(factor(sections$level, levels = c("lower", "upper", "grad")))
  xl <- sections[!is.na(sections$crosslist_group), ]
  xl_groups <- xl %>% dplyr::distinct(term, campus, crosslist_group, department) %>%
    dplyr::count(term, campus, crosslist_group, name = "n_depts")
  partners <- sum(!xl$crosslist_role %in% c("home", "internal"))
  excluded <- sections[sections$subject_course %in% excluded_courses, ]

  # Student-terms in the class lists with no program record (ISSUES.md I20).
  st <- students %>% dplyr::distinct(student_id, term, student_campus)
  has_program <- paste(st$student_id, st$term) %in%
    unique(paste(programs$student_id, programs$term))
  branch <- st$student_campus %in% CEDAR_CAMPUS_BRANCH
  main <- st$student_campus %in% CEDAR_CAMPUS_MAIN

  tibble::tibble(
    rule = c("Concentrations", "Pre-majors by name", "PHRD", "Banner's college",
             "Course level", "Cross-listed courses", "Excluded courses",
             "Students with no program record", "Home campus", "HR departments",
             "Program names to codes"),
    what = c(
      "A concentration has no code in Banner's report, so it counts with the department of the student's primary major that term.",
      "A program code with no programs.csv row is a pre-major when Banner's name for it begins \"Pre-\", and is stored without the \"Pre-\". A row in programs.csv states the flag instead. A concentration is never a pre-major and keeps its name (ISSUES.md I21); tables built before that fix still show concentrations here.",
      "PHRD was undergraduate pre-pharmacy before Fall 2025; undergraduate PHRD rows are pre-majors whatever programs.csv says.",
      "A code with no confirmed row has no department, and reports the college Banner gives it, labelled college_basis = \"banner\".",
      sprintf("A course's level is read from the first digit of its number: %s. subjects.csv rows with in_level apply at one level only.",
              paste(sprintf("%s %s", names(COURSE_LEVEL_BY_LEADING_DIGIT), COURSE_LEVEL_BY_LEADING_DIGIT),
                    collapse = ", ")),
      "Every section in a cross-list group carries the group's combined enrollment, so a course counts once, under its home section's department (keep_home_sections()). The transform picks the home section, falling back to enrollment where Banner names none.",
      "Thesis, dissertation, honors-credit and similar courses are left out wherever a computation applies the excluded list (opt$uel = TRUE): department enrollment trends and reviews, Regstats waitlists and saturation, Open Seats; optional on the Enrollment tab.",
      "Class lists cover every campus; program records (Academic Studies) mostly cover Albuquerque. A student-term with no program record counts in course enrollment but in no department's or college's headcount.",
      "Program records name a student's home campus (\"Albuquerque/Main\"); class lists code it (\"ABQ\"). No file maps one to the other: headcounts filter on the names, course figures on the codes.",
      "Faculty get a department from the HR report's organisation name through a hand-kept list. HR organisations not on it are dropped when the report is parsed.",
      "Older exports with a program name but no code get the code from a hand-kept list of names."),
    affects = c(
      sprintf("%s concentration rows; %s count toward no department because the primary major is undecided.",
              n(nrow(conc)), n(sum(is.na(conc$dept_code)))),
      if (nrow(by_name)) {
        by_name_conc <- grepl("Concentration", by_name$program_type)
        conc_text <- sprintf("%s concentration rows (%s)", n(sum(by_name_conc)),
                             some(by_name$program_name[by_name_conc]))
        coded_text <- sprintf("%s rows under %s codes (%s)", n(sum(!by_name_conc)),
                              n(dplyr::n_distinct(stats::na.omit(by_name$major_code[!by_name_conc]))),
                              some(by_name$major_code[!by_name_conc]))
        if (all(by_name_conc)) {
          sprintf("%s rows, all concentrations (%s); no coded program takes this fallback.",
                  n(nrow(by_name)), some(by_name$program_name))
        } else if (!any(by_name_conc)) {
          paste0(coded_text, ".")
        } else sprintf("%s rows: %s; %s.", n(nrow(by_name)), conc_text, coded_text)
      } else "None in the loaded data.",
      sprintf("%s rows.", n(nrow(phrd))),
      sprintf("%s program rows (%s codes: %s); %s sections (subjects %s); %s class-list rows.",
              n(nrow(banner_pr)), n(dplyr::n_distinct(stats::na.omit(banner_pr$major_code))), some(banner_pr$major_code),
              n(nrow(banner_sec)), some(banner_sec$subject), n(sum(students$college_basis %in% "banner"))),
      sprintf("Sections: %s lower, %s upper, %s grad. %s subjects.csv rows keyed on level.",
              n(levels[["lower"]]), n(levels[["upper"]]), n(levels[["grad"]]),
              n(sum(nzchar(files$subjects$in_level)))),
      sprintf("%s cross-list groups; %s span more than one department, so the home section decides which counts them. %s partner sections are left out of course counts. How many homes came from the enrollment fallback is not recorded.",
              n(nrow(xl_groups)), n(sum(xl_groups$n_depts > 1)), n(partners)),
      sprintf("%s courses on the list; %s sections in the loaded data.",
              n(length(excluded_courses)), n(nrow(excluded))),
      sprintf("%s of %s student-terms (%s): %s at Albuquerque, %s at the branch campuses (ISSUES.md I20).",
              n(sum(!has_program)), n(nrow(st)), pct(sum(!has_program), nrow(st)),
              pct(sum(!has_program & main), sum(main)), pct(sum(!has_program & branch), sum(branch))),
      sprintf("%s home-campus names in program records; %s campus codes in class lists.",
              n(dplyr::n_distinct(stats::na.omit(programs$student_campus))),
              n(dplyr::n_distinct(stats::na.omit(students$student_campus)))),
      sprintf("%s organisation names to %s departments.", n(length(hr_org_desc_to_dept)),
              n(dplyr::n_distinct(hr_org_desc_to_dept))),
      sprintf("%s names.", n(length(major_name_to_major_code)))),
    coded_in = c(
      "transform_programs(), R/data-parsers/transform-to-cedar.R",
      "transform_programs(), R/data-parsers/transform-to-cedar.R",
      "transform_programs(); CEDAR_DATA_SEMANTICS (R/lists/data_semantics.R)",
      "add_program_colleges() and .course_colleges(), R/data-parsers/transform-to-cedar.R",
      "institution/<id>/course_levels.csv (COURSE_LEVEL_BY_LEADING_DIGIT, R/lists/course_numbering.R)",
      "keep_home_sections(), R/trunk/filter.R; transform_sections()",
      "institution/<id>/excluded_courses.csv (excluded_courses, R/lists/excluded_courses.R)",
      "the source exports (mrgather); ISSUES.md I18, I20",
      "institution/<id>/campuses.csv (R/lists/campuses.R)",
      "institution/<id>/source_organizations.csv (hr_org_desc_to_dept, R/lists/mappings.R); R/data-parsers/parse-HRreport.R",
      "institution/<id>/program_names.csv (major_name_to_major_code, R/lists/mappings.R)"))
}

#' Every campus code: its label, group, and where it is counted
#'
#' The codes the institution's campuses.csv defines, plus any code the loaded data uses
#' that it does not, so an unexplained code is visible rather than silently
#' grouped. Sections and enrollments count where a course was taught
#' (`campus`); home-campus rows count the student's home campus as class lists
#' code it.
#'
#' @param sections,students cedar_sections and cedar_students as loaded.
#' @return A tibble: campus, label, group, default_scope, sections,
#'   enrollments_taught, enrollments_home.
build_campus_reference <- function(sections, students) {
  if (!"campus" %in% names(sections)) stop("[admin.R] build_campus_reference: cedar_sections lacks campus")
  if (!all(c("campus", "student_campus") %in% names(students))) {
    stop("[admin.R] build_campus_reference: cedar_students lacks campus or student_campus")
  }
  known <- c(CEDAR_CAMPUS_MAIN, CEDAR_CAMPUS_ONLINE, CEDAR_CAMPUS_BRANCH)
  seen <- unique(stats::na.omit(c(sections$campus, students$campus, students$student_campus)))
  codes <- c(known, sort(setdiff(seen[nzchar(seen)], known)))
  count_in <- function(x) as.integer(table(factor(x, levels = codes)))
  tibble::tibble(
    campus = codes,
    label = unname(CEDAR_CAMPUS_LABELS[codes]),
    group = dplyr::case_when(codes %in% CEDAR_CAMPUS_MAIN ~ "Main",
                             codes %in% CEDAR_CAMPUS_ONLINE ~ "Online",
                             codes %in% CEDAR_CAMPUS_BRANCH ~ "Branch",
                             TRUE ~ "Not in campuses.csv"),
    default_scope = codes %in% CEDAR_CAMPUS_DEFAULT,
    sections = count_in(sections$campus),
    enrollments_taught = count_in(students$campus),
    enrollments_home = count_in(students$student_campus))
}


# What kind of program a code is, from its rows: a major, a minor, or both;
# pre-majors as programs.csv states them.
.program_kind <- function(codes, is_pre_major, programs) {
  rows <- programs %>% dplyr::filter(major_code %in% codes, !grepl("Concentration", program_type))
  has <- function(pattern) codes %in% rows$major_code[grepl(pattern, rows$program_type)]
  major <- has("Major"); minor <- has("Minor")
  dplyr::case_when(
    is_pre_major == "TRUE" ~ "Program (pre-major)",
    major & minor          ~ "Program (major and minor)",
    major                  ~ "Program (major)",
    minor                  ~ "Program (minor)",
    TRUE                   ~ "Program")
}

# How much to trust the mapping assistant's suggestion, in words, from the
# evidence it recorded. Strong: the source's own department, matching names, a
# matching subject code, or a pre-major's target. Course-taking alone is
# Plausible when clear -- students take the department's courses at 5x the
# overall rate or more, over 100 or more enrolments -- and Weak otherwise, or
# when the program sits in a catch-all ("bucket") source department, whose
# students' courses say little about an owner.
.suggestion_confidence <- function(basis, evidence, suggested, source_departments) {
  lift <- suppressWarnings(as.numeric(sub(".*at ([0-9.]+)x the overall rate.*", "\\1", evidence)))
  enrolments <- suppressWarnings(as.integer(sub(".*the overall rate \\(([0-9]+) enrolments\\).*", "\\1", evidence)))
  source_dept <- ifelse(grepl('source department "', evidence),
                        sub('.*source department "([^"]+)".*', "\\1", evidence), NA_character_)
  bucket <- source_dept %in% source_departments$source_name[source_departments$kind == "bucket"]
  clear <- !is.na(lift) & lift >= 5 & !is.na(enrolments) & enrolments >= 100
  dplyr::case_when(
    is.na(suggested) | !nzchar(suggested) ~ "None: no evidence settled it",
    basis == "source_department" ~ "Strong: the source's own department",
    basis == "name_match"        ~ "Strong: the names match",
    basis == "subject_code"      ~ "Strong: a course subject with the same code",
    basis == "inherited"         ~ "Strong: the program it leads to",
    basis == "course_taking" & bucket ~
      "Weak: course-taking only, in a catch-all source department",
    basis == "course_taking" & clear ~ sprintf(
      "Plausible: students take its courses at %.1fx the usual rate", lift),
    basis == "course_taking" ~ "Weak: course-taking only, and not clear-cut",
    TRUE ~ paste0("Unrated: ", basis))
}
