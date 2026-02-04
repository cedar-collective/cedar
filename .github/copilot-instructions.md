# CEDAR - Curricular and Enrollment Data Reporting and Analysis

This is a multi-modal R application for higher education data analysis that runs as CLI, RStudio environment, or Shiny web app.

## Architecture Overview

### Core Structure
- **Shiny app entry points**: `app.R` (simple launcher), `global.R` (environment setup), `server.R` (reactive logic), `ui.R` (interface)
- **Modular components**: `cones/` directory contains feature modules (headcount, enrollment, forecasting, etc.)
- **Shared utilities**: `includes/` directory with configuration, filtering, mappings, and helper functions
- **Data processing**: `data-parsers/` for ETL operations on MyReports Excel files

### Key Patterns

#### Function Loading System
All functionality is loaded via `R/branches/load-funcs.R` which sources modules in dependency order:
```r
source("lists/mappings.R")        # Data mappings
source("cones/enrl/enrl.R")          # Enrollment analysis
source("cones/course-report.R")      # Course reporting
```

#### Environment Detection
Uses environment-aware configuration throughout:
```r
is_docker() <- file.exists("/.dockerenv")
is_posit_connect() <- nzchar(Sys.getenv("CONNECT_SERVER"))
```

#### Data Architecture
- **Raw data**: Excel files from MyReports system → `data-parsers/parse-data.R`
- **Processed data**: `.Rds` files in `data/` directory
- **Output**: Reports in `output/` with subdirectories by type

#### Configuration Patterns
- **Environment-specific configs**: `config/config.R` (local), `config/shiny_config.R` (web app)
- **Template pattern**: `config/config_template.R` → user creates `config/config.R`
- **Runtime variables**: `cedar_base_dir`, `cedar_current_term`, thresholds

### Module Structure ("Cones")

Each cone is a self-contained analytical module:
- `cones/headcount.R` - Student program enrollment counting
- `cones/enrl/` - Enrollment analysis with plotting
- `cones/forecast/` - Predictive modeling
- `cones/course-report.R` - Individual course analysis
- `cones/dept-report.R` - Department-level reporting

#### Cone Function Patterns
Functions typically accept `(students, courses, opt)` parameters where `opt` contains filtering and configuration options.

### Data Processing Conventions

#### Parser Specifications
Data parsers are defined in `report_specs` list with filename signatures:
```r
desr = list(
  data_file = "DESRs",
  filename_sig = "Department_Enrollment_Status",
  parser = "parse-DESR.R"
)
```

#### Filtering System
Centralized filtering in `includes/filter.R` using `opt` parameter pattern:
- `opt$dept` - Department filter
- `opt$term` - Term filter  
- `opt$uel` - Use exclude list (defaults TRUE)
- `opt$status` - Course status filter

#### Report Generation
Uses R Markdown templates in `Rmd/` directory with parameterized reports:
```r
# Reports use params object for configuration
params:
  opt: 1
  course_data: 1
  output_filename: 1
```

### Important Globals

#### Data Objects
- `courses` - Main course/section data (from DESRs)
- `students` - Student enrollment data (from class lists)  
- `academic_studies` - Student program data
- `degrees` - Graduation data
- `forecasts` - Predictive models

#### Key Lists (includes/lists.R)
- `tl_falls`, `tl_springs`, `tl_summers` - Term code lists
- `dl_humanities`, `dl_soc_sci`, `dl_stem` - Department groupings

### Development Workflow

#### Local Development
1. Copy `config/config_template.R` to `config/config.R`
2. Set `cedar_base_dir` to full project path
3. Use `cedar.R` CLI for batch operations
4. Run Shiny app via `app.R`

#### Docker Deployment
- Uses `Dockerfile.shiny` and `docker-compose.yml`
- Environment variables for data source URLs in production
- Volume mounts for persistent data storage

### Debugging & Logging
- Extensive `message()` calls throughout for operation tracking
- Functions log entry/exit and row counts for data operations
- Shiny notifications for user feedback on long operations

### Performance Considerations
- Data is pre-loaded and cached (no real-time DB queries)
- Uses `updateSelectizeInput(..., server = TRUE)` for large choice lists
- AOP (All Online Programs) course compression for enrollment aggregation
- Background data updates via scheduled parsing jobs