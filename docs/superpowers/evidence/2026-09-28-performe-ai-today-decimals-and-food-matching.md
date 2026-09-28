# Performe AI — Today with fractional meal energy and food matching (2026-09-28)

Operation `FIX_TODAY_DECIMALS_AND_FOOD_MATCHING_WITH_SECURE_CLOSEOUT_V1`.
Baseline: `b7c46f4534922204d5631f79b5874a3d73cfa815` (tree `87f0d66f…`), clean.
Source incidents: staging device gate of 2026-09-27 (QA account A, physical
iPhone, Preview `dpl_FzuyWMEvgpZzxseQc4UYwNQFM2My`, backend `b7c46f45`).

Performe AI = public product; Flow = public agent; BodyFlow = preserved
internal technical identity.

## Incident 1 — Today fails with a fractional meal energy

Exact scenario. The patient confirmed one dinner with three items. The
confirmed `meal_logs` rows (ids sanitized in the fixtures):

| food_name | quantity_g | kcal | source |
|---|---:|---:|---|
| Arroz branco | 150 | 200 | user_kcal |
| Feijão carioca | 86.5 | 284.6 | canonical_fuzzy |
| Frango grelhado | 120 | 191 | canonical_exact |

`GET /api/mobile/v1/today` answered 200 (request ids
`79926-1790556586092-…`, `lmlpv-1790563332092-…`). The app kept a stale cache
with "As informações podem estar desatualizadas" and, on a clean login,
showed "Não foi possível carregar". Decoding the same number in Swift fails with
`DecodingError.dataCorrupted … "Number 284.6 is not representable in Swift."`

Layer and cause. Server: `meal_logs.kcal` is `numeric(7,2)` nullable; the
contract `DailyStateMeal` (`packages/core/src/daily-state.ts`) declares `kcal`,
`quantity_g` and macros as `number | null` and `meal_type` as `string | null`;
the daily state passes the row value through unchanged (new characterization
test). Client: `TodayMeal` declared `kcal: Int` and the other fields
non-optional, while `HistoryMealLogRow` already used `Decimal?`. The Today test
fixture only ever used integer meal energy (`407`), the History fixture used
`407.25`. `let kcal: Int` exists in `TodayMeal` since `6fa8b2c` (2026-07-30);
when a fractional value first reached it is not known.

Fix (at the boundary that violated the contract, iOS only): `TodayMeal` and
`TodayMealDescriptor` use `Decimal?`/`String?` like History; the meal row shows
`TodayValueFormatter.mealKcal` — pt-BR "284,6 kcal", en "284.6 kcal", never
rounded, `nil` as "Indisponível"/"Not available", never "0 kcal". Official day
totals (integers) are untouched; nothing is recalculated on the device.

RED → GREEN. `TodayContractTests` "device gate meals with a fractional official
energy decode" failed on the old model with the exact device error; after the
fix it passes, plus: nil stays nil and zero stays zero, malformed energy
(`"284,6"`, `"abc"`, `true`) is rejected, and `TodayPresentationTests` checks the
pt-BR/en text.

## Incident 2 — wrong food for "Arroz branco" and "Feijão carioca"

Exact scenario. Items sent by the app: `Arroz branco` 150 g, `Feijão carioca`
86.5 g, `Frango grelhado` 120 g. Proposal (pending `f836d0b3…`):
`Arroz branco` → food_db 673 "Bolinho de arroz" 410.3 kcal; `Feijão carioca` →
704 "Feijão, carioca, cru" 284.6 kcal; `Frango grelhado` → 7 191 kcal.

Candidate windows (staging `search_food_trgm(term, 0.2, 20, 'BR')`, copied
verbatim into the golden fixture): "arroz branco" → 673 Bolinho de arroz
0.3043, 306 Repolho branco cru 0.28, 669 Arroz carreteiro 0.2609, 161 Arroz
tipo 1 cru 0.25 … 160 Arroz tipo 1 cozido 0.2222; "feijão carioca" → 704 cru
0.8333, 703 cozido 0.7143.

Causes (shared pipeline `calcMealMacros`, also used by WhatsApp):
1. The short-query threshold is 0.30; the anchor check only requires "arroz"
   to appear somewhere in the candidate, so "Bolinho **de** arroz" passed.
2. The request states no preparation, so no preparation filter applies and the
   shorter name ("cru", 329.03 kcal/100 g) wins the trigram over "cozido"
   (76.42). Nothing in the pipeline treated this as ambiguous.

Catalog evidence (TACO BR): 97 foods appear in ≥2 preparation states; energy
ratio <1.25 in 22, 1.25–1.5 in 33, 1.5–2 in 18, ≥2 in 24.

Product decision (Eduardo, 2026-09-28): without a stated preparation, ask when
the energy of the same food changes by 50% or more between preparations; do
not ask below that (cenoura, brócolis, peito de frango).

