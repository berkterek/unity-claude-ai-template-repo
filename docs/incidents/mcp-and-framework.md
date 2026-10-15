# MCP Sessions, SerializedOps, the Framework Package and the Unity Plugin

Moved verbatim from `.claude/CLAUDE.md` on 2026-10-08; the rule it supports is stated there in short form.

- **A session's MCP tool list is frozen at session start — and a missing bridge is never a reason to reach for its transport.** A server added mid-session with `claude mcp add` runs correctly and still contributes no `mcp__<server>__*` tools to that session; nothing reports this, the tools are just absent. That is why `.mcp.json` is **committed** (it was gitignored, which is exactly why each clone re-hit this) — every session in this repo opens with `graph_mcp` and `blender` already registered. When a bridge genuinely is missing, restart the session; do **not** substitute Bash. Talking to Blender's socket on `localhost:9876` directly and calling `bpy.ops.export_scene.fbx` skips `blender_export_fbx`'s pre-flight (missing UV layer, wrong unit scale, non-uniform scale) in one move — those three fail silently in Unity and **no content hook can see them, because a `.fbx` is binary**. Same shape as the `check-write-via-bash.sh` rule: switching tools to get past a gate cancels the gate. Full note: README → "MCP servers are frozen at session start".
- **An inspector reference on a prefab or ScriptableObject is assigned with the SerializedOps applier, never with a throwaway Editor script.** This is the one job MCP cannot do reliably — an object field on a prefab component, a nested `SerializedProperty`, a reference stored on a ScriptableObject. The applier ships in the framework package as `Tools/Framework/Apply Serialized Ops`: write a versioned JSON manifest to `Temp/serialized-ops.json`, trigger the menu item (MCP `execute_menu_item`, full path including the leading `Tools/`), then **read `Temp/serialized-ops-result.json`** — not the console. It supports `setRef`, `setValue` and `addComponent`, fails each op loudly with its index and reason while the rest still run, and **re-reads every applied op from a fresh load of the saved asset**, so a write that reported success but did not persist is reported as a failure rather than a pass. Input contract, including the property-path forms and the array-growth trap: `packages/framework/Editors/SERIALIZED_OPS_MANIFEST.md`. Writing a one-off `[InitializeOnLoad]` script instead is blocked by `check-no-throwaway-editor-script.sh` — that block now names a tool that exists, which it did not before.
- **The framework is a package; `packages/framework/` is its only source.** `/setup-project` Step 2b writes one `Packages/manifest.json` line pinned to a `framework/vX.Y.Z` tag, and Steps 3–4 no longer emit any `_Framework/` assembly file. Never vendor the package into `Assets/` and never re-create those four assemblies there: a second copy is either a `CS0101` duplicate-type error or — worse when it compiles — the copy that silently drifts. That drift is measured, not hypothetical: for a while both a generated copy and a hand-exported `.unitypackage` existed, and **ten of twelve files had diverged** before anyone looked, including an `.asmdef` misspelled `FramworkLogging` for months. Nothing could catch it — a `.unitypackage` is a gzipped tar, invisible to every content hook, to `validate-generated-asmdefs.py` and to the compile probe alike, the same blind spot as a `.fbx`. After editing anything under `packages/framework/`, run `.claude/tests/setup-compile-probe/run-probe.sh`: it now pulls the package by `file:` path precisely so it compiles the working tree rather than an older tag. `_Framework/Installers/IInstaller.cs` is the one framework file still generated into `Assets/`, because it owns no `.asmdef` and package code without one is never compiled.

### Unity official plugin (`unity@unity-agent-plugin`) — precedence

