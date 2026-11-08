---
title: Architecture Decisions
parent: Developer Guide
nav_order: 2
---

# Architecture decisions

An architecture decision record (ADR) states one decision CEDAR has made, why,
and what it costs. Each keeps its status line current; what a PR changed lives
in git, and open defects in [`ISSUES.md`](https://github.com/cedar-collective/cedar/blob/main/ISSUES.md).

- [ADR-001: domain-shaped tables](#adr-001-move-cedars-tables-from-report-shaped-to-domain-shaped) — facts, dimensions and
  measures in place of report-shaped extracts. In progress.
- [ADR-002: explicit mapping files](#adr-002-explicit-mapping-files-replace-runtime-department-inference) — every unit and college from
  `institution/<id>/*.csv`, never inferred. Done.

---

## ADR-001: Move CEDAR's tables from report-shaped to domain-shaped

- **Status:** Accepted, in progress (steps 1–5 done; steps 6 and 7 planned
  2026-11-08). First written 2026-07-31; rewritten 2026-11-03 with the
  measurements below. Step 3's design revised 2026-11-06 after review; course
  keying decided 2026-11-07.
- **Supersedes:** [ADR-002](#adr-002-explicit-mapping-files-replace-runtime-department-inference) Stages 3 and
  3b (units and colleges stamped onto rows at transform time): the same files
  are read as dimensions at load. ADR-002's files, rules and pipeline
  contract stand.
- **Complements:** [source-to-cedar-manifest.md](source-to-cedar-manifest.md),
  [field-reliability.md](field-reliability.md), [right-edge-policy.md](right-edge-policy.md).

---

### Context

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

#### 1. The same fact is stored on several tables, each copy mapped separately

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
| `cedar_students` | 1,855,577 | 465,836 | 468 MB | 347 MB without the student columns; ~190 MB without the section columns too (the first draft's estimate; most section columns are grouping keys and stay, see step 5's decisions) |
| `cedar_programs` | 622,988 | 426,222 | 181 MB | — |
| `cedar_sections` | 253,707 | — | 100 MB | already at its grain (`job_cat` was 100% NA; dropped 2026-11-07, I52) |

A student-term table carrying the eight student columns is 53 MB.

#### 2. The copies disagree, and nothing compares them

- **Course codes (I45).** The class list carries a renamed subject's new code
  back onto old terms; the DESR keeps the code the section was scheduled under.
  23,451 class-list rows (1.26%) name a different `subject_course` than their
  own section: SOC→SOCI and PSY→PSYC in 2019–2021, CCS→CCST in Fall 2025.
  SOCI 371 has 177 registered students on the Fall 2019 class list and no
  sections that term. Every other section attribute agrees 100% across the two
  tables.
- **Instructor IDs.** Both tables have `instructor_id`; the class list's is a
  32-character hash and the DESR's a 9-digit ID. Zero values match. Nothing
  joins on it yet; the first join will return nothing, silently. *(The
  transform's HR merge onto the DESR was that join: it matched nothing and
  left `job_cat` NA on every section. Fixed 2026-11-07, ISSUES I52: the
  transform hashes every instructor ID alike, and sections carry no faculty
  attribute.)*
- **Classification.** 111 student-terms carry two classifications on the class
  list, every one from rows pulled on two dates. ADR-001's first draft found
  116 adjacent-level disagreements between the class list and academic
  studies, all snapshot skew. **Which answer a reader gets depends on which
  table it reads.**
- **Vocabulary.** Before the source-to-CEDAR mapping was standardized,
  `student_level` held `UG` on one table and `Undergraduate` on the other,
  0% overlap, and a cross-table filter returned zero rows rather than erroring.

#### 3. Every analysis re-derives the same facts, slightly differently

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

#### 4. Mappings are applied at transform time, so an edit rebuilds four tables

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

### Decision

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

#### Facts: one row per event

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

#### Dimensions: one row per entity, from the files

| table | grain | source | what moves here |
|---|---|---|---|
| `cedar_terms` | term | derived from the data once per load | season, academic year, next/previous regular term, start and census dates, and the four right edges as flags (`is_settled`, `is_graded`, `is_latest_enrolled`, `has_degrees`) |
| `cedar_courses` | course id | the sections, the class lists and `code_history.csv` | a **stable id** per course: the last code of its confirmed succession chain, so a renamed or renumbered course keeps one history (I37, I45); the codes it has carried are `cedar_course_codes`. Built 2026-11-06 (step 4, PR 1); written out [below](#step-4-the-course-dimension-and-what-follows-it) |
| `cedar_subjects` | subject × college × level | `subjects.csv` | subject → unit → college, read as a table instead of stamped |
| `cedar_program_catalog` | program code × college | `programs.csv` | program → unit, `is_pre_major`, `leads_to` |
| `cedar_units`, `cedar_colleges`, `cedar_campuses` | code | `units.csv`, `colleges.csv`, `campuses.csv` | names, home college, aliases |
| `cedar_student_terms` | student × term | class list and academic studies, with declared precedence | level, classification, campus, college, standing, residency, primary major, per-term credits and GPA: each stored once |
| `cedar_people` | student | academic studies | `gender`, `ipeds_race`, `first_gen`, and the **pull-stamped fields** (`inst_credits_*`, `overall_credits_*`, `inst_gpa`) labelled with their pull date, so no per-term table holds a field that is not per-term |

The vocabulary decision is made once, in one column of one dimension. The
mapping files **are** the dimension tables: an edit changes the next load and
rebuilds nothing. The provenance stamps, `CEDAR_MAPPED_TABLES` and the deploy
gate's mapping branch retired with the stamped columns (step 3, 2026-11-06).

#### Measures: computed once, under the canonical definitions

| table | grain | promoted from | carries |
|---|---|---|---|
| `cedar_student_terms` (measure columns) | student × term | `cedar_student_term_credits` + `cedar_next_term` | `enrolled` (registered or late-dropped: census participation, as everywhere else in CEDAR), `returned_next_regular_term`, `return_observable` (from `cedar_terms`), DFW count, late withdrawals, credits entering/after, `timeline_valid` |
| `cedar_attempts` | student × course × term × campus | `cedar_grades` (retired 2026-11-07) | one outcome per attempt from `classify_enrollment_outcomes()`, `cedar_outcome_policy_version` |
| `cedar_course_terms` | course × term × campus | `cedar_cl_enrls_base` | first-day, census and final enrollment, waitlist demand, DFW rate, fill |

These three already exist in partial, ad hoc form. The change is to declare
them the canonical source, give each one definition, and make cones read them.

#### Snapshot vs. history

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

### What this unlocks for other institutions

Today onboarding says *produce a MyReports class-list export*, which asks a
university to reproduce UNM's reporting quirks. Under this model it says *give
us registrations, declarations, completions, sections and the mapping files*:
concepts every SIS has. The MyReports extracts become one adapter among
several, and the manifest's §1–5 become an appendix of that adapter.

---

### Consequences

#### Costs, stated plainly

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

#### Migration path: strangler, in this order

Each step is additive until its last sub-step, so the app runs throughout.
What each PR changed and measured is in its PR description and commit; this
record keeps the decisions.

| Step | What | Status |
|---|---|---|
| 1 | `cedar_terms`: the right edges become a join | done |
| 2 | `cedar_student_terms`: one definition of an enrolled term and of return (closes I44) | done 2026-11-04 |
| 3 | Dimensions from the mapping files, units attached at load | done 2026-11-06 |
| 4 | `cedar_courses` and course ids at load (I37, I45); `cedar_course_terms`; `cedar_attempts` | courses and keying done 2026-11-07; `cedar_course_terms` done 2026-11-07; `cedar_attempts` done 2026-11-07 (`cedar_grades` retired); `cedar_course_flows` done 2026-11-07 |
| 5 | Thin `cedar_students` and `cedar_programs` to keys and registration facts; rename to fact names | student-term columns off the loaded class list done 2026-11-07 (`thin_class_list()`), and off the saved file (`cedar_class_list_descriptions`); the section columns and `cedar_programs` stay (decisions below); renamed `cedar_registrations` 2026-11-07, its file still `cedar_students.qs` (`CEDAR_TABLE_FILES`) |
| 6 | The measure tables become transform outputs: the app loads and verifies, never builds (decisions below) | done 2026-11-08 (`transform_measures()`, `cedar_load_measure_table()`, the gate's `build_measures_if_stale()`) |
| 7 | Re-point the cones onto the measure tables, deleting each re-derivation; then rename the class-list file | planned 2026-11-08; progress is the count of cones that take `cedar_registrations` (18 of 26 on 2026-11-08) and the cone line count (8,908) |

Step 2's precedence rule: when the two source snapshots disagree, the
academic-studies row wins, the row is flagged and the count reported, never
a silent coalesce.

#### Steps 6 and 7: where compute lives, and the cone migration (planned 2026-11-08)

**The principle.** The transform runs once a day and may take as long as it
needs; a restart should be as fast as a load, and does not need fresher data
than the last transform (re-run the transform when it does). So every table
the app holds is *built* in the transform and *loaded* at start, and the app
never builds a table in its own process.

**What this changes.** Until now `cedar_attempts`, `cedar_course_terms` and
`cedar_course_flows` were startup caches: the saved copy was used when
`*_is_current()` matched the class list, the outcome-policy version, the
graded edge and the course renames, and otherwise the app rebuilt the table
at start. That is the slow, memory-heavy start (the worst case measured
about 2.7 of 3.83 GiB, from the build-time transient copies), and it is the
opposite of the principle. Measured on 2026-11-08 with every cache current,
a restart takes 47 s to *Listening*: about 10 s reading the six saved tables
(the class list 6 s), about 19 s trimming, deriving the class-list
descriptions, building the dimensions and course ids and attaching units
(one block, not yet instrumented), 6 s for the edges, `cedar_terms` and the
cache hashes, 2 s per measure table, and 6 s for the summary and the Shiny
files.

**Step 6 decisions.**

- **The transform builds and saves the three measure tables** after it saves
  the class list, under the same `build_*()` functions and the same currency
  stamp (`CEDAR_OUTCOME_POLICY_VERSION`, the graded edge, the renames). The
  stamp stays: it is what lets the app refuse a stale table.
- **The app loads and verifies; a stale or missing measure table is a
  startup error** that names the table and the command to run, in the fail-closed
  form the edges already use. No rebuild path remains in `global.R`, the
  cache-warming scripts or `scripts/cedar-repl.R`. A code change that alters a
  measure (an outcome-policy bump, a confirmed rename) therefore needs the
  transform re-run before the restart; deploy already gates
  `cedar_student_terms` this way and the measure tables join that gate.
- **Units and course ids stay attached at load** (step 3's decision stands)
  for the fact tables: about 15 s per restart buys a mapping PR that takes
  effect at the next start without a transform run. **The measure tables
  carry unit columns** (`college`, `department`, `source_college`), so they
  cannot: each is stamped with `cedar_dims_fingerprint()` of the mapping
  files and with the first term it was counted from (`cedar_min_term`, which
  decides which course-code renames the trimmed class list shows), and the
  gate rebuilds them when either changes. A mapping PR therefore costs
  minutes at deploy, in the gate's own process, and the app that starts
  afterwards still only loads.
- **The stage is one process and builds one table at a time**, saving and
  dropping each before the next, because the morning refresh runs it beside
  the live app on the 3.8 GiB production host.
- **The AGENTS.md sentence** that the measures are built at startup and are
  not a saved source of truth was replaced with the code (2026-11-08).

**Step 7: the cone migration.** The measure tables exist, but on 2026-11-08
eighteen of the twenty-six cones take `cedar_registrations`, eleven of them
take it and none of the measure tables (bottleneck, course-adjacency,
course-instructor-effect, course-pairs, course-sequence-effect,
data-integrity, declaration-context, entry-heatmap, grouped-student-paths,
major-changes, seatfinder), five still classify grades or compute census
themselves, and only one cone each reads `cedar_attempts` and
`cedar_course_terms`. The payoff of the model — a new cone is a filter and a
join — holds for new cones and not yet for the existing 8,908 lines. The
migration goes one group at a time, each PR deleting the re-derivation it
replaces: outcome cones onto `cedar_attempts`; count and fill cones onto
`cedar_course_terms`; flow, retention and sequence cones onto
`cedar_student_terms` and `cedar_course_flows`. Each migrated cone keeps its
output contract and its fixture expectations, so the committed tests are the
regression check. When a re-transform is routine, the class-list file is
renamed `cedar_registrations.qs` (one line in `CEDAR_TABLE_FILES`, one in
the transform's save), closing step 5.

Group 1, the outcome hub, moved on 2026-11-08: every function in
`R/branches/course-attempts.R` but the status-exclusion report takes
`cedar_attempts`, scoped by the class list's options through
`filter_attempts()` and counted through `attempt_outcome_flags()` off the
stored `outcome_category`, so the per-request path no longer decides which
rows are attempts or reclassifies a grade. The table gained the section's
instructor and the subject (`ATTEMPTS_BUILD_VERSION` 2) because the Course
Report and Gen Ed group by them. Course Dynamics' outcomes, Open Seats' DFW
column and the Gen Ed profile's outcome tables read it; `seatfinder()` no
longer takes the class list at all, and `get_course_outcomes()` takes the
attempts (the persistence analyses beside it still read the class list's
next-term rows). The measure (classified once, dedup'd once) also settled
what a reader of the class list had to re-derive: the AUD, recycled-CRN and
drop-normalisation tests now exercise the table.

Group 2, the two grade-reading cones, followed the same day:
`get_course_sequence_effect()` reads both courses' outcomes off
`cedar_attempts` (`outcome`: pass, dfw, or NA for an early drop or an
ungraded registration, which is what "classifiable" meant), and
`get_instructor_effect()` reads the Y outcomes off it (`outcome_category`:
pass, a late withdrawal is dropped, any other graded category failed,
missing unobserved). Each takes `attempts` beside `students`: the X cohort
reads enrollment to the settled edge, which the attempt table (bounded at the
graded edge) cannot answer, and the comparison's covariates read the class
list, both of which move with group 4. Neither cone classifies a grade any
more.

Group 3, the count and fill readers, followed the same day, and changed the
table before it changed the readers. `cedar_course_terms` build 3 is the
full join of the class list's side (the counts, census, and now the first
day through `calc_first_day_enrl()`) and the schedule's side (the active
offerings through `get_enrl()`: sections, seats, whether the seats are
known, the DESR headcount, and how many of the sections the class list has a
row in), because every reader in the group compared the two sources
itself. The join is full and **NA on a side means that source has no row**:
an offering nobody is listed in is unknown, not empty (EC-11b), and a
cancelled offering students dropped from has no sections. Regstats' lifecycle
history and saturation seats, Waitlists' census history, and the Course
Planning History behind Degree Explorer's tiles read the table scoped by
`filter_course_terms()`, which answers the class list's option names and
refuses a section's or a student's; the recount fallbacks and the
`add_census_enrl()` / `calc_cl_enrls()` / `get_enrl()` calls they wrapped are
deleted, and `get_reg_stats()` and `inspect_waitlist()` require the table.
Regstats' saturation now follows the planning history's capacity rule
instead of its own sum, and the real-data comparison (Fall 2026, 634 rows
before) shows what that changes: an active section with no seats (`enrolled
+ available` not finite or not positive) makes the course-term's capacity
unknown, so twelve rows whose fill was computed over a sum that counted such
a section as zero seats (ARCH 2315 at 104% of 80 seats from four sections,
three with none) leave the table and are counted in `invalid_capacity`; a
zero-seat, zero-student section is not an offering, so four rows count one
or two fewer sections, fourteen course-terms nobody could register for are
no longer "unmatched", and CHEM 304L, whose Summer 2020 row of four empty
sections had poisoned its fill history, enters the table. Dips, waits, early
drops, the waitlist counts and the planning history are identical row for
row, and Regstats runs in 57 s instead of 74 s. Still counting the class list per
request (group 3b): Open Seats' class-list tab, the Course Report's lifecycle
history, the registration snapshots and the demographics' census.

#### Step 5: decisions (2026-11-07)

- **Order:** the student-term columns leave the loaded class list first
  (`student_level`, `student_classification`, `major_code`, `major_name`,
  `student_college`, `student_campus`, `residency`, `dual_credit`, and the
  unread `enrollment_id`: `CLASS_LIST_UNLOADED_COLUMNS`); the section columns
  second; the rename last, as one mechanical PR. Each 1.85M-row column costs
  about 14 MB whatever it holds.
- **The saved file is thin too** (second PR). The transform saves the
  columns once per student, term and pull as `cedar_class_list_descriptions`
  (`build_class_list_descriptions()`, with `rows`, how many class-list rows
  carried each), builds `cedar_student_terms` from that table, and saves the
  class list without them. The mapping audit and Admin > Mappings read the
  roster's majors off it (`summarize_class_list_majors()`). Loading a thin
  file cuts the container's high-water mark, which dropping columns after
  reading a full file did not (R keeps the pages it frees). Every loader
  still calls `thin_class_list()`, so a class list saved before 2026-11-07
  loads in the same shape, its descriptions derived from it with a log line
  (`resolve_class_list_descriptions()`; I48).
- **Readers attach, never re-derive:** `attach_student_descriptions()` reads
  named columns off `cedar_student_terms` and refuses a class-list row the
  table lacks. `filter_class_list()` keeps a `classification` key, which
  filters a column the caller attached; the major, home-campus and
  student-college keys are gone (nothing set them).
- **The projections read the table too** (model 0.29.0): the classification
  and primary major of each student-term, instead of the most common value on
  its class-list rows (I47).
- **Name:** `cedar_registrations`, renamed last as one mechanical PR
  (2026-11-07), which answers open question 1. The table, every
  `data_objects` key, the fixture names and the docs carry the new name; the
  saved file keeps the transform's name, `cedar_students.qs`, because
  production cannot write a new file until its refresh runs again (I43).
  `CEDAR_TABLE_FILES` (`R/trunk/data.R`) maps the table to its file and every
  loader reads through `cedar_table_file()`, so renaming the file is one line
  there and one in the transform's save. `cedar_programs` and `cedar_degrees`
  keep their names: only the class list's was decided.
- **The section columns stay on the row** (decided 2026-11-07, after
  measuring their readers). Of the thirteen, `subject_course`, `campus`,
  `college`, `department`, `level`, `part_term` and `term_type` are the keys
  nearly every course read groups or filters by (campus beside the course,
  always), and `subject_code` and Banner's college are the keys `attach_unit()`
  resolves at load: moving them off means a join on almost every read, which
  is the cost the measure tables exist to avoid. `term_type` alone has a
  dozen readers, the canonical counter and the `cedar_course_terms` cache
  among them, for 14 MB. The status label stays beside its code: it is the
  only explanation of a code CEDAR does not know (the unexpected-status
  audit). What could move is `course_title` and `instructor_name` (29 MB,
  about eight readers, the 149 rows with no section left untitled) and
  `instructor_id`, which must wait until production's sections carry the
  hashed ID (I52) or instructor DFW would group by employee IDs that join no
  faculty row. Not worth the churn now; revisit with the rename if memory
  is short again. `total_credits` (no reader) left the class list with this
  decision. So the saved class list holds about 326 MB in memory on the
  2026-11-04 pull (22 columns), not the ~190 MB the first draft assumed.
- **`cedar_programs` stays at its grain** (decided 2026-11-07). It holds 1.46
  rows per student-term (622,385 rows, 426,241 student-terms, 181 MB), where
  the class list holds four, so moving its 24 student-term columns to a
  student-term table saves about 35 MB and rewrites every program reader
  (Headcount, Pathways, the comparisons). The pull-stamped fields stay too:
  their readers (the comparison covariates, the credit and GPA timelines,
  major-change detection) use them under the field-reliability rules.

Pull history is the one piece with a deadline and should be sized now.

#### Step 3: dimensions, and how data reaches a cone

Decided 2026-11-05; revised 2026-11-06 after review.

- **The mapping files are the dimension tables, and the default unit is
  attached once at load.** On disk a fact table keeps keys only. The loader
  attaches the default unit and college columns under the names every reader
  already used (`department`, `college`, `dept_code`, `college_code`,
  `primary_dept_code`, …), so no reader changed and a mapping edit rebuilds
  nothing.
- **Rejected: the star schema proper**, where every reader joins the
  dimension it needs. Measured on 2026-11-06, 66 files (15 of 26 cones, 28 of
  40 branches, 10 of 18 features, 13 of 16 modules) read a unit column,
  almost all as a filter or a grouping. The join would have become a
  mandatory step in each and in every future cone, and moved no number. The
  concern behind it, that a column's name did not say which rule produced it
  (how I7 and I9 stayed invisible), is answered by the naming rule.
- **The naming rule.** The default columns always mean the default
  hierarchy: the subject's unit on a section or class-list row, the
  program's unit on a declaration or degree. Any other hierarchy is attached
  under its own name (`instructor_unit`), never into the default columns.
- **How data reaches a cone.** A cone names the fact tables that are its
  input; one that needs a dimension by name takes a single `dims`. Features
  keep taking `data_objects`. A single data bag for cones (`cone(data, opt)`)
  was rejected: it hides the dependency the parameter rule exists to show.
- **One function resolves a unit:** `attach_unit(rows, dims, hierarchy)`,
  wrapping the two rules in `R/lists/institution_files.R`. A row the files do
  not cover gets `NA` and a `unit_basis`, never a unit named after itself.
  `test-architecture.R` forbids resolving a unit anywhere else, which is what
  prevents I9.

Consequences: the transform stopped stamping units, the provenance stamps
and `CEDAR_MAPPED_TABLES` went, the deploy gate builds only
`cedar_student_terms`, and `cedar_lookups` retired into `dims`
(`unit_names()`, `college_code_names()`, `subject_units()`,
`name_program_codes()`). One rule surfaced only by comparing on real data: a
declaration's `program_college` is the files' answer alone (NA when
undecided); the Banner fallback belongs to the student's `college_code`.

#### Step 4: the course dimension, and what follows it

Decided 2026-11-06; the keying decision 2026-11-07.

**The problem.** On the 2026-10-08 pull the data carries 7,641 course codes.
Banner applies a subject's rename to old class lists but not old schedules
(I45: 1,355 sections carry two codes), and the Fall 2019 common course
numbering and the Fall 2026 renumberings started each affected course's
history over (I37). Every reader grouping on `subject_course` saw the old
course die and the new one arrive from nowhere.

- **One file records successions: `institution/<id>/code_history.csv`.**
  One row per succession, `kind` subject / course / program. A subject row
  renames every number under it; a course row renumbers one course; a chain
  may mix them (SOC 250 → SOCI 250 → SOCI 2315). The validator refuses a
  self-succession, a malformed term, a confirmed code with two successors (a
  split: one code cannot have two ids) and a cycle.
- **Only confirmed rows take effect.** A proposed row is a candidate with its
  evidence and assigns nothing. `detect_course_renamings()` proposes (a
  section under two codes; a title whose retired code stopped before its new
  one began); `scripts/propose-code-history.R --write` appends what it finds;
  a person confirms through a pull request.
- **`course_id` is the last code of the chain**, not a surrogate: readable,
  stable until the next confirmed rename, and never saved, so there is no key
  to migrate.
- **Keyed at load (decided by the user, 2026-11-07).** The first readers each
  opted in through a per-reader shim, so `subject_course` meant the code or
  the course depending on which function had run, and both regressions caught
  in the Regstats PR came from that. Of three end states (key once at load;
  group on `course_id` openly everywhere, with a ratchet; keep the shim), the
  user chose the first, so a cone written naively on `subject_course` is
  right by default. `attach_course_ids()` sets `subject_course` to the
  course on the loaded sections, class list and grades, keeps the
  registrar's code in `listed_code`, and the saved files are never rewritten.
  The two code-level functions read the registrar's code back
  (`.registrar_codes()`).
- **CCS is not renamed to CCST** (corrected by the user, 2026-11-07). CCST is
  the lower-division prefix and CCS still the upper-division one; the first
  confirmed subject row would have renamed every current CCS course. It is
  61 course rows instead, CCST nnn → CCS nnn.
- **`cedar_course_terms` replaces `cedar_cl_enrls_base`** (2026-11-07).
  Its grain is course × term × campus × part of term: Regstats compares a
  full-term section with its half-term siblings, and since the class list is
  one row per student, course, campus and term, the part-of-term rows sum
  exactly to the ADR's grain. It carries counts only, nothing pooled across
  terms: a measure table holding a mean would hold a later term's counts in
  an earlier term's row. It is a parameter with a declared contract
  (`COURSE_TERMS_COLUMNS`, `COURSE_TERMS_BUILD_VERSION`, the class list's
  renames), never a global. First-day enrollment, DFW, fill and waitlist
  demand join it when a reader moves to them.
- **`cedar_attempts` is built from the keyed class list, not from saved
  `cedar_grades`** (2026-11-07). `cedar_grades` is pre-dedup, at CRN level,
  and keyed on the registrar's code; the loaded class list is one row per
  student, course, campus and term, the grain the ADR names. It is bounded at
  `last_graded` and stamped with it, so a row with no posted grade is never
  in it and a copy built to another edge is rebuilt. Its outcome comes from
  the classifier's own flags, and its per-course-term counts equal
  `get_course_outcome_rates()`. `cedar_course_terms` (build 2) carries the
  counts: NA after the graded edge, unknown rather than zero.

Confirming the 320 proposed renumberings is a person's decision: it is what
makes I37's courses show their earlier offerings (84 Fall 2026 courses with
no Fall history by code would find it).

- **`cedar_grades` retires; Roadblocks reads `cedar_attempts`** (2026-11-07).
  Comparing the two found the class-list dedup could keep an early drop over
  a late withdrawal (ISSUES I50): the transform now keeps the row
  `STATUS_PRECEDENCE` ranks first, a posted grade before none. On one pull
  run both ways, Roadblocks' first observations match the saved-grades path
  on every one of 1,328,766 and add the 305 it excluded as conflicting: the
  loaded class list holds one row of record per course-term, so a
  first-term outcome is never in conflict (Roadblocks 2.2.0).

- **`cedar_course_flows` is a measure held in `data_objects`, bounded at the
  longitudinal edge** (2026-11-07). The precompute Regstats' downstream
  signals read was a bare global the feature found with `exists()`, counted
  into the registration still in progress, recomputed silently from the
  class list when absent, and returned NULL on any error. It is now
  `build_course_flows(students, edges)`: every next-term pair to
  `cedar_longitudinal_edge()`, stamped and checked like `cedar_course_terms`
  (`course_flows_is_current()`), passed to `get_next_term_signals()` as a
  parameter, which refuses anything else. The Course Report's flows tab
  already trimmed to the same edge.

**Not doing.** Rewriting saved rows to the new code: the code the registrar
used that term is a fact about the term. A surrogate integer id: a saved key
is a migration every time it moves. Inferring successions at runtime from
titles: the title screen proposes one-to-one matches only, because a
many-to-many group needs a person. Recording a split: a course that becomes
two courses is two courses.

#### Not doing this

Every new analysis keeps choosing its own "enrolled", its own next-term
lookup and its own unit column, and the disagreements stay invisible until
someone compares two pages. The deploy gate keeps rebuilding four tables per
CSV edit. The vocabulary splits recur the next time a report changes.

---

### Open questions

1. ~~`cedar_registrations` vs `cedar_class_lists`: decide before step 5.~~
   `cedar_registrations`, renamed last (step 5 decisions).
2. Pulls layer: full extracts or a changes-only log? Size it first.
3. ~~Does the renaming crosswalk live in a mapping file or derive from
   DESR history?~~ Answered by step 4: both. The screen derives candidates;
   the file holds the confirmed rows.
4. Which measure columns on `cedar_student_terms` need a campus variant
   (home campus is a dimension; delivery campus is on the attempt).

---

## ADR-002: Explicit mapping files replace runtime department inference

- **Status:** Done. Accepted 2026-10-03; Stages 0–6 finished 2026-10-16. A
  unit is the source system's organisation (Banner's department) by default,
  keeping CEDAR's existing splits of a Banner department as recorded splits.
  Stages 3 and 3b stamped units and colleges onto saved rows; ADR-001 step 3
  replaced that with attaching them at load, from the same files.
- **Supersedes:** the code-parsing department chain (`generate_program_map()`,
  `program_map.qs`, and the overrides in `R/lists/program_code_maps.R`), and the
  program-to-department review list as the way to fix mappings.
- **Complements:** [ADR-001](#adr-001-move-cedars-tables-from-report-shaped-to-domain-shaped), whose unit dimension
  this defines; [institution-boundary-audit.md](audits/institution-boundary-audit.md),
  which found ten of twelve `R/lists/` files are institution configuration.
- **Resolved:** ISSUES I7 (phantom departments), I9 (pre-major lists
  disagree), I11 (concentrations mapped by name), and the ROADMAP item
  "Externalize department/program/subject mappings to YAML or CSV data files".

---

### Context

Every CEDAR department report rests on one question: **which unit does this
course, program, or student belong to?** CEDAR answers it at transform time, by
inference:

- A program's department is rebuilt from its code through five tiers:
  `major_college_to_dept`, `subj_to_dept`, `major_to_dept` (derived from a
  generated `program_map.qs`), `extra_p2d`, and finally the program code itself.
- A course's department is its subject code looked up in `subj_dept_map`,
  falling back to the subject code itself.
- Thirteen lists feed this, totalling about 1,060 lines, plus a 180-line
  generator that parses Banner program codes into degree, major and college.

The October 2026 pipeline audit measured what that costs:

| Failure | Measured |
|---|---|
| Programs reported under a department named after their own code | 77 codes |
| Courses reported under a department named after their subject | 21 subjects, 10,221 enrollments |
| Overrides written down but silently ignored | `FPMD="PHRM"` and three more, until #106 |
| Concentrations with no department, or the wrong one by name | 23,304 rows since Fall 2024; Public Policy counted under PADM for Political Science students |
| Programs mapped to the wrong department | East Asian Studies, Comparative Literature (#100) |

Each was found one at a time, after someone noticed a number was wrong. The
inference is invisible: a wrong answer looks exactly like a right one.

Meanwhile Banner already records the owning department. `Department` is native
to the Academic Studies, degrees and class-list exports, 99.9% filled, and was
identical on all 12,786 rows re-pulled a median 153 days apart. It names the
right owner for every major fixed by hand this year: East Asian Studies,
Comparative Literature, Doctor of Pharmacy, Radiologic Sciences and Health
Administration. CEDAR read it until
March 2026 and replaced it with code parsing because the name-to-code crosswalk
covered only 29% of rows.

Two facts shape the replacement:

1. **Native fields are good evidence but not a contract.** Banner's department
   is too coarse in places (one "Provost Branch Campuses" for 38 programs),
   is a bucket rather than an owner in others (`*Interdisciplinary: A.S.` holds
   Museum Studies, Biochemistry and the MPP), and covers only the primary
   major.
2. **CEDAR has to run outside UNM.** Another institution has different programs,
   departments, export columns, and its own messy data. Logic tied to UNM's
   MyReports fields cannot be adopted; a reviewed text file can.

### Decision

**The pipeline reads explicit mapping files and nothing else to assign units.
Native fields and data patterns are used only to *propose* rows for those files,
by a separate script, for a person to confirm.**

Three roles, kept apart:

| Role | Who | Reads | Writes |
|---|---|---|---|
| Evidence | Source exports | | Native fields such as Banner `Department` |
| Proposal | `scripts/propose-mappings.R` | Exports + existing mapping files | New rows marked `proposed`, with their evidence |
| Contract | Transform | Mapping files only | Units on every CEDAR table |

The transform never parses a code, never falls back to a self-named unit, and
never reads a source department field to decide anything.

### The mapping files

One directory per institution, `institution/<id>/`, chosen by the
`CEDAR_INSTITUTION` environment variable (default `unm`). Not a `config.R`
setting, because `config.R` is not committed and CI, the demo stack and the
transform run without one. UNM is `institution/unm/`; the synthetic demo gets
`institution/demo/`. Plain CSV, UTF-8, one row per key, so every change is a
one-line diff.

#### `units.csv`: what a department report is about

| Column | Meaning |
|---|---|
| `unit_code` | Short stable code, e.g. `HIST`, `THDA`, `MSST` |
| `unit_name` | Display name |
| `college_code` | The unit's home college (decided 2026-10-04; see "Colleges are mapped, not read") |
| `kind` | `department`, `program` (a standalone interdisciplinary unit), or `college` (a college-wide unit owning courses no department does, coded college + `CW`: `ASCW`). Added 2026-10-04 with its first use; replaces the draft's `school` |
| `status` (deferred) | `active` or `retired`; retired units keep their history |

`status` was planned for Stage 2 and deferred: nothing reads it yet. Add it
with its first reader.

The first draft gave units no college, because 11 units appear under two
colleges in `subjects.csv` (PADM under Arts & Sciences and the Provost, for
example). That is superseded: each unit has one home college, and the 11 are
decided once. See below.

#### `subjects.csv`: course subject to unit

`subject_code`, `in_college`, `in_level`, `unit_code`, `college_code`,
`status`, `evidence`, `notes`. Replaces `subj_dept_map.R`.

- `in_college` and `in_level` narrow which courses a row covers: branch
  campuses reuse subject codes (`HLED`, `PH`, `SUST`) for units that differ
  from the main campus's, and a subject's courses can belong to different
  colleges by level. The most specific confirmed row wins (subject + college +
  level, subject + college, subject + level, subject).
- `college_code` names the college credited with the courses when it is not
  the unit's home college (decided 2026-10-04): Global & National Security is
  one unit, its undergraduate courses University College's and its graduate
  courses Graduate Studies'.
- `status` and `evidence` work as in `programs.csv`: the assistant proposes a
  row for every subject the data uses with no row, and only confirmed rows map.
- From Stage 3 the transform takes the most specific confirmed row, after
  translating the section's college through `colleges.csv`. The runtime lookups
  built from `subj_dept_map` still take the first confirmed row for a code
  until Stage 4, so row order still matters to them.

#### `programs.csv`: program code to unit

| Column | Meaning |
|---|---|
| `program_code` | The major, minor or second-major code as it appears in the data |
| `college_code` | Blank for every college, or a college where this code has a different unit. A college row wins there. Only two UNM codes need one (`BADM`, `CRIM` at the branches) |
| `program_name` | Display name |
| `unit_code` | Owning unit |
| `is_pre_major` | `TRUE` / `FALSE`, stated rather than inferred |
| `leads_to` | For a pre-major, the program code of the degree it leads to (replaces `premaj_canon`). A program code, never a department code; blank when that degree has no code. It translates pre-major to major and records no history: a code that replaced another is lineage (`institution/unm/README.md`) |
| `basis` | Why this unit: `source_department`, `subject_code`, `inherited`, `name_match`, `course_taking`, `decided`, `override`, `no_unit` (nothing owns it), `unresolved` (no evidence; always proposed) |
| `status` | `confirmed` or `proposed` |
| `evidence` | What the assistant saw, e.g. `Banner Department "Radiology" on 236 rows` |
| `notes` | Free text, e.g. the date and who decided |

#### `colleges.csv`

`college_code`, `college_name`, `source_names` (every spelling the exports use,
`|`-separated, replacing `college_name_to_code`).

#### `source_departments.csv`: evidence aid, not read by the transform

`source_name`, `unit_code`, `kind`, `notes`. Records what each source-system
department means, so the assistant can propose program rows from it. `kind` is
`department` (one unit), `split` (several units, `|`-separated; the assistant
places each program among them), `bucket` (no unit: every program in it needs
its own evidence) or `non_degree` (its programs belong to no unit). The
`source_code` column first proposed was dropped: UNM's exports carry only names.
Every spelling needs a row, because Banner renames departments.

#### `settings.csv`

`setting`, `value`. Holds `mapping_files_url`, the GitHub location of the
institution's directory, so Admin > Mappings can link each proposed program row
to its line. Mapping decisions are edits to these files in the repository, never
in the app: the running container's copy is replaced by the next deploy.

#### Rules that need no file

- **Concentrations take the unit of the student's primary major.** Measured on
  every concentration in the Academic Studies file: none fit only a second
  major. Should an institution need exceptions, an optional `concentrations.csv`
  can be added later.
- **Second majors and minors** use their own code's row in `programs.csv`, never
  the student's primary-major department.

#### Validation

`validate_mapping_files()` runs at startup and in the test suite, and stops with
every problem listed: missing columns, duplicate keys, a `unit_code` absent from
`units.csv`, a `leads_to` that is not a program, an unknown `basis` or `status`.
Invalid files are an error, never a warning.

### Colleges are mapped, not read (decided 2026-10-04)

The mapping files state how the institution is organised, so that no reported
relationship depends on which fields an export happens to carry. That covers
colleges as much as units:

- **A program's college is its unit's college**: program → unit (`programs.csv`)
  → college (`units.csv`). An optional per-program college, for a program that
  sits in a different college from its owning unit, overrides it.
- **Reports use the mapped college.** The college the source recorded on each
  row is kept beside it as `source_college`, for audit only, and the mapping
  audit lists every row where the two disagree. That is how a rename is seen:
  UNM's College of Education appears as `ED` and "College of Education" before
  2021 and as `EH` and "College of Educ & Human Sci" after (ISSUES I12).
- **History is restated to today's organisation**, as it already is for units:
  a program that moved colleges reports under its current college in every
  year. `source_college` keeps the as-recorded view.
- **Every spelling and former code a source uses for a college** is listed in
  `colleges.csv` (`source_names`), so source values are translated explicitly
  and an unknown one is listed, never silently dropped.
- **One source college stays an input:** a course section's own college (the
  DESR `COLLEGE`), because `subjects.csv` keys on it to tell a branch campus's
  `HLED` from the main campus's. It chooses the unit; it is not reported as
  the course's college.

Two changes follow in the files. `units.csv` gains `college_code`, and the
assistant proposes each unit's from the data for review. In `programs.csv`, the
column that today means "this row applies only in that college" is renamed
`in_college`, so that no column called `college_code` means two different things.

Decided with it, 2026-10-04:

- **Graduate students report under their academic unit's college.** Banner's
  Actual College files 79% of graduate major rows under Graduate Programs
  (`GP`), an administrative home; academic units keep their graduate students.
- **Pre-majors report under the college they lead to**, through `leads_to`:
  a pre-Nursing student counts under Nursing, not University College.
- **Banner's Translated College is the evidence and the check, not the
  reported value.** It is Banner's own translation of each student to an
  academic college: graduate students to their colleges, most pre-majors to
  their target college, and the I12 renames already applied. The chain
  program → unit → college agrees with it on 96.9% of 393,143 UNM major rows.
  The assistant proposes unit home colleges and per-program overrides from it
  (Biochemistry's courses are taught by Medicine but its majors are Arts &
  Sciences), and the audit compares the mapped college against it, so the
  remaining disagreements are each a reviewed decision. An institution whose
  exports carry nothing like it gets proposals from weaker evidence, and the
  same mapping.
- **"Undergrad Certificate Program" is `AD`**, with the branch campuses' other
  programs; "University Studies" is `UC`; `ED` and "College of Education" are
  `EH` (ISSUES I12).

Why not read the college from each row, as CEDAR did: it is implicit (nobody can
point to where "Nursing is in the College of Nursing" is stated), it inherits
every source quirk (a rename splits one college's history in two), and an
institution whose exports carry no college gets nothing. Reading per row is
right for events -- what a student declared, which course they took -- and
those stay in the data.

### The pipeline contract

- Every subject and program code in the data is looked up in its file. There is
  one tier.
- A code with no row gets **no unit** (`NA`). It is listed on Admin > Data &
  Usage > Mappings and in the refresh report. It is never given a self-named
  unit, and it never blocks the refresh, which the whole app depends on.
- Only `confirmed` rows assign units. `proposed` rows are visible on the Admin
  page but assign nothing until someone confirms them.
- The unit a row resolved through is kept, so any number can be traced to the
  line in the file that produced it.

### The mapping assistant

`scripts/propose-mappings.R --institution <id> [--write]`

1. Reads the parsed exports and collects every distinct subject code, program
   code (primary, second major, minors), and source department name.
2. For each code with no row, proposes a unit, strongest evidence first:
   - the source department, through `source_departments.csv` (primary majors);
   - inheritance: a minor or second-major code that is someone's primary major
     takes that program's unit;
   - for a pre-major, the unit of the program it leads to;
   - a name match against `units.csv`;
   - course-taking: which unit's courses the program's students take most.
3. Writes the evidence beside each proposal and marks it `proposed`.
4. **Never edits a `confirmed` row.** Dry run by default; `--write` appends.
5. Prints a short review list: new codes, proposals, and codes it could not
   propose for.

Run it at setup, and whenever the Admin page shows unmapped codes. The daily
refresh may run it in dry-run mode so new codes appear on the Admin page the
day they arrive.

For UNM its first run reproduces most of today's departments from Banner's
`Department`, leaving the cases Banner cannot settle, already drafted in
`docs/developers/drafts/unit-decisions-draft.csv` (branch `drafts/unit-decisions`):
20 programs in interdisciplinary buckets, 38 branch-campus programs, and 44
codes that only ever appear as minors or second majors.

### Migration for UNM

Staged, each stage compared against the previous output before it ships.

| Stage | Work | Accepted when |
|---|---|---|
| 0 | Snapshot today's unit for every program and subject (`scripts/unit-mapping-baseline.R snapshot`; `compare` diffs any later build against it) | **Done.** 741 program groups, 263 course groups |
| 1 | Write `institution/unm/units.csv`, `subjects.csv`, `colleges.csv` from `subj_dept_map.R`; add the reader, validator and tests | **Done.** Built table identical to the old one; rebuilt sections, students and programs differ from the baseline in 0 groups |
| 2 | Build the assistant; generate `programs.csv` and `source_departments.csv` | **Done.** |
| 2b | Colleges mapped (`units.csv` and per-program `college_code`, `colleges.csv` `source_names`); the mapping audit at the end of every transform and on Admin | **Done.** Mapped college agrees with Banner's Translated College on 98.98% of major rows; the rest are decided pre-major differences and two to review. Changes no number |
| 3 | Transform reads the files for units; both self-naming fallbacks removed | **Done 2026-10-09.** Rebuilt from the same exports, programs, degrees, sections and class lists differ from Stage 1 only as decided; no real unit loses a row. |
| 3b | Colleges reported through program → unit → college, and through subject rows for courses | **Done 2026-10-10.** Units unchanged from Stage 3; colleges differ only as decided. |
| 4 | Retire `generate_program_map()`, `program_map.qs`, and the lists it fed | **Done 2026-10-10.** Tests pass with the lists gone; units and colleges identical to Stage 3b; pre-major flags differ only as reviewed. |
| 5 | Give the synthetic demo its own `institution/demo/` files | **Done 2026-10-10.** The demo builds with `institution/unm/` absent; its course units and colleges are identical to the UNM-files build. |
| 6 | Move the remaining UNM R lists to configuration files under `institution/<id>/` (`CEDAR_CONFIG_FILE_SPECS`), one list at a time | **Done 2026-10-16.** `campuses.csv`, `course_levels.csv`, `gen_ed_courses.csv`, `excluded_courses.csv`, `population_groups.csv`, `projection_groups.csv`, `projection_courses.csv`, `program_names.csv`, `program_name_aliases.csv`, `source_organizations.csv`; every `R/lists/` file is now platform, and the constants they build are unchanged, so no number moves |

##### Decisions made during the migration

The row-by-row comparisons behind each stage are in the stage PRs. What they
decided, and still holds:

- **Pre-majors.** The F code decides: F and XF codes are pre-majors, overruling
  the old exemptions (FES, FPE, FNE, FFDA, FLAI; I9). Branch-campus "Pre-"
  associate degrees and certificates students are admitted to (ASPE, PBA,
  PRSC, APHS, PHSC) are not. A concentration has no code and never takes a
  pre-major flag (I21). A code with no row falls back to Banner's "Pre-" name,
  labelled `pre_major_basis = name_prefix`.
- **Colleges.** A student counts under their primary major's college on every
  row. A program nothing owns may name a college (Undecided → UC). The four
  School of Medicine programs Banner files under UC (Dental Hygiene,
  Radiologic Sciences, EMS, Medical Laboratory Sciences) report under ME. A
  code not yet decided reports Banner's college, labelled `college_basis =
  banner`. Branch-campus sections of main-campus units stay in the branch
  college.
- **Courses are looked up by subject and the section's college,** with the
  section college translated through `colleges.csv` first: pre-2021 Education
  sections carry `ED` where subject rows say `EH`, and a literal match would
  have dropped 10,370 of them. A subject taught under a college it had no row
  for got a row carrying the unit it already had.
- **Configuration files differ from mapping files** in who reads them: the
  `R/lists/` file that builds a constant reads and validates its file at load
  (`CEDAR_CONFIG_FILE_SPECS`); the platform code reading the constant does not
  change. Stage 5's demo institution is the adopter test: it builds from its
  own files with `institution/unm/` absent.
- **Two lessons.** Read the exports the transform reads (a stale
  `data/academic_studies.qs` hid 12 codes). Compare row by row, never against a
  whole column of old values (that confirmed 65 wrong rows).

### What this retires

`generate_program_map()` and `program_map.qs`; `xvar_explicit`,
`known_suffixes`, `ad_major_to_dept`, `allowed_unmapped_program_codes`,
`real_F_progs`, `pre_major_exempt_codes`; most of `extra_p2d`; the department
half of `catalog_lookups.R`; the program-name department lookup used by
headcount; and the identity fallbacks in `transform_programs()` and the course
transforms. `subj_dept_map.R`, `mappings.R` and `premaj_canon` move into the
CSV files rather than disappearing.

### Consequences

**Gains.** A wrong unit is a visible line in a file, not an emergent result of
five tiers. Adopting CEDAR means writing files, helped by the assistant, not
changing code. Every mapping change is reviewable in a diff. Unmapped codes are
seen the day they appear.

**Costs, stated honestly.**

- Someone must own the files. New programs arrive every term, and a proposed
  row assigns nothing until it is confirmed.
- The first UNM `programs.csv` needs a review pass, mostly the 102 drafted rows.

### Open questions

1. ~~What a unit is.~~ **Decided 2026-10-03:** the source organisation by
   default (Theatre & Dance is one unit, with each major broken out inside its
   report), with explicit splits only where a subject area is reported on
   separately.
2. **Branch campuses.** One Banner department covers 38 programs; each needs a
   unit decision, or a rule such as "branch programs report to their campus".
3. **Bucket programs.** Whether each interdisciplinary program (Museum Studies,
   Latin American Studies, International Studies) is its own unit or belongs to
   a home department. The MPP was mapped to PADM until 2026-10-12, when it
   moved to ASCW with its PUBP courses.
4. **Concentration rule.** Inferred from the data, not confirmed against
   Banner's own concentration-to-major link, which the export flattens away.
5. **CSV or YAML.** CSV is proposed for diffability and spreadsheet editing.
6. **The 81 proposed programs.** Mostly branch-campus certificates and
   minor-only codes. Many carry a sensible proposal (Art → ARTS, Liberal Arts
   → LAIS); each needs someone who knows the program, because some do not
   survive review (Military Studies was proposed for NVSC and belongs to ROTC).
   From Stage 3 they appear under no unit, on Admin > Mappings, until confirmed.
7. **Hand decisions Banner disagrees with.** Kept at Stage 2, but Banner names
   a different owner for ABA and ASD (Special Education, CEDAR says PSYC), CTS
   (Biomedical Sciences, CEDAR says CHEM), ELNG (LLSS, CEDAR says LING) and
   CHBI (Chemistry, CEDAR says BIOL). Worth confirming with IR.
8. **Accelerated online (X-prefix) programs.** X marks an accelerated online
   program. CEDAR maps each to its base program's unit and has never defined
   whether they should be reported apart.

### Out of scope

- **Input adapters.** Mapping files solve "my programs and departments are
  different", not "my exports have different columns". A defined input format
  with a small adapter per source is separate work.
- **Faculty data** (stops at Spring 2025; audit finding 3) and the HR merge.
- **ADR-001's** move to domain-shaped tables. This ADR defines the unit
  dimension that move will need.
