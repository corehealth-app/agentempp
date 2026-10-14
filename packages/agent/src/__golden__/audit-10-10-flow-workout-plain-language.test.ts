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
 *  - the two decisions that waited are ON since the second round of
 *    2026-10-10, by decisão do orquestrador, anunciada ao dono em 2026-10-10,
 *    que pode riscar qualquer uma (the owner's written yes is still blank in
 *    the doc): "Hip Thrust" and "Military press" carry the Portuguese name
 *    with the original in parentheses (RC TL-13) and an effort grade from 1
 *    to 10 says "de 10" (RC TL-14). "Stiff" and "Leg Press" stay as generated.
 *
 * Second round of 2026-10-10 (this file was written for 3b65bee and changed
 * here on purpose): the expected texts of sections A, B and L follow the two
 * decisions; section N is new (a repetitions or effort text over 40
 * characters with the phrase the Flow prompt teaches no longer refuses the
 * suggestion); the pendencies went from 16 to 22 lines.
 *
 * The term search of A1/A4/B1 walks the TEXT VALUES of the payload (string
 * leaves and list items), never JSON.stringify, and a term counts only as a
 * whole word (a letter, a digit or "_" next to it is glue): otherwise "reps"
 * would match the KEY "reps_range" and the test could never be green.
 *
 * > RC TL-1 — cenário rascunho de treino do Flow de 2026-10-10 16:44:49Z (conta de teste, 5 dias, 29 exercícios) variante os 23 exercícios, o grupo muscular de 3 exercícios e os dias de terça e quinta, cujo texto o arquivo de evidência não traz NÃO coberta nesta PR (pendência da audit 2026-10-10). O fim do chat só está provado no recorte de 3 dias e 6 exercícios: para o turno relatado inteiro o golden é variante próxima. No plano inteiro o texto simples é mais longo (só o parágrafo de progressão cresce 35 caracteres) e o chat pode terminar em '(O restante está em "Revisar sugestão".)' sem o parágrafo de progressão e sem o último dia; a aba Plano continua com tudo. Só a releitura autorizada do rascunho inteiro, fora desta raia, fecha esta linha.
 * > RC TL-2 — cenário termos "porção clavicular", "cabeça longa do tríceps", "isquiotibiais", "gastrocnêmio", "sóleo", "cadeia posterior" e "Military press" variante a frase exata em que cada um apareceu no rascunho de 2026-10-10 (não está no arquivo de evidência; os seis primeiros são cobertos numa frase de teste, que é variante próxima, inclusive com barra; o sétimo é renomeado desde a segunda rodada: RC TL-13) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-3 — cenário sugestão de treino do Flow variante resposta do MODELO REAL ao pedido de linguagem simples (o modelo é roteirizado nos testes; nenhum turno real rodou com o pedido novo) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-4 — cenário termo técnico ou nome em inglês variante FORA do vocabulário fechado (por exemplo "peitoral", "quadríceps", "dorsal", "deltoide", "amplitude", "stress", "escápulas" sem "retraídas", "unilateral" e "unilaterais", "pegada neutra", "cabeça longa" sem o músculo, "Upper back", "Pulldown", "Pullover", "Crossover", "drop set") NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-5 — cenário linha do exercício no chat ("• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s", que a tela do dono mostrava como "• Hip Thrust com Barra — 4×8-12, descanso 90 s") variante a notação séries×repetições, o "s" de segundos e o rótulo "Progressão:" NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-6 — cenário rascunho de treino gravado ANTES desta mudança (inclusive o de 2026-10-10 16:44:49Z no ambiente de teste) e mensagem do chat já gravada variante texto já armazenado, que não é reescrito NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-7 — cenário campo cujo texto simples passaria do limite (observações, progressão e equipamentos 500; observação do exercício, passos e erros 300; nome 120; foco e grupo muscular 80; repetições e esforço 40; dia 20) variante frases ou campo que ficam como o gerador escreveu, por exemplo o dia "Upper A" NÃO coberta nesta PR (pendência da audit 2026-10-10). No campo do dia, "Upper" e "Lower" nunca são trocadas: "Parte de cima do corpo" tem 22 caracteres, "Parte de baixo do corpo" tem 23 e o limite é 20; um plano com os dias "Upper A" e "Lower A" continua com esses dois rótulos em inglês no chat e na aba Plano.
 * > RC TL-8 — cenário perguntas do Flow ANTES de montar o treino e respostas a dúvidas depois variante texto livre do chat fora do turno da sugestão (inclusive uma pergunta sobre "falha muscular" vinda da descrição do parâmetro compartilhado) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-9 — cenário sugestão de treino para conta em INGLÊS variante pedido ao gerador e vocabulário só em português NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-10 — cenário frase depois da troca variante redação que continua sem ser do dia a dia, porque a rede troca palavras e não reescreve a frase ("Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo)", "Exercício de vários músculos principal para peitoral", "Panturrilha (músculo da panturrilha)") NÃO coberta nesta PR (pendência da audit 2026-10-10). A concordância com a palavra vizinha também não é ajustada: "12 rep" vira "12 repetição", "MMII fortes" vira "Parte de baixo do corpo fortes" e "Treine a PSE 8" vira "Treine o esforço 8 de 10" (o "a" era preposição e foi lido como artigo).
 * > RC TL-11 — cenário plano importado de foto ou PDF, texto digitado pela pessoa em "Revisar sugestão" e sugestão de cardápio variante texto que não é sugestão de treino escrita pelo Flow, deixado como está de propósito NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-12 — cenário frase de abertura ou de fecho escrita pelo modelo no turno da sugestão de treino variante termo técnico fora do bloco da sugestão NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-13 — cenário nomes de exercício em inglês vistos pelo dono ("Hip Thrust com Barra", "Stiff Unilateral com Halter", "Leg Press 45°") e "Military press" variante "Stiff" e "Leg Press", que ficam como o gerador escreveu (é o nome da máquina e o que as academias do Brasil usam); qualquer outro nome em inglês; as outras palavras em inglês do mesmo nome, que ficam ("Single Leg Hip Thrust" vira "Single Leg elevação pélvica (Hip Thrust)"); o nome que o gerador já escreveu entre parênteses ("Glúteos (hip thrust)"); o campo ou a frase que já traz o nome em português, que fica como veio ("Hip Thrust (elevação pélvica)"); a lista de equipamentos ("banco para hip thrust"); e a segunda menção no mesmo texto, que fica só com o nome em português NÃO coberta nesta PR (pendência da audit 2026-10-10). Coberto desde a segunda rodada de 2026-10-10, por decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma: "Hip Thrust" vira "Elevação pélvica" e "Military press" vira "Desenvolvimento militar", com o nome original entre parênteses ("Hip Thrust com Barra" vira "Elevação pélvica com Barra (Hip Thrust)"); quando o resultado não cabe no limite do campo, fica só o nome em português (RC TL-22). A frase exata em que "Military press" apareceu no rascunho de 2026-10-10 não está no arquivo de evidência.
 * > RC TL-14 — cenário "Esforço alvo 9" na aba Plano variante nota fora de 1 a 10 ("15"), esforço escrito em palavras ("moderado"), nota que o próprio gerador escreveu depois da palavra "esforço" em texto corrido ("esforço 8-9"), nota que continua depois do número ou é seguida de um sinal fora da lista fechada ("RPE 8/9", "RPE 8+", "RPE 8 ou 9", "RPE 8 para 9", "RPE 8 - RIR 2"), faixa escrita com espaço ao lado do traço ou com " a " e seguida de palavra ou de "(", em que o segundo número pode ser outra coisa ("RPE 8 - 10 repetições", "RPE 8 a 10 repetições por série", e também a faixa de verdade "RPE 8 a 9 nas últimas séries"), nota seguida de outro texto no próprio rpe_target, sem a sigla ("8 (pesado)") e nota cuja frase já diz a escala depois dela ("RPE 8 (de 10)", "RPE 8 numa escala de 1 a 10"), que ficam sem a escala NÃO coberta nesta PR (pendência da audit 2026-10-10). Coberto desde a segunda rodada de 2026-10-10, por decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma: a nota de 1 a 10 sozinha em rpe_target ganha a escala ("9" vira "9 de 10", e com ponto final "9." vira "9 de 10.") e a nota depois da sigla, no texto, também ("RPE 8-9" vira "esforço 8-9 de 10"). A faixa com espaço ao lado do traço seguida do fim da frase ou de pontuação é lida como faixa e ganha a escala ("RPE 8 - 9." vira "esforço 8 - 9 de 10."), também se o gerador quis dizer outra coisa com o segundo número. O "10" da escala é o único número que a rede acrescenta; o documento do método não define a escala.
 * > RC TL-15 — cenário grafia do vocabulário fechado variante que a regra deixa passar de propósito (colada a letra, número, "_", "@" ou "-"; sigla em minúsculas, como "rpe" e "rir"; a sigla RIR com número dos dois lados, como "Séries de 12 RIR 2"; "PSE" antes de palavra terminada em "a" ou "as"; as divisões em inglês dentro de nome de exercício ou de equipamento; Push, Pull, Legs, Upper, Lower e Core vizinhas de uma palavra da lista fechada de inglês; "falha" fora de "até", "até a", "à", "próximo da", "próximo à", "perto da", "antes da", e depois de "à" quando segue "de", "do", "da", "na", "no" ou "em" (nos campos de repetições e de esforço a palavra sozinha também é trocada, dentro da gramática fechada: RC TL-18); "composto" e "isolador" depois de uma palavra que não anuncia nome, como um verbo, ou "composto" antes de "por", de "de" e de palavra de substância, também com um advérbio da lista fechada no meio quando vem no início, depois de pontuação, de "e" ou de "ou" (RC TL-17); "escápulas retraídas" depois de outra palavra terminada em "as" ou antes de "e" ou vírgula mais uma palavra terminada em "adas" ou "idas"; trecho de endereço), composto em inglês com vizinha fora da lista, trocado palavra por palavra em texto corrido ("Core Blaster" vira "abdômen Blaster"), frase trocada pela metade ("Combine compostos e isoladores" vira "Combine compostos e exercícios de um músculo só"), e grafia colada a letra ou número de outro alfabeto, que não conta como cola ("Treino de Coreж" vira "Treino de abdômenж") NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-16 — cenário turno relatado ("Nenhuma limitacao e sem prioridade", 2026-10-10 16:44:49Z) variante a resposta do modelo na segunda chamada do turno, os argumentos que ele passou à ferramenta e a data de nascimento da conta de teste, que não foram registrados NÃO coberta nesta PR (pendência da audit 2026-10-10). A mensagem não é um pedido único: o turno faz duas chamadas ao modelo. No golden a segunda resposta é roteirizada nas duas formas possíveis (o modelo resume, e o sistema põe a sugestão gravada entre a abertura e o fecho fixos, que é o fecho que a tela mostrou; ou o modelo copia a sugestão), e os argumentos são reconstruídos da conversa.
 * > RC TL-17 — cenário "composto" usado como particípio ("Treino ABC, composto principalmente por exercícios básicos.") variante outra palavra entre o particípio e a preposição que não seja advérbio da lista fechada (palavra terminada em "mente", "apenas", "só", "sobretudo", "quase", "também", "ainda", "sempre", "tanto", "em grande parte", "em sua maioria", "na maior parte"), como em "Treino ABC, composto na prática por exercícios básicos.", que continua trocada; vírgula no meio ("composto, na prática, por"); e particípio logo depois de artigo ou de preposição NÃO coberta nesta PR (pendência da audit 2026-10-10). A leitura através do advérbio também deixa como o gerador escreveu um nome seguido de advérbio da lista e de "de" ou "por", no início, depois de pontuação, de "e" ou de "ou" ("Compostos sempre de manhã." fica). A segunda frase do revisor não está em nenhum registro: a de "e" foi escrita no teste.
 * > RC TL-18 — cenário "falha" ou "falha técnica" escrita sozinha no campo de repetições ou de esforço variante valor cujo texto simples passa de 40 caracteres ("10-12 ou falha" teria 41, como "12-15 ou falha" e "10-12 ou até a falha": é a faixa de dois dígitos, o valor mais provável do campo), que fica como o gerador escreveu, e "falha" fora da gramática fechada: depois de outra palavra ("sem falha"), colada a hífen ("pré-falha") ou seguida de outra palavra ("Falha total") NÃO coberta nesta PR (pendência da audit 2026-10-10). As grafias cobertas foram tiradas da leitura do código; as do revisor não estão em nenhum registro. Fechar a faixa de dois dígitos pede que a rede mova texto de um campo para outro (como o gerador faz com a frase ensinada: RC TL-21), o que não foi decidido.
 * > RC TL-19 — cenário rótulo do esforço repetido em rpe_target variante campo que é só o rótulo ("RPE" vira "Esforço"), rótulo no meio de uma frase ("Mantenha RPE alto" vira "Mantenha esforço alto"), rótulo seguido de mais de uma palavra ("Esforço percebido 8" fica), rótulo seguido de palavra que é parte do próprio nome ("Esforço percebido" fica) e "PSE" antes de palavra terminada em "a" ("PSE alta" fica) NÃO coberta nesta PR (pendência da audit 2026-10-10). As grafias cobertas foram tiradas da leitura do código; as do revisor não estão em nenhum registro.
 * > RC TL-20 — cenário tempo da rede de linguagem simples variante sequência longa de pontos ou de letras sem espaço, cujo custo ainda cresce mais depressa que o tamanho do texto (medido com um build do Xcode ao lado: 4.000 pontos em 78 ms e 4.000 letras em 31 ms; nos 500 caracteres de um campo, 5 ms e 2 ms) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC TL-21 — cenário reps_range ou rpe_target com mais de 40 caracteres variante texto sem a frase "última repetição bem feita", que continua recusando a sugestão inteira (como já acontece com nome acima de 120, foco acima de 80 e dia acima de 20), e texto com a frase cujo original, movido para o começo da observação do exercício, faz a observação passar de 300 caracteres: ela é cortada no fim com "…" pela regra que já existe NÃO coberta nesta PR (pendência da audit 2026-10-10). A frase escrita com hífen ("até a última repetição bem-feita") conta como a frase desde a revisão da segunda rodada.
 * > RC TL-22 — cenário escala "de 10" da nota de esforço e nome original entre parênteses variante campo cujo texto passaria do limite com eles (rpe_target "RPE 9, até a falha" teria 41 caracteres com a escala e fica "9, até a última repetição bem feita"): sai primeiro a escala, depois o parêntese, e só então vale RC TL-7; a telemetria não conta essas omissões NÃO coberta nesta PR (pendência da audit 2026-10-10)
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
/** RC TL-13: renamed since the second round — the Portuguese name, with this one in parentheses. */
const RENAMED_TERM = 'Hip Thrust'
/** The stored name of the exercise the owner read as "Hip Thrust com Barra". */
const RENAMED_NAME = 'Elevação pélvica com Barra (Hip Thrust)'
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
  'Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo), Quinta (Ombros+abdômen), Sexta (pernas posterior). Exercícios de vários músculos primeiro, exercícios de um músculo só depois. 10-20 séries/músculo/semana. Descanso 60-120s. Treino até próximo da última repetição bem feita (esforço 8-9 de 10). Aqueça sempre: 5min cardio leve + séries progressivas. Hidrate-se. Durma 7-9h. Qualquer dor articular, pare e reavalie técnica.'
