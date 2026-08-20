---
name: bootstrap-pattern
description: Code-first bootstrap structure — static [X]Module classes → AppModules → AppScope, ConfigCatalog validation, EventBusModule first, GameScope vs SceneModules boundary, TestScope reusing production modules. Use when adding a new module, writing an installer, or setting up VContainer registration. AppScope.cs never changes; a new module is one line in AppModules.cs.
model-tier: normal
---

# Bootstrap & Installer Pattern

> **`.claude/rules/bootstrap-pattern.md` is the authority.** Read it before wiring anything — this skill is the short form; the rule file carries the six cards, the full `AppScope`/`GameScope`/`ConfigCatalog` listings and the folder structure. On any conflict, the rule file wins.

## The shape

```
[Domain]Module (static class)   ← Install(IContainerBuilder, [Domain]Configuration)
    ↑
AppModules (static class)       ← the module list; one line per module
    ↑
AppScope (LifetimeScope)        ← Bootstrap scene; validates ConfigCatalog, calls AppModules
```

```csharp
public static class AudioModule
{
    public static void Install(IContainerBuilder builder, AudioConfiguration config)
    {
        if (config == null)
        {
            Debug.LogError("[AudioModule] AudioConfiguration missing.");
            return;
        }

        builder.RegisterInstance(config);
        builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
    }
}

public static class AppModules
{
    public static void Install(IContainerBuilder builder, ConfigCatalog configs)
    {
        EventBusModule.Install(builder);                 // FIRST — structural guarantee
        AudioModule.Install(builder, configs.Audio);
        // New module: one line here
    }
}
```

## Non-negotiables

| Rule | Why |
|---|---|
| **`ModuleInstaller` and `AppInstaller` do not exist** — both were removed | A module is a static class, not a ScriptableObject asset. No `[CreateAssetMenu]`, no `_modules` list, no Inspector drag-drop, no merge-conflict-prone `.asset` |
| `EventBusModule.Install` is the first call in `AppModules.Install` | Other modules may `Subscribe` during `Initialize()`; without EventBus registered first, those subscriptions silently fail |
| `ConfigCatalog.Validate(out missing)` runs before any module installs | Otherwise a null config is caught mid-installation and the container ends up half-wired with no clear error |
| Null guards use `Debug.LogError` + `return`, never `throw` | `throw` crashes the build context |
| `AppScope.cs` never changes when a module is added | Adding a module is one line in `AppModules.cs` — visible in the diff, hookable, no Editor action |
| `GameScope` uses `RegisterComponent` only; scene-lifetime services go to `SceneModules` | Inline `builder.Register<T>()` in `GameScope` bypasses the module pattern and makes those services invisible to `/knowledge-graph` |
| `TestScope` calls the production `[Domain]Module.Install()`, then overrides only the fakes | Hand-copied registrations drift from production; reusing the real wiring means a production break breaks the test — that is the point |
| Scene loading goes `ISceneService` (Tier 3) → `ISceneLoader` (Tier 4), never raw `SceneManager` in a service | Keeps an Addressables-backed loader a drop-in swap; see the rule file's Card 6 for the additive-load activate+unload trap |

Full cards, the new-module flow and the folder layout: `.claude/rules/bootstrap-pattern.md`.
