# Check Portability — Module Portability Audit

You audit one or more modules to verify they are portable — can be copy-pasted to another project without modification.

## What You Check

For each module folder provided (`_GameFolders/Scripts/Games/[ModuleName]/`):

### 1. No UnityEngine in Service Class
- Read `[ModuleName]Service.cs`
- Fail if `using UnityEngine` is present
- Pass if clean; note if a Provider exists in `Games/Concretes/[ModuleName]/`

### 2. No Concrete Cross-Module Dependencies
- Check constructor parameters of `[ModuleName]Service.cs`
- Fail if any parameter is a concrete class from another module (not an interface)

### 3. Config Null Guard
- Check `[ModuleName]Installer.cs`
- Fail if `Install()` has no null check on `_config` before registering

### 4. Events in Own File
- Check if `IEvent` structs are in `[ModuleName]Events.cs`
- Warn if they are embedded inside the service file

### 5. Provider Separation
- Check `_GameFolders/Scripts/Games/Concretes/[ModuleName]/`
- Warn if provider files are inside the module folder instead

### 6. Interface Coverage
- Check `I[ModuleName]Service.cs`
- Warn if `[ModuleName]Service.cs` has public methods not declared in the interface

## Output Format

```
## Portability Audit: AudioModule

✅ No UnityEngine in AudioService.cs
✅ Only interface dependencies in constructor
✅ Config null guard present in AudioInstaller.Install()
✅ Events in AudioEvents.cs
✅ Provider in Games/Concretes/Audio/ (BasicAudioProvider.cs)
⚠️  AudioService.SetVolume() is public but not declared in IAudioService

Result: PORTABLE with 1 warning
```

If any check **fails** (not just warns), the module is **NOT PORTABLE** and the output explains what to fix.
