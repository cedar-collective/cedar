---
title: Degree Explorer Rules
parent: Developer Guide
nav_order: 32
---

# Degree Explorer rules

Read this file before changing Degree Explorer, its curriculum files, or its
planner. These product rules record decisions made with the user; they are not
optional styling suggestions. The data/API contract is in
[degree-requirements.md](degree-requirements.md).

## What students should see

- Show one degree as a semester board. Use the same interface for every program.
- Ask for math and English starting points and show their actual preparation
  courses. Changes redraw the course sequence immediately.
- Resolve math entry routes per program. A placement choice must not impose
  calculus on a major that only needs general math/statistics. Preserve the
  placement identifier when changing degrees; update the route and labels.
  Distinguish a named major math requirement from an illustrative Gen Ed choice.
- Keep courses and course groups visible. Do not replace the board with a set
  of accordions or a requirements table.
- A named alternative set must show **Choose N of X courses** and its course
  codes on the chart. Show every member when it fits; clamp a long list to three
  lines with a visible ellipsis, retaining the total count. The popup always
  shows the complete list, full titles, credits and individual catalog links.
  Never show one example course as though the program requires that course.
- Keep each course code intact when wrapping a preview. Break between options,
  rather than separating a subject prefix from its number to squeeze in a list.
- Store OR alternatives separately from the AND components of a lecture/lab
  bundle. Unresolved choices remain gray with prerequisites that vary. A single
  option's prerequisites, conditions or offering history cannot describe the
  entire set. Known option-specific prerequisites stay beside that option.
- For a shared credit block, show its total and lab/pairing rule on every slot,
  distinct from that slot's planned credits. Keep a compact, clamped option
  preview on the card and the full options in the popup. Group lecture/lab AND
  components under one OR option; a standalone one-credit lab is not a complete
  science-course choice. Combined lecture/lab courses remain one option.
- The CS science example reserves **4 + 4 + 3 + 3 = 14 credits**, with labs in
  the first two slots. These are unresolved choices, not a selected sequence.
  Its eleven introductory lecture/combined choices and eight separate labs are
  enumerated; advanced-science alternatives remain visibly open for review.
  Do not imply a lab-free fifth course satisfies the required lab pairings, or
  that the same course can fill multiple slots. Higher-credit choices require
  workload review; the prototype does not yet select or audit combinations.
- Disclose variable credits and mixed course levels. A planning allowance must
  say how many credits it reserves; selecting an upper-level or higher-credit
  alternative needs its timing and workload reviewed.
- Hovering or keyboard-focusing a course previews both its prerequisite /
  corequisite chain and courses that depend on it, with a readable preview and
  matching chart connections. Blue leads in; purple leads out. These are the
  named courses in the selected route, not every catalog alternative.
- Hover is local presentation only: it must never open the enrollment dialog,
  request history, or change the clicked course's data. Leaving clears the
  temporary preview or restores the last clicked chain; an active keyboard
  focus keeps its own preview. Keep the preview
  readable when moving into it, and let Escape dismiss it.
- Coursework-count / permission conditions retain their diamond label and
  dotted qualifying pool on hover. Course sets say prerequisites depend on the
  selection; do not turn those conditions or alternatives into named edges.
- Clicking (or pressing Enter/Space) opens a dismissible, keyboard-accessible
  popup with **enrollment and first-day seats first**. Catalog links stay at the
  top; complete requirement evidence, conditions and course-set details remain
  in the same popup below the history. Each opening starts at enrollment history,
  even after scrolling. Closing returns focus to the clicked tile. Touch users
  can open the popup directly without a hover step.
- Every semester header has identical height, including wrapped year/term labels
  and plans longer than eight semesters. First tile rows start at the same height.
- Keep Gen Ed, minor and other degree work secondary, but include its workload.
- Early Gen Ed / lower-level allowances are course-sized, clickable tiles in the
  same grid as named courses. Split their existing budget using the institution
  plan's usual slot credits; preserve small remainders explicitly as credits
  left to allocate. Never round up, drop credits, or imply that a one-/two-credit
  remainder is a complete course. Show actual suggested course credits and
  whether they fit the allowance; changing the plan still needs review.
- Ask whether the first semester is fall or spring, label every term accordingly,
  and preserve that choice in shared URLs and degree switches. Season labels
  select historical examples; they do not change prerequisite scheduling or
  guarantee that named courses will be offered then.
- Allowance popups show recent matching-season Gen Ed examples with titles,
  course credits, delivery campus/college/session, last offered term, seats and
  first-day enrollments. Use CEDAR's institution Gen Ed list and exclude entry
  routes, fixed requirements and enumerated choice pools already represented in
  the program. These are unreviewed examples, not an audit of remaining Gen Ed
  areas or recommendations tailored to a major. Future major-specific Markdown
  guidance may augment suggestions, separately from catalog requirement truth.
- Hovering an allowance explains that no course is selected. Do not invent
  prerequisite arrows, a green zero-prerequisite rating, or a catalog excerpt
  for a planning allowance. Its popup links to the current Gen Ed course list.
