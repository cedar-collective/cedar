# propose-mappings.R — propose programs.csv rows for codes that have none
#
#   Rscript --vanilla scripts/propose-mappings.R [--institution unm]
#       [--data-dir <dir with the source exports>] [--write]
#
# The mapping assistant from ADR-002. The transform reads institution/<id>/
# mapping files and nothing else; this script is the only place source-system
# fields and data patterns are used, and only to PROPOSE rows for a person to
# confirm. Every proposal is written with status `proposed` and the evidence
# that produced it, and assigns nothing until someone changes it to `confirmed`.
#
# It never edits an existing row. Dry run by default: prints what it would add.
# --write appends the new rows to programs.csv.
#
# Evidence, strongest first. The first tier that settles a code wins.
#   1. source_department — the source system's owning department for the code's
#      primary-major rows, read through source_departments.csv. A `split`
#      department is settled among its candidate units by the tiers below; a
#      `non_degree` one means nothing owns the program (basis no_unit); a
#      `bucket` says nothing and the code falls through.
#   2. inherited — a pre-major takes the unit of the program it leads to.
#   3. subject_code — the code is also a course subject in subjects.csv.
#   4. name_match — the program's name is a unit's name.
#   5. course_taking — the unit whose courses the program's students take far
#      more than students overall do.
# A minor or second major that is also someone's primary major needs no tier:
# programs.csv is keyed by code, so it shares the primary major's row.

args <- commandArgs(trailingOnly = TRUE)
write_rows <- "--write" %in% args
i <- match("--institution", args)
if (!is.na(i)) Sys.setenv(CEDAR_INSTITUTION = args[i + 1])
j <- match("--data-dir", args)

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

dir      <- cedar_institution_dir(cedar_base_dir)
files    <- read_institution_mappings(dir)
src_dept <- validate_source_departments(read_institution_file("source_departments", dir),
                                        files$units)

# ── Source adapter: Banner / MyReports ───────────────────────────────────────
# The only part of this script that knows a source system's column names. An
# institution with different exports replaces this block; everything below
# works on the four tibbles it produces.
#   occurrences: one row per (code, type) occurrence — code, type, name
#   primary:     one row per primary-major occurrence — code, source_name
#   colleges:    one row per primary-major occurrence — code, college (the
#                source's academic college for the student, as a college code)
#   enrolments:  student-term program codes — student_id, term, code
#   courses:     student-term course units — student_id, term, unit_code
# and pre_major_code_pattern: how the source marks a pre-major in its codes, if
# it does. Banner gives a pre-major an F prefix (FBIO is pre-Biology) but names
# it like its target ("Biology"), so the name alone cannot say which is which.
pre_major_code_pattern <- "^F[A-Z]"
# Read the exports the transform reads. The repository's data/ can hold an
# older copy than the shared data directory, and proposing from it misses every
# code that arrived since (it missed FRAD, ISSUES I7's Radiologic Sciences).
source_dir <- if (!is.na(j)) args[j + 1] else
  if (nzchar(Sys.getenv("CEDAR_DATA_DIR"))) Sys.getenv("CEDAR_DATA_DIR") else cedar_data_dir
academic_studies <- qs2::qs_read(file.path(source_dir, "academic_studies.qs"))
degrees          <- qs2::qs_read(file.path(source_dir, "degrees.qs"))
message("Source exports from ", source_dir, ": academic_studies pulled ",
        max(as.Date(academic_studies$as_of_date)), ", degrees pulled ",
        max(as.Date(degrees$as_of_date)))

code_cols <- c(`Major Code` = "Major", `Second Major Code` = "Second Major",
               `First Minor Code` = "First Minor", `Second Minor Code` = "Second Minor")
occurrences <- bind_rows(lapply(names(code_cols), function(cc) {
  tibble(code = academic_studies[[cc]], type = code_cols[[cc]],
         name = academic_studies[[code_cols[[cc]]]])
}), tibble(code = degrees$`Major Code`, type = "Major", name = degrees$Major)) %>%
  filter(!is.na(code), nzchar(code), !grepl("^[0-9]+$", code))
primary <- bind_rows(
  tibble(code = academic_studies$`Major Code`, source_name = academic_studies$Department),
  tibble(code = degrees$`Major Code`, source_name = degrees$Department)
) %>% filter(!is.na(code), nzchar(code), !is.na(source_name), nzchar(source_name))
# Banner's Translated College: its translation of each student to an academic
# college (graduate students to their college, not Graduate Programs).
colleges <- tibble(code = academic_studies$`Major Code`,
                   college = translate_source_college(academic_studies$`Translated College`, files)) %>%
  filter(!is.na(code), !is.na(college))
