# Cones: Gen Ed Conversion
#
# Tracks students who took gen ed courses in a given subject and maps
# where they ended up: the major on their last recorded program entry,
# whether they stopped out or graduated.
#
# Source (left) nodes: the student's declared program at the time they
#   took the gen ed course (pre-majors and declared majors shown separately).
# Target (right) nodes: their last recorded program in cedar_programs.
#
# Students with no program record at the time of the gen ed course are
# labelled "Undeclared". Students whose major never changed appear as a
# self-loop (source == target) which plotly Sankey drops automatically.
#
# Flows below opt$min_n students are collapsed into "Other [Pre-Major]"
# or "Other Major" within each side independently.
#
# Depends on:
#   lists/status_codes.R  — STATUS_REGISTERED
#
# Exported:
#   get_gen_ed_conversion(students, programs, opt)


get_gen_ed_conversion <- function(students, programs, opt = list()) {
  subject_code     <- opt[["subject_code"]] %||% ""
  gen_ed_only      <- isTRUE(opt[["gen_ed_only"]] %||% TRUE)
  gen_ed_courses   <- opt[["gen_ed_courses"]]   # character vector of subject_course codes
  terms            <- opt[["terms"]]             # integer vector; NULL = all except current
  min_n            <- as.integer(opt[["min_n"]] %||% 5L)
  top_n            <- as.integer(opt[["top_n"]] %||% 10L)

  if (!nzchar(subject_code)) {
    stop("[gen-ed-conversion.R] opt$subject_code is required.")
  }

  message("[gen-ed-conversion.R] subject=", subject_code,
          " gen_ed_only=", gen_ed_only,
          " min_n=", min_n,
          " terms=", if (is.null(terms)) "all" else paste(range(terms), collapse = "-"))

  campus <- opt[["campus"]]  # character vector; NULL = all campuses

  # ── Step 1: qualifying gen ed enrollments ─────────────────────────────────
  exposures <- students %>%
    filter(
      registration_status_code %in% STATUS_REGISTERED,
      subject_code == .env$subject_code
    )

  if (!is.null(campus) && length(campus) > 0)
    exposures <- exposures %>% filter(campus %in% .env$campus)

  if (gen_ed_only && length(gen_ed_courses) > 0) {
    exposures <- exposures %>% filter(subject_course %in% gen_ed_courses)
  }

  if (!is.null(terms) && length(terms) > 0) {
    exposures <- exposures %>% filter(term %in% as.integer(terms))
  }

  # One record per student: earliest qualifying term
  exposures <- exposures %>%
    distinct(student_id, term) %>%
    group_by(student_id) %>%
    slice_min(term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    rename(exposure_term = term)

  if (nrow(exposures) == 0) {
    message("[gen-ed-conversion.R] No qualifying students found.")
    return(NULL)
  }

  message("[gen-ed-conversion.R] ", nrow(exposures), " qualifying students")

  # ── Step 2: major at time of gen ed exposure ───────────────────────────────
  # Use the student's most recent program record at or before the exposure term.
  # Filter to primary Major type first; fall back to any program type if needed.
  major_at_exposure <- programs %>%
    filter(program_type == "Major") %>%
    select(student_id, term, program_name, major_code, is_pre_major, dept_code) %>%
    inner_join(exposures, by = "student_id") %>%
    filter(term <= exposure_term) %>%
    group_by(student_id) %>%
    slice_max(term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(student_id, exposure_term,
           source_name = program_name,
           source_code = major_code,
           source_is_pre = is_pre_major)

  # Join back — students with no prior program record are Undeclared
  cohort <- exposures %>%
    left_join(major_at_exposure, by = c("student_id", "exposure_term")) %>%
    mutate(
      source_name  = if_else(is.na(source_name),  "Undeclared", source_name),
      source_code  = if_else(is.na(source_code),  "UNDECL",     source_code),
      source_is_pre = if_else(is.na(source_is_pre), FALSE,       source_is_pre)
    )

  # ── Step 3: last recorded major ───────────────────────────────────────────
  last_major <- programs %>%
    filter(program_type == "Major") %>%
    select(student_id, term, program_name, major_code, is_pre_major) %>%
    group_by(student_id) %>%
    slice_max(term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(student_id,
           target_name = program_name,
           target_code = major_code,
           target_is_pre = is_pre_major)

  cohort <- cohort %>%
    left_join(last_major, by = "student_id") %>%
    mutate(
      target_name   = if_else(is.na(target_name),  "Undeclared", target_name),
      target_code   = if_else(is.na(target_code),  "UNDECL",     target_code),
      target_is_pre = if_else(is.na(target_is_pre), FALSE,        target_is_pre)
    )

  # ── Step 4: build node labels ─────────────────────────────────────────────
  # Pre-majors prefixed with "[Pre]" so they read distinctly on the diagram.
  cohort <- cohort %>%
    mutate(
      source_label = if_else(source_is_pre,
        paste0("[Pre] ", source_name), source_name),
      target_label = if_else(target_is_pre,
        paste0("[Pre] ", target_name), target_name)
    )

  # ── Step 4b: capture excluded-student counts before filtering ────────────
  # Students whose last recorded major is Undeclared are excluded from the
  # diagram (they never completed a declared program and don't represent a
  # meaningful conversion destination).
  n_undeclared_end <- sum(cohort$target_label == "Undeclared")
  n_never_declared <- sum(cohort$source_label == "Undeclared" &
                            cohort$target_label == "Undeclared")

  # ── Step 5: count flows and collapse small nodes ───────────────────────────
  # Drop target = "Undeclared": students who never declared any final major
  # (dropped out, non-degree-seeking, etc.) don't represent a meaningful
  # conversion destination and can dominate the Undeclared source node visually.
  flows <- cohort %>%
    count(source_label, source_is_pre, target_label, target_is_pre, name = "n") %>%
    filter(target_label != "Undeclared")

  if (nrow(flows) == 0) {
    message("[gen-ed-conversion.R] No cross-major flows found.")
    return(NULL)
  }

  collapse_small <- function(flows, side_col, is_pre_col, min_n) {
    totals <- flows %>%
      group_by(across(all_of(c(side_col, is_pre_col)))) %>%
      summarise(total = sum(n), .groups = "drop")

    small_pre   <- totals %>% filter(.data[[is_pre_col]],  total < min_n) %>% pull(.data[[side_col]])
    small_major <- totals %>% filter(!.data[[is_pre_col]], total < min_n) %>% pull(.data[[side_col]])

    flows %>%
      mutate(!!side_col := case_when(
        .data[[side_col]] %in% small_pre   ~ "Other [Pre-Major]",
        .data[[side_col]] %in% small_major ~ "Other Major",
        TRUE                               ~ .data[[side_col]]
      )) %>%
      group_by(across(all_of(c("source_label", "source_is_pre",
                                "target_label", "target_is_pre")))) %>%
      summarise(n = sum(n), .groups = "drop")
  }

  flows <- collapse_small(flows, "source_label", "source_is_pre", min_n)
  flows <- collapse_small(flows, "target_label", "target_is_pre", min_n)

  # Apply min_n at the link level so thin individual flows don't clutter the diagram.
  flows <- flows %>%
    filter(n >= min_n)

  if (nrow(flows) == 0) {
    message("[gen-ed-conversion.R] No flows remain after min_n filtering.")
    return(NULL)
  }

  # ── Step 5b: cap visible nodes at top_n per side ────────────────────────────
  # Keep the top_n nodes by total flow on each side; collapse the rest into
  # "Other" / "Other [Pre-Major]" with a hover label listing the collapsed names.
  collapse_to_top_n <- function(flows, side_col, is_pre_col, top_n) {
    totals <- flows %>%
      group_by(across(all_of(c(side_col, is_pre_col)))) %>%
      summarise(total = sum(n), .groups = "drop")

    # Never collapse existing "Other" aggregates — they stay as-is
    real <- totals %>% filter(!grepl("^Other", .data[[side_col]]))
    already_other <- totals %>% filter(grepl("^Other", .data[[side_col]]))

    if (nrow(real) <= top_n) return(flows)  # nothing to collapse

    keep <- real %>% arrange(desc(total)) %>% slice_head(n = top_n)
    drop <- real %>% anti_join(keep, by = c(side_col, is_pre_col))

    # Build hover detail showing collapsed program names + counts
    drop_pre   <- drop %>% filter(.data[[is_pre_col]])
    drop_major <- drop %>% filter(!.data[[is_pre_col]])
    .hover_list <- function(df, side) {
      if (nrow(df) == 0) return(NULL)
      items <- df %>% arrange(desc(total))
      paste(items[[side]], items$total, sep = ": ", collapse = "; ")
    }
    other_pre_hover   <- .hover_list(drop_pre,   side_col)
    other_major_hover <- .hover_list(drop_major, side_col)

    keep_labels <- keep[[side_col]]
    other_labels <- c(if (!is.null(already_other) && nrow(already_other) > 0)
                        already_other[[side_col]] else character(0))

    flows <- flows %>%
      mutate(!!side_col := if_else(
        .data[[side_col]] %in% keep_labels | .data[[side_col]] %in% other_labels,
        .data[[side_col]],
        if_else(.data[[is_pre_col]], "Other [Pre-Major]", "Other Major")
      )) %>%
      group_by(across(all_of(c("source_label", "source_is_pre",
                                "target_label", "target_is_pre")))) %>%
      summarise(n = sum(n), .groups = "drop")

    # Attach hover detail as attributes so the node-building step can use them
    attr(flows, paste0(side_col, "_other_pre_hover"))   <- other_pre_hover
    attr(flows, paste0(side_col, "_other_major_hover")) <- other_major_hover
    flows
  }

  flows <- collapse_to_top_n(flows, "source_label", "source_is_pre", top_n)
  flows <- collapse_to_top_n(flows, "target_label", "target_is_pre", top_n)

  # ── Step 6: build plotly Sankey node/link tables ───────────────────────────
  # Source nodes (left column) and target nodes (right column) receive SEPARATE
  # node IDs even when the same label appears on both sides.  If they shared an
  # ID, plotly would infer that node has both incoming and outgoing flows and
  # place it in an intermediate column, breaking the two-column layout.
  #
  # Node order: pre-majors first, "Other" last, then largest-to-smallest by
  # total students.  Explicit x_pos/y_pos are passed to plotly so the visual
  # ordering matches the data ordering (arrangement = "fixed").
  source_totals <- flows %>% group_by(source_label) %>% summarise(total = sum(n), .groups = "drop")
  target_totals <- flows %>% group_by(target_label) %>% summarise(total = sum(n), .groups = "drop")

  .y_pos <- function(n) if (n == 1L) 0.5 else seq(0.05, 0.95, length.out = n)

  source_node_tbl <- flows %>%
    distinct(label = source_label, is_pre = source_is_pre) %>%
    left_join(source_totals, by = c("label" = "source_label")) %>%
    arrange(!is_pre, grepl("^Other", label), desc(total)) %>%
    mutate(
      node_id = row_number() - 1L,
      side    = "source",
      x_pos   = 0.001,
      y_pos   = .y_pos(n())
    )

  n_source <- nrow(source_node_tbl)

  target_node_tbl <- flows %>%
    distinct(label = target_label, is_pre = target_is_pre) %>%
    left_join(target_totals, by = c("label" = "target_label")) %>%
    arrange(!is_pre, grepl("^Other", label), desc(total)) %>%
    mutate(
      node_id = n_source + row_number() - 1L,
      side    = "target",
      x_pos   = 0.999,
      y_pos   = .y_pos(n())
    )

  source_id_map <- setNames(source_node_tbl$node_id, source_node_tbl$label)
  target_id_map <- setNames(target_node_tbl$node_id, target_node_tbl$label)

  all_nodes <- bind_rows(source_node_tbl, target_node_tbl)

  # Build node labels — append collapsed-program detail to "Other" nodes
  .other_hover <- function(side, is_pre) {
    key <- paste0(side, "_other_", if (is_pre) "pre" else "major", "_hover")
    h <- attr(flows, key)
    if (is.null(h) || !nzchar(h)) return(NULL)
    h
  }
  all_nodes <- all_nodes %>%
    mutate(hover_detail = sapply(seq_len(n()), function(i) {
      lab <- label[i]
      if (!grepl("^Other", lab)) return(lab)
      detail <- .other_hover(side[i], is_pre[i])
      if (!is.null(detail)) paste0(lab, " (", total[i], ")\n", detail)
      else paste0(lab, " (", total[i], ")")
    }))

  links <- flows %>%
    transmute(
      source = source_id_map[source_label],
      target = target_id_map[target_label],
      value  = n,
      hover  = paste0(source_label, " → ", target_label, ": ", n)
    )

  list(
    nodes      = all_nodes,
    links      = links,
    n_students = nrow(cohort),
    metadata   = list(
      subject_code     = subject_code,
      gen_ed_only      = gen_ed_only,
      min_n            = min_n,
      top_n            = top_n,
      n_terms          = length(terms),
      n_undeclared_end = n_undeclared_end,
      n_never_declared = n_never_declared
    )
  )
}


# Course-major associations
#
# For each selected course group, counts how many
# students who had NO prior major/pre-major in the corresponding department
# later declared one. Identifies which course groups are most associated with
# students entering the department.
#
# Exclusion: students who already had a cedar_programs record with a matching
# dept_code (Major or Second Major, declared or pre-major) in any term BEFORE
# their enrollment term are excluded from that enrollment's count.
#
# Later declared: an eligible student counts if their first dept_code program
# record is at or after the enrollment term.
#
# Depends on:
#   lists/status_codes.R  — STATUS_REGISTERED
#
# Exported:
#   get_course_major_associations(students, programs, opt)

get_course_major_associations <- function(students, programs, opt = list()) {
  subject_codes  <- opt[["subject_code"]] %||% character(0)
  dept_codes     <- opt[["dept_codes"]]
  gen_ed_only    <- isTRUE(opt[["gen_ed_only"]] %||% TRUE)
  gen_ed_courses <- opt[["gen_ed_courses"]]
  terms          <- opt[["terms"]]
  min_n          <- as.integer(opt[["min_n"]] %||% 5L)
  group_cols     <- opt[["group_cols"]] %||% c("subject_course", "instructor_name")
  group_cols     <- unique(group_cols)
  allowed_groups <- c("department", "subject_code", "subject_course", "instructor_name")

  if (length(subject_codes) == 0 || all(!nzchar(subject_codes)))
    stop("[gen-ed-conversion] opt$subject_code is required for course-major associations.")
  if (length(dept_codes) == 0)
    stop("[gen-ed-conversion] opt$dept_codes is required for course-major associations.")
  if (!all(group_cols %in% allowed_groups))
    stop("[gen-ed-conversion] unsupported group_cols: ",
         paste(setdiff(group_cols, allowed_groups), collapse = ", "))

  message("[gen-ed-conversion] course-major associations: subjects=",
          paste(subject_codes, collapse = ","),
          " dept_codes=", paste(dept_codes, collapse = ","),
          " gen_ed_only=", gen_ed_only, " min_n=", min_n,
          " group_cols=", paste(group_cols, collapse = ","))

  campus <- opt[["campus"]]  # character vector; NULL = all campuses

  # ── Step 1: qualifying enrollments ──────────────────────────────────────
  enrollments <- students %>%
    filter(
      registration_status_code %in% STATUS_REGISTERED,
      subject_code %in% .env$subject_codes
    )

  if ("instructor_name" %in% group_cols) {
    enrollments <- enrollments %>%
      filter(!is.na(instructor_name), instructor_name != "")
  }

  if (!is.null(campus) && length(campus) > 0)
    enrollments <- enrollments %>% filter(campus %in% .env$campus)

  if (gen_ed_only && length(gen_ed_courses) > 0)
    enrollments <- enrollments %>% filter(subject_course %in% gen_ed_courses)

  if (!is.null(terms) && length(terms) > 0)
    enrollments <- enrollments %>% filter(term %in% as.integer(terms))

  if (!is.null(opt[["level"]]) && length(opt[["level"]]) > 0)
    enrollments <- enrollments %>% filter(level %in% opt[["level"]])

  enrollments <- enrollments %>%
    select(any_of(c("student_id", "term", group_cols)))

  if (nrow(enrollments) == 0) {
    message("[gen-ed-conversion] course-major associations: no qualifying enrollments.")
    return(NULL)
  }

  message("[gen-ed-conversion] course-major associations: ",
          nrow(enrollments), " qualifying enrollment rows")

  # ── Step 2: first term each student appeared in a dept program ──────────
  enrl_ids <- unique(enrollments$student_id)
  first_dept <- programs %>%
    filter(
      student_id %in% enrl_ids,
      program_type %in% c("Major", "Second Major"),
      dept_code %in% .env$dept_codes
    ) %>%
    group_by(student_id) %>%
    summarize(first_dept_term = min(term), .groups = "drop")

  # ── Step 3: exclude prior affiliates, mark later declarations ───────────
  # Eligible: student had no dept program record before the enrollment term.
  # Later declared: student's first dept record is at or after the enrollment term.
  enriched <- enrollments %>%
    left_join(first_dept, by = "student_id") %>%
    filter(is.na(first_dept_term) | first_dept_term >= term) %>%
    mutate(later_declared = !is.na(first_dept_term))

  if (nrow(enriched) == 0) {
    message("[gen-ed-conversion] course-major associations: ",
            "no eligible students (all had prior dept affiliation).")
    return(NULL)
  }

  # ── Step 4: summarize by requested group ────────────────────────────────
  total_eligible <- n_distinct(enriched$student_id)

  result <- enriched %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(
      n_eligible       = n_distinct(student_id),
      n_later_declared = n_distinct(student_id[later_declared]),
      n_terms          = n_distinct(term),
      .groups          = "drop"
    ) %>%
    mutate(
      declaration_pct = n_later_declared / n_eligible,
      pct_of_eligible = n_eligible / total_eligible
    ) %>%
    filter(n_eligible >= min_n) %>%
    arrange(desc(n_later_declared), desc(declaration_pct))

  if (nrow(result) == 0) {
    message("[gen-ed-conversion] course-major associations: ",
            "no groups met min_n=", min_n, " threshold.")
    return(NULL)
  }

  message("[gen-ed-conversion] course-major associations: ",
          nrow(result), " groups")
  attr(result, "association_meta") <- list(
    distinct_eligible       = total_eligible,
    distinct_later_declared = n_distinct(enriched$student_id[enriched$later_declared]),
    group_eligible_sum      = sum(result$n_eligible, na.rm = TRUE),
    group_later_sum         = sum(result$n_later_declared, na.rm = TRUE)
  )
  result
}
