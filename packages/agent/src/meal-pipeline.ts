/**
 * Pipeline de processamento de refeição.
 *
 * Recebe lista de itens (nome + quantidade) → faz match na food_db (TACO) →
 * calcula macros determinísticamente.
 *
 * ADR-006: cálculos saem da TACO, não do LLM.
 */
import type { ServiceClient } from '@mpp/db'

export interface MealItemInput {
  food_name: string
  quantity_g: number
}

export interface MealItemMatched {
  food_name: string
  matched_taco_name: string
  matched_taco_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  similarity: number
  source:
    | 'taco'
    | 'llm_estimate'
    | 'no_match'
    /** Nome com "X com Y", "X e Y" — paciente passou prato composto. */
    | 'composite_rejected'
    /** Match com densidade calórica de gordura mas food_name não é gordura. */
    | 'category_mismatch'
    /** Alimento que deveria ter proteína (ovo/carne/whey) bateu sem proteína. */
    | 'protein_mismatch'
  /** Quantidade em UNIDADE NATURAL pra exibir ao paciente (ex: "2 unidades", "250 ml"). */
  display_qty?: number
  /** Unidade natural pra exibição: 'g' (default), 'ml', 'unidade', 'unidades', 'pão', 'pães'. */
  display_unit?: string
}

/**
 * Decide unidade natural pra exibição baseado no nome do alimento.
 * Backend mantém gramas como unidade interna; isso é só pra UX.
 *
 * Regras:
 *   - Ovos → unidades (50g por ovo médio)
 *   - Líquidos (leite, suco, café, chocolate quente, vitamina, etc) → ml (1g ≈ 1ml)
 *   - Pão francês → unidades quando múltiplo de 50g
 *   - Outros → g
 */
export function naturalUnit(
  foodName: string,
  qtyG: number,
): { display_qty: number; display_unit: string } {
  const lower = foodName.toLowerCase()
  // Ovos: 1 ovo médio ≈ 50g
  if (/\bovo\b|\bovos\b|omelete/.test(lower)) {
    const units = Math.round(qtyG / 50)
    if (units >= 1) {
      return { display_qty: units, display_unit: units === 1 ? 'unidade' : 'unidades' }
    }
  }
  // SÓLIDOS/PÓS de marcas que costumam parecer líquido pelo nome.
  // Caso real Roberto 2026-05-15: "leite em pó" exibido como ml porque o regex
  // de líquidos abaixo casa em \bleite\b. Esta guarda EARLY força "g" pra:
  //   - leite em pó / em pó integral
  //   - café solúvel / café instantâneo
  //   - whey protein em pó / whey em pó
  //   - achocolatado em pó
  //   - chá em folhas / em flocos / granulado
  // OBS: regex usa substring sem \b porque JS \b não trata acentos (é, ó) como
  // word chars — \bp[óo]\b NÃO match "pó" no fim de string. Substring é seguro
  // aqui pois esses termos são únicos em nomes de alimentos.
  if (
    /em\s+p[óo]|sol[úu]vel|instant[âa]ne[oa]|em\s+flocos|em\s+folhas|granulad[oa]/i.test(
      lower,
    )
  ) {
    return { display_qty: qtyG, display_unit: 'g' }
  }
  // Líquidos: leite, suco, café, chocolate quente, achocolatado, vitamina, smoothie,
  // chá, cerveja, vinho, refrigerante, água, whey, capuccino
  if (
    /\bleite\b|\bsuco\b|\bcaf[ée]\b|chocolate\s+quente|cappuc|capuc|achocolatad|vitamina|smoothie|\bch[áa]\b|cerveja|vinho|refri|coca|\b[áa]gua\b|whey|caipirinha|cachaça|whisky|gin|champ/.test(
      lower,
    )
  ) {
    return { display_qty: qtyG, display_unit: 'ml' }
  }
  // Pão francês: 1 pão ≈ 50g
  if (/p[ãa]o\s*franc/.test(lower) && qtyG >= 50 && qtyG % 50 === 0) {
    const units = qtyG / 50
    return { display_qty: units, display_unit: units === 1 ? 'pão' : 'pães' }
  }
  // Pão de queijo: 1 unidade ≈ 30g
  if (/p[ãa]o\s+de\s+queijo/.test(lower) && qtyG >= 30 && qtyG % 30 === 0) {
    const units = qtyG / 30
    return { display_qty: units, display_unit: units === 1 ? 'pão de queijo' : 'pães de queijo' }
  }
  // Fatias (queijo, presunto, mortadela, peito de peru): se "fatiado" ou "fatia(s)" no nome
  if (/fatiad|\bfatia/.test(lower) && qtyG >= 15 && qtyG % 15 === 0) {
    const units = qtyG / 15  // ~15g por fatia média
    return { display_qty: units, display_unit: units === 1 ? 'fatia' : 'fatias' }
  }
  // Banana média ≈ 100g; maçã ≈ 150g — só converte se múltiplo limpo
  if (/\bbanana\b/.test(lower) && qtyG >= 100 && qtyG % 100 === 0) {
    const units = qtyG / 100
    return { display_qty: units, display_unit: units === 1 ? 'banana' : 'bananas' }
  }
  if (/\bma[çc][ãa]\b/.test(lower) && qtyG >= 150 && qtyG % 150 === 0) {
    const units = qtyG / 150
    return { display_qty: units, display_unit: units === 1 ? 'maçã' : 'maçãs' }
  }
  return { display_qty: qtyG, display_unit: 'g' }
}

/**
 * Estimativa de macros por categoria quando search_food_trgm não acha.
 * Roberto pediu: em vez de zerar, supor por porções médias.
 *
 * Categorias por keyword (em ordem de prioridade):
 *   - fruta_doce | fruta_neutra
 *   - vegetal_folhoso | vegetal_geral
 *   - carne | peixe | embutido
 *   - laticineo | queijo
 *   - carbo (massa, batata, mandioca, arroz)
 *   - molho (lipid-heavy)
 *   - oleaginosa
 *   - doce / sobremesa
 *   - prato (fallback genérico)
 */
