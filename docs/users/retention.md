---
title: Retention
parent: User Guide
nav_order: 16
---

# Retention
{: .fs-9 }

**After the first year: are students coming back each semester, are they keeping pace, and who is not?**
{: .fs-6 .fw-300 }

---

Retention is the institution-wide view of whether enrolled students come back, the middle of three pages: [First Year](first-year) follows each entering class through its first semesters, Retention reads every enrolled student term by term, and [Graduation](graduation) reads the end. It lives under **Bird's Eye > Retention**. It answers four questions, in order: is the share who come back rising or falling; how often students with a warning sign came back; whether each classification and college is moving the same way; and in which courses a D, F or withdrawal goes with not coming back the most.

One course's retention is **Course Dynamics > Downstream > Coming Back** ([guide](course-reports#retention)).

---

## Controls

The page builds as soon as it opens; there is no run button.

| Control | What it changes |
|---|---|
| **Term type** | Fall or spring: the term the students were enrolled in. One at a time, since a fall's students are not a spring's. |
| **Student level** | Undergraduate to start. A level is its own group of students: one at another level is not counted. |
| **Home campus** | The students' home campus. It opens on the main campus; clear it to read every campus. Coming back is counted at UNM on any campus. |

---

## Who is counted

The strip under the controls says who the page is counting, with the numbers for the latest term it reads:

- **Counted**: every student enrolled that term at the chosen level and home campus.
- **First-time students**, **Transfer students**, **Start not on record**: how many of them the record calls a first-time student or a new transfer in the term they arrived, and how many it never calls new in the terms on record (readmitted after time away, moved from another campus or level, or here before the records begin). The three add to the number counted. **Transfer students are counted** in every return rate on the page.
- **Not counted**: students at another level that term, each level with its number. At UNM non-degree students are their own levels (Non-degree undergraduate, which holds high-school students taking college courses, and Non-degree graduate), so **they are not among the undergraduates**; choose that level to read them.

Three sections count a narrower or wider group, and say so in **How this is counted**:

- **Still Here, and Moving Forward?** follows first-time students, or transfer students by the credits they brought, as its control says. A student with no start on record is in no class.
- **Summer and Staying on Pace** reads first-time students only.
- **Courses Harder on Students with Lower GPAs** reads every student in a course, whatever their level.

---

## Sections

| Section | What it shows |
|---|---|
| **How Often Students Come Back** | One sentence with the verdict over the terms and the first and last rates, then every term's rate as a line (hover a term for its counts), with the trend as a dashed line labelled with its points a year and its verdict: rising, falling or steady. |
| **Who Isn't Coming Back** | For a late withdrawal and for a DFW grade: how many students had it, how often they came back against those without it, and what share of the students who did not come back had it. |
| **By Classification and College** | Each classification and each primary-major college: its latest rate, its rate over the terms and its terms as a small line with the trend. |
| **Still Here, and Moving Forward?** | Each fall's new students as each year begins: awarded a degree, enrolled and on pace for four or six years, enrolled and slower, or not enrolled. [More below](#still-here-and-moving-forward). |
| **Summer and Staying on Pace** | First-time students behind a 15-credit pace after each spring: how many took no summer course, took one and stayed behind, or caught up; and the courses they took. Credit brought from elsewhere is not counted, so some students shown as behind are not. |
| **Courses Where a DFW Costs the Most** | Over the latest three terms with posted grades, the courses where students who got a DFW came back much less often than those who passed: the 25 largest gaps. |

Each section's **How this is counted** gives its thresholds and the edge it reads to.

---

## Reading it

- **Coming back means enrolled the next regular term,** registered or withdrawn after census, at UNM on any campus. Summer is not a step: a spring's next term is the fall.
- **A degree that term is finishing, not leaving,** and so is a degree in the summer after a spring. Those students are left out of the rate and counted in the method note. Where a summer's degrees are not posted yet, students who have applied to graduate then are counted as finishing, and the note says how many. A degree on hold is not a degree.
- **The latest terms wait for their next term to settle.** A term whose next term is still registering has no rate yet.
- **A DFW sign needs posted grades.** A term past the last graded term, or a student with no grade posted, is in neither group.
- **A course's gap describes who fails it as much as the course.** Students who fail one course often struggle in others. Open the course in Course Dynamics for its full picture.
- **Academic standing is not one of the signs.** The two read are a late withdrawal and a non-passing grade.

---

## Still Here, and Moving Forward?

