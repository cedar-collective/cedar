# Admin > Data & Usage > Catalog Review. Sources and decisions remain files.
# Its Extraction diagnostics tab (the older parser's flags) was retired on
# 2026-11-27: the readings replaced it, and the one flag still worth reading,
# a degree total the catalog states two ways, is a catalog question now
# (catalog_total_conflict_questions()). load_catalog_review(),
# filter_catalog_review() and catalog_review_detail() remain for inspecting an
# analysis from the console and for the tests of the parser.

catalogReviewUI <- function(id, catalog, roadmaps, drafts = NULL) {
  ns <- NS(id)
  navset_tab(id = ns("mode"), selected = "rules",
    nav_panel("Visualization rules", value = "rules", degreePlanRulesUI(ns("rules"), catalog, roadmaps)),
    nav_panel("Draft interpretations", value = "program", catalogNormalizationUI(ns("normalization"))),
    nav_panel("Catalog questions", value = "questions", catalogQuestionsUI(ns("questions"), drafts)))
}

# Render only text and a small tag vocabulary. No catalog attributes, scripts,
# active embeds or event handlers ever reach the browser; list nesting survives.
catalog_review_source_view <- function(value) {
  if (!is.character(value) || length(value) != 1L) {
    return(tags$pre(as.character(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA))))
  }
  document <- catalog_html_document(value)
  root <- xml2::xml_find_first(document, "//div[@id='cedar-source']")
  allowed <- c("div", "p", "ul", "ol", "li", "span", "strong", "em", "b", "i", "br", "table", "thead", "tbody", "tr", "th", "td", "code", "pre")
  render <- function(node) {
    if (xml2::xml_type(node) == "text") return(xml2::xml_text(node))
    name <- xml2::xml_name(node)
    if (name %in% c("script", "style")) return(NULL)
    if (!name %in% allowed) name <- "span"
    htmltools::tag(name, lapply(xml2::xml_contents(node), render))
  }
  div(class = "cedar-body", lapply(xml2::xml_contents(root), render))
}

catalogReviewServer <- function(id, root, active, catalog, roadmaps,
    review_root = file.path(dirname(dirname(root)), "catalog-normalizations", basename(root)), shared = NULL,
    drafts = NULL, boards = NULL) {
  moduleServer(id, function(input, output, session) {
    degreePlanRulesServer("rules", catalog, roadmaps, shared)
    catalogQuestionsServer("questions", drafts, boards)
    catalogNormalizationServer("normalization", root = review_root, capture_root = root,
      active = reactive(isTRUE(active()) && identical(input$mode, "program")))
  })
}
