---
title: Performance Monitoring
parent: Operations
grand_parent: Developer Guide
nav_order: 3
---

# Performance Monitoring

Where a slow page's time goes, what the app records about each report, how to
profile the part that is slow, and which of it a test holds.

## Where a slow page's time goes

**A page that takes too long is usually not a slow report.** The app is one R
process, and R answers one request at a time. What a reader waits for is four
stretches, and only the last is the analysis:

| Stretch | What happens in it | Who pays |
|:--|:--|:--|
| The process starts | `global.R` loads the tables and the functions, builds the UI, compiles the server function and then builds some pages ahead | the first request after a restart, and anyone who arrives during the build-ahead |
| The session starts | every module server's set-up runs, for every page, whichever tab the link names | every session, a few seconds each |
| The queue | another session's run, or a build-ahead job, has the one R process | whoever arrives meanwhile |
| The report | the analysis, or the read of a cached or shared result | the run |

The report's own timer sees only the last. On 2026-11-25 a Dept Dashboard link
that read its cached result in 0.17 seconds took 30 on production: the process
had been restarted that morning, and the time was the session starting while R
compiled the server code it was running for the first time (ISSUES I81). So
find the stretch before profiling anything.

**On production.** The files under the data directory give one session's
times: `report_timing.csv` (each report's seconds), `client_render_timing.csv`
(what the browser measured) and the day's usage log under `logs/` (when the
page was there, when the session's first observer ran, when the run began).
Compare a slow session's gaps with those of a session in a process already in
use. The morning's scheduled restart means the first reader of the day meets a
new process ([Droplet Installation](droplet-installation.html) has the
schedule). Do not `tail` the nginx container's `access.log`: it is a link to
stdout, the command never returns over ssh and leaves processes behind.

**In a browser.** `sessionStart(page)` (`tests/e2e/lib.mjs`) returns, for a
page `connect()` opened, the seconds to the websocket opening (`connected`),
to the page's first busy state (`busy`) and to the end of the session's first
busy-to-idle cycle (`started`). Connected to busy is before the server
function runs, which is where a process just started waits for the compiler;
busy to started is the session's set-up. `./run-tests.sh --e2e --fresh` prints
the whole start, and the wait from connected to busy, for a new process's
first six sessions
([a process just started](e2e-testing.html#a-process-just-started)). For one
deep link, a puppeteer script with a CDP session (`Network.enable`, logging
`webSocketFrameSent` and `webSocketFrameReceived` with the time) shows the
same stretches and then the run.

## What the app records for each report

CEDAR records both the server calculation and the browser-visible wait for its
main reports. Open **Data & Usage → Cache → Report Timing Estimates** and click
**Refresh Timing Stats** to compare report types and fresh/cache paths.

The median describes a typical run. The 90th percentile (P90) describes the
slow tail and is usually the better prioritization measure for a shared Shiny
process. The table separates:

| Measure | Interpretation |
|:--|:--|
| Total | Time from the user's request until the output is delivered and painted. |
| Compute | Time inside the report's server timer. |
| Wait/delivery | Event-loop waiting and delivery time before the browser receives the completion message. This can rise when other sessions occupy the Shiny worker. |
| Browser settle | Output handling and painting after the completion message arrives. |
| CPU | Process CPU consumed during the server timer. |
| Worker growth | Change in the R worker's resident memory across the operation. |
| Result size | Size of the retained R result object returned by an instrumented report. |
| Payload | Approximate JSON value size delivered to report outputs. |
| Connected sessions | Browsers connected to that R worker at the observation boundary. |

Use the measures together. High compute and CPU points toward the R analysis.
High total with modest compute, especially when connected sessions are high,
points toward queueing or delivery contention. High browser settle and payload
points toward output serialization or rendering. Large result objects and
worker growth identify candidates for narrower payloads, precomputation, or
cache changes.

The loading overlay learns from the most recent 100 observations for each
report and cache path. Once three browser observations exist, it shows the
recent median-to-P90 end-to-end range. Until then it falls back to server
calculation history and finally to the configured static default. This avoids
presenting a fast calculation or cache lookup as if it were the user's full
wait.

### Log files

`report_timing.csv` contains calculation, CPU, worker memory, result size,
cache, session, success, and report-parameter fields. `client_render_timing.csv`
contains total, compute, wait/delivery, browser settle, payload, viewport, cache,
and session fields. New observations share an `operation_id` so the two files
can be joined for run-level analysis.

CEDAR migrates older schemas at startup and keeps the original file beside the
new one with a `.legacy` suffix. Appends use a small cross-process lock so
multiple Shiny workers do not migrate or write the same file simultaneously.

Worker growth is a boundary measurement for the whole R process, not a record
of peak allocations. A negative value can mean that garbage collection freed
memory during the report. Result size measures retained output and may differ
from transient working memory. Connected sessions provide load context but do
not mean every connected browser was actively running a report.

After a release, exercise at least one cold and warm path for each important
report, then review P90 total, P90 compute, wait/delivery, result size, and
worker memory. Compare one-session and many-session observations before
deciding whether the next improvement belongs in analysis code, caching,
payload shaping, or deployment capacity.

## Profiling the slow part

### A session's start

The timeline says which stretch is long; a line profile says which lines. Two
things stand in the way of one: the app's R keeps no line numbers, and a
session runs inside Shiny, where nothing of yours is called before the server
function. So a profiled run is a one-off container with three things mounted
into it, all of them kept outside the repository:

- an `Rprofile.site` of one line, `options(keep.source = TRUE)`, without which
  the profile names functions and no lines;
- an empty directory for the profiles, writable by the container's `shiny`
  user;
- a `server.R` that wraps the real one, which is mounted beside it as
  `server_main.R`:

```r
# global.R reads this file once and Shiny reads it again for the first
# session: the real function is read and compiled at the first read only.
if (!exists("cedar_profiled_server", envir = globalenv())) {
  source("server_main.R", local = TRUE)
  assign("cedar_profiled_server", compiler::cmpfun(server), envir = globalenv())
}
server <- function(input, output, session) {
  Rprof(file.path("/profiles", format(Sys.time(), "session-%H%M%S.prof")),
        interval = 0.02, line.profiling = TRUE)
  session$onFlushed(function() Rprof(NULL), once = TRUE)
  cedar_profiled_server(input, output, session)
}
cedar_server_to_run(server, cedar_compiled_server, "server.R")
```

```bash
docker compose stop cedar-shiny     # the port, and the memory, are the app's
docker compose run --rm --service-ports \
  -v "$PWD/server.R:/srv/shiny-server/cedar/server_main.R:ro" \
  -v "$HOME/cedar-profile/server.R:/srv/shiny-server/cedar/server.R:ro" \
  -v "$HOME/cedar-profile/Rprofile.site:/usr/local/lib/R/etc/Rprofile.site:ro" \
  -v "$HOME/cedar-profile/out:/profiles" \
  cedar-shiny
```

Open one page, wait for it to settle, and read the profile on the host:

```r
prof <- summaryRprof("~/cedar-profile/out/session-101502.prof", lines = "show")$by.total
head(prof[grepl("\\.R#", rownames(prof)), ], 30)
```

`summaryRprof()` warns "NAs introduced by coercion" as it reads a line
profile; the rows are there all the same. The wrapper's own call is
`server.R#11` and holds the whole start; the real server's lines read
`server_main.R#…`, and every other file keeps its name.

- **Compare sessions line by line.** What a process does once shows as lines
  the first session's profile has and the second's has not. That is how the
  Headcount module's choices, built by the first session and read by the
  rest, were found (ISSUES M75).
- **Compare like with like, and more than one process.** The first reading
  of M75 set a process that had also built ten courses ahead beside ones that
  had not, and took one run for the size of the saving: two seconds, where
  three processes before and three after gave a third of one.
- **A profile names a file by its base name.** `headcount.R#195` is a line of
  `R/modules/headcount.R` or of `R/branches/headcount.R`; open both before
  saying what a line is. M75's first reading took a line of the branch for
  the module's download control.
- **A stall in an unlikely place may be a garbage collection.** The recipe's
  `Rprof()` does not record collections, so a second spent collecting is
  given to whatever was running: `paste0()`, the creation of one observer.
  `Rprof(gc.profiling = TRUE)` shows it as `<GC>`.
- **The container runs the source its image was built with** (all of it but
  the `server.R` mounted here). Rebuild the image first, or mount the checkout
  as `compose.dev.yml` does.
- **`onFlushed()` ends the profile when the session's first results have been
  sent**, which is a start. `session$onSessionEnded()` in its place profiles a
  whole visit.
- **One session at a time.** R has one profiler, and a second session's start
  ends the first one's file.
- **Wait for the build-ahead's last `[preload]` line** in the container's log
  before opening the page, or a job of the build-ahead is measured with it.
  Shiny Server starts the R process on the first request, so a container
  just started or restarted logs nothing until the page is asked for:
  request it (`curl`), then wait.
- **A process's first session costs more than its later ones** (ISSUES M75).
  Profile the first for what a restart adds, and the third for what every
  reader pays.
- **The profiler's own cost was within the noise**: later sessions started in
  4.2 and 4.3 seconds under it, and in 3.6 to 5.6 without.
- **On Apple silicon the container is emulated.** The order of the lines is
  worth reading; the seconds are not production's, and a line that leads in
  the container may not natively (the next section).

### A cone, on the host

An Apple-silicon machine runs the app image (amd64) emulated, and a line
profile taken in the container misleads: one line measured ten times slower
there than natively. Profile an analysis on the host instead, with the local
app stopped (the full tables and the app do not fit in memory together):

```r
options(keep.source = TRUE)
source("scripts/cedar-repl.R")
edges <- cedar_report_edges(cedar_registrations, degrees = cedar_degrees)$edges
Rprof("cone.prof", interval = 0.02, line.profiling = TRUE)
result <- get_something(cedar_attempts, list(data_edges = edges))
Rprof(NULL)
head(summaryRprof("cone.prof", lines = "show")$by.total, 30)
```

Keep the rows whose name holds `.R#`: those are lines of CEDAR's own files.
Production ran about three times slower than an M-series host does natively.

- **The usual cause is a `summarize()`, `slice()` or `min()` per student over
  100,000 or more groups.** The rewrites that keep the rows: `group_by()`,
  then `group_keys()` and `group_indices()`, with `tabulate(index[flag], n)`
  for a count; or one `arrange()` and `distinct(id, .keep_all = TRUE)` for a
  first row per student.
- **Save the result before changing anything** (`saveRDS()` of the function's
  output on the full tables, outside the repository) and compare with
  `identical()` after. It has caught a real difference: a grouped `arrange()`
  drops a table's extra attributes (the schema stamp), the ungrouped rewrite
  kept them, and `tibble::tibble(!!!x)` rebuilds a table without them.
- **Do not trust the suite to hold a rewritten line.** Four of five deliberate
  breaks of rewritten lines passed the existing tests on 2026-11-25. Break
  each one ([prove a test catches the bug](testing.html#prove-a-new-test-catches-the-bug))
  and add a fixed table for what nothing holds.
- **Compare two versions warm.** The first call of a function includes R
  compiling it: call both versions once before timing either.
- A rewrite that moves a `subject_course` grouping keeps its `CAMPUS_ROLLUP:`
  comment directly above the pipeline: `test-architecture.R` looks within
  eight lines.

## What is held, and what is only printed

A time is held by a test only where a run can tell a change from noise. The
rest is printed where the person making the change will see it.

| What | Held or printed | Where |
|:--|:--|:--|
| A process's first two sessions meet a server that begins as soon as it does for the four after | held, to a second: `fresh-start.test.mjs` | [A process just started](e2e-testing.html#a-process-just-started), which has the last measurements |
| A session's whole start | printed by the same run beside the last run on other code; sessions of one process differ by a second and a half, so no allowance would hold it | the same section |
| A result every session shares is built once per process | held: `downstream-glance.test.mjs` opens a second session and compares how long each worked | [Results shared by every session](shiny-modules.html#results-shared-by-every-session-and-built-ahead) |
| The memory the app's container has while the browser suites run | printed by the runner's resource check before the suites | [The browser stages are memory-bound](e2e-testing.html#the-browser-stages-are-memory-bound-and-running-out-does-not-look-like-it) |
| Each report's seconds, fresh and from cache | recorded by the app and shown on Data & Usage; nothing fails on them | [What the app records](#what-the-app-records-for-each-report) |
| What the process spends starting | printed in the container's log: `global.R` gives the seconds for each table it loads, for compiling the server functions and for each job of the build-ahead | `docker logs` |

`./run-tests.sh --e2e --fresh` is the one run that times a start. It adds its
six sessions to a history on the machine it ran on
(`tests/e2e/.fresh-start-history.jsonl` in the main checkout, which git
ignores and every worktree shares; `CEDAR_START_HISTORY` names another file)
and prints them beside the latest run recorded on other code:

```
     whole start, sessions 1 to 6: 6.3 4.5 4.2 5.7 4.4 4.6 s  (4110a0b+changes)
     the last run on other code:   7.6 8.1 4.2 6.2 4.4 4.2 s  (248a3da, 2026-11-20)
     since then: first session -1.3 s, second -3.6 s, the later ones +0.2 s at the median
     printed, not held: sessions of one process differ by a second and a half among themselves
```

The code named is what was checked out. The app runs it only when its image
was rebuilt from it or the checkout is mounted, so the comparison means what
it says after `./run-tests.sh --all --fresh`. A run whose checks failed is not
recorded.
