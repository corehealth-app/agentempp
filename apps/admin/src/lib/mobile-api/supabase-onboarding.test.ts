import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { OnboardingCompletionInput } from './contracts'
import { hashMobileRequest } from './idempotency'
import { OnboardingRepositoryError } from './onboarding-service'
import type { PreparedSignupPhotoConfirmation } from './signup-body-photo-confirmation'
import { createSupabaseOnboardingRepository } from './supabase-onboarding'

const USER_ID = '00000000-0000-4000-8000-000000000951'

function queryResult(data: unknown, error: unknown = null) {
  const query = Object.assign(Promise.resolve({ data, error }), {
    select: vi.fn(),
    eq: vi.fn(),
    in: vi.fn(),
    lte: vi.fn(),
    order: vi.fn(),
    limit: vi.fn(),
    maybeSingle: vi.fn(),
  })
  query.select.mockReturnValue(query)
  query.eq.mockReturnValue(query)
  query.in.mockReturnValue(query)
  query.lte.mockReturnValue(query)
  query.order.mockReturnValue(query)
  query.limit.mockReturnValue(query)
  query.maybeSingle.mockResolvedValue({ data, error })
  return query
}

function completionInput(): OnboardingCompletionInput {
  return {
    name: 'Synthetic User',
    locale: 'pt-BR',
    country: 'BR',
    timezone: 'America/Sao_Paulo',
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    objective: 'recomposicao',
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms_of_service',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  }
}

function embeddedDocument(index: number, body = 'Synthetic terms for tests only') {
  return {
    document_key: `synthetic_document_${index}`,
    version: '2026-09-15.1',
    locale: 'pt-BR',
    body,
    content_url: null,
    content_hash: createHash('sha256').update(body).digest('hex'),
    purpose: `synthetic_document_${index}_test`,
    action_type: 'acceptance',
    required: true,
    effective_at: '2026-09-15T00:00:00.000Z',
    published_at: '2026-09-15T00:00:00.000Z',
    id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
  }
}

function requirementSet(documentKeys: string[]) {
  return {
    version: '2026-09-15.1',
    locale: 'pt-BR',
    document_keys: documentKeys,
    effective_at: '2026-09-15T00:00:00.000Z',
    published_at: '2026-09-15T00:00:00.000Z',
  }
}

afterEach(() => vi.unstubAllEnvs())

describe('Supabase onboarding adapter', () => {
  it.each([
    ['40001', 'onboarding_generation_changed', 409],
    ['22023', 'body_photo_confirmation_stale', 409],
    ['22023', 'body_photo_confirmation_unavailable', 409],
    ['22023', 'body_photo_confirmation_value_mismatch', 422],
    ['22023', 'body_photo_consent_required', 403],
    ['22023', 'body_photo_age_not_allowed', 403],
    ['22023', 'body_photo_consent_locale_changed', 409],
    ['22023', 'body_photos_unavailable', 404],
  ] as const)('maps checked SQL %s/%s to the recoverable HTTP status %s', async (code, message, status) => {
    const original = completionInput()
    const prepared: PreparedSignupPhotoConfirmation = {
      original,
      effectiveSubmission: original,
      mode: 'manual',
      snapshot: {
        version: 1,
        user_id: USER_ID,
        profile_present: true,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        generation_token: {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: 1,
        },
        poses: [],
        remaining_uploads: 0,
        consent: null,
        estimate: null,
        candidate: null,
        confirmation: null,
      },
    }
    const rpc = vi.fn(async () => ({ data: null, error: { code, message } }))
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupPhotoConfirmation: prepared,
    })
    await expect(repository.complete(USER_ID, original)).rejects.toMatchObject({
      status,
      code: message,
    })
  })

  it.each([
    'absent',
    'accept',
  ] as const)('uses the server generation in the checked RPC with ORIGINAL submission (%s)', async (mode) => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    const original = completionInput()
    original.height_cm = 173.555
    original.weight_kg = 80.005
    if (mode === 'accept')
      original.body_photo_confirmation = {
        decision: 'accept',
        source_ids: {
          front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        },
        fingerprint: 'a'.repeat(64),
      }
    const { body_photo_confirmation: confirmation, ...official } = original
    const prepared: PreparedSignupPhotoConfirmation = {
      original,
      effectiveSubmission: mode === 'accept' ? { ...official, body_fat_percent: 24 } : official,
      mode: mode === 'accept' ? 'fresh_accept' : 'manual',
      snapshot: {
        version: 1,
        user_id: USER_ID,
        profile_present: true,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        generation_token: {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: 0,
        },
        poses: [],
        remaining_uploads: 0,
        consent: null,
        estimate: null,
        candidate: null,
        confirmation: null,
      },
    }
    const rpc = vi.fn(async () => ({
      data: {
        user_id: USER_ID,
        onboarding_completed: true,
        completed_at: '2026-10-12T01:00:00.000Z',
        objective: 'recomposicao',
        persona: 'focus',
        document_actions: [],
      },
      error: null,
    }))
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupPhotoConfirmation: prepared,
    })
    await expect(repository.complete(USER_ID, original)).resolves.toMatchObject({
      userId: USER_ID,
      completed: true,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_with_cleanup_scope', {
      p_user_id: USER_ID,
      p_submission: official,
      p_confirmation: confirmation ?? null,
      p_expected_completed: false,
      p_expected_completed_at: null,
      p_expected_receipt_count: 0,
    })
    expect(original).not.toHaveProperty('body_fat_percent')
    expect(original.height_cm).toBe(173.555)
    expect(original.weight_kg).toBe(80.005)
  })

  it('loads only the authenticated user and current locale documents', async () => {
    const profile = queryResult({
      onboarding_completed: false,
      onboarding_completed_at: null,
    })
    const actions = queryResult([])
    const requirements = queryResult(requirementSet(['terms_of_service']))
    const documents = queryResult([
      {
        document_key: 'terms_of_service',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        body: 'Synthetic terms for tests only',
        content_url: null,
        content_hash: 'a'.repeat(64),
        purpose: 'synthetic_terms_test',
        action_type: 'acceptance',
        required: true,
        effective_at: '2026-09-15T00:00:00.000Z',
        published_at: '2026-09-15T00:00:00.000Z',
        id: '00000000-0000-4000-8000-000000000953',
      },
    ])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      if (table === 'onboarding_legal_documents') return documents
      throw new Error(`unexpected table ${table}`)
    })
    const client = { from, rpc: vi.fn() } as unknown as ServiceClient

    const result = await createSupabaseOnboardingRepository(client, {
      now: () => new Date('2026-09-15T15:00:00.000Z'),
      allowedLegalOrigins: [],
    }).load(USER_ID, 'pt-BR')

    expect(profile.eq).toHaveBeenCalledWith('user_id', USER_ID)
    expect(actions.eq).toHaveBeenCalledWith('user_id', USER_ID)
    expect(actions.eq).toHaveBeenCalledWith('locale', 'pt-BR')
    expect(actions.in).toHaveBeenCalledWith('legal_document_id', [
      '00000000-0000-4000-8000-000000000953',
    ])
    expect(actions.order).toHaveBeenCalledWith('acted_at', { ascending: false })
    expect(actions.limit).toHaveBeenCalledWith(16)
    expect(documents.eq).toHaveBeenCalledWith('locale', 'pt-BR')
    expect(documents.eq).toHaveBeenCalledWith('publication_status', 'published')
    expect(documents.lte).toHaveBeenCalledWith('effective_at', '2026-09-15T15:00:00.000Z')
    expect(requirements.eq).toHaveBeenCalledWith('locale', 'pt-BR')
    expect(requirements.eq).toHaveBeenCalledWith('publication_status', 'published')
    expect(requirements.lte).toHaveBeenCalledWith('effective_at', '2026-09-15T15:00:00.000Z')
    expect(result.documents).toHaveLength(1)
  })

  it('fails closed when a URL document origin is not explicitly allowed', async () => {
    const profile = queryResult({ onboarding_completed: false, onboarding_completed_at: null })
    const actions = queryResult([])
    const requirements = queryResult(requirementSet(['privacy_policy']))
    const documents = queryResult([
      {
        document_key: 'privacy_policy',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        body: null,
        content_url: 'https://untrusted.example.invalid/privacy',
        content_hash: 'b'.repeat(64),
        purpose: 'synthetic_privacy_test',
        action_type: 'acknowledgement',
        required: true,
        effective_at: '2026-09-15T00:00:00.000Z',
        published_at: '2026-09-15T00:00:00.000Z',
        id: '00000000-0000-4000-8000-000000000954',
      },
    ])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      return documents
    })

    await expect(
      createSupabaseOnboardingRepository({ from, rpc: vi.fn() } as unknown as ServiceClient, {
        allowedLegalOrigins: ['https://legal.example.invalid'],
      }).load(USER_ID, 'pt-BR'),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
  })

  it('presents only fetched URL content whose bytes match the published hash', async () => {
    const body = 'Synthetic privacy text fetched for tests only'
    const profile = queryResult({ onboarding_completed: false, onboarding_completed_at: null })
    const actions = queryResult([])
    const requirements = queryResult(requirementSet(['privacy_policy']))
    const documents = queryResult([
      {
        document_key: 'privacy_policy',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        body: null,
        content_url: 'https://legal.example.invalid/privacy',
        content_hash: createHash('sha256').update(body).digest('hex'),
        purpose: 'synthetic_privacy_test',
        action_type: 'acknowledgement',
        required: true,
        effective_at: '2026-09-15T00:00:00.000Z',
        published_at: '2026-09-15T00:00:00.000Z',
        id: '00000000-0000-4000-8000-000000000954',
      },
    ])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      return documents
    })
    const fetchLegalContent = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(body, {
          status: 200,
          headers: { 'content-type': 'text/plain; charset=utf-8' },
        }),
      )
      .mockResolvedValueOnce(
        new Response(`${body} changed`, {
          status: 200,
          headers: { 'content-type': 'text/plain; charset=utf-8' },
        }),
      )
    const repository = createSupabaseOnboardingRepository(
      { from, rpc: vi.fn() } as unknown as ServiceClient,
      {
        allowedLegalOrigins: ['https://legal.example.invalid'],
        fetchLegalContent,
      },
    )

    await expect(repository.load(USER_ID, 'pt-BR')).resolves.toMatchObject({
      documents: [{ body, contentUrl: 'https://legal.example.invalid/privacy' }],
    })
    expect(fetchLegalContent).toHaveBeenCalledWith(
      'https://legal.example.invalid/privacy',
      expect.objectContaining({
        headers: { Accept: 'text/plain, text/markdown' },
        redirect: 'error',
        signal: expect.any(AbortSignal),
      }),
    )
    await expect(repository.load(USER_ID, 'pt-BR')).rejects.toEqual(
      new OnboardingRepositoryError('documents_unavailable'),
    )
  })

  it('bounds remote legal content by time and incrementally-read bytes', async () => {
    const profile = queryResult({ onboarding_completed: false, onboarding_completed_at: null })
    const actions = queryResult([])
    const requirements = queryResult(requirementSet(['privacy_policy']))
    const documents = queryResult([
      {
        document_key: 'privacy_policy',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        body: null,
        content_url: 'https://legal.example.invalid/privacy',
        content_hash: 'b'.repeat(64),
        purpose: 'synthetic_privacy_test',
        action_type: 'acknowledgement',
        required: true,
        effective_at: '2026-09-15T00:00:00.000Z',
        published_at: '2026-09-15T00:00:00.000Z',
        id: '00000000-0000-4000-8000-000000000954',
      },
    ])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      return documents
    })
    let cancelled = false
    const oversizedStream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(8_000))
        controller.enqueue(new Uint8Array(8_000))
      },
      cancel() {
        cancelled = true
      },
    })
    const oversizedFetch = vi.fn().mockResolvedValue(
      new Response(oversizedStream, {
        status: 200,
        headers: { 'content-type': 'text/plain' },
      }),
    )
    const neverResolvingFetch = vi.fn(
      (_input: string, init: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init.signal?.addEventListener('abort', () => reject(new Error('aborted')), {
            once: true,
          })
        }),
    )

    await expect(
      createSupabaseOnboardingRepository({ from, rpc: vi.fn() } as unknown as ServiceClient, {
        allowedLegalOrigins: ['https://legal.example.invalid'],
        fetchLegalContent: oversizedFetch,
      }).load(USER_ID, 'pt-BR'),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
    expect(cancelled).toBe(true)

    await expect(
      createSupabaseOnboardingRepository({ from, rpc: vi.fn() } as unknown as ServiceClient, {
        allowedLegalOrigins: ['https://legal.example.invalid'],
        fetchLegalContent: neverResolvingFetch,
        legalContentTimeoutMs: 5,
      }).load(USER_ID, 'pt-BR'),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
  })

  it('fails closed when current requirements exceed the submit or response limits', async () => {
    const profile = queryResult({ onboarding_completed: false, onboarding_completed_at: null })
    const actions = queryResult([])
    const tooManyRequirements = queryResult(
      requirementSet(Array.from({ length: 17 }, (_, index) => `synthetic_document_${index + 1}`)),
    )
    const oversizedRequirements = queryResult(
      requirementSet(Array.from({ length: 5 }, (_, index) => `synthetic_document_${index + 101}`)),
    )
    const tooManyDocuments = queryResult(
      Array.from({ length: 17 }, (_, index) => embeddedDocument(index + 1)),
    )
    const oversizedDocuments = queryResult(
      Array.from({ length: 5 }, (_, index) => embeddedDocument(index + 101, 'x'.repeat(10_000))),
    )
    const fromTooMany = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return tooManyRequirements
      return tooManyDocuments
    })
    const fromOversized = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return oversizedRequirements
      return oversizedDocuments
    })

    await expect(
      createSupabaseOnboardingRepository({
        from: fromTooMany,
        rpc: vi.fn(),
      } as unknown as ServiceClient).load(USER_ID, 'pt-BR'),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
    await expect(
      createSupabaseOnboardingRepository({
        from: fromOversized,
        rpc: vi.fn(),
      } as unknown as ServiceClient).load(USER_ID, 'pt-BR'),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
  })

  it('fails closed when the authoritative requirement set is only partially published', async () => {
    const profile = queryResult({ onboarding_completed: false, onboarding_completed_at: null })
    const actions = queryResult([])
    const requirements = queryResult(requirementSet(['terms_of_service', 'privacy_policy']))
    const documents = queryResult([{ ...embeddedDocument(301), document_key: 'terms_of_service' }])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      return documents
    })

    await expect(
      createSupabaseOnboardingRepository({ from, rpc: vi.fn() } as unknown as ServiceClient).load(
        USER_ID,
        'pt-BR',
      ),
    ).rejects.toEqual(new OnboardingRepositoryError('documents_unavailable'))
  })

  it.each([
    'moderado',
    null,
  ] as const)('loads reconsent without inventing habitual water (%s)', async (waterIntake) => {
    const profile = queryResult({
      onboarding_completed: true,
      onboarding_completed_at: '2026-09-15T15:00:00.000Z',
      sex: 'masculino',
      birth_date: '1990-01-01',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: null,
      current_protocol: 'recomposicao',
      activity_level: 'moderado',
      training_frequency: 4,
      water_intake: waterIntake,
      hunger_level: 'moderada',
      wake_time: '07:00:00',
      bedtime: '23:00:00',
      food_organization: 'sim',
    })
    const user = queryResult({
      name: 'Synthetic User',
      locale: 'pt-BR',
      country: 'BR',
      timezone: 'America/Sao_Paulo',
      country_confirmed: true,
    })
    const preference = queryResult({ personality_code: 'focus' })
    const actions = queryResult([
      {
        document_key: 'terms_of_service',
        version: 'older-version',
        locale: 'pt-BR',
        content_hash: 'b'.repeat(64),
        purpose: 'synthetic_old_terms_test',
        action_type: 'acceptance',
        acted_at: '2026-09-14T15:00:00.000Z',
      },
    ])
    const requirements = queryResult(requirementSet(['terms_of_service']))
    const documents = queryResult([{ ...embeddedDocument(302), document_key: 'terms_of_service' }])
    const from = vi.fn((table: string) => {
      if (table === 'user_profiles') return profile
      if (table === 'users') return user
      if (table === 'user_coach_preferences') return preference
      if (table === 'user_onboarding_legal_actions') return actions
      if (table === 'onboarding_legal_requirement_sets') return requirements
      return documents
    })

    await expect(
      createSupabaseOnboardingRepository({ from, rpc: vi.fn() } as unknown as ServiceClient).load(
        USER_ID,
        'pt-BR',
      ),
    ).resolves.toMatchObject({
      completed: false,
      acceptedActions: [],
      draft: {
        name: 'Synthetic User',
        objective: 'recomposicao',
        persona: 'focus',
        waterIntake,
      },
    })
  })

  it('calls only the atomic RPC with the server-derived user and maps stale documents', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({
        data: {
          user_id: USER_ID,
          onboarding_completed: true,
          completed_at: '2026-09-15T15:00:00.000Z',
          objective: 'recomposicao',
          persona: 'focus',
          document_actions: [],
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: null,
        error: { code: '23514', message: 'onboarding_document_version_mismatch private detail' },
      })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient)

    await expect(repository.complete(USER_ID, completionInput())).resolves.toMatchObject({
      completed: true,
      userId: USER_ID,
    })
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_atomic', {
      p_user_id: USER_ID,
      p_submission: completionInput(),
    })
    await expect(repository.complete(USER_ID, completionInput())).rejects.toEqual(
      new OnboardingRepositoryError('requirements_changed'),
    )
  })

  it('maps a different post-completion submission without exposing database details', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: '23514', message: 'onboarding_already_completed private detail' },
    })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient)

    await expect(repository.complete(USER_ID, completionInput())).rejects.toEqual(
      new OnboardingRepositoryError('already_completed'),
    )
  })
})

