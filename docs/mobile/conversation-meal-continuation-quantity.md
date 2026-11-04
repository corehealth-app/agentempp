# Linked explicit quantity conversion

`resolveConversationMealQuantityAnswer(input, question)` is a pure boundary for
an explicit typed answer to an already qualified quantity question. It captures
detached closed copies, validates the exact question revision/key/kind, food
occurrence and allowed unit, and requires quantity kind. A matching meal-type
answer/question is not a quantity answer.

Its seven immutable facts are `food_index`, literal `food_name`, original
`amount`, original `unit`, canonical `quantity_g`, `quantity_basis` and nullable
`quantity_display`. It creates no question/owner/registration token, calorie or
macro value. Inputs and their opaque tokens remain unchanged.

Explicit grams stay unchanged. Explicit kilograms use `amount * 1000`, without
reference rounding. Both have `quantity_basis: stated` and null display metadata.
Reference units use only the actual whole-name `mobileQuantityDisplay` result
already verified by the question parser. Their conversion uses one final
`Math.round(amount * factor * 1e6) / 1e6`, in that exact operation order:

| Unit | Approved factor |
| --- | --- |
| mL | Reference grams per mL |
| L | `1000 * reference.grams_per_unit` for an approved liquid |
| unit / scoop | The matching approved portion's grams per unit |
| caneca | `200 * reference.grams_per_unit`, whole-milk reference only |

Reference results have `quantity_basis: portion_reference` and the exact approved
estimated display metadata. No generic liquid density, scoop size, brand,
mixture or powdered-food reference is introduced. An unknown food can still
carry an explicit mass; it cannot borrow an unsupported reference unit.

Final grams must be finite, positive and at most 9,999. Rounded-zero reference
answers and converted values above the bound are refused, without a zero
fallback. Explicit mass preserves representable small values: `1e-7` g stays
`1e-7` g; `1e-7` kg uses the actual IEEE-754 product
`0.00009999999999999999`. Reference conversion instead follows the existing
six-decimal rounding discipline. Real SQL differential qualification, including
subnormal float conversion, remains a separate integration gate.

These facts are not a preparation or registration proof. The caller must first
prove the original positive semantic result, immutable captured source and exact
originally missing food occurrence. It must separately bind fresh authorized
calculation context and actual materialized input indexes. This module changes
no model/source bytes, food interpretation, materializer, Auth state, SQL,
routes, rewards, daily totals or feature activation.
