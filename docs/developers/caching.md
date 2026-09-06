---
title: Caching
parent: Developer Guide
nav_order: 24
---

# Caching

The cache-key contract, the two cardinal rules and the incidents behind them, and the conventions every cached CEDAR computation follows.

Several expensive computations are cached to disk. The general infrastructure
lives in `R/trunk/cache.R` (course-neighbors, dept-profile tabs, population
benchmarks); the Regstats dashboard keeps its own cache in
`R/features/regstats.R`. All of them follow the same shape: a `get_*_cache_key()`
(or `create_*_cache_filename()`) builds a key, save/load helpers read and write
`.qs`/`.Rds` files under `get_cache_dir()`, and a miss returns `NULL` so the
caller recomputes.

**The cardinal rule: the cache key must encode every input that changes the
result.** If a filter, option, or data version can change the output but is not
part of the key, two different requests collide on the same cache entry and the
second silently gets the first's result — the filter appears dead even though
the compute path is correct. This is exactly how the Regstats Part-of-Term
filter broke: `create_regstats_cache_filename()` omitted `pt`, so changing PoT
reused a stale cache file. When you add a new filter/option to a cached feature
(especially a new Regstats input), add it to that feature's key function in the
same change, and verify the key string actually changes when the input changes.

**The second cardinal rule: never persist configuration into a cached payload.**
A cache stores *data*. Configuration — palettes, thresholds, feature flags,
anything read from `config/` — belongs to the running app and must be read live
on every load. Storing it means a payload written under an old config keeps
forcing that old config on everything rebuilt from it, and the key has nothing
that could notice, because config is not an input the key covers.

This is exactly how the Dept Trends charts turned rainbow: `set_payload()` put
`palette = cedar_report_palette` into the report cfg, and `cache_dept_tab()`
persisted the whole cfg. Cache files written while the config said `"Spectral"`
kept feeding that string into `cedar_brewer_palette()` — which happily resolved
it as an RColorBrewer palette name — for every chart taking a `palette`
argument, months after the config had been set to `NULL`. The compute path was
correct the whole time; source-level tests all passed, because they read the
*current* config. Fixed 2026-07-31 by stripping `palette` on write, reading it
from live config on restore, and adding `cedar_dept_cache_version` to the key.
Dept Trends v5 also stores compact, built Plotly objects so warmed sessions do
not rebuild charts. The palette is fingerprinted in the key but remains absent
from the payload. Build the Plotly traces before serialization and remove
`visdat`, `cur_data`, `attrs`, and `layoutAttrs`; otherwise formula environments
can silently pull full source tables into a cache file.

If a cached payload must record which config produced it, put that in the
**key**, not the payload — then a config change is a cache miss instead of a
silent override.

What a key must cover:
- **All result-affecting filters/options** — every `opt` field the computation
  reads. Prefer hashing the whole relevant option set over hand-listing keys:
  `get_population_benchmark_cache_key()` digests `list(version, term, college,
  opt)`, which can't silently under-specify. The hand-built readable filename in
  `create_regstats_cache_filename()` is easy to under-specify — that's what bit
  us; if you keep that style, treat the key builder as correctness-critical.
- **Data freshness** — so a stale entry can't outlive the data. Existing choices:
  a data hash (`cedar_students_hash` / `cedar_sections_hash` in course-neighbors),
  the current term (`cedar_current_term` / `cedar_report_end_term`), or a short
  time window when the computation itself depends on the calendar. Pick the one whose
  granularity matches how the underlying data moves. **A time-based key alone is
  the weakest option**: it cannot notice a same-period change to the data *or*
  the code, so an entry written Monday is served all week no matter what ships
  after it. Prefer a data hash; if you use a week/term key, pair it with a
  version counter. The `dept_*` keys had neither until 2026-07-31, which is why
  the `"Spectral"` payloads above survived every deploy that week.
- **A manual version counter** (e.g. `cedar_course_neighbors_cache_version`,
  `cedar_population_benchmark_cache_version`)
  — bump it whenever you change the *shape or logic* of the cached output so old
  files aren't served. A key that only covers inputs won't invalidate when you
  change the computation itself.

Other conventions in use, worth matching:
- Loads return `NULL` on miss/error and the caller recomputes. This is a
  documented supported state, **not** a silent fallback (see Coding Standards) —
  the "no fallbacks" rule is about masking *errors*, and a cache miss is not one.
- Non-standard requests may bypass the cache entirely rather than pollute it —
  Regstats skips the cache when custom thresholds are set (`using_custom_thresholds`).
- Write atomically (`.tmp` then `file.rename`) and store only serialisable
  **data** — not plots, not live `data_objects`, and not configuration (see the
  second cardinal rule) — rebuilding the rest on load. `cache_dept_tab()` is the
  reference: it strips `plots`, `data_objects_filt`, and `palette` before
  writing. The dept *dashboard* cache is the deliberate exception — it does
  store built plot objects, which is why a palette change requires bumping
  `cedar_dept_dashboard_cache_version`.
- `clear_all_caches()`, `clear_dept_cache()`, and `clear_course_cache()` exist
  for manual invalidation; reach for a version bump or a data-hash/term/date key
  before relying on manual clears.

Dept Trends uses content-addressed, per-tab caches. Headcount, Degrees, and
Demographics are department/report-window artifacts; Enrollment also keys on
campus, current term, and calendar year, while Credit Hours keys on campus.
`scripts/warm-dept-trends-cache.R` prepares the standard production scope after
data refreshes. Nonstandard campus combinations compute on first use. Gen Ed is
kept lazy because its independent provider/graduate analyses and protected
instructor detail have different scopes. Never add plots or palette values to
these cached payloads; extend the tab's data tables and `rebuild_*()` helper.

