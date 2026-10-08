# Skills Library — Loading and Enforcement

Moved verbatim from `.claude/CLAUDE.md` on 2026-10-08; the rule it supports is stated there in short form.

> **Correction, 2026-10-08:** the first paragraph below claimed these skills were `@`-referenced into every
> session. They never loaded: imports resolve relative to the importing file, so every `@.claude/...` path
> inside `.claude/` pointed at a non-existent `.claude/.claude/...` (measured — see
> `docs/superpowers/specs/2026-10-08-instruction-loading-spike.md`). The list is now a described index
> injected at SessionStart by `session-restore.sh`.

Skills under `third-party/`, `plugins/`, `learned/`, and `platform/` are listed (path + description) in `auto-loaded-skills.md`, which `session-restore.sh` injects at every SessionStart. Until 2026-10-08 the file used `@.claude/…` imports, which resolve relative to the importing file and so never loaded at all; the list replaced them. The `auto-load-skills.sh` PostToolUse hook keeps it in sync whenever a skill file is written.

**Agent-side skill loading:** All code-writing, review, and exploration agents (`unity-coder`, `coder`, `tester`, `reviewer`, `unity-fixer`, `debugger`, `unity-scout`, and 20+ others) include a **Step 0** that reads `auto-loaded-skills.md` and then loads every relevant skill before starting work. This ensures subagents — which do not receive the parent session's SessionStart injection — still know which skills exist. `unity-git-master` reads `.claude/skills/core/unity-git.md` at Step 0 for the same reason. `committer` carries the same Step 0, but it runs **both** ways: the nine commit-capable pipelines commit inline (session model, skill list already injected), while `/create-plan`, `/update-plan`, and `audio-clip-agent` spawn it as a real subagent on `sonnet`. Its Step 0 is load-bearing on the spawned paths and redundant on the inline ones. See `.claude/agents/committer.md` for the split.

**Skill enforcement (NON-NEGOTIABLE):** `enforce-skill-for-keywords.sh` (UserPromptSubmit hook) detects third-party package keywords in every prompt (strict profile; text inside pasted blocks is ignored). Since 2026-10-08 `auto-loaded-skills.md` is a plain list, not an `@`-import, so being listed there no longer skips enforcement — only a `Skill` invocation earlier this session does. A skill at `.claude/skills/<name>/SKILL.md` gets a blocking demand — you MUST invoke the skill before writing code, giving advice, or calling MCP tools. A nested reference skill (`third-party/…`, `plugins/…`) gets a Read pointer instead, because the Skill tool cannot invoke it. `track-skill-invocations.sh` (PostToolUse/Skill hook) records each Skill tool invocation. To add a new keyword mapping, edit the `KEYWORD_MAP` array in `.claude/hooks/enforce-skill-for-keywords.sh`.
