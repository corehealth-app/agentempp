import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import type { MediaAssetRecord } from './media-service'
import {
  confirmPlanDraft,
  createPlanImport,
  discardPlanDraft,
  getPlanDraft,
  listPlanDrafts,
  type PlanDraftDependencies,
  type PlanDraftRecord,
  planDraftDatabaseError,
  updatePlanDraft,
} from './plan-draft-service'

const USER_A = '00000000-0000-4000-8000-00000000000a'
const USER_B = '00000000-0000-4000-8000-00000000000b'
const DRAFT = '11111111-1111-4111-8111-111111111111'
const ASSET = '22222222-2222-4222-8222-222222222222'
const NOW = new Date('2026-09-28T12:00:00.000Z')

const exercise = {
  name: 'Agachamento',
  muscle_group: 'pernas',
  sets: 4,
  reps_range: '8-12',
  rest_seconds: 90,
}
const training = {
  plan_type: 'split',
  weekly_schedule: [{ day: 'seg', focus: 'inferiores', duration_min: 60, exercises: [exercise] }],
}

function draft(overrides: Partial<PlanDraftRecord> = {}): PlanDraftRecord {
  return {
    id: DRAFT,
    user_id: USER_A,
    domain: 'training',
    origin: 'flow_generated',
    status: 'ready_for_review',
    source_media_asset_id: null,
    payload: training,
    payload_version: 1,
    uncertain_fields: [],
    unrecognized_segments: [],
    base_active_plan_id: '33333333-3333-4333-8333-333333333333',
    base_latest_prescription_id: null,
    failure_code: null,
    confirmed_plan_id: null,
    created_at: '2026-09-28T11:00:00.000Z',
    updated_at: '2026-09-28T11:00:00.000Z',
    expires_at: '2026-10-28T11:00:00.000Z',
    resolved_at: null,
    ...overrides,
  }
}

function asset(overrides: Partial<MediaAssetRecord> = {}): MediaAssetRecord {
  return {
    id: ASSET,
    user_id: USER_A,
    kind: 'plan_document',
    bucket_id: 'plan-documents',
    object_path: `${USER_A}/${ASSET}.pdf`,
    mime_type: 'application/pdf',
    declared_size_bytes: 1000,
    actual_size_bytes: 1000,
    status: 'uploaded',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: null,
    uploaded_at: '2026-09-28T11:00:00.000Z',
    processed_at: null,
    deleted_at: null,
    created_at: '2026-09-28T11:00:00.000Z',
    updated_at: '2026-09-28T11:00:00.000Z',
    ...overrides,
  }
}

function harness(
  stored: PlanDraftRecord | null = draft(),
  media: MediaAssetRecord | null = asset(),
  imported: PlanDraftRecord | null = null,
) {
  let current = stored
  const outcome = () => ({
    id: DRAFT,
    status: current?.status ?? 'ready_for_review',
    payload_version: current?.payload_version ?? 1,
    confirmed_plan_id: current?.confirmed_plan_id ?? null,
  })
  const repository = {
    list: vi.fn(async (userId: string) => (current && current.user_id === userId ? [current] : [])),
    findOwned: vi.fn(async (userId: string, id: string) =>
      current && current.user_id === userId && current.id === id ? current : null,
    ),
    update: vi.fn(async (input: { payload: Record<string, unknown>; complete: boolean }) => {
      if (current) {
        current = {
          ...current,
          payload: input.payload,
          payload_version: current.payload_version + 1,
          status: input.complete ? 'ready_for_review' : 'needs_completion',
        }
      }
      return outcome()
    }),
    confirm: vi.fn(async () => {
      const already = current?.status === 'confirmed'
      if (current) {
        current = {
          ...current,
          status: 'confirmed',
          confirmed_plan_id: '44444444-4444-4444-8444-444444444444',
          resolved_at: NOW.toISOString(),
        }
      }
      return { ...outcome(), already_confirmed: already }
    }),
    discard: vi.fn(async () => {
      if (current) current = { ...current, status: 'discarded', resolved_at: NOW.toISOString() }
      return outcome()
    }),
    findImportOfMedia: vi.fn(async (userId: string) =>
      imported && imported.user_id === userId ? imported : null,
    ),
    createImport: vi.fn(async () => ({
      id: DRAFT,
      status: 'extracting' as const,
      payload_version: 1,
      confirmed_plan_id: null,
      inserted: true,
    })),
  }
  const deps: PlanDraftDependencies = {
    repository,
    media: {
      findOwned: vi.fn(async (userId: string, id: string) =>
        media && media.user_id === userId && media.id === id ? media : null,
      ),
    },
    events: { sendProcessingRequested: vi.fn(async () => {}) },
  }
  return { deps, repository }
}

