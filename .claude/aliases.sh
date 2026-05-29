#!/usr/bin/env sh
# Unity Claude AI Template — Model Tier Aliases
#
# Add to your shell profile:
#   source /path/to/your-unity-project/.claude/aliases.sh
#
# Or add the lines below directly to ~/.zshrc / ~/.bashrc

# Light — Claude Haiku
# Quick tasks: /dump, /five, /mermaid, /create-changelog, /context-prime
alias claude-light='claude --model claude-haiku-4-5'

# Normal — Claude Sonnet (default)
# Balanced work: /review-code, /debug-session, /validate, /generate-tests, /new-module
alias claude-normal='claude --model claude-sonnet-4-6'

# Heavy — Claude Opus
# Deep thinking: /architect, /plan-workflow, /game-idea, /add-feature
alias claude-heavy='claude --model claude-opus-4-8'
