# What the tests in test-architecture.R share: builders, option lists, constants.

r_files_under <- function(...) {
  path <- file.path(cedar_base_dir, ...)
  list.files(path, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
}

read_code <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines <- lines[!grepl("^\\s*#", lines)]
  paste(lines, collapse = "\n")
}

relative_path <- function(path) {
  sub(paste0("^", normalizePath(cedar_base_dir), "/"), "", normalizePath(path))
}

extract_function_names <- function(file) {
  code <- read_code(file)
  hits <- regmatches(
    code,
    gregexpr("\\b[A-Za-z.][A-Za-z0-9_.]*\\s*<-\\s*function\\s*\\(", code, perl = TRUE)
  )[[1]]
  if (identical(hits, character(0)) || hits[1] == -1) {
    return(character())
  }
  sub("\\s*<-.*$", "", hits)
}

# Every `error = function(e)` handler in a file, with its body text. A brace
# handler is read to its matching brace; a one-line handler to the end of the
# line, which is enough to see what it returns.
architecture_error_handlers <- function(file) {
  text <- paste(readLines(file, warn = FALSE), collapse = "\n")
  starts <- gregexpr("error\\s*=\\s*function\\s*\\(\\s*[A-Za-z_.]*\\s*\\)", text)[[1]]
  if (length(starts) == 1L && starts[[1]] == -1L) return(character(0))
  # Each result keeps its `error = function(<arg>)` prefix so the classifier
  # can tell a handler that returns the condition itself from one returning
  # a literal.
  vapply(starts, function(start) {
    rest <- substr(text, start, nchar(text))
    prefix <- regmatches(rest, regexpr("^error\\s*=\\s*function\\s*\\([^)]*\\)\\s*", rest))
    after <- substr(rest, nchar(prefix) + 1L, nchar(rest))
    body <- if (startsWith(after, "{")) {
      depth <- 0L
      chars <- strsplit(after, "")[[1]]
      end <- length(chars)
      for (i in seq_along(chars)) {
        if (chars[[i]] == "{") depth <- depth + 1L
        if (chars[[i]] == "}") {
          depth <- depth - 1L
          if (depth == 0L) { end <- i; break }
        }
      }
      paste(chars[seq_len(end)], collapse = "")
    } else {
      sub("\n.*$", "", after)
    }
    paste0(trimws(prefix), " ", body)
  }, character(1))
}

# A handler is a silent fallback when it hands the caller a value without
# telling anyone. Showing the error (showNotification, the module helper
# handle_error), re-raising it (stop), warning, writing it to the log
# (message, cedar_log_*), or handing the condition itself to the caller
# (returning the error object or its conditionMessage, so the caller decides
# and can say why) are not silent: someone can find out. A degenerate
# statistic returning NA is the one sanctioned default.
architecture_silent_fallback <- function(handler) {
  prefix <- "^error\\s*=\\s*function\\s*\\(\\s*([A-Za-z_.]*)\\s*\\)\\s*"
  argument <- sub(paste0(prefix, ".*$"), "\\1", handler)
  body <- gsub("#[^\n]*", "", sub(prefix, "", handler))
  reported <- paste0(
    "showNotification\\(|handle_error\\(|\\bstop\\(|\\bwarning\\(|",
    "rlang::abort\\(|cli::cli_abort\\(|\\bmessage\\(|cedar_log[a-z_]*\\(|",
    "conditionMessage\\("
  )
  if (grepl(reported, body)) {
    return(FALSE)
  }
  compact_body <- gsub("^\\{|\\}$|\\s+", "", body)
  if (nzchar(argument) && identical(sub("\\)$", "", compact_body), argument)) {
    return(FALSE)
  }
  compact <- gsub("^\\{|\\}$|\\s+", "", body)
  if (grepl("^NA(_real_|_integer_|_character_|_logical_)?\\)?$", compact)) return(FALSE)
  TRUE
}

architecture_count_by_file <- function(files, counter) {
  counts <- vapply(files, counter, integer(1))
  names(counts) <- vapply(files, relative_path, character(1))
  counts[counts > 0L]
}

# Compare measured counts with the allowances and explain every mismatch.
architecture_expect_ratchet <- function(measured, allowance, what) {
  files <- union(names(measured), names(allowance))
  problems <- character(0)
  for (file in files) {
    have <- if (file %in% names(measured)) measured[[file]] else 0L
    allow <- if (file %in% names(allowance)) allowance[[file]] else 0L
    if (have > allow) {
      problems <- c(problems, sprintf(
        "%s has %d %s (allowance %d): fix the new one, do not raise the allowance",
        file, have, what, allow
      ))
    } else if (have < allow) {
      problems <- c(problems, sprintf(
        "%s has %d %s but an allowance of %d: lower the allowance to %d%s",
        file, have, what, allow, have,
        if (have == 0L) " by deleting its entry" else ""
      ))
    }
  }
  expect(length(problems) == 0L, paste(problems, collapse = "\n"))
}

# What sits at the top level of a test or helper file: one row per expression,
# with its line and its kind ("test" for test_that(), context() and
# testthat::local_edition(); "definition" for an assignment; "call" for
# anything else, a library() or a source() among them).
architecture_top_level <- function(file) {
  exprs <- parse(file, keep.source = TRUE)
  head_of <- function(e) if (is.call(e)) paste(deparse(e[[1]]), collapse = "") else ""
  heads <- vapply(exprs, head_of, character(1))
  what <- vapply(seq_along(exprs), function(i) {
    if (heads[[i]] %in% c("<-", "=", "<<-")) paste(deparse(exprs[[i]][[2]]), collapse = "")
    else if (nzchar(heads[[i]])) paste0(heads[[i]], "()")
    else "a bare value"
  }, character(1))
  # A definition's arguments: NA for an object, 0 for `function()`.
  n_args <- vapply(seq_along(exprs), function(i) {
    if (!heads[[i]] %in% c("<-", "=", "<<-")) return(NA_integer_)
    value <- exprs[[i]][[3]]
    if (is.call(value) && identical(value[[1]], as.name("function"))) length(value[[2]]) else NA_integer_
  }, integer(1))
  data.frame(
    file = rep(basename(file), length(exprs)),
    line = vapply(attr(exprs, "srcref"), function(ref) ref[[1]], integer(1)),
    what = what,
    kind = ifelse(heads %in% c("test_that", "context", "testthat::local_edition"), "test",
                  ifelse(heads %in% c("<-", "=", "<<-"), "definition", "call")),
    n_args = n_args,
    stringsAsFactors = FALSE
  )
}

# The helper functions that take no argument. A function with no argument
# returns the same thing every call, so a table written as one is fixed data
# and belongs in fixtures/scenario_tables.R as an object. These are not tables:
# each does something when a test calls it. The list may only get shorter.
helper_actions_without_arguments <- c(
  skip_if_no_catalogs       = "skips the test",
  skip_if_no_lookups        = "skips the test",
  load_r_environment_script = "sources scripts/r-environment.R into a fresh environment",
  load_transform_helpers    = "sources the transform into a fresh environment",
  projection_request_runner = "sources the projection build script",
  make_shared_rule_artifact = "writes rule files to a temporary directory",
  st01                      = "runs build_student_terms(), the function under test",
  ch_result                 = "runs credit_hours_by_major(), the function under test",
  ids_result                = "runs check_student_id_integrity(), the function under test",
  gpa_timeline              = "runs build_gpa_timeline(), the function under test",
  pcc_changes               = "runs detect_major_changes(), tested in the same file",
  gg_population             = "runs get_gen_ed_grad_cohort(), tested in the same file"
)
