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
# Groups list declared PROGRAM CODES from programs.csv, never names: one Banner
# name covers several programs (ISSUES I62, M56). A group's pre-majors join
# through programs.csv's leads_to (FRAD leads to RADS) and a renamed program's
# codes through code_history.csv, both in population_group_major_codes()
# (R/branches/population.R). A new Banner variant joins no group until the
# file lists it; population_group_audit() reports one that shares a group
# program's name, and a pre-major with no leads_to, so it is found rather than
# silently dropped (ISSUES.md I7).
#
# CEDAR_POPULATION_GROUPS: a named list in file order, one entry per group:
#   codes       — character vector of declared program codes
#   description — one-line description (shown as a selectize option label)
# CEDAR_POPULATION_GROUP_DEFAULTS: the group preselected on each surface in
#   CEDAR_POPULATION_GROUP_SURFACES that the file names one for.

.cedar_population_groups <- validate_population_groups(read_institution_file("population_groups"),
                                                       cedar_institution_files$programs)

CEDAR_POPULATION_GROUPS <- local({
  ids <- unique(.cedar_population_groups$group)
  stats::setNames(lapply(ids, function(id) {
    rows <- .cedar_population_groups[.cedar_population_groups$group == id, ]
    list(codes = unique(rows$program_code), description = rows$description[[1]])
  }), ids)
})

CEDAR_POPULATION_GROUP_DEFAULTS <- local({
  per_group <- .cedar_population_groups[!duplicated(.cedar_population_groups$group), ]
  surfaces <- strsplit(per_group$default_for, "|", fixed = TRUE)
  out <- stats::setNames(rep(per_group$group, lengths(surfaces)), unlist(surfaces))
  out[names(out) %in% CEDAR_POPULATION_GROUP_SURFACES]
})
