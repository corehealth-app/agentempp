/**
 * Golden — "leite" and "whey" typed without a type (rule M2, everyday names).
 *
 * THE REPORT (test 3 of the WhatsApp-group audit): iPhone, staging, QA
 * account, build 21b5ec7, 2026-10-04. Text "1 copo de leite com whey no
 * jantar", grams typed on the phone 200 and 30, meal type jantar, country BR.
 * Observed on the proposal screen:
 *   leite  200 g → "Leite, de coco"  332.3 kcal · 36.7 g of fat (canonical_fuzzy)
 *   whey    30 g → not calculated, 0 kcal (protein_mismatch). By the code, a
 *                  proposal with such an item cannot be confirmed (422
 *                  registration_unresolved_items); the refusal itself was
 *                  not captured in the report.
 * Correct result with the rule below: leite integral 122 kcal + whey protein
 * em pó 105.6 kcal = 227.6 kcal · P 29.7 · C 11.5 · G 7.0, nothing blocked.
 *
 * THE RULE AND WHO SAID IT. The client stated the general rule "assume
 * instead of asking" on 06/01/2026 (manual 4.2), 18/05/2026 and 01/06/2026.
 * He did not state this list of items; it was implemented on 2026-10-04 at
 * Eduardo's request and the client's confirmation is pending
 * (everyday-food-defaults.ts; revert = empty the list).
 *
 * READ FROM STAGING on 2026-10-04 ~15:00 BRT (read-only; public catalog data):
 *   - search_food_trgm('leite', 0.2, 6, 'BR') and ('whey', 0.2, 6, 'BR'): ids,
 *     names and similarities of the six rows of each window;
 *   - the macros of rows 666, 602, 4112 and 4508;
 *   - the two verified rows the list points to, found by their exact name
 *     with similarity 1: 4492 "Milk, whole, 3.25% milkfat, with added
 *     vitamin D" (FDC:171265; 61 / 3.15 / 4.8 / 3.25 / fiber 0) and 6407
 *     "Beverages, Protein powder whey based" (FDC:173180; 352 / 78.13 / 6.25 /
 *     1.56 / fiber 3.1);
 *   - "leite integral" (2026-10-04, round 1, finding F23) and "azeite" (empty)
 *     come from audit-10-04-e2e-iphone-food-and-diet.test.ts; "arroz branco"
 *     (2026-09-28) comes from audit-09-27-device-gate.test.ts.
 *
 * ASSUMED — declared:
 *   - the staging read asked for 6 rows and the code asks for 20. The rows
 *     below the sixth (TAIL) are computed from the catalog migrations with
 *     the pg_trgm rule; the same computation gives the six rows read on
 *     staging, row for row. One test runs the report with them.
 *   - only the fields listed above were printed in the staging read. Every
 *     other field of the window rows (the macros of 596, 601, 606, 640, 4509,
 *     4510, 2948 and 5913; categories; the fibre of 602, 4112 and 4508) is the
 *     value of the official import migrations (20260718213529 and
 *     20260718213533).
 *   - the windows of "salada com azeite", "salada", "ovo", "leite de coco",
 *     "leite de cabra", "leite com whey" and "whey protein em pó" are
 *     computed from the same migrations, not read from staging.
 *   - the patient id, the history row and the correction rows are synthetic.
 *
 * The three guards are the side effects that made the first attempt (catalog
 * alias rows, withdrawn on 2026-10-04) unsafe. Their expected values were
 * measured with these same windows on the code BEFORE this change.
 *
 * REVIEW FINDING (adversarial review of 2026-10-04, executed): items
 * [leite 200 g, leite integral 200 g]. Before the rename (HEAD 55294c4) the
 * two names were distinct and both were recorded (557.2 kcal: coconut milk
 * 332.3 + "Canjica, com leite integral" 224.9). With the rename, the proposal
 * had two identical lines "leite integral" (244 kcal) and the confirmation's
 * in-array dedup wrote one (122 kcal). Now the two items are ONE line,
 * "leite integral" 400 g, 244 kcal, and the day receives 244 kcal (the app
 * end is in registration-service.everyday-defaults.test.ts).
 *
 * Declared pendencies (CLAUDE.md criterion 2). The section "Padrões do dia a
 * dia" of docs/CALCULO-MPP.md has to carry these same "> RC M2" lines,
 * verbatim.
 *
 * > RC M2 — cenário frase "1 copo de leite com whey no jantar" passando pelo extrator de texto do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A fixture entra com os itens "leite" 200 g e "whey" 30 g, como no relato;
 *   os nomes que o extrator gravou no pending real não foram lidos. Se ele
 *   devolver "leite no jantar" ou "copo de leite", o nome não está na lista e
 *   o item segue o cálculo de antes.
 * > RC M2 — cenário medida caseira ("1 copo", "1 scoop") sem gramas NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O app continua pedindo as gramas (achado F25).
 * > RC M2 — cenário item único "leite com whey" (WhatsApp, relatos C6-14 e C6-22) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Continua sem cálculo (composite_rejected): falta a receita padrão, que o
 *   cliente não disse. Caracterizado abaixo.
 * > RC M2 — cenário "leite desnatado", "leite semidesnatado", "leite de vaca", "leite de soja" e "whey protein" NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não estão na lista e seguem o cálculo de antes, com os erros de antes.
 * > RC M2 — cenário correção aprendida do paciente sobre o nome mostrado ("leite integral" → outro) aplicada ao nome digitado "leite" NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A correção é procurada pelo nome que chegou ("leite"), não pelo mostrado.
 * > RC M2 — cenário dois itens de mesmo nome FORA da lista do dia a dia na mesma proposta (por exemplo "leite de coco" 100 g duas vezes) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Limite anterior a esta mudança e inalterado: a proposta mostra as duas
 *   linhas (332,4 kcal) e a dedup do confirm grava uma (166,2 kcal). Só os
 *   itens da lista são somados numa linha. Caracterizado abaixo.
 * > RC M2 — cenário item da lista ao lado de outra linha que sai com o MESMO nome mostrado por outra fonte — kcal dita pelo paciente, correção ativa do paciente com macro próprio ou rótulo aprovado (por exemplo "leite" 200 g e "leite integral" 200 g com 90 kcal) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Vale para QUALQUER linha que saia com o nome mostrado por outra fonte que
 *   não a linha do catálogo da lista: kcal dita pelo paciente, correção ativa
 *   do paciente com macro próprio e rótulo aprovado. Só as linhas do padrão do
 *   dia a dia são somadas numa só. Com kcal dita pelo paciente: a proposta
 *   mostra duas linhas "leite integral" (122 e 90 kcal) e, no confirm, a dedup
 *   lança "conflito nutricional entre cópias de leite integral"; nada é
 *   gravado. Com correção ativa "leite desnatado" → "leite integral" a 35
 *   kcal/100 g, itens "leite" 200 g e "leite desnatado" 200 g: duas linhas
 *   "leite integral" (122 e 70 kcal, 192 no total) e o mesmo conflito no
 *   confirm; com gramas diferentes (200 g e 150 g) a dedup do confirm soma as
 *   duas numa linha de 350 g e 174,5 kcal. Com rótulo aprovado: mesmo
 *   mecanismo, não executado. Antes da renomeação os nomes eram diferentes e
 *   os dois eram gravados. As duas primeiras variantes estão caracterizadas
 *   abaixo (cálculo e dedup reais).
 * > RC M2 — cenário proposta do app com outro item depois dos dois itens somados (quantity_basis e candidate_id lidos por posição em registration-service.ts) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A proposta tem uma linha a menos que o pedido; o item seguinte recebe o
 *   quantity_basis e o candidate_id do item que foi somado. Kcal, gramas e
 *   nomes ficam certos. O cálculo devolve `input_indexes` para o serviço
 *   parear certo; o serviço ainda não lê. Caracterizado no teste do app.
 * > RC M2 — cenário WhatsApp ponta a ponta com "leite" e "leite integral" na mesma mensagem (pending, edição do pending e correção em 30 min da linha somada) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Coberto aqui só no cálculo e nos argumentos do confirm.
 * > RC M2 — cenário WhatsApp ponta a ponta (o modelo chama registra_refeicao com "leite" e "whey" como itens separados) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Coberto aqui só no cálculo e no texto da proposta; a gravação pela
 *   ferramenta real está no teste do app
 *   (registration-service.everyday-defaults.test.ts), pelo caminho do confirm.
 * > RC M2 — cenário tela do iPhone mostrando o nome assumido NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O contrato não muda (o app imprime `name` como recebe), mas nada foi
 *   executado no aparelho depois desta mudança; nem a proposta com UMA linha
 *   somada no lugar das duas digitadas.
 * > RC M2 — cenário correção em 30 min no WhatsApp de uma refeição com dois itens de leite (por exemplo "leite" e "leite em pó") NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O nome digitado ("leite") contra o gravado ("leite integral") deixa de ser
 *   igual e passa a ser "contém": com outro item que também contém "leite" o
 *   alvo da correção fica ambíguo. O caso de um item só está fixado abaixo.
 * > RC M2 — cenário registros e pendings anteriores a esta mudança ("leite" gravado como leite de coco, 332,3 kcal) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nada é corrigido para trás; backfill exige autorização do Eduardo nomeando
 *   alvo e valores.
 * > RC M2 — cenário catálogo de PRODUÇÃO (linhas FDC:171265 e FDC:173180 verificadas, com os mesmos valores do staging) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não foi lido. Sem as linhas, ou com valor diferente, a regra não age e o
 *   erro do relato continua (leite de coco 332,3 kcal; whey sem cálculo).
 * > RC M2 — cenário lista de itens aprovada pelo cliente NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O cliente disse a regra geral (06/01/2026, 18/05/2026 e 01/06/2026), não
 *   os itens; "leite" = integral e "whey" = whey protein em pó aguardam a
 *   confirmação dele.
 */
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { buildConfirmedMealArgs } from '../confirmed-meal.js'
import { EVERYDAY_FOOD_DEFAULTS } from '../everyday-food-defaults.js'
import { dedupeMealItems } from '../meal-item-dedup.js'
import {
  calcMealMacros,
  isUnresolvedNutritionSource,
  type MealCalcResult,
  type MealItemInput,
} from '../meal-pipeline.js'
import { foodNamesReferToSameItem, selectMealReplacementTarget } from '../meal-replacement-target.js'
import {
  buildPendingNutritionConfirmationNotes,
  composePendingProposal,
  type MealItem,
} from '../post-registration-message.js'