describe('C59a signup authority cannot fall back to legacy completion', () => {
  it('C59c A1 valid authority calls only keyed11 atomic and returns the official completion', async () => {
    const from = vi.fn()
    const fetchLegalContent = vi.fn()
    const verifyReplay = vi.fn(async () => {})
    const rpc = vi.fn().mockResolvedValue({
      data: {
        user_id: USER_ID,
        onboarding_completed: true,
        completed_at: '2026-09-15T15:00:00.000Z',
        objective: 'recomposicao',
        persona: 'focus',
        document_actions: [],
      },
      error: null,
    })
    const input = completionInput()
    const requestHash = hashMobileRequest(input)
    const authority = Object.freeze({
      userId: USER_ID,
      requestKey: 'c59c-keyed-atomic-red1',
      requestHash,
      epoch: '00000000-0000-4000-8000-000000000e01',
      admissionId: '00000000-0000-4000-8000-000000000e03',
      verifyReplay,
    })

    await expect(
      Promise.resolve().then(() =>
        createSupabaseOnboardingRepository({ rpc, from } as unknown as ServiceClient, {
          signupStrengthRequest: authority,
          fetchLegalContent,
        }).complete(USER_ID, input),
      ),
    ).resolves.toEqual({
      userId: USER_ID,
      completed: true,
      completedAt: '2026-09-15T15:00:00.000Z',
      objective: 'recomposicao',
      persona: 'focus',
      documentActions: [],
    })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_keyed', {
      p_user_id: USER_ID,
      p_submission: input,
      p_completion_path: 'atomic',
      p_request_key: 'c59c-keyed-atomic-red1',
      p_request_hash: requestHash,
      p_expected_epoch: '00000000-0000-4000-8000-000000000e01',
      p_admission_id: '00000000-0000-4000-8000-000000000e03',
      p_confirmation: null,
      p_expected_completed: null,
      p_expected_completed_at: null,
      p_expected_receipt_count: null,
    })
    expect(from).not.toHaveBeenCalled()
    expect(fetchLegalContent).not.toHaveBeenCalled()
    expect(verifyReplay).not.toHaveBeenCalled()
  })

  it('C59a H6 a keyed failure never falls back to legacy completion', async () => {
    const from = vi.fn()
    const fetchLegalContent = vi.fn()
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: 'XX001', message: 'private database detail' },
    })
    const input = completionInput()
    const options = {
      now: () => new Date('2026-10-19T12:00:00Z'),
      fetchLegalContent,
      signupStrengthRequest: {
        userId: USER_ID,
        requestKey: 'c59a-no-fallback-1',
        requestHash: hashMobileRequest(input),
        epoch: '00000000-0000-4000-8000-000000000e01',
        admissionId: '00000000-0000-4000-8000-000000000e03',
        verifyReplay: vi.fn(async () => {}),
      },
    }
    await expect(
      Promise.resolve().then(() =>
        createSupabaseOnboardingRepository(
          { rpc, from } as unknown as ServiceClient,
          options,
        ).complete(USER_ID, input),
      ),
    ).rejects.toEqual(new OnboardingRepositoryError('internal'))
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_keyed', expect.any(Object))
    expect(from).not.toHaveBeenCalled()
    expect(fetchLegalContent).not.toHaveBeenCalled()
  })
})

