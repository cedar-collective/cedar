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

The Enrollment tab is the primary workspace for exploring enrollment data across courses, departments, terms, and instructors. Set your filters at the top and click **Gather Enrollments**. The results share a course scope where their sources allow, but they are not four views of one table: DESR uses section snapshots, Classlist uses student registration records, and the Low Enrollment and Trend Explorer tabs apply their own grouping rules.

---

## Filters

Campus, college, department, term, course, instructor, level, part of term, and the exclude list establish the base section scope. Classlist is matched to those active DESR sections by CRN and term before its student counts are calculated.

- **Campus / College / Department / Term / Course** — standard drill-down filters. Term defaults to the current term; use it to select another specific term or a term type (e.g., "Fall" to compare all fall semesters across years).
- **Group by** — controls the DESR table's row grain. The default `term + subject_course` view produces course-campus-term rows. Whenever `subject_course` is grouped, CEDAR keeps `campus` in the grouping automatically so ABQ, EA, and branch-campus histories do not merge. It does not change the fixed Classlist grain.
- **Instructor** — filter to a specific instructor; type to search.
- **Exclude List** — when checked, removes independent studies, thesis credits, dissertation credits, honors credits, and similar special-enrollment courses. The list is in `R/lists/excluded_courses.R` and contains approximately 200 course codes. Uncheck to include them.
- **DESR Min / DESR Max** — filter the displayed DESR `DESR Enrl` value after the selected crosslist view is grouped. Min defaults to 1. These controls do not restrict Classlist, Low Enrollment, or Trend Explorer.

Click **Gather Enrollments** after adjusting filters.

---

## DESR

{% include definition-summary.html id="desr-enrollment" %}

The selected crosslist view is applied to DESR section rows first. CEDAR then aggregates those rows according to **Group by**, and finally applies **DESR Min / DESR Max**.

### Enrollment counts: section vs. combined

MyReports records enrollment at the individual section level. In an ungrouped table, **Section Enrl** is the section row's own DESR enrollment. **XL Total Enrl** is `max(ENROLLED, XL_TOTAL_ENROLLMENT)`: it normally equals Section Enrl for a non-crosslisted row and carries the crosslist group's combined value for a crosslisted row.

In a grouped table:

- **DESR Enrl** sums the contributing rows' DESR enrollment.
- **XL-aware Enrl** adds each non-crosslisted row's own enrollment and counts each crosslist group's combined total once within that displayed row.
- **Sections**, **XL Sections**, and **Non-XL Sections** count the DESR rows contributing to that displayed group.

XL-aware Enrl prevents duplicate partner rows within one aggregation cell. It does not make arbitrary rows additive across different course numbers: an internal split-level pair can remain as two course rows, and the **All** view deliberately retains partner representations.

### Crosslist views

The DESR tab has five sub-views for handling crosslisted sections:

| Sub-view | What it shows |
|---|---|
| **Home** | CEDAR-classified home rows for external crosslists, plus non-crosslisted courses. Same-subject internal crosslists retain their separate course rows. |
| **Split-level** | Sections crosslisted across the undergraduate/graduate divide (upper-division paired with a graduate section of the same course). |
| **Crosslisted** | External crosslist groups on the row CEDAR classifies as home. |
| **Away** | External crosslist partner rows whose corresponding home row belongs to another department. |
| **All** | All sections including every crosslist partner — useful for seeing the full picture but will double-count enrollment. |

The Home view is the right starting point for most department-level inspection because it removes external partner rows. Internal same-subject pairs remain visible because both course numbers belong to the same subject area; do not add those paired course rows when the question requires one count per crosslist group.

Each DESR sub-view has its own **Download CSV** link directly below the view description. The download contains the same crosslist slice shown in the table. The Classlist tab has a separate download for its student-count summary.

### How home sections are identified

For external crosslists, CEDAR classifies one row as **home** and the others as partners. This is a data-processing classification used to choose a display row; it should not be read as a general claim about budget or curricular ownership.

When the **SHORT_TEXT** field contains a note such as `"HIST home 202610"` and that subject appears in the group, CEDAR uses it as the strongest available signal.

When that signal is absent or cannot be matched, CEDAR uses the section with the **highest section-level enrollment**; ties are ordered by subject code. Same-subject crosslists are marked internal, and the Home view keeps their course rows rather than treating one subject as an external partner.

