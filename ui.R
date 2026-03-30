# ============================================================================
# UI Definition for Cedar Analytics Application
# ============================================================================
#
# DEPENDENCIES (loaded via global.R):
#   - data_objects[["cedar_sections"]]  - Course sections (DESRs)
#   - data_objects[["cedar_students"]]  - Student enrollments (class lists)
#   - data_objects[["cedar_programs"]]  - Student programs (academic studies)
#   - data_objects[["cedar_degrees"]]   - Degree completions
#   - data_objects[["cedar_faculty"]]   - Faculty information
#
# DATA MODEL: CEDAR (lowercase column names, no backticks)
#   - All data uses CEDAR naming conventions (e.g., campus, department, term)
#   - No legacy column names (e.g., CAMP, DEPT, TERM)
#
# ============================================================================

# Convenience variables for UI (all from data_objects loaded in global.R)
cedar_sections <- data_objects[["cedar_sections"]]
cedar_students <- data_objects[["cedar_students"]]
cedar_programs <- data_objects[["cedar_programs"]]
cedar_degrees <- data_objects[["cedar_degrees"]]
cedar_faculty <- data_objects[["cedar_faculty"]]

# Helper: named vector of dept choices (dept_name → dept_code) for selectizeInput dropdowns.
# Source: cedar_lookups$dept_name_lookup, derived from subj_dept_map in transform-to-cedar.R.
# Falls back to raw dept_codes if lookups not available.
.dept_choices <- local({
  # Restrict to departments with sections at main academic campuses (ABQ + EA).
  # This excludes branch-campus-only vocational/continuing-ed units (e.g., ADOB/Adobe)
  # that clutter the list for main-campus users. Branch campus departments are still
  # accessible on the dashboard when a branch campus is explicitly selected.
  main_campus_codes <- c("ABQ", "EA")
  main_campus_depts <- unique(cedar_sections$department[
    !is.na(cedar_sections$department) &
    cedar_sections$department != "" &
    cedar_sections$campus %in% main_campus_codes
  ])
  lkp <- data_objects[["cedar_lookups"]][["dept_name_lookup"]]
  if (!is.null(lkp) && nrow(lkp) > 0) {
    lkp <- lkp[lkp$dept_code %in% main_campus_depts, ]
    lkp <- lkp[order(lkp$dept_name), ]
    setNames(lkp$dept_code, lkp$dept_name)
  } else {
    sort(main_campus_depts)
  }
})

