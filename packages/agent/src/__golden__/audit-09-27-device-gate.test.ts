/**
 * Golden tests — meal proposal from the staging device gate of 2026-09-27
 * (QA account A, iPhone, text registration, backend b7c46f45).
 *
 * Exact scenario, not a nearby variant: the app sent three items parsed from
 *   "Arroz branco 150 g" / "Feijão carioca 86,5 g" / "Frango grelhado 120 g"
 * and the server proposed (pending f836d0b3…, then b193680e…):
 *   - Arroz branco  150 g  -> food_db 673 "Bolinho de arroz"  410.3 kcal (canonical_fuzzy)
 *   - Feijão carioca 86.5 g -> food_db 704 "Feijão, carioca, cru" 284.6 kcal (canonical_fuzzy)
 *   - Frango grelhado 120 g -> food_db 7 "frango grelhado" 191 kcal (canonical_exact)
 *
 * The candidate windows for the three incident terms and for the adversarial
 * review neighbours are the exact rows returned by the staging RPC
 * search_food_trgm(search_term, 0.2, 20, 'BR') on 2026-09-28 (public TACO
 * catalog data; no patient data). The other neighbour windows keep only their
 * leading rows (results are the same with the full windows).
 *
 * Expected results come from the approved source (TACO IV) and from the
 * product decision of 2026-09-28 (Eduardo): when the patient does not say how
 * the food was prepared and the energy of the same food changes by 50% or
 * more between preparations, the system asks instead of choosing.
 */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { calcMealMacros } from '../meal-pipeline.js'

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

const CEREAIS = 'Cereais e derivados'
const PREPARADOS = 'Alimentos preparados'
const VERDURAS = 'Verduras, hortaliças e derivados'
const LEGUMINOSAS = 'Leguminosas e derivados'
const CARNES = 'Carnes e derivados'
const PESCADOS = 'Pescados e frutos do mar'

