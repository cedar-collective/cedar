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
**Department**, and **Course** to narrow the saved rows. The table expands to
show every matching row and scrolls with the page. These controls do not fit or
rerun a model.

Two sentences sit above the table. The first, once the target term's draft
schedule is in the data, says how many of the courses shown are short of the
students expected on day one, with a link to the **Draft schedule** tab. The
second says how many courses' past forecasts were more than 20% off, for how
many of those the schedule set the number, and names the ones that missed
with seats to spare. The scope stripe
beneath them names the date the projection was built and the date the draft
schedule was pulled.

The table opens sorted by **Plan adds**, largest first, up or down. Most
projections are last year's registrations, so what the plan adds is the plan's
change from last year. Click any header to sort by it instead: **Flags** puts
warnings (amber) first, and the rating columns put the weakest first, with
Unrated last. The search box matches flag and rating text, including the
own-history and evidence ratings the table does not show, so typing
"Hard to predict" or "Volatile" finds those courses.

Three blue boxes above the table each answer one question; the title says which:

| Box | Answers |
|---|---|
| **Reading the table: what each column means** | Every column, and when a miss is the schedule's rather than the forecast's |
| **How a course's plan is built, step by step** | From last year's registrations to sections, and why each step is there; then what the pressure bump and the feeder adjustment add across the courses shown |
| **Where forecast error comes from** | Past misses by cause, measured on the loaded projection's past forecasts |

Below the table, **Projection methods: the two forecasts, and how one is
chosen** describes the two forecasting methods. The Draft schedule tab has its
own box, **How the draft comparison works**.

{% include definition-summary.html id="enrollment-projection" %}

## Reliability, and whose miss it was

Most past forecast error came in terms when a near-full course's seats
changed. A course near full on the first day (90% of its seats filled or
more) registers about as many students as it has seats, so when the schedule adds or cuts seats, registrations follow and last
year's number misses. That miss is the schedule's. A course with seats to
spare could have drawn more or fewer students whatever its seats did, so a
miss there is the forecast's own.

CEDAR sorts every past forecast term this way, with seats counted as moved at
10% or more:

| The past term | Whose miss |
|---|---|
| The course was near full (on the first day, or the year before when seats were added) and its seats moved the way the forecast missed: added and the forecast ran low, cut and it ran high | The schedule's |
| The course was near full on the first day and its seats held | The schedule's: registrations stopped at the seats |
| The course had seats to spare, or its seats moved the other way from the miss | The forecast's own |
| The seats or the first day are not known | Cannot be told |

A course takes whichever cause accounts for most of its past error. A seat
move alone does not make a miss the schedule's: a course whose seats moved
every year but never filled them missed on its own. Read reliability with it:

| Reliability | Most of the miss | What it means |
|---|---|---|
| High | any | Past forecasts landed close; plan to it. |
| Moderate | any | Usable for planning, not for a precise seat count. |
| Low | when near full and its seats changed | The schedule set those numbers; the projection holds if the seats do. |
| Low | with seats to spare | The forecast's own miss: enrollment changed by itself. Flagged "Off 20%+ with seats to spare". Ask the department what it expects before planning to the number. |
| Low | not known | The cause cannot be told. |
| Unrated | — | Too few past forecasts to tell. |

The table shows Reliability as how far past forecasts were off ("10.4% off"),
in its rating colour, with how often the seats moved 10% or more beneath it
("seats moved in 1 of 4"). The course's detail gives the sentence for its row
of the table above. The sentence above the table counts the courses whose
forecasts missed by more than 20%, says for how many the schedule set the
number, and names those that missed with seats to spare.

The **Where forecast error comes from** box gives the breakdown for the
loaded projection: how much error came from seat changes, from missing data,
from full courses whose seats held, and from courses with room whose seats
held. Only that last group tests the forecast of demand itself.

## Compare to the draft schedule

