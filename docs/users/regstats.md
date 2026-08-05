---
title: Regstats
parent: User Guide
nav_order: 4
---

# Regstats
{: .fs-9 }

**Registration anomalies and demand pressure, compared against each course's own history**
{: .fs-6 .fw-300 }

---

Regstats shows courses where something is a bit out of the ordinary — waitlists building, drop rates changing, enrollment bumps — compared against each course's own historical averages.

It is most useful during active registration, when current patterns can still inform scheduling conversations, capacity checks, or outreach to departments.

Set your filters, click **Get Stats**, and the dashboard assembles across seven signal categories. A summary bar at the top shows counts in each category, the thresholds used, the comparison baseline, and whether the run came from cache.

---

## Filters

- **Campus / College / Department / Term / Level / PoT (Part of Term)** — standard scope filters. Campus defaults to ABQ and EA, Term defaults to the next term when CEDAR knows the current term, and Level defaults to lower division.
- Use exact term codes when you want a current-term anomaly run. Term-type values such as `fall` or `spring` are useful for broad scans, but exact term runs provide the clearest historical-only baseline.

### Threshold controls

| Field | What it controls |
|---|---|
| **Min Impacted** | The minimum **Outside SD** count — students (or drops) beyond the course's own noise band (see below) — for a course to appear in the bumps, dips, and drop tables. On the Saturation tab it doubles as a floor on section size (a course needs at least this many students at census to be considered). Keeps noisy small-scale signals out of the report. |
| **Min SDs** | Sets the width of that noise band, in standard deviations of the course's historical mean. Higher values require a larger deviation before any student counts as "outside," so fewer courses clear Min Impacted. |
| **Chronic Fill Rate** | The census fill a course must reach to count as "full." One control drives both the **Full now** flag (this term) and the count of a course's prior **Terms at Cap**. Default 90%. |
| **Min Terms at Cap** | How many prior same-type terms at or above the Chronic Fill Rate a course needs before it's tagged **Chronically full**. Default 3. |
| **Min Waiting** | Minimum waitlist count to appear in the High Waitlists tab. |

---

## How the comparisons work

All comparisons are **term-type matched**: fall courses are compared to prior fall terms, spring courses to prior spring terms. This prevents usual term variation from creating false signals.

Means are computed from **historical terms only**, excluding the current/target term — so the reference baseline is not biased by the data being evaluated.

**Population standard deviation** is used throughout. Because CEDAR is working with all courses in the filtered scope rather than a statistical sample, population SD is the appropriate measure.

**SDs from mean** = (metric − historical mean) ÷ population SD

**Outside SD** = |metric − historical mean| − (Min SDs × population SD)
Outside SD is the number of students beyond the course's own noise band. A course with 40 students above its mean but a large historical SD might show a low Outside SD; a course with 15 above its mean but consistently tight variance shows a higher one. A course is flagged when its Outside SD exceeds **Min Impacted** — a single test that already guarantees the deviation is past the Min SDs band, so the two controls work together rather than as independent filters. (For drops, which are flagged in both directions, Outside SD is the magnitude and the concern tier carries the direction.)

---

## Signal categories

Most tables include a **Trend** sparkline: the flagged metric — enrollment for bumps and dips, the drop count for early and late drops, census fill for saturation — plotted across the course's prior offerings of the same term type and part of term, with the current term dotted in place. A **▲/▼** chip gives the rate of change heading *into* that term (per term); hovering shows the full-arc trend and the historic average. It is the fastest way to tell a one-term anomaly from a developing trend — a dip at the end of a steadily falling line is a very different situation from a single low point in an otherwise flat history.

### Enrollment Bumps

Courses with registration higher than their historical average for the same term type. The key column calculations:

- **registered_mean** — mean enrollment across prior terms of the same type, excluding the current term
- **SDs from mean** — (registered − registered_mean) ÷ pop_sd
- **Outside SD** — (registered − registered_mean) − (Min SDs × pop_sd)

Bumps are most important to inspect when the course is near capacity or when downstream demand (Downstream Concerns tab) suggests possible pressure next term based on courses typically taken after the bumped course.

---

### Enrollment Dips

Courses with registration **below** their historical average for the same term type — the mirror image of Enrollment Bumps. A dip can signal shifting student interest, a competing option, a scheduling or format change, or an instructor change that hasn't been widely noticed.

- **registered_mean** — mean enrollment across prior terms of the same type, excluding the current term
- **SDs from mean** — (registered − registered_mean) ÷ pop_sd (negative for a dip)
- **Outside SD** — (registered_mean − registered) − (Min SDs × pop_sd)

The concern tier reflects the severity of the shortfall (a `_low`-direction tier).

---

### High Waitlists

Courses where the waitlist count exceeds the `Min Waiting` threshold. A large waitlist means demand is already outpacing available seats and may be worth a capacity or scheduling check.

---

### Saturation

