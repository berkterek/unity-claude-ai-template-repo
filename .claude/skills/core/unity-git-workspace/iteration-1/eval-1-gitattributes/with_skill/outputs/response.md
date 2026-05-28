# .gitattributes for Unity (with LFS)

## Setup

Run once: `git lfs install`

## .gitattributes content

```gitattributes
# ─── Git LFS ────────────────────────────────────────────────────────────────
*.png    filter=lfs diff=lfs merge=lfs -text
*.psd    filter=lfs diff=lfs merge=lfs -text
*.tga    filter=lfs diff=lfs merge=lfs -text
*.jpg    filter=lfs diff=lfs merge=lfs -text
*.jpeg   filter=lfs diff=lfs merge=lfs -text
*.exr    filter=lfs diff=lfs merge=lfs -text
*.hdr    filter=lfs diff=lfs merge=lfs -text
*.fbx    filter=lfs diff=lfs merge=lfs -text
*.obj    filter=lfs diff=lfs merge=lfs -text
*.blend  filter=lfs diff=lfs merge=lfs -text
*.wav    filter=lfs diff=lfs merge=lfs -text
*.mp3    filter=lfs diff=lfs merge=lfs -text
*.ogg    filter=lfs diff=lfs merge=lfs -text
*.mp4    filter=lfs diff=lfs merge=lfs -text
*.mov    filter=lfs diff=lfs merge=lfs -text
*.ttf    filter=lfs diff=lfs merge=lfs -text
*.otf    filter=lfs diff=lfs merge=lfs -text
*.unitypackage filter=lfs diff=lfs merge=lfs -text

# ─── Unity YAML — merge strategy ────────────────────────────────────────────
*.unity      merge=unityyamlmerge diff=unity
*.prefab     merge=unityyamlmerge diff=unity
*.asset      merge=unityyamlmerge diff=unity
*.meta       merge=unityyamlmerge diff=unity
*.mat        merge=unityyamlmerge diff=unity
*.anim       merge=unityyamlmerge diff=unity
*.controller merge=unityyamlmerge diff=unity

# ─── C# and shaders ─────────────────────────────────────────────────────────
*.cs        text=auto diff=csharp
*.shader    text=auto
*.cginc     text=auto
*.hlsl      text=auto
*.compute   text=auto
*.asmdef    text=auto
*.asmref    text=auto

# ─── Config ──────────────────────────────────────────────────────────────────
*.json  text=auto
*.xml   text=auto
*.yaml  text=auto
*.yml   text=auto
*.txt   text=auto
*.md    text=auto
```

## Key decisions

- `*.png` / `*.fbx` → LFS with `-text` — large binaries, LFS keeps clone fast
- `*.unity` / `*.prefab` → `unityyamlmerge`, NO LFS — YAML text, merge works better than binary replace
- `*.cs` → `diff=csharp` — syntax-aware diffs in PRs
- `*.meta` → `unityyamlmerge` — preserves GUIDs on merge

## UnityYAMLMerge setup (once per machine)

```bash
# macOS
git config --global merge.unityyamlmerge.name "UnityYAMLMerge"
git config --global merge.unityyamlmerge.driver \
  "'/Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/Tools/UnityYAMLMerge' merge -p %O %B %A %A"
```
