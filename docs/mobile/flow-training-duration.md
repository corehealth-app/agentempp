# Tempo disponível na sugestão de treino do Flow

Quando a pessoa informa o tempo disponível por sessão, a ferramenta
`propoe_plano_treino` aceita `duration_min`, inteiro entre 10 e 180 minutos.
Esse campo é opcional: o Flow não deve inventar um limite que não foi informado.

O limite chega ao gerador junto com equipamentos, nível e dias da semana. A
instrução pede um volume de exercícios, séries e descansos que caiba no tempo,
incluindo aquecimento e transições. Sessões menores cabem no limite; a duração
continua sendo uma estimativa, não uma medição de execução real.

Uma resposta com qualquer sessão acima do limite é recusada antes de arredondar
os minutos. O sistema não troca o rótulo de 60 para 45 mantendo o mesmo treino,
nem repete automaticamente a chamada paga. O Flow não pode apresentar essa
resposta como sugestão válida. A falha registra `training.generation_failed`
com motivo `requested_duration_exceeded` e o limite numérico, sem texto privado.

Pedidos sem duração mantêm o comportamento anterior. O campo não altera a
ferramenta legada `gera_treino`, importação de documentos, registros de treino,
fórmulas, guardas clínicos ou confirmação do plano. A sugestão continua sendo
rascunho até a pessoa revisar e confirmar no app.

A regressão reproduz o vetor registrado no QA R353: pedido de 45 minutos e
resposta de 60/60/60/50. Os exercícios da fixture são sintéticos. Testes locais
não substituem a qualificação da geração real e da versão distribuída.
