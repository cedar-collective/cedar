#!/usr/bin/env Rscript
#
# audit-mappings.R — verify CEDAR's lookups and join keys against real data.
#
# Re-run after any change to transform-to-cedar.R or R/lists/. Findings as of
# 2026-07-31 are written up in docs/developers/mapping-audit-2026-07.md.
#
# Checks, in order:
#   1. Cross-table vocabulary — does the same concept use the same values in
#      every table that carries it? (catches the code-vs-label splits)
#   2. Declared lookups vs observed data — coverage, orphans, duplicate keys.
#   3. Derivability — where the data already implies a clean 1:1, the map could
#      be generated rather than hand-maintained.
#
# Usage:  Rscript scripts/audit-mappings.R
# Exit:   0 always (reporting tool, not a gate) — read the output.

suppressMessages({library(qs2); library(dplyr)})

base_dir <- {
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) normalizePath(file.path(dirname(sub("^--file=", "", a[[1]])), "..")) else getwd()
}
setwd(base_dir)

source("config/shiny_config.R")
source("R/trunk/load-funcs.R")
suppressMessages(load_funcs(cedar_base_dir, modules = FALSE))

read_tbl <- function(n) {
  f <- file.path("data", paste0(n, ".qs"))
  if (!file.exists(f)) return(NULL)
  suppressWarnings(qs2::qs_read(f))
}
D <- list(sections = read_tbl("cedar_sections"), students = read_tbl("cedar_students"),
          programs = read_tbl("cedar_programs"), degrees  = read_tbl("cedar_degrees"),
          faculty  = read_tbl("cedar_faculty"))
missing <- names(D)[vapply(D, is.null, logical(1))]
if (length(missing)) stop("Missing cedar tables in data/: ", paste(missing, collapse = ", "))

uv <- function(x) { x <- as.character(x); sort(unique(x[!is.na(x) & nzchar(x)])) }
vals <- function(tb, col) if (is.null(D[[tb]][[col]])) character(0) else uv(D[[tb]][[col]])

# ── 1. Cross-table vocabulary ───────────────────────────────────────────────
cat("========== 1. CROSS-TABLE VOCABULARY ==========\n")
concepts <- list(
  department = list(sections="department", students="department", degrees="dept_code",
                    programs="dept_code", faculty="department"),
  college    = list(sections="college", students="college", degrees="college", programs="college_code"),
  campus     = list(sections="campus", students="campus", degrees="campus", programs="student_campus"),
  subject    = list(sections="subject", students="subject_code"),
  major      = list(students="major_code", programs="major_code", degrees="major_code")
)
for (cn in names(concepts)) {
  m <- concepts[[cn]]
  vs <- setNames(lapply(names(m), function(tb) vals(tb, m[[tb]])), names(m))
  cat("\n-- ", cn, "\n", sep = "")
  for (tb in names(vs))
    cat(sprintf("   %-9s $%-16s n=%-4d %s\n", tb, m[[tb]], length(vs[[tb]]),
                paste(head(vs[[tb]], 4), collapse=", ")))
  nm <- names(vs)
  for (i in seq_along(nm)) for (j in seq_along(nm)) if (i < j) {
    a <- vs[[i]]; b <- vs[[j]]
    if (!length(a) || !length(b)) next
    pct <- round(100 * length(intersect(a,b)) / length(union(a,b)))
    if (pct < 60)
      cat(sprintf("   !! %s vs %s share %d%% — %s\n", nm[i], nm[j], pct,
                  if (pct == 0) "DISJOINT VOCABULARIES" else "partial"))
  }
}

