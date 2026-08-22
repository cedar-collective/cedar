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

Course-specific curriculum breaks can move the floor later. MATH 1215 begins
with Fall 2025 (`202580`), when the current high-enrollment curriculum appears.
Earlier small MATH 1215 offerings are not comparable, and MATH 1215X/Y/Z are
not folded into the base course. For a Spring 2027 forecast this leaves Spring
2026 as the only same-season MATH 1215 observation. The prior-Spring method and
its one-term census retention are permitted, but the row has confidence None
until the current curriculum accumulates at least two aftcasts.

Both the general floor and course exceptions are saved in `model_config`. The
validator rejects saved recent-history or aftcast rows that precede the
effective course window.

## Enrollment Target

The primary target is **unique class-list demand**: every student who appeared
on the course class list as registered, an early drop, or a late drop. Waitlist-
only rows are excluded:

```text
classlist_total = registered + dr_early + dr_late + other_non_waitlist
census_enrl = registered + dr_late
```

Before market aggregation, repeated ABQ/EA rows are collapsed to one
student-course-term. A currently registered record wins over a drop record; a
late drop wins over an early drop. This status priority makes the equations
reconcile while preventing a section or modality change from becoming two units
of demand. An unfamiliar non-waitlist status is retained in
`other_non_waitlist` for audit rather than dropped or assumed to occupy a census
seat. Projection WAPE, signed bias, calibration, and method selection all use
`classlist_total`.

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

Waitlists are not a method input. Current waitlist data are all zero and cannot
provide a defensible demand signal.

## Method Roles

The candidate registry intentionally separates two analytical jobs:

| Method | Role | Interpretation |
|---|---|---|
| Prior same-season | Observed enrollment | Last comparable season; the naive benchmark |
| Seasonal median | Observed enrollment | Stable center of recent comparable seasons |
| Seasonal trend | Observed enrollment | Linear trend across recent comparable seasons |
| Spring population growth | Structural demand | Prior Spring matched cohort propagated by growth in all preceding-Fall students |
| Spring cohort flow | Structural demand | Prior Spring course cohort propagated by preceding-Fall major/classification growth |
| Feeder transitions | Structural demand | Student-level prior-course transitions, deduplicated across feeders |

Observed methods estimate the recorded class-list series. Structural methods ask
whether the current student population implies more course taking than the
recorded history alone suggests. They are not interchangeable targets.

The Spring cohort-flow model starts with the immediately prior Spring course
roster. It looks up those students' major and classification in the preceding
Fall, measures how each of those Fall population cells changed one year later,
and applies empirically shrunk cell-growth ratios to the matched course cohort.
Students in the baseline Spring course who were not present in the preceding
Fall are carried forward as a separate component. This includes prior Spring
entrants and returning-after-absence students without pretending that Fall
population growth describes them.

The Spring population-growth model uses the same prior Spring matched and
unmatched decomposition, but applies one growth ratio from all students in the
preceding Fall instead of separate major/classification cells. It is a deliberate
broad-population comparator. The bundle stores both methods' projections,
aftcast counts, WAPE, and WAPE difference. `coupling_status` records whether the
evidence favors `Broad population`, `Major/classification`, is `Mixed` within
two WAPE points, or remains `Insufficient evidence`. This is saved evidence, not
a UI-time model choice.

The feeder model uses the maximum learned transition probability for a student
appearing in multiple selected feeders, then adjusts for historical feeder
coverage. No structural method uses frozen cumulative-credit fields.

### Separate Spring and Fall Specifications

The shared engine has season-specific candidates rather than one universal
model. `spring_cohort_flow` is inapplicable to Fall and Summer targets. Its
calculation is:

```text
projected matched cohort
  = sum(prior Spring matched major/class count
        x smoothed preceding-Fall population growth)

projected Spring class-list total
  = projected matched cohort
  + prior Spring unmatched count
```

The current Fall source includes all students appearing on class lists, including new
Fall freshmen and transfers. Only students absent from that Fall need the
unmatched component. The initial unmatched method is deliberately simple: carry
forward the prior count. A separate Spring-entry model should be added only if
blocked aftcasts show that the component is material, variable, and predictable.

Fall will receive its own specification after Spring is stable. It should split
the observed Spring continuing population from the incoming Fall cohort and use
archived admissions/acceptance/NSO snapshots for the latter. The two seasons
share persistence, validation, and display contracts, not fitted formulas.

## Capacity Censoring

A full course records enrollment up to the seats the institution made available;
it does not reveal how many additional students would have enrolled. Ordinary
forecast error therefore rewards a naive method for reproducing a historical cap
and can punish a structural estimate for projecting above an unknown ceiling.

CEDAR retains four accuracy views:

| Metric | Meaning |
|---|---|
| `wape` | Ordinary error against actual class-list total; used for method selection |
| `census_equivalent_wape` | Error between projected census-equivalent load and actual census enrollment |
| `capacity_censored_wape` | One-sided class-list error that does not penalize overprojection after registration reached capacity |
| `uncensored_wape` | Class-list WAPE only on terms whose registrations remained below capacity |

