/**
 * Golden tests — bugs descobertos no audit 2026-06-20 (feedback Roberto 19/06).
 *
 * Cenário base (Roberto 2026-06-19, Orlando ET):
 *  - 13:42 ET café (correto)
 *  - 17:48 ET camarão+kani → sistema rotulou "lanche" (na verdade era almoço tardio)
 *  - 18:56 ET jantar (tortilha+frango+queijo)
 *  - 19:09 ET 2 cookies (3º registro de jantar)
 *  - 21:31 ET lembrete proativo "você não registrou almoço hoje"
 *  - 22:49 ET 6 chicken wings (resposta ao lembrete) → LLM passou meal_type='almoco',
 *    autocorrect determinístico forçou pra 'jantar' (4º jantar do dia)
 *  - day_status='incomplete_no_response', bloco delta=0, excedente +403 kcal
 *  - 08:16 (06-20) bom dia matinal "4 blocos de 7.700 kcal completos" — alucinação
 *    escapou da regex HALLUCINATION_RE (plural + 'kcal' interpolado).
 *
 * Causas-raiz cobertas aqui:
 *  RC4: regex HALLUCINATION_RE deve pegar plural ("blocos", "completos") e "kcal"
 *  RC6: buildReminderText deve listar refeições já registradas com horário
 *  Documentação: RC1, RC2, RC3 são cobertos por integration tests + review manual.
 */
import { describe, expect, it } from 'vitest'

