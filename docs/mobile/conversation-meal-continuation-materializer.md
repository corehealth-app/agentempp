# Linked missing-quantity materializer

`materializeConversationMealContinuation(db, command, originalCapture,
originalInterpretation, options, { resolutionSource, quantityAnswers })` is a
private additive entry point. `options` retains `confidenceThreshold`;
`quantityAnswers` is a closed, detached array of at most 30 exact
`{ replyId, input, question }` objects. It reuses the qualified reply/question
parser and quantity converter. Duplicate reply IDs or food occurrence indexes,
unknown fields, getters, non-JSON data and meal-type answers are refused.

The existing `materializeConversationMealInterpretation` signature and behavior
remain available through the same private core with no overlay. The six original
rules (`literal`, `mobile_household`, `milk_whey_cup`, `milk_whey_total`,
`prepared_dish`, `visual`) retain their names and behavior.

Original interpretation qualification always uses the original command and
capture. No child command, provider identity, model call, rewritten source text,
ref, source position, model metadata or interpretation hash is substituted.
Before any query/await, both captures must match the original command/owner,
input, epoch, source units, source evidence and pinned media. Both source readers
must retain their respective actual owner and capture clock. Original/fresh day
dates must be valid civil dates, equal and open; timezone, confirmed country and
nullable locale must agree. Catalog/clinical changes in fresh context are not
treated as changes to original semantic evidence. Personal-correction resolution
uses the fresh capture clock, while original semantics keep their old clock.

Every answer must name the exact original food occurrence with null original
quantity/unit refs. Existing whole-food qualification and candidate generation
run first. An answer can supply quantity only to exactly one candidate whose
actual quantity is still null. It cannot overwrite an explicit quantity, a
resolved visual mass, an expanded recipe or an ambiguous compact association.
Visual quantity completion also requires the original whole-name and confidence
guards. Quantity basis, approved display metadata and review hints come from the
qualified answer; the original rule/source positions remain unchanged.

The closed frozen return is `{ materialization, quantity_witnesses }`. Each
witness has the exact private contract fields: `reply_id`, `food_index`, original
`amount`/`unit`, `quantity_g`, `quantity_basis`, `quantity_display` and
`input_indexes`. All supplied answers must actually be applied. A complete
materialization maps each witness to the real one-input source group; an actual
clarification carries an empty index array, never a fabricated partial slot.
For example, answering rice while beans still lack quantity yields the original
`missing_quantity` clarification for beans and `[]` for the rice witness; after
both answers the mappings are the real `[0]` and `[1]`.

Other existing clarification reasons remain explicit. A supplied answer that
cannot be applied is a refusal, rather than a witness claiming application.
This first slice accepts only quantity overlays, not a meal-type override.

This source-bound result is not admission, live clinical authority, a sealed
preparation, registration proof or permission to write. The real orchestrator
must independently prove the durable positive parent/decision and answer chain,
bind fresh authorized calculation context/readers, and let SQL enforce current
epoch, source, catalog, media, day and winner guards. No SQL, routes, feature
activation, rewards or deployment are introduced here.
