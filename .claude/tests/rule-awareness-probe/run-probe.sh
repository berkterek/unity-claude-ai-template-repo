#!/usr/bin/env bash
# Rule-awareness probe — measures whether a FRESH session plans by the rules.
# Non-deterministic: one run proves nothing; compare means over >=3 runs.
# Usage: .claude/tests/rule-awareness-probe/run-probe.sh [runs]   (default 3)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS="${1:-3}"
cd "$DIR/../../.."   # repo root — the probe must load this repo's instructions

for prompt_file in "$DIR"/prompts/*.txt; do
    name="$(basename "$prompt_file" .txt)"
    markers="$DIR/prompts/${name}.markers"
    total=$(grep -c . "$markers")
    sum=0
    scored=0
    for run in $(seq 1 "$RUNS"); do
        # Score the WHOLE answer. In plan mode the full plan goes into a Write / ExitPlanMode
        # tool input and the final message is only a summary — grading the summary alone
        # under-counted at random (measured 2026-10-08: a 5/5 plan scored 3/5).
        answer=$(claude -p "$(cat "$prompt_file")" --permission-mode plan --output-format stream-json --verbose 2>/dev/null \
            | jq -r 'select(.type=="result") | .result // empty,
                     (select(.type=="assistant") | .message.content[]?
                      | select(.type=="tool_use" and (.name=="Write" or .name=="ExitPlanMode"))
                      | (.input.content // .input.plan // empty))' 2>/dev/null || true)
        # An empty answer is a failed call (rate limit, auth, crash), never a score of 0 —
        # counting it as 0 turned a run of rate-limited calls into "0/5" (measured 2026-10-08,
        # in a downstream project).
        if [ -z "$answer" ]; then
            printf '%s\t%s\tERROR (empty answer — excluded from mean)\n' "$name" "$run"
            continue
        fi
        scored=$((scored + 1))
        hits=0
        while IFS= read -r re; do
            [ -z "$re" ] && continue
            printf '%s' "$answer" | grep -qE "$re" && hits=$((hits + 1))
        done < "$markers"
        sum=$((sum + hits))
        printf '%s\t%s\t%s/%s\n' "$name" "$run" "$hits" "$total"
    done
    if [ "$scored" -eq 0 ]; then
        printf '%s\tmean\tn/a (no scored runs)\n' "$name"
    else
        printf '%s\tmean\t%s\t(%s/%s runs scored)\n' "$name" "$(echo "scale=2; $sum / $scored" | bc)" "$scored" "$RUNS"
    fi
done
