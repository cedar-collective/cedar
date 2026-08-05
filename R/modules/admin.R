# Shiny Module: Admin Tabs (Changelog + Cache Management)
#
# Two small modules that live inside the Data & Usage and Changelog nav_panels.
#
# Exported functions:
#   changelogUI(id)
#   changelogServer(id)
#   cacheUI(id)
#   cacheServer(id)


# =============================================================================
# Changelog sub-module
# =============================================================================

changelogUI <- function(id) {
  ns <- NS(id)
  tagList(
    fluidRow(
      column(12,
        card(
          card_header("Recent Updates"),
          card_body(htmlOutput(ns("changelog_recent")))
        )
      )
    ),
    fluidRow(
      column(12,
        card(
          card_header("All Changes"),
          card_body(htmlOutput(ns("changelog_full")))
        )
      )
    )
  )
}

changelogServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    output$changelog_recent <- renderUI({
      tryCatch({
        recent_entries <- get_recent_changelog(max_entries = 1)
        changelog_html <- format_changelog_html(recent_entries)
        if (changelog_html == "<p>No changelog entries available.</p>") {
          empty_state("No recent changes yet. Changelog entries appear here as releases ship.")
        } else {
          HTML(changelog_html)
        }
      }, error = function(e) {
        handle_error(e, "changelog_recent")
        div(class = "alert-box alert-box--critical",
            tags$strong("Could not load the changelog."),
            tags$div(e$message))
      })
    })

    output$changelog_full <- renderUI({
      tryCatch({
        all_entries <- load_changelog()
        if (length(all_entries) == 0) {
          empty_state("No changelog entries yet. The full history appears here once releases are recorded.")
        } else {
          changelog_html <- format_changelog_html(all_entries, max_entries = length(all_entries))
          HTML(changelog_html)
        }
      }, error = function(e) {
        handle_error(e, "changelog_full")
        div(class = "alert-box alert-box--critical",
            tags$strong("Could not load the full changelog."),
            tags$div(e$message))
      })
    })
  })
}


# =============================================================================
# Cache Management sub-module
# =============================================================================

cacheUI <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Course Report Cache"),
      p("CEDAR caches expensive lookup calculations (course flow analysis) to speed up repeated course report requests. The cache automatically invalidates when data changes."),
      fluidRow(
        column(4, actionButton(ns("refresh_cache_stats"), "Refresh Stats",
                               class = "btn-info", icon = icon("sync"))),
        column(4, actionButton(ns("clear_all_cache"), "Clear All Cache",
                               class = "btn-warning", icon = icon("trash")))
      ),
      br(),
      reactable::reactableOutput(ns("cache_stats_table"))
    ),
    card(
      card_header("Department Trends Cache"),
      p("Dept Trends headcount/base payloads are cached to disk by department and ISO week. Longer-running trend tabs still compute lazily when opened."),
      actionButton(ns("clear_dept_cache"), "Clear Dept Trends Cache",
                   class = "btn-warning", icon = icon("trash"))
    ),
    card(
      card_header("Dept Dashboard Cache"),
      p("Dept Dashboard snapshots are cached by department, campus scope, selected term, date, and CEDAR table hashes. Production data refreshes warm the primary audience dashboards each morning."),
      actionButton(ns("clear_dept_dashboard_cache"), "Clear Dept Dashboard Cache",
                   class = "btn-warning", icon = icon("trash"))
    ),
    card(
      card_header("Pathways Population Benchmarks"),
      p("College comparison benchmarks in the Pathways Population tab are cached by CEDAR current term, college, campus, student level, and population scope. Clear this after changing the benchmark logic or when a mid-semester data correction should be reflected immediately."),
      actionButton(ns("clear_population_benchmark_cache"), "Clear Pathways Benchmarks",
                   class = "btn-warning", icon = icon("trash"))
    ),
    card(
      card_header("Report Timing Estimates"),
      p("CEDAR learns separate calculation and cache-hit estimates from completed report runs. It also measures the additional time until the browser is usable and estimates the output payload size. Post-compute time includes serialization, transfer, and browser rendering."),
      fluidRow(
        column(4, actionButton(ns("refresh_timing_stats"), "Refresh Timing Stats",
                               class = "btn-info", icon = icon("sync"))),
        column(4, actionButton(ns("reset_report_timings"), "Reset Timing History",
                               class = "btn-warning", icon = icon("history")))
      ),
      br(),
      reactable::reactableOutput(ns("timing_stats_table")),
      tags$small(class = "text-muted",
                 "Payload size is an approximation based on values delivered to Shiny outputs; it is not a network-byte counter.")
    )
  )
}

cacheServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    cache_stats_data <- reactiveVal(NULL)
    timing_stats_data <- reactiveVal(NULL)

    observeEvent(input$refresh_cache_stats, {
      tryCatch({
        stats <- get_cache_stats()
        cache_stats_data(stats)
        showNotification("Cache statistics refreshed", type = "message")
        cedar_debug("[cache] Cache stats refreshed")
      }, error = function(e) {
        showNotification(paste("Error refreshing cache:", e$message), type = "error")
        message("[cache] Error refreshing cache stats: ", e$message)
      })
    })

    observeEvent(input$clear_all_cache, {
      showModal(cedar_confirm_modal(
        title = "Clear Course Report Cache",
        "Are you sure you want to clear all cached course report data? This will slow down the next request for each course.",
        confirm_button = actionButton(session$ns("confirm_clear_cache"), "Clear Cache", class = "btn-danger")
      ))
    })

    observeEvent(input$confirm_clear_cache, {
      tryCatch({
        clear_all_caches()
        removeModal()
        stats <- get_cache_stats()
        cache_stats_data(stats)
        showNotification("All cache cleared successfully", type = "message")
        cedar_debug("[cache] All cache cleared")
      }, error = function(e) {
        showNotification(paste("Error clearing cache:", e$message), type = "error")
        message("[cache] Error clearing cache: ", e$message)
      })
    })

    observeEvent(input$clear_dept_cache, {
      tryCatch({
        clear_dept_cache()
        showNotification("Department profile cache cleared", type = "message")
        cedar_debug("[cache] Dept profile cache cleared")
      }, error = function(e) {
        showNotification(paste("Error clearing dept cache:", e$message), type = "error")
        message("[cache] Error clearing dept cache: ", e$message)
      })
    })

    observeEvent(input$clear_dept_dashboard_cache, {
      tryCatch({
        n <- clear_dept_dashboard_cache()
        showNotification(
          paste0("Dept Dashboard cache cleared", if (n > 0) paste0(" (", n, " files)") else ""),
          type = "message"
        )
        cedar_debug("[cache] Dept Dashboard cache cleared")
      }, error = function(e) {
        showNotification(paste("Error clearing dept dashboard cache:", e$message), type = "error")
        message("[cache] Error clearing dept dashboard cache: ", e$message)
      })
    })

    observeEvent(input$clear_population_benchmark_cache, {
      tryCatch({
        n <- clear_population_benchmark_cache()
        showNotification(
          paste0("Pathways population benchmark cache cleared", if (n > 0) paste0(" (", n, " files)") else ""),
          type = "message"
        )
        cedar_debug("[cache] Pathways population benchmark cache cleared")
      }, error = function(e) {
        showNotification(paste("Error clearing pathways benchmark cache:", e$message), type = "error")
        message("[cache] Error clearing pathways benchmark cache: ", e$message)
      })
    })

    observeEvent(input$reset_report_timings, {
      showModal(cedar_confirm_modal(
        title = "Reset Timing Estimates",
        "Reset all recorded calculation, cache-hit, browser-visible, and payload timing history? Loading estimates will return to their configured defaults and learn again from subsequent report runs.",
        confirm_button = actionButton(
          session$ns("confirm_reset_report_timings"),
          "Reset Timings",
          class = "btn-danger"
        )
      ))
    })

    observeEvent(input$confirm_reset_report_timings, {
      tryCatch({
        n <- reset_report_timings() + reset_client_render_timings()
        timing_stats_data(get_client_render_timing_summary())
        removeModal()
        showNotification(
          if (n > 0) {
            paste0("Timing estimates reset (", n, " observations removed)")
          } else {
            "Timing estimates were already empty"
          },
          type = "message"
        )
        cedar_debug("[cache] Report timing estimates reset")
      }, error = function(e) {
        showNotification(paste("Error resetting timing estimates:", e$message), type = "error")
        message("[cache] Error resetting timing estimates: ", e$message)
      })
    })

    observeEvent(input$refresh_timing_stats, {
      tryCatch({
        timing_stats_data(get_client_render_timing_summary())
        showNotification("Timing statistics refreshed", type = "message")
      }, error = function(e) {
        showNotification(paste("Error refreshing timing statistics:", e$message), type = "error")
        message("[cache] Error refreshing timing statistics: ", e$message)
      })
    })

    output$timing_stats_table <- reactable::renderReactable({
      stats <- timing_stats_data()
      if (is.null(stats)) {
        return(reactable::reactable(
          data.frame(Message = "Click Refresh Timing Stats to load recent observations."),
          pagination = FALSE, theme = cedar_tbl_theme
        ))
      }
      if (nrow(stats) == 0L) {
        return(reactable::reactable(
          data.frame(Message = "No browser timing observations yet."),
          pagination = FALSE, theme = cedar_tbl_theme
        ))
      }

      names(stats) <- c(
        "Report", "Path", "Runs", "Avg compute (s)", "Avg post-compute (s)",
        "Avg total (s)", "P95 total (s)", "Avg payload (MB)",
        "Max payload (MB)", "Last observed"
      )
      reactable::reactable(
        stats, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE,
        compact = TRUE, searchable = TRUE, defaultPageSize = 10,
        showPageSizeOptions = TRUE, pageSizeOptions = c(10, 25, 50),
        defaultSorted = list(`Avg total (s)` = "desc")
      )
    })

    output$cache_stats_table <- reactable::renderReactable({
      stats <- cache_stats_data()

      if (is.null(stats)) {
        return(reactable::reactable(
          data.frame(Message = "Loading cache statistics..."),
          pagination = FALSE,
          theme = cedar_tbl_theme
        ))
      }
      if ("message" %in% colnames(stats)) {
        return(reactable::reactable(
          stats,
          pagination = FALSE,
          theme = cedar_tbl_theme
        ))
      }

      display_stats <- stats
      display_stats$size_mb  <- round(display_stats$size_mb, 2)
      display_stats$age_days <- round(display_stats$age_days, 1)
      display_stats$modified <- format(display_stats$modified, "%Y-%m-%d %H:%M")
      names(display_stats) <- c("Cache File", "Size (MB)", "Last Modified", "Age (days)")

      reactable::reactable(
        display_stats,
        theme = cedar_tbl_theme,
        striped = TRUE,
        highlight = TRUE,
        compact = TRUE,
        searchable = TRUE,
        defaultPageSize = 10,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(10, 25, 50),
        defaultSorted = list(`Last Modified` = "desc"),
        columns = list(
          `Size (MB)` = reactable::colDef(align = "right", format = reactable::colFormat(digits = 2)),
          `Age (days)` = reactable::colDef(align = "right", format = reactable::colFormat(digits = 1))
        )
      )
    })
  })
}
