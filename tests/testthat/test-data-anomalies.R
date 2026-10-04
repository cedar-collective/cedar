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

test_that("a pre-major code that is also a real department says so", {
  # FCS is pre-Computer Science AND the Family and Child Studies department.
  # Telling someone to "map the code" there is useless advice: it already
  # resolves, to the wrong one of its two meanings.
  plain <- detect_pre_major_self_mapping(test_programs_hp)
  expect_false(any(grepl("namespace collision", plain$details)))

  collision <- detect_pre_major_self_mapping(
    test_programs_hp, known_departments = c("FRAD", "NURS")
  )
  frad <- collision$details[collision$major_code == "FRAD"]
  expect_match(frad, "namespace collision")
  expect_match(frad, "major_college_to_dept")
  # A flagged code that is NOT a department keeps the ordinary advice.
  expect_false(grepl("namespace collision",
                     collision$details[collision$major_code == "FMDL"]))
})

test_that("no self-mapped pre-majors yields an empty report, not an error", {
  clean <- test_programs_hp %>% dplyr::filter(!is_pre_major)
  expect_equal(nrow(detect_pre_major_self_mapping(clean)), 0L)
  expect_error(
    detect_pre_major_self_mapping(dplyr::select(test_programs_hp, -is_pre_major)),
    "programs is missing: is_pre_major"
  )
})

# Admin > Mappings combines startup exclusions with the runtime screens. It used
# to swallow a screen error and show only the startup rows, so a broken screen
# read as "no mapping issues".
test_that("the Admin mapping panel combines startup issues with every screen", {
  startup <- tibble::tibble(
    issue_type = "unmapped_program_code", severity = "info",
    review_status = "reviewed_exception", program_code = "BA-TEST-AS",
    major_code = "TEST", college_code = "AS", dept_code = NA_character_,
    degree_level = "Undergraduate", program_type = "degree",
    details = "startup row"
  )
  issues <- build_admin_mapping_issues(startup, test_programs_hp,
                                       known_departments = c("NURS", "RADS", "MEDL", "BIOL"))
  expect_true("BA-TEST-AS" %in% issues$program_code)
  expect_setequal(
    issues$major_code[issues$issue_type == "pre_major_self_mapped_department"],
    c("FRAD", "FMDL", "XRAD")
  )
})

