---
title: Cohort Analysis
nav_order: 6
parent: User Guide
---

# Cohort Analysis
{: .fs-9 }

**Answering questions about specific student populations**
{: .fs-6 .fw-300 }

---

CEDAR's cohort tools let you scope any analysis to a defined population of students — for example, students pursuing health professions — and compare what you find against the full student body. This page walks through the two most useful admin questions and how to answer them directly in RStudio.

No Shiny required. Load the data, build a cohort, run the analysis.

---

## Setup

```r
library(qs)
library(dplyr)

cedar_programs <- qread("data/cedar_programs.qs")
cedar_students <- qread("data/cedar_students.qs")

source("R/cones/cohort.R")
source("R/cones/bottleneck.R")
source("R/cones/stopout.R")
source("R/branches/utils.R")
```

---

## What is a cohort?

A cohort is a set of student IDs with a label. You build one from `cedar_programs` — the table that records which major each student is declared in — using `build_cohort()`.

```r
cohort <- build_cohort(cedar_programs, opt = list(type = "health"))
head(cohort)
#> # A tibble: 6 × 2
#>   student_id cohort_label
#>   <chr>      <chr>
#> 1 ABC123     health_major
#> 2 DEF456     health_major
#> ...
```

The default health track covers nursing, pharmacy, public health, allied health, and related professional programs. See `DEFAULT_HEALTH_PROGRAMS` in `R/cones/cohort.R` for the full list, and override it with `opt$health_programs` if you need a different scope.

### Pre-majors vs. declared majors

Many students are working toward a health profession before they're formally admitted to a professional program — they're declared in Biology or Biochemistry, not Nursing yet. The `include_pre_majors` option controls whether to include them:

| Value | Behavior |
|---|---|
| `"exclude"` (default) | Only students formally admitted to a health professional program |
| `"lump"` | Core health + pre-major feeder students, treated as one group |
| `"split"` | Both groups included, labeled separately for side-by-side comparison |

```r
# Include pre-majors in the same cohort
cohort_lumped <- build_cohort(cedar_programs,
                              opt = list(type = "health",
                                         include_pre_majors = "lump"))

# Or separate them for comparison
cohort_split <- build_cohort(cedar_programs,
                             opt = list(type = "health",
                                        include_pre_majors = "split"))
table(cohort_split$cohort_label)
```

The pre-major feeder programs default is defined in `DEFAULT_HEALTH_PRE_MAJOR_PROGRAMS` in `cohort.R`. Override with `opt$pre_major_programs`.

---

## Question 1: Where are pre-health students not getting into courses?

This is an **access bottleneck** — courses where students want seats and can't get them. CEDAR measures this by looking at students who are on the waitlist but hold no registered seat in that course (hedged waitlisters, who are already registered in another section, are excluded from the count).

```r
cohort <- build_cohort(cedar_programs, opt = list(type = "health"))
result <- get_bottlenecks(cohort, cedar_students, opt = list())

# Courses with the most unmet demand from health track students
result$waitlist
```

The result is sorted by `n_waitlisted` descending. A course near the top is one where multiple health track students couldn't get a seat.

### What this tells you — and what it doesn't

Waitlist counts in CEDAR reflect *end-of-term* data from the DESR. Students who wanted a course, couldn't get in, and stopped trying don't appear in the waitlist — they simply don't appear. So this analysis likely **understates** the true access problem. High waitlist counts are a signal worth acting on; low counts don't necessarily mean demand is met.

### Comparing pre-majors vs. declared majors

```r
cohort_split <- build_cohort(cedar_programs,
                             opt = list(type = "health",
                                        include_pre_majors = "split"))
result_split <- get_bottlenecks(cohort_split, cedar_students, opt = list())

# Side-by-side view
result_split$by_label
```

If pre-major students are concentrated on different courses than declared majors, that tells you something about where in the pipeline the bottleneck sits — before admission to the professional program, or within it.

### Restricting to a specific term

```r
result <- get_bottlenecks(cohort, cedar_students, opt = list(term = 202510))
```

