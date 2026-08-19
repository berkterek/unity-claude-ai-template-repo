#!/usr/bin/env python3
"""test_as_implemented_resolution.py — pins the .AsImplementedInterfaces() expansion.

`.AsImplementedInterfaces()` names no type, so the extractor stores the literal string
"AsImplementedInterfaces" in `as`. `/knowledge-graph registrations IEventBus` therefore returned
nothing for every service registered the way `rules/bootstrap-pattern.md` MANDATES — Card 1's
RIGHT block uses it, and a separate rule states it "covers IInitializable, IDisposable, ITickable
automatically". Same failure as the old name-suffix installer test, one layer down: the convention
the project is required to follow was the one the graph could not answer questions about.

resolve_as_implemented expands the placeholder from the concrete type's own AND inherited
`implements`, and marks every expansion full/partial. These tests pin four things that are easy to
regress:

  - `as` keeps the placeholder. Overwriting it would destroy a real distinction — an explicit
    `.As<IEventBus>()` is intent, a wildcard covering IEventBus is a side effect — and break the
    single-string contract other consumers rely on.
  - inherited interfaces are included (the per-file extractor cannot see them; only this global
    builder pass can).
  - each partial case reports WHICH partiality applies, rather than emitting a short list that
    reads as exhaustive.
  - a partial list is still emitted. Empty-on-doubt would be a regression to the behaviour this
    replaces.

Stdlib-only (no pytest) per project convention — tooling, not Unity C#.

Run: python3 .claude/graph/test/test_as_implemented_resolution.py
Exit codes: 0 = all passed, 1 = at least one failure.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BUILDER_PATH = os.path.join(_HERE, "..", "graph-builder.py")

_spec = importlib.util.spec_from_file_location("gb", _BUILDER_PATH)
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)

_failures = []


def check(label, actual, expected):
    if actual == expected:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}\n       expected: {expected}\n       actual:   {actual}")
        _failures.append(label)


def _cls(name, implements=(), bases=(), file="Concretes/X.cs"):
    return {"name": name, "file": file, "source_file": file,
            "implements": list(implements), "base_types": list(bases) + list(implements)}


def _reg(type_name, as_value="AsImplementedInterfaces"):
    return {"type": type_name, "as": as_value, "lifetime": "Singleton"}


def _installer(regs):
    return {"name": "AudioModule", "file": "Concretes/Audio/AudioModule.cs", "registrations": regs}


def test_full_resolution():
    reg = _reg("EventBus")
    classes = [_cls("EventBus", ["IEventBus", "IInitializable", "IDisposable"])]
    gb.resolve_as_implemented([_installer([reg])], [], classes)
    check("wildcard expands to every declared interface",
          reg["as_resolved"], ["IEventBus", "IInitializable", "IDisposable"])
    check("resolution marked full", reg["as_resolution"], "full")
    check("no reason field on a full resolution", "as_resolution_reason" in reg, False)
    # The whole point of not rewriting `as`: provenance. An explicit .As<IEventBus>() and a
    # wildcard that happens to cover IEventBus are different facts about the author's intent.
    check("`as` keeps the placeholder, it is not rewritten to an interface name",
          reg["as"], "AsImplementedInterfaces")


def test_inherited_interfaces():
    # ServiceBase contributes IDisposable. The per-file extractor sees only AudioService's own
    # base list, so without the builder's base-chain walk IDisposable would be missing — and
    # VContainer really does register it.
    reg = _reg("AudioService")
    classes = [
        _cls("AudioService", ["IAudioService"], bases=["ServiceBase"]),
        _cls("ServiceBase", ["IDisposable"]),
    ]
    gb.resolve_as_implemented([_installer([reg])], [], classes)
    check("interfaces inherited through a base class are included",
          reg["as_resolved"], ["IAudioService", "IDisposable"])
    check("a fully walked base chain is still full", reg["as_resolution"], "full")


def test_partial_type_unresolved():
    reg = _reg("")            # RegisterComponent(_field) — opaque argument, no concrete type
    gb.resolve_as_implemented([_installer([reg])], [], [_cls("Whatever", ["IWhatever"])])
    check("no concrete type -> partial/type-unresolved",
          (reg["as_resolved"], reg["as_resolution"], reg["as_resolution_reason"]),
          ([], "partial", "type-unresolved"))


def test_partial_class_not_in_graph():
    reg = _reg("ThirdPartyThing")
    gb.resolve_as_implemented([_installer([reg])], [], [_cls("Unrelated", ["IUnrelated"])])
    check("concrete type absent from classes[] -> partial/class-not-in-graph",
          (reg["as_resolved"], reg["as_resolution"], reg["as_resolution_reason"]),
          ([], "partial", "class-not-in-graph"))


def test_partial_base_not_in_graph():
    # The base chain leaves the graph. What was found is real; what is missing is unknown — and
    # emitting the short list WITHOUT the marker is exactly the "confidently wrong" failure.
    reg = _reg("AudioService")
    classes = [_cls("AudioService", ["IAudioService"], bases=["UnseenBase"])]
    gb.resolve_as_implemented([_installer([reg])], [], classes)
    check("base chain leaving the graph -> partial/base-not-in-graph",
          (reg["as_resolution"], reg["as_resolution_reason"]),
          ("partial", "base-not-in-graph"))
    check("a partial list is still emitted, not emptied on doubt",
          reg["as_resolved"], ["IAudioService"])


def test_scope_registrations_and_untouched_explicit_as():
    # Scopes carry registrations too (GameScope's RegisterComponent calls), so the pass must walk
    # them as well — the schema did not even declare them until 1.7.0.
    scope_reg = _reg("GridRenderController")
    explicit = _reg("AudioService", as_value="IAudioService")
    classes = [_cls("GridRenderController", ["IGridRenderer"]), _cls("AudioService", ["IAudioService"])]
    n = gb.resolve_as_implemented([_installer([explicit])], [{"name": "GameScope",
                                                             "registrations": [scope_reg]}], classes)
    check("registrations on a scope are expanded too", scope_reg["as_resolved"], ["IGridRenderer"])
    check("an explicit .As<T>() registration is left completely alone",
          ("as_resolved" in explicit, "as_resolution" in explicit, explicit["as"]),
          (False, False, "IAudioService"))
    check("only wildcard registrations are counted as expanded", n, 1)


def test_cycle_guard():
    # A malformed/circular base chain must terminate rather than hang. Same depth-cap-as-cycle
    # -guard contract as resolve_call_targets._field_type.
    reg = _reg("A")
    classes = [_cls("A", ["IA"], bases=["B"]), _cls("B", ["IB"], bases=["A"])]
    gb.resolve_as_implemented([_installer([reg])], [], classes)
    check("a circular base chain terminates and still yields both interfaces",
          sorted(reg["as_resolved"]), ["IA", "IB"])


if __name__ == "__main__":
    test_full_resolution()
    test_inherited_interfaces()
    test_partial_type_unresolved()
    test_partial_class_not_in_graph()
    test_partial_base_not_in_graph()
    test_scope_registrations_and_untouched_explicit_as()
    test_cycle_guard()

    print(f"\n{'FAILED' if _failures else 'OK'} — {len(_failures)} failure(s)")
    sys.exit(1 if _failures else 0)
