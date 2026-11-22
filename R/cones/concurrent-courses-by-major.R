# concurrent-courses-by-major.R — What else do a course's students take that
# term, by their major?
#
# One question: of the student-terms in one course, grouped by the student's
# primary major that term, which other courses were they registered in that
# same term on the same campus, and what share of the group took each? A
# course's students differ by major (pre-nursing students take BIOL 2210
# beside CHEM 1215, engineering students MATH 1512), and a pooled list is
# led by the courses everyone takes; one list per major says what a semester
# with this course looks like for each kind of student.
#
# A student-term is a student registered in the course at the pull on a
# campus in one term (prepare_course_flow_enrollments(), the same rows
# get_concurrent_courses() reads: registered statuses only). A student who
# took the course in two terms is two student-terms. The other courses are
# that student's registered rows the same term on the same campus; a course
# on another campus that term is not counted, because every course figure is
# read by campus (campus-policy.md).
#
# The major is cedar_student_terms' primary major for the student-term,
# named through name_program_codes(), so a pre-major is its own group
# ("Nursing (pre-major)" beside "Nursing"). The opt$n_majors largest groups
# with at least opt$min_n student-terms get a list each; every other
# student-term is in "All other majors", whose shares are over its own
# student-terms. Ties go to the name first in alphabetical order.
#
# The window is one term type at a time (opt$term_type): the course's last
# opt$n_terms terms of that type on each campus, up to the settled enrollment
# edge (last_enrolled_complete). Registration still moving is not a semester's
# course-taking. Each campus's terms are on the result.
#
# The course's own lab (its code with an L suffix, a standalone lab:
# AGENTS.md, Course suffixes) is taken by most of the course's students
# whatever their major, so it would lead every list and push out a course
# that tells the groups apart. It is read once per campus, as a share of all
# the course's student-terms, and left out of the lists.
#
# Before the majors, the same courses for every student-term together
# (`all_courses`), each with the college that taught it on that campus, so a
# reader sees the overall shape first: the plot section draws it as a treemap
# grouped by college, every block labelled with its share of students.
#
# Same-term pairs are counted from the class list: no measure table holds
# them (AGENTS.md: a same-term pair is not a flow).
#
# Depends on: prepare_course_flow_enrollments() (branches/course-flows.R)
#             attach_student_term(), name_program_codes() (branches/student-terms.R)
#             fmt_term() (trunk/utils.R)

CONCURRENT_OTHER_MAJORS <- "All other majors"

