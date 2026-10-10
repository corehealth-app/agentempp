/**
 * Audit 2026-10-10 — the Flow (app Performe AI) writes the workout suggestion
 * in plain language.
 *
 * The report. The owner used build 1.0 (3) on his own iPhone against the
 * staging server of e725096 and said, in his words: "quando ele monta o
 * treino, está muito tecnico os termos usados, precisam ser mais simples para
 * facilitar o entendimento do usuario". The turn, on a TEST account with
 * fictitious data (muscle gain): "Monte um treino para hoje" → "Academia
 * completa" → "5 dias" → "Intermediario" → "Nenhuma limitacao e sem
 * prioridade". The draft stored for it (public.plan_drafts, 2026-10-10
 * 16:44:49Z) and the end of the chat he saw are in
 * fixtures/audit-10-10-flow-workout-reported-draft.json, verbatim: "Plano
 * Push/Pull/Legs modificado…", "Compostos primeiro, isoladores depois",
 * "falha técnica (RPE 8-9)", "progressão linear … 6 reps", "Pegada pronada",
 * "escápulas retraídas", "retração escapular".
 *
 * The cause. `propoe_plano_treino` (the app-only tool) calls the generator it
 * shares with the legacy `gera_treino`; the Flow prompt was the legacy prompt
 * with two sentences swapped, so it told the model to write those very words;
 * the draft was stored as generated and the chat text is rendered from the
 * stored draft.
 *
 * The fix, Flow only, in two layers:
 *  1. a deterministic net (flow-plain-training-language.ts): a CLOSED
 *     vocabulary applied once, inside `propoe_plano_treino`, to the candidate
 *     BEFORE it is assessed and stored. The chat text comes from the stored
 *     draft, so the chat and the Plan tab show the same words through one
 *     hook. Numbers and structure are never read nor written;
 *  2. the request to the generator (training-plan-generator.ts, Flow branches
 *     only): the method rules stay byte for byte, a "COMO ESCREVER" block
 *     closes the prompt and the progression example uses plain words with the
 *     same numbers.
 * The legacy tool, its prompt, its request and what it stores are byte for
 * byte the same: sections B2 and the two WhatsApp locks (unedited).
 *
 * What this file proves and what it does not:
 *  - the fixture has 6 of the 29 exercises and 3 of the 5 days of the
 *    reported draft (all the evidence carries). Sections A and B run the
 *    REAL tool and the REAL entry point on that cut: the stored texts are
 *    exact, but the end of the chat of the WHOLE turn is a close variant
 *    (RC TL-1);
 *  - the model is scripted everywhere: nothing here says how the real model
 *    answers the new request (RC TL-3);
 *  - the owner's two decisions are OFF: no exercise is renamed (RC TL-13) and
 *    the effort grade gets no scale (RC TL-14).
 *
 * The term search of A1/A4/B1 walks the TEXT VALUES of the payload (string
 * leaves and list items), never JSON.stringify, and a term counts only as a
 * whole word (a letter, a digit or "_" next to it is glue): otherwise "reps"
 * would match the KEY "reps_range" and the test could never be green.
 *
 * > RC TL-1 — cenário rascunho de treino do Flow de 2026-10-10 16:44:49Z (conta de teste, 5 dias, 29 exercícios) variante os 23 exercícios, o grupo muscular de 3 exercícios e os dias de terça e quinta, cujo texto o arquivo de evidência não traz NÃO coberta nesta PR (pendência da audit 2026-10-10). O fim do chat só está provado no recorte de 3 dias e 6 exercícios: para o turno relatado inteiro o golden é variante próxima. No plano inteiro o texto simples é mais longo (só o parágrafo de progressão cresce 35 caracteres) e o chat pode terminar em '(O restante está em "Revisar sugestão".)' sem o parágrafo de progressão e sem o último dia; a aba Plano continua com tudo. Só a releitura autorizada do rascunho inteiro, fora desta raia, fecha esta linha.
 * > RC TL-2 — cenário termos "porção clavicular", "cabeça longa do tríceps", "isquiotibiais", "gastrocnêmio", "sóleo", "cadeia posterior" e "Military press" variante a frase exata em que cada um apareceu no rascunho de 2026-10-10 (não está no arquivo de evidência; os seis primeiros são cobertos numa frase de teste, que é variante próxima, inclusive com barra; o sétimo está em RC TL-13) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-3 — cenário sugestão de treino do Flow variante resposta do MODELO REAL ao pedido de linguagem simples (o modelo é roteirizado nos testes; nenhum turno real rodou com o pedido novo) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-4 — cenário termo técnico ou nome em inglês variante FORA do vocabulário fechado (por exemplo "peitoral", "quadríceps", "dorsal", "deltoide", "amplitude", "stress", "escápulas" sem "retraídas", "unilateral" e "unilaterais", "pegada neutra", "cabeça longa" sem o músculo, "Upper back", "Pulldown", "Pullover", "Crossover", "drop set") NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-5 — cenário linha do exercício no chat ("• Hip Thrust com Barra — 4×8-12, descanso 90 s") variante a notação séries×repetições, o "s" de segundos e o rótulo "Progressão:" NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-6 — cenário rascunho de treino gravado ANTES desta mudança (inclusive o de 2026-10-10 16:44:49Z no ambiente de teste) e mensagem do chat já gravada variante texto já armazenado, que não é reescrito NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-7 — cenário campo cujo texto simples passaria do limite (observações, progressão e equipamentos 500; observação do exercício, passos e erros 300; nome 120; foco e grupo muscular 80; repetições e esforço 40; dia 20) variante frases ou campo que ficam como o gerador escreveu, por exemplo o dia "Upper A" NÃO coberta nesta PR (pendência da audit 2026-10-10). No campo do dia, "Upper" e "Lower" nunca são trocadas: "Parte de cima do corpo" tem 22 caracteres, "Parte de baixo do corpo" tem 23 e o limite é 20; um plano com os dias "Upper A" e "Lower A" continua com esses dois rótulos em inglês no chat e na aba Plano.
 * > RC TL-8 — cenário perguntas do Flow ANTES de montar o treino e respostas a dúvidas depois variante texto livre do chat fora do turno da sugestão (inclusive uma pergunta sobre "falha muscular" vinda da descrição do parâmetro compartilhado) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-9 — cenário sugestão de treino para conta em INGLÊS variante pedido ao gerador e vocabulário só em português NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-10 — cenário frase depois da troca variante redação que continua sem ser do dia a dia, porque a rede troca palavras e não reescreve a frase ("Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo)", "Exercício de vários músculos principal para peitoral", "Panturrilha (músculo da panturrilha)") NÃO coberta nesta PR (pendência da audit 2026-10-10). A concordância com a palavra vizinha também não é ajustada: "12 rep" vira "12 repetição", "MMII fortes" vira "Parte de baixo do corpo fortes" e "Treine a PSE 8" vira "Treine o esforço 8" (o "a" era preposição e foi lido como artigo).
 * > RC TL-11 — cenário plano importado de foto ou PDF, texto digitado pela pessoa em "Revisar sugestão" e sugestão de cardápio variante texto que não é sugestão de treino escrita pelo Flow, deixado como está de propósito NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-12 — cenário frase de abertura ou de fecho escrita pelo modelo no turno da sugestão de treino variante termo técnico fora do bloco da sugestão NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-13 — cenário nomes de exercício em inglês vistos pelo dono ("Hip Thrust com Barra", "Stiff Unilateral com Halter", "Leg Press 45°") e "Military press" variante troca do nome pela rede determinística, que entra desligada até o dono aprovar cada nome NÃO coberta nesta PR (pendência da audit 2026-10-10). O nome fica como o gerador escreveu; só o pedido ao modelo pede o nome usado nas academias do Brasil.
 * > RC TL-14 — cenário "Esforço alvo 9" na aba Plano variante explicação da escala da nota ("9 de 10"), que entra desligada até o dono decidir NÃO coberta nesta PR (pendência da audit 2026-10-10). A sigla sai do texto ("RPE 8-9" vira "esforço 8-9"); a nota fica como o gerador escreveu.
 * > RC TL-15 — cenário grafia do vocabulário fechado variante que a regra deixa passar de propósito (colada a letra, número, "_", "@" ou "-"; sigla em minúsculas, como "rpe" e "rir"; a sigla RIR com número dos dois lados, como "Séries de 12 RIR 2"; "PSE" antes de palavra terminada em "a" ou "as"; as divisões em inglês dentro de nome de exercício ou de equipamento; Push, Pull, Legs, Upper, Lower e Core vizinhas de uma palavra da lista fechada de inglês; "falha" fora de "até", "até a", "à", "próximo da", "próximo à", "perto da", "antes da", e depois de "à" quando segue "de", "do", "da", "na", "no" ou "em"; "composto" e "isolador" depois de uma palavra que não anuncia nome, como um verbo, ou "composto" antes de "por", de "de" e de palavra de substância; "escápulas retraídas" depois de outra palavra terminada em "as" ou antes de "e" ou vírgula mais uma palavra terminada em "adas" ou "idas"; trecho de endereço), composto em inglês com vizinha fora da lista, trocado palavra por palavra em texto corrido ("Core Blaster" vira "abdômen Blaster"), frase trocada pela metade ("Combine compostos e isoladores" vira "Combine compostos e exercícios de um músculo só"), e grafia colada a letra ou número de outro alfabeto, que não conta como cola ("Treino de Coreж" vira "Treino de abdômenж") NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-16 — cenário turno relatado ("Nenhuma limitacao e sem prioridade", 2026-10-10 16:44:49Z) variante a resposta do modelo na segunda chamada do turno, os argumentos que ele passou à ferramenta e a data de nascimento da conta de teste, que não foram registrados NÃO coberta nesta PR (pendência da audit 2026-10-10). A mensagem não é um pedido único: o turno faz duas chamadas ao modelo. No golden a segunda resposta é roteirizada nas duas formas possíveis (o modelo resume, e o sistema põe a sugestão gravada entre a abertura e o fecho fixos, que é o fecho que a tela mostrou; ou o modelo copia a sugestão), e os argumentos são reconstruídos da conversa.
 */
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import {
  FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS,
  FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER,
  FLOW_PLAIN_TRAINING_VOCABULARY,
  type FlowPlainTrainingRow,
  projectFlowPlainTrainingDraft,
  projectFlowPlainTrainingText,
} from '../flow-plain-training-language.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage, processMessage } from '../pipeline.js'
import { PLAN_SUGGESTION_TRUNCATED, trainingSuggestionText } from '../plan-suggestion-text.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import type { ToolContext } from '../tools.js'
import { geraTreino, propoePlanoTreino } from '../tools.js'
import { trainingSystemPrompt } from '../training-plan-generator.js'

