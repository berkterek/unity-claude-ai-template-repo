#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    REPO="$(pwd)"
    HOOK="$REPO/.claude/hooks/check-playtest-drift.sh"
    GEN="$REPO/.claude/scripts/generate-playtest-commands.py"
    PROJ="$(mktemp -d)"
    SCRIPTS="$PROJ/Assets/_GameFolders/Scripts/Games/Concretes"
    mkdir -p "$SCRIPTS/Levels" "$SCRIPTS/Infrastructure" "$PROJ/docs"

    cat > "$SCRIPTS/Levels/LevelDebugCommands.cs" <<'EOF'
#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System.ComponentModel;
namespace Game.Concretes.Levels
{
    public sealed class LevelDebugCommands : IInitializable, IDisposable
    {
        [Category("Level")]
        public int TargetLevel { get; set; }

        public int CurrentLevel => _levelService.CurrentLevel;

        /// <summary>
        /// Jumps to the target level
        /// </summary>
        [Category("Level")]
        public void GoToLevel() { _levelService.SetLevel(TargetLevel); }

        public void Initialize() { _registry.Register(this); }

        public void Dispose() { _registry.Unregister(this); }

        private void Helper() { }
    }
}
#endif
EOF
    cat > "$SCRIPTS/Levels/LevelModule.cs" <<'EOF'
public static class LevelModule
{
    public static void Install(IContainerBuilder builder)
    {
        builder.Register<LevelDebugCommands>(Lifetime.Scoped).AsImplementedInterfaces();
    }
}
EOF
    cat > "$SCRIPTS/Infrastructure/SceneModules.cs" <<'EOF'
public static class SceneModules
{
    public static void InstallGame(IContainerBuilder builder) { LevelModule.Install(builder); }
}
EOF
    printf '# Playtest\n\n## Debug commands\n\n<!-- debug-commands:begin -->\n<!-- debug-commands:end -->\n\n## Rules\n' > "$PROJ/docs/PLAYTEST.md"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$PROJ"
}

gen() {
    run bash -c "cd '$PROJ' && python3 -I '$GEN' $*"
}

run_hook() {
    jq -n --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' > "$PROJ/in.json"
    run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK' < '$PROJ/in.json'"
}

# --- generator ---

@test "generator writes the command row with scope, parameters and description" {
    gen
    [ "$status" -eq 0 ]
    grep -qF '| Command | Scope | Parameters | Description |' "$PROJ/docs/PLAYTEST.md"
    grep -qF '| Level.GoToLevel | Scene | TargetLevel:int | Jumps to the target level |' "$PROJ/docs/PLAYTEST.md"
}

@test "generator lists neither lifecycle methods nor private helpers nor values as commands" {
    gen
    [ "$status" -eq 0 ]
    [ "$(grep -c '^| Level\.' "$PROJ/docs/PLAYTEST.md")" -eq 1 ]
}

@test "generator follows the registry's member rules" {
    cat > "$SCRIPTS/Levels/EconomyDebugCommands.cs" <<'EOF'
#if UNITY_EDITOR || DEVELOPMENT_BUILD
public sealed class EconomyDebugCommands : BaseCommands
{
    [Category("Gold")] public int Amount { get; set; }
    public int Total { get; private set; }
    [Category("Gold")] public void AddGold() { }
    public void Start() { }
    public override void Refresh() { }
    [Browsable(false)] public void Hidden() { }
    [Browsable(false)] public int Secret { get; set; }
    public static void NotInstance() { }
}
#endif
EOF
    gen
    [ "$status" -eq 0 ]
    grep -qF '| Economy.AddGold | unknown | Amount:int | — |' "$PROJ/docs/PLAYTEST.md"
    grep -qF '| Economy.Start |' "$PROJ/docs/PLAYTEST.md"
    grep -qF '| Economy.Refresh |' "$PROJ/docs/PLAYTEST.md"
    [ "$(grep -c '^| Economy\.' "$PROJ/docs/PLAYTEST.md")" -eq 3 ]
}

@test "generator keeps the hand-written parts of the doc" {
    gen
    [ "$status" -eq 0 ]
    grep -qF '| Command |' "$PROJ/docs/PLAYTEST.md"
    grep -qF '## Rules' "$PROJ/docs/PLAYTEST.md"
    grep -qF '# Playtest' "$PROJ/docs/PLAYTEST.md"
}

@test "--check exits 1 before generation and 0 after" {
    gen --check
    [ "$status" -eq 1 ]
    gen
    gen --check
    [ "$status" -eq 0 ]
}

@test "app scope when the module is installed from AppModules" {
    rm "$SCRIPTS/Infrastructure/SceneModules.cs"
    printf 'public static class AppModules { public static void Install(IContainerBuilder b) { LevelModule.Install(b); } }\n' > "$SCRIPTS/Infrastructure/AppModules.cs"
    gen
    grep -qF '| Level.GoToLevel | App |' "$PROJ/docs/PLAYTEST.md"
}

@test "unresolved registration gives unknown scope, a warning, exit 0" {
    rm "$SCRIPTS/Infrastructure/SceneModules.cs"
    gen
    [ "$status" -eq 0 ]
    grep -qF '| Level.GoToLevel | unknown |' "$PROJ/docs/PLAYTEST.md"
    [[ "$output" == *"unknown scope"* ]]
}

@test "missing markers exit 2" {
    printf '# Playtest\n' > "$PROJ/docs/PLAYTEST.md"
    gen
    [ "$status" -eq 2 ]
    [[ "$output" == *"debug-commands:begin"* ]]
}

# --- drift hook ---

@test "drift hook warns with the regenerate command on a stale doc, exit 0" {
    run_hook "$SCRIPTS/Levels/LevelDebugCommands.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"generate-playtest-commands.py"* ]]
}

@test "drift hook is silent when the doc is current" {
    gen
    run_hook "$SCRIPTS/Levels/LevelDebugCommands.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "drift hook ignores other files" {
    run_hook "$SCRIPTS/Levels/LevelService.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
