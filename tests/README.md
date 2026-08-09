# CEDAR Tests

Run tests from the repository root through the single standard entry point:

```bash
./run-tests.sh          # selector check + complete R suite
./run-tests.sh --e2e    # plus browser suites; app must already be running
./run-tests.sh --all    # rebuild container, then run the complete release gate
```

For a tight edit loop, a focused committed `testthat` file is allowed:

```bash
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-<name>.R')"
```

Do not add standalone runners, copied smoke scripts, Python browser probes, or
production-data tests. Add durable logic coverage to `tests/testthat/`, browser
coverage to `tests/e2e/*.test.mjs`, and make sure every committed browser suite
is included in `run-tests.sh`.

## Layout

- `testthat/` contains deterministic R tests built on committed designed fixtures.
- `testthat/fixtures/designed_test_data.R` is the shared institutional data shape.
- `e2e/` contains committed Puppeteer regressions against the running Shiny app.

The complete testing policy, fixture rules, environment details, and reporting
requirements live in [the developer testing guide](../docs/developers/testing.md)
and `AGENTS.md` under **Standard Testing Procedure**.