type Row = {
  id: number
  name_pt: string
  category: string
  country_code: string
  similarity: number
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number | null
}

const r = (
  id: number,
  name_pt: string,
  category: string,
  similarity: number,
  kcal_per_100g: number,
  protein_g: number,
  carbs_g: number,
  fat_g: number,
  fiber_g: number | null,
  country_code = 'BR',
): Row => ({
  id,
  name_pt,
  category,
  country_code,
  similarity,
  kcal_per_100g,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
})

const LEITE = 'Leite e derivados'
const ACUCARADOS = 'Produtos açucarados'
const CEREAIS = 'Cereais e derivados'
const PREPARADOS = 'Alimentos preparados'
const VERDURAS = 'Verduras, hortaliças e derivados'
const INDUSTRIALIZADOS = 'Outros alimentos industrializados'
const DAIRY = 'Dairy and Egg Products'
const BEVERAGES = 'Beverages'

const MILK_NAME = 'Milk, whole, 3.25% milkfat, with added vitamin D'
const WHEY_NAME = 'Beverages, Protein powder whey based'
const MILK_ROW_ID = 4492
const WHEY_ROW_ID = 6407

const WINDOWS: Record<string, Row[]> = {
  // ── read from staging, 2026-10-04 ~15:00 BRT ────────────────────────────
  leite: [
    r(666, 'Leite, de coco', INDUSTRIALIZADOS, 0.428571, 166.16, 1.01, 2.19, 18.36, 0.68),
    r(596, 'Creme de Leite', LEITE, 0.4, 221.48, 1.51, 4.51, 22.48, null),
    r(602, 'Leite, de cabra', LEITE, 0.4, 66.42, 3.07, 5.25, 3.75, null),
    r(601, 'Leite, condensado', LEITE, 0.352941, 312.57, 7.67, 57, 6.74, null),
    r(606, 'Leite, fermentado', LEITE, 0.352941, 69.62, 1.89, 15.67, 0.1, null),
    r(640, 'Chocolate, ao leite', ACUCARADOS, 0.333333, 539.59, 7.22, 59.58, 30.27, 2.17),
  ],
  whey: [
    r(4112, 'Whey, acid, fluid', DAIRY, 0.333333, 24, 0.76, 5.12, 0.09, 0, 'US'),
    r(4508, 'Whey, acid, dried', DAIRY, 0.3125, 339, 11.73, 73.45, 0.54, 0, 'US'),
    r(4509, 'Whey, sweet, fluid', DAIRY, 0.294118, 27, 0.85, 5.14, 0.36, 0, 'US'),
    r(4510, 'Whey, sweet, dried', DAIRY, 0.294118, 353, 12.93, 74.46, 1.07, 0, 'US'),
    r(2948, 'Wheat, durum', 'Cereal Grains and Pasta', 0.214286, 339, 13.68, 71.13, 2.47, null, 'US'),
    r(5913, 'Bread, wheat', 'Baked Products', 0.214286, 274, 10.67, 47.54, 4.53, 4, 'US'),
  ],
  [MILK_NAME.toLowerCase()]: [r(MILK_ROW_ID, MILK_NAME, DAIRY, 1, 61, 3.15, 4.8, 3.25, 0, 'US')],
  [WHEY_NAME.toLowerCase()]: [r(WHEY_ROW_ID, WHEY_NAME, BEVERAGES, 1, 352, 78.13, 6.25, 1.56, 3.1, 'US')],
  // Round 1 of the same day (finding F23).
  'leite integral': [
    r(177, 'Canjica, com leite integral', CEREAIS, 0.576923, 112.46, 2.36, 23.63, 1.24, 1.22),
    r(605, 'Leite, de vaca, integral, pó', LEITE, 0.576923, 496.65, 25.42, 39.18, 26.9, null),
    r(159, 'Arroz, integral, cru', CEREAIS, 0.36, 359.68, 7.32, 77.45, 1.86, 4.82),
  ],
  azeite: [],
  // 2026-09-28 (device gate).
  'arroz branco': [
    r(673, 'Bolinho de arroz', PREPARADOS, 0.3043, 273.51, 8.04, 41.68, 8.29, 2.74),
    r(306, 'Repolho, branco, cru', VERDURAS, 0.28, 17.12, 0.88, 3.86, 0.14, 1.89),
    r(669, 'Arroz carreteiro', PREPARADOS, 0.2609, 153.77, 10.83, 11.58, 7.12, 1.5),
    r(161, 'Arroz, tipo 1, cru', CEREAIS, 0.25, 357.79, 7.16, 78.76, 0.34, 1.64),
    r(163, 'Arroz, tipo 2, cru', CEREAIS, 0.25, 358.12, 7.24, 78.88, 0.28, 1.72),
    r(184, 'Creme de arroz, pó', CEREAIS, 0.24, 386, 7.03, 83.87, 1.23, 1.07),
    r(159, 'Arroz, integral, cru', CEREAIS, 0.2308, 359.68, 7.32, 77.45, 1.86, 4.82),
    r(644, 'Cocada branca', ACUCARADOS, 0.2273, 448.85, 1.12, 81.38, 13.59, 3.57),
    r(160, 'Arroz, tipo 1, cozido', CEREAIS, 0.2222, 128.26, 2.52, 28.06, 0.23, 1.56),
    r(162, 'Arroz, tipo 2, cozido', CEREAIS, 0.2222, 130.12, 2.57, 28.19, 0.36, 1.07),
    r(158, 'Arroz, integral, cozido', CEREAIS, 0.2069, 123.53, 2.59, 25.81, 1, 2.75),
  ],
  // ── computed from the catalog migrations (see ASSUMED) ──────────────────
  'salada com azeite': [
    r(318, 'Tomate, salada', VERDURAS, 0.333333, 20.55, 0.81, 5.12, 0, 2.27),
    r(687, 'Salada, de legumes, com maionese', PREPARADOS, 0.289474, 96.1, 1.05, 8.92, 7.04, 2.22),
    r(416, 'Manteiga, com sal', 'Gorduras e óleos', 0.25, 725.97, 0.41, 0.06, 82.36, null),
    r(688, 'Salada, de legumes, cozida no vapor', PREPARADOS, 0.214286, 35.41, 2.01, 7.09, 0.31, 2.51),
    r(663, 'Azeitona, preta, conserva', INDUSTRIALIZADOS, 0.2, 194.15, 1.16, 5.54, 20.35, 4.56),
    r(664, 'Azeitona, verde, conserva', INDUSTRIALIZADOS, 0.2, 136.94, 0.95, 4.1, 14.22, 3.85),
    r(2283, 'Salad dressing, coleslaw', 'Fats and Oils', 0.2, 404, 0.85, 22.4, 34.53, 0, 'US'),
  ],
  salada: [
    r(318, 'Tomate, salada', VERDURAS, 0.5, 20.55, 0.81, 5.12, 0, 2.27),
    r(592, 'Salame', 'Carnes e derivados', 0.4, 397.84, 25.81, 2.91, 30.64, null),
    r(7093, 'Ham salad spread', 'Sausages and Luncheon Meats', 0.294118, 216, 8.68, 10.64, 15.53, 0, 'US'),
    r(3963, 'TACO BELL, Taco Salad', 'Fast Foods', 0.277778, 170, 6.69, 15.1, 9.17, 3, 'US'),
    r(8387, 'Fish, tuna salad', 'Finfish and Shellfish Products', 0.277778, 187, 16.04, 9.41, 9.26, 0, 'US'),
    r(5301, "McDONALD'S, Side Salad", 'Fast Foods', 0.227273, 20, 1.03, 4.3, 0.19, 1.6, 'US'),
    r(687, 'Salada, de legumes, com maionese', PREPARADOS, 0.225806, 96.1, 1.05, 8.92, 7.04, 2.22),
    r(651, 'Marmelada', ACUCARADOS, 0.214286, 257.24, 0.4, 70.76, 0.14, 4.07),
    r(688, 'Salada, de legumes, cozida no vapor', PREPARADOS, 0.212121, 35.41, 2.01, 7.09, 0.31, 2.51),
    r(467, 'Sardinha, assada', 'Pescados e frutos do mar', 0.210526, 164.35, 32.18, 0, 2.99, null),
    r(729, 'Amêndoa, torrada, salgada', 'Nozes e sementes', 0.208333, 580.75, 18.55, 29.55, 47.32, 11.64),
    r(4232, 'Salad dressing, russian dressing', 'Fats and Oils', 0.208333, 355, 0.69, 31.9, 26.18, 0.7, 'US'),
    r(6570, 'Potato salad with egg', 'Meals, Entrees, and Side Dishes', 0.208333, 157, 1.96, 16.18, 9.4, 1.3, 'US'),
    r(310, 'Salsa, crua', VERDURAS, 0.2, 33.42, 3.26, 5.71, 0.61, 1.85),
    r(6695, 'Salt, table', 'Spices and Herbs', 0.2, 0, 0, 0, 0, 0, 'US'),
  ],
  ovo: [],
  'leite de coco': [
    r(666, 'Leite, de coco', INDUSTRIALIZADOS, 1, 166.16, 1.01, 2.19, 18.36, 0.68),
    r(596, 'Creme de Leite', LEITE, 0.526316, 221.48, 1.51, 4.51, 22.48, null),
    r(602, 'Leite, de cabra', LEITE, 0.526316, 66.42, 3.07, 5.25, 3.75, null),
    r(623, 'Coco, água de', 'Bebidas (alcoólicas e não alcoólicas)', 0.421053, 21.51, 0, 5.28, 0, 0.13),
    r(646, 'Doce, de leite, cremoso', ACUCARADOS, 0.4, 306.31, 5.48, 59.49, 5.99, null),
    r(601, 'Leite, condensado', LEITE, 0.347826, 312.57, 7.67, 57, 6.74, null),
    r(640, 'Chocolate, ao leite', ACUCARADOS, 0.333333, 539.59, 7.22, 59.58, 30.27, 2.17),
    r(603, 'Leite, de vaca, achocolatado', LEITE, 0.322581, 82.82, 2.1, 14.16, 2.17, 0.65),
    r(604, 'Leite, de vaca, desnatado, pó', LEITE, 0.3, 361.61, 34.69, 53.04, 0.93, null),
    r(732, 'Coco, cru', 'Nozes e sementes', 0.294118, 406.49, 3.69, 10.4, 41.98, 5.38),
    r(605, 'Leite, de vaca, integral, pó', LEITE, 0.290323, 496.65, 25.42, 39.18, 26.9, null),
  ],
  'leite de cabra': [
    r(602, 'Leite, de cabra', LEITE, 1, 66.42, 3.07, 5.25, 3.75, null),
    r(666, 'Leite, de coco', INDUSTRIALIZADOS, 0.526316, 166.16, 1.01, 2.19, 18.36, 0.68),
    r(596, 'Creme de Leite', LEITE, 0.5, 221.48, 1.51, 4.51, 22.48, null),
    r(646, 'Doce, de leite, cremoso', ACUCARADOS, 0.384615, 306.31, 5.48, 59.49, 5.99, null),
    r(604, 'Leite, de vaca, desnatado, pó', LEITE, 0.290323, 361.61, 34.69, 53.04, 0.93, null),
    r(605, 'Leite, de vaca, integral, pó', LEITE, 0.28125, 496.65, 25.42, 39.18, 26.9, null),
    r(601, 'Leite, condensado', LEITE, 0.28, 312.57, 7.67, 57, 6.74, null),
    r(603, 'Leite, de vaca, achocolatado', LEITE, 0.272727, 82.82, 2.1, 14.16, 2.17, 0.65),
  ],
  'leite com whey': [
    r(666, 'Leite, de coco', INDUSTRIALIZADOS, 0.380952, 166.16, 1.01, 2.19, 18.36, 0.68),
    r(601, 'Leite, condensado', LEITE, 0.333333, 312.57, 7.67, 57, 6.74, null),
    r(177, 'Canjica, com leite integral', CEREAIS, 0.322581, 112.46, 2.36, 23.63, 1.24, 1.22),
    r(596, 'Creme de Leite', LEITE, 0.304348, 221.48, 1.51, 4.51, 22.48, null),
    r(602, 'Leite, de cabra', LEITE, 0.304348, 66.42, 3.07, 5.25, 3.75, null),
    r(640, 'Chocolate, ao leite', ACUCARADOS, 0.269231, 539.59, 7.22, 59.58, 30.27, 2.17),
    r(646, 'Doce, de leite, cremoso', ACUCARADOS, 0.241379, 306.31, 5.48, 59.49, 5.99, null),
    r(606, 'Leite, fermentado', LEITE, 0.230769, 69.62, 1.89, 15.67, 0.1, null),
    r(4112, 'Whey, acid, fluid', DAIRY, 0.2, 24, 0.76, 5.12, 0.09, 0, 'US'),
  ],
  'whey protein em pó': [
    r(WHEY_ROW_ID, WHEY_NAME, BEVERAGES, 0.368421, 352, 78.13, 6.25, 1.56, 3.1, 'US'),
    r(6394, 'Beverages, ABBOTT, EAS whey protein powder', BEVERAGES, 0.348837, 385, 66.67, 17.95, 5.13, 0, 'US'),
    r(6404, 'Beverages, Whey protein powder isolate', BEVERAGES, 0.341463, 359, 58.14, 29.07, 1.16, 0, 'US'),
    r(7503, 'Soy protein isolate', 'Legumes and Legume Products', 0.266667, 335, 88.32, 0, 3.39, 0, 'US'),
    r(6408, 'Beverages, Protein powder soy based', BEVERAGES, 0.214286, 388, 55.56, 28.89, 5.56, 6.7, 'US'),
  ],
}

