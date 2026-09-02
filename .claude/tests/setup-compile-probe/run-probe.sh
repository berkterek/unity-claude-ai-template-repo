#!/usr/bin/env bash
#
# setup-compile-probe — does the project /setup-project generates actually COMPILE?
#
# Fifth test layer in this repo and the second deterministic one (see README.md).
# No model in the loop: it extracts the Step 3 / Step 4 blocks from the command file,
# builds a throwaway Unity project around them, and runs a real `Unity -batchmode`.
#
# Exit codes:  0 = compiled clean   2 = compile errors   1 = harness could not run
#
# The extraction deliberately reuses `.claude/scripts/validate-generated-asmdefs.py --extract`,
# so the probe compiles exactly the files that validator reasons about. Two parsers would
# eventually disagree, and the disagreement would show up as a green probe over an unchecked file.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SOURCE_MD="$REPO/.claude/commands/setup-project.md"
EXTRACTOR="$REPO/.claude/scripts/validate-generated-asmdefs.py"

UNITY_BIN=""
KEEP=0
PROJECT_NAME="Probe"
# Pinned on purpose: a version bump is a deliberate edit, never an ambient one.
PINNED_UNITY="6000.2.6f2"

usage() {
    cat <<EOF
setup-compile-probe — compiles the project /setup-project would generate.

  run-probe.sh [--unity PATH] [--keep] [--name NAME] [--help]

  --unity PATH   Unity executable. Default: the pinned $PINNED_UNITY under
                 /Applications/Unity/Hub/Editor/, else the newest installed Editor.
  --keep         Leave the temp project on disk and print its path.
  --name NAME    Substituted for [ProjectName] in asmdef names. Default: $PROJECT_NAME.

Covers Step 3 (asmdefs) + Step 4 (framework C#) at the template's DEFAULT feature set.
Excluded, and why: Games/Ecs/ needs Unity.Entities (ecs is disabled by default) and
Scripts/Tests/ needs an NSubstitute DLL that no clone has (Gate B). Neither exclusion is
a judgement that those paths are fine — they are simply not what this probe measures.

A green run means it compiles. It does NOT mean setup works: PlayMode, scene wiring and
prefab authoring are covered by nothing here.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --unity) UNITY_BIN="$2"; shift 2 ;;
        --keep)  KEEP=1; shift ;;
        --name)  PROJECT_NAME="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

fail_harness() { echo "HARNESS FAIL — $1" >&2; exit 1; }

# --- locate Unity -------------------------------------------------------------
if [ -z "$UNITY_BIN" ]; then
    HUB="/Applications/Unity/Hub/Editor"
    CAND="$HUB/$PINNED_UNITY/Unity.app/Contents/MacOS/Unity"
    if [ -x "$CAND" ]; then
        UNITY_BIN="$CAND"
    else
        NEWEST=$(find "$HUB" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)
        [ -n "$NEWEST" ] && UNITY_BIN="$NEWEST/Unity.app/Contents/MacOS/Unity"
        [ -x "${UNITY_BIN:-}" ] && echo "NOTE: pinned $PINNED_UNITY not installed; using $(basename "$NEWEST")"
    fi
fi
[ -x "${UNITY_BIN:-}" ] || fail_harness "no Unity executable found. Pass --unity PATH."

[ -f "$SOURCE_MD" ]  || fail_harness "missing $SOURCE_MD"
[ -f "$EXTRACTOR" ]  || fail_harness "missing $EXTRACTOR"

PROJ=$(mktemp -d -t setup-probe)
cleanup() { [ "$KEEP" -eq 1 ] && echo "kept: $PROJ" || rm -rf "$PROJ"; }
trap cleanup EXIT

echo "[1/5] temp project: $PROJ"

# --- 1. materialise the generated files ---------------------------------------
FILES=$(python3 "$EXTRACTOR" --extract "$PROJ/Assets" --project-name "$PROJECT_NAME" \
            --skip "/Ecs/" --skip "/Tests/" "$SOURCE_MD") \
    || fail_harness "extraction failed"
COUNT=$(printf '%s\n' "$FILES" | grep -c . || true)
[ "$COUNT" -gt 0 ] || fail_harness "extracted 0 files — that is a failure, not a pass"
ASM=$(printf '%s\n' "$FILES" | grep -c '\.asmdef$' || true)
CS=$(printf '%s\n' "$FILES" | grep -c '\.cs$' || true)
echo "[2/5] extracted $COUNT files from setup-project.md ($ASM asmdef, $CS cs)"

# --- 2. packages ---------------------------------------------------------------
# VContainer and UniTask are not on the Unity registry; they come from OpenUPM.
mkdir -p "$PROJ/Packages"
cat > "$PROJ/Packages/manifest.json" <<EOF
{
  "dependencies": {
    "com.unity.inputsystem": "1.11.2",
    "com.unity.nuget.newtonsoft-json": "3.2.1",
    "jp.hadashikick.vcontainer": "1.16.9",
    "com.cysharp.unitask": "2.5.10"
  },
  "scopedRegistries": [
    {
      "name": "OpenUPM",
      "url": "https://package.openupm.com",
      "scopes": ["jp.hadashikick", "com.cysharp"]
    }
  ]
}
EOF
echo "[3/5] manifest written: inputsystem, newtonsoft, vcontainer, unitask"

# --- 3. compile ----------------------------------------------------------------
LOG="$PROJ/unity.log"
echo "[4/5] $("$UNITY_BIN" -version 2>/dev/null || basename "$(dirname "$(dirname "$(dirname "$UNITY_BIN")")")") -batchmode — this takes minutes"
START=$(date +%s)
"$UNITY_BIN" -batchmode -nographics -quit \
    -projectPath "$PROJ" \
    -logFile "$LOG" >/dev/null 2>&1
UNITY_CODE=$?
ELAPSED=$(( $(date +%s) - START ))

[ -f "$LOG" ] || fail_harness "Unity produced no log (exit $UNITY_CODE) — licence or install problem"

# --- 4. verdict ------------------------------------------------------------------
echo "[5/5] scanning log (${ELAPSED}s, unity exit $UNITY_CODE)"

ERRORS=$(grep -E "error CS[0-9]+" "$LOG" | sort -u || true)
NERR=$(printf '%s\n' "$ERRORS" | grep -c . || true)

# A licence/package failure must never be reported as "compiled clean".
if [ "$NERR" -eq 0 ] && [ "$UNITY_CODE" -ne 0 ]; then
    echo
    echo "HARNESS FAIL — Unity exited $UNITY_CODE with no compile errors in the log." >&2
    echo "Usually a licence or package-resolution failure, not a code problem. Last lines:" >&2
    tail -25 "$LOG" >&2
    KEEP=1
    exit 1
fi

if [ "$NERR" -gt 0 ]; then
    echo
    echo "  compile errors: $NERR"
    echo
    printf '%s\n' "$ERRORS" | sed 's/^/  /'
    echo
    echo "FAIL — the generated project does not compile."
    KEEP=1
    echo "log: $LOG"
    exit 2
fi

BUILT=$(grep -oE "Finished compiling graph: Assets/[^ ]*" "$LOG" | sed 's|.*/||' | sort -u | tr '\n' ' ')
echo
echo "  compile errors: 0"
[ -n "$BUILT" ] && echo "  compiled: $BUILT"
echo
echo "PASS — the generated project compiles."
echo "       (compiles != works: PlayMode, scene wiring and prefab authoring are not covered)"
exit 0
