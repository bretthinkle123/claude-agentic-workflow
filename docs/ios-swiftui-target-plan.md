# Plan — native SwiftUI iOS target: planning/build competence + honest gate adaptation (iOS side-track)

> **Status: partially BUILT.** Layers 0–2 shipped 2026-07-04 (PR #21: the four iOS skills in
> `global-project-skills/` — `swift-conventions`, `apple-hig-compliance`, `claude-design-to-swiftui`,
> `app-store-submission-requirements` — plus the planning/implementation iOS routing), and Layer 3's
> **reduced-assurance stamp** shipped 2026-07-05 (`run-summary.sh` + `tests/suites/assurance.sh`).
> What remains ⬜ is the rest of **Layer 3** — the Swift gate adapters (`xcodebuild` smoke,
> Semgrep-Swift/SPM SCA, `xccov` coverage) — which is **macOS/Xcode-bound and cannot be built on
> the Windows dev host**; until a macOS runner exists, iOS runs are stamped reduced-assurance by
> construction.
> Scope is the **engine's ability to plan, build, and gate a native iOS app** (Project 3),
> NOT the app itself. Consumes the artifact from `docs/design-spec-stage-plan.md` (a design
> bundle → approved `design-spec.md`). This is the front-end workstream's iOS specialization
> (`[[deferred-frontend-workstream]]`).

## Goal & honest scope

Let the pipeline take an approved design spec and a feature description and produce a **native
SwiftUI implementation plan** (and build it, and gate it honestly) — mapping design intent to
SwiftUI views, translating layout/styling intent to modifiers, and **flagging where a clean
mapping isn't possible** — instead of the current JavaScript-web-only frontend default.

Honest bar: the design bundle is a **visual/UX reference that a human approved**, and the plan is
a **native architecture generated against that intent** — *not* a line-by-line transpile of the
Claude Design HTML/CSS/JS. A literal HTML→SwiftUI port yields non-idiomatic SwiftUI that fights
the platform (CSS cascade ≠ modifier order, flexbox ≠ stacks, web gestures ≠ UIKit); the
reference-not-source framing is both higher-fidelity and the correct security posture.

## The gap it closes (verified against the current engine)

- **Frontend default is JavaScript** (`planning.md:61`); there is **zero** Swift/SwiftUI/HIG/
  Xcode-build content in any agent, skill, or convention (repo-wide grep: only an incidental
  "Apple" OAuth provider and the post-merge App Store recipe below).
- **Deployment already covers submission, not build.** `docs/pipeline-deployment-targets.md:251`
  has an Apple App Store / Fastlane recipe (code signing, `PrivacyInfo.xcprivacy`, TestFlight) —
  but it runs **after merge, outside the pipeline** (`agentic-pipeline-plan.md:283`); nothing
  makes those requirements accountable during planning, and nothing plans or builds the Swift.
- **The deterministic gates are Python/JS-shaped.** Semgrep rulesets, OSV/SCA keyed to npm/PyPI,
  and the `test-conventions` coverage runner assume the default stack. On a Swift diff they would
  run but analyze little — a real risk that the `loop-exit ≡ gate` guarantee stays *structurally*
  true while its underlying checks go *vacuous* (green on effectively unanalyzed code). Closing
  this is Layer 3 and is a **precondition**, not polish.

## Design principles (inherited)

- **Documented defaults, not hard requirements** (`planning.md:52-56`) — iOS/SwiftUI is an
  *alternative frontend stack* recorded and justified under `## Stack notes`, the sanctioned way
  to depart from the JS default.
- **On-demand skills keep base context lean** (`planning.md:26-38`) — the iOS skills load only
  when the target is iOS, and load nothing on a default-stack run.
- **Native from reference, never transpilation** — the §2 honest posture, encoded as an explicit
  planning instruction, not left to the agent to infer.
