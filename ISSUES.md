# CEDAR Issues

Known problems and improvements in CEDAR **as it exists today** — code, data,
tests, docs, and interface. Each entry is concrete enough to say where it is
and when it is done. New features and significant upgrades are planned in
`ROADMAP.md`, which links here rather than repeating these entries; finished
work lives in git history and the changelog.

**A quick test for where something belongs:** could someone write "done when…"
for it today, against code that already exists? Then it is an issue. Does it
need design, or a decision about something new? Then it is roadmap.

There are two kinds, in two sections:

- **[Defects](#defects)** (`I` numbers) — CEDAR produces a wrong number or
  breaks. Each carries the evidence and a reproduction, because a defect that
  changes numbers is urgent and must never have to be diagnosed twice. **Post a
  defect the moment it is discovered**, even if it will be fixed in the same
  sitting. A *suspected* defect (two paths that may disagree) is posted with how
  to check it.
- **[Improvements](#improvements)** (`M` numbers) — debt, inconsistency, missing
  tests, and interface standards: what, where, and done when. Short by design.

IDs are stable: code and docs cite them. Resolved entries stay, with
`Status: resolved` and the resolving commit, until the next release, so that a
recurrence is recognizable.

## Open items

| ID | Kind | Summary |
|---|---|---|
| [I26](#i26--projection-capacity-reached-was-judged-on-ever-registered-demand) | Defect | Projection "capacity reached" was judged on ever-registered demand: 72% of course-terms flagged full when census filled 17% (resolved) |
| [I25](#i25--projection-method-selection-was-in-sample-and-lost-to-the-default) | Defect | Projection method selection was in-sample on two folds and lost to doing nothing; reported 13.7% WAPE, honest 16.5% (resolved) |
| [I24](#i24--cis-demo-browser-run-intermittently-loses-the-app-at-open-seats) | Defect | CI's demo browser run intermittently loses the app at Open Seats (passes on rerun) |
| [I23](#i23--student-ids-are-hashed-with-the-built-in-default-salt) | Defect | Student IDs are hashed with the built-in default salt: the salt protects nothing |
| [I20](#i20--cedar_programs-holds-almost-no-branch-campus-students) | Defect | `cedar_programs` holds 1–3% of branch-campus students; branch program counts read near zero |
| [I18](#i18--cedar_degrees-holds-no-associate-degrees-so-branch-campus-completions-read-zero) | Defect | `cedar_degrees` holds no associate degrees: branch-campus completions read zero |
| [I16](#i16--bottleneck-waitlist-pressure-ignores-term-so-later-registration-erases-earlier-waiting) | Defect | `get_bottlenecks()` waitlist pressure ignores term: ~6% under true demand (RStudio only; no page shows it) |
| [I8](#i8--a-timing-log-row-is-silently-dropped-when-the-write-lock-times-out) | Defect | A timing-log row is dropped when the write lock times out |
| [I6](#i6--a-killed-projection-rebuild-strands-its-lock-and-blocks-every-later-refresh) | Defect | A killed projection rebuild strands its lock |
| [I4](#i4--pre-change-course-ratios-are-confounded-by-career-stage) | Defect | Pre-change course ratios confounded by career stage (deferred) |
| M1–M28 | Improvement | See [Improvements](#improvements) |

---

# Defects

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

**Status:** resolved 2026-10-03. Both transforms now call one classifier,
`course_level_from_number()` (`R/trunk/utils.R`), which reads the leading digit
through `COURSE_LEVEL_BY_LEADING_DIGIT` (`R/lists/course_numbering.R`). Rebuilding
`cedar_sections` moved exactly the 1,355 4-digit 3000/4000-level sections to
`upper` and gave the 1,609 sections numbered 700-999 the `grad` level the class
lists already used; sections and class lists now agree on every course. It had
grown sharply: Fall 2026 alone had 289 misclassified sections, after Business
(BUSA), Accounting (ACCT) and Population Health (POPH) renumbered to 4 digits,
joining Nursing (NMNC, since Fall 2024). An architecture test now requires both
transforms to use the classifier.
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

---

## I6 — A killed projection rebuild strands its lock and blocks every later refresh

**Status:** open
**Found:** 2026-09-08 (while adding Fall targets, which roughly doubles the work
one rebuild does and turns this from theoretical into likely)
**Severity:** moderate — silent stoppage. Projections quietly stop updating; the
page keeps serving the last good bundle, so nothing errors and nothing looks
wrong until someone notices the numbers are stale.
**Affects:** `run_projection_auto_refresh()` and `run_projection_rebuild_request()`
in `scripts/build-enrollment-projections.R`; the deploy step in
`.github/workflows/deploy.yml`.

### What is wrong

Both refresh entry points take a lock by creating a directory
(`output/projections/rebuild-request.yml.lock`) and release it with `on.exit()`.
`on.exit()` does not run when the process is killed rather than returning — a
`command_timeout` expiring on the deploy's SSH session, a dropped connection, an
OOM kill, or a `docker compose run` interrupted mid-build. The directory then
stays forever, and every subsequent refresh fails closed:

```
[projections] Rebuild already running or stale lock: .../rebuild-request.yml.lock
```

Failing closed is correct — the alternative is two concurrent builds writing the
same bundle — but nothing ever clears the lock, so the stoppage is permanent
until someone removes the directory by hand.

This is the same shape as the stranded `restarting.flag` fixed in `7cdf09b`: an
EXIT trap that a killed session never runs.

### Reproduction

```bash
Rscript --vanilla scripts/build-enrollment-projections.R --refresh &
sleep 30 && kill -9 %1          # simulate the timeout / dropped session
ls output/projections/rebuild-request.yml.lock   # still there
Rscript --vanilla scripts/build-enrollment-projections.R --refresh
# -> [projections] Rebuild already running or stale lock
```

### What a fix requires

Write the owning PID and a start timestamp into the lock directory, and treat a
lock as stale when its process is gone or it is older than a bounded maximum
build time. Clearing on age alone is not enough: a legitimate build can outlive
any fixed guess, which is how a stale-lock heuristic ends up running two builds
at once against the same output path. Deploy-side clearing before taking the
lock is not safe either, because a deploy can overlap the morning refresh.

Raising `command_timeout` to 60m (this change) reduces how often the kill
happens; it does not fix the stranding.

Since 2026-10-11 (I19) the error tells a held lock from an unwritable
directory and says when the lock was created, so a stranded lock is easier to
recognise; it still has to be removed by hand.

---

## I7 — Health pre-major codes get a phantom department, hiding most of a program's students

**Status:** resolved 2026-10-09 by ADR-002 Stage 3: the transform takes every unit from the mapping files, and a code with no confirmed row has no unit instead of a department named after itself. Codes still awaiting a decision are listed on Admin > Data & Usage > Mappings. (Health pre-majors fixed 2026-09-09.)
**Found:** 2026-09-09 (while resolving named population groups to Banner codes for
the projection growth scenario)
**Severity:** high — silent wrongness at the department level. Nothing errors and
nothing appears in `cedar_mapping_issues`, because the row *is* mapped: to a
department that does not exist.
**Affects:** `dept_code` in `cedar_programs` for `FRAD`, `FDEH`, `FEMS`, `FMDL`,
`XFDE`. Every surface that groups or filters on `dept_code`: Headcount, Dept
Trends, Dept Dashboard, population building by `type = "dept"`.

### What is wrong

`premaj_canon` (`R/lists/program_code_maps.R`) maps pre-major F-codes to the
major they lead to — `FNRS` → `NURS`, `FPOH` → `POHE`, and 90-odd others. Four
health pre-majors are missing from it. They are still detected as pre-majors
(`is_pre_major = TRUE`), so the gap is not visible there; they simply fall
through to the last resort in the documented `dept_code` chain, *the major code
itself*, and land in a department named after the pre-major code.

Fall 2026 counts, by `dept_code`:

| Program | Declared | Pre-major | Pre-major lands in | Share of program hidden from its own dept |
|---|---|---|---|---|
| Radiologic Sciences | `RADS` 35 | `FRAD` 194 | dept `FRAD` | **85%** |
| Dental Hygiene | `DEHY` 108 | `FDEH` 163 (+`XFDE` 1) | dept `FDEH` | **60%** |
| Emergency Medical Services | `EMS` 71 | `FEMS` 114 | dept `FEMS` | **62%** |

A dean asking for Radiologic Sciences headcount is shown 35 students out of 229.

**Why nothing flagged it.** `cedar_mapping_issues` collects rows with *no*
department owner. These rows have one — it is just wrong. The fallback that makes
`dept_code` total is exactly what stops this from being reported.

### Reproduction

```r
source("scripts/cedar-repl.R")
c("FRAD", "FDEH", "FEMS", "FMDL") %in% names(premaj_canon)          # all FALSE
c("FRAD", "FDEH", "FEMS", "FMDL") %in% allowed_unmapped_program_codes # all FALSE
cedar_programs %>% filter(term == 202680L, program_name == "Radiologic Sciences") %>%
  count(dept_code, is_pre_major)          # FRAD 194 / RADS 35
```

### Correction to the first diagnosis (2026-09-09)

**The missing `premaj_canon` entries are a symptom, not the cause.** The cause is
that `program_map.qs` is **stale**: it was generated 2026-06-17 from that day's
`academic_studies` export, while `cedar_programs` is built from the current one.
Every program that first appeared after June therefore has no row in the map, so
Tiers 1 and 3 of the `dept_code` chain both miss, Tier 2 misses (these are not
subject codes), and Tier 4 — the identity fallback — hands the student a
department named after their own program code.

Two exports exist and they are not the same file:

| Path | Date | Size |
|---|---|---|
| `data/academic_studies.qs` (what `cedar_data_dir` points at) | 2026-06-17 | 16.6 MB |
| `<CEDAR_DATA_DIR>/academic_studies.qs` | 2026-09-07 | 21.1 MB |

So a regenerate run locally silently reproduces the stale map. Regenerating from
the **current** export fails loudly, correctly, on every program added since June.

**The full scope is 15 codes, not 4.** Beyond the four health pre-majors, these
11 are in phantom departments right now (214 student-term rows), each needing a
department owner before the map can be regenerated:

| Program code | Name | College | Major code |
|---|---|---|---|
| `CERT-AAHS-GA` | Human Services | Undergrad Cert (Gallup) | `AAHS` |
| `BA-FS-AS` | Family Studies | Arts & Sciences | `FS` |
| `BS-ECME-ED` | Early Child Multicult Educ | Education | `ECME` |
| `BA-DFP-FA` | Design for Performance | Fine Arts | `DFP` |
| `MCM-CMGT` | Construction Management | Graduate | `CMGT` |
| `MS-CLSC` | Clinical Laboratory Science | Graduate | `CLSC` |
| `BA-FILA-HC` | Pre-Interdisc Liberal Arts | Honors | `FILA` |
| `CERT-HHHA-TA` | Holistic Health & Healing | Undergrad Cert (Taos) | `HHHA` |
| `CERT-MDRC-GA` | Health Info Tech Coding | Undergrad Cert (Gallup) | `MDRC` |
| `PHD-EDST` | Education Studies | Graduate | `EDST` |
| `GCERT-GLPO` | Glob & Nat Secur Policy | Graduate | `GLPO` |

### Resolved, 2026-09-09

`program_map.qs` regenerated from the September export (555 rows, up from the
stale 523) and `cedar_programs` rebuilt. Department headcounts at Fall 2026:

| Department | Before | After |
|---|---:|---:|
| `RADS` | 35 | **230** |
| `DEHY` | 108 | **272** |
| `EMS` | 71 | **185** |
| `MEDL` | — | **115** |

The screens confirm the change scoped to what was mapped: pre-major phantoms
22 → 16, identity-fallback 72 remaining. Those 88 are a genuine backlog and are
now visible in Admin > Data & Usage > Mappings rather than invisible.

**Three traps cost time here; all are now documented in
[data-anomalies.md](docs/developers/data-anomalies.md).**

1. **Two `academic_studies.qs` exist.** The transform reads
   `cedar_shared_data_dir` (current) while `cedar_data_dir` is the repo's local
   copy, which was nine months stale. A regenerate pointed at the wrong one
   silently reproduces the old map.
2. **`transform_to_cedar()` skips the regenerate when `program_map` already
   exists in the session,** and `load_funcs()` defines it. Any script that loads
   CEDAR functions first rebuilds against the stale in-memory map and reports
   success. This is what made the first rebuild attempt a no-op.
3. **Do not move the map aside to force a regenerate.** The running app reads
   `program_map.qs` from the shared data directory; removing it breaks startup.
   Generate and save the new map first, then rebuild.

### Remaining backlog as of 2026-09-09 (all visible in Admin > Data & Usage > Mappings)

**570 students across 27 programs.** Every item below appears on the Admin
Mappings tab; none of it is silent any more. Ranked by students, majors only —
minors and the selective-admission screen are excluded because they are not
mapping work. See [mapping-review-guide.md](docs/developers/mapping-review-guide.md)
for how to resolve one.

| Code | Students | Program | Likely resolution |
|---|---:|---|---|
| `FPMD` | 184 | Doctor of Pharmacy (pre) | → `PHRM`, unconfirmed |
| `FLIB` | 89 | Liberal Arts (pre) | → `LAIS`, by analogy with `FLAI`; unconfirmed |
| `GSCI` | 60 | General Science | possibly `department_less_major_codes` |
| `EAST` | 42 | East Asian Studies | needs catalog |
| `FCOE` | 37 | Construction Engineering | blocked on the `E` suffix below |
| `ASPE` | 32 | Engineering | possibly `department_less_major_codes` |
| — | ~126 | 21 programs under 30 students each | low value, can wait |

**Open question — the `E` college suffix.** `BSCNE-CONE-E` and `BSCNE-FCOE-E`
are still discarded because `E` is not in `known_suffixes`. `BSCNE` is
Construction Engineering, so `E` looks like a truncated `EN`, but a data-entry
variant and a real code are indistinguishable from the data. Adding it wrongly
would file those students in Engineering on a guess. They are listed on the
Admin tab as `program_dropped_unknown_college_suffix`.

### Two flaws in the loud failure itself

Both fixed while diagnosing this, because they made the error unusable:

1. `unexpected` is a tibble when `academic_studies` is read from `.qs`, and
   `print.tbl_df` rejects `row.names = FALSE` — so the message whose whole job is
   to name the unmapped codes threw a formatting error instead of listing them.
2. The list is truncated at R's 1000-character `warning.length`, which cuts it
   off mid-code. Raise the option when regenerating, or read the list another way.

### Related: the name for `FMDL` does not match its own major

`FMDL` carries `program_name = "Medical Laboratory Science"` while `MEDL` carries
`"Medical Laboratory Sciences"`. Any grouping that matches programs *by name*
silently splits that pair, which is the mirror image of this bug — so a fix must
not simply move everything to name matching.

### What a fix requires

1. The four `premaj_canon` entries (`FRAD` → `RADS`, `FDEH` → `DEHY`,
   `FEMS` → `EMS`, `FMDL` → `MEDL`) and `XFDE` → `DEHY` in `xvar_explicit`.
   **Done.**
2. A department owner for each of the 11 programs above. **Seven mapped** in
   `extra_p2d` with the reasoning recorded per entry; **four still open** and
   listed under NEEDS RESEARCH in `allowed_unmapped_program_codes`
   (`BS-ECME-ED`, `BA-FS-AS`, `MCM-CMGT`, `CERT-HHHA-TA`). Those four are
   parked, not answered: their students have no department today.
   Two of the seven — `CLSC` → `MEDL` and `DFP` → `THEA` — are reasoned rather
   than certain and are worth confirming with IR.
3. Regenerate `program_map.qs` from the **current** export, not the stale local
   copy, and rebuild `cedar_programs`. **Not yet done** — this rewrites a
   durable artifact and every dept-scoped surface changes when it lands.
   A dry run against the current export now succeeds: 555 rows against the
   stale map's 523, with all five health codes resolving correctly.
4. Close the hole that hid all of it: a pre-major whose resolved `dept_code`
   equals its own `major_code` should be reported in `cedar_mapping_issues`.
   Tier 4 exists so `dept_code` is never NA, but for a pre-major that outcome is
   always a mapping failure rather than a real department, and today it is
   indistinguishable from a correct answer.
5. Reconcile the two lists that both decide which F-prefix codes are real
   programs — `real_F_progs` in `program_code_maps.R` and the inline exclusion
   vector in `transform_to_cedar()`. They disagree today (`FCS` is in one and not
   the other), which is a separate latent defect in the same area.


### Update 2026-10-02: the backlog is 57 self-named departments, not a handful

GitHub #100 (LCL undercounted) traced to `BA-EAST-AS`, East Asian Studies. It
was on `allowed_unmapped_program_codes` as "no defensible owner", so the Tier 4
identity fallback filed its majors under a department named `EAST`, while its
own pre-major `FEAS` resolved to LCL. LCL confirmed ownership, and it is now
`EAST="LCL"` in `extra_p2d`. Comparative Literature & Cultural Studies
(`CLCS`, BA and MA, with pre-major `FCLC`) had been mapped to ENGL and is also
LCL's. Together, LCL majors for Fall 2026 went from 71 to 91 undergraduate and
from 5 to 14 graduate, the "grad majors are very low" in the report.

The same screen run across all of `cedar_programs` since Fall 2024 found
**59 `dept_code` values that are not departments in `subj_dept_map`**. Two are
legitimate (`NOND`, `UNDC`, already in `department_less_major_codes`). The other
57 are programs reported under a department named after their own code, so their
students count toward no real department. Largest by student-terms: `ART` minor
(572), `ASL` minor (430), `FPMD` Doctor of Pharmacy (384), `MLST` Military
Studies (384), `ALB` Arts Leadership & Business (197), `GAMG` Gaming (161),
`FOAN` Forensic Anthropology (128), `NLL` Navajo Language & Linguistics (115),
`PBSV` Public Service (109), `BLE` Bilingual Education (93), `ATHC` (86),
`FLHC` (85), `DSTM` (81), `FCOE` (66), `GSCI` (62), then a long tail. Several
are minors only, which no `extra_p2d` entry ever covers.

**Correction (2026-10-03):** these are not invisible. The Admin > Data &
Usage > Mappings panel runs `detect_identity_fallback_departments()` and
`detect_pre_major_self_mapping()` at runtime against `subj_dept_map`, and on
current data it lists 70 identity-fallback programs and 14 self-mapped
pre-majors, with a summary line saying they name departments that do not exist.
Item 4 above is effectively done. What does NOT list them is the *startup*
`cedar_mapping_issues` table, and `cedar_lookups$dept_name_lookup` treats them
as departments (`EAST` was in it), so an ad-hoc check against the lookup passes.
**Check against `subj_dept_map`, never `dept_name_lookup`:**

```r
source("scripts/cedar-repl.R")
cedar_programs |>
  dplyr::filter(term >= 202480, !is.na(dept_code),
                !dept_code %in% unique(subj_dept_map$dept_code)) |>
  dplyr::count(dept_code, major_code, program_name, program_type, sort = TRUE)
```

Each needs an owning department from someone who knows the unit, or a place on
`department_less_major_codes` if genuinely none exists. The panel's own gap was
error handling: it sat in `server.R` inside a `tryCatch` that returned only the
startup rows when a screen failed, so a broken screen would have read as "no
mapping issues". It is now `build_admin_mapping_issues()` in
`R/features/admin.R`, which fails loudly and is tested.
---

## I8 — A timing-log row is silently dropped when the write lock times out

**Status:** open
**Found:** 2026-09-09 (test-logging.R failed once during a run that was competing
with a Docker image build; it passes 3/3 in isolation)
**Severity:** low — telemetry only. No analytical table is affected. But the loss
is silent, which is why it is written down rather than shrugged off.
**Affects:** `with_timing_log_lock()` and `end_report_timer()` in
`R/trunk/logging.R`; the usage/timing figures on Admin > Data & Usage.

### What is wrong

`with_timing_log_lock()` waits up to **2 seconds** for the lock directory and
then `stop()`s. Callers reach it through `end_report_timer()`, which in the
failing test runs inside `parallel::mclapply(...)` whose result is discarded —
so the error is captured by the worker, thrown away, and the row never lands.

Observed: 8 concurrent workers, 7 rows written, `worker_4` missing, with no
error surfaced anywhere.

In production the same shape occurs whenever several sessions finish a report at
once on a loaded machine. The consequence is under-counted usage, not wrong
analytics.

### Reproduction

Run the suite while the machine is saturated (a container build is enough):

```r
testthat::test_file("tests/testthat/test-logging.R")
# "concurrent workers append complete timing rows" fails: nrow(written) == 7
```

It passes reliably when the machine is idle, which is what makes it a flake in
appearance and a race in fact.

### What a fix requires

Decide what a failed timing write should do, and make it explicit either way.
Either retry with backoff past a longer deadline, or let the write fail loudly
enough that the count is known to be incomplete. What it must not do is what it
does now: raise an error into a context that discards it. Note that the 2-second
timeout is itself reasonable — a report-timing write should not block a user
session — so the fix is about the swallowed error, not the deadline.

---

## I9 — `real_F_progs` lists codes the transform treats as pre-majors

**Status:** resolved 2026-10-10 by ADR-002 Stage 4: both lists are retired.
`is_pre_major` is read per code from `programs.csv`, checked against Banner's own
program records; `FCS` resolves to CS through its row. Narrowed 2026-09-09 after
`pre_major_basis` made the evidence readable; **the original diagnosis on this
entry was wrong; it is corrected below.**
**Found:** 2026-09-09 (platform/institution boundary audit)
**Severity:** moderate for `FCS`, which has a demonstrated consequence; unproven
for the rest.
**Affects:** `real_F_progs` in `R/lists/program_code_maps.R`, consumed by
`generate_program_map()` when deciding `prog_type`.

### Correction to the first diagnosis

This was filed claiming `real_F_progs` and `pre_major_exempt_codes` "answer the
same question and disagree", over 23,272 rows, and that `is_pre_major`
contradicted itself. **All three claims were wrong**, and the `pre_major_basis`
column added the same day shows why.

The two lists serve different consumers and different questions:

| Constant | Consumer | Question |
|---|---|---|
| `real_F_progs` | `generate_program_map()` | is this F-code a real program for `prog_type` and department routing? |
| `pre_major_exempt_codes` | `transform_programs()` | for this F-code, should the NAME decide pre-major status rather than the F-prefix? |

`pre_major_exempt_codes` is **correct and load-bearing**. For every code on it,
`pre_major_basis` is `name_prefix` or absent — the code convention never fires —
and the splits are real rather than contradictory:

| Code | Named `Pre-` | Not named `Pre-` |
|---|---:|---:|
| `FDMA` Film and Digital Arts | 0 | 4,664 |
| `FES` Exercise Science | 4,015 | 1,040 |
| `FFDA` | 3,423 | 987 |

Removing the exemption would misflag all 4,664 declared Film and Digital Arts
majors as pre-majors. What looked like self-contradiction was Banner correctly
recording that some students under a code are pre-majors and some have declared.

### What is actually wrong

`real_F_progs` contains four codes that the transform classifies as pre-majors
in **every** row:

| Code | Rows, all pre-major | Basis | Degrees awarded |
|---|---:|---|---:|
| `FCS` Computer Science | 6,121 | code convention | **0** |
| `FCST` Family & Child Studies | 3,223 | name + code | 394 |
| `FREN` French | 762 | name + code | 45 |
| `FRST` French Studies | 22 | name + code | 4 |

`FDMA` and `FS` are consistent — never flagged pre-major, and they award degrees.

**`FCS` is the proven defect.** It awards no degrees, `premaj_canon` declares it
leads to `CS`, and every one of its 6,121 rows is a pre-major — yet
`real_F_progs` tells `generate_program_map()` it is a real program, so it never
receives its canonical mapping. Those students sit in a phantom `FCS` department
(ISSUES.md I7), which is separately complicated by `FCS` also being the genuine
code for the Family and Child Studies department.

The other three award degrees while being flagged pre-major in every row, which
suggests the declared form of those programs carries a different `major_code`.
That needs catalog knowledge, not more querying.

### What a fix requires

Remove `FCS` from `real_F_progs` and confirm it then resolves through
`premaj_canon["FCS"] == "CS"` — noting the department-code collision means it may
also need a `major_college_to_dept` entry keyed on the Engineering college.
Review `FCST`, `FREN` and `FRST` against the catalog: either they belong in
`real_F_progs` and the transform is over-flagging them, or they do not and the
degrees are awarded under a different code.

Do **not** merge the two constants. They are not duplicates.


---

## I10 — `renv::activate()` in parse-data.R took production down

**Status:** resolved 2026-09-10 (the call is removed and an architecture test
prevents its return); the `--vanilla` asymmetry it exposed is also fixed
**Found:** 2026-09-10, production outage during a data refresh
**Severity:** critical — the app was down. Every `library()` call in the
pipeline failed after the activation.
**Affects:** `R/data-parsers/parse-data.R`, and the production branch of
`scripts/update-data.sh`.

### What happened

`parse-data.R` opened with:

```r
tryCatch({
  if (requireNamespace("renv", quietly = TRUE) && !nzchar(Sys.getenv("RENV_PROJECT"))) {
    renv::activate()
  }
}, error = function(e) warning("renv activation failed; using system packages"))
```

Inside the container, `renv/library` is **empty** — the image installs the
pinned package set into `/usr/local/lib/R/site-library` at build time via
`scripts/r-environment.R restore-docker`, and `renv/` arrives only because the
Dockerfile copies the repository. Activating therefore repointed `.libPaths()`
at a directory with no packages in it, and every `library()` call after that
point failed.

**The `tryCatch` gave false comfort.** It catches errors *from* `activate()`,
but `activate()` succeeds — it does exactly what it was asked to. The failures
come afterwards, from consumers, and were never caught.

### Why it reached production and not a dev machine

`update-data.sh` already knew this call was dangerous and guarded against it —
in one branch only:

| Branch | `--vanilla` | `RENV_PROJECT` | Result |
|---|---|---|---|
| Local dev | yes | yes | activation skipped |
| **Production Docker** | **no** | **no** | **activation runs** |

The workaround was applied where the problem was first noticed and never to the
path that actually ships. Both guards are documented in the script's own header
as protecting against exactly this call.

### Why renv was there at all

It was a leftover. Every other part of CEDAR had already moved off runtime
activation: `.Rprofile` states "Startup never installs packages or activates
renv's old cache-linked library", `AGENTS.md` says there is no runtime
activation, and `scripts/r-environment.R` is the only sanctioned setup path.
This one call survived the migration, and the caller was patched around it
instead of it being deleted.

### Fix

1. The call is removed. `scripts/r-environment.R` remains the only file allowed
   to touch renv, and `tests/testthat/test-architecture.R` now fails on any
   `renv::activate/deactivate/restore/load` call elsewhere.
2. All eight container R invocations in `update-data.sh` now use `--vanilla`,
   matching the local branch, so the two paths cannot diverge again.

### The general lesson

A guard applied to the path where a bug was noticed, rather than to the bug, is
a guard that will be missing from the path that matters. The asymmetry sat in
the script header describing itself for months.

---

## I11 — Concentrations are assigned to departments by name, so PADM borrows Political Science students and misses its own

**Status:** resolved 2026-10-10. ADR-002 Stage 3 gives every concentration
row in `cedar_programs` the unit of the student's primary major, and with I15's
fix Headcount reads that unit rather than matching the concentration's name.
**Found:** 2026-10-02, auditing SPA (PADM) program mappings after an MHA request
**Severity:** low — single-digit students per term — but it misattributes
students across departments, and the same mechanism applies to every concentration
**Affects:** the Headcount explorer and any headcount built through
`add_headcount_dept_fields()` (`R/branches/headcount.R`), which assigns a
department by joining `program_name` to `cedar_lookups$program_name_lookup`.

### What is wrong

Concentration rows in `cedar_programs` carry no `major_code`, so their
`dept_code` is NA and headcount falls back to matching the concentration's
**name** against the program-name lookup. That lookup is built from majors, so
a concentration inherits whatever department owns a *major* of the same name:

| Concentration | Actually held by | Name lookup says |
|---|---|---|
| Public Policy | Political Science MA/PhD (41 student-terms) | **PADM** — borrowed from the MPP |
| Public Management | MPA students (31) | NA — dropped |
| Health Policy and Admin | MPA students (8) | NA — dropped |
| General Healthcare Admin | MHA students (2) | NA — dropped |

So a PADM headcount counts POLS graduate students (Fall 2025: 4) as PADM
"Public Policy" concentrations, while SPA's own MPA/MHA concentrations do not
appear under PADM at all. Majors are unaffected: MPA (`PADM`), MHA (`HLAD`) and
MPP (`PUPO`) resolve to PADM in `cedar_programs`, `cedar_degrees`, the class
lists, and every catalog lookup, with no identity fallbacks and no
`cedar_mapping_issues` rows.

### Reproduce

```r
source("scripts/cedar-repl.R")
get_headcount(cedar_programs, list(dept_code = "PADM"), lookups = cedar_lookups)$data |>
  dplyr::filter(term == 202580, grepl("Concentration", program_type))
# Public Policy concentrations, degree MA / PhD -- Political Science students
```

### What a fix requires

A concentration belongs to the department of the **major it sits under** in the
same student-term, not to whichever major shares its name. Resolve it through
the host major's `dept_code` at transform time (or in headcount), and decide
explicitly what a concentration with no host major means rather than falling
back to the name lookup. Check the other name collisions this exposes before
shipping — "Public Policy" will not be the only one.

---

## I12 — Renamed and non-college names leave 48k program rows and 10k sections with no college

**Status:** resolved 2026-10-10 by ADR-002 Stage 3b: every reported college comes from the mapping files, Banner's values translated through `colleges.csv` `source_names` (ED and "College of Education" → EH, "University Studies" → UC, "Undergrad Certificate Program" → AD). 10,423 Education sections now report EH, and Banner's original stays in `source_college`.
**Found:** 2026-10-04, measuring unmapped codes of every kind for the Admin > Mappings page
**Severity:** medium — any college-scoped count of Education before 2021 is short,
and nothing says so
**Affects:** `cedar_programs$college_code` (and anything filtering or grouping by
it), and `cedar_sections$college` for College of Education sections before 2021.

### What is wrong

`college_name_to_code` (`R/lists/catalog_lookups.R`) is built from the one name
per college in `institution/unm/colleges.csv`. The exports use more names than
that, so `transform_programs()` gives these rows `college_code = NA`, silently:

| Academic Studies `Actual College` | Why it does not map |
|---|---|
| College of Education | The College of Education's name before it became Educ & Human Sci |
| University Studies | Not a college: University College's bachelor programs |
| Undergrad Certificate Program | Not a college |
| (blank) | Missing in the export |

Measured on `cedar_programs` built 2026-10-03: 47,886 rows have no
`college_code`, 18,181 of them Education students, mostly 2018–2022.

The course side has the same rename as a code. DESR sections for the College of
Education carry college `ED` through Fall 2021 and `EH` from Fall 2021, and only
`EH` is in `colleges.csv`: 10,423 sections (2018–2021) have a college that maps
to nothing. Their department is unaffected, because `subj_to_dept` ignores
college, but a filter on college `EH` misses Education's first four years.

### Reproduce

```r
source("scripts/cedar-repl.R")
cedar_programs |> dplyr::filter(is.na(college_code)) |> dplyr::count(student_college)
cedar_sections |> dplyr::filter(college %in% c("ED", "EH")) |>
  dplyr::count(college, year = substr(term, 1, 4))
```

### What a fix requires

Banner's own Translated College field already applies these renames, and
ADR-002 now uses it as evidence for an explicit college mapping (see "Colleges
are mapped, not read"). ADR-002 already plans the fix: `colleges.csv` gains `source_names`, every spelling
and former code the exports use, replacing `college_name_to_code`.

Decided 2026-10-04: `ED` and "College of Education" **are** `EH` (a rename).
"University Studies" belongs to University College (`UC`). The
college of "Undergrad Certificate Program" students was decided 2026-10-04: `AD`.
The evidence it was decided on: all 15 such rows in the September 2026 export are branch-campus
students, the population Banner otherwise files under "Associate Degree" (`AD`,
Banner's college for branch-campus associate programs: every one of its 1,088
rows is a Gallup, Los Alamos, Taos or Valencia student).
The transform-time mapping audit should list any name or code with no row, so
the next rename is seen the day it arrives.

---

## I13 — A transform run as a script never stamps cedar_programs with its mapping provenance

**Status:** resolved 2026-10-04 in #109 (merge `17ea915`): script mode and the demo
generator load CEDAR's functions, and the stamp is unconditional.
**Found:** 2026-10-04, wiring the mapping audit into the end of the transform
**Severity:** low in effect, misleading in appearance — every data refresh that
rebuilds programs leaves Admin > Data & Usage reporting STALE departments
**Affects:** `R/data-parsers/transform-to-cedar.R` when run as
`Rscript transform-to-cedar.R`, which is how `scripts/update-data.sh` runs it.

### What is wrong

The stamp is written only `if (exists("cedar_mapping_provenance"))`. Script mode
sources `config/config.R` and a few lists, but never `load_funcs()`, so the
branch that defines `cedar_mapping_provenance()` is never loaded and the stamp
is silently skipped. `cedar_programs_mapping_drift()` then reports "predates
mapping-provenance tracking", the Admin page says STALE, and the deploy gate (and
now `update-data.sh`'s mapping check) rebuilds programs a second time to stamp
it. The departments are right; the warning and the duplicate rebuild are not.

`scripts/rebuild-programs-if-mappings-changed.R` stamps correctly because it
calls `load_funcs()` before `transform_to_cedar()`. `dev/generate-demo.R` had the same
gap: the synthetic demo's `cedar_programs` was never stamped either, found when
the stamp was made unconditional.

### Reproduce

```bash
Rscript --vanilla R/data-parsers/transform-to-cedar.R --tables programs
Rscript --vanilla -e 'p <- qs2::qs_read("data/cedar_programs.qs"); is.null(attr(p, "cedar_mapping_provenance"))'
# TRUE
```

### What a fix requires

Script mode loads functions as the rebuild script does, and the stamp drops its
`exists()` guard so a missing function fails loudly instead of silently.

---

## I14 — The deploy's mapping rebuild looked for institution files on the host path, inside the container

**Status:** resolved 2026-10-04 in #112 (merge `8a11473`); the next deploy's
mapping step passed and rebuilt production's `cedar_programs`.
**Found:** 2026-10-04, merging #108: its deploy, and #107's, failed
**Severity:** high for mappings — every deploy since #107 has failed at the mapping
check, so no mapping change reaches production's cedar_programs. The app itself
deployed and passed its health check each time.
**Affects:** `scripts/rebuild-programs-if-mappings-changed.R` run by
`.github/workflows/deploy.yml` inside the production container; anything that
sources `config/config.R` and then `load_funcs()` inside a container.

### What is wrong

The deploy step failed with
`No mapping files for institution 'unm' at ***/institution/unm` (`***` is the
masked `CEDAR_PATH` secret). The rebuild script sources `config/config.R`, whose
`cedar_base_dir` is the server's host path to the repository, then calls
`load_funcs()` with the container path. `institution_files.R` found the
repository by looking `cedar_base_dir` up the calling frames, and while a list
file is being sourced the global environment is one of them -- so it found the
host path before load_funcs()'s argument. It worked on a laptop (the host path is
the repository) and in the app (whose `shiny_config.R` uses a relative path).

### Reproduce

```bash
docker exec -w /srv/shiny-server/cedar cedar-shiny Rscript --vanilla -e '
  source("config/config.R"); cedar_base_dir <- "/not/in/the/container"
  source("R/trunk/load-funcs.R"); load_funcs("/srv/shiny-server/cedar", modules = FALSE)'
# Error: No mapping files for institution 'unm' at /not/in/the/container/institution/unm
```

### What a fix requires

`load_funcs()` records the base it was given (`options(cedar.base_dir = ...)`)
and the institution-files lookup uses it first.


---

## I15 — The Headcount tab scopes a department by program name, crediting it with other departments' students

**Status:** resolved 2026-10-10. `filter_programs_to_dept()` (`R/branches/headcount.R`)
keeps the rows whose own `dept_code` is the department, and the Headcount tab,
Dept Trends and the Dept Dashboard all scope through it; the rollup to
department totals uses the row's unit too. EC-16 (two departments' programs
named "Engineering") is the cross-tab test, and fails with the name match
restored. Both scope strips now say the same thing.
**Found:** 2026-10-07, auditing where CEDAR counts the same thing twice
**Severity:** medium — wrong department totals where program names collide; the
counting itself agrees everywhere
**Affects:** the Headcount tab and Dept Trends' headcount (both through
`filter_programs_by_opt()` in `R/branches/headcount.R`); the Dept Dashboard
(`get_headcount_summary()` in `R/features/dept-dashboard.R`) is computed apart.

### What is wrong

The three surfaces count the same way — unique students per term with a
declared major or second major — and agree on 1,062 of 1,088 comparisons (every
department with majors × undergraduate and graduate × Summer 2022 through Fall
2025). They differ only in **which rows belong to a department**:

- The Dashboard takes rows whose `dept_code` is the department.
- The Headcount tab and Dept Trends take rows whose `dept_code` is the department
  **or whose program name** is one of the department's program names
  (`program_name_lookup`).

Name matching is wrong where two departments' programs share a name, and only
accidentally right where it pulls in a program whose department is a phantom:

| Department | Headcount tab − Dashboard | Rows added by name |
|---|---|---|
| ASPE (branch Pre-Engineering), graduate | **+231 to +246 every term** | ENG's graduate "Engineering" programs — **wrong department** |
| LAIS, undergraduate | +1 to +131 | FLIB "Liberal Arts" pre-majors, today under phantom department FLIB |
| CONE, undergraduate | +6 to +14 | FCOE "Construction Engineering" pre-majors, phantom FCOE |
| LING, LCL, MATH, BIOC, MGMT, CE | +1 to +6 | the same mechanism |

The concentration case in I11 is the same mechanism.

### Reproduce

```r
source("scripts/cedar-repl.R")
pn <- cedar_lookups$program_name_lookup
cedar_programs |>
  dplyr::filter(term == 202580, student_level == "Graduate/GASM",
                program_type %in% c("Major", "Second Major"),
                dept_code != "ASPE",
                program_name %in% pn$program_name[pn$dept_code == "ASPE"]) |>
  dplyr::count(program_name, dept_code)   # Engineering / ENG: 243
```

### Disclosed, not fixed

Since 2026-10-07 the Headcount tab's scope strip names the rule ("or a program
with the same name ... ISSUES I15") whenever a department is selected, and the
Dept Dashboard's headcount cards carry the same strip saying they use the
program's own department. Both are built by `describe_headcount_scope()`
(`R/branches/headcount.R`). The counts are unchanged; Dept Trends' headcount
still has no strip.

### What a fix requires

Scope a department by `dept_code` alone, in one shared function the Dashboard
uses too, and a cross-tab test. Do it with ADR-002 Stage 3: dropping the name
match before then would move FLIB's students out of LAIS while they still carry a
phantom department (FLIB → LAIS is already confirmed in `programs.csv`). The
Headcount page's scope bar should then say how the department was decided.
**Unblocked 2026-10-09:** Stage 3 shipped, so FLIB's students carry LAIS on
their own rows and nothing still depends on the name match.

---

## I16 — Bottleneck waitlist pressure ignores term, so later registration erases earlier waiting

**Status:** open — confirmed 2026-10-07
**Found:** 2026-10-07, auditing where CEDAR counts the same thing twice
**Severity:** low — totals about 6% under the canonical count; a few courses
read far lower. No app page shows it.
**Affects:** `compute_waitlist_pressure()` and `get_bottlenecks()`
(`R/cones/bottleneck.R`). Nothing in `server.R`, a module, or a feature calls
them; they are reachable only by analysts in RStudio (the AGENTS.md population
example uses `get_bottlenecks()`).

### What is wrong

The suspicion was duplicate waitlist rows. That part is fine:
`compute_waitlist_pressure()` counts distinct students and removes anyone
registered. The real difference is that it works on `(student, campus, course)`
**with no term**. A student waitlisted in one term who registers for the course
in *any* term of the window is removed, and the remaining students are pooled
across terms. The canonical count (`R/branches/waitlist-demand.R`) is per term,
course title, campus, college, and part of term.

### Evidence

Fall 2024 – Fall 2026, ABQ and EA, every student as the population: pressure
3,501 vs canonical 3,707 summed over terms (−5.6%); 105 of 548 courses differ.
Largest gaps: PSYC 376 (EA) 62 vs 72, BIOL 2210L 67 vs 76, ARCH 472 4 vs 13.
ARCH 472 is the pattern: students who waited one term and took it later vanish.

### Reproduce

    st  <- cedar_students %>% filter(term >= 202480, campus %in% c("ABQ", "EA"))
    p   <- compute_waitlist_pressure(st, unique(st$student_id))
    c   <- summarize_waitlist_demand(get_true_waitlisted_rows(st, cedar_sections),
                                     c("campus", "term", "subject_course"))
    # compare sum(p$n_waitlisted) with sum(c$waiting), per course

### What a fix requires

A decision first. "Waited and never got in during the window" is a defensible
Roadblocks question, but then it needs its own label and definition; otherwise
use `get_true_waitlisted_rows()` / `summarize_waitlist_demand()` per term. Either
way, a fixture student waitlisted in 202080 and registered in 202110 for the
same course pins the behaviour.

---

## I18 — cedar_degrees holds no associate degrees, so branch-campus completions read zero

**Status:** open
**Found:** 2026-10-10, checking whether branch pre-programs (ASPE, PBA, PRSC) award degrees
**Severity:** medium for any completions view of the branch campuses — every
associate degree and branch certificate is missing, and the count is zero, not
blank. Main-campus degrees are unaffected.
**Affects:** `cedar_degrees`, and anything reading it for branch programs:
degree counts, Pathways' `graduated` outcome for branch students, and the
evidence the mapping review uses ("no degrees awarded" is meaningless for a
branch code).

### What is wrong

The degrees export CEDAR receives has no associate degrees at all: no row whose
`degree` begins "Associate", and no program code ending in a branch campus
(`-LA`, `-VA`, `-TA`, `-GA`) other than the Master of Landscape Architecture,
whose codes happen to end `-LA`. Branch associate programs appear in Academic
Studies (AS Pre-Engineering at Los Alamos and Valencia, AA Pre-Business
Administration, AS General Science...) but never graduate.

This nearly misled a mapping decision: five branch "Pre-" programs looked like
pre-majors partly because none had awarded a degree. They had no chance to.

### Reproduce

```r
source("scripts/cedar-repl.R")
sum(grepl("^Associate", cedar_degrees$degree))                       # 0
cedar_degrees |> dplyr::filter(grepl("-(LA|VA|TA|GA)$", program_code)) |>
  dplyr::count(degree)                                                 # Master of Landscape Architect only
```

### What a fix requires

Find out whether the degrees report is scoped to the main campus by design.
If so, request the branch campuses' awards and add them; if not, find where
they are dropped. Until then, say on any degree count that it excludes the
branch campuses.

Academic Studies is missing the same students (I20): a raw download with all
campuses selected holds only students registered for a main-campus or online
course that term, and no code filters them. Check a raw Degrees download the
same way (match it to the class lists); the two likely share a cause.

---

## I19 — The morning refresh could never publish projections, and blamed a stale lock

**Status:** resolved 2026-10-11. `update-data.sh` builds through the
`cedar-projections` service, the same command as the deploy's gate, and
`take_projection_lock()` (`scripts/build-enrollment-projections.R`) tells a held
lock from a directory it cannot write. `test-data-update-pipeline.R` asserts the
publisher service and fails with the old command restored;
`test-projection-refresh.R` checks the second message.
**Found:** 2026-10-11, when a manual refresh failed at its projection step
**Severity:** moderate — projections went stale silently. They moved only when a
deploy changed the model, never with new data, and the one visible symptom
pointed at a different defect (I6).
**Affects:** the projection step of `scripts/update-data.sh` in production mode.

### What is wrong

The morning step ran the build as `docker compose run ... --volume
./output:...:rw cedar-shiny`. Compose keeps the app service's read-only `output/`
mount, so the override did nothing. `7cdf09b` (2026-09-08) measured exactly
that, gave the publisher its own `cedar-projections` service, and moved the
deploy to it, but not the morning refresh. `test-data-update-pipeline.R` asserted
the broken command, so nothing flagged it.

The build then failed one second in, at `dir.create()` of the lock, which
reported any failure to create as `Rebuild already running or stale lock`.
Production on 2026-10-11:

```
==> Check enrollment projections and rebuild only when stale
Error: [projections] Rebuild already running or stale lock: /srv/shiny-server/cedar/output/projections/rebuild-request.yml.lock
  refresh projections          ❌      1s       exit 1; retry on next successful data refresh
```

The deploy the evening before had taken and released that same lock cleanly
through `cedar-projections`, which is what pointed away from I6.

### Reproduction

On the droplet, from the repository, with the old command's mounts:

```bash
docker compose run --rm --no-deps -T \
  --volume "$PWD/output:/srv/shiny-server/cedar/output:rw" \
  --entrypoint Rscript cedar-shiny --vanilla -e 'dir.create("output/probe")' </dev/null
# FALSE, with "Read-only file system"; no lock directory exists
```

---

## I20 — cedar_programs holds almost no branch-campus students

**Status:** open, parked 2026-10-15. The fix is a change to the report's
population, which needs whoever owns the MyReports Academic Study report; no
CEDAR or mrgather change can recover the students. Until then, branch-campus
program counts are not usable.
**Found:** 2026-10-12, reviewing the Taos subject HHHA: class lists show 99
students declared in its certificate, and `cedar_programs` has one of their 226
student-terms.
**Severity:** high for anything about branch-campus students, none for
Albuquerque. Every count is far too low and reads as real: a branch program
shows 2 students where class lists show 99.
**Affects:** `cedar_programs`, and everything reading it for branch students:
Headcount and Dept Trends headcounts for branch units, Pathways populations,
program counts on Admin > Mappings, demographics, and each student's major
college for branch students.

### What is wrong

Class lists cover every campus. Academic Studies, which builds `cedar_programs`,
covers the main campus only. Share of class-list student-terms (Fall 2018 –
Fall 2026, by home campus) with any `cedar_programs` row:

| Home campus | Student-terms | In `cedar_programs` |
|---|---:|---:|
| ABQ | 391,357 | 95.1% |
| Gallup | 28,038 | 1.2% |
| Valencia | 23,492 | 2.1% |
| Taos | 14,692 | 0.7% |
| Los Alamos | 8,264 | 2.9% |

Taos sits under 1% in every year, so this is not a recent change.

The download itself lacks them. Neither mrgather nor CEDAR filters on campus:
`getASs()` sets the term, all fields and Excel output, and the form has all
campuses selected; parsing removes only empty rows, rows with a blank Academic
Year and exact duplicates; the transform drops only empty program slots. The
parsed file is already 99.7% Albuquerque. (Checked 2026-10-14.)

Whether a student is in it depends on where they took courses that term, not
their home campus. Share of class-list student-terms (Fall 2019 – Fall 2026)
with any program record:

| Took courses at | Albuquerque home | Branch home |
|---|---:|---:|
| Some ABQ | 97.9% | 63.2% |
| Online (EA) only | 93.6% | 74.6% |
| EA plus branch | 92.1% | 73.4% |
| Branch campuses only | **4.7%** (8,384) | **0.0%** (72,841) |

So the report's population behaves like "registered for a main-campus or
online course", whatever its campus selector says. The Degrees report, with no
associate degrees (I18), likely shares it.

Confirmed against a raw download (Fall 2026, pulled 2026-10-14 with all
campuses selected: one sheet, 24,229 rows, 59 of them branch-campus), matched
to the class lists through the same two hashes CEDAR applies:

| Fall 2026 class-list students | Count | In the raw report |
|---|---:|---:|
| Took an ABQ or EA course | 24,821 | 24,209 (97.5%) |
| Took only branch courses | 5,089 | 7 (0.1%) |

Every one of its 59 branch-campus students also took an ABQ or EA course. Not
all the missing students belong in a program report: about half of the
branch-only students are concurrent-enrollment (dual-credit) or non-degree.
But 2,873 of them had a degree major in the class lists that term, 1,452 in
programs the mapping files place in branch units (General Studies, Liberal
Arts, Welding Technology, ...), and the report has none of them.

### Reproduce

```r
source("scripts/cedar-repl.R")
cl <- dplyr::distinct(cedar_students, student_id, term, student_campus)
pr <- dplyr::distinct(cedar_programs, student_id, term) |> dplyr::mutate(found = TRUE)
dplyr::left_join(cl, pr, by = c("student_id", "term")) |>
  dplyr::group_by(student_campus) |>
  dplyr::summarise(n = dplyr::n(), pct = 100 * mean(!is.na(found)))
```

### What a fix requires

Find what the report's population is: whether the campus selector's "All"
includes Gallup, Los Alamos, Taos and Valencia; whether a branch campus picked
explicitly returns its branch-only students (a term such as Fall 2025 should
show hundreds of Taos rows, not dozens); or, failing both, ask the report's
owner. Then change the pull (or request a report that covers the branches),
re-pull the history, and rebuild.
Until then, branch-campus program counts are not usable, including the counts
the mapping review shows for branch codes.

---

## I21 — Concentrations named "Pre-" are flagged pre-majors and lose the "Pre-"

**Status:** resolved 2026-10-14. `transform_programs()` never applies the name
rules to a concentration: it is never a pre-major, keeps Banner's name, and
gets no program code from its name (a "Mathematics" concentration had been
given MATH: 950 rows). A pre-major student's major row still says so. EC-14
holds a pre-major with a "Pre-Law" concentration and a "History" concentration;
`test-transform-status.R` fails with the old rules. Rebuilt from the same
export: only those four columns on concentration rows changed; no department
or college moved.
**Found:** 2026-10-12, reading the new Counting rules table on Admin > Mappings
**Severity:** medium. Headcount and the Dept Dashboard report inflated
pre-major figures for five departments, Architecture most, and two
concentrations display under a misleading name. Department totals themselves
are unaffected: concentrations count with the student's primary major either
way.
**Affects:** `transform_programs()` in `R/data-parsers/transform-to-cedar.R`:
`is_pre_major`, `pre_major_basis` and `program_name` on concentration rows;
then every reader of `is_pre_major`, including the "Pre-majors" part of the
Headcount and Dashboard scope strips (`headcount_scope_facts()`).

### What is wrong

A program row with no `programs.csv` row falls back to Banner's name: a
"Pre-" name makes it a pre-major (`pre_major_basis = "name_prefix"`), and the
"Pre-" is stripped from the stored name. The fallback was meant for codes not
yet in the file. But concentrations have no code at all, so every
concentration takes it. Banner names two concentrations "Pre-Professional
Architecture" and "Pre-Law"; they are tracks within a major, not pre-majors
leading to a program.

All 5,606 name-flagged rows are concentration rows (4,547 Professional
Architecture, 1,059 Law); no coded program takes the fallback. In Fall 2026:

| Department | Concentration students counted as pre-majors | Real pre-majors |
|---|---:|---:|
| ARCH | 294 | 0 |
| PHIL | 33 | 46 |
| SOCI | 27 | 375 |
| LAIS | 25 | 79 |
| POLS | 1 | 174 |

So Architecture's strip says 294 pre-majors are included, where it has none,
and the concentrations display as "Professional Architecture" and "Law".

### Reproduce

```r
source("scripts/cedar-repl.R")
cedar_programs |>
  dplyr::filter(pre_major_basis %in% "name_prefix", is_pre_major %in% TRUE) |>
  dplyr::count(program_type, program_name)
```

### What a fix requires

Apply the name fallback to coded rows only: a concentration is never a
pre-major, and keeps Banner's name. That changes the transform, so the deploy
gate rebuilds the program tables. Check first that nothing matches a
concentration by its stripped name.

---

## I22 — A mapping deploy is served from the tables it replaced until the app restarts

**Status:** resolved 2026-10-14. When the gate rebuilds anything, the deploy
puts the restart page back, restarts `cedar-shiny`, checks it again and clears
the page, so the app serves the rebuilt tables. A deploy that changes no
mapping file restarts once, as before. Running the gate before the first start
was tried and dropped: it would run beside the old app, whose sessions have
grown its memory, and a one-off rebuild beside a running app was killed for
memory on a development VM. `test-mapping-provenance.R` runs the deploy's gate
block with docker stubbed and fails without the restart. A bare
`update-data.sh` run still leaves the app on its old tables until it restarts:
the morning job's `restart-cedar.sh --update` restarts it.
**Found:** 2026-10-14, reviewing why each mapping deploy needed a manual restart
**Severity:** medium. Every mapping decision and transform fix reaches the
stored tables at deploy but not the running app: production keeps showing the
old departments for up to a day, and Admin > Data & Usage > Mappings says
STALE meanwhile. Nothing is lost; it is late.
**Affects:** the deploy script in `.github/workflows/deploy.yml`, with
`shiny-server.conf`.

### What is wrong

The deploy starts the new container, then polls the app until it answers. That
first request starts the app's R process, and `global.R` loads the tables then
on disk. Only after that does the mapping gate
(`scripts/rebuild-programs-if-mappings-changed.R`) rebuild the tables the new
files changed. `shiny-server.conf` sets `app_idle_timeout 0`, so the R process
never exits and keeps serving what it loaded until the container restarts,
normally at the morning refresh (`restart-cedar.sh --update`).

Every mapping deploy so far has done this: #125, #133, #135 rebuilt the four
mapped tables after the health check.

### Reproduce

After a deploy whose log shows `[mappings] Rebuilt: ...`, open Admin > Data &
Usage > Mappings: the banner says "Departments are STALE". `docker compose
restart cedar-shiny` clears it.

### What a fix requires

When the gate rebuilt anything, restart `cedar-shiny` and run the health check
again, inside the same guarded block so a failure leaves the previous app
serving. Running the gate before `docker compose up` would avoid the second
restart but needs the new image to run in a one-off container, as the
projection publisher does.

---

## I23 — Student IDs are hashed with the built-in default salt

**Status:** open
**Found:** 2026-10-15, answering whether a salt change would split old and new
terms
**Severity:** medium for privacy; no number is wrong. The salt is meant to make
CEDAR's student IDs impossible to link back to Banner IDs without a secret.
With the default, anyone with the code and a Banner ID can compute the
student's CEDAR ID.
**Affects:** `encrypt_if_needed()` in `R/data-parsers/transform-to-cedar.R`,
every table it builds with a `student_id`, and `docker-compose.yml`.

### What is wrong

IDs are hashed twice. Parsing stores the MD5 of the Banner ID, unsalted, in
the exports (`class_lists.qs`, `academic_studies.qs`, ...). The transform then
stores SHA-256 of that MD5 plus `CEDAR_STUDENT_SALT`, and falls back silently
to the built-in `"cedar_default_salt_change_me"` when the variable is unset.

It is unset everywhere CEDAR runs. Locally it is in neither `.env` nor
`.Renviron` nor the shell; every R step runs `Rscript --vanilla`, which skips
`.Renviron` anyway; and `docker-compose.yml` passes no environment to
`cedar-shiny` or `cedar-projections`, so the containers never see it
(confirmed in the local app container). Production uses the same compose file.

The parse-stage MD5 is weak on its own: a 9-digit Banner ID can be recovered
from its unsalted MD5 by trying every ID, so the stored exports are not
pseudonymous whatever the salt.

### Reproduce

```bash
docker exec cedar-shiny sh -c '[ -n "$CEDAR_STUDENT_SALT" ] && echo set || echo not set'
Rscript --vanilla -e 'cat(nzchar(Sys.getenv("CEDAR_STUDENT_SALT")))'   # FALSE
```

### What a fix requires

Set a secret salt in production's `.env`, pass it to both services
(`environment: CEDAR_STUDENT_SALT: ${CEDAR_STUDENT_SALT}`), and make the
transform stop when it is unset rather than use a default (the demo sets its
own). A new salt changes every student ID, consistently across terms within a
rebuilt table, since the transform rehashes every term from the stored MD5s.
But tables built under different salts no longer join, so the change must be
one complete rebuild of every table holding student IDs (`cedar_programs`,
`cedar_degrees`, `cedar_students`, `cedar_grades`,
`cedar_student_term_credits`, `cedar_next_term`, `cedar_applicants`; the
course-flow and enrollment caches hold none), checked afterwards on Admin >
Join Integrity. Salting the parse stage too means a one-time migration of the
stored exports' MD5s, not a re-pull.

---

## I24 — CI's demo browser run intermittently loses the app at Open Seats

**Status:** open (suspected; intermittent)
**Found:** 2026-10-15, its second occurrence
**Severity:** low for users: CI only, and it passes on rerun. But a red check
blocks a merge, and a habit of rerunning would hide a real failure.
**Affects:** the `Synthetic checks` job (`.github/workflows/pr-checks.yml`),
`./run-tests.sh --e2e demo`.

### What is wrong

Twice, every step passed until "Open Seats runs", which failed about 1.5
seconds after the previous step with "the CEDAR app reloaded itself 7x
mid-test": run 38259413583 (2026-10-12, #134) and run 38750323255
(2026-10-15, #139, documentation only). Neither PR touched Open Seats; both
passed on rerun.

The app's log in the run's `cedar-synthetic-diagnostics` artifact ends at the
step before (Pathways stop-outs): no error, no Open Seats request, no worker
exit. The harness guesses an out-of-memory kill. Seven reloads in 1.5 seconds
look more like the worker refusing or dropping the connection at once, but
nothing kept can tell.

### Reproduce

Not on demand. `./run-tests.sh --e2e demo` against the synthetic stack,
repeated.

### What a fix requires

First, capture enough to tell: on failure, add to the diagnostics artifact the
app container's `OOMKilled`, exit code and restart count (`docker inspect`),
`docker stats --no-stream`, the runner's free memory, and the Shiny Server log
files inside the container. Then fix what they show.

---

## I25 — Projection method selection was in-sample, and lost to the default

**Status:** resolved 2026-10-16, model 0.19.0. `select_projection_methods()`
now publishes prior same-season unless a challenger beat it by two WAPE points
on at least three earlier shared aftcasts, replays that rule at every historical
fold, and reports the realised error of what the rule would have picked.
`test-enrollment-projections.R` holds a fixture whose in-sample winner fits 2%
and whose honest record is 8%; the old code reports 2%. Two shared folds were
tried first: on the rebuilt bundle the 26 challengers they admitted on the 2026
fold scored 11.4% against the default's 8.2% on the same courses.
**Found:** 2026-10-16, auditing the Spring 2027 bundle (model 0.18.0)
**Severity:** high for the page's credibility — every Accuracy badge was a fit
to the folds that chose the method, and the selection itself made projections
worse than publishing last Spring's number.
**Affects:** `R/branches/enrollment-projections.R` selection; every published
`wape`, Depth and Accuracy axis, and prediction interval in both saved bundles.

### What was wrong

Nine candidates were ranked by WAPE on the folds every eligible method shared.
The seasonal-trend candidate needs three prior Springs, so with a 2022 history
floor the shared window was Spring 2025 and 2026 for 80 of 83 courses: the
winner was chosen on two folds, then its WAPE on those two folds was reported
as its accuracy. Measured on the bundle's own backtests:

| Strategy | Folds | WAPE |
|---|---:|---:|
| Published selection, scored on the folds that chose it | 273 | 13.7% |
| The same rule applied rolling (choose only from earlier folds) | 311 | 16.5% |
| Prior same-season everywhere, no selection | 311 | 15.9% |

Depth read "Deep" from the winner's four own folds while the choice rested on
two. `forecasting-lessons.md` had already noted the problem for structural
switching; the code did it for every row.

### Reproduction

Against the 0.18.0 Spring 2027 bundle, join `projections` to `backtests` on the
selected method and pool `abs_error / actual_classlist_total`; then re-pick per
fold using only earlier folds and pool again. The two figures above differ by
2.8 points in the wrong direction.

---

## I26 — Projection "capacity reached" was judged on ever-registered demand

**Status:** resolved 2026-10-16, model 0.19.0. `projection_capacity_metrics()`
takes census occupancy (registered + late drops), or the students registered
now for a target still filling. Planning sections and seat gaps are sized from
`projected_census_equivalent` for the same reason.
**Found:** 2026-10-16, auditing the Spring 2027 bundle (model 0.18.0)
**Severity:** moderate — the flag fed the Capacity-bounded label, the capacity
caveat, the demand signal, the five-point selection margin, and the pressure
screen, all of which read seat churn as seat pressure.
**Affects:** `add_projection_capacity_censoring()`,
`build_projection_pressure_screen()`, `projection_capacity_context()`,
`build_projection_recent_history()`, `add_projection_recommendations()`.

### What was wrong

`classlist_total >= scheduled_capacity` was the test. Ever-registered counts
every student who ever held a seat, so a course whose seats turned over once
reads as over capacity. On 284 Spring folds with usable capacity:

| Measure vs scheduled seats | Median fill | Flagged "reached" |
|---|---:|---:|
| Ever-registered (the old test) | 105% | 72% |
| Census | 94% | 17% |
| Final enrollment | 86% | 6% |

In 87 of the 284 "reached" folds, final fill was under 85%. The pressure screen
passed all 72 non-forced courses on "chronic fill" alone, so it screened
nothing. Sections were sized from the ever-registered headline, which runs 13%
above census at the median: 596 sections recommended against 505 scheduled for
the same courses, on a demand estimate only 5% above their capacity.

### Reproduction

From the 0.18.0 bundle's `backtests`, compare `mean(capacity_reached)` with
`mean(actual_census >= scheduled_capacity)` on `seasonal_last` rows.

---

# Improvements

Short entries: **what**, **where**, **done when**. Counts measured 2026-10-07;
rechecked 2026-10-14, when only `server.R` had moved (6,356 lines).
The recommended order before new features is in `ROADMAP.md`.

### Counting and definitions

**M1 — Grade-distribution buckets live outside the grade constants.** The
A/B/C/D/F/W buckets are inline in `R/branches/course-attempts.R`
(`get_grade_distribution()`). *Done when:* they are named constants in
`R/lists/grades.R` beside the DFW sets.

**M2 — Census and term type derived by hand.** `registered + dr_late` in
`R/branches/enrollment-projections.R`; `substr(term, 5, 6)` in
`R/branches/enrl.R` (2) and `R/branches/relative-terms.R`. *Done when:* they use
`add_census_enrl()` and `add_term_type_col()`.

**M3 — `max(term)` uses to review against the right-edge policy.** 29 uses:
`R/branches/population.R` 8, `R/branches/enrollment-projections.R` 5,
`R/features/dept-dashboard.R` 2, `R/features/course-report.R` 2,
`R/cones/gen-ed-conversion.R` 2, `R/branches/enrl.R` 2, and singles. Many are a
legitimate per-student latest term. *Done when:* each is either that, with a
comment, or replaced by `cedar_data_edges()`.

**M4 — Duplicated metric explanations.** *Done when:* each reconciled analysis's
explanation lives in the shared definition records (`docs/_data/definitions.yml`),
with only run-specific scope notes local.

**M5 — Missing scope notes where same-looking numbers differ.** Term scope,
campus scope, crosslists, census/final enrollment, current-term exclusion, the
grade edge. *Done when:* each such place has a visible note.

**M6 — The usage overview is not yet glanceable.** *Done when:* Admin → Data &
Usage → Usage Overview leads with key counts, unique users, departments, active
tabs, and trend, with detail behind it.

### Testing and pipeline safety

**M7 — Untested analytical code.** No direct tests for
`R/branches/credit-hours.R`; thin coverage for `R/cones/course-neighbors.R` and
`R/branches/degrees.R`; no render-path test for Course Dynamics wiring.
*Done when:* each has focused tests on the designed fixture.

**M8 — Pipeline failures that could break production updates.** *Done when:*
class-list key type drift, waitlist preservation, and parse-step failures each
have a regression test.

**M9 — `Synthetic checks` is not required on `main`.** The branch is unprotected
(checked 2026-10-07). *Done when:* the ruleset requires it (a repository-admin
setting).

**M10 — Release validation needs memory headroom.** *Done when:* the full
institutional tour has passed on a host where the VM is not near its memory
limit, and dependency changes are validated in both the native library and the
Docker image.

**M25 — The mapping validator accepts any program as a `leads_to`.**
*Status: resolved 2026-10-09.* `leads_to` was seeded from `premaj_canon`, which
mixes department and program codes, so where a department code is also a
program code it named the wrong degree: `FFCS` → `FCS`, pre-Computer Science.
Ten more named a general program or a successor (`FEE` → `ECE`, `FIDA` →
`FDMA`, `FMAR` → `FDMA`, …); all now name the pre-major's own degree, and
`FING`, whose degree has no code, has none. `.validate_program_rows()` now
refuses a confirmed pre-major in a different unit from its target (tested in
`test-catalogs.R`). A same-unit wrong target, as `FEE`'s was, still needs a
reviewer: check the target's name.

**M26 — The mapping gate rebuilds cedar_programs only.** *Status: resolved
2026-10-10.* The transform stamps programs, degrees, sections and class lists
with their mapping provenance, and the gate rebuilds whichever are stale
(`cedar_stale_mapped_tables()`), stopping if an export it needs is missing or a
rebuilt table is still stale. Before, it rebuilt only `cedar_programs`, so a
subject decision reached the course tables only at the next refresh. A
rebuild now restarts the app so it serves them (I22).

### Architecture rules (`AGENTS.md`)

**M11 — Silent fallbacks.** *Enforced since 2026-10-16* by
`tests/testthat/test-architecture.R` ("silent error fallbacks do not grow"):
every `error = function(e)` handler that hands back a value without showing,
re-raising, warning, logging, or propagating the error (returning the
condition or its message to a caller that decides) counts, and each file
carries today's count as an allowance that may only go down. Measured: 33
across 9 files — `R/modules/pathways.R` 11, `server.R` 9, `R/trunk/logging.R`
7, and one each in `R/modules/dept-trends.R`, `regstats.R`, `seatfinder.R`,
`ui-helpers.R`, `waitlist.R`, and `global.R`. Nothing remains in the cones,
branches, features, or data pipeline: `cedar_edge_note()` no longer drops its
next-term sentence when `add_term()` fails (2026-10-16), and the git
provenance capture logs why git was unavailable instead of saying nothing.
The one in the data pipeline, where AGENTS.md calls it always a bug, was
`build_lookups()` in `transform-to-cedar.R` reading the saved `cedar_lookups`
inside a `tryCatch` that returned NULL, so an unreadable file silently left
every major unnamed. Fixed 2026-10-16: an unreadable or wrong-shaped file now
stops the rebuild, and `test-transform-status.R` proves it.
*Done when:* the allowance list is empty; only the sanctioned kinds remain (a
module error shown with `showNotification()` or `handle_error()`; a degenerate
statistic returning `NA`; a logged failure in the logging layer itself).

**M12 — Cones and branches reading global data.** **Done 2026-10-16.**
`tests/testthat/test-architecture.R` ("cones and branches do not read global
state") now fails on any `data_objects`, `.GlobalEnv`, `get("cedar_…")`, or
`exists("…")` in `R/cones` or `R/branches`, except the two standalone guards
`exists("%||%")` and `exists("cedar_log_level")`; the allowance it ratcheted
over (19 across 5 files when enforcement began) is empty. What each fix did:
`R/branches/course-attempts.R` — the graded edge is `opt$data_edges`
(required, fails closed when undetermined) and the left edge `opt$min_term`,
never a global or a literal. `R/cones/sfr.R` — `get_sfr(programs, faculty)`
and `get_sfr_data_for_dept_report(programs, faculty, opt)` take their two
tables, `opt$dept_code` required (the cone has no app caller; see
`docs/developers/source-to-cedar-manifest.md` §5). `R/branches/credit-hours.R`
— `credit_hours_by_major()` takes `major_codes` from the caller (Dept Trends
passes `base$prog_codes`, the set the module labels as home majors) instead of
reading `major_to_dept` behind an `exists()` guard that fell back to the
department code as a major code; `credit_hours_by_fac(students, faculty, …)`
names its tables. `R/cones/waitlist.R` — `inspect_waitlist(students, opt,
sections, enrl_base)` and `attach_enrollment_history()` take the precomputed
`cedar_cl_enrls_base` from the Waitlists module, which gets it from `server.R`.
`R/cones/course-demographics.R` — `get_course_major_mix()` reads the
code-to-name table from `opt$major_code_to_name`, threaded from
`data_objects[["cedar_lookups"]]` through the Gen Ed module's `lookups`
argument. The two feature-layer reads of the same globals
(`R/features/regstats.R` `cedar_cl_enrls_base`, `R/features/dept-dashboard.R`
`major_code_to_name`) are outside the rule's scope and remain.

**M13 — Business logic in modules.** `R/modules/pathways.R` 38
`group_by`/`summarize` pipelines, `R/modules/cancellations.R` 10,
`R/modules/gen-ed.R` 2. *Done when:* each calculation lives in the cone or
branch that owns the question.

**M14 — Inline surfaces in `server.R`.** 6,356 lines. *Done when:* the remaining
inline tabs are modules (templates: `R/modules/headcount.R`,
`R/modules/dept-trends.R`), with logic in branches/cones/features.

**M15 — `ggplot` charts.** Six remain. *Done when:* each is native `plot_ly()`.

**M16 — Oversized files.** Cones over the 500-line budget: `pathway.R` 904,
`course-demographics.R` 679, `stopout.R` 577, `gen-ed-conversion.R` 542,
`seatfinder.R` 522. Long analytical files with repeated
filter/summarize/cache code: `enrl.R`, `regstats.R`, `credit-hours.R`,
`pathway.R`, `dept-dashboard.R`. *Done when:* each is split by sub-question or
its repeated code extracted — alongside other work on the file.

### Interface consistency

**M17 — Inline styles.** 153 `style =` attributes in module and UI code.
*Done when:* replaced by shared helpers and CSS classes
(`R/modules/ui-helpers.R`), one tab per PR.

**M18 — Bare headings.** 53 `h3()`–`h6()`. *Done when:* each is
`subtab_header()`, `dashboard_section()`, `dashboard_subsection()`, or
`section_heading()` with its one-sentence description.

**M19 — Pathways heatmap legibility.** Long course labels and dense
course-to-major views. *Done when:* labels are readable at the default size.

**M27 — Headcount lists a department's programs by name.** Its program
dropdown takes a department's programs from `cedar_lookups$program_name_lookup`
(each program name's most common department), so a name two departments share
lists under one. Counting is by each row's own department (I15); only the
choices are affected. *Done when:* the choices come from the rows'
`dept_code`, or from `unit_mapping_rows()`.

### Documentation and naming

**M20 — Function reference can go stale.** *Done when:* CI regenerates it or
fails on stale output.

**M21 — Install docs unverified.** *Done when:* a fresh install has been done
from the docs alone, and the docs corrected.

**M22 — Misleading internal names.** `course-report.R` for Course Dynamics,
`seatfinder` for Open Seats, department-profile naming. *Done when:* renamed in
focused, tested patches.

### Data model

**M23 — Campus vocabularies differ by table.** The same field name can hold codes
in one table and labels in another: `student_campus` is a name in
`cedar_programs` ("Albuquerque/Main", "Taos") and a code in `cedar_students`
("ABQ", "TA"), and no file maps one to the other, so headcounts filter on names
and course figures on codes. `institution/unm/campuses.csv` gives no expansion for EW, EF,
ELA and TAQ, and the data uses codes it does not define (05, EG, ET, TAP
locally, a few sections each). Admin > Data & Usage > Mappings shows both
(Counting rules; Campuses). The campus list moved to `institution/<id>/campuses.csv`
on 2026-10-16. *Done when:* each campus field holds one vocabulary and every
code in the data is defined or reported as a source error.

**M24 — Enrollment lifecycle labels differ by tab.** The same class-list counts
carry different names: `census_enrl` is "Census Estimate" (Enrollment),
"Census enrollment" (Course Dynamics), "Census Enrollment" (`server.R` export),
and "Enrolled" (Regstats); `first_day_proxy` (`registered + dr_all`) is "Ever
Registered Proxy" in Enrollment but described as a first-day roster in
Projections. No day-1 snapshot exists, so "first day" overclaims. A dated
reconstruction now exists — `first_day_enrl` (`calc_first_day_enrl()`, definition
`first-day-enrollment`), shown on Course Dynamics — which makes the proxy's name
actively misleading beside it: rename `first_day_proxy` to an ever-registered
name. *Done when:* each lifecycle column has one label, from
`docs/_data/definitions.yml`, used everywhere it is shown.

**M28 — The HR department list is a hand-kept R list.** **Done 2026-10-16.**
`hr_org_desc_to_dept` (79 names to 32 departments) now comes from
`institution/<id>/source_organizations.csv`, validated at load so every unit
it names is in `units.csv` (`validate_text_maps()`; `test-catalogs.R`).
Organisations not on it are still dropped when the HR report is parsed, and
the report is no longer pulled, so retiring it with the faculty table remains
open (see `docs/developers/source-to-cedar-manifest.md` §5).
