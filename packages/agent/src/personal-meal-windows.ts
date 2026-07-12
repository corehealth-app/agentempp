/**
 * personal-meal-windows.ts (RC7 — adiado da audit 2026-06-20)
 *
 * Calibra a janela de meal_type por paciente, em vez de usar a tabela global
 * canônica (5-10 cafe, 11-14 almoco, 15-17 lanche, 18-22 jantar, 23-4 ceia).
 *
 * Motivação: Roberto janta 17-19h ET (almoço social), fora da tabela canônica.
 * Pipeline classifica 17h como "lanche" e dispara autocorrect lanche→almoco
 * silencioso. Em vez de empurrar uma janela global em todo mundo, aprende do
 * comportamento real do paciente: olha os últimos 30d de meal_logs e calcula
 * o p10/p90 da hora local pra cada meal_type. Com ≥5 amostras, usa janela
 * pessoal; senão, fallback pra tabela global.
 *
 * Onde é chamado:
 *  - tools.ts autocorrect (L990-L1001) — antes de cair na cascata global.
 *
 * Custo: 1 SELECT extra por chamada de registra_refeicao (~150 linhas
 * típicas, simples por user_id + consumed_at >= 30d). Aceitável pro impacto.
 */
import type { ServiceClient } from '@mpp/db'
import { getLocalDateMinusDays, getLocalDateString } from './timezone-utils.js'

export type MealType = 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'

export interface PersonalWindow {
  meal_type: MealType
  p10: number
  p90: number
  sample_count: number
  distinct_day_count: number
}

export interface PersonalMealWindows {
  /** Mapa meal_type → janela pessoal (só pros tipos com >=MIN_SAMPLES). */
  windows: Map<MealType, PersonalWindow>
  /** Quantos logs foram considerados (debug/telemetria). */
  totalLogs: number
  /** Quantidade de linhas de alimento antes de colapsar registros. */
  totalRows?: number
}

export interface MealRegistrationSample {
  meal_type: MealType
  hour: number
  local_date: string
  registration_key: string
}

export interface MealLogWindowRow {
  meal_type: string | null
  consumed_at: string | null
  raw_provider_message_id?: string | null
  food_name?: string | null
}

/** Janelas globais MPP canônicas (mesma tabela do system prompt + autocorrect). */
const GLOBAL_WINDOWS: Record<MealType, { startHour: number; endHour: number }> = {
  cafe: { startHour: 5, endHour: 11 }, // 5h–10h59
  almoco: { startHour: 11, endHour: 15 }, // 11h–14h59
  lanche: { startHour: 15, endHour: 18 }, // 15h–17h59
  jantar: { startHour: 18, endHour: 23 }, // 18h–22h59
  ceia: { startHour: 23, endHour: 5 }, // 23h–4h59 (wrap)
}

/** Mínimo de amostras por meal_type pra ativar janela pessoal. */
export const MIN_SAMPLES_FOR_PERSONAL = 5

/** Janela de lookback em dias (típico ~150 logs/paciente). */
export const LOOKBACK_DAYS = 30

/** Amplitude maxima para considerar uma rotina pessoal confiavel. */
export const MAX_PERSONAL_WINDOW_SPAN_HOURS = 6

/**
 * Hora local (0-23) de um instante UTC, no timezone do paciente.
 * Exposto pra testar independente de Supabase.
 */
export function hourInTimezone(iso: string, tz: string): number {
  const d = new Date(iso)
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  }).formatToParts(d)
  const h = parts.find((p) => p.type === 'hour')?.value ?? '0'
  // Intl.DateTimeFormat em alguns locales/zones devolve '24' à meia-noite.
  const n = Number.parseInt(h, 10)
  return n === 24 ? 0 : n
}

/**
 * Calcula percentil simples (interpolação linear estilo numpy).
 * Para n pequeno (~5-30) é mais que suficiente.
 */
export function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  if (sorted.length === 1) return sorted[0] ?? 0
  const rank = (p / 100) * (sorted.length - 1)
  const lo = Math.floor(rank)
  const hi = Math.ceil(rank)
  const frac = rank - lo
  const low = sorted[lo]
  const high = sorted[hi]
  if (low == null || high == null) return 0
  return low * (1 - frac) + high * frac
}

