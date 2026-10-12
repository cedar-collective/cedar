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
- Are any program, subject, or department mappings waiting for a decision?
- Which tabs and report types are people using?
- Which cached outputs can be cleared after a data or logic change?

This tab is mostly for CEDAR maintainers, IR staff, and power users who need to
understand the app's data state.

---

## Data Summary

Data Summary is embedded in the initial page as a plain table. Once the app
page has loaded, opening it needs no server response, log scan, or interactive
table initialization—even if another report is busy. A cold app still needs
its initial startup; this does not bypass data loading on the first request.

The version comes from the newest entry in `config/changelog.yml`. The data
status table reports row counts and term-level freshness for the major loaded
tables, such as sections, students, programs, degrees, and faculty.

Use this after a data refresh or deployment to confirm that the app is reading
the expected data snapshot.

Dates are source extract dates, not the time you opened the page. The separate
app-snapshot timestamp identifies when the running app loaded them. Missing
datasets remain visible as **Not loaded** and missing dates as **Not available**.
The morning refresh reloads this snapshot; the table does not poll files while
you browse. Join Integrity and usage analyses only start when opened.

---

## Mappings

Mappings shows how CEDAR decides which department, college, and program every
course and student belongs to, and what still needs a person's decision. Those
relationships are stated in plain files under `institution/unm/` in the CEDAR
repository (see [ADR-002](https://github.com/cedar-collective/cedar/blob/main/docs/developers/adr-002-explicit-mapping-files.md)), so
every mapping is a reviewable line, not something CEDAR infers.

At the top, a banner says whether the departments CEDAR is showing were built
from the mapping files now deployed (**current**) or from older ones (**STALE**:
the next data refresh or deploy rebuilds them).

**Mapping decisions** lists everything settled by editing a mapping file,
largest first, in three tabs:

- **Programs**: programs awaiting a decision, program codes in the data that no
  file covers, and programs whose mapped college differs from Banner's.
- **Course subjects**: course subjects awaiting a decision.
- **Colleges**: college names no file recognizes, and departments with no
  home college.

Each row opens with what it is, then what it needs:

| Column | What it means |
|---|---|
| **Banner code** | The code Banner uses for it — a program's major or minor code (for example `ART`, the Art minor), a course subject, or a college value |
| **Name** | The code's own name: a program's name in the mapping file, or for a code with no row, the name its records most often carry. A course subject has no name, so the Course subjects tab shows **Taught in college** instead |
| **Kind** | What the row is: a program (major, minor, both, or pre-major), a program code with no row, a college check, a college name, or a department's college |
| **Where** | The file and line, as `file.csv:line`, for someone editing a local copy |
| **Needs** | What to supply, as a link to that line (or to the file, for a new row) |
| **Reported today as** | What CEDAR shows now. Every department comes from the mapping files, so an undecided code reads *none*: its students count toward no department until the row is confirmed and the data is rebuilt. For a college check, the mapped college and Banner's |
| **Suggested department** | The department (CEDAR unit) the mapping assistant thinks should own it, with its name — for example `ARTS — Art Studio` |
| **Confidence** | How far to trust the suggestion. *Strong*: Banner's own department, matching names, or the program a pre-major leads to. *Plausible*: its students clearly take that department's courses. *Weak*: course-taking only, and not clear-cut, or the program sits in a catch-all Banner department. Hover for the full evidence |

To accept a suggestion, change the row's `status` to `confirmed`. To choose a
different unit, also change `unit_code`. Decisions are made in the files and
reviewed like any other change; the app never edits them.

**Other problems in the data** lists what no mapping can fix — for example,
Banner organization IDs that appear in the major-code column — so they can be
reported to whoever owns the source data.

Below those, subtabs show what *is* mapped today:

| Subtab | What it shows |
|---|---|
| **Program to Dept** | Every confirmed program: its code and name, the department (code and name) that owns it, and the college it applies in when it is not every college. A program no department owns says so. |
| **Subject to Dept** | Every confirmed course subject: the department (code and name) that owns it, and the college or course level it applies to when it is not all of them. |
| **Dept Names** | Every department: its code, name, home college, and kind (a department, a program, or a college-wide unit for courses no department owns). |

A long decisions list does not mean the app is broken. It means some codes
should be checked before someone treats a department or college total as
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

The preview shows the newest 500 matching events. Its summary includes all
matching events, not just those visible in the preview. Refresh rereads the
selected range, and the preview and summary share that read.

New usage logs rotate daily, including across midnight in long-running sessions.
Older monthly files remain readable; date filtering happens before JSON parsing.
At app startup, closed usage files older than the configured active window
(90 days by default) move to `logs/archive/` in the data directory instead of
being deleted. Older date selections include those archives automatically.
Archives remain part of the production data backup; timing logs are unchanged.

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
