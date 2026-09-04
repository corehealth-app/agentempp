# CI-3 readiness-race V4 authority evidence

## Diagnostic classification

- class: `B — READINESS_RACE`
- expected mappings: 19
- missing before readiness: 19 in each preserved loader-probe observation
- missing after readiness: 0 in all four consecutive vmmap observations
- mandatory mappings: 19, complete
- weak/lazy mappings: 0
- external non-system images: 0
- source-root dependencies: 0
- duplicate physical images: 0
- vmmap and independent telemetry agreement: yes
- expected/mandatory/consumed set SHA-256: `f10d09f0e35d0b04668ac8e6d1d611960cb81bf72eba1544e8439c6c6b2d5949`
- empty missing-set SHA-256: `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`
- loaded module-set count: 7
- loaded module-set SHA-256: `f792cfae25ee77777a698fd5920cdfa3b4f3e30e9179178646224a2e96606b4f`
- sanitized diagnostic-capture SHA-256: `381a9b73c139c3dae8826b993dbab36869c1f223ca031e92b2afebdf910915e2`

## Mach-O command evidence

The 93 records were classified from `otool -l`: 74 `LC_LOAD_DYLIB`, 19 `LC_ID_DYLIB`, and zero `LC_REEXPORT_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, or `LC_LAZY_LOAD_DYLIB`. The load-command set SHA-256 values are `aa4544f5e50f2a12d0ed32ef422b4dd9a86520f8304d61d8a7606fec15c44241` for `LC_LOAD_DYLIB` and `47c9895d457a6d07e1448cc219c0f6782b8f1b1f4dce909ad660b8fef8fdb20f` for `LC_ID_DYLIB`.

## Remediation evidence contract

- a real single-byte handshake precedes every productive vmmap observation;
- two consecutive vmmap observations per loader probe must be stable;
- separate DYLD telemetry must agree with the stable vmmap set;
- mandatory and weak/lazy classifications come from structured `otool -l` parsing;
- the complete copied set must be consumed even when a command is weak or lazy;
- external non-system, source-root, copied-but-unused, missing mandatory, unstable, and source-disagreement cases remain rejected;
- V4 authority, generation, namespace, root, claim, staging, result, and receipt are independent of V2 and V3;
- V2 and V3 retry, cleanup, adoption, promotion, rename, and physical reuse remain prohibited.

Publication requires more than 2142 tests with zero failures, skips, todos, or expected failures; constructor 53/53; consumers 5/5; syntax and Swift compile gates; and reviews A/B with zero Critical and Important findings. Runtime evidence is valid only after exact Git materialization, a new Gate 0, and the one allowed V4 creation attempt.
