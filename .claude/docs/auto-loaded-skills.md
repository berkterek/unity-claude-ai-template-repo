# Auto-Loaded Skills

<!-- managed by auto-load-skills.sh — do not edit manually -->

Reference skills for this project. Not @-imported: injected at SessionStart as an index.
Read the file when its description matches the work.

- `.claude/skills/core/knowledge-graph-hybrid.md` — Routes the 4 call-graph queries (callers/impact/path/god-nodes) to the in-process graph-mcp-server.py (backed by graph_bfs_core.py) with gra
- `.claude/skills/core/solid-oop.md` — SOLID & OOP rules — the Card 0 MonoBehaviour gate, the four MonoBehaviour roles (View/Provider/Controller/Manager), the 4-tier architecture
- `.claude/skills/core/unity-git.md` — Unity-specific git conventions — .meta file hygiene, .gitattributes, LFS patterns, .gitignore, commit message format, branch naming, and mer
- `.claude/skills/core/bootstrap-pattern.md` — Code-first bootstrap structure — static [X]Module classes → AppModules → AppScope, ConfigCatalog validation, EventBusModule first, GameScope
- `.claude/skills/core/input-system.md` — New Input System — pull-based InputService (pure C#) + per-prefab InputHandler, action map switching, the FixedUpdate latch rule, legacy Inp
- `.claude/skills/core/scene-hierarchy.md` — Scene hierarchy standards — 6 container GOs (Setup/Services/UI/Environment/Characters/VFX), GO classification table, prefab domain mapping,
- `.claude/skills/third-party/vcontainer.md` — VContainer dependency injection for Unity — scope hierarchy, the code-first module pattern ([Domain]Module → AppModules → AppScope), registr
- `.claude/skills/platform/mobile/SKILL.md` — Mobile optimization — tile-based GPU, ASTC textures, draw call budget (<100), thermal throttling, battery, touch input, safe areas, App Stor
- `.claude/skills/plugins/primetween.md` — PrimeTween usage pattern — setup, tween API, sequences, and UniTask integration
- `.claude/skills/plugins/r3.md` — R3 (Cysharp) usage pattern — Observable, Subject, ReactiveProperty, and UniTask integration
- `.claude/skills/third-party/dotween/SKILL.md` — DOTween animation library — sequence composition, tween lifecycle, easing, kill strategies. CRITICAL: Always kill tweens in OnDestroy to pre
- `.claude/skills/third-party/nsubstitute.md` — NSubstitute setup, configuration, and usage patterns for Unity test assemblies. Use when adding NSubstitute to a project, diagnosing mock fa
- `.claude/skills/third-party/odin-inspector/SKILL.md` — Odin Inspector & Serializer — SerializedMonoBehaviour, validation attributes, custom drawers, editor windows. Enhances Unity inspector with
- `.claude/skills/third-party/textmeshpro/SKILL.md` — TextMeshPro text rendering — font asset creation, material presets, rich text tags, dynamic font fallback, sprite assets in text. Use for al
- `.claude/skills/third-party/unitask/SKILL.md` — UniTask async/await for Unity — zero-alloc async, cancellation tokens, PlayerLoop integration, async LINQ. Use instead of coroutines for can
- `.claude/skills/third-party/unity-asmdef.md` — Assembly Definition setup, reference wiring, and diagnosis for Unity projects. Use when adding a new assembly, fixing CS0246/CS0234 referenc
- `.claude/skills/third-party/unity-editor-tools.md` — Unity Editor scripting patterns beyond UI: AssetDatabase operations, AssetPostprocessor, InitializeOnLoad, EditorPrefs, SessionState, Undo s
- `.claude/skills/third-party/unity-uitoolkit.md` — Unity UI Toolkit patterns for custom Editor windows, custom inspectors, PropertyDrawers, and level editors. Use when building EditorWindow,
- `.claude/skills/third-party/netcode/SKILL.md` — Netcode for GameObjects (NGO) 2.x architecture rules and hallucination guards. Load before writing
- `.claude/skills/systems/urp-volume/SKILL.md` — URP Volume setup via MCP — create global/local Volume GameObjects, create VolumeProfile assets,
- `.claude/skills/third-party/probuilder/SKILL.md` — Unity ProBuilder in-editor mesh modeling — create/edit 3D geometry, UV mapping, poly shapes, Boolean ops, material assignment. Use for level
- `.claude/skills/third-party/probuilder/api.md` — ProBuilder API Reference
- `.claude/skills/third-party/probuilder/integration.md` — ProBuilder — VContainer / Prefab / Scene Integration
- `.claude/skills/third-party/blender-mcp/SKILL.md` — Use when producing, inspecting, or exporting 3D assets from Blender for this Unity project — modelling via MCP, checking a mesh before expor