#' What else a course's students take that term, by their major
#'
#' @param registrations `cedar_registrations` as loaded (`subject_course` is
#'   the course id).
#' @param student_terms `cedar_student_terms`, read for `primary_major_code`
#'   and `is_pre_major`.
#' @param dims `cedar_dims`, to name the majors.
#' @param opt `course` (one course id; required), `term_type` (`"fall"`,
#'   `"spring"` or `"summer"`; required), `campus` (campuses to keep; NULL
#'   keeps every campus, each read apart), `n_terms` (the course's last terms
#'   of that type on each campus; default 3), `n_majors` (default 5),
#'   `n_courses` (courses listed per group; default 5), `min_n` (the fewest
#'   student-terms a major needs for a list of its own; default 20),
#'   `min_course_n` (the fewest student-terms a listed course needs; default
#'   5), `n_all` (courses in the all-students list; default 20),
#'   `data_edges` (`cedar_data_edges()` output; required).
#' @return A list: `all_courses` (one row per campus and course across every
#'   student-term: `college` (the teaching college's name, "College not
#'   decided" where no mapping row decides it), `subject_course`,
#'   `n_student_terms`, `pct` of the campus's student-terms, `per_term` (the
#'   average a term over the window), `course_rank`; the `n_all` largest with
#'   at least `min_course_n`); `lab` (one row per campus where at least
#'   `min_course_n` of the course's student-terms took its own lab:
#'   `lab_course`, `n_student_terms`, `course_student_terms`, `pct`);
#'   `groups` (one row per campus and group: `group`,
#'   `group_rank`, the "All other majors" group last, `n_student_terms`,
#'   `n_students`, `n_majors`, `program_codes`: the Banner codes behind a
#'   named group, so two names that read alike are told apart; NA for All
#'   other majors); `courses` (one row per campus, group and
#'   listed course: `subject_course`, `n_student_terms` taking it,
#'   `pct` of the group's student-terms, `course_rank`); `meta` (`course`,
#'   `term_type`, `terms`: one row per campus with its terms, `edge`, and the
#'   options used).
get_concurrent_courses_by_major <- function(registrations, student_terms, dims, opt = list()) {
  course <- opt[["course"]]
  if (is.null(course) || length(course) != 1 || is.na(course) || !nzchar(course)) {
    stop("[concurrent-courses-by-major.R] opt$course must be one course id", call. = FALSE)
  }
  term_type <- opt[["term_type"]]
  if (is.null(term_type) || length(term_type) != 1 || !term_type %in% c("fall", "spring", "summer")) {
    stop("[concurrent-courses-by-major.R] opt$term_type must be one of fall, spring, summer", call. = FALSE)
  }
  edge <- opt[["data_edges"]][["last_enrolled_complete"]]
  if (is.null(edge)) {
    stop("[concurrent-courses-by-major.R] opt$data_edges must name last_enrolled_complete", call. = FALSE)
  }
  edge <- as.integer(edge)
  st_cols <- c("student_id", "term", "primary_major_code", "is_pre_major")
  if (is.null(student_terms) || !all(st_cols %in% names(student_terms))) {
    stop("[concurrent-courses-by-major.R] student_terms needs ", paste(st_cols, collapse = ", "),
         call. = FALSE)
  }
  concurrent_major_int_opt <- function(name, default) {
    v <- suppressWarnings(as.integer(opt[[name]] %||% default))
    if (length(v) != 1 || is.na(v) || v < 1L) {
      stop("[concurrent-courses-by-major.R] opt$", name, " must be a positive whole number", call. = FALSE)
    }
    v
  }
  n_terms      <- concurrent_major_int_opt("n_terms", 3L)
  n_majors     <- concurrent_major_int_opt("n_majors", 5L)
  n_courses    <- concurrent_major_int_opt("n_courses", 5L)
  min_n        <- concurrent_major_int_opt("min_n", 20L)
  min_course_n <- concurrent_major_int_opt("min_course_n", 5L)
  n_all        <- concurrent_major_int_opt("n_all", 20L)

  enrollments <- prepare_course_flow_enrollments(registrations, list(campus = opt[["campus"]])) %>%
    dplyr::mutate(term = as.integer(term)) %>%
    dplyr::filter(term_type == .env$term_type, term <= .env$edge)

  # The course's last n_terms terms of the type on each campus.
  window <- enrollments %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::distinct(campus, term) %>%
    dplyr::group_by(campus) %>%
    dplyr::slice_max(term, n = n_terms, with_ties = FALSE) %>%
    dplyr::ungroup()

  members <- enrollments %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::semi_join(window, by = c("campus", "term")) %>%
    dplyr::distinct(campus, student_id, term)
  members <- attach_student_term(members, dplyr::mutate(student_terms, term = as.integer(term)),
                                 c("primary_major_code", "is_pre_major"))
  unmatched <- !(paste(members$student_id, members$term) %in%
                   paste(student_terms$student_id, student_terms$term))
  if (any(unmatched)) {
    stop("[concurrent-courses-by-major.R] ", sum(unmatched), " student-terms in ", course,
         " have no row on cedar_student_terms; the tables were not built from the same class lists.",
         call. = FALSE)
  }
  labels <- name_program_codes(members$primary_major_code, dims, is_pre_major = members$is_pre_major)
  members <- members %>%
    dplyr::mutate(major = dplyr::if_else(is.na(primary_major_code) | !nzchar(primary_major_code),
                                         "No major recorded", unname(labels[primary_major_code])))

  # The groups: the largest majors with min_n student-terms, then the rest.
  by_major <- members %>%
    dplyr::count(campus, major, name = "n_student_terms") %>%
    dplyr::arrange(campus, dplyr::desc(n_student_terms), major) %>%
    dplyr::group_by(campus) %>%
    dplyr::mutate(.rank = cumsum(n_student_terms >= min_n),
                  shown = n_student_terms >= min_n & .rank <= n_majors) %>%
    dplyr::ungroup()
  members <- members %>%
    dplyr::left_join(dplyr::select(by_major, campus, major, shown, .rank), by = c("campus", "major")) %>%
    dplyr::mutate(group = dplyr::if_else(shown, major, CONCURRENT_OTHER_MAJORS),
                  group_rank = dplyr::if_else(shown, .rank, n_majors + 1L))

  groups <- members %>%
    dplyr::group_by(campus, group, group_rank) %>%
    dplyr::summarise(n_student_terms = dplyr::n(), n_students = dplyr::n_distinct(student_id),
                     n_majors = dplyr::n_distinct(major),
                     program_codes = paste(sort(unique(stats::na.omit(primary_major_code))), collapse = ", "),
                     .groups = "drop") %>%
    # A pooled group's codes are its majors' count; a group with none is NA.
    dplyr::mutate(program_codes = dplyr::if_else(group == CONCURRENT_OTHER_MAJORS | !nzchar(program_codes),
                                                 NA_character_, program_codes)) %>%
    dplyr::arrange(campus, group_rank)

  # Each member's other registered courses that term on that campus.
  taken <- members %>%
    dplyr::select(campus, student_id, term, group, group_rank) %>%
    dplyr::inner_join(dplyr::select(enrollments, campus, student_id, term, subject_course),
                      by = c("campus", "student_id", "term"), relationship = "one-to-many") %>%
    dplyr::filter(subject_course != .env$course) %>%
    dplyr::distinct(campus, student_id, term, group, group_rank, subject_course)

  # The course's own lab, once per campus, and out of the lists.
  lab_course <- paste0(course, "L")
  lab <- taken %>%
    dplyr::filter(subject_course == .env$lab_course) %>%
    dplyr::count(campus, name = "n_student_terms") %>%
    dplyr::left_join(dplyr::count(members, campus, name = "course_student_terms"), by = "campus") %>%
    dplyr::mutate(lab_course = .env$lab_course, pct = 100 * n_student_terms / course_student_terms) %>%
    dplyr::filter(n_student_terms >= min_course_n) %>%
    dplyr::select(campus, lab_course, n_student_terms, course_student_terms, pct)
  taken <- dplyr::filter(taken, subject_course != .env$lab_course)

  # Every student-term together, each course under the college that taught it
  # there over the window (the most rows; a tie goes to the code first).
  colleges <- enrollments %>%
    dplyr::semi_join(window, by = c("campus", "term")) %>%
    dplyr::count(campus, subject_course, college, name = ".rows") %>%
    dplyr::arrange(campus, subject_course, dplyr::desc(.rows), college) %>%
    dplyr::distinct(campus, subject_course, .keep_all = TRUE)
  college_names <- college_code_names(dims)
  all_courses <- taken %>%
    dplyr::count(campus, subject_course, name = "n_student_terms") %>%
    dplyr::left_join(dplyr::count(members, campus, name = "campus_terms"), by = "campus") %>%
    dplyr::left_join(dplyr::count(window, campus, name = "n_window_terms"), by = "campus") %>%
    dplyr::left_join(dplyr::select(colleges, campus, subject_course, college), by = c("campus", "subject_course")) %>%
    dplyr::mutate(
      college = dplyr::case_when(is.na(college) | !nzchar(college) ~ "College not decided",
                                 college %in% names(college_names) ~ unname(college_names[college]),
                                 TRUE ~ college),
      pct = 100 * n_student_terms / campus_terms,
      per_term = n_student_terms / n_window_terms
    ) %>%
    dplyr::filter(n_student_terms >= min_course_n) %>%
    dplyr::arrange(campus, dplyr::desc(n_student_terms), subject_course) %>%
    dplyr::group_by(campus) %>%
    dplyr::mutate(course_rank = dplyr::row_number()) %>%
    dplyr::filter(course_rank <= n_all) %>%
    dplyr::ungroup() %>%
    dplyr::select(campus, college, subject_course, n_student_terms, pct, per_term, course_rank)

  courses <- taken %>%
    dplyr::count(campus, group, group_rank, subject_course, name = "n_student_terms") %>%
    dplyr::left_join(dplyr::select(groups, campus, group, group_terms = n_student_terms),
                     by = c("campus", "group")) %>%
    dplyr::mutate(pct = 100 * n_student_terms / group_terms) %>%
    dplyr::filter(n_student_terms >= min_course_n) %>%
    dplyr::arrange(campus, group_rank, dplyr::desc(n_student_terms), subject_course) %>%
    dplyr::group_by(campus, group) %>%
    dplyr::mutate(course_rank = dplyr::row_number()) %>%
    dplyr::filter(course_rank <= n_courses) %>%
    dplyr::ungroup() %>%
    dplyr::select(campus, group, group_rank, subject_course, n_student_terms, pct, course_rank)

  terms <- window %>%
    dplyr::arrange(campus, term) %>%
    dplyr::group_by(campus) %>%
    dplyr::summarise(terms = list(term), .groups = "drop")

  cedar_debug("[concurrent-courses-by-major.R] ", course, " ", term_type, ": ", nrow(members),
              " student-terms in ", nrow(groups), " campus groups; ", nrow(courses), " courses listed")

  list(
    all_courses = all_courses,
    lab = lab,
    groups = groups,
    courses = courses,
    meta = list(course = course, term_type = term_type, terms = terms, edge = edge,
                n_terms = n_terms, n_majors = n_majors, n_courses = n_courses,
                min_n = min_n, min_course_n = min_course_n, n_all = n_all)
  )
}

