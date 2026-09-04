# CI-3 vmmap canonicalization successor authority evidence

## Root cause

The Capsule V2 loader probes compared vmmap text against a logical temp-directory path. macOS reported the same loaded images under the physical canonical path, causing `COPIED_IMAGE_NOT_CONSUMED` even though the closure had loaded.

## Remediation evidence contract

- tests precede production changes and retain their observed RED output privately;
- `/var` and `/private/var` aliases converge only through injected or native `realpath`;
- paths containing spaces remain intact;
- sibling-prefix and same-basename collisions stay external;
- aliases resolving inside the capsule are accepted structurally;
- copied-but-unloaded, external non-system, and source-root images remain rejected;
- malformed image records, non-system realpath failure, and logical-root drift fail closed;
- duplicate loaded images are deduplicated by canonical physical identity;
- system shared-cache image paths do not require filesystem realpath;
- V3 authority, generation, root, claim, staging, result, and receipt are independent of V2.

Publication requires the preserved predecessor suite plus the new tests, constructor 53/53, all five consumer suites, syntax/compile gates, diff and safety scans, and two independent reviews with zero Critical and Important findings. Runtime evidence is valid only after exact Git-blob materialization, a new Gate 0, and the single V3 creation attempt.