// ── The report ──────────────────────────────────────────────────────────────
type Row = Record<string, unknown>

interface Exercise {
  name: string
  muscle_group: string
  sets: number
  reps_range: string
  rest_seconds: number
  rpe_target?: string
  notes?: string
  execution_steps?: string[]
  common_mistakes?: string[]
}
interface Day {
  day: string
  focus: string
  duration_min: number
  exercises: Exercise[]
}
interface Plan {
  plan_type: string
  equipment_summary?: string
  weekly_schedule: Day[]
  progression_rule?: string
  notes?: string
}

const REPORT = JSON.parse(
  readFileSync(
    fileURLToPath(new URL('./fixtures/audit-10-10-flow-workout-reported-draft.json', import.meta.url)),
    'utf8',
  ),
) as {
  conversation: Array<{ role: 'user' | 'assistant'; text: string }>
  payload: { equipment_summary: string; notes: string; progression_rule: string; weekly_schedule_days: string[] }
  chat_text_seen_on_screen_excerpt: string
  jargon_the_owner_objected_to_examples: string[]
  tool_arguments_reconstructed: Row
  generator_output_3_day_cut: Plan
  draft_20260930: Plan
}

/** The patient's last line of the reported turn, exactly as typed. */
const REPORTED_PHRASE = 'Nenhuma limitacao e sem prioridade'
/** What the generator answered for the reported turn (the 3-day cut of the evidence). */
const GENERATED = REPORT.generator_output_3_day_cut
const GENERATED_JSON = JSON.stringify(GENERATED)

/** The 15 example terms that are in the evidence's texts; the net covers the first 14. */
const COVERED_TERMS = [
  'Push/Pull/Legs',
  'Push superior',
  'Pull',
  'Legs completo',
  'Core',
  'Compostos primeiro, isoladores depois',
  'falha técnica',
  'RPE 8-9',
  'progressão linear',
  'reps',
  'rep',
  'retração escapular',
  'pegada pronada',
  'escápulas retraídas',
]
/** RC TL-13: stays as generated until the owner approves a name. */
const PENDING_TERM = 'Hip Thrust'
/** The 7 example terms whose sentence the evidence does not carry (RC TL-2, RC TL-13). */
const TERMS_NOT_IN_THE_EVIDENCE = [
  'porção clavicular',
  'cabeça longa do tríceps',
  'isquiotibiais',
  'gastrocnêmio',
  'sóleo',
  'cadeia posterior',
  'Military press',
]

// ── What the Plan tab and the chat must show (S1, S2) ───────────────────────
const PLAIN_NOTES =
  'Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo), Quinta (Ombros+abdômen), Sexta (pernas posterior). Exercícios de vários músculos primeiro, exercícios de um músculo só depois. 10-20 séries/músculo/semana. Descanso 60-120s. Treino até próximo da última repetição bem feita (esforço 8-9). Aqueça sempre: 5min cardio leve + séries progressivas. Hidrate-se. Durma 7-9h. Qualquer dor articular, pare e reavalie técnica.'
const PLAIN_PROGRESSION =
  'Como intermediário, use evolução passo a passo: inicie cada exercício com 6 repetições. A cada treino, adicione 1 repetição mantendo o peso. Quando atingir 12 repetições com técnica perfeita, aumente a carga e volte para 6 repetições. Registre peso e repetições a cada sessão.'
/** The four lines the screen ended on: they do not change (the names wait for the owner). */
const SCREEN_LAST_LINES =
  '• Cadeira Abdutora — 3×12-15, descanso 60 s\n• Stiff Unilateral com Halter — 3×10-12, descanso 60 s\n• Hip Thrust com Barra — 4×8-12, descanso 90 s\n• Panturrilha Sentado — 3×12-15, descanso 60 s'
const PLAIN_CHAT_END = `${SCREEN_LAST_LINES}\n\nProgressão: ${PLAIN_PROGRESSION}`

/** The fixed text around a suggestion (ensureSuggestionShown). */
const OPENING = 'Sua sugestão está pronta:'
const CLOSING =
  'É um rascunho: toque em "Revisar sugestão" para conferir, ajustar e confirmar. Ele só vale depois que você confirmar.'

/** The block the Flow prompt ends with, written here by hand (not imported). */
const HOW_TO_WRITE = `COMO ESCREVER (obrigatório; vale para todo texto do JSON: notes, progression_rule, day, focus, name, muscle_group, notes do exercício, execution_steps e common_mistakes):
As regras acima são para VOCÊ montar o plano. Quem vai ler nunca treinou. Escreva em português simples, do dia a dia, como quem explica a um amigo.
- Sem gíria de academia, sem sigla e sem palavra em inglês quando existe palavra comum em português.
- Não escreva: RPE, reps, rep, Push, Pull, Legs, Upper, Lower, Full Body, Core, MMII, compostos, isoladores, falha, progressão linear, pegada pronada, pegada supinada, retração escapular, escápulas, cadeia posterior, isquiotibiais, gastrocnêmio, sóleo, porção clavicular, cabeça longa.
- Escreva: "repetições"; "exercícios de vários músculos" e "exercícios de um músculo só"; "até a última repetição bem feita"; "evolução passo a passo"; "pegada por cima" ou "pegada por baixo"; "ombros para trás"; "parte de trás da coxa"; "panturrilha"; "parte de cima do peito"; "parte de trás do braço"; "abdômen".
- Foco do dia em palavras comuns, como "Peito e tríceps", "Costas e bíceps", "Pernas", "Corpo inteiro". Não mude quais músculos entram em cada dia.
- Nome de exercício: use o nome em português que as academias do Brasil usam. Não invente nome nem traduza palavra por palavra; se a academia só usa o nome em inglês, mantenha-o.
- Esforço: não escreva a sigla. No texto, escreva "esforço" e a nota, como "esforço 8-9". Em rpe_target, escreva só a nota.
- Passos e erros comuns: frases curtas que digam o que fazer com o corpo.
- Os números não mudam: séries, repetições, descanso, minutos e dias continuam os das regras acima.`

