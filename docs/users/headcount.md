---
title: Headcount
parent: User Guide
nav_order: 14
---

# Headcount
{: .fs-9 }

**Unduplicated declared-program counts by term**
{: .fs-6 .fw-300 }

---

Headcount counts unique students with active declared program records by term. It lives under **Explore -> Headcount**.

Use it when you need program-based headcount over time: majors, minors, concentrations, or combinations of those filters. This is different from counting students sitting in a department's courses; for course-enrollment headcount, use [Dept Dashboard](dept-dashboard) or [Enrollment](enrollment-tab).

---

## Filters

Set the filters, then click **Update Headcount**.

| Filter | What it controls |
|---|---|
| **Campus** | Limits by student campus. |
| **College** | Limits available departments and programs to the selected college. |
| **Department** | Limits available majors, minors, and concentrations using CEDAR's program-to-department mappings. |
| **Major** | Counts students holding selected majors or second majors. |
| **Minor** | Counts students holding selected first or second minors. |
| **Concentration** | Counts students holding selected concentrations. |

The major, minor, and concentration controls update based on the broader college and department selections.

---

## Charts

Headcount returns two plots:

| Chart | What it shows |
|---|---|
| **Undergraduate Headcount** | Unique undergraduate students with matching active declared program records by term. |
| **Graduate Headcount** | Unique graduate students with matching active declared program records by term. |

Each point is a term. The count is unique students, not registrations.

---

## Methodology Notes

Headcount uses `cedar_programs`, which is derived from Banner Academic Studies records. A student with three course enrollments still counts once in Headcount if they have one matching active program record in that term.

Students can appear in more than one department when their declared programs cross departments. For example, a student with a History major and an Anthropology minor appears under each department when those departments are selected separately.

Combining filters narrows the count. Selecting both a major and a minor counts students who hold both at the same time, not students who hold either one.

---

## Related Analyses

- [Dept Trends](department-reports) — historical department report with program headcount
- [Dept Dashboard](dept-dashboard) — current-term students enrolled in a department's sections
- [Pathways](pathways) — selected-population analyses built from program records
