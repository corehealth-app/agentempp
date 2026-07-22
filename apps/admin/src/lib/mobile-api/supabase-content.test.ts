import { encodeContentCursor } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ContentRepositoryError } from './content-service'
import { createSupabaseContentDependencies } from './supabase-content'

const USER_ID = '00000000-0000-0000-0000-000000000411'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000412'
const PUBLISH_AT = '2026-07-21T12:00:00.000Z'
const CURSOR_PUBLICATION_ID = '00000000-0000-0000-0000-000000000413'

function feedItem(overrides: Record<string, unknown> = {}) {
  return {
    publicationId: PUBLICATION_ID,
    slug: 'hidratacao-no-dia',
    locale: 'pt-BR',
    title: 'Hidratacao ao longo do dia',
    excerpt: 'Organize pequenos momentos para manter a hidratacao durante a rotina.',
    category: 'hydration',
    tags: ['hidratacao', 'rotina'],
    readingTimeMinutes: 2,
    publishAt: PUBLISH_AT,
    featuredToday: true,
    version: 4,
    saved: false,
    completed: false,
    cover: {
      bucketId: 'content-covers',
      objectPath: 'content/private-hydration.webp',
    },
    ...overrides,
  }
}

function state(overrides: Record<string, unknown> = {}) {
  return {
    publicationId: PUBLICATION_ID,
    version: 4,
    saved: false,
    completed: true,
    changed: true,
    replayed: false,
    ...overrides,
  }
}

function serviceClient(rpc: ReturnType<typeof vi.fn>, storageFrom = vi.fn()) {
  return {
    rpc,
    storage: { from: storageFrom },
  } as unknown as ServiceClient
}

afterEach(() => {
  vi.restoreAllMocks()
})

