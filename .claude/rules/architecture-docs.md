---
paths:
  - "**/ARCHITECTURE.md"
---
# ARCHITECTURE.md Intent Docs

> Moved verbatim from `rules/architecture.md` on 2026-10-08 so it loads only when an `ARCHITECTURE.md` is read or
> edited. Creating a **new** one does not trigger this rule (a new-file Write never fires `paths:`), so
> `/new-module` and `/setup-project` Read it first. `check-architecture-doc.sh` blocks a malformed doc regardless.

### ARCHITECTURE.md — one per Concretes domain

Every `Concretes/<Domain>/` carries an `ARCHITECTURE.md`. Never under `Abstracts/` — interface files document themselves. Written in **English**, like the rest of this repo. One H1, then exactly these four `##` headings, in this order:

```
## Purpose          ← one sentence; if it needs "AND", the domain is two domains
## Boundary         ← what this domain never does, and which domain owns that instead
## How to extend    ← the SHAPE of an extension: layer, folder, wiring method
## Gotchas          ← the mistake people actually make here
```

**Hard cap 40 lines. No class-name-like symbols anywhere** — including `## How to extend`. Detected by `\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b`. Identifiers ending in `Module` are exempt **by design**: module names are convention-fixed by `bootstrap-pattern.md` and never renamed, so naming one cannot rot.

Describe shape, not names:

```markdown
## How to extend
New ability: contract interface in Abstracts/<domain>/ → pure C# handler in
Concretes/<domain>/ → register in this domain's Module.Install. The controller
creates it in Awake, or via a Func<> factory if it needs a container dependency.
```

Concrete type names come from `/knowledge-graph implementers <interface>`, not from this file.

**No domain is exempt, `Infrastructure/` included.** It hosts the project's most frequently confused boundary (app-lifetime vs. scene-lifetime registration; scope vs. module), so it needs a boundary statement more than most. Its doc is a short **pointer** — state the boundary, then delegate detail to `rules/bootstrap-pattern.md` rather than restating six cards.

**Why intent only.** voxel-blast applied a fat version of this convention with real discipline — 25 docs, 8031 lines — and 15 of the 25 are factually wrong today, because a `Car` → `Turret` rename never propagated (0 `Car*.cs` on disk, 29 `Turret*.cs`). Every rotted line contained a class name; no intent line rotted. `/knowledge-graph` already owns the inventory half of documentation, so these docs carry only the half that survives refactoring.

Missing doc → warning (`check-architecture-doc.sh`, exit 0). Malformed doc → block (exit 2). The reading side of this convention — which agents and commands consult these docs — is tracked in `docs/PLAN_architecture_doc_consumption.md`.

### `_Framework/<Subfolder>/` — the same contract, for a stricter boundary

**Every `_Framework/` subfolder that owns an `.asmdef` carries an `ARCHITECTURE.md` too**, with the identical
four headings, the identical 40-line cap, and the identical ban on class-name-like symbols.

The reason differs from the `Concretes/` case, and the difference is what makes it non-negotiable rather than
tidy. A `Concretes/<Domain>/` doc records a **feature** boundary — a convention, enforced by review. A
`_Framework/<Subfolder>/` doc records an **assembly** boundary, and an assembly boundary is a physical fact:
`noEngineReferences`, platform filters and `defineConstraints` are per-`.asmdef`, therefore per-folder, and
unenforceable per-file. The folder *is* the boundary, so the folder is what gets documented.

The `.asmdef` is also the scope test, which is why there is no skip list. `Installers/` holds one interface
and owns no `.asmdef`, so it is not a boundary and is exempt automatically; a folder that later gains an
`.asmdef` starts being asked for a doc on the same day it becomes one.

**No doc at the `_Framework/` root.** Same reason `Concretes/` has none: one doc per boundary, and the root is
not one — it is a container for independent assemblies whose whole point is that they do not reference each
other. `check-architecture-doc.sh` blocks a root doc explicitly.

### A declared top-level folder gets the same gate, automatically

A folder added to `.claude/path-allowlist.txt` is in scope too. This is not a third rule: the allowlist's own
stated grounds for an entry is *"the folder needs its own `.asmdef`"*, which is the assembly-boundary
criterion above, word for word. One rule, applied wherever that criterion holds.

The unit is resolved mechanically — **the nearest directory at or below the scope root that owns an
`.asmdef`** — so both real layouts work with no configuration: a folder split into per-domain assemblies
documents each subfolder; a folder that is itself one assembly documents its own root. A subfolder that owns
no `.asmdef` is not a boundary and is exempt.

**The mechanism is `_arch_doc_scope()` in `check-architecture-doc.sh`, plus `path-allowlist.txt`.** Adding a
project folder to the gate means adding a line to the allowlist and nothing else — no hook edit, no registry,
and **no marker to register** (`arch_doc_marker()` has never existed — delete any reference to it). History and
the measurement correction: `docs/incidents/architecture-doc-gate.md`.
