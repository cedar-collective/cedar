---
title: Campus Policy
parent: Developer Guide
nav_order: 23
---

# Campus Policy

Why every course-level analytic is grouped by campus, what that requires in practice, the two campus fields, and the deliberate exceptions. `AGENTS.md` carries the rule; this page carries the reasoning.

**Any analytic grouped by course must also be grouped by campus.** Wherever `subject_course` appears in a `group_cols` vector, a `group_by()`, a `count()`, or a join key, `campus` belongs beside it. This is not a display preference — it is the same class of rule as the DFW policy above and is not negotiable per-cone.

UNM is not one campus. `cedar_students` carries ten campus codes:

| | Code | Share of enrollment rows |
|---|---|---|
| Main | `ABQ` | 61% |
| Online | `EA` | 24% |
| Branch | `GA` `VA` `TA` `LA` `EW` `EF` `ELA` `TAQ` | **15%** |

**21% of all courses (1,310 of 6,244) are taught on more than one campus**, and they are the high-enrollment ones people actually analyse. The largest Gen Ed courses each run on six campuses and draw a quarter to a third of their rows from branches:

| Course | Rows | Campuses | Branch share |
|---|---|---|---|
| `ENGL 1120` | 26,419 | 6 | 26.9% |
| `SPAN 1110` | 17,252 | 6 | 35.7% |
| `COMM 1130` | 15,002 | 6 | 30.6% |

## Why this is a silent-wrongness rule

Main campus is the default reading of every number in the app. Nothing on a course-level chart says "this includes Gallup, Valencia, Taos, and Los Alamos," so a campus-blind aggregate quietly folds a fifth of a different institution into what a chair reads as their own course. The failure mode is not an error or an empty table — it is a plausible number that is wrong by 25–35%, which is why it survives review.

Grouping is also **not** the same as filtering. Filtering to `ABQ` answers one question and discards the rest; grouping keeps every campus visible as its own row and lets the reader see the gap. Prefer grouping. A campus filter is a user's choice about scope, never a substitute for the grouping key.

## What this requires in practice

- **Group, don't just filter.** `group_cols = c("campus", "department", "subject_course")`, not `c("department", "subject_course")`.
- **Carry campus through every join.** A table that is one row per campus joined on `(department, subject_course)` fans out silently and attaches the wrong comparison value. Campus goes in the join key too. See `R/features/gen-ed.R` for the worked example — an instructor is compared against the course rate *on the campus they taught on*.
- **Carry campus into plot keys.** A chart keyed on `subject_course` alone puts two campuses at the same axis position and draws one over the other with no warning. See `instructor_dfw_plot` in `R/modules/gen-ed.R`.
- **Keep headline totals independent of the display grain.** If a summary number is summed out of a table that applies a small-cell guard per campus row, changing the grouping moves the headline as a side effect. Compute totals from their own unfiltered pass.
- **Sibling tables on one page must share a grain.** If one table is per campus and the next is not, the same course shows a different number of rows in each and the page reads as though the data disagrees with itself.

## Two campus fields, and why filtering on the wrong one leaks

`cedar_students` carries **both**:

| Column | Meaning | Lives on |
|---|---|---|
| `campus` | the campus that **taught the section** | `cedar_students` |
| `student_campus` | the student's **home campus** | `cedar_programs`, `cedar_students` |

**They disagree on 28% of enrollment rows.** Albuquerque-home students take 404,684 rows online through EA and roughly 61,000 rows at branch campuses. A filter on `student_campus` therefore does *not* keep branch-delivered course rows out of a main-campus view — course-level analytics must scope on `campus`.

Use `cedar_filter_campus()` / `cedar_require_campus()` from `R/lists/campuses.R`, and `CEDAR_CAMPUS_DEFAULT` (`ABQ` + `EA`) for filter-bar defaults rather than a bare `c("ABQ", "EA")` literal.

## Cohort vs outcome

Scoping the cohort is not the same as scoping the outcome, and conflating them creates a different wrong number. Retention is the worked example: the *cohort* is campus-scoped (a student who took the course at Gallup is not in the Albuquerque cohort), but the *outcome* — still enrolled anywhere at UNM — is deliberately UNM-wide. Narrowing the outcome lookup to the cohort's campus would silently redefine retention as "stayed on the same campus" and count every inter-campus transfer as attrition. See `.build_registered_lookup()` in `R/cones/course-retention.R`, which is commented as the one deliberate UNM-wide aggregate in that file.

## Deliberate exceptions

`get_course_pairs()` in `R/cones/pathway.R` scopes by campus but does **not** put campus in the pair key. A pair is a statement about one student taking two courses, and those can legitimately sit on different campuses — an Albuquerque student taking the follow-on online is an ordinary path. Forcing one campus onto the row would either drop those pairs or label them with a campus half the pair does not belong to. Exceptions like this are allowed; they must be commented at the site with the reason.

`get_course_timing()` takes the same exception under `opt$group_campus = FALSE`, and only under it. The default keeps campus in the key. Pass `FALSE` when the row is a statement about one student's path through the curriculum — a student who took ENGL 1120 online and PSYC 1110 in Albuquerque has one trajectory, and splitting them by delivery campus both answers a different question and halves every count on a small population. It also puts two tiles at the same heatmap coordinate, which `plot_curriculum_map()` draws one over the other. A delivery-mix or course-audience view must keep the default.

Enrollment projections have one further named exception:
`market_id = "abq_ea_course_market"`. For the monitored Gen Ed/FYEX/gateway
scope, ABQ and EA are substitutable deliveries of one planning market: online
enrollment is strongly governed by the seats offered, so separate campus series
mostly forecast allocation rather than demand. The projection branch must
prefilter to the market's declared campuses, count each student-course once
across them, pool capacity, and save every campus/part-term row in
`delivery_components`. It must never label the result as an ABQ campus metric,
include a branch campus, or discard the components. Other analyses may not infer
an exception merely because they also use `CEDAR_CAMPUS_DEFAULT`.

## Audit enforcement

No active delivery-level course metric is exempt from the campus policy. A
campus-neutral curriculum, trajectory, or explicitly named planning-market
operation must carry a nearby
`CAMPUS_ROLLUP:` comment explaining why no single delivery campus belongs on
the result. `tests/testthat/test-architecture.R` enforces that marker for
literal `subject_course` groupings, while multi-campus fixtures pin the actual
behavior of delivery metrics. See the
[campus-grain audit](docs/developers/campus-grain-audit-2026-08.md) for the
completed 1.0 inventory.

The unfinished Healthcare what-if surface was retired before 1.0 rather than
shipping a campus-blind projection.
