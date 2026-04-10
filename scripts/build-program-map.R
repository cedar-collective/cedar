# build-program-map.R — STUB
#
# This script has been superseded. program_map.qs is now generated automatically
# by transform_to_cedar() at the start of each pipeline run, using:
#
#   - R/lists/program_code_maps.R  — manual override maps (premaj_canon, xvar_explicit, etc.)
#   - R/data-parsers/transform-to-cedar.R::generate_program_map() — parsing logic
#
# To regenerate program_map.qs, run the normal transform pipeline:
#   Rscript scripts/run-transform.R
#
# Or call transform_to_cedar() directly from R:
#   transform_to_cedar(data_dir = "path/to/data", tables = "programs")
#
# To edit the override maps (e.g. add a new pre-major code), edit:
#   R/lists/program_code_maps.R

stop("build-program-map.R is no longer used. See comments above.")
