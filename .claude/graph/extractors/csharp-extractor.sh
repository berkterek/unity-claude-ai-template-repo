#!/usr/bin/env bash
# csharp-extractor.sh — Extract classes/interfaces/events/VContainer from C# files.
# tree-sitter primary; regex fallback if tree-sitter unavailable.
# Usage:
#   csharp-extractor.sh                          # scan all C# under Assets/ and Packages/
#   csharp-extractor.sh --changed-files a.cs,b.cs
#   csharp-extractor.sh --include-tests          # also scan Tests folders
set -euo pipefail

CHANGED_FILES=""
INCLUDE_TESTS=0
MODE="regex"
CS_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files)  CHANGED_FILES="$2"; shift 2 ;;
    --include-tests)  INCLUDE_TESTS=1; shift ;;
    --root)           CS_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Detect tree-sitter
if command -v tree-sitter >/dev/null 2>&1 && tree-sitter --version 2>/dev/null | grep -q '^tree-sitter'; then
  MODE="tree-sitter"
else
  echo "csharp-extractor: tree-sitter not found — using regex mode (confidence: INFERRED)" >&2
fi

CONFIDENCE="EXTRACTED"
[[ "$MODE" == "regex" ]] && CONFIDENCE="INFERRED"

# Build file list
declare -a FILES=()
if [[ -n "$CHANGED_FILES" ]]; then
  IFS=',' read -ra RAW <<< "$CHANGED_FILES"
  for f in "${RAW[@]}"; do
    [[ "$f" == *.cs ]] && FILES+=("$f")
  done
else
  # Resolve root prefix: --root arg > unity_project_folder (project-features.json) > Assets/.
  # Never hardcode a project's subfolder name — read it from config (see CLAUDE.md).
  if [[ -n "$CS_ROOT" ]]; then
    _prefix="$CS_ROOT"
  else
    _repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    _uf="$(python3 - "$_repo_root" <<'PY' 2>/dev/null || echo "."
import json, os, sys
p = os.path.join(sys.argv[1], ".claude", "project-features.json")
try:
    v = (json.load(open(p)).get("unity_project_folder", ".") or ".")
except Exception:
    v = "."
print(str(v).rstrip("/") or ".")
PY
)"
    if [[ "$_uf" == "." ]]; then _prefix="Assets"; else _prefix="${_uf}/Assets"; fi
  fi
  FIND_OPTS=( "${_prefix}/_Framework" "${_prefix}/_GameFolders/Scripts" )
  [[ -d "${_prefix}/../Packages" ]] && FIND_OPTS+=( "${_prefix}/../Packages" )
  while IFS= read -r -d '' f; do
    if [[ $INCLUDE_TESTS -eq 0 ]]; then
      [[ "$f" == *Tests* ]] && continue
    fi
    FILES+=("$f")
  done < <(find "${FIND_OPTS[@]}" -name '*.cs' -print0 2>/dev/null)
fi

# ── Python/tree-sitter preflight ────────────────────────────────────────────
# If csharp_extractor.py succeeds (tree-sitter available), use its EXTRACTED output and exit.
# On exit 2 (tree-sitter unavailable) or any other non-zero, fall through to regex pipeline.
_EXTRACTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1 && [[ -f "$_EXTRACTOR_DIR/csharp_extractor.py" ]]; then
  TS_OUT=""
  TS_EXIT=0
  TS_OUT=$(python3 "$_EXTRACTOR_DIR/csharp_extractor.py" \
    --changed-files "$CHANGED_FILES" 2>/dev/null) || TS_EXIT=$?
  if [[ $TS_EXIT -eq 0 && -n "$TS_OUT" ]]; then
    echo "$TS_OUT"; exit 0
  fi
  # TS_EXIT=2 means tree-sitter unavailable → fall through to regex (INFERRED)
fi

# ── Regex extraction helpers ────────────────────────────────────────────────

extract_classes() {
  local f="$1"
  grep -nE '^[[:space:]]*(public|internal)?[[:space:]]*(sealed|abstract)?[[:space:]]*class[[:space:]]+([A-Z][A-Za-z0-9_]*)' "$f" 2>/dev/null || true
}

extract_interfaces() {
  local f="$1"
  grep -nE '^[[:space:]]*(public|internal)?[[:space:]]*interface[[:space:]]+(I[A-Z][A-Za-z0-9_]*)' "$f" 2>/dev/null || true
}

