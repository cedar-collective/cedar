# Bird's Eye > Retention
#
# The first of the two student pages (Retention, then Graduation): are
# students coming back? One term type at a time: how often enrolled students
# came back the next regular term and whether that is rising or falling; who
# is not coming back, by the warning signs known by the end of the term; each
# classification and college; each entering class semester by semester, then
# year by year with its pace; the two summer questions; and the courses where
# a DFW grade goes with not coming back the most. Finishing in the summer is
# on Graduation.
#
# The module holds no analysis: it collects the term type, level and home
# campuses, calls build_retention_dashboard() (features/retention-dashboard.R)
# and lays out its payload. It builds only while the tab is open, once per
# scope a session asks for. The two entering-class sections, the First Year
# page until 2026-11, are a module inside this one
# (modules/retention-entering-classes.R), placed here and read under this
# page's controls.
#
# Who is counted is said twice, each where its kind belongs: as facts in the
# data scope bar under the controls (the level's students in the latest term,
# how many started first-time or transferred in, and the levels left out), and
# as the rule in each section's "How this is counted".
#
# Exported functions:
#   retentionDashboardUI(id, campuses)
#   retentionDashboardServer(id, student_terms, attempts, degrees, dims, edges, active)

RETENTION_TERM_TYPES <- c(Fall = "fall", Spring = "spring")

# campuses  the home campuses to offer; it opens on the main campus
#           (CEDAR_CAMPUS_MAIN), and none selected reads every campus.
retentionDashboardUI <- function(id, campuses) {
  ns <- NS(id)
  # The page opens on student_levels.csv's first level.
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  entering <- retentionEnteringClassesUI(ns("classes"))
  tagList(
    filter_bar(
      "Retention",
      "From the first semester on: are students coming back, are they keeping pace, and who is not?",
      fluidRow(
        column(3, radioButtons(ns("term_type"), "Term type", choices = RETENTION_TERM_TYPES,
                               selected = "fall", inline = TRUE)),
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus")))
      )
    ),
    # Who the page counts, as facts (describe_retention_scope()).
    uiOutput(ns("scope")),
    # Opened by the server while it reads (cedar_with_loading()).
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332", loading_label = "Reading who came back…",
    dashboard_section(
      "How Often Students Come Back",
      "Is the share of students who come back the next fall or spring rising or falling?",
      method = uiOutput(ns("method_overall")), concept = "retention.return-rate",
      uiOutput(ns("overall_finding")),
      plotly::plotlyOutput(ns("overall_plot"), height = "340px")
    ),
    dashboard_section(
      "Who Isn't Coming Back",
      "How often do students with a warning sign by the end of the term come back, and how many of those who left had one?",
      method = uiOutput(ns("method_signs")), concept = "retention.warning-signs",
      reactable::reactableOutput(ns("signs_table"))
    ),
    dashboard_section(
      "By Classification and College",
      "Is the return rate moving the same way in every classification and college?",
      method = uiOutput(ns("method_groups")), concept = "retention.groups",
      fluidRow(
        column(6, dashboard_subsection("Classification", "The student's classification that term.",
                                       reactable::reactableOutput(ns("classification_table")))),
        column(6, dashboard_subsection("College", "The college of the student's primary major that term.",
                                       reactable::reactableOutput(ns("college_table"))))
      )
    ),
    entering$classes,
    dashboard_section(
      "Still Here, and Moving Forward?",
      "As each year begins, are the students still enrolled from each fall's class earning credits fast enough to finish?",
      method = uiOutput(ns("method_pace")), concept = "retention.class-pace",
      fluidRow(
        column(7, radioButtons(ns("pace_started"), "Students who started as",
                               choices = c("First-time students" = "first_time",
                                           stats::setNames(paste0("transfer:", exit_credit_band_labels(GRADUATION_ARRIVAL_BREAKS)),
                                                           paste0("Transfer, brought ", tolower(exit_credit_band_labels(GRADUATION_ARRIVAL_BREAKS)), " credits"))),
                               selected = "first_time", inline = TRUE)),
        column(5, radioButtons(ns("pace_step"), "At the start of their",
                               choices = stats::setNames(GRADUATION_PACE_STEPS, paste(names(GRADUATION_PACE_STEPS), "year here")),
                               selected = GRADUATION_PACE_STEPS[["third"]], inline = TRUE))),
      uiOutput(ns("pace_lead")),
      plotly::plotlyOutput(ns("pace_plot"), height = "420px"),
      dashboard_subsection(
        "Credits earned, term by term",
        "How many credits has the middle enrolled student of each class earned here before each term?",
        plotly::plotlyOutput(ns("accumulation_plot"), height = "400px"))
    ),
    entering$summer,
    dashboard_section(
      "Summer and Staying on Pace",
      "Of the students behind on credits after each spring, how many take summer courses, and does it bring them back onto pace?",
      method = uiOutput(ns("method_pace_summer")), concept = "retention.pace-summer",
      uiOutput(ns("pace_summer_finding")),
      plotly::plotlyOutput(ns("pace_summer_plot"), height = "360px"),
      dashboard_subsection(
        "Their Summer Courses",
        "The courses students behind on credits took most that summer.",
        reactable::reactableOutput(ns("pace_summer_courses")))
    ),
    dashboard_section(
      "Courses Where a DFW Costs the Most",
      "In which courses do students who did not pass (a grade below C, or a withdrawal) come back much less often than those who passed?",
      method = uiOutput(ns("method_courses")), concept = "retention.dfw-courses",
      reactable::reactableOutput(ns("courses_table"))
    ),
    dashboard_section(
      "Courses Harder on Students with Lower GPAs",
      "Which courses do students with lower GPAs fail by more than they fail the rest of their term, and in which do they hold their own?",
      method = uiOutput(ns("method_bands")), concept = "retention.gpa-band-courses",
      radioButtons(ns("band_by"), "Students", choices = RETENTION_BAND_CHOICES, selected = "entering", inline = TRUE),
      uiOutput(ns("bands_finding")),
      dashboard_subsection(
        "Harder on Them",
        "They fail this course more often than their other courses that term, by a wider margin than the course's other students do.",
        reactable::reactableOutput(ns("bands_harder"))),
      dashboard_subsection(
        "Where They Hold Their Own",
        "They do about as well here as in their other courses that term, or better, where the course's other students do worse.",
        reactable::reactableOutput(ns("bands_easier")))
    ))
  )
}

