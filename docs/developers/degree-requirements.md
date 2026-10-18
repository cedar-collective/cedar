---
title: Degree Requirements and Observed Paths
parent: Developer Guide
nav_order: 31
---

# Degree requirements and observed paths

Read the [Degree Explorer rules](degree-explorer-rules.md) before changing the
feature. That file records the product decisions and prevents interface drift.

Institution files are registered in `CEDAR_CONFIG_FILE_SPECS` and validated
by `R/lists/degree_catalog.R` at startup:

| Table | Grain and purpose |
|---|---|
| `degree_catalogs.csv` | Snapshot: program name, degree label, year, source, retrieval date, coverage and caveats |
| `degree_rules.csv` | Rule node, parent, catalog, phase, common area, target course, operator, minimum, grade, review status and detail |
| `degree_rule_courses.csv` | One course per leaf rule, with catalog title and credits |
| `degree_roadmap_nodes.csv` | Authored planning slots, course/group labels, explicit lower/upper course level, credits, type, paired flag, source and `row_group` course-family alignment; `*` holds shared entry routes |
| `degree_roadmap_links.csv` | Selected prerequisite route edges, earlier vs earlier-or-concurrent timing, detail, source and evidence ID |
| `degree_roadmap_courses.csv` | Exact course components for concrete tiles; two rows for lecture/lab bundles, none for unresolved choices; no historical equivalences |
| `degree_roadmap_options.csv` | Finite OR sets: `option_id` groups required AND components within an alternative; minimum option count, course code/title, component credit range, individual course URL, program evidence and optional course-prerequisite evidence. Separate from selected bundle components |
| `degree_catalog_evidence.csv` | Exact excerpt, catalog year, program/course page, section path, retrieval date, transcription/review/conflict status and explanatory note |
| `degree_roadmap_basis.csv` | One program/node membership: degree, prerequisite preparation or illustrative general route, with a citation and explanation |
| `degree_roadmap_plans.csv` | Degree credit target, usual/maximum loads, baseline semesters, first upper-level semester, usual allowance-slot credits, Gen Ed source URL, target citation and workload assumption |
| `degree_roadmap_starts.csv` | Common math/English placement identifiers, English course routes and explicitly completed degree credits |
| `degree_roadmap_math_routes.csv` | One route per program/math placement identifier, with program-specific labels and ordered shared course IDs; no calculus fallback |
| `degree_roadmap_conditions.csv` | Course-count pools and permission conditions, target, minimum, eligible single-course slots, visible label and course-page evidence; separate from named-course edges |
| `pathway_subject_groups.csv` | One descriptive group per subject prefix, with consistent labels |

Degree tables are exposed as `CEDAR_DEGREE_CATALOG` (`catalogs`, `rules`,
`courses`, `evidence`); templates as `CEDAR_DEGREE_ROADMAPS`
(`nodes`, `links`, `starts`, `basis`, `plans`, `courses`);
categories as `CEDAR_PATHWAY_SUBJECT_GROUPS`. The synthetic institution
has empty catalog files rather than importing real university rules as synthetic
facts; its fixture courses still have descriptive groups.

## Rule semantics

`all` and `choose_n` preserve AND/OR trees. A two-course `all` child is one option
of its parent's `choose_n`. Course leaves distinguish `course`, `prior`,
`concurrent`, and `prior_or_concurrent`. `credits` records a threshold;
eligibility restrictions remain explicit until encoded. `condition` preserves
non-course rules without pretending they are executable. `none` is a known
absence; missing rows mean not encoded. Bad references, cycles, impossible
choices, missing leaf courses and duplicate grouping keys fail loudly.

Admission and degree rules share structure without merging their purposes.
Requisites have a target course and separate phase. No evaluator yet determines
student eligibility, admission or completion. Do not infer course equivalences
or impose the current catalog on historical students. A future evaluator needs
allocation constraints: one course may satisfy permitted overlapping rules,
while earned credit counts only once. Coverage and review must gate planning use.

## Semester planning