describe('C59c keyed signup completion adapter', () => {
  function handle() {
    return {
      userId: USER_ID,
      requestKey: 'c59c-original-key',
      requestHash: 'f'.repeat(64),
      epoch: '00000000-0000-4000-8000-000000000e01',
      admissionId: '00000000-0000-4000-8000-000000000e03',
      verifyReplay: vi.fn(async () => {}),
    }
  }
  function wire() {
    return {
      user_id: USER_ID,
      onboarding_completed: true,
      completed_at: '2026-10-20T10:00:00.123456Z',
      objective: 'recomposicao',
      persona: 'focus',
      document_actions: [],
    }
  }
  function photo(input: OnboardingCompletionInput): PreparedSignupPhotoConfirmation {
    return {
      original: input,
      effectiveSubmission: { ...input, body_fat_percent: 24 },
      mode: 'manual',
      snapshot: {
        version: 1,
        user_id: USER_ID,
        profile_present: true,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        generation_token: {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: 0,
        },
        poses: [],
        remaining_uploads: 0,
        consent: null,
        estimate: null,
        candidate: null,
        confirmation: null,
      },
    }
  }

  it.each([
    ['https://not-staging.example.invalid', 'body_photo_confirmation'],
    ['https://xitugspwfxkcluxvrdeg.supabase.co', 'cleanup_scope'],
  ])('captures the ON backend selector and exact ORIGINAL/CAS values (%s)', async (url, path) => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', url)
    const input = completionInput()
    input.height_cm = 173.555
    input.weight_kg = 80.005
    input.body_photo_confirmation = { decision: 'decline' }
    const original = structuredClone(input)
    const prepared = photo(input)
    const authority = handle()
    const rpc = vi.fn().mockResolvedValue({ data: wire(), error: null })
    const client = { rpc }
    const options = { signupStrengthRequest: authority, signupPhotoConfirmation: prepared }
    const repository = createSupabaseOnboardingRepository(
      client as unknown as ServiceClient,
      options,
    )
    // These are retained aliases, including mutation during prepareEvaluationAccess.
    authority.requestKey = 'c59c-mutated-key'
    authority.epoch = '00000000-0000-4000-8000-000000000e99'
    authority.admissionId = '00000000-0000-4000-8000-000000000e98'
    authority.requestHash = 'e'.repeat(64)
    if (!prepared.snapshot) throw new Error('fixture snapshot missing')
    prepared.snapshot.generation_token.onboarding_completed = true
    prepared.snapshot.generation_token.onboarding_completed_at = '2026-10-20T11:00:00.123456Z'
    prepared.snapshot.generation_token.receipt_count = 88
    client.rpc = vi.fn()
    options.signupStrengthRequest = handle()
    vi.stubEnv(
      'NEXT_PUBLIC_SUPABASE_URL',
      url.includes('xitugspwfxkcluxvrdeg')
        ? 'https://not-staging.example.invalid'
        : 'https://xitugspwfxkcluxvrdeg.supabase.co',
    )
    await expect(repository.complete(USER_ID, input)).resolves.toMatchObject({
      userId: USER_ID,
      completed: true,
      completedAt: '2026-10-20T10:00:00.123456Z',
    })
    const { body_photo_confirmation, ...official } = original
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_keyed', {
      p_user_id: USER_ID,
      p_submission: official,
      p_completion_path: path,
      p_request_key: 'c59c-original-key',
      p_request_hash: 'f'.repeat(64),
      p_expected_epoch: '00000000-0000-4000-8000-000000000e01',
      p_admission_id: '00000000-0000-4000-8000-000000000e03',
      p_confirmation: body_photo_confirmation,
      p_expected_completed: false,
      p_expected_completed_at: null,
      p_expected_receipt_count: 0,
    })
    expect(client.rpc).not.toHaveBeenCalled()
    expect(input).toEqual(original)
    expect(authority.verifyReplay).not.toHaveBeenCalled()
  })

  it('captures the RPC receiver and copies the ORIGINAL structured payload before await', async () => {
    const input = completionInput()
    input.body_photo_confirmation = { decision: 'decline' }
    const original = structuredClone(input)
    let release!: (result: { data: unknown; error: null }) => void
    let parameters: Record<string, unknown> | undefined
    const client = {
      receiver: true,
      rpc: vi.fn(function (
        this: { receiver: boolean },
        _name: string,
        args: Record<string, unknown>,
      ) {
        expect(this.receiver).toBe(true)
        parameters = args
        return new Promise<{ data: unknown; error: null }>((resolve) => {
          release = resolve
        })
      }),
    }
    const repository = createSupabaseOnboardingRepository(client as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
    })
    const pending = repository.complete(USER_ID, input)
    input.document_actions[0].version = 'changed-after-start'
    input.training_frequency = 7
    if (input.body_photo_confirmation) input.body_photo_confirmation.decision = 'decline'
    expect(parameters?.p_submission).toEqual(original)
    expect(parameters?.p_submission).not.toBe(input)
    release({ data: wire(), error: null })
    await expect(pending).resolves.toMatchObject({ completed: true })
    expect(client.rpc).toHaveBeenCalledTimes(1)
  })

  it('refuses a different owner before any RPC', async () => {
    const rpc = vi.fn()
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
    })
    await expect(
      repository.complete('00000000-0000-4000-8000-000000000952', completionInput()),
    ).rejects.toEqual(new OnboardingRepositoryError('internal'))
    expect(rpc).not.toHaveBeenCalled()
  })

  it('preserves a completed CAS timestamp with all six fractional digits and a nonzero receipt count', async () => {
    const input = completionInput()
    const prepared = photo(input)
    if (!prepared.snapshot) throw new Error('fixture snapshot missing')
    prepared.snapshot.generation_token = {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-19T23:59:59.123456Z',
      receipt_count: 7,
    }
    const rpc = vi.fn().mockResolvedValue({ data: wire(), error: null })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
      signupPhotoConfirmation: prepared,
    })
    await repository.complete(USER_ID, input)
    expect(rpc).toHaveBeenCalledWith(
      'complete_mobile_onboarding_keyed',
      expect.objectContaining({
        p_expected_completed: true,
        p_expected_completed_at: '2026-10-19T23:59:59.123456Z',
        p_expected_receipt_count: 7,
      }),
    )
  })

  it('retries only the same captured keyed context after a transient transport failure', async () => {
    const rpc = vi
      .fn()
      .mockRejectedValueOnce(new Error('transport failure'))
      .mockResolvedValueOnce({ data: wire(), error: null })
    const request = handle()
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: request,
    })
    const input = completionInput()
    await expect(repository.complete(USER_ID, input)).rejects.toEqual(
      new OnboardingRepositoryError('internal'),
    )
    request.requestKey = 'new-intent-must-not-be-used'
    request.requestHash = 'a'.repeat(64)
    await expect(repository.complete(USER_ID, input)).resolves.toMatchObject({ completed: true })
    expect(rpc).toHaveBeenCalledTimes(2)
    expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0])
  })

  it.each([
    ['40001', 'mobile_signup_strength_stale_epoch', 409],
    ['40001', 'mobile_signup_strength_invalid_admission', 409],
    ['40001', 'mobile_signup_strength_existing_scope', 409],
    ['22023', 'mobile_signup_strength_stale_epoch', undefined],
    ['40001', 'mobile_signup_strength_stale_epoch private detail', undefined],
    ['40001', 'unknown_private_failure', undefined],
  ] as const)('maps only exact keyed authority failures %s/%s', async (code, message, status) => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code, message } })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
    })
    if (status) {
      await expect(repository.complete(USER_ID, completionInput())).rejects.toMatchObject({
        status,
        code: message,
      })
    } else {
      await expect(repository.complete(USER_ID, completionInput())).rejects.toEqual(
        new OnboardingRepositoryError('internal'),
      )
    }
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_keyed', expect.any(Object))
  })

  it.each(
    [
      null,
      [],
      { user_id: USER_ID },
      { ...wire(), user_id: '00000000-0000-4000-8000-000000000952' },
    ].map((data) => ({ data })),
  )('rejects malformed keyed success without legacy fallback ($data)', async ({ data }) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
    })
    await expect(repository.complete(USER_ID, completionInput())).rejects.toEqual(
      new OnboardingRepositoryError('internal'),
    )
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('does not retry or fall back when the keyed transport throws', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('synthetic transport failure'))
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupStrengthRequest: handle(),
    })
    await expect(repository.complete(USER_ID, completionInput())).rejects.toEqual(
      new OnboardingRepositoryError('internal'),
    )
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('keeps OFF selector timing and historical six arguments', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://not-staging.example.invalid')
    const input = completionInput()
    const rpc = vi.fn().mockResolvedValue({ data: wire(), error: null })
    const repository = createSupabaseOnboardingRepository({ rpc } as unknown as ServiceClient, {
      signupPhotoConfirmation: photo(input),
    })
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    await repository.complete(USER_ID, input)
    expect(rpc).toHaveBeenCalledWith('complete_mobile_onboarding_with_cleanup_scope', {
      p_user_id: USER_ID,
      p_submission: input,
      p_confirmation: null,
      p_expected_completed: false,
      p_expected_completed_at: null,
      p_expected_receipt_count: 0,
    })
  })
})
