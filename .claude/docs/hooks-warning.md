# Warning Hooks (exit 0 — logs to stderr, does not block)

| Hook | Warns |
|------|-------|
| `check-naming-conventions.sh` | Non-PascalCase types, wrong field naming |
| `check-no-linq-hotpath.sh` | LINQ in Update/FixedUpdate/LateUpdate |
| `check-no-hotpath-expensive-calls.sh` | `GetComponent`, `Camera.main`, `FindObjectOfType`, bare `transform.`, `tag ==`, `SendMessage` inside Update/FixedUpdate/LateUpdate/Tick/FixedTick/LateTick — suppressed if `_transform` field is cached |
| `check-getcomponent-in-awake.sh` | `GetComponent`/`GetComponentInChildren` in `Awake` — prefer `[SerializeField]` Inspector assignment for all components including `Transform`; only acceptable when component is added dynamically at runtime |
| `check-no-runtime-instantiate.sh` | `new GameObject()` — **blocked** outside Pool/Factory/Spawner and Editor files; `Destroy()` — warning only (`Instantiate(prefab)` is allowed) |
| `check-test-exists.sh` | Logic class with no corresponding test file — skipped if `testing=false` in `project-features.json` |
| `check-compile.sh` | Basic C# syntax (braces, namespace, type declaration) |
| `warn-serialization.sh` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `warn-filename.sh` | C# filename doesn't match primary class name |
| `check-unused-code.sh` | Unused private members, unused imports |
| `check-namespace-format.sh` | Namespace not in `Layer.Module` format |
| `check-event-naming.sh` | `IEvent` struct without `Event` suffix or not past tense |
| `check-ecs-structural-changes.sh` | `EntityManager.AddComponent/RemoveComponent/DestroyEntity` inside ECS system (use ECB) — skipped if `ecs=false` in `project-features.json` |
| `check-async-void.sh` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation.sh` | `async UniTask` methods without `CancellationToken` parameter |
| `check-null-propagation.sh` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |
| `detect-gaps.sh` (SessionStart) | Scans for undocumented systems, missing tests, and orphaned modules at session start |
| `session-start.sh` (SessionStart) | Loads session state at session start |
| `track-codex-review.sh` (PostToolUse) | Creates `.claude/state/codex-reviewed` when `codex:codex-rescue` agent completes — enables `unity-reviewer` as fallback in reviewer-order enforcement |
| `instinct-capture.sh` (PostToolUse) | Captures tool-use observations for later distillation into instincts |
| `cost-tracker.sh` (PostToolUse) | Logs every tool call with timestamp for cost auditing |
| `instinct-distill.sh` (Stop) | Distills captured observations into confidence-scored instincts |
| `pre-compact.sh` (Stop) | Prompts Claude to save session state before context compaction |
| `session-restore.sh` (SessionStart) | Restores session state from `.claude/state/` on session start |
| `session-save.sh` (Stop) | Saves current session state to `.claude/state/` on stop |
