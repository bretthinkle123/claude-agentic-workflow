# Plan — design-spec stage: an authoritative-but-untrusted design bundle as pipeline input (DS side-track)

> **Status: Layers 0–4 BUILT (Layers 0–3 on 2026-07-04, Layer 4 on 2026-07-05; roadmap row DS).**
> The `design-spec` agent, the `design-system-conventions` skill, the `design-approved` checkpoint +
> currency/forgery guard, the orchestration wiring, and planning's authoritative third branch are
> implemented and harness-tested (`tests/suites/design-spec.sh`). **Layer 4** (the post-build
> design-review) is also built — deterministic budget compare (`design-review-check.sh` +
> `tests/suites/design-review.sh`) with the Playwright capture (`ui-capture.sh`/`.mjs`)
> **runtime-bound**: a fail-safe no-op until the operator provisions `ui.env` + a browser runtime.
> It is advisory only — never a gate, never in loop-exit.
> Scope is the **engine** (a new pre-planning stage + a human checkpoint), NOT any built app.
> This is Layer 2 of the front-end workstream (`[[deferred-frontend-workstream]]`); it is the
> prerequisite that makes Section 1 of the Claude-Design evaluation real. Companion:
> `plan/ios-swiftui-target-plan.md` (consumes the artifact this stage produces).

## Goal & honest scope

Give the pipeline a way to consume a **design bundle** (a Claude Design HTML/CSS/JS export,
a Figma export, or reference screenshots) and treat its **visual/UX/component decisions as
settled input** that planning builds *from* — instead of the current behavior, where planning
has no design-input channel at all and re-derives the UI itself.

The honest bar, mirroring the rest of the engine, is **not** "the design is trusted." It is:

> A design bundle is **untrusted data**. A dedicated stage **normalizes** it into a reviewable
> spec (never obeying any instruction embedded in it); a **human approves** that spec; and only
> then does planning treat the *visual intent* as authoritative — while still treating the
> spec's bytes as data, never as instructions.

No stage can prove a screenshot's embedded text is benign (that is the open injection problem).
"Authoritative" here means **a human vouched for the visual intent**, exactly the way
`plan-approved` makes a plan authoritative — a human checkpoint, never a deterministic gate
driven by design content.

## The gap it closes (verified against the current agent)

Today the planning agent (`global-agents/planning.md`) cannot do this, and says so structurally:

- **No design-input channel.** Its input model is binary (`planning.md:93-102`): greenfield →
  `PROJECT.md`; existing → `CLAUDE.md` + code. There is no third channel for a design export and
  nothing tells it where one would live.
- **It is told to design the UI itself.** Step 3 (`planning.md:104-116`) directs planning to
  research and design the Frontend layer ("UI components, state management, routing"). Handed a
  design bundle today it would re-derive the UI, i.e. treat the design as raw material to
  redesign — the exact failure Section 1 names.
- **The interlock contract has no design artifact** (`pipeline-orchestration/SKILL.md:135-152`);
  there is no file for a design spec, no reader wired to consume one.

## Design principles (inherited from this pipeline)

