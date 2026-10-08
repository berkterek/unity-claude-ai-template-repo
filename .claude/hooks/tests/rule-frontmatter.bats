#!/usr/bin/env bats
# Pins which rules are always loaded and which are path-scoped. A rule that loses
# its frontmatter loads into every session again; a core rule that gains one
# vanishes at plan time and after /compact.

setup() { cd "$BATS_TEST_DIRNAME/../../.." || exit 1; }

_globs() {  # print the quoted globs of a rule's paths: block, one per line
    awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} /^  - "/ {print}' ".claude/rules/$1.md" \
        | sed -E 's/^  - "(.*)"$/\1/'
}

@test "core rules have no frontmatter" {
    for r in architecture solid-oop csharp-unity bootstrap-pattern; do
        [ "$(head -1 .claude/rules/$r.md)" != "---" ] || { echo "core rule $r is scoped"; false; }
    done
}

@test "every non-core rule is path-scoped" {
    for f in .claude/rules/*.md; do
        r=$(basename "$f" .md)
        case "$r" in architecture|solid-oop|csharp-unity|bootstrap-pattern) continue ;; esac
        [ "$(head -1 "$f")" = "---" ] || { echo "$r has no frontmatter"; false; }
        [ -n "$(_globs "$r")" ] || { echo "$r has no quoted paths"; false; }
    done
}

@test "frontmatter uses only the paths key (any other key is silently ignored)" {
    for f in .claude/rules/*.md; do
        [ "$(head -1 "$f")" = "---" ] || continue
        bad=$(awk 'NR>1 && $0=="---" {exit} NR>1 && /^[a-z_]+:/ && !/^paths:/' "$f")
        [ -z "$bad" ] || { echo "$f: $bad"; false; }
    done
}

@test "C# layer rules trigger on .cs" {
    for r in event-patterns unity-async serialization unity-lifecycle logging save-load unity-input performance; do
        _globs "$r" | grep -qxF '**/*.cs' || { echo "$r missing **/*.cs"; false; }
    done
}

@test "domain rules carry their domain glob" {
    _globs testing | grep -qxF '**/Tests/**'
    _globs ui-toolkit-runtime | grep -qxF '**/*.{uxml,uss,tss}'
    _globs web-tool-architecture | grep -qxF 'tools/**'
    _globs unity-prefabs | grep -qxF '**/*.{prefab,unity}'
    _globs scene-hierarchy | grep -qxF '**/*.{prefab,unity}'
    _globs ecs-dots | grep -qxF '**/Ecs/**'
    _globs roadmap-milestones | grep -qxF 'docs/ROADMAP.md'
}

@test "every scoped rule is listed in the rule index" {
    for f in .claude/rules/*.md; do
        [ "$(head -1 "$f")" = "---" ] || continue
        r=$(basename "$f")
        grep -qF "$r" .claude/docs/rule-index.md || { echo "$r missing from rule-index.md"; false; }
    done
}
