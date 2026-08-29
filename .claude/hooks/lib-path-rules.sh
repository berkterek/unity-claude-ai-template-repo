#!/usr/bin/env bash
# ============================================================================
# lib-path-rules.sh — SINGLE SOURCE OF TRUTH for Unity script path rules.
#
# Sourced, never executed directly. Contains no exits, no hook plumbing, no
# stdin parsing — just one pure function so the SAME rule can be enforced from
# two places that fire at two different times:
#
#   1. .claude/hooks/check-domain-folder-structure.sh  — PreToolUse, at WRITE time
#   2. .claude/scripts/validate-plan-paths.sh          — preflight, at PLAN time
#
# Why both: a path violation is authored in tasks.md/design.md long before any
# file is written. A write-time hook cannot see it, and by the time the hook
# could fire, the plan has already been approved and the wrong tree is being
# built. Plan-time validation is the one that actually prevents the mistake;
# the write-time hook is the backstop.
#
# FAIL-CLOSED: an unrecognized first path segment is a VIOLATION, not a
# fall-through. The previous version of this rule exited 0 on anything outside
# Games/Abstracts|Concretes — and a plan recorded that silence as "verified
# compliant". Silence is not a pass. See unity_path_rules_summary().
#
# Escape hatch: .claude/path-allowlist.txt (see architecture.md → "Adding a
# top-level folder"). An entry there is a deliberate, greppable, reviewable
# exception — not a silent one.
# ============================================================================

# Folders legitimately allowed as the first segment under <root>/Scripts/
UNITY_ALLOWED_SCRIPTS_FOLDERS="Games Tests Editors"

# Folders legitimately allowed as the first segment under Scripts/Games/
UNITY_ALLOWED_GAMES_FOLDERS="Abstracts Concretes Ecs"

# unity_path_allowlist_file — resolves .claude/path-allowlist.txt
#
# CLAUDE_PROJECT_DIR first (same fix as _lib.sh's _resolve_state_dir, 2026-08-29):
# git rev-parse depends on cwd, and a subagent's tool-execution context is not
# guaranteed to run from the repo root. Falling through to "." there resolves
# the allowlist relative to whatever cwd the subagent happens to have, so a
# real, reviewed allowlist entry silently stops matching inside a subagent —
# check-domain-folder-structure.sh then blocks a path that plan/architecture.md
# already approved.
unity_path_allowlist_file() {
    local root
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.claude" ]; then
        root="$CLAUDE_PROJECT_DIR"
    else
        root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
    fi
    echo "$root/.claude/path-allowlist.txt"
}

# unity_path_is_allowlisted <relative-path-prefix>
# Matches a line in path-allowlist.txt of the form:
#   Scripts/Simulation    # reason: engine-free assembly boundary
# Comments (#...) and blank lines ignored. Exact match on the first field.
unity_path_is_allowlisted() {
    local needle="$1" file
    file="$(unity_path_allowlist_file)"
    [ -f "$file" ] || return 1
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [ -z "$line" ] && continue
        [ "$line" = "$needle" ] && return 0
    done < "$file"
    return 1
}

