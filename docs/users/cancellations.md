---
title: Cancellations
parent: User Guide
nav_order: 11
---

# Cancellations
{: .fs-9 }

**Cancelled sections and cancellation timing**
{: .fs-6 .fw-300 }

---

Cancellations shows scheduled sections that were cancelled, along with timing context relative to the section start date. It lives under **Explore -> Cancellations**.

Use it when you need to review cancellation patterns by term, department, course, level, part of term, or delivery method. The view is descriptive: it shows what was cancelled and when, not why the cancellation happened.

---

## Filters

Set the filter stripe, then click **Find Cancellations**.

| Filter | What it controls |
|---|---|
| **Campus / College / Department** | Limits the sections included in the run. |
| **Term** | Accepts exact term codes or term-type values such as fall or spring. |
| **PoT** | Limits to selected parts of term. |
| **Method** | Limits by delivery method. |
| **Level** | Limits by course level. Defaults to lower division. |

The link button copies a shareable URL for the current view.

---

## Views

| View | What it shows |
|---|---|
| **Cancelled Sections** | Section-level rows: term, department, course, title, section, CRN, enrollment/capacity, cancellation date, start date, days before start, and comments where available. |
| **By Department** | Cancelled section counts by department and term. |
| **Timing** | Cancellation counts by days before course start, limited to 0-100 days before start. |
| **Common Courses** | Courses with repeated cancellation patterns across terms. |
| **Trends** | Term-level cancellation counts by department. Units outside the top ten are grouped as Other. |

---

## Methodology Notes

Cancellations uses section records with status `C`. Removed (`R`) and suspended (`S`) sections are shown in the scope stripe as not included.

Timing is based on parsed cancellation dates from section comments when available, compared with the course start date. If start date is missing, the timing logic falls back to census date where possible. Rows with missing timing dates, cancellations after start, or cancellations more than 100 days before start are excluded from the Timing plot but remain part of the section-level cancellation count.

The Trends view ignores exact term-code filters so it can show broader term patterns. Fall, Spring, and Summer term-type filters are retained.

---

## Related Analyses

- [Enrollment](enrollment-tab) — scheduled and historical section-level enrollment
- [Open Seats](open-seats) — current or future capacity by course
- [Regstats](regstats) — registration pressure and anomaly signals
