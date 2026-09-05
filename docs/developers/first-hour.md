---
title: Your First Change (Docker)
parent: Developer Guide
nav_order: 0
---

# Run CEDAR and make your first change

You need Git, a running Docker installation with Compose, a browser, and any
text editor. VS Code is convenient, but not required. You do **not** need local
R, RStudio, Node, mrgather, production credentials, or institutional data.

The demo is a separate local instance containing invented records. It uses the
normal CEDAR transformation and analysis code. It does not mount production data
or read your production `.env`, and it cannot deploy a change.

## 1. Get your own checkout

If you cannot push branches to the CEDAR repository, fork it on GitHub first and
clone your fork. Otherwise:

```bash
git clone https://github.com/cedar-collective/cedar.git
cd cedar
git switch -c contribution/demo-help
```

Open this folder in your editor. Run the following commands from its terminal
or any terminal in the repository root. On Windows, use a WSL checkout and
terminal with Docker integration enabled; the launcher uses Bash.

## 2. Start the synthetic demo

```bash
bash scripts/dev.sh up
```

Open [localhost:3839](http://localhost:3839/). You should see CEDAR's Home page
and a yellow **Synthetic data — development only** notice. The first image
build downloads R packages and can take several minutes; subsequent builds
reuse those layers. Opening the app also starts its R worker.

No `.env` or personal R configuration is needed. The fixed demo current term is
Fall 2026, with nine terms beginning Spring 2023. History, Mathematics, Computer
Science, and English have course offerings. Dates are intentionally fixed;
Admin's old-looking refresh dates are synthetic, not a failed nightly refresh.

Try Course Dynamics for MATH 375, Fall 2026, Albuquerque. Its shared offering
with CS 375 has 30 current registrations: 20 under MATH and 10 under CS. Across
both listings there are two late drops, so reconstructed census enrollment is
32. There are also two early drops and four waitlisted records across the pair.
Use the displayed campus/college scope when comparing results across pages.

## 3. Make an edit you can see

For a first practice edit, open `ui.R` and search for:

```r
These invented records are not institutional results. Demo current term: Fall 2026.
```

Change it to:

```r
Explore safely with invented records. No institutional student data is shown. Demo current term: Fall 2026.
```

Save, then run:

```bash
bash scripts/dev.sh restart
```

Refresh the browser. The banner should show your new wording. R source is
mounted from your checkout, but the R worker must restart to load edits.
Restart disconnects only local demo sessions. Rebuild with `up` if you change
dependencies, Docker configuration, or the demo generator.

For analytical edits, remember that CEDAR caches some report results. Use
Admin's cache controls to clear the relevant demo cache when checking a changed
calculation, and follow the cache-version rules when preparing the actual fix.
Changing code does not by itself change a persisted report's cache key.

This is a practice-sized contribution. Before submitting, choose wording that
actually improves the help text or agree another small issue with a maintainer;
there is no need for every contributor to submit this same banner change.

## 4. Test the change in Docker

```bash
bash scripts/dev.sh test
```

This builds a disposable test image from your current checkout and runs the
standard `run-tests.sh` selector checks and complete R suite. It does not require
the demo app to be running. This command does not run browser tests: record your
manual browser check. The PR workflow runs the synthetic browser acceptance
checks automatically; a maintainer still runs the appropriate institutional
browser gate before release. Analytical changes need a regression test, not
just a screenshot.

## 5. Prepare a pull request

```bash
git diff
git status --short
git add ui.R
git commit -m "Clarify synthetic demo notice"
git push -u origin contribution/demo-help
```

Open a PR from your branch to CEDAR's `main`. Describe the change and why it
helps; include the test result and a screenshot for visible changes. Stage only
the files you intended to change. Never attach real student data, exports,
credentials, or production screenshots containing sensitive information.

For your next contribution, follow [Contributing](contributing.html) and
[Testing](testing.html). Reuse the shared enrollment/outcome functions rather
than creating another counting rule inside the UI.

## Daily commands and troubleshooting

| Need | Command or action |
|---|---|
| Start or update the demo | `bash scripts/dev.sh up` |
| See saved R/UI edits | `bash scripts/dev.sh restart`, then refresh |
| Run selector and R tests | `bash scripts/dev.sh test` |
| See startup/error messages | `bash scripts/dev.sh logs` (Ctrl-C stops following logs, not the app) |
| Stop the demo | `bash scripts/dev.sh down` (retains synthetic data) |
| Port 3839 occupied | `CEDAR_DEV_PORT=3840 bash scripts/dev.sh up`; open port 3840 |
| Docker unavailable | Start Docker and check your terminal has permission to use it |
| Blank/error page | Read the logs; check `demo-init` completed successfully |
| Edit does not appear | Save, restart, refresh, and confirm you are on port 3839, not production/3838 |

The generated data and output live in Docker volumes belonging to the
`cedar-demo` project. They survive container rebuilds. Generation reuses unchanged
data and rebuilds it after source changes when you run `up`. Never point these
volumes at institutional data. A nonempty directory without the synthetic marker
is rejected. No automatic deletion/reset command is provided.

## What the demo does and does not establish

`dev/demo-data.R` contains the invented source records; `dev/generate-demo.R`
feeds them through `transform-to-cedar.R`. These are not anonymized extracts.
The tiny population is useful for UI development, integration checks, and
understanding the data shape. Small-cell guards may suppress some analyses;
saved projection bundles are not supplied and the projection page explains that.
The demo is not a performance benchmark or evidence about any institution.

Real-data reconciliation and production-scale performance checks remain a
separate, authorized maintainer step before release. When that step reveals an
edge case, add an invented reproduction to the shared unit fixtures so the next
contributor can test it without restricted data.
