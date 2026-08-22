# CI-0 old-worktree residue drift STOP

**Source:** `USER-SUPPLIED MAC CI-0 PRE-FETCH RESIDUE DRIFT REPORT`
**Classification:** `PHYSICALLY_INCOMPLETE_WORKTREE`
**Subclassificação:** `VOLATILE_RESIDUE_DRIFT`
**Date recorded:** 2026-08-22

This evidence records a read-only observation made by the Mac session. The VPS
did not repeat any measurement, fetch, build, test, signing, renderer, Docker,
pnpm, staging, or commit operation described by that report.

## Reported environment and STOP boundary

The Mac reported macOS 26.5.2 (25F84), Xcode 26.6 (17F113), and Swift 6.3.3 at
2026-08-22T09:52:22-0300. The STOP occurred in the pre-fetch Phase 1, before
remote inspection, fetch, reading the new documentation commit, unsigned
builds, scans, review, final tests, staging, or commit. None of those actions
was performed by that attempt.

## Preserved Git evidence reported by Mac

The Git manager remained clean at `0ce7f20f22b0e66a6de0544d4a46345181f2fccb`
(parent `a31449f7254d0697652866e192363c303dd9978e`), with empty staging and
empty porcelain/binary-diff SHA-256 values. The diagnostic repository remained
at `03df7894e4cdb37db08351aafb6dd20ad4cb4103` (parent
`5f5e9a485847291acbae3ae7de23b27824d49343`), with nine tracked modifications,
no untracked files, empty staging, porcelain SHA-256
`4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c`, and
binary-diff SHA-256
`90a36577ad148e5391c147e72c4566716fe97adf02e02ddc53b7be594681bde8`.
The nine physical hashes matched their authority.

The orphan `worktree1` metadata remained present at
`ad9869c0d6b11222263ea40c7b72e329092aeef5` (parent
`8f4020b0ae27d27c0de1b97d1682f507cd0be57c`). Its empty staging, index SHA-256
`2e4cef4ed2f2bfe7e7e4cb2825001401ff80ef1252227f07f13ae36fcd545dd0`, index
size 184050 bytes, mtime, and ctime were reported unchanged. It was not
repaired, removed, pruned, reattached, or otherwise altered.

## Old worktree observation

The old path remains `PHYSICALLY_INCOMPLETE_WORKTREE`: `.git` is absent; it has
zero regular files; its orphan index lists 1420 tracked paths; zero tracked
paths are physically present; and all 1420 remain physically absent. The prior
audit observed 5270 directories excluding root. The new read-only observation,
confirmed twice with `find -P ... -mindepth 1 -type d | wc -l`, observed 987
directories and 2057 symlinks: a difference of -4283 directories.

No cause or author was determined. The Mac did not investigate removal, create
directories, restore files, execute cleanup/repair, or modify the path. The
CI-0 durable worktree was confirmed to exist, but its detailed baseline was
not completed after this mandatory STOP; its staging was not touched and no
CI-0 commit was created. The prior CI-0 baseline remains the 2026-08-21
signing-gate evidence.

## Decision

`VOLATILE_RESIDUE_DRIFT` records drift in untracked physical residue. It means
the prior physical residue is no longer byte/path-identical, but it does not
recover or newly lose tracked content: all 1420 tracked paths were already
absent and remain absent. It does not change orphan HEAD, parent, index, or
staging; does not make the old worktree operational; and does not block the
separate durable CI-0 worktree.

Directory count, empty-directory count, symlink count, residue pathname or
symlink-target hashes, timestamps, and `node_modules` cardinality are forensic
observations only, not CI-0 equality gates. The old path's existence continues
to be checked. If it is completely absent later, record that fact; do not
recreate it automatically.

The material STOP gates remain: authorized manager/diagnostic state; presence
of `worktree1`; orphan HEAD, parent, index SHA-256, index size and empty staged
diff; absent `.git`; zero regular files; zero physically present orphan-index
paths; no repair, reattachment, reuse, or overwrite of the old worktree; a
valid clean CI-0 worktree with its authorized baseline, paths, and staging; and
no asset, naming, or production change.

There is no authorization to recreate 4283 directories, copy `node_modules`,
install dependencies, use a backup, touch orphan metadata, create `.git`,
approximate missing blobs, resume the rebrand, or run the renderer. This STOP
ends the reported attempt; it does not conclude CI-0.
