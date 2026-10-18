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

### Seats are judged on the first day of classes

Whether a course was full is read on the **first day of classes**: the students
holding a seat when classes began, reconstructed from each student's
registration and drop dates. A course counts as full when 98% or more of its
seats were taken that day. Census comes on the 15th day of classes (the third
Friday), after three weeks of drops, so a course that turned students away on
day one can read 95% at census. Sections
are planned for first-day seats for the same reason: everyone in the room on
day one needs one. Some terms' class lists were exported without status dates,
so their first day is unknown; **Admin > Data & Usage** lists which. Those terms
show a dash and are never judged full or not full; they are not filled in from
census.

Below the table, expand **Projection methods** for the method map. There are
two candidates:

- **Prior same-season**, the spine and the default: last comparable season's
  class-list demand. When the schedule holds still it is within about 6%.
- **Prior same-season + floor + Fall deltas**: the same number, raised to
  first-day enrollment plus the waitlist when that term was saturated (90% or
  more of the seats filled on the first day), plus the change in the course's
  own enrollment and in its feeder courses' enrollment during the term just
  finished, each scaled by the share that historically carried into this
  course. It uses Fall enrollments, not grades, because grades are not posted
  when the schedule is built.

**Prior same-season is the default for every course.** The adjusted candidate
replaces it only after beating it by a margin on earlier aftcast terms the two
share. The rule is replayed at every past term with only the evidence available
then, so the accuracy you see is what that rule would actually have delivered,
not the fit of the winner on the terms that chose it. A course's detail gives
the evidence behind its current method.

The **Only courses that need a look** box narrows the course table to rows that
were full on the first day last term, moved sharply in the term just finished,
or whose past forecasts were more than 20% off.

The table is sized to fit a laptop window:

| Column | Meaning |
|---|---|
| **Course** | The course, with its department beneath. |
| **Sections** | Day-1 seats divided by the section size (the target schedule's average when it exists, otherwise the recent median), rounded up. "Plan at least" when last term filled its seats. |
| **Seats (day 1)** | Students expected to hold a seat when classes begin: registrations times the share of this course's registrants still enrolled on the first day in recent terms. Beneath it, the range past forecasts for this course usually landed in. |
| **Registrations** | Everyone expected to sign up, including students who drop before or after classes begin: the class-list demand the model forecasts. Beneath it, the change on the last same-season term's registrations. |
| **First day / sections** | The last four same-season terms: students enrolled on the first day over the sections scheduled. A dash means the course was not offered, or the first day cannot be reconstructed; hover for which. |
| **Flags** | Plain-language reasons to look: near full last term (90% of seats filled on the first day), students left waiting, a big change in the term just finished, a volatile history, past forecasts well off, or the two candidates disagreeing. |
| **Stability** | Stable, Moderate, Volatile, or Unrated: whether the course is predictable from its own history at all, measured with no model |
| **Depth** | Deep, Moderate, Thin, or None: how many comparable rolling-selection aftcasts stand behind the published method |
| **Accuracy** | Close, Fair, Poor, or Unrated: how close those aftcasts landed, as an out-of-sample record |

Clicking a row opens the course's evidence in a window over the table; close it
to return to the same place in the list. The evidence opens with one sentence
that says what to plan and why, then the selected method and why it was
selected, the three axes, the planning recommendation, and the floor, Fall
delta, regime, and capacity checks. The method plot, movement diagnostic, and
candidate table sit under **Analyst detail**.

The plot compares every forecasting method against historical ever-registered,
first-day, census, and final/last-day enrollment. It is restricted to the
selected target's term type: Spring is compared only with prior Spring terms,
Fall only with Fall, and Summer only with Summer. Method selection, WAPE, and
the accuracy axis are judged against ever-registered demand; first-day, census
and final enrollment provide lifecycle context rather than alternative accuracy
targets.

The detail also shows the last four same-season terms' registrations,
first-day enrollment, census, sections, capacity, first-day fill, the method
the selection rule would have published that term and its aftcast, signed
error, capacity-bounded status, and potential explanation. Three rows describe
the adjustment whichever candidate was published: **Saturation floor**
(whether the prior term was full on the first day, the waitlist left on it,
and what happened the last times saturated courses in this market were given
more seats), **Fall deltas** (the enrollment changes and carry-through rates
behind the repeat and feeder terms), and **Regime check**, which flags a
course whose own enrollment in the term just finished moved 25% or more from
the year before. The check changes nothing; it says look. Its full **What this
means** text separates historical fit from structural caveats: a method can
fit observed enrollment consistently while a seat ceiling still prevents that
fit from proving unconstrained demand.

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

`Capacity-bounded` means first-day enrollment filled 98% or more of the
scheduled seats that term (a few empty seats spread over many section times
still leave the course full to a student choosing one), so an estimate above the observed ever-registered demand cannot be fully
judged as an error. A term whose first day cannot be reconstructed is never
capacity-bounded. It does not mean zero error, and
ever-registered demand above capacity on its own does not make a term
capacity-bounded: seats that turned over were never all occupied at once. `Potential explanation` identifies measured changes
that coincide with a miss; it is not a causal claim.

The page is a planning aid rather than an automatic scheduling decision. Review
stability, depth, accuracy, capacity status, and recent evidence before acting
on a section recommendation.
