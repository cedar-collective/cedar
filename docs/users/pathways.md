---
title: Pathways
parent: User Guide
nav_order: 5
---

# Pathways
{: .fs-9 }

**Cohort-aware curriculum analysis**
{: .fs-6 .fw-300 }

---

The Pathways tab lets you define a group of students and then trace how they actually move through the curriculum — when they encounter gateway courses, where they stop out, what sequences they follow. Unlike the other tabs, which start from courses, Pathways starts from students.

This is the right tool for questions like: *Do pre-nursing students who take Statistics in their first year continue at higher rates than those who take it later? What fraction of declared History majors ever take our 300-level courses? How do students arriving via transfer differ in their course-taking patterns from first-time freshmen?*

---

## Building a cohort

The left sidebar contains the cohort builder. You'll define your student population before running any analysis.

**Focal programs** — the program(s) you want to study. Start typing a program name to search. You can select multiple programs (e.g., all variants of a major across degree types, or a set of related programs).

**Pre-major programs** — feeder or pre-major programs whose students you want to include. This is useful when the path into a major involves a declared pre-major stage. The `include pre-majors` option controls how these students are handled:
- **Majors only** (default) — only students in the focal programs
- **Pre only** — only students in the pre-major programs
- **Lump together** — treat focal + pre-major as one group
- **Split** — run analysis on both groups side by side for comparison

**Campus** — restrict to students enrolled at a specific campus.

**Term** — restrict to program declarations in a specific term (useful for point-in-time cohort analysis).

Click **Build cohort** to create the population. The cohort size and composition are shown before you run any individual analysis.

---

## Analyses

Once you have a cohort, the right panel offers several analysis tabs.

### Course timing

When do students in this cohort take each course, relative to their program entry? This analysis identifies the typical term-relative timing of course appearances — whether students tend to take a course in their first term, second, third, and so on.

Useful for understanding whether your curriculum sequence is working as designed, or whether students are taking courses out of the expected order.

### Course pairs

Which courses are commonly taken in sequence (A before B) by students in this cohort? Shows the most frequent ordered pairs, with counts and term-gap distributions.

Use this to identify the de facto prerequisites in your curriculum — courses that students consistently take before others, regardless of what the catalog says.

### Stop-out patterns

What fraction of students stop out after encountering a high-DFW course vs. after passing? This analysis compares next-term return rates for students with different grade outcomes in a specified course.

The gap between "passed and returned" and "DFW'd and returned" is a measure of the course's role in student departure. A large gap suggests the course is a meaningful attrition point. A small gap suggests students who struggle in the course return anyway — the course difficulty isn't the departure driver.

### Bottlenecks

Courses in this cohort's path where waitlist pressure is concentrated. Identifies courses with consistent unmet demand — sections that fill quickly and leave students waiting.

### Major changes

For cohorts where switch-out patterns are relevant: when do students switch out of this program, what programs do they go to, and what courses were they taking at the time of the switch?

---

## Interpretation notes

**Cohort sizes and statistical significance** — many analyses set a minimum cohort size (`min_n`, typically 10) to avoid drawing conclusions from very small groups. If your cohort is small, some analyses will return limited or no results. Consider broadening the program scope or removing campus restrictions.

**Term codes** — CEDAR uses 6-digit term codes (YYYYSS format: 10 = spring, 60 = summer, 80 = fall). The analysis outputs translate these to readable labels (Fall 2025 etc.) for display.

**Re-running after changing the cohort** — changing cohort parameters does not automatically rerun sub-analyses. After rebuilding the cohort, re-run the specific analyses you want updated.

---

## Related analyses

- **Course Dynamics** (under Explore) — for detailed analysis of a specific course independent of a defined cohort
- **Headcount** (under Explore) — for declared program enrollment trends over time
- **Retention** (under Explore) — for institution-wide or program-level retention and graduation rates without cohort-level filtering
