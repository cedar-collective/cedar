#!/usr/bin/env Rscript
#' Generate Function Reference Documentation from Roxygen Comments
#'
#' This script extracts roxygen2 documentation from R files and generates
#' Jekyll-compatible markdown files for the docs site.
#'
#' Usage: Rscript scripts/generate-function-docs.R
#'
#' Output: docs/reference/functions.md (combined reference)
#'         docs/reference/functions/ (individual function files)

library(stringr)

# Configuration
R_DIRS <- c("R/cones", "R/branches", "R/data-parsers")
OUTPUT_DIR <- "docs/reference"
COMBINED_OUTPUT <- file.path(OUTPUT_DIR, "functions.md")

#' Parse a single R file and extract roxygen blocks
#'
#' @param file_path Path to R file
#' @return List of parsed roxygen blocks with function info
parse_r_file <- function(file_path) {
  lines <- readLines(file_path, warn = FALSE)

  blocks <- list()
  current_block <- NULL
  in_roxygen <- FALSE

  for (i in seq_along(lines)) {
    line <- lines[i]

    # Check if this is a roxygen comment line
    if (grepl("^#'", line)) {
      if (!in_roxygen) {
        # Start new block
        in_roxygen <- TRUE
        current_block <- list(
          file = basename(file_path),
          start_line = i,
          roxygen_lines = c(),
          title = NULL,
          description = NULL,
          params = list(),
          return_value = NULL,
          examples = c(),
          details = NULL,
          seealso = NULL
        )
      }
      # Add line to current block (remove #' prefix)
      current_block$roxygen_lines <- c(current_block$roxygen_lines, sub("^#'\\s?", "", line))
    } else if (in_roxygen) {
      # End of roxygen block - look for function definition
      if (grepl("^[a-zA-Z_][a-zA-Z0-9_]*\\s*<-\\s*function", line)) {
        func_name <- str_extract(line, "^[a-zA-Z_][a-zA-Z0-9_]*")
        current_block$function_name <- func_name
        current_block$end_line <- i

        # Parse the roxygen lines
        current_block <- parse_roxygen_block(current_block)

        # Only include if we have a function name and title
        if (!is.null(current_block$function_name) && !is.null(current_block$title)) {
          blocks[[length(blocks) + 1]] <- current_block
        }
      }
      in_roxygen <- FALSE
      current_block <- NULL
    }
  }

  return(blocks)
}

#' Parse roxygen lines into structured documentation
#'
#' @param block Block with raw roxygen_lines
#' @return Block with parsed fields
parse_roxygen_block <- function(block) {
  lines <- block$roxygen_lines

  # State machine for parsing
  current_tag <- "description"
  current_content <- c()
  current_param_name <- NULL

  for (line in lines) {
    # Check for tags
    if (grepl("^@param\\s+", line)) {
      # Save previous content
      block <- save_tag_content(block, current_tag, current_content, current_param_name)
      # Start new param
      current_tag <- "param"
      match <- str_match(line, "^@param\\s+(\\S+)\\s*(.*)")
      current_param_name <- match[2]
      current_content <- if (!is.na(match[3])) match[3] else ""
    } else if (grepl("^@return\\s*", line)) {
      block <- save_tag_content(block, current_tag, current_content, current_param_name)
      current_tag <- "return"
      current_content <- sub("^@return\\s*", "", line)
    } else if (grepl("^@examples?\\s*", line)) {
      block <- save_tag_content(block, current_tag, current_content, current_param_name)
      current_tag <- "examples"
      current_content <- c()
    } else if (grepl("^@details\\s*", line)) {
      block <- save_tag_content(block, current_tag, current_content, current_param_name)
      current_tag <- "details"
      current_content <- sub("^@details\\s*", "", line)
    } else if (grepl("^@seealso\\s*", line)) {
      block <- save_tag_content(block, current_tag, current_content, current_param_name)
      current_tag <- "seealso"
      current_content <- sub("^@seealso\\s*", "", line)
    } else if (grepl("^@export", line) || grepl("^@noRd", line)) {
      # Skip export/noRd tags
      next
    } else if (grepl("^@", line)) {
      # Unknown tag, skip
      next
    } else {
      # Continuation of current tag
      current_content <- c(current_content, line)
    }
  }

  # Save final content
  block <- save_tag_content(block, current_tag, current_content, current_param_name)

  # First non-tag line is usually the title
  if (length(lines) > 0 && !grepl("^@", lines[1])) {
    block$title <- lines[1]
    # Description is lines 2+ until first @tag (already captured in description)
  }

  return(block)
}

