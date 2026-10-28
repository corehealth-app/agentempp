import { describe, expect, it } from 'vitest'
import { resolveCurrentClinicalRuntime } from './current-clinical-runtime-switch'

const ref = 'xitugspwfxkcluxvrdeg'
const good = {
  NEXT_PUBLIC_SUPABASE_URL: `https://${ref}.supabase.co`,
  MOBILE_CURRENT_CLINICAL_PROJECT_REF: ref,
}
describe('complete current clinical runtime target', () => {
  it('is off by default and never infers activation from a staging URL', () => {
    expect(resolveCurrentClinicalRuntime({})).toEqual({ mode: 'legacy' })
    expect(
      resolveCurrentClinicalRuntime({ NEXT_PUBLIC_SUPABASE_URL: good.NEXT_PUBLIC_SUPABASE_URL }),
    ).toEqual({ mode: 'legacy' })
  })
  it('requires exactly the known staging target and normalizes its private storage origin', () => {
    expect(resolveCurrentClinicalRuntime(good)).toEqual({
      mode: 'current',
      storageOrigin: `https://${ref}.supabase.co`,
    })
  })
  it.each([
    'xuxehkhdvjivitduarvb',
    'other-project',
    `${ref},xuxehkhdvjivitduarvb`,
    `${ref},other`,
  ])('refuses invalid explicit selection %s', (selected) => {
    expect(
      resolveCurrentClinicalRuntime({ ...good, MOBILE_CURRENT_CLINICAL_PROJECT_REF: selected }),
    ).toEqual({ mode: 'unavailable' })
  })
  it.each([
    `http://${ref}.supabase.co`,
    `https://xuxehkhdvjivitduarvb.supabase.co`,
    `https://${ref}.supabase.co/path`,
    `https://${ref}.supabase.co?x=1`,
    `https://user:synthetic@${ref}.supabase.co`,
    `https://${ref}.supabase.co:444`,
  ])('never downgrades an explicit current mode with bad origin %s', (origin) => {
    expect(resolveCurrentClinicalRuntime({ ...good, NEXT_PUBLIC_SUPABASE_URL: origin })).toEqual({
      mode: 'unavailable',
    })
  })
})
