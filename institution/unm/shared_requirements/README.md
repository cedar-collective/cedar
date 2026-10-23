# Shared UNM requirements

Read the [2026–2027 rules](2026-2027/RULES.md), gathered from the current Main
Campus catalog on **2026-10-20**. `RULES.md` is generated from the JSON rather
than maintained as a second interpretation. Statements are readable paraphrases;
their JSON records retain catalog links, exact source hashes and locators.
The normalization was assistant-authored from those sources, not inferred by
the legacy phrase parser. `bundle.json` records that provenance and the absence
of academic review; deterministic recapture does not redo the interpretation.

Keep separate files by authority, with one rule format:

| File in `2026-2027/` | Purpose |
|---|---|
| `university.json` | Bachelor completion, residency, grades, writing, cultures and catalog-selection rules |
| `general-education.json` | The 31-credit Gen Ed structure, eight areas, transfer treatment, composition preparation, overlap and restrictions |
| `colleges/*.json` | College-scoped admission, completion and overlap rules, or explicit limits of the checked source |
| `bundle.json` | Edition files, composition policy and the shared sets applicable to each prototype degree |
| `gen-ed-course-memberships.csv` | Courses explicitly enumerated in the Gen Ed program, excluding open language/studio alternatives |
| `sources.json` | Public page/API links, retrieval times, response hashes and capture receipts |
| `RULES.md` | Generated readable rules and source questions |

Existing `degree_rules.csv` and roadmap files remain degree-specific. A program
profile links their catalog IDs to University + Gen Ed + the **awarding
college**. This is not a Banner program/department mapping. These are reference
transcriptions, not advisor approvals or executable student audits. Typed
planning fields now supply illustrative coverage, named Gen Ed slots and
standard upper-credit context to the semester planner. Other allowance slots
remain flexible elective/minor credits. Conditional alternatives and student
evaluation still need implementation.

## Common format and scope

Each set has `schema_version`, `rule_set_id`, `catalog_year`, `catalog_id`,
`title`, `scope`, `coverage`, `notes`, `rules` and `attention`. A rule has a
stable `rule_id`, `label`, readable `statement`, `phase`, `operator`, `role`,
`applies_when`, transcription status and `source_refs`. The degree-rule
AND/OR vocabulary is reused: `all`, `choose_n`, `credits`, `course`, `condition`,
`none`. Alternatives use nested `children`, inheriting parent source references.
Bounds, units, grade thresholds and specialized exceptions stay explicit.
Named college alternatives identify `alternative_to`; their applicability is
recorded in words and is not yet evaluated by CEDAR.
`source_refs` identify a saved source, JSON pointer and exact anchor. An anchor
locates evidence; it is not proof that a paraphrase is academically correct.

Roles distinguish totals, subsets/areas, restatements, conditional alternatives,
allocation policies, guidance and milestones. **Never sum all thresholds.**
31 Gen Ed credits, 90 A&S credits and 48 upper-division credits constrain the
same degree-credit record. Approved overlaps can satisfy multiple rules while
earned credits count once. College rules can narrow University allowances.
Alternatives and conflicts must not become silent overrides.

The college files cover the six awarding colleges in the prototypes. A&S,
Engineering and Business have selected shared rules. Nursing, Population Health
and Medicine record that no common bachelor completion block was located on
their checked overviews. Empty lists are coverage limits, **not exemptions**.
Program/route rules still apply. Other colleges are not covered by this first set.

The new membership CSV uses Roman area labels, including VA/VB. Existing
`gen_ed_courses.csv` uses historical numeric analytics labels and a different
membership set. It is preserved; do not join their area codes blindly or replace
analytics mappings without a separate review. Flat membership does not prove
valid science/lab pairings. Open language and approved advanced studio choices
cannot be reduced to invented finite lists.

## Check, read and update

Run from the repository root:

```bash
# Metadata, identities, scope, alternatives and membership structure.
Rscript --vanilla scripts/shared-requirements.R check institution/unm/shared_requirements/2026-2027

# Also verify original bytes, pointers, anchors and referenced course URLs.
Rscript --vanilla scripts/shared-requirements.R check institution/unm/shared_requirements/2026-2027 data/catalog-shared-requirements/unm/2026-2027-20261020

# Regenerate the readable rules after editing JSON.
Rscript --vanilla scripts/shared-requirements.R render institution/unm/shared_requirements/2026-2027 > institution/unm/shared_requirements/2026-2027/RULES.md

# Capture pinned-edition sources into a NEW directory; never rewrite rules.
Rscript --vanilla scripts/shared-requirements.R recapture institution/unm/shared_requirements/2026-2027 data/catalog-shared-requirements/unm/2026-2027-new-check
```

Exact public responses are stored in the capture directory named in
`sources.json`, using the catalog scanner's immutable hash mechanism. Preserve
that archive with CEDAR data backups; it is not committed with the rules.
A metadata-only check explicitly reports that source bytes were not verified.
A byte/locator check establishes integrity and locator existence, not semantic
correctness or a complete course-allocation audit.

Recapture reports changed response hashes at this edition's pinned URLs. It
detects changes within 2026–2027; it does **not** automatically discover or
interpret next year's edition. Create a new annual directory, rediscover its
edition/content IDs, capture pages, compare rules and alternatives, and update
profiles. Preserve prior editions in Git and their source archives. Editing
only a year/date is not an annual review. Administrative prose can change a
source hash without changing a degree requirement.

Recorded source questions cover flexible-area numbering, cultures-requirement
naming, A&S Honors credit treatment, Engineering technical admission credits
and Business's Phase I GPA typo. These are cases to clarify, not a separate
approval checklist for every routine rule.

## Runtime planning

The shared bundle now supplies illustrative Gen Ed coverage to Degree Explorer and
Admin Visualization rules. Typed planning fields split Communication, identify
related science bundles and describe flexible choices. Selected course credits
are consumed once across these areas; open choices only advertise potential
coverage. Remaining needs earmark existing allowance space, while other slots
are labeled elective/minor and may use upper-level courses. The standard A&S
upper-level minimum is shown as overlapping credit context. Conditional college
alternatives, student grades, transfer and approvals are not evaluated. Flexible
coverage remains provisional because of the recorded policy-numbering conflict.

`planning_parts`, `planning_method`, `planning_course_count`, `planning_metric`
and the Gen Ed set’s `planning` configuration are executable interpretations;
review them alongside their source-linked rule when updating the annual edition.
The existing numeric Gen Ed analytics mapping is unchanged.
