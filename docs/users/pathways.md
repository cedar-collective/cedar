---
title: Pathways
parent: User Guide
nav_order: 5
---

# Pathways
{: .fs-9 }

**Student-population views of course taking and major movement**
{: .fs-6 .fw-300 }

---

Pathways lets you define a student population, then look at how that group appears in courses, sequences, roadblocks, and major-change records. It is meant to make program-level patterns easier to inspect, not to turn those patterns into automatic judgments about courses, instructors, or students.

Most Pathways views are descriptive. They can show where a pattern is worth asking about, but they do not by themselves explain why the pattern exists.

---

## Build a population

Use the filter stripe at the top of the tab, then click **Define Population**.

{% include definition-summary.html id="pathways-population" %}

| Control | What it does |
|---|---|
| **Select population by** | Choose majors, a department, a preset major group, or demographic criteria. |
| **Majors / Department / Major Group / Demographics** | Defines the starting population. Major and department searches are based on program records. |
| **Population scope** | For major, department, and preset populations, choose declared majors only, declared + pre-major, or pre-major only. |
| **Level** | Limits the population to undergraduate, graduate, or all levels. |
| **Campus** | Limits the population by student campus. |

The scope stripe below the filters shows how many students matched, how many program records were used, what the focal programs resolved to, and the analysis-through term. For Major Changes, it also shows how many selected-unit students are excluded from timing cards because their first observed UNM course history begins too late to estimate credits reliably.

---

## Subtabs

### Population

Shows the population definition, entry-status composition, and college comparisons where available. Use this as a quick check that the population you built is the one you intended.

### Roadblocks

{% include definition-summary.html id="roadblocks" %}

The courses may lie outside the focal department if selected students take them.

### Course Timing

{% include definition-summary.html id="course-timing" %}
{% include definition-summary.html id="credit-position" %}

Each axis has a run-specific note beneath its chart. Credit positions entering
a term exclude that term's own work. The displayed credit axes use attempted
credits; they do not represent historical Banner earned-credit totals.

### Course Pairs

Shows common ordered course pairs: courses students often take before or after one another. These are observed course-taking sequences, not catalog requirements.

Course A records are counted only when CEDAR has the full follow-up window needed by the selected max term gap. This prevents newer terms from making follow-on rates look artificially low simply because the data ends.

### Course to Major

Connects course-taking to later selected-unit entry. The **Course + Instructor Signals** table shows course, title, instructor, and later declaration patterns. Course titles are matched at the course-title and instructor level so topics courses with the same number but different titles are not collapsed together.

The **Courses Before Major Entry** heatmaps are limited to the selected population and show courses taken before students first appear in the selected unit. They are intended to make visible which courses are commonly in students' records before entry, not to imply that any course caused the later declaration.

This subtab has two scopes. The Course + Instructor table uses the population only to resolve the focal department/subject prefixes, then scans all eligible students in those focal-subject courses. The heatmaps use only the selected population.

### Major Changes

Shows movement into, within, and out of the selected unit. The page separates pre-major and full-major patterns where that distinction is visible in the program records.

The top movement cards focus on four timing questions:

- When do students first appear in the selected unit as pre-majors?
- When do students first appear as full majors without a prior selected-unit pre-major record?
- When do selected-unit pre-majors convert to full majors?
- When do selected-unit students leave for another program?

Each timing view separates Always UNM and Transfer students where the data allow it. Transfer origin is assigned from the student's earliest available Academic Studies **Student Population** label; it is not inferred from credits. Credit figures in these cards come from class-list-derived UNM credit histories. A separate entry-card eligibility rule excludes students at the data-start boundary or whose first selected-unit record occurs after more than 30 class-list-derived attempted UNM credits. That 30-credit rule does not label a student as Transfer.

**Courses in the Term Before Students Left** lists what departing students were taking in the last term on the old major. A switch reaches Banner the term after the student actually moves, so this is the term whose coursework was in progress while they were deciding, not the term the change appeared.

Every course is shown twice: how often it turned up in those final terms, and how often it turns up in a normal term for this group. If the two numbers are close, the course is just part of what everyone here takes. A course only stands out when the first is well above the second.

> **Example.** A course taken by 15% of departing students in their final term, against 10% in a typical term, is 1.5× — common, but not concentrated. One at 4% against 0.5% is 8×: rarer overall, yet eight times more likely right before a switch. The biggest numbers are usually just the required courses; the interesting rows are often further down the list.

