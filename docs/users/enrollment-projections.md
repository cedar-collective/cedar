---
title: Enrollment Projections
parent: User Guide
nav_order: 4.5
---

# Enrollment Projections
{: .fs-9 }

**Saved course-demand projections with visible historical evidence**
{: .fs-6 .fw-300 }

---

Open **Registration > Projections** to inspect the latest validated demand
artifacts for the pooled ABQ and EA course market. The page
includes courses in the Gen Ed monitoring scope that passed the pressure screen
plus the always-monitored FYEX and gateway list. Branch campuses are not
included.

CEDAR publishes **one projection per season** — a Spring target and a Fall
target — and neither replaces the other. Use **Target term** to choose which one
you are reading; the page opens on the nearest one, and the scope stripe always
names the term actually loaded. The two are not directly comparable as forecasts
of the same thing: the nearer target can read the term that has already
happened for its Fall deltas, while the further one carries the spine and the
saturation floor alone. A further-out target therefore shows thinner evidence
depth and no deltas — which means that evidence was unavailable, not that
nothing changed.

The page opens to **Always monitored**. Use **Target term**, **Course group**,
**Department**, **Course**, **Stability**, and **Aftcast accuracy** to narrow the
saved rows. The table expands to
show every matching row and scrolls with the page. These controls do not fit or
rerun a model. The download button exports the current filtered table. Expand
**How projections work and how to read the table** for an in-page methodology
and column guide.

{% include definition-summary.html id="enrollment-projection" %}

## Scenario: growing a population

The **Scenario** sub-tab answers a planning question the projection table cannot:
*if one group of students grows, what happens to the courses they take?*

Pick a **Population** (for example, Health Professions (Clinical)), an annual
**growth** rate, and a **horizon**, and the table shows each course year by year
— as students, as sections needed, or as sections beyond what is scheduled today.

Three things to know before quoting a number from it:

- **The first year is the published projection**, unchanged, whatever growth rate
  you choose. Growth applies to the years after it.
- **Later years are arithmetic, not forecasts.** They carry no aftcast accuracy,
  because no aftcast has ever been run against a hypothetical. They answer "what
  would this course need if that growth happened", not "what will happen".
- **Only the chosen population grows.** Every other student in the course is held
  flat. That is why each row shows the population's **share** of the course: 10%
  growth on a course that is 13% health-professions students is a 1.3% change in
  that course, not 10%.

A course whose population cohort is too small to scale is listed underneath with
the reason rather than dropped, so a thin population reads as thin evidence and
not as an absence of demand.

Below the summary table, expand **Projection methods** for the method map.
There are two candidates:

- **Prior same-season**, the spine and the default: last comparable season's
  class-list demand. When the schedule holds still it is within about 6%.
- **Prior same-season + floor + Fall deltas**: the same number, raised to
  census plus the waitlist when that term was saturated (census filled 90% or
  more of the seats), plus the change in the course's own enrollment and in
  its feeder courses' enrollment during the term just finished, each scaled by
  the share that historically carried into this course. It uses Fall
  enrollments, not grades, because grades are not posted when the schedule is
  built.

**Prior same-season is the default for every course.** The adjusted candidate
replaces it only after beating it by a margin on earlier aftcast terms the two
share. The rule is replayed at every past term with only the evidence available
then, so the accuracy you see is what that rule would actually have delivered,
not the fit of the winner on the terms that chose it. The **Why** column gives
the evidence behind the current method.

The page opens with a **By department** table: sections and seats summed over
the courses in view. That total is more reliable than any one course, because
course errors largely offset, and it is the number a dean negotiates. The
**Only courses that need a look** box narrows the course table to rows that
were full last term, moved sharply in the term just finished, or whose past
forecasts were more than 20% off.

