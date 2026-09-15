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
#   <spent_seconds>|<num_timeouts>|<num_failures>|<bad_tests>|<num_flaky>|<flaky_tests>
#
#   spent_seconds   - sum of cumulative testcase-seconds (the "Spent X of Y ..." X value)
#                     across this run's sub-invocations (nobig + big). This is the stable
#                     work metric; wall time depends on how much parallelism the worker got.
#   num_timeouts    - count of "timeout after" lines (hung tests killed by --testcase-timeout)
#   num_failures    - number of distinct hard-failing tests, i.e. tests that were still
#                     failing after MTR used up their retries
#   bad_tests       - space-separated names of those tests, or empty
#   num_flaky       - number of distinct tests that failed and then passed on a retry
#                     (MTR's "unstable" tests: they do not hard-fail the run)
#   flaky_tests     - space-separated names of those tests, or empty
#
# Hard vs flaky comes from MTR's own end-of-run verdict, which is printed once per
# sub-invocation:
#   "Failing test(s): a.b c.d"                        -> hard failures
#   "Unstable test(s)(failures/attempts): a.b(1/3)"   -> failed, then passed on a retry
# Counting "[ fail ]" lines instead (what this script used to do) marks a suite failed for a
# test MTR itself let pass, e.g. perfschema|nobig in build 9 of
# percona-server-8.0-VALGRIND-pipeline-dynamic: "FAIL x1: perfschema.idx_compare_threads"
# for a test whose only failure was recovered by the retry. "[ fail ]" lines are still used
# as a backstop for tests MTR never got to report on (a run killed before its summary): any
# failed test that appears in neither verdict list counts as a hard failure.
#
# Test names never contain spaces or "|", so the name fields stay parseable, and the two
# lists are disjoint (a test that hard-fails in one sub-invocation is never also reported as
# flaky). Names keep the order MTR reported them.
#
# All fields default to 0 / empty when the inputs are missing, so the caller can rely on
# the "a|b|c|d|e|f" shape.

set +e

wt="$1"
log="$2"

spent=0
if [[ -f "${wt}" ]]; then
    spent=$(grep -oE 'Spent [0-9.]+' "${wt}" | awk '{s += $2} END {printf "%d", s + 0}')
fi

rest='0|0||0|'
if [[ -f "${log}" ]]; then
    rest=$(awk '
        # MTR verdict: the tests that were still failing when their retries ran out.
        /Failing test\(s\):/ {
            s = $0; sub(/.*Failing test\(s\):[ \t]*/, "", s)
            n = split(s, a, /[ \t]+/)
            for (i = 1; i <= n; i++)
                if (a[i] != "" && !(a[i] in hard)) { hard[a[i]] = 1; hord[++hn] = a[i] }
            next
        }
        # MTR verdict: the tests that failed but passed on a retry ("(failures/attempts)").
        /Unstable test\(s\)\(failures\/attempts\):/ {
            s = $0; sub(/.*Unstable test\(s\)\(failures\/attempts\):[ \t]*/, "", s)
            n = split(s, a, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                t = a[i]; sub(/\([0-9]+\/[0-9]+\)$/, "", t)
                if (t != "" && !(t in unst)) { unst[t] = 1; uord[++un] = t }
            }
            next
        }
        # Result line: "<date> <time> [ NN%] <test> wN [ fail ] ...". The test name is the
        # field right after the "...%]" progress marker (robust to "[ 99%]" vs "[100%]").
        # Retries print "[ retry-fail ]", so this sees each test at most once per
        # sub-invocation. "?" keeps the test represented if a line lacks the marker.
        /\[ fail \]/ {
            name = "?"
            for (i = 1; i <= NF; i++) if ($i ~ /%\]$/) { name = $(i + 1); break }
            if (!(name in seen)) { seen[name] = 1; ford[++fn] = name }
        }
        /timeout after/ { to++ }
        END {
            bad = ""; nbad = 0
            for (i = 1; i <= hn; i++) bad = bad (nbad++ ? " " : "") hord[i]
            # Backstop: a test that failed but appears in neither verdict list (MTR was
            # killed before printing its summary) is treated as a hard failure.
            for (i = 1; i <= fn; i++)
                if (!(ford[i] in hard) && !(ford[i] in unst))
                    bad = bad (nbad++ ? " " : "") ford[i]
            fky = ""; nfky = 0
            for (i = 1; i <= un; i++)
                if (!(uord[i] in hard)) fky = fky (nfky++ ? " " : "") uord[i]
            printf "%d|%d|%s|%d|%s", to + 0, nbad, bad, nfky, fky
        }' "${log}")
fi

echo "${spent}|${rest}"