enrolments <- cedar_programs %>%
  filter(!grepl("Concentration", program_type), !is.na(major_code)) %>%
  distinct(student_id, term, code = major_code)
courses <- cedar_students %>% filter(!is.na(department)) %>%
  select(student_id, term, unit_code = department)
rm(academic_studies, degrees)
# ── end of source adapter ────────────────────────────────────────────────────

pre_pattern <- "^Pre[- ]+"
norm_name <- function(x) tolower(gsub("\\s+", " ", gsub("&", "and", trimws(x))))

codes <- occurrences %>%
  mutate(is_pre = grepl(pre_pattern, name, ignore.case = TRUE),
         name = trimws(sub(pre_pattern, "", name, ignore.case = TRUE))) %>%
  group_by(code) %>%
  summarize(program_name = names(sort(table(name), decreasing = TRUE))[1],
            pre_share = mean(is_pre), rows = n(),
            types = paste(sort(unique(type)), collapse = "; "), .groups = "drop")

new_codes <- setdiff(codes$code, files$programs$program_code)
message(nrow(codes), " program codes in the data; ", length(new_codes), " have no row.")

# Tier 1 evidence: the dominant source department per code, with its share.
dept_evidence <- primary %>% count(code, source_name) %>%
  group_by(code) %>% mutate(share = n / sum(n)) %>%
  slice_max(n, n = 1, with_ties = FALSE) %>% ungroup() %>%
  left_join(src_dept %>% select(source_name, sd_units = unit_code, kind), by = "source_name")

# Course-taking lift: how much more a program's students take a unit's courses
# than students overall. Raw share would name ENGL for every program.
unit_base <- courses %>% count(unit_code) %>% mutate(base = n / sum(n)) %>% select(-n)
course_lift <- enrolments %>% filter(code %in% new_codes) %>%
  inner_join(courses, by = c("student_id", "term"), relationship = "many-to-many") %>%
  count(code, unit_code) %>% group_by(code) %>% mutate(share = n / sum(n)) %>% ungroup() %>%
  inner_join(unit_base, by = "unit_code") %>% mutate(lift = share / base) %>%
  filter(n >= 5, lift > 1) %>% arrange(code, desc(lift))

subject_units <- files$subjects %>% distinct(subject_code, unit_code) %>%
  group_by(subject_code) %>% filter(n() == 1) %>% ungroup()
unit_by_name <- setNames(files$units$unit_code, norm_name(files$units$unit_name))

propose_one <- function(code, name, candidates = files$units$unit_code) {
  su <- subject_units$unit_code[subject_units$subject_code == code]
  if (length(su) && su %in% candidates)
    return(list(unit = su, basis = "subject_code", why = paste0("course subject ", code)))
  nm <- unname(unit_by_name[norm_name(name)])
  if (length(nm) && !is.na(nm) && nm %in% candidates)
    return(list(unit = nm, basis = "name_match", why = paste0("unit named \"", name, "\"")))
  # Choosing among every unit needs a strong signal; choosing among a split
  # department's two or three candidates needs only the best of them.
  open_choice <- length(candidates) > 10
  cl <- course_lift %>% filter(code == !!code, unit_code %in% candidates,
                               !open_choice | (n >= 20 & lift >= 3))
  if (nrow(cl))
    return(list(unit = cl$unit_code[1], basis = "course_taking",
                why = sprintf("students take %s courses at %.1fx the overall rate (%d enrolments)",
                              cl$unit_code[1], cl$lift[1], cl$n[1])))
  NULL
}

# A pre-major is named "Pre-" on most rows, or follows the source's pre-major
# code convention AND shares its name with a declared program -- the twin is
# what it leads to. The twin test keeps a real program that merely starts with
# the convention's letter (French, FREN) from being called a pre-major.
by_convention <- grepl(pre_major_code_pattern, codes$code)
declared <- codes[!by_convention & codes$pre_share < 0.5, ] %>% arrange(desc(rows)) %>%
  distinct(name_key = norm_name(program_name), .keep_all = TRUE)
twin <- declared$code[match(norm_name(codes$program_name), declared$name_key)]
codes$is_pre_major <- codes$pre_share >= 0.5 | (by_convention & !is.na(twin))
codes$leads_to <- ifelse(codes$is_pre_major & twin != codes$code, twin, NA)
# Declared programs first, so a pre-major can inherit what its target was just
# proposed, not only what is already confirmed.
proposals <- codes %>% filter(code %in% new_codes) %>% arrange(is_pre_major, desc(rows))

