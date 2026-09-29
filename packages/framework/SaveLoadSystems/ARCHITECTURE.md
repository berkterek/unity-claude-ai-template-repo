# SaveLoadSystems

## Purpose
Persists small named blobs of player state across sessions, behind one contract the game
calls and a second, narrower one that decides where the bytes actually land.

## Boundary
Split in two on purpose, and the split is the whole point: the upper half knows about keys
and typed payloads and never touches a file, a path or a serializer; the lower half knows
nothing but a key and a string. That is what lets the storage mechanism be swapped — a
different backend for the web, a remote one, a syncing pair of both — without a single
caller changing. Game code never names the lower half, never reads a platform path, and
never reaches for the engine's own key-value store; a call site that does has cancelled the
swap before it was possible. This assembly decides nothing about what is worth saving, when
to save it, or what a new player should start with — those are the owning domain's. Keys
are the owning domain's too, and therefore are not declared here: a key names a game's own
data, and this package ships to every project.

## How to extend
A new persisted thing is a plain serializable class carrying its own version number, owned
by its domain, written under its own key rather than folded into a shared root object. One
key per domain: a single root means every future domain edits one class and one version
number speaks for all of them, and the consistency that buys is not consistency anyone
needs. Keys are declared once as constants in one place on the game side, never typed
inline — a casing slip is silent data loss, not an error. A new backend implements the
lower contract only, and is chosen at wiring time.

## Gotchas
Reading is a two-step question and both steps can disagree: whether a key exists, and
whether what it holds still parses. They come apart exactly when a payload is corrupt or
was written by an older build, so a caller that trusts existence alone turns a recoverable
restart into a crash on the first run after an upgrade.
The platform kills a backgrounded process without warning — routine on mobile, not exotic —
so a write that truncates the live file before the new bytes are complete can leave neither
the old state nor the new. The write belongs in a temporary file that is swapped in once it
is whole.
A parse failure is a fallback with a log, never an exception thrown into the game, and the
catch is narrow: a locked file is a different problem and must not be absorbed into it.
I/O here is synchronous, which the project's async rule otherwise forbids: saves are a few
hundred bytes written at startup and at the end of a run, so the frame cost that rule targets
does not exist at this size. A knowing deviation, recorded rather than silent — large blobs,
remote storage or per-frame autosave reopen it.
