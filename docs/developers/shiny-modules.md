---
title: Shiny Module Detail
parent: Developer Guide
nav_order: 26
---

# Shiny Module Detail

The long-form companion to the Shiny Module Pattern section of `AGENTS.md`: table and plot gotchas, selectize/CSS traps, the shareable-URL registry, and the page-structure heading contract.

## Module UI Gotchas From Cancellations

**Tables are user interfaces, not raw cone dumps.**
- Keep the cone return contract broad enough for analysis, but make each Shiny table choose an explicit display-column order.
- Put workflow/context columns first: campus, college, term, course, title, CRN/section, then metrics/dates.
- If users ask to hide fields, hide them in the module display `select()`, not by removing them from the cone output.
- If one `make_reactable()` helper serves multiple table shapes, either pass table-specific `columns =` or filter the column definitions before calling `reactable()`:
```r
columns <- columns[names(columns) %in% names(df)]
```
Reactable errors if `columns` includes names not present in `data`.
- For narrow inspection tables, use `fullWidth = FALSE` so striped rows do not stretch across the whole viewport. Keep wide raw-data tables full width.
- Sort inspection tables in the order users scan them. For trend backing tables, prefer chronological term, then descending count, then label.
- **Part-of-Term columns use the shared `cedar_pot_coldef()` helper** (`ui-helpers.R`), never a hand-rolled colDef. It renders `1` → "Full", blank/`NA` → "—", and half/nonstandard terms (`1H`, `2H`, `INT`, …) in semibold, so the label and cell treatment stay identical across tabs (regstats, seatfinder, cancellations, …). Any new table with a `part_term` column should call it.
- **`cedar_tbl_theme` uppercases every header** (`textTransform: uppercase`). A header that must keep mixed case — e.g. "PoT" rather than "POT" — has to override it with `headerStyle = list(textTransform = "none")` on its colDef. `cedar_pot_coldef()` already does this; hand-rolled colDefs that set `name = "PoT"` will silently render "POT".

**Plotly is preferred when hover detail matters.**
- CEDAR already loads `plotly`; use `plotlyOutput()` / `renderPlotly()` for charts where users need tooltips or dense drill-down detail.
- Keep chart labels quiet. Use `hovertext = ~...` plus `hoverinfo = "text"` for tooltip-only content. Do not use `text = ~...` unless you actually want labels printed on the plot; Plotly may render it visibly on bars.
- For stacked plots with many departments/units, show the top N units and collapse the rest to `"Other"` for color readability. Put the `"Other"` breakdown in hover text and expose the plotted data in a table underneath.
- Strip names from vectors before sending them to Plotly or Shiny JSON when they are intended as arrays:
```r
term_levels <- pull(df, term_label) |> unname()
colors <- as.list(unname(palette[seq_along(unit_levels)]))
names(colors) <- unit_levels
```
Named atomic vectors can trigger jsonlite warnings such as `Input to asJSON(keep_vec_names=TRUE) is a named vector`.
- Use lists, not named atomic vectors, for UI choice objects or JSON payloads when they need object semantics. Example: `choices = as.list(dept_choices)`.

**Selectize and CSS need special care.**
- Prefer shared UI helpers and existing CSS classes (`filter_bar`,
  `filter_scope_stripe`, `scope-bar`, `section_block`, `cedar_tbl_theme`,
  etc.) over tab-local styling. Do not fix layout glitches with inline
  `style =` attributes or one-off CSS classes unless there is no reusable
  pattern; if a new visual pattern is genuinely needed, add/extend a shared
  helper or generic CSS rule and migrate the caller to it.
- Shiny/selectize copies Bootstrap classes onto generated wrappers and dropdowns. A selectize dropdown can have both `.selectize-dropdown` and `.form-control`.
- Do not style all `.filters-compact input[type=text]`; Selectize's tiny internal search input is also a text input and will become a stray bordered one-line box.
- Filter-bar form-control rules should exclude both Selectize wrappers and Selectize dropdowns:
```css
.filters-compact .form-control:not(.selectize-control):not(.selectize-dropdown) { ... }
```
- Reset Selectize internals separately:
```css
.selectize-control.form-control { border: none; padding: 0; background: transparent; }
.selectize-dropdown.form-control { height: auto; padding: 0; }
.selectize-input > input { border: none; padding: 0; box-shadow: none; }
```
- When CSS differs across tabs, inspect the live generated DOM. The same Shiny input type can render with different copied classes depending on `selectInput()` vs `selectizeInput()` and module/server-side setup.

