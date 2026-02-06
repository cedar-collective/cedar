---
title: Installation
parent: Developer Guide
nav_order: 1
---

# Installation

This guide walks you through setting up CEDAR for local development.

## Prerequisites

### Required

- **R** (version 4.0 or higher)
- **Git** (for cloning the repository)

### Recommended

- **RStudio** (makes development easier)
- **renv** (for dependency management — CEDAR uses this)

## Step 1: Clone the Repository

```bash
git clone https://github.com/fredgibbs/cedar.git
cd cedar
```

## Step 2: Install R Dependencies

CEDAR uses `renv` for dependency management. When you first open the project, renv should activate automatically.

```r
# In R or RStudio, from the cedar directory:

# If renv doesn't activate automatically:
renv::activate()

# Install all dependencies from the lockfile:
renv::restore()
```

If you prefer not to use renv, you can install packages manually:

```r
# Core packages
install.packages(c(
  "tidyverse",
  "shiny",
  "shinydashboard",
  "bslib",
  "qs",
  "plotly",
  "DT",
  "digest",
  "optparse"
))
```

## Step 3: Configure Data Location

Create a configuration file to tell CEDAR where your data lives:

```r
# config/config.R

# Path to your data directory
cedar_data_dir <- "/path/to/your/data/"

# Optional: Path to small test data
cedar_small_data_dir <- "/path/to/small/data/"

# Use small data for faster development (TRUE/FALSE)
cedar_use_small_data <- FALSE
```

## Step 4: Get Sample Data

CEDAR needs data files to run. You have two options:

### Option A: Use Test Fixtures (For Development)

Generate small test datasets:

```bash
Rscript tests/testthat/create-test-fixtures.R
```

Then point your config to the fixtures directory.

### Option B: Transform Real Data

If you have institutional data in the expected format:

```bash
# Parse source files (Excel → intermediate format)
Rscript cedar.R -f parse-data

# Transform to CEDAR model
Rscript R/data-parsers/transform-to-cedar.R
```

## Step 5: Verify Installation

### Test the CLI

```bash
# Should show available commands
Rscript cedar.R -f guide
```

### Test the Shiny App

```bash
# Start the web interface
Rscript cedar.R -f shiny
```

Then open `http://localhost:3838` in your browser.

### Run Tests

```bash
# Run the test suite
cd tests && ./run-tests.sh
```

## Common Issues

### "Package not found" errors

```r
# Install missing packages
renv::restore()

# Or manually:
install.packages("package_name")
```

### "Data file not found" errors

Check that:
1. Your `cedar_data_dir` path is correct in config/config.R
2. The data files exist in that directory
3. Files have the expected names (cedar_sections.qs, cedar_students.qs, etc.)

### renv issues

If renv causes problems:

```r
# Deactivate renv
renv::deactivate()

# Then install packages manually
```

### Port already in use

If the Shiny app can't start because port 3838 is busy:

```r
# Specify a different port
shiny::runApp(port = 3839)
```

## Environment Variables

CEDAR uses a few environment variables for sensitive settings:

| Variable | Purpose | Required? |
|:---------|:--------|:----------|
| `CEDAR_DATA_DIR` | Data file location | No (can use config.R) |
| `CEDAR_STUDENT_SALT` | Salt for encrypting student IDs | Yes (for production) |
| `CEDAR_DFW_PASSWORD` | Password for DFW data access | No (has default) |

Set these in your `.Renviron` file or shell profile:

```bash
# In ~/.Renviron or ~/.bashrc
export CEDAR_STUDENT_SALT="your-secret-salt-here"
```

## Next Steps

- [CLI Usage](cli-usage.html) — Learn the command line tools
- [Data Model](data-model.html) — Understand the data structure
- [Contributing](contributing.html) — Start contributing