| Column | Meaning |
|---|---|
| **Sections** | Seats filled at census divided by the section size (the target schedule's average when it exists, otherwise the recent median), rounded up. "Plan at least" when last term filled its seats. |
| **Seats** | Students expected to be filled at census: registrations times the course's historical class-list-to-census retention. |
| **Likely range** | Where past forecasts for this course usually landed, as seats at census. |
| **vs last** | Change on last year's same-term registrations. |
| **Flags** | Plain-language reasons to look: full last term, students left waiting, a big change in the term just finished, a volatile history, past forecasts well off, or the two candidates disagreeing. |
| **Trend** | The last four same-term enrollments as a sparkline; hover for the numbers and sections. |
| **Stability** | Stable, Moderate, Volatile, or Unrated: whether the course is predictable from its own history at all, measured with no model |
| **Depth** | Deep, Moderate, Thin, or None: how many comparable rolling-selection aftcasts stand behind the published method |
| **Accuracy** | Close, Fair, Poor, or Unrated: how close those aftcasts landed, as an out-of-sample record |
| **Registrations** | First-day / ever-registered proxy: unique non-waitlisted students found in the class-list extract, including students who later dropped. This is the aftcast target, but it is not a frozen first-day roster. |
| **Basis** | Prior same-season unless the adjusted candidate beat it on earlier shared aftcasts |
| **Why** | The evidence behind the basis: "Default" or the challenger's earlier record against prior same-season |

Selecting a row opens with one sentence that says what to plan and why, then
the evidence behind it. The method plot, movement diagnostic, and candidate
table sit under **Analyst detail**.

Select a row to compare every forecasting method against historical first-day /
ever-registered, census, and final/last-day enrollment. The plot is restricted
to the selected target's term type: Spring is compared only with prior Spring
terms, Fall only with Fall, and Summer only with Summer. Method selection, WAPE,
and the accuracy axis are judged against the first-day / ever-registered proxy;
census and final enrollment provide lifecycle context rather than alternative
accuracy targets.

The detail also shows the last four same-season enrollments, sections,
capacity, census fill, the method the selection rule would have published that
term and its aftcast, signed error, capacity-bounded status, and potential
explanation. Three rows describe the adjustment whichever candidate was
published: **Saturation floor** (whether the prior term was full, the waitlist
left on it, and what happened the last times saturated courses in this market
were given more seats), **Fall deltas** (the enrollment changes and
carry-through rates behind the repeat and feeder terms), and **Regime check**,
which flags a course whose own enrollment in the term just finished moved 25%
or more from the year before. The check changes nothing; it says look. Its full **What this means** text separates historical fit from
structural caveats: a method can fit observed enrollment consistently while a
seat ceiling still prevents that fit from proving unconstrained demand.
The detail summary also retains the full planning recommendation, bias-correction
status, and population-fit evidence removed from the compact summary table.
The candidate-method table beneath it shows every
observed and structural estimate, including methods that were not selected.
Use **Back to projection table** above the evidence to return to the main list.

Expand **Enrollment movement diagnostic** in the course detail to compare each
same-season enrollment movement with scheduled capacity and three possible
upstream indicators from the preceding term: enrolled-student population, pooled
ABQ/EA market population, and first-semester freshman population. These are
distinct enrolled students in the class-list data, not official institutional
headcount measures. The diagnostic
also reports the course's canonical DFW count/rate in that preceding term and,
after the fact, how many of those students enrolled in the same course in the
following term. A DFW source term beyond the graded data edge is shown as
unavailable rather than calculated from partial grades.

These comparisons are clues, not attribution. Capacity may have followed
anticipated demand; university growth may affect courses unevenly; and the
next-term repeater count is known only after that next term begins. The signals
remain diagnostic because leakage-safe testing did not justify adding separate
incoming-freshman or DFW forecasting methods.

The context stripe states the target, historical data window, pooled campus
scope, and model version. Hover the information icon beside the model version
to see its Git state. The saved artifact carries hashes and the exact normalized
model source for analyst audit and future comparisons.

`Capacity-bounded` means census enrollment filled the scheduled seats that
term, so an estimate above the observed first-day / ever-registered proxy
cannot be fully judged as an error. It does not mean zero error, and
ever-registered demand above capacity on its own does not make a term
capacity-bounded: seats that turned over were never all occupied at once. `Potential explanation` identifies measured changes
that coincide with a miss; it is not a causal claim.

The page is a planning aid rather than an automatic scheduling decision. Review
stability, depth, accuracy, capacity status, and recent evidence before acting
on a section recommendation.