const STAGING_WINDOWS: Record<string, Row[]> = {
  'arroz branco': [
    r(673, 'Bolinho de arroz', PREPARADOS, 0.3043, 273.51, 8.04, 41.68, 8.29, 2.74),
    r(306, 'Repolho, branco, cru', VERDURAS, 0.28, 17.12, 0.88, 3.86, 0.14, 1.89),
    r(669, 'Arroz carreteiro', PREPARADOS, 0.2609, 153.77, 10.83, 11.58, 7.12, 1.5),
    r(161, 'Arroz, tipo 1, cru', CEREAIS, 0.25, 357.79, 7.16, 78.76, 0.34, 1.64),
    r(163, 'Arroz, tipo 2, cru', CEREAIS, 0.25, 358.12, 7.24, 78.88, 0.28, 1.72),
    r(184, 'Creme de arroz, pó', CEREAIS, 0.24, 386, 7.03, 83.87, 1.23, 1.07),
    r(159, 'Arroz, integral, cru', CEREAIS, 0.2308, 359.68, 7.32, 77.45, 1.86, 4.82),
    r(644, 'Cocada branca', 'Produtos açucarados', 0.2273, 448.85, 1.12, 81.38, 13.59, 3.57),
    r(160, 'Arroz, tipo 1, cozido', CEREAIS, 0.2222, 128.26, 2.52, 28.06, 0.23, 1.56),
    r(162, 'Arroz, tipo 2, cozido', CEREAIS, 0.2222, 130.12, 2.57, 28.19, 0.36, 1.07),
    r(158, 'Arroz, integral, cozido', CEREAIS, 0.2069, 123.53, 2.59, 25.81, 1, 2.75),
  ],
  'feijão carioca': [
    r(704, 'Feijão, carioca, cru', LEGUMINOSAS, 0.8333, 329.03, 19.98, 61.22, 1.26, 18.42),
    r(703, 'Feijão, carioca, cozido', LEGUMINOSAS, 0.7143, 76.42, 4.78, 13.59, 0.54, 8.51),
    r(708, 'Feijão, jalo, cru', LEGUMINOSAS, 0.3478, 327.91, 20.1, 61.48, 0.95, 30.32),
    r(716, 'Feijão, roxo, cru', LEGUMINOSAS, 0.3478, 331.41, 22.17, 59.99, 1.24, 33.84),
    r(282, 'Feijão, broto, cru', VERDURAS, 0.3333, 38.72, 4.17, 7.76, 0.1, 1.97),
    r(710, 'Feijão, preto, cru', LEGUMINOSAS, 0.3333, 323.57, 21.34, 58.75, 1.24, 21.83),
    r(712, 'Feijão, rajado, cru', LEGUMINOSAS, 0.32, 325.84, 17.27, 62.93, 1.17, 24.01),
    r(706, 'Feijão, fradinho, cru', LEGUMINOSAS, 0.3077, 339.16, 20.21, 61.24, 2.37, 23.59),
    r(707, 'Feijão, jalo, cozido', LEGUMINOSAS, 0.3077, 92.74, 6.14, 16.5, 0.51, 13.87),
    r(714, 'Feijão, rosinha, cru', LEGUMINOSAS, 0.3077, 336.96, 20.92, 62.22, 1.33, 20.63),
    r(715, 'Feijão, roxo, cozido', LEGUMINOSAS, 0.3077, 76.89, 5.72, 12.91, 0.54, 11.51),
    r(709, 'Feijão, preto, cozido', LEGUMINOSAS, 0.2963, 77.03, 4.48, 14.01, 0.54, 8.4),
    r(711, 'Feijão, rajado, cozido', LEGUMINOSAS, 0.2963, 84.7, 5.54, 15.27, 0.4, 9.32),
    r(705, 'Feijão, fradinho, cozido', LEGUMINOSAS, 0.2759, 78.01, 5.09, 13.5, 0.64, 7.47),
    r(713, 'Feijão, rosinha, cozido', LEGUMINOSAS, 0.2759, 67.87, 4.54, 11.82, 0.48, 4.76),
    r(682, 'Feijão tropeiro mineiro', PREPARADOS, 0.2414, 151.56, 10.17, 19.58, 6.79, 3.57),
    r(670, 'Baião de dois, arroz e feijão-de-corda', PREPARADOS, 0.2, 135.68, 6.24, 20.42, 3.23, 5.07),
  ],
  'frango grelhado': [
    r(7, 'frango grelhado', CARNES, 1, 159.19, 32.03, 0, 2.48, null),
    r(8543, 'frango grelhado', 'Poultry Products', 1, 151, 30.54, 0, 3.17, 0, 'US'),
    r(544, 'Frango, coração, grelhado', CARNES, 0.6667, 207.27, 22.44, 0.61, 12.1, null),
    r(559, 'Frango, peito, sem pele, grelhado', CARNES, 0.5517, 159.19, 32.03, 0, 2.48, null),
    r(569, 'Lingüiça, frango, grelhada', CARNES, 0.5185, 243.66, 18.19, 0, 18.4, null),
    r(462, 'Pintado, grelhado', PESCADOS, 0.4091, 152.19, 30.8, 0, 2.29, null),
    r(549, 'Frango, fígado, cru', CARNES, 0.375, 106.48, 17.59, 0, 3.49, null),
    r(8544, 'frango frito', 'Poultry Products', 0.35, 219, 30.57, 1.69, 9.12, 0.1),
    r(8545, 'frango frito', 'Poultry Products', 0.35, 219, 30.57, 1.69, 9.12, 0.1, 'US'),
    r(466, 'Salmão, sem pele, fresco, grelhado', PESCADOS, 0.3056, 242.71, 26.14, 0, 14.53, null),
    r(505, 'Carne, bovina, fígado, grelhado', CARNES, 0.303, 225.03, 29.86, 4.2, 9.01, null),
    r(425, 'Abadejo, filé, congelado, grelhado', PESCADOS, 0.2778, 129.64, 27.61, 0, 1.3, null),
    r(464, 'Salmão, filé, com pele, fresco,  grelhado', PESCADOS, 0.275, 228.73, 23.92, 0, 14.04, null),
    r(555, 'Frango, peito, com pele, assado', CARNES, 0.2647, 211.68, 33.42, 0, 7.65, null),
    r(566, 'Hambúrguer, bovino, grelhado', CARNES, 0.2647, 209.83, 13.16, 11.33, 12.43, null),
    r(543, 'Frango, coração, cru', CARNES, 0.2593, 221.5, 12.58, 0, 18.6, null),
    r(683, 'Frango, com açafrão', PREPARADOS, 0.2593, 112.78, 9.7, 4.06, 6.17, 0.22),
    r(689, 'Salpicão, de frango', PREPARADOS, 0.25, 147.86, 13.93, 4.57, 7.84, 0.41),
    r(568, 'Lingüiça, frango, frita', CARNES, 0.2414, 245.46, 18.32, 0, 18.54, null),
    r(552, 'Frango, inteiro, sem pele, assado', CARNES, 0.2368, 187.34, 28.03, 0, 7.5, null),
  ],
  // Adversarial review neighbours (full staging windows): other foods in the
  // window that share a word must not trigger the preparation question.
  manteiga: [
    r(417, 'Manteiga, sem sal', 'Gorduras e óleos', 0.5625, 757.54, 0.4, 0, 86.04, null),
    r(416, 'Manteiga, com sal', 'Gorduras e óleos', 0.5294, 725.97, 0.41, 0.06, 82.36, null),
    r(272, 'Couve, manteiga, crua', VERDURAS, 0.4737, 27.06, 2.87, 4.33, 0.55, 3.12),
    r(693, 'Tapioca, com manteiga', PREPARADOS, 0.4286, 347.83, 0.09, 63.59, 10.91, 0),
    r(273, 'Couve, manteiga, refogada', VERDURAS, 0.375, 90.34, 1.67, 8.71, 6.59, 5.74),
    r(341, 'Cajá-Manga, cru', 'Frutas e derivados', 0.2105, 45.58, 1.28, 11.43, 0, 2.58),
    r(685, 'Maniçoba', PREPARADOS, 0.2, 134.22, 9.96, 3.42, 8.7, 2.16),
  ],
  'chá preto': [
    r(622, 'Chá, preto, infusão 5%', 'Bebidas (alcoólicas e não alcoólicas)', 0.5, 2.25, 0, 0.63, 0, null),
    r(710, 'Feijão, preto, cru', LEGUMINOSAS, 0.35, 323.57, 21.34, 58.75, 1.24, 21.83),
    r(709, 'Feijão, preto, cozido', LEGUMINOSAS, 0.3043, 77.03, 4.48, 14.01, 0.54, 8.4),
    r(2291, 'Pretzels, soft', 'Snacks', 0.2, 338, 8.2, 69.39, 3.1, 1.7, 'US'),
  ],
  'farinha de mandioca': [
    r(278, 'Farinha, de mandioca, crua', VERDURAS, 0.8, 360.87, 1.55, 87.9, 0.28, 6.39),
    r(279, 'Farinha, de mandioca, torrada', VERDURAS, 0.7143, 365.27, 1.23, 89.19, 0.29, 6.54),
    r(281, 'Fécula, de mandioca', VERDURAS, 0.5, 330.85, 0.52, 81.15, 0.28, 0.65),
    r(191, 'Farinha, de rosca', CEREAIS, 0.48, 370.58, 11.38, 75.79, 1.46, 4.82),
    r(280, 'Farinha, de puba', VERDURAS, 0.44, 360.18, 1.62, 87.29, 0.47, 4.24),
    r(192, 'Farinha, de trigo', CEREAIS, 0.4231, 360.47, 9.79, 75.09, 1.37, 2.35),
    r(289, 'Mandioca, frita', VERDURAS, 0.4, 300.06, 1.38, 50.25, 11.2, 1.87),
    r(190, 'Farinha, de milho, amarela', CEREAIS, 0.3636, 350.59, 7.19, 79.08, 1.47, 5.49),
    r(287, 'Mandioca, crua', VERDURAS, 0.36, 151.42, 1.13, 36.17, 0.3, 1.88),
    r(288, 'Mandioca, farofa, temperada', VERDURAS, 0.3529, 405.69, 2.06, 80.3, 9.12, 7.82),
    r(448, 'Manjuba, com farinha de trigo, frita', PESCADOS, 0.35, 343.55, 23.45, 10.24, 22.59, 0.36),
    r(286, 'Mandioca, cozida', VERDURAS, 0.3333, 125.36, 0.57, 30.09, 0.3, 1.56),
    r(733, 'Farinha, de mesocarpo de babaçu, crua', 'Nozes e sementes', 0.325, 328.77, 1.41, 79.17, 0.2, 17.86),
    r(723, 'Soja, farinha', LEGUMINOSAS, 0.32, 403.96, 36.03, 38.44, 14.63, 20.18),
    r(193, 'Farinha, láctea, de cereais', CEREAIS, 0.3143, 414.85, 11.88, 77.77, 5.79, 1.94),
    r(189, 'Farinha, de centeio, integral', CEREAIS, 0.3056, 335.78, 12.52, 73.3, 1.75, 15.48),
    r(188, 'Farinha, de arroz, enriquecida', CEREAIS, 0.2895, 363.06, 1.27, 85.5, 0.3, 0.58),
    r(430, 'Cação, posta, com farinha de trigo, frita', PESCADOS, 0.2444, 208.33, 24.95, 3.1, 9.95, 0.54),
    r(455, 'Pescada, filé, com farinha de trigo, frito', PESCADOS, 0.234, 283.43, 21.44, 5.03, 19.11, 0),
    r(535, 'Coxinha de frango, frita', CARNES, 0.2, 283.05, 9.61, 34.52, 11.84, 4.97),
  ],
  'pães de queijo': [
    r(298, 'Pão, de queijo, cru', VERDURAS, 0.5714, 294.54, 3.65, 38.51, 13.99, 0.98),
    r(214, 'Pastel, de queijo, cru', CEREAIS, 0.5, 308.47, 9.85, 45.95, 9.63, 1.11),
    r(297, 'Pão, de queijo, assado', VERDURAS, 0.5, 363.08, 5.12, 34.24, 24.57, 0.56),
    r(215, 'Pastel, de queijo, frito', CEREAIS, 0.4615, 422.11, 8.71, 48.13, 22.67, 0.94),
    r(629, 'Omelete, de queijo', 'Ovos e derivados', 0.4348, 268.01, 15.57, 0.44, 22.01, null),
    r(610, 'Queijo, parmesão', 'Leite e derivados', 0.4091, 452.96, 35.55, 1.66, 33.53, null),
    r(613, 'Queijo, prato', 'Leite e derivados', 0.4, 359.88, 22.66, 1.88, 29.11, null),
  ],
  'batata doce': [
    r(246, 'Batata, doce, crua', VERDURAS, 0.6875, 118.24, 1.26, 28.2, 0.13, 2.57),
    r(245, 'Batata, doce, cozida', VERDURAS, 0.6111, 76.76, 0.64, 18.42, 0.09, 2.21),
    r(333, 'Banana, doce em barra', 'Frutas e derivados', 0.3182, 280.11, 2.17, 75.67, 0.05, 3.83),
    r(244, 'Batata, baroa, crua', VERDURAS, 0.3, 100.98, 1.05, 23.98, 0.17, 2.06),
    r(243, 'Batata, baroa, cozida', VERDURAS, 0.2727, 80.12, 0.85, 18.95, 0.17, 1.76),
    r(249, 'Batata, inglesa, crua', VERDURAS, 0.25, 64.37, 1.77, 14.69, 0, 1.16),
    r(250, 'Batata, inglesa, frita', VERDURAS, 0.25, 267.16, 4.97, 35.64, 13.11, 8.06),
    r(303, 'Polvilho, doce', VERDURAS, 0.25, 351.23, 0.43, 86.77, 0, 0.24),
    r(251, 'Batata, inglesa, sauté', VERDURAS, 0.24, 67.89, 1.29, 14.09, 0.9, 1.38),
    r(293, 'Nhoque, batata, cozido', VERDURAS, 0.24, 180.78, 5.86, 36.78, 1.94, 1.78),
    r(248, 'Batata, inglesa, cozida', VERDURAS, 0.2308, 51.59, 1.16, 11.94, 0, 1.34),
    r(355, 'Goiaba, doce em pasta', 'Frutas e derivados', 0.2308, 268.96, 0.58, 74.12, 0, 3.73),
    r(165, 'Biscoito, doce, maisena', CEREAIS, 0.2222, 442.82, 8.07, 75.23, 11.97, 2.1),
    r(256, 'Biscoito, polvilho doce', VERDURAS, 0.2143, 437.55, 1.29, 80.54, 12.25, 1.16),
    r(356, 'Goiaba, doce, cascão', 'Frutas e derivados', 0.2, 285.59, 0.41, 78.7, 0.1, 4.37),
  ],
  // Adjective-only coincidence (review scan; full staging windows, 2026-09-28).
  'café preto': [
    r(710, 'Feijão, preto, cru', LEGUMINOSAS, 0.3333, 323.57, 21.34, 58.75, 1.24, 21.83),
    r(622, 'Chá, preto, infusão 5%', 'Bebidas (alcoólicas e não alcoólicas)', 0.2917, 2.25, 0, 0.63, 0, null),
    r(709, 'Feijão, preto, cozido', LEGUMINOSAS, 0.2917, 77.03, 4.48, 14.01, 0.54, 8.4),
    r(656, 'Café, pó, torrado', 'Miscelâneas', 0.2857, 418.62, 14.7, 65.75, 11.95, 51.23),
    r(617, 'Café, infusão 10%', 'Bebidas (alcoólicas e não alcoólicas)', 0.2273, 9.07, 0.71, 1.48, 0.07, null),
  ],
  'pão preto': [
    r(710, 'Feijão, preto, cru', LEGUMINOSAS, 0.3684, 323.57, 21.34, 58.75, 1.24, 21.83),
    r(622, 'Chá, preto, infusão 5%', 'Bebidas (alcoólicas e não alcoólicas)', 0.3182, 2.25, 0, 0.63, 0, null),
    r(709, 'Feijão, preto, cozido', LEGUMINOSAS, 0.3182, 77.03, 4.48, 14.01, 0.54, 8.4),
    r(206, 'Pão, de soja', CEREAIS, 0.2353, 308.73, 11.34, 56.51, 3.58, 5.71),
    r(2291, 'Pretzels, soft', 'Snacks', 0.2105, 338, 8.2, 69.39, 3.1, 1.7, 'US'),
    r(353, 'Fruta-pão, crua', 'Frutas e derivados', 0.2, 67.05, 1.08, 17.17, 0.19, 5.55),
  ],
  // Neighbours: the patient's answer after the question, and foods that must
  // keep their current behaviour.
  'feijão carioca cozido': [
    r(703, 'Feijão, carioca, cozido', LEGUMINOSAS, 1, 76.42, 4.78, 13.59, 0.54, 8.51),
    r(704, 'Feijão, carioca, cru', LEGUMINOSAS, 0.625, 329.03, 19.98, 61.22, 1.26, 18.42),
    r(707, 'Feijão, jalo, cozido', LEGUMINOSAS, 0.5385, 92.74, 6.14, 16.5, 0.51, 13.87),
    r(715, 'Feijão, roxo, cozido', LEGUMINOSAS, 0.5385, 76.89, 5.72, 12.91, 0.54, 11.51),
    r(709, 'Feijão, preto, cozido', LEGUMINOSAS, 0.5185, 77.03, 4.48, 14.01, 0.54, 8.4),
  ],
  'arroz branco cozido': [
    r(160, 'Arroz, tipo 1, cozido', CEREAIS, 0.4815, 128.26, 2.52, 28.06, 0.23, 1.56),
    r(162, 'Arroz, tipo 2, cozido', CEREAIS, 0.4815, 130.12, 2.57, 28.19, 0.36, 1.07),
    r(158, 'Arroz, integral, cozido', CEREAIS, 0.4483, 123.53, 2.59, 25.81, 1, 2.75),
    r(257, 'Brócolis, cozido', VERDURAS, 0.3333, 24.64, 2.13, 4.37, 0.46, 3.42),
    r(669, 'Arroz carreteiro', PREPARADOS, 0.2414, 153.77, 10.83, 11.58, 7.12, 1.5),
    r(161, 'Arroz, tipo 1, cru', CEREAIS, 0.2333, 357.79, 7.16, 78.76, 0.34, 1.64),
    r(673, 'Bolinho de arroz', PREPARADOS, 0.2333, 273.51, 8.04, 41.68, 8.29, 2.74),
  ],
  'bolinho de arroz': [
    r(673, 'Bolinho de arroz', PREPARADOS, 1, 273.51, 8.04, 41.68, 8.29, 2.74),
    r(184, 'Creme de arroz, pó', CEREAIS, 0.3462, 386, 7.03, 83.87, 1.23, 1.07),
    r(188, 'Farinha, de arroz, enriquecida', CEREAIS, 0.2778, 363.06, 1.27, 85.5, 0.3, 0.58),
    r(161, 'Arroz, tipo 1, cru', CEREAIS, 0.2143, 357.79, 7.16, 78.76, 0.34, 1.64),
  ],
  cenoura: [
    r(267, 'Cenoura, crua', VERDURAS, 0.6667, 34.14, 1.32, 7.66, 0.17, 3.18),
    r(266, 'Cenoura, cozida', VERDURAS, 0.5714, 29.86, 0.85, 6.69, 0.22, 2.63),
  ],
  'peito de frango': [
    r(556, 'Frango, peito, com pele, cru', CARNES, 0.5, 149.47, 20.78, 0, 6.73, null),
    r(8544, 'frango frito', 'Poultry Products', 0.5, 219, 30.57, 1.69, 9.12, 0.1),
    r(8545, 'frango frito', 'Poultry Products', 0.5, 219, 30.57, 1.69, 9.12, 0.1, 'US'),
    r(558, 'Frango, peito, sem pele, cru', CARNES, 0.4815, 119.16, 21.53, 0, 3.02, null),
    r(555, 'Frango, peito, com pele, assado', CARNES, 0.4333, 211.68, 33.42, 0, 7.65, null),
    r(557, 'Frango, peito, sem pele, cozido', CARNES, 0.4333, 162.87, 31.47, 0, 3.16, null),
    r(559, 'Frango, peito, sem pele, grelhado', CARNES, 0.4063, 159.19, 32.03, 0, 2.48, null),
    r(689, 'Salpicão, de frango', PREPARADOS, 0.4, 147.86, 13.93, 4.57, 7.84, 0.41),
    r(535, 'Coxinha de frango, frita', CARNES, 0.3571, 283.05, 9.61, 34.52, 11.84, 4.97),
    r(681, 'Estrogonofe de frango', PREPARADOS, 0.3571, 156.81, 17.55, 2.59, 7.96, 1),
    r(539, 'Empada, de frango, pré-cozida', CARNES, 0.3438, 377.48, 7.34, 35.53, 22.89, 2.22),
    r(7, 'frango grelhado', CARNES, 0.28, 159.19, 32.03, 0, 2.48, null),
  ],
}

