#!/usr/bin/env sh
# Unity Claude AI Template — Model Tier Aliases
#
# Add to your shell profile:
#   source /path/to/your-unity-project/.claude/aliases.sh
#
# Or add the lines below directly to ~/.zshrc / ~/.bashrc

# The three tiers below use the UNVERSIONED aliases haiku / sonnet / opus, the
# same strings the agent frontmatter uses, so Layer 1 and Layer 2 always resolve
# to the same generation. A pinned ID here (claude-opus-5) silently desynced the
# two: the session ran Opus 5 while every spawned agent ran Opus 5.5.
#
# Pinning a version is also not a cost lever in this generation — Opus 5.5 is
# CHEAPER than Opus 5 ($4/$20 vs $5/$25 per MTok) and Sonnet 5.5 costs exactly
# what Sonnet 5 does. Depth is tuned with `effort`, never by holding back a
# generation. See .claude/docs/model-tiers.md.

# Light — Claude Haiku
# Quick tasks: /dump, /five, /mermaid, /create-changelog, /context-prime
alias claude-light='claude --model haiku'

# Normal — Claude Sonnet (default)
# Balanced work: /review-code, /debug-session, /validate, /generate-tests, /new-module
alias claude-normal='claude --model sonnet'

# Heavy — Claude Opus
# Deep thinking: /architect, /roadmap, /plan-module, /game-idea, /grill-me
alias claude-heavy='claude --model opus'

# Frontier — Claude Fable 5 (opt-in, NOT a project tier)
# 2.5x Opus 5.5 pricing, always-on thinking, minutes-long turns. Only worth it for
# long-horizon autonomous work, which this repo's gate-driven pipelines are not.
# See .claude/docs/model-tiers.md → "Why not Claude Fable 5".
# alias claude-frontier='claude --model claude-fable-5'

# ---------------------------------------------------------------------------
# Fallback tiers — previous-generation models
#
# Use when the current-generation model is unavailable: sustained 529
# overloaded_error, or a rate limit you can't wait out. The 5.x models draw
# from RATE-LIMIT BUCKETS SEPARATE from the 4.x pool, so dropping a generation
# genuinely gives you fresh headroom — it is not the same quota.
#
# These stay PINNED on purpose: their whole job is to name one specific older
# generation. An unversioned alias here would resolve back to the model that is
# already failing.
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
