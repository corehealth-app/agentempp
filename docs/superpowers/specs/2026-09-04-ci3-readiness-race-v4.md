# CI-3 loaded-image proof V4 specification

## Goal

Replace spawn-time loaded-image observation with a bounded, evidence-backed readiness protocol while preserving the requirement that every copied non-system image is actually loaded.

## Required behavior

1. Load the fixed controller/constructor module set in the relocated executable.
2. Emit exactly one fixed readiness byte on an anonymous pipe after module loading succeeds.
3. After readiness, obtain two consecutive structured vmmap observations for each loader probe.
4. Obtain a separate loaded-image observation with `DYLD_PRINT_LIBRARIES=1` and no loader-path, fallback-path, framework-path, preload, or injection variable.
5. Canonicalize the probe root and every non-system image with `realpath`, then use `path.relative` containment.
6. Classify dependency commands from `otool -l` into mandatory, weak/lazy, identity, and explicitly rejected classes.
7. Require complete mandatory residency, stable vmmap sets, independent-source agreement, the full copied set consumed, zero external non-system images, and zero source-root dependencies.
8. Publish schema 4 artifacts only in a new `capsule-v4` authority namespace with an independent physical 0/1 budget and explicit failed V3 predecessor lineage.

## Fail-closed cases

Timeout, early exit, malformed readiness, malformed image record, canonicalization failure, probe-root drift, unstable observations, independent-source mismatch, missing mandatory image, copied-but-unused image, external image, source-root dependency, ambiguous relocation, and V2/V3 lineage or namespace reuse all stop before downstream effects.

## Preserved boundaries

The remote bundle, constructor contract, five consumers, CI-3 worktree, service-role boundary, providers, database, production, V2, and V3 remain unchanged. Publication does not authorize SSH, simulator, remote reads, CI-4, cleanup, PR, merge, deployment, TestFlight, or App Store operations.
