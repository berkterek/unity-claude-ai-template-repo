# Plan: Hook Reliability — cwd-Proof Paths, BSD sed, Gate Scope, Template-Mode Churn

**Status:** IMPLEMENTED (Items 1–4 done; Item 1 needs manual Director swap of settings.json)
**Affected repos:** `unity-claude-ai-template-repo` (source of truth) → sync to `nile_hole_incremental_repo`
**Origin:** Live session log (2026-07) showed ~564 lines of hook errors, silent enforcement fail-open, and BSD sed failures on macOS. Root-cause analysis confirmed four independent issues.

---

## Item 1 — settings.json: relative hook paths (CRITICAL)

### Problem
All ~45 hook entries in `.claude/settings.json` use relative commands (`.claude/hooks/foo.sh`). Claude Code's Bash tool keeps a persistent shell; the moment any command does `cd <subdir>` (e.g. into the Unity project folder), every subsequent hook invocation resolves the relative path against the drifted cwd and fails with "No such file or directory". Consequences:
- **Fail-open enforcement:** ALL hooks die at once — including blocking guards (`guard-gate-cleared`, `block-scene-edit`, `check-config-protection`). The safety layer silently disappears.
- **Context pollution:** every tool call emits 5–10 error lines into the model's context (observed: 564 hidden lines in one session).

### Fix
Prefix every hook command in `settings.json` with `"$CLAUDE_PROJECT_DIR"/`:

```json
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-ls-grep.sh"
```

`$CLAUDE_PROJECT_DIR` is set by Claude Code for hook execution specifically to make hook paths cwd-independent.

### Constraint — settings.json is protected
`check-config-protection.sh` blocks Claude from editing `settings.json` (by design). Procedure:
1. Claude writes the fully transformed file to `.claude/settings.json.new`.
2. Claude diffs old vs new (only the command prefixes may change — nothing else).
3. **Director manually replaces** `settings.json` with the new file after review. Do NOT bypass the protection hook.

### Acceptance
- [x] All hook `command` values are `$CLAUDE_PROJECT_DIR`-prefixed; JSON valid; no other field changed.
- [ ] Manual test: from a Claude Code session, `cd` into the Unity subfolder, trigger an Edit — hooks still fire (no "No such file" errors). **PENDING: Director must swap settings.json with settings.json.new first.**

---

## Item 2 — BSD sed incompatibility in 6 content-checking hooks (HIGH)

### Problem
`check-input-system.sh`, `check-unity-event.sh`, `check-no-runtime-instantiate.sh`, `check-no-linq-hotpath.sh`, `check-time-scale.sh`, `guard-editor-runtime.sh` all use the GNU-only one-liner label form for multiline block-comment stripping:

```sh
sed ':a;N;$!ba;s|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/||g'
```

macOS BSD sed rejects `;`-separated labels (`unused label` — observed live). The error is swallowed, block-comment stripping silently no-ops, and code inside `/* ... */` comments triggers false-positive blocks.

### Fix
Replace the stripping pipeline with a single shared helper in `_lib.sh` — `strip_cs_noise <file>` — implemented in **python3** (already a hard dependency of the hooks), handling `//` line comments, `/* */` block comments, and string literals in one pass, correctly ordered (strings stripped before comment detection so `"http://x"` doesn't eat the rest of the line). All 6 hooks call the helper instead of inline sed.

Rationale for python over portable sed (`-e ':a' -e 'N' -e '$!ba' ...`): the portable-sed form fixes the label error but keeps the existing ordering bug (line-comment stripping before string stripping corrupts lines containing `//` inside strings). One python helper fixes both and is testable in isolation.

### Acceptance
- [x] `grep -l ':a;N;$!ba' .claude/hooks/*.sh` returns nothing.
- [x] New bats test: file with `new GameObject()` **only inside a block comment** is NOT blocked; same call in live code IS blocked; `var s = "// not a comment"; new GameObject()` on one line IS blocked.
- [x] Existing hook bats tests still pass (118 ok, pre-existing graph-auto-update test 1 failure unrelated).
- [x] Director runs `hooks/tests/run-tests.sh` **on macOS** — all new tests pass locally.

---

## Item 3 — Director Gate: interrupted-pipeline leak (DECISION + SMALL FIX)

### Problem
Gate cleanup is deterministic on the happy path (committer finish → `agent-stop-log.sh` deletes it) and at session boundary (`session-restore.sh`). But a pipeline interrupted mid-flight (QUALITY_GATE "stop", error, user abandons) leaves the gate valid for up to 4h within the same session — a later pipeline can spawn coder/committer without a fresh approval.

The guard cannot reliably verify *which* pipeline is spawning (it only sees `subagent_type`), so full pipeline-scoping is not implementable at the hook layer.

### Decision (proposed)
Accept the residual risk with two cheap mitigations:
1. **Shorten the TTL in `guard-gate-cleared.sh` from 4h (14400s) to 45min (2700s).** Approval-to-spawn latency within a pipeline is minutes; 45min covers slow SPARC/plan phases while shrinking the leak window ~5×.
2. **Document the residual risk** in CLAUDE.md's Director Gate section: one sentence stating that an aborted pipeline's gate remains valid up to 45min and a cautious Director can run `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"` when stopping a pipeline midway.

### Acceptance
- [x] TTL constant changed (2700s) + bats tests: 46-min-old gate rejected, 5-min-old gate allowed.
- [x] CLAUDE.md note added (Director Gate Rules section).

---

## Item 4 — graph-auto-update: template-mode churn (LOW)

### Problem
In the template repo (no Unity project, `unity_project_folder: "."`, no `Assets/`), every edit still triggers a background graph rebuild that rewrites `graph.json` timestamps — dirtying the working tree on every session (observed 3× during recent work; worked around by committing churn).

### Fix
Early-exit in `graph-auto-update.sh`: after reading `project-features.json`, resolve the assets root (`Assets` or `<unity_project_folder>/Assets`); if the directory does not exist, `exit 0` before spawning the builder. (Builder's own template-mode support stays — this only stops *auto*-triggered rebuilds; manual `/build-knowledge-graph` still works.)

### Acceptance
- [x] Editing a file in the template repo no longer modifies `graph.json` (early-exit when Assets/ absent).
- [ ] In nile (real Assets/), auto-update still fires (graph-updates.log gets a new line on .cs edit). **PENDING: nile smoke test.**
- [x] bats test for the early-exit branch.

---

## Rollout Order

1. Item 2 (sed→python helper) + Item 4 (template-mode skip) — pure hook-file changes, one commit each.
2. Item 3 (TTL + doc note) — one commit.
3. Item 1 (settings.json.new generation) — Claude prepares, **Director swaps manually**, then manual verification.
4. Run full bats suite on macOS + one live smoke test (cd into subfolder → Edit → hooks fire).
5. Sync all changed files to `nile_hole_incremental_repo` in a single `chore(harness)` commit; repeat the smoke test there.

## Out of Scope (parked, separate discussions)

- Session-start context weight (~55k tokens; auto-loaded skills pruning)
- Folder-placement / MonoBehaviour-suffix rules have no enforcing hook (architectural drift observed in nile)
- Per-edit hook count (25) and aggregate latency
- Bash-write bypass of Edit/Write-scoped content hooks
