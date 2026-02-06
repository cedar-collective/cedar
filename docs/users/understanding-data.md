---
title: Understanding Your Data
parent: User Guide
nav_order: 5
---

# Understanding Your Data

CEDAR presents enrollment data in ways that should be intuitive, but it helps to understand where the data comes from and what it represents.

## Data Sources

CEDAR works with several types of institutional data:

### Course Sections (DESR)

The Daily Enrollment Status Report contains information about every course section:

- What courses are offered
- When and where they meet
- Who's teaching them
- How many students are enrolled
- Current capacity and availability

### Class Lists

Detailed student-level enrollment data:

- Which students are in which sections
- Registration status (registered, dropped, withdrawn)
- Final grades (for completed terms)
- Student demographics

### Program Data

Information about student majors and minors:

- Primary and secondary majors
- Minors and concentrations
- Student level (freshman, sophomore, etc.)
- College affiliation

### Degree Data

Records of degrees awarded:

- Degree type (BA, BS, MA, PhD, etc.)
- Program/major
- Graduation term

## Key Concepts

### Enrollment vs. Headcount

This is one of the most common points of confusion:

| Concept | Definition | Example |
|:--------|:-----------|:--------|
| **Enrollment** | Count of registrations | Student in 4 classes = 4 enrollments |
| **Headcount** | Count of unique students | Student in 4 classes = 1 head |

CEDAR uses both, depending on what question you're asking:
- "How many seats are we filling?" → Enrollment
- "How many students are we serving?" → Headcount

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

### Course Levels

Courses are categorized by level based on course number:

| Level | Course Numbers | Description |
|:------|:---------------|:------------|
| Lower Division | 100-299 | Introductory, general education |
| Upper Division | 300-499 | Advanced undergraduate |
| Graduate | 500+ | Graduate level |

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

### Why Might Data Be Stale?

- Updates may pause during breaks
- Technical issues can delay updates
- Historical data is static (won't change)

## Common Data Questions

### Why don't my numbers match official reports?

Several factors can cause differences:

1. **Timing** — CEDAR uses nightly snapshots; official reports use census date
2. **Filters** — You may have filters applied that exclude some data
3. **Definitions** — Different systems may define metrics differently
4. **Crosslisting** — Enrollment may be counted differently for crosslisted courses

{: .important }
CEDAR data is **not official institutional data**. For required reporting (IPEDS, state reports, etc.), always use your official institutional data office.

### What's the census date?

The census date is typically the end of the second week of classes (third Friday). Official enrollment counts are frozen at this point for required reporting.

CEDAR data continues to update throughout the term, so it may show different numbers than census-date reports.

### How are crosslisted courses handled?

Crosslisted courses (same class offered under multiple subject codes) can be tricky:

- **Enrollment** may be split across listings
- **Credit hours** are counted for each listing
- Some reports "compress" crosslisted sections; others show them separately

Check if your view is using "compress crosslists" or showing them individually.

### What about cancelled sections?

By default, CEDAR excludes cancelled sections. This gives you an accurate picture of what actually ran. Some reports have options to include cancelled sections if needed.

## Limitations

### What CEDAR Doesn't Do

- **Official reporting** — Use institutional data for required reports
- **Individual student tracking** — Student IDs are encrypted for privacy
- **Real-time data** — Updates are nightly, not instant
- **Predictive analytics** — CEDAR is descriptive, not predictive

### Data Privacy

CEDAR takes student privacy seriously:

- Student IDs are encrypted (hashed)
- No individual student names are shown
- Data is aggregated for most analyses
- Access should be limited to those who need it

## Getting Help

If you have questions about your institution's data:

- Contact your CEDAR administrator
- Reach out to your institutional research office
- Check with your registrar's office for official definitions

For questions about CEDAR itself:

- Check the [FAQ](#common-data-questions) above
- Open an issue on [GitHub](https://github.com/fredgibbs/cedar/issues)
- Email fwgibbs@unm.edu
