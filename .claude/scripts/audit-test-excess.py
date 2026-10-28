#!/usr/bin/env python3
"""
audit-test-excess.py — mechanical audit of tests that `rules/testing.md` calls "excess".

Why this exists: the Risk-Based TDD gate is prompt-level only (tester / reviewer / plan tasks).
It decides what a NEW test may cover, and `testing.md` says existing tests are never mass-deleted,
so a project that wrote tests before the gate landed keeps them forever, unseen. This script makes
that debt visible and countable. It decides nothing and deletes nothing.

What it reports, per *Tests.cs file (test target = the class named by the file stem):

  VIOLATION  the target is in a NoTest category that can be told from code alone:
               ScriptableObject config, LifetimeScope, static installer (Install(IContainerBuilder..)),
               Provider, or code compiled only under #if DEVELOPMENT_BUILD / UNITY_EDITOR-only tooling
  REVIEW     the target is a MonoBehaviour shell — NoTest unless it carries real branch/math/state,
             in which case that logic should be extracted to a pure helper (testing.md, "Logic inside
             a Mono shell is extracted, not tested in place"); or the test/source line ratio is extreme
  FLAG       per-index [TestCase] runs (0,1,2,3...), reflection into private members, many tests in a
             file with no multi-assert helper (one scenario split across tests)

Not detectable here (needs a human or the reviewer): visual/feel work, a dependency re-tested
through its wrapper, a test that is a regression guard for a past bug. Check docs/fixes/ and
`git log` before deleting anything this script flags.

Usage:
  audit-test-excess.py [unity-project-root]      # default: unity_project_folder from
                                                 # .claude/project-features.json, else "."
Exit: 0 = no VIOLATION, 2 = at least one VIOLATION, 1 = usage / nothing to audit.
"""
import json
import os
import re
import sys

SKIP_DIRS = {"Library", "Temp", "obj", "Logs", "UserSettings", ".git", "node_modules"}
MULTI_ASSERT = re.compile(r"Assert\.Multiple|AssertEx\.\w+\(")
TEST_ATTR = re.compile(r"^\s*\[(Test|UnityTest)\b", re.M)
TESTCASE_INT = re.compile(r"^\s*\[TestCase\(\s*(-?\d+)\s*\)\]", re.M)
TESTCASE_ANY = re.compile(r"\[TestCase\b")
PRIVATE_REFLECTION = re.compile(r"BindingFlags\.NonPublic")
CLASS_DECL = re.compile(
    r"\b(?P<mods>(?:public|internal|private|protected|static|sealed|abstract|partial)\s+)*"
    r"class\s+(?P<name>[A-Za-z_]\w*)\s*(?:<[^>{]*>)?\s*(?::\s*(?P<bases>[^{]+?))?\s*(?:where\s[^{]+)?\{",
)
# Decisions a pure data holder / thin wrapper does not make. Guard clauses (`if (x == null) { log; return; }`)
# contain none of these, so a class with any of them is not a forwarder (testing.md: "a class with a
# branch, math or state is tested no matter how it is named").
LOGIC = re.compile(r"\b(?:for|foreach|while|switch|else)\b|Mathf\.")
INSTALL_SIG = re.compile(r"static\s+void\s+Install\w*\s*\(\s*(?:this\s+)?IContainerBuilder")
# whole file wrapped in the guard: only leading blank lines / // comments may precede it
DEV_ONLY = re.compile(r"(?:\s*//[^\n]*\n)*\s*#if\s+(?:UNITY_EDITOR|DEVELOPMENT_BUILD)")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def walk_cs(root):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f.endswith(".cs"):
                yield os.path.join(base, f)


def read(path):
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        return fh.read()


def is_test_path(path):
    parts = path.replace("\\", "/").split("/")
    return "Tests" in parts


def classify(name, bases, mods, body, has_unity):
    """Return (kind, label) for a declared class, or None when it is ordinary testable code."""
    base_list = [b.strip().split("<")[0] for b in (bases or "").split(",") if b.strip()]
    is_static = "static" in (mods or "")
    has_logic = bool(LOGIC.search(body))
    if "ScriptableObject" in base_list:
        if has_logic:
            return ("REVIEW", "ScriptableObject with loops/else/math (data holder, or validation logic?)")
        return ("VIOLATION", "ScriptableObject config")
    if "LifetimeScope" in base_list:
        return ("VIOLATION", "LifetimeScope")
    if is_static and INSTALL_SIG.search(body):
        return ("VIOLATION", "static installer")
    if name.endswith("Provider") and not name.startswith("I"):
        # NoTest is by role, not name: a Provider is the Unity API wrapper. A *Provider that never
        # imports UnityEngine may hold real branch/math/state, so a human decides.
        if has_unity and not has_logic:
            return ("VIOLATION", "Provider")
        return ("REVIEW", "Provider with no UnityEngine import, or with loops/else/math (wrapper, or real logic?)")
    if "MonoBehaviour" in base_list or any(b.endswith("Behaviour") for b in base_list):
        return ("REVIEW", "MonoBehaviour shell")
    return None


