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

Use it when you need program-based headcount over time: majors, minors, concentrations, or combinations of those filters. This is different from counting students sitting in a department's courses; for course enrollment, use [Enrollment](enrollment-tab). The [Dept Dashboard](dept-dashboard) also has program-based headline headcounts.

---

## Filters

Set the filters, then click **Update Headcount**.

| Filter | What it controls |
|---|---|
| **Campus** | Limits by student campus. |
| **College** | Limits records by student college and narrows the available departments and programs. |
| **Department** | Limits program records and available choices by department code or CEDAR's program-to-department mappings. Leave unselected for combinations across departments. |
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

## Download

After running Headcount, use **Download headcount CSV** to export the summarized table behind the charts. The file includes the term code, readable term label, student level, program type, program or department fields where applicable, degree, and student count.

---

## Methodology Notes

{% include definition-summary.html id="program-headcount" %}

---

## Related Analyses

- [Dept Trends](department-reports) — historical department report with program headcount
- [Dept Dashboard](dept-dashboard) — selected-term program headcounts and course activity
- [Pathways](pathways) — selected-population analyses built from program records
