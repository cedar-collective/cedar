#' Headcount: Student Program Enrollment Analysis
#'
#' Functions for analyzing student enrollment by academic program
#' (majors, minors, concentrations) over time.
#'
#' @section Data Requirements:
#' Requires cedar_programs table with CEDAR column names (lowercase with underscores):
#' - student_id (encrypted student identifier)
#' - term (integer term code, e.g., 202580)
#' - student_campus (campus code, consistent across all program rows for a student per term)
#' - student_college (college code for student's primary college)
#' - student_level ("Undergraduate", "Graduate/GASM")
#' - degree (degree type)
#' - dept_code (department code derived from the program's major code)
#' - program_type ("Major", "Second Major", "First Minor", "Second Minor",
#'                 "First Concentration", "Second Concentration", "Third Concentration")
#' - program_name (program name)
#'
#' @section Main Functions:
#' - get_headcount(): Main orchestrating function for flexible headcount analysis
#' - get_headcount_data_for_dept_report(): Generate complete dept report data/plots
#' - make_headcount_plots_by_level(): Create separate UG/Grad plots
#' - make_headcount_plot(): Create single combined plot
#'
#' @section Helper Functions:
#' - filter_programs_by_opt(): Apply institutional and program filters
#' - summarize_headcount(): Group and count students
#' - format_headcount_result(): Package data with metadata
#'
#' @examples
#' \dontrun{
#' # Headcount for a department
#' result <- get_headcount(cedar_programs, list(dept_code = "MATH"))
#'
#' # Students with both a History major and an Anthropology minor
#' result <- get_headcount(cedar_programs, list(major = "History", minor = "Anthropology"))
#'
#' # Custom grouping for SFR calculations
#' result <- get_headcount(
#'   cedar_programs,
#'   opt      = list(),
#'   group_by = c("term", "dept_code", "student_level")
#' )
#'
#' plots <- make_headcount_plots_by_level(result)
#' }
#'
#' @name headcount



#' Filter Programs Data by Options
#'
#' Helper function that applies institutional and program filters to CEDAR programs data.
#'
#' @param programs Data frame of student program enrollment data (CEDAR format)
#' @param opt Options list with possible filters:
#'   \itemize{
#'     \item campus - Vector of campus codes to include
#'     \item college - Vector of college codes to include
#'     \item dept - Vector of department codes to include
#'     \item major - Vector of major program names to include
#'     \item minor - Vector of minor program names to include
#'     \item concentration - Vector of concentration names to include
#'   }
#'
#' @return List with:
#'   \describe{
#'     \item{data}{Filtered data frame}
#'     \item{has_program_filter}{Boolean indicating if program-specific filters were applied}
#'   }
#'
#' @details
#' **Filtering strategy**
#'
#' Campus and college are row-level filters. Because these attributes are the same
#' across all program rows for a student in a given term, row-level filtering is
#' equivalent to student-level filtering and safe to apply directly.
#'
#' Dept is a row-level filter: only program rows whose dept_code matches are kept.
#' Cross-dept combinations (e.g. History major + Anthropology minor) are handled by
#' using the major/minor/concentration filters directly instead of the dept filter.
#'
#' Major, minor, and concentration each independently find the set of student IDs that
#' satisfy that criterion, then intersect them. A student must satisfy every active
#' program filter to be included (AND logic across filters). When multiple program
#' filters are active, only rows for the primary filter are returned (major > minor >
#' concentration), so the plot shows a single series rather than one facet per type.
#'
#' @keywords internal
normalize_headcount_opt <- function(programs, opt = list(), lookups = NULL) {
  opt <- opt %||% list()

  normalize_empty <- function(x) {
    if (is.null(x)) return(NULL)
    x <- as.character(x)
    x <- x[!is.na(x) & nzchar(x)]
    if (length(x) == 0) NULL else x
  }

  opt$campus        <- normalize_empty(opt$campus)
  opt$college       <- normalize_empty(opt$college)
  opt$dept_code     <- toupper(normalize_empty(opt$dept_code))
  opt$major         <- normalize_empty(opt$major)
  opt$minor         <- normalize_empty(opt$minor)
  opt$concentration <- normalize_empty(opt$concentration)

  if (!is.null(opt$college) && "student_college" %in% names(programs)) {
    valid_colleges <- sort(unique(programs$student_college[
      !is.na(programs$student_college) & nzchar(programs$student_college)
    ]))

    college_map <- stats::setNames(valid_colleges, valid_colleges)
    if (!is.null(lookups$college_code_to_name)) {
      code_map <- lookups$college_code_to_name
      code_map <- code_map[!is.na(code_map) & nzchar(code_map)]
      college_map <- c(college_map, code_map)
    }

    lower_map <- stats::setNames(unname(college_map), tolower(names(college_map)))
    opt$college <- vapply(opt$college, function(x) {
      lower_map[[tolower(x)]] %||% x
    }, character(1), USE.NAMES = FALSE)
    opt$college <- unique(opt$college)

    unknown_colleges <- setdiff(opt$college, valid_colleges)
    if (length(unknown_colleges) > 0) {
      stop("[headcount.R] Unknown college filter value(s): ",
           paste(unknown_colleges, collapse = ", "),
           ". Values must match cedar_programs$student_college or ",
           "cedar_lookups$college_code_to_name.", call. = FALSE)
    }
  }

  opt
}


