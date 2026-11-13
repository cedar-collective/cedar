---
title: Dept Trends
parent: User Guide
nav_order: 2
---

# Dept Trends
{: .fs-9 }

**Multi-year historical analysis of a department's programs, students, and instructional output**
{: .fs-6 .fw-300 }

---

Dept Trends is the longer-term department report. Unlike the [Dept Dashboard](dept-dashboard) — which auto-loads and focuses on current-term course activity — Dept Trends assembles historical views from versioned tab caches. Standard department and campus scopes are prepared after production data refreshes; an uncommon scope computes once on demand and is then cached. The cache stores ready-to-render charts, and a change to the app's visual palette creates a distinct cache entry for that styling.

Select a department (and optionally a campus) and the report assembles automatically. The strip under the filters lists the codes behind the department, each program with its name: course subject codes, program codes, accelerated online (X-prefix) codes, and pre-major codes. A code that applies only in one college or at one course level says so. They are the rows the institution mapping files assign it; Admin > Data & Usage > Mappings explains each, and the same block appears on the Dept Dashboard and Headcount.

---

## Headcount

{% include definition-summary.html id="program-headcount" %}

Trend charts showing how many students have been enrolled in the department's programs over time, drawn from declared program records rather than course enrollment. Broken out by:

- Undergraduate majors
- Undergraduate minors
- Graduate majors
- Graduate minors

{: .note }
These are counts for each observed program term, not just counts of new entrants.
For course registrations, see [Enrollment](enrollment-tab); the dashboard's
headline headcounts also use program records.

---

## Enrollment

Section-level enrollment analysis across all terms in the data:

- **Highest total enrollment** — courses ranked by total students enrolled over time
- **Highest mean enrollment** — courses ranked by average section size
- **Mean enrollment distribution** — histogram of typical section sizes across the department's offerings

Useful for understanding which courses carry the most instructional load and where section sizes cluster.

---

## Demographics

How the mix of new entrants has shifted over time for declared majors and pre-majors in this department. Students are counted once — at their first term in the program. Categories include First-Time Freshman, Transfer, Continuing, and others drawn from Banner classification codes.

Useful for seeing whether the mix of students entering a program is changing — more transfer students, fewer freshmen entering pre-major, and so on.

---

## Degrees

Degrees awarded by programs in the department over time:

- **By major** — trend lines for each degree program
- **By program stacked** — combined view showing the relative contribution of each program to total degree output

Degree production often lags behind enrollment changes by several years, so this view is best read alongside headcount, entry mix, and curriculum context.

---

## Credit Hours

{% include definition-summary.html id="credit-hours" %}

The credit-hour tab includes:

- **At census and end of term**: the department's SCH at census (solid line) and still registered at the end of term (dashed). The gap between the lines is the credits of students who withdrew after census. Every other chart on the tab counts at census.
- **By level and subject code** — SCH per term split by course level (lower 100–299, upper 300–499, graduate 500+) and by subject code prefix. Departments that teach under multiple subject codes (e.g., BIOL and BIOC) appear in separate facets.
- **By subject code combined** — same data collapsed across levels, showing total SCH per subject code as a stacked bar over time.
- **By major (home vs. outside)** — whose students are taking these courses? Home majors are students whose Banner major code matches the department's programs; outside majors are everyone else — other programs, pre-majors, undeclared students. Shown separately for lower and upper division.
- **By instructor type** — SCH attributed to Professor, Associate Professor, Assistant Professor, Lecturer, Term Teacher, TPT (temporary part-time / adjunct), and Grad (graduate teaching assistant). Requires HR data to be loaded; charts are hidden if HR data is unavailable.

The methodology note at the top of the tab explains exactly what is and isn't counted.

---

## Courses Taken

The inverse of the Credit Hours tab's Students Served charts. Those ask whose
majors fill this department's seats; this tab asks which units teach the
courses this department's majors sit in.

A member is an enrolled student-term whose primary major belongs to the
department, pre-majors included. Each member's class-list registrations that
term (registered at the pull, or withdrawn late, which held a seat past
census) are split by the unit that taught the course, as the mapping files
decide it. Shares are within the term and teaching campus, over every member
registration there. A subject no mapping row has decided appears as its own
"No unit decided" row rather than being given a unit.

The tab reads from the top:

- **Own-unit share over time** — a line per teaching campus: of the majors'
  registrations each term, the share in the department's own courses. The
  table under the chart gives the students and registrations behind each
  point. A shaded term is in progress.
- **Teaching units, latest term** — one bar chart per teaching campus, headed
  by that campus's majors and registrations: the department's own courses
  first, then the eight outside units that taught the most of the majors'
  registrations, then every other unit as one grey bar. The table under the
  charts lists every unit, with students, registrations and share.
- **Teaching colleges over time** — one stacked bar per term, split by the
  college of the teaching unit, one chart per teaching campus.
- **Top outside courses, latest term** — the courses outside the department
  that the most of its majors sit in, with the share of that term's majors
  and the count a year earlier.

A teaching unit or college that taught fewer than ten of the majors in a term
is not shown on its own: it is pooled with the others like it, as one table
row or one grey segment. Most colleges teach a department's majors a course
or two, and listing each would hide the few that carry the load. A campus
with fewer than ten of the majors in a term has no point on the line that
term and no chart; its counts are in the tables.

**Term types** chooses the terms the two over-time charts and the table under
the first one show. It opens on Fall and Spring. Summer is a tick away, and
off to begin with: few majors enrol in summer and they take a different mix
of courses, so a summer point between a spring and a fall reads as a change
when nothing about the department changed.

Where a department has more than one program, a Program picker narrows the
majors to one of them.

The tab computes when you open it and is not cached; it follows the page's
campus scope.

---

## DFW

Nonpassing course outcomes under CEDAR's shared DFW definition, with instructor-level comparison. This section is **password protected** — contact your CEDAR administrator for access.

DFW data is intentionally not public within the app because it involves identifiable information about specific instructors. The data is intended to help departments understand patterns at the course and program level and to support instructors — not to evaluate individuals punitively.

---

## Common questions

**Why is my department missing from the list?**
The dropdown shows departments with course data in CEDAR. If your department is missing, it may use a different Banner code than expected, or may not have section data in the current dataset.

**Why don't the credit hour numbers match what IR reports?**
They should. CEDAR counts attempted credit hours at census, as UNM's official enrollment report does: every enrollment still registered, plus every student who withdrew after census, whatever grade they receive. For Chemistry, Fall 2022–2026, the two agree to within 0.2%. Remaining differences come from scope: the official report covers every location of the Albuquerque campus, so compare it with Albuquerque and online (EA) together. A figure that counts only earned credits, or only students still enrolled at the end of term, will be lower. The end-of-term count is the dashed line on the first Credit Hours chart. The Credit Hours tab explains the exact methodology.

**Why does the newest term look different on the charts?**
A term that has not finished is shown as soon as it has registrations, shaded and labeled *In progress*, with the date of the data pull. Its enrollment, headcount, and credit hours are current registration and will change until the term closes. DFW and other grade-based measures stop at the last term with grades posted.

**Can I compare two departments side by side?**
Not currently — generate profiles separately for each department. Cross-department comparison is on the roadmap.
