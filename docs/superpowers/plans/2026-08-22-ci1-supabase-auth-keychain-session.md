# CI-1 execution plan — isolated Supabase authentication

Base `b9a51bc1a641895ef5323cb1085b3b5622bbb277`; branch
`codex/ci1-supabase-auth-session-v1`; worktree
`/Users/eduardohenrique/Developer/bodyflow-ci1-supabase-auth-session-v1`; final
commit `feat(ios): add isolated Supabase authentication session`.

Task 0 proves published authority, CI-0 base, manager/diagnostic/orphan/old
worktree preservation, absent branch/path and clean new worktree. Task 1 adds
only `Auth` exact 2.54.1 and its resolved revision, never product Supabase.
Task 2 TDDs injected configuration. Task 3 TDDs discarding SDK storage,
short-lived adapter and safe fetch/no-refresh proof. Task 4 TDDs versioned
Keychain record. Task 5 TDDs actor session ownership/hydration/bearer. Task 6
TDDs existing authentication operations. Task 7 TDDs AppDependencies wiring.
Task 8 runs CI-1, CI-0, Authentication, Storage and dependency tests, unsigned
Debug/Release builds, scans, two reviews, selective commit and one non-force
push without upstream.

Each task requires expected RED, minimal implementation and focused GREEN; no
unapproved skipped case or assertion reduction. The final allowlist must enumerate exact
files after Task 0; it may only name necessary Auth/Storage/test files,
`AppDependencies.swift`, `project.pbxproj` and `Package.resolved`, never a
wildcard, asset, strings, plist, renderer, backend or documentation.

Use only the established unsigned build overrides and simulator destination
`platform=iOS Simulator,name=iPhone 17 Pro`. Review A covers SDK/Auth/Keychain;
Review B covers actor/session/concurrency. Stop for package/API mismatch,
refresh, persistent SDK storage, double authority, forbidden naming, secret,
real URL/key, Release mock, failed build/test or Critical/Important finding.
