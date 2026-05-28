---
name: unity-git
description: Unity-specific git conventions — .meta file hygiene, .gitattributes, LFS patterns, .gitignore, commit message format, branch naming, and merge conflict resolution. Use whenever committing Unity project changes, configuring git for a Unity repo, resolving Unity merge conflicts, or auditing .meta file consistency.
---

# Unity Git Conventions

## .meta File Rules (NON-NEGOTIABLE)

Every file and folder under `Assets/` must have a matching `.meta` file. Unity uses `.meta` files to assign stable GUIDs — breaking this breaks all asset references silently.

| Rule | Why |
|------|-----|
| Commit `.meta` alongside its asset — always in the same commit | A `.meta` without its asset (or vice versa) breaks references for other team members |
| Never delete a `.meta` manually — delete the asset in Unity Editor instead | Editor keeps GUIDs consistent; manual deletion leaves dangling references |
| No orphaned `.meta` files (a `.meta` whose asset no longer exists) | Causes Unity to create phantom entries in the asset database |
| No duplicate `guid:` values across `.meta` files | Silent reference break — two assets share the same GUID, one wins randomly |

**Audit command:**
```bash
# Find orphaned .meta files (meta exists, asset does not)
find Assets -name "*.meta" | while read meta; do
  asset="${meta%.meta}"
  [ ! -e "$asset" ] && echo "ORPHANED: $meta"
done

# Find duplicate GUIDs
grep -r "^guid:" Assets --include="*.meta" | awk -F: '{print $3}' | sort | uniq -d
```

---

## .gitattributes for Unity

Place at the repo root. Covers merge strategy, line endings, and diff:

```gitattributes
# Unity YAML — use UnityYAMLMerge if available, otherwise text merge
*.unity        merge=unityyamlmerge diff=unity
*.prefab       merge=unityyamlmerge diff=unity
*.asset        merge=unityyamlmerge diff=unity
*.meta         merge=unityyamlmerge diff=unity
*.mat          merge=unityyamlmerge diff=unity
*.anim         merge=unityyamlmerge diff=unity
*.controller   merge=unityyamlmerge diff=unity

# Binary assets — no merge, no text diff
*.png    binary
*.psd    binary
*.tga    binary
*.jpg    binary
*.jpeg   binary
*.gif    binary
*.bmp    binary
*.tif    binary
*.tiff   binary
*.exr    binary
*.hdr    binary
*.fbx    binary
*.obj    binary
*.blend  binary
*.wav    binary
*.mp3    binary
*.ogg    binary
*.aif    binary
*.bank   binary
*.mp4    binary
*.mov    binary
*.ttf    binary
*.otf    binary

# C# and shaders — normalize line endings
*.cs       text=auto diff=csharp
*.shader   text=auto
*.cginc    text=auto
*.hlsl     text=auto
*.compute  text=auto
*.asmdef   text=auto
*.asmref   text=auto

# Config — normalize line endings
*.json  text=auto
*.xml   text=auto
*.yaml  text=auto
*.yml   text=auto
*.txt   text=auto
*.md    text=auto
```

---

## Git LFS Patterns

Track large binaries with LFS. Run `git lfs install` once, then track:

```bash
git lfs track "*.psd" "*.tga" "*.png" "*.jpg" "*.jpeg"
git lfs track "*.exr" "*.hdr" "*.tif" "*.tiff"
git lfs track "*.fbx" "*.obj" "*.blend" "*.ma" "*.mb"
git lfs track "*.wav" "*.mp3" "*.ogg" "*.aif" "*.aiff" "*.flac" "*.bank"
git lfs track "*.mp4" "*.mov" "*.avi" "*.webm"
git lfs track "*.ttf" "*.otf"
git lfs track "*.unitypackage" "*.cubemap"
```

Verify tracked patterns: `git lfs track` (no args).

> `*.unity` and `*.asset` are typically NOT tracked by LFS — they are YAML text files that benefit from diff/merge. Track them with LFS only if they grow very large (> 50 MB).

---

## .gitignore for Unity