- Put observed student coursework at **Pathways > Course paths**, using the
  shared Pathways population. Never present observed order as a prerequisite.

## Spatial layout

- Align related courses horizontally across semesters. ENGL 1110 → ENGL 1120
  and the stretch English route each stay in one row; algebra through calculus
  also stays aligned. Apply the same technique to program sequences and course
  groups, such as History surveys, accounting and physics sequences.
- Author course-family membership as `row_group` in the institution node file.
  Never infer it from display labels or invent prerequisites to force alignment.
  Row membership means related coursework; only catalog-backed arrows establish
  prerequisite timing. Suggestions keep their distinct styling in every row.
- Assign rows after scheduling. Layout must never move a course to another
  semester, change its credits, or override the 15/16-credit workload policy.
- Reserve math and writing rows. Preserve empty positions within a sequence
  rather than pulling other courses upward. Other families may share a row
  outside each other's full semester span to keep the board compact.
- Concurrent courses in a family use separate rows. Never overlap, omit, or
  move a course to make a family fit on one row.
- Share row heights across all semester columns, sized to their tallest tile.
  Wrapped titles and condition badges must stay readable. Keep semester headers
  equal in height. Place early allowance tiles in free grid slots, preserving
  math/writing rows and interior gaps in every course family. Later upper-level,
  minor and elective allowances remain below the aligned rows.
- Check actual rendered alignment for ordinary and extended plans, alternate
  math/English placements, and narrow screens. An assigned row number alone
  does not prove visual alignment.

## Workload and timing

- The UNM planning policy is **15 credits usual; 16 credits maximum per
  semester**, including other degree work. The institution plan file supplies
  those values; no alternate limit is hidden in a renderer.
- Extend the plan when needed. Eight semesters is a template, never a constraint
  that justifies overloading a term, dropping coursework or hiding preparation.
- Size the horizon to the whole workload and prerequisite schedule. Fill other
  requirement allowances toward the usual load first; use the allowed maximum
  for the remainder within that horizon. Display total planned credits per term.
- Prioritize Gen Ed and lower-level foundations in the first two years. Schedule
  upper-level requirements from semester 5 onward, including upper-level course
  groups. The plan file supplies this boundary so programs use the same rule.
  Later-semester allowances identify upper-level, minor and elective work rather
  than implying Gen Ed is still unfinished. These are planning allowances, not
  audited Gen Ed or upper-division credit totals.
- This timing pattern is a planning preference, not a catalog restriction or a
  new prerequisite. Preserve the actual prerequisite chain and credit limit;
  extend the plan if later placement or required sequences need more semesters.
- Keep strict prerequisites earlier. Preserve before-or-concurrent timing and
  keep paired lecture/lab bundles together. Never invent prerequisite edges to
  explain an authored semester position.
- Store course-count and permission conditions separately from named-course
  edges. A requirement such as two prior upper-level courses can be satisfied by
  different members of a pool. Schedule enough qualifying slots earlier without
  claiming that two particular electives, or every pool member, are required.
- The current scenario adds preparation to its degree-credit target. Say so.
  This is a conservative planning assumption, not a blanket finding that every
  preparatory course is ineligible for degree credit. Reviewed overlap,
  substitutions and transfer credit can reduce it. CS's explicit exclusion of
  mathematics before calculus is recorded as catalog evidence.
- Explicitly completed starting courses reduce the remaining degree credit
  target. Placement or a waiver alone does not award course credit.
- Credit targets must cite their source. Conflicting totals remain visibly
  unresolved; do not quietly pick a new official total. Biology currently uses
  the Degree Hours field for the example and retains the conflicting grand total.
- Admission, specific elective prerequisites, course offerings, transfer and
  full allocation remain unresolved until encoded. Never call the prototype a
  validated graduation plan or imply a student is eligible to enroll.

## Planning colors and chains

- Color means prerequisite planning on the **selected route**, not difficulty,
  failure, student readiness, or an eligibility decision.
- Green: zero shown prerequisite courses. Yellow: one or two. Red: three or
  more. Count unique direct **and indirect** prerequisite courses. Do not count
  the same ancestor twice when branches converge. A lecture/lab pair represents
  two courses even though it occupies one tile.
- A choice with unencoded course prerequisites is gray, never green by default.
- Show aggregate coursework/permission conditions with a purple diamond badge
  and their actual wording. They do not increase the named prerequisite count.
  Selecting the course highlights qualifying options with a dotted outline,
  without drawing named-course arrows from those options.
- Mark illustrative Gen Ed courses on the chart as **Suggested Gen Ed**, with
  a lighter surface and dashed border. Keep text fully readable; do not fade the
  whole tile. A named program requirement keeps its solid program styling even
  when the same course is a suggestion in another program.
- Placement removes satisfied preparation from the scenario; explain that these
  counts concern the displayed route, not every alternative in the catalog.
- Show numbers and text alongside color. Every tile shows prerequisite burden
  and downstream reach. Entry courses clearly identify a chain they start.