**Loading and empty states.**
- Use the current modal/overlay pattern from Open Seats/Regstats; do not resurrect old notification-only loading protocols.
- Center loading overlays with a fixed-position overlay selector for the module ID.
- Always show a clear blue info callout when a run succeeds but returns no rows for the selected criteria. If a secondary tab intentionally ignores one filter (e.g., Trends ignoring exact term codes), do not hide useful secondary results just because the primary table is empty.

**User-facing polish review.**
Before marking a release-polish item complete, check the rendered app, not just
the code. The review pass should confirm:

- chart legends, labels, hover text, and dense plots are readable with no obvious
  overlap;
- scope notes or blue explanation panels are visible near non-obvious
  calculations, filters, denominators, and exclusions;
- empty states say what is missing and what the user can change;
- each tab or subtab opens with a clear first answer before optional detail;
- modals use shared title, close, confirmation, and error wording patterns;
- long explanations move into `info_panel()` or another compact disclosure when
  they interrupt the page's first answer;
- users do not have to read the docs to understand a basic calculation
  difference visible on the page.

**Prose width uses character measures, not viewport percentages.** CEDAR's app
canvas is fluid, so `70%` or `80%` becomes too wide on a large monitor and too
narrow inside a smaller panel. Use the shared tokens and semantic classes in
`www/cedar-custom.css`:

- `--prose-measure-brief` (`105ch`) for short subtab introductions and hints;
- `--prose-measure-standard` (`90ch`) for ordinary dashboard explanations;
- `--prose-measure-long` (`80ch`) for sustained methodology/help reading.

Apply a measure to the text, never to a wrapper that also contains tables,
plots, filter strips, or cards. Those data/layout containers normally use the
full available width. Prefer `.cedar-lead`, `.cedar-body`, `.text-hint`, or the
explicit `.cedar-prose-*` utilities over a new `max-width` literal.

**Input values must match actual data values.** Always check the data parser (`R/data-parsers/transform-to-cedar.R`) or existing filter usage before hardcoding `choices =` in a `selectInput`. Display labels and data values often differ — e.g., the Level field stores `"lower"`, `"upper"`, `"grad"` in the data, not `"undergrad"`. If a UI label like "Undergrad" maps to multiple data values, do the mapping in the server (`opt$level <- c("lower", "upper")`), not in the `choices` vector.

**Refactoring strategy for existing tabs:**
- Do not refactor the remaining inline server.R tabs unless touching them for a separate reason. The `enrl_data` reactive feeds 8+ output handlers and has non-obvious shared state.
- Headcount has been extracted to `R/modules/headcount.R` — use it (with pathways.R) as the extraction template. See `ROADMAP.md` for the recommended extraction order of the remaining inline surfaces.

## URL deep links & shareable state

One registry, `CEDAR_SHARE_SPECS` in `R/trunk/url-state.R`, drives BOTH directions of the shareable-URL round-trip so they cannot drift. Each entry is keyed by the exact navbar tab title and declares `slug` (the `?tab=` value), `prefix`/`sep` (how a namespaced input id is built), ordered `fields` (the only URL keys accepted, with dependency order such as campus before department), `run` (the ordinary run button), optional per-key `types`, optional `aliases`, and an optional early-loading `overlay`.

- **Copy (build a link):** a module wires `cedar_copy_url_observer(input, session, copy_id, values_fn, spec_title = "…")`. On click it builds `?tab=<slug>&autorun=true&k=v…` via `cedar_share_query()` and copies it (the `copy_cedar_url` handler in `ui.R`).
- **Bootstrap (one source of timing):** after all link-related browser handlers are registered, `ui.R` sends `cedar_link_bootstrap` with the original query string. `cedar_link_server()` parses that exact string once and stores the session's shared link state. Do not read `clientData$url_search` independently in a tab or module.
- **Restore (ordered and fail-closed):** `cedar_restore_from_query()` accepts only the spec's declared fields. `cedar_schedule_link_restore()` applies them one at a time in registry order and waits until each value has round-tripped to the server before moving on. If a value cannot be restored, autorun does not run with a different scope.
- **Run (same path as a person):** after every declared value matches, the controller publishes one server-side run event. The report's ordinary observer consumes `cedar_run_trigger(input, session, input_id, spec_title)`, which merges that event with manual button presses. There is one report entry point and no synthetic browser click or tab-specific autorun observer.
- **Tabs and history:** `CEDAR_TAB_SLUGS` is serialized to the browser for initial activation, URL updates, and Back/Forward. Never add a hand-maintained JavaScript slug map.

