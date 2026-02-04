#!/usr/bin/env Rscript
# Cedar Setup Script
# Interactive configuration wizard for first-time setup

cat("\n")
cat("═══════════════════════════════════════════════════════\n")
cat("  🌲 CEDAR Setup Wizard\n")
cat("═══════════════════════════════════════════════════════\n")
cat("\n")
cat("This script will help you set up Cedar for the first time.\n")
cat("You'll be asked a few questions to configure your installation.\n")
cat("\n")

# Helper function for yes/no prompts
ask_yes_no <- function(prompt, default = "y") {
  cat(sprintf("%s [%s/n]: ", prompt, if(default == "y") "Y" else "y"))
  response <- tolower(trimws(readline()))
  if (response == "") response <- default
  return(response == "y")
}

# Helper function for text prompts with defaults
ask_text <- function(prompt, default = NULL) {
  if (!is.null(default)) {
    cat(sprintf("%s\n  [default: %s]: ", prompt, default))
  } else {
    cat(sprintf("%s: ", prompt))
  }
  response <- trimws(readline())
  if (response == "" && !is.null(default)) {
    return(default)
  }
  return(response)
}

# Step 1: Check if config already exists
config_exists <- file.exists("config/config.R")
if (config_exists) {
  cat("⚠️  Warning: config/config.R already exists.\n")
  if (!ask_yes_no("   Overwrite existing configuration?", default = "n")) {
    cat("\n❌ Setup cancelled. Your existing config was not modified.\n\n")
    quit(save = "no", status = 0)
  }
  cat("\n")
}

# Step 2: Detect project directory
project_dir <- normalizePath(getwd(), winslash = "/")
cat("──────────────────────────────────────────────────────\n")
cat("📁 Project Directory\n")
cat("──────────────────────────────────────────────────────\n")
cat(sprintf("Detected: %s\n", project_dir))
if (!ask_yes_no("Is this correct?", default = "y")) {
  project_dir <- ask_text("Enter full path to Cedar directory")
  project_dir <- normalizePath(project_dir, winslash = "/")
}
cat(sprintf("✅ Using: %s\n\n", project_dir))

# Step 3: Configure term settings
cat("──────────────────────────────────────────────────────\n")
cat("📅 Academic Term Settings\n")
cat("──────────────────────────────────────────────────────\n")
cat("Term codes are 6-digit numbers in format YYYYCC:\n")
cat("  - Spring: 10 (e.g., 202510 = Spring 2025)\n")
cat("  - Summer: 60 (e.g., 202560 = Summer 2025)\n")
cat("  - Fall:   80 (e.g., 202580 = Fall 2025)\n\n")

current_term <- ask_text("What is your current term?", default = "202510")
while (nchar(current_term) != 6 || !grepl("^[0-9]+$", current_term)) {
  cat("❌ Invalid term code. Must be 6 digits (e.g., 202510).\n")
  current_term <- ask_text("What is your current term?", default = "202510")
}
cat(sprintf("✅ Current term: %s\n\n", current_term))

cat("Data range for reports (how far back to include data):\n")
report_start <- ask_text("Start term for reports", default = "201980")
report_end <- ask_text("End term for reports", default = current_term)
cat(sprintf("✅ Report range: %s to %s\n\n", report_start, report_end))

# Step 4: Data storage settings
cat("──────────────────────────────────────────────────────\n")
cat("💾 Data Storage\n")
cat("──────────────────────────────────────────────────────\n")

data_dir <- paste0(project_dir, "/data/")
cat(sprintf("Data directory: %s\n", data_dir))
if (!dir.exists(data_dir)) {
  if (ask_yes_no("Data directory doesn't exist. Create it?", default = "y")) {
    dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
    cat("✅ Created data directory\n")
  }
} else {
  cat("✅ Data directory exists\n")
}

output_dir <- paste0(project_dir, "/output/")
if (!dir.exists(output_dir)) {
  if (ask_yes_no("Create output directory for reports?", default = "y")) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    cat("✅ Created output directory\n")
  }
}

