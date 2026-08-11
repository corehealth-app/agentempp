# Better Ahead — Controlled Rebranding Design

**Status:** Written specification approved on 2026-08-11<br>
**Scope:** Brand architecture and controlled migration from BodyFlow to Better Ahead<br>
**Implementation order:** iOS client build, backend public language, release channels

## 1. Objective

Adopt **Better Ahead** as the independent consumer brand while preserving the
approved BodyFlow visual system wherever it remains semantically valid. The
rebranding must remove the former name from every customer-facing surface
without introducing unnecessary migrations in signing, storage, APIs, or other
internal contracts before the client test.

The assistant inside the product is named **Flow**.

## 2. Approved Brand Foundation

### 2.1 Brand architecture

- **Better Ahead** is the public product brand.
- **Flow** is the in-product guide and conversational agent.
- CoreHealth, MPP, and Dr. Roberto are not endorsements or visible elements of
  the consumer identity.
- A corporate or professional name may still appear where ownership,
  contracting, privacy, tax, App Store seller identification, or another legal
  obligation requires it. Those references must not be styled as the product
  brand.

### 2.2 Portuguese

> **Better Ahead**<br>
> Melhor a cada dia.<br>
> Sua jornada personalizada para uma vida mais saudável.<br>
> **Flow**, seu guia em cada etapa.

### 2.3 English

> **Better Ahead**<br>
> Better every day.<br>
> Your personalized journey to a healthier life.<br>
> **Flow**, your guide every step of the way.

### 2.4 Language rules

- Better Ahead and Flow are proper names and are never translated.
- The slogan, descriptor, accessibility labels, onboarding copy, notifications,
  and support copy follow the selected app language.
- “Better” means progress relative to the user's own starting point. It must not
  imply perfection, superiority over other people, guaranteed outcomes, or
  moral judgment.
- The descriptor is used on explanatory surfaces such as onboarding, marketing,
  store metadata, and About. It is not repeated on routine operational screens.
- Flow communicates with clarity, encouragement, calm, and precision. Flow does
  not shame the user, promise a cure, diagnose, or replace a qualified health
  professional.

## 3. Visual Identity Strategy

This is an evolution of the approved identity, not a new visual identity.

### 3.1 Preserve

- The existing abstract, fluid **B** symbol.
- The forward motion/arrow meaning already present in the symbol.
- The text-free App Icon, provided audit confirms it contains no BodyFlow name.
- The approved color system:
  - Teal Green `#006D67`
  - Warm Cream `#F6EFE3`
  - Charcoal `#222528`
  - Muted Coral `#FF7F6B`
  - Soft Gold `#D4AF7A`
- The premium wellness-tech UI direction.
- Space Grotesk for headings and Inter for body copy where the licensed files
  are already present; existing approved fallbacks remain otherwise.

The symbol remains appropriate because its **B** maps to Better and its forward
motion maps directly to Ahead.

If the audit finds former-name text or lettering beyond the approved abstract B
in an otherwise preserved export, that export is reclassified as an intentional
new asset. It must not be described or tested as byte-invariant.

### 3.2 Replace or add

- Replace the BodyFlow wordmark with a Better Ahead wordmark.
- Add a horizontal lockup using the preserved symbol and the new wordmark.
- Add positive, negative, and monochrome variants only when required by an
  existing supported surface.
- Replace customer-facing BodyFlow text in splash, onboarding, settings, About,
  notifications, accessibility labels, and release metadata.

### 3.3 Neutral asset interfaces

Customer-facing code must request semantic assets such as:

- `BrandSymbol`
- `BrandWordmark`
- `BrandLogoHorizontal`
- `AppIcon`

The implementation may retain old file history or internal source provenance,
but views must not depend on product-specific names such as `BodyFlowLogo`.
Former-name wordmarks or lockups may remain only in Git history or in a source
archive that is excluded from every application target and Copy Bundle
Resources phase. They are prohibited from `Assets.xcassets` and the compiled app
bundle.

## 4. Controlled Technical Boundary

### 4.1 Change now

- App display name and every visible brand string.
- PT-BR and English localization values.
- Onboarding and About hierarchy.
- Public agent name and agent introductions.
- Titles and bodies for notifications scheduled locally by the iOS app.
- Asset Catalog interfaces used by views.
- Tests and public-content audits.

Remote push payload templates, scheduled backend messages, emails, and support
responses belong exclusively to Workstream 2. Workstream 1 may audit how the app
displays them, but must not duplicate or rewrite their backend content.

### 4.2 Preserve for stability

Unless a preserved value leaks into a user-facing surface, do not rename it in
the client-test rebranding:

- bundle identifier;
- signing configuration and entitlements;
- target and scheme names used only by development tooling;
- Keychain access groups and App Groups;
- database tables, columns, and migrations;
- API request/response contracts;
- internal analytics event identifiers;
- stable cache keys and persisted preference keys;
- internal automation and deployment identifiers.

