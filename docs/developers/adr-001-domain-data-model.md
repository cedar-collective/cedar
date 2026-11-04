# ADR-001: Move CEDAR's tables from report-shaped to domain-shaped

- **Status:** Proposed. First written 2026-07-31; rewritten 2026-11-03 with the
  measurements below and a target architecture, after the app's growth began
  exposing the report-shaped tables (ISSUES.md I9, I15, I37, I44, I45).
- **Supersedes:** nothing yet. When step 3 below lands it supersedes
  [ADR-002](adr-002-explicit-mapping-files.md) Stages 3 and 3b (units and
  colleges stamped onto rows at transform time) with the same files read as
  dimensions. ADR-002's files, rules and pipeline contract stand.
- **Complements:** [source-to-cedar-manifest.md](source-to-cedar-manifest.md),
  [field-reliability.md](field-reliability.md), [right-edge-policy.md](right-edge-policy.md).

---

## Context

CEDAR's tables are 1:1 with UNM MyReports **reports**, not with domain
**entities**:

```
DESRs            → cedar_sections
class_lists      → cedar_students
academic_studies → cedar_programs
degrees          → cedar_degrees
hr_data          → cedar_faculty   (frozen; see manifest §5)
```

That is how the data arrives, and it was fine while the app was small. The
shape has four consequences, each now measured on the production tables
(shared-data, 2026-11-03 pull; `cedar_students` 1,855,577 rows).

### 1. The same fact is stored on several tables, each copy mapped separately

Of `cedar_students`' 32 columns, 11 describe the registration itself. Eight
describe the **student that term** (`student_level`, `student_classification`,
`major_code`, `major_name`, `student_college`, `student_campus`, `residency`,
`dual_credit`) and repeat on each of the student's ~4 course rows. Thirteen
describe the **section** (`subject_course`, `course_title`, `instructor_id`,
`instructor_name`, `campus`, `college`, `source_college`, `college_basis`,
`department`, `level`, `term_type`, `part_term`, `subject_code`) and repeat on
each of the section's ~17 students.

Of `cedar_programs`' 37 columns, 25 hold one value per student per term and
repeat on each of the student's program rows; five of them are the pull-stamped
fields the [field reliability contract](field-reliability.md) bans from
per-term claims. `gender` is constant per student.

| table | rows | distinct student-terms | memory | if thinned to its own grain |
|---|---|---|---|---|
| `cedar_students` | 1,855,577 | 465,836 | 468 MB | 347 MB without the student columns; ~190 MB without the section columns too |
| `cedar_programs` | 622,988 | 426,222 | 181 MB | — |
| `cedar_sections` | 253,707 | — | 100 MB | already at its grain (`job_cat` is 100% NA) |

A student-term table carrying the eight student columns is 53 MB.

### 2. The copies disagree, and nothing compares them

- **Course codes (I45).** The class list carries a renamed subject's new code
  back onto old terms; the DESR keeps the code the section was scheduled under.
  23,451 class-list rows (1.26%) name a different `subject_course` than their
  own section: SOC→SOCI and PSY→PSYC in 2019–2021, CCS→CCST in Fall 2025.
  SOCI 371 has 177 registered students on the Fall 2019 class list and no
  sections that term. Every other section attribute agrees 100% across the two
  tables.
- **Instructor IDs.** Both tables have `instructor_id`; the class list's is a
  32-character hash and the DESR's a 9-digit ID. Zero values match. Nothing
  joins on it yet; the first join will return nothing, silently.
- **Classification.** 111 student-terms carry two classifications on the class
  list, every one from rows pulled on two dates. ADR-001's first draft found
  116 adjacent-level disagreements between the class list and academic
  studies, all snapshot skew. **Which answer a reader gets depends on which
  table it reads.**
- **Vocabulary.** Before the source-to-CEDAR mapping was standardized,
  `student_level` held `UG` on one table and `Undergraduate` on the other,
  0% overlap, and a cross-table filter returned zero rows rather than erroring.

### 3. Every analysis re-derives the same facts, slightly differently

The transform builds `cedar_student_term_credits` (enrolled = registered) and
`cedar_next_term` (enrolled = registered or late-dropped) fifty lines apart;
Retention and Roadblocks then disagree by 284 students on who returned (I44).
Five other files decide for themselves what an enrolled student-term is.

The cost is runtime as well as consistency. On the production class list:

