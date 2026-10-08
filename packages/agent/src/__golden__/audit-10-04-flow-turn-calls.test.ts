/**
 * Audit 2026-10-04 — Flow chat (iOS app), cost and speed: HOW MANY model calls
 * a turn makes and HOW LONG it may wait.
 *
 * The report (staging, QA account A, public.messages with provider
 * 'mobile_flow', read 2026-10-04 ~15:45 BRT):
 *   - 10-04 10:32 "Sugira um cardápio completo para hoje": 22,443 prompt
 *     tokens, 608 of completion, US$ 0.078, 52.9 s. Two model calls: the
 *     second one only copied the suggestion the tool had just stored.
 *   - 09-30 15:56Z "Pode ser equilibrado no geral." (the workout suggestion
 *     of the device audit): the second call answered with a generic summary,
 *     which the system then replaced by the stored suggestion.
 *   - 09-30 12:44: 37,328 prompt tokens in one turn (four model calls).
 *   - the plan generator's own call (25–90 s, Sonnet 4.5) is in neither the
 *     tokens nor the cost of the turn.
 *   - one model call may take 90 s + one retry (181 s, above the app's 180 s
 *     request timeout) and a turn has no limit: past the route's 300 s the
 *     function dies with the turn in "processing" (409 for up to 10 minutes).
 *   - a status question answered by the "pure status" path reaches the app's
 *     bubble as the WhatsApp card, pictographs and Markdown marks included.
 *
 * Fix, Flow channel only (processAuthenticatedMessage):
 *  1. a turn whose only tools are plan-suggestion tools, each returning its
 *     text, ends without the second model call WHEN the patient's message is
 *     a single request and the model wrote nothing next to the tool call.
 *     A single request is a message with no "?" that (a) is written only
 *     with words of a closed list (SINGLE_REQUEST_VOCABULARY; "e" is not one
 *     of them) and numbers of days or times, (b) names exactly one plan — a
 *     menu or a workout, in one noun group, for one day —, (c) is one
 *     clause, greetings and thanks apart, and (d) names its plan itself (one
 *     exact reply apart, SINGLE_REQUEST_EXACT_REPLIES); any other wording
 *     keeps the second call.
 *     The answer is the text ensureSuggestionShown already sends when the
 *     model paraphrases: "Sua sugestão está pronta:" + the stored suggestion
 *     + "É um rascunho: toque em "Revisar sugestão"…"
 *     (MOBILE_FLOW_DIRECT_PLAN_SUGGESTION, isSingleRequestMessage);
 *  2. at most 2 model iterations with tools, in code
 *     (MOBILE_FLOW_MAX_MODEL_ITERATIONS); guard retries keep their own extra
 *     iteration; and when the last allowed iteration was a tool call, ONE
 *     closing call with the tools switched off (MOBILE_FLOW_CLOSING_CALL), so
 *     the turn ends with words — unless the message is a single request and
 *     its suggestion is already stored (that suggestion is the answer). A
 *     provider error on that call does not fail a turn that has a suggestion
 *     stored: the suggestion is the answer;
 *  3. 45 s per chat call and 150 s of model work per turn; the tools' own
 *     model calls never get more than the turn has left
 *     (MOBILE_FLOW_TIME_LIMITS). With a suggestion already stored the
 *     deadline ends the turn on that suggestion instead of an error. The
 *     service adds a hard 165 s limit
 *     (apps/admin/src/lib/mobile-api/flow-chat-service.turn-limit.test.ts);
 *  4. the status answer leaves as plain text with the Today screen's labels
 *     (MOBILE_FLOW_PLAIN_STATUS). The day values and order are preserved;
 *     decisions-v1 item5 subsequently hides block progress outside
 *     recomposition and the pending 14-day budget/DAM on the Flow;
 *  5. the generator's tokens, cost and milliseconds are in `llm.flow_calls`
 *     and in the turn's totals, and the event is written for a turn that
 *     fails too;
 *  6. every history line of the patient's current session goes to the
 *     model (mobileFlowPromptHistory): the lines of the current local day
 *     and those of the 6 hours before the turn (MOBILE_FLOW_SESSION_HOURS),
 *     so a session that crosses midnight is still seen whole.
 * No calculation rule, no model and no max_tokens changed. WhatsApp is
 * byte-identical: audit-10-04-whatsapp-request-lock.test.ts (fixture and hash
 * unchanged) pins the request of two turns, and the WhatsApp tests of this
 * file pin what those two turns do not show (iteration count, no closing
 * call, the status card, the tools' client).
 *
 * Review of 2026-10-04 (three adversarial reviewers), fixed in this file with
 * the reviewers' exact messages and scripts: a message that asks for the plan
 * AND something else lost its second question (section 2b); with the cap a
 * model asking for a tool twice ended with no text (section 3); an allergy
 * said 18+ lines earlier the same day never reached the menu generator
 * (section 5c); the deadline after a stored draft failed the turn and lost
 * the generator's cost (sections 4 and 5b).
 *
 * Second review of 2026-10-04 (lens A), fixed in this file with the
 * reviewer's exact messages and scripts: with a suggestion stored, a message
 * that asks something else answered by tool, tool got no closing call and
 * lost its other question (section 3b); a second request in the same
 * sentence with no "?" still ended on the suggestion alone (section 2c: the
 * gate is now a closed word list); a session that crosses local midnight was
 * cut to 16 lines at 00:05 (section 5d).
 *
 * Third review of 2026-10-04 (lens A), fixed in this file with the
 * reviewer's exact messages and scripts: a menu and a workout written as
 * "Monte uma dieta e um plano pra academia" counted as one request and the
 * workout was dropped (section 2d); a reply that names no plan ("quero os
 * 2", "Quero") after a Flow line that offered two things ended on the first
 * suggestion (section 2d); a provider error on the closing call failed a
 * turn that already had its suggestion stored (section 3b). Declared, with
 * the reviewer's exact sequence locked as a pendency: a plan the model only
 * asks for on its third iteration (RC PERF-C15, section 3b).
 *
 * Every pipeline test runs the REAL entry point and the REAL tools with a
 * fake database and a scripted model.
 *
 * > RC PERF-C1 — cenário saída REAL do gerador e argumentos REAIS da ferramenta no turno de cardápio de 10-04 10:32 NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A frase é a exata. A saída do gerador não foi guardada: o fixture reproduz
 *   os totais lidos no aparelho (2.884 kcal, 152,3 g), não os alimentos. Os
 *   argumentos da ferramenta também não foram registrados: o golden usa o
 *   horizonte diário (`daily`).
 * > RC PERF-C2 — cenário turno de TREINO do baseline de 10-04 09:21 (21.750 tokens, 46,3 s) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O texto do paciente desse turno não foi registrado. O turno de treino
 *   coberto é o do aparelho de 30/09 15:56Z, com a frase e os argumentos exatos
 *   e o rascunho real gravado (956b82be…).
 * > RC PERF-C3 — cenário resposta de sugestão SEM a frase livre de abertura do modelo, vista pelo paciente, NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nos turnos de pedido único o paciente vê sempre a abertura fixa. Precisa do
 *   aval do Eduardo e de uma rodada no iPhone.
 * > RC PERF-C4 — cenário chamada de chat real acima de 45 s NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nenhuma foi observada (o maior turno de uma chamada levou 12,6 s), mas o
 *   limite não foi medido contra a distribuição real. `llm.flow_calls` traz `ms`
 *   por chamada.
 * > RC PERF-C5 — cenário card escrito pelo MODELO no Flow (troca pós-laço pelo card canônico, com pictogramas e negrito) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Só a resposta do caminho "status puro" sai em texto simples.
 * > RC PERF-C6 — cenário paciente do app em INGLÊS perguntando o status NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O card é em português para todos os idiomas, como já era.
 * > RC PERF-C7 — cenário tokens COBRADOS por uma chamada que falhou ou expirou, e turno encerrado pela trava de 165 s do serviço ou pela plataforma, NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O turno que termina em erro grava `llm.flow_calls` com o que já gastou, mas
 *   a chamada que falhou entra só com o tempo (o provedor não devolve os tokens
 *   de uma chamada cortada). Quando é o serviço que encerra o turno aos 165 s, o
 *   agente continua rodando e grava o evento ao terminar, se a função ainda
 *   estiver viva; se a plataforma matou a função, nada é gravado.
 * > RC PERF-C8 — cenário chamada de fechamento com MODELO REAL, repetição de guarda DEPOIS dela (as ferramentas voltam a estar ligadas) e erro do provedor NA chamada de fechamento SEM sugestão gravada (o turno falha) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Não há chave de modelo local: não foi verificado como o provedor trata
 *   `tool_choice: none` com as ferramentas no pedido, nem a qualidade dessa
 *   resposta. Três casos travados como pendência no golden: (a) sem sugestão
 *   gravada, o modelo ainda devolve só uma chamada de ferramenta, ou texto
 *   vazio, na chamada de fechamento: o turno termina sem texto e o serviço
 *   devolve 502 depois de três chamadas pagas; (b) uma guarda recusa a resposta
 *   de fechamento: a repetição de guarda é feita com as ferramentas ligadas de
 *   novo, e se o modelo voltar a pedir ferramenta o turno termina sem texto
 *   depois de quatro chamadas (a chamada de fechamento é uma só por turno); (c)
 *   o provedor responde erro na chamada de fechamento e não há sugestão gravada:
 *   o turno falha com 502 e `llm.flow_calls` é gravado com `turn_failed` (onde a
 *   config permite 3 ou mais, o commit anterior respondia na terceira chamada,
 *   com as ferramentas ligadas). Com uma sugestão gravada o erro do provedor no
 *   fechamento não derruba o turno: a resposta é a sugestão gravada, sem a
 *   resposta à outra pergunta (RC PERF-C13); se o provedor recusar `tool_choice:
 *   none` sempre, é isso que acontece em todo turno desse formato. Com o prazo
 *   vencido a chamada não é feita.
 * > RC PERF-C10 — cenário dois pedidos do MESMO tipo numa oração só, sem "e", sem pontuação, sem pronome e sem repetir o nome do plano ("Monte um cardápio pra hoje pra semana"), e a resposta exata "Pode ser equilibrado no geral." depois de uma linha do Flow que ofereceu duas coisas, NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A regra de pedido único lê palavras, não sentido. (1) A primeira mensagem
 *   conta como um pedido: se o modelo chamar a ferramenta uma vez, o turno
 *   termina nessa sugestão, sem uma palavra sobre a outra. (2) A frase exata do
 *   turno de treino do aparelho fica no caminho de uma chamada sem citar o
 *   plano; se a linha anterior do Flow ofereceu cardápio e treino e o modelo
 *   chama uma ferramenta por iteração, o turno termina na primeira sugestão. Os
 *   dois casos estão travados como pendência no golden. Está coberto, com a
 *   segunda chamada (ou a de fechamento): cardápio e treino na mesma mensagem,
 *   inclusive "plano pra academia" e "dieta e academia"; dois pedidos ligados
 *   por "e", vírgula ou outra pontuação ("Monte um cardápio para hoje e outro
 *   para amanhã"); "outro", "um", "o" ou "os 2" no lugar do nome do plano;
 *   "hoje" e "amanhã" juntos; a resposta que não cita o plano ("Quero", "pode",
 *   "Pode ser", "manda", "quero os 2", "1 e 2", "faz os 2"); e qualquer palavra
 *   fora da lista.
 * > RC PERF-C11 — cenário mensagem com outra pergunta em que o modelo PARAFRASEIA a sugestão na segunda chamada NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A resposta vira o texto fixo com a sugestão gravada e a frase do modelo
 *   sobre a outra pergunta vai embora junto, como já era antes desta mudança. A
 *   outra pergunta só é respondida quando o modelo copia a sugestão palavra por
 *   palavra. Vale também para a chamada de fechamento (travado no golden).
 * > RC PERF-C12 — cenário paciente do app em INGLÊS cuja sugestão o modelo parafraseia, ou cujo turno o prazo ou um erro na chamada de fechamento encerra, NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Nesses casos a resposta é o texto fixo, com a abertura e o fecho em
 *   português para todos, e o botão do app em inglês se chama "Review
 *   suggestion", não "Revisar sugestão". Já era assim antes desta mudança.
 *   Nenhuma frase nova podia entrar; uma versão em inglês da moldura precisa de
 *   aval. A paráfrase está travada como pendência no golden. O pedido em inglês
 *   ("Please suggest a full menu for today") está fora da lista fechada: faz a
 *   segunda chamada e fica com a moldura que o modelo escreve, como antes
 *   (travado no golden).
 * > RC PERF-C13 — cenário turno que o PRAZO, ou um erro do provedor na chamada de fechamento, encerra com uma sugestão gravada e algo mais pedido NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A resposta é a sugestão gravada com o texto fixo: não diz que o segundo
 *   plano não foi criado (dois planos na mesma mensagem) nem responde a outra
 *   pergunta. Nenhuma frase nova podia entrar nesta mudança. Travado no golden:
 *   no prazo o evento traz `plan_suggestion_at_deadline`; no erro do fechamento,
 *   a terceira chamada com `closing` e `failed`.
 * > RC PERF-C14 — cenário frequência REAL do caminho de uma chamada só NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   Só fica com uma chamada o pedido simples, único e explícito: escrito inteiro
 *   com palavras da lista fechada, sem "?", numa oração só, citando um plano só,
 *   e sem texto do modelo junto da chamada da ferramenta. Ficam com duas: o
 *   pedido escrito como pergunta ("Pode montar um cardápio para hoje?"), em
 *   inglês, com abreviação, com erro de digitação, com "e", com um número que
 *   não conta dias ou vezes ou com qualquer palavra fora da lista, e a resposta
 *   curta que não cita o plano. Não se sabe quantos turnos de sugestão caem em
 *   cada caso; `plan_suggestion_direct` mede em staging.
 * > RC PERF-C15 — cenário plano que o modelo só pede na TERCEIRA iteração (leitura, leitura, plano) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O teto é de 2 iterações com ferramenta e a chamada de fechamento vem com as
 *   ferramentas desligadas: a ferramenta de plano que o modelo pede nela não é
 *   executada e nenhum rascunho é gravado no turno. Travado como pendência no
 *   golden com a sequência exata da terceira revisão ("Monte uma sugestão de
 *   cardápio para amanhã. E quanto falta de proteína hoje?", com
 *   `consulta_progresso`, `consulta_metricas`, `propoe_plano_dieta`), config 2 e
 *   5: 3 chamadas, nenhum rascunho. O que o paciente lê depende do que o modelo
 *   real escreve sem a ferramenta (não medido); com o modelo roteirizado o texto
 *   sai vazio (502 no serviço). O commit anterior com config 5 fazia 4 chamadas
 *   e entregava a sugestão e a resposta; com a config 2 de staging terminava em
 *   2 chamadas, sem rascunho e sem texto. A sequência está na lista do que rodar
 *   em staging.
 * > RC PERF-T4 — cenário chamada de chat com 429 e `Retry-After` do provedor NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A espera do SDK entre as duas tentativas (até 60 s) não entra na conta do
 *   prazo: uma chamada pode durar até 150 s e terminar depois dos 150 s do
 *   turno. Medido na revisão com o SDK real e tempo virtual: 429 com
 *   `Retry-After: 55` e segunda tentativa pendurada só falha aos 100 s. Quem
 *   encerra o turno é a trava de 165 s do serviço, com o agente ainda rodando
 *   (RC PERF-T3). No golden o modelo é roteirizado: sem SDK.
 * > RC PERF-W1 — cenário alergia ou intolerância dita em DIA ANTERIOR há mais de 6 horas, fora da janela (por exemplo, ontem de manhã, com 16 ou mais linhas na sessão atual) NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   O modelo não lê a linha e o gerador de cardápio recebe "(nenhuma)".
 *   Restrições não são gravadas no perfil; gravar é a solução de fundo e fica
 *   fora desta mudança. Travado como pendência em
 *   `audit-10-04-flow-turn-calls.test.ts`, em dois casos: dita ontem de manhã
 *   com 20 linhas hoje; e dita às 17:50, com o turno às 00:05 e 20 linhas depois
 *   das 23:30. A linha de dia anterior dita nas 6 horas antes do turno está
 *   coberta.
 * > RC PERF-W2 — cenário alergia dita há mais de 49 linhas no MESMO dia NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A leitura do banco traz 50 linhas; o que ficou antes disso nunca chegou ao
 *   modelo, antes ou depois desta mudança.
 * > RC PERF-C9 — cenário ordem das linhas da resposta de status NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A troca de card pós-laço põe a linha "Sequência" antes do card, no WhatsApp
 *   e no Flow. O Flow repete a ordem do WhatsApp; corrigir a ordem mexe no
 *   WhatsApp.
 * > RC PERF-C16 — cenário pergunta de sim ou não, ou pedido de reenvio, escrita SEM "?" só com palavras da lista ("Dá pra fazer o treino de hoje em casa", "pode treino hoje", "Preciso fazer dieta", "hoje faz treino", "Pode fazer treino em casa", "me passa o treino de hoje") NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A regra de pedido único lê palavras, não sentido: a mensagem conta como pedido único. Se o modelo responder só com a ferramenta de plano, sem texto, o turno termina na sugestão com o texto fixo, sem o sim ou não (no commit anterior a segunda chamada respondia). Com texto do modelo junto da ferramenta o turno faz a segunda chamada. Medido pela quarta revisão de 04/10 (sonda Q-nomark); sem golden.
 * > RC PERF-C17 — cenário guarda que RECUSA a resposta da chamada de fechamento seguida de erro do provedor na repetição de guarda, com sugestão gravada NÃO coberto nesta PR (pendência da audit 2026-10-04).
 *   A saída que responde com a sugestão gravada vale só para a própria chamada de fechamento. Nessa falha dupla o turno falha com 502, `llm.flow_calls` é gravado com `turn_failed`, o rascunho fica pendente e nada chega ao chat ("Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?": propoe_plano_dieta, consulta_progresso, fechamento recusado pela guarda de bloco, repetição com erro 500). Com a config 2 o commit anterior entregava a sugestão; com a config 5 falhava do mesmo jeito. A correção de uma condição foi testada em cópia pela quarta revisão de 04/10 (sonda G1); sem golden nesta PR.
 */
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { flowPlainStatusText } from '../flow-status-text.js'
import type { PipelineDeps } from '../pipeline.js'
import {
  MOBILE_FLOW_CALLS_EVENT,
  MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS,
  MOBILE_FLOW_DEADLINE_ERROR,
  MOBILE_FLOW_MAX_MODEL_ITERATIONS,
  MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS,
  MOBILE_FLOW_TURN_DEADLINE_MS,
  processAuthenticatedMessage,
  processMessage,
} from '../pipeline.js'
import {
  ensureSuggestionShown,
  isPurePlanSuggestionTurn,
  isSingleRequestMessage,
  nutritionSuggestionText,
  SINGLE_REQUEST_EXACT_REPLIES,
  SINGLE_REQUEST_VOCABULARY,
  trainingSuggestionText,
} from '../plan-suggestion-text.js'
import { composeStatusMessage } from '../post-registration-message.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { consultaProgresso, propoePlanoTreino } from '../tools.js'

