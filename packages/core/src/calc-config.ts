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
  /**
   * Fixed protein factor (g/kg) of recomposição: hunger and training do not
   * enter, and `protein_factors` does not apply to that protocol (see
   * `resolveProteinFactorForProtocol`). Absent = `RECOMP_PROTEIN_G_PER_KG`.
   *
   * Revert switch: an explicit `0` (or JSON `null`) = recomposição follows
   * `protein_factors` again, like the other protocols, and
   * `cadastra_dados_iniciais` hands the view's `protein_factor` back to the
   * model. Without a deploy (up to 60 s of loader cache) — the row does not
   * exist in any migration and `global_config.value` is `jsonb NOT NULL`, so
   * it has to be created with a JSON value; `0` is the recommended one
   * because a SQL NULL (what a client sending JSON null to the
   * `set_global_config` RPC produces, as read from the migrations — never
   * run against a database) is refused by the column:
   *
   *   INSERT INTO public.global_config (key, value, updated_at)
   *   VALUES ('calc.recomp_protein_g_per_kg', '0'::jsonb, now())
   *   ON CONFLICT (key) DO UPDATE
   *     SET value = EXCLUDED.value, updated_at = now();
   *
   * Turning it on again: `DELETE FROM public.global_config WHERE key =
   * 'calc.recomp_protein_g_per_kg';` (the code default is back).
   *
   * Any other row value is read by `fixedRecompProteinFactor`: a number in
   * (0, `RECOMP_PROTEIN_G_PER_KG_SANITY_MAX`] replaces the factor; text, a
   * negative number or anything above the bound is a typing mistake and falls
   * back to `RECOMP_PROTEIN_G_PER_KG` — never silently to the cascade.
   */
  recomp_protein_g_per_kg?: number | null
  /** Multiplicador de superávit pra ganho de massa (doc MPP: 1.05 = superávit leve). */
  ganho_massa_surplus_multiplier: number
  /** Déficit calórico por nível de fome (apenas recomposição). */
  deficit_by_hunger: Record<HungerLevel, number>
  kcal_block: number
  imc_limit_recomp: number
  training_min: number
  /** Horas mínimas de sono pra qualificar pra Ganho de Massa. Doc MPP: 6.5h. */
  sleep_min_hours: number
  bf_limits: Record<Sex, BFLimits>
  imc_goal_steps: number[]
  /**
   * BMI points the first goal drops per step while the BMI is above
   * `imc_limit_recomp` (see `calcIMCGoal`). `null` or `0` = the previous
   * ladder, walking `imc_goal_steps` from the top (30 first): the revert
   * switch, also reachable without a deploy through a `global_config` row
   * `calc.imc_goal_step_points` = null.
   *
   * Any other row value is read by `imcGoalStepPoints`: a number in
   * (0, `IMC_GOAL_STEP_POINTS_SANITY_MAX`] is the step; text (such as "5"), a
   * negative number or anything above the bound is a typing mistake and falls
   * back to `IMC_GOAL_STEP_POINTS` — never silently to the previous ladder.
   */
  imc_goal_step_points: number | null
  bf_goal_rules: BFGoalRule[]
  levels: LevelDef[]
  badges: BadgeDef[]
  xp_rules: XPRules
}

/**
 * Protein of recomposição, in g per kg of body weight.
 *
 * Stated by the client on 2026-04-15 (typed: "fixa de 1,5 g de proteina por
 * quilo de peso pra o protocolo de recomposição") and on 2026-05-15 (typed:
 * "Mantém 1,5 para todos"). Implemented on 2026-10-04 at Eduardo's request;
 * the client's confirmation is pending. Whether "todos" also covers ganho de
 * massa and manutenção was never said, so those keep `protein_factors`.
 * `null` here = the previous behaviour for recomposição too.
 */
export const RECOMP_PROTEIN_G_PER_KG: number | null = 1.5

/**
 * Highest g/kg accepted from the `calc.recomp_protein_g_per_kg` database row.
 * A typing guard, not a clinical limit and not a number the client stated: a
 * row holding 99 used to become a 9900 g target for a 100 kg patient. Above
 * it (or below/equal to 0, other than the explicit switch) the code default
 * is used.
 */
export const RECOMP_PROTEIN_G_PER_KG_SANITY_MAX = 3

/**
 * BMI points of one step of the first goal (rule R3, `calcIMCGoal`).
 *
 * Stated by the client on 2026-01-26 (typed: "caindo de 5 em cinco pontos até
 * chegar a faixa da normalidade") and in his manual 9.4.3.1. Implemented on
 * 2026-10-04 at Eduardo's request; the client's confirmation is pending.
 */
export const IMC_GOAL_STEP_POINTS = 5

/**
 * Highest step accepted from the `calc.imc_goal_step_points` database row. A
 * typing guard, not a clinical limit and not a number the client stated. Above
 * it (or below 0, or not a number) the code default is used; only an explicit
 * `null` or `0` switches the rule off.
 */
export const IMC_GOAL_STEP_POINTS_SANITY_MAX = 20

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
    // Roberto pediu (2026-05-15): flat 1.5 g/kg pra recomposição não estourar
    // a meta calórica. Continua sendo hiperproteica (média BR é 0,8-1,2 g/kg);
    // saturação de síntese muscular fica em ~1.6 — perda marginal vs ganho de
    // adesão. Antes era cascata 1.6-2.0 dependente de fome+treino.
    // Since 2026-10-04 recomposição no longer reads this map (a `global_config`
    // row replaced it with the 1.6–2.0 cascade): see `recomp_protein_g_per_kg`.
    // This map is what ganho de massa, manutenção and a profile without a
    // protocol use.
    muita: 1.5,
    moderada: 1.5,
    pouca: 1.5,
    training_low: 1.5,
    optimal_mid_training: 1.5,
    optimal_high_training: 1.5,
  },
  recomp_bmr_multiplier: 1.2,
  // No migration seeds this key, so the code value is the one at runtime
  // unless someone creates the `global_config` row.
  recomp_protein_g_per_kg: RECOMP_PROTEIN_G_PER_KG,
  ganho_massa_surplus_multiplier: 1.05,
  deficit_by_hunger: {
    pouca: 600,
    moderada: 500,
    muita: 400,
  },
  kcal_block: 7700,
  imc_limit_recomp: 25,
  training_min: 3,
  sleep_min_hours: 6.5,
  bf_limits: {
    masculino: { recomp: 20, gain: 19 },
    feminino: { recomp: 28, gain: 27 },
  },
  // The array mirrors `global_config` (`calc.imc_goal_steps`), which wins at
  // runtime. The 30 came from the previous developer's n8n node (commit
  // 63f2aea, 2026-05-07), not from the client's manual. With
  // `imc_goal_step_points` set, only the steps below `imc_limit_recomp` are
  // used; the whole array is used again when the switch is off.
  imc_goal_steps: [30, 25, 23, 22, 21],
  // Stated by the client on 2026-01-26 (typed: "caindo de 5 em cinco pontos
  // até chegar a faixa da normalidade ... até chegar a 25") and in his manual
  // 9.4.3.1 (35→30, 34→29, 31→26). On 2026-02-07 he typed "perder 10 pontos
  // do imc" once: unresolved conflict. Implemented on 2026-10-04 at Eduardo's
  // request; the client's confirmation is pending. null/0 = previous ladder.
  imc_goal_step_points: IMC_GOAL_STEP_POINTS,
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
