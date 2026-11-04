# Private source-to-registration composition

`registerPersistedConversationMeal` connects the actual command journal, current
clinical day initializer, captured SQL source, durable semantic attempt,
whole-name materializer, shared calculator and atomic SQL meal writer. It is
not mounted on an HTTP route and does not activate the new Flow UI.

The real writer's recovery read runs first. A committed effect only reads the
original feedback; a prepared result commits its stored hash without another
model, catalog or daily operation. New commands are admitted before initializing
the day, then capture one original source. An already captured source skips day
initialization. Loss of a prepare or commit response grants a bounded read of
the existing preparation/effect, never another calculation, interpretation or
writer attempt within that call. Durable SQL state governs subsequent calls.

Only a sourced positive interpretation, complete materialized occurrences,
resolved shared nutrition and all actual history hit/MISS receipts can prepare
the resolved command. Literal and expanded source positions are checked before
the writer's closed payload. Unknown/partial nutrition and indispensable
quantities remain unresolved. No unknown item becomes zero and no manual kcal
is required. Optional original enrichment failure cannot undo or repeat a saved
meal. The result retains the actual server journal binding for subsequent
current-policy presentation.

The calculator uses only the opted-in consumed-food preparation policy and its
actual annotations, captured history reader and in-memory audit sink. It keeps
raw item precision and official rounded totals separate; SQL stores physical
facts. Display references convert milk mass to mL and whey to editable scoops.
The existing approved prepared-dish fallback is reused only for its recognized
whole phrases. This composition does not execute the legacy agent or generator.

An explicitly selected meal type always wins, even at another time of day.
Otherwise the existing positive current-text detector can supply the type.
Without either, the private result is `meal_type_required`: automatic personal
routine classification needs its actual owned, frozen meal-window history;
the nutrition history reader cannot supply it. No empty personal window is
fabricated as authority for a clock fallback. This is an activation gate for
the free-form chat, not a claim that the complete approved UX is delivered.

Nutrition-label metadata currently requires an explicit confirmation boundary;
it is neither silently applied as consent nor ignored in favor of generic food.
Clarification/resubmission, full timeline, current item editing, five-minute
versioned undo and native encrypted-outbox transport remain separate work.

`historicalFeedback` is private immutable historical enrichment, not an HTTP
response DTO. Before any public use, `readHistorical` on the current-policy
presentation service must obtain stable owned PRE/POST clinical state using the
actual `serverBinding`. Its wrapper labels historical day/block values and
masks restricted targets, percentages, budget and education. A successful meal
effect does not authorize exposing a stale raw v1/v2 feedback payload.

Unit tests cover nominal save, explicit breakfast, no-type clarification,
source/occurrence binding, hit/MISS evidence, unresolved nutrition, replay,
lost prepare/commit outcomes, callback detachment and nonfatal enrichment.
Unit tests alone are not SDK/PG, real-provider, authenticated native, staging,
TestFlight or Roberto acceptance evidence. No cloud environment is created by
these source changes. All contractual areas in the consolidated plan remain
active until separately qualified and delivered.