`build_degree_roadmap(catalog, roadmaps, catalog_id, math_start, english_start)`
selects one program plus its entry routes. `build_degree_roadmap_view()` adds
presentation text; `degree_semester_board()` (`R/modules/degree-explorer.R`)
renders the same payload as an HTML semester board. `www/cedar-roadmap.js` draws
connections and handles hover and focus; it makes no scheduling decisions and
does not walk the graph: `get_degree_chain_metrics()` exports each course's
`upstream_ids` and `downstream_ids`, and `qualifying_ids` names a course-count
condition's pool. `format_degree_explorer_preview()`
formats that production payload for analysts without Shiny.

After scheduling, `assign_degree_roadmap_rows(nodes)` adds a positive integer
`row` from the authored `row_group` family. Math and writing have reserved rows;
parallel courses occupy separate rows. Other families can share a row only
outside each other's complete semester span, preserving gaps within sequences.
This step changes neither course semesters nor workload. The view adds `n_rows`;
the renderer uses shared CSS grid tracks so each row grows to fit its tallest
tile across every semester. Browser code still only draws actual graph edges.

Nodes distinguish major, support, writing, preparation and course choice. Paired
lecture/lab coursework is a single node with combined credits. This avoids
misrepresenting same-term bundles as a prerequisite cycle. Each edge is one
selected valid prerequisite route, not the complete AND/OR rule tree. Missing
shared nodes are satisfied by the selected placement scenario. Biology currently
illustrates Calculus I rather than its alternative Applications of Calculus.

Finite alternative sets live in `degree_roadmap_options.csv`, not the component
table. All five Philosophy sets are transcribed completely. Their nodes are
unresolved choices, with the minimum/count and a three-line course-code preview;
the popup lists every title, credit range, level and course URL. The program
evidence must match the node's basis. Optional prerequisite evidence must match
that individual course page and catalog year. Selected-course edges/conditions
on an unresolved set are rejected. Logic reserves three credits for a lower-level
choice and explicitly identifies the higher-level, variable-credit alternative.
Offering history for a finite set uses its options separately in the standard
table; it never aggregates their seats as a required bundle.

Rows sharing `(catalog_id, node_id, option_id)` form one complete alternative.
Validation sums component credit ranges before checking the planning allowance;
option counts count groups, not rows. The feature supplies typed option groups
for compact card previews and grouped popup lists, while history retains exact
individual course identifiers. `requirement_summary` on a node is authored
institution text for a shared block's total/rules, distinct from slot credits.
CS's science block has two four-credit lecture/lab slots and two three-credit
science slots. The first two enumerate eleven complete alternatives (nineteen
individual lecture, lab and combined-course entries); the other two list the
eleven lecture/combined courses. Higher-credit choices and the catalog's open
advanced-science alternatives need review. No selection, distinct-course audit,
or new generic prerequisite sequence is implied.

A topological scheduler respects authored minimum semesters, strictly earlier
and earlier-or-same edges, and the institution plan's maximum load (16 at UNM).
Upper-level nodes also respect `upper_level_from_semester` (5 in the pilot).
Course groups have authored levels; concrete components must agree with the
institution's leading-digit bands. Never infer a group's level from its display
label. Earliest eligible planning slots win ties, then file order. This later
upper-level stage is a user-requested planning preference, not catalog evidence.
The full workload is the
planning degree-credit target minus explicitly completed starting credits,
plus preparation; this additional-work assumption
is explicit, not an assertion that all preparation is ineligible for degree
credit. Other work is the target minus shown non-preparation courses. The
horizon grows to fit the workload and all scheduled courses. Other work fills
toward the usual load (15), then uses the allowed maximum for the remainder.
Semester totals include both named courses and other work. The latter remains
an unaudited allowance until course allocation/overlap is implemented.

`build_degree_allowance_slots()` splits early allowances into course-sized grid
tiles, using the plan's `allowance_slot_credits` and preserving the exact budget.
A usual slot can absorb one extra credit; smaller remainders remain explicit.
It fills available rows without disturbing math/writing rows or interior course
family spans. Later upper-level/minor allowances remain below the grid. The view
returns these tiles separately in `allowances`, never as catalog graph nodes.
`start_season` defaults to fall and alternates fall/spring labels, with a selector
and shared-URL field. It affects example offerings, not prerequisite scheduling.

