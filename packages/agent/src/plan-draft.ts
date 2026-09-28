/**
 * Rascunhos de plano (C3/C4 da beta funcional).
 *
 * Um plano proposto pelo Flow ou lido de um documento é um RASCUNHO: só vira
 * plano depois que o paciente revisa e confirma no app. Este módulo decide
 * uma única coisa — se o conteúdo de um rascunho está completo para ser
 * confirmado — e o que fazer com o que não está:
 *
 *   - valor ausente ou fora da faixa fica `null` e é marcado como incerto;
 *   - nada é ajustado, arredondado para dentro da faixa ou preenchido;
 *   - nenhuma caloria ou macro é calculado aqui.
 *
 * Medicamento, suplemento e dose não têm campo em nenhum dos dois formatos:
 * um trecho assim só pode existir como texto não reconhecido.
 */
import { z } from 'zod'
import { ShoppingItemSchema } from './diet-generator.js'
import { TrainingDaySchema } from './training-plan-generator.js'

export type PlanDraftDomain = 'training' | 'nutrition'
export type PlanDraftOrigin = 'flow_generated' | 'imported_photo' | 'imported_pdf'

/**
 * `not_in_document`: o número veio da leitura de um documento, mas não está
 * escrito nele — fica vazio até o paciente informar.
 */
export type PlanDraftUncertainReason =
  | 'missing'
  | 'out_of_range'
  | 'invalid'
  | 'not_in_document'

export interface PlanDraftUncertainField {
  /** Ponteiro JSON (RFC 6901) dentro do conteúdo do rascunho. */
  pointer: string
  reason: PlanDraftUncertainReason
}

export const PLAN_DRAFT_MAX_UNCERTAIN_FIELDS = 200
export const PLAN_DRAFT_MAX_UNRECOGNIZED_SEGMENTS = 40
export const PLAN_DRAFT_MAX_SEGMENT_LENGTH = 500

const optionalText = (max: number) => z.string().trim().min(1).max(max).optional()

/** Treino pronto para confirmar: os mesmos limites do gerador. */
export const trainingDraftPayloadSchema = z
  .object({
    plan_type: z.enum(['split', 'full_body', 'custom']).default('custom'),
    equipment_summary: optionalText(500),
    weekly_schedule: z.array(TrainingDaySchema).min(1).max(7),
    progression_rule: optionalText(500),
    notes: optionalText(500),
  })
  .strip()

const macro = (max: number) => z.number().min(0).max(max).nullable().optional()

/**
 * Dieta pronta para confirmar. Alimento e quantidade são obrigatórios;
 * calorias e macros são opcionais — um plano importado que não os traz fica
 * sem eles, nunca com valores calculados aqui.
 */
export const nutritionDraftPayloadSchema = z
  .object({
    mode: z.enum(['rigida', 'referencia']).optional(),
    horizon: z.enum(['daily', 'weekly']).default('daily'),
    meta_kcal: macro(10_000),
    meta_protein_g: macro(1_000),
    daily_meals: z
      .array(
        z
          .object({
            meal_type: z.enum(['cafe', 'lanche_manha', 'almoco', 'lanche_tarde', 'jantar', 'ceia']),
            day_of_week: z.number().int().min(1).max(7).optional(),
            time_suggestion: optionalText(40),
            items: z
              .array(
                z
                  .object({
                    food_name: z.string().trim().min(1).max(120),
                    quantity_g: z.number().positive().max(2000),
                    display_qty: z.number().positive().max(10_000).optional(),
                    display_unit: optionalText(20),
                    kcal: macro(3000),
                    protein_g: macro(300),
                    carbs_g: macro(500),
                    fat_g: macro(300),
                  })
                  .strip(),
              )
              .min(1)
              .max(12),
            total_kcal: macro(3000),
            total_protein_g: macro(300),
            notes: optionalText(300),
          })
          .strip(),
      )
      .min(1)
      .max(42),
    shopping_list: z.array(ShoppingItemSchema).max(120).default([]),
    notes: optionalText(500),
  })
  .strip()

export type TrainingDraftPayload = z.infer<typeof trainingDraftPayloadSchema>
export type NutritionDraftPayload = z.infer<typeof nutritionDraftPayloadSchema>

