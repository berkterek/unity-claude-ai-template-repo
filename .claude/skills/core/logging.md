---
name: logging
description: DLog usage pattern — project logging implementation, location, namespace, and code examples
model-tier: normal
---

# DLog — Usage Pattern

## Location
`Assets/_AssetFolders/_Framework/Logging/`
Assembly: `FramworkLogging` | Namespace: `Framework.Logging`

## Structure

```
LogTag    → enum, identifies which system is logging
DLog      → static wrapper, zero cost in production via [Conditional]
```

## Available LogTags

```csharp
public enum LogTag
{
    General,   // general purpose
    EventBus,  // EventBus subscribe/publish logs
    SaveLoad   // save/load operations
}
```

When adding a new system, add a corresponding tag to the `LogTag` enum.

## Usage

```csharp
DLog.Log(LogTag.General, "Message");
DLog.Warning(LogTag.SaveLoad, "Warning message");
DLog.Error(LogTag.EventBus, "Error message");
```

## Enabling / Disabling Tags

By default only `LogTag.General` is active. To enable or disable other tags at runtime:

```csharp
DLog.Enable(LogTag.EventBus);   // enable EventBus logs
DLog.Disable(LogTag.EventBus);  // disable EventBus logs
```

This lets you see only the logs for the system you are currently debugging.

## Important Behavior

- All methods are marked with `[Conditional("UNITY_EDITOR")]` and `[Conditional("DEVELOPMENT_BUILD")]`
- In production builds (without `DEVELOPMENT_BUILD`) all DLog calls are stripped at compile time — zero runtime cost
- Use `DLog` instead of `Debug.Log` directly so no logs leak into production
