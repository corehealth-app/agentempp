import {
  prepareRegistrationFeedbackV2,
  renderRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  auth,
  context,
  day,
  legacyFeedback,
  other,
  owner,
  registrationId,
} from './__fixtures__/feedback-v2-source'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import type {
  FeedbackV2ClinicalContext,
  loadFeedbackV2ClinicalContext,
} from './registration-feedback-v2-clinical'
import {
  ensureRegistrationFeedbackV2,
  readRegistrationFeedbackV2,
} from './registration-feedback-v2-service'
import {
  type FeedbackV2Read,
  parseFeedbackV2Capture,
  type RegistrationFeedbackV2Store,
} from './registration-feedback-v2-store'

const who = { userId: owner, registrationId, kind: 'meal' as const }
const row = () => context().confirmed
function harness() {
  const observation = parseFeedbackV2Capture(context(), who)
  const clinical: FeedbackV2ClinicalContext = {
    policy: projectCurrentClinicalPublicPolicy(observation.clinical),
    officialDay: day(),
  }
  const loadClinical = vi.fn<typeof loadFeedbackV2ClinicalContext>(async () => clinical)
  const store: RegistrationFeedbackV2Store = {
    readReceipt: vi.fn(async (): Promise<FeedbackV2Read> => ({ action: 'absent' })),
    capture: vi.fn(async () => ({ action: 'available' as const, observation })),
    commit: vi.fn(async (input) => ({ action: 'committed' as const, feedback: input.feedback })),
  }
  const db = {
    rpc: vi.fn(async () => {
      throw new Error('Unexpected real RPC')
    }),
  } as unknown as ServiceClient
  const expected = prepareRegistrationFeedbackV2({
    registrationId,
    localDate: observation.facts.localDate,
    locale: 'pt-BR',
    registration: observation.facts.registration,
    policy: clinical.policy,
    officialDay: clinical.officialDay,
  })
  return { observation, clinical, loadClinical, store, db, expected }
}
describe('feedback v2 optional saved-registration service', () => {
  it('prepares all six ordered blocks from saved facts and official context, then commits once', async () => {
    const h = harness()
    const result = await ensureRegistrationFeedbackV2(h.db, auth, row(), h)
    expect(result).toEqual(h.expected)
    if (!result || result.schema !== 'registration.feedback.v2') throw new Error('Fixture feedback')
    expect(renderRegistrationFeedbackV2(result).map((section) => section.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    expect(result.day).toMatchObject({
      consumed: { calories_kcal: 126 },
      targets: { calories_kcal: 1900, protein_g: 120 },
      remaining_food_kcal: 1774,
    })
    expect(result.registration).toMatchObject({
      items: [{ kcal: 126.12 }],
      totals: { kcal: 126.1 },
    })
    expect(h.store.capture).toHaveBeenCalledTimes(1)
    expect(h.loadClinical).toHaveBeenCalledTimes(1)
    expect(h.store.commit).toHaveBeenCalledTimes(1)
    expect(h.db.rpc).not.toHaveBeenCalled()
    expect(result.education).toMatchObject({ provenance: { preferences_known: false } })
  })
  it.each([
    'v2',
    'v1',
  ] as const)('returns existing %s before source, policy or education preparation', async (version) => {
    const h = harness(),
      f = version === 'v2' ? h.expected : parseRegistrationFeedback(legacyFeedback(), who)
    vi.mocked(h.store.readReceipt).mockResolvedValueOnce(
      version === 'v2'
        ? { action: 'available', feedback: h.expected }
        : { action: 'legacy', feedback: parseRegistrationFeedback(legacyFeedback(), who) },
    )
    expect(await ensureRegistrationFeedbackV2(h.db, auth, row(), h)).toEqual(f)
    expect(h.store.capture).not.toHaveBeenCalled()
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
  })
  it('reopening is receipt-only and cannot create feedback, domain records or phrase draws', async () => {
    const h = harness()
    vi.mocked(h.store.readReceipt).mockResolvedValue({ action: 'available', feedback: h.expected })
    expect(await readRegistrationFeedbackV2(h.db, auth, row(), h.store)).toEqual(h.expected)
    expect(h.store.readReceipt).toHaveBeenCalledTimes(1)
    expect(h.store.capture).not.toHaveBeenCalled()
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
  })
  it.each([
    'pending',
    'foreign-row',
    'foreign-auth',
    'invalid-event',
  ] as const)('refuses %s before I/O', async (kind) => {
    const h = harness(),
      r = row(),
      a = structuredClone(auth)
    if (kind === 'pending') r.status = 'pending'
    if (kind === 'foreign-row') r.user_id = other
    if (kind === 'foreign-auth') a.userId = other
    if (kind === 'invalid-event') r.id = 'not-a-uuid'
    expect(await ensureRegistrationFeedbackV2(h.db, a, r, h)).toBeNull()
    expect(h.store.readReceipt).not.toHaveBeenCalled()
  })
  it('refuses changed canonical proposal rather than describing a different saved event', async () => {
    const h = harness(),
      r = row()
    r.proposal.totals.kcal = 999
    expect(await ensureRegistrationFeedbackV2(h.db, auth, r, h)).toBeNull()
    expect(h.loadClinical).not.toHaveBeenCalled()
    expect(h.store.commit).not.toHaveBeenCalled()
  })
  it('detaches auth and saved event before awaits so alias mutation cannot switch accounts', async () => {
    const h = harness(),
      a = structuredClone(auth),
      r = row()
    vi.mocked(h.store.readReceipt).mockImplementationOnce(async () => {
      a.userId = other
      r.proposal.totals.kcal = 999
      return { action: 'absent' }
    })
    expect(await ensureRegistrationFeedbackV2(h.db, a, r, h)).toEqual(h.expected)
    expect(h.store.capture).toHaveBeenCalledWith(who)
    expect(h.loadClinical.mock.calls[0]?.[1].userId).toBe(owner)
  })
  it('reconciles an uncertain commit once by read, never retries the registration or commit', async () => {
    const h = harness()
    vi.mocked(h.store.readReceipt)
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce({ action: 'available', feedback: h.expected })
    vi.mocked(h.store.commit).mockRejectedValue(new Error('lost response after commit'))
    expect(await ensureRegistrationFeedbackV2(h.db, auth, row(), h)).toEqual(h.expected)
    expect(h.store.readReceipt).toHaveBeenCalledTimes(2)
    expect(h.store.capture).toHaveBeenCalledTimes(1)
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('does not repeat a known source conflict or substitute an unproved day', async () => {
    const h = harness()
    vi.mocked(h.store.commit).mockResolvedValue({ action: 'source_conflict' })
    expect(await ensureRegistrationFeedbackV2(h.db, auth, row(), h)).toBeNull()
    expect(h.store.capture).toHaveBeenCalledTimes(1)
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('keeps a saved registration successful when optional clinical enrichment fails', async () => {
    const h = harness()
    h.loadClinical.mockRejectedValue(new Error('private clinical detail'))
    expect(await ensureRegistrationFeedbackV2(h.db, auth, row(), h)).toBeNull()
    expect(h.store.commit).not.toHaveBeenCalled()
    expect(row().status).toBe('confirmed')
  })
  it('accepts a competing legacy winner without another draw or new receipt', async () => {
    const h = harness(),
      legacy = parseRegistrationFeedback(legacyFeedback(), who)
    vi.mocked(h.store.commit).mockResolvedValue({ action: 'legacy', feedback: legacy })
    expect(await ensureRegistrationFeedbackV2(h.db, auth, row(), h)).toEqual(legacy)
    expect(h.store.commit).toHaveBeenCalledTimes(1)
  })
  it('retains item feedback while the optional day is unavailable', async () => {
    const h = harness()
    h.clinical.officialDay = null
    const value = await ensureRegistrationFeedbackV2(h.db, auth, row(), h)
    expect(value).toMatchObject({
      schema: 'registration.feedback.v2',
      day: null,
      registration: { items: [{ quantity: { unit: 'mL', value: 200 } }] },
    })
  })
})