**Server-side selectize (`server = TRUE`) remains module-owned.** The module owns the potentially large choices, while shared link infrastructure owns the selected URL value. Initialize it through `cedar_linked_server_selectize()` after `cedar_link_server()` has been installed:

```r
cedar_linked_server_selectize(
  session = session,
  root_session = parent_session,
  input_id = "wl_course",
  choices = sort(unique(students$subject_course)),
  spec_title = "Waitlists",
  key = "course"
)
```

- Declare the key as `type = "select_server"` in the share spec. The module restores it through `cedar_linked_server_selectize()`; the controller only waits for its real server input value. Never add a second controller-side write, which can make a transient value look ready before module initialization settles.
- The `selectize_set_value` handler must include selectize's `label` field; adding only `value`/`text` renders the chip as the literal string `undefined`.

**Headcount is deliberately not deep-linkable in 1.0.** Its six server-side selectizes cascade (college → department → major/minor/concentration). It has no `CEDAR_SHARE_SPECS` entry and no copy button. Adding it requires declaring the full field order and verifying every cascade in the running app; partial restoration is not acceptable.

**Headcount program intersections are per student and term.**
`filter_programs_by_opt()` intersects `(student_id, term)` pairs for active
major/minor/concentration filters: AND across filters, OR within each selection.
Never intersect student IDs across history to claim simultaneous membership.
Institutional filters apply first; department remains a program-row filter, so
cross-department combinations leave it unselected. The returned rows follow the
primary filter (major > minor > concentration). See the versioned
`program-headcount` record and the EC-10 fixture.


## Page structure — every section is a heading plus a description

**Shared definitions:** `docs/_data/definitions.yml` is the authored source for
the migrated metric explanations. `R/trunk/definitions.R` validates and selects
records; `load_funcs()` loads them once as static metadata. Use
`cedar_definition_summary()` for descriptions and `cedar_definition_note()` /
`cedar_definition_panel()` from `ui-helpers.R` for blue boxes. Jekyll uses the
same records in its user guides and versioned reference page. Keep actual run
scope, data edges, and exclusion counts beside results. Full methodology lives
on the docs site; do not add static Methodology tabs. Preserve published record
versions and append a new version when meaning or wording changes. See
`docs/developers/definitions.md` for the contract and release order.

**A tab body is a stack of `dashboard_section()`s. Every section states what it
shows in one sentence, directly under its heading.** A heading alone makes the
reader infer the counting rule; the sentence is where scope, denominator, and
exclusions get said. This is the "transparency" half of the 1.0 UX north star,
and it is why the helpers take a `description` argument rather than just a
title.

The hierarchy, all from `R/modules/ui-helpers.R`:

| level | helper | renders |
|---|---|---|
| tab title + subtitle | `filter_bar(title, subtitle, …)` | the green band at the top of every tab |
| **subtab title** | **`subtab_header(title, description, …)`** | **near-black h2 + copy, no fill** |
| major group | `dashboard_section(title, description, …)` | filled green heading bar + copy |
| block inside a group | `dashboard_subsection(title, description, …)` | uppercase green heading + copy |
| minor in-flow heading | `section_heading(title, level = "h5"/"h6")` | plain text heading, no description slot |

Rules:

- **A subtab opens with `subtab_header()`, never with a section bar.** The
  subtab's own title must not look like a divider inside itself. `subtab_header`
  is larger than a section bar (1.35 vs 1.2rem) but carries no fill, so the page
  reads *subtab by size, section by fill*. Every `nav_panel()` / `tabPanel()`
  that holds content gets one.
- **Section bars are for dividing a subtab that has more than one section.** A
  subtab with a single section does not need both — the `subtab_header()` alone
  is the heading, and its `dashboard_subsection()`s can sit directly beneath.
- **Use `dashboard_section()` / `dashboard_subsection()` for anything a user
  reads as a section of the page.** Reach for `section_heading()` only for a
  minor label inside an already-described block.
