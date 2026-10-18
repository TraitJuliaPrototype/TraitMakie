#!/bin/bash
# Runs scripts/session.jl in a real REPL on a pseudo-terminal (`script`), as a user would type it,
# and reports its CHECK lines. A correctness check, not a timing. One Julia job at a time.
#
#     scripts/session.sh            # JULIA=<julia binary>, LOCK=<lock file> to override
set -u
cd "$(dirname "$0")/.."
ROOT=/home/hellmann/Repos/julia-trait-bound
J=${JULIA:-$ROOT/julia-1.13/julia}
LOCK=${LOCK:-/tmp/claude-1000/julia-review.lock}
OUT=${TMPDIR:-/tmp}/traitmakie_session.out
export JULIA_PKG_OFFLINE=true JULIA_TW_VIEWCACHE=0 LINES=40 COLUMNS=140
flock "$LOCK" nice -n 19 timeout 1800 script -qec "$J --startup-file=no -i --banner=no --project=scripts/env" /dev/null \
    < scripts/session.jl > "$OUT" 2>&1
checks() { tr -d '\r' < "$OUT" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -ao 'CHECK .* \(ok\|FAIL\)$'; }
errors() { tr -d '\r' < "$OUT" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -a '^ERROR'; }
checks
echo "errors shown at the prompt (expected: the deliberate mistakes):"; errors | cut -c1-200
n=$(checks | grep -c ' ok$'); bad=$(checks | grep -c 'FAIL$')
echo "session: $n checks ok, $bad failed (transcript: $OUT)"
[ "$bad" = 0 ] && checks | grep -q '^CHECK session done ok'
