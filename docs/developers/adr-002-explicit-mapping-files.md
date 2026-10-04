# ADR-002: Explicit mapping files replace runtime department inference

- **Status:** Proposed
- **Date:** 2026-10-03
- **Supersedes:** the code-parsing department chain (`generate_program_map()`,
  `program_map.qs`, and the overrides in `R/lists/program_code_maps.R`), and the
  program-to-department review list as the way to fix mappings.
- **Complements:** [ADR-001](adr-001-domain-data-model.md), whose unit dimension
  this defines; [institution-boundary-audit.md](institution-boundary-audit.md),
  which found ten of twelve `R/lists/` files are institution configuration.
- **Resolves when done:** ISSUES I7 (phantom departments), I9 (pre-major lists
  disagree), I11 (concentrations mapped by name), and the ROADMAP item
  "Externalize department/program/subject mappings to YAML or CSV data files".

---

## Context

Every CEDAR department report rests on one question: **which unit does this
course, program, or student belong to?** CEDAR answers it at transform time, by
inference:

- A program's department is rebuilt from its code through five tiers:
  `major_college_to_dept`, `subj_to_dept`, `major_to_dept` (derived from a
  generated `program_map.qs`), `extra_p2d`, and finally the program code itself.
- A course's department is its subject code looked up in `subj_dept_map`,
  falling back to the subject code itself.
- Thirteen lists feed this, totalling about 1,060 lines, plus a 180-line
  generator that parses Banner program codes into degree, major and college.

The October 2026 pipeline audit measured what that costs:

| Failure | Measured |
|---|---|
| Programs reported under a department named after their own code | 77 codes |
| Courses reported under a department named after their subject | 21 subjects, 10,221 enrollments |
| Overrides written down but silently ignored | `FPMD="PHRM"` and three more, until #106 |
| Concentrations with no department, or the wrong one by name | 23,304 rows since Fall 2024; Public Policy counted under PADM for Political Science students |
| Programs mapped to the wrong department | East Asian Studies, Comparative Literature (#100) |

Each was found one at a time, after someone noticed a number was wrong. The
inference is invisible: a wrong answer looks exactly like a right one.

Meanwhile Banner already records the owning department. `Department` is native
to the Academic Studies, degrees and class-list exports, 99.9% filled, and was
identical on all 12,786 rows re-pulled a median 153 days apart. It names the
right owner for every major fixed by hand this year: East Asian Studies,
Comparative Literature, Doctor of Pharmacy, Radiologic Sciences and Health
Administration. CEDAR read it until
March 2026 and replaced it with code parsing because the name-to-code crosswalk
covered only 29% of rows.

Two facts shape the replacement:

1. **Native fields are good evidence but not a contract.** Banner's department
   is too coarse in places (one "Provost Branch Campuses" for 38 programs),
   is a bucket rather than an owner in others (`*Interdisciplinary: A.S.` holds
   Museum Studies, Biochemistry and the MPP), and covers only the primary
   major.
2. **CEDAR has to run outside UNM.** Another institution has different programs,
   departments, export columns, and its own messy data. Logic tied to UNM's
   MyReports fields cannot be adopted; a reviewed text file can.

## Decision

**The pipeline reads explicit mapping files and nothing else to assign units.
Native fields and data patterns are used only to *propose* rows for those files,
by a separate script, for a person to confirm.**

Three roles, kept apart:

| Role | Who | Reads | Writes |
|---|---|---|---|
| Evidence | Source exports | | Native fields such as Banner `Department` |
| Proposal | `scripts/propose-mappings.R` | Exports + existing mapping files | New rows marked `proposed`, with their evidence |
| Contract | Transform | Mapping files only | Units on every CEDAR table |

The transform never parses a code, never falls back to a self-named unit, and
never reads a source department field to decide anything.

## The mapping files

One directory per institution, `institution/<id>/`, chosen in `config.R` by
`cedar_institution`. UNM is `institution/unm/`; the synthetic demo gets
`institution/demo/`. Plain CSV, UTF-8, one row per key, so every change is a
one-line diff.

### `units.csv`: what a department report is about

| Column | Meaning |
|---|---|
| `unit_code` | Short stable code, e.g. `HIST`, `THDA`, `MSST` |
| `unit_name` | Display name |
| `college_code` | Owning college (`colleges.csv`) |
| `kind` | `department`, `program` (a standalone interdisciplinary unit), or `school` |
| `status` | `active` or `retired`; retired units keep their history |

### `subjects.csv`: course subject to unit

`subject_code`, `unit_code`, `notes`. Replaces the subject half of
`subj_dept_map`.

### `programs.csv`: program code to unit

| Column | Meaning |
|---|---|
| `program_code` | The major, minor or second-major code as it appears in the data |
| `program_name` | Display name |
| `unit_code` | Owning unit |
| `is_pre_major` | `TRUE` / `FALSE`, stated rather than inferred |
| `leads_to` | For a pre-major, the program code it leads to (replaces `premaj_canon`) |
| `basis` | Why this unit: `source_department`, `inherited`, `decided`, `override` |
| `status` | `confirmed` or `proposed` |
| `evidence` | What the assistant saw, e.g. `Banner Department "Radiology" on 236 rows` |
| `notes` | Free text, e.g. the date and who decided |

### `colleges.csv`

`college_code`, `college_name`, `source_names` (every spelling the exports use,
`|`-separated, replacing `college_name_to_code`).

### `source_departments.csv`: evidence aid, not read by the transform

`source_name`, `source_code`, `unit_code`, `kind` (`department`, `bucket`,
`non_degree`). Records what each source-system department means, so the
assistant can propose program rows from it. A `bucket` row has no unit: every
program in it needs its own row in `programs.csv`.

### Rules that need no file

- **Concentrations take the unit of the student's primary major.** Measured on
  every concentration in the Academic Studies file: none fit only a second
  major. Should an institution need exceptions, an optional `concentrations.csv`
  can be added later.
- **Second majors and minors** use their own code's row in `programs.csv`, never
  the student's primary-major department.

### Validation

`validate_mapping_files()` runs at startup and in the test suite, and stops with
every problem listed: missing columns, duplicate keys, a `unit_code` absent from
`units.csv`, a `leads_to` that is not a program, an unknown `basis` or `status`.
Invalid files are an error, never a warning.

## The pipeline contract

- Every subject and program code in the data is looked up in its file. There is
  one tier.
- A code with no row gets **no unit** (`NA`). It is listed on Admin > Data &
  Usage > Mappings and in the refresh report. It is never given a self-named
  unit, and it never blocks the refresh, which the whole app depends on.
- Only `confirmed` rows assign units. `proposed` rows are visible on the Admin
  page but assign nothing until someone confirms them.
- The unit a row resolved through is kept, so any number can be traced to the
  line in the file that produced it.

## The mapping assistant

`scripts/propose-mappings.R --institution <id> [--write]`

1. Reads the parsed exports and collects every distinct subject code, program
   code (primary, second major, minors), and source department name.
2. For each code with no row, proposes a unit, strongest evidence first:
   - the source department, through `source_departments.csv` (primary majors);
   - inheritance: a minor or second-major code that is someone's primary major
     takes that program's unit;
   - for a pre-major, the unit of the program it leads to;
   - a name match against `units.csv`;
   - course-taking: which unit's courses the program's students take most.
3. Writes the evidence beside each proposal and marks it `proposed`.
4. **Never edits a `confirmed` row.** Dry run by default; `--write` appends.
5. Prints a short review list: new codes, proposals, and codes it could not
   propose for.

Run it at setup, and whenever the Admin page shows unmapped codes. The daily
refresh may run it in dry-run mode so new codes appear on the Admin page the
day they arrive.

For UNM its first run reproduces most of today's departments from Banner's
`Department`, leaving the cases Banner cannot settle, already drafted in
`docs/developers/drafts/unit-decisions-draft.csv` (branch `drafts/unit-decisions`):
20 programs in interdisciplinary buckets, 38 branch-campus programs, and 44
codes that only ever appear as minors or second majors.

## Migration for UNM

Staged, each stage compared against the previous output before it ships.

| Stage | Work | Accepted when |
|---|---|---|
| 0 | Snapshot today's unit for every program and subject, by term | Baseline saved |
| 1 | Write `institution/unm/units.csv`, `subjects.csv`, `colleges.csv` from `subj_dept_map` and `mappings.R`; add the validator and its tests | Files reproduce `subj_dept_map` exactly; no behaviour change |
| 2 | Build the assistant; generate `programs.csv` and `source_departments.csv` | Every disagreement with Stage 0 listed; each one confirmed or decided |
| 3 | Transform reads the files; both self-naming fallbacks removed | Differences from Stage 0 are exactly the decided ones |
| 4 | Retire `generate_program_map()`, `program_map.qs`, and the lists it fed | Tests pass with the lists gone |
| 5 | Give the synthetic demo its own `institution/demo/` files | Demo runs with no UNM file loaded |

Stage 5 is the adopter test: if the demo institution works from its own files
alone, so can a real one.

## What this retires

`generate_program_map()` and `program_map.qs`; `xvar_explicit`,
`known_suffixes`, `ad_major_to_dept`, `allowed_unmapped_program_codes`,
`real_F_progs`, `pre_major_exempt_codes`; most of `extra_p2d`; the department
half of `catalog_lookups.R`; the program-name department lookup used by
headcount; and the identity fallbacks in `transform_programs()` and the course
transforms. `subj_dept_map.R`, `mappings.R` and `premaj_canon` move into the
CSV files rather than disappearing.

## Consequences

**Gains.** A wrong unit is a visible line in a file, not an emergent result of
five tiers. Adopting CEDAR means writing files, helped by the assistant, not
changing code. Every mapping change is reviewable in a diff. Unmapped codes are
seen the day they appear.

**Costs, stated honestly.**

- Someone must own the files. New programs arrive every term, and a proposed
  row assigns nothing until it is confirmed.
- The first UNM `programs.csv` needs a review pass, mostly the 102 drafted rows.
- Until Stage 3 ships, two systems exist side by side.

## Open questions

1. **What a unit is.** Recommendation: the source organisation by default
   (Theatre & Dance is one unit, with each major broken out inside its report),
   with explicit splits only where a subject area is reported on separately.
   Needs a decision before Stage 2.
2. **Branch campuses.** One Banner department covers 38 programs; each needs a
   unit decision, or a rule such as "branch programs report to their campus".
3. **Bucket programs.** Whether each interdisciplinary program (Museum Studies,
   Latin American Studies, International Studies) is its own unit or belongs to
   a home department, as MPP belongs to PADM.
4. **Concentration rule.** Inferred from the data, not confirmed against
   Banner's own concentration-to-major link, which the export flattens away.
5. **CSV or YAML.** CSV is proposed for diffability and spreadsheet editing.

## Out of scope

- **Input adapters.** Mapping files solve "my programs and departments are
  different", not "my exports have different columns". A defined input format
  with a small adapter per source is separate work.
- **Faculty data** (stops at Spring 2025; audit finding 3) and the HR merge.
- **ADR-001's** move to domain-shaped tables. This ADR defines the unit
  dimension that move will need.
