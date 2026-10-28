import { z } from 'zod'
import { DEFAULT_CALC_CONFIG } from './calc-config.js'
import { fixedRecompProteinFactor, resolveProteinBranch } from './nutrition.js'
import { evaluateReevaluationSafety } from './reevaluation-clinical-safety.js'

/** Approved row, not the permissive legacy 1.5 code fallback. */
export const clinicalProteinFactorsSchema = z
  .object({
    muita: z.literal(1.6),
    moderada: z.literal(1.8),
    pouca: z.literal(1.8),
    training_low: z.literal(1.7),
    optimal_mid_training: z.literal(1.9),
    optimal_high_training: z.literal(2),
  })
  .strict()
export const isOfficialClinicalProteinTable = (row: unknown): boolean =>
  clinicalProteinFactorsSchema.safeParse(row).success

const hunger = z.enum(['pouca', 'moderada', 'muita']).nullable()
const sessions = z.number().int().min(0).max(7).nullable()
const schema = z
  .object({
    phase: z.enum(['recomposicao', 'manutencao', 'ganho_massa']),
    profileHunger: hunger,
    profileSessions: sessions,
    answeredHunger: hunger,
    answeredSessions: sessions,
    // Server maps only an actually accepted before->after package to this value.
    confirmedPrincipal: z.enum(['activity', 'phase']).nullable(),
    proteinFactors: z.unknown(),
    recompProteinFactor: z.number().finite().nullable().optional(),
    safety: z.unknown(),
  })
  .strict()

/** n3/n11: ordinary answers remain auditable even when their clinical effects
 * are declined. This pure decision neither writes a profile nor approves a
 * phase/target. The orchestrator binds it to the same snapshot and intent. */
export function evaluateReevaluationProteinInputs(input: unknown) {
  const value = schema.parse(input)
  const safety = evaluateReevaluationSafety(value.safety)
  const config = {
    ...DEFAULT_CALC_CONFIG,
    ...(value.recompProteinFactor === undefined
      ? {}
      : { recomp_protein_g_per_kg: value.recompProteinFactor }),
  }
  const fixed = value.phase === 'recomposicao' && fixedRecompProteinFactor(config) !== null
  const profile = { hunger: value.profileHunger, sessions: value.profileSessions }
  const candidate = {
    hunger: value.answeredHunger ?? value.profileHunger,
    sessions: value.answeredSessions ?? value.profileSessions,
  }
  const branch = (item: typeof profile) =>
    fixed
      ? ('fixed_recomposition' as const)
      : resolveProteinBranch(item.hunger ?? 'moderada', item.sessions)
  const beforeBranch = branch(profile),
    candidateBranch = branch(candidate)
  const branchChanged = beforeBranch !== candidateBranch
  const base = { profile, candidate, beforeBranch, candidateBranch, branchChanged }
  if (!safety.automaticTargetChangeAllowed) return { ...base, status: 'safety' as const }
  if (!branchChanged) return { ...base, profile: candidate, status: 'same_branch' as const }
  if (!isOfficialClinicalProteinTable(value.proteinFactors))
    return { ...base, status: 'unverified_table' as const }
  if (value.confirmedPrincipal === null)
    return { ...base, status: 'confirmation_required' as const }
  return { ...base, profile: candidate, status: 'confirmed' as const }
}
