#!/usr/bin/env python3
"""test_registration_method.py — Task 5: registrations[] carry method / chain / line / factory_of.

Fixture: fixtures/members_docs/Registrations.cs (five registrations, lines 49-53).
Both extractors must emit the same (method, type-or-factory_of, chain, line) tuples, and the
legacy single-string `as` contract must not change.

Regex mode: `bash csharp-extractor.sh` proxies to csharp_extractor.py first, so a `python3`
shim on PATH that exits 2 for `*csharp_extractor.py` forces the regex fallback (same trick as
verify-graphify.sh "Registration semantics"). Proof the regex path ran: class records lack the
tree-sitter-only `end_line` key.

Stdlib-only. Run: python3 .claude/graph/test/test_registration_method.py
Exit: 0 = all passed (tree-sitter section may SKIP), 1 = failure.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_EXTRACTORS = os.path.join(_HERE, "..", "extractors")
_FIXTURE = os.path.join(_HERE, "fixtures", "members_docs", "Registrations.cs")

_failures = []

# (method, type or factory_of, chain, line)
EXPECTED = {
    ("RegisterEntryPoint", "A", ("AsImplementedInterfaces",), 49),
    ("RegisterEntryPoint", "B", ("AsSelf",), 50),
    ("Register", "C", ("As<IFoo>", "AsImplementedInterfaces"), 51),
    ("RegisterFactory", "IThing", (), 52),
    ("RegisterComponentInHierarchy", "D", (), 53),
}

# Today's legacy `as` values (pinned so Task 5 does not change them), keyed by type.
PINNED_AS_TS = {"A": "AsImplementedInterfaces", "B": "", "C": "IFoo", "D": ""}
# Regex had no RegisterEntryPoint form before T5; it now emits A/B with the same `as` as tree-sitter.
PINNED_AS_REGEX = PINNED_AS_TS


def check(label, actual, expected):
    if actual == expected:
        print(f"[PASS] {label}")
    else:
        print(f"[FAIL] {label}\n       expected: {expected}\n       actual:   {actual}")
        _failures.append(label)


def section(name):
    print(f"\n== {name} ==")


def _regs(out):
    regs = []
    for inst in out["vcontainer"]["installers"] + out["vcontainer"].get("scopes", []):
        regs.extend(inst.get("registrations", []))
    return regs


def _tuples(regs):
    return {(r.get("method"), r.get("type") or r.get("factory_of"),
             tuple(r.get("chain") or ()), r.get("line")) for r in regs}


def _as_by_type(regs):
    return {r["type"]: r.get("as") for r in regs if r.get("type")}


def _run_checks(mode, out, pinned_as):
    regs = _regs(out)
    got = _tuples(regs)
    check(f"{mode}: registration tuples (method, type, chain, line)",
          sorted(got, key=str), sorted(EXPECTED, key=str))
    check(f"{mode}: legacy `as` values unchanged", _as_by_type(regs), pinned_as)
    check(f"{mode}: every `as` is a string", all(isinstance(r.get("as"), str) for r in regs), True)
    fac = [r for r in regs if r.get("method") == "RegisterFactory"]
    check(f"{mode}: RegisterFactory is unresolved/AMBIGUOUS with empty type",
          [(r.get("type"), r.get("unresolved"), r.get("confidence")) for r in fac],
          [("", True, "AMBIGUOUS")])
    return got


def test_tree_sitter():
    section("tree-sitter")
    spec = importlib.util.spec_from_file_location(
        "csharp_extractor", os.path.join(_EXTRACTORS, "csharp_extractor.py"))
    csx = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(csx)
    try:
        lang, parser_cls = csx._try_import()
    except Exception as exc:  # bindings missing
        print(f"SKIP: tree-sitter unavailable ({exc})")
        return None
    parser = parser_cls()
    parser.language = lang
    with open(_FIXTURE, "rb") as fh:
        out = csx.extract_file(parser, _FIXTURE, fh.read())
    check("tree-sitter: path emits end_line on classes (tree-sitter-only key)",
          "end_line" in out["classes"][0], True)
    return _run_checks("tree-sitter", out, PINNED_AS_TS)


def test_regex():
    section("regex")
    tmp = tempfile.mkdtemp(prefix="regexshim_")
    try:
        shim = os.path.join(tmp, "python3")
        with open(shim, "w") as fh:
            fh.write('#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in '
                     '*csharp_extractor.py) exit 2 ;; esac; done\n'
                     f'exec "{sys.executable}" "$@"\n')
        os.chmod(shim, 0o755)
        env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"])
        proc = subprocess.run(
            ["bash", os.path.join(_EXTRACTORS, "csharp-extractor.sh"),
             "--changed-files", _FIXTURE],
            env=env, capture_output=True, text=True)
        try:
            out = json.loads(proc.stdout)
        except ValueError:
            check("regex: extractor produced JSON", proc.stdout[:200] + proc.stderr[:200], "JSON")
            return None
        check("regex: path ran (class records lack tree-sitter-only end_line)",
              "end_line" in out["classes"][0], False)
        return _run_checks("regex", out, PINNED_AS_REGEX)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ts = test_tree_sitter()
    rx = test_regex()
    if ts is not None and rx is not None:
        section("parity")
        check("tree-sitter and regex yield identical tuple sets", ts == rx, True)
    print()
    if _failures:
        print(f"{len(_failures)} FAILED")
        sys.exit(1)
    print("ALL PASSED")


if __name__ == "__main__":
    main()