async function failure(promise: Promise<unknown>): Promise<MobileApiError> {
  try {
    await promise
  } catch (error) {
    if (error instanceof MobileApiError) return error
    throw error
  }
  throw new Error('expected a MobileApiError')
}

describe('reading', () => {
  it('a supplement kept from an imported document is not called "not imported"; one proposed by Flow is', async () => {
    const flagged = { uncertain_fields: [{ pointer: '/daily_meals/0/items/0', reason: 'supplement' }] }
    const imported = await getPlanDraft(
      harness(draft({ origin: 'imported_pdf', source_media_asset_id: ASSET, ...flagged })).deps,
      USER_A,
      DRAFT,
      NOW,
    )
    expect(imported.notices).toEqual(['not_professionally_reviewed'])
    const proposed = await getPlanDraft(
      harness(draft({ origin: 'flow_generated', ...flagged })).deps,
      USER_A,
      DRAFT,
      NOW,
    )
    expect(proposed.notices).toEqual(['not_professionally_reviewed', 'medications_not_imported'])
  })

  it('shows the draft with the notice that it is not a professional review', async () => {
    const { deps } = harness(
      draft({
        origin: 'imported_pdf',
        source_media_asset_id: ASSET,
        unrecognized_segments: ['Tomar 1 comprimido de X', 'Observação do treinador'],
      }),
    )
    const dto = await getPlanDraft(deps, USER_A, DRAFT, NOW)
    expect(dto.notices).toEqual(['not_professionally_reviewed', 'medications_not_imported'])
    expect(dto.unrecognized_segments).toEqual([
      'Tomar 1 comprimido de X',
      'Observação do treinador',
    ])
    expect(dto.replaces_current_plan).toBe(true)
    expect(dto.can_confirm).toBe(true)
    expect(dto).not.toHaveProperty('user_id')
    expect(dto).not.toHaveProperty('request_key')
    expect(dto).not.toHaveProperty('extraction_payload')
    expect(dto).not.toHaveProperty('origin_detail')
  })

  it('another patient gets 404 for every operation and nothing is written', async () => {
    const { deps, repository } = harness()
    const input = { payload_version: 1 }
    for (const attempt of [
      getPlanDraft(deps, USER_B, DRAFT, NOW),
      updatePlanDraft(deps, USER_B, DRAFT, { ...input, payload: training }, NOW),
      confirmPlanDraft(deps, USER_B, DRAFT, input, 'confirm-key-0001', NOW),
      discardPlanDraft(deps, USER_B, DRAFT, NOW),
    ]) {
      const error = await failure(attempt)
      expect(error.status).toBe(404)
      expect(error.code).toBe('plan_draft_not_found')
    }
    expect((await listPlanDrafts(deps, USER_B, { status: 'open' }, NOW)).items).toEqual([])
    expect(repository.update).not.toHaveBeenCalled()
    expect(repository.confirm).not.toHaveBeenCalled()
    expect(repository.discard).not.toHaveBeenCalled()
  })

  it('an expired draft reads as expired and leaves the open list', async () => {
    const { deps } = harness(draft({ expires_at: '2026-09-28T11:59:59.000Z' }))
    expect((await getPlanDraft(deps, USER_A, DRAFT, NOW)).status).toBe('expired')
    expect((await getPlanDraft(deps, USER_A, DRAFT, NOW)).can_confirm).toBe(false)
    expect((await listPlanDrafts(deps, USER_A, { status: 'open' }, NOW)).items).toEqual([])
  })
})

