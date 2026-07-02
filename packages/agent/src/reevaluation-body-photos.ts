export const BODY_PHOTO_REQUIRED_VIEWS = ['front', 'side', 'back'] as const

export type BodyPhotoRequiredView = (typeof BODY_PHOTO_REQUIRED_VIEWS)[number]
export type BodyPhotoView = BodyPhotoRequiredView | 'unknown'

export interface BodyPhotoSignal {
  view: BodyPhotoView
  bfPercentEstimate: number | null
  confidence: number | null
  occurredAt: string | null
  providerMessageId: string | null
  photoCount: number | null
  compositionNotes: string | null
  postureNotes: string | null
}

export interface BodyPhotoState {
  receivedViews: BodyPhotoRequiredView[]
  missingViews: BodyPhotoRequiredView[]
  unknownCount: number
  recentSignals: BodyPhotoSignal[]
  optedOut: boolean
  isComplete: boolean
}

export interface BodyBfAggregate {
  estimate: number
  confidence: number | null
  views: BodyPhotoView[]
}

const VIEW_LABELS: Record<BodyPhotoView, string> = {
  front: 'frente',
  side: 'lado',
  back: 'costas',
  unknown: 'angulo indefinido',
}

export function normalizeBodyPhotoView(value: unknown): BodyPhotoView {
  if (typeof value !== 'string') return 'unknown'
  const v = value.trim().toLowerCase()
  if (v === 'front' || v === 'frente' || v === 'frontal') return 'front'
  if (v === 'side' || v === 'lado' || v === 'lateral' || v === 'perfil') return 'side'
  if (v === 'back' || v === 'costas' || v === 'posterior' || v === 'traseira') return 'back'
  return 'unknown'
}

export function bodyPhotoViewLabel(view: BodyPhotoView): string {
  return VIEW_LABELS[view] ?? VIEW_LABELS.unknown
}

export function formatBodyPhotoViews(views: BodyPhotoView[]): string {
  const labels = views.map(bodyPhotoViewLabel)
  if (labels.length === 0) return 'nenhuma'
  if (labels.length === 1) return labels[0] ?? 'nenhuma'
  if (labels.length === 2) return `${labels[0]} e ${labels[1]}`
  return `${labels.slice(0, -1).join(', ')} e ${labels[labels.length - 1] ?? ''}`
}

export function isBodyPhotoOptOut(text: string | null | undefined): boolean {
  if (!text) return false
  const t = normalizeText(text)
  return (
    /\b(sem|sem\s+as|sem\s+essas)\s+foto(s)?\b/.test(t) ||
    /\b(segue|pode\s+seguir|continua|pode\s+continuar)\s+sem\s+(as\s+)?foto(s)?\b/.test(t) ||
    /\b(segue|pode\s+seguir|continua|pode\s+continuar)\s+com\s+essa(s)?(\s+so)?\b/.test(t) ||
    /\bnao\s+(vou|quero|consigo)\s+(mandar|enviar|tirar)\s+(as\s+)?foto(s)?\b/.test(t) ||
    /\bnao\s+(tenho|tem)\s+(as\s+)?foto(s)?\b/.test(t) ||
    /\bdeixa\s+sem\s+(as\s+)?foto(s)?\b/.test(t)
  )
}

export function deriveBodyPhotoState(
  signals: BodyPhotoSignal[],
  userTexts: Array<string | null | undefined> = [],
): BodyPhotoState {
  const sorted = signals
    .slice()
    .sort((a, b) => timestampMs(a.occurredAt) - timestampMs(b.occurredAt))
  const received = new Set<BodyPhotoRequiredView>()
  let unknownCount = 0
  for (const signal of sorted) {
    const view = normalizeBodyPhotoView(signal.view)
    if (view === 'unknown') {
      unknownCount += 1
    } else {
      received.add(view)
    }
  }
  const receivedViews = BODY_PHOTO_REQUIRED_VIEWS.filter((view) => received.has(view))
  const missingViews = BODY_PHOTO_REQUIRED_VIEWS.filter((view) => !received.has(view))
  const optedOut = userTexts.some(isBodyPhotoOptOut)
  return {
    receivedViews,
    missingViews,
    unknownCount,
    recentSignals: sorted,
    optedOut,
    isComplete: missingViews.length === 0,
  }
}

export function shouldWaitForBodyPhotosBeforeReeval(
  state: BodyPhotoState | null | undefined,
  reevaluationDueRecent: boolean,
): boolean {
  if (!reevaluationDueRecent || !state) return false
  return !state.isComplete && !state.optedOut
}

export function composeReevalBodyPhotoWaitMessage(state: BodyPhotoState): string {
  const missing = formatBodyPhotoViews(state.missingViews)
  const received = formatBodyPhotoViews(state.receivedViews)
  const prefix =
    state.receivedViews.length > 0
      ? `Recebi os dados da reavaliacao e ja tenho foto de ${received}.`
      : 'Recebi os dados da reavaliacao.'
  const unknown =
    state.unknownCount > 0 ? ` Recebi ${state.unknownCount} foto(s), mas sem angulo claro.` : ''
  return `${prefix}${unknown} Pra fechar com fotos, ainda falta ${missing}. Manda ${missing} ou responde "sem fotos" que eu sigo sem elas.`
}