# ── Text preview ───────────────────────────────────────────────────────────────

#' The by-major lists as text
#'
#' @param payload get_concurrent_courses_by_major() output.
#' @return A character vector of lines.
format_concurrent_courses_by_major <- function(payload) {
  if (!all(c("all_courses", "lab", "groups", "courses", "meta") %in% names(payload))) {
    stop("[concurrent-courses-by-major.R] payload must come from get_concurrent_courses_by_major()",
         call. = FALSE)
  }
  m <- payload$meta
  whole <- fmt_count
  out <- sprintf("Courses taken alongside %s, %s terms, through %s (the settled edge)",
                 m$course, m$term_type, fmt_term(m$edge))
  if (nrow(payload$groups) == 0) {
    return(c(out, sprintf("No student registered in %s in a %s term up to the edge.", m$course, m$term_type)))
  }
  for (cp in unique(payload$groups$campus)) {
    g <- payload$groups[payload$groups$campus == cp, ]
    terms <- m$terms$terms[[match(cp, m$terms$campus)]]
    out <- c(out, "", sprintf("%s: %s student-terms in %s (%s)", cp, whole(sum(g$n_student_terms)), m$course,
                              paste(vapply(terms, fmt_term, character(1)), collapse = ", ")))
    every <- utils::head(payload$all_courses[payload$all_courses$campus == cp, ], 10)
    if (nrow(every) > 0) {
      out <- c(out, sprintf("  All students: %s", paste(sprintf("%s %.1f%% (%s)", every$subject_course, every$pct,
                                                                whole(every$n_student_terms)), collapse = ", ")))
    }
    lab <- payload$lab[payload$lab$campus == cp, ]
    if (nrow(lab) == 1) {
      out <- c(out, sprintf("  Its lab, %s: %.1f%% (%s), every major together; not in the lists below",
                            lab$lab_course, lab$pct, whole(lab$n_student_terms)))
    }
    for (i in seq_len(nrow(g))) {
      size <- sprintf("%s student-terms, %s students", whole(g$n_student_terms[i]), whole(g$n_students[i]))
      name <- if (is.na(g$program_codes[i])) g$group[i] else sprintf("%s [%s]", g$group[i], g$program_codes[i])
      if (g$group[i] == CONCURRENT_OTHER_MAJORS) {
        size <- paste0(size, sprintf(", %s majors", whole(g$n_majors[i])))
      }
      cs <- payload$courses[payload$courses$campus == cp & payload$courses$group == g$group[i], ]
      listed <- if (nrow(cs) == 0) "no other course with enough students" else
        paste(sprintf("%s %.1f%% (%s)", cs$subject_course, cs$pct, whole(cs$n_student_terms)), collapse = ", ")
      out <- c(out, sprintf("  %s (%s): %s", name, size, listed))
    }
  }
  out
}

