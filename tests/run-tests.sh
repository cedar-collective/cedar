#!/bin/bash
# Wrapper script to run CEDAR tests
# Usage: ./run-tests.sh [options]
#
# Options:
#   --filtering   Run only filtering tests
#   --all         Run all tests (default)
#   --verbose     Show detailed output

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ "$1" == "--filtering" ]; then
    echo -e "${YELLOW}Running filtering tests only...${NC}"
    Rscript -e "testthat::test_file('testthat/test-filtering.R')"
elif [ "$1" == "--verbose" ]; then
    echo -e "${YELLOW}Running all tests (verbose)...${NC}"
    Rscript testthat.R
else
    echo -e "${YELLOW}Running all tests...${NC}"
    Rscript testthat.R 2>&1 | grep -A 100 "Results"
fi

echo -e "${GREEN}✓ Tests complete${NC}"