export function estimateMacros(foodName: string): {
  category: string
  kcal: number // por 100g
  protein: number
  carbs: number
  fat: number
  fiber: number
} {
  const n = foodName.toLowerCase()
  // Frutas (doces vs neutras)
  if (/\buva\b|manga|abacaxi|melancia|melão|mam[ãa]o|pera|maçã|banana|laranja|tangerina|kiwi|morango|cereja|pêssego|figo|caqui|jabuticaba|goiaba|fruta/.test(n)) {
    return { category: 'fruta', kcal: 55, protein: 0.8, carbs: 14, fat: 0.3, fiber: 1.5 }
  }
  // Vegetais folhosos
  if (/alface|rúcula|agrião|espinafre|acelga|couve|repolho|chicória|radicchio|escarola/.test(n)) {
    return { category: 'vegetal_folhoso', kcal: 18, protein: 1.5, carbs: 3, fat: 0.3, fiber: 1.8 }
  }
  // Vegetais cozidos / em geral
  if (/br[óo]colis|couve-flor|abobrinha|berinjela|pepino|tomate|cenoura|beterraba|chuchu|vagem|ervilha|milho|aspargo|palmito/.test(n)) {
    return { category: 'vegetal', kcal: 35, protein: 2, carbs: 7, fat: 0.3, fiber: 2 }
  }
  // Embutidos / frios processados
  if (/salame|presunto|mortadela|peito\s+de\s+peru|peru|peito\s+de\s+frango\s+defumado|salsicha|kani|kani\s+kama|sushi/.test(n)) {
    return { category: 'embutido', kcal: 180, protein: 18, carbs: 2, fat: 11, fiber: 0 }
  }
  // Peixe
  if (/peixe|atum|salmão|tilápia|merluza|sardinha|bacalhau|camarão|sush|robalo|namorado|cação/.test(n)) {
    return { category: 'peixe', kcal: 130, protein: 22, carbs: 0, fat: 4, fiber: 0 }
  }
  // Carne vermelha
  if (/carne|bife|picanha|alcatra|file mignon|filé mignon|costela|patinho|coxão|maminha|fraldinha|cordeiro/.test(n)) {
    return { category: 'carne', kcal: 200, protein: 26, carbs: 0, fat: 11, fiber: 0 }
  }
  // Frango / aves
  if (/frango|coxa|asa|sobrecoxa|peito\s+de\s+frango|peru/.test(n)) {
    return { category: 'frango', kcal: 165, protein: 28, carbs: 0, fat: 5, fiber: 0 }
  }
  // Laticínios líquidos / leites
  if (/iogurte|kefir|coalhada|leite/.test(n)) {
    return { category: 'laticineo', kcal: 65, protein: 4, carbs: 5, fat: 3, fiber: 0 }
  }
  // Queijos
  if (/queijo|cream\s+cheese|requeij[ãa]o|ricota|cottage|burrata|mussarela|provolone|parmes[ãa]o|gorgonzola/.test(n)) {
    return { category: 'queijo', kcal: 290, protein: 20, carbs: 3, fat: 22, fiber: 0 }
  }
  // Massas / carbos
  if (/macarr[ãa]o|massa|espaguete|talharim|penne|nhoque|lasanha|ravioli|tortelini/.test(n)) {
    return { category: 'massa', kcal: 130, protein: 5, carbs: 25, fat: 1.5, fiber: 1 }
  }
  if (/arroz|risoto|pa[ée]lla/.test(n)) {
    return { category: 'arroz', kcal: 130, protein: 2.5, carbs: 28, fat: 0.3, fiber: 0.5 }
  }
  if (/batata|mandioca|aipim|inhame|cará|baroa|tubércul/.test(n)) {
    return { category: 'tubérculo', kcal: 90, protein: 1.5, carbs: 21, fat: 0.1, fiber: 1.5 }
  }
  // Pão / panificação
  if (/p[ãa]o|biscoito|bolacha|torrada|crepioca|tapioca|panqueca|crepe|wrap/.test(n)) {
    return { category: 'panificação', kcal: 270, protein: 8, carbs: 50, fat: 4, fiber: 2 }
  }
  // Molhos / condimentos calóricos
  if (/molho\s+de\s+salada|molho\s+ranch|maionese|mostarda\s+e\s+mel|c[ée]sar|tarta/.test(n)) {
    return { category: 'molho_calórico', kcal: 380, protein: 1, carbs: 6, fat: 38, fiber: 0 }
  }
  if (/molho/.test(n)) {
    return { category: 'molho', kcal: 80, protein: 2, carbs: 8, fat: 4, fiber: 0.5 }
  }
  // Doces / sobremesas
  if (/sorvete|chocolate|brigadeiro|pudim|torta|bolo|doce|geleia|mel|açúcar/.test(n)) {
    return { category: 'doce', kcal: 260, protein: 3, carbs: 45, fat: 8, fiber: 1 }
  }
  // Oleaginosas
  if (/castanha|amêndoa|noz|amendoim|pistache|avelã|macadâmia|granola/.test(n)) {
    return { category: 'oleaginosa', kcal: 580, protein: 18, carbs: 20, fat: 50, fiber: 8 }
  }
  // Bebidas zero — refrigerantes/bebidas com qualificador zero/diet/light
  // (coca zero, coca-cola zero, guaraná zero, refri diet, soda light, etc.).
  // Bug Luciana 2026-05-25: regex antigo só pegava "refri zero" literal.
  if (
    /[áa]gua|ch[áa]\b|caf[ée]\s+preto|adoçant/.test(n) ||
    (/\b(zero|diet|light|sem a[çc][uú]car|sem calorias?)\b/.test(n) &&
      /\b(refri|refrigerante|coca|cola|guaran[áa]|soda|gaseosa|soft\s*drink|t[ôo]nica|energ[ée]tico)\b/.test(n))
  ) {
    return { category: 'bebida_zero', kcal: 1, protein: 0, carbs: 0, fat: 0, fiber: 0 }
  }
  // Fallback genérico — prato preparado
  return { category: 'prato_genérico', kcal: 150, protein: 7, carbs: 18, fat: 5, fiber: 1 }
}

export interface MealCalcResult {
  items: MealItemMatched[]
  totals: {
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
    fiber_g: number
  }
  /** Warnings DEPRECATED. Use user_warnings ou audit_warnings. Mantido pra
   * compatibilidade — concatena os dois. */
  warnings: string[]
  /** Warnings que DEVEM ser mostradas ao paciente (precisa de ação dele):
   *  - composite rejeitado (paciente separa items)
   *  - match suspeito (paciente confirma)
   *  - sanity violations (densidade calórica, proteína esperada)
   * Estes vão na resposta do agente. */
  user_warnings: string[]
  /** Warnings APENAS pra audit interno (paciente NÃO precisa saber):
   *  - auto-split bem-sucedido
   *  - reuso de histórico
   *  - estimativa por categoria silenciosa
   * Estes vão pra product_events mas não pro paciente. */
  audit_warnings: string[]
}

/**
 * Extrai o "âncora" do nome do alimento — palavra-chave do ingrediente principal,
 * removendo qualifiers de preparo/tipo. Usado pra rejeitar match catastrófico
 * onde o trigram dominou a similaridade por uma palavra de preparo.
 *
 * Exemplo: "arroz refogado" → âncora="arroz". Match "espinafre refogado" não
 * contém "arroz" → rejeita match, cai pra estimativa por categoria.
 *
 * Reportado por Roberto em 2026-05-12: "arroz refogado" matchou com
 * "espinafre refogado" (39 kcal/100g) → 47 kcal pra 120g de arroz = absurdo.
 */
