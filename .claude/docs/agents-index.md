# Agents (`.claude/agents/`)

> `.claude/agents/*.md` files are prompt overlays for built-in FleetView agent types — they do not define new `subagent_type` values.
> Use the **Invoke** column below as the exact `subagent_type` value when spawning an agent.
> Every agent's `subagent_type` matches its filename (e.g. `unity-coder.md` → `subagent_type: unity-coder`).

## Model Tier (Lead / Worker / Scanner)

Each agent's `model:` frontmatter follows **role level**, not domain (full rule: `.claude/docs/model-tiers.md`):

- **Lead (Opus)** — decides / reviews / critiques / plans: `unity-critic`, `debugger`, `unity-developer`, `reviewer`, `unity-reviewer`, `debate-proposer`, `debate-critic`, `debate-moderator`
- **Scanner (Haiku)** — mechanical read-only scan: `unity-scout`, `unity-linter`
- **Worker (Sonnet)** — everything else (writers, testers, setup, fixers, builders, including `lean-planner` and `coder`)

This table is the source of truth — keep each `.md` frontmatter in sync with the list above.

| Agent | Invoke (`subagent_type`) | Role |
|-------|--------------------------|------|
| `coder` | `coder` | **Pure C# only — no Unity API.** Used for `_Framework/`, `Games/Abstracts/`, and pure C# targets in `Games/Concretes/` in complexity-scored pipelines (`/orchestrate`, `/migrate`). |
| `tester` | `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks. Spawned as an isolated `claude` subagent (clean context window) in `/implement`, `/fix`, `/orchestrate`, `/migrate` — prevents implementation context from leaking into test decisions. |
| `reviewer` | `reviewer` | General code review |
| `unity-developer` | `unity-developer` | Unity 6 specialist — second reviewer for complex tasks (score ≥ 0.7); checks hot paths, draw calls, ECS safety, Addressables lifecycle + prefab structure (10-point checklist) |
| `unity-setup` | `unity-setup` | Unity Editor setup via MCP — scenes, prefabs (root=logic / Body=visual, domain folders, Prefab Variants), ScriptableObjects |
| `committer` | `committer` | Staged changes → semantic git commit. Runs inline (not as subagent). |
| `debugger` | `debugger` | Root cause analysis |
| `migrator` | `migrator` | Pattern migration |
| `lean-planner` | `lean-planner` | Compact plan writer (Sonnet) — used by `/create-plan --lean`. Produces a 3-5 task table (name, files, one-line note). No code skeletons, no acceptance criteria. Implementer auto-spawn disabled. |
| `unity-critic` | `unity-critic` | Opus adversarial plan challenger — stress-tests architecture decisions before implementation |
| `debate-proposer` | `debate-proposer` | Opus debate advocate — builds the strongest steelman case FOR a thesis/idea/plan. Used by `/debate`; pairs with `debate-critic` + `debate-moderator` |
| `debate-critic` | `debate-critic` | Opus debate adversary — refutes a thesis, tagging each objection FACT/OPINION. Used by `/debate`. **Distinct from `unity-critic`:** debates an arbitrary thesis in an ensemble; `unity-critic` one-pass-reviews a Unity implementation plan |
| `debate-moderator` | `debate-moderator` | Opus debate judge — triages each objection into REFUTED / CONFIRMED / ESCALATE in a single pass, settling verifiable clashes with its own tools. Used by `/debate` |
| `unity-shader-dev` | `unity-shader-dev` | URP shader authoring — complexity router: simple effects use HLSL, complex/visual effects use ShaderGraph (generates .shadergraph JSON + assigns material via MCP) |
| `unity-ui-builder` | `unity-ui-builder` | Runtime UGUI specialist — Canvas hierarchy via MCP, MonoBehaviour view scripts, TextMeshPro, safe area, responsive layout, Canvas split strategy |
| `unity-ui-toolkit-builder` | `unity-ui-toolkit-builder` | Editor UI Toolkit specialist — UXML layouts, USS stylesheets, custom inspectors, EditorWindows, SerializedObject data binding (Editor-only; runtime UI uses UGUI) |
| `unity-optimizer` | `unity-optimizer` | Runtime performance — allocations, draw calls, ECS hot paths, profiler-guided fixes |
| `unity-scene-builder` | `unity-scene-builder` | Scene composition via MCP — hierarchy, lighting, camera, volumes |
| `graphics-setup-agent` | `graphics-setup-agent` | Creates URP Pipeline Assets (Low/Medium/High) for mobile or pc, configures Renderer Data, wires Quality Settings via MCP |
| `audio-clip-agent` | `audio-clip-agent` | Scans AudioClip assets, categorizes them, applies optimized import settings via temp Editor script + MCP |
| `package-analyzer` | `package-analyzer` | Read-only analyst — walks `Packages/manifest.json` + each package directory, detects prefabs and APIs, and returns skill drafts as JSON for `/discover` to write. Compliance scan catches all singleton variants (`Instance`, `_instance`, `Current`/`Shared`/`Main`/`Default`, `GetInstance()`, `DontDestroyOnLoad`) and emits Adapter pattern boilerplate (interface + adapter class + AppScope registration + NSubstitute mock line) for each. `test-strategy.md` gains a mandatory Mock Requirements section when singletons are detected. |
| `unity-linter` | `unity-linter` | Static analysis pass — naming, regions, hook-rule compliance |
| `unity-security-reviewer` | `unity-security-reviewer` | Security audit — data exposure, serialization risks, network surface |
| `unity-build-runner` | `unity-build-runner` | CI/build pipeline — platform flags, build profiles, addressables baking |
| `unity-coder` | `unity-coder` | **Primary Unity coder for Medium/Complex tasks.** Full Unity C# — MonoBehaviours, providers, installers, scene wiring. Used in `/implement`, `/fix`, `/scene-setup`, `/orchestrate`, `/migrate` when complexity ≥ 0.4. |
| `unity-fixer` | `unity-fixer` | Bug fixer with full context — reads surrounding code before patching |
| `unity-git-master` | `unity-git-master` | Git workflow — branching strategy, conflict resolution, history rewrite |
| `unity-migrator` | `unity-migrator` | Pattern migration specialist — coroutine→UniTask, singleton→VContainer, legacy input |
| `unity-network-dev` | `unity-network-dev` | Netcode for GameObjects / Unity Transport — lobby, relay, RPCs |
| `unity-prototyper` | `unity-prototyper` | Rapid prototype scaffolding — speed over correctness, clearly marked TODOs |
| `unity-reviewer` | `unity-reviewer` | Unity-specific code review — full checklist including ECS, Input, Addressables |
| `unity-scout` | `unity-scout` | Codebase explorer — maps dependencies, surfaces risks, no writes |
| `unity-test-runner` | `unity-test-runner` | Runs Edit/Play Mode tests via MCP and reports failures with context |
| `silent-failure-hunter` | `silent-failure-hunter` | Audits C# files for silent failure patterns (empty catch, swallowed async errors, dangerous fallbacks) — reports only, never auto-fixes |
| `unity-test-builder` | `unity-test-builder` | Builds Play Mode test scenes — creates TestScope, TestInstaller, PlayMode test stub, wires TestBootstrap in scene via MCP, and adds the test scene to Build Settings automatically; used by `/create-test` (PlayMode-Scene path) |
| `unity-verifier` | `unity-verifier` | Post-implementation verification — compile + test + prefab/scene integrity |
| `unity-particle-designer` | `unity-particle-designer` | VFX specialist — creates ParticleSystem prefabs, URP particle materials, pooled VFX services, and wires event-driven playback via MCP |
