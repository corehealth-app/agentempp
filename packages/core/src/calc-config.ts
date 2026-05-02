/**
 * Configuração editável dos cálculos.
 *
 * Constantes que antes eram hardcoded em nutrition.ts / progress-calc.ts /
 * protocol-router.ts agora vêm daqui. Cada função aceita um CalcConfig
 * opcional; quando omitido usa DEFAULT_CALC_CONFIG (mesmos valores antigos).
 *
 * Em produção o agente/Inngest carrega a config do `global_config` (chaves
 * `calc.*`) e passa pra função. Tests usam DEFAULT_CALC_CONFIG sem mudar
 * nada.
 */
import type { ActivityLevel, HungerLevel, Sex } from './types.js'

export interface BMRMifflinConfig {
  weight_coef: number
  height_coef: number
  age_coef: number
  male_offset: number
  female_offset: number
}

export interface BMRKatchConfig {
  base: number
  lbm_coef: number
}

export interface BFLimits {
  recomp: number
  gain: number
}

export type BFGoalRule =
  | { above: number; subtract: number }
  | { above: number; target: number }

export interface LevelDef {
  level: number
  name: string
  min: number
  max: number | null
}

export type BadgeType = 'streak' | 'blocks' | 'xp'

export interface BadgeDef {
  key: string
  type: BadgeType
  threshold: number
}

export interface XPRules {
  base: number
  training_bonus: number
  protein_bonus: number
  protein_threshold_g: number
}

export interface CalcConfig {
  bmr_mifflin: BMRMifflinConfig
  bmr_katch: BMRKatchConfig
  activity_factors: Record<ActivityLevel, number>
  protein_factors: Record<HungerLevel, number>
  kcal_block: number
  imc_limit_recomp: number
  training_min: number
  bf_limits: Record<Sex, BFLimits>
  imc_goal_steps: number[]
  bf_goal_rules: BFGoalRule[]
  levels: LevelDef[]
  badges: BadgeDef[]
  xp_rules: XPRules
}

export const DEFAULT_CALC_CONFIG: CalcConfig = {
  bmr_mifflin: {
    weight_coef: 10,
    height_coef: 6.25,
    age_coef: 5,
    male_offset: 5,
    female_offset: -161,
  },
  bmr_katch: {
    base: 370,
    lbm_coef: 21.6,
  },
  activity_factors: {
    sedentario: 1.2,
    leve: 1.375,
    moderado: 1.55,
    alto: 1.725,
    atleta: 1.9,
  },
  protein_factors: {
    pouca: 1.6,
    moderada: 1.8,
    muita: 2.0,
  },
  kcal_block: 7700,
  imc_limit_recomp: 25,
  training_min: 3,
  bf_limits: {
    masculino: { recomp: 20, gain: 19 },
    feminino: { recomp: 28, gain: 27 },
  },
  imc_goal_steps: [25, 23, 22, 21],
  bf_goal_rules: [
    { above: 30, subtract: 10 },
    { above: 20, target: 20 },
    { above: 18, target: 18 },
    { above: 15, target: 15 },
    { above: 0, target: 10 },
  ],
  levels: [
    { level: 1, name: 'Início', min: 0, max: 99 },
    { level: 2, name: 'Constância', min: 100, max: 249 },
    { level: 3, name: 'Foco', min: 250, max: 499 },
    { level: 4, name: 'Disciplina', min: 500, max: 999 },
    { level: 5, name: 'Performance', min: 1000, max: 1999 },
    { level: 6, name: 'Domínio', min: 2000, max: 3499 },
    { level: 7, name: 'Elite MPP', min: 3500, max: null },
  ],
  badges: [
    { key: 'Primeira Semana', type: 'streak', threshold: 7 },
    { key: 'Mês de Ferro', type: 'streak', threshold: 30 },
    { key: 'Atleta Real', type: 'streak', threshold: 90 },
    { key: 'Primeiro Bloco', type: 'blocks', threshold: 1 },
    { key: 'XP Master', type: 'xp', threshold: 1000 },
    { key: 'Elite', type: 'xp', threshold: 3500 },
  ],
  xp_rules: {
    base: 10,
    training_bonus: 5,
    protein_bonus: 5,
    protein_threshold_g: 100,
  },
}
