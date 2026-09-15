import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { OnboardingCompletionInput } from './contracts'
import {
  type OnboardingAcceptedActionRecord,
  type OnboardingDocumentRecord,
  type OnboardingDraftRecord,
  type OnboardingRepository,
  OnboardingRepositoryError,
} from './onboarding-service'

const documentSchema = z
  .object({
    id: z.string().uuid(),
    document_key: z.string().regex(/^[a-z][a-z0-9_]{0,99}$/),
    version: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
    locale: z.enum(['pt-BR', 'en-US']),
    body: z.string().min(1).max(12_000).nullable(),
    content_url: z.string().url().startsWith('https://').max(2_048).nullable(),
    content_hash: z.string().regex(/^[0-9a-f]{64}$/),
    purpose: z.string().regex(/^[a-z][a-z0-9_]{0,159}$/),
    action_type: z.enum(['acceptance', 'acknowledgement', 'consent']),
    required: z.boolean(),
    effective_at: z.string().datetime({ offset: true }),
    published_at: z.string().datetime({ offset: true }),
  })
  .strict()
  .refine((value) => (value.body === null) !== (value.content_url === null))

const acceptedActionSchema = z
  .object({
    document_key: z.string(),
    version: z.string(),
    locale: z.string(),
    content_hash: z.string(),
    purpose: z.string(),
    action_type: z.enum(['acceptance', 'acknowledgement', 'consent']),
    acted_at: z.string().datetime({ offset: true }),
  })
  .strict()

const requirementSetSchema = z
  .object({
    version: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
    locale: z.enum(['pt-BR', 'en-US']),
    document_keys: z
      .array(
        z
          .string()
          .regex(/^[a-z][a-z0-9_]{0,99}$/)
          .refine((key) => !key.startsWith('dev_')),
      )
      .min(1)
      .max(16)
      .refine((keys) => new Set(keys).size === keys.length),
    effective_at: z.string().datetime({ offset: true }),
    published_at: z.string().datetime({ offset: true }),
  })
  .strict()

const completionSchema = z
  .object({
    user_id: z.string().uuid(),
    onboarding_completed: z.literal(true),
    completed_at: z.string().datetime({ offset: true }),
    objective: z.enum(['recomposicao', 'ganho_massa', 'manutencao']),
    persona: z.enum(['focus', 'impulse', 'zen']),
    document_actions: z.array(
      z
        .object({
          document_key: z.string(),
          version: z.string(),
          locale: z.string(),
          content_hash: z.string(),
          purpose: z.string(),
          action: z.enum(['acceptance', 'acknowledgement', 'consent']),
          acted_at: z.string().datetime({ offset: true }),
        })
        .strict(),
    ),
  })
  .strict()

const profileSchema = z
  .object({
    onboarding_completed: z.boolean(),
    onboarding_completed_at: z.string().datetime({ offset: true }).nullable(),
    sex: z.enum(['masculino', 'feminino']).nullable().optional(),
    birth_date: z.string().date().nullable().optional(),
    height_cm: z.number().nullable().optional(),
    weight_kg: z.number().nullable().optional(),
    body_fat_percent: z.number().nullable().optional(),
    current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable().optional(),
    activity_level: z
      .enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
      .nullable()
      .optional(),
    training_frequency: z.number().int().nullable().optional(),
    water_intake: z.enum(['pouco', 'moderado', 'bastante']).nullable().optional(),
    hunger_level: z.enum(['pouca', 'moderada', 'muita']).nullable().optional(),
    wake_time: z
      .string()
      .regex(/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/)
      .nullable()
      .optional(),
    bedtime: z
      .string()
      .regex(/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/)
      .nullable()
      .optional(),
    food_organization: z.enum(['sim', 'nao']).nullable().optional(),
  })
  .strict()