These values may be migrated later through dedicated compatibility plans. A
cosmetic mass rename is explicitly out of scope.

### 4.3 Public-leak exception

If any otherwise-preserved identifier is visible in UI, a notification, a URL
shown to users, an exported file, accessibility output, App Store metadata, or a
support response, it must be replaced or wrapped by a Better Ahead public alias.
Compatibility aliases may continue accepting old values internally, but the old
brand must not be advertised.

## 5. Brand Content Architecture

The iOS implementation must provide one authoritative brand-content boundary.
The exact Swift type may follow existing project conventions, but it must expose
the semantic equivalents of:

- product name;
- agent name;
- localized slogan;
- localized descriptor;
- localized agent role line;
- semantic logo and symbol asset names.

Expected resolution flow:

1. The app resolves its supported locale.
2. The localization layer supplies the approved slogan, descriptor, and Flow
   role line.
3. UI surfaces consume the brand boundary instead of hard-coded product names.
4. The symbol and wordmark are selected through semantic asset interfaces.
5. Server-provided copy is audited separately so it cannot reintroduce the old
   public brand.

The brand boundary owns identity only. It must not absorb unrelated UI tokens,
business logic, nutrition calculations, networking, or persistence.

## 6. Fallback and Error Behavior

- If a new wordmark cannot load, render the preserved symbol plus the localized
  text “Better Ahead”. Never fall back to a BodyFlow asset or string.
- If a localized key is missing, use the project's established safe language
  fallback, with Better Ahead and Flow preserved as proper names. Missing keys
  must also fail localization tests.
- If a preserved asset hash changes unexpectedly, stop the asset gate and keep
  all generated files for audit. Do not update expected hashes automatically.
- If a customer-facing old-brand occurrence is found, the public-content gate
  fails unless that exact occurrence has a documented legal justification.
- Unavailable domains or release metadata do not block the local client build;
  they block external distribution when their dedicated release gate runs.

## 7. Asset Integrity Gate

The previous rasterization investigation established that a rerender can change
both bytes and a small number of pixels. This rebranding therefore separates
preserved and new assets.

### 7.1 Baseline resolution

The nine modified files in the original working tree are diagnostic artifacts.
They are never a source of expected hashes and must not be normalized, staged,
discarded, or copied into the implementation worktree.

Before any rebranding edit:

- record the implementation base `HEAD` SHA, complete porcelain status, and
  staging state;
- create the implementation in a clean isolated worktree at that exact commit;
- locate the tracked approved asset manifest at `HEAD` and compare it with the
  committed artifacts, reading committed bytes rather than dirty working-tree
  bytes;
- produce an audit mapping each candidate path to its committed SHA-256, approved
  manifest SHA-256, diagnostic working-tree SHA-256 when present, and intended
  classification as preserved or new;
- stop if the committed artifact and approved manifest disagree, or if no
  tracked approval identifies the intended baseline. Do not infer approval from
  the nine diagnostic files.

### 7.2 Preserved assets

- Use only committed artifacts whose bytes match the tracked approved manifest.
- Copy or reference those exact artifacts without rerendering them.
- Require byte-for-byte equality at the end of the rebranding.
- A pixel-only comparison is additional evidence, not a replacement for the
  required byte invariant.

### 7.3 New assets

- The Better Ahead wordmark and horizontal lockups are intentional new outputs.
- Generate them once with the existing locked project dependencies; do not
  upgrade or replace the render stack during the rebranding.
- Before rendering, commit an environment fingerprint containing the base Git
  SHA, macOS build, CPU architecture, Xcode version, Node version, package
  manager version, lockfile hash, Sharp version, libvips version, librsvg version,
  and exact render command. That exact fingerprint defines the canonical
  environment for these new assets.
- Review them visually before acceptance.
- Store their bytes as the new canonical artifacts and record their hashes in a
  separate manifest.
- A later reproduction may only claim invariance if it matches those canonical
  bytes under the recorded fingerprint. If the fingerprint cannot be recreated,
  use the committed canonical artifacts without rerendering; do not claim
  reproducibility. Any differing output must be reported rather than silently
  replacing the assets.

### 7.4 Forbidden behavior

- Do not rerender the entire approved asset family merely to rename the product.
- Do not overwrite expected hashes as a way to make a failing test pass.
- Do not stage or discard diagnostic artifacts before the audit is complete.

## 8. Workstream Decomposition

The rebranding spans independent systems and must not be implemented as one
unbounded change.

### Workstream 1 — iOS client build

First priority and subject of the first implementation plan:

- central brand boundary;
- PT-BR and English strings;
- notification copy scheduled locally by iOS;
- semantic asset aliases;
- preserved symbol and App Icon;
- new wordmark/lockup integration;
- audit of all iOS public surfaces;
- native tests and Debug/Release builds.

This work is executed in the local macOS/Xcode repository.

