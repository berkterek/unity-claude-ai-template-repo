#!/usr/bin/env bash
# graph-builder.sh — Aggregates extractor output + SHA256 cache → graph.json
# Usage:
#   graph-builder.sh [--full] [--incremental] [--changed-files a.cs,b.asmdef]
#                    [--skip-mcp] [--output path/to/graph.json] [--quiet]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_EPOCH=$(python3 -c "import time; print(int(time.time() * 1000))")

# ── Flags ────────────────────────────────────────────────────────────────────
MODE="incremental"
CHANGED_FILES=""
SKIP_MCP=0
OUTPUT="${SCRIPT_DIR}/graph.json"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)           MODE="full"; shift ;;
    --incremental)    MODE="incremental"; shift ;;
    --changed-files)  CHANGED_FILES="$2"; shift 2 ;;
    --skip-mcp)       SKIP_MCP=1; shift ;;
    --output)         OUTPUT="$2"; shift 2 ;;
    --quiet)          QUIET=1; shift ;;
    *) shift ;;
  esac
done

log() { [[ $QUIET -eq 1 ]] && return; echo "graph-builder: $*" >&2; }

# ── SHA256 tool detection ─────────────────────────────────────────────────────
SHA_CMD="sha256sum"
command -v sha256sum >/dev/null 2>&1 || SHA_CMD="shasum -a 256"

hash_file() { $SHA_CMD "$1" 2>/dev/null | awk '{print $1}'; }

# ── Paths ────────────────────────────────────────────────────────────────────
CACHE_FILE="${SCRIPT_DIR}/cache/file-hashes.json"
MCP_CACHE="${SCRIPT_DIR}/cache/mcp-extract.json"
LAST_BUILD="${SCRIPT_DIR}/.last-build"
ASMDEF_EX="${SCRIPT_DIR}/extractors/asmdef-extractor.sh"
CSHARP_EX="${SCRIPT_DIR}/extractors/csharp-extractor.sh"

mkdir -p "${SCRIPT_DIR}/cache"
[[ -f "$CACHE_FILE" ]] || echo '{}' > "$CACHE_FILE"
[[ -f "$OUTPUT" ]] || echo '{}' > "$OUTPUT"

# ── Determine changed files ──────────────────────────────────────────────────
# Gather all candidate source files
declare -a ALL_CS=() ALL_ASMDEF=()

if [[ -n "$CHANGED_FILES" ]]; then
  IFS=',' read -ra RAW <<< "$CHANGED_FILES"
  for f in "${RAW[@]}"; do
    [[ "$f" == *.cs     ]] && ALL_CS+=("$f")
    [[ "$f" == *.asmdef ]] && ALL_ASMDEF+=("$f")
  done
else
  while IFS= read -r -d '' f; do
    ALL_CS+=("$f")
  done < <(find Assets/_Framework Assets/_GameFolders/Scripts -name '*.cs' -print0 2>/dev/null || true)
  while IFS= read -r -d '' f; do
    ALL_ASMDEF+=("$f")
  done < <(find Assets -name '*.asmdef' -print0 2>/dev/null || true)
fi

# ── Cache-aware file selection ───────────────────────────────────────────────
declare -a CHANGED_CS=() CHANGED_ASMDEF=()
CACHE_HITS=0
SCANNED=0

# Load current cache
CURRENT_CACHE=$(cat "$CACHE_FILE")

# Current paths set (for ghost purge)
declare -a CURRENT_PATHS=()

check_file() {
  local f="$1"
  CURRENT_PATHS+=("$f")
  ((SCANNED++)) || true
  [[ -f "$f" ]] || return 0
  local cur_hash
  cur_hash=$(hash_file "$f")
  local cached_hash
  cached_hash=$(echo "$CURRENT_CACHE" | jq -r --arg k "$f" '.[$k] // ""')
  if [[ "$MODE" == "full" || "$cur_hash" != "$cached_hash" ]]; then
    echo "$f"
  else
    ((CACHE_HITS++)) || true
  fi
}

while IFS= read -r f; do
  CHANGED_CS+=("$f")
done < <(for f in "${ALL_CS[@]:-}"; do [[ -z "$f" ]] && continue; check_file "$f"; done)

while IFS= read -r f; do
  CHANGED_ASMDEF+=("$f")
