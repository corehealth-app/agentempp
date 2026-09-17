# Performe AI public v1 — external asset approval checklist

Status: **PENDING_EXTERNAL_ASSETS**. Direction approved; no final bytes supplied or approved. This package contains infrastructure and documentation only. It does not complete Slice 1, authorize S1.3, select an icon, or replace historical artwork.

Authority: approved UI/UX implementation plan §5, S1.1 and S1.2. Final files must be delivered by an external designer or a separately authorized creative operation. Do not render the historical family or generate placeholder artwork.

## Exact pending deliverables

All paths below are relative to this directory and are **pending**, not existing files.

| Family | Named masters/review exports | Requirements |
| --- | --- | --- |
| Symbol | `masters/symbol-light.svg`, `masters/symbol-dark.svg`, `masters/symbol-mono.svg`, `masters/symbol-negative.svg`; corresponding vector PDFs under `exports/`; `exports/symbol-light-1024.png`, `exports/symbol-dark-1024.png`, `exports/symbol-mono-1024.png`, `exports/symbol-negative-1024.png` | Near-square abstract P/rising trajectory, distinct from the historical B. Review PNGs 1024×1024; optical sheets at 16/24/32/48 pt. |
| Wordmark | `masters/wordmark-light.svg`, `masters/wordmark-dark.svg`, `masters/wordmark-mono.svg`; corresponding vector PDFs and review sheets | Exact “Performe AI”; intrinsic horizontal bounds, never stretched. Review widths 140/240 pt. |
| Lockup | `masters/lockup-light.svg`, `masters/lockup-dark.svg`, `masters/lockup-mono.svg`, `masters/lockup-negative.svg`; corresponding vector PDFs and review PNGs | Review canvas 1600×400, clear space ≥¼-symbol; canvas is not a forced artwork ratio. |
| Splash review | `exports/splash-review-standard.png`, `exports/splash-review-compact.png`, `exports/splash-review-large.png` | Standard 1179×2556 px; compact 375×667 and large 430×932 logical at 2×. Native integration would use separate approved negative symbol/wordmark PDFs at 96 pt/≤240 pt intrinsic width, never a screen-sized image. |
| AppIcon | `exports/appicon-default-1024.png`, `exports/appicon-dark-1024.png`, `exports/appicon-tinted-1024.png` | Opaque 1024×1024 squares; no baked corner mask or text. Proposed central 70% optical zone; Home Screen review. Tinted only if the existing pipeline supports it and separately approved. |

## Review gates — not yet satisfied

- [ ] Designer/source author, version, source ownership and export settings documented for each file.
- [ ] Artwork and font licenses verified; no assumed rights. Optional photography defaults to none without rights.
- [ ] Distinct P/trajectory reviewed beside the old B; no recycled swooshes or medical/arrow/dumbbell/chat-face substitution.
- [ ] Light/dark/mono/negative geometry and meaning consistent; mono silhouette, counters and gaps readable at small sizes.
- [ ] Native optical sizes 16/24/32/48 pt reviewed, plus wordmark widths 140/240 pt and lockup clear space ≥¼-symbol.
- [ ] Actual role/theme contrast, transparency, clear space and intrinsic vector/PDF bounds verified.
- [ ] Each named PNG dimension checked with `sips` only after delivery; native catalog import settings verified only after approval.
- [ ] User explicitly approves named exact files/variants and the review sheets. AppIcon selection requires separate explicit approval.
- [ ] Actual approval time/reference and SHA-256 of **each approved master/export** recorded in the manifest after approval. A hash is byte identity, not approval; any changed byte invalidates its approval.
- [ ] Exact public callsite allowlist recorded after approval; currently empty.
- [ ] Before/after S1.3, historical tracked brand/catalog files compared with planning baseline `7ab3e657` and old-family hashes remain identical. Only new approved files are eligible.

## Infrastructure mapping

Optional enum resources: `PerformeAISymbolLightV1`, `PerformeAISymbolDarkV1`, `PerformeAISymbolMonoV1`, `PerformeAISymbolNegativeV1`, `PerformeAIWordmarkLightV1`, `PerformeAIWordmarkDarkV1`, `PerformeAILockupV1`.

No resource currently exists or is selected. Public fallback remains the existing textual “Performe AI”. Manifest remains `pending`, with empty `approvedFiles` and `publicCallsites`; no invented authors, licenses, hashes, dates or approval records. Missing final assets do not block the separately authorized Flow/Auth work. S1.3 remains outside Batch 2.
