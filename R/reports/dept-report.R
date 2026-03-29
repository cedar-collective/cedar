#' Department Report Generation for CEDAR
#'
#' @description
#' This file contains functions for generating comprehensive department reports.
#' Reports include headcount, degrees, credit hours, grades (DFW), enrollment, and SFR analysis.
#'
#' @section Functions:
#'
#' **Core Functions:**
#' - `set_payload()` - Build department config (dept metadata, program codes, term range)
#' - `create_dept_report_data()` - Generate all plots/tables for interactive reports (used by Shiny)
#' - `create_dept_report()` - Generate full RMarkdown HTML reports (batch processing)
#'
#' @section Data Requirements:
#'
#' **data_objects list must contain:**
#' - `academic_studies` - Student program enrollment data (for headcount)
#' - `degrees` - Graduate data with CEDAR naming (for degrees analysis)
#' - `class_lists` - Course enrollment data (for credit hours, grades)
#' - `cedar_faculty` - Faculty HR data with CEDAR naming (for SFR, DFW by instructor type)
#' - `DESRs` - Demand-enrollment data (for enrollment trends)
#'
#' @section Usage:
#'
#' ```r
#' # Interactive report (for Shiny)
#' opt <- list(dept = "HIST", prog = NULL, shiny = TRUE)
#' d_params <- create_dept_report_data(data_objects, opt)
#'
#' # HTML report (RMarkdown)
#' opt <- list(dept = "HIST", output = "html")
#' create_dept_report(data_objects, opt)
#' ```
#'
#' @name dept-report
NULL

#' Initialize Department Report Parameters
#'
#' @description
#' Builds a pure department config list from global maps and config values.
#' Used by `create_dept_report_data()` as the first step in report generation.
#'
#' @param dept_code Character. Department code (e.g., "HIST", "MATH")
#' @param prog_focus Character or NULL. Optional program code to restrict to
#'   a single program within the department (e.g., "HIST" for History major only)
#'
#' @return Named list of department config (no output slots):
#'   - `dept_code` - Department code
#'   - `dept_name` - Full department name
#'   - `subj_codes` - Subject codes associated with department
#'   - `prog_focus` - Program focus (if specified)
#'   - `prog_codes` - Program codes
#'   - `term_start` - Start term from config
#'   - `term_end` - End term from config
#'   - `palette` - Color palette from config
#'
#' @details
#' Uses global mapping variables:
#' - `major_to_dept` - Maps major codes to departments
#' - `subj_to_dept` - Maps subject codes to departments
#' - `dept_code_to_name` - Maps department codes to full names
#'
#' @examples
#' \dontrun{
#' # All programs in History department
#' d_params <- set_payload("HIST")
#'
#' # Focus on specific program
#' d_params <- set_payload("HIST", prog_focus = "HIST")
#' }
#'
#' @export
set_payload <- function (dept_code, prog_focus = NULL) {
  message("[dept-report.R] Welcome to set_payload!")
  message("[dept-report.R] Received dept_code: ", dept_code)
  
  # set program codes
  message("[dept-report.R] Setting program codes and names from mappings.R...")

# if program focus specified
  if (!is.null(prog_focus)) {
    prog_codes <- prog_focus
  } else {
    # get all major codes associated with the dept
    prog_codes <- names(major_to_dept)[major_to_dept == dept_code]
    message("[dept-report.R] prog_codes: ", paste(prog_codes, collapse=", "))
  }
  
  
  message("[dept-report.R] building dept config...")
  cfg <- list(
    dept_code  = dept_code,
    dept_name  = dept_code_to_name[dept_code],
    subj_codes = names(subj_to_dept[which(subj_to_dept == dept_code)]),
    prog_focus = prog_focus,
    prog_codes = prog_codes,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = cedar_report_palette
  )

  message("[dept-report.R] returning cfg set as:\n",
        paste(capture.output(str(cfg, max.level = 1)), collapse = "\n"))

  return(cfg)
}