The **Draft schedule** tab sets each course's plan beside the target term's
schedule as it stands. The schedule is pulled from MyReports with the rest of
the data, and the tab says when. It is a draft until registration settles:
departments edit it, and the comparison follows at the next refresh.

Each course gets one verdict:

- **Short of day-one seats**: the draft has fewer seats than the students
  expected in the room when classes begin. Fix these first. The verdict gives
  each shortfall its own sections: "short of day-one seats by 10 (1 section);
  44 short of the plan (2 sections)".
- **Covers day one, short of the plan**: only the planning margin, the
  feeder adjustment or the pressure bump is missing.
- **Covers the plan**, or **seats beyond the plan** when it has more than a
  section to spare. In a course that is always full, spare seats are likely to
  fill: when such courses were given more seats, the new seats filled.
- **Not in the draft schedule**: a monitored course with a projection and no
  sections yet.

The table also shows the draft's sections (with each campus's share), its
seats, the expected day-one seats, the planned registrations (including the
feeder adjustment and any pressure bump), the plan's sections, **Draft vs. plan** (draft seats minus planned
registrations, negative where the draft is short), students registered so far once
registration opens, and the course's reliability with how often its seats
moved. Click a
course for its full evidence. Until the target term's schedule is in the data,
the tab says so instead of showing a table.

## Scenario: growing a population

The **Scenario** sub-tab answers a planning question the projection table cannot:
*if one group of students grows, what happens to the courses they take?*

Pick a **Population** (for example, Health Professions (Clinical)), an annual
**growth** rate, and a **horizon**, and the table shows each course year by year
— as students, as sections needed, or as sections beyond what is scheduled today.

Three things to know before quoting a number from it:

- **The first year is the published projection**, unchanged, whatever growth rate
  you choose. Growth applies to the years after it.
- **Later years are arithmetic, not forecasts.** They carry no reliability
  rating, because no past forecast can be checked against a hypothetical. They answer "what
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
day one can read 95% at census.

### December intersession is not included

December intersession sections belong to the Fall term but start weeks after
it, and register after the Fall is under way, so projections leave them out:
their students, seats and first days are not in any number here. To see
intersession sections, filter **Open Seats**, **Regstats** or **Enrollment** by
part of term.

### Sections are planned for registrations

Sections are planned for everyone expected to register, not only the students
expected in their seats on the first day. Registrations run about 8% above the
first day, because a student who drops early frees a seat someone else takes.
That margin is deliberate: running short of seats costs more than an empty
one. In past terms, planning for first-day seats alone would have fallen short
of the seats actually filled on day one in 61% of courses; planning for
registrations, in 32%. Expected first-day seats are shown beside the plan.

### The pressure bump

A course that is always full turns students away, so last year's registrations
undercount what it would draw. When near-full courses were given 10% or more
seats, the new seats filled; when their seats were held flat, registrations
stayed flat; when seats were cut, registrations fell by the cut.

So a course near full on the first day in every recent same-season term with a
first-day count (at least two of the last three) is planned for **5% more**
than it registered last time, or for the students left waiting if that is
more. 5% is about what the typical always-full course left waiting in Fall
2026, and it is deliberately modest: a new section needs an instructor. Feeder
courses never cancel it, because the students already turned away do not leave
when a feeder shrinks; their change is the feeder adjustment, below.

The bump is an allowance, not a measurement, and it is always shown
separately:

- The **Plan adds** column gives the registrations added and, beneath them,
  the sections that adds.
- The line above the table totals what the bump adds across the courses shown.
- A course's detail says why it got the bump, or why not.
- The registration forecast and its accuracy never include it.

As waitlists accumulate, the flat 5% will be replaced by a measured allowance.

### The feeder adjustment

Last year's registrations are a year old by the time the schedule is built.
A Spring plan still follows the Fall just finished:

