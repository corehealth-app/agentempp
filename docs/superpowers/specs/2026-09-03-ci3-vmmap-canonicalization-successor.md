# CI-3 Mac Node Capsule V3 vmmap residency specification

## Identity and lineage

- tool: `MAC_RELOCATABLE_NODE_CAPSULE_V3`;
- generation: `capsule-v3`;
- namespace: `mac-node-capsule-v3`;
- authority parent: `c1c83a63b9f258546310eccba30b889958ccabe5`;
- predecessor generation: `capsule-v2`;
- predecessor state: `FAILED_PARTIAL_PRESERVED`, `1/1_CONSUMED`, retry/cleanup/adoption false.

## Probe algorithm

1. Copy the immutable capsule into a new logical probe location.
2. Resolve and retain its physical root before spawning.
3. Execute Node and set cwd from that retained physical root.
4. While the loader child is alive, parse only structural vmmap `__TEXT` image records.
5. Ignore recognized system/shared-cache images; resolve every non-system image by `realpath`.
6. Reject logical-root drift from the retained pre-spawn physical root.
7. Compute `path.relative(physicalProbeRoot, physicalImagePath)` and treat the image as internal only when the result is non-absolute, is not `..`, and does not begin with `../`.
8. Count only exact relocation-plan destinations as consumed. Reject any other internal non-system image.
9. Hash and report any canonical non-system image outside the capsule as external; mark an exact canonical source-graph image as source-root use.
10. Require all copied non-system destinations in every probe set and publish manifest/receipt last.

Text-wide substring residency and textual `/var` rewriting are forbidden. Any parse, realpath, schema, ambiguity, escape, external-image, source-image, or completeness failure is terminal for the one V3 attempt.