headcount_has_program_filter <- function(opt) {
  any(vapply(c("major", "minor", "concentration"), function(key) {
    !is.null(opt[[key]]) && length(opt[[key]]) > 0
  }, logical(1)))
}


headcount_default_scope <- function(opt, has_program_filter) {
  if (has_program_filter) return("program")
  if (!is.null(opt$dept_code) && length(opt$dept_code) > 0) return("program")
  if (!is.null(opt$college) && length(opt$college) > 0) return("department")
  "program_type"
}


headcount_should_plot_aggregate <- function(opt) {
  (is.null(opt$dept_code) || length(opt$dept_code) == 0) && !headcount_has_program_filter(opt)
}


require_headcount_lookup <- function(lookups, name, cols) {
  if (is.null(lookups) || is.null(lookups[[name]])) {
    stop("[headcount.R] Missing required cedar_lookups$", name,
         ". Re-run the transform or fix cedar_lookups.qs before using Headcount.",
         call. = FALSE)
  }

  missing_cols <- setdiff(cols, names(lookups[[name]]))
  if (length(missing_cols) > 0) {
    stop("[headcount.R] cedar_lookups$", name, " is missing required columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  lookups[[name]]
}


add_headcount_dept_fields <- function(df, lookups = NULL) {
  if ("dept_code" %in% names(df)) {
    df <- df %>% rename(original_dept_code = dept_code)
  } else {
    df <- df %>% mutate(original_dept_code = NA_character_)
  }

  program_lookup <- require_headcount_lookup(
    lookups, "program_name_lookup", c("program_name", "dept_code")
  )
  dept_names <- require_headcount_lookup(
    lookups, "dept_name_lookup", c("dept_code", "dept_name")
  )

  dept_lookup <- program_lookup %>%
    select(program_name, lookup_dept_code = dept_code) %>%
    left_join(
      dept_names %>% select(lookup_dept_code = dept_code, lookup_dept_name = dept_name),
      by = "lookup_dept_code"
    )

  df %>%
    left_join(dept_lookup, by = "program_name") %>%
    mutate(
      dept_code = coalesce(lookup_dept_code, original_dept_code, "UNK"),
      dept_name = coalesce(lookup_dept_name, dept_code)
    ) %>%
    select(-original_dept_code, -lookup_dept_code, -lookup_dept_name)
}


filter_programs_by_opt <- function(programs, opt = list(), lookups = NULL) {
  opt <- normalize_headcount_opt(programs, opt, lookups)

  # Select important columns (CEDAR naming)
  important_cols <- c("student_id", "term", "student_college", "student_campus",
                      "student_level", "degree", "dept_code",
                      "program_type", "program_name")

  message("[headcount.R] Selecting CEDAR columns...")
  available_cols <- important_cols[important_cols %in% colnames(programs)]
  df <- programs %>% select(all_of(available_cols)) %>% distinct()
  message("[headcount.R] Data shape: ", nrow(df), " rows, ", ncol(df), " cols")

  # Campus/college: row-level filters (consistent across all program rows for a student)
  if (!is.null(opt$campus) && length(opt$campus) > 0) {
    message("[headcount.R] Filtering by campus: ", paste(opt$campus, collapse = ", "))
    df <- df %>% filter(student_campus %in% opt$campus)
  }

  if (!is.null(opt$college) && length(opt$college) > 0) {
    message("[headcount.R] Filtering by college: ", paste(opt$college, collapse = ", "))
    df <- df %>% filter(student_college %in% opt$college)
  }

  if (!is.null(opt$dept_code) && length(opt$dept_code) > 0) {
    message("[headcount.R] Filtering by department code: ", paste(opt$dept_code, collapse = ", "))
    pnl <- require_headcount_lookup(
      lookups, "program_name_lookup", c("program_name", "dept_code")
    )
    dept_programs <- pnl %>% filter(dept_code %in% opt$dept_code) %>% pull(program_name)
    df <- df %>% filter(dept_code %in% opt$dept_code | program_name %in% dept_programs)
  }

  has_program_filter <- headcount_has_program_filter(opt)

  # Program filters: find student_ids matching each criterion independently, then
  # intersect so that combined filters (e.g. major + minor) require BOTH.
  # This avoids the sequential-filter bug where major filter removes minor-type rows.
  scoped_ids <- df %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

  if (!is.null(opt$major) && length(opt$major) > 0) {
    message("[headcount.R] Filtering by major: ", paste(opt$major, collapse = ", "))
    major_ids <- df %>%
      filter(program_type %in% c("Major", "Second Major"),
             program_name %in% opt$major, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, major_ids)
  }

  if (!is.null(opt$minor) && length(opt$minor) > 0) {
    message("[headcount.R] Filtering by minor: ", paste(opt$minor, collapse = ", "))
    minor_ids <- df %>%
      filter(program_type %in% c("First Minor", "Second Minor"),
             program_name %in% opt$minor, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, minor_ids)
  }

  if (!is.null(opt$concentration) && length(opt$concentration) > 0) {
    message("[headcount.R] Filtering by concentration: ", paste(opt$concentration, collapse = ", "))
    conc_ids <- df %>%
      filter(program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"),
             program_name %in% opt$concentration, !is.na(student_id)) %>%
      distinct(student_id) %>% pull(student_id)
    scoped_ids <- intersect(scoped_ids, conc_ids)
  }

  if (has_program_filter) {
    df <- df %>% filter(student_id %in% scoped_ids)

    # When multiple program filters are combined (e.g. major + minor), secondary filters
    # already narrowed scoped_ids above. Now keep only the rows for the PRIMARY filter
    # so the plot shows a single series rather than one facet per program type.
    # Priority: major > minor > concentration.
    if (!is.null(opt$major) && length(opt$major) > 0) {
      df <- df %>% filter(program_type %in% c("Major", "Second Major"),
                          program_name %in% opt$major)
    } else if (!is.null(opt$minor) && length(opt$minor) > 0) {
      df <- df %>% filter(program_type %in% c("First Minor", "Second Minor"),
                          program_name %in% opt$minor)
    } else if (!is.null(opt$concentration) && length(opt$concentration) > 0) {
      df <- df %>% filter(
        program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"),
        program_name %in% opt$concentration)
    }
  }

  message("[headcount.R] Data shape after filters: ", nrow(df), " rows")

  return(list(data = df, has_program_filter = has_program_filter))
}


#' Summarize Headcount Data
#'
#' Helper function that groups and counts students from filtered programs data.
#'
#' @param df Filtered programs data frame (from filter_programs_by_opt)
#' @param has_program_filter Boolean indicating if program filters were applied
#' @param group_by Character vector of column names to group by. When NULL:
#'   - No program filter: groups by c("term", "student_level", "program_type")
#'   - Program filter active: groups by c("term", "student_level", "program_type", "program_name")
#'   Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).
#'
#' @param lookups Optional list with \code{program_name_lookup} (program_name →
#'   dept_code) and \code{dept_name_lookup} (dept_code → dept_name), used only to
#'   roll a broad program selection up to department totals (see Details).
#'
#' @return Data frame with columns from group_by plus student_count (distinct student IDs)
#'
#' @details
#' **Department/unit rollup**
#'
#' When no explicit \code{group_by} is given and a program filter selects more than
#' \code{UNIT_ROLLUP_THRESHOLD} distinct programs (e.g. every major in a college),
#' faceting one panel per program doesn't scale. In that case the data is regrouped
#' by the program's owning department (via \code{program_name_lookup}) instead of by
#' individual program, and \code{attr(result, "rolled_up_by_dept")} is set to TRUE so
#' \code{\link{make_headcount_plots_by_level}} can facet/label by department.
#'
#' @keywords internal
summarize_headcount <- function(df, has_program_filter, group_by = NULL,
                                lookups = NULL, opt = list()) {

  UNIT_ROLLUP_THRESHOLD <- 12
  rolled_up_by_dept <- FALSE

  # Determine grouping columns
  if (is.null(group_by)) {
    scope <- headcount_default_scope(opt, has_program_filter)
    if (identical(scope, "program_type")) {
      message("[headcount.R] No program filters - summarizing by program type only")
      group_by <- c("term", "student_level", "program_type")
    } else if (identical(scope, "department")) {
      message("[headcount.R] College-level scope - summarizing by department/unit")
      df <- add_headcount_dept_fields(df, lookups)
      rolled_up_by_dept <- TRUE
      group_by <- c("term", "student_level", "program_type", "dept_code", "dept_name")
    } else {
      n_programs <- n_distinct(df$program_name[!is.na(df$program_name) & df$program_name != ""])

      if (n_programs > UNIT_ROLLUP_THRESHOLD) {
        message("[headcount.R] ", n_programs, " distinct programs selected (> ",
                UNIT_ROLLUP_THRESHOLD, ") - rolling up to department/unit totals")

        df <- add_headcount_dept_fields(df, lookups)
        rolled_up_by_dept <- TRUE
        group_by <- c("term", "student_level", "program_type", "dept_code", "dept_name")
      } else {
        message("[headcount.R] Summarizing by specific programs")
        group_by <- c("term", "student_level", "program_type", "program_name")
      }
    }
  } else {
    message("[headcount.R] Using custom grouping: ", paste(group_by, collapse = ", "))
  }

  # Include degree in grouping when available — enables degree-type breakdown in the grad plot
  if ("degree" %in% names(df) && !"degree" %in% group_by) {
    group_by <- c(group_by, "degree")
  }

  # Filter out empty program names and summarize
  summarized <- df %>%
    filter(!is.na(program_name) & program_name != "") %>%
    group_by(across(all_of(group_by))) %>%
    summarize(student_count = n_distinct(student_id), .groups = "drop") %>%
    arrange(across(all_of(group_by)))

  message("[headcount.R] Summary data shape: ", nrow(summarized), " rows")

  attr(summarized, "rolled_up_by_dept") <- rolled_up_by_dept
  return(summarized)
}


summarize_headcount_plot_data <- function(df, opt = list()) {
  if (!headcount_should_plot_aggregate(opt)) {
    return(NULL)
  }

  group_by <- c("term", "student_level", "program_type")
  if ("degree" %in% names(df)) {
    group_by <- c(group_by, "degree")
  }

  df %>%
    filter(!is.na(program_name) & program_name != "") %>%
    group_by(across(all_of(group_by))) %>%
    summarize(student_count = n_distinct(student_id), .groups = "drop") %>%
    arrange(across(all_of(group_by)))
}


#' Format Headcount Result with Metadata
#'
#' Helper function that packages headcount data with metadata.
#'
#' @param summarized Summarized headcount data frame
#' @param df Original filtered data (for metadata calculation)
#' @param has_program_filter Boolean indicating if program filters were applied
#' @param opt Options list used for filtering
#'
#' @return List with data and metadata:
#'   \describe{
#'     \item{data}{Summarized headcount data frame}
#'     \item{no_program_filter}{Boolean - TRUE if no program filters applied}
#'     \item{metadata}{List with total_students, programs_included, filters_applied}
#'   }
#'
#' @keywords internal
format_headcount_result <- function(summarized, df, has_program_filter, opt,
                                    rolled_up_by_dept = FALSE, plot_data = NULL) {
  has_display_unit <- any(c("program_name", "dept_name") %in% names(summarized))

  result <- list(
    data = summarized,
    plot_data = plot_data,
    plot_as_aggregate = !is.null(plot_data),
    no_program_filter = !has_display_unit,
    rolled_up_by_dept = rolled_up_by_dept,
    metadata = list(
      total_students = n_distinct(df$student_id),
      programs_included = if (!has_program_filter) "all" else c(opt$major, opt$minor, opt$concentration),
      filters_applied = names(opt)[!sapply(opt, is.null)]
    )
  )

  return(result)
}


#' Format Headcount Results for CSV Export
#'
#' @param result Result list returned by \code{get_headcount()}.
#' @return Data frame suitable for a user-facing CSV download.
#' @export
format_headcount_export <- function(result) {
  if (is.null(result) || is.null(result$data) || !is.data.frame(result$data) ||
      nrow(result$data) == 0) {
    return(data.frame(message = "No headcount data available"))
  }

  export <- result$data %>%
    ungroup()

  if ("term" %in% names(export)) {
    export <- export %>%
      mutate(term_label = vapply(term, fmt_term, character(1))) %>%
      relocate(term_label, .after = term)
  }

  preferred_cols <- c(
    "term", "term_label", "student_level", "program_type", "program_name",
    "dept_code", "dept_name", "degree", "student_count"
  )
  present_preferred <- intersect(preferred_cols, names(export))
  other_cols <- setdiff(names(export), present_preferred)

  export %>%
    select(all_of(c(present_preferred, other_cols))) %>%
    arrange(across(any_of(c("term", "student_level", "program_type",
                           "program_name", "dept_code", "degree"))))
}


#' Get Student Headcount
#'
#' Main orchestrating function for calculating student headcount from CEDAR programs data.
#'
#' @param programs Student program enrollment data in CEDAR format.
#'   Required columns: student_id, term, student_level, program_type, program_name, dept_code.
#'   Optional columns: student_college, student_campus, degree.
#' @param opt Options list for filtering:
#'   \itemize{
#'     \item campus - Filter by campus code(s)
#'     \item college - Filter by college code(s)
#'     \item dept - Filter by department code(s); scopes to students with any program in
#'           that dept, preserving their minor/concentration rows from other depts
#'     \item major - Filter by major program name(s)
#'     \item minor - Filter by minor program name(s)
#'     \item concentration - Filter by concentration name(s)
#'   }
#'   Multiple program filters (major + minor, etc.) are combined with AND logic:
#'   only students satisfying all specified filters are counted. The plot reflects
#'   the primary filter (major > minor > concentration).
#' @param group_by Optional character vector of columns to group by.
#'   Defaults to c("term", "student_level", "program_type", "program_name") when a
#'   program filter is active, or c("term", "student_level", "program_type") otherwise.
#'   Pass explicitly for custom aggregations (e.g. SFR: c("term", "dept_code", "student_level")).
#'
#' @return List with:
#'   \describe{
#'     \item{data}{Data frame with student_count and grouping columns}
#'     \item{no_program_filter}{TRUE when no major/minor/concentration filter was applied}
#'     \item{metadata}{List with total_students, programs_included, filters_applied}
#'   }
#'
#' @details
#' Delegates to \code{\link{filter_programs_by_opt}}, \code{\link{summarize_headcount}},
#' and \code{\link{format_headcount_result}}. See \code{\link{filter_programs_by_opt}}
#' for details on the ID-scope filtering strategy.
#'
#' @examples
#' \dontrun{
#' # All programs in a department
#' result <- get_headcount(cedar_programs, list(dept_code = "HIST"))
#'
#' # History majors who also have an Anthropology minor
#' result <- get_headcount(cedar_programs, list(major = "History", minor = "Anthropology"))
#'
#' # SFR aggregation
#' result <- get_headcount(
#'   cedar_programs,
#'   opt      = list(),
#'   group_by = c("term", "dept_code", "student_level")
#' )
#' }
#'
#' @seealso \code{\link{filter_programs_by_opt}}, \code{\link{make_headcount_plots_by_level}}
#'
#' Related functions:
#' \code{\link{get_headcount_data_for_dept_report}},
#' \code{\link{make_headcount_plots_by_level}},
#' \code{\link{make_headcount_plot}}
#'
#' @export
get_headcount <- function(programs, opt = list(), group_by = NULL, lookups = NULL) {

  message("[headcount.R] Welcome to get_headcount!")
  message("[headcount.R] opt contents: ", paste(names(opt), collapse = ", "))

  # Step 1: Filter programs data
  filtered <- filter_programs_by_opt(programs, opt, lookups = lookups)
  opt <- normalize_headcount_opt(programs, opt, lookups)

  # Step 2: Summarize headcount by specified groups
  summarized <- summarize_headcount(
    df = filtered$data,
    has_program_filter = filtered$has_program_filter,
    group_by = group_by,
    lookups = lookups,
    opt = opt
  )
  rolled_up_by_dept <- isTRUE(attr(summarized, "rolled_up_by_dept"))
  plot_data <- if (is.null(group_by)) summarize_headcount_plot_data(filtered$data, opt) else NULL

  message("[headcount.R] Sample data (", nrow(summarized), " rows, columns: ", paste(names(summarized), collapse=", "), "):")
  message(paste(capture.output(print(head(summarized, 10))), collapse = "\n"))

  # Step 3: Format result with metadata
  result <- format_headcount_result(
    summarized = summarized,
    df = filtered$data,
    has_program_filter = filtered$has_program_filter,
    opt = opt,
    rolled_up_by_dept = rolled_up_by_dept,
    plot_data = plot_data
  )

  return(result)
}


#' Create Headcount Plots by Student Level
#'
#' Creates separate interactive plots for undergraduate and graduate students,
#' with appropriate visualization choices for each level.
#'
#' @param result Result list from count_heads_by_program() containing data and metadata
#'
#' @return Named list with plotly plots:
#'   \describe{
#'     \item{undergrad}{Undergraduate enrollment plot (stacked bars by program)}
#'     \item{graduate}{Graduate enrollment plot (dodged bars by program)}
#'   }
#'
#' @details
#' Undergraduate plots use stacked bars faceted by program for density.
#' Graduate plots use dodged bars for easier comparison of smaller cohorts.
#'
#' @export
make_headcount_plots_by_level <- function(result) {

  message("[headcount.R] Welcome to make_headcount_plots_by_level!")

  # Extract data and metadata
  plot_as_aggregate <- isTRUE(result$plot_as_aggregate)
  summarized <- if (plot_as_aggregate && !is.null(result$plot_data)) {
    result$plot_data
  } else {
    result$data
  }
  no_program <- isTRUE(result$no_program_filter) || plot_as_aggregate
  rolled_up_by_dept <- isTRUE(result$rolled_up_by_dept) && !plot_as_aggregate
  has_program_type <- "program_type" %in% colnames(summarized)

  # When summarize_headcount() rolled a broad program selection up to department
  # totals, reuse the existing program_name faceting code below by renaming
  # dept_name → program_name (titles are adjusted separately further down).
  if (rolled_up_by_dept && "dept_name" %in% colnames(summarized)) {
    summarized <- summarized %>%
      rename(program_name = dept_name) %>%
      select(-any_of("dept_code"))
  }

  plots <- list()

  # Keep terms as ordered categories so Plotly does not treat Banner codes as
  # continuous numbers and abbreviate them as 202k.
  term_levels <- headcount_term_levels(summarized$term)
  summarized$term <- term_axis_factor(summarized$term)

  # Define program type ordering (academic hierarchy) - only if column exists
  if (has_program_type) {
    program_type_order <- c("Major", "Second Major", "First Minor", "Second Minor",
                           "First Concentration", "Second Concentration")
    summarized$program_type <- factor(summarized$program_type,
                                     levels = program_type_order,
                                     ordered = TRUE)
  }

  # Order program values alphabetically for consistent display
  if (!no_program && "program_name" %in% colnames(summarized)) {
    program_value_order <- sort(unique(summarized$program_name))
    summarized$program_name <- factor(summarized$program_name,
                                      levels = program_value_order,
                                      ordered = TRUE)
  }

  # Undergraduate plot (CEDAR naming)
  message("[headcount.R] Creating Undergraduate plot...")
  undergrad_data <- summarized[summarized$student_level == "Undergraduate", ]

  # Collapse degree for the undergrad plot — degree breakdown is shown only in the grad plot
  if ("degree" %in% names(undergrad_data)) {
    ug_agg_cols <- setdiff(names(undergrad_data), c("degree", "student_count"))
    undergrad_data <- undergrad_data %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(ug_agg_cols))) %>%
      dplyr::summarize(student_count = sum(student_count), .groups = "drop")
  }

  if (nrow(undergrad_data) > 0) {
    if (!has_program_type) {
      plots$undergrad <- plot_ly(undergrad_data, x = ~term, y = ~student_count,
                                 type = "bar", marker = list(color = unname(CEDAR_COLORS["blue"])),
                                 hovertemplate = "%{x}<br>Students: %{y}<extra></extra>") %>%
        layout(title = list(text = "Undergraduate Headcount", x = 0),
               xaxis = headcount_term_axis(term_levels, title = "Term"),
               yaxis = list(title = "Student Count"))
    } else if (no_program) {
      plots$undergrad <- plot_ly(undergrad_data, x = ~term, y = ~student_count,
                                 color = ~program_type,
                                 colors = cedar_plotly_palette(undergrad_data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                                 type = "bar",
                                 hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "stack",
               title  = list(text = "Undergraduate Headcount", x = 0),
               xaxis  = headcount_term_axis(term_levels, title = "Term"),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.15))
    } else if (!no_program && "program_name" %in% colnames(summarized)) {
      prog_names <- unique(undergrad_data$program_name)
      sub_plots  <- lapply(seq_along(prog_names), function(i) {
        pn <- prog_names[[i]]
        plot_ly(undergrad_data %>% filter(program_name == pn),
                x = ~term, y = ~student_count, color = ~program_type,
                colors = cedar_plotly_palette(undergrad_data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                type = "bar",
                showlegend  = (i == 1), legendgroup = ~program_type,
                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
          layout(barmode = "stack",
                 annotations = list(list(text = pn, showarrow = FALSE,
                                         xref = "paper", yref = "paper",
                                         x = 0.5, y = 1.05, font = list(size = 11))),
                 xaxis = headcount_term_axis(term_levels))
      })
      plots$undergrad <- subplot(sub_plots, nrows = ceiling(length(prog_names) / 2),
                                 shareX = FALSE, shareY = FALSE,
                                 titleX = TRUE, titleY = TRUE, margin = 0.08) %>%
        layout(title  = list(text = if (rolled_up_by_dept) "Undergraduate Headcount by Department"
                                     else "Undergraduate Headcount by Program", x = 0),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.15))
    } else {
      prog_types <- unique(undergrad_data$program_type)
      sub_plots  <- lapply(seq_along(prog_types), function(i) {
        pt <- prog_types[[i]]
        plot_ly(undergrad_data %>% filter(program_type == pt),
                x = ~term, y = ~student_count, color = ~program_type,
                colors = cedar_plotly_palette(undergrad_data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                type = "bar",
                showlegend  = (i == 1), legendgroup = ~program_type,
                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
          layout(barmode = "stack",
                 annotations = list(list(text = pt, showarrow = FALSE,
                                         xref = "paper", yref = "paper",
                                         x = 0.5, y = 1.05, font = list(size = 11))),
                 xaxis = headcount_term_axis(term_levels))
      })
      plots$undergrad <- subplot(sub_plots, nrows = ceiling(length(prog_types) / 2),
                                 shareX = FALSE, shareY = FALSE,
                                 titleX = TRUE, titleY = TRUE, margin = 0.08) %>%
        layout(title  = list(text = "Undergraduate Headcount", x = 0),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.15))
    }
  } else {
    plots$undergrad <- NULL
    message("[headcount.R] No undergraduate data to plot")
  }

  # Graduate plot (CEDAR naming) - use flexible matching for graduate levels
  message("[headcount.R] Creating Graduate plot...")
  grad_data <- summarized[grepl("^Grad", summarized$student_level, ignore.case = TRUE), ]

  if (nrow(grad_data) > 0) {
    if (!has_program_type) {
      plots$graduate <- plot_ly(grad_data, x = ~term, y = ~student_count,
                                type = "bar", marker = list(color = unname(CEDAR_COLORS["green"])),
                                hovertemplate = "%{x}<br>Students: %{y}<extra></extra>") %>%
        layout(title = list(text = "Graduate Headcount", x = 0),
               xaxis = headcount_term_axis(term_levels, title = "Term"),
               yaxis = list(title = "Student Count"))
    } else if (no_program && !"degree" %in% colnames(grad_data)) {
      plots$graduate <- plot_ly(grad_data, x = ~term, y = ~student_count,
                                color = ~program_type,
                                colors = cedar_plotly_palette(grad_data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                                type = "bar",
                                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "stack",
               title  = list(text = "Graduate Headcount", x = 0),
               xaxis  = headcount_term_axis(term_levels, title = "Term"),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.2))
    } else {
      fill_col <- if ("degree" %in% colnames(grad_data)) ~degree
                  else if (!no_program && "program_name" %in% colnames(summarized)) ~program_name
                  else ~program_type
      fill_values <- if ("degree" %in% colnames(grad_data)) grad_data$degree
                     else if (!no_program && "program_name" %in% colnames(summarized)) grad_data$program_name
                     else grad_data$program_type
      grad_title <- if ("degree" %in% colnames(grad_data)) "Graduate Headcount by Degree Type"
                    else "Graduate Headcount"
      plots$graduate <- plot_ly(grad_data, x = ~term, y = ~student_count, color = fill_col,
                                colors = cedar_plotly_palette(fill_values),
                                type = "bar",
                                hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "stack",
               title  = list(text = grad_title, x = 0),
               xaxis  = headcount_term_axis(term_levels, title = "Term"),
               yaxis  = list(title = "Student Count"),
               legend = list(orientation = "h", x = 0, y = -0.2))
    }
  } else {
    plots$graduate <- NULL
    message("[headcount.R] No graduate data to plot")
  }

  message("[headcount.R] Returning ", length(plots), " plots")
  return(plots)
}


headcount_term_levels <- function(term) {
  term_axis_levels(term)
}


headcount_term_axis <- function(term_levels, title = NULL) {
  axis <- list(
    type = "category",
    categoryorder = "array",
    categoryarray = as.character(term_levels),
    tickangle = -45
  )

  if (!is.null(title)) {
    axis$title <- title
  }

  axis
}


#' Create Single Combined Headcount Plot
#'
#' Creates a single stacked bar chart showing enrollment across all programs and levels.
#'
#' @param summarized Summarized data frame from count_heads_by_program()
#'
#' @return Interactive plotly plot or NULL if no data
#'
#' @details
#' This is a simplified plotting function that creates a single view.
#' For more detailed analysis, use make_headcount_plots_by_level() instead.
#'
#' @export
make_headcount_plot <- function(summarized) {
  message("[headcount.R] Creating combined plot for ", nrow(summarized), " rows...")

  if (nrow(summarized) > 0) {
    term_levels <- headcount_term_levels(summarized$term)
    summarized$term <- term_axis_factor(summarized$term)

    message("[headcount.R] Creating plotly chart...")
    plot <- plot_ly(summarized, x = ~term, y = ~student_count, color = ~program_type,
                   colors        = cedar_plotly_palette(summarized$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                   type          = "bar",
                   hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
      layout(barmode = "stack",
             xaxis   = headcount_term_axis(term_levels, title = "Term"),
             legend  = list(orientation = "h", x = 0, y = -0.2))
  } else {
    plot <- NULL
    message("[headcount.R] No data to plot")
  }

  return(plot)
}


#' Headcount Sparkline for Department Dashboard
#'
#' Creates a compact static ggplot showing term-by-term headcount for a
#' department's major and minor programs. Faceted by student level
#' (Undergraduate / Graduate), with separate lines for Majors and Minors.
#' Summer terms are already excluded by \code{get_headcount_series()}.
#' Intended for embedding in the "Explore Your Unit" dashboard summary.
#'
#' @param series Data frame returned by \code{get_headcount_series()} in
#'   dept-dashboard.R. Columns: term, group, student_level_clean, program_cat, count.
#' @return A ggplot object, or NULL if series is NULL/empty.
#' @export
make_headcount_sparklines <- function(series) {
  message("[headcount.R] make_headcount_sparklines")

  if (is.null(series) || nrow(series) == 0) return(NULL)

  # Keep only levels that have data so we don't show empty facets
  levels_present <- unique(series$student_level_clean)
  if (length(levels_present) == 0) return(NULL)

  series <- series %>%
    dplyr::mutate(
      student_level_clean = factor(student_level_clean,
                                   levels = c("Undergraduate", "Graduate")),
      program_cat = factor(program_cat, levels = c("Majors", "Minors"))
    )

  # Build ordered factor from sorted unique terms
  term_labels <- term_axis_levels(series$term)

  series <- series %>%
    dplyr::mutate(term_label = factor(term_code_to_axis_label(term),
                                      levels = term_labels, ordered = TRUE))

  ggplot2::ggplot(series, ggplot2::aes(
    x     = term_label,
    y     = count,
    color = program_cat,
    group = program_cat
  )) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::facet_wrap(~ student_level_clean,
                        scales = "free_y",
                        ncol   = length(levels_present)) +
    ggplot2::scale_color_manual(
      values = cedar_plotly_palette(CEDAR_MAJOR_MINOR_ORDER),
      labels = c(Majors = "Majors (incl. 2nd)", Minors = "Minors"),
      name   = NULL
    ) +
    ggplot2::scale_y_continuous(labels = scales::comma_format(accuracy = 1)) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x      = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y      = ggplot2::element_text(size = 8),
      legend.position  = "top",
      legend.text      = ggplot2::element_text(size = 9),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(size = 10, face = "bold")
    )
}


#' Count Students by Program (Legacy Function)
#'
#' Legacy headcount function for backward compatibility with older code.
#' Uses mapped DEPT and PRGM codes for filtering.
#'
#' @param academic_studies_data Academic studies data with original column names
#' @param opt Options list with dept, prgm, and term filters
#'
#' @return Data frame with headcount summary
#'
#' @details
#' **DEPRECATED**: This function uses legacy column naming and mapping logic.
#' New code should use count_heads_by_program() with CEDAR-formatted data instead.
#'
#' This function:
#' 1. Pivots programs to long format
#' 2. Maps program names to PRGM and DEPT codes
#' 3. Filters by DEPT or PRGM
#' 4. Summarizes student counts
#'
#' @export
#' Generate Headcount Data and Plots for Department Reports
#'
#' Comprehensive function that generates all headcount data and visualizations
#' needed for department reports. Creates separate plots for undergraduate/graduate
#' and major/minor programs.
#'
#' @param programs Student program enrollment data in CEDAR format.
#'   Required columns: student_id, term, student_level, program_type, program_name.
#'   This is typically the academic_studies dataset with CEDAR naming.
#' @param dept_code Character. Department code for filtering (e.g., "HIST", "MATH").
#' @param term_start Integer. Starting term code for filtering (e.g., 201980).
#' @param term_end Integer. Ending term code for filtering (e.g., 202580).
#' @param opt Options list for filtering (passed to get_headcount).
#'   Can include filters for campus, college, etc. If empty, dept_code is used.
#'
#' @return List with structure:
#'   list(
#'     plots  = list(hc_progs_under_long_majors_plot, hc_progs_under_long_minors_plot,
#'                   hc_progs_grad_long_majors_plot,   hc_progs_grad_long_minors_plot),
#'     tables = list(hc_progs_under, hc_progs_under_long_majors, hc_progs_under_long_minors,
#'                   hc_progs_grad,  hc_progs_grad_long_majors,  hc_progs_grad_long_minors)
#'   )
#'
#' @details
#' **CEDAR Data Model Only**
#'
#' This function requires CEDAR-formatted data and will error if legacy column
#' names are provided. There are no fallbacks - CEDAR naming is mandatory.
#'
#' Workflow:
#' 1. Validates CEDAR column structure (errors with clear message if missing)
#' 2. Calls get_headcount() to get aggregated headcount data
#' 3. Filters by term range
#' 4. Splits into undergraduate/graduate and major/minor subsets
#' 5. Creates plotly plots for each subset
#' 6. Returns plots and tables as a plain list
#'
#' **Column Mappings (Legacy → CEDAR):**
#' - term_code → term
#' - Student Level → student_level
#' - major_type → program_type
#' - major_name → program_name
#'
#' @export
get_headcount_data_for_dept_report <- function(programs, dept_code, term_start, term_end,
                                               opt = list(), lookups = NULL) {
  message("[headcount.R] Welcome to get_headcount_data_for_dept_report!")

  # Validate CEDAR data structure
  required_cols <- c("student_id", "term", "student_level", "program_type", "program_name")
  missing_cols <- setdiff(required_cols, colnames(programs))
  if (length(missing_cols) > 0) {
    stop("[headcount.R] Missing required CEDAR columns in programs data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Run data transformation scripts to create CEDAR-formatted data.")
  }

  if (length(opt) == 0) {
    opt$dept_code <- dept_code
    message("[headcount.R] filtering by dept_code = ", dept_code)
  }

  # Get headcount data using CEDAR function
  message("[headcount.R] Counting heads with CEDAR data model...")
  result <- get_headcount(programs, opt, lookups = lookups)
  headcount <- result$data


  # Filter by term range (CEDAR: term not term_code)
  headcount_filtered <- headcount %>%
    filter(term >= term_start & term <= term_end)

  # Define program type groups
  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  tables <- list()
  plots  <- list()

  # UNDERGRADUATE data splits (CEDAR: student_level not `Student Level`)
  message("[headcount.R] Processing undergraduate data...")
  hc_progs_under <- headcount_filtered %>%
    filter(student_level == "Undergraduate")
  tables[["hc_progs_under"]] <- hc_progs_under

  hc_progs_under_long_majors <- hc_progs_under %>%
    filter(program_type %in% major_types & student_count > 0)
  tables[["hc_progs_under_long_majors"]] <- hc_progs_under_long_majors

  hc_progs_under_long_minors <- hc_progs_under %>%
    filter(program_type %in% minor_types & student_count > 0)
  tables[["hc_progs_under_long_minors"]] <- hc_progs_under_long_minors

  # GRADUATE data splits (CEDAR: student_level not `Student Level`)
  # Use ^Grad to match only strings STARTING with "Grad" (not "Undergraduate" which contains "grad")
  message("[headcount.R] Processing graduate data...")
  grad_levels <- unique(headcount_filtered$student_level[grepl("^Grad", headcount_filtered$student_level, ignore.case = TRUE)])
  message("[headcount.R] Detected graduate levels: ", paste(grad_levels, collapse = ", "))
  hc_progs_grad <- headcount_filtered %>%
    filter(grepl("^Grad", student_level, ignore.case = TRUE))
  tables[["hc_progs_grad"]] <- hc_progs_grad

  hc_progs_grad_long_majors <- hc_progs_grad %>%
    filter(program_type %in% major_types & student_count > 0)
  tables[["hc_progs_grad_long_majors"]] <- hc_progs_grad_long_majors

  hc_progs_grad_long_minors <- hc_progs_grad %>%
    filter(program_type %in% minor_types & student_count > 0)
  tables[["hc_progs_grad_long_minors"]] <- hc_progs_grad_long_minors

  # CREATE PLOTS for each data subset
  message("[headcount.R] Creating plots...")

  plot_names <- c("hc_progs_under_long_majors",
                  "hc_progs_under_long_minors",
                  "hc_progs_grad_long_majors",
                  "hc_progs_grad_long_minors")

  for (data_name in plot_names) {
    data <- tables[[data_name]]

    if (!is.null(data) && nrow(data) > 0) {
      message("[headcount.R] Creating plot for ", data_name)

      data$term <- term_axis_factor(data$term)

      # CEDAR: use term not term_code, program_type not major_type, student_count not students
      plot <- plot_ly(data, x = ~term, y = ~student_count, color = ~program_type,
                      colors        = cedar_plotly_palette(data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
                      type          = "bar",
                      hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>") %>%
        layout(barmode = "stack",
               xaxis   = list(tickangle = -45),
               legend  = list(orientation = "h", x = 0, y = -0.2))

      plots[[paste0(data_name, "_plot")]] <- plot
    } else {
      message("[headcount.R] No data for ", data_name, " - skipping plot")
    }
  }

  message("[headcount.R] Returning ", length(tables), " tables and ", length(plots), " plots")
  list(plots = plots, tables = tables)
}