# ── Plot prep ─────────────────────────────────────────────────────────────────

#' One campus's all-students courses as treemap nodes
#'
#' A block's area is the student-terms that took the course. Each student-term
#' takes several, so the areas do not add up to the students: every block is
#' labelled with its share of students, which the area understates.
#'
#' @param payload get_concurrent_courses_by_major() output.
#' @param campus One campus on `payload$all_courses`.
#' @return A tibble of nodes: `id`, `parent` ("" for a college), `label`,
#'   `value`, `text` (the block's label line), `hover`, `college`, one row per
#'   college, then one per course.
prepare_concurrent_courses_treemap <- function(payload, campus) {
  rows <- payload$all_courses[payload$all_courses$campus == campus, , drop = FALSE]
  if (nrow(rows) == 0L) {
    stop("[concurrent-courses-by-major.R] no all-students courses on campus ", campus, call. = FALSE)
  }
  treemap_count <- fmt_count
  campus_terms <- rows$n_student_terms[1] / rows$pct[1] * 100
  leaves <- tibble::tibble(
    id = paste(rows$college, rows$subject_course, sep = " / "),
    parent = rows$college,
    label = rows$subject_course,
    value = rows$n_student_terms,
    text = sprintf("%.0f%% of students", rows$pct),
    hover = sprintf("%s: %s of %s student-terms (%.1f%%), about %s a term", rows$subject_course,
                    treemap_count(rows$n_student_terms), treemap_count(campus_terms), rows$pct, treemap_count(rows$per_term)),
    college = rows$college
  )
  parents <- leaves %>%
    dplyr::group_by(college) %>%
    dplyr::summarise(value = sum(value), n_courses = dplyr::n(), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(value), college) %>%
    dplyr::transmute(id = college, parent = "", label = college, value,
                     text = "", hover = paste0(college, ": ", n_courses, " of the courses listed"), college)
  dplyr::bind_rows(parents, leaves[order(match(leaves$college, parents$college), -leaves$value), ])
}

