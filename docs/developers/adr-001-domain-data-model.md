# ADR-001: Move CEDAR's tables from report-shaped to domain-shaped

- **Status:** Proposed. First written 2026-07-31; rewritten 2026-11-03 with the
  measurements below and a target architecture, after the app's growth began
  exposing the report-shaped tables (ISSUES.md I9, I15, I37, I44, I45).
  Amended 2026-11-05: step 2 closed, and step 3 written out in full
  ([below](#step-3-in-full-dimensions-and-how-data-reaches-a-cone)), with the
  convention for how tables reach a cone. Revised 2026-11-06 after review:
  the default unit is attached once at load, not joined by every reader, and
  step 4 follows in the same order it did, no longer behind a reader
  migration.
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

The transform built `cedar_student_term_credits` (enrolled = registered) and
`cedar_next_term` (enrolled = registered or late-dropped) fifty lines apart (both retired 2026-11-04);
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

*(As it stood until step 3, 2026-11-06.)* ADR-002 Stage 3 stamped
`subjects.csv` onto every class-list row and section (`department`, `college`)
and `programs.csv` onto every program and degree row (`dept_code`,
`college_code`). A one-line edit to a 263-line CSV rebuilt four tables; each
carried a provenance stamp so a deploy gate
(`scripts/rebuild-programs-if-mappings-changed.R`) could tell which was stale;
and the same unit fact lived in four places, each able to drift, which is how
I9 misclassified 23,272 rows. The gate and the stamps were machinery for a
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
| `cedar_courses` | course id | the sections, the class lists and `code_history.csv` | a **stable id** per course: the last code of its confirmed succession chain, so a renamed or renumbered course keeps one history (I37, I45); the codes it has carried are `cedar_course_codes`. Built 2026-11-06 (step 4, PR 1); written out [below](#step-4-in-full-the-course-dimension-and-what-follows-it) |
| `cedar_subjects` | subject × college × level | `subjects.csv` | subject → unit → college, read as a table instead of stamped |
| `cedar_program_catalog` | program code × college | `programs.csv` | program → unit, `is_pre_major`, `leads_to` |
| `cedar_units`, `cedar_colleges`, `cedar_campuses` | code | `units.csv`, `colleges.csv`, `campuses.csv` | names, home college, aliases |
| `cedar_student_terms` | student × term | class list and academic studies, with declared precedence | level, classification, campus, college, standing, residency, primary major, per-term credits and GPA: each stored once |
| `cedar_people` | student | academic studies | `gender`, `ipeds_race`, `first_gen`, and the **pull-stamped fields** (`inst_credits_*`, `overall_credits_*`, `inst_gpa`) labelled with their pull date, so no per-term table holds a field that is not per-term |

The vocabulary decision is made once, in one column of one dimension. The
mapping files **are** the dimension tables: an edit changes the next load and
rebuilds nothing. The provenance stamps, `CEDAR_MAPPED_TABLES` and the deploy
gate's mapping branch retired with the stamped columns (step 3, 2026-11-06).

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
   **Done 2026-11-04.** Every reader that groups, labels or places a student
   by a description column reads the table (the per-reader measurements are
   in [student-terms.md](student-terms.md)). Three reads of the class-list
   copies remain, each assigned elsewhere: `filter_class_list()`'s
   `classification`, `major`, `student_campus` and `student_college` keys
   and Regstats' sophomore screen join the table in step 5, when the columns
   go (until then a late-pulled term's classification filter selects the
   wrong students, ISSUES.md I47); `course-flows.R` carries
   `student_classification` into the `cedar_course_flows` precompute and
   moves with step 4, which rebuilds that precompute; the enrollment
   projection inputs read `major_code` and `student_classification` as model
   inputs, so that change is a `model_version` decision, not a data-model
   chore.
3. **Dimensions from the mapping files**, loaded as one `dims` object by one
   shared loader, which attaches the default unit columns to the fact tables
   once at load through `attach_unit()`; the transform then stops stamping
   them, and the provenance stamps and deploy gate go. No reader changes.
   Supersedes ADR-002 Stages 3 and 3b. Written out in full
   [below](#step-3-in-full-dimensions-and-how-data-reaches-a-cone).
4. **`cedar_courses` with a stable id and renaming crosswalk** (I37, I45),
   then `cedar_course_terms` promoted from `cedar_cl_enrls_base` and
   `cedar_attempts` from `cedar_grades`. **PR 1 done 2026-11-06:** the
   dimension and `course_id` at load, no reader changed. Written out
   [below](#step-4-in-full-the-course-dimension-and-what-follows-it).
5. **Thin `cedar_students` and `cedar_programs`** to their keys and
   registration facts; rename to the fact names once no reader uses the old
   columns.

Pull history is the one piece with a deadline and should be sized now.

### Step 3 in full: dimensions, and how data reaches a cone

Decided 2026-11-05, before any code; revised 2026-11-06 after review. Three
questions were open: whether the unit join runs once at load or where it is
read; whether a reader may choose a hierarchy other than the subject's unit;
and whether "every table a cone needs is a parameter" survives a model with
twelve tables. The answers below are one design.

**The mapping files are the dimension tables, and the default unit is
attached once at load.** On disk, fact tables keep keys only: a class-list
row its subject, section college and level; a section the same; a program or
degree row its program code and college. The mapping files load as dimension
tables beside `cedar_terms`: `subjects` (subject × college × level → unit),
`programs` (code × college → unit, `is_pre_major`, `leads_to`), `units`,
`colleges` and `campuses` (names, home college, aliases). The shared loader
then attaches the default unit and college columns to every fact table, under
the names every reader has always read (`department` and `college` on
sections and class-list rows, `dept_code` and `college_code` on programs and
degrees, `primary_dept_code` and `primary_college_code` on student-terms), so
the in-memory tables look as they do today and **no reader changes**. A
mapping edit changes the next start and rebuilds nothing.

The alternative, the star schema proper, where every reader joins the
dimension it needs and a cone or branch may not read a unit column off a fact
table, was the 2026-11-05 design and was rejected on 2026-11-06. Measured on
that day: 15 of 26 cones, 28 of 40 branches, 10 of 18 features and 13 of 16
modules read a unit column, almost all as `filter(department == ...)` or
`group_by(term, campus, college, department, ...)`. The end state would have
turned that one-column read into a mandatory join step in 66 files, moved no
number, and cost a migration six times the size of step 2 — and every future
cone would carry the step. CEDAR's queries are mostly "filter registrations
by a student or section attribute", which should need no join. The concern
that had argued for the star schema, that a reader could not tell from a
column's name which rule produced it (how I7 and I9 stayed invisible), is
answered by a naming rule, not by removing the column: I7 and I9 came from a
self-named fallback and a drifted duplicate list, both already gone under
ADR-002.

**The naming rule.** `department`, `college`, `dept_code` and `college_code`
always mean the default hierarchy: the subject's unit on a section or
class-list row, the program's unit on a declaration or degree. Any other
hierarchy a reader wants (a course under its instructor's unit, a Gen Ed
course under its awarding college, a student under their primary major's
college) is attached by `attach_unit()` under its own column name, never
written into the default columns. A reader that sees `department` knows the
rule; a reader that sees `instructor_unit` knows the other one.

**How data reaches a cone: facts explicit, `dims` as one object, `opt`
last.** The rule that every table a cone needs is a parameter stays, for the
reasons it was made: a cone is testable against a fixture, runnable in
RStudio against any table, and says what it depends on. A cone names the one
or two **fact** tables that are its actual input. A cone that needs a
dimension by name (a unit's display name, a college's home, a non-default
hierarchy) takes a single **`dims`** argument holding every dimension table,
rather than five of them threaded through its signature. Most cones need
neither: they read the attached column. `dims` is built once by one shared
loader that every entry point calls (`global.R`, the two cache-warming
scripts, `cedar-repl.R` and the scripts that source it, `dev/demo-data.R`,
the projection build and the snapshot scripts), carries a class, is validated
there, and absorbs `cedar_lookups`, which is already this object in all but
name; the transform stopped writing `cedar_lookups` on 2026-11-06. Features keep
taking `data_objects`; they are orchestrators. The M12 architecture test
keeps forbidding global reads. A single data bag for cones (`cone(data, opt)`)
was rejected: it hides the dependency the rule exists to show, and a test has
to assemble everything to run anything.

**How a unit is attached: one function, with the hierarchy as an argument.**
`attach_unit(rows, dims, hierarchy)` is the only code that resolves a unit.
It wraps `resolve_course_units()` and `resolve_program_units()`, which
already hold the two default rules in `R/lists/institution_files.R`; it does
not reimplement them. `hierarchy` names the rule (`"subject"`; `"program"`
for declarations and degrees; others as readers need them). A row the files
do not cover gets `NA` and a `unit_basis`, never a unit named after itself
(the rule EC-14 guards). The invariant `test-architecture.R` enforces is the
one that actually prevents I9: **no code outside `attach_unit()` and the
lists layer resolves a unit** — no call to the resolve functions, no read of
`subj_dept_map` or the mapping files, in a cone, branch, feature or module.
Reading the dimension tables at load is what makes an institution's mapping
work "edit a CSV and restart", and makes an adopter whose units are keyed on
something other than subject a new hierarchy in one function.

**How we get there: two code PRs and a small third, numbers compared on real
data at each.**

1. **The loader and `dims`.** One function every entry point calls reads the
   mapping files into `dims`, drops any stamped unit column it finds on a
   fact table, and attaches the default columns through `attach_unit()`.
   The transform still stamps at this point, so the before-and-after
   comparison must be identical to the row (same resolve functions, same
   files); the join time and the peak memory of dropping and re-attaching
   columns on 1.86M rows are measured here, against the projection build's
   ceiling. The ADR's own measurement of the join is 0.4–0.9 s on the full
   class list.
   **Done 2026-11-06** (`R/branches/dims.R`; `global.R`, both cache-warming
   scripts and `cedar-repl.R` call it). Measured on the 2026-10-08 pull in
   shared-data, host R: every stamped value reproduced on all four tables.

   | table | rows | attach | transient memory over the table |
   |---|---|---|---|
   | `cedar_sections` | 242,413 | 0.20 s | 63 MB over 100 MB |
   | `cedar_students` | 1,853,633 | 1.21 s | 340 MB over 484 MB |
   | `cedar_programs` | 622,385 | 1.2–1.8 s | 436 MB over 232 MB |
   | `cedar_degrees` | 75,272 | 0.05 s | 67 MB over 57 MB |

   The transient is freed once the table is attached, before any analysis
   allocates, so the projection build's peak (3.2 of 3.8 GiB, reached in its
   own working copies) is not raised. One rule was found only by this
   comparison: a declaration row's `program_college` is the files' answer
   alone (NA for an undecided code); the Banner fallback belongs to the
   student's `college_code`, never the program's. 3,981 rows said so.
2. **The transform stops stamping.** `cedar_students`, `cedar_sections`,
   `cedar_programs` and `cedar_degrees` are written with keys only;
   `cedar_student_terms` stores `primary_major_code` and the college key its
   resolution uses, and the loader attaches `primary_dept_code` and
   `primary_college_code` the same way, so a mapping edit no longer rebuilds
   it either. The provenance stamps, `CEDAR_MAPPED_TABLES` and
   `scripts/rebuild-programs-if-mappings-changed.R`'s mapping branch go (its
   student-terms branch stays until step 5). AGENTS.md's "every stored unit
   comes from the mapping files" paragraph is rewritten to "every unit is
   attached at load". Because the loader already drops any stamped column, a
   file written by either transform loads the same way, and the deploy needs
   no startup sequencing of the kind I46 was about.
   **Done 2026-11-06.** The transform writes `source_college` on sections
   and class-list rows, `source_college` / `source_college_code` on programs
   and `source_student_college` / `source_college` on degrees, and nothing
   else about a unit. `cedar_student_terms`
   stores `primary_source_college_code` / `primary_source_college` beside
   `primary_major_code`; `attach_student_term_units()` resolves the three
   attached columns, and `attach_section_units()` derives
   `crosslist_external` / `crosslist_partners` from the attached department.
   `R/branches/mapping-provenance.R` and `CEDAR_MAPPED_TABLES` are gone; the
   gate is `build_student_terms_if_stale()` and nothing else. Measured on the
   2026-10-08 pull: the new builder rebuilds the saved table's 518,894
   student-terms (136.6 s) and, attached (0.39 s, 368 MB transient over a
   136 MB table), `primary_major_code`, `primary_dept_code`,
   `primary_college_code` and `is_pre_major` match the stamped values on
   every row (14,086 under a Banner college, 451,940 mapped, 52,868 none).
3. **`dims` absorbs `cedar_lookups`.** The lookups the transform builds from
   the files (`dept_lookup`, `dept_name_lookup`, `college_code_to_name`,
   `subject_lookup`) are read off `dims`; the ones it builds from the data
   (`program_name_lookup`) move to a measure or stay a small saved table.
   Readers that take a `lookups` parameter take `dims`.
   **Done 2026-11-06.** `unit_names(dims)`, `college_code_names(dims)` and
   `subject_units(dims)` (`R/branches/dims.R`) replace `dept_name_lookup`,
   `college_code_to_name` and `subject_lookup`; `headcount_program_names(programs)`
   counts the modal unit per program name where `program_name_lookup` stored
   it; `dept_lookup` had no reader. The transform's `build_lookups()` writes
   `major_code_to_name` alone, the class lists' Major Code beside its name,
   which no file knows, and runs when the students do. `dept_code_to_name`
   (`R/lists/catalog_lookups.R`) names every unit in units.csv, no longer
   only those teaching a subject, and `global.R` no longer overrides it from
   the saved file. Headcount (`get_headcount()`, the module), Dept Trends'
   headcount panel, the Pathways focal-subject helper and the department
   choice lists take `dims`. Dept Trends' cache keys hash `cedar_dims` for
   every tab that labels a unit.
   **`cedar_lookups` retired 2026-11-06.** Its last table, `major_code_to_name`,
   named the codes only a class list carries. Those 49 codes (6,362 class-list
   rows, 0.34%) are now proposed rows in programs.csv, named from the class
   list, so `name_program_codes(codes, dims)` names every code the data
   carries from the file alone, and the Gen Ed major mix, Dept Trends' SCH by
   major and the Dept Dashboard's donuts show one name per code. The mapping
   audit reads the class lists' major codes too (`class_list_program_code`),
   so a new class-list-only code is listed the day it arrives, with the
   roster's name as context. Measured before the switch: 459 of 469 codes
   named identically; the file's spelling wins on the rest.
   Measured on the 2026-10-08 pull before the change: every one of the saved
   `subject_lookup`'s 214 subjects is among subjects.csv's rows (25 of them
   with a second row differing only by college, which `subject_units()`
   keeps); 162 of the 163 saved unit names are units.csv's verbatim and all
   17 college names match colleges.csv; `program_name_lookup`'s 501 names
   are reproduced by `headcount_program_names()` from the loaded table.

**Cost, stated plainly.** Three PRs, no reader migration, and no number
should move. The cost is startup time and a transient copy of the largest
table, both measured in the first PR. Step 4 then follows directly, and that
is where a new cone gains something to reuse: `cedar_course_terms` and
`cedar_attempts` are what let it filter a measure table and join rather than
re-derive from 1.86M rows.

### Step 4 in full: the course dimension, and what follows it

**Decided 2026-11-06, with the first PR.** Step 3 gave every row its unit
from the files at load. Step 4 does the same for the course: every section
and class-list row gets a `course_id` at load, from the files, and the code
the registrar used that term stays beside it.

**The problem, measured on the 2026-10-08 pull** (terms Fall 2018 to Fall
2026). The data carries 7,641 distinct `subject_course` codes: 7,573 on the
schedule, 6,598 on class lists, 68 on class lists only (61 CCST, 4 SOCI, 3
PSYC). Those 68 are I45: Banner applies a subject's rename to old class lists
and not to old schedules, so 1,355 `(term, crn)` sections carry two codes, 180
distinct pairs, every one a same-number rename (CCS → CCST on 524 sections,
PSY → PSYC on 611, SOC → SOCI on 220). CCS persists on the schedule to Fall
2026 beside CCST, which began Fall 2019. Across terms the same gap is I37:
the Fall 2019 common course numbering and the Fall 2026 Anderson and
Population Health renumberings each started every affected course's history
over. 36 R files group on `subject_course`; each one sees the old course die
and the new one arrive from nowhere.

**The decision.**

- **One file records successions: `institution/<id>/code_history.csv`**,
  the file the ROADMAP's "Code history" item planned, with a `status`. One
  row per succession, `kind` subject / course / program, `from_code`,
  `to_code`, `effective_term`, `scope`, `basis`, `status`, `evidence`,
  `notes`. A subject row renames every number under the subject; a course
  row renumbers one course; a chain may mix the two (SOC 250 → SOCI 250 →
  SOCI 2315). The validator refuses a self-succession, a term that is not a
  term code, a `scope` on a subject or course row, a confirmed code with two
  successors (a split: one code cannot have two ids), and a cycle.
- **Only confirmed rows take effect**, as with a unit mapping. A proposed row
  is the screen's candidate, with its evidence, and assigns nothing until a
  person confirms it. The data can only suggest a succession; recording one
  is a decision, taken by a pull request, effective at the next start.
- **`course_id` is the last code of the chain**, not a surrogate. It is
  readable, it is stable until the next confirmed rename (a decision, like a
  unit's), and since nothing is saved there is no key to migrate when it
  moves. `cedar_courses` is one row per id (current subject and number,
  level, latest title, first and last term over every code, how many codes
  and which); `cedar_course_codes` one row per code with its id, where it
  appears and how many steps it took.
- **Attached at load, never saved.** `build_cedar_courses()` runs in every
  loader after the units, `attach_course_ids()` writes `course_id` onto
  `cedar_sections` and `cedar_students`, and `subject_course` is never
  rewritten (annotate, never mutate). 8 s to build and under a second to
  attach on the full pull.
- **A screen proposes; a script writes.** `detect_course_renamings()` finds a
  section under two subjects (`section_crn`) and a title whose one retired
  code stopped before its one new code began (`title_match`), resolving codes
  through the file first so a pair already joined is not a candidate.
  `scripts/propose-code-history.R --write` appends what it finds as proposed
  rows, with a floor of 20 rows between the two codes.

**What the first PR produced.** UNM's file carries the three section-evidenced
subject renames confirmed and 320 title matches proposed: 117 effective Fall
2019 (the common course numbering: ENGL 112 → ENGL 1120 on 30,400 rows, MATH
121 → MATH 1220, CJ 130 → COMM 1130), 64 effective Fall 2026 (MGMT 326 → BUSA
3260 and the rest of I37's list), the remainder spread across the years
between. With the three confirmed rows the dimension has 7,450 courses from
7,641 codes; 229 codes resolve to another, joining 191 courses (79 PSYC, 61
CCST, 51 SOCI). SOCI 371's history now begins Fall 2018, where SOC 371's did,
instead of Fall 2021. The demo institution's file carries the RN01 fixtures'
successions, one of them proposed, so `test-courses.R` shows a proposed row
assigning nothing and a chain crossing kinds.

**The readers, in order.** No reader grouped on `course_id` in PR 1, so no
number moved there. **Reader PR 1 (2026-11-06): Low Enrollment.** Its
schedule view and course histories (`get_enrollment_concerns()`,
`get_course_enrollment_history()` and the batched form in `enrl.R`) key on
`course_id`, require the column, and name the former codes behind the shown
numbers in the history text. Measured on the 2026-10-08 pull for Fall 2026:
2,199 scheduled course-campus rows, 42 with history under a former code (all
PSYC behind PSY, the confirmed renames); SOCI 371 on ABQ has 19 terms of
history where it had 12. With only the three subject renames confirmed, 4 of
the 391 courses with no Fall history by code find it by id; were the 320
proposed renumberings confirmed, 84 would (36 BUSA, 8 ACCT, 8 NURS, I37's
list), which is why confirming them is a decision worth a person's hour.
**Reader PR 2 (2026-11-06): Course Dynamics.** The whole tab reads by
course. `key_on_course_id()` (`courses.R`) returns a working frame whose
`subject_course` is the `course_id` and whose registrar's code is
`listed_code` — every column shared, nothing copied, the loaded tables
untouched — so a reader's filters, groupings, joins and flows on
`subject_course` follow the course with no change to their grain, and
`course_id_of()` resolves the picked code, current or former, to its course.
`create_course_base_data()` resolves once and names the report by the id
(`course_code`; the picked code stays as `selected_code`); the crosslist-family
functions in `enrl.R` key both tables the same way, so a former code is the
course's own history and never a partner listing; the flows, outcomes,
rollcall, retention and downstream readers take the keyed class list
(`cr_students` in `server.R`); the page says which codes the course has
carried and when (`course_former_codes_note()`, reading `listed_as` off the
section history); and the neighbors cache keys the frame's renames
(`course_code_renames()`, version 4). Former codes were not made a kind of
listing after all: a listing is a code students register under *in the same
term*, and a former code is the same course in an earlier one, so it belongs
in the course's own row with a note, not in a split column. Measured on the
2026-10-08 pull: keying the 1.85M-row class list takes no measurable time
(two column pointers); SOCI 371 on ABQ has 19 terms of section history where
it had 12 and 17 terms of class-list lifecycle where it had the 12 the
sections reached (the class list already carried SOCI on the old sections,
I45, so the grade-reading and flow cones were whole by code; the sections and
everything joined through them were not); PSYC 302 likewise, 19 and 17 where
it had 9. SOCI 371's feeders drop from 1,175 rows to 1,154 with the same
4,728 students: 21 feeder codes united with their renames.

**Reader PR 3 (2026-11-06): Regstats.** `get_reg_stats()` keys both tables
on `course_id` before anything reads them, so `history_keys` follow the
course unchanged in name: a renumbered course's strictly earlier offerings
are its own count means, drop means and Terms at Cap, and the schedule's
capacity for a section the class list names by the newer code (I45) joins
its census instead of reporting unmatched. A picked code, current or former,
resolves once (`course_id_of()` over the codes both tables carry). The
precomputed base it filters moved into a branch helper,
`build_cl_enrls_base()`, which counts the keyed class list and stamps the
renames it saw on the result; `cl_enrls_base_is_current()` refuses a base
saved before the current `code_history.csv` rows were confirmed, in
`global.R` (recompute) and in `get_reg_stats()` (stop). The day cache is v6
and records the renames it was counted over, so a confirmed row is a miss
the same day. Every flagged table carries `former_codes`
(`course_former_code_spans()`, "HIST 320 (Spring 2020 to Fall 2020)"), shown
beneath the code, and the scope bar says how many flagged courses ran under
another code. The excluded-course list is applied by course on both
whole tables before anything reads them (`excluded_course_ids()`; ISSUES
M39), since a list naming CCS 699 matched by code misses the CCST 699 the
course is keyed on. Measured on the 2026-10-08 pull: 551 flagged courses
for Fall 2026 by course and by code (seven CCS courses report as CCST with
both codes' counts, and 30 name a former code), 557 against 548 for Spring
2026 (PSYC, SOCI and CCST courses whose PSY, SOC and CCS offerings are
now their baselines); the saturation universe is the same 3,685 groups
either way; the base builds in 7.6 s as before. Definition regstats 5.0.0. Waitlists reads the same keyed
base: `attach_enrollment_history()` resolves each waitlist row's code to its
course for the join and puts the code back, so the history follows the
course. That is needed today, not only after a confirmation: UNM's class
lists carry CCS beside CCST through Fall 2026 (201 CCS codes from Spring
2026 on, 109 Fall 2026 sections), and joined by code a waitlisted CCS course
would read no history from the keyed base.

**Reader PR 4 (2026-11-06): Waitlists.** `inspect_waitlist()` keys both
tables on `course_id` and resolves a picked code once (`course_ids_of()`,
shared with Regstats), so the true-demand de-dup, the three tables and the
section supply follow the course: students waiting under CCS 370 and CCST
370 in one term are one row, and a student waiting under one code while
registered under the other holds a seat and is not counted. Every table
carries `former_codes`, shown beneath the code by `course_code_cell()`,
which now takes the drill link (`onclick`). Definition waitlist 3.0.0.
Measured on the 2026-10-08 pull: Fall 2026 has the same 732 rows and 3,865
waiting students by course and by code (no student in this pull waits
under two codes of one course), 39 rows name a former code, and one more
row reads enrollment history. Regstats rows, which carry course ids since
reader PR 3, now drill into a Waitlists view that finds every code's rows.
The Department Dashboard's waitlist block still matches by code (its
enrollment history comes from `get_enrl()` by code and it caches its own
payload); it is the next reader, and the definition says so. The downstream-signals
flows (`cedar_course_flows`) are still by code and rebuild on
`cedar_course_terms`. Next: the enrollment projection inputs are a
`model_version` decision. Then `cedar_course_terms` is promoted from
`cedar_cl_enrls_base` and `cedar_attempts` from `cedar_grades`, both keyed on
`course_id`, and `course-flows.R`'s precompute rebuilds on it. The Admin > Mappings surface for code history (when each
code was in use, computed from the data; which replaced which, from the
file) is its own PR, and `program` rows are validated now so it has
something to read.

**Not doing.** Rewriting saved rows to the new code: the code the registrar
used that term is a fact about the term, and a reader that wants it keeps
it. A surrogate integer id: it would need saving, and a saved key is a
migration every time it moves. Inferring successions at runtime from titles:
the title screen is a proposer, and proposes one-to-one matches only, because
a many-to-many title group (BIOL 429 matched BIOL 201L) needs a person.
Recording a split: a course that becomes two courses is two courses, and the
history before the split belongs to neither alone.

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
