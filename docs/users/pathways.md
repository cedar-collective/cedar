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

The Major Changes subtab has two related but distinct views:

- **Major-change events** compare one observed primary-major record to the next. A change is counted when the student's primary `cedar_programs$program_name` differs from the previous primary-major record, excluding undergraduate-to-graduate level transitions. Moving from a pre-major to the full major in the same program is not counted as a major change.
- **Major-status movement cards** summarize when students first appear as selected-unit pre-majors, first appear directly as selected-unit full majors, convert from selected-unit pre-major to full major, or leave the selected unit for another major.

### Major Changes source fields

The tab uses normalized CEDAR tables, but the underlying fields come from Banner/MyReports exports:

| CEDAR field | Source field | How it is used |
|-------------|--------------|----------------|
| `cedar_students$term` | Class Lists `Academic Period Code` | First observed class-list enrollment term. This is not a formal Banner matriculation/start term. |
| `cedar_student_term_credits` | Derived from Class Lists / `cedar_students` | Observed UNM attempted and completed credits by student-term. Used for movement-card UNM credit timing. |
| `cedar_programs$term` | Academic Studies `Academic Period` | Program-record term, converted to a CEDAR term code. |
| `cedar_programs$program_name` | Academic Studies program columns such as `Major`, `Second Major` | Detects program changes and selected-unit records. |
| `cedar_programs$program_type` | Derived while expanding Academic Studies program columns | Limits most logic to `Major` and `Second Major`; primary change detection uses `Major`. |
| `cedar_programs$is_pre_major` | CEDAR-computed from program naming/code patterns | Separates pre-major status from full-major status. |
| `cedar_programs$student_population` | Academic Studies `Student Population` | Labels Native UNM vs Transfer. |
| `cedar_programs$inst_credits_attempted` | Academic Studies `Institution Credits Attempted` | Banner cumulative UNM-only attempted credits. Kept as source context, but not used for movement-card UNM credit medians. |
| `cedar_programs$overall_credits_attempted` | Academic Studies `Overall Credits Attempted` | Transfer-inclusive attempted-credit context. |

### Timing and credit interpretation

`Median terms` uses CEDAR's `term_diff()` helper. It counts regular Spring/Fall steps only: Spring to Fall is 1, Fall to next Spring is 1, and summer is not counted as an extra term.

The starting point depends on the event:

- Entry cards count from the student's first observed class-list enrollment term.
- Pre-major to full-major cards count from first selected-unit pre-major record to first selected-unit full-major record.
- Departure cards count from first selected-unit record to the first observed departure for another major.

Because first observed class-list enrollment is not a formal Banner start date, the headline entry cards exclude students already present at the data-start term and students whose first selected-unit program record already has substantial class-list-derived attempted UNM credits. Those records remain in the movement detail table as uncertain/left-censored records, but they are not summarized as new declarations.

Headline movement-card credits are observed completed UNM credits from Class Lists. Completed credits use the standard credit-earning grade set, so W/F/non-credit outcomes do not increase the completed-credit total. The movement detail table also shows observed attempted UNM credits and transfer-inclusive attempted credits from Academic Studies. Departure credit figures are lag-adjusted to the term before the change posted to Banner because program changes often appear in Banner one term after the student's actual decision.

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
