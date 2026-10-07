# mapping-review.R — the mapping work list, in the terminal
#
#   Rscript --vanilla scripts/mapping-review.R
#
# Prints each mapping decision as a path:line into institution/<id>/, so in VS
# Code's terminal a click opens the row to edit; then the other problems no
# mapping can fix. It is the same list as Admin > Data & Usage > Mappings, built
# by the same function (build_mapping_worklist()), so the two cannot disagree.
#
# To accept a suggestion, change the row's status to confirmed. To choose
# otherwise, also change unit_code (or college_code) and, in programs.csv, set
# basis to decided. A note saying why helps the next reader. New codes in the
# data get proposed rows from scripts/propose-mappings.R --write. Uses the CEDAR
# tables in data/.

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

dir   <- file.path("institution", cedar_institution_id())
files <- read_institution_mappings(cedar_institution_dir(cedar_base_dir))
at    <- function(file, line) ifelse(is.na(line), file.path(dir, paste0(file, ".csv")),
                                     paste0(file.path(dir, paste0(file, ".csv")), ":", line))

issues <- build_admin_mapping_issues(get0("cedar_mapping_issues"), cedar_programs,
                                     files$units$unit_code)
audit  <- audit_mapping_coverage(files, sections = cedar_sections, students = cedar_students,
                                 programs = cedar_programs, degrees = cedar_degrees)
work   <- build_mapping_worklist(files, cedar_programs, issues, audit,
                                 source_departments = read_institution_file(
                                   "source_departments", cedar_institution_dir(cedar_base_dir)))

d <- work$decisions
cat(sprintf("\n── Mapping decisions (%d) %s\n", nrow(d), strrep("─", 50)))
for (i in seq_len(nrow(d))) {
  suggested <- if (is.na(d$suggested[i])) "none" else
    paste0(d$suggested[i], if (!is.na(d$suggested_name[i])) paste0(" (", d$suggested_name[i], ")"))
  cat(sprintf("%s  %s %s  %s | %s %s | suggested %s -- %s | needs: %s\n",
              at(d$file[i], d$line[i]), d$kind[i], d$code[i], d$name[i] %||% "",
              format(d$size[i], big.mark = ","), d$size_unit[i], suggested,
              d$confidence[i] %||% "unrated", d$needs[i]))
}

o <- work$other
cat(sprintf("\n── Other problems in the data (%d) %s\n", nrow(o), strrep("─", 42)))
for (i in seq_len(nrow(o))) {
  cat(sprintf("%s %s  %s | %s rows | %s\n", o$kind[i], o$code[i], o$context[i],
              format(o$size[i], big.mark = ","), o$needs[i]))
}
cat(sprintf("\n%d expected difference(s) not listed: pre-majors reporting under the college they lead to.\n",
            work$n_expected))