// Rows 7 to 20 of the two reported windows, computed (see ASSUMED).
const TAIL: Record<string, Row[]> = {
  leite: [
    r(646, 'Doce, de leite, cremoso', ACUCARADOS, 0.285714, 306.31, 5.48, 59.49, 5.99, null),
    r(604, 'Leite, de vaca, desnatado, pó', LEITE, 0.24, 361.61, 34.69, 53.04, 0.93, null),
    r(177, 'Canjica, com leite integral', CEREAIS, 0.230769, 112.46, 2.36, 23.63, 1.24, 1.22),
    r(605, 'Leite, de vaca, integral, pó', LEITE, 0.230769, 496.65, 25.42, 39.18, 26.9, null),
    r(603, 'Leite, de vaca, achocolatado', LEITE, 0.222222, 82.82, 2.1, 14.16, 2.17, 0.65),
    r(642, 'Chocolate, ao leite, dietético', ACUCARADOS, 0.214286, 556.82, 6.9, 56.32, 33.77, 2.85),
  ],
  whey: [r(760, 'Bagels, wheat', 'Baked Products', 0.2, 250, 10.2, 48.89, 1.53, 4.1, 'US')],
}

type Correction = {
  said_name: string
  corrected_to: string
  custom_kcal_per_100g: number | null
  custom_protein_g: number | null
  custom_carbs_g: number | null
  custom_fat_g: number | null
  status: 'learning' | 'active'
  confirmed_count: number
}

type HistoryRow = {
  id: string
  food_name: string
  food_db_id: number
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source: string
  food_db: { is_verified: boolean }
}

type RpcCall = { term: string; min_similarity: number; max_results: number; p_country: string }

type CatalogOptions = {
  /** Rows the catalog does not hold (every window loses them). */
  withoutRows?: number[]
  /** A row whose values differ from the ones written in the list. */
  changed?: Record<number, Partial<Row>>
  /** Adds the computed rows below the sixth to "leite" and "whey". */
  withTail?: boolean
  /** The exact-name search fails. */
  exactSearchError?: string
  corrections?: Correction[]
  history?: HistoryRow[]
}

