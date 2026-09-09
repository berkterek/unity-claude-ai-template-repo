#!/usr/bin/env bats
#
# Pins the eleven cases that shaped check-duplicate-siblings.py.
#
# Three of them exist because the script FAILED them on measurement, and all three
# failures were false positives — the expensive kind, because a noisy gate gets
# ignored and then stops protecting anything:
#
#   "different project scripts"  m_EditorClassIdentifier is populated only for
#                                scripts in a package assembly. The project's own
#                                scripts carry an empty one, so every MonoBehaviour
#                                collapsed to "114:" and two siblings holding
#                                DIFFERENT scripts compared equal. Invisible in a
#                                run whose hits are package components (TMP, Image)
#                                — which is exactly how it survived its first run.
#
#   "empty grouping nodes"       the organizer exclusion covered Transform (class 4)
#                                but not RectTransform (224), so two empty UI
#                                grouping nodes read as a duplicate.
#
#   "nested prefab instances"    a nested instance serializes as *stripped* blocks
#                                with no m_Name and no components, so two of them
#                                shared the signature (parent, ()) and reported
#                                ['?', '?']. Measured 2026-09-10 on a real
#                                CanvasHUD.prefab whose two source GUIDs differed —
#                                and the verdict is backwards even when they match,
#                                because repeated instances under a layout parent
#                                are what Card 5 PRESCRIBES.
#
# The rest pin behaviour that must not regress: a real duplicate is caught,
# Unity's own Cmd+D naming is caught (the name-based grep this script replaced was
# blind to it), scene containers are never flagged, and "same components" alone is
# not enough without "same parent".

