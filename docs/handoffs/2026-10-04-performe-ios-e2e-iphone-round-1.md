# Performe AI iOS — E2E on the iPhone, round 1 (2026-10-04)

Performe AI is the public product, Flow the public agent; BodyFlow is the
preserved internal technical identity.

- Device: iPhone 13 Pro Max over iPhone Mirroring. Build `b92fb28`, staging
  (Supabase `xitugspwfxkcluxvrdeg`, Vercel Preview). Production not touched.
- Account: QA A (already signed in; no password typed by the agent).
- Window: 09:00–09:35 BRT. LLM spend: US$ 0.194 (6 Flow turns) plus the meal
  extractor calls, which are not in `messages`.
- Evidence (screenshots and running ledger, outside the repo):
  `~/.local/share/performe-ai/final-polish-20261001/e2e-20261004/`.
- Visual acceptance: Eduardo, 2026-10-04, on the iPhone with `b92fb28`:
  "agora ficou bom, pode iniciar os testes".

## Result by journey (plan §9 of the v2 proposal)

| # | Journey | Result |
|---|---|---|
| 1 | Sign-up + onboarding | NOT RUN — needs Eduardo to type the password and open the confirmation e-mail |
| 2 | Today, day zero → first record | PASS |
| 3 | Meal by text | PASS for the flow; FAIL for one value (F1). Photo and audio NOT RUN (no camera/microphone over mirroring; photo needs a picture chosen by Eduardo) |
| 4 | Workout | PASS, including rule nº 1 (exercise never frees food) |
| 5 | Hydration, weight | PASS. Routine and reminders NOT RUN on this account |
| 6 | Flow | Day summary PASS; workout suggestion PASS with reservations; diet/menu suggestion FAIL (F14). Retry and cancel NOT RUN |
| 7 | Plan: draft → review → confirmed | PASS. Import NOT RUN |
| 8 | Progress + charts | Food chart PASS; weight chart FAIL (F18); streak/XP FAIL (F19) |
| 9 | Library | BLOCKED — no published content on staging |
| 10 | Performance | Partial: timings below. Cold start, memory and Instruments NOT RUN |
| 11 | Token cost | Measured (below) |
| 12 | Food and exercise base | Food FAIL: 3 of 11 everyday items right (F23, F24). Exercise PASS |
| 13 | Accessibility on the device | NOT RUN (needs system settings changed on the phone) |

## Findings

HIGH
- **F23 — the everyday-food aliases are out of the search.** `search_food_trgm`
  keeps only `food_db.is_verified IS TRUE`; all 149 `source='alias'` rows (ovo
  cozido, ovo frito, café preto, azeite de oliva, pizza, granola, tilápia…) are
  `is_verified=false` on staging. "ovo" matches nothing, "azeite" matches
  nothing, "leite integral" matches "Canjica, com leite integral" (224.9 kcal
  for 200 ml instead of about 120). Production state not checked.
- **F24/F1 — the fallback invents macros.** With no match, `estimateMacros`
  falls to `prato_genérico` (150 kcal, P 7, C 18, F 5 per 100 g,
  `packages/agent/src/meal-pipeline.ts:622`): "ovo mexido 100 g" was saved with
  18 g of carbohydrate and 7 g of protein; "azeite 13 g" came as 19.5 kcal
  instead of about 115. Stored as `llm_estimate` with confidence 1.00, shown as
  "Valores fornecidos pelo serviço".
- **F14 — Flow cannot produce a menu.** "Problema técnico aqui" after 42.7 s
  and US$ 0.041. Preview logs: `[diet-generator] zod_validation_failed`
  (numbers returned as strings in `daily_meals.0.items.0.*`), then
  `protein_drift_exceeded` (200 g vs target 144.9 g). Same blocker as 09-30.
- **F18 — today's weight is not in the weight chart.** 80.5 kg registered at
  09:09 shows under "Medidas" but the chart still ends at 80.0 kg (3 Oct): the
  series comes from `reevaluations`, `POST /weight` only updates the profile.

MEDIUM
- F8 — dark mode: the buttons of the workout, hydration and weight sheets
  (UIKit-bridged) keep white text on the light teal; the meal sheet is right.
  Regression of the A/B palette (`1b2c4c3`).
- F19 — streak 0, 0 XP, level 1, "Atualizado em 27/09" after 12 days of
  records: the daily closer never runs on staging.
- F13 — the ready-made question "Sugira um jantar para fechar o dia" is
  deflected in the morning ("São 9h da manhã ainda…").
- F15 — asked for a one-off chest and triceps workout; got a full-body plan
  (squat, row, curl, lateral raise) that replaces the current plan as
  "1x/semana".
- F16 — a ready-made question took 3 turns and about 58 s of server time to
  reach a workout suggestion.
- F25 — household measures are not converted ("1 scoop", "1 colher de sopa").
- F26 — agent-facing text reaches the patient: "Peça pro paciente confirmar ou
  detalhar."
- F27 — a blocked proposal offers only "Editar primeiro item"; rice and beans
  need the name retyped with "cozido".
- F2 — after "Calcular refeição" the sheet rests at the buttons; the values
  are above, out of sight. F9 — "Hidratação registrada." appears below the
  button, out of sight.
- F22 — Profile shows no patient data (weight, height, goal, targets).

LOW
- F3/F6 decimals ("149,9 kcal", "10,98 g / 144 g"); F4 coffee in ml shown as
  g; F7 raw code "musculacao" and a prefilled 47 min; F10 golden "Concluído"
  key; F11 tab bar lifts with a hardware keyboard; F12 "Pelo contexto aqui,";
  F17 long right-aligned bold values in the plan review; F20 one target line
  for days with different targets; F21 technical copy in Progress; ISO date
  "Data local: 2026-10-04"; four old drafts under "Para revisar".