---

## Question 2: Where are pre-health students stopping out?

This is an **offramp** — a course where students who fail or withdraw disproportionately disappear from the enrollment record entirely the following term. The question isn't just "what courses have high DFW rates?" It's "which courses cause students to leave the pipeline?"

`get_stopout()` answers this by comparing two things within each course:

- **Stop-out rate after DFW**: what fraction of cohort students who got a D/F/W grade did not enroll the following term?
- **Stop-out rate after passing**: what fraction of cohort students who passed did not enroll the following term?

The gap between those two rates is the key signal. A large gap means failing that course predicts leaving — not just academically struggling. The analysis runs the same comparison for **all other students** in the same courses (the baseline), so you can see whether the pattern is specific to health track students or common to everyone.

```r
cohort <- build_cohort(cedar_programs, opt = list(type = "health"))
result <- get_stopout(cedar_students, cohort, opt = list())

# All courses, sorted by cohort DFW stop-out rate
result$by_course

# Focus on courses where the gap is large AND statistically significant
result$by_course %>%
  filter(cohort_p_value < 0.05) %>%
  arrange(desc(cohort_stopout_gap))
```

### Reading the output

| Column | What it means |
|---|---|
| `cohort_n_dfw` | Number of cohort students with a DFW grade in this course |
| `cohort_dfw_stopout_rate` | Fraction of those who didn't return the next term |
| `cohort_pass_stopout_rate` | Same for cohort students who passed |
| `cohort_stopout_gap` | DFW rate minus pass rate — the penalty for failing, for this cohort |
| `cohort_p_value` | Chi-squared p-value: is the gap statistically distinguishable from chance? |
| `baseline_*` | Same metrics for all non-cohort students in the same course |

A course worth flagging has:
- High `cohort_stopout_gap` — failing predicts leaving for health track students
- Low `cohort_p_value` — the pattern isn't noise
- `cohort_stopout_gap` noticeably higher than `baseline_stopout_gap` — health track students are more vulnerable than other students in the same course

### Comparing pre-majors and declared majors

```r
cohort_split <- build_cohort(cedar_programs,
                             opt = list(type = "health",
                                        include_pre_majors = "split"))

# Run once for each group
for (label in unique(cohort_split$cohort_label)) {
  sub_cohort <- cohort_split %>% filter(cohort_label == label)
  cat("\n---", label, "---\n")
  result <- get_stopout(cedar_students, sub_cohort, opt = list())
  print(head(result$by_course %>% arrange(desc(cohort_stopout_gap)), 5))
}
```

### A note on "the following term"

Stop-out is measured as: did this student appear in any course the next fall or spring? Summer terms are not counted as a "return" — a student who skips summer is not a stop-out. This is intentional; summer non-enrollment is normal and noisy.

---

## What about course requirements?

Identifying which courses health track students *need* — not just which ones they take — requires encoding degree program requirements, which CEDAR does not yet have. That work is in progress.

In the meantime, the enrollment pattern itself is informative. Courses that appear frequently in the schedules of health track students, particularly in early terms, are de facto part of the pathway even if not formally encoded. The bottleneck and offramp analyses will surface them if they're causing problems.

---

## Customizing the cohort

The default program lists are starting points, not authoritative definitions. Override either list if your institution has different programs or you want a narrower scope:

```r
cohort <- build_cohort(cedar_programs,
  opt = list(
    type = "health",
    health_programs = c("Nursing", "Public Health", "Physical Therapy"),
    pre_major_programs = c("Biology", "Biochemistry"),
    include_pre_majors = "split"
  )
)
```

You can also inspect the cohort before running any analysis — it's just a data frame:

```r
# How many students per label?
table(cohort$cohort_label)

# Which programs are represented? (requires joining back to cedar_programs)
cohort %>%
  left_join(cedar_programs %>% select(student_id, program_name, program_type) %>% distinct(),
            by = "student_id") %>%
  count(cohort_label, program_name, sort = TRUE)
```