| work a cone repeats today | elapsed |
|---|---|
| per-student-term summary from raw rows | 3.8 s |
| rebuild the next-term lookup | 0.9 s |
| classify every row under the DFW policy | 1.9 s |
| **join a ready-made 53 MB student-term table onto all 1.86M rows** | **0.9 s** |
| the same, one term filtered first | 0.4 s |

Normalizing is cheap. Re-deriving is what is slow, and it is also where the
"joining variants" that complicate every new cone come from.

### 4. Mappings are applied at transform time, so an edit rebuilds four tables

ADR-002 Stage 3 stamps `subjects.csv` onto every class-list row and section
(`department`, `college`) and `programs.csv` onto every program and degree row
(`dept_code`, `college_code`). A one-line edit to a 263-line CSV rebuilds four
tables; each carries a provenance stamp so a deploy gate
(`scripts/rebuild-programs-if-mappings-changed.R`) can tell which is stale;
and the same unit fact lives in four places, each able to drift, which is how
I9 misclassified 23,272 rows. The gate and the stamps are machinery for a
problem the storage shape created.

---

## Decision

Restructure around domain entities in three layers. Facts record what the
source said; dimensions describe entities and come straight from the
institution's files; measures are computed once per pull under CEDAR's
canonical definitions. Cones read the layers; they never classify, dedupe, or
decide what "enrolled" means.

```
Pulls      — every extract as received, pull-dated, never overwritten
   │
Facts      — class list (student × section), declarations, degrees
             keys only: term, crn, student_id, subject_course, program code + college
   │  one join each
Dimensions — read from institution/<id>/, no transform step
             terms, courses, subjects, programs, units, colleges, campuses, people
   │
Measures   — built once per pull, canonical definitions
             student_terms, attempts, course_terms
```

### Facts: one row per event

| table | grain | replaces | notes |
|---|---|---|---|
| `cedar_registrations` (the class list) | student × section | `cedar_students` | grain unchanged: 1,855,577 rows, zero duplicate pairs |
| `cedar_declarations` | student × term × program slot | `cedar_programs` | major / second major / minor / concentration |
| `cedar_completions` | student × program × term | `cedar_degrees` | awards |

A fact keeps its registration columns (`registration_status_code`,
`registration_date`, `final_grade`, `credits`, `dual_credit`) and the keys
that reach its dimensions. **It keeps `campus`**, because the campus policy
groups on it in every course analytic and a section's campus never changes
after the fact. It drops the student-term and section descriptions.

### Dimensions: one row per entity, from the files

| table | grain | source | what moves here |
|---|---|---|---|
| `cedar_terms` | term | derived from the data once per load | season, academic year, next/previous regular term, start and census dates, and the four right edges as flags (`is_settled`, `is_graded`, `is_latest_enrolled`, `has_degrees`) |
| `cedar_courses` | course id | the DESR plus a renaming crosswalk | a **stable id** per course; the display code (`SOCI 371`) is an attribute with effective terms, so a renamed or renumbered course keeps one history (I37, I45) |
| `cedar_subjects` | subject × college × level | `subjects.csv` | subject → unit → college, read as a table instead of stamped |
| `cedar_program_catalog` | program code × college | `programs.csv` | program → unit, `is_pre_major`, `leads_to` |
| `cedar_units`, `cedar_colleges`, `cedar_campuses` | code | `units.csv`, `colleges.csv`, `campuses.csv` | names, home college, aliases |
| `cedar_student_terms` | student × term | class list and academic studies, with declared precedence | level, classification, campus, college, standing, residency, primary major, per-term credits and GPA: each stored once |
| `cedar_people` | student | academic studies | `gender`, `ipeds_race`, `first_gen`, and the **pull-stamped fields** (`inst_credits_*`, `overall_credits_*`, `inst_gpa`) labelled with their pull date, so no per-term table holds a field that is not per-term |

The vocabulary decision is made once, in one column of one dimension. The
mapping files **are** the dimension tables: an edit changes the next load and
rebuilds nothing. The provenance stamps, `CEDAR_MAPPED_TABLES` and the deploy
gate retire with the stamped columns.

### Measures: computed once, under the canonical definitions

| table | grain | promoted from | carries |
|---|---|---|---|
| `cedar_student_terms` (measure columns) | student × term | `cedar_student_term_credits` + `cedar_next_term` | `enrolled` (registered or late-dropped: census participation, as everywhere else in CEDAR), `returned_next_regular_term`, `return_observable` (from `cedar_terms`), DFW count, late withdrawals, credits entering/after, `timeline_valid` |
| `cedar_attempts` | student × course × term × campus | `cedar_grades` | one outcome per attempt from `classify_enrollment_outcomes()`, `cedar_outcome_policy_version` |
| `cedar_course_terms` | course × term × campus | `cedar_cl_enrls_base` | first-day, census and final enrollment, waitlist demand, DFW rate, fill |