cat("\n")
if (ask_yes_no("Do you want to archive downloaded MyReports files?", default = "n")) {
  archive_dir <- ask_text("Enter path for MyReports archive")
  archive_dir <- normalizePath(archive_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(archive_dir)) {
    if (ask_yes_no(sprintf("Create archive directory at %s?", archive_dir), default = "y")) {
      dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
      cat("✅ Created archive directory\n")
    }
  }
} else {
  archive_dir <- NULL
  cat("ℹ️  MyReports archiving disabled\n")
}

cat("\n")
if (ask_yes_no("Do you use OneDrive for sharing reports?", default = "n")) {
  onedrive_dir <- ask_text("Enter OneDrive path", default = "~/Library/CloudStorage/OneDrive-YourOrg/CEDAR")
  onedrive_dir <- path.expand(onedrive_dir)
} else {
  onedrive_dir <- NULL
  cat("ℹ️  OneDrive integration disabled\n")
}

cat("\n")

# Step 5: Advanced settings
cat("──────────────────────────────────────────────────────\n")
cat("⚙️  Advanced Settings\n")
cat("──────────────────────────────────────────────────────\n")

use_qs <- ask_yes_no("Use fast .qs format for data files? (recommended)", default = "y")
reg_underway <- ask_yes_no("Is registration currently underway?", default = "n")

cat("\n")

# Step 6: Write configuration file
cat("──────────────────────────────────────────────────────\n")
cat("💾 Writing Configuration\n")
cat("──────────────────────────────────────────────────────\n")

config_lines <- c(
  sprintf('cedar_base_dir <- "%s"', project_dir),
  "",
  "# Directory paths",
  sprintf('cedar_output_dir <- paste0(cedar_base_dir, "output/")'),
  sprintf('cedar_data_dir <- paste0(cedar_base_dir, "data/")'),
  "",
  "# MyReports archive directory",
  if (is.null(archive_dir)) {
    "cedar_data_archive_dir <- NULL  # Archiving disabled"
  } else {
    sprintf('cedar_data_archive_dir <- "%s"', archive_dir)
  },
  "",
  "# OneDrive directory for sharing",
  if (is.null(onedrive_dir)) {
    "cedar_onedrive_dir <- NULL  # OneDrive integration disabled"
  } else {
    sprintf('cedar_onedrive_dir <- "%s"', onedrive_dir)
  },
  "",
  'Sys.setenv("shiny" = FALSE)',
  "",
  "# Data serialization format",
  sprintf("cedar_use_qs <- %s", toupper(as.character(use_qs))),
  "",
  "# Academic term settings",
  sprintf("cedar_current_term <- %s", current_term),
  sprintf("cedar_report_start_term <- %s", report_start),
  sprintf("cedar_report_end_term <- %s", report_end),
  "",
  "# Registration status",
  sprintf("cedar_registration_underway <- %s", toupper(as.character(reg_underway))),
  "",
  "# Registration statistics thresholds",
  "cedar_regstats_thresholds <- list()",
  "cedar_regstats_thresholds[[\"min_impacted\"]] <- 20",
  "cedar_regstats_thresholds[[\"pct_sd\"]] <- 1",
  "cedar_regstats_thresholds[[\"min_squeeze\"]] <- .3",
  "cedar_regstats_thresholds[[\"min_wait\"]] <- 20",
  "cedar_regstats_thresholds[[\"section_proximity\"]] <- .3",
  "",
  "# Visualization settings",
  'cedar_report_palette <- "Spectral"',
  "",
  "# Pandoc path (for R Markdown reports)",
  'rstudio_pandoc <- "/usr/local/bin/"'
)

writeLines(config_lines, "config/config.R")
cat("✅ Configuration written to config/config.R\n\n")

# Step 7: Install R packages
cat("──────────────────────────────────────────────────────\n")
cat("📦 R Package Installation\n")
cat("──────────────────────────────────────────────────────\n")

