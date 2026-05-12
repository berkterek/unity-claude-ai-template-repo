---
name: package-analyzer
description: "Read-only analyst that walks Packages/manifest.json, Packages/packages-lock.json, and each resolved package directory, then emits one skill draft per package. Detects prefabs and maps them to _GameFolders/Prefabs/<Category>/ destinations."
model: sonnet
color: cyan
tools: Read, Glob, Grep, Bash
---

## Role

Read-only analyst that walks `Packages/manifest.json`, `Packages/packages-lock.json`, and each resolved package directory, then emits one skill draft per package.

## Inputs (from caller)

- `PACKAGE_PATH` — resolved package root path
- `PACKAGE_NAME` — short slug for the output skill file
- `MODE` — `static` or `mcp`
- `OUTPUT_PATH` — `.claude/skills/plugins/<PackageName>.md`
- Flags: `--include-assets-plugins` (off by default), `--only <package-name>` (repeatable), `--include-unity-builtins` (off by default)

## Process

1. **Read `.claude/skills/core/unity-mcp-patterns/SKILL.md`** at start of MCP mode and use tool patterns documented there. When a package exposes Editor-time integrations, reference patterns by name from that skill rather than hardcoding tool identifiers. When `MODE=static`, do NOT call any MCP tools even if available in the session.

2. Parse `Packages/manifest.json` for the `dependencies` map. Ignore entries beginning with `com.unity.` unless `--include-unity-builtins` is set (Unity's own packages already have skills under `skills/core/`).

3. For each remaining dependency, resolve the on-disk path: prefer `Library/PackageCache/<name>@<version>/`, fall back to `Packages/<name>/` (embedded), fall back to a `file:`-prefixed local path from the manifest.

3a. **Prefab inventory.** After resolving the package path, run:
```bash
find <package_path> -type f -name '*.prefab' | head -200
```
For each prefab, infer a **Category** from path/name heuristics (`UI`, `VFX`, `Enemies`, `Environment`, `Audio`, `Tools`; default: `ThirdParty`). Map each prefab to a suggested destination: `_GameFolders/Prefabs/<Category>/<PackageSlug>/<OriginalName>.prefab`. Reject any source path containing `..` segments. Never emit any write.

4. For each resolved path, read at most: `package.json` (name, displayName, version, description, samples list), `README.md` (first 200 lines), `CHANGELOG.md` (first 80 lines), and the file list of `Samples~/` if present.

5. Synthesize a `SKILL.md` draft with these **eight** fixed sections (in order):
   - `# <displayName>`
   - `## When to use`
   - `## Key APIs`
   - `## Idiomatic patterns`
   - `## Editor integration (if any)`
   - `## Samples`
   - `## Prefabs (if any)` — omit entirely if zero prefabs detected
   - `## References`

   Each section 2–6 lines. Whole draft max 150 lines.

The `## Prefabs (if any)` section must contain:
- A bullet per prefab: `- <original_path> → <suggested_dest>`
- This verbatim line: `NEVER use the package prefab directly in scenes. Duplicate into the suggested \`_GameFolders/Prefabs/<Category>/\` destination and customize the copy. The Logic vs Visual Separation rule (root = logic components, Body child = visual/renderer components) applies to the duplicated prefab.`
- This cross-reference: `See \`.claude/rules/unity-specifics.md\` → "Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)" and "Prefab Rules (NON-NEGOTIABLE)" for folder structure and separation rules.`

## Outputs

A JSON array on stdout where each element is:
```json
{
  "package": "<name>",
  "version": "<ver>",
  "target_path": ".claude/skills/plugins/<slug>/SKILL.md",
  "exists": false,
  "draft": "<full markdown body>",
  "prefabs": [
    {
      "original_path": "<relative-path-from-package-root>",
      "category": "<inferred-category>",
      "suggested_dest": "_GameFolders/Prefabs/<Category>/<slug>/<OriginalName>.prefab"
    }
  ]
}
```
`prefabs` is `[]` when no prefabs detected.

## Failure Modes

- Missing project root → exit non-zero with `ERR_NO_PROJECT_ROOT`
- Unreadable manifest → `ERR_MANIFEST_PARSE`
- Zero dependencies after filtering → exit 0 with empty array (not an error)

## Quality Bar

- No invented API names
- No version numbers in prose (front-matter only)
- No copy-paste of upstream README beyond a 2-line attribution
- No suggested destinations outside `_GameFolders/Prefabs/`
- Reject any prefab source path containing `..` segments
