/** Immutable presentation facts. Storage/ownership and replay belong to the authenticated writer. */
import { z } from 'zod'
import {
  type FlowClinicalPolicy,
  type FlowClinicalToday,
  readFlowClinicalPolicy,
} from './flow-current-clinical.js'

export interface FeedbackV2Nutrients {
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}
export interface FeedbackV2MealItem extends FeedbackV2Nutrients {
  log_id: string
  food_name: string
  quantity_g: number
  quantity: {
    value: number
    unit: 'g' | 'mL' | 'unit' | 'scoop'
    estimated: boolean
    reference_id: string | null
  }
  nutrition_source: string
}
export type FeedbackV2Registration =
  | {
      kind: 'meal'
      meal_kind: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro'
      items: FeedbackV2MealItem[]
      totals: FeedbackV2Nutrients
    }
  | {
      kind: 'workout'
      log_id: string
      workout_type: string
      duration_min: number | null
      intensity: string | null
      estimated_kcal: number | null
    }
export type FeedbackV2Day = {
  local_date: string
  current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
  consumed: { calories_kcal: number; protein_g: number; carbs_g: number; fat_g: number }
  targets: { calories_kcal: number | null; protein_g: number | null }
  calorie_percentage: number | null
  protein_percentage: number | null
  remaining_food_kcal: number | null
  food_excess_kcal: number | null
  exercise_kcal: number
}
export type FeedbackV2Block =
  | {
      status: 'available'
      target_kcal: 7700
      current_kcal: number
      percentage: number
      completed_blocks: number
      total_credited_kcal: number
    }
  | { status: 'unavailable' | 'not_applicable' | 'protected' }
export interface RegistrationFeedbackV2 {
  schema: 'registration.feedback.v2'
  registration_id: string
  local_date: string
  locale: 'pt-BR' | 'en'
  assistant: 'Flow AI'
  registration: FeedbackV2Registration
  day: FeedbackV2Day | null
  block: FeedbackV2Block
  guidance: 'available' | 'paused' | 'unavailable'
  education:
    | {
        status: 'available'
        text: string
        provenance: {
          source: 'reviewed_template'
          catalog_version: 'registration.education.v1'
          template_id: string
          preferences_known: boolean
        }
      }
    | { status: 'unavailable' }
}
export interface RegistrationFeedbackV2Input {
  registrationId: string
  localDate: string
  locale: string | null
  registration: FeedbackV2Registration
  /** Already proved owned and same-date by the caller. No Today effects may run here. */
  officialDay: FlowClinicalToday | null
  policy: FlowClinicalPolicy | null
  preferencesKnown?: boolean
  educationAvailable?: boolean
}
export interface FeedbackV2Identity {
  registrationId: string
  kind: 'meal' | 'workout'
}
export interface FeedbackV2Section {
  key: 'saved' | 'items' | 'summary' | 'day' | 'block' | 'education'
  text: string
}

const amount = z.number().finite().min(0).max(Number.MAX_SAFE_INTEGER)
const positive = amount.positive()
const text = z.string().trim().min(1).max(240)
const nutrients = z
  .object({ kcal: amount, protein_g: amount, carbs_g: amount, fat_g: amount })
  .strict()
const mealItem = nutrients
  .extend({
    log_id: z.string().uuid(),
    food_name: text,
    quantity_g: positive.max(9999),
    quantity: z
      .object({
        value: positive.max(999999),
        unit: z.enum(['g', 'mL', 'unit', 'scoop']),
        estimated: z.boolean(),
        reference_id: text.nullable(),
      })
      .strict(),
    nutrition_source: z.enum([
      'taco',
      'canonical_exact',
      'canonical_fuzzy',
      'canonical_composite',
      'canonical_composite_partial',
      'rule_based',
      'user_correction',
      'history',
      'user_kcal',
      'product_label',
      'pending_approved',
      'llm_estimate',
    ]),
  })
  .strict()
