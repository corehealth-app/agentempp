# Photo registration recovery — 19 November 2026

## Change

Ordinary Brazilian “pão francês” is qualified against the existing exact
catalogue wording “Pão, trigo, francês”. This is a reviewed whole-name alias;
unknown prose still cannot pass a reduced fuzzy threshold. The original visual
quantity, source positions and confidence remain unchanged.

An unqualified whole name can receive one item-bound `food_name` question through
the existing immutable clarification chain. A reply changes only that item's
name. Other items, quantities, the original observation and sealed refusal remain
unchanged. Interpretation is not rerun. A technical replay keeps the original
reply UUID and body, with one fulfillment at most.

The iOS live result and historical message explain a refused registration in
Portuguese/English without exposing raw internal error codes. The reply form
preserves its exact authored answer during storage/network uncertainty.

## Versioned read compatibility

The new backend reads `read_conversation_meal_journal_page_v3`. It retains the
closed page DTO and existing receipt formats, extending only the item-name
question/answer variants. The v2 reader remains available to existing servers.
It keeps original unsupported-name refusals readable without an unknown question
kind. Once a thread contains the new name continuation, v2 filters that thread
**before pagination**; its complete history is available through v3. Supported
older threads and their receipts are retained. The historical v3 journal renders
name corrections as existing plain-text observations for its older readers.

The guarded migration patches current function bodies rather than replacing them
with an older local copy. It preserves the shared meal/workout admission counter,
UUID type fence, ownership, closed-day and epoch protections. It adds two
backend-only read functions; it changes no table, RLS policy or user records.
Staging project: `xitugspwfxkcluxvrdeg`. Protected legacy project:
`xuxehkhdvjivitduarvb`. Do not use a broad database push or migration-history repair.
After named replies exist, preserve the additive schema on application rollback.

## Verification before distribution

- Root tests: all seven packages pass; BFF build and exact source/compiled graph
  checks pass. Full typecheck passes. Changed-file lint passes. Repository-wide
  lint has pre-existing diagnostics in unchanged packages; no broad formatting
  or suppression is included.
- Native: 44 focused tests pass, including real name-field binding, immutable
  intent, network-unknown locking and localized historical explanation.
- SQL: name/source preservation, wrong-item rejection, replay/conflict, no
  premature meal/XP, and actual legacy/current pagination are covered. Existing
  continuation, writer, guard, original-source, service-role and thread suites pass.
- Hosted migration: exact dry run passed and rolled back; 11 function definitions,
  backend-only privileges and 935 neighboring functions were verified unchanged.
- Connected photo QA and TestFlight: **pending at this source checkpoint**.
  Distribution requires photo → upload → actual worker/AI → calculation → saved
  receipt → nutrition/history → cold reopen, plus no duplicated retry effect.

The broader full-product goal remains paused; this change concerns the reported
photo incident. This source checkpoint is not a claim of complete product validation.
