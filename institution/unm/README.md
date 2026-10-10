# UNM mapping files

CEDAR reads these files to decide which unit (department) every course and
program belongs to. Edit them here; no code changes are needed. They are validated at startup,
and a malformed file stops the app with every problem listed.
See `docs/developers/adr-002-explicit-mapping-files.md`.

| File | One row per | Columns |
|---|---|---|
| `colleges.csv` | college | `college_code`, `college_name`, `source_names` |
| `units.csv` | unit (department) | `unit_code`, `unit_name`, `college_code`, `kind`, `notes` |
| `subjects.csv` | course subject, optionally within a section college or level | `subject_code`, `in_college`, `in_level`, `unit_code`, `college_code`, `status`, `evidence`, `notes` |
| `programs.csv` | program code (optionally within a college) | `program_code`, `in_college`, `program_name`, `unit_code`, `college_code`, `is_pre_major`, `leads_to`, `basis`, `status`, `evidence`, `notes` |
| `source_departments.csv` | department name as Banner exports it | `source_name`, `unit_code`, `kind`, `notes` |
| `settings.csv` | institution setting | `setting`, `value` |

**Every row is one line.** No blank lines and no line breaks inside a field:
Admin > Mappings links to rows by line number, and the loader refuses a file
where row and line disagree.

`settings.csv` holds `mapping_files_url`, the GitHub location of this directory
(a `blob` URL). Admin > Data & Usage > Mappings uses it to link each program
awaiting a decision to its line here; a fork points it at its own repository.
`source_files_url` is the repository root, for links to platform files that
still hold mappings. Optional `source_values_without_college` lists source
college values that deliberately name no college (`Non-Degree Status`), so the
mapping audit does not report them as unknown.

## Colleges are mapped, not read

A program's college is its unit's home college (`units.csv`), unless its own
row sets `college_code` (Biochemistry: taught by Medicine, its majors in Arts &
Sciences), and a pre-major reports under the college of the program it leads
to. Graduate students report under their academic unit's college, not Banner's
Graduate Programs. `colleges.csv` `source_names` lists every other spelling and
former code a source uses (`College of Education|ED` for EH). See ADR-002,
"Colleges are mapped, not read". Unit colleges and the six program colleges were
proposed on 2026-10-04 by `scripts/unit-mapping-baseline.R colleges`, from
where each unit's sections sit since Spring 2024 and Banner's Translated
College; each row's `notes` gives the evidence.

The transform reports these colleges (ADR-002 Stage 3b, decided 2026-10-10):

- **A student counts under their primary major's college** that term, on every
  row they have (`college_code`, `student_college`); each row also carries its
  own program's college (`program_college`).
- **A course counts under its subject row's `college_code`, else its unit's
  home college.** Branch-campus rows (`in_college` AD) for main-campus units set
  `college_code` AD, so branch sections stay in the branch college.
- **A program nothing owns may still name a college**: Undecided is UC's.
- **A code not yet decided reports Banner's college**, translated through
  `source_names` and labelled `college_basis = banner`, until its row is
  confirmed; Admin > Mappings says so on its row.
- Banner's own values stay beside them as `source_college` (and
  `source_college_code` on programs), for the audit.

Admin > Data & Usage > Mappings lists every value the data uses that these files
do not cover, and every program whose mapped college differs from Banner's
Translated College, with a link to the file that fixes it.

The transform reads these files (ADR-002 Stage 3): every stored unit —
`dept_code` on programs and degrees, `department` on sections and class lists —
comes from a confirmed row here, and a code with no confirmed row has none.
A decision reaches the app when the deploy gate rebuilds the tables built
from the old files: programs and degrees for `programs.csv`, sections and
class lists for `subjects.csv`, all four for `units.csv` or `colleges.csv`.

## programs.csv

- **Only `confirmed` rows assign a unit.** A `proposed` row is the mapping
  assistant's suggestion, with the evidence it saw; it assigns nothing until
  someone changes `status` to `confirmed`. **To accept the suggested unit,
  change `status` to `confirmed`** -- `basis` stays as the reason it was
  suggested. To choose a different unit, also change `unit_code` and set
  `basis` to `decided`. Either way, a note in `notes` saying why helps.
- **A blank `in_college` applies in every college.** A row with one wins over
  it there: `CRIM` is Sociology, but `CRIM` in college `AD` (branch campuses)
  is Criminal Justice. `college_code` is different: the program's own college,
  when it is not its unit's.
