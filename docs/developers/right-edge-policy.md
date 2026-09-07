---
title: Right-Edge Policy
parent: Developer Guide
nav_order: 22
---

# Right-Edge Policy

Why the right edge of the data is not one number, which edge each kind of analysis uses, and the measured failures that established the rule. `AGENTS.md` carries the rule; this page carries the reasoning.

**Roadblocks observation grain:** `get_stopout()` selects the first eligible
outcome per student/course/delivery campus after scope, population-window, and
right-edge filtering. Agreeing first-term records collapse; conflicting first-term
outcomes exclude the comparison and are reported in `observation_info`. Counts,
rates, DFW context, and chi-square tests use the same selected observations.
Later enrollments remain available to the separate full-history return lookup.
This Roadblocks-specific rule does not change CEDAR's all-attempt course DFW rates;
`get_dfw_rates()` is a separate ever-DFW measure and must not supply Roadblocks context.

**Never bound an analysis with `max(term)`, a hardcoded term, or arithmetic on `cedar_current_term`.** Use the edges computed once at startup by `cedar_data_edges()` (`R/branches/data-edges.R`). This is the same class of rule as the campus and DFW policies.

## Why an edge is not one number

CEDAR's local data runs behind the registrar, and a term does not arrive all at once — registration appears months early, grades land weeks late. At any moment the tail looks like this:

| term | rows | graded |
|---|---|---|
| Fall 2025 | 128k | **91%** |
| Spring 2026 | 119k | **7%** |
| Summer 2026 | 15k | 0% |
| Fall 2026 | 85k | 0% |

So "the last term in the data" is at least two different terms depending on what you are asking.

## Which edge

| Edge | Use it for |
|---|---|
| `last_graded` (`cedar_graded_through`) | anything reading a grade: DFW, pass rates, grade distributions, stop-out after a DFW, course outcomes |
| `last_enrolled_complete` (`cedar_report_end_term`) | settled enrollment reporting and the hard observation edge for every longitudinal analysis |
| `last_enrolled` | the raw extent of the data. **Not a reporting boundary** — it includes a term that is still filling |
| `last_degree` | completions |

`cedar_report_end_term` is **no longer hand-maintained**. `global.R` derives it from `last_enrolled_complete`; the config value survives only as a fallback for a snapshot with no `as_of_date`. On current data the derived value matches what the config had been set to by hand, which is the check that it works.

## Settled enrollment, and why not by size

A term counts as settled when the newest pull covering it happened at least `min_days_after_start` days (default 14, clearing add/drop) after the term began. Term start is approximated from the term code — Fall mid-August, Spring mid-January, Summer mid-June.

Comparing a term's row count against the same season in prior years separates the cases just as cleanly today (Fall 2026 sits at 71% of a typical fall). **Do not use it.** A genuine enrollment decline is indistinguishable from an unfinished term under a size rule, so it would quietly truncate reports in exactly the year a chair most needs to see the drop. Pull timing cannot make that mistake — it describes when the data was captured, not how many students exist. There is a test for this.

## Why this is a silent-wrongness rule

Bounding a grade rate by the enrollment edge does not error — it returns a plausible number. Measured before this policy existed: **the DFW rate for Spring 2026 read 0.3% against 6–8% for every other term**, because `prepare_course_attempts()` capped at `cedar_report_end_term` (the enrollment edge) and the denominator counted all 104,431 attempts while the numerator saw only the 7% of grades that had posted. Every DFW surface in the app showed the newest term as a dramatic improvement.

## Why config arithmetic is not the answer

`cedar_report_end_term <- subtract_term(cedar_current_term)` encodes a guess that exactly one term is in flight. It fails both ways:

- **Stale.** Grades land after the term ends; nothing advances until somebody edits config.
- **Overshoot.** A config set ahead of the data nominates a term with no grades at all, and every student in it reads as having no outcome.

`cedar_data_edges()` reads the data, so it is right on whatever snapshot is loaded and moves on its own. `cedar_report_end_term` survives as the *enrollment* edge and as a cache-key component; it is not a grade boundary.

## In practice

