# ARCHITECTURE.md Gate — How Its Scope Was Found

Moved verbatim from `.claude/rules/architecture.md` on 2026-10-08; the rule it supports stays there in short form.

**The mechanism is `_arch_doc_scope()` in `check-architecture-doc.sh`, plus `path-allowlist.txt`.** Adding a
project folder to the gate means adding a line to the allowlist and nothing else — no hook edit, no registry,
and **no marker to register**. If you find a reference anywhere to registering a marker with a function named
`arch_doc_marker()`, delete it: that function has never existed in this repo. It was invented mid-conversation
as a plausible-sounding mechanism and repeated until it read like fact. A named function is exactly the kind
of detail that survives a summary while the check that would have caught it does not — verify before you
propagate.

**What this was fixing.** The convention was written when `_Framework/` held only `Events/`, and stayed
scoped that way after `/setup-project` began generating `Logging/` and `SaveLoadSystems/`. The evidence that
the gap was real, rather than theoretical: the reason `DLog.Error` is deliberately neither `[Conditional]`
nor tag-filtered lived **only** as a comment inside `DLog.cs`, because there was nowhere else to put it — and
a project that inherited the framework carried the defect that comment describes for months, unnoticed. A
load-bearing decision parked in a source comment survives exactly as long as nobody tidies the file.

One measurement correction against `docs/PLAN_framework_architecture_docs.md`, which recorded that the hook
**blocked** such a doc and therefore had to change first: it did not. It fell through to `exit 0` — silently
accepted, never validated. That is worse than a block, because nothing tells the author the doc went
unchecked. The hook now validates both scopes.
