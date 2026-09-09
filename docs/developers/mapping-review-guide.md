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

**Admin > Data & Usage > Mappings** is the shortest path. It lists every mapping
problem CEDAR can detect about itself, in three kinds:

| `issue_type` | What it means | What to do |
|---|---|---|
| `unmapped_program_code` | A program with no department owner, already reviewed | Nothing, unless the program has since acquired an owner |
| `pre_major_self_mapped_department` | A pre-major whose department is its own code — always a mapping failure | Add it to `premaj_canon` |
| `identity_fallback_department` | A declared program whose department does not exist | Map it in `extra_p2d`, or add to `department_less_major_codes` if nothing owns it |
| `declared_majors_far_exceed_graduates` | A program carrying far more majors than it graduates | Investigate; often means the code records intent, not admission |

Everything below is how to reach the same conclusions by reading files.

## The files, and what to look at in each

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

### `subj_dept_map.R` — subject → department → college

The authoritative department list. If a department is missing here, every code
that should map to it falls through.
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

## When you change a mapping

A list edit alone changes nothing. The map must be regenerated and
`cedar_programs` rebuilt — and there are three traps in doing that, all
documented in [data-anomalies.md](data-anomalies.md#regenerating-program_mapqs).
The short version: generate from the **shared** data directory, `rm(program_map)`
before rebuilding, and never move the map aside to force a regenerate.

Afterwards, verify by counting students per department for a program you expect
to change, and re-run the screens: the flagged counts should fall by exactly what
you mapped, and nothing else should move.
