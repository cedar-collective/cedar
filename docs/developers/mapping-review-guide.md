---
title: Reviewing the mappings — a reader's guide
---

# Reviewing the mappings

**Who this is for:** someone with catalog knowledge and a text editor, who needs
to find where CEDAR's mappings are wrong. No R required for most of it; the
queries are here for when you want them.

Mapping errors do not announce themselves. A wrong department produces a
plausible number, and the last tier of the lookup chain guarantees a value even
when nothing matched. So the job is not "look for errors" — it is "look at the
places where a wrong answer would be invisible."

## Start here: the Admin page

**To work through decisions locally**, run
`Rscript --vanilla scripts/mapping-review.R`: it lists everything that needs a
decision as `institution/unm/<file>.csv:<line>`, which VS Code's terminal opens
at the row. Undecided rows carry `status = proposed` in `programs.csv` and
`subjects.csv`. Edit, commit on a branch, push. The Admin page's GitHub links
point at `main` and work once the files are merged there.

**Admin > Data & Usage > Mappings** is the shortest path. It has two tables,
by the kind of work:

- **Mapping decisions** — everything settled by editing a file in
  `institution/unm/`: programs and course subjects awaiting a decision, codes
  the data uses that no file has, college values no file names, units with no
  college, and mapped colleges Banner's Translated College disagrees with.
  Largest first. Columns:

  | Column | What it says |
  |---|---|
  | Needs | What to supply, as a link to the row's line (or the file, for a new row) |
  | Where | The same place as `file.csv:line`, for a local checkout |
  | Reported today as | The unit the stored tables carry now. Since ADR-002 Stage 3 that comes from these files, so an unconfirmed code reads *none*; *phantom* (a department named after the code itself) appears only in tables built before Stage 3 |
  | Kind, Banner code | What the row is (program major/minor/pre-major, course subject, college) and Banner's code for it |
  | Suggested department | The unit the assistant suggests should own it, with its name |
  | Confidence | Strong (the source's own department, matching names or subject code, a pre-major's target), Plausible (clear course-taking: 5x the usual rate or more, over 100 or more enrolments), Weak (otherwise, or in a catch-all source department), with the evidence on hover. `.suggestion_confidence()` in `R/features/admin.R` |

  To accept a suggestion, change the row's `status` to `confirmed`; `basis`
  stays as the reason it was suggested. To choose otherwise, also change
  `unit_code` (or `college_code`) and, in `programs.csv`, set `basis` to
  `decided`. A note in `notes` saying why helps the next reader. Commit through
  a pull request; the app never edits the files, because the running container
  holds a copy of the source that the next deploy replaces.

- **Other problems in the data** — what no mapping can fix: Banner
  organisation IDs leaking into the major-code column, and codes only the old
  `program_map` checks report (which Stage 4 retires). List them for whoever
  owns the source.

Expected differences — pre-majors reporting under the college they lead to —
are counted, not listed. A decision changes reported numbers at the next
rebuild: the deploy gate rebuilds every table built from older mapping files —
programs, degrees, sections and class lists each carry a stamp of the files
that built them. `scripts/mapping-review.R` prints the same two lists in
the terminal.

Below them, the lookup tables show what *is* mapped today.

Everything below is how to reach the same conclusions by reading files.

## First: which code are you looking at?

Three different namespaces use short uppercase strings, and **the same string can
appear in all three meaning different things.** Every screen and every table in
this guide reports `major_code` unless it says otherwise.

| Namespace | Lives in | Example | What it identifies |
|---|---|---|---|
| `major_code` | `cedar_programs`, `cedar_degrees` | `RADS` | the program a student declared |
| `dept_code` | `subj_dept_map`, derived onto programs | `RADS` | the academic department |
| `subject_code` | the prefix in `subject_course` | `RADS 101` | the course subject |

They often coincide, which is why the collisions are easy to miss. `FCS` is a
pre-major code for Computer Science **and** the department code for Family and
Child Studies. `FORS` is a major code, a department code, and a course subject
all at once.

A collision cannot be fixed by mapping the code, because the code already
resolves — to the wrong thing for one of its meanings. It needs a
`major_college_to_dept` entry keyed on the college, which is why the screens call
it out separately in their `details`.

