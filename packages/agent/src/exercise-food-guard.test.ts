import { describe, expect, it } from 'vitest'
import {
  asksExerciseFoodQuestion,
  EXERCISE_FOOD_ANSWER_OPENING,
  lastReplyIsSameAnswer,
  renderExerciseFoodAnswer,
  statedWorkoutCalories,
} from './exercise-food-guard.js'
import { detectFakeWrite } from './fake-write-detector.js'
import { detectPrematureBlockCompletion } from './numeric-validator.js'

// iPhone, staging, 2026-10-04 — the exact phrase stored in `messages`
// (provider 'mobile_flow', 2026-10-04T15:03:40.503Z), typed without accents.
const REPORT_PHRASE = 'Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?'

// > RC A — cenário pergunta direta fora da gramática NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   Lista OUTSIDE_THE_GRAMMAR abaixo (erro de digitação, "será que", "ingerir",
//   "consigo", "repor" sem calorias, emoji, modalidade fora da lista, "passar
//   da meta", pergunta sem o relato do treino de hoje…): vão para o modelo com
//   o contexto corrigido.
// > RC A — cenário mensagem mista (relato do treino + pergunta direta + outro pedido, sintoma, alimento ou segunda pergunta) NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   Uma palavra a mais e quem responde é o modelo.
// > RC A — cenário resposta do MODELO com o contexto corrigido NÃO coberto nesta PR (pendência da audit 2026-10-04).
// > RC A — cenário redação da resposta do sistema e da REGRA NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   Texto clínico ainda sem aprovação do Roberto.
// > RC A — cenário exercício no balanço de ganho_massa/manutenção NÃO coberto nesta PR (pendência da audit 2026-10-04).
// > RC A — cenário canal WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
// > RC A — cenário afirmação sem pontuação final ("treinei hoje e posso comer mais") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   Sem "?" e sem marca no fim não dá para separar a pergunta ditada da
//   afirmação: continua recebendo a resposta do sistema. Com "." ou "!" no fim
//   vai para o modelo.

const unique = (list: string[]): string[] => [...new Set(list)]

// Inside the grammar: (greeting) + report of today's workout + direct question.
const MUST_MATCH = unique([
  // the report, as typed and with accents
  REPORT_PHRASE,
  'Treinei musculação hoje e gastei 322 kcal. Posso comer 322 kcal a mais?',
  // report → "may I eat more?"
  'Treinei hoje. Posso comer mais hoje?',
  'treinei hoje, posso comer a mais?',
  'Treinei. Posso comer a mais hoje?',
  'Treinei, da pra comer um pouco a mais?',
  'Fiz musculação hoje, dá pra comer mais?',
  'Treinei pesado. Posso comer mais hoje?',
  'Treinei hoje, eu posso comer mais?',
  'Treinei hoje, dá para eu comer mais?',
  'Treinei hoje, da pra comer mais um pouco?',
  'Treinei hoje, então posso comer mais né?',
  'Treinei hoje então eu posso comer mais né?',
  'Treinei hoje, posso comer mais, certo?',
  'Treinei e gastei 322 kcal. Posso comer 322 kcal a mais, certo?',
  'Treinei hoje, posso comer mais ?',
  'Fiz crossfit hoje, posso comer mais?',
  'Fiz pilates hoje, posso comer a mais?',
  'Corri 5km hoje, da pra comer mais?',
  'Caminhei 40 minutos de manhã. Posso comer mais?',
  'Fui à academia hoje. Posso comer um pouco mais?',
  'Boa tarde, fiz yoga hoje, posso comer um pouquinho mais?',
  'Bom dia! Treinei agora cedo, posso comer mais hoje?',
  'Oi Flow, treinei hoje, posso comer mais?',
  // with the calories burned
  'Malhei e queimei 400 kcal, posso comer mais 400 kcal?',
  'Corri 10 km e queimei 650 calorias. Posso comer 650 calorias a mais hoje?',
  'Fiz bike e queimei 480 kcal.\nPosso comer mais 480 kcal?',
  'Oi! Treinei musculação e gastei 322 kcal. Posso comer 322 kcal a mais?',
  'Flow, treinei e gastei 322 kcal, posso comer 322 kcal a mais?',
  'Treinei e gastei 1200 calorias, posso comer 1200 calorias a mais?',
  'Queimei 500 calorias na esteira, posso comer 500 calorias a mais?',
  'Fiz esteira e queimei 500 calorias, posso comer 500 calorias a mais?',
  'Fiz 1h de spinning e gastei 600 kcal, posso comer mais 600 kcal?',
  'Nadei 1 hora e gastei 400 kcal, posso comer 400 kcal a mais?',
  'Treinei leve hoje e gastei 150 kcal, por isso posso comer 150 kcal extras?',
  // pt-BR thousand separator
  'Pedalei 3 horas e gastei 1.200 kcal. Posso comer 1.200 kcal a mais?',
  'Treinei e gastei 1.200 kcal, posso comer 1.200 kcal a mais?',
  // upper case, no punctuation, voice style
  'TREINEI HOJE. POSSO COMER MAIS?',
  'TREINEI MUSCULACAO HOJE E GASTEI 322 KCAL. POSSO COMER 322 KCAL A MAIS?',
  'treinei hoje posso comer mais',
  'treinei hj e gastei 322kcal posso comer 322kcal a mais',
  'Treinei hoje gastei 322 kcal posso comer 322 a mais?',
  'treinei musculacao hoje e gastei 322 kcal posso comer 322 kcal a mais',
  'Fiz academia hoje posso comer mais né',
  'Hoje eu treinei pesado posso comer um pouquinho a mais?',
  // the number echoes the calories reported
  'Treinei e gastei 322 kcal. Posso comer 322 kcal?',
  'Treinei e gastei 322 kcal, posso comer 322 a mais?',
  'Treinei e gastei 322 kcal, posso comer essas 322 kcal?',
  'Queimei 500 kcal no treino, posso comer as 500 kcal que queimei?',
  // question first
  'Posso comer mais porque treinei?',
  'Posso comer mais calorias hoje porque treinei?',
  'posso comer mais kcal hoje ja que malhei?',
  'Posso comer 322 kcal a mais? Treinei musculação hoje e gastei 322 kcal.',
  'Posso comer mais hoje, já que treinei?',
  // question first, then the report after a sentence break
  'Posso comer mais? Treinei.',
  'Posso comer mais. Treinei hoje',
  'posso comer mais, treinei',
  // "como" / "já que" before the report
  'Já que treinei, posso comer um pouco mais?',
  'Como treinei hoje eu posso comer mais?',
  'Já que eu treinei hoje eu posso comer mais calorias?',
  'Como treinei e gastei 322 kcal, posso comer essas 322 kcal?',
  // those calories
  'Fui na academia. Posso comer as calorias do treino?',
  'Treinei e gastei 322 kcal, posso comer essas calorias?',
  'Treinei hoje. Posso comer as calorias que queimei no treino?',
  // replace
  'Fiz 40 min de corrida. Preciso repor as calorias?',
  'Fiz academia hoje. Posso repor as calorias do treino?',
  'Queimei 500 kcal no treino, posso comer de volta essas calorias?',
  'Fiz cardio e gastei 250 kcal. Devo repor essas calorias?',
  'Treinei hoje. Preciso repor as calorias do treino?',
  'Treinei hoje. Tenho que comer de volta as calorias?',
  'Fui à academia hoje e queimei 350 kcal. Devo repor essas 350 kcal?',
  // the target, always next to the report
  'Treinei hoje. O treino aumenta minha meta?',
  'treinei hoje o treino aumenta minha meta',
  'Corri hoje. O exercício aumenta a minha meta de hoje?',
  'Treinei hoje. O treino muda minha meta calórica?',
  'Treinei hoje, a meta aumenta com o treino?',
  'Fiz musculação hoje. Minha meta sobe quando eu treino?',
  'Minha meta aumenta porque treinei?',
  'Minha meta aumenta já que treinei hoje?',
  'Minha meta de hoje sobe porque fiz musculação?',
  'A meta muda? Treinei hoje.',
  'Queimei 322 kcal na academia, isso aumenta minha meta?',
  'Treinei hoje, minha meta aumenta?',
  'Treinei hoje, a meta muda?',
  'Malhei hoje, minha meta de hoje aumenta?',
  'Treinei hoje. O treino aumenta a meta de hoje?',
  // no mark at the end: a dictated question and a statement read the same
  // (declared above as "afirmação sem pontuação final")
  'treinei hoje e posso comer mais',
  'Treinei hoje e posso comer mais',
  'Eu treinei hoje e por isso posso comer mais',
  'Treinei hoje da pra comer mais',
])

