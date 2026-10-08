#!/usr/bin/env bats
# Guards the launch-loaded instruction budget. Claude Code warns when instruction files loaded
# at session start add past 150,000 chars (unicode chars — the warning's 469.5k matched 474k
# bytes), and the documented cost of that bloat is adherence. Restructured 2026-10-08 to
# ~147.9k with a thin margin — and claude-md-management:revise-claude-md appends to CLAUDE.md
# on every /implement and /fix — so the margin needs a guard, not a memory.
#
# Counted: .claude/CLAUDE.md, every @-import it resolves (file-relative), and every rule file
# without paths: frontmatter. The user-level ~/.claude/CLAUDE.md lives outside the repo, so a
# constant stands in for it. Path-scoped rules are not counted at launch (spike S7a).
#
# If this fails, move the new text to docs/incidents/ or a path-scoped rule — do not raise
# the threshold to make it pass.

setup() { cd "$BATS_TEST_DIRNAME/../../.." || exit 1; }

@test "launch-loaded instructions stay under the budget" {
    limit="${UNITY_RULE_BUDGET_CHARS:-148000}"
    total=$(python3 - <<'PY'
import glob, os, re
files = ['.claude/CLAUDE.md']
for line in open('.claude/CLAUDE.md', encoding='utf-8'):
    m = re.match(r'^@(\S+)', line)
    if m:
        files.append(os.path.join('.claude', m.group(1)))
for r in sorted(glob.glob('.claude/rules/*.md')):
    with open(r, encoding='utf-8') as f:
        if f.readline().rstrip('\n') != '---':
            files.append(r)
GLOBAL_CLAUDE_MD = 1000  # ~/.claude/CLAUDE.md, outside the repo
print(sum(len(open(f, encoding='utf-8').read()) for f in files) + GLOBAL_CLAUDE_MD)
PY
)
    echo "launch total: $total chars (limit $limit)"
    [ "$total" -le "$limit" ]
}

@test "every @-import in CLAUDE.md resolves relative to .claude/ (an unresolved import loads nothing)" {
    while read -r imp; do
        [ -f ".claude/${imp#@}" ] || { echo "unresolved import: $imp"; false; }
    done < <(grep -E '^@' .claude/CLAUDE.md)
}
