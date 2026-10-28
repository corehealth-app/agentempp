import type { FlowClinicalPolicy, FlowClinicalToday } from './flow-current-clinical.js'
import type { FlowDayStatusProgress } from './flow-day-status-context.js'

const CLOSING = {
  'pt-BR': {
    recomposicao: 'Nesta fase, o foco é repetir dias bem executados até fechar o bloco.',
    ganho_massa: 'Aqui, o progresso vem da repetição consistente do estímulo — não da balança.',
    manutencao: 'Na manutenção, o corpo responde à média — não a um dia isolado.',
  },
  en: {
    recomposicao:
      'In this phase, the focus is on repeating well-executed days until the block is complete.',
    ganho_massa:
      'Here, progress comes from consistently repeating the stimulus — not from the scale.',
    manutencao: 'In maintenance, the body responds to the average — not to an isolated day.',
  },
} as const

/** Flow-only presentation. Amounts and availability come from official Today. */
export function renderFlowDayStatus(
  today: FlowClinicalToday,
  locale: string | null,
  progress: FlowDayStatusProgress | null = null,
  policy?: FlowClinicalPolicy,
): string {
  const en = locale?.startsWith('en') ?? false
  const format = new Intl.NumberFormat(en ? 'en-US' : 'pt-BR', { maximumFractionDigits: 2 })
  const n = (value: number) => format.format(value)
  const opening = en
    ? 'Before updating your status: did you have a meal, snack or physical activity that you have not recorded? No pressure — this helps keep everything accurate. Use Register to add anything missing.'
    : 'Antes de atualizar seu status: teve alguma refeição, belisco ou atividade física que você fez e não registrou? Sem cobrança — é só pra manter tudo preciso. Use Registrar para incluir o que faltou.'
  const lines = [`${en ? 'Day status' : 'Status do dia'}: ${today.local_date}`]
  const emptyObserved =
    today.meals.length === 0 &&
    today.workouts.length === 0 &&
    today.consumed.calories_kcal === 0 &&
    today.consumed.protein_g === 0 &&
    today.consumed.carbs_g === 0 &&
    today.consumed.fat_g === 0 &&
    today.exercise_kcal === 0
  if (emptyObserved)
    lines.push(
      en
        ? 'There is no confirmed meal or workout for this day yet.'
        : 'Ainda não há refeição ou treino confirmado neste dia.',
    )
  const pending = today.pending_actions.registrations.length
  if (pending > 0)
    lines.push(
      en
        ? pending === 1
          ? 'There is 1 record awaiting review; it is not included in the totals yet.'
          : 'There are records awaiting review; they are not included in the totals yet.'
        : pending === 1
          ? 'Há 1 registro pendente de revisão; ele ainda não entra nos totais.'
          : 'Há registros pendentes de revisão; eles ainda não entram nos totais.',
    )

  const calories = today.targets.calories_kcal
  lines.push(
    calories === null
      ? `${en ? 'Consumed' : 'Consumido'}: ${n(today.consumed.calories_kcal)} kcal. ${en ? 'Target unavailable' : 'Meta indisponível'}.`
      : `${en ? 'Consumed' : 'Consumido'}: ${n(today.consumed.calories_kcal)} / ${n(calories)} kcal (${n(Math.round((today.consumed.calories_kcal / calories) * 100))}%).`,
  )
  if (today.food_excess_kcal !== null && today.food_excess_kcal > 0)
    lines.push(
      en
        ? `Excess: ${n(today.food_excess_kcal)} kcal of food.`
        : `Excedente: ${n(today.food_excess_kcal)} kcal de comida.`,
    )
  else if (today.remaining_food_kcal !== null)
    lines.push(
      en
        ? `Remaining: ${n(today.remaining_food_kcal)} kcal for food.`
        : `Restam: ${n(today.remaining_food_kcal)} kcal para comida.`,
    )
  lines.push(
    en
      ? `Recorded exercise: ${n(today.exercise_kcal)} kcal. This expenditure does not increase the food remaining.`
      : `Exercício registrado: ${n(today.exercise_kcal)} kcal. Esse gasto não aumenta o que resta para comida.`,
  )

  const protein = today.protein_status
  if (protein.target_g === null || protein.percentage === null)
    lines.push(
      en
        ? `Protein: ${n(protein.consumed_g)} g. Target unavailable.`
        : `Proteína: ${n(protein.consumed_g)} g. Meta indisponível.`,
    )
  else {
    let line = `${en ? 'Protein' : 'Proteína'}: ${n(protein.consumed_g)} / ${n(protein.target_g)} g (${n(protein.percentage)}%).`
    if (protein.status === 'target_reached') line += en ? ' Target reached.' : ' Meta atingida.'
    else if (protein.remaining_g !== null)
      line += en
        ? ` Remaining: ${n(protein.remaining_g)} g.`
        : ` Faltam ${n(protein.remaining_g)} g.`
    lines.push(line)
  }
  if (calories === null || protein.target_g === null)
    lines.push(
      en
        ? 'Check your objective details in Profile.'
        : 'Confira os dados do seu objetivo em Perfil.',
    )

  const balance = today.daily_balance_kcal
  if (today.daily_balance_status === 'insufficient_data')
    lines.push(en ? 'Day balance: insufficient data.' : 'Balanço do dia: dados insuficientes.')
  else if (balance === null)
    lines.push(en ? 'Day balance: unavailable.' : 'Balanço do dia: indisponível.')
  else {
    const state = today.daily_balance_status === 'final' ? 'final' : en ? 'partial' : 'parcial'
    const direction =
      balance < 0
        ? en
          ? 'Deficit of '
          : 'Déficit de '
        : balance > 0
          ? en
            ? 'Surplus of '
            : 'Superávit de '
          : ''
    lines.push(
      `${en ? 'Day balance' : 'Balanço do dia'} (${state}): ${direction}${n(Math.abs(balance))} kcal.`,
    )
  }

  const protocol = today.current_protocol
  const block = today.block_7700
  if (protocol === 'recomposicao' && block.enabled) {
    if (
      block.availability === 'available' &&
      block.target_kcal !== null &&
      block.current_kcal !== null &&
      block.percentage !== null
    ) {
      lines.push(
        en
          ? `Block 7,700: ${n(block.current_kcal)} / ${n(block.target_kcal)} kcal (${n(block.percentage)}%). Theoretical reference for accumulated deficit.`
          : `Bloco 7.700: ${n(block.current_kcal)} / ${n(block.target_kcal)} kcal (${n(block.percentage)}%). Referência teórica de déficit acumulado.`,
      )
      if (block.completed_blocks !== null)
        lines.push(
          en
            ? `Completed blocks: ${n(block.completed_blocks)}.`
            : `Blocos concluídos: ${n(block.completed_blocks)}.`,
        )
    } else lines.push(en ? 'Block 7,700: data unavailable.' : 'Bloco 7.700: dados indisponíveis.')
  } else if (protocol === 'ganho_massa' || protocol === 'manutencao')
    lines.push(
      en
        ? 'Block 7,700 is shown only in body recomposition.'
        : 'O Bloco 7.700 é exibido apenas na recomposição corporal.',
    )
  if (progress) {
    const unit = en
      ? progress.currentStreak === 1
        ? 'day'
        : 'days'
      : progress.currentStreak === 1
        ? 'dia'
        : 'dias'
    lines.push(
      en
        ? `Streak: ${n(progress.currentStreak)} ${unit} · Level: ${n(progress.level)} · XP: ${n(progress.xpTotal)}.`
        : `Sequência: ${n(progress.currentStreak)} ${unit} · Nível: ${n(progress.level)} · XP: ${n(progress.xpTotal)}.`,
    )
  }
  const closing =
    policy?.pause_weight_loss_guidance || policy?.hide.objective || policy?.hide.block
      ? policy?.professional_assessment_recommended
        ? en
          ? 'Weight-loss guidance is paused. Seek a professional assessment; your records and history remain available.'
          : 'As orientações de emagrecimento estão pausadas. Procure avaliação profissional; seus registros e histórico continuam disponíveis.'
        : null
      : protocol
        ? CLOSING[en ? 'en' : 'pt-BR'][protocol]
        : null
  return [opening, lines.join('\n'), closing].filter(Boolean).join('\n\n')
}