// Plausible direct questions left OUT of the grammar on purpose. The model
// answers them, with the corrected context. Widening the grammar for one of
// them needs its own line here moved to MUST_MATCH and a review of what else
// the new rule lets in.
const OUTSIDE_THE_GRAMMAR = unique([
  // typing errors
  'trenei hoje posso comer mais?',
  'treinei hoje posso come mais?',
  // softeners and other verbs
  'eu treinei hoje será que posso comer mais',
  'Treinei hoje. Será que eu posso comer um pouco a mais?',
  'Nadei 1 hora, posso ingerir 400 kcal a mais?',
  'Treinei hoje, pode comer mais?',
  'Treinei hoje posso comer mais sim ou não?',
  'Treinei hoje, posso comer mais hoje por conta do treino?',
  'Fui correr hoje cedo. Posso comer mais por causa disso?',
  'Treinei musculação, gastei 322 kcal, isso quer dizer que posso comer 322 kcal a mais?',
  // "consigo" is capacity or appetite, not permission (review round 2)
  'Treinei pesado. Consigo comer mais hoje?',
  'Treinei hoje, consigo comer mais?',
  // no report of today's workout: "treino" may be the plan or the routine
  // (review round 2 — these stood alone before)
  'O treino muda minha meta?',
  'Minha meta muda quando eu treino?',
  'O treino aumenta minha meta?',
  'o treino aumenta minha meta',
  'O exercício aumenta a minha meta de hoje?',
  'O treino muda minha meta calórica?',
  'A meta aumenta com o treino?',
  'Minha meta sobe quando eu treino?',
  'Posso comer as calorias que queimei no treino?',
  'Posso comer as calorias do treino?',
  'Preciso repor as calorias do treino?',
  'Oi Flow, o treino aumenta minha meta?',
  // symbols the grammar does not read
  'Treinei hoje, posso comer + ?',
  'Treinei hoje 💪 posso comer mais?',
  // workouts outside the list
  'Joguei futebol hoje, posso comer mais?',
  'Fiz treino de perna hoje, posso comer mais?',
  'Fiz exercício hoje. Minha meta aumentou?',
  'Treinei pouco hoje, posso comer mais?',
  // a number that does not echo calories reported burned
  'Treinei hoje. Posso comer 322 kcal?',
  'Treinei hoje. Posso comer 300 a mais?',
  'Treinei e gastei 322 kcal. Posso comer 400 a mais?',
  'Malhei hoje e queimei umas 300 calorias, posso comer elas?',
  'Como treinei, posso comer essas 322 kcal?',
  'Treinei e gastei 300 kcal. Posso comer as 500 kcal a mais?',
  // "repor" with no calories named
  'Treinei e gastei 300 kcal, posso repor?',
  'Caminhei 1 hora. Tenho que repor o que gastei?',
  'Treinei hoje e queimei 300 kcal. Preciso compensar essas calorias comendo?',
  // over the target
  'Treinei hoje. Posso passar da meta?',
  'Treinei hoje. Posso comer mais do que a meta?',
  'Treinei hoje. Posso ultrapassar a meta em 322 kcal?',
  'Treinei hoje e gastei 322 kcal, posso comer 322 calorias além da meta?',
  // "do I have / did I earn"
  'Treinei hoje e gastei 400 kcal. Tenho 400 kcal a mais pra comer?',
  'Treinei hoje e gastei 400 kcal. Tenho direito a mais 400 kcal?',
  'Ganhei 322 kcal pra comer por causa do treino?',
  'Fiz musculacao, ganhei 322 kcal pra comer?',
  'Treinei, gastei 322 kcal, então sobram 322 kcal a mais pra eu comer?',
  // other wordings about the target and what is left
  'O treino me dá direito a comer mais?',
  'O treino me libera comer mais?',
  'O treino libera mais calorias pra comer?',
  'As calorias do treino eu posso comer?',
  'As calorias que gastei no treino voltam pra minha meta?',
  'as calorias do treino somam na meta?',
  'O treino soma na meta?',
  'O treino desconta do que comi?',
  'O treino não aumenta minha meta?',
  'O gasto do treino entra na minha meta?',
  'O exercício conta na meta?',
  'O exercício entra no que resta pra comer?',
  'Treinei 1 hora. O gasto entra no que posso comer?',
  'Meu treino de hoje muda alguma coisa na meta?',
  'A academia de hoje aumenta minha meta?',
  'treino aumenta a meta de calorias',
  'minha meta aumenta nos dias de treino?',
  'O exercício de hoje aumenta o que eu posso comer?',
  'O exercício aumenta quanto eu posso comer?',
  'treino conta pra comer mais?',
  // hypothetical: no workout reported
  'Minha meta muda se eu treinar?',
  'Se eu treinar posso comer mais?',
  'Se eu malhar hoje posso comer mais?',
])