- **`basis` says why the row names its unit:** `source_department` (Banner's
  Department, through `source_departments.csv`), `subject_code` (the code is
  also a course subject), `inherited` (a pre-major takes its target's unit),
  `name_match`, `course_taking`, `decided` (a person chose), `override` (a
  college-specific row), `no_unit` (nothing owns the program: Non-Degree,
  Undecided), `unresolved` (no evidence settled it; always `proposed`).
- **`is_pre_major` and `leads_to` translate a pre-major to its major, and
  nothing else.**
  - `is_pre_major` says *whether* the code is a pre-major (`TRUE` / `FALSE`),
    stated rather than inferred from an F prefix.
  - `leads_to` says *which program* a pre-major leads to: the `program_code` of
    the degree its own Banner record names. `FFCS` is "BS Pre Family & Child
    Studies", so it leads to `FCST`, Family & Child Studies. It is blank on
    every row that is not a pre-major (the loader refuses it), and blank on a
    pre-major whose degree has no code in the data: `FING` is the pre-major
    for the Bachelor of Integrative Studies, which has none.
  - **Always a program code, never a department code.** The two share strings:
    `FCS` is Family & Child Studies' department and pre-Computer Science's
    program code, so `FFCS` → `FCS` named the wrong degree. Check the target's
    row: the same unit and a matching name.
  - **Not history.** A code that replaced another (BIS by BISI, course subject
    `ALB` by `ALBS`) is lineage. Record it in `notes` until `code_history.csv`
    exists (ROADMAP, "Code history"), and never point `leads_to` at a successor
    to stand in for a degree with no code.
  - What reads it: a pre-major's college, when its target sets its own
    `college_code`; the mapping assistant, which gives a pre-major its target's
    unit (`basis = inherited`); and the named population groups in Pathways and projections, which count a
    program's pre-majors through it.
- **A code with no row gets no unit.** It is never reported under a department
  named after itself.
- Concentrations have no rows: they take the unit of the student's primary
  major.

New codes: run `Rscript --vanilla scripts/propose-mappings.R --data-dir <shared data dir>`
to see proposals, and add `--write` to append them as `proposed` rows. Point
`--data-dir` at the exports the transform reads; the repository's `data/` can
hold an older copy that is missing recent programs.

## source_departments.csv

What each Banner `Department` means, so the assistant can propose from it. The
transform never reads it. `kind` is one of:

- `department` — one unit owns its programs.
- `split` — a Banner department CEDAR reports as several units (Theatre & Dance
  is THEA and DANC). `unit_code` lists the candidates, `|`-separated; each
  program is placed among them by its subject code, name, or course-taking.
- `bucket` — a holding name that owns nothing (`*Interdisciplinary: A.S.`,
  `Provost Branch Campuses`); programs in it need their own evidence.
- `non_degree` — its programs belong to no unit (Non-Degree, Undecided).

Banner renames departments: a new spelling needs its own row (`Cinematic Arts`
beside `Film and Digital Arts`).

## subjects.csv

- **Which rows apply:** `in_college` (the source's section college) and
  `in_level` (`lower`, `upper`, `grad`) narrow a row; blank means any. The most
  specific confirmed row wins: subject + college + level, then subject +
  college, then subject + level, then subject alone. A section's college is
  first translated through `colleges.csv`, so a former code (`ED` for `EH`)
  matches its college's rows.
- **Which college is credited:** `college_code`, when it is not the unit's home
  college. Global & National Security is one unit, so its director sees both
  levels, but its undergraduate courses are credited to University College and
  its graduate courses to Graduate Studies:

      GLNS,,grad,GLNS,,confirmed,...
      GLNS,,,GLNS,UC,confirmed,...

- **Courses a college owns directly** belong to a unit of `kind = college`,
  coded as the college code plus `CW`: `ARSC` → `ASCW`, "Arts & Sciences
  (college-wide)". A college-wide unit is never named with the bare college
  code, which already means the college (as `ME` means the School of Medicine,
  not the Mechanical Engineering unit).

## Working through decisions

Everything that needs a decision is a row with `status = proposed`, in
`programs.csv` or `subjects.csv`, with the evidence the mapping assistant saw.
Filter on that column, or run

    Rscript --vanilla scripts/mapping-review.R

which lists every item as `institution/unm/<file>.csv:<line>` (click it in VS
Code's terminal), plus what no row can show: program codes with no row,
college values no row names, and programs whose mapped college differs from
Banner's. To accept a suggestion, change `status` to `confirmed`; to choose
otherwise, also change `unit_code` (or `college_code`) and, in `programs.csv`,
set `basis` to `decided`. Commit on a branch. Admin >
Data & Usage > Mappings shows the same list, each row with its `file:line`. New
codes in the data get proposed rows from `scripts/propose-mappings.R --write`.

**Row order.** `programs.csv`, `units.csv`, `colleges.csv` and
`source_departments.csv` are sorted by their first column; keep them so.
**`subjects.csv` is not, and must not be sorted yet:** the transform takes the
most specific row, but the runtime lookups built from `subj_dept_map` still
take the first row for a subject code regardless of college, until ADR-002
Stage 4. For a subject listed under two colleges (`HLED`, `PH`, `SUST`) the
order decides which unit those lookups use. Only confirmed rows are looked up.
New rows go at the end.

**A subject can appear under two colleges with different units.** Branch
campuses reuse subject codes (for example `HLED`, `PH`, `SUST`) for units that
differ from the main campus's.

## Provenance

Derived from UNM's schedule key (https://xmlschedule.unm.edu/docs/schedule-key.html),
with deliberate overrides for interdisciplinary and special programs, recorded
in the `notes` column. Converted from `R/lists/subj_dept_map.R` on 2026-10-03
with no change to any mapping.

`source_departments.csv` was seeded on 2026-10-03 from which unit each Banner
department's primary majors were reported under at Stage 0 (exports pulled
2026-09-07); each row's `notes` gives those shares. A department is a `split`
when two or more units each hold at least 3% of its majors and have it as
their main home.

`programs.csv` was generated on 2026-10-03 by the assistant and reconciled
against Stage 0 (`scripts/unit-mapping-baseline.R reconcile`). Proposals that
matched the unit CEDAR reported were confirmed. Decisions taken for whole
classes of disagreement, recorded in each row's `notes`:

- Where the unit came from a hand decision in `program_code_maps.R`, it was
  kept (30 programs).
- Where a code was a pre-major on only some rows, its F code decides: F and XF
  codes are pre-majors, overruling `pre_major_exempt_codes` (ISSUES I9).
- Programs whose unit was a self-named phantom, or that had none, were left
  `proposed` for someone who knows them.

## Context carried over from the original file

- `GP` is the college code for students in interdisciplinary graduate programs.
  Their courses are typically listed under their home department's college.
- Branch-campus subject codes map to the campus-level organisation.