describe('editing', () => {
  it('an incomplete edit is kept as incomplete, with what is missing', async () => {
    const { deps, repository } = harness()
    const dto = await updatePlanDraft(
      deps,
      USER_A,
      DRAFT,
      {
        payload_version: 1,
        payload: {
          weekly_schedule: [
            { day: 'seg', focus: 'a', duration_min: 900, exercises: [{ ...exercise, sets: 99 }] },
          ],
          medication: 'X 10 mg',
        },
      },
      NOW,
    )
    expect(repository.update).toHaveBeenCalledWith(
      expect.objectContaining({
        complete: false,
        expectedVersion: 1,
        uncertainFields: expect.arrayContaining([
          { pointer: '/weekly_schedule/0/duration_min', reason: 'out_of_range' },
          { pointer: '/weekly_schedule/0/exercises/0/sets', reason: 'out_of_range' },
        ]),
      }),
    )
    expect(dto.status).toBe('needs_completion')
    expect(dto.can_confirm).toBe(false)
    expect(JSON.stringify(dto.payload)).not.toContain('medication')
  })

  it('an edit over another version is refused before any write', async () => {
    const { deps, repository } = harness(draft({ payload_version: 3 }))
    const error = await failure(
      updatePlanDraft(deps, USER_A, DRAFT, { payload_version: 2, payload: training }, NOW),
    )
    expect([error.status, error.code]).toEqual([409, 'draft_changed'])
    expect(repository.update).not.toHaveBeenCalled()
  })

  it('a resolved or expired draft is not edited', async () => {
    for (const [stored, status, code] of [
      [draft({ status: 'confirmed' }), 409, 'plan_draft_not_reviewable'],
      [draft({ status: 'discarded' }), 409, 'plan_draft_not_reviewable'],
      [draft({ status: 'extracting', payload: null }), 409, 'plan_draft_not_reviewable'],
      [draft({ expires_at: '2026-09-01T00:00:00.000Z' }), 410, 'plan_draft_expired'],
    ] as const) {
      const { deps, repository } = harness(stored)
      const error = await failure(
        updatePlanDraft(deps, USER_A, DRAFT, { payload_version: 1, payload: training }, NOW),
      )
      expect([error.status, error.code]).toEqual([status, code])
      expect(repository.update).not.toHaveBeenCalled()
    }
  })
})

describe('confirming', () => {
  it('confirms the reviewed version with the validity of its origin', async () => {
    const { deps, repository } = harness()
    const dto = await confirmPlanDraft(
      deps,
      USER_A,
      DRAFT,
      { payload_version: 1 },
      'confirm-key-0001',
      NOW,
    )
    expect(repository.confirm).toHaveBeenCalledWith({
      userId: USER_A,
      draftId: DRAFT,
      payloadVersion: 1,
      validUntil: '2026-11-09T12:00:00.000Z',
      idempotencyKey: 'confirm-key-0001',
    })
    expect(dto.status).toBe('confirmed')
    expect(dto.already_confirmed).toBe(false)
    expect(dto.notices).toContain('not_professionally_reviewed')
  })

  it('an imported plan gets no invented validity', async () => {
    const { deps, repository } = harness(
      draft({ origin: 'imported_photo', source_media_asset_id: ASSET }),
    )
    await confirmPlanDraft(deps, USER_A, DRAFT, { payload_version: 1 }, 'confirm-key-0002', NOW)
    expect(repository.confirm).toHaveBeenCalledWith(expect.objectContaining({ validUntil: null }))
  })

  it('refuses what the patient did not review, what is incomplete and what expired', async () => {
    for (const [stored, version, status, code] of [
      [draft({ payload_version: 2 }), 1, 409, 'draft_changed'],
      [draft({ status: 'needs_completion' }), 1, 422, 'plan_draft_incomplete'],
      [draft({ status: 'extracting', payload: null }), 1, 409, 'plan_draft_not_reviewable'],
      [draft({ status: 'discarded' }), 1, 409, 'plan_draft_not_reviewable'],
      [draft({ status: 'failed', failure_code: 'x' }), 1, 409, 'plan_draft_not_reviewable'],
      [draft({ expires_at: '2026-09-01T00:00:00.000Z' }), 1, 410, 'plan_draft_expired'],
    ] as const) {
      const { deps, repository } = harness(stored)
      const error = await failure(
        confirmPlanDraft(deps, USER_A, DRAFT, { payload_version: version }, 'confirm-key-0003', NOW),
      )
      expect([error.status, error.code]).toEqual([status, code])
      expect(repository.confirm).not.toHaveBeenCalled()
    }
  })

  it('content that does not pass the strict rules is refused whatever the status says', async () => {
    const { deps, repository } = harness(
      draft({
        status: 'ready_for_review',
        payload: { weekly_schedule: [{ day: 'seg', exercises: [] }] },
      }),
    )
    const error = await failure(
      confirmPlanDraft(deps, USER_A, DRAFT, { payload_version: 1 }, 'confirm-key-0004', NOW),
    )
    expect([error.status, error.code]).toEqual([422, 'plan_draft_incomplete'])
    expect(repository.confirm).not.toHaveBeenCalled()
  })

  it('the same confirmation again answers with the same plan', async () => {
    const { deps } = harness()
    const first = await confirmPlanDraft(
      deps, USER_A, DRAFT, { payload_version: 1 }, 'confirm-key-0005', NOW,
    )
    const second = await confirmPlanDraft(
      deps, USER_A, DRAFT, { payload_version: 1 }, 'confirm-key-0005', NOW,
    )
    expect(second.confirmed_plan_id).toBe(first.confirmed_plan_id)
    expect(second.already_confirmed).toBe(true)
  })
})

