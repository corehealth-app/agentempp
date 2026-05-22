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

export function reevaluationKickoff(protocol: Protocol): string {
  const abertura =
    '🎯 Hoje fecha *14 dias* de acompanhamento — hora da sua reavaliação! ' +
    'Vou coletar 3 dados pra recalibrar tua meta com precisão. Me manda:'
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
  return abertura + q1 + q2 + q3
}
