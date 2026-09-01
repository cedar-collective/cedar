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

Regstats shows courses where something is a bit out of the ordinary — waitlists building, drop counts changing, enrollment bumps — compared against each course's own historical averages.

It is most useful during active registration, when current patterns can still inform scheduling conversations, capacity checks, or outreach to departments.

Set your filters, click **Get Stats**, and the dashboard assembles across seven signal categories. A summary bar at the top shows counts in each category, the thresholds used, the comparison baseline, and whether the run came from cache.

---

## Filters

- **Campus / College / Department / Term / Level / PoT (Part of Term)** — standard scope filters. Campus defaults to ABQ and EA, Term defaults to the next term when CEDAR knows the current term, and Level defaults to lower division.
- Use an exact term code to inspect one term. Term-type values such as `fall` or `spring` scan several terms; each is compared separately with its own earlier matching offerings.

### Threshold controls

| Field | What it controls |
|---|---|
| **Min Impacted** | **Outside SD** must exceed this count for a course to appear in the bumps, dips, and drop tables. In Saturation, it is also the minimum class-list census enrollment for both target and historical course groups to be included. |
| **Min SDs** | Sets the width of that noise band, in standard deviations of the course's historical mean. Higher values require a larger deviation before any student counts as "outside," so fewer courses clear Min Impacted. |
| **Chronic Fill Rate** | The reconstructed fill a course must reach to count as "full." One control drives both the **Full now** label (this term) and the count of a course's prior **Terms at Cap**. Default 90%. |
| **Min Terms at Cap** | How many prior same-type terms at or above the Chronic Fill Rate a course needs before it's tagged **Chronically full**. Default 3. |
| **Min Waiting** | Minimum class-list true-demand count to appear in the High Waitlists tab. The threshold is inclusive. |

---

## How the comparisons work

{% include definition-summary.html id="regstats" %}
{% include definition-summary.html id="census-enrollment" %}

For enrollment and drop screens, **SDs from mean** is the deviation from the
comparison mean divided by the calculated spread. **Outside SD** subtracts
`Min SDs × spread` from the directional enrollment deviation (or the absolute
drop-count deviation). Rows appear when Outside SD exceeds **Min Impacted**.
These are descriptive screening thresholds, not statistical significance tests.

Drop alerts are deliberately selected by **counts**, because the operational
question is how many students are affected beyond the course's usual count
variation. The tables also show **Drop Rate**, **Rate Hist**, and **Rate Delta**
so a larger course can be distinguished from a higher probability of dropping.
Those rates provide context; they do not independently admit or remove a row.

For each target, the mean and spread use **exactly the same earlier observations**
of that course, delivery campus, college, season, and part of term. Population SD
is `sqrt(sum((history − mean(history))²) / n)`. The target and later terms do not
contribute. Selecting several targets does not pool their baselines: an earlier
selected term may legitimately supply history for a later one.

An SD comparison is unscored with fewer than two earlier observations or zero
historical variation. The scope bar reports those counts separately for
enrollment, early drops, late drops, and fill. **Unscored does not mean normal.**
Two observations permit a calculation but are still a small evidence base.

---

## Signal categories

Most tables include a **Trend** sparkline of the flagged metric across matching
offerings, with the selected term dotted in place. When reviewing an older term,
the line can include later offerings as context; they do not affect its flag.
A **▲/▼** chip describes the trend heading *into* the selected term. The tooltip
separately labels the full-arc trend and the **prior average** actually used for
comparison, including its number of earlier terms.

### Enrollment Bumps

Courses with reconstructed census enrollment higher than their historical average for the same term type. The key column calculations:

- **census_enrl_mean** — mean reconstructed census enrollment across strictly earlier matching offerings
- **SDs from mean** — (census_enrl − census_enrl_mean) ÷ pop_sd
- **Outside SD** — (census_enrl − census_enrl_mean) − (Min SDs × pop_sd)

Bumps are most important to inspect when the course is near capacity or when downstream demand (Downstream Concerns tab) suggests possible pressure next term based on courses typically taken after the bumped course.

---

### Enrollment Dips

Courses with reconstructed census enrollment **below** their historical average for the same term type — the mirror image of Enrollment Bumps. A dip can signal shifting student interest, a competing option, a scheduling or format change, or an instructor change that hasn't been widely noticed.

- **census_enrl_mean** — mean reconstructed census enrollment across strictly earlier matching offerings
- **SDs from mean** — (census_enrl − census_enrl_mean) ÷ pop_sd (negative for a dip)
- **Outside SD** — (census_enrl_mean − census_enrl) − (Min SDs × pop_sd)

The concern tier reflects the severity of the shortfall (a `_low`-direction tier).

---

### High Waitlists

Course-title, delivery-campus, college, term, and part-of-term groups where
class-list true demand is at least the `Min Waiting` threshold. The count uses
the same definition as the linked Waitlists page: distinct WL students after
removing anyone who also holds an RE/RS/RR registration in that matching group.
Duplicate WL rows do not add students. A large waitlist means expressed demand
is already outpacing available seats and may be worth a capacity or scheduling
check; it does not prove another section will fill.

---

