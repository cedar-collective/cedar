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
| `0.11.0` | 12 | Six candidates; observed-method selection; Spring population and cohort-flow evidence; leakage-safe bias validation; registration-cap-censored audit | Current evidence snapshot above |

The model number changes when calculations, selection, calibration, or scoring
thresholds change. The schema number changes when the saved representation
changes. Schema 12 embeds the normalized model source and its hashes, so future
comparisons can recover the implementation behind a saved result instead of
relying on the version label alone.

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

Per-course switching is not yet the published demand method. Choosing the
winner on the same history used to report its performance would overstate
accuracy. Any adaptive structural selection must be rolling and use only prior
aftcasts at each historical target.

## Bias Can Be Correctable, Variance Cannot

WAPE is unsigned. A stable +10% error and alternating +20%/-20% errors can have
similar WAPE but imply different action. CEDAR stores weighted signed bias,
term-level signed errors, directional consistency, and error spread.

A bias correction is applied only after a proposed multiplicative factor has
been tested on at least two later rolling aftcasts and improves WAPE by at least
one percentage point. Structural methods fit and validate corrections only on
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

1. Test damped trend and robust observed-method ensembles against the current
   course-specific selection, using rolling selection rather than in-sample
   winners.
2. Evaluate hierarchical shrinkage so two-aftcast courses borrow strength
   without erasing course differences.
3. Add repeat-eligible and feeder-pass candidates only where the course logic
   supports them; do not add DFW as a universal multiplier.
4. Build the separate Fall specification from continuing Spring students plus
   archived admissions, acceptance, and orientation snapshots for new students.
5. Retain registration snapshots if pace or true peak-demand models become a
   priority. One final snapshot per term cannot recover blocked demand.

Every new method follows the same gate: designed fixture, rolling aftcasts,
real-data audit, schema and preview update, saved-bundle rebuild, full R suite,
then Docker and browser verification if the display contract changes.
