# CI-3 loaded-image proof V4 implementation plan

1. Preserve and inventory the consumed V2/V3 states, the five CI-3 paths, the empty index, and the bound remote bundle.
2. Diagnose both preserved V3 loader probes read-only with a real readiness pipe, two vmmap observations, independent DYLD telemetry, and `otool -l` command classification.
3. Classify exactly one cause and continue only for A, B, or C.
4. Add RED tests for actual-format parsing, readiness order, stable observations, source reconciliation, command classes, negative residency cases, and independent V4 lineage/root/claim.
5. Implement the minimum V4 loader-proof protocol and update only consumers that interpret capsule schema, lineage, generation, or source namespace.
6. Run the focused tests, constructor 53/53, all five consumer gates, the full authority suite, syntax/compile checks, and two independent reviews.
7. Stage only the reviewed paths, create one commit with the required parent and subject, and push once without force.
8. Materialize the exact published Git authority, rerun the full suite and Gate 0, and prove the V4 root and claim are absent.
9. Consume the V4 physical budget exactly once, verify the final manifest/receipt and physical readback, and preserve all artifacts regardless of outcome.
10. On V4 PASS, prepare only the OOB human gate and stop at `HUMAN_GATE_READY`.
