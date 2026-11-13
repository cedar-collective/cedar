# What the tests in test-dept-report-plots.R share: builders, option lists, constants.

is_plotly <- function(x) inherits(x, "plotly")

any_plotly <- function(plot_list) any(sapply(plot_list, is_plotly))

# Use plotly_build() to force trace evaluation before inspecting internals.
# Without it, x/y/type fields may be unevaluated formulas or NULL.
built_data <- function(p) plotly_build(p)$x$data

trace_types <- function(p) unique(sapply(built_data(p), function(t) t$type))

all_y_values <- function(p) unlist(lapply(built_data(p), function(t) t$y))