const registration = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('meal'),
      meal_kind: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
      items: z.array(mealItem).min(1).max(30),
      totals: nutrients,
    })
    .strict(),
  z
    .object({
      kind: z.literal('workout'),
      log_id: z.string().uuid(),
      workout_type: text,
      duration_min: positive.max(1440).nullable(),
      intensity: text.nullable(),
      estimated_kcal: amount.nullable(),
    })
    .strict(),
])
const daySchema = z
  .object({
    local_date: z.string().date(),
    current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
    consumed: z
      .object({ calories_kcal: amount, protein_g: amount, carbs_g: amount, fat_g: amount })
      .strict(),
    targets: z
      .object({ calories_kcal: positive.nullable(), protein_g: positive.nullable() })
      .strict(),
    calorie_percentage: amount.nullable(),
    protein_percentage: amount.nullable(),
    remaining_food_kcal: amount.nullable(),
    food_excess_kcal: amount.nullable(),
    exercise_kcal: amount,
  })
  .strict()
const blockSchema = z.union([
  z
    .object({
      status: z.literal('available'),
      target_kcal: z.literal(7700),
      current_kcal: amount,
      percentage: amount,
      completed_blocks: amount.int(),
      total_credited_kcal: amount,
    })
    .strict(),
  z.object({ status: z.enum(['unavailable', 'not_applicable', 'protected']) }).strict(),
])
const educationSchema = z.discriminatedUnion('status', [
  z
    .object({
      status: z.literal('available'),
      text: z.string().min(1).max(1600),
      provenance: z
        .object({
          source: z.literal('reviewed_template'),
          catalog_version: z.literal('registration.education.v1'),
          template_id: z.enum([
            'milk_whey',
            'meal_protein',
            'meal_energy',
            'meal_general',
            'activity_walking',
            'activity_strength',
            'activity_general',
            'clinical_pause',
          ]),
          preferences_known: z.boolean(),
        })
        .strict(),
    })
    .strict(),
  z.object({ status: z.literal('unavailable') }).strict(),
])
const receiptSchema = z
  .object({
    schema: z.literal('registration.feedback.v2'),
    registration_id: z.string().uuid(),
    local_date: z.string().date(),
    locale: z.enum(['pt-BR', 'en']),
    assistant: z.literal('Flow AI'),
    registration,
    day: daySchema.nullable(),
    block: blockSchema,
    guidance: z.enum(['available', 'paused', 'unavailable']),
    education: educationSchema,
  })
  .strict()
const percentage = (value: number, target: number | null) =>
  target === null ? null : Math.round((value / target) * 1000) / 10
const close = (a: number, b: number) => Math.abs(a - b) < 0.000001
const coherentBlock = (b: Extract<FeedbackV2Block, { status: 'available' }>) =>
  b.percentage === Math.round((b.current_kcal / b.target_kcal) * 100) &&
  close(b.total_credited_kcal, b.completed_blocks * b.target_kcal + b.current_kcal)
const normalize = (value: string) =>
  value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()

/** Reviewed, version-pinned copy; no writer tools, model call or private prompt.
 * Activity principle: WHO physical-activity factsheet, 2024-06-26, overview and
 * guidelines sections (checked 2026-11-03). Quantities/targets are never authored here.
 * Food context describes the recorded facts, not a prescribed diet or diagnosis.
 * Changing any historical template requires a NEW catalog version and reader. */
