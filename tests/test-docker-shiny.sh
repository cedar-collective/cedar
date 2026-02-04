#!/bin/bash

# ==============================================================================
# Docker Shiny Full Test Script
# ==============================================================================
# Comprehensive test including HTTP endpoint checks
#
# Usage:
#   ./test-docker-shiny-full.sh [options]
#
# Options:
#   --no-build    Skip docker rebuild (just restart)
#   --follow      Keep following logs after startup
#   --timeout N   Seconds to wait for app startup (default: 45)
#   --check-url   Test HTTP endpoint after startup
#
# What it does:
#   1. Stops existing container
#   2. Rebuilds container (unless --no-build)
#   3. Starts container in detached mode
#   4. Monitors logs for startup completion or errors
#   5. Optionally tests HTTP endpoint
#   6. Extracts and displays all errors found
# ==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
DO_BUILD=true
FOLLOW_LOGS=false
CHECK_URL=false
TIMEOUT=45
APP_URL="http://localhost:3838/cedar/"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-build)
      DO_BUILD=false
      shift
      ;;
    --follow)
      FOLLOW_LOGS=true
      shift
      ;;
    --check-url)
      CHECK_URL=true
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}Cedar Shiny Docker Full Test${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# Step 1: Stop existing container
echo -e "${YELLOW}[1/6] Stopping existing container...${NC}"
docker compose down 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Container stopped${NC}"
echo ""

# Step 2: Build container (if requested)
if [ "$DO_BUILD" = true ]; then
  echo -e "${YELLOW}[2/6] Building Docker container...${NC}"
  echo -e "${CYAN}Build progress (showing key steps):${NC}"
  echo ""

  # Show build output live, filtering for key steps
  docker compose build 2>&1 | grep --line-buffered -E "Step [0-9]+/[0-9]+|CACHED|RUN|COPY|FROM|naming to|Successfully built|writing image" || docker compose build

  BUILD_EXIT_CODE=${PIPESTATUS[0]}
  echo ""

  if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Build complete${NC}"
  else
    echo -e "${RED}✗ Build failed with exit code $BUILD_EXIT_CODE${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}[2/6] Skipping build (--no-build specified)${NC}"
fi
echo ""

# Step 3: Start container
echo -e "${YELLOW}[3/6] Starting container...${NC}"
docker compose up -d
sleep 3
CONTAINER_NAME="cedar-shiny"
echo -e "${GREEN}✓ Container started (${CONTAINER_NAME})${NC}"
echo ""

# Step 4: Monitor logs for startup completion or errors
echo -e "${YELLOW}[4/6] Monitoring startup logs (timeout: ${TIMEOUT}s)...${NC}"
echo -e "${BLUE}-------------------------------------------------------------------${NC}"

# Create temporary files for log analysis
LOG_FILE=$(mktemp)
ERROR_FILE=$(mktemp)
CEDAR_ERRORS=$(mktemp)
R_ERRORS=$(mktemp)

# Capture logs in background using container name directly
docker logs -f "$CONTAINER_NAME" > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Monitor for completion or timeout
START_TIME=$(date +%s)
SUCCESS=false
ERROR_FOUND=false
STARTUP_COMPLETE=false

echo -e "${CYAN}Watching for startup signals...${NC}"

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  # Check for timeout
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}⏱ Timeout reached (${TIMEOUT}s)${NC}"
    break
  fi

  # Check for successful startup indicators
  if grep -q "Listening on http" "$LOG_FILE" 2>/dev/null; then
    if [ "$STARTUP_COMPLETE" = false ]; then
      echo -e "${GREEN}✓ Shiny server started${NC}"
      STARTUP_COMPLETE=true
    fi
  fi

  # Check for CEDAR validation success
  if grep -q "All CEDAR data validated successfully\|✅ All CEDAR data validated successfully" "$LOG_FILE" 2>/dev/null; then
    if [ "$SUCCESS" = false ]; then
      echo -e "${GREEN}✓ CEDAR data validated${NC}"
      SUCCESS=true
    fi
  fi

  # Extract CEDAR-specific errors
  grep -E "\[global\.R\].*error|validation failed|missing required.*columns" "$LOG_FILE" 2>/dev/null > "$CEDAR_ERRORS" || true

  # Extract R errors
  grep -iE "^Error|Error in|Error:|Warning:" "$LOG_FILE" 2>/dev/null > "$R_ERRORS" || true

  # Check if we found errors
  if [ -s "$CEDAR_ERRORS" ] || [ -s "$R_ERRORS" ]; then
    ERROR_FOUND=true
  fi

  # Exit if we have success and enough time has passed
  if [ "$SUCCESS" = true ] && [ $ELAPSED -ge 15 ]; then
    break
  fi

  sleep 1
  echo -n "."
done

