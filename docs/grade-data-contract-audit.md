# Grade Data Contract Audit

This audit documents current consumers of `get_grades()` before and during the
course-attempt / DFW separation.

## Public API Guidance

New cones should not call `get_grades()` unless they need the legacy report
bundle. Use:

- `get_course_outcome_rates()` for DFW, W, D/F, C-, and below-C metrics.
- `get_grade_distribution()` for A/B/C/D/F/W/Other grade distributions.
- `prepare_course_attempts()` only when a cone needs row-level cleaned attempts.

## Current Consumers

| Consumer | Current Need | Migration Status |
| --- | --- | --- |
| `R/cones/seatfinder.R` | Course-level `dfw_pct` by campus/college/course | Migrated to `get_course_outcome_rates()` |
| `R/cones/course-outcomes.R` | Course-term DFW trend, instructor DFW, course average DFW | Migrated to `get_course_outcome_rates()` |
| `R/reports/gen-ed.R` | Gen Ed course DFW and grade distribution | Migrated to `get_course_outcome_rates()` and `get_grade_distribution()` |
| `R/reports/course-report.R` | Full `grade_data` bundle for course report plots/tables | Keep on `get_grades()` until report contract is audited |
| `R/reports/dept-report.R` | Lower-division DFW plot bundle via `get_grades_for_dept_report()` | Keep on `get_grades()` until Dept Profile DFW removal/migration |
| `R/trunk/command-handler.R` | CLI/export access to the legacy grade bundle | Keep on `get_grades()` for compatibility |

## Legacy `get_grades()` Return Contract

`get_grades()` remains a report compatibility facade. It returns:

- `counts`
- `dfw_summary`
- `course_inst_avg`
- `course_term`
- `course_avg`
- `course_avg_by_term`

The legacy `dfw_pct` is preserved during phase 1:

```text
dfw_pct = (failed + late_dropped) / (passed + failed + late_dropped) * 100
```

Here, `failed` means any non-passing, non-W, non-early-drop grade under the
legacy gradebook policy. This includes C- and other non-passing outcomes.
Nuanced component columns are exposed by `get_course_outcome_rates()`.
