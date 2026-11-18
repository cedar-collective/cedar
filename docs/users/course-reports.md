---
title: Course Dynamics
parent: User Guide
nav_order: 15
---

# Course Dynamics
{: .fs-9 }

**Enrollment patterns, student flows, and grade distributions for a specific course**
{: .fs-6 .fw-300 }

---

Course Dynamics is a one-course workspace: enrollment history, who takes the course, where students come from, grade outcomes, and what later enrollment looks like. It lives under **Course Dynamics** in the top navigation.

Select a course using the search box (type a subject code or course number to filter), choose your campus, and click **Analyze Course**.

---

## Overview

The first tab: how many students the course draws each term, how many it loses to drops, and how many sections it runs. The **Term type** control at the top applies to every chart and the table below it.

{% include definition-summary.html id="first-day-enrollment" %}
{% include definition-summary.html id="census-enrollment" %}
{% include definition-summary.html id="registered" %}

- **Latest-Term Snapshot** — one compact table per campus: the latest available term in the selected term type beside the same term in the three years before it, so each measure reads across as its own history. Rows are grouped as *Enrollment* (first day, census, final), *Churn* (early drops, late drops, waitlisted), and *Sections* (active sections, average size). The latest term is bold on a tinted column; a term still in progress says so, and the measures that keep moving until it ends read *so far*. A dash marks a value that cannot be shown, such as a first day before status dates were recorded.
  - For a crosslisted term, the latest column splits into **All** and each code's own count (for example, All 11 · MATH 375 6 · CS 375 7 early drops), selected code first. Hover an earlier year to see its split. Section rows are not split, because a shared section is one room.
  - A student who switches codes has a row under each — a drop under one, an enrollment under the other — so the code columns can add up to more than All. A note under the table names those students (for example, *2 moved from CS 375 to MATH 375 and 1 dropped both*).
- **Enrollment History** — three points in each term, one line each with campuses kept separate: **first day** (dotted), **census** (solid), and **final** (dashed). Crosslisted offerings combine the full course family once rather than showing only the selected department's listing; hovering a point gives the selected code's own count.
  - *First day* is reconstructed from the date on each class-list row: students still enrolled who registered by the first class day, plus anyone who dropped after it. It is blank for terms whose class list was exported without status dates, rather than shown as a partial count; re-pulling those terms' class lists fills it in.
  - *Final* is enrollment when the term ended. A shaded term is still in progress, so its final point is current registration.
  - First day minus census is mostly early drops after classes began, offset by late adds; census minus final is the late withdrawals.
- **Early and Late Drops** — early drops (no grade, never DFW) and late drops (withdrawals) each term, from the same crosslist-family series.
- **Active Sections** and **Average Section Size** — home sections each term, a crosslist family counted once, and students per section.
- **Enrollment by Term** — the counts behind the charts, term by term: first day, census, final, drops and each term type's average, from class-list records. A dash marks a term whose first day cannot be reconstructed.

Useful for seeing whether course registrations are growing, declining, or stable. Every enrollment surface in Course Dynamics uses one shared crosslist-aware payload: registrations under active partner codes are combined and deduplicated per campus and term, one home section represents each crosslist group, and standalone sections of the selected course are added normally. A student who drops one listing and registers under its partner — common when students switch codes inside a shared section — counts once, as enrolled. Because standalone sections belong only to their own code, a course and its partner can show different totals: the partner's report counts only the sections the two share. Per-code counts appear only as explicitly labeled comparisons on Overview cards and in the history hover.

The report tabs appear once **Analyze Course** has finished; changing the course or campus hides them until the next run.

---

## Topics

Some course numbers carry many courses: FYEX 1110's seminars, a department's special-topics slot. Each section's title names its topic, and the **Topics** tab counts each topic separately so they can be compared within that one course number. The tab appears only for a course that offered two or more topics in the same term on a campus picked.