The two percentages are not out of the same thing, which matters if you are checking the arithmetic:

- **In their last term** is out of departing students — specifically the ones with coursework on record for that term, which the line above the table reports.
- **In a typical term** is out of *terms*, not students. It counts every enrolled term belonging to anyone in the population, those who left and those who stayed, minus the terms around a switch. A student enrolled eight terms contributes eight of them.

This section is descriptive and uncontrolled. A high ratio does not mean the course caused anyone to leave. Students already leaning toward another field enroll differently, so the decision can be producing the schedule rather than the reverse, and switches cluster early in a career without the comparison adjusting for that — which pushes lower-division courses above 1.0 for reasons unrelated to switching. Small departure counts move the ratio a long way on one or two students.

The tables near the bottom provide reference detail:

- **Movement Detail** is student-level timing context for the displayed movement categories.
- **Change Events** is the underlying event table: each row is a term-to-term program change.
- **Common Pathways** aggregates from-major to to-major switches. Median completed and attempted UNM credits are derived from class-list credit histories through the term before the change posted.

## Methodology

The docs site holds the full reference; there is no separate in-app Methodology
tab. The blue explanation boxes and the records embedded in this guide use the
same versioned source. Read [Definition Records](definitions) for populations,
units, numerators, denominators, time windows, exclusions, and known issues.
Run-specific coverage and scope notes remain in the app beside the results.

## Technical traceability

These are the main code paths:

| Pathways concept | Primary code |
|---|---|
| Population definition, outcomes, entry status, and `relevant_until` | `R/branches/population.R`: `build_population()` |
| Shared population-window filters | `R/branches/pathways.R`: `apply_pathways_population_window()`, `filter_pathways_analysis_population()` |
| Roadblocks | `R/cones/stopout.R`: `get_stopout()`, `classify_outcomes()`, `compute_stopout_for_group()` |
| Course Timing and Course Pairs | `R/cones/pathway.R`: `get_course_timing()`, `get_course_pairs()` |
| Course to Major table | `R/cones/gen-ed-conversion.R`: `get_course_major_associations()` |
| Courses Before Major Entry heatmaps | `R/cones/major-changes.R`: `get_entry_heatmap()` |
| Major Changes | `R/cones/major-changes.R`: `detect_major_changes()` plus display assembly in `R/modules/pathways.R` |
| Courses in the Term Before Students Left | `R/cones/major-changes.R`: `get_pre_change_courses()` |
| Credit positions used in timing/change cards | `R/branches/credit-timeline.R`: `build_credit_timeline()`; `cedar_student_term_credits` from class-list history |

Two rules explain many surprising Pathways numbers:

- **Population membership is not lifetime enrollment.** For non-ongoing students, `relevant_until` prevents courses after a student leaves the selected unit from being attributed back to that unit.
- **Credit positions avoid frozen Banner cumulative fields.** Pathways uses class-list-derived credit histories where possible and reports/excludes students whose earlier UNM record is not visible enough to support a timing claim.

---

## Interpreting Major Changes

Program records are term snapshots. CEDAR compares a student's primary program from one term to the next. Moving from a pre-major to the full major in the same program is treated as staying in that program for switch counts; switching to a different pre-major or major is counted as movement.

Timing is based on observed terms:

- **Terms** count regular academic terms between two observed records. Summer is generally skipped unless a specific analysis says otherwise.
- **Always UNM** means the earliest available Academic Studies `student_population` label used by this analysis does not contain “transfer.”
- **Transfer** means that earliest available `student_population` label contains “transfer.” No credit threshold is used for this origin label.
- **Completed UNM credits** are derived from class-list rows with credit-earning outcomes.
- **Attempted UNM credits** are derived from registered class-list rows and accumulated term by term in `cedar_student_term_credits`. They are not the pull-stamped Academic Studies `Institution Credits Attempted` value.

Because CEDAR does not always have a formal Banner matriculation term in the student-course data, students already present at the left edge of the available data can have uncertain starts. Those students remain visible in reference tables where appropriate, but they are excluded from timing cards that would otherwise imply a precision the data do not support.

---

## Related Analyses

- [Dept Dashboard](dept-dashboard) — current-term course activity for a department
- [Course Dynamics](course-reports) — course-level enrollment history, flows, outcomes, and retention
- [Dept Trends](department-reports) — multi-year program and instructional trends