Historical registration capacity is marked reached when:

```text
classlist_total >= scheduled_capacity
```

This comparison deliberately ignores later census attrition. A course that
filled during registration remains capacity reached even if many students
dropped before day 15. Registrations above the nominal cap also remain capacity
reached; overrides do not turn a bounded observation into an unbounded one.

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

## Paired Demand Evidence

CEDAR does not average the observed and structural methods. There is not yet a
validated conversion from a structural population estimate to unmet seats, and
a weighted average would create false precision.

Each published row instead carries:

- the best-scoring observed-enrollment baseline;
- broad-population, Spring cohort-flow, and feeder estimates with all three
  accuracy views;
- the broad-versus-major/classification coupling label and WAPE difference;
- recent usable and registration-capacity-reached term counts;
- same-season enrollment slope;
- evidence that enrollment followed a historical capacity increase;
- a conservative demand-signal label and an explanation.

`Possible latent demand` requires a structural estimate meaningfully above the
seasonal baseline, at least two recent terms that reached registration capacity, and rising observed
enrollment. Agreement by at least two structural methods produces a stronger label. A
high structural estimate without capacity/growth corroboration is explicitly
`Structural estimate uncorroborated`.

A structural method can contribute to those labels only when it has at least
three aftcasts, at least 40% cohort/feeder coverage, and no more than 20%
class-list WAPE on either all observations or the unconstrained subset. A good
cap-censored score alone never establishes credibility because an
arbitrarily high estimate can fit a capped observation. Each method's
credibility flag and the number of credible structural methods are saved.

The selected projection and confidence describe fit to **class-list demand**.
The demand signal is separate evidence for planning and human review.

## Aftcasting and Selection

Backtests are rolling-origin evaluations. For each historical target, every
candidate receives only terms and student populations that precede that target.
The current target and future rows never enter training.

Accuracy is method- and course-market-specific. Every candidate and published
row stores `target_term`, `target_term_label`, `n_backtests`, the exact comma-
separated `backtest_terms`, their readable labels, and `backtest_term_range`.
Any UI showing WAPE must display this context at the row level; a percentage
without its evaluated terms is not an interpretable accuracy claim.

The published demand method is the applicable **observed-enrollment** candidate
with the lowest course-market WAPE and at least two comparable backtests.
Structural-demand methods remain visible beside it and may inform the demand
signal, but cannot silently replace the observed class-list estimate even when
their historical WAPE is lower. Sparse rows fall back to the first applicable
observed method and remain visible. Confidence is High with at least four
aftcasts and at most 10% WAPE, Medium with at least three and at most 15%, Low
with at least two and at most 20%, and None otherwise. Rows with no applicable
observed method also remain explicit with confidence None and a reason.

Confidence combines aftcast count, ordinary WAPE, and structural-method coverage.
The text preview also shows cap-censored and uncensored WAPE so a bounded history
cannot look like precise validation.
Prediction intervals use the selected method's historical 80th-percentile
absolute error. These are empirical planning intervals, not formal probabilistic
confidence intervals.

### Signed Error and Calibration

WAPE remains unsigned. It answers how far projections missed in aggregate and
cannot honestly carry a plus or minus sign:

```text
WAPE = sum(abs(projected - actual)) / sum(actual)
```

The companion `weighted_bias` records direction using the same denominator:

```text
weighted_bias = sum(projected - actual) / sum(actual)
```

Positive bias means systematic overprojection; negative bias means
underprojection. Each method row also stores the standard deviation of its
term-level percentage errors, over- and underprediction rates,
`direction_consistency`, and a readable `signed_error_history` such as
`Spring 2023: +8.1%; Spring 2024: +7.4%`. Errors within one percentage point are
neutral when direction consistency is calculated. A row-level interface should
show WAPE and bias together, followed by the exact aftcast terms; WAPE alone
cannot distinguish a correctable offset from an unstable model.

Calibration is a guarded multiplicative adjustment, not an automatic bias
subtraction. The proposed factor is:

```text
sum(actual classlist total) / sum(raw projected classlist total)
```

By default a course-method pair becomes a calibration candidate only with at
least four eligible aftcasts, absolute weighted bias of at least 5%, at least
75% of directional errors pointing the same way, and a factor between 0.75 and
1.25. Historical calibrated aftcasts are strictly rolling: the factor for each
target is fitted only on earlier targets. The current projection is adjusted
only after at least two such rolling trials improve WAPE by at least one
percentage point.

Structural-demand methods have an additional censoring guard. Both factor
fitting and rolling validation use only terms with usable capacity that did not
reach the registration ceiling. Full terms may contain unmet demand, so they
cannot teach or validate a downward correction to a major/classification or
feeder estimate. Observed-enrollment methods may use all terms because
reproducing the observed class-list series is their stated job.

