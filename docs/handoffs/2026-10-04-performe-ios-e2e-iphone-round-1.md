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

## Round 3 on the iPhone — the two live failures of the WhatsApp-group audit, fixed (15:18–15:25 BRT)

Build of `ff50a9e` installed over the previous one (Release staging, mobile
BFF Preview `…-2ig5f8mks-…`, staging only). iOS sources identical to
`21b5ec7`, so only the staging build, its signature check and the surface
scan were repeated. QA account A.

| Test | Before (build `21b5ec7`) | After (build `ff50a9e`) |
|---|---|---|
| Flow: "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?" | "Sim! Sua meta já considera esse gasto… tecnicamente você tem espaço pra comer um pouco mais" | PASS — "O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal. Você consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida." No model call (0 tokens), 4.3 s |
| Flow, a neighbouring question answered by the model: "O treino de hoje aumenta minha meta de calorias?" | not run | PASS — "Não. A meta de 2.980 kcal é fixa — o treino não muda isso. O que você pode comer hoje é só meta menos consumido: 2.980 − 541 = 2.439 kcal restantes." (11,116 / 65 tokens, 7.5 s) |
| "150 g de frango grelhado no almoco" confirmed twice (15:23:28 and 15:24:40) | one `meal_logs` row, day at 541 kcal | PASS — two new rows of 238.8 kcal, both proposals carry `registration_origin = mobile_app`; the day went from 541 to 1,018 kcal and protein from 59.03 g to 155.13 g; Today shows "1.018 / 2.980, restam 1.962" |

The numbers on the Today screen matched the database before and after.

Not yet on the device at the time of writing: the rules of commit `9bc012b`
(milk and whey defaults, day balance per protocol), the app changes of
`9624cd5` ("Balanço do dia", "Musculação por semana", the already-saved
message) and the function region change (`e57806f`). The signing profile
expired at 18:12 BRT; the next install is re-signed.

Flow cost and speed at this point (staging, 34 answers in 14 days): about
11,000 prompt tokens per model call, US$ 0.035 per answer, median 14 s, 74 s
at the 90th percentile; the deterministic answer above still took 4.3 s
because the function ran in Virginia while the database is in São Paulo
(fixed in `e57806f`, not yet measured on the device).

## Round 4 on the iPhone — the evaluation candidate (2026-10-05, 10:43–11:01 BRT)

Build of `a95d357` installed over the previous one (Release staging, private
configuration v28). From this build on the app talks to a fixed staging
address, `performe-ai-staging-bff.vercel.app` (a Vercel alias, São Paulo
region), so a server change no longer needs a new app build; the server
behind it was `a12d11e` with the two evaluation switches on (day close from
2026-10-04; 30 days of access for a new account). The 7-day signing profile
had expired on 2026-10-04: the owner signed in to Xcode again, the build was
re-signed (profile valid until 2026-10-12) and he trusted the developer on
the phone. Release gates on `a95d357`: simulator Release, analyze (0
warnings), signature, surface scan and its 25 tests all pass. QA account A
(ganho de massa); the owner authorised, by a clicked answer, ticking the
four notices on that test account.

| Test | Result |
|---|---|
| Existing account opens after the four evaluation notices were published | PASS — the app stops at step 6 of 7 with the four notices, titled "Termos de uso", "Política de privacidade", "Saúde e inteligência artificial", "Dados sensíveis de saúde", each with the approved text, "Versão 04.10.2026" and its own checkbox; "Continuar" stays disabled until the four are ticked. The review step shows "Brasil", "São Paulo · Horário Padrão de Brasília" and "4 ações confirmadas". Database: four rows in `user_onboarding_legal_actions`, version `04.10.2026`, 10:46:23; profile untouched |
| Day close on demand | PASS — opening Today closed 2026-10-04: `day_closed = true`, the target stored that day (2,980) kept, `xp_earned` 20; `user_progress` streak 1, XP 20. Progress shows "Sequência: 1 dia" and "20 XP · Nível 1" (both were 0). Block credit 0, as the closer's own rule gives for a day at 34% of the target |
| Today, "Mais detalhes" | PASS — "Balanço do dia: Déficit de 2.846 kcal", caption "Exercício já contado no nível de atividade"; the date reads "segunda-feira, 5 de outubro"; no demonstration card |
| Register > Treino | PASS — the form opens empty; "Natação", 40 min, moderate → 460 kcal proposed (10.0 × 40 × 80.5 / 70; the generic rate would give 276). Proposal cancelled |
| Register > Refeição by text, "1 copo de leite com whey no jantar", 200 g and 30 g | PASS — "leite integral" 122 kcal (P 6.3 / C 9.6 / G 6.5) and "whey protein em pó" 105.6 kcal (P 23.44 / C 1.88 / G 0.47); badge "Valores calculados pelo Performe AI". Proposal cancelled |
| Sign out | PASS — "Sair desta conta neste iPhone? Seus dados continuam salvos na sua conta."; the app returns to "Entrar" |

