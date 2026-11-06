#!/usr/bin/env bash
# graph-coverage-run.sh — measure graph coverage of a code-map against ANOTHER repo, read-only.
# Usage:
#   graph-coverage-run.sh <target-repo> <sha> <code-map> [out.json]
# Env: GATE_LOCATION / GATE_BEHAVIOUR (forwarded as gates), KEEP_TMP=1 (keep and print scratch dir).
# Exit: 0 ok · 1 gate missed (JSON still written) · 2 refused / bad input.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: graph-coverage-run.sh <target-repo> <sha> <code-map> [out.json]" >&2
  exit 2
fi

repo=$1 sha=$2 map=$3 out=${4:-/dev/stdout}
TPL=$(cd "$(dirname "$0")/../.." && pwd)

git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "refusing: $repo is not a git repo" >&2; exit 2; }
git -C "$repo" rev-parse --verify --quiet "$sha^{commit}" >/dev/null || { echo "refusing: sha $sha does not resolve in $repo" >&2; exit 2; }
[[ -f "$map" ]] || { echo "refusing: code-map $map not found" >&2; exit 2; }

repo_real=$(cd "$repo" && pwd -P)
# A symlinked output file would write through to its target — guard the resolved path, not the link.
out_resolved=$out
[[ -L "$out" ]] && out_resolved=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$out")
out_dir_real=$(cd "$(dirname "$out_resolved")" 2>/dev/null && pwd -P) || { echo "refusing: output directory missing" >&2; exit 2; }
if [[ "$out_dir_real" == "$repo_real" || "$out_dir_real" == "$repo_real"/* ]]; then
  echo "refusing: output inside target repo" >&2
  exit 2
fi
map_abs="$(cd "$(dirname "$map")" && pwd -P)/$(basename "$map")"

TMP=$(mktemp -d)
if [[ ${KEEP_TMP:-0} == 1 ]]; then
  echo "graph-coverage-run: TMP=$TMP" >&2
else
  trap 'rm -rf "$TMP"' EXIT
fi
mkdir -p "$TMP/src" "$TMP/out" "$TMP/tool"

uf=$(git -C "$repo" show "$sha:.claude/project-features.json" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("unity_project_folder") or ".")' 2>/dev/null || echo ".")
uf=${uf%/}
[[ -n "$uf" ]] || uf="."

roots=() code_roots=0
for cand in "$uf/Assets/_Framework" "$uf/Assets/_GameFolders/Scripts" ".claude/project-features.json"; do
  cand=${cand#./}
  if git -C "$repo" cat-file -e "$sha:$cand" 2>/dev/null; then
    roots+=("$cand")
    [[ "$cand" == *project-features.json ]] || code_roots=$((code_roots + 1))
  fi
done
if [[ $code_roots -eq 0 ]]; then
  echo "refusing: no code roots found at $sha in $repo (unity_project_folder=$uf)" >&2
  exit 2
fi

git -C "$repo" archive "$sha" -- "${roots[@]}" | tar -x -C "$TMP/src"
git -C "$TMP/src" init -q

cp -R "$TPL/.claude/graph/." "$TMP/tool/"
rm -rf "$TMP/tool/graph.json" "$TMP/tool/scenes.json" "$TMP/tool/prefabs.json" \
  "$TMP/tool/cache" "$TMP/tool/.last-build" "$TMP/tool/__pycache__"

(cd "$TMP/src" && python3 "$TMP/tool/graph-builder.py" --full --skip-mcp --quiet --output "$TMP/out/graph.json")

gate_args=()
[[ -z "${GATE_LOCATION:-}" ]] || gate_args+=(--gate-location "$GATE_LOCATION")
[[ -z "${GATE_BEHAVIOUR:-}" ]] || gate_args+=(--gate-behaviour "$GATE_BEHAVIOUR")

rc=0
python3 "$TMP/tool/graph_coverage.py" --code-map "$map_abs" --graph "$TMP/out/graph.json" --json \
  ${gate_args[@]+"${gate_args[@]}"} > "$TMP/out/coverage.json" || rc=$?
if [[ $rc -gt 1 ]]; then
  echo "graph-coverage-run: graph_coverage.py failed (exit $rc)" >&2
  exit "$rc"
fi

template_sha=$(git -C "$TPL" rev-parse --short HEAD)
python3 - "$TMP/out/coverage.json" "$TMP/out/graph.json" "$template_sha" "$sha" > "$TMP/out/final.json" <<'PY'
import json, os, sys
cov_path, graph_path, template_sha, target_sha = sys.argv[1:5]
with open(cov_path) as f:
    cov = json.load(f)
cov["graph_bytes"] = os.path.getsize(graph_path)
cov["template_sha"] = template_sha
cov["target_sha"] = target_sha
if "mode" not in cov:
    try:
        with open(graph_path) as f:
            cov["mode"] = (json.load(f).get("meta") or {}).get("mode", "unknown")
    except (OSError, ValueError):
        cov["mode"] = "unknown"
json.dump(cov, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
cat "$TMP/out/final.json" > "$out"
exit "$rc"
