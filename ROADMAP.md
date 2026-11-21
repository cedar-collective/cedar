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

Supported surfaces: Dept Dashboard, Dept Trends, Course Dynamics; Student
Pathways, Degree Explorer (Pathways); Regstats, Open Seats, Waitlists,
Projections (Registration); Enrollment, Headcount, Gen Ed, DFW Rates,
Retention, Graduation, Cancellations (Bird's Eye); Data & Usage, Changelog (Admin).
Course-anchored retention across courses is built but hidden.

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
`scripts/mapping-review.R`). Whether FYEX 1110's *Starts Here* is *Success Starts
Here* and *Fndmntl / Found. / Foundatnl Math Transition* one seminar
(`institution/unm/topic_titles.csv`).

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

- [ ] **A registration watch: what is worth a look, ranked.** One list built
  from the screens Regstats already runs, read together: a course flagged by
  several independent screens outranks any single flag, and their
  combinations are named (seats cut: a dip in a near-full course; students still
  waiting; growth near capacity; churn; falling or rising demand with room; a
  drop spike), with a state that holds every year (usually near full) counted but
  not listed. Measured on Fall 2026 lower division (ABQ and EA, Oct 8 pull),
  by the watch: 363 courses flagged (333 course-campus pairs, each part of term
  read apart), 297 by two or more screens; 110 only usually near full, counted
  and not listed; 16 seats cut, led by MATH 1430 at ABQ, 165 enrolled against
  a usual 360 in 174 seats, 94.8% filled at census. Done: step 1, the
  text-first preview over the Regstats payload (`build_registration_watch()`),
  and step 2, Regstats' Worth a Look tab, a picture of it: each course a point at its change against its usual
  enrollment (across) and its census fill (up), sized by the students behind
  it and coloured by pattern, with the near-full line drawn, so seats cut,
  growth near capacity, falling and rising demand sit in their own corners and
  waiting and drops are marked on the point; the ranked list beside it. Then
  the Dept Dashboard (chairs), a college roll-up (deans) and Home (provost),
  each item a sentence and a link. Later: a department roll-up
  (`attach_unit()` on the flagged rows) and the return watch as another
  screen. Regstats' own "full" badges: ISSUES M51.
- [ ] **Bird's Eye > DFW: how UNM is doing on DFW, and where to act.**
  Lower division, one term type at a time, replacing OIA's course fail rates
  page: the UNM-wide series with a trend verdict and what the DFW grades
  were; the courses ranked by DFW grades (on the 2026-11-15 tables, 23 of
  1,396 fall campus-courses hold a quarter of them, 90 half); which are
  rising, falling or swinging more than courses usually do; courses whose
  sections disagree term after term (25 in fall); campus and college. Done:
  step 1, the text-first preview (`build_dfw_dashboard()`), and step 2, the
  page (Bird's Eye > DFW Rates). Next: a course row opens it in Course
  Dynamics. Graduate rates wait on how PR (thesis in progress) is read; upper
  division is left to the department pages.
- [ ] **Gen Ed's DFW table from the DFW course board.** Gen Ed pools the term
  types chosen and rounds in its own way, so a course can read two DFW rates
  on two pages. Give `get_dfw_course_board()` a Gen Ed course scope and make
  Gen Ed's DFW table that board, which also gives it trends and swings.
- [ ] **A trend verdict on the Course Report's DFW by term:** the table mixes
  Fall, Spring and Summer and says nothing about direction; read it one term
  type at a time with `compute_rate_trend()`, the test Later Course and the
  DFW dashboard share.
- [ ] **Choose the tabs** that get one: likely DFW, Enrollment Trends,
  Headcount Trends and Gen Ed.

## Retention signals while there is time to act

Built: next-term registration of last term's students kept at every refresh
(`return-*` snapshots); Course Dynamics > Takers vs Non-Takers (2026-11-10:
a course's passed, DFW'd and never-took groups for a classification by home
campus, with return and next-term DFW share, read against every course of a
college the same students took, with the balance table). Measured: of Fall
2025's undergraduates, the 6,751 who withdrew late, failed a course or were on
probation returned at 78% against 93% and were 63% of the loss; a third had
not registered on Dec 1. The measure is pace against the same day a year
earlier, always aggregate. And for main-campus first-semester freshmen, Fall
2023–2025: passing any Arts & Sciences lower-division course went with
returning at a median 96 / 94 / 96%, a gap of +19 / +17 / +8 points over
never-takers; FYEX 1110 was the median course on return and on next-term
grades, FYEX 1010 average on return (gap +16 / +11 / +8) and the one course
whose passers DFW'd more the next term than its never-takers (+3 / +2 / +4
against a median of −11 / −8 / −6), which is who is placed into it (ACT,
high-school GPA, Pell, first-generation all differ). The retention signal is
the selection every course shows, not a lift the seminars add; the question
worth a page is who does not pass a course, which is the return watch.