export function formatBodyPhotoContext(state: BodyPhotoState): string {
  const received = formatBodyPhotoViews(state.receivedViews)
  const missing = formatBodyPhotoViews(state.missingViews)
  const unknown =
    state.unknownCount > 0 ? `\n- Fotos com angulo indefinido: ${state.unknownCount}` : ''
  const optOut = state.optedOut
    ? '\n- Paciente ja autorizou seguir sem fotos; nao peca fotos de novo.'
    : ''
  return (
    `### Fotos corporais de reavaliacao\n` +
    `- Fotos ja recebidas: ${received}\n` +
    `- Fotos faltantes: ${missing}${unknown}${optOut}\n` +
    `Regra: nao peca novamente angulos ja recebidos. Se ainda faltar foto, peca somente as faltantes ou aceite "sem fotos". Se frente, lado e costas ja foram recebidas, continue a reavaliacao sem perguntar por fotos.`
  )
}

export function formatBodyPhotoDigest(signals: BodyPhotoSignal[]): string {
  const total = signals.length
  return signals
    .map((signal, idx) => {
      const prefix = total > 1 ? `Foto ${idx + 1}/${total}` : 'Foto'
      const bf =
        signal.bfPercentEstimate == null ? 'BF n/d' : `BF ~${round1(signal.bfPercentEstimate)}%`
      const confidence =
        signal.confidence == null ? '' : `, conf ${Math.round(signal.confidence * 100)}%`
      const notes = compactText(signal.compositionNotes, 90)
      const posture = compactText(signal.postureNotes, 70)
      return `[vision-body] ${prefix}: ${bodyPhotoViewLabel(signal.view)}; ${bf}${confidence}${notes ? `; ${notes}` : ''}${posture ? `; postura: ${posture}` : ''}`
    })
    .join('\n')
}

export function aggregateBodyBfEstimate(signals: BodyPhotoSignal[]): BodyBfAggregate | null {
  const latestByView = new Map<BodyPhotoView, BodyPhotoSignal>()
  const sorted = signals
    .slice()
    .sort((a, b) => timestampMs(a.occurredAt) - timestampMs(b.occurredAt))
  for (const signal of sorted) {
    if (signal.bfPercentEstimate == null) continue
    const view = normalizeBodyPhotoView(signal.view)
    if (view !== 'unknown') latestByView.set(view, { ...signal, view })
  }

  let candidates = Array.from(latestByView.values())
  if (candidates.length === 0) {
    candidates = sorted
      .filter((signal) => signal.bfPercentEstimate != null)
      .slice(-3)
      .map((signal) => ({ ...signal, view: normalizeBodyPhotoView(signal.view) }))
  }
  if (candidates.length === 0) return null

  let weightedSum = 0
  let weightSum = 0
  let confidenceSum = 0
  let confidenceCount = 0
  for (const signal of candidates) {
    const estimate = signal.bfPercentEstimate
    if (estimate == null) continue
    const confidence = clampConfidence(signal.confidence)
    const weight = Math.max(confidence ?? 0.5, 0.1)
    weightedSum += estimate * weight
    weightSum += weight
    if (confidence != null) {
      confidenceSum += confidence
      confidenceCount += 1
    }
  }
  if (weightSum === 0) return null

  const views = Array.from(new Set(candidates.map((signal) => normalizeBodyPhotoView(signal.view))))
  return {
    estimate: round1(weightedSum / weightSum),
    confidence: confidenceCount > 0 ? round2(confidenceSum / confidenceCount) : null,
    views,
  }
}

export function bodyPhotoSignalFromEventProperties(
  properties: unknown,
  occurredAt: string | null = null,
): BodyPhotoSignal | null {
  if (!properties || typeof properties !== 'object') return null
  const p = properties as Record<string, unknown>
  if (p.type !== 'body') return null
  return {
    view: normalizeBodyPhotoView(p.view ?? p.body_view),
    bfPercentEstimate: nullableNumber(p.bf_percent_estimate ?? p.bfPercentEstimate),
    confidence: nullableNumber(p.bf_confidence ?? p.confidence),
    occurredAt,
    providerMessageId: typeof p.provider_message_id === 'string' ? p.provider_message_id : null,
    photoCount: nullableNumber(p.photo_count),
    compositionNotes: typeof p.composition_notes === 'string' ? p.composition_notes : null,
    postureNotes: typeof p.posture_notes === 'string' ? p.posture_notes : null,
  }
}

function normalizeText(text: string): string {
  return text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
}

function timestampMs(value: string | null): number {
  if (!value) return 0
  const ms = new Date(value).getTime()
  return Number.isFinite(ms) ? ms : 0
}

function nullableNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim().length > 0) {
    const n = Number(value)
    return Number.isFinite(n) ? n : null
  }
  return null
}

function clampConfidence(value: number | null): number | null {
  if (value == null || !Number.isFinite(value)) return null
  if (value < 0) return 0
  if (value > 1) return 1
  return value
}

function compactText(value: string | null | undefined, max: number): string {
  if (!value) return ''
  const text = value.replace(/\s+/g, ' ').trim()
  if (text.length <= max) return text
  return `${text.slice(0, max - 1)}...`
}

function round1(value: number): number {
  return Math.round(value * 10) / 10
}

function round2(value: number): number {
  return Math.round(value * 100) / 100
}
