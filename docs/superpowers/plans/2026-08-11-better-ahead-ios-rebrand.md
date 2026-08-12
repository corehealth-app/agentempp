# Better Ahead iOS Controlled Rebrand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace every customer-facing BodyFlow identity in the native iOS
client with Better Ahead and Flow, provide complete `pt-BR` and English client
localization, preserve the approved symbol and App Icons byte for byte, and
integrate visually approved Better Ahead wordmark assets without changing
stable technical contracts.

**Architecture:** Add one neutral `BrandIdentity`/`BrandAsset` boundary and one
String Catalog-backed localization boundary. Keep target, scheme, module,
bundle identifier, API contracts, persistence keys, telemetry identifiers, and
server-owned domain values unchanged. Use one explicit source `Info.plist` to
decouple the two public bundle names from the preserved technical
`PRODUCT_NAME`, with one exact synchronized-root membership exception. Preserve
the approved BodyFlow asset manifest as historical provenance; create a
separate, narrow Better Ahead manifest and renderer that can only write new
wordmark/lockup/review outputs. Publish those outputs as one immutable,
  version-addressed bundle with a single exclusive directory rename; the root
  manifest is updated afterward as an ordinary reviewed Git patch that points
  downstream tasks at that bundle, never by the transactional renderer.
Perform all implementation in a clean isolated worktree based on the approved
asset tip. The clean Git-manager repository creates that worktree; the separate
Mac worktree that holds the nine diagnostic files is read-only evidence.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XCTest/XCUIAutomation, Xcode
String Catalogs, Asset Catalogs, Node.js 22+, Corepack invoking exactly pnpm
10.33.2, Node test runner, Sharp 0.34.5 inside the already pinned Linux/amd64
renderer, shell, `plutil`, and `xcrun assetutil`.

**Authoritative specification:**
`docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md`

## Fixed Decisions And Safety Boundaries

- Public product name: **Better Ahead**.
- Public agent/guide name: **Flow**.
- Portuguese slogan: **Melhor a cada dia.**
- English slogan: **Better every day.**
- Portuguese descriptor: **Sua jornada personalizada para uma vida mais saudável.**
- English descriptor: **Your personalized journey to a healthier life.**
- Portuguese role line: **Flow, seu guia em cada etapa.**
- English role line: **Flow, your guide every step of the way.**
- Preserve target, scheme, module, and source root named `BodyFlow`.
- Preserve `PRODUCT_BUNDLE_IDENTIFIER = com.bodyflow.app` and the test bundle
  identifiers.
- Preserve API payload names such as `using_bodyflow`, stored keys beginning
  with `bodyflow.`, internal `Coach*`/`Mascot*` types, telemetry event names,
  accessibility identifiers, and test launch arguments unless they are shown
  to the user.
- `Focus`, `Impulse`, and `Zen` may remain public only as named styles of Flow;
  public labels must establish that relationship. Their display names are
  stable in both languages and their descriptions are client-owned localized
  copy keyed by the existing persona code. Raw server `name`/`description`
  fields and internal enum/wire values remain unchanged but are not rendered
  for these three known controls.
- No database, API, signing, entitlement, deployment, TestFlight, App Store,
  push-provider, email, or support-system change belongs to this plan.
- There is no local iOS notification scheduler at the approved base. Record the
  local-notification portion as audited/not applicable; do not invent one.
- Exact committed symbol colors and gradients outrank prose/token
  approximations for invariant assets. Compose new vector lockups with colors
  declared by the historical asset manifest; leave the existing
  `BodyFlowColor` UI tokens unchanged. Do not recolor the symbol to reconcile a
  one-channel hex difference.
- Do not edit `project.pbxproj` to register new Swift or resource files because
  the project uses file-system-synchronized groups. Edit it only for the English
  region declaration, changing `SWIFT_EMIT_LOC_STRINGS` from `YES` to `NO`,
  temporarily setting the two public `INFOPLIST_KEY_CFBundle*` diagnostic inputs
  before the generated-plist baseline and removing them before Task 2 staging,
  setting `GENERATE_INFOPLIST_FILE = NO` and the explicit `INFOPLIST_FILE` in the
  two application configurations, removing only the superseded app
  `INFOPLIST_KEY_*` entries migrated into that source file, and adding the one
  exact synchronized-membership exception that prevents that plist from
  entering Copy Bundle Resources. No other group, target, phase, file-reference,
  or build-setting edit is authorized.
- Do not invoke legacy `brand:render` or `brand:review` in write mode during the
  rebrand. Those commands reconstruct all BodyFlow outputs and the entire Asset
  Catalog. Legacy `brand:test`, `brand:validate`, and `brand:render:check` are
  valid only as a read-only preflight against an untouched snapshot of the
  approved historical tree.
- Better Ahead renderer output is never installed as independent live files.
  The only visual commit point is one same-filesystem, FD-anchored,
  no-replace rename of the complete sealed directory
  `design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>`. That immutable bundle
  contains all three SVGs, all three review PNGs, and its receipt. No `current`
  symlink, mutable alias, wildcard resolver, or flat `exports`/`review` output
  is permitted. The root Better Ahead manifest is a reviewed source registry,
  not a receipt and not the commit point; `finish`/`recover` never mutate it.
  Downstream tasks resolve the exact committed bundle path recorded there only
  after the candidate bundle and manifest patch are committed together.
- The repository root's exact `packageManager` contract is
  `pnpm@10.33.2`. Every plan command invokes it explicitly as
  `corepack pnpm@10.33.2`; a globally installed `pnpm`, `corepack use`,
  `corepack up`, `corepack install -g`, `corepack enable`, and
  `--dangerously-allow-all-builds` are outside this plan. The committed
  `onlyBuiltDependencies` policy remains authoritative.
- The first Better Ahead fingerprint and render require Docker Desktop 4.80.0
  or newer and its local Linux engine. Every renderer-side Docker invocation
  explicitly uses `docker --context desktop-linux`; the runner never relies on
  an ambient/default context, and every build/run passes literal
  `--platform=linux/amd64`. The resolved CLI and the Buildx, Desktop, and
  Offload CLI plugins must resolve inside Docker Desktop's application bundle.
  `cliPluginsExtraDirs` must be empty; user/system candidates are allowed only
  when their realpath is the exact bundled binary, and every non-bundled shadow
  is forbidden. Builds use the literal
  `buildx build --builder default` path and its context-bound `docker` driver. A
  static/Homebrew client, remote/cloud daemon, Docker Offload route,
  Colima, OrbStack, Podman, or a host-native Sharp renderer is not an equivalent
  environment. Exit `78` can preserve already committed canonical outputs
  without claiming reproducibility; it cannot create the first
  `environment.json` or the first Better Ahead outputs.

## Confirmed Baseline

- Approved iOS/asset tip:
  `11f5a7cec331d4fc683b6cee5cdf046d3e89623d` on
  `codex/bodyflow-ios-brand-design-system-v1`.
- Approved historical manifest:
  `design/brand/bodyflow-brand-assets.json`, state `1.0.0 / approved`.
- Design specification tip at plan time:
  `326ae714ae15a1f722acf01c0f2297ea8c5129cd` on
  `codex/better-ahead-rebranding-design`.
- Those two tips diverge at
  `b5f1d1c31993e160c0c9d7bc32c0dca77094b62f`; the implementation branch must
  start at the approved iOS tip and explicitly add this specification and plan.
  Never treat the design branch as if it already contained the iOS asset tree.
- Previously verified native environment: Xcode 26.6 (`17F113`), Swift 6.3.3,
  macOS 26.5.2 (`25F84`), iPhone 17 Pro simulator, iOS 26.5 (`23F77`), UDID
  `27291590-659D-4A29-8F45-CA5CA2D154F9`.
- Git-manager repository (clean at the corrected preflight):
  `/Users/eduardohenrique/Developer/bodyflow`, observed HEAD
  `0ce7f20f22b0e66a6de0544d4a46345181f2fccb`. Use it only for fetch, Git object
  lookup, and isolated-worktree creation; do not treat it as diagnostic input.
- Diagnostic worktree:
  `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1`, required
  HEAD `03df7894e4cdb37db08351aafb6dd20ad4cb4103`. It contains the nine diagnostic
  asset changes, with empty staging. They are evidence, not the baseline, and
  must remain unstaged and physically untouched. The interrupted preflight
  reported combined diagnostic fingerprint
  `f42572fbb61c48c150a58ea8c144455ecae7cf373f369820a9140f6b58dff45d`;
  record it as audit metadata, while the deterministic physical-state JSON is
  the authoritative before/after comparison. The previously preserved exact
  porcelain SHA-256 is
  `4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c`.
- `GIT_REPO` and `DIAGNOSTIC_REPO` are distinct required roles throughout Tasks
  0, 1, and 10. A single path may never satisfy both roles.

## Preserved Asset Contract

The implementation must resolve these values from committed bytes at the
approved base and prove them again after every asset-affecting task. The short
prefixes below are orientation only; the tracked historical manifest is the
authority for the complete SHA-256 values.

| Asset family | Approved SHA-256 prefix | Classification |
| --- | --- | --- |
| Symbol SVG | `01343fcb` | preserved, byte-invariant |
| Symbol PNG 44/88/132/512/1024 | `d1fd4fb6`, `6221f43b`, `89eee28f`, `d272fc80`, `c1b3211e` | preserved if copied or retained |
| Monochrome SVG | `6809439b` | preserved, byte-invariant |
| Monochrome PNG 44/88/132 | `6677b8ae`, `8ef78c14`, `0c7ab083` | preserved if copied or retained |
| Negative SVG | `a8f1ff09` | preserved, byte-invariant |
| Negative PNG 44/88/132 | `27954fd7`, `a69f6566`, `d99817a7` | preserved if copied or retained |
| App Icon default/dark/tinted | `400f0b86`, `361e42e3`, `10c3e7af` | preserved, byte-invariant |
| BodyFlow wordmark/horizontal/launch | `57503318`, `cb88d3af`, `06580ac9` | historical only; prohibited from app target |

The Better Ahead wordmark, horizontal lockup, and launch composition are new
assets. Never compare them to the last three historical hashes or call them
invariant.

---

### Task 0: Create The Isolated Implementation Worktree And Prove The Base

**Files:**

- Read only: clean Git-manager repository
- Read only: separate diagnostic worktree and its nine diagnostic files
- Read only: `design/brand/bodyflow-brand-assets.json` at the approved base
- Create outside the repository: preflight command logs and status snapshots
- Create branch: `codex/better-ahead-ios-rebrand-v1`

**Step 1: Capture both source worktrees without changing either**

Run from the Mac session:

```bash
set -euo pipefail
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
GIT_REPO_PHYSICAL=$(cd -- "$GIT_REPO" && pwd -P)
DIAGNOSTIC_REPO_PHYSICAL=$(cd -- "$DIAGNOSTIC_REPO" && pwd -P)
test "$GIT_REPO_PHYSICAL" != "$DIAGNOSTIC_REPO_PHYSICAL"
test "$(git -C "$GIT_REPO" rev-parse --show-toplevel)" = "$GIT_REPO_PHYSICAL"
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse --show-toplevel)" = "$DIAGNOSTIC_REPO_PHYSICAL"
PREFLIGHT_POINTER=/tmp/better-ahead-preflight-root.txt
test ! -e "$PREFLIGHT_POINTER"
PREFLIGHT_ROOT=$(mktemp -d /tmp/better-ahead-preflight.XXXXXX)
git -C "$GIT_REPO" rev-parse HEAD | tee "$PREFLIGHT_ROOT/git-repo-head.txt"
test "$(tr -d '\n' < "$PREFLIGHT_ROOT/git-repo-head.txt")" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" status --porcelain=v1 -uall \
  | tee "$PREFLIGHT_ROOT/git-repo-status.before.txt"
git -C "$GIT_REPO" diff --cached --quiet
test ! -s "$PREFLIGHT_ROOT/git-repo-status.before.txt"
shasum -a 256 "$PREFLIGHT_ROOT/git-repo-status.before.txt" \
  | awk '{print $1}' | tee "$PREFLIGHT_ROOT/git-repo-status.before.sha256"
git -C "$DIAGNOSTIC_REPO" rev-parse HEAD \
  | tee "$PREFLIGHT_ROOT/diagnostic-head.txt"
test "$(tr -d '\n' < "$PREFLIGHT_ROOT/diagnostic-head.txt")" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  | tee "$PREFLIGHT_ROOT/diagnostic-status.before.txt"
git -C "$DIAGNOSTIC_REPO" diff --cached --quiet
DIAGNOSTIC_COUNT=$(wc -l < "$PREFLIGHT_ROOT/diagnostic-status.before.txt" \
  | tr -d '[:space:]')
test "$DIAGNOSTIC_COUNT" = "9"
shasum -a 256 "$PREFLIGHT_ROOT/diagnostic-status.before.txt" \
  | awk '{print $1}' | tee "$PREFLIGHT_ROOT/diagnostic-status.before.sha256"
test "$(tr -d '\n' < "$PREFLIGHT_ROOT/diagnostic-status.before.sha256")" \
  = "4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c"
printf '%s\n' "$PREFLIGHT_ROOT" > "$PREFLIGHT_POINTER"
```

Expected: `GIT_REPO` is at the exact reported clean HEAD with empty staging;
`DIAGNOSTIC_REPO` is at the required diagnostic HEAD with exactly nine
porcelain entries and empty staging. The pointer is written only after every
capture assertion succeeds. Do not clean, stash, restore, checkout, stage, or
copy any diagnostic file.

**Step 2: Verify the approved remote tip**

```bash
set -euo pipefail
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
git -C "$GIT_REPO" fetch origin codex/bodyflow-ios-brand-design-system-v1
test "$(git -C "$GIT_REPO" rev-parse origin/codex/bodyflow-ios-brand-design-system-v1)" \
  = "11f5a7cec331d4fc683b6cee5cdf046d3e89623d"
```

Expected: equality succeeds. If the remote tip differs, stop and report both
SHAs; do not silently choose a newer implementation base.

**Step 3: Create a clean worktree at that exact commit**

```bash
set -euo pipefail
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
IMPLEMENTATION_POINTER=/tmp/better-ahead-implementation-repo.txt
test ! -e "$IMPLEMENTATION_POINTER"
IMPLEMENTATION_ROOT=$(mktemp -d /tmp/better-ahead-ios.XXXXXX)
EXISTING_BRANCH=$(git -C "$GIT_REPO" show-ref --verify --hash \
  refs/heads/codex/better-ahead-ios-rebrand-v1 2>/dev/null || test "$?" -eq 1)
test -z "$EXISTING_BRANCH"
git -C "$GIT_REPO" worktree add \
  -b codex/better-ahead-ios-rebrand-v1 \
  "$IMPLEMENTATION_ROOT/worktree" \
  11f5a7cec331d4fc683b6cee5cdf046d3e89623d
git -C "$IMPLEMENTATION_ROOT/worktree" status --porcelain=v1 -uall
git -C "$IMPLEMENTATION_ROOT/worktree" diff --cached --quiet
IMPLEMENTATION_REPO="$IMPLEMENTATION_ROOT/worktree"
printf '%s\n' "$IMPLEMENTATION_REPO" > "$IMPLEMENTATION_POINTER"
cd -- "$IMPLEMENTATION_REPO"
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git rev-parse HEAD)" = "11f5a7cec331d4fc683b6cee5cdf046d3e89623d"
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
test -z "$(git status --porcelain=v1 -uall)"
```

Expected: the isolated worktree prints no porcelain output and has empty
staging. Keep this worktree for the full plan. Record the physical
`GIT_REPO`, `DIAGNOSTIC_REPO`, and `IMPLEMENTATION_REPO` paths in preflight
evidence. At the start of every later task and every resumed shell session,
`cd` to that recorded path and assert its
top-level path and branch before any relative command. Never infer the
implementation repository from the current terminal directory.

**Step 4: Add the approved design documents explicitly**

Bring these exact files from the approved planning branch into the isolated
worktree without merging the unrelated design-branch history:

```text
docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md
docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
```

The execution handoff supplies an exact 40-character `DOCUMENTATION_COMMIT` and
makes that commit reachable through a separately authorized read-only fetch or
Git bundle. Do not reconstruct either document from chat text. Verify the
commit object and blob identity, then restore only the two absent documentation
paths:

```bash
set -euo pipefail
IMPLEMENTATION_REPO=$(tr -d '\n' < /tmp/better-ahead-implementation-repo.txt)
cd -- "$IMPLEMENTATION_REPO"
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
: "${DOCUMENTATION_COMMIT:?execution handoff must supply the exact documentation commit}"
test "${#DOCUMENTATION_COMMIT}" -eq 40
test -z "$(printf '%s' "$DOCUMENTATION_COMMIT" | tr -d '0-9a-f')"
git cat-file -e "$DOCUMENTATION_COMMIT^{commit}"
for DOCUMENT_PATH in \
  docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md \
  docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md; do
  test ! -e "$DOCUMENT_PATH"
  git cat-file -e "$DOCUMENTATION_COMMIT:$DOCUMENT_PATH"
done
git restore --source="$DOCUMENTATION_COMMIT" -- \
  docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md \
  docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
for DOCUMENT_PATH in \
  docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md \
  docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md; do
  test "$(git hash-object "$DOCUMENT_PATH")" \
    = "$(git rev-parse "$DOCUMENTATION_COMMIT:$DOCUMENT_PATH")"
done
rg -F '**Status:** Written specification approved on 2026-08-11' \
  docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md
rg -F '11f5a7cec331d4fc683b6cee5cdf046d3e89623d' \
  docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
git add docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md \
  docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
git commit -m "docs(brand): add Better Ahead iOS rebrand plan"
```

If the exact documentation commit is not reachable, stop before restoring or
staging anything and request the approved transport. The commit and its two
verified blob IDs are the content checksum.

**Step 5: Install the locked workspace dependencies**

```bash
set -euo pipefail
LOCKFILE_BEFORE=$(shasum -a 256 pnpm-lock.yaml | awk '{print $1}')
node --version
test "$(node -p 'require("./package.json").packageManager')" = "pnpm@10.33.2"
command -v corepack
test "$(corepack pnpm@10.33.2 --version)" = "10.33.2"
corepack pnpm@10.33.2 install --frozen-lockfile
test "$(shasum -a 256 pnpm-lock.yaml | awk '{print $1}')" = "$LOCKFILE_BEFORE"
git diff --exit-code -- pnpm-lock.yaml package.json scripts/package.json \
  pnpm-workspace.yaml
test -z "$(git status --porcelain=v1 -uall)"
```

Expected: the locked install succeeds, provides Sharp to the scripts workspace,
and changes no tracked dependency declaration or lockfile.

**Step 6: Run the historical read-only gate**

```bash
corepack pnpm@10.33.2 --filter @mpp/scripts brand:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:validate
corepack pnpm@10.33.2 --filter @mpp/scripts brand:render:check
git diff --check
```

Expected: all legacy checks pass and `brand:render:check` says the historical
BodyFlow render is byte-identical. It must not alter tracked files. If Docker is
unavailable, record that condition but continue only after direct committed
byte-to-manifest verification in Task 1 succeeds; never run a host-native
renderer as a substitute.

Before **every** Task 1-10 starts (and after any shell/session resume), run this
mandatory re-anchoring preamble:

```bash
set -euo pipefail
IMPLEMENTATION_REPO=$(tr -d '\n' < /tmp/better-ahead-implementation-repo.txt)
cd -- "$IMPLEMENTATION_REPO"
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
git merge-base --is-ancestor \
  11f5a7cec331d4fc683b6cee5cdf046d3e89623d HEAD
git diff --cached --quiet
test -z "$(git status --porcelain=v1 -uall)"
test "$(node -p 'require("./package.json").packageManager')" = "pnpm@10.33.2"
command -v corepack
test "$(corepack pnpm@10.33.2 --version)" = "10.33.2"
```

Expected: all assertions pass before a task mutates anything. A failure stops
that task; never continue relative-path commands from either source worktree.

---

### Task 1: Lock The Better Ahead Provenance And Preserved-Byte Gate

**Files:**

- Create: `design/brand/better-ahead-brand-assets.json`
- Create: `scripts/brand/better-ahead-preserved-assets.mjs`
- Create: `scripts/brand/better-ahead-preserved-assets.test.mjs`
- Create: `scripts/brand/better-ahead-worktree-state.mjs`
- Create: `scripts/brand/better-ahead-worktree-state.test.mjs`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.txt`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.sha256`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-head.before.txt`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-worktree.before.json`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.txt`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.sha256`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-head.before.txt`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-worktree.before.json`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preserved-assets.before.json`
- Modify: `scripts/package.json`

**Interfaces:**

- `betterAheadPreservedAssets(root)` returns the historical manifest entry,
  committed hash, physical hash, future neutral-catalog path, and
  classification for each preserved artifact.
- `brand:better-ahead:baseline` performs a read-only check.
- `brand:better-ahead:catalog` adds a physical bundle-source check once the
  semantic catalog exists. It requires the exact historical hashes for
  `BrandSymbol`, `BrandMonochrome`, and `BrandNegative`; the approved Better
  Ahead root manifest's exact immutable bundle/receipt hashes for
  `BrandWordmark`, `BrandLogoHorizontal`, and `BrandLaunch`; and the baseline
  bytes plus `Contents.json` for every AppIcon payload. It never scans the
  bundle parent or follows an alias. Missing, extra, misnamed, rejected, or
  re-encoded files fail the gate.
- `better-ahead-worktree-state.mjs --repository PATH` parses NUL-delimited
  porcelain and emits deterministic JSON containing each changed/untracked
  relative path, status, file type, byte size, and SHA-256 (or explicit missing
  state). It emits no timestamp or absolute path so before/after output can be
  compared byte for byte.
- `--exclude-exact RELATIVE_PATH` may exclude one explicitly named path for a
  controlled mutation check; it rejects absolute paths, traversal, globs, and
  directory-wide exclusions.
- `--require-only-prefix RELATIVE_DIRECTORY` fails unless every reported path
  is a regular file below that one non-root directory; it is used only to prove
  Task 10 has evidence changes and no application/tooling changes.
- The Better Ahead manifest is separate from
  `bodyflow-brand-assets.json`; it never rewrites historical approval.

**Step 1: Write failing baseline tests**

Cover all of the following:

```javascript
test("historical approved manifest is the only baseline", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);
  assert.equal(audit.historicalBrandVersion, "1.0.0");
  assert.equal(audit.historicalApprovalState, "approved");
  assert.equal(audit.mismatches.length, 0);
});

