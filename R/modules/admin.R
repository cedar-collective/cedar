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
          div(style = "text-align: center; padding: 20px; color: #666;",
              h4("No Recent Changes Available"),
              p("Changelog entries will appear here when available."))
        } else {
          HTML(changelog_html)
        }
      }, error = function(e) {
        handle_error(e, "changelog_recent")
        div(style = "color: #d9534f; padding: 20px;",
            h4("Error Loading Changelog"),
            p(paste("Unable to load changelog:", e$message)))
      })
    })

    output$changelog_full <- renderUI({
      tryCatch({
        all_entries <- load_changelog()
        if (length(all_entries) == 0) {
          div(style = "text-align: center; padding: 20px; color: #666;",
              h4("No Changelog Available"),
              p("Complete changelog will appear here when available."))
        } else {
          changelog_html <- format_changelog_html(all_entries, max_entries = length(all_entries))
          HTML(changelog_html)
        }
      }, error = function(e) {
        handle_error(e, "changelog_full")
        div(style = "color: #d9534f; padding: 20px;",
            h4("Error Loading Full Changelog"),
            p(paste("Unable to load full changelog:", e$message)))
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
      div(DT::dataTableOutput(ns("cache_stats_table")), class = "dt-container")
    ),
    card(
      card_header("Department Trends Cache"),
      p("Department trends reports are cached to disk after first generation. The cache invalidates automatically when source data changes. Use this button after manually correcting data or when reports look stale."),
      actionButton(ns("clear_dept_cache"), "Clear Dept Trends Cache",
                   class = "btn-warning", icon = icon("trash"))
    )
  )
}

cacheServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    cache_stats_data <- reactiveVal(NULL)

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
      showModal(modalDialog(
        title = "Confirm Clear All Cache",
        "Are you sure you want to clear all cached course report data? This will slow down the next request for each course.",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(session$ns("confirm_clear_cache"), "Clear Cache", class = "btn-danger")
        )
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

    output$cache_stats_table <- DT::renderDataTable({
      stats <- cache_stats_data()

      if (is.null(stats)) {
        return(DT::datatable(data.frame(Message = "Loading cache statistics..."), rownames = FALSE))
      }
      if ("message" %in% colnames(stats)) {
        return(DT::datatable(stats, rownames = FALSE, options = list(dom = "t")))
      }

      display_stats <- stats
      display_stats$size_mb  <- round(display_stats$size_mb, 2)
      display_stats$age_days <- round(display_stats$age_days, 1)
      display_stats$modified <- format(display_stats$modified, "%Y-%m-%d %H:%M")

      DT::datatable(
        display_stats,
        rownames = FALSE,
        colnames = c("Cache File", "Size (MB)", "Last Modified", "Age (days)"),
        options = list(
          pageLength = 10,
          scrollX    = TRUE,
          order      = list(list(2, "desc"))
        )
      )
    })
  })
}
