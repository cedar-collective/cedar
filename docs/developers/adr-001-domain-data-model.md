# ADR-001: Move CEDAR's tables from report-shaped to domain-shaped

- **Status:** Accepted, in progress (steps 1–3 done; step 4 under way). First
  written 2026-07-31; rewritten 2026-11-03 with the measurements below.
  Step 3's design revised 2026-11-06 after review; course keying decided
  2026-11-07.
- **Supersedes:** [ADR-002](adr-002-explicit-mapping-files.md) Stages 3 and
  3b (units and colleges stamped onto rows at transform time): the same files
  are read as dimensions at load. ADR-002's files, rules and pipeline
  contract stand.
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
What each PR changed and measured is in its PR description and commit; this
record keeps the decisions.

| Step | What | Status |
|---|---|---|
| 1 | `cedar_terms`: the right edges become a join | done |
| 2 | `cedar_student_terms`: one definition of an enrolled term and of return (closes I44) | done 2026-11-04 |
| 3 | Dimensions from the mapping files, units attached at load | done 2026-11-06 |
| 4 | `cedar_courses` and course ids at load (I37, I45); `cedar_course_terms`; `cedar_attempts` | courses and keying done 2026-11-07; `cedar_course_terms` done 2026-11-07; `cedar_attempts` next |
| 5 | Thin `cedar_students` and `cedar_programs` to keys and registration facts; rename to fact names | not started |

Step 2's precedence rule: when the two source snapshots disagree, the
academic-studies row wins, the row is flagged and the count reported, never
a silent coalesce. Three class-list description reads remain until step 5:
`filter_class_list()`'s `classification`, `major`, `student_campus` and
`student_college` keys and Regstats' sophomore screen (I47). The enrollment
projections read `major_code` and `student_classification` as model inputs,
so moving them is a `model_version` decision, not a data-model chore.

Pull history is the one piece with a deadline and should be sized now.

### Step 3: dimensions, and how data reaches a cone

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

### Step 4: the course dimension, and what follows it

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

Confirming the 320 proposed renumberings is a person's decision: it is what
makes I37's courses show their earlier offerings (84 Fall 2026 courses with
no Fall history by code would find it).

**Next.** `cedar_attempts` from `cedar_grades` on the keyed tables, its DFW
rate joined onto `cedar_course_terms`, and `course-flows.R`'s precompute
rebuilt on them. Then the Admin > Mappings surface for code history.

**Not doing.** Rewriting saved rows to the new code: the code the registrar
used that term is a fact about the term. A surrogate integer id: a saved key
is a migration every time it moves. Inferring successions at runtime from
titles: the title screen proposes one-to-one matches only, because a
many-to-many group needs a person. Recording a split: a course that becomes
two courses is two courses.

### Not doing this

Every new analysis keeps choosing its own "enrolled", its own next-term
lookup and its own unit column, and the disagreements stay invisible until
someone compares two pages. The deploy gate keeps rebuilding four tables per
CSV edit. The vocabulary splits recur the next time a report changes.

---

## Open questions

1. `cedar_registrations` vs `cedar_class_lists`: decide before step 5.
2. Pulls layer: full extracts or a changes-only log? Size it first.
3. ~~Does the renaming crosswalk live in a mapping file or derive from
   DESR history?~~ Answered by step 4: both. The screen derives candidates;
   the file holds the confirmed rows.
4. Which measure columns on `cedar_student_terms` need a campus variant
   (home campus is a dimension; delivery campus is on the attempt).
