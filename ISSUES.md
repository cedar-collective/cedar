# CEDAR Issues

Known defects in CEDAR — code or data — that are not yet fixed. One entry per
issue. This is not a planning document: forward-looking work goes in
`ROADMAP.md`, and finished work lives in git history and the changelog.

**Post an issue here the moment it is discovered**, even if it is going to be
fixed in the same sitting. The point is that a problem found once never has to
be rediscovered from scratch — the evidence and the reproduction go in the entry
while they are still in hand.

Each entry carries: a stable ID, status, the date it was found, what is wrong,
how to reproduce it, and what a fix requires. Resolved issues stay in the file
with `Status: resolved` and the resolving commit, until the next release, so
that a recurrence is recognizable.

---

## I1 — `cedar_programs` and `cedar_degrees` were fragmented into seven student ID spaces

**Status:** resolved 2026-08-12. Repulled `as` + `deg` for 201980–202460, then
(after fixing I3) ran a full transform to land the tables in `data/`. Verified in
the app's own data directory: `cedar_programs` is **one ID space across all 25
terms**, and no table has a term that fails to join. Watch for a recurrence via
Data & Usage → Join Integrity after any future refresh.
**Found:** 2026-08-12
**Severity:** high — silently truncated every cross-table student analysis
**Affects:** `academic_studies.qs` → `cedar_programs`, `degrees.qs` →
`cedar_degrees`. Class-list-derived tables were always clean.

### Correction to the first diagnosis

This was initially recorded as *two* disjoint ID spaces, split at 202480. That
was wrong, and wrong in a way worth remembering: the first pass only ever asked
"does this term join to the class lists?", which is a test against one external
reference. It never asked whether the failing terms joined to *each other*.
Pairwise overlap within `cedar_programs` showed **seven** disjoint spaces:

| cluster | terms |
|---|---|
| 1–5 | `201980` / `202010` / `202060` / `202080` / `202110` — five singletons |
| 6 | `202160, 202480, 202510, 202560, 202580` — matched the class lists |
| 7 | `202180 … 202460` — nine terms, internally coherent, matched nothing else |

Cluster 7 had normal term-to-term persistence (89%, 84%, 87%), so it was a
healthy ID space that simply could not reach anything outside itself. That
structure confirmed the per-file mechanism below: the `2025-02-28` ingest batch
(202180–202460) stayed coherent, while the `2025-03-21` batch (201980–202160)
shattered into six spaces — one per file, with 202160 landing by luck in the
format that matched everything current.

**Lesson for the next check of this kind:** a spine comparison finds tables that
cannot join outward. It cannot see fragmentation *within* a table. Cluster the
terms by shared IDs.

### What was wrong

The hashed `student_id` in `cedar_programs` and `cedar_degrees` belonged to one
of the seven mutually incompatible spaces above, depending on which MyReports
file supplied that term. Records outside cluster 6 could not join to
`cedar_students` at all, and could not join to the *same student's* records in
another cluster within their own table.

Per-term match against `cedar_students` was never partial — exactly 0% or
exactly 100%:

| terms | match |
|---|---|
| 201980–202110, 202180–202460 | **0%** |
| 202160, 202480, 202510, 202560, 202580, 202610 | 100% |

Within `cedar_programs` alone: 37,802 ids lived in the matching terms, 133,617
across the others, and the intersection was **zero**. One person therefore
appeared under a different id in each cluster they touched, which is why the
table reported 171,419 distinct students when the class lists saw 95,542 over
the same window. It also produced 12,504 ids holding exactly one program term —
the five singleton clusters — none of which can generate a change event, since
detecting one requires two consecutive records under the same id.

The decisive check: 18,233 students appear in `cedar_students` at both 202410 and
202480 — same id string, same table, unambiguously the same people. Of those,
15,681 have a program record at 202480 and **zero** have one at 202410. They were
plainly enrolled and declared in 202410; those rows exist, under a different hash.

