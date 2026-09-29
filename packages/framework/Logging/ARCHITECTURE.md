# Logging

## Purpose
Gives runtime game code one tagged way to report what it is doing, so diagnostics can be
filtered by domain and stripped from release builds without deleting the call sites.

## Boundary
Wraps the engine's console and nothing else — no file sink, no upload, no severity policy
beyond the three levels it offers. It knows no game type and holds no state other than the
set of enabled tags, which is why every other framework assembly may reference it and it
may reference none of them. Editor-only tooling and tests deliberately do **not** log
through here: their output must never be filterable by runtime state, and they never ship,
so the stripping this assembly exists for buys them nothing.

## How to extend
A new domain gets a new member on the tag enum and nothing else — the enabled set is built
from the enum itself at startup, so a tag is live the moment it is declared and there is no
second place to forget. The tags declared here are framework-level only; a tag naming one
game's own domain is noise in every other project that consumes this package, so those are
declared on the game side. Resist adding a tag for a sub-part of a domain that already has
one; the filter is only useful while the tags stay few enough to reason about. A new
severity level is a design decision, not an addition: the asymmetry described below is the
whole design, and a fourth level has to say which side of it it falls on.

## Gotchas
The two lower levels are compiled out of release builds and gated on the enabled tag set.
The error level is **neither**, and that is deliberate rather than an oversight: an error is
a defect report, not a diagnostic, so it must survive into release and must never be
silenced by turning a domain off. Anyone tidying this file will see the inconsistency
before they see the reason — the reason is in a comment beside it, and this is its second
home so that tidying the comment away does not take the reason with it.
The cost of getting that wrong has been paid once already, and it took two independent
mistakes at the same time: the event bus reported every listener failure at error level,
that tag was not enabled, and the level was strippable — so failures inside listeners,
where nearly all game logic runs, were invisible in the editor and absent from release
simultaneously. Either mistake alone would have been noticed.
When a failure carries an exception, pass the exception itself rather than its message
text: only the object form produces a stack trace the console can navigate to. That form
emits **two** console entries, the message and then the exception — a test asserting on an
error path must expect both, in that order, or it fails on the one it forgot.