const STRICT_SCHEMAS = {
  training: trainingDraftPayloadSchema,
  nutrition: nutritionDraftPayloadSchema,
} as const

// Campos que cada formato conhece, por nível. O que não está aqui é
// descartado antes de qualquer validação: um rascunho não carrega chave
// desconhecida (nem dose, nem medicamento, nem instrução).
type Shape = { [key: string]: Shape | [Shape] | true }

const EXERCISE_SHAPE: Shape = {
  name: true,
  muscle_group: true,
  sets: true,
  reps_range: true,
  rest_seconds: true,
  rpe_target: true,
  notes: true,
  execution_steps: true,
  common_mistakes: true,
}

const SHAPES: Record<PlanDraftDomain, Shape> = {
  training: {
    plan_type: true,
    equipment_summary: true,
    weekly_schedule: [{ day: true, focus: true, duration_min: true, exercises: [EXERCISE_SHAPE] }],
    progression_rule: true,
    notes: true,
  },
  nutrition: {
    mode: true,
    horizon: true,
    meta_kcal: true,
    meta_protein_g: true,
    daily_meals: [
      {
        meal_type: true,
        day_of_week: true,
        time_suggestion: true,
        items: [
          {
            food_name: true,
            quantity_g: true,
            display_qty: true,
            display_unit: true,
            kcal: true,
            protein_g: true,
            carbs_g: true,
            fat_g: true,
          },
        ],
        total_kcal: true,
        total_protein_g: true,
        notes: true,
      },
    ],
    shopping_list: [
      { category: true, food_name: true, quantity_g: true, display_qty: true, display_unit: true },
    ],
    notes: true,
  },
}

const MAX_ARRAY_LENGTH = 200
const MAX_TEXT_LENGTH = 2000

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function leaf(value: unknown): unknown {
  if (value === null || typeof value === 'boolean') return value
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value === 'string') return value.slice(0, MAX_TEXT_LENGTH)
  if (Array.isArray(value)) {
    // Só listas de texto são folhas (passos de execução, erros comuns).
    return value
      .filter((entry): entry is string => typeof entry === 'string')
      .slice(0, MAX_ARRAY_LENGTH)
      .map((entry) => entry.slice(0, MAX_TEXT_LENGTH))
  }
  return null
}

function project(value: unknown, shape: Shape): Record<string, unknown> {
  const source = isRecord(value) ? value : {}
  const result: Record<string, unknown> = {}
  for (const [key, inner] of Object.entries(shape)) {
    if (!(key in source) || source[key] === undefined) continue
    const current = source[key]
    if (inner === true) {
      result[key] = leaf(current)
    } else if (Array.isArray(inner)) {
      result[key] = Array.isArray(current)
        ? current.slice(0, MAX_ARRAY_LENGTH).map((entry) => project(entry, inner[0]))
        : null
    } else {
      result[key] = isRecord(current) ? project(current, inner) : null
    }
  }
  return result
}

function pointerOf(path: ReadonlyArray<string | number>): string {
  return path.map((part) => `/${String(part).replace(/~/g, '~0').replace(/\//g, '~1')}`).join('')
}

function valueAt(root: unknown, path: ReadonlyArray<string | number>): unknown {
  let current: unknown = root
  for (const part of path) {
    if (Array.isArray(current) && typeof part === 'number') current = current[part]
    else if (isRecord(current)) current = current[String(part)]
    else return undefined
  }
  return current
}

function clearAt(root: unknown, path: ReadonlyArray<string | number>): void {
  if (path.length === 0) return
  const parent = valueAt(root, path.slice(0, -1))
  const last = path[path.length - 1]
  if (last === undefined) return
  if (isRecord(parent)) parent[String(last)] = null
  // Um item de lista inválido como um todo não é apagado nem trocado: fica
  // como está e o ponteiro diz que precisa de revisão.
}

function reasonOf(issue: z.ZodIssue, current: unknown): PlanDraftUncertainReason {
  if (current === undefined || current === null) return 'missing'
  if (issue.code === 'too_small' || issue.code === 'too_big') {
    // Lista vazia ou texto vazio é ausência; número fora da faixa é faixa.
    if (typeof current === 'number') return 'out_of_range'
    if (typeof current === 'string' && current.trim() === '') return 'missing'
    if (Array.isArray(current) && current.length === 0) return 'missing'
    return 'out_of_range'
  }
  return 'invalid'
}

