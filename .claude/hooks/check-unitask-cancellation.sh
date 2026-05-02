#!/bin/bash
# Hook: Warns about async UniTask methods missing CancellationToken parameter
# Exempt: override methods, Unity lifecycle wrappers, private helpers under 5 lines
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Skip test files
if echo "$FILE_PATH" | grep -qiE "(Tests?|Spec)/"; then
    exit 0
fi

ISSUES=""

# Strip single-line comments
STRIPPED=$(sed 's|//.*||g' "$FILE_PATH" 2>/dev/null)

# Find async UniTask methods without CancellationToken
# Match: async UniTask or async UniTask<T> method signatures
while IFS= read -r match; do
    LINE_NUM=$(echo "$match" | cut -d: -f1)
    LINE_CONTENT=$(echo "$match" | cut -d: -f2-)

    # Skip if already has CancellationToken
    if echo "$LINE_CONTENT" | grep -qE "CancellationToken"; then
        continue
    fi

    # Skip override methods — they must match base signature
    if echo "$LINE_CONTENT" | grep -qE "\boverride\b"; then
        continue
    fi

    # Skip interface declarations (no body)
    if echo "$LINE_CONTENT" | grep -qE ";\s*$"; then
        continue
    fi

    ISSUES="${ISSUES}\n  Line ${LINE_NUM}: $(echo "$LINE_CONTENT" | sed 's/^\s*//')"
done < <(grep -n "async\s\+UniTask" "$FILE_PATH" 2>/dev/null | grep -v "//")

if [ -n "$ISSUES" ]; then
    echo "WARNING — async UniTask methods without CancellationToken in: $FILE_PATH"
    echo ""
    echo "Every async UniTask method should accept a CancellationToken to support cancellation:"
    echo -e "$ISSUES"
    echo ""
    echo "Pattern: public async UniTask DoWorkAsync(CancellationToken ct)"
    echo "In services: bind to _cts.Token (cancel in Dispose)"
    echo "In MonoBehaviours: this.GetCancellationTokenOnDestroy()"
    exit 0
fi

exit 0