const PREPARATION_QUALIFIERS = new Set([
  'refogado', 'refogada', 'cozido', 'cozida', 'frito', 'frita', 'assado',
  'assada', 'grelhado', 'grelhada', 'cru', 'crua', 'natural', 'temperado',
  'temperada', 'recheado', 'recheada', 'gratinado', 'gratinada', 'mexido',
  'mexida', 'desfiado', 'desfiada', 'moído', 'moida', 'moído', 'moída',
  'picado', 'picada', 'fatiado', 'fatiada', 'ralado', 'ralada',
  'branco', 'branca', 'integral', 'doce', 'salgado', 'salgada', 'light',
  'diet', 'zero', 'magro', 'magra', 'gordo', 'gorda',
  'com', 'sem', 'ao', 'no', 'na', 'de', 'do', 'da', 'dos', 'das', 'e', 'em',
  'pra', 'para', 'tipo', 'estilo', 'mix',
])

export function extractAnchor(foodName: string): string | null {
  const tokens = foodName
    .toLowerCase()
    .replace(/[^a-záéíóúâêôãõçü\s]/gi, ' ')
    .split(/\s+/)
    .filter((t) => t.length >= 3 && !PREPARATION_QUALIFIERS.has(t))
  // Prioriza o token mais longo (geralmente o ingrediente principal).
  // Empate: pega o primeiro (ordem de menção do paciente).
  if (tokens.length === 0) return null
  tokens.sort((a, b) => b.length - a.length)
  return tokens[0] ?? null
}

/**
 * Detecta bebida ZERO/diet/light (caloria desprezível) — Bug Luciana 2026-05-25.
 *
 * Caso real: paciente disse "a coca é zero", o agente respondeu "tem caloria
 * zerada" mas GRAVOU "coca-cola zero" com 136,5 kcal — o valor da coca NORMAL.
 * Causa: a food_db tem "coca-cola" (~42 kcal/100g) mas NÃO tem o alias zero, e o
 * "zero" é tratado como qualifier de preparo (PREPARATION_QUALIFIERS), então o
 * trigram casa a coca cheia e o qualificador "zero" é simplesmente descartado.
 *
 * Aqui forçamos macros ~0 ANTES do match quando o nome tem qualificador de
 * zero-caloria E é claramente uma bebida/refrigerante. Suco, leite, água de
 * coco e a coca NORMAL não casam (sem qualificador zero) e seguem o fluxo normal.
 */
const ZERO_CAL_QUALIFIER = /\b(zero|diet|light|sem a[çc][uú]car|sem calorias?)\b/i
const DRINK_KEYWORD = /\b(refri|refrigerante|coca|cola|guaran[áa]|soda|gaseosa|soft\s*drink|tônica|t[ôo]nica|energ[ée]tico)\b/i

export function isZeroCalDrink(foodName: string, matchCategory?: string | null): boolean {
  const n = foodName.toLowerCase()
  if (!ZERO_CAL_QUALIFIER.test(n)) return false
  // É bebida pelo nome OU pela categoria do match no food_db (ex.: "bebidas").
  const cat = (matchCategory ?? '').toLowerCase()
  return DRINK_KEYWORD.test(n) || cat === 'bebidas' || cat === 'bebida'
}

/**
 * Match fuzzy via pg_trgm.
 * Threshold de 0.3 (ajustável). Acima disso confiamos no match.
 */
async function matchFood(
  supabase: ServiceClient,
  name: string,
  country: string = 'BR',
): Promise<{
  id: number | null
  name_pt: string | null
  category: string | null
  similarity: number
  kcal_per_100g: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
  fiber_g: number | null
}> {
  // Pede 5 candidatos pra fazer tie-break determinístico em código (Roberto+Luciana
  // 2026-06-03: alface crespa retornava 6 kcal numa chamada e 4 noutra; milho 34 vs 14
  // — postgres não garante ordem estável em ORDER BY similarity DESC quando há
  // empate, e LIMIT 1 expõe a flutuação. Fix: pega top-5, ordena por
  // (similarity DESC, id ASC) em JS — mesma chamada, mesmo retorno, sempre).
  const { data, error } = await (supabase as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
  }).rpc('search_food_trgm', {
    search_term: name.toLowerCase(),
    min_similarity: 0.2,
    max_results: 5,
    p_country: country,
  })

  const empty = {
    id: null,
    name_pt: null,
    category: null,
    similarity: 0,
    kcal_per_100g: null,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    fiber_g: null,
  }

  type Row = {
    id: number | null
    name_pt: string | null
    category: string | null
    similarity: number | null
    kcal_per_100g: number | string | null
    protein_g: number | string | null
    carbs_g: number | string | null
    fat_g: number | string | null
    fiber_g: number | string | null
  }
  const rows = (data ?? []) as Row[]
  if (error || rows.length === 0) return empty

  // Tie-break determinístico: similarity DESC, id ASC. Empate de similarity
  // (até 0.001 de diferença, abaixo do ruído de cast real→float) → menor id,
  // que é estável entre chamadas e entre pacientes.
  const sorted = [...rows].sort((a, b) => {
    const simA = a.similarity ?? 0
    const simB = b.similarity ?? 0
    if (Math.abs(simA - simB) > 0.001) return simB - simA
    const idA = a.id ?? Number.MAX_SAFE_INTEGER
    const idB = b.id ?? Number.MAX_SAFE_INTEGER
    return idA - idB
  })

  const top = sorted[0]
  if (!top) return empty
  return {
    id: top.id ?? null,
    name_pt: top.name_pt ?? null,
    category: top.category ?? null,
    similarity: top.similarity ?? 0,
    kcal_per_100g: top.kcal_per_100g != null ? Number(top.kcal_per_100g) : null,
    protein_g: top.protein_g != null ? Number(top.protein_g) : null,
    carbs_g: top.carbs_g != null ? Number(top.carbs_g) : null,
    fat_g: top.fat_g != null ? Number(top.fat_g) : null,
    fiber_g: top.fiber_g != null ? Number(top.fiber_g) : null,
  }
}

/**
 * Calcula macros para uma lista de itens.
 * Cada item identificado vai para a food_db. Itens sem match recebem
 * estimativa zero e o warning é registrado.
 */
/**
 * Procura uma correção de alimento APRENDIDA pra esse paciente.
 * Roberto pediu (2026-05-14): quando o paciente corrige a identidade de um
 * alimento ("batata" → "mandioca"), o sistema aprende e reaplica.
 *
 * Precedência: ESTE lookup roda ANTES de tudo (histórico, trigram, estimativa).
 *
 * Comportamento por status:
 *   - 'active' (confirmed_count >= 2): aplica silencioso — remapeia o nome.
 *   - 'learning' (confirmed_count = 1): aplica MAS marca needs_confirmation=true,
 *     pra o agente confirmar com o paciente ("registrei mandioca — você corrigiu
 *     isso antes; se hoje for batata mesmo, me avisa").
 *   - 'retired': ignorado (filtrado na query).
 *
 * Janela: só correções com last_seen nos últimos 30 dias (mesma janela do
 * lookupUserHistory — correção velha de comida que a pessoa não come mais
 * não deve valer pra sempre).
 *
 * Retorna `null` se não há correção aplicável.
 */
