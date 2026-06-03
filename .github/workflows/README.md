# Workflows

## claude-pr-review.yml

Runs `anthropics/claude-code-action` against every PR that touches source, packages, docs, or `.claude/`. Requires the repo secret:

- `ANTHROPIC_API_KEY` — your Anthropic API key. Add at **Settings > Secrets and variables > Actions**.

The workflow uses `-p` (non-interactive) so it never hangs waiting for input. It reviews against the project's own `.claude/CLAUDE.md` conventions.
