import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { cleanupReevaluationPhotos } from '../lib/reevaluation-photo-cleanup.js'
import { createReevaluationPhotoCleanupDependencies } from '../lib/supabase-reevaluation-photo-cleanup.js'

/** Served only by the explicit clinical staging set. Ordinary/all and the
 * existing media-staging endpoint are unchanged. No LLM, analysis or upload. */
export const reevaluationPhotoDispositionCleanupFn = inngest.createFunction(
  { id: 'reevaluation-photo-disposition-cleanup', retries: 1, concurrency: { limit: 1 } },
  { cron: '* * * * *' },
  async ({ step, logger }) =>
    step.run('cleanup-recurring-photo-dispositions', async () => {
      // Also guard a direct or stale invocation, before any privileged client.
      assertClinicalStagingWorkerTarget()
      const result = await cleanupReevaluationPhotos(
        createReevaluationPhotoCleanupDependencies(createWorkerSupabase()),
      )
      // Step results/logs contain only bounded counts and safe stop reasons.
      if (result.incomplete > 0 || result.stopped !== 'batch_end')
        logger.warn('recurring photo cleanup deferred', result)
      else if (result.newlyDeleted > 0) logger.info('recurring photo cleanup batch', result)
      return result
    }),
)
