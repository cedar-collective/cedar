---
title: Catalog Interpretation and Review
parent: Developer Guide
nav_order: 34
---

# Catalog interpretation and review

The normal Catalog Review landing page is **Visualization rules**, a readable
view of the saved data already driving Degree Explorer. It requires no approvals.
This document describes the optional **Draft interpretations** workflow for
preparing future catalog ingestion.

AI proposes a complete interpretation; a human compares it with the catalog.
The older phrase parser is an extraction diagnostic, not the primary semantic
interpreter. Preserve the scanner's immutable capture, source hashes, edition
identities and annual language comparisons. No model calls run in Shiny.

For the solo-maintainer workflow, interpretations are authored as versioned JSON
under `institution/<id>/catalog_interpretations/<edition>/`. CEDAR validates and
stages them automatically when Program review opens. The upload/exchange UI and
its observer are commented out for later shared use; the backend and maintenance
CLI remain available. No API credential or new dependency is required.

The initial v1 files cover History, Philosophy, Business Administration and
Computer Science, including their embedded concentrations. Codex interpreted
complete captured program sections in the development session; these are real
AI-assisted drafts, not parser output or test fixtures. Attribution records that
no API call occurred. They are **not human-approved**. Linked-course prerequisite
units still need their own interpretations; the UI labels those as not drafted.

## Prepare programs

From the repository root:

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R prepare \
  --analysis "$CEDAR_DATA_DIR"/catalog-scans/unm/2026-2027-undergraduate-complete-20261018/analysis-milestones-1.2.0 \
  --programs HkzhQeX5iq,SkWn7eQ9o9,HJlTXxQcic,HJZpXxQ9s9 \
  --output "$CEDAR_DATA_DIR"/catalog-normalizations/unm
```

This pilot selects History, Philosophy, Business Administration and Computer
Science. Pass any captured undergraduate program IDs to extend it. Preparation
uses frozen sources and makes no network or AI requests. The existing scanner
still determines the latest published edition and undergraduate scope.

Each program has one interpretation unit containing its complete program and
embedded concentration sections, plus separate units for linked courses. Course
units include their own complete records and captured admission-policy context
when program links resolve. Course references never establish requirements.
Identical course inputs/instructions/schema produce the same unit key across
programs, so imported proposals and reviews can be reused. Concentrations retain
their own identities and the occurrence under the selected parent program.

Public record metadata is supplied too: requirements can appear in fields such
as degree hours or concentration-required flags. Visible text is partitioned
mechanically into passages, with DOM ancestry and enclosing HTML retained.
No old parser interpretation is included in the AI request. Every requested
passage needs a coverage entry, even when classified informational. Linked
policies outside the capture remain explicit unresolved references; no live
fetch fills them silently.

Instructions are in `config/catalog-normalization-prompt.txt`; the normalized
vocabulary and response contract are in `config/catalog-normalization.schema.json`.
Packets embed both. Changing source, instructions or schema changes the content
identity; previous proposals and decisions are not overwritten or inherited.

## Compare and sign off

Open **Admin > Data & Usage > Catalog Review > Draft interpretations**. The page reads
prepared packets and stages local drafts without loading the older all-catalog
diagnostic queue. No export/upload round trip is needed.

1. Select a program and interpretation version. The initial selection is the
   program/concentration unit; linked course rules are separate units.
2. Start with **Cases needing attention**. These are unresolved interpretations,
   catalog conflicts, open questions and issues explicitly flagged by a reviewer.
   Several passages supporting one unresolved rule count as one case.
3. Select a rule to compare its normalized meaning with exact catalog evidence.
   All source passages remain inspectable, including passages classified as
   informational. Expand the enclosing section to check context.
4. Correct interpretations using the rule or complete-proposal editor. Resolving
   an authored unresolved case requires correcting its meaning and coverage,
   rather than merely dismissing a warning. Reviewer-created flags can be cleared
   with a resolution note. Edits reopen the complete unit review.
5. After comparing the **whole unit**, enter your name and choose **Approve
   complete unit** once. Routine rules and source passages require no separate
   approval clicks. Sign-off remains blocked by unresolved cases. Successful
   validation or AI confidence never supplies human approval. Names are entered
   by the reviewer, not verified account identities.
6. The reviewed export includes the proposal, evidence, version identity and
   attributed review receipt. It does not yet change plans or projections.

Program-level sign-off covers the program and its embedded concentrations, not
all linked courses. First interpretations need a human assessment of the complete
comparison, with detailed editing concentrated on edge cases. Future annual
review should concentrate on changed language and changed interpretations; the
existing scanner provides language diffs, but automatic semantic approval reuse
across catalog editions is not implemented.

## Versioned drafts

Each JSON file contains `schema_version`, positive integer `version`,
`catalog_id`, `program_id`, `unit_key`, `producer`, `scope`, and `proposal`.
The proposal uses the fixed normalized schema. Its complete coverage map and
exact quotations bind it to the prepared unit; source hashes and locators remain
in that immutable packet. Git retains the authored data and reviewable diffs.
Create `program.v2.json` for a subsequent draft and retain v1. A changed source,
schema or prompt needs a freshly prepared matching unit and a new draft. The
compile script builds each program from its latest version, from the packet
whose program unit matches the reading's `unit_key`; packets prepared under an
earlier schema stay in the store for the earlier versions.

The app stages matching files automatically, idempotently. For maintenance:

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R stage \
  --root "$CEDAR_DATA_DIR"/catalog-normalizations/unm \
  --drafts institution/unm/catalog_interpretations \
  --capture-root "$CEDAR_DATA_DIR"/catalog-scans/unm
```