const PLAIN_PROGRESSION =
  'Como intermediário, use evolução passo a passo: inicie cada exercício com 6 repetições. A cada treino, adicione 1 repetição mantendo o peso. Quando atingir 12 repetições com técnica perfeita, aumente a carga e volte para 6 repetições. Registre peso e repetições a cada sessão.'
/** The four lines the screen of the OWNER ended on (the evidence: A0 and B3). They are not what is stored now. */
const SCREEN_LAST_LINES =
  '• Cadeira Abdutora — 3×12-15, descanso 60 s\n• Stiff Unilateral com Halter — 3×10-12, descanso 60 s\n• Hip Thrust com Barra — 4×8-12, descanso 90 s\n• Panturrilha Sentado — 3×12-15, descanso 60 s'
/** The same four lines as a suggestion created now shows them: one name changed. */
const PLAIN_LAST_LINES =
  '• Cadeira Abdutora — 3×12-15, descanso 60 s\n• Stiff Unilateral com Halter — 3×10-12, descanso 60 s\n• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s\n• Panturrilha Sentado — 3×12-15, descanso 60 s'
const PLAIN_CHAT_END = `${PLAIN_LAST_LINES}\n\nProgressão: ${PLAIN_PROGRESSION}`

/** How every decision of the second round is recorded: never as the owner's nor the physician's approval. */
const ORCHESTRATOR_DECISION =
  'decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma'

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
  user_id: USER_ID,
  onboarding_completed: true,
  onboarding_completed_at: null,
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
      if (name === 'get_mobile_signup_body_photo_snapshot') {
        expect(params).toEqual({ p_user_id: USER_ID, p_include_open_photos: false })
        return {
          data: {
            version: 1,
            user_id: USER_ID,
            profile_present: true,
            locale: 'pt-BR',
            timezone: 'America/Sao_Paulo',
            generation_token: {
              onboarding_completed: true,
              onboarding_completed_at: null,
              receipt_count: 0,
            },
            poses: [],
            remaining_uploads: 0,
            consent: null,
            estimate: null,
            candidate: null,
            confirmation: null,
          },
          error: null,
        }
      }
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
      RENAMED_TERM,
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

  it('A1 the stored draft of the reported turn carries none of the 14 reported terms the net covers, and the 15th only in parentheses', async () => {
    const { stored } = await propose(GENERATED_JSON)

    // Not vacuous: each of the 15 terms is in the text values of the generator's answer…
    for (const term of [...COVERED_TERMS, RENAMED_TERM]) {
      expect(carriers(GENERATED, term), `generated: ${term}`).not.toEqual([])
    }
    expect(carriers(GENERATED, RENAMED_TERM)).toEqual(['Hip Thrust com Barra'])
    // …and the 7 others are not in the evidence at all (RC TL-2).
    for (const term of TERMS_NOT_IN_THE_EVIDENCE) expect(carriers(GENERATED, term)).toEqual([])

    expect(stored).toHaveLength(1)
    const payload = stored[0]?.p_payload
    for (const term of COVERED_TERMS) {
      expect(carriers(payload, term), `stored: ${term}`).toEqual([])
    }
    // The 15th: the exercise carries its Portuguese name, and the name the
    // owner read is kept after it, in parentheses, in that one text (RC TL-13).
    expect(carriers(payload, RENAMED_TERM)).toEqual([RENAMED_NAME])
    expect((payload as Plan).weekly_schedule[2]?.exercises[2]?.name).toBe(RENAMED_NAME)
    expect(RENAMED_NAME).toHaveLength(39)
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
    // 487 before the scale; " de 10" after the grade of the sentence of the effort.
    expect(payload.notes).toHaveLength(493)
    expect(payload.notes).toContain('Treino até próximo da última repetição bem feita (esforço 8-9 de 10).')
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

    // The names: one is renamed, with the name the owner read in parentheses;
    // "Leg Press" and "Stiff" are exactly as the generator wrote them (RC TL-13).
    expect(payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name))).toEqual([
      'Supino Reto com Barra',
      'Leg Press 45°',
      'Cadeira Abdutora',
      'Stiff Unilateral com Halter',
      'Elevação pélvica com Barra (Hip Thrust)',
      'Panturrilha Sentado',
    ])
    // As generated: the days, the focus, the muscle groups, the equipment and
    // every text the vocabulary has no row for.
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

  it('A3 rpe_target keeps its shape and says its scale: "Esforço alvo 9" reads "Esforço alvo 9 de 10" (RC TL-14)', async () => {
    const { stored } = await propose(GENERATED_JSON)
    const payload = stored[0]?.p_payload as Plan
    const generated = GENERATED.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.rpe_target))
    const grades = payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.rpe_target))
    // The three whole exercises carried "9"; the three known only by their chat line carry none.
    expect(generated).toEqual(['9', '9', undefined, undefined, '9', undefined])
    expect(grades).toEqual(['9 de 10', '9 de 10', undefined, undefined, '9 de 10', undefined])
    // Same shape: still a text, within the field's 40 characters, absent where it was absent.
    for (const grade of grades.filter((entry) => entry !== undefined)) {
      expect(typeof grade).toBe('string')
      expect(String(grade).length).toBeLessThanOrEqual(40)
    }
  })

  it('A4 the chat shows the same plain text as the draft (3-day cut; the whole plan may be cut: RC TL-1)', async () => {
    const { result, stored } = await propose(GENERATED_JSON)
    const suggestion = String(result.sugestao)

    expect(result).toMatchObject({ success: true, draft_id: 'draft-0001', domain: 'training', status: 'ready_for_review' })
    expect(suggestion).toBe(trainingSuggestionText(stored[0]?.p_payload))
    expect(suggestion.endsWith(PLAIN_CHAT_END)).toBe(true)
    expect(suggestion).not.toContain(PLAN_SUGGESTION_TRUNCATED)
    expect(trainingSuggestionText(GENERATED)).toHaveLength(650)
    // 685 in plain words before the rename; the one renamed line has 19 characters more.
    expect(suggestion).toHaveLength(704)
    for (const term of COVERED_TERMS) expect(carriers([suggestion], term), term).toEqual([])
    // RC TL-5: the line of an exercise keeps its notation; the name is the renamed one.
    expect(suggestion).toContain('• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s')
    expect(suggestion).not.toContain('• Hip Thrust com Barra')
    expect('• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s').toHaveLength(65)
    // The effort grade is not part of the chat line: the scale shows in the Plan tab only.
    expect(suggestion).not.toContain(' de 10')
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
        // The grade is the generated one, followed by its scale (the same type; absent stays absent).
        expect(exercise.rpe_target).toBe(
          generated.rpe_target === undefined ? undefined : `${generated.rpe_target} de 10`,
        )
        expect(exercise.execution_steps?.length).toBe(generated.execution_steps?.length)
        expect(exercise.common_mistakes?.length).toBe(generated.common_mistakes?.length)
      })
    })
    // In EVERY text field the digit groups are the generated ones, in the same
    // order, once the " de 10" the net wrote is taken out: the "10" of the
    // scale is the ONLY number the net adds. The generator wrote no " de 10"
    // anywhere, so every one in the stored draft is the net's.
    const generatedFields = textFields({ ...GENERATED, equipment_summary: REPORT.payload.equipment_summary })
    const storedFields = textFields(payload)
    expect(storedFields.map(([path]) => path)).toEqual(generatedFields.map(([path]) => path))
    expect(generatedFields.filter(([, text]) => text.includes(' de 10'))).toEqual([])
    const scaled: string[] = []
    storedFields.forEach(([path, text], index) => {
      const generated = generatedFields[index]?.[1] ?? ''
      expect(digitGroups(text.replaceAll(' de 10', '')), path).toEqual(digitGroups(generated))
      const added = text.split(' de 10').length - 1
      expect(added, path).toBeLessThanOrEqual(1)
      if (added === 1) scaled.push(path)
    })
    // The three grades and the one sentence of the notes that carried "RPE 8-9".
    expect(scaled).toEqual(['notes', '0/0/rpe_target', '1/0/rpe_target', '2/2/rpe_target'])
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
      // notes 10, progression_rule 6, three exercise notes, two steps, one mistake (22);
      // and, since the second round, three effort grades and one exercise name.
      plain_terms_replaced: 26,
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
    // None of the 18 names has a row: they stay as generated (RC TL-13, RC TL-4).
    const names = payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name))
    expect(names).toEqual(
      generated.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.name)),
    )
    expect(names).toContain('Stiff (levantamento romeno)')
    expect(names).toContain('Leg press 45°')
    expect(names).toContain('Pulldown com corda (ou pullover)')
    // The 18 effort grades were "7-8": each one says its scale now, and the chat text did not change.
    const generatedGrades = generated.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.rpe_target))
    expect(generatedGrades).toEqual(Array.from({ length: 18 }, () => '7-8'))
    expect(
      payload.weekly_schedule.flatMap((day) => day.exercises.map((exercise) => exercise.rpe_target)),
    ).toEqual(Array.from({ length: 18 }, () => '7-8 de 10'))
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

    // In plain words it would have 1,996 characters (1,977 before the rename): the last block goes to the review.
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
    expect(text).toContain(PLAIN_LAST_LINES)
    // 1,729 before the rename; the one renamed line has 19 characters more.
    expect(text).toHaveLength(1748)
    // The Plan tab keeps the whole rule, in plain words.
    expect(payload.progression_rule).toBe(PLAIN_PROGRESSION)
    expect(payload.notes).toBe(PLAIN_NOTES)
  })
})

