# Checkpoint — Context Save & Clear

Use this command when context is getting full (70%+) and you want to continue working without losing progress.

## What This Does

1. Summarizes the current conversation into a checkpoint file
2. Saves it to `.claude/state/checkpoint.md`
3. Instructs you to run `/clear`
4. Next session automatically reads the checkpoint and resumes

## Steps

### Step 1: Write Checkpoint

Write a comprehensive checkpoint to `.claude/state/checkpoint.md` with this exact structure:

```markdown
# Checkpoint
**Saved:** [ISO datetime]
**Branch:** [current git branch]

## What We Were Doing
[1-3 sentences: the task, feature, or bug we were working on]

## Decisions Made
- [decision and why]
- [decision and why]

## Files Changed This Session
- [file path] — [what changed]

## Current State
[Where exactly we are: what's done, what's in progress, what's broken]

## Next Step
[The very next action to take when resuming — be specific]

## Context That Would Be Lost
[Any important details, constraints, or discoveries from this conversation that aren't in the code or docs]
```

### Step 2: Confirm & Instruct

After saving the file, tell the user exactly this:

```
Checkpoint saved to .claude/state/checkpoint.md

Now do these two steps:
1. Run: /clear
2. After /clear, send this message: read .claude/state/checkpoint.md
```

### Step 3: On Resume (after /clear)

When the user says "read .claude/state/checkpoint.md", immediately read the file and acknowledge:

```
Resuming from checkpoint ([datetime]):
[one sentence summary of where we were]

Continuing: [next step from checkpoint]
```

Then delete the checkpoint file — it has been consumed:
```bash
rm .claude/state/checkpoint.md
```
