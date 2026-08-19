#!/usr/bin/env python3
"""test_event_defs_and_installer_detection.py — pins three confidently-wrong graph outputs.

All three had the same shape: the graph asserted something false, in a field a reader trusts,
with nothing marking it as unknown.

1. events[] location. `event_pivot` was built from `classes[].events_published/subscribed` only,
   so an event's `file`/`source_file` named whichever class published or subscribed FIRST — never
   the IEvent struct's own file, since events are declared in `<Domain>Events.cs` and published
   from a service. `line` and `namespace` were dropped and `confidence` reported the publishing
   class's value. The extractor had always emitted correct declaration records; the builder never
   read them.

2. events[] completeness. An event declared but never published or subscribed did not appear in
   events[] at all. The R2 EVENT_DANGLING rule catches "publisher, no subscriber"; the strictly
   worse "neither" case was invisible.

3. installers[] detection. `name.endswith("Installer") or (name.endswith("Module") and is_static)`
   missed `AppModules` and `SceneModules` — plural, so neither suffix matches — the two names
   bootstrap-pattern.md MANDATES. The project's own required convention was the one shape the
   extractor could not see. Adding "Modules" to the suffix list would only postpone the same
   failure, so the test is structural: an `Install*` method taking an `IContainerBuilder`.

Stdlib-only (no pytest) per project convention — tooling, not Unity C#.

Run: python3 .claude/graph/test/test_event_defs_and_installer_detection.py
Exit codes: 0 = all passed, 1 = at least one failure,
            0 with "SKIP" printed = tree-sitter unavailable (not a failure).
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

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


def _extract(source, path):
    lang, ParserCls = csx._try_import()
    parser = ParserCls()
    parser.language = lang
    return csx.extract_file(parser, path, source.encode("utf-8"))


# ── 3. structural installer detection ────────────────────────────────────────

_MODULES = """
using VContainer;
namespace Game.Concretes.Infrastructure
{
    // Plural — the exact name bootstrap-pattern.md mandates, and the one the old
    // endswith("Module") test could never match.
    public static class AppModules {
        public static void Install(IContainerBuilder builder, ConfigCatalog configs) {
            EventBusModule.Install(builder);
        }
    }
    public static class SceneModules {
        public static void InstallGame(IContainerBuilder builder) { }
    }
    public static class AudioModule {
        public static void Install(IContainerBuilder builder, AudioConfiguration c) {
            builder.Register<AudioService>(Lifetime.Singleton);
        }
    }
    // Takes an IContainerBuilder but is NOT an installer. Guards the structural test against
    // widening into "anything that mentions IContainerBuilder".
    public static class ContainerBuilderExtensions {
        public static void Register2(this IContainerBuilder builder) { }
    }
}
"""

_SCOPE_NOT_INSTALLER = """
using VContainer; using VContainer.Unity;
public sealed class GameScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder) { }
}
"""


def test_installer_detection():
    out = _extract(_MODULES, "Concretes/Infrastructure/AppModules.cs")
    names = sorted(i["name"] for i in out["vcontainer"]["installers"])
    check("plural AppModules/SceneModules are detected alongside AudioModule",
          names, ["AppModules", "AudioModule", "SceneModules"])
    check("an IContainerBuilder extension helper is NOT an installer",
          "ContainerBuilderExtensions" in names, False)

    # Configure(IContainerBuilder) must not make a scope an installer as well. The caller routes
    # scopes first, so this pins the routing, not just the predicate.
    out = _extract(_SCOPE_NOT_INSTALLER, "Concretes/Infrastructure/GameScope.cs")
    check("a LifetimeScope stays in scopes[] and out of installers[]",
          (len(out["vcontainer"]["scopes"]), len(out["vcontainer"]["installers"])), (1, 0))

    # An aggregator registers nothing itself. Empty registrations is the truth; absence was not.
    app = [i for i in _extract(_MODULES, "x.cs")["vcontainer"]["installers"]
           if i["name"] == "AppModules"][0]
    check("aggregator is present with an empty registrations[]", app["registrations"], [])


# ── 1 + 2. event declaration records ─────────────────────────────────────────

_EVENT_DECLS = """
namespace Game.Concretes.Audio
{
    public struct CoinsChangedEvent : IEvent { public readonly int NewAmount; }
    public struct NeverUsedEvent : IEvent { }
}
"""

_PUBLISHER = """
namespace Game.Concretes.Score
{
    public sealed class ScoreService {
        private IEventBus _bus;
        public void Add(int n) { _bus.Publish(new CoinsChangedEvent()); }
    }
}
"""

_DECL_FILE = "Concretes/Audio/AudioEvents.cs"
_PUB_FILE = "Concretes/Score/ScoreService.cs"


def test_event_defs():
    decls = _extract(_EVENT_DECLS, _DECL_FILE)
    pub = _extract(_PUBLISHER, _PUB_FILE)
    events = {e["name"]: e
              for e in gb.event_pivot(decls["classes"] + pub["classes"],
                                      decls["events"] + pub["events"])}

    coins = events["CoinsChangedEvent"]
    # The regression: this used to be _PUB_FILE, because the publisher was pivoted first.
    check("event file names the DECLARATION site, not the publisher's file",
          coins["file"], _DECL_FILE)
    check("declaration line survives", coins["line"], 4)
    check("declaration namespace survives", coins["namespace"], "Game.Concretes.Audio")
    check("confidence is the event's own EXTRACTED, not the publisher class's",
          coins["confidence"], "EXTRACTED")
    check("publishers still pivot across files", coins["publishers"], ["ScoreService"])
    check("a resolved event carries no declaration_unresolved flag",
          "declaration_unresolved" in coins, False)

    # Previously absent from events[] entirely — invisible to violations and to any query.
    never = events["NeverUsedEvent"]
    check("declared-but-unreferenced event appears at all",
          (never["file"], never["publishers"], never["subscribers"]), (_DECL_FILE, [], []))

    # No declaration record: the old code borrowed the referencing class's file, which is exactly
    # the confidently-wrong answer. It must stay empty and say so.
    only_ref = gb.event_pivot(pub["classes"], [])[0]
    check("no declaration record -> empty file, flagged unresolved",
          (only_ref["file"], only_ref["source_file"], only_ref.get("declaration_unresolved")),
          ("", "", True))
    check("an unresolved event still lists its publisher", only_ref["publishers"], ["ScoreService"])


# ── 4. the MCP cache log names the real reason ───────────────────────────────


def test_mcp_cache_log():
    d = tempfile.mkdtemp()
    cache = os.path.join(d, "mcp-extract.json")
    out = os.path.join(d, "graph.json")
    with open(cache, "w") as fh:
        json.dump({"scenes": [], "prefabs": [], "scope_parents": [], "extracted_at": "now"}, fh)
    with open(out, "w") as fh:
        json.dump({"codebase": {"prefabs": []}}, fh)

    lines = []
    real_log, gb.log = gb.log, lambda m, q=False: lines.append(m)
    try:
        # A cache written seconds ago, on --full: the old message said "stale (0m old)" and told
        # the reader to run the command they had just run.
        gb.load_mcp_cache(cache, out, "full", False, False)
        msg = lines[-1]
        check("--full says it BYPASSED the cache, not that the cache is stale",
              ("bypassed by --full" in msg, "stale" in msg.split("not stale")[0]), (True, False))
        check("--full does not tell the reader to re-run /build-knowledge-graph",
              "/build-knowledge-graph" in msg, False)

        os.utime(cache, (time.time() - 7200, ) * 2)
        gb.load_mcp_cache(cache, out, "incremental", False, False)
        msg = lines[-1]
        check("a genuinely old cache on --incremental still reports stale, with the limit",
              ("stale (120m old, limit 60m)" in msg), True)
    finally:
        gb.log = real_log


if __name__ == "__main__":
    try:
        csx = _load("csharp_extractor", _EXTRACTOR_PATH)
    except SystemExit:
        print("SKIP — tree-sitter unavailable")
        sys.exit(0)
    gb = _load("gb", _BUILDER_PATH)

    test_installer_detection()
    test_event_defs()
    test_mcp_cache_log()

    print(f"\n{'FAILED' if _failures else 'OK'} — {len(_failures)} failure(s)")
    sys.exit(1 if _failures else 0)
