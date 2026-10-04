# mapping-review.R — everything in the mapping files that needs a person's decision
#
#   Rscript --vanilla scripts/mapping-review.R
#
# Prints each item as a path:line into institution/<id>/, so in VS Code's
# terminal a click opens the row to edit. The same two functions build Admin >
# Data & Usage > Mappings -- build_program_mapping_queue() and
# audit_mapping_coverage() -- so this list and that page cannot disagree.
#
# To decide a row: set unit_code (and college_code if needed), set status to
# confirmed, and say why in notes. New codes in the data get proposed rows from
# scripts/propose-mappings.R --write. Uses the CEDAR tables in data/.

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

dir   <- file.path("institution", cedar_institution_id())
files <- read_institution_mappings(cedar_institution_dir(cedar_base_dir))
at    <- function(file, line) ifelse(is.na(line), file.path(dir, paste0(file, ".csv")),
                                     paste0(file.path(dir, paste0(file, ".csv")), ":", line))
heading <- function(title, n) cat(sprintf("\n── %s (%d) %s\n", title, n,
                                          strrep("─", max(0, 60 - nchar(title)))))

issues <- build_admin_mapping_issues(get0("cedar_mapping_issues"), cedar_programs,
                                     files$units$unit_code)
queue <- build_program_mapping_queue(files, cedar_programs, issues,
                                     known_units = files$units$unit_code)$queue
audit <- audit_mapping_coverage(files, sections = cedar_sections, students = cedar_students,
                                programs = cedar_programs, degrees = cedar_degrees)

heading("Programs to decide: programs.csv", nrow(queue))
for (i in seq_len(nrow(queue))) {
  q <- queue[i, ]
  cat(sprintf("%s  %s  %s | %s students | today %s | suggested %s (%s)\n",
              at("programs", q$line), q$program_code, q$program_name %||% "", q$students,
              q$today, if (nzchar(q$suggested_unit)) q$suggested_unit else "none", q$basis))
}

subjects <- audit %>% filter(kind == "subject")
heading("Course subjects to decide: subjects.csv", nrow(subjects))
for (i in seq_len(nrow(subjects))) {
  a <- subjects[i, ]
  row <- files$subjects[files$subjects$subject_code == a$value & files$subjects$status == "proposed", ]
  cat(sprintf("%s  %s  %s | %s enrollments | suggested %s\n",
              at("subjects", a$line), a$value, a$context, format(a$rows, big.mark = ","),
              if (nrow(row) && nzchar(row$unit_code[1])) row$unit_code[1] else "none"))
}

colleges <- audit %>% filter(kind == "college_disagreement", status == "review")
heading("Mapped colleges to review: programs.csv", nrow(colleges))
for (i in seq_len(nrow(colleges))) {
  a <- colleges[i, ]
  cat(sprintf("%s  %s  %s | %s rows\n", at(a$file, a$line), a$value, a$context,
              format(a$rows, big.mark = ",")))
}

other <- audit %>% filter(!kind %in% c("subject", "college_disagreement"),
                          !(kind == "program_code" & value %in% queue$program_code))
heading("Other values with no mapping", nrow(other))
for (i in seq_len(nrow(other))) {
  a <- other[i, ]
  cat(sprintf("%s  %s  %s | %s rows | needs: %s\n", at(a$file, a$line), a$value, a$context,
              format(a$rows, big.mark = ","), a$needs))
}

expected <- sum(audit$status == "expected")
cat(sprintf("\n%d expected difference(s) not listed: pre-majors reporting under the college they lead to.\n",
            expected))
