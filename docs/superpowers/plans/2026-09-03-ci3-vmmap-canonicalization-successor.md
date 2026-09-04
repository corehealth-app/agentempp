# CI-3 vmmap canonicalization successor execution plan

1. Preserve and inventory Capsule V2 read-only without enumerating sensitive paths or identifiers.
2. Establish the published 2119-test and focused capsule baselines.
3. Add and observe REDs for canonical aliases, structural containment, negative residency cases, fail-closed parser/realpath behavior, duplicate images, and V3 independence.
4. Implement the smallest V3 source change and the two topology-reader binding changes; keep the remaining three consumers digest-bound.
5. Re-run focused tests, native local vmmap parser characterization, constructor 53/53, five consumer suites, Swift and shell compilation, and the full authority suite with zero failures, skips, todos, or expected failures.
6. Perform security/correctness Review A and preservation/lineage Review B; remediate findings locally until both have zero Critical and Important findings.
7. Stage only explicit allowlisted paths, commit once with the required parent and subject, push once without force, and read back commit metadata and manifest without fetch.
8. Materialize exact Git blobs, run the fresh Gate 0, confirm V3 root and claim absence, create the owner-only V3 context, and consume exactly one V3 creation attempt.
9. Require the complete signed closure, dependency graph, two move probes, two loader probes, all copied non-system images consumed, zero external/source-root dependency, final manifest/receipt, and physical readback.
10. On PASS, prepare only the OOB human gate and stop at `HUMAN_GATE_READY`; on failure, preserve everything and stop at `STOP_DOCUMENTED` without retry or cleanup.
