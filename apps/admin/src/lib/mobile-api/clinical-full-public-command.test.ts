import { describe, expect, it } from 'vitest'
import { readClinicalFullContext } from './clinical-full-authority'
import {
  bindClinicalFullPublicCommand,
  clinicalFullPublicCandidateId,
  clinicalFullPublicInputSchema,
} from './clinical-full-public-command'
import wire from './testing/clinical-full-wire.json'

const scope = {
  userId: wire.context.user_id,
  cycleId: wire.context.cycle_id,
  kind: 'REGULAR' as const,
}
const context = () => readClinicalFullContext(wire.context, scope)
const proof = () => structuredClone(wire.receipt.intent.bodyFat)
const input = () => ({
  activityPurpose: wire.receipt.form.activityPurpose,
  answers: structuredClone(wire.receipt.form.answers),
  preference: null,
  choice: { kind: 'keep' },
  measureConfirmed: false,
  bodyFat: { confirmed: true, candidateId: clinicalFullPublicCandidateId(scope, proof()) },
})
describe('public FULL input binds private form/measurement identity on the server', () => {
  it('uses actual current phase/kind and real photo mean without accepting a client formula or private hash', () => {
    const value = bindClinicalFullPublicCommand(input(), scope, { context: context() })
    expect(value.form.phase).toBe('recomposicao')
    expect(value.form.kind).toBe('REGULAR')
    expect(value.bodyFat).toEqual(proof())
    expect(input().bodyFat.candidateId).not.toBe(proof()?.sourceHash)
  })
  it.each([
    'phase',
    'kind',
    'noPlanOrigin',
    'targets',
    'context_hash',
  ])('refuses a client supplied %s', (field) => {
    expect(
      clinicalFullPublicInputSchema.safeParse({ ...input(), [field]: 'forbidden' }).success,
    ).toBe(false)
  })
  it('refuses a client mean or private source hash instead of treating them as proof', () => {
    expect(clinicalFullPublicInputSchema.safeParse({ ...input(), bodyFat: proof() }).success).toBe(
      false,
    )
    expect(
      clinicalFullPublicInputSchema.safeParse({
        ...input(),
        bodyFat: { ...input().bodyFat, meanHundredths: 1000 },
      }).success,
    ).toBe(false)
  })
  it('requires exactly the photo reading shown; a replacement candidate invalidates its opaque identity', () => {
    const changed = context()
    const candidate = changed.facts.protocol_authority.body_fat_candidate
    if (!candidate || candidate.availability !== 'available')
      throw new Error('Real fixture candidate missing')
    candidate.mean_hundredths += 1
    expect(() => bindClinicalFullPublicCommand(input(), scope, { context: changed })).toThrow()
  })
  it('binding includes the real owner and cycle, so another scope cannot reuse the displayed reading', () => {
    expect(
      clinicalFullPublicCandidateId(
        { ...scope, userId: 'b3b01000-0000-4000-8000-000000004399' },
        proof(),
      ),
    ).not.toBe(input().bodyFat.candidateId)
    expect(
      clinicalFullPublicCandidateId(
        { ...scope, cycleId: 'b3b01000-0000-4000-8000-000000004399' },
        proof(),
      ),
    ).not.toBe(input().bodyFat.candidateId)
  })
})
