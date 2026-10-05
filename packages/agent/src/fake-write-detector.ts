/**
 * Detector de "escrita fantasma": o LLM AFIRMA ter registrado/corrigido uma
 * refeição (ou treino) e exibe um card, mas NÃO chamou a tool de gravação no
 * turno — então nada foi salvo no banco.
 *
 * Casos reais:
 *  - Registro-fake (Luciana 2026-05-20): "Almoço registrado. … 521 kcal" sem
 *    chamar registra_refeicao → refeição fantasma, snapshot com déficit fake.
 *  - Correção-fake (Roberto 2026-05-21): "Corrigido. Feijão 180g…" sem chamar
 *    registra_refeicao(replace=true) → banco fica com a refeição velha; o card
 *    (canônico, vindo do banco) some com a correção.
 *
 * O card NUNCA é alucinado (o FIX C no pipeline reescreve o card com dados
 * frescos do banco). A falha é a montante: a tool não roda. Este detector é a
 * base do guard que força a tool a ser chamada.
 */

// "salv*" incluído (Paulo 2026-05-22): o agente usa MUITO "Café/Almoço/Jantar
// salvo" — era o buraco que mais perdia refeição (guard não pegava sem a tool).
const REGISTRATION_CLAIM =
  /\b(registr(?:ei|ado|ada|ados|adas)|anot(?:ei|ado|ada)|salv(?:o|a|os|as|ei|amos)|adicion(?:ei|ado|ada)\s+ao)\b/i

// Sem \b no FIM: "substituí" termina em vogal acentuada (não-ASCII), e \b
// ASCII falha entre "í" e espaço (ambos não-\w). Mesmo gotcha do correction-detector.
// Card de refeição itemizado (Roberto 2026-05-22 14:02): o agente às vezes mostra
// "**Almoço:** • item… **Total refeição: X**" SEM dizer "registrado/salvo" — é uma
// afirmação IMPLÍCITA de registro. "Total refeição" não aparece no card de balanço
// (que usa 🔥 Consumido), só no card de registro de refeição.
const MEAL_CARD = /total\s+(?:da\s+)?refei[çc][ãa]o/i

const CORRECTION_CLAIM =
  /\b(?:corrig(?:i|ido|ida|idos|idas)|corre[çc][ãa]o|substitu(?:í|i|ído|ido|ída|ida)|re-?registr(?:ei|ado|ada)|troquei|atualiz(?:ei|ado|ada))/i

// Skip explícito (Roberto 2026-06-16): paciente confirma que NÃO comeu uma
// refeição. Tool correta é `marca_refeicao_pulada`, NÃO `registra_refeicao`.
// Sem este detector dedicado, "Pulei o almoço, anotado." cai na regex
// REGISTRATION_CLAIM via "anotado" → retry força registra_refeicao →
// LLM inventa refeição vazia ou refaz uma anterior. Bug caso Roberto
// 2026-06-15 23:06 BRT: "Pulei" → Haiku "Anotado: jantar pulado" → fake_write
// detectou registration → Haiku no retry copiou items do LANCHE anterior
// e propôs registrar como pending fantasma.
const SKIP_CLAIM =
  /\b(?:pul(?:ei|ado|ada)|n[ãa]o\s+com(?:i|ia)|n[ãa]o\s+(?:almoc(?:ei|ava)|jantei|cafei|lanchei|ceei)|fiquei\s+sem\s+(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)|passei\s+direto|estou\s+em\s+jejum|t[ôo]\s+em\s+jejum|sem\s+(?:almo[çc]ar|jantar|caf[ée])\s+hoje)\b/i

// ABANDONO total — paciente NÃO está pulando UMA refeição, está reportando
// o dia inteiro sem comer. Não disparar skip-fake-write (caso clínico, não
// caso de tool). Daily-closer trata via incomplete_no_response.
const ABANDONMENT_CLAIM =
  /\bn[ãa]o\s+com(?:i|ia)\s+nada\s+(?:hoje|o\s+dia)|n[ãa]o\s+com(?:i|ia)\s+o\s+dia\s+(?:inteiro|todo)|jejum\s+(?:total|do\s+dia)|nada\s+(?:hoje|o\s+dia\s+inteiro)\b/i

// CONTEXTOS NEGATIVOS — paciente disse algo que CASA SKIP_CLAIM mas o
// contexto é claramente social/clínico, não skip de refeição. Bloqueia
// false positives (review CRITICAL 2026-06-16):
//  - "passei direto pra cama / pra casa / pro quarto"
//  - "passei direto pelo restaurante e comi em casa"
//  - "estou em jejum intermitente até 12h"
//  - "não comi banana" (negação de ITEM específico, não da refeição)
const SKIP_NEGATIVE_CONTEXT =
  /\bpassei\s+direto\s+(?:pra|para|pro|para\s+o|pelo|pelo[s]?|por|em)\s+\w+|jejum\s+intermitente|j(?:i|í)\s+intermitente|n[ãa]o\s+com(?:i|ia)\s+(?:o\s+|a\s+|um[a]?\s+)?[a-zà-ú]+\s*(?:hoje|agora|ontem)?\s*(?:,|\.|$)/i