/** sha256 of the legacy training prompt, as pinned in pipeline-mobile-flow-runtime.test.ts. */
const LEGACY_TRAINING_PROMPT_SHA256 = '19bb8a14a93e85d499497c8cb7a0e9c25ce12bab11b7d03dcd36ba4d45f84f5c'

// ── The account (rehearsal notes of 2026-10-10, test account 2) ─────────────
/** 13:44 in São Paulo: the instant the draft was stored (the turn's own instant was not recorded). */
const NOW = new Date('2026-10-10T16:44:49.000Z')
const USER_ID = 'qa-pa2'
const TURN_ID = 'mobile_flow/qa-pa2/workout-plain-language'
const MODEL = 'anthropic/claude-sonnet-4.6'
const GENERATOR_MODEL = 'anthropic/claude-sonnet-4.5'

const USER: Row = {
  id: USER_ID,
  // The fictitious name of the test account (it carries the surname on purpose).
  name: 'Teste Menescal',
  summary: null,
  last_active_at: null,
  country: 'BR',
  country_confirmed: true,
  country_detected_from_wpp: null,
  locale: 'pt-BR',
  metadata: null,
  timezone: 'America/Sao_Paulo',
}

const PROFILE: Row = {
  sex: 'masculino',
  // Not recorded (RC TL-16).
  birth_date: '2000-01-01',
  height_cm: 180,
  weight_kg: 75,
  body_fat_percent: 15,
  activity_level: 'moderado',
  training_frequency: 5,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}

const DAY: Row = {
  date: '2026-10-10',
  calories_target: 2843,
  protein_target: '135.00',
  calories_consumed: 0,
  protein_g: '0.00',
  carbs_g: '0.00',
  fat_g: '0.00',
  exercise_calories: 0,
  water_consumed_ml: 0,
  daily_balance: 0,
  deficit_accumulated: 0,
  day_status: null,
  day_closed: false,
  gap_reminder_sent_at: null,
}

const PROGRESS: Row = {
  current_streak: 0,
  longest_streak: 0,
  xp_total: 0,
  level: 1,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

/** The 8 lines said before the reported phrase, one every 30 s. */
const HISTORY: Row[] = REPORT.conversation.slice(0, -1).map((line, index) => ({
  direction: line.role === 'user' ? 'in' : 'out',
  content: line.text,
  content_type: 'text',
  created_at: new Date(NOW.getTime() - (8 - index) * 30_000).toISOString(),
  provider_message_id: `mobile_flow/qa-pa2/h${index}`,
}))

// ── Harness (the one of audit-10-05, plus the history and a stored draft) ───
interface ChatStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
  /** The model's whole reply, written around the suggestion the tool returned. */
  replyFrom?: (suggestion: string) => string
}

interface Fixture {
  channel?: 'flow' | 'whatsapp'
  chat?: ChatStep[]
  /** What the generator answers (the JSON text). */
  generator?: string
  history?: Row[]
  /** plan_drafts rows by request_key (a draft this very turn already stored). */
  drafts?: Record<string, Row>
}

interface GeneratorCall {
  keys: string[]
  model: unknown
  systemPrompt: string
  message: string
  maxTokens: unknown
  requestTimeoutMs: unknown
  maxRetries: unknown
  temperature: unknown
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  rpcs: Array<{ name: string; params: Row }>
  chatCalls: number
  generatorCalls: GeneratorCall[]
}

function harness(fixture: Fixture = {}): Harness {
  const provider = fixture.channel === 'whatsapp' ? 'whatsapp' : 'mobile_flow'
  const chat = fixture.chat ?? [{ content: 'Resposta do modelo.' }]
  const inserts: Harness['inserts'] = []
  const rpcs: Harness['rpcs'] = []
  const state: Harness = { deps: {} as PipelineDeps, inserts, rpcs, chatCalls: 0, generatorCalls: [] }
  const turnRow: Row = {
    id: 'message-turn-0001',
    direction: 'in',
    content: REPORTED_PHRASE,
    content_type: 'text',
    created_at: NOW.toISOString(),
    provider,
    provider_message_id: TURN_ID,
  }

  interface Read {
    table: string
    columns: string
    filters: Row
    within: Record<string, unknown[]>
    limit: number | null
  }
  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return USER
      case 'user_profiles':
        return PROFILE
      case 'user_progress':
        return PROGRESS
      case 'messages': {
        if (read.filters.provider != null && read.filters.provider !== provider) return []
        if (read.filters.provider_message_id != null) return [turnRow]
        const rows: Row[] = [
          ...(fixture.history ?? []).map((row): Row => ({ ...row, provider })),
          turnRow,
        ].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (read.filters.date !== '2026-10-10') return null
        if (read.columns.trim() === '*') return DAY
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), DAY[key.trim()] ?? null]),
        )
      }
      case 'plan_drafts': {
        const key = read.filters.request_key
        return typeof key === 'string' ? (fixture.drafts?.[key] ?? null) : []
      }
      case 'global_config':
        if (read.filters.key === 'router.haiku_enabled') return { value: false }
        return []
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'ganho_massa',
          model: MODEL,
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 2,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        return []
    }
  }

  const supabase = {
    from(table: string) {
      const read: Read = { table, columns: '', filters: {}, within: {}, limit: null }
      const result = () => ({ data: rowsFor(read), error: null })
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<{ data: unknown; error: null }> &
        Record<string, unknown>
      for (const method of [
        'neq',
        'gte',
        'lte',
        'lt',
        'gt',
        'is',
        'like',
        'ilike',
        'or',
        'not',
        'order',
        'update',
        'upsert',
        'delete',
      ]) {
        chain[method] = () => chain
      }
      chain.select = (columns?: string) => {
        if (typeof columns === 'string') read.columns = columns
        return chain
      }
      chain.eq = (key: string, value: unknown) => {
        read.filters[key] = value
        return chain
      }
      chain.filter = (key: string, _operator: string, value: unknown) => {
        read.filters[key] = value
        return chain
      }
      chain.in = (key: string, values: unknown[]) => {
        read.within[key] = values
        return chain
      }
      chain.limit = (count: number) => {
        read.limit = count
        return chain
      }
      chain.insert = (row: Row) => {
        inserts.push({ table, row })
        return chain
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    rpc: async (name: string, params: Row = {}) => {
      rpcs.push({ name, params })
      if (name === 'list_mobile_routine_items') {
        return { data: { local_date: '2026-10-10', items: [] }, error: null }
      }
      if (name === 'create_plan_draft_atomic') {
        return { data: { id: 'draft-0001', status: params.p_status, inserted: true }, error: null }
      }
      if (name === 'save_training_plan_atomic') {
        return { data: { plan_id: 'plan-0001', inserted: true }, error: null }
      }
      return { data: name === 'match_method_chunks' ? [] : USER_ID, error: null }
    },
  } as unknown as PipelineDeps['supabase']

  /** The suggestion text of the newest tool result in the messages of a call. */
  const suggestionIn = (messages: Array<{ role: string; content: unknown }>): string => {
    const toolMessage = [...messages]
      .reverse()
      .find((message) => message.role === 'tool' && /"sugestao"/.test(String(message.content)))
    return (
      (JSON.parse(String(toolMessage?.content ?? '{}')) as { sugestao?: string }).sugestao ?? ''
    )
  }

  const llm = {
    complete: async (input: {
      model?: unknown
      systemPrompt?: unknown
      messages: Array<{ role: string; content: unknown }>
      metadata?: Record<string, string>
      maxTokens?: unknown
      requestTimeoutMs?: unknown
      maxRetries?: unknown
      temperature?: unknown
    }) => {
      const stage = input.metadata?.Stage
      if (stage === 'diet-generator' || stage === 'training-generator') {
        state.generatorCalls.push({
          keys: Object.keys(input).sort(),
          model: input.model,
          systemPrompt: String(input.systemPrompt),
          message: String(input.messages[0]?.content),
          maxTokens: input.maxTokens,
          requestTimeoutMs: input.requestTimeoutMs,
          maxRetries: input.maxRetries,
          temperature: input.temperature,
        })
        return {
          content: fixture.generator ?? '',
          toolCalls: [],
          model: GENERATOR_MODEL,
          finishReason: 'stop',
          promptTokens: 900,
          completionTokens: 2600,
          costUsd: 0.0417,
        }
      }
      const step = chat[Math.min(state.chatCalls, chat.length - 1)] ?? {}
      state.chatCalls += 1
      return {
        content: step.replyFrom ? step.replyFrom(suggestionIn(input.messages)) : (step.content ?? ''),
        toolCalls: step.toolCalls ?? [],
        model: MODEL,
        finishReason: 'stop',
        promptTokens: 7400,
        completionTokens: 60,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
        costUsd: 0.0098,
      }
    },
  } as unknown as PipelineDeps['llm']

  state.deps = { supabase, llm }
  return state
}

function flow(h: Harness, text: string = REPORTED_PHRASE) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: NOW,
  })
}

