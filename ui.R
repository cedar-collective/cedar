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
    # Switch to the URL-requested tab immediately at DOM-ready, before the Shiny
    # WebSocket connects. This prevents the homepage from showing for 5-7 seconds
    # while Shiny initializes. The server observer still runs later to set filter
    # inputs and trigger autorun.
    tags$script(HTML("
      (function() {
        var tabMap = {
          'enrollment':         'Enrollment',
          'low-enrollment':     'Enrollment',
          'headcount':          'Headcount',
          'waitlists':          'Waitlists',
          'open-seats':         'Open Seats',
          'cancellations':      'Cancellations',
          'course-dynamics':    'Course Dynamics',
          'gen-ed':             'Gen Ed',
          'department-profile': 'Dept Trends',
          'dept-trends':        'Dept Trends',
          'registration':       'Regstats'
        };
        var params = new URLSearchParams(window.location.search);
        var tabSlug = (params.get('tab') || '').toLowerCase();
        var tabName = tabMap[tabSlug] || tabSlug;
        if (!tabName) return;
        document.addEventListener('DOMContentLoaded', function() {
          // Top-level panels use .nav-link; panels inside nav_menu() use .dropdown-item.
          // Scope to .navbar so we never accidentally match tab-content panel wrappers.
          var link = document.querySelector('.navbar [data-value=\"' + tabName + '\"]');
          if (link) link.click();

          // Show loading overlay immediately for autorun URLs so users don't
          // watch a blank screen for 4+ seconds while Shiny initializes.
          if (params.get('autorun') === 'true') {
            var overlayMap = {
              'open-seats':   'seatfinder-loading-overlay',
              'cancellations': 'cancellations-loading-overlay',
              'registration': 'regstats-loading-overlay',
              'enrollment':   'enrl-loading-overlay'
            };
            var oid = overlayMap[tabSlug];
            if (oid) {
              var el = document.getElementById(oid);
              if (el) { el.style.opacity = '1'; el.style.display = 'flex'; }
            }
          }
        });
      })();
    ")),

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

        // Programmatically click an action button by ID
        Shiny.addCustomMessageHandler('click_button', function(id) {
          var btn = document.getElementById(id);
          if (btn) btn.click();
        });

        // Force a value into a server-side selectize input (which won't display selected
        // values it hasn't loaded yet). Adds the option and selects it via the selectize API.
        Shiny.addCustomMessageHandler('selectize_set_value', function(msg) {
          if (!msg || msg.value == null || msg.value === '') return;
          var el = document.getElementById(msg.id);
          if (el && el.selectize) {
            el.selectize.addOption({value: msg.value, text: msg.value});
            el.selectize.setValue(msg.value, false);
          }
        });

        // Generic copy-URL handler: msg = { queryStr, buttonId }
        // Used by enrollment, regstats, seatfinder, and any future tab.
        Shiny.addCustomMessageHandler('copy_cedar_url', function(msg) {
          var url = window.location.origin + window.location.pathname + '?' + msg.queryStr;
          var btn = msg.buttonId ? document.getElementById(msg.buttonId) : null;
          function flash() {
            if (!btn) return;
            var icon = btn.querySelector('i');
            var savedClass = icon ? icon.className : '';
            btn.classList.add('btn-success');
            btn.classList.remove('btn-outline-secondary');
            if (icon) icon.className = 'fa fa-check';
            setTimeout(function() {
              btn.classList.remove('btn-success');
              btn.classList.add('btn-outline-secondary');
              if (icon) icon.className = savedClass;
            }, 1500);
          }
          if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(url).then(flash);
          } else {
            var el = document.createElement('textarea');
            el.value = url;
            el.style.cssText = 'position:fixed;opacity:0';
            document.body.appendChild(el);
            el.select();
            try { document.execCommand('copy'); flash(); } catch(e) {}
            document.body.removeChild(el);
          }
        });

        // After any tab activation (manual or programmatic), close open navbar dropdowns.
        // Runs on shown.bs.tab so it fires after Bootstrap finishes its own activation sequence.
        document.addEventListener('shown.bs.tab', function() {
          $('.navbar-nav .dropdown').removeClass('show');
          $('.navbar-nav .dropdown-toggle').removeClass('show').attr('aria-expanded', 'false');
          $('.navbar-nav .dropdown-menu').removeClass('show');
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

  div(class = "filters-compact",
    h1("Dept Dashboard"),
    tags$p("Headcount trends, enrollment patterns, and course activity for the current term.",
           class = "filter-subtitle"),
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
    } # end campus default block
  ), # end filters-compact

  div(style = "position: relative; min-height: 500px;",

  # Loading overlay — shown while dashboard data is computing
  div(
    id = "dashboard-loading-overlay",
    style = "display: none;",
    div(class = "dash-loader-backdrop"),
    div(class = "dash-loader-box",
      div(class = "dash-loader-icon",
        div(class = "dash-spinner"),
        tags$span("\U0001f332", class = "dash-tree-icon")
      ),
      div(id = "dashboard-loading-label", class = "dash-loader-msg", "Loading…"),
      div(id = "dashboard-timing-msg",    class = "dash-timing-msg")
    )
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
        if (e.value && e.value !== "") showOverlay();
        else                            hideOverlay();
      });

      Shiny.addCustomMessageHandler("dashboard_load_complete", function(msg) {
        completeOverlay(msg.duration_sec, msg.avg_sec);
      });

      function showOverlay() {
        clearTimeout(hideTimer);
        var el     = document.getElementById("dashboard-loading-overlay");
        var label  = document.getElementById("dashboard-loading-label");
        var timing = document.getElementById("dashboard-timing-msg");
        if (!el) return;
        label.textContent  = "Loading\u2026 (est. " + Math.round(expectedSec) + "s)";
        timing.textContent = "";
        el.style.opacity    = "0";
        el.style.display    = "flex";
        el.style.transition = "opacity 0.2s ease";
        el.offsetWidth; // force reflow
        el.style.opacity = "1";
      }

      function completeOverlay(durationSec, avgSec) {
        var el     = document.getElementById("dashboard-loading-overlay");
        var timing = document.getElementById("dashboard-timing-msg");
        if (!el || el.style.display === "none") return;
        var txt = "Loaded in " + durationSec + "s";
        if (avgSec !== null && avgSec !== undefined) txt += " \u00b7 avg " + avgSec + "s";
        timing.textContent = txt;
        hideTimer = setTimeout(function() {
          el.style.transition = "opacity 0.4s ease";
          el.style.opacity    = "0";
          setTimeout(function() {
            el.style.display    = "none";
            el.style.transition = "";
            el.style.opacity    = "1";
          }, 400);
        }, 800);
      }

      function hideOverlay() {
        clearTimeout(hideTimer);
        var el = document.getElementById("dashboard-loading-overlay");
        if (!el) return;
        el.style.transition = "";
        el.style.opacity    = "1";
        el.style.display    = "none";
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

    # Program transparency info box — shows which program/subject codes are matched
    uiOutput("dashboard_program_info"),

    # Headcount: stat cards + sparkline
    h4("Students", style = "margin-top: 8px; margin-bottom: 12px; color: #333;"),
    uiOutput("dashboard_headcount_cards"),
    plotOutput("dashboard_headcount_sparkline", height = "200px"),

    hr(style = "margin: 24px 0;"),

    # Current-term enrollment vs historical average
    fluidRow(
      column(6,
        h4("\u2191 Above Average This Term", style = "color: #2e7d32; margin-bottom: 8px;"),
        p("Courses running higher than their historical average enrollment for the same term type
          (fall vs. fall, spring vs. spring). Requires at least 2 prior same-season offerings.
          Each row shows current enrollment, then the difference vs. the historical average —
          e.g., \"+8 (+22%) vs avg 36\" means 44 enrolled this term, average was 36.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_above_avg_courses")
      ),
      column(6,
        h4("\u2193 Below Average This Term", style = "color: #c62828; margin-bottom: 8px;"),
        p("Courses running lower than their historical average for the same term type.
          The historical average is the mean enrollment across all prior offerings in the same
          season (e.g., all prior falls). Only courses with at least 2 prior same-season
          terms appear. Example: \"\u22125 (\u221212%) vs avg 41\" means 36 enrolled this term,
          average was 41.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_below_avg_courses")
      )
    ),

    hr(style = "margin: 24px 0;"),

    # New this term and missing vs. last year
    fluidRow(
      column(6,
        h4("\u2728 New This Term", style = "color: #1565c0; margin-bottom: 8px;"),
        p("Courses whose course number has never appeared in the historical data — genuinely
          new to the schedule (or returning after a long absence). For topics courses (T: prefix),
          each distinct title counts as a new course even if the course number is familiar.
          Topics rows also show a \"slot avg\" — average enrollment across all prior T: offerings
          under that same course number, so you can see what demand for that slot typically looks like.
          A high volume of new or infrequently offered courses can complicate advising and multi-year
          degree planning — students and advisors benefit most from a predictable course rotation.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_new_courses")
      ),
      column(6,
        h4("\u23f8 Missing vs. Two Years Ago", style = "color: #888; margin-bottom: 8px;"),
        p("Courses that ran in this same term type two years ago but are not scheduled this term.
          Each row shows the course and its recent enrollment history (last 1\u20133 prior offerings
          with enrollment counts), so you can judge whether this is a routine gap or a course
          that quietly stopped running. Courses that disappear without a clear curricular rationale
          can strand students mid-degree — especially those relying on a specific sequence for
          graduation requirements or certification. Worth a quick check before the schedule is final.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        uiOutput("dashboard_dormant_courses")
      )
    ),

    hr(style = "margin: 24px 0;"),

    # Repeated topics slots
    h4("Recurring Topics This Term", style = "margin-bottom: 8px;"),
    p("Topics courses (T: prefix) running this term that have been offered at least twice before
      under the same course number. Shows current enrollment alongside a recent history of prior
      offerings so you can see whether this topic draws consistently or is gaining/losing interest.
      Useful for evaluating which rotating topics might warrant their own permanent course number.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 12px;"),
    uiOutput("dashboard_repeated_topics"),

    hr(style = "margin: 24px 0;"),

    # Drop rate stats for current term — stacked early/late, each with below|above columns
    h4("Drop Rates This Term", style = "margin-bottom: 8px;"),
    info_panel("How drop rates work",
      tags$ul(
        tags$li(tags$strong("drop rate"), " = drops \u00f7 class list total (not just enrolled students), expressed as a percentage."),
        tags$li(tags$strong("Early drops"), " (pre-census DR) \u2014 withdrawals before the census date; no academic consequence. High early rates often signal scheduling conflicts, unclear descriptions, or prerequisite mismatches."),
        tags$li(tags$strong("Late drops"), " (DW/DG) \u2014 drops after the census date; appear on transcript and may affect financial aid. A stronger signal of course difficulty or support gaps."),
        tags$li(tags$strong("Diff"), " \u2014 how much this term\u2019s rate differs from that course\u2019s own historical average for the same term type. +4.2 means 4.2 percentage points above that course\u2019s norm."),
        tags$li("Only courses with \u226510 students and \u22653 total drops appear. Compared against at least 2 prior same-season terms.")
      ),
      tags$a("Full methodology \u2192", href = "https://cedarplatform.org/users/dept-dashboard",
             target = "_blank")
    ),
    h5("Early Drops (pre-census DR)", style = "color: #555; margin-bottom: 6px;"),
    uiOutput("dashboard_early_drops"),
    hr(style = "margin: 16px 0;"),
    h5("Late Drops (DW/DG)", style = "color: #555; margin-bottom: 6px;"),
    uiOutput("dashboard_late_drops"),

    hr(style = "margin: 24px 0;"),

    # Visual row: donut + credit hour trendlines
    fluidRow(
      column(6,
        h4("Where Your Majors Also Study", style = "margin-bottom: 8px;"),
        p("Minors declared by currently enrolled students whose home major is in this department.
          Reflects the current term's declared programs. Understanding where your majors study
          across disciplines can reveal opportunities for course cross-listing, interdisciplinary
          partnerships, or coordinated advising agreements with high-overlap departments.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        plotlyOutput("dashboard_cross_dept_minors", height = "320px")
      ),
      column(6,
        h4("Who Minors Here", style = "margin-bottom: 8px;"),
        p("Home majors of students who have declared a minor in this department.
          Surfaces which programs send students here as a secondary interest — useful for
          identifying curricular partners and advising outreach targets.",
          style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
        plotlyOutput("dashboard_majors_with_minor", height = "320px")
      )
    ),

    fluidRow(
      column(12,
        h4("Credit Hour Production by Course Level", style = "margin-bottom: 8px;"),
        p("Student credit hours (SCH) generated by this department's sections, broken out by
          course level (lower division, upper division, graduate), over the past five years.
          SCH = enrolled students \u00d7 credit hours per course. Only passing grades are counted.
          Sustained decline in a level may indicate shrinking demand, shifting prerequisites,
          or changes in course offerings — all worth investigating before making staffing decisions.",
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
  ) # end position:relative wrapper
), # end Explore Your Unit nav_panel

############################
# DEPARTMENT TRENDS PANEL
############################

nav_panel(
  title = "Dept Trends",
  icon = icon("chart-line"),

  div(class = "filters-compact",
    h1("Dept Trends"),
    tags$p("Longitudinal department patterns in students, enrollment, degrees, credit hours, Gen Ed, and course outcomes.",
           class = "filter-subtitle"),
    fluidRow(
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
      column(4,
        selectizeInput(
          inputId = "dept_report_dept",
          label = "Department",
          multiple = FALSE,
          choices = c("Select a department..." = "", .dept_choices),
          selected = ""
        )
      ),
      column(3,
        uiOutput("dept_report_actions", inline = TRUE)
      )
    )
  ), # end filters-compact

  fluidRow(
    column(12,
      uiOutput("dept_report")
    )
  )
), # end department trends nav_panel

######################
# ENROLLMENT NAV PANEL
########################

nav_panel(
  title = "Enrollment",
  icon = icon("chart-bar"),

    div(class = "filters-compact",
      h1("Enrollment"),
      tags$p("Section-level enrollment from the Department Enrollment Status Report, with crosslist deduplication and historical comparison.",
             class = "filter-subtitle"),
    fluidRow(
      column(2,
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
             selectizeInput(
               inputId = "enrl_subj",
               label = "Subject",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$subject))),
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
        numericInput("enrl_max", "Max", value = NA, min = 0, step = 1)
      ),
      column(1,
        tags$div(
          tags$label("Exclude List", class = "control-label"),
          checkboxInput(inputId = "enrl_uel", label = "Use", value = TRUE)
        )
      ),
      column(2,
        div(style = "display: flex; align-items: flex-end; gap: 10px; height: 100%; padding-bottom: 2px;",
          actionButton("enrl_button",
                       label = "Gather Enrollments",
                       class = "btn-success",
                       icon = icon("sync-alt")),
          uiOutput("enrl_download_button_ui"),
          actionButton("enrl_copy_url",
                       label = NULL,
                       icon = icon("link"),
                       title = "Copy shareable link for current view",
                       class = "btn-outline-secondary btn-sm",
                       style = "padding: 2px 8px;")
        )
      )
    ), # end fluidRow

    ), # end filters-compact div

    div(class = "rs-filter-stripe", uiOutput("enrl_filter_summary")),

    div(style = "position: relative; min-height: 300px;",

      div(
        id = "enrl-loading-overlay",
        style = "display: none;",
        div(class = "dash-loader-backdrop"),
        div(class = "dash-loader-box",
          div(class = "dash-loader-icon",
            div(class = "dash-spinner"),
            tags$span("\U0001f393", class = "dash-tree-icon")
          ),
          div(id = "enrl-loading-label", class = "dash-loader-msg", "Loading…"),
          div(id = "enrl-timing-msg",    class = "dash-timing-msg")
        )
      ),

      tags$script(HTML(paste0('
      (function() {
        var expectedSec = ', {
          avg <- get_average_report_time("enrollment")
          if (!is.null(avg)) round(avg) else 10L
        }, ';
        var hideTimer = null;

        $(document).on("shiny:inputchanged", function(e) {
          if (e.name !== "enrl_button") return;
          showOverlay();
        });

        Shiny.addCustomMessageHandler("enrl_load_complete", function(msg) {
          completeOverlay(msg.duration_sec, msg.avg_sec);
        });

        function showOverlay() {
          clearTimeout(hideTimer);
          var el    = document.getElementById("enrl-loading-overlay");
          var label = document.getElementById("enrl-loading-label");
          var timing = document.getElementById("enrl-timing-msg");
          if (!el) return;
          label.textContent  = "Loading… (est. " + Math.round(expectedSec) + "s)";
          timing.textContent = "";
          el.style.opacity    = "0";
          el.style.display    = "flex";
          el.style.transition = "opacity 0.2s ease";
          el.offsetWidth;
          el.style.opacity = "1";
        }

        function completeOverlay(durationSec, avgSec) {
          var el     = document.getElementById("enrl-loading-overlay");
          var timing = document.getElementById("enrl-timing-msg");
          if (!el || el.style.display === "none") return;
          var txt = "Loaded in " + durationSec + "s";
          if (avgSec !== null && avgSec !== undefined) txt += " · avg " + avgSec + "s";
          timing.textContent = txt;
          hideTimer = setTimeout(function() {
            el.style.transition = "opacity 0.4s ease";
            el.style.opacity    = "0";
            setTimeout(function() {
              el.style.display    = "none";
              el.style.transition = "";
              el.style.opacity    = "1";
            }, 400);
          }, 800);
        }
      })();
      '))),

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
            info_panel("Column guide — Home",
              tags$p("Your department's home/primary sections, plus all non-crosslisted courses. Each crosslisted course appears once, under its administrative home department."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this section."),
                tags$li(tags$strong("TotalEnrl"), " — for crosslisted sections, combined enrollment across all partner sections; equals SectionEnrl for non-crosslisted courses. Use this column for enrollment counts — it avoids double-counting."),
                tags$li(tags$strong("Partners"), " — other course codes sharing this section's enrollment pool (e.g., ANTH 350 paired with HIST 350).")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Split-level", value = "split",
            info_panel("Column guide — Split-level",
              tags$p("Sections crosslisted across the undergraduate/graduate divide — at least one section at or below 499 paired with one at 500 or above. Each group appears once (home section shown)."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across both the undergraduate and graduate sections in the split group."),
                tags$li(tags$strong("Partners"), " — the paired course code at the other level (e.g., HIST 402 shows HIST 502 here).")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Crosslisted", value = "xl-home",
            info_panel("Column guide — Crosslisted",
              tags$p("Your department's sections that also appear under another department's course number — your course is home, theirs is the partner."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in your department's section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across your section and all crosslist partner sections."),
                tags$li(tags$strong("Partners"), " — the other department's course code(s) this section is crosslisted with.")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Away", value = "away",
            info_panel("Column guide — Away",
              tags$p("Sections owned by another department but crosslisted under your department's course number. Your number is the partner; the other department is home."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in the away (home-department) section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across all sections in the crosslist group."),
                tags$li(tags$strong("Partners"), " — the home department's course code that owns this section.")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "All", value = "all",
            info_panel("Column guide — All",
              tags$p("Every section including all crosslist partner rows. Crosslisted courses appear multiple times — once per subject code. Enrollment is not de-duplicated here."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this specific section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across all sections sharing this crosslist group."),
                tags$li(tags$strong("Partners"), " — all other course codes in the same crosslist group.")
              ),
              tags$p(style = "color: #8a6a3a; margin-top: 6px; font-size: 0.9em;",
                icon("triangle-exclamation"), " Summing TotalEnrl across rows in this view will double-count crosslisted courses. Use the Home view for accurate totals."),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          )
        ),
        reactable::reactableOutput("enrl_summary")
      ),

      # Class list enrollment
      nav_panel(
        title = "Classlist",
        icon = icon("list"),
        reactable::reactableOutput("enrl_cl_summary")
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

        # Threshold controls and calculate button
        div(style = "display: flex; align-items: flex-end; gap: 20px; padding: 4px 0 8px 0;",
          span("Thresholds:", style = "font-weight: 600; color: #555; padding-bottom: 6px; white-space: nowrap;"),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_lower", "Lower div", value = 12, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_upper", "Upper div", value = 12, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_split", "Split-level", value = 10, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_grad", "Graduate", value = 5, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_min_enrl", "Min enrolled", value = 0, min = 0, max = 1000, step = 1)
          ),
          div(style = "padding-bottom: 6px;",
            uiOutput("low_enrl_download_ui"))
        ),

        info_panel("How to read this table",
          tags$p(tags$strong("Current / past terms (alerts mode):"), style = "margin-bottom: 4px;"),
          tags$ul(
            tags$li(tags$strong("Sects"), " — number of active home sections of this course in the selected term."),
            tags$li(tags$strong("Enrolled"), " — this section's own registered student count."),
            tags$li(tags$strong("XL Total"), " — for crosslisted sections, the combined count across all partner sections; equals Enrolled for non-crosslisted courses."),
            tags$li(tags$strong("Course Total"), " — sum of XL Total across all home sections of this course. Color-coded against the threshold.")
          ),
          tags$p(tags$strong("Future terms (concerns mode):"), style = "margin-bottom: 4px; margin-top: 8px;"),
          tags$ul(
            tags$li(tags$strong("Sects"), " — number of scheduled home sections."),
            tags$li(tags$strong("Sect Enrl"), " — current registration count for those sections."),
            tags$li(tags$strong("Hist Avg"), " — average combined enrollment over the last 4 same-type terms. Color-coded against the threshold."),
            tags$li(tags$strong("Trend"), " — ↑ up / ↓ down / ↔ stable based on linear regression slope across prior terms."),
            tags$li(tags$strong("# Terms"), " — how many prior terms contributed to the average.")
          ),
          tags$p(tags$strong("Color bands:"), " red = below 50% of threshold; yellow = 50–75%; blue = 75–100%; green = meets or exceeds threshold.", style = "margin-top: 8px;"),
          tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab",
                 target = "_blank")
        ),

        navset_tab(
          id = "low_enrl_tabs",
          nav_panel(
            title = "Lower",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_lower")
          ),
          nav_panel(
            title = "Upper",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_upper")
          ),
          nav_panel(
            title = "Split",
            icon = icon("exclamation-triangle"),
            br(),
            p("Crosslisted courses that span the undergraduate/graduate boundary (at least one section \u2264499 and one \u2265500). The Sections column shows all partner courses in the group. Enrollment is the combined total.",
              style = "color: #666; font-size: 0.9em; margin-bottom: 0.75rem;"),
            reactable::reactableOutput("low_enrl_table_split")
          ),
          nav_panel(
            title = "Graduate",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_grad")
          )
        ) # end low_enrl navset_tab
      ),

      # Multi-year enrollment trends (growing / declining) — single dept only
      # Enrollment trends \u2014 level overview + top growing/declining course charts
      nav_panel(
        title = "Trends",
        icon = icon("chart-line"),

        h5("Enrollment by Level", style = "margin: 12px 0 4px 0; font-weight: 600; color: #333;"),
        p("Total enrollment broken out by course level across your selected filters and terms.",
          style = "color: #666; font-size: 0.88em; margin-bottom: 8px;"),
        plotlyOutput("enrl_level_plot", height = "280px"),

        hr(style = "margin: 20px 0 12px 0;"),

        p("Select a single department to see which courses are growing or declining. Based on
          linear regression across each course\u2019s last 6 offerings; courses with fewer than
          2 offerings are excluded. Trends mix term types (fall, spring, summer) unless you
          filter by term first.",
          style = "color: #666; font-size: 0.88em; margin-bottom: 12px;"),
        fluidRow(
          column(6,
            h5("\u2191 Top Growing Courses", style = "color: #2e7d32; margin-bottom: 4px;"),
            plotlyOutput("enrl_trends_growth_plot", height = "280px")
          ),
          column(6,
            h5("\u2193 Top Declining Courses", style = "color: #c62828; margin-bottom: 4px;"),
            plotlyOutput("enrl_trends_decline_plot", height = "280px")
          )
        )
      ),


    ) # end navset_tab

    ) # end position:relative wrapper

), # end nav_panel for enrollment



  # Headcount nav_panel removed from top level — now lives in Explore menu



  ######################
  # REGSTATS NAV PANEL
  ########################
  nav_panel(
    title = "Regstats",
    icon = icon("tachometer-alt"),
    regstatsUI("regstats", cedar_sections, cedar_regstats_thresholds, .dept_choices, cedar_current_term)
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
      seatfinderUI("seatfinder", cedar_sections, cedar_next_term, .dept_choices)
    ), # end open seats nav_panel

    nav_panel(
      title = "Cancellations",
      icon = icon("ban"),
      cancellationsUI("cancellations", cedar_sections, cedar_next_term, .dept_choices)
    ), # end cancellations nav_panel
    
    nav_panel(
      title = "Waitlists",
      icon = icon("list-ol"),
      waitlistUI("waitlist", cedar_sections, cedar_next_term, .dept_choices)
    ), # end waitlists nav_panel

    nav_panel(
      title = "Gen Ed",
      icon = icon("layer-group"),
      genEdExploreUI("gen_ed", cedar_sections, .dept_choices, cedar_current_term)
    ), # end gen ed nav_panel

    #####################
    # HEADCOUNT (inside Explore)
    #####################
    nav_panel(
      title = "Headcount",
      icon = icon("users"),
      headcountUI("headcount")
    ), # end headcount nav_panel

    #####################
    # COURSE DYNAMICS (inside Explore)
    #####################
    nav_panel(
      title = "Course Dynamics",
      icon = icon("file-lines"),

      div(class = "filters-compact",
        h1("Course Dynamics"),
        tags$p("Enrollment trends, student flows, grade distributions, and outcomes for a single course.",
               class = "filter-subtitle"),
        fluidRow(
          column(4,
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
          column(4,
            selectizeInput(
              inputId = "cr_campus",
              label = "Campus",
              multiple = TRUE,
              choices  = sort(unique(cedar_sections$campus)),
              selected = c("ABQ", "EA")
            )
          ),
          column(3,
            actionButton(
              "cr_generate_button",
              "Analyze Course",
              icon = icon("chart-line"),
              class = "btn-primary",
              style = "margin-top: 25px;"
            )
          )
        )
      ), # end filters-compact

      conditionalPanel(
        condition = "input.cr_course === null || input.cr_course === ''",
        div(class = "empty-state",
          tags$p("Select a course to load its data."))
      ),

      conditionalPanel(
        condition = "input.cr_course !== null && input.cr_course !== ''",
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
          uiOutput("cr_flow_scope_note"),
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
          "DFW",
          icon = icon("chart-bar"),
          uiOutput("cr_dfw_tab_content")
        ),

        nav_panel(
          "Retention",
          icon = icon("person-walking-arrow-right"),
          uiOutput("cr_impact_retention_ui")
        ),

        nav_panel(
          "Sequence Effect",
          icon = icon("arrow-right-long"),
          uiOutput("cr_impact_sequence_ui")
        ),

        nav_panel(
          "Downstream Success",
          icon = icon("chalkboard-teacher"),
          uiOutput("cr_impact_instructor_ui")
        )

      ) # end navset_tab
    ) # end conditionalPanel
  ), # end course dynamics nav_panel

    # RETENTION (inside Explore) — hidden until cross-course comparison
    # is ready. Course-level retention trend lives in Course Dynamics tab.
    # nav_panel(
    #   title = "Retention",
    #   icon  = icon("user-check"),
    #   retentionUI("retention")
    # ), # end retention nav_panel

  ), # end Explore nav_menu

  # Admin dropdown menu
  nav_menu(
    title = "Admin",
    icon = icon("cog"),

  nav_panel(
    title = "Healthcare",
    icon  = icon("hospital"),
    healthWhatIfUI("health_whatif")
  ),

  nav_item(tags$hr(style = "margin: 4px 0;")),

  nav_panel(
    title = "Data & Usage",
    icon  = icon("database"),

    div(class = "filters-compact",
      h1("Data Status & Usage Analytics")
    ),

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

      # ── Tab 2: Mapping Transparency ───────────────────────────────────
      nav_panel(
        title = "Mappings",
        br(),
        div(
          p("Department, subject, and program mappings used by Cedar at startup. Mapping issues are surfaced here so unusual Banner codes can be reviewed without blocking the app.",
            style = "color: #666; font-size: 0.9em; margin-bottom: 10px;"),
          uiOutput("mapping_issues_summary"),
          card(
            card_header("Mapping Issues"),
            p("Rows listed here are excluded from lookup vectors until they are mapped or explicitly reviewed. They may still appear in source data.",
              style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
            div(DT::dataTableOutput("mapping_issues_table"), class = "dt-container")
          ),
          navset_tab(
            nav_panel(
              title = "Program to Dept",
              br(),
              p("Validated major/program code to department-code lookup used for home-major classification and transform fallbacks.",
                style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
              div(DT::dataTableOutput("program_dept_mapping_table"), class = "dt-container")
            ),
            nav_panel(
              title = "Subject to Dept",
              br(),
              p("Course subject prefixes mapped to Cedar department codes. Use this when interpreting course ownership.",
                style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
              div(DT::dataTableOutput("subject_dept_mapping_table"), class = "dt-container")
            ),
            nav_panel(
              title = "Dept Names",
              br(),
              p("Department code display names derived from the subject/dept catalog.",
                style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
              div(DT::dataTableOutput("dept_name_mapping_table"), class = "dt-container")
            ),
            nav_panel(
              title = "Reviewed Exceptions",
              br(),
              p("Program codes intentionally allowed to remain unmapped at app startup. These should be treated as a review queue, not permanent truth.",
                style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
              div(DT::dataTableOutput("allowed_unmapped_mapping_table"), class = "dt-container")
            )
          )
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
          card_header("Department Trends"),
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

      # ── Tab 4: Cache Management (lazy loaded) ──────────────────────
      nav_panel(
        title = "Cache",
        br(),
        cacheUI("cache")
      )
    ) # end navset_tab
  ), # end data & usage nav_panel
  
nav_panel(
    title = "Changelog",
    icon = icon("history"),
    div(class = "filters-compact",
      h1("CEDAR Changelog")
    ),
    changelogUI("changelog")
  )
), # end Admin nav_menu

nav_spacer(),
nav_item(
  actionLink(
    "nav_changelog_link",
    label = tagList(icon("history"), "See what's new"),
    class = "nav-changelog-link"
  )
)

) # end ui