known <- with(files$programs[files$programs$status == "confirmed", ],
              setNames(unit_code, program_code))
rows_out <- vector("list", nrow(proposals))
for (k in seq_len(nrow(proposals))) {
  p  <- proposals[k, ]
  ev <- sprintf("%d rows as %s", p$rows, p$types)
  if (p$pre_share > 0 && p$pre_share < 1)
    ev <- c(ev, sprintf("named Pre- on %.0f%% of rows", 100 * p$pre_share))
  d <- dept_evidence[dept_evidence$code == p$code, ]
  res <- NULL
  if (nrow(d)) {
    ev <- c(ev, sprintf("source department \"%s\" on %.0f%% of primary-major rows",
                        d$source_name, 100 * d$share))
    if (is.na(d$kind)) {
      ev <- c(ev, "that department has no source_departments.csv row")
    } else if (d$share < 0.8) {
      ev <- c(ev, "too mixed to settle the unit")
    } else if (d$kind == "department") {
      res <- list(unit = d$sd_units, basis = "source_department", why = NULL)
    } else if (d$kind == "non_degree") {
      res <- list(unit = "", basis = "no_unit", why = "a department that owns no programs")
    } else if (d$kind == "split") {
      cands <- strsplit(d$sd_units, "|", fixed = TRUE)[[1]]
      res <- propose_one(p$code, p$program_name, cands)
      if (!is.null(res)) res$basis <- "source_department"
      else ev <- c(ev, paste("split department; none of", d$sd_units, "fits"))
    }
  }
  if (is.null(res) && isTRUE(p$is_pre_major) && !is.na(p$leads_to)) {
    tgt <- unname(known[p$leads_to])
    if (!is.na(tgt) && nzchar(tgt))
      res <- list(unit = tgt, basis = "inherited", why = paste0("leads to ", p$leads_to))
  }
  if (is.null(res)) res <- propose_one(p$code, p$program_name)
  if (is.null(res)) res <- list(unit = "", basis = "unresolved", why = "no evidence settles the unit")
  known[p$code] <- res$unit
  # The program's own college, only where its majors sit mostly in a different
  # college from its unit's. A pre-major reports under the college it leads to.
  college <- ""
  unit_college <- files$units$college_code[match(res$unit, files$units$unit_code)]
  cc <- colleges %>% filter(code == p$code) %>% count(college, sort = TRUE)
  if (!isTRUE(p$is_pre_major) && nrow(cc) && !is.na(unit_college) &&
      cc$college[1] != unit_college && sum(cc$n) >= 20 && cc$n[1] / sum(cc$n) >= 0.6) {
    college <- cc$college[1]
    ev <- c(ev, sprintf("majors in college %s on %.0f%% of %d rows, unlike its unit's %s",
                        college, 100 * cc$n[1] / sum(cc$n), sum(cc$n), unit_college))
  }
  rows_out[[k]] <- tibble(program_code = p$code, in_college = "", program_name = p$program_name,
         unit_code = res$unit, college_code = college, is_pre_major = ifelse(p$is_pre_major, "TRUE", "FALSE"),
         leads_to = coalesce(p$leads_to, ""), basis = res$basis, status = "proposed",
         evidence = paste(c(ev, res$why), collapse = "; "), notes = "")
}
out <- bind_rows(rows_out)

if (nrow(out)) {
  message("\nProposals by basis:")
  print(as.data.frame(count(out, basis, unit_settled = nzchar(unit_code) | basis == "no_unit")))
  unsettled <- out %>% filter(basis == "unresolved")
  message("\nCodes no evidence settles (", nrow(unsettled), "):")
  if (nrow(unsettled)) print(as.data.frame(unsettled %>% select(program_code, program_name, evidence)),
                             right = FALSE)
}
unknown_src <- setdiff(primary$source_name, src_dept$source_name)
if (length(unknown_src))
  message("\nSource departments with no source_departments.csv row: ",
          paste(sort(unknown_src), collapse = "; "))

if (write_rows && nrow(out)) {
  files$programs <- bind_rows(files$programs, out)
  validate_mapping_files(files)
  readr::write_csv(files$programs, file.path(dir, "programs.csv"), na = "")
  message("\nAppended ", nrow(out), " proposed rows to ", file.path(dir, "programs.csv"))
} else if (nrow(out)) {
  message("\nDry run: rerun with --write to append these ", nrow(out), " rows.")
}