function whatsapp(h: Harness, text: string) {
  return processMessage(h.deps, {
    from: '5511999999999',
    providerMessageId: TURN_ID,
    text,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

/** The app-only tool, run directly with the Flow context the pipeline hands it. */
async function propose(generator: string | Plan, args: Row = REPORT.tool_arguments_reconstructed) {
  const h = harness({ generator: typeof generator === 'string' ? generator : JSON.stringify(generator) })
  const ctx = {
    supabase: h.deps.supabase,
    userId: USER_ID,
    userWpp: '',
    llm: h.deps.llm,
    providerMessageId: TURN_ID,
    referenceTimestamp: NOW,
    assistantIdentity: 'flow',
  } as unknown as ToolContext
  const result = (await propoePlanoTreino.execute(args as never, ctx)) as Row
  return { h, result, stored: storedDrafts(h) }
}

function storedDrafts(h: Harness): Row[] {
  return h.rpcs.filter((call) => call.name === 'create_plan_draft_atomic').map((call) => call.params)
}

function events(h: Harness, name: string): Row[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events' && entry.row.event === name)
    .map((entry) => entry.row)
}

// ── Reading a payload ───────────────────────────────────────────────────────
/** Every TEXT VALUE of a payload (string leaves and list items); never a key. */
function textValues(value: unknown): string[] {
  if (typeof value === 'string') return [value]
  if (Array.isArray(value)) return value.flatMap(textValues)
  if (value && typeof value === 'object') return Object.values(value).flatMap(textValues)
  return []
}

/** A term as a whole word: a letter, a digit or "_" next to it is glue. */
function carriers(payload: unknown, term: string): string[] {
  const escaped = term.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')
  const pattern = new RegExp(`(?<![\\p{L}\\p{N}_])${escaped}(?![\\p{L}\\p{N}_])`, 'iu')
  return textValues(payload).filter((value) => pattern.test(value))
}

const digitGroups = (text: string) => text.match(/\d+/g) ?? []

/** Every text field of a plan, by its path, in a fixed order. */
function textFields(plan: Plan): Array<[string, string]> {
  const out: Array<[string, string]> = []
  const push = (path: string, value: unknown) => {
    if (typeof value === 'string') out.push([path, value])
    else if (Array.isArray(value)) {
      for (const [index, entry] of value.entries()) push(`${path}/${index}`, entry)
    }
  }
  push('notes', plan.notes)
  push('progression_rule', plan.progression_rule)
  push('equipment_summary', plan.equipment_summary)
  plan.weekly_schedule.forEach((day, d) => {
    push(`${d}/day`, day.day)
    push(`${d}/focus`, day.focus)
    day.exercises.forEach((exercise, e) => {
      for (const key of [
        'name',
        'muscle_group',
        'reps_range',
        'rpe_target',
        'notes',
        'execution_steps',
        'common_mistakes',
      ] as const) {
        push(`${d}/${e}/${key}`, exercise[key])
      }
    })
  })
  return out
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

// ── A. The app-only tool, on the reported generator answer ──────────────────
describe('audit 2026-10-10 Flow workout — the stored draft of the reported turn (3-day cut)', () => {
  it('A0 the fixture is the reported screen: its chat text ends exactly on what the owner saw', () => {
    expect(REPORT.conversation).toHaveLength(9)
    expect(REPORT.conversation.at(-1)).toEqual({ role: 'user', text: REPORTED_PHRASE })
    expect(REPORT.jargon_the_owner_objected_to_examples).toEqual([
      ...COVERED_TERMS,
      ...TERMS_NOT_IN_THE_EVIDENCE.slice(0, 6),
      'Military press',
      PENDING_TERM,
    ])
    expect(GENERATED.notes).toBe(REPORT.payload.notes)
    expect(GENERATED.progression_rule).toBe(REPORT.payload.progression_rule)
    // 6 of the 29 exercises, 3 of the 5 days: all the evidence carries.
    expect(GENERATED.weekly_schedule.map((day) => `${day.day} — ${day.focus} (${day.duration_min} min)`)).toEqual([
      REPORT.payload.weekly_schedule_days[0],
      REPORT.payload.weekly_schedule_days[2],
      REPORT.payload.weekly_schedule_days[4],
    ])
    expect(GENERATED.weekly_schedule.flatMap((day) => day.exercises)).toHaveLength(6)
    // The renderer on the generated cut, plus the fixed closing, ends on the screen's text.
    expect(
      `${trainingSuggestionText(GENERATED)}\n\n${CLOSING}`.endsWith(REPORT.chat_text_seen_on_screen_excerpt),
    ).toBe(true)
    expect(REPORT.chat_text_seen_on_screen_excerpt.startsWith(SCREEN_LAST_LINES)).toBe(true)
  })

  it('A1 the stored draft of the reported turn carries none of the 14 reported terms the net covers', async () => {
    const { stored } = await propose(GENERATED_JSON)

    // Not vacuous: each of the 15 terms is in the text values of the generator's answer…
    for (const term of [...COVERED_TERMS, PENDING_TERM]) {
      expect(carriers(GENERATED, term), `generated: ${term}`).not.toEqual([])
    }
    // …and the 7 others are not in the evidence at all (RC TL-2).
    for (const term of TERMS_NOT_IN_THE_EVIDENCE) expect(carriers(GENERATED, term)).toEqual([])

    expect(stored).toHaveLength(1)
    const payload = stored[0]?.p_payload
    for (const term of COVERED_TERMS) {
      expect(carriers(payload, term), `stored: ${term}`).toEqual([])
    }
  })

  it('A2 every stored text field is the exact plain sentence', async () => {
    const { stored } = await propose(GENERATED_JSON)
    const payload = stored[0]?.p_payload as Plan
    const [monday, wednesday, friday] = payload.weekly_schedule
    const bench = monday?.exercises[0]
    const press = wednesday?.exercises[0]
    const thrust = friday?.exercises[2]

    expect(payload.notes).toBe(PLAIN_NOTES)
    expect(GENERATED.notes).toHaveLength(414)
    expect(payload.notes).toHaveLength(487)
    expect(payload.progression_rule).toBe(PLAIN_PROGRESSION)
    expect(GENERATED.progression_rule).toHaveLength(241)
    expect(payload.progression_rule).toHaveLength(276)

    expect(bench?.notes).toBe(
      'Exercício de vários músculos principal para peitoral. Pegada na largura dos ombros.',
    )
    expect(press?.notes).toBe('Exercício de vários músculos com carga alta, menor stress lombar.')
    expect(thrust?.notes).toBe('Exercício de um músculo só específico para glúteos.')
    expect(bench?.execution_steps).toEqual([
      'Deite no banco, pés firmes no chão',
      'Pegada por cima, mãos alinhadas com linha dos mamilos',
      'Desça a barra controlada até tocar o peito',
      'Empurre explosivo mantendo ombros para trás',
    ])
    expect(bench?.common_mistakes).toEqual([
      'Tirar os pés do chão',
      'Barra descer muito alta (clavícula)',
      'Perder postura de ombros para trás',
    ])

    // As generated: the names (RC TL-13), the days, the focus, the muscle
    // groups, the equipment and every text the vocabulary has no row for.
    expect(payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name))).toEqual([
      'Supino Reto com Barra',
      'Leg Press 45°',
      'Cadeira Abdutora',
      'Stiff Unilateral com Halter',
      'Hip Thrust com Barra',
      'Panturrilha Sentado',
    ])
    expect(payload.weekly_schedule.map((day) => [day.day, day.focus])).toEqual([
      ['Segunda', 'Peito e Tríceps'],
      ['Quarta', 'Pernas Completo'],
      ['Sexta', 'Pernas Posterior e Glúteos'],
    ])
    expect(
      payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.muscle_group)),
    ).toEqual(['Peitoral', 'Quadríceps/Glúteos', '', '', 'Glúteos', ''])
    expect(payload.equipment_summary).toBe(REPORT.payload.equipment_summary)
    expect(press?.execution_steps).toEqual(GENERATED.weekly_schedule[1]?.exercises[0]?.execution_steps)
    expect(press?.common_mistakes).toEqual(GENERATED.weekly_schedule[1]?.exercises[0]?.common_mistakes)
    expect(thrust?.execution_steps).toEqual(GENERATED.weekly_schedule[2]?.exercises[2]?.execution_steps)
    expect(thrust?.common_mistakes).toEqual(GENERATED.weekly_schedule[2]?.exercises[2]?.common_mistakes)
  })

  it('A3 rpe_target keeps its shape and its value (lock; the owner\'s decision D1 is off)', async () => {
    const { stored } = await propose(GENERATED_JSON)
    const payload = stored[0]?.p_payload as Plan
    const grades = payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.rpe_target))
    // The three whole exercises carry "9"; the three known only by their chat line carry none.
    expect(grades).toEqual(['9', '9', undefined, undefined, '9', undefined])
    for (const grade of grades.filter((entry) => entry !== undefined)) expect(typeof grade).toBe('string')
  })

  it('A4 the chat shows the same plain text as the draft (3-day cut; the whole plan may be cut: RC TL-1)', async () => {
    const { result, stored } = await propose(GENERATED_JSON)
    const suggestion = String(result.sugestao)

    expect(result).toMatchObject({ success: true, draft_id: 'draft-0001', domain: 'training', status: 'ready_for_review' })
    expect(suggestion).toBe(trainingSuggestionText(stored[0]?.p_payload))
    expect(suggestion.endsWith(PLAIN_CHAT_END)).toBe(true)
    expect(suggestion).not.toContain(PLAN_SUGGESTION_TRUNCATED)
    expect(trainingSuggestionText(GENERATED)).toHaveLength(650)
    expect(suggestion).toHaveLength(685)
    for (const term of COVERED_TERMS) expect(carriers([suggestion], term), term).toEqual([])
    // RC TL-5: the line of an exercise keeps its notation.
    expect(suggestion).toContain('• Hip Thrust com Barra — 4×8-12, descanso 90 s')
  })

  it('A5 numbers and structure are the generator\'s (lock)', async () => {
    const { stored } = await propose(GENERATED_JSON)
    const payload = stored[0]?.p_payload as Plan

    expect(stored[0]).toMatchObject({
      p_user_id: USER_ID,
      p_domain: 'training',
      p_origin: 'flow_generated',
      p_status: 'ready_for_review',
      p_uncertain_fields: [],
      p_request_key: `${TURN_ID}:propoe_plano_treino`,
      p_origin_detail: { method: 'training_plan_generator', identity: 'flow' },
    })
    expect(Object.keys(payload).sort()).toEqual([
      'equipment_summary',
      'notes',
      'plan_type',
      'progression_rule',
      'weekly_schedule',
    ])
    expect(payload.plan_type).toBe(GENERATED.plan_type)
    expect(payload.weekly_schedule).toHaveLength(GENERATED.weekly_schedule.length)
    payload.weekly_schedule.forEach((day, d) => {
      const generatedDay = GENERATED.weekly_schedule[d] as Day
      expect(Object.keys(day).sort()).toEqual(Object.keys(generatedDay).sort())
      expect(day.day).toBe(generatedDay.day)
      expect(day.duration_min).toBe(generatedDay.duration_min)
      expect(day.exercises).toHaveLength(generatedDay.exercises.length)
      day.exercises.forEach((exercise, e) => {
        const generated = generatedDay.exercises[e] as Exercise
        expect(Object.keys(exercise).sort()).toEqual(Object.keys(generated).sort())
        expect(exercise.sets).toBe(generated.sets)
        expect(exercise.reps_range).toBe(generated.reps_range)
        expect(exercise.rest_seconds).toBe(generated.rest_seconds)
        expect(exercise.rpe_target).toBe(generated.rpe_target)
        expect(exercise.execution_steps?.length).toBe(generated.execution_steps?.length)
        expect(exercise.common_mistakes?.length).toBe(generated.common_mistakes?.length)
      })
    })
    // In EVERY text field the digit groups are the generated ones, in the same order.
    const generatedFields = textFields({ ...GENERATED, equipment_summary: REPORT.payload.equipment_summary })
    const storedFields = textFields(payload)
    expect(storedFields.map(([path]) => path)).toEqual(generatedFields.map(([path]) => path))
    storedFields.forEach(([path, text], index) => {
      expect(digitGroups(text), path).toEqual(digitGroups(generatedFields[index]?.[1] ?? ''))
    })
  })

  it('A6 a generator answer without progression_rule gets the default in plain words', async () => {
    const { progression_rule: _dropped, ...withoutRule } = GENERATED
    const { result, stored } = await propose(withoutRule as Plan)

    expect((stored[0]?.p_payload as Plan).progression_rule).toBe(
      'Adicione 1 repetição por treino. Bateu 12 repetições com técnica → aumenta peso, volta pra 6.',
    )
    expect(String(result.sugestao).endsWith(
      'Progressão: Adicione 1 repetição por treino. Bateu 12 repetições com técnica → aumenta peso, volta pra 6.',
    )).toBe(true)
  })

  it('A7 the event of the proposal counts what the net did, in numbers only', async () => {
    const { h } = await propose(GENERATED_JSON)
    const proposed = events(h, 'training.plan_proposed')

    expect(proposed).toHaveLength(1)
    expect(proposed[0]?.properties).toEqual({
      draft_id: 'draft-0001',
      plan_type: 'split',
      days_per_week: 5,
      location: 'academia_completa',
      // notes 10, progression_rule 6, three exercise notes, two steps, one mistake.
      plain_terms_replaced: 22,
      plain_sentences_kept: 0,
      plain_fields_kept: 0,
    })
  })
})

