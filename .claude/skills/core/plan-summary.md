---
name: plan-summary
description: Reads a plan file and produces a three-part, plain-language summary — what we are building, how, and what we will see at the end. No gates, no agent spawns.
---

# Plan Summary

Read the given plan file and produce the fixed three-part summary below. Running this skill means:

1. Read the `<file>` argument
2. If the file does not exist: print `"File not found: <path>. Run /create-plan first."` and stop
3. If the file contains no tasks: print `"Plan file contains no tasks. Add content with /update-plan."` and stop
4. Produce the summary in the format below — write nothing else

## Output Format (do not change it)

```
## Plan Summary — <file name>

### What are we building?
[1-2 sentences. Which part of the project this touches and why. No technical detail.]

### How are we building it?
[Bullet list. One line per task, in plain language. Not "add Register<T> to AudioInstaller" → "the audio system gets wired into dependency injection".]

### What will we see at the end?
[Observable outcomes. Every item must be something you can observe. Not "code will be written" → "you will hear sound when you run the game". Shape: "X works / Y appears in the Inspector / test Z passes".]
```

## Rules

- Read only the plan file — never open source files
- Write nothing outside the summary sections (no preamble, no commentary, no suggestions)
- Every item in the outcome section must be observable
- Tone: plain language, minimal jargon