type HistoryRow = {
  food_name: string
  food_db_id: number
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  source: string
}

function stagingMock(history: HistoryRow[] = []): ServiceClient {
  const chain = (rows: unknown): unknown => {
    const obj: Record<string, unknown> = { data: rows, error: null }
    for (const m of ['select', 'eq', 'ilike', 'gte', 'gt', 'lt', 'neq', 'in', 'or', 'order', 'limit']) {
      obj[m] = () => chain(rows)
    }
    obj.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return obj
  }
  return {
    rpc: async (_fn: string, params: { search_term: string }) => ({
      data: STAGING_WINDOWS[params.search_term.toLowerCase().trim()] ?? [],
      error: null,
    }),
    from: (table: string) => {
      if (table === 'meal_logs') {
        return chain(history.map((row) => ({ ...row, food_db: { is_verified: true } })))
      }
      if (table === 'product_events') return { insert: () => chain([]) }
      return chain([])
    },
  } as unknown as ServiceClient
}

// Exactly what the app sent for the proposal on 2026-09-27.
const INCIDENT_ITEMS = [
  { food_name: 'Arroz branco', quantity_g: 150 },
  { food_name: 'Feijão carioca', quantity_g: 86.5 },
  { food_name: 'Frango grelhado', quantity_g: 120 },
]

