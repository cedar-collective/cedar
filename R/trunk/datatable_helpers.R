# Helper functions for DataTable formatting and styling
# These functions provide reusable formatting for DT::datatable objects

# Color scheme presets for different column types
COLOR_SCHEMES <- list(
  availability = list(
    thresholds = c(5, 15),
    colors = c('#f8d7da', '#fff3cd', '#d4edda'),  # Red, Yellow, Green
    reverse_scale = FALSE
  ),
  enrollment = list(
    thresholds = c(8, 12),
    colors = c('#f8d7da', '#fff3cd', '#d1ecf1'),  # Red, Yellow, Blue
    reverse_scale = FALSE
  ),
  difference = list(
    thresholds = c(-5, 5),
    colors = c('#f8d7da', '#fff9e6', '#d4edda'),  # Red, Light Yellow, Green
    reverse_scale = FALSE
  ),
  dfw = list(
    thresholds = c(15, 30),
    colors = c('#d4edda', '#fff3cd', '#f8d7da'),  # Green, Yellow, Red
    reverse_scale = FALSE
  )
)


#' Apply color coding to a column using preset or custom scheme
#'
#' @param dt A DT::datatable object
#' @param column Character string of column name to color code
#' @param scheme Character name of preset scheme OR list with thresholds/colors/reverse_scale
#' @param bold Logical, if TRUE makes the column text bold
#' @return Modified datatable object with color formatting applied
#' 
#' @examples
#' # Using preset scheme
#' dt %>% apply_column_colors("avail", "availability")
#' 
#' # Using custom scheme
#' dt %>% apply_column_colors("my_col", list(
#'   thresholds = c(10, 20),
#'   colors = c('red', 'yellow', 'green'),
#'   reverse_scale = FALSE
#' ))
apply_column_colors <- function(dt, column, scheme, bold = TRUE) {
  
  # Validate dt input
  if (!inherits(dt, "datatables")) {
    stop("dt must be a datatables object from DT::datatable()")
  }
  
  # Get scheme configuration
  if (is.character(scheme)) {
    if (!scheme %in% names(COLOR_SCHEMES)) {
      stop("Unknown color scheme: ", scheme, ". Available: ", paste(names(COLOR_SCHEMES), collapse = ", "))
    }
    config <- COLOR_SCHEMES[[scheme]]
  } else if (is.list(scheme)) {
    config <- scheme
  } else {
    stop("scheme must be a character (preset name) or list (custom config)")
  }
  
  # Validate config
  if (length(config$colors) != length(config$thresholds) + 1) {
    stop("colors length must be thresholds length + 1")
  }
  
  # Reverse colors if specified
  colors <- if (config$reverse_scale) rev(config$colors) else config$colors
  
  # Apply the color formatting
  style_args <- list(
    dt,
    column,
    backgroundColor = DT::styleInterval(config$thresholds, colors)
  )
  
  # Add bold if requested
  if (bold) {
    style_args$fontWeight <- 'bold'
  }
  
  do.call(DT::formatStyle, style_args)
}


#' Create a styled datatable with automatic color coding
#' 
#' Applies color schemes based on column names matching preset patterns.
#' Can also accept custom column-to-scheme mappings.
#' 
#' @param data Data frame to display
#' @param column_schemes Named list mapping column names to scheme names or NULL for auto-detection
#' @param pageLength Integer, number of rows per page (default 50)
#' @return Styled datatable object
#' 
#' @examples
#' # Auto-detect columns
#' create_styled_datatable(my_data)
#' 
#' # Custom mappings
#' create_styled_datatable(my_data, column_schemes = list(
#'   "seats_left" = "availability",
#'   "students" = "enrollment"
#' ))
create_styled_datatable <- function(data, 
                                   column_schemes = NULL,
                                   pageLength = 50) {
  
  # Create base datatable
  dt <- DT::datatable(
    data,
    options = list(
      pageLength = pageLength,
      scrollX = TRUE,
      dom = 'Bfrtip',
      buttons = c('copy', 'csv', 'excel')
    ),
    rownames = FALSE,
    class = 'cell-border stripe hover'
  )
  
  # Auto-detect column schemes if not provided
  if (is.null(column_schemes)) {
    column_schemes <- list()
    cols <- colnames(data)
    
    # Availability columns
    if ("avail" %in% cols) column_schemes[["avail"]] <- "availability"
    
    # Enrollment columns
    if ("ENRL" %in% cols) column_schemes[["ENRL"]] <- "enrollment"
    if ("enrolled" %in% cols) column_schemes[["enrolled"]] <- "enrollment"
    if ("Enrolled" %in% cols) column_schemes[["Enrolled"]] <- "enrollment"
    
    # Difference columns
    if ("avail_diff" %in% cols) column_schemes[["avail_diff"]] <- "difference"
    if ("enrl_diff_from_last_year" %in% cols) column_schemes[["enrl_diff_from_last_year"]] <- "difference"
    
    # DFW columns
    if ("DFW %" %in% cols) column_schemes[["DFW %"]] <- "dfw"
  }
  
  # Apply color schemes to each column
  for (col_name in names(column_schemes)) {
    if (col_name %in% colnames(data)) {
      dt <- apply_column_colors(dt, col_name, column_schemes[[col_name]])
    }
  }
  
  return(dt)
}


# Convenience wrapper for seatfinder tables (backward compatibility)
create_seatfinder_datatable <- function(data, 
                                        color_avail = TRUE,
                                        color_diff = TRUE, 
                                        color_dfw = TRUE,
                                        color_enrl = FALSE,
                                        pageLength = 50) {
  
  # Build column schemes based on flags
  column_schemes <- list()
  
  if (color_avail && "avail" %in% colnames(data)) {
    column_schemes[["avail"]] <- "availability"
  }
  
  if (color_diff && "avail_diff" %in% colnames(data)) {
    column_schemes[["avail_diff"]] <- "difference"
  }
  
  if (color_dfw && "DFW %" %in% colnames(data)) {
    column_schemes[["DFW %"]] <- "dfw"
  }
  
  if (color_enrl) {
    if ("ENRL" %in% colnames(data)) {
      column_schemes[["ENRL"]] <- "enrollment"
    } else if ("enrolled" %in% colnames(data)) {
      column_schemes[["enrolled"]] <- "enrollment"
    }
  }
  
  create_styled_datatable(data, column_schemes, pageLength)
}
