# ADR-002: Explicit mapping files replace runtime department inference

- **Status:** Accepted 2026-10-03. Decided: a unit is the source system's
  organisation (Banner's department) by default, keeping CEDAR's existing
  splits of a Banner department as recorded splits. Stages 0, 1 and 2 are done.
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

One directory per institution, `institution/<id>/`, chosen by the
`CEDAR_INSTITUTION` environment variable (default `unm`). Not a `config.R`
setting, because `config.R` is not committed and CI, the demo stack and the
transform run without one. UNM is `institution/unm/`; the synthetic demo gets
`institution/demo/`. Plain CSV, UTF-8, one row per key, so every change is a
one-line diff.

### `units.csv`: what a department report is about

| Column | Meaning |
|---|---|
| `unit_code` | Short stable code, e.g. `HIST`, `THDA`, `MSST` |
| `unit_name` | Display name |
| `college_code` | The unit's home college (decided 2026-10-04; see "Colleges are mapped, not read") |
| `kind` (deferred) | `department`, `program` (a standalone interdisciplinary unit), or `school` |
| `status` (deferred) | `active` or `retired`; retired units keep their history |

`kind` and `status` were planned for Stage 2 and deferred: nothing reads them
yet, and guessing 164 values nobody consumes would be noise. Add them with
their first reader.

The first draft gave units no college, because 11 units appear under two
colleges in `subjects.csv` (PADM under Arts & Sciences and the Provost, for
example). That is superseded: each unit has one home college, and the 11 are
decided once. See below.

### `subjects.csv`: course subject to unit

`subject_code`, `college_code`, `unit_code`, `notes`. **Keyed by subject and
college**, not subject alone: branch campuses reuse subject codes (`HLED`,
`PH`, `SUST`) for units that differ from the main campus's. Row order matters,
because lookups take the first match. Replaces `subj_dept_map.R`.

### `programs.csv`: program code to unit

| Column | Meaning |
|---|---|
| `program_code` | The major, minor or second-major code as it appears in the data |
| `college_code` | Blank for every college, or a college where this code has a different unit. A college row wins there. Only two UNM codes need one (`BADM`, `CRIM` at the branches) |
| `program_name` | Display name |
| `unit_code` | Owning unit |
| `is_pre_major` | `TRUE` / `FALSE`, stated rather than inferred |
| `leads_to` | For a pre-major, the program code it leads to (replaces `premaj_canon`) |
| `basis` | Why this unit: `source_department`, `subject_code`, `inherited`, `name_match`, `course_taking`, `decided`, `override`, `no_unit` (nothing owns it), `unresolved` (no evidence; always proposed) |
| `status` | `confirmed` or `proposed` |
| `evidence` | What the assistant saw, e.g. `Banner Department "Radiology" on 236 rows` |
| `notes` | Free text, e.g. the date and who decided |

### `colleges.csv`

`college_code`, `college_name`, `source_names` (every spelling the exports use,
`|`-separated, replacing `college_name_to_code`).

### `source_departments.csv`: evidence aid, not read by the transform

`source_name`, `unit_code`, `kind`, `notes`. Records what each source-system
department means, so the assistant can propose program rows from it. `kind` is
`department` (one unit), `split` (several units, `|`-separated; the assistant
places each program among them), `bucket` (no unit: every program in it needs
its own evidence) or `non_degree` (its programs belong to no unit). The
`source_code` column first proposed was dropped: UNM's exports carry only names.
Every spelling needs a row, because Banner renames departments.

### `settings.csv`

`setting`, `value`. Holds `mapping_files_url`, the GitHub location of the
institution's directory, so Admin > Mappings can link each proposed program row
to its line. Mapping decisions are edits to these files in the repository, never
in the app: the running container's copy is replaced by the next deploy.

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

## Colleges are mapped, not read (decided 2026-10-04)

The mapping files state how the institution is organised, so that no reported
relationship depends on which fields an export happens to carry. That covers
colleges as much as units:

- **A program's college is its unit's college**: program → unit (`programs.csv`)
  → college (`units.csv`). An optional per-program college, for a program that
  sits in a different college from its owning unit, overrides it.
- **Reports use the mapped college.** The college the source recorded on each
  row is kept beside it as `source_college`, for audit only, and the mapping
  audit lists every row where the two disagree. That is how a rename is seen:
  UNM's College of Education appears as `ED` and "College of Education" before
  2021 and as `EH` and "College of Educ & Human Sci" after (ISSUES I12).
- **History is restated to today's organisation**, as it already is for units:
  a program that moved colleges reports under its current college in every
  year. `source_college` keeps the as-recorded view.
- **Every spelling and former code a source uses for a college** is listed in
  `colleges.csv` (`source_names`), so source values are translated explicitly
  and an unknown one is listed, never silently dropped.
- **One source college stays an input:** a course section's own college (the
  DESR `COLLEGE`), because `subjects.csv` keys on it to tell a branch campus's
  `HLED` from the main campus's. It chooses the unit; it is not reported as
  the course's college.

Two changes follow in the files. `units.csv` gains `college_code`, and the
assistant proposes each unit's from the data for review. In `programs.csv`, the
column that today means "this row applies only in that college" is renamed
`in_college`, so that no column called `college_code` means two different things.

