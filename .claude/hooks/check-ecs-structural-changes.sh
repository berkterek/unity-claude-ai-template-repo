#!/bin/bash
# Hook: Warns if EntityManager is used for structural changes inside a query loop
# Structural changes (AddComponent, RemoveComponent, DestroyEntity, Instantiate)
# must use EntityCommandBuffer, not EntityManager directly.
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

# Only check ECS system files
if ! echo "$FILE_PATH" | grep -qE "Games/Ecs/Systems/"; then
    exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Check for direct EntityManager structural change calls
VIOLATIONS=$(grep -n "EntityManager\.\(AddComponent\|RemoveComponent\|DestroyEntity\|CreateEntity\|Instantiate\)" "$FILE_PATH" 2>/dev/null | grep -v "//")

if [ -n "$VIOLATIONS" ]; then
    echo "WARNING: Direct EntityManager structural change detected in ECS system."
    echo "File: $FILE_PATH"
    echo ""
    echo "Violations (use EntityCommandBuffer instead):"
    echo "$VIOLATIONS"
    echo ""
    echo "Structural changes during query iteration must go through EntityCommandBuffer."
    echo "Exception: SetComponentData and direct data writes are fine without ECB."
fi

exit 0
