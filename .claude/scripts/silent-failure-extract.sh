#!/bin/bash
# Prints only the lines a silent-failure audit needs (catch blocks, async void, .Forget(),
# Subscribe/Unsubscribe balance) from the given .cs files, with context. Empty output = nothing
# to audit. Used by /orchestrate checkpoint Step 2 so the linter judges excerpts instead of
# reading whole files.
# Usage: silent-failure-extract.sh <file.cs>...
set -uo pipefail

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in *.cs) ;; *) continue ;; esac

    hits=$(grep -nE -A4 'catch[[:space:]]*(\(|\{|$)|async[[:space:]]+void|\.Forget\(\)' "$f")
    subs=$(grep -cE '\.Subscribe(<|\()' "$f")
    unsubs=$(grep -cE '\.Unsubscribe(<|\()' "$f")

    [ -z "$hits" ] && [ "$subs" -eq "$unsubs" ] && continue

    echo "=== $f"
    [ -n "$hits" ] && echo "$hits"
    if [ "$subs" -ne "$unsubs" ]; then
        echo "--- Subscribe x$subs vs Unsubscribe x$unsubs:"
        grep -nE '\.(Un)?[Ss]ubscribe(<|\()' "$f"
    fi
done
