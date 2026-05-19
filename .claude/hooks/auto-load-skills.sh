#!/bin/bash
# PostToolUse hook: auto-adds @-references for new skill files into CLAUDE.md
# Triggers on Write/Edit to .claude/skills/{third-party,plugins,learned}/

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

CLAUDE_MD="$PROJECT_ROOT/.claude/docs/auto-loaded-skills.md"
AT_REF="@$RELATIVE_PATH"
SECTION_HEADER="# Auto-Loaded Skills"

# Already referenced?
if grep -qF "$AT_REF" "$CLAUDE_MD"; then
    exit 0
fi

# Add section if missing
if ! grep -qF "$SECTION_HEADER" "$CLAUDE_MD"; then
    printf '\n%s\n\n<!-- managed by auto-load-skills.sh — do not edit manually -->\n' "$SECTION_HEADER" >> "$CLAUDE_MD"
fi

# Insert @-ref after the section header
python3 - "$CLAUDE_MD" "$SECTION_HEADER" "$AT_REF" << 'PYEOF'
import sys

claude_md_path = sys.argv[1]
section_header = sys.argv[2]
at_ref = sys.argv[3]

with open(claude_md_path, 'r') as f:
    lines = f.readlines()

insert_at = None
for i, line in enumerate(lines):
    if line.strip() == section_header:
        # Find the end of the section block to append after existing refs
        for j in range(i + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped.startswith('@'):
                insert_at = j + 1  # keep appending after last @-ref
            elif stripped.startswith('##') and j > i + 1:
                break
        if insert_at is None:
            insert_at = i + 1
        break

if insert_at is not None:
    lines.insert(insert_at, at_ref + '\n')
    with open(claude_md_path, 'w') as f:
        f.writelines(lines)
PYEOF

echo "auto-load-skills: added $AT_REF to CLAUDE.md" >&2
exit 0
