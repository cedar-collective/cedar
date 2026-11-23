#!/usr/bin/env bash
#
# report-registry.sh — the MyReports reports the shell scripts know, in one table.
#
# Sourced by update-data.sh and restart-cedar.sh; nothing here runs on its own.
# R/data-parsers/report-specs.R holds the same four facts for parse-data.R
# (filename_sig, stage, daily), and test-data-update-pipeline.R fails when the
# two disagree. mrgather keeps the codes in its own list (REPORT_HANDLERS in
# mrgather.js) and refuses a code it does not have.
#
# Adding a report: docs/developers/data-transformation-myreports.md,
# "Adding a MyReports report".
#
#   code       what is typed on the command line
#   signature  text every download's name carries; a file is today's when its
#              name holds the signature and today's date
#   stage      the transform-to-cedar.R --tables stage built from the report
#   schedule   daily = fetched when no report is named (the scheduled refresh);
#              named = fetched only when asked for. A report production
#              mrgather cannot fetch must be `named`: a requested report with
#              no file from today fails the fetch (ISSUES.md I43).
#   label      one line for the usage text
#
# code|signature|stage|schedule|label
CEDAR_REPORT_REGISTRY=(
    "desr|Department_Enrollment_Status|sections|daily|Department Enrollment Status Report (sections)"
    "deg|Graduates_and_Pending_Graduates|degrees|daily|Graduates and Pending Graduates (degrees)"
    "as|Academic_Study_Detail_Guided|programs|daily|Academic Study Detail (programs and majors)"
    "cl|Class_List_Guided_Adhoc|students|daily|Class List (registrations)"
    "aa|S_Admissions_Applicants_Detail|applicants|named|Admissions Applicants Detail (applicants)"
    "holds|S_Student_Holds|holds|named|Student Holds (every hold of the term's students)"
)

# One field of a report's row: report_field CODE N (2 signature, 3 stage,
# 4 schedule, 5 label). Returns 1, printing nothing, for a code not listed.
report_field() {
    local code row
    code="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    for row in "${CEDAR_REPORT_REGISTRY[@]}"; do
        if [[ "${row%%|*}" == "$code" ]]; then
            echo "$row" | cut -d'|' -f"$2"
            return 0
        fi
    done
    return 1
}

report_is_known()      { report_field "$1" 1 > /dev/null; }
report_filename_sig()  { report_field "$1" 2; }
report_stage()         { report_field "$1" 3; }
report_label()         { report_field "$1" 5; }

# Every code, in the table's order, on one line.
report_codes() {
    local row codes=()
    for row in "${CEDAR_REPORT_REGISTRY[@]}"; do codes+=("${row%%|*}"); done
    echo "${codes[*]}"
}

# The codes fetched when no report is named.
report_daily_codes() {
    local row codes=()
    for row in "${CEDAR_REPORT_REGISTRY[@]}"; do
        [[ "$(echo "$row" | cut -d'|' -f4)" == "daily" ]] && codes+=("${row%%|*}")
    done
    echo "${codes[*]}"
}

# The usage text's list: one indented line per report.
report_usage_lines() {
    local row code schedule
    for row in "${CEDAR_REPORT_REGISTRY[@]}"; do
        code="${row%%|*}"
        schedule="$(echo "$row" | cut -d'|' -f4)"
        printf '  %-6s %s%s\n' "$code" "$(echo "$row" | cut -d'|' -f5)" \
            "$([[ "$schedule" == "named" ]] && echo " — only when named")"
    done
}