function staging(options: CatalogOptions = {}) {
  const calls: RpcCall[] = []
  const tables: string[] = []
  const table = (rows: unknown[]) => {
    let orFilter: string | null = null
    let nameFilter: string | null = null
    const builder: Record<string, unknown> = {}
    for (const method of ['select', 'eq', 'neq', 'gt', 'gte', 'in', 'order', 'limit']) {
      builder[method] = () => builder
    }
    // lookupFoodCorrection: "said_name.eq.<name>,corrected_to.eq.<name>".
    builder.or = (expression: string) => {
      orFilter = expression
      return builder
    }
    // The median fallback reads meal_logs by food name (no wildcard).
    builder.ilike = (_column: string, value: string) => {
      nameFilter = value.toLowerCase()
      return builder
    }
    const run = () => {
      if (nameFilter != null) {
        return (rows as HistoryRow[]).filter((row) => row.food_name.toLowerCase() === nameFilter)
      }
      if (orFilter == null) return rows
      const target = /^said_name\.eq\.(.*),corrected_to\.eq\.\1$/.exec(orFilter)?.[1]
      return (rows as Correction[]).filter(
        (row) => row.said_name === target || row.corrected_to === target,
      )
    }
    // biome-ignore lint/suspicious/noThenProperty: mirrors the awaitable PostgREST builder
    builder.then = (resolve: (value: { data: unknown[]; error: null }) => unknown) =>
      Promise.resolve(resolve({ data: run(), error: null }))
    return builder
  }
  const client = {
    rpc: async (fn: string, params: Record<string, unknown>) => {
      if (fn !== 'search_food_trgm') throw new Error(`fixture: unexpected rpc ${fn}`)
      const call: RpcCall = {
        term: String(params.search_term),
        min_similarity: Number(params.min_similarity),
        max_results: Number(params.max_results),
        p_country: String(params.p_country),
      }
      calls.push(call)
      if (options.exactSearchError && call.min_similarity >= 0.9) {
        return { data: null, error: { message: options.exactSearchError } }
      }
      const window = WINDOWS[call.term]
      if (!window) throw new Error(`fixture: no window for "${call.term}"`)
      const rows = [...window, ...(options.withTail ? (TAIL[call.term] ?? []) : [])]
        .filter((row) => !(options.withoutRows ?? []).includes(row.id))
        .map((row) => ({ ...row, ...(options.changed?.[row.id] ?? {}) }))
        .filter((row) => row.similarity >= call.min_similarity)
        .slice(0, call.max_results)
      return { data: rows, error: null }
    },
    from: (name: string) => {
      tables.push(name)
      if (name === 'user_food_corrections') return table(options.corrections ?? [])
      if (name === 'meal_logs') return table(options.history ?? [])
      throw new Error(`fixture: unexpected table ${name}`)
    },
  }
  return {
    client: client as unknown as ServiceClient,
    calls,
    tables,
    exactSearches: () => calls.filter((call) => call.min_similarity >= 0.9),
    terms: () => calls.map((call) => call.term),
  }
}

const QA_ACCOUNT = '0b9f6f0e-0000-4000-8000-0000000000a1'
const WITHOUT_THE_TWO_ROWS = { withoutRows: [MILK_ROW_ID, WHEY_ROW_ID] }

/** What the phone sent on 2026-10-04: two items, grams typed by the patient. */
const REPORTED: MealItemInput[] = [
  { food_name: 'leite', quantity_g: 200 },
  { food_name: 'whey', quantity_g: 30 },
]

const MILK_200 = {
  food_name: 'leite integral',
  matched_taco_name: MILK_NAME,
  matched_taco_id: MILK_ROW_ID,
  quantity_g: 200,
  kcal: 122,
  protein_g: 6.3,
  carbs_g: 9.6,
  fat_g: 6.5,
  fiber_g: 0,
  similarity: 1,
  source: 'canonical_fuzzy',
  display_qty: 200,
  display_unit: 'ml',
}

const WHEY_30 = {
  food_name: 'whey protein em pó',
  matched_taco_name: WHEY_NAME,
  matched_taco_id: WHEY_ROW_ID,
  quantity_g: 30,
  kcal: 105.6,
  protein_g: 23.44,
  carbs_g: 1.88,
  fat_g: 0.47,
  fiber_g: 0.93,
  similarity: 1,
  source: 'canonical_fuzzy',
  display_qty: 30,
  display_unit: 'g',
}

/** The observation of the report, as the calculation returns it. */
function expectTheReportedFailure(result: MealCalcResult) {
  expect(result.items[0]).toMatchObject({
    food_name: 'leite',
    matched_taco_name: 'Leite, de coco',
    matched_taco_id: 666,
    quantity_g: 200,
    kcal: 332.3,
    protein_g: 2.02,
    carbs_g: 4.38,
    fat_g: 36.72,
    source: 'canonical_fuzzy',
    display_qty: 200,
    display_unit: 'ml',
  })
  expect(result.items[1]).toMatchObject({
    food_name: 'whey',
    matched_taco_name: 'Whey, acid, fluid',
    matched_taco_id: 4112,
    quantity_g: 30,
    kcal: 0,
    protein_g: 0,
    source: 'protein_mismatch',
  })
  expect(isUnresolvedNutritionSource(result.items[1]?.source)).toBe(true)
  expect(result.totals).toMatchObject({ kcal: 332.3, protein_g: 2, carbs_g: 4.4, fat_g: 36.7 })
  expect(result.user_warnings).toEqual([
    'Não tenho certeza sobre "whey" — esperava um alimento rico em proteína mas o valor encontrado não bate. Peça pro paciente confirmar ou detalhar. Não calculei as calorias desse item ainda.',
  ])
}

describe('audit 2026-10-04 — the exact report: leite 200 g and whey 30 g at dinner', () => {
  it('is whole milk and whey powder from their verified catalog rows: 227.6 kcal, nothing blocked', async () => {
    const db = staging()
    const result = await calcMealMacros(db.client, REPORTED, 'BR', QA_ACCOUNT)

    expect(result.items).toEqual([MILK_200, WHEY_30])
    expect(result.totals).toEqual({ kcal: 227.6, protein_g: 29.7, carbs_g: 11.5, fat_g: 7, fiber_g: 0.9 })
    expect(result.user_warnings).toEqual([])
    expect(result.items.some((item) => isUnresolvedNutritionSource(item.source))).toBe(false)
    // Coconut milk and dairy whey are never searched: the rows are read by name.
    expect(db.calls).toEqual([
      { term: MILK_NAME.toLowerCase(), min_similarity: 0.9, max_results: 5, p_country: 'BR' },
      { term: WHEY_NAME.toLowerCase(), min_similarity: 0.9, max_results: 5, p_country: 'BR' },
    ])
  })

  it('says in the audit trail that the item was assumed and that the client has not confirmed it', async () => {
    const result = await calcMealMacros(staging().client, REPORTED, 'BR', QA_ACCOUNT)
    expect(result.audit_warnings).toEqual([
      `"leite" assumido como "leite integral" (${MILK_NAME}; FDC:171265) — padrão do dia a dia, confirmação do cliente pendente.`,
      `"whey" assumido como "whey protein em pó" (${WHEY_NAME}; FDC:173180) — padrão do dia a dia, confirmação do cliente pendente.`,
    ])
  })

  it('takes every value from the catalog row, which equals the list entry', async () => {
    const result = await calcMealMacros(staging().client, REPORTED, 'BR')
    for (const [index, entry] of EVERYDAY_FOOD_DEFAULTS.entries()) {
      const item = result.items[index]
      const factor = (item?.quantity_g ?? 0) / 100
      expect(item?.food_name).toBe(entry.shown_as)
      expect(item?.matched_taco_name).toBe(entry.catalog_name)
      expect(item?.kcal).toBe(+(entry.per_100g.kcal * factor).toFixed(1))
      expect(item?.protein_g).toBe(+(entry.per_100g.protein_g * factor).toFixed(2))
      expect(item?.carbs_g).toBe(+(entry.per_100g.carbs_g * factor).toFixed(2))
      expect(item?.fat_g).toBe(+(entry.per_100g.fat_g * factor).toFixed(2))
    }
  })

  it('gives the same row and the same values to a patient of another country', async () => {
    const db = staging()
    const result = await calcMealMacros(db.client, REPORTED, 'US')
    expect(result.items).toEqual([MILK_200, WHEY_30])
    expect(db.calls.map((call) => call.p_country)).toEqual(['US', 'US'])
  })

  it('reads the typed name whatever its case and spacing', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'Leite', quantity_g: 200 },
        { food_name: ' WHEY ', quantity_g: 30 },
      ],
      'BR',
    )
    expect(result.items).toEqual([MILK_200, WHEY_30])
  })
})

