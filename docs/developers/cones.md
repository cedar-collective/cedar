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

A cone is an R function (or small set of functions) that:

1. **Accepts** CEDAR-formatted data — `cedar_students`, `cedar_sections`, and related tables
2. **Filters and groups** that data according to an options list (term, department, course, etc.)
3. **Analyzes** it to answer a specific question
4. **Returns** a structured result — a data frame, a summary, or a list combining both

Every cone follows the same signature:

```r
cone_function <- function(students, courses, opt, additional_data = NULL) {
  # students      = cedar_students (one row per student per section)
  # courses       = cedar_sections (one row per section per term)
  # opt           = named list: term, dept, course, and other filters
  # additional_data = optional: degrees, programs, faculty, etc.
}
```

And returns the same basic structure:

```r
return(list(
  data     = result_data_frame,
  summary  = summary_stats,       # optional
  metadata = list(
    function_name = "my_cone",
    options_used  = opt,
    row_count     = nrow(result_data_frame)
  )
))
```

This consistency is what makes cones composable. A department report cone can call an enrollment cone, a DFW cone, and a headcount cone, assemble their results, and return the whole picture.

---

## A real example

Here's a simplified version of the low enrollment cone — it identifies sections below a threshold before the drop deadline:

```r
flag_low_enrollment <- function(courses, opt = list()) {

  # Resolve options — %||% is defined in trunk/utils.R
  if (is.null(opt$term)) stop("opt$term is required")
  threshold <- opt$threshold %||% 10L
  status    <- opt$status    %||% "A"

  sections <- courses %>%
    filter(
      term   == opt$term,
      status == status
    )

  if (!is.null(opt$dept_code)) {
    sections <- sections %>% filter(department == opt$dept_code)
  }

  result <- sections %>%
    filter(enrolled < threshold) %>%
    arrange(enrolled) %>%
    select(crn, subject_course, enrolled, total_enrl,
           instructor_name, term_type, delivery_method)

  return(list(
    data = result,
    metadata = list(
      function_name = "flag_low_enrollment",
      options_used  = opt,
      row_count     = nrow(result)
    )
  ))
}
```

The cone is short, readable, and does one thing. The question it answers — *which sections are at risk this term?* — is one that every scheduling coordinator at every institution faces. Written once in this form, it can be adapted anywhere.

---

## Writing a cone

### With an AI assistant

The fastest path to a working cone is to describe your question to an AI assistant with enough context about the CEDAR data model for it to write correct, idiomatic code.

CEDAR provides a compact reference document for exactly this purpose:

**[CEDAR AI Reference →](../ai-reference)** — paste this into your AI prompt along with your question.

A prompt that works:

> *I want to understand what students who succeed in the second course of a two-course sequence have in common compared to those who don't. [paste the CEDAR AI reference here]. Write a CEDAR cone that joins cedar_students across two terms, identifies students who took course A before course B, groups them by grade in A, and compares their outcomes in B.*

The AI will produce a draft. Verify that:
- Column names match the CEDAR schema exactly
- Joins use the correct keys (`section_id`, `student_id`)
- The `opt` pattern is followed
- The return structure matches the standard

### From scratch

If you prefer to write directly, the [cone standards documentation](cone-standards) has the full specification: function signatures, options handling, error patterns, and testing conventions.

---

## Contributing a cone

A cone that answers a question well — documented, tested, working on real data — belongs in the CEDAR collective, not just on your institution's server.

To contribute:

1. **Write and test your cone** locally against your institution's CEDAR data
2. **Generalize it** — replace any institution-specific hardcoding with `opt` parameters
3. **Document the question it answers** — one clear sentence at the top of the file
4. **Open a pull request** on [GitHub](https://github.com/cedar-collective/cedar) with a description of the question, the approach, and example output

You don't need to know whether other institutions have the same question. They do. That's the premise.

[Cone standards →](cone-standards) \| [Contributing guide →](contributing) \| [CEDAR AI reference →](../ai-reference)
