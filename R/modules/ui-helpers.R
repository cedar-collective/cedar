# Shared UI helper functions available to all Shiny modules.
# Sourced by load-funcs.R before any module files.

# Collapsible info panel for column guides, methodology notes, and detail tables.
# Usage: info_panel("Title", p("..."), tags$ul(tags$li(...)))
info_panel <- function(title, ..., description = NULL, class = NULL) {
  classes <- paste(c("cedar-info-panel", class), collapse = " ")
  tags$details(
    class = classes,
    tags$summary(
      tags$span(
        class = "cedar-info-summary-copy",
        tags$span(class = "cedar-info-summary-title", title),
        if (!is.null(description)) {
          tags$span(class = "cedar-info-summary-description", description)
        }
      )
    ),
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

# Standard in-flow section heading for tab bodies. Replaces the ad-hoc
# h5(..., class = "text-secondary mb-1") pattern so spacing/size are uniform.
# level = "h6" renders the smaller subsection variant.
# Usage: section_heading("DFW Rates by Course")  /  section_heading("Changes by Term", level = "h6")
section_heading <- function(title, ..., level = "h5", class = NULL) {
  tag <- match.fun(level)
  base <- if (identical(level, "h6")) "cedar-section-heading--sub" else "cedar-section-heading"
  tag(class = paste(c(base, class), collapse = " "), title, ...)
}

# Shared heading + explanatory copy + body block.
# Use this when a section has a heading followed by a short description so the
# heading/paragraph/table spacing is consistent across modules.
section_block <- function(title, description = NULL, ..., level = "h5", class = NULL) {
  classes <- paste(c("cedar-section-block", class), collapse = " ")
  description_tag <- NULL
  if (!is.null(description)) {
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      description
    } else {
      tags$p(class = "text-hint", description)
    }
  }

  div(
    class = classes,
    section_heading(title, level = level),
    description_tag,
    ...
  )
}

# Primary explanatory paragraph ("what this tab/section does"). rem-based so it
# escapes the global body 0.9em shrink. Use for the lead copy under a heading.
lead_text <- function(...) tags$p(class = "cedar-lead", ...)

# Standard top filter band used by Cedar tabs and modules.
filter_bar <- function(title, subtitle = NULL, ..., class = NULL) {
  classes <- paste(c("filters-compact", class), collapse = " ")
  div(
    class = classes,
    h1(title),
    if (!is.null(subtitle)) tags$p(subtitle, class = "filter-subtitle"),
    ...
  )
}

# Aligns run/download/copy buttons with compact filter inputs.
filter_actions <- function(..., class = NULL) {
  classes <- paste(c("filter-actions", class), collapse = " ")
  div(class = classes, ...)
}

# Light green scope strip shown at the bottom of a filter bar.
filter_scope_stripe <- function(...) {
  div(class = "filter-scope-strip", ...)
}

# Shared campus + single-department selector formulation for department tabs.
dept_selector_bar <- function(title, subtitle, campus_input, dept_input,
                              actions = NULL, scope_output = NULL) {
  filter_bar(
    title,
    subtitle,
    fluidRow(
      column(3, campus_input),
      column(4, dept_input),
      if (!is.null(actions)) column(3, actions)
    ),
    scope_output
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
