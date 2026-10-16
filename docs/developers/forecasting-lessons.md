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

1. Test a robust ensemble of the observed baselines against the rolling
   default-plus-challenger rule; any candidate enters as a challenger and must
   beat prior same-season out of sample.
2. Evaluate hierarchical shrinkage so two-aftcast courses borrow strength
   without erasing course differences.
3. Add repeat-eligible candidates only where the course logic supports them;
   do not add DFW as a universal multiplier, and do not revive the retired
   feeder-transition estimator without fixing its +35% bias.
4. Build the separate Fall specification from continuing Spring students plus
   archived admissions, acceptance, and orientation snapshots for new students.
5. Retain registration snapshots if pace or true peak-demand models become a
   priority. One final snapshot per term cannot recover blocked demand.

Every new method follows the same gate: designed fixture, rolling aftcasts,
real-data audit, schema and preview update, saved-bundle rebuild, full R suite,
then Docker and browser verification if the display contract changes.