- [ ] **Return watch** on the Dept Dashboard and as the top section of Bird's
  Eye > Retention: continuing students not yet registered against the same
  day a year earlier, by classification, standing and warning sign. Exact
  from Fall 2027.
- [ ] **Probation as a Retention warning sign** once `academic_standing`'s
  Banner values are mapped to a standing group in an institution file.
- [ ] **Roadblocks on the Dept Dashboard,** ranked by Impact (`get_stopout()`).
- [ ] **Unhide cross-course Retention** once it sets each course against its
  department and college.
- [ ] **Give Coming Back the classification scope** (Course Dynamics >
  Downstream) that Against Non-Takers has
  (M41), so its cohorts can leave concurrent-enrollment students out.
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
- [ ] **Electives at the bottom right** (user 2026-11-19). Every elective
  card, the major's own and free elective/minor space alike, moves below the
  program's required courses, so the required courses sit together and nothing
  is scrolled past to reach them. Revises the four-band rule in
  degree-explorer-rules.md.
- [ ] **Two-part sequences in consecutive semesters** (user 2026-11-19). An
  authored sequence field beside `row_group` (never inferred from numbers);
  the scheduler puts part two in the next regular semester, starting in fall
  where it can, on one row. An audit lists same-subject number-adjacent pairs
  (HIST 491/492) as candidates to confirm.
- [ ] **Humanities Gen Ed before STEM Gen Ed** (user 2026-11-19), unless a
  program requirement needs it sooner: a platform default order of Gen Ed
  areas a program can override. Math and writing stay in the first year, and
  one science Gen Ed is placed by the end of the second year.
- [ ] **Minors.** Pilot list (English, Spanish, History, …), placed in the top
  band, with authored overlap rules.
- [ ] **Elective guidance.** Reviewed, major-specific suggestions kept apart
  from catalog rules, perhaps as institution Markdown files.
- [ ] **Advising-reviewed audit.** Conditional alternatives, transfer, grades,
  minor/residence/college constraints and selectable choices, without silently
  adding credits or certifying completion.
