#!/usr/bin/env bash
# Probe: hooks run under `set -euo pipefail`. `echo "$BIG" | grep -q` makes grep exit on the first
# match while echo is still writing; echo gets SIGPIPE, the pipeline returns 141, and `if` reads that
# as "no match". Over the pipe buffer (~64KB) a hook then mis-judges the file.
# Fixed by here-strings: `grep -q ... <<< "$BIG"`.
#
# Usage: run-probe.sh   (exit 0 = all pass, 1 = a hook mis-judged a large file)
set -u
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)"
FAIL=0

# 1. Static: no `<producer> "$VAR" | grep -q...` left in any hook (the pattern itself is the defect).
#    Producers: echo / printf (builtins writing a variable). A mid-pipeline `| head -n 1 | grep -q`
#    on such a producer is the same defect, so the producer only has to start the pipeline.
HITS=$(grep -nE '(echo|printf)( +-[a-zA-Z]+)* +(.[^|]*)?"\$[{A-Za-z_0-9@#]+[^|]*\|( *head[^|]*\|)? *grep +-[a-zA-Z]*q' "$HOOKS_DIR"/*.sh || true)
if [ -n "$HITS" ]; then
    echo "FAIL static: producer-pipe-grep -q still present in $(echo "$HITS" | wc -l | tr -d ' ') places"
    echo "$HITS" | cut -c1-160
    FAIL=1
else
    echo "PASS static: no echo/printf-pipe-grep -q in hooks"
fi

# 1b. Static: in a hook that enables pipefail, `X=$(... | head -N)` without `|| true` dies with 141 once the
#     producer writes more than the pipe buffer. (Hooks without pipefail are unaffected; echo lines are text.)
HEAD_HITS=""
for f in "$HOOKS_DIR"/*.sh; do
    grep -qE '^set -[a-z]*o pipefail|^set -[a-z]*e[a-z]* *$|set -euo pipefail' "$f" || continue
    H=$(grep -nE '=\$\(.*\| *head( |\))' "$f" | grep -vE '\|\| *true|^[0-9]+: *echo' || true)
    [ -n "$H" ] && HEAD_HITS+="${f##*/}: ${H}"$'\n'
done
if [ -n "$HEAD_HITS" ]; then
    echo "FAIL static: \$(... | head) without '|| true' in a pipefail hook"
    echo "$HEAD_HITS" | cut -c1-160
    FAIL=1
else
    echo "PASS static: no unguarded \$(... | head) in pipefail hooks"
fi

# 2. Behavioural. Two shapes, because the bug flips direction with where the match sits:
#    - guarded file, `UnityEditor` use at the END: line 128 reads all input (matches), line 130 matches
#      the early `#if` and gets SIGPIPE  -> false BLOCK of a correct file.
#    - unguarded file, `using UnityEditor;` at the TOP: line 128 gets SIGPIPE -> false negative, the
#      violation is waved through (the dangerous direction).
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
DIR="$SANDBOX/_GameFolders/Scripts/Games/Concretes/Probe"
mkdir -p "$DIR"

pad() { for i in $(seq 1 6000); do echo "    private int _field$i; // padding to exceed the pipe buffer"; done; }

run_case() { # name expected_rc file
    local name=$1 want=$2 file=$3 rc
    jq -n --arg p "$file" --rawfile c "$file" '{tool_input:{file_path:$p,content:$c}}' \
        | (cd "$SANDBOX" && bash "$HOOKS_DIR/guard-editor-runtime.sh") >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        echo "PASS behavioural: $name (exit $rc, $(wc -c < "$file" | tr -d ' ')B)"
    else
        echo "FAIL behavioural: $name (exit $rc, wanted $want, $(wc -c < "$file" | tr -d ' ')B)"
        FAIL=1
    fi
}

GUARDED="$DIR/BigGuarded.cs"
UNGUARDED="$DIR/BigUnguarded.cs"

{
    echo '#if UNITY_EDITOR'
    echo '#endif'
    echo 'namespace Game.Concretes.Probe { public sealed class BigGuarded {'
    pad
    echo '#if UNITY_EDITOR'
    echo '    private void Ping() { UnityEditor.EditorApplication.Beep(); }'
    echo '#endif'
    echo '} }'
} > "$GUARDED"
run_case "large guarded file is accepted" 0 "$GUARDED"

{
    echo 'using UnityEditor;'
    echo 'namespace Game.Concretes.Probe { public sealed class BigUnguarded {'
    pad
    echo '} }'
} > "$UNGUARDED"
run_case "large unguarded file is blocked" 2 "$UNGUARDED"

exit "$FAIL"
