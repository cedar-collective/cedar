---
title: Field Reliability Contract
parent: Developer Guide
nav_order: 20
---

# Field Reliability Contract

Which `academic_studies` fields may be used in a claim about a past term, the measurements behind the verdict, and the sanctioned replacements. The rule itself is summarized in `AGENTS.md`; this page is the evidence.


**This is a hard rule, in the same class as the campus and DFW policies.** It exists because MyReports' Academic Studies report returns *cumulative* figures as of the moment you pull, stamped onto every historical row it hands back. A row keyed `(student_id, term = 202180)` does not necessarily describe Fall 2021.

### The two tests

A field may be used in a claim about a past term only if it passes **both**:

1. **Pull independence.** Re-pulling the same `(student, term)` later returns the same value. If it drifts, the field records "now", not "then", and no pull cadence fixes that.
2. **Within-history variation.** Inside a *single* pull covering many terms, the value moves from term to term for the same student. A field frozen across a student's own history cannot be a timeline no matter how stable it is.

A field passing only (1) is stable but static. A field passing only (2) does not exist in practice. Both, or the field is off limits for temporal claims.

### Measured verdict

Test 1 compares a 2025-02/03 pull against the 2026-03 full historical re-pull on the same `(ID, term)`. Test 2 asks whether the value varies across a student's own terms *within* the 2026 re-pull alone (27,795 students with 5+ terms).

| Field (`academic_studies`) | Survives re-pull | Varies across terms | Verdict |
|---|---|---|---|
| `Semester Credits Attempted` | 100.00% | 97.96% | **safe** |
| `Semester Credits Earned` | 99.97% | 98.05% | **safe** |
| `Total Credits` | 99.92% | 98.54% | **safe** — per-term load, *not* a running total |
| `Semester GPA` | 99.98% | 98.16% | **safe** |
| `Student Classification` | 99.82% | 74.00%, never regresses (n=30,098) | **safe** |
| `Student Level` | 100.00% | — | **safe** |
| `Academic Standing` | 100.00% | 7.40% | safe; genuinely rarely changes |
| `Major` / program | 80.6% raw, **99.2%** after normalising the `Pre-` prefix | — | **safe** with caveat |
| `Institution Credits Attempted` | ~92%* | **16.25%** | **BANNED for per-term claims** |
| `Institution Credits Earned` | ~92%* | **16.25%** | **BANNED for per-term claims** |
| `Overall Credits Attempted` | ~92%* | **16.15%** | **BANNED for per-term claims** |
| `Overall Credits Earned` | ~92%* | **16.14%** | **BANNED for per-term claims** |
| `Institution GPA` | — | **16.25%** | **BANNED for per-term claims** |

\* Read that column as unreliable good news: the cross-pull overlap skews toward students who had stopped accruing credits, so their totals could not drift. The within-re-pull figure is the sound measurement, and it is damning.

The canonical illustration, one student's entire history as returned by the **single** 2026 re-pull:

| term | sem att | sem earned | Total Credits | Institution Cr Earned | Overall Cr Earned | classification |
|---|---|---|---|---|---|---|
| 202180 | 16 | 16 | 16 | **129** | **139** | Freshman, 1st Yr, 2nd Sem |
| 202210 | 16 | 16 | 16 | **129** | **139** | Sophomore, 2nd Yr |
| 202280 | 18 | 18 | 18 | **129** | **139** | Junior, 3rd Yr |
| 202310 | 16 | 16 | 16 | **129** | **139** | Nursing, Lvl I |
| 202410 | 16 | 16 | 16 | **129** | **139** | Nursing, Lvl IV |
| 202460 | 15 | 15 | 15 | **129** | **139** | Nursing, Lvl V |

A freshman with 129 earned credits. The per-term columns are right; the cumulative columns are that student's 2026 totals printed six times.

### What this permits and forbids

**Permitted:** when a student took a course; when they changed program and to what; their classification, level, standing, per-term credit load and per-term GPA at any past term.

**Forbidden:** any "how far into their degree were they" claim sourced from the banned fields — credit bands on a timing axis, "credits at the time of the major change", "credits at first declaration", credit-band cohorts. Use one of the two sound replacements below.

### The two sound replacements

- **`cedar_student_term_credits`** — built in `transform-to-cedar.R` from the per-term fields, so it inherits their reliability. `cumulative_completed_unm_credits` is a genuine running total. UNM-only, so a transfer student places earlier than their true standing; History graduates carry a median 58 UNM credits against 129.5 on the degree record, and the upper bands thin out badly (eligibility 101, 80, 33, 16, 4). Biology is healthy on the same axis (453, 407, 285, 209, 60). Never assume a population whose UNM record is complete arrived with no credit.
- **`build_gpa_timeline()`** in `R/branches/gpa-timeline.R` — a cumulative GPA that moves, rebuilt as a credit-weighted running mean over class-list grade points. `gpa_entering` is the matchable one: it excludes the term's own grades, which in a course-effect study *are* the outcome. Validated where the frozen field is right — `inst_gpa` is stamped at pull, so it should equal a student's true cumulative GPA at the **end** of their record and nowhere else; for students whose whole history is in-window the reconstruction lands within a median of **0.090** of it (85% within 0.25, r = 0.937). Not Banner's official GPA: UNM's repeat policy replaces the earlier grade of a repeated course, this counts both attempts.
### Descriptive vs matched — a pull-stamped field is not simply banned

