#!/usr/bin/env python3
"""Regenerate the debug-command table in docs/PLAYTEST.md from the *DebugCommands.cs sources.

Static parse — works without Unity open. Rewrites only the block between the
`<!-- debug-commands:begin -->` and `<!-- debug-commands:end -->` markers.

Usage:
  python3 -I .claude/scripts/generate-playtest-commands.py [--root <unity_project_folder>]
                                                           [--doc docs/PLAYTEST.md] [--check]
Exit: 0 written / current · 1 --check and the block is stale · 2 doc or markers missing.

Command id = class name minus the `DebugCommands` suffix, `.`, member (same rule as the runtime
registry). Member rules mirror the registry — see parse_container. Scope = App / Scene by which module list installs the
module that registers the class; unresolved → `unknown` plus one warning, never a failure.
"""
import argparse
import json
import os
import re
import sys

BEGIN = "<!-- debug-commands:begin -->"
END = "<!-- debug-commands:end -->"
HEADER = "| Command | Scope | Parameters | Description |"
SEPARATOR = "|---|---|---|---|"
SUFFIX = "DebugCommands"
# Lifecycle interface → the method it makes the container implement. The registry hides every
# interface implementation (reflection); statically we can only see these well-known ones, so any
# other interface method should carry [Browsable(false)], which hides it on every side.
LIFECYCLE = {
    "IInitializable": "Initialize", "IPostInitializable": "PostInitialize",
    "IStartable": "Start", "IPostStartable": "PostStart", "IDisposable": "Dispose",
}
SKIP_DIRS = {"Library", "Temp", "Logs", "obj", "Build", "Builds", "UserSettings", ".git", "node_modules"}

CLASS_RE = re.compile(r"\bclass\s+(\w+)" + SUFFIX + r"\b([^{]*)")
# Leading `///` and attribute lines, then attributes on the member's own line, then the declaration.
LEAD = r"((?:^[ \t]*///[^\n]*\n|^[ \t]*\[[^\n]*\][ \t]*\n)*)^[ \t]*((?:\[[^\]\n]*\][ \t]*)*)"
MODIFIERS = r"public\s+(?:(?:override|new|virtual|sealed)\s+)*"
METHOD_RE = re.compile(LEAD + MODIFIERS + r"void\s+(\w+)\s*\(\s*\)", re.M)
PROPERTY_RE = re.compile(
    LEAD + MODIFIERS + r"(?!static\b|class\b|void\b|const\b|readonly\b|event\b|delegate\b)"
    r"([\w.<>\[\],? ]+?)\s+(\w+)\s*\{", re.M)
HIDDEN_RE = re.compile(r"\bBrowsable\s*\(\s*false\s*\)")
NON_PUBLIC_SET_RE = re.compile(r"\b(?:private|protected|internal)\s+set\b")
SUMMARY_LINE_RE = re.compile(r"///\s*([^<\s].*)")
REGISTER_RE = r"\bRegister(?:EntryPoint)?\s*<\s*{name}\s*>"
STATIC_CLASS_RE = re.compile(r"\bstatic\s+class\s+(\w+)")


def default_root():
    try:
        with open(os.path.join(".claude", "project-features.json"), encoding="utf-8") as f:
            return json.load(f).get("unity_project_folder") or "."
    except (OSError, ValueError):
        return "."


def cs_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith(".cs"):
                yield os.path.join(dirpath, name)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_line_comments(text):
    # Keeps `///` doc lines (the description source) and drops ordinary `//` comments.
    return re.sub(r"(?<!/)//(?!/)[^\n]*", "", text)


def block_after(text, open_index):
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index:i + 1]
    return text[open_index:]