RETENTION_BAND_CHOICES <- c("Continuing students, by GPA entering the term" = "entering",
                            "First-term students, by high-school GPA" = "hs")

# One by-band list as a table: the lowest band beside the course's other students.
.retention_band_table <- function(rows, low_band) {
  if (NROW(rows) == 0L) return(reactable::reactable(
    data.frame(Message = "No course on this list."), theme = cedar_tbl_theme, compact = TRUE))
  shown <- data.frame(
    course = rows$subject_course, campus = rows$campus, low_n = rows$low_attempts,
    low_dfw = rows$low_dfw_pct / 100, low_other = rows$low_other_dfw_pct / 100,
    rest_dfw = rows$rest_dfw_pct / 100, rest_other = rows$rest_other_dfw_pct / 100,
    gap = rows$gap_pts, chance = 2 * rows$gap_se, stringsAsFactors = FALSE)
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, columns = list(
    course = reactable::colDef(name = "Course"), campus = reactable::colDef(name = "Campus"),
    low_n = cedar_count_coldef("Attempts"),
    low_dfw = cedar_percent_coldef("DFW here"), low_other = cedar_percent_coldef("DFW in their other courses"),
    rest_dfw = cedar_percent_coldef("DFW here"), rest_other = cedar_percent_coldef("DFW in their other courses"),
    gap = cedar_points_coldef("Gap (points)"), chance = reactable::colDef(name = "Chance alone, up to", align = "right", format = reactable::colFormat(digits = 1))),
    columnGroups = list(
      reactable::colGroup(name = paste0("GPA ", low_band), columns = c("low_n", "low_dfw", "low_other")),
      reactable::colGroup(name = "The course's other students", columns = c("rest_dfw", "rest_other"))))
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.retention_pct <- function(x) if (length(x) == 0L || is.na(x)) "—" else sprintf("%.1f%%", x)
.retention_type <- function(p) tolower(names(RETENTION_TERM_TYPES)[RETENTION_TERM_TYPES == p$meta$term_type])
.retention_rate_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "—",
                    format = reactable::colFormat(digits = 1, suffix = "%"), ...)
}

