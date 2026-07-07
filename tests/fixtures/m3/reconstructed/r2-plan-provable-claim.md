# Reconstructed excerpt — run 2 plan.md, the "provably implied" claim (U-03 replay input)

Provenance: run 2's `plan.md` was overwritten by run 3's before preservation. The claim
below was verified verbatim at line 186 during the audit session (grep hit,
2026-07-06); surrounding context is summarized, not original bytes.

## The claim (verbatim fragment, plan.md:186)

> …predicates `window_start >= floor_hour(from)` and `window_start < to` (both provably implied by the…

Context (audited): the plan asserted the coarse `window_start` filter predicates on
the events listing query were "provably implied" by the fine `event_time` bounds. The
assumed invariant — `window_start == floor(event_time)` — was enforced nowhere in the
planned change (no CHECK constraint, no single code path, no test): `window_start` is
floored **app receive-time** while `event_time` is **DB now()**, so the two clocks can
straddle an hour boundary and the "implied" predicates silently drop rows
(review finding #1, CONFIRMED by 5/5 angles; deferred to the app backlog).

## What the U-03 proof-claim replay must assert

Given a plan containing this claim, the upgraded plan-audit flags it **material**
because step (b) fails: no enforcement point (constraint / code path / failing test)
exists for the invariant the claim rests on.
