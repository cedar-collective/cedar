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
census/capacity. `recent_campus_history` (schema 24) holds each campus's own
first day for the recent same-season terms, beside the pooled `recent_history`. They are evidence about delivery mix, not
independent campus-demand forecasts. Branch campuses never enter this market.

A named course group is a monitoring scope, declared in the institution's
`projection_groups.csv` and `projection_courses.csv`. UNM's `critical_courses`
group contains the canonical Gen Ed list (`include_gen_ed`) plus the explicitly
monitored FYEX and gateway courses. Its always-monitored core is FYEX 1010,
1030, and 1110; MATH 1215, 1220, and 1350; BIOL 1140; CHEM 1215 and 1215L; and
ENGL 1110 and 1120. CHEM 1220 is not in the monitoring scope. The group is
restricted to ABQ and EA. Course membership uses exact `subject_course` values;
suffix variants are never included by prefix.

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

The model window begins at the institution's `projection_history_start_term`
(`settings.csv`; UNM: Spring 2022, `202210`); a course may start later through
`projection_courses.csv`. Earlier target
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
its one-term first-day retention are permitted, but the row has `accuracy`
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
first_day_enrl  = calc_first_day_enrl(): students holding a seat when classes began
census_enrl     = registered + dr_late
final_enrl      = registered
```

`first_day_enrl` is reconstructed from each row's Registration Status Date
against its section's first class day (`calc_first_day_enrl(..., pool_campuses
= TRUE)`, each student-course once across the pooled market). It is the
occupancy every seat judgment reads (0.21.0). It is `NA`, never a partial count,
for a course-term whose class lists carry no status dates (`first_day_basis =
"undated"`) or that has a session which had not begun when the class list was
pulled (`"sessions_pending"`, such as a second-half session; ISSUES.md I28). A
pending term also carries `first_day_started_enrl`, the count over the sessions
that had begun. Divided by all the scheduled seats it is a lower bound on fill,
so `projection_judged_first_day()` uses it only where it already reaches the
level being judged (the saturation floor, the pressure bump, the expansion
response), and the floor note says "at least"; below that level the term is
unknown and the note names the session not yet begun (0.25.0). Aftcast actuals
and displayed fills read `first_day_enrl` alone.
`class_list_status_date_coverage()` reports which terms lack dates, and Admin >
Data & Usage lists them; never name the terms in prose, because re-pulling a
term's class list fills its dates in.

**Intersession is out of the forecast (0.24.0).** `prepare_enrollment_projection_inputs()`
drops sections and class-list rows whose part of term is in
`intersession_parts_of_term` (`institution/<id>/settings.csv`; UNM's `INT`,
December sessions that belong to Fall) before anything reads them. A student in
both a regular and a December section counts once, by the regular one. An
intersession starts weeks after the term's first day, so its rows made a
course's first day unknown until December (ISSUES.md I28), and it registers
after a Fall settles, so its students read the Fall spine from a partial Fall
(I35).

Before market aggregation, repeated ABQ/EA rows are collapsed to one
student-course-term. A currently registered record wins over a drop record; a
late drop wins over an early drop. This status priority makes the equations
reconcile while preventing a section or modality change from becoming two units
of demand. An unfamiliar non-waitlist status is retained in
`other_non_waitlist` for audit rather than dropped or assumed to occupy a census
seat. Projection WAPE, signed bias, and method selection all use
`classlist_total`. First-day, census, and final enrollment are saved with each
aftcast for historical lifecycle comparison, but they are not alternative
scoring targets.

Sections and seat gaps are planned for registrations, not first-day seats
(0.23.0): projected registrations plus the feeder adjustment and any pressure
bump (below). Registrations run a median 8% above the first day, because a
student who drops early frees a seat someone else takes, and the margin is kept
on purpose: running short of seats costs more than an empty one. Over 207 past
aftcasts with a known first day, sizing on the first day would have planned
fewer seats than were filled on day one 61% of the time; sizing on
registrations, 32%, with seats short (3,877) and spare (3,867) in balance.
Most of those course-terms filled their seats, so the first day undercounts
what they needed; see `forecasting-lessons.md`.

### Pressure bump

A course near full on the first day (`saturation_fill_threshold`, 90%) in every
one of its last `pressure_bump_window` (3) same-season offerings with a known
first day, at least `pressure_bump_min_terms` (2) of them, is planned for more
than it registered last time:

```text
unserved          = max(pressure_bump_share x spine, students left waiting)
pressure_bump     = max(0, unserved - floor already in the published projection)
planned_registrations = max(0, projected_classlist_total
                               + plan_feeder_adjustment + pressure_bump)
