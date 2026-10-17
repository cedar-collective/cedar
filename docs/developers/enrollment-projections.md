---
title: Enrollment Projection Architecture
parent: Developer Guide
nav_order: 10
---

# Enrollment Projection Architecture

CEDAR's enrollment projections are a reusable, non-UI computation and saved-data
contract. The first pass projects only an explicit course scope, evaluates every
method with rolling-origin aftcasts, and publishes one versioned bundle for Shiny
and other CEDAR features to read.

The computation does not run in a module and does not read global data. This is
deliberate: method development and artifact publication must remain testable in
a vanilla R process without loading or restarting Shiny.

## Production refresh

The morning refresh automatically checks projection freshness after successful
data transformation. `config/enrollment-projections.yml` defaults to the next
Spring after the settled enrollment edge, with that edge as the historical
cutoff and `critical_courses` as the scope. It can pin explicit terms or disable
automatic builds; the process never guesses an edge when data timing is missing.

The feature builder prepares the same inputs used by the analyses, normalizes
row ordering, and compares their content hash, model-source hashes, configuration,
and scope with the saved bundle. Missing, invalid, legacy-without-freshness, or
changed bundles rebuild. Unchanged bundles skip fitting and are not rewritten.
File timestamps and raw extract dates do not themselves cause rebuilds. The
prepared inputs include upstream populations, target registrations, and scheduled
capacity, so changes to those can legitimately refresh the saved output too.
This is a data preparation check, not a zero-cost check, but it runs outside
Shiny and does not refit or aftcast unchanged models.

An optional `output/projections/rebuild-request.yml` still forces one build with
explicit terms and scope and is cleared on success. The following refresh returns
to the configured policy; pin terms in the policy for a continuing override.
Failures preserve the old artifact and are reported to the scheduler; the next
successful data refresh retries automatically.

### Deploy-time model gate

Shiny never fits a model, so a bundle saved by older code is not replaced just
because new code shipped. A schema or scoring change would otherwise leave the
Projections page on its empty state until the next morning refresh, or until
someone remembered to rebuild by hand.

`.github/workflows/deploy.yml` closes that gap. After the health check passes it
runs `scripts/build-enrollment-projections.R --refresh-if-model-changed`, which
calls `enrollment_projection_model_drift()` to compare the saved bundle's
recorded schema version, model version, and per-file model source hashes against
the deployed source. It loads **no CEDAR table**: a no-change deploy costs about
a second, against roughly four minutes for a real rebuild, and most deploys touch
no projection source at all.

The gate owns **model** staleness only. Data-driven staleness stays with the
morning refresh, which still runs the full signature comparison including
`inputs_sha256` over the prepared inputs. Anything unreadable, invalid, or
predating provenance tracking counts as drift — failing towards a rebuild is
correct, because the alternative is serving a page built by unknown code.

It never fails the deploy. The app is already serving by that point; a failure
leaves the previous bundle in place, is reported in the deploy log, and is
retried by the next morning refresh. A concurrent morning refresh holds the
build lock, so the deploy's attempt exits with that message rather than racing
it.

Because the gate reads the hashes of every file in
`enrollment_projection_model_source_files()`, editing any of them — including
the refresh feature itself — correctly triggers one rebuild on the next deploy.