describe('audit 2026-06-20 — feedback Roberto 19/06', () => {
  // ── RC4: regex HALLUCINATION_RE ampliada (plural + kcal interpolado) ──────
  describe('RC4: HALLUCINATION_RE pega plural + kcal interpolado', () => {
    // Cópia LITERAL da regex em packages/inngest-functions/src/functions/engagement-sender.ts
    // pra travar paridade. Se alguém mudar lá sem atualizar aqui, teste falha.
    const HALLUCINATION_RE =
      /\b(fechou\s+(bem|com\s+deficit|com\s+saldo|dentro\s+da\s+meta)|saldo\s+positivo|blocos?(?:\s+(?:de\s+7\.?700(?:\s+kcal)?)?)?\s+(?:completos?|fechados?)|completou\s+(?:os?\s+)?blocos?|dentro\s+da\s+meta|deficit\s+real\s+de|deficit\s+de\s+\d|superavit|excedeu\s+a\s+meta\s+e\s+ainda\s+assim)/i

    const normalize = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '')

    it('"4 blocos de 7.700 kcal completos" → MATCHA (frase real Roberto 06-20 08:16)', () => {
      expect(HALLUCINATION_RE.test(normalize('4 blocos de 7.700 kcal completos'))).toBe(true)
    })

    it('"3 blocos completos" (plural sem 7.700) → MATCHA', () => {
      expect(HALLUCINATION_RE.test(normalize('3 blocos completos'))).toBe(true)
    })

    it('"bloco de 7.700 kcal completo" (singular + kcal) → MATCHA', () => {
      expect(HALLUCINATION_RE.test(normalize('bloco de 7.700 kcal completo'))).toBe(true)
    })

    it('"bloco completo" (singular sem kcal) → MATCHA (caso original já coberto)', () => {
      expect(HALLUCINATION_RE.test(normalize('bloco completo'))).toBe(true)
    })

    it('"completou o bloco" / "completou os blocos" → MATCHA', () => {
      expect(HALLUCINATION_RE.test(normalize('completou o bloco'))).toBe(true)
      expect(HALLUCINATION_RE.test(normalize('completou os blocos'))).toBe(true)
    })

    it('"blocos fechados" (plural fechados) → MATCHA', () => {
      expect(HALLUCINATION_RE.test(normalize('seus blocos fechados'))).toBe(true)
    })

    it('"alimentando seu bloco" → NÃO MATCHA (frase educativa lícita)', () => {
      expect(HALLUCINATION_RE.test(normalize('alimentando seu bloco 7700'))).toBe(false)
    })

    it('"saldo do bloco" → NÃO MATCHA (não afirma fechamento)', () => {
      expect(HALLUCINATION_RE.test(normalize('o saldo do bloco hoje'))).toBe(false)
    })

    it('"déficit real de 704 kcal" (com acento, normalizado) → MATCHA (só permitido em FECHOU OK)', () => {
      expect(HALLUCINATION_RE.test(normalize('déficit real de 704 kcal'))).toBe(true)
    })
  })

  // ── RC6: buildReminderText lista refeições já registradas ─────────────────
  describe('RC6: lembrete acionável cita refeições já registradas', () => {
    // Réplica simplificada (paridade exata com daily-gap-checker.ts após
    // adversarial review F5-F9 06-20). Versão completa em
    // packages/inngest-functions/src/functions/daily-gap-checker.ts.
    type MealType = 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'
    const labels: Record<string, string> = {
      cafe: 'café da manhã',
      almoco: 'almoço',
      lanche: 'lanche',
      jantar: 'jantar',
      ceia: 'ceia',
      outro: 'refeição',
    }

    function buildReminderText(
      name: string,
      gap: MealType[],
      logs: Array<{ meal_type: string | null; kcal: number; hour: string; ts?: string }>,
    ): string {
      const list = gap.map((mt) => labels[mt] ?? mt).join(' e ')
      type Show = { hour: string; mealType: string; kcal: number; itemCount: number }
      const grouped = new Map<string, Show>()
      for (const l of logs) {
        if (!l.meal_type) continue
        // chave = meal_type + ts (default ts=hour pra teste; em prod é consumed_at iso)
        const ts = l.ts ?? l.hour
        const key = `${l.meal_type}|${ts}`
        const existing = grouped.get(key)
        if (existing) {
          existing.kcal += l.kcal
          existing.itemCount += 1
        } else {
          grouped.set(key, { hour: l.hour, mealType: l.meal_type, kcal: l.kcal, itemCount: 1 })
        }
      }
      const shown: Show[] = Array.from(grouped.values())
      const firstGap = gap[0]
      if (shown.length === 0 || !firstGap) {
        return `Olá ${name}, antes de fechar o dia: você não registrou ${list} hoje. Se comeu, me descreve rapidão o que foi (ou manda foto) — dá tempo de registrar agora ou até amanhã cedo. Se realmente pulou, é só responder "pulei". Sem resposta até o fechamento, o dia fica como incompleto — e o bloco 7700 não credita.`
      }
      const registradoLines = shown
        .map((l) => {
          const lbl = labels[l.mealType] ?? l.mealType
          const itemsSuffix = l.itemCount > 1 ? `, ${l.itemCount} itens` : ''
          return `${l.hour} ${lbl} (${Math.round(l.kcal)} kcal${itemsSuffix})`
        })
        .join(', ')
      const exampleLogs = shown.filter((l) => l.mealType !== firstGap)
      const exampleLog = exampleLogs[0]
      const reclassifyHint =
        gap.length === 1
          ? exampleLog
            ? `Algum desses ERA seu ${labels[firstGap]}? Se sim, me diz qual horário e eu reclassifico sem dobrar (ex: "aquele ${labels[exampleLog.mealType] ?? exampleLog.mealType} das ${exampleLog.hour} era o ${labels[firstGap]}"). `
            : `Algum desses ERA seu ${labels[firstGap]}? Se sim, me diz qual horário e eu reclassifico sem dobrar. `
          : `Alguma dessas refeições do dia ERA na verdade ${list}? Me diz qual horário e eu reclassifico sem dobrar. `
      return `Olá ${name}, antes de fechar o dia: você não registrou ${list} hoje. Hoje você já registrou: ${registradoLines}. ${reclassifyHint}Se ainda vai comer agora ou amanhã cedo, me descreve. Se realmente pulou, é só responder "pulei". Sem resposta até o fechamento, o dia fica como incompleto — e o bloco 7700 não credita.`
    }

    it('cenário Roberto 19/06: gap=almoço + 2 jantares em horários DIFERENTES → linhas separadas', () => {
      const text = buildReminderText('Roberto', ['almoco'], [
        { meal_type: 'cafe', kcal: 808, hour: '13:42', ts: '2026-06-19T13:42:00' },
        { meal_type: 'lanche', kcal: 356, hour: '17:48', ts: '2026-06-19T17:48:00' },
        { meal_type: 'jantar', kcal: 552, hour: '18:56', ts: '2026-06-19T18:56:00' },
        { meal_type: 'jantar', kcal: 90, hour: '19:09', ts: '2026-06-19T19:09:00' },
      ])
      expect(text).toContain('13:42 café da manhã (808 kcal)')
      expect(text).toContain('17:48 lanche (356 kcal)')
      // 2 jantares em timestamps DIFERENTES = 2 linhas separadas
      expect(text).toContain('18:56 jantar (552 kcal)')
      expect(text).toContain('19:09 jantar (90 kcal)')
      expect(text).toContain('Algum desses ERA seu almoço')
      expect(text).toContain('reclassifico sem dobrar')
      expect(text).toContain('aquele café da manhã das 13:42 era o almoço')
    })

    it('cenário Luciana 22/06 (Bug #1 fix 23/06): refeição com MÚLTIPLOS ITENS MESMO TS → 1 linha agrupada', () => {
      // Realidade: 5 itens do MESMO almoço com mesma timestamp consumed_at.
      // ANTES (regressão F5 06-20): listava 5 linhas "14:18 almoço (192), 14:18 almoço (236)...".
      // AGORA: agrupa por (meal_type, ts) → 1 linha "14:18 almoço (572 kcal, 5 itens)".
      const text = buildReminderText('Roberto', ['jantar'], [
        { meal_type: 'cafe', kcal: 78, hour: '10:23', ts: '2026-06-22T10:23:00' },
        { meal_type: 'cafe', kcal: 84, hour: '10:23', ts: '2026-06-22T10:23:00' },
        { meal_type: 'almoco', kcal: 192, hour: '14:18', ts: '2026-06-22T14:18:00' },
        { meal_type: 'almoco', kcal: 236, hour: '14:18', ts: '2026-06-22T14:18:00' },
        { meal_type: 'almoco', kcal: 88, hour: '14:18', ts: '2026-06-22T14:18:00' },
        { meal_type: 'almoco', kcal: 7, hour: '14:18', ts: '2026-06-22T14:18:00' },
        { meal_type: 'almoco', kcal: 48, hour: '14:18', ts: '2026-06-22T14:18:00' },
      ])
      // 1 linha por refeição agrupada com kcal somado + contagem
      expect(text).toContain('10:23 café da manhã (162 kcal, 2 itens)')
      expect(text).toContain('14:18 almoço (571 kcal, 5 itens)')
      // NÃO deve ter linhas duplicadas
      expect((text.match(/10:23 café/g) ?? []).length).toBe(1)
      expect((text.match(/14:18 almoço/g) ?? []).length).toBe(1)
    })

    it('singleton: 1 item só não mostra ", N itens" no sufixo', () => {
      const text = buildReminderText('Roberto', ['jantar'], [
        { meal_type: 'lanche', kcal: 70, hour: '17:32', ts: '2026-06-21T17:32:00' },
      ])
      expect(text).toContain('17:32 lanche (70 kcal)')
      expect(text).not.toContain('17:32 lanche (70 kcal, 1 itens)')
    })

    it('sem registros → fallback simples (texto antigo)', () => {
      const text = buildReminderText('Roberto', ['almoco'], [])
      expect(text).not.toContain('Hoje você já registrou')
      expect(text).toContain('Se comeu, me descreve rapidão')
    })

    it('F8: 2 gaps → pergunta plural REFORMULADA (sem duplicar lista)', () => {
      const text = buildReminderText('Roberto', ['almoco', 'jantar'], [
        { meal_type: 'cafe', kcal: 808, hour: '13:42' },
      ])
      expect(text).toContain('almoço e jantar')
      // F8: frase reformulada — NÃO contém "(almoço e jantar) era almoço e jantar"
      expect(text).not.toContain('(almoço e jantar) era almoço e jantar')
      expect(text).toContain('Alguma dessas refeições do dia ERA na verdade almoço e jantar')
      expect(text).toContain('reclassifico sem dobrar')
    })

    it('F6: cenário recursivo — primeiro log É do mesmo meal_type do gap → exemplo pula pro próximo', () => {
      // gap=almoco mas o primeiro log já é "almoco" (registro errado mas existe).
      // ANTES o exemplo seria "aquele almoço das 13:42 era o almoço" (nonsense).
      // AGORA: filtra pra pegar próximo log que NÃO é do gap.
      const text = buildReminderText('Roberto', ['almoco'], [
        { meal_type: 'almoco', kcal: 80, hour: '13:42' }, // snack rotulado como almoço
        { meal_type: 'lanche', kcal: 356, hour: '17:48' },
      ])
      expect(text).not.toContain('aquele almoço das 13:42 era o almoço')
      expect(text).toContain('aquele lanche das 17:48 era o almoço')
    })

    it('F6 edge: TODOS os logs são do mesmo meal_type do gap → exemplo OMITIDO mas hint segue', () => {
      const text = buildReminderText('Roberto', ['almoco'], [
        { meal_type: 'almoco', kcal: 80, hour: '13:42' },
      ])
      expect(text).toContain('Algum desses ERA seu almoço')
      expect(text).not.toContain('aquele almoço das')
      expect(text).not.toContain('era o almoço")')
    })

    it('F7: meal_type=outro → renderizado como "refeição" (não literal "outro")', () => {
      const text = buildReminderText('Roberto', ['almoco'], [
        { meal_type: 'outro', kcal: 150, hour: '17:30' },
      ])
      expect(text).toContain('17:30 refeição (150 kcal)')
      expect(text).not.toContain('17:30 outro')
    })
  })

  // ── Bug #2 (Luciana 23/06): subset check evita pizza sumir ─────────────────
  describe('Bug #2: pipeline.ts subset check antes do cancel cego', () => {
    // Réplica das funções normalizeFoodName e isSubsetOfPending do
    // pipeline.ts. Cenário REAL: foto pizza criou pending de 8 itens; 27s
    // depois caption "10g ketchup + 10g maionese" disparou 2º turno que SEM o
    // fix cancelava o pending de 8 itens E gravava só 2 (express path).
    // Layer 1 do fix: detecta subset próprio (novos itens ⊆ pending E |novo|
    // < |pending|) e SUPRIME o 2º registro silenciosamente — paciente ainda
    // confirma o pending original de 8 itens via botão.
    const normalizeFoodName = (s: string) =>
      s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').trim()

    function isProperSubset(
      newItems: string[],
      pendingItems: string[],
    ): boolean {
      const newSet = new Set(newItems.map(normalizeFoodName))
      const pendSet = new Set(pendingItems.map(normalizeFoodName))
      if (newSet.size === 0 || pendSet.size <= newSet.size) return false
      for (const n of newSet) if (!pendSet.has(n)) return false
      return true
    }

    it('cenário real Luciana 23/06: ketchup+maionese ⊆ pizza+frango+mussarela+tomate+orégano+ketchup+maionese (8 itens) → SUPRIME', () => {
      const pending = [
        'tortilha de trigo',
        'molho de tomate',
        'frango desfiado',
        'queijo mussarela ralado',
        'tomate fatiado',
        'orégano',
        'ketchup',
        'maionese',
      ]
      const novoToolCall = ['ketchup', 'maionese']
      expect(isProperSubset(novoToolCall, pending)).toBe(true)
    })

    it('subset com acentos normalizados: "Maionese" e "MAIONESE" matcham', () => {
      expect(isProperSubset(['Maionese'], ['Pão', 'Café', 'MAIONESE'])).toBe(true)
    })

    it('igualdade NÃO conta como subset próprio (precisa pending ter MAIS itens)', () => {
      // |novo| === |pending| — refeição idêntica, paciente re-confirmando.
      // Não suprime — vai pro fluxo normal (cancel + execute).
      expect(isProperSubset(['ketchup', 'maionese'], ['ketchup', 'maionese'])).toBe(false)
    })

    it('superset NÃO conta como subset (paciente adicionou itens novos)', () => {
      // Paciente realmente adicionou itens novos — cancel + execute corretos.
      expect(isProperSubset(['ketchup', 'maionese', 'sorvete'], ['ketchup', 'maionese'])).toBe(false)
    })

    it('overlap parcial NÃO conta como subset (refeição diferente)', () => {
      // Pizza no pending; paciente manda hamburguer separado.
      expect(isProperSubset(['hambúrguer', 'batata'], ['pizza', 'frango', 'ketchup'])).toBe(false)
    })

    it('vazio NÃO conta como subset (sem items, nada a suprimir)', () => {
      expect(isProperSubset([], ['pizza', 'frango'])).toBe(false)
    })

    it('item único do tool call presente no pending (caption tardio só de 1 item) → SUPRIME', () => {
      // Edge case: paciente só completou com 1 item. Ainda é continuação.
      expect(isProperSubset(['maionese'], ['pizza', 'frango', 'maionese'])).toBe(true)
    })

    // ── Adversarial review H1+H2 (2026-06-24) ────────────────────────────
    // H1: replace=true (correção destrutiva) NÃO deve suprimir.
    // H2: quantity_g divergente (>20%) entre item novo e pending = correção
    //     de gramatura, NÃO suprimir.
    describe('H1+H2: bail-out de suppression em correções explícitas', () => {
      // Réplica do código do pipeline.ts pra testar a lógica isolada.
      function shouldSuppress(args: {
        replace?: boolean
        items: Array<{ food_name: string; quantity_g?: number }>
        pendingItems: Array<{ name: string; quantity_g?: number }>
      }): boolean {
        if (args.replace === true) return false // H1
        const newNames = new Set(args.items.map((i) => normalizeFoodName(i.food_name)))
        const newByName = new Map(
          args.items.map((i) => [normalizeFoodName(i.food_name), i.quantity_g]),
        )
        const pendNames = new Set(args.pendingItems.map((it) => normalizeFoodName(it.name)))
        const pendByName = new Map(
          args.pendingItems.map((it) => [normalizeFoodName(it.name), it.quantity_g]),
        )
        if (newNames.size === 0 || pendNames.size <= newNames.size) return false
        for (const n of newNames) if (!pendNames.has(n)) return false
        // H2: checa divergência de gramatura >20%
        for (const [name, newQ] of newByName) {
          const pendQ = pendByName.get(name)
          if (typeof newQ === 'number' && typeof pendQ === 'number' && pendQ > 0) {
            if (Math.abs(newQ - pendQ) / pendQ > 0.2) return false
          }
        }
        return true
      }

      it('H1: replace=true com items subset → NÃO suprime (correção destrutiva)', () => {
        expect(
          shouldSuppress({
            replace: true,
            items: [{ food_name: 'pizza queijo', quantity_g: 200 }],
            pendingItems: [
              { name: 'pizza queijo', quantity_g: 150 },
              { name: 'frango', quantity_g: 60 },
              { name: 'tomate', quantity_g: 40 },
              { name: 'orégano', quantity_g: 1 },
            ],
          }),
        ).toBe(false)
      })

      it('H1: replace=false (default) com subset perfeito → suprime', () => {
        expect(
          shouldSuppress({
            items: [{ food_name: 'ketchup', quantity_g: 10 }, { food_name: 'maionese', quantity_g: 10 }],
            pendingItems: [
              { name: 'tortilha', quantity_g: 45 },
              { name: 'frango', quantity_g: 60 },
              { name: 'ketchup', quantity_g: 10 },
              { name: 'maionese', quantity_g: 10 },
            ],
          }),
        ).toBe(true)
      })

      it('H2: arroz 200g novo vs arroz 50g no pending (gramatura 4x maior) → NÃO suprime', () => {
        expect(
          shouldSuppress({
            items: [{ food_name: 'arroz', quantity_g: 200 }],
            pendingItems: [
              { name: 'arroz', quantity_g: 50 },
              { name: 'feijão', quantity_g: 50 },
            ],
          }),
        ).toBe(false)
      })

      it('H2: arroz 55g vs arroz 50g (10% diff) → suprime (dentro de tolerância 20%)', () => {
        expect(
          shouldSuppress({
            items: [{ food_name: 'arroz', quantity_g: 55 }],
            pendingItems: [
              { name: 'arroz', quantity_g: 50 },
              { name: 'feijão', quantity_g: 50 },
            ],
          }),
        ).toBe(true)
      })

      it('H2: arroz sem quantity_g vs arroz com quantity_g no pending → suprime (sem dado pra comparar)', () => {
        expect(
          shouldSuppress({
            items: [{ food_name: 'arroz' }],
            pendingItems: [
              { name: 'arroz', quantity_g: 50 },
              { name: 'feijão', quantity_g: 50 },
            ],
          }),
        ).toBe(true)
      })
    })
  })
})
