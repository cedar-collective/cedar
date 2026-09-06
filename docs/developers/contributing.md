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

Cones are analysis modules. To add one:

1. **Create the file** in `R/cones/your-cone.R`
2. **Follow the pattern**:
   ```r
   #' Your Cone Analysis
   #'
   #' @description What this cone does
   #' @param students CEDAR students data
   #' @param sections CEDAR sections data
   #' @param opt Options list with filters
   #' @return Data frame or list of results
   #' @export
   get_your_cone <- function(students, sections, opt) {
     message("[your-cone.R] Starting analysis...")

     # Your analysis logic here

     message("[your-cone.R] Done. Returning X rows.")
     return(result)
   }
   ```
3. **Wire it in** — call the cone from the relevant Shiny module/server (or a report orchestrator); cones are never called directly from a dispatcher
4. **Add tests** in `tests/testthat/`
5. **Document** in the appropriate guide

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