Use `scripts/restart-cedar.sh --update` for the morning refresh plus app reload.
The builder runs outside Shiny with a temporary writable output mount; normal
Shiny startup continues to consume saved bundles only. Rebuild for a new target
or cutoff, corrected historical inputs, or changed model/policy/scope. Retain
deliberately published official vintages under `output/projections/vintages/`
with unique dated names and production backups; only `*-latest.qs` is replaceable.
See [the scripts guide](https://github.com/cedar-collective/cedar/blob/main/scripts/README.md)
for the policy, force-rebuild, immediate-check, and retry commands.

## Grain and Scope

Every result is keyed by:

```text
market_id + subject_course + term_type + target_term
```

`college` and `department` remain descriptive metadata, not projection keys.
The named `abq_ea_course_market` is a deliberate exception to the normal campus
grain: ABQ and EA are treated as substitutable deliveries because online
enrollment is strongly governed by the seats offered. The market class list
counts each student-course once across both campuses and total capacity is pooled.

The underlying delivery rows are not discarded. `delivery_components` remains
keyed by:

```text
market_id + campus + college + subject_course + part_term + target_term
```

Those rows describe where seats are allocated and the prior comparable
census/capacity. They are evidence about delivery mix, not
independent campus-demand forecasts. Branch campuses never enter this market.

A named course group is a monitoring scope. The initial `critical_courses`
group contains the canonical `gen_ed_all` list plus the explicitly monitored
FYEX and gateway courses. Its always-monitored core is FYEX 1010, 1030, and
1110; MATH 1215, 1220, and 1350; BIOL 1140; CHEM 1215 and 1215L; and ENGL 1110
and 1120. CHEM 1220 is not in the monitoring scope. The group is restricted to
ABQ and EA. Course membership
uses exact `subject_course` values; suffix variants are never included by
prefix.

There is no implicit user scope because CEDAR has no login identity. A caller
must supply courses, campuses, and a named market, directly or through a course
group. Future department controls must resolve department codes through
`cedar_lookups$subject_lookup` before calling the feature builder.

The inexpensive pressure screen runs before student-level methods. It can retain
courses because they are always monitored, have a historical capacity
shortfall, show repeated high class-list registration fill, or have growth beyond scheduled
capacity. The always-monitored core proceeds to student-level methods and
aftcasts on every build; the remainder of the broad Gen Ed scope must pass the
pressure screen. An explicit ad hoc course request is also forced through for
diagnosis. The saved screen includes the number of recent terms with usable
capacity, the number at or above the fill threshold, every pressure flag, and a
plain-language reason. Excluded rows therefore say, for example, `1 of 3 recent
spring terms with class-list registrations at or above 90% of scheduled
capacity` and whether target capacity was
available for the other checks. A pressure-only scope with no included courses
publishes a valid zero-row bundle.

## Comparable History Window

The standard model window begins with Spring 2022 (`202210`). Earlier target
enrollments, capacities, transitions, and aftcasts are excluded so
pandemic-era behavior cannot silently influence accuracy or method selection.
The immediately preceding source term may still support a structural transition
into the first eligible target; for Spring 2022 that source is Fall 2021. It is
a source population, not an older target outcome.

The requested `as_of_term` must be at or before
`cedar_data_edges(students)$last_enrolled_complete`. The bundle builder fails
closed when it cannot determine that edge or when the requested source term is
still filling. This prevents an advance-registration snapshot from being
treated as a completed upstream population.

Course-specific curriculum breaks can move the floor later. MATH 1215 begins
with Fall 2025 (`202580`), when the current high-enrollment curriculum appears.
Earlier small MATH 1215 offerings are not comparable, and MATH 1215X/Y/Z are
not folded into the base course. For a Spring 2027 forecast this leaves Spring
2026 as the only same-season MATH 1215 observation. The prior-Spring method and
its one-term census retention are permitted, but the row has `accuracy`
`Unrated` and `depth` `Thin` until the current curriculum accumulates at least
two aftcasts.

Both the general floor and course exceptions are saved in `model_config`. The
validator rejects saved recent-history or aftcast rows that precede the
effective course window.

## Enrollment Target

The primary target is the **first-day / ever-registered class-list proxy**:
every unique non-waitlisted student who appeared on the course class-list
extract as registered, an early drop, a late drop, or another auditable status.
Because CEDAR retains a final/current status rather than frozen roster snapshots,
this is not a literal first-day count. It is the closest recoverable gross
registration-demand measure:

```text
classlist_total = registered + dr_early + dr_late + other_non_waitlist
census_enrl = registered + dr_late
final_enrl = registered
```

Before market aggregation, repeated ABQ/EA rows are collapsed to one
student-course-term. A currently registered record wins over a drop record; a
late drop wins over an early drop. This status priority makes the equations
reconcile while preventing a section or modality change from becoming two units
of demand. An unfamiliar non-waitlist status is retained in
`other_non_waitlist` for audit rather than dropped or assumed to occupy a census
seat. Projection WAPE, signed bias, and method selection all use
`classlist_total`. Census and final enrollment are saved with each aftcast for
historical lifecycle comparison, but they are not alternative scoring targets.

Census enrollment remains a secondary occupancy measure. For each aftcast or
current projection, CEDAR estimates a leakage-safe same-season retention rate
from earlier terms only:

```text
census_retention_rate = sum(census_enrl) / sum(classlist_total)
projected_census_equivalent = projected_classlist_total
                              x census_retention_rate
```

The default uses up to four prior same-season terms and requires two. This
converts gross registration demand into expected census occupancy; it does not
change the forecast target, determine whether registration was constrained, or
reduce the seats recommended for registration. The target term's class-list snapshot is
kept outside training and supplies `target_classlist_total_to_date`,
`target_registered_now`, and drop counts to date. DESR supplies the schedule and
capacity only; its `total_enrl` is not a projection input or live-demand check.

Waitlists are not a method input. Class lists only began retaining waitlist rows
in 2026 (Summer 2026: 543; Fall 2026: 3,615); a past term's extract keeps only
students still waiting when it closed. There is no history yet to fit or test a
waitlist method against, so it cannot provide a defensible demand signal.

## Method Roles

Model 0.20.0 has two candidates and one idea: **seats needed is last year's
number, corrected for what can actually be seen**.

| Method | Role | What it is |
|---|---|---|
| Prior same-season | The spine, and the default | Last comparable season's class-list demand |
| Prior same-season + floor + Fall deltas | Challenger | The spine, raised to a floor when that term was saturated, plus two deltas read from the term just finished |

Reader-facing method descriptions live in
`CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE` beside the registry in
`R/lists/enrollment_projection_groups.R`; the page generates its accordion from
that catalog and a registry test keeps the two in step.

### Why this shape

Two measurements on the 0.19.0 Spring 2027 bundle decided it (the full audit
is in [Forecasting Lessons](forecasting-lessons.html)):

- **The error lives where the schedule moved.** Over 238 rolling aftcasts,
  terms whose capacity held within 10% of the prior Spring aftcast at 6.1%
  WAPE; terms with 10% or more seats added at 23% (enrollment followed the
  seats, bias -22%); terms with seats cut at 39% (bias +38%). Seventy-seven
  percent of all error sat in the moved-capacity terms. A same-season baseline
  cannot see a schedule that has not been written, but it can see when the
  previous one was full.
- **A Spring roster is 86% continuing students, 7% new entrants, 5% repeaters
  after a Fall DFW, 2% returners.** Last Spring's count already carries the
  steady state of all four. Replacing the continuing block with population
  times take-rate gained 0.6 points; the components only add information when
  a Fall driver changed from the year before.

So the published number is the spine, moved only where something measurable
moved: the prior term was clipped by its seats, the course's own Fall
enrollment changed, or its feeders' Fall enrollment changed.

### The adjusted candidate

```text
seats needed = spine + floor uplift + repeat delta + feeder delta

spine         prior same-season class-list total
floor uplift  if census fill of that term >= 90% (the Regstats saturation
              definition): max(0, census + waitlisted - spine); else 0
repeat delta  (course enrollment in the preceding term
               - same a year earlier) x repeat rate
feeder delta  (distinct enrollment across the feeder set in the preceding term
               - same a year earlier) x feeder rate
```

The rates are learned only from pairs (preceding term, following same-season
term) that precede the target, over the last four such pairs and at least
two. The repeat rate is the share of students in the course in the preceding
term who were in it again the following same-season term. The feeder set is
the up-to-eight courses whose preceding-term students most often took this
course next (at least three transitions over at least two pairs), and the
feeder rate is one pooled share across that set so a student in two feeders
counts once. **Both deltas read enrollments, not grades**, because grades are
not posted when the schedule is built; the rates embed the historical pass
and repeat behaviour, and the same terms can be re-read once grades land.

The waitlist in the floor is the canonical class-list true-waitlist count
(`R/branches/waitlist-demand.R`), rolled up per market term. Class lists
retain waitlist rows only from Summer 2026, so a saturated earlier term says
"no waitlist rows retained" and the spine is itself the floor. The
saturation test is `capacity_saturation_metrics()` from `R/branches/enrl.R`,
the same function Regstats uses, so "saturated" means one thing in both
places.

Beside a floor the bundle reports the market's **expansion response**: among
same-season pairs before the target whose prior term was saturated and whose
capacity then grew 10% or more, the median share of the added seats that
filled (93% on the Spring 2027 build, 44 pairs). It is context for a reader
deciding whether to add seats, not a multiplier, because the question is how
many seats are needed rather than what a hypothetical expansion would fill.

A **regime check** flags any course whose own enrollment in the preceding term
moved 25% or more from the year before. It does not change the number; it
tells a reader to look (FDMA 2110 rebounded from 106 to 355 in Fall 2026 and
the 0.18.0 engine published 106).

### What a Fall target gets

The floor needs only the prior same-season term and applies to either season.
The deltas read the term immediately before the target; two steps past the
settled edge that term is unobserved, so a Fall bundle built from a Fall edge
carries the spine and the floor and says "Preceding term ... is not observed
yet" for the deltas. Which season holds which horizon alternates through the
year:

| Settled edge | One step out (deltas available) | Two steps out (spine and floor only) |
|---|---|---|
| a Fall term | next Spring | next Fall |
| a Spring term | next Fall | next Spring |

**Both current targets are pre-schedule.** Spring 2027 and Fall 2027 carry
`target_schedule_available = FALSE` for every row, so capacity-derived
comparisons are unavailable rather than zero and the recommendation reads
"Plan N section(s)", or "Plan at least N section(s); prior term was saturated"
when the floor applies.

## Capacity Censoring

A full course records enrollment up to the seats the institution made available;
it does not reveal how many additional students would have enrolled. Ordinary
forecast error therefore rewards a naive method for reproducing a historical cap
and can punish a structural estimate for projecting above an unknown ceiling.

CEDAR retains four accuracy views:

| Metric | Meaning |
|---|---|
| `wape` | Ordinary error against actual class-list total; used when the history is not mostly capacity-reached |
| `census_equivalent_wape` | Error between projected census-equivalent load and actual census enrollment |
| `capacity_censored_wape` | One-sided class-list error that does not penalize overprojection after registration reached capacity |
| `uncensored_wape` | Class-list WAPE only on terms whose registrations remained below capacity |

Historical capacity is marked reached when census occupancy filled the seats:

```text
census_enrl >= scheduled_capacity          (census_enrl = registered + dr_late)
```

**It is deliberately not `classlist_total >= scheduled_capacity`.** The
ever-registered total counts seat churn: every early drop freed a seat that
someone else took, so it exceeds capacity whenever a course turns over. On the
Spring 2027 audit it marked 72% of course-terms as capacity reached, while
census marked 17% and final enrollment 6%, and in 87 of those 284 "reached"
terms fewer than 85% of seats were still filled at the end. Every downstream
reading of the flag (the Capacity-bounded label, the capacity caveat, the
demand signal, the pressure screen's chronic-fill test) depends on it measuring
real occupancy. For a target term still filling, which has no census, the
students registered right now are its occupancy. Census above the nominal cap
still counts as reached; overrides do not turn a bounded observation into an
unbounded one.

For a reached-capacity term, the observed class-list total is treated as a lower
bound on demand. The one-sided scored projection is:

```text
if capacity_reached and projected_classlist_total > actual_classlist_total:
    capacity_censored_classlist_projection = actual_classlist_total
else:
    capacity_censored_classlist_projection = projected_classlist_total
```

This preserves the full penalty for underprojection while declining to call an
above-observed estimate wrong when registration was bounded. A 0% cap-censored
error means that overprojection cannot be established; it does **not** prove
that latent demand was predicted exactly. Raw WAPE, cap-censored WAPE,
uncensored WAPE, bias, and exact aftcast terms remain visible together.
User-facing tables do not render that technical zero as `0.0%`. They label the
term `Capacity-bounded`, and an all-bounded accuracy window appears as
`Capacity-bounded (n/n)`. Mixed windows report the bounded count and identify
the numerical cap-censored WAPE as a minimum rather than an observed error.

The class list records everyone who registered but has no timestamps from which
to reconstruct peak concurrent occupancy. `classlist_total >= capacity` is
therefore CEDAR's operational historical ceiling signal, not a claim that the
exact minute of constraint is known. Retained registration snapshots or usable
waitlists would be required to measure blocked demand directly.

## Retired candidates

The registry once held nine candidates: three same-season baselines, a
student-level feeder-transition estimator, two Spring population methods, and
50/50 blends of each upstream signal with prior same-season. 0.19.0 retired the
undamped trend (+11.7% bias), the feeder estimator (+35% bias) and its blend,
and the population blend (a duplicate at correlation 1.000). 0.20.0 retired the
seasonal median, the raw and blended preceding-term ratio, both Spring
population methods and the anchored cohort blend: every one sat within 0.3 WAPE
points of the spine or lost to it under rolling selection. The feeder idea
survives as a delta, not a level estimator. The Spring cohort-cell preparation
went with the population methods; `cohort_composition` stays because the
growth scenario depends on it. The figures are in
[Forecasting Lessons](forecasting-lessons.html).

## Aftcasting and Selection

Backtests are rolling-origin evaluations. For each historical target, every
candidate receives only terms and student populations that precede that target.
The current target and future rows never enter training.

Accuracy is method- and course-market-specific. Every candidate and published
row stores `target_term`, `target_term_label`, `n_backtests`, the exact comma-
separated `backtest_terms`, their readable labels, and `backtest_term_range`.
Any UI showing WAPE must display this context at the row level; a percentage
without its evaluated terms is not an interpretable accuracy claim.

### Selection is rolling, and the published accuracy is out of sample

**Prior same-season is the default for every course.** A challenger replaces
it for a target only when, on at least `selection_min_backtests` (3) earlier
aftcast terms the two share, the challenger's WAPE was lower by at least
`selection_challenger_margin` (two points). Three, not two: replayed on the
0.19.0 Spring 2027 bundle with two shared folds, 26 challengers were live on
the 2026 fold and scored 11.4% where the default scored 8.2% on the same
courses; with three, the rule's realised record equals the default's.

**The same rule is replayed at every historical fold** with only the folds
before it, and the accuracy published for a course (`n_backtests`, `wape`,
the Depth and Accuracy axes, the prediction interval) is the realised error of
the method the rule would have picked at each fold. The saved `backtests`
carry `policy_selected`, and the recent-history table shows, for each past
term, the method that would have been live then. The published row's
`selection_common_n`, `selection_default_wape` and `selection_challenger_wape`
record the evidence that made the current pick; a default pick has none.

This replaced in-sample selection on 2026-10-16. The 0.18.0 engine chose the
minimum-WAPE method on the folds all eligible methods shared, which the
seasonal-trend candidate shrank to two terms for 80 of 83 courses, and then
reported the winner's WAPE on those same folds. Measured on the Spring 2027
bundle: the published picks scored 13.7% in-sample, the same rule replayed
rolling scored 16.5%, and prior same-season alone scored 15.9%. A rule that
cannot beat the default out of sample does not get to replace it, and a
`selection_wape` that is lower than the rule could have delivered is not a
number a reader should see. `tests/testthat/test-enrollment-projections.R`
guards this with a fixture where the in-sample winner's fit is 2% and the
honest record is 8%.

Sparse rows (no prior same-season at all) fall back to the first applicable
observed baseline and say so.

### Three axes, not one label

A single `confidence` label was retired on 2026-09-07. It fused three
independent questions into one word and then reported the worst of them, so a
reader could not tell which had failed. Every row in the production scope came
back `Low` or `None`, including courses whose enrollment had barely moved in
five years and which aftcast to within 2%.

| Axis | Question | Values | Needs a model? |
|---|---|---|---|
| `stability` | Is this course predictable from its own history at all? | Stable / Moderate / Volatile / Unrated | **No** |
| `depth` | How much comparable aftcast evidence stands behind the selected method? | Deep / Moderate / Thin / None | No |
| `accuracy` | When we did aftcast it, how close were we? | Close / Fair / Poor / Unrated | Yes |

**`stability` is measured with no model**, from the coefficient of variation of
the course's own comparable class-list series over `demand_history_window`
terms: Stable at or below 10%, Moderate at or below 25%, Volatile above, and
Unrated below `stability_min_terms` (default 3) comparable terms. Median and
maximum year-over-year change are carried beside it, because a single structural
break and steady churn produce similar CVs and call for different responses.

That independence is the point: stability is publishable for a course the
aftcast machinery cannot rate at all, which on a build where the upstream
population has not settled is most of the scope. It is also predictive rather
than merely descriptive — on the Spring 2027 build its CV correlates r = 0.69
with realised aftcast error, and **no course rated Stable was forecast Poorly**
(13 Close, 2 Fair, 0 Poor).

A `Volatile` rating is a finding, not a failure. A course whose enrollment
swings 50% year to year is one where something is moving, and the swing is what
deserves attention.

**`depth` and `accuracy` read the rolling-selection record** (`n_backtests`,
`wape` on the published row): how many folds the rule published and how far
those published aftcasts missed. For a course where the default was never
beaten that is prior same-season's own record; where a challenger took over it
is the mixed record a reader would actually have lived through. Since 0.19.0
`selection_wape` and `selection_n_backtests` are the same figures, so a row
carries one accuracy number. (The retired single label failed in part by
reading a common-fold count that topped out at 2 against thresholds written for
a per-method count that reached 4, so Medium and High were unreachable.)

`depth` is Deep at `depth_deep_min_aftcasts` (4) folds, Moderate at
`depth_moderate_min_aftcasts` (3), Thin at 1-2, None at 0. `accuracy` is Close
at or below `accuracy_close_max_wape` (10%), Fair at or below
`accuracy_fair_max_wape` (20%), Poor above, and Unrated below
`accuracy_min_aftcasts` (2) folds. Term-to-term error variation is reported in
the reason text rather than collapsing the rating, so a close-on-average but
inconsistent method is visible as such.

**The axes are allowed to disagree, and usually do.** Deep evidence spans Close,
Fair, and Poor accuracy; a Stable course may have Thin depth. The validator
checks each axis against its own vocabulary separately, because a shared check
would have to accept every value on every axis and would catch nothing.

Qualifications are reported beside, rather than folded invisibly into, these
axes. A mostly capacity-reached history says that fit is to observed class-list
enrollment and cannot validate latent demand. A regime check says the term just
finished moved sharply. Material disagreement between the two candidates is
also named. The summary table compresses this to a short phrase; the course
spotlight preserves the full interpretation.
Prediction intervals use the selected method's historical 80th-percentile
absolute error. These are empirical planning intervals, not formal probabilistic
confidence intervals.

### Signed error

WAPE remains unsigned. It answers how far projections missed in aggregate and
cannot honestly carry a plus or minus sign:

```text
WAPE = sum(abs(projected - actual)) / sum(actual)
```

The companion `weighted_bias` records direction using the same denominator.
Each method row also stores the standard deviation of its term-level
percentage errors, over- and underprediction rates, `direction_consistency`,
and a readable `signed_error_history`. A row-level interface should show WAPE
and bias together, followed by the exact aftcast terms.

**Bias correction was retired in 0.20.0.** The rolling multiplicative
calibration needed four training aftcasts plus two validation trials, and
five comparable Springs never supplied them: zero rows were ever corrected.
The floor and deltas correct the spine in the two places the audit found it
wrong, which is a narrower and more defensible adjustment than a learned
multiplier.

## Code Ownership

| Layer | File | Responsibility |
|---|---|---|
| List | `R/lists/enrollment_projection_groups.R` | Course groups, method registry, schema/model versions |
| Branch | `R/branches/enrollment-projections.R` | Inputs, the spine and adjusted candidates, pressure, aftcasts, rolling selection, recommendation, persistence |
| Cone | `R/cones/enrollment-projections.R` | One question: projection and section need for the screened scope |
| Feature | `R/features/enrollment-projections.R` | Explicit-cutoff orchestration, Spring-only publisher guard, artifact loader, filtered reusable view payload, content fingerprints, model-source provenance, and canonical text preview |
| Module | `R/modules/enrollment-projections.R` | Read-only Registration page over the saved feature payload |
| Script | `scripts/build-enrollment-projections.R` | Clean-process artifact publication |

Future modules and Course Dynamics must call the feature/cone or read the saved
bundle. They must not reproduce a model, backtest, pressure calculation, or
recommendation pipeline.

## Saved Bundle

Schema 20 (model 0.20.0) has two candidates and no calibration columns. Each
candidate row carries the model's audit fields (`spine`, `spine_term`,
`saturated_prior`, `prior_census_fill`, `waitlisted_prior`, `floor_uplift`,
`floor_basis`, `preceding_term`, `preceding_term_change`, `regime_alarm`,
`delta_repeat`, `repeat_rate`, `delta_feeder`, `feeder_rate`,
`feeder_courses`, `delta_basis`), and `validate_spine_rows()` rejects an
adjusted row whose parts do not sum to its projection. Every published row
carries the adjusted candidate's evidence as `adjusted_*` columns whichever
candidate the rule selected, plus the expansion response and the floor and
regime notes, so the detail can show them for every course. The inputs gain
`waitlist_history`; `student_inputs$course_enrollments` returns for the
deltas. Schema 19 (model 0.19.0) added `policy_selected` on `backtests`, the per-fold
`aftcast_method_id` / `aftcast_method_label` on `recent_history`, the rolling
selection evidence columns on `projections`, a `preceding_term_history` input,
and renames the capacity columns to `capacity_fill` / `capacity_gap` (backtests)
and `census_fill` / `census_capacity_gap` (recent history) because they now
measure census occupancy. It drops `selection_uses_uncensored` and every
`feeder_*` column. Published rows size `recommended_sections` and `seat_gap`
from `projected_census_equivalent`, not the class-list headline: ever-registered
runs about 13% above census at the median, and sizing from it had recommended
596 sections against 505 scheduled for the same courses on a demand estimate
only 5% above their capacity. Schema 16 and later store the named market, exact course and campus scopes,
campus/part-term delivery components, metadata, source fingerprints, the full
effective model configuration, the pressure screen, published projections,
every current candidate, every aftcast row, method performance, and a normalized
four-term `recent_history` audit table. Each audit row stores the actual
first-day / ever-registered proxy, census enrollment, final/last-day enrollment,
sections, capacity, census fill, the aftcast the rolling rule would have
published that term and which candidate it was, signed error, the
capacity-censored flag and score, prior same-season enrollment/capacity changes,
and a typed potential-miss explanation. Schema 16 also attaches the preceding
term's all-campus university headcount, pooled projection-market headcount,
first-semester freshman count, and course DFW count/rate. DFW values are capped
at the derived graded edge. The post-hoc repeat count joins canonical DFW
students to same-course enrollment in the immediately following non-summer
term; it is explicitly diagnostic and never enters a candidate formula. It is
a recreated current-method aftcast, not a claim
that CEDAR published that method in the historical term. Saving the effective
configuration records defaults as well as caller overrides, including history
floors and selection thresholds. Candidate rows mark the selected method and
retain method role, applicability, evidence size, class-list WAPE,
census-equivalent, cap-censored, and uncensored WAPE, signed bias and error
history, and the spine / floor / delta audit fields listed above. The validator
rejects an adjusted row whose components do not reconcile or whose spine term
does not precede its target.

The validator rejects cutoff/target inversions, rows outside the saved course,
campus, or market scope, duplicate market rows, duplicate delivery components,
component totals that do not reconcile to market capacity, target-term
mismatches, and disagreement between a published method and its selected
candidate. Publication writes a temporary file and atomically renames it into
place.

`model_version` identifies the calculation contract; it changes when a formula,
method-selection rule, calibration rule, or threshold changes. `schema_version`
identifies the saved-file shape and can change without changing the estimates.
Model 0.17.0 excludes AUD from DFW and repeat-demand signals even when the
registration status is DG/DW. Rebuild older bundles before using them with this
model; validation rejects their older model version. The saved schema is unchanged.
Every schema-16 bundle also stores the Git commit when available, whether any
model source file differed from that commit, SHA-256 hashes, and an embedded
normalized copy of the source files that define the model. Validation recomputes
the hashes before a bundle can be read. This makes a dirty development artifact
inspectable, while official production artifacts should still be built from a
clean commit.

Routine development and UI recomputation replace
`enrollment-projections-TARGET-latest.qs`; they do not create permanent forecast
vintages. Retain an official vintage only through a deliberate `--output`
publication action when its numbers are used for a scheduling decision. A
materially revised decision can create another labeled vintage. The eventual
outcome record should reference that official forecast; an automatic archive
of every code run is explicitly out of scope.

Docker mounts the repository's gitignored `output/` directory read-only at the
same path inside the app. The one writable mount belongs to the
`cedar-projections` Compose service, which publishes bundles; a `--volume` on a
`docker compose run` against the app service does not override the app's
read-only mount, so the publisher runs as its own service. Publish the latest
bundle on the host before starting or restarting CEDAR; the UI does not write
artifacts. An absent or invalid bundle produces an explicit empty state instead
of a model run.

`format_enrollment_projection_preview()` renders the validated bundle as a
stable Markdown/text table containing the current projections and up to four
same-season evidence rows per course. It is the fast development view and the
table-contract reference for the Shiny module. The formatter performs no
model computation, and the module consumes the bundle's typed
`projections` and `recent_history` tables rather than parsing the text output.

The course detail also consumes typed `backtests` rows to plot every applicable
method against the three enrollment-lifecycle measures. The feature layer
filters these rows to the course's term type and builds the plot; the Shiny
module does not recompute methods or reshape model data.

The enrollment-movement accordion is built from the typed diagnostic columns
on `recent_history`. Student-term population signals are deduplicated before
counting. Course outcomes flow through `classify_enrollment_outcomes()`, so the
default passes only A+ through C and CR; every other recorded non-audit outcome
plus a non-audit late drop is DFW, while early drops never are. AUD is excluded
even under late-drop status; a blank/NA late-drop grade still counts as a
withdrawal. The feature layer
builds the schedule/upstream/DFW narrative and presentation table; the module
only renders that payload. Correlation is descriptive: schedule changes can be
a response to demand, so the UI never labels it a causal capacity effect.

Registration > Projections lists saved bundles with
`find_enrollment_projection_bundles()`, loads the reader's chosen target term
with `load_enrollment_projection_bundle()`, and filters it through
`build_enrollment_projection_view()`. It never runs a candidate method, aftcast,
calibration, or pressure screen. `server.R` owns the path and the file read; the
module receives a discovery reactive and a loader function. Course Dynamics must
reuse that same loader/view boundary when projections are added there.

Discovery is season-aware because CEDAR publishes **one bundle per season**. A
Fall 2027 and a Spring 2027 projection are both current and neither supersedes
the other, so a loader must name a season (`load_latest_enrollment_projection_bundle(dir, "fall")`)
or an exact target term. The earlier "highest saved target term" rule would have
made the first published Fall bundle silently hide Spring from every reader.

## Population Growth Scenarios

A dean asks "if health professions grows 10% a year for five years, how many
students and sections will the critical courses need?" That question is answered
by `build_enrollment_projection_scenario()` (`R/features/enrollment-projection-scenario.R`)
as **arithmetic over rows the bundle already carries**. Nothing fits, aftcasts,
calibrates, or selects a model in a user session — the same rule that governs the
projection page, and also what makes the scenario fast enough to explore.

### What the bundle saves for it

`cohort_composition` (schema 18) records, per published course, the baseline
roster counted by each student's **same-term** `major_code` and
`student_classification`. The baseline term is the most recent comparable
same-season term at or before the cutoff — the same comparability rule the
projection methods use, so the composition describes the term the projection is
anchored to. Students with no program row that term are kept with
`major_code = NA`: they really are in the seats, and dropping them would stop the
composition summing to the course total.

Per-term `Major` is one of the fields the reliability contract marks safe, which
is why the composition can be attributed to a past term at all.

### The arithmetic, and the assumption it rests on

```text
pop_cohort   = baseline students whose major_code is in the population
year 1       = the published projection, unchanged
year k       = year 1 + pop_cohort * ((1 + g)^(k-1) - 1)
sections_k   = ceiling(year k / reference_section_size)
```

The assumption, stated on the page rather than implied: **the population's
headcount grows at the given rate and its students keep taking each course at
today's rate; everyone else in the course is held flat.** A course whose baseline
roster is 13% health-professions students therefore moves 1.3% when that
population grows 10%. The share is displayed per course, because a reader who
cannot see it will assume the whole course grew.

Section sizing goes through `projection_sections_for_demand()` /
`projection_additional_sections()`, shared with the bundle builder, so a scenario
at 0% growth cannot disagree with the projection it is anchored on.

### Honesty rules

- **Year 1 is the published projection at any growth rate.** Growth applies to
  the years after the target term.
- Later years are labeled `Scenario`, carry **no** accuracy axes, and never
  borrow year 1's. No aftcast has been run against a hypothetical.
- A course whose population cohort is below `min_population_cohort` (default 10)
  is **listed with a reason** rather than dropped or shown as zero — a thin
  population must read as thin evidence, not as an absence of demand.
- A course with no published projection to grow from is listed the same way.

### Named populations

Groups live in `CEDAR_POPULATION_GROUPS` (`institution/<id>/population_groups.csv`, read by `R/lists/population-presets.R`) and are
shared with Pathways, so "health professions" means one thing across CEDAR. They
declare **program names**; `population_group_major_codes()` resolves those to
Banner codes through two mechanisms, because neither is complete:

| Mechanism | Catches | Misses |
|---|---|---|
| Name match | A pre-major carrying its major's name (`FRAD` / `RADS`), including codes Banner added after the list was written | A pre-major whose name has drifted |
| `leads_to` (programs.csv) | A drifted pre-major whose row leads to the right major | A pre-major with no `leads_to` |

Both once failed on the same row for `FMDL` ("Medical Laboratory Science"
against `MEDL`'s "Medical Laboratory Sciences", with no canon entry). Its
`programs.csv` row now leads it to `MEDL`, and the registry still lists both
spellings and `population_group_audit()` reports `near_miss`
names. Run that audit when adding a group. ISSUES.md I7 documents the live
mapping defect this work uncovered.

**Measured on real data** (Fall 2026 baseline, 139-course scope): the clinical
group resolves to 27 codes and holds 4,358 of 27,982 seats — 15.6% — across
1,576 of 11,440 students. A hand-listed code set omitting `FRAD`, `FDEH`, `FEMS`
and `FMDL` would have missed 1,281 of those seats.

### Real-data audit of the saved composition

The check the designed fixtures cannot make: `cohort_composition` keys on
`cedar_students$major_code` while a population group resolves against
`cedar_programs$major_code`. If those vocabularies disagreed, every cohort would
silently be zero and the scenario would report a flat line as a finding. They
agree:

| | Spring 2027 | Fall 2027 |
|---|---|---|
| Composition rows / courses | 6,028 / 83 | 7,016 / 90 |
| Students counted | 17,467 | 23,451 |
| Baseline terms used | 202310–202610 (Springs) | 202380–202680 (Falls) |
| Rows with `major_code = NA` | 0 | 0 |
| Composition rows matching the clinical group | 718 | 774 |
| Students matched | 2,767 | 3,471 |

Each course takes its own most recent comparable term as its baseline, which is
why four baseline terms appear rather than one, and every one is in the target's
season.

Fall 2027 at 10% annual growth, always-monitored scope — 11 courses scaled, none
excluded. The spread is the reason the share column exists:

| Course | Population in course | Share | Fall 2027 | Fall 2031 |
|---|---:|---:|---:|---:|
| BIOL 1140 | 475 | 68.5% | 684 | 904 |
| MATH 1350 | 290 | 25.0% | 1,161 | 1,296 |
| ENGL 1110 | 412 | 18.6% | 2,219 | 2,410 |
| CHEM 1215 | 113 | 12.8% | 915 | 967 |

The same 10% assumption moves BIOL 1140 by 32% and CHEM 1215 by 5.7%, because
the population is 68.5% of one course and 12.8% of the other. A reader shown only
the demand column would reasonably assume both grew 10%.

## Development and Release

Use `scripts/cedar-repl.R` for repeated real-data work, then re-source only the
changed files. Publish in a clean process with:

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202710 \
  --as-of-term 202660 \
  --group critical_courses
```

Inspect the working artifact without starting Shiny:

```r
source("scripts/cedar-repl.R")
bundle <- read_enrollment_projection_bundle(
  "output/projections/enrollment-projections-202710-latest.qs"
)
print_enrollment_projection_preview(
  bundle,
  courses = c("MATH 1215", "CHEM 1215")
)

# List the saved model files and hashes, then inspect exact saved source.
enrollment_projection_model_source(bundle)
cat(enrollment_projection_model_source(
  bundle, "R/branches/enrollment-projections.R"
))

# This path form remains available after CEDAR has moved to a newer schema.
cat(enrollment_projection_model_source(
  "output/projections/official-spring-2027.qs",
  "R/branches/enrollment-projections.R"
))
```

Focused fixture and architecture tests live in
`tests/testthat/test-enrollment-projections.R` and
`tests/testthat/test-architecture.R`. The projection browser suite exercises
the saved-bundle table, filters, and row evidence through
`./run-tests.sh --e2e enrollment-projections`; the release gate remains
`./run-tests.sh --all`.

Model research findings, failed assumptions, and current real-data benchmarks
are maintained separately in
[Forecasting Lessons](forecasting-lessons.html). That file records evidence;
the live backlog remains in `ROADMAP.md`.

## Known Limits and Next Methods

- Structural estimates are signals, not identified latent-demand counts.
- The class list has no registration timestamps, so capacity reached is an
  operational signal rather than a recovered peak-occupancy observation.
- Method selection can be unstable with only two or three aftcasts; the rolling
  rule limits the damage (a challenger needs two shared folds and a two-point
  margin) but pooled or hierarchical shrinkage should be evaluated before
  expanding the scope.
- A robust ensemble of the observed baselines may improve class-list demand
  fit; a damped trend was not tried after the undamped one was retired.
- A censored count model is the principled next latent-demand candidate once
  the capacity contract is reliable.
- Registration-pace models require retained historical snapshots; the current
  one-snapshot-per-term data cannot support them.