/**
 * Constrói janelas pessoais a partir de uma lista de logs. Função pura
 * (testável sem Supabase). Lida com wrap noturno (ceia 23h→4h) usando
 * representação cíclica: horas <5 viram h+24 antes do percentil, e a janela
 * resultante volta pro espaço 0-23 se p90 ultrapassa 24.
 */
export function buildPersonalWindowsFromLogs(
  logs: MealRegistrationSample[],
): Map<MealType, PersonalWindow> {
  const grouped = new Map<MealType, MealRegistrationSample[]>()
  for (const log of logs) {
    const arr = grouped.get(log.meal_type) ?? []
    arr.push(log)
    grouped.set(log.meal_type, arr)
  }

  const out = new Map<MealType, PersonalWindow>()
  for (const [meal_type, samples] of grouped) {
    const distinctDays = new Set(samples.map((sample) => sample.local_date)).size
    if (samples.length < MIN_SAMPLES_FOR_PERSONAL || distinctDays < MIN_SAMPLES_FOR_PERSONAL) {
      continue
    }
    const hours = samples.map((sample) => sample.hour)

    // Ceia tem wrap noturno — empurra horas <5 pra >24 antes de percentilar,
    // pra a sequência ficar monotônica (ex: [23, 0, 1, 2, 3] → [23, 24, 25, 26, 27]).
    const normalized = meal_type === 'ceia' ? hours.map((h) => (h < 5 ? h + 24 : h)) : hours
    const p10raw = percentile(normalized, 10)
    const p90raw = percentile(normalized, 90)
    if (p90raw - p10raw > MAX_PERSONAL_WINDOW_SPAN_HOURS) continue
    const p10 = ((Math.round(p10raw) % 24) + 24) % 24
    const p90 = ((Math.round(p90raw) % 24) + 24) % 24
    out.set(meal_type, {
      meal_type,
      p10,
      p90,
      sample_count: hours.length,
      distinct_day_count: distinctDays,
    })
  }
  return out
}

/**
 * meal_logs tem uma linha por alimento. Esta funcao transforma todas as linhas
 * da mesma mensagem/instante em uma unica amostra de refeicao. Grupos com
 * rotulos conflitantes sao descartados para nao aprender de reclassificacao
 * parcial ou dado corrompido.
 */
export function collapseMealRowsToRegistrations(
  rows: MealLogWindowRow[],
  tz: string,
): MealRegistrationSample[] {
  const groups = new Map<string, MealLogWindowRow[]>()
  for (const row of rows) {
    if (!row.consumed_at) continue
    const key = row.raw_provider_message_id
      ? `provider:${row.raw_provider_message_id}`
      : `time:${row.consumed_at}`
    const group = groups.get(key) ?? []
    group.push(row)
    groups.set(key, group)
  }

  const registrations: MealRegistrationSample[] = []
  for (const [registrationKey, group] of groups) {
    const types = new Set(
      group.map((row) => row.meal_type).filter((value): value is string => !!value),
    )
    if (types.size !== 1) continue
    const mealType = Array.from(types)[0]
    if (!mealType) continue
    if (!isMealType(mealType)) continue
    const consumedAt = group[0]?.consumed_at
    if (!consumedAt || !Number.isFinite(new Date(consumedAt).getTime())) continue
    registrations.push({
      meal_type: mealType,
      hour: hourInTimezone(consumedAt, tz),
      local_date: getLocalDateString(tz, new Date(consumedAt)),
      registration_key: registrationKey,
    })
  }
  return registrations
}

/**
 * Lê meal_logs dos últimos 30d e devolve janelas pessoais por meal_type.
 * Filtra meal_types canônicos e logs com consumed_at não-null.
 *
 * O fallback global só vale quando a consulta funciona mas não há amostras
 * suficientes. Erro de leitura é propagado para não classificar por uma fonte
 * diferente sem saber se existe uma rotina pessoal válida.
 */
