# Workflows

## claude-pr-review.yml

Runs `anthropics/claude-code-action` against every PR that touches source, packages, docs, or `.claude/`. Requires the repo secret:

- `ANTHROPIC_API_KEY` — your Anthropic API key. Add at **Settings > Secrets and variables > Actions**.

The workflow uses `-p` (non-interactive) so it never hangs waiting for input. It reviews against the project's own `.claude/CLAUDE.md` conventions.

## hook-tests.yml

Runs the bash hook test suite (bats-core) plus `shellcheck` on every change under `.claude/hooks/`. This is the regression gate the false-positive hooks lacked — a broken or over-broad hook turns the check red instead of silently shipping. Uses `npm install -g bats` (bats-core), **not** the obsolete apt `bats` 0.4 fork.

**Run locally:**

```bash
brew bundle                          # installs bats-core + shellcheck (see /Brewfile)
bash .claude/hooks/tests/run-tests.sh
```

### Known non-POSIX regex (follow-up)

The 4 hooks fixed in `PLAN_hook_test_infrastructure.md` were converted to POSIX classes (`[[:space:]]`, `[[:alnum:]_]`). Other hooks still use `\s`/`\w`/`\?`, which work on GNU grep (CI) and BSD grep (macOS) but break silently under ugrep. CI on ubuntu uses GNU grep, so it does **not** catch a grep-flavor regression — a full POSIX sweep + a ugrep CI matrix are tracked follow-ups. To list remaining offenders:

```bash
grep -REln '\\(s|w)' .claude/hooks/*.sh
```