done < <(for f in "${ALL_ASMDEF[@]:-}"; do [[ -z "$f" ]] && continue; check_file "$f"; done)

log "scan: ${SCANNED} files, ${CACHE_HITS} cache hits, $((${#CHANGED_CS[@]:-0} + ${#CHANGED_ASMDEF[@]:-0})) to re-extract"

# ── Run extractors ────────────────────────────────────────────────────────────

CS_OUTPUT='{"classes":[],"interfaces":[],"events":[],"vcontainer":{"installers":[],"scopes":[]}}'
ASMDEF_OUTPUT='[]'

if [[ ${#CHANGED_CS[@]} -gt 0 ]]; then
  log "running csharp-extractor on ${#CHANGED_CS[@]} files…"
  CHANGED_CS_STR=$(IFS=','; echo "${CHANGED_CS[*]}")
  if [[ -x "$CSHARP_EX" ]]; then
    CS_OUTPUT=$(bash "$CSHARP_EX" --changed-files "$CHANGED_CS_STR" 2>/dev/null) || CS_OUTPUT='{"classes":[],"interfaces":[],"events":[],"vcontainer":{"installers":[],"scopes":[]}}'
  fi
fi

if [[ ${#CHANGED_ASMDEF[@]} -gt 0 ]]; then
  log "running asmdef-extractor on ${#CHANGED_ASMDEF[@]} files…"
  CHANGED_ASMDEF_STR=$(IFS=','; echo "${CHANGED_ASMDEF[*]}")
  if [[ -x "$ASMDEF_EX" ]]; then
    ASMDEF_OUTPUT=$(bash "$ASMDEF_EX" --changed-files "$CHANGED_ASMDEF_STR" 2>/dev/null) || ASMDEF_OUTPUT='[]'
  fi
fi

# ── MCP cache merge ───────────────────────────────────────────────────────────
MCP_STATUS="skipped"
MCP_SCENES="[]"
MCP_PREFABS="[]"
MCP_EXTRACTED_AT="null"
MCP_SKIP_REASON="MCP_UNAVAILABLE"

if [[ $SKIP_MCP -eq 0 && -f "$MCP_CACHE" ]]; then
  # Check freshness: reuse if < 1 hour old
  MCP_AGE=9999
  if command -v python3 >/dev/null 2>&1; then
    MCP_AGE=$(python3 -c "
import os, time
mtime = os.path.getmtime('$MCP_CACHE')
print(int((time.time() - mtime) / 60))
" 2>/dev/null || echo 9999)
  fi
  if [[ $MCP_AGE -lt 60 ]]; then
    MCP_SCENES=$(jq -r '.scenes // []' "$MCP_CACHE")
    MCP_PREFABS=$(jq -r '.prefabs // []' "$MCP_CACHE")
    MCP_EXTRACTED_AT=$(jq -r '.extracted_at // null' "$MCP_CACHE")
    MCP_STATUS="ok"
    log "mcp cache reused (${MCP_AGE}m old)"
  else
    log "mcp cache stale (${MCP_AGE}m old) — MCP refresh recommended; pass --skip-mcp to suppress"
  fi
elif [[ $SKIP_MCP -eq 1 ]]; then
  MCP_SKIP_REASON="SKIP_MCP_FLAG"
fi

# ── Merge with existing graph (retained cache entries) ────────────────────────
# Load existing graph
EXISTING_GRAPH=$(cat "$OUTPUT" 2>/dev/null || echo '{}')

# For incremental mode: retain entries from files that were NOT re-extracted
RETAINED_CLASSES="[]"
RETAINED_IFACES="[]"
RETAINED_ASSEMBLIES="[]"
RETAINED_INSTALLERS="[]"

if [[ "$MODE" == "incremental" ]]; then
  # Build set of re-extracted source files
  REEXTRACTED_SET=$(python3 -c "
import sys, json
files = '${CHANGED_CS_STR:-},${CHANGED_ASMDEF_STR:-}'.split(',')
print(json.dumps([f for f in files if f]))
" 2>/dev/null || echo "[]")

  RETAINED_CLASSES=$(echo "$EXISTING_GRAPH" | jq \
    --argjson re "$REEXTRACTED_SET" \
    '[.codebase.classes // [] | .[] | select(.source_file as $sf | $re | index($sf) == null)]' 2>/dev/null || echo "[]")
  RETAINED_IFACES=$(echo "$EXISTING_GRAPH" | jq \
    --argjson re "$REEXTRACTED_SET" \
    '[.codebase.interfaces // [] | .[] | select(.source_file as $sf | $re | index($sf) == null)]' 2>/dev/null || echo "[]")
  RETAINED_ASSEMBLIES=$(echo "$EXISTING_GRAPH" | jq \
    --argjson re "$REEXTRACTED_SET" \
    '[.codebase.assemblies // [] | .[] | select(.source_file as $sf | $re | index($sf) == null)]' 2>/dev/null || echo "[]")
  RETAINED_INSTALLERS=$(echo "$EXISTING_GRAPH" | jq \
    --argjson re "$REEXTRACTED_SET" \
    '[.codebase.vcontainer.installers // [] | .[] | select(.source_file as $sf | $re | index($sf) == null)]' 2>/dev/null || echo "[]")
fi

# ── Purge ghost entries (deleted/renamed files) ───────────────────────────────
CURRENT_PATHS_JSON=$(printf '%s\n' "${CURRENT_PATHS[@]:-}" | jq -R . | jq -sc . 2>/dev/null || echo "[]")

purge_ghosts() {
  local arr="$1"
  echo "$arr" | jq --argjson paths "$CURRENT_PATHS_JSON" \
    '[.[] | select(.source_file as $sf | $sf == null or ($paths | index($sf) != null))]' 2>/dev/null || echo "$arr"
}

RETAINED_CLASSES=$(purge_ghosts "$RETAINED_CLASSES")
RETAINED_IFACES=$(purge_ghosts "$RETAINED_IFACES")
RETAINED_ASSEMBLIES=$(purge_ghosts "$RETAINED_ASSEMBLIES")
RETAINED_INSTALLERS=$(purge_ghosts "$RETAINED_INSTALLERS")

# ── Merge new + retained ──────────────────────────────────────────────────────
NEW_CLASSES=$(echo "$CS_OUTPUT" | jq '.classes // []')
NEW_IFACES=$(echo "$CS_OUTPUT" | jq '.interfaces // []')
NEW_EVENTS=$(echo "$CS_OUTPUT" | jq '.events // []')
NEW_INSTALLERS=$(echo "$CS_OUTPUT" | jq '.vcontainer.installers // []')

ALL_CLASSES=$(jq -n --argjson a "$RETAINED_CLASSES" --argjson b "$NEW_CLASSES" '$a + $b')
ALL_IFACES=$(jq -n --argjson a "$RETAINED_IFACES" --argjson b "$NEW_IFACES" '$a + $b')
ALL_ASSEMBLIES=$(jq -n --argjson a "$RETAINED_ASSEMBLIES" --argjson b "$ASMDEF_OUTPUT" '$a + $b')
ALL_INSTALLERS=$(jq -n --argjson a "$RETAINED_INSTALLERS" --argjson b "$NEW_INSTALLERS" '$a + $b')

# Re-pivot all events (full pass across merged classes)
ALL_EVENTS=$(python3 - <<PYEOF
import json, sys

classes = json.loads("""$ALL_CLASSES""")
prev_events = json.loads("""$NEW_EVENTS""")

events = {}
for cls in classes:
    for ev in cls.get("events_published", []):
        e = events.setdefault(ev, {"name": ev, "file": cls["file"], "source_file": cls["file"],
                                    "publishers": [], "subscribers": [], "confidence": cls.get("confidence","INFERRED")})
        if cls["name"] not in e["publishers"]:
            e["publishers"].append(cls["name"])
    for ev in cls.get("events_subscribed", []):
        e = events.setdefault(ev, {"name": ev, "file": cls["file"], "source_file": cls["file"],
                                    "publishers": [], "subscribers": [], "confidence": cls.get("confidence","INFERRED")})
        if cls["name"] not in e["subscribers"]:
            e["subscribers"].append(cls["name"])

print(json.dumps(list(events.values())))
PYEOF
)

# Resolve implementers
ALL_IFACES=$(python3 - <<PYEOF
import json

classes = json.loads("""$ALL_CLASSES""")
ifaces  = json.loads("""$ALL_IFACES""")

iface_map = {i["name"]: i for i in ifaces}
for cls in classes:
    for impl in cls.get("implements", []):
        if impl in iface_map:
            imps = iface_map[impl].setdefault("implementers", [])
            if cls["name"] not in imps:
                imps.append(cls["name"])

print(json.dumps(list(iface_map.values())))
PYEOF
)

# ── Build scopes from existing graph (stable) ─────────────────────────────────
SCOPES=$(echo "$EXISTING_GRAPH" | jq '.codebase.vcontainer.scopes // []' 2>/dev/null || echo "[]")

# ── Assemble final graph ──────────────────────────────────────────────────────
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
END_EPOCH=$(python3 -c "import time; print(int(time.time() * 1000))")
BUILD_MS=$(( END_EPOCH - START_EPOCH ))

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

MCP_META="{}"
if [[ "$MCP_STATUS" == "ok" ]]; then
  MCP_META=$(jq -n --arg at "$MCP_EXTRACTED_AT" '{"status":"ok","extracted_at":$at}')
else
  MCP_META=$(jq -n --arg reason "$MCP_SKIP_REASON" '{"status":"skipped","skipped_reason":$reason}')
fi

FINAL_GRAPH=$(jq -n \
  --arg sv "1.0.0" \
  --arg now "$NOW" \
  --arg gen "graph-builder.sh@${GIT_SHA}" \
  --argjson classes "$ALL_CLASSES" \
  --argjson interfaces "$ALL_IFACES" \
  --argjson events "$ALL_EVENTS" \
  --argjson installers "$ALL_INSTALLERS" \
  --argjson scopes "$SCOPES" \
  --argjson assemblies "$ALL_ASSEMBLIES" \
  --argjson scenes "$MCP_SCENES" \
  --argjson prefabs "$MCP_PREFABS" \
  --argjson mcp_meta "$MCP_META" \
  --argjson scanned "$SCANNED" \
  --argjson hits "$CACHE_HITS" \
  --argjson ms "$BUILD_MS" \
  '{
    schema_version: $sv,
    generated_at: $now,
    generator: $gen,
    confidence_legend: {
      EXTRACTED: "Explicit machine-readable data (asmdef JSON, tree-sitter AST)",
      INFERRED:  "Derived from regex patterns — correct on common cases, may miss edge cases",
      AMBIGUOUS: "Conflicting signals — needs human review"
    },
    codebase: {
      classes:    $classes,
      interfaces: $interfaces,
      events:     $events,
      vcontainer: { installers: $installers, scopes: $scopes },
      assemblies: $assemblies,
      scenes:     $scenes,
      prefabs:    $prefabs,
      mcp_extraction: $mcp_meta
    },
    validation: { errors: [], warnings: [] },
    stats: { scanned_files: $scanned, cache_hits: $hits, build_ms: $ms }
  }')

# ── Atomic write ─────────────────────────────────────────────────────────────
TMP="${OUTPUT}.tmp"
echo "$FINAL_GRAPH" > "$TMP"
jq empty "$TMP" || { echo "graph-builder: invalid JSON output — aborting" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$OUTPUT"

# ── Update hash cache ─────────────────────────────────────────────────────────
NEW_CACHE="$CURRENT_CACHE"
for f in "${ALL_CS[@]:-}" "${ALL_ASMDEF[@]:-}"; do
  [[ -z "$f" ]] && continue
  [[ -f "$f" ]] || continue
  h=$(hash_file "$f")
  NEW_CACHE=$(echo "$NEW_CACHE" | jq --arg k "$f" --arg v "$h" '.[$k] = $v')
done
CACHE_TMP="${CACHE_FILE}.tmp"
echo "$NEW_CACHE" > "$CACHE_TMP"
mv "$CACHE_TMP" "$CACHE_FILE"

# ── Touch .last-build ─────────────────────────────────────────────────────────
echo "$NOW" > "$LAST_BUILD"

# ── Summary ───────────────────────────────────────────────────────────────────
CLASS_COUNT=$(echo "$ALL_CLASSES" | jq 'length')
EVENT_COUNT=$(echo "$ALL_EVENTS" | jq 'length')
INST_COUNT=$(echo "$ALL_INSTALLERS" | jq 'length')
log "graph: ${CLASS_COUNT} classes, ${EVENT_COUNT} events, ${INST_COUNT} installers (${CACHE_HITS} cached, $((SCANNED - CACHE_HITS)) reparsed) in ${BUILD_MS}ms"