// Every input quoted in the adversarial review of 2026-10-04 as hijacked by
// the first predicate, verbatim (the ones it abbreviated with "…" are written
// out as they were run).
const REVIEW_HIJACKED = unique([
  // a workout to create, change or delete
  'Cria um treino de perna pra mim. Posso comer mais hoje?',
  'Apaga o treino de hoje. Posso comer mais?',
  'Quero um treino novo. Posso comer mais hoje?',
  'Faz um treino de peito pra mim. Posso comer mais?',
  'Preciso de um treino novo, posso comer mais hoje?',
  'Quero trocar meu treino de perna. Posso comer mais hoje?',
  'Troca meu treino de hoje por um de braço. Posso comer mais?',
  'Muda meu treino pra 4x. Posso comer mais?',
  'Atualiza meu treino. Posso comer mais hoje?',
  'Prepara um treino de 30 min. Posso comer mais hoje?',
  'Manda um treino de costas. Posso comer mais?',
  'quero trocar meu treino de perna por um de braço e também treinei hoje posso comer mais',
  'Monta um treino pra mim. Posso comer mais?',
  'Remove o treino de hoje, lancei errado. Posso comer mais?',
  'Exclui o treino duplicado. Posso comer mais hoje?',
  'Deleta o treino de hoje. Posso comer mais?',
  'Altera o treino pra 500 kcal. Posso comer mais 500 kcal?',
  'Adiciona musculação 50 min 322 kcal. Posso comer 322 kcal a mais?',
  'Lança meu treino de hoje, 400 kcal. Posso comer mais 400 kcal?',
  'Salva meu treino de 322 kcal. Posso comer 322 kcal a mais?',
  'O treino ficou duplicado, gastei 322 kcal e nao 644 kcal. Posso comer mais?',
  'O app marcou 322 kcal no treino mas gastei 600 kcal. Posso comer 600 kcal a mais?',
  'Errei, o treino foi 200 kcal. Posso comer mais 200 kcal?',
  // symptom, health condition, how the patient feels
  'Treinei hoje e passei mal. Posso comer mais?',
  'Treinei e passei mal, posso comer mais?',
  'Treinei e minha glicemia baixou. Posso comer mais?',
  'Treinei hoje e minha glicemia baixou. Posso comer mais?',
  'Treinei hoje e estou cansado, posso comer mais?',
  'Estou cansado. Treinei hoje, posso comer mais?',
  'Treinei hoje e vomitei. Posso comer mais?',
  'Treinei hoje e senti fraco. Posso comer mais?',
  'Treinei e fiquei fraca, posso comer mais?',
  'Treinei em jejum e fiquei tremendo. Posso comer mais?',
  'Treinei e minha pressão caiu. Posso comer mais?',
  'Treinei hoje e minha pressão caiu. Posso comer mais?',
  'Treinei e tive queda de glicose, posso comer mais?',
  'Treinei e a vista escureceu. Posso comer mais?',
  'Treinei e quase caí de tão zonzo. Posso comer mais?',
  'Treinei hoje e to suando frio, posso comer mais?',
  'Treinei hoje, estou gestante, posso comer mais?',
  'Treinei hoje, estou amamentando, posso comer mais?',
  'Treinei hoje, tomo ozempic, posso comer mais?',
  'Treinei hoje, tomo insulina, posso comer mais?',
  'Treinei e tive cãibra, posso comer mais?',
  'Treinei e fiquei desidratado. Posso comer mais?',
  'Treinei e to faminto, posso comer mais?',
  'Treinei e to varado, posso comer mais?',
  'Treinei pra compensar a compulsão. Posso comer mais?',
  'Treinei 3 horas de culpa porque exagerei. Posso comer mais?',
  'Treinei hoje mas to muito ansiosa, posso comer mais?',
  'Treinei hoje, to triste, posso comer mais?',
  'Treinei hoje e mesmo assim engordei, to desanimado. Posso comer mais?',
  'Treinei hoje e estou exausto, posso comer mais?',
  // did not train, will train, another day
  'Hoje não deu pra treinar, posso comer mais?',
  'Hoje não teve academia, posso comer mais?',
  'Faltei no treino, posso comer mais?',
  'Pulei o treino hoje. Posso comer mais?',
  'Cancelei o treino, posso comer mais?',
  'Meu treino foi cancelado. Posso comer mais hoje?',
  'Hoje é descanso do treino. Posso comer mais?',
  'Antes de treinar posso comer mais?',
  'Vou treinar agora, posso comer mais antes?',
  'Vou treinar mais tarde. Posso comer mais agora?',
  'Pretendo treinar hoje à noite, posso comer mais?',
  'Vou treinar às 18h. Posso comer mais depois do treino?',
  'Posso comer mais depois do treino?',
  'Se eu treinar no dia seguinte posso comer mais hoje?',
  'Treinei hoje. Posso comer mais no dia seguinte?',
  'Treinei hoje. Posso comer mais no dia de descanso?',
  // open question, reported speech, statement
  'Treinei hoje. O que posso comer a mais?',
  'Treinei hoje. O que posso comer mais?',
  'Treinei hoje, o que da pra comer a mais?',
  'Treinei hoje. Como posso comer mais?',
  'Treinei hoje. Meu nutricionista disse que posso comer mais.',
  'Treinei hoje. Minha personal falou que posso comer mais hoje.',
  'Treinei hoje e li que posso comer mais.',
  'Treinei hoje, então acho que posso comer mais.',
  'Treinei hoje. Vi no app que posso comer mais.',
  'Treinei mas sei que não posso comer mais.',
  // another person
  'Meu filho treinou hoje, ele pode comer mais?',
  'Minha esposa malhou e gastou 500 kcal. Pode comer mais?',
  'Meu aluno treinou hoje. Ele pode comer mais?',
  // the inverse question, the profile, steps
  'Posso compensar o excesso de calorias treinando mais?',
  'Passei da meta, posso compensar essas calorias na academia?',
  'Preciso compensar as calorias do exagero com cardio?',
  'Devo compensar as 500 kcal que passei fazendo corrida?',
  'Aumentei meu treino pra 6 dias. Isso muda minha meta?',
  'Comecei a fazer musculação. Isso aumenta minha meta?',
  'Parei de treinar. Isso muda minha meta?',
  'Machuquei e parei a academia. Isso muda minha meta?',
  'Emagreci 2 kg treinando, isso muda minha meta?',
  'Caminhei 8 mil passos, isso conta na meta?',
  'Fiz 10 mil passos na caminhada. Isso entra na meta?',
  'Estou em manutenção, treinei hoje, posso comer mais?',
  'Hoje foi uma corrida danada no trabalho, posso comer mais?',
  'Fiz um treinamento na empresa o dia todo. Posso comer mais?',
  // the patient asks again or says he already knows
  'Mas treinei 2 horas hoje, posso comer mais?',
  'Sei que treino não libera, mas posso comer mais hoje?',
  'Treinei hoje. Você já me disse que não, mas posso comer mais?',
  // called debatable by the review; the grammar leaves them to the model
  'Corri 10 km e bati meu recorde! Posso comer mais?',
  'Treinei hoje e já passei da meta. Posso comer mais?',
])

// Every input quoted in the second adversarial review (2026-10-04, round 2)
// as answered by the system when it should not be, verbatim.
const REVIEW_ROUND_2 = unique([
  // a statement, not a question: capacity, appetite or belief
  'Treinei pesado hoje, consigo comer mais.',
  'Treinei cedo e consigo comer mais hoje',
  'Malhei hoje e consigo comer um pouco mais.',
  'Treinei hoje e consigo comer mais',
  'Treinei hoje e posso comer mais!',
  'Treinei hoje, então posso comer mais.',
  'Treinei hoje, dá pra comer mais.',
  'Treinei hoje e preciso repor as calorias.',
  // the same class in the reviewer's own corpus
  'Hoje treinei, por isso posso comer mais.',
  'Treinei agora e consigo comer mais',
  'Malhei cedo e consigo comer mais hoje',
  'Treinei, entao posso comer mais.',
  // "essas N kcal" that does not repeat the burn reported (a food quoted
  // earlier in the chat), and "certo" as an adverb
  'Treinei hoje. Posso comer essas 500 kcal?',
  'Treinei e gastei 300 kcal. Posso comer essas 500 kcal?',
  'Treinei hoje. Posso comer mais certo?',
])

// The raw ending: with no "?" anywhere, a final mark makes it a statement.
const ENDS_AS_STATEMENT = unique([
  'Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais.',
  'Treinei hoje e posso comer mais.',
  'Treinei hoje e posso comer mais. ',
  'Treinei hoje e posso comer mais...',
  'Treinei hoje e posso comer mais…',
  'Treinei hoje e posso comer mais!!',
  'Treinei hoje e posso comer mais!\n',
  'Treinei hoje e posso comer mais."',
  'Treinei hoje e posso comer mais.”',
  "Treinei hoje e posso comer mais!' ",
  'Treinei hoje, posso comer mais,',
  'Treinei hoje, posso comer mais;',
  'Treinei hoje. Preciso repor as calorias do treino.',
  'Treinei hoje, minha meta aumenta.',
  'Posso comer mais porque treinei.',
  'Posso comer mais. Treinei hoje.',
  'TREINEI HOJE. POSSO COMER MAIS!',
])

