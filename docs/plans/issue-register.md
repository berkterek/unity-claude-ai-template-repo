# Issue Register — Unity Claude AI Template

**Purpose:** Master list of every problem found during the July 2026 template audit (3 external review passes + live session log analysis). Single source of truth for what is fixed, what is open, and what needs a decision. Update statuses here as work lands.

**Legend:** Severity = impact if left unfixed. Effort = S (< 1h) / M (half day) / L (multi-day or needs design).

---

## A. RESOLVED ✅ (kept for the record)

| # | Issue | Fix | Evidence |
|---|-------|-----|----------|
| R1 | Graph ghost-purge collapse: single-file incremental wiped 172/173 classes | Full-walk `current_paths` + collapse guard (`14cc640`) | nile rebuilt 1→174, survived real edits |
| R2 | Abs/rel path mix → duplicate classes + silent data decay | realpath+relpath normalization (`57c9340`) | 3-step fixture test clean |
| R3 | Gate deleted on every Stop → re-approval mid-pipeline | Stop cleanup removed; committer-finish + SessionStart deletion (`e5a13de`) | bats + live |
| R4 | Gate written/read via relative path → "gate lost" on cwd drift | `git rev-parse --show-toplevel` on both sides (`4203f2e`) | synced to nile |
| R5 | BSD sed GNUism in 6 hooks + strip-ordering bug → false positives on macOS | python3 `strip_cs_noise` in `_lib.sh` (`a93fb03`) | functional test: block-comment FP gone |
| R6 | settings.json relative hook paths → all hooks die on `cd` (fail-open + 564-line spam) | `$CLAUDE_PROJECT_DIR` prefix (`1362a81`) | **nile: `settings.json.new` awaits Director swap** |
| R7 | Template-mode graph churn dirtied working tree every session | Early-exit when Assets/ absent (`05d832e` + `9843e5a`) | bats |
| R8 | Gate TTL 4h too wide for abandoned pipelines | TTL → 45min + residual-risk doc (`b572e2a`) | bats |
| R9 | Health warning blind: checked `scanned_files==0`, collapsed graph reported 1 | classes-vs-cs-count check, date-keyed sentinel (`14cc640`) | bats |
| R10 | Builder resolved paths against caller cwd → empty graph, exit 0 | chdir repo_root + loud fail (`739523a`, pre-audit) | — |

**Immediate leftovers (do now, S):**
- [ ] nile: `cp .claude/settings.json.new .claude/settings.json && rm .claude/settings.json.new` (Director, manual) + cd-Edit smoke test → closes plan PENDING boxes
- [ ] template: commit uncommitted README Gate-TTL section (`docs(gates)`)

---

## B. OPEN — Structural (need design/decision, discussed one by one)

| # | Issue | Evidence | Severity | Effort |
|---|-------|----------|----------|--------|
| S1 | **Session-start context obesity: ~55k tokens** (CLAUDE.md 2.3k words + 14 docs 10.6k + 23 auto-loaded skills 26k; rules add ~17k). Shrinks working room, dilutes per-rule compliance, costs every session. Lazy-load mechanism (`enforce-skill-for-keywords.sh`) already exists but 23 skills are force-loaded anyway. | measured | HIGH | M |
| S2 | **No template→project distribution mechanism.** No version stamp, no `/update-template`, sync is manual file copy. Observed: nile left half-synced 3× during this audit alone. Multiplies with every project using the template. | 3 sync failures | HIGH | M |
| S3 | **Enforcement asymmetry.** The most important rules (Scripts/ folder placement, Abstracts/Concretes structure, View/Controller/Provider suffixes, namespace convention) have ZERO enforcing hooks; only regex-able content rules are enforced. Proof: nile violates all of them (`Scripts/Core|UI|Gameplay`, `Game.Gameplay.Run`, `RunRecordFlagView` on a gameplay object) with no hook ever firing. Decision needed: add path/suffix hooks vs. delegate architecture rules to reviewer agent + `/knowledge-graph violations`. | nile drift | HIGH | M |
| S4 | **Bash-write bypass.** Content hooks guard only Edit/Write tools; writing files via `python3 -c` in Bash bypasses everything. Observed 3× live (incl. model self-setting `UNITY_HOOK_MODE=warn`). Blocking hooks are effectively advisory against a determined model. | 3 live cases | MED-HIGH | L (design) |
| S5 | **Process weight vs solo-dev reality.** 3 gates per pipeline, mandatory TDD for every class. Real usage: nile set `testing: false` immediately. Hooks have profiles; gates/rules don't. Proposal: `mode: prototype|production` in project-features.json (prototype = SCOPE_GATE only, TDD optional). | nile config | MED | M |
| S6 | **Guard messages teach the bypass.** `guard-gate-cleared.sh` exit-2 text prints the exact command to create the gate file; a session was observed recreating the gate without user approval. Same pattern risk in other guards. | live log | MED | S |

