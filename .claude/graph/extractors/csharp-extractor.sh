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
  # Resolve root prefix: --root arg > auto-detect HoleSphere/ > fallback Assets/
  if [[ -n "$CS_ROOT" ]]; then
    _prefix="$CS_ROOT"
  elif [[ -d "HoleSphere/Assets" ]]; then
    _prefix="HoleSphere/Assets"
  else
    _prefix="Assets"
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

# Form 1: generic  builder.Register<Type>(Lifetime.X)
for m in re.finditer(
    r'builder\.(Register(?:Instance|Component(?:InHierarchy)?)?)'
    r'<([A-Za-z0-9_]+)>'
    r'(?:[^;(]*\(\s*Lifetime\.(\w+)\s*\))?',
    text
):
    reg = {
        "type": m.group(2),
        "as": [],
        "lifetime": m.group(3) or "Singleton",
        "scope": ""
    }
    tail = text[m.end():m.end()+400]
    # Collect all .As<T>() in the chain
    as_matches = re.findall(r'\.As<([A-Za-z0-9_]+)>', tail[:300])
    if as_matches:
        reg["as"] = as_matches if len(as_matches) > 1 else as_matches[0]
    elif ".AsImplementedInterfaces()" in tail[:200]:
        reg["as"] = "AsImplementedInterfaces"
    results.append(reg)

# Form 2: non-generic  builder.RegisterInstance(someVar)
for m in re.finditer(
    r'builder\.RegisterInstance\(([A-Za-z0-9_\.]+)\)',
    text
):
    arg = m.group(1)
    # Infer type from variable name: strip leading _ and lowercase
    type_name = arg.lstrip('_')
    type_name = type_name[0].upper() + type_name[1:] if type_name else arg
    reg = {"type": type_name, "as": "", "lifetime": "Singleton", "scope": "", "inferred": True}
    results.append(reg)

# Deduplicate by type (first occurrence wins)
seen = set()
deduped = []
for r in results:
    if r["type"] not in seen:
        seen.add(r["type"])
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
  local installer_json="null"
  if echo "$f" | grep -q 'Installer'; then
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