Staging validates the source archive, schema, citations, coverage and graph;
missing/mismatched source packets fail explicitly. Each validated version enters
the immutable proposal store. Staging never writes a human decision. Previous
responses and review receipts survive; approvals belong to the exact proposal.

The retained CLI `import --root ROOT --program PACKET_KEY --unit UNIT_KEY
--response FILE --model NAME` supports maintenance and future API automation.
Restore its commented UI controls and observer together when file exchange is
useful to other reviewers. No student data is included in interpretation packets.

## Rules, checks and provenance

The graph has explicit parents and entity/phase boundaries. AND lecture/lab
bundles stay inside OR/choose-N alternatives. Credit totals differ from course
counts. Grades stay on their scoped group. Upper-level-course counts, class
standing, admission status, permissions and unresolved restrictions remain
distinct from named prerequisite edges. Junior alone is not a credit threshold;
completed admission criteria do not establish an admission award. Planning
preferences do not become catalog requirements.

Each node cites a requested passage and an exact case-sensitive quotation.
CEDAR checks the quote against that passage, rejects unknown course/program
IDs, invalid parent graphs/cycles, missing citations, missing/duplicate coverage,
inconsistent coverage links and impossible choice counts. Bounds and units are
validated. Passing these checks establishes a reviewable structure, not a correct
academic interpretation. Humans must catch incorrect meaning, missing scope,
and passages incorrectly called informational.

The store is `catalog-normalizations/<institution>/` in the app's data
directory (`CEDAR_DATA_DIR`, beside the Banner tables and the catalog archive),
not in Git:

| Location | Contents |
|---|---|
| `programs/<packet-key>/` | Immutable packet, embedded request/schema/prompt and manifest |
| `proposals/<unit-key>/<proposal-key>/` | Original proposal bytes, producer attribution and manifest |
| `reviews/<proposal-key>/` | Complete, hash-linked, attributed review revisions |

Review stores must be writable by the Shiny worker for staging and decisions;
keep those directories owned by the application's deployment user. The store
is inside the data directory's read/write mount; Compose mounts the catalog
archive over it read-only. Preserve the whole review store and capture archive
together in durable storage.

