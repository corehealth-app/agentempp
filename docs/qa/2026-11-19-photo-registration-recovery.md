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

## Connected photo follow-up: plain water

The real gallery photo test recognized the French bread and explained the next
blocked item correctly: a glass of plain water. The verified catalogue contained
USDA FDC 174158 (`Water, bottled, generic`) but no Portuguese plain-water alias.
The follow-up migration copies that exact verified row into the single `água`
alias. Its zero values are upstream facts, not a fallback for unknown foods.
The official USDA API was independently checked on 19 November 2026.

The regression first failed with no alias. After migration, exact 0.9 search,
provenance, no duplicate alias on repeat, preservation of all existing catalogue
rows, and exclusion of coconut water/unknown drinks pass in a rolled-back local
transaction. The migration refuses conflicting aliases or altered upstream facts.
No application code or provider configuration changes in this follow-up.
Existing photo interpretation and original refusal remain immutable; continue
through the linked reply rather than resubmitting the photo.

## Connected historical compatibility

The connected name reply exposed two additional read boundaries: the native v3
journal had accepted only quantity/meal-type replies, and the old server's unified
page could enumerate name threads unsupported by its meal reader. A captured
synthetic public page now reproduces the native failure. The decoder accepts only
the bounded, read-only name-observation text; arbitrary/media/private reply bodies
remain rejected. Fifty-four focused native tests pass, including cold-history
composition and negative packets.

The additive `read_conversation_journal_page_v4` RPC preserves the closed public
v3 page schema and qualified media validators. New servers select v4. The old
v3 RPC filters unsupported name threads before pagination, including their intake
root, while retaining supported old history. The migration fingerprints its exact
predecessor and preserves immutable observations and effects. An actual staging
dry run verifies both reader generations against the same synthetic QA photo;
the full synthetic SQL regression also passes and rolls back.

Connected QA has observed one saved breakfast from the gallery photo, all six
feedback sections, matching nutrition values after cold reopen, and an exact
technical replay returning the same receipt. Distribution and final runtime
closeout remain separate release gates.

## Cross-country incident applicability

A final metadata-only check found that the original incident account has country
US. The original strict alias was scoped to BR, while search intentionally treats
country as a tie-breaker. A regression reproduces the missing exact Portuguese
name at similarity 0.9 for US. An additive catalogue alias `pão francês` copies
only official verified TACO4:53, refusing conflicts or changed upstream facts.
The rollback dry run verifies exact BR/US lookup, qualifiers remain distinct,
repeat creates no duplicate, and all 8,541 pre-task catalogue rows remain exact.
No user country, old meal, runtime code, app binary or provider configuration is
changed. The Release archive and BFF remain source 1ca2ef99; this follow-up commit
contains only the database migration, regressions and this documentation.
