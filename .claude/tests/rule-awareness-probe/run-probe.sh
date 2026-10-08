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
    for run in $(seq 1 "$RUNS"); do
        answer=$(claude -p "$(cat "$prompt_file")" --permission-mode plan 2>/dev/null || true)
        hits=0
        while IFS= read -r re; do
            [ -z "$re" ] && continue
            printf '%s' "$answer" | grep -qE "$re" && hits=$((hits + 1))
        done < "$markers"
        sum=$((sum + hits))
        printf '%s\t%s\t%s/%s\n' "$name" "$run" "$hits" "$total"
    done
    printf '%s\tmean\t%s\n' "$name" "$(echo "scale=2; $sum / $RUNS" | bc)"
done
