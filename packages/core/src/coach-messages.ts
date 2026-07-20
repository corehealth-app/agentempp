import { z } from 'zod'

export const coachPersonalitySchema = z.enum(['balanced', 'focus', 'impulse', 'zen'])
export const selectableCoachPersonalitySchema = z.enum(['focus', 'impulse', 'zen'])
export const coachMessageContextSchema = z.enum([
  'onboarding',
  'meal_pending',
  'registration_confirmed',
  'error_corrected',
  'hydration',
  'supplement',
  'medication',
  'workout',
  'progress',
  'day_incomplete',
  'reevaluation',
  'reengagement',
  'trial',
  'paywall',
  'return_after_abandonment',
])
export const coachMessageChannelSchema = z.enum(['in_app', 'push', 'email'])
export const coachMessageLocaleSchema = z.enum(['pt-BR', 'en-US'])

export type CoachPersonality = z.infer<typeof coachPersonalitySchema>
export type SelectableCoachPersonality = z.infer<typeof selectableCoachPersonalitySchema>
export type CoachMessageContext = z.infer<typeof coachMessageContextSchema>
export type CoachMessageChannel = z.infer<typeof coachMessageChannelSchema>
export type CoachMessageLocale = z.infer<typeof coachMessageLocaleSchema>

export const COACH_CONTEXT_ALLOWED_VARIABLES = {
  onboarding: ['name'],
  meal_pending: ['name', 'meal'],
  registration_confirmed: [
    'name',
    'meal',
    'protein_remaining_g',
    'kcal_remaining',
    'block_progress_percent',
  ],
  error_corrected: ['name', 'meal'],
  hydration: ['name', 'water_remaining_ml'],
  supplement: ['name', 'supplement_name'],
  medication: ['name', 'medication_name'],
  workout: ['name'],
  progress: ['name', 'protein_remaining_g', 'kcal_remaining', 'block_progress_percent'],
  day_incomplete: ['name', 'meal'],
  reevaluation: ['name', 'next_reevaluation_date'],
  reengagement: ['name'],
  trial: ['name', 'trial_days_remaining'],
  paywall: ['name'],
  return_after_abandonment: ['name'],
} as const satisfies Record<CoachMessageContext, readonly string[]>

export interface CoachTemplateLintInput {
  context: CoachMessageContext
  channel: CoachMessageChannel
  locale: CoachMessageLocale
  title: string | null
  subject: string | null
  body: string
  allowedVariables: readonly string[]
  requiredVariables: readonly string[]
}

export interface CoachTemplateLintIssue {
  code:
    | 'invalid_placeholder'
    | 'unknown_variable'
    | 'missing_required_variable'
    | 'channel_length'
    | 'unsafe_language'
    | 'control_character'
  field: 'title' | 'subject' | 'body' | 'variables'
  message: string
}

type TemplateTextField = 'title' | 'subject' | 'body'

const PLACEHOLDER_PATTERN = /{{([a-z][a-z0-9_]*)}}/g
const PLACEHOLDER_CANDIDATE_PATTERN = /{{[^{}]*}}/g
const VALID_PLACEHOLDER_PATTERN = /^{{[a-z][a-z0-9_]*}}$/

const CHANNEL_LIMITS = {
  in_app: { title: 0, subject: 0, body: 1_200 },
  push: { title: 60, subject: 0, body: 180 },
  email: { title: 0, subject: 120, body: 4_000 },
} as const satisfies Record<CoachMessageChannel, Record<TemplateTextField, number>>

const UNSAFE_LANGUAGE_PATTERNS: Record<CoachMessageLocale, readonly RegExp[]> = {
  'pt-BR': [
    /\b(vergonha|fracass(?:o|ou|ado|ada)|preguicos[oa]|culpa)\b/i,
    /\bgarantid[oa]s?\b/i,
    /\bsem desculpas\b/i,
  ],
  'en-US': [/\b(shame|failed|failure|lazy|guilt)\b/i, /\bguaranteed\b/i, /\bno excuses\b/i],
}

function templateFields(input: CoachTemplateLintInput): Array<{
  field: TemplateTextField
  value: string | null
}> {
  return [
    { field: 'title', value: input.title },
    { field: 'subject', value: input.subject },
    { field: 'body', value: input.body },
  ]
}

function isForbiddenControlCharacter(character: string): boolean {
  const code = character.codePointAt(0)
  return (
    code !== undefined &&
    ((code >= 0 && code <= 8) ||
      code === 11 ||
      code === 12 ||
      (code >= 14 && code <= 31) ||
      code === 127)
  )
}

function containsForbiddenControlCharacter(value: string): boolean {
  return [...value].some(isForbiddenControlCharacter)
}

function stripForbiddenControlCharacters(value: string): string {
  return [...value].filter((character) => !isForbiddenControlCharacter(character)).join('')
}

function foldForSafetyCheck(value: string): string {
  return value.normalize('NFKD').replace(/\p{M}/gu, '')
}

export function extractCoachPlaceholders(value: string): string[] {
  const seen = new Set<string>()
  for (const match of value.matchAll(PLACEHOLDER_PATTERN)) {
    const name = match[1]
    if (name) seen.add(name)
  }
  return [...seen]
}