// The reviewer's corpus of messages that must reach the model (165 of them;
// the ones quoted in the findings are in REVIEW_HIJACKED).
const REVIEW_CORPUS = unique([
  'treinei e depois comi 200 g de frango',
  'Treinei e depois almocei 200 g de frango, posso comer mais?',
  'Pós treino: 2 ovos e 1 banana',
  'Depois da academia jantei arroz feijao e bife',
  'Treinei hoje e mandei um shake de 300 kcal a mais. Posso?',
  'Treinei hoje, vou comer 200 g de frango a mais. Posso comer mais?',
  'Treinei hoje. Acabei de comer um pao a mais, pode?',
  'Registra 300 kcal de corrida. Posso comer mais?',
  'Anota ai: treinei 1h musculação. Posso comer mais?',
  'Inclui o treino de hoje 322 kcal, posso comer 322 kcal a mais?',
  'Coloca aí que treinei e gastei 322 kcal. Posso comer 322 kcal a mais?',
  'Treinei e gastei 322 kcal, marca aí. Posso comer 322 kcal a mais?',
  'Treinei hoje, me passa um cardápio pra comer mais',
  'Treinei hoje. Faz um cardápio com 300 kcal a mais?',
  'Treinei hoje. O que eu posso comer mais tarde?',
  'Treinei, o que da pra comer agora?',
  'Treinei hoje, posso comer mais o quê?',
  'Treinei hoje. Posso comer mais alguma coisa?',
  'Treinei hoje. Posso comer mais alguma coisa antes de dormir?',
  'Treinei hoje. Posso comer mais tarde hoje?',
  'Treinei hoje. Posso comer algo a mais antes de dormir?',
  'Treinei hoje. Posso comer mais uma vez hoje?',
  'Treinei hoje. Posso comer mais vezes hoje?',
  'Treinei pesado, preciso tomar mais agua?',
  'Depois do treino devo comer proteína?',
  'Treinei hoje. Devo comer mais ptn?',
  'Treinei hoje. Posso comer mais frango hoje?',
  'Treinei hoje. Posso comer mais carne?',
  'Treinei hoje. Posso comer mais ovo?',
  'Treinei hoje. Posso comer mais fruta?',
  'Treinei hoje posso comer mais pizza',
  'Treinei hoje posso comer mais pao hoje',
  'Treinei hoje. Posso comer 100 g de arroz a mais?',
  'Treinei hoje. Posso comer um pão a mais?',
  'Treinei hoje. Posso comer uma barrinha a mais?',
  'Treinei hoje. Posso comer um hamburguer hoje?',
  'Treinei hoje, posso comer um brigadeiro?',
  'Treinei hoje, posso comer açaí?',
  'Malhei hoje, mereço um doce?',
  'Treinei hoje e estou morrendo de vontade de comer, posso comer mais?',
  'Treinei hoje e to sem energia nenhuma. Posso comer mais?',
  'O treino acelera meu bloco?',
  'Treinei hoje, isso ajuda no bloco?',
  'Treinei hoje. O treino conta no 7700?',
  'Treinei e gastei 322 kcal, isso entra no 7.700?',
  'O treino de hoje entra no meu saldo?',
  'O treino entra no meu balanço?',
  'Treinei ontem, posso comer mais hoje?',
  'Vou treinar amanhã, posso comer mais amanhã?',
  'Treinei hoje. Posso comer mais amanha?',
  'Treinei hoje. Posso comer a mais no fim de semana?',
  'Treinei hoje. Posso comer mais no sábado?',
  'Treinei hoje. Posso comer mais depois de amanha?',
  'Treinei anteontem, posso comer mais?',
  'Treinei a semana toda, posso comer mais hoje?',
  'Treinei hoje de manha. Posso comer mais a noite?',
  'Treinei hoje. Posso comer mais de noite?',
  'Treinei hoje. Posso comer mais na janta?',
  'Treinei hoje. Posso comer mais no almoço?',
  'Treinei hoje. Na manutenção posso comer mais?',
  'Treinei hoje. Posso comer mais sem sair da manutenção?',
  'Treinei hoje. Posso comer mais pra ganhar massa?',
  'Treinei hoje. Posso comer mais pra não perder massa?',
  'Treinei hoje. Posso comer mais sem engordar?',
  'Treinei hoje. Posso comer mais sem atrapalhar?',
  'Sei que treino não libera comida, mas hoje treinei 2h, posso comer mais?',
  'Eu sei que o treino não aumenta a meta, mas treinei muito hoje. Posso comer mais um pouco?',
  'Treinei hoje. Posso comer mais? Você já respondeu isso mas não entendi',
  'Não entendi. Treinei, posso comer mais?',
  'Como assim? Treinei hoje, posso comer mais?',
  'Treinei hoje, posso comer mais? Não entendi sua resposta anterior.',
  'Treinei hoje, registrei tudo, meu peso caiu. Posso comer mais?',
  'Hoje treinei, dormi mal, e o trabalho foi puxado. Posso comer mais?',
  'Treinei hoje. Minha esposa fez lasanha. Posso comer mais?',
  'Treinei hoje. Tenho um churrasco. Posso comer mais?',
  'Treinei hoje. Tenho um aniversário à noite. Posso comer mais?',
  'Treinei hoje e vou num rodízio. Posso comer mais?',
  'Treinei hoje e vou sair pra jantar fora. Posso comer mais?',
  'Treinei hoje. Hoje é meu dia livre. Posso comer mais?',
  'Treinei hoje, estou de TPM, posso comer mais?',
  'Posso treinar e comer mais tarde?',
  'Treinei hoje. Posso comer mais devagar?',
  'Treinei hoje. Posso comer mais cedo?',
  'Treinei hoje. Posso comer mais saudavel?',
  'Treinei hoje. Posso comer mais leve?',
  'Treinei hoje. Devo comer mais limpo?',
  'Treinei hoje. Posso comer menos?',
  'Treinei hoje. Posso comer mais ou menos o que comi ontem?',
  'Treinei hoje. Posso comer mais ou menos 500 kcal agora?',
  'Não vou treinar hoje. Posso comer mais?',
  'Treino só amanhã, posso comer mais hoje?',
  'Perdi o treino hoje, posso comer mais?',
  'Minha esposa treinou hoje, ela pode comer mais?',
  'Meu marido malhou e gastou 500 kcal. Pode comer mais?',
  'Treinei hoje. O relógio disse 800 kcal mas o app registrou 322. Posso comer mais?',
  'Meu relógio marcou 322 kcal no treino. Você pode corrigir? Posso comer mais?',
  'Na verdade gastei 500 kcal no treino e não 322. Posso comer mais?',
  'O treino de hoje foi de 322 kcal e não de 500 kcal. Posso comer mais?',
  'Vou treinar daqui a pouco, posso comer mais hoje?',
  'Quero treinar em jejum. Posso comer mais depois?',
  'Treinei hoje. Posso beber mais?',
  'Treinei hoje. Posso tomar um vinho?',
  'Treinei hoje. Posso comer mais sal?',
  'Treinei hoje. Posso comer mais besteira?',
  'Treinei hoje. Posso comer mais besteira hoje?',
  'Treinei hoje. Posso comer mais porcaria hoje?',
  'Treinei hoje, posso comer mais lixo hoje',
  'Treinei hoje. Posso comer um pouco mais de arroz?',
  'Treinei hoje. Posso comer um pouco a mais de arroz?',
  'Treinei hoje. Posso comer 322 kcal a mais de chocolate?',
  'Treinei hoje. Posso comer 322 kcal a mais em chocolate?',
  'Treinei hoje. Posso comer mais 322 kcal de pizza?',
  'Treinei hoje. Posso comer 200 kcal a mais de pão?',
  'Treinei hoje. Posso comer mais 2 fatias?',
  'Treinei hoje. Posso comer mais 1?',
  'Treinei hoje. Posso comer mais 100 g?',
  'Treinei hoje. Posso comer mais 300?',
  'Treinei e bati a meta de proteina. Posso comer mais?',
  'Treinei hoje. Já bati a meta. Posso comer mais?',
  'Treinei hoje e estourei a meta em 300 kcal. Posso comer mais?',
  'Treinei hoje. Ja comi tudo que podia. Posso comer mais?',
  'Treinei hoje. Ainda restam 200 kcal. Posso comer mais que isso?',
  'Treinei hoje. O app diz que restam 2.439 kcal. Posso comer mais?',
  'Treinei hoje. A tela mostra excedente de 200 kcal. Posso comer mais?',
  'Treinei hoje. O Dr. Roberto falou que posso comer mais?',
  'Treinei hoje. Meu médico mandou comer mais. Posso comer mais?',
  'Treinei hoje. Tenho consulta com o Dr Roberto. Posso comer mais?',
  'Treinei hoje. I can eat more?',
  'Entrené hoy. Puedo comer más?',
])