The bundle always preserves `raw_projected_classlist_total` alongside the exact effective
`calibrated_projected_classlist_total`, whole-student `projected_classlist_total`,
`calibration_factor`, `calibration_adjustment`, validation metrics, and a
human-readable reason. Method selection continues to rank the uncalibrated
observed-method WAPE; calibration changes the selected method's current value
only after its independent rolling check passes.

The canonical preview labels this state `Bias correction`, never the ambiguous
`Calibration: None`. An applied correction includes both its multiplier and
whole-student adjustment, for example `Applied x0.912 (-42 students)`. Stable
bias awaiting enough leakage-safe trials appears as
`Pending validation: 0/2 trials`; other rows give the reason the correction was
not applied. The displayed class-list demand is the corrected value when a
correction has passed validation, while the bundle retains the raw value for
audit.

## Code Ownership

| Layer | File | Responsibility |
|---|---|---|
| List | `R/lists/enrollment_projection_groups.R` | Course groups, method registry, schema/model versions |
| Branch | `R/branches/enrollment-projections.R` | Inputs, methods, pressure, aftcasts, selection, demand context, persistence |
| Cone | `R/cones/enrollment-projections.R` | One question: projection and section need for the screened scope |
| Feature | `R/features/enrollment-projections.R` | Explicit-cutoff orchestration, artifact loader, filtered reusable view payload, data fingerprints, model-source provenance, and canonical text preview |
| Module | `R/modules/enrollment-projections.R` | Read-only Registration page over the saved feature payload |
| Script | `scripts/build-enrollment-projections.R` | Clean-process artifact publication |

Future modules and Course Dynamics must call the feature/cone or read the saved
bundle. They must not reproduce a model, backtest, pressure calculation, or
recommendation pipeline.

## Saved Bundle

Schema version 12 stores the named market, exact course and campus scopes,
campus/part-term delivery components, metadata, source fingerprints, the full
effective model configuration, the pressure screen, published projections,
every current candidate, every aftcast row, method performance, and a normalized
three-term `recent_history` audit table. Each audit row stores actual class-list
demand, actual census enrollment, sections, capacity, registration fill, the current selected
method's leakage-safe aftcast, calibration status, signed error, the
capacity-censored flag and score, prior same-season enrollment/capacity changes,
and a typed potential-miss explanation. It is a recreated current-method aftcast, not a claim
that CEDAR published that method in the historical term. Saving the effective
configuration records defaults as well as caller overrides, including history
floors, calibration thresholds, and factor bounds. Candidate rows mark the selected method and retain
method role, applicability, evidence size, coverage, class-list WAPE,
census-equivalent, cap-censored, and uncensored WAPE, signed bias and error history, raw and
calibrated values, the calibration factor, and rolling validation evidence.
They also retain typed Spring audit
fields: baseline and source terms, baseline class-list total, matched and unmatched
baseline counts, both projected contributions, source-population totals and
growth, and the projection formula. The validator rejects a Spring row whose
components do not reconcile or whose source terms do not precede its target. It
also rejects a calibration whose raw value, factor, adjustment, and effective
projection do not reconcile.

The validator rejects cutoff/target inversions, rows outside the saved course,
campus, or market scope, duplicate market rows, duplicate delivery components,
component totals that do not reconcile to market capacity, target-term
mismatches, and disagreement between a published method and its selected
candidate. Publication writes a temporary file and atomically renames it into
place.

`model_version` identifies the calculation contract; it changes when a formula,
method-selection rule, calibration rule, or threshold changes. `schema_version`
identifies the saved-file shape and can change without changing the estimates.
Every schema-12 bundle also stores the Git commit when available, whether any
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
same path inside the app. Publish the latest bundle on the host before starting
or restarting CEDAR; the UI does not write artifacts. An absent or invalid
bundle produces an explicit empty state instead of a model run.

`format_enrollment_projection_preview()` renders the validated bundle as a
stable Markdown/text table containing the current projections and up to three
same-season evidence rows per course. It is the fast development view and the
table-contract reference for the Shiny module. The formatter performs no
model computation, and the module consumes the bundle's typed
`projections` and `recent_history` tables rather than parsing the text output.

Registration > Projections calls `load_latest_enrollment_projection_bundle()`
once per session and filters it through `build_enrollment_projection_view()`.
It never runs a candidate method, aftcast, calibration, or pressure screen.
Course Dynamics must reuse that same loader/view boundary when projections are
added there.

## Development and Release

Use `scripts/cedar-repl.R` for repeated real-data work, then re-source only the
changed files. Publish in a clean process with:

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202710 \
  --as-of-term 202680 \
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
- Method selection can be unstable with only two or three aftcasts; pooled or
  hierarchical shrinkage should be evaluated before expanding the scope.
- A damped seasonal trend or robust ensemble may improve class-list demand fit.
- A censored count model is the principled next latent-demand candidate once
  the capacity contract is reliable.
- Registration-pace models require retained historical snapshots; the current
  one-snapshot-per-term data cannot support them.
