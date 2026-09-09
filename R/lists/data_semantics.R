# CEDAR-PLATFORM: registry mechanism; its ENTRIES are institution-specific
# data_semantics.R — what CEDAR knows about its own data that the data does not say.
#
# Banner records facts. It does not record that a code changed meaning, that a
# program used a major code for intent rather than admission, or that two tables
# name the same thing differently. Those are things people learn once, usually
# the hard way, and then have to remember forever.
#
# This is where they get written down, as DATA rather than as an exception coded
# into whichever surface tripped over it first. A caveat recorded here is
# available to every consumer; a caveat coded into one cone is available to that
# cone, until someone rewrites it.
#
# ── The one hard rule ─────────────────────────────────────────────────────────
#
# ANNOTATE, NEVER MUTATE. An entry here explains what a value means. It must
# never be used to rewrite rows so they mean something else. Recoding historical
# Radiologic Sciences majors as pre-majors, for instance, would assert a
# per-student fact the data does not support -- some of those students really
# were admitted -- and would silently change nine years of numbers with no trace.
# Marking the range as intent-coded is honest; rewriting it is fabrication.
#
# ── What belongs here, and what does not ──────────────────────────────────────
#
#   Belongs:      a code's meaning changed at a known term; a program's major
#                 code records intent rather than admission; two tables that
#                 look joinable are not; a value that is a snapshot rather than
#                 a per-term fact.
#
#   Does NOT:     a mapping ERROR -- that is wrong data, and belongs in
#                 program_code_maps.R where it can be corrected retroactively.
#                 Nor a DERIVED measure: "which students were admitted" is not
#                 recorded anywhere, so no annotation can supply it. That needs
#                 a computed proxy and is genuinely code.
#
#   Also not:     rules governing what an analysis may DO, as opposed to what a
#                 value MEANS. The field-reliability contract (AGENTS.md) is
#                 deliberately rules-plus-tests rather than a registry entry,
#                 because it constrains analyses, not values.
#
# ── Entry shape ───────────────────────────────────────────────────────────────
#
#   id           stable slug, referenced by tests and surfaces
#   kind         "semantic_break" | "intent_coding" | "join_hazard"
#   summary      one line, safe to show a reader verbatim
#   scope        list(table, column, values) -- what the entry is about
#   terms        list(from, through) -- inclusive bounds, NA for open-ended
#   effect       "warn" (surface a caveat) | "exclude" (drop from an analysis)
#   detail       the full explanation, for a developer or a methodology panel
#   evidence     the measurement that established it, so it can be rechecked
#   recorded_on  when it was written down

