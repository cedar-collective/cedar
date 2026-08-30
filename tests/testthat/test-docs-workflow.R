context("Docs workflow")

test_that("shared definitions trigger both docs and app workflows", {
  docs <- readLines("../../.github/workflows/docs.yml", warn = FALSE)
  app <- readLines("../../.github/workflows/deploy.yml", warn = FALSE)
  # Check the ordered trigger block directly; R's YAML 1.1 reader treats
  # GitHub's `on` key as a boolean instead of a YAML 1.2 string.
  trigger <- app[seq_len(match("  workflow_dispatch:", app))]
  expect_true('      - "docs/**"' %in% docs)
  expect_true("    paths:" %in% trigger)
  expect_false("    paths-ignore:" %in% trigger)
  expect_true("      - '**'" %in% trigger)
  expect_gt(match("      - 'docs/_data/definitions.yml'", trigger),
            match("      - '!docs/**'", trigger))
})


test_that("docs workflow runs when its own workflow file changes", {
  workflow <- paste(readLines("../../.github/workflows/docs.yml", warn = FALSE), collapse = "\n")

  expect_match(workflow, '- ".github/workflows/docs.yml"', fixed = TRUE)
})


test_that("docs workflow retries a stuck Pages deployment once", {
  workflow <- paste(readLines("../../.github/workflows/docs.yml", warn = FALSE), collapse = "\n")

  expect_match(workflow, "id: deployment_primary", fixed = TRUE)
  expect_match(workflow, "continue-on-error: true", fixed = TRUE)
  expect_match(workflow, "uses: actions/deploy-pages@v5", fixed = TRUE)
  expect_match(workflow, "if: steps.deployment_primary.outcome == 'failure'", fixed = TRUE)
  expect_match(workflow, "id: deployment_retry", fixed = TRUE)
  expect_match(
    workflow,
    "steps\\.deployment_retry\\.outputs\\.page_url \\|\\| steps\\.deployment_primary\\.outputs\\.page_url"
  )
  expect_match(workflow, "if: steps.deployment_primary.outcome == 'failure' && steps.deployment_retry.outcome == 'failure'", fixed = TRUE)
})
