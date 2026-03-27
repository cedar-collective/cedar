# CEDAR Changelog Helper Functions
# Following CEDAR patterns for modular configuration

# Load changelog from YAML file
load_changelog <- function() {
  changelog_file <- file.path(cedar_base_dir, "config", "changelog.yml")
  if (!file.exists(changelog_file)) {
    message("[changelog] Warning: changelog.yml not found at ", changelog_file)
    return(list())
  }
  
  tryCatch({
    changelog_data <- yaml::read_yaml(changelog_file)
    return(changelog_data$changelog)
  }, error = function(e) {
    message("[changelog] Error loading changelog: ", e$message)
    return(list())
  })
}

# Get recent changelog entries
get_recent_changelog <- function(max_entries = 3) {
  changelog <- load_changelog()
  changelog[1:min(max_entries, length(changelog))]
}

# Format changelog for HTML display
format_changelog_html <- function(entries = NULL, max_entries = 3) {
  if (is.null(entries)) {
    entries <- get_recent_changelog(max_entries)
  }
  
  if (length(entries) == 0) {
    return("<p>No changelog entries available.</p>")
  }
  
  html_parts <- c()
  
  for (entry in entries) {
    # Version header with badge
    type_class <- switch(entry$type,
      "major" = "badge-primary",
      "minor" = "badge-info", 
      "patch" = "badge-secondary",
      "badge-secondary"
    )
    
    version_html <- paste0(
      "<div class='changelog-entry'>",
      "<div class='changelog-date'>", entry$date, "</div>",
      "<h4 class='changelog-title'>", entry$title, " ",
      "<span class='badge ", type_class, "'>", entry$version, "</span>",
      "</h4>",
      "</div>"
    )
    
    # Items list
    items_html <- paste0(
      "<ul>",
      paste0("<li>", entry$items, "</li>", collapse = ""),
      "</ul>"
    )
    
    html_parts <- c(html_parts, version_html, items_html)
  }
  
  paste(html_parts, collapse = "")
}

# Get changelog for specific version
get_changelog_version <- function(version) {
  changelog <- load_changelog()
  for (entry in changelog) {
    if (entry$version == version) {
      return(entry)
    }
  }
  return(NULL)
}

# Get changelog entries by type
get_changelog_by_type <- function(type = "major") {
  changelog <- load_changelog()
  Filter(function(x) x$type == type, changelog)
}