# What the tests in test-courses.R share: builders, option lists, constants.

demo_files <- function() read_institution_mappings(cedar_institution_dir(cedar_base_dir, "demo"))

# The demo institution's files, whichever institution load_funcs() read.
demo_dims <- function() build_cedar_dims(demo_files())
