# Skills Library (`.claude/skills/`)

Pre-built reference skills loaded automatically by commands. Organized by category:

## Core (`skills/core/`)

Infrastructure skills that govern how Claude reasons and acts across all tasks:

| Skill | Covers |
|-------|--------|
| `model-routing` | Automatic model selection heuristics — file count, complexity, risk factors |
| `deep-interview` | 5-dimension ambiguity gating before implementation starts |
| `grill-me` | One-question-at-a-time design stress-test — challenges an existing plan, resolves branches, produces a Decision Record |
| `learner` | Post-debug insight extraction — writes findings to CLAUDE.md Project Learnings |
| `unity-instincts` | Instinct system for learned Unity patterns — capture, score, promote, apply |
| `unity-asmdef` | .asmdef authoring — references, platforms, define constraints, user-invocable |
| `source-driven-development` | Fetch official Unity docs before writing API calls — cites sources, flags deprecated APIs, surfaces version conflicts |
| `documentation-and-adrs` | ADR creation for architectural decisions — `/adr` command, `docs/decisions/` folder, lifecycle management |
| `planning-and-task-breakdown` | Vertical slice decomposition + per-task acceptance criteria for `/create-plan` and `/plan-workflow` |
| `writing-plans` | Plan authoring — required End State section, bite-sized tasks, no-placeholder rules, self-review checklist |
| `executing-plans` | Plan execution — pre-flight summary (Understood / Unclear / Assumptions) before any code is written |
| `code-simplification` | Chesterton's Fence discipline for `/clean-slop` — understand before removing, behavior-preserving refactor |
| `commit-trailers` | Conventional commit trailers — co-author, ticket links, sign-off |
| `event-systems` | Decide which event mechanism to use — C# events vs IEventBus vs Action vs UnityEvent |
| `event-bus` | Project IEventBus implementation — location, namespace, Subscribe/Unsubscribe/Publish API, EventBusAccessor |
| `bootstrap-pattern` | IInstaller → ModuleInstaller → AppInstaller → AppScope layer structure, new module addition flow |
| `input-system` | New Input System & InputView pattern, OnEnable/OnDisable subscription rules, action map switching |
| `scene-hierarchy` | 6-container scene structure, GO classification table, prefab domain mapping |
| `logging` | Project-specific DLog pattern — logging implementation, location, and usage |
| `save-load` | Project-specific SaveLoadSystem pattern — location, namespace, and usage |
| `tdd-nsubstitute` | Project-specific TDD pattern — assembly structure, test templates, and mock rules |
| `hud-statusline` | In-session status line rendering for pipeline progress |
| `object-pooling` | ObjectPool<T> setup, return-to-pool patterns, warm-up |
| `scriptable-objects` | ScriptableObject config authoring, CreateAssetMenu, validation |
| `serialization-safety` | FormerlySerializedAs, SerializeReference, Unity null semantics |
| `unity-mcp-patterns` | MCP tool call patterns for scene/prefab/asset operations |
| `playmode-scene-testing` | Play Mode scene test pattern — TestBootstrap prefab, TestScope (VContainer), scene setup, UnityTest patterns |
| `mcp-preflight` | 3-state MCP availability check — connected / disconnected / not installed |
| `test-type-router` | Determines test type (EditMode / PlayMode-Programmatic / PlayMode-ECS / PlayMode-Scene / NoTest) from a class name, file path, or task description. Used by /implement, /orchestrate, /fix, /fix-deep, /generate-tests, /create-test, and /create-plan before any test writing begins. When result is NoTest (LifetimeScope, ScriptableObject, Baker, IComponentData, config-only changes), tester agent is skipped entirely |
| `unity-ugui` | Runtime UGUI implementation — View scripts, Canvas/MCP setup, HUD, Popup/Dialog, Scroll View pool, safe area |
| `fix-codex` | Full Codex-driven fix pipeline — Codex analyzes fresh (no prior hypotheses), implements, then Claude reviews (correct location? root cause understood? complete? architecture?); committer on APPROVED |
| `caveman` | Ultra-compressed communication mode (~75% fewer tokens) — `/caveman` to enter, `/normal` to exit |
| `context-prime` | Brief Claude on project context at session start — reads key files and summarizes current state |
| `create-changelog` | Create or update CHANGELOG.md with recent git changes |
| `dump` | Save current session notes and decisions to `.claude/logs/` as markdown |
| `five` | 5 Whys root cause analysis — drill down to true cause of a bug or architectural problem |
| `mermaid` | Generate a Mermaid architecture diagram for a module, system, or the full project |

## Platform (`skills/platform/`)

| Skill | Covers |
|-------|--------|
| `mobile` | Touch input, safe area, haptics, app lifecycle |

## Systems (`skills/systems/`)