### Saturation

The Saturation tab screens fill against earlier matching offerings. Its fill
measure divides the **class-list census proxy** (`registered + late drops`) by
**DESR scheduled capacity**. This keeps the numerator on one lifecycle source.
Only course groups matched at course, term, delivery campus, college, and part
of term enter the series. The scope bar reports unmatched groups, unusable
capacity, and groups below Min Impacted.

Every flagged course gets a **Status** tag for each signal it trips (a course can carry more than one):

- **Full now** — this term's fill is at or above the **Chronic Fill Rate** (default 90%).
- **Chronically full** — the course reached that ceiling in **Min Terms at Cap** or more prior same-type terms (default 3), *even if it's soft this term*.
- **Running hot** — fill is at least Min SDs above its prior mean, using population SD from at least two earlier matching offerings with positive variation. This describes occupancy above its usual level, not registration speed.

Only **Running hot** or **Chronically full** admits a course to this table.
**Full now** is an additional label on those rows, not an independent entry rule.

Columns:

- **Term Fill** (drives flagging) = class-list census proxy ÷ DESR scheduled capacity. Shown as the bar.
- **Hist Fill** = the same source-aligned fill measure averaged over earlier matching offerings. Read it next to Term Fill to compare the selected term with its prior pattern.
- **DESR snapshot fill** = DESR enrolled ÷ capacity, shown on hover as secondary source context. It represents final enrollment only when pulled after term end. A **▾N** marker shows the late drops included in the class-list census proxy when N is at least 5.
- **Fill Trend** = a sparkline of the same fill measure across matching offerings. Later terms can appear when reviewing an older target. Hover for the full-arc trend and the strictly prior comparison average.
- **SDs Hist** (`sd_above_mean`) = SDs above the course's own historical mean census fill — the Running hot signal (blank when there isn't enough history).
- **Terms at Cap** (`n_chronic_terms`) = prior same-type terms with census fill at or above the Chronic Fill Rate; **Min Terms at Cap** or more earns the Chronically full tag.

Sort by **Term Fill** for the highest selected-term fill, by **Hist Fill** or **Terms at Cap** for historically high fill, or by **SDs Hist** for fill furthest above its prior pattern.

Class-list statuses reconstruct who remained through census; they do not recover
a frozen census roster or peak occupancy. Capacity still comes from DESR, so
class-list and section extract dates can differ. Groups whose implied fill is
not usable for capacity analysis are excluded and counted in the scope bar.

---

### Early Drops

Courses with early withdrawals (DR/DD) different from their historical count
average. Higher counts may reflect scheduling conflicts, course-fit issues,
unclear descriptions, prerequisite mismatches, normal registration churn, or
simply a larger course. Unusually low counts can also appear and are labeled
with a low-direction concern tier.

Column calculations follow the same pattern as Enrollment Bumps:
- **dr_early_mean** — mean early-drop counts across strictly earlier matching offerings
- **SDs from mean** — (drop_early − dr_early_mean) ÷ pop_sd
- **Outside SD** — `abs(drop_early − dr_early_mean) − (Min SDs × pop_sd)`, flagged in either direction
- **Rate N** — class-list first-day proxy: still registered plus all early and late drops
- **Drop Rate** — early drops ÷ Rate N
- **Rate Hist** — mean Drop Rate across usable strictly earlier matching offerings
- **Rate Delta** — Drop Rate minus Rate Hist, in percentage points
- **Rate Terms** — prior offerings with a usable rate behind Rate Hist

---

### Late Drops

Courses with late-drop counts (DW/DG) different from their historical count
average. Higher counts are a prompt to inspect course difficulty, pacing,
section context, and student support conditions. Unusually low counts can also
appear and are labeled with a low-direction concern tier.

The count-screen calculations are identical in structure to Early Drops. For
rate context, **Rate N** is reconstructed census enrollment (`registered + late
drops`), **Drop Rate** is late drops ÷ Rate N, and **Rate Hist** is the mean of
usable prior offering rates. **Rate Delta** is their percentage-point difference.
The early and late denominators differ because they describe different points
in the registration lifecycle.

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

**Running hot** means fill is above its earlier pattern by the chosen SD threshold.
**Chronically full** means it reached the Chronic Fill Rate in enough earlier
matching terms, even if current fill is lower. Either signal admits a row to the
table. **Full now** additionally labels a displayed row at or above the fill
ceiling in the selected term.

**How current is the registration data?**

The "data as of" date in the summary bar is the newest DESR section-extract date
available to the app. It is not a guarantee that every selected term or the class
list was refreshed on that date. Consult the source dates when comparing terms.

---

## Data sources

Source: cedar_students (classlist registrations), cedar_sections (section capacity and status), and precomputed course-flow history when available. Anomaly detection and downstream flow assembly live in `R/features/regstats.R`.

---

## Related analyses

- [Enrollment tab](enrollment-tab) — section-level enrollment with Low Enrollment alerts and enrollment concerns for future terms
- [Dept Dashboard](dept-dashboard) — current-term snapshot including drop rate alerts by course
- [Course Dynamics](course-reports) — one-course view of enrollment history and drop patterns over time
