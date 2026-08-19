#!/usr/bin/env python3
"""test_scope_parent_resolution.py — pins scope-parent resolution across BOTH routes.

The bug this locks down: `scope_parents` reported a bare `null` for every LifetimeScope whose
parent is assigned in code, and `/knowledge-graph scope-tree` presents the graph as source of
truth — so "parent unresolved" was read as the fact "this scope has no parent". In
piggy-doku-repo that meant the graph asserted GameScope had no parent while GameScope.Configure()
carries an explicit LogError describing exactly how catastrophic a missing parent would be (a
second IEventBus, publishers and subscribers on different buses, every test still green).

A LifetimeScope's parent arrives by two routes, both ending in the same runtime call
(`LifetimeScope.GetRuntimeParent()` -> `Find(parentReference.Type)`):

  code      — `parentReference = ParentReference.Create<T>()` in Awake(), before base.Awake().
              Read by csharp_extractor.py, with or without Unity running.
  inspector — the serialized `parentReference.TypeName` on the prefab. Read by the MCP extractor
              (mcp-extractor.md Step 2b), only with the Editor connected. Note the Inspector
              control is a TYPE-NAME DROPDOWN, not an object picker
              (VContainer Editor/ParentReferencePropertyDrawer.cs), so this route works across
              scenes — a comment claiming otherwise is wrong.

Code wins on conflict, because `Create<T>()` overwrites the whole struct at runtime and so
discards whatever the Inspector held.

Stdlib-only (no pytest) per project convention — this is tooling, not Unity C#.

Run: python3 .claude/graph/test/test_scope_parent_resolution.py
Exit codes: 0 = all passed, 1 = at least one failure,
            0 with "SKIP" printed = tree-sitter unavailable (not a failure).
"""
import importlib.util
import os
import sys


_HERE = os.path.dirname(os.path.abspath(__file__))
_EXTRACTOR_PATH = os.path.join(_HERE, "..", "extractors", "csharp_extractor.py")
_BUILDER_PATH = os.path.join(_HERE, "..", "graph-builder.py")

_failures = []


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(label, actual, expected):
    if actual == expected:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}\n       expected: {expected}\n       actual:   {actual}")
        _failures.append(label)


# ── extractor side: the code route ───────────────────────────────────────────

_SCOPE_CODE_ROUTE = """
using VContainer; using VContainer.Unity;
namespace Game.Concretes.Infrastructure
{
    public sealed class GameScope : LifetimeScope
    {
        protected override void Awake()
        {
            parentReference = ParentReference.Create<AppScope>();
            base.Awake();
        }
        protected override void Configure(IContainerBuilder builder) { }
    }
}
"""

# Fully-qualified generic argument: only the short name may reach the graph, because that is how
# the MCP extractor reports it and how every other node in the graph is keyed. A qualified name
# here would silently fail to join against classes[].name.
_SCOPE_QUALIFIED = """
using VContainer.Unity;
public sealed class MenuScope : LifetimeScope
{
    protected override void Awake()
    {
        parentReference = ParentReference.Create<Game.Concretes.Infrastructure.AppScope>();
        base.Awake();
    }
}
"""

_SCOPE_ROOT = """
using VContainer; using VContainer.Unity;
public sealed class AppScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder) { }
}
"""


def _scopes_for(source):
    """Run the extractor over an in-memory snippet — same helper shape as
    test_extractor_pubsub.py::_extract."""
    lang, ParserCls = csx._try_import()
    parser = ParserCls()
    parser.language = lang
    out = csx.extract_file(parser, "mem.cs", source.encode("utf-8"))
    return out["vcontainer"]["scopes"]


def test_extractor():
    s = _scopes_for(_SCOPE_CODE_ROUTE)[0]
    check("code route: parent read from ParentReference.Create<T>()", s.get("parent"), "AppScope")
    check("code route: parent_source tagged 'code'", s.get("parent_source"), "code")

    s = _scopes_for(_SCOPE_QUALIFIED)[0]
    check("qualified generic arg reduced to the short name", s.get("parent"), "AppScope")

    s = _scopes_for(_SCOPE_ROOT)[0]
    check("root scope claims no parent from code", s.get("parent"), None)


# ── builder side: merge + the unresolved reason ──────────────────────────────


def test_merge():
    m = gb.scope_merge

    out = {x["name"]: x for x in m([], [
        {"name": "GameScope", "parent": "AppScope", "parent_source": "code"},
        {"name": "AppScope"},
    ], [])}
    check("code route survives an empty MCP payload",
          (out["GameScope"]["parent"], out["GameScope"]["parent_source"]), ("AppScope", "code"))
    check("no MCP data -> reason names the missing extraction, not an absent parent",
          out["AppScope"].get("parent_unresolved_reason"), "mcp-extraction-absent")

    out = {x["name"]: x for x in m([], [{"name": "GameScope"}, {"name": "AppScope"}], [
        {"scope_name": "GameScope", "parent_name": "AppScope"},
        {"scope_name": "AppScope", "parent_name": None},
    ])}
    check("inspector route resolves when code says nothing",
          (out["GameScope"]["parent"], out["GameScope"]["parent_source"]),
          ("AppScope", "inspector"))
    check("MCP read it and found nothing -> 'no-parent-declared'",
          out["AppScope"].get("parent_unresolved_reason"), "no-parent-declared")

    # Create<T>() overwrites the struct at runtime, so a differing serialized value is dead
    # config. If the Inspector won here the graph would report a parent the game never uses.
    out = m([], [{"name": "GameScope", "parent": "AppScope", "parent_source": "code"}],
            [{"scope_name": "GameScope", "parent_name": "OtherScope"}])[0]
    check("conflict: code wins over inspector", (out["parent"], out["parent_source"]),
          ("AppScope", "code"))

    # A cache-hit entry carries whatever the previous build wrote. A reason left behind on a
    # now-resolved scope is exactly the misleading-evidence failure this whole change is about.
    out = m([], [{"name": "GameScope", "parent": "AppScope", "parent_source": "code",
                  "parent_unresolved_reason": "mcp-extraction-absent"}], [])[0]
    check("stale reason from a previous build is cleared once resolved",
          "parent_unresolved_reason" in out, False)

    # Resolved scopes must not carry the key at all — a null reason next to a real parent reads
    # as "resolved, but also unresolved".
    out = m([], [{"name": "GameScope", "parent": "AppScope", "parent_source": "code"}], [])[0]
    check("resolved scope omits the reason key entirely",
          "parent_unresolved_reason" in out, False)


if __name__ == "__main__":
    try:
        csx = _load("csharp_extractor", _EXTRACTOR_PATH)
    except SystemExit:
        print("SKIP — tree-sitter unavailable")
        sys.exit(0)
    gb = _load("gb", _BUILDER_PATH)

    test_extractor()
    test_merge()

    print(f"\n{'FAILED' if _failures else 'OK'} — {len(_failures)} failure(s)")
    sys.exit(1 if _failures else 0)
