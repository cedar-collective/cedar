---
title: Catalog Scanning
parent: Developer Guide
nav_order: 33
---

# Catalog scanning

The offline scanner captures public catalog records, extracts draft requirement
trees, and compares source language across scans. It does not start Shiny, read
student data, call an AI service, or overwrite reviewed Degree Explorer files.
Every extraction is **unreviewed**. Capture success establishes source collection,
not an executable degree audit or verified academic interpretation.

## Scope and institution files

`institution/<id>/catalog_scan_sources.csv` declares the landing page, provider,
API base and source-level classification fields. The Kuali adapter selects the
explicit `window.catalogId` on that landing page; `--catalog-id` pins another
published edition. It saves the edition list, selected edition, complete program
index and program/course/specialization schemas. UNM's default is its Main Campus
catalog and the units that edition's own query publishes, not every campus edition.

`catalog_scan_credentials.csv` explicitly marks credential labels as
`undergraduate_degree` or `excluded`. New unmapped labels stop the capture.
Unlabeled records are fetched and examined: explicit minor/certificate requirements
and graduate-level records are excluded; other undergraduates remain candidates
for review. Every index entry appears in `program-inventory.csv`. Standalone dual/
shared-credit records, certificates and minors are excluded from this scope.
Embedded concentrations retain their parent program relationships.

`catalog_scan_fields.csv` assigns source fields to admission, degree, prerequisite,
corequisite or informational phases. Labels/types come from the captured schema:
UNM's `graduateAdmissionsRequirements`, for example, is labelled **Admissions
Requirements** on undergraduate records. Unknown published OmegaRules fields
remain unclassified sections requiring review.

## Commands

Run from the repository root with the existing pinned dependencies:

```bash
# Degrees, embedded specializations, and the closure of linked course records.
Rscript --vanilla scripts/scan-degree-catalog.R scan --institution unm \
  --output data/catalog-scans/unm/current-full

# Program records only; no course-page acquisition.
Rscript --vanilla scripts/scan-degree-catalog.R scan --institution unm \
  --programs-only --output data/catalog-scans/unm/current-programs
```

`capture` runs acquisition alone. `scan` captures, then analyzes offline. Output
directories must be new. HTTP errors, malformed records and unknown credential
types stop loudly, leaving an incomplete capture and saved earlier responses.
Resume with the same configuration and scope:

```bash
Rscript --vanilla scripts/scan-degree-catalog.R scan --institution unm \
  --output data/catalog-scans/unm/current-full --resume
```

Resume verifies and reuses saved bytes; it does not refresh earlier requests.
Completed captures cannot be resumed or overwritten. A fresh scan needs a new
directory. The program index is checked again at the end: changed identities or
revision IDs make the capture incomplete instead of silently mixing program sets.

With course acquisition enabled, recognized Kuali course links are followed from
programs and specializations, then recursively from those course records. Cycles
do not loop forever. A course mention/link is a reference, not automatically a
prerequisite edge. Other links remain in the extracted sections; linked policies,
query-based pools and unlinked course mentions still require review.

## Artifacts and interpretation

| File | Purpose |
|---|---|
| `source-manifest.json` | Status, edition, scope/configuration, inventory, source receipts and hashes |
| `sources/*.body` | Exact decoded HTTP response bytes, named by SHA-256 |
| `program-inventory.csv` | Every index entry and its inclusion/exclusion classification |
| `analysis/records.jsonl` | Programs, concentrations and courses with metadata, draft trees, source pointers and links |
| `analysis/rule-nodes.csv` | Parent/child nodes, operator/count, optional minimum grade, course references, source locator/hash and review status |
| `analysis/milestones.csv` | Shared class-standing/admission definitions; each cited use is linked by `milestone_id` in rule-nodes.csv |
| `analysis/sections.csv` | Normalized language, explicit structure fingerprints and metadata, including course credits |
| `analysis/review-queue.jsonl` | Prose/unsupported structures suitable for a later bounded AI proposal stage |
| `analysis/program-coverage.csv` | Requirement-section, degree-section and narrative review counts by program |
| `analysis/source-issues.csv` | Provider query flags, missing degree sections and unresolved credential classifications, without silently dropping source records |
| `analysis/extractor-source.json` | Actual extraction function definitions, R and relevant package versions |
| `analysis/analysis-manifest.json` | Capture/provenance hashes, extraction version, counts and artifact hashes |
| `analysis/REPORT.md` | Readable scope, coverage and review summary |