- **Topics by Term** — one line per topic and campus for the measure chosen: students at census, sections, fill, DFW or return to the next regular term. On a rate, a grey line shows every topic together. Choose the term types and which topics to draw; the five with the most students are drawn first.
- **Topics Side by Side** — each topic pooled over its settled terms beside every topic together, one table per campus.
- **Topic by Term** — the topics drawn, term by term, with each term's total.
- **Titles Behind Each Topic** — every title the schedule printed and the topic it was counted under.

How the tab reads a title:

- A leading section label such as *Sem:* or *T:* is dropped, and case, punctuation and *&* against *and* are ignored, so *Sem: Success Starts Here* and *Success Starts Here* are one topic.
- A misspelling or a title cut short at the schedule's length limit is merged only when someone has reviewed it into the institution's topic-titles file; until then it is a topic of its own, and the last table shows it.
- Only students registered under this course number count. Students registered under a crosslisted partner code belong to that code's report, and fill is left blank for a crosslisted section, whose seats are shared.
- A term still in progress is shaded and counts current registration; DFW is read through the last graded term, and return once the next regular term has settled. A rate is shown only when enough students stand behind it (the minimum is a control on the page).

{: .warning }
A topic taught by one instructor in a term is that instructor's course, so its DFW and return rates are withheld without the instructor password, the same password as the DFW tab's instructor results. So is the next smallest topic in a term where exactly one topic was withheld, since the term's total would otherwise give the withheld rate back. Pooled rates then cover only the terms shown, and the table says so. Student, section and seat counts are never withheld, nor are the rates for every topic together.

---

## Section Plan

The published plan for this course in each term CEDAR has projected, read from
the same saved projection as **Registration → Projections → Plan**. One block per
projected term (a Fall and a Spring are both current) shows the sections to
schedule, the registrations they are sized for, each step that built the number
from last year's class list, the recent same-season evidence, and how close
past forecasts for the course came.

- Projections are made for **ABQ and EA together as one market**, so the campus
  filter at the top of the page does not apply to this tab, and branch campuses
  are never projected.
- Only monitored courses are projected. A course outside the monitored groups
  says so; a monitored course the pressure screen left out of a term shows the
  saved reason (for example, how many recent same-season terms reached 90% of
  scheduled capacity).
- Nothing is computed when the tab opens: every number is the saved
  projection's, built by the morning refresh. See
  [Enrollment Projections](enrollment-projections) for how to read the plan.

---