# ── Plotting ──────────────────────────────────────────────────────────────────

#' The all-students treemap for one campus
#'
#' @param nodes prepare_concurrent_courses_treemap() output.
#' @return A plotly treemap: one colour per college, every course block named
#'   with its share of students.
plot_concurrent_courses_treemap <- function(nodes) {
  colors <- build_color_map(nodes$college[nodes$parent == ""])
  fills <- unname(colors[nodes$college])
  # White text where it reaches 4.5:1 on the block, dark ink where it does not
  # (the gold and olive colleges): the share line is small text.
  treemap_text_color <- function(hex) {
    rgb <- grDevices::col2rgb(hex) / 255
    lin <- ifelse(rgb <= 0.03928, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
    lum <- colSums(lin * c(0.2126, 0.7152, 0.0722))
    ifelse(1.05 / (lum + 0.05) >= 4.5, "#ffffff", "#1f2421")
  }
  plotly::plot_ly(
    type = "treemap", ids = nodes$id, parents = nodes$parent, labels = nodes$label,
    values = nodes$value, branchvalues = "total", text = nodes$text,
    customdata = nodes$hover, texttemplate = "<b>%{label}</b><br>%{text}",
    hovertemplate = "%{customdata}<extra></extra>",
    marker = list(colors = fills, line = list(color = "#ffffff", width = 2)),
    textfont = list(color = treemap_text_color(fills)),
    pathbar = list(visible = FALSE), tiling = list(pad = 2)
  ) %>%
    plotly::layout(margin = list(l = 0, r = 0, t = 0, b = 0)) %>%
    plotly::config(displayModeBar = FALSE)
}