# ── 2. Declared lookups vs data ─────────────────────────────────────────────
cat("\n========== 2. DECLARED LOOKUPS vs DATA ==========\n")
report <- function(name, keys, data_vals) {
  keys <- uv(keys); dv <- uv(data_vals)
  gaps <- setdiff(dv, keys); orph <- setdiff(keys, dv)
  cov <- if (length(dv)) round(100 * length(intersect(keys, dv)) / length(dv)) else NA
  cat(sprintf("\n-- %-26s declared=%-4d data=%-4d coverage=%s%%\n", name, length(keys), length(dv), cov))
  cat(sprintf("   unmapped in data (%d): %s\n", length(gaps),
              if (!length(gaps)) "none" else paste(head(gaps, 10), collapse=", ")))
  cat(sprintf("   orphaned in map  (%d): %s\n", length(orph),
              if (!length(orph)) "none" else paste(head(orph, 10), collapse=", ")))
}
report("subj_to_dept",         names(subj_to_dept),         D$sections$subject)
report("major_to_dept",        names(major_to_dept),        D$programs$major_code)
report("dept_code_to_name",    names(dept_code_to_name),
       c(D$sections$department, D$programs$dept_code, D$degrees$dept_code))
report("college_name_to_code", names(college_name_to_code),
       c(D$programs$student_college, D$degrees$college))
report("hr_org_desc_to_dept",  names(hr_org_desc_to_dept),  D$faculty$home_org)

cat("\n-- duplicate keys (R returns the FIRST silently)\n")
for (nm in c("subj_to_dept","major_to_dept","college_name_to_code","dept_code_to_name")) {
  m <- get(nm)
  dups <- unique(names(m)[duplicated(names(m))])
  conflict <- Filter(function(k) length(unique(unname(m[names(m) == k]))) > 1, dups)
  cat(sprintf("   %-22s duplicates=%-3d conflicting=%-3d %s\n", nm, length(dups), length(conflict),
              if (length(conflict)) paste(conflict, collapse=", ") else ""))
  for (k in conflict)
    cat(sprintf("      %-6s -> %-20s uses: %s\n", k,
                paste(unique(unname(m[names(m) == k])), collapse=" vs "), m[[k]]))
}

# ── 3. Derivability ─────────────────────────────────────────────────────────
cat("\n========== 3. DERIVABLE FROM DATA? ==========\n")
chk <- function(label, df, key, val) {
  t <- df %>%
    filter(!is.na(.data[[key]]), nzchar(as.character(.data[[key]])),
           !is.na(.data[[val]]), nzchar(as.character(.data[[val]]))) %>%
    count(k = .data[[key]], v = .data[[val]]) %>%
    group_by(k) %>% summarise(n_vals = n(), .groups = "drop")
  amb <- filter(t, n_vals > 1)
  cat(sprintf("   %-36s keys=%-4d ambiguous=%-3d %s\n", label, nrow(t), nrow(amb),
              if (nrow(amb)) paste("e.g.", paste(head(amb$k, 4), collapse=", ")) else "clean 1:1"))
}
chk("sections: subject -> department",  D$sections, "subject",    "department")
chk("programs: major_code -> dept_code", D$programs, "major_code", "dept_code")
chk("degrees:  major_code -> dept_code", D$degrees,  "major_code", "dept_code")

# Campus label <-> code, derived by joining the two vocabularies on student+term.
cat("\n-- campus label <-> code, derived from student_id + term\n")
j <- inner_join(
  D$students %>% select(student_id, term, code = student_campus) %>%
    filter(!is.na(code), nzchar(code)) %>% distinct(),
  D$programs %>% select(student_id, term, label = student_campus) %>%
    filter(!is.na(label), nzchar(label)) %>% distinct(),
  by = c("student_id", "term"))
pairs <- count(j, label, code, sort = TRUE)
print(as.data.frame(pairs))
amb <- pairs %>% group_by(label) %>% filter(n() > 1) %>% ungroup()
cat("   ambiguous labels:", if (nrow(amb) == 0) "NONE — clean 1:1\n" else paste(nrow(amb), "\n"))

cat("\nDone. Narrative: docs/developers/mapping-audit-2026-07.md\n")