export interface PlanDraftAssessment {
  /** Conteúdo como fica guardado: só campos conhecidos, inválidos em `null`. */
  payload: Record<string, unknown>
  uncertain_fields: PlanDraftUncertainField[]
  /** `true` só quando o conteúdo passa inteiro na validação de confirmação. */
  complete: boolean
}

/**
 * Avalia o conteúdo de um rascunho. Não lança para conteúdo incompleto: devolve
 * o que falta. Lança `TypeError` só quando o conteúdo não é um objeto.
 */
export function assessPlanDraftPayload(
  domain: PlanDraftDomain,
  candidate: unknown,
): PlanDraftAssessment {
  if (!isRecord(candidate)) throw new TypeError('plan draft payload must be an object')
  const payload = project(candidate, SHAPES[domain])
  const parsed = STRICT_SCHEMAS[domain].safeParse(payload)
  if (parsed.success) {
    return { payload: parsed.data as Record<string, unknown>, uncertain_fields: [], complete: true }
  }

  const seen = new Set<string>()
  const uncertain: PlanDraftUncertainField[] = []
  for (const issue of parsed.error.issues) {
    const pointer = pointerOf(issue.path)
    if (seen.has(pointer)) continue
    seen.add(pointer)
    const current = valueAt(payload, issue.path)
    uncertain.push({ pointer, reason: reasonOf(issue, current) })
    const isLeaf = current !== undefined && !isRecord(current) && !Array.isArray(current)
    if (isLeaf) clearAt(payload, issue.path)
  }
  return {
    payload,
    uncertain_fields: uncertain.slice(0, PLAN_DRAFT_MAX_UNCERTAIN_FIELDS),
    complete: false,
  }
}

/** Conteúdo confirmável ou `null`. Usado imediatamente antes de confirmar. */
export function confirmablePlanDraftPayload(
  domain: PlanDraftDomain,
  payload: unknown,
): TrainingDraftPayload | NutritionDraftPayload | null {
  if (!isRecord(payload)) return null
  const assessment = assessPlanDraftPayload(domain, payload)
  return assessment.complete
    ? (assessment.payload as TrainingDraftPayload | NutritionDraftPayload)
    : null
}

/** Trechos do original que não viraram campo, como vieram, com limites. */
export function sanitizeUnrecognizedSegments(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  const segments: string[] = []
  for (const entry of value) {
    if (typeof entry !== 'string') continue
    const text = entry.replace(/\s+/g, ' ').trim()
    if (!text) continue
    segments.push(text.slice(0, PLAN_DRAFT_MAX_SEGMENT_LENGTH))
    if (segments.length === PLAN_DRAFT_MAX_UNRECOGNIZED_SEGMENTS) break
  }
  return segments
}

const MEDICATION_HINT =
  /\b(medicament\w*|rem[eé]dio\w*|comprimid\w*|c[aá]psula\w*|\d+\s?(mg|mcg|ui)\b|suplement\w*|creatina|whey|vitamina\w*|[oô]mega|horm[oô]ni\w*|anaboliz\w*|injet[aá]ve\w*|dose\w*|posologia)/i

/** O trecho fala de medicamento, suplemento ou dose (o app avisa que não importa). */
export function mentionsMedication(segment: string): boolean {
  return MEDICATION_HINT.test(segment)
}

/**
 * Validade do plano confirmado. Os gerados seguem a regra que já valia para
 * os geradores (treino 6 semanas; dieta 1 dia ou 7 dias). Um plano importado
 * não recebe validade inventada.
 */
export function planDraftValidUntil(
  domain: PlanDraftDomain,
  origin: PlanDraftOrigin,
  payload: unknown,
  now: Date,
): string | null {
  if (origin !== 'flow_generated') return null
  const day = 24 * 60 * 60 * 1000
  if (domain === 'training') return new Date(now.getTime() + 42 * day).toISOString()
  const weekly = isRecord(payload) && payload.horizon === 'weekly'
  return new Date(now.getTime() + (weekly ? 7 : 1) * day).toISOString()
}