**A committed reading needs its packet and its captured pages on every server
that runs the app** (ISSUES I101). Copy both from the machine that prepared
them with `bash scripts/sync-catalog-store.sh` (`--dry-run` first lists what
it would copy) before merging the reading. It only adds and updates, so the
server's own proposals and reviews are kept. The deploy runs
`scripts/check-catalog-store.R` in the new image before it replaces the app,
and stops, naming every reading short of its files, when one is; staging names
them all the same way instead of stopping at the first.
The app verifies packet/proposal hashes and review-history links. Source bytes
are verified when opening a unit/passage, saving a decision and exporting.
A directory lock and expected review head reject simultaneous/stale writes.
If a process dies while holding `.lock`, an administrator must verify no writer
is active and remove that lock before retrying; there is no silent lock takeover.

Annual refresh creates new capture/packet identities. The existing language
comparison identifies changed source sections. New proposals and reviews stay
separate from prior approvals; automatic semantic diffs and a reviewed runtime
compiler are still future work. Do not call successful import an annual review.

Regression coverage extends `tests/testthat/test-degree-explorer.R` using the
authored demo catalog: versioned staging, evidence validation, batch sign-off,
unresolved-case blocking, revisions and stale writers. Browser coverage in
`tests/e2e/admin.test.mjs` verifies real pilot comparisons and absent upload
controls, then exercises flags, edits, one-click sign-off and persistence on an
explicitly attributed disposable workflow fixture. It removes only that fixture
and its receipts afterward; no real program is approved by a test.

## Compiling a reading into board rows

`R/branches/degree-compiler.R` turns one interpretation into draft Degree
Explorer rows, and `scripts/compile-degree-interpretations.R --root
REVIEW_ROOT` prints each committed interpretation beside its hand-built board.
It reads prepared packets for course credits (each course unit's own catalog
record) and writes nothing.

| Reading | Draft |
|---|---|
| a required `course` | one tile |
| `choose_n` / `any`, or credits from a listed set | one choice, with its options; a two-course option fills two tiles |
| `choose_n` / `any` with an option that names no course ("one strand", three of them 9 credits of endorsement courses) | elective space for k of its smallest option's credits; k tiles of unknown credits when an option states none (ISSUES I98) |
| a credit group whose listed courses add to its minimum | each course required |
| an unlisted credit pool inside a group | elective space, credits ÷ 3 tiles (rounded, at least one) |
| an unlisted credit rule at the top of the tree | listed for a reviewer, never a tile: the schema cannot tell an elective pool from a total or a residency rule |
| admission, policy, GPA, grade, permission, standing, restriction | a condition |
| `unresolved` | a question for the reviewer, never an option |
| a concentration's rules | listed, not compiled |

On the four-program pilot (2026-2027 catalog) the comparison found:

| Program | Tiles, compiled / board | What differs |
|---|---|---|
| History B.A. | 12 / 12 | nothing; the same 18 elective credits |
| Computer Science B.S. | 26 / 26 | the board shows CSCI 1210, which the reading does not name; the science pool drafts five tiles for "14 credits" where the rule means four courses with labs (flagged) |
| Philosophy B.A. | 14 / 10 | three overlapping elective rules draft 12 credits where the board holds 6 (the reading flags the overlap) |
| Business Administration B.B.A. | 24 / 23 | four Gen Ed area pools become elective space; nine concentrations not compiled |

Every required course is either on its board or on the shared math and English
routes, and every board course except CS's CSCI 1210 is in its reading. The
differences are where the reading is ambiguous, and each such passage is
already an unresolved question in its reading.

### The draft board

`R/branches/degree-compiler-board.R` turns the compiled rows into the tables an
authored board has (`degree_catalogs` through `degree_roadmap_plans`), runs them
through the same validators (`validate_degree_catalog()`,
`validate_degree_roadmaps()`), and hands them to `build_degree_roadmap()`
unchanged. With `--analysis DIR` the script builds each draft and prints it
beside its hand-built board, semester by semester.

