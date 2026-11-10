#!/usr/bin/env python3
"""Lint a UI Toolkit HTML/CSS mockup against what USS can port.

Usage: python3 lint-mockup.py [--strict] <Screen>.html [...]

Exit 1 on any ERROR (or any WARN with --strict). Stdlib only.

Scaffolding is exempt: selectors containing `mk-`, `html`, `body` and `*` are for the browser review
sheet and never ported, so they may use anything. Everything else is the spec and must be portable.
Rules mirror skills/systems/ui-mockup/SKILL.md and rules/ui-toolkit-runtime.md Cards 2, 6, 8, 14.
"""
import re
import sys
from pathlib import Path

FORBIDDEN_PROPS = {
    "box-shadow": "no USS equivalent - draw depth as a sprite / 9-slice and list it in Notes",
    "backdrop-filter": "no USS equivalent",
    "clip-path": "no USS equivalent",
    "float": "no USS equivalent - use flexbox",
}
WARN_PROPS = {
    "filter": "USS filter needs Unity 6000.3+ - check ProjectVersion.txt",
    "gap": "USS gap support is unverified in this repo - use margins",
    "row-gap": "USS gap support is unverified in this repo - use margins",
    "column-gap": "USS gap support is unverified in this repo - use margins",
    "transform": "use translate / scale / rotate; transform is review scaffolding only",
}
ALLOWED_TRANSITION_PROPS = {"translate", "scale", "rotate", "opacity", "background-color", "none"}
COLOR_PROPS = {"color", "background-color", "border-color", "background", "border"}
NAMED_COLORS = {"white", "black", "red", "green", "blue", "gray", "grey", "yellow", "orange", "purple"}