- **A course taken just before this one** (Composition I before Composition II,
  Calculus I before II) counts every time, up or down. Most of its students go
  straight into the next course, so its change carries through: if Fall
  Composition I lost 100 students and 68% usually go on to Composition II, the
  Spring plan for Composition II drops by 68. These pairs are a short list the
  institution keeps (`projection_sequences.csv`).
- **The course's other feeder courses** count only when together they moved
  5% or more, either way, and then by the share of their students who
  historically took this course next. A smaller move is noise against a
  course's own year, and not every student who could take a course does.
- When the published forecast is the adjusted one, it already holds these
  changes, and the plan adds nothing.
- Two terms ahead, the term just finished has not happened yet, so there is
  nothing to follow and the course's detail says so.
- **A Fall plan does not follow its feeders.** Following Fall feeder courses
  made past Spring forecasts closer. Following Spring feeder courses made past
  Fall forecasts no closer: a Spring feeder's change pointed the way the Fall
  course moved about half the time, no better than a coin toss.

The **Plan adds** column shows the feeder change beside any bump, and a
course's detail gives the arithmetic. The registration forecast and its
accuracy never include it.

Some terms' class lists were exported without status dates,
so their first day is unknown; **Admin > Data & Usage** lists which. Those terms
show a dash and are never judged full or not full; they are not filled in from
census. A term pulled before one of its later sessions began, such as a
second-half session, has no complete first day either until a later pull
covers it. If the sessions that had begun already fill 90% of all the course's
seats, it is still judged near full, and the note says "at least".

Below the table, expand **Projection methods** for the method map. There are
two candidates:

- **Prior same-season**, the spine and the default: last comparable season's
  class-list demand. When the schedule holds still it is within about 6%.
- **Prior same-season + floor + Fall deltas**: the same number, plus the
  students still waiting for a seat at the end of that term when it was
  saturated (90% or more of the seats filled on the first day), plus the change
  in the course's own enrollment, in the course taken just before it, and in
  its other feeder courses during the term just finished, each scaled by the
  share that historically carried into this course. It uses Fall enrollments, not grades, because grades are not posted
  when the schedule is built.

**Prior same-season is the default for every course.** The adjusted candidate
replaces it only after beating it by a margin on earlier terms both were
forecast for. The rule is replayed at every past term with only the evidence available
then, so the accuracy you see is what that rule would actually have delivered,
not the fit of the winner on the terms that chose it. A course's detail gives
the evidence behind its current method.

The table is sized to fit a laptop window:

| Column | Meaning |
|---|---|
| **Course** | The course, with its department beneath. |
| **Sections** | Registrations plus what the plan adds, divided by the section size (the target schedule's average when it exists, otherwise the recent median), rounded up, with the registrations they are planned for beneath. "Plan at least" in the course's detail when the same term last year filled its seats. |
| **Plan adds** | Registrations the plan adds to the forecast: the change in the course's feeder courses in the term just finished (up or down), and a pressure bump when the course was near full on the first day in every recent same-season term, with the sections they add beneath. A dash means neither; the course's detail says why. |
| **Registrations** | Everyone expected to sign up, including students who drop before or after classes begin: the class-list demand the model forecasts, and the number sections are planned for. Beneath it, the range past forecasts for this course usually landed in. There is no change-on-last-year line: most forecasts are last year's number, and where the adjusted forecast moves it, the move has been a percent or so and has not predicted which way the course went. The range assumes seats like last year's: on past forecasts it held about 8 or 9 times in 10 when seats stayed within 10%, and about 1 in 3 when they moved. When the draft schedule moves the seats 10% or more, the course's detail says so beside the range. |
| **Students (day 1)** | Students expected to hold a seat when classes begin: registrations times the share of this course's registrants still enrolled on the first day in recent terms. Context, not the planning number. |
| **First day / sections** | The last four same-season terms: students enrolled on the first day over the sections scheduled. A dash means the course was not offered, or the first day cannot be reconstructed; hover for which. |
| **Day-1 fill** | The share of seats filled on the first day of classes in the term the forecast starts from, the same season last year; the header names that term. **Full** at 98% or more, **Near full** at 90%, with the students still waiting beneath. "Unknown" says why: the class lists carry no status dates, a later session had not begun when the data was pulled, or there was no seat count. |
| **Flags** | What no column already says: one campus full while another had room (online seats can fill while Albuquerque's do not, and the pooled plan hides it), a big enrollment change in the term just finished, a volatile history with no track record yet ("Hard to predict"), past forecasts more than 20% off while the course had seats to spare, or the two candidates disagreeing. |
| **Reliability** | How far past forecasts for this course were off, each made with only the evidence available then, coloured High (within 10%), Moderate (10 to 20%) or Low (more than 20%), with how many of those same past terms moved the course's seats 10% or more beneath. Unrated when there are too few. |

The course's **Own history** (whether it is predictable from its own history
at all, measured with no model: Stable, Moderate, Volatile or Unrated) and
**Evidence** (how many past forecasts stand behind the published method: Deep,
Moderate, Thin or None) are in its detail.

Clicking a row opens the course's evidence in a window over the table; close it
to return to the same place in the list. It opens with one sentence that says
what to plan and why, then three things large and up front: its **Status**
(the planning recommendation), the **Sections**, and the planned registrations
they are sized for.

**How this plan was built** follows, open: one line per step from last
year's class list to the sections, each with where its number came from.

- Registered last year: everyone on the class lists, including students who
  later dropped.
- Students still waiting, when the course was near full.
- The enrollment change in the term just finished, split into retakes, the
  listed predecessor, and other feeder courses.
- The forecast, with how far past forecasts for the course missed.
- The feeder adjustment and the pressure bump, when the plan has them.
- The planned registrations.
- The sections: registrations divided by the section size, rounded up, beside
  the draft schedule's count.

Each total is the sum of the lines above it, so a reader can check the plan
line by line.

Beneath that are four badges, each with its number: Reliability with its
rating ("10.4% off (Low)"), Seats (how often they moved in those past terms,
in grey because seat moves are not good or bad in themselves), Own history
and Evidence, then the one sentence saying whose the past misses were, and
then the last four same-season
terms. The reasoning behind each step is in **Why this method, why this
course: the full evidence trail**, collapsed by default: the selected method
and why, why the course is listed, the feeder and pressure-bump notes, and the
floor, Fall-delta, regime and capacity checks. The method plot, movement
diagnostic and candidate table sit under **Analyst detail**, collapsed as
well.

The plot compares every forecasting method against historical ever-registered,
first-day, census, and final/last-day enrollment. It is restricted to the
selected target's term type: Spring is compared only with prior Spring terms,
Fall only with Fall, and Summer only with Summer. Method selection and the
reliability rating are judged against ever-registered demand; first-day, census
and final enrollment provide lifecycle context rather than alternative accuracy
targets.

The detail also shows the last four same-season terms' registrations,
first-day enrollment, census, sections, capacity, first-day fill, the method
the selection rule would have published that term and what it forecast, signed
error, capacity-bounded status, and potential explanation. Three rows describe
the adjustment whichever candidate was published: **Saturation floor**
(whether the prior term was full on the first day, the waitlist left on it,
and what happened the last times saturated courses in this market were given
more seats), **Fall deltas** (the enrollment changes and carry-through rates
behind the repeat, sequence and feeder terms), and **Regime check**, which flags a
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
judged as an error. A term whose first day is unknown is never
capacity-bounded. It does not mean zero error, and
ever-registered demand above capacity on its own does not make a term
capacity-bounded: seats that turned over were never all occupied at once. `Potential explanation` identifies measured changes
that coincide with a miss; it is not a causal claim.

The page is a planning aid rather than an automatic scheduling decision. Review
reliability and whose the past misses were, own history, evidence, capacity
status, and the recent terms before acting on a section recommendation.