CEDAR_DATA_SEMANTICS <- list(

  list(
    id = "rads-major-code-records-intent",
    kind = "intent_coding",
    summary = paste(
      "Before Fall 2026, the Radiologic Sciences major code recorded intent to",
      "enter the program, not admission to it. Outcome mixes for this program",
      "measure an admission funnel, not attrition from an admitted cohort."
    ),
    scope = list(table = "cedar_programs", column = "major_code", values = "RADS"),
    terms = list(from = NA_integer_, through = 202610L),
    effect = "warn",
    detail = paste(
      "The pre-major code FRAD first appears in 202660. Before that every",
      "student intending Radiologic Sciences was carried as a declared RADS",
      "major, so the population conflates 'wants this program' with 'was",
      "admitted to it'. A Pathways population for this program therefore shows",
      "roughly a third switched out and a third stopped out, which is the",
      "admission ratio rather than students failing out. From 202660 the two",
      "are separable through is_pre_major; before it they are not, and no",
      "annotation can separate them -- that needs a derived admission proxy."
    ),
    evidence = paste(
      "143-189 declared RADS majors per recent term against 13-19 degrees",
      "awarded per year, steady across 2018-2026. FRAD first appears 202660",
      "(40 students), reaching 194 by 202680 against 35 declared."
    ),
    recorded_on = "2026-09-09"
  ),

  list(
    id = "phrd-undergraduate-pre-pharmacy",
    kind = "semantic_break",
    summary = paste(
      "Before Spring 2025, undergraduates carrying the Doctor of Pharmacy code",
      "were pre-pharmacy students, not doctoral candidates. From 202580 they",
      "carry FPHS instead."
    ),
    scope = list(table = "cedar_programs", column = "major_code", values = "PHRD"),
    terms = list(from = NA_integer_, through = 202510L),
    effect = "warn",
    detail = paste(
      "transform_programs() encodes this as an is_pre_major condition:",
      "major_code == 'PHRD' & student_level in ('UG','NG'). The rule is correct",
      "and stays where it is -- deriving a stored column is not something an",
      "annotation can do -- but the REASON it exists belongs here, where a",
      "reader of any PHRD figure can find it. Counting undergraduate PHRD rows",
      "as doctoral students overstates the professional programme and",
      "understates its pipeline."
    ),
    evidence = paste(
      "The code switched to FPHS at 202580; the transform's condition names",
      "202580 as the boundary and this entry bounds at the preceding term."
    ),
    recorded_on = "2026-09-09"
  ),

  list(
    id = "degrees-programs-name-mismatch",
    kind = "join_hazard",
    summary = paste(
      "cedar_degrees and cedar_programs use different program-name",
      "vocabularies. Join them on major_code, never on program_name."
    ),
    scope = list(table = "cedar_degrees", column = "program_name", values = NA_character_),
    terms = list(from = NA_integer_, through = NA_integer_),
    effect = "warn",
    detail = paste(
      "Only 3 of 303 distinct program_name values in cedar_degrees appear in",
      "cedar_programs$program_name. A join on program_name therefore returns",
      "almost nothing while erroring on nothing -- the failure mode is an empty",
      "or tiny result that looks like a real finding. major_code joins cleanly.",
      "Note also that cedar_degrees carries multiple award rows per student and",
      "mixes award levels, so count distinct students and filter award_category",
      "before comparing degrees to an undergraduate major headcount."
    ),
    evidence = paste(
      "3/303 name overlap measured 2026-09-09. NURS shows 3,026 degree rows",
      "for 1,007 distinct students across three award categories."
    ),
    recorded_on = "2026-09-09"
  )
)


cedar_data_semantics <- function(kind = NULL) {
  entries <- CEDAR_DATA_SEMANTICS
  if (is.null(kind)) return(entries)
  Filter(function(entry) entry$kind %in% kind, entries)
}


#' Semantic annotations that apply to a table, optionally narrowed
#'
#' @param table CEDAR table name, e.g. "cedar_programs".
#' @param values Optional codes/values in scope; an entry whose scope names
#'   specific values matches only when one of them is present.
#' @param terms Optional term codes; an entry with term bounds matches only when
#'   at least one term falls inside them.
#' @return A list of matching entries.
cedar_semantic_notes <- function(table, values = NULL, terms = NULL) {
  if (length(table) != 1L || is.na(table)) {
    stop("[data_semantics.R] One table name is required.", call. = FALSE)
  }
  Filter(function(entry) {
    if (!identical(entry$scope$table, table)) return(FALSE)
    scoped <- entry$scope$values
    if (!is.null(values) && length(scoped) > 0 && !all(is.na(scoped))) {
      if (!any(values %in% scoped)) return(FALSE)
    }
    if (!is.null(terms) && length(terms) > 0) {
      from <- entry$terms$from
      through <- entry$terms$through
      in_range <- rep(TRUE, length(terms))
      if (!is.na(from)) in_range <- in_range & terms >= from
      if (!is.na(through)) in_range <- in_range & terms <= through
      if (!any(in_range)) return(FALSE)
    }
    TRUE
  }, CEDAR_DATA_SEMANTICS)
}


#' Render semantic notes as reader-facing caveat lines
#'
#' Returns the `summary` of each note, which is written to be shown verbatim.
cedar_semantic_caption <- function(notes) {
  if (length(notes) == 0) return(character(0))
  vapply(notes, function(entry) entry$summary, character(1))
}