{: .note }
A lower-enrollment row can be classified as home when the SHORT_TEXT signal identifies its subject. The classification and fallback live in `transform-to-cedar.R`.

---

## Classlist

{% include definition-summary.html id="registered" %}

{% include definition-summary.html id="census-enrollment" %}

Each row is one course, delivery campus, college, and term. The table starts from student records whose CRN and term match the base active-section scope, then counts each student once within that row.

**Group by**, **DESR Min / DESR Max**, and the selected DESR crosslist sub-view do not change Classlist. Those controls describe how DESR rows are displayed, not how student registration records are grouped.

The lifecycle columns are reconstructed from registration statuses in the retained extract:

| Column | Calculation | Interpretation |
|---|---|---|
| **Ever Registered Proxy** | Registered at extract + all early and late drops | Everyone observed with a registration or drop status. It can include pre-term registration churn and is not a frozen first-day roster. |
| **Census Estimate** | Registered at extract + late drops | An estimate of students who stayed beyond the early-drop period. CEDAR has no census-frozen roster or registration timestamps. |
| **Registered at Extract** | Distinct RE/RS/RR students | The retained class-list snapshot. It is final only when the term and extract are complete. |

Early Drops, Late Drops, and Waitlist Status remain beside the lifecycle columns so the reconstruction is auditable. Waitlist Status is a raw status bucket in this course-level summary; use the [Waitlists report](waitlists) for the cross-section true-demand definition that removes students already registered in the same course group. The download uses the same columns and definitions as the table.

**DESR vs. Classlist:** DESR starts at section snapshots and supports schedule and crosslist inspection. Classlist aggregates distinct student records to course-campus-college-term lifecycle counts. Their extract dates can differ, and neither source is a certified census freeze. See [Why Numbers Differ Across Tabs](why-numbers-differ).

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

## Trend Explorer

Growing and declining course identification using linear regression across the last 6 offerings of each course. A course is flagged as trending up or down when its regression slope exceeds ±1 student per term. The 6-offering window mixes term types (fall, spring, summer) unless you filter to a single term type first — filtering before opening Trend Explorer gives cleaner comparisons.

The campus-and-level overview keeps one point per term, campus, and course level. Campus controls line color, while each level remains a separate trace. The growing and declining course plots also retain campus, drawing separate course-campus series instead of merging campuses into one line.

Useful for distinguishing genuine directional shifts from year-to-year noise, and for surfacing courses whose trajectory may not be obvious from a single-term view.

---

## Common questions

**Why don't the numbers match what I expected?**

- **Term filters** — make sure you've selected the terms you want
- **Campus filters** — the default includes ABQ and EA; adjust if needed
- **Crosslisted courses** — enrollment may differ by sub-view; Home removes external partner rows, while internal pairs remain visible and All includes every partner row
- **Cancelled sections** — the page queries active DESR sections
- **Exclude List** — special-enrollment courses are removed when the checkbox is on

**What's the difference between enrollment and headcount?**

Enrollment counts registrations — a student in 3 courses = 3 enrollments. Headcount counts unique students — a student in 3 courses = 1 head. The Enrollment tab works with enrollment counts. For headcount of declared majors, see Headcount under Explore.

**Why doesn't my department's enrollment match what IR reports?**

CEDAR reports retained DESR snapshots and class-list status reconstructions under the grouping shown on the page. IR may use a certified census file, another extract date, or different crosslist and cancellation rules. The definitions and local scope notes above describe what the current CEDAR view counts.

**How current is the data?**

Refresh cadence depends on the institution's data pipeline. The "as of" date in
each table tells you when that source was extracted; DESR and Class List dates
can differ.

---

## Data sources

Sources: MyReports DESR and Class List data. Parsing: `R/data-parsers/parse-DESR.R` and `R/data-parsers/parse-data.R`. Transformation: `R/data-parsers/transform-to-cedar.R`. Home-row classification lives in the transform. Excluded courses: `R/lists/excluded_courses.R`. Low enrollment functions: `R/cones/enrl.R`.

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term snapshot with historical comparisons, auto-loaded by department
- [Headcount](headcount) — unique students declared in a program, per term (under Explore)
- [Course Dynamics](course-reports) — one-course view of enrollment history, flows, and outcomes