describe('importing', () => {
  it('starts a draft in extraction and asks the worker to read the document', async () => {
    const { deps, repository } = harness()
    const result = await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'nutrition' }, 'import-key-0001',
    )
    expect(result).toEqual({ draft_id: DRAFT, status: 'extracting' })
    expect(repository.createImport).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: USER_A,
        domain: 'nutrition',
        origin: 'imported_pdf',
        mediaAssetId: ASSET,
        requestKey: expect.stringMatching(/^plan-import:[0-9a-f]{64}$/),
      }),
    )
    expect(deps.events.sendProcessingRequested).toHaveBeenCalledWith(
      expect.objectContaining({ assetId: ASSET, userId: USER_A }),
    )
  })

  it('a photo is an imported photo', async () => {
    const { deps, repository } = harness(draft(), asset({ mime_type: 'image/jpeg' }))
    await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0002',
    )
    expect(repository.createImport).toHaveBeenCalledWith(
      expect.objectContaining({ origin: 'imported_photo' }),
    )
  })

  it('refuses the media of another patient, other kinds and what was not uploaded', async () => {
    for (const [userId, media, status, code] of [
      [USER_B, asset(), 404, 'media_asset_not_found'],
      [USER_A, asset({ status: 'deleted' }), 404, 'media_asset_not_found'],
      [USER_A, asset({ kind: 'meal_photo' }), 422, 'media_kind_not_supported'],
      [USER_A, asset({ status: 'pending_upload' }), 409, 'media_not_uploaded'],
      [USER_A, asset({ status: 'failed', failure_stage: 'upload', failure_code: 'x' }), 409,
        'media_not_uploaded'],
      [USER_A, asset({ status: 'processed' }), 409, 'plan_document_already_read'],
      [USER_A, asset({ status: 'processing' }), 409, 'plan_document_already_read'],
    ] as const) {
      const { deps, repository } = harness(draft(), media)
      const error = await failure(
        createPlanImport(
          deps, userId, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0003',
        ),
      )
      expect([error.status, error.code]).toEqual([status, code])
      expect(repository.createImport).not.toHaveBeenCalled()
      expect(deps.events.sendProcessingRequested).not.toHaveBeenCalled()
    }
  })
})

