# Demo institution mapping files

The synthetic demo (`dev/demo-data.R`, `dev/generate-demo.R`) is its own
institution: these files, not UNM's, decide every unit and college it reports
(ADR-002 Stage 5). The demo generator and the demo app set
`CEDAR_INSTITUTION=demo`; the demo builds with `institution/unm/` absent.

The codes are the ones the shared test fixtures use (`HIST`, `SOCI`, `NURS`…),
and the colleges' `source_names` translate the fixtures' college groups
(`ARTS`, `SOSC`, `STEM`, `BUS`, `NURS`, `EDU`, `POPH`). Columns and rules are
the same as UNM's; see `institution/unm/README.md`.

`campuses.csv` names the four campus codes the fixtures use (ABQ, EA, GA, VA)
and `course_levels.csv` carries UNM's leading-digit bands, which the fixtures'
course numbers follow. `gen_ed_courses.csv` lists the fixture courses UNM's
Gen Ed areas contain, under those areas, and `excluded_courses.csv` the two
fixture courses UNM excludes, so the demo's Gen Ed tab and excluded-list
controls have something to show. `population_groups.csv` groups the fixtures'
program names into four named populations for Pathways and the projections
scenario.

Every row is confirmed: the demo has no decisions waiting, so Admin > Mappings
shows none. A fixture code with no row here would be listed there, as at any
institution. `BUSA` is a program, not a pre-major: the fixtures flag a few BUSA
rows pre-major, and a flag is stated per code.