export async function getPersonalMealWindows(
  supabase: ServiceClient,
  userId: string,
  tz: string,
  referenceTimestamp: Date = new Date(),
): Promise<PersonalMealWindows> {
  const cutoffDate = getLocalDateMinusDays(tz, LOOKBACK_DAYS, referenceTimestamp)
  // Query SIMPLES: user_id + consumed_at >= cutoff (data local convertida em
  // limite frouxo — não precisa offset porque queremos margem). Limit alto
  // pra cobrir ~150 logs típicos sem cap.
  // biome-ignore lint/suspicious/noExplicitAny: ServiceClient sem types estritos aqui
  const { data, error } = await (supabase as any)
    .from('meal_logs')
    .select('meal_type, consumed_at, raw_provider_message_id, food_name')
    .eq('user_id', userId)
    .gte('consumed_at', `${cutoffDate}T00:00:00Z`)
    .not('meal_type', 'is', null)
    .not('consumed_at', 'is', null)
    .limit(500)
  if (error) throw new Error(error.message ?? 'personal meal window lookup failed')
  const rows = (data ?? []) as MealLogWindowRow[]

  const valid = collapseMealRowsToRegistrations(rows, tz)

  return {
    windows: buildPersonalWindowsFromLogs(valid),
    totalLogs: valid.length,
    totalRows: rows.length,
  }
}

function isMealType(s: string): s is MealType {
  return s === 'cafe' || s === 'almoco' || s === 'lanche' || s === 'jantar' || s === 'ceia'
}

/**
 * Resolve o meal_type esperado pra uma hora local, usando janelas pessoais
 * quando disponíveis. Se a hora cair dentro de MÚLTIPLAS janelas pessoais
 * (sobreposição possível: ex: paciente faz lanche 14-16 e almoço 13-15),
 * escolhe a janela mais ESPECÍFICA (menor span); em empate, alfabética
 * estável.
 *
 * Se a hora NÃO cair em nenhuma janela pessoal (paciente tem janelas mas
 * comeu fora do padrão dele), cai pra tabela global.
 *
 * Retorna também uma flag `personal` indicando se a decisão veio de janela
 * pessoal ou global — usado pra telemetria.
 */
export function resolveMealTypeByHour(
  localHour: number,
  personal: PersonalMealWindows,
): { expected: MealType; source: 'personal' | 'global' } {
  const matches: PersonalWindow[] = []
  for (const w of personal.windows.values()) {
    if (hourFallsInWindow(localHour, w.p10, w.p90)) matches.push(w)
  }
  if (matches.length > 0) {
    matches.sort((a, b) => spanOf(a) - spanOf(b) || a.meal_type.localeCompare(b.meal_type))
    const first = matches[0]
    if (first) return { expected: first.meal_type, source: 'personal' }
  }
  return { expected: globalWindowFor(localHour), source: 'global' }
}

function hourFallsInWindow(hour: number, start: number, end: number): boolean {
  if (start <= end) {
    // Janela normal: hour entre start e end inclusive.
    return hour >= start && hour <= end
  }
  // Wrap noturno (ex: ceia 23→4): hour >= start OU hour <= end.
  return hour >= start || hour <= end
}

function spanOf(w: PersonalWindow): number {
  if (w.p10 <= w.p90) return w.p90 - w.p10
  // wrap: 23→4 = 5 horas
  return 24 - w.p10 + w.p90
}

function globalWindowFor(hour: number): MealType {
  if (hour >= GLOBAL_WINDOWS.cafe.startHour && hour < GLOBAL_WINDOWS.cafe.endHour) return 'cafe'
  if (hour >= GLOBAL_WINDOWS.almoco.startHour && hour < GLOBAL_WINDOWS.almoco.endHour)
    return 'almoco'
  if (hour >= GLOBAL_WINDOWS.lanche.startHour && hour < GLOBAL_WINDOWS.lanche.endHour)
    return 'lanche'
  if (hour >= GLOBAL_WINDOWS.jantar.startHour && hour < GLOBAL_WINDOWS.jantar.endHour)
    return 'jantar'
  return 'ceia'
}