// ── The report ──────────────────────────────────────────────────────────────
/** Exact phrase of the baseline menu turn (10-04 10:32; handoff F14). */
const MENU_PHRASE = 'Sugira um cardápio completo para hoje'
/** Exact phrase and tool arguments of the device workout turn (09-30 15:56Z). */
const WORKOUT_PHRASE = 'Pode ser equilibrado no geral.'
const WORKOUT_ARGS = {
  available_equipment: ['equipamentos completos de academia'],
  location: 'academia_completa',
  days_per_week: 3,
  training_level: 'iniciante',
}
/** The generic reply the model gave on the device after the tool (09-30). */
const GENERIC_REPLY =
  'Proposta pronta! Ficou assim:\n\nSegunda — Full Body A (6 exercícios)\nQuarta — Full Body B (6 exercícios)\nSexta — Full Body C (6 exercícios)\n\nPra iniciante, full body 3x por semana é o formato ideal — trabalha o corpo todo com frequência alta e dá tempo de recuperação entre os dias.\n\nÉ um rascunho ainda. Abre o app, toca em "Revisar proposta", confere os exercícios e confirma pra valer.'
/** The first ready-made question of the app (FlowChatPresentation, flow.suggestion.day). */
const STATUS_PHRASE = 'Como está meu dia até agora?'

/** The fixed text around a suggestion, as ensureSuggestionShown writes it today. */
const OPENING = 'Sua sugestão está pronta:'
const CLOSING =
  'É um rascunho: toque em "Revisar sugestão" para conferir, ajustar e confirmar. Ele só vale depois que você confirmar.'

const NOW = new Date('2026-10-04T15:03:40.503Z') // 12:03 in São Paulo
const USER_ID = 'qa-a'
const TURN_ID = 'mobile_flow/qa-a/turn-calls'
const MODEL = 'anthropic/claude-sonnet-4.6'
const GENERATOR_MODEL = 'anthropic/claude-sonnet-4.5'

type Row = Record<string, unknown>

const PROFILE: Row = {
  sex: 'masculino',
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80.5,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}

/** The QA account's day row at 15:03:40Z of 2026-10-04 (audit RC A). */
const DAY: Row = {
  date: '2026-10-04',
  calories_target: 2980,
  protein_target: '144.00',
  calories_consumed: 541,
  protein_g: '59.03',
  carbs_g: '47.32',
  fat_g: '10.27',
  exercise_calories: 322,
  water_consumed_ml: 500,
  daily_balance: -2761,
  deficit_accumulated: 0,
  day_status: null,
  day_closed: false,
  gap_reminder_sent_at: null,
}

const PROGRESS: Row = {
  current_streak: 3,
  longest_streak: 5,
  xp_total: 1240,
  level: 2,
  blocks_completed: 0,
  deficit_block: 3120,
  last_active_date: null,
}

const USER: Row = {
  id: USER_ID,
  name: 'QA A',
  summary: null,
  last_active_at: null,
  country: 'BR',
  country_confirmed: true,
  country_detected_from_wpp: null,
  locale: 'pt-BR',
  metadata: null,
  timezone: 'America/Sao_Paulo',
}

// ── Generator outputs ───────────────────────────────────────────────────────
const food = (food_name: string, quantity_g: number, kcal: number, protein_g: number) => ({
  food_name,
  quantity_g,
  kcal,
  protein_g,
  carbs_g: 1,
  fat_g: 1,
})

/** 2,884 kcal and 152.3 g of protein: the totals read on the device (F14). */
const MENU_OUTPUT = JSON.stringify({
  daily_meals: [
    {
      meal_type: 'cafe',
      time_suggestion: '07:30',
      items: [
        food('Pão francês', 100, 300, 9),
        food('Ovos mexidos', 150, 219, 20),
        food('Banana', 120, 118, 1.6),
        food('Queijo minas frescal', 60, 158, 10.5),
      ],
      total_kcal: 795,
      total_protein_g: 41.1,
    },
    {
      meal_type: 'almoco',
      time_suggestion: '12:30',
      items: [
        food('Arroz branco cozido', 250, 325, 6.3),
        food('Feijão carioca cozido', 150, 114, 8.4),
        food('Frango grelhado', 150, 248, 43.5),
        food('Azeite de oliva', 10, 90, 0),
        food('Salada de alface e tomate', 100, 20, 1),
      ],
      total_kcal: 797,
      total_protein_g: 59.2,
    },
    {
      meal_type: 'lanche_tarde',
      time_suggestion: '16:00',
      items: [
        food('Iogurte natural', 200, 126, 8.2),
        food('Aveia em flocos', 60, 236, 8.4),
        food('Mel', 20, 61, 0.1),
        food('Castanha de caju', 30, 171, 5.6),
      ],
      total_kcal: 594,
      total_protein_g: 22.3,
    },
    {
      meal_type: 'jantar',
      time_suggestion: '20:00',
      items: [
        food('Macarrão cozido', 250, 395, 14.5),
        food('Carne moída refogada', 80, 170, 13.2),
        food('Molho de tomate', 100, 38, 1.4),
        food('Azeite de oliva', 10, 90, 0),
        food('Brócolis cozido', 20, 5, 0.6),
      ],
      total_kcal: 698,
      total_protein_g: 29.7,
    },
  ],
  shopping_list: [{ category: 'proteínas', food_name: 'Frango', quantity_g: 150 }],
})

const exercise = (name: string, muscle_group: string, sets: number, rest_seconds: number) => ({
  name,
  muscle_group,
  sets,
  reps_range: '12-15',
  rpe_target: '7-8',
  rest_seconds,
})

/** The draft stored on staging for this very turn (956b82be…, 2026-09-30 15:57Z). */
const WORKOUT_OUTPUT = JSON.stringify({
  plan_type: 'full_body',
  weekly_schedule: [
    {
      day: 'Segunda-feira',
      focus: 'Full Body A',
      duration_min: 60,
      exercises: [
        exercise('Agachamento livre', 'quadríceps/glúteos', 3, 90),
        exercise('Supino reto com barra', 'peitoral', 3, 90),
        exercise('Puxada frontal', 'dorsal', 3, 90),
        exercise('Desenvolvimento com halteres', 'ombros', 3, 90),
        exercise('Rosca direta com barra', 'bíceps', 2, 60),
        exercise('Tríceps na polia (corda)', 'tríceps', 2, 60),
      ],
    },
    {
      day: 'Quarta-feira',
      focus: 'Full Body B',
      duration_min: 60,
      exercises: [
        exercise('Leg press 45°', 'quadríceps/glúteos', 3, 90),
        exercise('Supino inclinado com halteres', 'peitoral superior', 3, 90),
        exercise('Remada curvada com barra', 'dorsal', 3, 90),
        exercise('Elevação lateral com halteres', 'ombros (deltoides laterais)', 3, 90),
        exercise('Rosca martelo alternada', 'bíceps/antebraço', 2, 60),
        exercise('Tríceps testa com barra', 'tríceps', 2, 60),
      ],
    },
    {
      day: 'Sexta-feira',
      focus: 'Full Body C',
      duration_min: 60,
      exercises: [
        exercise('Stiff (levantamento romeno)', 'posteriores de coxa/glúteos', 3, 90),
        exercise('Crucifixo inclinado com halteres', 'peitoral', 3, 90),
        exercise('Pulldown com corda (ou pullover)', 'dorsal', 3, 90),
        exercise('Remada alta com barra', 'ombros/trapézio', 3, 90),
        exercise('Rosca concentrada', 'bíceps', 2, 60),
        exercise('Tríceps francês com haltere', 'tríceps', 2, 60),
      ],
    },
  ],
  progression_rule:
    'Período de aclimatação: 15 dias mantendo mesmo peso para aprender técnica. Depois, progressão em escada por 4-6 meses: 1ª semana 12-15 reps, 2ª semana 10-12 reps, 3ª semana 8-10 reps, 4ª semana 6-8 reps. Sempre mantendo técnica perfeita. Quando completar ciclo, aumenta carga e reinicia.',
})

// ── Harness ─────────────────────────────────────────────────────────────────
interface ChatStep {
  content?: string
  toolCalls?: Array<{ id: string; name: string; arguments: string }>
  /** Tool calls decided from the messages the model received in this call. */
  toolCallsFrom?: (
    messages: LlmCall['messages'],
  ) => Array<{ id: string; name: string; arguments: string }>
  /**
   * The model copies the suggestion the tool returned, word for word, between
   * an opening and a closing of its own, and then answers the other question
   * (the string). The reply shape of the review probes of 2026-10-04.
   */
  copySuggestion?: string | true
  /** The model's whole reply, written around the suggestion the tool returned. */
  replyFrom?: (suggestion: string) => string
  promptTokens?: number
  completionTokens?: number
  cacheRead?: number
  costUsd?: number | null
  /** How long the call takes on the fake clock. */
  ms?: number
  /**
   * The call fails as a client timeout does: after its whole time limit, or
   * after `ms` when given.
   */
  timesOut?: boolean
  /** The provider answers the call with this error (not a timeout). */
  throws?: string
}

interface GeneratorStep {
  content: string
  promptTokens?: number
  completionTokens?: number
  costUsd?: number | null
  ms?: number
  timesOut?: boolean
}

interface Fixture {
  channel?: 'flow' | 'whatsapp'
  text?: string
  /** The moment of the turn when it is not NOW (the day row follows it). */
  now?: Date
  user?: Row
  /** Stored lines of the channel before this turn (oldest first). */
  history?: Row[]
  chat?: ChatStep[]
  generator?: GeneratorStep[]
  /** agent_configs.max_tool_iterations of the stage (the row WhatsApp shares). */
  configIterations?: number | null
  depsIterations?: number
  profile?: Row
  day?: Row | null
  progress?: Row
  closedDays?: Row[]
  /** product_events rows the tools' limits read (event names only). */
  pastEvents?: string[]
  /** plan_drafts rows by request_key (a draft this very turn already stored). */
  drafts?: Record<string, Row>
}

interface LlmCall {
  model: string
  keys: string[]
  stage: string | undefined
  requestTimeoutMs: number | undefined
  maxRetries: number | undefined
  maxTokens: number | undefined
  toolChoice: unknown
  /** How many tool schemas the call carried. */
  tools: number
  messages: Array<{ role: string; content: unknown }>
  /** Milliseconds since the start of the turn when the call was made. */
  at: number
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Row }>
  rpcs: Array<{ name: string; params: Row }>
  chatCalls: LlmCall[]
  generatorCalls: LlmCall[]
}

const advance = (ms: number) => vi.setSystemTime(new Date(Date.now() + ms))

function harness(fixture: Fixture = {}): Harness {
  const provider = fixture.channel === 'whatsapp' ? 'whatsapp' : 'mobile_flow'
  const day = fixture.day === undefined ? DAY : fixture.day
  const chat = fixture.chat ?? [{ content: 'Resposta do modelo.' }]
  const generator = fixture.generator ?? []
  const inserts: Harness['inserts'] = []
  const rpcs: Harness['rpcs'] = []
  const chatCalls: LlmCall[] = []
  const generatorCalls: LlmCall[] = []
  const now = fixture.now ?? NOW
  // The patient's local day at `now` (YYYY-MM-DD), the date the day row is read by.
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: String((fixture.user ?? USER).timezone ?? 'America/Sao_Paulo'),
  }).format(now)
  const turnRow: Row = {
    id: 'message-turn-0001',
    direction: 'in',
    content: fixture.text ?? MENU_PHRASE,
    content_type: 'text',
    created_at: now.toISOString(),
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
        return fixture.user ?? USER
      case 'user_profiles':
        return fixture.profile ?? PROFILE
      case 'user_progress':
        return fixture.progress ?? PROGRESS
      case 'messages': {
        if (read.filters.provider != null && read.filters.provider !== provider) return []
        // A lookup of this turn's own row (the tools ask for its id).
        if (read.filters.provider_message_id != null) return [turnRow]
        // The history read: newest first, cut at the limit asked.
        const rows: Row[] = [
          ...(fixture.history ?? []).map((row): Row => ({ ...row, provider })),
          turnRow,
        ].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
        return read.limit == null ? rows : rows.slice(0, read.limit)
      }
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return fixture.closedDays ?? []
        if (!day || read.filters.date !== (fixture.now ? today : '2026-10-04')) return null
        if (read.columns.trim() === '*') return day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'product_events': {
        // The tools' limits ask by event name; the context reads find nothing.
        const names = read.within.event
        if (!names) return []
        return (fixture.pastEvents ?? [])
          .filter((name) => names.includes(name))
          .map((name, index) => ({ id: `event-${index}`, event: name }))
      }
      case 'plan_drafts': {
        const key = read.filters.request_key
        return typeof key === 'string' ? (fixture.drafts?.[key] ?? null) : []
      }
      case 'global_config':
        // The model router stays off: the turn keeps the stage's model.
        if (read.filters.key === 'router.haiku_enabled') return { value: false }
        return [
          {
            key: 'calc.protein_factors',
            value: {
              muita: 1.6,
              pouca: 1.8,
              moderada: 1.8,
              training_low: 1.7,
              optimal_mid_training: 1.9,
              optimal_high_training: 2,
            },
          },
        ]
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'ganho_massa',
          model: MODEL,
          temperature: 0.2,
          max_tokens: 1200,
          ...(fixture.configIterations === null
            ? {}
            : { max_tool_iterations: fixture.configIterations ?? 2 }),
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
      if (name === 'create_plan_draft_atomic') {
        return { data: { id: 'draft-0001', status: params.p_status, inserted: true }, error: null }
      }
      return { data: name === 'match_method_chunks' ? [] : USER_ID, error: null }
    },
  } as unknown as PipelineDeps['supabase']

  interface LlmInput {
    model: string
    messages: Array<{ role: string; content: unknown }>
    metadata?: Record<string, string>
    requestTimeoutMs?: number
    maxRetries?: number
    maxTokens?: number
    toolChoice?: unknown
    tools?: unknown[]
  }
  /** The suggestion text of the newest tool result in the messages of a call. */
  const suggestionIn = (messages: LlmInput['messages']): string => {
    const toolMessage = [...messages]
      .reverse()
      .find((message) => message.role === 'tool' && /"sugestao"/.test(String(message.content)))
    return (
      (JSON.parse(String(toolMessage?.content ?? '{}')) as { sugestao?: string }).sugestao ?? ''
    )
  }
  const llm = {
    complete: async (input: LlmInput) => {
      const stage = input.metadata?.Stage
      const isGenerator = stage === 'diet-generator' || stage === 'training-generator'
      const seen = isGenerator ? generatorCalls : chatCalls
      const step: ChatStep & Partial<GeneratorStep> =
        (isGenerator ? generator : chat)[
          Math.min(seen.length, (isGenerator ? generator : chat).length - 1)
        ] ?? {}
      const messages = input.messages.map((message) => ({ ...message }))
      seen.push({
        model: input.model,
        keys: Object.keys(input).sort(),
        stage,
        requestTimeoutMs: input.requestTimeoutMs,
        maxRetries: input.maxRetries,
        maxTokens: input.maxTokens,
        toolChoice: input.toolChoice,
        tools: input.tools?.length ?? 0,
        messages,
        at: Date.now() - now.getTime(),
      })
      if (step.timesOut) {
        advance(step.ms ?? input.requestTimeoutMs ?? 90_000)
        throw new Error('Request timed out.')
      }
      if (step.ms) advance(step.ms)
      if (step.throws) throw new Error(step.throws)
      const copied = step.replyFrom
        ? step.replyFrom(suggestionIn(messages))
        : step.copySuggestion
          ? `Sua sugestão está pronta!\n\n${suggestionIn(messages)}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.${
              typeof step.copySuggestion === 'string' ? `\n\n${step.copySuggestion}` : ''
            }`
          : null
      return {
        content: copied ?? step.content ?? '',
        toolCalls: isGenerator ? [] : (step.toolCallsFrom?.(messages) ?? step.toolCalls ?? []),
        model: isGenerator ? GENERATOR_MODEL : MODEL,
        finishReason: 'stop',
        promptTokens: step.promptTokens ?? (isGenerator ? 900 : 7400),
        completionTokens: step.completionTokens ?? (isGenerator ? 2600 : 60),
        cacheReadInputTokens: isGenerator ? undefined : (step.cacheRead ?? 5060),
        cacheCreationInputTokens: isGenerator ? undefined : 0,
        costUsd: step.costUsd === undefined ? (isGenerator ? 0.0417 : 0.0098) : step.costUsd,
      }
    },
  } as unknown as PipelineDeps['llm']

  return {
    deps: {
      supabase,
      llm,
      ...(fixture.depsIterations === undefined
        ? {}
        : { maxToolIterations: fixture.depsIterations }),
    },
    inserts,
    rpcs,
    chatCalls,
    generatorCalls,
  }
}

function flow(h: Harness, text: string = MENU_PHRASE, at: Date = NOW) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text,
    timestamp: at,
  })
}

