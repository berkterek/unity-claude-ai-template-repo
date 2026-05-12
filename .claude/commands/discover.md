---
description: Discover installed Unity packages and emit per-package skill drafts under .claude/skills/third-party/<pkg>/
argument-hint: "[--dry-run] [--write] [--only <pkg>] [--include-assets-plugins]"
---

## Usage

```
/discover                                          ← dry-run by default
/discover --write
/discover --only com.kybernetik.primetween --write
/discover --include-assets-plugins --dry-run
/discover --include-assets-plugins --only uhfps --write
```

## Flow

1. Resolve the project root from the current working directory. Fail fast with `ERR_NO_PROJECT_ROOT` if `Packages/manifest.json` is missing.

2. Read `.claude/agents/package-analyzer.md` to load the package-analyzer instructions. Then invoke a `general-purpose` subagent with those instructions as the system prompt, passing the parsed flags (`--only`, `--include-assets-plugins`, `--include-unity-builtins`) and the current working directory as context. Capture its JSON array output.

   > **Important:** Do NOT use `subagent_type: "package-analyzer"` in the Agent tool — that type is not registered as a built-in FleetView agent. Instead use `subagent_type: "general-purpose"` and embed the package-analyzer instructions in the prompt.

   > **Deep scan for Assets-folder plugins:** When `--include-assets-plugins` is set (or when a package lives under `Assets/_AssetFolders/` or `Assets/Plugins/`), the package-analyzer MUST execute steps 3b (script sampling) and 3c (demo scene inspection). These packages have no README; scripts and scenes are the only source of truth.

3. Pretty-print a preview table:

   | package | size | output_dir | files |
   |---------|------|-----------|-------|

   Where `files` is the comma-separated list of filenames in the `files[]` array (e.g. `SKILL.md, prefabs.md, api.md`).

   Then immediately print the **Prefab Summary** table:

   | package | category | prefab_count | suggested_dest_root |
   |---------|----------|--------------|---------------------|

   If all packages have `prefabs: []`, print: `Prefab Summary: (none detected)`

   Then print the **Demo Scenes** table:

   | package | scene_path | notes |
   |---------|-----------|-------|

   If all packages have `demo_scenes: []`, print: `Demo Scenes: (none detected)`

4. Print this note verbatim:
   ```
   Note: --write only documents prefab duplication targets inside skill files. It does not duplicate any prefab.
   ```

5. If `--dry-run` (default when neither `--dry-run` nor `--write` is given), stop here.

6. If `--write`, iterate the JSON array per package:
   - Reject any element whose `output_dir` or any `suggested_dest` in `prefabs` escapes its expected root — surface `ERR_PATH_TRAVERSAL` and skip that package.
   - For each package, check if `output_dir` already exists:
     - If **new package** (`output_dir` does not exist): create the directory and write all `files[]` using the Write tool. Print: `Created <output_dir> with <N> files: <filenames>`.
     - If **existing package** (`output_dir` exists): for each file in `files[]`, check if the file exists:
       - New file → write directly.
       - Existing file → show a 10-line diff and prompt `overwrite | skip | edit`. This prompt fires **per file**, not per package.
   - After processing all files for a package, print a per-package summary: `<pkg>: <N> written, <M> skipped`.

7. After all packages, print a final summary line: `<N> packages processed, <M> files written, <K> files skipped`.

## Output Contract

- Every write goes through the standard Write tool so gateguard / read-before-edit hooks apply. No shell redirects.
- `--write` does NOT create, copy, or move any `.prefab` file. It only writes skill `.md` files.
- Dry-run (default) produces no file writes of any kind.
- All skill files are written under `.claude/skills/third-party/<pkg>/` — never under `skills/plugins/`.

## Error Surfaces

| Error code | Trigger |
|-----------|---------|
| `ERR_NO_PROJECT_ROOT` | `Packages/manifest.json` not found in current directory |
| `ERR_MANIFEST_PARSE` | `Packages/manifest.json` is not valid JSON |
| `ERR_SUBAGENT_OUTPUT` | `package-analyzer` returns malformed or non-JSON output |
| `ERR_WRITE_DENIED` | Write tool returns a permission error |
| `ERR_PATH_TRAVERSAL` | `output_dir` or prefab `suggested_dest` contains `..` segments — rejected before any write |