Retention says a student came back. This section asks whether they are also
earning credits. Each bar is one fall's first-time students, read as a year
begins (the second, third, fourth or fifth), and split into:

- **awarded a degree** by then;
- **enrolled, on pace for four years**: 15 credits completed here for each
  regular term since entering, summer credits included;
- **enrolled, on pace for six years**: 10 credits a term;
- **enrolled, slower than that**;
- **enrolled, earlier credits not on record**: students whose first term here
  is the first term of the class lists, which is the whole of the first class;
- **not enrolled**.

If the enrolled share grows from class to class while the on-pace share does
not, students are being kept and not moved forward. Credit brought from
elsewhere is not counted, so a student who arrived with credit is further
along than shown.

**Transfer students** have their own classes, chosen with **Students who
started as**: each fall's new transfer students, grouped by the credits they
brought (under 30, 30 to 59, 60 or more). They start part-way, so they are
not read against a four-year pace. The split is by the credits a term they
earn here: 15 or more, 10 to 14, or fewer. Students who transfer in a spring
are not in these classes yet.

**Credits earned, term by term** draws a line for each class: the credits the
middle enrolled student had earned here before each term, against the
four-year and six-year paces. Students who left are not in a line, so it can
rise because slower students left.

---

## Course-anchored retention (not in the app yet)

{: .note }
> A tab comparing later retention across the courses of one term, and one course's retention across its offerings, is built but hidden until it sets each course against its department and college. It is described below.

### What Counts As Retained

A student is counted as retained when they have any registered enrollment record
at UNM in the target future term. The measure is institution-level retention,
not retention in the same major, department, college, or course sequence.

Summer terms are skipped when counting forward. A "+1 sem" value means the next
regular term, not necessarily the next calendar term.

Rows are suppressed when they do not meet the selected **Min students per row**
threshold. This protects privacy and avoids presenting unstable rates as if
they were reliable signals.

For shared definitions, see [What CEDAR Counts](what-cedar-counts).

---

### Display Options

| Control | What it does |
|---|---|
| **Semesters to track** | How many regular future terms to check, from +1 to +8. |
| **Min students per row** | Minimum cohort size needed for a course/term/instructor row to appear. |

Changing these controls affects both retention views.

---

### Course Comparison

Course Comparison starts from one anchor term and compares later retention
across courses.

Use it to scan a term for courses whose enrolled students returned at unusually
high or low rates in later terms. You can leave **Course(s)** blank to include
all courses, or select one or more courses to narrow the table.

Columns:

| Column | Meaning |
|---|---|
| **Course** | The subject-course value used as the anchor. |
| **Students** | Students registered in that course in the selected term, after the minimum-size filter. |
| **+1 sem, +2 sem, ...** | Share of those students still enrolled at UNM that many regular semesters later. |

---

### Course Trend

Course Trend starts from one course and compares its retention pattern across
terms.

Use it to see whether later enrollment after a specific course has been stable,
improving, declining, or too noisy to interpret. Optional instructor breakout
shows rows by instructor when available, but those rows should be read as
descriptive context, not individual evaluation.

Columns:

| Column | Meaning |
|---|---|
| **Term** | The course offering term. |
| **Instructor** | Included only when instructor breakout is selected. |
| **Students** | Students registered in that course offering. |
| **+1 sem, +2 sem, ...** | Share of those students still enrolled at UNM that many regular semesters later. |

---

### Reading The Results

Retention rates are most useful as prompts for better questions:

- Did the course enroll many first-year, transfer, or near-graduation students?
- Did it enroll concurrent-enrollment (dual-credit) high-school students? They
  are in every cohort and return on the high-school calendar, so a course they
  fill can show a low +1 rate and a high +2 rate. Gallup's Fall 2023 FYEX 1110
  cohort was 35 such students: 37% at +1, 97% at +2.
- Is the course a gateway, elective, prerequisite, or high-DFW course?
- Did the term have unusual enrollment disruption?
- Are small cohorts making the rate unstable?
- Does [Course Dynamics](course-reports) show related DFW, rollcall, or sequence
  patterns for the same course?

Blank or missing values usually mean the future term is not yet observable in
the loaded data, or the row did not meet the minimum student threshold.

---

## Related Analyses

- [Course Dynamics](course-reports) - course-level enrollment, DFW, flow, and
  course-specific retention context
- [Dept Dashboard](dept-dashboard) - current-term course activity and attention
  signals
- [Dept Trends](department-reports) - longer-term department trends
- [What CEDAR Counts](what-cedar-counts) - shared counting definitions
