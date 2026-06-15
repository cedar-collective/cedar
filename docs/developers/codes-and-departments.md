---
title: Codes and Departments
nav_order: 9
parent: Developer Guide
---

# Codes, Programs, and Departments

Three distinct code namespaces appear across Cedar's data sources. They look similar — four-letter uppercase abbreviations — but come from different Banner systems and mean different things. Conflating them is the source of most mapping bugs.

---

## The three namespaces

### Subject codes
Used in the **DESRs** (course section reports) and in `cedar_sections`. Identify the subject area listed on a course section — the prefix in a course number like `HIST 101` or `GEOG 250`.

Examples: `HIST`, `GEOG`, `SOC`, `RLST`, `PHYC`, `ASTR`, `ENVS`

Subject codes represent how courses are *listed*, not which department *owns* them. `GEOG` sections belong to the Geography and Environmental Studies dept (`GES`). `PHYC` and `ASTR` sections both belong to Physics (`PHYS`). There is no field in the DESRs data that says which department a section belongs to — that relationship exists only in `subj_to_dept`.

### Program codes
Used in the **academic studies** report and in `cedar_programs`. Identify a specific academic program a student is enrolled in.

Examples: `HIST`, `GEOG`, `RLST`, `PSY`, `SOC`, `CRWR`, `INTS`, `JRMC`, `COM`

A program code identifies the degree or certificate a student is pursuing. Multiple program codes can belong to the same department: `CRWR`, `ENGL`, `ENGS`, `ENGP` all belong to the English department (`ENGL`); `COM`, `JRMC`, `JOUR`, `CJ` all belong to the Communication and Journalism department (`CJ`).

### Department codes
Cedar's organizational identifier for an academic department. Used in `cedar_sections$department`, `cedar_programs$dept_code`, and throughout the analysis pipeline.

Examples: `HIST`, `GES`, `PHYS`, `ENGL`, `CJ`, `PSYC`, `SOCI`

Department codes are not a raw Banner field — they are Cedar's computed grouping. Some happen to match a program code (HIST, ANTH, ECON), some don't exist as program codes at all (GES aggregates GEOG + SUST programs; no GES program exists in Banner).

---

## Where each code appears

| Source | Code type | Column(s) |
|--------|-----------|-----------|
| DESRs / `cedar_sections` | subject | `subject`, `subject_course` |
| Academic studies / `cedar_programs` | program | `program_code` |
| `cedar_programs` (computed) | department | `dept_code` |
| `cedar_sections` (computed) | department | `department` |

---

## How departments are derived

### For cedar_programs (program data)

At transform time, `transform-to-cedar.R` parses Banner `program_code` values
into `major_code`, `college_code`, and `dept_code` using the catalog files in
`R/lists/`:

```
program_code → major_code → major_college_to_dept / subj_to_dept / major_to_dept → dept_code
  BA-RLST-AS →   RLST     →                 RLST = RELG                         → RELG
  BA-JRMC-AS →   JRMC     →                 JRMC = CJ                           → CJ
  BA-CRWR-AS →   CRWR     →                 CRWR = ENGL                         → ENGL
  BA-GEOG-AS →   GEOG     →                 GEOG = GES                          → GES
```

Once cedar_programs.qs is saved, `dept_code` is on every row. No lookup is needed at runtime — the app reads it directly.

The same catalog also builds runtime lookup vectors used when the app needs the
reverse question, "which program codes belong to this department?" For example,
Dept Trends > Credit Hours uses `major_to_dept` to classify home majors versus
outside majors.

`program_map.qs` can contain Banner programs that do not have a defensible
academic-department owner yet, such as broad branch-campus associate programs or
undecided programs. Runtime lookup vectors exclude invalid or unmapped rows and
collect them in `cedar_mapping_issues`, which is surfaced under Admin > Data &
Usage > Mappings. Reviewed exceptions live in `allowed_unmapped_program_codes`
in `R/lists/program_code_maps.R`. Regenerating `program_map.qs` should still
fail loudly on new unmapped codes until they are mapped or reviewed. The goal is
to prevent unknown programs from silently becoming `NA` entries in department
lookups while keeping the Shiny app available.

### For cedar_sections (course data)

DESRs have no department field. The subject code is the only organizational identifier on a course section. At transform time, `subj_to_dept` translates:

```
subject → subj_to_dept → department
  GEOG  →   GEOG = GES    →    GES
  RLST  →   RLST = RELG   →   RELG (courses use RLST; students use RLST program)
  PHYC  →   PHYC = PHYS   →   PHYS
  SOC   →   SOC  = SOCI   →   SOCI
```