```gitignore
# Unity generated
[Ll]ibrary/
[Tt]emp/
[Oo]bj/
[Bb]uild/
[Bb]uilds/
[Ll]ogs/
[Uu]serSettings/
[Mm]emoryCaptures/

# Unity cache
*.pidb.meta
*.pdb.meta
*.mdb.meta

# IDE
.vs/
.vscode/
*.csproj
*.sln
*.suo
*.tmp
*.user
*.userprefs
*.pidb
*.booproj
*.svd
*.pdb
*.mdb
*.opendb
*.VC.db

# OS
.DS_Store
.DS_Store?
._*
Thumbs.db

# Build output
*.apk
*.aab
*.ipa
*.exe
*.x86
*.x86_64

# Android
ExportedObj/
.gradle/
crashlytics-build.properties

# Packages lock (optional — include if you want reproducible package installs)
# Packages/packages-lock.json
```

---

## Commit Message Format

Use **Conventional Commits**:

```
<type>(<scope>): <short description>

<body — what was built and why, 2–4 lines>

<trailers>
```

**Types:**

| Type | When |
|------|------|
| `feat` | New feature or gameplay system |
| `fix` | Bug fix |
| `test` | Test files only |
| `infra` | Assembly definitions, project config, bootstrap |
| `config` | ScriptableObject assets, Unity settings |
| `refactor` | Code restructure without behavior change |
| `docs` | Documentation only |
| `chore` | Dependency bump, package update |

**Scope:** the module or domain name — `audio`, `player`, `event-bus`, `wallet`, `ui-hud`

**Examples:**
```
infra(event-bus): add type-safe publish/subscribe event bus

feat(wallet): implement virtual currency wallet with persistence

test(wallet): add unit tests for deduct and add operations

config(assemblies): add asmdef files for Game.Concretes and Game.Abstracts
```

**Rules:**
- Subject line: ≤ 72 characters, imperative mood ("add" not "added")
- No emojis
- No AI co-author trailers (`Co-Authored-By: Claude`)
- No "Generated by Claude" or similar AI references
- `.meta` files are committed with their asset — never in a separate commit

---

## Commit Grouping Strategy

Group files into atomic commits by system boundary, ordered by dependency:

1. Assembly definitions and project config
2. Shared interfaces and base types (`Abstracts/`)
3. Infrastructure systems (EventBus, ObjectPool)
4. Core logic systems (`Concretes/`)
5. ScriptableObject configs and assets
6. Tests
7. MonoBehaviour adapters and scene-related files
8. Documentation (PROGRESS.md, CHANGELOG.md last)

**Rules:**
- Never `git add -A` or `git add .` — always add specific files
- Never mix unrelated systems in one commit (e.g., `AudioService` + `WalletSystem` = two commits)
- Every uncommitted change must end up in a commit — working tree must be clean when done

---

## Branch Naming

```
feature/<description>    new features
fix/<description>        bug fixes
release/<version>        release prep
hotfix/<description>     production patch
refactor/<description>   code restructure
```

Use kebab-case for the description: `feature/audio-service`, `fix/player-null-ref`.

---

## Merge Conflict Resolution

| File type | Strategy |
|-----------|----------|
| `*.unity`, `*.prefab` | Use UnityYAMLMerge. If unresolvable, take target branch version and re-apply changes in Unity Editor |
| `*.meta` | Keep the version whose `guid:` is referenced by other assets. Check with `grep -r "<guid>" Assets --include="*.meta"` |
| `ProjectSettings/*.asset` | Merge manually — prefer newer settings, verify each changed line |
| `*.asmdef` | Merge both `references` arrays, remove duplicates |
| `Packages/packages-lock.json` | Take theirs, run `Package Manager → Refresh` to regenerate |

**UnityYAMLMerge setup** (run once, sets `.gitconfig`):
```bash
git config --global merge.unityyamlmerge.name "UnityYAMLMerge"
git config --global merge.unityyamlmerge.driver \
  "'C:/Program Files/Unity/Hub/Editor/<version>/Editor/Data/Tools/UnityYAMLMerge.exe' merge -p %O %B %A %A"
# macOS path: /Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/Tools/UnityYAMLMerge
```
