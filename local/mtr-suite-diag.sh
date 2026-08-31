#!/bin/bash
#
# Summarize one dynamic-pipeline suite run for the end-of-run diagnostics table.
# (Used by jenkins/pipeline-dynamic.groovy; kept as a script so the awk/regex parsing
# doesn't have to be escaped through a Groovy here-string.)
#
# Usage:
#   mtr-suite-diag.sh <walltime_file> <mtr_log_file>
#
# Prints exactly one line:
#   <spent_seconds>|<num_timeouts>|<num_failures>|<bad_tests>
#
#   spent_seconds   - sum of cumulative testcase-seconds (the "Spent X of Y ..." X value)
#                     across this run's sub-invocations (nobig + big). This is the stable
#                     work metric; wall time depends on how much parallelism the worker got.
#   num_timeouts    - count of "timeout after" lines (hung tests killed by --testcase-timeout)
#   num_failures    - count of "[ fail ]" result lines
#   bad_tests       - space-separated names of every failed/timed-out test, in the order
#                     MTR reported them (one name per "[ fail ]" line, so the name count
#                     matches num_failures), or empty. Test names never contain spaces or
#                     "|", so this stays parseable as a single field.
#
# All fields default to 0 / empty when the inputs are missing, so the caller can rely on
# the "a|b|c|d" shape.

set +e

wt="$1"
log="$2"

spent=0
if [[ -f "${wt}" ]]; then
    spent=$(grep -oE 'Spent [0-9.]+' "${wt}" | awk '{s += $2} END {printf "%d", s + 0}')
fi

timeouts=0
fails=0
bad=""
if [[ -f "${log}" ]]; then
    timeouts=$(grep -c 'timeout after' "${log}")
    fails=$(grep -cE '\[ fail \]' "${log}")
    # MTR result line: "<date> <time> [ NN%] <test> wN [ fail ] ...". The test name is the
    # field right after the "...%]" progress marker (robust to "[ 99%]" vs "[100%]").
    # "?" keeps one name per fail line if a line ever lacks the marker, so the name count
    # stays equal to ${fails}. paste joins them into one space-separated field.
    bad=$(grep -E '\[ fail \]' "${log}" \
          | awk '{name = "?"
                  for (i = 1; i <= NF; i++) if ($i ~ /%\]$/) { name = $(i + 1); break }
                  print name}' \
          | paste -sd' ' -)
fi

echo "${spent}|${timeouts}|${fails}|${bad}"