```r
# Which namespaces does a string live in?
code <- "FCS"
c(major   = code %in% cedar_programs$major_code,
  dept    = code %in% subj_dept_map$dept_code,
  subject = code %in% subj_dept_map$subject_code)
```

## Prioritise by program type, not just headcount

`program_type` decides how much a wrong department costs. A student's **Major**
determines their home unit and appears in every department report; a **Minor**
mostly does not. Of the flagged rows, more than a third are minors.

The mapping backlog worth working is *majors in a phantom department*:

```r
rep <- build_data_anomaly_report(cedar_programs, cedar_degrees,
                                 known_departments = subj_dept_map$dept_code)
phantom <- rep |> dplyr::filter(issue_type != "declared_majors_far_exceed_graduates")

cedar_programs |>
  dplyr::filter(major_code %in% phantom$major_code, term >= 202410L,
                program_type %in% c("Major", "Second Major")) |>
  dplyr::group_by(major_code) |>
  dplyr::summarise(students = dplyr::n_distinct(student_id), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(students))
```

Note the filter dropping `declared_majors_far_exceed_graduates`. That screen is
**not** a mapping problem — it flags programs whose code records intent rather
than admission, and those are usually mapped perfectly. Mixing it into a mapping
worklist produces a to-do list where the top entries need no work.

## The files, and what to look at in each

> **Since ADR-002 Stage 3 (2026-10-09), every stored unit comes from
> `institution/unm/*.csv`.** The lists in `R/lists/program_code_maps.R`
> described below no longer decide any stored `dept_code`; they feed only the
> runtime lookup vectors until Stage 4 retires them. Make decisions in the CSV
> files, as above. The failure signatures and queries below still apply to
> reading the data.

All live in `R/lists/`. Files whose first line says `# CEDAR-INSTITUTION:` are
UNM's; `# CEDAR-PLATFORM:` files are mechanism you should not need to touch.

### `program_code_maps.R` — the one that goes wrong most

Six lists, each a different way a Banner code can mislead:

- **`premaj_canon`** — pre-major code → the major it leads to. *Missing entries
  are the most damaging error in the whole pipeline.* A pre-major with no entry
  gets a department named after itself, and its students vanish from their real
  unit. This is how Radiologic Sciences reported 35 students when it had 229
  (ISSUES.md I7).
  **Look for:** any F-prefixed code in the data that is not a key here.
- **`real_F_progs`** and **`pre_major_exempt_codes`** — the exceptions to
  "F means pre-major". **It very often does not.** `FREN` is French, `FRST`
  French Studies, `FCST` Family & Child Studies, `FDMA` Film and Digital Arts —
  real programs that award degrees. All four were flagged as pre-majors at some
  point purely because of their first letter.
  **Look for:** a code in one list but not the other. They serve different
  consumers, so that is not automatically wrong — but it is always worth asking.
- **`xvar_explicit`** — X-prefix variant → canonical code. Same failure shape as
  `premaj_canon`.
- **`extra_p2d`** — major code → department, for codes absent from
  `subj_dept_map`. **Look for:** entries with no comment saying why.
- **`ad_major_to_dept`** — branch-campus overrides, only where the branch
  department differs from main campus.
- **`allowed_unmapped_program_codes`** — reviewed exceptions. **Look for:** the
  `NEEDS RESEARCH` block, which is parked questions rather than settled ones.
- **`department_less_major_codes`** — programs no department owns, such as
  Non-Degree and Undecided. **The bar is "nothing owns this", never "nobody has
  worked out what owns this."**

### `institution/unm/*.csv` — subject → department → college

The authoritative department list, as plain CSV files (`colleges.csv`,
`units.csv`, `subjects.csv`; see ADR-002). If a department is missing here,
every code that should map to it falls through.
**Look for:** a department you know exists that is not in the file.

### `mappings.R` — text → code

`major_name_to_major_code` and `hr_org_desc_to_dept` translate free text from
Banner and HR exports. Text maps rot when the source system renames something.
**Look for:** names that no longer appear in current exports.

### `data_semantics.R` — what the data means

Not a mapping, but read it alongside them: it records codes whose *meaning*
changed, which is different from codes that are mapped wrong.

## The four failure signatures

Learn these and most problems become visible on sight.

**1. A department named after a program code.** `dept_code == major_code` where
that code is not a real department. Guaranteed wrong for a pre-major. The
identity fallback exists so `dept_code` is never empty, which means an unmapped
program is indistinguishable from a mapped one.