_unity_in_list() {
    local needle="$1" item
    shift
    for item in $1; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# unity_validate_script_path <path>
# Prints a violation message on stdout and returns 1 when the path breaks a
# rule. Returns 0 when the path is fine OR is out of scope for these rules.
# Never exits — the caller decides whether a violation blocks or warns.
unity_validate_script_path() {
    local p="$1"
    [ -z "$p" ] && return 0

    # ---- Rule A: first segment under Scripts/ ----
    local tail first
    case "$p" in
        */_GameFolders/Scripts/*) tail="${p#*/_GameFolders/Scripts/}" ;;
        _GameFolders/Scripts/*)   tail="${p#_GameFolders/Scripts/}" ;;
        */Assets/Scripts/*)       tail="${p#*/Assets/Scripts/}" ;;
        Assets/Scripts/*)         tail="${p#Assets/Scripts/}" ;;
        *)                        tail="" ;;
    esac

    if [ -n "$tail" ]; then
        first="${tail%%/*}"
        if [ "$first" = "$tail" ]; then
            echo "File directly under Scripts/: '$p'
Nothing may sit at the root of Scripts/. It belongs in one of:
  Scripts/Games/    — all game code
  Scripts/Tests/    — test assemblies
  Scripts/Editors/  — Editor-only tooling
Rule: rules/architecture.md -> Scripts/ Folder Rules"
            return 1
        fi
        if ! _unity_in_list "$first" "$UNITY_ALLOWED_SCRIPTS_FOLDERS" \
           && ! unity_path_is_allowlisted "Scripts/$first"; then
            echo "Illegal top-level folder: 'Scripts/$first/'  (path: $p)
The ONLY folders allowed directly under Scripts/ are: $UNITY_ALLOWED_SCRIPTS_FOLDERS
'$first' is not one of them, and is not in .claude/path-allowlist.txt.

If this folder exists for a real structural reason (most often: it needs its
OWN .asmdef because assembly flags like noEngineReferences are per-assembly and
therefore per-folder), that is a legitimate exception — but it must be DECLARED,
not invented silently:
  1. Add a line to .claude/path-allowlist.txt:
         Scripts/$first    # reason: <one line, e.g. engine-free simulation assembly>
  2. Add the folder to the table in rules/architecture.md -> Scripts/ Folder Rules
Otherwise move the code under Scripts/Games/<Domain>/.
Rule: rules/architecture.md -> Scripts/ Folder Rules
Kill switch: DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1"
            return 1
        fi

        # ---- Rule B: first segment under Scripts/Games/ ----
        if [ "$first" = "Games" ]; then
            local gtail gfirst
            gtail="${tail#Games/}"
            gfirst="${gtail%%/*}"
            if [ "$gfirst" != "$gtail" ] \
               && ! _unity_in_list "$gfirst" "$UNITY_ALLOWED_GAMES_FOLDERS" \
               && ! unity_path_is_allowlisted "Scripts/Games/$gfirst"; then
                echo "Illegal folder under Games/: 'Games/$gfirst/'  (path: $p)
The ONLY folders allowed directly under Scripts/Games/ are: $UNITY_ALLOWED_GAMES_FOLDERS
Interfaces -> Games/Abstracts/<Domain>/ , everything concrete -> Games/Concretes/<Domain>/.
Declare a real exception in .claude/path-allowlist.txt (see architecture.md).
Rule: rules/architecture.md -> Scripts/ Folder Rules"
                return 1
            fi
        fi
    fi

    # ---- Rule C: domain folder under Abstracts/ | Concretes/ (.cs only) ----
    case "$p" in *.cs) ;; *) return 0 ;; esac

    local side dtail dfirst
    case "$p" in
        *Games/Abstracts/*) side=Abstracts ;;
        *Games/Concretes/*) side=Concretes ;;
        *) return 0 ;;
    esac

    dtail="${p#*Games/$side/}"
    [ "$dtail" = "$p" ] && return 0    # prefix strip failed — refuse to guess
    dfirst="${dtail%%/*}"

    if [ "$dfirst" = "$dtail" ]; then
        echo "No domain folder: '$p'
.cs files may not sit directly under Games/$side/.
Put it in a domain folder: Games/$side/<Domain>/$dfirst
Plural for countable domains (Players/, Enemies/, Inputs/), singular for mass
nouns (Audio/, UI/, VFX/). DI and bootstrap wiring -> Concretes/Infrastructure/."
        return 1
    fi

    case "$(printf '%s' "$dfirst" | tr '[:upper:]' '[:lower:]')" in
        service|services|provider|providers|controller|controllers|view|views|\
manager|managers|interface|interfaces|config|configs)
            echo "Layer name in the domain position: 'Games/$side/$dfirst/'
The first folder under Games/$side/ must be a DOMAIN — Players/, Enemies/,
Inputs/, Audio/, UI/, VFX/, Infrastructure/ — never a layer.
Layer names are free BELOW the domain: Games/$side/<Domain>/$dfirst/ is legal.
Kill switch: DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1"
            return 1
            ;;
        core|general|generals)
            echo "Catch-all folder: 'Games/$side/$dfirst/'
'$dfirst' is not a domain — it is a name that cannot refuse a file, so everything
drains into it. (In the voxel-blast project, Core/ reached 85 files and 7692
lines spanning five unrelated concerns.)
Pick a real domain instead. For code that genuinely has no domain:
  _Framework/                  -> domain-agnostic infrastructure
  Concretes/Infrastructure/    -> DI, bootstrap, scope and config wiring
Kill switch: DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1"
            return 1
            ;;
    esac

    return 0
}

# unity_path_rules_summary — the POSITIVE receipt. Callers print this so that
# "no output" can never again be mistaken for "rule was checked".
unity_path_rules_summary() {
    # The receipt must name every rule ACTUALLY enforced, allowlist included. It used to
    # print only the static built-in list, so a repo with `Scripts/Simulation` declared in
    # path-allowlist.txt got a receipt claiming the first segment had to be one of
    # [Games Tests Editors] — while the validator was, correctly, also accepting Simulation.
    # CLAUDE.md makes this receipt the only thing that counts as evidence ("A silent hook is
    # NOT a compliance check … Only an explicit `checked: <rule>` receipt counts"), so a
    # receipt that understates the rule is worse than no receipt: it is wrong evidence,
    # presented as proof, in the one place a human is told to trust.
    local allowed_scripts="$UNITY_ALLOWED_SCRIPTS_FOLDERS"
    local allowed_games="$UNITY_ALLOWED_GAMES_FOLDERS"
    local file extra_scripts="" extra_games=""
    file="$(unity_path_allowlist_file)"
    if [ -n "$file" ] && [ -f "$file" ]; then
        # Same shape unity_path_is_allowlisted matches: "Scripts/<Folder>" / "Scripts/Games/<Folder>",
        # comments and blank lines ignored.
        extra_games=$(sed 's/#.*//' "$file" \
            | awk '{print $1}' \
            | sed -n 's|^Scripts/Games/\([A-Za-z0-9_.-]\{1,\}\)$|\1|p' \
            | sort -u | tr '\n' ' ')
        extra_scripts=$(sed 's/#.*//' "$file" \
            | awk '{print $1}' \
            | sed -n 's|^Scripts/\([A-Za-z0-9_.-]\{1,\}\)$|\1|p' \
            | sort -u | tr '\n' ' ')
    fi
    [ -n "${extra_scripts// /}" ] && allowed_scripts="$allowed_scripts + allowlist: ${extra_scripts% }"
    [ -n "${extra_games// /}" ]   && allowed_games="$allowed_games + allowlist: ${extra_games% }"
    echo "checked: Scripts/ first segment in [$allowed_scripts]; Games/ first segment in [$allowed_games]; Abstracts|Concretes domain-folder rule (rules/architecture.md)"
}
