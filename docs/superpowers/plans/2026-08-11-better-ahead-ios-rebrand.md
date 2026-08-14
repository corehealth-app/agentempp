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
- The one canonical image build uses literal
  `docker --context desktop-linux buildx build --builder default --platform=linux/amd64 --quiet --file Dockerfile .`
  with cwd set to the exact journal-bound canonical-renderer directory in the
  immutable transaction snapshot. Buildx receives no output pathname. The
  existing embedded native helper owns the complete anchored
  open/journal/spawn/drain/wait/fsync/validate cycle, maps two anonymous pipe
  write ends to child descriptors `1` and `2`, drains their read ends into its
  preopened IID stdout capture and Buildx stderr diagnostic log, and accepts only
  the single canonical IID line printed on successful quiet output.
  `--iidfile`, `--metadata-file`, any other pathname/stdout exporter,
  `/dev/fd` or `/proc/self/fd` pathname handoff, and shell pathname redirection
  are prohibited. This preserves exactly one build and one visual container.
- Task 3's native-helper V3 fault oracle is a test-only programmatic seam in
  the existing renderer module. `runNativeHelperV3` remains module-private;
  production renderer/recovery/cleanup, journal, payload, CLI, package-script,
  and environment interfaces gain no test control. The single named test-only
  module export defined below is the explicit exception; it cannot dispatch a
  production operation or accept a live path. The seam accepts only the frozen
  closed-case inventory and fixed closed negative-probe matrix defined by the
  latest current-execution reconciliation below, owns an isolated temporary
  fixture, and synchronizes through
  capability-bound anonymous pipes. It accepts no caller path, bytes,
  descriptor, command, callback, offset, timeout, environment, or arbitrary
  operation. No marker file, sleep, filesystem polling, Docker invocation, or
  new tracked helper is authorized.

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
- The sole test-only programmatic expansion is the named export
  `nativeHelperV3TestOracle` from the existing
  `render-better-ahead-brand-assets.mjs` module. It exposes only
  `open(CLOSED_CASE_ID)`, `probe(CLOSED_NEGATIVE_PROBE_ID)`, and the frozen
  one-shot protocols defined by the current-execution oracle reconciliation
  below. It is not dispatched by the module's `main`, shell runner,
  `scripts/package.json`, argv, environment, or serialized transaction data. It
  can operate only on a private fixture that it creates itself and can never
  receive or mutate the live repository.
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
- a per-run Docker image ID captured from the stdout of the exact literal
  `docker --context desktop-linux buildx build --builder default --platform=linux/amd64 --quiet --file Dockerfile .`
  argv, with cwd set to the exact journal-bound
  `<TRANSACTION_PATH>/snapshot/scripts/brand/canonical-renderer` directory.
  That anchored snapshot directory is the context; neither `.` nor `Dockerfile`
  is resolved from the live repository. The existing
  embedded native helper, not the shell, opens the journal-declared IID stdout
  capture and Buildx stderr diagnostic log with anchored no-follow descriptors,
  durably binds their physical identities to the journal, directly spawns the
  approved Docker executable without an intermediate shell, maps anonymous pipe
  write ends to child stdout/stderr, concurrently drains their read ends into
  the retained evidence descriptors, waits for EOF and child termination,
  flushes, revalidates, and parses the capture without reopening either
  pathname. The canonical Dockerfile's
  dependency installation retains build-time network access. The exact ID
  built for a run must be passed as one already validated argv element to
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
  IID stdout capture, Buildx stderr diagnostic log, Docker command, render log,
  candidate, bundle staging, or other preparation write. Its initial schema
  declares the exact capture/log paths as absent; the native pre-build
  transition records their anchored device/inode identities and permitted build
  mutation phase, and fsyncs the authoritative journal before spawning Buildx.
  Failures and signals at every begin, snapshot, capture preparation, build,
  container, resume, sealing, bundle publication, verification, cleanup, and
  unlock boundary retain the journal and all available evidence;
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
  removes the exact lock as its final destructive pathname mutation and unlock
  linearization point. Only fsync of the already-open lock parent and return may
  follow as production filesystem operations; neither step may reopen or mutate
  a pathname. A recognized test-only lock-POST oracle may exchange only its
  anonymous `REACHED/RELEASE/CONSUMED` control frames around that fsync. A second
  write remains blocked after any injected error until the applicable audited
  `--recover-orphan EXACT_BEGIN_TEMP_PATH` (before lock publication) or
  `--recover EXACT_TRANSACTION_PATH` (after publication) completes
  successfully;
- the bounded digest and environment contract reject a changed root
  `packageManager`, `pnpm-workspace.yaml` build policy, exact Corepack command,
  or Node/Corepack/pnpm version without modifying any of those read-only inputs;
- fake Docker fixtures prove `--assert-local-docker` is non-writing and
  fail-closed: non-bundled client or Buildx/Desktop/Offload plugin
  realpath/hash, non-bundled user/system plugin shadow, non-empty
  `cliPluginsExtraDirs`, any non-empty Docker CLI `proxies` configuration,
  Docker Desktop application older than
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
  and every build/run uses literal `--platform=linux/amd64`. The one build uses
  exactly one `--quiet`, exact `--file Dockerfile .`, and zero `--iidfile`,
  `--metadata-file`, `--call`, `--progress`, stdin context/Dockerfile,
  stdout-writing exporter, shell pathname
  redirection, `/dev/fd`, or `/proc/self/fd` pathname. Only run uses literal
  `--network none` and consumes, without rereading a pathname or using `eval`,
  the exact normalized IID returned by the native helper. No context-less
  Docker daemon API probe is permitted during attestation or rendering;
- native-helper fixtures prove the helper owns one uninterrupted
  `open -> journal bind -> spawn -> drain/wait/EOF -> fsync -> fstat -> parse -> journal result`
  operation. It traverses anchored parents component by component, creates two
  distinct absent-only `0600` regular leaves with
  `O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC`, and requires the expected owner
  and device, `st_nlink == 1`, size zero, and unchanged parent identity before
  Buildx. The fixed transaction-relative leaves are
  `evidence/buildx-image-id.stdout` and `evidence/buildx-stderr.log`; neither
  name is caller-controlled. It directly executes the approved absolute Docker
  realpath with an exact five-variable environment: `HOME` is the physically
  attested current-user home used by the checked Docker context;
  `PATH=/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
  `TMPDIR=/private/tmp`, after proving it is the physical root-owned sticky
  temporary directory; and `LANG=C` plus `LC_ALL=C`. The fingerprint and journal
  bind all five exact values. No ambient `DOCKER_*`, `BUILDKIT_*`,
  `BUILDX_*`, BuildKit source-policy, proxy, credential/config, or other
  variable is inherited. The helper uses `fchdir` on the already validated
  snapshot-context dirfd, revalidates its identity, opens `/dev/null` for child
  stdin, maps only two anonymous pipe write ends to child descriptors `1`/`2`,
  and closes every other descriptor before `exec`; no output pathname is passed
  to Docker or Buildx;
- after the child is reaped, the same helper fsyncs and fstats both retained
  descriptors, revalidates both leaves and their parent with anchored no-follow
  lookups against the recorded identities, and reads the IID only with `pread`
  from the retained descriptor. While draining each anonymous pipe, it computes
  the authoritative byte count and SHA-256 in memory; after EOF, bytes read back
  from each evidence FD must match that exact count/hash. Any mismatch or
  post-EOF mutation is physical divergence and `BLOCKED`. An unchanged capture
  whose exact pipe stream is merely invalid is `RECOVERY_REQUIRED`. Build
  success accepts exactly 72 bytes matching
  `^sha256:[0-9a-f]{64}\n$`; empty, partial, oversized, missing/extra newline,
  CRLF, whitespace, uppercase/nonhex, NUL, multiple IDs, an inline message, a
  nonzero exit, or a signal is invalid and must not reach `image inspect` or
  `run`. Stderr may be empty or may grow only on its recorded regular-file inode
  during the declared build phase; its final size and SHA-256 are journaled. The
  helper concurrently drains helper-owned pipes into the two evidence FDs, with
  hard caps of 4 KiB for stdout and 16 MiB for stderr. Overflow terminates the
  process group, preserves only the bounded prefix, journals the overflow/count,
  and is invalid. The helper launches one dedicated process group, reaps its
  direct child, forwards `HUP`/`INT`/`TERM` to the whole group, and requires pipe
  EOF before any successful seal. After direct-child exit without EOF, or after
  any error/overflow/signal, it sends `TERM`, waits at most five seconds, sends
  `KILL`, and allows at most five more seconds for EOF. If a writer survives,
  the helper closes the anonymous pipes, records `BLOCKED`, and never seals a
  successful result; that writer never held an evidence FD. Any drain/write
  error, missing EOF on success, or signal-escalation failure is likewise
  `BLOCKED`;
- OA-16 and OA-34 native-helper fixtures use only the closed programmatic test
  oracle specified below. OA-16 proves that a canonical FD3 V3 payload truncated
  by exactly its final byte and followed by real EOF is rejected without a
  partial parse, retry, state transition, cleanup, unlock, Docker call, or
  filesystem mutation. OA-34 deterministically exercises the six fixed
  cleanup/unlock boundaries around mirror unlink, transaction rmdir, and lock
  unlink. No fixture may reach those cases through CLI flags, environment
  variables, serialized fields, marker paths, sleeps, or polling;
- fake runner tests also prove the exact persisted order
  `BEGIN -> BUILDX -> RUN -> RESUME -> FINISH`, exactly one build and one
  container for a successful write, and zero Docker calls from `resume`, `finish`,
  `--recover`, or any cleanup path. The explicit failure paths are
  `BEGIN -> BUILDX -> RESUME_FAILURE` for a failed build/invalid IID and
  `BEGIN -> BUILDX -> RUN -> RESUME_FAILURE` for a failed container, with zero
  `FINISH`, zero retry, and no reliance on `set -e` or a trap for the durable
  classification. Build/container failures and `HUP`, `INT`, or `TERM` after
  `begin` preserve the journal, request, IID stdout capture, Buildx stderr log,
  render logs, candidates, and transaction path; no trap removes or unlocks them;
- deterministic capture tests attack each IID/log leaf independently before
  open, after each open, before spawn, while the child writes, after child exit,
  before post-build identity validation, and before helper return. They cover a
  pre-existing regular file, final/intermediate symlink, directory/FIFO/socket,
  hardlink, unlink/rename/replacement, changed transaction parent, unauthorized
  append/truncate/overwrite outside the authorized drain, fsync/read error, and
  an external sentinel. Every path/identity or stream-vs-evidence divergence is
  `BLOCKED`, preserves available evidence, leaves the
  sentinel byte-identical, and invokes no container; legitimate same-inode
  helper writes during drain, stderr growth, and empty stderr are successful
  controls. A physically intact failed build or invalid IID whose capture bytes
  exactly equal the child pipe stream durably selects `RECOVERY_REQUIRED` without
  requiring a render completion or receipt. Signals are injected before capture
  creation, between capture creation and its journal bind, during Buildx, after
  wait/pipe EOF, and after the post-build journal transition; no case performs a
  second build or container. A signal/orphan fixture leaves a Buildx descendant
  holding stdout/stderr after the Docker parent exits and proves the helper
  cannot seal successfully until both pipes reach EOF; escalation failure closes
  the pipes, persists `BLOCKED`, and leaves the bounded evidence immutable.
  Tests do not overclaim protection from an already
  compromised same-UID process inside the existing private helper-owned threat
  exclusion;
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
The image ID from the helper-owned `--quiet` stdout capture is per-run execution
evidence: tests prove the same freshly built, strictly parsed ID is journaled and
used by
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
probe, IID stdout capture, Buildx stderr diagnostic log, render log, request,
candidate, or bundle staging path. The
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
claim path, completion path, exact fixed IID stdout-capture and Buildx
stderr-log paths in their initially absent state, and initially absent final
destination. It then
copies the complete bounded input set into an immutable transaction snapshot and
proves that snapshot against the exact Task 3 input commit. Docker context,
comparison input, and render inputs come only from that snapshot.

The shell runner invokes `begin` before its sole Buildx build and performs no
output-path redirection. All subsequent execution evidence stays under the
recorded transaction, and the runner repeats the fail-closed local-route
attestation inside that journaled phase immediately before Buildx. One operation
in the existing embedded native helper then owns the complete capture lifecycle:
it opens the two absent evidence leaves through the anchored transaction parent;
atomically journals and fsyncs their physical identities before spawn; enters
the anchored snapshot-context cwd; launches the exact approved Docker argv in a
dedicated process group with anonymous pipes as stdout/stderr; concurrently
drains those pipes into the retained evidence descriptors; reaps the direct
child and enforces EOF/termination; fsyncs, revalidates, and seals both leaves;
parses the IID from the retained descriptor; and atomically records the child
status plus capture/log identity, size, hash, and overflow state before
returning. No repository, journal, or directory descriptor is inherited by
Buildx. Only an exit-zero child, closed writers, and the exact canonical IID line
permit `image inspect` and one container with that validated IID. The
standalone environment command in Task 4 is an earlier read-only preflight; it
does not replace this post-`begin` attestation. A single dispatcher inside that
container atomically claims the journal-bound request and imports both asset and
review workers, producing all six candidates. The request binds the run ID, nonce,
snapshot digest, exact input roots, and exact candidate allowlist. The workers
reject standalone invocation, request replay, a second claim/writer, live-tree
input, or output outside that allowlist. The snapshot is mounted read-only; only
recorded transaction candidate/log paths are writable; the live repository is
not mounted writable.

After the external command completes, the runner deliberately invokes the
appropriate resume transition even for a captured nonzero status; `set -e` and
the signal trap are not the normal classifier. Build failure or invalid IID with
intact physical evidence selects `RECOVERY_REQUIRED` from the journaled
capture/log result without requiring a request claim, completion record, render
receipt, or populated IID. Physical ambiguity selects `BLOCKED`. After a
container attempt, `resume` validates the request, claim, completion record,
nonce, exit status, and exact six candidate paths using the authoritative
journal. Container failure or incomplete record durably selects
`RECOVERY_REQUIRED` when safe to record and preserves all evidence. Success
advances only to `RENDERED`; `resume` never invokes Docker, publishes an output,
mutates the manifest, cleans, or unlocks. On an abrupt signal, the runner's trap
may only best-effort request the same durable failure transition, record the
signal/exit status, and print the transaction path. It must not remove any path
or lock.

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
`unlinkat`, which is its final pathname mutation and linearization point. It
then fsyncs only the already-open lock parent and returns without another
pathname lookup, journal write, unlink, or filesystem mutation. A recognized
test-only lock-POST oracle may only emit `REACHED`, await exact `RELEASE` plus
FD4 EOF, and emit `CONSUMED` around that fsync; those anonymous control frames
never enter production state. A new lock created after the old unlink is a
legitimate next owner and must survive.

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
      enforce the exact successful
      `BEGIN -> BUILDX -> RUN -> RESUME -> FINISH` order, the explicit
      `RESUME_FAILURE` paths defined above, and one visual container; make
      failure/signal traps preserve all evidence;
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
      every non-bundled shadow, any non-empty Docker CLI `proxies` configuration,
      and all ambient `DOCKER_*`, `BUILDKIT_*`, and `BUILDX_*` variables plus the
      BuildKit source-policy override; pin the exact
      `desktop-linux` Unix-socket endpoint and local engine identity, make every
      attestation/renderer/build/run daemon command use literal
      `docker --context desktop-linux` without exception; require the
      context-bound `default` Buildx builder with `docker` driver and literal
      `buildx build --builder default`; make every build/run pass literal
      `--platform=linux/amd64`; and require the exact build tail
      `--quiet --file Dockerfile .` from the anchored snapshot-context cwd. The
      existing embedded native helper owns open, durable pre-spawn journal
      binding, direct process-group spawn without a shell, anonymous-pipe drain
      into distinct anchored stdout/stderr evidence FDs, wait/EOF, flush,
      identity revalidation, strict parse, and durable post-build journal result
      as one operation.
      Forbid `--iidfile`, `--metadata-file`, every pathname/stdout exporter,
      `/dev/fd`/`/proc/self/fd`, and shell pathname redirection.
      This authorizes the required schema, test, capture, and validation
      changes; it does not authorize changing dependency declarations, the
      lockfile, workspace policy, Docker context, Offload state, or any
      canonical/historical input.

   The write allowlist for this hardening commit remains exactly the Better Ahead
   manifest, `better-ahead-brand-contract.mjs` and its test,
   `capture-better-ahead-environment.mjs`, both Better Ahead render scripts,
   `run-better-ahead-brand-renderer.sh`, and `scripts/package.json` limited to
   existing `brand:better-ahead:*` commands: eight authorized paths in total.
   The current seven-file dirty set is a preservation fact, not a narrower or
   contradictory implementation allowlist. Root `package.json`,
   `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `canonical-renderer/**`, committed
   masters, and the historical comparison SVG remain read-only, unchanged, and
   unstaged. `environment.json`, `bundles/**`, flat exports/review paths, review
   PNGs, locks, journals, transactions, iOS files, and every other path remain
   prohibited in this commit. No new helper file is authorized: extend the
   native helper embedded in the existing renderer script.

   The OA-16/OA-34 oracle is a test-only verification adjunct to workstreams
   **b** and **c**, not a seventh production workstream and not an allowlist
   expansion. Its implementation is confined to the already authorized
   renderer module and contract test. It must not require a new tracked file or
   any change to `scripts/package.json` unless that path was already required by
   the production workstreams above.

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

