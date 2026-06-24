# Workflows

## claude-pr-review.yml

Runs `anthropics/claude-code-action` against every PR that touches source, packages, docs, or `.claude/`. Requires the repo secret:

- `ANTHROPIC_API_KEY` — your Anthropic API key. Add at **Settings > Secrets and variables > Actions**.

The workflow uses `-p` (non-interactive) so it never hangs waiting for input. It reviews against the project's own `.claude/CLAUDE.md` conventions.

## hook-tests.yml

Runs the bash hook test suite (bats-core) plus `shellcheck` on every change under `.claude/hooks/` (and on changes to its own YAML; also `workflow_dispatch` for manual runs). This is the regression gate the false-positive hooks lacked — a broken or over-broad hook turns the check red instead of silently shipping. Uses `sudo npm install -g bats` (bats-core), **not** the obsolete apt `bats` 0.4 fork.

> **Why `sudo`:** the GitHub runner's `/usr/local` npm global prefix is not writable by the unprivileged `runner` user. A plain `npm install -g bats` fails with `EACCES` on `/usr/local/share/man/man7` (exit 243) before any test runs. This passes locally (where `/usr/local` is writable) so it only ever surfaced on the runner.

**Run locally:**

```bash
brew bundle                          # installs bats-core + shellcheck (see /Brewfile)
bash .claude/hooks/tests/run-tests.sh
```

## graph-tests.yml

Runs the knowledge-graph integration harness (`.claude/graph/test/verify-graphify.sh`) on every change under `.claude/graph/` (and on changes to its own YAML; also `workflow_dispatch`). Installs `jq` + Python 3.12.

> **`graph.json` is committed, not gitignored.** `verify-graphify.sh` hard-exits 2 (`graph.json not found`) if the file is absent — it does not build it. `actions/checkout` only delivers tracked files, so `.claude/graph/graph.json` **must** be committed alongside its siblings `scenes.json` / `prefabs.json` (CLAUDE.md: "generated and committed together"). It was previously gitignored, which turned this check red on every runner while passing locally. Consequence: every `/build-knowledge-graph` now produces a `graph.json` diff — same tradeoff the already-committed `scenes.json`/`prefabs.json` carry.

**Run locally:**

```bash
bash .claude/graph/test/verify-graphify.sh   # needs a present, valid graph.json
```

## Action versions

All workflows pin `actions/checkout@v5` and `actions/setup-python@v6` (Node 24). The older `@v4`/`@v5` targeted Node 20, which GitHub now force-runs on Node 24 and flags as a deprecation annotation — bumping clears the warning. `anthropics/claude-code-action@v1` is third-party and left as-is.

### Known non-POSIX regex (follow-up)

The 4 hooks fixed in `PLAN_hook_test_infrastructure.md` were converted to POSIX classes (`[[:space:]]`, `[[:alnum:]_]`). Other hooks still use `\s`/`\w`/`\?`, which work on GNU grep (CI) and BSD grep (macOS) but break silently under ugrep. CI on ubuntu uses GNU grep, so it does **not** catch a grep-flavor regression — a full POSIX sweep + a ugrep CI matrix are tracked follow-ups. To list remaining offenders:

```bash
grep -REln '\\(s|w)' .claude/hooks/*.sh
```

