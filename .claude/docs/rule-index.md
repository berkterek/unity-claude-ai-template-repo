# Rule Index — Path-Scoped Rules

These rules are NOT in your context until a matching file is touched, and /compact drops them again.
When the work below is in scope — **including while only planning** — Read the file before deciding.
MCP tools (scene, prefab, component) never trigger auto-load: Read the rule yourself before MCP work.

| Before you… | Read |
|---|---|
| decide how anything is persisted, or name a `*SaveData` / `*Model` | `.claude/rules/save-load.md` |
| choose UGUI vs UI Toolkit, or plan any screen, menu, popup or HUD | `.claude/rules/ui-toolkit-runtime.md` |
| choose a test type, or write or plan a test | `.claude/rules/testing.md` |
| plan, start or prioritize a module; edit the GDD, TDD or ROADMAP | `.claude/rules/roadmap-milestones.md` |
| create or change a prefab, or place a second copy of an object | `.claude/rules/unity-prefabs.md` |
| place or move objects in a scene | `.claude/rules/scene-hierarchy.md` |
| choose IEventBus vs Action vs C# event vs R3 | `.claude/rules/event-patterns.md` |
| write async code | `.claude/rules/unity-async.md` |
| rename or add a serialized field | `.claude/rules/serialization.md` |
| use editor guards, platform defines, lifecycle order, DOTween cleanup | `.claude/rules/unity-lifecycle.md` |
| log anything | `.claude/rules/logging.md` |
| read player input | `.claude/rules/unity-input.md` |
| write hot-path code, materials, shaders, or UI raycast settings | `.claude/rules/performance.md` |
| write ECS code (only if feature `ecs` is enabled) | `.claude/rules/ecs-dots.md` |
| load assets at runtime (only if feature `addressables` is enabled) | `.claude/rules/addressables.md` |
| build a browser-based authoring tool | `.claude/rules/web-tool-architecture.md`, `web-tool-data-contract.md`, `web-tool-design-system.md` |

Always loaded, no action needed: `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`.
