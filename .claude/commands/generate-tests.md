# Generate Tests — Missing Test Writer

You write missing tests for existing classes. You do not change the class under test — only create or extend the test file.

## Initialization

Ask:
1. Which class needs tests? (file path or class name)
2. Are there existing tests to extend, or starting from scratch?

Then read the target class fully before writing any tests.

## Preflight — Test Type Decision (MANDATORY, run first)

Read `.claude/skills/core/test-type-router.md` and apply the decision matrix to the target class.

Emit the decision block:
```
TEST TYPE DECISION
  Target:   [class name or file path]
  Decision: [EditMode | PlayMode-ECS | PlayMode-Scene | NoTest]
  Reason:   [one sentence]
```

- **NoTest** → stop:
  > "This class does not require tests (data struct, authoring baker, thin view adapter, or config SO). No test file will be created."
- **PlayMode-Scene** → stop:
  > "This class requires a Play Mode scene test. Run `/create-test [FeatureName]` to scaffold the scene, TestBootstrap, and test stub."
- **PlayMode-ECS** → continue; write an isolated World test in `[ProjectName]PlayModeTest` assembly (not a scene test)
- **EditMode** → continue normally with NUnit + NSubstitute

---

## Preflight — Assembly & NSubstitute Check (MANDATORY)

Before writing any test code, verify the test infrastructure exists:

1. **Find the test assembly** — look for `*Tests.asmdef` under `_GameFolders/Scripts/Tests/`. If none exists, stop and tell the user:
   > "No test assembly found. Run `/setup-project` or manually create the test assembly before generating tests."

2. **Check game assembly reference** — open the test `.asmdef` and confirm the target class's assembly is listed in `references`. If missing, add it before proceeding.

3. **Check NSubstitute** — confirm the test `.asmdef` has:
   - `"overrideReferences": true`
   - `"NSubstitute.dll"` in `precompiledReferences`
   - `Assets/_GameFolders/Plugins/NSubstitute/NSubstitute.dll` exists on disk

   If `overrideReferences` is false or `NSubstitute.dll` is missing from `precompiledReferences`, fix the `.asmdef` before writing tests. If the DLL is missing from disk, stop and tell the user:
   > "NSubstitute.dll not found at Assets/_GameFolders/Plugins/NSubstitute/. Download it from https://github.com/nsubstitute/NSubstitute/releases and place it there."

4. **Trigger Unity compile** — use `mcp__unityMCP__refresh_unity` and wait for `isCompiling` to be false. Check for errors with `mcp__unityMCP__read_console` type "Error". If there are existing compile errors unrelated to your changes, stop and report them to the user first.

Only proceed to write tests after all preflight checks pass.

## What You Generate

For every `public` method and every meaningful `private` method that contains logic:

- At least one happy path test
- At least one edge case (null input, zero, empty collection, boundary value)
- At least one failure case if the method can throw or return error state

## Test Structure Rules

**File location:** `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/[ClassName]Tests.cs`

**Naming:** `MethodName_WhenCondition_ExpectedBehavior`

**Pattern:** Always AAA with explicit comments:

```csharp
[Test]
public void TakeDamage_WhenDamageExceedsHealth_SetsHealthToZero()
{
    // Arrange
    var eventBus = Substitute.For<IEventBus>();
    var sut = new EnemyService(health: 10, eventBus);

    // Act
    sut.TakeDamage(999);

    // Assert
    Assert.AreEqual(0, sut.Health);
}
```

**Mocking rules:**
- Only mock interfaces (`Substitute.For<IInterface>()`)
- Never mock concrete classes
- Inject mocks via constructor

## Output Format

1. List every public method you found in the class
2. For each method, list the test cases you will write
3. Write the complete test file
4. Note any methods that are untestable without Play Mode (MonoBehaviour lifecycle, ECS) — flag them but do not write broken tests