if (file.exists("renv.lock")) {
  if (ask_yes_no("Install/restore R packages with renv?", default = "y")) {
    cat("\nThis may take several minutes...\n")
    if (requireNamespace("renv", quietly = TRUE)) {
      renv::restore(prompt = FALSE)
      cat("✅ Packages restored successfully\n\n")
    } else {
      cat("Installing renv package manager...\n")
      install.packages("renv", repos = "https://cloud.r-project.org")
      renv::restore(prompt = FALSE)
      cat("✅ Packages restored successfully\n\n")
    }
  } else {
    cat("ℹ️  Skipped package installation. Run renv::restore() manually later.\n\n")
  }
} else {
  cat("⚠️  No renv.lock file found. Packages not installed automatically.\n\n")
}

# Step 8: Validate setup
cat("──────────────────────────────────────────────────────\n")
cat("🔍 Validating Setup\n")
cat("──────────────────────────────────────────────────────\n")

# Source the config we just created
tryCatch({
  source("config/config.R")
  cat("✅ Configuration loads successfully\n")

  # Run validation checks
  checks <- list(
    "Project directory exists" = dir.exists(cedar_base_dir),
    "Data directory exists" = dir.exists(cedar_data_dir),
    "Output directory exists" = dir.exists(cedar_output_dir),
    "Current term is set" = !is.null(cedar_current_term) && nchar(as.character(cedar_current_term)) == 6
  )

  all_pass <- TRUE
  for (check_name in names(checks)) {
    status <- if (checks[[check_name]]) "✅" else "❌"
    cat(sprintf("%s %s\n", status, check_name))
    if (!checks[[check_name]]) all_pass <- FALSE
  }

  cat("\n")

  if (!all_pass) {
    cat("⚠️  Some validation checks failed. Please review errors above.\n\n")
  }

}, error = function(e) {
  cat("❌ Error loading configuration:\n")
  cat(sprintf("   %s\n\n", e$message))
  all_pass <- FALSE
})

# Step 9: Check for data files
cat("──────────────────────────────────────────────────────\n")
cat("📊 Data Files\n")
cat("──────────────────────────────────────────────────────\n")

if (exists("cedar_data_dir") && dir.exists(cedar_data_dir)) {
  data_files <- list.files(cedar_data_dir, pattern = "\\.(qs|rds|Rds)$")

  if (length(data_files) == 0) {
    cat("⚠️  No data files found in data/ directory\n")
    cat("\n")
    cat("To use Cedar, you'll need to add MyReports data files:\n")
    cat("  1. Download reports from MyReports (DESR, Class Lists, etc.)\n")
    cat("  2. Run data parsers: Rscript cedar.R -f parse-data\n")
    cat("  3. Or see docs/data.md for detailed instructions\n")
  } else {
    cat(sprintf("✅ Found %d data file(s):\n", length(data_files)))
    for (f in head(data_files, 5)) {
      cat(sprintf("   - %s\n", f))
    }
    if (length(data_files) > 5) {
      cat(sprintf("   ... and %d more\n", length(data_files) - 5))
    }
  }
} else {
  cat("⚠️  Could not check for data files\n")
}

cat("\n")

# Step 10: Success message and next steps
cat("═══════════════════════════════════════════════════════\n")
cat("  ✅ Setup Complete!\n")
cat("═══════════════════════════════════════════════════════\n")
cat("\n")
cat("Your Cedar installation is configured. Here's how to use it:\n")
cat("\n")
cat("1️⃣  Command Line Interface:\n")
cat("   Rscript cedar.R -f enrl --help\n")
cat("\n")
cat("2️⃣  Web Interface (Shiny App):\n")
cat("   Rscript app.R\n")
cat("   Then open: http://localhost:3838\n")
cat("\n")
cat("3️⃣  Interactive R Session:\n")
cat("   Open cedar.Rproj in RStudio, then call:\n")
cat("   > cedar()\n")
cat("\n")
cat("📚 Documentation:\n")
cat("   - Getting started: docs/index.md\n")
cat("   - Data setup: docs/data.md\n")
cat("   - Web guide: docs/web-guide.md\n")
cat("\n")
cat("💡 Need help?\n")
cat("   - Check the documentation in docs/\n")
cat("   - Review config/config.R for all settings\n")
cat("   - Open an issue on GitHub\n")
cat("\n")
cat("Happy analyzing! 🌲\n")
cat("\n")
