# Reading UNM's catalog

Each file here is one reading of one program's catalog record: what its
requirements are, every rule citing the catalog's exact words. Files sit under
their edition (`2026-2027/`) as `<program>.v<n>.json`. A reading is an AI
proposal, a draft until a person signs off the whole unit in Catalog Review.
It is never an approval, a student audit or a forecast input.

This page records **how UNM's catalog says things, and how the readings here
have read them**, so the next reading starts from these decisions instead of
rediscovering them. Every convention below is taken from the readings in this
folder; when a reading settles a new pattern, add it here in the same change.

- How to write a reading, step by step: the `catalog-reading` skill
  (`.claude/skills/catalog-reading/SKILL.md`).
- The schema, the checks, staging, review and the compiler:
  [catalog-normalization.md](../../../docs/developers/catalog-normalization.md).
- What a node may mean is set by `config/catalog-normalization-prompt.txt` and
  `config/catalog-normalization.schema.json`. Don't put UNM conventions there:
  the prompt is part of every packet's identity, so editing it means preparing
  every program's packet again.

## The record

UNM's catalog runs on Kuali. A program is one record, and every passage in a
packet carries the record field it came from. The field names are Kuali's,
and two are misleading:

| Field | What it holds | How a reading covers it |
|---|---|---|
| `degreeRequirements` | the program's requirement tree, one line per passage ([below](#the-requirement-tree)) | requirements; a heading or note that requires nothing is information |
| `concentrationRequirements` | each concentration's tree, on its own entity (`specializations:<id>`) | requirements, on the concentration's entity |
| `graduateGraduationRequirements` | **the undergraduate program's graduation requirements**, despite the name: residency, GPA, the college's rules | sentence by sentence: requirements, or information when a sentence requires nothing |
| `graduateAdmissionsRequirements` | **admission to the program**, despite the name | `phase: admission` ([below](#admission)) |
| `description` | prose, which sometimes restates the tree and sometimes contradicts it | information, unless it states a requirement the tree lacks; a contradiction is an `unresolved` rule and a question |
| `degreeHours` | the degree total as text: `"120"`, or `"A minimum of 128 hours"` (Secondary Education B.S.) | requirements: the degree-total rule cites it ([below](#the-degree-total)) |
| `concentrationRequired`, `minimumMajorHours` | a flag, a number | requirements when they state one; a flag the prose contradicts is unresolved (Business: the flag requires a concentration, the prose allows a General Management route) |
| `title`, `code`, `degreeType`, `ugGrDegree`, `dateStart`, `catalogActivationDate`, `groupFilter1`, `groupFilter2`, `dualDegree`, `emphasisRequired`, `inheritedFrom`, `isThisProgramAlsoOfferedOnline`, `__passedCatalogQuery` | record metadata | information |

## The requirement tree

Kuali renders the tree as fixed phrases. The readings read them this way:

| Catalog line | Reading |
|---|---|
| `Complete all of the following` | `all` |
| `Complete at least 1 of the following:` | `choose_n`, `unit: courses`, `minimum` 1; a lecture and its lab offered together are an `all` inside it |
| `Earn at least 15 credits from the following types of courses:` | `credits`, `minimum` 15, its listed courses as children |
| `Earned at least 18 credits from HIST 300 - 499` | `credits` with `minimum_course_number: 300`, the subject and range in `value` |
| `Earned at least 3 credits from 400 - 499` (no subject) | the same, and a question asking whether any subject counts (Computer Engineering) |
| `Earn at least this many additional elective credits: 3` | `credits`, an unlisted pool |
| `CE160L - Civil Engineering Design (3)` | `course`, one registry ref; the code is printed without a space, and the credits come from the course's own unit, not this line |
| `Grand Total Credits: 120` | the total of the tree it closes: `degree-total` at the top, `<concentration>-total` in a concentration |
| `Grand Total Credits: 55 - 56` | `minimum` 55 and `maximum` 56 |
| `Earned a minimum grade of C in each of the following:`; "with a grade of C or higher in each course" | `minimum_grade` on the group it scopes |

## Course numbers

- UNM's lower-division courses have four-digit numbers (`ENGL 1120`, `MATH 2531`)
  and its upper-division courses three (`CE 302`, `HIST 491`). 500-level
  courses are graduate courses.
- `minimum_course_number` is the number as written: 2000 for "ARTH 2000 -
  2999", 300 for "300 - 499". The compiler reads 1000–2999 as lower division
  and 300–499 as upper.
- A three-digit lower-division range ("ARTH 200 - 299", "200-level or above")
  is ambiguous under the four-digit numbering. Record it as written and ask the
  catalog (Art Studio B.F.A., Elementary Education).
- A 500-level course listed for undergraduates stays as listed, with a question
  (Chemical Engineering's concentrations).

## The degree total

- `degree-total` is the reading's one top-level `credits` rule for the degree.
  It cites the `degreeHours` passage and the tree's closing "Grand Total
  Credits" line, and the graduation requirements' sentence when there is one.
  The compiler plans the board to it; where `degreeHours` is a bare number, the
  two must agree (ISSUES I99).
- Totals that disagree stay disagreeing. A count that doesn't add up (Business:
  "31 core credits" over eleven 3-credit courses) or two totals (Business's 44
  and 41) is an `unresolved` rule with a question for the catalog; never pick
  the convenient one. The compile also adds a question for the catalog for
  every program whose record gives its total two ways, read or not.
- Other top-level totals keep their own ids: `gened-total`, `residency`,
  `admit-credits`, `upper-division`.

## General Education

- The 2026–2027 areas: I Communication, II Mathematics and Statistics, III
  Physical and Natural Sciences, IV Social and Behavioral Sciences, VA
  Humanities, VB Second Language, VI Arts and Design, VII Flexible Student
  Choice (`shared_requirements/2026-2027/general-education.json`).
- **An area pool** ("Humanities: 3 credit hours chosen from the General
  Education curriculum list.") is a `credits` rule inside the tree, named in
  `gen_ed_pools` with its area: `{"rule": "humanities", "area": "VA"}` (Business).
- **A remainder pool** ("Additional course work to meet remaining University
  requirements", "At least 26 elective credits in any field", "N more credits
  toward the concentration, General Education and electives") is named with
  `area: ""`.
- **A top-level pool** "toward General Education and other degree
  requirements" (History's 84, Philosophy's 90) is not named: the compiler
  lists an unlisted credit rule at the top of the tree for a reviewer, never as
  tiles, and `gen_ed_pools` names only pools inside the tree.
- A reading can name pools only when its board has a profile in
  `shared_requirements/2026-2027/bundle.json`. Liberal Arts and Integrative
  Studies (University College) has none (ISSUES M82).

## Admission

- Admission text is `phase: admission`, kept apart from the degree.
- Credits for admission come in two figures: "A minimum of 26 credit hours; 23
  credit hours must be in courses acceptable toward graduation" is two rules,
  `admit-attempted` and `admit-applicable`.
- A GPA per population is one `gpa` rule each, the population in `value`:
  continuing UNM students' institutional GPA, transfer students' transfer GPA.
- Admission to the program as a condition of candidacy is `program_admission`
  naming the program's own registry ref (Chemical Engineering).
- School of Engineering admission, whose criteria these records don't state,
  is a question for CEDAR's copy of the catalog (Computer Science, Chemical
  Engineering, Civil Engineering).
- Automatic admission needs its sentence. Business's "Completion of all Phase
  I courses (21 credits) automatically moves Pre-BBA to BBA status" is a
  `restriction` citing it, never inferred from the Phase I list.

## GPA, residency and conditions

- `gpa` rules say their scope in `value`, in the catalog's words: "All work",
  "UNM grade point average", "Grade point in the major", "All credit hours
  attempted while enrolled in the College of Fine Arts".
- Residency ("Completion of a minimum of 24 credit hours in residence") is a
  top-level `credits` rule with where in `value`.
- What a student must do that is not a course or a count is a `restriction`
  with the whole sentence in `value`: a portfolio review, a graduation
  application, an advisor meeting, the FE exam, a limit on physical education
  credit, "No C/NC" rules, "No minor is required".
- A chair's, advisor's or department's approval is a `permission`.

## Concentrations

- Each concentration is its own entity; its rules bind only its students. Its
  closing "Grand Total Credits" is `<concentration>-total`, and an
  upper-division share within it (Secondary Education's "at least 12 credit
  hours at the 300-level or above") is `<concentration>-upper`.
- When the program's narrative describes the concentrations differently from
  their own records (Chemical Engineering's "6 credit hours of technical
  electives" against a 9-credit Semiconductor concentration), keep both and
  ask the catalog.

## Who settles each open item

Each open item (an `unresolved` rule, an uncovered passage, a question) gets a
`triage` entry. Across the latest readings, 39 are for the catalog, 6 for
CEDAR's copy of the catalog and 6 for CEDAR's reading. What sends an item to
each:

| `settled_by` | UNM examples |
|---|---|
| `catalog` | two totals, or a total its courses don't add to; "three of the following four areas" over a list of six; a requirement "pending a curricular update"; a record copied from another (the B.A.Ed. naming the "BSED"); a pool that doesn't say which requirement it counts toward |
| `capture` | a footnote the captured table lacks (Chemical Engineering's "Footnote 1"); another program's admission criteria; an empty admission field; college graduation requirements the B.F.A.'s record doesn't carry |
| `reading` | the catalog leaves a choice and the reading planned one way: Computer Science's science pool as four courses with labs; LAIS's 51 upper-division credits without a concentration, against 45 with one; whether students declared under LIBA belong to LAIS |

## The file

- `producer` names the model and the session, and says no API call was made:
  `"Claude (Opus 5.5); source interpretation in the CEDAR development session, 2026-11-26; no API call."`
- `scope`: the program and its embedded concentrations only; linked course
  units are not interpreted; a draft with no human academic approval.
- A new version is a new file (`history.v2.json`); the earlier one stays. A
  reading written from an earlier prompt's packet (History v1, Philosophy v1
  and v2) keeps its packet, which stays in the store.
- `triage` and `gen_ed_pools` sit beside `proposal`, so editing them changes
  no packet, staged key or sign-off.

## A program with no hand-built board

Its board is written only when `institution/unm/degree_reading_catalogs.csv`
gives its catalog row: names, the degree code and the Banner program codes of
its students, pipe-separated and including the pre-major code, decided against
`programs.csv`: `BSCPE-CPE-EN|BSCPE-FCP-EN`. A Banner code carries the degree
(`BA-PSY-AS` and `BS-PSY-AS` are two programs), so a B.A. and a B.S. of one
subject are two rows. No reading supplies these.
