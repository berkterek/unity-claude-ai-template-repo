# /smart-commit — Analyze Changes & Commit Intelligently

Analyzes all uncommitted changes, groups them into logical atomic commits, and commits them with well-crafted messages. No pipeline required — works standalone on any dirty working tree.

## Usage

```
/smart-commit
/smart-commit "add audio system and event bus"  ← optional context hint
```

No argument needed. If given, the argument is passed as context to help the committer understand the intent behind the changes.

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

## Step 2 — Commit

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then apply these context-specific rules:

- Optional hint from user: `$OPTIONAL_CONTEXT_HINT`
- Run: `git status`, `git diff`, `git diff --cached` to see everything
- Read `.claude/CLAUDE.md` to understand project architecture
- Group files into logical atomic commits by system/feature boundary
- Infrastructure before logic before tests; docs go last
- Unity `.meta` files must be committed alongside their asset
- Commit message format: `<type>(<scope>): <short description>`
- NEVER use `git add -A` or `git add .` — specific files only
- NEVER push — local commits only
- ALWAYS end each commit with a `Co-Authored-By:` trailer naming the authoring model (see `.claude/skills/core/unity-git.md`)
- NEVER create empty commits
- Every uncommitted file must end up in a commit — working tree clean when done

When done: list every commit created (hash + message). Report: DONE or BLOCKED with reason.

---

## Completion

Print:
```
## ✓ Committed
[N] commits created:
  [hash] — [message]
  [hash] — [message]
  ...
Working tree: clean
```

$ARGUMENTS
