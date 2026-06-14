---
title: Regstats
parent: User Guide
nav_order: 3
---

# Regstats
{: .fs-9 }

**Registration anomalies and demand pressure, compared against each course's own history**
{: .fs-6 .fw-300 }

---

Regstats surfaces courses where something is a bit out of the ordinary — waitlists building, drop rates spiking, enrollment surges — compared against each course's own historical averages. 

It is most useful during active registration, when there is still time to act: open a section, raise capacity, or reach out to departments.

Set your filters, click **Get Stats**, and the dashboard assembles across seven signal categories. A summary bar at the top shows counts in each category, the thresholds used, the comparison baseline, and whether the run came from cache.

---

## Filters

- **Campus / College / Department / Term / Level / PoT (Part of Term)** — standard scope filters. Campus defaults to ABQ and EA, Term defaults to the next term when CEDAR knows the current term, and Level defaults to lower division.
- Use exact term codes when you want a current-term anomaly run. Term-type values such as `fall` or `spring` are useful for broad scans, but exact term runs provide the clearest historical-only baseline.

### Threshold controls

| Field | What it controls |
|---|---|
| **Min Impacted** | Filters all anomaly tables by the raw excess count — students (or drops) above the mean beyond what normal variance explains. Keeps noisy small-scale signals out of the report. |
| **Min SDs** | Filters by standard deviations above the course's historical mean. Higher values surface only the most extreme deviations. |
| **Chronic Fill Rate** | The current fill rate a course must exceed to appear as chronic saturation. Historical chronic evidence counts prior same-type terms at or above 80%. |
| **Min Waiting** | Minimum waitlist count to appear in the High Waitlists tab. |

---

## How the comparisons work

All comparisons are **term-type matched**: fall courses are compared to prior fall terms, spring courses to prior spring terms. This prevents usual term variation from creating false signals.

Means are computed from **historical terms only**, excluding the current/target term — so the reference baseline is not biased by the data being evaluated.

**Population standard deviation** is used throughout. Because CEDAR is working with all courses in the filtered scope rather than a statistical sample, population SD is the appropriate measure.

**SDs from mean** = (metric − historical mean) ÷ population SD

**Impacted** = (metric − historical mean) − (Min SDs × population SD)
Impacted is the excess above what normal variance explains, given the Min SDs threshold. A course with 40 students above its mean but a large historical SD might show low impacted; a course with 15 above its mean but consistently tight variance shows higher impacted. Both Min SDs and Min Impacted filter independently — a course must clear both to appear.

---

## Signal categories

### Enrollment Bumps

Courses with registration higher than their historical average for the same term type. The key column calculations:

- **registered_mean** — mean enrollment across prior terms of the same type, excluding the current term
- **SDs from mean** — (registered − registered_mean) ÷ pop_sd
- **impacted** — (registered − registered_mean) − (Min SDs × pop_sd)

Bumps are most actionable when the course is near capacity or when downstream demand (Downstream Concerns tab) suggests pressure may manifest next term based on courses typically taken after the bumped course.

---

### High Waitlists

Courses where the waitlist count exceeds the `Min Waiting` threshold. A large waitlist means demand is already outpacing available seats. Consider opening an additional section or increasing capacity.

---

### Emerging Saturation

Courses whose current fill rate is significantly higher than their own historical fill rate average for the same term type. Flagged when the fill rate deviation exceeds the Min SDs threshold.

- **fill_rate** = enrolled ÷ (enrolled + available seats)
- **sd_above_mean** = SDs above the course's historical mean fill rate

A course appearing here is filling faster than its own norm — an early signal of growing demand before capacity has been adjusted. Not the same as simply being near full; the comparison is to the course's own pattern.

---

### Saturation

The Saturation tab combines two related signals:

- **Emerging Saturation** — current fill rate is significantly above the course's own historical fill-rate average for the same term type.
- **Chronic Saturation** — current fill rate is at or above the Chronic Fill Rate control, and the course has had 3 or more prior same-type terms with fill rate at or above 80%.

A course appearing in both is filling faster than usual *and* has been consistently near capacity for years.

---

### Early Drops

Courses with pre-census withdrawals (DR) significantly different from their historical average. High rates often reflect scheduling conflicts, unclear course descriptions, or prerequisite mismatches — things that may be correctable mid-registration. Unusually low rates can also appear and are labeled with a low-direction concern tier.

Column calculations follow the same pattern as Enrollment Bumps:
- **dr_early_mean** — mean early drops across prior terms of the same type
- **SDs from mean** — (drop_early − dr_early_mean) ÷ pop_sd
- **impacted** — (drop_early − dr_early_mean) − (Min SDs × pop_sd)

---

### Late Drops

Courses with post-census withdrawals (DW/DG) significantly different from their historical average. Late drops appear on transcripts and may affect financial aid — high late-drop rates are a stronger signal than early drops of course difficulty, pacing, or student support gaps. Unusually low rates can also appear and are labeled with a low-direction concern tier.

Column calculations are identical in structure to Early Drops.

---

### Downstream Concerns

Courses expected to see extra demand next term, based on enrollment flow patterns. Two types of signals:

- **Bump** — the destination course is commonly taken immediately after one or more bump courses (based on historical enrollment flow). If MATH 1430 has a bump this term, and students typically take MATH 1440 next, MATH 1440 is flagged as a downstream concern.
- **Drop** — the course itself had unusually high drops this term, suggesting some students may attempt to re-enroll.

**Top feeders** shows up to 3 upstream bump courses by historical flow volume (for Bump signals), or the drop signal types (for Drop signals).

This tab requires scanning the full enrollment history and takes longer to generate. Click **Load Downstream Concerns** when you are ready.

{: .note }
Downstream analysis is most meaningful when run without a department filter, since flow patterns cross departmental boundaries. When a department is selected, only destination courses within that department are shown — useful for a specific unit but may miss cross-departmental pressure.

---

## Common questions

**Why do I see courses with small enrollment differences flagged?**

The SD-based filter can surface courses with small absolute differences if their historical variance is very low. Raise Min SDs or Min Impacted to focus on larger deviations.

**What's the difference between Emerging and Chronic Saturation?**

Emerging Saturation detects courses filling *faster than their own norm this term*. Chronic Saturation detects courses that have been *near capacity for years* and remain so now. A course can appear in both, in either, or in neither depending on its pattern.

**How current is the registration data?**

The "data as of" date in the summary bar reflects when the underlying CEDAR data was last extracted from Banner — typically nightly during the academic year.

**Can I download the report?**

Yes — click the **Download report** link in the summary bar to get a formatted HTML report of the current dashboard.

---

## Data sources

Source: cedar_students (classlist registrations), cedar_sections (section capacity and status), and precomputed course-flow history when available. Anomaly detection and downstream flow assembly live in `R/reports/regstats.R`.

---

## Related analyses

- [Enrollment tab](enrollment-tab) — section-level enrollment with Low Enrollment alerts and enrollment concerns for future terms
- [Dept Dashboard](dept-dashboard) — current-term snapshot including drop rate alerts by course
- [Course Dynamics](course-reports) — deep dive into a single course's enrollment history and drop patterns over time