- [ ] **Compile approved rules** into runtime degree tables and route templates.
  Draft rows, placed draft boards and the board comparison exist
  (`degree-compiler.R`, `degree-compiler-board.R`,
  [results](docs/developers/catalog-normalization.md#compiling-a-reading-into-board-rows)).
  Compiled boards are published (`--write`, `features/degree-drafts.R`): each
  takes its program's hand board's place on Degree Explorer, labelled a draft
  until its reading is signed off, then reviewed. Next: readings for programs
  with no hand board (a draft needs a catalog row for them), and showing a
  sign-off without a restart.
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

## Finding your way

The 2026-11-14 page audit found the app does more than a reader can see.
Page-level legibility is [M43](ISSUES.md)–M48; these are the new pieces.

- [ ] **Every course code and department opens its page.** A course code in any
  table opens Course Dynamics for that course, a department opens Dept Trends;
  only Waitlists and Regstats drill today, and the Dashboard's "Full trendlines
  are in Dept Trends > Course Demand" is plain text.
- [ ] **A Home page organized by question.** "Is my department growing?",
  "Which courses are under pressure this term?", "Where do students go after
  this course?", each a deep link to the subtab that answers it; Course
  Dynamics' eight subtabs and Pathways' six are invisible from Home now.


## Platform

- [ ] **Code history by unit.** Admin → Mappings → Code history lists every
  `code_history.csv` row with when each code was offered. Still to do: each
  unit's program codes and course subjects with when each was in use, and the
  `program` rows, which are validated but no reader follows yet (the file
  holds none). Picking a unit or college already counts every code mapped to
  it: Liberal Arts & Integrative Studies (LAIS, in University College) holds
  LIBA, INGI and LAIS and the pre-majors FLIB, FING, FINN and FLAI, and LAIS
  itself is only 1,619 of their 8,531 enrolled student-terms since Fall 2019.
  Picking one major does not: Pathways' Majors picker by name, or Dept
  Trends' program filter, set to LAIS misses LIBA's 4,372. Show each code's
  years in use in the Data scope disclosure (from `cedar_class_list_majors`),
  and record successions such as LIBA → LAIS as `program` rows that a major
  picker follows, naming the earlier codes it added.
- [ ] **Courses Taken for any major, Undecided included.** "What courses do
  students in major X take?" is Dept Trends > Courses Taken, entered by
  department, so a major no unit owns (Undecided `UNDC`, Non-Degree `NOND`)
  had no answer. The cone now reads any major by its code (PR #328; own-unit
  share blank). Left: show it on Pathways for the majors its Major picker
  already offers (Undecided among them; `cedar_programs` holds its
  declarations), with no picker of its own. The unit's own courses are now
  listed course by course beside the outside ones, with level and Gen Ed
  filters (Every Course These Majors Take, 2026-11-21). Later: mark the
  courses a compiled degree plan names.
- [ ] **The mapping assistant proposes ADCW for a branch-only code.**
  `scripts/propose-mappings.R` stops at "no evidence settles the unit" for a
  subject or program whose only source department is the Provost Branch
  Campuses bucket. The rule decided 2026-11-14: the branch unit that teaches
  it (or, for a new subject, the unit of the subject it renumbers, read from
  `code_history.csv`) where one exists, otherwise ADCW. Propose rows by that
  rule, still `proposed`, and review the proposals after each term's first
  pull, largest first, stopping when the tail is under about 50 student-terms
  a term.
- [ ] **Operational monitoring.** Shiny errors, usage logs, scheduled-refresh
  outcomes and cold-cache latency after release.
- [ ] **Standard CSV export** across user-facing tables through a shared helper.
- [ ] **A topic filter for the whole Course Dynamics page.** The Topics tab
  counts a course's topics from the schedule and class list, because the
  measure tables are counted by course and part of term. A section (or topic)
  grain on `cedar_course_terms` and `cedar_attempts`, with a schema bump and
  rebuild, would let every tab scope to one topic and the Topics cone read the
  measures.
- [ ] **One test for a topics course.** Low Enrollment, the Dept Dashboard and
  planning history call a course topics when a title starts `T:`
  (`is_topics_course()`, `is_topics`); Course Dynamics > Topics calls it topics
  when one campus-term offered two or more titles (`course_has_topics()`).
  Move the others to the data-driven rule.
- [ ] **ADR-001's open questions:** size the pulls layer (full extracts or a
  changes-only log), and decide which `cedar_student_terms` measures need a
  home-campus variant
  ([open questions](docs/developers/architecture-decisions.md#open-questions)).

## Later

- [ ] **Demographics** by race/ethnicity/gender on chair-facing or Explore
  surfaces, with small-cell suppression.
- [ ] **Named-instructor DFW,** if policy supports showing it. Three views
  now ask whether a teaching unit differs from its course (the Course Report's
  and Gen Ed's instructor DFW, the dashboard's section spread); only the
  section spread tests it against chance. Build one branch for units against
  the course's pooled rate and give the gated instructor views its test.
- [ ] **Faculty counts**, if HR data returns: build a faculty table fresh from the new report. The old HR pipeline and `cedar_faculty` were retired on 2026-11-18, and git history keeps them.
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

- **A course's entering students, years on** (from the 2026-11-20 Downstream audit). For the first-term students who took a course: return a year later, second-year GPA and graduation in four years, against similar students of the same entering class, with the alike check. Against Non-Takers reads one semester ahead only, so it cannot answer "does this course raise graduation?".
- **Placement scores in the admissions table** (wanted; the data is being requested, 2026-11-20). A course students are placed into (developmental math, reading) cannot be compared like for like without the score that placed them: matched on everything the records hold, its students still start behind. With the score, compare students just either side of the cut.
- **Retained early, then spinning their wheels?** (meeting notes, 2026-11-21). Built on Bird's Eye > Graduation: each fall's first-time class as each year begins, split into a degree, enrolled on a four-year pace, on a six-year pace, slower, and not enrolled; and the middle enrolled student's credits term by term (`get_entering_class_retention()` with `opt$pace`). Open: the first class the lists hold has no readable credits (`timeline_valid`); credit brought from elsewhere is not counted; completed against attempted credits; where the line between Retention and Graduation should fall.
- **Where students are when they pass 160 attempted credits** (asked 2026-11-21). Built on Bird's Eye > Graduation (`get_credit_ceiling_crossings()`): where the credits came from and what happened in the terms after. Open: students whose record began before the class lists cannot be placed (a backward count from the latest stamped total, less the class-list credits since, might recover them; unvalidated); their majors and colleges; the same reading at 120 earned credits.
- **Five-year and six-year degree maps** (asked 2026-11-21; later). A slower map per program for students who need more time or summer terms. Cost: every map is a second and third schedule to keep in step with the catalog; a generated slower schedule from the same requirements would avoid hand upkeep.
- **Where students are when they reach 120 credits, and what is missing** (meeting notes, 2026-11-21). Of the students who reach 120: awarded a degree that term, within a year, still enrolled, gone. For those whose whole record is here (started here, little credit from elsewhere), a course with no attempt really was not taken, so the plan's named courses can be read as missing, which they cannot for leavers in general (Graduation's required-courses section).
- **What a leaver's credits could still be good for** (meeting notes, 2026-11-21). How many left with 120 credits or more and a GPA of 2.0 or better; how many past 60. Whether those credits complete another credential (an associate degree, Liberal Arts) needs that credential's rules on file and a way to see transfer coursework, which the data does not hold.
- **Transfer students as their own population** (2026-11-21). Built: transfer classes on Graduation's pace section, by credits brought, read by credits earned here a term (`opt$arrival_credits`). Next: the same split on the leavers views (credit bands, majors, required courses); spring transfer classes; degree within two, three and four years of arriving as a headline; transfer articulation records (which courses the credit counted for), a data request, without which "what is missing" cannot be read for them; transfer degree maps.
- **More entering populations on Retention**: transfer students by standing at entry (lower-division, upper-division or with an associate degree), and a table per class of who is counted and who is not (first-time, transfer, readmitted, high-school students, non-degree). The first-time and transfer choices are built.
- **Intended sequels, filled in and used further**: `course_sequels.csv` exists and sets Next Courses' default (three pairs so far). Add the rest by PR; then read it for projections and degree maps, with rules for when to ignore it. `projection_sequences.csv` holds three such pairs for the projections; a separate file keeps edits from rebuilding the projection bundles.
- **Academic recovery**: among students who entered a term below a 2.0, which courses go with being back above it a term later, against similar students who did not take the course (the Against Non-Takers matching, restricted to that group). Retention's by-band lists show where such students hold their own within a term; this follows them to the next.
- **Graduation tab (Bird's Eye): what each far-along student's major still required** (asked 2026-11-20). Shipped: the count (`get_exit_credits()`) and the page (credit bands, last terms, Pell and the two general standards for aid, colleges and majors). The counting for what was left is built (`get_exit_requirement_progress()`, text preview in `format_graduation_dashboard()`): per named course of the program's board, who passed it here, who tried and never passed, who has no attempt. Most far-along leavers brought most of their credit from elsewhere, so "no attempt" cannot be read as "still required"; the dependable signal is "tried and never passed". Its section is on the page (a chart and table per plan, led by "tried here, never passed"). Next: choices and elective space; plans whose course numbers are newer than the students (needs confirmed renames in `code_history.csv`); then the requirement-file rounds below.
- **Requirement files for every major, ingested and approved in rounds** (2026-11-20): the Graduation tab's "what was left" needs a reviewed requirement file per program. Work out the kinks on the pilot samples first, then show the round: scan, extract, review, sign off, and what the page shows for a program not yet signed off.
- **Reassess field reliability** (2026-11-20): the page states verdicts more firmly than it documents how each was measured. Restate each field's verdict with its measurement, re-measure on two current pulls, and test the departed-student exception against a second pull.
- **Retention built before the first reader arrives**: the page is shared by every session once built, and the first reader after a start still waits about 25 seconds. Build it at start or at deploy.
- **Prepared for It on the same footing as Against Non-Takers** ([M60](ISSUES.md)): the same matching cells and the same check of the matching.

