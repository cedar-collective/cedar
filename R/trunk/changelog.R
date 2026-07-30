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

# Load evergreen homepage feature spotlights from YAML.
load_feature_spotlights <- function() {
  spotlights_file <- file.path(cedar_base_dir, "config", "feature_spotlights.yml")
  if (!file.exists(spotlights_file)) {
    message("[changelog] feature_spotlights.yml not found at ", spotlights_file)
    return(list())
  }

  tryCatch({
    spotlight_data <- yaml::read_yaml(spotlights_file)
    spotlights <- spotlight_data$spotlights
    if (is.null(spotlights)) list() else spotlights
  }, error = function(e) {
    message("[changelog] Error loading feature spotlights: ", e$message)
    list()
  })
}

# Pick one evergreen feature spotlight for the homepage. Changelog highlights
# stay chronological; this can rotate so useful-but-not-new features resurface.
get_feature_spotlight <- function() {
  spotlights <- load_feature_spotlights()
  if (length(spotlights) == 0) return(NULL)
  spotlights[[sample.int(length(spotlights), 1)]]
}

# Get recent changelog entries
get_recent_changelog <- function(max_entries = 3) {
  changelog <- load_changelog()
  changelog[1:min(max_entries, length(changelog))]
}

# The newest changelog entry is CEDAR's app-version source of truth. Keep
# release-facing version labels in config/changelog.yml so homepage highlights,
# the changelog modal, Data & Usage, and release notes all point at one place.
get_cedar_version_info <- function() {
  changelog <- load_changelog()
  if (length(changelog) == 0 || is.null(changelog[[1]]$version)) {
    return(list(
      version = "unknown",
      date = NA_character_,
      title = "No changelog entry found",
      type = NA_character_
    ))
  }
  entry <- changelog[[1]]
  val_or <- function(x, default) {
    if (is.null(x) || length(x) == 0) default else x
  }
  list(
    version = val_or(entry$version, "unknown"),
    date = val_or(entry$date, NA_character_),
    title = val_or(entry$title, ""),
    type = val_or(entry$type, NA_character_)
  )
}

get_cedar_version <- function() {
  get_cedar_version_info()$version
}

# Collect recent feature highlights for the homepage "What's New" strip.
# Walks changelog entries newest-first and gathers the curated `highlights`
# (friendly, user-facing feature blurbs) until `max` are collected. Each
# returned highlight is augmented with its entry's version and date.
get_recent_highlights <- function(max = 4) {
  changelog <- load_changelog()
  out <- list()
  for (entry in changelog) {
    highlights <- entry$highlights
    if (is.null(highlights) || length(highlights) == 0) next
    for (h in highlights) {
      h$version <- entry$version
      h$date    <- entry$date
      out[[length(out) + 1]] <- h
      if (length(out) >= max) return(out)
    }
  }
  out
}

# Collect recent "improvements" for the homepage chip row — the smaller fixes
# and enhancements that signal steady progress without being headline features.
# Walks entries newest-first. Each improvement may be authored as a plain string
# (static chip) or a list with `title` and an optional `tab` (linked chip).
get_recent_improvements <- function(max = 4) {
  changelog <- load_changelog()
  out <- list()
  for (entry in changelog) {
    improvements <- entry$improvements
    if (is.null(improvements) || length(improvements) == 0) next
    for (imp in improvements) {
      if (is.character(imp)) imp <- list(title = imp)
      imp$version <- entry$version
      imp$date    <- entry$date
      out[[length(out) + 1]] <- imp
      if (length(out) >= max) return(out)
    }
  }
  out
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