### Consequences

- Any population built from `cedar_programs` loses all class-list coursework for
  pre-202480 terms. A History population of 1,645 students resolves to 330 with
  any enrollment rows, and coverage is binary by term — 0 or 100, never between.
- `detect_major_changes()` cannot see a switch that crosses 202460 → 202480, and
  reads pre- and post-boundary records as different people. Only 1,196 of 171,419
  program ids span that boundary.
- Distinct-student counts taken from `cedar_programs` are inflated by
  double-counting.
- Credit and GPA timelines, Pathways populations, Roadblocks, and the Major
  Changes course tables all inherit the truncation.

### Root cause

The divergence is already present in the raw MD5 ids in `academic_studies.qs` and
`degrees.qs`, so it is upstream of `encrypt_if_needed()` in
`R/data-parsers/transform-to-cedar.R` — that function is deterministic and is
being fed mismatched input.

`R/data-parsers/parse-data.R` hashes only newly ingested rows (`# only encrypt new
data!`, ~line 558), so each term's MD5 is frozen at whatever the raw ID string
looked like in the file it arrived in. The file is read with a bare
`fread(csv_file)` (~line 490) with no `colClasses`, so the ID column's type is
inferred per file. A column read as numeric loses leading zeros; the same column
read as text keeps them. Same person, two different strings, two different MD5s.

That the split varies *within* a single download batch supports this: in both
`academic_studies` and `degrees`, the 2025-03-21 batch covers six terms and only
202160 matches — consistent with per-file type inference rather than a per-batch
setting.

**This can recur on any future pull** until the ID column is forced to character
at read time.

### Reproduction

In the running app: **Data & Usage → Join Integrity**. Every table should read
`consistent`; any `split` verdict is this issue, and the by-term table lists
exactly which terms need repulling.

From RStudio:

```r
check_student_id_integrity(
  spine  = load_cedar_data("data/cedar_students.qs"),
  tables = list(
    cedar_programs = load_cedar_data("data/cedar_programs.qs"),
    cedar_degrees  = load_cedar_data("data/cedar_degrees.qs")
  ),
  opt = list(spine_name = "cedar_students")
)$by_table
```

### What a fix requires

1. ~~Force the ID column to character at read time in `parse-data.R` so the hash
   cannot depend on type inference.~~ **Done 2026-08-12** — `fread()` now takes
   `colClasses = list(character = report_spec$ID_col)`, and a named ID column
   missing from the CSV is a hard error rather than an `fread` warning.
2. ~~Repull and re-ingest the affected terms.~~ **Done 2026-08-12** — `as` and
   `deg` for 201980–202460. Result in `shared-data/`: `cedar_programs` 616,627
   rows / 86,583 ids, one ID space across all 25 terms, zero non-joining terms;
   `cedar_degrees` likewise. Terms 201980–202610 all match the class lists at
   100%. The remaining partials are expected, not defects: 201880/201910/201960
   predate the class-list window, and 202680 is a future term whose students have
   not enrolled yet.
3. ~~Get those files into the app's `data/` directory.~~ **Done 2026-08-12** —
   the copy had never happened because of I3. A full
   `Rscript --vanilla R/data-parsers/transform-to-cedar.R` (no `--tables`; the
   copy loop only iterates the tables that run built, and nine local tables were
   stale, not two) rebuilt and copied all nine.
4. ~~Re-verify.~~ **Done** — in `data/`: 0 tables split, 0 non-joining terms,
   `cedar_programs` in a single ID-space cluster across all 25 terms.

### Result

| | before | after |
|---|---|---|
| `cedar_programs` ID spaces | 7 | **1** |
| distinct ids in `cedar_programs` | 171,419 | 86,583 |
| History population | 1,645 | 883 |
| History departures matchable to coursework | 11 of 43 (26%) | 88 of 104 (85%) |

The id count halving is the fix working: those were never 171,419 people, they
were one person counted once per cluster they touched.

