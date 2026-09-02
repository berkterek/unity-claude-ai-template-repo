# PLAN — `subagent-depth` is blind to a `SendMessage` resume

**Status:** open · **Created:** 2026-09-02 · **Raised by:** a real `/orchestrate` run in a downstream project

## The defect

An agent resumed with `SendMessage` fires **no** `PreToolUse/Agent`, so `agent-start-log.sh` never runs and
the depth counter is never incremented — while a subagent genuinely is running.

Measured, not inferred:

```
settings.json  PreToolUse   matcher=Agent   agent-start-log.sh
settings.json  PostToolUse  matcher=Agent   agent-stop-log.sh
grep -c SendMessage .claude/settings.json  ->  0
```

This is a **new leak direction**. Every cause listed in `CLAUDE.md` until now made the counter read too
**high** (an interruption, a terminal error, a session ending mid-agent, the Agent tool's retry path). This
one makes it read too **low**.

## Why the low direction is worse

The two consumer families resolve a doubtful count in deliberately opposite directions, so a count that is
too low is wrong for both — and wrong loudly in one place, silently in the other:

| Consumer | Reads 0 as | Effect while a subagent really is running |
|---|---|---|
| `guard-pipeline-direct-work.sh` | "the Director is doing this" | **Blocks the subagent's own `Write`.** Loud, self-announcing, and now named in the block message. |
| `gateguard.sh`, `guard-critical-files.sh`, `check-config-protection.sh` | "not inside a subagent, apply the gate normally" — these *pass* on 0 | **Releases that subagent through the gate.** Silent. Nothing reports it, and the whole point of those gates is that a subagent must not sail past them. |

The second row is the reason this is a real item and not a nuisance. The first row is what got noticed.

## Why the obvious fix is wrong

Registering the two logging hooks on `Agent|SendMessage` looks like a one-line fix and is not one.
`SendMessage`'s `to` is a plain name that may address:

- an in-process subagent (a resume — should increment),
- **`main`** — a subagent messaging the Director, which happens *inside* a subagent where depth is already
  correct (must not increment),
- another local Claude session, a cloud session, or a Remote Control session (must not increment).

Incrementing for the last two hands the Director `depth > 0`, which is precisely the bypass
`guard-pipeline-direct-work.sh` exists to prevent. A fix that over-permits the Director is worse than the
defect it replaces.

## What has to be measured before a fix is written

The blocking unknown is: **can a hook tell an in-process subagent resume from a cross-session message?**
The current audit log cannot answer it — `subagent-log.jsonl` records `agent_type` and `description`, never
the agent's *name*, and `to` is a name.

Three things to establish, in order. Do not write the fix before all three are answered with a measurement:

1. **Does `PostToolUse/Agent` carry the spawned agent's name in `tool_response`?** If it does,
   `agent-stop-log.sh` can record it, and a later `SendMessage` whose `to` matches a name this session
   spawned is a resume. This is the most promising route and it is a pure observation — dump one payload.
2. **Does any hook payload distinguish "this tool call is happening inside a subagent"?** If such a field
   exists, the counter is the wrong mechanism entirely and every consumer should read that instead. Worth
   ten minutes before building anything on top of the counter.
3. **Does `PostToolUse/SendMessage` fire on a resume, and when?** `PostToolUse/Agent` already fires on
   dispatch *acknowledgement* rather than completion — hence the deferred-decrement machinery. If the
   resume path behaves the same, the fix must reuse `unity_subagent_schedule_decrement`, not invent a
   second timing model.

## Interim guidance (already shipped)

- `guard-pipeline-direct-work.sh`'s block message names this cause and says what to do: correct the counter,
  do **not** write `pipeline-override` — that file asserts the user approved *skipping* the pipeline, which
  is false when the pipeline is what is doing the work. Recording a convenient lie is worse than fixing a
  wrong number.
- Correcting the counter by hand must clear `subagent-depth-pending.jsonl` in the same command. Measured: a
  hand-written `1` is reset to `0` by the very next hook read when a matured decrement is still queued, so
  the correction silently evaporates and the agent is blocked again mid-run — with the same symptom, inviting
  the same misdiagnosis a second time.
- The correction has no audit trail, unlike `pipeline-override`. Say in the response what was changed and
  why, and restore the counter when the agent finishes — otherwise the guard stays disabled for the rest of
  the session, which is the actual bypass.

## Not in scope

Do not add an "orchestrate is active" marker file as a shortcut. That was already rejected once for gate
teardown: it moves the same conflict one layer down and creates a second piece of state that can go stale
independently of the first.