def parse_container(text, base_list):
    """Same member rules as the runtime registry: a parameter has a public getter and a public
    setter; a command is a public instance parameterless void method declared on the class; members
    marked [Browsable(false)] and lifecycle-interface implementations are neither."""
    lifecycle = {method for contract, method in LIFECYCLE.items()
                 if re.search(r"\b" + contract + r"\b", base_list)}

    parameters = []
    for match in PROPERTY_RE.finditer(text):
        if HIDDEN_RE.search(match.group(1) + match.group(2)):
            continue
        body = NON_PUBLIC_SET_RE.sub("", block_after(text, match.end() - 1))
        if re.search(r"\bset\b", body) and re.search(r"\bget\b", body):
            parameters.append(f"{match.group(4)}:{match.group(3).strip()}")

    commands = []
    for match in METHOD_RE.finditer(text):
        name = match.group(3)
        if name in lifecycle or HIDDEN_RE.search(match.group(1) + match.group(2)):
            continue
        description = ""
        for line in match.group(1).splitlines():
            doc = SUMMARY_LINE_RE.search(line)
            if doc and doc.group(1).strip():
                description = doc.group(1).strip()
                break
        commands.append((name, description))
    return parameters, commands


def resolve_scope(class_name, sources):
    register = re.compile(REGISTER_RE.format(name=re.escape(class_name)))
    for path, text in sources.items():
        if not register.search(text):
            continue
        base = os.path.basename(path)
        if base == "AppModules.cs":
            return "App"
        if base == "SceneModules.cs":
            return "Scene"
        owner = STATIC_CLASS_RE.search(text)
        if not owner:
            continue
        install = re.compile(r"\b" + re.escape(owner.group(1)) + r"\.Install\b")
        for list_path, list_text in sources.items():
            list_base = os.path.basename(list_path)
            if list_base in ("AppModules.cs", "SceneModules.cs") and install.search(list_text):
                return "App" if list_base == "AppModules.cs" else "Scene"
    return None


def cell(value):
    return value.replace("|", "\\|") if value else "—"


def build_block(root):
    sources = {path: strip_line_comments(read(path)) for path in cs_files(root)}
    rows = []
    for path, text in sources.items():
        if not os.path.basename(path).endswith(SUFFIX + ".cs"):
            continue
        for class_match in CLASS_RE.finditer(text):
            prefix = class_match.group(1)
            open_index = text.find("{", class_match.end())
            if open_index < 0:
                continue
            body = block_after(text, open_index)
            parameters, commands = parse_container(body, class_match.group(2))
            scope = resolve_scope(prefix + SUFFIX, sources)
            if scope is None:
                print(f"warning: unknown scope for {prefix}{SUFFIX} ({path}) — no Register<{prefix}{SUFFIX}> "
                      f"reached from AppModules or SceneModules", file=sys.stderr)
                scope = "unknown"
            for name, description in commands:
                rows.append(f"| {prefix}.{name} | {scope} | {cell(', '.join(parameters))} | {cell(description)} |")

    if not rows:
        return "\n_No `*DebugCommands` classes found._\n"
    return "\n" + "\n".join([HEADER, SEPARATOR] + sorted(rows)) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=None, help="Unity project folder (default: project-features.json)")
    parser.add_argument("--doc", default=os.path.join("docs", "PLAYTEST.md"))
    parser.add_argument("--check", action="store_true", help="exit 1 if the block is stale; write nothing")
    args = parser.parse_args()

    try:
        doc = read(args.doc)
    except OSError:
        print(f"error: {args.doc} not found — /setup-project writes the skeleton with "
              f"{BEGIN} / {END} markers", file=sys.stderr)
        return 2

    start, end = doc.find(BEGIN), doc.find(END)
    if start < 0 or end < 0 or end < start:
        print(f"error: {args.doc} has no {BEGIN} ... {END} block", file=sys.stderr)
        return 2

    block = build_block(args.root or default_root())
    updated = doc[:start + len(BEGIN)] + block + doc[end:]

    if args.check:
        if updated != doc:
            print(f"{args.doc} debug-command table is stale", file=sys.stderr)
            return 1
        return 0

    if updated != doc:
        with open(args.doc, "w", encoding="utf-8") as f:
            f.write(updated)
    return 0


if __name__ == "__main__":
    sys.exit(main())
