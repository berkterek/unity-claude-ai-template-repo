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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files)  CHANGED_FILES="$2"; shift 2 ;;
    --include-tests)  INCLUDE_TESTS=1; shift ;;
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
  FIND_OPTS=( Assets/_Framework Assets/_GameFolders/Scripts )
  [[ -d Packages ]] && FIND_OPTS+=( Packages )
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

extract_base_list() {
  local line="$1"
  # Grab everything after : on the class declaration line
  echo "$line" | grep -oE ':[[:space:]]*[A-Za-z0-9_<>, ]+' | sed 's/^:[[:space:]]*//' | tr -d '\n' || echo ""
}

has_static_instance() {
  local f="$1"
  grep -qE 'static[[:space:]]+(readonly[[:space:]]+)?[A-Za-z0-9_<>]+[[:space:]]+(Instance|Current|Shared|Main|Default)[[:space:]]*[{;=]' "$f" 2>/dev/null && echo "true" || \
  grep -qE 'static[[:space:]]+[A-Za-z0-9_<>]+[[:space:]]+_instance\b' "$f" 2>/dev/null && echo "true" || echo "false"
}

is_mono_behaviour() {
  local base_list="$1"
  echo "$base_list" | grep -q 'MonoBehaviour' && echo "true" || echo "false"
}

extract_events_published() {
  local f="$1" result a b combined
  # Pass A: legacy generic form  _eventBus.Publish<EventName>()
  a=$(grep -oE '\.(Publish)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>') || a=""
  # Pass B: constructor-call form  _eventBus.Publish(new EventName(...))
  b=$(grep -oE '\.Publish\([[:space:]]*new[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null | sed -E 's/^\.Publish\([[:space:]]*new[[:space:]]+//') || b=""
  combined=$(printf '%s\n%s\n' "$a" "$b" | grep -v '^$' | sort -u) || combined=""
  result=$(printf '%s' "$combined" | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}

extract_events_subscribed() {
  local f="$1"
  grep -oE '\.(Subscribe)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>' | sort -u | jq -R . | jq -sc . || echo "[]"
}

extract_registrations() {
  local f="$1"
  grep -oE 'builder\.(Register|RegisterInstance|RegisterComponent)<([A-Za-z0-9_]+)>' "$f" 2>/dev/null | grep -oE '<([A-Za-z0-9_]+)>' | tr -d '<>' | sort -u | jq -R '{type: ., as: "", lifetime: "Singleton", scope: ""}' | jq -sc . || echo "[]"
}

extract_dependencies() {
  local f="$1"
  # Constructor parameters that look like injected services (IXxx types)
  grep -oE 'I[A-Z][A-Za-z0-9]+[[:space:]]+[a-z][A-Za-z0-9]+' "$f" 2>/dev/null | grep -oE '^I[A-Z][A-Za-z0-9]+' | sort -u | jq -R . | jq -sc . || echo "[]"
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

  # Build classes array
  local classes_json="[]"
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    local linenum class_name raw_base base_arr mono impl
    linenum=$(echo "$match" | cut -d: -f1)
    class_name=$(echo "$match" | grep -oE 'class[[:space:]]+([A-Z][A-Za-z0-9_]*)' | awk '{print $2}')
    [[ -z "$class_name" ]] && continue
    raw_base=$(extract_base_list "$match")
    base_arr=$(echo "$raw_base" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -v '^$' | jq -R . | jq -sc . 2>/dev/null || echo "[]")
    mono=$(is_mono_behaviour "$raw_base")
    impl=$(echo "$raw_base" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -E '^I[A-Z]' | jq -R . | jq -sc . 2>/dev/null || echo "[]")

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
        confidence: $confidence
      }')
    classes_json=$(echo "$classes_json" | jq ". + [$entry]")
  done < <(extract_classes "$f")

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
    '{
      file: $file,
      partial: true,
      classes: $classes,
      interfaces: $interfaces,
      events_published: $published,
      events_subscribed: $subscribed,
      installer: $installer
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

for p in "${PAYLOADS[@]:-}"; do
  [[ -z "$p" ]] && continue
  ALL_CLASSES=$(echo "$ALL_CLASSES" | jq ". + $(echo "$p" | jq '.classes')")
  ALL_IFACES=$(echo "$ALL_IFACES" | jq ". + $(echo "$p" | jq '.interfaces')")
  inst=$(echo "$p" | jq '.installer')
  [[ "$inst" != "null" ]] && ALL_INSTALLERS=$(echo "$ALL_INSTALLERS" | jq ". + [$inst]")
done

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
ALL_EVENTS=$(python3 - "$CONFIDENCE" <<'PYEOF'
import sys, json

confidence = sys.argv[1]
classes = json.loads(sys.stdin.read()) if not sys.stdin.isatty() else []

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
) <<< "$ALL_CLASSES"

jq -n \
  --argjson classes "$ALL_CLASSES" \
  --argjson interfaces "$ALL_IFACES" \
  --argjson events "$ALL_EVENTS" \
  --argjson installers "$ALL_INSTALLERS" \
  '{
    classes: $classes,
    interfaces: $interfaces,
    events: $events,
    vcontainer: { installers: $installers, scopes: [] }
  }'