describe('audit 2026-09-27 — device gate meal proposal (QA A)', () => {
  it('never turns "Arroz branco" into "Bolinho de arroz" (food_db 673)', async () => {
    const result = await calcMealMacros(stagingMock(), INCIDENT_ITEMS, 'BR')
    const rice = result.items[0]!
    expect(rice.matched_taco_id).not.toBe(673)
    expect(rice.matched_taco_name).not.toContain('Bolinho')
  })

  it('asks for the preparation of "Arroz branco" and "Feijão carioca" instead of choosing raw', async () => {
    const result = await calcMealMacros(stagingMock(), INCIDENT_ITEMS, 'BR')
    const [rice, beans, chicken] = result.items

    for (const item of [rice!, beans!]) {
      expect(item.source).toBe('no_match')
      expect(item.kcal).toBe(0)
      expect(item.matched_taco_id).toBeNull()
    }
    expect(beans!.quantity_g).toBe(86.5)
    expect(result.user_warnings.some((w) => w.includes('"Arroz branco"') && /cru/.test(w) && /cozido/.test(w))).toBe(true)
    expect(result.user_warnings.some((w) => w.includes('"Feijão carioca"') && /cru/.test(w) && /cozido/.test(w))).toBe(true)

    // The third item is unambiguous and unchanged: canonical exact alias, TACO value.
    expect(chicken!.matched_taco_id).toBe(7)
    expect(chicken!.source).toBe('canonical_exact')
    expect(chicken!.kcal).toBe(191)
    expect(result.totals.kcal).toBe(191)
  })

  it('does not reuse the wrong raw-beans value already logged for the same name', async () => {
    // QA A's confirmed log from the incident (meal_logs, 2026-09-28 01:19Z).
    const history: HistoryRow[] = [
      {
        food_name: 'Feijão carioca',
        food_db_id: 704,
        quantity_g: 86.5,
        kcal: 284.6,
        protein_g: 17.28,
        carbs_g: 52.96,
        fat_g: 1.09,
        source: 'canonical_fuzzy',
      },
    ]
    const result = await calcMealMacros(
      stagingMock(history),
      [{ food_name: 'Feijão carioca', quantity_g: 86.5 }],
      'BR',
      'device-gate-qa-a',
    )
    expect(result.items[0]!.source).toBe('no_match')
    expect(result.items[0]!.kcal).toBe(0)
  })

  it('calculates the TACO value once the patient states the preparation', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [
        { food_name: 'Feijão carioca cozido', quantity_g: 86.5 },
        { food_name: 'Arroz branco cozido', quantity_g: 150 },
      ],
      'BR',
    )
    const [beans, rice] = result.items
    expect(beans!.matched_taco_id).toBe(703)
    expect(beans!.kcal).toBe(66.1) // 76.42 kcal/100 g × 0.865
    expect(rice!.matched_taco_id).toBe(160)
    expect(rice!.kcal).toBe(192.4) // 128.26 kcal/100 g × 1.5
    expect(result.user_warnings).toEqual([])
  })

  it('still recognises "Bolinho de arroz" when the patient names it', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [{ food_name: 'Bolinho de arroz', quantity_g: 100 }],
      'BR',
    )
    expect(result.items[0]!.matched_taco_id).toBe(673)
    expect(result.items[0]!.kcal).toBe(273.5)
  })

  it('does not ask when the preparations differ by less than 50% (cenoura, peito de frango)', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [
        { food_name: 'Cenoura', quantity_g: 100 },
        { food_name: 'Peito de frango', quantity_g: 100 },
      ],
      'BR',
    )
    const [carrot, breast] = result.items
    expect(carrot!.matched_taco_id).toBe(267)
    expect(carrot!.kcal).toBe(34.1)
    // Which "peito de frango" row wins is pre-existing behaviour, outside this
    // fix (recorded as a separate finding); here only "no question" is locked.
    expect(breast!.source).not.toBe('no_match')
    expect(breast!.kcal).toBeGreaterThan(0)
    expect(result.user_warnings).toEqual([])
  })

  it('does not ask for foods that only share a word with another food (adversarial review)', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [
        { food_name: 'Manteiga', quantity_g: 10 },
        { food_name: 'Chá preto', quantity_g: 200 },
        { food_name: 'Farinha de mandioca', quantity_g: 30 },
        { food_name: 'Pães de queijo', quantity_g: 100 },
      ],
      'BR',
    )
    expect(result.items.map((item) => item.matched_taco_id)).toEqual([417, 622, 278, 298])
    expect(result.items.map((item) => item.kcal)).toEqual([75.8, 4.5, 108.3, 294.5])
    expect(result.user_warnings).toEqual([])
  })

  it('asks for the ambiguous part of a composite instead of moving its grams to the other part', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [{ food_name: 'Frango grelhado com batata doce', quantity_g: 300 }],
      'BR',
    )
    expect(result.items[0]).toMatchObject({ source: 'no_match', kcal: 0, quantity_g: 300 })
    expect(result.totals.kcal).toBe(0)
    expect(
      result.user_warnings.some((w) => w.includes('"batata doce"') && /cru/.test(w) && /cozido/.test(w)),
    ).toBe(true)
  })

  it('never answers "Café preto" or "Pão preto" with beans or tea that only share the adjective', async () => {
    const result = await calcMealMacros(
      stagingMock(),
      [
        { food_name: 'Café preto', quantity_g: 100 },
        { food_name: 'Pão preto', quantity_g: 50 },
      ],
      'BR',
    )
    for (const item of result.items) {
      expect([710, 709, 622]).not.toContain(item.matched_taco_id)
      expect(item.matched_taco_name).not.toMatch(/Feij|Chá/)
    }
    // No catalog row of the named food reaches the threshold: the existing
    // category estimate applies (constants unchanged: black coffee ~1 kcal/100 g,
    // bread 270 kcal/100 g) and is labelled as an estimate.
    expect(result.items[0]).toMatchObject({ source: 'llm_estimate', kcal: 1 })
    expect(result.items[1]).toMatchObject({ source: 'llm_estimate', kcal: 135 })
  })
})
