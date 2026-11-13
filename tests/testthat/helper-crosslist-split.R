# What the tests in test-crosslist-split.R share: builders, option lists, constants.

# Derived view used throughout — mirrors how production code sees XL sections
xl_sections <- function() test_sections %>% filter(!is.na(crosslist_group))
