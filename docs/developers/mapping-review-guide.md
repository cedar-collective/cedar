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
  organisation IDs leaking into the major-code column. List them for whoever
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
| `major_code` | `cedar_programs`, `cedar_degrees`; `programs.csv` `program_code` | `RADS` | the program a student declared |
| `dept_code` | `units.csv` `unit_code`, written onto every table | `RADS` | the academic department (unit) |
| `subject_code` | the prefix in `subject_course`; `subjects.csv` | `RADS 101` | the course subject |

They often coincide, which is why the collisions are easy to miss. `FCS` is a
pre-major code for Computer Science **and** the department code for Family and
Child Studies. `FORS` is a major code, a department code, and a course subject
all at once. A `leads_to` must name a program code, never a department code —
`FFCS` once led to `FCS`, pre-Computer Science (the validator now refuses a
target in another unit).

```r
# Which namespaces does a string live in?
code <- "FCS"; f <- cedar_institution_files
c(program = code %in% f$programs$program_code,
  unit    = code %in% f$units$unit_code,
  subject = code %in% f$subjects$subject_code)
```

## Prioritise by program type, not just headcount

`program_type` decides how much an undecided code costs. A student's **Major**
determines their home unit and appears in every department report; a **Minor**
mostly does not. `scripts/mapping-review.R` and the Admin table already sort by
students; read the Kind column before the size.

## The files, and what to look at in each

All in `institution/unm/`; `README.md` there gives every column.

### `programs.csv` — the one that goes wrong most

One row per program code (optionally per college): its unit, whether it is a
pre-major, the program it `leads_to`, why (`basis`), and whether a person has
confirmed it (`status`).

- **`is_pre_major`** is stated, not inferred. **Look for** a flag that disagrees
  with Banner's own program record: main-campus pre-majors are named "Pre-" in
  the Academic Studies `Program` field ("BS Pre-Exercise Science") and award no
  degrees. Branch-campus "Pre-" programs ("AS Pre-Engineering") are associate
  degrees students are admitted to, not pre-majors — and the degrees export
  carries no associate degrees, so "no degrees" is no evidence there (ISSUES I18).
- **`leads_to`** translates a pre-major to its major and nothing else. **Look
  for** a target whose name is not the pre-major's own degree.
- **`basis = no_unit`** — programs no department owns, such as Non-Degree and
  Undecided. **The bar is "nothing owns this", never "nobody has worked out
  what owns this."** A no_unit row may still name a college (Undecided: UC).
- **`in_college` rows** — a code whose unit differs in one college (CRIM and
  BADM at the branch campuses).

### `subjects.csv` — course subject to unit

Keyed on subject, section college and level; the most specific confirmed row
wins. **Look for** a branch-campus row for a main-campus unit without
`college_code` AD (branch sections stay in the branch college).

### `units.csv` and `colleges.csv`

The authoritative unit list, each with its home college, and every spelling a
source uses for a college (`source_names`). **Look for** a department you know
exists that is not in the file, and a renamed college whose old name is missing.

### `R/lists/mappings.R` — text → code

`major_name_to_major_code` and `hr_org_desc_to_dept` translate free text from
Banner and HR exports. Text maps rot when the source system renames something.
**Look for:** names that no longer appear in current exports.

### `R/lists/data_semantics.R` — what the data means

Not a mapping, but read it alongside them: it records codes whose *meaning*
changed, which is different from codes that are mapped wrong.

## The failure signatures

Learn these and most problems become visible on sight.

**1. A code with no department.** Since ADR-002 Stage 3 an unconfirmed code has
no unit (`NA`) and appears on Admin > Mappings. Before then it got a department
named after itself, which no report could tell from a real one (ISSUES I7);
EC-14 fails if that fallback returns.

**2. A prefix assumption.** Any rule keyed on the first letter of a code is a
guess about naming, not a fact about programs: F did not mark every pre-major,
and not every "Pre-" program is one. Check `pre_major_basis`: `programs_csv`
means the file decided; `name_prefix` means the code has no row and Banner's
name was used.

**3. A drifted name.** `FMDL` is "Medical Laboratory Science", `MEDL` is
"Medical Laboratory Sciences". Anything matching programs by name splits that
pair silently. `population_group_audit()` reports these as near misses.

**4. Many majors, few graduates.** A program carrying far more declared majors
than it graduates is usually recording intent rather than admission. Not a
mapping error, but it reads like one.

**5. A code with no row at all.** A program or subject the data uses that no
file lists. The mapping audit lists it ("A programs.csv row"); run
`scripts/propose-mappings.R --write` to add a proposed row with the evidence.