.retention_group_table <- function(g, labels = NULL) {
  shown <- data.frame(
    group = if (is.null(labels)) g$group else dplyr::coalesce(unname(labels[g$group]), g$group),
    last_term = vapply(g$last_term, fmt_term, character(1)),
    last_pct = g$last_pct, pooled_pct = g$pooled_pct, direction = g$direction,
    stringsAsFactors = FALSE)
  series <- g$rates
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    defaultSorted = list(last_pct = "asc"), columns = list(
      group = reactable::colDef(name = "", minWidth = 160),
      last_term = reactable::colDef(name = "Latest term"),
      last_pct = .retention_rate_coldef("Came back"),
      pooled_pct = .retention_rate_coldef("Over the terms"),
      # The line is the message; its verdict is the cell's tooltip.
      direction = reactable::colDef(name = "Trend", minWidth = 110, html = TRUE, cell = function(value, index) {
        as.character(tags$span(title = unname(DFW_DIRECTION_LABELS[value]), make_sparkline(series[[index]])))
      })))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, attempts, degrees, dims, edges   the loaded tables and edges.
# active   reactive: TRUE while the tab is open.
retentionDashboardServer <- function(id, student_terms, attempts, degrees, programs, applicants, dims, edges, active,
                                     course_dim, course_codes) {
  moduleServer(id, function(input, output, session) {
    college_names <- college_code_names(dims)
    # The entering-class sections read this page's controls.
    retentionEnteringClassesServer(
      "classes", student_terms, degrees, programs, attempts, course_dim, course_codes, edges,
      scope = reactive({
        req(isTRUE(active()), input$term_type, input$level)
        list(term_type = input$term_type, level = input$level,
             campus = if (length(input$campus) > 0) input$campus else NULL)
      }))
    payload <- reactive({
      req(isTRUE(active()), input$term_type, input$level)
      cedar_shared_result(list("retention_dashboard", input$term_type, input$level, input$campus), function() cedar_with_loading(session, session$ns("load"), report_type = "retention_dashboard", {
        tryCatch(
          build_retention_dashboard(student_terms, attempts, degrees, list(
            term_type = input$term_type, student_level = input$level,
            campus = if (length(input$campus) > 0) input$campus else NULL, data_edges = edges,
            milestones = FALSE, courses = FALSE), programs = programs),
          error = function(e) {
            showNotification(paste("Retention:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          })
      }))
    # Shared by every session (cedar_shared_result()): the tables are fixed for
    # the life of the process, so the first reader after a start waits and the
    # rest do not.
    })

    # Who is counted, as facts: the latest term's students, how they started,
    # and the levels left out. The rule is in each section's method.
    output$scope <- renderUI({
      p <- payload(); req(p, p$who)
      headcount_scope_bar(describe_retention_scope(p$who))
    })

    # The course list is the slowest part: read after the charts above it.
    courses <- reactive({
      p <- payload(); req(p, nrow(p$series) > 0L)
      cedar_shared_result(list("retention_courses", input$term_type, input$level, input$campus), function() tryCatch(
        retention_dashboard_course_list(student_terms, attempts, degrees, p$series, list(
          student_level = input$level, campus = if (length(input$campus) > 0) input$campus else NULL,
          data_edges = edges)),
        error = function(e) {
          showNotification(paste("Courses:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }))
    })

    bands <- reactive({
      req(isTRUE(active()), input$term_type, input$level, input$band_by)
      if (identical(input$band_by, "hs") && is.null(applicants)) return(NULL)
      cedar_shared_result(list("retention_bands", input$term_type, input$level, input$campus, input$band_by), function() tryCatch(
        retention_dashboard_band_courses(attempts, student_terms, applicants, list(
          term_type = input$term_type, student_level = input$level,
          campus = if (length(input$campus) > 0) input$campus else NULL,
          data_edges = edges, band_by = input$band_by)),
        error = function(e) {
          showNotification(paste("Courses by GPA:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }))
    })
    output$bands_finding <- renderUI({
      b <- bands()
      if (is.null(b)) return(empty_state("This reading needs high-school GPAs, which this installation does not hold, or could not be built; a notification says why."))
      lead_text(retention_band_sentence(b))
    })
    output$bands_harder <- reactable::renderReactable({ b <- bands(); req(b); .retention_band_table(b$harder, b$meta$low_band) })
    output$bands_easier <- reactable::renderReactable({ b <- bands(); req(b); .retention_band_table(b$easier, b$meta$low_band) })
    output$method_bands <- renderUI({
      b <- bands(); req(b)
      m <- b$meta
      tags$ul(
        tags$li(paste0("Graded attempts in ", paste(vapply(m$terms, fmt_term, character(1)), collapse = ", "),
                       " by students at the chosen level and home campus that term, transfer students included. ",
                       "Each course is read by the campus that taught it, and a student's other courses count ",
                       "wherever they were taught. The GPA band is ",
                       if (m$band_by == "entering") "the GPA a continuing student brought into the term, counted from their own earlier terms here; first-term students have none"
                       else "the high-school GPA on file for a student in their first graded term here",
                       ". A student is read once for each term: ", fmt_count(m$n_banded), " in all. ",
                       fmt_count(m$n_no_band), " more have no such GPA, and ", fmt_count(m$n_invalid),
                       " started before the data does, so their GPA cannot be added up; both are left out.")),
        tags$li(paste0("For each group, the DFW rate in the course is set beside the same students' DFW rate in the other ",
                       "courses they took that term. A student who is struggling everywhere shows it in both, so the ",
                       "difference is what this course adds. The gap is that difference for students with a GPA ",
                       m$low_band, " less the same difference for the course's other students: a course hard on everyone has no gap.")),
        tags$li(paste0("A course is read when both groups have ", m$min_n, " attempts, and listed when its gap is beyond ",
                       "chance alone (two standard errors). ", fmt_count(m$n_courses), " courses were read; with that ",
                       "many, chance alone lists some. Ranked by the attempts the gap stands for.")),
        tags$li("A place to look, not a finding. The other courses are each student's own choice of a term, and a course usually taken beside lighter ones shows a larger gap for that reason."))
    })

    output$overall_finding <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The retention figures could not be built; the notification says why."))
      if (nrow(p$series) == 0L) return(empty_state("No student in this scope has a settled next term to read."))
      # The verdict over the terms; the chart below shows each term's rate
      # and the trend's line.
      lead_text(retention_lead_sentence(p$trend[1, , drop = FALSE], .retention_type(p)))
    })
    output$overall_plot <- plotly::renderPlotly({ p <- payload(); req(p, nrow(p$series) > 0L); plot_return_series(p) })
    output$method_overall <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("Every student enrolled in each of the ", .retention_type(p), " terms (registered, or withdrawn ",
                       "after census) at the student level chosen above, counted once for each term, by the student's home campus. Came back means enrolled the next regular term, ",
                       "at UNM on any campus: summer is not a step, and moving campus is not leaving.")),
        tags$li(retention_who_note(p$who)),
        tags$li(paste0("Left out: ", fmt_count(m$n_graduated), " who finished rather than left, and ",
                       fmt_count(m$n_unobservable), " whose next term had not settled. Finished means awarded a ",
                       "degree that term",
                       if (m$term_type == "spring") paste0(
                         " or in the summer after it (", fmt_count(m$n_finished_between), " students; ",
                         fmt_count(m$n_applied_between), " more have applied to graduate in a summer whose ",
                         "degrees are not posted yet, and are counted as finishing)") else "",
                       ". A degree on hold is not a degree.")),
        tags$li(paste0("The dashed line is the trend, fitted through the terms; it is rising or falling when its ",
                       "slope is beyond both chance and the ordinary term-to-term swings. ",
                       retention_trend_arithmetic(p$trend[1, , drop = FALSE]))),
        tags$li(paste0("Enrollment settled through ", fmt_term(m$edge), "; a term's rate needs ", m$min_n,
                       " students whose return can be read. Hover a term for its counts.")))
    })

    # Each fall's entering classes, year by year: read on their own, the
    # slowest part of the page.
    class_pace <- reactive({
      req(isTRUE(active()), input$level)
      cedar_shared_result(list("class_pace", input$level, input$campus), function() tryCatch(
        build_class_pace(student_terms, degrees, programs, list(
          student_level = input$level, campus = if (length(input$campus) > 0) input$campus else NULL,
          data_edges = edges)),
        error = function(e) {
          showNotification(paste("Pace:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }))
    })
    pace_step <- reactive({ req(input$pace_step); as.integer(input$pace_step) })
    # The chosen group's table: first-time students, or one band of transfer students.
    pace_table <- reactive({
      p <- class_pace(); req(p, input$pace_started)
      if (identical(input$pace_started, "first_time")) return(p$pace)
      band <- sub("^transfer:", "", input$pace_started)
      req(band %in% names(p$transfer))
      p$transfer[[band]]
    })
    pace_drawn <- function(pace) nrow(graduation_pace_shares(pace, pace_step())) > 0L
    output$pace_lead <- renderUI({
      pace <- pace_table()
      if (!pace_drawn(pace)) return(empty_state(graduation_pace_lead(pace, pace_step())))
      lead_text(graduation_pace_lead(pace, pace_step()))
    })
    output$pace_plot <- plotly::renderPlotly({
      pace <- pace_table(); req(pace_drawn(pace)); plot_class_pace(pace, pace_step())
    })
    output$accumulation_plot <- plotly::renderPlotly({
      pace <- pace_table(); req(any(!is.na(pace$credits_median) & !is.na(pace$here_pct)))
      plot_credit_accumulation(pace)
    })
    output$method_pace <- renderUI({
      p <- class_pace(); req(p)
      rates <- attr(p$pace, "pace")
      tags$ul(
        tags$li(paste0("An entering class is the students the record calls first-time that fall, at this level and ",
                       "home campus; a first-time student who started in the summer and enrolled that fall is in ",
                       "the fall class (", fmt_count(attr(p$pace, "n_summer_starts")), " students). ",
                       "A class of fewer than ", attr(p$pace, "min_n"), " is not drawn.")),
        tags$li(paste0("Transfer students are read apart, because they start part-way: each fall's students the record ",
                       "calls a new transfer, grouped by the credits they brought from elsewhere. For them the split is ",
                       "by the credits a term they earn here (", rates[["four_year"]], " or more, ", rates[["six_year"]],
                       " to ", rates[["four_year"]] - 1, ", fewer), not by a four-year pace: a student who brought 60 ",
                       "credits and earns ", rates[["four_year"]], " a term finishes in two years. Students who transfer ",
                       "in a spring are not in these classes.")),
        tags$li(graduation_transfer_record_note(p$transfer[[1]])),
        tags$li(paste0("A student the record never calls first-time or a new transfer (readmitted after time away, moved ",
                       "from another campus or level, or here before the records begin) is in no class here, though the ",
                       "return rates above count them.")),
        tags$li(paste0("Each student is in one part as the year begins: awarded a degree by then; enrolled that term; ",
                       "or not enrolled, which includes a student away for the term who later comes back.")),
        tags$li(paste0("An enrolled student is on pace for four years with ", rates[["four_year"]],
                       " credits completed here for each regular term since entering, counted before the term ",
                       "begins and with summer credits, and on pace for six with ", rates[["six_year"]],
                       ". Credit brought from elsewhere (test, dual or transfer credit) is not counted, so a ",
                       "student who arrived with credit is further along than shown.")),
        tags$li(paste0("A student whose first term here is the first term of the class lists may have earlier credits ",
                       "that cannot be seen, and is shown as enrolled with earlier credits not on record. The first ",
                       "first-time class is the exception: the record calls its ", fmt_count(attr(p$pace, "n_label_trusted")),
                       " students new that term, so their credits are counted from it. A few had earned credit here ",
                       "before entering (dual credit), and are a little further along than shown.")),
        tags$li(paste0("Degrees are posted through ", fmt_term(edges[["last_degree"]]), ". For a term after that, a student ",
                       "who has applied to graduate counts as having the degree from the following term.")),
        tags$li(paste0("Enrollment is settled through ", fmt_term(attr(p$pace, "edge")), " and credits are read through ",
                       fmt_term(attr(p$pace, "pace_edge")), ". The credit lines show the middle student of those still ",
                       "enrolled, with half of them between the figures in the hover; students who left are not in ",
                       "them, so a line can rise because slower students left.")))
    })


    # Students behind on credits each spring, and what the summer did.
    pace_summer <- reactive({
      req(isTRUE(active()), input$level)
      cedar_shared_result(list("pace_summer", input$level, input$campus), function() tryCatch(
        build_pace_summer(student_terms, attempts, degrees, programs, list(
          student_level = input$level, campus = if (length(input$campus) > 0) input$campus else NULL,
          data_edges = edges)),
        error = function(e) {
          showNotification(paste("Summer and pace:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }))
    })
    pace_summer_rows <- reactive({ s <- pace_summer(); req(s); summer_catch_up_by_term(s) })
    output$pace_summer_finding <- renderUI({
      s <- pace_summer()
      if (is.null(s)) return(empty_state("The summer figures could not be built; the notification says why."))
      sentence <- summer_catch_up_sentence(pace_summer_rows(), s$meta$pace_credits)
      if (length(sentence) == 0L) return(empty_state("No spring in this scope has a graded summer after it to read."))
      lead_text(sentence)
    })
    output$pace_summer_plot <- plotly::renderPlotly({
      rows <- pace_summer_rows(); req(any(rows$n_behind > 0L)); plot_summer_catch_up(rows)
    })
    output$pace_summer_courses <- reactable::renderReactable({
      s <- pace_summer(); req(s)
      # `course_dim`, not `courses`: that name is this page's DFW course list.
      cedar_course_share_table(s$courses, describe_courses(s$courses$subject_course, course_dim, course_codes),
                               "Of those behind who took a summer course")
    })
    output$method_pace_summer <- renderUI({
      s <- pace_summer(); req(s)
      m <- s$meta
      rows <- pace_summer_rows()
      tags$ul(
        tags$li(paste0("First-time students who entered in a fall, read at the spring that ends each of their first ",
                       "four years, if enrolled that spring. Transfer students are not read here: they start part-way, ",
                       "so a four-year pace does not fit them. A student awarded a degree that spring is left out (",
                       fmt_count(sum(rows$n_finished)), " over these springs).")),
        tags$li(paste0("Behind means fewer than ", m$pace_credits, " credits completed here for each fall and spring ",
                       "since entering, the pace that finishes in four years. Credit brought from elsewhere (test, ",
                       "dual or transfer credit) is not counted, so a student who arrived with credit is further ",
                       "along than shown and some counted as behind are not.")),
        tags$li(paste0("Caught up means the credits completed here that summer bring the total to that pace. A course ",
                       "attempted and not passed adds nothing. A spring is read once its summer's grades are posted ",
                       "(grades are posted through ", fmt_term(m$graded_edge), ").")),
        tags$li(paste0(fmt_count(sum(rows$n_unknown)), " students over these springs have a record that began before ",
                       "the class lists, so their total cannot be added up; they are in no bar.")),
        tags$li(if (length(m$course_terms) == 0L) "No summer in this scope has posted grades, so no course is listed."
                else paste0("Courses are graded attempts in ", paste(vapply(m$course_terms, fmt_term, character(1)), collapse = ", "),
                            ", by the campus that taught them, as a share of the ", fmt_count(m$n_course_students),
                            " students behind who took a course in those summers. A course taken by fewer than ",
                            m$min_n, " of them is not listed.")))
    })

    output$signs_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$signs) > 0L)
      last <- p$signs_latest
      shown <- data.frame(
        sign = unname(RETENTION_SIGNS[last$sign]), term = vapply(last$term, fmt_term, character(1)),
        n_with = last$n_with, return_with = last$return_with_pct, return_without = last$return_without_pct,
        share = last$share_of_nonreturners_pct, stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, columns = list(
        sign = reactable::colDef(name = "Warning sign", minWidth = 140),
        term = reactable::colDef(name = "Term"),
        n_with = cedar_count_coldef("Students with it"),
        return_with = .retention_rate_coldef("Came back, with it"),
        return_without = .retention_rate_coldef("Came back, without it"),
        share = .retention_rate_coldef("Of those who didn't come back, had it")))
    })
    output$method_signs <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li("The same students as the section above: everyone enrolled that term at the chosen level and home campus, transfer students included."),
        tags$li("A late withdrawal: at least one course dropped after census that term."),
        tags$li(paste0("A DFW grade: at least one D, F or other non-passing grade posted that term (a late ",
                       "withdrawal is counted apart). Read only for terms with posted grades, through ",
                       fmt_term(p$meta$graded_edge), "; a student with no grade posted is in neither group.")),
        tags$li("Each sign is read apart: a student may carry both, so the shares can add to more than 100%."),
        tags$li(paste0("The latest term with the sign known is shown; a rate needs ", p$meta$min_n,
                       " students.")))
    })

    output$classification_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$groups) > 0L)
      .retention_group_table(p$groups[p$groups$dimension == "classification", , drop = FALSE])
    })
    output$college_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$groups) > 0L)
      .retention_group_table(p$groups[p$groups$dimension == "college", , drop = FALSE], college_names)
    })
    output$method_groups <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li("The same students as the first section: everyone enrolled that term at the chosen level and home campus, transfer students included."),
        tags$li("Classification is the student's that term; college is the college of the primary major that term."),
        tags$li(paste0("A group's rate is read in each term it had ", p$meta$min_n, " or more students whose return ",
                       "could be read; a group not read in the latest term is left out (",
                       fmt_count(p$meta$n_groups_past), " here). Sorted with the lowest latest rate first.")))
    })

    output$courses_table <- reactable::renderReactable({
      crs <- courses(); req(crs, NROW(crs$listed) > 0L)
      top <- crs$listed
      shown <- data.frame(course = top$subject_course, campus = top$campus, n_dfw = top$pop_n_dfw,
                          dfw_rate = top$pop_dfw_rate, after_dfw = 1 - top$pop_dfw_stopout_rate,
                          after_pass = 1 - top$pop_pass_stopout_rate, gap = 100 * top$pop_stopout_gap,
                          excess = round(top$excess_not_back), stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, columns = list(
        course = reactable::colDef(name = "Course"), campus = reactable::colDef(name = "Campus"),
        n_dfw = cedar_count_coldef("Students with a DFW"),
        dfw_rate = cedar_percent_coldef("DFW rate"),
        after_dfw = cedar_percent_coldef("Came back after a DFW"),
        after_pass = cedar_percent_coldef("Came back after passing"),
        gap = cedar_points_coldef("Gap (points)"),
        excess = cedar_count_coldef("Not back, beyond the passers' rate")))
    })
    output$method_courses <- renderUI({
      p <- payload(); crs <- courses(); req(p, crs)
      terms <- crs$terms
      tags$ul(
        tags$li(paste0("The students of the latest ", length(terms), " ", .retention_type(p), " terms with posted grades (",
                       paste(vapply(terms, fmt_term, character(1)), collapse = ", "), ") at the chosen level and home ",
                       "campus, transfer students included; each course is read by the campus that taught it. ",
                       "A degree that term counts as finishing, not leaving.")),
        tags$li(paste0("A course is listed when 100 or more of these students took it, 20 or more got a DFW, and the ",
                       "students who did not pass came back less often than those who passed by more than chance ",
                       "alone would explain. Each course is tested on its own, so among this many courses chance ",
                       "still lists a few (a chi-squared test at the 5% level, not adjusted across courses).")),
        tags$li(paste0("Ranked by the students a gap stands for: the students with a DFW times the gap, how many ",
                       "more did not come back than would have at the passers' rate. A large course with a ",
                       "moderate gap comes before a small one with a wide gap. The top 25 are listed.")),
        tags$li("The gap describes who fails the course as much as the course itself; Course Dynamics > Downstream > Coming Back reads one course in depth."))
    })
  })
}