- **Never use a bare `h3()`–`h6()`.** An unclassed heading renders at browser
  default and will not match anything around it.
- **`description` is not optional in spirit.** If a section genuinely needs no
  explanation, that is a signal the section may not need to exist.
- **Say the exclusions.** If a number leaves something out — early drops are not
  in DFW, crosslist partners are deduplicated, summers are dropped — the
  description is where that goes, not the docs. Pages should not depend on the
  user guide to explain a basic calculation difference.
- **Two sections showing the same numbers is a bug.** If a scope strip restates
  what the summary cards already show, delete one.

Reference implementations: Dept Dashboard (`ui.R`), Course Dynamics → Rollcall,
Explore → Gen Ed.

## Module inventory

| File | UI / server pairs | Mounted at |
|------|-------------------|------------|
| `pathways.R` | `pathwaysUI/Server`, `populationSelectorUI/Server` | Pathways |
| `headcount.R` | `headcountUI/Server` | Explore > Headcount |
| `seatfinder.R` | `seatfinderUI/Server` | Explore > Open Seats |
| `cancellations.R` | `cancellationsUI/Server` | Explore > Cancellations |
| `waitlist.R` | `waitlistUI/Server` | Explore > Waitlists |
| `gen-ed.R` | `genEdExploreUI/Server`, `deptProfileGenEdUI/Server` | Explore > Gen Ed; Dept Trends Gen Ed panel (`deptProfileGenEd*` is the legacy internal function name) |
| `regstats.R` | `regstatsUI/Server` | Regstats |
| `retention.R` | `retentionUI/Server` | **Hidden** — UI commented out in ui.R pending cross-course comparison (`retentionServer` is still wired in server.R); course-level retention lives in Course Dynamics |
| `admin.R` | `dataStatusUI` (static HTML, no server), `changelogUI/Server`, `cacheUI/Server` | Admin freshness, changelog, and cache management |
| `ui-helpers.R` | shared UI primitives, not a module: `filter_bar`, `filter_scope_stripe`, `info_panel`, `empty_state`, `section_block`, `dept_selector_bar`, …; plus shared table pieces `cedar_tbl_theme` (the reactable theme every table uses) and `cedar_pot_coldef()` (standardized Part-of-Term column) | used across modules and ui.R |

**Layout pattern:**
```r
pathwaysUI uses layout_sidebar():
  sidebar (width=320, always open) — cohort builder
  main content — navset_tab with analysis panels
```

**Wiring in ui.R / server.R:**

## Coding standards — full text

Moved from `AGENTS.md`, which keeps the condensed rules.

## Numeric precision, rounding, and identifier display

**Round for display only, and preserve enough visible precision to explain every derived statistic shown beside it.** Calculations use unrounded values; round once in the final display adapter (`mutate()` for a display tibble, a shared formatter, or a table/plot column definition). Never round an input or intermediate value before computing a rate, difference, average, trend, SMD, or other statistic.

- **Do not apply one generic numeric formatter to semantically different columns.** Counts, percentages, continuous means, statistical diagnostics, and numeric-looking identifiers require separate column definitions or a row-aware shared formatter. A mixed table must not let a count formatter erase decimals from means.
- **Counts** display as whole numbers and may use thousands separators (`1,234`). **Percentages/rates** normally display one decimal unless the analytical context requires more. **GPA and continuous means** normally display two decimals. **SMDs and similar diagnostics** normally display three decimals.
- Display precision must make adjacent values reconcilable. If two group means feed a reported difference or SMD, do not render both as `3` when the underlying values are `3.26` and `2.98`; show the decimals needed to make the diagnostic plausible. Increase precision when ordinary defaults would still collapse meaningfully different values.
- Missing numeric values display as an em dash, not `0`, unless zero is the actual measured value.
- **Identifiers are not quantities.** Term codes, CRNs, student IDs, course numbers, and similar codes never receive thousands separators, decimal suffixes, or magnitude-based abbreviation. In particular, Banner term codes render as six ungrouped digits (`202580`), never `202,580`.
- Prefer or extend shared formatters in `R/modules/ui-helpers.R` when the same convention appears on multiple surfaces. Keep raw cone/branch outputs numeric and analysis-ready; formatting belongs in the UI/display layer.

## No fallback behavior

