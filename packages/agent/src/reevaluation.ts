/**
 * Kickoff DETERMINÍSTICO da reavaliação de 14 dias, fiel ao script do manual MPP.
 * Usado pelo engagement matinal quando o daily-closer marca `reevaluation.due`.
 *
 * Antes o pedido era genérico ("manda teu peso e BF%/medidas") e o LLM ainda
 * podia ignorar. Roberto 2026-05-22: o manual tem perguntas ESPECÍFICAS por
 * protocolo, e o agente pedia medida errada (medidas em vez de FOTOS) e
 * esquecia a FOME (que define o déficit na recomp).
 *
 * Script oficial (method_chunks "Recomposição/Ganho/Manutenção - Reavaliações a
 * cada 14 dias"): abertura + 3 perguntas obrigatórias. Q1 (peso) e Q2 (3 fotos
 * frente/lado/costas) são iguais nos 3 protocolos; Q3 difere:
 *  - recomposicao → fome média (muita/moderada/baixa) → ajusta o déficit
 *  - ganho_massa  → treinos de musculação/semana → ajusta fator de atividade
 *  - manutencao   → dias de atividade física/semana
 * "O que NÃO pedir": contagem de calorias, cálculos do usuário, detalhe
 * excessivo de treino — só sinais simples.
 */
export type Protocol = 'recomposicao' | 'ganho_massa' | 'manutencao' | null | undefined

export interface ReevaluationKickoffOptions {
  /** Meta de peso atual do paciente (kg), se houver. Vem de user_profiles.goal_value
   * quando goal_type='peso_kg'. Roberto 2026-06-03: na reavaliação, perguntar se
   * a meta continua a mesma. */
  currentTargetWeightKg?: number | null
  /** Meta de BF% atual do paciente, se houver. Vem de user_profiles.goal_value
   * quando goal_type='BF'. Audit 06-18 (caso Roberto): paciente tem goal_type='BF'
   * (4 em prod) e ficava sem Q4 porque código só cobria peso_kg. Estendido. */
  currentTargetBfPercent?: number | null
}

export function reevaluationKickoff(
  protocol: Protocol,
  opts: ReevaluationKickoffOptions = {},
): string {
  const hasTargetWeight =
    typeof opts.currentTargetWeightKg === 'number' && opts.currentTargetWeightKg > 0
  const hasTargetBf =
    typeof opts.currentTargetBfPercent === 'number' && opts.currentTargetBfPercent > 0
  const hasAnyTarget = hasTargetWeight || hasTargetBf
  const totalPerguntas = hasAnyTarget ? 4 : 3
  const abertura =
    `🎯 Hoje fecha *14 dias* de acompanhamento — hora da sua reavaliação! ` +
    `Vou coletar ${totalPerguntas} dados pra recalibrar tua meta com precisão. Me manda:`
  const q1 = '\n\n1) Qual teu *peso atual*?'
  const q2 =
    '\n2) Me manda *3 fotos* pra eu checar a tendência de gordura — *frente, lado e costas* (ou diz "sem fotos").'

  let q3: string
  switch (protocol) {
    case 'ganho_massa':
      q3 = '\n3) Quantos *treinos de musculação* você está fazendo por semana?'
      break
    case 'manutencao':
      q3 =
        '\n3) Quantos *dias de atividade física* por semana? (considere a musculação como referência)'
      break
    case 'recomposicao':
    default:
      q3 = '\n3) Como tá tua *fome* na média desses dias — *muita, moderada ou baixa*?'
      break
  }

  // Q4 opcional — confirma meta atual. Roberto 2026-06-03 (peso_kg) + audit
  // 06-18 (BF). Manual MPP §2.18 não menciona, é extensão pra reaproveitar
  // define_meta_peso (que agora aceita target_weight_kg OU target_bf_percent).
  // Prioriza peso quando ambos definidos (raro — paciente normalmente tem 1
  // goal_type só).
  let q4 = ''
  if (hasTargetWeight) {
    q4 = `\n4) Sua *meta de peso* continua sendo *${opts.currentTargetWeightKg}kg* ou mudou? Se mudou, me diz o novo valor.`
  } else if (hasTargetBf) {
    q4 = `\n4) Sua *meta de gordura corporal* continua sendo *${opts.currentTargetBfPercent}%* ou mudou? Se mudou, me diz o novo valor.`
  }

  return abertura + q1 + q2 + q3 + q4
}
