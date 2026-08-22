---
title: Campus-Grain Audit (2026-08)
parent: Developer Guide
nav_order: 9
---

# Campus-Grain Audit - 2026-08-09

CEDAR's campus rule is about **delivery identity**, not display preference. A
course metric is keyed by `(campus, subject_course)` because the same course at
ABQ, EA, and a branch represents different students and delivery conditions.
Filtering to a campus does not replace grouping by campus.

## Delivery Metrics Audited

The 1.0 audit traced course keys from transformation through payloads and plots.
These surfaces now require or preserve campus:

| Surface | Campus contract |
|---|---|
| Course Outcomes persistence | Outcome groups are campus-course rows. |
| Roadblocks / Stopout | Cohorts and DFW comparisons are campus-course rows; next-term return remains UNM-wide. |
| Bottleneck waitlists | Waitlisted-versus-registered keys include campus. |
| Pathways Course Timing | Titles, thresholds, medians, rows, and plot labels share one campus-course key. |
| Major-entry heatmap | Population cells and all-student denominators join by campus-course. |
| Gen Ed course trends | Course series and modality rows retain campus. |
| Gen Ed course-major associations | Course groupings require campus, including title lookup joins. |
| Transformed enrollment data | Student-course deduplication retains campus. |
| Crosslist transformation | Crosslist groups are local to term and campus. |

Multi-campus fixtures exercise opposite ABQ/EA outcomes, ABQ/GA course timing,
campus moves, and same-course rows on multiple campuses. The standard test gate
also checks that the transform keeps campus in its dedup and crosslist keys.

## Intentional Rollups

Some questions do not have one delivery campus. These remain campus-neutral by
design after the caller's campus scope is applied:

- ordered course pairs and downstream-course pickers
- prior-course histories around a major change or declaration
- graduate Gen Ed uptake: whether a graduate ever took a catalog course
- institution-wide same-term workload context for a focal DFW event
- student-term observed credit loads
- course catalog, title, ownership, and ranking lookups
- curriculum newness across the institution
- the named ABQ+EA enrollment-planning market, which deduplicates students and
  pools capacity while saving every campus/part-term delivery component

Each literal campus-free course grouping is marked nearby with
`CAMPUS_ROLLUP:` and a reason. The architecture suite rejects an unmarked
literal `subject_course` grouping, making new exceptions visible during review.

## Verification

The completed fast gate passed 2,731 assertions with 0 failures and one known
fixture-dependent skip. Release verification uses the canonical procedure:

```bash
./run-tests.sh --all
```
