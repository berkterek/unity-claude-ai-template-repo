#!/usr/bin/env python3
"""test_resolve_implementers_same_name.py — two interfaces sharing a simple name both survive.

resolve_implementers used to key interfaces by simple name and return the dict's values, so a
project with `Framework.SaveLoadSystems.ISaveLoadService` and `Game.Abstracts.ISaveLoadService`
silently lost one record (last wins) — nothing in the build reported it except a standing
GRAPH_DISK_MISMATCH that a --full rebuild could not clear. Classes were never deduplicated, so
only interfaces were affected.

A class lists the interfaces it implements by simple name, so the builder cannot tell which of two
same-named interfaces it means; each candidate gets the implementer (same by-name resolution the
call-edge pass uses) instead of one record being dropped.

Stdlib-only (no pytest) per project convention.
Run: python3 .claude/graph/test/test_resolve_implementers_same_name.py
Exit codes: 0 = all passed, 1 = at least one failure.
"""
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("gb", os.path.join(_HERE, "..", "graph-builder.py"))
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)

_failures = []


def check(label, actual, expected):
    if actual == expected:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}\n       expected: {expected}\n       actual:   {actual}")
        _failures.append(label)


def _iface(name, file):
    return {"name": name, "file": file, "source_file": file}


def _cls(name, implements):
    return {"name": name, "implements": list(implements)}


def test_same_name_interfaces_both_kept():
    ifaces = [_iface("ISaveLoadService", "_Framework/SaveLoad/ISaveLoadService.cs"),
              _iface("ISaveLoadService", "Games/Concretes/SaveLoad/ISaveLoadService.cs"),
              _iface("IOther", "Games/IOther.cs")]
    out = gb.resolve_implementers(ifaces, [])
    check("every interface record survives", [i["file"] for i in out], [i["file"] for i in ifaces])


def test_implementer_attached_to_each_candidate():
    ifaces = [_iface("ISaveLoadService", "a.cs"), _iface("ISaveLoadService", "b.cs")]
    out = gb.resolve_implementers(ifaces, [_cls("SaveLoadService", ["ISaveLoadService"])])
    check("each same-named candidate lists the implementer",
          [i.get("implementers") for i in out], [["SaveLoadService"], ["SaveLoadService"]])


def test_unique_name_unchanged():
    ifaces = [_iface("IEventBus", "e.cs")]
    out = gb.resolve_implementers(ifaces, [_cls("EventBus", ["IEventBus", "IDisposable"])])
    check("a unique interface still gets its implementer once",
          out[0].get("implementers"), ["EventBus"])


if __name__ == "__main__":
    test_same_name_interfaces_both_kept()
    test_implementer_attached_to_each_candidate()
    test_unique_name_unchanged()
    print(f"\n{'FAILED' if _failures else 'OK'} — {len(_failures)} failure(s)")
    sys.exit(1 if _failures else 0)