## Queries, when you want them

```r
source("scripts/cedar-repl.R")
f <- cedar_institution_files

# Undecided codes, largest first: the same list as Admin > Mappings
source("scripts/mapping-review.R")

# Pre-majors with no target in the file
f$programs |> dplyr::filter(is_pre_major == "TRUE", !nzchar(leads_to)) |>
  dplyr::select(program_code, program_name, unit_code, status)

# Rows whose pre-major flag came from Banner's name, not the file
cedar_programs |> dplyr::filter(pre_major_basis == "name_prefix") |>
  dplyr::count(major_code, program_name, sort = TRUE)

# Does a "pre-major" award degrees? If so it is not one (main campus only: I18)
cedar_degrees |>
  dplyr::filter(major_code %in% f$programs$program_code[f$programs$is_pre_major == "TRUE"]) |>
  dplyr::count(major_code, sort = TRUE)

# Rows reporting Banner's college because their code is undecided
cedar_programs |> dplyr::filter(college_basis == "banner") |> dplyr::count(major_code, college_code)
```

## Resolving one mapping, start to finish

Worked example: **Military Studies (`MLST`)**, a minor whose row is still
proposed, so its students count toward no department.

### 1. Decide what it should be

Two possible answers, and they are not the same:

- **It has an owner.** Find the real unit code in `units.csv`. The assistant
  suggests NVSC (its students take Naval Science courses); MLSL (Military
  Science & Leadership) also exists. Someone who knows the program decides.
- **Nothing owns it.** Non-Degree and Undecided are the clear cases. Then its
  row gets `basis = no_unit` and no unit.

Do not guess between these. A wrong department is invisible once written.

```r
source("scripts/cedar-repl.R")
units <- cedar_institution_files$units
units[grepl("milit|naval", units$unit_name, ignore.case = TRUE), ]
cedar_programs |> dplyr::filter(major_code == "MLST") |>
  dplyr::summarise(students = dplyr::n_distinct(student_id),
                   first = min(term), last = max(term))
```

### 2. Make the edit

In `institution/unm/programs.csv` (or `subjects.csv` for a course subject), on
the code's row:

| To | Change |
|---|---|
| Accept the suggestion | `status` → `confirmed`; `basis` stays |
| Choose another unit | `unit_code`, `basis` → `decided`, `status` → `confirmed` |
| Say nothing owns it | `unit_code` blank, `basis` → `no_unit`, `status` → `confirmed` |
| Mark a pre-major | `is_pre_major` → `TRUE`; `leads_to` → its own degree's program code, if it has one |
| Credit a different college | `college_code` (a program's own college; a subject row's credited college) |

**Write the reason in `notes`**, with the date. An unexplained mapping is the
next person's unanswerable question. Commit on a branch, one decision per
commit, through a pull request: the app never edits the files.

### 3. Rebuild — automatic on deploy and data refresh

`scripts/rebuild-programs-if-mappings-changed.R` runs on every deploy and every
`scripts/update-data.sh` run. It hashes the files that decide units and colleges
(`cedar_mapping_source_files()`), compares them with the fingerprint stamped on
each of `cedar_programs`, `cedar_degrees`, `cedar_sections` and
`cedar_students`, and rebuilds only the tables that differ. It stops, rather
than reporting success, if an export it needs is missing or a rebuilt table is
still stale.

The hash covers whole files, comments included, so Admin > Data & Usage reports
STALE after any edit to them, even one that moves no department. The rebuild
clears it. To apply an edit now: `Rscript --vanilla
scripts/rebuild-programs-if-mappings-changed.R` (`--force` rebuilds all four).

**Rebuild from the exports the transform reads** (`cedar_shared_data_dir`), not
an old local copy: a stale `academic_studies.qs` faithfully reproduces stale
programs.

### 4. Verify

```r
source("scripts/cedar-repl.R")
cedar_programs |> dplyr::filter(major_code == "MLST") |>
  dplyr::count(dept_code, college_code, college_basis)   # the decided unit, "mapped"
```

The code leaves Admin > Mappings' decisions table. Nothing else should move: a
decision changes only the rows of its own code.

### 5. Restart the app

`docker compose restart cedar-shiny`. The data is bind-mounted but the R worker
reads it at startup.

## Working through a backlog

Do not work alphabetically. Rank by students affected and stop when the tail goes
quiet — a handful of programs usually carry most of the impact, and the long tail
of one- and two-student programs can wait indefinitely without harming a report.
`scripts/mapping-review.R` lists them in that order. Rebuilding once after
several decisions is fine.
