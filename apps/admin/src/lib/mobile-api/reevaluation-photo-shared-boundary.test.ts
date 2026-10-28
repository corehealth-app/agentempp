import { drainReevaluationPhotoDisposition } from '@mpp/agent/reevaluation-photo-disposition'
import { createReevaluationPhotoDispositionDependencies } from '@mpp/agent/supabase-reevaluation-photo-disposition'
import type { ServiceClient } from '@mpp/db'
import { drainReevaluationPhotoDisposition as workerDrain } from '@mpp/inngest-functions/reevaluation-photo-disposition'
import { createReevaluationPhotoDispositionDependencies as workerDependencies } from '@mpp/inngest-functions/supabase-reevaluation-photo-disposition'
import { describe, expect, it, vi } from 'vitest'

describe('shared inert recurring-photo disposition boundary', () => {
  it('keeps the existing worker entrypoints on the exact shared implementation', () => {
    expect(workerDrain).toBe(drainReevaluationPhotoDisposition)
    expect(workerDependencies).toBe(createReevaluationPhotoDispositionDependencies)
  })
  it('constructs backend dependencies without creating a client, reading credentials or registering a job', () => {
    const access = vi.fn(() => {
      throw new Error('No runtime access at construction')
    })
    const client = new Proxy({}, { get: access }) as ServiceClient
    const deps = createReevaluationPhotoDispositionDependencies(client)
    expect(Object.keys(deps).sort()).toEqual(['commit', 'page', 'prepare', 'remove'])
    expect(access).not.toHaveBeenCalled()
  })
})
