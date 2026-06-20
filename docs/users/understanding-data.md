---
title: Understanding Your Data
parent: User Guide
nav_order: 20
---

# Understanding Your Data
CEDAR tries to make institutional data easier to inspect at the unit level. The same source records can support several reasonable definitions, so the notes below explain what CEDAR is reading and what its numbers mean.

## Data Sources
CEDAR works with several types of institutional data:

### Course Sections (DESR)

The Department Enrollment Status Report contains information about every course section:
- What courses are offered
- When and where they meet
- Who's teaching them
- How many students are enrolled
- Current capacity and availability


### Class Lists
Detailed student-level enrollment records:

- Which students are in which sections
- Registration status (registered, dropped, withdrawn)
- Final grades (for completed terms)
- Student demographics

CEDAR derives `cedar_students$term` from the Class Lists `Academic Period Code`
field. When an analysis needs a student's enrollment anchor, CEDAR may use the
minimum observed class-list term for that student. This means "first observed
class-list enrollment," not a formal Banner matriculation or start-term field.

CEDAR also derives `cedar_student_term_credits` from Class Lists. This table
summarizes each student's observed UNM credits by term and is used by Pathways
for movement-card credit timing and Common Pathways medians. Completed credits
come from credit-earning outcomes; attempted credits come from observed
registered course attempts.


### Program Data
Information about student majors and minors:
- Primary and secondary majors
- Minors and concentrations
- Student level (freshman, sophomore, etc.)
- College affiliation

CEDAR derives program-history rows from Academic Studies data. The Academic
Studies `Academic Period` becomes `cedar_programs$term`; program columns such as
`Major`, `Second Major`, and their matching code fields become normalized
`program_name`, `major_code`, `program_code`, and `program_type` values. CEDAR
also carries context fields such as `Student Population`, `Institution Credits
Attempted`, and `Overall Credits Attempted` into the program table. Those fields
can be useful context, but Pathways timing cards now use class-list-derived UNM
credit histories when they need term-specific credit timing.

Pre-major status is computed inside CEDAR from program naming and code patterns.
The Pathways > Major Changes tab treats a move from a selected pre-major into
the matching selected full major as a conversion within the same program family,
not as a departure to another major.

### Degree Data
Records of degrees awarded:

- Degree type (BA, BS, MA, PhD, etc.)
- Program/major
- Graduation term

## Key Concepts

### Term Codes
CEDAR uses 6-digit term codes:

| Code | Meaning |
|:-----|:--------|
| YYYY | Year |
| T | Term type (1=Spring, 6=Summer, 8=Fall) |
| S | Session (usually 0) |

**Examples:**
- 202510 = Spring 2025
- 202560 = Summer 2025
- 202580 = Fall 2025

### Observed Dates vs. Formal Start Dates

Some Pathways views report timing in terms or credits. For entry-timing cards,
the term count starts from the student's first observed class-list enrollment in
CEDAR. That anchor comes from Class Lists, not from a formal Banner admission,
matriculation, or start-date field. Because of that, headline entry cards exclude
records that are already present at the beginning of the available data window or
that first appear with substantial prior UNM attempted credits.

Credits shown in Pathways movement cards come from class-list-derived UNM credit
histories. Completed credits are based on observed credit-earning outcomes.
Attempted credits are based on observed registered attempts. These figures do
not include transfer credits or UNM coursework outside the loaded Class List
window.

Some reference tables may still display Academic Studies cumulative credit
fields as transfer-inclusive context. When those fields appear, they should be
read as source-system context rather than the term-by-term credit timeline used
by the timing cards.


### Registration Status
Students can have different registration statuses:

| Status | Meaning |
|:-------|:--------|
| Registered | Currently enrolled |
| Dropped | Removed from course (before deadline) |
| Withdrawn | Removed from course (after deadline, with W grade) |

## Data Freshness

### When Is Data Updated?
CEDAR data is typically updated nightly during the academic year. The update usually runs overnight, so morning data reflects the previous day's registrations.

### How Do I Know When Data Was Updated?
Look for "as of" dates in reports and on data tables. This tells you when the underlying data was extracted from the source system.


## Common Data Questions

### Why don't my numbers match official reports?

Several factors can cause differences:

1. **Timing** — CEDAR uses nightly snapshots; official reports use census date
2. **Filters** — You may have filters applied that exclude some data
3. **Definitions** — Different systems may define metrics differently
4. **Crosslisting** — Enrollment may be counted differently for crosslisted courses

{: .note }
CEDAR is designed for internal exploration, planning, and methodological transparency, not official external reporting. For IPEDS, state reports, or accreditation submissions, use your institutional data office; those reports depend on definitions and certification processes calibrated for those specific requirements.


### What's the census date?
The census date is typically the 15th day of the semester, which is the third Friday. Official enrollment counts are frozen at this point for required reporting.

CEDAR data continues to update throughout the term, so it may show different numbers than census-date reports.


### How are crosslisted courses handled?

Crosslisted courses (same class offered under multiple subject codes) can be tricky:

- **Enrollment** may be split across listings
- **Credit hours** are counted for each listing
- Some reports "compress" crosslisted sections; others show them separately

Check if your view is using "compress crosslists" or showing them individually.

### What about cancelled sections?

By default, CEDAR excludes cancelled sections. This keeps most views focused on sections that actually ran. Some reports have options to include cancelled sections when the scheduling question requires them.

## Limitations

### What CEDAR Doesn't Do

- **Official reporting** — Use institutional data for required reports
- **Real-time data** — Updates are nightly, not instant


### Data Privacy
CEDAR takes data privacy seriously:

- Data is aggregated for most analyses
- Student and instructor IDs are encrypted 
- User-facing views avoid exposing direct student identifiers
- Restricted instructor-level outcomes are password protected where they appear
