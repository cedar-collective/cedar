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

{% include definition-summary.html id="course-retention" %}

Summer terms are skipped when counting forward.

You can configure how many semesters to track, set a minimum cohort size per row, and optionally break out results by instructor.

---

## Downstream

The Downstream tab combines two related views that use the same observed follow-on-course list but answer different questions. Choose **Course Sequence** when the question is about taking this course before another course. Choose **Instructor Patterns** when the question is about later continuation and outcomes among this course's students, grouped by their first instructor here.

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

### Instructor Patterns

Among students who took this course and later took a downstream course, do downstream grades differ by the instructor students had here? This tab compares downstream grades for students grouped by which instructor they had in this course.

A balance table is included to show whether different instructors' sections enrolled different types of students. Self-selection is a major confounder here, since students often choose sections based on schedule, availability, or reputation. Check the balance table before treating differences as instructor effects.

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
- **Retention** shows, of the students who took the course, how many came
  back the next fall or spring, split by how they did in it. For FYEX 1010 on
  main campus, 92% of those who passed returned against 49% of those who
  failed. That is a strong signal about the students who fail a first-year
  seminar, not a measure of the seminar.

What neither tab does is compare takers with students who did not take the
course at all, holding classification constant. That comparison is on the
roadmap.

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term view across all courses in a department
- [Dept Trends](department-reports) — multi-year historical analysis including DFW trends and credit hours
- [Pathways](pathways) — population-level analysis of course timing, roadblocks, sequences, and major movement
