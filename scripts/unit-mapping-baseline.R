# unit-mapping-baseline.R — what unit does every program and subject land in?
#
#   Rscript --vanilla scripts/unit-mapping-baseline.R snapshot   # save today's
#   Rscript --vanilla scripts/unit-mapping-baseline.R compare    # diff against it
#   Rscript --vanilla scripts/unit-mapping-baseline.R reconcile  # Stage 2, once
#   Rscript --vanilla scripts/unit-mapping-baseline.R files      # Stage 3 preview
#   Rscript --vanilla scripts/unit-mapping-baseline.R colleges   # college proposals, once
#
# The ADR-002 migration replaces how CEDAR assigns units, in stages. Each stage
# must change exactly the rows that were decided and nothing else, so each is
# compared against a snapshot taken before the first one (Stage 0).
#
# The snapshot records, from the stored CEDAR tables:
#   programs — student-term rows per (program_type, major_code, dept_code)
#   courses  — enrollment rows per (subject_code, college, department)
# and is written beside the data as unit_mapping_baseline.qs.
#
# reconcile (ADR-002 Stage 2) settles the assistant's proposals in programs.csv
# against the units the stored tables carry today. A proposal that agrees is
# confirmed. One that disagrees stays proposed and is written to the review
# list beside the data, tagged with why today's unit is what it is. College-
# specific units today (one code, different units by college) become override
# rows. Run once, after scripts/propose-mappings.R --write and before any rows
# are confirmed by hand: it only ever touches proposed rows.
#
# files previews Stage 3: it assigns program units from programs.csv alone, as
# the transform will (resolve_program_units(), concentrations taking the unit
# of the student's primary major), and diffs that against the baseline.

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

mode <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(mode) || !mode %in% c("snapshot", "compare", "reconcile", "files", "colleges")) {
  stop("Usage: Rscript --vanilla scripts/unit-mapping-baseline.R snapshot|compare|reconcile|files|colleges")
}
# reconcile (Stage 2) and colleges (Stage 2b) read the lists that fed
# program_map.qs, retired at ADR-002 Stage 4. They did their work once and are
# kept as the record of how programs.csv and units.csv were seeded.
if (mode %in% c("reconcile", "colleges")) {
  stop("unit-mapping-baseline.R ", mode, " ran once, at ADR-002 Stage 2; the lists it read ",
       "were retired at Stage 4. snapshot, compare and files still run.", call. = FALSE)
}
baseline_file <- file.path(cedar_data_dir, "unit_mapping_baseline.qs")

current_units <- function() {
  list(
    programs = cedar_programs %>%
      count(program_type, major_code, dept_code, name = "rows"),
    courses = cedar_students %>%
      count(subject_code, college, department, name = "rows"),
    taken = Sys.time()
  )
}

diff_units <- function(before, after, keys, unit_col) {
  b <- before %>% group_by(across(all_of(keys))) %>%
    summarize(before = paste(sort(unique(.data[[unit_col]])), collapse = "|"),
              rows = sum(rows), .groups = "drop")
  a <- after %>% group_by(across(all_of(keys))) %>%
    summarize(after = paste(sort(unique(.data[[unit_col]])), collapse = "|"),
              .groups = "drop")
  full_join(b, a, by = keys) %>%
    filter(is.na(before) | is.na(after) | before != after) %>%
    arrange(desc(rows))
}

