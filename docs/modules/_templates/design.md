# Design: [Module Name]
> Spec: spec.md | TDD ref: [relevant TDD section]

## New / Changed Contracts

### `Game.Abstracts.<Domain>`
- `IXxxService` — [method signatures + contract doc: precondition/postcondition]
- `IXxxProvider` — [...]

## Module Wiring

```csharp
// [Domain]Module.Install(builder, configs.[Domain]):
builder.Register<XxxService>(Lifetime.Singleton).AsImplementedInterfaces();
builder.RegisterEntryPoint<YyyService>().AsImplementedInterfaces();
```

Line to add to AppModules.cs:
```csharp
[Domain]Module.Install(builder, configs.[Domain]);
```

## Events

Readonly structs to define in `[Domain]Events.cs`:
- `XxxHappenedEvent` — [when it is published, which fields it carries]

## File Map

| Dosya | Add/Modify | Not |
|-------|-----------|-----|
| `_GameFolders/Scripts/Games/Abstracts/[Domain]/IXxxService.cs` | Add | |
| `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` | Add | |
| `_GameFolders/Scripts/Games/Concretes/[Domain]/[Domain]Module.cs` | Add | |

## Test Type Decisions

| Class | Test Type | Rationale |
|-------|-----------|---------|
| `XxxService` | EditMode | Pure C#, NSubstitute ile mock |
| `XxxController` | PlayMode-Programmatic | MonoBehaviour lifecycle |

## Risks / Open Questions

- [Risk veya soru]
