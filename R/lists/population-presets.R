# CEDAR-PLATFORM: named population groups from institution/<id>/population_groups.csv
# population-presets.R — Named population groups, shared across CEDAR.
#
# These are NOT specific to any one tab. Pathways pre-populates its program
# selectizeInput from them; the enrollment-projection growth scenario resolves
# them to Banner major codes. Anything that needs "health professions" to mean
# one thing reads this registry, so the definition cannot drift between tabs.
# Which groups exist, and which programs each names, is the institution's, in
# population_groups.csv (read and validated here at load). This file names no
# group and no program.
#
# Groups are declared as PROGRAM NAMES, not Banner codes, and resolved to codes
# against cedar_programs by population_group_major_codes() in
# R/branches/population.R. Names are the right declaration because a pre-major
# usually carries the same program_name as the major it leads to (FRAD and RADS
# are both "Radiologic Sciences"), so declared and pre-major students resolve
# together without a hand-maintained code list going stale every time Banner
# adds a variant. Where a pre-major's name has drifted from its major's, the
# file lists BOTH spellings; population_group_audit() reports near-miss names
# precisely so that drift is found rather than silently dropped (ISSUES.md I7).
#
# CEDAR_POPULATION_GROUPS: a named list in file order, one entry per group:
#   programs    — character vector of program_name values
#   description — one-line description (shown as a selectize option label)
# CEDAR_POPULATION_GROUP_DEFAULTS: the group preselected on each surface in
#   CEDAR_POPULATION_GROUP_SURFACES that the file names one for.

.cedar_population_groups <- validate_population_groups(read_institution_file("population_groups"))

CEDAR_POPULATION_GROUPS <- local({
  ids <- unique(.cedar_population_groups$group)
  stats::setNames(lapply(ids, function(id) {
    rows <- .cedar_population_groups[.cedar_population_groups$group == id, ]
    list(programs = unique(rows$program_name), description = rows$description[[1]])
  }), ids)
})

CEDAR_POPULATION_GROUP_DEFAULTS <- local({
  per_group <- .cedar_population_groups[!duplicated(.cedar_population_groups$group), ]
  surfaces <- strsplit(per_group$default_for, "|", fixed = TRUE)
  out <- stats::setNames(rep(per_group$group, lengths(surfaces)), unlist(surfaces))
  out[names(out) %in% CEDAR_POPULATION_GROUP_SURFACES]
})