test("wordmark lockups are never classified as preserved", async () => {
  const audit = await betterAheadPreservedAssets(repositoryRoot);
  assert.deepEqual(
    audit.intentionalNewRoles.toSorted(),
    ["horizontal", "launch", "wordmark"],
  );
});
```

Also require exact full SHA-256 equality for the symbol, monochrome symbol,
negative symbol, all corresponding declared PNG exports, and all three App Icon
exports/copies. Require each future catalog alias to be neutral. Reject a
missing historical manifest, non-approved state, diagnostic path, wildcard
allowance, or changed expected hash.

Pin the historical manifest independently of any Better Ahead declaration:

```text
path: design/brand/bodyflow-brand-assets.json
Git baseline: 11f5a7cec331d4fc683b6cee5cdf046d3e89623d
SHA-256: 7f729f2221f95c6023fb98a01db4eae469c17568725eb96b6b5ead2ab2448b07
```

The auditor reads the baseline blob with Git, hashes the current clean-tree
file, and requires both to equal this pinned value. It must not learn the
expected value from `better-ahead-brand-assets.json`.

Test the worktree-state helper with spaces, non-ASCII paths, untracked files,
modified files, symlinks, deletion, and rename records. Its parser must consume
`git status --porcelain=v1 -z -uall`; line-delimited parsing is prohibited.
Also prove exact-path exclusion ignores only that file and rejects wildcard or
ancestor-directory exclusions. Prove the required-prefix mode rejects a root,
traversal, a sibling path, and symlinks.

**Step 2: Run RED**

```bash
node --test scripts/brand/better-ahead-preserved-assets.test.mjs
```

Expected: FAIL because the audit module and Better Ahead manifest do not exist.

**Step 3: Implement the minimal read-only audit**

The new manifest begins at schema version 1, product `Better Ahead`, version
`1.0.0-candidate.1`, and approval state `candidate`. It records:

```text
historical_manifest.path
historical_manifest.sha256
historical_manifest.brand_version
historical_manifest.approval_state
preserved[].role
preserved[].historical_path
preserved[].historical_sha256
preserved[].neutral_catalog_path (when bundled)
intentional_new_roles[]
new_assets[] (initially empty)
```

Read baseline bytes from `IMPLEMENTATION_REPO` only. Never read an expected
asset hash from `GIT_REPO`, `DIAGNOSTIC_REPO`, or the nine diagnostic files.
Fail closed before writing anything if the tracked manifest and physical bytes
disagree.

Add these scripts to `scripts/package.json`:

```json
{
  "brand:better-ahead:baseline": "node brand/better-ahead-preserved-assets.mjs --check",
  "brand:better-ahead:test": "node --test brand/better-ahead-preserved-assets.test.mjs brand/better-ahead-worktree-state.test.mjs"
}
```

**Step 4: Record preflight evidence**

The evidence file records all three repository roles/paths, both source
HEADs/status checksums/staging states, the reported diagnostic fingerprint, the
exact implementation base SHA, historical manifest SHA, every complete
preserved SHA-256, isolated worktree path, commands/results, and this
classification:

```text
preserved: symbol, monochrome symbol, negative symbol, App Icons
new: Better Ahead wordmark, horizontal lockup, launch composition
historical/excluded: BodyFlow wordmark, horizontal lockup, launch composition
```

Do not copy the nine diagnostic files into evidence or the isolated worktree.
Copy only the captured diagnostic and Git-manager HEAD/status/checksum records,
then capture both physical worktree states with their correct repository roles:

```bash
set -euo pipefail
PREFLIGHT_ROOT=$(tr -d '\n' < /tmp/better-ahead-preflight-root.txt)
EVIDENCE_ROOT=docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
test "$(cd -- "$GIT_REPO" && pwd -P)" != "$(cd -- "$DIAGNOSTIC_REPO" && pwd -P)"
test -d "$PREFLIGHT_ROOT"

test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
test "$(tr -d '\n' < "$PREFLIGHT_ROOT/diagnostic-head.txt")" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$PREFLIGHT_ROOT/diagnostic-status.task1.txt"
cmp "$PREFLIGHT_ROOT/diagnostic-status.before.txt" \
  "$PREFLIGHT_ROOT/diagnostic-status.task1.txt"
git -C "$DIAGNOSTIC_REPO" diff --cached --quiet

test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
test "$(tr -d '\n' < "$PREFLIGHT_ROOT/git-repo-head.txt")" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" status --porcelain=v1 -uall \
  > "$PREFLIGHT_ROOT/git-repo-status.task1.txt"
cmp "$PREFLIGHT_ROOT/git-repo-status.before.txt" \
  "$PREFLIGHT_ROOT/git-repo-status.task1.txt"
git -C "$GIT_REPO" diff --cached --quiet

mkdir -p "$EVIDENCE_ROOT"
cp -- "$PREFLIGHT_ROOT/diagnostic-status.before.txt" \
  "$EVIDENCE_ROOT/diagnostic-status.before.txt"
cp -- "$PREFLIGHT_ROOT/diagnostic-status.before.sha256" \
  "$EVIDENCE_ROOT/diagnostic-status.before.sha256"
cp -- "$PREFLIGHT_ROOT/diagnostic-head.txt" \
  "$EVIDENCE_ROOT/diagnostic-head.before.txt"
cp -- "$PREFLIGHT_ROOT/git-repo-status.before.txt" \
  "$EVIDENCE_ROOT/git-repo-status.before.txt"
cp -- "$PREFLIGHT_ROOT/git-repo-status.before.sha256" \
  "$EVIDENCE_ROOT/git-repo-status.before.sha256"
cp -- "$PREFLIGHT_ROOT/git-repo-head.txt" \
  "$EVIDENCE_ROOT/git-repo-head.before.txt"
test "$(shasum -a 256 "$EVIDENCE_ROOT/diagnostic-status.before.txt" | awk '{print $1}')" \
  = "$(tr -d '\n' < "$EVIDENCE_ROOT/diagnostic-status.before.sha256")"
test "$(shasum -a 256 "$EVIDENCE_ROOT/git-repo-status.before.txt" | awk '{print $1}')" \
  = "$(tr -d '\n' < "$EVIDENCE_ROOT/git-repo-status.before.sha256")"
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository "$DIAGNOSTIC_REPO" \
  > "$EVIDENCE_ROOT/diagnostic-worktree.before.json"
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository "$GIT_REPO" \
  > "$EVIDENCE_ROOT/git-repo-worktree.before.json"
```

Verify the diagnostic JSON enumerates the same nine paths reported by diagnostic
porcelain and contains a physical SHA-256 for every present regular file.
Verify the Git-manager JSON contains zero changed-path entries because that
worktree is clean. These evidence files are stable Task 10 comparison inputs
even if the shell session or `/tmp` directory no longer exists.

Also write the deterministic committed-byte map used by the final invariant
comparison:

```bash
node scripts/brand/better-ahead-preserved-assets.mjs --emit-historical-map \
  > docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preserved-assets.before.json
```

`--emit-historical-map` contains only the stable historical
source/master/export and AppIcon baseline paths/hashes, sorted
deterministically. It does not add future semantic alias paths; those are
checked independently by `brand:better-ahead:catalog`, so the Task 1 and Task
10 maps have identical schemas.

**Step 5: Run GREEN and commit**

```bash
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
git diff --check
git add design/brand/better-ahead-brand-assets.json \
  scripts/brand/better-ahead-preserved-assets.mjs \
  scripts/brand/better-ahead-preserved-assets.test.mjs \
  scripts/brand/better-ahead-worktree-state.mjs \
  scripts/brand/better-ahead-worktree-state.test.mjs \
  scripts/package.json \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.txt \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.sha256 \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-head.before.txt \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-worktree.before.json \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.txt \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.sha256 \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-head.before.txt \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-worktree.before.json \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preserved-assets.before.json
git commit -m "test(brand): lock Better Ahead preserved asset baseline"
```

---

### Task 2: Add The Bilingual Brand-Content Boundary And Public Bundle Name

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlow/DesignSystem/BrandIdentity.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Localization/AppLocalization.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings`
- Create: `apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings`
- Create: `apps/ios/BodyFlow/BodyFlow/Resources/Info.plist`
- Create: `apps/ios/BodyFlow/BodyFlowTests/BrandIdentityTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/LocalizationContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentModels.swift`
- Audit: `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingModels.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum SupportedAppLanguage: String, CaseIterable, Sendable {
    case portugueseBrazil = "pt-BR"
    case englishUnitedStates = "en-US"

    var catalogLocalization: String { get } // pt-BR or en
    var formattingLocale: Locale { get }   // pt_BR or en_US
    var contentLocale: ContentLocale { get }
}

enum AppLocalization {
    static func localizedBundle(
        for language: SupportedAppLanguage,
        in bundle: Bundle = .main
    ) throws -> Bundle

    static func string(
        _ key: String.LocalizationValue,
        for language: SupportedAppLanguage,
        in bundle: Bundle = .main
    ) throws -> String
}

struct BrandCopy: Equatable, Sendable {
    let slogan: String
    let descriptor: String
    let flowRoleLine: String
}

enum BrandIdentity {
    static let productName = "Better Ahead"
    static let agentName = "Flow"
    static func copy(
        for language: SupportedAppLanguage,
        bundle: Bundle = .main
    ) -> BrandCopy
}
```

`Better Ahead` and `Flow` are constants and are not looked up from
`Localizable.xcstrings`. `InfoPlist.xcstrings` repeats Better Ahead unchanged
for OS-owned metadata in both locales. Only slogan, descriptor, role line, and
surrounding UI copy are translated.
`Resources/Info.plist` is the source of nonlocalized bundle metadata and both
base public names. It uses build-setting substitutions for technical identity;
it must never hard-code `BodyFlow` as a public value.
`SupportedAppLanguage.englishUnitedStates` resolves the catalog localization
`en`; its persisted/onboarding identifier remains `en-US`. Portuguese resolves
`pt-BR` in both places. Tests require
`Set(SupportedAppLanguage.allCases.map(\.rawValue)) ==
OnboardingLocalePolicy.supportedIdentifiers`. Add `CaseIterable` to
`ContentLocale`, require the same raw-value set from `ContentLocale.allCases`,
and do not introduce a third independent locale list.

`AppLocalization` is the single boundary for every client-owned dynamic string
whose language is selected independently from the process locale. It maps
`en-US` to the committed `en.lproj` catalog and `pt-BR` to `pt-BR.lproj`, then
performs lookup in that localized bundle. A caller may instead construct a
`LocalizedStringResource` only when its `locale` is set from the same mapping.
Passing `locale:` only to a `String(localized:)` formatting overload is not an
accepted language-selection mechanism. Static SwiftUI localized keys continue
to follow the app's active locale.

**Step 1: Write failing identity/localization tests**

```swift
@Test(arguments: SupportedAppLanguage.allCases)
func properNamesNeverChange(_ language: SupportedAppLanguage) {
    #expect(BrandIdentity.productName == "Better Ahead")
    #expect(BrandIdentity.agentName == "Flow")
}

@Test
func approvedPortugueseCopy() {
    #expect(BrandIdentity.copy(for: .portugueseBrazil) == BrandCopy(
        slogan: "Melhor a cada dia.",
        descriptor: "Sua jornada personalizada para uma vida mais saudável.",
        flowRoleLine: "Flow, seu guia em cada etapa."
    ))
}

@Test
func approvedEnglishCopy() {
    #expect(BrandIdentity.copy(for: .englishUnitedStates) == BrandCopy(
        slogan: "Better every day.",
        descriptor: "Your personalized journey to a healthier life.",
        flowRoleLine: "Flow, your guide every step of the way."
    ))
}

@Test
func publicBundleNamesUseApprovedBrand() {
    #expect(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String == "Better Ahead")
    #expect(Bundle.main.infoDictionary?["CFBundleName"] as? String == "Better Ahead")
}
```

Also test that a missing brand key is reported by the localization contract and
that fallback output equals the approved Portuguese copy and contains neither
`BodyFlow` nor another agent name. Test
the `en-US` -> `en` catalog mapping directly, force the process language to the
opposite locale, and prove `AppLocalization` still returns the requested
language. Add a fixture for a dynamic computed/interpolated presentation string
so the boundary is not treated as brand-copy-only.

Declare `@Suite struct BrandIdentityTests` and
`@Suite struct LocalizationContractTests` so the documented `-only-testing`
selectors address real suite names. Runtime tests exercise `Bundle.main` or an
injected fixture bundle; only the Node catalog contract introduced in Task 7
reads source JSON. `BodyFlowTests` is hosted by the application, so the
bundle-name test is the regression for the processed application's raw,
nonlocalized plist, not the test bundle's generated plist. Use
`infoDictionary`; do not use `object(forInfoDictionaryKey:)`, which may
substitute an already-green value from localized `InfoPlist.strings` and
conceal the raw `CFBundleName` failure.

**Step 2: Run focused tests and verify RED**

```bash
set -euo pipefail
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/BrandIdentityTests \
  -only-testing:BodyFlowTests/LocalizationContractTests test
```

Expected on a fresh execution: FAIL because the boundary/catalogs do not exist.
For the authorized Task 2 resume after the first eight files were implemented,
rerun after adding the hosted bundle-name assertion and require the focused suite
to fail specifically because compiled `CFBundleName` is still `BodyFlow`.

**Step 3: Implement the boundary and exact catalog entries**

The String Catalog must contain reviewed `pt-BR` and `en` localizations for:

```text
brand.slogan
brand.descriptor
brand.flow.role-line
brand.logo.accessibility-label
brand.logo.fallback.accessibility-label
```

Use an explicit bundle/localization lookup in tests so host language cannot
make expectations nondeterministic. Missing keys fail tests; the runtime safe
fallback follows the project's established `pt-BR` development region and uses
the approved Portuguese value, never the former brand. `AppLocalization.string`
may throw for a missing localized bundle/key; `BrandIdentity.copy` catches that
failure and returns the complete approved Portuguese `BrandCopy`, preserving its
non-throwing interface. Other dynamic presentation boundaries apply the same
explicit pt-BR fallback and report the missing key to diagnostics.

The existing project enables `SWIFT_EMIT_LOC_STRINGS`. Once the reviewed String
Catalogs exist, set `SWIFT_EMIT_LOC_STRINGS = NO` in both application Debug and
Release configurations. The catalogs are manually reviewed inputs and the Node
inventory contract in Tasks 7-8 owns discovery; an ordinary build/test must
never autoedit them. Any future extraction experiment must run in a disposable
worktree and enter through a separately reviewed catalog diff.

Before the generated-plist reproduction in Step 4, keep
`GENERATE_INFOPLIST_FILE = YES` and set these temporary diagnostic inputs in
both application configurations:

```text
INFOPLIST_KEY_CFBundleDisplayName = "Better Ahead";
INFOPLIST_KEY_CFBundleName = "Better Ahead";
```

The first setting proves the supported display-name injection path; the second
deliberately reproduces the Xcode 26.6 conflict. Step 5 removes both settings
after the explicit source plist takes ownership. This makes the diagnostic
replayable from the approved base as well as from the currently paused
eight-file Task 2 worktree.

**Step 4: Reproduce and preserve the generated-plist baseline**

Xcode 26.6 derives `CFBundleName` from `PRODUCT_NAME` when
`GENERATE_INFOPLIST_FILE = YES`; `INFOPLIST_KEY_CFBundleName` does not override
that derivation. Prove this behavior before changing the build configuration and
retain the compiled plist outside the repository as the behavioral baseline:

```bash
set -euo pipefail
PLIST_BASELINE_POINTER=/tmp/better-ahead-task2-plist-baseline-root.txt
test ! -e "$PLIST_BASELINE_POINTER"
PLIST_BASELINE_ROOT=$(mktemp -d /tmp/better-ahead-task2-plist-baseline.XXXXXX)
xcodebuild -version | tee "$PLIST_BASELINE_ROOT/xcode-version.txt"
test "$(sed -n '1p' "$PLIST_BASELINE_ROOT/xcode-version.txt")" = "Xcode 26.6"
test "$(sed -n '2p' "$PLIST_BASELINE_ROOT/xcode-version.txt")" = "Build version 17F113"
CATALOG_SNAPSHOT="$PLIST_BASELINE_ROOT/catalogs.before.sha256"
find apps/ios/BodyFlow/BodyFlow/Resources \
  -name '*.xcstrings' -type f -print0 \
  | sort -z | xargs -0 shasum -a 256 > "$CATALOG_SNAPSHOT"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -derivedDataPath "$PLIST_BASELINE_ROOT/DerivedData" \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" build \
  2>&1 | tee "$PLIST_BASELINE_ROOT/generated-debug-build.log"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Release \
  -derivedDataPath "$PLIST_BASELINE_ROOT/DerivedData" \
  -destination "generic/platform=iOS Simulator" build \
  2>&1 | tee "$PLIST_BASELINE_ROOT/generated-release-build.log"
GENERATED_DEBUG_INFO="$PLIST_BASELINE_ROOT/DerivedData/Build/Products/Debug-iphonesimulator/BodyFlow.app/Info.plist"
GENERATED_RELEASE_INFO="$PLIST_BASELINE_ROOT/DerivedData/Build/Products/Release-iphonesimulator/BodyFlow.app/Info.plist"
for GENERATED_INFO in "$GENERATED_DEBUG_INFO" "$GENERATED_RELEASE_INFO"; do
  test -f "$GENERATED_INFO"
  test "$(plutil -extract CFBundleDisplayName raw -o - "$GENERATED_INFO")" \
    = "Better Ahead"
  test "$(plutil -extract CFBundleName raw -o - "$GENERATED_INFO")" \
    = "BodyFlow"
done
cp -- "$GENERATED_DEBUG_INFO" \
  "$PLIST_BASELINE_ROOT/generated-debug-before.plist"
cp -- "$GENERATED_RELEASE_INFO" \
  "$PLIST_BASELINE_ROOT/generated-release-before.plist"
for BASELINE_CONFIGURATION in debug release; do
  plutil -convert json \
    -o "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.json" \
    "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.plist"
done
node - \
  "$PLIST_BASELINE_ROOT/generated-debug-before.json" \
  "$PLIST_BASELINE_ROOT/generated-release-before.json" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const expectedBehavior = {
  UIApplicationSceneManifest: {
    UIApplicationSupportsMultipleScenes: true,
    UISceneConfigurations: {},
  },
  UIApplicationSupportsIndirectInputEvents: true,
  UILaunchScreen: { UILaunchScreen: {} },
  "UISupportedInterfaceOrientations~iphone": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
  "UISupportedInterfaceOrientations~ipad": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
};

for (const plistPath of process.argv.slice(2)) {
  const plist = JSON.parse(fs.readFileSync(plistPath, "utf8"));
  for (const [key, value] of Object.entries(expectedBehavior)) {
    assert.deepStrictEqual(plist[key], value, `${plistPath}: ${key}`);
  }
}
NODE
find apps/ios/BodyFlow/BodyFlow/Resources \
  -name '*.xcstrings' -type f -print0 \
  | sort -z | xargs -0 shasum -a 256 | cmp "$CATALOG_SNAPSHOT" -
printf '%s\n' "$PLIST_BASELINE_ROOT" > "$PLIST_BASELINE_POINTER"
```

Expected: both builds and display-name checks pass while both captured raw
`CFBundleName` values are `BodyFlow`. The complete behavioral contract also
passes in both configurations, including
`UILaunchScreen = { UILaunchScreen = {} }`, the value captured for this project
with Xcode 26.6 (`17F113`). This is the RED evidence for the
public-name requirement; do not rename the target or `PRODUCT_NAME` to make it
green.

For an authorized resume after Step 4 already created the pointer and preserved
both `generated-*-before.plist` files, do not delete the pointer or rerun the
creation/build portion merely to satisfy `test ! -e`. Resolve the recorded root,
revalidate it without modifying the pointer or either preserved plist, then run
the JSON behavioral check above against those files:

```bash
set -euo pipefail
PLIST_BASELINE_ROOT=$(tr -d '\n' < /tmp/better-ahead-task2-plist-baseline-root.txt)
test -d "$PLIST_BASELINE_ROOT"
test "$(xcodebuild -version | sed -n '1p')" = "Xcode 26.6"
test "$(xcodebuild -version | sed -n '2p')" = "Build version 17F113"
if test -f "$PLIST_BASELINE_ROOT/xcode-version.txt"; then
  xcodebuild -version | cmp "$PLIST_BASELINE_ROOT/xcode-version.txt" -
else
  test "$PLIST_BASELINE_ROOT" \
    = "/tmp/better-ahead-task2-plist-baseline.idcbiX"
  test "$(git rev-parse HEAD^)" \
    = "55e20de2cce1e2dce457c64aaf2f591131a17407"
  test -f \
    .superpowers/sdd/2026-08-11-better-ahead-ios-rebrand/task-2-report.md
fi
for CONFIGURATION in Debug Release; do
  BASELINE_CONFIGURATION=$(printf '%s' "$CONFIGURATION" \
    | tr '[:upper:]' '[:lower:]')
  rg -F -- '** BUILD SUCCEEDED **' \
    "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-build.log"
  cmp "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.plist" \
    "$PLIST_BASELINE_ROOT/DerivedData/Build/Products/$CONFIGURATION-iphonesimulator/BodyFlow.app/Info.plist"
  test "$(plutil -extract CFBundleDisplayName raw -o - \
    "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.plist")" \
    = "Better Ahead"
  test "$(plutil -extract CFBundleName raw -o - \
    "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.plist")" \
    = "BodyFlow"
  plutil -convert json \
    -o "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.json" \
    "$PLIST_BASELINE_ROOT/generated-$BASELINE_CONFIGURATION-before.plist"
done
node - \
  "$PLIST_BASELINE_ROOT/generated-debug-before.json" \
  "$PLIST_BASELINE_ROOT/generated-release-before.json" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const expectedBehavior = {
  UIApplicationSceneManifest: {
    UIApplicationSupportsMultipleScenes: true,
    UISceneConfigurations: {},
  },
  UIApplicationSupportsIndirectInputEvents: true,
  UILaunchScreen: { UILaunchScreen: {} },
  "UISupportedInterfaceOrientations~iphone": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
  "UISupportedInterfaceOrientations~ipad": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
};

for (const plistPath of process.argv.slice(2)) {
  const plist = JSON.parse(fs.readFileSync(plistPath, "utf8"));
  for (const [key, value] of Object.entries(expectedBehavior)) {
    assert.deepStrictEqual(plist[key], value, `${plistPath}: ${key}`);
  }
}
NODE
test -f "$PLIST_BASELINE_ROOT/catalogs.before.sha256"
find apps/ios/BodyFlow/BodyFlow/Resources \
  -name '*.xcstrings' -type f -print0 \
  | sort -z | xargs -0 shasum -a 256 \
  | cmp "$PLIST_BASELINE_ROOT/catalogs.before.sha256" -
```

Every new Step 4 capture must contain `xcode-version.txt`. The one authorized
resume whose baseline was created by the immediately preceding plan revision
may lack that newly introduced file; in that case the exact live version checks
above and the preserved execution report are the provenance bridge. Do not
retroactively create the file or generalize this exception to another baseline.

