# Demo institution mapping files

The synthetic demo (`dev/demo-data.R`, `dev/generate-demo.R`) is its own
institution: these files, not UNM's, decide every unit and college it reports
(ADR-002 Stage 5). The demo generator and the demo app set
`CEDAR_INSTITUTION=demo`; the demo builds with `institution/unm/` absent.

The codes are the ones the shared test fixtures use (`HIST`, `SOCI`, `NURS`…),
and the colleges' `source_names` translate the fixtures' college groups
(`ARTS`, `SOSC`, `STEM`, `BUS`, `NURS`, `EDU`, `POPH`). Columns and rules are
the same as UNM's; see `institution/unm/README.md`.

Every row is confirmed: the demo has no decisions waiting, so Admin > Mappings
shows none. A fixture code with no row here would be listed there, as at any
institution. `BUSA` is a program, not a pre-major: the fixtures flag a few BUSA
rows pre-major, and a flag is stated per code.
