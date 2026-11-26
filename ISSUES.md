# CEDAR Issues

Known problems and improvements in CEDAR **as it exists today** — code, data,
tests, docs, and interface. Each entry is concrete enough to say where it is
and when it is done. New features and significant upgrades are planned in
`ROADMAP.md`, which links here rather than repeating these entries; finished
work lives in git history and the changelog.

**A quick test for where something belongs:** could someone write "done when…"
for it today, against code that already exists? Then it is an issue. Does it
need design, or a decision about something new? Then it is roadmap.

There are two kinds, in two sections:

- **[Defects](#defects)** (`I` numbers) — CEDAR produces a wrong number or
  breaks. Each carries the evidence and a reproduction, because a defect that
  changes numbers is urgent and must never have to be diagnosed twice. **Post a
  defect the moment it is discovered**, even if it will be fixed in the same
  sitting. A *suspected* defect (two paths that may disagree) is posted with how
  to check it.
- **[Improvements](#improvements)** (`M` numbers) — debt, inconsistency, missing
  tests, and interface standards: what, where, and done when. Short by design.

IDs are stable: code and docs cite them. Resolved entries stay, with
`Status: resolved` and the resolving commit, until the next release, so that a
recurrence is recognizable. **An entry's status lives here and nowhere
else**: other files link to the entry instead of restating where it stands.

**Order for the improvements** (from the 2026-10-07 audit): reconcile counts
computed twice (I16, M1–M3, M24); then the architecture rules file by file
(M11 silent fallbacks first, because they hide failures, then M13 logic in
modules); then interface consistency one tab per PR (M17, M18); file size
alongside other work (M14, M16).

## Open items

| ID | Kind | Summary |
|---|---|---|
| [I68](#i68--the-compiled-computer-science-board-plans-composition-i-twice) | Defect | The compiled CS board plans Composition I twice: the English route's ENGL 1110 (`engl1`) and the reading's "Composition I: ENGL1110Y, ENGL1110Z or ENGL1110" choice (`composition_one_1`), 3 credits too many |
| [I67](#i67--a-compiled-business-board-plans-its-writing-choice-before-composition-ii) | Defect | With stretch English, the compiled Business board plans "3 credits: ENGL2120 or ENGL2210" (`writing_1`) in semester 2, before Composition II in semester 3, though both options require it: a compiled choice tile carries no prerequisite its options share |
| [I61](#i61--summer-2025-holds-nr-grades-where-summer-2024-held-none-and-reads-as-a-dfw-spike) | Defect | Summer 2025 holds 1,479 NR grades in 336 sections (Summer 2024: none), so it reads 22.5% DFW against about 13% for other summers; suspected an early pull before grades rolled |
| [I55](#i55--the-instructor-gate-password-stopped-reaching-the-app) | Defect | The instructor-gate password stopped reaching the app: since 2026-09-05 `.Renviron` is kept out of the image and nothing else passed `CEDAR_DFW_PASSWORD`, so every instructor gate on production reads "not configured" (fixed in code 2026-11-12; production needs the password in its `.env`) |
| [I46](#i46--a-deploy-that-must-rebuild-a-table-the-app-cannot-start-without-takes-the-site-down) | Defect | The deploy's table gate ran after the health check, so a deploy that added a column to `cedar_student_terms` failed its health check on the missing column and never reached the gate: production served the restart page from 17:07 UTC on 2026-11-04 (gate moved before the first request) |
| [I45](#i45--the-class-list-and-the-schedule-name-the-same-section-with-different-course-codes) | Defect | The class list and the schedule name the same section with different course codes for renamed subjects (SOC to SOCI, PSY to PSYC): SOCI 371 had class-list history from Fall 2019 but no sections before Fall 2021 (fixed for every reader by keying the loaded tables on the course, 2026-11-07; open until the remaining successions are confirmed) |
| [I43](#i43--every-scheduled-refresh-fails-because-the-default-asks-for-a-report-mrgather-never-fetches) | Defect | Every scheduled refresh failed from 2026-10-24 to 2026-11-03: the default asked for the applicants report, which production mrgather never fetches, and one missing report skipped every table (default fixed 2026-11-03, per-report rebuilds 2026-11-11; mrgather refuses a report it does not have since 2026-11-22; open until production's mrgather is rebuilt from that source) |
| [I38](#i38--a-pathways-program-population-misses-pre-majors-whose-name-differs-from-their-major) | Defect | A Pathways program population misses pre-majors whose name differs from their major: "Film and Digital Arts" holds 1 of the 1,016 Film pre-majors who never declared the major, because `FFDA` is named "FDMA" (fixed 2026-11-11 through `leads_to`; open for the eleven names in `programs.csv`) |
| [I37](#i37--renumbered-courses-lose-their-history) | Defect | Renumbered courses lose their history: ACCT 3401 (was MGMT 340) and the other Fall 2026 ACCT, BUSA and POPH courses read as new (every reader follows a confirmed renumbering; 277 of the 320 title matches confirmed 2026-11-07, 6 deleted, 37 held for review with the reason on each row) |
| [I33](#i33--a-crashed-myreports-download-is-recorded-as-a-successful-fetch) | Defect | A crashed MyReports download is recorded as a successful fetch: on Oct 23 class lists and applicants were never downloaded, and every step reported ✅ (fixed in CEDAR 2026-11-11: the fetch is judged per report by its files and parse stops on a named report with no file; open for mrgather's exit status) |
| [I32](#i32--a-scheduled-refresh-waits-forever-when-myreports-asks-for-a-2fa-code) | Defect | A scheduled refresh waits forever when MyReports asks for a 2FA code: the Oct 11 run sat 12 days at the prompt, unreported (fixed in CEDAR 2026-11-11: the fetch is stopped at the prompt when no one can answer, and after a time limit) |
| [I24](#i24--cis-demo-browser-run-intermittently-loses-the-app-at-open-seats) | Defect | CI's demo browser run intermittently loses the app at Open Seats (probably fixed 2026-10-23: a test race) |
| [I23](#i23--student-ids-are-hashed-with-the-built-in-default-salt) | Defect | Student IDs are hashed with the built-in default salt: the salt protects nothing |
| [I20](#i20--cedar_programs-holds-almost-no-branch-campus-students) | Defect | `cedar_programs` holds 1–3% of branch-campus students; branch program counts read near zero |
| [I18](#i18--cedar_degrees-holds-no-associate-degrees-so-branch-campus-completions-read-zero) | Defect | `cedar_degrees` holds no associate degrees: branch-campus completions read zero |
| [I4](#i4--pre-change-course-ratios-are-confounded-by-career-stage) | Defect | Pre-change course ratios confounded by career stage (deferred) |
| M1–M78 | Improvement | See [Improvements](#improvements) |

### Resolved since the last release

Kept until the next release, so a recurrence is recognisable; each entry below gives its fix.

| ID | Kind | Summary |
|---|---|---|
| [I86](#i86--retentions-course-list-stopped-with-an-error-when-its-students-held-no-graded-course) | Defect | Retention's "Courses Where a DFW Costs the Most" stopped with `object 'pop_p_value' not found` when the students of the chosen level and home campus held no graded course in the terms it reads: an error notice where an empty list belongs. Not seen on a page; found on the fixtures 2026-11-25 |
| [I85](#i85--at-a-glance-was-left-with-no-step-in-one-session-and-nothing-in-the-log-said-why) | Defect | Downstream's At a Glance was left empty in the session straight after the warm-up of a just-started process, four of four times on 2026-11-25. It was the browser-test driver: `connect()` took a quiet page for a started session, the test set the course, and the picker's one-time set-up then emptied it. A reader cannot do that. `connect()` now waits for the session's first busy-to-idle cycle (three of three fresh starts pass) |
| [I84](#i84--the-admin-browser-suite-expected-the-math-starting-point-that-was-replaced) | Defect | The `admin` browser suite failed at its Catalog Review step on `main` from 2026-11-23: it expected the summary to read "Math: Calculus-ready" after Degree Explorer's opening starting point became College Algebra (a76ab5a), and `run-tests.sh` stops at the first failing suite, so the suites after it did not run (the step now expects the opening starting point's label; resolved 2026-11-25) |
| [I83](#i83--a-deep-links-loading-notice-gave-no-estimate-and-no-running-count) | Defect | A link that runs a report on arrival (`autorun=true`) showed a bare "Loading…" until the report arrived: no estimate and no running count, because the overlay it opens before Shiny connects never went through the code that writes them (resolved 2026-11-25) |
| [I82](#i82--downstreams-at-a-glance-showed-an-empty-page-while-it-ran-the-other-views) | Defect | Course Dynamics > Downstream opened on an empty page for as long as its analyses ran (two minutes for FYEX 1110 on production, 2026-11-25): At a Glance runs Against Non-Takers and Next Courses, and each showed its wait on its own subtab, which is hidden then (the waits now show on the page's overlay; the length of the run is [M68](#improvements)) |
| [I81](#i81--the-first-sessions-after-a-restart-wait-while-the-server-code-is-compiled) | Defect | The first session after a restart waited about 10 seconds longer than any other while R compiled the server code (16 on production, 2026-11-25), and the second about 3 more. `global.R` now compiles the module servers and the server function at start, and `server.R`'s last line hands the compiled function to Shiny, which reads that file itself. In the development container the second session's server began 2.8 s after the connection before and 0.2 after. `./run-tests.sh --all --fresh` holds it. The first session's remaining 2 seconds are not compilation ([M75](#improvements)) |
| [I80](#i80--every-session-began-by-recounting-headcounts-program-menu) | Defect | Every session spent about 8 seconds starting (10 on production) before it could respond, on whatever page it opened, 4.5 of them rebuilding Headcount's program menu with one read of the declarations table per program; a deep link to a cached dashboard that loads in 0.2 seconds took 12 to 30 (now 2.3 seconds locally: the rows are found in one pass and the opening choices are shared) |
| [I79](#i79--a-report-whose-conversion-or-read-stopped-part-way-was-stored-as-a-smaller-report) | Defect | `parse-data.R` stored whatever part of an export its converter had written or its reader returned: on 2026-11-23 Fall 2025's Student Holds were stored as the first 211,142 of 300,138 rows (15,152 of 26,890 students) with no error. A converter that does not exit 0, or any warning from the read, now stops the parse (resolved 2026-11-23; what cut that conversion short is not established) |
| [I77](#i77--the-parser-left-each-export-unhashed-beside-its-hashed-file) | Defect | `parse-data.R` left each export as a CSV, names and unhashed IDs included, beside the hashed file it had just written: five files in the local data directory, dated 2026-10-08 (the CSV is now removed once read; the files already written were deleted locally and on production on 2026-11-23) |
| [I78](#i78--the-transforms-status-file-lists-only-the-tables-of-the-last-run) | Defect | `cedar-status.json` held only the tables the last transform run built, so a run of one stage (`--tables degrees`, or the holds catch-up) left `scripts/data-status.sh` listing one table (the file now keeps the entries of tables a run did not rebuild) |
| [I73](#i73--special-topics-st-titles-were-not-treated-as-topics-courses) | Defect | A topics course was recognised only by a title opening "T:"; "ST:" (special topics) sections were stored as ordinary courses, so their history, trends and dashboard cards mixed unrelated topics. The labels are now an institution setting read by one function (resolved 2026-11-20) |
| [I72](#i72--the-enrollment-table-counted-a-crosslisted-offering-by-its-home-listing-alone) | Defect | The Enrollment table showed a crosslisted offering once, on its home row, with class-list counts (first day, census, final) for the home listing's students only, while the schedule's combined total beside it counted every listing. The home row now counts the whole offering, each student once (resolved 2026-11-20) |
| [I71](#i71--regstats-worth-a-look-stops-on-a-topics-course-waitlisted-under-two-titles) | Defect | Regstats' "Worth a look" could not be built for a term in which a topics course had waitlisted students under two titles: the waitlist screen has a row per title and the watch reads one row per course. The watch now reads `waits_by_course`, each student once (resolved 2026-11-20) |
| [I70](#i70--production-mrgather-crashes-instead-of-retrying-a-failed-download) | Defect | Production mrgather crashed instead of retrying a failed download: its image called `tracker.recordReportFetchError()`, which the server's `reportTracker.js` lacked, so on 2026-11-13 one failed Academic Studies download ended the fetch and that day's class list was never pulled. The server's image was rebuilt from its own with only the current `reportTracker.js` added, keeping its Chrome (resolved 2026-11-20) |
| [I69](#i69--the-nightly-dept-dashboard-warm-failed-every-department-since-the-measure-tables) | Defect | The refresh's Dept Dashboard warm failed every department every night from 2026-11-08: the script loaded its own tables and never the measure tables the Registration flags read, so chairs' dashboards were built on first visit. Every loader now reads the measure tables and computes the cache hashes through one function each (resolved 2026-11-19) |
| [I66](#i66--opening-a-downstream-subtab-reruns-the-analysis-at-a-glance-already-ran) | Defect | Opening Against Non-Takers, Next Courses or Prepared for It after At a Glance ran each analysis again, and Coming Back ran twice on opening: a run key held the subtab's Update button value, which Shiny reports as a classed 0 once the button renders and `identical()` holds different from the 0 used before it did. The keys read `cedar_click_count()` (resolved 2026-11-19) |
| [I65](#i65--the-degree-explorer-browser-suite-checks-the-hand-built-boards-the-compiled-drafts-replaced) | Defect | `tests/e2e/degree-explorer.test.mjs` has failed since the compiled drafts replaced the CS, Business, History and Philosophy boards (#309, 2026-11-16): it hovers hand-board tiles (`java1`, `java2`, `os`, `historiography`, `philbuddhist`, `buscapstone`, …) the page no longer draws, and stops at the first. The suite now names the compiled tiles and asserts I64 on Philosophy (resolved 2026-11-19) |
| [I64](#i64--a-compiled-degree-board-plans-400-level-electives-in-the-first-semester) | Defect | The compiled Philosophy board plans its two "6 elective credits at the 400–499 level" tiles, and the four "two at the 400 level" elective tiles, in semester 1: a compiled elective slot was upper only when every course its group requires is upper. Readings can now state a pool's lowest course number (`minimum_course_number`, schema 1.1.0), and 400-level work is planned from a new `senior_level_from_semester` (6); Philosophy's tiles start in semester 6 (resolved 2026-11-18) |
| [I63](#i63--the-online-psychology-pre-major-leads-to-the-campus-major-not-the-online-one) | Defect | `programs.csv` said the online Psychology pre-major XFPY leads to PSY, though 360 of its students declared XPSY (57 PSY): a PSY population counted them as "chose elsewhere". XFPY now leads to XPSY, a separate program (resolved 2026-11-16) |
| [I62](#i62--a-pathways-population-counted-every-program-that-shared-a-name) | Defect | A Pathways population matched programs by Banner name: department BIOL took in 1,873 Biochemistry students (BIOC and FBIC, another unit) because CHBI is named "Biochemistry", "Architecture" merged ARCH and ARCT, and "Liberal Arts" missed its renamed code LAIS (7 ongoing students instead of 411). Populations now match codes, follow confirmed renames in `code_history.csv`, and keep same-named programs apart (resolved 2026-11-16) |
| [I60](#i60--takers-vs-non-takers-opens-on-a-classification-its-home-campus-scope-hardly-holds) | Defect | Takers vs Non-Takers picked its opening classification from the course's takers on every campus and then opened on the page's home campus: HIST 1110 opened on Concurrent Enrollment, nearly all of them dual-credit students at branch campuses, so on ABQ its passed and DFW'd groups were empty in almost every term. The defaults are now read off the takers in the opening home-campus scope (resolved) |
| [I59](#i59--the-dfw-tabs-dfw-by-term-table-stopped-with-an-error-for-every-course) | Defect | The DFW tab's DFW by Term table stopped with an error for every course from 2026-10-16 (#143) to 2026-11-13: its status-exclusion summary read the class list without the graded edge (resolved) |
| [I58](#i58--courses-taken-calls-a-term-in-progress-in-its-charts-and-settled-in-its-tables) | Defect | Courses Taken shaded Fall 2026 "In progress" in its charts and called it settled in its tables, heading and note; every label now reads `cedar_term_in_progress()` (resolved) |
| [I57](#i57--the-instructor-patterns-column-guide-states-a-pass-rule-cedar-does-not-use) | Defect | The Instructor Patterns column guide said "Passing is C− or better, CR, P, or S" beside a table that followed CEDAR's rule (A+ through C and CR). The tab is gone: the breakdown by instructor is a section of Downstream > Later Course, which states no pass rule of its own (resolved 2026-11-13, #280) |
| [I56](#i56--downstream-continuation-misses-every-later-enrollment-after-the-grade-edge) | Defect | Downstream continuation read the later course only to the graded edge while counting eligibility to the settled edge, so the newest students who continued counted as not continuing: 183 of 557 for CHEM 1215 to 1225, confirmed on the 2026-11-13 tables. One cohort (`build_downstream_cohort()`) now reads enrollment to the settled edge and grades to the graded edge, inside a fixed window, by the campus that taught the first course (resolved 2026-11-13, #280) |
| [I54](#i54--the-gen-ed-list-had-no-second-language-area) | Defect | The Gen Ed list had no area 6 (second language): no language course counted as Gen Ed anywhere, 36 courses and 2,228 enrolled seats in Fall 2025 on ABQ and online (reported in #269; the 55 catalog courses added and production's sections rebuilt 2026-11-12) |
| [I52](#i52--sections-stored-the-instructors-employee-id-so-they-joined-no-other-table) | Defect | The DESR's instructor ID was saved as the employee ID while the class list and HR hash theirs: the transform's HR merge matched nothing (`job_cat` NA on all 242,413 sections) and sections joined neither table. Fixed in the transform (every source hashed alike, the merge and `job_cat` removed; resolved 2026-11-12, when the deploy rebuilt production's sections) |
| [I50](#i50--the-class-list-dedup-can-keep-an-early-drop-over-a-late-withdrawal) | Defect | The transform keeps one class-list row per student-course-campus-term but ranked only "registered first": a student who early-dropped one section and withdrew late from another could keep the early drop, so the W left the loaded class list (703 student-course-terms on the 2026-10-08 pull; 651 on the 2026-02-04 one). Every outcome reader now classifies that table (`cedar_attempts`); fixed in the transform (resolved 2026-11-12, when the deploy rebuilt production's class list) |
| [I48](#i48--a-transform-change-to-a-fact-tables-stored-columns-is-not-rebuilt-at-deploy) | Defect | Since the mapping stamps retired (ADR-001 step 3, 2026-11-06) the deploy gate rebuilt only `cedar_student_terms`: a transform change that adds or renames a stored column on sections, students, programs or degrees started the app on files without it until the morning refresh, the I46 shape with no gate (resolved 2026-11-12: each fact table carries a schema stamp the gate checks, and the deploy that carried it rebuilt all four of production's unstamped tables) |
| [I28](#i28--one-late-starting-session-makes-a-whole-courses-first-day-unknown) | Defect | One late-starting session made a whole course's first day unknown (257 Fall 2026 courses on the Oct 8 pull), under a reason that read as missing status dates. Intersession is out of the forecast (model 0.24.0), a session not yet begun is judged on its lower bound (0.25.0), and a section with no start date now has its own basis and reason (resolved 2026-11-11) |
| [I16](#i16--bottleneck-waitlist-pressure-ignores-term-so-later-registration-erases-earlier-waiting) | Defect | `get_bottlenecks()` matched waitlisted against registered rows with no term, so a seat in any later term erased earlier waiting: about 6% under true demand (RStudio only). It now returns the canonical class-list waitlist demand per campus, term and course (resolved 2026-11-11) |
| [I8](#i8--a-timing-log-row-is-silently-dropped-when-the-write-lock-times-out) | Defect | A report-timing row that could not take the log's write lock within 2 seconds was dropped with a console message (8 concurrent workers, 7 rows); it is now kept as a pending file and appended by the next write (resolved 2026-11-11) |
| [I6](#i6--a-killed-projection-rebuild-strands-its-lock-and-blocks-every-later-refresh) | Defect | A projection rebuild that was killed (a deploy timeout, an out-of-memory kill) left its lock for ever and every later refresh failed closed until someone removed it; a held lock now carries a heartbeat, and a lock whose heartbeat has stopped is taken over by the next run (resolved 2026-11-11) |
| [I53](#i53--declaring-the-major-a-pre-major-leads-to-was-counted-as-a-change-of-major) | Defect | Pathways > Major Changes counted a student moving from a pre-major to its own major as a change of major whenever the two names differ ("FDMA" to "Film and Digital Arts"): 1,414 of 23,388 change events (resolved 2026-11-11: a pre-major and the major it leads to are one program) |
| [I51](#i51--a-classification-filter-matched-nobody-its-value-was-split-on-the-comma) | Defect | `filter_class_list()` split every filter value on commas, so a classification filter (`"Sophomore, 2nd Yr"`) became two values that match no row, and Regstats' sophomore screen never found a course (resolved 2026-11-07) |
| [I47](#i47--the-class-lists-student_classification-is-stamped-at-pull-time-when-a-term-is-pulled-late) | Defect | A class list pulled months after its term carries each student's classification as of the pull (35% of ENGL 1120's Fall 2025 registered student-terms one step ahead); every reader now takes the student-term table's, and the loaded class list carries none (resolved 2026-11-07) |
| [I49](#i49--ticking-break-out-by-instructor-errors-the-retention-tables-until-run) | Defect | Ticking "Break out by instructor" on Course Dynamics > Retention errored every retention table until Run, because the renderers read the checkbox rather than how the shown result was computed (resolved 2026-11-07) |
| [I44](#i44--roadblocks-and-retention-disagree-on-whether-a-late-withdrawal-returned) | Defect | Roadblocks and Retention disagreed on whether a student who withdrew late next term returned: Fall 2025 to Spring 2026 read 82.7% on one and 81.7% on the other (284 students) (resolved 2026-11-04) |
| [I42](#i42--a-saturated-course-whose-fall-changes-lower-its-forecast-is-still-called-a-floor) | Defect | A saturated course whose Fall changes lower its forecast was still called "a floor": ENGL 1120's Spring 2027 forecast is 2,164, below last Spring's 2,179, and the page said "so this is a floor" (resolved 2026-11-03) |
| [I41](#i41--projection-labels-call-the-term-just-finished-fall-whatever-its-season) | Defect | Projection labels called the term just finished "Fall" whatever its season: once Spring 2027 settles, a Fall 2027 course whose Spring moved 25% would have been flagged "Fall enrollment +25%" (resolved 2026-11-03) |
| [I40](#i40--the-projections-page-gave-a-forecasts-own-misses-to-the-schedule) | Defect | The projections page gave a forecast's own misses to the schedule: 7 of the 8 Spring 2027 courses whose past misses came with seats to spare read "the misses came when the seats moved", because any seat move counted (resolved 2026-10-29) |
| [I39](#i39--projection-flags-called-last-years-same-season-term-last-term) | Defect | Projection flags called last year's same-season term "last term": a Spring 2027 course flagged "Full last term" was full in Spring 2026, not in the Fall just finished (resolved 2026-10-28) |
| [I36](#i36--low-enrollments-schedule-view-reports-no-prior-history-for-courses-that-have-it) | Defect | Low Enrollment's schedule view reports no prior history for courses that have it: 363 of 2,226 Spring 2027 ABQ/EA undergraduate courses, of which 40 were never offered under that number (resolved 2026-10-24) |
| [I35](#i35--a-fall-projection-is-read-before-the-falls-intersession-has-registered) | Defect | A Fall projection is read before the Fall's intersession has registered: the Fall 2027 spine had none of Fall 2026's December demand (FYEX 1110: 168 of 801 Fall 2025 registrations were December) (fixed in model 0.24.0) |
| [I34](#i34--a-projection-pressure-decision-flips-with-the-platforms-floating-point) | Defect | A projection pressure decision flips with the platform's floating point: NATV 1150 is included for Spring 2027 on Linux and excluded on macOS (fixed in model 0.24.0) |
| [I31](#i31--course-paths-finishes-behind-a-stuck-loading-dialog) | Defect | Nested Course paths report sends completion to the wrong loading-dialog channel (resolved) |
| [I30](#i30--saved-r-workspaces-entered-the-docker-build-context) | Defect | Case-sensitive Docker ignore omitted `.RData`, copying an 89 MB workspace into app image layers (resolved) |
| [I29](#i29--generated-navigation-ids-can-open-the-wrong-panel) | Defect | Generated nav-menu IDs collide, so Admin can open Gen Ed instead of Data & Usage (resolved) |
| [I27](#i27--the-projection-floor-adds-a-waitlist-to-first-day-enrollment-and-compares-it-with-ever-registered-demand) | Defect | The projection floor mixed units: 245 unserved waitlisted students lifted Fall 2027 by 77 (resolved) |
| [I26](#i26--projection-capacity-reached-was-judged-on-ever-registered-demand) | Defect | Projection "capacity reached" was judged on ever-registered demand: 72% of course-terms flagged full when census filled 17% (resolved) |
| [I25](#i25--projection-method-selection-was-in-sample-and-lost-to-the-default) | Defect | Projection method selection was in-sample on two folds and lost to doing nothing; reported 13.7% WAPE, honest 16.5% (resolved) |

---

# Defects

## I86 — Retention's course list stopped with an error when its students held no graded course

**Status:** resolved 2026-11-25 (branch `retention/band-courses-page-scope`).
**Found:** 2026-11-25, writing a test that the section reads the students'
home campus (M67).
**Severity:** low. No number was wrong: an error notice where an empty list
belongs, in a scope not seen on a page.
**Affects:** `retention_dashboard_course_list()`
(`R/features/retention-dashboard.R`), the Retention page's "Courses Where a
DFW Costs the Most".

### What was wrong

`get_stopout()` returns a table with no columns when the students it is given
hold no graded attempt in the terms. `retention_dashboard_course_list()` took
only `NULL` as nothing to list and filtered that table on `pop_p_value`, so
the page showed "Courses: object 'pop_p_value' not found". It takes a level
and home campus whose students have a settled next term and no graded course
in the latest three graded terms of the page's term type; none is known in
the data.

### Reproduce (before the fix)

On the fixtures, where RR01's EA-home students take no course:
`retention_dashboard_course_list(rr01$student_terms, rr01$attempts, NULL,
rr01$dashboard$series, list(student_level = "UG", campus = "EA", data_edges =
rr01_edges, course_min_n = 10L, course_min_dfw_n = 5L))`.

### Fix

A table with no rows is nothing to list, and the section shows no table, as
it does when no term is graded. `test-return-rates.R` ("RR01: the courses
read the latest graded falls' students") holds it.

## I85 — At a Glance was left with no step in one session, and nothing in the log said why

**Status:** resolved 2026-11-25 (branch `test/first-suite-session`). It was
the browser-test driver, in the second session of a just-started process; a
reader cannot take this path. `connect()` now waits for the session to have
started.
**Found:** 2026-11-25, timing Downstream in the local container for M72; seen
three more times the same day, checking the courses built ahead.
**Severity:** low for readers (none can reach it); medium for the test gate: a
first suite run after a restart can fail on an empty page.
**Affects:** `tests/e2e/lib.mjs` (`connect()`, `runAndWait()`),
`tests/e2e/warmup.mjs`.

### What was seen

The first time: Course Dynamics for FYEX 1110 on ABQ and EA, Analyze Course,
then Downstream, as the first session after the warm-up on a container just
started. "Reading the course's outcomes…" ran and the overlay closed;
"Comparing takers with non-takers…" ran (20 seconds); Next Courses and the
sequence comparison never ran, and the page went idle with no step drawn. The
log held no error. Thirteen later sessions opened the same way ran every step.

It came back on each of the next three fresh starts, each time in the session
straight after the warm-up, and never in a later session of the same process.
One of them was traced in the browser:

- the report ran for FYEX 1110 (7.1 seconds in the log) and its outcomes were
  read (1.4 seconds);
- when the page went idle the browser's value for the course picker
  (`cr_course`) was the empty string, and At a Glance held "Select a course
  and click Analyze Course first, then open this tab.";
- in another, `runAndWait()` returned before the report had drawn its tabs,
  and the click on Downstream found no such tab.

### Cause

The course picker gets its choices once a session, from the server
(`cedar_linked_server_selectize()`, when the link bootstrap arrives), and that
message leaves the picker empty whatever it held. A reader cannot pick a
course before it lands: until then the picker has no choices. The driver can,
because `setInput()` writes the value itself.

A process compiles the server function as its second session starts (about 3
seconds, M70). The browser shows no busy state while the server has not begun
to answer, `connect()` reads the quiet page as settled (its own comment names
the symptom: a picker that still reads "Type to search" and a page on its
empty state after the analysis ran), and `runAndWait()` gives the server 400 ms
to say it is busy. Timed on the session straight after the warm-up: connected
at 0.5 seconds, busy at 3.7, idle with the picker's choices at 5.7; the two
sessions after it went busy 0.1 seconds after connecting. `connect()` slept
2.5 seconds, saw 600 ms of quiet and returned at about 3.6. So the driver sets
the course and clicks Analyze, the report runs for that course, and the set-up
message then lands and empties the picker. The page answers as it does when a reader picks another course
without analysing it: it asks for a course. Against Non-Takers reads the
analysed course and so ran the first time; Next Courses and the sequence
comparison read the picker and did not.

The suite warm-up opens one session (the home page), so the first session of
any suite run after a restart is that second session. The four occurrences
were scratch scripts built on `connect()`, `setInput()` and `runAndWait()` as
the suites are; the committed suites are exposed in the same way.

The earlier guess, two caught errors on a VM out of memory, is withdrawn: the
traced occurrences had 1.3 GiB free and no `[caught]` line.

### What changed, so the next one can be read

- The caught errors on this path are written to the log as
  `[caught] <what>: <message>` (`cedar_notify_caught()`,
  `R/modules/ui-helpers.R`).
- At a Glance says on the page that it could not be put together, with the
  message, instead of showing a heading over nothing; a summary that is only
  not ready yet waits, as before.

Neither is the fix: no error is raised.

### Reproduce

Start the app and wait for the `[preload]` lines to stop. Run
`node tests/e2e/warmup.mjs`, then at once a script that connects to Course
Dynamics, sets `cr_course`, clicks Analyze Course with `runAndWait()` and
opens Downstream. Read `Shiny.shinyapp.$inputValues.cr_course` when the page
is idle: it is empty and At a Glance asks for a course. Run the same script
again on the same process: five steps.

### Fix

In the driver. `connect()` (`tests/e2e/lib.mjs`) counts the page's
busy-to-idle cycles from the first moment of the document and waits for the
first one, which is the server running the session's start, before its floor
and its wait for idle; a session that never starts fails with that message.
On three fresh starts, the session straight after the warm-up kept its course
and drew its five steps each time (it had failed four of four). The harness
suite checks that `connect()` returns with a cycle seen. Not changed:
`runAndWait()`'s 400 ms beat, which a started session answers in 0.1 seconds,
and the warm-up, which still opens one session.

## I84 — The admin browser suite expected the math starting point that was replaced

**Status:** resolved 2026-11-25 (branch `perf/session-start`).
**Found:** 2026-11-25, running `./run-tests.sh --changed` for I80 to I83: the
gate stopped at `e2e: admin`.
**Severity:** low for the app (nothing on a page is wrong); medium for the
gate, which stops at the first failing suite and so ran none of the suites
listed after `admin`.
**Affects:** `tests/e2e/admin.test.mjs`.

### What was wrong

Commit a76ab5a (2026-11-23) made College Algebra the starting point Degree
Explorer opens on (`opens` in `degree_roadmap_starts.csv`) and updated
`degree-explorer.test.mjs`. Admin > Catalog Review opens on the same starting
point, and `admin.test.mjs` still expected "Math: Calculus-ready" in its
summary.

### Reproduce (before the fix)

`./run-tests.sh --e2e admin` against the institutional app:
`AssertionError: selected planning scenario shows the math starting-point
label`. The summary reads "Math: College-algebra-ready".

### Fix

The step expects the label of the starting point the page opens on.

## I83 — A deep link's loading notice gave no estimate and no running count

**Status:** resolved 2026-11-25 (branch `perf/session-start`).
**Found:** 2026-11-25, on production, opening
`?tab=dept-dashboard&autorun=true&campus=ABQ,EA&dept=HIST&term=202680`: the
loading notice read "Loading…" for the 30 seconds the page took (I80, I81).
**Severity:** low: nothing is wrong on the page, but a long wait said nothing.
**Affects:** `cedar_loading_overlay()` in `R/modules/ui-helpers.R`, for every
page reached by a link with `autorun=true` and every `show_at_start` page.

### What was wrong

An autorun link's overlay is opened by the script in the page's `<head>`,
before Shiny connects. The overlay's own script then adopted it by starting its
clock and nothing else. The label with its estimate ("cached ~2s; fresh ~20s")
and the count of seconds ("Working for 12s") were written only by
`showOverlay()`, which runs on a button press or a message from the server. A
linked run sends neither: it starts on the server.

### Reproduce (before the fix)

Open any link with `autorun=true` and read `#<id>-loading-label` and
`#<id>-timing-msg` while the overlay is up: "Loading…" and nothing.

### Fix

The adopted overlay writes the same label and starts the same count
(`startWaiting()`, shared with `showOverlay()`). Its estimate is the one
embedded when the app started: a request for current values would be answered
only as the wait ends. `waitlist-deeplink.test.mjs` reads the label as the page
arrives.

## I82 — Downstream's At a Glance showed an empty page while it ran the other views

**Status:** resolved 2026-11-25 (branch `perf/session-start`) for what the page
shows. How long the run takes is M68.
**Found:** 2026-11-25, on production: Course Dynamics for FYEX 1110, then
Downstream. "None of the subtabs display anything."
**Severity:** medium: the page reads as broken for as long as the run takes,
and so does every other page of every other session, since R answers one
request at a time.
**Affects:** `R/modules/course-cohort.R`, `R/modules/later-course.R`,
`server.R` (Course Dynamics), the overlay script in `R/modules/ui-helpers.R`.

### What was wrong

Downstream opens on At a Glance, which runs Next Courses, Against Non-Takers
and Prepared for It on their defaults. Each module showed its wait on the
overlay inside its own subtab. With At a Glance open those subtabs are hidden,
and so were their overlays: the page was empty, with no notice, until the last
of the three began (the only one that used the page's overlay). Clicking
another subtab meanwhile showed that one empty too, because its outputs were
queued behind the run.

### Evidence

Production, 2026-11-25 (UTC), `report_timing.csv`, one session:

| Started | Step | Seconds | Overlay it used |
|---|---|---|---|
| 14:36:51 | `later_course` | 5.4 | Next Courses' own (hidden) |
| 14:36:57 | `course_cohort` | 91.2 | Against Non-Takers' own (hidden) |
| 14:38:33 | `course_sequence` | 19.5 | the page's |

Nothing was on screen from 14:36:51 to 14:38:33. No error was logged and the
results did arrive.

### Reproduce (before the fix)

Course Dynamics, a large course, Analyze Course, Downstream. Until the
sequence comparison starts, `#cr-loading-overlay` is hidden and
`#cr_cohort-load-loading-overlay` is open inside a hidden tab pane.

### Fix

Each module takes the page's overlay (`page_overlay = "cr"`) and opens it, with
its own label, when At a Glance is the open view; on its own subtab it opens
its own as before. The overlay script keeps one overlay open across runs that
follow one another: a run that starts as the one before ends records the
finished run at once, where its pending finish used to hide the overlay under
the new run a moment later. `downstream-glance.test.mjs` records every label
the page's overlay is given and expects both modules' waits among them.

## I81 — The first sessions after a restart wait while the server code is compiled

**Status:** resolved 2026-11-25: the module servers are compiled at start
(branch `perf/session-start`), and so is the server function, which is handed
to Shiny (branch `perf/first-sessions`). What the first session still adds is
not compilation and is M75.
**Found:** 2026-11-25, on production: the first visit of the day, by a link to
a cached dashboard, took 29.6 seconds.
**Severity:** medium: once per restart, so every morning's first reader.
**Affects:** `global.R`; `server.R` and how Shiny reads it.

### What is wrong

R compiles a function the first time it is called (a function not defined at
top level, the second time). The restart's warm-up request fetches the page
and opens no session, so the first person's session compiled every module's
server function, and the second session the server function.

### Evidence

Production, 2026-11-25, one session, from `client_render_timing.csv`
and the usage log: the page was there about 13:33:29; the session's first
observer ran at 13:33:48 (19 seconds, against 2.5 for a session on 2026-11-23
in a process already used); the run began at 13:33:58 (I80); the dashboard
came from cache in 0.17 seconds.

Locally, the same link three times in a fresh process, with a profiler around
the server function: 19.2 seconds, then 8.5 and 9.1. The first session's
server function body took 11.0 seconds against 1.1, and the samples are the
compiler's (`findCenvVar`, `cmpCall`, `putconst`). Compiling the module servers
alone takes 4.5 seconds, the server function 2.5.

### Reproduce

Restart the app, wait for the preload lines to stop, open any page: the gap
between the websocket opening and the first output is several seconds longer
than on the third session.

### Fix, and what remains

`global.R` compiles every module server (`ls(pattern = "Server$")`) after
loading them: 4.5 seconds added to the start, taken off the first session.
With I80 fixed too, the first session's deep link is ready in 5.4 seconds
locally (was 19.2) and later ones in 3.5 (was about 9).

The server function could not be compiled the same way: Shiny reads
`server.R` itself for the first session and runs what that read returns, not
the function `global.R` made from the same file (M70). It was compiled on its
second call, so the second session waited about 3 seconds.

Since `perf/first-sessions`: `global.R` compiles its copy
(`cedar_compile_server()`, `R/trunk/utils.R`; 2 of the 6.3 seconds the start
now spends compiling) and the last line of `server.R` returns it
(`cedar_server_to_run()`), so the function Shiny runs is the compiled one. A
`server.R` changed since the start is run as it now reads. On fresh starts in
the development container, from the connection to the server's first sign of
work: 2.8 seconds for the second session before, 0.2 after, against 0.1 to
0.2 for later sessions; the second session's whole start went from 6.7 to 8.1
seconds to 4.5. `tests/e2e/fresh-start.test.mjs` holds that wait for the
first two sessions of a new process (`./run-tests.sh --all --fresh`), and
fails with the hand-over taken out. `test-utils.R` holds the two functions and
`test-ci.R` both ends of the wiring.

## I80 — Every session began by recounting Headcount's program menu

**Status:** resolved 2026-11-25 (branch `perf/session-start`).
**Found:** 2026-11-25, on production: a link to a Dept Dashboard that was in
the cache took 29.6 seconds; the dashboard's own load was 0.17.
**Severity:** high in effect: every session, on every page, waited about 10
seconds on production before the server answered anything, and a deep link's
run could not start until then.
**Affects:** `program_choices()` in `R/branches/population.R`,
`R/modules/headcount.R`, `R/modules/pathways.R`.

### What was wrong

Headcount's server fills its Major and Minor menus when a session starts,
whatever page the session opened (`observeEvent(input$college, …, ignoreInit =
FALSE)`). The labels say each program's degrees, campuses and years, and
`program_choices()` found each program's declaration rows with
`profile[major_code %in% covered, ]` inside a loop over about 250 programs: one
read of the whole declarations table per program. Pathways' server likewise
read the subject off every class-list row to list the subjects.

R answers one request at a time, so nothing else in the session ran until this
finished: not the page's own outputs, and not a link's restore and run.

### Evidence

Production, the same link (cache hit each time, 0.07 to 0.17 seconds of
calculation), `client_render_timing.csv` against the usage log:

| Session | Page there to ready | Session's first observer to the run |
|---|---|---|
| 2026-11-20 18:25 | 20.5 s | 12 s |
| 2026-11-23 12:39 | 12.8 s | 10 s |
| 2026-11-25 13:33 (first of the day, I81) | 29.6 s | 10 s |

Locally, a profile of one session's start (not the first of its process), 7.6
seconds sampled:

| Seconds | Where |
|---|---|
| 4.5 | Headcount's menus: 3.4 in `program_choices()`'s per-program lookup |
| 1.1 | the server function's own body (every module's set-up) |
| 0.6 | Pathways' subject list (`sub()` over every class-list row) |
| 0.3 | `course_picker_choices()` for a course picker |
| 1.1 | everything else |

### Reproduce (before the fix)

Open any page in a fresh browser session and time the websocket's `busy` to
`idle`: 7.6 to 8.3 seconds locally. Or change College on Headcount: about 4
seconds before the menus refill.

### Fix

`program_choices()` finds every program's rows in one pass (each code belongs
to one program, so the rows are split by it once); the labels are unchanged
(`test-pathways-helpers.R`, and the same labels on the full table before and
after). Headcount's choices for a scope are built once and shared by every
session (`cedar_shared_result()`). Pathways reads each course code's subject
once. A session's start is 2.3 seconds locally, and the link above is ready in
3.5 (was about 9).

What a session's start still costs, for a later pass: the server function's
body (1.0 s), Headcount's department list (0.2 s, a `distinct()` in the
module), a course picker's choices (0.3 s, `course_picker_choices()` over the
class list per session).

## I79 — A report whose conversion or read stopped part-way was stored as a smaller report

**Status:** resolved 2026-11-23 (branch `parser/short-read-is-an-error`), and
Fall 2025's holds reloaded the same day. What cut the conversion short on the
run that found it is not established (see Evidence).
**Found:** 2026-11-23, loading Student Holds for Fall 2019 to Fall 2026: Fall
2025 held 15,152 students where every other fall holds 23,700 to 27,600.
**Severity:** high where it happens: the term is stored without a third of its
students and reads as a quiet term. Seen once, on the development machine;
production's stored reports show no sign of it (see Evidence).
**Affects:** `R/data-parsers/parse-data.R`, every report.

### What is wrong

The parser converts each `.xlsx` to a CSV with `xlsx2csv` and reads the CSV
with `fread()`. Both steps took whatever they were given:

- **The conversion.** `system2(..., stdout = TRUE)` reports a converter that
  failed or was killed as a warning and a `status` attribute. The parser
  checked only that a non-empty file existed, and the lines a stopped
  converter had already written are one.
- **The read.** `fread()` warns and carries on when a line does not fit the
  table. It returns only the rows above a line with too many cells, drops a
  last line cut off inside a cell, and keeps a last line cut off after one as
  a row with its cells in the wrong columns. The parser did not look at the
  warnings, and each quotes the line it is about into the log: a person's row,
  name and unhashed ID included.

### Evidence

Fall 2025's export is sorted by ID and holds 300,138 holds for 26,890
students. The parse of 2026-11-23 stored 211,142 rows for 15,152 students:
exactly the export's first 211,142 rows (they hold 15,152 students, none of
whom has a row further down), which end 52.0 MB into a 74.1 MB CSV.

Fetched again and converted with nothing else running, the same export (28.8
MB both times) converts and reads whole, with no warning. So the CSV was short
on the first run, not the export. That parse ran beside a MyReports fetch on a
machine with 8 GB of memory, and Docker's virtual machine stopped minutes
later; the kernel log for the hour shows no process killed for memory, so the
cause is not known.

The size of each export against the rows stored from it shows the other 21
terms loaded that day at 98.7 to 101.5 bytes a row, and the short one at
143.1 (100.7 once whole). That rules out another cut of more than about 2%,
not a smaller one.

Production: none of the 441 refresh logs from 2026-03-09 to 2026-11-23 holds
an `fread` warning or a "had status" warning.

### Reproduce (before the fix)

```r
# A converter that stops part-way: a warning, and a file the parser accepted.
out <- system2("sh", c("-c", shQuote("printf 'a,b\\n1,2\\n' > part.csv; exit 1")),
               stdout = TRUE, stderr = TRUE)
attr(out, "status")      # 1; part.csv exists and is not empty

# A line with one cell too many: the row below it is not returned.
nrow(data.table::fread(text = 'ID,Name,Code\n1,"A, B",X\n2,C, D,Y\n3,"E, F",Z\n'))   # 1
```

### Fix

`convert_report_export()` stops when the converter does not exit 0 and
removes what it had written; `read_report_export()` stops on any warning from
the read, and repeats the warning only up to the row it quotes
(`R/data-parsers/report-specs.R`). Tests: "a conversion that stops part-way
stops the parse and leaves no unhashed file" and "an export the reader cannot
take as written stops the parse, and its row is not quoted"
(`test-report-specs.R`), on `holds_export_unreadable`.

Not covered: a converter that writes part of a sheet and still exits 0.

## I78 — The transform's status file lists only the tables of the last run

**Status:** resolved 2026-11-22 (branch `ingest/student-holds`).
**Found:** 2026-11-22, running the new `holds` stage alone.
**Severity:** low: no table is wrong. `scripts/data-status.sh` reads
`cedar-status.json` for its table of row counts and pull dates, and after any
run that built some tables it showed only those.
**Affects:** `write_cedar_status_file()` in
`R/data-parsers/transform-to-cedar.R`.

### Reproduce (before the fix)

```bash
Rscript --vanilla R/data-parsers/transform-to-cedar.R --tables degrees
scripts/data-status.sh      # lists cedar_degrees and the derived tables only
```

Every scheduled refresh names its stages, so the applicants table had been
missing from the listing since the default stopped asking for that report.

### Fix

The writer reads the file already there and keeps the entry of every table
this run did not build, as long as the table's file is still in the
directory; a table built again replaces its entry. A previous file that is
not valid JSON is replaced. Test: "a run that rebuilds some tables keeps the
others in the status file" (`test-transform-status.R`).

## I77 — The parser left each export unhashed beside its hashed file

**Status:** resolved 2026-11-23. Fixed in code 2026-11-22 (branch
`ingest/student-holds`, PR #388); the files already written are gone (see
The files already written).
**Found:** 2026-11-22, parsing the Student Holds report for the first time.
**Severity:** medium for privacy; no number is wrong. The parser drops names,
emails and addresses and hashes every ID before it saves a report, and the
file it converted the export into, with all of them, stayed next to the
result.
**Affects:** `R/data-parsers/parse-data.R`, every report, in every data
directory a parse has run in.

### What is wrong

`parse-data.R` converts each `.xlsx` to `<data_file>.csv` in the shared data
directory with `xlsx2csv`, reads it, and never removed it. The CSV is the
export as MyReports wrote it. Each parse overwrote the last, so the directory
held the most recent export of each report:

```
academic_studies.csv       15.6 MB   2026-10-08
admissions_applicants.csv  29.6 MB   2026-10-08
class_lists.csv           104.2 MB   2026-10-08
degrees.csv                 1.6 MB   2026-10-08
DESRs.csv                   4.8 MB   2026-10-08
```

That is the local shared data directory, which Dropbox syncs. Nothing reads
these files (`grep -rn "class_lists.csv"` finds only the line that writes
one).

### Reproduce (before the fix)

```bash
Rscript --vanilla R/data-parsers/parse-data.R -r deg
ls -la <shared data dir>/degrees.csv
```

### Fix

The CSV is removed as soon as it has been read, whether or not the read
worked, and the parse stops if it cannot be removed.

### The files already written

Gone on 2026-11-23. The five above were deleted from the local shared data
directory by hand. Production's (`/root/shared-data`) held four, and the
scheduled refresh of 2026-11-23, the first on the fixed parser, removed each
as it parsed that report. The directory also holds CSVs that are not exports
(`report_timing.csv`); those stay.

## I76 — Dept Trends raises a plotly "axis scaling" error in the browser

**Status:** resolved 2026-11-21 (branch `dept-trends/axis-scaling-i76`).
**Found:** 2026-11-21, running `./run-tests.sh --e2e dept-trends` for the
Courses Taken course list. The same run against production, on code without
that change, raises it too, so it predates it.
**Severity:** low to moderate: every step of the tour passes and the charts
checked are drawn, but one chart on the page fails to lay out, and the tour's
"no uncaught JS page errors" check fails, so the `dept-trends` scope cannot go
green.
**Affects:** some plotly figure opened by the Dept Trends tour
(`tests/e2e/reports-smoke.test.mjs`, scope `dept-trends`, department HIST,
campuses ABQ and EA). It fires as the Courses Taken sub-tab opens and again
as the reader leaves it for the next one, so it is one of that tab's figures;
which one is not yet known. Every figure on the tab is laid out with a
finite range afterwards, and the error's stack runs through a mouse-event
handler on a figure (`setScale` called from an SVG element's listener), so it
is likely a hover or drag on a figure being redrawn, not a failed first draw.

### Reproduce

`./run-tests.sh --e2e dept-trends` on the institutional app: the last check
reports `Error: Something went wrong with axis scaling`. CI does not see it:
it runs the synthetic `demo` tour, which passes.

### Cause and fix

The figure was Courses Taken's grid of outside courses
(`plot_major_course_units_course_history()`), for a campus with one or two
courses to draw (History on ABQ has one). The page gave it 110px plus 26px a
row; the colour scale beside the grid put its title above itself, which left
the scale's own axis no length, and plotly stopped the whole draw: the grid
showed as an empty frame. Redrawing the same figure in the browser with one
ingredient removed at a time found it: without the scale, or at 170px, it drew.

The scale's title now runs up its side, and a grid is never shorter than four
rows (`major_course_grid_height()`). Not the cause, though tried first: the
figure's margins, and a one-course axis order sent as a bare string.

## I75 — Graduation stayed blank for every session after a first visit to another page

**Status:** resolved 2026-11-21. Graduation first (PR #370), then both pages
moved to `cedar_shared_result()` (`R/modules/ui-helpers.R`), which stores only
a built result: never a failed `req()`, never a failed build.
**Found:** 2026-11-21, on production: clicking Bird's Eye > Graduation did
nothing, with no loading overlay and no error.
**Severity:** high: the page was blank for everyone until the next restart.
**Affects:** `graduationServer()` in `R/modules/graduation.R`.

### What was wrong

The page's build was a reactive bound to the app-wide cache
(`bindCache(..., cache = "app")`) with `req(isTRUE(active()), ...)` inside it.
A cached reactive stores a failed `req()` like any other result. The plan
picker's observer (added with the required-courses section) reads the build as
soon as a session starts, on whatever page it opens. So the first session after
a restart that opened anywhere but Graduation stored "not ready" under the
default inputs' key, and every later session, on the tab or not, was handed
that.

The browser test opens Graduation directly, so the first read always happened
with the tab open and the test passed.

### Reproduce (before the fix)

Restart the app; open the home page; then open Bird's Eye > Graduation with
the default inputs. Nothing is drawn and the session log shows no build.

### Fix

Graduation's and Retention's shared results are read through
`cedar_shared_result()` inside a plain reactive, after its `req()`. A build that
fails returns NULL to the session that asked and is not stored, so the next
read tries again. No module binds a reactive to the app-wide cache with a
`req()` inside, and `test-architecture.R` fails on one.

Why no test caught it: every `./run-tests.sh --e2e` run begins with a warm-up
session on the home page, which is the condition, but the suites were run
directly with `node` after a rebuild, and CI's tour (`demo`) did not open
either page. The tour now opens Graduation and Retention in a session that
began on the home page (`reports-smoke.test.mjs`, smoke scope, so CI's fresh
app runs it on every PR). Confirmed by putting the fault back: the step fails.
Its first CI run found a second fault on the synthetic institution: with no
plan to show, Graduation's plan picker built a one-label list for zero plans,
the observer errored and the session dropped. Fixed with an empty list.

## I74 — The newest transfer class's "credits brought" band is tilted by who stayed

**Status:** resolved 2026-11-22 (branch `audit/degree-rule-and-transfer-bands`).
**Found:** 2026-11-21, reading the first real-data run of the transfer classes.
**Severity:** moderate: one class's bars are misleading in each band; older
classes look consistent with one another.
**Affects:** `get_entering_class_retention(opt$arrival_credits)` and so
`build_graduation_dashboard()$transfer`; the source is
`build_credit_timeline()`'s `transfer_credits`.

### What is wrong

A transfer student's credits brought are `overall_credits_attempted -
inst_credits_attempted`, read off rows stamped at each pull. For the Fall 2025
transfer class (ABQ undergraduates), read a year on, the band that brought
under 30 credits shows more than twice the not-enrolled share of the five
classes before it, and the 30-to-59 band shows about half of theirs; the
earlier classes agree with one another within a few points. A class does not
differ that much by band from one year to the next.

The likely cause: a student who left before their transfer credit was posted
has only early stamps, with little or no credit brought, and lands in the
lowest band; a student who stayed has later stamps with the credit posted.
Older classes were all covered by a later full historical pull, so their bands
do not sort by who stayed.

### Reproduce

`build_graduation_dashboard()` on the shared data, undergraduates, ABQ; print
`format_graduation_pace()` for each element of `$transfer` and compare the
newest class's "Gone" share at the start of the second year with the classes
before it, band by band.

### Cause and fix

Not who stayed, but who has a record at all. `build_credit_timeline()` read a
student with no recorded pair of totals as having brought zero credits. A new
student's first pull carries no totals; a later pull fills them in; a student
who has left is not pulled again. So the newest class's leavers were "brought
none" and filled the lowest band, and the in-progress class was nearly all
there.

`build_credit_timeline()` now returns `transfer_credits_known`.
`get_entering_class_retention(opt$arrival_credits)` puts a student without a
record in no band and counts them (`n_arrival_unknown`), and
`get_credit_ceiling_crossings()` counts them as not readable. The page says how
many.

## I73 — Special topics ("ST:") titles were not treated as topics courses

**Status:** resolved 2026-11-20.
**Found:** 2026-11-20, by a reader, on a class crosslisted under "T:" and
"ST:" titles.
**Severity:** moderate: a special-topics number's sections under different
titles were read as one course, so a topic's low-enrollment history, its
enrollment trend and the dashboard's topics cards mixed unrelated topics.
**Cause:** the test was the literal `^T:`, written in the transform
(`is_topics`) and in four readers.
**Evidence:** sections whose title opens "ST:" carried `is_topics = FALSE`.
**Fix:** `settings.csv` `topics_title_labels` (UNM: `T:|ST:`) and one test,
`is_topics_course()` (`R/lists/topic_titles.R`), called by the transform and
every reader. `CEDAR_FACT_SCHEMA_VERSIONS` sections 3.
**Guard:** `test-topic-titles.R`. "Sel T:" and "Adv T:" (selected and
advanced topics) joined the list the same day, confirmed by the user;
sections 4.

## I72 — The Enrollment table counted a crosslisted offering by its home listing alone

**Status:** resolved 2026-11-20.
**Found:** 2026-11-20, by a reader: a topics course taught as one class under
four departments' codes showed its home department's students only.
**Severity:** high for crosslisted courses: Census and Final understate the
class by the partners' students, so a healthy shared class looks
under-enrolled and falls under a Census Max filter.
**Cause:** `attach_enrollment_section_counts()` (added with the class-list
counts, #323) joined counts to a row by its own `(term, crn)`. The Home,
Crosslisted and Split-level views drop the partner rows, so their students
appeared nowhere; a department filter also keeps the partners off the page.
**Evidence:** the home row's class-list counts were below its own
crosslist-combined schedule total (`total_enrl`).
**Reproduction:** EC-15 (`test_sections_xl_switch`): MATH 3750 is home to a
section shared with CS 3750. Filtered to MATH, the home row counted 5
registered against a combined total of 9.
**Fix:** the primary row also carries the offering's counts (`xl_*`): every
offered listing of its crosslist group, read from the whole schedule and
counted as the Course Report counts a family, each student once by
`STATUS_PRECEDENCE`. `summarize_enrollment_view()` reads them in the views
that show the offering once; Away and All keep each listing's own count.
**Guard:** `test-enrollment.R`, "a crosslisted offering's home row counts
every listing's students once (EC-15)".

## I71 — Regstats "Worth a look" stops on a topics course waitlisted under two titles

**Status:** resolved 2026-11-20.
**Found:** 2026-11-19, running Regstats for Spring 2027.
**Severity:** moderate: the whole "Worth a look" list is replaced by an error
for the term; the screens' own tables still render.
**Cause:** `get_reg_stats()` counts waitlist demand at the Waitlists grain,
which includes `course_title`, so a topics course with waiting students under
two titles has two `waits` rows. `build_registration_watch()` keys every
screen on term, campus, college, course and part of term and stops on a
repeated key.
**Evidence:** the page showed "Worth a look could not be built:
[registration-watch.R] flagged$waits repeats a term, campus, college, course
and part of term" for an Honors topics course on ABQ.
**Reproduction:** `watch_topic_regstats` (`fixtures/scenario_tables.R`): three
students wait for SOCI 104, one of them under both of two titles.
`build_registration_watch()` over it stopped with the message above.
**Fix:** `get_reg_stats()` also returns `waits_by_course`, the same true
waitlist rows counted by course with each student once, and the watch reads
that. Summing the titled rows would count a student waiting for two titles
twice. `cedar_regstats_cache_version` 10 so a saved run without the table is
recomputed. A student registered in one title and waiting for another is
still waiting, as on Waitlists.
**Guard:** `test-registration-watch.R`, "a topics course waiting under two
titles is one watch row, each student once".

## I70 — Production mrgather crashes instead of retrying a failed download

**Status:** resolved 2026-11-20.
**Found:** 2026-11-19, explaining a gap in the registration snapshots.
**Severity:** moderate: one failed download ends the whole fetch, and the
reports after it are not pulled that day. The refresh then runs on the
previous day's files for those reports (I33's per-report judgement keeps it
honest: the summary lists each missing report).
**Cause:** production's `mrgather-mrgather:latest` image was built on
2026-04-10 from a `mrgather.js` whose retry path calls
`tracker.recordReportFetchError()` and a `reportTracker.js` that does not
define it. The current source defines it (`reportTracker.js`), so the image
and the source disagree.
**Evidence:** `/var/log/cedar-update-20261113_100501.log`: "Fatal error during
report gathering: TypeError: tracker.recordReportFetchError is not a function"
during the Academic Studies fetch; the class list was not downloaded, and the
registration snapshot that day paired the 2026-11-12 class list with the
2026-11-13 schedule.
**Reproduction:** on the server, `docker run --rm --entrypoint sh
mrgather-mrgather:latest -c "grep -c recordReportFetchError /app/*.js"`:
`mrgather.js` 1, `reportTracker.js` 0.
**Fix:** the server's own source carried the old `reportTracker.js` too, so
a rebuild from it would not have helped, and a full rebuild reinstalled
Chrome (146 to 158) under the login automation. The image was instead built
`FROM` the April image with only the current `reportTracker.js` copied in,
so Chrome and `mrgather.js` are unchanged; the new file adds the method and
a fetch-error section to the run summary and nothing else. The April image
is kept as `mrgather-mrgather:pre-i70` and the old file as
`/root/mrgather/reportTracker.js.pre-i70`. Checked in the new image:
Chrome 146, and `recordReportFetchError()` records an error when called.

## I69 — The nightly Dept Dashboard warm failed every department since the measure tables

**Status:** resolved 2026-11-19.
**Found:** 2026-11-19, reading the refresh logs for the registration snapshots.
**Severity:** moderate: no wrong number, but every chair's dashboard was built
on their first visit each day instead of read from the morning cache, and the
refresh summary showed the step ⚠️ for twelve days unnoticed.
**Cause:** `scripts/warm-dept-dashboard-cache.R` kept its own copy of
global.R's loading. When the measure tables arrived (ADR-001 step 6,
2026-11-08) the dashboard's Registration flags began to read
`cedar_course_terms`, which the script never loaded: every department stopped
with "get_reg_stats(): course_terms (cedar_course_terms, as the loader holds
it) is required."
**Evidence:** `/var/log/cedar-update-2026110[8-9]*` onward: "warm dashboard
cache ⚠️ exit 1"; 2026-11-07 and earlier ✅.
**Fix:** `load_measure_tables()` (`R/branches/measure-tables.R`) and
`cedar_table_cache_hashes()` (`R/trunk/cache.R`) are the one way to load the
measure tables and to hash the tables for cache keys; global.R and the warm
script both call them, and the script loads every table the dashboard reads.
A real-data run warmed a department and the app then loaded that cache
instead of rebuilding it. Tests: `test-transform-measures.R`, `test-cache.R`.

## I68 — The compiled Computer Science board plans Composition I twice

**Status:** open.
**Found:** 2026-11-19, rewriting the Degree Explorer browser suite (I65).
**Severity:** moderate, Degree Explorer only: the CS plan carries 3 credits of
Composition I it does not need, and a student reading it sees two first-year
composition courses.
**Cause:** every board gets the English route's tiles (`engl1` ENGL 1110,
`engl2` ENGL 1120) from the student's starting point; the compiled CS reading
also lists Composition I as a program requirement, "Composition I: ENGL1110Y,
ENGL1110Z or ENGL1110", which `assemble_compiled_degree_board()` places as its
own choice tile (`composition_one_1`, semester 2). Nothing recognises that the
route already holds it.
**Reproduction:** Degree Explorer, Computer Science B.S., any starting point:
`engl1` in semester 1 and `composition_one_1` in semester 2
(`institution/unm/degree_drafts/degree_roadmap_nodes.csv`, `cs-bs-2026`).
**Fix:** a compiled choice whose options are all English-route courses is the
route's tile, not another one.

## I67 — A compiled Business board plans its writing choice before Composition II

**Status:** open.
**Found:** 2026-11-19, rewriting the Degree Explorer browser suite (I65); the
hand board it replaced held this course after Composition II.
**Severity:** moderate, Degree Explorer only: with stretch English (ENGL
1110X, 1110Y, then 1120 in semester 3) the plan puts ENGL 2120 or 2210 in
semester 2, a term before its prerequisite.
**Cause:** the compiled tile `writing_1` ("3 credits: ENGL2120 or ENGL2210")
is a choice; the compiler links a named course to its prerequisites but gives
a choice none, even when every option has the same one (ENGL 1120). No
`degree_roadmap_links.csv` row reaches `writing_1`.
**Reproduction:** `?tab=degree-explorer&catalog_id=business-bba-2026&math_start=algebra&english_start=stretch`:
`engl2` in semester 3, `writing_1` in semester 2.
**Fix:** link a choice tile to a prerequisite all its options share.

## I66 — Opening a Downstream subtab reruns the analysis At a Glance already ran

**Status:** resolved 2026-11-19. The four run keys read
`cedar_click_count()` (`R/modules/ui-helpers.R`), a button's count as a
plain integer; `tests/e2e/downstream-glance.test.mjs` records every progress
notification after At a Glance settles and fails on a second run.
**Found:** 2026-11-19, reported by the user: "the course dynamics downstream
tab seems to compute everything on that click, and then again when i click
its subtabs."
**Severity:** moderate, Course Dynamics > Downstream only: no number was
wrong, but each subtab repeated a run of tens of seconds.
**Cause:** At a Glance runs Against Non-Takers, Next Courses and Prepared for
It on their defaults before their subtabs have rendered, with a run key of
`input$<update button> %||% 0L`, so `0L`. Opening a subtab renders its
Update button, whose value is Shiny's `0` with class
`shinyActionButtonValue`; `identical(0L, <that 0>)` is `FALSE`, so the key
changed and the observer ran the view again (`courseCohortServer()`,
`laterCourseServer()`, and Prepared for It's and Coming Back's observers in
`server.R`). Coming Back ran twice for the same reason on its own subtab.
**Reproduction:** in R, `identical(list("X", 0L), list("X",
structure(0L, class = c("shinyActionButtonValue", "integer"))))` is
`FALSE`. In the app, Course Dynamics with HIST 1110, Downstream, wait for At a
Glance, then open Against Non-Takers: its progress notification shows again.
The browser check counted 2 reruns before the fix and 0 after.

## I65 — The Degree Explorer browser suite checks the hand-built boards the compiled drafts replaced

**Status:** resolved 2026-11-19. The suite names the compiled tiles (`cs_361l`,
`csci_2310`, `science_1`, `cs_481`, `hist_491`, `upper_electives_*`, `asian_1`,
`knowledge_1`, `logic_1`, `busa_4988`, `communication_elective_1`) and the
compiled boards' wording, and asserts I64: Philosophy's two 400-level
electives start in semester 6 or later. Running it found the compiled
boards' draft badge widening the page at phone width (fixed in
`www/cedar-roadmap.css`), I67 and I68.
**Found:** 2026-11-18, running the suite for I64.
**Severity:** moderate, tests only: the page is not broken, but its browser
suite has guarded nothing past its first three checks since 2026-11-16.
**Cause:** #309 (degree compiler step 3) put each compiled draft in place of
the hand-built board with the same catalog id. The suite (last changed
2026-11-15) still names the hand boards' tiles: `java1`, `java2`,
`computing0`, `os` (CS), `buscapstone` (Business), `historiography` (History),
`philbuddhist`, `philknowledge`, `phillogic` (Philosophy). The compiled boards
name tiles by rule (`intro_1`, `elective_upper_1`).
**Reproduction:** `node tests/e2e/degree-explorer.test.mjs` against any app
built since #309: three checks pass, then `No element found for selector:
[data-node="java1"]`.
**Fix:** point the CS, Business, History and Philosophy checks at the compiled
tiles (or at a hand-built board that is still shown, such as Physics or
Biology), and assert I64's placement there: Philosophy's `elective_upper_*`
in semester 5 or later.

## I64 — A compiled degree board plans 400-level electives in the first semester

**Status:** resolved 2026-11-18. The reading schema (1.1.0) gives a node an
optional, cited `minimum_course_number`; the compiler places a slot in the band
of that number, else at its group's level. Philosophy and History v2 readings
state 400 and 300 on their 400–499 and HIST 300–499 pools (packets re-prepared
under the new schema; v1 kept). At the user's request every plan also gained
`senior_level_from_semester` (6): a tile whose courses are all 400-level, or a
400-level pool, starts no earlier. The recompiled Philosophy board starts its
two 400-level tiles in semester 6; on the authored boards Population Health's
POPH 420, Chemistry's instrumental analysis and Biochemistry's BIOC 445 move
from 5 to 6. No plan grows a semester. The Philosophy reading's "Four Philosophy electives, two at
the 400 level" is split, at the user's direction, into two 400-level electives
(semester 6) and two at any level; whether those four restate the two credit
pools is still the reading's unresolved `elective-overlap`.
**Found:** 2026-11-18, from the user's to-do list ("Degree Explorer puts
upper-level electives too early"), by building every board.
**Severity:** moderate, Degree Explorer only. The compiled Philosophy B.A.
board (`institution/unm/degree_drafts/degree_roadmap_nodes.csv`) gives
`elective_upper_1` and `elective_upper_2` ("At least 6 elective credits at the
400–499 level") and `elective_count_1`–`_4` ("Four Philosophy electives, two
at the 400 level") `course_level = lower` and semester 1, against the plan's
upper-level boundary of semester 5. A student reading the board sees 400-level
work planned for their first term.
**Cause:** `assemble_compiled_degree_board()` gives an elective slot the level
of its group: upper only when every course the group requires is upper
(`R/branches/degree-compiler-board.R`, the `role == "slot"` branch). The
Philosophy major group requires PHIL 1115 and others below 300, so its slots
read lower. History's "18 credits in HIST300–499" reads upper only because
every course its group requires happens to be upper. The level is stated only
in the catalog text the reading cites ("Earned at least 6 credits from 400 -
499"); the reading schema (`config/catalog-normalization.schema.json`) has no
field for a pool's level, and a label is never parsed for one.
**Reproduction:** `Rscript --vanilla scripts/compile-degree-interpretations.R`
(or read the committed draft nodes file): the Philosophy rows above carry
`course_level = lower`, `semester = 1`. The hand-authored boards are not
affected the same way: their elective tiles carry an authored `course_level`,
and the early ones say so (Anthropology's "Select an eligible lower-level
course for this early slot").

## I63 — The online Psychology pre-major leads to the campus major, not the online one

**Status:** resolved 2026-11-16: `programs.csv` gives XFPY `leads_to =
XPSY`, PSY and XPSY being separate programs at UNM; FHIL, which led nowhere,
leads to HILA.
**Found:** 2026-11-16, comparing Pathways populations before and after I62.
**Severity:** moderate for Psychology only. `programs.csv` gives XFPY (the
accelerated-online Psychology pre-major) `leads_to = PSY`. Its students
declare XPSY, the online major. Since populations keep same-named programs
apart (I62), a PSY population counts an XFPY student who declared XPSY as
"chose elsewhere": 364 of the 615 such students in a PSY population on the
2026-11-16 tables, against 251 before. An XPSY population misses its own
pre-majors.
**Reproduction:** `build_population(cedar_programs, cedar_degrees,
cedar_student_terms, opt = list(type = "major", program_codes = "PSY",
outcomes = c("chose_elsewhere")))`, then count the declared `major_code` of
those students in `cedar_programs`: XPSY 364, NURS 33.
**Fix:** a mapping edit, no code. Of XFPY's 704 students, 360 later declared
XPSY and 57 PSY. XFBA, the other online pre-major, already led to its online
major (XBAD).

## I62 — A Pathways population counted every program that shared a name

**Status:** resolved 2026-11-16.
**Found:** 2026-11-16, asked why the Pathways Majors list holds many spellings
of Liberal Arts.
**Severity:** high for the programs affected. The Majors list offered Banner's
raw program names (234 names over 360 codes; 93 names cover more than one
code), and `build_population()` matched `major_code %in% codes | program_name
%in% names` in every detector, graduation included. On the 2026-11-16 tables:
department BIOL counted 7,303 students where 5,855 hold its own codes, because
CHBI is named "Biochemistry" and pulled in the BIOC unit's Biochemistry
students (BIOC 810, FBIC 1,063); department MGMT took in 45 students of
same-named programs elsewhere; the "Architecture" major merged ARCH and ARCT
(1,655 students where ARCH holds 640); "Liberal Arts" held LIBA and FLIB but
not LAIS and FLAI, which replaced them in Fall 2023, so it read 7 ongoing
students instead of 411; "Psychology" merged PSY with the online XPSY (149
students). The History major and the HIST, ARCH, PSYC, NURS, ENGL and CHEM
departments were unchanged.
**Cause:** the selector and `get_focal_programs()` treated a program name as
an identity; the confirmed program renames had nowhere to live.
**Reproduction:** before the fix, `build_population(cedar_programs,
cedar_degrees, cedar_student_terms, opt = list(type = "dept", dept_code =
"BIOL"))` returned 7,303 students; 1,448 of them hold no BIOL-owned code.
**Fix:** a population selects codes (`resolve_focal_programs()`): the major
type takes `program_codes`, a department its own codes and pre-majors, a
preset its names resolved to codes once; confirmed `kind = program` rows in
`code_history.csv` join a renamed program's codes (`program_successions`; LIBA
to LAIS and FLIB to FLAI confirmed 2026-11-16); degrees match by `major_code`.
The Majors list is one choice per program, named from `programs.csv`, and the
scope bar lists every code counted, each rename and each pre-major. Major
Changes no longer counts a rename as a change. Tests in `test-population.R`,
`test-population-outcomes.R`, `test-pathways-helpers.R` and
`test-pathways-integration.R` fail with name matching or without the renames.

## I61 — Summer 2025 holds NR grades where Summer 2024 held none, and reads as a DFW spike

**Status:** open. Recorded on the DFW dashboard (Bird's Eye > DFW), which names
a term whose NR grades are 1% or more of its attempts; nothing is corrected.
**Found:** 2026-11-15, while sizing the DFW dashboard on the 2026-11-15 tables.
**Severity:** moderate. Summer 2025's DFW rate, every level, reads 22.5%
against 12.4–15.5% for every other summer, and any summer series, course DFW
rate or GPA that reads that term carries it. Fall and Spring are barely
touched (31 to 223 NR a term since Fall 2024).
**Affects:** every grade reader over Summer 2025 (`cedar_attempts` classifies
NR as DFW under the default policy, as it should for a grade that was never
posted).
**Cause (suspected):** the Summer 2025 class list was pulled before its
grades were rolled. It holds 1,479 NR ("not reported") grades in 336 of its
1,291 sections (265 of those sections are NR for every student), where
Summer 2024 held none; and only 86 PR (thesis in progress) grades, where
every other summer held 182–249, as if NR stood in for grades yet to post.
NR first appears in Fall 2024 (31), and every term since has some. A re-pull
of Summer 2025's class list would settle it.

### Reproduction

On the loaded tables: `cedar_attempts %>% dplyr::filter(final_grade %in%
c("NR", "PR")) %>% dplyr::count(term, final_grade)` shows NR 1,479 and PR 86
in 202560, NR absent and PR 243 in 202460. The DFW rate by term,
`summarize_attempt_outcomes(attempt_outcome_flags(cedar_attempts), "term")`,
reads 22.50% for 202560 and 12.97% for 202460.

## I60 — Takers vs Non-Takers opens on a classification its home-campus scope hardly holds

**Status:** resolved 2026-11-13 (#287). `course_cohort_context_defaults()`
reads the opening term type, classification, level and college off the takers
whose home campus is in the scope the page opens on; when no taker's home
campus is in the page's selection the page opens on every home campus, which
its Home campus control shows. HIST 1110 on an ABQ and online page now opens
on first-semester freshmen, and on Concurrent Enrollment on a Valencia page.
The test in `test-course-cohort-context.R` states SPAN 101's two GA takers as
concurrent-enrollment students; on the old rule it failed twice (a GA page
opened on Freshman, and a selection with no taker's home campus kept it).
**Found:** 2026-11-13, in the browser test's screenshot of HIST 1110 (ABQ and
EA) while moving the tab under Retention (#286); confirmed on the 2026-11-13
tables.
**Severity:** moderate. The page opens on a comparison with almost no takers
in it, and the gap rows read "—" for nearly every term. Nothing it shows is
wrong; the default question is the wrong one, and a reader has to know to
change the classification.
**Affects:** `course_cohort_context_defaults()` in
`R/features/course-cohort-context.R`.
**Cause:** the opening classification, level and benchmark college were the
modes of the course's takers on every home campus, while the opening home
campus is the page's campus selection. For HIST 1110 the commonest
classification of its Fall takers across UNM is Concurrent Enrollment, and
nearly all of those students are dual-credit students at two branch campuses,
taught there. Among takers whose home campus is ABQ, Concurrent Enrollment is
almost absent and first-semester freshmen and sophomores are the commonest.
The page opens on ABQ Concurrent Enrollment students, few of whom took the
course. A course whose branch-campus enrollment outweighs its main-campus one
in one classification has the same shape.

### Reproduction

Before the fix, Course Dynamics, HIST 1110, campus ABQ and EA, Analyze Course, then Retention >
Takers vs Non-Takers: Classification opens on "Concurrent Enrollment" and Home
campus on ABQ, and the "Passed, DFW'd, Never Took It" table has no passed or
DFW'd students in nearly every Fall. On the loaded tables:
`course_cohort_context_defaults("HIST 1110", cedar_student_terms,
cedar_attempts, edges, list(campus = c("ABQ", "EA")))` returns
`classification = "Concurrent Enrollment"` and `campus = "ABQ"`, while among
the Fall takers whose `student_campus` is ABQ, first-semester freshmen and
sophomores are the commonest and Concurrent Enrollment is almost absent.

## I59 — The DFW tab's DFW by Term table stopped with an error for every course

**Status:** resolved 2026-11-13 (#285). The DFW tab's sections read one
options builder, `cr_dfw_opt()` in `server.R`, which carries the course's
scope, the grade rule, the graded edge and the campus filter, so no section
can leave the edge out. `tests/e2e/course-dynamics-deeplink.test.mjs` opens
the DFW tab and fails on any section that shows an error; against the app
before the fix it failed with this one.
**Found:** 2026-11-13, reported on production: "an error has occured for the
dfw by term section".
**Severity:** moderate. For every course since 2026-10-16, the DFW by Term
section showed Shiny's "An error has occurred" in place of the term table
and the note on excluded registration statuses. The chart above it and the
other sections were right; no number was wrong, one table was missing.
**Affects:** `cr_dfw_status_exclusions_reactive` in `server.R`.
**Cause:** #143 (2026-10-16, M12) made the graded edge a parameter of the
course-attempts branch: `course_attempt_term_window()` stops without
`opt$data_edges`, so no path reads a grade past `last_graded`. Three of the
DFW tab's reactives were given the edge; the status-exclusion summary
(`summarize_outcome_status_exclusions()`, called by the DFW by Term section)
was passed the course's `opt` without it. Module code is not loaded by the R
suite, and no browser test opened the DFW tab.

### Reproduction

Before the fix, Course Dynamics, any course (CHEM 1215L, ABQ and EA), DFW
tab: the DFW by Term section reads "An error has occurred". The worker's log:
`Error in : [course-attempts.R] opt$data_edges (cedar_data_edges() output) is
required to bound grade-based outcomes at the graded edge`, from
`summarize_outcome_status_exclusions` in `cr_dfw_status_exclusions_reactive`.

## I58 — Courses Taken calls a term in progress in its charts and settled in its tables

**Status:** resolved 2026-11-13 (#284). One definition, `cedar_term_in_progress()`
(`R/branches/data-edges.R`): a term after `last_graded`, at or before
`last_enrolled`, settled or not. `cedar_in_progress_terms()`, which the
charts' shading reads, filters on it, and so do the cone's `in_progress`
and the payload's `meta$latest_in_progress`; the cone refuses edges that do
not name `last_graded`. The note's in-progress line now says the grades have
not posted and the registrations can still change. `test-dept-report.R`
(edges settled past the graded edge) and `test-major-course-units.R`
(`rw01_settled_ungraded_edges`) fail with the old rule restored.
**Found:** 2026-11-13, looking at Dept Trends > Courses Taken for History
(ABQ, EA) on the local institutional app, after #282.
**Severity:** low. No count is wrong; one page labels the same term two ways,
and the reader cannot tell whether Fall 2026's registrations are final.
**Affects:** `get_major_course_units()` (`R/cones/major-course-units.R`),
`compute_dept_course_units_tab()` (`R/features/dept-trends.R`) and the
Courses Taken page (`R/modules/dept-trends.R`).

### What is wrong

The page reads two definitions of "in progress":

- **The charts** shade every term after `last_graded`, to `last_enrolled`
  (`cedar_in_progress_terms()`, `R/modules/dept-trends.R:75`, drawn by
  `mark_plotly_terms()`), as the right-edge policy says a descriptive
  current-registration chart must. The outside-course table's column headings
  read the same terms (`R/modules/dept-trends.R:595`).
- **The tables and the words** read the cone's `in_progress`, which is
  `term > last_enrolled_complete` (`R/cones/major-course-units.R:177`), and
  the payload's `meta$latest_in_progress` built the same way
  (`R/features/dept-trends.R:939`). The own-share table's In progress column,
  the "Teaching Units, <term>" heading (`R/modules/dept-trends.R:483`) and the
  in-progress line of "Who is being counted" (`:509`) follow it.

Whenever a term is settled but not graded (each regular term, from the day it
settles until its grades post), the two disagree. On the Oct 8 pull the edges
are `last_enrolled` 202680, `last_enrolled_complete` 202680 and `last_graded`
202660: every over-time chart shades Fall 2026 "In progress", while its row in
the own-share table is blank in In progress, the heading reads "Teaching
Units, Fall 2026" with no "(in progress)", and the note leaves out the
in-progress line.

### Reproduction

On `shared-data` (`scripts/cedar-repl.R` with `cedar_data_dir` set to it;
edges from `cedar_report_edges()`):
`cedar_in_progress_terms(edges)$term` is `202680`, while
`compute_dept_course_units_tab(list(dept_code = "HIST", dept_name = "History"), data_objects)`
gives `meta$latest_in_progress` FALSE and no `own_share` row with
`in_progress` TRUE. In the app: Dept Trends, History, Courses Taken.

### Done when

Every in-progress label on the page reads one definition, the terms after
`last_graded` that the charts shade, and a test on the fixtures sets edges
with the settled edge later than the graded edge and finds the latest term
labelled in progress in the table, the heading and the note. The cone's own
`in_progress` (past the settled edge) either goes or is renamed for what it
is, so no reader takes it for the page's label.

## I57 — The Instructor Patterns column guide states a pass rule CEDAR does not use

**Status:** resolved 2026-11-13 (#280). The Instructor Patterns tab and its
column guide are removed. The breakdown by instructor is a section of
Downstream > Later Course, which states no pass rule of its own: the shared
`downstream-outcomes` definition gives the rule (A+ through C, and CR), and
the page's words are covered by snapshots
(`tests/testthat/_snaps/later-course.md`).
**Found:** 2026-10-29, auditing the Course Report's Downstream tab on the
branch `course-dynamics/downstream`, which fixed it there and was never
merged; confirmed still on `main` 2026-11-12.
**Severity:** low. The numbers use the canonical classifier; the words beside
them do not describe it.
**Affects:** the Instructor Patterns column guide, `server.R`.

### What is wrong

The column guide says "Passing is C− or better, CR, P, or S; Failed is a
canonical D/F/W grade". CEDAR's default passes A+ through C and CR only; C−,
P and S are DFW (AGENTS.md, Grades and the DFW policy). The table beside the
sentence follows the default: `get_instructor_effect()` counts the stored
`outcome_category` of `cedar_attempts`. A reader comparing the page with the
DFW tab would conclude the two count differently.

### Reproduction

`grep -n "C− or better" server.R` (line 4804 at `2317b0c`).

### Done when

The page states no pass rule of its own: the sentence says A+ through C or CR,
or gives the shared definition through `cedar_definition_note()`, and the
page's words are covered by a snapshot.

## I56 — Downstream continuation misses every later enrollment after the grade edge

**Status:** resolved 2026-11-13 (#280). Confirmed on `shared-data` the same
day, before the fix, with the check below: first X in Spring 2026 and Y in
Fall 2026, counted as not continuing, CHEM 1215 → 1225, 183 of 557;
MATH 1512 → 1522, 67 of 185; ENGL 1110 → 1120, 85 of 167. The fix is one
cohort definition, `build_downstream_cohort()`
(`R/branches/downstream-cohort.R`), behind the picker, the outcomes and the
instructor balance check: enrollment in Y is read off the class list to the
settled edge and grades off `cedar_attempts` to the graded edge, Y counts
inside a fixed window of regular terms (default 3), and every table is grouped
by the campus that taught X. `get_instructor_effect()` and
`get_downstream_pair_audit()` are removed. DS01's `DS_E1` row expresses the
case, and `test-later-course.R` fails (22 expectations) with the graded-edge
filter restored.
**Found:** 2026-10-29, auditing the Course Report's Downstream tab on the
branch `course-dynamics/downstream` (two local commits, never merged). The
branch fixed it against the tables of the time and cannot be merged now: 16 of
its 24 files conflict with `main`. It is the specification of the fix.
**Severity:** high. The continuation rate, the later-course picker's
percentages and every instructor row undercount, most for the most recent
students.
**Affects:** `get_instructor_effect()` (`R/cones/course-instructor-effect.R`),
`get_downstream_pair_audit()` and `get_downstream_course_options()`
(`R/branches/course-flows.R`).

### What is wrong

**The later course (Y) is read to the graded edge, and eligibility to the
settled edge.** In `get_downstream_pair_audit()` a student of the first course
(X) is in the denominator when their first follow-up term is at or before
`edge$observation_end`, but Y rows are kept only where
`term <= edge$grade_end`. `get_instructor_effect()` does the same: `took_y`
comes from `cedar_attempts`, which stops at `last_graded`, while
`right_censored` compares with the settled edge. Whenever the settled edge is
later than the graded edge (each regular term, from the day it settles until
its grades post), a student whose first X was in the last graded regular term had a
full follow-up and counts in the denominator, and their enrollment in Y in the
settled term is never seen. They count as not continuing.

The branch found two more things in the same denominator:

- **No follow-up window.** Y counts in any later term, so a 2019 student has
  seven years to take Y and a 2025 student one, and the pooled rate mixes both.
- **Campuses pooled.** The headline is one number across the selected
  campuses, and Y is read only on those campuses. The pooling carries a
  `CAMPUS_ROLLUP` comment; the branch grouped every table by the campus that
  taught X instead.

### How to check

Measured 2026-10-29 on `shared-data`, campuses ABQ + EA. First X attempt in
Spring 2026, Y in Fall 2026, all counted as not continuing: CHEM 1215 → 1225,
183 of 557; MATH 1512 → 1522, 66 of 185; ENGL 1110 → 1120, 85 of 167.

To check on today's tables (`scripts/cedar-repl.R`): for one pair, count the
students whose first registered X is in the last graded regular term and who
hold a registered Y row in the next regular term, at or before
`last_enrolled_complete`, in `cedar_registrations`. The audit counts none of
them as taking Y while it keeps Y rows only to `edge$grade_end`
(`R/branches/course-flows.R:535`).

### Done when

Enrollment in Y counts through the settled edge, and a Y taken after the graded
edge counts as taken, not yet graded; grade outcomes still stop at the graded
edge. A fixture row expresses the case and its test fails with the graded-edge
filter restored. The branch's `build_downstream_cohort()` and its DS01 fixture
are the worked design: a fixed window of regular terms after X (default 3),
and every table grouped by the campus that taught X.

## I55 — The instructor-gate password stopped reaching the app

**Status:** fixed in code 2026-11-12; in effect on production once
`CEDAR_DFW_PASSWORD` is set in the host's `.env` and the app is deployed.
**Found:** 2026-11-12, on production: every instructor gate read
"CEDAR_DFW_PASSWORD is not configured", where the password had worked before.
**Severity:** moderate. Nothing wrong was shown: the gate fails closed. But
no one could open instructor-level results, and since #267 (2026-11-11) put
instructor names behind the gate everywhere, that is every by-instructor
table.
**Cause:** the app reads the password with `Sys.getenv()` in the Shiny worker.
The install guide said to set it in `.Renviron`, and it reached the app only
because the image build copied the checkout's `.Renviron` into the app
directory. Commit `0b8ccd1` (2026-09-05) added `.Renviron` and `.env` to
`.dockerignore`, rightly, and dropped the variable from the install guide;
`docker-compose.yml` passed no environment to the app, so from the next image
the variable was unset. Passing it to the container is not enough either:
shiny-server starts its R worker with a clean environment (`HOME`, `PATH`,
`LANG` and R's own). That production set it in `.Renviron` is inferred from
the guide and the history, not read off the host.
**Reproduction:** `docker exec cedar-shiny sh -c 'tr "\0" "\n" <
/proc/$(pgrep -f exec/R | head -1)/environ | cut -d= -f1'` lists the worker's
variables: no `CEDAR_*` among them, whatever the container was given.
**Fix:** `docker-compose.yml` passes `CEDAR_DFW_PASSWORD` from `.env` to the
app container, and `entrypoint.sh` writes it to the worker's user `.Renviron`
(mode 600, rewritten at every start, single-quoted so the value is literal; a
password holding a single quote or a line break stops the container with the
reason). Checked on the local institutional app with a password holding `$`,
`#`, a space and double quotes: `./run-tests.sh --e2e retention` with
`CEDAR_E2E_INSTRUCTOR_PASSWORD` set unlocked the instructor breakout.
`test-ci.R` pins the hand-off.

## I54 — The Gen Ed list had no second-language area

**Status:** resolved 2026-11-12 (#270, #271). The deploy of #271 (run
43312320789) rebuilt production's sections before the app restarted: its gate
log reads "[fact-tables] Rebuilt: sections." and "[measures] Rebuilt:
cedar_attempts, cedar_course_terms, cedar_course_flows." Confirmed from the
gate's log, not by reading production's rows.
**Found:** 2026-11-12, reported in #269 ("Is CEDAR capturing SPAN's gen ed
enrollment?").
**Severity:** moderate. `institution/unm/gen_ed_courses.csv` listed areas 1,
2, 3, 4, 5 and 7 and never area 6, so every second-language course had
`gen_ed_area` NA: absent from Explore > Gen Ed, Dept Trends > Gen Ed, the Gen
Ed tables of Open Seats and Regstats. The
only Spanish course counted was SPAN 2130, under Communication. On the local
tables, Fall 2025 on ABQ and online had 36 of the 55 courses on the schedule
with 2,228 enrolled seats, none counted as Gen Ed. Each course's own
enrollment was right everywhere; only the Gen Ed views missed it.
**Reproduction:** `dplyr::count(CEDAR_GEN_ED_COURSES, area)` shows no area 6;
`cedar_sections %>% filter(subject_course == "SPAN 1110") %>%
count(gen_ed_area)` is all NA.
**Fix:** the 55 courses the catalog lists for the second-language area, added
as area 6, "Second Language". All 55 codes appear in `cedar_sections`. The
transform stamps the area on sections, so `CEDAR_FACT_SCHEMA_VERSIONS` moves
sections to 2 and the next deploy rebuilds them. The projections leave the
area out on purpose (`projection_groups.csv` `exclude_gen_ed_areas`: language
courses are limited by instructors) and name SPAN 1110 and SPAN 1210 in
`projection_courses.csv`, so the monitored group goes from 139 courses to
141.

## I53 — Declaring the major a pre-major leads to was counted as a change of major

**Status:** resolved 2026-11-11.
**Found:** 2026-11-11, adding I38's fixture: its pre-major student who then
declared the major appeared in `detect_major_changes()`.
**Severity:** moderate. Pathways > Major Changes counted a student moving
from a pre-major to its own major as a major change whenever the two rows'
names differ, the same eleven drifted names as I38: 1,414 of 23,388 change
events on the 2026-11-04 tables, 980 of them "FDMA" to "Film and Digital
Arts", then Liberal Arts & Integrative Studies (182) and Signed Language
Interpreting (76). Each inflated its program's switched-in and switched-out
flows and the courses-before-leaving tables.
**Cause:** `detect_major_changes()` (`R/branches/major-change-detection.R`)
compared consecutive `program_name` values only.
**Reproduction:** `detect_major_changes(cedar_programs, opt =
list(premajor_leads_to = c(x = "y")))` (a map that ties nothing) returns the
old count; `count(from_major, to_major)` shows the pairs.
**Fix:** two consecutive rows are one program when either's code leads to the
other's in `premajor_leads_to` (programs.csv `leads_to`); `major_code` is
required. "declaring the major a pre-major leads to is not a major change" in
`test-pathways-integration.R` fails without it.

## I52 — Sections stored the instructor's employee ID, so they joined no other table

**Status:** resolved 2026-11-12. Fixed in the transform 2026-11-07; production's
DESRs were transformed again in the deploy of 2026-11-12 (run 43135526579), whose gate log reads "[fact-tables] Rebuilt: sections, students, programs, degrees." before the app restarted and passed its health check.
Confirmed from the gate's log, not by reading production's rows.
**Found:** 2026-11-07, checking whether the class list's section columns could
be read from `cedar_sections` instead (ADR-001 step 5).
**Severity:** medium. `parse-data.R` md5-hashes `Primary Instructor ID` on the
class list and `UNM ID` on the HR report, but the DESR's report spec names no
ID column, so `PRIM_INST_ID` reached `cedar_sections` as the 9-digit employee
ID, in the clear. The transform then left-joined the HR report onto the DESR
by that ID against HR's hash: it matched nothing, and `job_cat` was NA on
every section while the log said "HR merge complete". A merge that had
matched would have duplicated sections, since HR holds several appointments
for 1,858 instructor-terms. Nothing in the app read the section's ID or
`job_cat`, so no page was wrong; the data model's sections → faculty key
(data-model.md) did not hold.
**Reproduction** (on the 2026-11-04 files):

```r
d <- Sys.getenv("CEDAR_DATA_DIR")   # the app's data, not the repo's data/
s <- qs2::qs_read(file.path(d, "cedar_sections.qs"))
mean(is.na(s$job_cat))                   # 1
table(nchar(s$instructor_id))            # 9 only
f <- qs2::qs_read(file.path(d, "cedar_faculty.qs"))
mean(s$instructor_id %in% f$instructor_id)   # 0
# md5-hashed, the section's ID is the class list's on 108,362 of 108,497 sections
```

**Fix:** `hash_instructor_id()` in the transform hashes the DESR's, the class
list's and HR's instructor IDs as `parse-data.R` does, leaving a hash and NA
alone, so files that never went through parse-data (the synthetic
institution's) come out the same. The HR merge and `job_cat` are gone: a
section carries no faculty attribute, and a reader that wants one joins
`cedar_faculty` on `term` and `instructor_id` and picks the appointment.
`test-demo-data.R` checks the three tables share the ID (fails without the
fix); `test-transform-status.R` the hashing. On the 2026-11-04 DESRs the
rebuilt sections are identical but for the ID and `job_cat`, and 30.7% of
section-terms find their instructor in `cedar_faculty` (none before).
**Affects:** `R/data-parsers/transform-to-cedar.R`; `cedar_sections` columns
`instructor_id`, `job_cat`.

## I51 — A classification filter matched nobody: its value was split on the comma

**Status:** resolved 2026-11-07.
**Found:** 2026-11-07, writing the test that a classification filter reads the
student-term table (ADR-001 step 5): a designed value with a comma selected
no rows.
**Severity:** low in effect, since the only setter was the sophomore screen
(`get_high_fall_sophs()`), which runs outside Shiny and which nothing reads.
But that screen has never returned a course.
**Cause:** `filter_by_col()` (`R/trunk/filter.R`) passes each filter value
through `convert_param_to_list()`, which splits a single string on commas.
Banner's classifications carry one (`"Sophomore, 2nd Yr"`, `"Freshman, 1st
Yr, 1st Sem"`), so the filter looked for `"Sophomore"` and `"2nd Yr"`.
Instructor names were already exempt.
**Reproduction:** `filter_class_list(rows, list(classification = "Sophomore, 2nd Yr"))`
on rows that carry the classification returns zero rows.
**Fix:** `student_classification` is exempt from the split, beside
`instructor_name`. "a classification filter selects on the student-term's
value" in `test-student-terms.R` filters on a value with a comma; it fails
with the split.

## I50 — The class-list dedup can keep an early drop over a late withdrawal

**Status:** resolved 2026-11-12. Fixed in the transform 2026-11-07; production's
class list was transformed again in the deploy of 2026-11-12 (run 43135526579), whose gate log reads "[fact-tables] Rebuilt: sections, students, programs, degrees." before the app restarted and passed its health check.
Confirmed from the gate's log, not by reading production's rows.
**Found:** 2026-11-07, comparing saved `cedar_grades` (classified before the
dedup, one row per CRN) with `cedar_attempts` (classified from the loaded,
deduplicated class list) before moving Roadblocks onto the second.
**Severity:** medium. 708 DFW outcomes on the 2026-10-08 pull (0.3% of DFW)
were in `cedar_grades` and not in the class list every other reader counts;
the late withdrawals were missing from every class-list DFW and W count.
**Cause:** `transform_students()` keeps one row per student, term, campus and
course, ordering only by "registered first". A key holding an early drop
(DR/DD) on one CRN and a late drop (DG/DW) on another kept whichever came
first. On the same pull it also kept an audit row over a credit attempt in a
second section of a topics course (14 keys) and an ungraded lab over a
graded lecture (128 keys).
**Reproduction:** on a pre-dedup class list, a student with DR on one section
and DW on another of the same course and term: the old transform keeps either.
On the 2026-10-08 pull, 720 student-course-terms have an outcome in
`cedar_grades` and none in `cedar_attempts`; 703 kept an early drop.
**Fix:** `dedup_class_list_rows()` keeps the row `STATUS_PRECEDENCE` ranks
first (registered, late drop, waitlist, early drop), a row with a posted,
non-audit grade first within a status, then the lowest CRN. Run on the
2026-02-04 class list against the old transform: 3,045 kept rows change; 2
student-course-terms keep an outcome only in `cedar_grades` (from 720 on
the later pull); Roadblocks' first observations match the old path on every
one of 1,328,766 and add the 305 it had excluded as conflicting.
`test-transform-status.R` covers each rank.

## I49 — Ticking "Break out by instructor" errors the retention tables until Run

**Status:** resolved 2026-11-07.
**Found:** 2026-11-07, in the app log of a full institutional browser run
(`summarize_retention_by_term_type: instructor_id is required when
by_instructor = TRUE`, four times).
**Severity:** low: no wrong number reached a reader. But every retention table
on Course Dynamics > Retention showed "An error has occurred" from the moment
the box was ticked until Run was pressed again.
**Cause:** the result renderers in `server.R` (`cr_retention_results`,
`cr_retention_table`, `cr_retention_term_table`) read
`input$cr_ret_by_instructor` live, so ticking the box re-rendered the previous
course-only result as if it were split by instructor, and
`summarize_retention_by_term_type()` stopped, correctly, on the missing
`instructor_id`.
**Reproduction:** Course Dynamics, any course, Retention, Run with the box
unticked; then tick it without pressing Run.
**Fix:** the run observer records how its result was computed
(`cr_retention_by_instructor()`), and the renderers read that, never the
checkbox. The reports browser suite (`--e2e retention`) ticks the box and
asserts no output error before Run; it fails on the old renderers.

## I48 — A transform change to a fact table's stored columns is not rebuilt at deploy

**Status:** resolved 2026-11-12. Fixed 2026-11-11; the deploy that carried it
rebuilt production's four unstamped fact tables in the deploy of 2026-11-12 (run 43135526579), whose gate log reads "[fact-tables] Rebuilt: sections, students, programs, degrees." before the app restarted and passed its health check.
The rebuild took about 33 minutes there, not the 10 estimated, and with two
projection bundles due the deploy step then ran into its 60-minute command
limit before the second bundle was saved.
**Found:** 2026-11-06, in review of the PR that retired the mapping stamps
(ADR-001 step 3, PR 2).
**Severity:** medium. Until 2026-11-06 each mapped table carried a provenance
stamp that hashed `R/data-parsers/transform-to-cedar.R` among the mapping
files, so any transform edit rebuilt `cedar_sections`, `cedar_registrations`,
`cedar_programs` and `cedar_degrees` at deploy (about 16 minutes, every
time, whatever the edit). The stamps went with the stored unit columns, and
nothing replaced the one case that mattered: a transform change that adds or
renames a column the loader or a reader needs. The deploy gate
(`scripts/rebuild-programs-if-mappings-changed.R`) now checks
`cedar_student_terms` alone (file times, `STUDENT_TERMS_COLUMNS`,
`STUDENT_TERMS_BUILD_VERSION`); the four fact tables are rebuilt only by the
morning refresh. So a deploy of such a change starts the app on yesterday's
files, and the first reader of the new column fails until the refresh: the
I46 shape, with no gate in front of it.
**Reproduction:** add a stored column to `transform_sections()` and a reader
of it to `attach_section_units()`; deploy without a refresh. The gate reports
`cedar_student_terms is current`, the app starts, and `attach_unit()` stops on
the missing key.
**Fix:** the pattern `cedar_student_terms` already uses. `save_cedar_file()`
stamps each fact table with a `cedar_transform_schema_version` attribute from
`CEDAR_FACT_SCHEMA_VERSIONS` (in the transform, one number per table), bumped
by hand when a stored column is added, renamed or changes meaning. The gate
asks `cedar_fact_tables_staleness()` and rebuilds each stale table's stage in
its own R process (`build_fact_tables_if_stale()`; one stage per process on
the 8.6 GB host, see the memory-kill note under I46), then
`cedar_student_terms` and the measure tables, which the new file times make
stale (`cedar_course_terms` now also against `cedar_sections`). An unstamped
file predates stamping and is rebuilt once. A transform edit that changes no
stored column costs the deploy nothing, which the retired stamp could not
tell. A fact table that cannot be rebuilt (its report is not on the host)
does not keep the derived-table checks from running; its error is raised
after them. `test-rebuild-gate.R` holds the decision and the deploy's restart.
Rehearsed 2026-11-11 on a copy of the development data directory (reports of
2026-10-08, every table unstamped): four stages, each building the derived
tables that follow from it, in 585 s with a 2.6 GB peak; a second run rebuilt
nothing.
**Only where the reports are current:** the gate rebuilds a fact table from
the parsed report beside it. On a development host whose `cedar_*` files were
pulled from production over older reports, running the gate by hand replaces
the newer tables with the older reports' rows; pull the reports too, or do
not run it there. Deploys and the refresh run it only in production.
**Worked around once (2026-11-07):** the thin saved class list (ADR-001 step
5) drops columns and adds `cedar_class_list_descriptions`. Every loader and
the transform's student-term stage accept the older full file, deriving its
descriptions from it and logging that they did
(`resolve_class_list_descriptions()`), so production keeps starting until its
next class-list transform. That path is the workaround, not the fix.
**Affects:** `.github/workflows/deploy.yml`,
`scripts/rebuild-programs-if-mappings-changed.R`, `transform-to-cedar.R`.

## I47 — The class list's `student_classification` is stamped at pull time when a term is pulled late

**Status:** resolved 2026-11-07 (ADR-001 step 5). The grouping readers moved
2026-11-04: Course Dynamics' rollcall, the Waitlists splits, Pathways'
classification axis and the Gen Ed graduate cohort read
`cedar_student_terms$student_classification`, which takes academic studies'
per-term value and keeps the class list's only where no academic-studies row
exists (`description_source`). On 2026-11-07 the loaded class list stopped
carrying the column (`thin_class_list()`): `filter_class_list()`'s
`classification` key filters a value the caller attached from the table, the
sophomore screen and the projections read it there, and the Course Report's
DFW by classification too. Since the saved class list went thin as well, the
reproduction below reads the roster's value from `cedar_class_list_descriptions`.
**Found:** 2026-11-04, comparing Course Dynamics' rollcall by classification
before and after the move (PR for the demographics readers).
**Severity:** medium. A late-pulled term's classification filter selects the
wrong students: filtering Fall 2025 to sophomores returns students who were
freshmen that term and sophomores at the pull. Terms pulled near their own
time are unaffected, which is why the 2026-11-04 agreement measurement
(99% of student-terms) hid it.
**Affects:** `R/trunk/filter.R` (`classification`), `R/features/regstats.R`
(`get_high_fall_sophs()`), and any ad-hoc reader of
`cedar_registrations$student_classification` for a term pulled late.

### What is wrong

The field-reliability contract tested academic studies' fields, not the class
list's. The class list's `student_classification` is the student's
classification **when the list was pulled**, printed on every row of the term.
Fall 2025's retained class list was pulled on 2026-03-07, mid Spring 2026, so
it describes its students as they stood in March 2026.

### Reproduction

```r
source("scripts/cedar-repl.R")
cl <- cedar_registrations %>%
  filter(subject_course == "ENGL 1120", term == 202580L,
         registration_status_code %in% STATUS_REGISTERED) %>%
  distinct(student_id, term) %>%
  inner_join(distinct(cedar_class_list_descriptions, student_id, term,
                      roster = student_classification),
             by = c("student_id", "term"))
j <- inner_join(cl, select(cedar_student_terms, student_id, term,
                           student_classification, description_conflict),
                by = c("student_id", "term"))
count(j, roster != student_classification)   # 535 of 1,543 differ
count(filter(j, roster != student_classification), roster, student_classification, sort = TRUE)
# Sophomore -> Freshman 2nd Sem 157; Freshman 2nd Sem -> Freshman 1st Sem 148;
# Sophomore -> Freshman 1st Sem 138; Junior -> Sophomore 76; Senior -> Junior 15
unique(filter(cedar_class_list_descriptions, term == 202580L)$as_of_date)   # 2026-03-07
```

Every differing row is `description_conflict = TRUE` with
`description_source = "programs"`, and every difference is the class list one
or two steps **ahead** of academic studies, never behind: the signature of a
value stamped at the pull.

### Done when

`filter_class_list()`'s `classification` key and `get_high_fall_sophs()` read
the student-term table (ADR-001 step 5), and the Fall 2025 sophomore filter
returns the students academic studies called sophomores that term. Done
2026-11-07.

---

## I46 — A deploy that must rebuild a table the app cannot start without takes the site down

**Status:** resolved 2026-11-04. The gate runs as soon as the new container
is up and before the health check, which is the first request and the one
that starts the app's R process. A table it rebuilds is on disk before the app
reads anything, and it runs beside no app at all: the old container is gone
and the new one has loaded nothing, which answers the memory concern that had
kept it off the start (I22). A rebuild still restarts the container, cheaply,
so nothing started meanwhile serves the old tables. The restart page stays up
throughout. `test-mapping-provenance.R` holds the order.
**Found:** 2026-11-04, the deploy of #193 (run 41870776329): the health check
failed and the step exited before the gate line.
**Severity:** high. Production answered 503 with the restart page from 17:07
UTC until the table was rebuilt by hand or by the morning refresh. The first
deploy after any change that adds a column the app requires to
`cedar_student_terms` would do the same.
**Affects:** `.github/workflows/deploy.yml`.

### What was wrong

The order was: replace the container, poll the health check, then run the gate.
The health check's first request starts the app, whose `global.R` validates
`cedar_student_terms` against the columns the new code requires and stops on
`cumulative_completed_unm_credits`, which #193 added. shiny-server reports the
app as exited on every request, the poll fails after five minutes and the step
exits, so the gate that reports exactly that staleness
(`cedar_student_terms_staleness()`: "saved cedar_student_terms lacks column(s)
the builder now writes") and would have rebuilt the table in its own process
never ran. The transform wrote the column on every development machine, which
is why the R gate and the browser suites passed.

### Reproduce

Add a column to `STUDENT_TERMS_COLUMNS` and to the app's validation spec, deploy
without rebuilding the server's saved table. With the gate after the health
check the deploy fails on the health check; with it before, the log shows
`[mappings] Rebuilding cedar_student_terms: saved cedar_student_terms lacks
column(s)...` and then the health check passes.

---

## I45 — The class list and the schedule name the same section with different course codes

**Status:** open; partly fixed 2026-11-06 (ADR-001 step 4, PR 1). The three
renames are confirmed `subject` rows in `institution/unm/code_history.csv`
(basis `section_crn`), and every section and class-list row carries a
`course_id` that joins them: SOC 371 and SOCI 371 are one course from Fall
2018. Low Enrollment's schedule view and course histories read it (reader PR
1, 2026-11-06: SOCI 371 on ABQ shows 19 terms where it showed 12), Course
Dynamics reads both tables by course (reader PR 2), and Regstats keys both
tables and its precomputed base on the id (reader PR 3, 2026-11-06), so the
schedule's SOC 371 capacity joins the class list's SOCI 371 census in its
saturation screen instead of reporting unmatched. Waitlists' enrollment
history resolves each row's code to its course for the join
(`attach_enrollment_history()`), so a waitlisted CCS course reads CCST's
history too, and since reader PR 4 its counts follow the course as well (one
row for a course waited for under two live codes). The Department Dashboard
(reader PR 5) and the enrollment projections (reader PR 6, model 0.28.0)
read by course as well. Since 2026-11-07 every loader keys the tables on the
course (`attach_course_ids()`: `subject_course` the course, `listed_code` the
term's code), so every reader does.
**CCS corrected 2026-11-07.** The confirmed subject row CCS → CCST was wrong:
CCST is the lower-division prefix (4-digit numbers) and CCS still the
upper-division one, on the Fall 2026 schedule and class lists alike; the 524
paired sections are pulls whose class lists printed CCST on 3-digit CCS
courses. `code_history.csv` now joins each of the 61 CCST nnn codes to CCS
nnn (course rows), so the CCS courses keep their own code as their id.
CCS is not retired: measured on the 2026-10-08 pull, both CCS and CCST
are on the schedule and the class list through Fall 2026 (CCS class-list
rows from Summer 2021, 5,675 of them; 109 Fall 2026 sections as CCS, none as
CCST), so a reader that joins a course-keyed table by the class list's code
misses CCS courses in the current term, not only in old ones.
**Found:** 2026-11-03, profiling which `cedar_registrations` columns could come from `cedar_sections`
**Severity:** medium. 1.3% of class-list rows; every page that reads the
schedule loses those terms for the courses affected.
**Affects:** any course-level view reading `cedar_sections` beside
`cedar_registrations` for SOCI, PSYC and CCST courses in the terms below. Related
to [I37](#i37--renumbered-courses-lose-their-history), which is the same gap
across terms; this one is inside a single term.

### What is wrong

Banner's class lists carry a renamed subject's new code back onto old terms,
and the DESR keeps the code the section was scheduled under. So one
`(term, crn)` has two `subject_course` values:

```
term     sections   class-list rows   example
201980      244          5,890        SOC 371 -> SOCI 371
202010      239          5,487        SOC 312 -> SOCI 312
202060       46          1,074        PSY 499 -> PSYC 499
202080      264          5,256        SOC 371 -> SOCI 371
202110      274          5,068        SOC 312 -> SOCI 312
202580       87            676        CCS 495 -> CCST 495
```

23,451 class-list rows (1.26%), all in SOC, PSY and CCS. SOCI 371 has 177,
150, 125 and 101 registered students from Fall 2019 to Spring 2021 on the class
list, and no sections at all in those terms: they sit under SOC 371. Courses
renumbered at the same time (SOC 1110 to SOCI 1110) agree, because the number
changed too. Every other section attribute checked agrees across the two
tables (campus, department, level, title: 100%).

### Reproduction

```r
source("scripts/cedar-repl.R")
inner_join(cedar_registrations %>% distinct(term, crn, subject_course),
           cedar_sections %>% select(term, crn, s_course = subject_course),
           by = c("term", "crn")) %>%
  filter(subject_course != s_course) %>% count(term)
```

### Done when

The transform names each section once. Either the class list takes its
section's code from the DESR, or both read a renaming crosswalk (I37's), so a
course's history is one code everywhere. A designed-fixture section carries
two codes across the tables and a test pins it to one.

## I44 — Roadblocks and Retention disagree on whether a late withdrawal returned

**Status:** resolved 2026-11-04. Both read `cedar_student_terms` (ADR-001
step 2): Roadblocks its `returned_next_regular_term`, Retention and persistence
its `enrolled` (registered, or registered and withdrawn after census), so a
student whose only next-term row is a late drop returned on every page.
`build_next_term_lookup()`, `.build_registered_lookup()` and the saved
`cedar_next_term` are gone. The cross-tab test is in
`tests/testthat/test-student-terms.R` (ST01: Retention's ret_1 and one minus
Roadblocks' pass stop-out rate are the same 3 of 10). Roadblocks' numbers did
not move; Retention's rose by the late withdrawals, about one point, and
`definitions.yml` course-retention 2.0.0 says so on the page.
**Found:** 2026-11-03, comparing the return lookups while planning degree-roadblock surfaces
**Severity:** medium. About one point UNM-wide, and more for the groups these
pages exist to find: a student who withdraws late is a student at risk.
**Affects:** `.build_registered_lookup()` in `R/branches/retention-context.R`
(Course Dynamics > Retention, `next_term_persistence()`, cross-course
Retention) and `build_next_term_lookup()` in `R/cones/stopout.R` (Pathways >
Roadblocks, saved as `cedar_next_term`).

### What is wrong

Both answer "was this student enrolled at UNM next term?", and they answer it
differently. Retention counts a registered row only (`STATUS_REGISTERED`).
Roadblocks counts a registered row or a late drop (`STATUS_DROP_LATE`). A
student who registered for next term, attended past census and then withdrew is
retained on one page and stopped out on the other.

```
anchor -> next   anchor students   registered only   registered or late drop   only a late drop next term
202580 -> 202610      28,282        23,111 (81.72%)      23,395 (82.72%)                 284
202510 -> 202580      25,921        18,425 (71.08%)      18,642 (71.92%)                 217
```

(All levels, enrolled in the anchor term registered or late-dropped, Oct 27
pull. Graduates are not removed here; both lookups treat them alike.)

I17 unified Retention with next-term persistence on Course Dynamics, but
Roadblocks kept its own lookup.

### Reproduction

```r
source("scripts/cedar-repl.R")
a <- cedar_registrations %>% filter(term == 202580, registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)) %>% distinct(student_id)
nx <- cedar_registrations %>% filter(term == 202610) %>% group_by(student_id) %>%
  summarise(reg = any(registration_status_code %in% STATUS_REGISTERED),
            late = any(registration_status_code %in% STATUS_DROP_LATE))
a %>% left_join(nx, by = "student_id") %>% summarise(only_late = sum(!reg & late, na.rm = TRUE))  # 284
```

### Done when

One definition of "enrolled next term", in one branch helper, read by
Retention, persistence, Roadblocks and `cedar_next_term`. A cross-tab test pins
a student whose only next-term row is a late drop to the same answer on every
path. Registered or late-dropped is the likelier choice, since census is
CEDAR's basis for enrollment elsewhere. Whichever is chosen goes into
`definitions.yml`, and the page whose numbers move says so.

## I43 — Every scheduled refresh fails because the default asks for a report mrgather never fetches

**Status:** fixed in CEDAR: the default 2026-11-03 (#186), per-report
rebuilds and the run summary 2026-11-11. mrgather's source refuses a report
it does not have since 2026-11-22; open until production's copy and image are
replaced with it (see Still to do)
**Found:** 2026-11-03, reading the production refresh logs
**Severity:** high. Nothing wrong was published, but production stopped
refreshing. `cedar_sections` and `cedar_programs` were last written on Oct 27
at the morning run, and `cedar_registrations` by a manual class-list run that
afternoon. The app has served those tables since.
**Affects:** the default report list in `scripts/update-data.sh`, and mrgather
(`/root/mrgather`, a separate repository; image built 2026-04-10).

### What is wrong

The 10:05 cron runs `update-data.sh -s 202680 -e 202710` and names no reports,
so the script asks for all five: `desr deg as cl aa`. Production mrgather
fetches only the first four. It accepts `aa` as an argument, never attempts
it, and still reports "Total Downloads Attempted: 8, Successful: 8". The
applicants table has not been refreshed since `admissions_applicants.qs` was
written on 2026-06-19.

Until 2026-10-24 that went unseen, because the fetch step trusted mrgather's
exit status (I33). The I33 fix checks every requested report for a file from
today. Since then, every scheduled run has stopped at the fetch, and the
transform and every later step are skipped:

```
mrgather fetch               ❌      1146s    no file from today for: aa; see mrgather output
transform-to-cedar.R         ✅      0s       prior step failed; transform not run
```

The four reports that did download are parsed and then never used. Oct 28 to
Nov 3 each failed on `aa` alone; Oct 25–26 on `cl aa`; Oct 29 on all five (a
login failure). Only the manual `cl` run of Oct 27 at 13:36 completed.

### Reproduction

On the droplet:

```bash
grep -E "Reports:|mrgather fetch|Total Downloads Attempted" /var/log/cedar-update-202611*_100501.log
ls -la /root/shared-data/cedar_sections.qs /root/shared-data/cedar_students.qs
```

### Fix

The default is `desr deg as cl`. The applicants report runs only when named
(`update-data.sh -s 202680 desr deg as cl aa`). A test in
`test-data-update-pipeline.R` pins the default; with `aa` back in it, the test
fails.

### Still to do

- Production's mrgather (`/root/mrgather`, image built 2026-04-10) is still
  the old one: copy the current `mrgather.js` there and rebuild the image.
  The current source (2026-11-22) fetches the applicants report, keeps every
  report in one list (`REPORT_HANDLERS`) and exits 1 naming any report not in
  it before fetching anything. Once production has it, `aa` and `holds` can
  be made `daily` in `R/data-parsers/report-specs.R` and
  `scripts/report-registry.sh`.

Done 2026-11-11 (branch `refresh/partial-rebuild-and-fetch-limit`):

- One missing report no longer skips every table. The fetch is judged per
  report: the ones with a file from today go on to parse and transform, the
  others keep their tables, the step reads `mrgather fetch ❌ no file from
  today for: aa; continuing with: desr deg as cl`, and the run still ends
  with an error (exit status 2, on which `restart-cedar.sh --update` reloads
  the app; 1 when nothing arrived or a later step failed).
- A step that did not run shows ➖ in the run summary, never ✅.

## I42 — A saturated course whose Fall changes lower its forecast is still called a floor

**Status:** resolved 2026-11-03: page text in #185, model-source text in #184
(branch `projections/fall-waiting`)
**Found:** 2026-11-03, rechecking the projections page's wording against the
saved Spring 2027 bundle
**Severity:** low. No number is wrong, but one row's text contradicts its own
plan steps.
**Affects:** `projection_summary_sentence()`
(`R/features/enrollment-projection-view.R`) and `floor_note` in
`add_projection_recommendations()` (`R/branches/enrollment-projection-plan.R`,
model source).

### What is wrong

When last year's same term was near full, the summary says "Last Spring filled
96.2% of its seats on the first day, so this is a floor", and `floor_note`
says "the floor is the spine itself; the projection is a lower bound". The
published adjusted forecast is spine + floor + Fall deltas. When the deltas
are negative it falls below the spine, which the text has just called the
floor. ENGL 1120: last Spring 2,179, and the Fall changes take 15 off (repeat
+3, ENGL 1110 −7, other feeders −12), so the forecast is 2,164. CHEM 1215:
719 → 716. The plan steps show the subtraction directly under a sentence that
says the number cannot go lower.

### Reproduction

Load the Spring 2027 bundle (schema 26) and filter `projections` to
`adjusted_saturated_prior` with `projected_classlist_total <
observed_baseline`. That returns ENGL 1120 and CHEM 1215, and both
`summary_sentence` values from `build_enrollment_projection_view()` end their
fill clause "so this is a floor". The Fall 2027 bundle has none, because two
steps ahead it carries no deltas.

### Decision: evidence about last year, not a floor under this one

A saturated course's count is a lower bound on *last year's* demand. A rule
that kept this year's forecast from falling below it would make the forecast
blind to falling feeder courses and majors, which is exactly what the deltas
are there to read. The saved aftcasts agree. Take the past forecasts whose
prior term was near full and whose term-just-finished changes pointed lower:
9 Spring and 26 Fall. Registrations then came in below last year's count in
6 of the 9 and 13 of the 26. A clamp at last year's count would have been 14.5%
off against 14.1% unclamped (Spring), and 8.0% against 8.4% (Fall). That is no
better, and it says nothing true about direction. So the forecast keeps the
decline, and the page states both facts. The capped count understates demand,
and the pressure bump, where it applies, allows for that. The changes in the
term just finished point lower. The bump is 5% of last year's count, so the
plan can still sit above last year (ENGL 1120: 2,164 + 109 = 2,273 against
2,179).

### Fix

`projection_summary_sentence()` now says "The forecast is 0.7% below last
Spring's 2,179: the changes in Fall 2026 point lower. Last Spring filled 96.2%
of its seats on the first day, so its count was capped by its seats and
understates demand; the pressure bump allows for that." A change under 1%
keeps a decimal, so CHEM 1215's 716 against 719 does not read as a match. The
plan explainer's "Changes in the term just finished" step says the change can
take a near-full course below last year's count, and the text preview's floor
column reads "spine was capped". A test in `test-projection-page-text.R`
pins the ENGL 1120 case. In the model source (#184), `floor_note`, shown
under **Saturation floor** in the evidence trail, now says the prior term's
count "was capped by its seats, so it understates demand" instead of "the
projection is a lower bound", and a capped term with no waitlist rows "adds
nothing to the spine" instead of being "the floor itself". The pressure-bump
note said "planned for 5% more than last Spring's 2,179 registrations", which
overstated the plan wherever the forecast differs from last year's count; it
now reads "the bump is 5% of last Spring's 2,179 registrations".

## I41 — Projection labels call the term just finished "Fall" whatever its season

**Status:** resolved 2026-11-03: page labels in #185, model-source labels in
#184 (branch `projections/fall-waiting`)
**Found:** 2026-11-03, rechecking the projections page's wording
**Severity:** low. A wrong word, not a wrong number, but it points a reader at
the wrong term.
**Affects:** `projection_flags()` ("Fall enrollment ±N%",
`R/features/enrollment-projection-view.R`); `projection_flag_is_warning()`
(matches `^Fall enrollment`) and the "Fall changes" step of
`projection_build_explainer()` (`R/modules/enrollment-projections.R`); the
method label "Prior same-season + floor + Fall deltas" and the "no Fall deltas"
basis text (model source).

### What is wrong

The adjusted candidate reads its deltas from `subtract_term(target_term,
summer = FALSE)`, the term just before the target. For a Spring target that is
a Fall term. For a Fall target one step ahead it is a Spring term. The regime
flag hard-codes the word "Fall". So does the step label, and so does the method
label. The summary sentence and `regime_note` use `fmt_term()` and are
correct. Today no Fall bundle is one step ahead: Fall 2027 is two steps past
the settled edge and carries no deltas. When Spring 2027 settles, the Fall 2027
bundle will read Spring 2027 and flag "Fall enrollment +N%" about a Spring term.

### Reproduction

`R/branches/enrollment-projection-candidates.R` sets `preceding_term <-
subtract_term(target_term, summer = FALSE)`, and `projection_flags()` pasted
the literal "Fall enrollment " in front of it. The saved Fall 2027 bundle's
own aftcasts are already one step ahead. Every `spine_adjusted` backtest row
for Fall 2023–2026 reads the Spring before it (`preceding_term` 202310 to
202610), and 98 of them raise the regime alarm. Only the published row is two
steps out today.

### Fix

The flag names the term ("Fall 2026 enrollment +25%", "Spring 2027 enrollment
+25%"), and `projection_flag_is_warning()` matches any season. The plan
explainer's step and the evidence trail read "Changes in the term just
finished". A test pins the Spring case. In the model source (#184), the
method label is "Prior same-season + floor + latest-term changes", the delta
basis says "so no change from it is added" instead of "no Fall deltas", and
the definition (`docs/_data/definitions.yml`, 1.10.0) says "moved by
enrollment changes in the term just finished". A change that rounds to
nothing reads "0%", not "-0%", in the regime note and the text preview.

## I40 — The projections page gave a forecast's own misses to the schedule

**Status:** resolved 2026-10-29
**Found:** 2026-10-29, auditing the projections table as a first-time reader
before the chairs' and deans' review
**Severity:** medium. No projection changed, but the page told a reader that a
course's large past misses were the schedule's, and so safe to plan through,
when the course had seats to spare and the misses were the forecast's own.
**Affects:** `projection_reliability_reading()`, `projection_flags()` and
`projection_miss_sentence()`, `R/features/enrollment-projection-view.R`.

### What is wrong

Whose miss a course's past error was came from one course-level rating,
`seat_consistency`: High when the seats held within 10% in every reliability
term, Low or Moderate when they moved in any. Low reliability with moving
seats read "the misses came when the seats moved: the schedule set those
numbers", with no flag; only Low with steady seats was flagged as the
forecast's own. A seat move says whose a miss was only when the course was
near full: a full course registers about as many students as it has seats, so
added seats fill and cut seats cap it. A course with seats to spare could have
drawn more or fewer students whatever its seats did. FYEX 1110 moved its seats
in all four of its Spring reliability terms, was never near full in them, and
missed by 48% on average; the page gave every point of that to the schedule.

### Reproduction

Load the saved Spring 2027 bundle and run `projection_miss_attribution()`
(this fix) beside each row's `seat_consistency`. Of 37 Low-reliability
courses, the old rule flagged 1 (GEOG 2115, steady seats) as the forecast's
own; per term, 8 missed mostly with seats to spare, and 7 of them (ARTS 1143,
CCST 1125, FYEX 1110, MATH 1300, POLS 1120, POLS 2120, RELG 2110) had moving
seats, so the old rule gave them to the schedule. In Fall 2027 the old rule
flagged none of 33 Low courses; per term, FYEX 1030 and PHIL 2225 missed
mostly with seats to spare.

### Fix

`projection_fold_miss_cause()` reads each past forecast term on its own: the
schedule's when the course was near full and its seats moved the way the
forecast missed, or held; the forecast's own when it had seats to spare or
its seats moved against the miss; unknown when the seats or the first day are
not known. `projection_miss_attribution()` gives each course the cause behind
most of its absolute error. The reading, the flag ("Off 20%+ with seats to
spare") and the sentence above the table follow it. Seat moves still show,
as counts beneath Reliability, never as a rating of their own. The test "a
past miss is the schedule's only when a full course's seats moved the way it
missed" in `test-projection-model.R` pins every case of the rule;
replacing the near-full condition with any seat move fails it.

The **Where forecast error comes from** panel made the same mistake page-wide:
`summarize_projection_error_sources()` counted every 10%+ seat move as the
schedule's. Schema 26 moved `projection_fold_miss_cause()` into
`R/branches/enrollment-projection-error-sources.R` and the panel now sums
the error by it, so the panel and each course read misses one way.

## I39 — Projection flags called last year's same-season term "last term"

**Status:** resolved 2026-10-28
**Found:** 2026-10-28, reviewing the Spring 2027 projections page before the
chairs' and deans' review
**Severity:** low. No number was wrong, but the words pointed a reader at the
wrong term.
**Affects:** `projection_flags()` and `projection_campus_fill_flags()`,
`R/features/enrollment-projection-view.R`.

### What is wrong

The fill flags ("Full last term", "Near full last term", "N waiting", "Last
term's fill unknown") and the campus flag ("EA full last term, ABQ had room")
read `adjusted_prior_first_day_fill` and `recent_campus_history`. Both describe
the spine term, the same season a year earlier. For a Spring 2027 target that
is Spring 2026. A chair reads "last term" as Fall 2026, the term just finished,
which the Fall deltas read and the fill does not.

### Reproduction

Load the Spring 2027 bundle and tabulate `spine_term` against
`adjusted_saturated_prior`. Of the 61 saturated rows, 57 start from 202610 and
4 from earlier Springs (courses not offered in Spring 2026); none is a Fall
term. `projection_flags()` on the bundle before this fix labels those rows
"Full last term" or "Near full last term". The Fall 2027 bundle is the same
with Fall terms: 74 of 79 saturated rows start from 202680.

### Fix

The fill moved out of the flags into its own **Day-1 fill** column
(`projection_prior_fill()`). Its header names the term, for example "Day-1 fill
(Spring 2026)", and each of those older-Spring rows names its own term. The campus flag names its term too: "EA full in Spring 2026, ABQ had
room". A test in `test-projection-page-text.R` asserts the named term. The
user guide says the column describes the same season last year.

## I38 — A Pathways program population misses pre-majors whose name differs from their major

**Status:** fixed 2026-11-11 for every program population: `build_population()`
adds the pre-major codes whose `leads_to` is a focal code
(`pre_major_codes_leading_to()`, shared with `population_group_major_codes()`).
Fixture EC-38 is a pre-major named unlike its major; the test in
`test-pathways-integration.R` fails without the fix. On the 2026-11-04 tables
the Film and Digital Arts population (every outcome) goes from 1,149 students
to 2,164: all 2,000 students ever declared `FFDA` are in it (985 before), and
all 1,013 who never declared `FDMA` (none before). Open only for the eleven
names in `programs.csv`, which no longer change a count but still read
oddly where a pre-major's name is shown; a mapping decision.
**Found:** 2026-10-26, while adding Film and Digital Arts to Degree Explorer
**Severity:** moderate — a program population undercounts its pre-majors, so
their outcomes (`chose_elsewhere`, `left_undeclared`) read low or vanish.
**Affects:** `build_population()` for every type that starts from declared
programs (`major`, `preset`, `dept`; `R/branches/population.R`), so every
Pathways population except the demographic one. Pathways presets pass their
group's program names down this path. Only the projections growth scenario
resolves a group through `population_group_major_codes()`, which already adds
pre-majors through `leads_to`.

### What is wrong

`get_focal_programs()` takes the declared programs' names and codes, and
candidates are rows matching either. A pre-major whose `program_name` in `institution/<id>/programs.csv`
differs from its major's matches neither. Eleven do: `FFDA` is named "FDMA"
(4,410 rows), `FSIG` "Signed Language Interpret" (657), `FLAI`, `FFDM`
("IFDM"), `FDTP`, `FCCS`, `FMDL`, `FWGS`, `FCLC`, `FINN` and `FITT`; each
`leads_to` names the right major.

Measured for Film: the "Film and Digital Arts" population (pre-majors lumped)
has 1,149 students. Of the 2,000 students ever declared `FFDA`, 985 are in it;
of the 1,016 who never declared `FDMA`, 1 is.

### Reproduction

`build_population(cedar_programs, cedar_degrees, cedar_registrations, opt =
list(program_names = "Film and Digital Arts", include_pre_majors = "lump",
data_edges = cedar_report_edges(cedar_registrations, cedar_degrees)))`, then count
`FFDA` students who never declared `FDMA` among its `student_id`s.

*Done when:* the program-name path adds pre-major codes through
`premajor_leads_to`, as `population_group_major_codes()` does, with a designed
fixture pre-major whose name differs from its major; and the eleven names are
corrected in `programs.csv` (a mapping change, so the deploy gate rebuilds
programs).

## I37 — Renumbered courses lose their history

**Status:** open; mostly fixed. On 2026-11-07, 277 of the 320 proposed title
matches were confirmed in bulk by rule: the common course numbering
conversions (3-digit to 4-digit at the same level, distinctive title) and
subject prefix changes seen on several courses. Six coincidences of a shared
title were deleted (NURS 419L → FDMA 2999, NURS 245 → SPCD 601, EMS 461 →
NURS 711, HHHA 153 → HED 486, LAIS 199 → LAIS 301, PEP 474 → ATED 610). The
37 still proposed change level (the NURS 5xx → 7xx doctoral series, ARTH,
BIOL, ENVS), carry a generic title, or are a one-off subject change; each row's
notes say which. Measured on the 2026-10-08 pull: ENGL 1120, MATH 1220,
ACCT 3401 and BUSA 3220 each read as one course from 2018.
Earlier history: partly fixed 2026-11-06 (ADR-001 step 4, PR 1).
`institution/unm/code_history.csv` exists, validated at startup;
`scripts/propose-code-history.R` wrote 320 one-to-one title matches as
proposed rows (MGMT 340 → ACCT 3401 among them), each waiting for a person to
confirm; a confirmed row gives both codes one `course_id` at the next start.
Low Enrollment's schedule view reads the id (reader PR 1, 2026-11-06): once
the Fall 2026 renumberings are confirmed, 84 of its 391 Fall 2026 courses
with no history by code show their old offerings (36 BUSA, 8 ACCT, 8 NURS).
Course Dynamics (reader PR 2) and Regstats (reader PR 3, 2026-11-06) read
the id: a confirmed renumbering's earlier offerings enter the course's
baselines and its Terms at Cap, and the row names the former code. The
enrollment projections read by course from model 0.28.0 (reader PR 6): a
confirmed renumbering joins its earlier offerings to the course's spine,
deltas and aftcasts. Waitlists' enrollment history
reads the precomputed base by course, resolving each waitlist row's code to
its id for the join, so a renumbered course's earlier offerings enter its
history; since reader PR 4 its counts are by course too.
**Found:** 2026-10-24, with I36
**Severity:** moderate — a history keyed on `subject_course` starts over at a
renumbering, so a renumbered course reads as new.
**Affects:** every lookup that follows a `subject_course` across terms. Measured
only in Low Enrollment's schedule view (I36); Regstats baselines, Course
Dynamics history and enrollment projections use the same key.

### What is wrong

In Fall 2026 Anderson renumbered its MGMT courses to ACCT and BUSA, and
Population Health renumbered POPH (the change behind I5). ACCT 3401 Financial
Accounting I was MGMT 340, and BUSA 3001 Operations Management was MGMT 300.
CEDAR has no old-to-new crosswalk, so each new number's history begins in Fall
2026. Of I36's 216 non-topics rows, 122 match an earlier offering with the same
title under another number on the same campus: 63 BUSA, 17 POPH, 7 ACCT, 6 MUS,
5 NURS. Title matching only proposes candidates: BIOL 429 matches BIOL 201L.

*Done when:* an institution file records renumberings (old code, new code,
first term), validated at startup; history lookups read through it; and I36's
renumbered rows show their old offerings.

*Plan (2026-10-24):* CEDAR keeps its own map. Each year, when the catalog
publishes, the Degree Explorer catalog update also compares the edition's
courses with the last edition's and proposes renumberings. Each term, a screen
lists newly scheduled codes with no history whose title matches a retired
code. Both produce candidates for review, never entries.

## I36 — Low Enrollment's schedule view reports no prior history for courses that have it

**Status:** resolved 2026-10-24
**Found:** 2026-10-24, reviewing Spring 2027 in Low Enrollment (2026-10-23 pull)
**Severity:** moderate — the view exists to flag risky courses before
registration, and it shows courses with years of history as new, with a red
average of 0.
**Affects:** `get_enrollment_concerns()` in `R/branches/enrl.R` and the
concerns table in `server.R`.

### What is wrong

`get_enrollment_concerns()` matches each scheduled course to earlier offerings
with the same `subject_course`, `course_title` and `campus` in the same season,
and each key drops real history. Of 2,226 Spring 2027 ABQ/EA undergraduate
courses, 363 show "No prior history":

| Why | Rows |
|---|---:|
| Offered in Spring on that campus under another title (126 topics, 50 reworded) | 176 |
| Offered on that campus, never in Spring (79 of the 98 non-topics are renumbered, I37) | 112 |
| Offered only on another campus (BIOL 2210 on EA; branches ran 48 online sections) | 26 |
| Only cancelled Spring offerings | 9 |
| Never offered under that number since Fall 2019 (15 renumbered) | 40 |

The title key is the reverse of `get_course_enrollment_history()` in the same
file, which narrows by title only for topics courses because regular titles get
reworded. A course with no history shows an average of 0 in the red band rather
than an em dash. In this mode the section-enrollment column is all zeros and
the Min enrolled input does nothing.

*Done when:* titles narrow history only for topics courses; a course with no
same-season history shows its latest other-season or other-campus offerings,
labelled as such; a missing average displays as an em dash; a designed fixture
holds a reworded title, a Fall-only course and a course new to one campus, and
its test fails on the current function.

### Reproduction

On the 2026-10-23 `cedar_sections`, run `get_enrollment_concerns(sections,
list(term = "202710", course_campus = c("ABQ", "EA"), level = c("lower",
"upper"), status = "A", uel = TRUE))`: 363 rows have `n_prior_terms == 0`.
Classify each against the sections before 202710 after `keep_home_sections()`
and `drop_shell_sections()`, by campus, then season, then title.

### Fix

Regular courses now match on number and campus; a course with any `T:` section
keeps its title in the key. A course with no same-season history shows a dash
and lists its latest offerings that ran anywhere else, each with its campus, and
those never set the average. On the same pull 1,910 of 2,226 courses find
same-season history (1,863 before). Of the 316 without, 263 list other
offerings; 44 have no earlier offering that ran (40 never scheduled under that
number, 15 of them renumbered, I37, and 4 only ever cancelled); and 9 have only
cancelled Spring sections on their campus, 6 of which list offerings elsewhere.
SC01 in `designed_test_data.R` fails when the title key returns, or when a
cancelled section is listed as another offering.

## I35 — A Fall projection is read before the Fall's intersession has registered

**Status:** resolved 2026-10-24 in model 0.24.0
**Found:** 2026-10-23, comparing Fall 2027 bundles built from the same pull
**Severity:** moderate, for the few courses with large December sessions.
**Affects:** the Fall spine in `R/branches/enrollment-projections.R`.

### What is wrong

A Fall counts as settled 14 days after it begins, but its December
intersession registers in November. On the 2026-10-23 pull no Fall 2026
December section held students, so the Fall 2027 spine had none of the
December demand that the Falls it is scored against had:

| Course | Fall 2025 registrations | of them December | Fall 2026 so far |
|---|---|---|---|
| FYEX 1110 | 801 | 168 | 560 |
| MUSC 1120 | 205 | 104 | 100 |
| DANC 1110 | 166 | 83 | 107 |

### Fix

`prepare_enrollment_projection_inputs()` drops intersession sections and
class-list rows before anything reads them, so every demand, seat and
first-day count is the regular sessions'. December students are 2–3% of Fall
registrations in the monitored courses (632 of 24,185 in Fall 2025). A design
that kept them, by splitting the spine and borrowing a pending December from
the previous Fall, was dropped as too much machinery for that share. The IS01
test fails when either the sections or the class-list filter is removed.

On the 2026-10-23 pull, against 0.23.0: Spring 2027 regains three pressure
bumps (CHEM 1215L, COMM 1130, HNRS 2221) that a December-inflated feeder fall
had vetoed (−5.6% to −6.3%, now −4.1% to −4.7%). Fall 2027 gains five courses
(AFST 1110, ENGL 2210, MATH 1430, RELG 1110, THEA 1110) once December seats and
first days stop hiding two near-full Falls.

## I34 — A projection pressure decision flips with the platform's floating point

**Status:** resolved 2026-10-24 in model 0.24.0
**Found:** 2026-10-23, rebuilding production's Spring 2027 bundle on a Mac to
audit the intersession change
**Severity:** low. One course in one bundle. But the same tables and the same
code published different course lists on different machines, so no rebuild
could be checked against production.
**Affects:** `build_projection_pressure_screen()` in
`R/branches/enrollment-projections.R`.

### What is wrong

The screen includes a course when its trend demand exceeds next term's seats
by at least `pressure_min_seat_gap` (10). The trend is an `lm()` fit, and its
last bit depends on the BLAS. NATV 1150's last three Springs, 109, 120 and
122, fit exactly 130 against 120 seats: the minimum, met. Production (Linux)
computed 130.000000000000000 and included the course ("Trend demand exceeds
scheduled capacity by 10 registrations"). R's reference BLAS on macOS computed
129.999999999999972 and excluded it ("historical and trend demand remain within
10 seats"). Every other number in the two bundles agreed.

### Reproduction

```r
x <- 1:3; v <- c(109, 120, 122)
sprintf("%.17g", predict(lm(v ~ x), data.frame(x = 4)))  # "129.99999999999997" on macOS
```

### Fix

`projection_seat_gap_reached()` compares both seat gaps (historical shortfall
and trend growth) with a tolerance of `sqrt(.Machine$double.eps)`. The test "a
trend exactly at the seat gap counts on every platform (I34)" fails on macOS
without it, and its fixed-value assertion fails on any platform.

## I33 — A crashed MyReports download is recorded as a successful fetch

**Status:** fixed in CEDAR (2026-10-24 and 2026-11-11, see Fix and Still
open); open for mrgather, which still exits 0 after a fatal error, and for
the two limits of the file check listed under Still open.
**Found:** 2026-10-23, reading the log of a manual production refresh
(`restart-cedar.sh --mode production --update -s 202680 -e 202710`,
`/var/log/cedar-update-20261023_192042.log`)
**Severity:** moderate. No number was wrong this time. But a refresh that
fetches nothing new for a table reports a complete success. The app then serves
the previous pull as if it were today's, and the as-of dates are the only sign.
**Affects:** the fetch and parse steps of `scripts/update-data.sh`, and
mrgather (`/root/mrgather`, a separate repository).

### What is wrong

mrgather downloaded the two DESR files, the two graduates files and the first
Academic Study file. The second Academic Study download then timed out. Its
error handler itself failed, and mrgather exited with status 0:

```
✗ Error fetching AS on attempt 1: Download timed out
Fatal error during report gathering: TypeError: tracker.recordReportFetchError is not a function
...
Script complete. Exiting...
✓ Fetch complete
```

The class list and applicants reports were never attempted. Every later step
still reported success:

- `update-data.sh` trusts the exit status. It recorded
  `mrgather fetch ✅ fetched: desr deg as cl aa`, and that note lists the
  reports requested, not the ones downloaded.
- `parse-data.R` logged `No .xlsx files found ... matching signature:
  Class_List_Guided_Adhoc` and the same for `S_Admissions_Applicants_Detail`,
  then reported ✅.
- The transform rebuilt `cedar_registrations` from the previous class-list export,
  and the run ended `CEDAR Update Complete`.

The data was not harmed this time, because that morning's cron run had already
fetched the day's class lists. The 15 earlier refresh logs, 2026-10-10 to
2026-10-23, show no other crash. But if the cron run itself failed this way,
the class lists would quietly stay at the previous pull while the morning
status said all was well.

*Done when:*

- A fetch that downloads fewer reports than were requested is recorded as
  failed, and names the missing reports.
- The fetch note lists the reports actually downloaded.
- `parse-data.R` fails a requested report that has no file.
- The tables built from a missing report are not rebuilt.
- mrgather exits non-zero after a fatal error, and its tracker method exists.
- `test-data-update-pipeline.R` covers the shell side.

### Reproduction

The timeout cannot be forced. Read the evidence from the log:

```bash
grep -nE "Fatal error during report gathering|Script complete|Fetch complete|No .xlsx files found|mrgather fetch" \
  /var/log/cedar-update-20261023_192042.log
```

To check any run: a requested report with no `Done processing file:` line for
its signature was not refreshed by that run.

### Fix

After mrgather exits 0, `update-data.sh` checks each requested report for a
file from today, with the same name patterns as the skip check before the
fetch. A report without one fails the step: `mrgather fetch ❌ no file from
today for: cl aa`. Every later step is already skipped after a failure, so the
tables in place are kept. The same failure had struck a local run on
2026-10-20: a MyReports login timeout, no download, and the morning's
production tables replaced by ones built from Oct 8 exports. That was recorded
only in work that was never merged. `test-data-update-pipeline.R` runs the
script's own fetch block with a stubbed mrgather; without the check, three of
its cases fail.

Still open:

- The check asks for a file from today, not from this run. On Oct 23 the
  morning cron had already fetched the class lists, so that run would have
  passed, rightly: the data was today's.
- One Academic Study file satisfies the check. A run that gets the first file
  and loses the second, as on Oct 23, still passes.
- mrgather still exits 0 after a fatal error. On Oct 27 a manual class-list
  re-pull (`/var/log/cedar-update-20261027_110446.log`) stopped on the
  VPN's sign-in handoff (`unmvpn.unm.edu/SAML20/SP/ACS`), never reached
  `#SignonUserName`, and exited 0 with `Fatal error during report gathering`.
  The fetch check caught it (`no file from today for: cl`) and nothing was
  republished; the same command run again at 13:36 UTC logged in normally.

Fixed 2026-11-11 (branch `refresh/partial-rebuild-and-fetch-limit`):

- A report that arrived is refreshed when another did not. The fetch step
  lists the reports with a file from today and passes only those to
  `parse-data.R -r` and to the transform's `--tables`; a missing report's
  tables are kept. The step is `PARTIAL` (❌ in the summary, exit status 2)
  and its note names both lists; the success note is now `files from today:`
  and the reports found, not the ones requested. Before this, one missing
  report failed the whole step: on Oct 25 and 26 the Academic Study download
  timed out and mrgather stopped before class lists and applicants, on Oct 27
  everything arrived but applicants, and each run published nothing (I43).
- `parse-data.R` stops, before parsing anything, when a report named with
  `-r` has no file. A run that names none still parses whatever it finds.
- `test-data-update-pipeline.R` runs the fetch step against a stand-in
  `docker` for each case.

To check a morning: `grep -E "Fetch incomplete|Fetch failed|Skipping
transform|Update Finished|Update Complete" /var/log/cedar-update-$(date -u
+%Y%m%d)_100501.log`.

---

## I32 — A scheduled refresh waits forever when MyReports asks for a 2FA code

**Status:** fixed in CEDAR 2026-11-11 (see Fix); takes effect in production
at the deploy that carries it. mrgather still waits at the prompt when run
without CEDAR's script.
**Found:** 2026-10-23, while starting a manual production refresh
**Severity:** moderate. No number is wrong. Later runs fetch normally, but a
run that hits the prompt never ends and never reports failure. It keeps its
headless browser container running, and the only sign is a log file nobody
reads.
**Affects:** the fetch step of `scripts/update-data.sh` in production mode
(`docker compose ... run --rm mrgather node mrgather.js ...`). The prompt itself
is in mrgather (`/root/mrgather`), a separate repository.

### What is wrong

The fetch runs mrgather with no time limit. If MyReports asks for a 2FA code,
mrgather prompts for one on standard input and waits. Under cron nobody can
answer, so the run waits forever.

The 05:05 cron run on 2026-10-11 (`update-data.sh -s 202660 -e 202680`) was
still running on 2026-10-23: three shell processes, a `docker compose run`
client, and container `mrgather-mrgather-run-81498ef90ea8`, all started
2026-10-11 10:05 UTC. Its log, `/var/log/cedar-update-20261011_100501.log`,
ends:

```
Prompting for 2FA code...
Screenshots and HTML saved to downloads folder (accessible outside Docker)
⚠️  There was an error with 2FA - see detailed error above
Please enter the 2FA code (or press Enter to take another screenshot):
```

The daily runs from 2026-10-12 on were not asked for 2FA and completed. So the
refresh kept working while the stuck run went unnoticed. If MyReports asked on
several days in a row, one stuck run would pile up for each day.

Two things are needed. A time limit on the compose client is not enough on its
own, because stopping the client need not remove a `--rm` container. And mrgather
should fail at once, with a clear status, when nobody is there to type a code.

*Done when:* a non-interactive fetch that meets a 2FA prompt exits non-zero
within a bounded time. Its container is removed, and the step is recorded as
`mrgather fetch FAILED` with "2FA required" in the note. The fetch also has an
overall time limit, so any other hang ends the same way. Finally,
`test-data-update-pipeline.R` fails if the production fetch command loses its
time limit.

### Reproduction

This cannot be forced, because MyReports decides when to ask for 2FA. To see
it, run the production fetch on the droplet from a shell with no terminal, on a
day MyReports asks:

```bash
setsid /root/cedar/scripts/update-data.sh -s 202680 -e 202680 </dev/null >/tmp/fetch.log 2>&1 &
# /tmp/fetch.log stops at "Please enter the 2FA code"; the process never exits
```

To check for runs already stuck:
`pgrep -fa update-data.sh` and `docker ps --filter name=mrgather-mrgather-run`.
Anything older than a day is one.

### Fix

`update-data.sh` starts the fetch container under a name
(`cedar-mrgather-fetch-<pid>`) and watches it. When the run has no terminal on
standard input and mrgather's output reaches `Please enter the 2FA code`, or
when the fetch has run for `CEDAR_FETCH_TIME_LIMIT` seconds (default 7200),
the watcher removes the container with `docker rm -f`, which also ends the
compose client. The step is then `mrgather fetch ❌` with `2FA required and
nobody at a terminal to enter the code` or `stopped after the 7200s time
limit` in its note. A run from a terminal is left at the prompt, so a person
can still type the code, and is bound only by the time limit. Production and
local runs share the one command. `test-data-update-pipeline.R` runs the step
against a stand-in `docker` that prints the prompt and waits, and one that
only waits: each is stopped, and the container removed is the one named on
the fetch command.

The prompt text is mrgather's (`mrgather.js`); if it changes, the 2FA case is
caught by the time limit instead. Not verified against MyReports, which
decides when to ask.


---

## I31 — Course paths finishes behind a stuck loading dialog

**Status: resolved (2026-10-19).** Pathways > Course paths could render its
plot and table while its blocking loading dialog remains open. The nested UI
listens on `pathways-course_paths_load_complete`, but the server passes its
local module ID to `signal_load_complete()`, sending `course_paths_load_complete`.
Custom-message channels are not automatically namespaced. The same mismatch
affects validation and error dismissal. The existing browser check found the
heatmap behind the dialog without asserting that the dialog closed.

`observedCoursePathsServer()` now uses `session$ns(NULL)` for every completion
signal. `node tests/e2e/degree-explorer.test.mjs --course-paths-only` reproduces
the original failure (plot rendered, dialog never closed) and passes all six
checks on the rebuilt image, including success, invalid campus input and a
repeated run. The full R gate passes 6,818 assertions with one existing fixture
skip. A first post-rebuild browser attempt hit its 60-second page-load timeout
during cold application startup; the focused rerun followed a completed page
load and passed with no JavaScript errors.

## I30 — Saved R workspaces entered the Docker build context

**Status: resolved (2026-10-19).** Rebuilt image inspection confirms no saved R
workspace, and the Admin browser suite passes. The ignore
file named `.Rdata`, but the host workspace is `.RData` (89 MB). Docker's
case-sensitive matcher included it in COPY and the following ownership layer.
Repeated local builds exhausted host space and Docker reported read-only
BuildKit metadata. Both spellings are now excluded. The saved workspace itself
is preserved; it is not an app dependency. Done when the rebuilt image omits it
and the normal app/browser gate passes.

## I29 — Generated navigation IDs can open the wrong panel

**Status: resolved (2026-10-19).** All 15 navigation checks and 36 Admin browser
checks pass, including forced primary-ID collisions. While verifying catalog milestones, Admin's
Data & Usage link and Explore's Gen Ed panel both rendered as `tab-7367-3`.
The link became selected but Bootstrap opened the first matching panel, Gen Ed.
The offline freshness assertion failed before Catalog Review was exercised.
The saved served HTML confirmed duplicate `tab-7367-1`, `-3` and `-4` IDs.

bslib independently samples a four-digit prefix for each `nav_menu`. The fix
assigns unique primary navbar link/panel IDs while retaining `data-value`
bindings and nested tab IDs. `www/cedar-navigation.js` runs before URL navigation
at DOM-ready; the forced collision and link/panel checks in `nav.test.mjs` guard it.

## I1 — `cedar_programs` and `cedar_degrees` were fragmented into seven student ID spaces

**Status:** resolved 2026-08-12. Repulled `as` + `deg` for 201980–202460, then
(after fixing I3) ran a full transform to land the tables in `data/`. Verified in
the app's own data directory: `cedar_programs` is **one ID space across all 25
terms**, and no table has a term that fails to join. Watch for a recurrence via
Data & Usage → Join Integrity after any future refresh.
**Found:** 2026-08-12
**Severity:** high — silently truncated every cross-table student analysis
**Affects:** `academic_studies.qs` → `cedar_programs`, `degrees.qs` →
`cedar_degrees`. Class-list-derived tables were always clean.

### Correction to the first diagnosis

This was initially recorded as *two* disjoint ID spaces, split at 202480. That
was wrong, and wrong in a way worth remembering: the first pass only ever asked
"does this term join to the class lists?", which is a test against one external
reference. It never asked whether the failing terms joined to *each other*.
Pairwise overlap within `cedar_programs` showed **seven** disjoint spaces:

| cluster | terms |
|---|---|
| 1–5 | `201980` / `202010` / `202060` / `202080` / `202110` — five singletons |
| 6 | `202160, 202480, 202510, 202560, 202580` — matched the class lists |
| 7 | `202180 … 202460` — nine terms, internally coherent, matched nothing else |

Cluster 7 had normal term-to-term persistence (89%, 84%, 87%), so it was a
healthy ID space that simply could not reach anything outside itself. That
structure confirmed the per-file mechanism below: the `2025-02-28` ingest batch
(202180–202460) stayed coherent, while the `2025-03-21` batch (201980–202160)
shattered into six spaces — one per file, with 202160 landing by luck in the
format that matched everything current.

**Lesson for the next check of this kind:** a spine comparison finds tables that
cannot join outward. It cannot see fragmentation *within* a table. Cluster the
terms by shared IDs.

### What was wrong

The hashed `student_id` in `cedar_programs` and `cedar_degrees` belonged to one
of the seven mutually incompatible spaces above, depending on which MyReports
file supplied that term. Records outside cluster 6 could not join to
`cedar_registrations` at all, and could not join to the *same student's* records in
another cluster within their own table.

Per-term match against `cedar_registrations` was never partial — exactly 0% or
exactly 100%:

| terms | match |
|---|---|
| 201980–202110, 202180–202460 | **0%** |
| 202160, 202480, 202510, 202560, 202580, 202610 | 100% |

Within `cedar_programs` alone: 37,802 ids lived in the matching terms, 133,617
across the others, and the intersection was **zero**. One person therefore
appeared under a different id in each cluster they touched, which is why the
table reported 171,419 distinct students when the class lists saw 95,542 over
the same window. It also produced 12,504 ids holding exactly one program term —
the five singleton clusters — none of which can generate a change event, since
detecting one requires two consecutive records under the same id.

The decisive check: 18,233 students appear in `cedar_registrations` at both 202410 and
202480 — same id string, same table, unambiguously the same people. Of those,
15,681 have a program record at 202480 and **zero** have one at 202410. They were
plainly enrolled and declared in 202410; those rows exist, under a different hash.

### Consequences

- Any population built from `cedar_programs` loses all class-list coursework for
  pre-202480 terms. A History population of 1,645 students resolves to 330 with
  any enrollment rows, and coverage is binary by term — 0 or 100, never between.
- `detect_major_changes()` cannot see a switch that crosses 202460 → 202480, and
  reads pre- and post-boundary records as different people. Only 1,196 of 171,419
  program ids span that boundary.
- Distinct-student counts taken from `cedar_programs` are inflated by
  double-counting.
- Credit and GPA timelines, Pathways populations, Roadblocks, and the Major
  Changes course tables all inherit the truncation.

### Root cause

The divergence is already present in the raw MD5 ids in `academic_studies.qs` and
`degrees.qs`, so it is upstream of `encrypt_if_needed()` in
`R/data-parsers/transform-to-cedar.R` — that function is deterministic and is
being fed mismatched input.

`R/data-parsers/parse-data.R` hashes only newly ingested rows (`# only encrypt new
data!`, ~line 558), so each term's MD5 is frozen at whatever the raw ID string
looked like in the file it arrived in. The file is read with a bare
`fread(csv_file)` (~line 490) with no `colClasses`, so the ID column's type is
inferred per file. A column read as numeric loses leading zeros; the same column
read as text keeps them. Same person, two different strings, two different MD5s.

That the split varies *within* a single download batch supports this: in both
`academic_studies` and `degrees`, the 2025-03-21 batch covers six terms and only
202160 matches — consistent with per-file type inference rather than a per-batch
setting.

**This can recur on any future pull** until the ID column is forced to character
at read time.

### Reproduction

In the running app: **Data & Usage → Join Integrity**. Every table should read
`consistent`; any `split` verdict is this issue, and the by-term table lists
exactly which terms need repulling.

From RStudio:

```r
check_student_id_integrity(
  spine  = load_cedar_data("data/cedar_students.qs"),
  tables = list(
    cedar_programs = load_cedar_data("data/cedar_programs.qs"),
    cedar_degrees  = load_cedar_data("data/cedar_degrees.qs")
  ),
  opt = list(spine_name = "cedar_registrations")
)$by_table
```

### What a fix requires

1. ~~Force the ID column to character at read time in `parse-data.R` so the hash
   cannot depend on type inference.~~ **Done 2026-08-12** — `fread()` now takes
   `colClasses = list(character = report_spec$ID_col)`, and a named ID column
   missing from the CSV is a hard error rather than an `fread` warning.
2. ~~Repull and re-ingest the affected terms.~~ **Done 2026-08-12** — `as` and
   `deg` for 201980–202460. Result in `shared-data/`: `cedar_programs` 616,627
   rows / 86,583 ids, one ID space across all 25 terms, zero non-joining terms;
   `cedar_degrees` likewise. Terms 201980–202610 all match the class lists at
   100%. The remaining partials are expected, not defects: 201880/201910/201960
   predate the class-list window, and 202680 is a future term whose students have
   not enrolled yet.
3. ~~Get those files into the app's `data/` directory.~~ **Done 2026-08-12** —
   the copy had never happened because of I3. A full
   `Rscript --vanilla R/data-parsers/transform-to-cedar.R` (no `--tables`; the
   copy loop only iterates the tables that run built, and nine local tables were
   stale, not two) rebuilt and copied all nine.
4. ~~Re-verify.~~ **Done** — in `data/`: 0 tables split, 0 non-joining terms,
   `cedar_programs` in a single ID-space cluster across all 25 terms.

### Result

| | before | after |
|---|---|---|
| `cedar_programs` ID spaces | 7 | **1** |
| distinct ids in `cedar_programs` | 171,419 | 86,583 |
| History population | 1,645 | 883 |
| History departures matchable to coursework | 11 of 43 (26%) | 88 of 104 (85%) |

The id count halving is the fix working: those were never 171,419 people, they
were one person counted once per cluster they touched.

### Repull list

Two MyReports reports, Fall 2019 through Summer 2024:

- **Academic Study Detail Guided** (`Academic_Study_Detail_Guided`)
- **Graduates and Pending Graduates** (`Graduates_and_Pending_Graduates`)

Not needed: Class Lists (the consistent spine, and what everything else is
matched against), DESRs (carries no student ids), Admissions Applicants (already
consistent across all terms).

`parse-data.R` replaces refreshed terms in place, so these can be ingested
without deleting the existing files. Do **not** delete `academic_studies.qs` or
`degrees.qs` to force a rebuild unless every term is being repulled in the same
run — `rebuild = TRUE` fires only when no previous file exists, and would drop
whatever terms are missing from the new pull.

```bash
./scripts/update-data.sh -s 201980 -e 202460 as deg
```

Safe to run in chunks if MyReports struggles with 15 terms — each run replaces
only the terms it fetched.

---

## I2 — `update-data.sh` same-day skip check could not fire for three reports

**Status:** resolved 2026-08-12
**Found:** 2026-08-12
**Severity:** low — failed toward re-fetching, never toward stale data
**Affects:** `scripts/update-data.sh`

### What was wrong

Step 1 skips the MyReports fetch when files for today are already on disk. The
globs it checked had drifted from the filename signatures `parse-data.R`
actually matches on:

| report | glob checked | real signature |
|---|---|---|
| `deg` | `*Degrees*` | `Graduates_and_Pending_Graduates` |
| `as` | `*Academic_Studies*` | `Academic_Study_Detail_Guided` |
| `aa` | *(absent from the case statement)* | `S_Admissions_Applicants_Detail` |

So the check could never succeed for degrees or academic studies, and `aa` fell
through to the unknown-report branch, which logged a warning and `continue`d
without touching `SKIP_FETCH`.

The consequence was only wasted downloads — a failed check leaves `SKIP_FETCH`
false, which fetches. But the `aa` path was the dangerous shape: a report that
falls through the case statement leaves `SKIP_FETCH` at whatever the other
reports set it to, so a request for `aa` alone would have skipped the fetch on
the strength of a check that never ran.

### Fix

Globs now use the exact `filename_sig` strings, `aa` has a branch, and the
fallback branch sets `SKIP_FETCH=false` so an unrecognized report always fetches
rather than trusting a check that could not run. A comment on the block names
`report_specs$<report>$filename_sig` in `parse-data.R` as the thing to keep it in
sync with.

Both sides are still hand-maintained in two languages. If they drift again the
symptom is silent — a redundant download, or in the fallback case a skipped one.
Worth deriving from one source if the parser ever gains more reports.

---

## I3 — `cedar_data_dir` pointed at a nonexistent directory; pipeline output never reached the app

**Status:** resolved 2026-08-12 (config fix). Local `data/` still needs one
transform run to pick up the files it missed.
**Found:** 2026-08-12
**Severity:** high — every data refresh silently had no effect on the app
**Affects:** `config/config.R`, `config/config_template.R`

### What was wrong

```r
cedar_base_dir <- ".../cedar-project/cedar"        # no trailing slash
cedar_data_dir <- paste0(cedar_base_dir, "data/")  # → ".../cedar-project/cedardata/"
```

The template's comment said `cedar_base_dir` "should end in /cedar/", which is
ambiguous about the trailing slash, and `paste0` silently concatenates without
one. The result was a path that does not exist.

`transform-to-cedar.R` guards its copy step with `dir.exists(local_data_dir)`
and, when that fails, prints `⏭ Skipping local data copy (directories not
configured or not found)` and continues. The step is not counted as a failure,
so `update-data.sh` reported every stage ✅ and a green **CEDAR Update
Complete** while the app went on reading whatever was already in `data/`.

This is how the 2026-08-12 repull that fixed I1 appeared to do nothing: it
worked, wrote correct tables to `shared-data/`, and never copied them. Nine
tables in `data/` were stale, some since 2026-08-05, for the same reason.

`config/shiny_config.R` builds the same path with `file.path()`, so the app
resolved `data/` correctly. Only the pipeline's copy target was wrong — which is
exactly why nothing looked broken.

### Fix

Both configs normalize the base with `sub("/+$", "", ...)` and build the
directories with `file.path(cedar_base_dir, "data/")`. The trailing slash is
kept deliberately: `parse-NSO.R` and `parse-HRreport.R` append to these with
`paste0()` and would produce `.../dataHRreports` without it.

The copy step is now loud. `transform-to-cedar.R` distinguishes three cases
instead of two: Docker (skip, correct), no local directory configured at all
(skip, also correct — nothing was asked for), and **configured but missing**,
which now `stop()`s with a message saying the tables were written to
`shared-data/` and no work was lost. A failed `file.copy()` is fatal too: a
half-refreshed `data/` mixes current and stale tables, which is unjoinable in
exactly the way this whole issue was about.

---

## I4 — Pre-change course ratios are confounded by career stage

**Status:** open, deliberately deferred 2026-08-12 (see "Why not now")
**Found:** 2026-08-12
**Severity:** moderate — the number is not wrong, but it invites a wrong reading
**Affects:** `get_pre_change_courses()` in `R/cones/major-changes.R`; surfaced as
the **Times as likely** column in Pathways → Major Changes → Courses in the Term
Before Students Left

### What is wrong

The ratio compares a course's share in the term before a switch against its
share in a typical term for the population. The baseline averages over students
at *every* career stage, but switches are not evenly distributed across a
career — they cluster early. So any lower-division course is over-represented
before a switch for a reason that has nothing to do with switching, and the
ratio reads that as concentration.

### Evidence

History population, 2026-08-12, `min_n = 5`. Every course clearing the threshold
is 1000-level; not one upper-division course appears:

| course | last term | typical | ratio |
|---|---|---|---|
| ENGL 1110 Composition I | 11.4% | 2.1% | 5.5× |
| SOCI 1110 Intro Sociology | 5.7% | 1.1% | 5.1× |
| MATH 1130 Survey of Mathematics | 6.8% | 1.4% | 4.9× |
| MATH 1350 Intro Statistics | 6.8% | 1.8% | 3.9× |
| SPAN 1110 Spanish I | 9.1% | 2.4% | 3.8× |
| HIST 1110 United States History I | 11.4% | 3.2% | 3.5× |
| ENGL 1120 Composition II | 8.0% | 3.6% | 2.2× |
| HIST 1150 Western Civilization I | 5.7% | 2.9% | 2.0× |

Read literally this says Composition I makes people leave History. What it
actually says is that these students were freshmen.

### Why not now

The all-1000-level result is self-evident. A reader looking at that list can see
what is happening without being told, and the section already carries an
interpretive caveat naming career stage specifically.

**Revisit when that stops being true.** The deferral rests on the confound being
visible, so the case to watch for is a population that returns a *mixed* list —
some upper-division courses among the lower-division ones. There the confound is
invisible, the surviving upper-division rows look like the real signal, and
nothing on the page tells the reader which is which. If someone reports a
surprising course from this table, check its level first.

### Possible fix

Compare each switch against baseline terms at a similar career position rather
than against all terms — match on term index (student's nth term) or on the
credit band from `build_credit_timeline()`, and compute the ratio within strata.
Costs statistical power, since each switch then draws on a slice of the baseline
rather than all 26,540-odd student-terms, and small populations may end up with
no usable comparison at all. An alternative that keeps the power is to leave the
ratio as it is and add a course-level column, so the reader can see at a glance
that the top of the list is entirely lower-division.

Whichever way it goes, `R/modules/pathways.R` (section caveat) and Methodology
Step 6 both describe the current unadjusted comparison and would need updating.

---

## I5 — Every 4-digit 3000/4000-level course is classified `lower`

**Status:** resolved 2026-10-03. Both transforms now call one classifier,
`course_level_from_number()` (`R/trunk/utils.R`), which reads the leading digit
through `COURSE_LEVEL_BY_LEADING_DIGIT` (`R/lists/course_numbering.R`). Rebuilding
`cedar_sections` moved exactly the 1,355 4-digit 3000/4000-level sections to
`upper` and gave the 1,609 sections numbered 700-999 the `grad` level the class
lists already used; sections and class lists now agree on every course. It had
grown sharply: Fall 2026 alone had 289 misclassified sections, after Business
(BUSA), Accounting (ACCT) and Population Health (POPH) renumbered to 4 digits,
joining Nursing (NMNC, since Fall 2024). An architecture test now requires both
transforms to use the classifier.
**Found:** 2026-09-05 (while reconciling the synthetic demo institution with the
browser gate — the Open Seats step asked for `upper` and the fixture's
`HIST 3010` was not in the result)
**Severity:** moderate — silent wrongness. The value is plausible, so nothing
errors and nothing looks unusual; upper-division work is simply counted as
lower-division wherever `level` is used.
**Affects:** `level` in `cedar_sections`, derived in `R/data-parsers/transform-to-cedar.R`
(the DESR branch, ~line 295). Every surface that filters or groups on `level`:
Open Seats, Enrollment, Credit Hours (`credit_hours_data$level`), Dept Trends,
and any `opt$level` filter.

### What is wrong

The rule is ordered so that a 4-digit number can never reach the upper or grad
branches:

```r
level = dplyr::case_when(
  crse_base < 300                    ~ "lower",
  crse_base >= 1000                  ~ "lower",   # <- catches ALL 4-digit courses
  crse_base >= 500 & crse_base < 700 ~ "grad",
  crse_base >= 300 & crse_base < 500 ~ "upper"
)
```

The `>= 1000` branch was written for UNM's 4-digit renumbering, where `1110` is
genuinely lower-division. But it fires for `3010` and `4445` too, before the
`upper` branch is ever evaluated. Under the 4-digit scheme the bands are
1000–2999 lower, 3000–4999 upper, 5000+ grad; only the first is handled.

### Evidence

Against `data/cedar_sections.qs` (2026-08-13 snapshot), 40,948 sections carry a
4-digit course number:

| course number band | assigned `level` | sections |
|---|---|---|
| 1000–2999 | `lower` | 39,597 (correct) |
| 3000–4999 | `lower` | **1,351 (should be `upper`)** |

No 4-digit course is ever assigned `upper` or `grad`. Misclassified examples are
concentrated in units already renumbered — `NMNC 3220`, `NMNC 3120`,
`NMNC 4445`, `NMNC 4545`, `NMNC 3235` (Nursing).

The aggregate distribution looks healthy (grad 108,342 / lower 59,065 / upper
73,273), which is why this survived: most of the data is still 3-digit, so the
totals are not obviously skewed and only the renumbered units are wrong.

### Reproduce

```r
Rscript --vanilla -e '
suppressMessages({library(qs2); library(dplyr)})
qs_read("data/cedar_sections.qs") %>%
  filter(grepl(" [0-9]{4}", subject_course)) %>%
  mutate(num = as.integer(sub("[A-Z]$", "", sub(".* ", "", subject_course)))) %>%
  filter(num >= 3000, num < 5000) %>%
  count(level)'
# -> level = "lower", n = 1351
```

### What a fix requires

Reorder so the 4-digit bands are handled explicitly rather than collapsed into
one `lower` branch — 1000–2999 lower, 3000–4999 upper, 5000–6999 grad — while
keeping the existing 3-digit bands (<300 lower, 300–499 upper, 500–699 grad).
Note the class-list branch at ~line 682 uses a *different*, regex-based rule
(`[0-2]` lower, `[3-4]` upper, `[5-9]` grad) that reads the leading digit and so
already gets 4-digit courses right; the two rules disagree, and the fix should
reconcile them rather than patch one.

This changes counts on every level-filtered surface, so it needs a transform
rerun and a check of the level-dependent tests and cached artifacts, not just a
one-line edit.

### Known dependents

`tests/e2e/reports-smoke.test.mjs` selects `lower` in two synthetic steps
because the fixture's upper-division courses currently classify that way:

| step | course | true level | classified |
|---|---|---|---|
| Open Seats | `HIST 3010` | upper | `lower` |
| Cancellations | `PSYC 3200` | upper | `lower` |

Fixing this issue must flip both selections back to `upper`. Both are commented
at the call site with a pointer here.

---

## I6 — A killed projection rebuild strands its lock and blocks every later refresh

**Status:** resolved 2026-11-11 (branch `projections/stale-lock-recovery`; see
Fix)
**Found:** 2026-09-08 (while adding Fall targets, which roughly doubles the work
one rebuild does and turns this from theoretical into likely)
**Severity:** moderate — silent stoppage. Projections quietly stop updating; the
page keeps serving the last good bundle, so nothing errors and nothing looks
wrong until someone notices the numbers are stale.
**Affects:** `run_projection_auto_refresh()` and `run_projection_rebuild_request()`
in `scripts/build-enrollment-projections.R`; the deploy step in
`.github/workflows/deploy.yml`.

### What is wrong

Both refresh entry points take a lock by creating a directory
(`output/projections/rebuild-request.yml.lock`) and release it with `on.exit()`.
`on.exit()` does not run when the process is killed rather than returning — a
`command_timeout` expiring on the deploy's SSH session, a dropped connection, an
OOM kill, or a `docker compose run` interrupted mid-build. The directory then
stays forever, and every subsequent refresh fails closed:

```
[projections] Rebuild already running or stale lock: .../rebuild-request.yml.lock
```

Failing closed is correct — the alternative is two concurrent builds writing the
same bundle — but nothing ever clears the lock, so the stoppage is permanent
until someone removes the directory by hand.

This is the same shape as the stranded `restarting.flag` fixed in `7cdf09b`: an
EXIT trap that a killed session never runs.

### Reproduction

```bash
Rscript --vanilla scripts/build-enrollment-projections.R --refresh &
sleep 30 && kill -9 %1          # simulate the timeout / dropped session
ls output/projections/rebuild-request.yml.lock   # still there
Rscript --vanilla scripts/build-enrollment-projections.R --refresh
# -> [projections] Rebuild already running or stale lock
```

### What a fix requires

Write the owning PID and a start timestamp into the lock directory, and treat a
lock as stale when its process is gone or it is older than a bounded maximum
build time. Clearing on age alone is not enough: a legitimate build can outlive
any fixed guess, which is how a stale-lock heuristic ends up running two builds
at once against the same output path. Deploy-side clearing before taking the
lock is not safe either, because a deploy can overlap the morning refresh.

Raising `command_timeout` to 60m (this change) reduces how often the kill
happens; it does not fix the stranding.

Since 2026-10-11 (I19) the error tells a held lock from an unwritable
directory and says when the lock was created, so a stranded lock is easier to
recognise.

### Fix

The owner's PID cannot decide it: the morning refresh and the deploy each
build in their own `cedar-projections` container, and one container cannot see
another's processes. What they share is the lock's directory. So
`take_projection_lock()` starts a shell loop beside the build that touches
`heartbeat` in the lock every 30 seconds for as long as the owning R process
exists and still holds the lock. A kill of the process, or of its container,
stops the heartbeat. A killed process that nothing has collected is a zombie,
on which `kill -0` still succeeds, so on Linux the loop reads the state from
`/proc` and counts a zombie as gone (the first version did not, and CI's
container, which has no init, kept a dead build's heartbeat going). A run that finds a lock whose heartbeat is
more than 600 seconds old takes it over and says so; a live build keeps its
lock however long it runs. Two runs that find the same dead lock race for one
`takeover-<heartbeat time>` directory, which exactly one can create. A lock
with no heartbeat file is from a build before this change and is stale only
after six hours. `release_projection_lock()` removes only a lock its caller
still owns.

`test-projection-refresh.R` runs the reproduction above: a second R process
takes the lock and is killed with SIGKILL. While it lives, a lock older than
the stale limit is refused; after the kill and the limit, the next run takes
it over. Without the heartbeat the takeover assertion fails.

`scripts/build-enrollment-projections.R` is projection model source, so the
deploy that carries this rebuilds both bundles once.

---

## I7 — Health pre-major codes get a phantom department, hiding most of a program's students

**Status:** resolved 2026-10-09 by ADR-002 Stage 3: the transform takes every unit from the mapping files, and a code with no confirmed row has no unit instead of a department named after itself. Codes still awaiting a decision are listed on Admin > Data & Usage > Mappings. (Health pre-majors fixed 2026-09-09.)
**Found:** 2026-09-09 (while resolving named population groups to Banner codes for
the projection growth scenario)
**Severity:** high — silent wrongness at the department level. Nothing errors and
nothing appears in `cedar_mapping_issues`, because the row *is* mapped: to a
department that does not exist.
**Affects:** `dept_code` in `cedar_programs` for `FRAD`, `FDEH`, `FEMS`, `FMDL`,
`XFDE`. Every surface that groups or filters on `dept_code`: Headcount, Dept
Trends, Dept Dashboard, population building by `type = "dept"`.

### What is wrong

`premaj_canon` (`R/lists/program_code_maps.R`) maps pre-major F-codes to the
major they lead to — `FNRS` → `NURS`, `FPOH` → `POHE`, and 90-odd others. Four
health pre-majors are missing from it. They are still detected as pre-majors
(`is_pre_major = TRUE`), so the gap is not visible there; they simply fall
through to the last resort in the documented `dept_code` chain, *the major code
itself*, and land in a department named after the pre-major code.

Fall 2026 counts, by `dept_code`:

| Program | Declared | Pre-major | Pre-major lands in | Share of program hidden from its own dept |
|---|---|---|---|---|
| Radiologic Sciences | `RADS` 35 | `FRAD` 194 | dept `FRAD` | **85%** |
| Dental Hygiene | `DEHY` 108 | `FDEH` 163 (+`XFDE` 1) | dept `FDEH` | **60%** |
| Emergency Medical Services | `EMS` 71 | `FEMS` 114 | dept `FEMS` | **62%** |

A dean asking for Radiologic Sciences headcount is shown 35 students out of 229.

**Why nothing flagged it.** `cedar_mapping_issues` collects rows with *no*
department owner. These rows have one — it is just wrong. The fallback that makes
`dept_code` total is exactly what stops this from being reported.

### Reproduction

```r
source("scripts/cedar-repl.R")
c("FRAD", "FDEH", "FEMS", "FMDL") %in% names(premaj_canon)          # all FALSE
c("FRAD", "FDEH", "FEMS", "FMDL") %in% allowed_unmapped_program_codes # all FALSE
cedar_programs %>% filter(term == 202680L, program_name == "Radiologic Sciences") %>%
  count(dept_code, is_pre_major)          # FRAD 194 / RADS 35
```

### Correction to the first diagnosis (2026-09-09)

**The missing `premaj_canon` entries are a symptom, not the cause.** The cause is
that `program_map.qs` is **stale**: it was generated 2026-06-17 from that day's
`academic_studies` export, while `cedar_programs` is built from the current one.
Every program that first appeared after June therefore has no row in the map, so
Tiers 1 and 3 of the `dept_code` chain both miss, Tier 2 misses (these are not
subject codes), and Tier 4 — the identity fallback — hands the student a
department named after their own program code.

Two exports exist and they are not the same file:

| Path | Date | Size |
|---|---|---|
| `data/academic_studies.qs` (what `cedar_data_dir` points at) | 2026-06-17 | 16.6 MB |
| `<CEDAR_DATA_DIR>/academic_studies.qs` | 2026-09-07 | 21.1 MB |

So a regenerate run locally silently reproduces the stale map. Regenerating from
the **current** export fails loudly, correctly, on every program added since June.

**The full scope is 15 codes, not 4.** Beyond the four health pre-majors, these
11 are in phantom departments right now (214 student-term rows), each needing a
department owner before the map can be regenerated:

| Program code | Name | College | Major code |
|---|---|---|---|
| `CERT-AAHS-GA` | Human Services | Undergrad Cert (Gallup) | `AAHS` |
| `BA-FS-AS` | Family Studies | Arts & Sciences | `FS` |
| `BS-ECME-ED` | Early Child Multicult Educ | Education | `ECME` |
| `BA-DFP-FA` | Design for Performance | Fine Arts | `DFP` |
| `MCM-CMGT` | Construction Management | Graduate | `CMGT` |
| `MS-CLSC` | Clinical Laboratory Science | Graduate | `CLSC` |
| `BA-FILA-HC` | Pre-Interdisc Liberal Arts | Honors | `FILA` |
| `CERT-HHHA-TA` | Holistic Health & Healing | Undergrad Cert (Taos) | `HHHA` |
| `CERT-MDRC-GA` | Health Info Tech Coding | Undergrad Cert (Gallup) | `MDRC` |
| `PHD-EDST` | Education Studies | Graduate | `EDST` |
| `GCERT-GLPO` | Glob & Nat Secur Policy | Graduate | `GLPO` |

### Resolved, 2026-09-09

`program_map.qs` regenerated from the September export (555 rows, up from the
stale 523) and `cedar_programs` rebuilt. Department headcounts at Fall 2026:

| Department | Before | After |
|---|---:|---:|
| `RADS` | 35 | **230** |
| `DEHY` | 108 | **272** |
| `EMS` | 71 | **185** |
| `MEDL` | — | **115** |

The screens confirm the change scoped to what was mapped: pre-major phantoms
22 → 16, identity-fallback 72 remaining. Those 88 are a genuine backlog and are
now visible in Admin > Data & Usage > Mappings rather than invisible.

**Three traps cost time here; all are now documented in
[data-anomalies.md](docs/developers/data-anomalies.md).**

1. **Two `academic_studies.qs` exist.** The transform reads
   `cedar_shared_data_dir` (current) while `cedar_data_dir` is the repo's local
   copy, which was nine months stale. A regenerate pointed at the wrong one
   silently reproduces the old map.
2. **`transform_to_cedar()` skips the regenerate when `program_map` already
   exists in the session,** and `load_funcs()` defines it. Any script that loads
   CEDAR functions first rebuilds against the stale in-memory map and reports
   success. This is what made the first rebuild attempt a no-op.
3. **Do not move the map aside to force a regenerate.** The running app reads
   `program_map.qs` from the shared data directory; removing it breaks startup.
   Generate and save the new map first, then rebuild.

### Remaining backlog as of 2026-09-09 (all visible in Admin > Data & Usage > Mappings)

**570 students across 27 programs.** Every item below appears on the Admin
Mappings tab; none of it is silent any more. Ranked by students, majors only —
minors and the selective-admission screen are excluded because they are not
mapping work. See [mapping-review-guide.md](docs/developers/mapping-review-guide.md)
for how to resolve one.

| Code | Students | Program | Likely resolution |
|---|---:|---|---|
| `FPMD` | 184 | Doctor of Pharmacy (pre) | → `PHRM`, unconfirmed |
| `FLIB` | 89 | Liberal Arts (pre) | → `LAIS`, by analogy with `FLAI`; unconfirmed |
| `GSCI` | 60 | General Science | possibly `department_less_major_codes` |
| `EAST` | 42 | East Asian Studies | needs catalog |
| `FCOE` | 37 | Construction Engineering | blocked on the `E` suffix below |
| `ASPE` | 32 | Engineering | possibly `department_less_major_codes` |
| — | ~126 | 21 programs under 30 students each | low value, can wait |

**Open question — the `E` college suffix.** `BSCNE-CONE-E` and `BSCNE-FCOE-E`
are still discarded because `E` is not in `known_suffixes`. `BSCNE` is
Construction Engineering, so `E` looks like a truncated `EN`, but a data-entry
variant and a real code are indistinguishable from the data. Adding it wrongly
would file those students in Engineering on a guess. They are listed on the
Admin tab as `program_dropped_unknown_college_suffix`.

### Two flaws in the loud failure itself

Both fixed while diagnosing this, because they made the error unusable:

1. `unexpected` is a tibble when `academic_studies` is read from `.qs`, and
   `print.tbl_df` rejects `row.names = FALSE` — so the message whose whole job is
   to name the unmapped codes threw a formatting error instead of listing them.
2. The list is truncated at R's 1000-character `warning.length`, which cuts it
   off mid-code. Raise the option when regenerating, or read the list another way.

### Related: the name for `FMDL` does not match its own major

`FMDL` carries `program_name = "Medical Laboratory Science"` while `MEDL` carries
`"Medical Laboratory Sciences"`. Any grouping that matches programs *by name*
silently splits that pair, which is the mirror image of this bug — so a fix must
not simply move everything to name matching.

### What a fix requires

1. The four `premaj_canon` entries (`FRAD` → `RADS`, `FDEH` → `DEHY`,
   `FEMS` → `EMS`, `FMDL` → `MEDL`) and `XFDE` → `DEHY` in `xvar_explicit`.
   **Done.**
2. A department owner for each of the 11 programs above. **Seven mapped** in
   `extra_p2d` with the reasoning recorded per entry; **four still open** and
   listed under NEEDS RESEARCH in `allowed_unmapped_program_codes`
   (`BS-ECME-ED`, `BA-FS-AS`, `MCM-CMGT`, `CERT-HHHA-TA`). Those four are
   parked, not answered: their students have no department today.
   Two of the seven — `CLSC` → `MEDL` and `DFP` → `THEA` — are reasoned rather
   than certain and are worth confirming with IR.
3. Regenerate `program_map.qs` from the **current** export, not the stale local
   copy, and rebuild `cedar_programs`. **Not yet done** — this rewrites a
   durable artifact and every dept-scoped surface changes when it lands.
   A dry run against the current export now succeeds: 555 rows against the
   stale map's 523, with all five health codes resolving correctly.
4. Close the hole that hid all of it: a pre-major whose resolved `dept_code`
   equals its own `major_code` should be reported in `cedar_mapping_issues`.
   Tier 4 exists so `dept_code` is never NA, but for a pre-major that outcome is
   always a mapping failure rather than a real department, and today it is
   indistinguishable from a correct answer.
5. Reconcile the two lists that both decide which F-prefix codes are real
   programs — `real_F_progs` in `program_code_maps.R` and the inline exclusion
   vector in `transform_to_cedar()`. They disagree today (`FCS` is in one and not
   the other), which is a separate latent defect in the same area.


### Update 2026-10-02: the backlog is 57 self-named departments, not a handful

GitHub #100 (LCL undercounted) traced to `BA-EAST-AS`, East Asian Studies. It
was on `allowed_unmapped_program_codes` as "no defensible owner", so the Tier 4
identity fallback filed its majors under a department named `EAST`, while its
own pre-major `FEAS` resolved to LCL. LCL confirmed ownership, and it is now
`EAST="LCL"` in `extra_p2d`. Comparative Literature & Cultural Studies
(`CLCS`, BA and MA, with pre-major `FCLC`) had been mapped to ENGL and is also
LCL's. Together, LCL majors for Fall 2026 went from 71 to 91 undergraduate and
from 5 to 14 graduate, the "grad majors are very low" in the report.

The same screen run across all of `cedar_programs` since Fall 2024 found
**59 `dept_code` values that are not departments in `subj_dept_map`**. Two are
legitimate (`NOND`, `UNDC`, already in `department_less_major_codes`). The other
57 are programs reported under a department named after their own code, so their
students count toward no real department. Largest by student-terms: `ART` minor
(572), `ASL` minor (430), `FPMD` Doctor of Pharmacy (384), `MLST` Military
Studies (384), `ALB` Arts Leadership & Business (197), `GAMG` Gaming (161),
`FOAN` Forensic Anthropology (128), `NLL` Navajo Language & Linguistics (115),
`PBSV` Public Service (109), `BLE` Bilingual Education (93), `ATHC` (86),
`FLHC` (85), `DSTM` (81), `FCOE` (66), `GSCI` (62), then a long tail. Several
are minors only, which no `extra_p2d` entry ever covers.

**Correction (2026-10-03):** these are not invisible. The Admin > Data &
Usage > Mappings panel runs `detect_identity_fallback_departments()` and
`detect_pre_major_self_mapping()` at runtime against `subj_dept_map`, and on
current data it lists 70 identity-fallback programs and 14 self-mapped
pre-majors, with a summary line saying they name departments that do not exist.
Item 4 above is effectively done. What does NOT list them is the *startup*
`cedar_mapping_issues` table, and `cedar_lookups$dept_name_lookup` treats them
as departments (`EAST` was in it), so an ad-hoc check against the lookup passes.
**Check against `subj_dept_map`, never `dept_name_lookup`:**

```r
source("scripts/cedar-repl.R")
cedar_programs |>
  dplyr::filter(term >= 202480, !is.na(dept_code),
                !dept_code %in% unique(subj_dept_map$dept_code)) |>
  dplyr::count(dept_code, major_code, program_name, program_type, sort = TRUE)
```

Each needs an owning department from someone who knows the unit, or a place on
`department_less_major_codes` if genuinely none exists. The panel's own gap was
error handling: it sat in `server.R` inside a `tryCatch` that returned only the
startup rows when a screen failed, so a broken screen would have read as "no
mapping issues". It is now `build_admin_mapping_issues()` in
`R/features/admin.R`, which fails loudly and is tested.
---

## I8 — A timing-log row is silently dropped when the write lock times out

**Status:** resolved 2026-11-11 (branch `logging/timing-row-not-dropped`; see
Fix)
**Found:** 2026-09-09 (test-logging.R failed once during a run that was competing
with a Docker image build; it passes 3/3 in isolation)
**Severity:** low — telemetry only. No analytical table is affected. But the loss
is silent, which is why it is written down rather than shrugged off.
**Affects:** `with_timing_log_lock()` and `end_report_timer()` in
`R/trunk/logging.R`; the usage/timing figures on Admin > Data & Usage.

### What is wrong

`with_timing_log_lock()` waits up to **2 seconds** for the lock directory and
then `stop()`s. Callers reach it through `end_report_timer()`, which in the
failing test runs inside `parallel::mclapply(...)` whose result is discarded —
so the error is captured by the worker, thrown away, and the row never lands.

Observed: 8 concurrent workers, 7 rows written, `worker_4` missing, with no
error surfaced anywhere.

In production the same shape occurs whenever several sessions finish a report at
once on a loaded machine. The consequence is under-counted usage, not wrong
analytics.

### Reproduction

Run the suite while the machine is saturated (a container build is enough):

```r
testthat::test_file("tests/testthat/test-logging.R")
# "concurrent workers append complete timing rows" fails: nrow(written) == 7
```

It passes reliably when the machine is idle, which is what makes it a flake in
appearance and a race in fact.

### What a fix requires

Decide what a failed timing write should do, and make it explicit either way.
Either retry with backoff past a longer deadline, or let the write fail loudly
enough that the count is known to be incomplete. What it must not do is what it
does now: raise an error into a context that discards it. Note that the 2-second
timeout is itself reasonable — a report-timing write should not block a user
session — so the fix is about the swallowed error, not the deadline.

### Fix

The wait stays at 2 seconds. A row that cannot take the lock in that time is
written whole to its own file in `<log>.pending/` (a temporary name, then a
rename, so a file seen there is complete) instead of being dropped.
Whoever next holds the lock, the next row from any worker or the next start
(`init_logging()`), appends the pending rows and removes their files; one
merger at a time, so no row lands twice. Both timing logs (report and
browser-render) write through the one function, `append_timing_row()`. A reset
clears pending rows with the history. Until that next write, Admin > Data &
Usage is short by the rows still pending.

`test-logging.R` holds the lock while a report finishes: the row waits, lands
first with the next report's row, keeps its JSON parameters intact, and is
not written again by the write after that.

---

## I9 — `real_F_progs` lists codes the transform treats as pre-majors

**Status:** resolved 2026-10-10 by ADR-002 Stage 4: both lists are retired.
`is_pre_major` is read per code from `programs.csv`, checked against Banner's own
program records; `FCS` resolves to CS through its row. Narrowed 2026-09-09 after
`pre_major_basis` made the evidence readable; **the original diagnosis on this
entry was wrong; it is corrected below.**
**Found:** 2026-09-09 (platform/institution boundary audit)
**Severity:** moderate for `FCS`, which has a demonstrated consequence; unproven
for the rest.
**Affects:** `real_F_progs` in `R/lists/program_code_maps.R`, consumed by
`generate_program_map()` when deciding `prog_type`.

### Correction to the first diagnosis

This was filed claiming `real_F_progs` and `pre_major_exempt_codes` "answer the
same question and disagree", over 23,272 rows, and that `is_pre_major`
contradicted itself. **All three claims were wrong**, and the `pre_major_basis`
column added the same day shows why.

The two lists serve different consumers and different questions:

| Constant | Consumer | Question |
|---|---|---|
| `real_F_progs` | `generate_program_map()` | is this F-code a real program for `prog_type` and department routing? |
| `pre_major_exempt_codes` | `transform_programs()` | for this F-code, should the NAME decide pre-major status rather than the F-prefix? |

`pre_major_exempt_codes` is **correct and load-bearing**. For every code on it,
`pre_major_basis` is `name_prefix` or absent — the code convention never fires —
and the splits are real rather than contradictory:

| Code | Named `Pre-` | Not named `Pre-` |
|---|---:|---:|
| `FDMA` Film and Digital Arts | 0 | 4,664 |
| `FES` Exercise Science | 4,015 | 1,040 |
| `FFDA` | 3,423 | 987 |

Removing the exemption would misflag all 4,664 declared Film and Digital Arts
majors as pre-majors. What looked like self-contradiction was Banner correctly
recording that some students under a code are pre-majors and some have declared.

### What is actually wrong

`real_F_progs` contains four codes that the transform classifies as pre-majors
in **every** row:

| Code | Rows, all pre-major | Basis | Degrees awarded |
|---|---:|---|---:|
| `FCS` Computer Science | 6,121 | code convention | **0** |
| `FCST` Family & Child Studies | 3,223 | name + code | 394 |
| `FREN` French | 762 | name + code | 45 |
| `FRST` French Studies | 22 | name + code | 4 |

`FDMA` and `FS` are consistent — never flagged pre-major, and they award degrees.

**`FCS` is the proven defect.** It awards no degrees, `premaj_canon` declares it
leads to `CS`, and every one of its 6,121 rows is a pre-major — yet
`real_F_progs` tells `generate_program_map()` it is a real program, so it never
receives its canonical mapping. Those students sit in a phantom `FCS` department
(ISSUES.md I7), which is separately complicated by `FCS` also being the genuine
code for the Family and Child Studies department.

The other three award degrees while being flagged pre-major in every row, which
suggests the declared form of those programs carries a different `major_code`.
That needs catalog knowledge, not more querying.

### What a fix requires

Remove `FCS` from `real_F_progs` and confirm it then resolves through
`premaj_canon["FCS"] == "CS"` — noting the department-code collision means it may
also need a `major_college_to_dept` entry keyed on the Engineering college.
Review `FCST`, `FREN` and `FRST` against the catalog: either they belong in
`real_F_progs` and the transform is over-flagging them, or they do not and the
degrees are awarded under a different code.

Do **not** merge the two constants. They are not duplicates.


---

## I10 — `renv::activate()` in parse-data.R took production down

**Status:** resolved 2026-09-10 (the call is removed and an architecture test
prevents its return); the `--vanilla` asymmetry it exposed is also fixed
**Found:** 2026-09-10, production outage during a data refresh
**Severity:** critical — the app was down. Every `library()` call in the
pipeline failed after the activation.
**Affects:** `R/data-parsers/parse-data.R`, and the production branch of
`scripts/update-data.sh`.

### What happened

`parse-data.R` opened with:

```r
tryCatch({
  if (requireNamespace("renv", quietly = TRUE) && !nzchar(Sys.getenv("RENV_PROJECT"))) {
    renv::activate()
  }
}, error = function(e) warning("renv activation failed; using system packages"))
```

Inside the container, `renv/library` is **empty** — the image installs the
pinned package set into `/usr/local/lib/R/site-library` at build time via
`scripts/r-environment.R restore-docker`, and `renv/` arrives only because the
Dockerfile copies the repository. Activating therefore repointed `.libPaths()`
at a directory with no packages in it, and every `library()` call after that
point failed.

**The `tryCatch` gave false comfort.** It catches errors *from* `activate()`,
but `activate()` succeeds — it does exactly what it was asked to. The failures
come afterwards, from consumers, and were never caught.

### Why it reached production and not a dev machine

`update-data.sh` already knew this call was dangerous and guarded against it —
in one branch only:

| Branch | `--vanilla` | `RENV_PROJECT` | Result |
|---|---|---|---|
| Local dev | yes | yes | activation skipped |
| **Production Docker** | **no** | **no** | **activation runs** |

The workaround was applied where the problem was first noticed and never to the
path that actually ships. Both guards are documented in the script's own header
as protecting against exactly this call.

### Why renv was there at all

It was a leftover. Every other part of CEDAR had already moved off runtime
activation: `.Rprofile` states "Startup never installs packages or activates
renv's old cache-linked library", `AGENTS.md` says there is no runtime
activation, and `scripts/r-environment.R` is the only sanctioned setup path.
This one call survived the migration, and the caller was patched around it
instead of it being deleted.

### Fix

1. The call is removed. `scripts/r-environment.R` remains the only file allowed
   to touch renv, and `tests/testthat/test-architecture.R` now fails on any
   `renv::activate/deactivate/restore/load` call elsewhere.
2. All eight container R invocations in `update-data.sh` now use `--vanilla`,
   matching the local branch, so the two paths cannot diverge again.

### The general lesson

A guard applied to the path where a bug was noticed, rather than to the bug, is
a guard that will be missing from the path that matters. The asymmetry sat in
the script header describing itself for months.

---

## I11 — Concentrations are assigned to departments by name, so PADM borrows Political Science students and misses its own

**Status:** resolved 2026-10-10. ADR-002 Stage 3 gives every concentration
row in `cedar_programs` the unit of the student's primary major, and with I15's
fix Headcount reads that unit rather than matching the concentration's name.
**Found:** 2026-10-02, auditing SPA (PADM) program mappings after an MHA request
**Severity:** low — single-digit students per term — but it misattributes
students across departments, and the same mechanism applies to every concentration
**Affects:** the Headcount explorer and any headcount built through
`add_headcount_dept_fields()` (`R/branches/headcount.R`), which assigns a
department by joining `program_name` to `cedar_lookups$program_name_lookup`.

### What is wrong

Concentration rows in `cedar_programs` carry no `major_code`, so their
`dept_code` is NA and headcount falls back to matching the concentration's
**name** against the program-name lookup. That lookup is built from majors, so
a concentration inherits whatever department owns a *major* of the same name:

| Concentration | Actually held by | Name lookup says |
|---|---|---|
| Public Policy | Political Science MA/PhD (41 student-terms) | **PADM** — borrowed from the MPP |
| Public Management | MPA students (31) | NA — dropped |
| Health Policy and Admin | MPA students (8) | NA — dropped |
| General Healthcare Admin | MHA students (2) | NA — dropped |

So a PADM headcount counts POLS graduate students (Fall 2025: 4) as PADM
"Public Policy" concentrations, while SPA's own MPA/MHA concentrations do not
appear under PADM at all. Majors are unaffected: MPA (`PADM`), MHA (`HLAD`) and
MPP (`PUPO`) resolve to PADM in `cedar_programs`, `cedar_degrees`, the class
lists, and every catalog lookup, with no identity fallbacks and no
`cedar_mapping_issues` rows.

### Reproduce

```r
source("scripts/cedar-repl.R")
get_headcount(cedar_programs, list(dept_code = "PADM"), lookups = cedar_lookups)$data |>
  dplyr::filter(term == 202580, grepl("Concentration", program_type))
# Public Policy concentrations, degree MA / PhD -- Political Science students
```

### What a fix requires

A concentration belongs to the department of the **major it sits under** in the
same student-term, not to whichever major shares its name. Resolve it through
the host major's `dept_code` at transform time (or in headcount), and decide
explicitly what a concentration with no host major means rather than falling
back to the name lookup. Check the other name collisions this exposes before
shipping — "Public Policy" will not be the only one.

---

## I12 — Renamed and non-college names leave 48k program rows and 10k sections with no college

**Status:** resolved 2026-10-10 by ADR-002 Stage 3b: every reported college comes from the mapping files, Banner's values translated through `colleges.csv` `source_names` (ED and "College of Education" → EH, "University Studies" → UC, "Undergrad Certificate Program" → AD). 10,423 Education sections now report EH, and Banner's original stays in `source_college`.
**Found:** 2026-10-04, measuring unmapped codes of every kind for the Admin > Mappings page
**Severity:** medium — any college-scoped count of Education before 2021 is short,
and nothing says so
**Affects:** `cedar_programs$college_code` (and anything filtering or grouping by
it), and `cedar_sections$college` for College of Education sections before 2021.

### What is wrong

`college_name_to_code` (`R/lists/catalog_lookups.R`) is built from the one name
per college in `institution/unm/colleges.csv`. The exports use more names than
that, so `transform_programs()` gives these rows `college_code = NA`, silently:

| Academic Studies `Actual College` | Why it does not map |
|---|---|
| College of Education | The College of Education's name before it became Educ & Human Sci |
| University Studies | Not a college: University College's bachelor programs |
| Undergrad Certificate Program | Not a college |
| (blank) | Missing in the export |

Measured on `cedar_programs` built 2026-10-03: 47,886 rows have no
`college_code`, 18,181 of them Education students, mostly 2018–2022.

The course side has the same rename as a code. DESR sections for the College of
Education carry college `ED` through Fall 2021 and `EH` from Fall 2021, and only
`EH` is in `colleges.csv`: 10,423 sections (2018–2021) have a college that maps
to nothing. Their department is unaffected, because `subj_to_dept` ignores
college, but a filter on college `EH` misses Education's first four years.

### Reproduce

```r
source("scripts/cedar-repl.R")
cedar_programs |> dplyr::filter(is.na(college_code)) |> dplyr::count(student_college)
cedar_sections |> dplyr::filter(college %in% c("ED", "EH")) |>
  dplyr::count(college, year = substr(term, 1, 4))
```

### What a fix requires

Banner's own Translated College field already applies these renames, and
ADR-002 now uses it as evidence for an explicit college mapping (see "Colleges
are mapped, not read"). ADR-002 already plans the fix: `colleges.csv` gains `source_names`, every spelling
and former code the exports use, replacing `college_name_to_code`.

Decided 2026-10-04: `ED` and "College of Education" **are** `EH` (a rename).
"University Studies" belongs to University College (`UC`). The
college of "Undergrad Certificate Program" students was decided 2026-10-04: `AD`.
The evidence it was decided on: all 15 such rows in the September 2026 export are branch-campus
students, the population Banner otherwise files under "Associate Degree" (`AD`,
Banner's college for branch-campus associate programs: every one of its 1,088
rows is a Gallup, Los Alamos, Taos or Valencia student).
The transform-time mapping audit should list any name or code with no row, so
the next rename is seen the day it arrives.

---

## I13 — A transform run as a script never stamps cedar_programs with its mapping provenance

**Status:** resolved 2026-10-04 in #109 (merge `17ea915`): script mode and the demo
generator load CEDAR's functions, and the stamp is unconditional.
**Found:** 2026-10-04, wiring the mapping audit into the end of the transform
**Severity:** low in effect, misleading in appearance — every data refresh that
rebuilds programs leaves Admin > Data & Usage reporting STALE departments
**Affects:** `R/data-parsers/transform-to-cedar.R` when run as
`Rscript transform-to-cedar.R`, which is how `scripts/update-data.sh` runs it.

### What is wrong

The stamp is written only `if (exists("cedar_mapping_provenance"))`. Script mode
sources `config/config.R` and a few lists, but never `load_funcs()`, so the
branch that defines `cedar_mapping_provenance()` is never loaded and the stamp
is silently skipped. `cedar_programs_mapping_drift()` then reports "predates
mapping-provenance tracking", the Admin page says STALE, and the deploy gate (and
now `update-data.sh`'s mapping check) rebuilds programs a second time to stamp
it. The departments are right; the warning and the duplicate rebuild are not.

`scripts/rebuild-programs-if-mappings-changed.R` stamps correctly because it
calls `load_funcs()` before `transform_to_cedar()`. `dev/generate-demo.R` had the same
gap: the synthetic demo's `cedar_programs` was never stamped either, found when
the stamp was made unconditional.

### Reproduce

```bash
Rscript --vanilla R/data-parsers/transform-to-cedar.R --tables programs
Rscript --vanilla -e 'p <- qs2::qs_read("data/cedar_programs.qs"); is.null(attr(p, "cedar_mapping_provenance"))'
# TRUE
```

### What a fix requires

Script mode loads functions as the rebuild script does, and the stamp drops its
`exists()` guard so a missing function fails loudly instead of silently.

---

## I14 — The deploy's mapping rebuild looked for institution files on the host path, inside the container

**Status:** resolved 2026-10-04 in #112 (merge `8a11473`); the next deploy's
mapping step passed and rebuilt production's `cedar_programs`.
**Found:** 2026-10-04, merging #108: its deploy, and #107's, failed
**Severity:** high for mappings — every deploy since #107 has failed at the mapping
check, so no mapping change reaches production's cedar_programs. The app itself
deployed and passed its health check each time.
**Affects:** `scripts/rebuild-programs-if-mappings-changed.R` run by
`.github/workflows/deploy.yml` inside the production container; anything that
sources `config/config.R` and then `load_funcs()` inside a container.

### What is wrong

The deploy step failed with
`No mapping files for institution 'unm' at ***/institution/unm` (`***` is the
masked `CEDAR_PATH` secret). The rebuild script sources `config/config.R`, whose
`cedar_base_dir` is the server's host path to the repository, then calls
`load_funcs()` with the container path. `institution_files.R` found the
repository by looking `cedar_base_dir` up the calling frames, and while a list
file is being sourced the global environment is one of them -- so it found the
host path before load_funcs()'s argument. It worked on a laptop (the host path is
the repository) and in the app (whose `shiny_config.R` uses a relative path).

### Reproduce

```bash
docker exec -w /srv/shiny-server/cedar cedar-shiny Rscript --vanilla -e '
  source("config/config.R"); cedar_base_dir <- "/not/in/the/container"
  source("R/trunk/load-funcs.R"); load_funcs("/srv/shiny-server/cedar", modules = FALSE)'
# Error: No mapping files for institution 'unm' at /not/in/the/container/institution/unm
```

### What a fix requires

`load_funcs()` records the base it was given (`options(cedar.base_dir = ...)`)
and the institution-files lookup uses it first.


---

## I15 — The Headcount tab scopes a department by program name, crediting it with other departments' students

**Status:** resolved 2026-10-10. `filter_programs_to_dept()` (`R/branches/headcount.R`)
keeps the rows whose own `dept_code` is the department, and the Headcount tab,
Dept Trends and the Dept Dashboard all scope through it; the rollup to
department totals uses the row's unit too. EC-16 (two departments' programs
named "Engineering") is the cross-tab test, and fails with the name match
restored. Both scope strips now say the same thing.
**Found:** 2026-10-07, auditing where CEDAR counts the same thing twice
**Severity:** medium — wrong department totals where program names collide; the
counting itself agrees everywhere
**Affects:** the Headcount tab and Dept Trends' headcount (both through
`filter_programs_by_opt()` in `R/branches/headcount.R`); the Dept Dashboard
(`get_headcount_summary()` in `R/features/dept-dashboard.R`) is computed apart.

### What is wrong

The three surfaces count the same way — unique students per term with a
declared major or second major — and agree on 1,062 of 1,088 comparisons (every
department with majors × undergraduate and graduate × Summer 2022 through Fall
2025). They differ only in **which rows belong to a department**:

- The Dashboard takes rows whose `dept_code` is the department.
- The Headcount tab and Dept Trends take rows whose `dept_code` is the department
  **or whose program name** is one of the department's program names
  (`program_name_lookup`).

Name matching is wrong where two departments' programs share a name, and only
accidentally right where it pulls in a program whose department is a phantom:

| Department | Headcount tab − Dashboard | Rows added by name |
|---|---|---|
| ASPE (branch Pre-Engineering), graduate | **+231 to +246 every term** | ENG's graduate "Engineering" programs — **wrong department** |
| LAIS, undergraduate | +1 to +131 | FLIB "Liberal Arts" pre-majors, today under phantom department FLIB |
| CONE, undergraduate | +6 to +14 | FCOE "Construction Engineering" pre-majors, phantom FCOE |
| LING, LCL, MATH, BIOC, MGMT, CE | +1 to +6 | the same mechanism |

The concentration case in I11 is the same mechanism.

### Reproduce

```r
source("scripts/cedar-repl.R")
pn <- cedar_lookups$program_name_lookup
cedar_programs |>
  dplyr::filter(term == 202580, student_level == "Graduate/GASM",
                program_type %in% c("Major", "Second Major"),
                dept_code != "ASPE",
                program_name %in% pn$program_name[pn$dept_code == "ASPE"]) |>
  dplyr::count(program_name, dept_code)   # Engineering / ENG: 243
```

### Disclosed, not fixed

Since 2026-10-07 the Headcount tab's scope strip names the rule ("or a program
with the same name ... ISSUES I15") whenever a department is selected, and the
Dept Dashboard's headcount cards carry the same strip saying they use the
program's own department. Both are built by `describe_headcount_scope()`
(`R/branches/headcount.R`). The counts are unchanged; Dept Trends' headcount
still has no strip.

### What a fix requires

Scope a department by `dept_code` alone, in one shared function the Dashboard
uses too, and a cross-tab test. Do it with ADR-002 Stage 3: dropping the name
match before then would move FLIB's students out of LAIS while they still carry a
phantom department (FLIB → LAIS is already confirmed in `programs.csv`). The
Headcount page's scope bar should then say how the department was decided.
**Unblocked 2026-10-09:** Stage 3 shipped, so FLIB's students carry LAIS on
their own rows and nothing still depends on the name match.

---

## I16 — Bottleneck waitlist pressure ignores term, so later registration erases earlier waiting

**Status:** resolved 2026-11-11 (branch `cones/bottleneck-waitlist-per-term`;
see Fix)
**Found:** 2026-10-07, auditing where CEDAR counts the same thing twice
**Severity:** low — totals about 6% under the canonical count; a few courses
read far lower. No app page shows it.
**Affects:** `compute_waitlist_pressure()` and `get_bottlenecks()`
(`R/cones/bottleneck.R`). Nothing in `server.R`, a module, or a feature calls
them; they are reachable only by analysts in RStudio (the AGENTS.md population
example uses `get_bottlenecks()`).

### What is wrong

The suspicion was duplicate waitlist rows. That part is fine:
`compute_waitlist_pressure()` counts distinct students and removes anyone
registered. The real difference is that it works on `(student, campus, course)`
**with no term**. A student waitlisted in one term who registers for the course
in *any* term of the window is removed, and the remaining students are pooled
across terms. The canonical count (`R/branches/waitlist-demand.R`) is per term,
course title, campus, college, and part of term.

### Evidence

Fall 2024 – Fall 2026, ABQ and EA, every student as the population: pressure
3,501 vs canonical 3,707 summed over terms (−5.6%); 105 of 548 courses differ.
Largest gaps: PSYC 376 (EA) 62 vs 72, BIOL 2210L 67 vs 76, ARCH 472 4 vs 13.
ARCH 472 is the pattern: students who waited one term and took it later vanish.

### Reproduce

    st  <- cedar_registrations %>% filter(term >= 202480, campus %in% c("ABQ", "EA"))
    p   <- compute_waitlist_pressure(st, unique(st$student_id))
    c   <- summarize_waitlist_demand(get_true_waitlisted_rows(st, cedar_sections),
                                     c("campus", "term", "subject_course"))
    # compare sum(p$n_waitlisted) with sum(c$waiting), per course

### What a fix requires

A decision first. "Waited and never got in during the window" is a defensible
Roadblocks question, but then it needs its own label and definition; otherwise
use `get_true_waitlisted_rows()` / `summarize_waitlist_demand()` per term. Either
way, a fixture student waitlisted in 202080 and registered in 202110 for the
same course pins the behaviour.

### Fix

The rule in AGENTS.md decides it: waitlist demand is the class list's true
demand, through `R/branches/waitlist-demand.R`. `compute_waitlist_pressure()`
is now that count restricted to the population
(`get_true_waitlisted_rows()` then `summarize_waitlist_demand()`), and
`get_bottlenecks()` returns one row per campus, **term** and course in
`$waitlist` and `$by_label`. Terms are never pooled. "Waited and never got in
during the window" is not offered; it would be a new measure with its own
name. `get_bottlenecks()` takes an optional `sections` before `opt`, for
course titles a class list lacks; options passed in that position are refused.

Fixture WL02 (`cedar_registrations_wlterm`) holds a student waitlisted in
Fall 2020 and registered in Spring 2021, and one waitlisted in both terms.
The old function returns ABQ 1 on it; `test-bottleneck.R` pins ABQ Fall 2020
2, ABQ Spring 2021 1, EA Spring 2021 1. On the reproduction above (the
2026-11-04 tables) the result is identical to the canonical summary, row for
row: 618 campus-term-courses, 3,954 waiting.

---

## I18 — cedar_degrees holds no associate degrees, so branch-campus completions read zero

**Status:** open
**Found:** 2026-10-10, checking whether branch pre-programs (ASPE, PBA, PRSC) award degrees
**Severity:** medium for any completions view of the branch campuses — every
associate degree and branch certificate is missing, and the count is zero, not
blank. Main-campus degrees are unaffected.
**Affects:** `cedar_degrees`, and anything reading it for branch programs:
degree counts, Pathways' `graduated` outcome for branch students, and the
evidence the mapping review uses ("no degrees awarded" is meaningless for a
branch code).

### What is wrong

The degrees export CEDAR receives has no associate degrees at all: no row whose
`degree` begins "Associate", and no program code ending in a branch campus
(`-LA`, `-VA`, `-TA`, `-GA`) other than the Master of Landscape Architecture,
whose codes happen to end `-LA`. Branch associate programs appear in Academic
Studies (AS Pre-Engineering at Los Alamos and Valencia, AA Pre-Business
Administration, AS General Science...) but never graduate.

This nearly misled a mapping decision: five branch "Pre-" programs looked like
pre-majors partly because none had awarded a degree. They had no chance to.

### Reproduce

```r
source("scripts/cedar-repl.R")
sum(grepl("^Associate", cedar_degrees$degree))                       # 0
cedar_degrees |> dplyr::filter(grepl("-(LA|VA|TA|GA)$", program_code)) |>
  dplyr::count(degree)                                                 # Master of Landscape Architect only
```

### What a fix requires

Find out whether the degrees report is scoped to the main campus by design.
If so, request the branch campuses' awards and add them; if not, find where
they are dropped. Until then, say on any degree count that it excludes the
branch campuses.

Academic Studies is missing the same students (I20): a raw download with all
campuses selected holds only students registered for a main-campus or online
course that term, and no code filters them. Check a raw Degrees download the
same way (match it to the class lists); the two likely share a cause.

---

## I19 — The morning refresh could never publish projections, and blamed a stale lock

**Status:** resolved 2026-10-11. `update-data.sh` builds through the
`cedar-projections` service, the same command as the deploy's gate, and
`take_projection_lock()` (`scripts/build-enrollment-projections.R`) tells a held
lock from a directory it cannot write. `test-data-update-pipeline.R` asserts the
publisher service and fails with the old command restored;
`test-projection-refresh.R` checks the second message.
**Found:** 2026-10-11, when a manual refresh failed at its projection step
**Severity:** moderate — projections went stale silently. They moved only when a
deploy changed the model, never with new data, and the one visible symptom
pointed at a different defect (I6).
**Affects:** the projection step of `scripts/update-data.sh` in production mode.

### What is wrong

The morning step ran the build as `docker compose run ... --volume
./output:...:rw cedar-shiny`. Compose keeps the app service's read-only `output/`
mount, so the override did nothing. `7cdf09b` (2026-09-08) measured exactly
that, gave the publisher its own `cedar-projections` service, and moved the
deploy to it, but not the morning refresh. `test-data-update-pipeline.R` asserted
the broken command, so nothing flagged it.

The build then failed one second in, at `dir.create()` of the lock, which
reported any failure to create as `Rebuild already running or stale lock`.
Production on 2026-10-11:

```
==> Check enrollment projections and rebuild only when stale
Error: [projections] Rebuild already running or stale lock: /srv/shiny-server/cedar/output/projections/rebuild-request.yml.lock
  refresh projections          ❌      1s       exit 1; retry on next successful data refresh
```

The deploy the evening before had taken and released that same lock cleanly
through `cedar-projections`, which is what pointed away from I6.

### Reproduction

On the droplet, from the repository, with the old command's mounts:

```bash
docker compose run --rm --no-deps -T \
  --volume "$PWD/output:/srv/shiny-server/cedar/output:rw" \
  --entrypoint Rscript cedar-shiny --vanilla -e 'dir.create("output/probe")' </dev/null
# FALSE, with "Read-only file system"; no lock directory exists
```

---

## I20 — cedar_programs holds almost no branch-campus students

**Status:** open, parked 2026-10-15. The fix is a change to the report's
population, which needs whoever owns the MyReports Academic Study report; no
CEDAR or mrgather change can recover the students. Until then, branch-campus
program counts are not usable.
**Found:** 2026-10-12, reviewing the Taos subject HHHA: class lists show 99
students declared in its certificate, and `cedar_programs` has one of their 226
student-terms.
**Severity:** high for anything about branch-campus students, none for
Albuquerque. Every count is far too low and reads as real: a branch program
shows 2 students where class lists show 99.
**Affects:** `cedar_programs`, and everything reading it for branch students:
Headcount and Dept Trends headcounts for branch units, Pathways populations,
program counts on Admin > Mappings, demographics, and each student's major
college for branch students.

### What is wrong

Class lists cover every campus. Academic Studies, which builds `cedar_programs`,
covers the main campus only. Share of class-list student-terms (Fall 2018 –
Fall 2026, by home campus) with any `cedar_programs` row:

| Home campus | Student-terms | In `cedar_programs` |
|---|---:|---:|
| ABQ | 391,357 | 95.1% |
| Gallup | 28,038 | 1.2% |
| Valencia | 23,492 | 2.1% |
| Taos | 14,692 | 0.7% |
| Los Alamos | 8,264 | 2.9% |

Taos sits under 1% in every year, so this is not a recent change.

The download itself lacks them. Neither mrgather nor CEDAR filters on campus:
`getASs()` sets the term, all fields and Excel output, and the form has all
campuses selected; parsing removes only empty rows, rows with a blank Academic
Year and exact duplicates; the transform drops only empty program slots. The
parsed file is already 99.7% Albuquerque. (Checked 2026-10-14.)

Whether a student is in it depends on where they took courses that term, not
their home campus. Share of class-list student-terms (Fall 2019 – Fall 2026)
with any program record:

| Took courses at | Albuquerque home | Branch home |
|---|---:|---:|
| Some ABQ | 97.9% | 63.2% |
| Online (EA) only | 93.6% | 74.6% |
| EA plus branch | 92.1% | 73.4% |
| Branch campuses only | **4.7%** (8,384) | **0.0%** (72,841) |

So the report's population behaves like "registered for a main-campus or
online course", whatever its campus selector says. The Degrees report, with no
associate degrees (I18), likely shares it.

Confirmed against a raw download (Fall 2026, pulled 2026-10-14 with all
campuses selected: one sheet, 24,229 rows, 59 of them branch-campus), matched
to the class lists through the same two hashes CEDAR applies:

| Fall 2026 class-list students | Count | In the raw report |
|---|---:|---:|
| Took an ABQ or EA course | 24,821 | 24,209 (97.5%) |
| Took only branch courses | 5,089 | 7 (0.1%) |

Every one of its 59 branch-campus students also took an ABQ or EA course. Not
all the missing students belong in a program report: about half of the
branch-only students are concurrent-enrollment (dual-credit) or non-degree.
But 2,873 of them had a degree major in the class lists that term, 1,452 in
programs the mapping files place in branch units (General Studies, Liberal
Arts, Welding Technology, ...), and the report has none of them.

### Reproduce

```r
source("scripts/cedar-repl.R")
cl <- dplyr::distinct(cedar_registrations, student_id, term, student_campus)
pr <- dplyr::distinct(cedar_programs, student_id, term) |> dplyr::mutate(found = TRUE)
dplyr::left_join(cl, pr, by = c("student_id", "term")) |>
  dplyr::group_by(student_campus) |>
  dplyr::summarise(n = dplyr::n(), pct = 100 * mean(!is.na(found)))
```

### What a fix requires

Find what the report's population is: whether the campus selector's "All"
includes Gallup, Los Alamos, Taos and Valencia; whether a branch campus picked
explicitly returns its branch-only students (a term such as Fall 2025 should
show hundreds of Taos rows, not dozens); or, failing both, ask the report's
owner. Then change the pull (or request a report that covers the branches),
re-pull the history, and rebuild.
Until then, branch-campus program counts are not usable, including the counts
the mapping review shows for branch codes.

---

## I21 — Concentrations named "Pre-" are flagged pre-majors and lose the "Pre-"

**Status:** resolved 2026-10-14. `transform_programs()` never applies the name
rules to a concentration: it is never a pre-major, keeps Banner's name, and
gets no program code from its name (a "Mathematics" concentration had been
given MATH: 950 rows). A pre-major student's major row still says so. EC-14
holds a pre-major with a "Pre-Law" concentration and a "History" concentration;
`test-transform-status.R` fails with the old rules. Rebuilt from the same
export: only those four columns on concentration rows changed; no department
or college moved.
**Found:** 2026-10-12, reading the new Counting rules table on Admin > Mappings
**Severity:** medium. Headcount and the Dept Dashboard report inflated
pre-major figures for five departments, Architecture most, and two
concentrations display under a misleading name. Department totals themselves
are unaffected: concentrations count with the student's primary major either
way.
**Affects:** `transform_programs()` in `R/data-parsers/transform-to-cedar.R`:
`is_pre_major`, `pre_major_basis` and `program_name` on concentration rows;
then every reader of `is_pre_major`, including the "Pre-majors" part of the
Headcount and Dashboard scope strips (`headcount_scope_facts()`).

### What is wrong

A program row with no `programs.csv` row falls back to Banner's name: a
"Pre-" name makes it a pre-major (`pre_major_basis = "name_prefix"`), and the
"Pre-" is stripped from the stored name. The fallback was meant for codes not
yet in the file. But concentrations have no code at all, so every
concentration takes it. Banner names two concentrations "Pre-Professional
Architecture" and "Pre-Law"; they are tracks within a major, not pre-majors
leading to a program.

All 5,606 name-flagged rows are concentration rows (4,547 Professional
Architecture, 1,059 Law); no coded program takes the fallback. In Fall 2026:

| Department | Concentration students counted as pre-majors | Real pre-majors |
|---|---:|---:|
| ARCH | 294 | 0 |
| PHIL | 33 | 46 |
| SOCI | 27 | 375 |
| LAIS | 25 | 79 |
| POLS | 1 | 174 |

So Architecture's strip says 294 pre-majors are included, where it has none,
and the concentrations display as "Professional Architecture" and "Law".

### Reproduce

```r
source("scripts/cedar-repl.R")
cedar_programs |>
  dplyr::filter(pre_major_basis %in% "name_prefix", is_pre_major %in% TRUE) |>
  dplyr::count(program_type, program_name)
```

### What a fix requires

Apply the name fallback to coded rows only: a concentration is never a
pre-major, and keeps Banner's name. That changes the transform, so the deploy
gate rebuilds the program tables. Check first that nothing matches a
concentration by its stripped name.

---

## I22 — A mapping deploy is served from the tables it replaced until the app restarts

**Status:** resolved 2026-10-14. When the gate rebuilds anything, the deploy
puts the restart page back, restarts `cedar-shiny`, checks it again and clears
the page, so the app serves the rebuilt tables. A deploy that changes no
mapping file restarts once, as before. Running the gate before the first start
was tried and dropped: it would run beside the old app, whose sessions have
grown its memory, and a one-off rebuild beside a running app was killed for
memory on a development VM. `test-mapping-provenance.R` runs the deploy's gate
block with docker stubbed and fails without the restart. Since I46
(2026-11-04) the gate runs after the container is replaced and before the
health check that first starts the app, beside no app at all. A bare
`update-data.sh` run still leaves the app on its old tables until it restarts:
the morning job's `restart-cedar.sh --update` restarts it.
**Found:** 2026-10-14, reviewing why each mapping deploy needed a manual restart
**Severity:** medium. Every mapping decision and transform fix reaches the
stored tables at deploy but not the running app: production keeps showing the
old departments for up to a day, and Admin > Data & Usage > Mappings says
STALE meanwhile. Nothing is lost; it is late.
**Affects:** the deploy script in `.github/workflows/deploy.yml`, with
`shiny-server.conf`.

### What is wrong

The deploy starts the new container, then polls the app until it answers. That
first request starts the app's R process, and `global.R` loads the tables then
on disk. Only after that does the mapping gate
(`scripts/rebuild-programs-if-mappings-changed.R`) rebuild the tables the new
files changed. `shiny-server.conf` sets `app_idle_timeout 0`, so the R process
never exits and keeps serving what it loaded until the container restarts,
normally at the morning refresh (`restart-cedar.sh --update`).

Every mapping deploy so far has done this: #125, #133, #135 rebuilt the four
mapped tables after the health check.

### Reproduce

After a deploy whose log shows `[mappings] Rebuilt: ...`, open Admin > Data &
Usage > Mappings: the banner says "Departments are STALE". `docker compose
restart cedar-shiny` clears it.

### What a fix requires

When the gate rebuilt anything, restart `cedar-shiny` and run the health check
again, inside the same guarded block so a failure leaves the previous app
serving. Running the gate before `docker compose up` would avoid the second
restart but needs the new image to run in a one-off container, as the
projection publisher does.

---

## I23 — Student IDs are hashed with the built-in default salt

**Status:** open
**Found:** 2026-10-15, answering whether a salt change would split old and new
terms
**Severity:** medium for privacy; no number is wrong. The salt is meant to make
CEDAR's student IDs impossible to link back to Banner IDs without a secret.
With the default, anyone with the code and a Banner ID can compute the
student's CEDAR ID.
**Affects:** `encrypt_if_needed()` in `R/data-parsers/transform-to-cedar.R`,
every table it builds with a `student_id`, and `docker-compose.yml`.

### What is wrong

IDs are hashed twice. Parsing stores the MD5 of the Banner ID, unsalted, in
the exports (`class_lists.qs`, `academic_studies.qs`, ...). The transform then
stores SHA-256 of that MD5 plus `CEDAR_STUDENT_SALT`, and falls back silently
to the built-in `"cedar_default_salt_change_me"` when the variable is unset.

It is unset everywhere CEDAR runs. Locally it is in neither `.env` nor
`.Renviron` nor the shell; every R step runs `Rscript --vanilla`, which skips
`.Renviron` anyway; and `docker-compose.yml` passes no environment to
`cedar-shiny` or `cedar-projections`, so the containers never see it
(confirmed in the local app container). Production uses the same compose file.

The parse-stage MD5 is weak on its own: a 9-digit Banner ID can be recovered
from its unsalted MD5 by trying every ID, so the stored exports are not
pseudonymous whatever the salt.

### Reproduce

```bash
docker exec cedar-shiny sh -c '[ -n "$CEDAR_STUDENT_SALT" ] && echo set || echo not set'
Rscript --vanilla -e 'cat(nzchar(Sys.getenv("CEDAR_STUDENT_SALT")))'   # FALSE
```

### What a fix requires

Set a secret salt in production's `.env`, pass it to both services
(`environment: CEDAR_STUDENT_SALT: ${CEDAR_STUDENT_SALT}`), and make the
transform stop when it is unset rather than use a default (the demo sets its
own). A new salt changes every student ID, consistently across terms within a
rebuilt table, since the transform rehashes every term from the stored MD5s.
But tables built under different salts no longer join, so the change must be
one complete rebuild of every table holding student IDs (`cedar_programs`,
`cedar_degrees`, `cedar_registrations`, `cedar_student_terms`,
`cedar_applicants`, `cedar_holds`; the course-flow and enrollment caches hold none; `cedar_student_term_credits`
and `cedar_next_term` are retired), checked afterwards on Admin >
Join Integrity. Salting the parse stage too means a one-time migration of the
stored exports' MD5s, not a re-pull.

---

## I24 — CI's demo browser run intermittently loses the app at Open Seats

**Status:** probably fixed 2026-10-23 (#167); reopen if it recurs
**Found:** 2026-10-15, its second occurrence
**Severity:** low for users: CI only, and it passes on rerun. But a red check
blocks a merge, and a habit of rerunning would hide a real failure.
**Affects:** the `Synthetic checks` job (`.github/workflows/pr-checks.yml`),
`./run-tests.sh --e2e demo`.

### What is wrong

Twice, every step passed until "Open Seats runs", which failed about 1.5
seconds after the previous step with "the CEDAR app reloaded itself 7x
mid-test": run 38259413583 (2026-10-12, #134) and run 38750323255
(2026-10-15, #139, documentation only). Neither PR touched Open Seats; both
passed on rerun.

The app's log in the run's `cedar-synthetic-diagnostics` artifact ends at the
step before (Pathways stop-outs): no error, no Open Seats request, no worker
exit. The harness guesses an out-of-memory kill. Seven reloads in 1.5 seconds
look more like the worker refusing or dropping the connection at once, but
nothing kept can tell.

### Reproduce

Not on demand. `./run-tests.sh --e2e demo` against the synthetic stack,
repeated.

### What a fix requires

First, capture enough to tell: on failure, add to the diagnostics artifact the
app container's `OOMKilled`, exit code and restart count (`docker inspect`),
`docker stats --no-stream`, the runner's free memory, and the Shiny Server log
files inside the container. Then fix what they show.


### Probable cause (2026-10-23)

Two test faults, neither in the app. The reload counter counted every
`history.pushState` as a reload, and the app runs one on each tab switch and
run, so "reloaded itself 7x" was not a dropped session. And the Open Seats
check passed as soon as `sf_output` drew its column guide and tabs, then read
the output once, before the Courses table had filled in: a failure about 1.5
seconds into the step, with no Open Seats work in the app log. PR #167's CI
run 40001898661 hit the same step with the reload count fixed, and
reported the true error: `sf_output` held only the guide and tab labels. The
counter now counts page loads (`tests/e2e/lib.mjs`) and the check waits for
HIST 3010 in the table.
---

## I25 — Projection method selection was in-sample, and lost to the default

**Status:** resolved 2026-10-16, model 0.19.0. `select_projection_methods()`
now publishes prior same-season unless a challenger beat it by two WAPE points
on at least three earlier shared aftcasts, replays that rule at every historical
fold, and reports the realised error of what the rule would have picked.
`test-projection-model.R` holds a fixture whose in-sample winner fits 2%
and whose honest record is 8%; the old code reports 2%. Two shared folds were
tried first: on the rebuilt bundle the 26 challengers they admitted on the 2026
fold scored 11.4% against the default's 8.2% on the same courses.
**Found:** 2026-10-16, auditing the Spring 2027 bundle (model 0.18.0)
**Severity:** high for the page's credibility — every Accuracy badge was a fit
to the folds that chose the method, and the selection itself made projections
worse than publishing last Spring's number.
**Affects:** `R/branches/enrollment-projections.R` selection; every published
`wape`, Depth and Accuracy axis, and prediction interval in both saved bundles.

### What was wrong

Nine candidates were ranked by WAPE on the folds every eligible method shared.
The seasonal-trend candidate needs three prior Springs, so with a 2022 history
floor the shared window was Spring 2025 and 2026 for 80 of 83 courses: the
winner was chosen on two folds, then its WAPE on those two folds was reported
as its accuracy. Measured on the bundle's own backtests:

| Strategy | Folds | WAPE |
|---|---:|---:|
| Published selection, scored on the folds that chose it | 273 | 13.7% |
| The same rule applied rolling (choose only from earlier folds) | 311 | 16.5% |
| Prior same-season everywhere, no selection | 311 | 15.9% |

Depth read "Deep" from the winner's four own folds while the choice rested on
two. `forecasting-lessons.md` had already noted the problem for structural
switching; the code did it for every row.

### Reproduction

Against the 0.18.0 Spring 2027 bundle, join `projections` to `backtests` on the
selected method and pool `abs_error / actual_classlist_total`; then re-pick per
fold using only earlier folds and pool again. The two figures above differ by
2.8 points in the wrong direction.

---

## I26 — Projection "capacity reached" was judged on ever-registered demand

**Status:** resolved 2026-10-16, model 0.19.0. `projection_capacity_metrics()`
takes census occupancy (registered + late drops), or the students registered
now for a target still filling. Planning sections and seat gaps are sized from
`projected_census_equivalent` for the same reason. **Superseded 2026-10-17,
model 0.21.0:** occupancy is first-day enrollment (`calc_first_day_enrl()`),
because census, the 15th day of instruction, follows three weeks of drops — on 598 ABQ+EA course-terms, 199 were
full on the first day but under capacity at census — and sections are sized
from `projected_first_day_equivalent`. A term without status dates is not
judged.
**Found:** 2026-10-16, auditing the Spring 2027 bundle (model 0.18.0)
**Severity:** moderate — the flag fed the Capacity-bounded label, the capacity
caveat, the demand signal, the five-point selection margin, and the pressure
screen, all of which read seat churn as seat pressure.
**Affects:** `add_projection_capacity_censoring()`,
`build_projection_pressure_screen()`, `projection_capacity_context()`,
`build_projection_recent_history()`, `add_projection_recommendations()`.

### What was wrong

`classlist_total >= scheduled_capacity` was the test. Ever-registered counts
every student who ever held a seat, so a course whose seats turned over once
reads as over capacity. On 284 Spring folds with usable capacity:

| Measure vs scheduled seats | Median fill | Flagged "reached" |
|---|---:|---:|
| Ever-registered (the old test) | 105% | 72% |
| Census | 94% | 17% |
| Final enrollment | 86% | 6% |

In 87 of the 284 "reached" folds, final fill was under 85%. The pressure screen
passed all 72 non-forced courses on "chronic fill" alone, so it screened
nothing. Sections were sized from the ever-registered headline, which runs 13%
above census at the median: 596 sections recommended against 505 scheduled for
the same courses, on a demand estimate only 5% above their capacity.

### Reproduction

From the 0.18.0 bundle's `backtests`, compare `mean(capacity_reached)` with
`mean(actual_census >= scheduled_capacity)` on `seasonal_last` rows.

## I27 — The projection floor adds a waitlist to first-day enrollment and compares it with ever-registered demand

**Status:** resolved 2026-10-18, model 0.22.0. `projection_spine_floor()`
adds the waiting students to the spine; `prepare_projection_waitlist_history()`
removes waiting students already on the market class list on either campus;
`validate_spine_rows()` rejects a row whose uplift is not its waiting count
when saturated and zero otherwise. Rebuilt Fall 2027: 35 saturated courses,
243 students waiting, uplift 243 (was 77), 35 courses lifted (was 12); 6
waiting students removed as already on the class list. Spring 2027 has no
waiting students to add. Two Spring 2024 aftcasts moved by two students each
(stray Spring 2023 waitlist rows); the published rule's WAPE is unchanged in
both seasons. `test-projection-model.R` holds a saturated term whose
waitlist is smaller than its early-drop churn (it failed on the old formula)
and the WL01 market-waitlist scenario.
**Found:** 2026-10-18, auditing the Spring and Fall 2027 bundles (model 0.21.0)
**Severity:** moderate — it understates the one adjustment meant to correct for
capacity clipping. On Fall 2027, the 36 saturated courses with students still
waitlisted at close held 245 of them; the floor added 77, and 24 of the 36
courses got no uplift at all.
**Affects:** `projection_spine_floor()` in `R/branches/enrollment-projections.R`;
`floor_uplift`, `floor_basis` and the "Plan at least N" recommendation; the
adjusted-candidate formula in `docs/developers/enrollment-projections.md`.

### What is wrong

The floor is `first_day_enrl + waitlisted`, and the uplift is that minus the
spine. The spine is the prior term's ever-registered class-list total, which
counts every early drop; first-day enrollment does not. So the floor lifts the
spine only when the waitlist is larger than the term's early-drop churn, and a
course with real unserved demand reads as having none:

| Course (Fall 2026) | Spine | First day | Churn | Waitlisted | Floor | Uplift |
|---|---:|---:|---:|---:|---:|---:|
| ARTS 1610 | 177 | 159 | 18 | 18 | 177 | 0 |
| ARTH 1120 | 294 | 264 | 30 | 16 | 280 | 0 |
| FYEX 1010 | 1,435 | 1,373 | 62 | 13 | 1,386 | 0 |
| MATH 1220 | 770 | 723 | 47 | 11 | 734 | 0 |
| ARTS 1510 | 105 | 97 | 8 | 22 | 119 | 14 |

True-waitlisted students are almost never in the class-list total: 6 of 331 on
Fall 2026 (pooled ABQ+EA), each registered on one campus and waitlisted on the
other. So the lower bound on what the term would have registered with more
seats is, in the spine's own units, the spine plus the waitlisted students not
already on the market class list. Those 6 also show that the waitlist should be
deduplicated against the pooled market, not per campus.

Under this formula no historical fold reached the floor (class lists keep
waitlist rows only from Summer 2026, apart from a few stray Spring 2023 rows the
churn absorbed), so the fix barely touches the aftcast record.

*Done when:* the floor is spine + market-deduplicated waitlist; a designed
fixture holds a saturated course whose waitlist is smaller than its early-drop
churn, and its test fails on the current formula; the model version is bumped.

### Reproduction

From `enrollment-projections-202780-latest.qs`, take `candidates` rows with
`method_id == "spine_adjusted"`, `saturated_prior`, and `waitlisted_prior > 0`,
and join `recent_history$actual_first_day` on `history_term == spine_term`.
`sum(waitlisted_prior)` is 245, `sum(floor_uplift)` 77; every zero-uplift row
has `spine - actual_first_day >= waitlisted_prior`.

## I28 — One late-starting session makes a whole course's first day unknown

**Status:** resolved 2026-11-11. Intersession is out of the forecast (model
0.24.0, 2026-10-23), so a December session no longer blanks the Fall first
day. A session not yet begun is judged on its lower bound (model 0.25.0,
2026-10-24; see *Fix* below). A section with no start date has its own basis
and reason (2026-11-11, branch `enrl/first-day-no-start-date`; see the last
section).
**Found:** 2026-10-18, reading the Fall 2027 projection rows (model 0.22.0)
for a transparency review
**Severity:** moderate — a course that was full last term is shown as unknown,
so its saturation flag, "Plan at least" wording and floor are withheld, and the
stated reason points at the wrong cause.
**Affects:** `calc_first_day_enrl()` in `R/branches/enrl.R` at course grain
(`by_part_term = FALSE`): the projection's market history
(`R/branches/enrollment-projections.R`, `pool_campuses = TRUE`) and
`add_first_day_enrl()` callers such as `get_course_crosslist_classlist_enrl()`.
`get_course_planning_history()` counts by part of term and is not affected.

### What is wrong

`calc_first_day_enrl()` returns `NA` for a course-term unless every
non-waitlist row is `.known`, and a row is not known until the class list was
pulled on or after its section's start date. The Fall 2026 class list was
pulled on 2026-10-08. Second-half sessions began on 2026-10-12, and a few other
late-start sections later still. So a course with a single 2H section has no
first-day count at all, even though its full-term sections started on
2026-08-17 and their count is complete.

Every one of the 257 Fall 2026 ABQ/EA courses (of 2,599 with non-waitlist rows)
whose first day reads unknown is unknown for this reason, and for no other:
9,271 rows pulled before their section started (8,870 of them in 2H sessions),
none missing a status date or a start date.

In the Fall 2027 projection, three rows lose their judgment this way. The
reason they show, "First-day enrollment for Fall 2026 cannot be reconstructed
from the class lists", reads as missing status dates, which is the cause for
Fall 2024 and Spring 2025 but not here. Counting only the sections that had
started gives a lower bound on first-day fill, because it divides by all the
scheduled seats:

| Course | First day, started sections | Scheduled seats (all) | Fill, at least | True waitlist |
|---|---:|---:|---:|---:|
| ENGL 1120 | 1,192 | 1,260 | 94.6% | none retained |
| MATH 1350 | 1,037 | 1,094 | 94.8% | 78 |
| FYEX 1110 | 371 | 635 | 58.4% | 6 |

ENGL 1120 and MATH 1350 were saturated by the 90% rule, and the page does not
say so. The waitlist counts are the canonical rule before the market
deduplication.

The defect recurs every Fall and Spring for any build made between the start of
the term and the start of its last late session, and it clears once a later
pull covers every start date. Past terms were pulled after they ended, so the
aftcast record is untouched.

*Done when:* a session that has started has a first-day count whether or not
a later session has; a course whose later sessions have not started is judged
on what has started, labelled as such, or is reported unknown with the true
reason (sessions not yet begun when the class list was pulled), never "cannot
be reconstructed"; a designed fixture holds a course with a full-term and a
not-yet-started 2H section, and its test fails on the current function.

### Reproduction

From `cedar_registrations`, take term 202680, campuses ABQ and EA, and every
non-waitlist row. Join each row's section start date (the minimum
`start_date` per `term`, `crn` in `cedar_sections`). 9,271 rows have
`as_of_date < start_date`. They fall in 257 courses, and those 257 are exactly
the courses with any unknown row. In the Fall 2027 bundle,
`projections$adjusted_saturated_prior` is `NA` for ENGL 1120, FYEX 1110 and
MATH 1350 with spine term Fall 2026. It is also `NA` for ENGL 2660 and HIST
1150, whose spine term is Fall 2024, which has no status dates.

### Update 2026-10-23

The 2026-10-23 pull is later than every 2H start, so ENGL 1120 and MATH 1350
are judged saturated again. 17 of 2,602 Fall 2026 ABQ/EA courses still read
unknown. Leaving intersession out of projections (model 0.24.0, I35) clears 7
of them (BIOL 1140, ECON 2110, ECON 2120, FDMA 330, FDMA 430, MUS 375, RELG
1110), and ENGL 2210's Fall 2025 first day, which a December section with no
start date (CRN 79775) had blanked.

The other 10 (ARTH 429, ARTH 529, HED 321, HLED 2210, LAW 550, MSST 529, NMNC
4445, NMNC 4545, PAST 517, PHED 1620) are in no published projection. Each has
sections with a blank part of term that start late (2026-11-06 to 2027-01-04)
or have no start date. These, and any regular session not yet begun at the
pull, still blank the course's first day under a reason that reads as missing
status dates. The *done when* above stands for them.

### Fix (model 0.25.0, 2026-10-24)

`calc_first_day_enrl()` now returns `first_day_basis` (`complete`,
`sessions_pending`, `undated`) and `first_day_started_enrl`, the count over the
sessions that had begun. While any session is pending the course's
`first_day_enrl` stays `NA`; it is never a partial count. Counted by part of
term, a session that has begun keeps its own count. The projection reads the
started count through `projection_judged_first_day()`. That settles
saturation, the pressure bump and the expansion response only where the bound
already reaches their level, and the floor note then says "at least".
Otherwise the note names the session not yet begun. Course history reads
"Session not yet begun". EC-11c in the designed fixture holds a full-term
section and a 2H section not yet begun. Its tests in
`test-course-planning-history.R` and `test-projection-model.R` fail when
the bound is ignored or trusted below the threshold.

Measured on 2026-10-20, with the same change on an earlier branch, against
the Oct 8 Fall 2026 class list:
12 of the 65 Fall 2027 monitored courses offered in Fall 2026 were pending in
the pooled market. The bound settled 5 as near full, ENGL 1120 (at least
94.6%) and MATH 1350 (94.8%) among them. FYEX 1110 (58.4%) stayed unknown, with
the pending session named. The published 0.25.0 bundles (2026-10-24) read the
Oct 23 pull, by which every second-half session had begun. No published row
is pending, and no projection, plan, section count, bump or range differs
from 0.24.0 in either season.

### Fix for a missing start date (2026-11-11)

`undated` covered both a missing status date (M32) and a missing start date,
and its reason read "no status dates" for both. They have different remedies:
a re-pull of the class list supplies status dates and never a start date.
`calc_first_day_enrl()` now returns `first_day_basis = "no_start_date"` when
every row has its status date and the schedule gives some row's section no
start date, or has no row for it; `undated` means a status date is missing.
The count stays `NA` either way, and there is no lower bound. Course history
reads "Section start date missing" and the projections table "a section has
no start date". No calculation reads the new value: the projection judges a
first day only when it is complete or `sessions_pending`.
`cedar_course_terms` is build 5, so the deploy's gate rebuilds the measure
tables; `R/branches/enrl.R` is projection model source, so that deploy also
rebuilds both bundles (the model version is unchanged).

On the 2026-11-04 tables, ABQ and EA, by campus, college and course: Fall
2025 has 9 groups with `no_start_date` that read `undated` before, and Fall
2024, which has no status dates, keeps `undated` on all 2,760.
`test-course-planning-history.R` removes EC-11c's second-half start date,
then its schedule row; with the old `case_when` both read `undated`.
- Course Dynamics (`add_first_day_enrl()`) shows a pending term as a dash and
  does not give the reason.

---

# Improvements

Short entries: **what**, **where**, **done when**. Counts measured 2026-10-07;
rechecked 2026-10-14, when only `server.R` had moved (6,356 lines).
The recommended order before new features is in `ROADMAP.md`.

### Counting and definitions

**M1 — Grade-distribution buckets live outside the grade constants.** The
A/B/C/D/F/W buckets are inline in `R/branches/course-attempts.R`
(`get_grade_distribution()`). *Done when:* they are named constants in
`R/lists/grades.R` beside the DFW sets.

**M2 — Census and term type derived by hand.** `registered + dr_late` in
`R/branches/enrollment-projections.R`; `substr(term, 5, 6)` in
`R/branches/enrl.R` (2) and `R/branches/relative-terms.R`. *Done when:* they use
`add_census_enrl()` and `add_term_type_col()`.

**M3 — `max(term)` uses to review against the right-edge policy.** 29 uses:
`R/branches/population.R` 8, `R/branches/enrollment-projections.R` 5,
`R/features/dept-dashboard.R` 2, `R/features/course-report.R` 2,
`R/cones/gen-ed-conversion.R` 2, `R/branches/enrl.R` 2, and singles. Many are a
legitimate per-student latest term. *Done when:* each is either that, with a
comment, or replaced by `cedar_data_edges()`.

**M4 — Duplicated metric explanations.** *Done when:* each reconciled analysis's
explanation lives in the shared definition records (`docs/_data/definitions.yml`),
with only run-specific scope notes local.

**M5 — Missing scope notes where same-looking numbers differ.** Term scope,
campus scope, crosslists, census/final enrollment, current-term exclusion, the
grade edge. *Done when:* each such place has a visible note.

**M6 — The usage overview is not yet glanceable.** *Done when:* Admin → Data &
Usage → Usage Overview leads with key counts, unique users, departments, active
tabs, and trend, with detail behind it.

**M34 — Low Enrollment's schedule view rounds the history average before
judging it.** `get_enrollment_concerns()` (`R/branches/enrl.R`) stores
`avg_enrl` rounded to one decimal, and the severity rule in `server.R`
(`enrl_val < .threshold`, concerns mode) compares that rounded value: a course
averaging 11.96 against a threshold of 12 rounds to 12.0 and lands in "near
threshold" instead of "watch". The severity `case_when` is also business logic
in the server. Its alerts-mode summary also puts seven cards on a six-column
grid, so "Avg Enrollment" wraps onto a row of its own (unseen until 2026-10-23,
when a CSS rule that kept the cards from ever rendering was removed). *Done
when:* the cone returns the unrounded average, the table rounds for display
only, the severity rule moves into a tested branch helper, and the cards fit one
row.

**M41 — Retention cohorts include concurrent-enrollment students without saying
so.** `get_retention_comparison()`, `get_retention_trend()` and
`get_course_persistence()` take every registered student in the course, so a
branch-campus first-year course filled by dual-credit high-school students
reports their return pattern as the course's: Gallup's Fall 2023 FYEX 1110
cohort (35 students, all `Concurrent Enrollment`) returned at 37% the next
spring and 97% the next fall, a shape no college cohort has. Found 2026-11-10
verifying the FYEX questions. The pages and the `course-retention` definition
now say the cohort is everyone registered (version 2.1.0), which is the
disclosure, not the fix. Course Dynamics > Takers vs Non-Takers (2026-11-10)
takes that scope through its classification control; the Retention tab and
the hidden Explore retention module still do not. *Done when:* each retention
view takes a classification scope through
`cedar_student_terms$student_classification` (the Explore page's cohort
builder and Course Dynamics' campus control are the places), and a cohort's
concurrent-enrollment share is shown beside its rate.

**M53 — Two readers still classify the class list instead of reading
`cedar_attempts`.** The Course Report's next-term persistence
(`next_term_persistence()`, `R/cones/course-outcomes.R`, from
`get_course_persistence()` in `server.R`) runs `classify_enrollment_outcomes()`
over `cedar_registrations` and rebuilds pass / fail / late drop / early drop by
hand, which `outcome_category` already stores. Stop-out (`get_stopout()`,
`get_dfw_rates()`, `R/cones/stopout.R`) keeps a class-list path
(`classify_outcomes()`) that only tests reach, since Pathways always passes
`attempts`, and scopes its attempts with its own filters
(`.stopout_attempt_outcomes()`) instead of `prepare_course_attempts()`.
`classify_grades()` (`R/trunk/utils.R`) has no caller but a test. Found
2026-11-15 surveying DFW code for consolidation. Two more callers of
`classify_enrollment_outcomes()` are harder and can wait:
`build_student_terms()` runs before `build_attempts()` in the transform, and
`prepare_projection_student_inputs()` is a projection model-source file
(editing it rebuilds both bundles at deploy). *Done when:* persistence and
stop-out read `cedar_attempts` through `prepare_course_attempts()` and
`attempt_outcome_flags()`, the class-list path and `classify_grades()` are
gone, their tests run on `test_attempts`, and the two remaining callers are
the only ones, each with a comment saying why.

**M54 — A DFW rate is computed by hand in about eight places, each with its
own floor and rounding.** `100 * n_dfw / n` with a small-cell guard is
written out in `R/cones/course-sequence-effect.R` (3),
`course-cohort-effect.R` (`rate_or_na()`), `course-similar-students.R`
(`ratio()`), `R/features/course-topics.R` (2), `R/cones/stopout.R`
(`round(n_dfw / n_graded, 3)`, a 0-1 rate rounded in the calculation) and
the two `safe_pct()` copies in `R/branches/course-attempts.R`
(`get_course_dfw_demographics()` rounds to one decimal);
`get_course_outcome_rates()` rounds its rates to two decimals because the
pages that read it (`server.R`'s Course Report tables, Seatfinder, Gen Ed,
Bottleneck, Population Course Pressure) display them as they come. Reading
`outcome == "dfw"` off the stored table is right; the arithmetic around it
drifts. Found 2026-11-15. *Done when:* one trunk helper (a rate with a
floor, NA under it, never rounded) computes every one of them, each display
rounds for itself, and `get_course_outcome_rates()` returns
`summarize_attempt_outcomes()`' rates unrounded.

**M55 — Headcount selects a department's programs by name.** **Done
2026-11-16.** The module filtered minors and concentrations with
`program_name %in% dept_program_names` (four places, from the retired
`headcount_program_names()`), and majors and minors were picked and counted by
name: a name another unit's program shares counted toward the department (I62's
pattern). `headcount_filter_choices()` (`R/branches/headcount.R`) now builds
the whole picker cascade from rows whose own `dept_code` is the department;
majors and minors are offered and counted by program code
(`opt$major_codes` / `opt$minor_codes`, `program_choices()` labels, renames
joined through `program_successions`); concentrations, which carry no code,
stay by name. EC-16's ENG minor guards it.

**M56 — Population groups declare program names.** **Done 2026-11-16.**
`population_groups.csv` listed names, resolved to codes by
`population_group_major_codes()` and the preset type of
`resolve_focal_programs()`. It now lists declared program codes, validated
against `programs.csv` (a pre-major code is refused: it joins through
`leads_to`); renames join through `program_successions`. The preset type takes
`program_codes`, so `build_population()` matches no name anywhere. The
conversion kept every UNM group's codes exactly; the audit now reports
`unheld_codes` and the codes a list leaves out (a variant under a group
program's name, a pre-major with no `leads_to`), and found none.

### Testing and pipeline safety

**M57 — The fixture's major codes carry the degree.** The shared fixture's
program and degree rows put a made-up, degree-specific code in `major_code`
(`HIST-BA`, `HIST-MA`, `MATH-BS`). Real data keeps the two apart (see
[major code and program code](docs/developers/data-model.md#major-code-and-program-code-what-a-program-is)):
`major_code` is the field, one code across degrees (`HIST` for the B.A., M.A.
and Ph.D.), and the degree program is `program_code` (`BA-HIST-AS`,
`MA-HIST`). A pre-major has its own major code (History's is `FHIS`); the
fixture gives History's pre-majors the major's (`HIST-BA`, `is_pre_major =
TRUE`). Because the tests read UNM's `programs.csv`, keyed on major codes, no
fixture code has a row there: a Dept Trends build on the fixture finds no
degrees, and Pathways and Headcount label the fixture's codes "[no
programs.csv row] (HIST-BA)". Tests that rest on the made-up codes: "two
programs sharing a name are two populations" (`test-population.R`) and the
Headcount test of the same name (44 `HIST-BA` / 2 `HIST-MA`, really one
program at two degrees), the dept-report degree counts by `HIST-BA`, and
`HIST_CODES` / `HC_HISTORY_CODES`.

*Plan:* move the fixture's `major_code` to UNM's major codes (`HIST`, `FHIS`
for History's pre-majors, `MATH`, `ANTH`, `BADM`, `PSY`; a concentration has
none, as in the export) and put the degree program in `program_code`
(`BA-HIST-AS`, `MA-HIST`); re-pin each B.A./M.A. count that changes, checking
each one; move the same-name-programs tests to a pair UNM really has (PSY and
XPSY, or ARCH and ARCT); keep the rename tests on a scenario
`program_successions` table. Update the header's pinned counts in the same
change. **Deferred (user, 2026-11-16)** until #311–#313 are merged and
checked in the browser. *Done when:* the fixture's programs and degrees use
codes `programs.csv` has, every test reads them through it, and a Dept Trends
degree count is pinned on it.

**M7 — Untested analytical code.** No direct tests for
`R/branches/credit-hours.R`; thin coverage for `R/cones/course-neighbors.R` and
`R/branches/degrees.R`; no render-path test for Course Dynamics wiring.
*Done when:* each has focused tests on the designed fixture.

**M8 — Pipeline failures that could break production updates.** *Done when:*
class-list key type drift, waitlist preservation, and parse-step failures each
have a regression test.

**M9 — `Synthetic checks` is not required on `main`.** The branch is unprotected
(checked 2026-10-07). *Done when:* the ruleset requires it (a repository-admin
setting).

**M10 — Release validation needs memory headroom.** *Done when:* the full
institutional tour has passed on a host where the VM is not near its memory
limit, and dependency changes are validated in both the native library and the
Docker image.

**M25 — The mapping validator accepts any program as a `leads_to`.**
*Status: resolved 2026-10-09.* `leads_to` was seeded from `premaj_canon`, which
mixes department and program codes, so where a department code is also a
program code it named the wrong degree: `FFCS` → `FCS`, pre-Computer Science.
Ten more named a general program or a successor (`FEE` → `ECE`, `FIDA` →
`FDMA`, `FMAR` → `FDMA`, …); all now name the pre-major's own degree, and
`FING`, whose degree has no code, has none. `.validate_program_rows()` now
refuses a confirmed pre-major in a different unit from its target (tested in
`test-catalogs.R`). A same-unit wrong target, as `FEE`'s was, still needs a
reviewer: check the target's name.

**M26 — The mapping gate rebuilds cedar_programs only.** *Status: resolved
2026-10-10; superseded 2026-11-06.* The transform stamped programs, degrees,
sections and class lists with their mapping provenance, and the gate rebuilt
whichever were stale (`cedar_stale_mapped_tables()`), stopping if an export it
needed was missing or a rebuilt table was still stale. Before, it rebuilt only
`cedar_programs`, so a subject decision reached the course tables only at the
next refresh. A rebuild restarted the app so it served them (I22). Since
ADR-001 step 3 no table stores a unit: the loader attaches every one at start
from the mapping files, so a mapping edit rebuilds nothing, and the stamps,
`R/branches/mapping-provenance.R` and the gate's mapping branch are gone. The
gate builds `cedar_student_terms` alone.

**M40 — The scenario program fixtures cannot build a student-term table with
their programs.** `cedar_programs_mc` (MC02) and `cedar_programs_hp2` (HP02)
lack `source_college_code`, `source_college` and `sem_gpa`, which
`build_student_terms()` requires of a programs table, so `setup.R` builds
`test_student_terms_mc` with `programs = NULL` (its majors come from the class
list's `major_code`) and HP02 has no student-term table at all. A cone that
joins `cedar_student_terms` to a class list by major (`get_major_course_units()`,
2026-11-10) tests on ST01, RW01 and MC02 instead; HP02's pre-nursing
population, the richer out-of-unit scenario, is unreachable. *Done when:* the
two fixtures carry the builder's required columns and `setup.R` builds
`test_student_terms_hp2` and `test_student_terms_mc` over them, with the
fixture header's expected values checked.

**M42 — Setting the Course Dynamics course picker with `setInput()` can lose
the value on the first session after a restart.** `cr_course` is a server-side
selectize; on a cold worker its initialisation can land after a browser test's
`setInput(page, 'cr_course', …)` and clear it. Seen 2026-11-13 on three of
three first sessions after a container start while writing
`tests/e2e/later-course.test.mjs` (each after `warmup.mjs`, which opens Home
only): `Shiny.shinyapp.$inputValues.cr_course` read `"HIST 1110"` after the set
and `""` once Analyze Course returned, and Downstream, which reads the picker,
stayed on "Select a course, then click Analyze Course to view this tab." until
the suite timed out. Every later session passed, so the failure follows suite
order and reads like a broken tab. `course-impact-covariates.test.mjs` and
`course-cohort.test.mjs` set the picker the same way; the first passed on the
one cold session tried, so there the race is possible, not certain.
`later-course.test.mjs` loads the course through a deep link
(`connect(page, { search })`, as `course-dynamics-deeplink.test.mjs` does) and
passed cold. *Done when:* `lib.mjs` has one helper that loads a Course Dynamics
course and waits for the picker to hold it, and every suite that needs a course
uses it.

**M66 — Nothing stops two fetches from running at once.** `update-data.sh`
starts its mrgather container (`cedar-mrgather-fetch-<pid>`) without looking
for another, and every fetch on a machine signs in through the same saved
browser profile. Chrome keeps a lock in a profile for exactly this, and
mrgather removes that lock when it starts, because a fetch stopped part-way
leaves one behind. So a refresh started by hand while the scheduled one is
fetching (or twice by hand) puts two browsers in one profile and writes two
sets of exports to one folder. Found 2026-11-23 reading mrgather's code; not
seen to happen. Resolved 2026-11-25 (branch
`fix/exit-progress-empty-and-one-fetch`): before it starts a fetch the script
asks `docker ps` for a `cedar-mrgather-fetch-*` container, and with one up the
step fails as "another fetch is running (<its name>)" without starting
mrgather. Nothing is parsed from that run, a file from today included, since
the other fetch may still be writing it. A fetch that died leaves no
container, so there is nothing to clear; and a run that finds every file
already from today needs no fetch and does not ask. `test-data-update-pipeline.R`
covers the three.

### Architecture rules (`AGENTS.md`)

**M11 — Silent fallbacks.** *Enforced since 2026-10-16* by
`tests/testthat/test-architecture.R` ("silent error fallbacks do not grow"):
every `error = function(e)` handler that hands back a value without showing,
re-raising, warning, logging, or propagating the error (returning the
condition or its message to a caller that decides) counts, and each file
carries today's count as an allowance that may only go down. Measured: 33
across 9 files — `R/modules/pathways.R` 11, `server.R` 9, `R/trunk/logging.R`
7, and one each in `R/modules/dept-trends.R`, `regstats.R`, `seatfinder.R`,
`ui-helpers.R`, `waitlist.R`, and `global.R`. Nothing remains in the cones,
branches, features, or data pipeline: `cedar_edge_note()` no longer drops its
next-term sentence when `add_term()` fails (2026-10-16), and the git
provenance capture logs why git was unavailable instead of saying nothing.
The one in the data pipeline, where AGENTS.md calls it always a bug, was
`build_lookups()` in `transform-to-cedar.R` reading the saved `cedar_lookups`
inside a `tryCatch` that returned NULL, so an unreadable file silently left
every major unnamed. Fixed 2026-10-16: an unreadable or wrong-shaped file now
stops the rebuild, and `test-transform-status.R` proves it.
*Done when:* the allowance list is empty; only the sanctioned kinds remain (a
module error shown with `showNotification()` or `handle_error()`; a degenerate
statistic returning `NA`; a logged failure in the logging layer itself).

**M33 — Generic degree allowances look like identified Gen Ed requirements.**
Resolved 2026-10-20: annual shared rules now allocate illustrative Gen Ed
coverage from selected courses before identifying remaining areas inside the
existing allowance budget. Other slots say elective/minor, any level, Gen Ed
not required. Course badges expose overlapping coverage; open choices do not
satisfy areas automatically. Flexible coverage is visibly provisional pending
source clarification. The standard upper-credit minimum is context, not an
additional credit charge. Anthropology's default example has four identified
area slots (12 credits); the other early slots represent elective/minor space.
Student transcript evaluation and conditional approvals remain roadmap work.

**M30 — Regstats restates its default thresholds.** `R/features/regstats.R`
writes the default threshold list twice (`get_dashboard_regstats_thresholds()`
and the run path), and when `cedar_regstats_thresholds` is missing it prints a
WARNING and runs on that copy instead of stopping. Only the chronic fill rate
reads a shared value (`CEDAR_NEAR_FULL_FILL`). The projection model had the
same pattern (47 `opt$x %||% literal` sites); it now reads every default from
`enrollment_projection_defaults()` through `projection_option()`. *Done when:*
Regstats' defaults live once and a missing configuration stops loudly.

**M12 — Cones and branches reading global data.** **Done 2026-10-16.**
`tests/testthat/test-architecture.R` ("cones and branches do not read global
state") now fails on any `data_objects`, `.GlobalEnv`, `get("cedar_…")`, or
`exists("…")` in `R/cones` or `R/branches`, except the two standalone guards
`exists("%||%")` and `exists("cedar_log_level")`; the allowance it ratcheted
over (19 across 5 files when enforcement began) is empty. What each fix did:
`R/branches/course-attempts.R` — the graded edge is `opt$data_edges`
(required, fails closed when undetermined) and the left edge `opt$min_term`,
never a global or a literal. `R/cones/sfr.R` — `get_sfr(programs, faculty)`
and `get_sfr_data_for_dept_report(programs, faculty, opt)` take their two
tables, `opt$dept_code` required (the cone has no app caller; see
`docs/developers/source-to-cedar-manifest.md` §5). `R/branches/credit-hours.R`
— `credit_hours_by_major()` takes `major_codes` from the caller (Dept Trends
passes `base$prog_codes`, the set the module labels as home majors) instead of
reading `major_to_dept` behind an `exists()` guard that fell back to the
department code as a major code; `credit_hours_by_fac(students, faculty, …)`
names its tables. `R/cones/waitlist.R` — `inspect_waitlist(students, opt,
sections, course_terms)` and `attach_enrollment_history()` take
`cedar_course_terms` from the Waitlists module, which gets it from `server.R`.
`R/cones/course-demographics.R` — `get_course_major_mix()` took the
code-to-name table as `opt$major_code_to_name`, threaded from
`data_objects[["cedar_lookups"]]` through the Gen Ed module's `lookups`
argument; since 2026-11-06 it takes `dims` and names codes from programs.csv.
The feature-layer read of the global `cedar_cl_enrls_base` in
`R/features/regstats.R`, outside the rule's scope, went with it on 2026-11-07:
`get_reg_stats()` takes `cedar_course_terms` as `course_terms`; `R/features/dept-dashboard.R`'s read of
the global `major_code_to_name` went with `cedar_lookups` (2026-11-06).

**M13 — Business logic in modules.** `R/modules/pathways.R` 38
`group_by`/`summarize` pipelines, `R/modules/cancellations.R` 10,
`R/modules/gen-ed.R` 2. *Done when:* each calculation lives in the cone or
branch that owns the question.

**M14 — Inline surfaces in `server.R`.** 6,356 lines. *Done when:* the remaining
inline tabs are modules (templates: `R/modules/headcount.R`,
`R/modules/dept-trends.R`), with logic in branches/cones/features.

**M15 — `ggplot` charts.** Six remain. *Done when:* each is native `plot_ly()`.

**M16 — Oversized files.** Cones over the 500-line budget: `pathway.R` 904,
`course-demographics.R` 679, `stopout.R` 577, `gen-ed-conversion.R` 542,
`seatfinder.R` 522. Long analytical files with repeated
filter/summarize/cache code: `enrl.R`, `regstats.R`, `credit-hours.R`,
`pathway.R`, `dept-dashboard.R`. The projections page (measured 2026-11-03):
`R/features/enrollment-projection-view.R` is 2,471 lines of page payload and
text, and `R/modules/enrollment-projections.R` 1,711, of which the server is
about 430 against a 300-line budget. The view file is deliberately off the
model-source list, so splitting it costs no bundle rebuild, but a split file
must stay off that list too. *Done when:* each is split by sub-question or
its repeated code extracted — alongside other work on the file.

### Interface consistency

**M17 — Inline styles.** 153 `style =` attributes in module and UI code
(133 lines on 2026-11-14, 91 of them in `server.R`). *Done when:* replaced by shared helpers and CSS classes
(`R/modules/ui-helpers.R`), one tab per PR.

**M18 — Bare headings.** 53 `h3()`–`h6()`. *Done when:* each is
`subtab_header()`, `dashboard_section()`, `dashboard_subsection()`, or
`section_heading()` with its one-sentence description.

**M19 — Pathways heatmap legibility.** Long course labels and dense
course-to-major views. *Done when:* labels are readable at the default size.

**M29 — Count and rate columns are formatted per tab.** The rule is whole
counts with separators, rates at one decimal and an em dash for unknown
(AGENTS.md, Numeric precision). `cedar_count_coldef()` and
`cedar_percent_coldef()` (`R/modules/ui-helpers.R`) now carry it, and Degree
Explorer and the projections percent columns use them. Projections' count
columns, Regstats' fill bar (whole percents, hard-coded hex colors and inline
styles in `fill_bar()`) and the other tabs' tables still format their own. The
projections browser suite parses some count cells with `parseFloat`, which
breaks on a thousands separator. Seen 2026-11-14: Open Seats prints DFW % at
two decimals (31.76), and the Dept Dashboard's credit-hour shifts print
`-12%` beside `-18.3%`. *Done when:* every count and rate column uses
the shared definitions, and the browser checks read the number, not the text.

**M27 — Headcount lists a department's programs by name.** Its program
dropdown takes a department's programs from `cedar_lookups$program_name_lookup`
(each program name's most common department), so a name two departments share
lists under one. Counting is by each row's own department (I15); only the
choices are affected. *Done when:* the choices come from the rows'
`dept_code`, or from `unit_mapping_rows()`.

The entries below come from the 2026-11-14 page audit (HIST and HIST 1110 on
the institutional app). Order: M43 first, on the dean-facing pages, then one
tab per PR; M44–M47 ride along with whichever tab is being touched.

**M43 — Method text leads the page instead of the finding.** Explanations
arrived in layers, each with its own device: an italic filter-bar subtitle, a
grey scope strip, the subtab sentence, open blue alert boxes, collapsible blue
`info_panel()`s and open definition notes. Most method text sits above the
first number. Worst cases: Dept Trends > Headcount states its definition twice
(the subtab sentence is the first line of an open `cedar_definition_note()`,
`R/modules/dept-trends.R:677`), then exclusions and three caveats; Regstats
opens with seven threshold inputs and Scope, Thresholds, Method and
"Unscored SD comparisons" lines plus three caveats; Course Dynamics > Course
Flows opens with about 200 words in three paragraphs; DFW with a five-sentence
policy paragraph; Explore > Enrollment with "XL-aware Enrl…"; the Dept
Dashboard leaves a six-line COUNTING block open under its student cards and
tells deans Low Enrollment "uses the same low-enrollment helper". There are
three blue-box systems: 22 collapsible definition panels, 28 open
`alert alert-info` boxes and 7 `alert-box--info`. *Done when:* every section
is title, one plain sentence saying what it answers (no method vocabulary),
one collapsed method panel (scope, exclusions, thresholds, edge, definition
links), then the result; an open box appears only
for a caveat that changes the reading (term in progress, data window), in one
shared style; tuning inputs (Regstats thresholds, flow minimums) sit behind a
disclosure; and the open-blue-box ratchet in `test-architecture.R` (added
2026-11-14, 38 boxes in 10 files) reaches zero. Course Dynamics > Overview is
the model; the Dept Dashboard and Dept Trends were the pilot. The pattern is in [shiny-modules.md](docs/developers/shiny-modules.md#explaining-a-section).

**M44 — Term codes on reader-facing surfaces.** The term inputs of Regstats,
Open Seats, Waitlists and Explore > Enrollment show `202680`; the Dept
Dashboard's High Waitlists table has a `TERM` column of codes while its own
term filter reads "Fall 2026". *Done when:* every term input and term column a
reader sees is labelled through `fmt_term()` (the code stays the value).
Regstats' and Waitlists' tables change together, with
`tests/e2e/waitlist-reconciliation.test.mjs`, which matches their Term cells
to each other and to the Waitlists term input.

**M45 — Per-term charts do not all use the Term types control.** The
pattern (PRs #273–#289): a "Term types" checkbox group, Fall and Spring ticked
by default and Summer opt-in, under the section's heading and sentence, above
the chart it governs. Gen Ed, Course Cohort, Topics, Later Course, Dept
Trends > Courses Taken and Course Dynamics > DFW use it; Gen Ed places it in
the top filter stripe instead of in the section. The exceptions: Course
Dynamics > Overview has an All / Fall / Spring / Summer radio; Rollcall draws
Fall and Spring side by side; Dept Trends' Headcount, Credit Hours and
Enrollment have no control and put every term, summers included, on one
axis, so the bars saw-tooth and a summer reads as a collapse (Credit Hours'
College Comparison index falls from about 100 to near 0 every summer). Dept
Trends' charts are stored in its cache, so that change bumps
`cedar_dept_cache_version`. *Done when:* every per-term chart uses the Term
types control, defaulting to Fall and Spring, placed in its section.

**M46 — Raw column names reach the reader.** Dept Trends' headcount charts
label their axes `term` and `student_count` (`R/branches/headcount.R`, every
`plot_ly(x = ~term, y = ~student_count)` without axis titles; fixed
2026-11-14), Credit Hours' charts `term`, "Academic Period" and lowercase
level legends (`grad`, `lower`, `upper`); Explore > Enrollment's Group by
shows `subject_course` and `term`. *Done when:* every
axis title and choice label is a word a dean would use.

**M47 — Filter bars disagree.** Headcount labels its inputs "Select Campus",
"Select College"… where every other tab says "Campus"; Pathways spells the
campus "Albuquerque/Main" where the rest say ABQ; the Waitlists campus box
wraps to one chip per line; empty states say "Select X, then click Y" except
Pathways', which says what each subtab will show. *Done when:* labels, campus
values and empty states follow one pattern (Pathways' start card for the
empty state).

**M48 — Dept Dashboard lists run unbounded.** "Missing vs. two years ago" listed
32 HIST courses with no cap or collapse, and the Low Enrollment table clips
its Recent History column at the default width. *Done when:* each list shows
its top rows with the rest one click away, and no table clips a column.
*Status: resolved 2026-11-14:* every course list shows its top rows with "Show
N more" for the rest, and Recent History wraps.

**M49 — Course Dynamics draws first day, census and final twice.** Overview's
Enrollment History (`cr_overview_enrollment_plot`) and the Enrollment subtab's
First Day, Census, and Final Enrollment (`cr_enrollment_pressure_plot`) chart
the same three class-list measures over the same crosslist-family totals; the
subtab's own sentence says so. *Done when:* the Enrollment subtab is folded
into Overview (its drops chart and class-list table move there) and its slug
and links resolve to Overview.
*Status: resolved 2026-11-14:* the drops chart and the Enrollment by Term table
are on Overview, following its Term type, and the subtab and its second
lifecycle chart are gone; the guide's links point to `course-reports#overview`.

**M50 — Two branch units are named for something they do not teach.** In
`units.csv`, MAS is "Medical Administrative Specialist" and STIN "STEM
Integration", but every MAS section in the data (from Fall 2018) is massage therapy at
UNM-Taos (Massage Therapy I, Deep Tissue Techniques, Cranial Sacral) and every
STIN section structural integration, the courses MASS and SHIN renumbered in
Fall 2026. The names were proposed from the codes on 2026-10-04. A page that
names the unit (Dept Trends, Courses Taken's teaching units) shows the wrong
discipline. *Done when:* each AD unit's name is checked against the titles it
taught, MAS and STIN first.

**M51 — Regstats calls a course at 90% census fill "full".** Its saturation
badges read **Full now** and **Chronically full** for census fill at or above
the Chronic Fill Rate, whose default is `CEDAR_NEAR_FULL_FILL` (90%), and
`docs/users/regstats.md` defines the rate as the fill "to count as full". CEDAR
calls 90% near full; full is `CEDAR_FULL_FILL`, 98% of seats on the first day.
A course at 91% shows the same badge as one turning students away. The
registration watch (`R/features/registration-watch.R`) reads the same flags
and says "near full", printing the rate it used. *Done when:* the badges, the
method text in `R/modules/regstats.R` and the guide say near full (or name the
rate), and a full badge, if kept, is judged at `CEDAR_FULL_FILL` on the first
day.

**M52 — Course Dynamics' two Downstream views read alike but count different
students.** **Later Course** starts from everyone who took the course (X) and
follows them into a later course (Y); **Course Sequence** starts from everyone
in Y and compares those who passed X first with those who did not. Both had a
"Later course" picker and both report results in Y, the names did not say
which students each counts, and the tab's one sentence described both at once,
so a reader could not tell what separates them.
*Done when:* each view's name and opening sentence say which students it starts
from, its picker says what the course is to those students, and the guide sets
the two side by side. *Status: resolved 2026-11-14:* renamed **Where Students
Go Next** and **With or Without This Course** (the code keeps `later-course`
and `course-sequence`); each opens on the students it starts from; the pickers
read "Later course(s) its students took" and "Students in"; the guide's
Downstream section is a side-by-side table, and its anchors are unchanged.

**M58 — Colours written into R code do not follow dark mode.** Dark mode
(2026-11-19) changes the CSS tokens, the table theme and each plotly figure's
background, text and grid; a colour an R function writes itself stays as it
was drawn for a white page. Nine inline `style =` colours remain:
`R/modules/regstats.R:130,133` (a bar track `#e0dbd2`, a `#666` label),
`R/modules/dept-trends.R:1220-1272` (`#555` and `#666` table text) and
`R/modules/pathways.R:1513` (`#b07000`). They also break the rule against
inline styles. Trace colours chosen for a white page (a near-black line or
label) and the sparkline strokes in `R/modules/ui-helpers.R` are not checked.
*Reproduce:* switch to dark mode and open Regstats, a Dept Trends degree
table or Pathways' warning line. *Done when:* each is a CSS class reading a
token, and a dark screenshot of each page shows no light-mode colour.

**M59 — Each cache-warming script copies global.R's load sequence.**
`scripts/warm-dept-dashboard-cache.R`, `warm-dept-trends-cache.R` and
`warm-cas-dept-profiles.R` each repeat global.R's steps by hand: read the
tables, trim to `cedar_min_term`, `thin_class_list()`,
`attach_default_units()`, `build_cedar_courses()` / `attach_course_ids()`,
`cedar_report_edges()`. A step added to global.R and not to a script makes
the script save caches the app never asks for, or stop (I69, where the
measure tables were the missing step; I69's fix shares only the measure
tables and the cache hashes). *Done when:* one function loads the tables as
the app holds them, global.R and every warm script call it, and
`scripts/cedar-repl.R` does too where its trimming allows.

**M60 — Two cones standardize a group to its comparison's rates by hand.**
`get_course_similar_students()` (cells of term, home campus, high-school GPA
band and time status) and `.sequence_band_comparison()` in
`course-sequence-effect.R` (high-school GPA bands) each compute "the rate the
first group would have had at the second group's rate in each cell", with
their own guards and their own standard errors. Prepared for It therefore
matches on one thing where Against Non-Takers matches on four, and has no
check of its matching (the ACT comparison Against Non-Takers runs). *Done
when:* one branch function standardizes a group to another over named cells
and returns the covered count, the expected value and its error; both cones
call it; and Prepared for It reads the same cells and the same alike check.

**M61 — Three readers of `student_population` each match its labels.**
`student_term_entry_type()` and `classify_origin()` (`population.R`),
`.recode_population()` (`population-trend.R`) and the Pathways module
(`pathways.R`, a `grepl("transfer", ...)`) each carry their own patterns for
Banner's labels. *Done when:* one branch function recodes the label, the
labels it reads are an institution file, and the others call it.

**M62 — A count formatter is written out in 17 files.** Resolved 2026-11-22:
`fmt_count()` (`R/trunk/display-format.R`: whole number, separators, an em
dash for NA, no padding) replaces the named copies (`.retention_n`,
`.graduation_n` and ten more) and the local closures. It is not in
`trunk/utils.R` because that file is projection model source. Still written
inline, not as a closure: single `format(x, big.mark = ",")` calls inside a
sentence, about 130 of them, most in the projection files and log messages.

**M63 — Two step-by-step follow-ups remain beside `follow_students()`.**
Resolved 2026-11-22: `get_entering_class_retention()` reads
`follow_students()` once (`since_start = TRUE`: a degree counts from the
entering term on) for both its rates and its pace columns.
`.compute_retention()` stays for the course cohorts, and its header says why:
a student is in a course's cohort once for each term they took it, and its
callers read one wide row with NA past the data.

**M64 — `get_exit_requirement_progress()` warns when no student is far along.**
With an empty `students` table, `max(as.integer(students$exit_term))`
(`R/cones/exit-requirements.R`) is a maximum of nothing: R warns and returns
`-Inf`. The result is still right (no plan is listed), so this is noise in the
app's log for a scope with no far-along leaver, such as a small level on one
campus. Found 2026-11-22 while testing the Graduation preload. *Reproduce:*
`build_graduation_dashboard()` on XC01 with `attempts` and `boards`, given
`parts` whose `exit$students` has no rows. Resolved 2026-11-25 (branch
`fix/exit-progress-empty-and-one-fetch`): with no student the cone reads no
last term and no course is readable; the result is the same empty one, without
the warning. `test-exit-requirements.R` runs XC01 with no student who left and
expects no warning.

**M65 — The list of MyReports reports is kept in three places.** Until
2026-11-22 a report's code, file signature or stage was typed in about a
dozen: `report_specs` inside `parse-data.R`, five spots in
`update-data.sh` (the argument pattern, the default, the file globs, the
stage map and a literal `5` for "every report"), `restart-cedar.sh` (which
had never accepted `aa`), three help texts and two lists in mrgather. Adding
the Student Holds report reduced that to three: `R/data-parsers/report-specs.R`
for the parser, `scripts/report-registry.sh` for the shell scripts, and
`REPORT_HANDLERS` in mrgather. The first two are held to each other by
`test-data-update-pipeline.R`; mrgather is a separate repository
(`cedar-collective/mrgather`), and nothing checks its list but its own
refusal of a code it does not have. *Done when:* one file is the list and the
others are generated from it or read it, mrgather's included (ROADMAP:
production's mrgather as a checkout of its repository).

**M67 — One Retention section reads every student level, whatever the page's
control says.** "Courses Harder on Students with Lower GPAs"
(`retention_dashboard_band_courses()` over `get_course_band_dfw()`) takes the
page's term type and campus and no student level. With Undergraduate chosen it
still reads every graded attempt in a course whose student has a GPA band:
graduate students, and students at a non-degree level. It also reads the
campus control as the campus that taught the course, where the sections above
it read the same control as the student's home campus. The section's method
note has said the second since it shipped and says the first since
2026-11-23; neither is a wrong number, but one control means two things on
one page. Found 2026-11-23 writing down who each Retention section counts
(read from the code). Resolved 2026-11-25 (branch
`retention/band-courses-page-scope`): the section reads the students enrolled
that term at the page's level and home campus, a student's whole term in or
out (`get_course_band_dfw()`'s `opt$student_level` and `opt$student_campus`,
through `scope_student_terms()`), and each of their courses on the campus
that taught it, as "Courses Where a DFW Costs the Most" does. Both controls
now mean one thing on the page. Measured on the development machine's own
copy of the tables (older than the app's), Fall 2021 to Fall 2025,
undergraduates of the main campus:

- 24.3% of the student-terms the old reading held were not undergraduates
  (16.6% of its graded attempts); 0.1% had another home campus.
- 31.1% of these students' graded attempts were taught on another campus
  (online, mostly), and the old reading held none of them.
- Courses read went from 103 to 168, 65 of them taught on another campus;
  harder from 7 to 10 and easier from 10 to 13. Every course on a list before
  is still on it. (The app's copy reads 168 too, 9 of them harder, and each
  list holds two courses taught on another campus.)
- Every level the page offers builds, by either GPA, in 0.4 to 4.8 seconds;
  graduate students have no course with 30 attempts in the lowest band.

Fixed with it: the cone took the lowest high-school GPA band from the
students present, so with nobody in the lowest band the next one up was
called the lowest (read from the code), and with nobody banded it stopped
("subscript out of bounds"), which a level choice makes reachable (graduate
students by high-school GPA). The lowest band is now the scale's, whoever is
in it, and a scope with no student reads as "No course had 30 graded
attempts…". `test-course-band-dfw.R` reads BD02 (graduate students, students
of another home campus, and one student whose level changes between terms,
in one course); 14 deliberate breaks of the change each failed a test. I86
and M76 came out of the same work.

**M78 — `./run-tests.sh --changed` compared a branch with the local `main`,
however old.** Resolved 2026-11-26 (branch `test/model-source-warning`). The
change analysis took its diff from `git merge-base HEAD main`. A clone worked
in branches and worktrees rarely pulls its local `main`: on the development
machine that day it stood 25 merges behind `origin/main`, and the analysis of
a branch that changed 13 files listed 104, selected nine browser suites and
the first-sessions run, and would have called `R/trunk/utils.R` model source
in a branch that had not touched it. It now takes the later of the two points where
the branch left `origin/main` (as of the last fetch) and the local `main`.
`test-ci.R` holds both orders against a stand-in `git`.

**M77 — Nothing says a change touches projection model source until the
deploy takes an hour.** Open; the first half of *Done when* is done
(2026-11-26, branch `test/model-source-warning`):
`scripts/projection-model-source.sh` reads the list from the function's own
text (`test-ci.R` holds that the two are one list), `./run-tests.sh --changed`
marks a listed file and says what the deploy will do, and the pull-request
checks carry it as the name of a check, `Deploy: rebuilds both projection
bundles (about 45 minutes)` or `Deploy: no projection rebuild`, which never
fails. What is left is the second half: `utils.R` is still on the list whole.
`enrollment_projection_model_source_files()`
(`R/features/enrollment-projections.R`) lists 22 files, and an edit to any of
them, a comment included, makes the next deploy rebuild both projection
bundles, about 20 minutes each, inside a deploy step that is stopped at 60
(I6 is what a rebuild stopped there leaves behind). `R/trunk/utils.R` is on
the list, and it is also where a general helper goes by habit. On 2026-11-25,
#405 added `cedar_compile_server()` and `cedar_server_to_run()` there. No
projection reads either, nothing in the pull request or its checks said what
the file was, and the deploy of #404 to #407 spent 45 minutes in "Deploy
over SSH", 43 of them rebuilding the two bundles ("model source changed:
R/trunk/utils.R"), where a deploy that rebuilds nothing takes about six. M62 had met the
same thing on 2026-11-22 and put `fmt_count()` in `display-format.R` for that
reason: the lesson was written in that entry and stood in nobody's way.
Moving the two functions out now would be one more edit to the file and one
more rebuild, so they stay. *Done when:* `./run-tests.sh --changed` and the
pull-request check say when a diff touches a file on the list and what the
deploy will then do, reading the list from the function itself; and what
projections read of `utils.R` is a file of its own, or the list is of
functions and not of files, so that a helper beside them costs nothing.

**M76 — A page's student scope (level that term, home campus) is written out
in five more places.** `scope_student_terms()` (`R/branches/student-terms.R`,
added 2026-11-25 for M67) is the enrolled student-terms of a level and a home
campus, and the Retention page's two course sections read through it. The
same filters are still written inline, each with its own handling of
`enrolled`, of a missing level and of the order they apply in:
`get_credit_ceiling_crossings()` (`R/cones/credit-ceiling.R`),
`get_course_cohort_effect()` (`R/cones/course-cohort-effect.R`, home campus
with a classification), `course_cohort_gen_ed_candidates()` and
`course_cohort_context_defaults()` (`R/features/course-cohort-context.R`),
`entering_students()` (`R/branches/retention-context.R`, the level on the
enrolled rows and the campus on the entering term) and
`retention_scope_facts()` (`R/features/retention-dashboard.R`, which also
counts the rows at another level). M67 was one such copy missing. Found
2026-11-25 looking for a helper before writing one; none was changed. *Done
when:* each reads through `scope_student_terms()`, or its header says why its
scope differs.

**M68 — Against Non-Takers took one to two minutes for a large course, and
runs when Downstream opens.** Resolved 2026-11-25 (branch
`perf/non-takers-run`) for the length of the run: 12.5 seconds locally for
FYEX 1110, where it was 46 to 50; on production after the deploy, 17.4 and
20.6 seconds in two sessions. FYEX 1110 on production before it,
2026-11-25: `course_cohort` 91.2 seconds, between `later_course` (5.4) and
`course_sequence` (19.5), during which R answers no other session (I82 is the
empty page it showed meanwhile). A profile of the local run gave 20 seconds in
`student_term_aid()` (`R/branches/comparison.R`: a `summarize(max(…))` per
student-term over the whole declarations table, the same for every course and
every call, wrapped in `suppressWarnings()` per group), 12 in the `touched`
table of `get_course_similar_students()` (a `summarize()` per member and
course), both rebuilt on each of the three readings the payload makes, and 6
in the balance table. What changed: `student_term_aid()` counts over the whole
table at once (4.6 seconds to 0.1 on the development machine, the same
426,241 rows); `prepare_course_similar_students()` builds the members, their
cells and each course's non-takers once and the payload reads it three times
(`prepared =`); each member's courses are counted over the rows at once. The
payloads for FYEX 1110 and ENGL 1110, with everyone else and with Gen Ed
non-takers, are `identical()` to the code before on the full tables. What the
run still costs, on the development machine outside the container: 5.6
seconds, of which the balance table 1.7, similar students 2.6, the raw
comparison 1.0. At a Glance starts all three runs on opening (decided
2026-11-25); M72 is what keeps a course's results for the sessions after the
first.

**M71 — The sequence comparison asked each student in turn.** Resolved
2026-11-25 (branch `perf/sequence-first-attempt`): 5.7 seconds locally for
FYEX 1110's default pair, where it was 8.4 to 11.6; 2.2 seconds for a large
pair on the development machine outside the container, where it was 4.4. At a
Glance's last step ("Did passing it first help?") took 19.5 seconds for FYEX
1110 on production on 2026-11-25, where the page's estimate for it reads
"usually ~2–5s"; after the deploy, 8.5 and 10.0 seconds in two sessions.
`get_course_sequence_effect()`
(`R/cones/course-sequence-effect.R`) picked each student's first attempt of
the later course with a `summarize()` per student-term and a `slice_head()`
per student, then each student's first pass of the earlier course with a
`min(term)` per student; and `build_comparison()`
(`R/branches/comparison.R`) picked each student's declaration record with a
`slice()` per student. Each is now one sort and the first row a student has.
The results for three large pairs, and the Against Non-Takers balance tables
that read the same builder, are `identical()` to the code before on the full
tables. Two picks had no test that held them: `.sequence_repeat_fixture` adds
a student with an A and an F in the later course in one term (the DFW is
kept) and one who passed the earlier course before and again after the later
one (the first pass counts). What the step still costs is the comparison
builder's as-of joins for entering GPA and credits (about half of the 2.2
seconds).

**M75 — The first session of a process starts about 2 seconds slower than
later ones, and it is not compilation.** Open. On fresh starts of the
development container (2026-11-25, `tests/e2e/fresh-start.test.mjs`, home
page, from opening the page to the end of the session's first busy-to-idle
cycle), the first session took 6.1 and 6.5 seconds with the server function
compiled at start, and 6.1 to 7.6 before; sessions three to six took 4.2 to
5.0, apart from the one below. Its server begins 0.2 to 0.4 seconds after the
connection, like any other, so the time is inside the session's own start.
Compiling every function in the global environment at start (33 seconds
against 6.3) left it at 5.9, so it is not R compiling CEDAR's functions. Not
traced: what a process does once on its first session (Shiny's own first
read of `server.R`, files read on first use, the first render of the home
page) is where to look, by profiling the server function on a new process
(`Rprof()` started before it and stopped in `session$onFlushed()`), first
session against second. Seen beside it and also not traced:
about one later session in four takes 1.2 to 1.6 seconds longer than its
neighbours (5.6 to 6.2 against 4.2 to 4.5), most often the fourth. It is not
garbage collection either: with `gcinfo(TRUE)` on, no full collection fell
inside any of seven sessions' starts (the first at 6.7 seconds, the fourth at
5.7), and each start saw one level-1 collection at most. Production's morning restart
is followed by a request that fetches the page and opens no session, so the
first reader of the day is this first session. **Traced 2026-11-25**, by the
profile this entry asked for
([a session's start](docs/developers/performance-monitoring.md#a-sessions-start)):
three sessions in turn on a new process of the development container, the
build-ahead finished. Inside the server function the first sampled 4.3
seconds and the next two 2.0 and 2.1. The lines the first has and the others
have not: `headcount.R:132` and `:95`, 1.3 seconds, the Headcount module's
set-up reading its filter choices through `cedar_shared_result()`, which the
first session of a process builds (`ui-helpers.R:1639`) and every later one
reads; `headcount.R:195`, 0.7, the first render of its download control;
`population.R:1297` to `1323`, 0.4, program labels; and 0.3 in Gen Ed's
set-up (`gen-ed.R:1177`, `:1211`). So most of it is a result shared by every
session that the first one still builds. One run, emulated. *Done when:*
Headcount's filter choices are a job of the build-ahead
(`cedar_preload_shared_results()`), the same profile shows what is left, and
either the start does that too or the entry says why it stays.

**M74 — The projection lock test fails when the machine is busy.**
Resolved 2026-11-25 (branch `test/first-suite-session`): the test no longer
holds a one-second loop to a three-second limit. `test-projection-refresh.R`
(the test that a live build keeps its lock and a killed one loses it) started
a second R process that holds the lock with a heartbeat every second, slept 4
seconds, and expected the lock to be refused under a stale limit of 3
seconds; then killed the holder, slept 5, and expected a takeover. On
2026-11-25 a full `./run-tests.sh` started right after a container was
removed gave 9,077 passed and 2 failed, both there (line 319, "Expected ...
to throw a error"; line 328, "Rebuild already running", the mirror image).
The file alone, minutes later: 82 passed, 0 failed. A heartbeat that arrives
a second or two late was enough to flip either expectation. The limit is now
600 seconds throughout and the test moves the heartbeat's date itself: set
back an hour, a live holder's next beat brings it forward (waited for, not
timed) and the lock is refused; after the kill, set back until it stays back
(`set_file_time_back()`, `helper-projection-refresh.R`, which the takeover
test beside it uses too) and the lock is taken over. Ten runs of the file with
every core busy (ten `yes` processes on eight cores), ten passed, the last
five as the test now stands; and each of
four deliberate breaks of the lock fails it (no heartbeat, a live lock taken,
a dead lock never taken, a heartbeat that outlives its holder). Found on the
way: the test above it ("automatic runs share the manual lock…") called the
refresh with its real build behind the lock, so a lock that did not hold
started a real projections build and the file hung; it now passes a build
that only records the call, and fails in a minute.

**M73 — The development container has about 400 MB to spare, and building courses ahead takes it.**
Resolved 2026-11-25 (branch `test/first-suite-session`): a development
machine builds no course ahead. The app image runs emulated in a Docker VM of
3.8 GiB on the development Mac. On 2026-11-25, seven browser suites in a row
(the five Course Dynamics suites, Graduation, DFW Rates) against a process
that built no course ahead passed, with the container at 3.2 GiB after the
first suite and 3.42 at the most. The same suites against a process that had
built two courses ahead (2.7 GiB once the build-ahead finished): the R process
was killed for memory during the DFW Rates suite, at its spring build, the
page reloaded, and the suite failed with "Execution context was destroyed"
(`docker inspect --format '{{.State.OOMKilled}}'` gave `true`, and the log
shows a second start). One run each, so the build-ahead is not shown to be
the cause; the margin is what is shown. Production's host has 8 GB and is not
close. The developer's `.env` sets `CEDAR_PRELOAD_COURSES=0` (decided
2026-11-25), `.env.example` carries the line, and
`docs/developers/e2e-testing.md` says why beside the other memory limits.

**M72 — Downstream's three comparisons were built again by every session.**
Resolved 2026-11-25 (branch `perf/downstream-shared-results`). At a Glance
runs Next Courses, Against Non-Takers and Prepared for It as Downstream opens,
and each session built all three for itself. On production after M68 and M71,
two sessions one after the other opened Downstream for FYEX 1110: ready in 46
and 38 seconds (the comparison with non-takers 20.6 and 17.4, the sequence
comparison 10.0 and 8.5, the later course 5.6 and 4.1), during which R
answers no other session. Each result is now read through
`cedar_shared_result()`, keyed by the course, the campuses and every setting:
the first session to ask builds it, behind the overlay as before, and every
later session on that process reads it. In the local container, three
sessions in turn for FYEX 1110: 47 seconds for the one that built, then 11.8
and 7.3. The later-course list and the settings Against Non-Takers opens on,
which every session also worked out for itself, are shared the same way. A
result that lost a part to a caught error is shown to its session and not
kept (`keep =`). What it
saves, from production's timing log for the 30 days to 2026-11-25: of 156
course analyses over 83 courses, 27 (17%) were of a course already analysed
that day. A course's three results are about 1.1 MB (0.95, 0.12 to 0.25 and
0.04) of the app's 200 MB cache, which drops the least recently read first.
Still paid by every session: reading the course's own outcomes (about 2
seconds, behind the overlay) and drawing At a Glance (about 4, with no wait
shown: the course's return rates and the page itself). The ten courses
analysed most are built ahead at start since 2026-11-25, so their first reader
does not wait for the three comparisons either
([built ahead](docs/developers/shiny-modules.md#downstream-for-the-courses-analysed-most)).

**M69 — A soft restart leaves the previous R process running.**
`restart-cedar.sh` touches `restart.txt`; Shiny Server starts a new R process
for new sessions and, with `app_idle_timeout 0`, never ends the old one. On
production on 2026-11-25 the process started after the 10:00 UTC container
restart was still there at 14:19 beside the one the 11:00 soft restart started:
1.2 GB resident and 1.4 GB in swap on an 8 GB host, until the next day's
container restart. Done when the morning job ends with one R process (a hard
restart there, or the soft restart ends the old worker), checked with `ps` in
the container. Production's 11:00 UTC job was changed to
`restart-cedar.sh --hard-restart` on 2026-11-25; its first run is 2026-11-26.
`docs/developers/droplet-installation.md` still gives a new host one job with
a soft restart.

**M70 — Shiny reads `ui.R` and `server.R` itself; `global.R` reads them too
and `app.R` was never used.** With a `server.R` in the directory Shiny ignores
an `app.R`: it sources `ui.R` on the first request and `server.R` on the first
session, each into its own environment, and uses what those reads return. So
the UI is built twice at start (the "Navigation containers" warning appears
twice in every log), and the server function Shiny runs is not the one
`global.R` made. Partly resolved 2026-11-25 (branch `perf/first-sessions`):
`server.R`'s last line now returns the function `global.R` compiled, which is
what I81 needed, and `docs/developers/index.md` and `AGENTS.md` say which file
does what. What remains costs the start and no reader: the UI is still built
twice, 2.1 seconds each in the development container, once in `global.R` and
once at the first request (the restart's own warm-up request); and `server.R`
is still read twice. `app.R`, which nothing read, was deleted on 2026-11-25
with its mount in `compose.dev.yml`. `global.R`'s read of
`ui.R` is also what puts `cedar_sections`, `cedar_registrations`,
`cedar_programs` and `cedar_degrees` in the global environment, where
`server.R` reads them as bare names (on 42 lines), so that read cannot simply go.
*Done when:* the UI is built once (`ui.R` returning what `global.R` built, the
way `server.R` now does) and `server.R` no longer depends on names `ui.R`
defines.

### Documentation and naming

**M20 — Function reference can go stale.** *Done when:* CI regenerates it or
fails on stale output.

**M21 — Install docs unverified.** *Done when:* a fresh install has been done
from the docs alone, and the docs corrected.

**M22 — Misleading internal names.** `course-report.R` for Course Dynamics,
`seatfinder` for Open Seats, department-profile naming. *Done when:* renamed in
focused, tested patches.

### Data model

**M23 — Campus vocabularies differ by table.** The same field name can hold codes
in one table and labels in another: `student_campus` is a name in
`cedar_programs` ("Albuquerque/Main", "Taos") and a code in `cedar_registrations`
("ABQ", "TA"), and no file maps one to the other, so headcounts filter on names
and course figures on codes. `institution/unm/campuses.csv` gives no expansion for EW, EF,
ELA and TAQ, and the data uses codes it does not define (05, EG, ET, TAP
locally, a few sections each). Admin > Data & Usage > Mappings shows both
(Counting rules; Campuses). The campus list moved to `institution/<id>/campuses.csv`
on 2026-10-16. *Done when:* each campus field holds one vocabulary and every
code in the data is defined or reported as a source error.

**M24 — Enrollment lifecycle labels differ by tab.** The same class-list counts
carry different names: `census_enrl` is "Census Estimate" (Enrollment),
"Census enrollment" (Course Dynamics), "Census Enrollment" (`server.R` export),
and "Enrolled" (Regstats); `first_day_proxy` (`registered + dr_all`) is "Ever
Registered Proxy" in Enrollment but described as a first-day roster in
Projections. No day-1 snapshot exists, so "first day" overclaims. A dated
reconstruction now exists — `first_day_enrl` (`calc_first_day_enrl()`, definition
`first-day-enrollment`), shown on Course Dynamics — which makes the proxy's name
actively misleading beside it: rename `first_day_proxy` to an ever-registered
name. *Done when:* each lifecycle column has one label, from
`docs/_data/definitions.yml`, used everywhere it is shown.

**M31 — Projection `recent_history` saves a join collision.** In
`attach_projection_movement_signals()` (`R/branches/enrollment-projections.R`),
`market_prior` renames `market_students` but not `market_incoming_first_sem`, so
saved bundles carry `market_incoming_first_sem.x` (the source term) and `.y`
(the prior term). Nothing reads either, and the validator does not reject
extra columns. *Done when:* the prior column is named
`prior_market_incoming_first_sem` or dropped, and the validator rejects
`.x`/`.y` suffixes in saved tables.

**M32 — One class-list term per season carries no status dates.** For one
Fall and one Spring term in the projection window (and a Summer between them,
which projections do not read) every class-list row lacks a Registration
Status Date, so `calc_first_day_enrl()` returns `NA` for every course and the
projection cannot judge saturation, capacity reached, or the floor for the
aftcast that reads them: one of the four history terms in each season. Admin >
Data & Usage and `class_list_status_date_coverage()` list which; prose does not
name them, because re-pulling a term's class list fills its dates in (the
projections scope bar names them from the loaded bundle for the same reason).
2026-11-09: the coverage report shows the undated terms are Fall 2024, Spring
2025 and Summer 2025, whose class lists were pulled on 2025-04-11, 2025-06-05
and 2025-08-04, before the Class List report carried the Registration Status
Date column; every term from Fall 2025 on is complete. They hold 40 of the 215
Spring 2027 and 60 of the 242 Fall 2027 past forecasts, 19% and 28% of the
error, as "seats or first-day data missing". *Done when:* the three terms are
re-pulled from MyReports with the current report definition, parsed and
transformed, the coverage report shows dates for every term from
`projection_history_start_term` on, and the projection bundles are rebuilt.

**M35 — The projection range covers two outcomes in three, and one in three
when seats move.** `projection_low` / `projection_high` are the projection plus
or minus the 80th percentile of the course's own absolute aftcast misses
(`error_q80`, three or four folds). Rebuilt rolling on the 2026-10-20 bundles
(each fold's range from earlier folds only), it covered 67% of 102 Spring and
123 Fall aftcasts. Where seats stayed within 10% of the previous same-season
offering it covered 88% (Spring) and 94% (Fall); where they moved, 40% and 33%.
Most misses fell below the range (actual above it). The page claims no
coverage level, but a reader takes a range as likely bounds. *Done when:* the
range is conditioned on the seats (steady, or the draft schedule's change) or
the page says plainly that it assumes steady seats, and a test pins the
rolling coverage on a worked frame.
*Done 2026-10-24 (model 0.25.0):* the page says the range assumes seats like
last year's and states its rolling coverage by seat condition.
`summarize_projection_range_coverage()` computes that live from the saved
aftcasts: each past range comes from earlier forecasts only, under the
published rule. A row whose draft moves the seats 10% or more from last year's
same term says so under its range. On the 2026-10-24 bundles the range held
for 86 of 105 (Spring) and 98 of 115 (Fall) with steady seats, and for 40 of 99
and 28 of 91 where seats moved. The test pins the rolling count on a worked
five-forecast frame. Conditioning the range itself on the seats remains
undone.

**M36 — Pooling ABQ and EA hides a full online campus.** The
`abq_ea_course_market` treats online seats as a substitute for in-person ones.
In Spring 2026, 33 scope courses were taught on both campuses. In 11 of them EA
was full on the first day (98% or more) while ABQ had 10% or more room, and 10
of those read under 90% full pooled. In Fall 2026 it was 4 of 40, CLST 1110
among them with 68 students waiting for EA and 217 open ABQ seats. A pooled
"capacity appears sufficient" or a draft-schedule "covers" is then wrong for
the students who want the online section. *Done when:* each published row and
each draft-schedule row flags a campus that was full on the first day while
the other had room, without splitting the forecast itself.
*Status, 2026-10-24 (model 0.25.0):* published rows done; draft-schedule rows
remain, with the Draft tab redesign. The bundle saves `recent_campus_history`:
each campus's own sections, seats and first day for the recent same-season
terms. `delivery_components` could not serve, since it holds only the campuses
in the target draft. The summary flags "EA full last term, ABQ had room".
On the 2026-10-24 bundles (Oct 23 pull) it flags 9 of the 34 Spring 2027 rows
taught on both campuses in Spring 2026, all EA full with ABQ under 90%. That
is not the hand audit's 11 of 33: ECON 2110 and RELG 2110 EA read 97.8% and
97.5%, just under full, and the difference was not traced. Fall 2027 flags 2:
FYEX 1030 (EA full) and NATV 1150 (ABQ full, EA at 86%). CLST 1110 is not a
published Fall 2027 row, so its flag cannot show. The flag reads only complete
campus first days: on the Oct 8 class list it found 1 Fall course, because 16
campus rows had a second-half session not yet begun.

**M37 — Pathways cannot tell a field's B.A. from its B.S.** A population is
chosen by program name or major code, and both are shared: `BA-PSY-AS` and
`BS-PSY-AS` are both "Psychology", major code `PSY` (11,596 and 3,913 program
rows). Chemistry, Biochemistry, Biology, Anthropology and Film and Digital
Arts (B.A. and B.F.A.) are the same. Banner's full program code
(`cedar_programs$program_code`) does separate them, and since 2026-10-26 each
Degree Explorer map names its own (`degree_catalogs.csv`, `program_codes`).
*Done when:* a Pathways population can be restricted to one degree's program
codes, and a page that pools them says so.

**M38 — The designed class-list fixture carries student level as a name,
production as a code.** `cedar_registrations$student_level` is `UG` / `GR` in
production (Banner's `Student Level Code`), and `Undergraduate` / `Graduate`
on academic studies; the fixture's `cedar_registrations` says `Undergraduate` on
both tables, so a test written against it cannot see the vocabulary split
ADR-001 §2 describes, and a filter that works on the fixture
(`student_level == "Undergraduate"`) matches nothing in production — which is
how the first return-snapshot probe, written against the fixture, read zero
undergraduates on real data. ST01
uses production vocabulary on purpose. *Done when:* the base fixture's class
list carries the codes and every test that filtered on the name is moved to
the code (or to `cedar_student_terms`, which stores the code).

**M39 — The excluded-course list is matched by code outside the keyed readers.**
`excluded_courses` (`institution/<id>/excluded_courses.csv`) names codes. A
table keyed on `course_id` (ADR-001 step 4) carries the course's current
code in `subject_course`, so a list matched against that column by code
misses every course the list names by an older code: UNM's list names CCS
495, 597, 599, 697 and 699, the class list and schedule key them as CCST,
and matched that way Regstats let 13 thesis and dissertation section groups
into its Fall 2026 saturation screen (measured 2026-11-06, caught before
merge). Since reader PR 3 the trunk `uel` filters drop a keyed table's rows
by course (`drop_excluded_courses()`, `excluded_course_ids()` in
`R/trunk/filter.R`: every row of a course the list names under any code it
carries there), and `get_reg_stats()` drops the excluded courses from both
whole tables once, so its class-list recount under a student-level filter
excludes them too, which it never did. Tables read by code still match by
code, so SOC 699 sections stay in where the list names only SOCI 699, and a
keyed table filtered to a few terms first can only find the codes those
terms carry. *Done when:* the list is resolved through the course dimension
once at load (`resolve_course_codes()`), and every exclusion compares ids
with ids.

**M28 — The HR department list is a hand-kept R list.** **Done 2026-10-16.**
`hr_org_desc_to_dept` (79 names to 32 departments) now comes from
`institution/<id>/source_organizations.csv`, validated at load so every unit
it names is in `units.csv` (`validate_text_maps()`; `test-catalogs.R`).
The report was no longer pulled; on 2026-11-18 the file, the HR parser and
`cedar_faculty` were retired together (`docs/developers/source-to-cedar-manifest.md` §5).
