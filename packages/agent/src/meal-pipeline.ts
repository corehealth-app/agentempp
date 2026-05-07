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
  // Bebidas zero
  if (/[áa]gua|ch[áa]\b|caf[ée]\s+preto|refri\s+zero|adoçant/.test(n)) {
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
  warnings: string[]
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
  similarity: number
  kcal_per_100g: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
  fiber_g: number | null
}> {
  // Normaliza + filtra por país (BR=TACO; US=USDA quando populado, etc.)
  const { data, error } = await (supabase as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
  }).rpc('search_food_trgm', {
    search_term: name.toLowerCase(),
    min_similarity: 0.2,
    max_results: 1,
    p_country: country,
  })

  const empty = {
    id: null,
    name_pt: null,
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
    similarity: number | null
    kcal_per_100g: number | string | null
    protein_g: number | string | null
    carbs_g: number | string | null
    fat_g: number | string | null
    fiber_g: number | string | null
  }
  const rows = (data ?? []) as Row[]
  if (error || rows.length === 0) return empty

  const top = rows[0]
  if (!top) return empty
  return {
    id: top.id ?? null,
    name_pt: top.name_pt ?? null,
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
export async function calcMealMacros(
  supabase: ServiceClient,
  items: MealItemInput[],
  country: string = 'BR',
  /** ID do paciente — habilita reuso de alimentos do histórico do user. */
  userIdHint?: string,
): Promise<MealCalcResult> {
  const matched: MealItemMatched[] = []
  const warnings: string[] = []
  const totals = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 }

  for (const it of items) {
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
        const pm = await matchFood(supabase, p, country)
        partMatches.push({ name: p, m: pm })
      }
      const allGood = partMatches.every((pm) => pm.m.similarity >= 0.45 && pm.m.kcal_per_100g != null)
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
        warnings.push(
          `"${it.food_name}" auto-dividido em ${partMatches.map((pm) => pm.m.name_pt).join(' + ')} (qty ${partQty.toFixed(0)}g cada). Quando souber quantidades exatas, separe os itens.`,
        )
        continue
      }
      // Algum part não matchou — mantém rejeição
      warnings.push(
        `Item composto rejeitado: "${it.food_name}" — não consegui separar em alimentos conhecidos. Peça pro paciente separar (ex: "leite 250ml" + "whey 30g"). Calorias zeradas.`,
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

    // Threshold mais conservador: 0.45 (era 0.3). Matches abaixo disso são quase
    // sempre erros (ex: "ovo" pegando "azeite" sim=0.3).
    if (m.id != null && m.kcal_per_100g != null && m.similarity >= 0.45) {
      const kcal = +(m.kcal_per_100g * factor).toFixed(1)
      const protein = +((m.protein_g ?? 0) * factor).toFixed(2)
      const carbs = +((m.carbs_g ?? 0) * factor).toFixed(2)
      const fat = +((m.fat_g ?? 0) * factor).toFixed(2)
      const fiber = +((m.fiber_g ?? 0) * factor).toFixed(2)

      // Sanity 2: densidade calórica catastrófica. Alimento sólido com >5 kcal/g
      // só faz sentido pra gorduras puras (azeite=8.84, manteiga=7.2). Se food_name
      // não menciona gordura/óleo/manteiga, é sinal de match errado.
      const kcalPerG = (m.kcal_per_100g ?? 0) / 100
      const lowerName = it.food_name.toLowerCase()
      const isFatLike =
        /azeite|óleo|oleo|manteiga|margarina|maionese|gordura|óleos|nozes|castanha|amêndoa|amendoim|pasta de amendoim/.test(
          lowerName,
        )
      if (kcalPerG > 5 && !isFatLike) {
        warnings.push(
          `Match suspeito: "${it.food_name}" → "${m.name_pt}" (${m.kcal_per_100g} kcal/100g é densidade de gordura). Provavelmente match errado. Confirme com paciente. Calorias zeradas.`,
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
          `Match suspeito: "${it.food_name}" tem proteína esperada mas matchou "${m.name_pt}" (${m.protein_g}g/100g). Match errado. Confirme com paciente. Calorias zeradas.`,
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
        warnings.push(
          `Match com baixa confiança: "${it.food_name}" → "${m.name_pt}" (sim=${m.similarity.toFixed(2)})`,
        )
      }
    } else {
      // ────────────────────────────────────────────────────────────────────
      // FALLBACK 1: tenta reusar do histórico do paciente (Roberto pediu:
      // "pode já colocar pra ele usar alimentos já informados ou identificados
      // nas próximas refeições"). Busca meal_logs últimos 30d com mesmo nome.
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
        .limit(1)
      if (prior && prior.length > 0 && prior[0].quantity_g > 0) {
        const p = prior[0]
        // Calcula per-100g do registro anterior e aplica na qty atual
        const ratio = it.quantity_g / Number(p.quantity_g)
        const reKcal = +(Number(p.kcal) * ratio).toFixed(1)
        const reProt = +(Number(p.protein_g) * ratio).toFixed(2)
        const reCarb = +(Number(p.carbs_g) * ratio).toFixed(2)
        const reFat = +(Number(p.fat_g) * ratio).toFixed(2)
        warnings.push(
          `"${it.food_name}" reusado de registro anterior (${p.kcal} kcal/${p.quantity_g}g → ${reKcal} kcal pra ${it.quantity_g}g).`,
        )
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
      warnings.push(
        `"${it.food_name}" sem match exato — estimando por categoria "${est.category}" (~${est.kcal} kcal/100g). Confiança média.`,
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

  return { items: matched, totals: roundTotals(totals), warnings }
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