### Repull list

Two MyReports reports, Fall 2019 through Summer 2024:

- **Academic Study Detail Guided** (`Academic_Study_Detail_Guided`)
- **Graduates and Pending Graduates** (`Graduates_and_Pending_Graduates`)

Not needed: Class Lists (the consistent spine, and what everything else is
matched against), DESRs (carries no student ids), Admissions Applicants (already
consistent across all terms).

`parse-data.R` replaces refreshed terms in place, so these can be ingested
without deleting the existing files. Do **not** delete `academic_studies.qs` or
`degrees.qs` to force a rebuild unless every term is being repulled in the same
run — `rebuild = TRUE` fires only when no previous file exists, and would drop
whatever terms are missing from the new pull.

```bash
./scripts/update-data.sh -s 201980 -e 202460 as deg
```

Safe to run in chunks if MyReports struggles with 15 terms — each run replaces
only the terms it fetched.

---

## I2 — `update-data.sh` same-day skip check could not fire for three reports

**Status:** resolved 2026-08-12
**Found:** 2026-08-12
**Severity:** low — failed toward re-fetching, never toward stale data
**Affects:** `scripts/update-data.sh`

### What was wrong

Step 1 skips the MyReports fetch when files for today are already on disk. The
globs it checked had drifted from the filename signatures `parse-data.R`
actually matches on:

| report | glob checked | real signature |
|---|---|---|
| `deg` | `*Degrees*` | `Graduates_and_Pending_Graduates` |
| `as` | `*Academic_Studies*` | `Academic_Study_Detail_Guided` |
| `aa` | *(absent from the case statement)* | `S_Admissions_Applicants_Detail` |

So the check could never succeed for degrees or academic studies, and `aa` fell
through to the unknown-report branch, which logged a warning and `continue`d
without touching `SKIP_FETCH`.

The consequence was only wasted downloads — a failed check leaves `SKIP_FETCH`
false, which fetches. But the `aa` path was the dangerous shape: a report that
falls through the case statement leaves `SKIP_FETCH` at whatever the other
reports set it to, so a request for `aa` alone would have skipped the fetch on
the strength of a check that never ran.

### Fix

Globs now use the exact `filename_sig` strings, `aa` has a branch, and the
fallback branch sets `SKIP_FETCH=false` so an unrecognized report always fetches
rather than trusting a check that could not run. A comment on the block names
`report_specs$<report>$filename_sig` in `parse-data.R` as the thing to keep it in
sync with.

Both sides are still hand-maintained in two languages. If they drift again the
symptom is silent — a redundant download, or in the fallback case a skipped one.
Worth deriving from one source if the parser ever gains more reports.

---

## I3 — `cedar_data_dir` pointed at a nonexistent directory; pipeline output never reached the app

**Status:** resolved 2026-08-12 (config fix). Local `data/` still needs one
transform run to pick up the files it missed.
**Found:** 2026-08-12
**Severity:** high — every data refresh silently had no effect on the app
**Affects:** `config/config.R`, `config/config_template.R`

### What was wrong

```r
cedar_base_dir <- ".../cedar-project/cedar"        # no trailing slash
cedar_data_dir <- paste0(cedar_base_dir, "data/")  # → ".../cedar-project/cedardata/"
```

The template's comment said `cedar_base_dir` "should end in /cedar/", which is
ambiguous about the trailing slash, and `paste0` silently concatenates without
one. The result was a path that does not exist.

`transform-to-cedar.R` guards its copy step with `dir.exists(local_data_dir)`
and, when that fails, prints `⏭ Skipping local data copy (directories not
configured or not found)` and continues. The step is not counted as a failure,
so `update-data.sh` reported every stage ✅ and a green **CEDAR Update
Complete** while the app went on reading whatever was already in `data/`.