- Keep chain length separate from ancestor count. Parallel prerequisites are
  not sequential semesters; concurrent links do not add an earlier semester.
- Selecting a course emphasizes both its upstream and downstream connections.
  Never flatten parallel branches into a misleading single ordered list.

## Evidence and annual updates

- The catalog is the authority. Program pages establish degree requirements;
  course pages establish prerequisites/corequisites. A course description alone
  does not establish that the degree requires it.
- Cross-check against degrees.unm.edu, recording the academic year and any
  differences. Use it as a secondary comparison; an older roadmap cannot
  overwrite the active catalog. Course descriptions remain linked to the
  individual current catalog pages. Do not assume how another site obtains them.
- Each catalog-backed course/group tile has a reason, source page, section path, short exact excerpt,
  catalog year, retrieval date and review status. Each graph edge has evidence.
  Keep copied text separate from explanations and planning assumptions.
- Show both **Degree requirements** and **Course description** links. The
  selected tile's evidence must reference the actual requirement or prerequisite
  section, rather than relying on a generic catalog link.
- A general requirement not fully encoded says it is illustrative. Source
  conflicts and missing coverage are visible; neither means “not required.”
- Name the selected concentration or example route. A general-major option
  explicitly permitted in program text may be shown with the conflicting
  concentration flag preserved in the source notes. Never silently treat one
  concentration's courses as requirements for every version of the degree.
- Store the graph as readable institution text files: nodes, selected-route
  edges, entry routes, program membership, evidence and planning policy.
  IDs refer to the active catalog year. One active year is served; preserve
  previous sets in Git rather than mixing editions or overwriting their history.
- Review the set annually as one change: obtain the new program/course pages,
  compare requirements and alternatives, save new excerpts and retrieval dates,
  review links and credits, then run validation and planner/browser checks.
  Changing a year/date alone is not an annual review.
- Live hash URLs can change with the catalog. The saved year and excerpt record
  what the graph was built from; a URL alone is insufficient provenance.
- `transcribed` means saved from the source, not approved by an academic advisor.
  Preserve `conflict` until resolved. Human-reviewed rules may be marked
  `reviewed`; never infer that status from successful code tests.

## Historical availability and pressure

- Course popups enrich the plan with descriptive history; history does not move
  courses or establish prerequisites or future availability.
- Use exact course components from `degree_roadmap_courses.csv`. Show lecture
  and lab separately. Unresolved choices need a specific course; do not infer
  equivalences between current identifiers and older course numbers.
- For an enumerated alternative set, the single history table may show all
  options, labelled as alternatives and kept separate by course. Never add
  their seats or enrollments together as if every option were required.
- Use one standard CEDAR Reactable in each popup, with course/campus filters and
  explicit term, component, campus, college and PoT columns. Keep lecture/lab
  components separate; do not require switching between little tables.
- Show the last nine possible terms through settled enrollment, with seasonal
  offering counts and typical scheduled seats. A frequency denominator includes
  all source-covered terms at that campus, including non-offerings. Missing
  source terms are unknown. No source-covered summer is not a summer zero.
- The primary line is **seats offered → filled at first class day → first-day
  fill percentage**, followed by pressure/coverage and seasonal frequency.
  Reuse `calc_first_day_enrl(..., by_part_term = TRUE)` and the common numeric
  capacity helper. No census, ever-registered, or DESR enrollment substitution.
  Missing status/start/pull dates yield unavailable first-day counts.
- Near full means at least 90% first-day fill. Count a term as near full when
  any session is near full; do not dilute it with another session's spare seats.
- Only fully matched terms with plausible capacity and cells of at least 10
  enter seasonal pressure counts. Missing matches, small cells and fill above
  125% are unscored. Say how pressure and frequency denominators differ.
- State the observation window and source limitations. Historical near-full
  offerings suggest planning pressure; they do not prove unmet demand or
  guarantee future schedules or available seats.
- Identify the first-day measure as a reconstruction. Banner keeps only the
  current status date, so late additions later dropped may be counted on day
  one. Show source-covered non-offerings separately from missing campus terms.
- Gen Ed suggestion tables reuse the same guarded first-day history. Show the
  latest matching-season offering at each course/campus/college/session, ordered
  by offering frequency then first-day enrollment. Count only source-covered
  terms in frequency denominators. Course credits/titles come from retained
  section metadata and do not establish current catalog eligibility.

## Implementation boundaries

Scheduling, row assignment, graph metrics and evidence resolution belong in branches. Features
assemble display payloads. Modules and browser code render those payloads and
handle interaction. They do not infer requirements, schedule courses or count
prerequisites independently. Planning itself uses metadata only; optional
offering-history enrichment reads section and class-list data through an
explicit cone. Individual student rows never enter the browser.

Regression checks must cover the complete 16-credit budget, semester extension,
all starting routes, converging chains, concurrent timing, source type/year
mismatches, and program-versus-course citations. Inspect the rendered board after
layout or color changes.