- Grade-dependent code uses `cedar_graded_through`; enrollment reporting uses `cedar_report_end_term`. Both fall back to config only when `global.R` never ran (standalone scripts).
- Startup prints all four edges, and says so when a derived value differs from what config arithmetic would have produced.
- The threshold (`min_graded_share`, default 0.5) is not finely balanced — finished terms sit at 83–91% and in-flight terms at 0–7%, so anything from ~0.2 to ~0.8 picks the same edge.
- An edge that cannot be determined is `NULL`, never a guess. Fail closed.
- **Say which edge you used.** `cedar_edge_note()` produces the sentence. A capped view that does not explain itself reads as a stale pipeline; "Spring 2026 is enrolled but not yet graded" reads as a data state and tells the user when it will move.

## Grade outcomes and longitudinal follow-up require two separate right edges

**Do not cap an entire page merely because it contains a longitudinal panel.**
Current registration is valid descriptive data and may appear in Course Dynamics
Overview and other explicitly current-enrollment summaries. The hard right edge
belongs to computations that need comparable history or a later observation:
retention, next-term persistence, course flows, sequence effects, and downstream
success. Those analyses stop at `last_enrolled_complete`. If they also read a
grade, use `cedar_longitudinal_edge(edges, grade_dependent = TRUE)`, which is the
earlier of `last_enrolled_complete` and `last_graded`. Never let a partial current
term enter a longitudinal cohort, lookup, denominator, cache key, or outcome.

This distinction is deliberate: on the August 2026 snapshot, Fall 2026
registration is useful in the Course Dynamics Overview, but longitudinal
sampling ends at Summer 2026, the previous complete term. A page-wide filter
would throw away good current information; no filter would turn advance
registration into apparently observed follow-up.

**A row with no posted grade is unknown, never a failure or a non-pass.** Filter
grade-dependent event rows to `last_graded` *before* selecting an attempt or
classifying its outcome, then pass them through `classify_enrollment_outcomes()`.
Do not use a catch-all branch such as `TRUE ~ "failed"`: blank grades, incomplete
work, audits, NR/NC, and other unclassifiable records must be excluded from the
grade-rate denominator and reported as unobserved.

An A→B analysis also needs an **opportunity edge** for the A cohort. A student
who took A too recently to have the declared follow-up interval before the
longitudinal observation edge has not failed to continue; the record is
right-censored. For a
one-regular-term opportunity window:

1. Compute the first possible follow-up with `add_next_term_col(..., summer = FALSE)`.
2. Exclude A rows whose follow-up term is after `last_enrolled_complete` from the continuation denominator.
3. Report the number excluded and show the data window in the page methodology.
4. Keep this separate from the B outcome edge: a graded B must be at or before the earlier of `last_enrolled_complete` and `last_graded`.

On the August 2026 snapshot, Fall 2026 enrollment is already present but has no
grades, so grade sampling ends at Summer 2026. This is data-derived, not a
hardcoded "current term minus one" rule; on another pull the named terms will
move. The Course Dynamics failure that established this rule was measurable:
33 Fall 2026 ENGL 1120 registrations after Oravetz's FYEX 1030 sections were
classified as failures. Capping at the graded edge changed that group's apparent
ENGL 1120 pass rate from 66.7% (98/147) to 86.0% (98/114 observed outcomes).
The corrected opportunity window excludes 123 of Oravetz's 418 first-attributed
FYEX students because their next regular term falls after the graded edge (90 of
them are Fall 2026 records with no later term in the data at all). Both errors
produced plausible instructor comparisons rather than an exception, which is
why every longitudinal page must display its outcome edge, opportunity rule,
and exclusion counts.

For prerequisite/order questions, distinguish **strictly earlier** (`term_y <
term_x`) from **same-term** (`term_y == term_x`) completion. Concurrent courses
must never be described as having been passed "before" the focal course. When a
single downstream course was already passed in a strictly earlier term, exclude
that student from a progression-to-that-course denominator and surface the count.
For a multi-course rollup, show prior completions as context but do not infer
that passing one member makes the student ineligible for every course in the set.
The worked FYEX 1030 audit illustrates why: among 439 distinct students ever
taught by Oravetz, 38 had passed ENGL 1110 or 1120 in a strictly earlier term,
80 passed one in the same term, and 110 were in the student-level union (8 did
both). Reporting the same-term rows as "passed before," or adding the two counts
without deduplicating, materially overstates the reverse-order population.