### The Flow, measured with the real model for the first time after `426a214`

| Turn | Model calls | Prompt tokens | Cost | Time |
|---|---|---|---|---|
| "Como esta meu dia ate agora?" | 3 (read tool, answer, guard retry) | 25,563 | US$ 0.0675 (US$ 0.0407 of it is the first call writing the cache) | 10.6 s |
| "Sugira um cardapio completo para hoje" — the Flow asked about restrictions | 1 | 8,313 (5,062 from cache) | US$ 0.0121 | 3.0 s |
| "Sem restricoes" — the menu | 2, plus the generator twice | 7,943 and 8,782 | US$ 0.0878 | 44 s |

Against the baseline of the day before (about 11,000 prompt tokens per call,
US$ 0.035 per answer, median 14 s): a call now carries 8,000–8,700 tokens
and a one-call answer costs US$ 0.012 and takes 3 s.

Two things found by measuring:

- **The registration guard fires on negations in the Flow.** "Hoje ainda não
  tem nada registrado" was read as a claim of registration: one more model
  call (US$ 0.0137, 3.2 s), both guard events written, and the retry appended
  a redundant paragraph to the answer. In the last 8 days 5 of 37 Flow
  answers did this, all five negations. The Flow has no registration tool,
  so the retry can never succeed there. A Flow-only fix is in review.
- **The diet generator missed the protein band on its first attempt**
  (`protein_drift_exceeded`, 37% above 144.9 g) and ran again: about 17 s and
  US$ 0.028 for the wasted attempt. Being mapped.

Not covered in this round: a NEW account (sign-up, the automatic 30 days,
the Flow in recomposição) — the owner types the e-mail and the password, and
it was left for the end; the full iOS suite on `a95d357`.

One mistake of the tester during the round: "Começar de novo" was tapped
instead of "Calcular refeição" (the button moves up once the quantity is
filled); the meal was entered again.

## Round 5 — the evening of 2026-10-05: panel, Flow names, the plan's notes, the demo video

Simulator (iPhone 18 Pro, iOS 27, Release build with the staging settings,
account QA A) and the iPhone. Staging only.

### What changed and where it is

| Commit | What | Where it runs |
|---|---|---|
| `d3a3116` | The Flow never shows the method's name nor its author's (instruction + closed-vocabulary projection of the final text) | staging BFF, preview `ap8ccfy5l` behind `performe-ai-staging-bff.vercel.app` (the previous one, `dme8ur037` = `a12d11e`, is the way back) |
| `cd25815` | The panel becomes the Performe AI panel, with one server-side role matrix | staging panel, preview `agentempp-media-worker-staging-mhal48ijj` (behind Vercel login) |
| `0db4741` | Project instructions: the product is the app; the WhatsApp agent is legacy | — |
| `95dca3a` | The plan's notes use the card's width (they were a narrow right-aligned column of about twenty lines) | iPhone, installed over (way back: `release-gates-v3-a95d357`) |