describe('audit 2026-10-04 — without the catalog rows of the list nothing is invented', () => {
  it('a catalog without the two rows gives exactly the report: coconut milk 332.3 kcal and whey blocked', async () => {
    const db = staging(WITHOUT_THE_TWO_ROWS)
    const result = await calcMealMacros(db.client, REPORTED, 'BR')

    expectTheReportedFailure(result)
    expect(result.audit_warnings).toContain(
      '"leite" tem padrão do dia a dia (FDC:171265), mas a linha da lista não está no catálogo verificado com os mesmos valores — seguiu o cálculo normal.',
    )
    expect(result.audit_warnings).toContain(
      '"whey" tem padrão do dia a dia (FDC:173180), mas a linha da lista não está no catálogo verificado com os mesmos valores — seguiu o cálculo normal.',
    )
  })

  it('the rows below the six read on staging do not change the report', async () => {
    const result = await calcMealMacros(
      staging({ ...WITHOUT_THE_TWO_ROWS, withTail: true }).client,
      REPORTED,
      'BR',
    )
    expectTheReportedFailure(result)
  })

  it('a row whose values differ from the list is not used: the written numbers are the contract', async () => {
    for (const changed of [
      { kcal_per_100g: 64 },
      { protein_g: 3.3 },
      { carbs_g: 4.7 },
      { fat_g: 3.5 },
      { name_pt: 'Milk, whole, 3.25% milkfat, without added vitamin A and vitamin D' },
    ]) {
      const result = await calcMealMacros(
        staging({ changed: { [MILK_ROW_ID]: changed } }).client,
        [{ food_name: 'leite', quantity_g: 200 }],
        'BR',
      )
      expect(result.items[0], JSON.stringify(changed)).toMatchObject({
        food_name: 'leite',
        matched_taco_name: 'Leite, de coco',
        kcal: 332.3,
      })
    }
  })

  it('a failed catalog read fails the calculation, as every other catalog read does', async () => {
    await expect(
      calcMealMacros(staging({ exactSearchError: 'statement timeout' }).client, REPORTED, 'BR'),
    ).rejects.toThrow('statement timeout')
  })
})

/** The pending items as pipeline.ts and the app build them (name ← food_name). */
function asProposalItems(result: MealCalcResult, userKcalByName = new Map<string, number>()): MealItem[] {
  return result.items.map((item) => ({
    name: item.food_name,
    food_db_id: item.matched_taco_id,
    nutrition_source: item.source,
    quantity_g: item.quantity_g,
    display_qty: item.display_qty ?? null,
    display_unit: item.display_unit ?? null,
    kcal: item.kcal,
    ...(userKcalByName.has(item.food_name) ? { user_kcal: userKcalByName.get(item.food_name) } : {}),
    protein_g: item.protein_g,
    carbs_g: item.carbs_g,
    fat_g: item.fat_g,
  }))
}

/** What registra_refeicao runs first on a confirmation: the in-array dedup
 * over the arguments built from the pending (no patient text in the app). */
function confirmDedup(result: MealCalcResult, userKcalByName?: Map<string, number>) {
  const args = buildConfirmedMealArgs(
    { mealType: 'jantar', items: asProposalItems(result, userKcalByName) },
    false,
    '2026-10-04',
  )
  return dedupeMealItems(
    args.items.map((item) => ({
      ...item,
      approved_nutrition: {
        ...item.approved_nutrition,
        source: item.approved_nutrition.source ?? undefined,
      },
    })),
  )
}

const TWO_MILKS: MealItemInput[] = [
  { food_name: 'leite', quantity_g: 200 },
  { food_name: 'leite integral', quantity_g: 200 },
]

const MILK_400 = {
  ...MILK_200,
  quantity_g: 400,
  kcal: 244,
  protein_g: 12.6,
  carbs_g: 19.2,
  fat_g: 13,
  display_qty: 400,
}

