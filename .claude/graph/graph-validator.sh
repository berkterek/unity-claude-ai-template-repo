#!/usr/bin/env bash
# graph-validator.sh — Check graph.json against architecture invariants (R1–R6).
# Exit 0 if only warnings; exit 1 if any error.
# Usage:
#   graph-validator.sh [path/to/graph.json]
set -euo pipefail

GRAPH="${1:-.claude/graph/graph.json}"

if [[ ! -f "$GRAPH" ]]; then
  echo "graph-validator: $GRAPH not found — skipping (run /build-knowledge-graph first)" >&2
  exit 0
fi

# Validate JSON
jq empty "$GRAPH" 2>/dev/null || { echo "graph-validator: $GRAPH is not valid JSON" >&2; exit 1; }

ERRORS="[]"
WARNINGS="[]"

add_error() {
  local rule_id="$1" file="${2:-}" line="${3:-0}" message="$4"
  local entry
  entry=$(jq -nc --arg r "$rule_id" --arg f "$file" --argjson l "$line" --arg m "$message" \
    '{"rule_id":$r,"file":$f,"line":$l,"message":$m,"severity":"error"}')
  ERRORS=$(echo "$ERRORS" | jq ". + [$entry]")
}

add_warning() {
  local rule_id="$1" file="${2:-}" line="${3:-0}" message="$4"
  local entry
  entry=$(jq -nc --arg r "$rule_id" --arg f "$file" --argjson l "$line" --arg m "$message" \
    '{"rule_id":$r,"file":$f,"line":$l,"message":$m,"severity":"warning"}')
  WARNINGS=$(echo "$WARNINGS" | jq ". + [$entry]")
}

# ── R1: No singletons ─────────────────────────────────────────────────────────
# Fail if any class has has_static_instance: true
while IFS= read -r row; do
  name=$(echo "$row" | jq -r '.name')
  file=$(echo "$row" | jq -r '.file')
  add_error "SINGLETON_DETECTED" "$file" 0 \
    "Class '$name' has a static singleton (Instance/Current/Shared/Main/Default). Use VContainer instead."
done < <(jq -c '.codebase.classes[] | select(.has_static_instance == true)' "$GRAPH" 2>/dev/null || true)

# ── R2: Every event has at least one publisher AND one subscriber ──────────────
while IFS= read -r row; do
  name=$(echo "$row" | jq -r '.name')
  file=$(echo "$row" | jq -r '.file')
  pub_count=$(echo "$row" | jq '.publishers | length')
  sub_count=$(echo "$row" | jq '.subscribers | length')
  if [[ "$pub_count" -eq 0 && "$sub_count" -eq 0 ]]; then
    add_warning "EVENT_DANGLING" "$file" 0 "Event '$name' has no publisher and no subscriber."
  elif [[ "$pub_count" -eq 0 ]]; then
    add_warning "EVENT_DANGLING" "$file" 0 "Event '$name' has subscriber(s) but no publisher."
  elif [[ "$sub_count" -eq 0 ]]; then
    add_warning "EVENT_DANGLING" "$file" 0 "Event '$name' has publisher(s) but no subscriber."
  fi
done < <(jq -c '.codebase.events[]' "$GRAPH" 2>/dev/null || true)

# ── R3: Every concrete in Games/Concretes/ is registered in at least one installer ──
declare -a REGISTERED_TYPES=()
while IFS= read -r t; do
  REGISTERED_TYPES+=("$t")
done < <(jq -r '.codebase.vcontainer.installers[].registrations[].type // empty' "$GRAPH" 2>/dev/null || true)