| Skill | Covers |
|-------|--------|
| `addressables` | Loading, handle lifecycle, label groups, preload |
| `animation` | Animator parameters, state machine behaviours, blend trees |
| `audio` | AudioMixer groups, snapshots, pooled AudioSource, spatial audio, beat sync, procedural SFX |
| `audio-mixer` | AudioMixer routing, exposed parameters, send/receive buses, ducking (sidechain), snapshot transitions |
| `audio-settings` | Audio settings UI, volume persistence via PlayerPrefs, IAudioSettingsService + VContainer wiring |
| `audio-clip-settings` | AudioClip import settings — PCM/ADPCM/Vorbis format selection, load type, platform overrides, memory budget |
| `cinemachine` | Virtual cameras, blends, impulse, follow targets |
| `navmesh` | NavMeshAgent setup, dynamic obstacles, off-mesh links |
| `physics` | Layer matrix, non-alloc queries, trigger vs collision |
| `shader-graph` | URP shader nodes, property exposure, keyword variants |
| `ui-toolkit` | USS, UXML, data binding, runtime panel setup |
| `urp-pipeline` | Renderer features, camera stacking, custom render passes, SRP Batcher, Forward+ |
| `urp-quality-settings` | URP quality tiers (Low/Medium/High/Ultra), runtime asset swap, auto-detect, adaptive performance |
| `urp-lighting-shadows` | Directional/point/spot lights, shadow cascades, bias tuning, light layers, light cookies, reflection probes |
| `urp-post-processing` | Bloom, DOF, Motion Blur, SSAO, Tonemapping, Color Grading, Vignette — setup, values, runtime control |
| `audio-mixer-mcp` | AudioMixer exposed parameters, AudioSource routing — configuration via MCP execute_code |
| `srp-batcher-mcp` | SRP Batcher enable/verify, UI Raycast Target audit, post-processing Volume cleanup via MCP |
| `particle-vfx` | ParticleSystem module config, URP particle shaders, VFX pool, VContainer wiring, event-driven playback |

## Third-Party (`skills/third-party/`)

| Skill | Covers |
|-------|--------|
| `dotween` | Tween creation, sequences, callbacks, memory management — + PITFALLS.md, LIFETIME.md sub-docs |
| `nsubstitute` | NSubstitute setup, configuration, and usage patterns for Unity test assemblies |
| `odin-inspector` | Custom attributes, validators, group drawers |
| `textmeshpro` | Font assets, rich text, SDF materials, localization |
| `unitask` | Async patterns, cancellation, `Forget()`, UniTaskVoid — + PITFALLS.md, CANCELLATION.md sub-docs |
| `unity-editor-tools` | AssetDatabase, AssetPostprocessor, InitializeOnLoad, EditorPrefs, PrefabUtility, build pipeline hooks |
| `unity-uitoolkit` | Editor-only UI Toolkit — EditorWindow, custom Inspector, PropertyDrawer, UXML/USS (NOT runtime UI) |
| `vcontainer` | Scope hierarchy, registration, lifecycle interfaces, DI failure diagnosis |

## Plugins (`skills/plugins/`)

Static skills for pre-installed plugins:

| Skill | Covers |
|-------|--------|
| `primetween` | PrimeTween API, sequences, UniTask integration |
| `r3` | R3 (Cysharp) Observable, Subject, ReactiveProperty, UniTask integration |

## Discovered Packages (`skills/third-party/`)

Generated by `/discover`. Each package folder contains `SKILL.md` (auto-loaded trigger) plus optional split files for large packages:

| File | Covers |
|------|--------|
| `SKILL.md` | Trigger file — When to use, Key APIs summary, links to other files |
| `api.md` | Full API reference + idiomatic code examples |
| `prefabs.md` | Complete prefab list with duplication targets (no line limit) |
| `integration.md` | VContainer / UniTask / IEventBus bridge patterns + Prefab setup workflow + customization |
| `test-strategy.md` | PlayMode test requirements, minimum scene setup, mock strategy |
| `samples.md` | Demo scene analysis — real GameObject/component hierarchy |
| `compliance.md` | Rule violations found in package + recommended fixes — **only emitted when violations exist** |

Small packages (< 10 prefabs) use a single `SKILL.md` (with inline `## Compliance` section if violations found). Medium packages add `prefabs.md`. Large packages (50+) use the full split. Pre-built static skills that came with the template remain in `skills/plugins/`.

**Compliance severities:**
- `MUST-FIX` — blocking hooks will fire (e.g. singleton pattern → `check-vcontainer-singleton`, legacy Input → `check-input-system`)
- `SHOULD-FIX` — warning hooks or explicit architecture rules (e.g. `StartCoroutine` → UniTask, `Resources.Load` → Addressables)
- `CONSIDER` — good practice improvements (e.g. `GetComponent` in Awake → `[SerializeField]`)

## Learned Skills (`skills/learned/`)

Generated by `/learn` from project-specific patterns. Empty until `/learn` is run.

| Skill | Covers |
|-------|--------|

> Skills are read-only reference files. They inform Claude's decisions but do not execute code. The `/learn` command writes new skills to `skills/learned/` based on patterns extracted from your specific project.

## Writing New Skills

Skills support a `model-tier` frontmatter field to control which tier runs them:

```markdown
---
name: my-skill
model-tier: heavy   # light | normal | heavy
---
```

Omit `model-tier` to inherit from the calling command. Use `light` for lookup/reference skills, `heavy` for skills that guide architectural decisions.
