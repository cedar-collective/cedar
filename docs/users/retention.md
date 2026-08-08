---
title: Retention
parent: User Guide
nav_order: 16
---

# Retention
{: .fs-9 }

**Course-anchored views of whether students stay enrolled in later terms**
{: .fs-6 .fw-300 }

---

Retention shows institution-level persistence after a course enrollment anchor.
It lives under **Explore -> Retention**.

Use it when you want to ask questions like:

- Which courses were students taking in a term before they did or did not return?
- How does later enrollment compare across courses in the same term?
- For one course, has subsequent retention changed across offerings?

This tab is descriptive. It can show where a pattern deserves attention, but it
does not by itself prove that a course caused students to stay or leave.

---

## What Counts As Retained

A student is counted as retained when they have any registered enrollment record
at UNM in the target future term. The measure is institution-level retention,
not retention in the same major, department, college, or course sequence.

Summer terms are skipped when counting forward. A "+1 sem" value means the next
regular term, not necessarily the next calendar term.

Rows are suppressed when they do not meet the selected **Min students per row**
threshold. This protects privacy and avoids presenting unstable rates as if
they were reliable signals.

For shared definitions, see [What CEDAR Counts](what-cedar-counts).

---

## Display Options

| Control | What it does |
|---|---|
| **Semesters to track** | How many regular future terms to check, from +1 to +8. |
| **Min students per row** | Minimum cohort size needed for a course/term/instructor row to appear. |

Changing these controls affects both retention views.

---

## Course Comparison

Course Comparison starts from one anchor term and compares later retention
across courses.

Use it to scan a term for courses whose enrolled students returned at unusually
high or low rates in later terms. You can leave **Course(s)** blank to include
all courses, or select one or more courses to narrow the table.

Columns:

| Column | Meaning |
|---|---|
| **Course** | The subject-course value used as the anchor. |
| **Students** | Students registered in that course in the selected term, after the minimum-size filter. |
| **+1 sem, +2 sem, ...** | Share of those students still enrolled at UNM that many regular semesters later. |

---

## Course Trend

Course Trend starts from one course and compares its retention pattern across
terms.

Use it to see whether later enrollment after a specific course has been stable,
improving, declining, or too noisy to interpret. Optional instructor breakout
shows rows by instructor when available, but those rows should be read as
descriptive context, not individual evaluation.

Columns:

| Column | Meaning |
|---|---|
| **Term** | The course offering term. |
| **Instructor** | Included only when instructor breakout is selected. |
| **Students** | Students registered in that course offering. |
| **+1 sem, +2 sem, ...** | Share of those students still enrolled at UNM that many regular semesters later. |

---

## Reading The Results

Retention rates are most useful as prompts for better questions:

- Did the course enroll many first-year, transfer, or near-graduation students?
- Is the course a gateway, elective, prerequisite, or high-DFW course?
- Did the term have unusual enrollment disruption?
- Are small cohorts making the rate unstable?
- Does [Course Dynamics](course-reports) show related DFW, rollcall, or sequence
  patterns for the same course?

Blank or missing values usually mean the future term is not yet observable in
the loaded data, or the row did not meet the minimum student threshold.

---

## Related Analyses

- [Course Dynamics](course-reports) - course-level enrollment, DFW, flow, and
  course-specific retention context
- [Dept Dashboard](dept-dashboard) - current-term course activity and attention
  signals
- [Dept Trends](department-reports) - longer-term department trends
- [What CEDAR Counts](what-cedar-counts) - shared counting definitions