This is how the 2026-08-12 repull that fixed I1 appeared to do nothing: it
worked, wrote correct tables to `shared-data/`, and never copied them. Nine
tables in `data/` were stale, some since 2026-08-05, for the same reason.

`config/shiny_config.R` builds the same path with `file.path()`, so the app
resolved `data/` correctly. Only the pipeline's copy target was wrong — which is
exactly why nothing looked broken.

### Fix

Both configs normalize the base with `sub("/+$", "", ...)` and build the
directories with `file.path(cedar_base_dir, "data/")`. The trailing slash is
kept deliberately: `parse-NSO.R` and `parse-HRreport.R` append to these with
`paste0()` and would produce `.../dataHRreports` without it.

The copy step is now loud. `transform-to-cedar.R` distinguishes three cases
instead of two: Docker (skip, correct), no local directory configured at all
(skip, also correct — nothing was asked for), and **configured but missing**,
which now `stop()`s with a message saying the tables were written to
`shared-data/` and no work was lost. A failed `file.copy()` is fatal too: a
half-refreshed `data/` mixes current and stale tables, which is unjoinable in
exactly the way this whole issue was about.

---

## I4 — Pre-change course ratios are confounded by career stage

**Status:** open, deliberately deferred 2026-08-12 (see "Why not now")
**Found:** 2026-08-12
**Severity:** moderate — the number is not wrong, but it invites a wrong reading
**Affects:** `get_pre_change_courses()` in `R/cones/major-changes.R`; surfaced as
the **Times as likely** column in Pathways → Major Changes → Courses in the Term
Before Students Left

### What is wrong

The ratio compares a course's share in the term before a switch against its
share in a typical term for the population. The baseline averages over students
at *every* career stage, but switches are not evenly distributed across a
career — they cluster early. So any lower-division course is over-represented
before a switch for a reason that has nothing to do with switching, and the
ratio reads that as concentration.

### Evidence

History population, 2026-08-12, `min_n = 5`. Every course clearing the threshold
is 1000-level; not one upper-division course appears:

| course | last term | typical | ratio |
|---|---|---|---|
| ENGL 1110 Composition I | 11.4% | 2.1% | 5.5× |
| SOCI 1110 Intro Sociology | 5.7% | 1.1% | 5.1× |
| MATH 1130 Survey of Mathematics | 6.8% | 1.4% | 4.9× |
| MATH 1350 Intro Statistics | 6.8% | 1.8% | 3.9× |
| SPAN 1110 Spanish I | 9.1% | 2.4% | 3.8× |
| HIST 1110 United States History I | 11.4% | 3.2% | 3.5× |
| ENGL 1120 Composition II | 8.0% | 3.6% | 2.2× |
| HIST 1150 Western Civilization I | 5.7% | 2.9% | 2.0× |

Read literally this says Composition I makes people leave History. What it
actually says is that these students were freshmen.

### Why not now

The all-1000-level result is self-evident. A reader looking at that list can see
what is happening without being told, and the section already carries an
interpretive caveat naming career stage specifically.

**Revisit when that stops being true.** The deferral rests on the confound being
visible, so the case to watch for is a population that returns a *mixed* list —
some upper-division courses among the lower-division ones. There the confound is
invisible, the surviving upper-division rows look like the real signal, and
nothing on the page tells the reader which is which. If someone reports a
surprising course from this table, check its level first.

### Possible fix

