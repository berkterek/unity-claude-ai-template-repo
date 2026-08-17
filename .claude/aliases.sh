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
alias claude-normal='claude --model claude-sonnet-5'

# Heavy — Claude Opus
# Deep thinking: /architect, /plan-workflow, /game-idea, /add-feature
alias claude-heavy='claude --model claude-opus-5'

# Frontier — Claude Fable 5 (opt-in, NOT a project tier)
# 2x Opus 5 pricing, always-on thinking, minutes-long turns. Only worth it for
# long-horizon autonomous work, which this repo's gate-driven pipelines are not.
# See .claude/docs/model-tiers.md → "Why not Claude Fable 5".
# alias claude-frontier='claude --model claude-fable-5'

# ---------------------------------------------------------------------------
# Fallback tiers — previous-generation models
#
# Use when the current-generation model is unavailable: sustained 529
# overloaded_error, or a rate limit you can't wait out. Opus 5 / Sonnet 5 draw
# from RATE-LIMIT BUCKETS SEPARATE from the 4.x pool, so dropping a generation
# genuinely gives you fresh headroom — it is not the same quota.
#
# Prefer /model inside a running session over restarting with these: it keeps
# your context. Restart only when the session itself is unusable.
#
# See .claude/docs/model-tiers.md → "When the Current Model Is Unavailable".
# ---------------------------------------------------------------------------

alias claude-heavy-fallback='claude --model claude-opus-4-7'
alias claude-normal-fallback='claude --model claude-sonnet-4-6'

# Last resort for the heavy tier. Opus 4.6 still accepts budget_tokens and
# sampling params that 4.7+ reject, so third-party tooling written for older
# models works here — at a real capability cost. Prefer 4.7.
# alias claude-heavy-fallback-old='claude --model claude-opus-4-6'
