#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# --- Hook Audit Logging ---
_hook_log() {
    local code=$1
    local log="${HOME}/.claude/hook-audit.log"
    mkdir -p "$(dirname "$log")"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local proj; proj=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    local file="${FILE_PATH:-}"
    local status
    if [ "$code" -eq 2 ]; then status="BLOCKED"
    elif [ "$code" -eq 0 ]; then status="OK"
    else status="WARN"; fi
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-save-load" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Persistence goes through Framework.SaveLoadSystems.ISaveLoadService.
#       Blocks PlayerPrefs and raw File/JsonConvert/persistentDataPath in game code (Card 1),
#       a *SaveData type that is a struct, unserializable, or has no int Version (Card 2),
#       and an inline save-key string literal instead of a SaveKeyHelper const (Card 4).
# Scope: _GameFolders/Scripts/Games/ .cs files. Editors/ and Tests/ are exempt; _Framework/
#        is out of scope because LocalSaveLoadDal is the one legitimate File/JsonConvert site.
# Rule: rules/save-load.md

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
echo "$FILE_PATH" | grep -qE "\.cs$" || exit 0
echo "$FILE_PATH" | grep -qE "_GameFolders/Scripts/Games/" || exit 0
should_skip_path "$FILE_PATH" && exit 0
echo "$FILE_PATH" | grep -qE "(^|/)Editors?/" && exit 0

# --- Compute the EFFECTIVE post-tool-call content ---
# PreToolUse fires BEFORE the write lands. Checking the on-disk file would make an
# existing violation permanently unfixable — the edit that removes it would still be
# judged against the pre-edit content.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
EFFECTIVE_FILE=$(mktemp)

case "$TOOL_NAME" in
    Write)
        echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
        ;;
    Edit)
        [ -f "$FILE_PATH" ] || exit 0
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        OLD_STRING_FILE=$(mktemp)
        NEW_STRING_FILE=$(mktemp)
        echo "$INPUT" | jq -j '.tool_input.old_string // empty' > "$OLD_STRING_FILE"
        echo "$INPUT" | jq -j '.tool_input.new_string // empty' > "$NEW_STRING_FILE"
        REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false')
        if [ -s "$OLD_STRING_FILE" ]; then
            python3 - "$EFFECTIVE_FILE" "$OLD_STRING_FILE" "$NEW_STRING_FILE" "$REPLACE_ALL" <<'PYEOF' 2>/dev/null || true
import sys
target_path, old_path, new_path, replace_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
with open(target_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    content = f.read()
with open(old_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    old = f.read()
with open(new_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    new = f.read()
content = content.replace(old, new) if replace_all else content.replace(old, new, 1)
with open(target_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(content)
PYEOF
        fi
        ;;
    *)
        [ -f "$FILE_PATH" ] || exit 0
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        ;;
esac

REPORT=$(python3 - "$EFFECTIVE_FILE" "$(basename "$FILE_PATH")" <<'PYEOF'
import re, sys

path, filename = sys.argv[1], sys.argv[2]
try:
    src = open(path, encoding="utf-8", errors="surrogateescape").read()
except OSError:
    sys.exit(0)

src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
lines = src.splitlines()

def code_lines():
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        yield n, line.split("//", 1)[0], line


BACKEND = re.compile(
    r"\bPlayerPrefs\s*\.|\bApplication\s*\.\s*persistentDataPath\b|\bJsonConvert\s*\.|"
    r"\bJsonUtility\s*\.\s*(To|From)Json\b|\bFile\s*\.\s*(WriteAllText|ReadAllText|WriteAllBytes|ReadAllBytes)\b"
)
INLINE_KEY = re.compile(r"\.\s*(Save|Load|HasKey|Delete)\s*(<[^<>()]*>)?\s*\(\s*\"")

findings = []

for n, code, raw in code_lines():
    if BACKEND.search(code):
        findings.append(("CARD1", n, raw.strip()))
    if INLINE_KEY.search(code):
        findings.append(("CARD4", n, raw.strip()))

# Card 2 applies to the shape of a persisted type, keyed off the *SaveData filename.
if filename.endswith("SaveData.cs"):
    typename = filename[:-3]
    decl = re.search(r"\b(class|struct|record)\s+" + re.escape(typename) + r"\b", src)
    if decl:
        decl_line = src[:decl.start()].count("\n") + 1
        kind = decl.group(1)
        if kind != "class":
            findings.append(("CARD2-KIND", decl_line, decl.group(0)))
        if not re.search(r"\[\s*(System\.)?Serializable\s*\]", src):
            findings.append(("CARD2-ATTR", decl_line, typename))
        if not re.search(r"\bpublic\s+int\s+Version\b", src):
            findings.append(("CARD2-VER", decl_line, typename))

if not findings:
    sys.exit(0)

msgs = {
    "CARD1": "Card 1 — persistence backend called directly. Inject ISaveLoadService instead.",
    "CARD4": "Card 4 — inline save-key string. Use a SaveKeyHelper const.",
    "CARD2-KIND": "Card 2 — a persisted type must be a class, not a struct/record (ISaveLoadDal.SaveData takes object, so a struct is boxed on every save, and default(T) is indistinguishable from a real save).",
    "CARD2-ATTR": "Card 2 — persisted type is missing [Serializable].",
    "CARD2-VER": "Card 2 — persisted type is missing 'public int Version = 1;' (without it a field type change is unrecoverable).",
}

seen = set()
for tag, n, text in findings[:10]:
    if tag in seen and tag.startswith("CARD2"):
        continue
    seen.add(tag)
    print("%d: %s\n    %s" % (n, text, msgs[tag]))
PYEOF
)

if [ -n "$REPORT" ]; then
    unity_hook_block "Save/load rule violation.
File: $FILE_PATH

$REPORT

The chain already exists and is generated by /setup-project — never rewritten per project:

    ISaveLoadService  ->  SaveLoadService    (Tier 3, pure C#)
    ISaveLoadDal      ->  LocalSaveLoadDal   (Tier 4, the only File/JsonConvert site)

Read path is HasKey -> Load, else the domain's config default (Card 6).

Rule: rules/save-load.md"
fi

exit 0