recommended_sections  = ceiling(planned_registrations / reference_section_size)
```

`pressure_bump_share` is 0.05 (0.10 before 0.26.0): the median always-full
Fall 2026 course left 4.7% of its registrations waiting, and new sections need
instructors who may not exist. Feeders never cancel the bump (they did before
0.26.0, at a 5% fall): a backlog does not leave with them, and their change is
the plan's feeder adjustment instead. A term whose first day is unknown is
skipped, never read as full or not full.

The reason is that a near-full course's registrations follow its seats: given
10% or more seats they filled them (89 course-terms), held flat they stayed
flat (139), cut they fell by the cut (51). The 5% is an allowance, not a
measurement, and every row says which. `projection_pressure_bump()` writes
`pressure_judged_terms`, `pressure_full_terms`, `pressure_bump_applied`,
`pressure_bump`, and `pressure_bump_note` (why it applies or why not);
`add_projection_recommendations()` adds `planned_registrations` and
`pressure_bump_sections` (the sections it adds). The forecast, WAPE and the
accuracy axes never include it, because a full course's registrations are
capped and would score any allowance as over-projection.
`validate_pressure_bump_rows()` rejects a bundle whose plan is not projection
plus feeder adjustment plus bump or whose sections are not sized from the plan.
The page states the total above the table (`projection_pressure_bump_summary()`).

### Feeder adjustment (0.26.0; Spring plans only from 0.27.0)

The spine is a year old when the schedule is built. Where the rule publishes
it, a Spring plan still reads the Fall just finished, from the adjusted
candidate's own deltas (`projection_plan_feeder_adjustment()`):

```text
plan_feeder_adjustment = delta_sequence                      always
                       + delta_feeder  if |pooled feeder change| >= plan_feeder_change
                       = 0             if the published method is spine_adjusted
                       = 0             if the target's term_type is not in plan_feeder_seasons
