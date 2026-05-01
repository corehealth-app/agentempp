/**
 * Roteamento determinístico de protocolo.
 * Replica a lógica do nó "User Route" do n8n original.
 *
 * Fluxo:
 *   1. Se BF disponível → decide por BF
 *   2. Senão → decide por IMC
 *   3. Treino < 3x/sem é blocker para "ganho_massa"
 *   4. Default sempre é "recomposicao" (mais conservador)
 */
import type { ProtocolDecision, UserMetrics, UserProfile } from './types.js'

const TRAINING_MIN = 3
const IMC_LIMIT_RECOMP = 25

interface BFLimits {
  recomp: number
  gain: number
}

const BF_LIMITS: Record<'masculino' | 'feminino', BFLimits> = {
  masculino: { recomp: 20, gain: 19 },
  feminino: { recomp: 28, gain: 27 },
}

export function calcBFGoal(bf: number): number {
  if (bf > 30) return Math.round(bf - 10)
  if (bf > 20) return 20
  if (bf > 18) return 18
  if (bf > 15) return 15
  return 10
}

export function calcIMCGoal(imc: number): number {
  for (const meta of [25, 23, 22, 21]) {
    if (imc - meta >= 1) return meta
  }
  return 21
}

export function resolveProtocol(profile: UserProfile, metrics: UserMetrics): ProtocolDecision {
  if (!profile.sex) {
    throw new Error('Cannot resolve protocol without sex defined')
  }

  const limits = BF_LIMITS[profile.sex]
  const blockers: string[] = []

  const trainingFreq = profile.trainingFrequency ?? 0
  if (trainingFreq < TRAINING_MIN) {
    blockers.push(
      `musculação insuficiente (atual: ${trainingFreq}x/semana, mínimo: ${TRAINING_MIN}x)`,
    )
  }

  // ----- Decisão por BF (preferencial) -----
  if (profile.bodyFatPercent != null) {
    const bf = profile.bodyFatPercent
    const goalValue = calcBFGoal(bf)

    if (bf >= limits.recomp) {
      return {
        protocol: 'recomposicao',
        canChoose: false,
        blockers: ['gordura corporal acima do limite para ganho de massa'],
        goalType: 'BF',
        goalValue,
      }
    }

    if (bf <= limits.gain && blockers.length === 0) {
      return {
        protocol: 'recomposicao',
        canChoose: true,
        blockers: [],
        goalType: 'BF',
        goalValue,
      }
    }

    return {
      protocol: 'recomposicao',
      canChoose: false,
      blockers,
      goalType: 'BF',
      goalValue,
    }
  }

  // ----- Decisão por IMC (fallback) -----
  if (metrics.imc == null) {
    throw new Error('Cannot resolve protocol without BF or IMC')
  }

  const goalValue = calcIMCGoal(metrics.imc)

  if (metrics.imc >= IMC_LIMIT_RECOMP) {
    return {
      protocol: 'recomposicao',
      canChoose: false,
      blockers: ['IMC acima do limite saudável para ganho de massa'],
      goalType: 'IMC',
      goalValue,
    }
  }

  if (blockers.length === 0) {
    return {
      protocol: 'recomposicao',
      canChoose: true,
      blockers: [],
      goalType: 'IMC',
      goalValue,
    }
  }

  return {
    protocol: 'recomposicao',
    canChoose: false,
    blockers,
    goalType: 'IMC',
    goalValue,
  }
}