function educationFor(
  feedback: Omit<RegistrationFeedbackV2, 'education'>,
  preferencesKnown: boolean,
): RegistrationFeedbackV2['education'] {
  const en = feedback.locale === 'en'
  const r = feedback.registration
  let id: Extract<
    z.infer<typeof educationSchema>,
    { status: 'available' }
  >['provenance']['template_id']
  let body: string
  if (feedback.guidance === 'paused') {
    id = 'clinical_pause'
    body = en
      ? 'Your record remains available. Weight-loss guidance is paused; seek a professional assessment before changing your targets.'
      : 'Seu registro continua disponível. As orientações de perda de peso estão pausadas; procure avaliação profissional antes de alterar suas metas.'
  } else if (r.kind === 'workout') {
    const type = normalize(r.workout_type)
    if (['caminhada', 'walking', 'walk'].includes(type)) {
      id = 'activity_walking'
      body = en
        ? 'Walking contributes to an active routine. Its value goes beyond estimated calories; it is a different stimulus from muscle-strengthening exercise.'
        : 'A caminhada contribui para uma rotina ativa. Seu valor vai além das calorias estimadas; é um estímulo diferente dos exercícios de fortalecimento muscular.'
    } else if (
      ['musculacao', 'treino de forca', 'strength training', 'resistance training'].includes(type)
    ) {
      id = 'activity_strength'
      body = en
        ? 'This strength session records a muscle-strengthening stimulus. Energy expenditure alone does not describe the session; sets, repetitions and load help track its execution.'
        : 'Este treino de força registra um estímulo de fortalecimento muscular. O gasto energético sozinho não descreve a sessão; séries, repetições e carga ajudam a acompanhar sua execução.'
    } else {
      id = 'activity_general'
      body = en
        ? 'This activity contributes to your movement routine. Estimated expenditure varies with duration and intensity and is not a measurement of muscle gain.'
        : 'Esta atividade contribui para sua rotina de movimento. O gasto estimado varia com duração e intensidade e não mede ganho de massa muscular.'
    }
  } else {
    const names = r.items.map((item) => normalize(item.food_name))
    if (
      names.some((name) => ['leite', 'leite integral'].includes(name)) &&
      names.some((name) => ['whey', 'whey protein', 'whey protein em po'].includes(name))
    ) {
      id = 'milk_whey'
      body = en
        ? 'Milk and whey both contribute to the protein shown for this drink. The scoop is an editable reference; checking the label helps account for differences between products.'
        : 'Leite e whey contribuem juntos para a proteína mostrada nesta bebida. A medida é uma referência editável; conferir o rótulo ajuda a considerar diferenças entre produtos.'
    } else if (r.totals.protein_g > 0) {
      id = 'meal_protein'
      const energy = r.items.reduce((a, b) => (a.kcal >= b.kcal ? a : b))
      const protein = r.items.reduce((a, b) => (a.protein_g >= b.protein_g ? a : b))
      body = en
        ? `Among the recorded items, ${energy.food_name} has the largest energy contribution and ${protein.food_name} the largest protein contribution. Changing a portion affects both energy and nutrients; compare the items before deciding what to adjust.`
        : `Entre os itens registrados, ${energy.food_name} tem a maior contribuição de energia e ${protein.food_name} a maior contribuição de proteína. Mudar uma porção afeta a energia e os nutrientes; compare os itens antes de decidir o que ajustar.`
    } else if (r.totals.kcal > 0) {
      id = 'meal_energy'
      body = en
        ? 'The portions determine the energy shown for this meal. Check the individual items to see which contributes most; one record alone does not define the quality of your whole day.'
        : 'As porções determinam a energia mostrada nesta refeição. Confira os itens para ver qual contribui mais; um registro isolado não define a qualidade de todo o seu dia.'
    } else {
      id = 'meal_general'
      body = en
        ? 'This record preserves the amounts you provided. If the food or preparation changes, editing the item updates its calculation without recording the meal again.'
        : 'Este registro preserva as quantidades informadas. Se o alimento ou preparo mudar, editar o item atualiza seu cálculo sem registrar a refeição outra vez.'
    }
  }
  const objective = feedback.day?.current_protocol
  if (feedback.guidance === 'available' && objective === 'ganho_massa')
    body += en
      ? ' For your current goal, follow the whole routine rather than interpreting this event as muscle gain.'
      : ' No seu objetivo atual, acompanhe o conjunto da rotina sem interpretar este evento como ganho de massa.'
  else if (
    feedback.guidance === 'available' &&
    objective === 'recomposicao' &&
    feedback.block.status === 'available'
  )
    body += en
      ? ' Your long-term block uses consolidated days, not an immediate credit for this record.'
      : ' Seu bloco de longo prazo usa dias consolidados, sem crédito imediato por este registro.'
  if (feedback.guidance !== 'paused')
    body += preferencesKnown
      ? en
        ? ' Would you like to explore an adjustment that respects the preferences you already shared?'
        : ' Quer pensar em um ajuste que respeite as preferências que você já informou?'
      : en
        ? ' Would you like to tell me what you prefer so we can discuss a suitable adjustment?'
        : ' Quer me contar o que você prefere para conversarmos sobre um ajuste adequado?'
  return educationSchema.parse({
    status: 'available',
    text: body,
    provenance: {
      source: 'reviewed_template',
      catalog_version: 'registration.education.v1',
      template_id: id,
      preferences_known: preferencesKnown,
    },
  })
}

