# Active degree catalog set: 2026–2027

The current pilot was transcribed from the **UNM 2026–2027 Catalog**, retrieved
2026-10-17. It uses these program pages:

- [Computer Science B.S.](https://catalog.unm.edu/#/programs/HJZpXxQ9s9)
- [Biology B.S.](https://catalog.unm.edu/#/programs/SygaQl75o5)
- [History B.A.](https://catalog.unm.edu/#/programs/HkzhQeX5iq) — U.S. survey example.
- [Philosophy B.A.](https://catalog.unm.edu/#/programs/SkWn7eQ9o9) — general major with five complete named alternative sets.
- [Business Administration B.B.A.](https://catalog.unm.edu/#/programs/HJlTXxQcic) — common core and stated General Management elective option.
- [Anthropology B.A.](https://catalog.unm.edu/#/programs/ryjXxmqs5) — general major with full Archaeology and Sociocultural/Linguistic core sequences.
- [Physics B.S.](https://catalog.unm.edu/#/programs/BJf67xXqoq) — General Physics concentration.

`degree_catalog_evidence.csv` records exact short excerpts, section locations,
source URLs, year, retrieval date and review status. Program pages establish
membership in a degree. Course pages establish the selected prerequisite and
concurrent routes. `degree_roadmap_basis.csv` connects each program/tile to that
proof; `degree_roadmap_links.csv` connects every edge to its evidence ID.
`degree_roadmap_conditions.csv` separately records count/permission conditions.
HIST 491 needs any two upper-level History courses plus departmental permission;
this is not an edge from two particular electives. `degree_roadmap_options.csv`
records Philosophy’s five complete alternative sets separately from required
course components. PHIL 358’s prior-course condition and PHIL 352’s PHIL 2210
prerequisite belong to those individual options, not their entire sets. Logic
reserves three credits; PHIL 356 is an upper-level, variable-credit alternative.

The CS Science courses section was checked again on 2026-10-17. It lists eleven
lecture/combined courses and eight separate labs, with a 14-credit minimum and
two lectures paired with their labs. Graduation Requirements item 7 also calls
for four science courses of at least three credits each. The template reserves
two four-credit lab-science slots and two three-credit science slots. Option IDs
keep each lecture and matching lab together as one alternative; combined courses
are single-component alternatives. The entire introductory pool is recorded,
but the section also permits advanced work in the sequence discipline. Those
advanced alternatives, distinct selections and individual prerequisite routes
are not yet audited. Higher-credit choices need workload review.

Cross-check on 2026-10-17: [the Philosophy roadmap](https://degrees.unm.edu/units/5024/periods/124/plans)
shows the same five alternative sets, with course descriptions in its popup.
It identifies its academic year as **2025–2026**, so it is secondary to this
2026–2027 catalog snapshot. Its description text for PHIL 333 matches the
current catalog; the method by which the site obtains descriptions is unverified.

`degree_roadmap_nodes.csv` stores courses, groups, credits and **authored semester
positions**. Those positions are CEDAR planning suggestions, not claims that the
catalog publishes this semester arrangement. Its `row_group` values also author
visual course families: related courses align horizontally after scheduling.
These families do not create requirements or prerequisite links. `degree_roadmap_starts.csv` stores
common placement identifiers, English routes, and explicitly completed credits
kept separate from placement. `degree_roadmap_math_routes.csv` selects the math
sequence per program and placement. CS/Biology/Physics use calculus; Business
uses required MATH 1350. History/Philosophy/Anthropology use MATH 1350 as an
illustrative Gen Ed choice, explicitly marked as such. Their intermediate entry
adds MATH 1215 only. Each program's basis must cover exactly its own nodes and
the shared nodes reachable from its entry routes, rather than every shared node.
`degree_roadmap_plans.csv` stores
the 120-credit planning targets and 15-usual/16-maximum workload policy.
Its `upper_level_from_semester = 5` is a planning preference requested for the
prototype: Gen Ed and foundations first, upper-level work later. It is not a
catalog timing restriction. Nodes explicitly identify lower/upper level;
concrete components are checked against `course_levels.csv` and choice groups
are authored rather than inferred from labels.
`degree_roadmap_courses.csv` explicitly identifies each concrete tile’s course
components for historical offering lookup. Lecture and lab are separate rows;
unresolved choices have none. It does not map renamed courses to older numbers.

The formal AND/OR requirement excerpts remain in `degree_rules.csv` and
`degree_rule_courses.csv`. The roadmap graph selects example routes; it does not
evaluate all alternatives or certify graduation. `pathway_subject_groups.csv`
serves descriptive observed student coursework, separately from degree rules.

Known limits remain explicit: Biology's Degree Hours field says 120 while its
grand total says 122–127, and its breadth wording conflicts. Its English route
is illustrative general education, not an explicit Biology course list. Current
CS admissions refer to legacy course identifiers; their equivalence to the new
CSCI identifiers has not been established. Specific elective/science choices,
admission eligibility, transfer and full allocation still need review.

Additional source limits: Business lists eleven 3-credit core courses (33) but
calls the core 31 credits; the concentration/free-elective heading says 44 and
its embedded prose says 41. Its General Management option conflicts with the
Concentration Required flag, as does Anthropology's explicit general-major option.
Anthropology's selected combination has 37 major credits against the 36-credit
minimum and 21 upper-division credits against the 18-credit minimum. Physics's
General Physics concentration is 21 credits in the structured requirements but
18 in the graduation prose; the example uses the explicit 21-credit selection.
All remain unresolved in plan assumptions. BBA's BCIS 1110 needs a completed
listed math course; placement alone is not confirmed to satisfy it.

This is one active annual graph set. Preserve its history in Git when reviewing
next year's set. Do not merely replace the year on old text. Recheck both program
and course pages, compare rule/edge/credit changes, save evidence, and validate
as one change. A live URL may later show a different edition; the saved excerpt
and year identify the transcribed fact. `transcribed` is not academic-advisor
approval. See [Degree Explorer rules](../../docs/developers/degree-explorer-rules.md).
