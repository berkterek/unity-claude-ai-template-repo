# /smart-commit-selected — Plan, Select & Commit

Analyzes uncommitted changes, groups them into logical atomic commits, shows a checklist, and commits **only the ones you select**.

## Usage

```
/smart-commit-selected
/smart-commit-selected "add audio system"  ← optional context hint
```

---

## Step 1 — Analyze

Run the following to understand the current state:

```bash
git status
git diff
git diff --cached
git log --oneline -5
```

If the working tree is **clean** → stop and print:
```
Nothing to commit. Working tree is clean.
```

---

## Step 2 — Plan Commit Groups (DO NOT COMMIT YET)

Group all changed files into logical atomic commits by system/feature boundary. Apply these rules:

- Infrastructure before logic before tests; docs go last
- Unity `.meta` files must be grouped with their asset
- Commit message format: `<type>(<scope>): <short description>`
- NEVER group unrelated files together

Print the proposed plan in this format:

```
## Proposed Commits

[1] feat(audio): add AudioService and AudioInstaller
    Files: AudioService.cs, AudioInstaller.cs, IAudioService.cs, AudioService.cs.meta

[2] fix(player): correct jump force calculation
    Files: PlayerService.cs

[3] docs: update README with architecture notes
    Files: README.md
```

---

## Step 3 — Ask User to Select

Use the `AskUserQuestion` tool with `multiSelect: true`.

- One option per proposed commit group
- Label: the full commit message (e.g. `feat(audio): add AudioService and AudioInstaller`)
- Description: list the files in that group

Wait for the user's selection before proceeding.

If the user selects nothing → stop and print:
```
No commits selected. Nothing was committed.
```

---

## Step 4 — Commit Selected Groups Only

Commit **only** the groups the user selected. Follow these rules:

- Optional hint from user: `$ARGUMENTS`
- NEVER use `git add -A` or `git add .` — add specific files only
- NEVER touch files from unselected groups — leave them unstaged
- NEVER push — local commits only
- ALWAYS end each commit with a `Co-Authored-By:` trailer naming the authoring model (see `.claude/skills/core/unity-git.md`)
- NEVER create empty commits

---

## Completion

Print:

```
## ✓ Committed
[N] commits created:
  [hash] — [message]
  [hash] — [message]

Skipped: [M] groups (not selected)
```
