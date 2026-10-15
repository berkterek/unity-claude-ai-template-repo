---
name: unity-cli-verify
description: "Headless compile/test verification through the Unity 6 CLI (`unity`) when no live-Editor (MCP) verdict is available. Preflight (binary → doctor → Editor-open detection, `editors running` first) → ONE batch `unity test` per verify iteration → exit-code reading (0 / 8 / 6). MCP stays the only live-Editor channel. Forbidden, and hook-enforced once registered in settings.json (check-unity-cli.sh): every named `unity command` incl. eval/eval_file, `unity run --command`, `unity shell`, `unity mcp` (except --help, configure --list/--dry-run), `unity pipeline install|upgrade`."
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
(`--query --tag --limit --sort --caller --skill …`), `unity list`, `unity pipeline list`,
`unity mcp --help`, `unity mcp configure --list` / `--dry-run`.

Forbidden, hook-enforced once registered in `settings.json` (`check-unity-cli.sh` → `.claude/scripts/check-unity-cli.py`):
- `unity command <any name>` (alias `cmd`; incl. `eval`, `eval_file`, and a name after `--`)
- `unity run … --command <name>` (before any `--`)
- `unity shell` (except `-h` / `--help`)
- `unity mcp` (bare = starts a stdio MCP server; any subcommand other than `configure --list` / `--dry-run` writes client config; except `-h` / `--help`)
- `unity pipeline install|upgrade` (alias `pipe`), also behind global value flags (`unity pipeline --format json install`)
- the same commands behind wrappers (`env`, `timeout`, `sudo`, `nice`, `nohup`, `exec`, `command`, `builtin`, `time`, `stdbuf`, `xargs`), shell keywords (incl. `coproc NAME {` and `function NAME {`), `bash -c` / `sh -c` (also `-c --`), `eval`, `$( )` / backticks, a backslash-newline continuation, anything chained on a heredoc opener line (`cat <<EOF; unity …`, `<<'EOF' && unity …`, `<<EOF | unity shell`), `$( )` / backticks inside unquoted heredoc bodies, an absolute binary path, or `Unity`
- NOT caught (accepted gaps, `docs/incidents/mcp-and-framework.md`): a shell fed through stdin or a pipe (`echo '…' | bash`, `| sh -s`), a here-string (`bash <<< '…'`), `source <(echo '…')`, variable/alias indirection, scripts on disk
- an unparseable (unbalanced-quote) command that names one of these subcommands — blocked conservatively

Forbidden, prose only (no hook): `unity close` (exits the Editor without saving); `unity watch` (a
file-watching loop with no exit condition of its own, per `unity watch --help`; its behaviour under
`--non-interactive` / CI is UNVERIFIED); `unity editors … --watch`; `unity setup <client>` /
`unity skill install` (installs the plugin skill that recommends eval; this repo's rules win anyway).
`unity recompile` needs com.unity.pipeline, which this template does not install — it exits 7 here.

## Preflight (in this order; first failing step decides)
P = absolute path: `$(git rev-parse --show-toplevel)/<unity_project_folder from .claude/project-features.json>`
0. `$P/ProjectSettings/ProjectVersion.txt` absent → STOP: `NOT VERIFIED — no Unity project at $P`.
1. Binary: `command -v unity` or `~/.unity/bin/unity` executable → else STOP (2b, "unity binary missing").
2. `unity --non-interactive doctor --ci` → non-zero → STOP (2b, "environment cannot build/test"), quote its output.
3. Editor-open detection — ANY positive, or any detector that errors, means "Editor open on this project" → STOP (2b).
   Exception: detector (a) answering exit 6 with `STATUS_NO_INSTANCES` is negative-but-insufficient, not an
   error (observed 2026-10-15 on beta.13 without Pipeline; it is the template default). The decision then
   rests on (d), (b), (c). Any OTHER error or exit from (a) is still STOP.
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
   insufficient: the CLI docs say `status` cannot connect without the Pipeline server. Task 10(a) of
   `docs/PLAN_unity_cli_verify.md` measures all four.

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
