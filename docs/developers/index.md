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
- **Docker with Compose** — Runs R and the app for the first-hour tutorial
- **An editor and browser** — VS Code, RStudio's editor, or another editor
- **Git** — For cloning the repository and contributing

A local R installation is optional for the Docker workflow. Native R analysis
is a separate advanced setup described in [Installation](installation.html).

Don't worry if you're still learning — the best way to learn is by doing. And we're happy to help if you get stuck.

## Getting Started

### Quick Start

For a Docker instance with synthetic data, start with
[Your First Change](first-hour.html). It covers editing in any editor, reloading,
testing in Docker, and opening a PR without institutional data or local R.

```bash
# Clone the repository
git clone https://github.com/cedar-collective/cedar.git
cd cedar

# Build and start the synthetic development instance
bash scripts/dev.sh up
```

See [Installation](installation.html) for detailed setup instructions.

### Next Steps

| I want to... | Go to... |
|:-------------|:---------|
| Install and run CEDAR locally | [Installation](installation.html) |
| Map institutional data into CEDAR | [Data Integration Guide](data-integration-guide.html) |
| Know exactly which source field fills which CEDAR column | [Source → CEDAR Field Manifest](source-to-cedar-manifest.html) |
| Understand the data model | [Data Model](data-model.html) |
| Understand subject, program, and dept codes | [Codes and Departments](codes-and-departments.html) |
| Check whether the mappings and join keys hold | [Mapping Audit (2026-07)](mapping-audit-2026-07.html) |
| Review campus grouping decisions and exceptions | [Campus-Grain Audit (2026-08)](campus-grain-audit-2026-08.html) |
| Understand projection methods, aftcasts, and demand censoring | [Enrollment Projection Architecture](enrollment-projections.html) |
| Review forecasting findings, failed assumptions, and next model ideas | [Enrollment Forecasting Lessons](forecasting-lessons.html) |
| Understand where the data model is heading | [ADR-001: Domain Data Model](adr-001-domain-data-model.html) |
| Look up function documentation | [Function Reference](functions.html) |
| Contribute code or docs | [Contributing](contributing.html) |
| Prepare a release or production deploy | [Release Runbook](release-runbook.html) |
| Diagnose slow reports, memory growth, or load contention | [Performance Monitoring](performance-monitoring.html) |
| Configure the restart notice during deploys | [Deployment Maintenance Page](deployment-maintenance.html) |

## Project Structure

CEDAR is organized into a few key areas:

```
cedar/
├── R/
│   ├── lists/          # Static constants and lookups (grade codes, status codes, mappings)
│   ├── trunk/          # Core infrastructure (filtering, term math, caching, logging, I/O)
│   ├── branches/       # Reusable domain computations (enrollment, grades, populations)
│   ├── cones/          # Focused analyses — each answers one question
│   ├── features/       # App-facing orchestration and payload builders
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

CEDAR's architecture is layered like a tree. At the base are the **lists** (static constants — grade codes, status codes, domain lookups) and the **trunk**: core utilities for loading, filtering, and transforming data — the logic that handles crosslisting, deduplication, term comparisons, and the structural details that every analysis needs to get right before the interesting work begins. Above that are the **branches**: domain-specific analytical functions for enrollment calculations, headcount, grade distributions, credit hour production, and other recurring computations that multiple analyses share. **Cones** sit at the top: focused, self-contained modules that answer specific questions by composing trunk and branch functions into a complete analysis. Two more layers turn analyses into things people use: **features** assemble multiple cones/branches into app-facing payloads, and **modules** wire those payloads into the Shiny dashboard's tabs.

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
| `gen-ed-conversion.R` | Where students who took gen-ed courses ended up (major flows) |
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

This model is institution-agnostic after local source data has been normalized
into the CEDAR contract. The integration work is mapping local SIS/reporting
exports, codes, calendars, and privacy rules into these tables. See the
[Data Integration Guide](data-integration-guide.html) for the implementation
workflow and [Data Model](data-model.html) for the full schema.

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
