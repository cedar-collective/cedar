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
          'course-dynamics':    'Course Dynamics',
          'department-profile': 'Department Profile'
        };
        var params = new URLSearchParams(window.location.search);
        var tabSlug = (params.get('tab') || '').toLowerCase();
        var tabName = tabMap[tabSlug] || tabSlug;
        if (!tabName) return;
        document.addEventListener('DOMContentLoaded', function() {
          var link = document.querySelector('.nav-link[data-value=\"' + tabName + '\"]');
          if (link) link.click();
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

        // Copy a query-string URL to the clipboard; briefly flash the trigger button green.
        Shiny.addCustomMessageHandler('copy_enrl_url', function(queryStr) {
          var url = window.location.origin + window.location.pathname + '?' + queryStr;
          var btn = document.getElementById('enrl_copy_url');
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
    p("Drop rate = drops \u00f7 class list total, expressed as a percentage. Compared against
      each course\u2019s own historical average for the same term type (fall vs. fall, etc.),
      using at least 2 prior same-season terms. Only courses with \u226510 students on the
      class list and \u22653 total drops appear. Courses are grouped by level (lower/upper/grad);
      the level average shown in the section header is the historical mean rate across all
      courses in that division.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 4px;"),
    p(strong("Early drops"), " (pre-census DR) = students who withdrew before the census date.
      These are often course-fit adjustments and cost the student nothing academically.
      High early drop rates can signal scheduling problems, unclear course descriptions, or
      prerequisite mismatches. ",
      strong("Late drops"), " (DW/DG) = drops after the census date. These appear on the
      transcript and may affect financial aid. Elevated late drop rates are a stronger signal
      of course difficulty, pacing, or support gaps. The \u201cDiff\u201d column shows how much
      this term\u2019s rate differs from the course\u2019s own historical average \u2014
      e.g., \u201c+4.2\u201d means the rate is 4.2 percentage points above normal.",
      style = "color: #888; font-size: 0.88em; margin-bottom: 12px;"),
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
      column(2,
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

    uiOutput("enrl_filter_summary"),

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
          actionButton("low_enrl_button", "Calculate",
                       icon = icon("exclamation-triangle"),
                       class = "btn-primary"),
          div(style = "padding-bottom: 6px;",
            uiOutput("low_enrl_download_ui"))
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
        p("Multi-year enrollment trends across the last 6 offerings of each course. Select a
          single department to see results. A course is classified as \u201cgrowing\u201d or
          \u201cdeclining\u201d when a linear regression slope across its recent offerings
          exceeds \u00b11 student per term. Courses with fewer than 2 offerings are excluded.",
          style = "color: #666; font-size: 0.88em; margin-bottom: 4px;"),
        p("Each row shows: average enrollment across the window, then early-window average
          vs. recent-window average (first half vs. second half of the 6-term window).
          For example: \"avg 34 enrolled \u2022 +9 (+36%) over window\" means the course averaged
          34 students across 6 terms, and the recent 3-term average is 9 students higher than
          the early 3-term average \u2014 a 36% gain. Note that these trends mix term types
          (fall, spring, summer) unless you filter first.",
          style = "color: #666; font-size: 0.88em; margin-bottom: 16px;"),
        fluidRow(
          column(6,
            h4("\u2191 Growing Courses", style = "color: #2e7d32; margin-bottom: 8px;"),
            p("Courses with a positive regression slope > 1 student/term across their last
              6 offerings. Sorted by slope (steepest growth first).",
              style = "color: #888; font-size: 0.88em; margin-bottom: 8px;"),
            uiOutput("enrl_trends_growing")
          ),
          column(6,
            h4("\u2193 Worth a Look", style = "color: #c62828; margin-bottom: 8px;"),
            p("Courses with a negative slope < \u22121 student/term. May reflect scheduling changes,
              curriculum shifts, prerequisite changes, or reduced demand. Sorted by steepest
              decline first.",
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
                 choices  = sort(unique(cedar_sections$campus)),
                 selected = c("ABQ", "EA")),
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
                 choices = sort(unique(cedar_sections$level)),
                 selected = "lower"),
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
                 label = "Min SDs",
                 value = cedar_regstats_thresholds[["pct_sd"]])
        ),
        column(2,
               numericInput(
                 inputId = "rs_chronic_fill_rate",
                 label = "Chronic Fill Rate",
                 value = cedar_regstats_thresholds[["chronic_fill_rate"]],
                 min = 0, max = 1, step = 0.05)
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
      seatfinderUI("seatfinder", cedar_sections, cedar_next_term, .dept_choices)
    ), # end open seats nav_panel
    
    nav_panel(
      title = "Waitlists",
      icon = icon("list-ol"),
      waitlistUI("waitlist", cedar_sections, cedar_next_term)
    ), # end waitlists nav_panel

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

      h1("Course Dynamics", style = "margin-bottom: 20px;"),
      p("Enrollment patterns, student flows, and grade distributions for a specific course."),

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
          "Instructor Prep",
          icon = icon("chalkboard-teacher"),
          uiOutput("cr_impact_instructor_ui")
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

    ), # end department profile nav_panel

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
    h1("CEDAR Changelog", style = "margin-bottom: 20px;"),
    changelogUI("changelog")
  )
) # end Admin nav_menu

) # end ui