Fix (`packages/agent/src/meal-pipeline.ts`, no constant or formula changed):
- "X de Y" is food X: a candidate whose head is another food and that only
  cites the request in the complement is dropped, unless the patient named X or
  X is a part/cut of Y (peito, coxa, filé, lombo…).
- Preparation ambiguity: same food (name without preparation words) in ≥2
  states whose mean energy differs ≥1.5× → no food is chosen: the item comes
  back with `kcal` 0, `nutrition_source` `no_match` and a warning asking the
  preparation. Checked before patient history (QA A's wrong 284.6 log would be
  reused otherwise) and applied to composite parts.
- Once the patient states the preparation: "Feijão carioca cozido" 86.5 g →
  703, 66.1 kcal; "Arroz branco cozido" 150 g → 160, 192.4 kcal (TACO).

RED → GREEN. `__golden__/audit-09-27-device-gate.test.ts` (6 tests) and 3 new
unit tests failed on the old pipeline (Bolinho 673; silent raw; history reuse;
Farinha de mandioca; Pão de queijo; raw composite part) and pass now. The first
draft also rejected "peito de frango" for "frango grelhado"; two existing tests
caught it and the part/cut exception was added — no existing assertion changed.

Not fixed (pre-existing, recorded): "Peito de frango" without skin → the skin
filter removes the "peito" rows and the "frango frito" alias (219 kcal/100 g)
wins.

## Adversarial review (isolated subagent, same model family — not a human review)

The reviewer rebuilt the verified catalog from the migrations (TACO 581, USDA
7,793, aliases 12), emulated `search_food_trgm` (it reproduces the three
staging incident windows exactly) and compared the old and new pipelines on
499 catalog-derived names. Findings on the first draft and what was done:

- CRITICAL — ambiguity leaked across foods: any window row whose name
  contained the anchor counted, and the widest group won ("Manteiga" asked
  because of "Couve, manteiga"; "Chá preto" because of "Feijão, preto";
  "Farinha de mandioca" because of "Mandioca"). 73 questions, 22 of them for
  foods whose own spread is under 50%. Fixed: only the requested food itself
  counts — same head noun (a part such as "peito" defers to the next noun) and
  the same variety words, qualifiers dropped only when nothing matches
  ("branco" in "arroz branco"). Re-scan: 49 questions, 0 outside the rule; 2
  names changed food, both away from a wrong dish ("Carne" no longer "Pastel,
  de carne"; "Soja" no longer "Pão, de soja").
- HIGH — a composite with one ambiguous part gave that part's grams to the
  others ("Frango grelhado com batata doce" 300 g counted as 300 g of chicken).
  Fixed: the whole item asks for the preparation.
- HIGH — irregular plural: "Pães de queijo" lost "Pão, de queijo". Fixed
  (`-ães`/`-ões` → `-ão`).
- Also: labels now list the states of the requested food only; per-state mean
  energy (not min/max over rows) so BR × US rows of one state never count.
- New tests lock each of these with the exact staging windows; both new golden
  tests fail on the first draft and pass now.

Not fixed here — recorded as pending with evidence:
- HIGH: the mobile confirm accepts an item with `kcal` 0 from the question
  (the app shows the warning but does not block), and the WhatsApp button
  proposal does not show `user_warnings`; `registra_refeicao` persists the 0
  item (pre-existing path, now reached by more foods). Blocking or rewording
  needs a contract/flow decision.
- HIGH: same class as incident 1 — `TodayWorkout` fields are non-optional in
  iOS although the contract allows null (a WhatsApp workout without intensity
  would break Today), and `remaining_food_kcal`/`food_excess_kcal`/
  `daily_balance_kcal` are `Int` in iOS while the server sends null without a
  calorie target.
- MEDIUM: the 50% rule is relative only (abobrinha 15–24 kcal/100 g asks);
  confirm whether an absolute floor is wanted. The rule needs ≥2 labelled
  preparations in the window: "Macarrão" and "Grão de bico" still take the raw
  row silently; USDA (English) names never ask.
- Pre-existing wrong matches seen in the scan (unchanged by this fix): "Café
  preto" → "Feijão, preto, cru" (323.6 kcal/100 g); "Leite" → "Leite, de coco";
  "Ovo" → generic dish estimate; "Coxa de frango"/"Peito de frango" → skin
  filter removes the cut rows.

## Gates (this tree, before commit)

- `@mpp/agent` 1110/1110 (1096 + 14 new), `@mpp/admin` 697/697,
  `@mpp/mobile-bff` 26/26, `pnpm typecheck` exit 0 (after the review fixes).
- iOS unit full: 34 XCTest + 1333 Swift Testing (110 suites) = 1367/0.
- iOS UI focused (Today/Registration): 54/0.
- Remaining gates and device results: see the sections appended below.
