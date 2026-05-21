# Agents (`.claude/agents/`)

| Agent | Role |
|-------|------|
| `coder` | **Pure C# only — no Unity API.** Used for `_Framework/`, `Games/Abstracts/`, and pure C# targets in `Games/Concretes/` in complexity-scored pipelines (`/orchestrate`, `/migrate`). |
| `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks. Spawned as an isolated `claude` subagent (clean context window) in `/implement`, `/fix`, `/orchestrate`, `/migrate` — prevents implementation context from leaking into test decisions. |
| `reviewer` | General code review |
| `unity-developer` | Unity 6 specialist — second reviewer for complex tasks (score ≥ 0.7); checks hot paths, draw calls, ECS safety, Addressables lifecycle + prefab structure (10-point checklist) |
| `unity-setup` | Unity Editor setup via MCP — scenes, prefabs (root=logic / Body=visual, domain folders, Prefab Variants), ScriptableObjects |
| `committer` | Staged changes → semantic git commit. Runs inline (not as subagent). |
| `debugger` | Root cause analysis |
| `migrator` | Pattern migration |
| `unity-critic` | Opus adversarial plan challenger — stress-tests architecture decisions before implementation |
| `unity-shader-dev` | URP shader authoring — complexity router: basit efektler HLSL, karmaşık/görsel efektler ShaderGraph (.shadergraph JSON üretir + MCP ile materyal atar) |
| `unity-ui-builder` | Runtime UGUI specialist — Canvas hierarchy via MCP, MonoBehaviour view scripts, TextMeshPro, safe area, responsive layout, Canvas split strategy |
| `unity-ui-toolkit-builder` | Editor UI Toolkit specialist — UXML layouts, USS stylesheets, custom inspectors, EditorWindows, SerializedObject data binding (Editor-only; runtime UI uses UGUI) |
| `unity-optimizer` | Runtime performance — allocations, draw calls, ECS hot paths, profiler-guided fixes |
| `unity-scene-builder` | Scene composition via MCP — hierarchy, lighting, camera, volumes |
| `graphics-setup-agent` | Creates URP Pipeline Assets (Low/Medium/High) for mobile or pc, configures Renderer Data, wires Quality Settings via MCP |
| `audio-clip-agent` | Scans AudioClip assets, categorizes them, applies optimized import settings via temp Editor script + MCP |
| `package-analyzer` | Read-only analyst — walks `Packages/manifest.json` + each package directory, detects prefabs and APIs, and returns skill drafts as JSON for `/discover` to write. Compliance scan catches all singleton variants (`Instance`, `_instance`, `Current`/`Shared`/`Main`/`Default`, `GetInstance()`, `DontDestroyOnLoad`) and emits Adapter pattern boilerplate (interface + adapter class + AppScope registration + NSubstitute mock line) for each. `test-strategy.md` gains a mandatory Mock Requirements section when singletons are detected. |
| `unity-linter` | Static analysis pass — naming, regions, hook-rule compliance |
| `unity-security-reviewer` | Security audit — data exposure, serialization risks, network surface |
| `unity-build-runner` | CI/build pipeline — platform flags, build profiles, addressables baking |
| `unity-coder` | **Primary Unity coder for Medium/Complex tasks.** Full Unity C# — MonoBehaviours, providers, installers, scene wiring. Used in `/implement`, `/fix`, `/scene-setup`, `/orchestrate`, `/migrate` when complexity ≥ 0.4. |
| `unity-coder-lite` | Lightweight Unity coder for small isolated changes |
| `unity-fixer` | Bug fixer with full context — reads surrounding code before patching |
| `unity-fixer-lite` | Quick targeted fix for a single well-scoped defect |
| `unity-git-master` | Git workflow — branching strategy, conflict resolution, history rewrite |
| `unity-migrator` | Pattern migration specialist — coroutine→UniTask, singleton→VContainer, legacy input |
| `unity-network-dev` | Netcode for GameObjects / Unity Transport — lobby, relay, RPCs |
| `unity-prototyper` | Rapid prototype scaffolding — speed over correctness, clearly marked TODOs |
| `unity-reviewer` | Unity-specific code review — full checklist including ECS, Input, Addressables |
| `unity-scout` | Codebase explorer — maps dependencies, surfaces risks, no writes |
| `unity-test-runner` | Runs Edit/Play Mode tests via MCP and reports failures with context |
| `silent-failure-hunter` | Audits C# files for silent failure patterns (empty catch, swallowed async errors, dangerous fallbacks) — reports only, never auto-fixes |
| `unity-test-builder` | Builds Play Mode test scenes — creates TestScope, TestInstaller, PlayMode test stub, wires TestBootstrap in scene via MCP, and adds the test scene to Build Settings automatically; used by `/create-test` (PlayMode-Scene path) |
| `unity-verifier` | Post-implementation verification — compile + test + prefab/scene integrity |
