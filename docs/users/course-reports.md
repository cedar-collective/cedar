---
title: Course Dynamics
parent: User Guide
nav_order: 4
---

# Course Dynamics
{: .fs-9 }

**Enrollment patterns, student flows, and grade distributions for a specific course**
{: .fs-6 .fw-300 }

---

Course Dynamics is a deep dive into a single course — its enrollment history, who takes it, where students come from, how they fare, and what happens to them after. It lives under **Explore → Course Dynamics** in the top navigation.

Select a course using the search box (type a subject code or course number to filter), choose your campus, and click **Analyze Course**.

---

## Enrollment

Enrollment trends and section history for the selected course across all terms in the data.

- **Enrollment Trends** — a chart showing enrollment over time, with the ability to see term-by-term variation at a glance
- **Enrollment History** — a table with section-level detail: term, section count, enrollment numbers

Useful for understanding whether a course is growing, declining, or stable, and how section sizes have shifted over time.

---

## Course Flows

Where do students come from before this course, and where do they go after? This analysis shows the most frequent ordered pairs — courses students took in the term immediately before or after the selected course.

Configurable settings:
- **Minimum students per term** — filters out low-frequency connections (default: 2)
- **Maximum courses to display** — limits the diagram to the most common connections for readability (default: 6)

Click **Update Flow Diagrams** after adjusting these settings.

{: .note }
Course flows work best for courses embedded in sequences. Isolated electives or highly variable topics courses may not show strong directional patterns.

**Reading flow diagrams:**
The diagram shows courses students took before (left) and after (right). The width of each connection represents how many students took that path. A strong flow from MATH 1215 into PHYS 1310, for instance, tells you something different about the de facto prerequisite structure than the catalog does.

---

## Rollcall

Who's taking this course? Rollcall shows the composition of students by classification (freshman, sophomore, junior, senior, graduate) and by declared major, broken out by term type (fall and spring shown separately) and across time.

- **By Student Classification** — fall and spring bar charts showing class-year distribution
- **By Major** — which programs send students to this course, and in what proportions
- **Classification Trends Over Time** — how the class-year mix has shifted across terms
- **Major Trends Over Time** — how the program-of-origin mix has shifted
- **Data Tables** — the underlying numbers for the above charts

Knowing that 60% of students in an upper-division elective come from outside the home department changes how you think about the course's curricular role — and how you might approach course design, prerequisites, or advising.

---

## DFW

D grades, F grades, and Withdrawals for the selected course, with trend lines across terms and optional breakdown by instructor type where faculty HR data is available.

{: .warning }
This section requires a password due to the sensitivity of grade data at the instructor level. Contact your CEDAR administrator for access.

The DFW tab is intended to support conversations about course design and student support — not to evaluate individual instructors. The instructor-type breakdown (tenure-track vs. contingent faculty) is one lens for understanding patterns; it should be read alongside section size, student composition, and course context.

---

## Retention

For each term the course was offered, how many of those enrolled students were still at UNM one, two, or more semesters later? The Retention tab tracks cohort persistence: every student registered in this course in a given term forms that term's cohort, and the +1, +2, ... columns show the share still enrolled at UNM that many semesters forward.

Graduation counts as retained — students who completed a degree are not treated as stop-outs. Summer terms are skipped when counting forward. Cells are left blank (not 0%) when the target semester is beyond the latest available data; a 0% for a recent cohort would be misleading because those students haven't yet had the chance to re-enroll.

You can configure how many semesters to track, set a minimum cohort size per row, and optionally break out results by instructor.

---

## Sequence Effect

Does taking this course first make a difference in how students perform downstream? Select a downstream course Y, and this tab compares grades in Y between two groups: students who took this course before Y, and students who took Y without prior exposure to this course.

A HS GPA filter is available to restrict both groups to the same ability window, which reduces the self-selection bias that comes from stronger students being more likely to complete prerequisites. Leave it blank to include all students.

Useful for evaluating whether a prerequisite or recommended sequence actually produces the outcome difference that motivates it.

---

## Instructor Prep

Among students who took this course and later took a downstream course, does it matter which instructor taught them here? This tab compares downstream grades for students grouped by which instructor they had in this course.

A balance table is included to show whether different instructors' sections enrolled different types of students — self-selection is the primary confounder here, since students often choose instructors based on schedule or reputation. Check the balance table before drawing conclusions about instructor effectiveness.

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
- [Department Profile](department-reports) — multi-year historical analysis including DFW trends and credit hours
- [Pathways](pathways) — cohort-level analysis tracing how defined student populations move through the curriculum
