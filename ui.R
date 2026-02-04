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

# Define UI for application
ui <- page_navbar(
  id = "main_navbar",  # Add ID to enable tab switching

  tags$head(
    tags$style(HTML("
      body, .container-fluid {
        font-size: 0.9em !important;

      #enrl_summary table.dataTable {
        font-size: 0.9em;
      }
    ")),
    
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



######################
# ENROLLMENT NAV PANEL
########################

nav_panel(
  title = "Enrollment",
  icon = icon("chart-bar"),

  # Page title
  h1("Enrollment Analysis & Trends", 
     style = "margin-bottom: 10px;",
     tags$a(
       href = "#",
       onclick = "Shiny.setInputValue('show_enrl_help', Math.random());",
       icon("circle-info"),
       style = "font-size: 0.6em; margin-left: 10px; color: #0066cc; text-decoration: none;",
       title = "Show detailed instructions"
     )
  ),
  
  # Simple instruction line
  p(
    "Enrollment tables always display, but for plots of enrollments over time, select 'TERM' and at least one other variable in the 'Group by' field.",
    style = "color: #666; font-size: 0.95em; margin-bottom: 20px; font-style: italic;"
  ),

    fluidRow(
      column(1,
             selectizeInput(
               inputId = "enrl_campus",
               label = "Campus", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$campus))),
      ),
      column(1,
             selectizeInput(
               inputId = "enrl_college",
               label = "College", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$college))),
      ),
      column(1,
             selectizeInput(
               inputId = "enrl_dept",
               label = "Department", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$department))),
      ),
      column(2,
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
      column(2,
             selectInput(
               inputId = "enrl_facet_field",
               label = "Facet by",
               choices = c(
                 "None" = "",
                 "term_type" = "term_type",
                 "Campus" = "CAMP",
                 "DEPT" = "DEPT",
                 "SUBJ_CRSE" = "SUBJ_CRSE",
                 "level" = "level",
                 "IM" = "INST_METHOD"
               ),
               selected = "",
               multiple = FALSE
             )
      ),

    ), # end fluidRow 
    fluidRow(
      column(2,
             selectizeInput(
               inputId = "enrl_inst",
               label = "Instructor", 
               multiple = TRUE,
               choices = NULL,
               options = list(placeholder = "Type to search instructors...")),
      ),
      column(1,
             selectInput(
               inputId = "enrl_im",
               label = "Method",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$delivery_method))),
      ),
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
      column(1,
             selectInput(
               inputId = "enrl_gen_ed",
               label = "Gen Ed", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$gen_ed_area))),
      ),
      column(1,
         numericInput(
           inputId = "enrl_min",
           label = "Min Enrl",
           value = 1,
           min = 0,
           step = 1
         )
      ),
      column(1,
         numericInput(
           inputId = "enrl_max",
           label = "Max Enrl",
           value = max(cedar_sections$total_enrl, na.rm = TRUE),
           min = 0,
           step = 1
         )
      ),
      column(1,
             checkboxInput(
               inputId = "enrl_uel",
               label = "Use Exclude List",
               value = TRUE
             )
      ),
      column(2,
             actionButton("enrl_button",
                         label = "Refresh table", 
                         icon = icon("sync-alt"))
      ),
      column(2,
             uiOutput("enrl_download_button_ui")
      )
    ), # end fluidRow

    # Tabbed output area (shares the filter controls above)
    navset_tab(
      id = "enrl_output_tabs",
      
      # Enrollment Trends Tab
      nav_panel(
        title = "Enrollment Trends",
        icon = icon("chart-line"),
        br(),
        # Conditional enrollment cards (rendered by server based on data availability)
        uiOutput("enrl_plot_card"),
        uiOutput("enrl_summary_card")
      ),
      
      # Low Enrollment Alert Tab
      nav_panel(
        title = "Low Enrollment Alert",
        icon = icon("exclamation-triangle"),
        
        # Instructional message at top
        p(
          "The Enrolled column reports total enrollment across all crosslisted sections.",
          style = "color: #666; font-size: 0.95em; margin-bottom: 15px; font-style: italic;"
        ),
        
        # Warning box at top (conditional - only shows before first generation)
        uiOutput("low_enrl_warning"),
        
        # Controls row
        fluidRow(
          column(3,
            numericInput(
              inputId = "low_enrl_threshold",
              label = "Enrollment Threshold",
              value = 15,
              min = 1,
              max = 50,
              step = 1
            )
          ),
          column(3,
            actionButton("low_enrl_button", 
                        label = "Generate Alert Dashboard", 
                        icon = icon("exclamation-triangle"),
                        class = "btn-warning",
                        style = "margin-top: 25px;")
          )
        ),
        
        br(),
        
        # Summary stats
        uiOutput("low_enrl_summary"),
        
        br(),
        
        # Main data table
        DTOutput("low_enrl_table")
      )
    ) # end navset_tab
    
), # end nav_panel for enrollment



  #####################
  # HEADCOUNT NAV PANEL
  #####################

  nav_panel(
    title = "Headcount",
    icon = icon("users"),
    
    # Page title
    h1("Student Headcount Analysis", style = "margin-bottom: 20px;"),
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
          choices = sort(unique(cedar_programs$department[!is.na(cedar_programs$department) & cedar_programs$department != ""]))
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

    # card( 
    #   card_header("Headcount Summary"),
    #   DT::DTOutput("hc_summary"),
    #   style = "height:100vh; min-height:100vh; overflow-y:auto;"
    # )

  ), # end nav_panel for headcount



  ######################  
  # REGSTATS NAV PANEL
  ########################
  nav_panel(
    title = "Regstats",
    icon = icon("tachometer-alt"), 
    
    # Page title
    h1("Registration Statistics Dashboard", style = "margin-bottom: 20px;"),
    
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
               inputId = "rs_term",
               label = "Term", 
               multiple = TRUE,
               choices = sort(unique(c(cedar_sections$term_type,cedar_sections$term)),decreasing = TRUE)),
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
      column(2,
             selectizeInput(
               inputId = "rs_course",
               label = "Select Course", 
               multiple = TRUE,
               choices = NULL,
               options = list(placeholder = "Type to search courses...")),
      )
    ), # end fluidRow
    
    fluidRow(
      column(2,
             numericInput(
               inputId = "rs_min_impacted",   # min impacted course for flagged list
               label = "Min Impacted",
               value = cedar_regstats_thresholds[["min_impacted"]])
      ),
      column(2,
             numericInput(
               inputId = "rs_pct_sd",   # pct standard deviation for flagging unusual enrolmment
               label = "SD %",
               value = cedar_regstats_thresholds[["pct_sd"]])
      ),
      column(2,
             numericInput(
               inputId = "rs_min_squeeze",   # squeeze is ratio of avail seats to  mean attrition
               label = "Min Squeeze",
               value = cedar_regstats_thresholds[["min_squeeze"]])
      ),
      column(2,
             numericInput(
               inputId = "rs_min_wait",   # min number of students on waitlist before being flagged
               label = "Min Waiting", 
               value = cedar_regstats_thresholds[["min_wait"]])
      ),
      column(2,
             actionButton("rs_dashboard_button", 
                         label = "Generate Dashboard", 
                         class = "btn-primary",
                         icon = icon("tachometer-alt"))
      ),
      column(2,
             downloadButton("rs_report_download", 
                           label = "Download Report", 
                           class = "btn-success",
                           icon = icon("download"))
      )
    ), # end fluidRow
    
    # Content area for regstats dashboard
    uiOutput("rs_dashboard")
    
  ), # end regstats nav_panel



  # Reports dropdown menu
  nav_menu(
    title = "Reports",
    icon = icon("file-alt"),
    
    # Inside the Reports nav_menu, replace the Course Reports nav_panel:
nav_panel(
  title = "Course Reports",
  icon = icon("file-lines"),
  
  # Page title
  h1("Individual Course Reports", style = "margin-bottom: 20px;"),
  
  p("Analyze individual course enrollment patterns, student flows, and grade distributions."),
  
  # Course selection and report generation (free floating)
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
      ) # end column for download button
  ), # end fluidRow for course selection
  
  # Tabbed report output
  navset_tab(
    id = "cr_tabs",
        
        # Enrollment Tab
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
        
        # Course Flows Tab
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
        
        # Rollcall Tab
        nav_panel(
          "Rollcall",
          icon = icon("user-check"),        
          p("Shows the composition of students taking this course by classification and major."),

          # Campus filter row
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


        
        # Outcomes Tab (placeholder for future use)
        nav_panel(
          "Outcomes",
          icon = icon("graduation-cap"),
          div(
            style = "text-align: center; padding: 40px;",
            icon("chart-line", class = "fa-3x text-muted"),
            h4("Coming Soon", style = "margin-top: 20px; color: #666;"),
            p("Future outcomes analysis will appear here.", style = "color: #888;")
          )
        ),

        # DFW Tab (password protected)
        nav_panel(
          "DFW",
          icon = icon("chart-bar"),
          uiOutput("cr_dfw_tab_content")
        )
      ) # end navset_tab
  ), # end course reports nav_panel


