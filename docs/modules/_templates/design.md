# Design: [Modül Adı]
> Spec: spec.md | TDD ref: [ilgili TDD bölümü]

## Yeni/Değişen Sözleşmeler

### `Game.Abstracts.<Domain>`
- `IXxxService` — [metot imzaları + contract doc: precondition/postcondition]
- `IXxxProvider` — [...]

## Module Wiring

```csharp
// [Domain]Module.Install(builder, configs.[Domain]):
builder.Register<XxxService>(Lifetime.Singleton).AsImplementedInterfaces();
builder.RegisterEntryPoint<YyyService>().AsImplementedInterfaces();
```

AppModules.cs'e eklenecek satır:
```csharp
[Domain]Module.Install(builder, configs.[Domain]);
```

## Events

`[Domain]Events.cs` içinde tanımlanacak readonly struct'lar:
- `XxxHappenedEvent` — [ne zaman publish edilir, hangi alanlar taşır]

## File Map

| Dosya | Add/Modify | Not |
|-------|-----------|-----|
| `_GameFolders/Scripts/Games/Abstracts/[Domain]/IXxxService.cs` | Add | |
| `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` | Add | |
| `_GameFolders/Scripts/Games/Concretes/[Domain]/[Domain]Module.cs` | Add | |

## Test Type Kararları

| Sınıf | Test Tipi | Gerekçe |
|-------|-----------|---------|
| `XxxService` | EditMode | Pure C#, NSubstitute ile mock |
| `XxxController` | PlayMode-Programmatic | MonoBehaviour lifecycle |

## Riskler / Açık Sorular

- [Risk veya soru]
