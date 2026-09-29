# Editors

## Purpose
Holds framework tooling that exists only inside the Unity Editor, including the permanent
applier that writes serialized properties from a versioned JSON manifest.

## Boundary
Never referenced from a runtime assembly, in either direction — this assembly is restricted
to the Editor platform, so a runtime reference to it does not fail at review, it fails at
build time, on the build machine, long after the change was made. Nothing here knows any
game type: the applier speaks serialized-property paths and component type names supplied by
its caller, which is what lets it ship from a template at all.

## How to extend
Add the tool here and keep it self-contained. Editor code that needs to read runtime types
references the runtime assembly, never the reverse. Runtime code that needs an Editor-only
branch guards it with the Editor compilation symbol in place, instead of moving the file.
A new manifest operation is a new case in the applier's dispatch plus a matching read-back
branch — never one without the other. A new kind of caller gets a new menu entry, not new
logic in the applier: the file-reading shell and the pure string-to-result core stay split,
because that split is the only reason the core is testable without driving the menu system.

## Gotchas
The platform restriction lives in this folder's assembly definition, not in any file, so it
cannot be granted or waived per file. Moving one script out of this folder silently drops it
into a shipping build, with no error anywhere until something Editor-only is called at
runtime. The namespace here is plural, and that is load-bearing: the singular form resolves
ahead of the Editor API's own root type for every sibling file in this assembly, so the
first file to reference that type stops compiling — measured here, not hypothetical.
A reference stored into a temporarily opened prefab copy dies when that copy unloads and
reads back as empty after the save, which is why references resolve against the asset and
why every write is re-read from a fresh load before it is reported as applied.
