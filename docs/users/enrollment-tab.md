---
title: Enrollment Tab
parent: User Guide
nav_order: 3
---

# Enrollment Tab
{: .fs-9 }

**Section-level and student-level enrollment data with flexible filtering**
{: .fs-6 .fw-300 }

---

The Enrollment tab is the primary workspace for exploring enrollment data across courses, departments, terms, and instructors. Set your filters at the top and click **Refresh Data** — the sub-tabs below update to show different views of the same filtered dataset.

---

## Filters

The filter bar at the top applies across all sub-tabs:

- **Campus / College / Department / Term / Course** — standard drill-down filters. Use Term to select a specific term or term type (e.g., "Fall" to compare all fall semesters across years).
- **Group by** — collapses individual sections into grouped rows with summed enrollment. For example, grouping by `subject_course` shows one row per course with total enrollment across all sections; adding `term` alongside `subject_course` shows trends over time.
- **Instructor** — filter to a specific instructor; type to search.
- **Exclude List** — when checked, removes independent studies, thesis credits, dissertation credits, honors credits, and similar special-enrollment courses. The list is in `R/lists/excluded_courses.R` and contains approximately 200 course codes. Uncheck to include them.
- **Min / Max** — filter sections by enrollment count. Min defaults to 1, which excludes zero-enrollment sections (typically scheduling placeholders). Set Min to 0 to include them.

Click **Refresh Data** after adjusting filters.

---

## DESR

Section-level enrollment data drawn from the Department Enrollment Status Report (MyReports). Each row represents one course section or an aggregation of sections depending on your Group by selection.

### Enrollment counts: section vs. combined

MyReports records enrollment at the individual section level. A crosslisted course with 8 students in the HIST section and 5 students in the ANTH section shows 8 and 5 in separate rows — not 13. CEDAR uses `total_enrl`, defined as `max(ENROLLED, XL_TOTAL_ENROLLMENT)` per section. For non-crosslisted sections this equals the section's own enrollment count; for crosslisted sections it equals the combined enrollment across all partner sections (the registrar's XL_TOTAL_ENROLLMENT figure).

When you use Group by, enrollment values are summed from `total_enrl` across all matching sections. Crosslisted courses grouped by `subject_course` show combined enrollment once (via the home section), not double-counted.

### Crosslist views

The DESR tab has five sub-views for handling crosslisted sections:

| Sub-view | What it shows |
|---|---|
| **Home** | Your department's home/primary sections, plus non-crosslisted courses. Crosslisted sections show their partner course(s) in the Partners column. |
| **Split-level** | Sections crosslisted across the undergraduate/graduate divide (upper-division paired with a graduate section of the same course). |
| **Crosslisted** | Your department's sections that also appear under another department's course number. |
| **Away** | Sections owned by another department but crosslisted under your department's number. |
| **All** | All sections including every crosslist partner — useful for seeing the full picture but will double-count enrollment. |

The Home view is the right starting point for most department-level analysis. It shows each crosslisted course once, under the administrative home department, preventing double-counting.

### How home sections are identified

When a course is crosslisted, only the **home (primary) section** appears in most views — the section administratively responsible for the course.

Home section is identified using the **SHORT_TEXT field** from MyReports, which contains a note like `"HIST home 202610"` identifying which department owns the crosslist. This is the registrar-authoritative signal.

When SHORT_TEXT is absent (roughly 85% of crosslist groups, particularly same-department split-level courses), the section with the **highest section-level enrollment** is treated as home. Ties are broken alphabetically by subject code.

{: .note }
When a department with lower enrollment appears as home, it is because SHORT_TEXT explicitly identified it — not an error in the data.

---

## Classlist

Student-level enrollment records for the filtered sections. Each row represents one student's registration in one section, including registration status (registered, dropped, withdrawn) and final grades for completed terms.

**DESR vs. Classlist:** DESR is section-level — one row per section, good for enrollment counts, crosslist views, and scheduling analysis. Classlist is student-level — one row per student enrollment, good for understanding who is in courses, tracking individual outcomes, or analyzing drop patterns at the student level. Classlist does not include sections with zero enrollment.

---

## Low Enrollment

Sections below configurable enrollment thresholds, organized by course level. The tab has four level sub-tabs (Lower, Upper, Split, Graduate) plus a data source footer.

### How sections are included

In **alerts mode** (current or past terms): a section appears when `total_enrl < threshold` for its level. Only home sections are shown — crosslisted courses appear once with their combined enrollment.

By default, alerts hide active zero-enrollment rows because these are usually schedule artifacts rather than viable low-enrollment sections. Set **Min enrolled** to `0` when you intentionally want to inspect them.

In **concerns mode** (future terms): instead of flagging current enrollment, CEDAR identifies courses on the upcoming schedule whose historical enrollment pattern suggests they may fall short. A course appears when its historical average is below `threshold + 5` (the +5 buffer catches courses near the boundary), or when it has no prior history.

### Thresholds

Each level has its own configurable threshold. Defaults (12 / 12 / 10 / 5 for lower / upper / split / graduate) reflect typical minimum viability targets, not institutional policy — adjust using the fields above the tabs.

