context("Data semantics registry and anomaly screens")

# Self-mapping uses the shared HP01 fixture: those are raw program rows in the
# stable term set. The ratio screens below need three distinct degree YEARS,
# which is outside that set, so they are built locally with their expected
# values stated -- the boundary documented in developers/agent-testing.md.

test_that("the registry annotates a scope and stays out of everything else", {
  entry <- Filter(function(e) e$id == "rads-major-code-records-intent",
                  cedar_data_semantics())[[1]]
  expect_equal(entry$kind, "intent_coding")
  expect_equal(entry$effect, "warn")

  # In range: the annotation applies and its summary is safe to show a reader.
  notes <- cedar_semantic_notes("cedar_programs", values = "RADS", terms = 202410L)
  expect_true(any(vapply(notes, function(n) n$id, character(1)) ==
                    "rads-major-code-records-intent"))
  expect_match(cedar_semantic_caption(notes)[[1]], "intent")

  # Out of range: FRAD separates intent from admission from 202660, so the
  # annotation must stop rather than warn forever.
  expect_length(
    cedar_semantic_notes("cedar_programs", values = "RADS", terms = 202680L), 0L
  )
  # Different code, same table: not in scope.
  expect_length(
    cedar_semantic_notes("cedar_programs", values = "BIOL", terms = 202410L), 0L
  )
  expect_error(cedar_semantic_notes(NA_character_), "One table name is required")
})

test_that("registry entries carry what a reader and a maintainer both need", {
  for (entry in cedar_data_semantics()) {
    expect_true(nzchar(entry$id), info = entry$id)
    expect_true(entry$kind %in% c("semantic_break", "intent_coding", "join_hazard"),
                info = entry$id)
    expect_true(entry$effect %in% c("warn", "exclude"), info = entry$id)
    # Evidence is what makes an entry re-checkable rather than folklore.
    expect_true(nzchar(entry$evidence), info = entry$id)
    expect_true(nzchar(entry$summary), info = entry$id)
    expect_true(nzchar(entry$scope$table), info = entry$id)
  }
})

test_that("pre-majors mapped to their own code are flagged, declared ones are not", {
  found <- detect_pre_major_self_mapping(test_programs_hp)

  # FRAD, FMDL and XRAD each resolve to a department named after themselves.
  expect_setequal(found$major_code, c("FRAD", "FMDL", "XRAD"))
  # FNRS is a pre-major mapped correctly to NURS -- flagging it would make the
  # screen fire on every pre-major and train people to ignore it.
  expect_false("FNRS" %in% found$major_code)
  # RADS, NURS, MEDL and BIOL are DECLARED majors whose dept_code equals their
  # major code, which is legitimate: RADS really is the RADS department.
  expect_false(any(c("RADS", "NURS", "MEDL", "BIOL") %in% found$major_code))
  expect_match(found$details[[1]], "identity fallback")
  expect_true(all(found$review_status == "needs_review"))
})

test_that("no self-mapped pre-majors yields an empty report, not an error", {
  clean <- test_programs_hp %>% dplyr::filter(!is_pre_major)
  expect_equal(nrow(detect_pre_major_self_mapping(clean)), 0L)
  expect_error(
    detect_pre_major_self_mapping(dplyr::select(test_programs_hp, -is_pre_major)),
    "programs is missing: is_pre_major"
  )
})

# DA01 (local): three programs over 2024-2026, each with 50 majors a term.
#   SEL   50 undergrad majors,  5 grads/yr  -> ratio 10.0, flagged
#   NORM  50 undergrad majors, 25 grads/yr  -> ratio  2.0, not flagged
#   GRAD  45 GRADUATE + 5 undergrad majors, 5 baccalaureate grads/yr
#         -> ratio 1.0 when levels are paired; 10.0 if they are not.
anomaly_ratio_programs <- function() {
  terms <- c(202480L, 202580L, 202680L)
  build <- function(code, n, level) {
    tidyr::expand_grid(term = terms, i = seq_len(n)) %>%
      dplyr::transmute(
        student_id = paste0(code, "-", level, "-", i), term, major_code = code,
        program_name = code, is_pre_major = FALSE, program_type = "Major",
        student_level = level
      )
  }
  dplyr::bind_rows(
    build("SEL", 50L, "Undergraduate"),
    build("NORM", 50L, "Undergraduate"),
    build("GRAD", 45L, "Graduate"),
    build("GRAD", 5L, "Undergraduate")
  )
}

anomaly_ratio_degrees <- function() {
  terms <- c(202410L, 202510L, 202610L)
  build <- function(code, n) {
    tidyr::expand_grid(term = terms, i = seq_len(n)) %>%
      dplyr::transmute(
        student_id = paste0(code, "-grad-", term, "-", i), term, major_code = code,
        award_category = "Baccalaureate Degree"
      )
  }
  dplyr::bind_rows(build("SEL", 5L), build("NORM", 25L), build("GRAD", 5L))
}

test_that("a program whose majors far exceed its graduates is flagged", {
  found <- detect_selective_admission_signal(
    anomaly_ratio_programs(), anomaly_ratio_degrees(),
    opt = list(from_term = 202410L)
  )

  expect_equal(found$major_code, "SEL")
  expect_match(found$details, "ratio 10")
  expect_equal(found$severity, "info")
  # A screen produces candidates for review, never a verdict.
  expect_equal(found$review_status, "needs_review")
})

test_that("graduate majors are not counted against baccalaureate degrees", {
  # The regression guard. GRAD has 50 majors a term and 5 graduates a year, so
  # an unpaired comparison scores it 10.0 and flags it. Pairing the level with
  # the award category leaves 5 undergraduate majors against 5 graduates.
  # Special Education scored 13.4 and Physics 9.9 this way on real data.
  found <- detect_selective_admission_signal(
    anomaly_ratio_programs(), anomaly_ratio_degrees(),
    opt = list(from_term = 202410L, min_majors = 1)
  )

  expect_false("GRAD" %in% found$major_code)
  expect_false("NORM" %in% found$major_code)
})

test_that("the combined report runs both screens and fails loudly on bad input", {
  report <- build_data_anomaly_report(
    anomaly_ratio_programs() %>%
      dplyr::mutate(dept_code = major_code, is_pre_major = TRUE),
    anomaly_ratio_degrees(),
    opt = list(from_term = 202410L)
  )
  expect_true("pre_major_self_mapped_department" %in% report$issue_type)
  expect_error(
    detect_selective_admission_signal(
      anomaly_ratio_programs(),
      dplyr::select(anomaly_ratio_degrees(), -award_category)
    ),
    "degrees is missing: award_category"
  )
})