If the pointer exists but any referenced artifact is missing, or if the
recorded Xcode build differs, stop without deleting or replacing anything. If
the entire `/tmp` state was lost, a later explicitly authorized replay may run
the complete Step 4 into a new root only after proving the same eight-file
pre-migration snapshot; never reconstruct or edit a baseline plist.

**Step 5: Add one explicit source plist without renaming technical targets**

Create `BodyFlow/Resources/Info.plist`. It must set these public keys directly:

```text
CFBundleDisplayName = Better Ahead
CFBundleName = Better Ahead
```

Use these substitutions for technical identity and versioning rather than
hard-coded product values:

```text
CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)
CFBundleExecutable = $(EXECUTABLE_NAME)
CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)
CFBundleInfoDictionaryVersion = 6.0
CFBundlePackageType = $(PRODUCT_BUNDLE_PACKAGE_TYPE)
CFBundleShortVersionString = $(MARKETING_VERSION)
CFBundleVersion = $(CURRENT_PROJECT_VERSION)
LSRequiresIPhoneOS = true
```

Move the exact current generated values for these behavioral keys into the
source plist; Step 6 compares their compiled forms against the Step 4 baseline:

```text
UIApplicationSceneManifest
UIApplicationSupportsIndirectInputEvents
UILaunchScreen
UISupportedInterfaceOrientations~iphone
UISupportedInterfaceOrientations~ipad
```

The captured and committed contract is exact: the scene manifest is a
dictionary containing `UIApplicationSupportsMultipleScenes = true` and an
empty `UISceneConfigurations` dictionary; indirect input support is `true`;
the top-level `UILaunchScreen` value is a dictionary with exactly one inner
`UILaunchScreen` key whose value is an empty dictionary; the `~iphone` array is
`UIInterfaceOrientationPortrait`, `UIInterfaceOrientationLandscapeLeft`,
`UIInterfaceOrientationLandscapeRight`; and the `~ipad` array adds
`UIInterfaceOrientationPortraitUpsideDown` immediately after Portrait, with
the remaining landscape values in the same order. If the freshly captured
Xcode 26.6 plist disagrees, stop and record the discrepancy instead of guessing.
Do not replace either device-qualified orientation key with an unqualified
`UISupportedInterfaceOrientations` key.

Encode the launch-screen fragment unambiguously as:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UILaunchScreen</key>
    <dict/>
</dict>
```

Do not flatten it to `<key>UILaunchScreen</key><dict/>`, remove the inner key,
or add another wrapper. Although Apple's build-setting reference describes the
nominal generated value as an empty dictionary, the paired Debug and Release
Xcode 26.6 (`17F113`) baselines for this project contain the nested structure.
The observed compiled baseline governs this preservation migration; accepting
a different compiled launch-screen structure or behavioral baseline would
require a separate, explicitly approved task.

Do not copy toolchain/platform outputs such as `DT*`, `BuildMachineOSBuild`,
`MinimumOSVersion`, `UIDeviceFamily`, `CFBundleSupportedPlatforms`, asset-compiler
icon keys, or `NSAccentColorName` into the source file. Xcode and `actool` must
continue injecting those values during processing; the compiled-plist parity
gate proves they remain present where applicable.

For both application Debug and Release configurations, remove exactly these
now-inactive settings after their values have moved into the source plist:

```text
INFOPLIST_KEY_CFBundleDisplayName
INFOPLIST_KEY_CFBundleName
INFOPLIST_KEY_UIApplicationSceneManifest_Generation
INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents
INFOPLIST_KEY_UILaunchScreen_Generation
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone
```

Set exactly:

```text
GENERATE_INFOPLIST_FILE = NO;
INFOPLIST_FILE = BodyFlow/Resources/Info.plist;
```

The application is a `PBXFileSystemSynchronizedRootGroup`. Add exactly one
`PBXFileSystemSynchronizedBuildFileExceptionSet`, attach it to the existing
`BodyFlow` root group's `exceptions`, target the existing `BodyFlow` application
target, and set:

```text
membershipExceptions = (
    Resources/Info.plist,
);
```

The fixed target UUID is `5575F9CF301658E800FB4722`; the synchronized root UUID
is `5575F9D2301658E800FB4722`. Generate one new collision-free 24-character PBX
UUID for the exception object and reference only that object from the root. The
membership path is relative to the synchronized `BodyFlow` root. Do not add a
`PBXFileReference`, `PBXBuildFile`, explicit Resources-phase entry,
`explicitFileTypes`, `explicitFolders`, directory exception, or wildcard. The
plist remains an `INFOPLIST_FILE` input while being excluded from implicit Copy
Bundle Resources membership.

Add `en` to `knownRegions`; keep `developmentRegion = "pt-BR"`, target/scheme,
module and executable names, `PRODUCT_NAME = "$(TARGET_NAME)"`, product path,
and bundle identifiers unchanged. Add `CFBundleDisplayName` and `CFBundleName`
to `InfoPlist.xcstrings` with the same Better Ahead value for `pt-BR` and
English.

**Step 6: Run GREEN, compare plists, and commit**

```bash
set -euo pipefail
PLIST_BASELINE_ROOT=$(tr -d '\n' < /tmp/better-ahead-task2-plist-baseline-root.txt)
test -d "$PLIST_BASELINE_ROOT"
CATALOG_SNAPSHOT="$PLIST_BASELINE_ROOT/catalogs.before.sha256"
test -f "$CATALOG_SNAPSHOT"
BEFORE_DEBUG_INFO="$PLIST_BASELINE_ROOT/generated-debug-before.plist"
BEFORE_RELEASE_INFO="$PLIST_BASELINE_ROOT/generated-release-before.plist"
SOURCE_INFO=apps/ios/BodyFlow/BodyFlow/Resources/Info.plist
PROJECT=apps/ios/BodyFlow/BodyFlow.xcodeproj
plutil -lint "$SOURCE_INFO"
test "$(plutil -extract CFBundleDisplayName raw -o - "$SOURCE_INFO")" \
  = "Better Ahead"
test "$(plutil -extract CFBundleName raw -o - "$SOURCE_INFO")" \
  = "Better Ahead"
test "$(plutil -extract CFBundleExecutable raw -o - "$SOURCE_INFO")" \
  = '$(EXECUTABLE_NAME)'
test "$(plutil -extract CFBundleIdentifier raw -o - "$SOURCE_INFO")" \
  = '$(PRODUCT_BUNDLE_IDENTIFIER)'
test "$(plutil -extract CFBundleDevelopmentRegion raw -o - "$SOURCE_INFO")" \
  = '$(DEVELOPMENT_LANGUAGE)'
test "$(plutil -extract CFBundleInfoDictionaryVersion raw -o - "$SOURCE_INFO")" \
  = "6.0"
test "$(plutil -extract CFBundlePackageType raw -o - "$SOURCE_INFO")" \
  = '$(PRODUCT_BUNDLE_PACKAGE_TYPE)'
test "$(plutil -extract CFBundleShortVersionString raw -o - "$SOURCE_INFO")" \
  = '$(MARKETING_VERSION)'
test "$(plutil -extract CFBundleVersion raw -o - "$SOURCE_INFO")" \
  = '$(CURRENT_PROJECT_VERSION)'
test "$(plutil -extract LSRequiresIPhoneOS raw -o - "$SOURCE_INFO")" \
  = "true"
for REQUIRED_SOURCE_KEY in \
  UIApplicationSceneManifest UIApplicationSupportsIndirectInputEvents \
  UILaunchScreen 'UISupportedInterfaceOrientations~iphone' \
  'UISupportedInterfaceOrientations~ipad'; do
  plutil -extract "$REQUIRED_SOURCE_KEY" xml1 -o /dev/null "$SOURCE_INFO"
done
SOURCE_INFO_JSON="$PLIST_BASELINE_ROOT/source-info.json"
plutil -convert json -o "$SOURCE_INFO_JSON" "$SOURCE_INFO"
node - "$SOURCE_INFO_JSON" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const plist = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const approvedTopLevelKeys = [
  "CFBundleDevelopmentRegion",
  "CFBundleDisplayName",
  "CFBundleExecutable",
  "CFBundleIdentifier",
  "CFBundleInfoDictionaryVersion",
  "CFBundleName",
  "CFBundlePackageType",
  "CFBundleShortVersionString",
  "CFBundleVersion",
  "LSRequiresIPhoneOS",
  "UIApplicationSceneManifest",
  "UIApplicationSupportsIndirectInputEvents",
  "UILaunchScreen",
  "UISupportedInterfaceOrientations~iphone",
  "UISupportedInterfaceOrientations~ipad",
];
assert.deepStrictEqual(Object.keys(plist).sort(), approvedTopLevelKeys.sort());
assert.deepStrictEqual(plist.UIApplicationSceneManifest, {
  UIApplicationSupportsMultipleScenes: true,
  UISceneConfigurations: {},
});
assert.equal(plist.UIApplicationSupportsIndirectInputEvents, true);
assert.deepStrictEqual(plist.UILaunchScreen, { UILaunchScreen: {} });
assert.deepStrictEqual(plist["UISupportedInterfaceOrientations~iphone"], [
  "UIInterfaceOrientationPortrait",
  "UIInterfaceOrientationLandscapeLeft",
  "UIInterfaceOrientationLandscapeRight",
]);
assert.deepStrictEqual(plist["UISupportedInterfaceOrientations~ipad"], [
  "UIInterfaceOrientationPortrait",
  "UIInterfaceOrientationPortraitUpsideDown",
  "UIInterfaceOrientationLandscapeLeft",
  "UIInterfaceOrientationLandscapeRight",
]);
NODE
xcodebuild -project "$PROJECT" -list \
  > "$PLIST_BASELINE_ROOT/project-list.txt"
for CONFIGURATION in Debug Release; do
  SETTINGS="$PLIST_BASELINE_ROOT/app-$CONFIGURATION.settings.txt"
  xcodebuild -project "$PROJECT" -target BodyFlow \
    -configuration "$CONFIGURATION" -sdk iphonesimulator \
    -showBuildSettings > "$SETTINGS"
  test "$(awk -F ' = ' '/^[[:space:]]*GENERATE_INFOPLIST_FILE = / {print $2; exit}' "$SETTINGS")" \
    = "NO"
  test "$(awk -F ' = ' '/^[[:space:]]*INFOPLIST_FILE = / {print $2; exit}' "$SETTINGS")" \
    = "BodyFlow/Resources/Info.plist"
  test "$(awk -F ' = ' '/^[[:space:]]*PRODUCT_NAME = / {print $2; exit}' "$SETTINGS")" \
    = "BodyFlow"
  test "$(awk -F ' = ' '/^[[:space:]]*PRODUCT_MODULE_NAME = / {print $2; exit}' "$SETTINGS")" \
    = "BodyFlow"
  test "$(awk -F ' = ' '/^[[:space:]]*EXECUTABLE_NAME = / {print $2; exit}' "$SETTINGS")" \
    = "BodyFlow"
  test "$(awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / {print $2; exit}' "$SETTINGS")" \
    = "com.bodyflow.app"
  for MIGRATED_SETTING in \
    INFOPLIST_KEY_CFBundleDisplayName \
    INFOPLIST_KEY_CFBundleName \
    INFOPLIST_KEY_UIApplicationSceneManifest_Generation \
    INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents \
    INFOPLIST_KEY_UILaunchScreen_Generation \
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad \
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone; do
    if rg -q "^[[:space:]]*$MIGRATED_SETTING = " "$SETTINGS"; then
      printf 'Migrated build setting remains active in %s: %s\n' \
        "$CONFIGURATION" "$MIGRATED_SETTING" >&2
      exit 1
    fi
  done
done
for TEST_TARGET in BodyFlowTests BodyFlowUITests; do
  for CONFIGURATION in Debug Release; do
    SETTINGS="$PLIST_BASELINE_ROOT/$TEST_TARGET-$CONFIGURATION.settings.txt"
    xcodebuild -project "$PROJECT" -target "$TEST_TARGET" \
      -configuration "$CONFIGURATION" -sdk iphonesimulator \
      -showBuildSettings > "$SETTINGS"
    test "$(awk -F ' = ' '/^[[:space:]]*GENERATE_INFOPLIST_FILE = / {print $2; exit}' "$SETTINGS")" \
      = "YES"
    test -z "$(awk -F ' = ' '/^[[:space:]]*INFOPLIST_FILE = / {print $2; exit}' "$SETTINGS")"
  done
done
DERIVED_DATA=$(mktemp -d /tmp/better-ahead-identity-derived.XXXXXX)
xcodebuild -project "$PROJECT" \
  -scheme BodyFlow -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" build \
  2>&1 | tee "$PLIST_BASELINE_ROOT/explicit-debug-build.log"
xcodebuild -project "$PROJECT" \
  -scheme BodyFlow -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=iOS Simulator" build \
  2>&1 | tee "$PLIST_BASELINE_ROOT/explicit-release-build.log"
DEBUG_INFO="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/BodyFlow.app/Info.plist"
RELEASE_INFO="$DERIVED_DATA/Build/Products/Release-iphonesimulator/BodyFlow.app/Info.plist"
for BUILT_INFO in "$DEBUG_INFO" "$RELEASE_INFO"; do
  test -f "$BUILT_INFO"
  test "$(plutil -extract CFBundleDisplayName raw -o - "$BUILT_INFO")" \
    = "Better Ahead"
  test "$(plutil -extract CFBundleName raw -o - "$BUILT_INFO")" \
    = "Better Ahead"
  test "$(plutil -extract CFBundleExecutable raw -o - "$BUILT_INFO")" \
    = "BodyFlow"
  test "$(plutil -extract CFBundleIdentifier raw -o - "$BUILT_INFO")" \
    = "com.bodyflow.app"
done
for CONFIGURATION in Debug Release; do
  if test "$CONFIGURATION" = "Debug"; then
    BEFORE_INFO="$BEFORE_DEBUG_INFO"
    BUILT_INFO="$DEBUG_INFO"
  else
    BEFORE_INFO="$BEFORE_RELEASE_INFO"
    BUILT_INFO="$RELEASE_INFO"
  fi
  NORMALIZED_BEFORE="$PLIST_BASELINE_ROOT/$CONFIGURATION.generated.normalized.plist"
  NORMALIZED_AFTER="$PLIST_BASELINE_ROOT/$CONFIGURATION.explicit.normalized.plist"
  cp -- "$BEFORE_INFO" "$NORMALIZED_BEFORE"
  cp -- "$BUILT_INFO" "$NORMALIZED_AFTER"
  for PUBLIC_KEY in CFBundleDisplayName CFBundleName; do
    plutil -remove "$PUBLIC_KEY" "$NORMALIZED_BEFORE"
    plutil -remove "$PUBLIC_KEY" "$NORMALIZED_AFTER"
  done
  plutil -convert json \
    -o "$PLIST_BASELINE_ROOT/$CONFIGURATION.generated.normalized.json" \
    "$NORMALIZED_BEFORE"
  plutil -convert json \
    -o "$PLIST_BASELINE_ROOT/$CONFIGURATION.explicit.normalized.json" \
    "$NORMALIZED_AFTER"
  node - \
    "$PLIST_BASELINE_ROOT/$CONFIGURATION.generated.normalized.json" \
    "$PLIST_BASELINE_ROOT/$CONFIGURATION.explicit.normalized.json" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");

const before = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const after = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
assert.deepStrictEqual(after, before);
NODE
  for TECHNICAL_KEY in \
    CFBundleExecutable CFBundleIdentifier CFBundleInfoDictionaryVersion \
    CFBundlePackageType CFBundleShortVersionString CFBundleVersion \
    LSRequiresIPhoneOS; do
    test "$(plutil -extract "$TECHNICAL_KEY" raw -o - "$BEFORE_INFO")" \
      = "$(plutil -extract "$TECHNICAL_KEY" raw -o - "$BUILT_INFO")"
  done
done
for CONFIGURATION in Debug Release; do
  for APP_LOCALE in pt-BR en; do
    LOCALIZED_INFO="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/BodyFlow.app/$APP_LOCALE.lproj/InfoPlist.strings"
    test -f "$LOCALIZED_INFO"
    test "$(plutil -extract CFBundleDisplayName raw -o - "$LOCALIZED_INFO")" = "Better Ahead"
    test "$(plutil -extract CFBundleName raw -o - "$LOCALIZED_INFO")" = "Better Ahead"
  done
done
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/BrandIdentityTests \
  -only-testing:BodyFlowTests/LocalizationContractTests test
for BUILD_LOG in \
  "$PLIST_BASELINE_ROOT/explicit-debug-build.log" \
  "$PLIST_BASELINE_ROOT/explicit-release-build.log"; do
  PROCESS_COUNT=0
  PROCESS_COUNT=$(rg -c \
    '^ProcessInfoPlistFile .*BodyFlow\.app/Info\.plist .*BodyFlow/Resources/Info\.plist([[:space:]]|$)' \
    "$BUILD_LOG") || {
    RG_STATUS=$?
    test "$RG_STATUS" -eq 1
    PROCESS_COUNT=0
  }
  test "$PROCESS_COUNT" -eq 1
  FORBIDDEN_COPY=$(rg -n \
    'Multiple commands produce .*BodyFlow\.app/Info\.plist|^(CpResource|CopyPlistFile) .*BodyFlow\.app/Info\.plist .*BodyFlow/Resources/Info\.plist|warning:.*Copy Bundle Resources.*BodyFlow/Resources/Info\.plist|warning:.*BodyFlow/Resources/Info\.plist.*Copy Bundle Resources' \
    "$BUILD_LOG" || test "$?" -eq 1)
  test -z "$FORBIDDEN_COPY"
done
find apps/ios/BodyFlow/BodyFlow/Resources \
  -name '*.xcstrings' -type f -print0 \
  | sort -z | xargs -0 shasum -a 256 | cmp "$CATALOG_SNAPSHOT" -
git diff --check
git add apps/ios/BodyFlow/BodyFlow/DesignSystem/BrandIdentity.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Localization/AppLocalization.swift \
  apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/Info.plist \
  apps/ios/BodyFlow/BodyFlowTests/BrandIdentityTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LocalizationContractTests.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentModels.swift \
  apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj
git commit -m "feat(ios): add Better Ahead bilingual identity boundary"
```

Expected: Debug and Release expose both public names as Better Ahead. After
removing only the two intentionally changed public-name keys, each complete
compiled plist is structurally identical to its generated-plist baseline; the
technical and behavioral values therefore match semantically in both
configurations without relying on dictionary serialization order. This parity
includes the exact nested `UILaunchScreen = { UILaunchScreen = {} }` value; it
must not be flattened or excluded from comparison. Target, scheme, module,
executable, product path, `PRODUCT_NAME`, and bundle identifiers remain
unchanged. Each
build uses the source plist exactly once and never copies it as a resource. The
catalog checksum comparison passes, and the project diff shows
`SWIFT_EMIT_LOC_STRINGS = NO`,
`GENERATE_INFOPLIST_FILE = NO`, and the exact `INFOPLIST_FILE` in both
application configurations.

---

### Task 3: Lock A Narrow Renderer And The New Wordmark Inputs

**Files:**

- Create: `design/brand/better-ahead/masters/better-ahead-wordmark.svg`
- Create: `design/brand/better-ahead/masters/better-ahead-horizontal.svg`
- Create: `design/brand/better-ahead/environment.json`
- Create: `scripts/brand/better-ahead-brand-contract.mjs`
- Create: `scripts/brand/better-ahead-brand-contract.test.mjs`
- Create: `scripts/brand/capture-better-ahead-environment.mjs`
- Create: `scripts/brand/render-better-ahead-brand-assets.mjs`
- Create: `scripts/brand/render-better-ahead-brand-review.mjs`
- Create: `scripts/brand/run-better-ahead-brand-renderer.sh`
- Modify: `design/brand/better-ahead-brand-assets.json`
- Modify: `scripts/package.json`
- Read only: `package.json`
- Read only: `pnpm-lock.yaml`
- Read only: `pnpm-workspace.yaml`
- Read only: `scripts/brand/canonical-renderer/**`
- Read only: `design/brand/exports/bodyflow-horizontal.svg`

**Interfaces:**

- `capture-better-ahead-environment.mjs --write|--check` records or validates
  the exact host and pinned renderer fingerprint.
- `capture-better-ahead-environment.mjs --assert-local-docker` is a read-only,
  fail-closed route attestation. It validates Offload status JSON and records
  the normalized bundled Offload plugin version in the normative runtime
  fingerprint. Only the status-command identifier plus raw JSON byte length and
  SHA-256 are non-secret per-run evidence; the raw diagnostic remains outside
  the repository and those volatile values are not reproducibility-equality
  inputs. Its verdict is
  based on bundled client/plugin provenance, Docker Desktop application
  version, absent environment overrides/non-bundled plugin shadows, the exact
  `desktop-linux` Unix-socket endpoint, the context-bound default Buildx
  builder, and the explicit context's local Docker Desktop engine identity. It
  does not infer semantics from Docker's undocumented Offload JSON fields.
- `better-ahead-brand-contract.mjs --check-bundle EXACT_BUNDLE_PATH` validates
  the physical no-follow tree, receipt, exact entry set, roles, sizes, and
  hashes independently immediately after rendering. Normal `--check` resolves
  only the reviewed root manifest's declared candidate, requires it to equal
  the bundle derived from `environment.task3_input_commit_sha`, and applies the
  same validation.
- `better-ahead-brand-contract.mjs --register-candidate EXACT_BUNDLE_PATH`
  is a Task 4 source-edit helper, not part of rendering or recovery. It requires
  the manifest to match its exact tracked pre-render blob, independently
  validates the bundle, and changes only the seven receipt-derived mutable
  fields enumerated in Task 4. `--print-bounded-digest` emits only the canonical
  bounded-input digest so Task 4 can prove registration did not alter it. This
  helper is an ordinary isolated-worktree source edit, not an adversarial CAS:
  no concurrent source editor may run. It nevertheless rejects an untracked,
  dirty, non-regular, hardlinked, or symlinked manifest; reads the exact HEAD
  blob and physical preimage; writes only an exclusive same-directory temp;
  fsyncs, atomically replaces, and fsyncs the parent; reopens the result
  no-follow; and proves the resulting Git diff contains only the declared
  mutable fields. Tests cover dirty/prechanged input, final/intermediate
  symlinks, hardlinks, extra-field mutation, bounded-digest drift, and exact
  success. Any suspected concurrent editing blocks Task 4 for manual audit.
- `run-better-ahead-brand-renderer.sh --write|--check` and
  `run-better-ahead-brand-renderer.sh --recover EXACT_TRANSACTION_PATH` plus
  `--recover-orphan EXACT_BEGIN_TEMP_PATH` are the only public
  rendering/recovery entry points. `--write` orchestrates the persisted
  `begin -> one Docker build -> one visual container -> resume -> finish`
  protocol; `--recover` never invokes Docker.
- Runner `--check` is read-only and Docker-free: it validates the already
  recorded environment file, bounded inputs, exact manifest-declared committed
  bundle, receipt, and six hashes. It does not call environment live
  attestation or regenerate comparison bytes; the separate
  `brand:better-ahead:environment` command owns live Docker attestation.
- The internal transaction interface is
  `render-better-ahead-brand-assets.mjs --transaction-begin`,
  `--transaction-resume EXACT_TRANSACTION_PATH`,
  `--transaction-finish EXACT_TRANSACTION_PATH`, and
  `--recover EXACT_TRANSACTION_PATH` plus
  `--recover-orphan EXACT_BEGIN_TEMP_PATH`. `begin` durably publishes the
  authoritative journal before snapshot, probe, build, render, log, or
  candidate creation. `resume` consumes the journal-bound one-shot completion
  record without publication. `finish` seals and atomically publishes the
  whole bundle, verifies it, cleans its transaction, and unlocks. It never
  mutates the root manifest.
- The runner may create only its exact lock/transaction paths, the immutable
  final bundle `design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>`. It has no
  write path to the root manifest, flat Better Ahead exports/review paths,
  legacy exports, source, masters, AppIcon, or the Asset Catalog.
- New production masters are self-contained, path-only SVGs. They contain no
  live `<text>`, font reference, external URL, script, raster payload, product
  descriptor, slogan, or localized copy.

Environment check exit codes are contractual: `0` means the recorded
fingerprint is recreated exactly; `78` means a complete, non-writing diagnostic
proved that the recorded environment is unavailable or differs; every other
nonzero code is a checker/tool failure. Exit `78` permits canonical committed
bytes to be used without a reproducibility claim, never a rerender or hash
replacement. Because no Better Ahead environment or output bytes exist before
Tasks 3 and 4, exit `78` at the current first-capture boundary is blocking.

**Step 1: Write failing renderer/input tests**

Require:

- exact master IDs `wordmark` and `horizontal`;
- manifest identity `Better Ahead`, non-empty outlined glyph geometry, and
  bytes distinct from the historical BodyFlow wordmark;
- horizontal lockup containing the preserved B symbol geometry plus new
  wordmark geometry;
- allowed SVG elements/attributes only;
- historical symbol/AppIcon hashes unchanged before and after fake renderer
  runs;
- a per-run Docker image ID captured with
  `buildx build --builder default --platform=linux/amd64 --iidfile`, using the
  pinned `scripts/brand/canonical-renderer` context. The canonical Dockerfile's
  dependency installation retains build-time network access. The exact ID
  built for a run must be passed to
  `docker --context desktop-linux run --platform=linux/amd64 --network none`;
- check mode never writes;
- write mode refuses a dirty input, concurrent edit, missing fingerprint,
  fingerprint mismatch, existing recovery quarantine, any pre-existing final
  bundle destination, or any target outside the exact transaction and final
  bundle paths. Only recovery may recognize an exact bundle bound to the same
  run ID and nonce after a publication crash;
- the comparison renderer may read only the manifest-declared historical input
  `design/brand/exports/bodyflow-horizontal.svg`, whose exact SHA-256 is
  `cb88d3af9c6687573f06c34349c9c8bda2e602f8862cc728ca564ed880708cb0`;
  changing one byte, redirecting the read to an undeclared path, or attempting
  to write that input fails before Docker or live-output mutation;
- an authoritative lock-journal exists atomically before any snapshot, probe,
  Docker command, render log, candidate, bundle staging, or other preparation
  write. Failures and signals at every begin, snapshot, build, container,
  resume, sealing, bundle publication, verification, cleanup, and unlock
  boundary retain the journal and all available evidence;
- `begin` records the run ID, nonce, exact transaction path, bounded input
  digest, expected six candidate paths, final bundle path, and dispatch request
  before the external visual work starts. The transaction-bound dispatcher
  claims that request exactly once and the one visual container produces all
  six candidates; direct asset/review worker invocation, replay, a fabricated
  request, a symlinked request, a live-repository input, or a second writer is
  rejected;
- the container receives the immutable snapshot read-only and only the exact
  candidate/log area writable. The live repository is never mounted writable.
  Asset and review workers are implementation modules, not public package
  commands, and can run only through the journal-bound dispatcher request;
- candidate files are opened through anchored descriptors without following
  symlinks, validated and hashed from the same descriptors, copied into a
  complete source bundle, and sealed. Path replacement, content mutation,
  symlink/hardlink substitution, and read error injection at every boundary
  fail closed without publishing the final bundle;
- the bundle source contains exactly the three SVGs, three PNGs, and
  `receipt.json`. A native helper validates that sealed tree and performs the
  same-filesystem `renameatx_np(..., RENAME_EXCL)` from source bundle to final
  bundle without returning to JavaScript between its final FD-based validation
  and rename. That single directory-entry rename is the sole visual commit
  point. The helper then fsyncs the bundles parent; a pre-created destination
  causes a no-replace failure and is never overwritten;
- recovery reads the lock, journal, mirror, transaction tree, candidates,
  staged bundle, committed receipt, and outputs only through
  component-by-component FD-relative traversal with `O_NOFOLLOW` and physical
  type/owner/device/inode/link-count/size/hash checks. Only an explicitly
  optional path returning `ENOENT` may mean absent; `ELOOP`, `ENOTDIR`,
  `EACCES`, `EPERM`, `EIO`, every other error, or any symlink/hardlink/race is
  blocking. The mirror is audit evidence only and never a fallback authority;
- pre-commit recovery preserves candidates/logs until the audited recovery is
  authorized, is idempotent, and names every touched path explicitly.
  Post-commit recovery never deletes or restores the bundle. Cleanup and
  recovery never use a glob or broad directory target;
- only a fully successful write or fully successful state-specific recovery
  removes the exact lock, always as its final operation. A second write remains
  blocked after any injected error until the applicable audited
  `--recover-orphan EXACT_BEGIN_TEMP_PATH` (before lock publication) or
  `--recover EXACT_TRANSACTION_PATH` (after publication) completes
  successfully;
- the bounded digest and environment contract reject a changed root
  `packageManager`, `pnpm-workspace.yaml` build policy, exact Corepack command,
  or Node/Corepack/pnpm version without modifying any of those read-only inputs;
- fake Docker fixtures prove `--assert-local-docker` is non-writing and
  fail-closed: non-bundled client or Buildx/Desktop/Offload plugin
  realpath/hash, non-bundled user/system plugin shadow, non-empty
  `cliPluginsExtraDirs`, Docker Desktop application older than
  4.80.0 or inconsistent with the server platform name, any ambient variable
  whose name begins `DOCKER_`, `BUILDKIT_`, or `BUILDX_`, or the
  `EXPERIMENTAL_BUILDKIT_SOURCE_POLICY` override, missing Offload
  version/status support, nonzero/empty/malformed Offload JSON,
  non-`desktop-linux` default context, nonlocal/TCP/SSH/cloud endpoint, a
  default Buildx builder whose name/driver/endpoint are not exactly
  `default`/`docker`/`desktop-linux`, or wrong explicit engine identity all exit
  `78`. Attestation inspects only the named `default` builder and never runs
  `buildx ls`, which could contact unrelated remote builders. The valid
  status JSON hash/length is non-normative execution evidence, not a
  state-schema or reproducibility oracle. Environment `--write`, environment
  `--check`, and runner `--write` repeat the same route attestation; renderer
  `--check` remains Docker-free and validates only the recorded fingerprint and
  committed bundle. Override fixtures use sentinel secret values and
  prove diagnostics emit only variable names/presence, never their values;
- fake runner tests prove every renderer `docker buildx build`, `run`,
  `image inspect`, and related daemon command uses the literal
  `--context desktop-linux` argument, build uses literal `--builder default`,
  and every build/run uses literal `--platform=linux/amd64`. Build captures its
  IID with `--iidfile`; only run uses literal `--network none` and consumes that
  exact IID. No context-less Docker daemon API probe is permitted during
  attestation or rendering;
- fake runner tests also prove the exact persisted order
  `BEGIN -> BUILDX -> RUN -> RESUME -> FINISH`, exactly one build and one
  container for a write, and zero Docker calls from `resume`, `finish`,
  `--recover`, or any cleanup path. Build/container failures and `HUP`, `INT`,
  or `TERM` after `begin` preserve the journal, request, logs, candidates, and
  transaction path; no trap removes or unlocks them;
- adversarial tests cover final and intermediate symlinks, matching-hash mirror
  fallback attempts, candidate and staged-bundle substitution, same-inode
  mutation and inode replacement before the native
  helper takes exclusive ownership, a pre-created final bundle, a competing
  final-path creation at the native publish boundary, interruption immediately
  before and after the directory rename, parent-fsync failure, unlock inode
  substitution, every non-`ENOENT` read error, idempotent post-commit recovery,
  and an exact successful regular-file/directory control case. Tests do not
  claim protection from deliberate mutation by an already-compromised process
  running as the same user inside the private helper-owned validation-to-rename
  interval;
- tests interrupt the native initial-journal helper before and after its
  exclusive lock rename. Before publication, a failed helper removes only its
  exact begin temp; if that cleanup cannot be proven, it reports
  `BEGIN_ORPHANED` with the exact path, blocks new writes, and only audited
  `--recover-orphan EXACT_BEGIN_TEMP_PATH` may remove it. After publication,
  the complete authoritative lock always exists, including when the transaction
  root has not yet been created;
- tests kill every later journal transition after deterministic
  `<LOCK_PATH>.update` create, write, fsync, and rename. Before rename the prior
  lock remains authoritative; the no-follow preflight always detects the exact
  orphan, and only tested exact-leaf recovery may complete or remove it;
- once the one container has produced a valid completion, a final destination
  proven absent, an unchanged anchored bundles parent, and exact
  candidates/staging, resumable failures in sealing, parent fsync, or
  publication select `FINISH_REQUIRED`, preserve candidates/staging, and resume
  `finish` without Docker. A present/divergent final path, substituted parent,
  ambiguous physical state, or mismatched bytes selects `BLOCKED`, never
  `FINISH_REQUIRED`. Tests prove no second build/container occurs and only a
  pre-render `RECOVERY_REQUIRED` cycle can require renewed render authorization;
- no originals or backups are created, read, restored, or present in the
  schema: the immutable final bundle destination is required to be absent;
- registration tests prove `--register-candidate` rejects a dirty/divergent
  manifest, invalid/rejected/symlinked bundle, non-regular or hardlinked
  manifest, extra-field edit, and bounded-digest drift; changes only the seven
  declared receipt-derived fields on exact success; rejects a second invocation
  unless the entire expected projection is already byte-identical, in which
  case it is a non-writing success; and is never invoked by the runner,
  `finish`, or recovery;
- no call to `render-bodyflow-brand-assets.mjs` or legacy `brand:render`.

Machine tests cannot prove that arbitrary paths visually spell the intended
name. Spelling, letterform quality, and absence of visual remnants of the old
wordmark remain blocking human assertions in Task 4; the machine gate proves
only path safety, declared role, composition, and byte provenance.

**Step 2: Run RED**

```bash
node --test scripts/brand/better-ahead-brand-contract.test.mjs
```

Expected: FAIL because the narrow pipeline and masters do not exist.

**Step 3: Author the new master geometry**

Reuse the approved symbol without modifying its geometry, colors, gradients, or
arrow. Create a new outlined Better Ahead wordmark with the existing premium,
forward-moving visual direction. Use the approved palette and existing system
font fallbacks as optical references only; no unlicensed font file enters the
repository. The horizontal master is self-contained and copies the preserved
symbol geometry into a new composition; it is therefore correctly classified
as new rather than invariant.

Before review, inspect at 96, 160, 320, and 960 point wordmark widths and at
44, 88, 132, 360, 720, and 1080 point lockup widths. Reject clipped glyphs,
ambiguous word separation, excessive slant, or a symbol smaller than its
historical clear-space rule.

**Step 4: Implement the narrow renderer**

Expose these commands without changing the existing `brand:*` commands:

```json
{
  "brand:better-ahead:environment": "node brand/capture-better-ahead-environment.mjs --check",
  "brand:better-ahead:catalog": "node brand/better-ahead-preserved-assets.mjs --check --require-catalog",
  "brand:better-ahead:render": "sh brand/run-better-ahead-brand-renderer.sh --write",
  "brand:better-ahead:render:check": "sh brand/run-better-ahead-brand-renderer.sh --check",
  "brand:better-ahead:validate": "node brand/better-ahead-brand-contract.mjs --check",
  "brand:better-ahead:validate:inputs": "node brand/better-ahead-brand-contract.mjs --check --inputs-only",
  "brand:better-ahead:test": "node --test brand/better-ahead-preserved-assets.test.mjs brand/better-ahead-worktree-state.test.mjs brand/better-ahead-brand-contract.test.mjs"
}
```

Let `TASK3_INPUT_SHA` be the full lowercase 40-hex hardening commit recorded as
`task3_input_commit_sha` in `environment.json`. The renderer publishes exactly
one immutable bundle at:

```text
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/exports/better-ahead-wordmark.svg
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/exports/better-ahead-horizontal.svg
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/exports/better-ahead-launch.svg
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/review/better-ahead-comparison.png
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/review/better-ahead-reduced-sizes.png
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/review/better-ahead-light-dark.png
design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/receipt.json
```

The production SVG exports are byte copies/controlled compositions of the new
masters. Sharp is used only for review PNGs. No symbol or App Icon raster is
rendered. The receipt records its schema, exact Task 3 input SHA, bounded input
digest, environment hash, renderer/run identity, bundle-relative path, and the
relative path, role, SHA-256, and byte length of every one of the six outputs.
No receipt field hashes the containing bundle or root-manifest bytes, avoiding
self-reference. Files are regular, single-link, non-executable files; symlinks,
hardlinks, devices, sockets, FIFOs, extra entries, and a pre-existing final
bundle path are rejected.

Before the first Task 3 commit, set the manifest's immutable
`environment.path = design/brand/better-ahead/environment.json`. The bounded
input digest covers the two masters, all new renderer/contract scripts, the
unchanged canonical-renderer Docker context, `pnpm-lock.yaml`, and a canonical
projection of only the renderer-related dependency versions and
`brand:better-ahead:{environment,render,render:check,validate,validate:inputs}`
commands from `scripts/package.json`, the root
`packageManager = pnpm@10.33.2`, and the committed
`pnpm-workspace.yaml` build-script policy. It also covers the exact path and
bytes of `design/brand/exports/bodyflow-horizontal.svg`, pinned to the full
historical manifest SHA above and declared for comparison-board input only.
No production export or app target may consume that historical wordmark.

The digest also covers a canonical immutable pre-render manifest projection:
product identity, historical/preserved references, the complete allowlist of
every file either renderer may read, role and output-path declarations, and
`environment.path`. A read outside that allowlist is a contract failure. The
digest does not hash unrelated package-script entries that Tasks 7 or 9 add
later. It explicitly excludes `environment.json` and mutable manifest candidate
version, approval/bundle-projection, and generated-output hash fields, avoiding
both a self-referential hash and false invalidation from unrelated tooling.

The normative renderer identity is the pinned base-image digest, the bounded
canonical-renderer context/package-lock digest, the bundled Docker CLI/plugin
realpaths, versions, and hashes, the context-bound default builder with its
`docker` driver, and complete runtime versions observed inside the container.
The image ID from `--iidfile` is per-run execution evidence: tests prove the
same freshly built ID is used by
`docker --context desktop-linux run`, but do not require separately rebuilt
image IDs to be equal.

Transactions use one fixed lock path and one unique transaction directory under
`design/brand`, both proven by physical, descriptor-relative traversal to be
inside the repository. The lock file is also the sole authoritative recovery
journal. After pure read-only admissions, `begin` writes the complete initial
JSON to the single deterministic exclusive leaf `<LOCK_PATH>.begin` in the
lock's parent, fsyncs the file, uses
anchored `renameatx_np(..., RENAME_EXCL)` to publish the lock atomically, and
fsyncs the parent. Only then may it create the transaction root, snapshot,
probe, IID file, render log, request, candidate, or bundle staging path. The
native helper owns journal-temp creation through parent fsync as one operation;
on pre-rename failure it removes only its exact temp. If removal/fsync cannot be
proved, it emits `BEGIN_ORPHANED` plus that exact path and every later write
blocks until audited `--recover-orphan EXACT_BEGIN_TEMP_PATH` verifies the
authoritative lock is absent, validates the orphan no-follow, and removes only
that leaf. Every write preflight checks the fixed begin leaf no-follow before
creating anything, so a `SIGKILL` or power loss cannot leave an undiscoverable
orphan; its presence reports `BEGIN_ORPHANED` with the deterministic path and
blocks. A crash after lock publication but before transaction-root creation
is a valid `LOCKED_PREPARING` state: the transaction root is schema-optional
only there and recovery remains journal-authoritative. After lock publication,
`begin` creates and validates the exact `bundles` parent with anchored
`mkdirat` if absent, records whether this run created it, and fsyncs its parent
before any Docker command. Pre-render recovery may remove that parent only if
it is still the same empty run-created directory. Later journal updates use the
single deterministic exclusive leaf `<LOCK_PATH>.update`, flush, anchored
atomic rename, and parent flush. Every transition checks that leaf no-follow
first. If a crash leaves it, the prior lock remains authoritative and the exact
update leaf is preserved/reported; audited recovery validates its bound run ID,
nonce, predecessor state, physical identity, and hash, then either completes
the already-authorized transition or removes only that leaf. It never
enumerates or glob-cleans lock siblings.
`transaction/recovery.json` is a diagnostic mirror only: it is never read as
fallback authority and disagreement is blocking.
After every journal rename, the writer reopens the authoritative leaf with
no-follow semantics and captures its new device/inode as the only valid lock
identity for subsequent checks and final unlock.

The normative state machine is:

```text
IDLE -> LOCKED_PREPARING -> RENDERING -> RENDERED -> SEALING
          |                   |
          +-------------------+-> RECOVERY_REQUIRED

RENDERED/SEALING -> BUNDLE_SEALED -> PUBLISHING_BUNDLE -> BUNDLE_COMMITTED
      |                  |                    |
      +------------------+--------------------+-> FINISH_REQUIRED when final bundle absent

BUNDLE_COMMITTED ------------------------> CLEANUP_REQUIRED -> IDLE
        |                                         |
        +-----------------------------------------+
                 exact committed bundle always dominates journal-label lag

unknown, ambiguous, symlinked, unreadable, or hash-divergent state -> BLOCKED
```

`begin` records the run ID and nonce, physical repository root, exact
transaction path, complete read/write allowlists, bounded input and environment
hashes, final bundle path, exact six candidate paths, dispatch request path,
claim path, completion path, and initially absent final destination. It then
copies the complete bounded input set into an immutable transaction snapshot and
proves that snapshot against the exact Task 3 input commit. Docker context,
comparison input, and render inputs come only from that snapshot.

The shell runner invokes `begin` before its sole Buildx build. It writes all
subsequent execution evidence under the recorded transaction, repeats the
fail-closed local-route attestation inside that journaled phase immediately
before Buildx, and invokes one container with the freshly built IID. The
standalone environment command in Task 4 is an earlier read-only preflight; it
does not replace this post-`begin` attestation. A single dispatcher inside that container
atomically claims the journal-bound request and imports both asset and review
workers, producing all six candidates. The request binds the run ID, nonce,
snapshot digest, exact input roots, and exact candidate allowlist. The workers
reject standalone invocation, request replay, a second claim/writer, live-tree
input, or output outside that allowlist. The snapshot is mounted read-only; only
recorded transaction candidate/log paths are writable; the live repository is
not mounted writable.

After the external command completes, `resume` validates the request, claim,
completion record, nonce, exit status, and exact six candidate paths using the
authoritative journal. A build/container failure or incomplete record durably
selects `RECOVERY_REQUIRED` when safe to record and preserves all evidence.
Success advances only to `RENDERED`; `resume` never invokes Docker, publishes an
output, mutates the manifest, cleans, or unlocks. On an abrupt signal, the
runner's trap may only best-effort record the signal/exit status and print the
transaction path. It must not remove any path or lock.

`finish` is valid from `RENDERED` or a validated `FINISH_REQUIRED` state. The
`bundles` parent was already prepared by `begin`; later runs validate that exact
existing parent but never enumerate it to choose an output. `finish` opens every candidate through anchored
descriptors with no symlink following, validates and hashes bytes from those
same descriptors, and materializes a source bundle under the transaction with
exactly the seven declared files. It fsyncs every file and directory, prohibits
extra entries/symlinks/hardlinks, and marks the staged tree sealed. A native
FD-anchored helper then opens the repository, transaction, and bundles parent
component by component; revalidates the sealed source tree and receipt; proves
the final leaf absent with `AT_SYMLINK_NOFOLLOW`; and, without returning to
JavaScript, performs the single same-filesystem
`renameatx_np(..., RENAME_EXCL)` of the source directory to
`bundles/<TASK3_INPUT_SHA>`. It fsyncs the bundles parent before reporting the
commit. No individual output is ever visible at a flat live path, and no
unconditional overwrite rename is permitted.

The threat boundary covers concurrent edits/precreation in the final repository
namespace and every pathname substitution before the native helper assumes
exclusive ownership of its private staged tree. It does not claim to make a
normal developer-owned worktree tamper-proof against an already-compromised
process running as the same macOS user that deliberately mutates that private
tree during the helper-owned validation-to-rename interval. Within the stated
boundary, the helper owns that final sequence and the live namespace changes
atomically from absent to the complete immutable bundle.

After the directory rename, physical bundle state dominates the journal label.
An absent final bundle before a valid render completion may select
`RECOVERY_REQUIRED`. An absent final bundle after an exact completion with
intact candidates or staged bundle selects `FINISH_REQUIRED` and resumes only
sealing/publication without Docker. An exact final bundle whose receipt and six
hashes match
the journal selects `BUNDLE_COMMITTED`/`CLEANUP_REQUIRED` even if the journal
still says `PUBLISHING_BUNDLE`. A present unexpected, malformed, partial,
symlinked, extra-entry, or hash-divergent bundle, or an absent bundle under a
durably post-commit label, is `BLOCKED` and authorizes neither cleanup nor
unlock.

The committed bundle is the authority. `finish` and recovery do not mutate the
root manifest. Once `finish` succeeds and unlocks, Task 4 validates the bundle
independently, then creates an ordinary reviewable Git patch to the root
manifest with `active_candidate.bundle_path`, receipt SHA-256, and all six
receipt-derived roles/hashes. That patch is staged and committed together with
the immutable bundle and evidence; a dirty or concurrently changed manifest is
a normal Git conflict/blocker, never something the renderer overwrites.
Downstream consumers must resolve the exact reviewed manifest-declared bundle
and verify its receipt; they never scan `bundles`, choose a latest entry, or
follow a mutable alias.

Every recovery read uses the same anchored no-follow discipline as publication:
open each directory component with `O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC`, open a
leaf with `O_RDONLY|O_NOFOLLOW|O_CLOEXEC`, require the documented physical type,
and verify owner, device, inode, link count, size, and hash from the same open
descriptor before and after use. Only `ENOENT` for a schema-declared optional
leaf means absent. Missing required lock/journal/receipt data and every
other error—including `ELOOP`, `ENOTDIR`, `EACCES`, `EPERM`, and `EIO`—blocks
without fallback, cleanup, or unlock. Unlock revalidates the exact recorded lock
inode with `fstatat(..., AT_SYMLINK_NOFOLLOW)` and removes only that leaf with
`unlinkat`, always as the final successful operation.

Recovery is permitted only through the tested exact-path interface after
audit: `--recover-orphan EXACT_BEGIN_TEMP_PATH` applies solely before an
authoritative lock exists; `--recover EXACT_TRANSACTION_PATH` applies once it
does. `RECOVERY_REQUIRED` is
pre-commit: it never renders, and it retains candidates/logs until the audited
explicit cleanup succeeds; any later write is a new fingerprinted cycle that
requires renewed render authorization. `FINISH_REQUIRED` means the authorized
container already completed: recovery revalidates the completion and exact
candidates/staging, calls only `finish`, and never cleans them or requests a new
render while publication remains safely resumable. `CLEANUP_REQUIRED` is
post-commit: it never removes/restores the bundle and may only verify
bundle/receipt/output hashes, reopen and fsync the anchored bundles parent to
close any recorded post-rename parent-fsync failure, remove journal-enumerated
transaction artifacts, and unlock. It never builds, invokes Docker, recreates
candidates, recaptures the fingerprint, or rerenders. After successful
post-commit recovery, Task 4 continues directly at Step 3.

**Step 5: Commit the complete renderer inputs before fingerprint capture**

Run the input-only tests, then commit masters and tooling without any generated
export, review PNG, or environment file:

```bash
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate:inputs
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
git diff --check
git add design/brand/better-ahead/masters \
  design/brand/better-ahead-brand-assets.json \
  scripts/brand/better-ahead-brand-contract.mjs \
  scripts/brand/better-ahead-brand-contract.test.mjs \
  scripts/brand/capture-better-ahead-environment.mjs \
  scripts/brand/render-better-ahead-brand-assets.mjs \
  scripts/brand/render-better-ahead-brand-review.mjs \
  scripts/brand/run-better-ahead-brand-renderer.sh scripts/package.json
git commit -m "build(brand): add Better Ahead asset pipeline"
```

The contract CLI must explicitly support `--inputs-only`; this mode validates
masters, preserved references, path boundaries, and tooling without requiring
outputs that do not exist yet.

**Current-execution reconciliation after the preserved partial commit**

The current implementation preserves pipeline commit
`0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38`, documentation-only child
`ac6960f690dda59844cb6cedef96f23f81a4558c`, and the later
documentation-only reconciliation
`9d204ab10801cd2cb07ec8d5ee6a759b12dd296b`. At that last commit the worktree
contains exactly seven unstaged Task 3 implementation modifications, staging is
empty, and no environment, bundle, export, review PNG, lock, journal, or
transaction exists. Preserve all three commits and all seven modifications;
do not amend, reset, stash, discard, stage, or replace them.

Before importing this Option A reconciliation, the operator must capture the
NUL-delimited porcelain and binary diff of those seven files in private temp
files. Import this plan as one additional documentation-only child of
`9d204ab...`, stage/commit only this plan, and prove that the remaining
porcelain and binary diff are byte-identical to the captured values. While that
new documentation commit is `HEAD`, prove the topology and documentation-only
boundaries before any dependency or implementation command:

```bash
set -euo pipefail
git diff --cached --exit-code
TASK3_STATUS_BEFORE=$(mktemp /tmp/better-ahead-task3-status.XXXXXX)
TASK3_DIFF_BEFORE=$(mktemp /tmp/better-ahead-task3-diff.XXXXXX)
git status --porcelain=v1 -z -uall > "$TASK3_STATUS_BEFORE"
git diff --binary > "$TASK3_DIFF_BEFORE"
test -n "${OPTION_A_DOC_SHA:?set OPTION_A_DOC_SHA to the exact published documentation SHA from the handoff}"
git fetch origin codex/better-ahead-rebranding-design
test "$(git diff-tree --no-commit-id --name-only -r "$OPTION_A_DOC_SHA")" \
  = "docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md"
test "$(git rev-parse "$OPTION_A_DOC_SHA^0")" \
  = "$(git rev-parse origin/codex/better-ahead-rebranding-design)"
git cherry-pick "$OPTION_A_DOC_SHA"
test "$(git rev-parse ac6960f690dda59844cb6cedef96f23f81a4558c^)" \
  = "0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38"
test "$(git rev-parse 9d204ab10801cd2cb07ec8d5ee6a759b12dd296b^)" \
  = "ac6960f690dda59844cb6cedef96f23f81a4558c"
test "$(git rev-parse HEAD^)" \
  = "9d204ab10801cd2cb07ec8d5ee6a759b12dd296b"
git merge-base --is-ancestor \
  9d204ab10801cd2cb07ec8d5ee6a759b12dd296b HEAD
test "$(git diff-tree --no-commit-id --name-only -r \
  9d204ab10801cd2cb07ec8d5ee6a759b12dd296b)" \
  = "docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" \
  = "docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md"
git diff --cached --exit-code
TASK3_STATUS_AFTER=$(mktemp /tmp/better-ahead-task3-status-after.XXXXXX)
TASK3_DIFF_AFTER=$(mktemp /tmp/better-ahead-task3-diff-after.XXXXXX)
git status --porcelain=v1 -z -uall > "$TASK3_STATUS_AFTER"
git diff --binary > "$TASK3_DIFF_AFTER"
cmp "$TASK3_STATUS_BEFORE" "$TASK3_STATUS_AFTER"
cmp "$TASK3_DIFF_BEFORE" "$TASK3_DIFF_AFTER"
test "$(git status --porcelain=v1 -z -uall \
  | tr -cd '\0' | wc -c | tr -d ' ')" = "7"
```

The import step must also list and record those seven exact relative paths;
their set, status, and binary diff—not merely their count—are the preservation
gate used below.

1. Verify and reconcile the dependency tree with the declared package manager.
   The earlier direct pnpm 11.16.0 invocation and
   `--dangerously-allow-all-builds` exception are not evidence for any gate:

   ```bash
   set -euo pipefail
   test "$(node -p 'require("./package.json").packageManager')" = "pnpm@10.33.2"
   command -v corepack
   test "$(corepack pnpm@10.33.2 --version)" = "10.33.2"
   DANGEROUS_BUILD_POLICY=$(corepack pnpm@10.33.2 config get dangerouslyAllowAllBuilds)
   case "$DANGEROUS_BUILD_POLICY" in
     ''|false|null|undefined) ;;
     *) false ;;
   esac
   export npm_config_dangerously_allow_all_builds=false
   PACKAGE_STATE=$(mktemp /tmp/better-ahead-package-state.XXXXXX)
   PACKAGE_DIFF_STATE=$(mktemp /tmp/better-ahead-package-diff.XXXXXX)
   shasum -a 256 pnpm-lock.yaml package.json scripts/package.json \
     pnpm-workspace.yaml > "$PACKAGE_STATE"
   git diff --binary -- scripts/package.json > "$PACKAGE_DIFF_STATE"
   corepack pnpm@10.33.2 install --frozen-lockfile --force
   shasum -a 256 pnpm-lock.yaml package.json scripts/package.json \
     pnpm-workspace.yaml | cmp "$PACKAGE_STATE" -
   git diff --exit-code -- pnpm-lock.yaml package.json pnpm-workspace.yaml
   git diff --binary -- scripts/package.json | cmp "$PACKAGE_DIFF_STATE" -
   ```

2. Preserve the earlier partial broad-suite evidence and its frozen test hash
   `88e20216f50d1dd0d8cab68e5729e030e8c1d496ff93073050dd0ab8febabac4`,
   but do not count it as a final gate: only its first shard ran. Re-run the
   existing contract suite with Corepack/pnpm 10.33.2. Add the RED tests in
   Step 1 for all four review findings and the Option A protocol, and prove each
   new assertion fails for its expected reason before changing implementation.
3. Implement exactly these six bounded workstreams in the preserved seven-file
   worktree. They jointly replace the superseded flat-file promotion design:

   a. **Persisted begin/resume/finish lifecycle:** publish the authoritative
      lock-journal before snapshot/probe/build/render/log/candidate writes;
      enforce the exact `BEGIN -> BUILDX -> RUN -> RESUME -> FINISH` order and
      one visual container; make failure/signal traps preserve all evidence;
      make resume/finish/recover Docker-free and idempotent by state.
   b. **Immutable atomic bundle:** materialize the exact seven-entry source
      bundle, validate and seal it, and extend the existing embedded native
      helper so final validation and the one
      `renameatx_np(..., RENAME_EXCL)` directory publication occur in the same
      FD-anchored process. Treat that rename as the only visual commit point.
      Keep the root manifest outside the renderer transaction; Task 4 updates it
      as a reviewed Git patch after bundle verification. Recovery never rolls
      back or rerenders a committed bundle.
   c. **Anchored no-follow recovery:** replace every pathname-first recovery,
      receipt/output, mirror, and unlock read with component-by-component
      anchored descriptors and the strict error/type/inode/link/hash taxonomy
      defined above. The mirror never becomes fallback authority; only a
      schema-optional `ENOENT` means absent. Remove the old originals/backups
      schema and implementation entirely.
   d. **Internal worker boundary:** make the asset and review renderers private
      modules behind one journal-bound, nonce-bound, one-shot dispatcher; reject
      direct CLI use, replay, fabricated/symlinked requests, live-tree input,
      second claims/writers, and output outside the six candidates. The single
      container imports both modules and produces all six outputs.
   e. **Comparison provenance:** declare
      `design/brand/exports/bodyflow-horizontal.svg` with its exact path,
      comparison-only role, and full SHA-256 in the immutable pre-render
      manifest fields and bounded digest; reject altered, redirected, undeclared,
      production-export, or app consumption before Docker or output mutation.
   f. **Canonical execution/fingerprint:** extend the bounded input digest only
      with the root `packageManager`, committed `pnpm-workspace.yaml` build
      policy, and exact `corepack pnpm@10.33.2` render-command declaration.
      Extend the environment capture/check contract with the observed
      Node/Corepack/pnpm and Docker Desktop/client/plugin/engine versions,
      realpaths, and hashes plus the composite local-route attestation. Record
      the valid Offload status-command identifier and JSON hash/length
      separately as per-run execution evidence
      excluded from both the bounded digest and fingerprint-equality checks; do
      not interpret undocumented JSON fields. Require Docker Desktop 4.80.0 or
      newer; require Docker Desktop's bundled client and Buildx/Desktop/Offload
      plugins; require empty `cliPluginsExtraDirs`; permit user/system plugin
      candidates only when they resolve to the exact bundled binary; reject
      every non-bundled shadow and all ambient `DOCKER_*`, `BUILDKIT_*`, and
      `BUILDX_*` variables plus the BuildKit source-policy override; pin the exact
      `desktop-linux` Unix-socket endpoint and local engine identity, make every
      attestation/renderer/build/run daemon command use literal
      `docker --context desktop-linux` without exception; require the
      context-bound `default` Buildx builder with `docker` driver and literal
      `buildx build --builder default`; and make every build/run pass literal
      `--platform=linux/amd64`.
      This authorizes the required schema, test, capture, and validation
      changes; it does not authorize changing dependency declarations, the
      lockfile, workspace policy, Docker context, Offload state, or any
      canonical/historical input.

   The write allowlist for this hardening commit remains exactly the Better Ahead
   manifest, `better-ahead-brand-contract.mjs` and its test,
   `capture-better-ahead-environment.mjs`, both Better Ahead render scripts,
   `run-better-ahead-brand-renderer.sh`, and `scripts/package.json` limited to
   existing `brand:better-ahead:*` commands. Root `package.json`,
   `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `canonical-renderer/**`, committed
   masters, and the historical comparison SVG remain read-only, unchanged, and
   unstaged. `environment.json`, `bundles/**`, flat exports/review paths, review
   PNGs, locks, journals, transactions, iOS files, and every other path remain
   prohibited in this commit. No new helper file is authorized: extend the
   native helper embedded in the existing renderer script.

   Run the complete expanded suite in one final unfrozen pass with exact
   Corepack/pnpm 10.33.2, then `validate:inputs`, the preserved baseline, and
   `git diff --check`. Obtain two fresh independent reviews: one focused on the
   state machine/atomic commit point and one on anchored recovery/runner
   lifecycle. Both must report no Critical or Important finding.
4. Confirm that no bundle, flat export/review output, review PNG,
   `environment.json`, lock, journal, or transaction exists. Stage only the
   allowlist and commit the hardening separately:

   ```bash
   git add design/brand/better-ahead-brand-assets.json \
     scripts/brand/better-ahead-brand-contract.mjs \
     scripts/brand/better-ahead-brand-contract.test.mjs \
     scripts/brand/capture-better-ahead-environment.mjs \
     scripts/brand/render-better-ahead-brand-assets.mjs \
     scripts/brand/render-better-ahead-brand-review.mjs \
     scripts/brand/run-better-ahead-brand-renderer.sh scripts/package.json
   git commit -m "fix(brand): harden Better Ahead render transaction"
   ```

The resulting hardening commit—not `0a5001e...` or any documentation-only
reconciliation—is the exact `task3_input_commit_sha` captured by
`environment.json` and later used as the immutable bundle directory name. The
historical comparison SVG remains read-only and unstaged throughout.

**Step 6: Capture and commit the fingerprint before rendering**

The environment capture records exact values for:

```text
implementation base SHA
exact Task 3 input commit SHA
digest of the bounded master/tooling/lockfile input set
macOS product/build version
host CPU architecture
Xcode and Swift versions
Node, Corepack, and exact pnpm 10.33.2 versions
pnpm-lock.yaml SHA-256
Sharp, libvips, and librsvg versions from the pinned container contract
canonical Docker base digest and canonical renderer-context/dependency digests
Docker Desktop/client/Buildx/Desktop-plugin/Offload-plugin/engine versions,
realpaths, and SHA-256 values plus explicit
`docker --context desktop-linux` command prefix
stable Offload status-command identifier/support capability; volatile status
JSON SHA-256/byte length remains only in the external capture evidence and later
Task 4 journal, excluded from committed `environment.json` and
fingerprint-equality checks
`desktop-linux` Unix-socket endpoint, explicit local engine identity, and
context-bound default Buildx builder with docker driver
canonical platform: linux/amd64
new master SHA-256 values
exact command: corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:render
```

The Task 4 run's freshly built image IID does not exist at this pre-render
commit and is not fabricated in `environment.json`. `begin` later records that
IID as transaction/receipt/log execution evidence after the one authorized
Buildx build and before the one visual container.

Run the capture in write mode once, then validate it without rendering:

`--write` may create only `environment.json`; it must fail if it would mutate
the manifest, masters, scripts, lockfile, or any output path.

Before that first capture, diagnose all three Docker layers: installed app/CLI,
session `PATH`, and reachable local engine. `docker --version` alone is
insufficient:

```bash
set -euo pipefail
printf 'architecture=%s\n' "$(uname -m)"
printf 'docker_app=%s\n' "$(test -d /Applications/Docker.app && printf present || printf absent)"
DOCKER_OVERRIDE_NAMES=$(env | sed -E -n \
  's/^(DOCKER_[^=]*|BUILDKIT_[^=]*|BUILDX_[^=]*|EXPERIMENTAL_BUILDKIT_SOURCE_POLICY)=.*/\1/p' \
  | LC_ALL=C sort)
