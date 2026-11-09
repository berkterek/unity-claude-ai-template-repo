# Optional Plugins

Moved from `.claude/CLAUDE.md` on 2026-11-06. Optional Claude Code plugins; each pipeline command checks for these at
its Step 0/0.5 Plugin Preflight.

| Plugin | Commands | Threshold |
|--------|----------|-----------|
| `superpowers:test-driven-development` | `/implement` | always |
| `superpowers:brainstorming` | `/implement` (score ≥ 0.7), `/scene-setup` (score ≥ 0.7), `/architect` | conditional |
| `superpowers:systematic-debugging` | `/fix` (score ≥ 0.4), `/fix-deep` (score ≥ 0.4), `/debug-session` | conditional |
| `superpowers:verification-before-completion` | `/architect`, `/orchestrate`, `/qa`, `/validate`, `/migrate` (score ≥ 0.7) | conditional |
| `code-simplifier` | `/implement` | always |
| `claude-md-management:revise-claude-md` | `/implement`, `/fix` | always |

**Unity official plugin (`unity:*`):** this repo's rules win on every conflict; the CLI's live-Editor code channel
(`unity command` incl. `eval`, `unity run --command`, `unity shell`) is forbidden and blocked by `check-unity-cli.sh`;
`unity:new-unity-project` never replaces `/setup-project`; `unity:ui-ugui` / `unity:ui-uitk` output is reshaped to
our rules before it lands. → `docs/incidents/mcp-and-framework.md`