**2. An F-prefix assumption.** Any rule keyed on the first letter of a code is a
guess about naming, not a fact about programs. Check `pre_major_basis`: a row
reading `code_convention` was decided by the prefix alone, with no supporting
name.

**3. A drifted name.** `FMDL` is "Medical Laboratory Science", `MEDL` is
"Medical Laboratory Sciences". Anything matching programs by name splits that
pair silently. `population_group_audit()` reports these as near misses.

**4. Many majors, few graduates.** A program carrying far more declared majors
than it graduates is usually recording intent rather than admission. Not a
mapping error, but it reads like one.

**5. A program that is not in `program_map` at all.** `generate_program_map()`
discards any program whose college suffix is not in `known_suffixes`, before the
unmapped check runs — so it produced no warning until one was added. `BA-FLAI-US`
and `BSCNE-FCOE-E` vanished this way: the suffixes `US` and `E` are unlisted, and
their students went straight to the identity fallback. If a code has no map row
at all, check its program code's third segment first.

```r
# Programs the map never saw
pm <- qs2::qs_read(file.path(cedar_data_dir, "program_map.qs"))
setdiff(unique(cedar_programs$major_code), pm$major_code) |> head(20)
```

## Queries, when you want them

```r
source("scripts/cedar-repl.R")

# Everything the screens can find, in one table
build_data_anomaly_report(cedar_programs, cedar_degrees,
                          known_departments = subj_dept_map$dept_code)

# Pre-majors with no canonical target -- the most damaging gap
cedar_programs |>
  dplyr::filter(is_pre_major, !major_code %in% names(premaj_canon)) |>
  dplyr::count(major_code, program_name, sort = TRUE)

# Rows flagged pre-major on the strength of the code alone
cedar_programs |>
  dplyr::filter(pre_major_basis == "code_convention") |>
  dplyr::count(major_code, program_name, sort = TRUE)

# Does a "pre-major" award degrees? If so it is not one.
cedar_degrees |>
  dplyr::filter(major_code %in% unique(cedar_programs$major_code[cedar_programs$is_pre_major])) |>
  dplyr::count(major_code, sort = TRUE)

# Departments a program claims that do not exist
setdiff(unique(cedar_programs$dept_code), subj_dept_map$dept_code)
```

## Resolving one mapping, start to finish

Worked example: **Military Studies (`MLST`)**, 179 students sitting in a
department called `MLST` that does not exist.

### 1. Decide what it should be

Two possible answers, and they are not the same:

- **It has an owner.** Find the real department code. `MLSL` (Military Science &
  Leadership) exists in `institution/unm/units.csv`, which settles it.
- **Nothing owns it.** Non-Degree and Undecided are the clear cases. Then it
  belongs in `department_less_major_codes`, not in a mapping.

Do not guess between these. A wrong department is invisible once written — that
is the whole reason this backlog existed.

```r
source("scripts/cedar-repl.R")
# What departments exist that could plausibly own it?
subj_dept_map |> dplyr::filter(grepl("milit", dept_name, ignore.case = TRUE)) |>
  dplyr::distinct(dept_code, dept_name)

# How many students, over what period, so you know what you are moving
cedar_programs |> dplyr::filter(major_code == "MLST") |>
  dplyr::summarise(students = dplyr::n_distinct(student_id),
                   first = min(term), last = max(term))
```

### 2. Make the edit

All in `R/lists/program_code_maps.R`. Which list depends on what kind of code it
is:

| The code is | Put it in | Example |
|---|---|---|
| A declared program with a department | `extra_p2d` | `MLST = "MLSL"` |
| A pre-major leading to a program | `premaj_canon` | `FRAD = "RADS"` |
| An X-prefix variant | `xvar_explicit` | `XFDE = "DEHY"` |
| A branch program whose department differs from main campus | `ad_major_to_dept` | `CRIM = "CJUS"` |
| Owned by nobody | `department_less_major_codes` | `NOND`, `UNDC` |
| Real, but its F prefix makes it look like a pre-major | `pre_major_exempt_codes` | `FREN`, `FCST` |

**Write the reason next to the entry.** Every existing entry has one. An
unexplained mapping is the next person's unanswerable question.

### 3. Rebuild — automatic on deploy and data refresh, manual if you want it now

