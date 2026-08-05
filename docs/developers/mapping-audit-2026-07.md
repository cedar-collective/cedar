# Mapping and Schema Audit — 2026-07-31

Every claim here was verified against the live tables in `data/` (241,941 sections;
1,687,084 class-list rows; 464,011 program rows; 63,284 degrees; 37,675 faculty
rows), not read off the source. Re-run the checks in
`scripts/audit-mappings.R` after any transform change.

**Bottom line:** nothing here is producing a wrong number on screen today. Every
user-facing filter path happens to stay inside one vocabulary. But the schema
does not *enforce* that — it relies on convention — and three of the traps are
one small feature away from firing silently. That is the gap to close before
CEDAR ingests a second institution's data.

---

## 1. The core problem: one concept, two vocabularies, same column name

`cedar_*` tables carry the same real-world concept under the same column name in
two different vocabularies. Nothing in the schema declares which is which.

| concept | CODE vocabulary | NAME vocabulary |
|---|---|---|
| campus | `sections$campus`, `students$campus`, `students$student_campus` | `programs$student_campus`, `degrees$campus` |
| college | `sections$college`, `students$college`, `students$student_college`, `programs$college_code` | `programs$student_college`, `degrees$college`, `degrees$student_college` |

Measured overlap between the two sides is **0%** — they are disjoint sets, so a
join or filter across them returns zero rows rather than an error:

```
campus   sections vs programs     0 / 19  (0%)   DISJOINT
campus   students vs degrees      0 / 15  (0%)   DISJOINT
college  sections vs degrees      0 / 33  (0%)   DISJOINT
```

The sharpest case: **`student_campus` is codes in `cedar_students` and labels in
`cedar_programs`.** Same name, same concept, incompatible values.
`student_college` has the identical split.

### Why nothing is broken yet

Every student-side filter (`population.R`, `headcount.R`, `major-changes.R`,
`course-impact.R`, Pathways) operates on `cedar_programs`, and both UI
choice-builders read their options from `cedar_programs`. Label-on-label,
self-consistent. Course-side filters operate on `sections`/`students`.
Code-on-code, self-consistent. The two sides never meet.

### Why it is still a live trap

`opt_col_map_classlist` in `R/trunk/filter.R` maps `opt$student_campus` and
`opt$student_college` onto the **code** columns in `cedar_students`, while every
UI in the app produces **labels**. `R/features/regstats.R` already lists both in
its `student_level_filters`. The first person to expose either filter passes
`"Albuquerque/Main"` into a column of `ABQ` and gets an empty result with no
error. This already happened once in miniature: Pathways shipped with
`selected = "ABQ"` against the label column, so its campus filter silently
selected nothing and every population quietly included all five campuses.

Also note `cedar_students$student_campus` and `student_college` (the code
columns) **are read nowhere in the app**. They exist only to be mistaken for
their `cedar_programs` namesakes.

### The mapping is derivable, not guesswork

Joining `cedar_students` to `cedar_programs` on `student_id + term` yields a
clean 1:1 with zero ambiguity. Confirmed independently on two snapshots — the
local `data/` set (82,332 matched student-terms, shown below) and the deployed
container's larger set (364,110) — with identical pairings:

| label | code | n (local) |
|---|---|---|
| Albuquerque/Main | ABQ | 82,021 |
| Valencia | VA | 178 |
| Gallup | GA | 54 |
| Los Alamos | LA | 54 |
| Taos | TA | 25 |

`transform_degrees()` already computes `.college_code` via
`college_name_to_code[student_college]` and then **discards it**
(`select(-.college_code)`), which is why `cedar_degrees$college` ships as a name
that cannot join to anything.

The 14 codes in `sections$campus` (EA, EF, TAP, `05`…) are course *delivery*
locations with no student equivalent. The two domains legitimately differ; only
the 5 student campuses need bridging.

---

## 2. Declared lookups vs observed data

| lookup | declared | in data | coverage | orphans |
|---|---|---|---|---|
| `subj_to_dept` | 215 | 228 | **89%** | 12 |
| `major_to_dept` | 302 | 406 | **74%** | 0 |
| `dept_code_to_name` | 163 | 259 | **61%** | 4 |
| `college_name_to_code` | 17 | 16 | 94% | 2 |
| `hr_org_desc_to_dept` | 79 | 41 | 100% | **38** |
| `major_name_to_major_code` | 93 | 515 | 15% * |
17 |

\* `major_name_to_major_code` is an alias list, not an exhaustive map — 15% is
expected. The others are meant to be complete.

**`dept_code_to_name` at 61% is the one users can see:** 100 department codes
appearing in the data have no display name, so they render as raw codes wherever
a department label is shown.

**`hr_org_desc_to_dept` is half dead:** 38 of 79 entries never appear in
`cedar_faculty$home_org`. Coverage of what *is* present is 100%, so this is
stale bulk rather than a gap.

### Silently shadowed duplicate keys

