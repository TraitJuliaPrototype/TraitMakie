#!/bin/bash
# Runs scripts/session.jl in a real REPL on a pseudo-terminal (`script`), as a user would type it,
# and reports its CHECK lines. A correctness check, not a timing. One Julia job at a time. It passes only
# when every check prints ok and the prompt shows only the expected errors.
#
#     scripts/session.sh            # JULIA=<julia binary>, LOCK=<lock file> to override
set -u
cd "$(dirname "$0")/.."
ROOT=${TW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
J=${JULIA:-$ROOT/julia-1.13/julia}
LOCK=${LOCK:-/tmp/claude-1000/julia-review.lock}
OUT=${TMPDIR:-/tmp}/traitmakie_session.out
export JULIA_PKG_OFFLINE=true JULIA_TW_VIEWCACHE=0 LINES=40 COLUMNS=140
flock "$LOCK" nice -n 19 timeout 1800 script -qec "$J --startup-file=no -i --banner=no --project=scripts/env" /dev/null \
    < <(cat scripts/session.jl; echo 'exit()') > "$OUT" 2>&1   # exit() ends the REPL after the last line
checks() { tr -d '\r' < "$OUT" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -ao 'CHECK .* \(ok\|FAIL\)$'; }
errors() { tr -d '\r' < "$OUT" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -a '^ERROR'; }
# what the session must print: one CHECK line per `_ok("…", …)` call, and one ERROR per line marked
# `# ERROR expected` (the deliberate mistakes). A step that raises where it should not, or a check that
# never prints (the session went on past an error), fails the session.
want=$(grep -c '_ok("' scripts/session.jl); want_err=$(grep -c '# ERROR expected$' scripts/session.jl)
checks
echo "errors shown at the prompt (expected: $want_err, the lines marked # ERROR expected):"; errors | cut -c1-200
n=$(checks | grep -c ' ok$'); bad=$(checks | grep -c 'FAIL$'); nerr=$(errors | wc -l)
echo "session: $n of $want checks ok, $bad failed, $((want - n - bad)) not printed; $nerr errors, $want_err expected (transcript: $OUT)"
[ "$bad" = 0 ] && [ "$n" = "$want" ] && [ "$nerr" = "$want_err" ] && checks | tail -1 | grep -q '^CHECK session done ok$'
