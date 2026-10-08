#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# PostToolUse hook: lists new skill files in .claude/docs/auto-loaded-skills.md
# as "- `path` — description". Triggers on Write/Edit to
# .claude/skills/{third-party,plugins,learned,platform}/.
#
# NOT an @-import. Imports load at launch and count toward the instruction
# budget — and the old @.claude/... form never loaded at all, because imports
# resolve relative to the importing file (measured 2026-10-08). session-restore.sh
# injects this list at every SessionStart and agents read it at Step 0, so the
# model knows each skill exists and Reads it when its description matches.
# Spec: docs/superpowers/specs/2026-10-08-instruction-loading-design.md

TOOL_INPUT=$(cat)

FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d)
    print(inp.get('file_path', ''))
except:
    print('')
" 2>/dev/null)

[[ -z "$FILE_PATH" ]] && exit 0

# Normalize to relative path from repo root
PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$PROJECT_ROOT" ]] && exit 0

RELATIVE_PATH="${FILE_PATH#$PROJECT_ROOT/}"

# Only handle skill directories we care about
case "$RELATIVE_PATH" in
    .claude/skills/third-party/*.md|\
    .claude/skills/plugins/*.md|\
    .claude/skills/learned/*.md|\
    .claude/skills/third-party/*/SKILL.md|\
    .claude/skills/platform/*/SKILL.md)
        ;;
    *)
        exit 0
        ;;
esac

INDEX_FILE="${UNITY_AUTO_LOADED_SKILLS_FILE:-$PROJECT_ROOT/.claude/docs/auto-loaded-skills.md}"
SECTION_HEADER="# Auto-Loaded Skills"

# Already listed, in either the old @ format or the new one?
if [ -f "$INDEX_FILE" ] && grep -qF "$RELATIVE_PATH" "$INDEX_FILE"; then
    exit 0
fi

if [ ! -f "$INDEX_FILE" ] || ! grep -qF "$SECTION_HEADER" "$INDEX_FILE"; then
    printf '\n%s\n\n<!-- managed by auto-load-skills.sh — do not edit manually -->\n' "$SECTION_HEADER" >> "$INDEX_FILE"
fi

python3 - "$INDEX_FILE" "$SECTION_HEADER" "$RELATIVE_PATH" "$PROJECT_ROOT/$RELATIVE_PATH" << 'PYEOF'
import sys

index_path, section_header, rel_path, abs_path = sys.argv[1:5]

def describe(path):
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except OSError:
        return ''
    if lines and lines[0].strip() == '---':
        for i in range(1, len(lines)):
            if lines[i].strip() == '---':
                break
            if lines[i].startswith('description:'):
                value = lines[i][len('description:'):].strip().strip('"').strip("'")
                if value in ('>', '|', '>-', '|-', ''):
                    for nxt in lines[i + 1:]:
                        if nxt.strip():
                            value = nxt.strip()
                            break
                return value[:140]
    for line in lines:
        if line.startswith('# '):
            return line[2:].strip()[:140]
    return ''

desc = describe(abs_path)
entry = f'- `{rel_path}`' + (f' — {desc}' if desc else '') + '\n'

with open(index_path, encoding='utf-8') as f:
    lines = f.readlines()

insert_at = None
for i, line in enumerate(lines):
    if line.strip() == section_header:
        insert_at = i + 1
        for j in range(i + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped.startswith('- `') or stripped.startswith('@') or stripped.startswith('<!--') or not stripped:
                insert_at = j + 1
            elif stripped.startswith('#'):
                break
        break

if insert_at is not None:
    lines.insert(insert_at, entry)
    with open(index_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
PYEOF

echo "auto-load-skills: listed $RELATIVE_PATH in auto-loaded-skills.md" >&2
exit 0
