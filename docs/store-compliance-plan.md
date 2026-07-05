# Plan — app-store compliance gate (Apple App Store + Google Play), project-scoped via PROJECT.md

> **Status: Layers E + C BUILT (2026-07-05); Layers A/B/D SPEC.** Layer E (Android reduced-assurance
> stamp) and Layer C (deterministic `store-compliance.sh` + deploy-gate floor + 14-assertion suite,
> first cut) are shipped and harness-green; the Google Play skill (A), planning routing (B), and
> Tier-2 flags (D) remain. Companion to `docs/ios-swiftui-target-plan.md` (which shipped the
> Apple-side competence), `docs/pipeline-deployment-targets.md` (the post-merge Fastlane / Gradle
> submission recipes), and `docs/asvs-determinism-roadmap.md` (whose Tier 1/2/3 promotion pattern
> this reuses). Scope is making store-submission requirements **accountable inside the pipeline** —
> caught at planning/gate time, not at upload — for projects whose `PROJECT.md` declares a mobile
> store target. It is NOT a guarantee of store acceptance (final review is human, by Apple/Google).

## Goal & honest scope

When a project's `PROJECT.md` declares an App Store and/or Play Store target, the pipeline should:

1. **emit the store's known submission requirements as acceptance criteria** at planning time (so
   they ride `criteria_covered`, the proven accountability channel), and
2. **verify the mechanically-checkable subset deterministically** (file/manifest/config checks an
   injected or sloppy agent cannot talk past — same posture as `asvs-sast.sh`).

Honest bar: the pipeline can **design out the known, frequent rejection causes** (privacy manifest,
usage strings, target SDK floor, debuggable release builds, account deletion, IAP rules). It cannot
guarantee acceptance — content policy, metadata quality, and the human review outcome are Tier 3 by
nature and stay in the post-merge recipes.

## Scoping mechanism — PROJECT.md (already exists)

No new config file. The iOS side-track already keys target detection off `PROJECT.md` / planning's
`## Stack notes` ("when PROJECT.md/Stack notes declare a native-iOS frontend…",
`ios-swiftui-target-plan.md` Layer 1). This plan generalizes that same switch:

