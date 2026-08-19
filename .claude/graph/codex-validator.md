# Codex Graph-Accuracy Validator

Use this prompt template with the `codex:codex-rescue` skill (see `/fix-codex` Step 1 for the
invocation pattern). Run on-demand — typically after every extractor change or schema version bump.

**Acceptance threshold:** ≥ 95% agreement on a 20-sample run.

---

## Prompt to hand to codex:codex-rescue

```
TASK: Validate accuracy of .claude/graph/graph.json.
Do NOT trust the graph — re-read source files yourself.

INPUT: .claude/graph/graph.json
SAMPLE_SIZE: 20 (5 classes, 5 events, 5 installers, 5 prefabs — balanced)

For each sampled entry:
  1. Open the file listed in the entry's "file" field.
  2. Verify every claim in the entry:
     - class: name, namespace, implements[], events_published[], events_subscribed[],
               has_static_instance, is_mono_behaviour
     - event: name, publishers[], subscribers[]
     - installer: name, registrations[].type, registrations[].lifetime
     - prefab: name, path, domain, isVariant, basePrefab (if applicable)
  3. If any claim is wrong → record under disagreements[].
  4. If a class/event/installer/prefab exists on disk but is missing from the graph → record
     under missing_in_graph[].
  5. If a graph entry references a file that does not exist → record under extra_in_graph[].

OUTPUT (JSON):
{
  "sampled": 20,
  "agreements": <number of correct claims>,
  "disagreements": [
    {
      "entry": "<graph entry name>",
      "claimed": "<what graph says>",
      "actual": "<what file says>",
      "file_line": "<file:line>"
    }
  ],
  "missing_in_graph": ["<class/event/installer/prefab name>"],
  "extra_in_graph":   ["<graph entry name>"]
}

Report agreement percentage: agreements / (agreements + disagreements.length) * 100.
If < 95%: list all disagreements and recommend running graph-builder.py --full.
```

---

## When to Run

| Trigger | Command |
|---------|---------|
| After changing an extractor script | `/build-knowledge-graph --validate-with-codex` |
| After a schema version bump | Manually via codex:codex-rescue |
| Periodic spot-check (monthly) | Manually via codex:codex-rescue |
| After a large refactor (50+ file changes) | `/build-knowledge-graph --full --validate-with-codex` |

## Interpreting Results

| Agreement | Action |
|-----------|--------|
| ≥ 95% | No action needed |
| 85–94% | Investigate disagreements; fix extractor if pattern-based |
| < 85% | Run `graph-builder.py --full`; if still < 85%, extractor has a bug — file an issue |