## C. OPEN — Reliability / Mechanical

| # | Issue | Severity | Effort |
|---|-------|----------|--------|
| M1 | Background graph builder has **no concurrency lock** (verified: no flock). Two rapid .cs edits → two builders race on graph.json; last-write-wins can drop the other's update. | MED | S |
| M2 | **CI is Linux-only**; macOS/BSD regressions invisible (the sed bug shipped precisely this way). Add a macOS CI job, or minimum: a lint forbidding GNU-only constructs in hooks. | MED | S-M |
| M3 | Hook bats coverage ~27/49; untested criticals include `enforce-skill-for-keywords.sh`, `stop-verify.sh`, `session-save.sh` edge cases. | MED | M |
| M4 | **25 hooks fire per Edit/Write**, 4-5 per Bash call; aggregate latency never measured. Each spawns bash+jq/python. Measure, then consider consolidating same-event hooks into one dispatcher script. | MED | M |
| M5 | `calls[]` edges are never ghost-purged for deleted files — stale call edges accumulate in graph (noted out-of-scope in purge plan). | LOW | S |
| M6 | Generated `graph.json` gets committed mixed into logic commits (hygiene; partially mitigated by R7). Consider committing graph separately or on a schedule. | LOW | S |
| M7 | Interrupted-pipeline gate leak: 45min TTL accepted as residual risk. Gate payload already contains `"pipeline"` field — guard could reject cross-pipeline reuse if a cheap pipeline-context signal is ever available. | LOW (mitigated) | — |

## D. OPEN — Docs / Consistency (small)

| # | Issue | Effort |
|---|-------|--------|
| D1 | No runtime self-check: pinned model names (34 agents), hook event names, `$CLAUDE_PROJECT_DIR`, `subagent_type` strings can silently break on any Claude Code update. Proposal: `/doctor` command that verifies hooks fire, env vars exist, models resolve. | M |
| D2 | `install.sh` still tells users to manually register 3 hooks that are already wired in settings.json (lines ~93-97). | S |
| D3 | `setup-project.md:162` and `build-knowledge-graph.md:22,64` reference **`graph-builder.sh`** — the file is `graph-builder.py`. Copy-pasted command fails. | S |
| D4 | `commands.md` has no quick-reference table for the 55 commands (prose-only). | S |
| D5 | Mixed TR/EN rule files (`solid-oop.md` TR, rest EN) — fine for personal use, inconsistent for sharing. | S |
| D6 | Template-repo health warning may fire daily (`classes==0` with 0 .cs files is normal in template mode) — small noise; suppress when project has no .cs at all. | S |

---

## Suggested Attack Order

1. **Leftovers** (A) — two S items, minutes.
2. **S1 context diet** — highest per-session return. (User-selected as next topic.)
3. **S2 distribution/update** — kills the recurring sync pain before more projects adopt the template.
4. **S3 enforcement decision** + **S6 guard messages** — one conversation, cheap fixes fall out of it.
5. **M1, M2, D3, D2** — mechanical batch, one afternoon.
6. **S5 mode flag**, **M4 latency**, **D1 /doctor** — as capacity allows.