#' Generate Department Report Data (Interactive)
#'
#' @description
#' Generates all tables and plots for department reports by calling individual
#' cone functions (headcount, degrees, credit hours, grades, enrollment, SFR).
#' This function is used by the Shiny app for interactive report generation.
#'
#' @param data_objects List containing required data sources:
#'   - `academic_studies` - Student program enrollment (headcount)
#'   - `degrees` - Graduate data with CEDAR naming (cedar_degrees)
#'   - `class_lists` - Course enrollment data (credit hours, grades)
#'   - `cedar_faculty` - Faculty HR data with CEDAR naming (SFR, DFW analysis)
#'   - `DESRs` - Demand-enrollment data (enrollment trends)
#' @param opt Options list with:
#'   - `dept` (required) - Department code (e.g., "HIST")
#'   - `prog` (optional) - Program focus code
#'   - `shiny` (optional) - Boolean indicating Shiny context
#'
#' @return Named list combining department config with all outputs:
#'   - All fields from `set_payload()` (dept_code, dept_name, subj_codes, etc.)
#'   - `tables` - Named list of data frames from all analyses
#'   - `plots` - Named list of plotly/ggplot objects from all analyses
#'
#' @details
#' **Processing workflow:**
#' 1. Calls `set_payload()` to build department config
#' 2. Headcount: `get_headcount_data_for_dept_report()`
#' 3. Degrees: `get_degrees_for_dept_report()`
#' 4. Credit Hours: `get_credit_hours_for_dept_report()`, `credit_hours_by_major()`, `credit_hours_by_fac()`
#' 5. Grades: `get_grades_for_dept_report()` (DFW analysis)
#' 6. Enrollment: `get_enrl_for_dept_report()`
#' 7. SFR: `get_sfr_data_for_dept_report()`
#'
#' **CEDAR Migration Notes:**
#' - Uses CEDAR dataset keys exclusively: cedar_faculty, cedar_students, cedar_programs, cedar_sections, cedar_degrees
#' - No legacy fallbacks; all data must be in CEDAR format with lowercase column names
#' - Requires `department` column (CEDAR) in cedar_students for filtering
#'
#' **Typical outputs include:**
#' - Headcount tables/plots by program and level
#' - Degree award trends by major and type
#' - Credit hour production by term
#' - DFW rates by course and instructor type
#' - Enrollment trends by term type
#' - Student-faculty ratios over time
#'
#' @examples
#' \dontrun{
#' # Load data (CEDAR naming only)
#' data_objects <- list(
#'   cedar_programs = readRDS(paste0(cedar_data_dir, "cedar_programs.Rds")),
#'   cedar_degrees = readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds")),
#'   cedar_students = readRDS(paste0(cedar_data_dir, "cedar_students.Rds")),
#'   cedar_faculty = readRDS(paste0(cedar_data_dir, "cedar_faculty.Rds")),
#'   cedar_sections = readRDS(paste0(cedar_data_dir, "cedar_sections.Rds"))
#' )
#'
#' # Generate report data
#' opt <- list(dept = "HIST", shiny = TRUE)
#' d_params <- create_dept_report_data(data_objects, opt)
#'
#' # Access outputs
#' names(d_params$tables)
#' names(d_params$plots)
#' d_params$plots$degree_summary_faceted_by_major_plot
#' }
#'
#' @seealso
#' \code{\link{set_payload}}, \code{\link{create_dept_report}} for HTML generation
#'
#' @export
create_dept_report_data <- function(data_objects, opt) {
  message("[dept-report.R] Welcome to create_dept_report_data!")

  # Validate CEDAR data structure (CEDAR naming only, no legacy fallbacks)
  message("[dept-report.R] Validating CEDAR data objects...")
  required_datasets <- c("cedar_students", "cedar_degrees", "cedar_sections", "cedar_faculty", "cedar_programs")
  missing_datasets <- setdiff(required_datasets, names(data_objects))

  if (length(missing_datasets) > 0) {
    stop("[dept-report.R] Missing required CEDAR datasets: ", paste(missing_datasets, collapse = ", "),
         "\n  Found data_objects keys: ", paste(names(data_objects), collapse = ", "),
         "\n  All CEDAR datasets must be loaded before generating reports.")
  }

  message("[dept-report.R] All required CEDAR datasets present")
  message("[dept-report.R] cedar_faculty rows: ", nrow(data_objects[["cedar_faculty"]]))

  
  # try to resolve incoming dept to dept code
  # originally, dept code was passed in, like "HIST"
  # but now may be value from Department column, like "History" or "AS Anthropology"
  # look up dept code from dept name if needed
  incoming_dept <- opt[["dept"]]
  if (incoming_dept %in% names(hr_org_desc_to_dept)) {
    dept_code <- hr_org_desc_to_dept[[incoming_dept]]
    message("[dept-report.R] Resolved incoming HR org desc '", incoming_dept, "' to dept code '", dept_code, "'")
  }
  else {
    message("[dept-report.R] WARNING: Using raw incoming dept code: ", incoming_dept)
    dept_code <- opt[["dept"]]
  }
  
  # set prog_focus in case report should focus on specific program
  prog_focus <- opt[["prog"]]

  # initialize payload
  cfg <- set_payload(dept_code, prog_focus)
  cfg[["dept_raw"]] <- incoming_dept

  # Apply campus filter if provided — filter both students and sections so all
  # downstream branches see only the requested campus(es). R passes lists by
  # value, so this modifies a local copy; global data_objects is unchanged.
  campus_filter <- opt[["campus"]]
  if (!is.null(campus_filter) && length(campus_filter) > 0) {
    message("[dept-report.R] Filtering to campus: ", paste(campus_filter, collapse = ", "))
    data_objects[["cedar_students"]] <- data_objects[["cedar_students"]] %>%
      filter(campus %in% campus_filter)
    data_objects[["cedar_sections"]] <- data_objects[["cedar_sections"]] %>%
      filter(campus %in% campus_filter)
  }

  plots  <- list()
  tables <- list()

  ####### HEADCOUNT
  message("[dept-report.R] About to call get_headcount_data_for_dept_report...")
  hc <- get_headcount_data_for_dept_report(
    data_objects[["cedar_programs"]],
    cfg$dept_code, cfg$term_start, cfg$term_end
  )
  plots  <- c(plots,  hc$plots)
  tables <- c(tables, hc$tables)
  message("[dept-report.R] Completed headcount data processing")

  ####### DEGREES
  message("[dept-report.R] About to call get_degrees_for_dept_report...")
  deg <- get_degrees_for_dept_report(
    data_objects[["cedar_degrees"]],
    cfg$dept_name, cfg$prog_codes, cfg$term_start, cfg$term_end, cfg$palette
  )
  plots  <- c(plots,  deg$plots)
  tables <- c(tables, deg$tables)
  message("[dept-report.R] Completed degrees data processing")

  ####### CREDIT HOURS
  message("[dept-report.R] About to filter cedar_students by dept_code...")
  # CEDAR naming required - no fallbacks
  if (!"department" %in% colnames(data_objects[["cedar_students"]])) {
    stop("[dept-report.R] cedar_students missing required CEDAR column: 'department'\n",
         "  Expected CEDAR format with lowercase column names.\n",
         "  Found columns: ", paste(colnames(data_objects[["cedar_students"]]), collapse = ", "))
  }

  message("[dept-report.R] Using CEDAR column: department, filtering by dept_code: ", dept_code)
  filtered_cl_by_dept <- data_objects[["cedar_students"]] %>%
    filter(department == dept_code)

  message("[dept-report.R] Calling get_credit_hours_for_dept_report...")
  sch_college <- get_credit_hours_for_dept_report(
    data_objects[["cedar_students"]],
    cfg$dept_code, cfg$subj_codes, cfg$term_start, cfg$term_end, cfg$palette
  )
  plots  <- c(plots,  sch_college$plots)
  tables <- c(tables, sch_college$tables)

  message("[dept-report.R] Calling credit_hours_by_major...")
  sch_major <- credit_hours_by_major(
    filtered_cl_by_dept,
    cfg$dept_code, cfg$term_start, cfg$term_end
  )
  plots  <- c(plots,  sch_major$plots)
  tables <- c(tables, sch_major$tables)

  message("[dept-report.R] Calling credit_hours_by_fac...")
  sch_fac <- credit_hours_by_fac(
    data_objects,
    cfg$dept_code, cfg$subj_codes, cfg$term_start, cfg$term_end, cfg$palette
  )
  plots <- c(plots, sch_fac$plots)

  ####### GRADES
  message("[dept-report.R] About to call get_grades_for_dept_report...")
  # CEDAR naming required - no fallbacks
  if (!"cedar_faculty" %in% names(data_objects)) {
    stop("[dept-report.R] data_objects missing required 'cedar_faculty' dataset\n",
         "  Expected CEDAR format with cedar_faculty key.\n",
         "  Run transform-hr-to-cedar.R to create cedar_faculty from hr_data.\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  if (is.null(data_objects[["cedar_faculty"]])) {
    stop("[dept-report.R] cedar_faculty dataset is NULL\n",
         "  Load cedar_faculty.Rds or run transform-hr-to-cedar.R")
  }

  message("[dept-report.R] Using CEDAR faculty data: cedar_faculty")
  gr <- get_grades_for_dept_report(filtered_cl_by_dept, data_objects[["cedar_faculty"]], cfg$dept_code, opt)
  plots  <- c(plots,  gr$plots)
  tables <- c(tables, gr$tables)
  message("[dept-report.R] Completed grades data processing")

  ####### ENROLLMENT
  message("[dept-report.R] About to call get_enrl_for_dept_report...")
  enrl <- get_enrl_for_dept_report(data_objects[["cedar_sections"]], cfg$dept_code, cfg$palette, cfg$term_start, cfg$term_end)
  plots  <- c(plots,  enrl$plots)
  tables <- c(tables, enrl$tables)
  message("[dept-report.R] Completed enrollment data processing")

  ####### SFRs
  message("[dept-report.R] About to call get_sfr_data_for_dept_report...")
  sfr <- get_sfr_data_for_dept_report(data_objects, cfg$dept_code)
  plots <- c(plots, sfr$plots)
  message("[dept-report.R] Completed SFR data processing")

  message("[dept-report.R] Returning report data")
  c(cfg, list(plots = plots, tables = tables))
}


# Rebuild all dept report plots from cached tables + cfg fields.
# Called on cache hit so that only the (fast) ggplot/ggplotly work happens,
# not the expensive data joins. Returns a named list of plots identical in
# structure to the $plots list produced by create_dept_report_data.
rebuild_dept_report_plots <- function(cached_data) {
  message("[dept-report.R] rebuild_dept_report_plots: rebuilding plots from cached tables")
  plots  <- list()
  tables <- cached_data$tables

  palette    <- cached_data$palette
  dept_code  <- cached_data$dept_code
  subj_codes <- cached_data$subj_codes
  term_start <- cached_data$term_start
  term_end   <- cached_data$term_end
  dept_name  <- cached_data$dept_name

  # --- HEADCOUNT ---
  tryCatch({
    plot_names <- c("hc_progs_under_long_majors", "hc_progs_under_long_minors",
                    "hc_progs_grad_long_majors",  "hc_progs_grad_long_minors")
    for (data_name in plot_names) {
      data <- tables[[data_name]]
      if (!is.null(data) && nrow(data) > 0) {
        data$term <- as.factor(data$term)
        p <- data %>%
          ggplot(aes(x = term, y = student_count)) +
          theme(legend.position = "bottom") +
          guides(color = guide_legend(title = "")) +
          geom_bar(aes(fill = program_type), position = "stack", stat = "identity") +
          theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1))
        p <- ggplotly(p) %>%
          layout(legend = list(orientation = 'h', x = 0.3, y = -.3),
                 xaxis  = list(standoff = -1))
        plots[[paste0(data_name, "_plot")]] <- p
      }
    }
    message("[dept-report.R] rebuild: headcount done")
  }, error = function(e) message("[dept-report.R] rebuild headcount failed: ", e$message))

  # --- DEGREES ---
  tryCatch({
    deg_filtered <- tables[["degree_summary_filtered"]]
    deg_by_prog  <- tables[["degree_summary_filtered_program"]]
    if (!is.null(deg_filtered) && nrow(deg_filtered) > 0) {
      p1 <- ggplot(deg_filtered, aes(x = term, y = majors, col = degree)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_line(aes(group = degree)) +
        geom_point(aes(group = degree), alpha = .8) +
        facet_wrap(~major, ncol = 3) +
        scale_color_brewer(palette = palette) +
        xlab("Term") + ylab("Degrees Awarded")
      plots[["degree_summary_faceted_by_major_plot"]] <- ggplotly(p1)
    }
    if (!is.null(deg_by_prog) && nrow(deg_by_prog) > 0) {
      p2 <- deg_by_prog %>%
        mutate(degree = fct_reorder(degree, majors_total), term = as.factor(term)) %>%
        ggplot(aes(x = term, y = majors_total, fill = degree)) +
        ggtitle(dept_name) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_bar(position = "stack", stat = "identity") +
        scale_fill_brewer(palette = palette, limits = unique(deg_by_prog$degree)) +
        xlab("Term") + ylab("Degrees Awarded")
      plots[["degree_summary_filtered_program_stacked_plot"]] <- ggplotly(p2)
    }
    message("[dept-report.R] rebuild: degrees done")
  }, error = function(e) message("[dept-report.R] rebuild degrees failed: ", e$message))

  # --- GRADES ---
  tryCatch({
    dfw_avg   <- tables[["dfw_summary_by_course_avg"]]
    inst_data <- tables[["instructor_data"]]
    if (!is.null(dfw_avg) && nrow(dfw_avg) > 0) {
      inst_data <- if (!is.null(inst_data))
        inst_data %>% filter(!is.na(instructor_last_name) & instructor_last_name != "")
      else
        data.frame()
      course_levels <- dfw_avg %>% arrange(subject_course) %>% pull(subject_course) %>% unique()
      p <- dfw_avg %>%
        mutate(subject_course = factor(subject_course, levels = course_levels)) %>%
        ggplot(aes(y = subject_course, x = dfw_pct, fill = campus,
                   text = paste("Course:", subject_course,
                               "<br>Campus:", campus,
                               "<br>DFW %:", dfw_pct))) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_bar(stat = "identity", position = position_dodge(), alpha = 0.7)
      if (nrow(inst_data) > 0) {
        p <- p + geom_point(
          data = inst_data %>% mutate(subject_course = factor(subject_course, levels = course_levels)),
          aes(x = dfw_pct, y = subject_course, color = campus,
              text = paste("Instructor:", instructor_last_name,
                          "<br>Course:", subject_course,
                          "<br>Campus:", campus,
                          "<br>DFW %:", dfw_pct,
                          "<br>Sections Taught:", sections_taught)),
          position = position_jitter(height = 0.2, width = 0), size = 2, alpha = 0.8)
      }
      p <- p + ylab("Course") + xlab("mean DFW %") +
        labs(caption = "Bars show course averages; dots show individual instructor averages")
      plots[["grades_summary_for_ld_abq_ea_plot"]] <- ggplotly(p, tooltip = "text")
    }
    message("[dept-report.R] rebuild: grades done")
  }, error = function(e) message("[dept-report.R] rebuild grades failed: ", e$message))

  # --- ENROLLMENT ---
  tryCatch({
    enrl_summary <- tables[["enrl_summary"]]
    if (!is.null(enrl_summary) && nrow(enrl_summary) > 0) {
      start_yr     <- as.integer(substr(as.character(term_start), 1, 4))
      end_yr       <- as.integer(substr(as.character(term_end),   1, 4))
      window_label <- if (start_yr == end_yr) as.character(start_yr) else paste0(start_yr, "\u2013", end_yr)

      highest_total <- enrl_summary %>% ungroup() %>% arrange(desc(enrolled))  %>% slice_head(n = 10)
      highest_mean  <- enrl_summary %>% ungroup() %>% arrange(desc(avg_size))  %>% slice_head(n = 10)
      all_by_avg    <- enrl_summary %>% ungroup() %>% arrange(desc(avg_size))

      plots[["highest_total_enrl_plot"]] <- highest_total %>%
        mutate(course_title = fct_reorder(course_title, enrolled)) %>%
        ggplot(aes(y = course_title, x = enrolled)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_bar(stat = "identity") +
        ylab("Course") + xlab(paste0("Total Enrollment (", window_label, ")"))

      plots[["highest_mean_enrl_plot"]] <- highest_mean %>%
        mutate(course_title = fct_reorder(course_title, avg_size)) %>%
        ggplot(aes(y = course_title, x = avg_size)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_bar(stat = "identity") +
        ylab("Course") + xlab(paste0("Mean Section Size (", window_label, ")"))

      p3 <- all_by_avg %>%
        mutate(course_title = fct_reorder(course_title, avg_size)) %>%
        ggplot(aes(x = avg_size)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "")) +
        geom_histogram(aes(fill = level), bins = 30) +
        scale_fill_brewer(palette = palette) +
        ylab("Number of courses") + xlab(paste0("Avg section size (", window_label, ")"))
      plots[["highest_mean_histo_plot"]] <- ggplotly(p3) %>%
        layout(legend = list(orientation = 'h', x = 0.3, y = -.3),
               xaxis  = list(standoff = -1))
    }
    message("[dept-report.R] rebuild: enrollment done")
  }, error = function(e) message("[dept-report.R] rebuild enrollment failed: ", e$message))

  # --- CREDIT HOURS FOR DEPT ---
  tryCatch({
    chd_col  <- tables[["chd_college"]]
    chd_diff <- tables[["chd_diff_fr_college"]]
    chd_idx  <- tables[["chd_indexed"]]
    chd_sl   <- tables[["chd_by_subj_level"]]
    chd_st   <- tables[["chd_by_subj_total"]]
    chd_per  <- tables[["chd_by_period_data"]]
    if (!is.null(chd_col))  plots[["college_credit_hours_plot"]]      <- plot_college_credit_hours(chd_col)
    if (!is.null(chd_diff)) plots[["college_credit_hours_comp_plot"]] <- plot_college_comp(chd_diff)
    if (!is.null(chd_idx))  plots[["college_dept_dual_plot"]]         <- plot_indexed_growth(chd_idx, dept_code)
    if (!is.null(chd_sl))   plots[["chd_by_year_facet_subj_plot"]]    <- plot_chd_by_subj_faceted(chd_sl, palette)
    if (!is.null(chd_st))   plots[["chd_by_year_subj_plot"]]          <- plot_chd_by_subj_stacked(chd_st)
    if (!is.null(chd_per))  plots[["chd_by_period_plot"]]             <- plot_chd_by_level(chd_per, subj_codes, palette)
    message("[dept-report.R] rebuild: credit hours for dept done")
  }, error = function(e) message("[dept-report.R] rebuild credit hours for dept failed: ", e$message))

  # --- CREDIT HOURS BY MAJOR ---
  tryCatch({
    rebuild_major_level <- function(sfx, level_label) {
      top_out  <- tables[[paste0("sch_top_outside_", sfx)]]
      cmap     <- tables[[paste0("sch_color_map_",   sfx)]]
      tdata    <- tables[[paste0("sch_time_data_",   sfx)]]
      spl      <- tables[[paste0("sch_split_",       sfx)]]
      list(
        outside_plot = if (!is.null(top_out) && !is.null(cmap) && nrow(top_out) > 0)
          plot_outside_majors_pie(top_out, cmap, level_label) else NULL,
        dept_plot = if (!is.null(spl) && !is.na(spl[["total"]]) && spl[["total"]] > 0)
          plot_home_outside_pie(spl[["home"]], spl[["outside"]], spl[["total"]], level_label) else NULL,
        time_plot = if (!is.null(tdata) && !is.null(cmap) && nrow(tdata) > 0)
          plot_outside_time_series(tdata, cmap, level_label) else NULL
      )
    }
    lwr <- rebuild_major_level("lower", "Lower Division")
    upr <- rebuild_major_level("upper", "Upper Division")
    aug <- rebuild_major_level("all_ug", "All Undergrad")
    plots[["sch_outside_pct_lower_plot"]] <- lwr$outside_plot
    plots[["sch_dept_pct_lower_plot"]]    <- lwr$dept_plot
    plots[["sch_top_majors_lower_plot"]]  <- lwr$time_plot
    plots[["sch_outside_pct_upper_plot"]] <- upr$outside_plot
    plots[["sch_dept_pct_upper_plot"]]    <- upr$dept_plot
    plots[["sch_top_majors_upper_plot"]]  <- upr$time_plot
    plots[["sch_outside_pct_plot"]]       <- aug$outside_plot
    plots[["sch_dept_pct_plot"]]          <- aug$dept_plot
    message("[dept-report.R] rebuild: credit hours by major done")
  }, error = function(e) message("[dept-report.R] rebuild credit hours by major failed: ", e$message))

  # --- CREDIT HOURS BY FAC ---
  tryCatch({
    fac_lvl <- tables[["chd_fac_by_level"]]
    fac_tot <- tables[["chd_fac_by_total"]]
    subj_title <- paste0("Subject codes: ", paste(subj_codes, collapse = ", "))
    if (!is.null(fac_lvl) && nrow(fac_lvl) > 0) {
      plots[["chd_by_fac_facet_plot"]] <- ggplot(fac_lvl, aes(x = term, y = total_hours)) +
        ggtitle(subj_title) +
        theme(legend.position = "bottom") +
        geom_bar(aes(fill = job_category), stat = "identity", position = "dodge") +
        facet_wrap(~level) +
        scale_fill_brewer(palette = palette) +
        theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1)) +
        xlab("Academic Period") + ylab("Credit Hours")
    }
    if (!is.null(fac_tot) && nrow(fac_tot) > 0) {
      plots[["chd_by_fac_plot"]] <- ggplot(fac_tot, aes(x = term, y = total_hours)) +
        ggtitle(subj_title) +
        theme(legend.position = "bottom") +
        geom_bar(aes(fill = job_category), stat = "identity", position = "stack") +
        scale_fill_brewer(palette = palette) +
        xlab("Academic Period") + ylab("Credit Hours")
    }
    message("[dept-report.R] rebuild: credit hours by fac done")
  }, error = function(e) message("[dept-report.R] rebuild credit hours by fac failed: ", e$message))

  # --- SFR ---
  tryCatch({
    ug_sfr           <- tables[["sfr_ug"]]
    grad_sfr         <- tables[["sfr_grad"]]
    sfr_college      <- tables[["sfr_college"]]
    sfr_college_dept <- tables[["sfr_college_dept"]]

    if (!is.null(ug_sfr) && nrow(ug_sfr) > 0) {
      plots[["ug_sfr_plot"]] <- ggplot(ug_sfr, aes(x = term)) +
        guides(color = guide_legend(title = "")) +
        theme(legend.position = "bottom") +
        labs(fill = "", color = "Comparison") +
        geom_bar(aes(y = sfr, fill = program_type), stat = "identity", position = "dodge") +
        xlab("Term") + ylab("Students per Faculty Member")
    }

    if (!is.null(grad_sfr) && nrow(grad_sfr) > 0) {
      plots[["grad_sfr_plot"]] <- ggplot(grad_sfr, aes(x = term)) +
        guides(color = guide_legend(title = "")) +
        theme(legend.position = "bottom") +
        geom_bar(aes(y = sfr, fill = program_type), stat = "identity", position = "dodge") +
        xlab("Term") + ylab("Students per Faculty Member")
    }

    if (!is.null(sfr_college_dept) && nrow(sfr_college_dept) > 0 && !is.null(sfr_college)) {
      sfr_scatter <- ggplot(sfr_college, aes(x = term, y = sfr)) +
        theme(legend.position = "bottom") +
        guides(color = guide_legend(title = "", color = "")) +
        geom_point(alpha = .5) +
        geom_line(alpha = .2, aes(group = dept_code)) +
        geom_point(sfr_college_dept, mapping = aes(x = term, y = sfr, color = program_name)) +
        geom_line(sfr_college_dept,  mapping = aes(x = term, y = sfr, color = program_name, group = program_name)) +
        xlab("Semester") + ylab("Students per Faculty")
      if (dept_code != "PSYC") sfr_scatter <- sfr_scatter + coord_cartesian(ylim = c(0, 50))
      plots[["sfr_scatterplot"]] <- sfr_scatter
    }
    message("[dept-report.R] rebuild: SFR done")
  }, error = function(e) message("[dept-report.R] rebuild SFR failed: ", e$message))

  message("[dept-report.R] rebuild_dept_report_plots complete: ", length(plots), " plots")
  plots
}