test_that("the Admin mapping panel fails loudly instead of hiding a broken screen", {
  broken <- dplyr::select(test_programs_hp, -is_pre_major)
  expect_error(build_admin_mapping_issues(NULL, broken, c("NURS")),
               "programs is missing: is_pre_major")
  expect_error(build_admin_mapping_issues(NULL, test_programs_hp, NULL),
               "known_departments is required")
  # No programs loaded is a state, not a failure: startup issues still show.
  expect_equal(nrow(build_admin_mapping_issues(NULL, NULL, NULL)), 0L)
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

test_that("identity-fallback departments are flagged, real ones are not", {
  programs <- test_programs_hp
  # RADS and MEDL are real departments; BIOL is too. FRAD/FMDL/XRAD are
  # pre-majors and belong to the other screen, not this one.
  found <- detect_identity_fallback_departments(
    programs, known_departments = c("RADS", "MEDL", "NURS", "BIOL")
  )
  expect_equal(nrow(found), 0L)

  # A declared program whose department does not exist: the identity fallback.
  invented <- programs %>%
    dplyr::mutate(
      major_code = dplyr::if_else(major_code == "BIOL", "ZZZZ", major_code),
      dept_code = dplyr::if_else(dept_code == "BIOL", "ZZZZ", dept_code),
      program_name = dplyr::if_else(program_name == "Biology", "Invented", program_name)
    )
  flagged <- detect_identity_fallback_departments(
    invented, known_departments = c("RADS", "MEDL", "NURS", "BIOL")
  )
  expect_equal(flagged$major_code, "ZZZZ")
  expect_match(flagged$details, "does not exist")

  # A code that legitimately has no department is not a failure and must not be
  # reported forever -- a page that cries wolf on its largest entries is ignored.
  expect_equal(
    nrow(detect_identity_fallback_departments(
      invented, known_departments = c("RADS", "MEDL", "NURS", "BIOL"),
      department_less = "ZZZZ"
    )),
    0L
  )
})

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


test_that("a population picks up the annotations that apply to its programs", {
  # HP01 carries RADS students at 202110, inside the entry's bounds, and BIOL
  # students who must pick up nothing.
  rads_pop <- tibble::tibble(
    student_id = c("HP_RADS_1", "HP_RADS_2", "HP_FRAD_1")
  )
  notes <- population_data_notes(
    rads_pop, test_programs_hp, list(program_names = "Radiologic Sciences")
  )
  expect_equal(
    vapply(notes, function(n) n$id, character(1)),
    "rads-major-code-records-intent"
  )

  biol_pop <- tibble::tibble(student_id = c("HP_BIOL_1", "HP_BIOL_2"))
  expect_length(
    population_data_notes(biol_pop, test_programs_hp, list(program_names = "Biology")),
    0L
  )

  # An empty population annotates nothing rather than erroring.
  expect_length(
    population_data_notes(rads_pop[0, ], test_programs_hp, list()), 0L
  )
  expect_error(
    population_data_notes(rads_pop, dplyr::select(test_programs_hp, -term), list()),
    "programs is missing: term"
  )
})

test_that("an annotation stops applying once its term bound passes", {
  # The same students, moved past the bound at which FRAD begins separating
  # intent from admission. A caveat that warned forever would become noise.
  after <- test_programs_hp %>% dplyr::mutate(term = 202680L)
  expect_length(
    population_data_notes(
      tibble::tibble(student_id = c("HP_RADS_1", "HP_RADS_2")),
      after, list(program_names = "Radiologic Sciences")
    ),
    0L
  )
})

# ── Mapping audit (ADR-002): every value the mapping files do not cover ───────
# Scaffolding: mapping files for the designed fixture's synthetic institution,
# with one deliberate gap of each kind. BIOL has no subject row; section college
# AS and Translated College EDU name no college; ENGL-BA and FSEC-BS have no
# program row; PSYC has no home college. POLS-BA and BUSA-BBA are mapped to a
# college Banner's Translated College disagrees with -- BUSA-BBA's pre-major
# rows are the expected kind of difference, its others need review.
audit_files <- function() {
  prog <- function(code, unit, pre = "FALSE") data.frame(
    program_code = code, in_college = "", program_name = code, unit_code = unit,
    college_code = "", is_pre_major = pre, leads_to = "", basis = "decided",
    status = "confirmed", evidence = "", notes = "")
  list(
    colleges = data.frame(college_code = c("ARTS", "SOSC", "STEM", "NURS", "BUS"),
                          college_name = c("Arts", "Social Science", "STEM", "Nursing", "Business"),
                          source_names = ""),
    units = data.frame(unit_code = c("ANTH", "HIST", "MATH", "NURS", "BUSN", "PSYC"),
                       unit_name = "", college_code = c("SOSC", "ARTS", "STEM", "NURS", "BUS", ""),
                       kind = "department", notes = ""),
    subjects = data.frame(subject_code = c("ANTH", "HIST", "MATH", "NURS"),
                          in_college = c("SOSC", "ARTS", "STEM", "NURS"), in_level = "",
                          college_code = "",
                          unit_code = c("ANTH", "HIST", "MATH", "NURS"),
                          status = "confirmed", evidence = "", notes = ""),
    programs = rbind(
      prog(c("ANTH-BA", "ANTH"), "ANTH"), prog(c("HIST-BA", "HIST-MA", "HIST"), "HIST"),
      prog(c("MATH-BS", "BIOL-BS", "MATH"), "MATH"), prog("NURS-BS", "NURS"),
      prog(c("POLS-BA", "PSYC-MIN"), "HIST"),
      prog("BUSA-BBA", "MATH"), prog(c("ACCT-BBA", "BUAN-BBA", "BUMG-BBA", "FINC-BBA"), "BUSN")),
    settings = data.frame(setting = c("mapping_files_url", "source_files_url"),
                          value = c("https://github.com/org/repo/blob/main/institution/x",
                                    "https://github.com/org/repo/blob/main"))
  )
}

test_that("the mapping audit lists each kind of unmapped value, and college disagreements", {
  audit <- audit_mapping_coverage(audit_files(), sections = test_sections, students = test_students,
                                  programs = test_programs, degrees = test_degrees)
  got <- audit %>% dplyr::arrange(kind, value, status) %>%
    dplyr::select(kind, value, status, rows) %>% as.data.frame()
  attr(got, "checked") <- NULL
  expect_equal(got, data.frame(
    kind   = c("college_disagreement", "college_disagreement", "college_disagreement",
               "program_code", "program_code", "section_college", "source_college",
               "subject", "unit_college"),
    value  = c("BUSA-BBA", "BUSA-BBA", "POLS-BA", "ENGL-BA", "FSEC-BS", "AS", "EDU", "BIOL", "PSYC"),
    status = c("expected", "review", "review", "unmapped", "unmapped", "unmapped", "unmapped",
               "unmapped", "unmapped"),
    rows   = c(1L, 3L, 4L, 2L, 1L, 17L, 1L, 2L, NA)))
  expect_setequal(attr(audit, "checked"),
                  c("subject", "section_college", "program_code", "source_college",
                    "college_disagreement", "degree_program_code", "degree_college", "unit_college"))
  # Where to fix each: POLS-BA's programs.csv row is line 11; PSYC is units.csv
  # line 7; a value with no row points at the file, with no line.
  where <- audit %>% dplyr::filter(value %in% c("POLS-BA", "PSYC", "BIOL"))
  expect_equal(where$file[order(where$value)], c("subjects", "programs", "units"))
  expect_equal(where$line[order(where$value)], c(NA, 11L, 7L))
  # And what to supply, in words.
  expect_equal(where$needs[order(where$value)],
               c("A subjects.csv row: unit and college",
                 "A decision: confirm, or set the program's college_code",
                 "A home college for the unit"))
  expect_equal(unique(audit$needs[audit$status == "expected"]), "Nothing: an expected difference")
  expect_match(summarize_mapping_audit(audit), "^Mapping audit: 6 unmapped value\\(s\\), 2 mapped")
})

test_that("a subject proposed in subjects.csv is still unmapped, and says where", {
  files <- audit_files()
  files$subjects <- rbind(files$subjects, data.frame(
    subject_code = "BIOL", in_college = "STEM", in_level = "", unit_code = "MATH",
    college_code = "", status = "proposed", evidence = "", notes = ""))
  biol <- audit_mapping_coverage(files, students = test_students) %>% dplyr::filter(value == "BIOL")
  expect_equal(biol$status, "unmapped")
  expect_match(biol$context, "proposed in subjects.csv")
  expect_equal(biol$needs, "Confirm the proposed unit, MATH, or replace it")
  expect_equal(biol$line, 6L)
})

test_that("the mapping audit checks only the tables it is given, and says so", {
  audit <- audit_mapping_coverage(audit_files(), sections = test_sections)
  expect_setequal(attr(audit, "checked"), c("subject", "section_college", "unit_college"))
  # With no course table, the other kinds still say what they need.
  only_programs <- audit_mapping_coverage(audit_files(), programs = test_programs)
  expect_false(anyNA(only_programs$needs))
  expect_error(audit_mapping_coverage(audit_files(), programs = dplyr::select(test_programs, -student_college)),
               "cedar_programs lacks student_college")
})
