# Performe AI Client Beta with Flow — Local Baseline Evidence

**Observed:** 2026-09-14, America/Sao_Paulo
**Evidence status:** baseline complete; implementation pending

## Host and isolation

- Host: `MacBook-Air-de-Eduardo.local`, Darwin 25.6 arm64, user `eduardohenrique`.
- Classification: `LOCAL_DEVELOPMENT`; no evidence that this filesystem is a production runtime.
- New worktree: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch/starting HEAD: `codex/performe-ai-client-beta-flow-v1` / `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Starting tree: `9999e4868d332235d7d71b051dd173b6b332d9e3`; dirty/staging: zero.
- Docker context: `colima`; no container/service was started for this task.
- Resource gate: PASS for serial local tests/builds (104 GiB free disk; CPU idle; swap pressured, so heavy work is serial).

## CI-3 preservation

- Frozen path/branch/HEAD: `/Users/eduardohenrique/Developer/bodyflow-ci3-provider-console-attestation-v2`, `codex/ci3-provider-console-attestation-v2`, `b4c09e80190fd6ce5c5f59b5193f8a6621554854`.
- Parent/tree/subject match the mandate: `32b108c43877923b76c7102b81bca56737be6d2c`, `2c81b8a426e9d263696bd1bcdaa5c4b09c623541`, `docs(ops): separate local toolchain observation from iOS build attestation`.
- Staging empty; exactly nine tracked unstaged paths. Each current SHA-256 appears in `.superpowers/sdd/2026-09-14-ci3-local-toolchain-observation-separation/progress.md`, including controller test `2f6d97b2…`; the other eight remain ledger-matched.
- No Git lock or active CI-3 executor was observed. One generic Desktop Commander Node service held read-only descriptors; it was not stopped.
- Files/index/tests/processes changed by this task: NO. Classification: `CI3_EVIDENCE_WORKTREE_FROZEN`.

## Authority and base decision

- Documentary dossier: committed object at `b4c09e…:docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`, SHA-256 `f0dc6dcd0e9136d4a0a275e94d4cc877ab504316a6d94030fbe6dbacc1c1486c`.
- Rebrand authority: committed `docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md` and `docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md`, updated by the current Performe AI/Flow mandate.
- Product base: exact dossier-authorized CI-2 SHA `277873…`, carrying real auth/session/Mobile transport. CI-3 operational documentation is deliberately not used as the implementation base.
- Ancestry verified locally from the approved iOS scaffold through naming-neutral CI-0, auth/Keychain CI-1, and session/Mobile transport CI-2. No fetch/pull/cherry-pick/merge/copy integration occurred.

## Tools

- Git 2.50.1; Node 22.23.2; Corepack 0.34.6; pnpm 10.33.2 from the existing Corepack cache; Xcode 26.6 (17F113); Swift 6.3.3.
- Dependencies installed with `COREPACK_ENABLE_NETWORK=0 corepack pnpm install --offline --frozen-lockfile`: 501 packages reused, zero downloaded.
- Supabase CLI executable is unavailable because the cached package's install script was not run; no global install or silent substitute is used. The selected design requires no schema migration in this checkpoint.
- Simulator: iPhone 17 Pro, iOS 26.5, UUID `27291590-659D-4A29-8F45-CA5CA2D154F9`.

## Component inventory

| Component | Baseline classification | Evidence |
|---|---|---|
| Supabase auth remote client | REAL_NOT_WIRED | Real REST contract/tests exist; app root supplies no runtime config. |
| Keychain/session lifecycle | REAL_AND_INTEGRATED internally | Store, refresh single-flight, request leases, logout/user switch and stale-response guards pass focused tests. |
| Mobile BFF auth/transport | REAL_AND_INTEGRATED server-side; REAL_NOT_WIRED client config | Bearer/bootstrap/entitlement/typed envelope/idempotency routes and secure iOS transport exist. |
| Flow agent pipeline | REAL_AND_INTEGRATED for WhatsApp | Official context/tools exist; no trusted authenticated-mobile entry yet. |
| Mobile chat BFF/persistence | MISSING | No `/api/mobile/v1/flow/chat`; `messages` can be reused with a provider scope. |
| Native iOS chat | MISSING | No chat models/repository/view; five-tab navigation exists. |
| Public textual brand | HISTORICAL | Better Ahead public text remains; internal BodyFlow names/assets are intentionally preserved. |
| External Supabase/BFF/LLM integration | BLOCKED_BY_DECISION | Staging/provider calls and credentials are outside this session. |

## Baseline commands and results

- `corepack pnpm --filter @mpp/admin exec vitest run src/lib/mobile-api src/app/api/mobile/v1`: PASS, 35 files / 309 tests.
- `corepack pnpm --filter @mpp/agent exec vitest run src/pipeline-context.test.ts src/pipeline-core-reads.test.ts src/prompt-rules.test.ts src/tools-profile-write-safety.test.ts src/tools-user-data.test.ts src/fake-write-detector.test.ts src/numeric-validator.test.ts`: PASS, 7 files / 113 tests.
- Focused `xcodebuild test` on auth/session/config/transport/dependency suites for iPhone 17 Pro: `TEST SUCCEEDED`.
- Pre-existing warnings: one unused test helper result and App Intents metadata skip for a target without the framework dependency. No baseline failure.

## Documentary reviews

- Review 1, architecture/security: Critical 0; Important 0. Verified trusted auth identity, channel isolation, read-only mobile tools, Release fail-closed configuration, server-only service role, and no remote migration.
- Review 2, requirement coverage/executability: Critical 0; Important 0. The review initially identified missing literal RED/GREEN commands; those were added before the gate was rerun. The final gate maps Tasks 0–12, exact paths/interfaces/commands, acceptance, and external stops.
- Implementation may proceed inline under the mandate. Providers remain simulated until a separate staging gate.

## Baseline statuses

- `AUTH_RUNTIME_INTEGRATION_NOT_VERIFIED`
- `DEPLOYMENT REQUIRED: NO`
- `PRODUCTION STATUS: NOT DEPLOYED`
- `IOS INTEGRATION STATUS: PARTIAL`
- `REBRAND STATUS: PARTIAL`
- `COST / ENVIRONMENT CLOSEOUT: NOT APPLICABLE`
