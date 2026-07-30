---
title: Data Integration Guide
nav_order: 4
parent: Developer Guide
---

# Data Integration Guide

CEDAR is portable at the level of its normalized data model, not at the level of
raw institutional exports.

That distinction is important. The CEDAR dashboard can run on a small server, in
a container, or inside another Shiny hosting environment, but hosting the app is
usually not the hard part. The real institutional implementation work is mapping
local student-information data into the `cedar_*` tables in a way that preserves
local meaning and makes analytical choices explicit.

## The Integration Contract

CEDAR analyses expect a small set of normalized tables:

| Table | Represents |
|:------|:-----------|
| `cedar_sections` | Course offerings and section-level enrollment context |
| `cedar_students` | Student course registrations, grades, and course-level attributes |
| `cedar_student_term_credits` | Observed term-level and cumulative UNM-style credit timeline |
| `cedar_programs` | Student majors, minors, concentrations, and program attributes by term |
| `cedar_degrees` | Degrees awarded or pending |
| `cedar_faculty` | Instructor identity and appointment context |
| `cedar_applicants` | Optional admissions/applicant context for analyses that need it |

The full schema lives in [Data Model](data-model.html). This guide explains the
decisions needed to produce those tables.

## What CEDAR Does Not Assume

CEDAR does not assume that another institution's raw data looks like UNM's
MyReports exports. It also does not assume that Banner, PeopleSoft, Colleague,
Workday, Canvas, or local reporting extracts use the same names, codes, or
timing rules.

Before CEDAR analytics are meaningful, each institution must decide how local
records map to the CEDAR contract. Those decisions are part of the analytical
method, not clerical setup.

## Core Mapping Decisions

### Terms

CEDAR term codes use `YYYYSS`:

| Suffix | Meaning |
|:-------|:--------|
| `10` | Spring |
| `60` | Summer |
| `80` | Fall |

Chronological sorting assumes these integer codes. If a local institution uses a
different term calendar or subterm structure, the integration layer should map it
to this convention or document a deliberate extension.

### Course Identity

Course identity is more than subject plus number. CEDAR uses fields such as:

- `subject_course`
- `course_title`
- `term`
- `campus`
- `college`
- `department`
- `crn`

This matters because topics courses can share the same subject and number while
representing different course titles, and crosslisted sections can represent one
instructional event through multiple administrative rows. The integration layer
should preserve enough identity to distinguish real repeated offerings from
duplicate-looking rows.

### Registration Status

CEDAR defines registration status categories in `R/lists/status_codes.R`.

| Category | Codes | Meaning |
|:---------|:------|:--------|
| Registered | `RE`, `RS`, `RR` | Still enrolled/registered |
| Waitlist | `WL` | Waitlisted |
| Early drop | `DR` | Dropped before the relevant deadline |
| Late drop | `DG`, `DW` | Withdrawal/drop with grade consequence |
| Other administrative drop | `DD` | Treated with early-drop style behavior unless local policy says otherwise |

An institution with different local codes should not silently shoehorn them into
CEDAR. Add or revise the status-code mapping, then document the policy. CEDAR
also surfaces unexpected registration codes in several outcome views because an
unknown code may carry a grade signal.

### Grades And DFW

CEDAR's current DFW policy is:

**DFW = D/F/W-style final grades plus late drops. Early drops are shown
separately and are not DFW.**

This policy lives in shared code and constants, not per-tab ad hoc logic. Local
integration should confirm:

- which local grade strings count as passing,
- which grade strings count as D/F/W,
- whether withdrawal grades appear as grades, registration statuses, or both,
- how incompletes, audits, credit/no-credit, and retake grades should be handled.

See [What CEDAR Counts](../users/what-cedar-counts.html) for user-facing
definitions.

### Programs, Departments, And Ownership

CEDAR distinguishes subject prefixes, academic departments, programs, colleges,
and student majors. Those are related but not interchangeable.

Examples:

- a department code may not equal the subject prefix used in course numbers,
- a program may be academically owned by a department different from its raw
  Banner or catalog code,
- pre-major programs may need explicit handling,
- concentrations and second majors may need separate rows.

Local mapping work should produce validated program and subject lookup tables.
Unmapped codes should fail loudly or appear in a review list rather than falling
silently into a generic bucket.

### Student Identity And Privacy

CEDAR tables should not contain plaintext student identifiers. The transform
process should hash or otherwise pseudonymize student IDs before writing
`cedar_students`, `cedar_programs`, `cedar_degrees`, or related tables.

Institutions remain responsible for:

- protecting the source data and transformed data directory,
- managing salts/secrets outside version control,
- defining retention rules for caches and logs,
- deciding which audiences may see which tabs,
- and applying small-cell suppression or other disclosure controls required by
  local policy.

## Integration Workflow

A typical institutional workflow looks like this:

1. Extract local source data from institutional systems.
2. Preserve a raw or aggregate copy for local audit and troubleshooting.
3. Transform source data into the normalized `cedar_*` tables.
4. Validate required columns, row counts, terms, code values, and joins.
5. Run the test suite and targeted smoke checks.
6. Review user-facing definitions against local policy.
7. Host the Shiny interface in the institution's chosen environment, if the
   dashboard will be shared beyond analysts.

For UNM's MyReports-based pipeline, see
[Data Transformation](data-transformation-myreports.html). Other institutions
should treat that as a worked example, not as the only supported ingestion path.

## Hosting Is Separate From Integration

CEDAR is a codebase and shared analytics platform. The included Shiny app is a
reference interface over that codebase. Making it available to other users
requires some hosting choice, but CEDAR does not prescribe a single institutional
deployment architecture.

At minimum, an institution should decide:

- where protected transformed data lives,
- how code updates are pulled and tested,
- who can access the Shiny app,
- whether RStudio or analyst tooling is exposed at all,
- how backups, logs, caches, and data refreshes are managed,
- and who owns operational support.

Those choices are local infrastructure and governance decisions. They should be
documented by the institution using CEDAR.

## Readiness Checklist

Before relying on CEDAR outputs for departmental or college conversations, an
institution should be able to answer:

- Are all required `cedar_*` tables generated?
- Are student IDs pseudonymized before transformed files are stored?
- Are term codes mapped to CEDAR's chronological convention?
- Are course identity fields sufficient for topics and crosslisted courses?
- Are registration status codes mapped and reviewed?
- Are grade and DFW policies documented?
- Are program, subject, department, and college mappings validated?
- Are unmapped codes visible for review?
- Are small-cell and demographic disclosure rules defined?
- Are data refresh, cache, and rollback steps documented?

If the answer to any of these is no, the project may still be useful for an
analyst-led pilot, but it should not be presented as a settled institutional
reporting surface.