/** Pure projection only. The caller must establish ownership and persisted facts. */
export function prepareRegistrationFeedbackV2(
  input: RegistrationFeedbackV2Input,
): RegistrationFeedbackV2 {
  const facts = registration.parse(input.registration)
  let policy: FlowClinicalPolicy | null = null
  try {
    if (input.policy) policy = readFlowClinicalPolicy(input.policy)
  } catch {
    /* Optional context fails closed. */
  }
  const usable = policy?.assessment === 'complete'
  const paused = policy?.pause_weight_loss_guidance === true
  const official = input.officialDay
  let day: FeedbackV2Day | null = null
  if (
    policy &&
    usable &&
    official?.local_date === input.localDate &&
    official.consumed.source === 'daily_snapshot'
  ) {
    const calories =
      !paused && !policy.hide.calories && official.targets.calories_source === 'daily_snapshot'
        ? official.targets.calories_kcal
        : null
    const protein =
      !paused && !policy.hide.protein && official.targets.protein_source === 'daily_snapshot'
        ? official.targets.protein_g
        : null
    day = daySchema.parse({
      local_date: official.local_date,
      current_protocol: paused || policy.hide.objective ? null : official.current_protocol,
      consumed: {
        calories_kcal: official.consumed.calories_kcal,
        protein_g: official.consumed.protein_g,
        carbs_g: official.consumed.carbs_g,
        fat_g: official.consumed.fat_g,
      },
      targets: { calories_kcal: calories, protein_g: protein },
      calorie_percentage: percentage(official.consumed.calories_kcal, calories),
      protein_percentage: percentage(official.consumed.protein_g, protein),
      remaining_food_kcal:
        calories === null || policy.hide.balance ? null : official.remaining_food_kcal,
      food_excess_kcal: calories === null || policy.hide.balance ? null : official.food_excess_kcal,
      exercise_kcal: official.exercise_kcal,
    })
  }
  let block: FeedbackV2Block = { status: 'unavailable' }
  const progress = official?.block_7700
  if (policy && usable && (paused || policy.hide.block || policy.hide.objective))
    block = { status: 'protected' }
  else if (day && day.current_protocol !== null && day.current_protocol !== 'recomposicao')
    block = { status: 'not_applicable' }
  else if (
    day?.current_protocol === 'recomposicao' &&
    progress?.enabled &&
    progress.availability === 'available' &&
    progress.source === 'user_progress'
  ) {
    const candidate = blockSchema.safeParse({
      status: 'available',
      target_kcal: progress.target_kcal,
      current_kcal: progress.current_kcal,
      percentage: progress.percentage,
      completed_blocks: progress.completed_blocks,
      total_credited_kcal: progress.total_credited_kcal,
    })
    if (candidate.success && candidate.data.status === 'available' && coherentBlock(candidate.data))
      block = candidate.data
  }
  const base: Omit<RegistrationFeedbackV2, 'education'> = {
    schema: 'registration.feedback.v2',
    registration_id: input.registrationId,
    local_date: input.localDate,
    locale: input.locale?.toLowerCase().startsWith('en') ? 'en' : 'pt-BR',
    assistant: 'Flow AI',
    registration: facts,
    day,
    block,
    guidance: paused ? 'paused' : usable ? 'available' : 'unavailable',
  }
  return parseRegistrationFeedbackV2(
    {
      ...base,
      education:
        input.educationAvailable === false
          ? { status: 'unavailable' }
          : educationFor(base, input.preferencesKnown === true),
    },
    { registrationId: input.registrationId, kind: facts.kind },
  )
}

