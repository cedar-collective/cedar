# UNM mapping files

CEDAR reads these files to decide which unit (department) every course belongs
to. Edit them here; no code changes are needed. They are validated at startup,
and a malformed file stops the app with every problem listed.
See `docs/developers/adr-002-explicit-mapping-files.md`.

| File | One row per | Columns |
|---|---|---|
| `colleges.csv` | college | `college_code`, `college_name` |
| `units.csv` | unit (department) | `unit_code`, `unit_name` |
| `subjects.csv` | course subject within a college | `subject_code`, `college_code`, `unit_code`, `notes` |

**Row order in `subjects.csv` matters.** Lookups take the first matching row.

**A subject can appear under two colleges with different units.** Branch
campuses reuse subject codes (for example `HLED`, `PH`, `SUST`) for units that
differ from the main campus's.

## Provenance

Derived from UNM's schedule key (https://xmlschedule.unm.edu/docs/schedule-key.html),
with deliberate overrides for interdisciplinary and special programs, recorded
in the `notes` column. Converted from `R/lists/subj_dept_map.R` on 2026-10-03
with no change to any mapping.

## Context carried over from the original file

- `GP` is the college code for students in interdisciplinary graduate programs.
  Their courses are typically listed under their home department's college.
- Branch-campus subject codes map to the campus-level organisation.