// ── N. A small field over its limit with the phrase the prompt teaches ──────
// Review of 3b65bee, round 2 (LOW, left open then): the Flow prompt teaches
// "até a última repetição bem feita" (32 characters); a model that writes it
// in reps_range or rpe_target beside a range passes the 40 characters of the
// field, the generator's schema refuses the answer and the person gets NO
// suggestion. Made HARMLESS (not impossible: the model may still write it):
// in the Flow branch of the generator, before the validation, the field keeps
// a clean value or the phrase itself, and the generator's whole text opens
// the exercise's note. The legacy path does not have the step.
describe('audit 2026-10-10 Flow workout — a repetitions or effort text over 40 characters with the taught phrase', () => {
  const TAUGHT_PHRASE = 'até a última repetição bem feita'
  const TAUGHT_REPS = '10-12 ou até a última repetição bem feita'
  const TAUGHT_EFFORT = 'esforço 9, perto da última repetição bem feita'
  /** The note of the first exercise of the cut, as the net stores it. */
  const BENCH_PLAIN_NOTE = 'Exercício de vários músculos principal para peitoral. Pegada na largura dos ombros.'

  /** The reported cut with fields of its first exercise (Monday, bench press) written over. */
  const withBench = (over: Partial<Exercise>): Plan => {
    const plan = structuredClone(GENERATED)
    const bench = plan.weekly_schedule[0]?.exercises[0] as Exercise
    expect(bench.name).toBe('Supino Reto com Barra')
    expect(bench.notes).toBe('Composto principal para peitoral. Pegada na largura dos ombros.')
    Object.assign(bench, over)
    return plan
  }
  const benchOf = (stored: Row[]) => (stored[0]?.p_payload as Plan).weekly_schedule[0]?.exercises[0] as Exercise
  const failures = (h: Harness) => events(h, 'training.generation_failed')

  it('the setup is the case: the phrase is the one the Flow prompt teaches, and the texts pass 40 characters', () => {
    expect(TAUGHT_PHRASE).toHaveLength(32)
    expect(trainingSystemPrompt('flow')).toContain(`"${TAUGHT_PHRASE}"`)
    expect(trainingSystemPrompt('legacy')).not.toContain(TAUGHT_PHRASE)
    expect(TAUGHT_REPS).toHaveLength(41)
    expect(TAUGHT_EFFORT).toHaveLength(46)
    expect(BENCH_PLAIN_NOTE).toHaveLength(83)
  })

  it('N1 a repetitions text of 41 characters with the taught phrase is stored, not refused', async () => {
    const { h, result, stored } = await propose(withBench({ reps_range: TAUGHT_REPS }))

    expect(stored).toHaveLength(1)
    expect(stored[0]?.p_status).toBe('ready_for_review')
    expect(result).toMatchObject({ success: true, domain: 'training', status: 'ready_for_review' })
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe('10-12')
    // The generator's own text comes FIRST in the note, then the note it wrote.
    expect(bench.notes).toBe(`${TAUGHT_REPS}. ${BENCH_PLAIN_NOTE}`)
    expect(bench.notes).toHaveLength(126)
    expect(String(result.sugestao)).toContain('• Supino Reto com Barra — 4×10-12, descanso 90 s')
    expect(failures(h)).toEqual([])

    // Every other field is the one of the reported turn (section A).
    const reference = (await propose(GENERATED_JSON)).stored[0]?.p_payload as Plan
    const restored = structuredClone(stored[0]?.p_payload as Plan)
    const restoredBench = restored.weekly_schedule[0]?.exercises[0] as Exercise
    restoredBench.reps_range = '6-12'
    restoredBench.notes = BENCH_PLAIN_NOTE
    expect(restored).toEqual(reference)
  })

  it('N2 the same with the effort: the grade stays in the field and the text opens the note', async () => {
    const { h, stored } = await propose(withBench({ rpe_target: TAUGHT_EFFORT }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    // "esforço 9" stayed in the field; the net takes the label out and writes the scale.
    expect(bench.rpe_target).toBe('9 de 10')
    expect(bench.notes).toBe(`${TAUGHT_EFFORT}. ${BENCH_PLAIN_NOTE}`)
    expect(bench.notes).toHaveLength(131)
    expect(bench.reps_range).toBe('6-12')
    expect(failures(h)).toEqual([])
  })

  it('N3 the phrase first: the field keeps the phrase, and the whole sentence opens the note', async () => {
    const written = 'Até a última repetição bem feita em todas as séries'
    expect(written).toHaveLength(51)
    const { result, stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe('Até a última repetição bem feita')
    expect(bench.notes).toBe(`${written}. ${BENCH_PLAIN_NOTE}`)
    expect(String(result.sugestao)).toContain('• Supino Reto com Barra — 4×Até a última repetição bem feita, descanso 90 s')
  })

  it('N4 without the taught phrase a text over 40 characters still refuses the suggestion (lock: RC TL-21)', async () => {
    const written = '8 a 12 repetições em cada uma das quatro séries'
    expect(written).toHaveLength(47)
    const { h, result, stored } = await propose(withBench({ reps_range: written }))

    expect(result).toMatchObject({ success: false })
    expect(stored).toEqual([])
    expect(failures(h)).toHaveLength(1)
    expect(failures(h)[0]?.properties).toMatchObject({ reason: 'zod_validation_failed' })
    expect(events(h, 'training.plan_proposed')).toEqual([])
  })

  it('N5 legacy: the same answer through gera_treino is refused as before, with the legacy request (lock)', async () => {
    const h = harness({ generator: JSON.stringify(withBench({ reps_range: TAUGHT_REPS })) })
    const ctx = { supabase: h.deps.supabase, userId: USER_ID, userWpp: '', llm: h.deps.llm } as unknown as ToolContext
    const result = (await geraTreino.execute(
      geraTreino.parameters.parse(REPORT.tool_arguments_reconstructed) as never,
      ctx,
    )) as Row

    expect(result).toEqual({ success: false, error: 'Falha ao gerar plano de treino. Tente novamente.' })
    expect(h.rpcs.filter((entry) => entry.name === 'save_training_plan_atomic')).toEqual([])
    expect(storedDrafts(h)).toEqual([])
    expect(failures(h)).toHaveLength(1)
    expect(failures(h)[0]?.properties).toMatchObject({ reason: 'zod_validation_failed' })
    // The legacy request: prompt, keys and limit as released (B2).
    expect(h.generatorCalls).toHaveLength(1)
    const call = h.generatorCalls[0] as GeneratorCall
    expect(createHash('sha256').update(call.systemPrompt).digest('hex')).toBe(LEGACY_TRAINING_PROMPT_SHA256)
    expect(call.keys).toEqual(['maxTokens', 'messages', 'metadata', 'model', 'systemPrompt', 'temperature'])
    expect(call.maxTokens).toBe(4500)
  })

  it('N6 at exactly 40 characters nothing moves: the field is the generator\'s and the note is intact (lock)', async () => {
    const written = '8-12 ou até a última repetição bem feita'
    expect(written).toHaveLength(40)
    const { stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe(written)
    expect(bench.notes).toBe(BENCH_PLAIN_NOTE)
  })

  it('N7 the moved text comes first and survives the 300-character cut of the note (RC TL-21)', async () => {
    const generatedNote = `${'Desça devagar e suba sem pressa. '.repeat(8)}Mantenha o ritmo até o fim`
    expect(generatedNote).toHaveLength(290)
    const { stored } = await propose(withBench({ reps_range: TAUGHT_REPS, notes: generatedNote }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe('10-12')
    // Written here by hand: the moved phrase whole, and the END of the generator's note cut with "…".
    const expected = `${TAUGHT_REPS}. ${'Desça devagar e suba sem pressa. '.repeat(7)}Desça devagar e suba sem…`
    expect(expected).toHaveLength(299)
    expect(bench.notes).toBe(expected)
  })

  it('N8 a prefix that is not a clean value does not stay in the field', async () => {
    const written = '3 séries de até a última repetição bem feita'
    expect(written).toHaveLength(44)
    const { result, stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe(TAUGHT_PHRASE)
    expect(bench.notes).toBe(`${written}. ${BENCH_PLAIN_NOTE}`)
    // The chat line never reads "4×3 séries de".
    const line = String(result.sugestao).split('\n').find((entry) => entry.startsWith('• Supino Reto com Barra'))
    expect(line).toBe('• Supino Reto com Barra — 4×até a última repetição bem feita, descanso 90 s')
  })

  it('N9 a prefix over 40 characters: the field keeps the phrase, and nothing is refused', async () => {
    const written = 'Na primeira semana 10-12, e nas outras semanas até a última repetição bem feita'
    expect(written).toHaveLength(79)
    expect(written.slice(0, written.indexOf(' até a última'))).toHaveLength(46)
    const { stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe(TAUGHT_PHRASE)
    expect(bench.notes).toBe(`${written}. ${BENCH_PLAIN_NOTE}`)
    expect(bench.notes).toHaveLength(164)
  })

  it.each([
    '10-12 OU ATÉ A ÚLTIMA REPETIÇÃO BEM FEITA',
    '10-12 ou ate a ultima repeticao bem feita',
    // Runs of spaces count as one: the text is read, and moved, with one space in each place.
    '10-12  ou  até  a  última  repetição  bem  feita',
  ])('N10 capitals, no accents, repeated spaces: %j keeps "10-12" in the field', async (written) => {
    expect(written.length).toBeGreaterThan(40)
    const { stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe('10-12')
    // The generator's text opens the note as it wrote it (one space where it wrote several).
    expect(bench.notes).toBe(`${written.replace(/ {2,}/g, ' ')}. ${BENCH_PLAIN_NOTE}`)
  })

  it('N11 both fields over 40 characters in the same exercise: repetitions first, then effort, then the note', async () => {
    const { stored } = await propose(withBench({ reps_range: TAUGHT_REPS, rpe_target: TAUGHT_EFFORT }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench.reps_range).toBe('10-12')
    expect(bench.rpe_target).toBe('9 de 10')
    expect(bench.notes).toBe(`${TAUGHT_REPS}. ${TAUGHT_EFFORT}. ${BENCH_PLAIN_NOTE}`)
    expect(bench.notes).toHaveLength(174)
  })

  it.each([
    // written, field, what stays in the field (after the net)
    ['10-12 repetições (até a última repetição bem feita)', 'reps_range', '10-12 repetições'],
    ['12 - sempre até a última repetição bem feita', 'reps_range', TAUGHT_PHRASE],
    ['8 a 12, parando antes da última repetição bem feita', 'reps_range', 'antes da última repetição bem feita'],
    ['9 - até a última repetição bem feita, sem perder a postura', 'rpe_target', '9 de 10'],
    // The model wrote the scale itself: the grade with its scale is a clean value too.
    ['9 de 10, até a última repetição bem feita', 'rpe_target', '9 de 10'],
    ['8-9/10 ou até a última repetição bem feita', 'rpe_target', '8-9 de 10'],
    ['Fique sempre bem próximo da última repetição bem feita', 'rpe_target', 'próximo da última repetição bem feita'],
    ['Alto: pare só na última repetição bem feita de cada série', 'rpe_target', 'última repetição bem feita'],
  ] as const)('N12 %j in %s: the field keeps %j', async (written, field, kept) => {
    expect(written.length).toBeGreaterThan(40)
    const { stored } = await propose(withBench({ [field]: written }))

    expect(stored).toHaveLength(1)
    const bench = benchOf(stored)
    expect(bench[field]).toBe(kept)
    expect(String(bench[field]).length).toBeLessThanOrEqual(40)
    // The longest value the step can write is the longest introduction and the phrase.
    expect('próximo da última repetição bem feita').toHaveLength(37)
    expect(bench.notes?.startsWith(`${written}. `)).toBe(true)
  })

  it('N13 an exercise that had no note gains one with the moved text, and nothing else changes in it', async () => {
    const plan = structuredClone(GENERATED)
    const abductor = plan.weekly_schedule[2]?.exercises[0] as Exercise
    expect(abductor.name).toBe('Cadeira Abdutora')
    expect(Object.keys(abductor).sort()).toEqual(['muscle_group', 'name', 'reps_range', 'rest_seconds', 'sets'])
    abductor.reps_range = '12-15, a última série até a última repetição bem feita'
    const { stored } = await propose(plan)

    expect(stored).toHaveLength(1)
    const storedAbductor = (stored[0]?.p_payload as Plan).weekly_schedule[2]?.exercises[0] as Exercise
    expect(storedAbductor).toEqual({
      name: 'Cadeira Abdutora',
      muscle_group: '',
      sets: 3,
      reps_range: TAUGHT_PHRASE,
      rest_seconds: 60,
      notes: '12-15, a última série até a última repetição bem feita.',
    })
  })

  // Review round 1 of the second round: "bem-feita", with a hyphen, is a
  // spelling a model writes too; the step read only the one with a space and
  // the whole suggestion was refused. The first string is the reviewer's.
  it.each([
    ['10-12, até a última repetição bem-feita possível', 48, '10-12'],
    ['10-12 ou até a última repetição bem-feita', 41, '10-12'],
    // The non-breaking hyphen is a hyphen too.
    ['10-12 ou até a última repetição bem\u2011feita', 41, '10-12'],
    ['Sempre até a última repetição bem-feita de cada série', 53, 'até a última repetição bem-feita'],
  ] as const)('N14 the phrase written with a hyphen: %j (%i characters) is stored, not refused', async (written, length, kept) => {
    expect(written).toHaveLength(length)
    const { h, result, stored } = await propose(withBench({ reps_range: written }))

    expect(stored).toHaveLength(1)
    expect(stored[0]?.p_status).toBe('ready_for_review')
    expect(result).toMatchObject({ success: true, domain: 'training', status: 'ready_for_review' })
    const bench = benchOf(stored)
    // The field keeps the clean value, or the phrase as the model wrote it — hyphen included.
    expect(bench.reps_range).toBe(kept)
    expect(String(bench.reps_range).length).toBeLessThanOrEqual(40)
    expect(bench.notes).toBe(`${written}. ${BENCH_PLAIN_NOTE}`)
    expect(failures(h)).toEqual([])
  })

  it('N14 legacy: the hyphenated text through gera_treino is refused as before (lock)', async () => {
    const h = harness({
      generator: JSON.stringify(withBench({ reps_range: '10-12, até a última repetição bem-feita possível' })),
    })
    const ctx = { supabase: h.deps.supabase, userId: USER_ID, userWpp: '', llm: h.deps.llm } as unknown as ToolContext
    const result = (await geraTreino.execute(
      geraTreino.parameters.parse(REPORT.tool_arguments_reconstructed) as never,
      ctx,
    )) as Row

    expect(result).toEqual({ success: false, error: 'Falha ao gerar plano de treino. Tente novamente.' })
    expect(h.rpcs.filter((entry) => entry.name === 'save_training_plan_atomic')).toEqual([])
    expect(failures(h)).toHaveLength(1)
    expect(failures(h)[0]?.properties).toMatchObject({ reason: 'zod_validation_failed' })
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
    // 16 with 3b65bee; 22 since the second round of 2026-10-10 (TL-17 to TL-22).
    expect(fromHeader).toHaveLength(22)
    expect(fromHeader.map((entry) => entry.match(/^> RC TL-\d+/)?.[0])).toEqual(
      Array.from({ length: 22 }, (_, index) => `> RC TL-${index + 1}`),
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
    expect(waiting).toContain("`{ effortOutOfTen: true, renames: ['hip_thrust', 'military_press'] }`")
    expect(waiting).not.toContain('effortOutOfTen: false')
    // Nothing is dated: no owner's yes was given. The three lines are still blank.
    expect(waiting.match(/sim do\s+dono em: ____/g)).toHaveLength(3)
    // Who turned each one on, written once for D1 and once for D2.
    expect(waiting.replace(/\s+/g, ' ').split(ORCHESTRATOR_DECISION).length - 1).toBeGreaterThanOrEqual(2)

    const flat = section.replace(/\s+/g, ' ')
    expect(flat).toContain(
      `Lista fechada de vizinhas em inglês (regra 4): ${FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS.join(', ')}.`,
    )
    expect(flat).toContain(
      'Desde esta mudança o rascunho de treino do Flow é gravado com as grafias desta tabela trocadas na criação; a frase de RC FN-3 (o rascunho é gravado como o gerador escreveu) continua valendo para todo o resto, e RC FN-3 segue aberta.',
    )
  })

  it('B4 nothing says the owner approved: each decision is written as the orchestrator\'s, and the owner\'s yes is blank', () => {
    const doc = readFileSync(
      fileURLToPath(new URL('../../../../docs/mobile/api-v1.md', import.meta.url)),
      'utf8',
    )
    const section = doc.slice(
      doc.indexOf('### O que espera o dono'),
      doc.indexOf('### O que é garantido'),
    )
    expect(section.length).toBeGreaterThan(500)
    // The module, with its comments read as running text.
    const source = readFileSync(
      fileURLToPath(new URL('../flow-plain-training-language.ts', import.meta.url)),
      'utf8',
    )
      .replace(/\n\s*(?:\*|\/\/)\s?/g, ' ')
      .replace(/\s+/g, ' ')
    const flatSection = section.replace(/\s+/g, ' ')

    // What 3b65bee wrote while the switches waited, and any wording of an approval.
    const approval = new RegExp(
      [
        'owner ' + 'approved',
        'scale ' + 'approved',
        "needs the owner's " + 'yes',
        'the owner ' + 'approves',
        'approved by the ' + '(?:owner|physician)',
        'aprovad[oa]s? pel[oa] ' + '(?:dono|médico)',
        'o dono ' + 'aprovou',
        'o médico ' + 'aprovou',
      ].join('|'),
      'i',
    )
    expect(source).not.toMatch(approval)
    expect(flatSection).not.toMatch(approval)
    // A dated yes would be an approval: none is written.
    expect(flatSection).not.toMatch(/sim do dono em: \d/)
    expect(source).toContain(ORCHESTRATOR_DECISION)
    expect(flatSection).toContain(ORCHESTRATOR_DECISION)
    // And the two lines of the pendencies that tell the decisions say it too.
    expect(line(13)).toContain(ORCHESTRATOR_DECISION)
    expect(line(14)).toContain(ORCHESTRATOR_DECISION)
  })

  it('B4 RC TL-13: two names are renamed with the original in parentheses; the others stay as generated', () => {
    for (const name of ['Hip Thrust com Barra', 'Stiff Unilateral com Halter', 'Leg Press 45°', 'Military press']) {
      expect(line(13)).toContain(`"${name}"`)
    }
    // Covered: the exact outputs the line states.
    expect(line(13)).toContain('"Hip Thrust com Barra" vira "Elevação pélvica com Barra (Hip Thrust)"')
    expect(projectFlowPlainTrainingText('Hip Thrust com Barra', 'name')).toEqual({
      text: 'Elevação pélvica com Barra (Hip Thrust)',
      replaced: 1,
    })
    expect(projectFlowPlainTrainingText('Military press', 'name')).toEqual({
      text: 'Desenvolvimento militar (Military press)',
      replaced: 1,
    })
    // Not covered, each one as the line says.
    for (const name of ['Stiff Unilateral com Halter', 'Leg Press 45°']) {
      expect(projectFlowPlainTrainingText(name, 'name')).toEqual({ text: name, replaced: 0 })
    }
    for (const [written, field] of [
      ['Glúteos (hip thrust)', 'name'],
      ['Hip Thrust (elevação pélvica)', 'name'],
      ['banco para hip thrust', 'equipment_summary'],
    ] as const) {
      expect(line(13)).toContain(`"${written}"`)
      expect(projectFlowPlainTrainingText(written, field), written).toEqual({ text: written, replaced: 0 })
    }
    // The other English words of the same name stay.
    expect(line(13)).toContain('"Single Leg Hip Thrust" vira "Single Leg elevação pélvica (Hip Thrust)"')
    expect(projectFlowPlainTrainingText('Single Leg Hip Thrust', 'name').text).toBe(
      'Single Leg elevação pélvica (Hip Thrust)',
    )
    // The second mention in the same text: the Portuguese name alone.
    expect(
      projectFlowPlainTrainingText('Faça o Hip Thrust devagar. No hip thrust, suba o quadril até o fim.', 'notes').text,
    ).toBe('Faça a elevação pélvica (Hip Thrust) devagar. Na elevação pélvica, suba o quadril até o fim.')
  })

  it('B4 RC TL-14: a grade from 1 to 10 says its scale; what the line lists stays without it', () => {
    expect(line(14)).toContain('"Esforço alvo 9"')
    expect(line(14)).toContain('"9" vira "9 de 10"')
    expect(projectFlowPlainTrainingText('9', 'rpe_target')).toEqual({ text: '9 de 10', replaced: 1 })
    expect(line(14)).toContain('"RPE 8-9" vira "esforço 8-9 de 10"')
    expect(projectFlowPlainTrainingText('Treine com RPE 8-9.', 'notes').text).toBe('Treine com esforço 8-9 de 10.')
    // Not covered: outside 1 to 10, in words, after the word "esforço" in running text.
    for (const [written, field] of [
      ['15', 'rpe_target'],
      ['moderado', 'rpe_target'],
      ['Treine com esforço 8-9.', 'notes'],
    ] as const) {
      expect(line(14)).toContain(`"${written.replace('Treine com ', '').replace('.', '')}"`)
      expect(projectFlowPlainTrainingText(written, field), written).toEqual({ text: written, replaced: 0 })
    }
    // Not covered: the grade goes on after the number, or a sign outside the closed list follows it.
    for (const [written, received] of [
      ['RPE 8/9', 'Esforço 8/9'],
      ['RPE 8+', 'Esforço 8+'],
      ['RPE 8 ou 9', 'Esforço 8 ou 9'],
      ['RPE 8 - RIR 2', 'Esforço 8 - RIR 2'],
      // …or the sentence already says the scale after the grade.
      ['RPE 8 (de 10)', 'Esforço 8 (de 10)'],
      ['RPE 8 numa escala de 1 a 10', 'Esforço 8 numa escala de 1 a 10'],
    ] as const) {
      expect(line(14)).toContain(`"${written}"`)
      expect(projectFlowPlainTrainingText(written, 'notes').text).toBe(received)
    }
    // Review round 1 of the second round. Not covered: "para" and a number;
    // a range written with a space beside its dash, or with " a ", and then a
    // word — the second number may be another thing, and a real range written
    // that way loses the scale too.
    for (const [written, received] of [
      ['RPE 8 para 9', 'Esforço 8 para 9'],
      ['RPE 8 - 10 repetições', 'Esforço 8 - 10 repetições'],
      ['RPE 8 a 10 repetições por série', 'Esforço 8 a 10 repetições por série'],
      ['RPE 8 a 9 nas últimas séries', 'Esforço 8 a 9 nas últimas séries'],
    ] as const) {
      expect(line(14)).toContain(`"${written}"`)
      expect(projectFlowPlainTrainingText(written, 'notes'), written).toEqual({ text: received, replaced: 1 })
    }
    // Not covered: a grade followed by other text in rpe_target itself, without the acronym.
    expect(line(14)).toContain('sem a sigla ("8 (pesado)")')
    expect(projectFlowPlainTrainingText('8 (pesado)', 'rpe_target')).toEqual({ text: '8 (pesado)', replaced: 0 })
    // Covered: the grade alone with its full stop.
    expect(line(14)).toContain('"9." vira "9 de 10."')
    expect(projectFlowPlainTrainingText('9.', 'rpe_target')).toEqual({ text: '9 de 10.', replaced: 1 })
    // Stated limit: a spaced range and then the end or punctuation is read as a range.
    expect(line(14)).toContain('"RPE 8 - 9." vira "esforço 8 - 9 de 10."')
    expect(projectFlowPlainTrainingText('Treine com RPE 8 - 9.', 'notes').text).toBe('Treine com esforço 8 - 9 de 10.')
  })

  it('B4 RC TL-5: the line of the renamed exercise in the chat is the one the pendency quotes', () => {
    expect(line(5)).toContain('"• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s"')
    expect(line(5)).toContain('"• Hip Thrust com Barra — 4×8-12, descanso 90 s"')
    expect(PLAIN_LAST_LINES.split('\n')[2]).toBe('• Elevação pélvica com Barra (Hip Thrust) — 4×8-12, descanso 90 s')
    expect(SCREEN_LAST_LINES.split('\n')[2]).toBe('• Hip Thrust com Barra — 4×8-12, descanso 90 s')
  })

  it('B4 RC TL-17: the participle stays; the two stated limits are pinned', () => {
    const reported = 'Treino ABC, composto principalmente por exercícios básicos.'
    expect(line(17)).toContain(`"${reported}"`)
    expect(projectFlowPlainTrainingText(reported, 'notes')).toEqual({ text: reported, replaced: 0 })
    // Limit 1: another word between the participle and the preposition — still replaced.
    const stillReplaced = 'Treino ABC, composto na prática por exercícios básicos.'
    expect(line(17)).toContain(`"${stillReplaced}", que continua trocada`)
    expect(projectFlowPlainTrainingText(stillReplaced, 'notes').text).toBe(
      'Treino ABC, exercício de vários músculos na prática por exercícios básicos.',
    )
    // Limit 2: the noun followed by an adverb of the list and "de" — stays as generated.
    expect(line(17)).toContain('"Compostos sempre de manhã." fica')
    expect(projectFlowPlainTrainingText('Compostos sempre de manhã.', 'notes')).toEqual({
      text: 'Compostos sempre de manhã.',
      replaced: 0,
    })
    for (const adverb of ['apenas', 'só', 'sobretudo', 'quase', 'também', 'ainda', 'sempre', 'tanto', 'em grande parte', 'em sua maioria', 'na maior parte']) {
      expect(line(17)).toContain(`"${adverb}"`)
    }
  })

  it('B4 RC TL-18: "falha" alone in the two small fields; the stated limits are pinned', () => {
    for (const field of ['reps_range', 'rpe_target'] as const) {
      expect(projectFlowPlainTrainingText('falha', field).text).toBe('até a última repetição bem feita')
      expect(projectFlowPlainTrainingText('Falha técnica', field).text).toBe('Até a última repetição bem feita')
      for (const kept of ['sem falha', 'pré-falha', 'Falha total']) {
        expect(line(18)).toContain(`"${kept}"`)
        expect(projectFlowPlainTrainingText(kept, field), kept).toEqual({ text: kept, replaced: 0 })
      }
    }
    expect(line(18)).toContain('"10-12 ou falha" teria 41')
    // The range of two digits and two digits, the most likely value of the
    // field: each of the three strings the line names stays as generated.
    for (const written of ['10-12 ou falha', '12-15 ou falha', '10-12 ou até a falha']) {
      expect(line(18)).toContain(`"${written}"`)
      expect(projectFlowPlainTrainingText(written, 'reps_range').text, written).toHaveLength(41)
      const kept = projectFlowPlainTrainingDraft({
        weekly_schedule: [
          { day: 'Segunda', focus: 'Peito', duration_min: 60, exercises: [{ name: 'Supino', reps_range: written }] },
        ],
      })
      expect((kept.payload as Plan).weekly_schedule[0]?.exercises[0]?.reps_range, written).toBe(written)
      expect(kept.fieldsKeptAsGenerated, written).toBe(1)
    }
  })

  it('B4 RC TL-19: the label leaves rpe_target before a grade or one word; each stated limit is pinned', () => {
    expect(projectFlowPlainTrainingText('RPE alto', 'rpe_target').text).toBe('alto')
    expect(projectFlowPlainTrainingText('Esforço alto', 'rpe_target').text).toBe('alto')
    for (const [written, received] of [
      ['RPE', 'Esforço'],
      ['Mantenha RPE alto', 'Mantenha esforço alto'],
    ] as const) {
      expect(line(19)).toContain(`"${written}" vira "${received}"`)
      expect(projectFlowPlainTrainingText(written, 'rpe_target').text).toBe(received)
    }
    for (const kept of ['Esforço percebido 8', 'Esforço percebido', 'PSE alta']) {
      expect(line(19)).toContain(`"${kept}" fica`)
      expect(projectFlowPlainTrainingText(kept, 'rpe_target'), kept).toEqual({ text: kept, replaced: 0 })
    }
  })

  it('B4 RC TL-20: the measured kind of text is the one the line names', () => {
    expect(line(20)).toContain('sequência longa de pontos ou de letras sem espaço')
    // Not a budget: only that such a text is read, and comes back as written.
    const dots = `Faça ${'.'.repeat(400)}`
    expect(projectFlowPlainTrainingText(dots, 'notes')).toEqual({ text: dots, replaced: 0 })
    const letters = `Faça ${'a'.repeat(400)}`
    expect(projectFlowPlainTrainingText(letters, 'notes')).toEqual({ text: letters, replaced: 0 })
  })

  it('B4 RC TL-21: the two limits of the small field over 40 characters are the ones section N pins', () => {
    // N4 (no phrase: refused) and N7 (the note cut at 300, with the moved text first).
    expect(line(21)).toContain('texto sem a frase "última repetição bem feita", que continua recusando a sugestão inteira')
    expect(line(21)).toContain('faz a observação passar de 300 caracteres: ela é cortada no fim com "…"')
    // N14: the spelling with a hyphen is the phrase too.
    expect(line(21)).toContain('A frase escrita com hífen ("até a última repetição bem-feita") conta como a frase')
  })

  it('B4 RC TL-22: when the scale or the parenthesis does not fit it is left out; the example of the line is exact', () => {
    expect(line(22)).toContain('rpe_target "RPE 9, até a falha" teria 41 caracteres com a escala e fica "9, até a última repetição bem feita"')
    expect('9 de 10, até a última repetição bem feita').toHaveLength(41)
    const result = projectFlowPlainTrainingDraft({
      weekly_schedule: [
        { day: 'Segunda', focus: 'Peito', duration_min: 60, exercises: [{ name: 'Supino', rpe_target: 'RPE 9, até a falha' }] },
      ],
    })
    expect((result.payload as Plan).weekly_schedule[0]?.exercises[0]?.rpe_target).toBe(
      '9, até a última repetição bem feita',
    )
    // The telemetry does not count the omission: nothing was kept as generated.
    expect(result).toMatchObject({ termsReplaced: 2, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
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
      ['Treine a PSE 8', 'Treine o esforço 8 de 10'],
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