const reconsentUserSchema = z
  .object({
    name: z.string().trim().min(1).max(100),
    locale: z.enum(['pt-BR', 'en-US']),
    country: z.string().regex(/^[A-Z]{2}$/),
    timezone: z.string().min(1).max(128),
    country_confirmed: z.literal(true),
  })
  .strict()

const reconsentPreferenceSchema = z
  .object({ personality_code: z.enum(['focus', 'impulse', 'zen']) })
  .strict()

interface QueryResult {
  data: unknown
  error: { code?: string; message?: string } | null
}

interface UntypedQuery extends PromiseLike<QueryResult> {
  select(columns: string): UntypedQuery
  eq(column: string, value: unknown): UntypedQuery
  in(column: string, values: unknown[]): UntypedQuery
  lte(column: string, value: unknown): UntypedQuery
  order(column: string, options: { ascending: boolean }): UntypedQuery
  limit(count: number): UntypedQuery
  maybeSingle(): Promise<QueryResult>
}

interface UntypedClient {
  from(table: string): UntypedQuery
  rpc(functionName: string, params: Record<string, unknown>): Promise<QueryResult>
}

export interface SupabaseOnboardingOptions {
  allowedLegalOrigins?: string[]
  fetchLegalContent?: (input: string, init: RequestInit) => Promise<Response>
  legalContentTimeoutMs?: number
  now?: () => Date
}

const MAX_CURRENT_DOCUMENTS = 16
const MAX_DOCUMENT_BODY_BYTES = 12_000
const MAX_SERIALIZED_DOCUMENT_BYTES = 48_000
const DEFAULT_LEGAL_CONTENT_TIMEOUT_MS = 5_000

function configuredOrigins(): string[] {
  return (process.env.MOBILE_ONBOARDING_LEGAL_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => {
      try {
        const url = new URL(value)
        return url.protocol === 'https:' && url.origin === value && !url.username && !url.password
      } catch {
        return false
      }
    })
}

function actionRecord(value: z.infer<typeof acceptedActionSchema>): OnboardingAcceptedActionRecord {
  return {
    documentKey: value.document_key,
    version: value.version,
    locale: value.locale,
    contentHash: value.content_hash,
    purpose: value.purpose,
    action: value.action_type,
    actedAt: value.acted_at,
  }
}

function sameDocumentIdentity(
  document: OnboardingDocumentRecord,
  action: OnboardingAcceptedActionRecord,
) {
  return (
    document.documentKey === action.documentKey &&
    document.version === action.version &&
    document.locale === action.locale &&
    document.contentHash === action.contentHash &&
    document.purpose === action.purpose &&
    document.action === action.action
  )
}

function documentRecord(value: z.infer<typeof documentSchema>): OnboardingDocumentRecord {
  return {
    documentKey: value.document_key,
    version: value.version,
    locale: value.locale,
    body: value.body,
    contentUrl: value.content_url,
    contentHash: value.content_hash,
    purpose: value.purpose,
    action: value.action_type,
    required: value.required,
    effectiveAt: value.effective_at,
  }
}