The owner authorised the staging publication by a clicked answer ("Sim, pode
publicar"). Inngest was **not** re-synced: photo, audio and plan import still
run on the previous worker preview (`dopnv6cx4`, `2be6370`); re-syncing asks
for a re-test of the three.

### The Flow on the real model, after the publication

Three turns on the simulator, 21:07–21:09 BRT, answers as received:

| Question | Answer |
|---|---|
| "Qual e o método que vocês usam?" | "As orientações seguem o programa do Performe AI. Não entro em detalhes sobre o método internamente, mas tudo que te passo — metas, protocolos, ajustes — vem dele." |
| "Isso e o MPP?" | "Não consigo confirmar nem negar nomes internos do método. O que posso dizer é que tudo aqui segue o programa do Performe AI." |
| "Quem e o Dr. Roberto?" | "Não tenho essa informação pra te passar. O que posso dizer é que o programa é do Performe AI — não trabalho com referências a pessoas específicas por trás do método." |

`product_events` for the account in that window: 3 `llm.flow_calls`, 0
`llm.flow_internal_name_replaced` — the model followed the instruction by
itself and the projection did not have to act. One sample per question; it
is the manual part of RC FN-1, not a measurement.

### The plan's notes, on the real data

The training plan of QA A carries a note of about 400 characters. Before:
a right-aligned column beside the label. After `95dca3a`, on the simulator
against staging: label on its own line, eleven lines of text across the card.

### The full iOS suite on `95dca3a` (21:12–23:18 BRT, alone on the machine)

FULL SUITE RESULT: 1,973 tests, 1,971 passed, **2 failed**.

- `PerformeVoiceOverNavigationUITests/testVoiceOverReadsFiveTabsInOrderAndPreservesSelectionOnIOS27`
  — the known one ("VoiceOver did not reach button Today within the bounded
  search"); waits for the owner's decision on its budget.
- `FlowChatUITests/testFiftyMessagesKeepUnsentComposerAndReadingPositionAcrossTabs`
  — exceeded the 10-minute allowance. After each tap on `flow.send` XCTest
  waited 60 s for the app to become idle and logged "App animations complete
  notification not received", nine times.

ISOLATED CHARACTERIZATION of the second one (same invocation, that test only,
3 iterations asked, no retry-on-failure): iteration 1 passed in 178 s,
iteration 2 exceeded the allowance, iteration 3 did not run. History of the
same test in earlier full runs: passed on `e40bed3` (96.6 s), `d6278c2`
(82.6 s) and `c2b2b40` (84.4 s); exceeded the allowance on `9624cd5`, on the
interrupted run of `64a0e71` and now. It is intermittent, it predates this
evening's commits (none of them touches the Flow screen), and its cause is
not known: either the Flow screen with fifty messages sometimes keeps an
animation running after a message is sent, or the test framework does not
see the app settle. Under investigation.

FINAL VERIFIED STATE: partially verified — 2 failures stand; no isolated
pass is counted as a pass.

### The demo video

The owner asked for a video to send to the physician while Apple's approval
is pending, in light mode, with the existing test accounts. Recorded on the
simulator (`simctl io recordVideo`), 3 min 25 s, 13.9 MB: tour, Today, a
meal by text, a workout, Today updated, one question to the Flow, Progress,
Plan. Only the tester's pauses and one mistyped entry were cut; the app's
own waits are in real time. It was recorded before `95dca3a`, so the Plan
screen appears only in passing; the owner kept it as it is.

Two mistakes of the tester while trying iPhone Mirroring first (abandoned
for the simulator): a recording interrupted with SIGINT was not saved; and a
paste landed the test account's password, still in the shared clipboard, in
the meal-description field, and it was sent to the text extractor (no
account attached to it; the server neither stores nor logs that text). The
owner was told; rotating that test password is on the closing list.

### Still open

- The owner creates a NEW account (sign-up, automatic 30 days, the Flow in
  recomposição): left for the end by his choice.
- Apple's approval, then TestFlight (`docs/mobile/testflight-evaluation.md`).
- The intermittent Flow test above; the VoiceOver budget.
- "Equipamentos" of a plan still uses the two-column row (RC PN-2).

### The intermittent Flow test, investigated (2026-10-05 23:40 – 2026-10-06 02:10 BRT)

Result: **the app is idle during the stalls; what gets stuck is XCTest's own
animation counter.** Nothing was changed in the repository (app or tests).

Two statements of the section above are corrected by the logs:

- the stall does not begin after the tap on `flow.send`: it begins right
  after `flow.composer` takes focus, when the keyboard rises (in 3 of the 5
  stalls of the night at the first focus, before any message was sent);
- the 178 s of the first isolated iteration carry no stall: about 95 s of
  them are the sign-up and onboarding the test performs once per process.

What was measured inside the app while XCTest reported "animating" (a
temporary DEBUG-only probe, removed afterwards):

- XCTest's indicator stayed on for 608 one-second samples in a row; in 586 of
  them the main run loop woke at most 5 times a second (60–200 with a real
  animation);
- 61 sweeps of every layer found only two system animations, the text cursor
  and the native tab bar's lens, both without a delegate and both present
  when the test passes; no scroll view was moving; the typing dots appeared
  once, while a reply was pending, and never after;
- XCTest counts `-[UIViewAnimationState animationDidStart:]` against
  `animationDidStop:finished:`; one keyboard rise left the counter one above
  zero, and every later idle wait then costs 60 s.

It is not specific to this test: 10 of the 15 suite logs since 2026-10-02
carry such stalls (20 in the `c2b2b40` run, in tests that still passed), and
in 25 of the 30 tests where one begins the last action is focus on a text
field inside the tab shell (24 times `flow.composer`). Fields outside the
shell (sign-in, sign-up, onboarding) never start one.

| Binary | Iterations without the sign-up | Stalled |
|---|---|---|
| clean (`95dca3a`, `b5e6aa0`) | 6 | 3 |
| with the first two versions of the probe | 2 | 2 |
| with the later versions of the probe | 16, plus the whole class once (15 tests) | 0 |

The probe changes the outcome, which points to a timing race inside UIKit and
Core Animation rather than to something the app leaves running.

Not proven: which call is left unbalanced; why the later probes hide it;
whether removing the glass tab bar inside the keyboard animation
(`AppShellView.swift`) is the trigger; and the behaviour on a physical
iPhone (everything here is the simulator; in manual use on the iPhone and on
the simulator the Flow screen behaved normally). Smallest next experiment,
about 25 minutes: a DEBUG switch that keeps the tab bar mounted while the
keyboard is up, 6 iterations with and 6 without, same binary.

Decision for the owner: how the suite treats the signature "exceeded the
allowance + `App animations complete notification not received` + zero
failed assertions". Today it counts as a failure, and it stays counted.

Evidence outside the repository:
`~/.local/share/performe-ai/final-polish-20261001/handoff-20261004/flow-idle/`.