Unity Technologies' own plugin (31 skills, `unity:*`, currently **0.1.6-beta**) is optional and
genuinely useful in the places this template leaves empty — `physics-3d-collision` (PhysX
diagnostics; it carries hard factual corrections such as *two kinematic triggers DO fire
`OnTriggerEnter`*, which contradicts the model's own priors), `optimize-audio`,
`optimize-text-mesh-pro`, `urp-postprocessing`, `localization`, `initialize-ai-navigation`,
`unity-package-management`. None of those hold an architectural opinion, so none of them collide.

Its skill descriptions are auto-loaded into every session, which is exactly why the collisions
below have to be written down: nothing in the plugin knows this repo exists, and three of its
skills are wired to do the job a rule here already owns.

- **This repo's rules win on every conflict.** A plugin skill is a reference, never an
  authority — it is not a rule file, and "the skill said so" is not a reason to write code a
  hook or a `rules/*.md` card forbids.
- **`unity:unity-cli`'s `unity command eval` is forbidden here — `check-unity-cli.sh` added 2026-10-15;
  enforced once registered in `settings.json`** (judge: `.claude/scripts/check-unity-cli.py`). `eval` (and every named
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
  not the reason for the ban. Also handled: any letter case of the binary name (`Unity …` runs the
  binary on a case-insensitive filesystem) and `$(…)` / backticks inside an unquoted heredoc body
  (bash expands them).
  **The hook is not airtight. Accepted gaps** (each kept because closing it costs more than it buys):
  variable or alias indirection (`U=unity; $U command eval`, a renamed symlink) — needs shell
  evaluation; a quote-split binary name (`u""nity command eval x`) — the bash prefilter matches the
  literal word `unity` before the judge runs (the judge itself would block it), and dropping the
  prefilter would start python3 on every Bash call; scripts on disk (`bash run.sh`) — `.sh` is not a
  governed extension in `check-write-via-bash.sh` either; a heredoc fed to a shell (`bash <<EOF`) —
  heredoc bodies are treated as data (only their `$(…)`/backticks are scanned) so commit messages
  pass; a shell fed through stdin or a pipe (`echo '…' | bash`, `| sh -s`), a here-string
  (`bash <<< '…'`, `. /dev/stdin <<< '…'`) and process substitution (`source <(echo '…')`) — the
  command text is data to the judge, and blocking `| bash` / `<<<` outright would break legitimate
  uses; heredoc detection is a regex, not a tokenizer, so a `<<` that is not a heredoc is read as one
  and the real command line after it is judged as data (measured 2026-10-15, each runs in bash): a
  `<<EOF` inside quotes (`echo "<<EOF"⏎unity command eval x; echo "⏎EOF⏎"`), a here-string word
  (`cat <<<EOF⏎unity command eval x⏎EOF`), an arithmetic shift (`echo $((1<<X))⏎unity command eval
  y⏎X`) and a `<<EOF` in a comment (`# <<EOF⏎unity …⏎EOF`); backslash-newline stripping eats an
  escaped backslash (`echo foo \\⏎unity command eval x` is judged as one line); the heredoc regex is
  quadratic on thousands of repeated unterminated openers (160KB ≈ 26 s against the hook's 5 s
  timeout — a timeout is expected to let the command through, inferred, not measured). The review
  loop stopped at its pass limit with these open (EXHAUSTION_GATE `skip`, 2026-10-15); the real fix
  is a shell tokenizer, which is out of this plan's scope; `xargs`-appended arguments (`echo eval | xargs unity command`) — the name is not in the
  command string; `env -S "…"` split strings and wrappers the judge does not model (`arch`,
  `caffeinate`, `script`, unknown value-taking flags) — rare, extendable per case; function bodies
  defined with the `name() { … }` form are handled, but a function defined in one Bash call and invoked
  in a later one is invisible; other interpreters
  (`python -c "subprocess.run(['unity', …])"`); anything typed outside Claude's Bash tool; the
  `minimal` profile, where the hook does not run; `unity close`, `unity watch`, `unity setup` /
  `unity skill install` (prose-only bans in the skill); `unity vcs` / `cm` remote writes, which
  `block-git-push.sh` does not cover; and MCP's own `execute_code`, a different channel outside this
  hook's reach. The hook does nothing until it is registered in `settings.json` (user-owned).
- **`unity:new-unity-project` never replaces `/setup-project`.** It creates a stock Unity project;
  `/setup-project` generates `_Framework`, the asmdef graph, `DLog`, the SaveLoad chain, `AppScope`
  and `ConfigCatalog`. Letting it run first discards the entire reason this template exists.
- **`unity:ui-ugui` output is not accepted as-is.** Its routing (runtime → uGUI, Editor → UI
  Toolkit) matches ours only below Unity 6 — on 6000.0+ full-screen menus go to UI Toolkit
  (`rules/ui-toolkit-runtime.md` Card 1) — and it is a good uGUI reference. But it knows nothing of the mandated
  six-container scene hierarchy (`scene-hierarchy.md`), the `BaseCanvas` variant chain or prefab
  DRY (`unity-prefabs.md` Cards 3 and 5), or the `RaycastTarget` rule (`performance.md`). Its
  hierarchy has to be reshaped to those before it lands.
- **`unity:ui-uitk` is a reference, not the routing authority.** It is a solid UXML/USS reference for Unity 6, but it does not know this template's version gate or screen routing (`rules/ui-toolkit-runtime.md` Card 1), the tokens-only rule (Card 2), the shared `PanelSettings` (Card 4) or the `*View` shape (Card 5). Its output is reshaped to those before it lands, exactly like `unity:ui-ugui`.
- **`unity:migrate-birp-to-urp` should never fire** — every project from this template is
  URP-native. If it triggers, the prompt is mis-scoped.
- **Its sample code is written for a stock project, not this one.** `Debug.Log` appears in ~18
  reference files (`check-dlog-usage.sh` blocks it in runtime game paths — use `DLog`), and
  `Resources.Load` in the sprite-atlas and codeless-IAP samples (`addressables.md`). A block there
  is enforcement working, not a bug to route around.
