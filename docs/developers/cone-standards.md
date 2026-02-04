---
title: Cone Standards
nav_order: 1
parent: Developers
---

# CEDAR Cone and Report Standardization Guidelines

## Function Signature Standards

### Primary Analysis Functions
All main cone functions should follow this signature pattern:
```r
cone_function_name <- function(students, courses, opt, additional_data = NULL) {
  # Function body
}
```

**Parameters:**
- `students` - Always first parameter, student enrollment data
- `courses` - Always second parameter, course/section data  
- `opt` - Always third parameter, options list with filtering and configuration
- `additional_data` - Optional fourth parameter for specialized data (forecasts, degrees, etc.)

### Report Generation Functions
```r
create_[cone]_report <- function(students, courses, opt, output_format = "html") {
  # Function body
}
```

## Options Object (`opt`) Standards

### Required Options Validation
Every cone function should start with:
```r
# Validate required options
required_opts <- c("term", "dept")  # Customize per function
validate_cone_options(opt, required_opts)
```

### Default Options Pattern
```r
# Set function-specific defaults
opt <- set_cone_defaults(opt, list(
  uel = TRUE,           # Use exclude list
  status = "A",         # Active courses only
  aop = "compress"      # AOP handling
))
```

### Options Modification Pattern
Never modify the original `opt` object directly. Instead:
```r
# Create local copy for modifications
local_opt <- opt
local_opt$additional_param <- "value"
```

## Return Value Standards

### Data Processing Functions
Return a named list with consistent structure:
```r
return(list(
  data = processed_data,
  summary = summary_stats,
  metadata = list(
    function_name = "cone_function_name",
    options_used = opt,
    row_count = nrow(processed_data),
    processing_time = proc_time
  )
))
```

### Report Generation Functions
Return a standardized report object:
```r
return(list(
  report_path = output_path,
  report_data = report_data_object,
  success = TRUE/FALSE,
  messages = processing_messages
))
```

## R Markdown Parameter Standards

### Consistent Rmd Parameters
All report templates should use this parameter structure:
```yaml
params:
  opt: 1                    # Options object
  data: 1                   # Main data object(s)
  report_metadata: 1        # Report generation metadata
  output_filename: 1        # Output file specification
```

### Data Organization in Rmd
```r
# Extract data consistently in setup chunk
opt <- params$opt
report_data <- params$data
metadata <- params$report_metadata

# Validate data structure
validate_report_data(report_data, expected_components)
```

## Error Handling Standards

### Consistent Logging Pattern
```r
message(sprintf("[%s] Starting %s with %d rows", 
                function_name, description, nrow(input_data)))

# Processing steps with logging
message(sprintf("[%s] Processing step: %s", function_name, step_name))

# Final logging
message(sprintf("[%s] Completed. Returning %d rows", 
                function_name, nrow(output_data)))
```

### Error Handling Pattern
```r
tryCatch({
  # Main processing code
}, error = function(e) {
  message(sprintf("[%s] Error: %s", function_name, e$message))
  return(NULL)  # or appropriate error return
})
```

## Implementation Utilities

### Helper Functions to Create
```r
# Option validation and defaults
validate_cone_options(opt, required_fields)
set_cone_defaults(opt, defaults_list)

# Data validation
validate_report_data(data, expected_structure)
validate_student_data(students)
validate_course_data(courses)

# Consistent filtering wrapper
apply_standard_filters(data, opt)

# Standardized return object creation
create_cone_result(data, metadata, opt)
create_report_result(report_path, success, messages)
```

## Migration Strategy

1. **Phase 1**: Create utility functions in `includes/cone_standards.R`
2. **Phase 2**: Update one cone at a time to use new patterns
3. **Phase 3**: Standardize Rmd templates 
4. **Phase 4**: Update Shiny server.R to use consistent interfaces

## Testing Standards

Each cone should include example usage that demonstrates the standard interface:
```r
# Example usage (for testing/documentation)
example_opt <- list(
  term = "202510",
  dept = "HIST",
  uel = TRUE
)

result <- cone_function_name(students, courses, example_opt)
```