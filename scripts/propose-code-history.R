# propose-code-history.R — propose code_history.csv rows for codes that look
# like successions of other codes
#
#   Rscript --vanilla scripts/propose-code-history.R [--institution unm]
#       [--min-sections 10] [--min-rows 20] [--write]
#
# The course dimension (ADR-001 step 4) follows the confirmed rows of
# institution/<id>/code_history.csv and nothing else. This script runs the
# screen in R/branches/courses.R, detect_course_renamings(), over the saved
# sections and class lists and PROPOSES rows for a person to confirm: every
# proposal is written with status `proposed` and the evidence that produced
# it, and assigns nothing until someone changes it to `confirmed`.
#
# It never edits an existing row, and never proposes a pair the file already
# has in any status. Dry run by default: prints what it would add. --write
# appends the new rows. --min-sections is the fewest shared sections a
# subject rename needs (default 10); --min-rows the fewest section and
# class-list rows a course renumbering's two codes need between them
# (default 20: a title seen once under each code is a coincidence as often
# as a succession). A course renumbering is proposed only when its title's
# retired and new codes are one each, which the screen already requires.
#
# A subject whose every course was renumbered one by one (ALB 450 to ALBS
# 450) arrives as course rows; a person may replace them with one subject
# row, which the dimension follows the same way.

args <- commandArgs(trailingOnly = TRUE)
write_rows <- "--write" %in% args
i <- match("--institution", args)
if (!is.na(i)) Sys.setenv(CEDAR_INSTITUTION = args[i + 1])
k <- match("--min-sections", args)
min_sections <- if (is.na(k)) 10L else as.integer(args[k + 1])
m <- match("--min-rows", args)
min_rows <- if (is.na(m)) 20L else as.integer(args[m + 1])

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

dir   <- cedar_institution_dir(cedar_base_dir)
files <- read_institution_mappings(dir)
pull  <- max(as.Date(cedar_sections$as_of_date), na.rm = TRUE)
message("Sections pulled ", pull, "; ", nrow(files$code_history), " rows in code_history.csv")

cand <- detect_course_renamings(cedar_sections, cedar_students, files)
enough <- ifelse(cand$kind == "subject", cand$n_evidence >= min_sections, cand$n_evidence >= min_rows)
new <- cand[is.na(cand$in_file) & enough, ]
skipped_thin <- sum(is.na(cand$in_file) & !enough)

cat(sprintf("\n%d candidate(s): %d already in the file, %d below --min-sections / --min-rows, %d new\n",
            nrow(cand), sum(!is.na(cand$in_file)), skipped_thin, nrow(new)))
if (nrow(new)) {
  print(as.data.frame(new %>% select(kind, from_code, to_code, effective_term, basis, n_evidence)),
        row.names = FALSE)
}

if (write_rows && nrow(new)) {
  rows <- new %>%
    arrange(kind != "subject", effective_term, from_code) %>%
    transmute(kind, from_code, to_code, effective_term = as.character(effective_term),
              scope = "", basis, status = "proposed", evidence,
              notes = sprintf("Proposed by scripts/propose-code-history.R from the %s pull; confirm it, correct it, or delete the row.", pull))
  out <- bind_rows(files$code_history, rows)
  readr::write_csv(out, file.path(dir, "code_history.csv"), na = "")
  # The file must still validate, with the new rows in it.
  read_institution_mappings(dir)
  message("Appended ", nrow(rows), " proposed row(s) to ", file.path(dir, "code_history.csv"))
} else if (nrow(new)) {
  message("\nDry run: rerun with --write to append these ", nrow(new), " row(s).")
}
