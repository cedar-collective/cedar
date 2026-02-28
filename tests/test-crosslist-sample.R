# test-crosslist-sample.R
#
# Integration test: verifies crosslist_primary and split-level detection
# using real rows from data/samples/desr_sample.csv.
#
# Unlike the unit tests in tests/testthat/ (which use synthetic known_sections_xl),
# this test uses actual DESR rows to catch real-data messiness:
#   - SHORT_TEXT casing inconsistency ("home" vs "Home")
#   - Cases where enrollment-based detection would give the WRONG home section
#   - Multi-way crosslist groups (3+ CRNs)
#   - Lab sections (crse_base strips trailing "L")
#
# Run from the cedar project root:
#   Rscript tests/test-crosslist-sample.R
#
# Requires: data/samples/desr_sample.csv (gitignored, local only)

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(readr))

sample_path <- "data/samples/desr_sample.csv"

if (!file.exists(sample_path)) {
  stop("Sample data not found: ", sample_path,
       "\nRun the sample extraction script or copy desr_sample.csv to data/samples/")
}

message("Loading sample: ", sample_path)
raw <- read_csv(sample_path, col_types = cols(.default = "c"), show_col_types = FALSE)
message("  ", nrow(raw), " rows, ", ncol(raw), " columns")

# ── Simulate parse-DESR.R output ─────────────────────────────────────────────
# Apply the same derived fields that parse-DESR.R computes before transform-to-cedar.R

sample <- raw %>%
  mutate(
    enrolled       = as.integer(ENROLLED),
    XL_ENRL        = as.integer(coalesce(XL_TOTAL_ENROLLMENT, "0")),
    total_enrl     = pmax(enrolled, XL_ENRL, na.rm = TRUE),
    crse_base      = suppressWarnings(
                       as.integer(sub("[A-Za-z]+$", "", `CRSE#`))
                     ),
    level          = case_when(
                       crse_base < 300               ~ "lower",
                       crse_base >= 1000             ~ "lower",
                       crse_base >= 500 & crse_base < 700 ~ "grad",
                       crse_base >= 300 & crse_base < 500 ~ "upper",
                       TRUE ~ NA_character_
                     ),
    section_id     = paste0(TERM, "-", CRN),
    subject        = SUBJ,
    term           = as.integer(TERM),
    crosslist_code = ifelse(is.na(XL_CODE) | XL_CODE == "", NA_character_, XL_CODE),
    xl_home_text   = ifelse(is.na(SHORT_TEXT) | SHORT_TEXT == "", NA_character_, SHORT_TEXT)
  )

# ── Apply crosslist enrichment (mirrors transform-to-cedar.R post-processing) ─

sample <- sample %>%
  mutate(crosslist_group = crosslist_code)

# Extract home subject — case-insensitive ("HIST home" and "HIST Home" both match)
sample <- sample %>%
  mutate(
    .xl_home_subj = ifelse(
      !is.na(xl_home_text) & grepl("^[A-Z]+ home ", xl_home_text, ignore.case = TRUE),
      sub("^([A-Z]+) home .*", "\\1", xl_home_text, ignore.case = TRUE),
      NA_character_
    )
  )

xl_primary_by_text <- sample %>%
  filter(!is.na(crosslist_group), !is.na(.xl_home_subj), subject == .xl_home_subj) %>%
  group_by(term, crosslist_group) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  pull(section_id)

xl_groups_needing_fallback <- sample %>%
  filter(!is.na(crosslist_group)) %>%
  group_by(term, crosslist_group) %>%
  summarize(has_text_primary = any(section_id %in% xl_primary_by_text), .groups = "drop") %>%
  filter(!has_text_primary) %>%
  select(term, crosslist_group)

