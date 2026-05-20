---
name: save-load
description: SaveLoadSystem usage pattern — project save/load implementation, location, namespace, and code examples
model-tier: normal
---

# SaveLoadSystem — Usage Pattern

## Location
`Assets/_Framework/SaveLoadSystems/`
Assembly: `FrameworkSaveLoadSystems` | Namespace: `Framework.SaveLoadSystems`

## Structure

```
ISaveLoadDal       → storage access abstraction (PlayerPrefs, cloud, db, etc.)
ISaveLoadService   → high-level API used by game code
SaveLoadManager    → ISaveLoadService implementation, delegates to ISaveLoadDal
LocalSaveLoadDal   → ISaveLoadDal implementation using PlayerPrefs + Newtonsoft.Json
```

## VContainer Registration

```csharp
builder.Register<LocalSaveLoadDal>(Lifetime.Singleton).As<ISaveLoadDal>();
builder.Register<SaveLoadManager>(Lifetime.Singleton).As<ISaveLoadService>();
```

Always inject `ISaveLoadService` in game code — never use `SaveLoadManager` or `LocalSaveLoadDal` directly.

## Saving / Loading Plain C# Data

`LocalSaveLoadDal` uses Newtonsoft.Json for plain C# objects:

```csharp
// Save
_saveLoadService.SaveDataProcess("player_coins", 500);
_saveLoadService.SaveDataProcess("player_data", new PlayerData { Level = 3, Name = "Ali" });

// Load
int coins = _saveLoadService.LoadDataProcess<int>("player_coins");
PlayerData data = _saveLoadService.LoadDataProcess<PlayerData>("player_data");

// Key check
if (_saveLoadService.HasKeyAvailable("player_coins")) { }

// Delete
_saveLoadService.DeleteData("player_coins");
```

## Saving / Loading Unity Objects

For Unity Objects (ScriptableObject etc.) `JsonUtility` is used:

```csharp
_saveLoadService.SaveUnityObjectProcess("config", myScriptableObject);
MyConfig loaded = _saveLoadService.LoadUnityObjectProcess<MyConfig>("config");
```

## Adding a New Storage Backend

Write a new class implementing `ISaveLoadDal` (e.g. `CloudSaveLoadDal`) and update the VContainer registration. `SaveLoadManager` and game code remain unchanged.

```csharp
public class CloudSaveLoadDal : ISaveLoadDal
{
    // implement ISaveLoadDal methods using cloud API
}
```

## LogTag

SaveLoad operations are logged with `LogTag.SaveLoad`. To enable during debugging:

```csharp
DLog.Enable(LogTag.SaveLoad);
```