```

`plan_feeder_seasons` is `"spring"`. Scored on the 0.26.0 bundles' past
forecasts, error weighted by course size:

| Rule | Spring targets (198 folds) | Fall targets (195 folds) |
|---|---:|---:|
| Spine alone | 14.71% | 12.78% |
| Spine + listed sequence | 13.85% | 12.78% |
| Spine + sequence + pooled feeders, always | 13.61% | 13.03% |
| Spine + sequence + pooled feeders at 5% | 13.60% | 13.01% |

A Fall feeder's change carries into Spring; a Spring feeder's does not carry
into Fall. Among Fall targets the pooled feeder delta pointed the way the
course moved in 97 of 194 folds (correlation -0.09), and where feeders moved
5% or more, following them raised error from 11.56% to 12.01%. The sequences
are weaker in that direction too: 41% of Spring MATH 1512 students take MATH
1522 in Fall and are 29% of its Fall students, against 59% and 67% from Fall
to Spring ([forecasting-lessons.md](forecasting-lessons.md)). A Fall plan's
note says the rule. The adjusted forecast candidate
keeps its deltas in both seasons, because it publishes only by beating the
spine on earlier aftcasts.

`plan_feeder_change` is 0.05. A listed predecessor (`projection_sequences.csv`)
counts every time, either way, because its students go straight into the next
course: 68% of Fall ENGL 1110 students took ENGL 1120 the next Spring, and they
were 71% of its Spring students. The pooled feeders are a looser set, ranked by
transitions, and a move under 5% is noise against the course's own year. At
the pooled carry-through rates, a 5% feeder move changes the median course by
3%: not everyone who could take it does, and the backlog apart from feeders is
the bump's. When the adjusted candidate is published, its projection already
holds both deltas, and the plan adds nothing (`validate_pressure_bump_rows()`
enforces it). Two steps out the term just finished is unobserved, so there is
nothing to read and the note says so.

Published rows gain `plan_feeder_adjustment`, `plan_feeder_note` (why it
applies or why not, with each part's arithmetic) and `plan_feeder_sections`
(the sections it adds or removes, before the bump's). The page states the total
(`projection_plan_feeder_summary()`) beside the bump's.

The sequence list is fixed today and applied at past folds too, so the rates
learned at a past fold use a list chosen with later knowledge. The pairs are
structural (a course and its continuation), so the look-ahead is mild, and the
selection rule's out-of-sample accuracy is unchanged in kind.

### Reliability, seat consistency, and where error comes from

The `accuracy` axis is shown to readers as **Reliability** (High within 10%
WAPE, Moderate to 20%, Low beyond; it was Close / Fair / Poor before 0.23.0).
The column keeps its name; only the values and the label changed.

`annotate_projection_fold_conditions()` tags every aftcast row with
`fold_seat_change` (the fold term's scheduled seats over the course's previous
same-season offering, minus one) and `fold_prior_near_full` (whether that
previous offering was near full on the first day; `NA` when its first day or
seats are unknown). Two summaries read them from the published rule's aftcasts
(`policy_selected`):

- `add_projection_seat_consistency()` gives each published row
  `seat_consistency`: High when the seats held within `seat_consistency_change`
  (10%) in every one of the course's reliability terms, Moderate when they moved
  in up to `seat_consistency_moderate_max_moves` (1), Low beyond, Unrated when no
  term can be compared; with `seat_consistency_reason`,
  `seat_consistency_terms` and `seat_consistency_moves`. Low reliability with
  High seat consistency is the forecast's own miss, flagged "Off 20%+ with
  steady seats"; with moving seats it is "Off 20%+ as seats moved".
- `summarize_projection_error_sources()` attributes each aftcast to one source
  -- seats changed 10%+, seat or first-day data missing, seats held while near
  full, seats held with room -- and sums the absolute error by source. The page
  renders it in **Where forecast error comes from**
  (`projection_error_sources_summary()`); the text preview prints it.

On the Spring and Fall 2027 bundles, 77% and 83% of the published rule's
aftcast error came from terms whose seats changed, and no Low-reliability
course had High seat consistency (the breakdown is in
`forecasting-lessons.md`).

### Draft schedule comparison

`build_enrollment_projection_draft_comparison(view)` sets each published row's
`planned_registrations` beside the target term's schedule as the bundle
captured it (`scheduled_sections`, `scheduled_capacity`, and per-campus
`delivery_components`), dated by the bundle's `target_schedule_as_of` (the
latest DESR `as_of_date` for the target term; `NA` when none is loaded). Each
course is one of: short of day-one seats (draft seats below
`projected_first_day_equivalent`), covering day one but short of the plan,
covering the plan, more than a section beyond it, or not in the draft. It is
arithmetic over saved rows: the bundle's refresh signature includes the
target-term sections, so a changed draft rebuilds the bundle at the next
refresh, and Shiny never refits to compare.

Expected first-day seats are still shown beside the plan, as context. For each
aftcast or current projection, CEDAR estimates a leakage-safe same-season
retention rate from earlier terms only, skipping any term whose first day
is unknown:

```text
first_day_retention_rate = sum(first_day_enrl) / sum(classlist_total)
projected_first_day_equivalent = projected_classlist_total
                              x first_day_retention_rate
