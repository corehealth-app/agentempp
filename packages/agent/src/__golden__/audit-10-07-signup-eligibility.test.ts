/**
 * Operative update 2026-10-25: approved final.answers n9/n39 supersedes the
 * historical BF-only gain exception. The exact BF15 / BMI26 fixture below
 * now closes gain and retains recomp/maintenance choice. This is the APP
 * signup helper, not a change to the legacy WhatsApp resolveProtocol.
 * Remaining n10/no-plan declarations below are historical open integration
 * gaps, not a claim that this composition-only golden implements n10.
 *
 * Audit 2026-10-07 — rule E: who is placed in recomposição at sign-up without
 * being asked, and who chooses among the three objectives. Rule, table and
 * pendencies: docs/CALCULO-MPP.md §10. Code: `decideSignupEligibility`,
 * packages/core/src/protocol-eligibility.ts.
 *
 * WHO CALLS THE FUNCTION. Since the server stages of the same audit, two
 * places, through one shared decision that rounds the body values to what the
 * profile stores: the sign-up eligibility check of the app (POST
 * /onboarding/eligibility, doc §10l), which answers and writes nothing, and
 * the completion of the sign-up (POST /onboarding, doc §10o), which on a FIRST
 * completion refuses an objective the check does not mark available. An
 * account that already has a completion time is never checked. No screen
 * changed. This file pins the pure function; the refusal is pinned through
 * the route in apps/admin/src/app/api/mobile/v1/onboarding/route.test.ts.
 *
 * THE RULE, as the client (Dr. Roberto) wrote it — it is NOT a new decision:
 *   Rule "Regra de Decisão Automática de Protocolo — Quando NÃO perguntar ao
 *     usuário" (in the list of active rules of 01/06/2026): "O agente NÃO deve
 *     perguntar preferência de protocolo quando: • BF ≥ 20% (homens) • BF ≥ 28%
 *     (mulheres) • IMC ≥ 25 (quando BF não disponível) / Nessas condições, o
 *     agente deve conduzir automaticamente para o protocolo de Recomposição
 *     Corporal, sem oferecer opção de escolha." / "O agente DEVE perguntar
 *     preferência APENAS quando: • BF < 20% (homens) ou < 28% (mulheres) • IMC
 *     < 25 (quando BF não disponível) … Nesse caso, apresentar as 3 opções".
 *   Rule "Ganho de massa muscular - Critérios de entrada" (the same text in
 *     the table of 02/02/2026 and in the list of 01/06/2026): "Composição
 *     corporal inicial adequada (pelo menos um): BF ≤ 19% (homens) / BF ≤ 27%
 *     (mulheres) / IMC ≤ 24 com aparência funcional adequada / Compromisso
 *     comportamental mínimo (todos obrigatórios): musculação ≥ 3x por semana".
 *   Rule "Decisão de objetivo - critérios internos antes de deixar o usuário
 *     decidir": 3.1 (the same three cuts), 3.2 ("só entra em ganho se cumprir
 *     todos") and 3.3 (manutenção: "já se encontra em faixa saudável").
 *   01/02/2026 10:19 (texto): "o IMC de 25 entra mesmo na recomposiçõa
 *     corporal".
 *   25/03/2026 19:42–19:43 (texto): "Acho q aqui poderia retirar esse menor ou
 *     igual do 24 e deixar só menor"; "Isso, menor q 25"; "Sem o igual"; "Q aí
 *     o 25 não estaria na faixa da normalidade". 19:43 (áudio): "No que tá aí
 *     menor = 24 aí você tira o igual … menor que 25 na verdade … incluiria o
 *     24 e não o 25 … o 25 estaria fora da faixa da normalidade".
 *   28/12/2025 14:07 (áudio): "ele tem que tá fazendo pelo [menos] 3 vezes por
 *     semana de musculação". 16:02 (áudio): within the normal range the person
 *     may enter manutenção or ganho de massa, or choose recomposição.
 *   15/05/2026 07:24 (texto): a person "dentro dos limites da normalidade pra
 *     IMC e gordura corporal" was not allowed to choose "entre os 3 possiveis".
 *   THE REAL EPISODE this rule exists to fix — list of active rules of
 *     01/06/2026, block "CHECKPOINT INVIOLÁVEL APÓS food_organization
 *     (2026-05-15)", about 14–15/05/2026: "usuárias dentro da faixa saudável
 *     (… BF 25%, … IMC 24,9) foram conduzidas pra recomposição sem a escolha
 *     que a regra exige" (names left out here). Both are cases below.
 * Dito pelo cliente nessas datas; implementado em 2026-10-07 a pedido do
 * Eduardo; confirmação do cliente pendente.
 *
 * CONTRADICTION, written text × later audio (both kept in the doc): the entry
 * criterion of ganho de massa still reads "IMC ≤ 24" (01/06/2026 included);
 * the audio of 25/03/2026 19:43 says "menor que 25". Implemented: the later
 * statement. Without body fat, 79,38 kg / 180 cm (BMI 24,5) with 3 sessions
 * has ganho de massa available; the written text would block it.
 * That evening was about the range of who CHOOSES (19:16, áudio: whether 25 is
 * inside "a faixa da normalidade pra poder escolher o protocolo"; 19:42:59,
 * texto: "a opção de manutenção pro 25"). Applying the "menor que 25" to the
 * ENTRY criterion of ganho de massa is OUR READING; the client's confirmation
 * is pending (doc §10c, §10k-1).
 *
 * NUMBERS — no name, weight or height of a patient. Weights and heights are
 * chosen to land on the BMI named in each case; body fat and sessions are the
 * client's cuts (19 / 20 / 27 / 28, BMI 25,0, 2 and 3 sessions) and their
 * neighbours. Two numbers come from the real episode as the list of 01/06/2026
 * records it — body fat 25% and BMI 24,9: the weight, the height and the
 * strength training of those two people are NOT in the documents and are
 * chosen here (said in each case). The profile of 170 cm, 65 kg, 25% and 3
 * sessions is the synthetic draft the app's own tests preload
 * (DemoOnboardingRepository.swift). The three `calc.*` rows are the ones of
 * staging as recorded on 2026-10-04 in audit-10-04-goal-ladder-floors.test.ts;
 * NO database was read in this stage.
 *
 * `resolveProtocol` (the legacy path, still behind the "Decisão automática"
 * context line) is not touched. The last block pins where the two differ.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same lines in docs/CALCULO-MPP.md §10j):
 *
 * > RC E — cenário cadastro pelo app publicado (a etapa do objetivo oferece os três objetivos e não chama a conferência) variante uso da conferência pela tela, com o aviso, os motivos e só os objetivos disponíveis NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   O servidor já responde a conferência (§10l) e já recusa na gravação (§10o). Falta a tela.
 * > RC E — cenário versão do app anterior à etapa do app concluindo o cadastro com objetivo fora da regra variante explicação do motivo na tela e volta à etapa do objetivo (ela mostra só "Revise os dados informados.") NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   O servidor responde 422 onboarding_objective_not_eligible. Publicar a recusa junto com a versão do app que chama a conferência.
 *   Essa versão reenvia com a mesma chave de idempotência depois da recusa; o servidor aceita, porque a recusa é decidida antes da reserva da chave e não deixa registro (travado no teste da rota com o cenário exato: 422, 422, conclui).
 * > RC E — cenário conta antiga marcada como concluída sem data de conclusão que refaz o cadastro pelo app variante manter o protocolo antigo sem conferência NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   A função SQL já a trata como primeira conclusão (regrava o protocolo); a conferência segue a função SQL (travado no teste da rota). A contagem de produção não foi feita: conferir antes de publicar.
 * > RC E — cenário primeira conclusão e novo aceite de termos contra a função SQL real do Postgres variante teste com o banco real (os testes usam um banco em memória que reproduz os dois ramos da função; nenhum banco foi lido nem gravado) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário recusa do objetivo seguida de novo envio com a mesma chave de idempotência contra as funções reais do registro de idempotência do Postgres variante teste com o banco real (a migration 20260720130537 foi lida, não executada; os testes usam um registro em memória que a segue) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário conta que passou pelo reset (perfil vazio e marcada como não concluída, com a data de conclusão mantida) refazendo o cadastro pelo app variante concluir o cadastro de novo, com a conferência do objetivo NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Defeito anterior a esta mudança e igual depois dela: por ter data, a conta não é conferida e a função SQL responde 409 onboarding_already_completed (travado como está no teste da rota).
 * > RC E — cenário cadastro de pessoa com peso muito baixo (desnutrição) variante bloqueio da perda de gordura e condução ao ganho de massa (o número do limite não existe em nenhum documento do cliente) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   A função não faz nada especial: 45 kg / 180 cm (IMC 13,9) sem gordura escolhe entre os três (travado abaixo). Redeclara a pendência R4 de 04/10 (§8c).
 * > RC E — cenário cadastro com gordura informada de até 10% escolhendo recomposição variante piso de redução aplicado na entrada, e piso separado para mulher NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Homem com 8% e mulher com 10% escolhem entre os três (travado abaixo).
 * > RC E — cenário ganho de massa sem gordura informada variante "aparência funcional adequada" (avaliação por fotos, que o cadastro do app não tem) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário ganho de massa sem gordura informada com IMC acima de 24 e abaixo de 25 variante barrar o ganho pelo texto escrito "IMC ≤ 24" (critério de entrada, ainda na lista de 01/06/2026) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Implementada a fala posterior (áudio de 25/03/2026 19:43, "menor que 25").
 * > RC E — cenário gordura informada entre os cortes (homem acima de 19% e abaixo de 20%; mulher acima de 27% e abaixo de 28%) variante liberar o ganho de massa pelo IMC ("pelo menos um" do critério de entrada) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Implementado: escolhe entre recomposição e manutenção, ganho barrado por composição. Homem 19,5% com IMC 22: barrado; o mesmo corpo sem gordura informada: liberado (travado abaixo).
 * > RC E — cenário gordura dentro do critério com IMC acima do corte (homem 15% e IMC 26) variante exigir também o IMC para o ganho de massa ("cumprir todos", regra 3.2) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário pessoa dentro da faixa barrada no ganho de massa variante condução direta à recomposição, sem a opção de manutenção (regra 8.2 e frase de bloqueio 3.4.1) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário sono abaixo de 6h30 ou alimentação não organizada variante barrar o ganho de massa por esses dois critérios (manual de 27/12/2025; regra de coleta de dados da lista de 01/06/2026) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   A função não recebe sono nem alimentação (travado abaixo contra a conta antiga).
 * > RC E — cenário fase de ganho de massa em andamento variante bloquear ou pausar a fase pelos quatro critérios da regra "Ganho de massa muscular - Critérios de bloqueio do protocolo" ("BF acima dos limites de entrada", "ausência de progressão no treino", "alimentação inconsistente", "histórico recente de perda de controle alimentar") NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Regra ATIVA (lista de 01/06/2026). Esta função só decide a entrada no cadastro e não recebe progressão de treino nem histórico alimentar.
 * > RC E — cenário gordura digitada pela pessoa (sem fotos e sem medida conferida) variante tratar a gordura digitada como não disponível e decidir pelo IMC NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário tabela de referência gordura × IMC da regra de decisão de objetivo (homem "Normal / Saudável" com IMC 23–26) variante usar as faixas da tabela como corte NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário linha "Decisão automática" do contexto do Flow e do WhatsApp (resolveProtocol, ainda com sono e alimentação) variante mesma decisão do cadastro novo NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário IMC de 25,0 exato no caminho antigo (64 kg / 1,60 m dá 24,999999999999996; resolveProtocol compara sem tolerância) variante correção da conta antiga NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário cortes em execução (linhas calc.bf_limits, calc.imc_limit_recomp e calc.training_min de global_config) variante leitura dos valores nos bancos de teste e de produção NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC E — cenário valor possível de calcular mas implausível (altura digitada em metros, musculação fracionária ou acima de 7) variante faixa de plausibilidade dentro da função NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *   Fica no contrato do cadastro (100 a 250 cm, 30 a 300 kg, 3 a 60%, inteiro de 0 a 7).
 * > RC E — cenário contas que já concluíram o cadastro com objetivo fora desta regra variante conferir ou mover essas contas NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *
 * > RC E — cenário app fechado na tela da mensagem de entrada variante mensagem mostrada de novo na abertura seguinte (só volta a ser lida em Perfil, na E6) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *
 * > RC E — cenário pessoa definida em recomposição que pede ganho de massa variante conversa de bloqueio (na tela, a frase fica num detalhe que ela abre) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 *
 * Closed by the server stages of the same audit, and so no longer in the list
 * (doc §10j): the wording and the translation of the texts shown for each
 * result (packages/core/src/protocol-messages.ts; their approval is in §10n),
 * the value with more than two decimal places (the eligibility check rounds as
 * the database stores before calling this function, §10l), and the refusal,
 * at the recording, of an objective outside the rule (§10o).
 */