Why not read the college from each row, as CEDAR did: it is implicit (nobody can
point to where "Nursing is in the College of Nursing" is stated), it inherits
every source quirk (a rename splits one college's history in two), and an
institution whose exports carry no college gets nothing. Reading per row is
right for events -- what a student declared, which course they took -- and
those stay in the data.

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
| 0 | Snapshot today's unit for every program and subject (`scripts/unit-mapping-baseline.R snapshot`; `compare` diffs any later build against it) | **Done.** 741 program groups, 263 course groups |
| 1 | Write `institution/unm/units.csv`, `subjects.csv`, `colleges.csv` from `subj_dept_map.R`; add the reader, validator and tests | **Done.** Built table identical to the old one; rebuilt sections, students and programs differ from the baseline in 0 groups |
| 2 | Build the assistant; generate `programs.csv` and `source_departments.csv` | **Done.** See Stage 2 results |
| 3 | Transform reads the files; both self-naming fallbacks removed | Differences from Stage 0 are exactly the decided ones |
| 4 | Retire `generate_program_map()`, `program_map.qs`, and the lists it fed | Tests pass with the lists gone |
| 5 | Give the synthetic demo its own `institution/demo/` files | Demo runs with no UNM file loaded |

### Stage 2 results (2026-10-03)

`scripts/propose-mappings.R` proposed a row for each of 420 program codes in
the exports. `scripts/unit-mapping-baseline.R reconcile` then compared each
proposal with the unit CEDAR reported at Stage 0:

| Outcome | Codes |
|---|---|
| Assistant agreed with Stage 0 independently; confirmed | 307 |
| Branch-campus college rows (`BADM`, `CRIM` in `AD`), beside their codes; confirmed | (2 rows) |
| Stage 0 unit was a hand decision the assistant disagreed with; kept (decided by class) | 30 |
| Non-Degree, Undecided: `no_unit` (decided in `department_less_major_codes`) | 2 |
| Self-named phantom unit, or none, at Stage 0; left `proposed` (decided) | 79 |
| Stage 0 unit derived by code parsing, assistant disagrees; left `proposed` | 2 |

Pre-majors: where a code's rows all agreed at Stage 0, the flag was carried
over. 16 codes were pre-majors on only some rows; the decision was that the F
code decides (F and XF are pre-majors), overruling `pre_major_exempt_codes`
for FES, FPE, FNE, FFDA and FLAI (ISSUES I9).

`unit-mapping-baseline.R files` previews Stage 3 against the baseline: **no
confirmed program changes unit.** What changes is exactly what was decided:
concentrations take their primary major's unit (83,138 rows, 82,024 of which
had none), Non-Degree and Undecided lose their phantom units (25,523), and the
81 proposed programs report under no unit until confirmed (11,618).

Two lessons recorded so they are not relearned:

- **Read the exports the transform reads.** The first run used the repository's
  `data/academic_studies.qs`, a June copy, and missed 12 codes including FRAD
  (I7's Radiologic Sciences) plus two renamed Banner departments.
- **Compare row by row.** A first reconcile tested each proposal against the
  whole column of Stage 0 units, confirming 65 wrong rows (FBAD as ACCT among
  them). The Stage 3 preview caught it: a confirmed row should never move.

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

1. ~~What a unit is.~~ **Decided 2026-10-03:** the source organisation by
   default (Theatre & Dance is one unit, with each major broken out inside its
   report), with explicit splits only where a subject area is reported on
   separately.
2. **Branch campuses.** One Banner department covers 38 programs; each needs a
   unit decision, or a rule such as "branch programs report to their campus".
3. **Bucket programs.** Whether each interdisciplinary program (Museum Studies,
   Latin American Studies, International Studies) is its own unit or belongs to
   a home department, as MPP belongs to PADM.
4. **Concentration rule.** Inferred from the data, not confirmed against
   Banner's own concentration-to-major link, which the export flattens away.
5. **CSV or YAML.** CSV is proposed for diffability and spreadsheet editing.
6. **The 81 proposed programs.** Mostly branch-campus certificates and
   minor-only codes. Many carry a sensible proposal (Art → ARTS, Liberal Arts
   → LAIS, Military Studies → NVSC); each needs someone who knows the program.
   From Stage 3 they appear under no unit, on Admin > Mappings, until confirmed.
7. **Hand decisions Banner disagrees with.** Kept at Stage 2, but Banner names
   a different owner for ABA and ASD (Special Education, CEDAR says PSYC), CTS
   (Biomedical Sciences, CEDAR says CHEM), ELNG (LLSS, CEDAR says LING) and
   CHBI (Chemistry, CEDAR says BIOL). Worth confirming with IR.
8. **Accelerated online (X-prefix) programs.** X marks an accelerated online
   program. CEDAR maps each to its base program's unit and has never defined
   whether they should be reported apart.

## Out of scope

- **Input adapters.** Mapping files solve "my programs and departments are
  different", not "my exports have different columns". A defined input format
  with a small adapter per source is separate work.
- **Faculty data** (stops at Spring 2025; audit finding 3) and the HR merge.
- **ADR-001's** move to domain-shaped tables. This ADR defines the unit
  dimension that move will need.