Receipts retain requested/final URL, UTC retrieval time, HTTP status/content type,
and ETag/Last-Modified when supplied. Bytes are the decoded response body, not
compressed wire bytes. Full JSON retains the enclosing requirement HTML. Scripts
in that HTML never execute. Source evidence includes a JSON pointer (including a
specialization's parent index) and a DOM locator/source anchor within the HTML.

Explicit **all**, **choose N** and **minimum credits from a list** preserve nesting.
A lecture/lab AND bundle inside an OR group remains one alternative. Prose such
as two upper-level courses plus permission stays a condition, not two named edges.
Unsupported structured values also remain reviewable conditions. Missing fields
mean not supplied, never no requirement. Descriptions remain informational.

### Supported patterns, not an ignore list

The legacy parser retains these tested patterns. New semantic interpretation
uses complete-program AI proposals and human review; do not keep growing a
phrase-by-phrase grammar as the primary interpreter. Never suppress a requirement
merely because its wording is common. Extractor 1.1.0 recognizes:

| Source wording | Preserved draft meaning |
|---|---|
| Complete (all of) the following | All child requirements |
| Complete (at least) N of the following | N child options needed; extra completed courses are not prohibited |
| Earn at least N credits from the following | Minimum credits from the child list |
| Earned a minimum grade of G in each of the following | All child requirements, with literal `minimum_grade = G` |
| Earned a minimum grade of G in at least N of the following | N child options with literal minimum grade G |

These are anchored whole-heading matches with an actual child list; invalid
choice counts and absent lists remain flagged. Letter-grade tokens are preserved,
including plus/minus. A C threshold is not C-minus, and it does not invoke CEDAR's
DFW policy. The constraint stays on its group so the original AND/OR scope is
preserved. Unrecognized children still produce their own flags. Qualifiers such
as permission, exceptions, or completion **or concurrent enrollment** stay
conditions until the full expression is supported; a partial regex match must
never erase the qualifier.

Extractor 1.2.0 also recognizes status milestones:

| Source wording | Preserved draft meaning |
|---|---|
| Must have a class standing of S | Recorded standing **is** the literal named status S |
| Must not have a class standing of S | Recorded standing **is not** S |
| Admitted to P, with one explicit program link | Admission to the captured program identified by that link |

Standing labels are captured literally, not converted into ranks, credit bands
or semester numbers. Junior does not silently mean Junior-or-higher. When the
catalog wraps Junior and Senior inside a choose-one group, both milestones and
the OR group remain intact. Inline compound/qualified wording stays flagged.
No current cumulative-credit field is used to infer a historical standing.

Program links resolve through the frozen registry's pid/revision aliases, never
by a matching name. Uncaptured targets remain conditions with an explicit review
reason; they do not expand the undergraduate scan's scope. Multiple-program,
negative-admission and permission expressions remain unsupported conditions.
Each canonical milestone has one definition in `milestones.csv`; rule-node uses
retain separate enclosing AND/OR context, course evidence, pointers and hashes.
The program definition includes its captured admission-policy context once.
Changing a standing, negation or linked program changes the structure fingerprint.

Admission is a required status, distinct from satisfying academic criteria.
Automatic admission must be supported by the target program's policy; the scanner
does not infer that a student has been admitted or compile that policy into an
automatic eligibility decision. A missing admission-policy section means not
supplied, not no conditions. These remain unreviewed staging rules; the authored
semester planner does not automatically schedule or enforce newly extracted gates.

Kuali's named group wrappers retain headings and nested rules. A heading alone
does not imply an academic restriction; extra prose in a wrapper remains a
condition. Plain text within lists is retained too. This prevents a short outer
heading from hiding an entire course group during extraction.

Recognition removes a separate interpretation flag, not the requirement or its
source citation. Every section remains unreviewed. Grade constraints are visible
in the draft tree, included in structural comparison hashes and exported as an
additive CSV column. Schema 1.0.0 readers can still open older grade-free analyses;
their missing optional grade means no grade was extracted, not no grade required.
Regenerate analyses into new directories when recognition improves; never mutate
an archived report. Extractor provenance distinguishes this from a catalog change.

Source `__passedCatalogQuery=false` flags are surfaced literally for inclusion
review. They do not establish cancellation, offering availability or an equivalent
replacement. These records and their citations remain in the capture/extraction.

Locators and revision IDs are evidence, not permanent comparison identities.
Program/course `pid` supplies identity. Conflicting revisions for the same
comparison identity stop analysis for review. All nodes remain unreviewed even
when their explicit list structure was recognized.

Captures default to local, Git-ignored `data/`. Preserve the **whole capture
directory**, including manifests and `sources/`, in the institution's durable
archive. A hash cannot reconstruct an old source. `--output` can name that archive
directly. Capture directories can be copied together without changing source bytes.

## Offline rebuilding and annual review

Re-extract frozen inputs into a new analysis directory without network calls:

```bash
Rscript --vanilla scripts/scan-degree-catalog.R analyze \
  --input data/catalog-scans/unm/current-full \
  --output data/catalog-scans/unm/current-full/analysis-new

Rscript --vanilla scripts/scan-degree-catalog.R compare \
  --before data/catalog-scans/unm/previous-full/analysis \
  --after data/catalog-scans/unm/current-full/analysis \
  --output data/catalog-scans/unm/annual-comparison
```

Make a fresh capture for the new edition, preserving the old baseline. Comparisons
require matching program/course scope and verify generated artifact hashes.
`changes.csv` and `CHANGES.md` distinguish additions/removals, metadata, wording,
explicit list structure and formatting, with before/after source URLs and hashes.
Wording-only does not establish equivalent academic requirements. The comparison
manifest separately flags changed extractor code/package provenance or configuration.

Tests extend `test-degree-explorer.R` using the demo institution's authored
`catalog-source-fixture.json`: nested OR/AND, changed counts/credits, prose and
structured restrictions, complete inventory, link cycles, resume, corruption and
comparison scope. Live scans supplement those designed regression checks.
