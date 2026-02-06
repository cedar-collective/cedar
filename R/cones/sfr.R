#' Get Permanent Faculty Count from CEDAR Faculty Table
#'
#' Calculates FTE (full-time equivalent) counts for permanent faculty by summing
#' appointment percentages. Uses the cedar_faculty table with normalized CEDAR
#' column names.
#'
#' @param cedar_faculty Data frame from cedar_faculty table with columns:
#'   term, department, job_category, appointment_pct
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{term} - Term code
#'     \item \code{department} - Department code (lowercase)
#'     \item \code{total} - FTE count (sum of appointment percentages)
#'   }
#'   Returns NULL if cedar_faculty is NULL, empty, or missing required columns.
#'
#' @details
#' Permanent faculty categories included in FTE calculation:
#' \itemize{
#'   \item professor
#'   \item associate_professor
#'   \item assistant_professor
#'   \item lecturer
#' }
#'
#' Excluded categories (non-permanent):
#' \itemize{
#'   \item term_teacher
#'   \item tpt (temporary part-time)
#'   \item grad (graduate assistants)
#'   \item professor_emeritus
#' }
#'
#' FTE calculation example: A professor at 100% appointment + a lecturer at
#' 50% appointment = 1.5 FTE for that department/term.
#'
#' @examples
#' \dontrun{
#' # Calculate permanent faculty FTE
#' perm_fac <- get_perm_faculty_count(cedar_faculty)
#'
#' # View FTE by department for recent term
#' perm_fac %>% filter(term == 202510) %>% arrange(desc(total))
#' }
#'
#' @seealso \code{\link{get_sfr}} for student-faculty ratio calculation
get_perm_faculty_count <- function(cedar_faculty) {

  # Check if we have faculty data
  if (is.null(cedar_faculty) || nrow(cedar_faculty) == 0) {
    message("[sfr.R] No cedar_faculty data found or cedar_faculty is empty")
    return(NULL)
  }

  message("[sfr.R] cedar_faculty has ", nrow(cedar_faculty), " rows")
  message("[sfr.R] cedar_faculty columns: ", paste(colnames(cedar_faculty), collapse=", "))

  # Check for required columns (CEDAR lowercase naming)
  required_cols <- c("term", "department", "job_category", "appointment_pct")
  missing_cols <- required_cols[!required_cols %in% colnames(cedar_faculty)]
  if (length(missing_cols) > 0) {
    message("[sfr.R] ERROR: Missing required columns: ", paste(missing_cols, collapse=", "))
    return(NULL)
  }

  # Sum appointment percentages by term, department, and job category
  fac_by_term_counts <- cedar_faculty %>%
    group_by(term, department, job_category) %>%
    summarize(count = sum(appointment_pct, na.rm = TRUE), .groups = "drop")

  # Only count permanent faculty in ratio calcs
  # Match actual job_category values from cedar_faculty data
  perm_fac_count <- fac_by_term_counts %>%
    filter(job_category %in% c("Professor", "Lecturer", "Associate Professor", "Assistant Professor"))

  message("[sfr.R] After filtering for permanent faculty: ", nrow(perm_fac_count), " rows")

  if (nrow(perm_fac_count) == 0) {
    message("[sfr.R] ERROR: No permanent faculty found after filtering")
    message("[sfr.R] Available job_category values: ", paste(unique(fac_by_term_counts$job_category), collapse=", "))
    return(NULL)
  }

  # Aggregate by term and department (summing across all permanent job categories)
  # Divide by 100 to convert from percentage (0-100) to FTE count
  perm_fac_count <- perm_fac_count %>%
    group_by(term, department) %>%
    summarize(total = sum(count, na.rm = TRUE) / 100, .groups = "drop")

  message("[sfr.R] Returning perm_fac_count with ", nrow(perm_fac_count), " rows")

  return(perm_fac_count)
}


