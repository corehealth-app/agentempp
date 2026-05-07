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
  /** Legacy: base genérico antes da tabela MPP. Mantido pra compat. */
  base: number
  /** Legacy: bônus se treinou. Mantido pra compat. */
  training_bonus: number
  /** Legacy: bônus se bateu proteína. Mantido pra compat. */
  protein_bonus: number
  protein_threshold_g: number
  // ── Tabela MPP oficial (doc Notion) ──────────────────────────
  /** Registrar peso do dia (+2 XP). */
  weight_xp?: number
  /** Por refeição registrada (+2 XP cada). */
  meal_xp?: number
  /** Enviar foto do dia (+3 XP). */
  photo_xp?: number
  /** Bater meta de proteína (+4 XP). */
  protein_meta_xp?: number
  /** Bater meta de calorias dentro da janela MPP (+6 XP). */
  calories_meta_xp?: number
  /** Bater meta de passos (+4 XP). NOTA: passos não tracked ainda. */
  steps_meta_xp?: number
  /** Beber meta de água (+3 XP). NOTA: água não tracked ainda. */
  water_meta_xp?: number
  /** Dormir 7-9h (+4 XP). NOTA: sono diário não tracked ainda. */
  sleep_meta_xp?: number
  /** Completar treino planejado (+5 XP). */
  training_xp?: number
  /** Dia Perfeito - todos hábitos do dia (+10 XP). */
  perfect_day_xp?: number
  /** Persistência - voltou após dia/semana ruim (+6 XP). */
  persistence_xp?: number
}

export interface CalcConfig {
  bmr_mifflin: BMRMifflinConfig
  bmr_katch: BMRKatchConfig
  activity_factors: Record<ActivityLevel, number>
  /**
   * Fatores de proteína (g/kg). Cascata por prioridade documentada no Notion:
   *   muita → 1.6 (perfil comportamental difícil — fallback baixo)
   *   training_low → 1.7 (treina < 3x/semana)
   *   optimal_mid_training → 1.9 (pouca fome + perfil ótimo + ≥4x/semana)
   *   optimal_high_training → 2.0 (pouca fome + perfil ótimo + ≥5x/semana)
   *   moderada → 1.8 (default)
   *   pouca → fallback aplicado em resolveProteinFactor (não lookup direto)
   * `pouca` no map é apenas placeholder pra compatibilidade.
   */
  protein_factors: Record<HungerLevel, number> & {
    training_low?: number
    optimal_mid_training?: number
    optimal_high_training?: number
  }
  /** Multiplicador FIXO do BMR pra recomposição (doc MPP: 1.2 — atividade não entra). */
  recomp_bmr_multiplier: number
  /** Multiplicador de superávit pra ganho de massa (doc MPP: 1.05 = superávit leve). */
  ganho_massa_surplus_multiplier: number
  /** Déficit calórico por nível de fome (apenas recomposição). */
  deficit_by_hunger: Record<HungerLevel, number>
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
    // Lookup direto (compatibilidade): muita=baixo, moderada=default
    muita: 1.6,
    moderada: 1.8,
    pouca: 1.8, // default; resolveProteinFactor sobe pra 1.9-2.0 se training alto
    // Fatores condicionais (cascata em resolveProteinFactor)
    training_low: 1.7,
    optimal_mid_training: 1.9,
    optimal_high_training: 2.0,
  },
  recomp_bmr_multiplier: 1.2,
  ganho_massa_surplus_multiplier: 1.05,
  deficit_by_hunger: {
    pouca: 600,
    moderada: 500,
    muita: 400,
  },
  kcal_block: 7700,
  imc_limit_recomp: 25,
  training_min: 3,
  bf_limits: {
    masculino: { recomp: 20, gain: 19 },
    feminino: { recomp: 28, gain: 27 },
  },
  // Escada oficial Notion MPP: [30, 25, 23, 22, 21] com margem mínima 1.
  // Antes faltava o 30 — paciente com IMC 32 ia direto pra 25 (meta agressiva).
  imc_goal_steps: [30, 25, 23, 22, 21],
  bf_goal_rules: [
    { above: 30, subtract: 10 },
    { above: 20, target: 20 },
    { above: 18, target: 18 },
    { above: 15, target: 15 },
    { above: 0, target: 10 },
  ],
  // Levels oficiais MPP (Notion): 0/100/300/600/1000/1500/2200/3000.
  // Antes thresholds divergiam (250/500/2000/3500) → users em 250-299 pulavam
  // pra level 3 quando Notion ainda os mantém em 2.
  levels: [
    { level: 1, name: 'Início', min: 0, max: 99 },
    { level: 2, name: 'Constância', min: 100, max: 299 },
    { level: 3, name: 'Foco', min: 300, max: 599 },
    { level: 4, name: 'Disciplina', min: 600, max: 999 },
    { level: 5, name: 'Performance', min: 1000, max: 1499 },
    { level: 6, name: 'Domínio', min: 1500, max: 2199 },
    { level: 7, name: 'Elite MPP', min: 2200, max: 2999 },
    { level: 8, name: 'Lenda MPP', min: 3000, max: null },
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