echo ""

# Stop log capture
kill $LOG_PID 2>/dev/null || true

echo -e "${BLUE}-------------------------------------------------------------------${NC}"
echo ""

# Step 5: Analyze results
echo -e "${YELLOW}[5/6] Analyzing Results${NC}"
echo -e "${BLUE}===================================================================${NC}"

if [ "$ERROR_FOUND" = true ]; then
  echo -e "${RED}❌ ERRORS DETECTED during startup${NC}"
  echo ""

  if [ -s "$CEDAR_ERRORS" ]; then
    echo -e "${RED}CEDAR Data Validation Errors:${NC}"
    echo -e "${RED}-------------------------------------------------------------------${NC}"
    cat "$CEDAR_ERRORS"
    echo -e "${RED}-------------------------------------------------------------------${NC}"
    echo ""
  fi

  if [ -s "$R_ERRORS" ]; then
    echo -e "${RED}R Errors/Warnings:${NC}"
    echo -e "${RED}-------------------------------------------------------------------${NC}"
    cat "$R_ERRORS" | head -30
    echo -e "${RED}-------------------------------------------------------------------${NC}"
    echo ""
  fi

  echo -e "${YELLOW}Recent log context:${NC}"
  tail -40 "$LOG_FILE"

elif [ "$SUCCESS" = true ]; then
  echo -e "${GREEN}✅ SUCCESS - App started and CEDAR data validated!${NC}"
  echo ""

  # Show key startup messages
  echo -e "${BLUE}Startup Summary:${NC}"
  grep -E "cedar_sections:|cedar_students:|cedar_programs:|cedar_degrees:|cedar_faculty:" "$LOG_FILE" 2>/dev/null || echo "  (row counts not found)"
  echo ""

else
  echo -e "${YELLOW}⚠ UNCLEAR STATUS - Check logs below${NC}"
  echo ""
  tail -40 "$LOG_FILE"
fi

# Step 6: Test HTTP endpoint (if requested)
if [ "$CHECK_URL" = true ]; then
  echo ""
  echo -e "${YELLOW}[6/6] Testing HTTP Endpoint${NC}"
  echo -e "${BLUE}===================================================================${NC}"

  echo -e "${CYAN}Testing: ${APP_URL}${NC}"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL" 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ HTTP 200 OK - App is responding${NC}"
  elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${RED}❌ Connection failed - Container may not be running${NC}"
  else
    echo -e "${YELLOW}⚠ HTTP $HTTP_CODE - Unexpected response${NC}"
  fi

  # Try to fetch and check for errors in HTML
  HTML_OUTPUT=$(mktemp)
  curl -s "$APP_URL" > "$HTML_OUTPUT" 2>/dev/null || true

  if grep -qi "error\|exception\|stack trace" "$HTML_OUTPUT" 2>/dev/null; then
    echo -e "${RED}⚠ Error messages found in HTML response${NC}"
    grep -i "error\|exception" "$HTML_OUTPUT" | head -5
  fi

  rm -f "$HTML_OUTPUT"
else
  echo -e "${YELLOW}[6/6] Skipping HTTP endpoint test (use --check-url to enable)${NC}"
fi

echo -e "${BLUE}===================================================================${NC}"
echo ""

# Summary - check full logs for validation (in case we missed startup window)
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}-------------------------------------------------------------------${NC}"
echo -e "Container Status:  $(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo 'Unknown')"
echo -e "App URL:           ${APP_URL}"

# Double-check CEDAR validation in full log history
if [ "$SUCCESS" = false ]; then
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "All CEDAR data validated successfully\|✅ All CEDAR data validated successfully"; then
    SUCCESS=true
  fi
fi

echo -e "CEDAR Validated:   $([ "$SUCCESS" = true ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
echo -e "Errors Found:      $([ "$ERROR_FOUND" = true ] && echo -e "${RED}Yes${NC}" || echo -e "${GREEN}No${NC}")"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# Cleanup temp files
rm -f "$LOG_FILE" "$ERROR_FILE" "$CEDAR_ERRORS" "$R_ERRORS"

# Option to follow logs
if [ "$FOLLOW_LOGS" = true ]; then
  echo -e "${BLUE}Following logs (Ctrl+C to exit)...${NC}"
  echo ""
  docker compose logs -f
fi

# Exit with appropriate code
if [ "$SUCCESS" = true ] && [ "$ERROR_FOUND" = false ]; then
  echo -e "${GREEN}✅ All checks passed!${NC}"
  exit 0
elif [ "$SUCCESS" = true ] && [ "$ERROR_FOUND" = true ]; then
  echo -e "${YELLOW}⚠ Partial success - app started but errors detected${NC}"
  exit 1
else
  echo -e "${RED}❌ Test failed${NC}"
  exit 1
fi