#' Calculate Student-Faculty Ratios
#'
#' Calculates student-faculty ratios (SFR) by merging headcount data with
#' permanent faculty FTE counts. Separates majors and minors for detailed
#' analysis.
#'
#' @param data_objects Named list containing:
#'   \itemize{
#'     \item \code{academic_studies} - Academic study data for headcount calculation
#'     \item \code{cedar_faculty} - CEDAR faculty table with normalized columns
#'   }
#'
#' @return Data frame with columns:
#'   \itemize{
#'     \item \code{term} - Term code (CEDAR naming)
#'     \item \code{department} - Department code (CEDAR naming, lowercase)
#'     \item \code{student_level} - Student level (Undergraduate/Graduate/GASM)
#'     \item \code{program_type} - Type: "all_majors" or "all_minors"
#'     \item \code{program_name} - Program name
#'     \item \code{total} - Faculty FTE count
#'     \item \code{students} - Student headcount
#'     \item \code{sfr} - Student-faculty ratio (students/total)
#'   }
#'   Returns NULL if headcount or faculty data is unavailable.
#'
#' @details
#' **CEDAR Data Model Only**
#'
#' This function requires CEDAR-formatted data with lowercase column names.
#'
#' Workflow:
#' \enumerate{
#'   \item Calls \code{get_headcount()} to get student headcount by department
#'   \item Calls \code{get_perm_faculty_count()} to get faculty FTE
#'   \item Merges headcount with faculty data (both use CEDAR naming)
#'   \item Filters out summer terms (term ending in 60)
#'   \item Separates majors from minors
#'   \item Calculates SFR = students / faculty_fte
#' }
#'
#' Major types included:
#' \itemize{
#'   \item Majors: "Major", "Second Major"
#'   \item Minors: "First Minor", "Second Minor"
#' }
#'
#' **Note**: Summer terms are excluded as they're not meaningful for SFR analysis.
#'
#' @examples
#' \dontrun{
#' # Calculate SFRs
#' data_objects <- list(
#'   academic_studies = academic_studies_data,
#'   cedar_faculty = cedar_faculty
#' )
#' sfr_data <- get_sfr(data_objects)
#'
#' # View undergraduate major SFRs for Fall 2025
#' sfr_data %>%
#'   filter(term == 202510, `Student Level` == "Undergraduate", major_type == "all_majors") %>%
#'   arrange(desc(sfr))
#' }
#'
#' @seealso
#' \code{\link{get_perm_faculty_count}} for faculty FTE calculation,
#' \code{\link{count_heads}} for headcount calculation,
#' \code{\link{get_sfr_data_for_dept_report}} for department report generation
#'
#' @export
get_sfr <- function (data_objects) {
  message("[sfr.R] welcome to get_sfr!")

  # Use CEDAR data with lowercase naming
  cedar_programs <- data_objects[["cedar_programs"]]

  if (is.null(cedar_programs)) {
    stop("[sfr.R] Could not find required CEDAR dataset: cedar_programs. ",
         "Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  # Validate CEDAR data structure
  required_cols <- c("student_id", "term", "student_level", "program_type", "program_name", "department")
  missing_cols <- setdiff(required_cols, colnames(cedar_programs))
  if (length(missing_cols) > 0) {
    stop("[sfr.R] Missing required CEDAR columns in programs data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(cedar_programs), collapse = ", "))
  }

  message("[sfr.R] calling get_headcount to count heads...")
  # Use get_headcount with custom grouping for SFR needs
  # Group by term, department, student_level, program_type, program_name
  result <- get_headcount(
    programs = cedar_programs,
    opt = list(),
    group_by = c("term", "department", "student_level", "program_type", "program_name")
  )

  headcount_all <- result$data

  if (is.null(headcount_all) || nrow(headcount_all) == 0) {
    message("[sfr.R] ERROR: No headcount data returned from get_headcount()")
    return(NULL)
  }

  message("[sfr.R] headcount_all has ", nrow(headcount_all), " rows")

  # TODO: count only majors or both majors and minors?
  # some programs have lots of minors that should be counted
  # allowed_types <- c("Major")
  # headcount_all <- headcount_all %>% filter(program_type %in% allowed_types)

  # Map department names to codes for joining with faculty data
  # cedar_programs uses full names ("AS Anthropology"), cedar_faculty uses codes ("ANTH")
  message("[sfr.R] Mapping department names to codes for join...")
  headcount_all <- headcount_all %>%
    mutate(dept_code = hr_org_desc_to_dept_map[department])

  unmapped_depts <- headcount_all %>%
    filter(is.na(dept_code)) %>%
    distinct(department) %>%
    pull(department)

  if (length(unmapped_depts) > 0) {
    message("[sfr.R] WARNING: ", length(unmapped_depts), " departments could not be mapped to codes:")
    message("[sfr.R]   ", paste(head(unmapped_depts, 10), collapse = ", "))
  }

  mapped_count <- sum(!is.na(headcount_all$dept_code))
  message("[sfr.R] Mapped ", mapped_count, " of ", nrow(headcount_all), " rows to dept codes")

  message("[sfr.R] getting permanent faculty headcount...")
  perm_faculty_count <- get_perm_faculty_count(data_objects[["cedar_faculty"]])

  if (is.null(perm_faculty_count) || nrow(perm_faculty_count) == 0) {
    message("[sfr.R] ERROR: No permanent faculty count data returned")
    return(NULL)
  }

  message("[sfr.R] perm_faculty_count has ", nrow(perm_faculty_count), " rows")

  message("[sfr.R] merging student and faculty tables...")
  # Join on term and dept_code (headcount) = department (faculty, which uses codes)
  studfac_ratios <- left_join(
    headcount_all,
    perm_faculty_count,
    by = c("term", "dept_code" = "department")
  )

  message("[sfr.R] After merge, studfac_ratios has ", nrow(studfac_ratios), " rows")

  # filter out summer, which is meaningless for sfr purposes
  message("[sfr.R] filtering out summer for sfr purposes...")
  studfac_ratios <- studfac_ratios %>% filter (!str_detect(as.character(term), "60"))

  message("[sfr.R] After filtering summer, studfac_ratios has ", nrow(studfac_ratios), " rows")

  if (nrow(studfac_ratios) == 0) {
    message("[sfr.R] ERROR: No data after filtering out summer terms")
    return(NULL)
  }

  # calc sums of majors and minors
  # CEDAR naming: student_level (not `Student Level`), program_name (not major_name)
  # Include dept_code for filtering by department code later
  studfac_ratios <- studfac_ratios %>%
    group_by(term, dept_code, department, student_level, program_name, total)

  # separate majors
  majors <- studfac_ratios %>% filter (program_type %in% c("Major","Second Major"))
  majors <- majors %>%  summarize(program_type="all_majors", students = sum(student_count, na.rm = TRUE), .groups = "drop")
  message("[sfr.R] Majors data has ", nrow(majors), " rows")

  # separate minors
  minors <- studfac_ratios %>% filter (program_type %in% c("First Minor","Second Minor"))
  minors <- minors %>%  summarize(program_type="all_minors", students = sum(student_count, na.rm = TRUE), .groups = "drop")
  message("[sfr.R] Minors data has ", nrow(minors), " rows")

  # combine majors and minors
  studfac_ratios <- rbind(majors,minors)

  message("[sfr.R] Combined majors/minors has ", nrow(studfac_ratios), " rows")

  if (nrow(studfac_ratios) == 0) {
    message("[sfr.R] ERROR: No data after combining majors and minors")
    return(NULL)
  }

  # compute SFRs
  message("[sfr.R] computing studfac_ratios...")
  studfac_ratios <- studfac_ratios %>%
    group_by(term, dept_code, department, student_level, program_type) %>%
    arrange(term, program_name, student_level, program_type)
  studfac_ratios <- studfac_ratios %>% mutate(sfr = students / total)

  message("[sfr.R] Returning studfac_ratios")
  return(studfac_ratios)
}


#' Get SFR Data for Department Reports
#'
#' Generates student-faculty ratio plots and data for department-specific reports.
#' Creates separate visualizations for undergraduate and graduate students, plus
#' a scatter plot showing the department in context of the full college.
#'
#' @param data_objects Named list containing academic_studies and cedar_faculty data
#' @param d_params Department report parameters list with:
#'   \itemize{
#'     \item \code{dept_code} - Department code (e.g., "HIST", "MATH")
#'     \item \code{plots} - Existing plots list (will be updated)
#'   }
#'
#' @return Updated d_params list with added plots:
#'   \itemize{
#'     \item \code{ug_sfr_plot} - Undergraduate SFR bar chart by term and major type
#'     \item \code{grad_sfr_plot} - Graduate SFR bar chart by term and major type
#'     \item \code{sfr_scatterplot} - Department in college context (all terms, majors only)
#'   }
#'   If insufficient data, plots will contain error messages instead of ggplot objects.
#'
#' @details
#' Plot specifications:
#'
#' **Undergraduate SFR Plot**:
#' \itemize{
#'   \item X-axis: term
#'   \item Y-axis: sfr (students per faculty)
#'   \item Fill: major_type (all_majors vs all_minors)
#'   \item Grouped bar chart
#' }
#'
#' **Graduate SFR Plot**:
#' \itemize{
#'   \item Same structure as undergraduate plot
#'   \item Filtered for Graduate/GASM student level
#' }
#'
#' **SFR Scatterplot** (College Context):
#' \itemize{
#'   \item Shows all college departments as gray points/lines
#'   \item Highlights target department in color
#'   \item Y-axis limited to 0-50 (except PSYC which often has higher ratios)
#'   \item Uses major data only (excludes minors)
#' }
#'
#' @examples
#' \dontrun{
#' # Generate SFR plots for History department
#' data_objects <- list(
#'   academic_studies = academic_studies_data,
#'   cedar_faculty = cedar_faculty
#' )
#' d_params <- list(dept_code = "HIST", plots = list())
#' d_params <- get_sfr_data_for_dept_report(data_objects, d_params)
#'
#' # Access plots
#' print(d_params$plots$ug_sfr_plot)
#' print(d_params$plots$grad_sfr_plot)
#' print(d_params$plots$sfr_scatterplot)
#' }
#'
#' @seealso
#' \code{\link{get_sfr}} for SFR calculation,
#' \code{\link{get_perm_faculty_count}} for faculty FTE
#'
#' @export
get_sfr_data_for_dept_report <- function(data_objects, d_params) {
  message("[sfr.R] Welcome to Starting get_sfr_data_for_dept_report!")

  studfac_ratios <- get_sfr(data_objects)

  if (is.null(studfac_ratios) || nrow(studfac_ratios) == 0) {
    message("ERROR: No SFR data returned from get_sfr()")
    d_params$plots[["ug_sfr_plot"]] <- "No SFR Data Available"
    d_params$plots[["grad_sfr_plot"]] <- "No SFR Data Available"
    d_params$plots[["sfr_scatterplot"]] <- "No SFR Data Available"
    return(d_params)
  }

  message("[sfr.R] studfac_ratios has ", nrow(studfac_ratios), " rows for dept report")

  # Filter by dept_code directly (now available in studfac_ratios)
  target_dept_code <- d_params[["dept_code"]]
  unique_codes <- unique(studfac_ratios$dept_code)
  message("[sfr.R] Looking for dept_code: '", target_dept_code, "'")
  message("[sfr.R] Available dept_codes: ", paste(na.omit(unique_codes), collapse = ", "))

  if (!target_dept_code %in% unique_codes) {
    message("[sfr.R] WARNING: dept_code '", target_dept_code, "' not found in SFR data")
  }

  # filter by UNDERGRADUATE and DEPT
  ug_sfr <- studfac_ratios %>%
    filter(student_level == "Undergraduate") %>%
    filter(dept_code == target_dept_code) %>%
    mutate(term = as.factor(term))

  message("[sfr.R] Undergraduate SFR data for dept ", d_params[["dept_code"]], " has ", nrow(ug_sfr), " rows")

  if (nrow(ug_sfr) > 0) {
    ug_sfr_plot <- ggplot(ug_sfr, aes(x=term)) +
      #ggtitle(paste(params["dept"], "-", params["program_str"])) +
      #ggtitle(sfr_dept_title) +
      guides(color = guide_legend(title = "")) +
      theme(legend.position="bottom") +
      labs(fill="",color="Comparison") +
      #scale_x_discrete(breaks=num.labs,labels=term.labs) +
      geom_bar(aes(y=sfr, fill=program_type), stat="identity", position="dodge") +
      xlab("Term") + ylab("Students per Faculty Member")
  } else {ug_sfr_plot <- "Insufficient Data"}

  ug_sfr_plot
  d_params$plots[["ug_sfr_plot"]] <- ug_sfr_plot


  # filter by GRADUATE and DEPT
  grad_sfr <- studfac_ratios %>%
    filter(student_level == "Graduate/GASM") %>%
    filter(dept_code == target_dept_code) %>%
    mutate(term = as.factor(term))

  message("[sfr.R] Graduate SFR data for dept ", d_params[["dept_code"]], " has ", nrow(grad_sfr), " rows")

  # plot faculty ratio as grouped bars for grad and undergrad
  if (nrow(grad_sfr) > 0) {
    grad_sfr_plot <- ggplot(grad_sfr, aes(x=term)) +
      #ggtitle(paste(params["dept"], "-", params["program_str"])) +
      #ggtitle(sfr_dept_title) +
      guides(color = guide_legend(title = "")) +
      theme(legend.position="bottom") +
      #labs(fill="",color="Comparison") +
      #scale_x_discrete(breaks=num.labs,labels=term.labs) +
      geom_bar(aes(y=sfr, fill=program_type), stat="identity", position="dodge") +
      xlab("Term") + ylab("Students per Faculty Member")
  } else {grad_sfr_plot <- "Insufficient Data"}

  d_params$plots[["grad_sfr_plot"]] <- grad_sfr_plot


  # plot SFRs in college context
  # get sfrs for majors
  sfr_college <- studfac_ratios %>%
    filter(student_level == "Undergraduate") %>%
    filter(program_type == "all_majors")

  # until there is better college-level sorting, remove rows with NAs for dept_code (meaning non-AS in mappings)
  sfr_college <- sfr_college[!is.na(sfr_college$dept_code),]

  # filter by department code to highlight dept in college context
  sfr_college_dept <- sfr_college %>% filter(dept_code == target_dept_code)

  # compress all college sfrs by dept (lose program info for simplicity)
  sfr_college <- sfr_college %>%
    ungroup() %>% group_by(term, dept_code, department, total) %>%
    mutate(all_students = sum(students), sfr = all_students / total) %>%
    distinct() %>%
    ungroup() %>%
    mutate(term = as.factor(term))

  # Update sfr_college_dept to match
  sfr_college_dept <- sfr_college_dept %>%
    mutate(term = as.factor(term))

  # scatter plot to see dept in context of college for current semester
  if (nrow(sfr_college_dept) > 0) {
    sfr_scatterplot <- ggplot(sfr_college, aes(x=term, y=sfr)) +
      theme(legend.position="bottom") +
      guides(color = guide_legend(title = "",color="")) +
      geom_point(alpha=.5) +
      geom_line(alpha=.2,aes(group=dept_code)) +
      geom_point(sfr_college_dept, mapping=aes(x=term, y=sfr, color=program_name)) +
      geom_line(sfr_college_dept, mapping=aes(x=term, y=sfr, color=program_name, group=program_name)) +
      xlab("Semester") + ylab("Students per Faculty")

    if (d_params$dept_code != "PSYC") {
      sfr_scatterplot <- sfr_scatterplot +
        coord_cartesian(
          ylim = c(0,50)
        )

    }
  } else {sfr_scatterplot <- "Insufficient HR data"}

  sfr_scatterplot
  d_params$plots[["sfr_scatterplot"]] <- sfr_scatterplot

  message("[sfr.R] returning d_params with new plot(s) and table(s)...")
  return(d_params)
}
