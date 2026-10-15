# PLAN: Use the Unity 6 CLI as a Headless Verification Layer

> **Version:** v3 — 2026-10-15
> **Status:** Active
> **Scope (approved):** (1) a new project-owned skill `.claude/skills/core/unity-cli-verify.md`, plus its row in `.claude/docs/skills-index.md`. (2) In `unity-verifier.md` Step 4 State 2, the non-Unity fallback is replaced by `unity test`. (3) A new PreToolUse Bash hook `.claude/hooks/check-unity-cli.sh` and its bats suite, which enforce the `unity command eval` ban. The user registers the hook in `settings.json`. (4) Updates to `docs/incidents/mcp-and-framework.md` and to the hook docs (`hooks-blocking.md`, `hook-profiles.md`, `hooks/tests/README.md`).
> **Scope additions, each needing explicit approval (see the dedicated section):** (a) block bare `unity mcp` and `unity mcp configure`. (b) Block `unity pipeline install|upgrade`. (c) The verifier outcomes `NOT VERIFIED` / `NO VERDICT`, the `Verdict channel:` line, and edits to Exit Condition 3 and the "satisfies none" note. (d) Edits to README.md beyond the required pending-list entry. (e) A new helper `.claude/scripts/check-unity-cli.py`. (f) Change State 3 as well as State 2.
> **Out of scope:**
> - installing `com.unity.pipeline`
> - editing `validate.md`, `orchestrate.md` or `scene-setup.md`
> - any new MCP server
> - a new `project-features.json` flag
> - changes to `/setup-project`
> - the State 2 sections of `unity-setup.md` and `graphics-setup-agent.md`
> - `verify-after-write.sh` and `stop-verify.sh`
> - how `/ralph`, `/qa`, `/implement`, `/fix` and `/orchestrate` handle `NOT VERIFIED` / `NO VERDICT`
> - the broken `@`-import in `hooks-blocking.md` line 46 (noted under Known gaps)

Complexity: 0.5 (Medium)

## Changes from v1

1. **The hook judge moves out of the shell script.** It now lives in its own file, `.claude/scripts/check-unity-cli.py`, and the bash hook has no heredoc at all. Reason: v1's heredoc-inside-`$( )` fails `/bin/bash -n` on bash 3.2 (rc=2), which would block every `unity` call (finding 1).
2. **New parse checks.** Added `/bin/bash -n` and Python compile checks, one bats test for each, and a bats test showing the hook fails closed when the `.py` file is missing (finding 1).
3. **Wrappers modelled properly.** Each wrapper's value-taking flags are modelled (`env`, `command`, `exec`, `time`, `nohup`, `nice`, `sudo`, `timeout`/`gtimeout`, `stdbuf`, `xargs`). Shell keywords count as the start of a segment. New bats cases B24–B29 cover this (finding 2).
4. **`CMD_OPTVALUE` completed** from `unity command --help`, with allow cases A14 (finding 3).
5. **`unity mcp` is blocked** except `-h/--help` and `configure --list|--dry-run`. New cases B22 and A15 (finding 4, scope addition (a)).
6. **`unity command -- eval x` is now blocked.** v1's `positional()` returned "no positional" at `--`, so this form slipped through (B23). Found during this revision.
7. **The verifier text no longer contains the word `dotnet`**, and the Goal is reworded to match (finding 5).
8. **Exit 6 on the CLI path means NO VERDICT.** The verifier reverts nothing, attributes no cause, and reports raw output. The finer "compile error caused by my fix" rule is marked UNVERIFIED (finding 6).
9. **Relation to `mcp-preflight.md` States 2/3 stated explicitly** (finding 7a).
10. **Runtime capped.** One EditMode batch run per iteration, PlayMode at most once, `--timeout 900`, and the loop stops on NO VERDICT. Worst case drops from 180 to 60 minutes (finding 7b).
11. **`unity editors running --format json` added as detector (d)**, listed first. It is also added to Task 10(a) (finding 8).
12. **`unity watch` reworded.** The ban now rests only on what `--help` says. Both claims about how it behaves under `--non-interactive` are marked unverified (finding 9).
13. **Bats counts corrected** to 55 files / 663 `@test`, marked as a snapshot (finding 10).
14. **Tasks reordered.** Task 1 now runs after Task 4, and Tasks 2 and 6 run after Task 1. Task 8 checks `settings.json` before it adds a pending entry, and Task 9 V3 reconciles that entry in either order (finding 11).
15. **New section: Scope additions.** It also adds markers in the Scope header and in each affected Task (finding 12).
16. **Task 7 Callers no longer cites the `@`-import.** That import is listed under Known gaps instead (finding 13).

**v2 -> v3**
- Fallback regex fixed: v2's `unity$W.*(^|$W)X` needed two separators and failed open under BSD grep. It is now `unity$W(.*$W)?X` with `grep -qiE`. F1 now also asserts `unity cmd eval x`, `unity shell` and `unity pipeline install`.
- The judge now scans `$( )` and backticks inside unquoted heredoc bodies, because bash expands them. Only quoted-delimiter bodies are stripped. New case B30.
- The head word, wrapper, shell and keyword comparisons and the bash prefilter are now case-insensitive (`Unity …`). New case B31.
- `coproc` (and `coproc NAME { … }`) counts as the start of a segment. New case B32.
- A13's payload now carries a banned command, so the test fails if the `tool_name` guard is removed.
- Hook-timeout units corrected. "3000 ms" is now only a self-imposed performance budget. The Task 5 entry uses `"timeout": 5` (seconds). The sibling entries' `3000` values are recorded under Known gaps.
- Accepted-gap list updated: quote-split binary names (`u""nity`) are a gap; `Unity` and unquoted-heredoc expansion are now handled.

## Scope additions — need explicit user approval before implementation

