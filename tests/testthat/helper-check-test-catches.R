# What the tests in test-check-test-catches.R share: a three-function tree
# written to a temporary directory, breaks of it, and the script run on both.

# Path -> lines. Like the repository in the ways that matter here: the code is
# in more than one file, the set-up file sources it, and the test file holds
# test_that() blocks.
tiny_tree <- list(
  "R/sums.R" = c("add_one <- function(x) x + 1",
                 "settle <- function(x) x"),
  "R/products.R" = "double <- function(x) x * 2",
  "tests/testthat/setup.R" = c('source("../../R/sums.R")',
                               'source("../../R/products.R")'),
  "tests/testthat/test-sums.R" = c('test_that("add_one adds one", {',
                                   "  expect_equal(add_one(1), 2)",
                                   "})",
                                   "",
                                   'test_that("settle returns what it was given", {',
                                   "  expect_equal(settle(3), 3)",
                                   "})")
)

# One of each outcome. A test that stops with an error holds a break as one
# that fails does. No test calls double(), so nothing holds it, and it is in
# the other file: a break of add_one() left in the copy would be read as a
# catch of double()'s. settle() is called, and its break never returns.
tiny_breaks <- list(
  adds_two = list(name = "add_one adds two", file = "R/sums.R",
                  old = "x + 1", new = "x + 2", tests = "test-sums.R"),
  stops = list(name = "add_one stops with an error", file = "R/sums.R",
               old = "x + 1", new = 'stop("nothing to add")', tests = "test-sums.R"),
  triples = list(name = "double triples", file = "R/products.R",
                 old = "x * 2", new = "x * 3", tests = "test-sums.R"),
  never_settles = list(name = "settle never returns", file = "R/sums.R",
                       old = "settle <- function(x) x", new = "settle <- function(x) repeat {}",
                       tests = "test-sums.R", timeout = 5L),
  does_not_parse = list(name = "the file no longer parses", file = "R/products.R",
                        old = "x * 2", new = "x * * 2", tests = "test-sums.R"),
  not_there = list(name = "text the file does not hold", file = "R/sums.R",
                   old = "x + 10", new = "x + 2", tests = "test-sums.R"),
  there_twice = list(name = "text the file holds twice", file = "R/sums.R",
                     old = "function(x)", new = "function(y)", tests = "test-sums.R"),
  no_such_test = list(name = "a test file that is not there", file = "R/sums.R",
                      old = "x + 1", new = "x + 2", tests = "test-products.R")
)

write_tiny_tree <- function(root, files) {
  for (path in names(files)) {
    dir.create(dirname(file.path(root, path)), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[path]], file.path(root, path))
  }
  invisible(root)
}

# Every file under `root` and its checksum: the same before and after a run
# means the run edited nothing and left nothing behind.
tree_checksums <- function(root) {
  files <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  stats::setNames(unname(tools::md5sum(file.path(root, files))), files)
}

# A breaks file as a person writes one, and gets wrong: the lines of a block
# of text indented by different amounts, where `|-` takes the first line's.
breaks_file_with_a_ragged_block <- c(
  "- name: a block whose lines are indented by different amounts",
  "  file: R/sums.R",
  "  old: |-",
  "      add_one <- function(x) {",
  "    }",
  "  new: x",
  "  tests: [test-sums.R]"
)

# scripts/check-test-catches.R on the tree at `root`: its exit status, the
# report it printed, and what it said on stderr. `breaks` is a list of
# entries, or the lines of a breaks file. A minute is the limit for a run
# here; a break that carries its own limit keeps it.
run_check_test_catches <- function(root, breaks) {
  work <- tempfile("catches-run-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  if (is.character(breaks)) {
    writeLines(breaks, file.path(work, "breaks.yml"))
  } else {
    yaml::write_yaml(unname(breaks), file.path(work, "breaks.yml"))
  }
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    c("--vanilla", shQuote(file.path(cedar_base_dir, "scripts", "check-test-catches.R")),
                      shQuote(file.path(work, "breaks.yml")), "--root", shQuote(root), "--timeout", "60"),
                    stdout = file.path(work, "out"), stderr = file.path(work, "err"))
  list(status = status, report = readLines(file.path(work, "out")), said = readLines(file.path(work, "err")))
}