describe('audit 2026-10-04 — two names of the same everyday item in one proposal (review finding)', () => {
  it('"leite" 200 g and "leite integral" 200 g are ONE line: leite integral 400 g, 244 kcal', async () => {
    const db = staging()
    const result = await calcMealMacros(db.client, TWO_MILKS, 'BR', QA_ACCOUNT)

    expect(result.items).toEqual([MILK_400])
    expect(result.totals).toEqual({ kcal: 244, protein_g: 12.6, carbs_g: 19.2, fat_g: 13, fiber_g: 0 })
    expect(result.user_warnings).toEqual([])
    // The row is read once and both quantities are priced from it.
    expect(db.calls).toEqual([
      { term: MILK_NAME.toLowerCase(), min_similarity: 0.9, max_results: 5, p_country: 'BR' },
    ])
    expect(result.input_indexes).toEqual([[0, 1]])
    expect(result.audit_warnings).toEqual([
      `"leite" assumido como "leite integral" (${MILK_NAME}; FDC:171265) — padrão do dia a dia, confirmação do cliente pendente.`,
      `"leite integral" assumido como "leite integral" (${MILK_NAME}; FDC:171265) — padrão do dia a dia, confirmação do cliente pendente.`,
      '"leite integral" (200 g) somado à linha "leite integral" já calculada nesta refeição: 400 g numa linha só.',
    ])
  })

  // The loss of the finding: the dedup of the confirmation read the two
  // identical lines as a repetition and kept one (244 shown, 122 recorded).
  it('the confirmation records what the proposal showed: one item of 400 g and 244 kcal, nothing collapsed', async () => {
    const result = await calcMealMacros(staging().client, TWO_MILKS, 'BR', QA_ACCOUNT)
    const confirm = confirmDedup(result)

    expect(confirm.duplicates).toEqual([])
    expect(confirm.items).toMatchObject([
      {
        food_name: 'leite integral',
        quantity_g: 400,
        approved_nutrition: { source: 'canonical_fuzzy', food_db_id: MILK_ROW_ID, kcal: 244 },
      },
    ])
    expect(confirm.items.reduce((sum, item) => sum + item.approved_nutrition.kcal, 0)).toBe(
      result.totals.kcal,
    )
  })

  it('"whey" 30 g and "whey protein em pó" 30 g are ONE line: whey protein em pó 60 g, 211.2 kcal', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'whey', quantity_g: 30 },
        { food_name: 'whey protein em pó', quantity_g: 30 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toEqual([
      {
        ...WHEY_30,
        quantity_g: 60,
        kcal: 211.2,
        protein_g: 46.88,
        carbs_g: 3.75,
        fat_g: 0.94,
        fiber_g: 1.86,
        display_qty: 60,
      },
    ])
    expect(result.totals.kcal).toBe(211.2)
    expect(confirmDedup(result).duplicates).toEqual([])
  })

  it('the same typed name twice is one line too: "leite" 200 g + "leite" 200 g = 400 g', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'Leite', quantity_g: 200 },
      ],
      'BR',
    )
    expect(result.items).toEqual([MILK_400])
    expect(result.input_indexes).toEqual([[0, 1]])
  })

  it('different grams are added the same way: 200 g + 100 g = 300 g, 183 kcal', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'leite integral', quantity_g: 100 },
      ],
      'BR',
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite integral', quantity_g: 300, kcal: 183, protein_g: 9.45, display_qty: 300 },
    ])
    expect(result.totals.kcal).toBe(183)
  })

  it('keeps the place of the first one and leaves the other items alone', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'whey', quantity_g: 30 },
        { food_name: 'leite integral', quantity_g: 200 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toEqual([MILK_400, WHEY_30])
    expect(result.totals).toEqual({ kcal: 349.6, protein_g: 36, carbs_g: 21.1, fat_g: 13.5, fiber_g: 0.9 })
    // Which input items each line answers for (the app pairs by position).
    expect(result.input_indexes).toEqual([[0, 2], [1]])
  })

  it('adds three or more items and both entries of the list in the same call', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [
        { food_name: 'whey', quantity_g: 30 },
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'whey protein em pó', quantity_g: 30 },
        { food_name: 'leite integral', quantity_g: 100 },
        { food_name: 'Leite', quantity_g: 50 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      { food_name: 'whey protein em pó', quantity_g: 60, kcal: 211.2 },
      { food_name: 'leite integral', quantity_g: 350, kcal: 213.5, display_qty: 350, display_unit: 'ml' },
    ])
    // 61 × 3.5 + 352 × 0.6: the totals hold only the summed lines.
    expect(result.totals.kcal).toBe(424.7)
    expect(result.input_indexes).toEqual([
      [0, 2],
      [1, 3, 4],
    ])
    expect(db.calls).toHaveLength(2)
  })

  it('reports no pairing when nothing was added into one line', async () => {
    const result = await calcMealMacros(staging().client, REPORTED, 'BR', QA_ACCOUNT)
    expect(result).not.toHaveProperty('input_indexes')
  })

  // Nothing is invented: without the row there is no everyday line to add
  // to, and the two names are priced as before the list existed (HEAD).
  it('without the catalog row the two names stay two lines, as before: 332.3 + 224.9 = 557.2 kcal', async () => {
    const db = staging(WITHOUT_THE_TWO_ROWS)
    const result = await calcMealMacros(db.client, TWO_MILKS, 'BR')

    expect(result.items).toMatchObject([
      { food_name: 'leite', matched_taco_name: 'Leite, de coco', quantity_g: 200, kcal: 332.3 },
      {
        food_name: 'leite integral',
        matched_taco_name: 'Canjica, com leite integral',
        quantity_g: 200,
        kcal: 224.9,
      },
    ])
    expect(result.totals.kcal).toBe(557.2)
    expect(result).not.toHaveProperty('input_indexes')
    expect(confirmDedup(result).duplicates).toEqual([])
  })

  // Declared pendency: only everyday lines are added. Equal names off the
  // list are the limit that existed before this change, and it is unchanged.
  it('declared: two equal items off the list stay two lines and the confirmation keeps one', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'leite de coco', quantity_g: 100 },
        { food_name: 'leite de coco', quantity_g: 100 },
      ],
      'BR',
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite de coco', quantity_g: 100, kcal: 166.2 },
      { food_name: 'leite de coco', quantity_g: 100, kcal: 166.2 },
    ])
    expect(result.totals.kcal).toBe(332.4)
    expect(result).not.toHaveProperty('input_indexes')

    const confirm = confirmDedup(result)
    expect(confirm.items).toMatchObject([{ food_name: 'leite de coco', quantity_g: 100 }])
    expect(confirm.duplicates).toEqual([
      { food_name: 'leite de coco', repeated: 2, result_g: 100, strategy: 'collapsed_identical' },
    ])
  })

  // Declared pendency: the patient's own number is never added into the
  // catalog line, so the shown name appears twice and the confirmation's
  // dedup refuses the two different lines.
  it('declared: "leite" 200 g beside "leite integral" 200 g with the kcal the patient stated', async () => {
    const result = await calcMealMacros(
      staging().client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'leite integral', quantity_g: 200, user_kcal: 90 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite integral', quantity_g: 200, kcal: 122, source: 'canonical_fuzzy' },
      { food_name: 'leite integral', quantity_g: 200, kcal: 90, source: 'user_kcal' },
    ])
    expect(result.totals.kcal).toBe(212)
    expect(result).not.toHaveProperty('input_indexes')
    expect(() => confirmDedup(result, new Map([['leite integral', 90]]))).toThrow(
      'conflito nutricional entre cópias de leite integral',
    )
  })

  // Declared pendency, the variant of the second review of 2026-10-04 (LOW):
  // the other line gets the shown name from the patient's own ACTIVE
  // correction with its own values ("leite desnatado" → "leite integral",
  // 35 kcal/100 g). Reproduced by the reviewer through the app service; here
  // through the real calculation and the real dedup of the confirmation. The
  // macros other than the kcal are synthetic. On commit 9624cd5 the first line
  // was coconut milk under the typed name "leite" (332.3 kcal), the names
  // differed and both lines were recorded (402.3 kcal).
  const SKIM_AS_WHOLE: Correction = {
    said_name: 'leite desnatado',
    corrected_to: 'leite integral',
    custom_kcal_per_100g: 35,
    custom_protein_g: 3.4,
    custom_carbs_g: 5,
    custom_fat_g: 0.2,
    status: 'active',
    confirmed_count: 2,
  }

  it('declared: "leite" 200 g beside "leite desnatado" 200 g that an active correction of the patient renames to "leite integral"', async () => {
    const result = await calcMealMacros(
      staging({ corrections: [SKIM_AS_WHOLE] }).client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'leite desnatado', quantity_g: 200 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite integral', quantity_g: 200, kcal: 122, source: 'canonical_fuzzy' },
      { food_name: 'leite integral', quantity_g: 200, kcal: 70, source: 'user_correction' },
    ])
    expect(result.totals.kcal).toBe(192)
    expect(result).not.toHaveProperty('input_indexes')
    expect(() => confirmDedup(result)).toThrow(
      'conflito nutricional entre cópias de leite integral',
    )
  })

  it('declared: the same correction with different grams (200 g and 150 g) — two lines on the proposal, one line of 350 g and 174.5 kcal at the confirmation', async () => {
    const result = await calcMealMacros(
      staging({ corrections: [SKIM_AS_WHOLE] }).client,
      [
        { food_name: 'leite', quantity_g: 200 },
        { food_name: 'leite desnatado', quantity_g: 150 },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite integral', quantity_g: 200, kcal: 122, source: 'canonical_fuzzy' },
      { food_name: 'leite integral', quantity_g: 150, kcal: 52.5, source: 'user_correction' },
    ])
    expect(result.totals.kcal).toBe(174.5)

    const confirm = confirmDedup(result)
    expect(confirm.items).toHaveLength(1)
    expect(confirm.items[0]).toMatchObject({ food_name: 'leite integral', quantity_g: 350 })
    expect(confirm.items[0]?.approved_nutrition).toMatchObject({ kcal: 174.5 })
  })
})

describe('audit 2026-10-04 — the revert switch', () => {
  afterEach(() => {
    vi.doUnmock('../everyday-food-defaults.js')
    vi.resetModules()
  })

  // The production code with the list emptied (the one-line switch).
  async function revertedPipeline() {
    vi.resetModules()
    vi.doMock('../everyday-food-defaults.js', async (importOriginal) => {
      const actual = await importOriginal<typeof import('../everyday-food-defaults.js')>()
      return {
        ...actual,
        EVERYDAY_FOOD_DEFAULTS: [],
        everydayFoodDefault: (name: string) => actual.everydayFoodDefault(name, []),
      }
    })
    return import('../meal-pipeline.js')
  }

  // The production lookup with an empty list, on the staging catalog that
  // holds the two rows: the calculation is the one of before this change.
  it('with an empty list the report comes back and the rows are never read', async () => {
    const reverted = await revertedPipeline()
    const db = staging()
    const result = await reverted.calcMealMacros(db.client, REPORTED, 'BR')

    expectTheReportedFailure(result)
    expect(db.exactSearches()).toEqual([])
    expect(result.audit_warnings.join(' ')).not.toContain('padrão do dia a dia')
  })

  it('with an empty list nothing is added into one line: the two names are two lines again', async () => {
    const reverted = await revertedPipeline()
    const db = staging()
    const result = await reverted.calcMealMacros(db.client, TWO_MILKS, 'BR')

    expect(result.items).toMatchObject([
      { food_name: 'leite', matched_taco_name: 'Leite, de coco', quantity_g: 200, kcal: 332.3 },
      {
        food_name: 'leite integral',
        matched_taco_name: 'Canjica, com leite integral',
        quantity_g: 200,
        kcal: 224.9,
      },
    ])
    expect(result.totals.kcal).toBe(557.2)
    expect(result).not.toHaveProperty('input_indexes')
    expect(db.exactSearches()).toEqual([])
  })

  // What the switch does NOT undo (review finding, executed on the reverted
  // tree): the records written under the rule stay, and for 30 days the
  // patient's own history answers for the shown name.
  it('does not undo what was recorded: "leite integral" keeps coming from the patient\'s own record', async () => {
    const reverted = await revertedPipeline()
    const recordedUnderTheRule: HistoryRow[] = [
      {
        id: 'meal-log-leite-integral',
        food_name: 'leite integral',
        food_db_id: MILK_ROW_ID,
        quantity_g: 200,
        kcal: 122,
        protein_g: 6.3,
        carbs_g: 9.6,
        fat_g: 6.5,
        source: 'canonical_fuzzy',
        food_db: { is_verified: true },
      },
    ]
    const ONLY_WHOLE_MILK: MealItemInput[] = [{ food_name: 'leite integral', quantity_g: 200 }]

    const withRecord = await reverted.calcMealMacros(
      staging({ history: recordedUnderTheRule }).client,
      ONLY_WHOLE_MILK,
      'BR',
      QA_ACCOUNT,
    )
    expect(withRecord.items[0]).toMatchObject({
      food_name: 'leite integral',
      matched_taco_id: MILK_ROW_ID,
      kcal: 122,
      source: 'history',
    })

    // A patient without that record gets the calculation of before (F23).
    const withoutRecord = await reverted.calcMealMacros(
      staging().client,
      ONLY_WHOLE_MILK,
      'BR',
      QA_ACCOUNT,
    )
    expect(withoutRecord.items[0]).toMatchObject({
      food_name: 'leite integral',
      matched_taco_name: 'Canjica, com leite integral',
      kcal: 224.9,
      source: 'canonical_fuzzy',
    })

    // The typed "leite" goes back to coconut milk at once, record or not.
    const typed = await reverted.calcMealMacros(
      staging({ history: recordedUnderTheRule }).client,
      [{ food_name: 'leite', quantity_g: 200 }],
      'BR',
      QA_ACCOUNT,
    )
    expect(typed.items[0]).toMatchObject({
      food_name: 'leite',
      matched_taco_name: 'Leite, de coco',
      kcal: 332.3,
    })
  })
})