// SKIP ACKNOWLEDGMENT no CONTENT do LLM — sinaliza que o LLM "anotou" o
// skip mas pode não ter chamado a tool. Combina com registration claim
// (anotado/salvo/registrado) — qualquer um basta.
const SKIP_ACK_CLAIM =
  /\b(?:pul(?:ado|ada|ados|adas)|sem\s+(?:registro|comer|refei[çc][ãa]o)|fica\s+(?:sem|em\s+branco)\s+(?:o\s+)?(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)|marquei?\s+(?:o\s+)?(?:caf[ée]|almo[çc]o|lanche|jantar|ceia)\s+(?:como\s+)?pulad)/i

// Extrai meal_type literal do texto do paciente. Ordem importa pouco
// (regexes independentes), mas mantemos café→almoço→lanche→jantar→ceia
// pra estabilidade.
// BOUNDARY PT-BR: `\b` do JS não trata 'ã/é/ç' como word chars — então
// "Café da manhã" tem `\b` ANTES de 'ã' (sem match no final). Usamos
// boundary custom: começo/fim de string OU char não-alfa-PT-BR.
const MEAL_KEYWORDS: Array<
  [RegExp, 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia']
> = [
  [/(?:^|[^a-zà-úãõçâêôîû])(?:caf[ée](?:\s+da\s+manh[ãa])?)(?=$|[^a-zà-úãõçâêôîû])/i, 'cafe'],
  [/(?:^|[^a-zà-úãõçâêôîû])almo[çc](?:o|ar|ei)(?=$|[^a-zà-úãõçâêôîû])/i, 'almoco'],
  [/(?:^|[^a-zà-úãõçâêôîû])lanch(?:e|ei|ar)(?=$|[^a-zà-úãõçâêôîû])/i, 'lanche'],
  [/(?:^|[^a-zà-úãõçâêôîû])jant(?:ar|ei|ou)(?=$|[^a-zà-úãõçâêôîû])/i, 'jantar'],
  [/(?:^|[^a-zà-úãõçâêôîû])ceia(?=$|[^a-zà-úãõçâêôîû])/i, 'ceia'],
]

/**
 * Infere meal_type pra skip a partir do texto do paciente. Se o paciente
 * mencionou explicitamente ("pulei o almoço"), usa isso; senão usa o hint
 * (geralmente o gap_reminder mais recente ou inferência por hora local).
 */
export function inferMealFromSkipText(
  text: string,
  hint?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia',
): 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | null {
  for (const [re, meal] of MEAL_KEYWORDS) {
    if (re.test(text)) return meal
  }
  return hint ?? null
}

export interface FakeWriteInput {
  /** Texto final que o LLM produziu pro paciente. */
  content: string
  /** Texto do paciente (último input). Necessário pra detectar skip claim.
   *  Quando ausente, o branch de skip nunca dispara (zero regressão). */
  patientText?: string
  /** registra_refeicao OU registra_treino foi chamada com sucesso no turno. */
  registrationToolCalled: boolean
  /** gera_dieta OU gera_treino foi chamada com sucesso no turno. */
  prescriptionToolCalled?: boolean
  /** marca_refeicao_pulada foi chamada com sucesso no turno. */
  skipToolCalled?: boolean
  /** define_protocolo OU define_meta_peso gravou (ou recusou pelo piso) no
   *  turno. A resposta só fica fora da regra genérica "verbo + kcal/emoji"
   *  quando toda afirmação de registro/correção que o detector reconhece nela
   *  está ligada ao nome da meta — os passos estão em `outsideGoalSentences`.
   *  Um verbo que sobre dispara, como no commit pai 279ba09. O que ainda passa
   *  em silêncio está nas entradas "RC R4" de docs/CALCULO-MPP.md §8c. As
   *  outras regras (pulei, cardápio/treino inventado, proposta imitada, bullets
   *  com kcal, card "Total refeição") não olham esta flag. Ausente = false
   *  (zero regressão). */
  goalToolCalled?: boolean
  /** Tudo o que o paciente mandou no turno e o pipeline tem como texto: o que
   *  ele digitou, a transcrição dos áudios e a análise automática das fotos
   *  (uma foto de prato entra como "[refeição]"). Quando esse texto tem uma
   *  palavra de refeição ou treino (`MEAL_OR_WORKOUT_WORD`), a isenção de
   *  `goalToolCalled` não vale: a resposta é lida inteira, como no commit pai
   *  279ba09. Só pode fazer o guard disparar MAIS. Ausente = a isenção é
   *  decidida só pela resposta (zero regressão). */
  patientTurnText?: string
  /** Fallback de meal_type quando texto do paciente não cita (vem do gap
   *  reminder do dia ou inferência por hora local — pipeline preenche). */
  mealTypeHint?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'
}

export interface FakeWriteResult {
  isFake: boolean
  kind: 'registration' | 'correction' | 'diet_fake' | 'training_fake' | 'skip' | null
  /** Quando kind='skip', meal_type sugerido pro retry msg. Pode ser null
   *  quando o paciente disse "pulei" sem especificar e não há hint. */
  inferredMealType?: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | null
}

// Card de DIETA inventado (Sprint 4.1 review 2026-06-12): LLM apresenta
// "Café da manhã: ... Almoço: ... Lista de compras: ..." sem chamar
// `gera_dieta`. Paciente vai pra cozinha seguir uma dieta que ninguém
// salvou e cujos macros não foram validados. Critério: ≥2 "headers de
// refeição" (Café/Almoço/Lanche/Jantar) seguido de itens E uma seção
// "Lista de compras" no mesmo turno.
const DIET_REFEICAO_HEADER =
  /\b(?:caf[ée]\s+da\s+manh[ãa]|almo[çc]o|lanche\s+(?:da\s+)?(?:manh[ãa]|tarde)|jantar|ceia)\s*:/gi
const DIET_SHOPPING =
  /\b(?:lista\s+de\s+compras|compras\s+da\s+semana|mercado|hortifruti)\s*[:\n]/i
const DIET_TOTAL =
  /\b(?:total\s+(?:di[áa]rio|do\s+dia)|kcal\s+totais|prote[ií]na\s+total)\b/i

// Plano de TREINO inventado: LLM apresenta "Treino A: ... Treino B: ..."
// ou "Segunda: ... Quarta: ..." com exercícios+séries+reps sem chamar
// `gera_treino`. Paciente segue um plano não salvo, cron diário nunca
// dispara, e regenerar bloqueia 24h pelo rate-limit.
const TRAINING_DAY_HEADER =
  /\b(?:treino\s+[ABCabc]|segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo|dia\s+\d)\s*:/gi
const TRAINING_EXERCISE_LINE =
  /(?:^|\n)\s*[•\-*]?\s*[^\n]{4,40}\s+\d+\s*[x×]\s*\d+/g

// Assinatura de TREINO (Paulo 2026-05-28): bug real do detector que só pegava
// REFEIÇÃO. Caso: "Registrei as duas caminhadas de 60 minutos cada..." sem
// chamar registra_treino. Texto tinha "registrei" + "minutos" + "caminhadas"
// mas zero kcal/🔥/💪/📊 → guard antigo retornava isFake=false → fantasma
// passava. Confirmado: workout_logs vazio, tools_audit não tem registra_treino.
const WORKOUT_SIGNATURE =
  /\b\d+\s*(min|minutos?|hora|horas?|h)\b.*\b(caminhada|musculaç[ãa]o|treino|corrida|bike|bicicleta|nataç[ãa]o|alongamento|yoga|pilates|exerc[íi]cio|peso|for[çc]a|cross\w*)\b|\b(caminhada|musculaç[ãa]o|treino|corrida|bike|bicicleta|nataç[ãa]o|exerc[íi]cio).*\b\d+\s*(min|hora)/i

// Bug Roberto 2026-05-29 21:41: LLM IMITOU o formato exato do
// composePendingProposal pra almoço — "Vi isso nas suas fotos (Almoço):" +
// lista de itens + "Confirma?" — mas SEM chamar registra_refeicao. Como o
// pipeline interception só dispara quando a tool foi chamada, NÃO houve
// pending criado nem interactive payload com botões. Paciente recebeu uma
// proposta-fantasma sem botões; quando respondeu por texto, agente perdeu o
// contexto e autocorrigiu pra jantar. Este padrão complementa as assinaturas
// de kcal/workout: detecta a IMITAÇÃO de proposta de botão sem tool.
const FAKE_PROPOSAL =
  /\bvi\s+isso\s+na\s+sua\s+(?:foto|áudio|audio)|\bvi\s+isso\s+nas\s+suas\s+fotos\b|\bentendi\s+do\s+áudio\b|\bentendi\s+do\s+audio\b/i
const PROPOSAL_QUESTION = /\bconfirma\??\s*$|\bregistro\?\s*$/i

// ── Turn in which the goal or the protocol was written (review 2026-10-04) ──
//
// After define_protocolo / define_meta_peso the model repeats the tool's words
// ("Protocolo registrado … a meta de 7% não foi registrada … 1.746 kcal 💪").
// Only a claim ABOUT THE GOAL is explained by the tool. Two earlier versions
// were too wide, and a meal, a correction or a workout claimed in the same
// answer reached the patient with no retry and no audit event:
//  - 9bc012b switched the generic rule off for the whole answer;
//  - the first per-sentence version set aside every sentence that named the
//    goal, so "Registrei o frango e o arroz na sua meta de hoje: 430 kcal 💪"
//    and "Meta registrada: 75 kg. Registrei arroz, feijão e frango grelhado.
//    Você está em 520 kcal da meta de 1.746." passed (16 of the 45 phantom
//    answers of the second check).
// A third check found two more shapes that passed: a participle that agrees
// with the kcal eaten, not with the goal ("520 kcal da meta já registradas"),
// and a verb cut from the list it governs by the sentence break at ": "
// ("Registrei a meta e também: arroz, feijão e frango — 520 kcal").
//
// When in doubt a sentence is NOT set aside, and then the cost is the parent's
// behaviour (one more model call). The exemption is still not complete: it
// reads words, not meaning. What is known to pass in silence is declared,
// phrase by phrase, in the "RC R4" entries of docs/CALCULO-MPP.md §8c (food
// shown with no verb of its own, "520 kcal da meta registrada"). The exemption
// is off when the patient's own text of the turn (`patientTurnText`) has a
// word of MEAL_OR_WORKOUT_WORD: in the probes of the three checks every answer
// that passed came from a turn in which the patient reported a meal or a
// workout. A report made with other words ("Comi 2 fatias de pizza") does not
// switch it off; that is declared in §8c too.

// PT-BR letters: `\b` breaks on accented ones (same gotcha as MEAL_KEYWORDS).
const LETTER = 'a-zà-ú'
const ptWord = (alternatives: string): RegExp =>
  new RegExp(`(?:^|[^${LETTER}])(?:${alternatives})(?=$|[^${LETTER}])`, 'i')

// "gordura" only in its body-fat wording: alone it is also a macro of a meal
// ("520 kcal, 20 g de gordura"), and that sentence must stay under the guard.
const GOAL_NOUN =
  'protocolos?|metas?|objetivos?|imc|gordura\\s+corporal|%\\s*de\\s+gordura|percentual\\s+de\\s+gordura|recomposi[çc][ãa]o|ganho\\s+de\\s+massa|manuten[çc][ãa]o'
const GOAL_WORD = ptWord(GOAL_NOUN)
// The workout words of WORKOUT_SIGNATURE without "peso" and "força", which
// also describe a weight goal; a duration next to them ("40 minutos de força",
// "1 hora de peso livre") is caught by WORKOUT_SIGNATURE itself. The same list
// is applied to the patient's text of the turn (`patientTurnText`).
const MEAL_OR_WORKOUT_WORD = ptWord(
  'caf[ée]s?|almo[çc](?:os?|ar|ei|ou)|lanch(?:es?|ar|ei|ou)|jant(?:as?|ar|ares|ei|ou)|ceias?|refei[çc](?:[ãa]o|[õo]es)|treinos?|caminhadas?|corridas?|muscula[çc][ãa]o|bikes?|bicicletas?|nata[çc][ãa]o|alongamentos?|yoga|pilates|exerc[íi]cios?|cross\\w*',
)
// A sentence ends at . ! ? … or : followed by a space, or at a line break
// ("1.746 kcal" and "118,5 g" are not split).
const SENTENCE_BREAK = /(?<=[.!?…:])\s+|\n+/

const hasFoodSignature = (text: string): boolean => /\bkcal\b/i.test(text) || /🔥|💪|📊/.test(text)
const hasWriteClaim = (text: string): boolean =>
  CORRECTION_CLAIM.test(text) || REGISTRATION_CLAIM.test(text)

// A claim BOUND to the goal noun, in the two shapes the goal tools hand to
// the model (goalBelowFloorReason in tools.ts; the messages of
// bf-goal-classifier.ts and weight-goal-classifier.ts):
//  (A) the participle right after the goal noun phrase — "Protocolo
//      registrado", "A meta de 7% de gordura corporal não foi registrada",
//      "A meta de IMC 18 não foi registrada", "Meta de 7% registrada";
//  (B) the finite verb whose object, right after it, is the goal noun —
//      "Não registrei essa meta", "não registrei essa meta e nada mudou";
//      only a determiner (and "também"/"já") may stand between them.
// Between the noun and the participle only the value of the goal and an
// auxiliary may stand, so "Meta registrada e arroz com frango anotado" and
// "…e já deixei anotado o pão com ovo" leave "anotado" unbound.
//
// The number token must leave ONE way to read a text. It used to end in
// "\s*(?:%|kg|kcal)?": the spaces after a number could go to the token or to
// the "\s+" of the next repetition, and "75 kg" was one token or two. A
// sentence with a verb, a goal noun, N numbers two spaces apart and no
// participle doubled the time per number (3.7 s at N=28; third check). Now a
// unit belongs to the number only when attached ("75kg") or when it is "%" or
// "kcal" (neither is a token of its own); a spaced "kg" is the standalone
// token. The texts accepted are the same.
const GOAL_VALUE_TOKEN =
  'd[eoa]|imc|bf|peso|gordura|corporal|kg|di[áa]ri[ao]|recomposi[çc][ãa]o|manuten[çc][ãa]o|ganho\\s+de\\s+massa|\\d+(?:[.,]\\d+)*(?:kg|\\s*(?:%|kcal))?'
const AUXILIARY_TOKEN = 'n[ãa]o|j[áa]|tamb[ée]m|ainda|agora|foi|foram|est[áa]|ficou'
const GOAL_DETERMINER = '[ao]s?|seus?|suas?|ess[ea]|est[ea]|nov[oa]'
const GOAL_BOUND_CLAIM = new RegExp(
  `(?<![${LETTER}])(?:` +
    // (A) noun phrase + participle
    `(?:${GOAL_NOUN})(?![${LETTER}])(?:\\s+(?:${GOAL_VALUE_TOKEN}|${AUXILIARY_TOKEN})(?![${LETTER}]))*` +
    `\\s+(?:re-?registrad|registrad|anotad|atualizad|corrigid|salv)[oa]s?` +
    '|' +
    // (B) finite verb + goal noun as its object
    `(?:re-?registrei|registrei|anotei|salvei|salvamos|atualizei|corrigi|troquei)` +
    `(?:\\s+(?:tamb[ée]m|j[áa]))?(?:\\s+(?:${GOAL_DETERMINER})(?![${LETTER}]))*\\s+(?:${GOAL_NOUN})` +
    `)(?![${LETTER}])`,
  'gi',
)
const GOAL_NOUN_PHRASE = new RegExp(`(?<![${LETTER}])(?:${GOAL_NOUN})(?![${LETTER}])`, 'gi')

// Shape (A) only binds the participle that AGREES with the goal noun heading
// the phrase. "520 kcal da meta já registradas" has the goal noun and then a
// participle, but the feminine plural belongs to the kcal eaten: it is a claim
// about the meal (third check, HIGH — 11 answers passed in silence).
const BOUND_PARTICIPLE = /(?:registrad|anotad|atualizad|corrigid|salv)([oa])(s?)$/i
// The phrase starts at its head noun. Feminine: meta, gordura corporal,
// recomposição, manutenção. Masculine: protocolo, objetivo, IMC, "% de
// gordura", percentual de gordura, ganho de massa.
const FEMININE_GOAL_NOUN = /^(?:metas?|gordura|recomposi|manuten)/i
const PLURAL_GOAL_NOUN = new RegExp(`^(?:protocolos|metas|objetivos)(?![${LETTER}])`, 'i')
// "Protocolo e meta registrados", "O protocolo e a meta foram registrados":
// one plural participle over two goal nouns joined by "e". The text before the
// phrase must END in the other goal noun (with its value) and that "e" — two
// goal nouns anywhere in the sentence are not enough ("520 kcal da meta de
// recomposição já registradas" names two and claims the meal).
const AFTER_COORDINATED_GOAL_NOUN = new RegExp(
  `(?<![${LETTER}])(?:${GOAL_NOUN})(?![${LETTER}])(?:\\s+(?:${GOAL_VALUE_TOKEN})(?![${LETTER}]))*` +
    `,?\\s+e\\s+(?:(?:${GOAL_DETERMINER})\\s+)*$`,
  'i',
)

/** `claim` is one match of GOAL_BOUND_CLAIM and `before` the sentence up to it. */
function isAboutTheGoal(claim: string, before: string): boolean {
  const participle = BOUND_PARTICIPLE.exec(claim)
  // Shape (B): the goal noun is the object of the finite verb.
  if (!participle) return true
  const feminine = participle[1]?.toLowerCase() === 'a'
  const plural = participle[2] !== ''
  if (feminine === FEMININE_GOAL_NOUN.test(claim) && plural === PLURAL_GOAL_NOUN.test(claim))
    return true
  return plural && AFTER_COORDINATED_GOAL_NOUN.test(before)
}

// Every other word of a sentence that carries a bound claim must be a goal
// noun or come from this closed list (numbers and symbols are not words).
// Food and sport names are an open class and cannot be listed; the words
// around a goal claim can — these are the ones of the tools' own sentences
// ("Por segurança, não registrei essa meta e nada mudou no seu cadastro"),
// the units of a goal and a few fillers. One word from outside ("Registrei a
// meta e o frango com arroz", "Salada dentro da meta registrada", "Meta
// registrada, Roberto!") keeps the sentence under the guard. "massa" and
// "gordura" are deliberately absent: outside "ganho de massa" and "gordura
// corporal" they are food ("Registrei a meta e a massa: 430 kcal").
const GOAL_SENTENCE_WORD = new RegExp(
  '^(?:' +
    'peso|bf|kg|kcal|d[ée]ficit|cadastro' +
    '|[ao]s?|uma?|seus?|suas?|ess[ea]|est[ea]|nov[oa]' +
    '|d[eoa]s?|em|n[oa]s?|para|pra|pro|por|com|como|e|ao|à' +
    '|n[ãa]o|j[áa]|tamb[ée]m|ainda|agora|foi|foram|est[áa]|ficou' +
    '|seguran[çc]a|nada|mudou|dia|di[áa]ri[ao]|sucesso' +
    '|pronto|perfeito|feito|[óo]timo|certo|combinado|beleza|ok|vamos|focar|seguimos' +
    ')$',
  'i',
)
const SENTENCE_WORD = new RegExp(`[${LETTER}]+`, 'gi')

/** True when every registration/correction verb of the sentence is bound to
 * the goal noun (a participle also has to agree with it) and every other word
 * of it is a goal noun or in the closed list. A sentence with no such verb
 * claims nothing. */
function claimsOnlyTheGoal(sentence: string): boolean {
  if (!hasWriteClaim(sentence)) return true
  // A phrase that fails the agreement stays in `rest`, verb included.
  const rest = sentence.replace(GOAL_BOUND_CLAIM, (claim: string, offset: number) =>
    isAboutTheGoal(claim, sentence.slice(0, offset)) ? ' ' : claim,
  )
  // Today the closed list alone would also catch an unbound verb (none is in
  // it); the explicit check keeps the rule standing if the list grows.
  if (hasWriteClaim(rest)) return false
  const words = rest.replace(GOAL_NOUN_PHRASE, ' ').match(SENTENCE_WORD) ?? []
  return words.every((word) => GOAL_SENTENCE_WORD.test(word))
}

// "Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪": the
// sentence break at ": " leaves the verb in a piece made only of listed words,
// and the list the verb governs in the next piece, which has no verb (third
// check, MEDIUM). A piece that stops at a coordination before the colon is an
// open list and is not set aside (without a verb it claims nothing either
// way). "Meta registrada:" and "Meta registrada também." are not matched.
const OPEN_COORDINATION = new RegExp(`(?<![${LETTER}])(?:e|tamb[ée]m|mais|ainda)\\s*:$`, 'i')
const endsInOpenList = (sentence: string): boolean => OPEN_COORDINATION.test(sentence.trimEnd())

/**
 * The part of an answer that the goal tool does NOT explain, or null when the
 * tool explains every claim the steps below recognise in it.
 *
 *  1. Split the answer into sentences.
 *  2. Set a sentence aside only when ALL of this holds: it has a goal word; it
 *     has no meal-or-workout word and no workout signature (duration + type);
 *     every registration/correction verb in it is bound to the goal noun, a
 *     participle agreeing with it; its other words are all goal nouns or in
 *     the closed list above; and it does not stop at an open coordination.
 *  3. If a registration or correction verb is left in the remaining sentences,
 *     the guard fires on them. The caller already checked that the WHOLE
 *     answer carries kcal/emoji or a workout signature, exactly as the parent
 *     commit 279ba09 did, so the signature is not required again here.
 *
 * In a sentence that carries a verb, the meal-or-workout word and the workout
 * signature are today also words from outside the closed list; the two checks
 * stay so that step 2 does not depend on what the list holds.
 */
function outsideGoalSentences(content: string): string | null {
  const kept = content
    .split(SENTENCE_BREAK)
    .filter(
      (s) =>
        !GOAL_WORD.test(s) ||
        MEAL_OR_WORKOUT_WORD.test(s) ||
        WORKOUT_SIGNATURE.test(s) ||
        !claimsOnlyTheGoal(s) ||
        endsInOpenList(s),
    )
  return kept.some(hasWriteClaim) ? kept.join('\n') : null
}

/**
 * Retorna isFake=true quando o texto afirma registro/correção + tem assinatura
 * de card (kcal/🔥💪📊 pra refeição OU duração+tipo pra treino) MAS nenhuma
 * tool de gravação rodou no turno. Correção tem prioridade no `kind` (decide
 * a mensagem de retry: replace=true).
 */
export function detectFakeWrite({
  content,
  patientText,
  registrationToolCalled,
  prescriptionToolCalled,
  skipToolCalled,
  goalToolCalled,
  patientTurnText,
  mealTypeHint,
}: FakeWriteInput): FakeWriteResult {
  if (registrationToolCalled) return { isFake: false, kind: null }

  // Bug Roberto 2026-06-15: paciente diz "Pulei", LLM responde "Anotado:
  // jantar pulado" SEM chamar marca_refeicao_pulada. Antes do fix, esse texto
  // caía na regex REGISTRATION_CLAIM (via "anotado") e o retry forçava
  // registra_refeicao — Haiku obediente copiava items do histórico e criava
  // pending fantasma. Solução: detectar SKIP_CLAIM no texto do paciente
  // ANTES das regras de registration/correction, e quando marca_refeicao_pulada
  // NÃO foi chamada, flagrar kind='skip' (retry message dirigido pra skip
  // tool, não pra registra_refeicao).
  //
  // HARDENING (review CRITICAL 2026-06-16): SKIP_CLAIM sozinho gera false
  // positives massivos ("passei direto pra cama", "não comi banana",
  // "jejum intermitente"). Pré-condições obrigatórias agora:
  //  (a) NÃO casa SKIP_NEGATIVE_CONTEXT (filtra "passei direto pra X",
  //      "jejum intermitente", "não comi <item>")
  //  (b) NÃO casa ABANDONMENT (clínico, não tool)
  //  (c) CONTENT do LLM precisa parecer fake-acknowledgment de skip:
  //      SKIP_ACK_CLAIM OU REGISTRATION_CLAIM (que é o caso real do bug
  //      Roberto: "Anotado: jantar pulado").
  // Sem (c), o LLM provavelmente respondeu coisa normal/conversational
  // (e.g. "Boa noite!" pra "passei direto pra cama") e não há fake-write.
  if (patientText && !skipToolCalled) {
    const isAbandonment = ABANDONMENT_CLAIM.test(patientText)
    const hasNegativeContext = SKIP_NEGATIVE_CONTEXT.test(patientText)
    const hasSkipClaim = SKIP_CLAIM.test(patientText)
    if (!isAbandonment && !hasNegativeContext && hasSkipClaim) {
      // Pré-condição (c): LLM tem que ter "anotado" o skip — senão é
      // conversa normal e não há fake-write.
      const llmAcknowledgedSkip =
        SKIP_ACK_CLAIM.test(content) || REGISTRATION_CLAIM.test(content)
      if (llmAcknowledgedSkip) {
        const inferredMealType = inferMealFromSkipText(patientText, mealTypeHint)
        return { isFake: true, kind: 'skip', inferredMealType }
      }
    }
  }

  // --- Detectores de prescrição-fantasma (rodam ANTES das regras antigas
  // porque cardápio inventado tem aparência profissional, paciente segue
  // sem questionar). Só dispara se gera_dieta/gera_treino NÃO foram chamadas.
  if (!prescriptionToolCalled) {
    // DIET FAKE: ≥2 headers de refeição + (lista de compras OU total diário).
    // Os 2 sinais juntos diferenciam cardápio inventado de uma simples
    // explicação ("almoço: arroz + frango" em uma linha não dispara).
    const dietHeaders = content.match(DIET_REFEICAO_HEADER) ?? []
    const hasDietContext = DIET_SHOPPING.test(content) || DIET_TOTAL.test(content)
    if (dietHeaders.length >= 2 && hasDietContext) {
      return { isFake: true, kind: 'diet_fake' }
    }

    // TRAINING FAKE: ≥1 header de dia/treino + ≥3 linhas de exercício no
    // formato "Nome NxR". Apenas explicar "vou treinar segunda" não dispara.
    const trainingHeaders = content.match(TRAINING_DAY_HEADER) ?? []
    const exerciseLines = content.match(TRAINING_EXERCISE_LINE) ?? []
    if (trainingHeaders.length >= 1 && exerciseLines.length >= 3) {
      return { isFake: true, kind: 'training_fake' }
    }
  }

  // Proposta-fake (Roberto 2026-05-29): LLM imita "Vi isso na sua foto …
  // Confirma?" sem chamar tool. Não tem kcal/workout signature mas é claro
  // que o LLM achou que tava propondo um botão → força retry pra ele chamar
  // registra_refeicao e o pipeline criar o pending com botões de verdade.
  if (FAKE_PROPOSAL.test(content) && PROPOSAL_QUESTION.test(content.trim())) {
    return { isFake: true, kind: 'registration' }
  }

  const foodSignature = hasFoodSignature(content)
  const hasWorkoutSignature = WORKOUT_SIGNATURE.test(content)

  // Proposta-fake genérica (Roberto 2026-05-30 13:47): LLM disse "Entendido!
  // Então incluo também o ovo... • leite com whey 190 kcal... Total: 568 kcal
  // ... Confirma?" — tem kcal + bullets + "Confirma?" no fim, MAS sem verbo de
  // claim ("incluo" não bate REGISTRATION_CLAIM, "vi isso" não bate
  // FAKE_PROPOSAL). Critério mais amplo: refeição-signature + ≥2 bullets de
  // itens + termina com "Confirma?" → é proposta de botão sem tool. Retry.
  if (foodSignature && PROPOSAL_QUESTION.test(content.trim())) {
    const bulletCount = (content.match(/(?:^|\n)\s*[•\-*]\s/g) ?? []).length
    if (bulletCount >= 2) {
      return { isFake: true, kind: 'registration' }
    }
  }

  // Proposta-fake SEM kcal (Roberto 2026-05-30 14:24): variante que escapou a
  // regra acima — LLM mandou "Então o almoço fica assim: • risoto (200g) •
  // queijo ralado (30g) ... Confirma?" SEM kcal e SEM emojis (só quantidades
  // em g/ml/unidade). Paciente teve que digitar "Confirma" pra forçar tool.
  // Critério: ≥2 bullets COM quantidade em (g)/(ml)/(unidade) + "Confirma?"
  // no fim → mesma intenção de proposta de botão, kind=registration.
  if (PROPOSAL_QUESTION.test(content.trim())) {
    const bulletLines = content.match(/(?:^|\n)\s*[•\-*]\s+[^\n]+/g) ?? []
    const QTY_IN_BULLET = /\(\s*\d+(?:[.,]\d+)?\s*(?:g|ml|kg|l|unidades?|fatia|p[ãa]o)\b/i
    const bulletsWithQty = bulletLines.filter((l) => QTY_IN_BULLET.test(l))
    if (bulletsWithQty.length >= 2) {
      return { isFake: true, kind: 'registration' }
    }
  }

  // Rascunho com kcal inventada (Roberto 2026-06-03 15:41): LLM mandou
  // "Entendi isso pro seu almoço: • alface crespa (40g) — 6 kcal • alface roxa
  // (20g) — 3 kcal ... Tem proteína nessa refeição?" — kcal em ≥2 bullets de
  // itens MAS termina com pergunta legítima (não "Confirma?") → escapa as
  // regras acima. Resultado: kcal inventada exibida ao paciente; quando a
  // tool roda na segunda passada, os números são diferentes e parece bug de
  // consistência. Critério: ≥2 bullets do formato "• <nome> (<qty>) — <X> kcal"
  // e nenhuma tool de registro chamada → força retry pro LLM chamar
  // registra_refeicao ANTES de mostrar kcal.
  const KCAL_BULLET = /(?:^|\n)\s*[•\-*]\s+[^\n]+\(\s*\d+(?:[.,]\d+)?\s*(?:g|ml|kg|l|unidades?|fatia|p[ãa]o)[^\n]*?\d+(?:[.,]\d+)?\s*kcal/i
  const kcalBullets = content.match(new RegExp(KCAL_BULLET.source, 'gi')) ?? []
  if (kcalBullets.length >= 2) {
    return { isFake: true, kind: 'registration' }
  }
  if (!foodSignature && !hasWorkoutSignature) return { isFake: false, kind: null }

  // Review 2026-10-04 (reavaliação com meta recusada): depois de
  // define_protocolo o modelo responde "Protocolo registrado … a meta de 7% não
  // foi registrada … 1.746 kcal 💪" — texto fiel ao retorno da tool, que a regra
  // abaixo lia como refeição registrada sem tool e forçava uma 3ª chamada com
  // "chame registra_refeicao". Com a tool de protocolo/meta no turno, só as
  // frases cuja afirmação é toda sobre a meta saem da leitura; um verbo de
  // registro/correção que sobre dispara. Com o card "Total refeição" o texto é
  // lido inteiro.
  const outsideGoal =
    goalToolCalled && !MEAL_CARD.test(content) ? outsideGoalSentences(content) : content
  // Third check of 2026-10-04: every answer that still passed in silence came
  // from a turn in which the PATIENT reported a meal or a workout next to the
  // goal ("Minha meta agora é 75 kg. Almocei arroz, feijão e frango
  // grelhado."). In such a turn the goal tool explains nothing about the meal,
  // so the exemption is off and the whole answer is read, as in the parent
  // 279ba09. When the per-sentence reading already leaves a claim it is kept:
  // same verdict and same kind of retry as without the patient's text. This
  // can only add turns in which the guard fires. WORKOUT_SIGNATURE is not
  // applied to the patient's text: it takes "peso" next to any hour, and a
  // goal turn says "Acordo às 7h, peso 80 kg. Minha meta agora é 75 kg".
  const claimText =
    outsideGoal ??
    (patientTurnText !== undefined && MEAL_OR_WORKOUT_WORD.test(patientTurnText) ? content : null)
  if (claimText === null) return { isFake: false, kind: null }

  if (CORRECTION_CLAIM.test(claimText)) return { isFake: true, kind: 'correction' }
  if (REGISTRATION_CLAIM.test(claimText) || MEAL_CARD.test(content))
    return { isFake: true, kind: 'registration' }
  return { isFake: false, kind: null }
}