## Other Courses
{: #other-courses}

What do students take alongside this course, where do they come from before it,
and where do they go after? (This tab was called Course Flows.)

### Courses Taken Alongside
{: #courses-taken-alongside}

What else this course's students take the same term: all of them together,
then by major.

**All students.** A treemap of the 20 courses taken by the most students
alongside this one, each block grouped under the college that taught it, beside
the ten largest as bars. Read the treemap for the overall shape: which one or
two courses dominate, and whether they come from one college or many. Each
block is labelled with its share of students; its area understates that share,
because every student takes several courses, so the areas add up to more
students than there are. The bars give the exact shares, with the count and
the average a term.

**By major.** A course's students differ by major: pre-nursing students take
BIOL 2210 beside CHEM 1215, engineering students MATH 1512. So each of the five
largest majors gets a card of its own, and every other student is in **All
other majors**.

- Choose **Fall**, **Spring** or **Summer**: the view reads the course's last
  three terms of that type on each campus, up to the last term whose
  enrollment has settled.
- Each card names the major (a pre-major is its own card, as in *Nursing
  (pre-major)* beside *Nursing*), the program codes behind it, and how many
  student-terms it holds. A student who took the course in two terms counts
  twice. A major needs 20 student-terms for its own card.
- Each bar is the share of that card's student-terms that were registered in
  the course the same term on the same campus. Up to five courses are listed,
  each taken by at least five of the group. Every bar is on the same 0–100%
  scale, so cards can be compared side by side.
- The course's own lab (CHEM 1215L for CHEM 1215) is shown once, above the
  cards, and left out of the treemap and the cards: most students take it
  whatever their major.
- Waitlists, drops and courses on another campus are not counted. On a campus
  whose students take their other courses elsewhere, a card can list nothing.

### Before and After

The flow diagrams show the most frequent ordered pairs —
courses students took in the term immediately before or after the selected
course.

Configurable settings:
- **Minimum students per term** — filters out low-frequency connections (default: 2)
- **Maximum courses to display** — limits the diagram to the most common connections for readability (default: 6)

Click **Update Flow Diagrams** after adjusting these settings.

{: .note }
Course flows work best for courses embedded in sequences. Isolated electives or highly variable topics courses may not show strong directional patterns.

**Reading flow diagrams:**
The diagram shows courses students took before (left) and after (right). The width of each connection represents how many students took that path. A strong flow from MATH 1215 into PHYS 1310, for instance, tells you something different about the de facto prerequisite structure than the catalog does.

Only registered class-list rows (RE/RS/RR) are used for both same-term and
before/after views; waitlists and drops are excluded. Every course result keeps
campus in its grouping, so a Main-campus schedule is not silently combined with
Online or branch-campus schedules.

---

## Rollcall

Who's taking this course? Rollcall shows the composition of students by classification (freshman, sophomore, junior, senior, graduate) and by declared major, broken out by term type (fall and spring shown separately) and across time.

- **By Student Classification** — fall and spring bar charts showing class-year distribution
- **By Major** — which programs send students to this course, and in what proportions
- **Classification Trends Over Time** — how the class-year mix has shifted across terms
- **Major Trends Over Time** — how the program-of-origin mix has shifted
- **Data Tables** — the underlying numbers for the above charts

Knowing that many students in an upper-division elective come from outside the home department can change how the course's curricular role is interpreted, especially for course design, prerequisites, and advising.

---

## DFW

{% include definition-summary.html id="dfw" %}

{: .warning }
Course-level results remain visible. Instructor-level results require a configured password due to their sensitivity; when the administrator has not configured one, those results remain disabled.

The DFW tab is intended to support conversations about course design and student support — not to evaluate individual instructors. The instructor-type breakdown (tenure-track vs. contingent faculty) is one lens for understanding patterns; it should be read alongside section size, student composition, and course context.

---

## Downstream

The Downstream tab follows the course's students afterwards, one question a subtab, in the order a reader asks them: do they come back, do they do better than students who skipped the course, where do they go next, and did the course prepare them for it.

| Subtab | Asks | Compares |
|---|---|---|
| **Coming Back** | Did the students who passed the course come back more often than those who did not? | this course's students, by their result here |
| **Against Non-Takers** | Do students who take it come back and do well more often than similar students who don't? | takers against students who did not take it |
| **Next Courses** | How many went on to a later course, and how did they do in it, by their grade here? | this course's students, by their grade here |
| **Prepared for It** | In a later course, did students who passed this one first do better? | later-course students who passed this one first against those who did not |

The first two read the university as a whole (return, grades in other courses, GPA); the last two read one later course. The **What counts as failing?** choice in Coming Back's Settings applies there only; every other view counts pass and DFW by the standard rule.

Each subtab runs when you open it, on the defaults its **Settings** box describes. Change a setting there and click **Update Results**.

### At a Glance

Downstream opens on **At a Glance**: the whole story in five cards, read top to bottom.

1. **In the Course**: the share of the course's graded attempts that ended in DFW, across its terms, and whether that rate has risen or fallen (from the DFW tab).
2. **Coming Back**: how often students who passed came back the next semester, against those who did not.
3. **Against Non-Takers**: how often its students came back against similar students who did not take it, and whether that is better, worse or about the same once chance is allowed for. It needs admissions records; without them the card says so.
4. **Next Courses**: of the students who could have taken the later course, how many did within the window, and how many of them passed it.
5. **Prepared for It**: the later course's DFW rate for students who passed this course first against those who did not, and whether the two groups were alike before it.

Each card gives its number as a sentence and a small figure, names the campus it reads (the one with the most students, so a number is never a blend of campuses), and opens the subtab behind it, where the same number comes with its change over time, its breakdowns and how far to trust it. Opening At a Glance runs the views it reads on their defaults, so its cards fill in one by one; the later course is the one Next Courses and Prepared for It show.

Every view is laid out in the same order, so a reader who has learned one can read the others:

1. **The answer**: the question, a lead sentence with the number, and its figure.
2. **Over Time**: the same rates term by term, one term type at a time, with a sentence saying whether each line is rising, falling or steady.
3. **The breakdowns**: by grade, by campus, by who is in each group, and by instructor behind the instructor-data password.
4. **Against Other Courses**, where the view has a benchmark.
5. **How Far to Trust It**: who was counted (collapsed), and how alike the compared groups were, in one table with a row per measured characteristic.

### Coming Back
{: #retention}

{% include definition-summary.html id="course-retention" %}

Summer terms are skipped when counting forward.

Under Settings you can choose what counts as failing, how many semesters to track and the minimum cohort size per row, and, behind the instructor-data password, break the results out by instructor.

### Against Non-Takers
{: #takers-vs-non-takers}

{% include definition-summary.html id="course-cohort-effect" %}

Coming Back follows the students who took the course. This view adds the
students who did not: for every enrolled student of a classification in a
term (first-semester freshmen, say), by home campus, it sets the course's
takers beside the students who never took it that term, on return the next
regular term, the DFW share of their next-term attempts and next-term GPA.
The split of the course's own students by grade is Coming Back's, and is
not repeated here.

The page opens on the course's takers whose home campus is among the
campuses chosen at the top of the page (every home campus when none of them
is): every term of the term type most of them took it in (every Fall, for a
course taken mostly in Fall), the classification most of them held, and the
course's own college and level. So a main-campus page asks about
main-campus students, even for a course most of whose takers are dual-credit
students on a branch campus. A Fall cohort and a
Spring one are different students, so read one term type at a time: **Term
types** selects every term of the types you tick, and **Terms** narrows them.
Change any of them under **Settings** and click **Update Results**.

Read the gap against the benchmark, not on its own. Passing any course goes
with returning, so the view runs the same comparison for every other course of
the chosen college (and level) the same students took, and reports the median
and quartiles of their gaps with the share of courses whose gap is below this
course's. A course whose gap sits at the college's median is an average
course; one far below it is where the question starts. A benchmark course
needs the minimum in both its passed and its never-took groups, and the
"Every Course in the Benchmark" table lists them.

Before Matching reads the gap with no matching at all. How Far to Trust It,
at the bottom, compares takers with never-takers on the measured covariates (ACT, high-school GPA, Pell eligibility, first-generation
share and the rest) at each student's first selected term. A substantial
difference says the gap describes who is placed into the course.

**Against Similar Students** narrows the comparison to students like the
takers: the same term, home campus, high-school GPA band and full- or
part-time status. It pools the selected terms and reports return, the DFW
share of the takers' other courses that term, and next-term GPA, each beside
the rate the takers would have had at their similar peers' rates. Each
outcome is a card: the two figures as bars, and whether the course's students
did better, worse or about the same once chance is allowed for. A dot chart
then places the course's return gap among every other course these students
take, since taking almost any course goes with coming back. The table below
the cards holds every figure. **Similar students compared** chooses those
peers:

- **Everyone else**: every similar student who did not take the course.
- **In a Gen Ed course**: only similar students who took a Gen Ed course that
  term (the institution's Gen Ed list) and not this one. For a course outside
  Gen Ed, such as a first-year seminar, this asks whether its students did
  better than students like them in Gen Ed courses. The page says what share
  of the population that is; most first-semester freshmen take a Gen Ed
  course, so the two choices usually differ little.

Either way the cells remove term, campus, high-school GPA and time status and
nothing else: placement, advising and motivation are not in them.

**Over Time** shows the three gaps one term at a time, each with the band
chance alone gives, so a gap that is shrinking or growing shows as a series
rather than hiding in the pooled average. A dashed line is fitted from fall
to fall (or spring to spring, whichever has more takers), and the lead says
whether each gap is rising, falling or showing no trend beyond chance. A
line needs at least three terms, and its slope must be larger than both
chance and the terms' own ups and downs before it counts as a trend.
**Against Other Courses** places the course's return gap among every other
course these students take, and its table shows the same return-gap line for
every course, with its slope a year, so a set of courses can be read for
their trends side by side.

### Next Courses and Prepared for It

Both subtabs read one later course, chosen in a picker that sits on each: change it on one and the other follows. It opens on the first course the list offers, the later course of this course's own department that most of its students took (or the most-taken one when the department has none), so neither opens empty. The list shows, beside each course, how many of this course's students took it within the window (three regular terms unless you change it under Next Courses' Settings). Choose several codes to read them as one course.

They start from different students:

| | **Next Courses** | **Prepared for It** |
|---|---|---|
| Starts from | everyone who took this course | everyone in the later course |
| Asks | how many went on to the later course, and how they did in it | did students who passed this course first do better there than those who did not? |
| Compares | this course's students with each other: by term, by the grade they earned, by instructor | two groups of later-course students: passed this course first, or not |
| Time limit | a window of regular terms (three unless you change it) | any earlier term |

Use the first for where a course's students go and how its grades carry forward; use the second for whether this course prepares students for the later one as well as the other routes into it do.

### Next Courses
{: #later-course}

{% include definition-summary.html id="downstream-outcomes" %}

The view gives, for each campus that taught the course:

- **The two rates, with the counts behind them.** The share who took the later
  course and the share of those who passed it, each over all terms. Directly
  underneath is the arithmetic: everyone who took the course, minus the
  students too recent to have had the whole window, minus those who had
  already passed the later course, equals the students who could have taken
  it; then how many did, and what became of them (passed, DFW, withdrew, not
  yet graded).
- **Over Time.** The same two rates by the term students took the course, as a
  chart and a table. Read one term type at a time with **Term types**: a Fall
  cohort and a Spring one are different students. Under the chart, one
  sentence per line says whether it is rising, falling or steady. The verdict
  is the fitted line's across every term, set beside the movement that chance
  and the terms' own scatter would give with no trend, so the first and last
  terms can point one way and the verdict another.
- **By grade in the course.** The grade a student earned separates their later
  results more than anything else on the page. Read every other comparison
  with that in mind.
- **When they took it**, in regular terms after the course.
- **By instructor in the course**, behind the instructor-data password. Each
  instructor's row gives their students' grades in this course first, then the
  later results, then the later pass rate among students with the same letter
  grade. An instructor who passes fewer students sends a stronger group on, so
  a higher later pass rate does not show better preparation. The table is not
  a measure of teaching and not a basis for evaluating anyone. A balance check
  under it says whether the two largest instructor groups started alike; it
  changes no number above it.
- **How Far to Trust It.** Course Order: how many students had already passed
  the later course before this one, or in the same term, by academic year, and
  so left the count. Behind the password, the instructor balance check.

A student who took the later course in a term whose grades are not posted yet
counts as having taken it, and is listed as not yet graded, never as failing.

### Prepared for It
{: #course-sequence}

{% include definition-summary.html id="course-sequence" %}

The optional HS GPA window under **Settings** restricts both groups to a
selected range; it is a sensitivity check, not an adjustment for unobserved differences.

The result opens with both groups' DFW rates in the later course, as a
sentence and a pair of bars, then charts them term by term under **Over
Time**. **Who Is in the Comparison Group** splits the students without a
prior pass into those who tried this course and did not pass and those who
never sat it, and **Within High-School GPA Bands** reads the same outcome
among students with similar preparation.

How Far to Trust It holds one balance table. It uses the absolute standardized
mean difference (SMD) for measured continuous and binary covariates, each
group's record entering the term that put it in its group. The registrar's
current UNM GPA, measured at the data pull and so after the outcome, is a
described row at the bottom with no difference: it is shown, never matched or
balanced on. CEDAR labels values below 0.10 as a
small observed difference, values from 0.10 through 0.25 as requiring review,
and values above 0.25 as a substantial observed difference. These labels do not
adjust the comparison or establish that the groups are comparable on unmeasured
factors. Categorical distributions must be reviewed directly, and an
unavailable SMD is not evidence of a small difference.

Useful for checking whether a prerequisite or recommended sequence is associated with the outcome difference that motivates it. The comparison is descriptive and should be read with the balance table and local curriculum context.

---

## Common questions

**Why is my course not in the list?**

The dropdown shows courses with enrollment data in CEDAR. If a course is missing, it may not have been offered recently enough to appear, or it may use a different subject code than expected.

**Why are the course flows empty?**

Flows require multiple terms of data and students who take other courses before and after this one. New courses, highly isolated electives, or courses with very small enrollments may not generate meaningful flow data.

**How far back does the data go?**

This depends on what your institution has loaded into CEDAR. Check with your CEDAR administrator for the data range.

**Do students who take a first-year course (FYEX 1010, FYEX 1110) do better later, or come back more?**

Two views answer two halves of this, and neither answers the whole of it.

- **Downstream → Prepared for It** compares grades in one later course you
  name (ENGL 1120, say) between students who passed the first-year course
  first and students who took the later course without it. The first sentence
  of the result gives both rates with their counts and says how alike the
  groups were. For a first-year course they are never alike on what CEDAR can
  see: students who passed it first are, by construction, in their first
  semester, while the other group includes transfer students and everyone who
  placed past it. On the 2026-11-04 pull, students who passed FYEX 1010 before
  ENGL 1120 did not pass ENGL 1120 14.2% of the time against 12.9%, and
  entered with 5 credits against 28. That gap describes who takes FYEX 1010.
- **Downstream → Coming Back** shows, of the students who took the course, how many came
  back the next fall or spring, split by how they did in it. For FYEX 1010 on
  main campus, 92% of those who passed returned against 49% of those who
  failed. That is a strong signal about the students who fail a first-year
  seminar, not a measure of the seminar.

What neither view does is compare takers with students who did not take the
course at all, holding classification constant. **Downstream → Against
Non-Takers** does: for one classification, by home
campus and term, return and next-term DFW share for the course's passers
against students who never took it, with a balance table. The groups differ
substantially on ACT, high-school GPA, Pell eligibility and first-generation
share, so the gap describes who is placed into the course as much as the
course.

Is that gap unusual? The same view runs the comparison for every Arts &
Sciences lower-division course those freshmen took and places the first-year
course among them. For the same students, passing any such course went with
returning at a median 96%, a gap of 19 points over those who never took it;
FYEX 1010's 16 points sat in the bottom quarter of courses and FYEX 1110's 18
at the median. On next-term grades, FYEX 1110 was again an average course,
while FYEX 1010 was the one course whose passers failed more the next term
than its never-takers did. Passing a course in the first semester goes with
coming back; neither seminar shows a lift beyond that, and the students
placed into FYEX 1010 carry their risk into the next term.

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term view across all courses in a department
- [Dept Trends](department-reports) — multi-year historical analysis including DFW trends and credit hours
- [Pathways](pathways) — population-level analysis of course timing, roadblocks, sequences, and major movement