setup() {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    SCRIPT=".claude/scripts/check-duplicate-siblings.py"
    TMPDIR_TEST="$(mktemp -d)"
    FIXTURE="$TMPDIR_TEST/Case.prefab"
    # Without the YAML header the first document is not split off, so the first
    # GameObject is silently dropped and a two-sibling case can never form a group.
    # Every fixture must start with it or the test passes vacuously.
    HDR=$'%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n'
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

# $1 fileID, $2 name, $3.. component fileIDs
go() {
    local id="$1" name="$2"; shift 2
    printf -- '--- !u!1 &%s\nGameObject:\n  m_Name: %s\n  m_Component:\n' "$id" "$name"
    local c; for c in "$@"; do printf -- '  - component: {fileID: %s}\n' "$c"; done
}

# $1 fileID, $2 owning GameObject, $3 parent transform fileID
rect() {
    printf -- '--- !u!224 &%s\nRectTransform:\n  m_GameObject: {fileID: %s}\n  m_Father: {fileID: %s}\n' "$1" "$2" "$3"
}

transform() {
    printf -- '--- !u!4 &%s\nTransform:\n  m_GameObject: {fileID: %s}\n  m_Father: {fileID: %s}\n' "$1" "$2" "$3"
}

# $1 fileID, $2 owning GameObject, $3 script guid, $4 optional editor class identifier
mono() {
    printf -- '--- !u!114 &%s\nMonoBehaviour:\n  m_GameObject: {fileID: %s}\n  m_Script: {fileID: 11500000, guid: %s, type: 3}\n  m_EditorClassIdentifier: %s\n' "$1" "$2" "$3" "${4:-}"
}

# A nested prefab instance: Unity emits the instance's GameObject and Transform as
# *stripped* blocks — no m_Name, no component entries — plus a PrefabInstance (1001)
# holding the source GUID. This is the shape that produced ['?', '?'] and exit 1.
# $1 GameObject fileID, $2 Transform fileID, $3 parent transform fileID, $4 source GUID
nested_instance() {
    printf -- '--- !u!1 &%s stripped\nGameObject:\n  m_PrefabInstance: {fileID: 900%s}\n' "$1" "$1"
    printf -- '--- !u!4 &%s stripped\nTransform:\n  m_GameObject: {fileID: %s}\n  m_Father: {fileID: %s}\n  m_PrefabInstance: {fileID: 900%s}\n' "$2" "$1" "$3" "$1"
    printf -- '--- !u!1001 &900%s\nPrefabInstance:\n  m_Modification:\n    m_Modifications:\n    - target: {fileID: 0}\n      propertyPath: m_Name\n      value: Heart\n  m_SourcePrefab: {fileID: 100100000, guid: %s, type: 3}\n' "$1" "$4"
}

run_check() {
    run python3 "$SCRIPT" "$FIXTURE"
}

# --- must be caught ---

@test "catches a real duplicate: two siblings, same parent, same script" {
    { printf '%s' "$HDR"
      go 10 Heart1 11 12; rect 11 10 99; mono 12 10 aaaaaaaa
      go 20 Heart2 21 22; rect 21 20 99; mono 22 20 aaaaaaaa
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Heart1"* && "$output" == *"Heart2"* ]]
}

@test "catches Unity's own Cmd+D naming — 'Heart' and 'Heart (1)'" {
    # The m_Name grep this script replaced matched only names ending in a digit,
    # so it missed the most common way a duplicate is created at all.
    { printf '%s' "$HDR"
      go 10 Heart 11 12;        rect 11 10 99; mono 12 10 f70555f1
      go 20 "Heart (1)" 21 22;  rect 21 20 99; mono 22 20 f70555f1
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Heart (1)"* ]]
}

# --- must NOT be caught ---

@test "does not flag two siblings holding different project scripts" {
    # Both carry an EMPTY m_EditorClassIdentifier, as every Assembly-CSharp script
    # does. Keying identity on that field alone made these compare equal.
    { printf '%s' "$HDR"
      go 10 HealthBar   11 12; rect 11 10 99; mono 12 10 aaaaaaaa
      go 20 AmmoCounter 21 22; rect 21 20 99; mono 22 20 bbbbbbbb
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
}

@test "does not flag empty RectTransform grouping nodes" {
    # An object whose only component is a transform has nothing to extract, so it
    # can never be the subject of Card 5 — Header/Footer, Left/Right and friends.
    { printf '%s' "$HDR"
      go 10 LeftGroup  11; rect 11 10 99
      go 20 RightGroup 21; rect 21 20 99
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
}

@test "does not flag the mandated scene containers" {
    # scene-hierarchy.md both requires these and forbids them from being prefabs,
    # so flagging them would be a permanent false positive in every scene.
    { printf '%s' "$HDR"
      go 10 "[Setup]" 11; transform 11 10 0
      go 20 "[UI]"    21; transform 21 20 0
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
}

@test "does not flag identical component sets under different parents" {
    # "Same component set" alone is not the test — condition 1 is same parent.
    { printf '%s' "$HDR"
      go 10 Slot 11 12; rect 11 10 98; mono 12 10 f70555f1
      go 20 Slot 21 22; rect 21 20 99; mono 22 20 f70555f1
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
}

# --- the silence-is-not-a-pass rule ---

@test "an empty scan reports NOT A PASS and exits non-zero" {
    # The grep this replaced returned nothing when pointed at the wrong path, and
    # nothing reads as success. Same failure shape as validate-plan-facts.sh's
    # 'NO TASKS FOUND is not a pass'.
    run python3 "$SCRIPT" "$TMPDIR_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOT a pass"* ]]
}

@test "a clean file reports zero groups and exits 0" {
    { printf '%s' "$HDR"
      go 10 Player 11 12; rect 11 10 99; mono 12 10 aaaaaaaa
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"duplicate sibling groups: 0"* ]]
}

# --- nested prefab instances: the third false positive (measured 2026-09-10) ---

@test "two nested prefab instances under one parent are NOT a duplicate hit" {
    # CanvasHUD.prefab reported ['?', '?'] with an empty component list and exited 1.
    # Stripped blocks carry no components, so Card 5's second condition is unmet --
    # a vacuum, not a match. Here the two source GUIDs even differ.
    { printf '%s' "$HDR"
      nested_instance 10 11 99 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      nested_instance 20 21 99 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" != *"['?', '?']"* ]]
    [[ "$output" == *"duplicate sibling groups: 0"* ]]
}

@test "the skip is reported, never silent" {
    # A checker that declines to look must say so -- otherwise 'groups: 0' reads as
    # 'inspected and clean' for objects it never inspected.
    { printf '%s' "$HDR"
      nested_instance 10 11 99 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      nested_instance 20 21 99 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"nested prefab instances skipped: 2"* ]]
    [[ "$output" == *"NOT inspected"* ]]
}

@test "a real duplicate is still caught alongside nested instances in the same file" {
    # Regression guard: the exemption must not swallow inline siblings that sit in
    # the same parent as a nested instance.
    { printf '%s' "$HDR"
      nested_instance 10 11 99 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      go 30 Pip1 31 32; rect 31 30 99; mono 32 30 cccccccc
      go 40 Pip2 41 42; rect 41 40 99; mono 42 40 cccccccc
    } > "$FIXTURE"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Pip1"* && "$output" == *"Pip2"* ]]
    [[ "$output" == *"nested prefab instances skipped: 1"* ]]
}
