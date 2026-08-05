---
title: Why Numbers Differ Across Tabs
parent: User Guide
nav_order: 21
---

# Why Numbers Differ Across Tabs
{: .fs-9 }

CEDAR shows several views of the same institutional records. Those views do not
always match because they are often answering different questions. A difference
is not automatically an error; it is usually a difference in source, timing,
cohort, or denominator.

{: .note }
Use CEDAR to inspect patterns and understand definitions. Use official
Institutional Research reports for certified census, accreditation, IPEDS, state,
or externally submitted figures.

## The Short Version

When two numbers differ, ask:

1. Are they using the same source table?
2. Are they using the same point in the enrollment lifecycle?
3. Are they counting rows, sections, credits, or unique students?
4. Are they grouped by campus, crosslist status, course title, or instructor?
5. Are they bounded by the same data edge?

## Common Reasons Numbers Differ

| Reason | What changes | Example |
|:--|:--|:--|
| Source table | DESR and Class Lists are separate extracts. | Open Seats uses section availability; Course Dynamics uses student enrollment records. |
| Snapshot timing | Current-term data may be live registration; past terms may be post-drop. | A current fill rate can look higher than a past final-enrollment comparison. |
| Enrollment lifecycle | Census-style, final, and ever-registered counts answer different questions. | Regstats demand signals add late drops back; end-of-term views may not. |
| Unit counted | Rows, courses, CRNs, students, and credit hours are different units. | A combined lecture/lab course can have multiple CRNs but one course identity. |
| Campus grouping | CEDAR separates main, online, and branch delivery where course-level numbers are shown. | A course taught on ABQ and EA can appear as separate campus rows. |
| Crosslists/topics | Crosslisted and topics courses may be compressed or kept separate depending on the question. | Two rows with the same course number may differ by title or campus. |
| Data edge | Grade-based views stop at the last graded term; enrollment views can include newer settled registration. | A newest term may appear in enrollment tabs but not in DFW-rate trends. |
| Cohort definition | Pathways, Headcount, Dept Trends, and Course Dynamics start from different populations. | Program headcount counts declared students; Course Dynamics starts from students in one course. |

## Enrollment Is Not One Number

CEDAR carries both section-level enrollment from DESR and student-level
registration from Class Lists.

DESR is useful for schedule and capacity questions. Class Lists are useful when
CEDAR needs individual student records, grades, drops, waitlists, demographics,
or later outcomes.

For demand and capacity questions, CEDAR may use a census-style count:

`registered students + late drops`

That count includes students who stayed past the drop deadline and later left
the course. It can be larger than final enrollment, and that is the point.

## Course Outcomes Have A Grade Edge

DFW, pass rates, grade distributions, and retention after grades depend on posted
grades. CEDAR stops grade-based reporting at the most recent term whose grades
are actually available. Enrollment views can include newer terms because they do
not need final grades.

If a term appears in an enrollment chart but not a DFW chart, that usually means
the term is enrolled but not graded yet.

## Program Headcount And Course Enrollment Differ

Program headcount starts from Academic Studies program records: who is declared
in a major, minor, concentration, or certificate.

Course enrollment starts from course registration records: who took a section.

A department can teach many students who are not in its programs, and its majors
can take many courses outside the department. Those are both real patterns, not
contradictions.

## What To Do When A Number Looks Wrong

Start with the local scope note or explain box. Then check:

- selected campus
- selected term or reporting edge
- course title for topics courses
- crosslist setting
- denominator and excluded rows
- whether the view is using DESR, Class Lists, Academic Studies, or Degrees

If the number still looks wrong, treat that as useful evidence. CEDAR's value is
that the scope, source, and code path are inspectable enough to audit.
