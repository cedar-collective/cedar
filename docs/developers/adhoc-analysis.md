---
title: Ad-Hoc Checks and Prototyping
parent: Developer Guide
nav_order: 28
---

# Ad-Hoc Checks and Prototyping

How to answer a question that no test failure can answer — running CEDAR functions against fixtures or real data outside Shiny, building text-first feature previews, and proving that a new test actually catches its bug.

## Ad-hoc checks against real data

Do not hand-roll the bootstrap; it has four separate gotchas. Source the helper:

```bash
Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'
```

It sets `cedar_base_dir` and `cedar_data_dir` (both required globals with no
defaults), loads the CEDAR functions, and lazily exposes the cedar tables.
For method development, keep a vanilla R process alive, source this helper once,
materialize only the required tables, and re-source changed branch/cone files
without reloading the data. The full workflow, evidence boundaries, invalidation
rules, and projection example are in `docs/developers/testing.md` under
**Computational Prototyping Without Shiny**.

## Text-first feature previews

For a computation-heavy feature, stabilize a canonical non-Shiny text preview
before building or revising its Shiny surface. The preview must be a committed
production formatter over the feature payload or validated saved artifact, not
a scratch script and not a second implementation of the analysis. It should
show the scope, terms, measures, selected method, confidence/caveats, and recent
evidence that the UI is expected to expose.

The formatter owns display formatting only. It never recomputes business logic,
and neither tests nor the eventual UI may parse its rendered text; both consume
the underlying typed payload. Exercise the formatter with committed `testthat`
expectations, then print it from the persistent real-data lab while iterating.
This is the preferred fast loop for computational and table-contract work.

A text preview is computational evidence, not UI evidence. Changes to layout,
reactivity, accessibility, CSS, routing, or browser behavior still require the
Dockerized app and browser checks below. Do not add a one-off preview script
when a canonical formatter exists. `format_enrollment_projection_preview()` is
the worked example.


## Ad-hoc checks against fixtures or real data

Some questions cannot be answered from a test failure diff: *how many rows does this actually affect*, *does this grouping change a real number*, *is this leak material*. Those need a scratch script, and writing one is correct — it is how the campus leak was quantified and how a repeater double-count was found. Keep them in the scratchpad directory, never in `tests/`.

The helpers set `cedar_base_dir` from the working directory, so `setwd("tests/testthat")` first:

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)   # cone/branch functions
source("setup.R")                                  # fixtures: test_students, test_sections, ...
suppressMessages(library(dplyr))

# Real data lives at ../../data/*.qs and is qs2 format.
# qs::qread() and qs2::qd_read() both fail on these files.
students <- qs2::qs_read("../../data/cedar_students.qs")
```

Run it with `Rscript --vanilla <script.R>`.

Two things the helper does not do for you, both of which look like broken code:

- **`optparse` is not loaded.** Anything reaching `filter_class_list()` —
  including `prepare_course_attempts()` — fails with
  `could not find function "print_help"`. Add `library(optparse)`.
- **An empty `opt` is a CLI path, not a no-op.** `prepare_course_attempts(s, list())`
  hits `filter_DESRs`/`filter_class_list`'s "no filters supplied" branch, which
  calls `print_help(opt_parser)` and dies on a global that only exists under the
  CLI. Pass at least one real filter: `list(course = "ENGL 1120")`.

## Prove a new test actually catches the bug

A test written alongside a fix usually passes for the wrong reason. Before trusting it, reintroduce the bug and confirm it fails:

```bash
cp R/cones/thing.R /tmp/thing.bak
# revert the fix by hand or with a small sed/python edit
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect FAIL
cp /tmp/thing.bak R/cones/thing.R
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect PASS
```

Do this for any test guarding a join key, a grouping grain, or a dedup — those are the ones that silently pass when the fixture is too simple to express the failure.

