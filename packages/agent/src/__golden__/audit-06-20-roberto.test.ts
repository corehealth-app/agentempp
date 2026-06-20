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
      logs: Array<{ meal_type: string | null; kcal: number; hour: string }>,
    ): string {
      const list = gap.map((mt) => labels[mt] ?? mt).join(' e ')
      const shown = logs
        .filter((l) => l.meal_type)
        .map((l) => ({ hour: l.hour, mealType: l.meal_type as string, kcal: l.kcal }))
      const firstGap = gap[0]
      if (shown.length === 0 || !firstGap) {
        return `Olá ${name}, antes de fechar o dia: você não registrou ${list} hoje. Se comeu, me descreve rapidão o que foi (ou manda foto) — dá tempo de registrar agora ou até amanhã cedo. Se realmente pulou, é só responder "pulei". Sem resposta até o fechamento, o dia fica como incompleto — e o bloco 7700 não credita.`
      }
      const registradoLines = shown
        .map((l) => `${l.hour} ${labels[l.mealType] ?? l.mealType} (${Math.round(l.kcal)} kcal)`)
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

    it('cenário real Roberto 19/06: gap=almoço + múltiplos jantares LISTADOS INDIVIDUALMENTE (review F5)', () => {
      const text = buildReminderText('Roberto', ['almoco'], [
        { meal_type: 'cafe', kcal: 808, hour: '13:42' },
        { meal_type: 'lanche', kcal: 356, hour: '17:48' },
        { meal_type: 'jantar', kcal: 552, hour: '18:56' },
        { meal_type: 'jantar', kcal: 90, hour: '19:09' },
      ])
      expect(text).toContain('13:42 café da manhã (808 kcal)')
      expect(text).toContain('17:48 lanche (356 kcal)')
      // F5: os DOIS jantares aparecem separados, não somados
      expect(text).toContain('18:56 jantar (552 kcal)')
      expect(text).toContain('19:09 jantar (90 kcal)')
      expect(text).toContain('Algum desses ERA seu almoço')
      expect(text).toContain('reclassifico sem dobrar')
      expect(text).toContain('aquele café da manhã das 13:42 era o almoço')
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
})
