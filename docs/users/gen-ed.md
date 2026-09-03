---
title: Gen Ed
parent: User Guide
nav_order: 13
---

# Gen Ed
{: .fs-9 }

**Aggregate Gen Ed enrollment and grade outcomes**
{: .fs-6 .fw-300 }

---

Gen Ed provides an institution-level view of Gen Ed courses. It lives under **Explore -> Gen Ed**.

Use it to review Gen Ed enrollment by modality, the major mix of students in selected Gen Ed seats, the largest Gen Ed courses in the selected scope, department summaries, DFW rates, and grade distributions. It is an aggregate view; department-specific Gen Ed instructor associations live inside [Dept Trends](department-reports) and use restricted access where instructor outcomes are shown.

---

## Filters

Set the filter stripe, then click **Run**.

| Filter | What it controls |
|---|---|
| **Campus / College / Department** | Limits Gen Ed sections included in the run. |
| **Gen Ed Area** | Limits to selected Gen Ed areas. |
| **From term / To term** | Sets the historical term window. |

Click **Run** to update the summary cards and views. Course, grade-distribution, and instructor outcome rows use a fixed five-attempt display threshold; there is no Min N control on this page.

---

## Views

| View | What it shows |
|---|---|
| **Summary cards** | Gen Ed courses, departments, section enrollment, distinct students, and overall DFW rate. |
| **Enrollment by Modality** | Enrollment split by face-to-face and online modality over time. |
| **Major Mix in Gen Ed Courses** | Major/program mix for students enrolled in the selected Gen Ed course set. Counts are enrollments, so a student taking two selected Gen Ed courses contributes two seats. |
| **Top Gen Ed Courses by Enrollment** | Enrollment trends for the largest courses in the selected scope, with faded course lines and a dashed average trend line for the courses shown. |
| **Department Summary** | Course and enrollment counts by department. |
| **DFW Rates by Course** | Course-level DFW, withdrawal, non-withdrawal DFW, D/F, and C- measures for course-campus groups with at least five classified attempts. |
| **Grade Distribution** | Grade distribution rows for course-campus groups with at least five classified attempts. The Attempts column uses the same denominator as the DFW table. |

---

## Methodology Notes

{% include definition-summary.html id="dfw" %}

Enrollment figures use section rows. DFW and grade tables use class-list course attempts under the shared definition above. Rows in those tables must meet the fixed five-attempt display threshold. The overall DFW summary card instead uses all classified attempts in the selected scope, so it is not calculated from only the visible course rows.

The major-mix donut uses registered student enrollment rows. The enrollment row's major code is the baseline because it is attached to the course term; when a same-term primary `Major` program record is available, CEDAR uses it for cleaner names and pre-major labels. Small or lower-ranked majors are grouped into "Other."

The DFW table and Grade Distribution table use the same outcome denominator. **DFW % equals Non-W DFW % plus W %.** Non-W DFW includes every non-withdrawal outcome classified as nonpassing by the shared policy, including C-, D, F, P, S, I, NC, NR, and unfamiliar recorded non-audit grades; it is broader than literal grades below C. Early drops are reported separately in the DFW table and are excluded from Grade Distribution totals.

Current or future terms can show enrollment without grade outcomes because final grades are not yet available. Sparse departments may also show enrollment charts while outcome tables are empty because their course-campus groups do not meet the fixed threshold.

Instructor-level Gen Ed rows, where available in department-scoped views, are descriptive associations rather than causal evidence of instructor effects.

---

## Related Analyses

- [Dept Trends](department-reports) — department-scoped Gen Ed and restricted instructor outcomes
- [Pathways](pathways) — selected-population course-to-major and Gen Ed-only course filters
- [Course Dynamics](course-reports) — one-course enrollment and outcome history
