# CEDAR-PLATFORM: the topics a course's sections are taught under
#
# One course number can carry many courses: a first-year seminar or a
# special-topics slot lists a different title on each section. The title is
# the topic, read once, wording-blind (topic_title_key()): a leading
# section-type label ("T:", "Sem:", "Perf Conc:") is dropped, case,
# punctuation and spacing are ignored, and "&" reads as "and". What that key
# cannot match (a typo, an abbreviation, a title cut short at the schedule's
# length limit) is merged by a reviewed row of the institution's
# topic_titles.csv, read and validated here at load. A title neither matches
# stays a topic of its own and is listed beside the topics it was not merged
# with (Course Dynamics > Topics).
#
# The key is a list-layer function because the file is validated with it:
# a row whose title already matches its topic by the key merges nothing.

#' A leading section-type label: up to 12 characters before a colon. Banner's
#' rotating-topics slot is "T:", UNM's seminars "Sem:", its lessons "Perf
#' Conc:"; the label says what kind of section it is, never which topic.
TOPIC_TITLE_LABEL <- "^[^:]{1,12}:\\s*"

#' A section title without its leading section-type label
#'
#' @param title Character vector of section titles.
#' @return The titles trimmed, with any TOPIC_TITLE_LABEL removed; NA stays NA.
topic_title_text <- function(title) {
  trimws(sub(TOPIC_TITLE_LABEL, "", trimws(title)))
}

#' The wording-blind key of a section title
#'
#' Two titles with one key name one topic: the label dropped
#' (topic_title_text()), lower case, "&" as "and", every run of characters
#' other than letters and digits one space.
#'
#' @param title Character vector of section titles.
#' @return Character vector of keys; NA for an NA title, "" for a title with
#'   no letters or digits.
topic_title_key <- function(title) {
  x <- tolower(topic_title_text(title))
  x <- gsub("&", " and ", x, fixed = TRUE)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(x)
}

#' Check topic_titles.csv
#'
#' @param df The table as read.
#' @return The table with `title_key` and `topic_key` added, if valid. Stops
#'   listing every problem otherwise.
validate_topic_titles <- function(df) {
  problems <- character(0)
  blank <- function(x) is.na(x) | !nzchar(trimws(x))
  for (col in c("subject_course", "title", "topic")) {
    if (any(blank(df[[col]]))) problems <- c(problems, paste("topic_titles.csv: blank", col))
  }
  df$title_key <- topic_title_key(df$title)
  df$topic_key <- topic_title_key(df$topic)
  rows <- paste0(df$subject_course, " \"", df$title, "\"")
  same <- !blank(df$title) & !blank(df$topic) & df$title_key == df$topic_key
  if (any(same)) {
    problems <- c(problems, paste("topic_titles.csv: title already reads as its topic, so the row merges nothing:",
                                  paste(rows[same], collapse = "; ")))
  }
  key <- paste(df$subject_course, df$title_key)
  d <- unique(rows[duplicated(key)])
  if (length(d)) problems <- c(problems, paste("topic_titles.csv: one title merged twice:", paste(d, collapse = "; ")))
  # A topic that is itself merged into another would need two steps; name
  # the final topic instead.
  chained <- paste(df$subject_course, df$topic_key) %in% key
  if (any(chained)) {
    problems <- c(problems, paste("topic_titles.csv: topic is itself a merged title (name the final topic):",
                                  paste(rows[chained], collapse = "; ")))
  }
  if (length(problems)) {
    stop("[topic_titles.R] Invalid topic_titles.csv:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  df
}

CEDAR_TOPIC_TITLES <- validate_topic_titles(read_institution_file("topic_titles"))
