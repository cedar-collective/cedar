---
title: Questions & How-Tos
nav_order: 15
---

# Questions CEDAR Answers
{: .fs-9 }

Common questions about courses, students, and programs, and how to use CEDAR to
answer each one.
{: .fs-6 .fw-300 }

Every answer has the same parts: a **short answer**, where to go **in CEDAR**,
what to **watch out for** so the number means what you think it means, and
where to read **more**. The watch-outs matter most: they are the places where a
plausible number can quietly answer a different question.

Not sure where to start? The [User Guide](users/) has a quick reference by role.

**Jump to:**
[Scheduling and seats](#scheduling-and-seats) ·
[Students and programs](#students-and-programs) ·
[Outcomes](#outcomes) ·
[Trends and resources](#trends-and-resources) ·
[Trusting the numbers](#trusting-the-numbers)

---

## Scheduling and seats

### Which of my sections are at risk this term?

**Short answer:** Look at sections below your enrollment thresholds, and at
courses running well below their own history.

**In CEDAR:** **Explore → Enrollment → Low Enrollment** lists active sections
under configurable thresholds by course level; for a future term, its concerns
mode uses prior patterns to flag courses likely to struggle. The **Dept
Dashboard** (pick campus, department, and term, then **Gather Data**) shows
courses running above and below their historical averages for the same kind of
term.

**Watch out for:** a term still in registration is a snapshot, not a final
count — it is labelled *in progress*. Compare it with earlier terms at the same
point in registration, not with their final numbers.

**More:** [Enrollment](users/enrollment-tab#low-enrollment) ·
[Dept Dashboard](users/dept-dashboard)

### Is a course turning students away?

**Short answer:** Check true waitlist demand against seats, across several
terms, together with how full the course gets.

**In CEDAR:** **Registration → Waitlists** (then **Inspect Waitlists**) shows
who is waiting, by course, program, and class standing. **Registration →
Regstats** flags **High Waitlists** and **Saturation** against each course's
own history.

**Watch out for:**
- CEDAR's waitlist count is distinct students still waiting who are not already
  registered in the same course — not the raw Banner waitlist field.
- A small waitlist in a *past* term does not prove demand was small: old
  extracts keep only students still waiting when the term closed.
- Students who wanted a course but never joined a waitlist are invisible here.

**More:** [Waitlists](users/waitlists) · [Regstats](users/regstats) ·
[What CEDAR counts](users/what-cedar-counts#waitlists)

### Where are there open seats students could take?

**Short answer:** Find courses with room in the term, compared with the same term
last year.

**In CEDAR:** **Registration → Open Seats**, set your filters, then **Find Open
Seats**. Tabs separate common courses, courses that ran last year but not this
year, new courses, and Gen Ed.

**Watch out for:** availability is counted from CEDAR's enrollment data and can
differ from Banner's live capacity during registration. Campus defaults to ABQ
and EA.

**More:** [Open Seats](users/open-seats)

### How many sections will we need next term?

**Short answer:** Start from the saved demand projection for each course, then
read how much its history supports it.

**In CEDAR:** **Registration → Projections** shows projected demand and section
need for the next Spring or Fall, for ABQ and EA together. Its **Scenario**
sub-tab answers *"if one group of students grows, what happens to the courses
they take?"*

**Watch out for:**
- Each projection carries three separate ratings — **stability**, **depth**, and
  **accuracy**. They can disagree; read all three rather than looking for one
  verdict.
- A course that filled its seats can only show demand up to capacity. Those rows
  are marked *Capacity-bounded*: the true demand may be higher.
- Branch campuses are not included.

**More:** [Enrollment Projections](users/enrollment-projections)

### What is unusual about registration this term?

**Short answer:** Compare each course with its own history at the same point in
the term.

**In CEDAR:** **Registration → Regstats** sorts courses into signals —
**Enrollment Bumps**, **Enrollment Dips**, **High Waitlists**, **Saturation**,
**Early Drops**, **Late Drops**, and **Downstream Concerns**.

**Watch out for:** a signal says a course differs from its history, not why.
Early drops (before the drop deadline) are registration churn; late drops carry
a grade consequence and are counted with DFW.

**More:** [Regstats](users/regstats)

### Which sections were cancelled, and how close to the start?

**In CEDAR:** **Admin → Cancellations**, then **Find Cancellations**, by term,
department, course, level, part of term, or delivery method.

**Watch out for:** the view shows what was cancelled and when, not why.

**More:** [Cancellations](users/cancellations)

---

## Students and programs

### How many majors do we have, and is that changing?

**Short answer:** Count unique students with an active declared program, term by
term.

**In CEDAR:** **Explore → Headcount** (then **Update Headcount**) for majors,
minors, and concentrations over time, by college or program. **Dept Trends →
Headcount** shows the same for a department alongside its other trends.

**Watch out for:**
- Headcount counts *declared programs*; it is not the number of students in your
  courses. A department with few majors can teach many students.
- Pre-majors are counted separately from admitted majors where the program
  records say so.
- A department's total depends on which programs map to it — see
  [Why does a department look smaller than it should?](#why-does-a-department-look-smaller-than-it-should)

**More:** [Headcount](users/headcount) ·
[Why numbers differ](users/why-numbers-differ)

### Who takes our courses?

**Short answer:** Look at the majors and class standing of the students in a
course, over time.

**In CEDAR:** **Course Dynamics → Rollcall** for one course, by classification
and declared major. The **Dept Dashboard**'s *Student composition* and *Where
your majors also study / Who minors here* panels do the same for a department.

**Watch out for:** a student's major is the one declared in that term, so a
student who switches majors appears under each in turn.

**More:** [Course Dynamics](users/course-reports#rollcall) ·
[Dept Dashboard](users/dept-dashboard)

### Where do students in a program move — into, within, or out of it?

**Short answer:** Follow a defined population's program records over time.

**In CEDAR:** **Pathways** — build a population (for example, a program and its
pre-majors), then **Define Population**. **Major Changes** shows movement into,
within, and out of the unit, separating pre-majors from full majors; **Course to
Major** shows which courses students took before they first entered it.

**Watch out for:** these views are descriptive. They show where a pattern is
worth asking about, not why students moved. Recent cohorts have not had time to
change majors yet.

**More:** [Pathways](users/pathways)

### Which courses do students in a program take, and when?

**In CEDAR:** **Pathways → Course Timing** shows when in their career students
take each course; **Course Pairs** shows courses students commonly take before or
after one another.

**Watch out for:** course pairs are observed sequences, not catalog
requirements. Course Timing places students by class standing or by the credits
CEDAR counted itself — never by Banner's cumulative credit fields, which show
today's totals on every past term.

**More:** [Pathways](users/pathways#course-timing) ·
[Field reliability](developers/field-reliability)

---

## Outcomes

### What is the DFW rate for a course, and is it changing?

**Short answer:** The share of students who did not pass, including those who
withdrew late, term by term.

**In CEDAR:** **Course Dynamics → DFW** for one course, with trend lines and an
optional breakdown by instructor type. **Dept Trends → DFW** for a department.

**Watch out for:**
- Only A+ through C (and CR) count as passing. C-, every D, F, W, incompletes,
  NC, NR, P, S, and late drops all count toward DFW. Early drops are never DFW.
- Terms without posted grades are left out, not counted as zero.
- The instructor-type breakdown depends on faculty HR data, which currently
  ends in Spring 2025.

**More:** [What CEDAR counts](users/what-cedar-counts#grade-outcomes) ·
[Course Dynamics](users/course-reports#dfw)

### Which courses are roadblocks for a group of students?

**Short answer:** Find courses where students in the group commonly do not pass,
and whether they continue afterward.

**In CEDAR:** **Pathways → Roadblocks** for a defined population, including
courses outside the department if those students take them.

**Watch out for:** Roadblocks uses each student's *first* observed outcome in a
course, so it differs from a course's all-attempt DFW rate on purpose.

**More:** [Pathways](users/pathways#roadblocks)

### Do students keep enrolling after taking a course?

**In CEDAR:** **Course Dynamics → Retention** shows how many students enrolled
in a course were still enrolled in later terms, optionally by instructor.

**Watch out for:** "still enrolled" means anywhere at the university, not in the
same department or campus. Students who took the course too recently to have
the follow-up terms are left out rather than counted as gone.

**More:** [Course Dynamics](users/course-reports#retention)

### Does taking course A before course B help?

**In CEDAR:** **Course Dynamics → Downstream → Course Sequence** compares later
results for students who did and did not take one course first; **Instructor
Patterns** compares later grades by the instructor students had.

**Watch out for:** students choose their own sequences and sections. The balance
table shows how alike the groups were; a difference is a lead to investigate,
not proof that one path causes better results.

**More:** [Course Dynamics](users/course-reports#downstream)

---

## Trends and resources

### How is credit hour production changing?

**In CEDAR:** **Dept Trends → Credit Hours** by course level (lower, upper,
graduate) over time. The **Dept Dashboard** shows this term's credit hours by
level.

**Watch out for:** credit hours are counted from registered (attempted) hours,
so the current term appears as soon as students register — marked *in
progress* — rather than waiting for grades.

**More:** [Dept Trends](users/department-reports#credit-hours)

### How many degrees does a department award?

**In CEDAR:** **Dept Trends → Degrees**.

**More:** [Dept Trends](users/department-reports#degrees)

### How are Gen Ed courses doing?

**In CEDAR:** **Explore → Gen Ed** (then **Run**) for Gen Ed enrollment by
modality, which majors fill Gen Ed seats, department summaries, DFW rates, and
grade distributions.

**More:** [Gen Ed](users/gen-ed)

---

## Trusting the numbers

### Why does this number differ from another tab, or from an official report?

**Short answer:** Usually because the two numbers count different things, at
different times, or for different campuses.

**In CEDAR:** start with [Why Numbers Differ Across Tabs](users/why-numbers-differ),
then [What CEDAR Counts](users/what-cedar-counts).

**Watch out for:**
- Enrollment is not one number: a section's count at a moment in registration,
  its count after drops, and the number ever registered all differ.
- Course figures are grouped by the campus that *taught* the course. A filter on
  students' *home* campus does not keep branch-taught courses out.
- CEDAR's data comes from MyReports, not the official census files, so it will
  not match census reports exactly.

**More:** [Understanding Your Data](users/understanding-data)

### Is this term's data complete?

**In CEDAR:** **Admin → Data & Usage → Data Summary** shows what is loaded and
how fresh each source is. Charts label any term still *in progress*.

**Watch out for:** a term arrives in stages — registration first, grades weeks
after it ends. Questions about grades stop at the last term with grades posted;
questions comparing years stop at the last complete term.

**More:** [Data & Usage](users/data-usage) ·
[Understanding Your Data](users/understanding-data#data-freshness)

### Why does a department look smaller than it should?

**Short answer:** Some of its programs or course subjects may not be mapped to
it yet.

**In CEDAR:** **Admin → Data & Usage → Mappings**. The **Mapping decisions**
table lists every program and course subject whose department is not yet
confirmed, largest first. *Reported today as … (phantom)* means its students are
counted under a department named after the code itself, not under their real
department.

**Watch out for:** a decision is made by editing CEDAR's mapping files (each row
links to its line). A course-subject decision reaches the numbers at the next
data refresh; program decisions take effect once CEDAR switches department
assignment over to the mapping files, which is in progress.

**More:** [Data & Usage → Mappings](users/data-usage#mappings)

---

## Getting started

CEDAR runs as a web dashboard — no R knowledge required for users. Setup requires
someone with basic R skills and access to your institution's standard enrollment
data exports. It is typically a one-time project that a technical staff member
handles, after which the dashboard updates each term.

[User Guide →](users/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Developer Documentation →](developers/){: .btn .fs-5 .mb-4 .mb-md-0 }