/** Closed transport/storage boundary. No coercion, private authority or arbitrary education. */
export function parseRegistrationFeedbackV2(
  value: unknown,
  identity: FeedbackV2Identity,
): RegistrationFeedbackV2 {
  z.string().uuid().parse(identity.registrationId)
  z.enum(['meal', 'workout']).parse(identity.kind)
  const feedback = receiptSchema.parse(value)
  const d = feedback.day
  if (
    feedback.registration_id !== identity.registrationId ||
    feedback.registration.kind !== identity.kind ||
    (d &&
      (d.local_date !== feedback.local_date ||
        d.calorie_percentage !== percentage(d.consumed.calories_kcal, d.targets.calories_kcal) ||
        d.protein_percentage !== percentage(d.consumed.protein_g, d.targets.protein_g) ||
        (d.targets.calories_kcal === null &&
          (d.remaining_food_kcal !== null || d.food_excess_kcal !== null)) ||
        (d.remaining_food_kcal !== null &&
          d.food_excess_kcal !== null &&
          d.remaining_food_kcal > 0 &&
          d.food_excess_kcal > 0))) ||
    (feedback.guidance === 'unavailable' && d !== null) ||
    (feedback.guidance === 'paused' &&
      d !== null &&
      (d.current_protocol !== null ||
        d.targets.calories_kcal !== null ||
        d.targets.protein_g !== null))
  )
    throw new Error('Invalid feedback v2 day or identity')
  const r = feedback.registration
  if (
    r.kind === 'meal' &&
    (new Set(r.items.map((item) => item.log_id)).size !== r.items.length ||
      r.items.some(
        (item) =>
          (item.quantity.unit === 'g' && !close(item.quantity.value, item.quantity_g)) ||
          (item.quantity.estimated &&
            item.quantity.unit !== 'g' &&
            item.quantity.reference_id === null),
      ))
  )
    throw new Error('Invalid feedback v2 item quantity or identity')
  const b = feedback.block
  if (
    b.status === 'available' &&
    (!d ||
      d.current_protocol !== 'recomposicao' ||
      feedback.guidance !== 'available' ||
      !coherentBlock(b))
  )
    throw new Error('Invalid feedback v2 consolidated block')
  if (
    b.status === 'not_applicable' &&
    (!d || d.current_protocol === null || d.current_protocol === 'recomposicao')
  )
    throw new Error('Invalid feedback v2 objective')
  if (feedback.education.status === 'available') {
    const expected = educationFor(feedback, feedback.education.provenance.preferences_known)
    if (
      expected.status !== 'available' ||
      expected.text !== feedback.education.text ||
      expected.provenance.template_id !== feedback.education.provenance.template_id
    )
      throw new Error('Invalid feedback v2 education provenance')
  }
  return feedback
}