describe('Supabase educational content adapter', () => {
  it('decodes the client cursor and encodes the next RPC tuple for the client', async () => {
    const cursor = encodeContentCursor({
      publishAt: '2026-07-21T13:00:00.000Z',
      publicationId: CURSOR_PUBLICATION_ID,
    })
    const rpc = vi.fn().mockResolvedValue({
      data: {
        items: [feedItem()],
        nextCursor: { publishAt: PUBLISH_AT, publicationId: PUBLICATION_ID },
      },
      error: null,
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    const result = await repository.list(USER_ID, {
      surface: 'library',
      category: 'hydration',
      limit: 20,
      cursor,
    })

    expect(rpc).toHaveBeenCalledWith('list_mobile_content', {
      p_user_id: USER_ID,
      p_surface: 'library',
      p_category: 'hydration',
      p_limit: 20,
      p_cursor_publish_at: '2026-07-21T13:00:00.000Z',
      p_cursor_publication_id: CURSOR_PUBLICATION_ID,
    })
    expect(Object.keys(vi.mocked(rpc).mock.calls[0]?.[1] ?? {}).sort()).toEqual([
      'p_category',
      'p_cursor_publication_id',
      'p_cursor_publish_at',
      'p_limit',
      'p_surface',
      'p_user_id',
    ])
    expect(result.items).toEqual([feedItem()])
    expect(result.nextCursor).toBe(
      encodeContentCursor({ publishAt: PUBLISH_AT, publicationId: PUBLICATION_ID }),
    )
  })

  it('sends explicit null filters and no server-clock override when pagination is absent', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { items: [], nextCursor: null },
      error: null,
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(repository.list(USER_ID, { surface: 'today', limit: 10 })).resolves.toEqual({
      items: [],
      nextCursor: null,
    })
    expect(rpc).toHaveBeenCalledWith('list_mobile_content', {
      p_user_id: USER_ID,
      p_surface: 'today',
      p_category: null,
      p_limit: 10,
      p_cursor_publish_at: null,
      p_cursor_publication_id: null,
    })
    expect(JSON.stringify(vi.mocked(rpc).mock.calls)).not.toContain('p_now')
    expect(JSON.stringify(vi.mocked(rpc).mock.calls)).not.toContain('locale')
    expect(JSON.stringify(vi.mocked(rpc).mock.calls)).not.toContain('protocol')
    expect(JSON.stringify(vi.mocked(rpc).mock.calls)).not.toContain('personality')
    expect(JSON.stringify(vi.mocked(rpc).mock.calls)).not.toContain('plan')
  })

  it('rejects a malformed cursor before calling the database', async () => {
    const rpc = vi.fn()
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(
      repository.list(USER_ID, { surface: 'library', limit: 20, cursor: 'not-a-valid-cursor' }),
    ).rejects.toEqual(new ContentRepositoryError('invalid_cursor'))
    expect(rpc).not.toHaveBeenCalled()
  })

  it('fails opaquely on malformed list payloads and does not log private response fields', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: {
        items: [feedItem({ version: 'four', secret: 'must-not-be-logged' })],
        nextCursor: null,
      },
      error: null,
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(repository.list(USER_ID, { surface: 'library', limit: 20 })).rejects.toEqual(
      new ContentRepositoryError('internal'),
    )
    expect(consoleError).toHaveBeenCalledWith('[mobile-content] operation_failed', {
      request_id: 'unknown',
      operation: 'parse_list',
      error_code: 'invalid_response',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('must-not-be-logged')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(USER_ID)
  })

  it('rejects out-of-int32 versions in feed and mutation RPC payloads', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)

    for (const version of [2_147_483_648, 1e100]) {
      const listRpc = vi.fn().mockResolvedValue({
        data: { items: [feedItem({ version })], nextCursor: null },
        error: null,
      })
      const listRepository = createSupabaseContentDependencies(serviceClient(listRpc)).repository
      await expect(listRepository.list(USER_ID, { surface: 'library', limit: 20 })).rejects.toEqual(
        new ContentRepositoryError('internal'),
      )

      const stateRpc = vi.fn().mockResolvedValue({ data: state({ version }), error: null })
      const stateRepository = createSupabaseContentDependencies(serviceClient(stateRpc)).repository
      await expect(
        stateRepository.setSaved({
          userId: USER_ID,
          publicationId: PUBLICATION_ID,
          saved: true,
          version: 4,
          origin: 'library',
          idempotencyKey: 'content-save-invalid-response-411',
        }),
      ).rejects.toEqual(new ContentRepositoryError('internal'))
    }
  })

  it('returns null for absent or P0002 detail and parses an eligible detail', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: null, error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { code: 'P0002', message: 'content_not_visible private detail' },
      })
      .mockResolvedValueOnce({
        data: {
          ...feedItem(),
          bodyMarkdown:
            '## Hidratacao consistente\n\nDistribua a ingestao de agua em momentos praticos da sua rotina diaria e ajuste a quantidade conforme sua sede e orientacao profissional.',
        },
        error: null,
      })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(repository.get(USER_ID, PUBLICATION_ID)).resolves.toBeNull()
    await expect(repository.get(USER_ID, PUBLICATION_ID)).resolves.toBeNull()
    await expect(repository.get(USER_ID, PUBLICATION_ID)).resolves.toMatchObject({
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      bodyMarkdown: expect.stringContaining('Hidratacao consistente'),
    })
    expect(rpc).toHaveBeenLastCalledWith('get_mobile_content', {
      p_user_id: USER_ID,
      p_publication_id: PUBLICATION_ID,
    })
  })

  it('rejects detail Markdown that violates the approved content limits', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: { ...feedItem(), bodyMarkdown: 'Too short.' },
      error: null,
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(repository.get(USER_ID, PUBLICATION_ID)).rejects.toEqual(
      new ContentRepositoryError('internal'),
    )
  })

  it('calls record_mobile_content_event with the exact trusted command and maps stale versions', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: state(), error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { code: '40001', message: 'content_version_changed private detail' },
      })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository
    const command = {
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      event: 'opened' as const,
      origin: 'today' as const,
      version: 4,
      idempotencyKey: 'content-read-request-411',
    }

    await expect(repository.recordRead(command)).resolves.toEqual(state())
    expect(rpc).toHaveBeenCalledWith('record_mobile_content_event', {
      p_user_id: USER_ID,
      p_publication_id: PUBLICATION_ID,
      p_version: 4,
      p_event_type: 'opened',
      p_origin: 'today',
      p_event_key: 'content-read-request-411',
    })
    await expect(repository.recordRead(command)).rejects.toEqual(
      new ContentRepositoryError('version_changed'),
    )
  })

  it('maps dedicated P4090 failures to idempotency conflict without inspecting provider messages', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: {
        code: 'P4090',
        message: 'provider detail that must not drive or enter application logs',
      },
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(
      repository.recordRead({
        userId: USER_ID,
        publicationId: PUBLICATION_ID,
        event: 'opened',
        origin: 'library',
        version: 4,
        idempotencyKey: 'content-read-conflict-411',
      }),
    ).rejects.toEqual(new ContentRepositoryError('idempotency_conflict'))
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('provider detail')
  })

  it('calls set_mobile_content_saved with fixed library origin and maps non-visible content', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: state({ saved: true, completed: false }), error: null })
      .mockResolvedValueOnce({
        data: null,
        error: { code: 'P0002', message: 'content_not_visible private detail' },
      })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository
    const command = {
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      saved: true,
      version: 4,
      origin: 'library' as const,
      idempotencyKey: 'content-save-request-411',
    }

    await expect(repository.setSaved(command)).resolves.toEqual(
      state({ saved: true, completed: false }),
    )
    expect(rpc).toHaveBeenCalledWith('set_mobile_content_saved', {
      p_user_id: USER_ID,
      p_publication_id: PUBLICATION_ID,
      p_version: 4,
      p_saved: true,
      p_origin: 'library',
      p_event_key: 'content-save-request-411',
    })
    await expect(repository.setSaved(command)).rejects.toEqual(
      new ContentRepositoryError('not_found'),
    )
  })

  it('maps unknown database failures to one opaque error and logs no message or patient id', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: 'XX999', message: 'secret database detail for a patient' },
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc), {
      requestId: 'request-content-411',
    }).repository

    await expect(repository.get(USER_ID, PUBLICATION_ID)).rejects.toEqual(
      new ContentRepositoryError('internal'),
    )
    expect(consoleError).toHaveBeenCalledWith('[mobile-content] operation_failed', {
      request_id: 'request-content-411',
      operation: 'get',
      error_code: 'unknown_error',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('secret database detail')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(USER_ID)
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(PUBLICATION_ID)
  })

  it('normalizes malformed provider error codes before logging', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: {
        code: 'synthetic-patient@example.invalid',
        message: 'private provider detail',
      },
    })
    const repository = createSupabaseContentDependencies(serviceClient(rpc)).repository

    await expect(repository.get(USER_ID, PUBLICATION_ID)).rejects.toEqual(
      new ContentRepositoryError('internal'),
    )
    expect(consoleError).toHaveBeenCalledWith('[mobile-content] operation_failed', {
      request_id: 'unknown',
      operation: 'get',
      error_code: 'unknown_error',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('synthetic-patient')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('private provider detail')
  })

  it('invokes RPC methods with the Supabase client receiver intact', async () => {
    const client = {
      marker: 'service-client',
      rpc(this: { marker: string }) {
        if (this.marker !== 'service-client') throw new Error('lost Supabase client receiver')
        return Promise.resolve({ data: { items: [], nextCursor: null }, error: null })
      },
      storage: { from: vi.fn() },
    }
    const repository = createSupabaseContentDependencies(
      client as unknown as ServiceClient,
    ).repository

    await expect(repository.list(USER_ID, { surface: 'library', limit: 20 })).resolves.toEqual({
      items: [],
      nextCursor: null,
    })
  })

  it('issues cover capabilities without sending storage locators to the codec or storage API', async () => {
    const storageFrom = vi.fn()
    const issue = vi.fn(() => ({
      token: 'opaque-cover-capability',
      expiresAt: '2026-07-21T12:10:00.000Z',
    }))
    const dependencies = createSupabaseContentDependencies(serviceClient(vi.fn(), storageFrom), {
      coverCapabilities: { issue },
    })

    await expect(
      dependencies.covers.issue({
        userId: USER_ID,
        publicationId: PUBLICATION_ID,
        version: 4,
      }),
    ).resolves.toEqual({
      token: 'opaque-cover-capability',
      expiresAt: '2026-07-21T12:10:00.000Z',
    })
    expect(issue).toHaveBeenCalledWith({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      version: 4,
    })
    expect(storageFrom).not.toHaveBeenCalled()
    expect(JSON.stringify(issue.mock.calls)).not.toContain('content-covers')
    expect(JSON.stringify(issue.mock.calls)).not.toContain('private-cover.webp')
  })

  it('rejects every other cover bucket opaquely before storage access', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const storageFrom = vi.fn()
    const rpc = vi.fn().mockResolvedValue({
      data: {
        items: [
          feedItem({
            cover: {
              bucketId: 'patient-private-media',
              objectPath: 'patient/private.jpg',
            },
          }),
        ],
        nextCursor: null,
      },
      error: null,
    })
    const rejectedBucket = createSupabaseContentDependencies(serviceClient(rpc, storageFrom))

    await expect(
      rejectedBucket.repository.list(USER_ID, { surface: 'library', limit: 20 }),
    ).rejects.toEqual(new ContentRepositoryError('internal'))
    expect(storageFrom).not.toHaveBeenCalled()
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('patient-private-media')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain('patient/private.jpg')
    expect(JSON.stringify(consoleError.mock.calls)).not.toContain(USER_ID)
  })
})