def build_source_index(root):
    """class name -> (path, line count, classification, dev_only)."""
    index = {}
    for path in walk_cs(root):
        if is_test_path(path):
            continue
        raw = read(path)
        text = strip_comments(raw)
        dev_only = bool(DEV_ONLY.match(raw)) and "#else" not in raw
        lines = raw.count("\n") + 1
        for m in CLASS_DECL.finditer(text):
            name = m.group("name")
            body = text[m.end():]
            cls = classify(name, m.group("bases"), m.group("mods"), body, "using UnityEngine" in raw)
            index.setdefault(name, (path, lines, cls, dev_only))
    return index


def resolve_target(stem, index):
    """FooBarTests -> Foo / FooBar: longest known class that is a prefix of the stem."""
    if stem in index:
        return stem
    best = None
    for name in index:
        if stem.startswith(name) and (best is None or len(name) > len(best)):
            best = name
    return best


def per_index_runs(text):
    """Longest run of consecutive single-int [TestCase(n)] rows (the 'one row per slot' shape)."""
    best = run = 0
    prev = None
    for m in TESTCASE_INT.finditer(text):
        n = int(m.group(1))
        run = run + 1 if prev is not None and n == prev + 1 else 1
        best = max(best, run)
        prev = n
    return best


def find_root(arg):
    if arg:
        return arg
    cfg = ".claude/project-features.json"
    if os.path.isfile(cfg):
        try:
            with open(cfg, encoding="utf-8") as fh:
                return json.load(fh).get("unity_project_folder") or "."
        except (OSError, ValueError):
            pass
    return "."


def main(argv):
    if len(argv) > 2 or (len(argv) == 2 and argv[1] in ("-h", "--help")):
        print(__doc__)
        return 1
    root = find_root(argv[1] if len(argv) == 2 else None)
    if not os.path.isdir(root):
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    index = build_source_index(root)
    test_files = [p for p in walk_cs(root) if is_test_path(p) and p.endswith("Tests.cs")]
    if not test_files:
        print(f"no *Tests.cs files under {root} — nothing to audit")
        return 1

    rows = []
    total_lines = 0
    for path in test_files:
        raw = read(path)
        text = strip_comments(raw)
        lines = raw.count("\n") + 1
        methods = len(TEST_ATTR.findall(text))
        cases = len(TESTCASE_ANY.findall(text))
        total_lines += lines
        stem = os.path.basename(path)[: -len("Tests.cs")]
        target = resolve_target(stem, index)
        findings = []
        severity = None

        if target:
            src_path, src_lines, cls, dev_only = index[target]
            if cls:
                severity, label = cls
                findings.append(f"{label}: {target}")
            if dev_only:
                severity = "VIOLATION"
                findings.append(f"dev-only tooling: {target}")
            if lines >= 300 and src_lines and lines / src_lines >= 8:
                severity = severity or "REVIEW"
                findings.append(f"{lines}/{src_lines} test/source lines ({lines / src_lines:.0f}x)")
        run = per_index_runs(text)
        if run >= 4:
            findings.append(f"per-index [TestCase] run of {run}")
        if PRIVATE_REFLECTION.search(text):
            findings.append("reflection into private members (reads private state, or only injects a [SerializeField]?)")
        if methods >= 8 and not MULTI_ASSERT.search(text):
            findings.append(f"{methods} tests, no multi-assert (split scenarios?)")

        if findings:
            rows.append((severity or "FLAG", lines, methods, cases, os.path.relpath(path, root), findings))

    order = {"VIOLATION": 0, "REVIEW": 1, "FLAG": 2}
    rows.sort(key=lambda r: (order[r[0]], -r[1]))

    print(f"Test excess audit — {root}")
    print(f"{len(test_files)} test files, {total_lines} test lines\n")
    if not rows:
        print("checked: testing.md NoTest categories, per-index [TestCase], private reflection, split scenarios — nothing flagged")
        return 0

    for sev, lines, methods, cases, rel, findings in rows:
        print(f"{sev:<9} {lines:>5} lines {methods:>3} tests {cases:>3} cases  {rel}")
        for f in findings:
            print(f"            - {f}")

    totals = {k: [0, 0] for k in order}
    for sev, lines, *_ in rows:
        totals[sev][0] += 1
        totals[sev][1] += lines
    print("\nSummary")
    for sev in order:
        n, ln = totals[sev]
        if n:
            print(f"  {sev:<9} {n:>3} files  {ln:>6} lines  ({100 * ln / total_lines:.0f}% of test lines)")
    print("\nThis audit deletes nothing. Before pruning a VIOLATION file, check docs/fixes/ and `git log`"
          " for a test that guards a past bug, and get the user's approval.")
    return 2 if totals["VIOLATION"][0] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
