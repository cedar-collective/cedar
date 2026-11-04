# `cedar_student_terms`: the contract

ADR-001 step 2. One row per student per term, built once in the transform,
holding every fact about a student in a term that CEDAR today re-derives from
raw class-list rows or reads off a repeated column. Written before the code;
the code is wrong where it departs from this page.

- **Status:** contract agreed 2026-11-03; **built the same day** (`R/branches/student-terms.R`, saved by the transform as `cedar_student_terms`). Not yet loaded by the app: the readers below move next, in order, and the two side tables retire with the last of them.
- **Closes:** ISSUES.md I44 (two definitions of "returned next term").
- **Depends on:** nothing new. ADR-001 step 1 (`cedar_terms`) would supply the
  next regular term and the settled edge; until it exists this table computes
  them the way the app does today (`add_next_term_col()`, `cedar_data_edges()`).
- **Replaces:** `cedar_student_term_credits` and `cedar_next_term`, which the
  transform builds fifty lines apart with two different definitions of an
  enrolled term.

---

## The one question it answers

*What was true of this student in this term, and did they come back?*

Everything on the row is either read from a source row for that student and
term, or counted from that student's class-list rows for that term, or looked
up in the next regular term. Nothing on it is a cumulative figure stamped at
pull time: the [field reliability contract](field-reliability.md) applies to
the table as a whole, and the banned fields (`inst_credits_*`,
`overall_credits_*`, `inst_gpa`) **never appear on it**. They move to the
per-student table in ADR-001 (`cedar_people`), labelled with their pull date.

## Grain and population

One row per `(student_id, term)` for every student who has **any class-list
row or any program declaration** in that term. So the table includes:

- students who only waitlisted or only dropped early (`enrolled = FALSE`,
  `class_list_rows > 0`), because the return watch needs to see them;
- students declared in a program with no class-list row that term
  (`enrolled = FALSE`, `class_list_rows = 0`, `declared = TRUE`), because a
  declared student who did not register is itself a signal.

It excludes nothing by level or campus. Readers filter.

Measured on the 2026-10-27 pull: 465,836 student-terms with a class-list row,
426,222 with a declaration; the union is the row count. At ~25 columns that is
roughly 60–80 MB, against the 53 MB of the eight student columns it lets
`cedar_students` drop later.

## Columns

Every column has one source and one definition. "Class list" means that
student's rows for that term in `cedar_students`; "programs" means their rows
in `cedar_programs`; "degrees" means `cedar_degrees`.

### Keys and provenance

| column | type | definition |
|---|---|---|
| `student_id` | chr | — |
| `term` | int | — |
| `classlist_as_of` | date | newest `as_of_date` among the class-list rows; `NA` when none |
| `programs_as_of` | date | newest `as_of_date` among the program rows; `NA` when none |
| `description_source` | chr | which source supplied the description columns: `"programs"`, `"class_list"`, or `"both_agree"` (see precedence) |
| `description_conflict` | lgl | the two sources both had the column and disagreed on at least one of level, classification or home campus |

### Description: who the student was that term

| column | type | source | definition |
|---|---|---|---|
| `student_level` | chr | programs, else class list | code vocabulary (`UG`, `GR`, …). The class list carries the code; academic studies carries a name (`Undergraduate`, `Graduate/GASM`), translated through `institution/<id>/student_levels.csv`. A name the file does not list is `NA` and the build reports it |
| `student_classification` | chr | programs, else class list | as Banner recorded it |
| `student_campus` | chr | programs, else class list | home campus code |
| `academic_standing` | chr | programs | as recorded; `NA` when no programs row |
| `residency` | chr | programs, else class list | |
| `time_status` | chr | programs | |
| `primary_major_code` | chr | programs | the **first `Major` row by `major_code`**, the rule the transform uses for a student's unit and college |
| `primary_dept_code` | chr | programs | that row's `dept_code`, as mapped by `programs.csv` (`NA` when the code has no confirmed row) |
| `primary_college_code` | chr | programs | that row's college, as mapped |
| `is_pre_major` | lgl | programs | the primary row's flag, from the file |
| `n_declarations` | int | programs | program rows that term (majors, minors, concentrations) |
| `declared` | lgl | programs | `n_declarations > 0` |

**Precedence when both sources carry a column.** The programs row wins. It is
the student-level report, and every measured disagreement (111 student-terms
on the class list, 116 across the two tables, all adjacent classifications)
came from rows pulled on different dates. When the two disagree the row says
so (`description_conflict = TRUE`) and the build logs the count; the Admin
data page shows it. A class list value fills in only where there is no
programs row. **No column is ever coalesced silently.**

### Enrollment: what they did that term

