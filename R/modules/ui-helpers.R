# Shared UI helper functions available to all Shiny modules.
# Sourced by load-funcs.R before any module files.

# Collapsible blue info panel for column guides and methodology notes.
# Usage: info_panel("Title", p("..."), tags$ul(tags$li(...)))
info_panel <- function(title, ...) {
  tags$details(
    class = "cedar-info-panel",
    tags$summary(title),
    tags$div(class = "panel-body", ...)
  )
}

# Standard empty-state prompt shown before a user action (button click, selection).
# msg: instruction text shown to the user.
empty_state <- function(msg = "Set filters and click the button to load data.") {
  div(
    class = "empty-state",
    tags$p(msg)
  )
}

# Shared reactable theme — used by all cedar tables for consistent styling.
cedar_tbl_theme <- reactable::reactableTheme(
  color           = "#232826",
  backgroundColor = "#ffffff",
  borderColor     = "#d4c5b0",
  stripedColor    = "#faf5ee",
  highlightColor  = "#f0e8d8",
  cellPadding     = "5px 10px",
  style           = list(fontSize = "0.87rem"),
  headerStyle     = list(
    background    = "#6B4A2A",
    color         = "#f5eedf",
    fontWeight    = "600",
    fontSize      = "0.73rem",
    textTransform = "uppercase",
    letterSpacing = "0.05em",
    borderBottom  = "2px solid #8B6240"
  ),
  paginationStyle = list(fontSize = "0.82rem")
)
