# Plan Summary — Design Spec

**Date:** 2026-06-17  
**Status:** Approved

## Problem

After `/create-plan` or `/update-plan`, there is no alignment checkpoint between planning and execution. The user has no quick way to verify that the plan matches their intent before invoking `/orchestrate` or `/implement`.

## Solution

A standalone `/plan-summary <file>` command backed by a simple skill. It reads the plan file and produces a fixed 3-section human-readable summary. No gate, no agent spawn, no file modification.

## Command

```
/plan-summary <file>
```

Example: `/plan-summary docs/WORKFLOW.md`

## Output Format (fixed)

```
## Plan Özeti — <filename>

### Ne yapıyoruz?
[1-2 sentences. Which part of the project we're touching and why.]

### Nasıl yapıyoruz?
[Bullet list of task flow in plain language. Not technical — human-readable steps.]

### Sonunda ne göreceğiz?
[Observable outcomes. Format: "X will work", "Y will appear in Inspector", "Z test will pass".]
```

## Skill Behavior

- Reads only the plan file specified as argument
- Does NOT read source code files
- Does NOT spawn agents
- Does NOT modify the plan file
- Does NOT wait for user approval (no gate)
- Output tone: plain language, not implementation detail

## Error Cases

| Condition | Output |
|-----------|--------|
| File not found | `"Dosya bulunamadı: <path>. Önce /create-plan çalıştırın."` |
| File has no tasks | `"Plan dosyası task içermiyor. /update-plan ile içerik ekleyin."` |

## Typical Workflow

```
1. /create-plan docs/WORKFLOW.md "add audio system"
2. /plan-summary docs/WORKFLOW.md   ← alignment check
3a. Looks right → /orchestrate
3b. Something missing → /update-plan docs/WORKFLOW.md "also add X"
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `.claude/skills/core/plan-summary.md` | Create — skill definition |
| `.claude/docs/commands.md` | Add entry under "Session & Context" |

## Out of Scope

- Auto-triggering after `/create-plan` (user invokes explicitly)
- Gate / approval flow
- Reading source code for deeper analysis
- Modifying plan files