import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  type CalcConfig,
  calcIMC,
  DEFAULT_CALC_CONFIG,
  decideSignupEligibility,
  resolveProtocol,
  SIGNUP_IMC_ROUNDING_TOLERANCE,
  type SignupBlockReason,
  type SignupEligibilityBasis,
  type SignupEligibilityInput,
  type UserMetrics,
  type UserProfile,
} from '@mpp/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from '../calc-config-loader.js'

type ConfigRow = { key: string; value: unknown }

/**
 * `public.global_config` of staging, the three rows this rule reads, as
 * recorded on 2026-10-04 (audit-10-04-goal-ladder-floors.test.ts).
 */
const STAGING_CALC_ROWS: ConfigRow[] = [
  {
    key: 'calc.bf_limits',
    value: { feminino: { gain: 27, recomp: 28 }, masculino: { gain: 19, recomp: 20 } },
  },
  { key: 'calc.imc_limit_recomp', value: 25 },
  { key: 'calc.training_min', value: 3 },
]

/** The one statement the calc-config loader sends. Anything else fails. */
function configClient(rows: ConfigRow[]) {
  return {
    from(table: string) {
      if (table !== 'global_config') throw new Error(`unexpected table ${table}`)
      return {
        select: () => ({
          like: async (column: string, pattern: string) => {
            if (column !== 'key' || pattern !== 'calc.%') {
              throw new Error(`unexpected global_config filter ${column} like ${pattern}`)
            }
            return { data: rows, error: null }
          },
        }),
      }
    },
  }
}

