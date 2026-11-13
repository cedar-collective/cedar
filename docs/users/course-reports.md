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

## Enrollment

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
- **First Day, Census, and Final Enrollment** — the same crosslist-family lifecycle series used by Overview, rather than a separate selected-code calculation
- **Classlist Enrollment History** — a table of the plotted crosslist-family first-day, census, and final counts, drops, and same-term-type averages from class-list records. A dash marks a term whose first day cannot be reconstructed.

Useful for seeing whether course registrations are growing, declining, or stable. Every enrollment surface in Course Dynamics uses one shared crosslist-aware payload: registrations under active partner codes are combined and deduplicated per campus and term, one home section represents each crosslist group, and standalone sections of the selected course are added normally. A student who drops one listing and registers under its partner — common when students switch codes inside a shared section — counts once, as enrolled. Because standalone sections belong only to their own code, a course and its partner can show different totals: the partner's report counts only the sections the two share. Per-code counts appear only as explicitly labeled comparisons on Overview cards and in the history hover.

The report tabs appear once **Analyze Course** has finished; changing the course or campus hides them until the next run.

---

## Projections

The published plan for this course in each term CEDAR has projected, read from
the same saved projection as **Registration → Projections**. One block per
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

## Course Flows

What do students take alongside this course, where do they come from before it,
and where do they go after? The first view is a treemap and ranked table of the
20 most common same-campus, same-term companion courses. Rectangle area shows
co-enrolled student-term enrollments; the table also gives the share of all
selected-course student-term enrollments that included each companion course.
A student taking the selected course in two terms contributes two student-term
enrollments.

The flow diagrams below the treemap show the most frequent ordered pairs —
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

## Retention

The Retention tab holds two views of whether students stay after the course. **By Grade** follows the course's own students and splits their return by how they did in it. **Takers vs Non-Takers** sets them beside students of the same classification who never took the course, against the college's other courses and against similar students. The **What counts as failing?** choice under By Grade applies there only; Takers vs Non-Takers counts pass and DFW by the standard rule.

### By Grade

{% include definition-summary.html id="course-retention" %}

Summer terms are skipped when counting forward.

You can configure how many semesters to track, set a minimum cohort size per row, and optionally break out results by instructor.

### Takers vs Non-Takers

{% include definition-summary.html id="course-cohort-effect" %}

By Grade follows the students who took the course. This view adds the
students who did not: for every enrolled student of a classification in a
term (first-semester freshmen, say), by home campus, it splits the population
into those who passed the course, those who DFW'd it, and those who never took
it that term, and shows each group's return the next regular term and the DFW
share of its next-term attempts. The gap columns are the passed group's rate
minus the never-took group's, in points.

The page opens on the course's takers whose home campus is among the
campuses chosen at the top of the page (every home campus when none of them
is): every term of the term type most of them took it in (every Fall, for a
course taken mostly in Fall), the classification most of them held, and the
course's own college and level. So a main-campus page asks about
main-campus students, even for a course most of whose takers are dual-credit
students on a branch campus. A Fall cohort and a
Spring one are different students, so read one term type at a time: **Term
types** selects every term of the types you tick, and **Terms** narrows them.
Change any of them and click **Compare Groups**.

Read the gap against the benchmark, not on its own. Passing any course goes
with returning, so the view runs the same comparison for every other course of
the chosen college (and level) the same students took, and reports the median
and quartiles of their gaps with the share of courses whose gap is below this
course's. A course whose gap sits at the college's median is an average
course; one far below it is where the question starts. A benchmark course
needs the minimum in both its passed and its never-took groups, and the
"Every Course in the Benchmark" table lists them.

The balance table at the bottom compares takers with never-takers on the
measured covariates (ACT, high-school GPA, Pell eligibility, first-generation
share and the rest) at each student's first selected term. A substantial
difference says the gap describes who is placed into the course.

---

## Downstream

The Downstream tab holds two views of what happens after the course. **Later Course** follows the course's own students forward: how many took a later course within a set number of terms, and how they did in it. **Course Sequence** starts from the later course and compares students who reached it after passing this one with students who reached it without. Both offer the later courses this course's students actually took.

### Later Course

{% include definition-summary.html id="downstream-outcomes" %}

Choose one later course, or several to read as a set, the window (three
regular terms unless you change it) and the smallest group a rate is shown
for, then click **Show Outcomes**. The list shows, beside each course, how
many of this course's students took it within the window.

The page gives, for each campus that taught the course:

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
- **Course Order.** How many students had already passed the later course
  before this one, or in the same term, by academic year.

A student who took the later course in a term whose grades are not posted yet
counts as having taken it, and is listed as not yet graded, never as failing.

### Course Sequence

{% include definition-summary.html id="course-sequence" %}

The optional HS GPA filter restricts both groups to a selected range; it is a
sensitivity check, not an adjustment for unobserved differences.

The balance table uses the absolute standardized mean difference (SMD) for
measured continuous and binary covariates. CEDAR labels values below 0.10 as a
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

Two tabs answer two halves of this, and neither answers the whole of it.

- **Downstream → Course Sequence** compares grades in one later course you
  name (ENGL 1120, say) between students who passed the first-year course
  first and students who took the later course without it. The first sentence
  of the result gives both rates with their counts and says how alike the
  groups were. For a first-year course they are never alike on what CEDAR can
  see: students who passed it first are, by construction, in their first
  semester, while the other group includes transfer students and everyone who
  placed past it. On the 2026-11-04 pull, students who passed FYEX 1010 before
  ENGL 1120 did not pass ENGL 1120 14.2% of the time against 12.9%, and
  entered with 5 credits against 28. That gap describes who takes FYEX 1010.
- **Retention → By Grade** shows, of the students who took the course, how many came
  back the next fall or spring, split by how they did in it. For FYEX 1010 on
  main campus, 92% of those who passed returned against 49% of those who
  failed. That is a strong signal about the students who fail a first-year
  seminar, not a measure of the seminar.

What neither tab does is compare takers with students who did not take the
course at all, holding classification constant. **Retention → Takers vs Non-Takers** does:
for one classification, by home campus and term, return and next-term DFW
share for students who passed the course, failed it, or never took it, with a
balance table. For main-campus first-semester freshmen in Fall 2023, 94% of
those who passed FYEX 1010 returned the next spring, 78% of those who never
took it, and 46% of those who failed it; the groups differ substantially on
ACT, high-school GPA, Pell eligibility and first-generation share, so these
describe who is placed into the course as much as the course.

Is that gap unusual? The same tab runs the comparison for every Arts &
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
