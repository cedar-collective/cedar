---
title: Enrollment Tab
parent: User Guide
nav_order: 3
---

# Enrollment Tab
{: .fs-9 }

**Seats and enrollment for the sections you choose, from the first day of classes to the end of the term**
{: .fs-6 .fw-300 }

---

The Enrollment tab is the primary workspace for exploring enrollment across courses, departments, terms, and instructors. Set your filters at the top and click **Gather Enrollments**. The **Courses** table shows each row's seats and its students on the first day, at census and at the end, with the schedule's own count beside them. The Low Enrollment and Trend Explorer tabs apply their own grouping rules.

---

## Filters

Campus, college, department, term, course, instructor, level, part of term, and the exclude list choose the sections. Every count in the Courses table follows them.

- **Campus / College / Department / Term / Course** — standard drill-down filters. Term defaults to the current term; use it to select another specific term or a term type (e.g., "Fall" to compare all fall semesters across years).
- **Group by** — the table's row grain. The default `term + subject_course` view gives course-campus-term rows; clear it for one row per section. Whenever `subject_course` is grouped, CEDAR keeps `campus` in the grouping automatically so ABQ, EA, and branch-campus histories do not merge.
- **Instructor** — filter to a specific instructor; type to search.
- **Exclude List** — when checked, removes independent studies, thesis credits, dissertation credits, honors credits, and similar special-enrollment courses. The list is the institution's `institution/<id>/excluded_courses.csv` (about 200 course codes at UNM). Uncheck to include them.
- **Census Min / Census Max** — filter rows by their census after grouping. Min defaults to 1. A row with no registrations has no census, so the filter keeps it, marks it *no registrations*, and the bar above the table counts it. These controls do not restrict Low Enrollment or Trend Explorer.

Click **Gather Enrollments** after adjusting filters.

---

## Courses

{% include definition-summary.html id="first-day-enrollment" %}

{% include definition-summary.html id="census-enrollment" %}

{% include definition-summary.html id="seat-fill" %}

The selected crosslist view chooses section rows first. CEDAR then groups them by **Group by**, and finally applies **Census Min / Census Max**.

### The columns

| Column | What it counts |
|---|---|
| **Seats** | DESR enrollment plus available seats for the row's sections |
| **First Day** | Students enrolled on each section's first class day, reconstructed from status dates. A row has one only when every section's is known; a term whose class lists carry no status dates, or a session that had not begun when the class list was pulled, shows a dash. |
| **First-Day Fill** | First Day over Seats, marked *near full* at 90% and *full* at 98%. Blank where seats are unknown, the fill is over 125% (unreliable capacity), or the row holds a crosslisted section, since crosslisted listings share their seats. |
| **Census** | Students still registered plus late drops. For a term in progress it is the count so far; the bar above the table names any term in progress. |
| **Final** | Students still registered when the class list was pulled: final for a finished term, current for one in progress. |
| **Early Drops / Late Drops** | Drops before and after the early-drop deadline. Early drops are never DFW. |

A row grouped by course shows its **Title**: its sections' most common title, with "(+N more)" when they had several (a topics course, or a course retitled across the terms a row spans). A grouped row also shows **Sections**, noting how many are on the class list when not all are, **XL Sections**, and **Avg Census per Section**.

The download adds three columns the table leaves out: **With Registrations** (sections with at least one class-list row), **DESR Enrl** (the schedule's own count when the DESR file was pulled: near peak for the current term, after drops for past terms; for a settled term it matches Final for nearly every course, and it is not compared with census) and **XL DESR Enrl** (a crosslist group's combined DESR enrollment, counted once). The student counts are summed over the row's sections. Each student is listed under one section of a course, so the sum counts each student once per course, and a sum across courses counts enrollments, not unique students.

Sections with neither seats nor students are schedule placeholders and are left out; the bar says how many. Waitlist demand is on the [Waitlists report](waitlists), which removes students already registered in the same course group.

### Crosslist views

The Courses table has five sub-views for handling crosslisted sections:

| Sub-view | What it shows |
|---|---|
| **Home** | CEDAR-classified home rows for external crosslists, plus non-crosslisted courses. Same-subject internal crosslists retain their separate course rows. |
| **Split-level** | Sections crosslisted across the undergraduate/graduate divide (upper-division paired with a graduate section of the same course). |
| **Crosslisted** | External crosslist groups on the row CEDAR classifies as home. |
| **Away** | External crosslist partner rows whose corresponding home row belongs to another department. |
| **All** | All sections including every crosslist partner — useful for seeing the full picture but will double-count enrollment. |

The Home view is the right starting point for most department-level inspection because it removes external partner rows. Internal same-subject pairs remain visible because both course numbers belong to the same subject area; do not add those paired course rows when the question requires one count per crosslist group.

Each sub-view has its own **Download CSV** link directly below the view description, with the same rows and columns as the table.

### How home sections are identified

For external crosslists, CEDAR classifies one row as **home** and the others as partners. This is a data-processing classification used to choose a display row; it should not be read as a general claim about budget or curricular ownership.

When the **SHORT_TEXT** field contains a note such as `"HIST home 202610"` and that subject appears in the group, CEDAR uses it as the strongest available signal.

When that signal is absent or cannot be matched, CEDAR uses the section with the **highest section-level enrollment**; ties are ordered by subject code. Same-subject crosslists are marked internal, and the Home view keeps their course rows rather than treating one subject as an external partner.

{: .note }
A lower-enrollment row can be classified as home when the SHORT_TEXT signal identifies its subject. The classification and fallback live in `transform-to-cedar.R`.

**Why census and DESR differ:** the class list and the DESR file are pulled on different dates, and neither is a certified census freeze. See [Why Numbers Differ Across Tabs](why-numbers-differ).

---

## Low Enrollment

Low Enrollment is its own page, **Courses > Low Enrollment**, with its own filters and thresholds. [Guide →](low-enrollment)

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

CEDAR reconstructs first-day, census and final counts from class-list statuses, and shows the retained DESR snapshot beside them, under the grouping shown on the page. IR may use a certified census file, another extract date, or different crosslist and cancellation rules. The definitions and local scope notes above describe what the current CEDAR view counts.

**How current is the data?**

Refresh cadence depends on the institution's data pipeline. The "as of" date in
each table tells you when that source was extracted; DESR and Class List dates
can differ.

---

## Data sources

Sources: MyReports DESR and Class List data. Parsing: `R/data-parsers/parse-DESR.R` and `R/data-parsers/parse-data.R`. Transformation: `R/data-parsers/transform-to-cedar.R`. Home-row classification lives in the transform. Excluded courses: `institution/<id>/excluded_courses.csv`. Low enrollment functions: `R/branches/enrl.R`.

---

## Related analyses

- [Dept Dashboard](dept-dashboard) — current-term snapshot with historical comparisons, auto-loaded by department
- [Headcount](headcount) — unique students declared in a program, per term (under Explore)
- [Course Dynamics](course-reports) — one-course view of enrollment history, flows, and outcomes