**Never write silent fallbacks.** If a required column is missing, a join produces no rows, or an input is malformed, raise an explicit error. Do not substitute defaults, return empty results, or silently skip.

```r
# Wrong — hides the real problem
result <- tryCatch(get_something(df), error = function(e) tibble())

# Wrong — silent coalesce when column should always exist
dept <- df$dept_code %||% df$department

# Right — fail loudly
if (!"dept_code" %in% names(df)) stop("dept_code column required but not found in input")
```

This applies everywhere: cones, branches, trunk, data pipeline scripts, and test helpers. Only two `tryCatch` uses are allowed: (a) in Shiny module servers, where a caught error is immediately shown to the user via `showNotification()`; and (b) around a genuinely fallible *statistic* (e.g. `chisq.test` on a degenerate table) where `NA` is the correct mathematical answer — never around data access. `tryCatch(..., error = function(e) NULL)` around a data pipeline is always a bug.

## Standardize counts and shared visuals — always prefer a helper

**Before writing a count, a rate, or a visualization inline, look for an existing helper — and if one doesn't exist but the pattern shows up in more than one place, add one and route all callers through it.** Divergent local implementations of "the same thing" are how two tabs end up disagreeing about a course's enrollment or drawing subtly different sparklines.

- **Ways of counting** — enrollment, drops, DFW, fill, headcount: there is (or should be) exactly one canonical definition. Census enrollment is `add_census_enrl()` / `calc_census_enrl_baselines()` (`R/branches/enrl.R`); DFW is `classify_enrollment_outcomes()` (`R/trunk/utils.R`); term type is `add_term_type_col()` / `get_term_type()`. Call these, don't re-derive `registered + dr_late` (or a grade filter, or a `substr(term, 5, 6)`) by hand. If you find the same formula written twice, that's a bug waiting to happen — extract it.
- **Enrollment history** — per-term active-enrollment series and its display: `summarize_term_enrl_series()` builds the term→(`has_active`, `term_enrl`) series (single course or keyed by course group); `format_term_history()` is the canonical text formatter and renders values first, with terms after: `"12, C, 10 (Fa22, Sp23, Fa23)"`; `drop_shell_sections()` removes active/zero-enrollment/unstaffed placeholders first (instructor sentinels in `NO_INSTRUCTOR_NAMES`, `R/lists/status_codes.R`). All in `R/branches/enrl.R`; used by both `get_course_enrollment_history()` and `get_enrollment_concerns()`. Dashboard helpers such as `.compact_enrl_history_str()` and `.recent_history_str()` may choose which terms to show, but must call `format_term_history()` for display. Don't re-hand-roll either the `group_by(term) %>% summarize(sum(total_enrl[status=="A"]))` slice or the history string.
- **Enrollment Trend Signals tab** — momentum and plot-prep helpers live in `R/branches/enrl.R`. Campus is part of the course key; multi-campus selections must produce separate course-campus series.
- **Shared visualizations** — sparklines, fill bars, tier/status badges, trend cells, reactable column defs: live in `R/modules/ui-helpers.R` (`make_sparkline()`, `trend_cell_html()`, `cedar_pot_coldef()`, …). A new tab that needs a sparkline uses the shared one so every sparkline reads the same; it does not hand-roll SVG.
- When a computation or component is currently inline and you touch nearby code, that's the moment to promote it to a helper and migrate the other callers — leave the codebase more standardized than you found it.

## Page structure — every section is a heading plus a description

**Shared definitions:** `docs/_data/definitions.yml` is the authored source for
the migrated metric explanations. `R/trunk/definitions.R` validates and selects
records; `load_funcs()` loads them once as static metadata. Use
`cedar_definition_summary()` for descriptions and `cedar_definition_note()` /
`cedar_definition_panel()` from `ui-helpers.R` for blue boxes. Jekyll uses the
same records in its user guides and versioned reference page. Keep actual run
scope, data edges, and exclusion counts beside results. Full methodology lives
on the docs site; do not add static Methodology tabs. Preserve published record
versions and append a new version when meaning or wording changes. See
`docs/developers/definitions.md` for the contract and release order.

**A tab body is a stack of `dashboard_section()`s. Every section states what it
shows in one sentence, directly under its heading.** A heading alone makes the
reader infer the counting rule; the sentence is where scope, denominator, and
exclusions get said. This is the "transparency" half of the 1.0 UX north star,
and it is why the helpers take a `description` argument rather than just a
title.

