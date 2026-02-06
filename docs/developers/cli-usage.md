---
title: CLI Reference
nav_order: 2
parent: Developer Guide
---

# CEDAR Command Line Reference

CEDAR can be run from the command line using `cedar.R`. This reference documents all available commands and options.

## Basic Usage

```bash
Rscript cedar.R -f <function> [options]
```

## Getting Help

```bash
# Show available functions
Rscript cedar.R -f guide

# Show all options
Rscript cedar.R --help
```

## Available Functions

### Application

| Function | Description |
|----------|-------------|
| `shiny` | Start the Shiny web application |
| `guide` | Display available functions and usage |

### Data Processing

| Function | Description |
|----------|-------------|
| `parse-data` | Parse MyReports Excel files into CEDAR format |
| `transform` | Transform aggregate data to CEDAR model |

### Reports

| Function | Description |
|----------|-------------|
| `dept-report` | Generate department-level report |
| `course-report` | Generate course-level report |

### Analysis

| Function | Description |
|----------|-------------|
| `enrl` | Enrollment analysis |
| `headcount` | Student headcount by program |
| `credit-hours` | Credit hour calculations |
| `sfr` | Student-Faculty Ratio |
| `rollcall` | Student demographics analysis |
| `regstats` | Registration statistics |
| `seatfinder` | Seat availability analysis |
| `waitlist` | Waitlist analysis |

## Common Options

### Filtering Options

| Option | Short | Description | Example |
|--------|-------|-------------|---------|
| `--term` | `-t` | Term code | `--term 202580` |
| `--dept` | `-d` | Department code | `--dept HIST` |
| `--subj` | `-s` | Subject code | `--subj ANTH` |
| `--college` | `-c` | College code | `--college AS` |
| `--campus` | | Campus code | `--campus ABQ` |
| `--level` | `-l` | Course level | `--level upper` |
| `--major` | `-m` | Student major | `--major "History"` |

### Output Options

| Option | Description | Values |
|--------|-------------|--------|
| `--output` | Output format | `csv`, `html`, `shiny` |
| `--arrange` | Sort by column | Column name |

### Report Options

| Option | Description |
|--------|-------------|
| `--group_cols` | Columns to group by |
| `--uel` | Use exclude list |
| `--aop` | AOP handling: `compress` or `exclude` |
| `--crosslist` | Crosslist handling: `compress` or `exclude` |

## Examples

### Generate Department Report

```bash
# HTML report for History department
Rscript cedar.R -f dept-report --dept HIST --output html

# CSV data for Mathematics
Rscript cedar.R -f dept-report --dept MATH --output csv
```

### Enrollment Analysis

```bash
# Enrollment for Fall 2025
Rscript cedar.R -f enrl --term 202580

# Enrollment by department
Rscript cedar.R -f enrl --dept ANTH --term 202580

# Upper-division only
Rscript cedar.R -f enrl --dept HIST --level upper
```

### Student Demographics (Rollcall)

```bash
# Who's taking HIST 1110?
Rscript cedar.R -f rollcall --subj HIST --course 1110

# Demographics by major
Rscript cedar.R -f rollcall --dept MATH --group_cols "major"
```

### Credit Hours

```bash
# Credit hours by department
Rscript cedar.R -f credit-hours --dept HIST

# Credit hours by faculty type
Rscript cedar.R -f credit-hours --dept MATH --group_cols "job_category"
```

### Registration Statistics

```bash
# Registration stats for Fall 2025
Rscript cedar.R -f regstats --term 202580

# By department
Rscript cedar.R -f regstats --dept HIST --term 202580
```

## Term Code Reference

CEDAR uses 6-digit term codes (YYYYTS):

| Term Type | Code Suffix | Example |
|-----------|-------------|---------|
| Spring | 10 | 202510 = Spring 2025 |
| Summer | 60 | 202560 = Summer 2025 |
| Fall | 80 | 202580 = Fall 2025 |

## Course Level Reference

| Level | Description | Course Numbers |
|-------|-------------|----------------|
| `lower` | Lower division | 100-299 |
| `upper` | Upper division | 300-499 |
| `grad` | Graduate | 500+ |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CEDAR_DATA_DIR` | Data directory path | `data/` |
| `CEDAR_STUDENT_SALT` | Student ID encryption salt | (required for encryption) |
| `CEDAR_DFW_PASSWORD` | Password for DFW data access | `cedar-dfw-2025` |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Data file not found |

## See Also

- [Getting Started](../guides/getting-started.md)
- [Function Reference](functions.md)
- [Data Model](data-model.md)
