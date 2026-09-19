# Performe AI public v1 — final asset approval package

Date: 2026-09-19. Visual direction: **B2 — Warm Performance**.

Status: **PENDING_EXTERNAL_ASSETS**. The direction is approved, but no final
asset byte, hash, public callsite or AppIcon is approved. This directory remains
a documentary approval package; it does not authorize asset integration.

The final mark must be a distinct abstract **P / trajectory / movement** symbol.
It must not reuse or redraw the historical BodyFlow “B”, and it must avoid
generic dumbbells, arrows, chat faces, medical symbols and procedural placeholder
artwork.

## Exact pending deliverables

All paths are relative to this directory. They are required unless explicitly
marked conditional, and none is an approved file merely because it is delivered.

### SVG masters

- `masters/symbol-light.svg`
- `masters/symbol-dark.svg`
- `masters/symbol-mono.svg`
- `masters/symbol-negative.svg`
- `masters/wordmark-light.svg`
- `masters/wordmark-dark.svg`
- `masters/wordmark-mono.svg`
- `masters/lockup-light.svg`
- `masters/lockup-dark.svg`
- `masters/lockup-mono.svg`
- `masters/lockup-negative.svg`

### Native vector exports

- `exports/symbol-light.pdf`
- `exports/symbol-dark.pdf`
- `exports/symbol-mono.pdf`
- `exports/symbol-negative.pdf`
- `exports/wordmark-light.pdf`
- `exports/wordmark-dark.pdf`

### Splash review exports

- `exports/splash-review-compact.png`
- `exports/splash-review-standard.png`
- `exports/splash-review-large.png`

Review the compact 375×667 pt, standard 393×852 pt and large 430×932 pt
compositions at @2x or @3x with the scale recorded. Native integration must use
separate approved vector symbol/wordmark assets, never a screen-sized raster.

### AppIcon candidates

- `exports/appicon-default-1024.png`
- `exports/appicon-dark-1024.png`
- `exports/appicon-tinted-1024.png` — conditional on verified pipeline support
  and separate explicit approval.

Each AppIcon candidate must be an opaque 1024×1024 square with no baked corner
mask, text or UI chrome. Keep the central optical zone deliberate and review the
actual Home Screen result; delivery does not select the icon.

## File-level review requirements

- [ ] Author/source, version and creation tool recorded for every delivered file.
- [ ] Ownership, artwork rights and font licenses verified; no assumed license.
- [ ] Export settings, color space, pixel scale and transparency recorded.
- [ ] Symbol compared beside the historical B and confirmed visually distinct.
- [ ] Light/dark/mono/negative variants preserve geometry and meaning.
- [ ] Symbol silhouette, counters and gaps remain readable at 16/24/32/48 pt.
- [ ] Wordmark is exactly “Performe AI”, with intrinsic bounds and no stretching.
- [ ] Lockup clear space is at least one quarter of the symbol; canvas bounds do
  not force the artwork into an artificial ratio.
- [ ] PDF/SVG intrinsic bounds, transparency and theme contrast are verified.
- [ ] PNG dimensions are checked after delivery; AppIcon candidates are reviewed
  without a baked mask or text.
- [ ] Compact, standard and large Splash compositions are reviewed with no
  artificial launch delay and no screen-sized raster integration.
- [ ] The user explicitly approves each accepted filename and variant. AppIcon
  approval is separate from symbol/wordmark approval.
- [ ] SHA-256 is recorded only after explicit approval. A changed byte invalidates
  that file's previous approval.
- [ ] Exact public callsites are allowlisted only after file approval.
- [ ] Historical tracked brand/catalog bytes remain unchanged unless a later,
  separately authorized migration names the exact file.

## Current optional infrastructure mapping

The app can currently resolve these optional resource names:

- `PerformeAISymbolLightV1`
- `PerformeAISymbolDarkV1`
- `PerformeAISymbolMonoV1`
- `PerformeAISymbolNegativeV1`
- `PerformeAIWordmarkLightV1`
- `PerformeAIWordmarkDarkV1`
- `PerformeAILockupV1`

This is an existing compatibility surface, not approval and not a complete
mapping for every pending master. Any additional catalog mapping must be proposed
and reviewed during P1; it must not be invented in this documentation phase.
Until then, the public fallback remains textual “Performe AI”.

## Approval record policy

`manifest.json` is the machine-readable checklist. While approval is pending:

- `approvalStatus` stays `pending`;
- `approvedFiles` stays empty;
- `publicCallsites` stays empty;
- no author, license, date, hash or approval reference is fabricated.

Final branded Splash, Welcome, shell/Profile identity and the authoritative
eight-screen showcase remain blocked by this gate. Product polish that does not
consume brand bytes may be prepared separately, but the Roberto evaluation
candidate cannot pass final readiness until the applicable files are approved,
integrated and reverified.