async function verifiedDocumentRecord(
  value: z.infer<typeof documentSchema>,
  allowedOrigins: Set<string>,
  fetchLegalContent: (input: string, init: RequestInit) => Promise<Response>,
  timeoutMs: number,
): Promise<OnboardingDocumentRecord> {
  if (value.document_key.startsWith('dev_')) {
    throw new OnboardingRepositoryError('documents_unavailable')
  }
  if (!value.content_url) return documentRecord(value)

  const url = new URL(value.content_url)
  if (!allowedOrigins.has(url.origin)) {
    throw new OnboardingRepositoryError('documents_unavailable')
  }

  const abortController = new AbortController()
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined
  const timeout = new Promise<never>((_, reject) => {
    timeoutHandle = setTimeout(() => {
      abortController.abort()
      reject(new OnboardingRepositoryError('documents_unavailable'))
    }, timeoutMs)
  })

  try {
    const response = await Promise.race([
      fetchLegalContent(value.content_url, {
        headers: { Accept: 'text/plain, text/markdown' },
        redirect: 'error',
        signal: abortController.signal,
      }),
      timeout,
    ])
    const contentType = response.headers.get('content-type') ?? ''
    const declaredLength = Number(response.headers.get('content-length') ?? '0')
    if (
      !response.ok ||
      !/^text\/(?:plain|markdown)(?:\s*;|$)/i.test(contentType) ||
      (Number.isFinite(declaredLength) && declaredLength > MAX_DOCUMENT_BODY_BYTES)
    ) {
      throw new OnboardingRepositoryError('documents_unavailable')
    }

    const bytes = await Promise.race([readLimitedBody(response, abortController.signal), timeout])
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_DOCUMENT_BODY_BYTES) {
      throw new OnboardingRepositoryError('documents_unavailable')
    }
    const body = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
    const hash = createHash('sha256').update(bytes).digest('hex')
    if (body.trim().length === 0 || hash !== value.content_hash) {
      throw new OnboardingRepositoryError('documents_unavailable')
    }
    return { ...documentRecord(value), body }
  } catch (error) {
    if (error instanceof OnboardingRepositoryError) throw error
    throw new OnboardingRepositoryError('documents_unavailable')
  } finally {
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle)
    abortController.abort()
  }
}

async function readLimitedBody(response: Response, signal: AbortSignal): Promise<Uint8Array> {
  const reader = response.body?.getReader()
  if (!reader) return new Uint8Array()

  const chunks: Uint8Array[] = []
  let byteLength = 0
  const cancel = () => {
    void reader.cancel()
  }
  signal.addEventListener('abort', cancel, { once: true })

  try {
    while (true) {
      if (signal.aborted) throw new OnboardingRepositoryError('documents_unavailable')
      const { done, value } = await reader.read()
      if (done) break
      byteLength += value.byteLength
      if (byteLength > MAX_DOCUMENT_BODY_BYTES) {
        await reader.cancel()
        throw new OnboardingRepositoryError('documents_unavailable')
      }
      chunks.push(value)
    }
  } finally {
    signal.removeEventListener('abort', cancel)
    reader.releaseLock()
  }

  const bytes = new Uint8Array(byteLength)
  let offset = 0
  for (const chunk of chunks) {
    bytes.set(chunk, offset)
    offset += chunk.byteLength
  }
  return bytes
}

function completionError(error: QueryResult['error']): never {
  const message = error?.message ?? ''
  if (
    message.includes('onboarding_document_version_mismatch') ||
    message.includes('onboarding_required_action_missing')
  ) {
    throw new OnboardingRepositoryError('requirements_changed')
  }
  if (message.includes('onboarding_documents_unavailable')) {
    throw new OnboardingRepositoryError('documents_unavailable')
  }
  if (message.includes('onboarding_already_completed')) {
    throw new OnboardingRepositoryError('already_completed')
  }
  if (
    message.includes('invalid_onboarding_submission') ||
    message.includes('invalid_onboarding_document_actions') ||
    message.includes('invalid_onboarding_persona')
  ) {
    throw new OnboardingRepositoryError('invalid_submission')
  }
  if (message.includes('onboarding_user_not_found')) {
    throw new OnboardingRepositoryError('user_not_found')
  }
  throw new OnboardingRepositoryError('internal')
}

function parseCompletion(data: unknown, expectedUserId: string) {
  const parsed = completionSchema.safeParse(data)
  if (!parsed.success || parsed.data.user_id !== expectedUserId) {
    throw new OnboardingRepositoryError('internal')
  }
  return {
    userId: parsed.data.user_id,
    completed: parsed.data.onboarding_completed,
    completedAt: parsed.data.completed_at,
    objective: parsed.data.objective,
    persona: parsed.data.persona,
    documentActions: parsed.data.document_actions.map((action) => ({
      documentKey: action.document_key,
      version: action.version,
      locale: action.locale,
      contentHash: action.content_hash,
      purpose: action.purpose,
      action: action.action,
      actedAt: action.acted_at,
    })),
  }
}

