import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { OnboardingCompletionInput } from './contracts'
import { OnboardingRepositoryError } from './onboarding-service'
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

describe('Supabase onboarding adapter', () => {
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

  it('does not trust a historical completion flag without current exact legal actions', async () => {
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
      water_intake: 'moderado',
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
