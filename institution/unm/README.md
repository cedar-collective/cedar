# UNM mapping files

CEDAR reads these files to decide which unit (department) every course and
program belongs to. Edit them here; no code changes are needed. They are validated at startup,
and a malformed file stops the app with every problem listed.
See `docs/developers/adr-002-explicit-mapping-files.md`.

| File | One row per | Columns |
|---|---|---|
| `colleges.csv` | college | `college_code`, `college_name` |
| `units.csv` | unit (department) | `unit_code`, `unit_name` |
| `subjects.csv` | course subject within a college | `subject_code`, `college_code`, `unit_code`, `notes` |
| `programs.csv` | program code (optionally within a college) | `program_code`, `college_code`, `program_name`, `unit_code`, `is_pre_major`, `leads_to`, `basis`, `status`, `evidence`, `notes` |
| `source_departments.csv` | department name as Banner exports it | `source_name`, `unit_code`, `kind`, `notes` |
| `settings.csv` | institution setting | `setting`, `value` |

**Every row is one line.** No blank lines and no line breaks inside a field:
Admin > Mappings links to rows by line number, and the loader refuses a file
where row and line disagree.

`settings.csv` holds `mapping_files_url`, the GitHub location of this directory
(a `blob` URL). Admin > Data & Usage > Mappings uses it to link each program
awaiting a decision to its line here; a fork points it at its own repository.

`programs.csv` is not read by the transform until ADR-002 Stage 3; until then
`cedar_programs$dept_code` still comes from `R/lists/program_code_maps.R`.

## programs.csv

- **Only `confirmed` rows assign a unit.** A `proposed` row is the mapping
  assistant's suggestion, with the evidence it saw; it assigns nothing until
  someone changes `status` to `confirmed`. To decide one, set `unit_code`, set
  `basis` to `decided`, set `status` to `confirmed`, and say why in `notes`.
- **A blank `college_code` applies in every college.** A row with a college
  wins over it there: `CRIM` is Sociology, but `CRIM` in college `AD` (branch
  campuses) is Criminal Justice.
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

**Row order in `subjects.csv` matters.** Lookups take the first matching row.

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
