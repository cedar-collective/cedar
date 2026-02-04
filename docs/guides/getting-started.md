---
title: Getting Started
nav_order: 1
parent: Guides
---

# Getting Started with CEDAR

CEDAR (Curriculum + Enrollment Data Analysis & Reporting) is a suite of R tools for analyzing enrollment data in higher education. This guide will help you get started quickly.

## Prerequisites

- **R** (version 4.0 or higher)
- **RStudio** (recommended but not required)
- **Required R packages**: tidyverse, shiny, qs, plotly

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/fredgibbs/cedar.git
cd cedar
```

### 2. Install Dependencies

Open R or RStudio and run:

```r
# Install pacman if you don't have it
if (!require("pacman")) install.packages("pacman")

# Install all dependencies
pacman::p_load(
  tidyverse,    # Data manipulation
  shiny,        # Web application
  qs,           # Fast data serialization
  plotly,       # Interactive plots
  DT,           # Data tables
  digest,       # Hashing
  optparse      # Command line parsing
)
```

### 3. Configure Data Location

Create or edit `config/config.R`:

```r
# Path to your data directory
cedar_data_dir <- "/path/to/your/data/"

# Optional: Student ID encryption salt
Sys.setenv(CEDAR_STUDENT_SALT = "your-secret-salt")
```

## Quick Start: Web Interface

The easiest way to use CEDAR is through the Shiny web interface:

```bash
Rscript cedar.R -f shiny
```

Or from within R:

```r
source("cedar.R")
shiny::runApp()
```

Then open your browser to `http://localhost:3838`

## Quick Start: Command Line

Generate a department report from the command line:

```bash
# See available commands
Rscript cedar.R -f guide

# Generate a department report
Rscript cedar.R -f dept-report --dept HIST

# Generate enrollment summary
Rscript cedar.R -f enrl --dept MATH --term 202580
```

## Understanding Term Codes

CEDAR uses 6-digit term codes in YYYYTS format:

| Code | Meaning | Example |
|------|---------|---------|
| YYYY | Year | 2025 |
| T | Term type | 1=Spring, 6=Summer, 8=Fall |
| S | Session | 0=Full term |

**Examples:**
- `202510` = Spring 2025
- `202560` = Summer 2025
- `202580` = Fall 2025

## Data Model Overview

CEDAR uses five normalized tables:

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `cedar_sections` | Course offerings | term, crn, subject_course, enrolled |
| `cedar_students` | Student enrollments | student_id, term, grade, major |
| `cedar_programs` | Student programs | student_id, program_type, program_name |
| `cedar_degrees` | Degrees awarded | student_id, degree, term |
| `cedar_faculty` | Faculty info | instructor_id, department, job_category |

See [Data Model Reference](../reference/data-model.md) for complete schema.

## Common Tasks

### View Enrollment Trends

1. Open the web interface
2. Go to **Enrollment** tab
3. Select department and term range
4. Click **Refresh Data**

### Generate Department Report

```bash
# Command line
Rscript cedar.R -f dept-report --dept HIST --output html

# Or use the web interface:
# Reports > Department Reports > Select Department > Generate
```

### Analyze Student Demographics

```r
# In R
source("config/config.R")
source("R/cones/rollcall.R")

# Get demographics for a course
opt <- list(course = "HIST 1110", term = 202580)
result <- rollcall(cedar_students, opt)
```

## Next Steps

- [Web Interface Guide](web-guide.md) - Detailed guide to the Shiny app
- [CLI Reference](../reference/cli-usage.md) - All command line options
- [Function Reference](../reference/functions.md) - API documentation
- [Data Model](../reference/data-model.md) - Complete schema reference

## Getting Help

- **GitHub Issues**: [Report bugs or request features](https://github.com/fredgibbs/cedar/issues)
- **Email**: fwgibbs@unm.edu
