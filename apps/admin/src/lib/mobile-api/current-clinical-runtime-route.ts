/** Route selection is lazy. An unavailable current selection must never invoke
 * a legacy writer/closer or initialize a provider. No runtime is enabled here. */
import { randomUUID } from 'node:crypto'
import { readClinicalRepresentation } from './clinical-representation'
import {
  type CurrentClinicalRuntimeSelection,
  type CurrentClinicalRuntimeTarget,
  currentClinicalRuntimeSelection,
} from './current-clinical-runtime-switch'
import { MobileApiError, mobileErrorResponse } from './http'

type Route<Args extends unknown[]> = (request: Request, ...args: Args) => Promise<Response>
export function selectCurrentClinicalRoute<Args extends unknown[]>(
  current: (target: CurrentClinicalRuntimeTarget) => Route<Args>,
  legacy?: Route<Args>,
  selection: () => CurrentClinicalRuntimeSelection = currentClinicalRuntimeSelection,
): Route<Args> {
  return async (request, ...args) => {
    const target = selection()
    if (target.mode === 'current') return current(target)(request, ...args)
    if (
      target.mode === 'legacy' &&
      legacy &&
      !new URL(request.url).searchParams.has('clinical_policy')
    )
      return legacy(request, ...args)
    const supplied = request.headers.get('x-request-id')
    const requestId =
      supplied && /^[A-Za-z0-9._:-]{8,128}$/.test(supplied) ? supplied : randomUUID()
    try {
      readClinicalRepresentation(request.url)
      throw new MobileApiError(
        503,
        'current_clinical_runtime_unavailable',
        'Clinical runtime unavailable',
      )
    } catch (error) {
      return mobileErrorResponse(
        error instanceof MobileApiError
          ? error
          : new MobileApiError(
              503,
              'current_clinical_runtime_unavailable',
              'Clinical runtime unavailable',
            ),
        requestId,
      )
    }
  }
}
