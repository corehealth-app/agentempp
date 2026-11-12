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

1. Freeze the original attachment, caption, optional meal hint and identifiers.
2. Upload under the original authenticated media owner and purpose.
3. Mark the asset retained before attempting the encrypted neutral enqueue.
4. Process the same asset only after that durable enqueue returns.
5. Submit the same neutral input and request media-provenance negotiation.

Within the current capture, an upload retry keeps its original create key
and caption. A queued media message can resume processing after reopening without
the local uploaded file. Processing first reads the asset; an already processed
or processing asset does not request another model attempt. Uncertain dispatched
intakes retain the controller's existing GET-first reconciliation and replay
fences. Neither logout nor an uncertain enqueue licenses remote blob deletion.

Legacy meal messages continue through their original controller. Neutral media
never creates a fake typed meal command to reach upload or processing.

## Release qualification

The pre-enqueue picker/upload preparation still uses memory and temporary files;
its cold-restart durability is not established by the queued-message tests.
Qualify or complete that lifecycle before claiming full WhatsApp-style delivery.

Native controlled HTTP, encrypted-store, rendering, isolation and interruption
tests are local evidence. Actual camera/gallery/recording, worker processing and
retention cleanup, connected factual feedback, cold edits/undo/panel agreement,
performance, TestFlight and installed-version acceptance remain separate gates.
The existing generic retention worker selects expired ordinary media and excludes
recurring clinical photos; its deployed schedule must also be verified.

This source change does not update distributed build 17, provider flags, workers,
credentials or TestFlight. Keep the approved full plan and all 20 delivery areas
active until their own acceptance evidence exists.
