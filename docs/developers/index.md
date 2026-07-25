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
git clone https://github.com/cedar-collective/cedar.git
cd cedar

# Install dependencies (in R)
source("setup.R")

# Start the Shiny app
R -e "shiny::runApp(port = 3838)"
```

See [Installation](installation.html) for detailed setup instructions.

### Next Steps

| I want to... | Go to... |
|:-------------|:---------|
| Install and run CEDAR locally | [Installation](installation.html) |
| Understand the data model | [Data Model](data-model.html) |
| Understand subject, program, and dept codes | [Codes and Departments](codes-and-departments.html) |
| Look up function documentation | [Function Reference](functions.html) |
| Contribute code or docs | [Contributing](contributing.html) |

## Project Structure

CEDAR is organized into a few key areas:

```
cedar/
├── R/
│   ├── lists/          # Static constants and lookups (grade codes, status codes, mappings)
│   ├── trunk/          # Core infrastructure (filtering, term math, caching, logging, I/O)
│   ├── branches/       # Reusable domain computations (enrollment, grades, populations)
│   ├── cones/          # Focused analyses — each answers one question
│   ├── reports/        # Orchestrators that assemble cones into rendered reports
│   ├── modules/        # Shiny UI/server pairs for dashboard tabs
│   └── data-parsers/   # Data transformation scripts (raw exports → CEDAR tables)
├── Rmd/                # Report templates
├── config/             # Configuration files
├── data/               # Data files (not in repo)
├── tests/              # Test suite (testthat + e2e browser tests)
├── app.R               # Shiny app entry point
├── ui.R                # Shiny UI
└── server.R            # Shiny server
```

## The "Cones" Concept

CEDAR's architecture is layered like a tree. At the base are the **lists** (static constants — grade codes, status codes, domain lookups) and the **trunk**: core utilities for loading, filtering, and transforming data — the logic that handles crosslisting, deduplication, term comparisons, and the structural details that every analysis needs to get right before the interesting work begins. Above that are the **branches**: domain-specific analytical functions for enrollment calculations, headcount, grade distributions, credit hour production, and other recurring computations that multiple analyses share. **Cones** sit at the top: focused, self-contained modules that answer specific questions by composing trunk and branch functions into a complete analysis. Two more layers turn analyses into things people use: **reports** assemble multiple cones into rendered output (department reports, course reports), and **modules** wire cones into the Shiny dashboard's tabs.

Adding a cone for a new question means defining what you want to find out and assembling pieces that already exist — the underlying infrastructure doesn't change. Specific questions live in cones, reusable logic lives below them, and neither needs to know too much about the other. That separation is what keeps the system extensible, and what makes a cone developed at one institution adaptable at another.

Current cones (in `R/cones/`):

| Cone | What It Does |
|:-----|:-------------|
| `bottleneck.R` | Waitlist pressure and unmet enrollment demand |
| `cancellations.R` | Cancelled course sections |
| `course-demographics.R` | Major and classification breakdown per course |
| `course-impact.R` | Observational comparisons: persistence and downstream grades for students who took a course vs. comparable students who didn't |
| `course-neighbors.R` | What students take before, after, and alongside a course |
| `course-outcomes.R` | Next-term persistence by grade, DFW trends, instructor DFW comparison |
| `course-retention.R` | Descriptive next-term retention rates across courses |
| `forecast/` | Course enrollment forecasting |
| `gen-ed-conversion.R` | Where students who took gen-ed courses ended up (major flows) |
| `gened-fulfillment.R` | Gen-ed area fulfillment by major |
| `health-whatif.R` | Health-program course demand and what-if enrollment projections |
| `major-changes.R` | Major-change detection, timing, and pathways |
| `pathway.R` | When students in a population take each course; course sequences |
| `population-trend.R` | Entry-type distribution over time |
| `seatfinder.R` | Seat availability across terms |
| `sfr.R` | Faculty FTE by department |
| `stopout.R` | Stop-out rates after DFW vs. passing outcomes |
| `waitlist.R` | Waitlist counts by course and major |

The full function-level reference — including the branch and report layers — is in the auto-generated [Function Reference](functions.html); the architecture rules live in `AGENTS.md` at the repository root.

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

- **Report bugs** — Found something broken? [Open an issue](https://github.com/cedar-collective/cedar/issues)
- **Suggest features** — Have an idea? We'd love to hear it
- **Improve docs** — See something unclear? PRs welcome
- **Add tests** — Help us improve coverage
- **Build features** — Check out the [Contributing Guide](contributing.html)

## Getting Help

- **GitHub Issues** — Best for bugs and feature requests
- **Email** — fwgibbs@unm.edu for general questions
- **Code questions** — Feel free to open a discussion on GitHub

We're a small project, so responses may take a few days. But we do read everything!
