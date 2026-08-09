# ADR-001: Move CEDAR's tables from report-shaped to domain-shaped

- **Status:** Proposed — targeted at 1.x, explicitly *not* 1.0
- **Date:** 2026-07-31
- **Supersedes:** nothing. Complements
  [source-to-cedar-manifest.md](source-to-cedar-manifest.md) and
  [mapping-audit-2026-07.md](mapping-audit-2026-07.md).

---

## Context

CEDAR's five tables are 1:1 with UNM MyReports **reports**, not with domain
**entities**:

```
DESRs            → cedar_sections
class_lists      → cedar_students
academic_studies → cedar_programs
degrees          → cedar_degrees
hr_data          → cedar_faculty   (frozen; see manifest §5)
```

That was a reasonable starting point — it is how the data arrives. But the
schema now inherits the reporting system's shape, with three consequences.

### 1. Student-term facts are stored two to four times

`student_level`, `student_classification`, `student_campus`, and
`student_college` are **student-term facts** — one value per student per term.
They are materialized in two tables:

| table | rows | distinct student-terms | over-storage |
|---|---|---|---|
| `cedar_students` | 1,687,084 | 424,788 | **4.0×** |
| `cedar_programs` | 464,011 | 318,748 | **1.5×** |

Both are internally consistent (0 student-terms with conflicting values in
either table). The duplication buys nothing.

### 2. The duplication caused three vocabulary splits

Because each copy was mapped independently from a different report, the same
column name holds different vocabularies:

```
cedar_students.student_level   ← `Student Level Code`   → UG, GR, AD …
cedar_programs.student_level   ← `Student Level`        → Undergraduate …
```

Same for `student_campus` and `student_college`. Measured overlap: **0%**. A
cross-table filter returns zero rows rather than erroring. Before the
source-to-CEDAR mapping was standardized, call sites compensated locally with
filters like `== "UG"` on one table and `== "Undergraduate"` on another.

### 3. It hides snapshot skew

Joining the two tables on `student_id + term` and translating vocabulary:

```
campus (code→name)     82,332 / 82,332 agree (100.00%)
level  (code→name)     82,331 / 82,332 agree (100.00%)
classification (raw)   82,214 / 82,330 agree ( 99.86%)
```

The 116 classification disagreements are all **adjacent** levels — Junior vs
Sophomore, Senior vs Junior, Freshman 2nd Sem vs 1st Sem. That is not a mapping
error; it is the class-list and academic-studies extracts being pulled at
different moments. **Nothing in CEDAR compares the two copies, so which answer a
user gets depends on which table their query happened to read.**

This is the strongest argument for the change: normalizing does not merely tidy
the schema, it makes a real class of error *visible*.

---

## Decision

Restructure around domain entities. Facts record events; dimensions describe
entities.

### Facts — one row per event

| table | grain | replaces | notes |
|---|---|---|---|
| **`cedar_registrations`** | **student × section** | `cedar_students` | **The class list.** Grain is unchanged — see below. |
| `cedar_program_enrollments` | student × term × program slot | `cedar_programs` | declarations: major / minor / concentration |
| `cedar_completions` | student × program × term | `cedar_degrees` | awards |

### Dimensions — one row per entity

| table | grain | rows (est.) | notes |
|---|---|---|---|
| `cedar_student_terms` | student × term | ~425K | **the fix** — classification, level, campus, college, residency, standing, GPA, credits, demographics, each stored once |
| `cedar_sections` | term × crn | 242K | the scheduled offering |
| `cedar_courses` | subject_course | ~8K | title, credits, gen_ed_area, level — currently smeared across sections and students |

Under this model, `campus` on a section and `campus` on a student-term are
different concepts living on different entities, so they can no longer collide.
The vocabulary decision is made **once**, in one column.

---

## The class list stays first-class

**`cedar_registrations` is the class list.** This is worth stating plainly
because the rename could suggest otherwise:

- **Grain is identical.** `cedar_students` is already exactly one row per
  student × section — 1,687,084 rows, 1,687,084 distinct pairs, **zero
  duplicates**. The proposed table has the same grain and the same row count.
- **Registration status is the load-bearing fact of the product.** DFW rates,
  census vs current enrollment, early vs late drops, waitlist demand, and
  the entire Course Dynamics tab derive from `registration_status_code`. Nothing
  about this proposal dilutes it.