```

The default uses up to four prior same-season terms with a known first day and
requires two. This converts gross registration demand into expected first-day
occupancy; it does not change the forecast target, determine whether
registration was constrained, or set the sections recommended. The target term's class-list snapshot is
kept outside training and supplies `target_classlist_total_to_date`,
`target_registered_now`, and drop counts to date. DESR supplies the schedule and
capacity only; its `total_enrl` is not a projection input or live-demand check.

Waitlists are not a method input. Class lists only began retaining waitlist rows
in 2026 (Summer 2026: 543; Fall 2026: 3,615); a past term's extract keeps only
students still waiting when it closed. There is no history yet to fit or test a
waitlist method against, so it cannot provide a defensible demand signal.

### Registration snapshots

The class lists and the draft schedule are overwritten by every refresh, and
neither can be rebuilt afterwards for a past week: a student who registered and
later dropped carries only the drop's status date, and a waiting student who got
a seat leaves no waitlist row. So the refresh keeps them.
`scripts/record-registration-snapshot.R` (run by `update-data.sh` after the
projection refresh) calls `record_registration_snapshot()`, which writes
`build_registration_snapshot()` for every term after the settled edge that has
a class list or a schedule to `output/registration-snapshots/`. It writes one
file per term per pair of class-list and schedule pulls, and skips a pair it
already holds.

Each row is one term, delivery campus, college, course and part of term. It
holds registered, waiting (the canonical rule), early and late drops, and active
sections and seats, with crosslists counted once at home. There are no student
IDs. Part of term is kept so a reader can leave out intersession. A source with
no pull for the term has `NA` counts, never zeros: before Spring registration
opens, its draft schedule is kept and its class-list counts are unknown.
Nothing reads the snapshots yet. They are the evidence a pace revision (this
week against the same week a year earlier) and a projection against the
submitted draft schedule would both need. Neither is useful until a year of
snapshots exists.

## Method Roles

Model 0.20.0 has two candidates and one idea: **seats needed is last year's
number, corrected for what can actually be seen**.

| Method | Role | What it is |
|---|---|---|
| Prior same-season | The spine, and the default | Last comparable season's class-list demand |
| Prior same-season + floor + Fall deltas | Challenger | The spine, raised to a floor when that term was saturated, plus two deltas read from the term just finished |

Reader-facing method descriptions live in
`CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE` beside the registry in
`R/lists/enrollment_projection_groups.R` (platform; the monitoring scopes it
reads are the institution's files); the page generates its accordion from
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
seats needed = spine + floor uplift + repeat delta + sequence delta + feeder delta

spine         prior same-season class-list total
floor uplift  if first-day fill of that term >= 90%:
              students still waiting at close who are on no campus's
              class list in the market; else 0
              (unknown first day: saturation cannot be judged, uplift 0)
repeat delta  (course enrollment in the preceding term
               - same a year earlier) x repeat rate
sequence delta for each listed predecessor (projection_sequences.csv):
               (its enrollment in the preceding term, excluding students
               also in this course - same a year earlier) x its own rate
feeder delta  (distinct enrollment across the feeder set in the preceding term,
               excluding students in this course or a listed predecessor
               - same a year earlier) x feeder rate
```

The rates are learned only from pairs (preceding term, following same-season
term) that precede the target, over the last four such pairs and at least
two. The repeat rate is the share of students in the course in the preceding
term who were in it again the following same-season term. The feeder set is
the up-to-eight courses whose preceding-term students most often took this
course next (at least three transitions over at least two pairs), and the
feeder rate is one pooled share across that set so a student in two feeders
counts once. A listed predecessor's rate is the share of its preceding-term
students who took this course next; its students leave the pool before the
feeder set is chosen, so the predecessor is never also a pooled feeder and a
student in both counts once, under the predecessor (0.26.0). **Both deltas read enrollments, not grades**, because grades are
not posted when the schedule is built; the rates embed the historical pass
and repeat behaviour, and the same terms can be re-read once grades land.

