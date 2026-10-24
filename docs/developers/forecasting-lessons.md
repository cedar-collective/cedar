---
title: Enrollment Forecasting Lessons
parent: Developer Guide
nav_order: 11
---

# Enrollment Forecasting Lessons

This is CEDAR's evidence ledger for enrollment-model development. It records
what has been learned, what has failed, and which claims the current data can
support. It is not a second backlog; open implementation work belongs in
`ROADMAP.md`. The executable contract remains in
[Enrollment Projection Architecture](enrollment-projections.html).

## Current Evidence Snapshot

These measurements were produced on 2026-08-15 from model `0.11.0`, targeting
Spring 2027 with enrollment data through Fall 2026. The scope is 83
pressure-screened or always-monitored ABQ+EA course markets drawn from the Gen
Ed and critical-course registry.

| Evidence | Result |
|---|---:|
| Published observed-method aftcasts | 246 |
| Aggregate raw WAPE | 13.7% |
| Aggregate registration-cap-censored WAPE | 10.7% |
| Major/classification flow aftcasts | 311 across 82 courses |
| Major/classification raw / cap-censored WAPE | 15.3% / 11.4% |
| Broad Fall-population aftcasts | 311 across 82 courses |
| Broad population raw / cap-censored WAPE | 15.6% / 11.4% |
| Coupling result | 17 major/classification, 11 broad, 50 mixed, 5 insufficient |
| Published confidence | 4 High, 22 Medium, 26 Low, 31 None |

The aggregate is useful for describing the pilot, but it is not a release
criterion for every row. Course-level behavior is heterogeneous. The saved
coupling result matters more than the three-tenths-point aggregate difference
between the two population models.

## Model Version Ledger