Compare each switch against baseline terms at a similar career position rather
than against all terms — match on term index (student's nth term) or on the
credit band from `build_credit_timeline()`, and compute the ratio within strata.
Costs statistical power, since each switch then draws on a slice of the baseline
rather than all 26,540-odd student-terms, and small populations may end up with
no usable comparison at all. An alternative that keeps the power is to leave the
ratio as it is and add a course-level column, so the reader can see at a glance
that the top of the list is entirely lower-division.

Whichever way it goes, `R/modules/pathways.R` (section caveat) and Methodology
Step 6 both describe the current unadjusted comparison and would need updating.

---

## I5 — Every 4-digit 3000/4000-level course is classified `lower`

**Status:** open
**Found:** 2026-09-05 (while reconciling the synthetic demo institution with the
browser gate — the Open Seats step asked for `upper` and the fixture's
`HIST 3010` was not in the result)
**Severity:** moderate — silent wrongness. The value is plausible, so nothing
errors and nothing looks unusual; upper-division work is simply counted as
lower-division wherever `level` is used.
**Affects:** `level` in `cedar_sections`, derived in `R/data-parsers/transform-to-cedar.R`
(the DESR branch, ~line 295). Every surface that filters or groups on `level`:
Open Seats, Enrollment, Credit Hours (`credit_hours_data$level`), Dept Trends,
and any `opt$level` filter.

### What is wrong

The rule is ordered so that a 4-digit number can never reach the upper or grad
branches:

```r
level = dplyr::case_when(
  crse_base < 300                    ~ "lower",
  crse_base >= 1000                  ~ "lower",   # <- catches ALL 4-digit courses
  crse_base >= 500 & crse_base < 700 ~ "grad",
  crse_base >= 300 & crse_base < 500 ~ "upper"
)
```

The `>= 1000` branch was written for UNM's 4-digit renumbering, where `1110` is
genuinely lower-division. But it fires for `3010` and `4445` too, before the
`upper` branch is ever evaluated. Under the 4-digit scheme the bands are
1000–2999 lower, 3000–4999 upper, 5000+ grad; only the first is handled.

### Evidence

Against `data/cedar_sections.qs` (2026-08-13 snapshot), 40,948 sections carry a
4-digit course number:

| course number band | assigned `level` | sections |
|---|---|---|
| 1000–2999 | `lower` | 39,597 (correct) |
| 3000–4999 | `lower` | **1,351 (should be `upper`)** |

No 4-digit course is ever assigned `upper` or `grad`. Misclassified examples are
concentrated in units already renumbered — `NMNC 3220`, `NMNC 3120`,
`NMNC 4445`, `NMNC 4545`, `NMNC 3235` (Nursing).

The aggregate distribution looks healthy (grad 108,342 / lower 59,065 / upper
73,273), which is why this survived: most of the data is still 3-digit, so the
totals are not obviously skewed and only the renumbered units are wrong.

### Reproduce

```r
Rscript --vanilla -e '
suppressMessages({library(qs2); library(dplyr)})
qs_read("data/cedar_sections.qs") %>%
  filter(grepl(" [0-9]{4}", subject_course)) %>%
  mutate(num = as.integer(sub("[A-Z]$", "", sub(".* ", "", subject_course)))) %>%
  filter(num >= 3000, num < 5000) %>%
  count(level)'
# -> level = "lower", n = 1351
```

### What a fix requires

Reorder so the 4-digit bands are handled explicitly rather than collapsed into
one `lower` branch — 1000–2999 lower, 3000–4999 upper, 5000–6999 grad — while
keeping the existing 3-digit bands (<300 lower, 300–499 upper, 500–699 grad).
Note the class-list branch at ~line 682 uses a *different*, regex-based rule
(`[0-2]` lower, `[3-4]` upper, `[5-9]` grad) that reads the leading digit and so
already gets 4-digit courses right; the two rules disagree, and the fix should
reconcile them rather than patch one.

This changes counts on every level-filtered surface, so it needs a transform
rerun and a check of the level-dependent tests and cached artifacts, not just a
one-line edit.

### Known dependents

`tests/e2e/reports-smoke.test.mjs` selects `lower` in two synthetic steps
because the fixture's upper-division courses currently classify that way:

| step | course | true level | classified |
|---|---|---|---|
| Open Seats | `HIST 3010` | upper | `lower` |
| Cancellations | `PSYC 3200` | upper | `lower` |

Fixing this issue must flip both selections back to `upper`. Both are commented
at the call site with a pointer here.