function replaceRow(key: string, value: unknown): ConfigRow[] {
  return STAGING_CALC_ROWS.map((row) => (row.key === key ? { key, value } : row))
}

beforeEach(() => clearCalcConfigCache())
afterEach(() => clearCalcConfigCache())

// ── The people of this file ─────────────────────────────────────────────────

type Input = SignupEligibilityInput

/** Homem, 180 cm. Sem `weightKg`: 80 kg (IMC 24,69). */
function man(patch: Partial<Input> = {}): Input {
  return { sex: 'masculino', heightCm: 180, weightKg: 80, trainingFrequency: 3, ...patch }
}

/** Mulher, 165 cm. Sem `weightKg`: 62 kg (IMC 22,77). */
function woman(patch: Partial<Input> = {}): Input {
  return { sex: 'feminino', heightCm: 165, weightKg: 62, trainingFrequency: 3, ...patch }
}

// ── What each case expects, in one readable object ──────────────────────────

type Verdict = {
  outcome: 'assigned' | 'choice'
  basis: SignupEligibilityBasis
  recomposicao: string
  ganho_massa: string
  manutencao: string
}

function verdict(input: Input, config?: CalcConfig): Verdict {
  const result = decideSignupEligibility(input, config)
  if (result.outcome === 'invalid_input') {
    throw new Error(`entrada inválida: ${result.invalidFields.join(', ')}`)
  }
  const show = (objective: { status: string; reasons: SignupBlockReason[] }) =>
    objective.reasons.length > 0
      ? `${objective.status}: ${objective.reasons.join(', ')}`
      : objective.status
  return {
    outcome: result.outcome,
    basis: result.basis,
    recomposicao: show(result.objectives.recomposicao),
    ganho_massa: show(result.objectives.ganho_massa),
    manutencao: show(result.objectives.manutencao),
  }
}

/** Colocado em recomposição sem perguntar. */
const assigned = (basis: SignupEligibilityBasis, ...reasons: SignupBlockReason[]): Verdict => ({
  outcome: 'assigned',
  basis,
  recomposicao: 'available',
  ganho_massa: `blocked: ${['composition', ...reasons].join(', ')}`,
  manutencao: 'not_offered',
})

/** Escolhe, com os três objetivos disponíveis. */
const three = (basis: SignupEligibilityBasis): Verdict => ({
  outcome: 'choice',
  basis,
  recomposicao: 'available',
  ganho_massa: 'available',
  manutencao: 'available',
})

/** Escolhe entre recomposição e manutenção; ganho de massa barrado. */
const gainBlocked = (basis: SignupEligibilityBasis, ...reasons: SignupBlockReason[]): Verdict => ({
  outcome: 'choice',
  basis,
  recomposicao: 'available',
  ganho_massa: `blocked: ${reasons.join(', ')}`,
  manutencao: 'available',
})

type Case = { rule: string; who: string; input: Input; expected: Verdict }