export async function lookupFoodCorrection(
  supabase: ServiceClient,
  userId: string,
  foodName: string,
): Promise<{
  corrected_to: string
  custom_macros: {
    kcal_per_100g: number
    protein_g: number
    carbs_g: number
    fat_g: number
  } | null
  needs_confirmation: boolean
  /** True quando correção tem confirmed_count >= 3 (paciente já confirmou
   * múltiplas vezes — aplicar silenciosamente sem warning audível). */
  is_well_established: boolean
} | null> {
  const normalize = (s: string) =>
    s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
  const target = normalize(foodName)
  if (!target) return null
  const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const supaTyped = supabase as any
  // Busca por said_name OU corrected_to. Bug Amanda 2026-05-16: ela corrigiu
  // "iogurte de pêssego" → "iogurte de pêssego whey" com custom_macros, depois
  // o LLM passou items.food_name="iogurte de pêssego whey" (= corrected_to).
  // Lookup com .eq('said_name', target) NÃO achava → cai em estimate genérico
  // → custom_macros 49 kcal/100g + 5.9g P/100g NÃO aplicado → registrou 0.68g P
  // em vez de 5g P. Usar .or() pra cobrir os 2 casos: LLM passou nome original
  // OU passou nome já corrigido. Ordena por last_seen DESC pra pegar o mais
  // recente em caso de múltiplas correções convergentes.
  const { data } = await supaTyped
    .from('user_food_corrections')
    .select(
      'said_name, corrected_to, custom_kcal_per_100g, custom_protein_g, custom_carbs_g, custom_fat_g, status, confirmed_count',
    )
    .eq('user_id', userId)
    .or(`said_name.eq.${target},corrected_to.eq.${target}`)
    .neq('status', 'retired')
    .gte('last_seen', lookback)
    .order('last_seen', { ascending: false })
    .limit(1)
  const row = (data ?? [])[0] as
    | {
        said_name: string
        corrected_to: string
        custom_kcal_per_100g: number | string | null
        custom_protein_g: number | string | null
        custom_carbs_g: number | string | null
        custom_fat_g: number | string | null
        status: string
        confirmed_count: number
      }
    | undefined
  if (!row) return null
  const hasCustom = row.custom_kcal_per_100g != null
  return {
    corrected_to: row.corrected_to,
    custom_macros: hasCustom
      ? {
          kcal_per_100g: Number(row.custom_kcal_per_100g),
          protein_g: Number(row.custom_protein_g ?? 0),
          carbs_g: Number(row.custom_carbs_g ?? 0),
          fat_g: Number(row.custom_fat_g ?? 0),
        }
      : null,
    needs_confirmation: row.status === 'learning',
    is_well_established: row.status === 'active' && (row.confirmed_count ?? 0) >= 3,
  }
}

/**
 * Procura o mesmo alimento no histórico do paciente nos últimos 30d.
 * Roberto pediu (2026-05-13): "consegue pegar os alimentos q se repetem
 * pra vir nas refeições seguintes qd ele identificar algo semelhante?
 * Pq tipo, todo dia eu tomo leite com whey de manhã e todo dia ele coloca
 * achocolatado ou chocolate quente".
 *
 * Estratégia: o próprio `meal_logs` é a memória do paciente. Se ele
 * confirmou X = Y macros num dia (após correção, replace=true substitui
 * os logs antigos), nos dias seguintes esse log vira fonte de verdade.
 *
 * Filtros importantes:
 *   - source='taco' (matches confiáveis, não estimativa por categoria nem zerados)
 *   - kcal > 0 (exclui logs sanity-rejected)
 *   - últimas 30d
 *   - case/acento-insensitive (normalize)
 *
 * Retorna `null` se não acha hit confiável.
 */