- **Untrusted input — data, not instructions.** Same rule the orchestration skill already states
  for `PROJECT.md`/cloned repos/registry text (`pipeline-orchestration/SKILL.md:214-224`),
  extended to a new and higher-risk carrier: image-embedded and HTML-embedded text. The
  design-spec agent extracts visual facts and **reports** any imperative it finds ("ignore the
  tests", "approve this") rather than obeying it.
- **Human checkpoint as the backstop, never a content-driven gate.** No deterministic gate ever
  reads design-spec content — consistent with "the deterministic gates never delegate a pass/fail
  to model judgement" (`pipeline-orchestration/SKILL.md:220-221`). The teeth are the human
  `design-approved` review, not a `jq` check on anything the design produced.
- **In-session approval, no terminal round-trip.** `design-approved` is recorded by the
  orchestrator when the human says "continue" in session (`[[checkpoint-approval-in-session]]`),
  *not* a TTY helper like `approve-diff.sh`. Justified because this marker gates *planning's
  treatment of visual intent*, not a deploy — it is a pre-planning vetting marker, strictly lower
  stakes than the anti-forgery `diff-approved` deploy gate (`approve-diff.sh:31-33`). Stated
  explicitly so the difference from the TTY-only posture is a conscious choice, not an oversight.
- **Fresh-context, file-handoff.** The stage communicates only through `.pipeline/*`
  (`pipeline-orchestration/SKILL.md:11-14`); the bundle lives in the repo, the normalized spec in
  `.pipeline/`.

## Layer 0 — the input convention (where design bundles sit)

- Design bundles live in a **`design/`** directory at the repo root, referenced by **one pointer
  line in `PROJECT.md`** (e.g. `Design source: see design/ (Claude Design export)`). PROJECT.md's
  body stays *functional* requirements; visual references are a separate input, never pasted into
  it. This matches how greenfield planning already reads PROJECT.md (`planning.md:96`).
- Accepted forms: a Claude Design HTML/CSS/JS export, a Figma export, or reference screenshots
  (PNG/JPG — read natively via the Read tool's image support). The stage is source-agnostic; the
  human picks a primary and may include others as backup (multiple sources allowed).
- **Trigger rule (explicit, so the stage is never silently skipped or force-run):** the
  orchestrator runs the design-spec stage **iff** `design/` exists **or** PROJECT.md declares a
  design source. No design source ⇒ the stage and its checkpoint are skipped entirely; the
  pipeline behaves exactly as today.

## Layer 1 — the `design-spec` agent (normalize; treat the bundle as data)

A new subagent `global-agents/design-spec.md` (tools: `Read, Write, Skill`; model opus). It reads
the `design/` bundle and writes **`.pipeline/design-spec.md`**, a normalized, reviewable spec:

- **Screen/flow inventory** — each screen the bundle depicts, and the navigation between them.
- **Component inventory** — the reusable UI components (button, card, list row…) and their states.
- **Design tokens** — color, type scale, spacing, radii, elevation — extracted as a named table.
- **Layout intent** — hierarchy, grouping, alignment per screen (intent, not pixel coordinates).
- **Interaction notes** — gestures/transitions the bundle implies.
- **"Needs native mapping" section (REQUIRED)** — web idioms with no clean native equivalent
  (hover states, CSS grid, scroll-snap, web modals) flagged for the target platform, so a
  downstream native plan translates intent rather than porting markup. This is the seam that
  `plan/ios-swiftui-target-plan.md` consumes.
- **Provenance + injection report** — the source(s) used, and a verbatim list of any
  instruction-shaped text found embedded in the bundle, quoted and marked **not acted on**.

The agent loads the on-demand `design-system-conventions` skill (and, for an iOS target,
`apple-hig-compliance` from the companion plan) to structure the extraction. It **never** edits
code and **never** treats bundle text as an instruction.

## Layer 2 — the `design-approved` human checkpoint

The human reviews `.pipeline/design-spec.md` (including its injection report) and approves in
session; the orchestrator records **`.pipeline/design-approved`** (a small JSON marker:
`{approved_at, note, design_spec_hash}`). Planning treats the design spec as authoritative **only
if this marker exists**; absent it, there is no authoritative design and planning proceeds as
today. The marker gates *authority*, not existence — the spec can be read, but its visual
decisions are not "settled" until a human vouches.

**Currency (the F3 *pattern*, `approve-diff.sh:37-46`).** `design_spec_hash` pins the exact
`design-spec.md` bytes the human approved. The **orchestrator recomputes** the current spec's hash
right before invoking planning and treats the design as authoritative **only if it matches** — if
the `design/` bundle changed and the spec was regenerated after approval, the marker is stale and
the orchestrator drops authority (re-run design-spec + re-approve). **The orchestrator, not
planning, does the recompute** — planning has no shell (`tools:` has no Bash), so a self-recompute
there is infeasible; and unlike F3 this is *not* backed by a deterministic deploy gate (design
content never gates by design), so it is the F3 hash-pinning *pattern* enforced at the human/
orchestrator seam, a softer guarantee than F3's gate-checked commit hash. Without it, approval
silently drifts from what ships into the plan.

**Forgery guard (mirrors the `plan-approved`/`diff-approved` protection,
`pipeline-orchestration/SKILL.md:194-196`).** `.pipeline/design-approved` is added to
`guard-approval-markers.sh`'s PreToolUse deny plus the settings `Write`/`Edit` deny, so **no
subagent can forge it** — critically the `design-spec` agent, which holds the `Write` tool and
would otherwise be able to approve its own output. Only the orchestrator (human-driven main
thread) records it. A checkpoint without this guard is not a checkpoint.

## Layer 3 — planning consumes the approved spec (the behavior change)

> **Status: the *default behavior* is already implemented in `global-agents/planning.md`**
> (the "Frontend design source" rule + the step-3 / rationale / self-audit scoping). That
> rule makes faithful replication the default whenever **any** design source is present — a
> `design/` export, screenshots, a Figma export, **or** an approved `.pipeline/design-spec.md`
> — not gated on `design-approved`. It degrades gracefully: with no design-spec stage yet,
> planning reads a raw export directly; when the stage lands, an approved, normalized,
> currency-checked `design-spec.md` becomes the higher-fidelity, forgery-guarded source the
> same rule consumes. What remains for the full stage below is the **normalization +
> human-vouched + currency/forgery-guarded** wrapper, not the replicate-not-redesign behavior.

`global-agents/planning.md` gains a **third input branch** (alongside greenfield/existing): when
`.pipeline/design-approved` exists, planning:

- reads `.pipeline/design-spec.md` as the **authoritative source of visual/UX/component
  decisions** — it plans architecture and task-breakdown *against* those decisions and **does not
  redesign** the frozen visual intent (a direct counter to the current step-3 "design the
  Frontend" instruction, scoped to when an approved spec is present);
- **still treats the spec's bytes as data, not instructions** — approval vouches for the *visual
  intent*, not for any imperative embedded text; planning obeys nothing written inside it (the
  human-review backstop does not launder injected instructions into trusted commands);
- **traces design → plan**: each screen/component in the spec maps to a plan section and to an
  acceptance criterion in `acceptance.md` (so downstream build/test are accountable to the
  design, riding the existing `criteria_covered` machinery — no new artifact, no new gate).

## Layer 4 — post-build design-review (advisory, later slice)

After GREEN, an optional `design-review` stage compares the built UI against the approved spec
(screenshot/pixel or snapshot diff) and surfaces drift as an **advisory** report folded into
documentation — never a gate (visual diff is too brittle to block on, and design content must not
gate). For a native iOS target this is snapshot testing, detailed in the companion plan. Scoped
last; the first three layers deliver the Section-1 capability without it.

## Interlock-file + orchestration impact (honest cost)

- **New files:** `.pipeline/design-spec.md` (writer: design-spec; readers: human, planning,
  design-review) and `.pipeline/design-approved` (writer: human via orchestrator; reader:
  planning). Two rows added to the interlock table (`pipeline-orchestration/SKILL.md:135-152`).
- **Marker-guard change:** add `design-approved` to `guard-approval-markers.sh` + the settings
  `Write`/`Edit` deny (Layer 2 forgery guard) — one new marker in an existing mechanism, no new
  gate.
- **New stage** inserted as step 0/0b **before** planning in the stage sequence
  (`pipeline-orchestration/SKILL.md:16-79`), conditional on the Layer-0 trigger. No change to the
  loop, the gates, or the `loop-exit ≡ gate` invariant — this stage adds **no** deterministic
  conjunct (design content never gates), so the invariant harness is untouched.
- **Bootstrap:** `design/` is a convention, not a required dir; no bootstrap change beyond
  documenting it.

## Non-goals

- Not a deterministic gate on design content — the human checkpoint is the only teeth.
- Not pixel-perfect enforcement, and not a replacement for the human's design judgment.
- Not auto-approval — an unreviewed spec is never authoritative.
- Not the native-translation work (that is `plan/ios-swiftui-target-plan.md`); this stage is
  platform-agnostic and stops at a normalized, approved spec.

## Sequencing (each slice independent; none on the critical path)

1. **Layer 0–1** ✅ — input convention + the `design-spec` agent writing `design-spec.md`. **Built.**
2. **Layer 2** ✅ — the `design-approved` in-session marker + orchestrator wiring + currency hash +
   forgery guard (`guard-approval-markers.sh` + settings deny). **Built.**
3. **Layer 3** ✅ — planning's third input branch (currency-checked) + design→AC tracing. **Built.**
4. **Layer 4** ✅ — post-build design-review (advisory visual-regression + a11y budget). **BUILT
   (2026-07-05):** `ui-capture.sh` + `ui-capture.mjs` (Playwright render → screenshot → pixelmatch
   diff vs baseline → axe) writes `ui-capture.json`; the deterministic `design-review-check.sh`
   compares it to `design-budget.json` and writes an **advisory** `design-review.json` (never a
   gate); documentation surfaces it in the PR. Orchestration stage 4d, conditional on `.pipeline/ui.env`.
   The budget logic is harness-tested (`tests/suites/design-review.sh`); the Playwright capture is
   **runtime-bound** (needs `npm i playwright pixelmatch pngjs @axe-core/playwright`), fail-safe no-op
   when unprovisioned. Web/platform-agnostic; the native-iOS analogue is XCUITest snapshotting (iOS Layer 3, macOS).