The hierarchy, all from `R/modules/ui-helpers.R`:

| level | helper | renders |
|---|---|---|
| tab title + subtitle | `filter_bar(title, subtitle, …)` | the green band at the top of every tab |
| **subtab title** | **`subtab_header(title, description, …)`** | **near-black h2 + copy, no fill** |
| major group | `dashboard_section(title, description, …)` | filled green heading bar + copy |
| block inside a group | `dashboard_subsection(title, description, …)` | uppercase green heading + copy |
| minor in-flow heading | `section_heading(title, level = "h5"/"h6")` | plain text heading, no description slot |

Rules:

- **A subtab opens with `subtab_header()`, never with a section bar.** The
  subtab's own title must not look like a divider inside itself. `subtab_header`
  is larger than a section bar (1.35 vs 1.2rem) but carries no fill, so the page
  reads *subtab by size, section by fill*. Every `nav_panel()` / `tabPanel()`
  that holds content gets one.
- **Section bars are for dividing a subtab that has more than one section.** A
  subtab with a single section does not need both — the `subtab_header()` alone
  is the heading, and its `dashboard_subsection()`s can sit directly beneath.
- **Use `dashboard_section()` / `dashboard_subsection()` for anything a user
  reads as a section of the page.** Reach for `section_heading()` only for a
  minor label inside an already-described block.
- **Never use a bare `h3()`–`h6()`.** An unclassed heading renders at browser
  default and will not match anything around it.
- **`description` is not optional in spirit.** If a section genuinely needs no
  explanation, that is a signal the section may not need to exist.
- **Say the exclusions.** If a number leaves something out — early drops are not
  in DFW, crosslist partners are deduplicated, summers are dropped — the
  description is where that goes, not the docs. Pages should not depend on the
  user guide to explain a basic calculation difference.
- **Two sections showing the same numbers is a bug.** If a scope strip restates
  what the summary cards already show, delete one.

Reference implementations: Dept Dashboard (`ui.R`), Course Dynamics → Rollcall,
Explore → Gen Ed.

## Reuse before writing

Search these locations, in order, before implementing anything:

1. `R/trunk/utils.R` and `R/trunk/filter.R` — term math, `filter_class_list()`, `filter_DESRs()`, `add_next_term_col()`, `validate_population()`, etc.
2. `R/lists/` — `STATUS_REGISTERED`, `STATUS_WAITLIST`, `GRADES_DFW`, `GRADES_PASS`. Never inline `c("RE","RS","RR")` or grade strings.
3. `R/branches/` — `build_population()`, `build_comparison()`, `get_course_outcome_rates()`, `get_enrl()`, `get_course_section_counts()`.
4. The cone/branch tables above — an existing cone may already answer your question.

A concrete check: `grep -rn "your_concept" R/trunk R/branches R/lists` before writing a helper. Duplicated logic found later gets consolidated *up* a layer, never copied sideways.

## Readable package calls

Prefer bare function names for packages already loaded by the app/test harness (`filter()`, `mutate()`, `select()`, `bind_rows()`, etc.). Avoid `package::function()` prefixes when they only add visual noise. Use an explicit namespace only when it prevents ambiguity, calls a package that is not normally attached, or makes an uncommon dependency clearer.

## Complexity budget

- New cone functions: aim for < 150 lines per function. If a cone file passes ~500 lines, split by sub-question or extract branch helpers.
- New modules: UI and server for one tab, one file. If a module server passes ~300 lines, business logic has leaked in — extract it.
- No new dependencies (packages) without explicit user approval. Prefer what `renv.lock` already pins.
- Plotting: **native `plot_ly()` only.** No new `ggplot()` + `ggplotly()`. When you touch a function that still uses ggplot, convert it.

## Every change ships with

- A test in `tests/testthat/` filtering from the committed fixtures (never inline tibbles), run with `Rscript --vanilla -e "testthat::test_file('tests/testthat/test-<name>.R')"` from the repo root.
- Updated AGENTS.md tables if you added or renamed a cone, branch, or module.
- No custom testing scripts. Use the committed test harnesses and gates below; do not create ad hoc shell, R, Node, Python, or browser-driver scripts to "just check" behavior unless the user explicitly asks for a new permanent test tool.

---