#' Save tag content to block
save_tag_content <- function(block, tag, content, param_name = NULL) {
  content_str <- paste(trimws(content), collapse = " ")
  content_str <- trimws(content_str)

  if (tag == "description" && content_str != "") {
    block$description <- content_str
  } else if (tag == "param" && !is.null(param_name)) {
    block$params[[param_name]] <- content_str
  } else if (tag == "return" && content_str != "") {
    block$return_value <- content_str
  } else if (tag == "examples") {
    block$examples <- content
  } else if (tag == "details" && content_str != "") {
    block$details <- content_str
  } else if (tag == "seealso" && content_str != "") {
    block$seealso <- content_str
  }

  return(block)
}

#' Generate markdown for a single function
#'
#' @param block Parsed roxygen block
#' @return Character string of markdown
generate_function_md <- function(block) {
  md <- c()

  # Function header
  md <- c(md, sprintf("### `%s()`", block$function_name))
  md <- c(md, "")

  # Source file
  md <- c(md, sprintf("*Source: %s*", block$file))
  md <- c(md, "")

  # Title/Description
  if (!is.null(block$title)) {
    md <- c(md, sprintf("**%s**", block$title))
    md <- c(md, "")
  }

  if (!is.null(block$description) && block$description != block$title) {
    md <- c(md, block$description)
    md <- c(md, "")
  }

  # Parameters
  if (length(block$params) > 0) {
    md <- c(md, "**Parameters:**")
    md <- c(md, "")
    for (param_name in names(block$params)) {
      md <- c(md, sprintf("- `%s` - %s", param_name, block$params[[param_name]]))
    }
    md <- c(md, "")
  }

  # Return value
  if (!is.null(block$return_value)) {
    md <- c(md, sprintf("**Returns:** %s", block$return_value))
    md <- c(md, "")
  }

  # Details
  if (!is.null(block$details)) {
    md <- c(md, "**Details:**")
    md <- c(md, "")
    md <- c(md, block$details)
    md <- c(md, "")
  }

  # Examples
  if (length(block$examples) > 0 && any(nchar(block$examples) > 0)) {
    md <- c(md, "**Example:**")
    md <- c(md, "```r")
    md <- c(md, block$examples)
    md <- c(md, "```")
    md <- c(md, "")
  }

  md <- c(md, "---")
  md <- c(md, "")

  return(paste(md, collapse = "\n"))
}

#' Group functions by category (file)
#'
#' @param blocks List of all parsed blocks
#' @return Named list grouped by file
group_by_file <- function(blocks) {
  groups <- list()
  for (block in blocks) {
    file <- block$file
    if (is.null(groups[[file]])) {
      groups[[file]] <- list()
    }
    groups[[file]][[length(groups[[file]]) + 1]] <- block
  }
  return(groups)
}

# Main execution
main <- function() {
  message("=== Generating Function Reference Documentation ===")
  message("")

  all_blocks <- list()

  # Parse all R files
  for (dir in R_DIRS) {
    if (dir.exists(dir)) {
      r_files <- list.files(dir, pattern = "\\.R$", full.names = TRUE)
      message(sprintf("Scanning %s (%d files)...", dir, length(r_files)))

      for (r_file in r_files) {
        blocks <- parse_r_file(r_file)
        if (length(blocks) > 0) {
          message(sprintf("  %s: %d documented functions", basename(r_file), length(blocks)))
          all_blocks <- c(all_blocks, blocks)
        }
      }
    }
  }

  message("")
  message(sprintf("Total: %d documented functions", length(all_blocks)))
  message("")

  if (length(all_blocks) == 0) {
    message("No documented functions found!")
    return(invisible(NULL))
  }

  # Generate combined markdown file
  message("Generating combined reference...")

  # Jekyll front matter
  md <- c(
    "---",
    "title: Function Reference",
    "nav_order: 3",
    "parent: Reference",
    "---",
    "",
    "# CEDAR Function Reference",
    "",
    "This reference is auto-generated from roxygen2 comments in the source code.",
    "",
    sprintf("*Generated: %s*", Sys.time()),
    "",
    "---",
    ""
  )

  # Group by file and generate
  grouped <- group_by_file(all_blocks)

  for (file in sort(names(grouped))) {
    # File header
    file_name <- sub("\\.R$", "", file)
    md <- c(md, sprintf("## %s", file_name))
    md <- c(md, "")

    # Functions in this file
    for (block in grouped[[file]]) {
      md <- c(md, generate_function_md(block))
    }
  }

  # Write combined file
  dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
  writeLines(md, COMBINED_OUTPUT)
  message(sprintf("Written: %s", COMBINED_OUTPUT))

  message("")
  message("=== Done! ===")
}

# Run
main()
