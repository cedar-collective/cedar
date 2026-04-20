---
title: The Questions
nav_order: 3
---

# Questions CEDAR Answers
{: .fs-9 }

The same institution-wide enrollment data looks different depending on where you sit. A department chair needs to know which sections are at risk before the drop deadline. A dean needs to see how credit hour production is shifting across a college. A provost needs to know whether the numbers coming up from programs are built on consistent definitions.

CEDAR addresses questions at all three levels from the same underlying data and the same documented code.

---

## Unit Level

**Department chairs, program directors, and graduate coordinators**

### Which sections are at risk this term?

The **Low Enrollment** tab flags active sections below configurable thresholds, organized by course level. For future terms, it uses prior enrollment patterns to identify courses likely to struggle before the schedule is final — not after sections are already cancelled.

### How does this term compare to previous terms?

The **Dept Dashboard** shows courses running above and below their historical term-type averages side by side, flags genuinely new courses, and highlights courses that ran two years ago but are absent this term. All of this is visible while there's still time to act.

### What's happening with drops?

The **Dept Dashboard** separates early drops (pre-census, no academic consequence) from late drops (post-census, transcript impact). Each course is compared against its own historical drop rate for the same term type, so you can see what's unusual for that course specifically — not just what's high in absolute terms.

### Who's actually taking our courses?

The **Course Dynamics** tab shows the major and class-standing breakdown for a specific course, across terms. Knowing that 65% of students in an upper-division elective are not your majors changes how you think about that course's role in the curriculum.

### Where do students go after a course?

The **Course Flows** sub-tab shows which courses students take in the term before and after a specific course, and what fraction continue in the sequence. This is the data behind sequence planning — not a guess about what students should do.

### Do DFW rates differ by instructor type?

The **DFW** sub-tab shows grade distributions over time with trend lines, with optional breakdown by tenure-track vs. contingent faculty where faculty HR data is available.

---

## College Level

**Deans, associate deans, and college-level analysts**

### How is each department's headcount changing?

The **Headcount** tab shows unduplicated student counts by major, minor, and concentration across terms. Filter by college to see declared enrollment trends across all departments in one view. A department with declining declared majors but stable course enrollment may be serving other programs; one with both declining is a different conversation.

### Where is credit hour production shifting?

The **Department Profile** tab shows student credit hour production by course level — lower division, upper division, graduate — over five years. Lower-division service courses generate volume; upper-division offerings signal program health; graduate credit hours reflect a different institutional economy.

### Which departments have registration pressure problems?

The **Regstats** tab surfaces courses with near-capacity enrollment, waitlist pressure, and unusual registration-timing signals. Filter to your college to see where students can't get into the courses they need — before it becomes a petition problem or an accreditation note.

### What does DFW look like across the college?

The **Course Dynamics** tab shows DFW rates for specific courses, with trend lines and optional instructor-type breakdowns. Comparing gateway courses across departments surfaces patterns that unit-level conversations rarely produce.

### Are there cross-departmental patterns worth investigating?

The Dept Dashboard's student composition panels show which other departments a unit's majors are also enrolled in. High overlap may suggest cross-listing opportunities, advising coordination, or joint programming worth exploring.

CEDAR analyses are reproducible by design. When you present enrollment trends or DFW patterns in a program review or self-study, the methodology is documented and inspectable. The same analysis re-run the following year produces updated results automatically.

---

## University Level

**Provosts, vice provosts, and institutional research**

### Are key metrics defined consistently across units?

CEDAR's data model defines core concepts — enrollment, headcount, DFW, credit hour production — in documented, versioned code. A metric calculated by a department chair is defined the same way as one produced by IR, because they're running the same codebase. When numbers don't reconcile in a budget meeting, CEDAR makes the definitional question answerable rather than a matter of institutional politics.

### What are retention and graduation patterns across programs?

The **Retention** tab surfaces longitudinal retention and graduation rates. The **Pathways** tab enables cohort-level analysis: define a student population by program, entry type, or other characteristics, and trace how they move through the curriculum over time — at whatever scope is appropriate.

### Do institutional patterns match what programs report?

Central analytics tends to aggregate upward, smoothing over local variation. When a provost's retention numbers and a program director's view diverge, CEDAR's shared codebase provides a common basis for understanding why — not just a disagreement about who has the right number.

### Can results be traced and reproduced?

Every analysis in CEDAR is produced from source code in a public repository. Running the same analysis in a subsequent year produces the same methodology updated for new data — not a new number calculated a different way. For accreditation, program review, and any institutional research that needs to be defended, that distinction matters.

---

## Getting started

CEDAR runs as a web dashboard — no R knowledge required for users. Setup requires someone with basic R skills and access to your institution's standard enrollment data exports. It is typically a one-time project that a technical staff member handles, after which the dashboard updates each term.

[User Guide →](users/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Developer Documentation →](developers/){: .btn .fs-5 .mb-4 .mb-md-0 }
