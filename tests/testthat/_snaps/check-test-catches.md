# a break is caught only when a test fails with it in place, and the tree is never edited

    Code
      writeLines(run$report[!quoted])
    Output
      5 breaks against 1 test file, in a copy of the tree. The checkout is not edited.
      
      As the tree stands: test-sums.R passes (2 tests).
      
      1. add_one adds two  [R/sums.R]
         CAUGHT by test-sums.R:
           add_one adds one
      
      2. add_one stops with an error  [R/sums.R]
         CAUGHT by test-sums.R:
           add_one adds one
      
      3. double triples  [R/products.R]
         NOT CAUGHT: test-sums.R passes with the break in place.
      
      4. settle never returns  [R/sums.R]
         TIMED OUT: test-sums.R ran past 5 s with the break in place. That is not a catch.
      
      5. the file no longer parses  [R/products.R]
         STOPPED: test-sums.R could not run with the break in place, so no test is shown to hold it.
      
      2 of 5 breaks caught. Not caught: 3, 4, 5.

# breaks that could prove nothing are refused before a test runs

    Code
      writeLines(c(unlist(lapply(refused, `[[`, "said"), use.names = FALSE), already$
        said))
    Output
      check-test-catches: break 1 (text the file does not hold): `old` is not in R/sums.R
      check-test-catches: break 1 (text the file holds twice): `old` is in R/sums.R 2 times; write enough of the line that it is there once
      check-test-catches: break 1 (a test file that is not there): no test file tests/testthat/test-products.R
      check-test-catches: test-sums.R fails as the tree stands, so a failure under a break proves nothing:
        add_one adds one