| # | Addition | Where | If rejected |
|---|---|---|---|
| (a) | Block bare `unity mcp` (it starts a stdio MCP server that exposes the live Editor's commands as tools) and `unity mcp configure` unless `--list` or `--dry-run` is given. "No new MCP server" limited this plan; it was not a request to enforce that. | Task 3 B21/B22/A15, Task 4, Task 1, Tasks 7/8 | Drop the `mcp` branch from the judge and its test cases. Consequence: an agent can open a second, unreviewed Unity MCP channel, or write AI-client config, from Bash. |
| (b) | Block `unity pipeline install|upgrade` (alias `pipe`). This is a package-install policy, not literally the eval ban, but installing the package opens the eval path. | Task 3 B17/B18, Task 4, Task 1 | Drop the `pipeline` branch and B17/B18. Consequence: an agent can install `com.unity.pipeline` through a Bash write to `Packages/manifest.json` that no Edit/Write hook sees. |
| (c) | New verifier outcomes `NOT VERIFIED` (branch 2b STOP) and `NO VERDICT` (exit 6), the `Verdict channel:` report line, and the edits to Exit Condition 3 and to the "satisfies none" note (line 119). These change verifier semantics for `/implement`, `/fix`, `/qa`, `/ralph` and `/orchestrate`. **How those callers handle `NOT VERIFIED` / `NO VERDICT` (stall, stop or retry) has not been examined.** | Task 6 | Keep only the channel swap in State 2 (run `unity test`, report the exit code). Consequence: an Editor-open or binary-missing case has no defined outcome, and an exit 6 can be read as "no issues". |
| (d) | Rewrite README.md's eval paragraph (lines 1258–1262) and add a README Blocking-table row (near line 928). Both sit outside "incident doc + hook docs". The README pending-list entry (line 1619) is **required** by README's own rule whenever a hook ships unregistered; the other two edits are optional. | Task 8 | Drop the eval-paragraph rewrite and the table row, and keep only the pending entry. Consequence: README keeps repeating the inaccurate "`block-scene-edit.sh`" reason. |
| (e) | New helper file `.claude/scripts/check-unity-cli.py` (needed for finding 1). | File Map, Task 4 | Fall back to a regex-only hook. Consequence: a regex cannot skip a flag's value or tell quoted text apart, so the hook blocks this work's own commit messages (see Chosen Approach). |
| (f) | Change State 3 as well as State 2 in `unity-verifier.md`, because line 101 also falls back to the non-Unity path. | Task 6 | Leave lines 100–102 as they are and record the gap. Consequence: the non-Unity fallback survives whenever MCP is not installed, which is the template's default state. |

## Context

The MCP bridge (`mcp__UnityMCP__*`) stays the only channel for live-Editor work: scenes, prefabs, components, and the State 1 compile check with its stale-assembly probe. The Unity 6 CLI (`unity`, 1.0.0-beta.13, at `~/.unity/bin/unity`) takes over headless jobs (compile, test, build) only when no live-Editor verdict is available.

There are two reasons for this plan:

1. **The current no-MCP fallback is not a Unity compile.** `unity-verifier.md` Step 4 State 2 (line 97) and State 3 (line 101) both fall back to `dotnet build` / `dotnet test`. Nobody has checked that this produces a Unity compile verdict. A batch `unity test` starts a fresh Editor process. By reasoning, not measurement, a fresh process cannot be holding a stale DLL from an earlier failed compile. A stale DLL caused the 2026-09-03 incident recorded in Step 4: "358/358 passed with four call sites broken".
2. **The eval ban is prose only.** `docs/incidents/mcp-and-framework.md` lines 25–33 forbid `unity command eval`, but no hook mentions `unity command`, `unity test` or `unity build` (a grep over `.claude/hooks/` returns nothing). The plugin skill `unity:unity-cli` actively tells agents to drive the Editor with eval instead of hand-editing scene or asset files. So a project-owned skill has to pin the rule, and a hook has to enforce it.

**This repo has no Unity project** (there is no `ProjectSettings/`), so `unity test` cannot be exercised here. Every claim that depends on real Editor behaviour is written below as an unverified assumption. Task 10 measures those claims in a real project and writes the results back into the skill. The CLI `--help` and embedded-doc facts cited in this plan were re-read on 2026-10-15 against 1.0.0-beta.13.

**Test types.** This repo has no game code, so the Test Type Decision Matrix paths (`Games/Abstracts/` and so on) do not apply. The plan uses:
- `bats` for the hook, and for the `.py` judge's behaviour as seen through the hook
- `NoTest (markdown)` for the docs, skill and prompt tasks
- `Verification` for the in-repo and real-project checks

## Goals

- [ ] A project-owned skill says exactly which `unity` subcommands an agent may run, in what order, and how to read their exit codes.
- [ ] The word `dotnet` no longer appears in `unity-verifier.md`. With no MCP verdict, the verifier either runs a batch `unity test` (2a) or stops and reports `NOT VERIFIED` (2b). It never substitutes one for the other, and it never starts an MCP call in either branch.
- [ ] Every verifier report names the channel that produced its verdict.
- [ ] `check-unity-cli.sh` blocks the Unity CLI's live-Editor code channel with exit 2 and an explicit stderr line, and the bats suite asserts on that line.
- [ ] The hook parses under `/bin/bash` (bash 3.2), and it fails closed when its judge file is missing.
- [ ] The user registers the hook in `settings.json`. This is confirmed by reading the file, not assumed.
- [ ] The incident doc states the ban's reason accurately and lists the hook's accepted gaps. README does the same if scope addition (d) is approved.
- [ ] Task 10 has been run in a real Unity project and its measurements are recorded in the skill. Until then, the skill's "Measured" section says `NOT YET MEASURED`.

## Status

| Order | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 3: write `check-unity-cli.bats` (RED) | Pending | — (first) |
| 2 | Task 4: implement `check-unity-cli.sh` + `check-unity-cli.py` (GREEN), `chmod +x` | Pending | — (after Task 3) |
| any time after Task 4 | Task 5: **[USER ACTION]** register the hook in `settings.json` | Pending | — |
| 3 | Task 1: create the `unity-cli-verify` skill | Pending | B |
| 3 | Task 7: hook docs under `.claude/` | Pending | B |
| 3 | Task 8: incident doc + README | Pending | B |
| 4 | Task 2: register the skill in `skills-index.md` | Pending | C |
| 4 | Task 6: rewrite the no-MCP branches of `unity-verifier.md` Step 4 | Pending | C |
| 5 | Task 9: in-repo verification | Pending | — (after C; V3 needs Task 5) |
| — | Task 10: real-project measurement **[BLOCKED — needs real Unity project]** | Blocked | — |

**Group B** starts after Task 4 is green. All three of its tasks describe the hook as built, and Task 1's forbidden list must match the final judge. Each task writes its own files (the skill; three `.claude/` docs; the incident doc plus README), and none reads another's output. Tasks 7 and 8 name the skill only by its path, which is fixed by this plan.

**Group C** starts after Task 1. Task 2 indexes the skill, and Task 6 depends on the skill's content (four detectors, the run cap, exit codes). The two tasks write different files.

All README edits are in Task 8. **Task 5 can happen at any point after Task 4.** Task 8 reads `settings.json` first so it never writes a stale pending entry, and Task 9 V3 reconciles the entry whichever order actually happened.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/hooks/tests/check-unity-cli.bats` | Add | Written first (TDD). Uses the `run_cmd` jq helper from `check-write-via-bash.bats` |
| `.claude/hooks/check-unity-cli.sh` | Add | `HOOK_PROFILE_LEVEL="standard"`, exec bit set. **No heredoc and no inline Python.** It only routes: prefilter, then the judge, then the fallback regex |
| `.claude/scripts/check-unity-cli.py` | Add (**scope addition (e)**) | Contains the judge. Invoked as `python3 -I`, reads the command from env `CHECK_UNITY_CLI_CMD`, prints `ALLOW` or `BLOCK <reason>`. Sits next to `check-duplicate-siblings.py` and `validate-generated-asmdefs.py` |
| `.claude/settings.json` | Modify (**user only**) | New `PreToolUse` entry with `matcher: "Bash"`. Claude cannot edit this file (`check-config-protection.sh`) |
| `.claude/skills/core/unity-cli-verify.md` | Add | Flat core skill. Frontmatter `name` / `description` / `model-tier: light`. Sibling pattern: `mcp-preflight.md` |
| `.claude/docs/skills-index.md` | Modify | One row in the Core table, inserted after the `mcp-preflight` row (line 39) |
| `.claude/agents/unity-verifier.md` | Modify | Step 4 lines 96–102 (State 2, and State 3 per **scope addition (f)**), the line after 104, Exit Condition 3 (line 117), the "satisfies none" note (line 119), and the Final Report template (lines 144–147), all per **scope addition (c)** |
| `.claude/docs/hooks-blocking.md` | Modify | One row after `check-ls-grep.sh` (line 40) |
| `.claude/docs/hook-profiles.md` | Modify | One row in the `standard` table |
| `.claude/hooks/tests/README.md` | Modify | One row in the "Test files" table |
| `docs/incidents/mcp-and-framework.md` | Modify | Rewrite the eval bullet (lines 25–33): the accurate reason, the enforcement, and the accepted gaps |
| `README.md` | Modify | The pending list (line 1619) is required, and conditional on `settings.json`. The eval paragraph (lines 1258–1262) and the Blocking-table row (near line 928) are **scope addition (d)** |

`.claude/CLAUDE.md` is **not** modified:
- "6 critical safety hooks" stays true because the hook is `standard`.
- "20+ hooks" stays true.
- Lines 43 and 92 ("never substitute Bash (… `unity command eval`)" and "`unity command eval` is forbidden") stay true.

`.claude/docs/auto-loaded-skills.md` is **not** modified. It is generated, and it only covers `third-party/`, `plugins/`, `learned/` and `platform/`.

## Chosen Approach

**One PreToolUse Bash hook with a targeted denylist of the CLI's code-channel family.** The judging is done by a quote-aware tokenizer (`python3 shlex`; python3 is already a hook dependency through `strip_cs_noise`, `_lib.sh` line 445). The tokenizer lives in `.claude/scripts/check-unity-cli.py`.

How the bash hook works:
- It finds the judge through `${SCRIPT_DIR}/../scripts/`, the same `${SCRIPT_DIR}/../` resolution that `inject-rule-pointers.sh:48–49` and `session-restore.sh:152–153` use.
- It passes the command through an env var, never argv.
- If the judge is missing or unreadable, python3 is absent, or the judge prints nothing it recognises, the hook **fails closed** on a narrow regex.

The Editor-open check lives **in prose** (the skill and the verifier) and is labelled "prose, not enforced".

Rejected alternatives:

- **Inline Python in a `<<'PY'` heredoc inside `$( )` (v1's design).** GNU bash 3.2.57, which `#!/usr/bin/env bash` resolves to on macOS, scans that heredoc body for quotes, backticks and `$(`. An odd number of backticks, or a literal `"$("`, in the Python text is a syntax error. That makes the hook exit 2 on every allowed `unity` call. The orchestrator reproduced this on the v1 skeleton (`line 46: syntax error near unexpected token 's[i+1:j]'`). Whether it breaks depends on the content, so the hook must contain no heredoc at all.
- **A `unity` wrapper shim on PATH that polices every call.** An absolute path (`~/.unity/bin/unity`, the actual install location) bypasses it. It also needs an env change in `settings.json`, and an install step, in a template that should not install things.
- **A `permissions.deny` rule (`Bash(unity command:*)`) as the only mechanism.** It is prefix-only, so it misses `unity --json command eval`, `FOO=1 unity …`, `a && unity …` and `bash -c "…"`. Claude cannot write it either. The user can add it later as optional defence in depth.
- **A regex-only hook in the style of `check-ls-grep.sh`.** A regex cannot skip a flag's value (`--project-path X`, `nice -n 10`) or tell quoted text from a command. It would block this very work's commits (`feat: block \`unity command eval\``).
- **Default-deny with an allowlist of safe subcommands.** The CLI has about 50 subcommands, and the list grows with every beta. Default-deny would block `editors`, `install`, `releases` and `vcs` in daily use, and it teaches people to set `DISABLE_HOOK_CHECK_UNITY_CLI=1`. A hook people silence protects nothing.
- **Running the Editor-open check inside the hook.** The hook would then shell out to the binary it polices, which is fragile: `unity status` / `editors running` can wait or hang, and every Bash call would pay for it. (This rejection does not rest on a harness timeout. The plan's "< 3000 ms" is a self-imposed performance budget for the hook, not the harness limit; see Task 5 for the units.)
- **Keeping the non-Unity build as a third fallback.** Nobody ever checked that it produces a Unity compile verdict. A third channel of unknown fidelity is how the wrong thing got reported as "passed".

Decisions on the borderline subcommands (one line each):

| Subcommand | Decision | Why |
|---|---|---|
| `unity command <name>` / `cmd <name>` (any name: `eval`, `eval_file`, …), including after `--` | **Block** | Every named command runs Editor-side code in a live Editor; `eval` and `eval_file` run arbitrary C#. Only the bare listing, and its listing flags, is safe |
| `unity run … --command <name>` | **Block** | The same Pipeline command channel; per the CLI docs it "reuses an Editor already open on the project" |
| `unity pipeline install` / `upgrade` (alias `pipe`) | **Block** (scope addition (b)) | Installs `com.unity.pipeline`, which opens the eval channel, by writing `Packages/manifest.json` from Bash. `block-projectsettings.sh` and `check-config-protection.sh` match on `Edit\|Write` only and never see that write |
| `unity shell` | **Block** (except `-h` / `--help`) | A REPL. Its commands arrive on stdin (or through `--protocol ndjson`), never in the Bash command string, so `eval` typed into it is invisible to any hook |
| `unity mcp` (bare, or with any args) | **Block** (except `-h` / `--help`) (scope addition (a)) | `unity mcp --help` Examples: "`unity mcp`  Start the MCP stdio server". It exposes the live Editor's commands as MCP tools, which makes it a second Unity MCP channel |
| `unity mcp configure …` | **Block** unless `--list` or `--dry-run` (scope addition (a)) | "Write MCP server config for an AI agent client". `--list` and `--dry-run` are read-only per `unity mcp configure --help` |
| `unity editors running [--format json]` | **Allow** | The CLI's documented Pipeline-independent Editor detector (skill detector (d)). Never pass `--watch` (prose rule) |
| `unity vcs` / `unity uvcs` / `unity cm` | **Allow, not policed** | Version control, with no channel into the Editor's C# domain. Accepted gap: a Plastic `checkin` is a remote write that `block-git-push.sh` does not cover |
| `unity plugin install <id>` | **Allow** | `unity plugin list` on this machine shows the installable ids `plastic`, `licensingClient`, `ugs`, `ai`. These are external CLIs, and none of them is `com.unity.pipeline` |
| `unity job …`, `unity list`, `unity pipeline list`, `unity recompile` | **Allow** | `job` only manages jobs that a blocked `command --detach` would create. `list` and `pipeline list` are read-only. `recompile` needs the Pipeline package and exits 7 here |
| `unity close <project>`, `unity watch …` | **Allow in the hook; forbidden in prose** | Neither is a code channel. `close` "exits without saving". `watch` is a file-watching loop with no exit condition of its own (see Task 1) |

## Task 1: Create the `unity-cli-verify` skill

**Files:** `.claude/skills/core/unity-cli-verify.md` (Add)

**Runs after Task 4 is green** (group B).

**Steps:**
- [ ] Read `.claude/skills/core/mcp-preflight.md` (the sibling pattern) and `.claude/project-features.json` (`unity_project_folder`).
- [ ] Read `.claude/scripts/check-unity-cli.py` and `.claude/hooks/tests/check-unity-cli.bats` as built. The forbidden list must match the judge's blocking branches exactly.
- [ ] Write the skill from the skeleton below. Keep every unmeasured statement marked `UNVERIFIED` and pointed at Task 10.
- [ ] Confirm the frontmatter uses `model-tier`, never `model`.

**Test Type:** NoTest (markdown)

**Code Skeleton:**

````markdown
---
name: unity-cli-verify
description: "Headless compile/test verification through the Unity 6 CLI (`unity`) when no live-Editor (MCP) verdict is available. Preflight (binary → doctor → Editor-open detection, `editors running` first) → ONE batch `unity test` per verify iteration → exit-code reading (0 / 8 / 6). MCP stays the only live-Editor channel. Forbidden and hook-enforced (check-unity-cli.sh): every named `unity command` incl. eval/eval_file, `unity run --command`, `unity shell`, `unity mcp` (except --help, configure --list/--dry-run), `unity pipeline install|upgrade`."
model-tier: light
---

# Unity CLI Verification (headless)

## Channel split
| Job | Channel |
|---|---|
| Scene / prefab / component / asset work in a live Editor | MCP only (`manage_scene`, `manage_gameobject`, `manage_components`) |
| Compile + test verdict while MCP is connected | MCP (unity-verifier State 1, incl. the stale-assembly probe) |
| Compile + test verdict with MCP unavailable and NO Editor open on this project | this skill: batch `unity test` |
| MCP unavailable and an Editor IS open on this project (or cannot be ruled out) | STOP — no channel. Never batch, never eval |

## Allowed / forbidden
Allowed: `unity test`, `unity build`, `unity run` (without `--command`), `unity doctor`, `unity status`,
`unity editors running --format json`, `unity logs` (Hub log only — NOT the Editor/compile log),
`unity editors`, `unity releases`, `unity --version` / `--help`, bare `unity command` with listing flags
(`--query --tag --limit --sort --caller --skill …`), `unity list`, `unity mcp --help`,
`unity mcp configure --list` / `--dry-run`.
Forbidden, hook-enforced: `unity command <any name>` (alias `cmd`; incl. `eval`, `eval_file`, and after `--`),
`unity run --command`, `unity shell`, `unity mcp` (bare = starts a stdio MCP server; `configure` writes
client config), `unity pipeline install|upgrade` (alias `pipe`).
Forbidden, prose only (no hook): `unity close` (exits the Editor without saving); `unity watch` (a
file-watching loop with no exit condition of its own, per `unity watch --help`; its behaviour under
`--non-interactive` / CI is UNVERIFIED); `unity editors … --watch`; `unity setup <client>` /
`unity skill install` (installs the plugin skill that recommends eval; this repo's rules win anyway).
`unity recompile` needs com.unity.pipeline, which this template does not install — it exits 7 here.

## Preflight (in this order; first failing step decides)
P = absolute path: `$(git rev-parse --show-toplevel)/<unity_project_folder from .claude/project-features.json>`
1. Binary: `command -v unity` or `~/.unity/bin/unity` executable → else STOP (2b, "unity binary missing").
2. `unity --non-interactive doctor --ci` → non-zero → STOP (2b, "environment cannot build/test"), quote its output.
3. Editor-open detection — ANY positive, or any detector that errors, means "Editor open on this project" → STOP (2b).
   Prose, not enforced:
   d. `unity --non-interactive editors running --format json` lists an instance whose project is $P.
      Documented as Pipeline-independent: "Detection is cross-platform (process table plus each project's
      Pipeline lockfile), and the version falls back to a project's ProjectSettings/ProjectVersion.txt for
      editors without the Pipeline package." An empty list is a normal exit-0 result. Never pass `--watch`.
   a. `unity --non-interactive status --project-path "$P" --json` lists an instance
   b. `$P/Temp/UnityLockfile` exists (a stale lockfile after a crash also reads as open — STOP is the safe direction)
   c. a Unity process whose command line carries `-projectPath` equal to $P (`pgrep -ifl` on `projectpath`)
   UNVERIFIED: whether (d) lists a GUI Editor in a project WITHOUT com.unity.pipeline, and which JSON field
   carries the project path (absolute? symlinks resolved?) so it can be matched to $P. (a) is assumed
   insufficient: the CLI docs say `status` cannot connect without the Pipeline server. Task 10(a) measures all four.
   UNVERIFIED: what a batch `unity test` does when an Editor already holds the project. Until measured:
   never start a batch run while step 3 is positive.

## Run (cap: ONE invocation per verify iteration)
```bash
OUT="${TMPDIR:-/tmp}/unity-cli-verify/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
unity --non-interactive --no-banner test "$P" --mode EditMode \
  --report-format junit --output "$OUT/results.xml" --timeout 900
echo "exit=$?"
```
`--timeout` is in seconds and kills the Unity process (`unity test --help`). 900 is a cap, not a measured
duration — a cold Library import may exceed it; that yields exit 6 = NO VERDICT (safe direction). Task 10(d) resets it.
PlayMode: at most ONE extra run per verify session (same command, `--mode PlayMode`), only on the final
iteration and only when the change touches PlayMode tests or MonoBehaviours.
Never pass `-batchmode`, `-quit`, `-projectPath`, `-runTests` after `--` (reserved; the CLI rejects them with exit 6).

## Exit codes (source: `unity skill show --path references/build-run-test.md`, not --help)
| Code | Meaning | Action |
|---|---|---|
| 0 | every test passed | PASS only if results.xml exists AND holds ≥1 `<testcase` — zero tests is not a pass |
| 8 | tests ran, ≥1 failed | real failure; list failing names from results.xml; do NOT retry |
| 6 | no verdict: compile error, licence, crash, unknown platform, `--timeout` | NO VERDICT. Not a pass, not a test failure. Do not retry, do not revert anything, do not attribute a cause. Report the last 40 output lines |
| 4 | precondition not met (e.g. no licence) | STOP (2b) |
| 2 | bad arguments — this skill's invocation is wrong | STOP, report the command line |
| other (1, 130, 143) | no verdict | STOP, report |
UNVERIFIED: where `error CS` lines surface on an exit-6 compile failure (stdout / stderr / `--format json`),
so a compile error cannot yet be told apart from infrastructure. Task 10(c).

## Reporting
Always print: `Verdict channel: unity CLI (batch EditMode[, PlayMode]) — exit <n> — <OUT>/results.xml`.
Stale-assembly probe: "not applicable — fresh batch process". That is REASONING about a new process
(no previously loaded DLL to keep), not a measurement. Task 10(c) is what tests it.

## Measured (fill from docs/PLAN_unity_cli_verify.md Task 10)
NOT YET MEASURED — every UNVERIFIED line above stands until this section holds dated results.
````

**Acceptance Criteria:**
- The frontmatter has exactly `name: unity-cli-verify`, a `description`, and `model-tier: light`.
- **The forbidden list matches the hook as built**: every blocking branch in `check-unity-cli.py` and every B-case family in the bats suite appears in it, and the prose-only items are labelled as such. Re-check this against the green Task 4 suite before Task 1 is marked done.
- Detector (d) is listed first, and the run section caps the work at one invocation per iteration.
- The project-lock behaviour, the detection method, the stale-assembly reasoning, the location of compile errors and the `unity watch` behaviour are each marked `UNVERIFIED` or "reasoning", with a pointer to Task 10.
- No sentence says a batch run is safe while an Editor is open.

**Callers:** `.claude/agents/unity-verifier.md` Step 4 State 2/3 (Task 6); `.claude/docs/skills-index.md` (Task 2); `docs/incidents/mcp-and-framework.md` (Task 8); the block message in `.claude/hooks/check-unity-cli.sh` (Task 4).

## Task 2: Register the skill in `skills-index.md`

**Files:** `.claude/docs/skills-index.md` (Modify)

**Steps:**
- [ ] Re-read the Core table (lines 5–48).
- [ ] Insert this row directly after the `mcp-preflight` row (line 39):
  `| \`unity-cli-verify\` | Headless compile/test verdict through the Unity 6 CLI when MCP is unavailable — preflight (binary → \`doctor --ci\` → Editor-open detection), one batch \`unity test\` per iteration, exit codes 0/8/6; MCP stays the live-Editor channel; \`unity command eval\` / \`unity mcp\` forbidden (hook-enforced) |`
- [ ] Do not touch `.claude/docs/auto-loaded-skills.md`.

**Test Type:** NoTest (markdown)

**Acceptance Criteria:** exactly one new row in the Core table, placed next to `mcp-preflight`. The table renders (the pipe count matches the header).

**Callers:** read by any session that follows the CLAUDE.md rule "check `skills-index.md` for a relevant skill first".

## Task 3: Write `check-unity-cli.bats` (RED)

**Files:** `.claude/hooks/tests/check-unity-cli.bats` (Add)

**Steps:**
- [ ] Copy the fixture shape from `check-write-via-bash.bats`:
  - `setup()` sets `UNITY_HOOK_STATE_DIR="$(mktemp -d)"`, `HOOK=".claude/hooks/check-unity-cli.sh"` and `JUDGE=".claude/scripts/check-unity-cli.py"`, then runs `cd "$BATS_TEST_DIRNAME/../../.."`.
  - Use its `run_cmd` helper, which builds the payload with `jq --arg` and so survives the quotes these commands contain.
  - Add `tool_name: "Bash"` to the payload, because this hook checks it.
- [ ] Every block test asserts **all three** of `[ "$status" -eq 2 ]`, `[[ "$output" == *"BLOCKED"* ]]` and `[[ "$output" == *"check-unity-cli"* ]]`. A silent exit 2 is not accepted.
- [ ] Note in a comment: `run_cmd` runs `bash`, which under bats may resolve to a newer bash than `/bin/bash`. The S1 test is what covers bash 3.2.
- [ ] Run `bats .claude/hooks/tests/check-unity-cli.bats`. It must fail, because neither file exists yet. Record the failure.

**Test Type:** bats

**Code Skeleton:** (these 11 `@test`s were run green against the Task 4 skeletons in a scratch copy; see Execution evidence)

```bash
#!/usr/bin/env bats

setup() {
    UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export UNITY_HOOK_STATE_DIR
    HOOK=".claude/hooks/check-unity-cli.sh"
    JUDGE=".claude/scripts/check-unity-cli.py"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

# NOTE: `bash` here may be a newer bash than /bin/bash under bats; S1 covers bash 3.2.
run_cmd() {
    local payload="${UNITY_HOOK_STATE_DIR}/payload.json"
    jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' > "$payload"
    run bash -c "bash $HOOK < '$payload'"
}

assert_blocked() {
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"check-unity-cli"* ]]
}

@test "S1: hook parses under /bin/bash (bash 3.2 on macOS)" {
    run /bin/bash -n "$HOOK"
    [ "$status" -eq 0 ]
}

@test "S2: judge source compiles (no __pycache__ written)" {
    run python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$JUDGE"
    [ "$status" -eq 0 ]
}

@test "F1: fails closed on the narrow regex when the judge file is missing" {
    mkdir -p "$UNITY_HOOK_STATE_DIR/hooks"
    cp .claude/hooks/check-unity-cli.sh .claude/hooks/_lib.sh "$UNITY_HOOK_STATE_DIR/hooks/"
    HOOK="$UNITY_HOOK_STATE_DIR/hooks/check-unity-cli.sh"   # ../scripts does not exist here
    [ ! -e "$UNITY_HOOK_STATE_DIR/scripts" ]
    for c in 'unity command eval x' 'unity cmd eval x' 'unity shell' 'unity pipeline install'; do
        run_cmd "$c"
        assert_blocked
        [[ "$output" == *"conservative"* ]]
    done
    run_cmd 'unity test . --mode EditMode'
    [ "$status" -eq 0 ]
}

@test "B1: blocks unity command eval" {
    run_cmd 'unity command eval "return Application.unityVersion;"'
    assert_blocked
}

@test "B30: blocks a substitution inside an unquoted heredoc (bash expands it)" {
    run_cmd $'cat <<EOF\n$(unity command eval x)\nEOF'
    assert_blocked
    run_cmd $'cat <<EOF\n`unity command eval x`\nEOF'
    assert_blocked
}

@test "B31: blocks a capitalised binary name (case-insensitive filesystem runs it)" {
    run_cmd 'Unity command eval x'
    assert_blocked
}

@test "B32: blocks coproc" {
    run_cmd 'coproc unity command eval x'
    assert_blocked
    run_cmd 'coproc U { unity command eval x; }'
    assert_blocked
}

@test "A14: allows listing flags the plugin skill passes on every call" {
    run_cmd 'unity command --caller plugin --skill unity-cli'
    [ "$status" -eq 0 ]
}

@test "A11: allows a commit whose quoted heredoc message names the ban" {
    run_cmd $'git commit -m "$(cat <<\'EOF\'\nfeat: block `unity command eval`\nEOF\n)"'
    [ "$status" -eq 0 ]
}

@test "A13: ignores a non-Bash payload even when it carries a banned command" {
    local payload="${UNITY_HOOK_STATE_DIR}/payload.json"
    jq -n '{tool_name:"Edit", tool_input:{command:"unity command eval x"}}' > "$payload"
    run bash -c "bash $HOOK < '$payload'"
    [ "$status" -eq 0 ]
}

@test "K3: warn mode downgrades the block" {
    UNITY_HOOK_MODE=warn run_cmd 'unity command eval x'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (downgraded from BLOCKED)"* ]]
}
```

The full case list follows. Each row is its own `@test` (55 rows: S1–S2, F1, B1–B32, A1–A16, K1–K4).

| # | Command | Expect |
|---|---|---|
| S1 | `/bin/bash -n` on the hook | rc 0 |
| S2 | Python `compile()` of the judge | rc 0 |
| F1 | hook copied without `../scripts`: `unity command eval x`, `unity cmd eval x`, `unity shell`, `unity pipeline install` → 2 with "conservative"; `unity test . --mode EditMode` → 0 | 2 / 0 |
| B1 | `unity command eval "return 1;"` | 2 |
| B2 | `unity cmd eval x` (alias) | 2 |
| B3 | `unity command eval_file snippet.cs` | 2 |
| B4 | `unity command create_gameobject --name X` (any name) | 2 |
| B5 | `unity --project-path /p command eval x` | 2 |
| B6 | `unity --json command eval x` | 2 |
| B7 | `unity command --detach --timeout 60 eval x` (flags before the name) | 2 |
| B8 | `FOO=1 unity command eval x` | 2 |
| B9 | `env UNITY_PROJECT_PATH=/p unity command eval x` | 2 |
| B10 | `cd /p && unity command eval x` | 2 |
| B11 | `true; unity command eval x` and `echo x \| unity command eval y` | 2 |
| B12 | `bash -c "unity command eval x"` and `sh -c 'unity command eval x'` | 2 |
| B13 | `eval "unity command eval x"` | 2 |
| B14 | `echo $(unity command eval x)` | 2 |
| B15 | `/Users/x/.unity/bin/unity command eval x` | 2 |
| B16 | a multi-line command whose second line is `unity command eval x` | 2 |
| B17 | `unity pipeline install --project-path /p` and `unity pipe install` (scope addition (b)) | 2 |
| B18 | `unity pipeline upgrade` (scope addition (b)) | 2 |
| B19 | `unity run /p --command my_cmd -- --count 3` | 2 |
| B20 | `unity shell` and `unity shell --protocol ndjson` | 2 |
| B21 | `unity mcp configure claude` and `unity mcp --project-path /p configure` (scope addition (a)) | 2 |
| B22 | `unity mcp` and `unity mcp --project-path /p` (bare: stdio server) (scope addition (a)) | 2 |
| B23 | `unity command -- eval x` (name after `--`) | 2 |
| B24 | `timeout 60 unity command eval x` and `gtimeout -k 5 60 unity command eval x` | 2 |
| B25 | `nice -n 10 unity command eval x` | 2 |
| B26 | `sudo -u root -g wheel unity command eval x` | 2 |
| B27 | `env -i PATH=/x unity command eval x`, `nohup unity command eval x`, `exec unity command eval x`, `command unity command eval x`, `time -p unity command eval x` | 2 |
| B28 | `stdbuf -oL unity command eval x` and `xargs -n 1 unity command eval` | 2 |
| B29 | `for i in 1; do unity command eval x; done`, `if true; then unity command eval x; fi`, `{ unity command eval x; }`, `! unity command eval x`, `while unity command eval x; do :; done` | 2 |
| B30 | `cat <<EOF` / `$(unity command eval x)` / `EOF` (unquoted heredoc: bash expands the body) and the backtick variant | 2 |
| B31 | `Unity command eval x` (macOS FS is case-insensitive, so `Unity` runs the binary) | 2 |
| B32 | `coproc unity command eval x` and `coproc U { unity command eval x; }` | 2 |
| A1 | `unity test /p --mode EditMode --report-format junit --output /tmp/r.xml --timeout 900` | 0 |
| A2 | `unity --non-interactive --no-banner test .` | 0 |
| A3 | `unity test . --filter command` (the word used as a filter value) | 0 |
| A4 | `unity build /p --target StandaloneOSX` | 0 |
| A5 | `unity run /p -- -executeMethod Builder.Build` | 0 |
| A6 | `unity status --project-path /p --json`, `unity doctor --ci`, `unity logs --tail 50` | 0 |
| A7 | `unity editors`, `unity editors running --format json`, `unity releases`, `unity --version`, `unity --help`, `unity help command` | 0 |
| A8 | `unity command`, `unity cmd --query eval`, `unity list`, `unity pipeline list` | 0 |
| A9 | `unity mcp --help`, `unity shell --help`, `unity plugin install plastic`, `unity vcs status` | 0 |
| A10 | `grep -rn "unity command eval" docs/` and `echo 'unity command eval'` | 0 |
| A11 | quoted (`<<'EOF'`) heredoc commit message containing `` `unity command eval` `` | 0 |
| A12 | `cat .claude/hooks/check-unity-cli.sh` (prefilter: `-unity-` is not the token `unity`) | 0 |
| A13 | non-Bash payload `{"tool_name":"Edit","tool_input":{"command":"unity command eval x"}}` (fails if the `tool_name = Bash` guard is removed) | 0 |
| A14 | `unity command --limit 5`, `unity command --sort name`, `unity command --caller plugin --skill unity-cli` | 0 |
| A15 | `unity mcp configure --list` and `unity mcp configure claude --dry-run` | 0 |
| A16 | `command -v unity` (a lookup, not execution) and `timeout 900 unity test /p --mode EditMode` | 0 |
| K1 | `DISABLE_HOOK_CHECK_UNITY_CLI=1` + B1 | 0 |
| K2 | `UNITY_HOOK_PROFILE=minimal` + B1 (documents that `standard` is skipped at minimal) | 0 |
| K3 | `UNITY_HOOK_MODE=warn` + B1 | 0 + `WARNING (downgraded from BLOCKED)` |
| K4 | unbalanced quote: `unity command eval "x` | 2 (fail-closed) |

**Acceptance Criteria:**
- The suite exists, runs, and fails before Task 4.
- Every `B*`, `F1` and `K4` case asserts the stderr marker.
- S1 runs `/bin/bash` explicitly, not `bash`.
- Each test name says what the case proves.

**Callers:** `.claude/hooks/tests/run-tests.sh` (globs `*.bats`).

## Task 4: Implement `check-unity-cli.sh` + `check-unity-cli.py` (GREEN)

**Files:** `.claude/hooks/check-unity-cli.sh` (Add); `.claude/scripts/check-unity-cli.py` (Add, **scope addition (e)**)

**Steps:**
- [ ] Re-read `check-write-via-bash.sh` (header, profile line) and `_lib.sh` (`unity_hook_block` at lines 116–128, the kill switch derived from the hook basename at line 50).
- [ ] Write both files from the skeletons below. The profile level is declared **before** `source _lib.sh`. The bash file contains **no heredoc** (`grep -c '<<' .claude/hooks/check-unity-cli.sh` prints `0`) and no inline Python.
- [ ] `chmod +x .claude/hooks/check-unity-cli.sh`. A missing exec bit makes the harness exit 126, and the hook silently does nothing. The `.py` file needs no exec bit, because it is invoked through `python3`.
- [ ] Run `bats .claude/hooks/tests/check-unity-cli.bats` until it is green. Never weaken a test to get there. If a case is genuinely wrong, change it and record why in the test name.
- [ ] Run `/bin/bash -n .claude/hooks/check-unity-cli.sh` (rc must be 0), and `shellcheck` if it is installed.
- [ ] Run `python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' .claude/scripts/check-unity-cli.py` (rc must be 0). This replaces `python3 -I -m py_compile`, which would write `.claude/scripts/__pycache__/`. That was confirmed in scratch: `-I` ignores `PYTHONPYCACHEPREFIX`, and a `__pycache__/` appeared.
- [ ] Time it: run `time` on B1 and A1 under `/bin/bash`. Both must stay under the hook's self-imposed **< 3000 ms performance budget**, which is not the harness timeout (see Task 5). Record the measured values.

**Fallback regex (judge unavailable only).** The fallback is deliberately narrow and conservative. It matches the word `unity`, then any later word `command|cmd` followed by a non-flag token, `pipe(line) install|upgrade`, `shell|mcp`, or `--command`, case-insensitively. In that fail-closed path only, it **also blocks allowed commands**. Verified examples: `unity mcp --help`, `unity shell --help`, `unity mcp configure --list`, `grep -rn "unity command eval" docs/`, `echo 'unity command eval'`, and any commit message naming the ban. These false positives are accepted **only** while the judge is missing or broken. The normal path (the judge) never blocks them; A9, A10, A11 and A15 assert that. It still allows `unity test …`, `unity status`, `unity command`, `unity command --limit 5`, `unity test . --filter command`, `unity editors running --format json` and `unity help command`.

**Test Type:** bats (Task 3's suite)

**Code Skeleton (bash; routes only):**

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict — standard keeps CLAUDE.md's "6 critical safety hooks" true
source "${SCRIPT_DIR}/_lib.sh"

# ============================================================================
# check-unity-cli.sh — BLOCKING HOOK (PreToolUse on Bash)
# Enforces the ban in docs/incidents/mcp-and-framework.md on the Unity CLI's live-Editor
# code channel. The judgement lives in .claude/scripts/check-unity-cli.py; this file routes.
# Keep this file free of heredocs and inline Python: bash 3.2 (macOS /bin/bash) mis-parses a
# heredoc inside $(...) whose body holds a backtick or "$(" — every call would exit 2.
# Does NOT call `unity` itself. Not airtight — accepted gaps in the incident doc.
# Exit: 2 = block, 0 = allow
# ============================================================================

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

W='[^A-Za-z0-9_-]'   # word boundary for `unity`; BSD grep has no portable \b
printf '%s\n' "$CMD" | grep -qiE "(^|$W)unity($W|\$)" || exit 0

JUDGE="${SCRIPT_DIR}/../scripts/check-unity-cli.py"
VERDICT=""
[ -r "$JUDGE" ] && VERDICT=$(CHECK_UNITY_CLI_CMD="$CMD" python3 -I "$JUDGE" 2>/dev/null)

case "$VERDICT" in
    ALLOW) exit 0 ;;
    "BLOCK "*) REASON="${VERDICT#BLOCK }" ;;
    *)  # judge missing/unreadable, python3 absent, or crashed: fail closed on a narrow regex
        if printf '%s\n' "$CMD" | grep -qiE \
            -e "(^|$W)unity$W(.*$W)?(command|cmd)[[:space:]]+[^-[:space:]]" \
            -e "(^|$W)unity$W(.*$W)?pipe(line)?[[:space:]]+(install|upgrade)" \
            -e "(^|$W)unity$W(.*$W)?(shell|mcp)($W|\$)" \
            -e "(^|$W)unity$W.*--command"; then
            REASON="judge unavailable (${JUDGE##*/} missing or failed) - conservative regex match"
        else
            exit 0
        fi ;;
