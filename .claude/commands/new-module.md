# New Module — 5-File Module Generator

You generate the standard 5-file module structure for a new service/system in this Unity project. You ask the developer for the module name and scope, then produce all files ready to use.

## What You Generate

For a module named `[ModuleName]`:

```
_GameFolders/Scripts/Games/Concretes/[ModuleName]/
├── I[ModuleName]Service.cs      ← Public API contract
├── [ModuleName]Service.cs       ← sealed implementation
├── [ModuleName]Configuration.cs ← ScriptableObject config (if needed)
├── [ModuleName]Installer.cs     ← VContainer registration
└── [ModuleName]Events.cs        ← IEvent structs (if needed)

_GameFolders/Scripts/Games/Concretes/[ModuleName]/
└── Basic[ModuleName]Provider.cs ← Unity-side implementation (if Unity API needed)
```

## Your Process

1. Ask: "What is the module name?" (e.g. `Audio`, `Currency`, `Store`)
2. Ask: "Does this module need a Unity provider (AudioSource, UnityIAP, etc.) or is it pure C#?"
3. Ask: "What are the main operations this service will expose?" (e.g. `PlaySound`, `AddCoins`)
4. Ask: "Does this module publish or subscribe to any events?"
5. Fire **ARCHITECTURE_GATE** (see `.claude/docs/director-gates.md`). Show the proposed module structure:
   - Interface, Service, Configuration, Installer, Events (if any), Provider (if Unity API needed)
   - Scope it will be registered in (AppScope / GameScope / MenuScope)
   - Wait for `go` before generating any files.
   - After receiving `go` → run:
     ```bash
     mkdir -p .claude/state && echo '{"gate":"ARCHITECTURE_GATE","pipeline":"new-module","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
     ```
6. Generate all files with proper naming, namespace, and VContainer registration.
7. After all files written → run: `rm -f .claude/state/gate-cleared`
7. Print the **Portability Checklist** for the generated module.

## Code Rules

- Interface: one method per line, no implementation
- Service: `sealed`, constructor injection, all dependencies via interface
- Configuration: `ScriptableObject`, `[SerializeField] private` fields with public getters
- Installer: inherit `ModuleInstaller`, null guard on config in `Install()`
- Events: `readonly struct`, implement `IEvent`, past-tense naming (`CoinsChangedEvent`)
- Provider: only file allowed to `using UnityEngine`; implements the provider interface

## Portability Checklist Output

After generating, always print:

```
## Module Portability Checklist: [ModuleName]

[ ] Service class has no `using UnityEngine` import
[ ] No concrete cross-module dependencies (only interfaces)
[ ] Config null guard present in Installer.Install()
[ ] Events in their own [ModuleName]Events.cs file
[ ] Provider (if any) is in Games/Concretes/[ModuleName]/, not in the module folder
[ ] All public methods have a corresponding interface declaration

To use in another project:
1. Copy _GameFolders/Scripts/Games/Concretes/[ModuleName]/ folder
2. Create [ModuleName]Configuration.asset → Assets/Configs/
3. Add [ModuleName]Installer to AppInstaller.asset → Modules list
4. Assign config in Inspector
```
