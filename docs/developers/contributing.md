---
title: Contributing
nav_order: 7
parent: Developer Guide
---

# Contributing to CEDAR

Thanks for your interest in contributing to CEDAR! We welcome contributions of all kinds — code, documentation, bug reports, feature suggestions, and more.

## Ways to Contribute

### Report Bugs

Found something broken? [Open an issue](https://github.com/cedar-collective/cedar/issues) with:

- What you were trying to do
- What you expected to happen
- What actually happened
- Steps to reproduce (if possible)

### Suggest Features

Have an idea for CEDAR? We'd love to hear it. Open an issue describing:

- What problem would this solve?
- How might it work?
- Who would use it?

### Improve Documentation

See something unclear in the docs? PRs are welcome! Documentation lives in the `docs/` folder.

### Fix Bugs

Look for issues labeled `good first issue` or `help wanted`. These are good starting points.

### Add Features

For larger features, please open an issue first to discuss the approach. This helps avoid wasted effort.

## Development Workflow

New to the project? [Your First Change](first-hour.html) is the complete
Docker-based path from a fresh clone to a visible edit and PR, using invented
data and no local R installation.

### 1. Fork and Clone

```bash
# Fork the repo on GitHub, then:
git clone https://github.com/YOUR-USERNAME/cedar.git
cd cedar
```

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/add-waitlist-analysis`
- `fix/enrollment-filter-bug`
- `docs/improve-installation-guide`

### 3. Make Your Changes

Follow the coding conventions below.

### 4. Test Your Changes

```bash
# Run the standard test gate from the repository root
./run-tests.sh

# Or, without local R/Node:
bash scripts/dev.sh test

# Test the Shiny app manually
bash scripts/dev.sh up
# Open localhost:3838; after saving edits, use bash scripts/dev.sh restart
```

### 5. Commit

Write clear commit messages:

```bash
git commit -m "Add waitlist analysis cone

- Implements get_waitlist() function
- Adds waitlist tab to department reports
- Updates documentation"
```

### 6. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

The **PR Checks / Synthetic checks** workflow validates the proposed merge
without production access. It runs the full R suite and opens the synthetic
demo in Chrome. A maintainer may need to approve the first workflow run from a
fork. Check its results before requesting review; synthetic app logs and a
screenshot are attached to the run. See [Testing](testing.html#pull-request-checks-without-institutional-data)
to reproduce it locally. This workflow has no production deployment access.

## Coding Conventions

### R Style

- Use tidyverse style (pipes, dplyr verbs)
- Use `snake_case` for variables and functions
- Keep functions focused (single responsibility)
- Add roxygen2 documentation for exported functions

### File Organization

- **Cones** go in `R/cones/`
- **Generic infrastructure** goes in `R/trunk/`
- **Shared domain computations** go in `R/branches/`
- **Feature orchestration** goes in `R/features/`
- **Shiny wiring** goes in `R/modules/` (no business logic)
- **Data processing** goes in `R/data-parsers/`

### CEDAR Data Model

All code should use CEDAR column names (lowercase, snake_case):

```r
# Good
sections %>% filter(term >= 202080)

# Bad (legacy column names)
sections %>% filter(TERM >= 202080)
```

See the [Data Model](data-model.html) for the full schema.

### Documentation

- Add roxygen2 comments to functions
- Update user docs if you change behavior
- Include examples where helpful

### Testing

- Add tests for new functionality
- Test fixtures are hand-crafted in `tests/testthat/fixtures/designed_test_data.R` (see [Testing](testing.html))
- Run the full test suite before submitting

## Adding a New Cone

A cone is one file in `R/cones/` answering one question. The rules are in
[`AGENTS.md`](https://github.com/cedar-collective/cedar/blob/main/AGENTS.md)
under "Writing a cone"; the pattern is below. Before writing one, check the
[layer inventory](layer-inventory.html): a branch or cone may already answer
the question, and the measure tables already hold most counts.

1. **Start from the measure tables**, not the class list. Every graded
   attempt is classified once in `cedar_attempts`; every course-term count
   (registered, census, first day, seats, sections, DFW) is in
   `cedar_course_terms`; every next-term course pair is in
   `cedar_course_flows`; every student-term's enrollment, return, major and
   running credits are in `cedar_student_terms`. A new cone is a filter and a
   join over them. It reads `cedar_registrations` only for a fact no measure
   holds (a same-term pair, a cohort defined by registration). See the
   [data model](data-model.html#loaded-tables-units-and-course-ids).
2. **Follow the pattern**:
   ```r
   # Which units teach the courses a major's students take?
   #
   # One question, stated plainly at the top of the file, with what the
   # rows mean, which edge bounds them and what is deliberately left out.

   #' @param student_terms `cedar_student_terms`.
   #' @param registrations `cedar_registrations`, keyed on the course.
   #' @param opt `dept_code` (required), `term`, `campus`, `min_n`
   #'   (default 10), `data_edges` (`cedar_data_edges()` output, required).
   #' @return One row per unit, term and campus: `n_students`, `n_registrations`.
   #'   Attribute `edge`: the term the rows stop at.
   get_your_cone <- function(student_terms, registrations, opt = list()) {
     if (is.null(opt$dept_code)) stop("[your-cone.R] opt$dept_code is required.", call. = FALSE)
     min_n <- opt$min_n %||% 10L
     edge  <- cedar_longitudinal_edge(opt$data_edges)
     if (is.null(edge)) stop("[your-cone.R] no settled enrollment edge.", call. = FALSE)

     # filter, join, count: campus beside the course in every group_by()

     cedar_debug("[your-cone.R] ", nrow(result), " rows to ", edge)
     result
   }
   ```
   Tables are parameters, never globals; `opt` is last and resolved with
   `%||%`; a missing column or an impossible empty join stops with an
   error, never a default. Round nothing: display adapters round.
3. **Add a test** in `tests/testthat/` on the committed fixtures
   (`tests/testthat/fixtures/designed_test_data.R`); `setup.R` exposes the
   measure tables (`test_student_terms`, `test_course_flows`,
   `attempts_for()`, `course_terms_for()`). Break the logic once and watch
   the test fail before trusting it.
4. **Wire it in** from a module or a feature; a cone never calls another
   cone, and a page never computes.
5. **Add its row** to the [layer inventory](layer-inventory.html).

## Pull Request Guidelines

### Before Submitting

- [ ] Code follows project conventions
- [ ] Tests pass locally
- [ ] Documentation updated (if needed)
- [ ] Commit messages are clear

### In the PR Description

- Describe what the change does
- Reference any related issues
- Note any breaking changes
- Include screenshots for UI changes

### Review Process

1. A maintainer will review your PR
2. They may ask for changes or clarification
3. Once approved, they'll merge it

Response times vary (we're a small team), but we read everything.

## Questions?

- **General questions**: Open an issue or email fwgibbs@unm.edu
- **Code questions**: Comment on the relevant issue or PR
- **Documentation**: PRs welcome, or open an issue

Thanks for contributing to CEDAR!
