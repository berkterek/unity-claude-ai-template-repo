#!/usr/bin/env bash
# Builds a throwaway fake-Unity project and prints its path, for dry-running a
# pipeline command end-to-end and observing GATE ORDER and STATE-FILE LIFECYCLE.
#
# WHY THIS EXISTS — the gap it covers, and the two it does not:
#   .claude/hooks/tests/ (36 bats suites) measures how a guard hook REACTS to a state
#   file. All six guard-*.sh are covered there and all six are registered in
#   settings.json — verified. What nothing covers is whether a pipeline CREATES that
#   file at the right step and REMOVES it at the end, and whether the gates fire in
#   the documented order. That is what this harness measures.
#   It does NOT cover: TD-COMPILE (needs Unity + MCP), PlayMode tests, prefab/scene work.
#
# WHY A SANDBOX AND NOT THIS REPO — the Director must write real state files. Writing
# .claude/state/gate-cleared here without a gate actually shown to a human is the
# violation CLAUDE.md forbids, and a leaked file locks the next real run out. Same
# reasoning as .claude/tests/reviewer-fixtures/: keep the artificial state off the repo.
#
# Usage:
#   SB="$(.claude/tests/pipeline-dry-run/make-sandbox.sh)"
#   # then hand $SB to a subagent as the project root, with a scripted user and
#   # scripted subagent results. Pass conditions are in README.md next to this script.

set -euo pipefail

SRC="$(git rev-parse --show-toplevel)"
DIR="${1:-$(mktemp -d)}"
mkdir -p "$DIR/.claude" "$DIR/_GameFolders/Scripts/Games/Abstracts/Turrets" \
         "$DIR/_GameFolders/Scripts/Games/Concretes/Turrets" "$DIR/docs"

# Real instruction layer — the point is to drive the actual command files, not copies
# rewritten for the test. hooks/ and settings.json are deliberately NOT copied: the
# harness resolves hooks from the live session, and settings.json is Claude-immutable.
cp -R "$SRC/.claude/commands" "$SRC/.claude/docs" "$SRC/.claude/rules" \
      "$SRC/.claude/CLAUDE.md" "$DIR/.claude/"

cat > "$DIR/_GameFolders/Scripts/Games/Abstracts/Turrets/ITurretService.cs" <<'CS'
namespace Game.Abstracts.Turrets
{
    public interface ITurretService
    {
        void Aim(UnityEngine.Vector3 worldPoint);
    }
}
CS

cat > "$DIR/_GameFolders/Scripts/Games/Concretes/Turrets/TurretService.cs" <<'CS'
using Game.Abstracts.Turrets;
using UnityEngine;

namespace Game.Concretes.Turrets
{
    public sealed class TurretService : ITurretService
    {
        // Deliberately empty: the dry-run task is "make Aim work, and move the
        // Unity call behind an ITurretProvider".
        public void Aim(Vector3 worldPoint) { }
    }
}
CS

git -C "$DIR" init -q
git -C "$DIR" add -A
git -C "$DIR" commit -qm "dry-run baseline"

echo "$DIR"