**The floor is in the spine's units (0.22.0).** The spine is the
ever-registered total, which already counts everyone who held a seat at any
point, early drops included. A student still waiting at close never held one,
so demand was at least the spine plus those students, and the uplift is
exactly their number. Until 0.22.0 the floor was first-day enrollment plus the
waitlist, compared with the spine. First-day enrollment leaves out the early
drops the spine counts, so the floor rose above the spine only when the
waitlist outnumbered the term's early-drop churn: on Fall 2027, 245 waiting
students in 36 saturated courses lifted the projection by 77, and 24 of those
courses not at all (ISSUES.md I27). `validate_spine_rows()` now rejects any
adjusted row whose uplift is not its waiting count when saturated and zero
otherwise.

The waiting count starts from the canonical class-list true-waitlist rule
(`R/branches/waitlist-demand.R`), which removes anyone registered in the same
delivery group. The market then removes anyone with a non-waitlist row on
either campus, because the class-list total already counts them: a student
holding an EA seat while waiting at ABQ survives the per-campus rule but is
not waiting in the pooled market (6 of 331 on Fall 2026). Class lists retain
waitlist rows only from Summer 2026, so a saturated earlier term says "no
waitlist rows retained" and the spine is itself the floor. That leaves the
floor almost no aftcast record: on the 0.22.0 bundles a handful of stray
Spring 2023 waitlist rows lift two Spring 2024 aftcasts by two students each,
and nothing else in either season's history reaches it. The
saturation test is `enrollment_capacity_metrics()` from `R/branches/enrl.R`
applied to first-day enrollment. Regstats' Saturation report still reads census
through `capacity_saturation_metrics()`, the same arithmetic on a different
lifecycle point; the two pages each say which they use.

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
"Plan N sections", or "Plan at least N sections; prior term was saturated"
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
| `first_day_equivalent_wape` | Error between projected first-day load and actual first-day enrollment, on terms where it is known |
| `capacity_censored_wape` | One-sided class-list error that does not penalize overprojection after registration reached capacity |
| `uncensored_wape` | Class-list WAPE only on terms whose registrations remained below capacity |

Historical capacity is marked reached when first-day occupancy filled 98% of
the seats or more:

```text
first_day_enrl / scheduled_capacity >= 0.98    (calc_first_day_enrl())
```

**98%, not 100%** (`CEDAR_FULL_FILL`, `R/lists/seat_fill.R`, shared with every page that calls a course full).
Capacity is pooled over every section, and a course with a few seats open
across many section times is full to the student choosing one: CHEM 1215
filled 682 of 690 seats on the first day of Spring 2026 (98.8%). At 98% a
50-seat course with one empty seat is full. On the 0.21.0 bundles the line
adds 12 Spring and 17 Fall course-terms of recent history to the reached set.

**It is not census either (0.21.0).** Census is the 15th day of instruction,
three weeks after the first day (the term calendar in `AGENTS.md`), and the
drops in between empty seats that were full on day one: on 598 ABQ+EA course-terms with a known first day, median fill was
98.9% on the first day and 95.6% at census, 46% of course-terms were full on
the first day against 15% at census, and 199 were full on day one but under
capacity at census. An unknown first day is unknown occupancy:
`capacity_usable` is FALSE and the term is neither reached nor unreached, so it
leaves `uncensored_wape` rather than counting as an unconstrained term.