describe('importing the same document again', () => {
  const imported = draft({
    origin: 'imported_pdf',
    domain: 'nutrition',
    status: 'needs_completion',
    source_media_asset_id: ASSET,
  })

  it('answers with the draft it already produced and reads nothing again', async () => {
    const { deps, repository } = harness(draft(), asset({ status: 'processed' }), imported)

    const result = await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'nutrition' }, 'import-key-0009',
    )

    expect(result).toEqual({ draft_id: DRAFT, status: 'needs_completion' })
    expect(repository.createImport).not.toHaveBeenCalled()
    expect(deps.events.sendProcessingRequested).not.toHaveBeenCalled()
  })

  it('a draft still waiting for its reading asks for it again (the first event may be lost)', async () => {
    const waiting = { ...imported, status: 'extracting' as const, payload: null }
    const { deps, repository } = harness(draft(), asset({ status: 'uploaded' }), waiting)

    const first = await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'nutrition' }, 'import-key-0012',
    )
    const second = await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'nutrition' }, 'import-key-0012',
    )

    expect(first).toEqual({ draft_id: DRAFT, status: 'extracting' })
    expect(second).toEqual(first)
    expect(repository.createImport).not.toHaveBeenCalled()
    const sent = vi.mocked(deps.events.sendProcessingRequested).mock.calls.map(([event]) => event)
    expect(sent).toHaveLength(2)
    // The same event both times: a reading under way is not repeated.
    expect(sent[0]).toEqual(sent[1])
    expect(sent[0]).toMatchObject({ assetId: ASSET, userId: USER_A })
  })

  it('the event that failed to be sent fails the request, so the app asks again', async () => {
    const { deps } = harness()
    vi.mocked(deps.events.sendProcessingRequested).mockRejectedValueOnce(new Error('queue down'))
    await expect(
      createPlanImport(
        deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0013',
      ),
    ).rejects.toThrow('queue down')
  })

  it('two requests at once for one document answer with the same draft', async () => {
    const { deps, repository } = harness()
    repository.createImport.mockRejectedValueOnce(
      new MobileApiError(409, 'idempotency_key_conflict', 'Request key was already used'),
    )
    repository.findImportOfMedia
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ ...imported, status: 'extracting', domain: 'training' })

    const result = await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0014',
    )

    expect(result).toEqual({ draft_id: DRAFT, status: 'extracting' })
    expect(deps.events.sendProcessingRequested).toHaveBeenCalledOnce()
  })

  it('and refuse the one that asked for another kind of plan', async () => {
    const { deps, repository } = harness()
    repository.createImport.mockRejectedValueOnce(
      new MobileApiError(409, 'idempotency_key_conflict', 'Request key was already used'),
    )
    repository.findImportOfMedia
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ ...imported, status: 'extracting', domain: 'nutrition' })

    const error = await failure(
      createPlanImport(
        deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0015',
      ),
    )
    expect([error.status, error.code]).toEqual([409, 'plan_document_already_imported'])
    expect(deps.events.sendProcessingRequested).not.toHaveBeenCalled()
  })

  it('refuses to import it as another kind of plan', async () => {
    const { deps, repository } = harness(draft(), asset({ status: 'processed' }), imported)
    const error = await failure(
      createPlanImport(
        deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0010',
      ),
    )
    expect([error.status, error.code]).toEqual([409, 'plan_document_already_imported'])
    expect(repository.createImport).not.toHaveBeenCalled()
  })

  it('a failed reading can be asked again', async () => {
    const { deps, repository } = harness(
      draft(),
      asset({ status: 'failed', failure_stage: 'processing', failure_code: 'provider_error' }),
      null,
    )
    await createPlanImport(
      deps, USER_A, { media_asset_id: ASSET, domain: 'training' }, 'import-key-0011',
    )
    expect(repository.createImport).toHaveBeenCalledOnce()
    expect(deps.events.sendProcessingRequested).toHaveBeenCalledOnce()
  })
})

describe('database outcomes', () => {
  it('maps every refusal of the RPCs', () => {
    expect(
      ['PD404', 'PD409', 'PD410', 'PD412', 'PD422', 'PD423', 'PD429', '22023', '23505', 'XX000'].map(
        (code) => {
          const error = planDraftDatabaseError({ code, message: 'secret detail' })
          expect(error.message).not.toContain('secret')
          return [error.status, error.code]
        },
      ),
    ).toEqual([
      [404, 'plan_draft_not_found'],
      [409, 'draft_changed'],
      [410, 'plan_draft_expired'],
      [409, 'plan_changed_during_review'],
      [409, 'plan_draft_not_reviewable'],
      [409, 'prescribed_plan_protected'],
      [429, 'plan_draft_limit_reached'],
      [422, 'plan_draft_invalid'],
      [409, 'idempotency_key_conflict'],
      [500, 'plan_draft_storage_failed'],
    ])
  })
})
