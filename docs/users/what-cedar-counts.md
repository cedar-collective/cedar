---
title: What CEDAR Counts
parent: User Guide
nav_order: 19
---

# What CEDAR Counts
{: .fs-9 }

CEDAR is built from snapshots of institutional source data. Most numbers are
counts of rows or unique people after CEDAR applies a clear scope: term, campus,
department, course, program, status, and sometimes grade outcome. This page
defines the common measures so the same words mean the same thing across tabs.

{: .note }
CEDAR is for exploration, planning, and methodological transparency. It is not a
census-freeze or official-reporting system unless your institution has built a
separate certified process around it.

## Enrollment Counts

| Measure | What it counts | Common use |
|:--|:--|:--|
| DESR enrollment | Section headcount from the Department Enrollment Status Report snapshot. | Schedule-facing views, capacity, available seats. |
| Class-list registered | Distinct class-list students with registered status codes: `RE`, `RS`, or `RR`. | Course Dynamics enrollment history and course-attempt denominators. |
| Census-style enrollment | Class-list registered students plus late drops: `registered + late drops`. | Demand/capacity questions where students who stayed past census should count. |
| Final enrollment | Students still registered when the class list was pulled. | End-of-term course participation. |
| Waitlist | Class-list rows with status `WL`. | Unmet demand; not counted as enrolled seats. |

DESR and class-list numbers can differ because they come from different extracts
and may be pulled at different times. For current or future terms, DESR usually
looks like live registration. For older terms, it usually looks closer to final
post-drop enrollment.

## Registration Status

| Status group | Codes | How CEDAR treats it |
|:--|:--|:--|
| Registered | `RE`, `RS`, `RR` | Counts as enrolled/registered. |
| Waitlisted | `WL` | Counts as waitlist demand, not enrollment. |
| Early drop | `DR`, `DD` | Shown separately as registration churn; not counted as DFW. |
| Late drop | `DG`, `DW` | Treated like a withdrawal outcome for DFW/drop analytics. |

`DD` means drop/delete with full tuition refund and is handled with early drops.
Unexpected registration codes are not silently reclassified; relevant app tables
surface them when they appear in outcome-sensitive data.

## Grade Outcomes

| Measure | What it counts |
|:--|:--|
| Passing for CEDAR DFW analytics | A+ through C, CR, and equivalent passing retake grades. |
| DFW / nonpassing outcome | By default: C-, D-range, F, W, I, NC, NR, P, S, other recorded non-audit grades, and late drops (`DG`, `DW`). |
| Optional sub-C exception | Where a visible toggle is offered, users may opt in to treating C-, D+, D, and D- as passing. P and S remain nonpassing. Without a toggle, the default applies. |
| Early drop | `DR` or `DD`; not included in D/F/W rates. |
| Missing grade | A row with a blank or missing final-grade field after status handling; excluded from the outcome denominator. An unexpected nonblank grade fails closed as nonpassing rather than disappearing. |
| Audit | Audit rows are excluded from DFW calculations; they are neither passing nor failing outcomes. |

Course outcome denominators usually exclude early drops because those students
left before the outcome window. Early drops are still useful, but they answer a
different question: registration churn rather than academic outcome.

## Headcount

Headcount is program-based. A student is counted when they have a matching
program, major, minor, concentration, or certificate record in Academic Studies
data. Program headcount answers "who is declared in this program?" not "who is
taking this department's classes?"

When Pathways builds a population, it uses observed program records and may
separate full majors from pre-majors. Timing metrics use the first observed
class-list enrollment in CEDAR, not a formal admissions or matriculation date.

## Credit Hours

Student Credit Hours are one student times the credit value of one course.
CEDAR's Dept Trends credit-hour views count credits attached to passing outcomes
only. Because that is an earned-credit view, it may differ from reports that use
attempted credits, census enrollment, or all registered students.

## Retention And Persistence

Retention and persistence views ask whether a student appears in a later term or
has graduated. Graduation counts as retained because the student completed the
institutional outcome rather than stopping out. Future terms beyond the loaded
data window are left blank rather than treated as 0%.

Course Dynamics retention starts with students registered in one course in one
term. Pathways retention starts with a selected student population. Those are
different cohorts and should not be expected to match.

## Courses, Crosslists, And Topics

CEDAR tries to preserve meaningful course identity:

- Crosslisted sections may be compressed or split depending on the tab.
- Combined lecture/lab courses with a `C` suffix are counted as one course when
  the question is course offerings rather than CRN count.
- Topics courses can share a course number while having different titles; views
  that need course identity keep the title so distinct topics are not collapsed.

When a table shows repeated-looking rows, check whether the row is separated by
campus, course title, section, part of term, crosslist status, or instructor.

## Reading A Rate

For any percentage, ask three questions:

1. What is the numerator?
2. What is the denominator?
3. Which rows were excluded before the rate was computed?

CEDAR's in-app blue explain boxes answer those questions near complex tables.
This page gives the shared vocabulary; the local table note gives the exact
scope for that view.
