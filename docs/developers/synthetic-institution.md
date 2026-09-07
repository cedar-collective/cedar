---
title: Synthetic institution
parent: Developer Guide
nav_order: 7
---

# Synthetic institution

The developer app uses existing records from
`tests/testthat/fixtures/designed_test_data.R`. The adapter in `dev/demo-data.R`
assembles those scenarios; it does not maintain a second invented population.

The default export contains five copies of the complete histories. Cohort 1
keeps the original source identities. The production transformation pipeline
creates the analytical tables and encrypts IDs consistently; provenance columns
make each person and section traceable afterward.

## Use it

`bash scripts/dev.sh up` generates the institution in isolated Docker volumes
and serves it at <http://localhost:3838/>. Source changes invalidate the saved
data automatically on the next `up`.

To export a portable bundle with the project's prepared R environment:

```bash
Rscript dev/generate-demo.R output/synthetic-institution
```

The exporter refuses populated directories without a synthetic-data marker.
The bundle includes source-report tables, all `cedar_*.qs` app tables,
`fixture-people.csv`, `fixture-sections.csv`, and `synthetic-institution.json`.
The JSON records actual row counts, terms, campuses, and scenario families.

## Select the original records

```r
students <- qs2::qs_read("output/synthetic-institution/cedar_students.qs")
original <- dplyr::filter(students,
  synthetic_cohort == 1L, fixture_source == "base")

# Original fixture ID, even though the app's student_id is encrypted:
dplyr::filter(original, fixture_student_id == "STU-HD-SP1-001")
```

`fixture_source` distinguishes base enrollment/population histories, Regstats,
Gen Ed associations, campus movement, retention, graduates, and major-entry
scenarios. The section table also includes Seatfinder and rotating topics.
Use both cohort and scenario when checking original expectations: the complete
institution intentionally combines several populations.

The base HIST 1110 Spring 2020 cohort retains 21 registrations and nine late
drops: reconstructed census enrollment is 30. The BIOL 2305 Fall 2020 internal
crosslist retains three CRNs and a deduplicated total of 71. NURS 2010 supplies
waitlist demand; Regstats includes growing, declining, and flat histories.

## What is adapted

Missing section metadata is completed from the fixture's enrollment rows.
People with no program history receive explicitly undeclared records; known
students do not receive invented historical declarations. Section identifiers
are unique across scenarios and copied cohorts. College codes, date fields,
and fractional faculty appointments are converted to source-report conventions.
Added sections are marked `synthetic_completion`. Enrollments, grades,
program changes, and terms come from the fixtures.

The independently authored DESR snapshots and class-list headcounts can differ.
The exporter does not invent students to force them to agree. Admissions records
and saved projections are absent. Deliberately corrupt fixtures and standalone
intermediate credit tables remain unit-test inputs.

Copied cohorts provide volume for exploring the app. They are not independent
statistical observations, a performance benchmark, or institutional evidence.
