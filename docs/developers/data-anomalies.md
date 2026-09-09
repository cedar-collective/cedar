---
title: Data anomalies and semantic annotations
---

# Data anomalies and semantic annotations

Banner records facts. It does not record that a code changed meaning, that a
program used a major code for intent rather than admission, or that two tables
name the same thing differently. Those are things people learn once, usually the
hard way, and then have to remember forever.

CEDAR has two halves of an answer, and they are deliberately separate.

| | Where | What it is |
|---|---|---|
| **Know** | `R/lists/data_semantics.R` | A registry of what we have already learned, as data |
| **Find** | `R/branches/data-anomalies.R` | Screens that surface candidates for review |

## The one hard rule: annotate, never mutate

An entry in the registry explains what a value *means*. It must never be used to
rewrite rows so they mean something else.

The tempting example is Radiologic Sciences. Before Fall 2026 its major code
recorded intent to enter the program rather than admission to it, so a Pathways
population reads as a third switched out and a third stopped out. Recoding those
historical rows as pre-majors would "fix" the display — and would assert a
per-student fact the data does not support, because some of those students
really were admitted. It would silently change nine years of numbers and leave no
trace. Marking the range as intent-coded is honest; rewriting it is fabrication.

## What belongs where

Three things get called "data anomalies" and they need different homes:

| Kind | Example | The data is | Home |
|---|---|---|---|
| **Mapping error** | `FRAD` resolves to no department | Wrong | `program_code_maps.R` — correct it retroactively |
| **Semantic break** | `RADS` records intent, not admission | Right, but its meaning changed | This registry — warn or exclude, never mutate |
| **Derived measure** | *Which* students were admitted | Absent entirely | Genuinely code; needs a proxy |

The third is the one that cannot be a lookup. No annotation can supply
information nobody recorded, and a registry that pretends otherwise is worse than
none.

A fourth thing deliberately stays out: rules governing what an analysis may **do**
rather than what a value **means**. The field-reliability contract in `AGENTS.md`
is rules plus tests plus documentation, not registry entries, because it
constrains analyses.

## Reading the registry

```r
# Everything, or one kind
cedar_data_semantics()
cedar_data_semantics(kind = "join_hazard")

# What applies to this table, these codes, these terms
notes <- cedar_semantic_notes("cedar_programs", values = "RADS", terms = 202410L)
cedar_semantic_caption(notes)   # summaries, written to show a reader verbatim
```

Term bounds matter: the Radiologic Sciences entry stops at 202610, because from
202660 the `FRAD` pre-major code separates intent from admission on its own. An
annotation that warned forever would become noise.

## The screens

Both come from defects that were found by accident and cost real time.

### `detect_pre_major_self_mapping(programs)`

A pre-major whose `dept_code` equals its own `major_code`. The `dept_code` chain
ends in an identity fallback so the column is never NA; for a declared major that
is often correct — `RADS` really is the RADS department — but for a **pre-major**
it is always a mapping failure. The result is indistinguishable from a correct
answer, and `cedar_mapping_issues` never sees it because the row *is* mapped.

That is how Radiologic Sciences reported 35 students at department level when it
had 229 (ISSUES.md I7). The screen flags **22 codes** on current data.

### `detect_selective_admission_signal(programs, degrees, opt)`

Programs carrying far more declared majors than they graduate. A multi-year
program always carries more; the typical CEDAR program sits near **2**.

Measured distribution, undergraduate majors against baccalaureate degrees,
2024 onward, programs with ≥40 majors and ≥3 graduates a year (42 programs):

| median | 75th | 90th | 95th | max |
|---|---|---|---|---|
| 2.2 | 2.7 | 3.9 | 5.3 | 8.2 |

The default `min_ratio = 4.0` sits near the 90th percentile — about twice a
typical program. On current data it flags four:

| Program | Majors/term | Graduates/yr | Ratio |
|---|---:|---:|---:|
| Spanish | 112 | 13.7 | 8.2 |
| Radiologic Sciences | 100 | 14.7 | 6.8 |
| Dental Hygiene | 123 | 23.3 | 5.3 |
| Medical Laboratory Sciences | 70 | 14.7 | 4.7 |

**A screen produces candidates, never verdicts.** Spanish outranks Radiologic
Sciences, and they are not the same phenomenon — one is a competitive-entry
health program, the other is something a person has to look into. Anything that
acted on this ratio automatically would be inventing conclusions.

**Pair the student level with the award category.** They are one choice, not two.
Counting graduate majors against baccalaureate degrees inflates the ratio for
every program with a large graduate population: Special Education scored 13.4
that way and Physics 9.9, both artifacts, and both disappeared once the level was
paired. `test-data-anomalies.R` guards this specifically.

## Adding an entry

1. Establish the fact and write the measurement into `evidence`. An entry without
   evidence is folklore, and nobody can recheck it later.
2. Bound it. If the condition ends at a known term, say so, or the annotation
   becomes permanent noise.
3. Decide `warn` or `exclude`, and never `mutate`.
4. Prefer a screen if the condition is detectable. A rule that finds the next
   instance is worth more than an entry describing this one.

## Where this does not reach

The registry can tell a reader that Radiologic Sciences outcomes describe an
admission funnel. It cannot tell them which students were admitted, because
nobody recorded it. That needs a derived proxy — first enrollment in a
professional-sequence course, say — which is a computed measure, opt-in, and
clearly labeled when it arrives. It is not part of this system and should not be
folded into it.
