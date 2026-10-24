# Retorno após refeição ou treino — C13

## Estado

Somente módulo puro local. Ainda não integrado às rotas, à persistência ou ao iPhone; nenhuma publicação deste pacote. O consumidor não deve ativar frases sem C5c durável e QA integrado.

## Contrato da preparação

`@mpp/agent/registration-feedback` exporta `prepareRegistrationFeedback`. Recebe registro confirmado, identidade da conta/registro, idioma e fatos oficiais do mesmo dia. Não grava refeição, não recalcula meta nem amplia o orçamento de comida pelo exercício. A projeção pública usa whitelist; não transporta listas de outros registros, pendências, medicamentos ou suplementos do estado diário.

A saída contém números, linhas localizadas, comentário alimentar/incentivo opcionais e os dois recibos privados de seleção, quando for refeição. O cursor é compartilhado com o Flow e avança sequencialmente entre comentário e incentivo; treino usa apenas incentivo aprovado. Nenhum efeito global, relógio, rede ou LLM. A preparação nova é determinística; replay durável pertence ao consumidor, que deve consultar seu recibo antes de selecionar novamente.

Rótulos Q42 ficam centralizados em `REGISTRATION_FEEDBACK_CALORIE_LABELS`. Percentuais têm uma casa; 1785/2900 resulta em61,6%, preservando a divergência declarada do exemplo61,5%. Sem meta, não fabricar percentual. Sem comentário elegível, números e incentivo. O banco atual só tem português: a apresentação numérica tem inglês, sem tradução inventada das frases. Não aparecem orçamento14d, diasacimameta, bloco de hipertrofia ou comentário LLM do C61.

## Pendências obrigatórias de integração

- Recibo privado por conta/registro; feedback e cursor em um commit atômico, CAS/concorrência/isolation/reset e replay depois de outros eventos.
- Separar witness das mensagensFlow da revisão comum; suportar primeiro eventoC13 com âncoraFlow nula e importar cursor antigo validado.
- Campo opcional nas confirmações de refeição/treino e reabertura, preservando sucesso quando feedback falha.
- Decoder/tela PT/EN no iOS, ownership/session guards e QA real. Sem ativar a persona/rotas legadas do WhatsApp.