| column | type | definition |
|---|---|---|
| `class_list_rows` | int | all class-list rows, any status |
| `enrolled` | lgl | at least one row in `STATUS_REGISTERED` **or** `STATUS_DROP_LATE`: the student was enrolled at census. **This is CEDAR's one definition of an enrolled student-term.** Waitlists and early drops are not enrollment. |
| `registered_courses` | int | distinct `subject_course` with a `STATUS_REGISTERED` row (CAMPUS_ROLLUP: a curriculum count, one per course however delivered) |
| `late_withdrawals` | int | distinct `subject_course` whose only rows are `STATUS_DROP_LATE` |
| `early_drops` | int | distinct `subject_course` whose only rows are `STATUS_DROP_EARLY` |
| `waitlisted_only` | lgl | not `enrolled` and at least one `STATUS_WAITLIST` row |
| `attempted_unm_credits` | num | sum of `credits` over registered rows with a credit value; as `cedar_student_term_credits` defines it today |
| `completed_unm_credits` | num | the same over rows whose `final_grade` is in `passing_grades` |
| `dfw_grades` | int | registered rows (not late drops) whose `classify_enrollment_outcomes()` outcome is `dfw`; late drops are counted in `late_withdrawals`, never here |
| `graded_rows` | int | registered rows with a posted grade; `dfw_grades` is unknown, not zero, when this is 0 and `enrolled` is TRUE |
| `sem_gpa` | num | programs `sem_gpa` (a per-term field; passes both reliability tests). The one description academic studies repeats with two values in one pull — a program row duplicated with a 0.00 beside the real figure, 381 student-terms (0.09%) on the 2026-10-27 pull — so it is kept only where the rows agree, `NA` and counted where they do not |

### Position: where they were in their degree

Carried over from `build_credit_timeline()`, which this table then reads
from instead of from `cedar_student_term_credits`.

| column | type | definition |
|---|---|---|
| `cumulative_attempted_unm_credits` | num | running sum of `attempted_unm_credits` over the student's enrolled terms in the data |
| `unm_credits_entering` | num | the running sum before this term |
| `timeline_valid` | lgl | the student's first term in the data is after the data's first term, so the running sum started at zero for a reason. **Readers placing students on a credit axis filter on it and say how many they dropped.** |

Transfer credits stay in `build_credit_timeline()`'s per-student block, since
they are recovered from two banned fields and are per-student, not per-term.

### Return: did they come back

| column | type | definition |
|---|---|---|
| `next_regular_term` | int | `add_next_term_col(term, summer = FALSE)`: Spring→Fall, Fall→Spring, Summer→Fall |
| `returned_next_regular_term` | lgl | the student has an `enrolled = TRUE` row for `next_regular_term`. `NA` when `return_observable` is FALSE. |
| `return_observable` | lgl | `next_regular_term <= last_enrolled_complete` at build time (`cedar_data_edges()`) **and** `next_regular_term` has a class list. A term past the settled edge has registration still arriving, and a Fall or Spring with no pull inside the data's run has nobody in it to find, so in both cases the return is unknown, never FALSE. The build names any such gap term; `cedar_terms` carries it as a row with zero enrollment. |
| `degree_awarded` | lgl | a `cedar_degrees` row with `graduation_status == "Awarded"` for this student and term |

A graduate who does not return is not a non-returner. The table does not
decide that; it gives readers `degree_awarded` beside
`returned_next_regular_term` so each denominator can say what it did.

## Right edges

- Rows exist for every term in the data, including terms past the settled
  and graded edges: current registration is never hidden (AGENTS.md,
  right-edge policy).
- `return_observable` is the only edge the table applies itself. Grade-based
  columns (`dfw_grades`, `completed_unm_credits`, `sem_gpa`) are reported as
  the data has them; a reader comparing them across terms bounds at
  `last_graded`, as today.
- The build fails if `cedar_data_edges()` cannot determine
  `last_enrolled_complete`. No guess.

## Not on this table

- Delivery `campus`. A student's courses can span campuses in one term; the
  attempt is where delivery campus lives. Home campus is here.
- Anything from `cedar_sections` or `cedar_faculty`.
- The pull-stamped fields. Any pull request adding `inst_*` or `overall_*`
  to this table is wrong by definition.
- Demographics constant per student (`gender`, `ipeds_race`, `first_gen`,
  `pell_eligible`): per-student, so `cedar_people`. Until that exists, readers
  keep taking them from `cedar_programs`.

## Readers it replaces, and the order to move them

Each move is one PR, with the page's numbers compared before and after and
any change stated in the PR body.

