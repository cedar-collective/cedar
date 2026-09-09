---
title: Mapping pipeline audit — platform vs institution
---

# Mapping pipeline audit: what is CEDAR, and what is UNM

Audited 2026-09-09, after ISSUES.md I7 showed a mapping defect hiding 85% of a
program's students. The question this answers: **is UNM-specific configuration
cleanly separable from CEDAR as a platform?**

Short answer: mostly, by accident rather than by design. The boundary is real in
practice but declared nowhere, one institution-specific list is hardcoded inside
platform code, and the duplicate copies of it have drifted apart.

## The pipeline

```
academic_studies.qs  (institutional export)
        │
        ▼
generate_program_map()            transform-to-cedar.R   ← platform mechanism
  uses: subj_dept_map, premaj_canon, xvar_explicit,      ← institution data
        extra_p2d, known_suffixes, real_F_progs,
        ad_major_to_dept, allowed_unmapped_program_codes
        │
        ▼
program_map.qs  →  catalog_lookups.R  →  major_college_to_dept  ┐
                                          subj_to_dept          ├─ 4-tier
                                          major_to_dept         ┘  dept_code chain
        │
        ▼
cedar_programs$dept_code           transform_programs()   ← platform mechanism
                                     + inline F-code list ← INSTITUTION DATA (defect)
```

## Classification of `R/lists/`

Measured by institution-shaped content, not by intent:

| File | Lines | Kind |
|---|---:|---|
| `grades.R` | 41 | **Platform** — grade vocabulary and the DFW policy |
| `status_codes.R` | 32 | **Platform** — Banner registration status codes |
| `catalog_lookups.R` | 244 | **Mixed** — derivation mechanism with institution rules embedded |
| `data_semantics.R` | 155 | **Mixed** — registry mechanism plus UNM entries |
| `subj_dept_map.R` | 294 | Institution — subject → department |
| `program_code_maps.R` | 223 | Institution — Banner code conventions |
| `mappings.R` | 218 | Institution — name → code, HR org → dept |
| `excluded_courses.R` | 226 | Institution |
| `gen_ed_courses.R` | 151 | Institution |
| `population-presets.R` | 174 | Institution — named program groups |
| `enrollment_projection_groups.R` | 133 | Institution — monitored courses |
| `campuses.R` | 101 | Institution |

Ten of twelve files are institution configuration. Nothing says so. `AGENTS.md`
describes the directory as "static constants, domain lookups", and
`first-hour.md` covers the synthetic demo rather than adoption, so an adopter has
no list of what to replace.

## Findings

### 1. Institution data hardcoded in platform code — and divergent

`transform-to-cedar.R` carries a sixteen-code UNM F-prefix exclusion list inline
while `generate_program_map()` uses `real_F_progs` from
`R/lists/program_code_maps.R`. Both answer the same question — *which F-prefixed
Banner codes are real programs rather than pre-majors* — and they disagree:

| | codes |
|---|---|
| In both | `FDMA`, `FS` |
| Map says real program, transform says pre-major | `FREN`, `FCS`, `FRST`, `FCST` |
| Transform says real program, map says pre-major | `FA`, `FLA`, `FILM`, `FFDA`, `FFDM`, `FMAR`, `FIDA`, `FLHC`, `FLPR`, `FLAI`, `FES`, `FPE`, `FAT`, `FNE` |

**23,272 student-term rows carry a code the two lists disagree about.** This is
how `FCS` came to be flagged a pre-major while being denied a pre-major's
canonical mapping — the mechanism behind part of I7.

### 2. `is_pre_major` disagrees with itself

The flag is set by two independent signals — a `^Pre[- ]` program-name prefix and
the F-code convention — which do not agree per row:

| Code | `is_pre_major = TRUE` | `FALSE` |
|---|---:|---:|
| `FES` Exercise Science | 4,015 | 1,040 |
| `FFDA` | 3,423 | 987 |

The same Banner code is a pre-major in some terms and a declared major in
others, decided by how the program name happened to be spelled.

### 3. A semantic break coded as a special case

```r
# PHRD used for UG pre-pharmacy students before 202580 (switched to FPHS)
(major_code == "PHRD" & student_level %in% c("UG", "NG"))
```

A code whose meaning changed at a known term is exactly a `CEDAR_DATA_SEMANTICS`
entry. Here it is an inline condition in the transform, invisible to every
consumer and to the reader of any number it affects.

### 4. Branch-campus knowledge hardcoded

`branch_campus_suffixes <- c("GA", "LA", "TA", "VA")` and
`progs$col[branch_mask] <- "AD"` are UNM's campus and college codes written into
the transform. An adopter with different branch codes must edit platform code.

### 5. Cosmetic: examples are UNM-flavoured

Roxygen blocks across branches, cones and features illustrate with `"AS"`,
`"HIST"`, `"MATH"`. Harmless — no executable path depends on them — but it
reinforces the impression that the platform assumes one institution.

## What the boundary should be

Two categories, declared:

- **Platform** — mechanism, vocabulary, and policy that any adopter inherits:
  the dept_code tier chain, the anomaly screens, the registry accessors, grade
  and status vocabulary, the DFW policy.
- **Institution** — every code, name, course, campus, college and program list
  that describes one university.

The rule that follows: **platform code may read institution data through a named
constant, and may never contain one.** Finding 1 is the only executable
violation; findings 3 and 4 are the same violation in weaker form.

## Recommended sequence

1. **Unify the two F-code lists** into one institution constant, and decide which
   membership is correct. This changes `is_pre_major` for real students, so it
   needs a decision and a measured before/after, not a quiet edit.
2. **Move findings 3 and 4** into institution constants — the PHRD term rule into
   `CEDAR_DATA_SEMANTICS`, the branch suffixes and branch college into
   `R/lists/campuses.R`.
3. **Declare the boundary**: a header convention in each `R/lists/` file stating
   Platform or Institution, this table in `AGENTS.md`, and an adoption section in
   `first-hour.md` naming the ten files to replace.
4. **Enforce it** with an architecture test that fails when a campus, college,
   department or course literal appears in executable code outside the
   institution files — the same shape as the existing `CAMPUS_ROLLUP` test.

Step 4 is what keeps this from re-eroding. Steps 1 and 2 are defects; step 3 is
documentation; only step 4 makes the boundary hold.

## What is already clean

The four-tier `dept_code` chain, `generate_program_map()`, `catalog_lookups.R`'s
derivations, the anomaly screens, and the semantics registry are all mechanism
that takes institution data as input. `mappings.R` explicitly records which
lookups were superseded and warns against re-adding them. The separation was
being maintained by care; it now needs to be maintained by structure.
