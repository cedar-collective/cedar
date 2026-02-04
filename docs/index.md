---
title: Home
layout: home
nav_order: 1
---

# CEDAR
### Curriculum + Enrollment Data Analysis & Reporting

## What is CEDAR?

CEDAR is a suite of R tools for analyzing enrollment data in higher education. It provides:

- **Interactive web interface** for exploring enrollment data
- **Command-line tools** for automated reporting
- **Flexible data model** that works with various data sources
- **Department and course reports** with visualizations

CEDAR uses a normalized data model designed to be institution-agnostic, making it adaptable to different student information systems.

## Quick Start

### Web Interface (Recommended)

```bash
Rscript cedar.R -f shiny
```

Then open your browser to `http://localhost:3838`

### Command Line

```bash
# See available commands
Rscript cedar.R -f guide

# Generate a department report
Rscript cedar.R -f dept-report --dept HIST
```

## Documentation

### Guides
- [Getting Started](guides/getting-started.md) - Installation and first steps
- [Web Interface Guide](web-guide.md) - Using the Shiny application
- [Enrollment Analysis](enrollment.md) - Understanding enrollment data
- [Registration Stats](regstats.md) - Registration statistics

### Reference
- [CLI Reference](reference/cli-usage.md) - Command line options
- [Data Model](reference/data-model.md) - CEDAR schema specification
- [Function Reference](reference/functions.md) - API documentation

### For Developers
- [Cone Standards](developers/cone-standards.md) - Development guidelines
- [Test Infrastructure](developers/TEST-FIXTURES-REAL-DATA.md) - Testing documentation

## Data Sources

CEDAR is designed to work with enrollment data from various sources. The current implementation supports:

- MyReports (Banner-based systems)
- Custom data transformations

See the [Data Model](reference/data-model.md) for how to adapt your data.

## Term Codes

CEDAR uses 6-digit term codes (YYYYTS):

| Code | Term |
|------|------|
| 202510 | Spring 2025 |
| 202560 | Summer 2025 |
| 202580 | Fall 2025 |

## Data Note

Data in CEDAR comes from operational systems (like MyReports) and is updated nightly. This is distinct from official institutional data, which is frozen at census dates for required reporting purposes.

## Contributing

The code is available on [GitHub](https://github.com/fredgibbs/cedar). Contributions are welcome!

## Questions & Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/fredgibbs/cedar/issues)
- **Email**: fwgibbs@unm.edu
