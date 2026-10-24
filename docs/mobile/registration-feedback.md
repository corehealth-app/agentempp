# Retorno após refeição ou treino — C13

## Estado

Módulo puro e migration C5c qualificados localmente. Ainda não integrados às rotas ou ao iPhone; a migration não foi aplicada ao staging e não houve publicação deste pacote. O consumidor não deve ativar frases sem o BFF comum compatível e QA integrado.

## Contrato da preparação

`@mpp/agent/registration-feedback` exporta `prepareRegistrationFeedback`. Recebe registro confirmado, identidade da conta/registro, idioma e fatos oficiais do mesmo dia. Não grava refeição, não recalcula meta nem amplia o orçamento de comida pelo exercício. A projeção pública usa whitelist; não transporta listas de outros registros, pendências, medicamentos ou suplementos do estado diário.

A saída contém números, linhas localizadas, comentário alimentar/incentivo opcionais e os dois recibos privados de seleção, quando for refeição. `steps` contém cada recibo e seu cursor seguinte, permitindo provar as duas transições no mesmo commit. O cursor é compartilhado com o Flow e avança sequencialmente entre comentário e incentivo; treino usa apenas incentivo aprovado. Nenhum efeito global, relógio, rede ou LLM. A preparação nova é determinística; replay durável pertence ao consumidor, que deve consultar seu recibo antes de selecionar novamente.

Os quatro totais vêm de `proposal.totals`, já calculados e confirmados pelo writer existente. Não ressomar itens em JavaScript ou SQL: `0.1 + 0.2` pode divergir do total decimal canônico `0.3`. Propostas históricas sem os totais válidos deixam o feedback indisponível, preservando a confirmação; não devem consumir uma frase nem provocar backfill.

Rótulos Q42 ficam centralizados em `REGISTRATION_FEEDBACK_CALORIE_LABELS`. Percentuais têm uma casa; 1785/2900 resulta em61,6%, preservando a divergência declarada do exemplo61,5%. Sem meta, não fabricar percentual. Sem comentário elegível, números e incentivo. O banco atual só tem português: a apresentação numérica tem inglês, sem tradução inventada das frases. Não aparecem orçamento14d, diasacimameta, bloco de hipertrofia ou comentário LLM do C61.

## Persistência C5c local

`20261024131247_flow_shared_phrase_registration_feedback.sql` adiciona três campos privados em `users`, recibos privados por registro e quatro RPCs exclusivos do backend. O commit da educação verifica propriedade, status confirmado, hash da proposta, CAS e transições; grava recibo e cursor juntos. Replay resolve o recibo antes dos parâmetros atuais de seleção. A projeção pública valida chaves, tipos e números em profundidade.

`read_flow_shared_phrase_cursor` separa revisão comum e revisão legada das mensagens. O modo `legacy` importa o cursor antigo validado; `shared` permite revisão comum positiva e âncora Flow nula quando o primeiro evento foi C13. Os RPCs C5a e seus namespaces continuam presentes. O reset existente apaga os recibos por cascade da proposta e limpa os campos comuns por trigger, inclusive quando a revisão legada ainda é zero.

A qualificação local usou as206migrations reais anteriores em uma instância Supabase nativa descartável:41assertions SQL, regressão C5a, payload real do módulo com dia completo e decimais canônicos, e duas conexões PostgreSQL concorrentes. Foram observados bloqueios reais para repetição do mesmo registro e disputa Flow × registro; nenhuma duplicação ou perda de seleção. Esses testes não representam sessões GoTrue, staging ou QA no iPhone.

## Ordem obrigatória de integração

- Aplicar a migration aditiva e qualificar um BFF que use os dois novos RPCs do Flow, ainda sem conectar C13 às confirmações.
- Preservar uma baseline de retorno comum compatível. A primeira publicação do novo Flow já adota estado comum; depois disso o BFF antigo não é um rollback completo, mesmo com C13 desligado.
- Campo opcional nas confirmações de refeição/treino e reabertura, preservando sucesso quando feedback falha.
- Decoder/tela PT/EN no iOS, ownership/session guards e QA real. Sem ativar a persona/rotas legadas do WhatsApp.
