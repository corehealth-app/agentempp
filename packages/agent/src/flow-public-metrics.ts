/** C1: presentation boundary only. No calculation, persisted data or legacy changes. */
type Targets = { calories_target: number | null; protein_target: number | null }

function normalized(text: string): string {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim()
}

/** Anchored questions only: a second request must still reach the model/tools. */
export function asksPrivateMetricQuestion(text: string | null | undefined): boolean {
  const question = normalized(text ?? '')
    .replace(/[?.!]+$/u, '')
    .trim()
  return (
    /^(?:qual (?:e )?(?:(?:o |a )?meu |(?:a )?minha )?|quanto e (?:o )?meu )(?:bmr|tmb|tdee|metabolismo basal|taxa metabolica basal)$/u.test(
      question,
    ) ||
    /^qual (?:a )?formula (?:voce usa|e usada|usa)$/u.test(question) ||
    /^what (?:is|s) my (?:bmr|tmb|tdee|basal metabolic rate)$/u.test(question) ||
    /^(?:which|what) formula do you use$/u.test(question)
  )
}

/** The recognized question's language wins over the saved account locale. */
export function flowMetricLocale(
  text: string | null | undefined,
  locale: string | null,
): string | null {
  const question = normalized(text ?? '')
  if (/^(?:what|which|how)\b/u.test(question)) return 'en'
  if (/^(?:qual|quanto|como)\b/u.test(question)) return 'pt-BR'
  return locale
}

export function renderOfficialTargets(targets: Targets | null, locale: string | null): string {
  const en = locale?.startsWith('en') ?? false
  const calories = targets?.calories_target
  const protein = targets?.protein_target
  const hasCalories = typeof calories === 'number' && Number.isFinite(calories) && calories > 0
  const hasProtein = typeof protein === 'number' && Number.isFinite(protein) && protein > 0
  if (!hasCalories && !hasProtein) {
    return en
      ? 'Today’s official targets are not available yet. Check your objective details in Profile.'
      : 'As metas oficiais de hoje ainda não estão disponíveis. Confira os dados do seu objetivo em Perfil.'
  }
  const format = new Intl.NumberFormat(en ? 'en-US' : 'pt-BR', { maximumFractionDigits: 2 })
  const parts: string[] = []
  if (hasCalories) parts.push(`${format.format(calories)} kcal`)
  if (hasProtein) parts.push(`${format.format(protein)} ${en ? 'g of protein' : 'g de proteína'}`)
  return en
    ? `Today’s official targets are ${parts.join(' and ')}. You can follow them in Today.`
    : `As metas oficiais de hoje são ${parts.join(' e ')}. Você pode acompanhá-las em Hoje.`
}

/** Closed vocabulary; infant formula, recipes and food energy remain public. */
function hasPrivateMetric(text: string): boolean {
  const value = normalized(text)
  return (
    /\b(?:bmr|tmb|tdee|lbm|katch(?:[- ]mcardle)?|mifflin(?:[- ]st[- ]jeor)?)\b|(?:metabolismo|taxa(?: metabolica)?|rate) basal|basal (?:metabolism|metabolic rate|rate)|gasto (?:energetico total|total diario)|total (?:daily )?energy expenditure|massa magra|lean body mass|fator(?:es)? de atividade|activity factors?/u.test(
      value,
    ) ||
    /(?:10\s*[×*x]\s*(?:peso|weight)|6[.,]25\s*[×*x]\s*(?:altura|height)|21[.,]6\s*[×*x]\s*(?:massa|lean)|370\s*\+\s*21[.,]6)|(?:meta|target).*(?:calculad[oa]|calculated|formula|equacao).*(?:peso|altura|idade|weight|height|age)/u.test(
      value,
    )
  )
}

export function publicBodyFatLabel(text: string, locale: string | null = null): string {
  const label = locale?.startsWith('en') ? 'Body fat' : 'Gordura corporal'
  return text
    .replace(
      /\bSeu BF(?=\s+(?:atual\s+)?(?:está|esta|é|e)\s+(?:em\s+)?\d+[.,]?\d*\s*%)/gi,
      'Sua gordura corporal',
    )
    .replace(
      /\bO BF(?=\s+(?:atual\s+)?(?:está|esta|é|e)\s+(?:em\s+)?\d+[.,]?\d*\s*%)/gi,
      'A gordura corporal',
    )
    .replace(
      /\bBF\s*%\s*([:=])\s*(\d+[.,]?\d*)(\s*%)?/gi,
      (_match, separator: string, value: string) => `${label}${separator} ${value}%`,
    )
    .replace(/\bBF\s*%/gi, label)
    .replace(/\bBF(?=\s*(?::|=|estimado\b|estimated\b|\d+[.,]?\d*\s*%))/gi, label)
    .replace(
      /\bBF(?=(?:\s+(?:atual|estimado|estimated|está|esta|is|é|e|at|em))*\s*\d+[.,]?\d*\s*%)/gi,
      label,
    )
}

