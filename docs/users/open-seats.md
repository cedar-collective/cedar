---
title: Open Seats
parent: User Guide
nav_order: 10
---

# Open Seats
{: .fs-9 }

**Courses with available capacity, compared year-over-year, with DFW history**
{: .fs-6 .fw-300 }

---

Open Seats shows which courses have room in the selected term, how that availability has changed from the same term last year, and what the historical CEDAR DFW/nonpassing rate looks like for each course. It is most useful before a term begins or during early registration, when available seats can still inform advising, scheduling, or capacity conversations.

Set your filters — campus, college, department, term, part of term, instruction method, and level — then click **Find Open Seats**. Results appear across six tabs.

---

## Filters

| Filter | What it controls |
|---|---|
| **Campus** | Which campus locations to include. Defaults to ABQ and EA. |
| **College** | Narrows to courses in a specific college. |
| **Department** | Narrows to a single department's offerings. |
| **Term** | The target term to examine. Defaults to the upcoming term. Supply two terms (`202410,202510`) to compare specific years; otherwise CEDAR automatically compares to the same term one year prior. |
| **PoT (Part of Term)** | Filter by part-of-term codes (e.g., `1H` = first half, `2H` = second half, `FT` = full term). |
| **Method** | Delivery method (online, face-to-face, hybrid, etc.). |
| **Level** | `lower`, `upper`, `grad`, or `split`. |

---

## Tabs

### Courses

The primary availability table. One row per course per part-of-term, filtered to sections with at least one open seat.

| Column | Meaning |
|---|---|
| **avail** | Seats currently available (max enrollment minus registered). |
| **enrolled** | Current enrollment count. |
| **DFW %** | Historical nonpassing rate for this course under the same college/department scope, averaged across prior terms with final outcomes. Only A+ through C and CR pass by default; other recorded non-audit outcomes and late drops count as DFW, while early drops do not. Blank if no prior grade data exists. |
| **avail_diff** | Change in available seats compared to the same course in the prior-year term. Positive means more open seats than last year; negative means fewer. |

---

### Common

Courses offered in **both** the target term and the comparison year, with year-over-year enrollment change.

| Column | Meaning |
|---|---|
| **enrl_diff_from_last_year** | Enrollment this term minus enrollment the same term last year. Negative values indicate lower enrollment than the prior year. |

Use this tab to spot courses where demand is declining or growing relative to prior-year patterns.

---

### Prev

Courses offered in the **prior-year** comparison term that are **not** scheduled this term (discontinued or not yet added). These are potential gaps to check, especially for courses that usually sit in a sequence or regular rotation.

---

### New

Courses scheduled this term that were **not** offered in the prior-year comparison term. New offerings that have no enrollment history; DFW data will be blank.

---

### Gen Ed

Gen Ed courses with at least one open seat in the target term, sorted by gen ed area and then by availability descending. Use this to answer "which gen ed areas have room?" at a glance.

---

### Gen Ed Likely

Gen Ed courses with **zero** available seats and **zero** enrolled students. These sections exist in Banner but are fully capped and empty — they may open later as capacity is adjusted. Useful for tracking planned offerings that haven't gone live yet.

---

## Methodology notes

### Term comparison
When you select a single term, CEDAR automatically pairs it with the same term one year prior (term code minus 100). To compare across a different span — say, two consecutive spring terms — enter both codes separated by a comma in the Term filter: `202410,202510`.

### DFW rate
{% include definition-summary.html id="dfw" %}

A blank DFW cell means no eligible grade history matched the current query; it
is not proof that the course has never had grades.

### Availability vs. Banner capacity
`avail` is derived from Banner's max enrollment minus the registered count at the time data was last refreshed. Waitlisted students are **not** counted as enrolled; a full section with a long waitlist will still show `avail = 0`.