export async function lookupUserHistory(
  supabase: ServiceClient,
  userId: string,
  foodName: string,
): Promise<{
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  matched_log_id: string
  matched_food_name: string
} | null> {
  const normalize = (s: string) =>
    s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
  const target = normalize(foodName)
  const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const supaTyped = supabase as any
  const { data } = await supaTyped
    .from('meal_logs')
    .select('id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g')
    .eq('user_id', userId)
    .eq('source', 'taco')
    .gt('kcal', 0)
    .gte('created_at', lookback)
    .order('created_at', { ascending: false })
    .limit(50)
  const rows = (data ?? []) as Array<{
    id: string
    food_name: string
    quantity_g: number
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  // Match exato (normalizado) primeiro; depois substring forte.
  const exact = rows.find((r) => normalize(r.food_name) === target)
  const sub =
    exact ??
    rows.find((r) => {
      const n = normalize(r.food_name)
      return n.length >= 4 && target.length >= 4 && (n.includes(target) || target.includes(n))
    })
  if (!sub || sub.quantity_g <= 0) return null
  const factor100 = 100 / Number(sub.quantity_g)
  return {
    kcal_per_100g: +(Number(sub.kcal) * factor100).toFixed(2),
    protein_g: +(Number(sub.protein_g) * factor100).toFixed(2),
    carbs_g: +(Number(sub.carbs_g) * factor100).toFixed(2),
    fat_g: +(Number(sub.fat_g) * factor100).toFixed(2),
    fiber_g: 0,
    matched_log_id: sub.id,
    matched_food_name: sub.food_name,
  }
}

export async function calcMealMacros(
  supabase: ServiceClient,
  items: MealItemInput[],
  country: string = 'BR',
  /** ID do paciente — habilita reuso de alimentos do histórico do user. */
  userIdHint?: string,
): Promise<MealCalcResult> {
  const matched: MealItemMatched[] = []
  const userWarnings: string[] = []
  const auditWarnings: string[] = []
  const warnings = userWarnings // alias pra compat com pushes existentes que não classificou
  const totals = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 }

  for (let it of items) {
    // ── PRIORIDADE -2: BEBIDA ZERO/DIET/LIGHT (Bug Luciana 2026-05-25) ──────
    // Roda ANTES de tudo. Se o nome já deixa claro que é refrigerante/bebida
    // zero ("coca zero", "guaraná diet", "refri light"), força macros ~0 e NÃO
    // deixa o trigram casar a versão cheia (coca-cola normal ~42 kcal/100g) e
    // gravar caloria que o paciente nem ingeriu. Detecção por categoria do
    // food_db ("bebidas") fica no fluxo de match abaixo, pra casos sem keyword.
    if (isZeroCalDrink(it.food_name)) {
      const natZero = naturalUnit(it.food_name, it.quantity_g)
      auditWarnings.push(
        `"${it.food_name}" tratado como bebida zero-caloria (forçado ~0 kcal — qualificador zero/diet/light + bebida).`,
      )
      matched.push({
        food_name: it.food_name,
        matched_taco_name: '[bebida zero]',
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        fiber_g: 0,
        similarity: 1.0,
        source: 'taco',
        display_qty: natZero.display_qty,
        display_unit: natZero.display_unit,
      })
      continue
    }
    // ── PRIORIDADE -1: MAPA DE CORREÇÕES DO PACIENTE (Roberto 2026-05-14) ───
    // Roda ANTES de tudo. Se o paciente já corrigiu esse alimento ("batata" →
    // "mandioca"), remapeia o nome aqui. Precedência: correção > histórico >
    // trigram > estimativa.
    //   - custom_macros presente → usa direto (alimento específico do paciente).
    //   - sem custom_macros → só remapeia o nome; o resto do pipeline (histórico
    //     /trigram) resolve os macros pro nome corrigido.
    //   - needs_confirmation (status=learning, 1ª correção) → aplica MAS adiciona
    //     user_warning pro agente confirmar com o paciente.
    if (userIdHint) {
      const corr = await lookupFoodCorrection(supabase, userIdHint, it.food_name)
      if (corr) {
        if (corr.custom_macros) {
          const f = it.quantity_g / 100
          const kcal = +(corr.custom_macros.kcal_per_100g * f).toFixed(1)
          const protein = +(corr.custom_macros.protein_g * f).toFixed(2)
          const carbs = +(corr.custom_macros.carbs_g * f).toFixed(2)
          const fat = +(corr.custom_macros.fat_g * f).toFixed(2)
          const nat = naturalUnit(corr.corrected_to, it.quantity_g)
          matched.push({
            food_name: corr.corrected_to,
            matched_taco_name: `[correção do paciente] ${it.food_name} → ${corr.corrected_to}`,
            matched_taco_id: null,
            quantity_g: it.quantity_g,
            kcal,
            protein_g: protein,
            carbs_g: carbs,
            fat_g: fat,
            fiber_g: 0,
            similarity: 1.0,
            source: 'taco',
            display_qty: nat.display_qty,
            display_unit: nat.display_unit,
          })
          totals.kcal += kcal
          totals.protein_g += protein
          totals.carbs_g += carbs
          totals.fat_g += fat
          // Caso Roberto 2026-05-19: correção "chocolate quente → leite com whey"
          // está active com confirmed_count=4 mas LLM continuava dizendo "Heads
          // up: identifiquei leite com whey pelo seu histórico" toda manhã. O
          // auditWarning ficava no result da tool e o LLM (Sonnet 4.6) achava
          // que era pra mencionar. Solução: SILENCIAR auditWarning quando
          // correção é well_established (active + confirmed>=3) — paciente já
          // sabe, não precisa de aviso repetido.
          if (!corr.is_well_established) {
            auditWarnings.push(
              `"${it.food_name}" remapeado pra "${corr.corrected_to}" via correção aprendida do paciente (macro customizado).`,
            )
          }
          if (corr.needs_confirmation) {
            userWarnings.push(
              `Registrei "${corr.corrected_to}" porque você corrigiu isso antes. Se hoje for "${it.food_name}" mesmo, é só me avisar.`,
            )
          }
          continue
        }
        // Sem macro customizado: só remapeia o nome e deixa o resto do pipeline
        // resolver os macros do nome corrigido.
        if (!corr.is_well_established) {
          auditWarnings.push(
            `"${it.food_name}" remapeado pra "${corr.corrected_to}" via correção aprendida do paciente.`,
          )
        }
        if (corr.needs_confirmation) {
          userWarnings.push(
            `Registrei "${corr.corrected_to}" porque você corrigiu isso antes. Se hoje for "${it.food_name}" mesmo, é só me avisar.`,
          )
        }
        it = { ...it, food_name: corr.corrected_to }
      }
    }

    // ── PRIORIDADE 0: HISTÓRICO DO PACIENTE (Roberto 2026-05-13) ────────────
    // Antes do trigram, checa se o paciente já registrou esse alimento antes.
    // Se sim, usa esses macros — evita "leite com whey" virar achocolatado
    // toda vez. Após correção via replace=true, o log atualizado vira a memória.
    if (userIdHint) {
      const hist = await lookupUserHistory(supabase, userIdHint, it.food_name)
      if (hist) {
        const f = it.quantity_g / 100
        const kcal = +(hist.kcal_per_100g * f).toFixed(1)
        const protein = +(hist.protein_g * f).toFixed(2)
        const carbs = +(hist.carbs_g * f).toFixed(2)
        const fat = +(hist.fat_g * f).toFixed(2)
        const nat = naturalUnit(it.food_name, it.quantity_g)
        matched.push({
          food_name: it.food_name,
          matched_taco_name: `[histórico] ${hist.matched_food_name}`,
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal,
          protein_g: protein,
          carbs_g: carbs,
          fat_g: fat,
          fiber_g: 0,
          similarity: 1.0,
          source: 'taco',
          display_qty: nat.display_qty,
          display_unit: nat.display_unit,
        })
        totals.kcal += kcal
        totals.protein_g += protein
        totals.carbs_g += carbs
        totals.fat_g += fat
        auditWarnings.push(
          `"${it.food_name}" reusado do histórico do paciente (registro anterior: "${hist.matched_food_name}").`,
        )
        continue
      }
    }
    // ───────────────────────────────────────────────────────────────────────
    // Sanity 1: nome composto ("ovo com azeite", "leite com whey", "arroz e feijão").
    // Antes: rejeitava direto e zerava. Agora: tenta auto-split, busca cada parte
    // separadamente, divide a quantidade proporcionalmente. Se TODAS as partes
    // matcham bem, agrega os macros. Senão rejeita com warning.
    //
    // PRECEDÊNCIA: se o nome COMPLETO bate exato no food_db (ex: "leite com whey"
    // tem alias próprio com sim>=0.85), usa o match direto e PULA auto-split.
    // Sem isso, "leite com whey" (alias 95 kcal/100g) era zerado porque "whey"
    // sozinho tem sim=0.38 < 0.45 e o composite-reject preempta o match perfeito.
    const isComposite =
      / com | e | \+ |\bcom\s+|^com\s+/i.test(` ${it.food_name} `) &&
      it.food_name.split(/\s+/).length >= 3
    if (isComposite) {
      const directMatch = await matchFood(supabase, it.food_name, country)
      if (
        directMatch.id != null &&
        directMatch.kcal_per_100g != null &&
        directMatch.similarity >= 0.85
      ) {
        // Match completo bom — segue pelo caminho não-composite (queda abaixo)
      } else {
      const parts = it.food_name
        .split(/ com | e | \+ /i)
        .map((s) => s.trim())
        .filter((s) => s.length >= 2)
      // Dividir qty igual entre as partes
      const partQty = it.quantity_g / parts.length
      const partMatches: Array<{ name: string; m: Awaited<ReturnType<typeof matchFood>> }> = []
      for (const p of parts) {
        let pm = await matchFood(supabase, p, country)
        // FALLBACK (Erika+Amanda 2026-05-15/16): se match da parte completa
        // ficou baixo, tenta a ÚLTIMA palavra "substantiva" (ignorando
        // preposições de/do/da/com). Ex: "lasanha de abóbora" → tenta "abóbora"
        // que é entry específica do food_db. Exige sim>=0.55 pra evitar falso
        // match (mais conservador que match composto inicial).
        if (pm.similarity < 0.45 || pm.kcal_per_100g == null) {
          const words = p
            .split(/\s+/)
            .filter((w) => w.length >= 3 && !/^(de|do|da|dos|das|com|e|ou|na|no|à|ao)$/i.test(w))
          for (const w of [...words].reverse()) {
            const m2 = await matchFood(supabase, w, country)
            if (m2.similarity >= 0.55 && m2.kcal_per_100g != null) {
              pm = m2
              break
            }
          }
        }
        partMatches.push({ name: p, m: pm })
      }
      // Conta partes BOAS (sim>=0.45 + kcal valido). Estratégia em camadas:
      //  - 100% boas: agrega tudo (caminho original)
      //  - parcial: agrega só as boas com warning ao paciente
      //  - threshold de parcial:
      //      2-3 partes: >=50% (>=1 ou 2 boas)
      //      4-5 partes: >=2 boas (40-50%)
      //      6+ partes: >=33% (composto super complexo aceita mais perda)
      const goodMatches = partMatches.filter(
        (pm) => pm.m.similarity >= 0.45 && pm.m.kcal_per_100g != null,
      )
      const allGood = goodMatches.length === partMatches.length
      const minGoodForPartial =
        partMatches.length >= 6
          ? Math.ceil(partMatches.length / 3)
          : partMatches.length >= 4
            ? 2
            : Math.ceil(partMatches.length / 2)
      const someGood = !allGood && goodMatches.length >= minGoodForPartial
      if (allGood) {
        // Adiciona cada parte como item separado, com nome composto preservado em matched_taco_name
        let totalKcal = 0,
          totalProt = 0,
          totalCarbs = 0,
          totalFat = 0,
          totalFib = 0
        for (const pm of partMatches) {
          const f = partQty / 100
          const kcal = +((pm.m.kcal_per_100g ?? 0) * f).toFixed(1)
          const prot = +((pm.m.protein_g ?? 0) * f).toFixed(2)
          const carb = +((pm.m.carbs_g ?? 0) * f).toFixed(2)
          const fat = +((pm.m.fat_g ?? 0) * f).toFixed(2)
          const fib = +((pm.m.fiber_g ?? 0) * f).toFixed(2)
          totalKcal += kcal
          totalProt += prot
          totalCarbs += carb
          totalFat += fat
          totalFib += fib
        }
        const natComp = naturalUnit(it.food_name, it.quantity_g)
        matched.push({
          food_name: it.food_name,
          matched_taco_name: partMatches.map((pm) => pm.m.name_pt).join(' + '),
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: +totalKcal.toFixed(1),
          protein_g: +totalProt.toFixed(2),
          carbs_g: +totalCarbs.toFixed(2),
          fat_g: +totalFat.toFixed(2),
          fiber_g: +totalFib.toFixed(2),
          similarity: Math.min(...partMatches.map((pm) => pm.m.similarity)),
          source: 'taco',
          display_qty: natComp.display_qty,
          display_unit: natComp.display_unit,
        })
        totals.kcal += totalKcal
        totals.protein_g += totalProt
        totals.carbs_g += totalCarbs
        totals.fat_g += totalFat
        totals.fiber_g += totalFib
        auditWarnings.push(
          `"${it.food_name}" auto-dividido em ${partMatches.map((pm) => pm.m.name_pt).join(' + ')} (qty ${partQty.toFixed(0)}g cada).`,
        )
        continue
      }
      // Algumas partes OK (mas não todas) — agrega só as boas com warning.
      // Casos reais (sessão 2026-05-19): "lasanha de abóbora com queijo"
      // (Erika 16/05), "muffin de banana com castanhas" (Amanda 16/05).
      // Em vez de zerar TUDO, usa as partes que matcharam (proporcional
      // a partes boas) e avisa o paciente do que faltou.
      if (someGood) {
        const partQtyGood = it.quantity_g / goodMatches.length
        let totalKcal = 0, totalProt = 0, totalCarbs = 0, totalFat = 0, totalFib = 0
        for (const pm of goodMatches) {
          const f = partQtyGood / 100
          totalKcal += (pm.m.kcal_per_100g ?? 0) * f
          totalProt += (pm.m.protein_g ?? 0) * f
          totalCarbs += (pm.m.carbs_g ?? 0) * f
          totalFat += (pm.m.fat_g ?? 0) * f
          totalFib += (pm.m.fiber_g ?? 0) * f
        }
        const missing = partMatches.filter((pm) => !goodMatches.includes(pm)).map((pm) => pm.name)
        const natComp = naturalUnit(it.food_name, it.quantity_g)
        matched.push({
          food_name: it.food_name,
          matched_taco_name: goodMatches.map((pm) => pm.m.name_pt).join(' + ') + ' (parcial)',
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: +totalKcal.toFixed(1),
          protein_g: +totalProt.toFixed(2),
          carbs_g: +totalCarbs.toFixed(2),
          fat_g: +totalFat.toFixed(2),
          fiber_g: +totalFib.toFixed(2),
          similarity: Math.min(...goodMatches.map((pm) => pm.m.similarity)),
          source: 'taco',
          display_qty: natComp.display_qty,
          display_unit: natComp.display_unit,
        })
        totals.kcal += totalKcal
        totals.protein_g += totalProt
        totals.carbs_g += totalCarbs
        totals.fat_g += totalFat
        totals.fiber_g += totalFib
        warnings.push(
          `Calculei "${it.food_name}" usando só [${goodMatches.map((g) => g.m.name_pt).join(', ')}] — não identifiquei ${missing.length > 1 ? 'as partes' : 'a parte'} ${missing.map((p) => `"${p}"`).join(' e ')}. Se faltou algo importante, me corrija com o nome certo dessa parte e a quantidade.`,
        )
        continue
      }
      // Nenhuma ou pouquíssimas partes OK — rejeição (composite_rejected).
      warnings.push(
        `Não consegui identificar "${it.food_name}" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: "leite 250ml" e "whey 30g"). Não foi possível calcular as calorias desse item ainda.`,
      )
      matched.push({
        food_name: it.food_name,
        matched_taco_name: '',
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        fiber_g: 0,
        similarity: 0,
        source: 'composite_rejected',
      })
      continue
      } // fecha else (auto-split)
      // Se chegou aqui, directMatch é bom — cai pro fluxo de match direto abaixo
    }

    const m = await matchFood(supabase, it.food_name, country)
    const factor = it.quantity_g / 100

    // Anchor check: o ingrediente principal da query precisa aparecer no
    // nome do match. Bloqueia bug "arroz refogado" → "espinafre refogado".
    // Se a âncora não aparece, força fallback pra estimativa por categoria.
    const anchor = extractAnchor(it.food_name)
    const matchedNameLower = (m.name_pt ?? '').toLowerCase()
    const anchorMatches = anchor == null || matchedNameLower.includes(anchor)

    // Threshold dinâmico por tamanho da query:
    // - Queries curtas (1-2 palavras, ≤15 chars) tendem a ter similarity baixa
    //   contra entries longos no DB (ex: "whey" vs "whey protein" = 0.38).
    //   Threshold mais permissivo evita fallback prematuro pra estimateMacros.
    // - Queries longas (>15 chars / 3+ palavras) usam threshold mais rigoroso
    //   pra evitar matches catastróficos (ex: "ovos cozidos com fio de azeite"
    //   matchando azeite por causa do trigram parcial).
    const queryWords = it.food_name.trim().split(/\s+/).length
    const queryLen = it.food_name.trim().length
    const isShortQuery = queryWords <= 2 || queryLen <= 15
    const matchThreshold = isShortQuery ? 0.3 : 0.45
    if (m.id != null && m.kcal_per_100g != null && m.similarity >= matchThreshold && anchorMatches) {
      // Camada 2 do guard de bebida zero (Bug Luciana 2026-05-25): nome sem
      // keyword de bebida ("zero" + nome genérico) mas que casou um item de
      // categoria "bebidas" no food_db. Aqui usamos a CATEGORIA do match pra
      // forçar ~0 antes de aceitar a caloria cheia do alimento-base.
      if (isZeroCalDrink(it.food_name, m.category)) {
        const natZ = naturalUnit(it.food_name, it.quantity_g)
        auditWarnings.push(
          `"${it.food_name}" tratado como bebida zero-caloria via categoria do match "${m.category}" (forçado ~0 kcal em vez de ${(m.kcal_per_100g * factor).toFixed(1)}).`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '[bebida zero]',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'taco',
          display_qty: natZ.display_qty,
          display_unit: natZ.display_unit,
        })
        continue
      }

      const kcal = +(m.kcal_per_100g * factor).toFixed(1)
      const protein = +((m.protein_g ?? 0) * factor).toFixed(2)
      const carbs = +((m.carbs_g ?? 0) * factor).toFixed(2)
      const fat = +((m.fat_g ?? 0) * factor).toFixed(2)
      const fiber = +((m.fiber_g ?? 0) * factor).toFixed(2)

      // Sanity 2: densidade calórica catastrófica. Alimento >5 kcal/g só faz
      // sentido pra gorduras/oleaginosas/embutidos densos / queijos gordos.
      //
      // Detecção PRINCIPAL via category do food_db (mais robusto que regex).
      // Categorias que justificam >5 kcal/g naturalmente:
      //   - gorduras (óleos, azeite, manteiga)
      //   - oleaginosas / sementes (castanhas, nozes, chia, linhaça)
      //   - doces (chocolates densos)
      // Pra carnes / laticínios / outros, ainda usa regex backup pra cobrir
      // casos específicos (bacon, parmesão, etc) que NÃO têm categoria dedicada.
      //
      // Histórico: regex sozinho falhava em bacon (carnes), parmesão (lacteos)
      // etc. Categoria + regex juntos cobrem todos casos legítimos.
      const kcalPerG = (m.kcal_per_100g ?? 0) / 100
      const lowerName = it.food_name.toLowerCase()
      const matchCat = (m.category ?? '').toLowerCase()
      const categoryAllowsHighKcal = [
        'gorduras',
        'oleaginosas',
        'sementes',
        'doces',
      ].includes(matchCat)
      const isFatLike =
        categoryAllowsHighKcal ||
        /azeite|[óo]leo|manteiga|margarina|maionese|gordura|nozes|castanha|am[êe]ndoa|amendoim|pasta de amendoim|nutella|tahini|abacate|coco|chia|linha[çc]a|gergelim|girassol|abóbora|bacon|toucinho|torresmo|salame|chouri[çc]o|sal[áa]mi|pepperoni|mortadela|paio|presunto parma|copa|linguiça|chocolate|brigadeiro|beijinho|trufa|queijo parmes[ãa]o|parmes[ãa]o|gorgonzola|brie|camembert|provolone|gruy[èe]re|requeij[ãa]o cremoso|cream cheese|catupiry|nata|creme de leite|leite de coco|granola/.test(
          lowerName,
        )
      if (kcalPerG > 5 && !isFatLike) {
        warnings.push(
          `Não tenho certeza sobre "${it.food_name}" — o valor calórico encontrado parece alto demais pro que o paciente descreveu. Peça pra ele confirmar ou detalhar melhor o alimento. Não calculei as calorias desse item ainda.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'category_mismatch',
        })
        continue
      }

      // Sanity 3: alimento c/ proteína esperada (carnes, peixes, ovos, embutidos,
      // laticínios proteicos) não pode ter protein_g=0. Match errado se sim.
      const expectsProtein =
        /\bovo|\bfrango|\bcarne|\bpeixe|\bwhey|\batum|\bfil[ée]|\bpicanha|\bbife|\bsalm[ãa]o|\btil[áa]pia|\bsalsicha|\blingu[ií]ça|\bbacon|\bpresunto|\bsalame|\bmortadela|\bperu|\bpernil|\bhamb[uú]rguer|\bnugget|\bisca|\bpat[ée]|\bmussarela|\bricota|\bcoalho|\bsardinha|\bcamar[ãa]o|\bcord[ãa]o\s+azul|\bcordeiro|\bcostela/.test(
          lowerName,
        )
      if (expectsProtein && (m.protein_g ?? 0) < 5) {
        warnings.push(
          `Não tenho certeza sobre "${it.food_name}" — esperava um alimento rico em proteína mas o valor encontrado não bate. Peça pro paciente confirmar ou detalhar. Não calculei as calorias desse item ainda.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'protein_mismatch',
        })
        continue
      }

      const nat = naturalUnit(it.food_name, it.quantity_g)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: m.name_pt ?? '',
        matched_taco_id: m.id,
        quantity_g: it.quantity_g,
        kcal,
        protein_g: protein,
        carbs_g: carbs,
        fat_g: fat,
        fiber_g: fiber,
        similarity: m.similarity,
        source: 'taco',
        display_qty: nat.display_qty,
        display_unit: nat.display_unit,
      })

      totals.kcal += kcal
      totals.protein_g += protein
      totals.carbs_g += carbs
      totals.fat_g += fat
      totals.fiber_g += fiber

      if (m.similarity < 0.5) {
        auditWarnings.push(
          `Match com baixa confiança: "${it.food_name}" → "${m.name_pt}" (sim=${m.similarity.toFixed(2)})`,
        )
      }
    } else {
      // Loga rejeição por anchor mismatch pra rastreabilidade no /audit
      if (
        m.id != null &&
        m.kcal_per_100g != null &&
        m.similarity >= matchThreshold &&
        !anchorMatches
      ) {
        auditWarnings.push(
          `"${it.food_name}" rejeitou match em "${m.name_pt}" (sim=${m.similarity.toFixed(2)}) — âncora "${anchor}" não aparece no nome.`,
        )
      }
      // ────────────────────────────────────────────────────────────────────
      // FALLBACK 1: reusa do histórico do paciente (Roberto pediu: "pode já
      // colocar pra ele usar alimentos já informados ou identificados nas
      // próximas refeições").
      //
      // Fix Q3 Roberto 2026-06-03: antes pegava só o último meal_log e aplicava
      // ratio direto — chamadas consecutivas podiam pegar logs diferentes, e
      // kcal variava entre propostas do MESMO turno (caso Luciana 02/06:
      // alface crespa 6→4 kcal, milho 34→14 kcal). Agora calcula MEDIANA de
      // kcal/100g (e dos macros) sobre todos os logs do paciente do mesmo
      // food_name nos últimos 30d. Mediana é resistente a outliers + estável
      // entre chamadas (mesmos logs entram → mesmo resultado sai).
      // ────────────────────────────────────────────────────────────────────
      const lookback = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const supaTyped = supabase as any
      const { data: prior } = await supaTyped
        .from('meal_logs')
        .select('food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, source, user_id')
        .eq('user_id', userIdHint ?? '_no_user_')
        .ilike('food_name', it.food_name)
        .gte('created_at', lookback)
        .neq('source', 'no_match')
        .neq('source', 'composite_rejected')
        .order('created_at', { ascending: false })
        .limit(20)
      if (prior && prior.length > 0) {
        // Normaliza tudo pra per-100g (kcal/100g, P/100g, C/100g, G/100g),
        // descarta linhas com quantity_g ≤ 0 (lixo).
        const per100g = (prior as Array<{ quantity_g: number; kcal: number; protein_g: number; carbs_g: number; fat_g: number }>)
          .filter((p) => Number(p.quantity_g) > 0)
          .map((p) => {
            const q = Number(p.quantity_g)
            return {
              kcal: (Number(p.kcal) / q) * 100,
              protein_g: (Number(p.protein_g) / q) * 100,
              carbs_g: (Number(p.carbs_g) / q) * 100,
              fat_g: (Number(p.fat_g) / q) * 100,
            }
          })
        if (per100g.length > 0) {
          const median = (arr: number[]): number => {
            const sorted = [...arr].sort((a, b) => a - b)
            const mid = Math.floor(sorted.length / 2)
            return sorted.length % 2 === 0
              ? (sorted[mid - 1]! + sorted[mid]!) / 2
              : sorted[mid]!
          }
          const medKcal100 = median(per100g.map((p) => p.kcal))
          const medProt100 = median(per100g.map((p) => p.protein_g))
          const medCarb100 = median(per100g.map((p) => p.carbs_g))
          const medFat100 = median(per100g.map((p) => p.fat_g))
          const q = it.quantity_g
          const reKcal = +((medKcal100 * q) / 100).toFixed(1)
          const reProt = +((medProt100 * q) / 100).toFixed(2)
          const reCarb = +((medCarb100 * q) / 100).toFixed(2)
          const reFat = +((medFat100 * q) / 100).toFixed(2)
          auditWarnings.push(
            `"${it.food_name}" reusado de ${per100g.length} registros (mediana: ${medKcal100.toFixed(0)} kcal/100g → ${reKcal} kcal pra ${q}g).`,
          )
          // Loga pra auditoria (Roberto 2026-06-03): rastreabilidade de
          // quando reuso de histórico foi usado em vez de TACO.
          await supaTyped.from('product_events').insert({
            user_id: userIdHint ?? null,
            event: 'meal_calc.history_reused',
            properties: {
              food_name: it.food_name,
              source_log_count: per100g.length,
              kcal_per_100g_median: +medKcal100.toFixed(1),
              quantity_g: q,
              kcal_result: reKcal,
            },
          })
          const natRe = naturalUnit(it.food_name, it.quantity_g)
          matched.push({
            food_name: it.food_name,
            matched_taco_name: '[reuso histórico]',
            matched_taco_id: null,
            quantity_g: it.quantity_g,
            kcal: reKcal,
            protein_g: reProt,
            carbs_g: reCarb,
            fat_g: reFat,
            fiber_g: 0,
            similarity: 1.0,
            source: 'taco',
            display_qty: natRe.display_qty,
            display_unit: natRe.display_unit,
          })
          totals.kcal += reKcal
          totals.protein_g += reProt
          totals.carbs_g += reCarb
          totals.fat_g += reFat
          continue
        }
      }
      // ────────────────────────────────────────────────────────────────────
      // FALLBACK 2: sem reuso — ESTIMA por categoria (em vez de zerar).
      // ────────────────────────────────────────────────────────────────────
      const est = estimateMacros(it.food_name)
      const factor = it.quantity_g / 100
      const eKcal = +(est.kcal * factor).toFixed(1)
      const eProt = +(est.protein * factor).toFixed(2)
      const eCarb = +(est.carbs * factor).toFixed(2)
      const eFat = +(est.fat * factor).toFixed(2)
      const eFib = +(est.fiber * factor).toFixed(2)
      auditWarnings.push(
        `"${it.food_name}" sem match exato — estimando por categoria "${est.category}" (~${est.kcal} kcal/100g).`,
      )
      const natEst = naturalUnit(it.food_name, it.quantity_g)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: `[estimativa ${est.category}]`,
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: eKcal,
        protein_g: eProt,
        carbs_g: eCarb,
        fat_g: eFat,
        fiber_g: eFib,
        similarity: 0,
        source: 'llm_estimate',
        display_qty: natEst.display_qty,
        display_unit: natEst.display_unit,
      })
      totals.kcal += eKcal
      totals.protein_g += eProt
      totals.carbs_g += eCarb
      totals.fat_g += eFat
      totals.fiber_g += eFib
      continue
    }
  }

  return {
    items: matched,
    totals: roundTotals(totals),
    warnings: [...userWarnings, ...auditWarnings], // compat
    user_warnings: userWarnings,
    audit_warnings: auditWarnings,
  }
}

function roundTotals(t: { kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number }) {
  return {
    kcal: +t.kcal.toFixed(1),
    protein_g: +t.protein_g.toFixed(1),
    carbs_g: +t.carbs_g.toFixed(1),
    fat_g: +t.fat_g.toFixed(1),
    fiber_g: +t.fiber_g.toFixed(1),
  }
}
