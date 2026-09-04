# CI-3 loaded-image proof V4 successor dossier

This dossier authorizes one successor of `85a9ebba88722915df56583d29defc253016a5f9` with subject `build(ops): reconcile loaded image proof for CI-3 capsule`.

Capsules V2 and V3 remain immutable, unadopted, and unpromoted with their one-attempt budgets consumed. V3 retains two claims, one executable, nineteen dylibs, twenty signed Mach-O files, ninety-three preserved edge records, four probe directories, and no final manifest or receipt. Diagnostic classification identified seventy-four load dependencies and nineteen identity commands without mutating that state. No V2 or V3 claim, generation, root, staging area, result, or receipt is a V4 input or output.

The read-only V3 diagnosis classified the failure as `B — READINESS_RACE`. Before the readiness byte, both observed processes lacked all nineteen planned images. After the readiness byte, two consecutive vmmap observations per loader probe and an independent DYLD telemetry observation all contained the complete nineteen-image plan. The mandatory set was complete, the weak/lazy set was empty, and no external non-system image or source-root dependency was observed.

The successor is `MAC_RELOCATABLE_NODE_CAPSULE_V4`, generation `capsule-v4`, under the independent `mac-node-capsule-v4` namespace. Its one physical creation budget begins at zero and may be consumed only after publication and a fresh local Gate 0.

The productive loader proof now loads the controller/constructor module set, emits one fixed readiness byte through an anonymous pipe, and only then permits two consecutive vmmap observations. A separate process supplies `DYLD_PRINT_LIBRARIES=1` telemetry. All loaded paths and the probe root are canonicalized, containment is structural, mandatory and weak/lazy commands are classified from `otool -l`, and vmmap must agree with the independent source. Missing mandatory images, copied-but-unused images, external images, source-root images, unstable observations, and source disagreement fail closed.

No fetch, SSH, network, simulator, remote read, service-role transfer, provider/database/production mutation, remote bundle mutation, CI-3 edit, cleanup, CI-4, PR, merge, deploy, TestFlight, or App Store action is authorized by this dossier.
