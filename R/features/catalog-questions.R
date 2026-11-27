# Catalog questions: every open question in the institution's catalog
# readings, on one page and as a document to send.
#
# A reading asks what the catalog leaves unclear: its questions and its
# unresolved rules, each citing a passage. scripts/compile-degree-interpretations.R
# --write lists them for every latest reading, board or not, with the passage
# and who can settle each (the reading's `triage`, CATALOG_QUESTION_SETTLERS),
# in degree_drafts/degree_reading_questions.csv; read_degree_drafts() reads it.
# Admin > Data & Usage > Catalog Review > Catalog questions shows it
# (R/modules/catalog-questions.R), and format_catalog_questions() is the same
# list as text, for the department or the catalog office.

CATALOG_QUESTION_NOT_SORTED <- "Not sorted yet"

# Who settles each item, in words; a reading that names no one is "Not sorted yet".
catalog_question_settler_label <- function(settled_by) {
  ifelse(nzchar(settled_by), unname(CATALOG_QUESTION_SETTLERS[settled_by]), CATALOG_QUESTION_NOT_SORTED)
}

# Where to change an item: its reading file and the item within it.
catalog_question_location <- function(reading, item) {
  paste0(reading, " · ", sub(":", " ", item, fixed = TRUE))
}

#' The "Who can settle it" picker: every settler and "Not sorted yet", each with its count
#'
#' @param questions `read_degree_drafts()$questions`.
#' @return Named character vector: values "" (every item), the settler names
#'   and "none"; names are the labels with their counts.
catalog_question_settler_choices <- function(questions) {
  n <- function(x) sum(questions$settled_by == x)
  values <- c("", names(CATALOG_QUESTION_SETTLERS), "none")
  counts <- c(nrow(questions), vapply(names(CATALOG_QUESTION_SETTLERS), n, 1L), n(""))
  labels <- c("Any", unname(CATALOG_QUESTION_SETTLERS), CATALOG_QUESTION_NOT_SORTED)
  stats::setNames(values, paste0(labels, " (", counts, ")"))
}

#' What a filtered list holds, in words, for the document's opening line
catalog_question_scope <- function(settled_by = "", program = "") {
  who <- if (!nzchar(settled_by)) "All open questions" else
    paste0("Who can settle them: ", if (settled_by == "none") CATALOG_QUESTION_NOT_SORTED else CATALOG_QUESTION_SETTLERS[[settled_by]])
  paste0(who, if (nzchar(program)) paste0(". Program: ", program))
}

#' The program picker: every program with an open item, alphabetical
catalog_question_program_choices <- function(questions) {
  programs <- sort(unique(questions$program_title))
  c(stats::setNames("", paste0("All programs (", length(programs), ")")), stats::setNames(programs, programs))
}

#' The open items a reader asked for, in display order
#'
#' @param questions `read_degree_drafts()$questions`.
#' @param settled_by "" for everyone, a `CATALOG_QUESTION_SETTLERS` name, or
#'   "none" for the items no one is named for.
#' @param program "" for every program, or a `program_title`.
#' @return Tibble, by program and then the reading's own order: `program`,
#'   `catalog_url`, `settled_by` (in words), `question` (a rule's or passage's
#'   label leads its text), `section`, `passage`, `location` (file and item).
catalog_question_rows <- function(questions, settled_by = "", program = "") {
  if (!settled_by %in% c("", names(CATALOG_QUESTION_SETTLERS), "none")) stop("[catalog-questions.R] Unknown settled_by: ", settled_by)
  keep <- questions
  if (nzchar(settled_by)) keep <- keep[keep$settled_by == if (settled_by == "none") "" else settled_by, ]
  if (nzchar(program)) keep <- keep[keep$program_title == program, ]
  keep <- keep[order(keep$program_title, seq_len(nrow(keep))), ]
  tibble::tibble(program = keep$program_title, catalog_url = keep$catalog_url,
    settled_by = catalog_question_settler_label(keep$settled_by),
    question = ifelse(keep$kind == "question", keep$question,
                      paste0(keep$label, ifelse(grepl("[?.!]$", keep$label), " ", ": "), keep$question)),
    section = keep$section, passage = keep$passage, location = catalog_question_location(keep$reading, keep$item))
}

#' The compiled boards, whether each reading is signed off, and what each board leaves out
#'
#' @param boards `publish_degree_drafts()` output.
#' @return Tibble, one row per compiled board in the degree list's order:
#'   `degree`, `review` (the status note), `note` (the catalog row's notes:
#'   what the board does not draw, and why it is a draft).
degree_draft_board_rows <- function(boards) {
  compiled <- boards$status[boards$status$source == "compiled", ]
  rows <- boards$catalog$catalogs[match(compiled$catalog_id, boards$catalog$catalogs$catalog_id), ]
  tibble::tibble(degree = rows$degree_label, review = compiled$note, note = rows$notes)
}

#' The open items as a document: by program, each with its passage and link
#'
#' The text a page offers to download, for the department or the catalog
#' office: one heading per program with its catalog page, then each question
#' with the start of the passage it is about.
#'
#' @param rows `catalog_question_rows()` output.
#' @param scope What the rows are, in words, for the opening line ("Who can
#'   settle them: The catalog").
#' @param passage_chars How much of each passage to quote.
#' @return One string, Markdown.
format_catalog_questions <- function(rows, scope, passage_chars = 300L) {
  if (!nrow(rows)) return(paste0("# Open questions in the catalog readings\n\n", scope, "\n\nNo open questions.\n"))
  quote <- function(text) if (nchar(text) > passage_chars) paste0(substr(text, 1L, passage_chars), "…") else text
  programs <- unique(rows$program)
  blocks <- vapply(programs, function(p) {
    own <- rows[rows$program == p, ]
    items <- vapply(seq_len(nrow(own)), function(i) paste0(i, ". ", own$question[i], "\n   ",
      own$section[i], ": \"", quote(own$passage[i]), "\"\n   (", own$settled_by[i], "; ", own$location[i], ")"), "")
    paste0("## ", p, "\n\n", own$catalog_url[1], "\n\n", paste(items, collapse = "\n\n"))
  }, "")
  paste0("# Open questions in the catalog readings\n\n", scope, ". ", nrow(rows), if (nrow(rows) == 1L) " question" else " questions",
    " in ", length(programs), if (length(programs) == 1L) " program" else " programs",
    ", each with the start of the catalog passage it is about.\n\n", paste(blocks, collapse = "\n\n"), "\n")
}