`build_degree_popup_history()` dispatches ordinary course cards to existing
history and validates allowance clicks against the current plan. Suggestions
use CEDAR's Gen Ed membership, excluding fixed/entry courses and finite option
pools already represented in the program. `get_gen_ed_planning_options()` reads
the explicitly supplied guarded history and section metadata; it never calls
another cone. It selects lower-level, non-topic, course-sized options and the
latest matching-season row at each course/delivery-campus/college/session.
Frequency denominators use source-covered terms only. Rows sort by frequency,
then first-day enrollment; missing dates and suppressed counts stay unknown.
Credit fit is an allowance comparison, not enrollment eligibility. The canonical
`format_degree_allowance_preview()` prints the same aggregate payload for review.
These are general historical examples, not a Gen Ed audit or curated advice for
a major. Future major-specific Markdown guidance remains a separate extension.
`terms$other_phase` distinguishes early foundation allowances from later advanced
work. The feature labels early slots Gen Ed / lower-level electives and later
slots upper-level / minor / electives. This prioritizes Gen Ed in years 1–2
without inventing an audited Gen Ed credit requirement or claiming every later
elective earns upper-division credit.

Template positions and elective-group placements are planning suggestions.
Course-specific options, offerings, admission, transfers, equivalences and the
complete degree allocation are not evaluated. A missing edge does not assert
that a course has no restrictions. Link/source validation rejects bad endpoints,
cycles and unknown starting routes. The requirement tree and selected planning
route are separate contracts; neither should silently update the other.

Degree planning uses metadata and redraws automatically. Its shared URL spec
restores `catalog_id`, `math_start` and `english_start`; it has no run button.

## Course popup and history

Hover and keyboard focus preview named upstream/downstream chains and their
course labels locally, without a history request. The floating preview is
hoverable, dismisses with Escape and restores the last clicked chain on leave.
Count conditions and unresolved alternatives retain their distinct semantics.
Course clicks open the standard CEDAR modal (`cedar_info_modal(scrollable = TRUE)`),
rendered by the server from `degree_roadmap_tile_detail(view, node_id)`: catalog
links at the top, enrollment history first and complete requirement evidence
below. Escape or either close control returns focus to the tile without
scrolling the page. Semester headers use identical fixed tracks.

`get_course_planning_history(sections, students, subject_courses, edges)` returns
`pressure` at course/campus/college/part-term/term grain, plus `terms`, seasonal
`frequency`, a complete-window `offerings` table, source `coverage`, missing exact codes and a window note. This is
an all-course computation, not Regstats' already-flagged subset. It reuses
`get_enrl()`, `filter_classlist_to_sections()`, `calc_first_day_enrl(..., by_part_term = TRUE)` and
`enrollment_capacity_metrics()`. Frequency uses all source-covered campus terms
in the last nine possible terms through `last_enrolled_complete`. Missing source
terms are excluded, never invented as non-offerings. Median seats sum sessions
within an offered term; partial capacity leaves the total unknown.

Pressure uses reconstructed first-class-day enrollment and DESR scheduled capacity at matching
campus/college/course/session/term grain. A term is near full if any session
reaches 90%; seasonal pressure denominators require every session to be matched,
plausible (fill at most 125%) and at least 10 first-day students. Missing matches
are unknown, not zero enrollment; small counts and reconstructable percentages
are suppressed. This describes potential planning pressure, not proven unmet
demand, a frozen first-day roster or future course availability. Missing status,
section-start or pull dates withhold the whole group's first-day count. Banner's
current-status-only dates can overcount late additions that later dropped.

`build_degree_course_history()` resolves explicit course components and assembles
one typed table. `degree_history_table()` uses the shared Reactable theme,
`cedar_count_coldef()` / `cedar_percent_coldef()`, course/campus filters and
`cedar_pot_coldef()`. Source-covered absence is Not offered (zero scheduled
seats); missing coverage stays unknown.
`degree_course_history_ui(history, table_id)` provides the table output slot
and explanation; the module renders `course_history_table` separately.
Unresolved course groups and new identifiers show explicit missing states.
History is lazy and cached per clicked program/node in the Shiny session.
Source tables, edges and catalog metadata are immutable session arguments, so
placement changes need no history recomputation; a new session gets fresh data.