### Excluded courses

Independent studies, thesis credits, dissertation credits, honors credits, and similar special-enrollment courses are excluded by default. These courses are expected to have very low or individually-arranged enrollment and would otherwise dominate the results. The excluded list is in `R/lists/excluded_courses.R` (approximately 200 course codes).

### Course levels

| Level | Course numbers |
|---|---|
| **Lower division** | Below 300 (and 1000+) |
| **Upper division** | 300–499 |
| **Graduate** | 500–699 |
| **Split-level** | A crosslisted group spanning the undergraduate/graduate boundary (at least one section ≤499 and at least one ≥500). Sections retain their original level but are flagged as split-level and appear in the Split sub-tab with a separate threshold. |

Lab sections (course numbers ending in L, e.g., EDUC 331L) are classified by their numeric base (331 → upper division).

### Section counts and course totals

The **Sects** column shows the number of active home sections of a course in the selected term and campus. **Course Total** is the sum of `total_enrl` across those sections. Both are computed from sections where `status = 'A'` and `crosslist_primary = TRUE`, grouped by term, course, and campus.

### Historical averages (concerns mode)

1. CEDAR identifies all prior terms of the same type (e.g., all past falls for a Fall 2026 schedule).
2. For each course on the future schedule, it sums `total_enrl` across home sections in each prior term, then averages the **last 4 available terms**.
3. Courses are matched by `subject_course` and `campus` — history for HIST 1105 at ABQ is computed separately from HIST 1105 at Valencia.
4. Only active terms (at least one active section) contribute to the average. Cancelled terms appear in the history column as "C" but do not affect the average.

History columns show counts first, followed by the matching terms in parentheses: `12, C, 10 (Fa22, Sp23, Fa23)`.

**Excluded from history:** Shell/placeholder sections (active status with zero enrollment and no instructor assigned) are excluded. If a course was renumbered or moved between departments, prior history under the old number will not be linked.

### Trend detection (concerns mode)

A linear regression slope is computed across enrollment values from active historical terms. A slope greater than +1 student/term is labeled **↑ up**; less than −1 is **↓ down**; between −1 and +1 is **↔ stable**. If fewer than 2 active terms are available, trend shows **—** (insufficient data).

### Color coding (concerns mode)

| Color | Meaning |
|---|---|
| **Red** | Historical average below 50% of threshold — consistently underperformed |
| **Yellow** | Historical average 50–75% of threshold — borderline |
| **Blue** | Historical average 75–100% of threshold — watch-list |
| **Green** | Historical average meets or exceeds threshold (buffer zone, up to 5 students above) |
| **Gray** | No prior history — new course or first offering of this term type |

### Limitations

- The analysis focuses on total enrollment per course, not individual section enrollment.
- New courses with no prior history of the same term type always appear regardless of threshold.
- The analysis does not account for changes in number of sections, delivery method shifts, or curricular changes.

---

## Trend Signals

Growing and declining course identification using linear regression across the last 6 offerings of each course. A course is flagged as trending up or down when its regression slope exceeds ±1 student per term. The 6-offering window mixes term types (fall, spring, summer) unless you filter to a single term type first — filtering before running Trend Signals gives cleaner comparisons.

Campus filters are retained. When multiple campuses are selected, the plots draw separate course-campus series instead of merging campuses into one line.

Useful for distinguishing genuine directional shifts from year-to-year noise, and for surfacing courses whose trajectory may not be obvious from a single-term view.

---

## Common questions

**Why don't the numbers match what I expected?**

- **Term filters** — make sure you've selected the terms you want
- **Campus filters** — the default includes ABQ and EA; adjust if needed
- **Crosslisted courses** — enrollment may differ depending on the sub-view; Home prevents double-counting, All includes every partner row
- **Cancelled sections** — excluded by default; set status filter to include them
- **Exclude List** — special-enrollment courses are removed when the checkbox is on

**What's the difference between enrollment and headcount?**

Enrollment counts registrations — a student in 3 courses = 3 enrollments. Headcount counts unique students — a student in 3 courses = 1 head. The Enrollment tab works with enrollment counts. For headcount of declared majors, see Headcount under Explore.

**Why doesn't my department's enrollment match what IR reports?**

CEDAR uses `total_enrl = max(ENROLLED, XL_TOTAL_ENROLLMENT)` and counts home sections only for crosslisted courses. IR may use different crosslist handling, a different term cutoff, or include cancelled sections. The methodology above describes exactly what CEDAR counts.

**How current is the data?**

CEDAR data is typically updated nightly during the academic year. The "as of" date in the data tables tells you when the underlying data was last extracted.

---

## Data sources

Source: MyReports DESR data. Transformation pipeline: `R/data-parsers/parse-DESR.R` → `R/data-parsers/transform-to-cedar.R`. Home section detection: `transform-to-cedar.R`. Excluded courses: `R/lists/excluded_courses.R`. Low enrollment functions: `R/cones/enrl.R`.

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term snapshot with historical comparisons, auto-loaded by department
- [Headcount](../users/) — unique students declared in a program, per term (under Explore)
- [Course Dynamics](course-reports) — one-course view of enrollment history, flows, and outcomes
