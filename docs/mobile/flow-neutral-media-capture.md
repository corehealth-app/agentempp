# Native Flow attachments

The scoped conversational composer reuses the existing camera, photo library,
audio recorder and audio importer. Selecting bytes does not register consumption
or exercise. Send creates a neutral original input; only the server's matched
factual receipt can produce a saved card or refresh official totals.

## Purpose and compatibility

`conversation_photo` remains distinct from legacy `meal_photo` and clinical
`body_checkin_photo`. The same JPEG normalizer strips private metadata and limits
pixels and bytes. The default meal stager and legacy draft precheck retain their
old behavior. Legacy upload/processing cannot borrow a neutral-purpose photo.
Audio retains `audio_note`, its measured duration and existing file limits.

The picker presentation captures the original account/session/epoch identity.
Late results are refused after scope invalidation, and only their owned local
file is removed. Civil-day, closed-day and clinical decisions remain authoritative
server checks; the client does not infer those decisions from its local clock.

Temporary foreground revalidation is distinct from changing account/session/epoch.
The capture sheet retains local ownership while authority is suspended. Permission
results and prepared bytes wait for the original scope to become current before
camera presentation or attachment acceptance. Terminal invalidation and explicit
closure still discard owned pending bytes and recordings. The retained identity
is presentation metadata and cannot authorize upload or registration.

Foreground refresh requests during a neutral operation coalesce until it settles;
the root then revalidates the same account and restores queue controls. Lifecycle
invalidation remains immediate, including while an upload is suspended.

## Original-send lifecycle

1. Freeze and encrypt the original attachment bytes, caption, optional meal hint,
   purpose, duration, patient/epoch and identifiers before any remote creation.
2. Upload under the original authenticated media owner and purpose.
3. Mark the asset retained before attempting the encrypted neutral enqueue.
4. Process the same asset only after that durable enqueue returns.
5. Submit the same neutral input and request media-provenance negotiation.

The local original uses one bounded authenticated capsule per Auth account beside
the existing v1–v5 encrypted outbox. Both share the private process lock, add-only
device-only Keychain key and 50-entry capacity; promotion counts the original
once. The capsule has a separate encryption domain, stores no path/bearer/local
session generation, and is excluded from backup and protected while locked.
Missing keys do not license creating replacements when only a capsule exists.

Bind the actual upload asset before enqueue. Enqueue the exact input first, then
replace the capsule's bytes/caption with a retirement marker before processing or
dispatch. A cold read reconciles that exact matching queue row instead of creating
another input. Queued processing rechecks retirement, including an uncertain
directory sync. Legacy queued media without a capsule remains compatible.

A cancelled original receives its durable cancellation marker before queue
removal. A crash between those writes cannot revive the send; unrelated originals
are preserved. This is cancellation of unsent local work, not Undo of consumption.

Cold recovery restores protected temporary bytes and the same capture/intake IDs.
Missing or changed temporary bytes during a live retry are restored from the
immutable encrypted original. Owned-path and symlink checks still apply; canonical
filesystem paths are compared without relying on Foundation's directory URL hints
for missing files. No original bytes or captions remain in a retirement marker.

The same Auth account/patient/epoch can recover under a legitimate new local
lease. A changed patient/epoch or unavailable capture capability holds the
original with its caption hidden, retry disabled and explicit unsent discard.
Disabling capture does not silently hide an existing protected original.

Within the current capture, an upload retry keeps its original create key
and caption. A queued media message can resume processing after reopening without
the local uploaded file. Processing first reads the asset; an already processed
or processing asset does not request another model attempt. Uncertain dispatched
intakes retain the controller's existing GET-first reconciliation and replay
fences. Neither logout nor an uncertain enqueue licenses remote blob deletion.

Legacy meal messages continue through their original controller. Neutral media
never creates a fake typed meal command to reach upload or processing.

## Release qualification

Selection before Send remains temporary; only the frozen Send original is made
durable. Native cold/live-interruption, actual encrypted-file and queue tests are
local evidence, not proof of provider processing or physical-device acceptance.
Complete connected/date/fuso, large-file performance, protected-file lifecycle
and release gates before claiming full WhatsApp-style delivery. Account-deletion
qualification must also include owned encrypted originals and keys; ordinary
sign-out preserves protected pending work, as it already does for the outbox.

Native controlled HTTP, encrypted-store, rendering, isolation and interruption
tests are local evidence. Actual camera/gallery/recording, worker processing and
retention cleanup, connected factual feedback, cold edits/undo/panel agreement,
performance, TestFlight and installed-version acceptance remain separate gates.
The existing generic retention worker selects expired ordinary media and excludes
recurring clinical photos; its deployed schedule must also be verified.

This source change does not update distributed build 17, provider flags, workers,
credentials or TestFlight. Keep the approved full plan and all 20 delivery areas
active until their own acceptance evidence exists.
