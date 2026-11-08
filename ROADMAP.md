# CEDAR Roadmap

What CEDAR should do next: **strategy, new functionality, enhancements and
significant upgrades**. Defects and improvements to what already exists live
in [`ISSUES.md`](ISSUES.md). The test for which file: if someone could write
"done when…" against existing code today, it is an issue; if it needs design
or a decision about something new, it is here.

Each item is one line, `- [ ] **Name.** What and why, in a sentence or two`,
linking an issue or design page rather than restating it. A shipped item is
deleted: what was built lives in the code, the changelog and git, and each
theme's first line says what exists. New ideas go in the [Inbox](#inbox) until
someone gives them a theme.

---

## Strategy

CEDAR is a transparent, reproducible analytics platform for higher-ed
curriculum, enrollment and student experience. Its promise is not that every
number is simple; it is that every number is explainable. It should keep
moving toward:

- **Trustworthy numbers:** scope, counting rules and caveats visible beside
  the table or plot, with the arithmetic one click away.
- **Attention over reporting:** answer "where should I look?" rather than only
  what a user already knew to ask.
- **Reusable analysis:** logic in branches, cones and features; measure tables
  a new cone filters and joins instead of re-deriving.
- **Installable structure:** an adopter edits the files under
  `institution/<id>/`, never code.
- **Focused surfaces:** the Shiny app is the product; RStudio analysis is
  supported through the same tables and functions.

Supported surfaces: Dept Dashboard, Dept Trends, Pathways, Course Dynamics;
Regstats, Open Seats, Waitlists, Projections (Registration); Enrollment,
Headcount, Gen Ed, Degree Explorer (Explore); Cancellations, Data & Usage,
Changelog (Admin). Cross-course Retention is built but hidden.

---

## Now

The order work is taken in.