###########
# DEPT REPORTS NAV PANEL
###########

    nav_panel(
      title = "Department Reports",
      icon = icon("folder-tree"),


      # Page title
      h1("Department-Level Reports", style = "margin-bottom: 20px;"),

      fluidRow(
        column(6,
          selectizeInput(
            inputId = "dept_report_dept",
            label = "Select Department",
            multiple = FALSE,
            choices = sort(unique(cedar_programs$department)),
            selected = ""
          )
        ),
        column(3,
          actionButton("dept_report_button", 
                      label = "Generate Interactive Report", 
                      class = "btn-primary",
                      icon = icon("chart-line"))
        ),
        column(3,
          downloadButton("dept_report_html_download", label = "Download HTML Report", class = "btn-success")
        )
      ),
      fluidRow(
        column(12,
          tags$div(
            style = "margin-bottom: 15px; padding: 10px; background-color: #f8f9fa; border-radius: 5px;",
            tags$p(
              style = "margin: 0; font-size: 0.9em; color: #666;",
              tags$strong("Interactive Report:"), " View plots and data within the app interface.",
              tags$br(),
              tags$strong("HTML Report:"), " Generate a standalone RMarkdown report that opens in a new tab."
            )
          )
        )
      ),
      fluidRow(
        column(12,
          uiOutput("dept_report")
        )
      )
    ) # end department reports nav_panel
  ), # end Reports nav_menu

  # Explorer dropdown menu  
  nav_menu(
    title = "Explorer",
    icon = icon("search"),
    
    nav_panel(
      title = "Seatfinder", 
      
      # Page title
      h1("Course / Seat Availability"),
      
      # Instructional note
      p("Seatfinder is a special case of the enrollment tab that focuses on courses with available seats for the specified search parameters.
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
                 choices = sort(unique(cedar_sections$department))),
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
    ), # end seatfinder nav_panel
    
    nav_panel(
      title = "Waitlists", 
      
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
    ) # end waitlists nav_panel
  ), # end Explorer nav_menu

  # Admin dropdown menu
  nav_menu(
    title = "Admin",
    icon = icon("cog"),

  nav_panel(
    title = "Data & Usage",

    # Page title
    h1("Data Status & Usage Analytics", style = "margin-bottom: 20px;"),

    # Data Status Section
    card( 
      card_header("Data Note"),
      
      "Data presented here MyReports data. It is not official institutional data, which has a specific meaning for required reporting purposes.
      Institutional data reports enrollment as of the 3rd Friday of the semester (the census date). My Reports data is updated nightly, which makes it a more useful source for data about things that happen after the census date. 
      "),

    card( 
      card_header("Data Summary"),
      div(DT::dataTableOutput("data_status_table"), style = "min-height: 300px;"),
      style = "min-height: 350px;"
    ),
    
    # Usage Analytics Section
    br(),
    h3("Usage Analytics"),
    
    fluidRow(
      column(4,
        dateInput("usage_start_date", "Start Date:", value = Sys.Date() - 7)
      ),
      column(4,
        dateInput("usage_end_date", "End Date:", value = Sys.Date())
      ),
      column(4,
        actionButton("refresh_usage", "Refresh Analytics", class = "btn-primary")
      )
    ),
    
    br(),
    
    card(
      card_header("CEDAR Usage Statistics"),
      verbatimTextOutput("usage_stats_output"),
      style = "min-height: 200px;"
    ),
    

    
    card(
      card_header("Session Details"),
      div(DT::dataTableOutput("session_details_table"), style = "min-height: 300px;"),
      style = "min-height: 350px;"
    ),
    
    card(
      card_header("Feature Usage"),
      div(DT::dataTableOutput("feature_usage_table"), style = "min-height: 300px;"),
      style = "min-height: 350px;"
    ),
    
    # Cache Management Section
    br(),
    h3("Cache Management"),
    card(
      card_header("Course Report Cache"),
      p("CEDAR caches expensive lookout calculations (course flow analysis) to speed up repeated course report requests. The cache automatically invalidates when data changes."),
      fluidRow(
        column(4,
          actionButton("refresh_cache_stats", "Refresh Stats", class = "btn-info", icon = icon("sync"))
        ),
        column(4,
          actionButton("clear_all_cache", "Clear All Cache", class = "btn-warning", icon = icon("trash"))
        )
      ),
      br(),
      div(DT::dataTableOutput("cache_stats_table"), style = "min-height: 200px;"),
      style = "min-height: 300px;"
    )
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