reconcile_programs <- function() {
  dir   <- cedar_institution_dir(cedar_base_dir)
  files <- read_institution_mappings(dir)
  pr    <- files$programs
  # Degrees carry a unit too, and some codes (short branch certificates) only
  # ever appear there. Their college is a name, so they inform the code-level
  # unit only.
  today_rows <- bind_rows(
    cedar_programs %>% filter(!grepl("Concentration", program_type), !is.na(major_code)) %>%
      select(major_code, college_code, dept_code, is_pre_major),
    cedar_degrees %>% filter(!is.na(major_code)) %>%
      transmute(major_code, college_code = NA_character_, dept_code, is_pre_major = NA))
  dominant <- function(df, ...) df %>% count(..., dept_code) %>%
    group_by(...) %>% arrange(desc(n), .by_group = TRUE) %>%
    summarize(today = dept_code[1],
              today_all = paste(sprintf("%s %d", coalesce(dept_code, "none"), n), collapse = ", "),
              rows = sum(n), .groups = "drop")
  by_code    <- dominant(today_rows, major_code)
  by_college <- dominant(today_rows, major_code, college_code) %>%
    inner_join(by_code %>% select(major_code, code_unit = today), by = "major_code") %>%
    filter(!is.na(college_code), today != code_unit)
  pre_today <- today_rows %>% filter(!is.na(is_pre_major)) %>% group_by(major_code) %>%
    summarize(pre_share_today = mean(is_pre_major), .groups = "drop") %>%
    mutate(pre_today = pre_share_today >= 0.5)

  # Why today's unit is what it is. Every hand-written decision lives in one
  # of these lists; anything else came from parsing the code.
  explicit <- unique(c(names(extra_p2d), names(premaj_canon), names(xvar_explicit),
                       names(ad_major_to_dept), department_less_major_codes))
  why_today <- function(code, today) case_when(
    is.na(today)                                         ~ "no unit today",
    code %in% department_less_major_codes                ~ "explicit: department_less_major_codes",
    today == code & !today %in% files$units$unit_code    ~ "self-named fallback",
    code %in% explicit                                   ~ "explicit: program_code_maps.R",
    TRUE                                                 ~ "derived from code parsing")

  pr <- pr %>% left_join(by_code, by = c("program_code" = "major_code")) %>%
    left_join(pre_today, by = c("program_code" = "major_code"))
  # Row by row: this code's proposal against this code's unit today.
  agrees <- pr$status == "proposed" & !nzchar(pr$in_college) & (
    (nzchar(pr$unit_code) & !is.na(pr$today) & pr$unit_code == pr$today) |
    (pr$basis == "no_unit" & pr$program_code %in% department_less_major_codes))
  pr$status[agrees] <- "confirmed"

  # Decided 2026-10-03 for the whole class: where today's unit is a real unit
  # chosen by hand in program_code_maps.R and the assistant disagrees or cannot
  # tell, the hand decision stands. Phantom (self-named) and missing units are
  # NOT settled here: they stay proposed for someone who knows the program.
  pr$why <- why_today(pr$program_code, pr$today)
  keep <- pr$status == "proposed" & !nzchar(pr$in_college) &
    pr$why == "explicit: program_code_maps.R" & pr$today %in% files$units$unit_code
  pr$evidence[keep] <- paste0(pr$evidence[keep], "; assistant proposed ",
                              ifelse(nzchar(pr$unit_code[keep]), pr$unit_code[keep], "nothing"))
  pr$unit_code[keep] <- pr$today[keep]
  pr$basis[keep]     <- "decided"
  pr$status[keep]    <- "confirmed"
  pr$notes[keep]     <- "Kept at its Stage 0 unit, a hand decision in program_code_maps.R; decided 2026-10-03."

  overrides <- by_college %>% transmute(
    program_code = major_code, in_college = college_code, unit_code = today, college_code = "",
    program_name = pr$program_name[match(major_code, pr$program_code)],
    is_pre_major = pr$is_pre_major[match(major_code, pr$program_code)],
    leads_to = "", basis = "override",
    status = ifelse(major_code %in% names(ad_major_to_dept) & today %in% files$units$unit_code,
                    "confirmed", "proposed"),
    evidence = sprintf("college %s carries %s today (%d rows), not %s", in_college, today, rows, code_unit),
    notes = ifelse(status == "confirmed", "Carried from ad_major_to_dept at Stage 2.", ""))

  # Pre-major status. Where every row agrees today, the flag came from the
  # reviewed lists (pre_major_exempt_codes and the F-code rule) and is carried
  # over. Where a code's rows disagree today -- a "Pre-" name on some rows only
  # -- no per-code value can reproduce it, so it is a decision.
  unanimous <- !is.na(pr$pre_share_today) & pr$pre_share_today %in% c(0, 1)
  pr$is_pre_major[unanimous] <- ifelse(pr$pre_today[unanimous], "TRUE", "FALSE")
  # Decided 2026-10-03: where today's rows disagree, the F code decides -- an
  # F or XF (accelerated-online F) code is a pre-major, anything else is not --
  # overruling pre_major_exempt_codes where they conflict (ISSUES I9).
  mixed <- !is.na(pr$pre_share_today) & !unanimous
  by_code <- grepl("^X?F[A-Z]", pr$program_code)
  pr$is_pre_major[mixed] <- ifelse(by_code[mixed], "TRUE", "FALSE")
  pr$notes[mixed] <- ifelse(by_code[mixed],
    "Pre-major by its F code; decided 2026-10-03 over mixed Pre- names and pre_major_exempt_codes (ISSUES I9).",
    "Not a pre-major (no F code); decided 2026-10-03 over mixed Pre- names.")
  canon_today <- unname(premaj_canon[pr$program_code])
  use_canon <- pr$is_pre_major == "TRUE" & !is.na(canon_today) &
    canon_today %in% pr$program_code & canon_today != pr$program_code
  pr$leads_to[use_canon] <- canon_today[use_canon]
  pr$leads_to[pr$is_pre_major != "TRUE"] <- ""
  pr$flag_issue <- case_when(
    mixed ~ sprintf("pre-major on %.0f%% of rows today; decided %s by F code",
                    100 * pr$pre_share_today, pr$is_pre_major),
    pr$is_pre_major == "TRUE" & !is.na(canon_today) & canon_today != pr$leads_to ~
      paste0("leads_to ", ifelse(nzchar(pr$leads_to), pr$leads_to, "none"),
             " here, premaj_canon says ", canon_today),
    TRUE ~ NA_character_)

  review <- pr %>% filter(status == "proposed" | basis == "decided" | !is.na(flag_issue)) %>% transmute(
    program_code, program_name, rows, proposed_unit = unit_code, basis,
    today_unit = today,
    why_today = case_when(status == "proposed" ~ why,
                          basis == "decided" ~ "kept hand decision",
                          TRUE ~ "unit agrees; pre-major or target differs"),
    flag_issue, today_all, is_pre_major, pre_today, leads_to, evidence) %>%
    bind_rows(overrides %>% filter(status == "proposed") %>%
                transmute(program_code = paste0(program_code, ":", in_college), program_name,
                          proposed_unit = unit_code, basis, why_today = "college-specific today",
                          evidence)) %>%
    arrange(why_today, desc(rows))

  files$programs <- bind_rows(pr %>% select(all_of(names(files$programs))), overrides) %>%
    arrange(program_code, in_college)
  validate_mapping_files(files)
  readr::write_csv(files$programs, file.path(dir, "programs.csv"), na = "")
  review_file <- file.path(cedar_data_dir, "stage2_program_review.csv")
  utils::write.csv(review, review_file, row.names = FALSE, na = "")
  message("Confirmed ", sum(agrees), " proposals that agree with today's units; added ",
          nrow(overrides), " college-specific rows.\n", nrow(review),
          " rows need a decision -> ", review_file)
  print(as.data.frame(count(review, why_today)))
}