if [[ ${#REGISTERED_TYPES[@]} -gt 0 ]]; then
  REGISTERED_JSON=$(printf '%s\n' "${REGISTERED_TYPES[@]}" | jq -R . | jq -sc . 2>/dev/null || echo "[]")
else
  REGISTERED_JSON="[]"
fi

while IFS= read -r row; do
  name=$(echo "$row" | jq -r '.name')
  file=$(echo "$row" | jq -r '.file')
  is_mono=$(echo "$row" | jq -r '.is_mono_behaviour')
  # Skip MonoBehaviours (registered via RegisterComponentInHierarchy, not installers)
  [[ "$is_mono" == "true" ]] && continue
  # Skip Installer classes themselves
  [[ "$name" == *Installer ]] && continue
  # Skip SO configs
  [[ "$file" == *Configuration* ]] && continue
  # Skip LifetimeScope subclasses (bootstrapped by Unity, not VContainer-registered)
  base_types=$(echo "$row" | jq -r '.base_types[]? // empty')
  echo "$base_types" | grep -qE '(^|\.)(LifetimeScope|ScriptableObject)$' && continue

  if ! echo "$REGISTERED_JSON" | jq -e --arg n "$name" '. | index($n) != null' >/dev/null 2>&1; then
    add_warning "CONCRETE_UNREGISTERED" "$file" 0 \
      "Class '$name' in Games/Concretes/ is not registered in any VContainer installer."
  fi
done < <(jq -c '.codebase.classes[] | select(.file | contains("/Games/Concretes/"))' "$GRAPH" 2>/dev/null || true)

# ── R4: No interface outside _Framework/ or Games/Abstracts/ ─────────────────
while IFS= read -r row; do
  name=$(echo "$row" | jq -r '.name')
  file=$(echo "$row" | jq -r '.file')
  add_error "INTERFACE_MISPLACED" "$file" 0 \
    "Interface '$name' must live in _Framework/ or Games/Abstracts/ — found in '$file'."
done < <(jq -c '.codebase.interfaces[] | select(.file | (contains("_Framework") or contains("Games/Abstracts")) | not)' "$GRAPH" 2>/dev/null || true)

# ── R5: Every asmdef reference must be a known asmdef name ───────────────────
KNOWN_ASMDEFS=$(jq -r '[.codebase.assemblies[].name]' "$GRAPH" 2>/dev/null || echo "[]")

while IFS= read -r row; do
  asmname=$(echo "$row" | jq -r '.name')
  asmfile=$(echo "$row" | jq -r '.file')
  # Skip third-party assemblies in _AssetFolders/ or Plugins/
  [[ "$asmfile" == */_AssetFolders/* || "$asmfile" == */Plugins/* || \
     "$asmfile" == */_assetfolders/* || "$asmfile" == */plugins/* ]] && continue
  while IFS= read -r ref; do
    # Built-in Unity assemblies are always valid — skip
    [[ "$ref" == UnityEngine* || "$ref" == UnityEditor* || "$ref" == Unity.* ]] && continue
    # Skip GUID-based references (UPM/built-in packages not in graph)
    [[ "$ref" == GUID:* ]] && continue
    if ! echo "$KNOWN_ASMDEFS" | jq -e --arg r "$ref" '. | index($r) != null' >/dev/null 2>&1; then
      add_error "ASMDEF_UNRESOLVED" "$asmfile" 0 \
        "Assembly '$asmname' references unknown assembly '$ref'."
    fi
  done < <(echo "$row" | jq -r '.references[]? // empty')
done < <(jq -c '.codebase.assemblies[]' "$GRAPH" 2>/dev/null || true)

# ── R6: No _Framework/ asmdef references a Games/ asmdef ────────────────────
# Build name→file map for all known assemblies
ASMDEF_FILE_MAP=$(jq -r '.codebase.assemblies[] | "\(.name)\t\(.file)"' "$GRAPH" 2>/dev/null || true)

while IFS= read -r row; do
  asmname=$(echo "$row" | jq -r '.name')
  asmfile=$(echo "$row" | jq -r '.file')
  while IFS= read -r ref; do
    # Resolve referenced assembly's file path from the name→file map
    ref_file=$(awk -F'\t' -v r="$ref" '$1==r{print $2; exit}' <<< "$ASMDEF_FILE_MAP") || ref_file=""
    if echo "$ref_file" | grep -qE 'Games|GameFolders'; then
      add_error "LAYER_VIOLATION" "$asmfile" 0 \
        "_Framework assembly '$asmname' references Games assembly '$ref' — forbidden (dependency direction violation)."
    fi
  done < <(echo "$row" | jq -r '.references[]? // empty')
done < <(jq -c '.codebase.assemblies[] | select(.file | contains("_Framework"))' "$GRAPH" 2>/dev/null || true)

# ── Merge findings back into graph.json ──────────────────────────────────────
TMP="${GRAPH}.tmp"
jq \
  --argjson errors "$ERRORS" \
  --argjson warnings "$WARNINGS" \
  '.validation.errors = $errors | .validation.warnings = $warnings' \
  "$GRAPH" > "$TMP"
mv "$TMP" "$GRAPH"

# ── Report ───────────────────────────────────────────────────────────────────
ERROR_COUNT=$(echo "$ERRORS" | jq 'length')
WARN_COUNT=$(echo "$WARNINGS" | jq 'length')
echo "graph-validator: ${ERROR_COUNT} error(s), ${WARN_COUNT} warning(s)" >&2

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  echo "$ERRORS" | jq -r '.[] | "  [\(.severity | ascii_upcase)] \(.rule_id) \(.file): \(.message)"' >&2
  exit 1
fi

if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "$WARNINGS" | jq -r '.[] | "  [WARN] \(.rule_id) \(.file): \(.message)"' >&2
fi

exit 0