esac

MSG="[check-unity-cli] ${REASON}

This is the Unity CLI's live-Editor code channel. The C# never becomes a file, so no
Edit|Write content hook sees it, and it skips the MCP pre-flight
(skills/core/mcp-preflight.md: instance pinning, dataPath check).

  Live Editor work      -> MCP: manage_scene / manage_gameobject / manage_components
  MCP bridge missing    -> restart the session; do not substitute the CLI
  Headless compile/test -> unity test / unity build (skills/core/unity-cli-verify.md)

Do not route around this block. Rule: docs/incidents/mcp-and-framework.md"
unity_hook_block "$MSG"
```

**Code Skeleton (Python judge):**

```python
#!/usr/bin/env python3
# check-unity-cli.py — judge for .claude/hooks/check-unity-cli.sh (invoked by it, via `python3 -I`).
# Input: the Bash command in env CHECK_UNITY_CLI_CMD (never argv). Output: exactly one stdout line,
# "ALLOW" or "BLOCK <reason>"; exit code 0. Any other outcome (crash, no output) makes the hook
# fall back to its narrow regex, i.e. fail closed.
import os, re, shlex

SHELLS   = {"bash", "sh", "zsh", "dash", "ksh"}
KEYWORDS = {"do", "then", "else", "elif", "{", "!", "while", "until", "if", "for", "coproc"}   # segment starts
# wrapper -> (its flags that take a separate value, positional operands to skip before the command)
WRAPPERS = {
    "env":     ({"-u", "--unset", "-C", "--chdir", "-P"}, 0),
    "command": (set(), 0),
    "exec":    ({"-a"}, 0),
    "time":    ({"-f", "--format", "-o", "--output"}, 0),
    "nohup":   (set(), 0),
    "nice":    ({"-n", "--adjustment"}, 0),
    "sudo":    ({"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from",
                 "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "--other-user",
                 "-T", "--command-timeout"}, 0),
    "timeout": ({"-s", "--signal", "-k", "--kill-after"}, 1),                    # then DURATION
    "stdbuf":  ({"-i", "--input", "-o", "--output", "-e", "--error"}, 0),
    "xargs":   ({"-n", "--max-args", "-I", "-L", "--max-lines", "-P", "--max-procs", "-s",
                 "--max-chars", "-d", "--delimiter", "-E", "-a", "--arg-file"}, 0),
}
WRAPPERS["gtimeout"] = WRAPPERS["timeout"]
ALIASES      = {"cmd": "command", "pipe": "pipeline"}
GLOBAL_VALUE = {"--format", "--color", "--proxy", "--project-path"}
CMD_VALUE    = {"--project-path", "--runtime", "--runtime-path", "--timeout", "--format", "--color", "--proxy"}
CMD_OPTVALUE = {"--detail", "--query", "--tag", "--group_by", "--sort", "--order",
                "--offset", "--limit", "--caller", "--skill"}                     # `unity command --help`
