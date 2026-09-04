# CI-3 vmmap canonicalization successor dossier

This dossier authorizes one successor of `c1c83a63b9f258546310eccba30b889958ccabe5` with subject `build(ops): canonicalize vmmap residency for CI-3 capsule`.

The consumed Capsule V2 remains immutable and unadopted: one attempt, two claims, one executable, nineteen dylibs, twenty signed Mach-O files, ninety-three dependency edges, four probe directories, and no final manifest or receipt. No V2 path is a V3 input or output.

The successor is `MAC_RELOCATABLE_NODE_CAPSULE_V3`, generation `capsule-v3`, under the independent `mac-node-capsule-v3` namespace. Its one physical creation budget begins at zero and may be consumed only after publication and a fresh local Gate 0.

The vmmap boundary parses `__TEXT` image records structurally, resolves the logical probe root and each non-system image with `realpath`, checks containment with `path.relative`, and records only exact relocation-plan destinations. Parse, canonicalization, root drift, internal-unplanned images, external non-system images, source-graph images, and copied-but-unloaded images fail closed.

The downstream binding remains receipt-hash and authority based. Only the topology readers that interpret capsule schema, purpose, generation, or source namespace change from V2 to V3; controller, launcher, and terminal consumers retain their existing digest-bound interfaces.

No fetch, SSH, network, simulator, remote read, service-role transfer, provider/database/production mutation, remote bundle mutation, CI-3 edit, cleanup, CI-4, PR, merge, deploy, TestFlight, or App Store action is authorized by this dossier.
