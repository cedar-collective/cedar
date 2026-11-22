# Bird's Eye > Graduation
#
# Where do students leave without a degree, and how far along were they? The
# students whose last enrolled term is behind them and who hold no degree: how
# many credits they had when they stopped, when they stopped, where they stood
# against the general standards for aid, and which colleges and majors the
# far-along ones were in, and in the courses their program's degree plan
# names, how many tried here and never passed. Then the students who pass
# 160 attempted credits with no degree, and each fall's first-time
# students: still enrolled as each year begins, and at what pace of credits.
#
# The module holds no analysis: it collects the level, the home campuses and
# the credit line, calls build_graduation_dashboard()
# (features/graduation-dashboard.R) and lays out its payload. It builds only
# while the tab is open, once per scope, shared by every session.
#
# Exported functions:
#   graduationUI(id, campuses)
#   graduationServer(id, student_terms, programs, degrees, terms, dims, edges, active, attempts, boards)

graduationUI <- function(id, campuses) {
  ns <- NS(id)
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  lines <- stats::setNames(GRADUATION_LINES, paste(GRADUATION_LINES, "credits or more"))
  tagList(
    filter_bar(
      "Graduation",
      "Where do students leave without a degree, and how far along were they?",
      fluidRow(
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus"))),
        column(5, radioButtons(ns("line"), "Far along means", choices = lines,
                               selected = GRADUATION_LINES[[1]], inline = TRUE))
      )
    ),
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332",
                          loading_label = "Reading who left…",
    dashboard_section(
      "How Far Along They Were",
      "Of the students who left without a degree, how many credits had each earned when they stopped?",
      method = uiOutput(ns("method_bands")),
      uiOutput(ns("headline")),
      plotly::plotlyOutput(ns("bands_plot"), height = "360px")
    ),
    dashboard_section(
      "Term by Term",
      "How many far-along students stopped after each term?",
      method = uiOutput(ns("method_series")),
      plotly::plotlyOutput(ns("series_plot"), height = "340px")
    ),
    dashboard_section(
      "Where They Stood",
      "In each credit band, how many had ever been Pell-eligible, and how many no longer met the general standards for aid?",
      method = uiOutput(ns("method_standing")),
      reactable::reactableOutput(ns("standing_table"))
    ),
    dashboard_section(
      "By College and Major",
      "Which colleges and majors were the far-along students in when they stopped?",
      method = uiOutput(ns("method_groups")),
      dashboard_subsection("College", "The college of the student's primary major in their last term.",
                           reactable::reactableOutput(ns("college_table"))),
      dashboard_subsection("Major", "The student's primary major in their last term, with its code: two majors may share a name.",
                           reactable::reactableOutput(ns("major_table")))
    ),
    dashboard_section(
      "The Courses Their Program Requires",
      "Of the far-along students who left without a degree, how many had tried each course their program requires here and never passed it?",
      method = uiOutput(ns("method_required")),
      uiOutput(ns("required_lead")),
      selectInput(ns("plan"), "Degree plan", choices = NULL, width = "100%"),
      uiOutput(ns("plan_note")),
      plotly::plotlyOutput(ns("required_plot"), height = "auto"),
      reactable::reactableOutput(ns("required_table"))
    ),
    dashboard_section(
      "At 160 Attempted Credits",
      "When students pass 160 attempted credits with no degree yet, where did the credits come from, and what happens next?",
      method = uiOutput(ns("method_ceiling")),
      uiOutput(ns("ceiling_lead")),
      plotly::plotlyOutput(ns("ceiling_parts_plot"), height = "auto"),
      dashboard_subsection(
        "What happened next",
        "By each term after they passed it, how many had a degree, were still enrolled, or were not enrolled?",
        uiOutput(ns("ceiling_outcome_note")),
        plotly::plotlyOutput(ns("ceiling_outcomes_plot"), height = "380px"))
    ),
    dashboard_section(
      "Still Here, and Moving Forward?",
      "Of each fall's new students, how many are still enrolled as each year begins, and are they earning credits fast enough to finish?",
      method = uiOutput(ns("method_pace")),
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
    ))
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

# show_code adds the group's code beside its name (majors: names repeat).
.graduation_group_table <- function(g, done_at, first_col, show_code = FALSE) {
  if (NROW(g) == 0L) return(reactable::reactable(
    data.frame(Message = "No student in this scope."), theme = cedar_tbl_theme, compact = TRUE))
  shown <- data.frame(group = g$label, code = g$group, n = g$n, n_done = g$n_done, n_flagged = g$n_flagged,
                      n_pell = g$n_pell, stringsAsFactors = FALSE)
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    columns = list(
      group = reactable::colDef(name = first_col, minWidth = 200),
      code = reactable::colDef(name = "Code", show = show_code, na = "\u2014", minWidth = 80),
      n = cedar_count_coldef("Left"),
      n_done = cedar_count_coldef(paste(done_at, "credits or more")),
      n_flagged = cedar_count_coldef("No longer met a standard"),
      n_pell = cedar_count_coldef("Ever Pell-eligible")))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, programs, degrees, terms, dims, edges   the loaded tables and edges.
# active   reactive: TRUE while the tab is open.
# attempts, boards   cedar_attempts and the degree boards (publish_degree_drafts()).
graduationServer <- function(id, student_terms, programs, degrees, terms, dims, edges, active, attempts, boards) {
  moduleServer(id, function(input, output, session) {
    # Shared by every session: the tables are fixed for the life of the process.
    payload <- reactive({
      req(isTRUE(active()), input$level, input$line)
      cedar_shared_result(list("graduation_dashboard", input$level, input$campus, input$line), function() cedar_with_loading(session, session$ns("load"), report_type = "graduation_dashboard", {
        tryCatch(
          build_graduation_dashboard(student_terms, programs, degrees, terms, dims, list(
            student_level = input$level, campus = if (length(input$campus) > 0) input$campus else NULL,
            line = as.numeric(input$line), data_edges = edges), attempts = attempts, boards = boards),
          error = function(e) {
            showNotification(paste("Graduation:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          })
      }))
    })

    n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
    has_rows <- function(p) !is.null(p) && p$meta$n_left > 0L

    output$headline <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The figures could not be built; the notification says why."))
      if (!has_rows(p)) return(empty_state(graduation_headline(p)))
      lead_text(graduation_headline(p))
    })
    output$bands_plot <- plotly::renderPlotly({ p <- payload(); req(has_rows(p)); plot_exit_bands(p) })
    output$series_plot <- plotly::renderPlotly({ p <- payload(); req(has_rows(p)); plot_exit_series(p) })

    output$method_bands <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("A student's last term is the last one they were enrolled in at this university, at any level, ",
                       "scoped by their level and home campus that term. They left when the two regular terms after it ",
                       "passed with no enrollment (summer is not a step) and they have been awarded no degree of any ",
                       "kind. A degree on hold, or one applied for and not yet awarded, is not a degree: ",
                       n(m$n_applied_to_graduate), " of those who left have an application to graduate on file for a ",
                       "later term.")),
        tags$li(paste0("Enrollment is settled through ", fmt_term(m$edge), " and degrees are posted through ",
                       fmt_term(m$degree_edge), ". ", n(m$n_not_judged), " students' last terms are too recent to judge: ",
                       "everyone still enrolled is among them. ", n(m$n_with_degree),
                       " students whose last term can be judged hold a degree and are not shown.")),
        tags$li(paste0("Credits are the total on the registrar's record when the student stopped, transfer and test ",
                       "credit included. For ", n(m$n_last_term_added), " students that record was pulled before the ",
                       "next term began, so the credits completed in the last term are added. ", n(m$n_not_recorded),
                       " have no total on record.")),
        tags$li("A student who finished at another institution is not known to have, and counts here as having left."))
    })
    output$method_series <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li(paste0("Each bar is the students whose last term it was and who had ", p$meta$line,
                       " credits or more. Hover a term for those at ", p$meta$done_at, " or more and for everyone who left.")),
        tags$li("Terms are not alike: more students stop after a spring than a fall, and few after a summer. Compare a term with the same term a year earlier."),
        tags$li(graduation_later_return_note(p$meta)))
    })

    output$standing_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p))
      b <- graduation_band_table(p)
      m <- p$meta
      shown <- data.frame(band = b$band, n = b$n, share = b$share_pct / 100, pell = b$pell_pct / 100,
                          gpa = b$gpa_below_pct / 100, ceiling = b$over_ceiling_pct / 100,
                          either = b$flagged_pct / 100, stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, sortable = FALSE, columns = list(
        band = reactable::colDef(name = "Credits when they stopped", minWidth = 170),
        n = cedar_count_coldef("Left"),
        share = cedar_percent_coldef("Share of all who left"),
        pell = cedar_percent_coldef("Ever Pell-eligible"),
        gpa = cedar_percent_coldef(paste0("GPA under ", format(m$gpa_floor, nsmall = 1))),
        ceiling = cedar_percent_coldef(paste0(m$credit_ceiling, " attempted credits or more")),
        either = cedar_percent_coldef("Either")),
        columnGroups = list(reactable::colGroup(name = "No longer met a general standard for aid",
                                                columns = c("gpa", "ceiling", "either"))))
    })
    output$method_standing <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("The two standards are general ones, computed here: a cumulative GPA under ",
                       format(m$gpa_floor, nsmall = 1), ", and ", m$credit_ceiling,
                       " attempted credits or more. The data holds no record of anyone's aid, so this is who would no ",
                       "longer have met the standard, not who lost aid.")),
        tags$li("GPA and attempted credits are the registrar's figures when the student stopped. Ever Pell-eligible means in any term on record."),
        tags$li(paste0("Each share is of the students the figure is known for; a band needs ", m$min_n,
                       " of them to show a share.")))
    })

    output$college_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p)); .graduation_group_table(p$colleges, p$meta$done_at, "College")
    })
    output$major_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p)); .graduation_group_table(p$majors, p$meta$done_at, "Major", show_code = TRUE)
    })
    output$method_groups <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("The ", n(m$n_far), " students who left with ", m$line, " credits or more, by the primary major ",
                       "on record in their last term and that major's college. No longer met a standard counts the students ",
                       "below the GPA line or at the credit line above.")),
        tags$li(paste0("A major with fewer than ", m$min_list, " such students is not named: ", n(m$n_majors_pooled),
                       " are counted together as all other majors.")),
        tags$li("The courses these students' programs require are in the next section, for the programs with a degree plan on file."))
    })

    # The plans with enough students to list, largest first.
    plans <- reactive({
      p <- payload(); req(has_rows(p))
      shown <- p$required$programs[p$required$programs$shown, ]
      # No plan to show: an empty list, not a label pasted from nothing.
      if (nrow(shown) == 0L) return(character(0))
      stats::setNames(shown$catalog_id, paste0(shown$label, " (", n(shown$n_students), " students)"))
    })
    observeEvent(plans(), {
      keep <- if (isTRUE(input$plan %in% plans())) input$plan else if (length(plans()) > 0L) plans()[[1]] else character(0)
      updateSelectInput(session, "plan", choices = plans(), selected = keep)
    })
    plan <- reactive({ req(length(plans()) > 0L, input$plan %in% plans()); input$plan })
    output$required_lead <- renderUI({
      p <- payload(); req(has_rows(p))
      tagList(lead_text(graduation_credit_source_note(p)), tags$p(graduation_required_lead(p)),
              if (length(plans()) == 0L) empty_state("No degree plan has enough of these students to list."))
    })
    output$plan_note <- renderUI(tags$p(graduation_plan_note(payload(), plan())))
    output$required_plot <- plotly::renderPlotly({
      p <- payload(); id <- plan()
      req(any(p$required$courses$readable[p$required$courses$catalog_id == id]))
      plot_exit_required(p, id)
    })
    output$required_table <- reactable::renderReactable({
      p <- payload(); id <- plan()
      rows <- p$required$courses[p$required$courses$catalog_id == id, ]
      shown <- data.frame(course = rows$subject_course, title = rows$title, tried = rows$n_tried,
                          passed = rows$n_passed, none = rows$n_none, stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE,
        columns = list(
          course = reactable::colDef(name = "Course", minWidth = 110),
          title = reactable::colDef(name = "Title", minWidth = 220),
          tried = cedar_count_coldef("Tried here, never passed"),
          passed = cedar_count_coldef("Passed here"),
          none = cedar_count_coldef("No attempt here")))
    })
    output$ceiling_lead <- renderUI({
      p <- payload(); req(p)
      if (p$ceiling$meta$n_passed == 0L) return(empty_state(graduation_ceiling_lead(p$ceiling)))
      lead_text(graduation_ceiling_lead(p$ceiling))
    })
    output$ceiling_parts_plot <- plotly::renderPlotly({
      p <- payload(); req(p, p$ceiling$meta$n_passed > 0L); plot_ceiling_parts(p$ceiling)
    })
    output$ceiling_outcome_note <- renderUI({
      p <- payload(); req(p, p$ceiling$meta$n_passed > 0L); tags$p(graduation_ceiling_outcome_note(p$ceiling))
    })
    output$ceiling_outcomes_plot <- plotly::renderPlotly({
      p <- payload(); req(p, nrow(graduation_ceiling_outcomes(p$ceiling)) > 0L); plot_ceiling_outcomes(p$ceiling)
    })
    output$method_ceiling <- renderUI({
      p <- payload(); req(p)
      m <- p$ceiling$meta
      tags$ul(
        tags$li(paste0(m$ceiling, " attempted credits is a general standard for aid, computed here. The data holds no ",
                       "record of anyone's aid, so this is who would no longer have met the standard, not who lost aid.")),
        tags$li(paste0("Attempted credits are counted term by term from the class lists, with the credit a student ",
                       "brought from elsewhere (transfer, test and dual credit) added. A student passes in the first ",
                       "enrolled term that ends at or past ", m$ceiling, ", at this level and home campus that term.")),
        tags$li(paste0("Not placed, because the passing cannot be seen: ", n(m$n_not_readable),
                       " students whose record began before the class lists or whose credit from elsewhere is not ",
                       "on record yet, and ", n(m$n_already_past),
                       " already past it in their first term on record. ", n(m$n_prior_degree),
                       " who already held a degree are left out. Because earlier records cannot be read, the count ",
                       "of students passing each term is not shown as a trend: it would rise only because more ",
                       "records become readable.")),
        tags$li(paste0("Attempted here, not completed, is credit for courses failed, withdrawn from, left incomplete ",
                       "or repeated. The three parts are averages, so they add to the average total.")),
        tags$li(paste0("What happened next counts only the students whose later term is settled (enrollment through ",
                       fmt_term(m$settled_edge), ", degrees through ", fmt_term(m$degree_edge),
                       "), so each bar has its own number of students, in the hover. A bar with fewer than ",
                       GRADUATION_CEILING_MIN_N, " is not drawn. Passing terms run through ", fmt_term(m$edge), ".")))
    })

    pace_step <- reactive({ req(input$pace_step); as.integer(input$pace_step) })
    # The chosen group's table: first-time students, or one band of transfer students.
    pace_table <- reactive({
      p <- payload(); req(p, input$pace_started)
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
      p <- payload(); req(p)
      rates <- attr(p$pace, "pace")
      tags$ul(
        tags$li(paste0("An entering class is the students the record calls first-time that fall, at this level and ",
                       "home campus; a first-time student who started in the summer and enrolled that fall is in ",
                       "the fall class (", n(attr(p$pace, "n_summer_starts")), " students). ",
                       "A class of fewer than ", attr(p$pace, "min_n"), " is not drawn.")),
        tags$li(paste0("Transfer students are read apart, because they start part-way: each fall's students the record ",
                       "calls a new transfer, grouped by the credits they brought from elsewhere. For them the split is ",
                       "by the credits a term they earn here (", rates[["four_year"]], " or more, ", rates[["six_year"]],
                       " to ", rates[["four_year"]] - 1, ", fewer), not by a four-year pace: a student who brought 60 ",
                       "credits and earns ", rates[["four_year"]], " a term finishes in two years. Students who transfer ",
                       "in a spring are not in these classes.")),
        tags$li(graduation_transfer_record_note(p$transfer[[1]])),
        tags$li(paste0("Each student is in one part as the year begins: awarded a degree by then; enrolled that term; ",
                       "or not enrolled, which includes a student away for the term who later comes back.")),
        tags$li(paste0("An enrolled student is on pace for four years with ", rates[["four_year"]],
                       " credits completed here for each regular term since entering, counted before the term ",
                       "begins and with summer credits, and on pace for six with ", rates[["six_year"]],
                       ". Credit brought from elsewhere (test, dual or transfer credit) is not counted, so a ",
                       "student who arrived with credit is further along than shown.")),
        tags$li(paste0("A student whose first term here is the first term of the class lists may have earlier credits ",
                       "that cannot be seen, and is shown as enrolled with earlier credits not on record. The first ",
                       "first-time class is the exception: the record calls its ", n(attr(p$pace, "n_label_trusted")),
                       " students new that term, so their credits are counted from it. A few had earned credit here ",
                       "before entering (dual credit), and are a little further along than shown.")),
        tags$li(paste0("Degrees are posted through ", fmt_term(p$meta$degree_edge), ". For a term after that, a student ",
                       "who has applied to graduate counts as having the degree from the following term.")),
        tags$li(paste0("Enrollment is settled through ", fmt_term(attr(p$pace, "edge")), " and credits are read through ",
                       fmt_term(attr(p$pace, "pace_edge")), ". The credit lines show the middle student of those still ",
                       "enrolled, with half of them between the figures in the hover; students who left are not in ",
                       "them, so a line can rise because slower students left.")))
    })

    output$method_required <- renderUI({
      p <- payload(); req(has_rows(p))
      m <- p$required$meta
      tags$ul(
        tags$li(paste0("Everyone counted here left without a degree with ", p$meta$line, " credits or more. A count is ",
                       "how many of them had that history in the course, not how many of the course's students ",
                       "went on to leave, and it does not say the course is why they left.")),
        tags$li(paste0("A student's program is the one on their last term's record, matched to its degree plan; a ",
                       "pre-major counts under the plan it leads to, and a student with two majors under each. The ",
                       "plan is the current catalog's, not the one a student entered under.")),
        tags$li(paste0("Each course the plan names is counted by itself, a lab apart from its lecture. Passed means a ",
                       "passing grade here, on any campus. Tried means a grade or a late withdrawal here and never a pass.")),
        tags$li(paste0("No attempt here is not the same as still required: the course may have been met by transfer or ",
                       "test credit, or before the class lists begin. Only the tried count says a student met the ",
                       "course and did not get through it.")),
        tags$li(paste0("Choices, elective space, general education and the math and English starting courses are not ",
                       "read. A course no one had taken under the plan's number by these students' last terms shows a dash.")),
        tags$li(paste0("A plan with fewer than ", m$min_n, " such students is not listed: ", n(m$n_plans_withheld),
                       if (m$n_plans_withheld == 1L) " plan, " else " plans, ", n(m$n_students_withheld),
                       if (m$n_students_withheld == 1L) " student." else " students.")))
    })
  })
}
