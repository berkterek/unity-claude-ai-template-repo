#!/usr/bin/env bats
# Files whose work happens before any matching file is touched (planning), through
# MCP (never fires paths:), or in a subagent must Read their path-scoped rules
# explicitly. This pins the list so a later edit cannot drop one silently.

setup() { cd "$BATS_TEST_DIRNAME/../../.." || exit 1; }

AUDIT=(
  "agents/tester.md:testing"
  "agents/unity-test-builder.md:testing"
  "agents/unity-ui-toolkit-builder.md:ui-toolkit-runtime"
  "agents/unity-ui-builder.md:ui-toolkit-runtime unity-prefabs performance"
  "agents/unity-setup.md:scene-hierarchy unity-prefabs ui-toolkit-runtime"
  "agents/unity-scene-builder.md:scene-hierarchy unity-prefabs"
  "agents/reviewer.md:logging save-load serialization event-patterns unity-async performance"
  "agents/unity-reviewer.md:logging save-load serialization event-patterns unity-async performance"
  "agents/migrator.md:unity-input unity-async event-patterns"
  "agents/unity-optimizer.md:performance"
  "commands/architect.md:ui-toolkit-runtime roadmap-milestones save-load testing"
  "commands/plan-module.md:roadmap-milestones"
  "commands/roadmap.md:roadmap-milestones"
  "commands/game-idea.md:roadmap-milestones"
  "commands/refine-gdd.md:roadmap-milestones"
  "commands/refine-tdd.md:roadmap-milestones"
  "commands/orchestrate.md:roadmap-milestones testing"
  "commands/implement.md:testing"
  "commands/fix.md:testing"
  "commands/migrate.md:testing"
  "commands/setup-project.md:save-load logging"
  "commands/scene-setup.md:scene-hierarchy unity-prefabs"
  "commands/update-scene-hierarchy.md:scene-hierarchy unity-prefabs"
  "commands/unity-scene-update.md:scene-hierarchy unity-prefabs"
  "commands/create-prefab-scene.md:scene-hierarchy unity-prefabs"
)

@test "every audited file carries a Rules-to-Read-first block naming its rules" {
    fail=0
    for entry in "${AUDIT[@]}"; do
        file=".claude/${entry%%:*}"
        block=$(grep -A2 'Rules to Read first' "$file" || true)
        [ -n "$block" ] || { echo "$file: no Rules-to-Read-first block"; fail=1; continue; }
        for rule in ${entry#*:}; do
            [[ "$block" == *".claude/rules/${rule}.md"* ]] || { echo "$file: missing $rule"; fail=1; }
        done
    done
    [ "$fail" -eq 0 ]
}

# Code-writing agents create new files, and a new-file Write does not trigger paths:
# (issue #93248, reproduced in the 2026-10-08 spike). Subagents do not receive the
# SessionStart index either, so they read the index itself and pick their rules from it.
CODE_AGENTS=(coder unity-coder unity-fixer debugger unity-prototyper unity-network-dev unity-particle-designer unity-shader-dev)

@test "every code-writing agent reads the rule index first" {
    fail=0
    for a in "${CODE_AGENTS[@]}"; do
        file=".claude/agents/${a}.md"
        block=$(grep -A2 'Rules to Read first' "$file" || true)
        [[ "$block" == *".claude/docs/rule-index.md"* ]] || { echo "$file: no rule-index.md in a Rules-to-Read-first block"; fail=1; }
    done
    [ "$fail" -eq 0 ]
}

@test "every rule named in the audit exists" {
    for entry in "${AUDIT[@]}"; do
        for rule in ${entry#*:}; do
            [ -f ".claude/rules/${rule}.md" ] || { echo "no rule $rule"; false; }
        done
    done
}