The two tests decide whether a field may make a claim **about a past term**. They
do not make a frozen field worthless; they decide what job it can hold.

`inst_gpa` is the worked example. It may not be *matched* on: measured at the
pull, it postdates both the treatment and the outcome, so balancing on it partly
balances on the outcome and biases the effect toward zero. But it is a sound
*description* of where a student stands now, and on coverage it beats the
reconstruction badly — 166,859 students against 41,016 (25%), because the rebuilt
series loses left-truncated students, first graded terms, and any UNM coursework
predating the window.

So Course Dynamics shows both, in different places: `cum_gpa_entering` in the
balance table, `current_unm_gpa` in the group profile, with on-screen text saying
which is evidence of comparability and which is not. Measured gap between them:
median 0.142, worst at a student's first term (0.220; 44.8% differ by >0.25),
with the signed error growing +0.005 → +0.081 across a career as the frozen value
folds in later work.

**The rule:** a frozen field is barred from *temporal claims and from matching*.
It may still be displayed as a current-state description, provided the page says
so. Putting one in a balance table is the error; putting one in a profile beside
a clear label is not.

- **`student_classification`** — per-term, pull-stable, monotone in 100% of 30,098 students with 3+ classified terms, and transfer-aware because Banner classifies on total earned hours. The honest answer to "where in the degree". Caveat: 33 distinct values; professional ladders (`Nursing, Lvl I–V`, `Law, 3rd Yr`, the `Graduate,` family) do not map onto Freshman/Sophomore/Junior/Senior and are dropped by a naive four-way mapping.

`relative_term` (terms enrolled) needs no credit data at all and stays populated to the tail, but measures time at UNM rather than degree progress, and normally requires an `opt$start_classification` filter against left truncation — unnecessary for a cohort *defined* as starting inside the window, e.g. `get_gen_ed_grad_cohort()`.

### Small-cell guards are mandatory on any progress axis

Eligibility thins sharply toward the far end of every one of these axes. `pct_pop` will report one student over four eligible as "25%", visually identical to a 23% built on 101. Guard the **band** (minimum students who reached it) and the **cell** (minimum students in it) separately — they fail differently. `get_gen_ed_grad_profile()`'s `min_band_n` / `min_n` are the worked example.

### Where the sound replacement lives

`build_credit_timeline(term_credits, programs, opt)` in `R/branches/credit-timeline.R` is the single
sanctioned source for a per-term credit position. It returns `unm_credits_entering` /
`unm_credits_after` (class-list series) and `total_credits_entering` / `total_credits_after` (plus a
transfer block recovered as `overall_credits_attempted - inst_credits_attempted`, a difference taken
at one instant and so immune to the freeze), with `timeline_valid` marking students whose UNM history
predates the data window. `attach_credit_position()` joins it onto any event table.

Validated against the shared data: the reconstruction moves across a student's terms **100%** of the
time (the frozen columns: 16%), and at a student's first term the frozen field overstates the
position by a median of **84 credits** (117 vs 6), converging to 9 by term 8.

### `timeline_valid` is not optional — filter on it

Fixing the freeze introduces a *different* exposure, and a consumer that takes the credit columns
without the flag trades one silent wrongness for another. The running total starts at zero on the
student's first term **in the data**, so anyone already enrolled when the window opens begins
mid-career reading zero. Measured on current data: **30.1%** of students are left-truncated, and
**100%** of them read 0 credits entering their first in-window term. The error only ever points one
way — truncated students shift *left* — so an unguarded map shows coursework happening earlier in a
career than it does, and the contamination worsens across the bands (32% of records in 0–30, **71%
in 150+**).

Any surface placing students on a credit axis must drop `timeline_valid == FALSE` rows (failing
closed on NA) and **say how many it dropped**. `get_course_timing()` does this for all three credit
axes and reports the count as `timing_meta$n_truncated`, which the Pathways scope bar prints.

`student_classification` is the axis with no such requirement: it varies within a student's history
for **63.9%** of students with 3+ terms, so it is a genuine per-term field by the second reliability
test and needs no cohort restriction. It is the default x-axis in Pathways → Course Timing for that
reason. Prefer it unless the question is specifically about credit progress.

**Every consumer has been migrated.** None of them falls back to the banned fields when
`term_credits` is absent — they return NA and say so, because a missing number is visible downstream
and a wrong one is not:

| Consumer | What it now reads |
|---|---|
| `detect_major_changes()` | position after `prev_term` (the decision point), via the timeline; `credits_position_valid` per event |
| `avg_credits_before_major()` | excludes events without a usable position and reports `n_excluded_position` per major |
| `get_declaration_context()` | position entering the declaration term |
| `get_course_timing()` | `inst_credit_band` / `overall_credit_band` / `unm_credit_band` all resolve through the timeline |
| Pathways movement cards | `credit_at_term()` helper in `R/modules/pathways.R` |

### Adding a field

Any new `academic_studies` field used in a temporal claim must be run through both tests and added to the table above before it ships. `tests/testthat/test-field-reliability.R` holds the fixtures and the assertions.
