import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { createConversationIntakeSessionService } from './conversation-intake-session'
import type { CurrentClinicalStateSource } from './current-clinical-state'

function setup() {
  const f = replyFixture(),
    enabled = vi.fn(() => true),
    auth = {
      verifyAccessToken: vi.fn(async () => f.auth.identity),
      loadPatient: vi.fn(async () => f.auth.patient),
      isAdmin: vi.fn(async () => false),
    },
    capture = vi.fn<CurrentClinicalStateSource['capture']>(async () => f.profile),
    ports = { enabled, auth, clinical: { capture } },
    db = { rpc: vi.fn(), from: vi.fn() },
    service = createConversationIntakeSessionService(db as unknown as ServiceClient, ports)
  return { ...f, enabled, authPorts: auth, capture, ports, service, db }
}
describe('genuine neutral existing-account session without a fake command', () => {
  it('returns only current observed identity and the neutral protocol', async () => {
    const f = setup()
    expect(await f.service.read(f.auth)).toEqual({
      schema: 'conversation.intake-session.v1',
      auth_user_id: f.auth.authUserId,
      owner_id: f.auth.userId,
      epoch: f.profile.epoch,
      observed_at: f.profile.observed_at,
      intake_protocol: 'conversation.intake.v1',
    })
    expect(f.capture).toHaveBeenCalledTimes(2)
    expect(f.capture.mock.calls[0]?.[0]).toEqual({ userId: f.auth.userId, mode: 'profile' })
    expect(f.capture.mock.calls[1]?.[0]).toEqual({
      userId: f.auth.userId,
      mode: 'profile',
      expectedEpoch: f.profile.epoch,
    })
    expect(f.db.rpc).not.toHaveBeenCalled()
    expect(f.db.from).not.toHaveBeenCalled()
  })
  it('is default OFF and performs no Auth, profile or domain call', async () => {
    const f = setup(),
      service = createConversationIntakeSessionService(f.db as unknown as ServiceClient, {
        auth: f.authPorts,
        clinical: { capture: f.capture },
      })
    await expect(service.read(f.auth)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(f.capture).not.toHaveBeenCalled()
    expect(f.authPorts.verifyAccessToken).not.toHaveBeenCalled()
  })
  it.each([
    'token',
    'admin',
    'mapping',
    'inactive',
  ] as const)('refuses %s before clinical access', async (reason) => {
    const f = setup()
    if (reason === 'token')
      f.authPorts.verifyAccessToken.mockRejectedValueOnce(new Error('Token unavailable'))
    if (reason === 'admin') f.authPorts.isAdmin.mockResolvedValueOnce(true)
    if (reason === 'mapping')
      f.authPorts.loadPatient.mockResolvedValueOnce({ ...f.auth.patient, id: f.auth.authUserId })
    if (reason === 'inactive')
      f.authPorts.loadPatient.mockResolvedValueOnce({ ...f.auth.patient, status: 'deleted' })
    await expect(f.service.read(f.auth)).rejects.toMatchObject({
      code: (
        {
          token: 'invalid_access_token',
          admin: 'patient_admin_account_conflict',
          mapping: 'conversation_patient_changed',
          inactive: 'patient_account_inactive',
        } as const
      )[reason],
    })
    expect(f.capture).not.toHaveBeenCalled()
  })
  it('denies a reset between the initial observation and the final current scope', async () => {
    const f = setup()
    f.capture
      .mockResolvedValueOnce(f.profile)
      .mockResolvedValueOnce({ ...f.profile, epoch: f.auth.authUserId })
    await expect(f.service.read(f.auth)).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
  })
  it('does not publish after capability is lost during the profile call', async () => {
    const f = setup()
    f.capture.mockImplementationOnce(async () => {
      f.enabled.mockReturnValue(false)
      return f.profile
    })
    await expect(f.service.read(f.auth)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
  })
  it('does not publish after token refusal during the initial capture', async () => {
    const f = setup()
    f.capture.mockImplementationOnce(async () => {
      f.authPorts.verifyAccessToken.mockRejectedValueOnce(new Error('Revoked'))
      return f.profile
    })
    await expect(f.service.read(f.auth)).rejects.toMatchObject({ code: 'invalid_access_token' })
  })
  it('does not leak or retry an uncertain clinical result', async () => {
    const f = setup()
    f.capture.mockRejectedValueOnce(new Error('Private raw SQL failure'))
    await expect(f.service.read(f.auth)).rejects.toMatchObject({
      code: 'mobile_current_clinical_unavailable',
    })
    expect(f.capture).toHaveBeenCalledOnce()
  })
})
