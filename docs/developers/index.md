---
title: Developer Guide
nav_order: 7
has_children: true
---

# Developer Guide

Welcome! If you're here, you're interested in running CEDAR locally, extending it, or contributing to the project. We're glad you're interested.

## Who This Is For

This guide is for:

- **Institutional researchers** who want more control than the web dashboard provides
- **R users** who want to build custom analyses on enrollment data
- **Developers** who want to contribute to CEDAR
- **Curious folks** who want to understand how CEDAR works

## What You'll Need

- **Basic R knowledge** — You should be comfortable with R basics (variables, functions, data frames)
- **R and RStudio** — Or another R development environment
- **Git** — For cloning the repository and contributing

Don't worry if you're still learning — the best way to learn is by doing. And we're happy to help if you get stuck.

## Getting Started

### Quick Start

```bash
# Clone the repository
git clone https://github.com/fredgibbs/cedar.git
cd cedar

# Install dependencies (in R)
source("setup.R")

# Start the Shiny app
Rscript cedar.R -f shiny
```

See [Installation](installation.html) for detailed setup instructions.

### Next Steps

| I want to... | Go to... |
|:-------------|:---------|
| Install and run CEDAR locally | [Installation](installation.html) |
| Use the command line tools | [CLI Usage](cli-usage.html) |
| Understand the data model | [Data Model](data-model.html) |
| Understand subject, program, and dept codes | [Codes and Departments](codes-and-departments.html) |
| Look up function documentation | [Function Reference](functions.html) |
| Contribute code or docs | [Contributing](contributing.html) |

## Project Structure

CEDAR is organized into a few key areas:

```
cedar/
├── R/
│   ├── cones/          # Analysis modules (enrollment, headcount, etc.)
│   ├── branches/       # Shared utilities (filtering, loading, etc.)
│   └── data-parsers/   # Data transformation scripts
├── Rmd/                # Report templates
├── config/             # Configuration files
├── data/               # Data files (not in repo)
├── tests/              # Test suite
├── ui.R                # Shiny UI
├── server.R            # Shiny server
└── cedar.R             # CLI entry point
```

## The "Cones" Concept

CEDAR's architecture has three layers. At the base is the **trunk**: core utilities for loading, filtering, and transforming data — the logic that handles crosslisting, deduplication, term comparisons, and the structural details that every analysis needs to get right before the interesting work begins. Above that are the **branches**: domain-specific analytical functions for enrollment calculations, headcount, grade distributions, credit hour production, and other recurring computations that multiple analyses share. **Cones** sit at the top: focused, self-contained modules that answer specific questions by composing trunk and branch functions into a complete analysis.

Adding a cone for a new question means defining what you want to find out and assembling pieces that already exist — the underlying infrastructure doesn't change. Specific questions live in cones, reusable logic lives below them, and neither needs to know too much about the other. That separation is what keeps the system extensible, and what makes a cone developed at one institution adaptable at another.

Current cones:

| Cone | What It Does |
|:-----|:-------------|
| `enrl.R` | Enrollment analysis |
| `headcount.R` | Student counts by program |
| `credit-hours.R` | Credit hour calculations |
| `sfr.R` | Student-faculty ratio |
| `rollcall.R` | Student demographics |
| `degrees.R` | Graduation data |
| `dept-report.R` | Department reports |
| `course-report.R` | Course reports |

## CEDAR Data Model

CEDAR uses a normalized data model with five main tables:

| Table | Contents |
|:------|:---------|
| `cedar_sections` | Course offerings |
| `cedar_students` | Student enrollments |
| `cedar_programs` | Student majors/minors |
| `cedar_degrees` | Degrees awarded |
| `cedar_faculty` | Faculty information |

This model is institution-agnostic. See [Data Model](data-model.html) for the full schema.

## Ways to Contribute

We welcome contributions of all sizes:

- **Report bugs** — Found something broken? [Open an issue](https://github.com/fredgibbs/cedar/issues)
- **Suggest features** — Have an idea? We'd love to hear it
- **Improve docs** — See something unclear? PRs welcome
- **Add tests** — Help us improve coverage
- **Build features** — Check out the [Contributing Guide](contributing.html)

## Getting Help

- **GitHub Issues** — Best for bugs and feature requests
- **Email** — fwgibbs@unm.edu for general questions
- **Code questions** — Feel free to open a discussion on GitHub

We're a small project, so responses may take a few days. But we do read everything!