// ── B. The exact turn through the real entry point ──────────────────────────
describe('audit 2026-10-10 Flow workout — the reported turn through processAuthenticatedMessage (3-day cut)', () => {
  const TOOL_CALL = {
    id: 'call-1',
    name: 'propoe_plano_treino',
    arguments: JSON.stringify(REPORT.tool_arguments_reconstructed),
  }
  /** A summary of its own: the model did not reproduce the suggestion (RC TL-16). */
  const MODEL_SUMMARY =
    'Pronto! Montei um treino de 5 dias na divisão Push/Pull/Legs, com RPE 8-9 e 6 a 12 reps por série.'

  it('B1 "Nenhuma limitacao e sem prioridade": the chat is the plain stored draft between the fixed opening and closing', async () => {
    const h = harness({
      history: HISTORY,
      chat: [{ toolCalls: [TOOL_CALL] }, { content: MODEL_SUMMARY }],
      generator: GENERATED_JSON,
    })
    const output = await flow(h)

    // Not a single request (the words are outside the closed list): two model calls.
    expect(h.chatCalls).toBe(2)
    expect(h.generatorCalls).toHaveLength(1)
    const stored = storedDrafts(h)
    expect(stored).toHaveLength(1)
    expect(stored[0]).toMatchObject({
      p_domain: 'training',
      p_status: 'ready_for_review',
      p_request_key: `${TURN_ID}:propoe_plano_treino`,
      p_source_message_id: 'message-turn-0001',
    })
    expect((stored[0]?.p_payload as Plan).notes).toBe(PLAIN_NOTES)

    const suggestion = trainingSuggestionText(stored[0]?.p_payload)
    expect(output.text).toBe(`${OPENING}\n\n${suggestion}\n\n${CLOSING}`)
    expect(output.text.endsWith(`${PLAIN_CHAT_END}\n\n${CLOSING}`)).toBe(true)
    for (const term of COVERED_TERMS) expect(carriers([output.text], term), term).toEqual([])
    expect(output.toolCalls).toHaveLength(1)
    expect(output.toolCalls[0]).toMatchObject({
      name: 'propoe_plano_treino',
      result: { success: true, draft_id: 'draft-0001', domain: 'training', sugestao: suggestion },
    })
  })

  it('B1b the same turn when the model copies the suggestion word for word: the copied text is the plain one', async () => {
    const h = harness({
      history: HISTORY,
      chat: [
        { toolCalls: [TOOL_CALL] },
        {
          replyFrom: (suggestion) =>
            `Sua sugestão está pronta!\n\n${suggestion}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.`,
        },
      ],
      generator: GENERATED_JSON,
    })
    const output = await flow(h)

    expect(h.chatCalls).toBe(2)
    const suggestion = trainingSuggestionText(storedDrafts(h)[0]?.p_payload)
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${suggestion}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.`,
    )
    expect(output.text).toContain(PLAIN_CHAT_END)
    for (const term of COVERED_TERMS) expect(carriers([output.text], term), term).toEqual([])
  })

  it('B2 legacy: gera_treino keeps its request and stores the generated words (lock)', async () => {
    const h = harness({ generator: GENERATED_JSON })
    const ctx = { supabase: h.deps.supabase, userId: USER_ID, userWpp: '', llm: h.deps.llm } as unknown as ToolContext
    const result = (await geraTreino.execute(
      geraTreino.parameters.parse(REPORT.tool_arguments_reconstructed) as never,
      ctx,
    )) as Row

    // The legacy request: prompt, limit and message as released.
    expect(h.generatorCalls).toHaveLength(1)
    const call = h.generatorCalls[0] as GeneratorCall
    expect(call.systemPrompt).toBe(trainingSystemPrompt('legacy'))
    expect(createHash('sha256').update(call.systemPrompt).digest('hex')).toBe(LEGACY_TRAINING_PROMPT_SHA256)
    expect(call.keys).toEqual(['maxTokens', 'messages', 'metadata', 'model', 'systemPrompt', 'temperature'])
    expect(call.maxTokens).toBe(4500)
    expect(call.requestTimeoutMs).toBeUndefined()
    expect(call.maxRetries).toBeUndefined()
    expect(call.message.endsWith('Gere o plano em JSON.')).toBe(true)
    expect(call.message).not.toContain('português simples')

    // What it stores and returns: the generator's words, jargon included.
    expect(result).toMatchObject({ success: true, plan_id: 'plan-0001' })
    expect(result.weekly_schedule).toEqual(GENERATED.weekly_schedule)
    expect(result.progression_rule).toBe(GENERATED.progression_rule)
    const saved = h.rpcs.filter((entry) => entry.name === 'save_training_plan_atomic')
    expect(saved).toHaveLength(1)
    expect(saved[0]?.params.p_weekly_schedule).toEqual(GENERATED.weekly_schedule)
    expect(saved[0]?.params.p_notes).toBe(GENERATED.notes)
    for (const term of COVERED_TERMS) {
      expect(carriers([saved[0]?.params.p_notes, result.progression_rule, result.weekly_schedule], term), term).not.toEqual([])
    }
    expect(storedDrafts(h)).toHaveLength(0)
  })

  it('B2 legacy: processMessage delivers a model answer with the same words, untouched (lock)', async () => {
    const answer = 'Treino Push/Pull/Legs, RPE 8-9, 12 reps.'
    const h = harness({ channel: 'whatsapp', chat: [{ content: answer }] })
    const output = await whatsapp(h, 'Como é o meu treino?')

    expect(output.text).toBe(answer)
    expect(h.generatorCalls).toHaveLength(0)
  })

  it('B3 a draft this turn had already stored is shown as stored, jargon included (lock: RC TL-6)', async () => {
    const payload = { ...GENERATED, equipment_summary: REPORT.payload.equipment_summary }
    const h = harness({
      history: HISTORY,
      chat: [{ toolCalls: [TOOL_CALL] }, { content: MODEL_SUMMARY }],
      generator: GENERATED_JSON,
      drafts: {
        [`${TURN_ID}:propoe_plano_treino`]: { id: 'draft-earlier', status: 'ready_for_review', payload },
      },
    })
    const output = await flow(h)

    expect(h.generatorCalls).toHaveLength(0)
    expect(storedDrafts(h)).toHaveLength(0)
    expect(events(h, 'training.plan_proposed')).toHaveLength(0)
    expect(output.text).toBe(`${OPENING}\n\n${trainingSuggestionText(payload)}\n\n${CLOSING}`)
    expect(output.text.endsWith(REPORT.chat_text_seen_on_screen_excerpt)).toBe(true)
    expect(output.toolCalls[0]?.result).toMatchObject({ success: true, draft_id: 'draft-earlier', replayed: true })
  })
})

// ── C. What the Flow asks the generator ─────────────────────────────────────
describe('audit 2026-10-10 Flow workout — the request of the reported turn', () => {
  it('C1 asks for plain words and adds no argument', async () => {
    const { h } = await propose(GENERATED_JSON)

    expect(h.generatorCalls).toHaveLength(1)
    const call = h.generatorCalls[0] as GeneratorCall
    // Same model, same arguments, same limits as before.
    expect(call.keys).toEqual([
      'maxRetries',
      'maxTokens',
      'messages',
      'metadata',
      'model',
      'requestTimeoutMs',
      'systemPrompt',
      'temperature',
    ])
    expect(call.model).toBe(GENERATOR_MODEL)
    expect(call.temperature).toBe(0.4)
    expect(call.maxTokens).toBe(8000)
    expect(call.requestTimeoutMs).toBe(120_000)
    expect(call.maxRetries).toBe(0)

    expect(call.systemPrompt).toBe(trainingSystemPrompt('flow'))
    expect(call.systemPrompt.endsWith(`\n\n${HOW_TO_WRITE}`)).toBe(true)

    expect(call.message).toContain('Nível musculação: intermediario')
    expect(call.message).toContain('Dias por semana: 5')
    expect(call.message).toContain('equipamentos completos de academia')
    expect(call.message).toContain('JSON compacto')
    expect(call.message).toMatch(/notes.*500/)
    expect(call.message).toContain('escreva notes e progression_rule com até 400 caracteres (o campo aceita 500)')
    expect(call.message).toContain('rpe_target e reps_range como texto (ex.: "8", "8-12")')
    expect(
      call.message.endsWith('Escreva todo texto em português simples, para quem nunca treinou.'),
    ).toBe(true)
  })
})

// ── L. The 2,000-character limit of the chat with the longer plain text ─────
describe('audit 2026-10-10 Flow workout — the chat limit with real texts', () => {
  const ARGS_20260930 = {
    available_equipment: ['equipamentos completos de academia'],
    location: 'academia_completa',
    days_per_week: 3,
    training_level: 'iniciante',
  }

  it('L1 the real draft of 2026-09-30 (18 exercises) is still shown whole', async () => {
    const generated = REPORT.draft_20260930
    expect(generated.weekly_schedule.flatMap((day) => day.exercises)).toHaveLength(18)
    expect(trainingSuggestionText(generated)).toHaveLength(1337)

    const { stored } = await propose(generated, ARGS_20260930)
    const payload = stored[0]?.p_payload as Plan
    const text = trainingSuggestionText(payload)

    expect(text).not.toContain(PLAN_SUGGESTION_TRUNCATED)
    expect(text).toContain('Segunda-feira — Corpo inteiro A (60 min)')
    expect(text).toContain('Quarta-feira — Corpo inteiro B (60 min)')
    expect(text).toContain('Sexta-feira — Corpo inteiro C (60 min)')
    expect(
      text.endsWith(
        'Progressão: Período de aclimatação: 15 dias mantendo mesmo peso para aprender técnica. Depois, progressão em escada por 4-6 meses: 1ª semana 12-15 repetições, 2ª semana 10-12 repetições, 3ª semana 8-10 repetições, 4ª semana 6-8 repetições. Sempre mantendo técnica perfeita. Quando completar ciclo, aumenta carga e reinicia.',
      ),
    ).toBe(true)
    expect(text).toHaveLength(1373)
    expect(text.length).toBeLessThanOrEqual(1958)
    // The names stay as generated (RC TL-13, RC TL-4).
    const names = payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name))
    expect(names).toEqual(
      generated.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name)),
    )
    expect(names).toContain('Stiff (levantamento romeno)')
    expect(names).toContain('Leg press 45°')
    expect(names).toContain('Pulldown com corda (ou pullover)')
  })

  it('L2 when the plain text does not fit, the progression paragraph is the first thing the chat loses, and the draft keeps it', async () => {
    // A composition, ASSEMBLED here from real texts only: the three days of
    // 2026-09-30, then the three days of the 2026-10-10 cut, with the first
    // five exercises of 2026-09-30 added in turns to Monday and Wednesday of
    // the cut (29 exercises, 6 days), and the progression rule of 2026-10-10.
    const firstFive = (REPORT.draft_20260930.weekly_schedule[0] as Day).exercises.slice(0, 5)
    const [monday, wednesday, friday] = GENERATED.weekly_schedule as [Day, Day, Day]
    const composition: Plan = {
      plan_type: 'split',
      weekly_schedule: [
        ...REPORT.draft_20260930.weekly_schedule,
        { ...monday, exercises: [...monday.exercises, firstFive[0], firstFive[2], firstFive[4]] as Exercise[] },
        { ...wednesday, exercises: [...wednesday.exercises, firstFive[1], firstFive[3]] as Exercise[] },
        friday,
      ],
      progression_rule: GENERATED.progression_rule,
      notes: GENERATED.notes,
    }
    expect(composition.weekly_schedule).toHaveLength(6)
    expect(composition.weekly_schedule.flatMap((day) => day.exercises)).toHaveLength(29)

    // As generated, it fits whole: 7 of 7 blocks, the progression included.
    const asGenerated = trainingSuggestionText(composition)
    expect(asGenerated).not.toContain(PLAN_SUGGESTION_TRUNCATED)
    expect(asGenerated).toContain('Progressão:')
    expect(asGenerated).toHaveLength(1930)

    const { result, stored } = await propose(composition, { ...ARGS_20260930, days_per_week: 6 })
    const payload = stored[0]?.p_payload as Plan
    const text = trainingSuggestionText(payload)

    // In plain words it would have 1,977 characters: the last block goes to the review.
    expect(result.sugestao).toBe(text)
    expect(text.endsWith(PLAN_SUGGESTION_TRUNCATED)).toBe(true)
    expect(text).not.toContain('Progressão:')
    for (const header of [
      'Segunda-feira — Corpo inteiro A (60 min)',
      'Quarta-feira — Corpo inteiro B (60 min)',
      'Sexta-feira — Corpo inteiro C (60 min)',
      'Segunda — Peito e Tríceps (60 min)',
      'Quarta — Pernas Completo (65 min)',
      'Sexta — Pernas Posterior e Glúteos (60 min)',
    ]) {
      expect(text).toContain(header)
    }
    expect(text).toContain(SCREEN_LAST_LINES)
    expect(text).toHaveLength(1729)
    // The Plan tab keeps the whole rule, in plain words.
    expect(payload.progression_rule).toBe(PLAIN_PROGRESSION)
    expect(payload.notes).toBe(PLAIN_NOTES)
  })
})

// ── D. The declared pendencies are the doc's, and each one is pinned ────────
describe('audit 2026-10-10 Flow workout — declared pendencies', () => {
  const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
  const fromHeader = Array.from(header.matchAll(/^ \* (> RC TL-\d+ — .*)$/gm), (match) => match[1] ?? '')
  const line = (number: number) => fromHeader[number - 1] ?? ''

  it('B4 every "RC TL" line of this header is in docs/mobile/api-v1.md, identical and in the same order', () => {
    const doc = readFileSync(
      fileURLToPath(new URL('../../../../docs/mobile/api-v1.md', import.meta.url)),
      'utf8',
    )
    const fromDoc = Array.from(doc.matchAll(/^(> RC TL-\d+ — .*)$/gm), (match) => match[1] ?? '')
    expect(fromHeader).toHaveLength(16)
    expect(fromHeader.map((entry) => entry.match(/^> RC TL-\d+/)?.[0])).toEqual(
      Array.from({ length: 16 }, (_, index) => `> RC TL-${index + 1}`),
    )
    expect(fromDoc).toEqual(fromHeader)
    // The project's mandatory wording of a pendency.
    for (const entry of fromHeader) {
      expect(entry).toMatch(
        /^> RC TL-\d+ — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-10\)(?:$|\. \S)/,
      )
    }
  })

  it('B4 the table the owner reads in the doc is the table of the code, row by row', () => {
    const doc = readFileSync(
      fileURLToPath(new URL('../../../../docs/mobile/api-v1.md', import.meta.url)),
      'utf8',
    )
    const start = doc.indexOf('## Linguagem simples na sugestão de treino do Flow')
    const end = doc.indexOf('## Proposta de treino')
    expect(start).toBeGreaterThan(doc.indexOf('> RC FN-7 — '))
    expect(end).toBeGreaterThan(start)
    const section = doc.slice(start, end)
    const part = (from: string, to: string) => section.slice(section.indexOf(from), section.indexOf(to))
    const rowsOf = (text: string) =>
      text
        .split('\n')
        .map((entry) => entry.trim())
        .filter((entry) => entry.startsWith('| `'))
    const code = (text: string) => `\`${text}\``
    const cells = (row: FlowPlainTrainingRow) =>
      `| ${row.spellings.map(code).join('; ')} | ${code(row.plain)}${row.one ? ` (com 1: ${code(row.one)})` : ''} | `

    const active = rowsOf(part('### Tabela ativa', '### O que espera o dono'))
    expect(active).toHaveLength(FLOW_PLAIN_TRAINING_VOCABULARY.length)
    FLOW_PLAIN_TRAINING_VOCABULARY.forEach((row, index) => {
      expect(active[index]?.startsWith(cells(row)), row.id).toBe(true)
      for (const [from, to] of Object.entries(row.articles ?? {})) {
        expect(active[index], row.id).toContain(`"${from}" por "${to}"`)
      }
    })

    const waiting = part('### O que espera o dono', '### O que é garantido')
    const renames = rowsOf(waiting)
    expect(renames).toHaveLength(FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER.length)
    FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER.forEach((row, index) => {
      expect(renames[index]?.startsWith(cells(row)), row.id).toBe(true)
    })
    expect(waiting).toContain('`{ effortOutOfTen: false, renames: [] }`')
    // Nothing is dated: no owner's yes was given.
    expect(waiting.match(/sim do\s+dono em: ____/g)).toHaveLength(3)

    const flat = section.replace(/\s+/g, ' ')
    expect(flat).toContain(
      `Lista fechada de vizinhas em inglês (regra 4): ${FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS.join(', ')}.`,
    )
    expect(flat).toContain(
      'Desde esta mudança o rascunho de treino do Flow é gravado com as grafias desta tabela trocadas na criação; a frase de RC FN-3 (o rascunho é gravado como o gerador escreveu) continua valendo para todo o resto, e RC FN-3 segue aberta.',
    )
  })

  it('B4 RC TL-13 and RC TL-14: the names and the effort grade stay as generated', () => {
    for (const name of ['Hip Thrust com Barra', 'Stiff Unilateral com Halter', 'Leg Press 45°', 'Military press']) {
      expect(line(13)).toContain(`"${name}"`)
      expect(projectFlowPlainTrainingText(name, 'name')).toEqual({ text: name, replaced: 0 })
    }
    expect(line(14)).toContain('"Esforço alvo 9"')
    expect(projectFlowPlainTrainingText('9', 'rpe_target')).toEqual({ text: '9', replaced: 0 })
    expect(line(14)).toContain('"RPE 8-9" vira "esforço 8-9"')
    expect(projectFlowPlainTrainingText('Treine com RPE 8-9.', 'notes').text).toBe('Treine com esforço 8-9.')
  })

  it('B4 RC TL-4 and RC TL-2: what is outside the vocabulary goes through; the six terms are covered in a sentence', () => {
    for (const untouched of ['peitoral', 'quadríceps', 'dorsal', 'deltoide', 'amplitude', 'stress', 'escápulas', 'unilateral', 'unilaterais', 'pegada neutra', 'cabeça longa', 'Upper back', 'Pulldown', 'Pullover', 'Crossover', 'drop set']) {
      expect(line(4)).toContain(`"${untouched}"`)
      const written = `Trabalhe ${untouched} com calma.`
      expect(projectFlowPlainTrainingText(written, 'notes'), untouched).toEqual({ text: written, replaced: 0 })
    }
    for (const term of TERMS_NOT_IN_THE_EVIDENCE) expect(line(2)).toContain(`"${term}"`)
    for (const term of TERMS_NOT_IN_THE_EVIDENCE.slice(0, 6)) {
      const result = projectFlowPlainTrainingText(`Trabalhe ${term} com calma.`, 'notes')
      expect(result.replaced, term).toBe(1)
      expect(carriers([result.text], term), term).toEqual([])
    }
  })

  it('B4 RC TL-7: a field whose plain text would not fit stays as generated, and is counted', () => {
    expect(line(7)).toContain('o dia "Upper A"')
    // Review of 2026-10-10: in the day field (20 characters) Upper and Lower never fit.
    expect(line(7)).toContain('"Parte de cima do corpo" tem 22 caracteres, "Parte de baixo do corpo" tem 23 e o limite é 20')
    expect(projectFlowPlainTrainingText('Upper', 'day').text).toHaveLength(22)
    expect(projectFlowPlainTrainingText('Lower', 'day').text).toHaveLength(23)
    for (const day of ['Upper', 'Lower', 'Upper A', 'Lower A', 'Upper/Lower', 'Upper body', 'Dia 1 - Lower']) {
      const kept = projectFlowPlainTrainingDraft({
        weekly_schedule: [{ day, focus: 'Peito', duration_min: 60, exercises: [] }],
      })
      expect((kept.payload as Plan).weekly_schedule[0]?.day, day).toBe(day)
      expect(kept.fieldsKeptAsGenerated, day).toBe(1)
    }
    const result = projectFlowPlainTrainingDraft({
      weekly_schedule: [{ day: 'Upper A', focus: 'Peito', duration_min: 60, exercises: [] }],
    })
    expect(result).toEqual({
      payload: { weekly_schedule: [{ day: 'Upper A', focus: 'Peito', duration_min: 60, exercises: [] }] },
      termsReplaced: 0,
      sentencesKeptAsGenerated: 0,
      fieldsKeptAsGenerated: 1,
    })
  })

  it('B4 RC TL-10: the sentence loses the terms, not its shape', () => {
    for (const [written, received, field] of [
      [
        'Plano Push/Pull/Legs modificado para 5 dias: Segunda (Push superior), Terça (Pull), Quarta (Legs completo)',
        'Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo)',
        'notes',
      ],
      ['Composto principal para peitoral', 'Exercício de vários músculos principal para peitoral', 'exercise_notes'],
      ['Panturrilha (gastrocnêmio)', 'Panturrilha (músculo da panturrilha)', 'name'],
    ] as const) {
      expect(line(10)).toContain(`"${received}"`)
      expect(projectFlowPlainTrainingText(written, field).text).toBe(received)
    }
    // Review of 2026-10-10: the word beside the term keeps its form.
    for (const [written, received] of [
      ['12 rep', '12 repetição'],
      ['MMII fortes', 'Parte de baixo do corpo fortes'],
      ['Treine a PSE 8', 'Treine o esforço 8'],
    ] as const) {
      expect(line(10)).toContain(`"${written}" vira "${received}"`)
      expect(projectFlowPlainTrainingText(written, 'notes').text).toBe(received)
    }
  })

  it('B4 RC TL-15: what the rule lets through on purpose, and its three known limits', () => {
    expect(line(15)).toContain('a sigla RIR com número dos dois lados, como "Séries de 12 RIR 2"')
    const through = [
      'reps_range',
      'Push-up',
      'rpe 8',
      'Você vai rir',
      'Séries de 12 RIR 2',
      'Semana 1 RIR 3, semana 2 RIR 2, semana 3 RIR 1.',
      'Faça 3 séries de 10 RIR 2-3.',
      'Pull Up',
      'Corrija qualquer falha técnica',
      'Lesão devida à falha na execução',
      'Push Workout',
      'Escápulas retraídas, deprimidas e firmes',
      'PSE alta só na última série',
      'Composto vitamínico não é necessário',
      'Priorize compostos no início',
      'treino composto por 5 dias',
      'Mantenha ambas as escápulas retraídas',
      'escápulas retraídas e deprimidas',
      'https://example.com/core/push',
    ]
    for (const written of through) {
      expect(projectFlowPlainTrainingText(written, 'notes'), written).toEqual({ text: written, replaced: 0 })
    }
    expect(projectFlowPlainTrainingText('Core Blaster', 'name').text).toBe('Core Blaster')
    for (const [written, received] of [
      ['Core Blaster', 'abdômen Blaster'],
      ['Combine compostos e isoladores', 'Combine compostos e exercícios de um músculo só'],
      ['Treino de Coreж', 'Treino de abdômenж'],
    ] as const) {
      expect(line(15)).toContain(`"${written}" vira "${received}"`)
    }
    expect(projectFlowPlainTrainingText('Treino de Coreж', 'notes').text).toBe('Treino de abdômenж')
    expect(projectFlowPlainTrainingText('Finalize com Core Blaster', 'notes').text).toBe(
      'Finalize com abdômen Blaster',
    )
    expect(projectFlowPlainTrainingText('Combine compostos e isoladores', 'notes').text).toBe(
      'Combine compostos e exercícios de um músculo só',
    )
  })

  it('B4 RC TL-1, RC TL-3, RC TL-6 and RC TL-16 say what was not proven', () => {
    expect(line(1)).toContain('o golden é variante próxima')
    expect(line(1)).toContain(`'${PLAN_SUGGESTION_TRUNCATED}'`)
    expect(line(3)).toContain('MODELO REAL')
    expect(line(6)).toContain('não é reescrito')
    expect(line(16)).toContain(`"${REPORTED_PHRASE}"`)
    expect(line(16)).toContain('o turno faz duas chamadas ao modelo')
  })
})
