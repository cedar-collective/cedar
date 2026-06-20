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

Use the filter stripe at the top of the tab, then click **Apply Population**.

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

Looks for courses in the selected population where DFW outcomes, withdrawals, or later departure patterns stand out. The table is population-filtered; the courses may include courses outside the focal department if students in the selected population commonly take them.

### Course Timing

Shows when students in the population take each course relative to their first selected-unit program record. This is useful for seeing de facto pathways, especially where students take important courses outside the department.

### Course Pairs

Shows common ordered course pairs: courses students often take before or after one another. These are observed course-taking sequences, not catalog requirements.

### Course to Major

Connects course-taking to later selected-unit entry. The **Course + Instructor Signals** table shows course, title, instructor, and later declaration patterns. Course titles are matched at the course-title and instructor level so topics courses with the same number but different titles are not collapsed together.

The **Courses Before Major Entry** heatmaps are limited to the selected population and show courses taken before students first appear in the selected unit. They are intended to make visible which courses are commonly in students' records before entry, not to imply that any course caused the later declaration.

### Major Changes

Shows movement into, within, and out of the selected unit. The page separates pre-major and full-major patterns where that distinction is visible in the program records.

The top movement cards focus on four timing questions:

- When do students first appear in the selected unit as pre-majors?
- When do students first appear as full majors without a prior selected-unit pre-major record?
- When do selected-unit pre-majors convert to full majors?
- When do selected-unit students leave for another program?

Each timing view separates native UNM and transfer-entry students where the data allow it. Credit figures in these cards come from class-list-derived UNM credit histories, so students whose first observed class-list term is already far into their UNM record are excluded from those timing cards and counted in the scope stripe.

The tables near the bottom provide reference detail:

- **Movement Detail** is student-level timing context for the displayed movement categories.
- **Change Events** is the underlying event table: each row is a term-to-term program change.
- **Common Pathways** aggregates from-major to to-major switches. Median completed and attempted UNM credits are derived from class-list credit histories through the term before the change posted.

### Methodology

Documents how population matching, pre-major/full-major handling, term timing, credit estimates, and suppression rules are applied. Check this tab when a number looks surprising; the goal is to keep the assumptions visible enough to question.

---

## Interpreting Major Changes

Program records are term snapshots. CEDAR compares a student's primary program from one term to the next. Moving from a pre-major to the full major in the same program is treated as staying in that program for switch counts; switching to a different pre-major or major is counted as movement.

Timing is based on observed terms:

- **Terms** count regular academic terms between two observed records. Summer is generally skipped unless a specific analysis says otherwise.
- **Native UNM** means the student's first observed class-list term is close enough to the selected-unit entry record that UNM credit timing can be estimated.
- **Transfer entry** means the student appears to enter UNM with transfer standing or with substantial prior credit context.
- **Completed UNM credits** are derived from class-list rows with credit-earning outcomes.
- **Attempted UNM credits** are derived from registered class-list rows. Withdrawals and drops are handled according to the grade/status rules documented in the methodology tab.

Because CEDAR does not always have a formal Banner matriculation term in the student-course data, students already present at the left edge of the available data can have uncertain starts. Those students remain visible in reference tables where appropriate, but they are excluded from timing cards that would otherwise imply a precision the data do not support.

---

## Related Analyses

- [Dept Dashboard](dept-dashboard) — current-term course activity for a department
- [Course Dynamics](course-reports) — course-level enrollment history, flows, outcomes, and retention
- [Dept Trends](department-reports) — multi-year program and instructional trends
