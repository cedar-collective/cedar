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

  if (!nzchar(subject_code)) {
    stop("[gen-ed-conversion.R] opt$subject_code is required.")
  }

  message("[gen-ed-conversion.R] subject=", subject_code,
          " gen_ed_only=", gen_ed_only,
          " min_n=", min_n,
          " terms=", if (is.null(terms)) "all" else paste(range(terms), collapse = "-"))

  # ── Step 1: qualifying gen ed enrollments ─────────────────────────────────
  exposures <- students %>%
    filter(
      registration_status_code %in% STATUS_REGISTERED,
      subject_code == .env$subject_code
    )

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

  .y_pos <- function(n) if (n == 1L) 0.5 else seq(0.02, 0.98, length.out = n)

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
      n_terms          = length(terms),
      n_undeclared_end = n_undeclared_end,
      n_never_declared = n_never_declared
    )
  )
}
