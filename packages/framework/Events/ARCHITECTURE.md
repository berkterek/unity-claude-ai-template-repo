# Events

## Purpose
Carries typed, one-way announcements between parts of the game that must not hold
references to each other, and offers one deliberately static way in for callers that
cannot be given a reference at all.

## Boundary
Knows no game type and must never learn one — this assembly sits below everything and
references only the logging assembly, so a reference pointing back at game code is not a
style question, it is a dependency cycle. It does not decide who listens, does not order
listeners, and does not retain anything: an announcement made before a listener attaches
is simply not heard, because nothing here is a queue or a history. Anything that needs
replay, buffering or ordering belongs to the domain that needs it.

## How to extend
A new announcement is a small immutable value type implementing this assembly's marker
interface, declared in the domain that raises it — never here. Name it for something that
already happened, past tense. Listeners attach when their owner is built and detach when
it is torn down, in matching pairs; the framework enforces no pairing and cannot, so an
unmatched attach is a leak that keeps its owner alive and keeps answering after teardown.
The static entry point exists for callers outside the container's reach and is initialised
once at startup — adding a second static accessor of any kind is a design decision, not a
convenience.

## Gotchas
Each listener is isolated during delivery: one that throws is reported and the rest still
run. Two consequences, both easy to get backwards. A publisher never sees a listener's
failure, so wrapping the publish call in a catch buys nothing and hides nothing. And a
listener that swallows its own exceptions suppresses a report that would otherwise have
been made for it — the bus already did that work, and the handler's own catch is the one
that logs nothing.
Delivery walks the listener list backwards without copying it, so a listener that detaches
itself during delivery is safe while one that attaches a new listener may or may not reach
it in the same round. Do not depend on either outcome.
That failure report is the one log this assembly emits that is neither compiled out of
release builds nor silenceable by tag — see the logging assembly's own note for why, and
what happened when both halves of that were wrong at once.
