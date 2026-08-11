# Better Ahead iOS Rebrand — Preflight Evidence

Captured on 2026-08-11 before any renderer execution. This evidence separates
the three repository roles and does not use the diagnostic artifacts as a hash
baseline.

## Repository roles and states

| Role | Physical path | HEAD/base | Porcelain SHA-256 | Staging |
| --- | --- | --- | --- | --- |
| Implementation | `/private/tmp/better-ahead-ios.GQgTa0/worktree` | `5317fab1af6d82bcd2886c07149244a2cb2c1765` | clean before Task 1 mutation | empty |
| Git manager | `/Users/eduardohenrique/Developer/bodyflow` | `0ce7f20f22b0e66a6de0544d4a46345181f2fccb` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | empty |
| Diagnostic evidence | `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1` | `03df7894e4cdb37db08351aafb6dd20ad4cb4103` | `4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c` | empty |

The Git-manager and diagnostic paths resolve to distinct physical directories.
The implementation directory is the isolated linked worktree on branch
`codex/better-ahead-ios-rebrand-v1`. The reported combined diagnostic
fingerprint is
`f42572fbb61c48c150a58ea8c144455ecae7cf373f369820a9140f6b58dff45d`;
the deterministic physical-state JSON is the authoritative before/after input.

The diagnostic snapshot contains exactly nine changed regular files, each with
an explicit byte size and physical SHA-256. The Git-manager snapshot contains
zero changed paths. The nine diagnostic payloads were not copied into this
worktree.

## Historical approval pin

- Git baseline commit: `11f5a7cec331d4fc683b6cee5cdf046d3e89623d`
- Tracked manifest: `design/brand/bodyflow-brand-assets.json`
- Historical brand version: `1.0.0`
- Historical approval state: `approved`
- Committed manifest SHA-256: `7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07`
- Physical clean-tree manifest SHA-256: `7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07`

The auditor reads the baseline manifest blob through Git at the pinned commit,
then separately hashes the implementation worktree bytes. It does not read an
expected asset hash from the Git-manager worktree, diagnostic worktree, or any
diagnostic payload.

## Preserved committed bytes

| Historical path | SHA-256 |
| --- | --- |
| `apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/AppIcon.appiconset/bodyflow-app-icon-dark-1024.png` | `361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc` |
| `apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/AppIcon.appiconset/bodyflow-app-icon-default-1024.png` | `400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8` |
| `apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets/AppIcon.appiconset/bodyflow-app-icon-tinted-1024.png` | `10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703` |
| `design/brand/exports/bodyflow-app-icon-dark-1024.png` | `361e42e33a442a961a34d38b61847d88287424d210c17721068fae0c4b10c2fc` |
| `design/brand/exports/bodyflow-app-icon-default-1024.png` | `400f0b86753226cc26e682b073689311d4086a50594b0f61e1b114d901d2dab8` |
| `design/brand/exports/bodyflow-app-icon-tinted-1024.png` | `10c3e7af9f15e4209c79002df05495d9709c3b1c4577ce1f94c129899cc04703` |
| `design/brand/exports/bodyflow-monochrome-132.png` | `0c7ab08351e7d21e6a43f67591c4f2bf040f9a0a9dc030172bad06f4e0776f94` |
| `design/brand/exports/bodyflow-monochrome-44.png` | `6677b8ae8b3a4fe152e48cf6b0e0999121d04e7dc1d9ff8a69213f82a0ab3807` |
| `design/brand/exports/bodyflow-monochrome-88.png` | `8ef78c14517bc118282de9848e7572b0ec405136ead1fcda1a9cacbf3b2534a9` |
| `design/brand/exports/bodyflow-negative-132.png` | `d99817a75434d5ceb752f86a5ac79b0a792d070603be655fc5ddf3ba22167729` |
| `design/brand/exports/bodyflow-negative-44.png` | `27954fd7666e1ba108a7f47e0f351df6c0136c0ef310b32bcc0cfaaba6d657da` |
| `design/brand/exports/bodyflow-negative-88.png` | `a69f656631e3d88fb3e3a2f966a1c1848c92d02924a8364d08a15c1b4a05de8b` |
| `design/brand/exports/bodyflow-symbol-1024.png` | `c1b3211e35b5e14345f90ed40ce26fadaec241bcf8ab621a0ddf0245749088e3` |
| `design/brand/exports/bodyflow-symbol-132.png` | `89eee28f8c122ac7188995a80fc46a8f04578e03f68548f7c568406d04fd29c0` |
| `design/brand/exports/bodyflow-symbol-44.png` | `d1fd4fb65559fd794b1a825a2da48e354011a4bb1551b87c42fccbe749cd7725` |
| `design/brand/exports/bodyflow-symbol-512.png` | `d272fc80e6d0592e67aac29bb752fcd9f516024a6c9793bb18225130a93c3412` |
| `design/brand/exports/bodyflow-symbol-88.png` | `6221f43bf532380524cba828aabe50a75d88c3b658b346250f291c70b87e5f97` |
| `design/brand/exports/bodyflow-symbol-monochrome.svg` | `6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36` |
| `design/brand/exports/bodyflow-symbol-negative.svg` | `a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647` |
| `design/brand/exports/bodyflow-symbol.svg` | `01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9` |
| `design/brand/masters/bodyflow-symbol-monochrome.svg` | `6809439b3b5de85682665d65c26c9088159420eab55b92606878776501d6ce36` |
| `design/brand/masters/bodyflow-symbol-negative.svg` | `a8f1ff09714181cb64d66c3bdf8481ec298d425adca514636c4ffd9d3eeb9647` |
| `design/brand/masters/bodyflow-symbol.svg` | `01343fcb7aa4a52b303bb9a602180f13973c74d2b53704eaa817ce1b9a9f5eb9` |
| `design/brand/source/bodyflow-approved-board.jpg` | `af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7` |

## Classification

```text
preserved: symbol, monochrome symbol, negative symbol, App Icons
new: Better Ahead wordmark, horizontal lockup, launch composition
historical/excluded: BodyFlow wordmark, horizontal lockup, launch composition
```

The approved source board is retained as historical provenance. Better Ahead's
wordmark, horizontal lockup, and launch composition are never inferred as
preserved merely because they reuse the symbol.

## Commands and results

- Reanchored branch/base/staging with `git branch --show-current`,
  `git rev-parse HEAD`, `git status --porcelain=v1 -uall`, and
  `git diff --cached --quiet`: expected branch/base, initially clean, empty
  staging.
- Read the committed historical manifest with
  `git show 11f5a7cec331d4fc683b6cee5cdf046d3e89623d:design/brand/bodyflow-brand-assets.json`
  and hashed both committed and physical bytes: both matched the pinned SHA.
- Compared fresh Git-manager and diagnostic porcelain byte-for-byte with the
  Task 0 captures and checked `git diff --cached --quiet`: both matched and both
  staging areas were empty.
- Ran `better-ahead-worktree-state.mjs --repository` for both source roles:
  diagnostic count `9`, Git-manager count `0`; the NUL porcelain path set and
  physical-file hashes were verified against the JSON.
- Ran `better-ahead-preserved-assets.mjs --emit-historical-map`: `24` stable
  historical source/master/export/AppIcon path-hash records emitted.
- No legacy or Better Ahead renderer was executed.