`subj_to_dept` is a named vector with **16 duplicate names**. R's `[[` returns
the first match, so the second entry is dead and unreachable. Five carry
genuinely conflicting values:

```
BUSA  -> MGMT vs BUSA   uses MGMT
ENVS  -> EPS  vs ENVS   uses EPS
HLED  -> HED  vs HLED   uses HED
PH    -> HSCI vs PH     uses HSCI
SUST  -> GES  vs SUST   uses GES
```

**All five currently resolve to the value the data agrees with** — checked
against `sections$subject → department`. That is ordering luck, not design;
reordering the file would silently reroute five subjects to different
departments. Note these same five (`ENVS HLED PH SUST`) are also the orphans in
`dept_code_to_name`: someone once expected them to become their own departments,
added entries in two maps, and the data never followed.

### What could be derived instead of declared

```
sections: subject    -> department    228 keys   0 ambiguous   clean 1:1
programs: major_code -> dept_code     404 keys   2 ambiguous   (BADM, CRIM)
degrees:  major_code -> dept_code     211 keys   2 ambiguous   (BADM, CRIM)
```

`subj_to_dept` is **fully derivable from the data** — a 228-key clean 1:1 that
is currently hand-maintained at 89% coverage with 5 shadowed conflicts. The two
ambiguous major codes are exactly the branch-campus cases already special-cased
in `program_code_maps.R` (`CRIM→CJUS`, `BADM→BUSA`), so the ambiguity is known
and handled.

### Not a defect: `student_college` vs `college_code`

`programs$student_college → college_code` looks 11/15 ambiguous, but these are
two different concepts, not one concept in two vocabularies:

```
College of Arts and Sciences -> AS 159,355 | GP 21,683 | MG 3 | LW 1 | UC 1
College of Nursing           -> NU  16,755 | UC  9,299 | GP 3,580
```

`student_college` is the student's home college; `college_code` is the
program's. A student in A&S enrolled in a Graduate Programs offering produces
`AS`/`GP`. The near-identical names with no documentation is the real problem
here; the counts of 1 and 3 are separately worth a data-quality look.

---

## 3. The institutional ingest seam

`R/data-parsers/transform-to-cedar.R` is the entire contract between an
institution's reporting system and the CEDAR schema. It requires **55 distinct
source columns**, referenced by literal backticked Banner/MyReports names:

| transform | source columns required |
|---|---|
| `transform_students` | 24 |
| `transform_programs` | 18 |
| `transform_degrees` | 13 |
| `transform_faculty` | 5 |

These names (`` `Student Campus Code` ``, `` `Translated College` ``,
`` `Program Classification` ``) are UNM MyReports vocabulary. A second
institution must either produce identically-named columns or fork the transform.

Beyond `R/lists/`, institution-specific values are also **hardcoded in analysis
code** — `campus %in% c("ABQ", "EA")` appears in `credit-hours.R` (5×),
`dept-trends.R`, `gened-fulfillment.R`, and `gen-ed.R` hardcodes
`campus == "ABQ" ~ "F2F / ABQ"`. Backlog **F2** covers the hardcoded `"AS"`
college; the campus literals are the same class of problem and are not yet
tracked.

---

## 4. Recommended target architecture

Ordered by value per unit of risk.

1. **One vocabulary per concept, codes internally.** Store codes in every
   `cedar_*` column; carry display names only in lookups resolved at render
   time. This is already the pattern for departments (`dept_code_to_name`) —
   apply it to campus and college. Rename `programs$student_college` →
   `student_college_name` (or convert it) so no two columns share a name and
   differ in vocabulary.

2. **Derive what the data can prove; declare only exceptions.** `subj_to_dept`
   should be generated from `sections$subject → department` with a small
   hand-maintained override list for genuine exceptions. That converts a
   215-entry hand-list at 89% coverage into a 228-entry derived map at 100%,
   plus ~5 documented overrides.

3. **Assert mappings at startup, don't assume them.** `cedar_mapping_issues`
   already exists, flags unmapped `program_map` rows without blocking startup,
   and surfaces them in Admin → Data & Usage. Extend it to campus, college, and
   duplicate-key detection. A named vector with duplicate keys should be a
   startup warning, not a silent first-wins.

4. **Make the source contract explicit and machine-checkable.** A manifest
   (YAML) listing the 55 required source columns per input file, validated
   before the transform runs, turns "the transform crashed on a missing
   backtick" into "your export is missing these 3 columns." This is the
   prerequisite for the second-institution goal, and it pairs with **F1**
   (mappings to data files).

5. **Finish externalizing.** Fold the campus literals into config alongside
   **F2**'s college code.

### Sequencing

Items 1–3 are internal and can ship without touching stored data (see BACKLOG
**F4** for the scoped version). Item 4 is the real unlock for a second
institution and belongs with **F1** in the same effort. Item 5 is cleanup that
can ride along.

**None of this blocks 1.0 for current users** — no wrong numbers are being
shown. It blocks *confidently accepting someone else's data*, which is the
roadmap goal it should be scheduled against.