## Catalog evidence and graph metrics

`attach_degree_roadmap_evidence(nodes, roadmaps, catalog, catalog_id)` resolves a
tile's actual reason for appearing. Degree membership must cite that program's
page; a course page may establish preparation but cannot substitute as degree
proof. Every selected edge has a course prerequisite citation. Unknown IDs,
missing tile membership, mismatched pages/types/years and malformed citations
fail at startup. The source bar shows the exact saved excerpt and section link,
plus separate program and course links. General English routes not explicitly
named by Biology remain marked illustrative.

`get_degree_chain_metrics(nodes, links, conditions = NULL)` computes unique direct/indirect named ancestor
counts, strict prerequisite depth, downstream reach and the longest sequence
through a node. Before-or-concurrent edges carry zero additional earlier-term
lag. Converging branches count ancestors once; paired lecture/lab nodes contribute
two courses without adding a sequential term. Colors use ancestor counts (0,
1–2, 3+); unselected course groups with unknown prerequisites remain gray.
Metrics concern the selected route after placement, not every catalog
alternative or a student's eligibility. Renderers consume them without
recomputing graph rules.

Course-count and permission conditions live in their own file. The scheduler
waits for enough eligible single-course slots to be scheduled, then places the
target after the earliest qualifying completions. It never turns the whole pool
into AND edges. The source must be the target course page. Conditions do not add
named ancestors or named-chain depth; purple diamond labels display them and
dotted outlines highlight qualifying options without arrows. Gen Ed suggestions
derive from `basis = general`, with a visible label, light surface and dashed border.

One active catalog year is loaded. The text files are a reviewable annual graph
snapshot, with catalog-year IDs and evidence; Git preserves previous sets.
Live catalog hash URLs alone do not freeze an edition. The saved year, excerpt,
retrieval date and review status record what was transcribed. Update the set as
one reviewed annual change, retaining conflicts and checking degree/course
pages independently. No live scraping or automatic inference runs in Shiny.

## Observed analysis

`build_population_course_paths(students, population, groups, opt, description)`
uses the already defined Pathways population and calls
`get_grouped_student_paths(students, population, groups, opt)`.
`observedCoursePathsUI/Server()` is mounted at Pathways > Course paths.
The root passes edges and grouping metadata explicitly through `pathwaysServer`;
its UI receives delivery-campus choices separately from home-campus choices.
Changing the population invalidates the old result.

The cone enforces `relevant_until`, numbers full undergraduate participation
history, then filters delivery campus and enrolled-term count. Registered and
late-drop rows count. No grades or frozen cumulative credits are read. Course
deduplication retains student, term, enrolled term, campus and course. Group cells
and denominators retain campus and enrolled term; course detail also keeps course.

Numerator: distinct participants in any course of the group. Denominator:
population students participating in any course at that delivery campus and
enrolled term. Multiple groups can coexist, so shares need not sum to 100%.
Band/cell guards default to 20/10. Suppressed counts become NA before the module
sees them; known zeros stay zero only when the band is large enough. Course
detail is filtered before returning. Unknown prefixes retain an unmapped group.

Term one is first observed study, not necessarily career entry. Left-boundary
counts are disclosed. This is marginal course-mix timing, not individual paths
or a graph of course-requisite or causal transitions. Subject categories are
independent of credential requirements.

## Forecast integration boundary

A future opportunity model should use reviewed rules to identify potentially
needed coursework; observed histories estimate whether/when enrollment occurs.
Do not sum alternatives as independent demand or use descriptive groups as
eligibility rules. Resolve catalog version, transfer/waivers, equivalences,
unresolved rules and overlap allocation before introducing a requirement-informed
challenger in rolling aftcasts. Capacity remains an audit, never a predictor.

Regression tests extend `test-pathways-helpers.R`; the standard
`degree-explorer` browser suite covers placement changes, dependency shifts,
paired courses, complete semester budgets, source evidence, planning colors,
mobile scrolling, URL restoration and the moved observed view.
