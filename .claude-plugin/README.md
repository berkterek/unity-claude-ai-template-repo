# unity-claude-ai-template — Claude Code Plugin

Opinionated Unity 6 + VContainer + UniTask Claude Code configuration with hook-enforced architecture, 72 skills, 38 agents, 59 slash commands, and Unity Knowledge Graph.

## Install via plugin

```bash
claude plugin install github:berkterek/unity-claude-ai-template-repo
```

## Install manually

```bash
git clone https://github.com/berkterek/unity-claude-ai-template-repo
./unity-claude-ai-template-repo/install.sh /path/to/UnityProject
```

## After install

```
/setup-project
```

Then optionally:

```
/build-knowledge-graph
```

See `.claude/docs/quick-start.md` for the full tour.

## Requirements

- git ≥ 2.0
- jq ≥ 1.6
- python3 ≥ 3.8
- Claude Code ≥ 0.5.0
