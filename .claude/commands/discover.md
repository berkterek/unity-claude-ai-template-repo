---
description: Discover installed Unity packages and emit per-package skill drafts under .claude/skills/plugins/
argument-hint: "[--dry-run] [--write] [--only <pkg>] [--include-assets-plugins]"
---

## Usage

```
/discover                                          ← dry-run by default
/discover --write
/discover --only com.kybernetik.primetween --write
/discover --include-assets-plugins --dry-run
```

## Flow

1. Resolve the project root from the current working directory. Fail fast with `ERR_NO_PROJECT_ROOT` if `Packages/manifest.json` is missing.

2. Read `.claude/agents/package-analyzer.md` to load the package-analyzer instructions. Then invoke a `general-purpose` subagent with those instructions as the system prompt, passing the parsed flags (`--only`, `--include-assets-plugins`, `--include-unity-builtins`) and the current working directory as context. Capture its JSON array output.

   > **Important:** Do NOT use `subagent_type: "package-analyzer"` in the Agent tool — that type is not registered as a built-in FleetView agent. Instead use `subagent_type: "general-purpose"` and embed the package-analyzer instructions in the prompt.

   > **Deep scan for Assets-folder plugins:** When `--include-assets-plugins` is set (or when a package lives under `Assets/_AssetFolders/` or `Assets/Plugins/`), the package-analyzer MUST execute steps 3b (script sampling) and 3c (demo scene inspection) in addition to the standard analysis. This is mandatory — static packages without a `package.json` often have no README; the scripts and scenes are the only source of truth.

3. Pretty-print a preview table:

   | package | version | target_path | exists |
   |---------|---------|-------------|--------|

   Then immediately print the **Prefab Summary** table built from the `prefabs` field of each JSON element:

   | package | prefab_name | suggested_destination |
   |---------|-------------|----------------------|

   If all packages have `prefabs: []`, print: `Prefab Summary: (none detected)`

   Then print the **Demo Scenes** table built from the `demo_scenes` field of each JSON element:

   | package | scene_path | notes |
   |---------|-----------|-------|

   If all packages have `demo_scenes: []`, print: `Demo Scenes: (none detected)`

4. Print this note verbatim:
   ```
   Note: --write only documents prefab duplication targets inside skill files. It does not duplicate any prefab.
   ```

5. If `--dry-run` (default when neither `--dry-run` nor `--write` is given), stop here.

6. If `--write`, iterate the JSON array:
   - Reject any element whose `target_path` or any `suggested_dest` in `prefabs` escapes its expected root — surface `ERR_PREFAB_DEST_OUT_OF_ROOT` and skip that package.
   - If `exists == false`: create the target directory and write the draft using the Write tool.
   - If `exists == true`: show a 10-line diff against the current file and prompt the user to choose `overwrite | skip | edit`. This prompt fires **per-package** — no bulk yes/no.

7. After all writes, print a summary line: `<N> created, <M> overwritten, <K> skipped`.

## Output Contract

- Every write goes through the standard Write tool so gateguard / read-before-edit hooks apply. No shell redirects.
- `--write` does NOT create, copy, or move any `.prefab` file. It only writes `SKILL.md` files that contain duplication documentation.
- Dry-run (default) produces no file writes of any kind.

## Error Surfaces

| Error code | Trigger |
|-----------|---------|
| `ERR_NO_PROJECT_ROOT` | `Packages/manifest.json` not found in current directory |
| `ERR_MANIFEST_PARSE` | `Packages/manifest.json` is not valid JSON |
| `ERR_SUBAGENT_OUTPUT` | `package-analyzer` returns malformed or non-JSON output |
| `ERR_WRITE_DENIED` | Write tool returns a permission error |
| `ERR_PATH_TRAVERSAL` | Package `name` field contains `..` segments — rejected before any write |
| `ERR_PREFAB_DEST_OUT_OF_ROOT` | A prefab's `suggested_dest` escapes `_GameFolders/Prefabs/` |
