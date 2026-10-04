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

Admin > Data & Usage > Mappings lists every value the data uses that these files
do not cover, and every program whose mapped college differs from Banner's
Translated College, with a link to the file that fixes it.

`programs.csv` is not read by the transform until ADR-002 Stage 3; until then
`cedar_programs$dept_code` still comes from `R/lists/program_code_maps.R`.

## programs.csv

- **Only `confirmed` rows assign a unit.** A `proposed` row is the mapping
  assistant's suggestion, with the evidence it saw; it assigns nothing until
  someone changes `status` to `confirmed`. To decide one, set `unit_code`, set
  `basis` to `decided`, set `status` to `confirmed`, and say why in `notes`.
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
  college, then subject + level, then subject alone (ADR-002 Stage 3; until
  then lookups use the subject code alone).
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
Banner's. To decide a row, set `unit_code` (and `college_code` if needed), set
`status` to `confirmed`, and say why in `notes`; commit on a branch. Admin >
Data & Usage > Mappings shows the same list, each row with its `file:line`. New
codes in the data get proposed rows from `scripts/propose-mappings.R --write`.

**Row order.** `programs.csv`, `units.csv`, `colleges.csv` and
`source_departments.csv` are sorted by their first column; keep them so.
**`subjects.csv` is not, and must not be sorted yet:** until ADR-002 Stage 3,
lookups take the first row for a subject code regardless of college, so for a
subject listed under two colleges (`HLED`, `PH`, `SUST`) the order decides
which unit wins. Only confirmed rows are looked up. New rows go at the end.

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