## Numbers that matched the database

- Meal: pão francês 50 g = 149.9 kcal (TACO4:53); snapshot 302 / 2980.
- Workout: musculação 47 min, moderate, 80 kg = 322 kcal
  (`calc_workout_kcal`); food balance stays 2,678 left, block balance −3,000.
- Hydration 500 ml; weight 80.5 kg; chart bar "4 de out. · 302 kcal"; 12 bars
  for 12 snapshots with the 25 Sep gap.

## Timings and tokens

| Step | Time | Prompt / completion tokens | US$ |
|---|---|---|---|
| Read foods (3 items; 8 items) | about 5 s | not logged in `messages` | — |
| Flow, simple turn (×4) | 5.9–6.6 s server, about 8 s felt | about 10.8 k / 18–81 | 0.018–0.049 |
| Flow, menu (failed) | 42.7 s | 22.0 k / 162 | 0.041 |
| Flow, workout plan | 46.3 s | 21.8 k / 502 | 0.045 |

Every simple turn carries about 10.8 k prompt tokens (model
`anthropic/claude-sonnet-4.6`); prompt caching already cuts the cost of the
following turns by about 60 %. The prompt size is the place to cut.

## Not covered in this round

> Journeys 1, 9 and 13, meal by photo and audio, routine and reminders, Flow
> retry/cancel, plan import, cold start and memory were NOT covered (pending
> for round 2, audit 2026-10-04). No golden fixture was written for the
> findings yet: none of them was fixed in this round.

## Fixes after the round (same day, staging only)

Eduardo answered "sim" to fixing the findings. What changed, and what did not:

| Finding | Status |
|---|---|
| F8 dark-mode buttons | FIXED — the UIKit-bridged primary buttons use the brand fill with the on-primary title (`RegistrationBridgedButtonStyle`), contrast pinned in both appearances |
| F18 weight in the chart | FIXED in the mobile read model — `/trends` adds the profile weight on the day it was measured (patient calendar), only when the instant is a real measurement. It is the latest value, not a history: the profile keeps one weight |
| F14 Flow menu | FIXED in the generator — numbers written between quotes are read as numbers (ambiguous "1.500" still refused); the Flow prompt states the protein ceiling; a refused total tells the retry which way to change. The accepted window (±15 % kcal, ±20 % protein) and the two attempts are unchanged; the WhatsApp generator keeps its single call and its prompt |
| F24/F1 invented macros | FIXED for eggs and for an item that IS oil, butter or whey powder (`estimateMacros`). A dish that only mentions them ("legumes no azeite", "shake de whey") keeps the generic estimate |
| F23 catalog aliases | NOT FIXED — see below |

### F23 is a catalog decision, not a bug in staging

The 149 everyday names are out of the search on purpose: migration
`20260718212715_enforce_verified_food_catalog.sql` quarantined every row
without an auditable source, in every environment. Only twelve audited aliases
exist. The round-1 text above ("unverified on staging") was wrong about the
cause.

A first set of nine audited aliases (values copied from TACO/USDA rows) was
written and then withdrawn before commit. The adversarial review simulated the
catalog with them and found:

- exact "azeite" and "whey" rows make the composed-name split give them half
  of the grams: "salada com azeite" 200 g went from 41 to 904.6 kcal, "leite
  com whey" 300 g to 1,056 kcal with 234 g of protein;
- "ovo cozido" plus "ovo frito" verified turn a bare "ovo" into a
  cooked-or-fried question (0 kcal until answered);
- "arroz branco cozido" removes the cru/cozido question for "arroz branco"
  decided on 2026-09-28.

> RC F23 — "leite integral" 200 ml (224.9 kcal, matched to "Canjica, com leite
> integral") and "whey" 30 g (0 kcal, protein_mismatch) NOT covered (pending
> from the audit 2026-10-04). They need (a) the split to stop dividing grams
> equally when one part is a pure fat or a powder, and (b) Roberto's decision
> on which everyday names become audited aliases. Neighbours seen in the same
> simulation, also open: "leite" 200 ml resolves to "Leite, de coco" 332 kcal;
> "leite desnatado" 200 ml to powdered milk 723 kcal.

## Round 2 on the iPhone — the fixes, checked on the device (10:28–11:40 BRT)

Builds `474294f` (fixes) and `21b5ec7` (animations), mobile BFF Preview
`…-r09mvdxlq-…` (staging only).

| Finding | Result on the device |
|---|---|
| F18 weight chart | PASS — the chart ends at "4 de out. · 80,5 kg" |
| F8 dark buttons | PASS — dark title on the teal fill in the hydration sheet |
| F14 Flow menu | PASS — "Sugira um cardápio completo para hoje" answered in 52.9 s (22,443 / 608 tokens, US$ 0.078): 2,884 kcal and 152.3 g of protein, inside the window; `plan_drafts` nutrition `ready_for_review`; no generator refusal in the Preview logs. The draft was not confirmed |
| F24/F1 egg and oil | PASS — "100 g de ovo mexido e 13 g de azeite no lanche da tarde": egg 146 kcal, P 13.3, C 0.6, F 9.5; oil 114.9 kcal, F 13. Proposal cancelled |
| Opening | PASS — mark, name and the ball climbing the stairs for about 3 s, then Today |
| Flow "typing" | PASS — avatar and three dots while waiting; answer "consumiu 11 g, meta 144 g, faltam 133 g" matches the database |

New LOW finding F29: the text extractor named the item "azeite no lanche da
tarde" (the meal phrase leaked into the food name); the meal type was read
correctly.

Privacy note: when iPhone Mirroring reopened it showed a personal app and,
in the search, photo thumbnails. Nothing was touched and those captures were
deleted.
