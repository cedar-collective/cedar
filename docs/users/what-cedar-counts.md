---
title: What CEDAR Counts
parent: User Guide
nav_order: 19
---

# What CEDAR Counts
{: .fs-9 }

CEDAR is built from snapshots of institutional source data. Most numbers are
counts of rows or unique people after CEDAR applies a clear scope: term, campus,
department, course, program, status, and sometimes grade outcome. The explanations below are read directly from the shared
[versioned definition records](definitions), also used by the app.

{: .note }
CEDAR is for exploration, planning, and methodological transparency. It is not a
census-freeze or official-reporting system unless your institution has built a
separate certified process around it.

## Enrollment Counts

{% include definition-summary.html id="desr-enrollment" %}
{% include definition-summary.html id="registered" %}
{% include definition-summary.html id="census-enrollment" %}

## Registration Status

Registered statuses are RE/RS/RR, waitlists are WL, early drops are DR/DD, and
late drops are DG/DW. The records above and below state how each measure uses
these categories. Early drops describe registration churn, not DFW outcomes.

## Grade Outcomes

{% include definition-summary.html id="dfw" %}

## Headcount

{% include definition-summary.html id="program-headcount" %}
{% include definition-summary.html id="dashboard-headcount" %}

## Credit Hours

{% include definition-summary.html id="credit-hours" %}

## Retention And Persistence

{% include definition-summary.html id="course-retention" %}

Pathways Roadblocks uses a different return rule and record grain; see its
[definition](definitions#roadblocks). Do not assume the two views have identical
cohorts or denominators.

## Waitlists

{% include definition-summary.html id="waitlist" %}

## Courses, Crosslists, And Topics

CEDAR tries to preserve meaningful course identity:

- Crosslisted sections may be compressed or split depending on the tab.
- Combined lecture/lab courses with a `C` suffix are counted as one course when
  the question is course offerings rather than CRN count.
- Topics courses can share a course number while having different titles; views
  that need course identity keep the title so distinct topics are not collapsed.

When a table shows repeated-looking rows, check whether the row is separated by
campus, course title, section, part of term, crosslist status, or instructor.

## Reading A Rate

For any percentage, ask three questions:

1. What is the numerator?
2. What is the denominator?
3. Which rows were excluded before the rate was computed?

CEDAR's in-app blue explain boxes answer those questions near complex tables.
This page gives the shared vocabulary; the local table note gives the exact
scope for that view.