printf 'docker_override_names=%s\n' "$DOCKER_OVERRIDE_NAMES"
test -z "$DOCKER_OVERRIDE_NAMES"
DOCKER_CLI_PATH=$(command -v docker)
DOCKER_CLI_REALPATH=$(node -e \
  'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' \
  "$DOCKER_CLI_PATH")
printf 'docker_cli_realpath=%s\n' "$DOCKER_CLI_REALPATH"
test "$DOCKER_CLI_REALPATH" \
  = "/Applications/Docker.app/Contents/Resources/bin/docker"
shasum -a 256 "$DOCKER_CLI_REALPATH"
MAC_USER_NAME=$(id -un)
MAC_USER_HOME=$(dscl . -read "/Users/$MAC_USER_NAME" NFSHomeDirectory \
  | awk '{print $2}')
test -n "$MAC_USER_HOME"
DOCKER_USER_CONFIG="$MAC_USER_HOME/.docker/config.json"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
if (!fs.existsSync(path)) process.exit(0);
const config = JSON.parse(fs.readFileSync(path, "utf8"));
if (!Object.hasOwn(config, "cliPluginsExtraDirs")) process.exit(0);
if (!Array.isArray(config.cliPluginsExtraDirs)) process.exit(1);
if (config.cliPluginsExtraDirs.length !== 0) process.exit(1);
' "$DOCKER_USER_CONFIG"
BUNDLED_PLUGIN_DIR="/Applications/Docker.app/Contents/Resources/cli-plugins"
for PLUGIN_NAME in docker-buildx docker-desktop docker-offload; do
  BUNDLED_PLUGIN_PATH="$BUNDLED_PLUGIN_DIR/$PLUGIN_NAME"
  test -x "$BUNDLED_PLUGIN_PATH"
  BUNDLED_PLUGIN_REALPATH=$(node -e \
    'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' \
    "$BUNDLED_PLUGIN_PATH")
  case "$BUNDLED_PLUGIN_REALPATH" in
    /Applications/Docker.app/Contents/Resources/*) ;;
    *) false ;;
  esac
  printf '%s_realpath=%s\n' "$PLUGIN_NAME" "$BUNDLED_PLUGIN_REALPATH"
  shasum -a 256 "$BUNDLED_PLUGIN_REALPATH"
  USER_PLUGIN_PATH="$MAC_USER_HOME/.docker/cli-plugins/$PLUGIN_NAME"
  if test -e "$USER_PLUGIN_PATH" || test -L "$USER_PLUGIN_PATH"; then
    USER_PLUGIN_REALPATH=$(node -e \
      'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' \
      "$USER_PLUGIN_PATH")
    test "$USER_PLUGIN_REALPATH" = "$BUNDLED_PLUGIN_REALPATH"
  fi
  for SYSTEM_PLUGIN_DIR in \
    /usr/local/lib/docker/cli-plugins \
    /usr/local/libexec/docker/cli-plugins \
    /usr/lib/docker/cli-plugins \
    /usr/libexec/docker/cli-plugins; do
    SYSTEM_PLUGIN_PATH="$SYSTEM_PLUGIN_DIR/$PLUGIN_NAME"
    if test -e "$SYSTEM_PLUGIN_PATH" || test -L "$SYSTEM_PLUGIN_PATH"; then
      SYSTEM_PLUGIN_REALPATH=$(node -e \
        'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' \
        "$SYSTEM_PLUGIN_PATH")
      test "$SYSTEM_PLUGIN_REALPATH" = "$BUNDLED_PLUGIN_REALPATH"
    fi
  done
done
DOCKER_DESKTOP_APP_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - \
  /Applications/Docker.app/Contents/Info.plist)
printf 'docker_desktop_app_version=%s\n' "$DOCKER_DESKTOP_APP_VERSION"
node -e '
const match = /^(\d+)\.(\d+)\.(\d+)/.exec(process.argv[1]);
if (!match) process.exit(1);
const actual = match.slice(1).map(Number);
const minimum = [4, 80, 0];
for (let index = 0; index < minimum.length; index += 1) {
  if (actual[index] > minimum[index]) process.exit(0);
  if (actual[index] < minimum[index]) process.exit(1);
}
' "$DOCKER_DESKTOP_APP_VERSION"
docker buildx version
docker desktop version
docker offload version --json
docker offload status --help | rg -F -- '--format'
OFFLOAD_STATUS_JSON=$(mktemp /tmp/better-ahead-offload-status.XXXXXX)
chmod 600 "$OFFLOAD_STATUS_JSON"
docker offload status --format json > "$OFFLOAD_STATUS_JSON"
test -s "$OFFLOAD_STATUS_JSON"
node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  "$OFFLOAD_STATUS_JSON"
test "$(docker context show)" = "desktop-linux"
EXPECTED_DOCKER_ENDPOINT="unix://${MAC_USER_HOME}/.docker/run/docker.sock"
ACTUAL_DOCKER_ENDPOINT=$(docker context inspect desktop-linux \
  --format '{{ .Endpoints.docker.Host }}')
test "$ACTUAL_DOCKER_ENDPOINT" = "$EXPECTED_DOCKER_ENDPOINT"
docker --context desktop-linux version
SERVER_PLATFORM_NAME=$(docker --context desktop-linux version \
  --format '{{.Server.Platform.Name}}')
printf 'docker_server_platform=%s\n' "$SERVER_PLATFORM_NAME"
case "$SERVER_PLATFORM_NAME" in
  "Docker Desktop $DOCKER_DESKTOP_APP_VERSION"*) ;;
  *) false ;;
esac
test "$(docker --context desktop-linux info --format '{{.OSType}}')" = "linux"
test "$(docker --context desktop-linux info --format '{{.OperatingSystem}}')" \
  = "Docker Desktop"
test "$(docker --context desktop-linux info --format '{{.Name}}')" \
  = "docker-desktop"
EXPLICIT_ENGINE_ID=$(docker --context desktop-linux info --format '{{.ID}}')
test -n "$EXPLICIT_ENGINE_ID"
DEFAULT_BUILDER_INSPECT=$(docker --context desktop-linux \
  buildx inspect default)
printf '%s\n' "$DEFAULT_BUILDER_INSPECT"
printf '%s\n' "$DEFAULT_BUILDER_INSPECT" \
  | rg -x 'Name:[[:space:]]+default'
printf '%s\n' "$DEFAULT_BUILDER_INSPECT" \
  | rg -x 'Driver:[[:space:]]+docker'
printf '%s\n' "$DEFAULT_BUILDER_INSPECT" \
  | rg -x 'Endpoint:[[:space:]]+desktop-linux'
LOCAL_DOCKER_EVIDENCE=$(mktemp /tmp/better-ahead-local-docker.XXXXXX)
chmod 600 "$LOCAL_DOCKER_EVIDENCE"
node scripts/brand/capture-better-ahead-environment.mjs \
  --assert-local-docker | tee "$LOCAL_DOCKER_EVIDENCE"
test -s "$LOCAL_DOCKER_EVIDENCE"
```

There is no best-effort fallback. Docker's public CLI reference guarantees JSON
output but does not publish the Offload status schema, so the plan keeps the raw
diagnostic only in the external runtime log. The bundled Offload plugin's
normalized version, realpath, and binary hash are normative runtime fingerprint
fields. The status-command identifier, JSON byte length, and SHA-256 are
recorded without guessing field semantics or committing unknown fields. The
status hash and length are volatile per-run
execution evidence and are excluded from `--check` reproducibility-equality
comparisons. The fail-closed verdict instead comes from the
composite local-route attestation above: Docker Desktop must be at least 4.80.0,
the resolved client and Buildx/Desktop/Offload plugins must be Docker Desktop's
bundled binaries, `cliPluginsExtraDirs` must be empty, and every user/system
candidate must resolve back to the exact bundled binary. All ambient variables
whose names begin `DOCKER_`, `BUILDKIT_`, or `BUILDX_`, plus the explicit
BuildKit source-policy override, must be absent; the server platform name must
agree with the application version, and the selected default context must
be `desktop-linux`, that context must resolve to the current macOS user's exact
Docker Desktop Unix socket, the context-bound `default` Buildx builder must use
the `docker` driver, and the explicit engine must report `linux`, Docker
Desktop, and `docker-desktop`. No context-less daemon API query is allowed:
Docker documents that any such API activity can wake an idle Offload session.
The 4.80.0 floor is required because that release fixed explicit
`desktop-linux` commands being silently routed to an active cloud engine.

Missing commands, older Desktop, nonzero status, empty/malformed JSON, an
unexpected endpoint/identity, or any failed assertion makes the standalone
diagnostic block stop immediately without writing repository content. The
`--assert-local-docker`, `--write`, and `--check` modes repeat the same
attestation and contractually classify environmental unavailability or
difference as exit `78`; unexpected checker/tool failures remain other nonzero
codes. They record the evidence. The renderer uses
`docker --context desktop-linux` for every daemon command, invokes the build as
`docker --context desktop-linux buildx build --builder default`, and supplies
literal `--platform=linux/amd64` plus `--iidfile`. It runs that exact IID with
literal `--platform=linux/amd64 --network none`; the build itself retains the
network access required by the pinned canonical Dockerfile. Never call
`docker offload stop` automatically: it
destroys the current cloud environment. If the route cannot be proved local,
stop and ask the operator to disable Offload/switch to the local engine, then
rerun the complete diagnostic. If
`/Applications/Docker.app` exists but its CLI is absent from `PATH`, prepend
`/Applications/Docker.app/Contents/Resources/bin` for this shell, start the
existing Docker Desktop application, and repeat the whole diagnostic. If the
application is absent, stop and request installation/startup of the official
Docker Desktop build for that Mac plus acceptance of its license terms. Do not
install only a static/Homebrew client and do not substitute another local or
remote backend. No `environment.json`, render, or Task 4 action is permitted
until every diagnostic above passes.

```bash
set -euo pipefail
node scripts/brand/capture-better-ahead-environment.mjs --write
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:environment
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate:inputs
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
git diff --check
git add design/brand/better-ahead/environment.json
git commit -m "build(brand): pin Better Ahead render environment"
```

The checker permits later output/evidence commits but requires the recorded
input commit to be an ancestor and the bounded input digest to remain exact.
Expected: no bundle, flat export/review file, review PNG, lock, journal, or
transaction exists in either Task 3 commit. The committed fingerprint predates
the first render.

---

### Task 4: Render Once, Preserve The Candidate, And Obtain Visual Approval

**Files:**

- Create:
  `design/brand/better-ahead/bundles/<TASK3_INPUT_SHA>/{exports,review,receipt.json}`
- Create:
  `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/brand-candidates/<TASK3_INPUT_SHA>/{brand-*.png,approval.md}`
- Modify: `design/brand/better-ahead-brand-assets.json`
- Modify: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md`

**Step 1: Snapshot every preserved byte before the one authorized render**

```bash
set -euo pipefail
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
find design/brand/exports \
  apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets \
  -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  | tee /tmp/better-ahead-preserved.before.sha256
git status --porcelain=v1 -uall
```

Expected: only the exact immutable bundle and later Task 4 manifest/evidence
paths can become dirty. No flat Better Ahead export/review path exists.

**Step 2: Run the new renderer exactly once in write mode**

```bash
set -euo pipefail
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:environment
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:render
```

If the renderer exits nonzero or reports a fingerprint mismatch, preserve and
report the authoritative lock-journal, exact transaction path, request/claim,
snapshot, build/render logs, candidates, staged bundle, final bundle if present,
and every recorded hash, then stop. Do not
rerun, replace hashes, manually remove a lock/quarantine, or fall back to the
legacy/host-native renderer. An unknown, unreadable, symlinked, or ambiguous
state is `BLOCKED`.

If the tested classifier yields `RECOVERY_REQUIRED`, it has proved the final
bundle is absent and the recorded pre-commit state is safely recoverable. After
audit and renewed recovery authorization, only the tested
`--recover EXACT_TRANSACTION_PATH` flow may perform its explicit pre-commit
cleanup. Any later write is a new fingerprinted single-render cycle requiring
renewed explicit render authorization.

If it yields `FINISH_REQUIRED`, the exact completion plus candidates/staging
prove the authorized visual container already ran and the final bundle is still
absent. After audit and recovery authorization, the same tested
`--recover EXACT_TRANSACTION_PATH` must revalidate those bytes and resume only
`finish`—sealing and atomic bundle publication—with zero Docker calls. Success
continues directly at Step 3. Failure preserves the journal, completion,
candidates, staging, and logs and stops again; it never requests or performs a
second render.

If the classifier finds the exact complete final bundle and matching receipt,
that physical commit dominates a lagging `PUBLISHING_BUNDLE`,
`BUNDLE_COMMITTED`, or `CLEANUP_REQUIRED` journal label:
the one authorized render is already complete. After audit and recovery
authorization, `--recover EXACT_TRANSACTION_PATH` may only verify the committed
bundle/receipt/output hashes and perform journal-enumerated cleanup/unlock. It must not remove or
restore the bundle, rebuild candidates, invoke Docker, recapture the
fingerprint, or rerender. On success continue directly at Step 3; on failure
retain the journal and all remaining evidence and stop again.

**Step 3: Prove old bytes did not move**

```bash
set -euo pipefail
find design/brand/exports \
  apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets \
  -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  | tee /tmp/better-ahead-preserved.after.sha256
cmp /tmp/better-ahead-preserved.before.sha256 \
  /tmp/better-ahead-preserved.after.sha256
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
TASK3_INPUT_SHA=$(node -e '
const fs = require("node:fs");
const value = JSON.parse(fs.readFileSync(
  "design/brand/better-ahead/environment.json", "utf8"
)).task3_input_commit_sha;
if (!/^[0-9a-f]{40}$/.test(value)) process.exit(1);
process.stdout.write(value);
')
BUNDLE_ROOT="design/brand/better-ahead/bundles/$TASK3_INPUT_SHA"
test -d "$BUNDLE_ROOT"
test ! -L "$BUNDLE_ROOT"
test -f "$BUNDLE_ROOT/receipt.json"
node scripts/brand/better-ahead-brand-contract.mjs \
  --check-bundle "$BUNDLE_ROOT"
```

Expected: `cmp` exit 0. The independent bundle check proves the exact seven
entries, receipt, six output hashes, Task 3 SHA, and environment binding without
requiring or changing a root-manifest pointer.

**Step 4: Register and commit the auditable candidate before asking for approval**

Create an ordinary source patch to
`design/brand/better-ahead-brand-assets.json`—outside the renderer—with exactly
these mutable fields derived from the verified receipt:

```text
active_candidate.bundle_path
active_candidate.receipt_sha256
active_candidate.task3_input_commit_sha
new_assets[].role
new_assets[].bundle_relative_path
new_assets[].sha256
new_assets[].byte_length
```

No renderer/recovery command creates this patch. Require the manifest to match
the exact clean pre-render Git blob before editing; if it is dirty or changed,
stop as a normal Git conflict. These fields, candidate `brand_version`, and
`approval_state` are the only mutable projection excluded from the bounded
input digest. Prove that digest is identical before and after this patch, while
normal validation requires `active_candidate` to match the receipt exactly.

Copy the three review PNGs mechanically, without re-encoding, to a
candidate-versioned evidence directory and prove each copy with `cmp`. Then:

```bash
set -euo pipefail
TASK3_INPUT_SHA=$(node -e '
const fs = require("node:fs");
const value = JSON.parse(fs.readFileSync(
  "design/brand/better-ahead/environment.json", "utf8"
)).task3_input_commit_sha;
if (!/^[0-9a-f]{40}$/.test(value)) process.exit(1);
process.stdout.write(value);
')
BUNDLE_ROOT="design/brand/better-ahead/bundles/$TASK3_INPUT_SHA"
EVIDENCE_ROOT="docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/brand-candidates/$TASK3_INPUT_SHA"
node scripts/brand/better-ahead-brand-contract.mjs \
  --check-bundle "$BUNDLE_ROOT"
BOUNDED_DIGEST_BEFORE=$(node scripts/brand/better-ahead-brand-contract.mjs \
  --print-bounded-digest)
node scripts/brand/better-ahead-brand-contract.mjs \
  --register-candidate "$BUNDLE_ROOT"
test "$(node scripts/brand/better-ahead-brand-contract.mjs \
  --print-bounded-digest)" = "$BOUNDED_DIGEST_BEFORE"
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate
mkdir -p "$EVIDENCE_ROOT"
cp -- "$BUNDLE_ROOT/review/better-ahead-comparison.png" \
  "$EVIDENCE_ROOT/brand-comparison.png"
cp -- "$BUNDLE_ROOT/review/better-ahead-reduced-sizes.png" \
  "$EVIDENCE_ROOT/brand-reduced-sizes.png"
cp -- "$BUNDLE_ROOT/review/better-ahead-light-dark.png" \
  "$EVIDENCE_ROOT/brand-light-dark.png"
cmp "$BUNDLE_ROOT/review/better-ahead-comparison.png" \
  "$EVIDENCE_ROOT/brand-comparison.png"
cmp "$BUNDLE_ROOT/review/better-ahead-reduced-sizes.png" \
  "$EVIDENCE_ROOT/brand-reduced-sizes.png"
cmp "$BUNDLE_ROOT/review/better-ahead-light-dark.png" \
  "$EVIDENCE_ROOT/brand-light-dark.png"
node scripts/brand/better-ahead-brand-contract.mjs \
  --check-bundle "$BUNDLE_ROOT"
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate
git diff --check
git add "$BUNDLE_ROOT" design/brand/better-ahead-brand-assets.json \
  "$EVIDENCE_ROOT"
git commit -m "feat(brand): add Better Ahead candidate wordmark"
```

**Step 5: Stop for the blocking human visual checkpoint**

Present the comparison, reduced-size, and Light/Dark boards. Approval must cover:

- spelling and immediate reading of “Better Ahead”;
- symbol fidelity and clear space;
- balance between the preserved symbol and longer wordmark;
- forward motion without a forced or aggressive feel;
- Light/Dark contrast;
- 44-point symbol and 96-point wordmark legibility;
- splash composition and no clipping;
- no BodyFlow wordmark or slogan embedded in any output.

Do not proceed to the Asset Catalog until the user explicitly approves this
candidate. If rejected, retain the rejected commit and evidence, revise only new
masters, increment the candidate version, create a new hardening input commit
and fingerprint, and publish a new immutable bundle under that new Task 3 SHA.
The rejected bundle, receipt, commit, and evidence remain untouched. A
successful but visually rejected render leaves no transaction quarantine, so
the next cycle starts only from the committed rejected candidate and new input
commit. Never rewrite, reuse, or discard the rejected audit trail.

**Step 6: Freeze only after explicit approval**

Derive the same `TASK3_INPUT_SHA` and `BUNDLE_ROOT`, revalidate the bundle, and
create only
`brand-candidates/<TASK3_INPUT_SHA>/approval.md` with `apply_patch`. Record the
exact approval text and UTC date, full bundle path, Task 3 input SHA, receipt
SHA-256, and all six relative output paths/hashes/byte lengths. Before changing
approval state, serialize `active_candidate` canonically. Set only
`brand_version: 1.0.0` and `approval_state: approved`; the serialized candidate
must remain byte-identical and the bounded digest must remain unchanged. Then
run:

```bash
set -euo pipefail
TASK3_INPUT_SHA=$(node -e '
const fs = require("node:fs");
const value = JSON.parse(fs.readFileSync(
  "design/brand/better-ahead/environment.json", "utf8"
)).task3_input_commit_sha;
if (!/^[0-9a-f]{40}$/.test(value)) process.exit(1);
process.stdout.write(value);
')
BUNDLE_ROOT="design/brand/better-ahead/bundles/$TASK3_INPUT_SHA"
APPROVAL_ROOT="docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/brand-candidates/$TASK3_INPUT_SHA"
APPROVAL_FILE="$APPROVAL_ROOT/approval.md"
node scripts/brand/better-ahead-brand-contract.mjs \
  --check-bundle "$BUNDLE_ROOT"
test -f "$APPROVAL_FILE"
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:render:check
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
git diff --check
git add design/brand/better-ahead-brand-assets.json \
  "$APPROVAL_FILE" \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md
git commit -m "docs(brand): approve Better Ahead asset family"
```

Expected: Docker-free check mode proves the approved bundle/receipt bytes are
unchanged, and preserved assets still match their historical manifest.

---

### Task 5: Replace Product-Specific Catalog Interfaces With Semantic Assets

**Files:**

- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowSymbol.imageset`
- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowWordmark.imageset`
- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowHorizontal.imageset`
- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowMonochrome.imageset`
- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowNegative.imageset`
- Delete from app target:
  `Resources/Assets.xcassets/BodyFlowLaunch.imageset`
- Create: `Resources/Assets.xcassets/BrandSymbol.imageset`
- Create: `Resources/Assets.xcassets/BrandWordmark.imageset`
- Create: `Resources/Assets.xcassets/BrandLogoHorizontal.imageset`
- Create: `Resources/Assets.xcassets/BrandMonochrome.imageset`
- Create: `Resources/Assets.xcassets/BrandNegative.imageset`
- Create: `Resources/Assets.xcassets/BrandLaunch.imageset`
- Rename: `DesignSystem/BodyFlowBrandAsset.swift` to
  `DesignSystem/BrandAsset.swift`
- Create: `DesignSystem/Components/BrandLogoView.swift`
- Modify: `DesignSystem/Components/ScreenStateView.swift`
- Modify: `Features/Auth/SplashView.swift`
- Modify: `Features/Profile/CoachPersonaPickerView.swift`
- Rename: `BodyFlowTests/BodyFlowBrandAssetTests.swift` to
  `BodyFlowTests/BrandAssetTests.swift`
- Modify: `BodyFlowTests/ScreenStateTests.swift`
- Modify: `BodyFlowUITests/BodyFlowUITests.swift`
- Modify: `BodyFlowUITests/Prompt14AccessibilityUITests.swift`
- Modify: `scripts/brand/bodyflow-brand-contract.test.mjs`
- Modify: `scripts/brand/bodyflow-brand-renderer-contract.test.mjs`
- Modify: `scripts/brand/run-bodyflow-brand-renderer.sh`

**Interfaces:**

```swift
enum BrandAsset: String, CaseIterable, Sendable {
    case symbol = "BrandSymbol"
    case wordmark = "BrandWordmark"
    case horizontal = "BrandLogoHorizontal"
    case monochrome = "BrandMonochrome"
    case negative = "BrandNegative"
    case launch = "BrandLaunch"
}

enum BrandLogoPresentation: Equatable, Sendable {
    case asset(BrandAsset)
    case symbolAndText(symbol: BrandAsset, text: String)
}
```

`BrandLogoView` resolves the requested asset. When a new wordmark/lockup cannot
load, it presents the preserved symbol plus `Better Ahead`. It never resolves a
BodyFlow image set or former-name text.

Regardless of whether the visible representation is vector art or fallback
text, `BrandLogoView` exposes one textual accessibility representation labeled
`Better Ahead` with the existing identifier `brand.product-name`. Decorative
image children are hidden. This deliberately preserves the element contract
used by `Prompt14AccessibilityUITests` (`staticTexts`), while the visual asset
remains an image.

**Step 1: Update tests first and verify RED**

Tests must require neutral catalog names, Better Ahead accessibility labels,
all semantic images load from the compiled iOS app bundle, the Node source gate
validates their provenance against the exact immutable Git asset bundle,
missing-wordmark fallback resolves to symbol + Better Ahead, and former catalog
names do not load. Update the accessibility UI
test first to require `staticTexts["brand.product-name"]`, label Better Ahead,
and no duplicate accessible image child.

```bash
set -euo pipefail
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/BrandAssetTests \
  -only-testing:BodyFlowTests/ScreenStateTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/Prompt14AccessibilityUITests test
```

Expected: FAIL against the old catalog/type.

**Step 2: Copy preserved bytes and approved new bytes into semantic sets**

- Copy the committed historical symbol/monochrome/negative SVG bytes exactly;
  renaming their payload files is allowed only if `cmp` proves byte equality.
- Resolve `active_candidate.bundle_path` from the approved Better Ahead root
  manifest, require that exact path to equal
  `design/brand/better-ahead/bundles/<environment.task3_input_commit_sha>`, and
  validate its `receipt.json` plus all six hashes before copying anything.
  Copy wordmark/horizontal/launch only from that bundle's `exports` directory.
  Do not scan `bundles`, choose a newest directory, follow a symlink/alias, or
  use a rejected bundle.
- Do not alter AppIcon payloads or their `Contents.json`.
- Use `preserves-vector-representation: true`; use `original` for multicolor
  assets and `template` only for monochrome/negative.
- Remove all six `BodyFlow*.imageset` directories from the app catalog. The
  historical assets remain in `design/brand`, which is outside the target.

**Step 3: Integrate actual production views**

- Replace the text-only top identity bar with `BrandLogoView`.
- Replace splash `Text("BodyFlow")` with the approved launch/wordmark and
  localized slogan.
- Use the same semantic brand header in the profile Flow-persona sheet.
- Keep the source-level design-system prefixes `BodyFlowColor`,
  `BodyFlowTypography`, and `BodyFlowSpacing`; they are internal compatibility
  identifiers and not public identity.

**Step 4: Run asset and native gates**

Before running the legacy tests, update only their active-catalog assertion:
the historical contract continues validating every approved BodyFlow
source/master/export hash, while active Asset Catalog coverage moves to the new
Better Ahead tests. Do not change any historical expected hash. Keep the legacy
renderer transaction behavior unchanged, but add a fail-closed admission guard:
if the Better Ahead manifest or any neutral brand image set exists, legacy
`--write` exits before snapshot/build/promotion and cannot overwrite the active
catalog. Add a fake-boundary test proving that refusal. Historical reproduction
remains possible from a detached worktree at the historical SHA;
`brand:render:check` is not run against the rebranded catalog.

```bash
set -euo pipefail
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:catalog
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate
corepack pnpm@10.33.2 --filter @mpp/scripts brand:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:validate
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/BrandAssetTests \
  -only-testing:BodyFlowTests/ScreenStateTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/Prompt14AccessibilityUITests test
git diff --exit-code -- \
  apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings
git diff --check
```

Expected: semantic assets load; historical catalog names do not; no Asset
Catalog warning; preserved hashes remain exact. The legacy suite is green in
archive-only mode and its fake renderer test proves legacy `--write` refuses
the active Better Ahead catalog before any snapshot or promotion.

**Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/DesignSystem \
  apps/ios/BodyFlow/BodyFlow/Features/Auth/SplashView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift \
  apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets \
  apps/ios/BodyFlow/BodyFlowTests/ScreenStateTests.swift \
  apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITests.swift \
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14AccessibilityUITests.swift \
  scripts/brand/bodyflow-brand-contract.test.mjs \
  scripts/brand/bodyflow-brand-renderer-contract.test.mjs \
  scripts/brand/run-bodyflow-brand-renderer.sh
git add -A -- \
  apps/ios/BodyFlow/BodyFlowTests/BodyFlowBrandAssetTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/BrandAssetTests.swift
git commit -m "feat(ios): integrate semantic Better Ahead brand assets"
```

---

### Task 6: Replace Public Product And Agent Copy, Including About

**Files:**

- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFieldMessage.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotPresentation.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/PersonaStepView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingCompletionView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingContainerView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersona.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Profile/AboutView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/MascotPresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/MascotAccessibilityModelTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/OnboardingCompletionTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14TodayMascotUITests.swift`

**Step 1: Write failing public-copy tests**

Require these semantics in both supported languages:

```text
product title: Better Ahead
guide title: Flow
category: Como usar o Better Ahead / Using Better Ahead
Flow styles: Focus, Impulse, Zen (names stable; descriptions localized)
persona chooser: Escolha o estilo do Flow / Choose Flow's style
about title: Sobre o Better Ahead / About Better Ahead
```

The reviewed style descriptions are:

| Style | pt-BR | en |
| --- | --- | --- |
| Focus | Direto, firme e objetivo. | Direct, firm, and objective. |
| Impulse | Motivador, positivo e energético. | Motivating, positive, and energetic. |
| Zen | Calmo, didático e acolhedor. | Calm, educational, and supportive. |

Store only the descriptions under
`flow.style.{focus,impulse,zen}.description`; the three stable display names
come from the exhaustive code mapping and are not translated.

Accessibility announcements must say Flow, never “Mascote BodyFlow” or “coach
BodyFlow”. Server enum/wire values and telemetry identifiers remain unchanged.

**Step 2: Run focused tests and verify RED**

```bash
set -euo pipefail
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/AppRouterTests \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/MascotAccessibilityModelTests \
  -only-testing:BodyFlowTests/OnboardingCompletionTests test
```

Expected: FAIL on old public copy and missing About route.

**Step 3: Implement the public copy and About surface**

- Add a typed profile About route; do not overload an unrelated demo detail.
- About shows semantic logo, product name, localized slogan, localized
  descriptor, localized Flow role line, app marketing/build version, privacy
  and support rows only when actual configured URLs exist. Do not
  invent legal entities, URLs, endorsements, or medical claims.
- Rename public mascot/coach headings to Flow and public persona controls to
  “Flow style”. Keep internal `Mascot*` and `Coach*` types.
- Map every `SelectableCoachPersona` code exhaustively to the stable public
  names `Focus`, `Impulse`, and `Zen` plus reviewed pt-BR/en descriptions from
  the String Catalog. `MascotPresentation.options/optionsByCode` must not render
  the API `option.name` or `option.description`; those wire fields remain
  decoded and unchanged for compatibility. Tests inject conflicting old-brand
  server text and prove it cannot reach the public Flow style controls.
- Change `.usingBodyFlow` presentation only; keep its raw/API contract.
- Replace the displayed demo markdown occurrence “aplicativo BodyFlow” with
  Better Ahead. Do not alter API schema or content identifiers.
- Auth layout, shell header, onboarding explanatory surface, and About consume
  `BrandIdentity`; they do not duplicate brand literals.

**Step 4: Run GREEN and commit**

```bash
set -euo pipefail
CATALOG_SNAPSHOT=$(mktemp /tmp/better-ahead-flow-copy.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  > "$CATALOG_SNAPSHOT"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/AppRouterTests \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/MascotAccessibilityModelTests \
  -only-testing:BodyFlowTests/OnboardingCompletionTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/Prompt14TodayMascotUITests test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  | cmp "$CATALOG_SNAPSHOT" -
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App \
  apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFieldMessage.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot \
  apps/ios/BodyFlow/BodyFlow/Features/Onboarding \
  apps/ios/BodyFlow/BodyFlow/Features/Profile \
  apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersona.swift \
  apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift \
  apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotAccessibilityModelTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/OnboardingCompletionTests.swift \
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14TodayMascotUITests.swift
git commit -m "feat(ios): adopt Better Ahead and Flow public copy"
```

Before committing, inspect the staged test directory and ensure unrelated test
files are not included; narrow `git add` to the named files if any other test is
dirty.

---

### Task 7: Localize Auth, Onboarding, Navigation, And Shared States

**Files:**

- Modify: `Resources/Localizable.xcstrings`
- Create: `config/brand/better-ahead-ios-public-surfaces.json`
- Create: `scripts/ios/better-ahead-localization-contract.mjs`
- Create: `scripts/ios/better-ahead-localization-contract.test.mjs`
- Modify: `scripts/package.json`
- Modify: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md`
- Modify/audit: `App/AppRootView.swift`
- Modify/audit: `App/AppTab.swift`
- Modify/audit: `App/AppRouter.swift`
- Modify/audit: `DesignSystem/Components/ScreenStateView.swift`
- Modify/audit: all files in `Features/Auth/`
- Modify/audit: all files in `Features/Onboarding/`
- Modify/audit: `Core/Coach/CoachPersona.swift`
- Modify/audit: `Features/Profile/CoachPersonaPickerView.swift`
- Create: `BodyFlowUITests/UITestLanguage.swift`
- Modify: `BodyFlowUITests/BodyFlowUITestSupport.swift`
- Modify: `BodyFlowUITests/Prompt14UITestSupport.swift`
- Modify: `BodyFlowUITests/BodyFlowUITests.swift`
- Create: `BodyFlowUITests/BetterAheadLocalizationUITests.swift`
- Modify: matching Auth, AppTab, Onboarding, CoachPersona, ScreenState tests

**Interfaces:**

- Xcode's compiler extraction is the authority for static SwiftUI localized
  APIs. One deliberate extraction build is allowed in this task; ordinary
  builds remain protected by `SWIFT_EMIT_LOC_STRINGS = NO`.
- Any client-owned `String` returned from a computed property, interpolation,
  ternary, validation model, or presentation model must resolve through the
  localization boundary explicitly.
- Server-provided article/domain values are displayed as server content and are
  not translated client-side. The three known Flow style names/descriptions are
  the explicit exception established in Task 6: UI copy is keyed by the stable
  code and never passes the corresponding raw server labels through.
- The contract has two explicit scopes: `foundation` for this task and `all`
  for Task 8. A key/producer has an exact scope and ownership classification;
  an unchecked “future key” bucket is prohibited.

**Step 1: Add failing catalog completeness tests**

The Node contract parses the String Catalog and the curated iOS public-surface
inventory. It rejects:

- a client-owned public key without reviewed `pt-BR` and `en` values;
- `needs_review`, stale, or empty translation states;
- an unlocalized dynamic presentation literal;
- fixed `pt_BR` formatting in a user-facing formatter;
- product/agent proper names placed in translatable values inconsistently;
- a broad file/directory wildcard allowlist.

The inventory contains exact file paths and exact producer/key records only. It
classifies each as `client_owned`, `server_owned`, or `technical`, and assigns
`foundation` or `authenticated`. Seed it from the approved base, including the
confirmed SwiftUI/presentation paths, `AppTab.swift`,
`OnboardingFlowModel.swift`, and every additional producer discovered during
extraction. Xcode owns discovery of static localized API calls; the custom
contract checks dynamic/computed/ternary/interpolated producers and ownership
classifications rather than pretending a regular expression is a full Swift
parser. Any unclassified public producer fails; directory globs and whole-file
exemptions are prohibited.

```bash
node --test scripts/ios/better-ahead-localization-contract.test.mjs
```

Expected: RED because the current app has no complete catalog.

**Step 2: Run the one deliberate static-string extraction**

Start from a clean Task 6 commit and run exactly:

```bash
set -euo pipefail
EXTRACTION_DERIVED=$(mktemp -d /tmp/better-ahead-extraction.XXXXXX)
CATALOG_PATH=apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings
EXTRACTION_STATE=$(mktemp -d /tmp/better-ahead-extraction-state.XXXXXX)
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository . --exclude-exact "$CATALOG_PATH" \
  > "$EXTRACTION_STATE/before.json"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -derivedDataPath "$EXTRACTION_DERIVED" \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  SWIFT_EMIT_LOC_STRINGS=YES build
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository . --exclude-exact "$CATALOG_PATH" \
  > "$EXTRACTION_STATE/after.json"
cmp "$EXTRACTION_STATE/before.json" "$EXTRACTION_STATE/after.json"
CATALOG_DIFF_STATUS=0
git diff --quiet -- "$CATALOG_PATH" || CATALOG_DIFF_STATUS=$?
test "$CATALOG_DIFF_STATUS" -eq 1
```

Expected: the extraction changes `Resources/Localizable.xcstrings` and the
exact-exclusion state comparison proves every other pending/tracked/untracked
path remained byte-identical. Review the complete catalog diff, assign
every extracted key to an exact scope/owner, and record the command/result in
preflight evidence. Do not run another extraction build in this plan. Keys in
the `authenticated` scope may remain explicitly incomplete until Task 8;
foundation keys may not.

**Step 3: Localize the launch/auth/shared surface**

Cover AppRoot loading/errors, all auth titles/messages/fields/actions,
validation/accessibility announcements, brand header, splash loading label,
and every shared screen-state title/message/retry action. Preserve input
identifiers and error cases.

**Step 4: Localize onboarding and navigation**

Cover all seven onboarding steps, validation messages, selection state,
country/time-zone search, review rows, Flow styles, consent development labels,
tab titles, registration-kind titles, and navigation headings. Use the active
locale for dates/numbers/regions; retain IANA identifiers and stored enum/raw
values.

**Step 5: Make all three UI-test launch paths locale-safe**

Modify:

```text
BodyFlowUITests/BodyFlowUITestSupport.swift
BodyFlowUITests/Prompt14UITestSupport.swift
BodyFlowUITests/BodyFlowUITests.swift (private launch and relaunch paths)
```

Create one shared typed locale. Existing tests default explicitly to pt-BR;
every relaunch reapplies the selected language instead of replacing its launch
arguments:

```swift
enum UITestLanguage {
    case portugueseBrazil
    case englishUnitedStates

    var launchArguments: [String] { get }
}
```

The exact pairs are:

```text
pt-BR: -AppleLanguages (pt-BR) -AppleLocale pt_BR
en-US: -AppleLanguages (en)    -AppleLocale en_US
```

The helper rejects caller arguments that already contain either locale flag,
then appends exactly one pair while retaining scenario arguments. Add
`testPortugueseFoundationSmoke` and `testEnglishFoundationSmoke` to
`BetterAheadLocalizationUITests` for splash, auth, onboarding, tabs, Flow
style, profile, and About.

**Step 6: Run the scoped contract, both UI locales, and commit**

```bash
set -euo pipefail
CATALOG_SNAPSHOT=$(mktemp /tmp/better-ahead-foundation-catalog.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  > "$CATALOG_SNAPSHOT"
corepack pnpm@10.33.2 --filter @mpp/scripts ios:localization:test:foundation
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/AuthFormStateTests \
  -only-testing:BodyFlowTests/AppTabTests \
  -only-testing:BodyFlowTests/OnboardingFlowModelTests \
  -only-testing:BodyFlowTests/OnboardingPresentationTests \
  -only-testing:BodyFlowTests/CoachPersonaTests \
  -only-testing:BodyFlowTests/ScreenStateTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/BetterAheadLocalizationUITests/testPortugueseFoundationSmoke \
  -only-testing:BodyFlowUITests/BetterAheadLocalizationUITests/testEnglishFoundationSmoke test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  | cmp "$CATALOG_SNAPSHOT" -
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/App \
  apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/ScreenStateView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Auth \
  apps/ios/BodyFlow/BodyFlow/Features/Onboarding \
  apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersona.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift \
  apps/ios/BodyFlow/BodyFlowTests \
  apps/ios/BodyFlow/BodyFlowUITests \
  config/brand/better-ahead-ios-public-surfaces.json \
  scripts/ios scripts/package.json \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md
git commit -m "feat(ios): localize Better Ahead auth and onboarding"
```

The scripts entry is:

```json
{
  "ios:localization:test:foundation": "node ios/better-ahead-localization-contract.mjs --check --scope foundation && node --test ios/better-ahead-localization-contract.test.mjs",
  "ios:localization:test:all": "node ios/better-ahead-localization-contract.mjs --check --scope all && node --test ios/better-ahead-localization-contract.test.mjs"
}
```

Inspect staged files before commit; only paths named in this task may be staged.
The `all` scope is intentionally RED until Task 8, but every remaining failure
must name an exact authenticated key/producer already present in the inventory.

---

### Task 8: Complete English Localization Across The Authenticated Client

**Files:**

- Modify: `Resources/Localizable.xcstrings`
- Modify: `config/brand/better-ahead-ios-public-surfaces.json`
- Modify: `scripts/ios/better-ahead-localization-contract.mjs`
- Modify: `scripts/ios/better-ahead-localization-contract.test.mjs`
- Modify/audit these feature groups and their presentation helpers:
  - `Features/Today/*.swift`
  - `Features/Register/*.swift`
  - `Features/Plan/*.swift`
  - `Features/Progress/*.swift`
  - `Features/History/*.swift`
  - `Features/Routine/*.swift`
  - `Features/Library/*.swift`
  - `Features/Mascot/*.swift`
  - `Features/Profile/*.swift`
  - `Features/Shared/*.swift`
- Modify/audit client-owned fixture labels in:
  - `Core/Models/AppFixtures.swift`
  - `Core/Demo/DemoBodyFlowFixtures.swift`
  - `Core/Demo/DemoPrompt14Fixtures.swift`
- Modify/audit: `Core/Demo/DemoBodyFlowRepository.swift`
- Modify matching presentation tests and bilingual UI smoke tests
- Create: `apps/ios/BodyFlow/BodyFlowTests/LocalizationFormattingTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/BetterAheadLocalizationUITests.swift`

**Step 1: Expand the failing inventory**

The localization contract must enumerate every Swift file with a public
SwiftUI string or client-owned presentation string. The approved-base audit
found at least 74 such files, but the actual gate is zero unclassified public
producer, not a numeric threshold. Technical IDs, system image names, endpoint
paths, telemetry values, server payloads, and persisted raw values are
explicitly classified rather than translated. Include the reachable fixture
label in `DemoBodyFlowRepository.swift`; a whole-file exemption is forbidden.

Run:

```bash
corepack pnpm@10.33.2 --filter @mpp/scripts ios:localization:test:all
```

Expected: RED until every client-owned public key in these groups has reviewed
Portuguese and English values.

**Step 2: Localize and prove reviewer-sized feature batches**

For each group, localize titles, buttons, empty/error/stale states, sheets,
accessibility labels/hints/announcements, units owned by the client, and date or
number formatting. Preserve official numeric values and server text. In
particular remove fixed `pt_BR` formatting from:

```text
Features/Mascot/MascotPresentation.swift
Features/Onboarding/BodyDataStepView.swift
Features/Plan/PlanComponents.swift
Features/Progress/ProgressComponents.swift
Features/Today/TodayHeaderSection.swift
```

The `en_US_POSIX` parser locale in Progress is technical and remains unchanged.

Presentation/formatting APIs accept an injected `SupportedAppLanguage`,
`Locale`, or `LocalizedStringResource`; tests exercise both pt-BR and English,
never just the process locale. String Catalog plural variations cover 0, 1,
and 2 for days, minutes, contents, stages, and items in both languages. Fixed
time-zone tests also prove localized decimal/thousands/date/time output,
including `7.420`/`7,420` and `78,4`/`78.4` where appropriate.

The localization contract supports cumulative exact scopes
`today-register`, `plan-progress-history`, and
`routine-library-flow-profile`. For each batch: make the intended
source/catalog/test changes; run its cumulative contract; snapshot both
catalogs; run the named presentation tests in both languages; compare the
post-build catalogs to that snapshot to prove ordinary Xcode execution did not
autoedit them; then commit and require a clean worktree. Do not run another
extraction build.

Commit after each green feature batch (the UI smoke file is not staged here):

```bash
set -euo pipefail
node scripts/ios/better-ahead-localization-contract.mjs --check --scope today-register
BATCH_CATALOG=$(mktemp /tmp/better-ahead-today-register.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings > "$BATCH_CATALOG"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/TodayPresentationTests \
  -only-testing:BodyFlowTests/RegistrationPresentationTests test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings | cmp "$BATCH_CATALOG" -
git add apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Features/Today \
  apps/ios/BodyFlow/BodyFlow/Features/Register \
  apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/RegistrationPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LocalizationFormattingTests.swift \
  config/brand/better-ahead-ios-public-surfaces.json \
  scripts/ios/better-ahead-localization-contract.mjs \
  scripts/ios/better-ahead-localization-contract.test.mjs
git commit -m "feat(ios): localize Today and registration"
git diff --exit-code
test -z "$(git status --porcelain=v1 -uall)"

node scripts/ios/better-ahead-localization-contract.mjs --check --scope plan-progress-history
BATCH_CATALOG=$(mktemp /tmp/better-ahead-plan-progress.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings > "$BATCH_CATALOG"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/PlanPresentationTests \
  -only-testing:BodyFlowTests/ProgressPresentationTests \
  -only-testing:BodyFlowTests/HistoryPresentationTests \
  -only-testing:BodyFlowTests/LocalizationFormattingTests test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings | cmp "$BATCH_CATALOG" -
git add apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Features/Plan \
  apps/ios/BodyFlow/BodyFlow/Features/Progress \
  apps/ios/BodyFlow/BodyFlow/Features/History \
  apps/ios/BodyFlow/BodyFlowTests/PlanPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/HistoryPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LocalizationFormattingTests.swift \
  config/brand/better-ahead-ios-public-surfaces.json \
  scripts/ios/better-ahead-localization-contract.mjs \
  scripts/ios/better-ahead-localization-contract.test.mjs
git commit -m "feat(ios): localize plan progress and history"
git diff --exit-code
test -z "$(git status --porcelain=v1 -uall)"

node scripts/ios/better-ahead-localization-contract.mjs --check --scope routine-library-flow-profile
BATCH_CATALOG=$(mktemp /tmp/better-ahead-routine-flow.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings > "$BATCH_CATALOG"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/RoutinePresentationTests \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/LocalizationFormattingTests test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings | cmp "$BATCH_CATALOG" -
git add apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Features/Routine \
  apps/ios/BodyFlow/BodyFlow/Features/Library \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot \
  apps/ios/BodyFlow/BodyFlow/Features/Profile \
  apps/ios/BodyFlow/BodyFlow/Features/Shared \
  apps/ios/BodyFlow/BodyFlow/Core/Models/AppFixtures.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowRepository.swift \
  apps/ios/BodyFlow/BodyFlowTests/RoutinePresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotPresentationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/LocalizationFormattingTests.swift \
  config/brand/better-ahead-ios-public-surfaces.json \
  scripts/ios/better-ahead-localization-contract.mjs \
  scripts/ios/better-ahead-localization-contract.test.mjs
git commit -m "feat(ios): localize routine library Flow and profile"
git diff --exit-code
test -z "$(git status --porcelain=v1 -uall)"
```

**Step 3: Add bilingual authenticated smoke coverage**

Using the existing loaded demo scenarios, test both languages for:

```text
all five tabs
Today header and one state
registration sheet
plan root
progress root
library root
Flow card/detail
profile and About
```

Assertions use stable accessibility identifiers for navigation and localized
visible strings only where copy itself is under test. Do not rename internal
IDs such as `tab.hoje`, `screen.mascot.detail`, or scenario arguments.

Keep the two foundation methods from Task 7 and add
`testPortugueseAuthenticatedSmoke` plus `testEnglishAuthenticatedSmoke`. Run
the entire class and commit it separately so the test is never referenced by a
prior commit before it exists. In the same file add these visual-evidence tests
before the commit:

```text
testBrandSurfacesLightAndDark
  -AppleInterfaceStyle Light, then Dark
  captures splash, Today, Flow, and About in each appearance

testBrandSurfacesAtAccessibilityDynamicType
  -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  captures onboarding, Today, and About

testFlowWithReduceMotion
  --ui-testing-prompt14-reduce-motion
  captures the Flow surface after its stable state is reached
```

Each launch also uses the typed locale helper (pt-BR for the visual matrix;
the two smoke methods separately prove pt-BR and English). Every requested
surface attaches an `XCUIScreen.main.screenshot()` with a stable name and
`XCTAttachment.Lifetime.keepAlways`. Tests assert no clipping/truncation marker,
the expected semantic accessibility element, and stable navigation before
capturing; screenshots do not replace assertions.

Record the exact attachment matrix in
`better-ahead-ios-public-surfaces.json`; the contract expands these literal
arrays into exact names (no glob):

```text
{pt-br,en} × {splash,sign-in,onboarding-welcome,onboarding-flow-style,today,flow,profile,about}
{light,dark} × {splash,today,flow,about}
accessibility-xxxl × {onboarding,today,about}
reduce-motion × {flow}
```

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/BetterAheadLocalizationUITests test
git add apps/ios/BodyFlow/BodyFlowUITests/BetterAheadLocalizationUITests.swift \
  config/brand/better-ahead-ios-public-surfaces.json
git commit -m "test(ios): cover Better Ahead in both app languages"
git diff --exit-code
test -z "$(git status --porcelain=v1 -uall)"
```

**Step 4: Run full localization contract and adjacent tests**

```bash
set -euo pipefail
CATALOG_SNAPSHOT=$(mktemp /tmp/better-ahead-all-catalog.XXXXXX)
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  > "$CATALOG_SNAPSHOT"
corepack pnpm@10.33.2 --filter @mpp/scripts ios:localization:test:all
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/TodayPresentationTests \
  -only-testing:BodyFlowTests/RegistrationPresentationTests \
  -only-testing:BodyFlowTests/PlanPresentationTests \
  -only-testing:BodyFlowTests/ProgressPresentationTests \
  -only-testing:BodyFlowTests/HistoryPresentationTests \
  -only-testing:BodyFlowTests/RoutinePresentationTests \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/LocalizationFormattingTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/BetterAheadLocalizationUITests test
shasum -a 256 apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings \
  | cmp "$CATALOG_SNAPSHOT" -
git diff --check
```

Expected: zero missing or review-state catalog entries. Server-owned article
content may remain in the payload language, but the three known Flow style
labels use the client-owned mapping from Task 6 and every iOS-owned control and
presentation wrapper is bilingual. Workstream 2 must make reachable server
content bilingual before integrated client delivery.

---

### Task 9: Add A Narrow Public-Content And Compiled-Resource Gate

**Files:**

- Create: `config/brand/better-ahead-ios-public-content-allowlist.json`
- Create: `scripts/brand/better-ahead-public-content-contract.mjs`
- Create: `scripts/brand/better-ahead-public-content-contract.test.mjs`
- Create: `scripts/ios/better-ahead-xcresult-contract.mjs`
- Create: `scripts/ios/better-ahead-xcresult-contract.test.mjs`
- Create: `apps/ios/BodyFlow/BodyFlowTests/PublicBrandContentTests.swift`
- Modify: `scripts/package.json`
- Modify: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md`

**Interfaces:**

- Source mode checks customer-visible literals, localization values, app
  catalog names, the explicit source-plist schema/build pipeline, plist public
  keys, and the exact exclusion of both the source plist from Copy Bundle
  Resources and historical wordmarks from targets.
- Bundle mode checks Debug and Release `Info.plist`, compiled `.strings`, and
  `.stringsdict`/`.loctable` localization resources, all resources under each
  `.lproj`, and `Assets.car` inventory. For every bundle invocation it parses
  the complete compiled plist and requires the two public names, preserved
  technical identity, and all five exact behavioral values from Task 2,
  including the nested launch-screen dictionary. It does not scan the
  executable as undifferentiated text because internal module/type symbols
  intentionally retain BodyFlow.
- Every allowlist entry contains exact path, exact field or anchored pattern,
  reason, and owner. Directory wildcards and “allow BodyFlow everywhere” rules
  are invalid.

**Step 1: Write failing contract tests**

Reject customer-facing matches for:

```text
BodyFlow / Body Flow
CoreHealth as consumer endorsement
MPP as consumer brand
Dr. Roberto as consumer endorsement
Balu or any obsolete agent name
Mascote BodyFlow / coach BodyFlow
BodyFlowWordmark / BodyFlowHorizontal / BodyFlowLaunch in Assets.car
```

Allow only exact internal/legal cases such as the preserved bundle identifier,
target/scheme/module fields, technical persisted keys, raw API value
`using_bodyflow`, the three AppIcon payload filenames required for byte
invariance, and explicitly enumerated historical files outside every app target.
Do not allow the whole `project.pbxproj` or whole `design/brand` directory.

The initial allowlist must enumerate at least these exact fields/paths rather
than generalize them:

```text
project.pbxproj :: PRODUCT_BUNDLE_IDENTIFIER = com.bodyflow.app(.tests|.uitests)
project.pbxproj :: target/product/scheme references named BodyFlow
project.pbxproj :: PRODUCT_NAME = $(TARGET_NAME) for the application
project.pbxproj :: INFOPLIST_FILE = BodyFlow/Resources/Info.plist for application Debug/Release
project.pbxproj :: synchronized membership exception = Resources/Info.plist for the BodyFlow target
source Info.plist :: CFBundleDisplayName and CFBundleName = Better Ahead
source Info.plist :: technical identity/version fields use the approved build-setting substitutions
compiled Info.plist :: CFBundleIdentifier = com.bodyflow.app
compiled Info.plist :: CFBundleExecutable = BodyFlow
compiled Info.plist :: exact Task 2 behavioral contract, including UILaunchScreen = { UILaunchScreen = {} }
PublishedContentModels.swift :: raw value using_bodyflow
DemoStateStore.swift :: persisted keys beginning bodyflow.demo.
AppLaunchConfiguration.swift :: Keychain service values beginning com.bodyflow.app.
AppIcon.appiconset/Contents.json :: the three exact bodyflow-app-icon-*-1024.png filename fields
AppIcon.appiconset/bodyflow-app-icon-default-1024.png :: invariant binary filename
AppIcon.appiconset/bodyflow-app-icon-dark-1024.png :: invariant binary filename
AppIcon.appiconset/bodyflow-app-icon-tinted-1024.png :: invariant binary filename
```

Historical wordmark paths are not public-source allowlist entries. The scanner
verifies separately that `design/brand` is outside synchronized app target roots
and that none of those exact files appears in Copy Bundle Resources or the
compiled bundle.

The source scanner also parses the two application build configurations and the
synchronized-root exception graph. It requires exactly:

```text
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = BodyFlow/Resources/Info.plist
no application INFOPLIST_KEY_CFBundleName/CFBundleDisplayName or migrated UI-generation keys
one PBXFileSystemSynchronizedBuildFileExceptionSet
membershipExceptions = Resources/Info.plist only
exception target = BodyFlow application target
exception attached to the BodyFlow synchronized root
no Info.plist PBXFileReference, PBXBuildFile, or explicit Resources-phase entry
BodyFlowTests and BodyFlowUITests keep GENERATE_INFOPLIST_FILE = YES and no INFOPLIST_FILE in Debug/Release
```

It parses `Resources/Info.plist` with `plutil`, requires the two public names,
the approved technical substitutions, and the exact behavior-preservation
values from Task 2: scene manifest with multiple scenes enabled and an empty
scene-configuration dictionary, indirect input enabled, the exact nested
`UILaunchScreen = { UILaunchScreen = {} }` value, and the ordered
`~iphone`/`~ipad` orientation arrays. The valid fixture hard-codes that nested
value; negative fixtures must flatten it to `{}` and separately add or alter an
inner key so semantic deep equality rejects both forms. The scanner must not
learn the expected value dynamically from the source plist. It rejects an
unqualified orientation key. It also requires the exact 15-key top-level source
schema enumerated by Task 2, so every unexpected generated/toolchain-owned key
is rejected, including `UIRequiredDeviceCapabilities`, all `CFBundleIcon*`
variants, `BuildMachineOSBuild`, `CFBundleSupportedPlatforms`,
`MinimumOSVersion`, `UIDeviceFamily`, `NSAccentColorName`, and every `DT*` key.
Fixtures must reject generation re-enabled, a wrong plist path, test-target
generation disabled or a test-target source-plist path, missing or
directory-wide membership exceptions, the exception attached to a test target,
duplicate resource membership, hard-coded technical identity, any unexpected
top-level source key, a missing behavior key, a wrong scalar/dictionary value,
and reordered or otherwise changed orientation arrays.

Bundle fixtures independently hard-code the approved processed values rather
than deriving them from `Resources/Info.plist`. They must reject a compiled
bundle whose launch value is flattened to `{}`, whose inner launch dictionary
is missing or nonempty, or whose other scene/input/orientation behavior differs.
Because `--check-bundle` is invoked once for Debug and once for Release in this
task and again in Task 10, a later build-time transformation cannot pass merely
because the source plist remains correct.

`PublicBrandContentTests` is a hosted runtime test for `Bundle.main`: it checks
semantic image lookup, both supported localized bundles, approved public plist
values, and runtime fallback. Filesystem source scanning, `plutil`, and
`assetutil` remain the Node contract's responsibility.

The xcresult contract invokes
`xcrun xcresulttool get test-results summary --path RESULT.xcresult`, parses the
documented JSON schema, and fails closed on a missing/unknown field, non-passed
result, zero executed tests, any failure, any skip, or any expected failure.
Fixture tests cover passed, failed, skipped, expected-failure, empty, and schema
drift cases. Its attachment mode reads the exported attachment manifest and
requires every stable screenshot name declared in Task 8 exactly once.

**Step 2: Run RED**

```bash
node --test scripts/brand/better-ahead-public-content-contract.test.mjs
node --test scripts/ios/better-ahead-xcresult-contract.test.mjs
```

Expected: FAIL until the scanner and exact allowlist exist.

**Step 3: Implement source and local-notification audits**

The source audit distinguishes string literals from type names. Also prove:

```bash
set -euo pipefail
NOTIFICATION_MATCHES=$(rg -n \
  'import UserNotifications|UNUserNotificationCenter|UNNotificationRequest|UNMutableNotificationContent' \
  apps/ios/BodyFlow/BodyFlow || test "$?" -eq 1)
test -z "$NOTIFICATION_MATCHES"
```

Expected: no local scheduler; evidence records “not applicable”. Do not confuse
`UIAccessibility.post(notification:)` or Foundation `NotificationCenter` with
user notifications.

**Step 4: Build and audit compiled public resources**

The bundle reader discovers exactly `pt-BR.lproj` and `en.lproj`. It converts
the bundle's root `Info.plist` to JSON and verifies the exact public, technical,
and behavioral contract before inspecting localized resources. It converts
every `Localizable.strings`, `Localizable.stringsdict`, `InfoPlist.strings`, and
`.loctable` it finds with `plutil -convert json -o -`, walks all scalar values,
and fails if a compiled localization resource cannot be parsed. It also audits
all other files beneath those `.lproj` directories using their declared
structured format or verified UTF-8 text. Binary-plist, plural, and loctable
fixtures are required in the Node tests.

For `Assets.car`, save `assetutil --info` JSON and parse exact `Name` fields.
Require all six semantic names and reject all six former product-specific
names; a positive `rg` match is not proof. AppIcon source bytes and
`Contents.json` remain governed by `brand:better-ahead:catalog`; bundle mode
follows `CFBundleIcons`/actool output to prove the referenced compiled icon
artifacts exist without assuming they are named entries in `Assets.car`.

```bash
set -euo pipefail
DERIVED_DATA=$(mktemp -d /tmp/better-ahead-bundle-audit.XXXXXX)
AUDIT_ROOT=$(mktemp -d /tmp/better-ahead-bundle-report.XXXXXX)
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" build
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=iOS Simulator" build
node scripts/brand/better-ahead-public-content-contract.mjs --check-source
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:catalog
node scripts/brand/better-ahead-public-content-contract.mjs --check-bundle \
  "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/BodyFlow.app"
node scripts/brand/better-ahead-public-content-contract.mjs --check-bundle \
  "$DERIVED_DATA/Build/Products/Release-iphonesimulator/BodyFlow.app"
xcrun assetutil --info \
  "$DERIVED_DATA/Build/Products/Release-iphonesimulator/BodyFlow.app/Assets.car" \
  > "$AUDIT_ROOT/release-assets.json"
node scripts/brand/better-ahead-public-content-contract.mjs --check-assetutil \
  "$AUDIT_ROOT/release-assets.json"
git diff --exit-code -- \
  apps/ios/BodyFlow/BodyFlow/Resources/Info.plist \
  apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings
```

Expected: both public plist names are Better Ahead; the compiled technical and
five behavioral values, including the nested launch dictionary, are exact in
both Debug and Release; both locales are present; neutral assets are present;
former wordmark/lockup/launch assets are absent.

**Step 5: Run GREEN and commit**

```bash
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:public-content:test
corepack pnpm@10.33.2 --filter @mpp/scripts ios:xcresult:test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/PublicBrandContentTests test
git diff --check
git add config/brand/better-ahead-ios-public-content-allowlist.json \
  scripts/brand/better-ahead-public-content-contract.mjs \
  scripts/brand/better-ahead-public-content-contract.test.mjs \
  scripts/ios/better-ahead-xcresult-contract.mjs \
  scripts/ios/better-ahead-xcresult-contract.test.mjs \
  scripts/package.json \
  apps/ios/BodyFlow/BodyFlowTests/PublicBrandContentTests.swift \
  docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preflight.md
git commit -m "test(brand): gate Better Ahead public content"
```

Add this script entry:

```json
{
  "brand:better-ahead:public-content:test": "node --test brand/better-ahead-public-content-contract.test.mjs",
  "ios:xcresult:test": "node --test ios/better-ahead-xcresult-contract.test.mjs"
}
```

---

### Task 10: Run The Complete Native, Visual, And Preservation Gate

**Files:**

- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/README.md`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt`
- Create: `docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/render-reproducibility.txt`
- Create approved screenshots beneath the same evidence directory
- No application code or asset mutation is expected in this task

**Step 1: Run all machine gates from a clean candidate commit**

```bash
set -euo pipefail
FINAL_ROOT=$(mktemp -d /tmp/better-ahead-final.XXXXXX)
DERIVED_DATA="$FINAL_ROOT/DerivedData"
SIMULATOR_UDID=27291590-659D-4A29-8F45-CA5CA2D154F9
mkdir -p "$DERIVED_DATA" "$FINAL_ROOT/logs" "$FINAL_ROOT/results"
xcrun simctl list devices available | rg -F "$SIMULATOR_UDID"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
git diff --exit-code
git diff --cached --exit-code
test -z "$(git status --porcelain=v1 -uall)"
RUNTIME_POINTER=docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt
test ! -e "$RUNTIME_POINTER"
printf '%s\n' "$FINAL_ROOT" > "$RUNTIME_POINTER"
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:baseline
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:catalog
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:validate
REPRO_EVIDENCE=docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/render-reproducibility.txt
ENVIRONMENT_STATUS=0
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:environment \
  > "$FINAL_ROOT/logs/render-environment.log" 2>&1 || ENVIRONMENT_STATUS=$?
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:render:check \
  2>&1 | tee "$FINAL_ROOT/logs/render-check.log"
case "$ENVIRONMENT_STATUS" in
  0)
    printf '%s\n' 'environment-recreated: fingerprint exact; canonical bundle verified without rerender' \
      > "$REPRO_EVIDENCE"
    ;;
  78)
    printf '%s\n' 'canonical-only: bundle verified without rerender; fingerprint not recreated; no reproducibility claim' \
      > "$REPRO_EVIDENCE"
    ;;
  *)
    false
    ;;
esac
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:public-content:test
corepack pnpm@10.33.2 --filter @mpp/scripts ios:xcresult:test
corepack pnpm@10.33.2 --filter @mpp/scripts ios:localization:test:all
corepack pnpm@10.33.2 --filter @mpp/scripts brand:test
corepack pnpm@10.33.2 --filter @mpp/scripts brand:validate
```

Do not run legacy `brand:render`, `brand:render:check`, or `brand:review` against
the rebranded catalog. Task 5 has already converted the applicable legacy tests
to archive-only assertions, retained every historical expected hash, and proven
the guarded legacy writer refuses the active catalog. Task 10 performs no
conditional test repair.

**Step 2: Run focused and complete native tests**

```bash
set -euo pipefail
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
DERIVED_DATA="$FINAL_ROOT/DerivedData"
SIMULATOR_UDID=27291590-659D-4A29-8F45-CA5CA2D154F9
test -d "$DERIVED_DATA"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$FINAL_ROOT/results/focused-native.xcresult" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:BodyFlowTests/BrandIdentityTests \
  -only-testing:BodyFlowTests/BrandAssetTests \
  -only-testing:BodyFlowTests/LocalizationContractTests \
  -only-testing:BodyFlowTests/PublicBrandContentTests \
  -only-testing:BodyFlowTests/ScreenStateTests test \
  2>&1 | tee "$FINAL_ROOT/logs/focused-native.log"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$FINAL_ROOT/results/all-native.xcresult" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:BodyFlowTests test \
  2>&1 | tee "$FINAL_ROOT/logs/all-native.log"
node scripts/ios/better-ahead-xcresult-contract.mjs --check \
  "$FINAL_ROOT/results/focused-native.xcresult"
node scripts/ios/better-ahead-xcresult-contract.mjs --check \
  "$FINAL_ROOT/results/all-native.xcresult"
```

Expected: zero failures and zero unapproved skips/expected failures.

**Step 3: Run bilingual UI smoke and accessibility tests**

Run the new Better Ahead smoke suite in `pt-BR` and English plus existing auth,
onboarding, Today, Flow, and accessibility suites. Capture:

```text
PT-BR: splash, sign-in, onboarding welcome, Flow style, Today, Flow, profile, About
English: the same eight surfaces
Light and Dark: splash, Today, Flow, About
Dynamic Type accessibility size: onboarding, Today, About
Reduce Motion: Flow surface
```

Verify no clipping of Better Ahead, no untranslated iOS-owned control, stable
focus order, minimum 44-point controls, and correct accessibility pronunciation
of Better Ahead and Flow.

Every captured test screenshot is an `XCTAttachment` with a stable descriptive
name and `lifetime = .keepAlways`. Run every existing UI class explicitly so
the bilingual suite does not replace the established regression coverage:

```bash
set -euo pipefail
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
DERIVED_DATA="$FINAL_ROOT/DerivedData"
SIMULATOR_UDID=27291590-659D-4A29-8F45-CA5CA2D154F9
test -d "$DERIVED_DATA"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$FINAL_ROOT/results/all-ui.xcresult" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:BodyFlowUITests/BodyFlowUITests \
  -only-testing:BodyFlowUITests/BetterAheadLocalizationUITests \
  -only-testing:BodyFlowUITests/Prompt13AccessibilityUITests \
  -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests \
  -only-testing:BodyFlowUITests/Prompt13RegistrationUITests \
  -only-testing:BodyFlowUITests/Prompt13RoutineUITests \
  -only-testing:BodyFlowUITests/Prompt13TodayUITests \
  -only-testing:BodyFlowUITests/Prompt14AccessibilityUITests \
  -only-testing:BodyFlowUITests/Prompt14LibraryUITests \
  -only-testing:BodyFlowUITests/Prompt14ProgressUITests \
  -only-testing:BodyFlowUITests/Prompt14TodayMascotUITests test \
  2>&1 | tee "$FINAL_ROOT/logs/all-ui.log"
node scripts/ios/better-ahead-xcresult-contract.mjs --check \
  "$FINAL_ROOT/results/all-ui.xcresult"
xcrun xcresulttool help export attachments > "$FINAL_ROOT/logs/xcresulttool-help.txt"
SCREENSHOT_DIR=docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/screenshots
test ! -e "$SCREENSHOT_DIR"
xcrun xcresulttool export attachments \
  --path "$FINAL_ROOT/results/all-ui.xcresult" \
  --output-path "$SCREENSHOT_DIR"
node scripts/ios/better-ahead-xcresult-contract.mjs --check-attachments \
  "$SCREENSHOT_DIR" \
  --config config/brand/better-ahead-ios-public-surfaces.json
```

Expected: all bilingual smoke/accessibility tests pass with zero unapproved
skips. The new suite owns one `pt-BR` and one English launch for every surface
listed above. Review the exported attachment manifest and images; the visual
checkpoint is blocking for clipping, contrast, identity, and wrong-language
copy. Retain every exported file mechanically without re-encoding.

**Step 4: Build Debug and Release with isolated DerivedData**

```bash
set -euo pipefail
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
DERIVED_DATA="$FINAL_ROOT/DerivedData"
SIMULATOR_UDID=27291590-659D-4A29-8F45-CA5CA2D154F9
test -d "$DERIVED_DATA"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build \
  2>&1 | tee "$FINAL_ROOT/logs/debug-build.log"
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=iOS Simulator" build \
  2>&1 | tee "$FINAL_ROOT/logs/release-build.log"
```

Expected: both `BUILD SUCCEEDED`, zero `actool`/Asset Catalog warning, and no
new warning introduced by the rebrand. Report inherited warnings exactly. The
last accepted baseline contained AppIntents warnings, MainActor warnings in
hydration/workout registration, and an unused `waitUntilStarted` result in a
test; do not claim “only AppIntents” if the others remain.

**Step 5: Repeat compiled-resource and invariant checks**

```bash
set -euo pipefail
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
DERIVED_DATA="$FINAL_ROOT/DerivedData"
test -d "$DERIVED_DATA"
for CONFIGURATION in Debug Release; do
  APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/BodyFlow.app"
  test -d "$APP_BUNDLE"
  node scripts/brand/better-ahead-public-content-contract.mjs \
    --check-bundle "$APP_BUNDLE"
  xcrun assetutil --info "$APP_BUNDLE/Assets.car" \
    > "$FINAL_ROOT/${CONFIGURATION}-assets.json"
  node scripts/brand/better-ahead-public-content-contract.mjs \
    --check-assetutil "$FINAL_ROOT/${CONFIGURATION}-assets.json"
done
node scripts/brand/better-ahead-public-content-contract.mjs --check-source
corepack pnpm@10.33.2 --filter @mpp/scripts brand:better-ahead:catalog
node scripts/brand/better-ahead-preserved-assets.mjs --emit-historical-map \
  > "$FINAL_ROOT/preserved-assets.after.json"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/preserved-assets.before.json \
  "$FINAL_ROOT/preserved-assets.after.json"
corepack pnpm@10.33.2 --filter @mpp/scripts ios:localization:test:all
git diff --exit-code -- \
  apps/ios/BodyFlow/BodyFlow/Resources/Info.plist \
  apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings \
  apps/ios/BodyFlow/BodyFlow/Resources/InfoPlist.xcstrings
git diff --cached --exit-code
```

Expected: Debug and Release pass the full structured resource scan; all
semantic catalog/AppIcon source bytes pass; the complete historical map is
byte-identical to Task 1 evidence. Pixel comparison may be supplementary but
does not replace byte equality.

**Step 6: Prove both source worktrees were preserved**

```bash
set -euo pipefail
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
test -d "$FINAL_ROOT"
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
test "$(cd -- "$GIT_REPO" && pwd -P)" != "$(cd -- "$DIAGNOSTIC_REPO" && pwd -P)"
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-head.before.txt)"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  | tee "$FINAL_ROOT/diagnostic-status.after.txt"
shasum -a 256 "$FINAL_ROOT/diagnostic-status.after.txt" \
  | awk '{print $1}' | tee "$FINAL_ROOT/diagnostic-status.after.sha256"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.txt \
  "$FINAL_ROOT/diagnostic-status.after.txt"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-status.before.sha256 \
  "$FINAL_ROOT/diagnostic-status.after.sha256"
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository "$DIAGNOSTIC_REPO" \
  > "$FINAL_ROOT/diagnostic-worktree.after.json"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/diagnostic-worktree.before.json \
  "$FINAL_ROOT/diagnostic-worktree.after.json"
git -C "$DIAGNOSTIC_REPO" diff --cached --quiet

test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-head.before.txt)"
git -C "$GIT_REPO" status --porcelain=v1 -uall \
  | tee "$FINAL_ROOT/git-repo-status.after.txt"
shasum -a 256 "$FINAL_ROOT/git-repo-status.after.txt" \
  | awk '{print $1}' | tee "$FINAL_ROOT/git-repo-status.after.sha256"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.txt \
  "$FINAL_ROOT/git-repo-status.after.txt"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-status.before.sha256 \
  "$FINAL_ROOT/git-repo-status.after.sha256"
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository "$GIT_REPO" \
  > "$FINAL_ROOT/git-repo-worktree.after.json"
cmp docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/git-repo-worktree.before.json \
  "$FINAL_ROOT/git-repo-worktree.after.json"
git -C "$GIT_REPO" diff --cached --quiet
```

Expected: diagnostic HEAD, its nine path/status/type/size/SHA-256 records, and
empty staging all match. The Git-manager HEAD, empty porcelain/physical map,
and empty staging also match. Remote refs and shared worktree metadata may have
changed because of fetch/worktree creation; neither is worktree content.

**Step 7: Record final evidence and commit**

The README records base/final SHAs, exact tool versions, commands/results,
preserved and new asset hashes, human approval, localization coverage, the
Xcode 26.6 generated-plist conflict and explicit-plist resolution, the observed
nested `UILaunchScreen` baseline and its exact preservation in the source plist,
public content allowlist, both bundle audits, warnings, UI screenshots,
preservation of both source worktrees, and these remaining gates:

```text
Workstream 2 backend public language: still required
private beta distribution: still requires explicit authorization and channel gate
App Store production submission: not authorized
```

Then:

```bash
set -euo pipefail
git diff --check
git status --porcelain=v1 -uall
FINAL_ROOT=$(tr -d '\n' < docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand/task10-runtime-root.txt)
node scripts/brand/better-ahead-worktree-state.mjs \
  --repository . \
  --require-only-prefix docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand \
  > "$FINAL_ROOT/implementation-evidence-only.json"
git add docs/superpowers/evidence/2026-08-11-better-ahead-ios-rebrand
git commit -m "docs(ios): verify Better Ahead client rebrand"
git diff --exit-code
git diff --cached --exit-code
git status --short --branch
```

Expected: isolated implementation worktree clean after the evidence commit.
Do not push, create a PR, merge, upload, sign, deploy, purchase a domain, or
file a trademark without separate authorization.

## Acceptance Traceability

| Approved requirement | Implemented by |
| --- | --- |
| Distinct clean Git manager, exact implementation base, and preserved diagnostic worktree | Tasks 0, 1, 10 |
| Historical manifest remains authority for preserved bytes | Tasks 1, 4, 5, 10 |
| Symbol and App Icons byte-identical | Tasks 1, 4, 5, 10 |
| Better Ahead wordmark/lockup generated and published as one immutable atomic bundle | Tasks 3, 4 |
| Canonical environment fingerprint committed before render | Task 3 |
| Human visual approval of new assets | Task 4 |
| Neutral semantic asset interfaces and safe fallback | Task 5 |
| Better Ahead sole public product name | Tasks 2, 5, 6, 9 |
| Flow sole public guide/agent name | Tasks 2, 6, 9 |
| PT-BR and English iOS-owned UI | Tasks 2, 7, 8, 10 |
| Public bundle names decoupled from preserved technical identity with plist parity | Tasks 2, 9, 10 |
| About hierarchy | Task 6 |
| Local notification copy | Task 9 audit: not applicable at current base |
| Stable internal IDs/contracts remain unchanged | All tasks; enforced by review/tests |
| Debug/Release/native/accessibility gates | Tasks 9, 10 |
| No external distribution or backend mutation | Tasks 0 and 10 boundaries |

## Plan Self-Review

- **Spec coverage:** all Workstream 1 requirements have an implementation task
  and an acceptance gate. Backend copy and distribution remain separate.
- **Placeholder scan:** execution-time facts are captured by scripts and logs;
  no fake checksum, URL, legal entity, credential, or release status is supplied.
- **Type consistency:** `BrandIdentity`, `BrandCopy`, `SupportedAppLanguage`,
  `BrandAsset`, and `BrandLogoPresentation` have one documented owner and are
  consumed by tests and production views.
- **Asset safety:** legacy write commands are prohibited; the new runner has a
  journal-first path boundary and one exclusive whole-bundle commit point;
  recovery is FD-anchored/no-follow, and preserved bytes are verified before
  and after.
- **Localization completeness:** the approved-base inventory found at least 74
  public-string files, while the enforced criterion is stronger: zero
  unclassified client-owned public producer, not a fixed file count.
- **Compatibility:** target/scheme/module/bundle ID, APIs, storage, telemetry,
  and server wire values remain stable unless an actual public leak is proven.
- **Release truthfulness:** completing this plan finishes only the iOS client
  rebrand. Integrated client testing still requires Workstream 2 and, depending
  on distribution method, the private-beta subgate of Workstream 3.
