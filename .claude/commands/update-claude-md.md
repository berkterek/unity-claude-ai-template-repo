# /update-claude-md — CLAUDE.md Sync Agent

Synchronizes CLAUDE.md with the actual project state: hooks in `settings.json`, rules in `.claude/rules/`, commands in `.claude/commands/`, and agents in `.claude/agents/`.

## Usage

```
/update-claude-md
/update-claude-md --section hooks
/update-claude-md --section rules
/update-claude-md --section commands
/update-claude-md --section agents
```

If `--section` is omitted, all sections are synced.

---

## Step 1 — Read Source of Truth

Read these files to build the authoritative state:

1. `.claude/settings.json` → extract all hooks from `PreToolUse` and `PostToolUse`
2. `.claude/hooks/` → list all `.sh` files present on disk
3. `.claude/rules/` → list all `.md` files present on disk
4. `.claude/commands/` → list all `.md` files present on disk
5. `.claude/agents/` → list all `.md` files present on disk (if folder exists)

Read CLAUDE.md to understand the current state of each section.

---

## Step 2 — Diff Each Section

### Hooks Section

Compare `settings.json` PreToolUse + PostToolUse entries against the **Hooks** table in CLAUDE.md.

For each hook in `settings.json`:
- Is it listed in CLAUDE.md? If not → **ADD**
- Is the description accurate? If not → **UPDATE**
- Is it in the correct table (Blocking vs Warning)? Exit 2 = Blocking, exit 0 = Warning.

For each hook in CLAUDE.md:
- Is it still in `settings.json`? If not → **REMOVE**
- Is the `.sh` file present on disk? If not → flag as **MISSING FILE**

Also check `.claude/hooks/` for `.sh` files not referenced in `settings.json` → flag as **UNREGISTERED HOOK** (warn, don't auto-add).

### Rules Section

Compare `.claude/rules/*.md` files against the **Rules** table in CLAUDE.md.

- File present but not in table → **ADD**
- File in table but deleted from disk → **REMOVE**
- Description changed → **UPDATE**

### Commands Section

Compare `.claude/commands/*.md` files against the **Commands** section in CLAUDE.md.

- File present but not listed → **ADD** (extract description from the command file's first paragraph)
- File deleted but still listed → **REMOVE**

### Agents Section

Compare `.claude/agents/*.md` files against the **Agents** table in CLAUDE.md.

- Agent present but not in table → **ADD** (extract role from agent file's first paragraph)
- Agent deleted but still listed → **REMOVE**

---

## Step 3 — Show Diff

Print a clear diff of what will change. Format:

```
CLAUDE.md Sync Report
=====================

Hooks — Blocking:
  + check-unity-event.sh     → UnityEvent, UnityEvent<T>, using UnityEngine.Events
  + check-time-scale.sh      → Time.timeScale = assignment
  ~ check-vcontainer-singleton.sh  (description updated)

Hooks — Warning:
  (no changes)

Rules:
  (no changes)

Commands:
  + update-claude-md  → Sync CLAUDE.md with settings.json, hooks, rules, and agents

Agents:
  (no changes)

Unregistered hooks (on disk but not in settings.json):
  ! warn-reviewer-priority.sh — not in settings.json, skipped

Legend: + add  - remove  ~ update  ! warning
```

If there are zero changes across all sections, print:
```
CLAUDE.md is up to date. No changes needed.
```
and stop.

---

## Step 4 — Confirm

Ask: **"Apply these changes to CLAUDE.md? (yes / no)"**

Wait for explicit confirmation before writing.

---

## Step 5 — Apply Changes

Update only the affected sections in CLAUDE.md. Do not rewrite unrelated content.

Rules for each section:

**Hooks table** — maintain two sub-tables (Blocking / Warning). Each row: `| hook-name | description |`. Sort alphabetically within each group. Remove the `.sh` extension from hook names in the table.

**Rules table** — each row: `| filename.md | one-line description |`. Extract description from the first sentence of the rule file.

**Commands section** — maintain category groupings. Each entry: `| /command-name | description |`. Extract description from the command file's first paragraph.

**Agents table** — each row: `| agent-name | role |`. Extract role from the agent file's first paragraph.

---

## Step 6 — Report

Print a summary:
```
CLAUDE.md updated.
  Hooks:    +2 added, 0 removed, 1 updated
  Rules:    no changes
  Commands: +1 added
  Agents:   no changes
```

Do NOT commit automatically. The user commits via `/smart-commit`.