| reader | today | after |
|---|---|---|
| `build_next_term_lookup()` (`R/cones/stopout.R`) and the saved `cedar_next_term` | own lookup, registered or late drop | read `returned_next_regular_term`; delete both. Numbers unchanged. |
| `.build_registered_lookup()` (`R/branches/retention-context.R`) | registered only | read `enrolled`. **Retention moves by about one point** (284 students, Fall 2025→Spring 2026); the Retention methodology panel and `definitions.yml` say so. Closes I44. |
| `build_credit_timeline()` input | `cedar_student_term_credits` | this table; `cedar_student_term_credits` retires |
| `build_return_snapshot()` anchor population and warning signs | own group-by over class-list rows | filter `enrolled`, read `late_withdrawals`, `dfw_grades`, `graded_rows`, the description columns |
| `population.R` enrollment-based switch detection, `course-flows.R`, `gen-ed-conversion.R`, `major-changes.R`, `course-instructor-effect.R` | each filters status codes itself | read `enrolled`; each is checked against its old output and any difference is reported before merging |
| `cedar_students` readers of the eight student columns | repeated column | join on `(student_id, term)` through a shared `attach_student_term(rows, cols)` helper; `cedar_students` keeps the columns until the last reader has moved (ADR-001 step 5) |

## Designed fixture: ST01

One scenario in `designed_test_data.R`, exposed as `test_students_st`,
`test_programs_st`, `test_degrees_st`, over the stable terms
202010 / 202060 / 202080 / 202110, with pinned counts in the file header.
Each student exists to make exactly one rule fail if it is broken:

| student | rows | the rule it guards |
|---|---|---|
| ST_A | registered 202010; only a `DW` row in 202080 | `enrolled` TRUE in 202080; `returned_next_regular_term` TRUE for 202010. **The I44 case.** Reintroducing registered-only makes it FALSE. |
| ST_B | registered 202010; only a `DR` row in 202080 | `enrolled` FALSE in 202080, row still present; returned FALSE |
| ST_C | registered 202010; only `WL` in 202080 | `waitlisted_only` TRUE; returned FALSE |
| ST_D | registered 202010 and 202060 only | Summer skipped: `next_regular_term` of 202010 is 202080; returned FALSE despite the summer row |
| ST_E | registered 202010; declaration in 202080, no class list | row for 202080 with `declared` TRUE, `enrolled` FALSE, `class_list_rows` 0 |
| ST_F | two class-list rows in 202010 pulled on two dates with different classifications (the older pull is ignored); programs row disagrees with the newer | `description_source = "programs"`, `description_conflict` TRUE; precedence picks the programs value |
| ST_G | registered 202010 with a `Major` row and a `Minor` row; two majors with codes `BB` and `AA` | `primary_major_code = "AA"` (first by code), `n_declarations` 3 |
| ST_H | registered 202010 with grades `A`, `C-`, and one `DW` row | `dfw_grades` 1 (the C-), `late_withdrawals` 1, `graded_rows` 2; counting the DW as a DFW grade makes it 2 |
| ST_I | registered in 202110 only (the last term) | `return_observable` FALSE, `returned_next_regular_term` NA |
| ST_J | registered 202010 with an Awarded degree in 202010; nothing after | `degree_awarded` TRUE, returned FALSE |
| ST_K | registered 202010 and 202080, no programs rows | description from the class list, `description_source = "class_list"`, `declared` FALSE |

The test file `test-student-terms.R` pins every column for every student,
and the mutation check in its header records that each of these breaks the
named assertion: registered-only enrollment (ST_A), DW counted as a DFW grade
(ST_H), every Major row counted (ST_G), class list winning precedence (ST_F),
summer as a return term (ST_D), and returned FALSE past the edge (ST_I).

## Measured on the first build (2026-10-27 pull)

518,889 student-terms: 452,021 enrolled, 53,053 declared without a class list, 92,667 described by the class list alone (no programs row), 373,169 by both, 5,442 of those disagreeing — 4,210 in Fall 2025, whose programs were pulled 2025-11-06 and whose class list 2026-03-07. 126 MB in memory, 126 s to build. Every one of the 443,458 `cedar_student_term_credits` rows matches on attempted and cumulative credits; every one of the 422,847 observable `cedar_next_term` rows agrees on the return. I44 reproduced from the table: Fall 2025 → Spring 2026 returned 82.72%, Spring → Fall 2025 71.92%. Home campus `student_campus` is one of the five campuses.csv codes on every row but one (a class-list `NA`); level resolves on every row but one (class-list code `00`).

## Done when

- `transform_to_cedar()` writes `cedar_student_terms.qs`, with the
  validator `validate_student_terms()` rejecting a duplicate key, an
  `enrolled` row with `class_list_rows = 0`, a `returned_next_regular_term`
  that is not `NA` where `return_observable` is FALSE, and any banned column.
- `global.R` loads it; `cedar_student_term_credits` and `cedar_next_term`
  are no longer written or loaded.
- The first two readers in the table above have moved and the Retention
  change is stated on the page and in `definitions.yml`.
- ST01 is in the fixture with its mutation checks recorded; `./run-tests.sh`
  passes.
- `data-model.md` documents the table; AGENTS.md's table list names it and
  this page; `layer-inventory.md` names `attach_student_term()`.
- A real-data check in the PR body: row count, the `description_conflict`
  count, and the I44 figures reproduced from the new column.