MCP_VALUE    = {"--project-path", "--runtime", "--runtime-path", "--server", "--format", "--color", "--proxy"}
ASSIGN  = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?[ \t]*(['\"\\]?)(\w+)['\"]?[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)

def substitutions(s, quotes=True):          # $(...) and `...` outside single quotes (quotes=False: heredoc body)
    out, i, n, sq, dq = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if c == "\\" and not sq: i += 2; continue
        if quotes and c == "'" and not dq: sq = not sq
        elif quotes and c == '"' and not sq: dq = not dq
        elif not sq and c == "`":
            j = s.find("`", i + 1)
            if j < 0: break
            out.append(s[i+1:j]); i = j
        elif not sq and s.startswith("$(", i):
            d, j = 1, i + 2
            while j < n and d:
                d += {"(": 1, ")": -1}.get(s[j], 0); j += 1
            out.append(s[i+2:j-1]); i = j - 1
        i += 1
    return out

def positional(args, value=frozenset(), optvalue=frozenset()):
    # Optional-value flags take the next token unless it starts with "-" (Commander-style; inferred
    # from the --help format, not measured). After "--" the next token IS the positional.
    k = 0
    while k < len(args):
        a = args[k]
        if a == "--": return k + 1 if k + 1 < len(args) else None
        if a.startswith("-"):
            if "=" not in a and a in value: k += 2; continue
            if "=" not in a and a in optvalue and k + 1 < len(args) and not args[k+1].startswith("-"): k += 2; continue
            k += 1; continue
        return k
    return None

def judge_unity(args):
    k = positional(args, GLOBAL_VALUE)
    if k is None: return None
    sub, rest = ALIASES.get(args[k], args[k]), args[k+1:]
    helping = any(a in ("-h", "--help") for a in rest)
    if sub == "command":
        j = positional(rest, CMD_VALUE, CMD_OPTVALUE)
        if j is not None: return f"`unity command {rest[j]}` runs Editor-side code (eval/eval_file run arbitrary C#) in a live Editor"
    if sub == "pipeline":
        j = positional(rest)
        if j is not None and rest[j] in ("install", "upgrade"):
            return f"`unity pipeline {rest[j]}` installs com.unity.pipeline (opens the eval channel) by writing Packages/manifest.json from Bash"
    if sub == "run":
        pre = rest[:rest.index("--")] if "--" in rest else rest
        if any(a == "--command" or a.startswith("--command=") for a in pre):
            return "`unity run --command` is the same Pipeline command channel and reuses an Editor already open on the project"
    if sub == "shell" and not helping:
        return "`unity shell` is a REPL whose commands arrive on stdin, where no hook can read them"
    if sub == "mcp" and not helping:
        j = positional(rest, MCP_VALUE)
        if j is None:
            return "bare `unity mcp` starts a stdio MCP server exposing the live Editor's commands as tools (a second Unity MCP channel)"
        if rest[j] == "configure" and any(a in ("--list", "--dry-run") for a in rest):
            return None
        return f"`unity mcp {rest[j]}` writes MCP server config for an AI client (only `configure --list` / `--dry-run` are read-only)"
    return None

def judge_segment(t, depth):
    i = 0
    while i < len(t):
        w = t[i]
        if w.lower() == "coproc" and i + 2 < len(t) and t[i+2] == "{": i += 2; continue   # coproc NAME { … }
        if w.lower() in KEYWORDS or ASSIGN.match(w): i += 1; continue
        name = os.path.basename(w).lower()
        if name not in WRAPPERS: break
        vflags, operands = WRAPPERS[name]
        i += 1
        while i < len(t) and t[i].startswith("-"):
            f = t[i]; i += 1
            if f == "--": break
            if name == "command" and f in ("-v", "-V"): return None      # `command -v unity` is a lookup
            if "=" not in f and f in vflags: i += 1
        i += operands                                                    # timeout's DURATION
    if i >= len(t): return None
    head, rest = os.path.basename(t[i]).lower(), t[i+1:]   # case-insensitive FS: `Unity` runs unity
    if head in SHELLS:
        for k, a in enumerate(rest):
            if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", a) and k + 1 < len(rest):
                return judge(rest[k+1], depth + 1)
        return None
    if head == "eval": return judge(" ".join(rest), depth + 1)
    return judge_unity(rest) if head == "unity" else None

def judge(s, depth=0):
    if depth > 4: return None
    bodies = [m.group(3) for m in HEREDOC.finditer(s) if not m.group(1)]   # unquoted: bash expands $( ) / ` `
    s = HEREDOC.sub("<<HEREDOC", s)         # heredoc body = data, not commands (gap: `bash <<EOF`)
    for sub in substitutions(s) + [x for b in bodies for x in substitutions(b, quotes=False)]:
        r = judge(sub, depth + 1)
        if r: return r
    lx = shlex.shlex(s.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lx.whitespace_split, lx.commenters = True, ""
    seg = []
    for tok in list(lx) + [";"]:
        if tok and set(tok) <= set(";&|()"):
            r = judge_segment(seg, depth); seg = []
            if r: return r
        else:
            seg.append(tok)
    return None

def main():
    raw = os.environ.get("CHECK_UNITY_CLI_CMD", "")
    try:
        r = judge(raw)
    except ValueError:                       # unbalanced quotes: fail closed on the narrow pattern
        r = ("unparseable command naming a banned unity subcommand - blocked conservatively"
             if re.search(r"\bunity\b.*\b(command|cmd|shell|pipeline|pipe|mcp)\b", raw, re.S | re.I) else None)
    print("BLOCK " + r if r else "ALLOW")

main()
```

**Acceptance Criteria:**
- The full Task 3 suite is green, including S1, S2, F1, A13 and B30–B32.
- `/bin/bash -n .claude/hooks/check-unity-cli.sh` returns 0.
- The Python compile check on `.claude/scripts/check-unity-cli.py` returns 0.
- `grep -c '<<' .claude/hooks/check-unity-cli.sh` prints `0`.
- The hook is executable (`test -x`) and declares `HOOK_PROFILE_LEVEL="standard"` before sourcing `_lib.sh`.
- Neither file ever invokes `unity`.
- The command reaches the judge through the environment, never through argv.
- Every block prints `BLOCKED: [check-unity-cli] …` to stderr through `unity_hook_block`.
- The measured runtime under `/bin/bash` on B1 and A1 is recorded and is within the self-imposed < 3000 ms performance budget.
- **Pre-implementation evidence (scratch copy of these exact skeletons, 2026-10-15):**
  - `/bin/bash -n` rc 0; compile check rc 0; `grep -c '<<'` prints 0.
  - 104 command strings run through the judge with 0 mismatches.
  - The 11 skeleton `@test`s pass. Run against v2's code, F1, B30, B31 and B32 fail.
  - A13 fails once the `tool_name` guard is removed.
  - The fallback cases behave as described, using `/usr/bin/grep` (BSD grep 2.6.0).
  - B1 and A1 end to end: at most 34 ms and 32 ms over 5 runs.
  
  See Execution evidence. The real Task 4 run must reproduce this in the repo.

**Callers:**
- `check-unity-cli.sh`: registered by the user in `.claude/settings.json` (Task 5), and exercised by `.claude/hooks/tests/check-unity-cli.bats` (Task 3).
- `check-unity-cli.py`: invoked by `.claude/hooks/check-unity-cli.sh`.

## Task 5: Register the hook in `settings.json` **[USER ACTION]**

**Files:** `.claude/settings.json` (Modify, **user only**; `check-config-protection.sh` blocks Claude)

**Steps (user):**
- [ ] Add this object to the `hooks.PreToolUse` array, directly after the existing `check-write-via-bash.sh` entry (its `command` is on line 75):

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-unity-cli.sh",
      "timeout": 5,
      "statusMessage": "Checking for banned Unity CLI channel (command eval)..."
    }
  ]
}
```

- [ ] Restart the Claude Code session. Hook config is read at session start.

**Timeout unit.** The `timeout` field is in **seconds**. That is per the Claude Code hook docs; it is not measured in this repo. No file in this repo states the unit: `.claude/docs/` and `README.md` were searched for "timeout". The only hits are bare `"timeout": 3000` examples, in `setup-checklist.md:24` and `README.md:1629`. `5` gives the hook a 5 s harness cap, well above its < 3000 ms budget. The sibling entries' `3000` / `5000` values are likely a misreading of the unit as milliseconds. That was observed and **not** touched (see Known gaps).

**Until this is done, the hook does nothing.** The script sits on disk, the bats suite is green, and nothing is enforced. This step can happen at any time after Task 4, including before or after Task 8. Task 9 V3 confirms the registration by reading the file and reconciles the README pending entry either way.

**Test Type:** NoTest (config, user-owned)

**Acceptance Criteria:** `settings.json` contains exactly one entry whose `command` ends in `check-unity-cli.sh`, under a `matcher: "Bash"` object in `PreToolUse`.

**Callers:** the Claude Code harness.

## Task 6: Rewrite the no-MCP branches of `unity-verifier.md` Step 4

**Files:** `.claude/agents/unity-verifier.md` (Modify). State 3 is **scope addition (f)**. The outcomes, exit-condition and report edits are **scope addition (c)**.

**Steps:**
- [ ] Re-read the whole file:
  - Step 4 is lines 63–104; line 65 already points at `mcp-preflight.md`.
  - Step 5 is lines 106–110.
  - Exit Conditions are lines 112–121, and Final Report is lines 123–147.
  - Frontmatter line 6 already has `Bash`; do not touch it.
- [ ] Re-read `.claude/skills/core/mcp-preflight.md`, States 2 (lines 55–76) and 3 (lines 80–93).
- [ ] Replace lines 96–102 (State 2 **and** State 3) with the text below. State 3 line 101 also says "Fall back to dotnet CLI silently". If only State 2 changes, that fallback survives in the template's default state. If the user rejects (f), leave lines 100–102 and record that under Known gaps.
- [ ] Leave State 1 (lines 67–94) and line 104 unchanged, and add the CLI qualifier shown below directly after line 104.
- [ ] Update Exit Condition 3 (line 117), line 119, and the Final Report template (lines 144–147).

**Precedence over `mcp-preflight.md` (part of the semantics change, needs approval under (c)/(f)):**
- Preflight governs **MCP operations**. Its State 2 forbids them; its State 3 switches to code-only. Step 4's verdict channel is outside the preflight's text, so the new branches **refine** the preflight rather than override it, and neither branch ever starts an MCP call or MCP write.
- Branch 2b keeps the preflight's STOP: it prints the State 2 checklist when in State 2, then ends the loop with `NOT VERIFIED`. A subagent cannot wait for a user reply, so the decision goes back to the calling command.
- The one real override is State 3. The preflight's "continue silently" no longer ends in a fallback verdict; it ends in either a 2a CLI verdict or a 2b `NOT VERIFIED`.

**Runtime cap (decided here):**
- One batch `unity test` (EditMode, `--timeout 900`) per Step 5 iteration.
- PlayMode at most once per verifier run, only on the final iteration (Step 3 applied no fix, or this is iteration 3), and only when the change touches PlayMode tests or MonoBehaviours.
- A NO VERDICT (exit 6, which includes a timeout) stops the loop.
- New worst case: 3 × 15 min EditMode + 1 × 15 min PlayMode = **60 min**. v1 allowed 3 × 2 × 30 min = 180 min.
- Justification: Step 5 can loop 3 times, and EditMode is the cheapest run that yields a compile verdict. 900 s is a cap, not a measurement. Task 10(d) records the real cold and warm durations and resets it.

**Test Type:** NoTest (agent prompt). It is measured by Task 9 V5/V6, not by bats.

**Code Skeleton:** (replacement for lines 96–102)

```markdown
**State 2 (disconnected) and State 3 (not installed) — no live-Editor verdict is available.**
Read and apply `.claude/skills/core/unity-cli-verify.md`; run its preflight. The previous non-Unity
fallback is removed: nobody checked that it produced a Unity compile verdict.
`mcp-preflight.md` still governs MCP: no MCP call and no MCP write is started on either branch below.

- **2a — preflight clean** (binary present, `doctor --ci` exit 0, no Editor detected on this
  project by any of the skill's four detectors): run ONE batch `unity test` per iteration
  (EditMode, `--timeout 900`). PlayMode: one extra run, only on the final iteration (Step 3
  applied no fix, or this is iteration 3) and only when the change touches PlayMode tests or
  MonoBehaviours. Read the exit code per the skill: `0` with ≥1 test case → pass · `8` → real
  test failures · `6` → **NO VERDICT**: not a pass, not a test failure — revert nothing, attribute
  no cause, put the last 40 output lines in the report, and stop the loop. Stale-assembly probe:
  write "not applicable — fresh batch process (reasoning, not measured)".
- **2b — an Editor IS open on this project (any detector positive or erroring), or the `unity`
  binary is missing, or `doctor --ci` fails:** STOP. In State 2, print the `mcp-preflight.md`
  State 2 checklist. Report `NOT VERIFIED — <reason>` and end the loop; the calling command
  decides what happens next. Do not start a batch run against an open project (its behaviour
  there is unmeasured), never run a named `unity command` (incl. `eval`) or `unity mcp`
  (blocked by `check-unity-cli.sh`), and never substitute a non-Unity build.

The Editor-open check is prose, not enforced — no hook runs it. Report which state (2/3) and
which branch (2a/2b) you were in.
```

Add after line 104: `On the CLI path, only exit 8 counts as "tests fail" for the rule above. Exit 6 is NO VERDICT: revert nothing and do not attribute a cause. Whether an exit-6 compile error can be traced to a Step 3 fix is unmeasured.` (That finer rule stays UNVERIFIED pending Task 10(c).)

Exit Condition 3 becomes: `All tests pass, the verdict is current (State 1: the assembly probe confirmed the DLL; State 2a: a fresh batch unity test exited 0 with ≥1 test case), and no critical issues remain`.

Line 119 becomes: `**A STALE ASSEMBLY, NOT VERIFIED or NO VERDICT result satisfies none of the three.**`

In the Final Report template, under `### Test Results`, add: `- Verdict channel: MCP (live Editor) | unity CLI (batch, exit <n>) | none — NOT VERIFIED (<reason>)`

**Acceptance Criteria:**
- `grep -n dotnet .claude/agents/unity-verifier.md` returns nothing.
- Step 4 names the skill by its path.
- 2a and 2b both exist; 2b says STOP and names `NOT VERIFIED`.
- Exit 6 says "revert nothing" and "stop the loop".
- The one-run-per-iteration cap and `--timeout 900` appear.
- `NOT VERIFIED` and `NO VERDICT` satisfy no exit condition.
- The report template has a `Verdict channel:` line.
- State 1 (lines 67–94) is byte-identical to before.

**Callers:** `/implement`, `/fix`, `/qa`, `/ralph` and `/orchestrate` (per the agent description, line 3). How they handle `NOT VERIFIED` / `NO VERDICT` is unexamined (scope addition (c)).

## Task 7: Hook docs under `.claude/`

**Files:** `.claude/docs/hooks-blocking.md`, `.claude/docs/hook-profiles.md`, `.claude/hooks/tests/README.md` (all Modify)

**Steps:**
- [ ] `hooks-blocking.md`: insert this row after the `check-ls-grep.sh` row (line 40):
  `| \`check-unity-cli.sh\` (PreToolUse Bash) | The Unity CLI's live-Editor code channel: \`unity command <name>\` for any name (alias \`cmd\`; \`eval\`, \`eval_file\`, …, also after \`--\`), \`unity run --command\`, \`unity shell\`, \`unity mcp\` (bare starts a stdio MCP server; \`configure\` allowed only with \`--list\`/\`--dry-run\`), \`unity pipeline install\|upgrade\` (alias \`pipe\`). Parses past env assignments, wrapper commands with their own flags (\`env\`, \`exec\`, \`command\`, \`time\`, \`nohup\`, \`nice -n N\`, \`sudo -u U\`, \`timeout\`/\`gtimeout\`, \`stdbuf\`, \`xargs\`), shell keywords (\`do\`, \`then\`, \`{\`, \`!\`, \`coproc\`, …), global flags with values, separators, newlines, \`bash -c\`/\`eval\`, \`$(…)\`, absolute binary paths, any letter case of the binary name; quoted-delimiter heredoc bodies are data, while \`$(…)\`/backticks inside unquoted heredoc bodies are scanned. Allowed: bare \`unity command\` listing (incl. \`--limit\`/\`--caller\`/\`--skill\`), \`test\`, \`build\`, \`run\` without \`--command\`, \`status\`, \`doctor\`, \`editors running\`, \`logs\`. Judge: \`.claude/scripts/check-unity-cli.py\`; if it is missing or fails, the hook fails closed on a narrow regex (which also blocks some allowed commands, e.g. \`unity mcp --help\`). Never calls \`unity\` itself. Not airtight — accepted gaps in \`docs/incidents/mcp-and-framework.md\`. Skill: \`skills/core/unity-cli-verify.md\` |`
- [ ] `hook-profiles.md`: add this row to the `standard` table:
  `| \`check-unity-cli.sh\` | **PreToolUse Bash.** Blocks the Unity CLI's live-Editor code channel (\`unity command <name>\`, \`run --command\`, \`shell\`, \`mcp\`, \`pipeline install\|upgrade\`). \`standard\`, not \`minimal\`: it enforces a policy rather than preventing file corruption, and \`minimal\` stays the 6 safety hooks CLAUDE.md counts — so under \`minimal\` the eval ban is prose only. Disable: \`DISABLE_HOOK_CHECK_UNITY_CLI=1\` |`
- [ ] `hooks/tests/README.md`: add `| \`check-unity-cli.bats\` | \`check-unity-cli.sh\` + \`.claude/scripts/check-unity-cli.py\` |` to the "Test files" table.

**Test Type:** NoTest (markdown)

**Acceptance Criteria:** each file gains exactly one row, and the tables still render. No row claims the hook is registered (Task 9 confirms that). The `minimal` table is unchanged.

**Callers:**
- `hooks-blocking.md` is read on demand when a hook blocks (CLAUDE.md Reference section).
- `hook-profiles.md` is read on demand through CLAUDE.md "Full profile docs: `.claude/docs/hook-profiles.md`".
- `hooks/tests/README.md` is read by anyone running the suite.

(This deliberately does not cite `hooks-blocking.md` line 46 as an import; see Known gaps.)

## Task 8: Incident doc + README: accurate reason, enforcement, gaps

**Files:** `docs/incidents/mcp-and-framework.md` (Modify), `README.md` (Modify). The eval paragraph and the table row are **scope addition (d)**; the pending entry is required.

**Steps:**
- [ ] **First, read `.claude/settings.json`** and grep it for `check-unity-cli`. Record whether the hook is already registered (Task 5 may have happened already). Also confirm two facts the new wording relies on: `block-scene-edit.sh` is matched on `Edit|Write` only, and there is no `mcp__UnityMCP__*` matcher anywhere.
- [ ] Re-read `mcp-and-framework.md` lines 22–33 and README lines 1254–1262, 920–930 and 1615–1625. README line 1621 warns against a stale pending entry; this task must not create one.
- [ ] Replace the eval bullet (lines 25–33) with the text below.
- [ ] (d) README item 2 (lines 1258–1262): apply the same correction in short form. Remove "skips the MCP tools' pre-flight and `block-scene-edit.sh` at once", and say instead that nothing looked at the Bash call until `check-unity-cli.sh`.
- [ ] (d) README Blocking table (near line 928): add a `check-unity-cli` row after `check-write-via-bash`, condensed from Task 7.
- [ ] README "Currently pending" (line 1619):
  - If the hook is **not** registered, change `none` to name `check-unity-cli.sh`, with the Task 5 snippet in the shape README already shows.
  - If it **is** registered, leave "none" untouched.
  - Either way, Task 9 V3 reconciles the entry.

**Test Type:** NoTest (markdown)

**Code Skeleton:** (replacement eval bullet)

```markdown
- **`unity:unity-cli`'s `unity command eval` is forbidden here — enforced since 2026-10-15 by
  `check-unity-cli.sh`** (judge: `.claude/scripts/check-unity-cli.py`). `eval` (and every named
  `unity command`, plus `unity run --command` and `unity shell`) runs C# inside a live Editor, issued
  as a Bash command. That is an unreviewed channel: the C# never becomes a file, so no `Edit|Write`
  content hook sees it, and it skips the MCP pre-flight in `skills/core/mcp-preflight.md` (instance
  pinning, `dataPath` check) — which is a skill, not a hook. *Corrected 2026-10-15:* this note used to
  say eval bypasses `block-scene-edit.sh`; that hook is matched on `Edit|Write` and never ran on Bash,
  so there was nothing to bypass. The real gap was that nothing looked at the Bash call at all. Live
  Editor work → `manage_scene` / `manage_gameobject` / `manage_components`; bridge absent → restart
  the session. Headless compile / test / build → `skills/core/unity-cli-verify.md` (batch `unity test`,
  only with no Editor open on the project). Also blocked: bare `unity mcp` (starts a stdio MCP server
  exposing the Editor's commands — a second Unity MCP channel) and `unity mcp configure` except
  `--list`/`--dry-run`; `unity pipeline install|upgrade` (writes `Packages/manifest.json` from Bash and
  opens the eval path). `com.unity.pipeline` is still not installed here — an accident of packaging,
  not the reason for the ban. Handled since v3 of the plan: any letter case of the binary name
  (`Unity …` runs the binary on a case-insensitive filesystem) and `$(…)` / backticks inside an
  unquoted heredoc body (bash expands them).
  **The hook is not airtight. Accepted gaps** (each kept because closing it costs more than it buys):
  variable or alias indirection (`U=unity; $U command eval`, a renamed symlink) — needs shell
  evaluation; a quote-split binary name (`u""nity command eval x`) — the bash prefilter matches the
  literal word `unity` before the judge runs (the judge itself would block it), and dropping the
  prefilter would start python3 on every Bash call; scripts on disk (`bash run.sh`) — `.sh` is not a
  governed extension in `check-write-via-bash.sh` either; a heredoc fed to a shell (`bash <<EOF`) —
  heredoc bodies are treated as data (only their `$(…)`/backticks are scanned) so commit messages
  pass; `xargs`-appended arguments (`echo eval | xargs unity command`) — the name is not in the
  command string; `env -S "…"` split strings and wrappers the judge does not model (`arch`,
  `caffeinate`, `script`, unknown value-taking flags) — rare, extendable per case; other interpreters
  (`python -c "subprocess.run(['unity', …])"`); anything typed outside Claude's Bash tool; the
  `minimal` profile, where the hook does not run; `unity close`, `unity watch`, `unity setup` /
  `unity skill install` (prose-only bans in the skill); `unity vcs` / `cm` remote writes, which
  `block-git-push.sh` does not cover; and MCP's own `execute_code`, a different channel outside this
  hook's reach.
```

**Acceptance Criteria:**
- Neither file says eval bypasses `block-scene-edit.sh` (the README part applies if (d) is approved).
- Both files name `check-unity-cli.sh`.
- The incident doc carries the accepted-gap list, with a justification per item, including the quote-split binary name.
- The README pending entry matches what `settings.json` showed when this task ran.
- `.claude/CLAUDE.md` lines 43 and 92 still match the docs (no edit needed).

**Callers:** `.claude/CLAUDE.md` lines 43 and 92 link to the incident doc.

## Task 9: In-repo verification

**Files:** none modified, except the README pending-entry reconciliation in V3.

**Steps:**
- [ ] **V1:** Run `.claude/hooks/tests/run-tests.sh`. The whole suite must be green, not just the new file. Record the counts. The S1 (`/bin/bash -n`) and F1 (fail-closed without the `.py`) tests must be among the passes.
- [ ] **V2:** Check that `test -x .claude/hooks/check-unity-cli.sh` passes, that `/bin/bash -n` on the hook gives rc 0, and that the Python compile check on the judge gives rc 0. Confirm `grep -c '<<'` on the hook prints `0`. Include the timing recorded in Task 4.
- [ ] **V3:** Read `.claude/settings.json`. Then reconcile the README:
  - **Registered, and README lists it pending:** delete the README entry in the same change.
  - **Not registered, and README says "none":** add the entry (Task 8 shape), report "hook unregistered — enforcement OFF", and stop. Do not mark this verified.
  - **Registered:** in a **new** session, ask for `unity command eval "return 1;"` and confirm the harness shows the `[check-unity-cli]` block.
- [ ] **V4:** `.claude/tests/pipeline-dry-run/` is **not run**. The hook refuses one Bash channel and changes no gate order and no state-file lifecycle. The verifier change alters an agent's verdict and adds one stop outcome, not a pipeline's step order. Record this judgement in the report.
- [ ] **V5:** Run `.claude/tests/reviewer-fixtures/`, as `docs/incidents/test-layers.md` requires for an agent-prompt edit. Run it against the verifier's Step 2 checklist (unchanged) as a regression check.
- [ ] **V6:** Run a behavioural probe of the new Step 4 here. Spawn `unity-verifier` with "execute Step 4 only; MCP tools are absent in this session". This repo has a `unity` binary but no project.
  - Expected: 2b (or a 2a run that ends with exit ≠ 0), reported as `NOT VERIFIED` / `NO VERDICT`, with a `Verdict channel:` line.
  - Check the transcript's Bash calls: no non-Unity build, no named `unity command`, no `unity mcp`, and at most one `unity test`.
  - Run it twice; it is non-deterministic.

**Test Type:** Verification

**What each result proves, and what it does NOT prove:**

| Check | Proves | Does NOT prove |
|---|---|---|
| V1 bats green | the hook's exit code and stderr on the listed strings; the hook parses under `/bin/bash`; it fails closed without the `.py` | that the hook runs in a live session; anything about the verifier prompt; that untested spellings are caught |
| V2 | the script is executable, parses under bash 3.2, has no heredoc, the judge compiles, and both fit the < 3000 ms performance budget | behaviour |
| V3 file read | the user registered it, and the README pending entry agrees | that the harness fires it (the live probe covers that) |
| V3 live probe | the harness runs the hook on a real Bash call | coverage of the accepted gaps |
| V5 reviewer-fixtures | Step 2 review behaviour did not regress | anything about Step 4: the fixture has no MCP or CLI dimension |
| V6 probe | the prompt steers away from the non-Unity build, eval and `unity mcp`, respects the run cap, and reports a channel when no project exists | 2a behaviour on a real project; one or two PASSes do not rule out a failure rate |

**Acceptance Criteria:** V1–V3 and V5–V6 are recorded with dates and outputs, and the V4 judgement is written down. If V3 shows the hook unregistered, the plan stays `Active` with Task 5 open, and README carries the pending entry.

**Callers:** —

## Task 10: Real-project measurement **[BLOCKED — needs real Unity project]**

**Files:** `.claude/skills/core/unity-cli-verify.md` (Modify: fill in "## Measured" and resolve each `UNVERIFIED` line).

**Steps (run in a real project generated by this template, so without `com.unity.pipeline`):**
- [ ] **(a) Detection.** Open a GUI Editor on the project and record:
  - (d) the full output of `unity editors running --format json`: does it list this Editor at all, and which field carries the project path? Is that path absolute, and are symlinks resolved, so it can be compared to `$P`?
  - (a) the output of `unity status --project-path "$P" --json`
  - (b) whether `Temp/UnityLockfile` exists
  - (c) the result of `pgrep -ifl projectpath`

  Repeat with the Editor closed. Keep only the detectors that actually distinguish the two states, and record the comparison rule for (d).
- [ ] **(b) Project lock.** With the Editor open, run the skill's `unity test` once with `--timeout 300`. Record the exit code, the output, and whether the open Editor was affected (prompt, crash, reimport). Do this on a throwaway copy of the project.
- [ ] **(c) Stale assembly / exit 6.** With the Editor closed, plant a compile error in an existing game C# source file, then run `unity test`. The CLI docs predict exit 6, not 0 and not 8. Record the actual code and where `error CS` appears (stdout, stderr or `--format json`). This decides whether the verifier may ever trace an exit 6 to a Step 3 fix.
- [ ] **(d) Pass + duration.** On a clean project, record exit 0, that `results.xml` exists at `--output`, and its `<testcase` count. Record the wall-clock time with a cold `Library/` and a warm one, and reset the 900 s default from those numbers.
- [ ] **(e) Fail.** Add one deliberately failing test. Record exit 8 and the failing name in the junit report.
- [ ] **(f) `unity watch`.** Optional, on a throwaway copy, with an external timeout: run `unity --non-interactive watch test` and record whether it refuses, exits, or loops. This resolves the unverified `watch` claim.
- [ ] Write the dated results into the skill's "## Measured" section. Then turn each `UNVERIFIED` line into a measured statement or a corrected rule. If (b) shows a batch run is harmless with an Editor open, that **still** does not lift the 2b STOP by itself; it goes back to the user as a scope decision.

**Test Type:** Verification

**Acceptance Criteria:** (a)–(e) are recorded with the date, Unity version and CLI version, and (f) is recorded or explicitly skipped. The skill has no `NOT YET MEASURED` left, or each remaining item has a written reason.

**Callers:** —

## Verification

| Run | By | Where | Result proves | Result does NOT prove |
|---|---|---|---|---|
| `.claude/hooks/tests/run-tests.sh` (incl. S1 `/bin/bash -n`, S2 judge compile, F1 fail-closed) | Claude | this repo | hook exit codes and stderr on the tested strings; bash 3.2 parse; fail-closed when the judge is missing | live enforcement; prompt behaviour; the accepted gaps |
| `/bin/bash -n` + `test -x` + `grep -c '<<'` + Python compile (V2) | Claude | this repo | the files are executable/parseable and the heredoc defect class is absent | behaviour |
| Read `settings.json` + live `unity command eval` probe in a new session | Claude, after the user's Task 5 | this repo | the hook is registered, the harness fires it, and the README pending entry is reconciled | coverage beyond the probe string |
| `.claude/tests/reviewer-fixtures/` | Claude | this repo | the Step 2 checklist did not regress | anything about Step 4's new branches |
| Step 4 behavioural probe (V6) | Claude | this repo, no project | the non-Unity build, eval and `unity mcp` are not used, the run cap holds, and a channel line is reported in the no-project case | the 2a path on real code; reliability (non-deterministic) |
| `.claude/tests/pipeline-dry-run/` | **not run** | — | — | judged unnecessary: no gate-order or state-file change |
| Task 10 (a)–(f) | user or Claude in a real project | real Unity project | detection, lock behaviour, exit codes, duration, the stale-assembly reasoning | other Unity or CLI versions; PlayMode, unless run |

A hook that exits 0 is not a compliance receipt. Only the explicit `[check-unity-cli]` block line counts as evidence that the hook looked at something.

## Known gaps / unverified assumptions

- **UNVERIFIED:** what a batch `unity test` does when an Editor already holds the project. Until Task 10(b), 2b says STOP.
- **UNVERIFIED:** whether `unity editors running` (detector (d)) lists a GUI Editor in a project without `com.unity.pipeline`, and how its project path compares to `$P`. The documentation says it should (process table, then ProjectVersion.txt fallback); this is not measured yet (Task 10(a)).
- **UNVERIFIED and probably false:** that `unity status` sees a GUI Editor without `com.unity.pipeline`. The lockfile and process checks are also unmeasured (Task 10(a)).
- **Reasoning, not measurement:** "stale-assembly probe not applicable" on the CLI path. Task 10(c) tests it.
- **UNVERIFIED:** where compile errors surface on exit 6. So on the CLI path an exit 6 is NO VERDICT with no revert and no attribution, until Task 10(c).
- **UNVERIFIED:** `unity watch` behaviour under `--non-interactive` or CI. One reviewer cited `build-run-test.md:318` as saying it refuses there, and neither the orchestrator nor an Explore pass could find that text. The ban rests only on `--help` ("re-runs a command each time project files change") (Task 10(f)).
- **Inferred, not measured:** the optional-value flag rule (the next token unless it starts with `-`) and the `--` handling in `positional()` follow Commander-style parsing, inferred from the `--help` format. Getting it wrong in the block direction is safe. In the allow direction, it could let a name pass that is swallowed as a flag value.
- **900 s timeout is a cap, not a measurement.** A cold `Library/` import may exceed it and yield NO VERDICT, which is the safe direction. Task 10(d) resets it.
- **Hook `timeout` units (per Claude Code hook docs; not measured in this repo):** seconds. The existing `settings.json` entries carry `"timeout"` values of 2000–30000 (lines 22–656; one existing entry, line 603, already uses `5`). Most are `3000` / `5000`, which would be 50–83 minutes if read as seconds. The same misreading appears in `setup-checklist.md:24` and `README.md:1629`. Observed, **not touched** (`settings.json` is user-owned). The new entry uses `5`.
- The fail-closed fallback regex (judge missing) also blocks some allowed commands, e.g. `unity mcp --help` and `grep "unity command eval"` (Task 4). This is accepted only on that path.
- The Editor-open check is prose. No hook enforces it.
- The hook does not run under the `minimal` profile, so the eval ban is prose-only there.
- The hook's accepted gaps are listed, with justifications, in the incident doc (Task 8).
- A core skill never appears in `auto-loaded-skills.md`. Agents reach `unity-cli-verify` only through the explicit pointer in `unity-verifier.md` and through `skills-index.md`, while the plugin's `unity:unity-cli` description is auto-loaded into every session.
- How `/implement`, `/fix`, `/qa`, `/ralph` and `/orchestrate` handle a `NOT VERIFIED` / `NO VERDICT` verifier result (stall vs stop vs retry) has not been examined (scope addition (c); out of scope).
- `verify-after-write.sh` and `stop-verify.sh` still run `dotnet build` (out of scope, noted).
- **Bats counts (snapshot, 2026-10-15):** 55 `.bats` files and 663 `@test`, measured with `find .claude/hooks/tests -name '*.bats' | wc -l` and `grep -h '^@test ' .claude/hooks/tests/*.bats | wc -l`. README says 49/595 (line 908), which is stale; it is not fixed here (out of scope). This plan's new suite (55 table rows) will raise both numbers.
- `.claude/docs/hooks-blocking.md` line 46 reads `@.claude/docs/hook-profiles.md`. CLAUDE.md says `@` imports resolve relative to the importing file's folder, so this form may load nothing. Observed, not fixed; how it actually resolves from `.claude/docs/` has not been measured.
- `.claude/docs/setup-checklist.md` still lists `check-write-via-bash.sh` as a manual step, although it is registered. Observed, out of scope.

## Corrections to the brief

1. **State 3 also falls back to dotnet.** `unity-verifier.md` line 101 reads "Fall back to dotnet CLI silently", so there are two such mentions in `.claude/agents/*.md`, not one. Task 6 changes both, which is scope addition (f).
2. **Exit codes 8 and 6 are not in `unity test --help`.** On 1.0.0-beta.13 they are documented in the CLI's embedded skill: `unity skill show` ("Exit codes") and `--path references/build-run-test.md` (around line 153). That source also defines 2 (bad arguments), 4 (precondition, e.g. licence), 130 and 143.
3. **`unity status` is not a reliable Editor-open detector here.** `unity editors running` is the CLI's documented detector that does not depend on the Pipeline package. `references/editors-install.md` (`unity skill show --path references/editors-install.md`, the `editors running` section) says: "Detection is cross-platform (process table plus each project's Pipeline lockfile), and the version falls back to a project's ProjectSettings/ProjectVersion.txt for editors without the Pipeline package." Its options are `--format`, `--verbose` and `--watch`, and `--watch` is never passed. It is detector (d), listed first. `status`, `Temp/UnityLockfile` and the process check remain as independent extras, and any positive means STOP.
4. **`unity logs` reads the Hub log file**, not the Editor or compile log. It is not a compile diagnostic.
5. **The real CLI surface differs from the brief's names.**
   - Aliases: `cmd` (for `command`) and `pipe` (for `pipeline`). `eval_file` exists alongside `eval`.
   - `unity run --command <name>` is a second route into Pipeline commands, and it reuses an open Editor. `pipeline upgrade` also writes the manifest.
   - **Bare `unity mcp` starts a stdio MCP server** (`unity mcp --help` Examples). `configure` writes client config, and `--list` / `--dry-run` are its read-only modes.
   - There is no top-level `uvcs` or `cm` in `--help`; the surface is `vcs`, with `unity uvcs` / `unity cm` passed through by the `plastic` plugin.
   - `job`, `recompile` (needs Pipeline, exits 7), `close` (no save), `watch`, `setup` and `skill` also exist.
6. **`auto-load-skills.sh` is a PostToolUse `Write|Edit` hook**, not a SessionStart generator, and it lists only `third-party/`, `plugins/`, `learned/` and `platform/` skills. `session-restore.sh` injects the list at SessionStart.
7. **`validate-plan-facts.sh` scans only `tasks.md` files** (or a file named explicitly), and only `.cs` / `.asmdef` task tokens. `Callers:` lines are kept anyway, as instructed.
8. **README.md must change, but only partly inside the approved scope.** The pending-list entry (line 1619) is required by README's own rule. The eval paragraph (lines 1258–1262) and the Blocking-table row are scope addition (d).
9. **`.claude/hooks/tests/README.md` has a per-file table** that needs a row (Task 7).
10. **The better bats fixture is in `check-write-via-bash.bats`.** Its `run_cmd` helper builds the payload with `jq --arg`.
11. **`check-ls-grep.sh` is registered with no matcher** and declares no `HOOK_PROFILE_LEVEL`. It is the pattern for stdin and tool-name parsing only. `check-write-via-bash.sh` is the pattern for the profile line.
12. **`reviewer-fixtures` cannot observe Step 4**, so the dedicated V6 probe is added.
13. **`unity plugin list` on this machine** shows the installable ids `plastic`, `licensingClient`, `ugs` and `ai`.
14. **v1's hook skeleton was a bash 3.2 syntax error** (reproduced by the orchestrator with `/bin/bash -n`, rc=2). An Explore subagent's counter-claim that it "is not reproducible" is invalid: its test script contained no backtick and no `"$("`, which are exactly the triggers.
15. **Helper convention, stated precisely.** `.claude/scripts/` holds the repo's helper `.py` files (`blender-mcp-bridge.py`, `check-duplicate-siblings.py`, `validate-generated-asmdefs.py`). However, no hook currently invokes a `.claude/scripts/*.py`. The `${SCRIPT_DIR}/../<dir>` lookup the new hook uses is the pattern of `inject-rule-pointers.sh:48–49` and `session-restore.sh:152–153`.
16. **v1's `positional()` let `unity command -- eval x` through**, because it returned "no positional" at `--`. Fixed in Task 4 and covered by B23.

### Critical Files for Implementation
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/agents/unity-verifier.md
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/check-write-via-bash.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/check-write-via-bash.bats
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/skills/core/mcp-preflight.md
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/docs/incidents/mcp-and-framework.md

## Execution evidence (v3)

All runs were on 2026-10-15, macOS (Darwin 24.6.0), only in the scratch directory `/private/tmp/claude-501/-Users-berkterek-Desktop-Github-unity-claude-ai-template-repo/d4ebf93a-f437-488e-8bdc-e6f1c1fa8ec0/scratchpad/r3/`. Nothing was written to the repo.

The scratch layout:
- `r3/hooks/check-unity-cli.sh`, plus `r3/hooks/_lib.sh` copied from the reviewer's `r2/`.
- `r3/scripts/check-unity-cli.py`.
- `r3/repo/.claude/{hooks,scripts,hooks/tests}` for bats.

`cmp` confirms the hook and judge in `r3/` and in `r3/repo/.claude/` are byte-identical to the Task 4 skeletons above. The bats file is the Task 3 skeleton above.

| # | Command | Result |
|---|---|---|
| 1 | `/bin/bash -n r3/hooks/check-unity-cli.sh` | rc 0 |
| 2 | `grep -c '<<' r3/hooks/check-unity-cli.sh` | `0` |
| 3 | `python3 -I -c 'compile(...)' r3/scripts/check-unity-cli.py` | rc 0 |
| 4 | `python3 -I -m py_compile r3/scripts/check-unity-cli.py` | rc 0, and it **wrote** `r3/scripts/__pycache__/…cpython-312.pyc` (`-I` ignores `PYTHONPYCACHEPREFIX`). This is why the plan uses the `compile()` form. The pycache was removed from scratch afterwards |
| 5 | Judge driver: each command string passed via `CHECK_UNITY_CLI_CMD=… python3 -I r3/scripts/check-unity-cli.py`. The strings were every command in the Task 3 B/A/K4 rows (multi-command rows split; 82 strings incl. B16, A11), the new B30 (both variants plus a `<<-`/apostrophe variant), B31 (plus `/…/UNITY`), B32 (both variants), allow extras A11b `<<"EOF"` / A11c `<<\EOF` with `$(unity command eval x)` in the body and A17 (unquoted body with plain text naming the ban), `u""nity command eval x`, and the reviewer's pass-2 extras P2a–P4d | **104 strings, 0 mismatches**. Every B/K4 string gave `BLOCK …`; every A string gave `ALLOW` |
| 6 | Hook end to end, `jq … \| /bin/bash r3/hooks/check-unity-cli.sh`: B1 `unity command eval "return 1;"` | rc 2, stderr `BLOCKED: [check-unity-cli] \`unity command eval\` runs Editor-side code…` |
| 7 | same: A1 `unity test /p --mode EditMode --report-format junit --output /tmp/r.xml --timeout 900` | rc 0 |
| 8 | same, `UNITY_HOOK_MODE=warn` + `unity command eval x` (K3) | rc 0, stderr `WARNING (downgraded from BLOCKED): [check-unity-cli] …` |
| 9 | same, `DISABLE_HOOK_CHECK_UNITY_CLI=1` (K1) | rc 0, no output |
| 10 | same, `UNITY_HOOK_PROFILE=minimal` (K2) | rc 0, no output |
| 11 | same: `Unity command eval x` (B31) | rc 2 |
| 12 | same: unquoted heredoc with `$(unity command eval x)`, and the backtick variant (B30) | rc 2 / rc 2 |
| 13 | same: `coproc unity command eval x` (B32) | rc 2 |
| 14 | same: A11 quoted-heredoc commit message naming the ban | rc 0 |
| 15 | same: `grep -rn "unity command eval" docs/` (A10) | rc 0 |
| 16 | same: `unity command eval "x` (K4) | rc 2, `unparseable command … blocked conservatively` |
| 17 | same: `u""nity command eval x` | rc 0. This is the accepted gap (prefilter), now listed in Task 8 |
| 18 | same: Edit payload `{"tool_name":"Edit","tool_input":{"command":"unity command eval x"}}` (A13) | rc 0 |
| 19 | A13 guard-removal check: the hook copied with `[ "$TOOL" = "Bash" ] \|\| exit 0` replaced by `:`, then the same Edit payload | rc 2 (BLOCKED). With bats, `bats -f A13` on that copy gives `not ok 1 A13…`, so the test can fail |
| 20 | Fallback (F1 layout: hook + `_lib.sh` copied to `r3/f1/hooks/`, no `../scripts`), `PATH=/usr/bin:/bin:/usr/sbin:/sbin` so `grep` = `/usr/bin/grep` (BSD grep 2.6.0-FreeBSD) | rc 2 + "conservative": `unity command eval x`, `unity cmd eval x`, `FOO=1 unity command eval x`, `Unity command eval x`, `unity shell`, `unity mcp`, `unity pipeline install`, `unity pipe upgrade`, `unity run /p --command foo`, `unity --json command eval x`. rc 0: `unity test . --mode EditMode`, `unity test .`, `unity status`, `unity command --limit 5`, `unity command`, `unity test . --filter command`, `unity editors running --format json`, `unity help command`. rc 2 (accepted fallback-only false positives): `unity mcp --help`, `unity shell --help`, `unity mcp configure --list`, `grep -rn "unity command eval" docs/`, `echo 'unity command eval'` |
| 21 | v2 fallback pattern vs v3 pattern, directly with `/usr/bin/grep -qE` / `-qiE`, on `unity command eval x`, `unity shell` and `unity cmd eval x` | v2: rc 1 (no match = fail open) for all three. v3: rc 0 (match) for all three |
| 22 | `bats r3/repo/.claude/hooks/tests/check-unity-cli.bats` (Bats 1.13.0) | `1..11`, all `ok`: S1, S2, F1, B1, B30, B31, B32, A14, A11, A13, K3 |
| 23 | the same bats file against v2's hook and judge (`r3/repo_v2/`, copied from `r2/`) | `not ok`: F1, B30, B31, B32; the other 7 `ok`. The new tests detect each pass-2 defect |
| 24 | Timing: 5 end-to-end `/bin/bash` runs each of B1 and A1 | max 34 ms (B1) and 32 ms (A1), within the < 3000 ms self-imposed budget |
| 25 | `grep -rn` over `.claude/docs/`, `README.md` and `.claude/CLAUDE.md` for a hook-timeout unit | no unit stated anywhere. Only bare `"timeout": 3000` at `.claude/docs/setup-checklist.md:24` and `README.md:1629`. `settings.json` has `"timeout"` values of 2000–30000 at lines 22–656 (one existing entry, line 603, already uses `5`). So "seconds" rests on the Claude Code hook docs, not on this repo |

Note on scratch writes: the caller's procedure required writing to the session scratchpad (`r3/` files, payloads, bats fixtures, plus `r3/repo_v2/` and `r3/repo_noguard/` for the negative checks). No repo file was created or modified. One attempted inline loop was refused by a Claude Code safety check (it flagged an `rm` inside a shell `-c` script). That command was not run, and the same cases were re-run through a python driver (row 20).