export function lintCoachTemplate(input: CoachTemplateLintInput): CoachTemplateLintIssue[] {
  const issues: CoachTemplateLintIssue[] = []
  const fields = templateFields(input)

  for (const { field, value } of fields) {
    if (value === null) continue
    if (containsForbiddenControlCharacter(value)) {
      issues.push({
        code: 'control_character',
        field,
        message: `${field} contains a forbidden control character`,
      })
    }
    for (const candidate of value.match(PLACEHOLDER_CANDIDATE_PATTERN) ?? []) {
      if (!VALID_PLACEHOLDER_PATTERN.test(candidate)) {
        issues.push({
          code: 'invalid_placeholder',
          field,
          message: `Invalid coach template placeholder: ${candidate}`,
        })
      }
    }
    const withoutCandidates = value.replace(PLACEHOLDER_CANDIDATE_PATTERN, '')
    if (withoutCandidates.includes('{{') || withoutCandidates.includes('}}')) {
      issues.push({
        code: 'invalid_placeholder',
        field,
        message: `Invalid coach template placeholder syntax in ${field}`,
      })
    }
  }

  const placeholders = extractCoachPlaceholders(fields.map(({ value }) => value ?? '').join('\n'))
  const allowedVariables = new Set(input.allowedVariables)
  const contextVariables = new Set<string>(COACH_CONTEXT_ALLOWED_VARIABLES[input.context])
  for (const declared of allowedVariables) {
    if (!contextVariables.has(declared)) {
      issues.push({
        code: 'unknown_variable',
        field: 'variables',
        message: `Coach template variable ${declared} is not allowed for ${input.context}`,
      })
    }
  }
  for (const placeholder of placeholders) {
    if (!allowedVariables.has(placeholder)) {
      issues.push({
        code: 'unknown_variable',
        field: 'variables',
        message: `Coach template variable is not allowed: ${placeholder}`,
      })
    }
  }
  const placeholderSet = new Set(placeholders)
  for (const required of input.requiredVariables) {
    if (!allowedVariables.has(required)) {
      issues.push({
        code: 'unknown_variable',
        field: 'variables',
        message: `Required coach template variable is not allowed: ${required}`,
      })
    }
    if (!placeholderSet.has(required)) {
      issues.push({
        code: 'missing_required_variable',
        field: 'variables',
        message: `Required coach template variable is absent: ${required}`,
      })
    }
  }

  const limits = CHANNEL_LIMITS[input.channel]
  for (const { field, value } of fields) {
    if (value === null) continue
    const limit = limits[field]
    if (limit === 0 || value.length > limit) {
      issues.push({
        code: 'channel_length',
        field,
        message:
          limit === 0
            ? `${field} is not supported for ${input.channel}`
            : `${field} exceeds the ${input.channel} limit of ${limit} characters`,
      })
    }
  }

  const copy = foldForSafetyCheck(fields.map(({ value }) => value ?? '').join('\n'))
  for (const pattern of UNSAFE_LANGUAGE_PATTERNS[input.locale]) {
    if (pattern.test(copy)) {
      issues.push({
        code: 'unsafe_language',
        field: 'body',
        message: `Coach template contains prohibited ${input.locale} language`,
      })
    }
  }

  return issues
}

function sanitizeVariable(value: string | number): string {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Coach template variable must be finite')
    return String(value)
  }

  return stripForbiddenControlCharacters(value.normalize('NFKC'))
    .replace(/[{}]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 200)
}

function renderField(
  value: string | null,
  variables: Readonly<Record<string, string>>,
): string | null {
  if (value === null) return null
  return value.replace(PLACEHOLDER_PATTERN, (_placeholder, name: string) => {
    const replacement = variables[name]
    if (replacement === undefined) {
      throw new Error(`Missing coach template variable: ${name}`)
    }
    return replacement
  })
}

export function renderCoachTemplate(
  input: CoachTemplateLintInput,
  variables: Record<string, string | number>,
): { title: string | null; subject: string | null; body: string } {
  const issues = lintCoachTemplate(input)
  if (issues.length > 0) {
    throw new Error(`Coach template failed lint: ${issues[0]?.message ?? 'unknown issue'}`)
  }

  const allowed = new Set(input.allowedVariables)
  const sanitized: Record<string, string> = {}
  for (const [name, value] of Object.entries(variables)) {
    if (!allowed.has(name)) throw new Error(`Unexpected coach template variable: ${name}`)
    sanitized[name] = sanitizeVariable(value)
  }
  for (const required of input.requiredVariables) {
    if (sanitized[required] === undefined) {
      throw new Error(`Missing required coach template variable: ${required}`)
    }
  }

  const rendered = {
    title: renderField(input.title, sanitized),
    subject: renderField(input.subject, sanitized),
    body: renderField(input.body, sanitized) ?? '',
  }
  if (templateFields({ ...input, ...rendered }).some(({ value }) => value?.includes('{{'))) {
    throw new Error('Coach template contains an unresolved placeholder')
  }
  return rendered
}

export function chooseLeastRecentlyUsedVariant<
  T extends { id: string; variant: 1 | 2 | 3; lastUsedAt: string | null },
>(candidates: readonly T[], lastSelectedId: string | null): T {
  if (candidates.length === 0) throw new Error('No eligible coach message variants')

  const eligible =
    candidates.length > 1 && lastSelectedId
      ? candidates.filter((candidate) => candidate.id !== lastSelectedId)
      : [...candidates]
  const pool = eligible.length > 0 ? eligible : [...candidates]

  return pool.sort((left, right) => {
    if (left.lastUsedAt === null && right.lastUsedAt !== null) return -1
    if (left.lastUsedAt !== null && right.lastUsedAt === null) return 1
    if (left.lastUsedAt !== null && right.lastUsedAt !== null) {
      const byTime = Date.parse(left.lastUsedAt) - Date.parse(right.lastUsedAt)
      if (byTime !== 0) return byTime
    }
    return left.id.localeCompare(right.id)
  })[0] as T
}