- **Deterministic gates stay language-honest** — a gate that cannot actually analyze Swift must
  not report a pass; better an explicit "not covered for this language" than a vacuous green
  (protects the `loop-exit ≡ gate` invariant's *meaning*, `pipeline-orchestration/SKILL.md:40-55`).

## Layer 0 — three iOS skills (the missing competence)

On-demand skills, ranked by how much ambiguity each removes for planning + implementation. Place
in `global-project-skills/` (Project-3-scoped; promote to `global-skills/` if reused across iOS
projects — decision recorded per skill).

1. **`swift-conventions` (SwiftUI) — highest value, build first.** SwiftUI view architecture,
   state model (`@Observable`/`@State`/`@Binding`), navigation stack, project layout, and the
   XCTest shape. Includes a **"coming from a web reference" mapping cheat-sheet** (`div`→stack,
   flexbox→`HStack`/`VStack`, CSS→modifiers) — the useful 20% of "HTML→SwiftUI," folded in here
   rather than a standalone transpiler skill (which would invite the port-vs-redesign confusion
   and produce non-idiomatic output). **Scope:** planning (view architecture) + implementation
   (idiomatic Swift) + testing (XCTest structure).
2. **`apple-hig-compliance`.** Native nav patterns, tab bars, SF Symbols, Dynamic Type, dark
   mode, safe areas. Highest use is at the design seam — mapping the design spec's *web* idioms
   (the "needs native mapping" section from the DS plan) onto iOS-native equivalents. **Scope:**
   planning + design-spec/design-review.
3. **`app-store-submission-requirements`.** Code signing, privacy manifest
   (`PrivacyInfo.xcprivacy`), data-use declarations, review guidelines — frequent rejection
   causes that must surface as **acceptance criteria early**, not at submission. **Scope:**
   planning (emits privacy-manifest/data-use ACs into `acceptance.md`) + deployment (makes the
   existing Fastlane recipe's requirements accountable).

## Layer 1 — planning recognizes and plans the iOS target

`global-agents/planning.md` changes (all additive, gated on the target being iOS):

- **Target detection** — when PROJECT.md/`Stack notes` declare a native-iOS frontend, planning
  records it under `## Stack notes` as an alternative to the JS default (`planning.md:68-79`) and
  loads `swift-conventions` + `apple-hig-compliance`.
- **Frontend layer produces a SwiftUI architecture** — the per-layer Frontend section
  (`planning.md:104-116`) yields SwiftUI view/state/navigation decisions with the usual
  what/why/how rationale, **against** the approved `design-spec.md` when present (DS plan Layer 3).
- **Native-from-reference instruction** — planning explicitly translates design *intent* to
  SwiftUI and **lists each web idiom that has no clean native mapping** (from the design spec's
  "needs native mapping" section) as an Open Question or a resolved decision — never a silent
  literal port.
- **App Store ACs** — via `app-store-submission-requirements`, planning emits privacy-manifest +
  data-use-declaration acceptance criteria into `acceptance.md` so they ride `criteria_covered`.

## Layer 2 — implementation builds SwiftUI through the conventions

`global-agents/implementation.md` loads `swift-conventions` for an iOS target; builds SwiftUI
views/state per the plan and the approved design intent; writes XCTest tests. All UI construction
follows the conventions skill; no ad-hoc idioms.

## Layer 3 — honest gate adaptation (the precondition, and the real cost)

Until these land, an iOS run's deterministic teeth are weaker than a Python/JS run's; this layer
is **required before any real iOS build is trusted**, and is platform-bound (needs macOS/Xcode).

- **Smoke / build** — `smoke-check.sh` is project-wired at bootstrap (`--build`/`--test` flags,
  `pipeline-orchestration/SKILL.md:127-131`). For iOS it must run `xcodebuild build`/`test` on a
  **macOS runner** (operator-provided; Windows dev host cannot build iOS — stated plainly).
- **Security** — a Semgrep **Swift** ruleset (extend `semgrep-ruleset-guide`); SCA over Swift
  Package Manager / CocoaPods dependencies. **Honest limitation:** OSV's Swift/SPM coverage is
  partial — name the residual and add SwiftLint + a manifest-pinning check as the belt-and-
  suspenders net, rather than claim OSV parity with npm/PyPI. Secrets scanning is language-
  agnostic and already works.
- **Testing / coverage** — the coverage runner must parse **`xccov`/llvm-cov** output, not the
  JS/Python coverage the `test-conventions` runner assumes; the `criteria_covered` gate is
  language-agnostic (it counts criteria, not lines) and is unaffected, but the coverage *number*
  it surfaces needs a Swift adapter to be real.
- **Invariant honesty** — none of this adds a status conjunct, so the `loop-exit ≡ gate`
  invariant and its harness are structurally untouched; what changes is making the existing
  conjuncts *mean something* on Swift. A gate that can't analyze Swift must surface "not covered,"
  never a vacuous pass.
- **Enforced reduced-assurance stamp (closes the "precondition is prose, not enforced" gap).**
  Stating Layer 3 is a precondition is not enough — a green iOS run before the Swift adapters
  exist would exit the loop with vacuous security/coverage checks. So the bootstrap/target check
  detects a Swift target with **absent language adapters** and stamps the run
  `assurance: "reduced (swift adapters absent)"` in `run-summary.json`; while that stamp is
  present the run must **not** be described as "gate-verified," and the reduced state is surfaced
  at the diff-review checkpoint. This converts the intended ordering into an observable,
  non-glossable fact rather than a hope. (No new *gate* conjunct — a surfaced honesty stamp, same
  posture as the coverage "surfaced, not gated" decision.)
- **Host feasibility (hard external dependency).** Layer 3 is macOS/Xcode-bound and **cannot be
  built or validated on the Windows 11 dev host** — it requires a macOS runner. Until one exists,
  the Swift gate adapters are un-testable, so iOS runs stay in the reduced-assurance state above
  by construction. This is a blocker on external infra, not a deferral that code alone clears —
  stated up front so the assurance story for iOS is never over-claimed.

## Layer 4 — deployment (mostly already present)

The Fastlane / App Store recipe already exists (`pipeline-deployment-targets.md:251`);
`app-store-submission-requirements` makes its requirements accountable as ACs upstream. No new
deployment mechanism — the gap here was *accountability*, not the recipe.

## Non-goals

- Not provisioning the macOS/Xcode runner (operator infra) — the plan *names* the dependency,
  doesn't build it.
- Not a standalone HTML→SwiftUI transpiler (absorbed as a cheat-sheet in `swift-conventions`).
- Not Android/cross-platform.
- **Not claiming iOS gate-parity until Layer 3 ships** — an iOS run before Layer 3 has honest but
  weaker deterministic teeth, and that must be stated on the run, not glossed.

## Sequencing (dependencies are real — order matters)

1. **Layer 0** — the three skills (`swift-conventions` first). **S–M.** Unblocks planning/impl.
2. **Layer 1** — planning's iOS target branch + native-from-reference instruction + App Store ACs.
   **S–M.** Depends on Layer 0 and (for design intent) `docs/design-spec-stage-plan.md`.
3. **Layer 3 gate adaptation** — the precondition for trust; **L**, platform-bound (macOS). Should
   land **before** an iOS build is treated as gate-verified, even though Layer 2 can technically
   run without it.
4. **Layer 4** — App Store AC accountability. **S** (recipe already exists).

## Tie-in

Directly depends on `docs/design-spec-stage-plan.md` (design intent) and reuses the existing
deploy recipe. Recorded in the front-end workstream (`[[deferred-frontend-workstream]]`); update
the parallel side-tracks table in `pipeline-june-analysis.md` with a DS and an iOS row when these
move from spec to build.