The Saturation tab flags courses under enrollment pressure, each compared to its own history. Fill is measured at **census** — the point in the term when enrollment is officially counted — so the current term and its history are compared the same way.

Every flagged course gets a **Status** tag for each signal it trips (a course can carry more than one):

- **Full now** — this term's fill is at or above the **Chronic Fill Rate** (default 90%).
- **Chronically full** — the course reached that ceiling in **Min Terms at Cap** or more prior same-type terms (default 3), *even if it's soft this term*.
- **Running hot** — the course is filling faster than its own history: fill deviation above the Min SDs band, with at least two prior terms of history. This is relative to the course's *own* norm, not to any absolute ceiling, so a course can run hot without being anywhere near full.

Columns:

- **Term Fill** (drives flagging) = this term's census headcount ÷ capacity, where census headcount = still-registered students **plus late drops** (present at census but withdrawn after the deadline). Shown as the bar.
- **Hist Fill** = the same census measure averaged over the course's prior same-type offerings — how full it runs *usually*, independent of this term. Read it next to Term Fill to spot a normally-packed course that's soft this term, or the reverse.
- **Final Fill** = end-of-term headcount ÷ capacity, after melt. Folded into the Term Fill cell: a **▾N** marker appears when a course sheds N (5 or more) students after census, and the final fill shows on hover.
- **Fill Trend** = a sparkline of the course's census fill across its prior offerings of the same term type **and** part of term (e.g. past falls, full-term only — the same matching used for the baseline and the Terms at Cap count), with the term you're viewing dotted in context. The **▲/▼** chip is the trend *heading into* that term (points per term, so it matches the dot); hover for the full-arc trend and the historic average.
- **SDs Hist** (`sd_above_mean`) = SDs above the course's own historical mean census fill — the Running hot signal (blank when there isn't enough history).
- **Terms at Cap** (`n_chronic_terms`) = prior same-type terms with census fill at or above the Chronic Fill Rate; **Min Terms at Cap** or more earns the Chronically full tag.

Sort by **Term Fill** for what's maxed *now*, by **Hist Fill** or **Terms at Cap** for what's *usually* packed, or by **SDs Hist** for what's filling faster than its own pattern.

Why census rather than end-of-term? A course can fill completely at census and then lose students to late withdrawals. Measuring at term end would make it look less saturated than it really was — and because historical data is pulled after terms close, it would deflate every course's baseline. Census fill removes that bias. (For an upcoming term no drops have happened yet, so census and final fill are the same live number.)

---

### Early Drops

Courses with pre-census withdrawals (DR) significantly different from their historical average. Higher rates may reflect scheduling conflicts, course-fit issues, unclear descriptions, prerequisite mismatches, or normal registration churn. Unusually low rates can also appear and are labeled with a low-direction concern tier.

Column calculations follow the same pattern as Enrollment Bumps:
- **dr_early_mean** — mean early drops across prior terms of the same type
- **SDs from mean** — (drop_early − dr_early_mean) ÷ pop_sd
- **Outside SD** — |drop_early − dr_early_mean| − (Min SDs × pop_sd), flagged in either direction

---

### Late Drops

Courses with post-census withdrawals (DW/DG) significantly different from their historical average. Late drops appear on transcripts and may affect financial aid, so higher late-drop rates are a prompt to inspect course difficulty, pacing, section context, and student support conditions. Unusually low rates can also appear and are labeled with a low-direction concern tier.

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

A course with very low historical variance has a narrow noise band, so even a modest change can land outside it. **Min Impacted** is the backstop — the minimum number of students beyond the band — so raising it filters out small-scale signals regardless of variance; raising **Min SDs** widens the band itself.

**What's the difference between the Running hot, Chronically full, and Full now tags?**

**Running hot** means a course is filling *faster than its own norm this term* — a big jump above its usual fill, whatever the absolute level. **Chronically full** means it reached the Chronic Fill Rate in enough prior same-type terms (Min Terms at Cap) — a standing capacity problem, shown *even if it happens to be soft this term*. **Full now** means it's simply at or above the ceiling this term. A course can carry any combination of the three: a course that's usually packed *and* running above even its own high baseline this term shows both Chronically full and Running hot.

**How current is the registration data?**

The "data as of" date in the summary bar reflects when the underlying CEDAR data was last extracted from Banner — typically nightly during the academic year.

---

## Data sources

Source: cedar_students (classlist registrations), cedar_sections (section capacity and status), and precomputed course-flow history when available. Anomaly detection and downstream flow assembly live in `R/features/regstats.R`.

---

## Related analyses

- [Enrollment tab](enrollment-tab) — section-level enrollment with Low Enrollment alerts and enrollment concerns for future terms
- [Dept Dashboard](dept-dashboard) — current-term snapshot including drop rate alerts by course
- [Course Dynamics](course-reports) — one-course view of enrollment history and drop patterns over time
