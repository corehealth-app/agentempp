# Posicionamento da fonte — sem autoridade de consumo

`positionConversationMealSource` reconstrói candidatos de texto, áudio e foto a
partir do comando original e da captura privada do banco. Não chama modelo,
calcula nutrientes ou grava domínio. Mantém os IDs dos candidatos e recoloca os
inputs na ordem da fonte, antes de qualquer agregação do calculador.

Uma captura já pertencente ao backend é obrigatória para candidatos preparados:
dono/comando/hash/DTO original, unidades de evidência e mídia precisam coincidir.
O processamento de mídia é confrontado com versão, relógios e hash integral.
Legenda, transcrição e itens visuais são tratados separadamente; o comentário do
Vision nunca estabelece que houve consumo. O código não aceita uma captura de
origem comprovada apenas porque seu JSON passou pelo schema: essa origem vem da
factory SQL real e do CAS posterior.

O parser determinístico é reutilizado sem outra extração de IA. Quantidade
contraditória, perda de trecho, nome abreviado, quantidade indispensável ausente,
baixa confiança e item visual descartado retêm o preparo original e devolvem
esclarecimento. A receita exata já existente de uma caneca de leite com uma medida
de whey pode usar suas referências editáveis, sem transformar similaridade de
uma palavra em cobertura. Dois alimentos iguais com quantidades diferentes
continuam sendo duas ocorrências. Referências de rótulo conservam seus IDs.

## Limite deliberado e obrigatório

O primeiro desenho atribuiria uma prova semântica ao acordo entre dois usos do
mesmo parser. A revisão encontrou o erro: o parser pode colocar prosa ou outra
quantidade dentro de um suposto nome, como `arroz menos 20 g`. Concordância entre
reconstruções não comprova que esse nome é uma expressão alimentar nominal ou que
o relato afirma consumo real.

Por isso o retorno é somente `positioned`, com
`coverage.schema: conversation.meal-positioning.v1` e `complete_source: false`.
Não existe `proof` nem `decision: consumed_meal`. Essa estrutura não satisfaz o
envelope do writer SQL e não deve ser convertida para ele por coerção de tipo.
O intérprete semântico posterior precisa analisar o relato inteiro, suas fontes
e referências reais, esclarecendo qualquer dúvida antes de produzir uma prova
de consumo. Esse intérprete e a composição pública continuam pendentes.

## Evidência local

28 testes novos cobrem ordem, duplicidade legítima, frase incompleta, nomes
truncados, quantidade contraditória, pergunta/futuro/negação, fonte/conta/mídia
alteradas, legenda e fala conflitantes, itens visuais omitidos e aliases mutáveis.
Os 133 testes de posicionamento e componentes vizinhos passaram, assim como o
typecheck. O ensaio BFF → SDK → REST → PostgreSQL real também posicionou e calculou
três relatos usando o catálogo existente e histórico verdadeiro de QA, preservando
recibos de fonte para hits e misses, sem gravar refeições ou conceder autoridade
semântica. Isso não equivale ao fluxo completo do app ou à entrega no TestFlight.