/** The six approved blocks are rendered from facts in a fixed order, never model-authored numbers. */
export function renderRegistrationFeedbackV2(raw: RegistrationFeedbackV2): FeedbackV2Section[] {
  const f = parseRegistrationFeedbackV2(raw, {
    registrationId: raw.registration_id,
    kind: raw.registration.kind,
  })
  const en = f.locale === 'en'
  const formatter = new Intl.NumberFormat(en ? 'en-US' : 'pt-BR', { maximumFractionDigits: 2 })
  const n = (v: number) => formatter.format(v)
  const macros = (v: FeedbackV2Nutrients) =>
    `${n(v.kcal)} kcal | ${en ? 'Protein' : 'Proteína'}: ${n(v.protein_g)} g | ${en ? 'Carbohydrates' : 'Carboidratos'}: ${n(v.carbs_g)} g | ${en ? 'Fat' : 'Gorduras'}: ${n(v.fat_g)} g`
  const r = f.registration
  const mealLabels = en
    ? {
        cafe: 'Breakfast',
        almoco: 'Lunch',
        lanche: 'Snack',
        jantar: 'Dinner',
        ceia: 'Supper',
        outro: 'Meal',
      }
    : {
        cafe: 'Café da manhã',
        almoco: 'Almoço',
        lanche: 'Lanche',
        jantar: 'Jantar',
        ceia: 'Ceia',
        outro: 'Refeição',
      }
  const result: FeedbackV2Section[] = [
    {
      key: 'saved',
      text:
        r.kind === 'meal'
          ? `${mealLabels[r.meal_kind]} ${en ? 'recorded' : 'registrado'}.`
          : en
            ? 'Activity recorded.'
            : 'Atividade registrada.',
    },
  ]
  if (r.kind === 'meal') {
    result.push({
      key: 'items',
      text: r.items
        .map((item) => {
          const q = item.quantity
          const unit =
            q.unit === 'scoop'
              ? en
                ? q.value === 1
                  ? 'scoop'
                  : 'scoops'
                : q.value === 1
                  ? 'medida'
                  : 'medidas'
              : q.unit === 'unit'
                ? en
                  ? q.value === 1
                    ? 'unit'
                    : 'units'
                  : q.value === 1
                    ? 'unidade'
                    : 'unidades'
                : q.unit
          return `${item.food_name} · ${n(q.value)} ${unit}${q.estimated ? (en ? ' (estimated, editable)' : ' (estimado, editável)') : ''}\n${macros(item)}`
        })
        .join('\n\n'),
    })
    result.push({
      key: 'summary',
      text: `${en ? 'Approximate meal total' : 'Total aproximado da refeição'}: ${macros(r.totals)}`,
    })
  } else {
    result.push({
      key: 'items',
      text: `${r.workout_type} · ${r.duration_min === null ? (en ? 'Duration unavailable' : 'Duração indisponível') : `${n(r.duration_min)} min`} · ${r.intensity ?? (en ? 'Intensity unavailable' : 'Intensidade indisponível')}`,
    })
    result.push({
      key: 'summary',
      text:
        r.estimated_kcal === null
          ? en
            ? 'Estimated expenditure unavailable.'
            : 'Gasto estimado indisponível.'
          : `${en ? 'Estimated expenditure' : 'Gasto estimado'}: ${n(r.estimated_kcal)} kcal.`,
    })
  }
  const dayLines: string[] = []
  const d = f.day
  if (!d)
    dayLines.push(
      en
        ? 'The official summary for this day is unavailable; your record was saved.'
        : 'O resumo oficial deste dia está indisponível; seu registro foi salvo.',
    )
  else {
    dayLines.push(`${en ? 'Day' : 'Dia'}: ${d.local_date}`)
    dayLines.push(
      d.targets.calories_kcal === null || d.calorie_percentage === null
        ? `${en ? 'Consumed' : 'Consumido'}: ${n(d.consumed.calories_kcal)} kcal. ${en ? 'Target unavailable' : 'Meta indisponível'}.`
        : `${en ? 'Consumed' : 'Consumido'}: ${n(d.consumed.calories_kcal)} / ${n(d.targets.calories_kcal)} kcal (${n(d.calorie_percentage)}%).`,
    )
    dayLines.push(
      d.targets.protein_g === null || d.protein_percentage === null
        ? `${en ? 'Protein' : 'Proteína'}: ${n(d.consumed.protein_g)} g. ${en ? 'Target unavailable' : 'Meta indisponível'}.`
        : `${en ? 'Protein' : 'Proteína'}: ${n(d.consumed.protein_g)} / ${n(d.targets.protein_g)} g (${n(d.protein_percentage)}%).`,
    )
    if (d.food_excess_kcal !== null && d.food_excess_kcal > 0)
      dayLines.push(`${en ? 'Food excess' : 'Excedente alimentar'}: ${n(d.food_excess_kcal)} kcal.`)
    else if (d.remaining_food_kcal !== null)
      dayLines.push(
        `${en ? 'Remaining for food' : 'Restam para comida'}: ${n(d.remaining_food_kcal)} kcal.`,
      )
    else dayLines.push(en ? 'Food budget unavailable.' : 'Saldo alimentar indisponível.')
    dayLines.push(
      `${en ? 'Recorded exercise' : 'Exercício registrado'}: ${n(d.exercise_kcal)} kcal. ${en ? 'It does not increase the food budget.' : 'Esse gasto não aumenta a comida disponível.'}`,
    )
  }
  result.push({ key: 'day', text: dayLines.join('\n') })
  const b = f.block
  result.push({
    key: 'block',
    text:
      b.status === 'available'
        ? `${en ? 'Block 7,700' : 'Bloco 7.700'}: ${n(b.current_kcal)} / ${n(b.target_kcal)} kcal (${n(b.percentage)}%).\n${en ? 'Total already consolidated' : 'Saldo total já consolidado'}: ${n(b.total_credited_kcal)} kcal · ${en ? 'Completed blocks' : 'Blocos concluídos'}: ${n(b.completed_blocks)}.\n${en ? 'Theoretical reference; this record does not create an immediate credit or guarantee a physical weight change.' : 'Referência teórica; este registro não cria crédito imediato nem garante uma mudança física de peso.'}`
        : b.status === 'not_applicable'
          ? en
            ? 'Block 7,700 does not apply to your current objective.'
            : 'O Bloco 7.700 não se aplica ao seu objetivo atual.'
          : b.status === 'protected'
            ? en
              ? 'Long-term guidance is paused.'
              : 'As orientações de longo prazo estão pausadas.'
            : en
              ? 'Consolidated block data is unavailable.'
              : 'Os dados consolidados do bloco estão indisponíveis.',
  })
  result.push({
    key: 'education',
    text:
      f.education.status === 'available'
        ? f.education.text
        : en
          ? 'The educational comment is unavailable; your record remains saved.'
          : 'O comentário educativo está indisponível; seu registro continua salvo.',
  })
  return result
}
