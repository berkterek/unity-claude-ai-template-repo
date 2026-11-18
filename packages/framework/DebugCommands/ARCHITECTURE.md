# DebugCommands

## Purpose
Lets dev-only command containers be listed and run by id from outside the game, by tools that cannot be handed a reference.

## Boundary
Compiled only into the Editor and development builds — the assembly's define constraint removes it from release
builds, so nothing here may ever be required by shipping code. It knows no game type and no container library:
containers register themselves, and this assembly only reflects over what is registered right now. It never
publishes announcements, never decides game outcomes and never finds services on its own; a command reaches the
game only through the methods its container was given by injection. Rendering the commands in an in-game panel is
the optional adapter assembly's job, not this one's.

## How to extend
A new command lives in the game, not here: a container class per domain, suffixed DebugCommands, that registers
with the registry interface when its owner is built and unregisters when it is torn down, installed from the
Module of the scope whose services it calls. Public settable properties are parameters, public parameterless void
methods are commands, public read-only properties are values to read back. Group with the standard
component-model category attribute only, so the same container works in an in-game panel too.

## Gotchas
The command id is the container's type name without its suffix, a dot, then the member — renaming a container
renames every id, and the generated playtest table with it.
Interface implementations and members marked not browsable are never listed; any other public parameterless
method is a command, so keep helpers private. The playtest generator applies the same rules without reflection and
can only recognise the well-known lifecycle interfaces — any other interface method needs the not-browsable mark.
Parameter values arrive as text and are all converted before any is applied, and a setter that throws rolls back
the ones already set — a failed run leaves the container as it was. A command that throws is reported and
answered, never rethrown; the parameters it was given stay set.
The static entry point is set once per container build and read by the Editor tool alone; game code injects the
interface. A second build in one domain replaces the registry and logs a warning.
The define constraint uses an OR expression; verified only on the Editor side (an Editor assembly references this
one and compiles) — release exclusion relies on the asmdef constraint documented by Unity.
The in-game panel adapter sits in its own subfolder assembly, compiled only when the project defines the
SRDebugger symbol; that panel honours the category and not-browsable attributes but lists every other public
method, lifecycle ones included — mark those not browsable to keep them off the panel.
