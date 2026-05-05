---
name: create-changelog
description: Create or update CHANGELOG.md with recent git changes — groups commits by type and formats for readability
user-invocable: true
model-tier: light
---

# Create Changelog

Creates or updates `CHANGELOG.md` at the repo root with recent changes, following the [Keep a Changelog](https://keepachangelog.com) format.

## Steps

1. Run `git log --oneline --since="30 days ago"` to get recent commits
2. If the user passes a version tag (e.g. `/create-changelog v1.2.0`), use `git log <last-tag>..HEAD --oneline` instead
3. Group commits into sections:
   - **Added** — new features, new modules, new commands
   - **Changed** — refactors, behavior changes, rule updates
   - **Fixed** — bug fixes, hook corrections
   - **Removed** — deleted files, removed commands

4. If `CHANGELOG.md` exists, prepend the new entry above the previous one
5. If it doesn't exist, create it with a header

## Format

```markdown
# Changelog

## [Unreleased] — YYYY-MM-DD

### Added
- New `AudioModule` with VContainer registration and UniTask async loading

### Changed
- `PlayerService` now accepts `CancellationToken` in all async methods

### Fixed
- `EnemySpawner` no longer calls `Instantiate` in Update loop

### Removed
- Legacy `InputManager.cs` (replaced by InputView + New Input System)
```

## Notes

- Use plain language, not commit message verbatim — rewrite for clarity
- Skip merge commits, version bumps, and minor doc typos
- One line per meaningful change
- If uncertain about a commit's impact, leave it out rather than misdescribe it