units_from_files <- function() {
  programs <- read_institution_mappings(cedar_institution_dir(cedar_base_dir))$programs
  p <- cedar_programs %>% select(student_id, term, program_type, major_code, college_code)
  p$dept_code <- resolve_program_units(p$major_code, p$college_code, programs)
  primary <- p %>% filter(program_type == "Major") %>%
    distinct(student_id, term, .keep_all = TRUE) %>% select(student_id, term, primary_unit = dept_code)
  p %>% left_join(primary, by = c("student_id", "term")) %>%
    mutate(dept_code = if_else(grepl("Concentration", program_type), primary_unit, dept_code)) %>%
    count(program_type, major_code, dept_code, name = "rows")
}

# colleges (ADR-002, "Colleges are mapped, not read"): proposes each unit's home
# college and the programs whose college differs from their unit's, once, for
# review in the pull request that adds them. Fills only blank values.
#   Unit: where its course sections sit since 2024, branch-campus (AD) sections
#   aside unless it has no others; with no recent sections, where its programs'
#   majors are, by Banner's Translated College; with neither, the one college
#   all its subjects sit under in subjects.csv.
#   Program: Translated College of its primary-major rows, when that is a
#   different college from its unit's on at least 60% of at least 20 rows.
#   Pre-majors get none: they report under the college they lead to.
propose_colleges <- function(source_dir) {
  dir   <- cedar_institution_dir(cedar_base_dir)
  files <- read_institution_mappings(dir)
  as <- qs2::qs_read(file.path(source_dir, "academic_studies.qs"))
  message("Translated College from ", source_dir, ", pulled ", max(as.Date(as$as_of_date)))
  majors <- tibble(code = as$`Major Code`,
                   college = translate_source_college(as$`Translated College`, files)) %>%
    filter(!is.na(code), !is.na(college))
  share <- function(df, ...) df %>% count(..., college) %>% group_by(...) %>%
    mutate(share = n / sum(n), total = sum(n)) %>% slice_max(n, n = 1, with_ties = FALSE) %>%
    ungroup()
  shares_text <- function(df, key, value) {
    df %>% filter(.data[[key]] == value) %>% count(college, sort = TRUE) %>%
      mutate(txt = sprintf("%s %.0f%%", college, 100 * n / sum(n))) %>% pull(txt) %>%
      head(3) %>% paste(collapse = ", ")
  }

  # Units.
  recent <- cedar_sections %>% filter(term >= 202410) %>% select(unit = department, college)
  by_sections <- recent %>% group_by(unit) %>% filter(all(college == "AD") | college != "AD") %>%
    ungroup() %>% share(unit)
  pr_conf <- files$programs %>% filter(status == "confirmed", !nzchar(in_college), nzchar(unit_code))
  by_programs <- majors %>% inner_join(pr_conf %>% filter(is_pre_major == "FALSE") %>%
                                         select(code = program_code, unit = unit_code), by = "code") %>%
    share(unit)
  u <- files$units
  todo <- !nzchar(u$college_code)
  s_at <- match(u$unit_code, by_sections$unit)
  p_at <- match(u$unit_code, by_programs$unit)
  for (i in which(todo)) {
    if (!is.na(s_at[i])) {
      r <- by_sections[s_at[i], ]
      u$college_code[i] <- r$college
      u$notes[i] <- sprintf("College proposed 2026-10-04 from its course sections since Spring 2024: %s (%d sections).",
                            shares_text(recent, "unit", u$unit_code[i]), r$total)
    } else if (!is.na(p_at[i])) {
      r <- by_programs[p_at[i], ]
      u$college_code[i] <- r$college
      u$notes[i] <- sprintf("College proposed 2026-10-04 from its programs' majors (Banner Translated College): %s %.0f%% of %d rows; no sections since Spring 2024.",
                            r$college, 100 * r$share, r$total)
    } else {
      in_subjects <- unique(files$subjects$in_college[files$subjects$unit_code == u$unit_code[i]])
      if (length(in_subjects) == 1) {
        u$college_code[i] <- in_subjects
        u$notes[i] <- sprintf("College proposed 2026-10-04 from subjects.csv, where all its subjects sit under %s; no sections under it since Spring 2024 and no programs.",
                              in_subjects)
      }
    }
  }
  files$units <- u

  # Programs whose majors sit in another college than their unit's.
  unit_college <- setNames(u$college_code, u$unit_code)
  by_code <- share(majors, code)
  pr <- files$programs
  cand <- which(pr$status == "confirmed" & !nzchar(pr$in_college) & nzchar(pr$unit_code) &
                  pr$is_pre_major == "FALSE" & !nzchar(pr$college_code))
  at <- match(pr$program_code[cand], by_code$code)
  differs <- !is.na(at) & by_code$college[at] != unit_college[pr$unit_code[cand]] &
    by_code$share[at] >= 0.6 & by_code$total[at] >= 20
  for (k in which(differs)) {
    i <- cand[k]; r <- by_code[at[k], ]
    pr$college_code[i] <- r$college
    pr$notes[i] <- trimws(paste(pr$notes[i], sprintf(
      "college_code %s proposed 2026-10-04: its majors are %s (Banner Translated College, %d rows); its unit %s is %s.",
      r$college, shares_text(majors, "code", pr$program_code[i]), r$total,
      pr$unit_code[i], unit_college[pr$unit_code[i]])))
  }
  files$programs <- pr
  validate_mapping_files(files)
  readr::write_csv(files$units, file.path(dir, "units.csv"), na = "")
  readr::write_csv(files$programs, file.path(dir, "programs.csv"), na = "")
  message("Units given a college: ", sum(todo & nzchar(u$college_code)), " of ", sum(todo),
          "; still blank: ", paste(u$unit_code[!nzchar(u$college_code)], collapse = " "))
  message("Programs given their own college: ", sum(differs))
  print(as.data.frame(pr[cand[differs], c("program_code", "program_name", "unit_code", "college_code")]))
}