// What the first version of this table already kept away from the system.
const EARLIER_NEGATIVES = unique([
  // what the iPhone round asked and must keep reaching the model
  'Quanto de proteína ainda falta hoje?',
  'Qual foi meu balanço de ontem? Mostre consumido, meta, exercício e a conta',
  'Sugira um cardápio completo para hoje',
  'Mostre meu progresso recente.',
  // a specific food or nutrient "a mais"
  'Fiz musculação. Posso comer 30 g de whey a mais hoje?',
  'posso comer 30 g de whey a mais?',
  'Treinei pesado hoje. Preciso comer mais proteína pra compensar?',
  'Vou treinar agora. Posso comer uma banana a mais antes?',
  'Posso comer um chocolate a mais hoje?',
  'Treinei hoje, posso comer mais carboidrato?',
  'Treinei hoje. Posso comer mais uma fatia de pizza?',
  'Treinei hoje. Posso comer mais arroz hoje?',
  'Treinei hoje. Posso comer mais 2 ovos hoje?',
  // a meal, not the day
  'Treinei. Posso comer um pouco a mais no jantar?',
  'Treinei hoje. Posso comer 500 kcal no jantar?',
  'Treinei hoje. Posso comer mais agora ou espero o jantar?',
  'Treinei hoje. Posso comer mais tarde?',
  // the patient did not train
  'Não treinei hoje. Posso comer mais?',
  'Hoje fiquei sem treinar, posso comer mais?',
  'Não fui na academia. Posso comer mais hoje?',
  // "gastei" / "queimei" that is not exercise
  'Hoje gastei muito no mercado. Posso comer um pouco a mais no jantar?',
  'Gastei 50 reais no mercado. Posso comer mais hoje?',
  'Queimei o arroz. Posso comer mais?',
  // plan requests
  'Monte um plano de treino pra eu poder comer mais',
  'Treinei hoje. Gere uma dieta com mais calorias, posso comer mais?',
  'Treinei hoje, me sugere um lanche? Posso comer mais?',
  // meal registrations that mention training
  'Almocei 150 g de frango grelhado depois do treino',
  'Registra meu treino: musculação 47 min, 322 kcal',
  'Treinei e almocei arroz com frango. Posso comer mais 300 kcal?',
  'Comi 2 ovos depois da academia, posso comer mais?',
  // status questions
  'Registrei musculacao 47 min. Quanto ainda posso comer hoje?',
  'Treinei hoje, o que devo comer no pos-treino?',
  'Mostre exercício, conta e meta de hoje',
  'Quantas calorias eu queimei no treino?',
  'Treinei hoje. Quanto posso comer a mais?',
  'Como está meu dia? Treinei hoje.',
  // more than one question
  'Treinei hoje. Posso comer mais? E a proteína, como está?',
  'O treino aumenta minha meta? E o bloco?',
  'Treinei hoje. Posso comer mais? Isso atrapalha meu resultado?',
  'Meu personal disse que quem treina pode comer mais. É verdade?',
  // another meaning of "meta", "repor" and "compensar"
  'O treino aumenta minha meta de proteína?',
  'O treino de hoje entra na meta da semana?',
  'Posso compensar o treino hoje?',
  'Posso repor o treino amanhã?',
  'Bebi pouca água no treino, posso repor agora?',
  'Treinei muito, posso repor agora?',
  'O treino acelera o bloco?',
  'O treino conta como meta?',
  'Posso malhar e comer mais?',
  'A meta de proteína aumenta com o treino?',
  'Posso treinar depois de comer?',
  // how the patient feels
  'Treinei e fiquei tonto. Posso comer mais?',
  'Treinei hoje e estou com fome. Posso comer mais?',
  // statements, not questions
  'Treinei hoje e gastei 322 kcal.',
  'Preciso comer mais calorias hoje porque treinei.',
  // another day
  'Treinei ontem e gastei 500 kcal. Posso comer 500 kcal a mais hoje?',
  // no workout in the message
  'Posso comer 322 kcal a mais?',
  'Posso comer mais hoje?',
  // other language, empty, noise
  'Can I eat 322 kcal more because I trained?',
  'Sim',
  '',
  '   ',
])

// More of the same classes, written for the whitelist.
const MORE_NEGATIVES = unique([
  // a symptom in the same sentence as the workout
  'Treinei hoje e fiquei tonto, posso comer mais?',
  'Treinei hoje e estou com dor de cabeça, posso comer mais?',
  'Treinei e estou enjoada, posso comer mais?',
  'Treinei hoje e senti tontura, posso comer 322 kcal a mais?',
  'Treinei e desmaiei na academia, posso comer mais?',
  'Treinei hoje e estou com hipoglicemia, posso comer mais?',
  'Treinei hoje, sou diabético, posso comer mais?',
  'Treinei hoje e estou tremendo, posso comer mais?',
  'Treinei hoje com febre, posso comer mais?',
  'Treinei hoje e machuquei o joelho, posso comer mais?',
  'Treinei hoje e estou com muita fome, posso comer mais?',
  'Treinei hoje e não estou bem, posso comer mais?',
  'Treinei hoje e gastei 322 kcal, estou fraco, posso comer 322 kcal a mais?',
  // an open question
  'O que posso comer a mais?',
  'Treinei hoje, o que posso comer a mais?',
  'Treinei hoje e gastei 322 kcal. Quantas calorias posso comer a mais?',
  'Treinei hoje. Como faço pra comer mais?',
  'Treinei hoje. Quando posso comer mais?',
  'Treinei hoje. Por que não posso comer mais?',
  'Treinei hoje. Qual alimento posso comer a mais?',
  'Treinei hoje. Quanto a mais posso comer?',
  // reported speech
  'Treinei hoje. Minha nutricionista falou que posso comer 322 kcal a mais.',
  'Treinei hoje. O personal disse que posso comer mais, é verdade?',
  'Treinei hoje. Li na internet que posso comer mais.',
  'Treinei hoje. Dizem que posso comer mais.',
  'Treinei hoje e ouvi que posso comer as calorias do treino.',
  'Treinei hoje. Acho que posso comer mais, né?',
  'O Dr. Roberto disse que o treino aumenta minha meta.',
  // another person
  'Meu marido treinou hoje, ele pode comer mais?',
  'Minha filha treinou e gastou 300 kcal, ela pode comer 300 kcal a mais?',
  'Treinamos hoje, podemos comer mais?',
  'Minha mãe fez caminhada hoje. Ela pode comer mais?',
  'O treino do meu filho aumenta a meta dele?',
  'Meu amigo malhou hoje, pode comer mais?',
  'Treinei hoje. Minha esposa pode comer mais?',
  // did not train
  'Não treinei hoje, posso comer mais?',
  'Hoje não treinei. Posso comer mais?',
  'Não fiz musculação hoje, posso comer mais?',
  'Hoje eu não malhei, posso comer mais?',
  'Não consegui treinar hoje. Posso comer mais?',
  'Quase treinei hoje, posso comer mais?',
  'Nem treinei hoje, posso comer mais?',
  'Nunca treinei, posso comer mais?',
  'Treinei hoje? Posso comer mais?',
  // will train
  'Vou treinar hoje, posso comer mais?',
  'Vou malhar daqui a pouco. Posso comer mais?',
  'Amanhã vou treinar, posso comer mais hoje?',
  'Quando eu treinar posso comer mais?',
  'Estou indo treinar, posso comer mais?',
  'Treinarei hoje à noite. Posso comer mais?',
  'Ainda vou fazer musculação hoje, posso comer mais?',
  // another day
  'Treinei ontem, posso comer mais?',
  'Treinei ontem e gastei 322 kcal. Posso comer 322 kcal a mais?',
  'Treinei hoje. Posso comer mais amanhã?',
  'Treinei segunda e terça, posso comer mais?',
  'Treinei a semana inteira. Posso comer mais no domingo?',
  'Treinei hoje. Posso comer 322 kcal a mais amanhã?',
  'Semana passada treinei todo dia, posso comer mais?',
  'Treinei hoje. O treino aumenta minha meta de amanhã?',
  // rest day
  'Hoje é meu dia de descanso, posso comer mais?',
  'Hoje é folga do treino. Posso comer mais?',
  'Dia de descanso hoje, posso comer as calorias do treino de ontem?',
  'No dia de descanso a meta muda?',
  // a workout plan asked for
  'Treinei hoje. Monta um treino pra amanhã. Posso comer mais?',
  'Quero um plano de treino. Posso comer mais nos dias de treino?',
  'Gera um treino de costas e me diz se posso comer mais',
  'Treinei hoje, me passa um treino novo? Posso comer mais?',
  'Sugere um treino de 40 min. Posso comer mais hoje?',
  // a workout to delete or edit
  'Apaga meu treino de hoje, posso comer mais?',
  'Corrige o treino pra 500 kcal. Posso comer 500 kcal a mais?',
  'Treinei hoje e gastei 322 kcal, registra pra mim. Posso comer 322 kcal a mais?',
  'Edita o treino de hoje para 60 min. Posso comer mais?',
  'O treino de hoje está errado, gastei 400 kcal. Posso comer 400 kcal a mais?',
  'Tira o treino de ontem. Posso comer mais hoje?',
  // a food in the message
  'Treinei hoje. Posso comer mais uma banana?',
  'Treinei hoje e gastei 322 kcal. Posso comer 322 kcal a mais de arroz?',
  'Treinei hoje. Posso comer um pouco mais de frango?',
  'Treinei hoje. Adiciona 200 g de arroz, posso comer mais?',
  'Treinei hoje e comi uma pizza. Posso comer mais?',
  'Treinei hoje. Posso comer um doce a mais?',
  'Treinei hoje. Posso comer mais 2 ovos?',
  'Treinei hoje. Posso tomar um whey a mais?',
  'Treinei hoje 💪 posso comer mais 🍕?',
  // the inverse question: burning an excess by training
  'Passei 300 kcal da meta. Posso queimar isso treinando?',
  'Comi demais hoje, posso compensar no treino?',
  'Se eu treinar mais apago o excedente?',
  'Treinei hoje pra compensar o que comi ontem. Posso comer mais?',
  'Quanto preciso treinar pra queimar 500 kcal?',
  // the profile, not the day
  'Mudei meu treino pra 5 vezes por semana, minha meta aumenta?',
  'Agora treino todo dia. Isso aumenta minha meta?',
  'Voltei a treinar essa semana. Minha meta muda?',
  'Meu nível de atividade mudou, a meta muda?',
  'Passei a fazer musculação 6x por semana, o treino aumenta minha meta?',
  'Aumentei meu treino pra 6 dias, isso muda minha meta?',
  // the patient asks again or already knows the rule
  'Mas treinei hoje, posso comer mais?',
  'Sei que não, mas treinei hoje. Posso comer mais?',
  'Treinei hoje. Já me disse que não, posso comer mais?',
  'Não entendi, treinei hoje, posso comer mais?',
  'Treinei hoje, mas posso comer mais?',
  'Tá, mas treinei hoje e gastei 322 kcal. Posso comer 322 kcal a mais?',
  'De novo: treinei hoje, posso comer mais?',
  'Sei que o treino não aumenta a meta. O treino aumenta minha meta?',
  // a plan, a menu, a diet
  'Treinei hoje. Meu plano deixa comer mais?',
  'Treinei hoje. Ajusta meu cardápio, posso comer mais?',
  'Treinei hoje. Posso comer mais na dieta?',
  // a second request or a second question
  'Treinei hoje. Posso comer mais? Quanto falta de proteína?',
  'Treinei hoje, posso comer mais? Mostra meu dia.',
  'Treinei hoje e gastei 322 kcal. Posso comer 322 kcal a mais? E amanhã?',
  // a statement, no question
  'Treinei hoje e vou comer mais.',
  'Treinei hoje, então vou comer 322 kcal a mais.',
  'Treinei hoje.',
  'Posso comer mais?',
  // long, several subjects
  'Treinei musculação hoje e gastei 322 kcal, depois almocei arroz, feijão e frango, tomei 500 ml de água e ainda preciso jantar. Posso comer 322 kcal a mais?',
  'Oi Flow, treinei hoje, registrei o café, o almoço ficou de fora, meu peso subiu e o bloco não andou. Posso comer mais?',
])

