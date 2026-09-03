---
title: Performance Monitoring
parent: Developer Guide
nav_order: 13
---

# Performance Monitoring

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

## Log files

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