extract_namespace() {
  local f="$1"
  grep -m1 -E '^[[:space:]]*namespace[[:space:]]+([A-Za-z0-9_.]+)' "$f" 2>/dev/null | sed -E 's/.*namespace[[:space:]]+([A-Za-z0-9_.]+).*/\1/' || echo ""
}

# extract_class_info: returns JSON array of {name, line, base_types, implements, methods}
# Uses python3 to handle multi-line class declarations reliably.
# Also emits file-level partial_calls as a second JSON line: {"partial_calls": [...]}
extract_class_info() {
  local f="$1"
  python3 - "$f" <<'PYEOF'
import re, sys, json

try:
    text = open(sys.argv[1]).read()
except Exception:
    print("[]")
    print(json.dumps({"partial_calls": []}))
    sys.exit(0)

text = text.replace('\r\n', '\n').replace('\r', '\n')
lines = text.split('\n')

# ── Regexes ──────────────────────────────────────────────────────────────────

class_re = re.compile(
    r'^[ \t]*(?:(?:public|internal|private|protected)\s+)?'
    r'(?:(?:sealed|abstract|static|partial)\s+)*'
    r'class\s+([A-Z][A-Za-z0-9_]*)'
)

METHOD_RE = re.compile(
    r'^\s*(?P<acc>public|internal|private|protected)?\s*'
    r'(?P<mods>(?:static\s+|virtual\s+|override\s+|abstract\s+|sealed\s+|async\s+)*)'
    r'(?P<ret>[A-Za-z_][\w<>,\s\[\]\?\.]*?)\s+'
    r'(?P<name>[A-Z]\w*)\s*\([^)]*\)\s*(?:\{|=>|;)',
    re.MULTILINE
)

CALL_RE = re.compile(
    r'(?:(?P<recv>[A-Za-z_][\w]*)\s*\.\s*)?(?P<callee>[A-Z]\w*)\s*\(',
    re.MULTILINE
)

CSHARP_KEYWORDS = {
    'if', 'while', 'for', 'foreach', 'switch', 'return', 'using', 'typeof', 'nameof',
    'lock', 'fixed', 'await', 'new', 'throw', 'catch', 'finally', 'else', 'case', 'default'
}

BCL_NOISE = {
    'Debug', 'Math', 'Mathf', 'Vector2', 'Vector3', 'Vector4', 'Quaternion', 'Color',
    'string', 'int', 'bool', 'float', 'double', 'List', 'Dictionary', 'Array', 'Enumerable',
    'Assert', 'Console', 'Convert', 'Encoding', 'StringBuilder', 'Task', 'UniTask'
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def line_of(pos):
    """Return 1-based line number for a character offset in `text`."""
    return text[:pos].count('\n') + 1

# ── Class extraction ──────────────────────────────────────────────────────────

# Collect (line_num, class_name, start_char_offset) for each class declaration
class_starts = []  # list of (line_1based, class_name, char_offset_of_open_brace)

results = []

i = 0
while i < len(lines):
    m = class_re.match(lines[i])
    if m:
        class_name = m.group(1)
        line_num = i + 1
        chunk = ' '.join(lines[i:i+6])
        base_match = re.search(
            r'class\s+' + re.escape(class_name) + r'(?:\s*<[^>]*>)?\s*:\s*([^{]+)',
            chunk
        )
        base_str = ""
        if base_match:
            base_str = base_match.group(1)
            where_idx = base_str.find(' where ')
            if where_idx >= 0:
                base_str = base_str[:where_idx]
        base_types = []
        if base_str.strip():
            for b in base_str.split(','):
                b = b.strip()
                b = re.sub(r'<[^<>]*>', '', b).strip()
                if b:
                    simple = b.split('.')[-1]
                    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', simple):
                        base_types.append(simple)
        implements = [b for b in base_types if re.match(r'^I[A-Z]', b)]

        # Find the character offset of line_num in text (for scoping)
        char_offset = sum(len(l) + 1 for l in lines[:i])

        results.append({
            "name": class_name,
            "line": line_num,
            "base_types": base_types,
            "implements": implements,
            "methods": [],          # filled in below
            "_char_offset": char_offset,
        })
    i += 1

# ── Method extraction & scoping ───────────────────────────────────────────────

# For each method match, assign it to the class whose declaration line is
# closest (and earlier) to the method line.

all_methods = []  # (line, class_idx, method_dict)

for m in METHOD_RE.finditer(text):
    name = m.group('name')
    if name in CSHARP_KEYWORDS:
        continue
    mods = m.group('mods') or ''
    acc  = m.group('acc') or 'private'
    ret  = (m.group('ret') or '').strip()
    ln   = line_of(m.start())
    sig  = m.group(0).strip()
    # Trim trailing brace/arrow/semicolon from signature
    sig  = re.sub(r'\s*[\{=>;]+\s*$', '', sig).strip()

    # Find owning class: last class whose declaration is on or before this line
    owner_idx = None
    for idx, cls in enumerate(results):
        if cls['line'] <= ln:
            owner_idx = idx
        else:
            break

    if owner_idx is None:
        continue

    method_entry = {
        "name": name,
        "signature": sig,
        "line": ln,
        "accessibility": acc,
        "is_async": "async" in mods,
        "is_static": "static" in mods,
        "return_type": ret,
    }
    all_methods.append((ln, owner_idx, method_entry))

# Attach methods to classes
for ln, owner_idx, method_entry in all_methods:
    results[owner_idx]['methods'].append(method_entry)

# Sort methods by line ascending (idempotency)
for cls in results:
    cls['methods'].sort(key=lambda x: x['line'])

# ── Call-site extraction ───────────────────────────────────────────────────────

# Build a flat sorted list of (method_line, class_name, method_name) for quick lookup
method_map = []  # (method_line, class_name, method_name)
for cls in results:
    for mth in cls['methods']:
        method_map.append((mth['line'], cls['name'], mth['name']))
method_map.sort(key=lambda x: x[0])

def enclosing_method(call_line):
    """Return (class_name, method_name) for the innermost method containing call_line."""
    best = None
    for mline, cname, mname in method_map:
        if mline <= call_line:
            best = (cname, mname)
        else:
            break
    return best

rel_path = sys.argv[1]
partial_calls = []

for c in CALL_RE.finditer(text):
    callee = c.group('callee')
    if callee in CSHARP_KEYWORDS or callee in BCL_NOISE:
        continue
    # Skip generic false positives: preceded by '<'
    start = c.start()
    preceding = text[max(0, start-1):start]
    if preceding == '<':
        continue

    call_line = line_of(start)
    enc = enclosing_method(call_line)
    if not enc:
        continue

    recv = c.group('recv')
    callee_str = f"{recv}.{callee}" if recv else callee

    partial_calls.append({
        "caller": f"{enc[0]}.{enc[1]}",
        "callee": callee_str,
        "file": rel_path,
        "line": call_line,
        "confidence": "INFERRED",
    })

# Sort for idempotency: by (caller, line)
partial_calls.sort(key=lambda x: (x['caller'], x['line']))

# Deduplicate exact duplicates (same caller+callee+line)
seen_calls = set()
deduped_calls = []
for pc in partial_calls:
    key = (pc['caller'], pc['callee'], pc['line'])
    if key not in seen_calls:
        seen_calls.add(key)
        deduped_calls.append(pc)

# Strip internal _char_offset before output
for cls in results:
    cls.pop('_char_offset', None)

# Emit two JSON lines: classes array, then partial_calls wrapper
print(json.dumps(results))
print(json.dumps({"partial_calls": deduped_calls}))
PYEOF
}

has_static_instance() {
  local f="$1"
  grep -qE 'static[[:space:]]+(readonly[[:space:]]+)?[A-Za-z0-9_<>]+[[:space:]]+(Instance|Current|Shared|Main|Default)[[:space:]]*[{;=]' "$f" 2>/dev/null && echo "true" || \
  grep -qE 'static[[:space:]]+[A-Za-z0-9_<>]+[[:space:]]+_instance\b' "$f" 2>/dev/null && echo "true" || echo "false"
}

extract_events_published() {
  local f="$1" result a b combined
  # Pass A: generic form  _eventBus.Publish<EventName>()
  a=$(grep -oE '\.(Publish)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>') || a=""
  # Pass B: constructor-call form  _eventBus.Publish(new EventName(...))
  b=$(grep -oE '\.Publish\([[:space:]]*new[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null | sed -E 's/^\.Publish\([[:space:]]*new[[:space:]]+//') || b=""
  combined=$(printf '%s\n%s\n' "$a" "$b" | grep -v '^$' | sort -u) || combined=""
  result=$(printf '%s' "$combined" | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}

extract_events_subscribed() {
  local f="$1" result
  result=$(grep -oE '\.(Subscribe)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>' | sort -u | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}

extract_registrations() {
  local f="$1" result
  result=$(python3 - "$f" <<'PYEOF'
import re, sys, json

try:
    text = open(sys.argv[1]).read()
except Exception:
    print("[]"); sys.exit(0)

results = []

# Field-type map keyed by NAME (not type) so FIELD_TYPES.get(ident) resolves.
# dict(re.findall(...)) would key by type and make every lookup miss.
FIELD_TYPES = {name: typ for typ, name in re.findall(
    r'(?:private|protected|public|internal|readonly|static|\s)+'
    r'([A-Za-z0-9_<>\.]+)\s+(_?[a-zA-Z][A-Za-z0-9_]*)\s*[;=]', text)}

# Spans consumed by Form 1b/1c so Form 1's generic regex does not also match them.
consumed_starts = set()

def _chain_as(pos):
    """Trailing `.As<T>()` / `.AsImplementedInterfaces()` for the statement starting at `pos`.

    Shared by Form 1b/1c and Form 1 so the precedence rule is implemented in ONE place.
    Bounded at the statement terminator `;` — an unbounded window reads the NEXT
    statement's chain and mis-assigns it (see the boundary note in Form 1).
    First `.As<T>()` wins -> always a single STRING, matching the tree-sitter `_as_chain`.
    """
    tail = text[pos:pos + 400]
    _end = tail.find(";")
    if _end != -1:
        tail = tail[:_end]
    hits = re.findall(r'\.As<([A-Za-z0-9_]+)>', tail)
    if hits:
        return hits[0]
    if ".AsImplementedInterfaces()" in tail:
        return "AsImplementedInterfaces"
    return ""

# Form 1b: builder.RegisterInstance<IFoo>(new Foo(...))
for m in re.finditer(
    r'builder\.RegisterInstance<([A-Za-z0-9_]+)>\s*\(\s*new\s+([A-Za-z0-9_]+)',
    text
):
    consumed_starts.add(m.start())
    # An explicit .As<T>() outranks the generic interface arg — Task 2 step 7, and it is
    # what the tree-sitter side already does (`chained or type_arg`). Without this the two
    # extractors DIVERGE on RegisterInstance<IFoo>(new Foo()).As<IBar>(): fallback said
    # IFoo, tree-sitter said IBar. Caught in final review; the rule was documented below
    # but never implemented here.
    results.append({
        "type": m.group(2), "as": _chain_as(m.end()) or m.group(1),
        "lifetime": "Singleton", "scope": ""
    })

# Form 1c: builder.RegisterInstance<IFoo>(_fooField)
for m in re.finditer(
    r'builder\.RegisterInstance<([A-Za-z0-9_]+)>\s*\(\s*(_?[a-zA-Z][A-Za-z0-9_]*)\s*\)',
    text
):
    if m.start() in consumed_starts:
        continue
    consumed_starts.add(m.start())
    iface, ident = m.group(1), m.group(2)
    concrete = FIELD_TYPES.get(ident, "")
    chained = _chain_as(m.end())     # explicit chain outranks the generic arg — see Form 1b
    if concrete:
        results.append({"type": concrete, "as": chained or iface, "lifetime": "Singleton", "scope": ""})
    else:
        # Mirrors Task 1 step 7 (tree-sitter side): the ONLY interface_only site
        # in this extractor. Do NOT reuse Form 2's name-guessing heuristic here —
        # the generic argument is strictly better information than a de-underscored
        # identifier guess.
        results.append({"type": iface, "as": "", "lifetime": "Singleton",
                        "scope": "", "interface_only": True, "confidence": "INFERRED"})

# Form 1: generic  builder.Register<Type>(Lifetime.X)
# `as` is normalised to a STRING throughout (was a list-or-string). schema.json:177
# types `as` as string, and knowledge-graph.md:139 compares it as a scalar (`.as == $name`),
# so a list has never matched any consumer. Task 1's tree-sitter `_as_chain` also takes
# only the first link, so first-wins is the agreed rule on both sides. Dropping the rest
# loses no information any consumer could ever see.
# Precedence: an explicit .As<T>() chain still wins over a generic interface argument on
# a RegisterInstance<T>(...) call — that shape is already routed through Form 1b/1c above
# and skipped here via consumed_starts, so this loop only ever sees the chain for those.
# TODO(parity): RegisterInstance<IFoo>(new Foo()).As<IBar>() — which of IFoo/IBar belongs
# in `as` is unresolved; no such call site exists in either repo to arbitrate it. Current
# behaviour (explicit chain wins) is kept, matching Task 1's tree-sitter side.
for m in re.finditer(
    r'builder\.(Register(?:Instance|Component(?:InHierarchy)?)?)'
    r'<([A-Za-z0-9_]+)>'
    r'(?:[^;(]*\(\s*Lifetime\.(\w+)\s*\))?',
    text
):
    if m.group(1) == "RegisterInstance" and m.start() in consumed_starts:
        continue
    # Factory-delegate overload: Register<TService>(resolver => new Impl(..), lifetime).
    # The generic slot is the SERVICE type here, not the concrete one — taking it as concrete
    # put an interface in `type`, which reg.2 forbids and which raised false
    # INSTALLER_MISSING_CLASS warnings. Mirrors _factory_delegate_concrete() on the
    # tree-sitter side, including the three-valued outcome, so reg.4 parity stays meaningful
    # instead of being two extractors agreeing on the same wrong answer (which is exactly
    # what reg.4 reported while both sides carried this bug).
    # Detection is STRUCTURAL — a `=>` right after the opening paren — never the generic's
    # name: `Register<Corge>(r => new Corge())` is the same overload with a concrete generic.
    # m.end() sits just after `<TService>` for this shape: the optional Lifetime group needs
    # `\(\s*Lifetime\.` right there and a lambda argument does not match it, so the group
    # fails and the args are still ahead of us. Bound the scan at the statement terminator
    # for the same reason _chain_as does — an unbounded window reads the next statement.
    _tail = text[m.end():m.end() + 600]
    _semi = _tail.find(";")
    if _semi != -1:
        _tail = _tail[:_semi]

    if re.match(r'\s*\(\s*(?:\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\s*=>', _tail):
        # First `new X(` in the body is the OUTERMOST one: `new Foo(new Bar())` -> Foo.
        _new = re.search(r'\bnew\s+([A-Za-z0-9_.]+)\s*[({]', _tail)
        _concrete = _new.group(1).split(".")[-1] if _new else ""
        _generic = m.group(2)
        if _concrete:
            reg = {
                "type": _concrete,
                "as": _chain_as(m.end()) or (_generic if _generic != _concrete else ""),
                "lifetime": m.group(3) or "Singleton",
                "scope": ""
            }
        else:
            # Body names no constructible type. Empty `type` is the honest record; falling
            # back to the generic is the defect. Matches the tree-sitter unresolved shape.
            reg = {
                "type": "",
                "as": _chain_as(m.end()) or _generic,
                "lifetime": m.group(3) or "Singleton",
                "scope": "",
                "unresolved": True,
                "confidence": "AMBIGUOUS"
            }
        results.append(reg)
        continue

    reg = {
        "type": m.group(2),
        "as": "",
        "lifetime": m.group(3) or "Singleton",
        "scope": ""
    }
    # Bound the chain scan at the STATEMENT terminator, not at a fixed character count.
    # Without the `;` cut, a chainless `Register<Bar>(...)` immediately followed by a chained
    # `Register<Baz>(...).As<IBaz>()` reads IBaz out of the NEXT statement and reports
    # {"type":"Bar","as":"IBaz"} — wrong data in the very key this plan makes load-bearing,
    # and a parity break against the tree-sitter side, which correctly emits "". Reproduced
    # during v4 implementation; found by Task 8's probe construction.
    reg["as"] = _chain_as(m.end())   # same helper as Form 1b/1c — one implementation of the rule
    results.append(reg)

# Form 2: non-generic  builder.RegisterInstance(someVar)
# Consult the field-type map before falling back to the name guess; keep "inferred": True
# on the guessed path so its low confidence stays visible. No interface_only here — there
# is no interface argument in play for this form.
for m in re.finditer(
    r'builder\.RegisterInstance\(([A-Za-z0-9_\.]+)\)',
    text
):
    arg = m.group(1)
    concrete = FIELD_TYPES.get(arg, "")
    if concrete:
        reg = {"type": concrete, "as": "", "lifetime": "Singleton", "scope": ""}
    else:
        # Infer type from variable name: strip leading _ and uppercase first char.
        type_name = arg.lstrip('_')
        type_name = type_name[0].upper() + type_name[1:] if type_name else arg
        reg = {"type": type_name, "as": "", "lifetime": "Singleton", "scope": "", "inferred": True}
    results.append(reg)

# Deduplicate by (type, as) pair, not type alone — two interfaces backed by the same
# concrete (e.g. RegisterInstance<IReader>(_store) and RegisterInstance<IWriter>(_store))
# must both survive. `as` is always a string now, so the key needs no json.dumps wrapper.
# Note: Task 1's tree-sitter path has no dedup at all, so this change reduces (does not
# create) divergence between the two extractors.
seen = set()
deduped = []
for r in results:
    k = (r["type"], r.get("as", ""))
    if k not in seen:
        seen.add(k)
        deduped.append(r)
print(json.dumps(deduped))
PYEOF
) || result=""
  echo "${result:-[]}"
}

extract_dependencies() {
  local f="$1" result
  result=$(grep -oE 'I[A-Z][A-Za-z0-9]+[[:space:]]+[a-z][A-Za-z0-9]+' "$f" 2>/dev/null | grep -oE '^I[A-Z][A-Za-z0-9]+' | sort -u | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}

extract_scope() {
  local f="$1" result
  result=$(python3 - "$f" <<'PYEOF'
import re, sys, json

try:
    text = open(sys.argv[1]).read()
except Exception:
    print("null"); sys.exit(0)

# Match class declaration that inherits LifetimeScope (single or multi-line)
# Joins up to 4 lines to handle split declarations
lines = text.splitlines()
combined = ""
scope_name = None
for i, line in enumerate(lines):
    chunk = " ".join(lines[i:i+4])
    m = re.search(r'class\s+([A-Z][A-Za-z0-9_]*)\s*[:<][^{]*LifetimeScope', chunk)
    if m:
        scope_name = m.group(1)
        break

if not scope_name:
    print("null"); sys.exit(0)

# Detect parent: look for [ParentScope(typeof(XScope))] attribute or
# a field/property typed as XScope where name ends with "Scope"
# Only match inside [ParentScope(...)] to avoid false typeof() references
parent = None
pm = re.search(r'\[ParentScope\s*\(\s*typeof\s*\(\s*([A-Za-z0-9_]+Scope)\s*\)', text)
if pm:
    parent = pm.group(1)

print(json.dumps({
    "name": scope_name,
    "file": sys.argv[1],
    "source_file": sys.argv[1],
    "parent": parent,
    "installers": []
}))
PYEOF
) || result="null"
  echo "${result:-null}"
}

# ── Per-file extraction ──────────────────────────────────────────────────────

process_file_regex() {
  local f="$1"
  local ns
  ns=$(extract_namespace "$f")
  local static_inst
  static_inst=$(has_static_instance "$f")
  local published
  published=$(extract_events_published "$f")
  local subscribed
  subscribed=$(extract_events_subscribed "$f")
  local deps
  deps=$(extract_dependencies "$f")
  local regs
  regs=$(extract_registrations "$f")
  local scope_entry
  scope_entry=$(extract_scope "$f")

  # Build classes array using python3-based extractor (handles multi-line declarations)
  # extract_class_info emits TWO lines: JSON array of classes, then {"partial_calls":[...]}
  local classes_json="[]"
  local file_partial_calls="[]"
  local class_info_raw
  class_info_raw=$(extract_class_info "$f")
  local class_info
  class_info=$(echo "$class_info_raw" | head -n1)
  local calls_line
  calls_line=$(echo "$class_info_raw" | tail -n1)
  file_partial_calls=$(echo "$calls_line" | jq '.partial_calls // []' 2>/dev/null || echo "[]")

  while IFS= read -r entry_raw; do
    [[ -z "$entry_raw" ]] && continue
    local class_name linenum base_arr impl mono methods_arr
    class_name=$(echo "$entry_raw" | jq -r '.name')
    linenum=$(echo "$entry_raw" | jq '.line')
    base_arr=$(echo "$entry_raw" | jq '.base_types')
    impl=$(echo "$entry_raw" | jq '.implements')
    methods_arr=$(echo "$entry_raw" | jq '.methods // []')
    # Determine is_mono_behaviour from base_types
    mono=$(echo "$base_arr" | jq -r 'if (. | index("MonoBehaviour")) != null then "true" else "false" end')

    local entry
    entry=$(jq -nc \
      --arg name "$class_name" \
      --arg ns "$ns" \
      --arg file "$f" \
      --argjson line "$linenum" \
      --argjson base_types "$base_arr" \
      --argjson is_mono "$mono" \
      --argjson implements "$impl" \
      --argjson deps "$deps" \
      --argjson published "$published" \
      --argjson subscribed "$subscribed" \
      --argjson has_static "$static_inst" \
      --argjson methods "$methods_arr" \
      --arg confidence "$CONFIDENCE" \
      '{
        name: $name,
        namespace: $ns,
        file: $file,
        source_file: $file,
        line: $line,
        base_types: $base_types,
        is_mono_behaviour: $is_mono,
        implements: $implements,
        dependencies: $deps,
        events_published: $published,
        events_subscribed: $subscribed,
        has_static_instance: $has_static,
        methods: $methods,
        confidence: $confidence
      }')
    classes_json=$(echo "$classes_json" | jq ". + [$entry]")
  done < <(echo "$class_info" | jq -c '.[]')

  # Build interfaces array
  local ifaces_json="[]"
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local ilinenum iname
    ilinenum=$(echo "$match" | cut -d: -f1)
    iname=$(echo "$match" | grep -oE 'interface[[:space:]]+(I[A-Z][A-Za-z0-9_]*)' | awk '{print $2}')
    [[ -z "$iname" ]] && continue

    local ientry
    ientry=$(jq -nc \
      --arg name "$iname" \
      --arg ns "$ns" \
      --arg file "$f" \
      --argjson line "$ilinenum" \
      --arg confidence "$CONFIDENCE" \
      '{ name: $name, namespace: $ns, file: $file, source_file: $file, line: $line, implementers: [], confidence: $confidence }')
    ifaces_json=$(echo "$ifaces_json" | jq ". + [$ientry]")
  done < <(extract_interfaces "$f")

  # Installer registrations
  #
  # Detection MIRRORS _declares_container_install() on the tree-sitter side, deliberately
  # including its two legacy name tests, so the two extractors cannot disagree about what a
  # registration belongs to. Before this, the test here was `grep -q 'Installer'` on the FILE
  # NAME — and `bootstrap-pattern.md` mandates the name `*Module`, having deliberately deleted
  # the ModuleInstaller/AppInstaller types this test looks for. Measured across four projects
  # built from this template: zero files named *Installer*, nine real installers in this one.
  # So the fallback reported `installers: []` for every project, and `reg.4` parity passed only
  # because the probe fixture happens to be called ProbeInstaller.cs — the fixture was shaped to
  # the bug, which is why the factory-delegate defect could sit behind a green parity test.
  #
  # This is the same failure CLAUDE.md already records for the tree-sitter side ("Installer
  # detection is structural … Not a name suffix"); that fix simply never reached this file.
  # Do NOT "repair" a future miss by adding `Module` to a name pattern — that is the
  # hand-maintained-blacklist trap the same note warns about. The structural clause is the rule;
  # the name clauses only keep already-detected files detected.
  local installer_json="null"
  if grep -Eq '\bInstall[A-Za-z0-9_]*[[:space:]]*\([^)]*IContainerBuilder' "$f" \
     || basename "$f" .cs | grep -Eq 'Installer$|Module$'; then
    local iname
    iname=$(basename "$f" .cs)
    installer_json=$(jq -nc \
      --arg name "$iname" \
      --arg file "$f" \
      --argjson regs "$regs" \
      '{ name: $name, file: $file, source_file: $file, registrations: $regs }')
  fi

  jq -nc \
    --arg file "$f" \
    --argjson classes "$classes_json" \
    --argjson interfaces "$ifaces_json" \
    --argjson published "$published" \
    --argjson subscribed "$subscribed" \
    --argjson installer "$installer_json" \
    --argjson scope "$scope_entry" \
    --argjson partial_calls "$file_partial_calls" \
    '{
      file: $file,
      partial: true,
      classes: $classes,
      interfaces: $interfaces,
      events_published: $published,
      events_subscribed: $subscribed,
      installer: $installer,
      scope: $scope,
      partial_calls: $partial_calls
    }'
}

# ── Collect all per-file payloads ───────────────────────────────────────────

declare -a PAYLOADS=()
for f in "${FILES[@]:-}"; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  payload=$(process_file_regex "$f")
  PAYLOADS+=("$payload")
done

# ── Merge into codebase shape ────────────────────────────────────────────────

ALL_CLASSES="[]"
ALL_IFACES="[]"
ALL_INSTALLERS="[]"
ALL_SCOPES="[]"
ALL_PARTIAL_CALLS="[]"

for p in "${PAYLOADS[@]:-}"; do
  [[ -z "$p" ]] && continue
  ALL_CLASSES=$(echo "$ALL_CLASSES" | jq ". + $(echo "$p" | jq '.classes')")
  ALL_IFACES=$(echo "$ALL_IFACES" | jq ". + $(echo "$p" | jq '.interfaces')")
  inst=$(echo "$p" | jq '.installer')
  [[ "$inst" != "null" ]] && ALL_INSTALLERS=$(echo "$ALL_INSTALLERS" | jq ". + [$inst]")
  scope=$(echo "$p" | jq '.scope')
  [[ "$scope" != "null" ]] && ALL_SCOPES=$(echo "$ALL_SCOPES" | jq ". + [$scope]")
  pcalls=$(echo "$p" | jq '.partial_calls // []')
  ALL_PARTIAL_CALLS=$(echo "$ALL_PARTIAL_CALLS" | jq ". + $pcalls")
done

# Sort partial_calls by (caller, line) for idempotency
ALL_PARTIAL_CALLS=$(echo "$ALL_PARTIAL_CALLS" | jq 'sort_by([.caller, .line])')

# Pivot events: aggregate publisher/subscriber lists across all classes
ALL_EVENTS=$(echo "$ALL_CLASSES" | jq '
  reduce .[] as $cls (
    {};
    ($cls.events_published[] // empty) as $ev |
    .[$ev].name = $ev |
    .[$ev].file = $cls.file |
    .[$ev].source_file = $cls.file |
    .[$ev].publishers = ((.[$ev].publishers // []) + [$cls.name]) |
    .[$ev].subscribers = (.[$ev].subscribers // []) |
    .[$ev].confidence = "'"$CONFIDENCE"'"
  ) |
  to_entries | map(.value) |
  reduce .[] as $item (
    .,
    ('"$(echo "$ALL_CLASSES" | jq -c '.')"' | .[] | .events_subscribed[] // empty) as $ev |
    .
  )
' 2>/dev/null || echo "[]")

# Simpler event pivot using python3 for reliability
ALL_EVENTS=$(GRAPH_CLASSES="$ALL_CLASSES" GRAPH_CONFIDENCE="$CONFIDENCE" python3 - <<'PYEOF'
import sys, json, os

confidence = os.environ.get("GRAPH_CONFIDENCE", "INFERRED")
classes_raw = os.environ.get("GRAPH_CLASSES", "[]")
try:
    classes = json.loads(classes_raw)
except Exception:
    classes = []

events = {}
for cls in classes:
    for ev in cls.get("events_published", []):
        events.setdefault(ev, {"name": ev, "file": cls["file"], "source_file": cls["file"],
                                "publishers": [], "subscribers": [], "confidence": confidence})
        events[ev]["publishers"].append(cls["name"])
    for ev in cls.get("events_subscribed", []):
        events.setdefault(ev, {"name": ev, "file": cls["file"], "source_file": cls["file"],
                                "publishers": [], "subscribers": [], "confidence": confidence})
        events[ev]["subscribers"].append(cls["name"])

print(json.dumps(list(events.values())))
PYEOF
)

jq -n \
  --argjson classes "$ALL_CLASSES" \
  --argjson interfaces "$ALL_IFACES" \
  --argjson events "$ALL_EVENTS" \
  --argjson installers "$ALL_INSTALLERS" \
  --argjson scopes "$ALL_SCOPES" \
  --argjson partial_calls "$ALL_PARTIAL_CALLS" \
  '{
    classes: $classes,
    interfaces: $interfaces,
    events: $events,
    vcontainer: { installers: $installers, scopes: $scopes },
    partial_calls: $partial_calls
  }'
