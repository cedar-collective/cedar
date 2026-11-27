---
name: catalog-reading
description: Use when writing, revising or checking a CEDAR catalog reading (institution/<id>/catalog_interpretations/<edition>/<program>.v<n>.json), when settling or triaging its open catalog questions, or when compiling readings into Degree Explorer draft boards. Covers preparing a program's packet, reading its passages, writing the proposal with exact citations and complete coverage, checking it with normalize-degree-catalog.R check, triage and gen_ed_pools, staging, compiling, and getting the packet to production.
---

# Writing a catalog reading

A reading is one program's catalog record turned into a requirement tree.
Every rule cites the catalog's exact words, and every passage of the record is
accounted for. It is an AI proposal: a draft until a person signs off the whole
unit in Admin > Data & Usage > Catalog Review. It is never an approval, a
student audit or a forecast input, and no AI API is called to make it. You
write it in this session.

## Read first

1. **The institution's conventions**, beside its readings
   (`institution/unm/catalog_interpretations/README.md` for UNM). They record
   how its catalog says things and how earlier readings read them. Follow them,
   and add to them when a reading settles a new pattern.
2. **The contract**: `config/catalog-normalization-prompt.txt` (what each node
   may mean) and `config/catalog-normalization.schema.json` (the fields). Both
   are embedded in every packet, so **never edit them for a reading**: a change
   re-keys every packet prepared afterwards.
3. [catalog-normalization.md](../../../docs/developers/catalog-normalization.md):
   "Rules, checks and provenance", "Compiling a reading into board rows", "Open
   questions and who can settle them" and "Gen Ed and remainder pools".
4. The program's existing readings, if any, and its row in Catalog questions.

Set `CEDAR_DATA_DIR` (the shared data directory). The packets are in
`$CEDAR_DATA_DIR/catalog-normalizations/<inst>` and the captured catalog in
`$CEDAR_DATA_DIR/catalog-scans/<inst>`; neither is in Git.

## Steps

### 1. Prepare the packet (once per program and edition)

The program id is the end of its catalog URL (`#/programs/SypQxQ9j5`).

```bash
A="$CEDAR_DATA_DIR"/catalog-scans/unm/2026-2027-undergraduate-complete-20261018
Rscript --vanilla scripts/normalize-degree-catalog.R prepare \
  --analysis "$A"/analysis-requisite-timing-1.4.0 --programs SypQxQ9j5 \
  --output "$CEDAR_DATA_DIR"/catalog-normalizations/unm
```

Skip this when `blocks` (next step) already finds the program. Preparing a
program the store holds writes a duplicate packet for the same unit (ISSUES
I103).

### 2. Print the unit, and read all of it before writing anything

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R blocks --program SypQxQ9j5 > <scratchpad>/program-blocks.txt
```

This prints the reading's `program_id`, `catalog_id` and `unit_key`, every
passage (full block id, entity, record field, section, text) and every
registry reference. Put the output in your scratchpad, never in the
repository. Read every passage, the description and the graduation and
admission fields included, before writing a node: contradictions between them
are the most common open items.

### 3. Write the reading

The file is `institution/<id>/catalog_interpretations/<edition>/<program>.v<n>.json`.
A revision is a new `v<n+1>` file; the earlier one stays.

```json
{
  "schema_version": "1.0.0",
  "version": 1,
  "catalog_id": "<from blocks>",
  "program_id": "<from blocks>",
  "unit_key": "<from blocks>",
  "producer": "<your model>; source interpretation in the CEDAR development session, <YYYY-MM-DD>; no API call.",
  "scope": "Program and embedded concentrations only. Linked course prerequisite units are not yet interpreted. Draft; no human academic approval.",
  "proposal": {"schema_version": "1.1.0", "nodes": [], "coverage": [], "questions": []},
  "triage": []
}
```

Add `gen_ed_pools` only when the reading names a pool (step 5). Even an empty
list stops the compile for a board with no Gen Ed profile.

**Every node has every field.** A field missing or extra fails the check. Use
`null` for an unused bound and `""` or `[]` for unused text and lists:

```json
{"id": "upper", "parent_id": "", "entity_id": "programs:HkzhQeX5iq",
 "phase": "degree", "kind": "credits", "label": "18 upper-division History credits",
 "minimum": 18, "maximum": null, "unit": "credits", "comparison": "at_least",
 "value": "HIST 300 - 499", "minimum_grade": "", "course_refs": [],
 "program_ref": "", "timing": "not_applicable",
 "citations": [{"block_id": "b-...", "quote": "Earned at least 18 credits from HIST 300 - 499"}],
 "minimum_course_number": 300}
