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

{% include definition-summary.html id="registered" %}
{% include definition-summary.html id="census-enrollment" %}

- **Overview cards** — census enrollment, current enrollment, active sections, average section size, early drops, late drops, and waitlisted students for the latest selected term type. Each card compares that value with the same term type one, two, and three years earlier.
- **Enrollment History** — census and current enrollment over time, with campuses kept separate
- **Classlist Enrollment History** — a table of registered counts, drops, and same-term-type averages from class-list records

Useful for seeing whether course registrations are growing, declining, or stable. For DESR section counts, crosslist totals, and schedule-facing enrollment signals, use the main Enrollment tab.

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

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term view across all courses in a department
- [Dept Trends](department-reports) — multi-year historical analysis including DFW trends and credit hours
- [Pathways](pathways) — population-level analysis of course timing, roadblocks, sequences, and major movement