/** Split only punctuation/conjunction boundaries, never numeric decimal marks. */
function metricStatementParts(line: string): string[] {
  const boundaries =
    /(?<=[.!?;])\s+|\s+[—–-]\s+|:\s+|\s+(?:e|mas|and|but)\s+|,\s+(?!(?:vezes|times|multiplicad[oa]|multiplied)\b)(?:mas\s+|but\s+)?/giu
  const parts: string[] = []
  let start = 0
  for (const match of line.matchAll(boundaries)) {
    const index = match.index
    if (match[0].startsWith(':') || /[—–-]/u.test(match[0])) {
      const left = line.slice(start, index)
      const right = line.slice(index + match[0].length)
      // Keep a metric label with its numeric value. Public text can be
      // separated from any recognized private clause on either side.
      const valueText = normalized(right).replace(/^(?:(?:e|is|de|of)\s+)+/u, '')
      // Estimation qualifiers may contain prepositions/adverbs. They still
      // belong to the private label, rather than a new public statement.
      const startsWithValue =
        /^[+−-]?\d/u.test(valueText) ||
        /^(?:estimad[oa]|estimated|aproximad[oa]|approximately|aproximadamente|about|around|cerca|roughly|entre|between|[~≈])\b[^.!?;\n]*\d/u.test(
          valueText,
        )
      if (hasPrivateMetric(left) && startsWithValue) continue
      if (
        match[0].startsWith(':') &&
        (startsWithValue || (!hasPrivateMetric(left) && !hasPrivateMetric(right)))
      )
        continue
    }
    parts.push(line.slice(start, index), match[0])
    start = index + match[0].length
  }
  parts.push(line.slice(start))
  return parts
}

function projectStatements(text: string, replacement: string): string {
  if (!hasPrivateMetric(text)) return text
  const factorTable = /fator(?:es)? de atividade|activity factors?/u.test(normalized(text))
  const isTableCoefficient = (statement: string): boolean =>
    factorTable &&
    /^(?:sedentari[oa]|leve|moderad[oa]|alt[oa]|atleta|sedentary|light|moderate|high|athlete|very active)\s*[:=]?\s*\d+(?:[.,]\d+)?[.!;]?$/u.test(
      normalized(statement),
    )
  const withoutParentheticals = text.replace(/\(([^()]*)\)/gu, (whole, content: string) => {
    if (!hasPrivateMetric(content)) return whole
    const publicPart = projectStatements(content, replacement).trim()
    return publicPart ? `(${publicPart})` : ''
  })
  return withoutParentheticals
    .split('\n')
    .map((line) => {
      if (!hasPrivateMetric(line) && !isTableCoefficient(line)) return line.trimEnd()
      const parts = metricStatementParts(line)
      let result = ''
      for (let i = 0; i < parts.length; i += 2) {
        const statement = parts[i] ?? ''
        const value =
          hasPrivateMetric(statement) || isTableCoefficient(statement) ? replacement : statement
        if (!value.trim()) continue
        result += result ? `${parts[i - 1] ?? ' '}${value}` : value.trimStart()
      }
      return result.trim()
    })
    .join('\n')
}

/** Only derived copies; the user's utterances and persisted data stay intact. */
export function projectFlowMetricContext(text: string): string {
  return projectStatements(publicBodyFatLabel(text), '[referência interna omitida]')
}

/** Last boundary, after suggestion reconstruction and the public-name guard. */
export function projectFlowMetricAnswer(
  text: string,
  targets: Targets | null,
  locale: string | null,
  hasSuggestion: boolean,
  fallback?: string,
): string {
  const publicText = publicBodyFatLabel(text, locale)
  if (!hasPrivateMetric(publicText)) return publicText
  const kept = projectStatements(publicText, '').trim()
  const result = kept || fallback || renderOfficialTargets(targets, locale)
  if (!hasSuggestion || /Revisar sugestão|Review suggestion/i.test(result)) return result
  return `${result}\n\n${locale?.startsWith('en') ? 'Your suggestion is ready to review in the app.' : 'Sua sugestão está pronta em "Revisar sugestão".'}`
}

/** Read projection only: a historical reply cannot imply today's target is absent. */
export function projectStoredFlowMetricAnswer(
  text: string,
  locale: string | null,
  hasSuggestion: boolean,
): string {
  // Keep a recognizable historical language; ambiguous labels such as BMR
  // alone use the already authenticated locale. This is not translation.
  const value = normalized(text)
  const pt =
    /\b(?:seu|sua|gordura corporal|(?:metabolismo|taxa(?: metabolica)?) basal|massa magra|fator(?:es)? de atividade|metas? oficia(?:l|is)|gasto (?:energetico total|total diario)|estimad[oa]|aproximad[oa]|aproximadamente|cerca de|entre)\b/u.test(
      value,
    )
  const en =
    /\b(?:your|my|body fat|basal (?:metabolism|metabolic rate|rate)|lean body mass|activity factors?|official targets?|total (?:daily )?energy expenditure|estimated|approximately|about|around|roughly|between)\b/u.test(
      value,
    )
  const storedLocale = pt !== en ? (en ? 'en' : 'pt-BR') : locale
  const fallback = storedLocale?.startsWith('en')
    ? 'Check your official targets in Today and your objective details in Profile.'
    : 'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.'
  return projectFlowMetricAnswer(text, null, storedLocale, hasSuggestion, fallback)
}