if (mode == "colleges") {
  args <- commandArgs(trailingOnly = TRUE)
  j <- match("--data-dir", args)
  source_dir <- if (!is.na(j)) args[j + 1] else
    if (nzchar(Sys.getenv("CEDAR_DATA_DIR"))) Sys.getenv("CEDAR_DATA_DIR") else cedar_data_dir
  propose_colleges(source_dir)
} else if (mode == "files") {
  base <- qs2::qs_read(baseline_file)
  prog <- diff_units(base$programs, units_from_files(), c("program_type", "major_code"), "dept_code")
  message("Program groups whose unit Stage 3 would change: ", nrow(prog), " (",
          format(sum(prog$rows, na.rm = TRUE), big.mark = ","), " student-term rows)")
  print(prog %>% mutate(is_conc = grepl("Concentration", program_type)) %>%
          group_by(is_conc, change = case_when(is.na(after) | !nzchar(after) ~ "loses its unit",
                                               is.na(before) | !nzchar(before) ~ "gains a unit",
                                               TRUE ~ "moves unit")) %>%
          summarize(groups = n(), rows = sum(rows, na.rm = TRUE), .groups = "drop"))
  out <- file.path(cedar_data_dir, "stage3_preview.csv")
  utils::write.csv(prog, out, row.names = FALSE, na = "")
  message("Every changed group -> ", out)
} else if (mode == "reconcile") {
  reconcile_programs()
} else if (mode == "snapshot") {
  snap <- current_units()
  qs2::qs_save(snap, baseline_file)
  message("Saved baseline: ", nrow(snap$programs), " program groups, ",
          nrow(snap$courses), " course groups -> ", baseline_file)
} else {
  if (!file.exists(baseline_file)) stop("No baseline at ", baseline_file, "; run snapshot first.")
  base <- qs2::qs_read(baseline_file)
  now <- current_units()
  message("Baseline taken ", format(base$taken), "\n")
  prog <- diff_units(base$programs, now$programs, c("program_type", "major_code"), "dept_code")
  crse <- diff_units(base$courses, now$courses, c("subject_code", "college"), "department")
  message("Programs whose unit changed: ", nrow(prog))
  if (nrow(prog)) print(as.data.frame(prog), right = FALSE)
  message("\nCourse subjects whose unit changed: ", nrow(crse))
  if (nrow(crse)) print(as.data.frame(crse), right = FALSE)
}
