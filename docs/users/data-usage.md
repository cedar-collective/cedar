---
title: Data & Usage
parent: User Guide
nav_order: 18
---

# Data & Usage
{: .fs-9 }

**Data freshness, mapping transparency, usage patterns, and cache tools**
{: .fs-6 .fw-300 }

---

Data & Usage is an administrative transparency area. It lives in the top
navigation as **Data & Usage**.

Use it to answer:

- What version of CEDAR is running?
- Which loaded data tables are fresh for which terms?
- Are any program, subject, or department mappings unresolved?
- Which tabs and report types are people using?
- Which cached outputs can be cleared after a data or logic change?

This tab is mostly for CEDAR maintainers, IR staff, and power users who need to
understand the app's data state.

---

## Data Summary

Data Summary loads immediately. It shows the current CEDAR version and a table
of loaded datasets.

The version comes from the newest entry in `config/changelog.yml`. The data
status table reports row counts and term-level freshness for the major loaded
tables, such as sections, students, programs, degrees, and faculty.

Use this after a data refresh or deployment to confirm that the app is reading
the expected data snapshot.

---

## Mappings

Mappings explains the department, subject, and program lookup tables CEDAR built
at startup.

The most important panel is **Mapping Issues**. Rows listed there were unusual
enough to need review. They are excluded from runtime lookup vectors until they
are mapped or explicitly reviewed, so a questionable code does not silently leak
into calculations.

Subtabs:

| Subtab | What it shows |
|---|---|
| **Program to Dept** | Major/program code to department-code lookup used for home-major classification and transform fallbacks. |
| **Subject to Dept** | Course subject prefixes mapped to CEDAR department codes. |
| **Dept Names** | Department-code display names. |
| **Reviewed Exceptions** | Program codes intentionally allowed to remain unmapped at startup. |

Mapping issues do not necessarily mean the app is broken. They mean the mapping
layer found codes that should be checked before someone treats an aggregation as
complete.

---

## Usage Overview

Usage Overview summarizes recent CEDAR activity for a selected date range.

The top dashboard shows:

- active sessions;
- reports run;
- tab views;
- logged errors;
- total events;
- downloads;
- top department;
- top course.

CEDAR logs browser sessions, not authenticated user identities. The active
session count should not be interpreted as unique people.

The tables below the dashboard break usage down by tab, report type,
department, course, campus scope, and day. Use this to see which parts of CEDAR
are getting attention and where training or documentation might help.

---

## Feature Details

Feature Details exposes the lower-level usage event log for a selected date
range. It is useful when the overview says something happened and you need the
specific event records behind it.

Use this for troubleshooting, not as a polished usage dashboard.

---

## Cache

Cache Management clears cached outputs used by expensive tabs such as Course
Dynamics, Dept Trends, Pathways, Open Seats, and Regstats.

Clear a cache when:

- data has been corrected and the cache key would not naturally change;
- a logic fix changes the meaning or shape of cached output;
- a production smoke test suggests the app is serving stale output.

Normal data refreshes should invalidate most caches through data hashes or
date-based keys. Manual cache clearing is a maintenance tool, not something
ordinary users should need.

For deploy steps, see the [release runbook](../developers/release-runbook).

---

## Related Analyses

- [Why Numbers Differ Across Tabs](why-numbers-differ) - common reasons CEDAR
  counts differ across views
- [What CEDAR Counts](what-cedar-counts) - shared counting definitions
- [Understanding Your Data](understanding-data) - known data caveats and
  reliability rules