- **What changes is only what gets removed:** the ~20 denormalized columns
  describing the *student* (`student_level`, `student_campus`, …) and the
  *course* (`course_title`, `level`) move to the dimensions they belong to. The
  registration facts — `registration_status_code`, `registration_status`,
  `registration_date`, `final_grade`, `credits`, `dual_credit` — stay put.

Naming is an open question. `cedar_registrations` names the fact;
`cedar_class_lists` names the source and matches what users say (the Enrollment
and Course Dynamics tabs both label this data "Classlist"). Either is fine; the
grain and the status columns are what matter. **Decide before migrating.**

### Snapshot vs. history — deliberately deferred

Today a registration is a **point-in-time snapshot**: one row carrying the
status as of the extract. The lifecycle is inferred from the *code* (DR/DD =
pre-census, DG/DW = post-census), not from dated transitions.

An event-grained alternative (one row per status change) would let CEDAR say
"this course lost 12 students in week 3" rather than "12 students hold DG." It
is **not proposed here**, because the data will not currently support it:

```
registration_date populated: 14.5%   (only from 2025-03-31 forward)
```

Historical drop timing does not exist to be modeled. Revisit if
`registration_date` coverage improves; the snapshot model is correct for the
data we have.

---

## What this unlocks for other institutions

Today, onboarding says *"produce a MyReports class-list export."* That asks
another university to reproduce UNM's reporting quirks.

Under a domain model it becomes *"give us registrations, student-terms,
sections, courses, program declarations, completions"* — concepts every SIS has,
whatever the vendor. **The MyReports extracts become one adapter among several
rather than the definition of the schema.**

This also reframes the manifest: §1–5 currently document *UNM's reports*. They
should document *CEDAR's domain*, with a UNM/MyReports adapter appendix showing
which source field fills each slot.

---

## Consequences

### Costs, stated honestly

**Denormalization is not a mistake here.** CEDAR's queries are overwhelmingly
"filter enrollments by student attributes," which today needs zero joins. What
CEDAR has is effectively One Big Table; this proposes a star schema. Both are
legitimate. The problem is not that the data is denormalized — it is that the
denormalization was *inherited from report shapes rather than chosen*, so no
copy was ever declared authoritative.

**Migration surface is real:** ~310 references across **26 files**
(`major_code` alone accounts for 160).

**Query cost:** every student-attribute filter gains a join from a 1.69M-row
fact to a 425K-row dimension. Trivial for dplyr/arrow at this scale, but not
zero, and it touches hot paths (Regstats, Enrollment, Pathways).

### Migration path — strangler, not big bang

Because the duplicated attributes are already 100% internally consistent, this
can be incremental:

1. **Build `cedar_student_terms` in the transform** as a derived table, with a
   **declared precedence** for which source wins when the snapshots disagree.
   This alone makes the classification skew explicit instead of arbitrary.
   *Roughly a day; delivers most of the value.*
2. **Leave existing columns in place.** Nothing breaks; no reader changes.
3. **Migrate readers opportunistically**, the way C1's plotly conversions ride
   along with files already being touched.
4. **Drop the duplicated columns** once the last reader is gone.
5. **Split `cedar_courses` out of sections/students**, then rename the fact
   tables.

Steps 1–2 are safe to do at any time, including during 1.0 stabilization, since
they are additive. Steps 3–5 are 1.x.

### Not doing this

The vocabulary splits stay, and every future author has to know that
`student_level` means different things in different tables. BACKLOG **F4**
covers the tactical patch (assert the mapping, block cross-vocabulary filters);
that closes the trap but leaves the duplication and the snapshot skew.

---

## Open questions

1. `cedar_registrations` vs `cedar_class_lists` — decide before migrating.
2. Precedence rule for `cedar_student_terms` when snapshots disagree: prefer the
   later `as_of_date`, prefer academic_studies, or record both and flag?
3. Does `cedar_courses` need a term dimension (catalog attributes change), or is
   subject_course sufficient?
4. Do the person-level attributes (`ipeds_race`, `gender`, `first_gen`) belong
   on `cedar_student_terms` or on a separate `cedar_students` person table?
