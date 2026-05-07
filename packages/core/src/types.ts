/**
 * Tipos puros do domínio MPP.
 * Não dependem de Supabase nem de qualquer infraestrutura.
 */

export type Sex = 'masculino' | 'feminino'

export type ActivityLevel = 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta'

export type WaterIntake = 'pouco' | 'moderado' | 'bastante'

export type HungerLevel = 'pouca' | 'moderada' | 'muita'

export type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao'

export type GoalType = 'BF' | 'IMC'

export type AgentStage =
  | 'coleta_dados'
  | 'recomposicao'
  | 'ganho_massa'
  | 'manutencao'
  | 'analista_diario'
  | 'engajamento'

export interface UserProfile {
  sex: Sex | null
  birthDate: Date | null
  heightCm: number | null
  weightKg: number | null
  bodyFatPercent: number | null
  activityLevel: ActivityLevel | null
  trainingFrequency: number | null
  waterIntake: WaterIntake | null
  hungerLevel: HungerLevel | null
  currentProtocol: Protocol | null
  goalType: GoalType | null
  goalValue: number | null
  deficitLevel: 400 | 500 | 600 | null
  /** Hora de dormir (HH:MM). Usado pra calcular sleep_hours pro critério de
   * Ganho de Massa (≥6h30) e janelas de engajamento. */
  bedTime?: string | null
  /** Hora de acordar (HH:MM). Mesmo uso que bedTime. */
  wakeTime?: string | null
  /** Alimentação estruturada (paciente segue plano vs come improvisado).
   * Critério obrigatório pra Ganho de Massa per doc Notion. */
  foodOrganization?: 'sim' | 'nao' | null
}

export interface UserMetrics {
  age: number | null
  bmr: number | null
  activityFactor: number | null
  lbm: number | null
  imc: number | null
  proteinFactor: number | null
}

export interface ProtocolDecision {
  protocol: Protocol
  canChoose: boolean
  blockers: string[]
  goalType: GoalType
  goalValue: number
}

export interface DailySnapshot {
  date: Date
  caloriesConsumed: number
  caloriesTarget: number | null
  proteinG: number
  proteinTarget: number | null
  exerciseCalories: number
  trainingDone: boolean
  xpEarned: number
  dailyBalance: number // calories_consumed - calories_target - exercise_calories
}

export interface UserProgress {
  xpTotal: number
  level: number
  currentStreak: number
  longestStreak: number
  blocksCompleted: number
  deficitBlock: number
  badgesEarned: string[]
  lastActiveDate: Date | null
}

export interface MealItem {
  foodName: string
  quantityG: number
  kcal: number
  proteinG: number
  carbsG: number
  fatG: number
  source?: string
  confidence?: number
}