**It is deliberately not `classlist_total >= scheduled_capacity`.** The
ever-registered total counts seat churn: every early drop freed a seat that
someone else took, so it exceeds capacity whenever a course turns over. On the
Spring 2027 audit it marked 72% of course-terms as capacity reached, while
census marked 17% and final enrollment 6%, and in 87 of those 284 "reached"
terms fewer than 85% of seats were still filled at the end. Every downstream
reading of the flag (the Capacity-bounded label, the capacity caveat, the
demand signal, the pressure screen's chronic-fill test) depends on it measuring
real occupancy. For a target term still filling, which has no first day yet,
the students registered right now are its occupancy. First-day enrollment above
the nominal cap still counts as reached; overrides do not turn a bounded observation into an
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
| `accuracy`, shown as Reliability | When we did aftcast it, how close were we? | High / Moderate / Low / Unrated | Yes |
| `seat_consistency` | Did the seats hold steady in those same aftcast terms? | High / Moderate / Low / Unrated | No |

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
(13 Close, 2 Fair, 0 Poor, in the labels of the time).

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
`depth_moderate_min_aftcasts` (3), Thin at 1-2, None at 0. `accuracy` is High
at or below `accuracy_close_max_wape` (10%), Moderate at or below
`accuracy_fair_max_wape` (20%), Low above, and Unrated below
`accuracy_min_aftcasts` (2) folds. Term-to-term error variation is reported in
the reason text rather than collapsing the rating, so a close-on-average but
inconsistent method is visible as such.

**The axes are allowed to disagree, and usually do.** Deep evidence spans High,
Moderate, and Low reliability; a Stable course may have Thin depth. The validator
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
confidence intervals, and they assume seats like last year's (ISSUES.md M35).
`summarize_projection_range_coverage()` rebuilds each past published forecast's
range from the course's earlier published forecasts only and counts how often
it held, split by whether that term's seats stayed within
`seat_consistency_change` of the year before; the page states both rates. On
the 2026-10-24 bundles (model 0.25.0) it held 86 of 105 Spring forecasts and
98 of 115 Fall forecasts with steady seats. Where seats moved it held 40 of 99
and 28 of 91. Most misses fell below the registrations. When the target's draft schedule moves the seats by that much
from last year's same term, the row's range carries
`projection_range_seat_notes()`'s "Draft seats +X% on <term>: the range assumes
steady seats". The range is not re-centred on the draft: registrations follow a
saturated course's seats, and no measured rule says by how much for the rest.

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
| List | `R/lists/enrollment_projection_groups.R` | Method registry and schema/model versions; reads the institution's course groups from `projection_groups.csv` / `projection_courses.csv` and the window start from `settings.csv` |
| Branch | `R/branches/enrollment-projections.R` | Inputs, the spine and adjusted candidates, pressure, aftcasts, rolling selection, recommendation, persistence |
| Cone | `R/cones/enrollment-projections.R` | One question: projection and section need for the screened scope |
| Feature | `R/features/enrollment-projections.R` | Explicit-cutoff orchestration, Spring-only publisher guard, artifact loader, filtered reusable view payload, content fingerprints, model-source provenance, and canonical text preview |
| Module | `R/modules/enrollment-projections.R` | Read-only Registration page over the saved feature payload |
| Script | `scripts/build-enrollment-projections.R` | Clean-process artifact publication |

Future modules and Course Dynamics must call the feature/cone or read the saved
bundle. They must not reproduce a model, backtest, pressure calculation, or
recommendation pipeline.

## Saved Bundle

Model 0.27.0 keeps schema 25. The model config gains `plan_feeder_seasons`,
and `validate_pressure_bump_rows()` takes it and rejects a feeder adjustment on
a row whose target season is not listed.

Schema 25 (model 0.26.0) adds the listed-predecessor delta: candidates gain
`delta_sequence`, `sequence_courses` and `sequence_change` (published as
`adjusted_delta_sequence`, `adjusted_sequence_courses`,
`adjusted_sequence_change`), and `validate_spine_rows()` includes it in the sum.
Published rows gain `plan_feeder_adjustment`, `plan_feeder_note` and
`plan_feeder_sections`; `planned_registrations` includes the feeder adjustment.
The model config gains `sequences` and `plan_feeder_change` and drops
`pressure_bump_feeder_decline`; `pressure_bump_share` is 0.05.

Schema 24 (model 0.25.0) adds `recent_campus_history`: the recent history's
terms again, one row per delivery campus that offered the course, with that
campus's `scheduled_sections`, `scheduled_capacity`, `first_day_enrl`,
`first_day_basis` and `first_day_fill` (each student counted once within the
campus). It never feeds a projection. It keeps a campus full on the first day
visible beside one with room, which pooling the market hides (ISSUES.md M36):
the summary flag "EA full last term, ABQ had room" compares the latest term's
complete campus first days at the two seat-fill levels, read live. Published
rows gain `adjusted_prior_first_day_basis` (`complete`, `sessions_begun`,
`sessions_pending`, `undated`, `no_capacity`), so a prior term full on the
first day is flagged full rather than near full, and an unknown prior fill
names its cause. Validation requires each campus row to belong to a
recent-history term, once.

Schema 22 (model 0.23.0) sizes `recommended_sections`, `seat_gap`,
`projected_over_capacity`, the capacity notes, and the recommendation from
`planned_registrations` (registrations plus the pressure bump) instead of
expected first-day seats; `projected_first_day_equivalent` and its range columns
are unchanged and shown as context. Published rows gain
`pressure_judged_terms`, `pressure_full_terms`, `pressure_bump_applied`,
`pressure_bump`, `pressure_bump_note`, `planned_registrations`, and
`pressure_bump_sections`, and `seat_consistency`, `seat_consistency_reason`,
`seat_consistency_terms`, `seat_consistency_moves`; candidates gain
`feeder_change_rate` and `feeder_check`, published as
`adjusted_feeder_change_rate` and `adjusted_feeder_check`; aftcasts gain
`fold_seat_change` and `fold_prior_near_full`; the bundle gains
`target_schedule_as_of`. The `accuracy` values become High / Moderate / Low.

Model 0.22.0 keeps schema 21. Its `floor_uplift` is the spine-unit floor, and
`waitlisted_prior` counts only students on no campus's class list in the
market (ISSUES.md I27); `validate_spine_rows()` enforces that the two agree.

Schema 21 (model 0.21.0) judges and sizes seats on the first day of classes.
The market enrollment history gains `first_day_enrl` (and its
`prepare_projection_market_enrollment_history()` takes `sections` for the start
dates); aftcasts and `recent_history` carry `actual_first_day` beside
`actual_census`; `recent_history` fills become `first_day_fill` /
`first_day_capacity_gap`; and every `census_retention_*` and
`*_census_equivalent*` column is renamed `first_day_retention_*` /
`*_first_day_equivalent*`, because sections are now sized for day-one
occupancy. The per-campus `delivery_components` keep their census columns,
which are labelled as census and only audit the market rollup.

Schema 20 (model 0.20.0) has two candidates and no calibration columns. Each
candidate row carries the model's audit fields (`spine`, `spine_term`,
`saturated_prior`, `prior_first_day_fill`, `waitlisted_prior`, `floor_uplift`,
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
and `census_fill` / `census_capacity_gap` (recent history) because they then
measured census occupancy. It drops `selection_uses_uncensored` and every
`feeder_*` column. Published rows size `recommended_sections` and `seat_gap`
from the occupancy equivalent, not the class-list headline: ever-registered
runs about 13% above census at the median, and sizing from it had recommended
596 sections against 505 scheduled for the same courses on a demand estimate
only 5% above their capacity. Schema 16 and later store the named market, exact course and campus scopes,
campus/part-term delivery components, metadata, source fingerprints, the full
effective model configuration, the pressure screen, published projections,
every current candidate, every aftcast row, method performance, and a normalized
four-term `recent_history` audit table. Each audit row stores the actual
ever-registered total, first-day enrollment, census enrollment, final/last-day
enrollment, sections, capacity, first-day fill, the aftcast the rolling rule would have
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
first-day-equivalent, cap-censored, and uncensored WAPE, signed bias and error
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
  fit. A damped trend and a pooled growth factor were tested on the 0.21.0
  aftcasts and both did worse than prior same-season (Forecasting Lessons).
- About two-thirds of the aftcast error moves with the schedule, one
  registrant per seat. A projection conditioned on the submitted draft
  schedule is the largest open improvement; it needs that schedule archived.
- A censored count model is the principled next latent-demand candidate once
  the capacity contract is reliable.
- Registration-pace models require retained historical snapshots; the current
  one-snapshot-per-term data cannot support them.
