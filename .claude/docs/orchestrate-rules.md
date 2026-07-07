# /orchestrate NON-NEGOTIABLE Rules

## Pre-Implementation Codebase Scan (/orchestrate only)

`/orchestrate` performs a mandatory pre-scan during Initialization (Step 5) before any agent is spawned:

**If `graph` feature is ENABLED and `graph.json` is fresh (< 24h):** query graph.json directly — do NOT re-scan source folders.
```bash
jq '.codebase.interfaces[] | {name, file}' .claude/graph/graph.json
jq '.codebase.classes[] | select(.file | contains("Concretes")) | {name, file, implements}' .claude/graph/graph.json
jq '.validation | {errors: (.errors|length), warnings: (.warnings|length)}' .claude/graph/graph.json
```

**If graph is disabled or stale (> 24h):** fall back to direct file-scan:

1. **Check `_Framework/`** — list all subfolders, `.asmdef` names, and existing interfaces/services. Never re-implement infrastructure that already exists.
2. **Check `_GameFolders/Scripts/Games/Abstracts/`** — list existing interfaces. If an interface already exists for a tasks.md target, use it — do not create a duplicate.
3. **Check `_GameFolders/Scripts/Games/Concretes/`** — list existing classes. If a target class already exists, read it and verify it follows architecture rules before deciding to modify or re-implement.

In both paths:

4. **Print a Pre-Scan Report** — what exists, what is missing, any conflicts with tasks.md outputs, any architecture violations in existing files.
5. **Flag already-implemented tasks** — if a tasks.md output file already exists and is correct, ask the developer whether to skip or re-implement before proceeding.

This scan is part of `/orchestrate` Initialization. It does not apply to `/implement` (which handles simpler, scoped tasks).

## Assembly Error Blocking (/orchestrate)

`/orchestrate` Step 3.5 (Bounded Verification) and Phase Gate Step 1 (Ralph) both perform an explicit compile check **before** committing or advancing. If any assembly or compile error is detected, the pipeline **stops** — the committer is never spawned.

Detected error patterns: `error CS`, `Assembly ... error/failed`, `has compiler errors`, `Scripts have compiler errors`, `is not allowed to reference`.

The verifier reads `get_logs` after `refresh_assets` and searches for these patterns explicitly. Errors are not silently ignored — they surface as `⛔ BLOCKED` with file path and line number.