describe('asksExerciseFoodQuestion — inside the grammar: the system answers', () => {
  it.each(MUST_MATCH)('answers: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(true)
  })
})

describe('asksExerciseFoodQuestion — direct questions outside the grammar, on purpose', () => {
  it.each(OUTSIDE_THE_GRAMMAR)('goes to the model: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })
})

describe('asksExerciseFoodQuestion — everything else goes to the model', () => {
  it.each(REVIEW_HIJACKED)('review 2026-10-04, hijacked before: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it.each(REVIEW_ROUND_2)('review round 2, answered by the system before: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it.each(ENDS_AS_STATEMENT)('ends as a statement: %j', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it('the final mark decides: every accepted message without "?" stops matching with "." or "!"', () => {
    for (const text of MUST_MATCH) {
      const bare = text.replace(/[?.!\s]+$/, '')
      if (bare.includes('?')) continue
      // No mark at the end (voice, fast typing): the question mark is optional.
      expect(asksExerciseFoodQuestion(bare)).toBe(true)
      expect(asksExerciseFoodQuestion(`${bare}?`)).toBe(true)
      for (const ending of ['.', '!', '...', '…', '. ', '!"', '.”', ',']) {
        expect(asksExerciseFoodQuestion(`${bare}${ending}`)).toBe(false)
      }
    }
  })

  it('a "?" anywhere keeps a message that ends in "." a question', () => {
    expect(
      asksExerciseFoodQuestion(
        'Posso comer 322 kcal a mais? Treinei musculação hoje e gastei 322 kcal.',
      ),
    ).toBe(true)
    expect(asksExerciseFoodQuestion('Posso comer mais? Treinei hoje!')).toBe(true)
  })

  it('no question form stands without the report of the workout', () => {
    // The same questions next to "Treinei hoje." are in MUST_MATCH.
    for (const question of [
      'O treino aumenta minha meta?',
      'O treino muda minha meta?',
      'A meta aumenta com o treino?',
      'Minha meta muda quando eu treino?',
      'Posso comer as calorias do treino?',
      'Posso comer as calorias que queimei no treino?',
      'Preciso repor as calorias do treino?',
      'Posso comer mais?',
      'Minha meta aumenta?',
    ]) {
      expect(asksExerciseFoodQuestion(question)).toBe(false)
      expect(asksExerciseFoodQuestion(`Bom dia! ${question}`)).toBe(false)
      expect(asksExerciseFoodQuestion(`Treinei hoje. ${question}`)).toBe(true)
    }
  })

  it.each(REVIEW_CORPUS)('review corpus: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it.each(EARLIER_NEGATIVES)('does not answer: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it.each(MORE_NEGATIVES)('does not answer: %s', (text) => {
    expect(asksExerciseFoodQuestion(text)).toBe(false)
  })

  it('one word outside the grammar turns every accepted message into a miss', () => {
    // The whitelist property itself: nothing may be left over, wherever it is.
    for (const text of MUST_MATCH) {
      const bare = text.replace(/[?.!\s]+$/, '')
      for (const extra of ['mas', 'ontem', 'pizza', 'tonto', 'não']) {
        expect(asksExerciseFoodQuestion(`${extra} ${text}`)).toBe(false)
        expect(asksExerciseFoodQuestion(`${bare} ${extra}?`)).toBe(false)
      }
    }
  })

  it('a message over 160 characters is never answered by the system, even inside the grammar', () => {
    const short = `${'Oi, '.repeat(5)}treinei hoje, posso comer mais?`
    const long = `${'Oi, '.repeat(45)}treinei hoje, posso comer mais?`

    expect(asksExerciseFoodQuestion(short)).toBe(true)
    expect(long.length).toBeGreaterThan(160)
    expect(asksExerciseFoodQuestion(long)).toBe(false)
    expect(
      asksExerciseFoodQuestion(
        `${'Treinei bastante hoje na academia. '.repeat(8)}Posso comer mais?`,
      ),
    ).toBe(false)
  })

  it('the tables keep the size the audit asked for and never overlap', () => {
    const negatives = [
      ...OUTSIDE_THE_GRAMMAR,
      ...REVIEW_HIJACKED,
      ...REVIEW_ROUND_2,
      ...ENDS_AS_STATEMENT,
      ...REVIEW_CORPUS,
      ...EARLIER_NEGATIVES,
      ...MORE_NEGATIVES,
    ]

    // The report phrase (two spellings) + at least 40 other direct forms.
    expect(MUST_MATCH.length).toBeGreaterThanOrEqual(42)
    expect(MORE_NEGATIVES.length).toBeGreaterThanOrEqual(60)
    expect(negatives.filter((text) => MUST_MATCH.includes(text))).toEqual([])
  })
})

describe('renderExerciseFoodAnswer', () => {
  // Said whenever the day has no workout stored, in every protocol.
  const NO_WORKOUT =
    'Não encontrei treino registrado hoje. Quando você registrar o treino no app, o gasto fica à parte e não entra no que resta para comida.'
  // Added when the patient typed a burn that is not the stored one.
  const STORED_VALUE_NOTE = 'Esse é o valor registrado no app.'

  // Day row of the report: target 2980, consumed 541, exercise 322, ganho_massa.
  const REPORT_DAY = {
    caloriesTarget: 2980,
    caloriesConsumed: 541,
    exerciseCalories: 322,
    protocol: 'ganho_massa',
  }

  const variants: Array<[string, Parameters<typeof renderExerciseFoodAnswer>[0], string]> = [
    [
      'the report: food left (ganho_massa)',
      REPORT_DAY,
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
    [
      'the same day before the second lunch (consumed 302)',
      { ...REPORT_DAY, caloriesConsumed: 302 },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 302 kcal, então restam 2.678 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
    [
      'manutenção: no block wording',
      { ...REPORT_DAY, protocol: 'manutencao' },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
    [
      'recomposição: block wording',
      {
        caloriesTarget: 1843,
        caloriesConsumed: 1407,
        exerciseCalories: 467,
        protocol: 'recomposicao',
      },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.407 kcal, então restam 436 kcal para comer hoje (meta menos consumido). As 467 kcal de treino registradas hoje aceleram o bloco de 7.700 kcal, mas não entram no que resta para comida.',
    ],
    [
      'target met exactly',
      { ...REPORT_DAY, caloriesConsumed: 2980 },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 2.980 kcal, então você já bateu a meta de hoje. As 322 kcal de treino registradas hoje ficam à parte e não liberam mais comida.',
    ],
    [
      'over the target: the workout does not erase the excess',
      { ...REPORT_DAY, caloriesConsumed: 3200 },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 3.200 kcal, então você está 220 kcal acima da meta (consumido menos meta). As 322 kcal de treino registradas hoje ficam à parte e não apagam esse excedente.',
    ],
    [
      'over the target in recomposição',
      {
        caloriesTarget: 1843,
        caloriesConsumed: 2000,
        exerciseCalories: 565,
        protocol: 'recomposicao',
      },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 2.000 kcal, então você está 157 kcal acima da meta (consumido menos meta). As 565 kcal de treino registradas hoje aceleram o bloco de 7.700 kcal, mas não apagam esse excedente.',
    ],
    [
      'exercise 0 in the database (the patient says he trained, nothing is stored)',
      { ...REPORT_DAY, exerciseCalories: 0 },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    ],
    [
      // Review 2026-10-04: this said "O gasto do treino acelera o bloco de
      // 7.700 kcal" with nothing stored — the block receives nothing.
      'exercise 0 in recomposição: no claim about the block',
      {
        caloriesTarget: 1843,
        caloriesConsumed: 1301,
        exerciseCalories: 0,
        protocol: 'recomposicao',
      },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.301 kcal, então restam 542 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    ],
    [
      'exercise 0 with the target met exactly: the same sentence',
      { ...REPORT_DAY, caloriesConsumed: 2980, exerciseCalories: 0 },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 2.980 kcal, então você já bateu a meta de hoje. ${NO_WORKOUT}`,
    ],
    [
      'exercise 0 over the target in recomposição: the same sentence',
      {
        caloriesTarget: 1843,
        caloriesConsumed: 2000,
        exerciseCalories: 0,
        protocol: 'recomposicao',
      },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 2.000 kcal, então você está 157 kcal acima da meta (consumido menos meta). ${NO_WORKOUT}`,
    ],
    [
      'a negative exercise value is read as no workout stored',
      { ...REPORT_DAY, exerciseCalories: -50 },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    ],
    [
      'no day row yet (nothing consumed, no exercise stored)',
      { caloriesTarget: 2980, caloriesConsumed: 0, exerciseCalories: 0, protocol: 'ganho_massa' },
      `O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê ainda não tem consumo lançado hoje, então restam 2.980 kcal para comer hoje (meta menos consumido). ${NO_WORKOUT}`,
    ],
    [
      'no target, with exercise stored',
      { caloriesTarget: null, caloriesConsumed: 541, exerciseCalories: 322, protocol: null },
      'O treino não aumenta o que você pode comer hoje: a meta do dia não muda com exercício.\n\nAs 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
    [
      'no target and no exercise stored',
      { caloriesTarget: null, caloriesConsumed: 0, exerciseCalories: 0, protocol: null },
      `O treino não aumenta o que você pode comer hoje: a meta do dia não muda com exercício.\n\n${NO_WORKOUT}`,
    ],
    [
      // Review 2026-10-04: this said "restam 1 kcal" and "As 1 kcal do treino ficam".
      'singular: 1 kcal left and 1 kcal of exercise',
      { ...REPORT_DAY, caloriesConsumed: 2979, exerciseCalories: 1 },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 2.979 kcal, então resta 1 kcal para comer hoje (meta menos consumido). A 1 kcal de treino registrada hoje fica à parte e não entra no que resta para comida.',
    ],
    [
      'singular in recomposição: 1 kcal of exercise, 1 kcal over',
      {
        caloriesTarget: 1843,
        caloriesConsumed: 1844,
        exerciseCalories: 1,
        protocol: 'recomposicao',
      },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1.843 kcal.\n\nVocê consumiu 1.844 kcal, então você está 1 kcal acima da meta (consumido menos meta). A 1 kcal de treino registrada hoje acelera o bloco de 7.700 kcal, mas não apaga esse excedente.',
    ],
    [
      'singular with the target met exactly',
      { ...REPORT_DAY, caloriesConsumed: 2980, exerciseCalories: 1 },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 2.980 kcal, então você já bateu a meta de hoje. A 1 kcal de treino registrada hoje fica à parte e não libera mais comida.',
    ],
    [
      'singular: 1 kcal left with nothing consumed',
      { caloriesTarget: 1, caloriesConsumed: 0, exerciseCalories: 322, protocol: 'manutencao' },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 1 kcal.\n\nVocê ainda não tem consumo lançado hoje, então resta 1 kcal para comer hoje (meta menos consumido). As 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
    [
      'thousands in every number',
      {
        caloriesTarget: 3361,
        caloriesConsumed: 1250,
        exerciseCalories: 1200,
        protocol: 'ganho_massa',
      },
      'O treino não aumenta o que você pode comer hoje: sua meta continua em 3.361 kcal.\n\nVocê consumiu 1.250 kcal, então restam 2.111 kcal para comer hoje (meta menos consumido). As 1.200 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
    ],
  ]

  it.each(variants)('%s', (_name, day, expected) => {
    expect(renderExerciseFoodAnswer(day)).toBe(expected)
  })

  it('a target of 0 or NaN is treated as no target (no made-up number)', () => {
    for (const caloriesTarget of [0, Number.NaN]) {
      expect(renderExerciseFoodAnswer({ ...REPORT_DAY, caloriesTarget })).toBe(
        'O treino não aumenta o que você pode comer hoje: a meta do dia não muda com exercício.\n\nAs 322 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida.',
      )
    }
  })

  it('the report answer never carries the numbers or the claims of the wrong reply', () => {
    const text = renderExerciseFoodAnswer(REPORT_DAY)

    // 2.761 = net balance; 3.302 = target + exercise; 2.761 was never "left".
    for (const wrong of [
      '2.761',
      '2761',
      '3.302',
      '3302',
      'já considera',
      'espaço pra comer',
      'Sim',
    ]) {
      expect(text).not.toContain(wrong)
    }
  })

  it('the block is named only in recomposição, and only when a workout is stored', () => {
    for (const [, day, expected] of variants) {
      if (day.protocol === 'recomposicao' && day.exerciseCalories > 0) {
        expect(expected).toContain('o bloco de 7.700 kcal')
      } else {
        expect(expected).not.toContain('7.700')
        expect(expected).not.toContain('bloco')
      }
    }
  })

  it('no workout stored: never speaks as if there were one', () => {
    for (const [, day] of variants) {
      const text = renderExerciseFoodAnswer(day)
      if (day.exerciseCalories > 0) {
        expect(text).not.toContain('Não encontrei treino')
        expect(text).toMatch(/kcal de treino registradas? hoje (?:fica|ficam|acelera|aceleram) /)
      } else {
        expect(text.endsWith(NO_WORKOUT)).toBe(true)
        expect(text).not.toMatch(/acelera|kcal de treino|kcal do treino|O gasto do treino/)
      }
    }
  })

  it('every variant opens with the sentence the pipeline recognises', () => {
    for (const [, day] of variants) {
      expect(renderExerciseFoodAnswer(day).startsWith(`${EXERCISE_FOOD_ANSWER_OPENING}: `)).toBe(
        true,
      )
    }
  })

  it('every variant is plain text and trips no block guard', () => {
    for (const [, day] of variants) {
      const text = renderExerciseFoodAnswer(day)

      expect(text).not.toMatch(/[*`]|_\(/)
      expect(text).not.toMatch(/^Não\b/)
      expect(detectPrematureBlockCompletion(text)).toBe(false)
    }
  })

  it('the write guard: "registrad…" is the only write word, and it is about what the app already holds', () => {
    const judge = (content: string) =>
      detectFakeWrite({
        content,
        patientText: REPORT_PHRASE,
        registrationToolCalled: false,
        prescriptionToolCalled: false,
        skipToolCalled: false,
      }).isFake

    // The answer says "treino registrado" / "de treino registradas hoje" /
    // "valor registrado no app" (wording asked by the audit and the review).
    // The write guard judges only what the MODEL writes in the current turn;
    // this text is returned before any model call, and the golden asserts no
    // llm.fake_write_* event. Without those fixed places nothing claims a write.
    for (const [, day] of variants) {
      for (const stated of [null, 999]) {
        const text = renderExerciseFoodAnswer(day, stated)
        const withoutStoredWording = text
          .replace(NO_WORKOUT, '')
          .replace(/ de treino registradas? hoje/, ' de treino')
          .replace(` ${STORED_VALUE_NOTE}`, '')

        expect(withoutStoredWording).not.toMatch(/registrad/)
        expect(judge(withoutStoredWording)).toBe(false)
      }
    }
  })

  // Review 2026-10-04, round 2: day with 150 kcal stored (a morning walk),
  // message "…gastei 400 kcal. Posso comer 400 kcal a mais?" → the answer said
  // "As 150 kcal do treino" with no hint of whose number it was.
  describe('the patient typed a burn that is not the stored one', () => {
    const WALK_DAY = { ...REPORT_DAY, exerciseCalories: 150 }

    it('says the number is the stored one, and nothing about the workout he cited', () => {
      const text = renderExerciseFoodAnswer(WALK_DAY, 400)

      expect(text).toBe(
        'O treino não aumenta o que você pode comer hoje: sua meta continua em 2.980 kcal.\n\nVocê consumiu 541 kcal, então restam 2.439 kcal para comer hoje (meta menos consumido). As 150 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida. Esse é o valor registrado no app.',
      )
      expect(text).not.toContain('400')
      expect(text).not.toMatch(/não está registrado|não encontrei|faltando/i)
    })

    it.each([
      ['the same number', REPORT_DAY, 322],
      ['the same number after rounding', REPORT_DAY, 322.4],
      ['no number typed', REPORT_DAY, null],
      ['not a number', REPORT_DAY, Number.NaN],
    ])('no note for %s', (_name, day, stated) => {
      expect(renderExerciseFoodAnswer(day, stated)).toBe(renderExerciseFoodAnswer(day))
      expect(renderExerciseFoodAnswer(day, stated)).not.toContain(STORED_VALUE_NOTE)
    })

    it('recomposição, over the target and singular keep their sentence and gain the note', () => {
      expect(
        renderExerciseFoodAnswer(
          {
            caloriesTarget: 1843,
            caloriesConsumed: 1407,
            exerciseCalories: 467,
            protocol: 'recomposicao',
          },
          300,
        ).endsWith(
          'As 467 kcal de treino registradas hoje aceleram o bloco de 7.700 kcal, mas não entram no que resta para comida. Esse é o valor registrado no app.',
        ),
      ).toBe(true)
      expect(
        renderExerciseFoodAnswer({ ...REPORT_DAY, caloriesConsumed: 3200 }, 500).endsWith(
          'As 322 kcal de treino registradas hoje ficam à parte e não apagam esse excedente. Esse é o valor registrado no app.',
        ),
      ).toBe(true)
      expect(
        renderExerciseFoodAnswer({ ...REPORT_DAY, exerciseCalories: 1 }, 322).endsWith(
          'A 1 kcal de treino registrada hoje fica à parte e não entra no que resta para comida. Esse é o valor registrado no app.',
        ),
      ).toBe(true)
      expect(
        renderExerciseFoodAnswer(
          { caloriesTarget: null, caloriesConsumed: 541, exerciseCalories: 150, protocol: null },
          400,
        ),
      ).toBe(
        'O treino não aumenta o que você pode comer hoje: a meta do dia não muda com exercício.\n\nAs 150 kcal de treino registradas hoje ficam à parte e não entram no que resta para comida. Esse é o valor registrado no app.',
      )
    })

    it('nothing stored: the no-workout sentence stands alone, with no note', () => {
      const text = renderExerciseFoodAnswer({ ...REPORT_DAY, exerciseCalories: 0 }, 322)

      expect(text.endsWith(NO_WORKOUT)).toBe(true)
      expect(text).not.toContain(STORED_VALUE_NOTE)
      expect(text).not.toContain('322')
    })
  })
})

describe('statedWorkoutCalories', () => {
  it.each([
    [REPORT_PHRASE, 322],
    ['Treinei musculação e gastei 400 kcal. Posso comer 400 kcal a mais?', 400],
    ['Pedalei 3 horas e gastei 1.200 kcal. Posso comer 1.200 kcal a mais?', 1200],
    ['Malhei hoje e queimei umas 300 calorias, posso comer mais?', 300],
    ['Queimei 500 calorias na esteira, posso comer 500 calorias a mais?', 500],
    ['treinei hj e gastei 322kcal posso comer 322kcal a mais', 322],
    // the number asked for is not a burn
    ['Treinei hoje. Posso comer 322 kcal a mais?', null],
    ['Treinei hoje, posso comer mais?', null],
    ['Corri 10 km hoje, posso comer mais?', null],
    ['', null],
  ])('%j → %s', (text, expected) => {
    expect(statedWorkoutCalories(text)).toBe(expected)
  })
})

describe('lastReplyIsSameAnswer', () => {
  const day = {
    caloriesTarget: 2980,
    caloriesConsumed: 541,
    exerciseCalories: 322,
    protocol: 'ganho_massa',
  }
  const answer = renderExerciseFoodAnswer(day)

  it('true only when the last thing Flow said is this very text', () => {
    expect(
      lastReplyIsSameAnswer(
        [
          { role: 'user', content: REPORT_PHRASE },
          { role: 'assistant', content: answer },
        ],
        answer,
      ),
    ).toBe(true)
    // A user turn after it does not change what Flow said last.
    expect(
      lastReplyIsSameAnswer(
        [
          { role: 'assistant', content: 'Bom dia!' },
          { role: 'assistant', content: answer },
          { role: 'user', content: 'ok' },
        ],
        answer,
      ),
    ).toBe(true)
    // Stored or rendered with spaces around: still the same text.
    expect(
      lastReplyIsSameAnswer([{ role: 'assistant', content: `${answer}\n` }], ` ${answer}`),
    ).toBe(true)
  })

  it('false when the previous system answer has other numbers or is to another day state', () => {
    // Review 2026-10-04, round 2: a prefix test sent the report phrase to the
    // model for the rest of the day after ONE system answer.
    const variants = [
      renderExerciseFoodAnswer({ ...day, caloriesConsumed: 302 }),
      renderExerciseFoodAnswer({ ...day, caloriesConsumed: 2980 }),
      renderExerciseFoodAnswer({ ...day, caloriesConsumed: 3200 }),
      renderExerciseFoodAnswer({ ...day, exerciseCalories: 0 }),
      renderExerciseFoodAnswer({ ...day, exerciseCalories: 150 }),
      renderExerciseFoodAnswer({ ...day, caloriesTarget: null }),
      renderExerciseFoodAnswer({ ...day, protocol: 'recomposicao' }),
      renderExerciseFoodAnswer({ ...day, exerciseCalories: 150 }, 400),
    ]
    for (const previous of variants) {
      expect(previous.startsWith(EXERCISE_FOOD_ANSWER_OPENING)).toBe(true)
      expect(previous).not.toBe(answer)
      expect(lastReplyIsSameAnswer([{ role: 'assistant', content: previous }], answer)).toBe(false)
    }
    // A longer or shorter text that only shares the beginning.
    expect(
      lastReplyIsSameAnswer([{ role: 'assistant', content: `${answer} Bons treinos!` }], answer),
    ).toBe(false)
    expect(
      lastReplyIsSameAnswer([{ role: 'assistant', content: answer.slice(0, -1) }], answer),
    ).toBe(false)
  })

  it('false when Flow said something else after it, or never said it', () => {
    expect(lastReplyIsSameAnswer([], answer)).toBe(false)
    expect(lastReplyIsSameAnswer([{ role: 'user', content: REPORT_PHRASE }], answer)).toBe(false)
    expect(
      lastReplyIsSameAnswer(
        [
          { role: 'assistant', content: answer },
          { role: 'user', content: 'Mostre meu progresso recente.' },
          { role: 'assistant', content: 'Hoje: 541 kcal consumidas.' },
        ],
        answer,
      ),
    ).toBe(false)
    // The patient quoting the sentence is not Flow saying it.
    expect(lastReplyIsSameAnswer([{ role: 'user', content: answer }], answer)).toBe(false)
  })

  it('false for the identical answer of a previous day (the history loader dates it)', () => {
    expect(
      lastReplyIsSameAnswer(
        [
          {
            role: 'assistant',
            content: `[Mensagem de 03/10/2026, dia anterior — números do dia e horário citados nela não valem para hoje]\n${answer}`,
          },
        ],
        answer,
      ),
    ).toBe(false)
  })
})