1. **Finish the domain data model (ADR-001 step 4, then 5).** Rebuild the
   course flows on the keyed tables; then thin `cedar_students` and `cedar_programs` (closes
   [I47](ISSUES.md)). Design: [ADR-001](docs/developers/architecture-decisions.md#adr-001-move-cedars-tables-from-report-shaped-to-domain-shaped).
2. **Projection adjustments.** The open items under [Section-needs
   projections](#section-needs-projections).
3. **Degree maps.** The open items under [Degree Explorer](#degree-explorer-and-curriculum-informed-demand).

**Decisions waiting on a person:** the 37 renumberings still proposed in
`institution/unm/code_history.csv` ([I37](ISSUES.md)); decide the largest
programs and subjects still proposed (Admin → Data & Usage → Mappings,
`scripts/mapping-review.R`).

---

## Section-needs projections

Built: a monitored course registry, the prior same-season spine and an
adjusted challenger, rolling out-of-sample selection, three evidence axes,
first-day capacity judgement, section plans from projected registrations with
a pressure bump and feeder adjustment, a draft-schedule comparison, growth
scenarios, and saved bundles per season with model provenance. Contract:
[enrollment-projections.md](docs/developers/enrollment-projections.md);
what was tried and rejected: [forecasting-lessons.md](docs/developers/forecasting-lessons.md).
Waitlists are not an input until two years of retained waitlists exist.

- [ ] **Projections on Course Dynamics.** Reuse the saved payload on the course page.
- [ ] **Pilot with chairs and associate deans.** The table and its explanations.
- [ ] **Structural Fall model.** Split continuing students from the incoming
  cohort; blocked on retained admissions/acceptance/NSO snapshots CEDAR does
  not archive.
- [ ] **Scenario extensions.** Several populations at once, a rate per
  population, and a population's share of a course over time.
- [ ] **December revision.** Re-read the Fall deltas with posted grades
  (completions and DFW in place of enrollments) as a revision for add/cancel
  decisions.
- [ ] **Revise Spring by pace.** This week's registrations against the same
  week a year earlier, once a year of registration snapshots exists, scored
  rolling against the spine.
- [ ] **Project against the submitted draft.** "With these seats, expect
  this": most aftcast error moves with the seats. Needs the submission date
  marked in the snapshots.
- [ ] **Rank feeders by lift,** not raw count, so a chair's feeder list names
  prerequisites, not the largest freshman courses; review
  `projection_sequences.csv` yearly.
- [ ] **Record policy changes** (placement cutoffs, redesigned sequences) under
  `institution/<id>/` as labelled adjustments, scored afterwards.
- [ ] **Carry a waitlist forward and measure the pressure bump** once two
  years of retained waitlists exist (27% of Summer 2026's unserved students
  took the course in Fall 2026).
- [ ] **One course-history spine** shared by projections and low-enrollment alerts.

Any new candidate enters only as a challenger scored rolling against the spine.

## Attention dashboards

Regstats is the model: it scans for bumps, dips, saturation and waitlist
pressure rather than displaying tables. Each dashboard opens with a few ranked
signals, a sentence each, and links into the evidence, aimed at its audience
(chairs: what needs attention now; associate deans: what is changing
unusually; provost: cross-college patterns and risks).

- [ ] **Choose the tabs** that get one: likely DFW, Enrollment Trends,
  Headcount Trends and Gen Ed.

## Retention signals while there is time to act

Built: next-term registration of last term's students kept at every refresh
(`return-*` snapshots). Measured: of Fall 2025's undergraduates, the 6,751 who
withdrew late, failed a course or were on probation returned at 78% against
93% and were 63% of the loss; a third had not registered on Dec 1. The
measure is pace against the same day a year earlier, always aggregate.

- [ ] **Return watch** on the Dept Dashboard and UNM-wide: continuing students
  not yet registered against the same day a year earlier, by classification,
  standing and warning sign. Exact from Fall 2027.
- [ ] **Roadblocks on the Dept Dashboard,** ranked by Impact (`get_stopout()`).
- [ ] **Unhide cross-course Retention** once it sets each course against its
  department and college.
- [ ] **Near-completers and stalled pre-majors** as outreach counts.

## Degree Explorer and curriculum-informed demand

Built: an illustrative semester board for about two dozen programs from the
2026–27 catalog, with math/English starting points, prerequisite links,
15/16-credit budgeting, annual shared University/Gen Ed/college rules, course
popups with seats and first-day pressure, Pathways > Course paths, the offline
catalog scanner, Admin Catalog Review, and reviewed AI-assisted draft
interpretations. Rules: [degree-explorer-rules.md](docs/developers/degree-explorer-rules.md);
contracts: [degree-requirements.md](docs/developers/degree-requirements.md),
[catalog-scanning.md](docs/developers/catalog-scanning.md),
[catalog-normalization.md](docs/developers/catalog-normalization.md).

- [ ] **Minors.** Pilot list (English, Spanish, History, …), placed in the top
  band, with authored overlap rules.
- [ ] **Elective guidance.** Reviewed, major-specific suggestions kept apart
  from catalog rules, perhaps as institution Markdown files.
- [ ] **Advising-reviewed audit.** Conditional alternatives, transfer, grades,
  minor/residence/college constraints and selectable choices, without silently
  adding credits or certifying completion.
- [ ] **Compile approved rules** into runtime degree tables and route templates.
- [ ] **AI automation** behind the same proposal/review boundary, evaluated on
  the four-program pilot first.
- [ ] **Routes and constraints.** Selectable elective/science routes, all
  course restrictions, admission milestones, offering constraints, transfer
  scenarios.
- [ ] **More programs** with different entry rules, electives and
  concentrations; reconcile source conflicts and equivalences.
- [ ] **Catalog year and transfer evidence** before evaluating a major switch.
- [ ] **Observed term portfolios** without inventing an order among
  concurrent classes.
- [ ] **A requirement-informed demand challenger,** scored through the rolling
  projection contract.

## Platform

- [ ] **Code history by unit.** Admin → Mappings → Code history lists every
  `code_history.csv` row with when each code was offered. Still to do: each
  unit's program codes and course subjects with when each was in use, and the
  `program` rows, which are validated but no reader follows yet.
- [ ] **Operational monitoring.** Shiny errors, usage logs, scheduled-refresh
  outcomes and cold-cache latency after release.
- [ ] **Standard CSV export** across user-facing tables through a shared helper.

## Later

- [ ] **Demographics** by race/ethnicity/gender on chair-facing or Explore
  surfaces, with small-cell suppression.
- [ ] **Named-instructor DFW,** if policy supports showing it.
- [ ] **Faculty counts** through the existing faculty/FTE helpers.
- [ ] **Low-enrollment exception workflow** for dean/chair decisions on
  flagged courses.

### Established analytical methods

Evaluation opportunities, not claims CEDAR implements them. Each would expose
its population, assumptions, uncertainty and limits through a versioned
definition.

- [ ] **Growth vs worsening outcomes:** denominator-aware proportion charts for
  drop/DFW rates, counts beside rates ([NIST](https://www.itl.nist.gov/div898/handbook/pmc/section3/pmc332.htm)).
- [ ] **Gateway and sequence comparisons:** eligibility, prior completion and
  outcome windows defined first; balance is not causality ([WWC](https://ies.ed.gov/ncee/wwc/Docs/ReferenceResources/WWC-Baseline-Brief-v6_508.pdf)).
- [ ] **Departure, switching, graduation and return** as competing risks or
  multistate models, censored at the observation edge ([survival](https://cran.r-project.org/web/packages/survival/vignettes/compete.pdf)).
- [ ] **Structural curricular bottlenecks** from a versioned prerequisite graph
  plus observed course-taking ([Curricular Analytics](https://arxiv.org/abs/1811.09676)).
- [ ] **Section-planning decisions** judged on seat shortage and excess as well
  as forecast error ([FPP3](https://otexts.com/fpp3/tscv.html)).
- [ ] **Early momentum indicators:** credit accumulation, completion ratios,
  first-year gateway completion, from reliable term-level data ([PDP](https://studentclearinghouse.org/academy/courses/postsecondary-data-partnership-an-introduction/lessons/the-postsecondary-data-partnership-metrics/)).
- [ ] **Interpretation safeguards:** exploratory flags apart from confirmatory
  findings; multiple comparisons; course-based retention kept distinct from
  [IPEDS](https://nces.ed.gov/statprog/2002/std5_1.asp) cohorts ([AIR principles](https://www.airweb.org/resources/publications/statement-of-ethical-principles/principles)).

---

## Inbox

Ideas not yet given a theme or an order. Add freely; triage moves an item into
a theme above, into `ISSUES.md` if it is a fix to something that exists, or
deletes it.

- [ ] _(empty)_