- `PROJECT.md` declares the distribution target (e.g. "ships to the Apple App Store", "ships to
  Google Play", or both) — planning records it under `## Stack notes`.
- The store-compliance layers below activate **only** for the declared store(s); a default web/API
  run loads nothing (on-demand-skill rule, `planning.md:26-38`).

## Already exists — do NOT re-spec

| Piece | Where | Status |
|---|---|---|
| Apple submission requirements → acceptance criteria | `global-project-skills/app-store-submission-requirements/` (privacy manifest, usage strings, Sign in with Apple, account deletion, IAP, signing, rejection causes, AC templates) | ✅ shipped PR #21 |
| Apple submission recipe (Fastlane, TestFlight, API-key signing) | `pipeline-deployment-targets.md` §Apple App Store | ✅ (post-merge, outside pipeline) |
| Google Play submission recipe (Gradle, signed AAB) | `pipeline-deployment-targets.md` §Google Play | ✅ (post-merge, outside pipeline) |
| Reduced-assurance stamp for un-adapted mobile targets | `run-summary.sh` + `tests/suites/assurance.sh` | ✅ shipped 2026-07-05 |

## The gap (verified against the current engine)

- **Google Play has no competence layer at all** — no skill, no planning routing, no ACs. Android
  is an explicit non-goal of the iOS plan (`ios-swiftui-target-plan.md` §Non-goals), so nothing
  makes Play requirements (target SDK floor, Data safety form, permission declarations, account
  deletion parity) accountable anywhere before the post-merge recipe.
- **Apple-side ACs are agent-verified only.** The skill emits them into `acceptance.md`, but every
  one is checked by agent judgment via `criteria_covered` — none is promoted to a deterministic
  check, even though several are pure file/grep checks (manifest presence, `Info.plist` keys).
- **Store floors drift.** Google raises the required `targetSdkVersion` annually; Apple updates
  Required-Reason API lists. A deterministic check needs a **maintained floor constant**, or it
  rots silently.

## Tiering (reuses the ASVS-determinism promotion pattern)

### Tier 1 — deterministic config/manifest checks → `store-compliance.sh`

A new hook wired **exactly like `asvs-sast.sh`** — this matters: the hook writes its **own
`store-compliance.json`**, and the deploy gate blocks deterministically on a `critical>0` floor
(deploy-only, absent ⇒ no-op, nothing added to loop-exit). NOT the `lockfile-check.sh` pattern
(where the security agent incorporates findings into `critical_count` — agent-trusted); only the
agent-independent wiring satisfies this plan's stated goal, "checks an injected or sloppy agent
cannot talk past." Criticals block via the floor; the rest emit as advisory warnings, per the same
false-positive rubric the ASVS roadmap used.

**Deterministic scoping key** (a hook cannot use planning's judgment — it needs a machine-checkable
signal, same problem `run-summary.sh:37` solves with a loose grep): Apple checks apply when
`PROJECT.md`/`CLAUDE.md` grep-match `app store|ios|swiftui` **or** an `.xcodeproj`/`Package.swift`
file signal exists; Play checks apply on `google play|android` **or** a `build.gradle(.kts)`/
`AndroidManifest.xml` signal. Scoping **fails open by design**: an undeclared target means the
checks silently don't run. That is safe here — declaring a target only *adds* checks, so nothing
can be bypassed by omitting the declaration — but it is stated plainly rather than left implicit.

**All of these are plain file/text checks — runnable on the Windows dev host; no
macOS/xcodebuild dependency** (unlike the iOS plan's Layer 3 gate adapters).

| # | Store | Check | Detection sketch | Severity |
|---|---|---|---|---|
| SC-1 | Apple | Privacy manifest missing | `PrivacyInfo.xcprivacy` absent from the app target | **Critical** (automated rejection at upload) |
| SC-2 | Apple | Capability API used without its usage string | grep capability APIs (camera, photos, location, tracking, Face ID…) ↔ `NS…UsageDescription` keys in **`Info.plist` AND `project.pbxproj` `INFOPLIST_KEY_NS…UsageDescription` build settings** — modern Xcode projects often have no editable Info.plist (generated plist), so checking only Info.plist false-positives on every such project | **Critical** (runtime crash + rejection) |
| SC-3 | Apple | ATS disabled | `NSAllowsArbitraryLoads: true` without a scoped exception | Advisory |
| SC-4 | Android | `targetSdkVersion` below Google's current floor | parse `build.gradle(.kts)` / manifest against a **maintained floor constant** (bumped annually — see maintenance note). Must **resolve the common indirections** — a Gradle variable (`targetSdk = libs.versions…` / `rootProject.ext`) and version catalogs (`libs.versions.toml`) — since a literal grep false-negatives on the one check Google hard-blocks uploads on; any indirection it cannot resolve is emitted as an advisory "unresolved target SDK," never a silent pass | **Critical** (upload blocked) |
| SC-5 | Android | Debuggable / cleartext release build | `android:debuggable="true"`, `usesCleartextTraffic="true"` in release config | **Critical** / Advisory respectively |
| SC-6 | Android | Permission declared but unused, or used but undeclared | grep permission-gated APIs ↔ `<uses-permission>` entries | Advisory (declared-vs-used mismatch is a Data-safety red flag) |
| SC-7 | Both | Debug logging / test hooks in release build | store-specific greps (`Log.d`/`print` floods, test endpoints) in release source sets | Advisory |
| SC-8 | Apple | Export-compliance key absent | `ITSAppUsesNonExemptEncryption` missing from `Info.plist`/`project.pbxproj` — absence causes a manual question on **every** upload; presence is one grep | Advisory |
| SC-9 | Apple | Required-Reason API used without a declared reason | grep the Required-Reason API surface (`UserDefaults`, file-timestamp, disk-space, active-keyboard, system-boot-time APIs) ↔ `NSPrivacyAccessedAPITypes` entries in `PrivacyInfo.xcprivacy` — **this, not mere manifest presence (SC-1), is what Apple's upload tooling actually enforces**; same shape as SC-2 (used-API ↔ declaration compare) | **Critical** (automated rejection at upload) |

### Tier 2 — semantic-but-testable → plan-audit material flags + `test-conventions` shapes

Same channel as the ASVS T2 rows (plan-audit flags a missing criterion; the test rides
`criteria_covered`):

| # | Store | Required shape | Triggers when |
|---|---|---|---|
| SC-T2-1 | Both | **Data-declaration reconciliation** — data types the code actually collects match the Privacy Nutrition Label / Play Data-safety declaration. Consumes the **shipped** DP workstream's `data_surface` classified-field inventory (`data-protection-enforcement-plan.md`, delivered 2026-07-04) — **unblocked today**, and the highest-value Tier-2 row: build it first in Layer D | the app collects any user data |
| SC-T2-2 | Both | **In-app account deletion** flow exists and works (Apple 5.1.1(v); Play requires deletion parity incl. a web path) | the feature has account creation |
| SC-T2-3 | Apple | **Sign in with Apple** offered alongside any social login (Guideline 4.8) | social login exists |
| SC-T2-4 | Both | **Digital goods use the store's billing** (StoreKit IAP / Play Billing), not an external processor | the feature monetizes digital goods |

### Tier 3 — genuinely judgment / post-merge (no promotion)

Content policy, screenshot + metadata quality, age rating, demo credentials for review, "minimum
functionality" (Apple 4.2), and the human review outcome itself. These stay where they are: the
`app-store-submission-requirements` skill surfaces them as planning-time awareness, and the
post-merge Fastlane/Gradle recipes in `pipeline-deployment-targets.md` own the submission step.

## Layers

1. **Layer A — `google-play-submission-requirements` skill.** Mirror of the shipped Apple skill:
   Data-safety form, target-SDK policy, permission best practices, account-deletion parity, Play
   Billing rules, common rejection causes, and the AC templates planning emits. Place in
   `global-project-skills/` (same promotion rule as the iOS skills). **S–M.**
2. **Layer B — planning routing.** Generalize the iOS target-detection branch: `PROJECT.md`
   declares the store target(s) → planning loads the matching skill(s) and emits the store ACs
   into `acceptance.md`. Apple side is already speced (iOS plan Layer 1); this adds the Play
   branch and the both-stores case. **S.**
3. **Layer C — `store-compliance.sh` (Tier 1 rows). ✅ BUILT (2026-07-05) — first cut.** Wired
   **exactly** like `asvs-sast.sh`: a security Stop hook writing its own `.pipeline/store-compliance.json`
   `{ran_at, scope, critical, warning, findings[]}` + a deploy-gate `critical>0` floor (deploy-only,
   absent ⇒ no-op, nothing in loop-exit) + `tests/suites/store-compliance.sh` (14 assertions). Activated
   by the **deterministic scoping key** above (file signals + PROJECT.md/CLAUDE.md grep) — no matching
   target ⇒ whole hook no-ops, so default runs see zero cost. **Scope = repo state** (an absent
   manifest / low targetSdk is a whole-app fact, not a per-diff one). **Built this cut:** SC-1 (privacy
   manifest absent, gated on `.xcodeproj`), SC-2 (capability API ↔ `NS…UsageDescription`, conservative
   API→key map over Info.plist + pbxproj), SC-3 (ATS disabled, advisory), SC-8 (export-compliance key
   absent, advisory), SC-4 (targetSdk vs the `ANDROID_TARGET_SDK_FLOOR` constant; unresolved
   indirection ⇒ advisory, never a silent pass), SC-5 (debuggable critical / cleartext advisory).
   **Deferred to a Layer-C follow-up** (higher false-positive risk — used-API↔declaration compares):
   SC-6 (permission declared-vs-used), SC-7 (debug logging in release), SC-9 (Required-Reason API
   compare). **M — first cut done; follow-up pending.**
4. **Layer D — Tier 2 rows** as plan-audit material flags + `test-conventions` shapes (the proven
   8.2.2 pattern). **SC-T2-1 first** — its DP dependency shipped 2026-07-04, so it is unblocked and
   is the highest-value row; SC-T2-2/3/4 follow. **M.**
5. **Layer E — extend the reduced-assurance stamp to Android (safety fix — see Non-goals).**
   `run-summary.sh:35-37` detects only Swift signals (`.swift`/`Package.swift`/`.xcodeproj`,
   `native ios|swiftui` in PROJECT.md/CLAUDE.md), so today a Kotlin/Gradle project sails through
   stamped `assurance: "standard"` — the exact vacuous-green the stamp exists to prevent, on the
   platform with the biggest gap. Extend target detection to Android signals (`.kt`,
   `build.gradle(.kts)`, `AndroidManifest.xml`; `android|kotlin|google play` in
   PROJECT.md/CLAUDE.md), generalize the stamp wording (`reduced (<lang> adapters absent)`), and
   add Android cases to `tests/suites/assurance.sh`. **S — and first in sequence**, because until
   it lands this plan's Non-goals section would otherwise assert a safety property that does not
   exist.

## Implementation inventory — files each layer touches (verified against the engine)

For a fresh-context implementation run: every touch-point below exists today (except the two
`(new)` files) and follows the exact wiring `asvs-sast.sh` proved.

| Layer | Files |
|---|---|
| **E** | `scripts/run-summary.sh:35-43` (extend the target-detection block + generalize the stamp string); `tests/suites/assurance.sh` (Android cases) |
| **A** | `global-project-skills/google-play-submission-requirements/SKILL.md` **(new)** — then re-run `scripts/list-skills.sh --annotate` (the loading-mode annotation is generated, not hand-written) |
| **B** | `global-agents/planning.md` (the iOS target-detection branch → generalize to store target(s); load the matching skill(s); emit store ACs into `acceptance.md`) |
| **C** | `global-hooks/store-compliance.sh` **(new)** — writes `.pipeline/store-compliance.json` `{ran_at, scope, critical, warning, findings[]}`, mirroring `global-hooks/asvs-sast.sh`; `global-agents/security.md` (add to the Stop-hook list in frontmatter ~line 22 **and** a numbered scan step mirroring 4e, so the agent fixes criticals in-loop); `global-hooks/deployment-gate.sh` (deploy-only `critical>0` floor on `store-compliance.json`, absent ⇒ no-op — copy the `asvs-sast.json` floor); `tests/suites/store-compliance.sh` **(new)**; `tests/run-eval.sh:18` (add `store-compliance` to `SUITES` — suites are registered explicitly, not auto-discovered) |
| **D** | `global-agents/plan-audit.md` (SC-T2 material-flag rows, next to the ASVS T2 rows); `global-project-skills/test-conventions/SKILL.md` (the adversarial test shapes) |

Publishing needs nothing extra: `scripts/install-global.sh` copies the whole `global-hooks/` tree
to `~/.claude/hooks/`, so the new hook rides the existing install. SC-4's floor constant must be
**looked up at implementation time** (planning has WebSearch) — Google's required target API level
changes annually and this doc deliberately does not hard-code it.

## Maintenance note (the honest cost)

SC-4's SDK floor and SC-9's Required-Reason API list are **policy-pinned, not code-pinned** — they
change on the stores' schedule, not ours. Keep them as named constants at the top of
`store-compliance.sh` with a `# policy floor — verify annually` marker, and accept that a stale
floor fails **open** (advisory reminder when the constant is >12 months old is cheap insurance).
This is the same class of residual the iOS plan names for OSV's partial SPM coverage: state it,
don't gloss it.

## Non-goals

- **Not guaranteeing store acceptance** — the pipeline designs out known rejection causes; Apple
  and Google still run human review.
- Not building the store upload/CI automation (the Fastlane/Gradle recipes already exist,
  post-merge, and stay there).
- Not screenshot/metadata generation, ASO, or store-listing content.
- Not the Android *build/gate* competence (Kotlin conventions, Semgrep-Kotlin, Gradle smoke) — that
  would be an Android sibling of the iOS side-track and is a separate, larger plan. Until it
  exists, an Android target run **must** carry the same reduced-assurance posture as pre-Layer-3
  iOS — **and today it does not**: `run-summary.sh` detects only Swift signals, so an Android run
  is currently stamped `standard`. Closing that hole is **Layer E** (in scope here, first in
  sequence); the larger Android gate-adapter work is what stays out of scope.

## Sequencing

1. **Layer E** (Android reduced-assurance stamp) — **S**, and first: it corrects an existing false
   safety claim independent of everything else in this plan.
2. **Layer A** (Play skill) + **Layer B** (planning routing) — closes the biggest gap (Play has
   nothing) using only the proven skill+AC channel. No new mechanism.
3. **Layer C** (`store-compliance.sh`) — the deterministic teeth; Windows-buildable, no external
   dependency.
4. **Layer D** (Tier 2 flags) — **SC-T2-1 first** (its DP dependency shipped 2026-07-04; highest
   value), then SC-T2-2/3/4.

## Tie-in

Pointed to from `docs/asvs-determinism-roadmap.md` (pattern source), extends
`docs/ios-swiftui-target-plan.md` Layer 4 (Apple accountability) to Google Play, and makes the
`docs/pipeline-deployment-targets.md` recipes' requirements accountable upstream. Tracked as the
**SC** row in the Track 2 (delivery/ops) table of `pipeline-june-analysis.md` (parallel to L–P,
not on the "10/10" line); flip its ⬜ per layer as the slices land.