`scripts/rebuild-programs-if-mappings-changed.R` runs on every deploy and every
`scripts/update-data.sh` run, local or production — including a refresh that
skips an export and so would otherwise leave a table built from the old
mappings. It hashes the files that decide units (`cedar_mapping_source_files()`),
compares them against the fingerprint stamped onto each of `cedar_programs`,
`cedar_degrees`, `cedar_sections` and `cedar_students`, and rebuilds only the
tables that differ — so a mapping edit reaches production without anyone
remembering to do anything, and a deploy that changed no mapping costs seconds.

The hash covers whole files, comments included, so Admin > Data & Usage reports
STALE after any edit to them, even one that moves no department. The rebuild
clears it.

To apply an edit immediately rather than waiting for a deploy or refresh:

```bash
Rscript --vanilla scripts/rebuild-programs-if-mappings-changed.R
```

`--force` rebuilds regardless. You need it if a table was stamped by a build that
did **not** regenerate `program_map.qs`, because the stamp then asserts something
false and the gate will skip a rebuild that is genuinely needed.

The rest of this section is what the gate does for you, and what to do if you
rebuild by hand.

### 3b. Rebuilding by hand — the edit alone does nothing

`program_map.qs` is generated, and `cedar_programs$dept_code` is written during
the transform. Editing a list changes neither until you rebuild. Three traps,
each of which silently produces a wrong or unchanged result:

1. **Generate from the shared data directory**, not `data/`. The repo's local
   copy of `academic_studies.qs` may be months behind; generating from it
   faithfully reproduces a stale map.
2. **`rm(program_map)` first.** `transform_to_cedar()` skips the regenerate when
   `program_map` already exists in the session, and `load_funcs()` defines it —
   so a script that loads CEDAR functions first rebuilds against the old map
   *and reports success*.
3. **Never move the map aside** to force a regenerate. The running app reads it
   from the shared directory; removing it breaks startup.

```r
SOURCED_FROM_PARSE_DATA <- TRUE          # sourcing the transform runs it otherwise
source("config/config.R"); source("R/trunk/load-funcs.R")
load_funcs(cedar_base_dir, modules = FALSE)
source("R/data-parsers/transform-to-cedar.R")

pm <- generate_program_map(
  file.path(cedar_shared_data_dir, "academic_studies.qs"), ".qs",
  subj_dept_map, premaj_canon, xvar_explicit, extra_p2d, known_suffixes,
  real_F_progs, get_lev, ad_major_to_dept, allowed_unmapped_program_codes)
nrow(pm)                                  # sanity-check before saving
qs2::qs_save(pm, file.path(cedar_shared_data_dir, "program_map.qs"))
qs2::qs_save(pm, file.path(cedar_data_dir, "program_map.qs"))

rm(program_map)
transform_to_cedar(tables = "programs")
```

### 4. Verify, and expect an exact number

Two checks. The first confirms the students moved; the second confirms nothing
else did.

```r
source("scripts/cedar-repl.R")
cedar_programs |> dplyr::filter(major_code == "MLST") |>
  dplyr::count(dept_code)                 # expect MLSL, not MLST

build_data_anomaly_report(cedar_programs, cedar_degrees,
                          known_departments = subj_dept_map$dept_code) |> nrow()
```

The flagged count should fall by **exactly** the number of programs you mapped.
If it falls by more, something else changed and you should find out what. If it
falls by less, the rebuild did not take — check trap 2.

### 5. Restart the app

`docker compose restart cedar-shiny`. The data is bind-mounted but the R worker
reads it at startup.

## Working through a backlog

Do not work alphabetically. Rank by students affected and stop when the tail goes
quiet — a handful of programs usually carry most of the impact, and the long tail
of one- and two-student programs can wait indefinitely without harming a report.

```r
rep <- build_data_anomaly_report(cedar_programs, cedar_degrees,
                                 known_departments = subj_dept_map$dept_code)
cedar_programs |>
  dplyr::filter(major_code %in% rep$major_code, term >= 202410L) |>
  dplyr::group_by(major_code) |>
  dplyr::summarise(students = dplyr::n_distinct(student_id), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(students))
```

Rebuilding once after several edits is fine and faster than rebuilding per
change — the verification in step 4 still works, you simply expect the count to
fall by the number of programs in the batch.