### Workstream 2 — backend public language

Separate plan immediately after the iOS surface is stable and required before
the integrated client-test release:

- Flow naming in public agent responses;
- remote push payloads and customer-facing scheduled backend messages;
- public email/support templates;
- prompt/configuration audit;
- compatibility with existing API contracts and stored data.

Internal MPP method or calculation terminology may remain where it is a true
domain concept and is not presented as the consumer brand.

### Workstream 3 — beta distribution, release, and legal channels

Separate external-distribution workstream with two gates:

**Private client beta, only if the chosen test channel requires it:**

- current Apple Developer and App Store Connect requirements verified at
  execution time;
- beta signing and distribution configuration;
- the minimum accurate privacy, support, review, and tester information required
  by the chosen channel;
- explicit authorization before uploading any build.

**Production release, after client approval:**

- formal trademark similarity review and filing strategy;
- domain purchase and DNS;
- App Store Connect name, subtitle, screenshots, privacy details, and seller
  information;
- support and privacy URLs;
- production deep links and associated domains;
- final release-candidate audit.

The preliminary searches performed during naming are directional only and are
not a legal clearance.

## 9. Verification Strategy

### 9.1 Automated checks

- Unit tests for the approved PT-BR and English brand copy.
- Tests proving Better Ahead and Flow are never translated.
- Tests for semantic asset resolution and the text fallback.
- Hash tests for every preserved invariant asset.
- Manifest tests for intentional new wordmark assets.
- A prohibited-content scan over customer-facing source and compiled resources
  for BodyFlow, CoreHealth, MPP-as-brand, and obsolete agent names.
- A narrow allowlist for justified internal or legal occurrences. Each entry
  requires path, reason, and owner.
- Existing focused native tests, including brand-asset and screen-state tests.
- `git diff --check`.

### 9.2 Native build gate

- Focused iOS tests succeed with zero failures and zero skips not already
  explicitly accepted by the project.
- Debug build succeeds.
- Release build succeeds.
- Asset Catalog emits zero warnings.
- Existing inherited warnings are reported exactly and are not misrepresented as
  introduced by the rebranding.

### 9.3 Manual checks

- PT-BR onboarding and primary navigation.
- English onboarding and primary navigation.
- splash, icon, wordmark, Settings, About, notifications, accessibility labels,
  empty/error/offline states, and dark/light appearances.
- visual confirmation that the preserved B symbol remains legible at App Icon
  sizes and that the longer Better Ahead wordmark does not truncate.

## 10. Acceptance Criteria

### 10.1 Workstream 1 completion

The isolated iOS rebranding is complete only when:

1. Better Ahead is the sole public product name.
2. Flow is the sole public agent name.
3. The approved bilingual slogan and descriptor appear in the intended
   explanatory surfaces.
4. No customer-facing BodyFlow occurrence remains.
5. CoreHealth, MPP, and Dr. Roberto appear only where legally required or where
   MPP is an actual internal method term, never as an endorsement of the public
   brand.
6. The approved symbol and text-free App Icon remain byte-identical to the
   committed artifacts that match the tracked approved manifest, never to the
   nine diagnostic working-tree files.
7. New wordmark assets are visually approved and recorded in their own manifest.
8. All focused tests and Debug/Release builds pass.
9. The original worktree state and unrelated user changes are preserved.
10. No push, pull request, external release, domain purchase, or trademark filing
    occurs without its own authorization and gate.

Completing this list does not by itself authorize an integrated client test if
server-generated copy can still expose the old public brand.

### 10.2 Integrated client-test release

The build may be handed to the client for integrated testing only after:

1. Workstream 1 is complete.
2. Workstream 2 is complete for every backend path reachable by the test build.
3. End-to-end checks confirm that server responses, scheduled messages,
   notifications, support copy, and app UI consistently use Better Ahead and
   Flow.
4. The private-beta portion of Workstream 3 is complete if the chosen
   distribution channel requires it.
5. No production publication or App Store submission is implied; the production
   portion of Workstream 3 remains a separate post-approval release gate.

## 11. Explicit Non-Goals

- Redesigning the symbol, icon, palette, typography, or overall UI language.
- Renaming every internal BodyFlow-era identifier.
- Changing nutrition, exercise, habit, or agent business behavior.
- Migrating databases, API contracts, signing identities, or persisted keys.
- Purchasing a domain or filing a trademark.
- Uploading a build to TestFlight or the App Store as part of the rebranding
  implementation itself; distribution requires its separate authorized gate.
- Claiming the product is medically diagnostic or guarantees health outcomes.

## 12. Handoff

After this design is approved in its written form, create a detailed
implementation plan for **Workstream 1 only**. The plan must be suitable for the
local macOS/Xcode session, use the exact repository state found there, preserve
the nine diagnostic asset files until explicitly resolved, establish the
baseline from the clean committed worktree and tracked manifest, and retain the
approved asset-invariance rules above.