RE_DECL = re.compile(r"([a-zA-Z-]+)\s*:\s*([^;]+)")
RE_RAW_COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgb|rgba|hsl|hsla)\(")
RE_BAD_UNIT = re.compile(r"(?<![\w-])\d*\.?\d+(?:rem|em|vw|vh|vmin|vmax)\b")
RE_RAW_PX = re.compile(r"(?<![\w.-])(\d+(?:\.\d+)?)px\b")
RE_RAW_TIME = re.compile(r"(?<![\w.-])\d*\.?\d+m?s\b")
RE_VAR = re.compile(r"var\(\s*(--[\w-]+)")
RE_BAD_SELECTOR = re.compile(r"::?(?:before|after)\b|:(?:nth-[\w-]+|not|has|is|where)\(")
RE_SIBLING = re.compile(r"(?<![\w\[])[+~](?!=)")


class Report:
    def __init__(self, path):
        self.path = path
        self.errors = 0
        self.warns = 0

    def add(self, level, line, code, message):
        print(f"{self.path}:{line}: {level} [{code}] {message}")
        if level == "ERROR":
            self.errors += 1
        else:
            self.warns += 1


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def split_top_level(value):
    parts, depth, cur = [], 0, ""
    for ch in value:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def is_scaffold(selector):
    parts = [p.strip() for p in selector.split(",")]
    return all(re.search(r"\bmk-", p) or p in ("html", "body", "*") for p in parts)


def check_decls(rep, line, selector, decls, in_root, tokens, used_vars, font_sizes, font_weights):
    for prop, value in RE_DECL.findall(decls):
        prop, value = prop.lower(), value.strip()
        if prop.startswith("--"):
            continue
        for name in RE_VAR.findall(value):
            used_vars.append((name, line))
        if prop in FORBIDDEN_PROPS:
            rep.add("ERROR", line, "uss-unsupported", f"`{prop}`: {FORBIDDEN_PROPS[prop]} ({selector})")
        if prop in WARN_PROPS:
            rep.add("WARN", line, "uss-risky", f"`{prop}`: {WARN_PROPS[prop]} ({selector})")
        if prop.startswith("animation"):
            rep.add("ERROR", line, "uss-unsupported", f"`{prop}`: no keyframes in USS - mark it 'C# tween' in Notes (Card 14)")
        if prop.startswith("grid") or (prop == "display" and "grid" in value):
            rep.add("ERROR", line, "uss-unsupported", f"grid layout: USS is flexbox only ({selector})")
        if "gradient(" in value:
            rep.add("ERROR", line, "uss-unsupported", f"CSS gradient: use a sprite / solid colour ({selector})")
        if "calc(" in value:
            rep.add("WARN", line, "uss-risky", f"`calc()` mixing units does not port ({selector})")
        if RE_BAD_UNIT.search(value):
            rep.add("ERROR", line, "bad-unit", f"`{prop}: {value}` - px or % only, no rem/em/vw/vh ({selector})")
        if prop == "border-radius":
            for px in RE_RAW_PX.findall(value):
                if float(px) >= 500:
                    rep.add("ERROR", line, "pill-radius", f"`{value}` renders an ellipse in USS - use a half-height pill token (Card 8)")
        if in_root:
            continue
        if RE_RAW_COLOR.search(value) or (prop in COLOR_PROPS and value.lower() in NAMED_COLORS):
            rep.add("ERROR", line, "raw-color", f"`{prop}: {value}` - a raw colour outside :root is a raw colour in the port (Card 2)")
        if prop.startswith("transition"):
            if RE_RAW_TIME.search(value):
                rep.add("ERROR", line, "raw-duration", f"`{prop}: {value}` - use var(--motion-fast|base|slow) (Card 14)")
            names = split_top_level(value) if prop == "transition-property" else [
                seg.split()[0] for seg in split_top_level(value) if seg.split()
            ] if prop == "transition" else []
            for name in names:
                if name not in ALLOWED_TRANSITION_PROPS:
                    rep.add("ERROR", line, "bad-transition", f"transition on `{name}` - only translate/scale/rotate/opacity/background-color (Card 6)")
        else:
            for px in RE_RAW_PX.findall(value):
                if float(px) not in (0.0, 1.0):
                    rep.add("WARN", line, "raw-px", f"`{prop}: {value}` - spacing/size/type from a token, not a raw px (Card 2)")
                    break
        if prop == "font-size":
            font_sizes.add(value)
        if prop == "font-weight":
            font_weights.add(value)


def lint(path):
    html = Path(path).read_text(encoding="utf-8")
    rep = Report(path)
    tokens, used_vars = set(), []
    font_sizes, font_weights = set(), set()
    css_all = ""
    has_root = False

    for block in re.finditer(r"<style[^>]*>(.*?)</style>", html, re.S | re.I):
        base = block.start(1)
        css = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), block.group(1), flags=re.S)
        css_all += css.lower()
        for m in re.finditer(r"@keyframes\b", css):
            rep.add("ERROR", line_of(html, base + m.start()), "uss-unsupported", "@keyframes: no keyframes in USS - mark it 'C# tween' in Notes (Card 14)")
        for m in re.finditer(r"@import\b", css):
            rep.add("ERROR", line_of(html, base + m.start()), "external", "@import: mockup must be self-contained")
        for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
            selector = m.group(1).strip()
            line = line_of(html, base + m.start(1) + (len(m.group(1)) - len(m.group(1).lstrip())))
            in_root = selector == ":root"
            if in_root:
                has_root = True
                tokens.update(re.findall(r"(--[\w-]+)\s*:", m.group(2)))
            if is_scaffold(selector):
                continue
            if RE_BAD_SELECTOR.search(selector):
                rep.add("ERROR", line, "bad-selector", f"`{selector}` - pseudo-elements and :nth-child/:not/:has/:is don't port")
            if RE_SIBLING.search(selector):
                rep.add("ERROR", line, "bad-selector", f"`{selector}` - sibling combinators don't port; use margins")
            check_decls(rep, line, selector, m.group(2), in_root, tokens, used_vars, font_sizes, font_weights)

    for m in re.finditer(r"<([a-zA-Z0-9]+)([^>]*?)\sstyle=\"([^\"]*)\"", html):
        if "mk-" in m.group(2):
            continue
        line = line_of(html, m.start())
        rep.add("WARN", line, "inline-style", "inline style on a spec element - use a class so it ports to USS (Card 3)")
        check_decls(rep, line, "inline style", m.group(3), False, tokens, used_vars, font_sizes, font_weights)

    for m in re.finditer(r"<link[^>]+stylesheet|<script[^>]+\ssrc=|url\(\s*['\"]?(?!data:)(?:https?:)?//", html, re.I):
        rep.add("ERROR", line_of(html, m.start()), "external", "external CSS/JS/font/image - the mockup must be self-contained")

    if not has_root:
        rep.add("ERROR", 1, "no-tokens", ":root token block missing - tokens are part of the deliverable (Card 2)")
    else:
        for name, line in used_vars:
            if name not in tokens:
                rep.add("ERROR", line, "undefined-token", f"var({name}) is not defined in :root - add the token first (Card 2)")
        for motion in ("--motion-fast", "--motion-base", "--motion-slow"):
            if motion not in tokens:
                rep.add("WARN", 1, "no-motion-token", f"{motion} missing from :root (Card 14)")

    if len(font_sizes) > 3:
        rep.add("WARN", 1, "type-scale", f"{len(font_sizes)} font sizes in use ({', '.join(sorted(font_sizes))}) - max 3 per screen")
    if len(font_weights) > 2:
        rep.add("WARN", 1, "type-scale", f"{len(font_weights)} font weights in use - max 2 per screen")

    if len(re.findall(r"class=\"[^\"]*\bmk-frame\b", html)) < 2:
        rep.add("ERROR", 1, "one-width", "fewer than 2 `mk-frame` elements - draw the reference width AND the narrow width (Card 8/10)")
    for label, needles, level in (
        ("pressed", (":active", ".is-pressed"), "ERROR"),
        ("disabled", (":disabled", ".is-disabled"), "ERROR"),
        ("focus", (":focus", ".is-focus"), "WARN"),
    ):
        if not any(n in css_all for n in needles):
            rep.add(level, 1, "missing-state", f"no {label} state ({' / '.join(needles)}) - every interactive element needs all its states drawn")
    if not re.search(r"id=\"notes\"|class=\"[^\"]*\bmk-notes\b", html):
        rep.add("ERROR", 1, "no-notes", "Notes block missing (id=\"notes\" or class mk-notes) - list sprites, fonts, C# tweens, deviations")
    return rep


def main(argv):
    strict = "--strict" in argv
    files = [a for a in argv if not a.startswith("--")]
    if not files:
        print(__doc__)
        return 2
    errors = warns = 0
    for f in files:
        rep = lint(f)
        errors += rep.errors
        warns += rep.warns
    print(f"{errors} error(s), {warns} warning(s)")
    return 1 if errors or (strict and warns) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
