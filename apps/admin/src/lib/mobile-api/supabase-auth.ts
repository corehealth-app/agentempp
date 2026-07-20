import type { ServiceClient } from '@mpp/db'
import { createPatientBearerClient } from '../supabase/server'
import type { MobileAuthDependencies, MobilePatient } from './auth'

export function createMobileAuthDependencies(supabase: ServiceClient): MobileAuthDependencies {
  return {
    async verifyAccessToken(token) {
      const { data, error } = await supabase.auth.getUser(token)
      if (error || !data.user) return null
      return {
        id: data.user.id,
        email: data.user.email ?? null,
        emailConfirmedAt: data.user.email_confirmed_at ?? null,
      }
    },

    async bootstrapPatient(token) {
      const patientClient = createPatientBearerClient(token)
      const { data, error } = await patientClient.rpc('bootstrap_patient_profile')
      if (error) throw new Error(error.message)
      if (!data) throw new Error('patient bootstrap returned no id')
      return data
    },

    async loadPatient(authUserId) {
      const { data, error } = await supabase
        .from('users')
        .select('id, auth_user_id, email, name, locale, timezone, country, status')
        .eq('auth_user_id', authUserId)
        .maybeSingle()
      if (error) throw new Error('patient identity lookup failed')
      if (!data?.auth_user_id) return null
      return {
        id: data.id,
        authUserId: data.auth_user_id,
        email: data.email,
        name: data.name,
        locale: data.locale,
        timezone: data.timezone,
        country: data.country,
        status: data.status,
      } satisfies MobilePatient
    },
  }
}
