# generic Rmd report creator
create_report <- function(opt, d_params) {
  message("[reporting.R] create_report() starting")
  message("[reporting.R]   output_filename: ", d_params$output_filename)
  message("[reporting.R]   is_docker: ", is_docker())
  message("[reporting.R]   working dir: ", getwd())

  # Determine output format
  output <- opt$output
  if (!is.null(output) && output == "aspx") {
    suffix <- "-report.aspx"
  } else {
    suffix <- ".html"
  }

  # Sanitize filename
  fixed_filename <- gsub(" ", "_", d_params$output_filename)
  output_file <- paste0(fixed_filename, suffix)

  if (is_docker()) {
    # Docker mode: render directly to data/ directory for download
    app_root <- getwd()
    data_dir <- file.path(app_root, "data")
    
    # Ensure data directory exists
    if (!dir.exists(data_dir)) {
      dir.create(data_dir, recursive = TRUE)
      message("[reporting.R]   created: ", data_dir)
    }

    output_path <- file.path(data_dir, output_file)
    message("[reporting.R]   rendering to: ", output_path)

    rmd_output <- rmarkdown::render(
      d_params$rmd_file,
      output_file = output_file,
      output_dir = data_dir,
      params = d_params
    )

    # Verify file was created
    if (file.exists(output_path)) {
      message("[reporting.R]   SUCCESS: file created at ", output_path)
    } else {
      message("[reporting.R]   ERROR: file NOT found at ", output_path)
      message("[reporting.R]   rmarkdown returned: ", rmd_output)
    }

  } # end docker rendering
  else { # non-docker rendering (CLI mode)
    message("[reporting.R]   CLI mode - using output_dir_base")
    Sys.setenv(RSTUDIO_PANDOC = rstudio_pandoc) # from config.R

    # Build output path from d_params
    output_subdir <- ifelse(!is.null(opt$output) && opt$output == "aspx", "aspx", "html")
    output_dir <- file.path(d_params$output_dir_base, output_subdir)
    
    # Ensure output directory exists
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
      message("[reporting.R]   created: ", output_dir)
    }

    output_path <- file.path(output_dir, output_file)
    message("[reporting.R]   rendering to: ", output_path)

    rmd_output <- rmarkdown::render(
      d_params$rmd_file,
      output_file = output_file,
      output_dir = output_dir,
      params = d_params
    )

    # Verify file was created
    if (file.exists(output_path)) {
      message("[reporting.R]   SUCCESS: file created at ", output_path)
    } else {
      message("[reporting.R]   ERROR: file NOT found at ", output_path)
    }
  }

  message("[reporting.R] create_report() complete")
  return(rmd_output)
} # end create_report
