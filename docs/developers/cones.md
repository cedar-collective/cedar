---
title: Cones
parent: Developer Guide
nav_order: 1
---

# Cones
{: .fs-9 }

**The unit of shared work in CEDAR**
{: .fs-6 .fw-300 }

---

## The idea

Every institution that runs courses faces the same questions. Which sections are trending toward low enrollment? How do DFW rates vary by instructor type? What do students in a gateway course have in common with those who succeed downstream?

These questions get answered, if they get answered at all, in isolation — a one-off analysis for one department, for one semester, that lives on someone's laptop and disappears when they leave. The next time someone asks, the work starts over.

CEDAR's response to this is the **cone**: a focused, documented, shareable analytical module that answers a specific question from standard institutional data. A cone developed to understand enrollment risk at one institution can be adapted by another. Solutions accumulate. The work doesn't start over.

---

## What a cone does

A cone is an R function in `R/cones/` that answers **one** analytical question:

1. **Accepts** the CEDAR tables it needs as parameters, never reading them from global state. Most questions are a filter and a join over the measure tables (`cedar_attempts`, `cedar_course_terms`, `cedar_course_flows`, `cedar_student_terms`), which already hold every classified attempt, every course-term count, every next-term pair and every student-term; the class list (`cedar_registrations`) and the schedule (`cedar_sections`) are for the facts no measure holds;
2. **Takes its choices** in an options list, `opt = list()`, always the last argument (term, department, campus, thresholds);
3. **Returns** a tibble or a named list with a documented output contract.

```r
get_low_enrollment_sections <- function(sections, opt = list()) {
  if (is.null(opt$term)) stop("opt$term is required")
  threshold <- opt$threshold %||% 10L

  sections %>%
    filter(term == opt$term, status == "A") %>%
    filter(enrolled < threshold) %>%
    arrange(campus, enrolled) %>%
    select(campus, crn, subject_course, enrolled, total_enrl)
}
```

It stops loudly on missing input rather than guessing, groups any course result by campus, and reuses the shared helpers for every count (census enrollment, DFW, term math) instead of re-deriving them. **A cone never calls another cone**: assembling several analyses into a page is a feature's job (`R/features/`). The full rules are in [`AGENTS.md`](https://github.com/cedar-collective/cedar/blob/main/AGENTS.md) under "Writing a cone", and [layer-inventory.md](layer-inventory) lists the cones, branches and helpers that already exist, so check there first.

---

## Writing a cone

The fastest path is often an AI assistant given the repository: it reads `AGENTS.md` and the existing cones. Describe the question plainly:

> *I want to understand what students who succeed in the second course of a two-course sequence have in common with those who don't. Write a CEDAR cone that finds students who took course A before course B, groups them by their grade in A, and compares their outcomes in B.*

Then verify the draft as you would anyone's:

- Column names match the CEDAR schema ([data-model.md](data-model)), and counts come off the measure tables rather than being re-derived from the class list.
- Course results are grouped by campus, and grade outcomes are read from `cedar_attempts`, never reclassified.
- A follow-up analysis stops at the right data edge ([right-edge-policy.md](right-edge-policy)) and says which edge it used.
- It has a test on the committed fixtures that fails when the logic is broken ([testing.md](testing)).
- It is listed in `R/trunk/load-funcs.R` (cones are sourced from a list, not a glob) and in the [layer inventory](layer-inventory).

`R/cones/major-course-units.R` (which units teach the courses a major's students take) is the smallest complete example: two tables in, one join, one count, a test on three fixtures.

---

## Contributing a cone

A cone that answers a question well — documented, tested, working on real data — belongs in the CEDAR collective, not just on your institution's server.

To contribute:

1. **Write and test your cone** against the committed fixtures and your institution's CEDAR data
2. **Generalize it** — institution-specific values belong in the `institution/<id>/` files or in `opt`, never in the code
3. **Document the question it answers** — one clear sentence at the top of the file
4. **Open a pull request** on [GitHub](https://github.com/cedar-collective/cedar) with a description of the question, the approach, and example output

You don't need to know whether other institutions have the same question. They do. That's the premise.

[Contributing guide →](contributing) \| [Layer inventory →](layer-inventory)