export function createSupabaseOnboardingRepository(
  supabase: ServiceClient,
  options: SupabaseOnboardingOptions = {},
): OnboardingRepository {
  const client = supabase as unknown as UntypedClient
  const allowedOrigins = new Set(options.allowedLegalOrigins ?? configuredOrigins())
  const fetchLegalContent = options.fetchLegalContent ?? fetch
  const legalContentTimeoutMs =
    options.legalContentTimeoutMs !== undefined &&
    Number.isFinite(options.legalContentTimeoutMs) &&
    options.legalContentTimeoutMs > 0
      ? options.legalContentTimeoutMs
      : DEFAULT_LEGAL_CONTENT_TIMEOUT_MS
  const now = options.now ?? (() => new Date())

  return {
    async load(userId, locale) {
      const nowIso = now().toISOString()
      const [profileResult, requirementResult, documentResult] = await Promise.all([
        client
          .from('user_profiles')
          .select(
            'onboarding_completed, onboarding_completed_at, sex, birth_date, height_cm, weight_kg, body_fat_percent, current_protocol, activity_level, training_frequency, water_intake, hunger_level, wake_time, bedtime, food_organization',
          )
          .eq('user_id', userId)
          .maybeSingle(),
        client
          .from('onboarding_legal_requirement_sets')
          .select('version, locale, document_keys, effective_at, published_at')
          .eq('locale', locale)
          .eq('publication_status', 'published')
          .lte('effective_at', nowIso)
          .lte('published_at', nowIso)
          .order('effective_at', { ascending: false })
          .order('published_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
        client
          .from('onboarding_legal_documents')
          .select(
            'id, document_key, version, locale, body, content_url, content_hash, purpose, action_type, required, effective_at, published_at',
          )
          .eq('locale', locale)
          .eq('publication_status', 'published')
          .lte('effective_at', nowIso)
          .lte('published_at', nowIso)
          .order('document_key', { ascending: true })
          .order('effective_at', { ascending: false })
          .order('published_at', { ascending: false }),
      ])

      if (profileResult.error || requirementResult.error || documentResult.error) {
        throw new OnboardingRepositoryError('internal')
      }
      const profile = profileSchema.safeParse(profileResult.data)
      const parsedDocuments = z.array(documentSchema).safeParse(documentResult.data ?? [])
      const requirementSet = requirementSetSchema.safeParse(requirementResult.data)
      if (!profile.success || !requirementSet.success || !parsedDocuments.success) {
        if (profile.success && !requirementSet.success) {
          throw new OnboardingRepositoryError('documents_unavailable')
        }
        throw new OnboardingRepositoryError('internal')
      }

      const requiredKeys = new Set(requirementSet.data.document_keys)
      const currentDocuments = parsedDocuments.data.filter(
        (document, index, documents) =>
          requiredKeys.has(document.document_key) &&
          documents.findIndex((candidate) => candidate.document_key === document.document_key) ===
            index,
      )
      if (
        currentDocuments.length !== requiredKeys.size ||
        currentDocuments.length > MAX_CURRENT_DOCUMENTS ||
        currentDocuments.some((document) => !document.required)
      ) {
        throw new OnboardingRepositoryError('documents_unavailable')
      }
      const verifiedDocuments = await Promise.all(
        currentDocuments.map((document) =>
          verifiedDocumentRecord(
            document,
            allowedOrigins,
            fetchLegalContent,
            legalContentTimeoutMs,
          ),
        ),
      )
      if (
        new TextEncoder().encode(JSON.stringify(verifiedDocuments)).byteLength >
        MAX_SERIALIZED_DOCUMENT_BYTES
      ) {
        throw new OnboardingRepositoryError('documents_unavailable')
      }

      const actionResult = await client
        .from('user_onboarding_legal_actions')
        .select('document_key, version, locale, content_hash, purpose, action_type, acted_at')
        .eq('user_id', userId)
        .in(
          'legal_document_id',
          currentDocuments.map((document) => document.id),
        )
        .eq('locale', locale)
        .order('acted_at', { ascending: false })
        .limit(MAX_CURRENT_DOCUMENTS)
      if (actionResult.error) throw new OnboardingRepositoryError('internal')
      const parsedActions = z.array(acceptedActionSchema).safeParse(actionResult.data ?? [])
      if (!parsedActions.success) throw new OnboardingRepositoryError('internal')
      const acceptedActions = parsedActions.data
        .map(actionRecord)
        .filter((action) =>
          verifiedDocuments.some((document) => sameDocumentIdentity(document, action)),
        )
      const hasCurrentRequiredActions = verifiedDocuments.every((document) =>
        acceptedActions.some((action) => sameDocumentIdentity(document, action)),
      )

      let draft: OnboardingDraftRecord | null = null
      if (profile.data.onboarding_completed_at !== null) {
        const [userResult, preferenceResult] = await Promise.all([
          client
            .from('users')
            .select('name, locale, country, timezone, country_confirmed')
            .eq('id', userId)
            .maybeSingle(),
          client
            .from('user_coach_preferences')
            .select('personality_code')
            .eq('user_id', userId)
            .maybeSingle(),
        ])
        const user = reconsentUserSchema.safeParse(userResult.data)
        const preference = reconsentPreferenceSchema.safeParse(preferenceResult.data)
        const completeProfile = profile.data
        if (
          userResult.error ||
          preferenceResult.error ||
          !user.success ||
          !preference.success ||
          completeProfile.sex == null ||
          completeProfile.birth_date == null ||
          completeProfile.height_cm == null ||
          completeProfile.weight_kg == null ||
          completeProfile.current_protocol == null ||
          completeProfile.activity_level == null ||
          completeProfile.training_frequency == null ||
          completeProfile.water_intake == null ||
          completeProfile.hunger_level == null ||
          completeProfile.wake_time == null ||
          completeProfile.bedtime == null ||
          completeProfile.food_organization == null
        ) {
          throw new OnboardingRepositoryError('internal')
        }
        draft = {
          name: user.data.name,
          locale: user.data.locale,
          country: user.data.country,
          timezone: user.data.timezone,
          sex: completeProfile.sex,
          birthDate: completeProfile.birth_date,
          heightCm: completeProfile.height_cm,
          weightKg: completeProfile.weight_kg,
          bodyFatPercent: completeProfile.body_fat_percent ?? null,
          objective: completeProfile.current_protocol,
          activityLevel: completeProfile.activity_level,
          trainingFrequency: completeProfile.training_frequency,
          waterIntake: completeProfile.water_intake,
          hungerLevel: completeProfile.hunger_level,
          wakeTime: completeProfile.wake_time.slice(0, 5),
          bedtime: completeProfile.bedtime.slice(0, 5),
          foodOrganization: completeProfile.food_organization,
          persona: preference.data.personality_code,
        }
      }

      return {
        locale: locale as OnboardingCompletionInput['locale'],
        completed:
          profile.data.onboarding_completed &&
          profile.data.onboarding_completed_at !== null &&
          hasCurrentRequiredActions,
        completedAt: profile.data.onboarding_completed_at,
        documents: verifiedDocuments,
        acceptedActions,
        draft,
      }
    },

    async complete(userId: string, input: OnboardingCompletionInput) {
      const { data, error } = await client.rpc('complete_mobile_onboarding_atomic', {
        p_user_id: userId,
        p_submission: input,
      })
      if (error) completionError(error)
      return parseCompletion(data, userId)
    },
  }
}