These three already exist in partial, ad hoc form. The change is to declare
them the canonical source, give each one definition, and make cones read them.

### Snapshot vs. history

A registration is a point-in-time snapshot; the lifecycle is inferred from
the status code, not from dated transitions, because `registration_date` is
populated only from 2025-03-31 forward. An event-grained class list is still
not proposed. **But a pull that is not kept cannot be rebuilt**: Banner
overwrites a row's status date when a student drops, and a waitlisted student
who got a seat leaves no row. The registration and return snapshot files
(`output/registration-snapshots/`) are the current workaround. The Pulls
layer generalizes them: keep each extract, or a changes-only log of it, and
measure its size before deciding which.

---

## What this unlocks for other institutions

Today onboarding says *produce a MyReports class-list export*, which asks a
university to reproduce UNM's reporting quirks. Under this model it says *give
us registrations, declarations, completions, sections and the mapping files*:
concepts every SIS has. The MyReports extracts become one adapter among
several, and the manifest's §1–5 become an appendix of that adapter.

---

## Consequences

### Costs, stated plainly

- **Denormalization was not the mistake.** CEDAR's queries are mostly "filter
  registrations by student attributes", which today needs no join. The
  problem is that the denormalization was inherited from report shapes rather
  than chosen, so no copy was ever authoritative. The measured join cost
  (0.4–0.9 s on the full table) is below the cost of any one re-derivation.
- **Migration surface:** ~310 references across 26 files as of July 2026,
  160 of them `major_code`. One shared helper that attaches named student-term
  or unit columns to any rows makes each reader's change small.
- **Memory:** net saving on `cedar_students` of about 70 MB after step 2 and
  about 280 MB after step 5; the projection build already peaks near 3.2 of
  3.8 GiB.
- **Not needed yet:** a columnar engine (DuckDB, Arrow). Plain dplyr is fast
  enough at this size once the measures exist, and neither is in `renv.lock`.
  Revisit for a larger institution.

### Migration path: strangler, in this order

Each step is additive until its last sub-step, so the app runs throughout.

1. **`cedar_terms`.** Small; the right-edge policy becomes a join instead of
   a parameter every cone passes and checks.
2. **`cedar_student_terms`**, merging the two existing side tables with one
   definition of an enrolled term and `return_observable` from `cedar_terms`.
   Closes I44 (closed 2026-11-04: the app loads the table and Roadblocks
   and Retention read it; `cedar_next_term` is gone). Precedence when the
   two source snapshots disagree: the
   academic-studies row wins (it is the student-level report), the row is
   flagged and the count reported — never a silent coalesce. Measured on the
   first build: 5,442 of 373,169 student-terms described by both sources
   disagree, 4,210 of them in Fall 2025, pulled four months apart.
3. **Dimension reads for the mapping files**, through a shared
   `attach_unit()`; readers move as files are touched; then the stamped
   columns, provenance stamps and deploy gate go. Supersedes ADR-002 Stages 3
   and 3b.
4. **`cedar_courses` with a stable id and renaming crosswalk** (I37, I45),
   then `cedar_course_terms` promoted from `cedar_cl_enrls_base` and
   `cedar_attempts` from `cedar_grades`.
5. **Thin `cedar_students` and `cedar_programs`** to their keys and
   registration facts; rename to the fact names once no reader uses the old
   columns.

Pull history is the one piece with a deadline and should be sized now.

### Not doing this

Every new analysis keeps choosing its own "enrolled", its own next-term
lookup and its own unit column, and the disagreements stay invisible until
someone compares two pages. The deploy gate keeps rebuilding four tables per
CSV edit. The vocabulary splits recur the next time a report changes.

---

## Open questions

1. `cedar_registrations` vs `cedar_class_lists`: decide before step 5.
2. Pulls layer: full extracts or a changes-only log? Size it first.
3. Does the renaming crosswalk live in `institution/<id>/` as a mapping file
   (I37's proposal), or is it derived from DESR history where a CRN's code
   differs between tables (I45's evidence)? Probably both: derived candidates,
   confirmed in the file.
4. Which measure columns on `cedar_student_terms` need a campus variant
   (home campus is a dimension; delivery campus is on the attempt).