This is the **one lookup table that cannot be derived from the data.** There is no field in DESRs or any other source that records which department owns a course section. `subj_to_dept` encodes institutional knowledge that exists only in this file.

---

## Department display names

Given `dept_code`, the display name (e.g., "Geography and Environmental Studies" for `GES`) is derived at transform time and stored in `cedar_lookups$dept_name_lookup`.

**The derivation rule:** for each `dept_code`, find the program in `cedar_programs` where `program_code == dept_code`. That program's `program_name` is the canonical department name.

This works for most departments:

```
HIST → program HIST → "History"
ANTH → program ANTH → "Anthropology"
ENGL → program ENGL → "English"
```

It breaks for five departments where no program code equals the dept code:

| dept_code | reason | override needed |
|-----------|--------|-----------------|
| `GES` | aggregates GEOG + SUST; no GES program exists | `"Geography and Environmental Studies"` |
| `ISI` | students use program code INTS, not ISI | `"International Studies"` |
| `PSYC` | students use program code PSY, not PSYC | `"Psychology"` |
| `RELG` | students use program code RLST, not RELG | `"Religious Studies"` |
| `SOCI` | students use program code SOC, not SOCI | `"Sociology"` |

These five, plus six optional editorial refinements (e.g., "Physics and Astronomy" instead of "Physics"), are maintained in `dept_display_names` in `R/lists/mappings.R`.

---

## What lives where

### `R/lists/program_code_maps.R`

| Map | Purpose | When used |
|-----|---------|-----------|
| `premaj_canon` | F-prefix pre-major code → target major code | program map generation |
| `xvar_explicit` | X-prefix variant code → canonical major code | program map generation |
| `extra_p2d` | program/major code → dept_code overrides | program map generation |
| `ad_major_to_dept` | branch-campus program overrides | program map generation |
| `allowed_unmapped_program_codes` | reviewed programs with no dept owner | labels reviewed exceptions; excluded from dept lookup vectors |

### `R/lists/catalog_lookups.R`

| Lookup | Purpose | When used |
|--------|---------|-----------|
| `subj_to_dept` | subject code → dept_code | transform time and runtime helpers |
| `major_college_to_dept` | `major_code:college_code` → dept_code | transform time; most precise program lookup |
| `major_to_dept` | major_code → dept_code | transform time fallback; runtime reverse lookup |
| `dept_code_to_name` | dept_code → dept_name | display |

### `R/lists/mappings.R`

| Map | Purpose | When used |
|-----|---------|-----------|
| `hr_org_desc_to_dept` | HR org description → dept_code | faculty data |
| `program_code_to_name` | program_code → display name | student composition charts |

### `data/cedar_lookups.qs` (built at transform time)

| Lookup | Content | Used by |
|--------|---------|---------|
| `dept_name_lookup` | dept_code → dept_name (31 rows) | department dropdown in UI |
| `dept_lookup` | HR/legacy string → dept_code | historical compatibility |
| `program_name_lookup` | program_name string → dept_code | legacy report ingestion |

### Runtime (Shiny app)

The app usually reads `cedar_programs$dept_code` directly from the .qs file. A
small number of runtime views also load catalog lookup vectors for reverse
questions, such as identifying all home-major codes for a department. These
runtime vectors are validated at load time; invalid and unmapped rows are
excluded from lookup vectors and surfaced as mapping issues in the Admin page.

---

## Could we simplify further?

Short answer: yes, the current system is close to minimal — one more step is possible.

**What's already data-driven:**
- `dept_code` on `cedar_programs` rows — stored in the .qs, no runtime lookup
- Department display names — derived from `program_name` where `program_code == dept_code`, stored in `cedar_lookups.qs`
- Which departments appear in the dropdown — derived from unique `dept_code` values in `cedar_programs`

**What still requires hand-maintained review:**
- `subj_to_dept` — irreducible, no data source provides this
- `extra_p2d` / `ad_major_to_dept` — program codes whose ownership cannot be inferred from subject codes alone
- `allowed_unmapped_program_codes` — codes intentionally excluded from department ownership until reviewed or mapped
- `dept_display_names` — could be reduced to the 5 required entries (removing editorial refinements like "Physics and Astronomy")

**The irreducible minimum:** `subj_to_dept`. This is the only map that encodes information genuinely absent from all data sources. Everything else is either derived at transform time and stored in the .qs files, or could be.