const DECISAO_AUTOMATICA = 'regra "Decisão Automática de Protocolo"'
const ENTRADA_GANHO = 'regra "Ganho de massa muscular - Critérios de entrada"'
/**
 * Lista de regras ativas de 01/06/2026, bloco "CHECKPOINT INVIOLÁVEL APÓS
 * food_organization (2026-05-15)": "usuárias dentro da faixa saudável (… BF
 * 25%, … IMC 24,9) foram conduzidas pra recomposição sem a escolha que a regra
 * exige" (nomes omitidos).
 */
const CHECKPOINT_15_05 = 'lista de 01/06/2026, "CHECKPOINT INVIOLÁVEL" de 15/05/2026'

const CASES: Case[] = [
  // O episódio real que esta regra existe para resolver (CHECKPOINT de 15/05/2026):
  // duas mulheres dentro da faixa foram levadas à recomposição sem escolher. Os
  // documentos registram só "BF 25%" de uma e "IMC 24,9" da outra. Peso, altura
  // e musculação delas NÃO constam em nenhum documento: os valores abaixo foram
  // escolhidos aqui. 62,35 kg / 165 cm dá o IMC 22,9 da frase-exemplo do mesmo
  // bloco ("Seu IMC atual é 22,9 e tua gordura corporal estimada é 25%"), que o
  // bloco não liga a ninguém; 67,8 kg / 165 cm dá IMC 24,90. Com 3 treinos.
  {
    rule: `C4 a C7, ${CHECKPOINT_15_05}: "BF 25%" dentro da faixa saudável — "< 28% (mulheres)" pergunta, "apresentar as 3 opções"`,
    who: 'mulher com 25% de gordura, 62,35 kg / 165 cm (IMC 22,9), 3 treinos (episódio real; peso, altura e musculação não constam nos documentos)',
    input: woman({ bodyFatPercent: 25, weightKg: 62.35 }),
    expected: three('BF'),
  },
  {
    rule: `C4 e C7, ${CHECKPOINT_15_05}: "IMC 24,9" dentro da faixa saudável — "IMC < 25 (quando BF não disponível)" pergunta, "apresentar as 3 opções"`,
    who: 'mulher sem gordura, 67,8 kg / 165 cm (IMC 24,9), 3 treinos (episódio real; peso, altura e musculação não constam nos documentos)',
    input: woman({ weightKg: 67.8 }),
    expected: three('IMC'),
  },
  // C1 — "BF ≥ 20% (homens)" → recomposição, sem oferecer escolha.
  {
    rule: `C1, ${DECISAO_AUTOMATICA}: "BF ≥ 20% (homens)"`,
    who: 'homem com 20,0% de gordura, 5 treinos',
    input: man({ bodyFatPercent: 20, trainingFrequency: 5 }),
    expected: assigned('BF'),
  },
  {
    rule: `C1, ${DECISAO_AUTOMATICA}: "BF ≥ 20% (homens)"`,
    who: 'homem com 20,0% de gordura, 2 treinos (os dois critérios do ganho falham)',
    input: man({ bodyFatPercent: 20, trainingFrequency: 2 }),
    expected: assigned('BF', 'training'),
  },
  // C2 — "BF ≥ 28% (mulheres)".
  {
    rule: `C2, ${DECISAO_AUTOMATICA}: "BF ≥ 28% (mulheres)"`,
    who: 'mulher com 28,0% de gordura, 4 treinos',
    input: woman({ bodyFatPercent: 28, trainingFrequency: 4 }),
    expected: assigned('BF'),
  },
  // C3 — "IMC ≥ 25 (quando BF não disponível)"; o 25,0 exato entra.
  {
    rule: `C3, ${DECISAO_AUTOMATICA}: "IMC ≥ 25 (quando BF não disponível)"; 01/02/2026 "o IMC de 25 entra mesmo na recomposiçõa corporal"`,
    who: 'homem sem gordura, 81 kg / 180 cm (IMC 25,0), 4 treinos',
    input: man({ weightKg: 81, trainingFrequency: 4 }),
    expected: assigned('IMC'),
  },
  {
    rule: `C3, ${DECISAO_AUTOMATICA}: "IMC ≥ 25"; 25/03/2026 "o 25 não estaria na faixa da normalidade" (tolerância de arredondamento)`,
    who: 'mulher sem gordura, 64 kg / 160 cm (IMC 25,0; o computador dá 24,999999999999996)',
    input: woman({ weightKg: 64, heightCm: 160 }),
    expected: assigned('IMC'),
  },
  // C4 — "IMC < 25 (quando BF não disponível)" → pergunta; as três opções.
  {
    rule: `C4, ${DECISAO_AUTOMATICA}: "IMC < 25 (quando BF não disponível)"; 25/03/2026 "Isso, menor q 25" / "Sem o igual"`,
    who: 'homem sem gordura, 99,96 kg / 200 cm (IMC 24,99), 3 treinos',
    input: man({ weightKg: 99.96, heightCm: 200 }),
    expected: three('IMC'),
  },
  {
    rule: `C4, ${DECISAO_AUTOMATICA}: "IMC < 25" (a tolerância não é uma faixa)`,
    who: 'homem sem gordura, 80,999 kg / 180 cm (IMC 24,9997), 3 treinos',
    input: man({ weightKg: 80.999 }),
    expected: three('IMC'),
  },
  // C7 sem gordura — o corte é "menor que 25" (áudio de 25/03/2026 19:43); musculação ≥ 3x.
  {
    rule: `C7, ${ENTRADA_GANHO}: "IMC ≤ 24" e "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 77,76 kg / 180 cm (IMC 24,0), 3 treinos',
    input: man({ weightKg: 77.76 }),
    expected: three('IMC'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "IMC ≤ 24" (o computador dá 24,000000000000004)`,
    who: 'homem sem gordura, 69,36 kg / 170 cm (IMC 24,0), 3 treinos',
    input: man({ weightKg: 69.36, heightCm: 170 }),
    expected: three('IMC'),
  },
  {
    rule: 'C7, áudio de 25/03/2026 19:43: "menor que 25 na verdade … incluiria o 24 e não o 25" (o texto escrito "IMC ≤ 24" barraria)',
    who: 'homem sem gordura, 79,38 kg / 180 cm (IMC 24,5), 3 treinos',
    input: man({ weightKg: 79.38 }),
    expected: three('IMC'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 79,38 kg / 180 cm (IMC 24,5), 2 treinos',
    input: man({ weightKg: 79.38, trainingFrequency: 2 }),
    expected: gainBlocked('IMC', 'training'),
  },
  // C7 com gordura — "BF ≤ 19% (homens)", "BF ≤ 27% (mulheres)", "musculação ≥ 3x por semana".
  {
    rule: `C7, ${ENTRADA_GANHO}: "BF ≤ 19% (homens)"`,
    who: 'homem com 19,0% de gordura, 3 treinos',
    input: man({ bodyFatPercent: 19 }),
    expected: three('BF'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"; C6, manutenção continua disponível`,
    who: 'homem com 19,0% de gordura, 2 treinos',
    input: man({ bodyFatPercent: 19, trainingFrequency: 2 }),
    expected: gainBlocked('BF', 'training'),
  },
  {
    rule: `C4 e C7, ${DECISAO_AUTOMATICA}: "BF < 20% (homens)" pergunta; ${ENTRADA_GANHO}: "BF ≤ 19% (homens)" não cumprido`,
    who: 'homem com 19,99% de gordura, 5 treinos',
    input: man({ bodyFatPercent: 19.99, trainingFrequency: 5 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "BF ≤ 19% (homens)" e "musculação ≥ 3x por semana", os dois não cumpridos`,
    who: 'homem com 19,5% de gordura, 2 treinos',
    input: man({ bodyFatPercent: 19.5, trainingFrequency: 2 }),
    expected: gainBlocked('BF', 'composition', 'training'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "BF ≤ 19% (homens)" não cumprido`,
    who: 'homem com 19,01% de gordura, 3 treinos',
    input: man({ bodyFatPercent: 19.01 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "BF ≤ 27% (mulheres)"`,
    who: 'mulher com 27,0% de gordura, 3 treinos',
    input: woman({ bodyFatPercent: 27 }),
    expected: three('BF'),
  },
  {
    rule: `C4 e C7, ${DECISAO_AUTOMATICA}: "< 28% (mulheres)" pergunta; ${ENTRADA_GANHO}: "BF ≤ 27% (mulheres)" não cumprido`,
    who: 'mulher com 27,5% de gordura, 3 treinos',
    input: woman({ bodyFatPercent: 27.5 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: `C4 e C7, ${DECISAO_AUTOMATICA}: "< 28% (mulheres)" pergunta; ${ENTRADA_GANHO}: "BF ≤ 27% (mulheres)" não cumprido`,
    who: 'mulher com 27,99% de gordura, 3 treinos',
    input: woman({ bodyFatPercent: 27.99 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'mulher com 27,0% de gordura, 2 treinos',
    input: woman({ bodyFatPercent: 27, trainingFrequency: 2 }),
    expected: gainBlocked('BF', 'training'),
  },
  // n9/n39 — BF decides the recomp cut; gain independently requires BMI<25.
  {
    rule: 'final.answers n9/n39: BF baixo não libera ganho com IMC26; recomp/manutenção por escolha',
    who: 'homem com 15% de gordura, 84,24 kg / 180 cm (IMC 26,0), 3 treinos',
    input: man({ bodyFatPercent: 15, weightKg: 84.24 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: 'C0 e C1: a gordura coloca em recomposição com IMC abaixo do corte',
    who: 'homem com 22% de gordura, 74,52 kg / 180 cm (IMC 23,0), 5 treinos',
    input: man({ bodyFatPercent: 22, weightKg: 74.52, trainingFrequency: 5 }),
    expected: assigned('BF'),
  },
  {
    rule: 'C0 e C7, faixa entre os cortes: o IMC não libera o ganho quando há gordura informada ("pelo menos um" liberaria — pendência)',
    who: 'homem com 19,5% de gordura, 71,28 kg / 180 cm (IMC 22,0), 5 treinos',
    input: man({ bodyFatPercent: 19.5, weightKg: 71.28, trainingFrequency: 5 }),
    expected: gainBlocked('BF', 'composition'),
  },
  {
    rule: 'C0 e C7: o mesmo corpo sem gordura informada é decidido pelo IMC',
    who: 'homem sem gordura, 71,28 kg / 180 cm (IMC 22,0), 5 treinos',
    input: man({ weightKg: 71.28, trainingFrequency: 5 }),
    expected: three('IMC'),
  },
  // O corte de gordura é o do sexo.
  {
    rule: `C4 e C7: "BF < 28% (mulheres)" e "BF ≤ 27% (mulheres)" — 20% é corte do homem`,
    who: 'mulher com 20,0% de gordura, 3 treinos',
    input: woman({ bodyFatPercent: 20 }),
    expected: three('BF'),
  },
  {
    rule: `C1, ${DECISAO_AUTOMATICA}: "BF ≥ 20% (homens)" — 27% é corte da mulher`,
    who: 'homem com 27,0% de gordura, 3 treinos',
    input: man({ bodyFatPercent: 27 }),
    expected: assigned('BF'),
  },
  // Musculação: 0, 2, 3 e 7 (C7b); áudio de 28/12/2025.
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 80 kg / 180 cm (IMC 24,69), nenhum treino',
    input: man({ trainingFrequency: 0 }),
    expected: gainBlocked('IMC', 'training'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 80 kg / 180 cm (IMC 24,69), 2 treinos',
    input: man({ trainingFrequency: 2 }),
    expected: gainBlocked('IMC', 'training'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 80 kg / 180 cm (IMC 24,69), 3 treinos',
    input: man({ trainingFrequency: 3 }),
    expected: three('IMC'),
  },
  {
    rule: `C7, ${ENTRADA_GANHO}: "musculação ≥ 3x por semana"`,
    who: 'homem sem gordura, 80 kg / 180 cm (IMC 24,69), 7 treinos',
    input: man({ trainingFrequency: 7 }),
    expected: three('IMC'),
  },
  // O rascunho sintético que os testes do app pré-carregam.
  {
    rule: `C4 a C7: "< 28% (mulheres)", "BF ≤ 27% (mulheres)", "musculação ≥ 3x por semana"`,
    who: 'mulher com 25% de gordura, 65 kg / 170 cm, 3 treinos (rascunho de teste do app)',
    input: woman({ bodyFatPercent: 25, weightKg: 65, heightCm: 170 }),
    expected: three('BF'),
  },
]

/** The expected verdict in words, for the test name. */
function inWords(expected: Verdict): string {
  if (expected.outcome === 'assigned') return 'recomposição sem perguntar'
  if (expected.ganho_massa === 'available') return 'escolhe, os três disponíveis'
  return `escolhe, ganho de massa barrado (${expected.ganho_massa.replace('blocked: ', '')})`
}

describe('audit 2026-10-07 — E: cadastro, os números do cliente (configuração padrão do código)', () => {
  it.each(
    CASES.map((c) => [c.who, inWords(c.expected), c.rule, c] as const),
  )('%s → %s — %s', (_who, _words, _rule, c) => {
    expect(verdict(c.input)).toEqual(c.expected)
  })

  it('cada caso traz a regra de onde vem e uma pessoa diferente', () => {
    expect(CASES.every((c) => c.rule.length > 0)).toBe(true)
    expect(new Set(CASES.map((c) => c.who)).size).toBe(CASES.length)
    expect(new Set(CASES.map((c) => JSON.stringify(c.input))).size).toBe(CASES.length)
  })
})

describe('audit 2026-10-07 — E / C1 a C3: quem é colocado em recomposição (o resultado inteiro)', () => {
  it('homem com 20,0% de gordura, 80 kg / 180 cm, 5 treinos', () => {
    expect(decideSignupEligibility(man({ bodyFatPercent: 20, trainingFrequency: 5 }))).toEqual({
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis: 'BF',
      imc: calcIMC(80, 180),
      objectives: {
        recomposicao: { status: 'available', reasons: [] },
        ganho_massa: { status: 'blocked', reasons: ['composition'] },
        manutencao: { status: 'not_offered', reasons: [] },
      },
      limits: { bodyFatRecomp: 20, bodyFatGain: 19, imcRecomp: 25, trainingMin: 3 },
    })
  })

  it('mulher sem gordura, 64 kg / 160 cm: IMC devolvido 24,999999999999996, base IMC, cortes da mulher', () => {
    expect(decideSignupEligibility(woman({ weightKg: 64, heightCm: 160 }))).toEqual({
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis: 'IMC',
      imc: 24.999999999999996,
      objectives: {
        recomposicao: { status: 'available', reasons: [] },
        ganho_massa: { status: 'blocked', reasons: ['composition'] },
        manutencao: { status: 'not_offered', reasons: [] },
      },
      limits: { bodyFatRecomp: 28, bodyFatGain: 27, imcRecomp: 25, trainingMin: 3 },
    })
  })
})

describe('audit 2026-10-07 — E / C3: IMC 25,0 exato e a tolerância de arredondamento', () => {
  it('os IMC deste arquivo, como o computador os calcula', () => {
    expect(calcIMC(81, 180)).toBe(25)
    expect(calcIMC(64, 160)).toBe(24.999999999999996)
    expect(calcIMC(99.96, 200)).toBe(24.99)
    expect(calcIMC(77.76, 180)).toBe(24)
    expect(calcIMC(69.36, 170)).toBe(24.000000000000004)
    expect(calcIMC(79.38, 180)).toBe(24.499999999999996)
    expect(calcIMC(84.24, 180)).toBe(25.999999999999996)
    expect(calcIMC(74.52, 180)).toBe(22.999999999999996)
    expect(calcIMC(80.999, 180)).toBeCloseTo(24.9997, 4)
    // Os dois corpos escolhidos para o episódio de 15/05/2026: 24,90 e 22,90.
    expect(calcIMC(67.8, 165).toFixed(2)).toBe('24.90')
    expect(calcIMC(67.8, 165).toFixed(1)).toBe('24.9')
    expect(calcIMC(62.35, 165).toFixed(2)).toBe('22.90')
  })

  it('a tolerância é 0,000000001: correção de arredondamento, não corte clínico', () => {
    expect(SIGNUP_IMC_ROUNDING_TOLERANCE).toBe(1e-9)
    // 0,00031 abaixo de 25 já escolhe.
    expect(verdict(man({ weightKg: 80.999 })).outcome).toBe('choice')
  })

  it('64 kg / 160 cm: uma comparação sem tolerância deixaria a pessoa escolher', () => {
    expect(calcIMC(64, 160) >= DEFAULT_CALC_CONFIG.imc_limit_recomp).toBe(false)
    expect(verdict(man({ weightKg: 64, heightCm: 160 })).outcome).toBe('assigned')
  })
})

describe('audit 2026-10-07 — E: os cortes vêm da configuração no formato do banco (carregador real)', () => {
  it('com as três linhas de staging, o carregador entrega 20/19, 28/27, 25 e 3', async () => {
    const config = await loadCalcConfig(configClient(STAGING_CALC_ROWS))
    expect(config.bf_limits).toEqual({
      masculino: { recomp: 20, gain: 19 },
      feminino: { recomp: 28, gain: 27 },
    })
    expect(config.imc_limit_recomp).toBe(25)
    expect(config.training_min).toBe(3)
  })

  it('todos os casos deste arquivo dão o mesmo resultado com a configuração carregada', async () => {
    const config = await loadCalcConfig(configClient(STAGING_CALC_ROWS))
    for (const c of CASES) {
      expect([c.who, verdict(c.input, config)]).toEqual([c.who, c.expected])
    }
  })

  it('sem nenhuma linha calc.* vale o padrão do código, com o mesmo resultado', async () => {
    const config = await loadCalcConfig(configClient([]))
    expect(config).toBe(DEFAULT_CALC_CONFIG)
    for (const c of CASES) {
      expect([c.who, verdict(c.input, config)]).toEqual([c.who, c.expected])
    }
  })

  it('a função lê a linha: com calc.imc_limit_recomp = 26, 81 kg / 180 cm (IMC 25,0) escolhe', async () => {
    const config = await loadCalcConfig(configClient(replaceRow('calc.imc_limit_recomp', 26)))
    expect(verdict(man({ weightKg: 81 }), config)).toEqual(three('IMC'))
    expect(verdict(man({ weightKg: 84.24 }), config)).toEqual(assigned('IMC'))
  })

  it('com calc.training_min = 4, 3 treinos deixam de bastar', async () => {
    const config = await loadCalcConfig(configClient(replaceRow('calc.training_min', 4)))
    expect(verdict(man({ bodyFatPercent: 19 }), config)).toEqual(gainBlocked('BF', 'training'))
    expect(verdict(man({ bodyFatPercent: 19, trainingFrequency: 4 }), config)).toEqual(three('BF'))
  })

  it('com calc.bf_limits do homem em 22/21, 20,0% deixa de entrar direto', async () => {
    const config = await loadCalcConfig(
      configClient(
        replaceRow('calc.bf_limits', {
          feminino: { gain: 27, recomp: 28 },
          masculino: { gain: 21, recomp: 22 },
        }),
      ),
    )
    expect(verdict(man({ bodyFatPercent: 20 }), config)).toEqual(three('BF'))
    expect(verdict(man({ bodyFatPercent: 21.5 }), config)).toEqual(gainBlocked('BF', 'composition'))
    expect(verdict(man({ bodyFatPercent: 22 }), config)).toEqual(assigned('BF'))
    expect(verdict(woman({ bodyFatPercent: 28 }), config)).toEqual(assigned('BF'))
  })

  it.each([
    ['calc.imc_limit_recomp', '25'],
    ['calc.imc_limit_recomp', 'vinte e cinco'],
    ['calc.training_min', '3'],
    ['calc.bf_limits', {}],
    ['calc.bf_limits', { feminino: { gain: 27, recomp: 28 } }],
    ['calc.bf_limits', { masculino: { gain: '19', recomp: '20' }, feminino: { recomp: 28 } }],
    ['calc.bf_limits', 'x'],
    // Texto DIFERENTE do padrão: o texto não é convertido em número.
    ['calc.imc_limit_recomp', '26'],
    ['calc.training_min', '4'],
    [
      'calc.bf_limits',
      { masculino: { gain: '21', recomp: '22' }, feminino: { gain: '29', recomp: '30' } },
    ],
  ])('linha %s com valor que não é número (%j): vale o padrão do código, ninguém escolhe por engano', async (key, value) => {
    const config = await loadCalcConfig(configClient(replaceRow(key, value)))
    for (const c of CASES) {
      expect([c.who, verdict(c.input, config)]).toEqual([c.who, c.expected])
    }
  })
})

describe('audit 2026-10-07 — E: entrada que a regra não consegue ler — nada é decidido', () => {
  it.each([
    ['altura 0', { heightCm: 0 }, ['heightCm']],
    ['altura ausente', { heightCm: null }, ['heightCm']],
    ['peso 0', { weightKg: 0 }, ['weightKg']],
    ['peso negativo', { weightKg: -70 }, ['weightKg']],
    ['peso que não é número', { weightKg: Number.NaN }, ['weightKg']],
    ['altura e peso ausentes', { heightCm: null, weightKg: null }, ['heightCm', 'weightKg']],
    ['sexo ausente', { sex: null }, ['sex']],
    ['gordura 0', { bodyFatPercent: 0 }, ['bodyFatPercent']],
    ['gordura 100', { bodyFatPercent: 100 }, ['bodyFatPercent']],
    ['musculação negativa', { trainingFrequency: -1 }, ['trainingFrequency']],
    ['musculação ausente', { trainingFrequency: null }, ['trainingFrequency']],
  ] as Array<
    [string, Partial<Input>, string[]]
  >)('%s → invalid_input, nem recomposição nem escolha', (_name, patch, invalidFields) => {
    expect(decideSignupEligibility(man(patch))).toEqual({
      outcome: 'invalid_input',
      invalidFields,
    })
  })

  it('altura ou peso inválidos não são salvos pela gordura informada', () => {
    expect(decideSignupEligibility(man({ bodyFatPercent: 25, heightCm: 0 }))).toEqual({
      outcome: 'invalid_input',
      invalidFields: ['heightCm'],
    })
  })
})

describe('audit 2026-10-07 — E: casos em que o documento do cliente é omisso — a função não faz nada especial', () => {
  it('RC E, peso muito baixo: homem sem gordura, 45 kg / 180 cm (IMC 13,9), 3 treinos → escolhe entre os três', () => {
    expect(calcIMC(45, 180)).toBeCloseTo(13.89, 2)
    expect(verdict(man({ weightKg: 45 }))).toEqual(three('IMC'))
  })

  it('RC E, gordura de até 10%: homem com 8% e mulher com 10%, 3 treinos → escolhem entre os três', () => {
    expect(verdict(man({ bodyFatPercent: 8 }))).toEqual(three('BF'))
    expect(verdict(woman({ bodyFatPercent: 10 }))).toEqual(three('BF'))
  })
})

describe('audit 2026-10-07 — E: valor com mais de duas casas decimais — a função decide sobre o valor que recebe; quem arredonda como o banco é o servidor', () => {
  // `user_profiles` guarda gordura em numeric(4,2) e peso em numeric(5,2); o
  // contrato do cadastro não limita as casas. Nenhum banco é lido aqui: o valor
  // "gravado" abaixo é o arredondamento a duas casas, escrito à mão. A
  // conferência do servidor arredonda antes de chamar a função (doc §10l,
  // travado em onboarding/eligibility/route.test.ts): por ela, os dois casos
  // abaixo dão recomposição sem perguntar.
  it('homem com 19,995% de gordura: a função decide "escolhe, ganho barrado"; com o valor gravado (20,00) é recomposição sem perguntar', () => {
    expect(verdict(man({ bodyFatPercent: 19.995 }))).toEqual(gainBlocked('BF', 'composition'))
    expect(verdict(man({ bodyFatPercent: 20 }))).toEqual(assigned('BF'))
  })

  it('homem sem gordura com 80,999 kg / 180 cm: a função decide "escolhe"; com o valor gravado (81,00 kg, IMC 25,0) é recomposição sem perguntar', () => {
    expect(verdict(man({ weightKg: 80.999 }))).toEqual(three('IMC'))
    expect(verdict(man({ weightKg: 81 }))).toEqual(assigned('IMC'))
  })
})

// ── The legacy path stays as it was ─────────────────────────────────────────

/** Perfil completo e "em ordem" para a conta antiga: sono de 8h, alimentação organizada. */
function legacyProfile(patch: Partial<UserProfile>): UserProfile {
  return {
    sex: 'masculino',
    birthDate: new Date('1990-01-01'),
    heightCm: 180,
    weightKg: 80,
    bodyFatPercent: null,
    activityLevel: 'moderado',
    trainingFrequency: 5,
    waterIntake: 'moderado',
    hungerLevel: 'moderada',
    currentProtocol: null,
    goalType: null,
    goalValue: null,
    deficitLevel: null,
    bedTime: '23:00',
    wakeTime: '07:00',
    foodOrganization: 'sim',
    ...patch,
  }
}

function legacyMetrics(imc: number): UserMetrics {
  return { age: 36, bmr: 1800, activityFactor: 1.55, lbm: 65, imc, proteinFactor: 1.5 }
}

describe('audit 2026-10-07 — E: resolveProtocol (caminho antigo) continua como estava; onde as duas contas diferem', () => {
  it('64 kg / 160 cm sem gordura: a antiga compara sem tolerância e deixa escolher; a nova coloca em recomposição', () => {
    const profile = legacyProfile({ sex: 'feminino', heightCm: 160, weightKg: 64 })
    expect(resolveProtocol(profile, legacyMetrics(calcIMC(64, 160)))).toEqual({
      protocol: 'recomposicao',
      canChoose: true,
      blockers: [],
      goalType: 'IMC',
      goalValue: 23,
    })
    expect(verdict(woman({ weightKg: 64, heightCm: 160, trainingFrequency: 5 }))).toEqual(
      assigned('IMC'),
    )
  })

  it('dentro da faixa com 2 treinos: a antiga tira toda a escolha; a nova barra só o ganho de massa', () => {
    const profile = legacyProfile({ trainingFrequency: 2 })
    expect(resolveProtocol(profile, legacyMetrics(calcIMC(80, 180)))).toMatchObject({
      protocol: 'recomposicao',
      canChoose: false,
      blockers: ['musculação insuficiente (atual: 2x/semana, mínimo: 3x)'],
    })
    expect(verdict(man({ trainingFrequency: 2 }))).toEqual(gainBlocked('IMC', 'training'))
  })

  it('homem com 19,5% e tudo em ordem: a antiga tira a escolha sem motivo listado; a nova pergunta e barra o ganho por composição', () => {
    const profile = legacyProfile({ bodyFatPercent: 19.5 })
    expect(resolveProtocol(profile, legacyMetrics(calcIMC(80, 180)))).toMatchObject({
      canChoose: false,
      blockers: [],
      goalType: 'BF',
    })
    expect(verdict(man({ bodyFatPercent: 19.5, trainingFrequency: 5 }))).toEqual(
      gainBlocked('BF', 'composition'),
    )
  })

  it('C10, homem com 17%, 5 treinos, sono de 5h e alimentação não organizada: a antiga barra pelos dois; a nova não lê nenhum dos dois', () => {
    const profile = legacyProfile({
      bodyFatPercent: 17,
      bedTime: '01:00',
      wakeTime: '06:00',
      foodOrganization: 'nao',
    })
    expect(resolveProtocol(profile, legacyMetrics(calcIMC(80, 180)))).toMatchObject({
      canChoose: false,
      blockers: ['sono insuficiente (5.0h, mínimo 6.5h)', 'alimentação não estruturada'],
    })
    const input: Input = man({ bodyFatPercent: 17, trainingFrequency: 5 })
    expect(verdict(input)).toEqual(three('BF'))
    expect(Object.keys(input).sort()).toEqual([
      'bodyFatPercent',
      'heightCm',
      'sex',
      'trainingFrequency',
      'weightKg',
    ])
  })
})

describe('declared pendencies', () => {
  it('every "RC E" line of this header is in docs/CALCULO-MPP.md §10j, identical', () => {
    const here = dirname(fileURLToPath(import.meta.url))
    const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    const doc = readFileSync(resolve(here, '../../../../docs/CALCULO-MPP.md'), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC E — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC E — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(24)
    expect(fromDoc).toEqual(fromHeader)
    for (const line of fromHeader) {
      expect(line).toMatch(
        /^> RC E — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-07\)$/,
      )
    }
  })
})