```

`minimum_course_number` is the one optional field. Include it only when the
text limits the whole pool to courses from a number up, and cite that text.

What the check enforces is listed in catalog-normalization.md. These are the
rules that cost the most rework:

- **Quotes are exact.** A quote is a short, case-sensitive substring of the
  block it cites. Copy it from the `blocks` output, never retype it. Cite only
  blocks of the node's own entity.
- **Coverage is both ways.** Each block has exactly one coverage entry. Its
  `node_ids` are exactly the nodes that cite that block: every node listed
  cites the block, and every node citing it is listed. When you add a
  citation, update that block's coverage too.
- **Dispositions:** `requirements` and `unresolved` need nodes. `information`
  may list only `information` nodes, or none; a passage that requires
  something is never information.
- **Graphs:** a parent is a group (`all`, `any`, `choose_n`, `credits`,
  `grade`) of the same entity and phase. A `choose_n` has `unit: "courses"`
  and a whole-number minimum no greater than its children. A lecture and its
  lab offered as one option are an `all` inside the choice.
- **`credits`, `gpa` and `course_pool`** need a positive `minimum` in their
  own unit. A `course` names exactly one registry course. `class_standing`
  needs a comparison. `permission`, `restriction`, `unresolved`,
  `information` and `gpa` carry their full meaning in `value`.
- **Don't choose.** Two totals, or a count its courses don't add up to, stay
  two. Mark it `unresolved` and ask a question; never pick one.
- **Don't fill gaps.** A linked policy the capture lacks is a question, never
  text fetched live or recalled. Planning preferences (suggested terms,
  workloads) are not requirements.

A scratch script that assembles the JSON from a compact spec is fine, but keep
it in the scratchpad. The check below is the authority, not your script.

### 4. Check, and fix everything it lists

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R check \
  --reading institution/unm/catalog_interpretations/2026-2027/<program>.v<n>.json
```

It lists every problem at once, each naming its node, block or question, and
exits 1 while any remain. Repeat until it prints "ready to commit".

### 5. Triage every open item, and name the Gen Ed pools

The check's clean output lists the open items. Each is keyed `rule:<node id>`
(an `unresolved` rule), `passage:<block id>` (an unresolved passage with no
rule) or `question:<n>`, and is "Not sorted yet" until `triage` names it:

- `catalog`: the catalog contradicts itself, is unclear or names nothing.
- `capture`: the catalog says it somewhere CEDAR's copy didn't keep.
- `reading`: the catalog leaves a choice, and the reading planned it one way.

`gen_ed_pools` names each unlisted credit pool inside the tree that is a Gen
Ed area (`{"rule": "<node id>", "area": "VA"}`) or the remainder of the
University's requirements (`"area": ""`); the conventions file says which UNM
phrases are which. Run the check again after editing either.

### 6. A program with no hand-built board needs its catalog row

Add its row to `institution/<id>/degree_reading_catalogs.csv`: its names, its
degree code, and the Banner program codes of its students, decided against
`programs.csv`. No reading can supply the codes; the compile skips the
program without the row.

### 7. Stage and compile

```bash
Rscript --vanilla scripts/normalize-degree-catalog.R stage \
  --root "$CEDAR_DATA_DIR"/catalog-normalizations/unm \
  --drafts institution/unm/catalog_interpretations \
  --capture-root "$CEDAR_DATA_DIR"/catalog-scans/unm
Rscript --vanilla scripts/compile-degree-interpretations.R \
  --root "$CEDAR_DATA_DIR"/catalog-normalizations/unm --analysis "$A"/analysis-requisite-timing-1.4.0
```

Read the comparison before writing anything. Look for:
- tiles against the hand-built board, if there is one;
- requisites and conditions held for a reviewer;
- items still "Not sorted yet";
- the degree total against the record's Degree Hours.

The compile is where `gen_ed_pools`, the degree total and the catalog row are
checked. Known compiler gaps (ISSUES I68, I67, M81, M82) are not the reading's
to work around. When the comparison is right, run the same command with
`--write` to publish `institution/<id>/degree_drafts/`.

### 8. Test, and get the packet to production

- Run `./run-tests.sh`. When a board changed, also run
  `./run-tests.sh --e2e degree-explorer` against an app rebuilt with the
  change (the image bakes its source; for a worktree see
  [testing.md](../../../docs/developers/testing.md#testing-a-branch-in-a-git-worktree)), then open the board and
  look at it.
- The deploy stops when a committed reading's packet or captured pages are
  missing on the server (I101). Before the PR merges, get the user's go-ahead,
  then run `bash scripts/sync-catalog-store.sh --dry-run` and
  `bash scripts/sync-catalog-store.sh`. The sync only adds and updates files.

## Report

When you finish, report:
- the reading file and its version;
- the check's output line;
- the open items, by who can settle them;
- what the compile changed on the board;
- any convention you added to the institution's file.

Put a question for the department in Catalog questions, never in the PR alone.