describe('audit 2026-10-04 — what the withdrawn catalog aliases broke stays as it was', () => {
  it('"salada com azeite" 200 g is still 41.1 kcal of salad, not half oil', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'salada com azeite', quantity_g: 200 }],
      'BR',
    )
    expect(result.items).toEqual([
      {
        food_name: 'salada com azeite',
        matched_taco_name: 'Tomate, salada (parcial)',
        matched_taco_id: null,
        quantity_g: 200,
        kcal: 41.1,
        protein_g: 1.62,
        carbs_g: 10.24,
        fat_g: 0,
        fiber_g: 4.54,
        similarity: 0.5,
        source: 'canonical_composite_partial',
        display_qty: 200,
        display_unit: 'g',
      },
    ])
    expect(result.user_warnings).toEqual([
      'Calculei "salada com azeite" usando só [Tomate, salada] — não identifiquei a parte "azeite". Se faltou algo importante, me corrija com o nome certo dessa parte e a quantidade.',
    ])
    expect(db.exactSearches()).toEqual([])
  })

  it('a bare "ovo" 50 g is still one egg of 73 kcal, with no preparation question', async () => {
    const db = staging()
    const result = await calcMealMacros(db.client, [{ food_name: 'ovo', quantity_g: 50 }], 'BR')
    expect(result.items).toEqual([
      {
        food_name: 'ovo',
        matched_taco_name: '[estimativa ovo]',
        matched_taco_id: null,
        quantity_g: 50,
        kcal: 73,
        protein_g: 6.65,
        carbs_g: 0.3,
        fat_g: 4.75,
        fiber_g: 0,
        similarity: 0,
        source: 'llm_estimate',
        display_qty: 1,
        display_unit: 'unidade',
      },
    ])
    expect(result.items[0]).not.toHaveProperty('preparation_options')
    expect(result.user_warnings).toEqual([])
    expect(db.exactSearches()).toEqual([])
  })

  it('"arroz branco" 150 g still asks cru or cozido (decision of 2026-09-28)', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'arroz branco', quantity_g: 150 }],
      'BR',
    )
    expect(result.items).toEqual([
      {
        food_name: 'arroz branco',
        matched_taco_name: '',
        matched_taco_id: null,
        quantity_g: 150,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        fiber_g: 0,
        similarity: 0,
        source: 'no_match',
        preparation_options: ['cru', 'cozido'],
      },
    ])
    expect(result.user_warnings).toEqual([
      'Não sei se "arroz branco" era cru ou cozido — as calorias mudam muito conforme o preparo. Informe o preparo no nome do item para eu calcular. Não calculei as calorias desse item ainda.',
    ])
    expect(db.terms()).toEqual(['arroz branco'])
  })

  it('"leite de coco" 100 g is still coconut milk', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'leite de coco', quantity_g: 100 }],
      'BR',
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'leite de coco',
      matched_taco_id: 666,
      kcal: 166.2,
      fat_g: 18.36,
      source: 'canonical_fuzzy',
    })
    expect(db.exactSearches()).toEqual([])
  })

  // Declared pendency: the single item of the WhatsApp reports is unchanged.
  // Its parts are resolved by the catalog search alone, never by the list.
  it('the single item "leite com whey" 300 g is still not calculated', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'leite com whey', quantity_g: 300 }],
      'BR',
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'leite com whey',
      kcal: 0,
      source: 'composite_rejected',
    })
    expect(result.user_warnings).toEqual([
      'Não consegui identificar "leite com whey" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: "leite 250ml" e "whey 30g"). Não foi possível calcular as calorias desse item ainda.',
    ])
    expect(db.exactSearches()).toEqual([])
    expect(new Set(db.terms())).toEqual(new Set(['leite com whey', 'leite', 'whey']))
  })
})

describe('audit 2026-10-04 — the shown name sent back by the app', () => {
  it('"leite integral" 200 g and "whey protein em pó" 30 g resolve to the same rows and values', async () => {
    const first = await calcMealMacros(staging().client, REPORTED, 'BR', QA_ACCOUNT)
    // The edit screen re-sends item.name of every item of the proposal.
    const resent = first.items.map((item) => ({ food_name: item.food_name, quantity_g: item.quantity_g }))
    expect(resent).toEqual([
      { food_name: 'leite integral', quantity_g: 200 },
      { food_name: 'whey protein em pó', quantity_g: 30 },
    ])
    const second = await calcMealMacros(staging().client, resent, 'BR', QA_ACCOUNT)
    expect(second.items).toEqual(first.items)
    expect(second.totals).toEqual(first.totals)
  })

  it('the patient changes the grams of the shown item: same row, new quantity', async () => {
    const result = await calcMealMacros(
      staging().client,
      [{ food_name: 'leite integral', quantity_g: 250 }],
      'BR',
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'leite integral',
      matched_taco_id: MILK_ROW_ID,
      kcal: 152.5,
      protein_g: 7.88,
      display_qty: 250,
      display_unit: 'ml',
    })
  })

  // Finding F23 of round 1 (same day): "leite integral" 200 ml was priced as
  // "Canjica, com leite integral". That is what the name gives without the row.
  it('without the row, "leite integral" 200 g is the 224.9 kcal of finding F23', async () => {
    const result = await calcMealMacros(
      staging(WITHOUT_THE_TWO_ROWS).client,
      [
        { food_name: 'leite integral', quantity_g: 200 },
        { food_name: 'whey protein em pó', quantity_g: 30 },
      ],
      'BR',
    )
    expect(result.items[0]).toMatchObject({
      food_name: 'leite integral',
      matched_taco_name: 'Canjica, com leite integral',
      matched_taco_id: 177,
      kcal: 224.9,
      carbs_g: 47.26,
      source: 'canonical_fuzzy',
    })
    expect(result.items[1]).toMatchObject({
      food_name: 'whey protein em pó',
      matched_taco_name: '[estimativa whey]',
      kcal: 105.6,
      protein_g: 23.4,
      source: 'llm_estimate',
    })
  })
})