**Current-execution reconciliation after the Buildx IID gate**

The implementation worktree has already imported the Option A document as
`60ecb54175fd1172ffe2105a8059702f8b3d8ea0`, whose parent is exactly
`9d204ab10801cd2cb07ec8d5ee6a759b12dd296b`. It still contains exactly the same
seven unstaged Task 3 implementation files and empty staging. Its frozen binary
diff SHA-256 is
`3a9aab2ae42ff2921265a0366765a52ad6c4d01118cbe83953fb71775d20c22a`, and the
current contract-test file SHA-256 is
`bd5c7dbbab702cfce4f40e087cf8321ce01b6135be383cf2ed5d2da6a25020fd`. No
`environment.json`, bundle, export, review PNG, lock, journal, transaction,
Docker build, capture, or render exists. Preserve that state exactly.

Buildx v0.32.1 makes the former literal `--iidfile` contract impossible to
satisfy: its
[tagged implementation](https://github.com/docker/buildx/blob/v0.32.1/commands/build.go#L321-L424)
removes the supplied pathname before the build and later recreates it with
`os.WriteFile`, invalidating a preopened inode and leaving a
pathname-substitution window. The same implementation emits the successful
image ID with `fmt.Println` in quiet mode, and the
[Docker reference](https://docs.docker.com/reference/cli/docker/buildx/build/)
documents `--quiet` as suppressing build output and printing the image ID on
success. This reconciliation therefore supersedes only the `--iidfile`
mechanism with the helper-owned `--quiet` FD-capture protocol above. It does not
weaken any no-follow, journal-first, one-build/one-container, allowlist,
fingerprint, recovery, or review gate.

Before resuming implementation, import the new documentation-only child of
`c8d2d2fa9a4e137ba8e2400140a17dc2ef47fd8e` while proving that the seven local
changes remain byte-identical:

```bash
set -euo pipefail
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
IID_PLAN_PATH=docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
git diff --cached --exit-code
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
test "$(git rev-parse HEAD)" = "60ecb54175fd1172ffe2105a8059702f8b3d8ea0"
test "$(git rev-parse HEAD^)" = "9d204ab10801cd2cb07ec8d5ee6a759b12dd296b"
IID_STATUS_BEFORE=$(mktemp /tmp/better-ahead-iid-status.XXXXXX)
IID_DIFF_BEFORE=$(mktemp /tmp/better-ahead-iid-diff.XXXXXX)
MANAGER_STATUS_BEFORE=$(mktemp /tmp/better-ahead-iid-manager-status.XXXXXX)
DIAGNOSTIC_STATUS_BEFORE=$(mktemp /tmp/better-ahead-iid-diagnostic-status.XXXXXX)
git status --porcelain=v1 -z -uall > "$IID_STATUS_BEFORE"
git diff --binary > "$IID_DIFF_BEFORE"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_BEFORE"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_BEFORE"
test "$(shasum -a 256 "$IID_DIFF_BEFORE" | awk '{print $1}')" \
  = "3a9aab2ae42ff2921265a0366765a52ad6c4d01118cbe83953fb71775d20c22a"
test "$(shasum -a 256 scripts/brand/better-ahead-brand-contract.test.mjs \
  | awk '{print $1}')" \
  = "bd5c7dbbab702cfce4f40e087cf8321ce01b6135be383cf2ed5d2da6a25020fd"
test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test ! -s "$MANAGER_STATUS_BEFORE"
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
test "$(shasum -a 256 "$DIAGNOSTIC_STATUS_BEFORE" | awk '{print $1}')" \
  = "4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c"
test -n "${IID_CAPTURE_DOC_SHA:?set IID_CAPTURE_DOC_SHA to the exact published documentation SHA from the handoff}"
test "${#IID_CAPTURE_DOC_SHA}" = 40
case "$IID_CAPTURE_DOC_SHA" in *[!0-9a-f]*) false ;; esac
git fetch origin codex/better-ahead-rebranding-design
test "$(git rev-list --parents -n 1 "$IID_CAPTURE_DOC_SHA" | awk '{print NF}')" = 2
test "$(git rev-parse "$IID_CAPTURE_DOC_SHA^")" \
  = "c8d2d2fa9a4e137ba8e2400140a17dc2ef47fd8e"
test "$(git rev-parse "$IID_CAPTURE_DOC_SHA^0")" \
  = "$(git rev-parse origin/codex/better-ahead-rebranding-design)"
test "$(git diff-tree --no-commit-id --name-only -r "$IID_CAPTURE_DOC_SHA")" \
  = "docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md"
test "$(git rev-parse "HEAD:$IID_PLAN_PATH")" \
  = "$(git rev-parse "${IID_CAPTURE_DOC_SHA}^:$IID_PLAN_PATH")"
git cherry-pick "$IID_CAPTURE_DOC_SHA"
test "$(git rev-parse HEAD^)" = "60ecb54175fd1172ffe2105a8059702f8b3d8ea0"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" = "$IID_PLAN_PATH"
test "$(git ls-tree HEAD -- "$IID_PLAN_PATH")" \
  = "$(git ls-tree "$IID_CAPTURE_DOC_SHA" -- "$IID_PLAN_PATH")"
git diff --cached --exit-code
IID_STATUS_AFTER=$(mktemp /tmp/better-ahead-iid-status-after.XXXXXX)
IID_DIFF_AFTER=$(mktemp /tmp/better-ahead-iid-diff-after.XXXXXX)
MANAGER_STATUS_AFTER=$(mktemp /tmp/better-ahead-iid-manager-status-after.XXXXXX)
DIAGNOSTIC_STATUS_AFTER=$(mktemp /tmp/better-ahead-iid-diagnostic-status-after.XXXXXX)
git status --porcelain=v1 -z -uall > "$IID_STATUS_AFTER"
git diff --binary > "$IID_DIFF_AFTER"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_AFTER"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_AFTER"
cmp "$IID_STATUS_BEFORE" "$IID_STATUS_AFTER"
cmp "$IID_DIFF_BEFORE" "$IID_DIFF_AFTER"
cmp "$MANAGER_STATUS_BEFORE" "$MANAGER_STATUS_AFTER"
cmp "$DIAGNOSTIC_STATUS_BEFORE" "$DIAGNOSTIC_STATUS_AFTER"
test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
test "$(git status --porcelain=v1 -z -uall \
  | LC_ALL=C tr -cd '\000' | wc -c | tr -d ' ')" = "7"
```

After that preservation gate, run the already-authored external OA-EXT cases as
REDs before implementation, finish the two outstanding mirror/cleanup REDs and
OA-29, then implement the capture protocol only within the eight-path Task 3
write allowlist above. The preserved seven-file dirty set remains the starting
state; the eighth authorized path may change only if a new RED demonstrates it
is required. OA-29 must become GREEN by
allowing the journal to record legitimate
same-inode stderr growth and a failed/empty IID capture as
`RECOVERY_REQUIRED` before any render receipt exists. Re-run the complete
unfrozen Corepack/pnpm 10.33.2 suite and both independent reviews required above.
No real Docker, fingerprint capture, or renderer may run until those gates pass;
no new helper file is authorized.

**Current-execution reconciliation after the native-helper V3 oracle gate**

The local Task 3 execution imported the preceding documentation reconciliation
as `726bae58042dc4da86b08f3fa52de0f2dccc24a4` and then stopped before applying
the Round 3 oracle work. The reported worktree still has exactly seven unstaged
Task 3 files, empty staging, and contract-test SHA-256
`bd5c7dbbab702cfce4f40e087cf8321ce01b6135be383cf2ed5d2da6a25020fd`.
No Docker command, fingerprint capture, render, `environment.json`, bundle,
lock, journal, or transaction was created. The local divergence report at
`/tmp/better-ahead-native-v3-legacy-migration-seam-divergence.md`, reported as
SHA-256 `0fa307f2f602297e5e41bebbca99afc639697c83ee2b0e6f3840fd0513e1fd6f`, is
ephemeral audit evidence only; this committed section is the self-contained
authority. Do not apply the uncommitted `/tmp` Round 3 material blindly.

The earlier local brief required behavioral coverage for OA-16 and the six
OA-34 races while keeping `runNativeHelperV3` private and forbidding test
controls in production recovery/cleanup interfaces, argv, environment,
markers, and polling. Those requirements are compatible only with the following
closed, programmatic test seam, which is now explicitly authorized and is
controlling wherever the earlier generic interface language appears narrower.
It does not weaken any production threat-model, no-follow, recovery, cleanup,
unlock, journal, one-build/one-container, allowlist, or review requirement.

**Closed oracle API and confinement**

- The existing renderer module may add exactly one new test-only named export,
  `nativeHelperV3TestOracle = Object.freeze({ open, probe })`.
  `runNativeHelperV3` itself remains lexical/module-private and is not re-exported.
- The initial `open(caseId)` inventory contains the following seven string
  literals. The later legacy-test reconciliation preserves them unchanged and
  defines the only authorized expansion. Unknown values and every extra
  argument/property remain rejected:

  ```text
  oa16.fd3_truncated
  oa34.mirror.pre_unlink
  oa34.mirror.post_unlink
  oa34.transaction.pre_rmdir
  oa34.transaction.post_rmdir
  oa34.lock.pre_unlink
  oa34.lock.post_unlink
  ```

- `probe(probeId)` accepts exactly one of the following closed negative IDs. It
  internally constructs the named malformed frame, descriptor topology, or
  lifecycle fault and returns one frozen audit result; it accepts no raw bytes,
  FD number, path, command, callback, timeout, environment, or options object:

  ```text
  protocol.wrong_magic
  protocol.wrong_version
  protocol.wrong_kind
  protocol.wrong_opcode
  protocol.nonzero_reserved
  protocol.wrong_session_nonce
  protocol.wrong_barrier_challenge
  protocol.wrong_sequence
  protocol.short_frame
  protocol.oversized_frame
  protocol.trailing_frame
  protocol.duplicate_frame
  protocol.out_of_order_release
  protocol.eof_before_release
  descriptor.fd4_missing
  descriptor.fd5_missing
  descriptor.fd4_nonpipe
  descriptor.fd5_nonpipe
  lifecycle.barrier_not_reached
  production.ambient_control_fds_closed
  production.descendant_control_fds_closed
  ```

- Both methods create and physically validate their own `0700` `mkdtemp`
  fixture under the attested local temporary root. They accept no repository
  root, pathname, command, arbitrary operation, or caller-controlled protocol
  material. Each fixture includes an independently hashed sentinel outside the
  subtree presented to the native operation. No live-repository path or Docker
  command is reachable from this façade. The negative matrix is an explicit
  test seam, not an additional production opcode or recovery/cleanup interface.
- The returned frozen, single-use OA-34 session exposes only `start()`, the
  `reached` Promise, `inject(eventToken)`, `release(eventToken)`, the `result`
  Promise, `audit()`, and `dispose()`. `await session.reached` supplies an opaque
  token bound to that exact session and case. `inject` performs only the case's
  fixed mutation; it accepts no callback or data. That same token authorizes exactly
  one `inject` and then exactly one immediately subsequent `release`; a second
  call in either phase or any use after release is reuse and fails closed.
  Cross-case, cloned, forged, serialized, proxied, or otherwise out-of-order
  sessions/tokens also fail closed.
- The only valid behavioral lifecycles are:

  | Case | Exact lifecycle |
  |---|---|
  | OA-16 | `open -> start` resolves after `ARM/ARMED` and closes FD4 -> `result` rejects with `NATIVE_HELPER_V3_TRUNCATED_RESPONSE` only after `CONSUMED`, FD5 EOF, and helper reap -> `audit -> dispose` |
  | OA-34 | `open -> start` resolves after `ARM/ARMED` -> `eventToken = await session.reached -> await session.inject(eventToken) -> await session.release(eventToken)` and FD4 close -> `result` settles only after `CONSUMED`, FD5 EOF, and helper reap -> `audit -> dispose` |

  The OA-16 session has the same frozen one-shot base but omits the `reached`,
  `inject`, and `release` members entirely; tests prove those properties are
  absent. `audit` is unavailable before `result` settles. Normal `dispose`
  follows one audit; early `dispose` is only the fail-closed abort path defined
  below. A repeated `start`, `audit`, normal `dispose`, or any other transition
  rejects.
- Internally, the session is registered by object identity in a module-private
  `WeakMap` and closes over a one-shot capability. Only that identity may reach
  a private final oracle parameter of `runNativeHelperV3`; every production call
  supplies the immutable `NO_ORACLE` sentinel. This explicitly authorizes that
  one module-private signature parameter; no public production function,
  renderer/recovery/cleanup interface, or serialized
  request/journal/recovery/receipt/log schema carries the capability.
- Arbitrary code already executing in the same trusted Node process could
  import the test façade, but the façade can touch only its self-created fixture
  and cannot select an operation or path. This is within the existing
  compromised-same-UID/process exclusion and is not authority to expose a
  runtime or live-repository test hook.

**Anonymous native protocol**

- FD3 retains its existing V3 payload role and framing. Only a recognized oracle
  session adds two anonymous pipes: FD4 carries fixed parent-to-helper control
  frames and FD5 carries fixed helper-to-parent acknowledgements. The native
  helper sets both control descriptors close-on-exec before it can spawn any
  descendant. Docker, a fake child, and every production child observe FD4/FD5
  closed; an ordinary production helper invocation receives neither descriptor.
- Each control frame is exactly 48 bytes: ASCII magic `BAO3` (4 bytes), version
  `1` (one byte), kind `ARM|RELEASE|ARMED|REACHED|CONSUMED` (one byte), one
  closed opcode byte, one zero reserved byte, a 32-byte in-memory authenticator,
  and one unsigned 64-bit big-endian phase sequence. There is no variable payload.
  Kind codes are fixed as `ARM=0x01`, `RELEASE=0x02`, `ARMED=0x81`,
  `REACHED=0x82`, and `CONSUMED=0x83`; opcode codes `0x01` through `0x07` map in
  the exact initial OA case-ID order listed above, and the later reconciliation
  assigns the only additional valid codes. `ARM/ARMED` use sequence `1` and echo
  a fresh parent-generated session nonce. At an OA-34 barrier the helper obtains
  a new unpredictable 32-byte challenge from the operating system and emits it
  only in `REACHED` with sequence `2`; the matching `RELEASE` must echo that
  challenge and sequence, and `CONSUMED` echoes it with sequence `3`. A release
  queued before `REACHED` cannot know the challenge and therefore fails closed.
  OA-16 uses the session nonce in `CONSUMED` with sequence `2`.
- Every endpoint uses exact-length blocking reads under the fixed watchdog, not
  polling. For OA-16 the parent closes FD4 immediately after validated `ARMED`;
  the helper requires that EOF before producing the truncated FD3 payload,
  emits exact `CONSUMED`, and closes FD5. For OA-34 the parent writes the single
  exact `RELEASE` only after fixed injection, then closes FD4; the helper reads
  the frame and requires immediate EOF before it can cross any pending PRE
  syscall or continue a POST path, then emits exact `CONSUMED` and closes FD5.
  The parent requires FD5 EOF and helper reap after `CONSUMED`. These explicit
  closes make short, oversized, and trailing input distinguishable without a
  sleep, marker, nonblocking peek, or polling.
- The helper-generated challenge is exposed to JavaScript only as the opaque
  session-bound `eventToken`; callers never receive its bytes. `inject` must
  complete and durably verify its fixed mutation before the closed façade may
  echo the challenge in `RELEASE`.
  Wrong magic, version, kind, opcode, reserved byte, authenticator, or sequence;
  short, oversized, trailing, duplicated, or out-of-order frames; EOF on a
  required control pipe; a non-pipe descriptor; or only one of FD4/FD5 being
  present
  aborts before every not-yet-executed guarded syscall and preserves the
  auditable state. At a POST barrier the named syscall has already linearized,
  so a protocol failure performs no later destructive syscall and preserves the
  exact post-syscall state for audit; it never pretends to roll that syscall back.
- The native oracle arms and consumes exactly one truncation or barrier. A
  second matching boundary is an error, never a silent no-op or retry. No oracle
  byte is written to the production payload, journal, recovery mirror, receipt,
  log, marker, or filesystem.

**OA-16: truncated FD3 payload**

For `oa16.fd3_truncated`, use the normal canonical V3 encoder for the existing
non-destructive fixture operation, write the complete frame except its final
byte to FD3, close the producer end to provide real EOF, and exit the native
helper successfully. The truncation offset is fixed at `canonicalLength - 1`
and is not caller-controlled. The consumer must reject it with stable
classification `NATIVE_HELPER_V3_TRUNCATED_RESPONSE`; it must not parse a
prefix, consult stdout/stderr or a pathname fallback, return partial data,
retry/reinvoke the helper, advance a transaction, clean up, unlock, or call
Docker. The behavioral GREEN test proves one invocation, declared length `N`,
observed length `N - 1`, real EOF, native exit zero, zero retry/Docker/mutation,
and byte-identical fixture and sentinel state. Its RED must fail because the
closed oracle behavior is absent, not because of timing.

**OA-34: six deterministic cleanup/unlock boundaries**

The PRE barriers occur immediately before the final anchored no-follow identity
revalidation that precedes the destructive syscall. They must never be inserted
between that final validation and the syscall, because the existing threat model
does not claim protection from an already-compromised same-UID process inside
that private interval. The mirror/transaction POST barriers occur immediately
after the successful syscall and before their absence postcondition and parent
fsync. The lock POST barrier occurs after its linearizing unlink and before only
the retained-parent fsync; it performs no absence lookup. Each `REACHED` is
emitted exactly once; only the matching fixed `inject` may precede `RELEASE`.

1. `oa34.mirror.pre_unlink`: replace the mirror leaf with a distinct
   inode/sentinel before final revalidation. The helper detects the mismatch,
   does not unlink the replacement, reports non-success/`BLOCKED`, and retains
   the authoritative lock and recoverable evidence.
2. `oa34.mirror.post_unlink`: after the expected mirror inode is unlinked but
   before absence proof and parent fsync, recreate that leaf with a distinct
   inode/sentinel. The helper detects the unexpected entry, preserves it,
   reports non-success/`BLOCKED`, and retains the lock; it never removes the new
   leaf as fallback cleanup.
3. `oa34.transaction.pre_rmdir`: replace the validated empty transaction
   directory with a distinct directory containing a sentinel before final
   revalidation. The helper detects the identity/content divergence, removes
   nothing from the replacement, reports non-success/`BLOCKED`, and retains the
   lock.
4. `oa34.transaction.post_rmdir`: after removing the expected transaction
   directory but before absence proof and parent fsync, recreate a distinct
   directory containing a sentinel. The helper preserves the new directory,
   reports non-success/`BLOCKED`, and retains the lock; it does not recurse or
   retry cleanup.
5. `oa34.lock.pre_unlink`: after all prior cleanup is durably complete but
   before the lock's final identity revalidation and unlink, replace the lock
   leaf with a distinct inode/sentinel. The helper detects the mismatch, does
   not unlink the replacement, and must not report unlock success.
6. `oa34.lock.post_unlink`: immediately after unlinking the old validated lock
   and before fsyncing its parent, acquire a new valid lock by exclusive create
   with a different run ID/nonce, then fsync that new lock and its parent and
   verify its identity before `inject` resolves and `RELEASE` is permitted. The
   old unlink is the unlock linearization point. The old helper performs only
   the prescribed anonymous `RELEASE/CONSUMED` exchange, its already-required
   retained-parent fsync, and return success; it performs no new pathname lookup,
   journal write, unlink, or other filesystem mutation. The durably published
   new lock remains byte- and inode-identical and blocks another writer.
   Treating that legitimate new owner as the old lock or removing it is a test
   failure.

Every case proves the independent sentinel's bytes, device, and inode remain
unchanged, the fixed injected object has the stated postcondition, no second
cleanup/helper attempt occurs, and Docker is never invoked. The first five
cases never claim successful cleanup/unlock; the sixth proves linearizable
successful unlock without harming the next owner.

**Synchronization, teardown, and negative gates**

- `reached` resolves only after an exact `REACHED` frame is read from FD5.
  `inject` completes its fixed mutation before `release` can emit the exact
  `RELEASE` frame on FD4. There is no sleep, stat loop, marker, or polling. One
  fixed 10-second monotonic watchdog is failure containment only, never race
  coordination.
- On timeout, assertion failure, early `dispose`, or EOF before release, close
  FD4 so the helper cannot cross any not-yet-executed guarded syscall; a POST
  case instead stops before any later cleanup/unlock action. Signal its dedicated
  process group with `TERM`, wait at most five seconds, use `KILL` if necessary,
  wait at most five more seconds, reap it, and close every descriptor. Audit the
  fixture and sentinel before teardown. Remove only the exact self-created
  fixture through no-follow traversal on audited success; if audit or teardown
  cannot be proved, preserve that `0700` fixture and report its exact path.
- Drive every raw-frame, descriptor-topology, and never-reached behavioral
  negative only through the exact closed `probe` IDs above. Add direct
  behavioral and source-level negatives for unknown/extra oracle input;
  forged/cloned/reused capability or token; wrong method order; duplicate event
  or release; all malformed control frames; missing/non-pipe FD4/FD5; helper
  never reaching the barrier; hostile `--oracle`, `--oa-*`, and `--test-*`
  flags; hostile environment names; ambient preopened FD4/FD5; and descendant
  descriptor inheritance. The public parser rejects unknown flags before any
  write, no environment value activates the seam, package scripts expose no
  oracle command, importing the module for the named test façade does not run
  `main` or any production admission, no schema accepts oracle fields, and
  `runNativeHelperV3` remains unexported. A normal production control case must
  preserve the prior behavior and descriptor inventory.

This oracle implementation remains inside the eight-path Task 3 allowlist and
may modify only `scripts/brand/render-better-ahead-brand-assets.mjs` plus
`scripts/brand/better-ahead-brand-contract.test.mjs` beyond already-preserved
changes. It creates no tracked helper or production dependency. Run its REDs
first, then its focused GREENs, the complete unfrozen contract suite with exact
`corepack pnpm@10.33.2`, `validate:inputs`, the preserved baseline, and
`git diff --check`. Both previously required independent final reviews must
cover the oracle's confinement, protocol, race linearization, and teardown and
report no Critical or Important finding. No real Docker, fingerprint capture,
renderer, Task 4, push, PR, merge, or deploy is authorized by this
reconciliation.

Before resuming, import this documentation-only child of
`359f4bb202c0c8a6696a033fe61f00085d2da720` while preserving every pre-existing
worktree and staging byte outside the authorized plan replacement. The fetch
and cherry-pick are explicitly allowed to update Git metadata such as
`FETCH_HEAD`, the named remote ref, index, reflog, and the new commit object;
the private `/tmp` snapshots are also expected new files.

```bash
set -euo pipefail
GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
ORACLE_PLAN_PATH=docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
ORACLE_PARENT_PLAN_BLOB=17776145d1b231ad5f057cf84f7c2048ca651e6d

git diff --cached --exit-code
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
test "$(git rev-parse HEAD)" = "726bae58042dc4da86b08f3fa52de0f2dccc24a4"
test "$(git rev-parse HEAD^)" = "60ecb54175fd1172ffe2105a8059702f8b3d8ea0"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" = "$ORACLE_PLAN_PATH"
test "$(git rev-parse "HEAD:$ORACLE_PLAN_PATH")" = "$ORACLE_PARENT_PLAN_BLOB"
git diff --exit-code -- "$ORACLE_PLAN_PATH"
for absent_path in \
  design/brand/better-ahead/environment.json \
  design/brand/better-ahead/bundles \
  design/brand/better-ahead/exports \
  design/brand/better-ahead/review
do
  test ! -e "$absent_path"
  test ! -L "$absent_path"
done
test -z "$(git ls-files --others --ignored --exclude-standard -- design/brand)"

ORACLE_STATUS_BEFORE=$(mktemp /tmp/better-ahead-oracle-status.XXXXXX)
ORACLE_DIFF_BEFORE=$(mktemp /tmp/better-ahead-oracle-diff.XXXXXX)
MANAGER_STATUS_BEFORE=$(mktemp /tmp/better-ahead-oracle-manager.XXXXXX)
DIAGNOSTIC_STATUS_BEFORE=$(mktemp /tmp/better-ahead-oracle-diagnostic.XXXXXX)
DIAGNOSTIC_DIFF_BEFORE=$(mktemp /tmp/better-ahead-oracle-diagnostic-diff.XXXXXX)
git status --porcelain=v1 -z -uall > "$ORACLE_STATUS_BEFORE"
git diff --binary > "$ORACLE_DIFF_BEFORE"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_BEFORE"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_BEFORE"
git -C "$DIAGNOSTIC_REPO" diff --binary > "$DIAGNOSTIC_DIFF_BEFORE"
ORACLE_DIRTY_COUNT=0
while IFS= read -r -d '' entry
do
  case "$entry" in
    " M "*) dirty_path=${entry:3} ;;
    *) false ;;
  esac
  case "$dirty_path" in
    design/brand/better-ahead-brand-assets.json|\
    scripts/brand/better-ahead-brand-contract.mjs|\
    scripts/brand/better-ahead-brand-contract.test.mjs|\
    scripts/brand/capture-better-ahead-environment.mjs|\
    scripts/brand/render-better-ahead-brand-assets.mjs|\
    scripts/brand/render-better-ahead-brand-review.mjs|\
    scripts/brand/run-better-ahead-brand-renderer.sh|\
    scripts/package.json) ;;
    *) false ;;
  esac
  ORACLE_DIRTY_COUNT=$((ORACLE_DIRTY_COUNT + 1))
done < "$ORACLE_STATUS_BEFORE"
test "$ORACLE_DIRTY_COUNT" = "7"
test "$(git diff --name-only -z | LC_ALL=C tr -cd '\000' \
  | wc -c | tr -d ' ')" = "7"
test "$(shasum -a 256 scripts/brand/better-ahead-brand-contract.test.mjs \
  | awk '{print $1}')" \
  = "bd5c7dbbab702cfce4f40e087cf8321ce01b6135be383cf2ed5d2da6a25020fd"
test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test ! -s "$MANAGER_STATUS_BEFORE"
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
test -z "$(git -C "$DIAGNOSTIC_REPO" ls-files --others --exclude-standard)"
test "$(git -C "$DIAGNOSTIC_REPO" diff --name-only -z \
  | LC_ALL=C tr -cd '\000' | wc -c | tr -d ' ')" = "9"
test "$(shasum -a 256 "$DIAGNOSTIC_STATUS_BEFORE" | awk '{print $1}')" \
  = "4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c"

test -n "${NATIVE_V3_ORACLE_DOC_SHA:?set the exact published documentation SHA from the handoff}"
test "${#NATIVE_V3_ORACLE_DOC_SHA}" = 40
case "$NATIVE_V3_ORACLE_DOC_SHA" in *[!0-9a-f]*) false ;; esac
git fetch origin codex/better-ahead-rebranding-design
test "$(git rev-list --parents -n 1 "$NATIVE_V3_ORACLE_DOC_SHA" \
  | awk '{print NF}')" = "2"
test "$(git rev-parse "$NATIVE_V3_ORACLE_DOC_SHA^")" \
  = "359f4bb202c0c8a6696a033fe61f00085d2da720"
test "$(git rev-parse "$NATIVE_V3_ORACLE_DOC_SHA^0")" \
  = "$(git rev-parse origin/codex/better-ahead-rebranding-design)"
test "$(git diff-tree --no-commit-id --name-only -r \
  "$NATIVE_V3_ORACLE_DOC_SHA")" = "$ORACLE_PLAN_PATH"
test "$(git rev-parse "$NATIVE_V3_ORACLE_DOC_SHA^:$ORACLE_PLAN_PATH")" \
  = "$ORACLE_PARENT_PLAN_BLOB"
test "$(git rev-parse "HEAD:$ORACLE_PLAN_PATH")" \
  = "$ORACLE_PARENT_PLAN_BLOB"
git diff --binary "$NATIVE_V3_ORACLE_DOC_SHA^" \
  "$NATIVE_V3_ORACLE_DOC_SHA" -- "$ORACLE_PLAN_PATH" | git apply --check

git -c core.hooksPath=/dev/null -c commit.gpgSign=false \
  cherry-pick "$NATIVE_V3_ORACLE_DOC_SHA"
test "$(git rev-parse HEAD^)" = "726bae58042dc4da86b08f3fa52de0f2dccc24a4"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" \
  = "$ORACLE_PLAN_PATH"
test "$(git ls-tree HEAD -- "$ORACLE_PLAN_PATH")" \
  = "$(git ls-tree "$NATIVE_V3_ORACLE_DOC_SHA" -- "$ORACLE_PLAN_PATH")"
git diff --cached --exit-code

ORACLE_STATUS_AFTER=$(mktemp /tmp/better-ahead-oracle-status-after.XXXXXX)
ORACLE_DIFF_AFTER=$(mktemp /tmp/better-ahead-oracle-diff-after.XXXXXX)
MANAGER_STATUS_AFTER=$(mktemp /tmp/better-ahead-oracle-manager-after.XXXXXX)
DIAGNOSTIC_STATUS_AFTER=$(mktemp /tmp/better-ahead-oracle-diagnostic-after.XXXXXX)
DIAGNOSTIC_DIFF_AFTER=$(mktemp /tmp/better-ahead-oracle-diagnostic-diff-after.XXXXXX)
git status --porcelain=v1 -z -uall > "$ORACLE_STATUS_AFTER"
git diff --binary > "$ORACLE_DIFF_AFTER"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_AFTER"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_AFTER"
git -C "$DIAGNOSTIC_REPO" diff --binary > "$DIAGNOSTIC_DIFF_AFTER"
cmp "$ORACLE_STATUS_BEFORE" "$ORACLE_STATUS_AFTER"
cmp "$ORACLE_DIFF_BEFORE" "$ORACLE_DIFF_AFTER"
cmp "$MANAGER_STATUS_BEFORE" "$MANAGER_STATUS_AFTER"
cmp "$DIAGNOSTIC_STATUS_BEFORE" "$DIAGNOSTIC_STATUS_AFTER"
cmp "$DIAGNOSTIC_DIFF_BEFORE" "$DIAGNOSTIC_DIFF_AFTER"
for absent_path in \
  design/brand/better-ahead/environment.json \
  design/brand/better-ahead/bundles \
  design/brand/better-ahead/exports \
  design/brand/better-ahead/review
do
  test ! -e "$absent_path"
  test ! -L "$absent_path"
done
test -z "$(git ls-files --others --ignored --exclude-standard -- design/brand)"
test "$(shasum -a 256 scripts/brand/better-ahead-brand-contract.test.mjs \
  | awk '{print $1}')" \
  = "bd5c7dbbab702cfce4f40e087cf8321ce01b6135be383cf2ed5d2da6a25020fd"
test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
```

If any precondition, parent/blob check, status/diff comparison, or repository
preservation check fails, stop without resolving a cherry-pick conflict or
editing/staging another file. After a successful import, first add the seven
closed OA cases and the closed negative-probe matrix as tracked behavioral REDs;
only then implement the minimal seam. Resume at the oracle RED, not at Docker
capture or render.

**Current-execution reconciliation after the read-only legacy-test inventory**

The local execution imported the preceding native-helper oracle authority as
`8f4020b0ae27d27c0de1b97d1682f507cd0be57c`, whose parent is
`726bae58042dc4da86b08f3fa52de0f2dccc24a4`, and then authored only the
tracked V3 oracle REDs in the contract test. The focused Corepack/pnpm 10.33.2
run produced 43 leaves: 33 expected REDs and 10 passing confinement sentinels.
Its complete log was reported as
`/tmp/better-ahead-native-v3-oracle-red-attempt2.log` with SHA-256
`fb79890356f3c9541615736ab185ef61a58e7882f0f76dffe94095b8e289b58d`.
Two independent reviews accepted that RED contract with no Critical,
Important, or Minor finding. Preserve that evidence; it need not be recreated
before this reconciliation is imported. The log is explicitly ephemeral: when
it still exists the handoff verifies its exact hash and summary; its absence
does not invalidate the committed documentary record, frozen test bytes, and
two accepted reviews and does not authorize a weaker substitute rerun.

The subsequent read-only inventory corrected the earlier approximate count and
is controlling:

- there are exactly 10 source blocks, `FCB-001` through `FCB-010`, using the
  four now-forbidden controls;
- those blocks materialize 23 leaves, of which 21 use a forbidden control and
  two are independent assertions that remain valid;
- there are exactly 107, not 108, tests depending on the removed
  `promoteBetterAheadCandidates` path: 106 transitively through the wrapper and
  one direct namespace lookup (`FP-079`);
- the apparent 108th test is the separate `NM-001` near-miss. It calls the
  still-supported recovery API and has an exact existing equivalent;
- the 107 tests partition exactly into 83 migrations, 20 removals tied only to
  the deleted flat-promotion architecture, and four P1 gaps that require
  additional closed oracle cases. No P0 gap was found.

The frozen source for that inventory is
`scripts/brand/better-ahead-brand-contract.test.mjs` at SHA-256
`61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1`
and Git blob OID `4c6619113829b83494292164696ee9abbd315eaf`. `FP-001`
through `FP-107` identify, in increasing source order, the complete top-level
registrations between the former lines 4148 and 9180 whose dependency chain
reaches the absent export; `FP-079` is the one direct namespace call. The
wrapper at the former lines 44-45 has SHA-256
`e2fe2a9b7d2dfaf6c8d8a9d152ea02f1a1bae219a54e0f5fe6941729375026a5`.
The IDs and classifications below remain stable even after line numbers move.

This section supersedes the earlier seven-case limit, the instruction to keep
the incompatible legacy test tail unchanged, and the immediately preceding
post-import instruction to author the seven OA REDs. Those REDs are already
present and accepted at the frozen test hash. Every earlier state-specific
import block remains historical evidence only; the preservation/import handoff
in this section is the sole executable re-entry point. This does not supersede
the private-helper boundary, negative-probe matrix, atomic-bundle architecture,
one-build/one-container rule, no-follow model, or any Docker/render gate. It
narrows the current migration write set as explicitly stated below.

**Frozen legacy-test disposition**

The 83 `MIGRATE` IDs are:

```text
FP-002 FP-003 FP-004 FP-005 FP-006 FP-007 FP-008 FP-009 FP-010
FP-011 FP-012 FP-013 FP-019 FP-020 FP-021 FP-022 FP-023 FP-024
FP-025 FP-027 FP-028 FP-030 FP-031 FP-032 FP-033 FP-034 FP-037
FP-038 FP-039 FP-040 FP-041 FP-042 FP-043 FP-044 FP-045 FP-046
FP-047 FP-048 FP-049 FP-050 FP-053 FP-054 FP-055 FP-057 FP-058
FP-059 FP-060 FP-061 FP-063 FP-064 FP-065 FP-067 FP-068 FP-069
FP-070 FP-072 FP-073 FP-074 FP-075 FP-076 FP-078 FP-079 FP-080
FP-081 FP-082 FP-083 FP-084 FP-085 FP-086 FP-087 FP-088 FP-089
FP-090 FP-093 FP-094 FP-097 FP-098 FP-099 FP-101 FP-102 FP-105
FP-106 FP-107
```

They partition without overlap into these nine migration owners:

| Owner | Closed classifier | Count | IDs | Required current path |
|---|---|---:|---|---|
| Validation, admission, and sealing | `VALIDATION_ADMISSION_SEALING` | 10 | `FP-002,004,005,027,057,070,079,083,098,099` | `begin -> dispatch -> resume -> finish`; sealing assertions execute in `finish` |
| Initial authority and owned workspace | `INITIAL_AUTHORITY_WORKSPACE` | 8 | `FP-007,028,046,047,048,049,050,053` | `begin -> recover` |
| Atomic-bundle materialization/publication | `ATOMIC_BUNDLE_PUBLICATION` | 14 | `FP-040,041,043,044,045,058,060,063,064,065,074,076,097,102` | `dispatch -> resume -> finish` |
| Journal update and resume reconciliation | `JOURNAL_RESUME_RECONCILIATION` | 12 | `FP-003,008,009,030,031,032,033,034,037,038,039,042` | `resume -> recover` |
| Commit durability and physical truth | `COMMIT_DURABILITY_PHYSICAL_TRUTH` | 4 | `FP-006,025,061,067` | `finish -> recover` |
| Path confinement and physical identity | `PATH_CONFINEMENT_IDENTITY` | 6 | `FP-020,021,022,023,024,068` | `begin/finish/recover` |
| Convergence, idempotency, and runner state | `CONVERGENCE_IDEMPOTENCY_RUNNER` | 7 | `FP-012,013,019,069,080,081,107` | interrupted `finish/recover` followed by fixed recovery |
| Cleanup ownership and integrity | `CLEANUP_OWNERSHIP_INTEGRITY` | 11 | `FP-054,055,059,075,078,082,084,085,101,105,106` | `finish/recover` |
| Final authority revalidation/removal | `FINAL_AUTHORITY_REVALIDATION` | 11 | `FP-010,011,072,073,086,087,088,089,090,093,094` | final `finish/recover` unlock |

Each migrated registration keeps its `FP-nnn` ID in its new test name or an
immediately adjacent literal comment and keeps the inventory's complete
input/action/matcher/invariant assertion. It must traverse the named current
lifecycle owner, not merely call a validation helper directly. `FP-079` must
use the real dispatcher and current bundle validation; it may not dynamically
look up the absent export. Tests that formerly named a flat receipt, restore,
displacement, or proof may retain only the invariant identified above and must
retarget it to current lock/update/mirror/transaction/candidate/staged-bundle
objects. They must not recreate the removed object model to preserve an old
test shape.

The 20 `DELETE_REMOVED_ARCHITECTURE` IDs are:

```text
FP-001 FP-014 FP-015 FP-016 FP-017 FP-018 FP-026 FP-029 FP-035
FP-036 FP-051 FP-052 FP-056 FP-062 FP-066 FP-071 FP-077 FP-100
FP-103 FP-104
```

Remove those complete registrations. Their only claimed objects are independent
per-destination publication, originals/backups, rollback of the active tree,
the root manifest as a receipt, per-destination pending records, or the removed
`M/Q/P` proof scheme. Do not replace them with skipped tests, aliases, archived
dead code, a compatibility export, or a test-only reconstruction of flat
promotion. Their absence is a positive architecture assertion.

The four `NEEDS_NEW_CLOSED_OPEN` IDs are:

```text
FP-091 FP-092 FP-095 FP-096
```

`FP-091` covers a physical edge swap after `openat`, `FP-092` a missing suffix
that reappears, `FP-095` a same-inode authority mutation after validation, and
`FP-096` both fixed variants of mutation after second-pass rebind. They migrate
only through the new closed `oa35.unlock.*` cases below. The two fixed
`FP-096` variants remain one traceability owner; they do not authorize a
caller-selected mutation.

Remove the duplicate `NM-001` registration only after identifying and
annotating its exact retained equivalent, formerly at test lines 3632-3658.
Preserve that equivalent and add the `NM-001` traceability ID to its name or
adjacent comment. This deletion is outside the 107 count.

The old `createPromotionFixture`, deferred
`promoteBetterAheadCandidates` wrapper, direct namespace lookup, and every
helper used only by the 20 removed blocks must disappear when their final live
consumer disappears. The renderer export surface must continue to prove that
`promoteBetterAheadCandidates` is absent.

**FCB migration ledger**

The following mapping is exhaustive. A `KEEP` entry means extract the
independent leaf before deleting the old controlled block.

| Block | Controlled replacement | Independent disposition |
|---|---|---|
| `FCB-001` | `oa35.begin.temporary_fsync.crash_orphan` | none |
| `FCB-002` | `oa35.journal.update_temporary_fsync.crash` | keep the pre-existing update collision leaf |
| `FCB-003` | `oa35.journal.update_rename.crash` and `oa35.journal.update_parent_fsync.crash` | none |
| `FCB-004` | `oa35.cleanup.pre_first_unlink.nonprefix_absence` | none |
| `FCB-005` | `oa35.begin.temporary_fsync.fail_clean` and `oa35.begin.temporary_fsync.crash_orphan` | none |
| `FCB-006` | `oa35.cleanup.early_lock_replacement` | none |
| `FCB-007` | `oa35.unlock.precommit_pre_unlink.fail_retry` | none |
| `FCB-008` | `oa35.cleanup.same_byte_leaf_replacement`, `oa35.cleanup.hardlinked_leaf`, and `oa35.cleanup.transaction_directory_swap` | keep the pre-payload same-byte replacement leaf |
| `FCB-009` | `oa35.unlock.committed_pre_unlink.fail_retry` and `oa35.unlock.bundle_same_inode_mutation` | none |
| `FCB-010` | the four `oa35.journal.mirror_*`/`predecessor_unlink` cases and three `oa35.cleanup.after_*` cases | none |

After extraction, remove the ten old controlled registrations rather than
leaving both implementations. The two `KEEP` leaves use only current public
lifecycle APIs and no oracle case. Every replacement keeps its `FCB-nnn` ID and
asserts the same durable and negative postconditions on the current
atomic-bundle state.

For the shared `FCB-001`/retained `FCB-005` begin case only, the legacy
transport distinction between caller-selected `fail` and `crash` is explicitly
non-normative: it existed solely because of the forbidden `retain` fault
option. The preserved production contract is the exact durable
`BEGIN_ORPHANED` state, second-writer block, and exact orphan recovery.
`crash_orphan` exercises that state through one real fixed interruption. This is
the sole exception to retaining the old failure class and is why the closed
inventory has 25 rather than 26 new IDs.

**Closed OA-35 expansion**

The named export remains exactly
`nativeHelperV3TestOracle = Object.freeze({ open, probe })` and
`runNativeHelperV3` remains lexical/module-private. The 21 `probe` IDs, their
behavior, and their negative lifecycle are unchanged. The seven existing
`open` IDs and opcodes `0x01` through `0x07` are unchanged. The following 25
additional literals are the complete authorized expansion, making exactly 32
`open` IDs. Twenty of the new literals replace the 21 controlled FCB leaves
(the one retained-begin invariant is deliberately consolidated); the remaining
five cover the four FP P1 owners because `FP-096` has two distinct mutations.
Their opcodes are fixed by this order:

```text
0x08 oa35.begin.temporary_fsync.fail_clean
0x09 oa35.begin.temporary_fsync.crash_orphan
0x0a oa35.journal.update_temporary_fsync.crash
0x0b oa35.journal.update_rename.crash
0x0c oa35.journal.update_parent_fsync.crash
0x0d oa35.journal.mirror_temporary_fsync.crash
0x0e oa35.journal.mirror_swap.crash
0x0f oa35.journal.mirror_parent_fsync.crash
0x10 oa35.journal.predecessor_unlink.crash
0x11 oa35.cleanup.pre_first_unlink.nonprefix_absence
0x12 oa35.cleanup.after_first_unlink.crash
0x13 oa35.cleanup.after_mirror_unlink.crash
0x14 oa35.cleanup.after_transaction_rmdir.crash
0x15 oa35.cleanup.early_lock_replacement
0x16 oa35.cleanup.same_byte_leaf_replacement
0x17 oa35.cleanup.hardlinked_leaf
0x18 oa35.cleanup.transaction_directory_swap
0x19 oa35.unlock.precommit_pre_unlink.fail_retry
0x1a oa35.unlock.committed_pre_unlink.fail_retry
0x1b oa35.unlock.bundle_same_inode_mutation
0x1c oa35.unlock.edge_swap_after_openat
0x1d oa35.unlock.missing_suffix_reappears
0x1e oa35.unlock.authority_same_inode_mutation
0x1f oa35.unlock.second_pass_edge_swap
0x20 oa35.unlock.second_pass_missing_suffix
```

Each OA-35 top-level name places these exact trace tokens, in this order,
immediately after its leading opcode token. No other `FCB-nnn` or `FP-nnn`
token may appear in that name:

```text
08 FCB-005
09 FCB-001 FCB-005
0a FCB-002
0b FCB-003
0c FCB-003
0d FCB-010
0e FCB-010
0f FCB-010
10 FCB-010
11 FCB-004
12 FCB-010
13 FCB-010
14 FCB-010
15 FCB-006
16 FCB-008
17 FCB-008
18 FCB-008
19 FCB-007
1a FCB-009
1b FCB-009
1c FP-091
1d FP-092
1e FP-095
1f FP-096
20 FP-096
```

The malformed-opcode negative uses an unsupported value outside
`0x01..0x20`. Unknown case IDs, old control names, extra arguments/properties,
raw opcode numbers, and every nonliteral attempt still reject before fixture or
filesystem creation.

All OA-35 cases use the same frozen, identity-bound, single-use session,
anonymous FD4/FD5 pipes, challenge, sequence, and
`ARM/ARMED/REACHED/RELEASE` frames already specified for OA-34.
`await session.reached` returns only an opaque token and `release(token)`
permits exactly one continuation. Mutation cases retain the OA-34 rule:
`inject(token)` performs and durably verifies exactly the case's fixed mutation
before release, with no caller data; the helper then emits exact `CONSUMED`,
closes FD5, and is reaped normally.

For a fixed ordinary-failure case, `inject(token)` instead arms only the
compiled-in error named by that literal. After exact `RELEASE` and FD4 EOF, the
helper emits exact `CONSUMED`, returns that fixed error, closes FD5, and is
reaped with the declared ordinary-error status.

A literal ending in `.crash`, plus `crash_orphan` and
`pre_first_unlink.nonprefix_absence`, uses a distinct honest-interruption
terminal lifecycle. `inject(token)` arms only fixed `_exit(86)`. After exact
`RELEASE` and FD4 EOF, the helper validates the frame and exits 86 at the named
boundary without emitting `CONSUMED`; process exit supplies FD5 EOF. The parent
requires that it successfully sent the exact challenge-bound release, then
observes no `CONSUMED` byte, FD5 EOF, exact exit 86, helper reap, and the case's
exact physical PRE or POST state. A PRE case executed no named destructive
syscall; a POST case already executed only its named syscall. Any frame byte,
unexpected acknowledgement, exit status, additional syscall, physical state,
or teardown difference rejects. `protocol.eof_before_release` remains distinct:
no valid release was sent, it uses its existing non-86 protocol classification,
and it must retain the pre-release state. An arbitrary helper death therefore
cannot satisfy an interruption case.

The oracle's `result` resolves to a frozen controlled-case outcome only when
the applicable normal, ordinary-error, or honest-interruption terminal sequence
matches exactly. Existing OA-16/OA-34 `CONSUMED` semantics remain unchanged.

Any declared fixed recovery pass starts only after the interrupted helper is
reaped. The façade performs exactly the declared zero, one, or two passes
against only its self-created fixture; `result` does not settle until those
passes finish and their classifications are frozen for `audit()`. The caller
cannot choose an operation, path, target, fault mode, retry count, or recovery
action.

Every case creates and physically validates its own `0700` temporary fixture,
includes an external independently hashed sentinel, and invokes no Docker
command. On successful result, audit, and teardown, neither the session nor
`audit()` exposes a fixture path or mutable object. `audit()` may expose only
frozen scalar classifications, counts, expected/observed identities and hashes,
and the case's declared final-state facts; it exposes no descriptor, byte
buffer, path, callback, command, function, or reusable capability. If audit or
teardown cannot be proved, preserve the fixture and report its exact path only
in the terminal failure diagnostic as already required above. The existing
watchdog is teardown containment only.

The 25 cases have these exact fixed effects and outcomes:

1. `fail_clean` reaches the initial temporary-fsync boundary, returns the fixed
   ordinary failure, proves the exact begin temporary and lock are absent, and
   ends `IDLE` without recovery.
2. `crash_orphan` crashes at that same boundary, proves the exact begin
   temporary remains while the lock is absent and a second begin reports
   `BEGIN_ORPHANED`, then performs one exact orphan recovery and ends `IDLE`.
   This one real interruption replaces both legacy retained branches; the
   artificial caller-selected `fail|crash` plus `retain` combination is removed,
   not reproduced.
3. `update_temporary_fsync.crash` crashes after the update temporary is durable
   but before its rename; the prior lock stays authoritative, the exact owned
   update temporary is the only extra leaf, another writer remains blocked, and
   fixed recovery converges without Docker.
4. `update_rename.crash` crashes immediately after the next lock-journal swap;
   recovery reconciles that exact next authority with its predecessor update,
   never promotes the mirror, and converges without Docker.
5. `update_parent_fsync.crash` crashes immediately after the swapped
   lock-journal parent fsync and proves the same exact durable reconciliation.
6. `mirror_temporary_fsync.crash`, `mirror_swap.crash`,
   `mirror_parent_fsync.crash`, and `predecessor_unlink.crash` each stop at
   exactly the named mirror/update boundary, preserve the physically
   authoritative lock and all required evidence, and converge through the
   exact fixed recovery sequence without a new render.
7. `pre_first_unlink.nonprefix_absence` reaches the point before cleanup's first
   unlink, consumes exact release, then performs the fixed exit-86 interruption
   and reaps that helper without a cleanup mutation. Only after reap, the closed
   façade removes the case's fixed later owned leaf and starts exactly one new
   recovery. That recovery rejects the non-prefix absence before mutation,
   preserves the remaining authority and evidence, and performs no fallback
   deletion or unlock.
8. `after_first_unlink.crash`, `after_mirror_unlink.crash`, and
   `after_transaction_rmdir.crash` crash immediately after exactly the named
   successful cleanup mutation. Recovery accepts only that exact prefix,
   revalidates every surviving object, converges to `IDLE`, and never rerenders.
9. `early_lock_replacement` replaces the authoritative lock with the fixed
   distinct sentinel before cleanup's first mutation; cleanup/unlock blocks and
   preserves the replacement, prior authority evidence, transaction, and
   external sentinel.
10. `same_byte_leaf_replacement` replaces the exact journal-enumerated leaf
    used by the frozen `FCB-008` row with a byte-identical distinct inode;
    `hardlinked_leaf` gives that row's exact regular leaf an additional link;
    and `transaction_directory_swap` replaces that row's exact directory with
    a distinct nonempty directory. Each blocks before deleting the unowned
    object and retains the lock and external sentinel.
11. `precommit_pre_unlink.fail_retry` reaches the final lock-unlink boundary in
    the precommit recovery state, returns the fixed ordinary failure, proves
    the lock remains after all earlier permitted cleanup, and one exact retry
    converges to `IDLE`.
12. `committed_pre_unlink.fail_retry` does the same in
    `BUNDLE_COMMITTED/CLEANUP_REQUIRED`, additionally proving the immutable
    bundle and receipt remain byte- and inode-identical through the retry.
13. `bundle_same_inode_mutation` mutates the fixed committed wordmark leaf
    in-place after the prior/second-pass bundle-content validation but before
    the final in-child revalidation that precedes authority removal. Unlock
    blocks, retains the lock, performs no later pathname mutation, and preserves
    the mutated fixture for audit. The barrier is never placed inside the final
    revalidation-to-unlink private interval.
14. `edge_swap_after_openat` swaps the fixed held physical parent edge after
    its first `openat`; `missing_suffix_reappears` creates the fixed previously
    absent suffix after that absence was observed. Both block final unlock,
    preserve the injected object and authority, and touch no external sentinel.
15. `authority_same_inode_mutation` changes the lock-journal bytes in the same
    inode after a prior authority-validation pass and before the final in-child
    revalidation. That final revalidation detects the content divergence and
    retains authority; the barrier is not inside its private unlink interval.
16. `second_pass_edge_swap` and `second_pass_missing_suffix` perform their
    respective fixed edge/suffix mutation only after the second-pass rebind.
    Both block before lock unlink and preserve all injected and authority
    objects.

The case implementation must use the exact literal target and failure class
defined by this OA-35 table for the frozen FCB/FP owner cited above. The only
intentional consolidation is `crash_orphan`, whose fixed real interruption
replaces the two removed caller-selected retained modes. No row may be
generalized into an arbitrary barrier, path, mutation, failure mode, or
callback. Cases that share a native boundary may share private implementation
code, but not an opcode or test result when their failure class, state, target,
or durable postcondition differs. This is why `FP-096` has two literals and why
the precommit and committed final-unlock retries remain distinct.

No `nativeBeginFault`, `nativeJournalUpdateFault`, `nativeCleanupFault`, or
`nativeCleanupBarrier` field may remain in a public function signature, options
object, serialized payload or schema, native argv, CLI parser, environment
lookup, package script, journal, log, receipt, or recovery state. Test source
may contain those spellings only inside a source-level negative assertion.
There is no compatibility alias.

The earlier eight-path Task 3 allowlist was a maximum, not a requirement to
touch all eight paths. For this reconciliation it is explicitly narrowed to the
seven paths already dirty in the frozen snapshot. `scripts/package.json` is
read-only throughout this migration, even if a new RED would otherwise suggest
a command change; such a need is a STOP requiring another documentary
reconciliation. This narrowing makes the exact seven-path final commit and
clean-worktree gate authoritative.

**Preservation and documentation-import handoff**

Import the documentation-only child of
`32e250525c8d9a56161e35e3ab599e9758cebd26` before changing another test or
production byte. The fetch/cherry-pick may update only normal Git metadata, the
new plan commit, the explicitly persisted frozen contract-test blob, and private
`/tmp` snapshots. It may not normalize or rewrite the seven dirty implementation
paths.

```bash
set -euo pipefail

GIT_REPO=/Users/eduardohenrique/Developer/bodyflow
DIAGNOSTIC_REPO=/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1
MIGRATION_PLAN_PATH=docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md
MIGRATION_PARENT_PLAN_BLOB=060cc50188670fc14d0cc0dcb1907a97ed71abc5

git diff --cached --exit-code
test "$(git branch --show-current)" = "codex/better-ahead-ios-rebrand-v1"
test "$(git rev-parse HEAD)" \
  = "8f4020b0ae27d27c0de1b97d1682f507cd0be57c"
test "$(git rev-parse HEAD^)" \
  = "726bae58042dc4da86b08f3fa52de0f2dccc24a4"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" \
  = "$MIGRATION_PLAN_PATH"
test "$(git rev-parse "HEAD:$MIGRATION_PLAN_PATH")" \
  = "$MIGRATION_PARENT_PLAN_BLOB"
git diff --exit-code -- "$MIGRATION_PLAN_PATH"

EXPECTED_DIRTY_PATHS=$(mktemp /tmp/better-ahead-migration-paths.XXXXXX)
ACTUAL_DIRTY_PATHS=$(mktemp /tmp/better-ahead-migration-paths-actual.XXXXXX)
printf '%s\n' \
  design/brand/better-ahead-brand-assets.json \
  scripts/brand/better-ahead-brand-contract.mjs \
  scripts/brand/better-ahead-brand-contract.test.mjs \
  scripts/brand/capture-better-ahead-environment.mjs \
  scripts/brand/render-better-ahead-brand-assets.mjs \
  scripts/brand/render-better-ahead-brand-review.mjs \
  scripts/brand/run-better-ahead-brand-renderer.sh \
  > "$EXPECTED_DIRTY_PATHS"
git status --porcelain=v1 -uall \
  | sed -n 's/^ M //p' \
  | LC_ALL=C sort > "$ACTUAL_DIRTY_PATHS"
LC_ALL=C sort -o "$EXPECTED_DIRTY_PATHS" "$EXPECTED_DIRTY_PATHS"
cmp "$EXPECTED_DIRTY_PATHS" "$ACTUAL_DIRTY_PATHS"
test "$(git status --porcelain=v1 -uall | shasum -a 256 \
  | awk '{print $1}')" \
  = "2d2881b85e533d247fd7b67cc9cec9a629ec66fa1b83e130d2771ac9eee416b4"
test "$(git diff --binary | shasum -a 256 | awk '{print $1}')" \
  = "52654f8b16bcd531902cbb285a26fc0d026739464bd04e7dc269e72fca8bf411"

assert_sha() {
  expected=$1
  path=$2
  test "$(shasum -a 256 "$path" | awk '{print $1}')" = "$expected"
}
assert_sha 5da5284c219f4b556110944c837c2dcbf0f406aa6327aec821cb72d6bf5cb11b \
  design/brand/better-ahead-brand-assets.json
assert_sha c9438906d4073813e15faec31332174e557888e0460705ddc6ff7bd89a7a99f0 \
  scripts/brand/better-ahead-brand-contract.mjs
assert_sha 61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1 \
  scripts/brand/better-ahead-brand-contract.test.mjs
test "$(git hash-object -w --no-filters \
  scripts/brand/better-ahead-brand-contract.test.mjs)" \
  = "4c6619113829b83494292164696ee9abbd315eaf"
git cat-file -e 4c6619113829b83494292164696ee9abbd315eaf^{blob}
assert_sha 7bc9239e37ad8f219b92f59f5476cd6e58276ca2b095b81c27716edbed8d0435 \
  scripts/brand/capture-better-ahead-environment.mjs
assert_sha 9a5cb0ea098c787bcc80ef0bea30eb28636178211fac07ebfb6c0f29c282220b \
  scripts/brand/render-better-ahead-brand-assets.mjs
assert_sha e3bac5f60c9892ef936cf87585ce74820f8fa24ac6879e5e17cc2211baf05e42 \
  scripts/brand/render-better-ahead-brand-review.mjs
assert_sha 686b89883bd21df8c95c7eb49244b93e81cea8d6094ddf689236ea10c9092dc0 \
  scripts/brand/run-better-ahead-brand-renderer.sh

ORACLE_RED_LOG=/tmp/better-ahead-native-v3-oracle-red-attempt2.log
ORACLE_RED_EXPECTED_SHA=fb79890356f3c9541615736ab185ef61a58e7882f0f76dffe94095b8e289b58d
ORACLE_RED_VERIFIED_SHA=
if test -e "$ORACLE_RED_LOG" || test -L "$ORACLE_RED_LOG"
then
  test -f "$ORACLE_RED_LOG"
  test ! -L "$ORACLE_RED_LOG"
  test "$(shasum -a 256 "$ORACLE_RED_LOG" | awk '{print $1}')" \
    = "$ORACLE_RED_EXPECTED_SHA"
  rg -q '^# tests 43$' "$ORACLE_RED_LOG"
  rg -q '^# pass 10$' "$ORACLE_RED_LOG"
  rg -q '^# fail 33$' "$ORACLE_RED_LOG"
  rg -q '^# skipped 0$' "$ORACLE_RED_LOG"
  ORACLE_RED_VERIFIED_SHA=$ORACLE_RED_EXPECTED_SHA
fi

for absent_path in \
  design/brand/better-ahead/environment.json \
  design/brand/better-ahead/bundles \
  design/brand/better-ahead/exports \
  design/brand/better-ahead/review
do
  test ! -e "$absent_path"
  test ! -L "$absent_path"
done
test -z "$(git ls-files --others --ignored --exclude-standard -- design/brand)"

MIGRATION_STATUS_BEFORE=$(mktemp /tmp/better-ahead-migration-status.XXXXXX)
MIGRATION_DIFF_BEFORE=$(mktemp /tmp/better-ahead-migration-diff.XXXXXX)
MANAGER_STATUS_BEFORE=$(mktemp /tmp/better-ahead-migration-manager.XXXXXX)
DIAGNOSTIC_STATUS_BEFORE=$(mktemp /tmp/better-ahead-migration-diagnostic.XXXXXX)
DIAGNOSTIC_DIFF_BEFORE=$(mktemp /tmp/better-ahead-migration-diagnostic-diff.XXXXXX)
git status --porcelain=v1 -z -uall > "$MIGRATION_STATUS_BEFORE"
git diff --binary > "$MIGRATION_DIFF_BEFORE"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_BEFORE"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_BEFORE"
git -C "$DIAGNOSTIC_REPO" diff --binary > "$DIAGNOSTIC_DIFF_BEFORE"

test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test ! -s "$MANAGER_STATUS_BEFORE"
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
test -z "$(git -C "$DIAGNOSTIC_REPO" ls-files --others --exclude-standard)"
test "$(git -C "$DIAGNOSTIC_REPO" diff --name-only -z \
  | LC_ALL=C tr -cd '\000' | wc -c | tr -d ' ')" = "9"
test "$(shasum -a 256 "$DIAGNOSTIC_STATUS_BEFORE" | awk '{print $1}')" \
  = "4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c"

test -n "${LEGACY_TEST_MIGRATION_DOC_SHA:?set the exact published documentation SHA from the handoff}"
test "${#LEGACY_TEST_MIGRATION_DOC_SHA}" = 40
case "$LEGACY_TEST_MIGRATION_DOC_SHA" in *[!0-9a-f]*) false ;; esac

git fetch origin \
  refs/heads/codex/better-ahead-rebranding-design:refs/remotes/origin/codex/better-ahead-rebranding-design
test "$(git rev-list --parents -n 1 "$LEGACY_TEST_MIGRATION_DOC_SHA" \
  | awk '{print NF}')" = "2"
test "$(git rev-parse "$LEGACY_TEST_MIGRATION_DOC_SHA^")" \
  = "32e250525c8d9a56161e35e3ab599e9758cebd26"
test "$(git rev-parse "$LEGACY_TEST_MIGRATION_DOC_SHA^0")" \
  = "$(git rev-parse origin/codex/better-ahead-rebranding-design)"
test "$(git diff-tree --no-commit-id --name-only -r \
  "$LEGACY_TEST_MIGRATION_DOC_SHA")" = "$MIGRATION_PLAN_PATH"
test "$(git rev-parse \
  "$LEGACY_TEST_MIGRATION_DOC_SHA^:$MIGRATION_PLAN_PATH")" \
  = "$MIGRATION_PARENT_PLAN_BLOB"
test "$(git rev-parse "HEAD:$MIGRATION_PLAN_PATH")" \
  = "$MIGRATION_PARENT_PLAN_BLOB"
git diff --binary "$LEGACY_TEST_MIGRATION_DOC_SHA^" \
  "$LEGACY_TEST_MIGRATION_DOC_SHA" -- "$MIGRATION_PLAN_PATH" \
  | git apply --check

git -c core.hooksPath=/dev/null -c commit.gpgSign=false \
  cherry-pick "$LEGACY_TEST_MIGRATION_DOC_SHA"
test "$(git rev-parse HEAD^)" \
  = "8f4020b0ae27d27c0de1b97d1682f507cd0be57c"
test "$(git diff-tree --no-commit-id --name-only -r HEAD)" \
  = "$MIGRATION_PLAN_PATH"
test "$(git ls-tree HEAD -- "$MIGRATION_PLAN_PATH")" \
  = "$(git ls-tree "$LEGACY_TEST_MIGRATION_DOC_SHA" -- "$MIGRATION_PLAN_PATH")"
git diff --cached --exit-code

MIGRATION_STATUS_AFTER=$(mktemp /tmp/better-ahead-migration-status-after.XXXXXX)
MIGRATION_DIFF_AFTER=$(mktemp /tmp/better-ahead-migration-diff-after.XXXXXX)
MANAGER_STATUS_AFTER=$(mktemp /tmp/better-ahead-migration-manager-after.XXXXXX)
DIAGNOSTIC_STATUS_AFTER=$(mktemp /tmp/better-ahead-migration-diagnostic-after.XXXXXX)
DIAGNOSTIC_DIFF_AFTER=$(mktemp /tmp/better-ahead-migration-diagnostic-diff-after.XXXXXX)
git status --porcelain=v1 -z -uall > "$MIGRATION_STATUS_AFTER"
git diff --binary > "$MIGRATION_DIFF_AFTER"
git -C "$GIT_REPO" status --porcelain=v1 -uall > "$MANAGER_STATUS_AFTER"
git -C "$DIAGNOSTIC_REPO" status --porcelain=v1 -uall \
  > "$DIAGNOSTIC_STATUS_AFTER"
git -C "$DIAGNOSTIC_REPO" diff --binary > "$DIAGNOSTIC_DIFF_AFTER"

cmp "$MIGRATION_STATUS_BEFORE" "$MIGRATION_STATUS_AFTER"
cmp "$MIGRATION_DIFF_BEFORE" "$MIGRATION_DIFF_AFTER"
cmp "$MANAGER_STATUS_BEFORE" "$MANAGER_STATUS_AFTER"
cmp "$DIAGNOSTIC_STATUS_BEFORE" "$DIAGNOSTIC_STATUS_AFTER"
cmp "$DIAGNOSTIC_DIFF_BEFORE" "$DIAGNOSTIC_DIFF_AFTER"
test "$(git -C "$GIT_REPO" rev-parse HEAD)" \
  = "0ce7f20f22b0e66a6de0544d4a46345181f2fccb"
git -C "$GIT_REPO" diff --cached --exit-code
test "$(git -C "$DIAGNOSTIC_REPO" rev-parse HEAD)" \
  = "03df7894e4cdb37db08351aafb6dd20ad4cb4103"
git -C "$DIAGNOSTIC_REPO" diff --cached --exit-code
git cat-file -e 4c6619113829b83494292164696ee9abbd315eaf^{blob}
assert_sha 61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1 \
  scripts/brand/better-ahead-brand-contract.test.mjs
if test -n "$ORACLE_RED_VERIFIED_SHA"
then
  test "$(shasum -a 256 "$ORACLE_RED_LOG" | awk '{print $1}')" \
    = "$ORACLE_RED_VERIFIED_SHA"
fi
for absent_path in \
  design/brand/better-ahead/environment.json \
  design/brand/better-ahead/bundles \
  design/brand/better-ahead/exports \
  design/brand/better-ahead/review
do
  test ! -e "$absent_path"
  test ! -L "$absent_path"
done
test -z "$(git ls-files --others --ignored --exclude-standard -- design/brand)"
```

If any precondition, exact hash, source parent/blob, remote-tip, apply check,
status/diff comparison, external repository check, or absence check fails, stop
without resolving a conflict or changing/staging another path. A mismatch
requires a new read-only inventory or documentary reconciliation; it is not
permission to regenerate the expected bytes.

**Required migration order and gates**

1. Import this documentation authority with the preservation handoff above.
   That handoff verifies the accepted 33-RED/10-pass log byte-for-byte when the
   ephemeral file still exists; otherwise the committed record, persisted
   frozen test blob, and accepted reviews remain the authority. Do not rerun the
   superseded 43-leaf command merely to recreate a deleted `/tmp` file.
2. Modify only the contract test first. Freeze the `83/20/4` and `10/21/2`
   ledgers in literal traceability assertions; migrate the 83 tests through the
   nine current owners; remove the 20 architecture-only blocks; replace the 21
   controlled FCB leaves with the mapped closed cases; extract the two
   independent leaves; replace the four P1 owners with the five fixed unlock
   cases; and remove the duplicate `NM-001` after annotating its retained exact
   equivalent.

   The post-migration naming/count contract is exact:

   - the original 43 `[OA-16-*]`, `[OA-34-*]`, and `[OA-V3-*]` leaves remain
     semantically unchanged;
   - exactly 25 new top-level tests begin `[OA-35-08]` through `[OA-35-20]`,
     one per literal/opcode. Their names also contain every mapped `FCB-nnn`
     and `FP-nnn` trace ID; they are the replacements, not duplicate wrappers.
     Their intentional pre-implementation assertion uses the exact diagnostic
     `EXPECTED_OA35_RED:<LOWERCASE_HEX_OPCODE>:UNIMPLEMENTED_CLOSED_CASE`;
   - exactly 83 top-level tests begin with their `[FP-nnn]` MIGRATE ID;
   - exactly two top-level extracted tests begin `[FCB-002-KEEP]` and
     `[FCB-008-KEEP]`;
   - exactly one top-level `[MIGRATION-LEDGER]` test freezes all 83 migration,
     20 removal, four P1, ten FCB, two KEEP, 32 open, 21 probe, and one
     `NM-001` disposition counts. It validates only the immutable test-side
     declarations, must already pass in characterization RED, and does not
     pretend the production seam is implemented;
   - every one of the 86 migration/KEEP/ledger registrations places
     `[RED-CLASSIFIER:<CLOSED_CLASSIFIER>]` immediately after its leading trace
     ID in the top-level test name. Each registration that is intentionally RED
     gives its failing assertion the literal diagnostic
     `EXPECTED_MIGRATION_RED:<EXACT_TRACE_ID>:<CLOSED_CLASSIFIER>`. The 83 FP
     classifiers are the exact values frozen in the owner table above;
     `FCB-002-KEEP` uses `KEEP_CURRENT_UPDATE_COLLISION`, `FCB-008-KEEP` uses
     `KEEP_CURRENT_PREPAYLOAD_REPLACEMENT`, and `MIGRATION-LEDGER` uses
     `STATIC_LEDGER`. The external TAP checker binds both the test-name
     classifier and any failure marker to that exact closed map. A registration
     that already passes in characterization, including `MIGRATION-LEDGER`,
     emits no marker. A thrown exception or failure before the intentional
     assertion likewise has no marker and therefore fails the RED gate;
   - the four P1 FP owners are asserted inside their five OA-35 tests and are
     not four additional `[FP-*]` registrations. Internal fixed scenario loops
     do not register nested `node:test` leaves.

3. Before production edits, prove the other six dirty files remain
   byte-identical to the imported snapshot. From the repository root, run these
   exact focused commands through Corepack/pnpm 10.33.2 (pnpm sets the scripts
   package working directory):

   ```bash
   set -euo pipefail
   test "$(shasum -a 256 design/brand/better-ahead-brand-assets.json \
     | awk '{print $1}')" \
     = "5da5284c219f4b556110944c837c2dcbf0f406aa6327aec821cb72d6bf5cb11b"
   test "$(shasum -a 256 scripts/brand/better-ahead-brand-contract.mjs \
     | awk '{print $1}')" \
     = "c9438906d4073813e15faec31332174e557888e0460705ddc6ff7bd89a7a99f0"
   test "$(shasum -a 256 scripts/brand/capture-better-ahead-environment.mjs \
     | awk '{print $1}')" \
     = "7bc9239e37ad8f219b92f59f5476cd6e58276ca2b095b81c27716edbed8d0435"
   test "$(shasum -a 256 scripts/brand/render-better-ahead-brand-assets.mjs \
     | awk '{print $1}')" \
     = "9a5cb0ea098c787bcc80ef0bea30eb28636178211fac07ebfb6c0f29c282220b"
   test "$(shasum -a 256 scripts/brand/render-better-ahead-brand-review.mjs \
     | awk '{print $1}')" \
     = "e3bac5f60c9892ef936cf87585ce74820f8fa24ac6879e5e17cc2211baf05e42"
   test "$(shasum -a 256 scripts/brand/run-better-ahead-brand-renderer.sh \
     | awk '{print $1}')" \
     = "686b89883bd21df8c95c7eb49244b93e81cea8d6094ddf689236ea10c9092dc0"

   OA35_RED_LOG=$(mktemp /tmp/better-ahead-oa35-red.XXXXXX)
   set +e
   corepack pnpm@10.33.2 --filter @mpp/scripts exec node --test \
     --test-name-pattern='^\[OA-(16|34|35|V3)-' \
     brand/better-ahead-brand-contract.test.mjs \
     > "$OA35_RED_LOG" 2>&1
   OA35_RED_EXIT=$?
   set -e
   test "$OA35_RED_EXIT" = "1"
   OA35_SUBTESTS=$(rg -c \
     '^# Subtest: \[OA-(16|34|35|V3)-' "$OA35_RED_LOG" || true)
   OA35_PASS=$(rg -c \
     '^ok [0-9]+ - \[OA-(16|34|35|V3)-' "$OA35_RED_LOG" || true)
   OA35_FAIL=$(rg -c \
     '^not ok [0-9]+ - \[OA-(16|34|35|V3)-' "$OA35_RED_LOG" || true)
   test "${OA35_SUBTESTS:-0}" = "68"
   test "${OA35_PASS:-0}" = "10"
   test "${OA35_FAIL:-0}" = "58"
   OA35_EXPECTED_NEW_RED_COUNT=$({ rg -o \
     'EXPECTED_OA35_RED:(08|09|0[a-f]|1[0-9a-f]|20):UNIMPLEMENTED_CLOSED_CASE' \
     "$OA35_RED_LOG" || true; } | LC_ALL=C sort -u | wc -l | tr -d ' ')
   test "$OA35_EXPECTED_NEW_RED_COUNT" = "25"
   ! rg -q \
     '^(ok|not ok) [0-9]+ - \[OA-(16|34|35|V3)-.*# (SKIP|TODO)' \
     "$OA35_RED_LOG"
   rg -q '^# cancelled 0$' "$OA35_RED_LOG"
   rg -q '^# todo 0$' "$OA35_RED_LOG"
   ! rg -q \
     'error: (SyntaxError|ReferenceError|TypeError)|ERR_MODULE_NOT_FOUND' \
     "$OA35_RED_LOG"

   MIGRATION_CHARACTERIZATION_LOG=$(mktemp \
     /tmp/better-ahead-migration-characterization.XXXXXX)
   set +e
   corepack pnpm@10.33.2 --filter @mpp/scripts exec node --test \
     --test-name-pattern='^\[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     brand/better-ahead-brand-contract.test.mjs \
     > "$MIGRATION_CHARACTERIZATION_LOG" 2>&1
   MIGRATION_CHARACTERIZATION_EXIT=$?
   set -e
   case "$MIGRATION_CHARACTERIZATION_EXIT" in 0|1) ;; *) false ;; esac
   MIGRATION_SUBTESTS=$(rg -c \
     '^# Subtest: \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_CHARACTERIZATION_LOG" || true)
   MIGRATION_PASS=$(rg -c \
     '^ok [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_CHARACTERIZATION_LOG" || true)
   MIGRATION_FAIL=$(rg -c \
     '^not ok [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_CHARACTERIZATION_LOG" || true)
   test "${MIGRATION_SUBTESTS:-0}" = "86"
   test $(( ${MIGRATION_PASS:-0} + ${MIGRATION_FAIL:-0} )) = 86
   ! rg -q \
     '^(ok|not ok) [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\].*# (SKIP|TODO)' \
     "$MIGRATION_CHARACTERIZATION_LOG"
   EXPECTED_MIGRATION_RED_COUNT=$({ rg -o \
     'EXPECTED_MIGRATION_RED:(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER):[A-Z0-9_]+' \
     "$MIGRATION_CHARACTERIZATION_LOG" || true; } \
     | LC_ALL=C sort -u | wc -l | tr -d ' ')
   test "$EXPECTED_MIGRATION_RED_COUNT" = "${MIGRATION_FAIL:-0}"
   rg -q '^# cancelled 0$' "$MIGRATION_CHARACTERIZATION_LOG"
   rg -q '^# todo 0$' "$MIGRATION_CHARACTERIZATION_LOG"
   ! rg -q \
     'promoteBetterAheadCandidates.*(?:not a function|undefined|missing export)|TypeError.*promoteBetterAheadCandidates' \
     "$MIGRATION_CHARACTERIZATION_LOG"
   ! rg -q \
     'error: (SyntaxError|ReferenceError|TypeError)|ERR_MODULE_NOT_FOUND' \
     "$MIGRATION_CHARACTERIZATION_LOG"

   TAP_ASSOCIATION_CHECKER='
   const fs = require("node:fs");
   const [file, mode] = process.argv.slice(1);
   const text = fs.readFileSync(file, "utf8");
   const blocks = text.split(/\n(?=# Subtest: )/u);
   const oaName = /^\[OA-(16|34|35|V3)-/u;
   const migrationName =
     /^\[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]/u;
   if (mode !== "oa-red" && mode !== "migration-red") {
     throw new Error("unsupported RED checker mode: " + mode);
   }
   const classifierById = new Map();
   const addClassifiers = (classifier, ids) => {
     for (const id of ids.trim().split(/\s+/u)) {
       if (classifierById.has(id)) {
         throw new Error("duplicate closed classifier ID: " + id);
       }
       classifierById.set(id, classifier);
     }
   };
   addClassifiers("VALIDATION_ADMISSION_SEALING",
     "FP-002 FP-004 FP-005 FP-027 FP-057 FP-070 FP-079 FP-083 FP-098 FP-099");
   addClassifiers("INITIAL_AUTHORITY_WORKSPACE",
     "FP-007 FP-028 FP-046 FP-047 FP-048 FP-049 FP-050 FP-053");
   addClassifiers("ATOMIC_BUNDLE_PUBLICATION",
     "FP-040 FP-041 FP-043 FP-044 FP-045 FP-058 FP-060 FP-063 FP-064 FP-065 FP-074 FP-076 FP-097 FP-102");
   addClassifiers("JOURNAL_RESUME_RECONCILIATION",
     "FP-003 FP-008 FP-009 FP-030 FP-031 FP-032 FP-033 FP-034 FP-037 FP-038 FP-039 FP-042");
   addClassifiers("COMMIT_DURABILITY_PHYSICAL_TRUTH",
     "FP-006 FP-025 FP-061 FP-067");
   addClassifiers("PATH_CONFINEMENT_IDENTITY",
     "FP-020 FP-021 FP-022 FP-023 FP-024 FP-068");
   addClassifiers("CONVERGENCE_IDEMPOTENCY_RUNNER",
     "FP-012 FP-013 FP-019 FP-069 FP-080 FP-081 FP-107");
   addClassifiers("CLEANUP_OWNERSHIP_INTEGRITY",
     "FP-054 FP-055 FP-059 FP-075 FP-078 FP-082 FP-084 FP-085 FP-101 FP-105 FP-106");
   addClassifiers("FINAL_AUTHORITY_REVALIDATION",
     "FP-010 FP-011 FP-072 FP-073 FP-086 FP-087 FP-088 FP-089 FP-090 FP-093 FP-094");
   classifierById.set("FCB-002-KEEP", "KEEP_CURRENT_UPDATE_COLLISION");
   classifierById.set(
     "FCB-008-KEEP", "KEEP_CURRENT_PREPAYLOAD_REPLACEMENT");
   classifierById.set("MIGRATION-LEDGER", "STATIC_LEDGER");
   if (classifierById.size !== 86) {
     throw new Error("closed classifier map size is not 86");
   }
   const oaTraceByOpcode = new Map([
     ["08", ["FCB-005"]],
     ["09", ["FCB-001", "FCB-005"]],
     ["0a", ["FCB-002"]], ["0b", ["FCB-003"]],
     ["0c", ["FCB-003"]], ["0d", ["FCB-010"]],
     ["0e", ["FCB-010"]], ["0f", ["FCB-010"]],
     ["10", ["FCB-010"]], ["11", ["FCB-004"]],
     ["12", ["FCB-010"]], ["13", ["FCB-010"]],
     ["14", ["FCB-010"]], ["15", ["FCB-006"]],
     ["16", ["FCB-008"]], ["17", ["FCB-008"]],
     ["18", ["FCB-008"]], ["19", ["FCB-007"]],
     ["1a", ["FCB-009"]], ["1b", ["FCB-009"]],
     ["1c", ["FP-091"]], ["1d", ["FP-092"]],
     ["1e", ["FP-095"]], ["1f", ["FP-096"]],
     ["20", ["FP-096"]],
   ]);
   if (oaTraceByOpcode.size !== 25) {
     throw new Error("closed OA-35 trace map size is not 25");
   }
   const selected = [];
   for (const block of blocks) {
     const header = block.match(/^# Subtest: (.+)$/mu);
     if (!header) continue;
     const name = header[1];
     if (!(mode.startsWith("oa") ? oaName : migrationName).test(name)) {
       continue;
     }
     const result = block.match(/^(not )?ok [0-9]+ - (.+)$/mu);
     if (!result || result[2] !== name) {
       throw new Error("missing top-level TAP result for " + name);
     }
     if (/# (SKIP|TODO)/u.test(result[2])) {
       throw new Error("matching TAP result was skipped/TODO: " + name);
     }
     selected.push({ name, block, failed: Boolean(result[1]) });
   }
   const requireTrue = (condition, message) => {
     if (!condition) throw new Error(message);
   };
   if (mode === "oa-red") {
     requireTrue(selected.length === 68, "OA named count is not 68");
     const failed = selected.filter((row) => row.failed);
     requireTrue(failed.length === 58, "OA failure count mismatch");
     const oa35 = selected.filter((row) => /^\[OA-35-/u.test(row.name));
     requireTrue(oa35.length === 25, "OA-35 named count is not 25");
     const expectedOpcodes = Array.from(
       { length: 25 },
       (_, index) => (index + 8).toString(16).padStart(2, "0"),
     );
     const observedOpcodes = oa35.map(
       (row) => row.name.match(/^\[OA-35-([0-9a-f]{2})\]/u)?.[1],
     );
     requireTrue(
       new Set(observedOpcodes).size === 25 &&
         expectedOpcodes.every((opcode) => observedOpcodes.includes(opcode)),
       "OA-35 opcode set is not exactly 08..20",
     );
     for (const row of oa35) {
       const opcode = row.name.match(/^\[OA-35-([0-9a-f]{2})\]/u)?.[1];
       requireTrue(Boolean(opcode), "OA-35 opcode missing from " + row.name);
       const observedTraces = [...row.name.matchAll(
         /\[((?:FCB|FP)-[0-9]{3})\]/gu,
       )].map((match) => match[1]);
       const expectedTraces = oaTraceByOpcode.get(opcode);
       const expectedPrefix = `[OA-35-${opcode}] ` +
         expectedTraces.map((trace) => `[${trace}]`).join(" ");
       requireTrue(
         JSON.stringify(observedTraces) ===
           JSON.stringify(expectedTraces) &&
           (row.name === expectedPrefix || row.name.startsWith(expectedPrefix + " ")),
         "OA-35 opcode/trace map mismatch: " + row.name,
       );
       const markers =
         row.block.match(
           /EXPECTED_OA35_RED:(08|09|0[a-f]|1[0-9a-f]|20):UNIMPLEMENTED_CLOSED_CASE/gu,
         ) ?? [];
       requireTrue(row.failed, "OA-35 unexpectedly passed: " + row.name);
       requireTrue(markers.length === 1, "OA-35 marker count: " + row.name);
       requireTrue(
         markers[0] ===
           "EXPECTED_OA35_RED:" + opcode + ":UNIMPLEMENTED_CLOSED_CASE",
         "OA-35 marker/opcode mismatch: " + row.name,
       );
       requireTrue(
         /code: ["\x27]?ERR_ASSERTION["\x27]?/u.test(row.block),
         "OA-35 did not fail by assertion: " + row.name,
       );
     }
     for (const row of failed) {
       requireTrue(
         /code: ["\x27]?ERR_ASSERTION["\x27]?/u.test(row.block),
         "OA failure was not an assertion: " + row.name,
       );
     }
   } else {
     requireTrue(selected.length === 86, "migration named count is not 86");
     const selectedIds = selected.map(
       (row) => row.name.match(/^\[([^\]]+)\]/u)?.[1],
     );
     const selectedIdSet = new Set(selectedIds);
     requireTrue(
       selectedIdSet.size === 86 &&
         [...classifierById.keys()].every((id) => selectedIdSet.has(id)),
       "migration trace-ID set differs from the closed 86-ID map",
     );
     const ledger = selected.find(
       (row) => row.name.startsWith("[MIGRATION-LEDGER]"),
     );
     requireTrue(Boolean(ledger) && !ledger.failed, "migration ledger must pass");
     for (const row of selected) {
       const id = row.name.match(/^\[([^\]]+)\]/u)?.[1];
       requireTrue(Boolean(id), "migration trace ID missing");
       const expectedClassifier = classifierById.get(id);
       requireTrue(Boolean(expectedClassifier), "unmapped migration ID: " + id);
       const classifierSegments = row.name.match(
         /\[RED-CLASSIFIER:[A-Z0-9_]+\]/gu,
       ) ?? [];
       const declaredClassifier = row.name.match(
         /^\[[^\]]+\] \[RED-CLASSIFIER:([A-Z0-9_]+)\](?: |$)/u,
       )?.[1];
       requireTrue(
         classifierSegments.length === 1 &&
           declaredClassifier === expectedClassifier,
         "migration name/classifier mismatch: " + id,
       );
       const markers =
         row.block.match(
           /EXPECTED_MIGRATION_RED:(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER):[A-Z0-9_]+/gu,
         ) ?? [];
       if (row.failed) {
         requireTrue(markers.length === 1, "migration marker count: " + id);
         requireTrue(
           markers[0] ===
             "EXPECTED_MIGRATION_RED:" + id + ":" + expectedClassifier,
           "migration marker/closed-classifier mismatch: " + id,
         );
         requireTrue(
           /code: ["\x27]?ERR_ASSERTION["\x27]?/u.test(row.block),
           "migration failure was not an assertion: " + id,
         );
       } else {
         requireTrue(!row.failed && markers.length === 0, "migration GREEN mismatch");
       }
     }
   }
   console.log(JSON.stringify({
     mode,
     selected: selected.length,
     pass: selected.filter((row) => !row.failed).length,
     fail: selected.filter((row) => row.failed).length,
   }));
   '
   node -e "$TAP_ASSOCIATION_CHECKER" "$OA35_RED_LOG" oa-red
   node -e "$TAP_ASSOCIATION_CHECKER" \
     "$MIGRATION_CHARACTERIZATION_LOG" migration-red
   ```

   The exact OA run is RED only because the original 33 oracle behaviors plus
   the 25 OA-35 behaviors are absent; its ten confinement sentinels still pass.
   The 86 characterization owners may honestly be mixed RED/GREEN against the
   partial implementation, but every failure must reach the current lifecycle
   owner and record its expected invariant reason. Nonmatching tests that Node
   reports as skipped because of `--test-name-pattern` are outside these named
   counts; no matching OA/migration record may be skipped or TODO. A
   missing-export
   `TypeError`, syntax error, wrong count, skipped case, timeout, ambient
   dependency, or changed legacy fixture is not accepted evidence.
4. Implement the complete 32-ID `open` inventory and unchanged 21-ID `probe`
   matrix only in
   `scripts/brand/render-better-ahead-brand-assets.mjs`, while completing the
   test changes in
   `scripts/brand/better-ahead-brand-contract.test.mjs`. Remove the four
   forbidden legacy controls as part of the same GREEN. The other five
   production files retain their frozen dirty bytes. No other new path, helper,
   dependency, export, or production interface is authorized.
5. Run the two exact focused commands again with new private logs. The named OA
   TAP records must be `68 total / 68 pass / 0 fail / 0 matching skip or TODO`.
   The named migration TAP records must be
   `86 total / 86 pass / 0 fail / 0 matching skip or TODO`. Unrelated tests
   filtered by Node may appear only as nonmatching skips and are not included in
   those counts. Every literal
   open/probe ID has a direct positive behavioral test; every FCB and P1 owner is
   traced from the applicable OA-35 name; and all
   unknown/extra/forged/reused/order and descriptor/protocol negatives remain
   GREEN. Re-run the exact SHA checks from Step 3 for the manifest, contract,
   environment capture, review renderer, and shell runner; those five files
   must still match their frozen hashes. Only the contract test and asset
   renderer may have advanced during GREEN.

   ```bash
   set -euo pipefail
   OA35_GREEN_LOG=$(mktemp /tmp/better-ahead-oa35-green.XXXXXX)
   corepack pnpm@10.33.2 --filter @mpp/scripts exec node --test \
     --test-name-pattern='^\[OA-(16|34|35|V3)-' \
     brand/better-ahead-brand-contract.test.mjs \
     > "$OA35_GREEN_LOG" 2>&1
   OA35_GREEN_SUBTESTS=$(rg -c \
     '^# Subtest: \[OA-(16|34|35|V3)-' "$OA35_GREEN_LOG" || true)
   OA35_GREEN_PASS=$(rg -c \
     '^ok [0-9]+ - \[OA-(16|34|35|V3)-' "$OA35_GREEN_LOG" || true)
   OA35_GREEN_FAIL=$(rg -c \
     '^not ok [0-9]+ - \[OA-(16|34|35|V3)-' "$OA35_GREEN_LOG" || true)
   test "${OA35_GREEN_SUBTESTS:-0}" = "68"
   test "${OA35_GREEN_PASS:-0}" = "68"
   test "${OA35_GREEN_FAIL:-0}" = "0"
   ! rg -q \
     '^(ok|not ok) [0-9]+ - \[OA-(16|34|35|V3)-.*# (SKIP|TODO)' \
     "$OA35_GREEN_LOG"
   rg -q '^# cancelled 0$' "$OA35_GREEN_LOG"
   rg -q '^# todo 0$' "$OA35_GREEN_LOG"

   MIGRATION_GREEN_LOG=$(mktemp /tmp/better-ahead-migration-green.XXXXXX)
   corepack pnpm@10.33.2 --filter @mpp/scripts exec node --test \
     --test-name-pattern='^\[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     brand/better-ahead-brand-contract.test.mjs \
     > "$MIGRATION_GREEN_LOG" 2>&1
   MIGRATION_GREEN_SUBTESTS=$(rg -c \
     '^# Subtest: \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_GREEN_LOG" || true)
   MIGRATION_GREEN_PASS=$(rg -c \
     '^ok [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_GREEN_LOG" || true)
   MIGRATION_GREEN_FAIL=$(rg -c \
     '^not ok [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]' \
     "$MIGRATION_GREEN_LOG" || true)
   test "${MIGRATION_GREEN_SUBTESTS:-0}" = "86"
   test "${MIGRATION_GREEN_PASS:-0}" = "86"
   test "${MIGRATION_GREEN_FAIL:-0}" = "0"
   ! rg -q \
     '^(ok|not ok) [0-9]+ - \[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\].*# (SKIP|TODO)' \
     "$MIGRATION_GREEN_LOG"
   rg -q '^# cancelled 0$' "$MIGRATION_GREEN_LOG"
   rg -q '^# todo 0$' "$MIGRATION_GREEN_LOG"

   GREEN_TAP_ASSOCIATION_CHECKER='
   const fs = require("node:fs");
   const [oaFile, migrationFile] = process.argv.slice(1);
   const requireTrue = (condition, message) => {
     if (!condition) throw new Error(message);
   };
   const classifierById = new Map();
   const addClassifiers = (classifier, ids) => {
     for (const id of ids.trim().split(/\s+/u)) {
       requireTrue(!classifierById.has(id), "duplicate classifier ID: " + id);
       classifierById.set(id, classifier);
     }
   };
   addClassifiers("VALIDATION_ADMISSION_SEALING",
     "FP-002 FP-004 FP-005 FP-027 FP-057 FP-070 FP-079 FP-083 FP-098 FP-099");
   addClassifiers("INITIAL_AUTHORITY_WORKSPACE",
     "FP-007 FP-028 FP-046 FP-047 FP-048 FP-049 FP-050 FP-053");
   addClassifiers("ATOMIC_BUNDLE_PUBLICATION",
     "FP-040 FP-041 FP-043 FP-044 FP-045 FP-058 FP-060 FP-063 FP-064 FP-065 FP-074 FP-076 FP-097 FP-102");
   addClassifiers("JOURNAL_RESUME_RECONCILIATION",
     "FP-003 FP-008 FP-009 FP-030 FP-031 FP-032 FP-033 FP-034 FP-037 FP-038 FP-039 FP-042");
   addClassifiers("COMMIT_DURABILITY_PHYSICAL_TRUTH",
     "FP-006 FP-025 FP-061 FP-067");
   addClassifiers("PATH_CONFINEMENT_IDENTITY",
     "FP-020 FP-021 FP-022 FP-023 FP-024 FP-068");
   addClassifiers("CONVERGENCE_IDEMPOTENCY_RUNNER",
     "FP-012 FP-013 FP-019 FP-069 FP-080 FP-081 FP-107");
   addClassifiers("CLEANUP_OWNERSHIP_INTEGRITY",
     "FP-054 FP-055 FP-059 FP-075 FP-078 FP-082 FP-084 FP-085 FP-101 FP-105 FP-106");
   addClassifiers("FINAL_AUTHORITY_REVALIDATION",
     "FP-010 FP-011 FP-072 FP-073 FP-086 FP-087 FP-088 FP-089 FP-090 FP-093 FP-094");
   classifierById.set("FCB-002-KEEP", "KEEP_CURRENT_UPDATE_COLLISION");
   classifierById.set(
     "FCB-008-KEEP", "KEEP_CURRENT_PREPAYLOAD_REPLACEMENT");
   classifierById.set("MIGRATION-LEDGER", "STATIC_LEDGER");
   requireTrue(classifierById.size === 86, "classifier map size is not 86");
   const oaTraceByOpcode = new Map([
     ["08", ["FCB-005"]],
     ["09", ["FCB-001", "FCB-005"]],
     ["0a", ["FCB-002"]], ["0b", ["FCB-003"]],
     ["0c", ["FCB-003"]], ["0d", ["FCB-010"]],
     ["0e", ["FCB-010"]], ["0f", ["FCB-010"]],
     ["10", ["FCB-010"]], ["11", ["FCB-004"]],
     ["12", ["FCB-010"]], ["13", ["FCB-010"]],
     ["14", ["FCB-010"]], ["15", ["FCB-006"]],
     ["16", ["FCB-008"]], ["17", ["FCB-008"]],
     ["18", ["FCB-008"]], ["19", ["FCB-007"]],
     ["1a", ["FCB-009"]], ["1b", ["FCB-009"]],
     ["1c", ["FP-091"]], ["1d", ["FP-092"]],
     ["1e", ["FP-095"]], ["1f", ["FP-096"]],
     ["20", ["FP-096"]],
   ]);
   requireTrue(oaTraceByOpcode.size === 25, "OA-35 trace map size is not 25");
   const select = (file, namePattern) => {
     const blocks = fs.readFileSync(file, "utf8")
       .split(/\n(?=# Subtest: )/u);
     const selected = [];
     for (const block of blocks) {
       const name = block.match(/^# Subtest: (.+)$/mu)?.[1];
       if (!name || !namePattern.test(name)) continue;
       const result = block.match(/^(not )?ok [0-9]+ - (.+)$/mu);
       requireTrue(
         Boolean(result) && result[2] === name,
         "missing top-level GREEN result: " + name,
       );
       requireTrue(!result[1], "GREEN test failed: " + name);
       requireTrue(
         !/# (SKIP|TODO)/u.test(result[2]),
         "GREEN test skipped/TODO: " + name,
       );
       selected.push({ name, block });
     }
     return selected;
   };
   const oa = select(oaFile, /^\[OA-(16|34|35|V3)-/u);
   requireTrue(oa.length === 68, "OA GREEN named count is not 68");
   const oa35 = oa.filter((row) => /^\[OA-35-/u.test(row.name));
   requireTrue(oa35.length === 25, "OA-35 GREEN named count is not 25");
   const expectedOpcodes = Array.from(
     { length: 25 },
     (_, index) => (index + 8).toString(16).padStart(2, "0"),
   );
   const observedOpcodes = oa35.map(
     (row) => row.name.match(/^\[OA-35-([0-9a-f]{2})\]/u)?.[1],
   );
   requireTrue(
     new Set(observedOpcodes).size === 25 &&
       expectedOpcodes.every((opcode) => observedOpcodes.includes(opcode)),
     "OA-35 GREEN opcode set is not exactly 08..20",
   );
   for (const row of oa35) {
     const opcode = row.name.match(/^\[OA-35-([0-9a-f]{2})\]/u)?.[1];
     const observedTraces = [...row.name.matchAll(
       /\[((?:FCB|FP)-[0-9]{3})\]/gu,
     )].map((match) => match[1]);
     const expectedTraces = oaTraceByOpcode.get(opcode);
     const expectedPrefix = `[OA-35-${opcode}] ` +
       expectedTraces.map((trace) => `[${trace}]`).join(" ");
     requireTrue(
       JSON.stringify(observedTraces) ===
         JSON.stringify(expectedTraces) &&
         (row.name === expectedPrefix || row.name.startsWith(expectedPrefix + " ")),
       "OA-35 GREEN opcode/trace mismatch: " + row.name,
     );
     requireTrue(
       !/EXPECTED_OA35_RED:/u.test(row.block),
       "OA-35 RED marker survived GREEN: " + row.name,
     );
   }
   const migration = select(
     migrationFile,
     /^\[(FP-[0-9]{3}|FCB-00(2|8)-KEEP|MIGRATION-LEDGER)\]/u,
   );
   requireTrue(migration.length === 86, "migration GREEN count is not 86");
   const migrationIds = migration.map(
     (row) => row.name.match(/^\[([^\]]+)\]/u)?.[1],
   );
   const migrationIdSet = new Set(migrationIds);
   requireTrue(
     migrationIdSet.size === 86 &&
       [...classifierById.keys()].every((id) => migrationIdSet.has(id)),
     "migration GREEN trace-ID set differs from the closed 86-ID map",
   );
   for (const row of migration) {
     const id = row.name.match(/^\[([^\]]+)\]/u)?.[1];
     const expectedClassifier = classifierById.get(id);
     const classifierSegments = row.name.match(
       /\[RED-CLASSIFIER:[A-Z0-9_]+\]/gu,
     ) ?? [];
     const declaredClassifier = row.name.match(
       /^\[[^\]]+\] \[RED-CLASSIFIER:([A-Z0-9_]+)\](?: |$)/u,
     )?.[1];
     requireTrue(Boolean(expectedClassifier), "unmapped GREEN ID: " + id);
     requireTrue(
       classifierSegments.length === 1 &&
         declaredClassifier === expectedClassifier,
       "GREEN name/classifier mismatch: " + id,
     );
     requireTrue(
       !/EXPECTED_MIGRATION_RED:/u.test(row.block),
       "migration RED marker survived GREEN: " + id,
     );
   }
   console.log(JSON.stringify({
     oa: oa.length,
     oa35: oa35.length,
     migration: migration.length,
   }));
   '
   node -e "$GREEN_TAP_ASSOCIATION_CHECKER" \
     "$OA35_GREEN_LOG" "$MIGRATION_GREEN_LOG"
   ```

   Then run:

   ```bash
   set -euo pipefail
   FULL_CONTRACT_LOG=$(mktemp /tmp/better-ahead-contract-green.XXXXXX)
   corepack pnpm@10.33.2 --filter @mpp/scripts \
     brand:better-ahead:test > "$FULL_CONTRACT_LOG" 2>&1
   rg -q '^# fail 0$' "$FULL_CONTRACT_LOG"
   rg -q '^# cancelled 0$' "$FULL_CONTRACT_LOG"
   rg -q '^# skipped 0$' "$FULL_CONTRACT_LOG"
   rg -q '^# todo 0$' "$FULL_CONTRACT_LOG"
   ! rg -q '^# (fail|cancelled|skipped|todo) [1-9][0-9]*$' \
     "$FULL_CONTRACT_LOG"
   corepack pnpm@10.33.2 --filter @mpp/scripts \
     brand:better-ahead:validate:inputs
   corepack pnpm@10.33.2 --filter @mpp/scripts \
     brand:better-ahead:baseline
   git diff --check
   ```

   The complete unfrozen suite has zero failure, skip, todo, expected failure,
   missing-export error, or filtered zero-test shard.
6. The final ledger must prove exactly 83 migrated owners, 20 removed
   architecture owners, four gap owners covered by five fixed literals, ten FCB
   replacements, two extracted independent leaves, and one `NM-001`
   deduplication. It must also prove zero executable dependency on
   `promoteBetterAheadCandidates` or `createPromotionFixture`, zero production
   occurrence of the four forbidden controls, and the exact renderer export
   surface with `nativeHelperV3TestOracle` as the only test-only exception.
7. Run two independent final reviews. One reviews seam confinement, fixed
   opcodes, native boundary placement, physical postconditions, teardown, and
   absence of production controls. The other reviews all 107 FP and 10 FCB
   dispositions, assertion preservation, and absence of removed-architecture
   resurrection. Both must report no Critical or Important finding before a
   commit.

The sentinel set must include at least `FP-004`, `FP-007`, `FP-024`,
`FP-031`, `FP-061`, `FP-064`, `FP-067`, `FP-069`, `FP-079`, `FP-081`,
`FP-085`, `FP-093`, and `FP-094` plus one successful
`begin -> dispatch -> resume -> finish -> IDLE` control. Before the visual
commit, failure must leave recoverable authority and no partial bundle. After
the visual commit, recovery performs cleanup only and preserves the exact
bundle. At `IDLE`, no lock, update, mirror, transaction directory, or unknown
temporary remains.

No real Docker, environment capture, fingerprint, renderer, Task 4, push, PR,
merge, or deploy may run during this migration gate. After all gates and both
reviews pass, stage exactly the pre-existing seven Task 3 implementation paths
and create one commit:

```bash
set -euo pipefail

git diff --cached --exit-code
EXPECTED_TASK3_COMMIT_PATHS=$(mktemp \
  /tmp/better-ahead-task3-commit-paths.XXXXXX)
ACTUAL_TASK3_COMMIT_PATHS=$(mktemp \
  /tmp/better-ahead-task3-commit-paths-actual.XXXXXX)
trap 'rm -f "$EXPECTED_TASK3_COMMIT_PATHS" \
  "$ACTUAL_TASK3_COMMIT_PATHS"' EXIT
printf '%s\0' \
  design/brand/better-ahead-brand-assets.json \
  scripts/brand/better-ahead-brand-contract.mjs \
  scripts/brand/better-ahead-brand-contract.test.mjs \
  scripts/brand/capture-better-ahead-environment.mjs \
  scripts/brand/render-better-ahead-brand-assets.mjs \
  scripts/brand/render-better-ahead-brand-review.mjs \
  scripts/brand/run-better-ahead-brand-renderer.sh \
  > "$EXPECTED_TASK3_COMMIT_PATHS"

git add \
  design/brand/better-ahead-brand-assets.json \
  scripts/brand/better-ahead-brand-contract.mjs \
  scripts/brand/better-ahead-brand-contract.test.mjs \
  scripts/brand/capture-better-ahead-environment.mjs \
  scripts/brand/render-better-ahead-brand-assets.mjs \
  scripts/brand/render-better-ahead-brand-review.mjs \
  scripts/brand/run-better-ahead-brand-renderer.sh
git diff --cached --name-only -z > "$ACTUAL_TASK3_COMMIT_PATHS"
cmp "$EXPECTED_TASK3_COMMIT_PATHS" "$ACTUAL_TASK3_COMMIT_PATHS"
git diff --cached --check

TASK3_HARDENING_PARENT=$(git rev-parse HEAD)
git -c core.hooksPath=/dev/null -c commit.gpgSign=false commit \
  -m "fix(brand): harden Better Ahead atomic asset transaction"
test "$(git rev-parse HEAD^)" = "$TASK3_HARDENING_PARENT"
test "$(git show -s --format=%s HEAD)" \
  = "fix(brand): harden Better Ahead atomic asset transaction"
git diff-tree --no-commit-id --name-only -z -r HEAD \
  > "$ACTUAL_TASK3_COMMIT_PATHS"
cmp "$EXPECTED_TASK3_COMMIT_PATHS" "$ACTUAL_TASK3_COMMIT_PATHS"
git diff --cached --exit-code
test -z "$(git status --porcelain=v1 -uall)"
```

The executable block proves the commit contains exactly those seven paths and
the worktree/staging are clean. Only then continue at Step 6. This
reconciliation authorizes no environment or generated-output commit by itself.

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
canonical Buildx child environment: physically attested `HOME`, fixed Docker
Desktop/system-only `PATH`, `LANG=C`, `LC_ALL=C`, and literal
`TMPDIR=/private/tmp` after physical root-owner/sticky-directory validation
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
commit and is not fabricated in `environment.json`. `begin` records only the
exact initially absent stdout-capture/stderr-log paths. The native helper's
durable pre-build transition later binds their identities; its durable
post-build transition records the actual validated IID, child status, capture
size/hash, and stderr-log size/hash as per-run transaction evidence. After the
one visual container succeeds, the same IID is copied into receipt/log evidence.
The actual IID and volatile capture metadata are excluded from committed
`environment.json` and fingerprint-equality checks.

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
node scripts/brand/capture-better-ahead-environment.mjs \
  --assert-docker-user-config "$DOCKER_USER_CONFIG"
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
candidate must resolve back to the exact bundled binary. Docker CLI `proxies`
must be absent or an empty object because Docker otherwise pre-populates proxy
build arguments from that configuration; the capture and the journaled
immediate pre-build attestation repeat this check without logging proxy values.
The checker reads an existing config only as an anchored, owner-matching,
single-link regular file and treats only `ENOENT` as absent; a symlink, malformed
JSON, non-regular file, hardlink, replacement, unreadable state, or non-empty
`proxies`/`cliPluginsExtraDirs` is blocking. All ambient variables
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
codes. The internal `--assert-docker-user-config EXACT_PATH` operation used by
that attestation traverses from the physically attested home dirfd, opens
`.docker` and then `config.json` descriptor-relatively with no-follow semantics,
validates owner/type/device/link count, reads and parses from that same FD, and
accepts only `ENOENT` for the optional file; it emits only the verdict and never
configuration values. They record the evidence. The renderer's exact build argv is
`docker --context desktop-linux buildx build --builder default --platform=linux/amd64 --quiet --file Dockerfile .`,
executed from the anchored journal-bound
`<TRANSACTION_PATH>/snapshot/scripts/brand/canonical-renderer` cwd. The embedded
native helper executes it directly and drains anonymous stdout/stderr pipes into
the two already opened, journal-bound descriptors; Buildx receives no output
pathname. The
renderer runs the strictly parsed IID with literal
`--platform=linux/amd64 --network none`; the build itself retains the network
access required by the pinned canonical Dockerfile. `--iidfile`,
`--metadata-file`, every pathname/stdout exporter, `/dev/fd`/`/proc/self/fd`
handoff, and shell pathname redirection remain forbidden. Never call
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
snapshot, IID stdout capture, Buildx stderr diagnostic log, render logs,
candidates, staged bundle, final bundle if present, and every recorded hash,
then stop. Do not
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