# Define UI for application
ui <- page_navbar(
  id = "main_navbar",  # Add ID to enable tab switching

  tags$head(
    # Scroll to top on load — prevents browser autofocus on first input from
    # jumping the page down past the navbar.
    tags$script("document.addEventListener('DOMContentLoaded', function() {
      window.scrollTo(0, 0);
      if (document.activeElement) document.activeElement.blur();
    });"),
    includeCSS("www/cedar-custom.css"),
    
    # Initialize tooltips and localStorage for changelog
    tags$script(HTML("
      $(document).ready(function(){
        $('[data-toggle=\"tooltip\"]').tooltip();
        
        // Re-initialize tooltips when new content is added
        $(document).on('shiny:value', function(event) {
          setTimeout(function() {
            $('[data-toggle=\"tooltip\"]').tooltip();
          }, 100);
        });
        
        // Close any open dropdowns when page loads with URL parameters
        if (window.location.search) {
          setTimeout(function() {
            $('.navbar-nav .dropdown').removeClass('show');
            $('.navbar-nav .dropdown-toggle').removeClass('show').attr('aria-expanded', 'false');
            $('.navbar-nav .dropdown-menu').removeClass('show');
          }, 100);
        }
      });
      
      // Check localStorage for changelog version AFTER Shiny is connected
      $(document).on('shiny:connected', function(event) {
        console.log('[CEDAR] Shiny connected, checking localStorage for version');
        var seenVersion = localStorage.getItem('cedar_changelog_version');
        console.log('[CEDAR] localStorage cedar_changelog_version:', seenVersion);
        
        // Always send the seen version to server for comparison
        // Server will decide if modal should show based on current version
        Shiny.setInputValue('cedar_last_seen_version', seenVersion || 'none', {priority: 'event'});
        console.log('[CEDAR] Sent last seen version to server:', seenVersion || 'none');
      });
      
      // Register custom message handler to update version when user sees modal
      $(document).ready(function() {
        Shiny.addCustomMessageHandler('cedar_mark_changelog_version', function(message) {
          console.log('[CEDAR] Received message to mark changelog version:', message.version);
          localStorage.setItem('cedar_changelog_version', message.version);
          console.log('[CEDAR] localStorage version set to:', message.version);
        });
      });
    "))
  ),
  
  title = "CEDAR",
  #fixed = FALSE,



############################
# EXPLORE YOUR UNIT PANEL
############################

nav_panel(
  title = "Dept Dashboard",
  icon = icon("compass"),

  div(
    style = "max-width: 1200px; margin: 0 auto; padding: 20px 10px;",

    # Header
    fluidRow(
      column(12,
        h2(paste0(cedar_current_term_label, " Dashboard"), style = "margin-bottom: 4px;"),
        p("Pick a department to see what's happening — where students are growing,
          what interests they bring, and where there's more to discover.",
          style = "color: #666; margin-bottom: 20px;")
      )
    ),

    # Campus + department selectors — auto-loads on change, no button needed
    {
      # Use campus codes from cedar_sections — these match the campus column in
      # cedar_students and cedar_sections used by the dashboard filters.
      campus_vals <- sort(unique(cedar_sections$campus[
        !is.na(cedar_sections$campus) & cedar_sections$campus != ""]))
      # Default to ABQ (main campus) + EA (online).
      default_campus <- campus_vals[grepl("^ABQ$|^Main$|Albuquer|^EA$|^Online$", campus_vals,
                                          ignore.case = TRUE)]
      if (length(default_campus) == 0) default_campus <- ""
    fluidRow(
      column(3,
        selectizeInput(
          inputId   = "dashboard_campus",
          label     = "Campus",
          multiple  = TRUE,
          choices   = campus_vals,
          selected  = default_campus
        )
      ),
      column(4,
        selectizeInput(
          inputId  = "dashboard_dept",
          label    = "Department",
          multiple = FALSE,
          choices  = c("Select a department..." = "", .dept_choices),
          selected = ""
        )
      ),
      # Subject dropdown removed for stripped-down dashboard
    )
    }, # end campus default block

    # Progress bar — client-side CSS animation, starts immediately on dept change.
    # The R thread is blocked during computation so the server can't push updates;
    # instead the bar fills over the expected load time (sent by server at session
    # start from the timing log) and snaps to 100% when the headcount cards render.
    div(
      id    = "dashboard-progress-wrap",
      style = "display:none; padding: 6px 0 10px 0;",
      div(
        style = "height: 4px; background: #e9ecef; border-radius: 2px; overflow: hidden;",
        div(id    = "dashboard-progress-fill",
            style = "height:100%; width:0%; background:#1565c0; border-radius:2px;")
      ),
      div(id    = "dashboard-progress-label",
          style = "font-size:0.78em; color:#777; margin-top:5px;")
    ),

    tags$script(HTML(paste0('
    (function() {
      // expectedSec is embedded at page render time from the timing log.
      // No async message needed — eliminates the race condition with shiny:inputchanged.
      var expectedSec = ', {
        avg <- get_average_report_time("dept_dashboard")
        if (!is.null(avg)) round(avg) else 20L
      }, ';
      var hideTimer = null;

      $(document).on("shiny:inputchanged", function(e) {
        if (e.name !== "dashboard_dept") return;
        if (e.value && e.value !== "") startProgress();
        else                            hideProgress();
      });

      // Complete the bar when the server sends actual + average timing.
      Shiny.addCustomMessageHandler("dashboard_load_complete", function(msg) {
        completeProgress(msg.duration_sec, msg.avg_sec);
      });

      function startProgress() {
        clearTimeout(hideTimer);
        var wrap  = document.getElementById("dashboard-progress-wrap");
        var fill  = document.getElementById("dashboard-progress-fill");
        var label = document.getElementById("dashboard-progress-label");
        if (!wrap) return;
        wrap.style.display = "block";
        wrap.style.opacity = "1";
        fill.style.transition = "none";
        fill.style.width = "0%";
        label.textContent = "Loading\u2026 (est. " + Math.round(expectedSec) + "s)";
        fill.offsetWidth;  // force reflow so the 0% registers before transition
        // Ease-out: rushes to ~60% then decelerates, leaving headroom for variance
        fill.style.transition = "width " + expectedSec + "s cubic-bezier(0.1, 0.8, 0.2, 1)";
        fill.style.width = "85%";
      }

      function completeProgress(durationSec, avgSec) {
        var wrap  = document.getElementById("dashboard-progress-wrap");
        var fill  = document.getElementById("dashboard-progress-fill");
        var label = document.getElementById("dashboard-progress-label");
        if (!wrap || wrap.style.display === "none") return;
        fill.style.transition = "width 0.3s ease";
        fill.style.width = "100%";
        // Show discrete timing summary, then fade the whole bar out
        var txt = "Loaded in " + durationSec + "s";
        if (avgSec !== null && avgSec !== undefined) txt += " \u00b7 avg " + avgSec + "s";
        label.textContent = txt;
        hideTimer = setTimeout(function() {
          wrap.style.transition = "opacity 0.8s ease";
          wrap.style.opacity = "0";
          setTimeout(function() {
            wrap.style.display = "none";
            wrap.style.transition = "";
            wrap.style.opacity = "1";
            fill.style.transition = "none";
            fill.style.width = "0%";
            label.textContent = "";
          }, 800);
        }, 3000);
      }

      function hideProgress() {
        clearTimeout(hideTimer);
        var wrap = document.getElementById("dashboard-progress-wrap");
        var fill = document.getElementById("dashboard-progress-fill");
        if (!wrap) return;
        wrap.style.display = "none";
        wrap.style.opacity = "1";
        fill.style.transition = "none";
        fill.style.width = "0%";
      }
    })();
    '))),

    # Placeholder shown before a department is selected
    conditionalPanel(
      condition = "input.dashboard_dept == ''",
      div(
        style = "text-align: center; padding: 40px 0;",
        #tags$img(src = "cedar-sketch.png", style = "max-width: 100%; max-height: 80vh; opacity: 0.85;")          
      )
    ),

    # Dashboard content — shown only when a department is selected
    conditionalPanel(
      condition = "input.dashboard_dept != ''",

    # Headcount: stat cards + sparkline
    h4("Students", style = "margin-top: 8px; margin-bottom: 12px; color: #333;"),
    uiOutput("dashboard_headcount_cards"),
    plotOutput("dashboard_headcount_sparkline", height = "200px"),

    hr(style = "margin: 24px 0;"),

    # Current-term enrollment vs historical average
    fluidRow(
      column(6,
        h4("\u2191 Above Average This Term", style = "color: #2e7d32; margin-bottom: 8px;"),
        p("Courses running higher than their historical average enrollment.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_above_avg_courses")
      ),
      column(6,
        h4("\u2193 Below Average This Term", style = "color: #c62828; margin-bottom: 8px;"),
        p("Courses running lower than their historical average enrollment.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_below_avg_courses")
      )
    ),

    hr(style = "margin: 24px 0;"),

    # New this term and missing vs. last year
    fluidRow(
      column(6,
        h4("\u2728 New This Term", style = "color: #1565c0; margin-bottom: 8px;"),
        p("Courses with no prior offering in the data — first time on the schedule.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_new_courses")
      ),
      column(6,
        h4("\u23f8 Missing vs. Two Years Ago", style = "color: #888; margin-bottom: 8px;"),
        p("Courses offered in this same term two years ago that aren't running now.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_dormant_courses")
      )
    ),

    hr(style = "margin: 24px 0;"),

    # Repeated topics slots
    h4("Recurring Topics This Term", style = "margin-bottom: 8px;"),
    p("Topics courses running this term that have been offered at least twice before.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 12px;"),
    uiOutput("dashboard_repeated_topics"),

    hr(style = "margin: 24px 0;"),

    # Drop rate stats for current term — stacked early/late, each with below|above columns
    h4("Drop Rates This Term", style = "margin-bottom: 8px;"),
    p("Rates as % of class list, same term type only. Sections by course level;",
      " rows ordered by rate. Diff shown vs. each course\u2019s own historical avg.",
      " Level avg shown in section header.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 12px;"),
    h5("Early Drops (pre-census DR)", style = "color: #555; margin-bottom: 6px;"),
    uiOutput("dashboard_early_drops"),
    hr(style = "margin: 16px 0;"),
    h5("Late Drops (DW/DG)", style = "color: #555; margin-bottom: 6px;"),
    uiOutput("dashboard_late_drops"),

    hr(style = "margin: 24px 0;"),

    # Visual row: donut + credit hour trendlines
    fluidRow(
      column(5,
        h4("Where Your Majors Also Study", style = "margin-bottom: 8px;"),
        p("Minors declared by students in this department.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        plotlyOutput("dashboard_cross_dept_minors", height = "320px")
      ),
      column(7,
        h4("Credit Hour Production by Course Level", style = "margin-bottom: 8px;"),
        p("Five-year trend in student credit hours earned.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        plotlyOutput("dashboard_credit_hours", height = "320px")
      )
    ),

    hr(style = "margin: 24px 0;"),

    # Student composition — who's in your courses?
    h4("Who's in your Courses?", style = "margin-bottom: 4px;"),
    p("Major and class-standing breakdown for home-dept sections, lower and upper division only.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 12px;"),

    h5("By Major", style = "color: #555; margin-bottom: 6px;"),
    fluidRow(
      column(6,
        p("Lower Div \u2014 Current term", style = "text-align:center; color:#666; font-size:0.85em; margin-bottom:2px;"),
        plotlyOutput("dashboard_lower_major_current", height = "300px")
      ),
      column(6,
        uiOutput("dashboard_lower_major_table")
      )
    ),
    fluidRow(
      column(6,
        p("Upper Div \u2014 Current term", style = "text-align:center; color:#666; font-size:0.85em; margin-bottom:2px;"),
        plotlyOutput("dashboard_upper_major_current", height = "300px")
      ),
      column(6,
        uiOutput("dashboard_upper_major_table")
      )
    ),

    h5("By Class Standing", style = "color: #555; margin-top: 16px; margin-bottom: 6px;"),
    fluidRow(
      column(6,
        p("Lower Div \u2014 Current term", style = "text-align:center; color:#666; font-size:0.85em; margin-bottom:2px;"),
        plotlyOutput("dashboard_lower_class_current", height = "300px")
      ),
      column(6,
        uiOutput("dashboard_lower_class_table")
      )
    ),
    fluidRow(
      column(6,
        p("Upper Div \u2014 Current term", style = "text-align:center; color:#666; font-size:0.85em; margin-bottom:2px;"),
        plotlyOutput("dashboard_upper_class_current", height = "300px")
      ),
      column(6,
        uiOutput("dashboard_upper_class_table")
      )
    )

    ) # end conditionalPanel (dept selected)
  )
), # end Explore Your Unit nav_panel

######################
# ENROLLMENT NAV PANEL
########################

nav_panel(
  title = "Enrollment",
  icon = icon("chart-bar"),

    div(class = "filters-compact",
    fluidRow(
      column(1,
             selectizeInput(
               inputId = "enrl_campus",
               label = "Campus",
               multiple = TRUE,
               choices  = sort(unique(cedar_sections$campus)),
               selected = c("ABQ", "EA")),
      ),
      column(1,
             selectizeInput(
               inputId = "enrl_college",
               label = "College", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$college))),
      ),
      column(3,
             selectizeInput(
               inputId = "enrl_dept",
               label = "Department",
               multiple = TRUE,
               choices = .dept_choices),
      ),
      column(1,
             selectInput(
               inputId = "enrl_term",
               label = "Term",
               multiple = TRUE,
               choices = sort(unique(c(cedar_sections$term_type,cedar_sections$term)),decreasing = TRUE)),
      ),

      column(2,
             selectizeInput(
               inputId = "enrl_course",
               label = "Course",
               multiple = TRUE,
               choices = NULL),
      ),
      column(2,
             selectizeInput(
               inputId = "enrl_agg_by",
               label = "Group by",
               multiple = TRUE,
               choices = c("campus", "college", "subject_course", "course_title", "department", "term", "term_type", "part_term", "delivery_method", "instructor_name", "gen_ed_area")),
      ),

    ), # end fluidRow
    fluidRow(
      column(3,
             selectizeInput(
               inputId = "enrl_inst",
               label = "Instructor",
               multiple = TRUE,
               choices = NULL,
               options = list(placeholder = "Type to search instructors...")),
      ),
      # column(1,  # Method filter — hidden to save space; re-enable if needed
      #        selectInput(
      #          inputId = "enrl_im",
      #          label = "Method",
      #          multiple = TRUE,
      #          choices = sort(unique(cedar_sections$delivery_method))),
      # ),
      column(1,
             selectInput(
               inputId = "enrl_pt",
               label = "PoT",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$part_term))),
      ),
      column(1,
             selectInput(
               inputId = "enrl_level",
               label = "Level",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$level))),
      ),
      # column(1,  # Gen Ed filter — hidden to save space; re-enable if needed
      #        selectInput(
      #          inputId = "enrl_gen_ed",
      #          label = "Gen Ed",
      #          multiple = TRUE,
      #          choices = sort(unique(cedar_sections$gen_ed_area))),
      # ),
      column(1,
        numericInput("enrl_min", "Min", value = 1, min = 0, step = 1)
      ),
      column(1,
        numericInput("enrl_max", "Max", value = max(cedar_sections$total_enrl, na.rm = TRUE), min = 0, step = 1)
      ),
      column(5,
        div(style = "display: flex; align-items: flex-end; gap: 10px; height: 100%; padding-bottom: 2px;",
          tags$div(
            tags$label("Exclude List", class = "control-label"),
            checkboxInput(inputId = "enrl_uel", label = "Use", value = TRUE)
          ),
          actionButton("enrl_button",
                       label = "Gather Enrollments",
                       class = "btn-success",
                       icon = icon("sync-alt")),
          uiOutput("enrl_download_button_ui")
        )
      )
    ), # end fluidRow

    ), # end filters-compact div

    tags$hr(style = "margin: 6px 0 4px 0; border-color: #dee2e6;"),

    # Tabbed output area (shares the filter controls above)
    navset_tab(
      id = "enrl_output_tabs",

      # DESR section-level data with crosslist sub-navigation
      nav_panel(
        title = "DESR",
        icon = icon("table"),
        # Crosslist view selector — tabs filter the DT below without re-querying
        navset_tab(
          id = "enrl_crosslist_tabs",
          selected = "home",
          nav_panel(
            title = "Home", value = "home",
            p("Your department's home/primary sections, plus non-crosslisted courses.",
              "Crosslisted sections show their partner course(s) in the Partners column.",
              style = "color: #666; font-size: 0.85rem; margin-bottom: 0;")
          ),
          nav_panel(
            title = "Split-level", value = "split",
            p("Sections crosslisted across the undergraduate/graduate divide",
              "(upper-division paired with a graduate section of the same course).",
              style = "color: #666; font-size: 0.85rem; margin-bottom: 0;")
          ),
          nav_panel(
            title = "Crosslisted", value = "xl-home",
            p("Your department's sections that also appear under another department's course number.",
              style = "color: #666; font-size: 0.85rem; margin-bottom: 0;")
          ),
          nav_panel(
            title = "Away", value = "away",
            p("Sections owned by another department but crosslisted under your department's number.",
              style = "color: #666; font-size: 0.85rem; margin-bottom: 0;")
          ),
          nav_panel(
            title = "All", value = "all",
            p("All sections including every crosslist partner.",
              style = "color: #666; font-size: 0.85rem; margin-bottom: 0;")
          )
        ),
        div(style = "margin-top: 4px;"),
        DTOutput("enrl_summary")
      ),

      # Class list enrollment
      nav_panel(
        title = "Classlist",
        icon = icon("list"),
        DTOutput("enrl_cl_summary")
      ),

      # Enrollment plots — facet control lives here
      nav_panel(
        title = "Plots",
        icon = icon("chart-line"),
        fluidRow(
          column(3,
            selectInput(
              inputId = "enrl_facet_field",
              label = "Facet by",
              choices = c(
                "None" = "",
                "Term Type" = "term_type",
                "Campus" = "campus",
                "Department" = "department",
                "Course" = "subject_course",
                "Level" = "level",
                "Delivery Method" = "delivery_method"
              ),
              selected = "",
              multiple = FALSE
            )
          )
        ),
        uiOutput("enrl_plot_card")
      ),

      # Low enrollment — mode banner, summary cards, thresholds, then level sub-tabs
      nav_panel(
        title = "Low Enrollment",
        value = "low_enrl",
        icon = icon("exclamation-triangle"),

        # Mode banner — shown when a future term triggers concerns mode
        uiOutput("enrl_mode_banner"),

        # Summary stat cards — shown above sub-tabs once data is gathered
        uiOutput("low_enrl_summary"),

        # Threshold and enrollment range controls
        div(style = "display: flex; align-items: flex-end; gap: 20px; padding: 4px 0 8px 0;",
          span("Thresholds:", style = "font-weight: 600; color: #555; padding-bottom: 6px; white-space: nowrap;"),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_lower", "Lower div", value = 15, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_upper", "Upper div", value = 15, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_split", "Split-level", value = 10, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_grad", "Graduate", value = 5, min = 1, max = 100, step = 1)
          )
        ),

        navset_tab(
          id = "low_enrl_tabs",
          nav_panel(
            title = "Lower",
            icon = icon("exclamation-triangle"),
            br(),
            DTOutput("low_enrl_table_lower")
          ),
          nav_panel(
            title = "Upper",
            icon = icon("exclamation-triangle"),
            br(),
            DTOutput("low_enrl_table_upper")
          ),
          nav_panel(
            title = "Split",
            icon = icon("exclamation-triangle"),
            br(),
            p("Crosslisted courses that span the undergraduate/graduate boundary (at least one section \u2264499 and one \u2265500). The Sections column shows all partner courses in the group. Enrollment is the combined total.",
              style = "color: #666; font-size: 0.9em; margin-bottom: 0.75rem;"),
            DTOutput("low_enrl_table_split")
          ),
          nav_panel(
            title = "Graduate",
            icon = icon("exclamation-triangle"),
            br(),
            DTOutput("low_enrl_table_grad")
          ),
          nav_panel(
            title = "Methodology",
            icon = icon("circle-question"),
            br(),
            div(style = "max-width: 700px;",
              h4("How Low Enrollment works"),
              tags$ul(
                tags$li(strong("Thresholds"), " — set per-level minimums above. A section appears in alerts mode when its combined enrollment falls below its level's threshold."),
                tags$li(strong("Home sections only"), " — only the administrative home section of a crosslisted course appears; the combined enrollment across all partner sections is shown."),
                tags$li(strong("Excluded courses"), " — independent studies, thesis credits, and similar special-enrollment courses are excluded by default (see below).")
              ),

              h4("Excluded courses"),
              p("Certain courses \u2014 independent studies, thesis credits, dissertation credits,
                honors credits, and similar special-enrollment courses \u2014 are excluded from the
                low enrollment analysis. These courses are expected to have very low or
                individually-arranged enrollment and would otherwise dominate the results. The
                excluded list is maintained in", code("R/lists/excluded_courses.R"),
                "and currently contains approximately 200 course codes."),

              h4("Home section \u2014 what it means and how it's determined"),
              p("When a course is crosslisted, only the", strong("home (primary) section"),
                "appears in the tables \u2014 the section that is administratively responsible for the
                course. Showing every crosslisted row would double- or triple-count courses."),
              p("Home section is identified using the", strong("SHORT_TEXT field"), "from MyReports,
                which contains a note like", code('"HIST home 202610"'), "identifying which department
                owns the crosslist. This is the registrar-authoritative signal."),
              p("When SHORT_TEXT is absent (roughly 85% of crosslist groups, particularly
                same-department split-level courses), the section with the",
                strong("highest section-level enrollment"), "is treated as home. Ties are broken
                alphabetically by subject code."),
              p(em("When a department with lower enrollment appears as home, it is because SHORT_TEXT
                explicitly identified it \u2014 not an error in the data.")),

              h4("Course levels"),
              tags$ul(
                tags$li(strong("Lower division:"), " course numbers below 300 (and 1000+)"),
                tags$li(strong("Upper division:"), " course numbers 300\u2013499"),
                tags$li(strong("Graduate:"), " course numbers 500\u2013699"),
                tags$li(strong("Split-level:"), " a crosslisted group spanning the undergraduate/graduate
                  boundary (at least one section \u2264499 and at least one \u2265500). Sections retain their
                  original level (upper/grad) but are flagged as split-level and appear in the
                  Split-Level tab with a separate, lower threshold. The Split Partners column shows
                  all partner courses in the group (e.g., 'BIOL 402 / BIOL 502').")
              ),
              p("Lab sections (course numbers ending in L, e.g., EDUC 331L) are classified by their
                numeric base (331 \u2192 upper division)."),

              h4("Section counts and course totals"),
              p("The", strong("Sects"), "column shows the number of active home sections of that
                course in the selected term and campus.", strong("Course Total"), "is the sum of",
                code("total_enrl"), "across those sections. Both are computed from sections where",
                code("status = 'A'"), "and", code("crosslist_primary = TRUE"),
                ", grouped by term, course, and campus."),

              h4("Thresholds"),
              p("Each level has its own threshold. In alerts mode, a section appears when",
                code("total_enrl < threshold"), ". In concerns mode, a course appears when",
                code("avg_enrl < threshold + 5"), "(the +5 buffer catches courses near the boundary)
                or when the course has no prior history. Defaults (15 / 15 / 10 / 5) reflect typical
                minimum viability targets, not institutional policy \u2014 adjust as needed using the
                Thresholds fields above the tabs."),

              h4("Future Term: Historical Enrollment Concerns"),
              p("When you select a term that is beyond the current term (",
                code("cedar_current_term"), " in config), CEDAR switches to",
                strong("concerns mode"), ". Instead of flagging courses with low current enrollment,
                it identifies courses on the future schedule whose historical enrollment pattern
                suggests they may struggle to meet minimum viability targets."),

              h5("How historical averages are computed"),
              tags$ol(
                tags$li("The system identifies all prior terms of the same type (e.g., all past
                        falls for a Fall 2026 schedule). Only terms in the DESR data are included."),
                tags$li("For each course on the future schedule, it sums ", code("total_enrl"),
                        " across all home sections (",  code("crosslist_primary = TRUE"),
                        ") in each prior term, then averages the last 4 available terms."),
                tags$li("Courses are matched by ", code("subject_course"), " and ", code("campus"),
                        " \u2014 history for HIST 1105 at ABQ is computed separately from HIST 1105
                        at Valencia."),
                tags$li("Only active terms (those with at least one active section) contribute to the
                        average and trend. Cancelled terms appear in the history column as 'C' but
                        do not affect the average."),
                tags$li("The historical average is compared against the same per-level thresholds
                        used for actual enrollment alerts, with a +5 student buffer zone (see
                        Thresholds above).")
              ),

              h5("What's excluded from history"),
              tags$ul(
                tags$li(strong("Shell/placeholder sections:"), " Sections that are active (status A) with
                        zero enrollment and no instructor assigned are excluded. These are sections left
                        in the schedule build that were never genuinely offered."),
                tags$li(strong("Cancelled sections:"), " Sections with status 'C' are included in
                        the historical record so you can see when a course was scheduled but later
                        cancelled (shown as 'C' in the Prior History column). However, cancelled
                        terms do not contribute to the historical average or trend calculation.")
              ),

              h5("Trend detection"),
              p("A linear regression slope is computed across enrollment values from active (non-cancelled)
                historical terms. A slope greater than +1 student/term is labeled",
                strong("\u2191 up"), "; less than \u22121 is", strong("\u2193 down"),
                "; between \u22121 and +1 is", strong("\u2194 stable"), ". If fewer than 2 active
                terms are available, trend shows", strong("\u2014"), "(insufficient data)."),

              h5("Color coding (concerns mode)"),
              tags$ul(
                tags$li(strong("Red:"), " Historical average is below 50% of the threshold.
                        These courses have consistently underperformed."),
                tags$li(strong("Yellow:"), " Historical average is 50\u201375% of the threshold.
                        These are borderline courses."),
                tags$li(strong("Blue:"), " Historical average is 75\u2013100% of the threshold.
                        Watch-list courses."),
                tags$li(strong("Green:"), " Historical average meets or exceeds the threshold.
                        Shown in the buffer zone (up to 5 students above threshold)."),
                tags$li(strong("Gray:"), " No prior history available (new course or first offering
                        of this term type).")
              ),

              h5("Limitations"),
              tags$ul(
                tags$li("Course-level totals: the analysis focuses on total enrollment per course,
                        not individual section enrollment."),
                tags$li("New courses with no prior history of the same term type appear with a
                        'No prior history' indicator and are always shown regardless of threshold."),
                tags$li("The analysis does not account for changes in number of sections offered,
                        delivery method shifts, or curricular changes that might affect enrollment."),
                tags$li("History matching uses ", code("subject_course"), " and ", code("campus"),
                        " only. If a course was renumbered or moved between departments, its prior
                        history under the old number will not be linked.")
              ),

              hr(),
              p("Source: MyReports DESR data. Transformation pipeline:",
                code("R/data-parsers/parse-DESR.R"), "\u2192",
                code("R/data-parsers/transform-to-cedar.R"), ". Home section detection:",
                code("transform-to-cedar.R"), ". Excluded courses:",
                code("R/lists/excluded_courses.R"), ". Low enrollment functions:",
                code("R/cones/enrl.R"), ". Combined enrollment per section:",
                code("total_enrl = max(ENROLLED, XL_TOTAL_ENROLLMENT)"), ".",
                style = "color: #888; font-size: 0.88em;")
            )
          )
        )
      ),

      # Multi-year enrollment trends (growing / declining) — single dept only
      nav_panel(
        title = "Trends",
        icon = icon("chart-line"),
        p("Multi-year enrollment trends for this department. Select a single department to see results.",
          style = "color: #666; font-size: 0.88em; margin-bottom: 16px;"),
        fluidRow(
          column(6,
            h4("\u2191 Growing Courses", style = "color: #2e7d32; margin-bottom: 8px;"),
            p("Courses with sustained enrollment increases over recent terms.",
              style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
            uiOutput("enrl_trends_growing")
          ),
          column(6,
            h4("\u2193 Worth a Look", style = "color: #c62828; margin-bottom: 8px;"),
            p("Courses with declining enrollment — may reflect scheduling, sequencing, or program changes.",
              style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
            uiOutput("enrl_trends_investigate")
          )
        )
      ),

      # General enrollment methodology — filters, grouping, DESR vs classlist, crosslists
      nav_panel(
        title = "Methodology",
        icon = icon("circle-question"),
        br(),
        div(style = "max-width: 700px;",
          h4("Filter panel"),
          p("The filter controls above apply to all tabs. Selections narrow the data before any
            grouping or enrollment calculation."),
          tags$ul(
            tags$li(strong("Campus / College / Department / Term / Course:"), " Standard drill-down
              filters. Use Term to select a specific term or term type (e.g., 'Fall' to compare
              all fall semesters)."),
            tags$li(strong("Group by:"), " Collapses individual sections into grouped rows.
              Enrollment values are summed across the group. For example, grouping by ",
              code("subject_course"), " shows one row per course with total enrollment across all
              its sections. Adding ", code("term"), " alongside ", code("subject_course"),
              " shows trends over time."),
            tags$li(strong("Exclude List:"), " When checked, removes independent studies, thesis
              credits, dissertation credits, honors credits, and similar special-enrollment courses
              from results. The list is maintained in ", code("R/lists/excluded_courses.R"),
              " and contains approximately 200 course codes. Uncheck to include these courses."),
            tags$li(strong("Level:"), " Filters by course level (lower division, upper division,
              graduate)."),
            tags$li(strong("Min / Max:"), " Filters sections by enrollment count. Min defaults to
              1, which excludes zero-enrollment sections (typically scheduling placeholders). Set
              Min to 0 to include them.")
          ),

          h4("Enrollment counts: section vs. combined"),
          p("MyReports records enrollment at the individual section level. A crosslisted course
            with 8 students in the HIST section and 5 students in the ANTH section shows",
            em("8"), "and", em("5"), "in separate rows \u2014 not 13. The dashboard uses",
            code("total_enrl"), ", defined as",
            code("max(ENROLLED, XL_TOTAL_ENROLLMENT)"), "per section. For non-crosslisted
            sections this simply equals the section's own enrollment count; for crosslisted
            sections it equals the combined enrollment across all partner sections (the
            registrar's XL_TOTAL_ENROLLMENT figure)."),
          p("When you use Group by, enrollment values are summed from ", code("total_enrl"),
            " across all matching sections. Crosslisted courses grouped by ",
            code("subject_course"), " show the combined enrollment once (via the home section),
            not double-counted."),

          h4("DESR vs. Classlist"),
          p(strong("DESR"), " (Detail Enrollment Section Report) is section-level data from
            MyReports. Each row is one course section with its enrollment count, attributes, and
            crosslist information. Use DESR for section-level analysis, crosslist views, and low
            enrollment alerts."),
          p(strong("Classlist"), " is student-level data. Each row is one student enrollment in
            one section. Use Classlist when you need student-level detail \u2014 individual
            students, majors, class standings. Classlist does not include sections with zero
            enrollment."),

          h4("Crosslist views (DESR tab)"),
          tags$ul(
            tags$li(strong("Home:"), " Your department's home/primary sections, plus
              non-crosslisted courses. Crosslisted sections show their partner course(s) in the
              Partners column."),
            tags$li(strong("Split-level:"), " Sections crosslisted across the
              undergraduate/graduate divide (upper-division paired with a graduate section of the
              same course)."),
            tags$li(strong("Crosslisted:"), " Your department's sections that also appear under
              another department's course number."),
            tags$li(strong("Away:"), " Sections owned by another department but crosslisted under
              your department's number."),
            tags$li(strong("All:"), " All sections including every crosslist partner.")
          ),
          p("The Home view is the most common starting point for department-level analysis. It
            prevents double-counting by showing each crosslisted course once, under the
            administrative home department."),

          hr(),
          p("Source: MyReports DESR data. Transformation pipeline:",
            code("R/data-parsers/parse-DESR.R"), "\u2192",
            code("R/data-parsers/transform-to-cedar.R"), ". Combined enrollment per section:",
            code("total_enrl = max(ENROLLED, XL_TOTAL_ENROLLMENT)"), ".",
            style = "color: #888; font-size: 0.88em;")
        )
      )

    ) # end navset_tab
    
), # end nav_panel for enrollment



  # Headcount nav_panel removed from top level — now lives in Explore menu



  ######################
  # REGSTATS NAV PANEL
  ########################
  nav_panel(
    title = "Regstats",
    icon = icon("tachometer-alt"),

    # Page title
    h1("Registration Statistics Dashboard", style = "margin-bottom: 12px;"),

    div(class = "filters-compact",
      fluidRow(
        column(1,
               selectInput(
                 inputId = "rs_campus",
                 label = "Campus",
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$campus))),
        ),
        column(1,
               selectInput(
                 inputId = "rs_college",
                 label = "College",
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$college))),
        ),
        column(2,
               selectInput(
                 inputId = "rs_dept",
                 label = "Department",
                 multiple = TRUE,
                 choices = .dept_choices),
        ),
        column(2,
               selectInput(
                 inputId = "rs_term",
                 label = "Term",
                 multiple = TRUE,
                 choices = sort(unique(c(cedar_sections$term_type, cedar_sections$term)), decreasing = TRUE)),
        ),
        column(2,
               selectInput(
                 inputId = "rs_level",
                 label = "Level",
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$level))),
        ),
        column(2,
               selectInput(
                 inputId = "rs_im",
                 label = "Instruction Method",
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$delivery_method))),
        ),
        column(2,
               selectInput(
                 inputId = "rs_pt",
                 label = "PoT",
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$part_term))),
        ),
      ), # end fluidRow

      fluidRow(
        column(2,
               selectizeInput(
                 inputId = "rs_course",
                 label = "Course",
                 multiple = TRUE,
                 choices = NULL,
                 options = list(placeholder = "Type to search...")),
        ),
        column(2,
               numericInput(
                 inputId = "rs_min_impacted",
                 label = "Min Impacted",
                 value = cedar_regstats_thresholds[["min_impacted"]])
        ),
        column(2,
               numericInput(
                 inputId = "rs_pct_sd",
                 label = "SD %",
                 value = cedar_regstats_thresholds[["pct_sd"]])
        ),
        column(2,
               numericInput(
                 inputId = "rs_min_squeeze",
                 label = "Min Squeeze",
                 value = cedar_regstats_thresholds[["min_squeeze"]])
        ),
        column(2,
               numericInput(
                 inputId = "rs_min_wait",
                 label = "Min Waiting",
                 value = cedar_regstats_thresholds[["min_wait"]])
        ),
        column(2,
               actionButton("rs_dashboard_button",
                           label = "Generate Dashboard",
                           class = "btn-primary",
                           icon = icon("tachometer-alt")),
               tags$a(
                 id = "rs_report_download",
                 class = "shiny-download-link rs-download-link",
                 href = "", target = "_blank", download = NA,
                 icon("download"), " Download report"
               )
        ),
      ), # end fluidRow
    ), # end filters-compact
    
    # Content area for regstats dashboard
    uiOutput("rs_dashboard")
    
  ), # end regstats nav_panel




  # Pathways tab — cohort-aware curriculum analytics
  nav_panel(
    title = "Pathways",
    icon  = icon("route"),
    pathwaysUI(
      "pathways",
      campus_choices = sort(unique(cedar_programs$student_campus[
        !is.na(cedar_programs$student_campus) & nzchar(cedar_programs$student_campus)
      ]))
    )
  ), # end Pathways nav_panel

  # Explore dropdown menu
  nav_menu(
    title = "Explore",
    icon = icon("search"),

    nav_panel(
      title = "Open Seats",
      icon = icon("door-open"),

      # Page title
      h1("Open Seats"),

      # Instructional note
      p("Shows courses with available seats for the specified search parameters.
      It also provides DFW rates for those courses that have been offered in before with the same filtering parameters. No DFW rate means that the course has not been offered before with those parameters.
      It also provides tabs to see courses that were offered a year previously, courses not offered a year previously, and courses common to both terms.
      Gen Ed Likely tab shows courses that are active but with no enrollment and likely capped at 0 for now (e.g., gen ed courses not yet opened for enrollment).",
        style = "color: #666; font-size: 0.9em"),

      p("DFW rates reflect courses matching your selected filters (e.g., if you filter by 2H, DFW % is for 2H versions of those courses).",
        style = "color: #666; font-size: 0.9em"),
      
      fluidRow(
        column(1,
               selectizeInput(
                 inputId = "sf_campus",
                 label = "Campus", 
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$campus))),
        ),
        column(1,
               selectizeInput(
                 inputId = "sf_college",
                 label = "College", 
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$college))),
        ),

        column(2,
               selectizeInput(
                 inputId = "sf_dept",
                 label = "Department",
                 multiple = TRUE,
                 choices = .dept_choices),
        ),
        column(2,
               selectizeInput(
                 inputId = "sf_term",
                 label = "Term", 
                 multiple = TRUE,
                 choices = sort(unique(c(cedar_sections$term_type,cedar_sections$term)),decreasing = TRUE)),
        ),
        
        column(1,
               selectInput(
                 inputId = "sf_pt",
                 label = "PoT", 
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$part_term))),
        ),
        column(1,
               selectInput(
                 inputId = "sf_im",
                 label = "Method", 
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$delivery_method))),
        ),      
        column(2,
               selectInput(
                 inputId = "sf_level",
                 label = "Level", 
                 multiple = TRUE,
                 choices = sort(unique(cedar_sections$level))),
        ),
        # column(2,
        #        selectizeInput(
        #          inputId = "sf_agg_by",
        #          label = "Group by", 
        #          multiple = TRUE,
        #          choices = c("CAMP","COLLEGE","SUBJ_CRSE", "CRSE_TITLE", "DEPT", "TERM","term_type", "PT","INST_METHOD", "level", "gen_ed_area" )),
        # ),
        column(2,
               actionButton("sf_button",
                           label = "Refresh table", 
                           icon = icon("sync-alt"))
        )
      ), # end fluidRow
      
      tabsetPanel(
        tabPanel("Courses", DT::DTOutput("type_summary")),
        tabPanel("Common", DT::DTOutput("courses_common")),
        tabPanel("Prev", DT::DTOutput("courses_prev")),
        tabPanel("New", DT::DTOutput("courses_new")),
        tabPanel("Gen Ed", DT::DTOutput("gen_ed_summary")),
        tabPanel("Gen Ed Likely", DT::DTOutput("gen_ed_likely"))
      )
    ), # end open seats nav_panel
    
    nav_panel(
      title = "Waitlists",
      icon = icon("list-ol"),
      
      # Page title
      h1("Course Waitlist Reporting", style = "margin-bottom: 20px;"),
      
      fluidRow(
        column(6,
               selectizeInput(
                 inputId = "wl_course",
                 label = "Select Course", 
                 multiple = TRUE,
                 choices = NULL),
        ),
        column(6,
               actionButton("wl_button",
                           label = "Inspect Wait Lists", 
                           icon = icon("list-ol"))
        )
      ), # end fluidRow

      fluidRow(
        column(12,
          tags$h4("Waitlist by Count"),
          tags$p("This table shows the number of students on the waitlist for each course. The courses are sorted by the number of students on the waitlist."),
          DTOutput("wl_count")
        )
      ), # end fluidRow

      fluidRow(
        column(12,
          tags$h4("Waitlist by Major"),
          tags$p("This table shows the distribution of students on waitlists by their major. This can help identify which programs are most affected by course availability issues."),
          DTOutput("wl_majors")
        )
      ), # end fluidRow
      fluidRow(
        column(12,
          tags$h4("Waitlist by Classification"),
          tags$p("This table shows the distribution of students on waitlists by their classification (freshman, sophomore, etc.). This can help identify which student levels are most affected by course availability."),
          DTOutput("wl_classifications")
        )
      ) # end fluidRow
    ), # end waitlists nav_panel

    #####################
    # HEADCOUNT (inside Explore)
    #####################
    nav_panel(
      title = "Headcount",
      icon = icon("users"),

      h1("Student Headcount", style = "margin-bottom: 20px;"),
      fluidRow(
        column(4,
          selectizeInput(
            inputId = "hc_campus",
            label = "Select Campus",
            multiple = TRUE,
            choices = sort(unique(cedar_programs$student_campus[!is.na(cedar_programs$student_campus) & cedar_programs$student_campus != ""]))
          )
        ),
        column(4,
          selectizeInput(
            inputId = "hc_college",
            label = "Select College",
            multiple = TRUE,
            choices = sort(unique(cedar_programs$student_college[!is.na(cedar_programs$student_college) & cedar_programs$student_college != ""]))
          )
        ),
        column(4,
          selectizeInput(
            inputId = "hc_dept",
            label = "Select Department",
            multiple = TRUE,
            choices = .dept_choices
          )
        )
      ), #end fluidRow
      fluidRow(
        column(2,
          selectizeInput(
            inputId = "hc_major",
            label = "Select Major",
            multiple = TRUE,
            choices = sort(unique(cedar_programs$program_name[cedar_programs$program_type %in% c('Major', 'Second Major')]))
          )
        ),
        column(2,
          selectizeInput(
            inputId = "hc_minor",
            label = "Select Minor",
            multiple = TRUE,
            choices = sort(unique(cedar_programs$program_name[cedar_programs$program_type %in% c('First Minor', 'Second Minor')]))
          )
        ),
        column(2,
          selectizeInput(
            inputId = "hc_conc",
            label = "Select Concentration",
            multiple = TRUE,
            choices = sort(unique(cedar_programs$program_name[cedar_programs$program_type %in% c('First Concentration', 'Second Concentration', 'Third Concentration')]))
          )
        ),
        column(3,
          actionButton("hc_button",
                      label = "Update Table",
                      icon = icon("sync-alt"))
        )
      ), # end fluidRow

      card(
        card_header("Undergraduate Headcount"),
        style = "height:100vh; min-height:100vh; overflow-y:auto;",
        plotlyOutput("hc_undergrad_plot")
      ),

      card(
        card_header("Graduate Headcount"),
        style = "height:100vh; min-height:100vh; overflow-y:auto;",
        plotlyOutput("hc_grad_plot")
      )
    ), # end headcount nav_panel

    #####################
    # COURSE DYNAMICS (inside Explore)
    #####################
    nav_panel(
      title = "Course Dynamics",
      icon = icon("file-lines"),

      h1("Course Dynamics", style = "margin-bottom: 20px;"),
      p("Enrollment patterns, student flows, and grade distributions for a specific course."),

      fluidRow(
        column(3,
          selectizeInput(
            inputId = "cr_course",
            label = "Select Course:",
            choices = NULL,
            options = list(
              placeholder = "Type to search courses...",
              maxOptions = 20
            )
          )
        ),
        column(3,
          checkboxInput(
            "cr_skip_forecast",
            "Skip new forecasting",
            value = TRUE
          )
        ),
        column(3,
            actionButton(
              "cr_generate_button",
              "Generate Web Report",
              icon = icon("chart-line"),
              class = "btn-primary"
            )
        ),
        column(3,
            actionButton(
              "cr_download_button",
              "Download HTML Report",
              icon = icon("file-pdf"),
              class = "btn-info",
              style = "margin-left: 10px;"
            )
          )
      ), # end fluidRow

      navset_tab(
        id = "cr_tabs",

        nav_panel(
          "Enrollment",
          icon = icon("users"),
          br(),
          h4("Enrollment Trends"),
          plotlyOutput("cr_enrollment_plot", height = "400px"),
          br(),
          h4("Enrollment History"),
          DT::DTOutput("cr_enrollment_table")
        ),

        nav_panel(
          "Course Flows",
          icon = icon("arrow-right-arrow-left"),
          br(),
          h4("Student Flow Patterns"),
          p("Shows where students come from and go to relative to this course."),
          fluidRow(
            column(4,
              numericInput(
                "cr_flow_min_contrib",
                "Minimum students per term:",
                value = 2,
                min = 1,
                max = 50
              )
            ),
            column(4,
              numericInput(
                "cr_flow_max_courses",
                "Maximum courses to display:",
                value = 6,
                min = 3,
                max = 12
              )
            ),
            column(4,
              div(
                style = "margin-top: 25px;",
                actionButton(
                  "cr_update_flows",
                  "Update Flow Diagrams",
                  icon = icon("refresh")
                )
              )
            )
          ),
          br(),
          uiOutput("cr_flow_plots_ui")
        ),

        nav_panel(
          "Rollcall",
          icon = icon("user-check"),
          p("Shows the composition of students taking this course by classification and major."),

          fluidRow(
            column(2,
              selectizeInput(
                inputId = "cr_rollcall_campus",
                label = "Select Campus",
                multiple = TRUE,
                choices = sort(unique(cedar_sections$campus)),
                selected = "ABQ"
              )
            ),
            column(10,
              p("Filter by campus to see rollcall data for specific locations. Multiple campuses can be selected to report TOTALS.",
                style = "margin-top: 25px; color: #666; font-style: italic;")
            )
          ),

          h5("By Student Classification"),
          fluidRow(
            column(6, plotlyOutput("cr_rollcall_by_class_fall_plot", height = "400px")),
            column(6, plotlyOutput("cr_rollcall_by_class_spring_plot", height = "400px"))
          ),

          h5("By Major"),
          fluidRow(
            column(6, plotlyOutput("cr_rollcall_by_major_fall_plot", height = "400px")),
            column(6, plotlyOutput("cr_rollcall_by_major_spring_plot", height = "400px"))
          ),

          h5("Classification Trends Over Time"),
          fluidRow(
            column(12, plotlyOutput("cr_rollcall_by_class_time_plot", height = "400px"))
          ),

          h5("Major Trends Over Time"),
          fluidRow(
            column(12, plotlyOutput("cr_rollcall_by_major_time_plot", height = "400px"))
          ),

          h5("Data Tables"),
          fluidRow(
            column(12, DT::DTOutput("cr_rollcall_major_fall_table"))
          ),
          fluidRow(
            column(12, DT::DTOutput("cr_rollcall_class_fall_table"))
          )
        ),

        nav_panel(
          "Outcomes",
          icon = icon("graduation-cap"),
          uiOutput("cr_outcomes_ui")
        ),

        nav_panel(
          "DFW",
          icon = icon("chart-bar"),
          uiOutput("cr_dfw_tab_content")
        )
      ) # end navset_tab
    ), # end course dynamics nav_panel

    #####################
    # DEPARTMENT PROFILE (inside Explore)
    #####################
    nav_panel(
      title = "Department Profile",
      icon = icon("folder-tree"),

      h1("Department Profile", style = "margin-bottom: 20px;"),

      fluidRow(
        column(4,
          selectizeInput(
            inputId = "dept_report_dept",
            label = "Select Department",
            multiple = FALSE,
            choices = c("Select a department..." = "", .dept_choices),
            selected = ""
          )
        ),
        column(3,
          selectizeInput(
            inputId = "dept_report_campus",
            label = "Campus",
            multiple = TRUE,
            choices = c(),
            selected = NULL,
            options = list(placeholder = "All campuses")
          )
        ),
        column(2,
          tags$div(style = "margin-top: 25px;",
            uiOutput("dept_download_link", inline = TRUE)
          )
        )
      ),

      fluidRow(
        column(12,
          uiOutput("dept_report")
        )
      )

    ) # end department profile nav_panel

  ), # end Explore nav_menu

  # Admin dropdown menu
  nav_menu(
    title = "Admin",
    icon = icon("cog"),

  nav_panel(
    title = "Data & Usage",

    # Page title
    h1("Data Status & Usage Analytics", style = "margin-bottom: 20px;"),

    # Data Note (shown above tabs)
    div(
      style = "font-size: 0.85em; color: #666; margin-bottom: 8px;",
      "Data presented here is MyReports data — not official institutional data — and should not be used for required reporting purposes. ",
      "CEDAR tables are updated nightly for the current semester and +/- 1-2 terms."
    ),

    br(),

    # Tabbed interface for different sections
    navset_tab(
      id = "data_usage_tabs",

      # ── Tab 1: Data Summary (loads immediately) ────────────────────────
      nav_panel(
        title = "Data Summary",
        br(),
        div(
          p("Last updated information for all loaded datasets. This data is computed at startup.",
            style = "color: #666; font-size: 0.9em; margin-bottom: 6px;"),
          DT::dataTableOutput("data_status_table")
        )
      ),

      # ── Tab 2: Usage Overview (lazy loaded) ────────────────────────────
      nav_panel(
        title = "Usage Overview",
        br(),

        # Date range selector
        fluidRow(
          column(4,
            dateInput("usage_start_date", "Start Date:", value = Sys.Date())
          ),
          column(4,
            dateInput("usage_end_date", "End Date:", value = Sys.Date())
          ),
          column(4,
            br(),
            actionButton("refresh_usage_overview", "Refresh", class = "btn-primary", icon = icon("sync"))
          )
        ),

        br(),

        card(
          card_header("Usage Summary"),
          p("High-level overview of CEDAR usage during the selected date range."),
          uiOutput("usage_overview_ui")
        ),

        card(
          card_header("Most Used Features"),
          div(DT::dataTableOutput("tab_usage_table"), class = "dt-container")
        ),

        card(
          card_header("Department Profile"),
          div(DT::dataTableOutput("dept_reports_table"), class = "dt-container")
        ),

        card(
          card_header("Course Dynamics"),
          div(DT::dataTableOutput("course_reports_table"), class = "dt-container")
        )
      ),

      # ── Tab 3: Feature Details (lazy loaded) ───────────────────────────
      nav_panel(
        title = "Feature Details",
        br(),

        # Date range selector (shared reactive values from Usage Overview)
        fluidRow(
          column(4,
            dateInput("feature_start_date", "Start Date:", value = Sys.Date())
          ),
          column(4,
            dateInput("feature_end_date", "End Date:", value = Sys.Date())
          ),
          column(4,
            br(),
            actionButton("refresh_feature_details", "Refresh", class = "btn-primary", icon = icon("sync"))
          )
        ),

        br(),

        uiOutput("usage_stats_output"),

        card(
          card_header("Usage Event Log"),
          div(DT::dataTableOutput("feature_usage_table"))
        )
      ),

      # ── Tab 4: Cache Management (lazy loaded) ──────────────────────────
      nav_panel(
        title = "Cache",
        br(),

        card(
          card_header("Course Report Cache"),
          p("CEDAR caches expensive lookup calculations (course flow analysis) to speed up repeated course report requests. The cache automatically invalidates when data changes."),

          fluidRow(
            column(4,
              actionButton("refresh_cache_stats", "Refresh Stats", class = "btn-info", icon = icon("sync"))
            ),
            column(4,
              actionButton("clear_all_cache", "Clear All Cache", class = "btn-warning", icon = icon("trash"))
            )
          ),

          br(),
          div(DT::dataTableOutput("cache_stats_table"), class = "dt-container")
        ),

        card(
          card_header("Department Profile Cache"),
          p("Department profile reports are cached to disk after first generation. The cache invalidates automatically when source data changes. Use this button after manually correcting data or when reports look stale."),

          actionButton("clear_dept_cache", "Clear Dept Profile Cache", class = "btn-warning", icon = icon("trash"))
        )
      )
    ) # end navset_tab
  ), # end data & usage nav_panel
  
nav_panel(
    title = "Changelog",
    icon = icon("history"),
    h1("CEDAR Changelog", style = "margin-bottom: 20px;"),
    
    fluidRow(
      column(12,
        card(
          card_header("Recent Updates"),
          card_body(
            htmlOutput("changelog_recent")
          )
        )
      )
    ),
    
    fluidRow(
      column(12,
        card(
          card_header("All Changes"),
          card_body(
            htmlOutput("changelog_full")
          )
        )
      )
    )
  )
) # end Admin nav_menu

) # end ui