describe('audit 2026-10-04 — precedence of the everyday default', () => {
  const correction = (status: Correction['status'], confirmed_count: number): Correction => ({
    said_name: 'leite',
    corrected_to: 'leite de cabra',
    custom_kcal_per_100g: null,
    custom_protein_g: null,
    custom_carbs_g: null,
    custom_fat_g: null,
    status,
    confirmed_count,
  })
  const ONLY_MILK: MealItemInput[] = [{ food_name: 'leite', quantity_g: 200 }]

  it("the patient's own active correction wins", async () => {
    const db = staging({ corrections: [correction('active', 2)] })
    const result = await calcMealMacros(db.client, ONLY_MILK, 'BR', QA_ACCOUNT)
    expect(result.items[0]).toMatchObject({
      food_name: 'leite de cabra',
      matched_taco_name: 'Leite, de cabra',
      matched_taco_id: 602,
      kcal: 132.8,
      source: 'canonical_fuzzy',
    })
    expect(db.exactSearches()).toEqual([])
  })

  it("the patient's own values for the food win", async () => {
    const db = staging({
      corrections: [
        {
          ...correction('active', 2),
          corrected_to: 'leite desnatado da fazenda',
          custom_kcal_per_100g: 35,
          custom_protein_g: 3.4,
          custom_carbs_g: 5,
          custom_fat_g: 0.2,
        },
      ],
    })
    const result = await calcMealMacros(db.client, ONLY_MILK, 'BR', QA_ACCOUNT)
    expect(result.items[0]).toMatchObject({
      food_name: 'leite desnatado da fazenda',
      kcal: 70,
      source: 'user_correction',
    })
    expect(db.calls).toEqual([])
  })

  it('a correction seen only once does not replace the default', async () => {
    const result = await calcMealMacros(
      staging({ corrections: [correction('learning', 1)] }).client,
      ONLY_MILK,
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toEqual([MILK_200])
  })

  // Step 4 of the precedence written in docs/CALCULO-MPP.md §9b: an active
  // correction without values of its own only renames the item, and the new
  // name goes on through the rest of the calculation. When the new name is a
  // said name it takes the default. The said name "leitinho" is synthetic.
  it('an active correction that renames to a said name takes the default of the new name', async () => {
    const db = staging({
      corrections: [{ ...correction('active', 2), said_name: 'leitinho', corrected_to: 'leite' }],
    })
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'leitinho', quantity_g: 200 }],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toEqual([MILK_200])
    expect(result.audit_warnings).toEqual([
      '"leitinho" remapeado pra "leite" via correção aprendida do paciente.',
      `"leite" assumido como "leite integral" (${MILK_NAME}; FDC:171265) — padrão do dia a dia, confirmação do cliente pendente.`,
    ])
  })

  it('the kcal the patient stated wins, and the item keeps the typed name', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [{ food_name: 'leite', quantity_g: 200, user_kcal: 90 }],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items[0]).toMatchObject({ food_name: 'leite', kcal: 90, source: 'user_kcal' })
    expect(db.exactSearches()).toEqual([])
  })

  it('the nutrition approved on a pending is persisted as shown, with no catalog read', async () => {
    const db = staging()
    const result = await calcMealMacros(
      db.client,
      [
        {
          food_name: 'leite integral',
          quantity_g: 200,
          approved_nutrition: {
            source: 'canonical_fuzzy',
            food_db_id: MILK_ROW_ID,
            kcal: 122,
            protein_g: 6.3,
            carbs_g: 9.6,
            fat_g: 6.5,
          },
        },
        {
          food_name: 'whey protein em pó',
          quantity_g: 30,
          approved_nutrition: {
            source: 'canonical_fuzzy',
            food_db_id: WHEY_ROW_ID,
            kcal: 105.6,
            protein_g: 23.44,
            carbs_g: 1.88,
            fat_g: 0.47,
          },
        },
      ],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      { food_name: 'leite integral', matched_taco_id: MILK_ROW_ID, kcal: 122, source: 'canonical_fuzzy' },
      { food_name: 'whey protein em pó', matched_taco_id: WHEY_ROW_ID, kcal: 105.6, source: 'canonical_fuzzy' },
    ])
    expect(result.totals).toMatchObject({ kcal: 227.6, protein_g: 29.7, carbs_g: 11.5, fat_g: 7 })
    expect(db.calls).toEqual([])
  })

  // The wrong match confirmed once would otherwise come back from the history.
  it('a "leite" already confirmed as coconut milk does not come back from the history', async () => {
    const history: HistoryRow[] = [
      {
        id: 'meal-log-leite-de-coco',
        food_name: 'leite',
        food_db_id: 666,
        quantity_g: 200,
        kcal: 332.3,
        protein_g: 2.02,
        carbs_g: 4.38,
        fat_g: 36.72,
        source: 'canonical_fuzzy',
        food_db: { is_verified: true },
      },
    ]
    const withRows = staging({ history })
    expect((await calcMealMacros(withRows.client, ONLY_MILK, 'BR', QA_ACCOUNT)).items).toEqual([
      MILK_200,
    ])
    expect(withRows.tables).not.toContain('meal_logs')

    // Without the row, the history still answers as it did before.
    const withoutRows = staging({ ...WITHOUT_THE_TWO_ROWS, history })
    const before = await calcMealMacros(withoutRows.client, ONLY_MILK, 'BR', QA_ACCOUNT)
    expect(before.items[0]).toMatchObject({ food_name: 'leite', kcal: 332.3, source: 'history' })
  })
})

describe('audit 2026-10-04 — the typed name still points to the shown item (WhatsApp flows)', () => {
  // The pending edit, the item-scoped correction and the 30-minute correction
  // link what the patient typed to the stored item with these two helpers.
  it('every shown name refers to the same item as each said name', () => {
    for (const entry of EVERYDAY_FOOD_DEFAULTS) {
      for (const said of entry.said) {
        expect(foodNamesReferToSameItem(entry.shown_as, said), `${said} / ${entry.shown_as}`).toBe(true)
      }
    }
  })

  it('a correction that says "leite" and "whey" targets the record stored with the shown names', () => {
    const consumed_at = '2026-10-04T22:30:00.000Z'
    const target = selectMealReplacementTarget({
      recentLogs: [
        { id: 'log-1', food_name: 'leite integral', meal_type: 'jantar', consumed_at, raw_provider_message_id: 'm-1' },
        { id: 'log-2', food_name: 'whey protein em pó', meal_type: 'jantar', consumed_at, raw_provider_message_id: 'm-1' },
      ],
      newFoodNames: ['leite', 'whey'],
    })
    expect(target).toMatchObject({ status: 'selected', logIds: ['log-1', 'log-2'], overlapRatio: 1 })
  })

  // Declared pendency: with a second item that also contains "leite" the
  // typed name no longer has an exact row and the target is ambiguous.
  it('declared: two milk items in the same record make the typed "leite" ambiguous', () => {
    const consumed_at = '2026-10-04T22:30:00.000Z'
    const rows = (milk: string) => [
      { id: 'log-1', food_name: milk, meal_type: 'cafe', consumed_at, raw_provider_message_id: 'm-1' },
      { id: 'log-2', food_name: 'leite em pó', meal_type: 'cafe', consumed_at, raw_provider_message_id: 'm-1' },
    ]
    // Stored as typed (before this change): the exact row is the target.
    expect(
      selectMealReplacementTarget({ recentLogs: rows('leite'), newFoodNames: ['leite'] }),
    ).toMatchObject({ status: 'selected', logIds: ['log-1'] })
    // Stored with the shown name: both rows only contain the typed name.
    expect(
      selectMealReplacementTarget({ recentLogs: rows('leite integral'), newFoodNames: ['leite'] }),
    ).toMatchObject({ status: 'ambiguous' })
  })
})

describe('audit 2026-10-04 — what the patient reads', () => {
  it('the WhatsApp proposal names the assumed items and adds no warning', async () => {
    const result = await calcMealMacros(staging().client, REPORTED, 'BR', QA_ACCOUNT)
    // Field by field as pipeline.ts builds the pending (name ← food_name).
    const items: MealItem[] = result.items.map((item) => ({
      name: item.food_name,
      food_db_id: item.matched_taco_id,
      nutrition_source: item.source,
      quantity_g: item.quantity_g,
      display_qty: item.display_qty ?? null,
      display_unit: item.display_unit ?? null,
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
    }))
    const confirmationNotes = buildPendingNutritionConfirmationNotes(items)
    expect(confirmationNotes).toEqual([])

    const message = composePendingProposal('pending-1', {
      kind: 'meal',
      mealType: 'jantar',
      items,
      totals: {
        kcal: result.totals.kcal,
        protein_g: result.totals.protein_g,
        carbs_g: result.totals.carbs_g,
        fat_g: result.totals.fat_g,
      },
      sourceContentType: 'text',
      confirmationNotes,
    })
    expect(message.body).toBe(
      [
        'Entendi isso pro seu Jantar:',
        '',
        '• leite integral (200 ml) — 122 kcal',
        '• whey protein em pó (30g) — 106 kcal',
        '',
        'Total: 228 kcal | 29.7g proteína | 11.5g carboidrato | 7g gordura',
        '',
        'Confirma?',
      ].join('\n'),
    )
  })

  // A number the client has already seen (docs/CALCULO-MPP.md §9c): the card
  // he pasted on 14/07/2026 showed "leite integral (240 ml) — 146 kcal". The
  // line and the value were read in the rule map of this audit; the print
  // itself was not read again. The verified row gives 146.4 kcal and the
  // line still reads 146.
  it('"leite integral" 240 ml still reads 146 kcal on the WhatsApp proposal', async () => {
    const result = await calcMealMacros(
      staging().client,
      [{ food_name: 'leite integral', quantity_g: 240 }],
      'BR',
      QA_ACCOUNT,
    )
    expect(result.items).toMatchObject([
      {
        food_name: 'leite integral',
        matched_taco_id: MILK_ROW_ID,
        kcal: 146.4,
        display_qty: 240,
        display_unit: 'ml',
      },
    ])

    const items: MealItem[] = result.items.map((item) => ({
      name: item.food_name,
      food_db_id: item.matched_taco_id,
      nutrition_source: item.source,
      quantity_g: item.quantity_g,
      display_qty: item.display_qty ?? null,
      display_unit: item.display_unit ?? null,
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
    }))
    const message = composePendingProposal('pending-2', {
      kind: 'meal',
      mealType: 'jantar',
      items,
      totals: {
        kcal: result.totals.kcal,
        protein_g: result.totals.protein_g,
        carbs_g: result.totals.carbs_g,
        fat_g: result.totals.fat_g,
      },
      sourceContentType: 'text',
      confirmationNotes: buildPendingNutritionConfirmationNotes(items),
    })
    expect(message.body).toContain('• leite integral (240 ml) — 146 kcal')
  })
})