| Model | Bundle schema | Calculation contract | Evidence |
|---|---:|---|---|
| `0.25.0` | 24 | No forecast change. The recent history is saved by delivery campus as well (`recent_campus_history`), and the summary flags a campus full on the first day while another had room, which the pooled market hides; a prior term at 98% or more is flagged full, not near full; an unknown prior fill names its cause. On the Oct 23 pull it flags 9 Spring 2027 rows, each EA full on the Spring 2026 first day with ABQ under 90%, and 2 Fall 2027 rows (FYEX 1030 EA full; NATV 1150 ABQ full with EA at 86%). The page states that the range assumes steady seats and how often it held, rebuilt from earlier forecasts only: Spring 86 of 105 with steady seats and 40 of 99 when they moved; Fall 98 of 115 and 28 of 91. A row whose draft moves the seats 10% or more says so under its range | [Re-audit on production data](#re-audit-on-production-data-model-0230-2026-10-20); ISSUES.md M36 |
| `0.25.0` | 24 | A term pulled before one of its later sessions began is no longer read as undated. Its begun sessions' first day, divided by all the seats, is a lower bound on fill: it settles saturation, the pressure bump and the expansion response only where it already reaches their level, the floor note says "at least", and an unsettled term names the session not yet begun. On a Fall 2026 class list pulled Oct 8, four days before the second-half sessions began, 12 of the 65 Fall 2027 courses offered in Fall 2026 are pending in the pooled market; the bound settles 5 as near full (MATH 1350 at least 94.8%, ENGL 1120 94.6%, PHIL 1120 92.6%, COMM 1130 91.8%, PHIL 1115 90.2%), and the other 7 now name the pending session instead of missing status dates. Once a pull covers every session start, nothing is pending and nothing changes | ISSUES.md I28 |
| `0.24.0` | 23 | December intersession (settings.csv `intersession_parts_of_term`) is left out of every projection input: it starts weeks after the term's first day, so it blanked first days (ISSUES.md I28), and it registers after a Fall settles, so the Fall spine read a partial Fall (I35). Pressure seat gaps compare with a floating-point tolerance (I34). | Spring 2027 regains pressure bumps for CHEM 1215L, COMM 1130 and HNRS 2221; Fall 2027 gains AFST 1110, ENGL 2210, MATH 1430, RELG 1110 and THEA 1110 (2026-10-23 pull). |
| `0.23.0` | 23 | No calculation change. Accuracy is shown as Reliability (High / Moderate / Low) beside a new seat-consistency axis; aftcasts record the seat and data conditions they were made under, and the page breaks past error down by them; the bundle dates the target term's draft schedule | [Where the error comes from](#where-the-error-comes-from-model-0230-2026-10-18) below |
| `0.23.0` | 22 | Planning sections, the seat gap and the recommendation are sized for registrations, not expected first-day seats, plus a pressure bump for a course always near full (10%, or its students left waiting if more) unless its feeders just fell 5% or more; the forecast and its accuracy are unchanged | [Sections sized for registrations again](#sections-sized-for-registrations-again-model-0230-2026-10-18) and [The pressure bump](#the-pressure-bump-model-0230-2026-10-18) below |
| `0.22.0` | 21 | The saturation floor is the spine plus the students still waiting who are on no campus's class list in the market; it was first-day enrollment plus the waitlist, which early-drop churn absorbed | [What the 0.21.0 audit found](#what-the-0210-audit-found-2026-10-18) below; ISSUES.md I27 |
| `0.21.0` | 21 | Seats judged and sized on the first day of classes: saturation, capacity reached (98% first-day fill), and section sizing read reconstructed first-day enrollment | [Capacity Censoring](enrollment-projections.html#capacity-censoring); ISSUES.md I26 |
| `0.20.0` | 20 | Two candidates: the prior same-season spine and spine + saturation floor + Fall enrollment deltas; rolling selection; every other candidate and bias correction retired | [Spring 2027 audit, 0.20.0](#spring-2027-audit-model-0200) below |
| `0.19.0` | 19 | Seven candidates (preceding-term ratio added; trend, feeder, and two anchored blends retired); rolling leakage-safe selection with out-of-sample accuracy; census-based capacity; sections from expected census; bias correction shelved | [Spring 2027 audit, 0.19.0](#spring-2027-audit-model-0190) below |
| `0.18.0` | 18 | Nine candidates; in-sample common-fold selection; ever-registered capacity flag; three evidence axes; Fall bundle; scenarios | [What the 0.18.0 audit found](#what-the-0180-audit-found-2026-10-16) |
| `0.11.0` | 12 | Six candidates; observed-method selection; Spring population and cohort-flow evidence; leakage-safe bias validation; registration-cap-censored audit | Evidence snapshot of 2026-08-15 above |

The model number changes when calculations, selection, calibration, or scoring
thresholds change. The schema number changes when the saved representation
changes. Schema 12 embeds the normalized model source and its hashes, so future
comparisons can recover the implementation behind a saved result instead of
relying on the version label alone.

## What the 0.18.0 audit found (2026-10-16)

Measured on the 0.18.0 Spring 2027 bundle (83 courses, data through Fall
2026) before model 0.19.0 replaced it. Each finding became a rule above or in
the architecture contract; ISSUES.md I25 and I26 carry the reproductions.

**In-sample selection lost to doing nothing.** The winner among nine candidates
was chosen on the two folds every eligible method shared (the trend candidate
needs three prior Springs), then scored on those two folds.

| Strategy, scored over the bundle's own aftcasts | Folds | WAPE |
|---|---:|---:|
| Published selection, scored on the folds that chose it | 273 | 13.7% |
| The same rule replayed rolling (choose only from earlier folds) | 311 | 16.5% |
| Prior same-season everywhere, no selection | 311 | 15.9% |

**Most candidates were the same number.** Correlation of each Spring 2027
candidate with prior same-season was 0.999 to 1.000 for both Spring population
methods and both anchored blends; median ratio 1.00 to 1.02. Choosing among
them was cosmetic.

**Two candidates were actively harmful.** Pooled over all applicable folds,
2023 to 2026:

| Method | Folds | WAPE | Bias |
|---|---:|---:|---:|
| Spring cohort flow | 311 | 15.3% | -4.6% |
| Prior same-season | 311 | 15.9% | -5.9% |
| Seasonal trend (undamped) | 149 | 20.0% | +11.7% |
| Seasonal median | 229 | 22.0% | -12.1% |
| Prior season + feeder change | 229 | 22.4% | +15.8% |
| Feeder transitions | 229 | 40.3% | +35.3% |

The feeder blend was nevertheless selected for six courses, on two-fold noise.
The median, which under-projects a recovering series, was the most-selected
observed method, though on the volatile courses it won it did help on the 2026
fold (17.8% vs 30.3%).

**"Capacity reached" measured seat churn.** Judged on ever-registered demand
the flag fired on 72% of folds; on census 17%; on final enrollment 6%. In 87 of
284 "reached" folds final fill was under 85%. The pressure screen passed every
non-forced course it saw on chronic fill, and sections sized from the
ever-registered headline came to 596 against 505 scheduled.

**Calibration never fired.** Four training plus two validation aftcasts cannot
be found in five Springs; zero of 83 rows were corrected.

**The engine never read the term that had just finished.** Prior same-season is
a year old when a Spring is scheduled. Tested over 226 Spring folds (2024 to
2026):

| Method | WAPE | Bias |
|---|---:|---:|
| Prior same-season | 16.5% | -5.0% |
| Preceding Fall x median Fall-to-Spring ratio | 19.2% | -1.8% |
| 50/50 blend of the two | 16.3% | -1.5% |

The ratio alone is noisier but unbiased; the blend matched prior same-season on
error, removed most of its under-projection, and was best on the 2026 fold
(13.6% vs 15.0%). It also sees what same-season history cannot: FDMA 2110 fell
to 106 in Spring 2026, rebounded to 355 in Fall 2026, and was published at 106.

## Spring 2027 audit, model 0.19.0

Rebuilt 2026-10-16 from data settled through Fall 2026, 139-course
`critical_courses` scope, `abq_ea_course_market`.

| Evidence | 0.18.0 | 0.19.0 |
|---|---:|---:|
| Published rows (pressure screen on ever-registered vs census fill) | 83 | 64 |
| Selected: prior same-season / median / ratio / blend / anchored cohort | 18 / 22 / — / — / 10 (+6 feeder, +22 population, +5 trend) | 31 / 11 / 12 / 5 / 5 |
| Realised WAPE of the published rule over its own folds | 13.7% in-sample (16.5% replayed) | 14.9% (238 folds, out of sample) |
| Prior same-season alone, same folds | 15.9% | 14.9% |
| 2026 fold, published rule | — | 10.7% (5 anchored challengers live) |
| Course-terms flagged capacity reached | 72% | 23% |
| Accuracy Close / Fair / Poor / Unrated | 21 / 27 / 32 / 3 | 14 / 22 / 26 / 2 |
| Expected census for Spring 2027 vs Spring 2026 census | — | 13,549 vs 13,458 |
| Planning sections vs Spring 2026 scheduled, same courses | 596 vs 505 | 460 vs 442 |
| Rows with a bias correction | 0 | 0 (disabled, stated on every row) |

Three readings:

1. **The honest record equals doing nothing, and now says so.** With three
   shared folds the rule admitted five challengers on the 2026 fold (all the
   anchored cohort blend) and its realised record is the default's to the
   decimal. Every published WAPE now reconciles exactly to the fold-by-fold
   `policy_selected` rows. The lower 0.18.0 figure was the fit of winners on
   the folds that chose them.
2. **Thirty-three challengers are live for Spring 2027** (12 preceding-term
   ratio, 11 median, 5 blend, 5 anchored), each having beaten the default by
   two points over Spring 2024 to 2026. Whether that holds is the first thing
   to read off the Spring 2027 actuals.
3. **The preceding-term ratio did not rescue FDMA 2110.** It projects 270
   where the default projects 106 and Fall 2026 was 355, but its own record on
   that course is poor (55.8% WAPE), so the rule keeps the default and the
   candidate table shows the disagreement. That is the designed outcome of a
   rule that must earn a switch; it is also the clearest case for a reader to
   look at.

## What the 0.19.0 audit found (2026-10-16)

Two decompositions on the rebuilt Spring 2027 bundle (64 courses, 238
rolling aftcasts) set the direction for 0.20.0.

**The error lives where the schedule moved.**

| Capacity change, prior Spring to the aftcast term | Folds | WAPE | Bias | Share of all error |
|---|---:|---:|---:|---:|
| Flat (within 10%) | 119 | 6.1% | -3.0% | 23% |
| Seats added, 10% or more | 74 | 23.0% | -22.4% | 55% |
| Seats cut, 10% or more | 45 | 39.0% | +37.7% | 22% |

Absolute error and absolute capacity change correlate 0.57 within course.
Stable courses aftcast at 6.8%, Volatile at 32%, and the Volatile ones are
mostly those whose schedules move. University headcount change correlates
about zero with course error. Under-projection outweighs over-projection two
and a half to one in seats, because the market grew from 11,990 to 14,897
ever-registered over four Springs and a last-value method is always a year
behind. The portfolio net error was within 2 to 3% in 2025 and 2026 even while
course-level WAPE was 11 to 14%: course errors offset.

**A Spring roster, by each student's state in the preceding Fall** (64
courses):

| Component | Spring 2025 | Spring 2026 |
|---|---:|---:|
| Enrolled in Fall, not in this course | 84.6% | 85.6% |
| New in Spring, no prior record | 7.6% | 6.7% |
| Repeating after a Fall DFW or W in the same course | 5.9% | 5.3% |
| Returning after an absence | 1.8% | 2.0% |

The per-course take rate of the Fall population has a median CV of 10% across
three Springs. Replacing the continuing block with Fall population times last
year's rate predicted it at 12.9% WAPE against 13.5% for carrying the count
forward: real, small. Last Spring already embeds the steady state of every
component; the components add information only when a Fall driver changes.

**When saturated courses were given room, they filled it.** Among same-season
pairs whose prior term had census fill of 90% or more and whose capacity then
grew by 10% or more (44 pairs), demand grew by a median 93% of the added
seats. Saturated courses held flat grew 0%.

Hence 0.20.0: the spine, a floor where the prior term was saturated, and two
deltas that are zero unless a Fall driver moved.

## Spring 2027 audit, model 0.20.0

Rebuilt 2026-10-16 from data settled through Fall 2026, 139-course
`critical_courses` scope, `abq_ea_course_market`.

| Evidence | Spring 2027 | Fall 2027 |
|---|---:|---:|
| Published rows | 64 | 75 |
| Selected: spine / adjusted | 55 / 9 | 73 / 2 |
| Adjusted candidate, pooled over every fold where both apply | 13.9% vs spine 14.9% (238 folds) | 14.2% vs spine 14.0% (279 folds) |
| Adjusted closer than the spine, by fold | 84 of 238 | 92 of 279 |
| Realised WAPE of the published rule | 14.9% | 14.0% |
| 2026 fold, published rule | 10.6% (11 adjusted rows live) | 15.1% (3 live) |
| Prior term saturated (census fill 90% or more) | 53 of 64 | 68 of 75 |
| Floor raised above the spine by a waitlist | 0 | 15 |
| Regime checks raised | 16 | 0 (deltas not observable two steps out) |
| Expansion response (saturated, then 10% or more seats added) | 97% of added seats filled, 77 cases | 100%, 76 cases |

Four readings:

1. **Pooled, the adjusted candidate beats the spine on Spring by one point**
   (13.9% against 14.9%) and ties it on Fall, where the deltas cannot apply.
   The gain is seat-weighted: it wins on 84 of 238 folds but on the large
   courses. Under the three-fold rolling rule it took over on 9 Spring
   courses and 2 Fall courses; the published rule's realised record is still
   the spine's, because a candidate only earns its place after three shared
   folds and most of its advantage is on the fourth.
2. **The floor is mostly a label this year.** Fifty-three of 64 Spring courses
   were saturated in Spring 2026, but class lists retained no Spring 2026
   waitlist rows, so the spine stands as its own floor and the recommendation
   says "at least". Fall 2027 is the first bundle where the waitlist lifts the
   floor: 15 courses, from Fall 2026's 3,885 retained waitlist rows.
3. **The deltas are small and mostly negative.** Median feeder delta -0.8
   students, median repeat delta 0; ENGL 1120 carries the largest, -85, from a
   smaller Fall 2026 feeder pool. Fall-enrollment change was muted this year,
   which is the designed behaviour: a delta is zero unless a driver moved.
4. **The regime check fires on 16 Spring courses**, FDMA 2110 among them (Fall
   2026 up 91% on Fall 2025). Its adjusted candidate still projects 106,
   because only 3 of the 12 Fall students historically repeat and the feeder
   pool barely moved; the number is honest and the alarm is the response.

## What the 0.21.0 audit found (2026-10-18)

Measured on the 0.21.0 Spring 2027 and Fall 2027 bundles (data settled through
Fall 2026, 139-course `critical_courses` scope) and on the class lists behind
them. Every rate below was learned only from terms before the aftcast it
scores; the scripts were session diagnostics, not committed code.

**Enrollment follows the seats, one registrant per seat.** Same strata as the
0.19.0 audit, now on the 0.21.0 aftcasts of prior same-season:

| Seats vs prior same-season | Spring folds | WAPE | Bias | Share of error | Fall folds | WAPE | Bias | Share of error |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Within 10% | 109 | 6.0% | -3.1% | 23% | 119 | 4.4% | -0.9% | 17% |
| Added 10% or more | 64 | 22.9% | -22.3% | 55% | 66 | 23.3% | -21.6% | 56% |
| Cut 10% or more | 42 | 39.7% | +38.2% | 22% | 41 | 39.2% | +39.2% | 27% |

The change in class-list demand correlates 0.95 (Spring) and 0.93 (Fall) with
the change in scheduled seats, at a slope of 1.00 and 0.98 registrants per
seat. Prior same-season plus the seat change would aftcast at 4.9% and 4.1%
WAPE against 14.8% and 14.3%: roughly two-thirds of the error is the schedule.
That figure is an oracle, and an optimistic one. A past term's DESR capacity is
its end-of-term schedule, which already holds sections added or cancelled
after registration opened, so some of the link runs from demand to seats.
Planned and reactive seats cannot be separated: the 265 cancelled sections in
scope carry no capacity, and only 11 of 42 Spring (11 of 41 Fall) seat cuts
coincide with a recorded cancellation. Nor can the schedule be anticipated
from the data: after a term full on the first day the median capacity change
was zero in both seasons, with seats added a third of the time in Spring and
cut more than a quarter.

**A demand signal cannot show up in a full course.** 53 of 58 Spring 2027 and
56 of 62 Fall 2027 courses were at or above 90% first-day fill in their spine
term. A course that cannot grow without seats cannot reward a model for
predicting that more students wanted it, so every demand-side adjustment is
scored against what is mostly a supply outcome. This is why the findings below
are small, and why they do not show that demand shifts are unimportant.

**Tested and rejected:**

| Idea | Folds | Prior same-season | Candidate | Verdict |
|---|---:|---:|---:|---|
| Pooled growth factor: spine x (1 + market growth over earlier folds), Spring | 161 | 15.0% (bias -5.0%) | 17.2% (+6.3%) | Worse: the 2023–24 recovery (portfolio under-projected by 11–14%) stopped, and the factor kept projecting it |
| Same, Fall | 169 | 13.2% (-2.2%) | 15.4% (+5.2%) | Worse |
| Damped own trend, phi 0.25, Spring / Fall | 158 / 164 | 14.9% / 12.5% | 17.1% / 14.2% | Worse; phi 0.5 worse again (19.7% / 16.7%) |
| Headcount change, flat-capacity folds | 109 / 119 | — | correlation -0.27 / 0.06 with the miss | No signal |
| Gen Ed area pooling (students substitute within an area) | 24 area-terms per season | course 13.7% / 13.7% | area 9.2% / 7.8% | Aggregation, not substitution: random course groupings of the same sizes score 8.3% / 7.3% (median of 2,000 shuffles) |

**Feeders: count, lift, majors, and an eligible pool.** The engine's feeder
set is the up-to-eight courses whose preceding-term students most often took
the target next. Ranked by count, that is the largest freshman courses: MATH
1220's feeders are ENGL 1110, PSYC 1110 and ENGL 1110X ahead of MATH 1215X/Y/Z.
Four variants were compared, each added with the repeat delta to the spine, on
the 152 Spring folds (2024–2026) where the preceding term was observed:

| Adjustment | All 53 courses | 44 courses fed mainly by prerequisites | Bias (all) |
|---|---:|---:|---:|
| None (prior same-season) | 14.7% | 13.7% | -4.7% |
| Engine: count-ranked feeders, one pooled rate | 13.2% | 12.1% | -1.5% |
| Prerequisite feeders (lift >= 3), one pooled rate | **12.9%** | **11.9%** | -2.0% |
| Prerequisite feeders, a separate rate per major | 13.5% | 12.4% | -3.0% |
| Eligible pool: preceding-term students without a pass, by segment (in a feeder, passed one in the last two years, earlier DFW in the target, other by major) | 13.5% | 12.5% | -1.0% |
| Eligible pool as a level, no spine | 15.8% | 14.9% | -3.3% |

Lift is a feeder student's rate of taking the target next over the rate for a
typical market student, from at least 20 transitions over at least two pairs;
the four prerequisite feeders carrying the most such students are kept. In
Fall nothing beat prior same-season: 13.0% over 156 folds, and 6.2% on the 16
courses fed mainly by prerequisites, which every adjustment made worse.

Four readings:

1. **Splitting the feeder change by major loses.** If the majors that take
   the target grow, the feeder grows and the pooled count already sees it; the
   split adds information only when the mix shifts toward majors more likely
   to continue, and per-major rates estimated from two to four pairs add more
   noise than that. The major-weighted delta's correlation with the residual
   after the seat change is 0.13, against 0.25 for the pooled count.
2. **The eligible pool's backlog is real and small**: students who passed a
   prerequisite and have not yet taken the target added about 3.5 students per
   course-term in Spring and 2 in Fall. An unbounded lookback roughly doubles
   it artificially (the history lengthens with every later term), so any pool
   needs a fixed window.
3. **Every variant tracks the seat change** about twice as strongly as the
   residual after it (correlation 0.47–0.54 against 0.13–0.25). Part of what a
   feeder delta predicts is that departments add Spring seats after a large
   Fall.
4. **MATH 1220 is a placement case.** It fell from 1,166 to 948 (Fall 2025)
   and to 770 (Fall 2026) as seats were cut by 127 and 238, and from 742 to 697
   in Spring 2026, while every demand adjustment predicted growth. The MATH
   1215 redesign placed students into 1215 who would have taken 1220 directly,
   so a larger feeder meant a smaller target. No feeder model can see a
   placement rule.

**The floor had never fired, and was in the wrong units.** Class lists keep no
waitlist rows before Summer 2026, so no historical aftcast has exercised the
floor. On the Fall 2027 bundle, 36 saturated courses held 245 students still
waiting at close; the floor added 77, and 24 of the 36 got nothing, because it
added the waitlist to first-day enrollment and compared the sum with the
ever-registered spine, which also counts early drops. Fixed in 0.22.0 (ISSUES.md
I27). Of the students still waiting at the end of Summer 2026, 29 of 107 (27%)
registered for the same course in Fall 2026: a turned-away student returns
the next term, not a year later, which the same-season floor cannot see.

**One history term per season cannot be judged.** Its class lists carry no
status dates, so no course in it has a first-day count and saturation,
capacity reached and the floor are unknown for the aftcast that reads it
(ISSUES.md M32).

## Rebuilt with model 0.22.0 (2026-10-18)

The same data and cutoff as the 0.21.0 bundles above; only the floor changed.

| Evidence | Spring 2027 | Fall 2027 |
|---|---:|---:|
| Saturated courses with students waiting | 0 | 36 → 35 |
| Students waiting in them | 0 | 245 → 243 |
| Floor uplift | 0 | 77 → 243 |
| Courses the floor lifts | 0 | 12 → 35 |
| Waiting students removed as already on the market class list | 0 | 6 |
| Aftcasts that moved | 2 (+2 students each) | 0 |
| Realised WAPE of the published rule | 14.7%, unchanged | 14.3%, unchanged |
| Published rows that moved | 0 | 1 (ARTS 1510, 119 → 127, 6 → 7 sections) |

Three readings:

1. **The floor now counts every waiting student.** ARTS 1610, ARTH 1120,
   FYEX 1010, MATH 1220 and BIOL 1140 each had students still waiting at the
   end of Fall 2026 and had been lifted by nothing.
2. **The published numbers barely move, because the published method is
   mostly the spine.** The adjusted candidate is selected for 2 of 62 Fall
   courses, so the corrected floor reaches the page mainly through the
   adjusted candidate's evidence, the floor note, and "Plan at least N", which
   every row carries. Whether the floor should apply to every saturated row
   regardless of which candidate is selected is a selection question, not a
   units one; the per-course rule cannot earn it on four aftcasts.
3. **The two moved aftcasts are Spring 2024 rows** (CLST 1110 and IADL 1110),
   lifted by stray waitlist rows retained from Spring 2023. Neither was the
   published pick. They are the floor's entire aftcast record, which is why
   its accuracy cannot be measured until Summer and Fall 2026 waitlists become
   spine terms for Fall 2027 and later.

## Sections sized for registrations again (model 0.23.0, 2026-10-18)

0.19.0 stopped sizing sections from registrations because they recommended 596
sections against 505 scheduled, and 0.21.0 moved the conversion from census to
the first day. Both judged the plan against what had been *scheduled*. Judged
against what was *filled*, the first-day plan runs short. On the 0.22.0
bundles' 207 aftcasts with a known first day (104 Spring, 103 Fall), comparing
the published rule's planned seats with the students actually seated on day
one:

| Planned seats | Short of day one | Seats short | Seats spare |
|---|---:|---:|---:|
| Expected first-day seats (0.21.0, 0.22.0) | 61% | 5,558 | 2,140 |
| Projected registrations (0.23.0) | 32% | 3,877 | 3,867 |
| Expected first-day seats + 10% | 33% | 3,442 | 4,706 |

147 of the 207 course-terms were full on day one, where the first day is
capped by the seats offered, so for them the shortfall is a minimum. The
first-day plan is centred on last year's first day, and these courses were
mostly growing (actual over planned, median 1.028) and mostly full. The
registration margin is a median 8% (10th to 90th percentile, 4% to 16%); it is
largest where early-drop churn is largest, not where the forecast is least
certain, but it correlates 0.35 with how far the actual overshot, and it puts
seats short and spare in balance. Running short of seats costs more than an
empty one, so the margin is kept on purpose.

Recomputed on the 0.22.0 bundles (no other number changes):

| Evidence | Spring 2027 | Fall 2027 |
|---|---:|---:|
| Planning sections, first-day sizing | 449 | 524 |
| Planning sections, registration sizing | 495 | 559 |
| Planning sections, with the pressure bump (below) | 514 | 599 |
| Rows whose sections change | 36 of 58 | 28 of 62 |
| Sections in each course's latest same-season offering | 427 | 502 |

A coverage level chosen as policy is the deliberate version of this margin:
plan seats so that past forecasts would have covered, say, 8 terms in 10. On
this record that is the first-day plan plus 21%. Registrations are the simpler
rule and do as well as a flat 10%.

## The pressure bump (model 0.23.0, 2026-10-18)

A near-full course's registrations follow its seats, not its demand. On the
0.22.0 bundles' aftcasts, 330 course-terms have both terms' capacity and a
judged prior term:

| After a near-full term (90%+ on day one), next term's seats | Course-terms | Median registration change | Share of the seat change registrations followed |
|---|---:|---:|---:|
| Up 10% or more | 89 | +28.6% | 100% |
| Within 10% | 139 | 0.0% | — |
| Down 10% or more | 51 | −33.3% | 100% |

So last year's count understates what an always-full course would draw. Until
retained waitlists can measure it, the plan adds a stated allowance: 10% (the
smallest expansion that record counts), or the students left waiting if that is
more, for a course near full on the first day in every one of its last three
same-season offerings with a known first day (at least two), unless its feeder
courses' enrollment fell 5% or more in the term just finished. The expansions
were chosen by schedulers who probably knew where demand was, so the record
shows that informed expansions filled, not how much the 139 held-flat courses
turned away: the 10% is an allowance, not a measurement, and the page says so.

It raises `planned_registrations` and the sections only. The forecast, WAPE and
the accuracy axes are untouched, because a full course's registrations are
capped and would score any allowance for the demand it turned away as
over-projection. Rebuilt on the same data and cutoff:

| Evidence | Spring 2027 | Fall 2027 |
|---|---:|---:|
| Courses bumped | 47 of 58 | 58 of 62 |
| Registrations added | 778 (10.0% of their projections) | 1,392 (10.2%) |
| Bumps sized by the students left waiting | 0 | 9 |
| Sections added | 19, in 17 courses | 40, in 22 courses |
| Denied: a recent term below 90% on day one | 6 | 1 |
| Denied: feeders fell 5% or more | 4 | 0 |
| Denied: too few terms with a first-day count | 1 | 3 |
| Forecast and published WAPE | unchanged | unchanged |

Three readings:

1. **Fall 2027 cannot run the feeder check.** Its feeders' term, Spring 2027,
   is not observed yet, so every Fall bump says so and asks for a recheck
   when it settles; the check runs for Spring 2027, where it denied four.
2. **The pressure screen selects full courses**, so most monitored rows get the
   bump: it is close to a 10% raise on the always-full core, and the page
   states the total above the table.
3. **Two Fall denials are I28, not the course.** ENGL 1120 and MATH 1350 have
   one Fall with a first-day count because the Fall 2026 class list was pulled
   before their second-half sessions began (ISSUES.md I28); both were near full
   in Fall 2025.

## Where the error comes from (model 0.23.0, 2026-10-18)

Every aftcast now records the conditions it was made under: how far the
course's seats moved from its previous same-season offering, and whether that
offering was near full on the first day. Summing the published rule's absolute
error by those conditions, on the 0.23.0 bundles (same data and cutoff as
above):

| Source of the miss | Spring 2027: terms | error | share of all error | Fall 2027: terms | error | share |
|---|---:|---:|---:|---:|---:|---:|
| Seats changed 10% or more | 106 | 25.9% | 77% | 107 | 26.7% | 83% |
| Seat or first-day data missing | 33 | 5.2% | 7% | 32 | 5.2% | 5% |
| Seats held; course was near full | 56 | 4.4% | 9% | 83 | 4.0% | 11% |
| Seats held; course had room | 20 | 14.6% | 7% | 4 | 5.7% | 1% |

Three readings:

1. **The misses are mostly the schedule's.** A near-full course registers
   about as many students as it has seats, so when seats move, registrations
   follow and last year's number misses by the move.
2. **The demand forecast proper is a small share.** Only seats-held-with-room
   tests it, and that is 7% and 1% of the error. A better demand model has
   little left to win; reading the draft schedule has most of it.
3. **No course misses with steady seats.** Reliability was paired with a new
   seat-consistency axis (how often seats moved 10% or more across the same
   terms). In both seasons every Low-reliability course had Low or Moderate
   seat consistency (24 of 24 in each), so none is flagged "Off 20%+ with steady
   seats". A course that appears there later is the first evidence of a
   model problem rather than a schedule one.

The page shows this breakdown for whichever projection is loaded, in the
"Where forecast error comes from" panel.

## Re-audit on production data (model 0.23.0, 2026-10-20)

Both bundles rebuilt from production's tables of 2026-10-20 (data settled
through Fall 2026, 139-course `critical_courses` scope): 58 Spring 2027 rows
over 215 published aftcasts, 71 Fall 2027 rows over 262. The scripts were
session diagnostics, not committed code.

**Where the record stands.**

| | Spring 2027 | Fall 2027 |
|---|---:|---:|
| Published rule, WAPE / bias | 14.7% / -6.3% | 14.0% / -4.4% |
| Seats within 10% of the prior offering | 6.0% / -2.8% (109) | 4.7% / -1.4% (136) |
| Seats added 10% or more | 22.7% / -22.3% (64) | 22.7% / -21.2% (77) |
| Seats cut 10% or more | 39.7% / +38.2% (42) | 36.0% / +36.0% (49) |
| Portfolio net error by fold | -11.5%, -14.2%, +3.5%, -3.6% | -10.6%, +0.4%, -5.0%, -2.5% |
| Aftcasts whose actual reached capacity (a lower bound on demand) | 107 of 215 | 127 of 262 |
| Aftcasts whose first day cannot be judged (M32, I28) | 54 of 215 | 68 of 262 |
| Published rows whose last offering was 98%+ full on day one / 90%+ | 42 / 53 of 58 | 48 / 66 of 71 |

**The labels mean what they say.** Median realised WAPE by stability: Stable
6.4% (both seasons), Moderate 14.8% / 13.0%, Volatile 33.5% / 36.2%; by seat
consistency, High 4.2% / 5.5%, Moderate 11.6% / 10.8%, Low 26.8% / 21.4%. A
reader who trusts "Stable" and distrusts "Volatile" is reading the evidence
correctly.

**The range does not.** Rebuilt rolling, the course's own 80th-percentile miss
covered 67% of next-fold outcomes in each season: 88% / 94% where seats held,
40% / 33% where they moved, mostly with the actual above the range (ISSUES.md
M35).

**Pooled selection does not help.** Choosing the adjusted candidate for every
course whenever it led pooled on earlier folds scored 12.6% on the Spring 2025
and 2026 folds, against 12.3% for the per-course rule and 12.4% for the spine;
on Fall it never switched. What to Try Next item 5 is closed.

**The schedule at registration opening carries most of the gain, in Spring.**
Registration opens about 80 days before a Spring term and 140 before a Fall
one. A section's first class-list status date shows when it first took a
registrant; sections that first did so 14 or more days after opening hold 10%
of final Spring capacity in scope. Adding the change from the prior offering's
seats to the seats on sale in the first 30 days to the spine:

| Spring aftcasts (2023, 2024, 2026; 109) | WAPE |
|---|---:|
| Spine (prior same-season) | 17.3% |
| Spine + seat change, schedule of the first 14 days | 14.6% |
| Spine + seat change, schedule of the first 30 days | 11.7% |
| Spine + seat change, final schedule (oracle) | 5.6% |

The same proxy fails for Fall (35.0% against the spine's 15.4%): 35% of Fall
seats first take a registrant after opening because new students register at
summer orientation, so a late first registrant there is not a late section.
Fall needs archived schedules to be tested. The Spring result is the evidence
behind What to Try Next item 1: a projection conditioned on the schedule a
department has posted, published beside the spine.

**Pooling ABQ and EA hides a full online campus.** In Spring 2026, 11 courses
had EA full on the first day while ABQ had 10% or more room, 10 of them under
90% full pooled; in Fall 2026, 4, CLST 1110 among them with 68 waiting for EA
and 217 open ABQ seats (ISSUES.md M36). The pooled demand is still the right
forecast target; the recommendation needs to say which delivery is short.

## Lessons From the Retired Experiments

The retired forecasting code tried useful ideas, especially major and
classification composition, but coupled data preparation, model calculation,
and display too tightly. Re-running a computational idea required a Shiny data
load and restart, model provenance was difficult to inspect row by row, and
historical evaluation could drift from the current formula.

The ideas were worth keeping; the execution path was not. The replacement has
one branch implementation per candidate, rolling-origin aftcasts through the
same candidate function, a validated saved artifact, a canonical text preview,
and a read-only UI. A model is not part of CEDAR until all five surfaces agree:
candidate output, aftcast output, bundle schema, text preview, and UI payload.

## Define the Target Before Improving the Model

The planning target is total unique class-list demand: anyone who registered
for the course, including later drops. It is not end-of-term DESR enrollment and
not census enrollment. Expected census is a secondary conversion based on each
course's historical class-list-to-census retention.

This decision resolves several apparent model failures. A model intended to
predict registration demand should not be scored against a later, attrition-
reduced lifecycle point. Attrition belongs in the expected-census conversion,
not as a downward adjustment to demand.

ABQ and EA are pooled for this scope. Online seats are a substitutable delivery
of the same planning market, and separate campus projections often reproduce
seat allocation rather than student demand. Branch campuses remain excluded.

## A Full Course Is a Lower Bound

The naive prior-season benchmark can look excellent because historical
enrollment repeats historical capacity. When class-list demand reached
scheduled capacity, an estimate above observed enrollment is not fully
measurable as an error. CEDAR therefore retains raw WAPE and a one-sided
registration-cap-censored WAPE, and labels individual terms
`Capacity-bounded` rather than showing a misleading zero.

Capacity does not become a demand input. It is used to interpret an aftcast and
to compare a published demand estimate with the target schedule. Otherwise the
system would answer the scheduling question with the schedule itself.

## Population Coupling Is Course-Specific

The major/classification method is not simply a feeder model. It begins with
the prior Spring target-course roster, observes those students' preceding-Fall
major/classification cells, measures year-over-year growth in those cells using
all Fall students, and propagates the matched course cohort. Students missing
from the preceding Fall are carried forward separately.

The broad comparator uses the same matched/unmatched decomposition but applies
one growth rate from all preceding-Fall students. Neither model wins globally:
the current aftcasts favor major/classification for some courses, broad
population for others, and show little meaningful difference for most. The
saved `coupling_status`, WAPE difference, and aftcast count preserve that result
for future model selection research.

Choosing the winner on the same history used to report its performance
overstates accuracy, and the 0.18.0 audit showed it does worse than not
choosing at all. Since 0.19.0 every selection is rolling: prior same-season is
the default, a challenger must beat it on earlier shared aftcasts, and the
published accuracy is the realised record of that rule.

## Bias Can Be Correctable, Variance Cannot

WAPE is unsigned. A stable +10% error and alternating +20%/-20% errors can have
similar WAPE but imply different action. CEDAR stores weighted signed bias,
term-level signed errors, directional consistency, and error spread.

A bias correction is applied only after a proposed multiplicative factor has
been tested on at least two later rolling aftcasts and improves WAPE by at least
one percentage point. That needs six comparable terms; five Springs cannot
supply them, so the correction is disabled (`calibration_enabled`) until they
can, and every row says so. Structural methods fit and validate corrections only on
terms that did not reach capacity. This prevents a full course from teaching
the model to reduce a potentially valid high demand estimate.

## Explanations Are Evidence, Not Causes

Recent evidence can identify a potential contributor to a miss: enrollment and
scheduled capacity moved together, enrollment changed sharply from the prior
same-season term, or registration reached capacity. These are row-level audit
signals, not causal findings. The UI must say `Potential explanation` or
`Potential contributor` and must retain the underlying numeric changes.

An exploratory check found almost no generic linear association between prior
same-course DFW rate and the next projection residual (correlation about
-0.01). A blanket DFW multiplier is therefore unsupported. More targeted ideas
remain plausible: a repeat-eligible pool after DFW, feeder-course pass counts,
or progression eligibility. Those require leakage-safe course-specific tests.

## What to Try Next

1. **Condition on the draft schedule.** Most of the error moves with the seats
   (77% of Spring 2027's aftcast error, 83% of Fall 2027's). The Draft schedule tab now compares the
   plan with the draft; the next step is a projection that reads the schedule a
   department has submitted and says "with these seats, expect this; the last
   term was full; past expansions filled this share". On Spring the schedule of
   registration's first 30 days took the spine from 17.3% to 11.7% (2026-10-20
   re-audit above); Fall cannot be tested until schedules are archived.
2. **Rank feeders by lift, not count**, keeping one pooled rate. The accuracy
   gain is small (0.2–0.3 points); the reason is that "ENGL 1110, PSYC 1110" is
   not a credible feeder list for MATH 1220. Do not split the rate by major,
   and do not build the eligible pool as a separate method.
3. **Record known policy changes as data** (placement cutoffs, redesigned
   sequences, new requirements) with their reason, shown as a labelled
   adjustment and checked against the actuals afterwards. MATH 1220 and FYEX
   1010 move for reasons no feeder or demand model can see.
4. **Carry a waitlist into the next term** as a change from the year before,
   once a second year of waitlists exists to measure the change against. The
   same evidence should replace the pressure bump's flat 10% with a measured,
   per-course allowance.
5. ~~Select between candidates over the pooled course set.~~ Tested
   2026-10-20: 12.6% against 12.3% per course and 12.4% for the spine on Spring;
   no switch on Fall. Closed.
6. Evaluate hierarchical shrinkage so two-aftcast courses borrow strength
   without erasing course differences. A robust ensemble of observed baselines
   remains untested; damped trends and pooled growth factors are tested and
   rejected (above).
7. Add repeat-eligible candidates only where the course logic supports them;
   do not add DFW as a universal multiplier, and do not revive the retired
   feeder-transition estimator without fixing its +35% bias.
8. Build the separate Fall specification from continuing Spring students plus
   archived admissions, acceptance, and orientation snapshots for new students.
9. **Archive a daily course-level snapshot of the schedule and of
   registration.** Production pulls both every morning and keeps only the last.
   A few thousand rows a day would give real planned-versus-reactive seats
   (item 1, and the only way to test it on Fall), registration pace against the
   same day a year earlier, and how waitlists rise and clear. One final snapshot
   per term cannot recover blocked demand.

Every new method follows the same gate: designed fixture, rolling aftcasts,
real-data audit, schema and preview update, saved-bundle rebuild, full R suite,
then Docker and browser verification if the display contract changes.
