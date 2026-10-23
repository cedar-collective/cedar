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
  --analysis data/catalog-scans/unm/2026-2027-undergraduate-complete-20261018/analysis-milestones-1.2.0 \
  --programs HkzhQeX5iq,SkWn7eQ9o9,HJlTXxQcic,HJZpXxQ9s9 \
  --output data/catalog-normalizations/unm
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
schema or prompt needs a freshly prepared matching unit and a new draft.

The app stages matching files automatically, idempotently. For maintenance:

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R stage \
  --root data/catalog-normalizations/unm \
  --drafts institution/unm/catalog_interpretations \
  --capture-root data/catalog-scans/unm
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

Storage under `data/catalog-normalizations/<institution>/` is Git-ignored:

| Location | Contents |
|---|---|
| `programs/<packet-key>/` | Immutable packet, embedded request/schema/prompt and manifest |
| `proposals/<unit-key>/<proposal-key>/` | Original proposal bytes, producer attribution and manifest |
| `reviews/<proposal-key>/` | Complete, hash-linked, attributed review revisions |

Review stores must be writable by the Shiny worker for staging and decisions;
keep those directories owned by the application's deployment user. Compose
mounts this store read/write separately from the read-only catalog archive.
Preserve the whole review store and capture archive together in durable storage.
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