function whatsapp(h: Harness, text: string = MENU_PHRASE) {
  return processMessage(h.deps, {
    from: '5511999999999',
    providerMessageId: TURN_ID,
    text,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

function eventNames(h: Harness): string[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events')
    .map((entry) => String(entry.row.event))
}

function events(h: Harness, name: string): Row[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events' && entry.row.event === name)
    .map((entry) => entry.row)
}

function drafts(h: Harness): Row[] {
  return h.rpcs
    .filter((call) => call.name === 'create_plan_draft_atomic')
    .map((call) => call.params)
}

const tool = (name: string, args: unknown = {}, id = 'call-1') => ({
  id,
  name,
  arguments: JSON.stringify(args),
})

const MENU_CALL: ChatStep = {
  toolCalls: [tool('propoe_plano_dieta', { horizon: 'daily' })],
  promptTokens: 11_040,
  completionTokens: 86,
  costUsd: 0.0211,
  ms: 4_200,
}
const MENU_GENERATION: GeneratorStep = {
  content: MENU_OUTPUT,
  promptTokens: 912,
  completionTokens: 2_710,
  costUsd: 0.0434,
  ms: 36_500,
}
const WORKOUT_CALL: ChatStep = { toolCalls: [tool('propoe_plano_treino', WORKOUT_ARGS)], ms: 3_800 }
const WORKOUT_GENERATION: GeneratorStep = { content: WORKOUT_OUTPUT, ms: 41_000 }

/** A reply the premature-block guard refuses once (pipeline-mobile-flow-runtime.test.ts). */
const PREMATURE_BLOCK = 'Com o treino de hoje você fechou o segundo bloco completo!'

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
  // The generators and the tools log their own refusals.
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

// ── 1. Plan suggestion: one model call ──────────────────────────────────────
describe('audit 2026-10-04 Flow calls — a plan suggestion ends without the second model call', () => {
  it('"Sugira um cardápio completo para hoje": one model call, the stored suggestion, the draft stored once', async () => {
    const h = harness({
      chat: [MENU_CALL, { content: 'NUNCA CHAMADO' }],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h)

    expect(h.chatCalls).toHaveLength(1)
    expect(h.generatorCalls).toHaveLength(1)

    // The draft: stored once, for this turn, as a draft and nothing else.
    const [stored] = drafts(h)
    expect(drafts(h)).toHaveLength(1)
    expect(stored).toMatchObject({
      p_user_id: USER_ID,
      p_domain: 'nutrition',
      p_origin: 'flow_generated',
      p_status: 'ready_for_review',
      p_request_key: `${TURN_ID}:propoe_plano_dieta`,
      p_source_message_id: 'message-turn-0001',
    })
    expect(h.rpcs.map((call) => call.name)).toEqual(['create_plan_draft_atomic'])
    expect(events(h, 'diet.proposed')).toHaveLength(1)

    // The answer is the stored draft's text between the fixed opening and closing.
    const suggestion = nutritionSuggestionText(stored?.p_payload)
    expect(suggestion).toContain('Café da manhã (07:30) — 795 kcal, 41,1 g de proteína')
    expect(suggestion).toContain('• Frango grelhado: 150 g')
    // The totals read on the device; the target in brackets is the fixture
    // profile's (the tool computes it from the profile, as before).
    expect(suggestion).toContain('Total do dia: 2.884 kcal, 152,3 g de proteína (meta: ')
    expect(output.text).toBe(`${OPENING}\n\n${suggestion}\n\n${CLOSING}`)
    expect(output.text).not.toContain('NUNCA CHAMADO')

    // What the service hands to the app: the same shape as before.
    expect(output.toolCalls).toHaveLength(1)
    expect(output.toolCalls[0]).toMatchObject({
      name: 'propoe_plano_dieta',
      result: { success: true, draft_id: 'draft-0001', domain: 'nutrition', sugestao: suggestion },
    })
    expect(output.modelUsed).toBe(MODEL)
    expect(output.stage).toBe('ganho_massa')
    expect(output.interactive).toBeUndefined()
  })

  it('the text is the one the code already sent when the model paraphrased', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    const output = await flow(h)

    const shown = ensureSuggestionShown('Pronto! Montei um cardápio equilibrado.', output.toolCalls)
    expect(shown.replaced).toBe(true)
    expect(output.text).toBe(shown.text)
    expect(ensureSuggestionShown('', output.toolCalls).text).toBe(output.text)
  })

  it('"Pode ser equilibrado no geral.": the device workout turn never reaches the generic summary', async () => {
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL, { content: GENERIC_REPLY }],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(h.generatorCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    const [stored] = drafts(h)
    expect(stored).toMatchObject({
      p_domain: 'training',
      p_status: 'ready_for_review',
      p_request_key: `${TURN_ID}:propoe_plano_treino`,
    })
    expect(events(h, 'training.plan_proposed')).toHaveLength(1)

    const suggestion = trainingSuggestionText(stored?.p_payload)
    expect(suggestion).toContain('Segunda-feira — Full Body A (60 min)')
    expect(suggestion).toContain('• Agachamento livre — 3×12-15, descanso 90 s')
    expect(suggestion).toContain('• Tríceps francês com haltere — 2×12-15, descanso 60 s')
    expect(output.text).toBe(`${OPENING}\n\n${suggestion}\n\n${CLOSING}`)
    expect(output.text).not.toMatch(/6 exercícios|Revisar proposta|Proposta pronta/)
  })

  it('the turn writes the events it wrote before, minus the "rewritten" report of a model that was not asked', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    await flow(h)

    expect(eventNames(h)).toEqual(['diet.proposed', MOBILE_FLOW_CALLS_EVENT, 'llm.cache_usage'])
    // In particular: no phantom-write signal on the fixed text.
    expect(eventNames(h)).not.toContain('llm.fake_write_unresolved')
    expect(eventNames(h)).not.toContain('llm.plan_suggestion_rewritten')
  })

  it('a suggestion this very turn already stored (retry of a failed turn) is shown again, and not stored twice', async () => {
    const payload = JSON.parse(WORKOUT_OUTPUT) as Row
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL, { content: GENERIC_REPLY }],
      generator: [WORKOUT_GENERATION],
      drafts: {
        [`${TURN_ID}:propoe_plano_treino`]: {
          id: 'draft-earlier',
          status: 'ready_for_review',
          payload,
        },
      },
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(h.generatorCalls).toHaveLength(0)
    expect(drafts(h)).toHaveLength(0)
    expect(output.text).toBe(`${OPENING}\n\n${trainingSuggestionText(payload)}\n\n${CLOSING}`)
  })
})

// ── 2. Everything else keeps the model's answer ─────────────────────────────
describe('audit 2026-10-04 Flow calls — any other turn is answered by the model, as before', () => {
  it('a refused suggestion (the 24 h limit) is explained by the model', async () => {
    const apology = 'Já existe uma sugestão de treino de hoje. Você pode revisá-la no app.'
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL, { content: apology }],
      generator: [WORKOUT_GENERATION],
      pastEvents: ['training.plan_proposed'],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.generatorCalls).toHaveLength(0)
    expect(drafts(h)).toHaveLength(0)
    expect(output.text).toBe(apology)
  })

  it('a generator that fails is explained by the model', async () => {
    const apology = 'Não consegui criar a sugestão agora. Tenta de novo em alguns minutos?'
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL, { content: apology }],
      generator: [{ content: 'sem json' }],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(2)
    expect(drafts(h)).toHaveLength(0)
    expect(output.text).toBe(apology)
    expect(output.text).not.toContain(OPENING)
  })

  it('arguments the tool refuses are answered by the model', async () => {
    const question = 'Em qual lugar você treina: academia completa, academia limitada ou em casa?'
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [
        { toolCalls: [tool('propoe_plano_treino', { ...WORKOUT_ARGS, location: null })] },
        { content: question },
      ],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.generatorCalls).toHaveLength(0)
    expect(output.text).toBe(question)
  })

  it('a read tool in the same turn: the model writes the reply, and a faithful one stays as written', async () => {
    const consulta = vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const h = harness({
      chat: [
        {
          toolCalls: [
            tool('consulta_progresso', {}, 'call-0'),
            tool('propoe_plano_dieta', { horizon: 'daily' }),
          ],
        },
        { content: 'PLACEHOLDER' },
      ],
      generator: [MENU_GENERATION],
    })
    // The model copies the suggestion and adds a sentence of its own.
    const original = h.deps.llm.complete.bind(h.deps.llm)
    let faithful = ''
    h.deps.llm.complete = async (params) => {
      const result = await original(params)
      if (result.content !== 'PLACEHOLDER') return result
      const suggestion = nutritionSuggestionText(drafts(h)[0]?.p_payload)
      faithful = `Sua sugestão está pronta!\n\n${suggestion}\n\nVocê ainda está longe da meta de hoje, então ela cobre o dia inteiro. Toque em "Revisar sugestão" para conferir.`
      return { ...result, content: faithful }
    }
    const output = await flow(h)

    expect(consulta).toHaveBeenCalledOnce()
    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(faithful)
    expect(eventNames(h)).not.toContain('llm.plan_suggestion_rewritten')
  })

  it('a suggestion that came without text is announced by the model', async () => {
    vi.spyOn(propoePlanoTreino, 'execute').mockResolvedValue({
      success: true,
      draft_id: 'draft-0002',
      domain: 'training',
      status: 'needs_completion',
      message: 'instrução',
    })
    const announcement =
      'Sua sugestão está pronta. Toque em "Revisar sugestão" para conferir, completar o que faltar e confirmar.'
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL, { content: announcement }],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(announcement)
  })

  it('a guard retry earlier in the turn keeps the model in charge of the reply', async () => {
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [{ content: PREMATURE_BLOCK }, WORKOUT_CALL, { content: 'PLACEHOLDER' }],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    // Refused reply, tool call, reply: the third call is the model's.
    expect(h.chatCalls).toHaveLength(3)
    expect(eventNames(h)).toContain('llm.premature_block_completion')
    // It did not reproduce the suggestion, so the stored text replaces it —
    // through the path that reports it.
    expect(output.text).toBe(
      `${OPENING}\n\n${trainingSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    expect(eventNames(h)).toContain('llm.plan_suggestion_rewritten')
  })

  it('WhatsApp has no suggestion tool: the call is refused and the model answers', async () => {
    const h = harness({
      channel: 'whatsapp',
      chat: [MENU_CALL, { content: 'Resposta do WhatsApp.' }],
      generator: [MENU_GENERATION],
    })
    const output = await whatsapp(h)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.generatorCalls).toHaveLength(0)
    expect(drafts(h)).toHaveLength(0)
    expect(output.toolCalls).toEqual([
      { name: 'propoe_plano_dieta', arguments: {}, error: 'tool_not_authorized' },
    ])
    expect(output.text).toBe('Resposta do WhatsApp.')
    expect(eventNames(h)).not.toContain(MOBILE_FLOW_CALLS_EVENT)
  })

  it.each([
    ['no tool call', [], false],
    [
      'one suggestion with its text',
      [{ name: 'propoe_plano_dieta', result: { success: true, sugestao: 'x' } }],
      true,
    ],
    [
      'two suggestions with their texts',
      [
        { name: 'propoe_plano_treino', result: { success: true, sugestao: 'x' } },
        { name: 'propoe_plano_dieta', result: { success: true, sugestao: 'y' } },
      ],
      true,
    ],
    [
      'a failed suggestion',
      [{ name: 'propoe_plano_dieta', result: { success: false, error: 'x' } }],
      false,
    ],
    [
      'a suggestion without text',
      [{ name: 'propoe_plano_dieta', result: { success: true } }],
      false,
    ],
    [
      'a suggestion with an empty text',
      [{ name: 'propoe_plano_dieta', result: { success: true, sugestao: '' } }],
      false,
    ],
    ['a call that threw', [{ name: 'propoe_plano_dieta', error: 'boom' }], false],
    [
      'a refused call',
      [{ name: 'propoe_plano_dieta', arguments: {}, error: 'tool_not_authorized' }],
      false,
    ],
    ['a result that is not an object', [{ name: 'propoe_plano_dieta', result: null }], false],
    [
      'a read tool next to the suggestion',
      [
        { name: 'consulta_progresso', result: { success: true } },
        { name: 'propoe_plano_dieta', result: { success: true, sugestao: 'x' } },
      ],
      false,
    ],
    [
      'one of two suggestions failed',
      [
        { name: 'propoe_plano_treino', result: { success: true, sugestao: 'x' } },
        { name: 'propoe_plano_dieta', result: { success: false } },
      ],
      false,
    ],
    [
      'the WhatsApp generator',
      [{ name: 'gera_dieta', result: { success: true, sugestao: 'x' } }],
      false,
    ],
  ] as const)('the turn predicate — %s: %s', (_label, calls, expected) => {
    expect(isPurePlanSuggestionTurn(calls)).toBe(expected)
  })
})

// ── 2b. A message that asks for the plan AND something else ─────────────────
describe('audit 2026-10-04 Flow calls — only a single request is answered with the suggestion alone', () => {
  const DIET = tool('propoe_plano_dieta', { horizon: 'daily' })
  const WORKOUT = tool('propoe_plano_treino', WORKOUT_ARGS)

  // The mixed messages of the reviews of 2026-10-04, with the reviewers'
  // model script: the model calls only the plan tool, and on the second call
  // copies the suggestion and answers the other question. With the direct
  // path reading only the tools, each ended after one call with the
  // suggestion alone and not a word about the second question.
  const MIXED = [
    {
      label: 'review 1, scenario 19 (menu + protein, two sentences)',
      text: 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?',
      call: DIET,
      generation: MENU_GENERATION,
      other: 'Sobre a proteína de hoje: você está em 59 g de 144 g, faltam 85 g.',
    },
    {
      label: 'review 1, scenario 21 (workout + knee pain)',
      text: 'Monta meu treino de 3 dias na academia, sou iniciante. Posso treinar perna com dor no joelho?',
      call: WORKOUT,
      generation: WORKOUT_GENERATION,
      other:
        'Sobre o joelho: com dor, evite carga em agachamento e procure avaliação antes de treinar perna.',
    },
    {
      label: 'review 3, scenario 12 (menu + protein, one sentence ending in "?")',
      text: 'Sugira um cardápio completo para hoje e me diga quanto de proteína ainda falta hoje?',
      call: DIET,
      generation: MENU_GENERATION,
      other: 'Sobre a proteína: você está em 59 g de 144 g, faltam 85 g hoje.',
    },
  ]

  it.each(MIXED)('$label — "$text": two model calls, and the other question is answered', async ({
    text,
    call,
    generation,
    other,
  }) => {
    const h = harness({
      text,
      chat: [{ toolCalls: [call] }, { copySuggestion: other }],
      generator: [generation],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.generatorCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)

    // The stored suggestion is in the answer, whole, and so is the answer to
    // the other question: the model's reply is kept as it wrote it.
    const stored = drafts(h)[0]?.p_payload
    const suggestion =
      call.name === 'propoe_plano_dieta'
        ? nutritionSuggestionText(stored)
        : trainingSuggestionText(stored)
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${suggestion}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.\n\n${other}`,
    )
    expect(output.text).toContain(other)
    expect(eventNames(h)).not.toContain('llm.plan_suggestion_rewritten')
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).not.toHaveProperty(
      'plan_suggestion_direct',
    )
  })

  it('review 1, scenario 22 — the model wrote text next to the tool call: the second call is made and reads that text', async () => {
    const text = 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?'
    const aside = 'Faltam 85 g de proteína hoje (59 g de 144 g). Vou montar a sugestão.'
    const other = 'Sobre a proteína de hoje: faltam 85 g.'
    const h = harness({
      text,
      chat: [{ content: aside, toolCalls: [DIET] }, { copySuggestion: other }],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.chatCalls[1]?.messages).toContainEqual(
      expect.objectContaining({ role: 'assistant', content: aside }),
    )
    expect(output.text).toContain(other)
    expect(output.text).toContain(nutritionSuggestionText(drafts(h)[0]?.p_payload))
  })

  it('review 3, scenario 13 — the question comes first and the model answers it next to the tool call: two calls', async () => {
    const text = 'Quanto de proteína falta hoje? E sugira um cardápio completo para hoje'
    const aside = 'Você está em 59 g de 144 g de proteína: faltam 85 g hoje. Vou montar o cardápio.'
    const h = harness({
      text,
      chat: [{ content: aside, toolCalls: [DIET] }, { copySuggestion: true }],
      generator: [MENU_GENERATION],
    })
    await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.chatCalls[1]?.messages).toContainEqual(
      expect.objectContaining({ role: 'assistant', content: aside }),
    )
  })

  it('the baseline phrase with a sentence of the model next to the tool call: the model finishes its own answer', async () => {
    const h = harness({
      chat: [
        { content: 'Vou montar seu cardápio de hoje.', toolCalls: [DIET] },
        { copySuggestion: true },
      ],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toContain('Sua sugestão está pronta!')
  })

  it('a mixed message whose second call paraphrases the suggestion gets the stored text, as before the change', async () => {
    const { text, call, generation } = MIXED[0] as (typeof MIXED)[number]
    const h = harness({
      text,
      chat: [{ toolCalls: [call] }, { content: 'Montei um cardápio equilibrado. Faltam 85 g.' }],
      generator: [generation],
    })
    const output = await flow(h, text)

    // The chat never shows a plan other than the stored draft (audit 09-30);
    // the model's own sentence goes with the paraphrase. See RC PERF-C11.
    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    expect(eventNames(h)).toContain('llm.plan_suggestion_rewritten')
  })

  it.each([
    // The two baseline requests of the report: one call each (section 1).
    [MENU_PHRASE, true],
    ['Sugira um cardapio completo para hoje', true],
    [WORKOUT_PHRASE, true],
    // Greetings, thanks and emoji are words of the list or no word at all.
    ['Sugira um cardápio completo para hoje, por favor.', true],
    ['Sugira um cardápio completo para hoje. Obrigado!', true],
    ['Sugira um cardápio completo para hoje.\nPor favor', true],
    ['Monta meu treino. Valeu', true],
    ['Oi, monte um cardápio pra hoje', true],
    ['Oi! Monte um cardápio pra hoje', true],
    ['Bom dia\nMonte um cardápio pra hoje', true],
    ['Monte um cardápio pra hoje, obrigado 🙏', true],
    ['monte um cardapio pra hoje. valeu!!', true],
    ['Monte um cardápio pra hoje… obrigado', true],
    ['Monta meu treino de 3 dias na academia', true],
    ['Quero um plano alimentar novo para a semana', true],
    ['Flow, me dá um treino simples pra fazer em casa 3 vezes por semana, pfv', true],
    ['Agora monte um cardápio para hoje', true],
    // The mixed messages of the first review.
    ['Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?', false],
    [
      'Monta meu treino de 3 dias na academia, sou iniciante. Posso treinar perna com dor no joelho?',
      false,
    ],
    ['Sugira um cardápio completo para hoje e me diga quanto de proteína ainda falta hoje?', false],
    ['Quanto de proteína falta hoje? E sugira um cardápio completo para hoje', false],
    // The second review: a second request in the same sentence, no "?".
    ['Monte um cardápio pra hoje, quanto falta de proteína hoje', false],
    ['Quanto falta de proteína hoje, e monta um cardápio pra hoje', false],
    ['monta um cardapio pra hj tb quero saber quanto de proteina falta', false],
    ['Monte um cardápio pra hoje e me diga quanto falta de proteína', false],
    ['Please suggest a full menu for today and tell me how much protein I have left', false],
    ['Please suggest a full menu for today. Also tell me how much protein I have left', false],
    ['Monte um cardápio pra hoje - e quanto de proteína falta hoje', false],
    ['Quero um cardápio pra hoje e também saber se posso tomar creatina', false],
    ['Monte um cardápio para hoje (e me diga quanta proteína falta)', false],
    ['Monte um cardápio pra hoje\nSem lactose', false],
    ['Monte um cardápio pra hoje: sou alérgico a camarão', false],
    ['Treinei pesado hoje. Monte um cardápio pra hoje', false],
    ['Monte um cardápio pra hoje c/ aprox. 2.000 kcal', false],
    [
      'Monta meu treino de 3 dias na academia e me diz se posso treinar perna com dor no joelho',
      false,
    ],
    // A menu and a workout in one message are two requests.
    ['Sugira um cardápio e um treino', false],
    ['Monte um cardápio para hoje. Monte um treino também.', false],
    ['Quero uma dieta e exercícios para casa', false],
    // Two sentences with no question mark.
    ['Monte um cardápio para hoje. Me diga também quanta proteína falta', false],
    ['Monte um cardápio para hoje! Me diga também quanta proteína falta', false],
    ['Monte um cardápio para hoje; me diga também quanta proteína falta', false],
    ['Monte um cardápio para hoje\nMe diga também quanta proteína falta', false],
    ['Monte um cardápio para hoje… me diga também quanta proteína falta', false],
    ['Monte um cardápio para hoje.Me diga também quanta proteína falta', false],
    ['Sugira um cardápio completo para hoje. Agradeço desde já', false],
    // A question mark, the fullwidth one included, keeps the second call.
    ['Pode montar um cardápio para hoje?', false],
    ['Monte um cardápio pra hoje e quanto falta de proteína？', false],
    ['Pode montar um cardápio para hoje？', false],
    // The price of a closed list: a unit, English, a typo and an
    // abbreviation are unknown words, and the unknown goes to the model.
    ['Monte um cardápio de 2.000 kcal para hoje', false],
    ['Please suggest a full menu for today', false],
    ['Sugira um cardapio conpleto para hoje', false],
    ['monta um cardapio pra hj', false],
    // Third review — (b) two plans: "academia" next to a menu noun is the
    // workout, and a second noun outside the group is a second request.
    ['Monte uma dieta e um plano pra academia', false],
    ['Quero um cardápio e um plano de academia', false],
    ['quero dieta e academia', false],
    ['quero dieta academia', false],
    ['Monte um cardápio e um plano', false],
    ['Monte um cardápio um plano', false],
    ['Monte um cardápio pra hoje cardápio pra amanhã', false],
    ['Monte um cardápio pra hoje pra amanhã', false],
    ['Monte um treino de 3 dias na academia', true],
    ['Quero uma sugestão de cardápio para amanhã', true],
    ['Quero um plano novo de treino', true],
    // Third review — (c) "e" joins two requests, and so does punctuation
    // that sets apart anything but a greeting or thanks.
    ['Monte um cardápio para hoje e outro para amanhã', false],
    ['Monte um cardápio para hoje, outro para amanhã', false],
    ['Monte um cardápio para hoje. Outro para amanhã', false],
    ['Monte um cardápio para hoje\nOutro para amanhã', false],
    ['Monte um cardápio pra hoje mais um treino', false],
    ['Monte um cardápio pra hoje também', false],
    ['Monte um cardápio pra hoje tb', false],
    ['Monte um cardápio simples e rápido', false],
    ['Monte um cardápio pra hoje, por favor e obrigado', false],
    // Third review — (d) a reply that names no plan takes its meaning from
    // the Flow's previous line; a determiner standing for the noun does too.
    ['Quero', false],
    ['pode', false],
    ['Pode ser', false],
    ['manda', false],
    ['Quero, por favor', false],
    ['quero os 2', false],
    ['1 e 2', false],
    ['faz os 2', false],
    ['os 2', false],
    ['outro', false],
    ['Quero outra sugestão', false],
    ['Monte um plano', false],
    ['Monte um plano pra academia', false],
    ['Na academia', false],
    ['Em casa 3 vezes por semana', false],
    ['Monte um cardápio pra hoje outro pra amanhã', false],
    ['Monte o cardápio de hoje o de amanhã', false],
    ['Monte um treino pra casa outro pra academia', false],
    ['Monte um cardápio simples um completo', false],
    ['Quero o cardápio de hoje o da semana', false],
    ['Quero o treino de amanhã', true],
    ['Quero outro cardápio', true],
    // The exact reply of the device workout turn, and nothing near it.
    ['Pode ser equilibrado no geral', true],
    ['Pode ser equilibrado', false],
    ['Pode ser equilibrada no geral', false],
    ['no geral pode ser equilibrado', false],
    ['o treino de hoje pode ser em casa', false],
    ['Pode ser em casa 3 vezes por semana', false],
    // A number counts days or times; any other number is a condition.
    ['Monte um treino de 4 dias', true],
    ['Monte um cardápio de 1500', false],
    ['nova dieta de 2000 por dia', false],
    // Nothing to read is not a request.
    ['', false],
    ['   ', false],
    ['🙏', false],
  ])('the message gate — %j is a single request: %s', (message, expected) => {
    expect(isSingleRequestMessage(message)).toBe(expected)
  })

  it('the message gate treats null and undefined as nothing to read', () => {
    expect(isSingleRequestMessage(null)).toBe(false)
    expect(isSingleRequestMessage(undefined)).toBe(false)
  })

  // The list is closed: a word added to it widens the one-call path, and
  // must show up here.
  it('the closed list is exactly these words (accents removed)', () => {
    expect([...SINGLE_REQUEST_VOCABULARY].sort()).toEqual(
      [
        // request verbs
        ...['monte', 'monta', 'montar', 'sugira', 'sugere', 'sugerir', 'crie', 'cria', 'criar'],
        ...['faca', 'faz', 'fazer', 'gere', 'gera', 'gerar', 'prepare', 'quero', 'queria'],
        ...['preciso', 'pode', 'poderia', 'consegue', 'me', 'da', 'passa', 'manda'],
        // plan nouns
        ...['sugestao', 'cardapio', 'dieta', 'menu', 'plano', 'alimentar', 'alimentacao'],
        ...['refeicoes', 'treino', 'treinos', 'exercicios'],
        // qualifiers
        ...['completo', 'completa', 'novo', 'nova', 'simples', 'rapido', 'outro', 'outra'],
        // time and place
        ...['hoje', 'amanha', 'agora', 'semana', 'dia', 'dias', 'vezes', 'por', 'na', 'em'],
        ...['casa', 'academia'],
        // articles, prepositions, pronouns
        ...['um', 'uma', 'o', 'a', 'os', 'as', 'de', 'do', 'para', 'pra', 'pro'],
        ...['meu', 'minha', 'mim'],
        // courtesy
        ...['oi', 'ola', 'bom', 'boa', 'tarde', 'noite', 'favor', 'pf', 'pfv'],
        ...['obrigado', 'obrigada', 'valeu', 'flow'],
      ].sort(),
    )
    // "e" joins two requests, and the words of the device workout reply
    // opened "Pode ser" and "pode ser em casa": none is a word of the list.
    for (const word of ['e', 'mais', 'tambem', 'tb', 'ser', 'equilibrado', 'no', 'geral']) {
      expect(SINGLE_REQUEST_VOCABULARY.has(word), word).toBe(false)
    }
  })

  // The one reply that is a single request without naming a plan, whole.
  it('the exact replies are exactly this one phrase', () => {
    expect([...SINGLE_REQUEST_EXACT_REPLIES]).toEqual(['pode ser equilibrado no geral'])
    expect(isSingleRequestMessage(WORKOUT_PHRASE)).toBe(true)
  })

  // What RC PERF-C10 used to declare as not covered: "e" was a word of the
  // list and the message counted as one request. Now the second call is made
  // and it is where the other menu gets its answer.
  it.each([
    2, 5,
  ])('"Monte um cardápio para hoje e outro para amanhã" (config %i): two calls, and the model answers about the other menu', async (config) => {
    const text = 'Monte um cardápio para hoje e outro para amanhã'
    const other = 'O de amanhã eu monto em seguida.'
    expect(isSingleRequestMessage(text)).toBe(false)

    const h = harness({
      text,
      chat: [{ toolCalls: [DIET] }, { copySuggestion: other }],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.\n\n${other}`,
    )
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).not.toHaveProperty(
      'plan_suggestion_direct',
    )
  })

  // Declared, not fixed (RC PERF-C10, 1): two requests of the SAME kind in
  // one clause, with no "e", no punctuation, no pronoun and no second noun,
  // are read as one request (the gate reads words, not meaning). Locked so
  // the pendency is not read as covered.
  it('RC PERF-C10 (not covered) — "Monte um cardápio pra hoje pra semana" still ends with the one suggestion the model stored', async () => {
    const text = 'Monte um cardápio pra hoje pra semana'
    expect(isSingleRequestMessage(text)).toBe(true)

    const h = harness({
      text,
      chat: [{ toolCalls: [DIET] }, { copySuggestion: 'O da semana eu monto em seguida.' }],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  const ENGLISH_PATIENT = { ...USER, country: 'US', locale: 'en-US', timezone: 'America/New_York' }

  // The English request is outside the closed list: the model answers, and
  // its own frame (in the patient's language) is what the chat shows.
  it('"Please suggest a full menu for today": the second call is made and the reply of the model is kept', async () => {
    const text = 'Please suggest a full menu for today'
    const reply = (suggestion: string) =>
      `Your suggestion is ready:\n\n${suggestion}\n\nTap "Review suggestion" to check, adjust and confirm it.`
    const h = harness({
      text,
      user: ENGLISH_PATIENT,
      chat: [{ toolCalls: [DIET] }, { replyFrom: reply }],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(reply(nutritionSuggestionText(drafts(h)[0]?.p_payload)))
    expect(output.text).not.toContain(OPENING)
  })

  // Declared, not fixed: when the model paraphrases, the fixed opening and
  // closing are Portuguese for every patient, as before this change (no new
  // patient-facing sentence was allowed).
  it('RC PERF-C12 (not covered) — a patient who writes in English and whose suggestion the model paraphrases gets the fixed frame in Portuguese', async () => {
    const text = 'Please suggest a full menu for today'
    const h = harness({
      text,
      user: ENGLISH_PATIENT,
      chat: [{ toolCalls: [DIET] }, { content: 'Your menu for today is ready.' }],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text.startsWith(`${OPENING}\n\n`)).toBe(true)
    expect(output.text.endsWith(CLOSING)).toBe(true)
  })
})

// ── 2c. Second review: a second request in the SAME sentence ────────────────
describe('audit 2026-10-04 Flow calls — second review: a wording outside the closed list keeps the second model call', () => {
  const DIET = tool('propoe_plano_dieta', { horizon: 'daily' })
  const WORKOUT = tool('propoe_plano_treino', WORKOUT_ARGS)
  const PROTEIN = 'Sobre a proteína de hoje: você está em 59 g de 144 g, faltam 85 g.'

  // The reviewer's messages, word for word, with the reviewer's model script:
  // the model calls only the plan tool, with no text, and on the second call
  // copies the suggestion and answers the other part. With the gate reading
  // punctuation each ended after ONE call with the suggestion alone; at the
  // parent commit each had two calls and the other answer.
  const SAME_SENTENCE = [
    { label: 'a comma, no "?"', text: 'Monte um cardápio pra hoje, quanto falta de proteína hoje' },
    {
      label: 'the question first',
      text: 'Quanto falta de proteína hoje, e monta um cardápio pra hoje',
    },
    {
      label: '"tb quero saber", no punctuation',
      text: 'monta um cardapio pra hj tb quero saber quanto de proteina falta',
    },
    {
      label: '"e me diga"',
      text: 'Monte um cardápio pra hoje e me diga quanto falta de proteína',
    },
    {
      label: 'English',
      text: 'Please suggest a full menu for today and tell me how much protein I have left',
    },
  ]

  it.each(
    SAME_SENTENCE.flatMap((message) => [2, 5].map((config) => ({ ...message, config }))),
  )('$label, config $config — "$text": two model calls, and the other part is answered', async ({
    text,
    config,
  }) => {
    expect(isSingleRequestMessage(text)).toBe(false)
    const h = harness({
      text,
      chat: [{ toolCalls: [DIET] }, { copySuggestion: PROTEIN }],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.generatorCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.\n\n${PROTEIN}`,
    )
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).not.toHaveProperty(
      'plan_suggestion_direct',
    )
  })

  // The example RC PERF-C10 used to declare as not covered.
  it('"Monta meu treino de 3 dias na academia e me diz se posso treinar perna com dor no joelho": two calls, the knee is answered', async () => {
    const text =
      'Monta meu treino de 3 dias na academia e me diz se posso treinar perna com dor no joelho'
    const knee = 'Sobre o joelho: evite carga.'
    const h = harness({
      text,
      chat: [{ toolCalls: [WORKOUT] }, { copySuggestion: knee }],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toContain(trainingSuggestionText(drafts(h)[0]?.p_payload))
    expect(output.text.endsWith(knee)).toBe(true)
  })

  // The reviewer's two-plan turn: the model calls one tool per iteration. At
  // the parent commit both drafts were stored and both suggestions shown
  // (2 calls under config 2, 3 under config 5); with the gate reading
  // punctuation the turn stopped after the menu, with not a word about the
  // workout. Now: both drafts, both suggestions, and the closing call.
  it.each([
    2, 5,
  ])('"Sugira um cardápio e um treino", one tool per iteration (config %i): both drafts are stored and both suggestions delivered', async (config) => {
    const text = 'Sugira um cardápio e um treino'
    const h = harness({
      text,
      chat: [
        { toolCalls: [DIET] },
        { toolCalls: [tool('propoe_plano_treino', WORKOUT_ARGS, 'call-2')] },
        { content: 'Suas sugestões estão prontas.' },
      ],
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.generatorCalls).toHaveLength(2)
    expect(drafts(h).map((draft) => draft.p_domain)).toEqual(['nutrition', 'training'])
    const [menu, workout] = drafts(h)
    // The text the parent commit gave this turn (ensureSuggestionShown).
    expect(output.text).toBe(
      `Suas sugestões estão prontas:\n\n${nutritionSuggestionText(menu?.p_payload)}\n\n${trainingSuggestionText(workout?.p_payload)}\n\n${CLOSING}`,
    )
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
  })

  it('"Sugira um cardápio e um treino", both tools in one call: the second call is made, as before', async () => {
    const text = 'Sugira um cardápio e um treino'
    const h = harness({
      text,
      chat: [
        { toolCalls: [DIET, tool('propoe_plano_treino', WORKOUT_ARGS, 'call-2')] },
        { content: 'Suas sugestões estão prontas.' },
      ],
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(drafts(h)).toHaveLength(2)
    expect(output.text.startsWith('Suas sugestões estão prontas:\n\n')).toBe(true)
  })

  // What still gets the one-call path: the two baseline requests (section 1)
  // and plain variants of them, written only with words of the list.
  it.each([
    ['Sugira um cardapio completo para hoje', DIET, MENU_GENERATION],
    ['Oi, monte um cardápio pra hoje', DIET, MENU_GENERATION],
    ['Bom dia! Sugira um cardápio completo para hoje, por favor', DIET, MENU_GENERATION],
    ['Monte um cardápio pra hoje, obrigado 🙏', DIET, MENU_GENERATION],
    ['Monta meu treino de 3 dias na academia. Valeu', WORKOUT, WORKOUT_GENERATION],
  ])('%j: one model call, the stored suggestion', async (text, call, generation) => {
    const h = harness({
      text,
      chat: [{ toolCalls: [call] }, { content: 'NUNCA CHAMADO' }],
      generator: [generation],
      configIterations: 5,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(1)
    const stored = drafts(h)[0]?.p_payload
    const suggestion =
      call.name === 'propoe_plano_dieta'
        ? nutritionSuggestionText(stored)
        : trainingSuggestionText(stored)
    expect(output.text).toBe(`${OPENING}\n\n${suggestion}\n\n${CLOSING}`)
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).toMatchObject({
      plan_suggestion_direct: 1,
    })
  })
})

// ── 2d. Third review: two plans, and a reply that names no plan ─────────────
describe('audit 2026-10-04 Flow calls — third review: two plans in one message, and a reply that names no plan, keep the model in charge', () => {
  const DIET = tool('propoe_plano_dieta', { horizon: 'daily' })
  const WORKOUT = tool('propoe_plano_treino', WORKOUT_ARGS, 'call-2')
  /** The reviewer's model: one plan tool per iteration, no text, then one line. */
  const ONE_TOOL_PER_ITERATION: ChatStep[] = [
    { toolCalls: [DIET] },
    { toolCalls: [WORKOUT] },
    { content: 'Suas sugestões estão prontas.' },
  ]
  const CONFIGS = [2, 5] as const

  /** The history of the reviewer's probe: six lines, one minute apart. */
  const line = (
    direction: 'in' | 'out',
    content: string,
    secondsAgo: number,
    index: number,
  ): Row => ({
    direction,
    content,
    content_type: 'text',
    created_at: new Date(NOW.getTime() - secondsAgo * 1_000).toISOString(),
    provider_message_id: `mobile_flow/qa-a/h${index}`,
  })
  /** Those six lines, then `offer` as the Flow's last line, 30 s before the turn. */
  const afterFlowLine = (offer: string): Row[] => [
    ...Array.from({ length: 6 }, (_, index) =>
      index % 2 === 0
        ? line('in', `Pergunta ${index}`, (6 - index) * 60, index)
        : line('out', `Resposta ${index}: tudo certo por aqui.`, (6 - index) * 60, index),
    ),
    line('out', offer, 30, 99),
  ]

  const bothSuggestions = (h: Harness): string => {
    const [menu, workout] = drafts(h)
    // The text the parent commit gave these turns (ensureSuggestionShown).
    return `Suas sugestões estão prontas:\n\n${nutritionSuggestionText(menu?.p_payload)}\n\n${trainingSuggestionText(workout?.p_payload)}\n\n${CLOSING}`
  }

  // HIGH. The reviewer's three messages, word for word. "academia" was a
  // word of the list and not a workout noun, and "plano" names no kind: each
  // message counted as ONE request, the turn ended after the menu, and the
  // workout was dropped without a word. At the parent commit both drafts
  // were stored and both suggestions shown (2 calls under config 2, 3 under
  // config 5).
  const TWO_PLANS = [
    'Monte uma dieta e um plano pra academia',
    'Quero um cardápio e um plano de academia',
    'quero dieta e academia',
  ]

  it.each(
    TWO_PLANS.flatMap((text) => CONFIGS.map((config) => ({ text, config }))),
  )('"$text", one tool per iteration (config $config): both drafts are stored, both suggestions delivered, the closing call made with the tools off', async ({
    text,
    config,
  }) => {
    expect(isSingleRequestMessage(text)).toBe(false)
    const h = harness({
      text,
      chat: ONE_TOOL_PER_ITERATION,
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.generatorCalls).toHaveLength(2)
    expect(drafts(h).map((draft) => draft.p_domain)).toEqual(['nutrition', 'training'])
    expect(output.text).toBe(bothSuggestions(h))
    expect(output.text).toContain('Café da manhã (07:30)')
    expect(output.text).toContain('• Agachamento livre — 3×12-15, descanso 90 s')
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as { calls: Row[] }
    expect(properties).not.toHaveProperty('plan_suggestion_direct')
    expect(properties.calls.map((call) => call.closing)).toEqual([undefined, undefined, 1])
  })

  it('"Monte uma dieta e um plano pra academia", both tools in one call: the second call is made, as before', async () => {
    const text = 'Monte uma dieta e um plano pra academia'
    const h = harness({
      text,
      chat: [{ toolCalls: [DIET, WORKOUT] }, { content: 'Suas sugestões estão prontas.' }],
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(bothSuggestions(h))
  })

  // "academia" as the place of ONE workout is still one request.
  it('"Monta meu treino de 3 dias na academia": one model call, the stored workout', async () => {
    const text = 'Monta meu treino de 3 dias na academia'
    const h = harness({
      text,
      chat: [{ toolCalls: [WORKOUT] }, { content: 'NUNCA CHAMADO' }],
      generator: [WORKOUT_GENERATION],
      configIterations: 5,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${trainingSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  // MEDIUM (a). The Flow's previous line offered two plans and the patient
  // accepts both with a reply that names neither. Every word (or number) of
  // these replies was accepted, so the turn ended after the menu. At the
  // parent commit: both drafts and both suggestions.
  const OFFER_OF_TWO_PLANS =
    'Posso montar: 1) um cardápio para hoje; 2) um treino para a semana. Qual você prefere?'

  it.each(
    ['quero os 2', '1 e 2', 'faz os 2'].flatMap((text) =>
      CONFIGS.map((config) => ({ text, config })),
    ),
  )('after "Posso montar: 1) um cardápio para hoje; 2) um treino para a semana. Qual você prefere?", "$text" (config $config): both drafts and both suggestions', async ({
    text,
    config,
  }) => {
    expect(isSingleRequestMessage(text)).toBe(false)
    const h = harness({
      text,
      history: afterFlowLine(OFFER_OF_TWO_PLANS),
      chat: ONE_TOOL_PER_ITERATION,
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    // The model read the offer the reply answers.
    expect(h.chatCalls[0]?.messages).toContainEqual(
      expect.objectContaining({ role: 'assistant', content: OFFER_OF_TWO_PLANS }),
    )
    expect(drafts(h).map((draft) => draft.p_domain)).toEqual(['nutrition', 'training'])
    expect(output.text).toBe(bothSuggestions(h))
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
  })

  // MEDIUM (b). The Flow's previous line offered a menu AND an explanation,
  // and the patient says yes. The model calls only the menu tool, and on its
  // second call copies the suggestion and explains the protein. The replies
  // made of words of the list ended after one call, with the suggestion
  // alone. ("sim" and "Sim, quero" already took the second call.)
  const OFFER_OF_MENU_AND_EXPLANATION =
    'Posso montar um cardápio para amanhã e também te explicar como bater a proteína de hoje. Quer?'
  const EXPLANATION =
    'Para bater a proteína de hoje faltam 85 g: um frango grelhado no jantar resolve.'

  it.each(
    ['Quero', 'pode', 'Pode ser', 'manda', 'Quero, por favor', 'sim', 'Sim, quero'].flatMap(
      (text) => CONFIGS.map((config) => ({ text, config })),
    ),
  )('after "Posso montar um cardápio para amanhã e também te explicar como bater a proteína de hoje. Quer?", "$text" (config $config): two calls, and the explanation is in the answer', async ({
    text,
    config,
  }) => {
    expect(isSingleRequestMessage(text)).toBe(false)
    const h = harness({
      text,
      history: afterFlowLine(OFFER_OF_MENU_AND_EXPLANATION),
      chat: [{ toolCalls: [DIET] }, { copySuggestion: EXPLANATION }],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(2)
    expect(h.chatCalls[0]?.messages).toContainEqual(
      expect.objectContaining({ role: 'assistant', content: OFFER_OF_MENU_AND_EXPLANATION }),
    )
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.\n\n${EXPLANATION}`,
    )
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).not.toHaveProperty(
      'plan_suggestion_direct',
    )
  })

  // A reply that names its plan is a request of its own, whatever the offer.
  it('after the offer of two plans, "Quero o treino": one model call, the stored workout', async () => {
    const text = 'Quero o treino'
    const h = harness({
      text,
      history: afterFlowLine(OFFER_OF_TWO_PLANS),
      chat: [{ toolCalls: [WORKOUT] }, { content: 'NUNCA CHAMADO' }],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${trainingSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  // Declared, not fixed (RC PERF-C10, 2): the one reply kept as an exact
  // phrase still ends on the first suggestion when the Flow's previous line
  // offered two plans and the model calls one tool per iteration. Locked so
  // the pendency is not read as covered.
  it('RC PERF-C10 (not covered) — "Pode ser equilibrado no geral." after a Flow line that offered a menu and a workout still ends on the first suggestion', async () => {
    const offer =
      'Posso montar um cardápio para hoje e um treino para a semana. O treino pode ser equilibrado no geral ou com foco em alguma região?'
    const h = harness({
      text: WORKOUT_PHRASE,
      history: afterFlowLine(offer),
      chat: ONE_TOOL_PER_ITERATION,
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(drafts(h).map((draft) => draft.p_domain)).toEqual(['nutrition'])
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })
})

// ── 3. At most two tool iterations, and the turn still ends with words ──────
describe('audit 2026-10-04 Flow calls — two tool iterations at most, then one closing call with the tools switched off', () => {
  /** A model that asks for a read tool on every call, the closing one included. */
  const ALWAYS_A_TOOL: ChatStep[] = [{ toolCalls: [tool('consulta_metricas')] }]

  it('the cap is 2', () => {
    expect(MOBILE_FLOW_MAX_MODEL_ITERATIONS).toBe(2)
  })

  it.each([
    ['the database default (5), the row production shares with WhatsApp', 5, undefined, 2],
    ['a larger number', 12, undefined, 2],
    ['the staging QA config (2)', 2, undefined, 2],
    ['a smaller number is respected', 1, undefined, 1],
    ['no config, the caller default (3)', null, 3, 2],
    ['no config and no caller default (5)', null, undefined, 2],
  ])('Flow, %s (config %s, caller default %s): at most %i tool iterations, then the closing call', async (_label, configIterations, depsIterations, expected) => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: ALWAYS_A_TOOL,
      configIterations,
      ...(depsIterations === undefined ? {} : { depsIterations }),
    })
    const output = await flow(h, 'Quais são minhas métricas?')

    // The capped tool iterations, then exactly one call that may not use a tool.
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([
      ...Array.from({ length: expected }, () => undefined),
      'none',
    ])
    // The tool the scripted model still asks for on the closing call is not run.
    expect(output.toolCalls).toHaveLength(expected)
  })

  it.each([
    ['the database default (5)', 5, 5],
    ['a larger number', 12, 12],
    ['a smaller number', 1, 1],
  ])('WhatsApp keeps the configured number and gets no closing call — %s', async (_label, configIterations, expected) => {
    const h = harness({
      channel: 'whatsapp',
      text: 'Quais são minhas métricas?',
      chat: ALWAYS_A_TOOL,
      configIterations,
    })
    await whatsapp(h, 'Quais são minhas métricas?')

    expect(h.chatCalls).toHaveLength(expected)
    for (const call of h.chatCalls) expect(call.keys).not.toContain('toolChoice')
  })

  it('a guard retry still gets its own iteration under the cap (config 5)', async () => {
    const corrected = 'Seu bloco atual está em andamento; ele só é creditado no fechamento do dia.'
    const h = harness({
      text: 'Mostre meu progresso recente.',
      chat: [
        { toolCalls: [tool('consulta_metricas')] },
        { content: PREMATURE_BLOCK },
        { content: corrected },
        { content: 'nunca chamado' },
      ],
      configIterations: 5,
    })
    const output = await flow(h, 'Mostre meu progresso recente.')

    expect(h.chatCalls).toHaveLength(3)
    expect(output.text).toBe(corrected)
    // The model answered inside its iterations: no closing call was needed.
    for (const call of h.chatCalls) expect(call.keys).not.toContain('toolChoice')
  })

  // The three turns the reviews of 2026-10-04 ran, message and script exact:
  // a tool, then another tool, then the answer. At the parent commit the
  // Flow answered them on the third call wherever the config allowed 3 or
  // more; with the cap alone they ended with an empty text after two paid
  // calls (502 in the service).
  const TOOL_TOOL_ANSWER = [
    {
      label: 'review 3, scenario 10',
      text: 'Qual e o meu gasto diario, e como foi minha semana?',
      second: tool('consulta_resumo_periodo', { days: 7 }, 'call-2'),
      answer: 'Seu gasto diário estimado é de 2.800 kcal e a semana fechou em 2.750 kcal de média.',
    },
    {
      label: 'review 1',
      text: 'Como foi minha semana comparada com hoje?',
      second: tool('consulta_progresso', {}, 'call-2'),
      answer: 'Sua semana foi boa: média de 2.700 kcal.',
    },
    {
      label: 'review 2',
      text: 'Como foi minha semana e qual minha taxa basal?',
      second: tool('consulta_resumo_periodo', { periodo: 'semana' }, 'call-2'),
      answer: 'Sua semana ficou perto da meta e sua basal é 1.488 kcal.',
    },
  ]
  const CONFIGS = [5, 3, 2] as const

  it.each(
    TOOL_TOOL_ANSWER.flatMap((turn) => CONFIGS.map((config) => ({ ...turn, config }))),
  )('$label, config $config — "$text": tool, tool, then the closing answer (3 calls, text present)', async ({
    text,
    second,
    answer,
    config,
  }) => {
    const h = harness({
      text,
      chat: [
        { toolCalls: [tool('consulta_metricas')] },
        { toolCalls: [second] },
        { content: answer },
      ],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(3)
    expect(output.text).toBe(answer)
    expect(output.toolCalls.map((call) => call.name)).toEqual(['consulta_metricas', second.name])

    const [first, middle, closing] = h.chatCalls as [LlmCall, LlmCall, LlmCall]
    expect(first.keys).not.toContain('toolChoice')
    expect(middle.keys).not.toContain('toolChoice')
    // The closing call: tools switched off, the same 6 schemas still sent
    // (the cached prefix is the one every call reads), its own time limit.
    expect(closing).toMatchObject({
      toolChoice: 'none',
      tools: first.tools,
      requestTimeoutMs: 45_000,
    })
    expect(first.tools).toBe(6)
    // It answers with what the two tools returned.
    expect(closing.messages.filter((message) => message.role === 'tool')).toHaveLength(2)
  })

  it("the closing call is in the turn's numbers: three calls, the third marked", async () => {
    const [turn] = TOOL_TOOL_ANSWER as [(typeof TOOL_TOOL_ANSWER)[number]]
    const h = harness({
      text: turn.text,
      chat: [
        { toolCalls: [tool('consulta_metricas')], promptTokens: 7_400, costUsd: 0.0098 },
        { toolCalls: [turn.second], promptTokens: 7_600, costUsd: 0.0101 },
        { content: turn.answer, promptTokens: 7_900, completionTokens: 44, costUsd: 0.0107 },
      ],
      configIterations: 5,
    })
    const output = await flow(h, turn.text)

    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as {
      call_count: number
      calls: Row[]
    }
    expect(properties.call_count).toBe(3)
    expect(properties.calls.map((call) => call.closing)).toEqual([undefined, undefined, 1])
    expect(properties.calls[2]).toMatchObject({ index: 2, prompt_tokens: 7_900, cost_usd: 0.0107 })
    expect(output.promptTokens).toBe(7_400 + 7_600 + 7_900)
    expect(output.costUsd).toBeCloseTo(0.0098 + 0.0101 + 0.0107, 10)
  })

  it('the closing answer passes the same guards as any answer of the model', async () => {
    const corrected = 'Seu bloco atual está em andamento; ele só é creditado no fechamento do dia.'
    const h = harness({
      text: 'Mostre meu progresso recente.',
      chat: [
        { toolCalls: [tool('consulta_metricas')] },
        { toolCalls: [tool('consulta_resumo_periodo', { days: 7 }, 'call-2')] },
        { content: PREMATURE_BLOCK },
        { content: corrected },
      ],
      configIterations: 5,
    })
    const output = await flow(h, 'Mostre meu progresso recente.')

    expect(h.chatCalls).toHaveLength(4)
    expect(eventNames(h)).toContain('llm.premature_block_completion')
    expect(output.text).toBe(corrected)
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([
      undefined,
      undefined,
      'none',
      undefined,
    ])
  })

  it('one closing call per turn, never a second: a guard retry after it that asks for a tool again ends the turn', async () => {
    const h = harness({
      text: 'Mostre meu progresso recente.',
      chat: [
        { toolCalls: [tool('consulta_metricas')] },
        { toolCalls: [tool('consulta_resumo_periodo', { days: 7 }, 'call-2')] },
        { content: PREMATURE_BLOCK },
        { toolCalls: [tool('consulta_metricas', {}, 'call-3')] },
        { content: 'nunca chamado' },
      ],
      configIterations: 5,
    })
    const output = await flow(h, 'Mostre meu progresso recente.')

    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([
      undefined,
      undefined,
      'none',
      undefined,
    ])
    expect(output.text).toBe('')
  })

  it('a single request with its suggestion stored needs no closing call: the suggestion is the answer', async () => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const h = harness({
      chat: [
        {
          toolCalls: [
            tool('consulta_progresso', {}, 'call-0'),
            tool('propoe_plano_dieta', { horizon: 'daily' }),
          ],
        },
        { toolCalls: [tool('consulta_metricas', {}, 'call-2')] },
        { content: 'nunca chamado' },
      ],
      generator: [MENU_GENERATION],
      configIterations: 5,
    })
    const output = await flow(h)

    expect(h.chatCalls).toHaveLength(2)
    for (const call of h.chatCalls) expect(call.keys).not.toContain('toolChoice')
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  it('with the deadline passed there is no closing call: the turn fails as a deadline', async () => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [
        { toolCalls: [tool('consulta_metricas')], ms: 100_000 },
        { toolCalls: [tool('consulta_metricas', {}, 'call-2')], ms: 50_000 },
        { content: 'nunca chamado' },
      ],
    })

    await expect(flow(h, 'Quais são minhas métricas?')).rejects.toThrow(
      new Error(MOBILE_FLOW_DEADLINE_ERROR),
    )
    expect(h.chatCalls).toHaveLength(2)
  })

  // What remains of RC PERF-C8, locked so nobody reads it as covered.
  // (a) A model (or provider) that ignores tool_choice "none" and writes no text.
  it('RC PERF-C8 (not covered) — a closing call answered with a tool call and no text still ends empty', async () => {
    const h = harness({ text: 'Quais são minhas métricas?', chat: ALWAYS_A_TOOL })
    const output = await flow(h, 'Quais são minhas métricas?')

    expect(h.chatCalls).toHaveLength(3)
    expect(output.text).toBe('')
    expect(output.toolCalls).toHaveLength(2)
  })

  // (b) is the test "one closing call per turn" above: the guard retry after
  // the closing call is made with the tools switched on again.

  // (c) The second review's scenario C04, message and script exact: the
  // provider refuses the closing call and NO suggestion is stored. The turn
  // has nothing to answer with and fails (502 in the service), and its
  // numbers are written. With a suggestion stored the turn answers with it
  // (section 3b).
  it.each([
    2, 5,
  ])('RC PERF-C8 (not covered) — "Como foi minha semana e qual minha taxa basal?", config %i: a provider error on the closing call, with no suggestion stored, fails the turn', async (config) => {
    const text = 'Como foi minha semana e qual minha taxa basal?'
    const h = harness({
      text,
      chat: [
        { toolCalls: [tool('consulta_metricas')] },
        { toolCalls: [tool('consulta_progresso', {}, 'call-2')] },
        { throws: '400 tool_choice none is not supported' },
      ],
      configIterations: config,
    })

    await expect(flow(h, text)).rejects.toThrow('400 tool_choice none is not supported')
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
    const written = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(written).toHaveLength(1)
    const properties = written[0]?.properties as { calls: Row[] }
    expect(properties).toMatchObject({ call_count: 3, turn_failed: 1 })
    expect(properties.calls[2]).toMatchObject({ index: 2, closing: 1, failed: 1 })
  })
})

// ── 3b. Second review: a stored suggestion AND another question ─────────────
describe('audit 2026-10-04 Flow calls — second review: with a suggestion stored, a message that asks something else still gets the closing call', () => {
  const DIET = tool('propoe_plano_dieta', { horizon: 'daily' }, 'call-diet')
  const CONFIGS = [2, 3, 5] as const

  // The reviewer's three turns (lens A, M01, M03, M02), message and script
  // exact: the model spends both iterations on tools, one of them the plan
  // tool. The closing call was granted only when no suggestion was stored,
  // so each ended after two calls on the fixed suggestion text and the other
  // question was dropped without a word. At the parent commit the model
  // answered on its third call wherever the config allowed 3 or more.
  type ToolCall = ReturnType<typeof tool>
  const TOOL_TOOL: Array<{
    label: string
    text: string
    script: [ToolCall, ToolCall]
    other: string
  }> = [
    {
      label: 'M01 — read tool, then plan tool',
      text: 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?',
      script: [tool('consulta_progresso', {}, 'call-read'), DIET],
      other: 'Sobre a proteína de hoje: você está em 59 g de 144 g, faltam 85 g.',
    },
    {
      label: 'M03 — the inverse order: plan tool, then read tool',
      text: 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?',
      script: [DIET, tool('consulta_progresso', {}, 'call-read')],
      other: 'Sobre a proteína de hoje: você está em 59 g de 144 g, faltam 85 g.',
    },
    {
      label: 'M02 — the week first',
      text: 'Como foi minha semana? E monte um cardápio para hoje.',
      script: [tool('consulta_metricas', {}, 'call-read'), DIET],
      other: 'Sobre a semana: você registrou 3 dias seguidos e a média ficou perto da meta.',
    },
  ]

  it.each(
    TOOL_TOOL.flatMap((turn) => CONFIGS.map((config) => ({ ...turn, config }))),
  )('$label, config $config — "$text": 3 model calls, the third with the tools switched off, and the other question answered', async ({
    text,
    script,
    other,
    config,
  }) => {
    const h = harness({
      text,
      chat: [{ toolCalls: [script[0]] }, { toolCalls: [script[1]] }, { copySuggestion: other }],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls).toHaveLength(3)
    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
    expect(h.generatorCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    // The stored suggestion, whole, and the answer to the other question.
    expect(output.text).toBe(
      `Sua sugestão está pronta!\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\nToque em "Revisar sugestão" para conferir, ajustar e confirmar.\n\n${other}`,
    )
    expect(output.text).toContain(other)
    expect(output.toolCalls.map((call) => call.name)).toEqual(script.map((call) => call.name))

    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as {
      call_count: number
      calls: Row[]
    }
    expect(properties.call_count).toBe(3)
    expect(properties.calls.map((call) => call.closing)).toEqual([undefined, undefined, 1])
    expect(properties).not.toHaveProperty('plan_suggestion_direct')
  })

  // The single request keeps its call count: the reviewer's M04 (a read tool,
  // then the plan tool) ends on the stored suggestion after two calls.
  it.each(
    CONFIGS,
  )('"Sugira um cardápio completo para hoje", read tool then plan tool (config %i): still 2 calls, no closing call', async (config) => {
    const h = harness({
      chat: [
        { toolCalls: [tool('consulta_metricas', {}, 'call-read')] },
        { toolCalls: [DIET] },
        { content: 'NUNCA CHAMADO' },
      ],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h)

    expect(h.chatCalls).toHaveLength(2)
    for (const call of h.chatCalls) expect(call.keys).not.toContain('toolChoice')
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  it('a closing call that paraphrases the suggestion gets the stored text, as any paraphrase does (RC PERF-C11)', async () => {
    const [turn] = TOOL_TOOL as [(typeof TOOL_TOOL)[number]]
    const h = harness({
      text: turn.text,
      chat: [
        { toolCalls: [turn.script[0]] },
        { toolCalls: [turn.script[1]] },
        { content: 'Montei um cardápio equilibrado. Faltam 85 g de proteína.' },
      ],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, turn.text)

    expect(h.chatCalls).toHaveLength(3)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
  })

  it('with less than the floor left, the stored suggestion is the answer and no closing call is made', async () => {
    const [turn] = TOOL_TOOL as [(typeof TOOL_TOOL)[number]]
    const h = harness({
      text: turn.text,
      chat: [
        { toolCalls: [turn.script[0]], ms: 40_000 },
        { toolCalls: [turn.script[1]], ms: 5_000 },
        { content: 'NUNCA CHAMADO' },
      ],
      // The generator leaves less than MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS.
      generator: [{ ...MENU_GENERATION, ms: 100_000 }],
    })
    const output = await flow(h, turn.text)

    expect(h.chatCalls).toHaveLength(2)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    expect(events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties).toMatchObject({
      plan_suggestion_at_deadline: 1,
    })
  })

  // Third review, K1, message and script exact: the plan tool, a read tool,
  // and the provider answers the closing call with an error. The catch
  // rethrew: the turn failed after three paid calls and the generator, the
  // draft stayed pending and the chat got nothing — where the stage config
  // of 2 used to end after two calls on the suggestion. Now the stored
  // suggestion is the answer, and the event shows the call that failed.
  it.each([
    2, 5,
  ])('"Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?", plan tool, read tool, closing call answered "500 upstream" (config %i): the stored suggestion is the answer', async (config) => {
    const text = 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?'
    const h = harness({
      text,
      chat: [
        { toolCalls: [DIET] },
        { toolCalls: [tool('consulta_progresso', {}, 'call-read')] },
        { throws: '500 upstream', ms: 2_000 },
      ],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
    expect(h.generatorCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    expect(output.toolCalls.map((call) => call.name)).toEqual([
      'propoe_plano_dieta',
      'consulta_progresso',
    ])

    // One event, of a turn that answered: three calls, the third one the
    // closing call that failed (its time, no tokens).
    const written = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(written).toHaveLength(1)
    const properties = written[0]?.properties as { calls: Row[] }
    expect(properties).toMatchObject({ call_count: 3 })
    expect(properties.calls[2]).toMatchObject({
      index: 2,
      closing: 1,
      failed: 1,
      prompt_tokens: 0,
      cost_usd: null,
      ms: 2_000,
    })
    for (const flag of ['turn_failed', 'plan_suggestion_direct', 'plan_suggestion_at_deadline']) {
      expect(properties, flag).not.toHaveProperty(flag)
    }
    // The model never answered: it is not reported as having rewritten.
    expect(eventNames(h)).not.toContain('llm.plan_suggestion_rewritten')
    // The error text is nowhere in what the turn wrote or answered.
    expect(JSON.stringify([output.text, h.inserts])).not.toContain('500 upstream')
  })

  it('the same failure with two suggestions stored: both are delivered', async () => {
    const text = 'Sugira um cardápio e um treino'
    const h = harness({
      text,
      chat: [
        { toolCalls: [DIET] },
        { toolCalls: [tool('propoe_plano_treino', WORKOUT_ARGS, 'call-2')] },
        { throws: '500 upstream' },
      ],
      generator: [MENU_GENERATION, WORKOUT_GENERATION],
    })
    const output = await flow(h, text)

    const [menu, workout] = drafts(h)
    expect(output.text).toBe(
      `Suas sugestões estão prontas:\n\n${nutritionSuggestionText(menu?.p_payload)}\n\n${trainingSuggestionText(workout?.p_payload)}\n\n${CLOSING}`,
    )
  })

  // Declared, not fixed (RC PERF-C13): the other question of that turn gets
  // no answer, and the fixed text does not say so.
  it('RC PERF-C13 (not covered) — the turn the failed closing call ends says nothing about the protein', async () => {
    const text = 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?'
    const h = harness({
      text,
      chat: [
        { toolCalls: [DIET] },
        { toolCalls: [tool('consulta_progresso', {}, 'call-read')] },
        { throws: '500 upstream' },
      ],
      generator: [MENU_GENERATION],
    })
    const output = await flow(h, text)

    expect(output.text.startsWith(`${OPENING}\n\n`)).toBe(true)
    expect(output.text.endsWith(CLOSING)).toBe(true)
    expect(output.text).not.toMatch(/faltam|falta de proteína/i)
  })

  // Declared, not fixed (RC PERF-C15). Third review, K8, message and script
  // exact: the model reads twice and only then asks for the plan tool. That
  // third call is the closing call, made with the tools switched off: the
  // plan tool is not run and no draft is stored in the turn. The scripted
  // model writes nothing without its tool, so the text is empty (502 in the
  // service); what a real model writes there was not measured. At the
  // parent commit, config 5: four calls, the draft, the suggestion and the
  // protein answered; config 2: two calls, no draft, empty text.
  it.each([
    2, 5,
  ])('RC PERF-C15 (not covered) — "Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?", read, read, plan (config %i): the plan is not generated in the turn', async (config) => {
    const text = 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?'
    const h = harness({
      text,
      chat: [
        { toolCalls: [tool('consulta_progresso', {}, 'call-read-1')] },
        { toolCalls: [tool('consulta_metricas', {}, 'call-read-2')] },
        { toolCalls: [DIET] },
        { copySuggestion: 'Sobre a proteína de hoje: faltam 85 g.' },
      ],
      generator: [MENU_GENERATION],
      configIterations: config,
    })
    const output = await flow(h, text)

    expect(h.chatCalls.map((call) => call.toolChoice)).toEqual([undefined, undefined, 'none'])
    expect(output.toolCalls.map((call) => call.name)).toEqual([
      'consulta_progresso',
      'consulta_metricas',
    ])
    expect(h.generatorCalls).toHaveLength(0)
    expect(drafts(h)).toHaveLength(0)
    expect(output.text).toBe('')
  })

  it('WhatsApp never gets a closing call, whatever the message', async () => {
    const [turn] = TOOL_TOOL as [(typeof TOOL_TOOL)[number]]
    const h = harness({
      channel: 'whatsapp',
      text: turn.text,
      chat: [
        { toolCalls: [tool('consulta_progresso', {}, 'call-read')] },
        { toolCalls: [tool('consulta_metricas', {}, 'call-2')] },
        { content: 'Faltam 85 g de proteína hoje.' },
      ],
      configIterations: 2,
    })
    await whatsapp(h, turn.text)

    expect(h.chatCalls).toHaveLength(2)
    for (const call of h.chatCalls) expect(call.keys).not.toContain('toolChoice')
  })
})

// ── 4. Time limits ──────────────────────────────────────────────────────────
describe('audit 2026-10-04 Flow calls — a chat call has 45 s and the turn 150 s of model work', () => {
  it('the limits sit under the app timeout (180 s) and the function limit (300 s)', () => {
    expect(MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS).toBe(45_000)
    expect(MOBILE_FLOW_TURN_DEADLINE_MS).toBe(150_000)
    expect(MOBILE_FLOW_TURN_DEADLINE_MS).toBeLessThan(180_000)
    expect(MOBILE_FLOW_TURN_DEADLINE_MS).toBeLessThan(300_000)
    // A call with its retry (the old worst case was 90 + 90 s) fits the turn.
    expect(2 * MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS).toBeLessThan(MOBILE_FLOW_TURN_DEADLINE_MS)
  })

  it('a Flow chat call carries its own limit and the one retry the client already made', async () => {
    const h = harness({ text: STATUS_PHRASE })
    await flow(h, STATUS_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(h.chatCalls[0]).toMatchObject({ requestTimeoutMs: 45_000, maxRetries: 1 })
  })

  it('WhatsApp chat calls carry neither argument', async () => {
    const h = harness({
      channel: 'whatsapp',
      text: 'Quais são minhas métricas?',
      chat: [{ toolCalls: [tool('consulta_metricas')], ms: 100_000 }, { content: 'Resposta.' }],
    })
    await whatsapp(h, 'Quais são minhas métricas?')

    expect(h.chatCalls).toHaveLength(2)
    for (const call of h.chatCalls) {
      expect(call.keys).not.toContain('requestTimeoutMs')
      expect(call.keys).not.toContain('maxRetries')
      expect(call.keys).toEqual([
        'cacheTools',
        'cacheToolsTtl',
        'maxTokens',
        'messages',
        'metadata',
        'model',
        'systemPrompt',
        'temperature',
        'tools',
        'userId',
      ])
    }
  })

  it.each([
    // first call takes → second call may take, retries
    ['a quick first call', 3_000, 45_000, 1],
    ['60 s gone: the full limit, with its retry', 60_000, 45_000, 1],
    ['61 s gone: the full limit, the retry no longer fits', 61_000, 45_000, 0],
    ['120 s gone: what is left of the turn', 120_000, 30_000, 0],
    ['149 s gone: one second', 149_000, 1_000, 0],
  ])('the second call never passes the turn deadline — %s', async (_label, firstMs, timeoutMs, retries) => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [{ toolCalls: [tool('consulta_metricas')], ms: firstMs }, { content: 'Resposta.' }],
    })
    const output = await flow(h, 'Quais são minhas métricas?')

    expect(output.text).toBe('Resposta.')
    expect(h.chatCalls[1]).toMatchObject({ requestTimeoutMs: timeoutMs, maxRetries: retries })
    expect(h.chatCalls[1]?.at).toBe(firstMs)
    expect((h.chatCalls[1]?.at ?? 0) + timeoutMs).toBeLessThanOrEqual(MOBILE_FLOW_TURN_DEADLINE_MS)
  })

  it.each([
    150_000, 151_000, 400_000,
  ])('with the deadline passed (%i ms) no further call is made and the turn fails', async (firstMs) => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [{ toolCalls: [tool('consulta_metricas')], ms: firstMs }, { content: 'nunca chamado' }],
    })

    await expect(flow(h, 'Quais são minhas métricas?')).rejects.toThrow(
      new Error(MOBILE_FLOW_DEADLINE_ERROR),
    )
    expect(h.chatCalls).toHaveLength(1)
    // The message is a fixed lowercase code: the service logs it as such.
    expect(MOBILE_FLOW_DEADLINE_ERROR).toMatch(/^[a-z][a-z _-]{2,79}$/)
  })

  it('a chat call that times out with turn time left fails the turn, as a provider failure always did', async () => {
    const h = harness({ text: STATUS_PHRASE, chat: [{ timesOut: true }] })

    // 45 s gone of 150: this is the call's own limit, not the turn's.
    await expect(flow(h, STATUS_PHRASE)).rejects.toThrow(new Error('Request timed out.'))
    expect(h.chatCalls).toHaveLength(1)
  })

  it('a chat call the deadline cut short fails the turn as a deadline, with the client error as its cause', async () => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [{ toolCalls: [tool('consulta_metricas')], ms: 120_000 }, { timesOut: true }],
    })

    const failure = await flow(h, 'Quais são minhas métricas?').catch((error: unknown) => error)
    // The second call had the 30 s the turn had left and used them all.
    expect(h.chatCalls[1]).toMatchObject({ requestTimeoutMs: 30_000, maxRetries: 0, at: 120_000 })
    expect(failure).toEqual(new Error(MOBILE_FLOW_DEADLINE_ERROR))
    expect((failure as Error).cause).toEqual(new Error('Request timed out.'))
  })

  it.each([
    // the cut call fails this long before the deadline → the turn's error
    ['on the deadline', 30_000, MOBILE_FLOW_DEADLINE_ERROR],
    [
      'a quarter of a second before it (the client timer is another clock)',
      29_750,
      MOBILE_FLOW_DEADLINE_ERROR,
    ],
    ['a second before it: the provider failed, not the deadline', 29_000, 'Request timed out.'],
  ])('a failed call counts as the deadline only when the deadline is there — %s', async (_label, failsAfter, message) => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [
        { toolCalls: [tool('consulta_metricas')], ms: 120_000 },
        { timesOut: true, ms: failsAfter },
      ],
    })

    await expect(flow(h, 'Quais são minhas métricas?')).rejects.toThrow(new Error(message))
  })

  it('the plan generator keeps its own 120 s while the turn has them', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    await flow(h)

    expect(h.generatorCalls[0]).toMatchObject({
      model: GENERATOR_MODEL,
      stage: 'diet-generator',
      maxTokens: 8000,
      requestTimeoutMs: 120_000,
      maxRetries: 0,
      at: 4_200,
    })
  })

  it.each([
    ['30 s', 30_000, 120_000],
    ['31 s', 31_000, 119_000],
    ['90 s', 90_000, 60_000],
  ])('after a first call of %s the generator gets no more than the turn has left', async (_label, firstMs, timeoutMs) => {
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [{ ...WORKOUT_CALL, ms: firstMs }],
      generator: [WORKOUT_GENERATION],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    expect(h.generatorCalls[0]).toMatchObject({ requestTimeoutMs: timeoutMs, maxRetries: 0 })
    expect(firstMs + timeoutMs).toBeLessThanOrEqual(MOBILE_FLOW_TURN_DEADLINE_MS)
    expect(output.text).toContain(OPENING)
  })

  it('a generator that uses all the time left ends the turn: nothing is stored, no call follows', async () => {
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [{ ...WORKOUT_CALL, ms: 40_000 }, { content: 'nunca chamado' }],
      generator: [{ content: '', timesOut: true }],
    })

    await expect(flow(h, WORKOUT_PHRASE)).rejects.toThrow(new Error(MOBILE_FLOW_DEADLINE_ERROR))
    expect(h.generatorCalls[0]).toMatchObject({ requestTimeoutMs: 110_000, at: 40_000 })
    expect(h.chatCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(0)
    expect(events(h, 'training.generation_failed')).toHaveLength(1)
  })

  it('a refused menu shares the generator budget between its two attempts, inside the turn', async () => {
    const refused = JSON.stringify({ daily_meals: [], shopping_list: [] })
    const h = harness({
      chat: [{ ...MENU_CALL, ms: 60_000 }],
      generator: [
        { content: refused, ms: 50_000 },
        { ...MENU_GENERATION, ms: 30_000 },
      ],
    })
    const output = await flow(h)

    expect(h.generatorCalls.map((call) => call.requestTimeoutMs)).toEqual([90_000, 40_000])
    expect(h.generatorCalls.map((call) => call.at)).toEqual([60_000, 110_000])
    expect(output.text).toContain(OPENING)
    expect(drafts(h)).toHaveLength(1)
  })

  // A draft already stored and the deadline at hand: the turn used to fail
  // with 502, leaving a pending draft with no answer in the chat (review 3).
  it('review 3, scenario 32 — plan + read tool, first call 30 s, generator 119 s: no second call, the stored suggestion is the answer', async () => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const h = harness({
      chat: [
        {
          toolCalls: [
            tool('consulta_progresso', {}, 'call-0'),
            tool('propoe_plano_dieta', { horizon: 'daily' }),
          ],
          ms: 30_000,
        },
        { copySuggestion: true, ms: 10_000 },
      ],
      generator: [{ ...MENU_GENERATION, ms: 119_000 }],
    })
    const output = await flow(h)

    // 149 s gone: one second is left, under the 12 s a copy needs.
    expect(MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS).toBe(12_000)
    expect(h.chatCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    expect(output.latencyMs).toBe(149_000)

    // Said in the numbers, and not reported as a model that paraphrased.
    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as Row
    expect(properties).toMatchObject({ call_count: 1, plan_suggestion_at_deadline: 1 })
    expect(properties).not.toHaveProperty('plan_suggestion_direct')
    expect(properties).not.toHaveProperty('turn_failed')
    expect((properties.generator_calls as Row[])[0]).toMatchObject({
      ms: 119_000,
      cost_usd: 0.0434,
    })
    expect(eventNames(h)).not.toContain('llm.plan_suggestion_rewritten')
  })

  it.each([
    ['12 s left: the second call is made', 108_000, 2],
    ['11 s left: it is not', 109_000, 1],
  ])('the floor for a call after a stored suggestion — %s', async (_label, generatorMs, calls) => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const h = harness({
      chat: [
        {
          toolCalls: [
            tool('consulta_progresso', {}, 'call-0'),
            tool('propoe_plano_dieta', { horizon: 'daily' }),
          ],
          ms: 30_000,
        },
        { copySuggestion: true, ms: 9_000 },
      ],
      generator: [{ ...MENU_GENERATION, ms: generatorMs }],
    })
    const output = await flow(h)

    expect(h.chatCalls).toHaveLength(calls)
    expect(output.text).toContain(nutritionSuggestionText(drafts(h)[0]?.p_payload))
  })

  it('a second call the deadline cuts while a suggestion is stored: the suggestion is still delivered', async () => {
    vi.spyOn(consultaProgresso, 'execute').mockResolvedValue({ success: true })
    const h = harness({
      chat: [
        {
          toolCalls: [
            tool('consulta_progresso', {}, 'call-0'),
            tool('propoe_plano_dieta', { horizon: 'daily' }),
          ],
          ms: 30_000,
        },
        { timesOut: true },
      ],
      generator: [{ ...MENU_GENERATION, ms: 100_000 }],
    })
    const output = await flow(h)

    // 130 s gone: the copy call starts with the 20 s left and never answers.
    expect(h.chatCalls).toHaveLength(2)
    expect(h.chatCalls[1]).toMatchObject({ requestTimeoutMs: 20_000, maxRetries: 0 })
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as { calls: Row[] }
    expect(properties).toMatchObject({ call_count: 2, plan_suggestion_at_deadline: 1 })
    // The cut call is in the numbers with its time and no tokens.
    expect(properties.calls[1]).toMatchObject({
      index: 1,
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: null,
      ms: 20_000,
      failed: 1,
    })
  })

  it('review 3, B2 — two plans in one call, first call 20 s, each generator 70 s: the menu that was stored is delivered', async () => {
    const text = 'Sugira um cardápio e um treino'
    const h = harness({
      text,
      chat: [
        {
          toolCalls: [
            tool('propoe_plano_dieta', { horizon: 'daily' }),
            tool('propoe_plano_treino', WORKOUT_ARGS, 'call-2'),
          ],
          ms: 20_000,
        },
        { copySuggestion: true },
      ],
      // The menu takes its 70 s; the workout generator gets the 60 s left of
      // the turn and does not finish.
      generator: [
        { ...MENU_GENERATION, ms: 70_000 },
        { content: '', timesOut: true },
      ],
    })
    const output = await flow(h, text)

    expect(h.generatorCalls.map((call) => [call.stage, call.at, call.requestTimeoutMs])).toEqual([
      ['diet-generator', 20_000, 120_000],
      ['training-generator', 90_000, 60_000],
    ])
    expect(h.chatCalls).toHaveLength(1)
    expect(drafts(h)).toHaveLength(1)
    expect(output.text).toBe(
      `${OPENING}\n\n${nutritionSuggestionText(drafts(h)[0]?.p_payload)}\n\n${CLOSING}`,
    )
    // Both generations are in the numbers: the one paid for and the one cut.
    const properties = events(h, MOBILE_FLOW_CALLS_EVENT)[0]?.properties as {
      generator_calls: Row[]
    }
    expect(properties).toMatchObject({ plan_suggestion_at_deadline: 1 })
    expect(properties.generator_calls).toMatchObject([
      { index: 0, cost_usd: 0.0434, ms: 70_000 },
      { index: 1, cost_usd: null, ms: 60_000, failed: 1 },
    ])
    // RC PERF-C13: nothing in the answer says the workout was not created.
    expect(output.text).not.toMatch(/treino/i)
  })

  it('WhatsApp tools get the client itself, untouched; Flow tools get the metered one', async () => {
    const seen: unknown[] = []
    vi.spyOn(consultaProgresso, 'execute').mockImplementation(async (_args, ctx) => {
      seen.push(ctx.llm)
      return { success: true }
    })
    const script: ChatStep[] = [{ toolCalls: [tool('consulta_progresso')] }, { content: 'Ok.' }]
    const legacy = harness({
      channel: 'whatsapp',
      text: 'Mostre meu progresso recente.',
      chat: script,
    })
    await whatsapp(legacy, 'Mostre meu progresso recente.')
    const mobile = harness({ text: 'Mostre meu progresso recente.', chat: script })
    await flow(mobile, 'Mostre meu progresso recente.')

    expect(seen[0]).toBe(legacy.deps.llm)
    expect(seen[1]).not.toBe(mobile.deps.llm)
  })
})

// ── 5. The generator in the turn's numbers ──────────────────────────────────
describe('audit 2026-10-04 Flow calls — the plan generator is in the turn’s tokens, cost and time', () => {
  it('the turn totals are the chat call plus the generator', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    const output = await flow(h)

    expect(output.promptTokens).toBe(11_040 + 912)
    expect(output.completionTokens).toBe(86 + 2_710)
    expect(output.costUsd).toBeCloseTo(0.0211 + 0.0434, 10)
    expect(output.latencyMs).toBe(4_200 + 36_500)
  })

  it('llm.flow_calls carries the generator call, numbers only, and says the turn was answered directly', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    const output = await flow(h)

    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(event?.properties).toMatchObject({
      stage: 'ganho_massa',
      call_count: 1,
      calls: [
        {
          index: 0,
          model: MODEL,
          prompt_tokens: 11_040,
          completion_tokens: 86,
          cost_usd: 0.0211,
          ms: 4_200,
        },
      ],
      generator_calls: [
        {
          index: 0,
          model: GENERATOR_MODEL,
          prompt_tokens: 912,
          completion_tokens: 2_710,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          cost_usd: 0.0434,
          ms: 36_500,
        },
      ],
      plan_suggestion_direct: 1,
    })

    // No text: not the phrase, not the suggestion, not a food, not the name.
    const serialized = JSON.stringify(event)
    for (const text of [MENU_PHRASE, 'cardápio', output.text, 'Frango', 'Café da manhã', 'QA A']) {
      expect(serialized, text).not.toContain(text)
    }
    const strings: string[] = []
    const walk = (value: unknown) => {
      if (typeof value === 'string') strings.push(value)
      else if (Array.isArray(value)) value.forEach(walk)
      else if (value && typeof value === 'object') Object.values(value).forEach(walk)
      else expect(value === null || typeof value === 'number').toBe(true)
    }
    walk(event)
    expect(strings.sort()).toEqual(
      [USER_ID, MOBILE_FLOW_CALLS_EVENT, 'ganho_massa', MODEL, GENERATOR_MODEL].sort(),
    )
  })

  it('a refused first generation is paid for too: both attempts are counted', async () => {
    const refused = JSON.stringify({ daily_meals: [], shopping_list: [] })
    const h = harness({
      chat: [MENU_CALL],
      generator: [
        { content: refused, promptTokens: 900, completionTokens: 40, costUsd: 0.0033, ms: 2_000 },
        MENU_GENERATION,
      ],
    })
    const output = await flow(h)

    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect((event?.properties as { generator_calls: Row[] }).generator_calls).toMatchObject([
      { index: 0, prompt_tokens: 900, completion_tokens: 40, cost_usd: 0.0033, ms: 2_000 },
      { index: 1, prompt_tokens: 912, completion_tokens: 2_710, cost_usd: 0.0434, ms: 36_500 },
    ])
    expect(output.costUsd).toBeCloseTo(0.0211 + 0.0033 + 0.0434, 10)
    expect(output.promptTokens).toBe(11_040 + 900 + 912)
  })

  it('a generator call that throws is recorded with its time and no tokens', async () => {
    const apology = 'Não consegui criar a sugestão agora.'
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [
        { ...WORKOUT_CALL, ms: 1_000 },
        { content: apology, ms: 1_000 },
      ],
      generator: [{ content: '', timesOut: true }],
    })
    const output = await flow(h, WORKOUT_PHRASE)

    // 120 s of generator, then 29 s were left for the model to explain.
    expect(output.text).toBe(apology)
    expect(h.chatCalls[1]).toMatchObject({ requestTimeoutMs: 29_000, maxRetries: 0 })
    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect((event?.properties as { generator_calls: Row[] }).generator_calls).toEqual([
      {
        index: 0,
        model: GENERATOR_MODEL,
        prompt_tokens: 0,
        completion_tokens: 0,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        cost_usd: null,
        ms: 120_000,
        failed: 1,
      },
    ])
    expect(event?.properties).not.toHaveProperty('plan_suggestion_direct')
  })

  it('a turn with no tool model call has the event it had: no generator field, no direct flag', async () => {
    const h = harness({ text: STATUS_PHRASE })
    const output = await flow(h, STATUS_PHRASE)

    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(Object.keys(event?.properties as Row).sort()).toEqual([
      'call_count',
      'calls',
      'stage',
      'tools_chars',
    ])
    expect(output.promptTokens).toBe(7400)
    expect(output.completionTokens).toBe(60)
    expect(output.costUsd).toBe(0.0098)
  })

  it('llm.cache_usage still counts the chat calls only', async () => {
    const h = harness({ chat: [MENU_CALL], generator: [MENU_GENERATION] })
    await flow(h)

    expect(events(h, 'llm.cache_usage')[0]?.properties).toMatchObject({
      prompt_tokens: 11_040,
      cache_read_tokens: 5060,
    })
  })
})

// ── 5b. The numbers of a turn that fails ────────────────────────────────────
describe('audit 2026-10-04 Flow calls — a turn that ends in an error still writes what it spent', () => {
  /** Every leaf of the event is a number or null, except these identifiers. */
  const onlyNumbers = (event: Row | undefined, models: string[]) => {
    const strings: string[] = []
    const walk = (value: unknown) => {
      if (typeof value === 'string') strings.push(value)
      else if (Array.isArray(value)) value.forEach(walk)
      else if (value && typeof value === 'object') Object.values(value).forEach(walk)
      else expect(value === null || typeof value === 'number').toBe(true)
    }
    walk(event)
    expect(strings.sort()).toEqual(
      [USER_ID, MOBILE_FLOW_CALLS_EVENT, 'ganho_massa', ...models].sort(),
    )
  }

  it('the deadline passes between two calls: the first call is recorded, marked as a failed turn', async () => {
    const h = harness({
      text: 'Quais são minhas métricas?',
      chat: [
        {
          toolCalls: [tool('consulta_metricas')],
          promptTokens: 7_421,
          costUsd: 0.0101,
          ms: 150_000,
        },
        { content: 'nunca chamado' },
      ],
    })

    await expect(flow(h, 'Quais são minhas métricas?')).rejects.toThrow(
      new Error(MOBILE_FLOW_DEADLINE_ERROR),
    )
    const written = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(written).toHaveLength(1)
    expect(written[0]?.properties).toMatchObject({
      stage: 'ganho_massa',
      call_count: 1,
      turn_failed: 1,
      calls: [{ index: 0, model: MODEL, prompt_tokens: 7_421, cost_usd: 0.0101, ms: 150_000 }],
    })
    onlyNumbers(written[0], [MODEL])
  })

  it('a first chat call that times out: its 45 s are recorded, with no tokens', async () => {
    const h = harness({ text: STATUS_PHRASE, chat: [{ timesOut: true }] })

    await expect(flow(h, STATUS_PHRASE)).rejects.toThrow(new Error('Request timed out.'))
    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(event?.properties).toMatchObject({
      call_count: 1,
      turn_failed: 1,
      calls: [
        {
          index: 0,
          model: MODEL,
          prompt_tokens: 0,
          completion_tokens: 0,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          cost_usd: null,
          ms: 45_000,
          failed: 1,
        },
      ],
    })
    onlyNumbers(event, [MODEL])
  })

  it('the generator that used all the time left: its time is recorded on the failed turn', async () => {
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [{ ...WORKOUT_CALL, ms: 40_000 }, { content: 'nunca chamado' }],
      generator: [{ content: '', timesOut: true }],
    })

    await expect(flow(h, WORKOUT_PHRASE)).rejects.toThrow(new Error(MOBILE_FLOW_DEADLINE_ERROR))
    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(event?.properties).toMatchObject({
      call_count: 1,
      turn_failed: 1,
      generator_calls: [
        { index: 0, model: GENERATOR_MODEL, cost_usd: null, ms: 110_000, failed: 1 },
      ],
    })
    onlyNumbers(event, [MODEL, GENERATOR_MODEL])
  })

  it('a paid generation followed by a provider failure: the generator cost is no longer lost', async () => {
    // The mixed message keeps the second call, and that call fails with time
    // left: the turn fails as before, and the US$ 0.0434 of the menu is in
    // the event. The draft stays for the retry of the same turn (section 1).
    const text = 'Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?'
    const h = harness({
      text,
      chat: [MENU_CALL, { timesOut: true }],
      generator: [MENU_GENERATION],
    })

    await expect(flow(h, text)).rejects.toThrow(new Error('Request timed out.'))
    expect(drafts(h)).toHaveLength(1)
    const [event] = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(event?.properties).toMatchObject({
      call_count: 2,
      turn_failed: 1,
      calls: [
        { index: 0, prompt_tokens: 11_040, cost_usd: 0.0211, ms: 4_200 },
        { index: 1, prompt_tokens: 0, cost_usd: null, ms: 45_000, failed: 1 },
      ],
      generator_calls: [{ index: 0, prompt_tokens: 912, cost_usd: 0.0434, ms: 36_500 }],
    })
    // No text of the patient, of the suggestion or of the error.
    const serialized = JSON.stringify(event)
    for (const fragment of [text, 'proteína', 'Frango', 'Request timed out', 'QA A']) {
      expect(serialized, fragment).not.toContain(fragment)
    }
    onlyNumbers(event, [MODEL, MODEL, GENERATOR_MODEL])
  })

  it('a turn that answers writes the event once, and never as a failed turn', async () => {
    const h = harness({ text: STATUS_PHRASE })
    await flow(h, STATUS_PHRASE)

    const written = events(h, MOBILE_FLOW_CALLS_EVENT)
    expect(written).toHaveLength(1)
    expect(written[0]?.properties).not.toHaveProperty('turn_failed')
  })

  it('WhatsApp writes nothing of this when its turn fails', async () => {
    const h = harness({ channel: 'whatsapp', text: STATUS_PHRASE, chat: [{ timesOut: true }] })

    await expect(whatsapp(h, STATUS_PHRASE)).rejects.toThrow(new Error('Request timed out.'))
    expect(eventNames(h)).not.toContain(MOBILE_FLOW_CALLS_EVENT)
  })
})

// ── 5c. What the model reads of today reaches the menu generator ────────────
describe('audit 2026-10-04 Flow calls — an allergy said earlier the same day reaches the menu generator', () => {
  /** The patient line of the review probe (2026-10-04), word for word. */
  const ALLERGY = 'Importante: sou intolerante a lactose e alérgico a castanhas.'
  const REQUEST = 'Agora monte um cardápio para hoje'

  const line = (direction: 'in' | 'out', content: string, at: string, index: number): Row => ({
    direction,
    content,
    content_type: 'text',
    created_at: at,
    provider_message_id: `mobile_flow/qa-a/h${index}`,
  })

  /**
   * The review probe's history: `count` stored lines, one minute apart, all
   * of today (one long session), the allergy `back` lines before the request.
   */
  function session(count: number, back: number): Row[] {
    const rows: Row[] = []
    for (let index = 0; index < count; index += 1) {
      const distance = count - index
      const at = new Date(NOW.getTime() - distance * 60_000).toISOString()
      const fromPatient = (index + (count % 2)) % 2 === 0
      let content = fromPatient
        ? 'Quanto falta de proteína hoje?'
        : 'Faltam 85 g de proteína para a meta de 144 g.'
      if (distance === back) content = ALLERGY
      if (distance === back - 1) content = 'Anotado.'
      rows.push(line(fromPatient ? 'in' : 'out', content, at, index))
    }
    return rows
  }

  /** A faithful model: it passes the restriction when, and only when, it can read it. */
  const FAITHFUL: ChatStep = {
    toolCallsFrom: (messages) => [
      tool('propoe_plano_dieta', {
        horizon: 'daily',
        ...(messages.some((message) => String(message.content).includes('intolerante a lactose'))
          ? { restrictions: ['lactose', 'castanhas'] }
          : {}),
      }),
    ],
  }

  const restrictionsSent = (h: Harness): string | undefined =>
    /<paciente_restricoes>\n([^\n]*)\n<\/paciente_restricoes>/.exec(
      String(h.generatorCalls[0]?.messages[0]?.content),
    )?.[1]

  // With a flat cut at 16 lines the generator received "(nenhuma)" from 18
  // lines back on (review 1: k = 18, 20, 30, 48), and the fixture menu has
  // cheese, yoghurt and cashew nuts.
  it.each([
    2, 6, 10, 14, 16, 18, 20, 30, 48,
  ])('49 lines today, the allergy %i lines before the request: the generator receives "lactose, castanhas"', async (back) => {
    const h = harness({
      text: REQUEST,
      history: session(49, back),
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST)

    expect(h.generatorCalls).toHaveLength(1)
    expect(restrictionsSent(h)).toBe('lactose, castanhas')
    // Every line of today went to the model, none with a date prefix.
    const sent = h.chatCalls[0]?.messages ?? []
    expect(sent).toHaveLength(50)
    expect(sent.filter((message) => message.content === ALLERGY)).toHaveLength(1)
    expect(sent.some((message) => String(message.content).startsWith('[Mensagem de'))).toBe(false)
  })

  // The local day is the session whatever the hour: a line of today said
  // more than 6 hours before the turn is never cut.
  it('the allergy said at 00:10 of the same local day, 12 hours and 30 lines before the request: the generator receives "lactose, castanhas"', async () => {
    const history = [
      line('in', ALLERGY, '2026-10-04T03:10:00.000Z', 0),
      line('out', 'Anotado.', '2026-10-04T03:11:00.000Z', 1),
      ...session(30, 0).map((row, index) => ({
        ...row,
        provider_message_id: `mobile_flow/qa-a/t${index}`,
      })),
    ]
    const h = harness({
      text: REQUEST,
      history,
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST)

    const sent = h.chatCalls[0]?.messages ?? []
    expect(sent).toHaveLength(33)
    expect(sent[0]?.content).toBe(ALLERGY)
    expect(restrictionsSent(h)).toBe('lactose, castanhas')
  })

  // ── 5d. Second review: the session that crosses local midnight ───────────
  /** 00:05 in São Paulo on 05/10: the reviewer's moment (lens A). */
  const AFTER_MIDNIGHT = new Date('2026-10-05T03:05:00.000Z')
  const DATED_04 =
    '[Mensagem de 04/10/2026, dia anterior — números do dia e horário citados nela não valem para hoje]\n'

  /**
   * The reviewer's history, as the probe built it: 49 lines one minute apart,
   * the newest 6 minutes before the turn (23:11 to 23:59 of 04/10), the
   * allergy `back` lines before the request.
   */
  function beforeMidnight(back: number): Row[] {
    const rows: Row[] = []
    for (let index = 0; index < 49; index += 1) {
      const distance = 49 - index
      const at = new Date(AFTER_MIDNIGHT.getTime() - (5 + distance) * 60_000).toISOString()
      const fromPatient = (index + 1) % 2 === 0
      rows.push(
        distance === back
          ? line('in', ALLERGY, at, index)
          : line(
              fromPatient ? 'in' : 'out',
              fromPatient ? `Pergunta ${index}` : `Resposta ${index}: tudo certo.`,
              at,
              index,
            ),
      )
    }
    return rows
  }

  // With the local day alone as the session, at 00:05 all 49 lines were
  // "previous day": only the newest 16 reached the model, and from 18 lines
  // back on the generator received "(nenhuma)" (the reviewer's k = 18, 30).
  it.each([
    10, 16, 18, 30,
  ])('00:05 in São Paulo, 49 lines said between 23:10 and 23:59, the allergy %i lines before the request: the generator receives "lactose, castanhas"', async (back) => {
    vi.setSystemTime(AFTER_MIDNIGHT)
    const h = harness({
      now: AFTER_MIDNIGHT,
      text: REQUEST,
      history: beforeMidnight(back),
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST, AFTER_MIDNIGHT)

    expect(h.generatorCalls).toHaveLength(1)
    expect(restrictionsSent(h)).toBe('lactose, castanhas')
    // The whole session went to the model. Its lines are of the previous
    // calendar day, so each keeps its date prefix.
    const sent = (h.chatCalls[0]?.messages ?? []).slice(0, -1)
    expect(sent).toHaveLength(49)
    expect(sent.every((message) => String(message.content).startsWith(DATED_04))).toBe(true)
    expect(sent.filter((message) => message.content === `${DATED_04}${ALLERGY}`)).toHaveLength(1)
  })

  it('the session reaches 6 hours back and no further: a line said 6 h before the turn stays, one said a minute earlier is cut', async () => {
    vi.setSystemTime(AFTER_MIDNIGHT)
    const at = (minutesBefore: number) =>
      new Date(AFTER_MIDNIGHT.getTime() - minutesBefore * 60_000).toISOString()
    const history = [
      line('in', 'Dita às 18:04.', at(361), 0),
      line('out', 'Dita às 18:05.', at(360), 1),
      // 16 lines between 23:44 and 23:59: the window has no room for older ones.
      ...Array.from({ length: 16 }, (_, index) =>
        line(index % 2 === 0 ? 'in' : 'out', `Linha ${index}`, at(21 - index), 2 + index),
      ),
    ]
    const h = harness({ now: AFTER_MIDNIGHT, text: REQUEST, history, chat: [{ content: 'ok' }] })
    await flow(h, REQUEST, AFTER_MIDNIGHT)

    const sent = (h.chatCalls[0]?.messages ?? []).slice(0, -1).map((message) => message.content)
    expect(sent).toHaveLength(17)
    expect(sent[0]).toBe(`${DATED_04}Dita às 18:05.`)
    expect(sent).not.toContain(`${DATED_04}Dita às 18:04.`)
  })

  // Declared, not fixed: restrictions are not stored in the profile, so one
  // said on a previous day more than 6 hours before the turn reaches the
  // generator only while its line is among the newest older lines the window
  // still carries.
  it('RC PERF-W1 (not covered) — the allergy said YESTERDAY morning, beyond the window: the generator receives "(nenhuma)"', async () => {
    const yesterday = (index: number, content: string, direction: 'in' | 'out') =>
      line(
        direction,
        content,
        new Date(Date.parse('2026-10-03T12:00:00.000Z') + index * 60_000).toISOString(),
        index,
      )
    const history = [
      yesterday(0, ALLERGY, 'in'),
      yesterday(1, 'Anotado.', 'out'),
      // 20 lines of today: the window is theirs, no previous-day line fits.
      ...session(20, 0).map((row, index) => ({
        ...row,
        provider_message_id: `mobile_flow/qa-a/t${index}`,
      })),
    ]
    const h = harness({
      text: REQUEST,
      history,
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST)

    expect(h.chatCalls[0]?.messages).toHaveLength(21)
    expect(restrictionsSent(h)).toBe('(nenhuma)')
  })

  it('RC PERF-W1 (not covered) — at 00:05, the allergy said at 17:50 and 20 lines after 23:30: the generator receives "(nenhuma)"', async () => {
    vi.setSystemTime(AFTER_MIDNIGHT)
    const at = (minutesBefore: number) =>
      new Date(AFTER_MIDNIGHT.getTime() - minutesBefore * 60_000).toISOString()
    const history = [
      line('in', ALLERGY, at(375), 0),
      line('out', 'Anotado.', at(374), 1),
      ...Array.from({ length: 20 }, (_, index) =>
        line(
          index % 2 === 0 ? 'in' : 'out',
          index % 2 === 0 ? `Pergunta ${index}` : `Resposta ${index}: tudo certo.`,
          at(26 - index),
          2 + index,
        ),
      ),
    ]
    const h = harness({
      now: AFTER_MIDNIGHT,
      text: REQUEST,
      history,
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST, AFTER_MIDNIGHT)

    expect(h.chatCalls[0]?.messages).toHaveLength(21)
    expect(restrictionsSent(h)).toBe('(nenhuma)')
  })

  it('the allergy said yesterday, with a short day today: its line is still in the window, dated', async () => {
    const history = [
      line('in', ALLERGY, '2026-10-03T12:00:00.000Z', 0),
      line('out', 'Anotado.', '2026-10-03T12:01:00.000Z', 1),
      ...session(4, 0).map((row, index) => ({
        ...row,
        provider_message_id: `mobile_flow/qa-a/t${index}`,
      })),
    ]
    const h = harness({
      text: REQUEST,
      history,
      chat: [FAITHFUL],
      generator: [MENU_GENERATION],
    })
    await flow(h, REQUEST)

    expect(h.chatCalls[0]?.messages[0]?.content).toBe(
      `[Mensagem de 03/10/2026, dia anterior — números do dia e horário citados nela não valem para hoje]\n${ALLERGY}`,
    )
    expect(restrictionsSent(h)).toBe('lactose, castanhas')
  })
})

// ── 6. Status answer as plain text ──────────────────────────────────────────
describe('audit 2026-10-04 Flow calls — the status answer reaches the app as plain text', () => {
  const STATUS_SCRIPT: ChatStep[] = [
    { toolCalls: [tool('consulta_progresso')] },
    { content: 'NUNCA CHAMADO' },
  ]
  const CLOSED = [
    { calories_consumed: 2750, calories_target: 2980, day_closed: true },
    { calories_consumed: 3100, calories_target: 2980, day_closed: true },
  ]

  /** What WhatsApp sends today for the same day (the card's order is the pipeline's). */
  const WHATSAPP_STATUS = [
    '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP) · 0 bloco(s) de 7.700 completo(s)',
    '',
    '🔥 Consumido: **541 / 2.980 kcal (18%)**',
    '🎯 Restam: **2.439 kcal**',
    '💪 Proteína: **59.0 / 144g (41%)**',
    '🏃🏻 Exercício: **322 kcal**',
    '📊 Orçamento 14d: **5.850 / 5.960 kcal (98%)** · DAM: 1/2',
  ].join('\n')

  const FLOW_STATUS = [
    'Sequência: 3 dias consecutivos · Nível 2 (1.240 XP)',
    '',
    'Consumido: 541 / 2.980 kcal (18%)',
    'Restam para comida: 2.439 kcal',
    'Proteína: 59.0 / 144g (41%)',
    'Exercício: 322 kcal',
    '',
    'O Bloco 7.700 é exibido apenas na recomposição corporal.',
  ].join('\n')

  const digits = (text: string) => text.replace(/\D/g, '')

  it('"Como está meu dia até agora?" on WhatsApp: the card, byte for byte as before', async () => {
    const h = harness({
      channel: 'whatsapp',
      text: STATUS_PHRASE,
      chat: STATUS_SCRIPT,
      closedDays: CLOSED,
    })
    const output = await whatsapp(h, STATUS_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(output.text).toBe(WHATSAPP_STATUS)
    expect(output.singleMessage).toBe(true)
  })

  it('"Como está meu dia até agora?" on the Flow: preserved day values, no block progress or pending budget in gain', async () => {
    const h = harness({ text: STATUS_PHRASE, chat: STATUS_SCRIPT, closedDays: CLOSED })
    const output = await flow(h, STATUS_PHRASE)

    expect(h.chatCalls).toHaveLength(1)
    expect(output.text).toBe(FLOW_STATUS)
    expect(output.text).not.toMatch(/[*_]/)
    expect(output.text).not.toMatch(/\p{Extended_Pictographic}/u)
    // decisions-v1 item5 supersedes formatting-only parity for Flow. Pin
    // each preserved day line; the complete WhatsApp golden above is intact.
    expect(output.text.split('\n').slice(2, 6)).toEqual([
      'Consumido: 541 / 2.980 kcal (18%)',
      'Restam para comida: 2.439 kcal',
      'Proteína: 59.0 / 144g (41%)',
      'Exercício: 322 kcal',
    ])
    expect(output.text).not.toMatch(/bloco\(s\)|Orçamento|DAM/)
    expect(output.singleMessage).toBe(true)
    // The same events as before: the path itself did not change.
    expect(eventNames(h)).toEqual([
      'pipeline.deterministic_status',
      'llm.card_replaced',
      MOBILE_FLOW_CALLS_EVENT,
      'llm.cache_usage',
    ])
  })

  it.each(['ganho_massa', 'manutencao'])('%s with historical nonzero block keeps the day and progress values without exposing block or budget', async (protocol) => {
    const h = harness({
      text: STATUS_PHRASE,
      chat: STATUS_SCRIPT,
      closedDays: CLOSED,
      profile: { ...PROFILE, current_protocol: protocol },
      progress: { ...PROGRESS, blocks_completed: 4, deficit_block: 3120 },
    })
    const output = await flow(h, STATUS_PHRASE)

    expect(output.text).toBe(FLOW_STATUS)
    expect(output.text).not.toMatch(/bloco\(s\)|3\.120|Orçamento|DAM/)
    expect(output.text.match(/O Bloco 7\.700 é exibido apenas/g)).toHaveLength(1)
    expect(h.chatCalls).toHaveLength(1)
    expect(output.singleMessage).toBe(true)
  })

  it('spoofed mobile_flow provider on the legacy entry does not opt into Flow status presentation', async () => {
    const h = harness({ channel: 'whatsapp', text: STATUS_PHRASE, chat: STATUS_SCRIPT, closedDays: CLOSED })
    const output = await processMessage(h.deps, {
      from: '5511999999999',
      providerMessageId: TURN_ID,
      text: STATUS_PHRASE,
      contentType: 'text',
      provider: 'mobile_flow',
      timestamp: NOW,
    })

    expect(output.text).toBe(WHATSAPP_STATUS)
    expect(h.chatCalls).toHaveLength(1)
    expect(output.singleMessage).toBe(true)
    expect(eventNames(h)).not.toContain(MOBILE_FLOW_CALLS_EVENT)
  })

  it('recomposition keeps a completed block and its unchanged balance even with closed budget days', async () => {
    const h = harness({
      text: STATUS_PHRASE,
      chat: STATUS_SCRIPT,
      closedDays: CLOSED,
      profile: { ...PROFILE, current_protocol: 'recomposicao', deficit_level: 500 },
      progress: { ...PROGRESS, blocks_completed: 4, deficit_block: 3120 },
      day: { ...DAY, calories_target: 2200, calories_consumed: 2330, protein_g: 150, protein_target: 180 },
    })
    const output = await flow(h, STATUS_PHRASE)

    expect(output.text).toBe([
      'Sequência: 3 dias consecutivos · Nível 2 (1.240 XP) · 4 bloco(s) de 7.700 completo(s)',
      '',
      'Consumido: 2.330 / 2.200 kcal (106%)',
      'Excesso alimentar: 130 kcal',
      'Proteína: 150 / 180g (83%)',
      'Exercício: 322 kcal (acelera o bloco 7.700)',
      'Bloco 7.700: 3.120 / 7.700 kcal (41%)',
    ].join('\n'))
    expect(output.text).not.toMatch(/Orçamento|DAM|é exibido apenas/)
    expect(h.chatCalls).toHaveLength(1)
    expect(output.singleMessage).toBe(true)
  })

  it('recomposição above the target with a workout: "Excesso alimentar", the block note and "Bloco 7.700"', async () => {
    const fixture: Fixture = {
      text: STATUS_PHRASE,
      chat: STATUS_SCRIPT,
      profile: { ...PROFILE, current_protocol: 'recomposicao', deficit_level: 500 },
      day: {
        ...DAY,
        calories_target: 2200,
        calories_consumed: 2330,
        protein_g: 150,
        protein_target: 180,
      },
    }
    const legacy = await whatsapp(harness({ ...fixture, channel: 'whatsapp' }), STATUS_PHRASE)
    const mobile = await flow(harness(fixture), STATUS_PHRASE)

    expect(legacy.text).toBe(
      [
        '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP) · 0 bloco(s) de 7.700 completo(s)',
        '',
        '🔥 Consumido: **2.330 / 2.200 kcal (106%)**',
        '🎯 Excedente: **130 kcal**',
        '💪 Proteína: **150 / 180g (83%)**',
        '🏃🏻 Exercício: **322 kcal** _(acelera o bloco 7700)_',
        '📊 Bloco 7700: **3.120 / 7.700 kcal (41%)**',
      ].join('\n'),
    )
    expect(mobile.text).toBe(
      [
        'Sequência: 3 dias consecutivos · Nível 2 (1.240 XP) · 0 bloco(s) de 7.700 completo(s)',
        '',
        'Consumido: 2.330 / 2.200 kcal (106%)',
        'Excesso alimentar: 130 kcal',
        'Proteína: 150 / 180g (83%)',
        // One spelling of the block in the whole answer (review 2026-10-04:
        // the note said "7700" right above the label "7.700").
        'Exercício: 322 kcal (acelera o bloco 7.700)',
        'Bloco 7.700: 3.120 / 7.700 kcal (41%)',
      ].join('\n'),
    )
    expect(mobile.text).not.toContain('7700')
    expect(digits(mobile.text)).toBe(digits(legacy.text))
  })

  it('the food line keeps its meaning: target minus consumed, with no exercise in it (docs/CALCULO-MPP.md §2a)', async () => {
    const h = harness({ text: STATUS_PHRASE, chat: STATUS_SCRIPT, closedDays: CLOSED })
    const output = await flow(h, STATUS_PHRASE)

    // 2,980 − 541 = 2,439. With the 322 kcal of exercise it would read 2,761.
    expect(output.text).toContain('Restam para comida: 2.439 kcal')
    expect(output.text).not.toContain('2.761')
  })

  it('a status question the MODEL answers is not touched', async () => {
    const reply = 'Você consumiu 541 de 2.980 kcal; *restam* 2.439 kcal para comida.'
    const h = harness({ text: STATUS_PHRASE, chat: [{ content: reply }] })
    const output = await flow(h, STATUS_PHRASE)

    expect(output.text).toBe(reply)
  })

  it('a non-deterministic Flow card preserves public values and omits only C3/C4 metrics', async () => {
    const h = harness({
      text: STATUS_PHRASE,
      chat: [{ content: WHATSAPP_STATUS }],
      closedDays: CLOSED,
    })
    const output = await flow(h, STATUS_PHRASE)

    expect(output.text).toBe([
      '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP)',
      '',
      '🔥 Consumido: **541 / 2.980 kcal (18%)**',
      '🎯 Restam: **2.439 kcal**',
      '💪 Proteína: **59.0 / 144g (41%)**',
      '🏃🏻 Exercício: **322 kcal**',
      '',
      'O Bloco 7.700 é exibido apenas na recomposição corporal.',
    ].join('\n'))
    expect(h.chatCalls).toHaveLength(1)
    expect(output.singleMessage).toBe(false)
    expect(eventNames(h)).not.toContain('pipeline.deterministic_status')
  })

  it('the renderer only removes marks, renames three labels and spells the block one way', () => {
    const card = composeStatusMessage(
      {
        caloriesConsumed: 1240,
        caloriesTarget: 2980,
        proteinG: 96,
        proteinTarget: 180,
        exerciseCalories: 322,
        deficitBlock: 3120,
        protocol: 'recomposicao',
        last14d: null,
      },
      { currentStreak: 1, level: 2, xpTotal: 120, blocksCompleted: 1 },
    )
    const plain = flowPlainStatusText(card)

    expect(plain).toBe(
      [
        'Consumido: 1.240 / 2.980 kcal (42%)',
        'Restam para comida: 1.740 kcal',
        'Proteína: 96 / 180g (53%)',
        'Exercício: 322 kcal (acelera o bloco 7.700)',
        'Bloco 7.700: 3.120 / 7.700 kcal (41%)',
        '',
        'Sequência: 1 dia consecutivo · Nível 2 (120 XP) · 1 bloco(s) de 7.700 completo(s)',
      ].join('\n'),
    )
    expect(digits(plain)).toBe(digits(card))
    // Applying it again, or to text with no marks, changes nothing.
    expect(flowPlainStatusText(plain)).toBe(plain)
    const prose = 'Restam 2.439 kcal para comida hoje. Seu bloco 7700 está em 41%.'
    expect(flowPlainStatusText(prose)).toBe(prose)
  })

  // The labels are the app's: read from its strings catalog (read-only), so a
  // label renamed in the app fails here instead of drifting.
  const catalog = fileURLToPath(
    new URL(
      '../../../../apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings',
      import.meta.url,
    ),
  )

  it.skipIf(!existsSync(catalog))(
    'every renamed or kept label is a label of the Today screen',
    () => {
      const strings = (
        JSON.parse(readFileSync(catalog, 'utf8')) as {
          strings: Record<
            string,
            { localizations?: Record<string, { stringUnit?: { value?: string } }> }
          >
        }
      ).strings
      const label = (key: string) => strings[key]?.localizations?.['pt-BR']?.stringUnit?.value
      const lines = FLOW_STATUS.split('\n')
      const recomp = flowPlainStatusText(
        '🎯 Excedente: **130 kcal**\n📊 Bloco 7700: **0 / 7.700 kcal (0%)**',
      )

      expect(lines[2]).toMatch(new RegExp(`^${label('metric.consumed')}: `))
      expect(lines[3]).toMatch(new RegExp(`^${label('today.energy.food-remaining')}: `))
      expect(lines[4]).toMatch(new RegExp(`^${label('today.protein.title')}: `))
      expect(lines[5]).toMatch(new RegExp(`^${label('today.energy.exercise')}: `))
      expect(recomp).toBe(
        `${label('today.energy.food-excess')}: 130 kcal\n${label('today.block.title')}: 0 / 7.700 kcal (0%)`,
      )
    },
  )
})

// ── 7. The declared pendencies are the same in the tests and in the doc ─────
describe('audit 2026-10-04 Flow calls — every pendency of the Flow work reads the same in the test headers and in the doc', () => {
  // CLAUDE.md: an uncovered variant is declared with the SAME wording in the
  // test header and in the doc. The second review of 2026-10-04 found nine
  // lines whose id and scenario matched and whose words did not, so a search
  // for one side's line did not find the other. The third review found the
  // lines equal and the explanation under them different in 28 entries, one
  // of them with the opposite meaning (RC PERF-C11: "vai junto" in the test,
  // "vai embora junto" in the doc). The WHOLE entry is compared now: the
  // line and the explanation that follows it.
  const RC_LINE = /^> RC [A-Z0-9-]+ — cenário .+ \(pendência da audit 2026-10-04\)\. \S/
  const path = (relative: string) => fileURLToPath(new URL(relative, import.meta.url))
  const DOC = path('../../../../docs/mobile/flow-performance.md')
  const HEADERS = [
    path('./audit-10-04-flow-turn-calls.test.ts'),
    path('./audit-10-04-flow-prompt-budget.test.ts'),
    path('./audit-10-04-whatsapp-request-lock.test.ts'),
    path('../../../../apps/admin/src/lib/mobile-api/flow-chat-service.turn-limit.test.ts'),
  ]
  const present = existsSync(DOC) && HEADERS.every((file) => existsSync(file))

  /**
   * The entries among `lines`: each starts at a "> RC" line and takes the
   * lines after it up to an empty one or to the next entry, joined by one
   * space. That is how an entry reads whatever the width it was wrapped at.
   */
  const entriesIn = (lines: string[]): string[] => {
    const entries: string[] = []
    let current: string[] | null = null
    for (const line of lines) {
      if (line.startsWith('> RC ')) {
        if (current) entries.push(current.join(' '))
        current = [line]
      } else if (current && line !== '') {
        current.push(line)
      } else if (current) {
        entries.push(current.join(' '))
        current = null
      }
    }
    if (current) entries.push(current.join(' '))
    return entries
  }
  /** The entries of a test file's header (what comes before its test code). */
  const headerEntries = (file: string): string[] => {
    const source = readFileSync(file, 'utf8')
    const header = source.slice(0, source.search(/^(?:const|describe|function|beforeEach)\b/m))
    // The comment marks go, the words stay.
    return entriesIn(
      header.split('\n').map((line) => line.replace(/^\s*(?:\*\/|\*|\/\/)/, '').trim()),
    )
  }
  /** The entries of the doc: its "> RC" paragraphs (continuation marks removed). */
  const docEntries = (): string[] =>
    entriesIn(
      readFileSync(DOC, 'utf8')
        .split('\n')
        .map((line) => (line.startsWith('> RC ') ? line : line.replace(/^>\s?/, '')).trim()),
    ).filter((entry) => entry.startsWith('> RC '))

  it('the reader takes the whole entry: the line and every line of its explanation', () => {
    expect(
      entriesIn(['texto', '> RC X-1 — cenário a NÃO coberto.', 'Primeira', 'segunda.', '', 'fora']),
    ).toEqual(['> RC X-1 — cenário a NÃO coberto. Primeira segunda.'])
    expect(entriesIn(['> RC X-1 — a.', 'b', '> RC X-2 — c.', 'd'])).toEqual([
      '> RC X-1 — a. b',
      '> RC X-2 — c. d',
    ])
  })

  it.skipIf(!present)(
    'each entry of a test header is in the doc, line and explanation, character for character',
    () => {
      const doc = docEntries()
      const entries = HEADERS.flatMap(headerEntries)
      // 29 ids in 30 entries (RC LOCK is two), and W1 and W2 sit in two headers.
      expect(entries).toHaveLength(32)
      for (const entry of entries) {
        // Every entry has the declared form and an explanation after its line.
        expect(entry).toMatch(RC_LINE)
        expect(doc).toContain(entry)
      }
    },
  )

  it.skipIf(!present)(
    'each entry of the doc is in a test header, line and explanation, character for character',
    () => {
      const headers = HEADERS.flatMap(headerEntries)
      const entries = docEntries()
      expect(entries).toHaveLength(30)
      for (const entry of entries) {
        expect(entry).toMatch(RC_LINE)
        expect(headers).toContain(entry)
      }
    },
  )

  it.skipIf(!present)(
    'RC PERF-C11 says the same thing on both sides: the sentence about the other question is lost',
    () => {
      const everywhere = [...HEADERS.flatMap(headerEntries), ...docEntries()].filter((entry) =>
        entry.startsWith('> RC PERF-C11 '),
      )
      expect(everywhere).toHaveLength(2)
      for (const entry of everywhere) expect(entry).toContain('vai embora junto')
    },
  )
})


// C1: the final public boundary runs after direct suggestion reconstruction.
describe('C1 — direct suggestion and retry replay preserve the stored draft', () => {
  it.each([false, true])('keeps exercises, sets, rest, review CTA and identifiers (replay=%s)', async replay => {
    const generated = WORKOUT_OUTPUT.replace('Agachamento livre', 'Agachamento livre (BMR: 1836 kcal)')
    const payload = JSON.parse(generated) as Row
    const h = harness({
      text: WORKOUT_PHRASE,
      chat: [WORKOUT_CALL],
      generator: [{ ...WORKOUT_GENERATION, content: generated }],
      ...(replay ? { drafts: { [`${TURN_ID}:propoe_plano_treino`]: { id: 'draft-earlier', status: 'ready_for_review', payload } } } : {}),
    })
    const output = await flow(h, WORKOUT_PHRASE)
    expect(output.text).toContain('• Agachamento livre')
    expect(output.text).toContain('3×12-15, descanso 90 s')
    expect(output.text).toContain('• Supino reto com barra — 3×12-15, descanso 90 s')
    expect(output.text).toContain(CLOSING)
    expect(output.text).not.toMatch(/BMR|1836/)
    expect(output.toolCalls[0]?.result).toMatchObject({ success: true, draft_id: replay ? 'draft-earlier' : 'draft-0001', status: 'ready_for_review' })
    expect(h.generatorCalls).toHaveLength(replay ? 0 : 1)
    expect(drafts(h)).toHaveLength(replay ? 0 : 1)
    // The display projection never rewrites the stored plan to hide a word.
    if (!replay) expect(JSON.stringify(drafts(h)[0]?.p_payload)).toContain('Agachamento livre (BMR: 1836 kcal)')
  })
})
