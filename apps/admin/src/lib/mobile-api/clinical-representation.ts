/** Small inert leaf shared by the dormant HTTP composition and clinical
 * readers. Importing negotiation must not initialize numeric read sources. */
import { MobileApiError } from './http'

export function readClinicalRepresentation(url: string) {
  const search = new URL(url).searchParams
  const values = search.getAll('clinical_policy')
  if (values.length > 1 || (values.length === 1 && values[0] !== 'current_clinical_v1'))
    throw new MobileApiError(
      400,
      'invalid_clinical_policy_representation',
      'Invalid clinical representation',
    )
  const energy = search.getAll('day_energy')
  if (
    energy.length > 1 ||
    (energy.length === 1 &&
      (energy[0] !== 'field_availability_v1' || values[0] !== 'current_clinical_v1'))
  )
    throw new MobileApiError(
      400,
      'invalid_day_energy_representation',
      'Invalid day energy representation',
    )
  search.delete('day_energy')
  search.delete('clinical_policy')
  return {
    compatible: values[0] === 'current_clinical_v1',
    dayEnergyCompatible: energy[0] === 'field_availability_v1',
    search,
  }
}