- **The degree total** is the reading's: its one top-level credit rule that
  cites the record's Degree Hours field. The record's field is text ("120", or
  "A minimum of 128 hours"), so it is never parsed for the number; when it is
  a bare number, the two must agree, and the build stops naming the program
  otherwise (ISSUES I99).
- **Placement.** A lower-division tile starts in semester 1 and an upper-division
  one at the semester most authored plans use (5). The scheduler moves each one
  later for prerequisites and load, as it does for an authored board. An elective
  slot takes the band of the lowest course number its reading allows
  (`minimum_course_number`, schema 1.1.0, cited like any other field: "Earned at
  least 6 credits from 400 - 499" is 400), and a 400-level slot starts at the
  plan's `senior_level_from_semester`. A slot with no stated number takes its
  group's level: upper when every course its group requires is upper. A label is
  never read for a level (ISSUES I64).
- **Arrows** come from the course pages' structured requisites in a catalog
  analysis from extractor 1.4.0 or later, timed by the catalog's own template
  ([catalog-scanning.md](catalog-scanning.md#requisite-timing)). A requisite
  is held for a reviewer, never drawn, when:
  - its wording isn't a recognised template;
  - the pair lists each other (the board can't draw a cycle);
  - a shared tile needs a course offered in a choice (its shared route places it).
- **Waiting on a choice.** A choice tile carries no arrows (the authored boards'
  rule: the option a student takes isn't known). A course that needs one of a
  choice's options instead gets a course-count condition on the choice's tiles,
  so it's planned a semester after the first of them and shows the condition
  rather than an arrow. Requisites under one "one of" in the course page share
  a condition across every choice that offers a member; a "one of" a drawn
  arrow already serves needs none. The condition always adds a semester, even
  where the catalog allows the same term.
- **The shared routes** come from the institution's boards:
  - Math plans toward the reading's required shared math course. A program
    with none plans toward the course most authored boards use for general
    education math.
  - Preparation tiles cite their route's course evidence.
  - Other shared tiles are labelled illustrative.
- **Enrollment conditions** come from the same course pages
  (`degree_course_conditions()`). They show on their course and never move it,
  except a count of courses:
  - class standing and program admission, which the extractor structures;
  - permission wording and "Admitted to ...", which it keeps as text;
  - "a minimum of N upper-division courses in <subject>", with the subject
    matched by the catalog's own name for it. It becomes a course-count
    condition over the board's upper-division tiles in that subject: courses,
    choices whose every option qualifies, and elective slots whose group's
    required courses are all in that subject.

  Alternatives made only of conditions ("Junior or Senior standing") are one
  condition. A condition offered as an alternative to coursework, an exclusion
  ("Not admitted to ..."), and wording not recognised are held.
- **Recorded requirements.** The reading's own tree becomes the board's
  `degree_rules` (`degree_reading_rules()`), which the page lists as its
  catalog requirements: groups, credit totals (a credit pool keeps its courses
  as children), courses, and every other kind as a condition in the reading's
  words. Concentrations are listed as concentrations; information passages are
  left out.
- **Every tile** cites the reading's quotation for its rule, and every arrow
  and condition cites its course page. Each carries the draft note: no one has
  reviewed it.

On the pilot, with the calculus start:

| Program | Courses on both boards | Same semester | Within one | Arrows, draft / board | Conditions, draft / board | Held |
|---|---|---|---|---|---|---|
| History B.A. | 5 | 3 | 4 | 1 / 1 | 2 / 2 | 0 |
| Philosophy B.A. | 4 | 3 | 3 | 1 / 1 | 0 / 0 | 0 |
| Business Administration B.B.A. | 19 | 11 | 19 | 14 / 25 | 11 / 0 | 1 |
| Computer Science B.S. | 18 | 8 | 14 | 17 / 25 | 15 / 0 | 6 |

History's two are HIST 491's, as on its hand board: two upper-division History
courses first, and department permission. Business's and CS's conditions are
the waits on a choice (10 and 5) and the admission and permission conditions
their course pages state, which their hand boards leave out.

Where the semesters differ, the draft is usually earlier: 18 of the 21
differences. The draft starts every tile as early as its level allows, where an
author spaces a sequence. The three later ones are Business's BUSA 1110 and
CS's MATH 1522 and CS 375. CS 375 waits on the linear algebra choice, which
load pushes to semester 6.

The conditions barely move placement: Business's placements don't change, and
in CS only C Programming and Java II move, from semester 1 to 2 (13 to 14 within
one semester). The other waiting courses already started after their choice by
level or load. The hand boards draw those arrows from an example pick (Business's writing
choice gates seven upper-division courses, CS's Java I choice gates C
Programming and Java II); the draft names the wait instead of choosing one.

### Publishing a compiled board

`--write` (with `--analysis`) replaces `institution/<id>/degree_drafts/` with
every compiled board. A board's own rows are written in the same files and
columns as the authored boards, and `degree_drafts.csv` records where it came
from: the reading, its packet, unit and staged proposal, the reading's hash,
and the analysis. Each reading must be staged first
(`scripts/normalize-degree-catalog.R stage`). A draft takes its authored
board's catalog row. A program with no authored board takes its row from
`institution/<id>/degree_reading_catalogs.csv` (the same columns as
`degree_catalogs.csv`): its names, and the Banner program codes of the
students it describes, which no reading can supply and are decided in that
file. A reading with neither is listed and not written. With no hand-built
board to compare, the script lists the draft's semesters, arrows, conditions
and courses on their own.

At startup (`R/features/degree-drafts.R`) the app reads the folder and puts
each draft in place of the authored board with the same catalog id, keeping
the degree list's order and every link to the board; a draft for a program
with no authored board follows the authored ones. The result passes the same
validators: each draft's Banner program codes are checked against
`programs.csv` like an authored board's, a code on two boards stops startup,
and so does a draft whose codes differ from its authored board's (codes
decided after it was compiled: recompile). Catalog Review keeps the authored boards, the baseline the
compiler is compared with; their files are not edited.

A compiled board is labelled in the degree list ("· draft") and on the board's
scope bar. It shows as reviewed only when the review store holds a complete
sign-off of the exact reading it was compiled from. It stays a draft, with the
reason on the label's hover, when the store is missing, the reading isn't
staged, it isn't signed off, or it was signed off after edits (recompile from
the edited reading). The status is read once at startup, so a sign-off shows
after the next restart.

### Open questions and who can settle them

A reading lists what it could not settle from the catalog: its `questions`,
each citing a passage, and its `unresolved` rules. Each such open item has a
key within its reading: `rule:<node id>`, `passage:<block id>` (a passage
left unresolved with no rule) or `question:<n>` (its n-th question). These
are the open cases Catalog Review lists for the reading before anyone reviews
it (`catalog_normalization_issues()`).

Each reading says who can settle each item, in a `triage` beside its
`proposal`:

```json
"triage": [
  {"item": "rule:core-total", "settled_by": "catalog"},
  {"item": "question:1", "settled_by": "capture"}
]
```

| `settled_by` | On the page | When |
|---|---|---|
| `catalog` | The catalog | the catalog contradicts itself, is unclear or names nothing; the department or the catalog office answers, and the catalog changes |
| `capture` | CEDAR's copy of the catalog | the catalog says it on a linked page or footnote CEDAR's copy did not keep; the scan is fixed |
| `reading` | CEDAR's reading | the catalog leaves a choice and the reading planned it one way; a reviewer confirms or changes the reading |

The triage is outside the proposal. Staging reads only the proposal, so
changing the triage changes no packet, staged key or sign-off. An item the
triage does not name is listed as "Not sorted yet", and the compile script
prints it. A triage entry that names no open item, names one twice or gives
another value stops the compile.

`--write` lists every open item of every program's latest reading, with or
without a board, in `degree_drafts/degree_reading_questions.csv`. Each row
holds the item, the passage's section and full text from the packet, who can
settle it, the program's catalog page, and the reading file with its hash.
The app reads the list at startup (`read_degree_drafts()`); it never needs
the review store. A reading edited since the list was compiled is named
above the list until the boards are recompiled.

**Admin > Data & Usage > Catalog Review > Catalog questions** shows the list
(`R/features/catalog-questions.R`, `R/modules/catalog-questions.R`):

- **The list:** filtered by who can settle each item and by program. Each row
  names the file and item to change.
- **"Download these questions":** the list as shown, as a Markdown document
  for the department or the catalog office (`format_catalog_questions()`),
  with each question, the start of its passage and the program's catalog
  page.
- **Boards compiled from a reading:** each draft board, whether its reading
  is signed off, and its catalog row's note (what the board leaves out).
  Degree Explorer's "Rules behind this plan" shows the same note.

**To settle an item:**

- When the catalog or the scan changes, prepare the new edition's packets and
  read them again. For the current edition, write a new version of the reading
  (`<name>.v<n+1>.json`) that drops the question or resolves the rule.
- To change only who can settle an item, edit the reading's `triage` in place.
- Then stage the readings and recompile with `--write`.
- A mapping decision a question raises, such as which Banner codes a board
  claims, is made in `degree_reading_catalogs.csv` or `programs.csv`.

### Gen Ed and remainder pools

A program page lists some credit without naming courses: Gen Ed by area
("Humanities: 3 credit hours chosen from the General Education curriculum
list") or what remains of the University's requirements ("Additional
coursework to meet remaining University requirements"). Its wording cannot
tell these from a pool with a real restriction ("12 credits outside the
major"), so a reading names them in `gen_ed_pools`, beside its `proposal`:

```json
"gen_ed_pools": [
  {"rule": "add-math", "area": "II"},
  {"rule": "additional-gened", "area": ""}
]
```

`rule` is an unlisted pool of the reading; `area` is a Gen Ed area of the
edition's shared rules, or empty for the remainder. A named pool draws no
tiles (`degree_reading_gen_ed_pools()`): the board's Gen Ed cards cover the
areas and its elective cards the rest, and an area pool's credits become the
plan's `gen_ed_area_minimums` (`III:8|VA:6`), which raise that area's Gen Ed
cards where they ask for more than the University. Every other unlisted pool
stays an elective tile. A pool that is not an unlisted pool of the reading,
is named twice, names an unknown area or, for an area, states no credits
stops the compile. So does naming pools for a board with no profile in the
edition's `bundle.json`, which would get no Gen Ed cards to cover them. Like
the triage, the pools are outside the proposal, so naming one changes no
packet, staged key or sign-off. The rule they implement:
[degree-explorer-rules.md](degree-explorer-rules.md#what-students-should-see).

## Where draft interpretations live

Moved from `AGENTS.md` on 2026-11-07.

Catalog interpretation uses versioned, complete-program AI drafts plus
separate reusable course units, not a growing semantic phrase grammar.
`R/branches/catalog-normalization.R` validates graphs, citations and complete
passage coverage; `R/features/catalog-normalization.R` preserves immutable
packets/proposals and hash-linked human review revisions. Maintainer drafts in
`institution/<id>/catalog_interpretations/<edition>/` stage automatically; exchange
controls and their observer are commented out for future shared use. Sign-off is
one explicit action per complete unit, blocked by unresolved cases; routine rules
and passages need no individual approval clicks. Edits reopen sign-off. This
optional workflow is under **Draft interpretations**; old queues are **Extraction
diagnostics**, loaded only on demand. `scripts/normalize-degree-catalog.R` and
`config/catalog-normalization*` define the exchange contract. No AI API calls,
automatic approvals or runtime compilation occur; the draft compiler above runs
offline and writes nothing. See
[catalog-normalization.md](catalog-normalization.md).