create_dept_report <- function (data_objects,opt) {
  
  message("[dept-report.R] Welcome to create_dept_report!")

  gc()  # clean up memory before starting

  # for studio testing...
  #opt <- list()
  #opt$output <- "html"
  #opt$dept <- "LCL"
  #opt$prog <- ""
  
# convert dept param to dept_list for processing
  dept_list <- convert_param_to_list(opt[["dept"]]) 
  
  # loop through each unit in dept list
  for (dept in dept_list) {
    # for studio testing a single dept
    #dept <- "AMST"
    message("[dept-report.R] looking at dept: ", dept)
    message("[dept-report.R] length: ", length(dept))

    dept_code <- ""
    prog_focus <- NULL
    
    if (length(dept) == 2) {
      dept_code <- unlist(dept)[1]
      prog_focus <- unlist(dept)[2]
    } else {
      dept_code <- dept
      prog_focus <- NULL
    }
  
    # set dept_code and prog_focus
    opt[["dept"]] <- dept_code
    opt[["prog"]] <- prog_focus

    # get dept report data
    message("[dept-report.R] about to call create_dept_report_data...")
    d_params <- create_dept_report_data(data_objects, opt)

    # set output_filename using raw incoming dept (not resolved dept_code)
    # This ensures filename matches what was passed from UI/CLI
    message("[dept-report.R] setting output filename...")
    if (!is.null(d_params$prog_focus) && !is.na(d_params$prog_focus)) {
      output_filename <- paste0(d_params$dept_raw, "-", d_params$prog_focus)
    } else {
      output_filename <- d_params$dept_raw
    }
    # Sanitize filename (replace spaces/special chars)
    output_filename <- gsub(" ", "_", output_filename)
    message("[dept-report.R] output_filename: ", output_filename)
    
    d_params$output_filename <- output_filename
    d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
    d_params$output_dir_base <- file.path(cedar_output_dir, "dept-reports")
    
    # create report (defined in utils.R)
    create_report(opt, d_params)
  
  } # end of dept loop
  message("[dept-report.R] Completed create_dept_report for all departments!")
  return("dept-report success!")
}

