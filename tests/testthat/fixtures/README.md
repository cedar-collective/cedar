# Shared synthetic data

`designed_test_data.R` is the authored source for CEDAR's analytical test
scenarios. Every record is invented; none is sampled from institutional data.
`setup.R` exposes the tables as `test_*` variables for the R suite.

The developer institution now uses these same records. `dev/demo-data.R`
assembles the usable scenarios, fills missing section/undeclared-program
metadata, and copies complete histories into five cohorts. The production
transforms write the app's tables. Cohort 1 remains traceable through
`fixture_student_id`, `fixture_source`, and `synthetic_cohort`.

Malformed-input fixtures and isolated intermediate credit tables remain in the
unit suite. They are not appended to the institution. The developer export never
rewrites this source or changes the unit suite's original populations.

See [Testing](../../../docs/developers/testing.md) for fixture rules and
[Synthetic institution](../../../docs/developers/synthetic-institution.md) for
export instructions, scenario coverage, and examples of selecting cohort 1.

Add reusable institutional scenarios here with an EC/XL/MC identifier and
hand-worked expected values. Update affected numerical tests when a scenario
changes. A single function's intermediate or deliberately malformed inputs may
stay local to its test, as explained in the testing guide.

`create-test-fixtures.R` is an unused historical sampling recipe. Do not add
records there or revive its binary fixtures.