xl_primary_by_enrl <- sample %>%
  semi_join(xl_groups_needing_fallback, by = c("term", "crosslist_group")) %>%
  group_by(term, crosslist_group) %>%
  arrange(desc(enrolled), subject, .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  pull(section_id)

sample <- sample %>%
  mutate(
    crosslist_primary = is.na(crosslist_group) |
      section_id %in% xl_primary_by_text |
      section_id %in% xl_primary_by_enrl
  )

split_groups_df <- sample %>%
  filter(!is.na(crosslist_group)) %>%
  distinct(term, crosslist_group, section_id, level) %>%
  group_by(term, crosslist_group) %>%
  summarize(
    .is_split = any(level %in% c("lower", "upper")) & any(level == "grad"),
    .groups = "drop"
  ) %>%
  filter(.is_split) %>%
  select(term, crosslist_group)

sample <- sample %>%
  left_join(split_groups_df %>% mutate(.is_split_flag = TRUE),
            by = c("term", "crosslist_group")) %>%
  mutate(is_split = coalesce(.is_split_flag, FALSE)) %>%
  select(-.is_split_flag, -.xl_home_subj)

# ── Helper ─────────────────────────────────────────────────────────────────────

pass  <- 0
fail  <- 0
fails <- character()

check <- function(label, condition) {
  if (isTRUE(condition)) {
    message("  ✓ ", label)
    pass <<- pass + 1
  } else {
    message("  ✗ FAIL: ", label)
    fail <<- fail + 1
    fails <<- c(fails, label)
  }
}

group_primary <- function(xl_code) {
  sample %>% filter(crosslist_group == xl_code, crosslist_primary) %>%
    distinct(CRN, subject, `CRSE#`)
}

group_rows <- function(xl_code) {
  sample %>% filter(crosslist_group == xl_code)
}


# =============================================================================
# SHORT_TEXT-based home detection
# =============================================================================

message("\n── SHORT_TEXT home detection ──────────────────────────────────────────────")

# Group IF: ENGL 324 (19 enrolled) vs FDMA 324 (2 enrolled)
# SHORT_TEXT = "FDMA home 202610" → FDMA is home despite lower enrollment.
# Enrollment-only logic would INCORRECTLY pick ENGL.
if_primary <- group_primary("IF")
check("IF: exactly one primary", nrow(if_primary) == 1)
check("IF: FDMA 324 is primary (SHORT_TEXT wins over enrollment)", if_primary$subject == "FDMA")

# Group SQ: AMST 370 (13 enrolled), HIST 396, NATV 450, WGSS 379 (3 each)
# SHORT_TEXT = "HIST home 202610" → HIST is home despite AMST's higher enrollment.
sq_primary <- group_primary("SQ")
check("SQ: exactly one primary", nrow(sq_primary) == 1)
check("SQ: HIST is primary (SHORT_TEXT wins over enrollment)", sq_primary$subject == "HIST")

# Group 3L: POLS 400, POLS 496, POLS 512 (0 enrolled each), GLNS 595 (9 enrolled)
# SHORT_TEXT = "POLS home 202610" → POLS is home despite GLNS having highest enrollment.
# Casing: "POLS home" (lowercase) — verify lowercase pattern works.
l3_primary <- group_primary("3L")
check("3L: exactly one primary", nrow(l3_primary) == 1)
check("3L: POLS is primary (SHORT_TEXT, lowercase 'home')", l3_primary$subject == "POLS")

# Group 13: GEOG 457, GEOG 557, GLNS 530
# SHORT_TEXT = "GEOG Home 202610" (capital H) → tests case-insensitive matching.
g13_primary <- group_primary("13")
check("13: exactly one primary", nrow(g13_primary) == 1)
check("13: GEOG is primary (SHORT_TEXT, capital 'Home')", g13_primary$subject == "GEOG")

# Group CJ: GEOG 499 (1 enrolled) vs UHON 301 (8 enrolled)
# SHORT_TEXT = "UHON home 202610" → UHON is home despite lower enrollment.
cj_primary <- group_primary("CJ")
check("CJ: exactly one primary", nrow(cj_primary) == 1)
check("CJ: UHON is primary (SHORT_TEXT wins over enrollment)", cj_primary$subject == "UHON")

# Group FW: 8-way XL. SHORT_TEXT = "ARTS home 202610" → ARTS section is primary.
fw_primary <- group_primary("FW")
check("FW: exactly one primary in 8-way XL", nrow(fw_primary) == 1)
check("FW: ARTS is primary", fw_primary$subject == "ARTS")

# Group S4: 10-way XL. SHORT_TEXT = "ARTS home 202610" → ARTS section is primary.
s4_primary <- group_primary("S4")
check("S4: exactly one primary in 10-way XL", nrow(s4_primary) == 1)
check("S4: ARTS is primary", s4_primary$subject == "ARTS")


# =============================================================================
# Enrollment fallback (no SHORT_TEXT)
# =============================================================================

message("\n── Enrollment fallback (no SHORT_TEXT) ────────────────────────────────────")

# Group IP: LA 402 (14 enrolled) vs LA 502 (1 enrolled). No SHORT_TEXT.
# Fallback: highest enrolled → LA 402 (undergrad).
ip_primary <- group_primary("IP")
check("IP: exactly one primary", nrow(ip_primary) == 1)
check("IP: LA 402 is primary (highest enrolled fallback)", ip_primary$`CRSE#` == "402")

# Group 2A: CRP 470 (0 enrolled) vs CRP 570 (7 enrolled). No SHORT_TEXT.
# Fallback: highest enrolled → CRP 570 (grad, more enrolled).
a2_primary <- group_primary("2A")
check("2A: exactly one primary", nrow(a2_primary) == 1)
check("2A: CRP 570 is primary (highest enrolled fallback)", a2_primary$`CRSE#` == "570")

# Group BC/OW/PD/ZN: MUS 560 vs MUSC 2170, both 0 enrolled. No SHORT_TEXT.
# Fallback: alphabetical by subject → MUS < MUSC → MUS is primary.
for (grp in c("BC", "OW", "PD", "ZN")) {
  p <- group_primary(grp)
  check(paste0(grp, ": exactly one primary"), nrow(p) == 1)
  check(paste0(grp, ": MUS is primary (alpha fallback, both 0 enrolled)"), p$subject == "MUS")
}

# Group ZJ: SPCD 411 (5/4 enrolled) vs SPCD 511 (9/2 enrolled). No SHORT_TEXT. 4 CRNs.
# Both subjects are SPCD; highest enrolled section should be primary.
zj_primary <- group_primary("ZJ")
check("ZJ: exactly one primary in 4-CRN same-dept group", nrow(zj_primary) == 1)
check("ZJ: SPCD 511 section CRN 61988 is primary (enrolled=9, highest)",
      zj_primary$CRN == "61988")

# Non-XL sections: all should be primary
non_xl <- sample %>% filter(is.na(crosslist_group))
check("Non-XL: all sections have crosslist_primary = TRUE",
      all(non_xl$crosslist_primary))


# =============================================================================
# Split-level detection
# =============================================================================

message("\n── Split-level detection ──────────────────────────────────────────────────")

# Group 13: GEOG 457 (upper) + GEOG 557, GLNS 530 (grad) → split
check("13: all sections flagged is_split",
      all(group_rows("13")$is_split))
check("13: original levels preserved (upper + grad)",
      setequal(unique(group_rows("13")$level), c("upper", "grad")))

# Group IP: LA 402 (upper) + LA 502 (grad) → split
check("IP: all sections flagged is_split",
      all(group_rows("IP")$is_split))
check("IP: original levels preserved",
      setequal(unique(group_rows("IP")$level), c("upper", "grad")))

# Group 2A: CRP 470 (upper) + CRP 570 (grad) → split
check("2A: all sections flagged is_split",
      all(group_rows("2A")$is_split))

# Group 3L: POLS 400, 496 (upper) + POLS 512, GLNS 595 (grad) → split
check("3L: all sections flagged is_split",
      all(group_rows("3L")$is_split))

# Group QZ: BIOL 430 (upper) + BIOL 530 (grad) → split
check("QZ: all sections flagged is_split",
      all(group_rows("QZ")$is_split))

# Group Y9: MUS 449 (upper) + MUS 549 (grad) → split
check("Y9: all sections flagged is_split",
      all(group_rows("Y9")$is_split))

# Group CJ: GEOG 499 (upper) + UHON 301 (lower) → both ≤499 → NOT split
check("CJ: not split (both sections ≤499)",
      all(!group_rows("CJ")$is_split))

# Group IF: ENGL 324 + FDMA 324 → both upper → not split
check("IF: not split (both sections upper)",
      all(!group_rows("IF")$is_split))

# Group SQ: AMST 370, HIST 396, NATV 450, WGSS 379 → all 300-level → not split
check("SQ: not split (all 300-level)",
      all(!group_rows("SQ")$is_split))

# Lab section in group 3D: EDUC 331L → crse_base=331 → "upper"; EDUC 531 → "grad" → split
check("3D: EDUC 331L + EDUC 531 detected as split (lab section crse_base strips 'L')",
      all(group_rows("3D")$is_split))


# =============================================================================
# Summary
# =============================================================================

message("\n══════════════════════════════════════════════════════")
message(sprintf("  Results: %d passed, %d failed", pass, fail))
if (fail > 0) {
  message("  Failed assertions:")
  for (f in fails) message("    - ", f)
  message("══════════════════════════════════════════════════════")
  quit(status = 1)
} else {
  message("  All assertions passed.")
  message("══════════════════════════════════════════════════════")
}
