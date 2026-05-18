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
| `assembly-definitions` | .asmdef authoring — references, platforms, define constraints |
| `source-driven-development` | Fetch official Unity docs before writing API calls — cites sources, flags deprecated APIs, surfaces version conflicts |
| `documentation-and-adrs` | ADR creation for architectural decisions — `/adr` command, `docs/decisions/` folder, lifecycle management |
| `planning-and-task-breakdown` | Vertical slice decomposition + per-task acceptance criteria for `/create-plan` and `/plan-workflow` |
| `code-simplification` | Chesterton's Fence discipline for `/clean-slop` — understand before removing, behavior-preserving refactor |
| `commit-trailers` | Conventional commit trailers — co-author, ticket links, sign-off |
| `event-systems` | IEventBus patterns — pub/sub, struct events, subscribe/unsubscribe lifecycle |
| `event-bus` | Project-specific IEventBus implementation — location, namespace, and code examples |
| `logging` | Project-specific DLog pattern — logging implementation, location, and usage |
| `save-load` | Project-specific SaveLoadSystem pattern — location, namespace, and usage |
| `tdd-nsubstitute` | Project-specific TDD pattern — assembly structure, test templates, and mock rules |
| `hud-statusline` | In-session status line rendering for pipeline progress |
| `object-pooling` | ObjectPool<T> setup, return-to-pool patterns, warm-up |
| `scriptable-objects` | ScriptableObject config authoring, CreateAssetMenu, validation |
| `serialization-safety` | FormerlySerializedAs, SerializeReference, Unity null semantics |
| `unity-mcp-patterns` | MCP tool call patterns for scene/prefab/asset operations |
| `playmode-scene-testing` | Play Mode scene test pattern — TestBootstrap prefab, TestScope (VContainer), scene setup, UnityTest patterns for real MonoBehaviour and prefab integration tests |
| `mcp-preflight` | 3-state MCP availability check — connected / disconnected / not installed. Used by all MCP-dependent pipeline commands before spawning agents |
| `test-type-router` | Determines test type (EditMode / PlayMode-Programmatic / PlayMode-ECS / PlayMode-Scene / NoTest) from class name or file path. Used by `/implement`, `/generate-tests`, `/create-test`, `/create-plan` before any test writing |
| `fix-smart` | Codex-first bug fix pipeline — packages context + architecture rules, hands to Codex for autonomous fix, Claude reviews for VContainer/UniTask/event violations, loops Codex up to 3x if needed |

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

## Third-Party (`skills/third-party/`)

| Skill | Covers |
|-------|--------|
| `dotween` | Tween creation, sequences, callbacks, memory management |
| `odin-inspector` | Custom attributes, validators, group drawers |
| `textmeshpro` | Font assets, rich text, SDF materials, localization |
| `unitask` | Async patterns, cancellation, `Forget()`, UniTaskVoid |
| `vcontainer` | Scope hierarchy, registration, lifecycle interfaces, DI failure diagnosis |

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
