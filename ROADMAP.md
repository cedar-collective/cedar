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

1. **Projection adjustments.** The open items under [Section-needs
   projections](#section-needs-projections).
2. **Degree maps.** The open items under [Degree Explorer](#degree-explorer-and-curriculum-informed-demand).

The domain data model ([ADR-001](docs/developers/architecture-decisions.md#adr-001-move-cedars-tables-from-report-shaped-to-domain-shaped))
closed its migration on 2026-11-09: the transform builds every table, the app
loads, and the cones read the measure tables. What remains of it is under
[Platform](#platform).

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
scenarios, saved bundles per season with model provenance, and each course's
saved plan on Course Dynamics. Contract:
[enrollment-projections.md](docs/developers/enrollment-projections.md);
what was tried and rejected: [forecasting-lessons.md](docs/developers/forecasting-lessons.md).
Waitlists are not an input until two years of retained waitlists exist.

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
- [ ] **Review `projection_sequences.csv` yearly** against the lift-ranked
  feeders each bundle now saves (`adjusted_feeder_lifts`): a listed
  predecessor should be the top feeder of its successor, and a feeder at a
  high lift with a stable carry-through is a candidate to list.
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
- [ ] **Surface a course's takers against its non-takers.** The cone exists
  (`get_course_cohort_effect()`, 2026-11-10, over `cedar_attempts` and
  `cedar_student_terms`): for the students of a classification, by home
  campus and term, return the next regular term and the DFW share of their
  next-term attempts, split into passed the course, DFW'd it and never took
  it, with the balance table for takers against never-takers. On the
  2026-11-04 pull, main-campus first-semester freshmen, Fall 2023: passed
  FYEX 1010 returned at 94%, never took it 78%, DFW'd it 46%; next-term DFW
  share 28%, 25%, 61%. The page needs a classification picker (M41) and goes
  beside Course Dynamics > Retention, whose persistence split it extends with
  the non-takers.
- [ ] **Read a course's gap against its college's courses.** The text-first
  preview exists (`build_course_cohort_context()`, 2026-11-10): the same
  cone over every Arts & Sciences lower-division course the population took,
  and the focal course placed among them. What it says about the first-year
  seminars, same pull and population, Fall 2023 / 2024 / 2025: passing any
  A&S lower-division course goes with returning at a median 96 / 94 / 96%,
  a gap over never-takers of +19 / +17 / +8 points. FYEX 1010's passers
  returned at 94 / 90 / 95% (gap +16 / +11 / +8, in the bottom quartile of
  courses two years of three), and were the only passers in the college
  whose next-term DFW share was *above* the never-takers' (+3 / +2 / +4
  points against a median of -11 / -8 / -6; worse than 92–98% of courses).
  FYEX 1110's passers returned at 95 / 94 / 97% (gap +18 / +17 / +9, the
  median course) with a next-term DFW gap of -1 / -7 / -6 (the median course
  from 2024). The same reading at a guard of 100 students a group. So the
  retention signal is the selection every course shows, not a lift the
  seminars add: FYEX 1110 is an average A&S course on both measures, FYEX
  1010 an average one on return and the worst on next-term grades, which
  is who is placed into it (its takers' ACT, high-school GPA, Pell and
  first-generation shares all differ). The honest claim for a retention
  page: a first-semester freshman who passes a course returns; the question
  worth a page is who does not pass one, and that is the return watch
  above. The preview's page needs the same classification picker.
- [ ] **Near-completers and stalled pre-majors** as outreach counts.

## Degree Explorer and curriculum-informed demand

Built: an illustrative semester board for about two dozen programs from the
2026–27 catalog, with math/English starting points, prerequisite links,
15/16-credit budgeting, annual shared University/Gen Ed/college rules, course
popups with seats and first-day pressure, Pathways > Course paths, the offline
catalog scanner, Admin Catalog Review, reviewed AI-assisted draft
interpretations, and the population course pressure text preview
(`scripts/population-course-pressure.R`: for a named population group and its
plans, each shared course's uptake and timing, DFW against everyone, retake
timing after a DFW, and seasons, parts of term, seats and day-1 fill).
Rules: [degree-explorer-rules.md](docs/developers/degree-explorer-rules.md);
contracts: [degree-requirements.md](docs/developers/degree-requirements.md),
[catalog-scanning.md](docs/developers/catalog-scanning.md),
[catalog-normalization.md](docs/developers/catalog-normalization.md).

- [ ] **Course pressure on the board.** Surface the population course pressure
  preview for a population and its plans: the shared courses' day-1 fill,
  DFW gap and retake timing on the tiles they share, and a compact card mode
  so the board keeps its visual power as cards gain facts.
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
- [ ] **ADR-001's open questions:** size the pulls layer (full extracts or a
  changes-only log), and decide which `cedar_student_terms` measures need a
  home-campus variant
  ([open questions](docs/developers/architecture-decisions.md#open-questions)).

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

- [ ] **Surface `get_major_course_units()`** (which units teach the courses a
  major's students take; `R/cones/major-course-units.R`, 2026-11-10) on a
  Dept page beside Dept Trends' inverse view of whose majors fill a unit's seats.
