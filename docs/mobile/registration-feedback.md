# Retorno após refeição ou treino — C13

## Estado

Módulo puro e migration C5c qualificados localmente. A migration foi aplicada ao staging e a baseline comum do Flow foi publicada e verificada nesse ambiente. O consumidor C13 está conectado localmente às confirmações legadas, à confirmação de treino ui-v1 e à reabertura ui-v1 já existente; essa fonte ainda não foi publicada. Apresentação no iPhone e reabertura pelo Histórico geral continuam pendentes. Esses comentários ainda não constituem uma entrega ao cliente.

O iOS agora decodifica o campo opcional `feedback` e apresenta os textos persistidos na confirmação de refeição ou treino, sob o estado e os guards de sessão já existentes. ID, status confirmado e tipo devem corresponder; payload inválido é ignorado sem invalidar o resultado principal. Não há cálculo de meta, seleção de frase, chamada adicional ou nova etapa de confirmação no cliente. A data civil segue o calendário gregoriano proléptico do contrato; chaves nullable são preservadas como `null` ao codificar e reler. A revisão encontrou e reproduziu a perda desses nulls e a aceitação de datas com sinais antes da correção. Os96testes selecionados de contrato/feedback/modelos de refeição e treino passaram no simulador, com build sem erros. Esse build local inclui os16WIP preservados e não é candidato distribuível; fonte limpa, QA integrado/visual, Histórico geral e distribuição continuam pendentes.

O consumidor opcional do BFF está implementado e qualificado localmente. `registration-feedback-store.ts` valida o DTO fechado e chama os RPCs C5c; `registration-feedback-service.ts` recupera o recibo antes de carregar fatos e preparar frases. Somente conflito explícito de cursor permite até três tentativas. Resultado incerto do commit é resolvido por uma leitura, sem repetir cegamente a escrita. A reabertura tem um caminho separado que apenas lê o recibo.

O campo HTTP opcional aprovado é somente `feedback`, irmão de `id/status/proposal`; não há segundo alias. As duas confirmações legadas o incluem após sucesso persistido e no replay já confirmado. O ui-v1 mantém sua autoridade e ID comprovado do treino antes de enriquecer; seu GET lê exclusivamente o recibo. Falha adicional omite o campo, preservando os resultados do writer. A qualificação do wiring passou com115casos focados e3794testes admin. A regressão da segunda porção continua verificando dois writers, dois almoços e780kcal; apenas os probes de recibo foram separados e conferidos. O teste de falha de leitura usa503 com `Retry-After:0` para manter o caminho do SDK sem esperas reais; o custo de latência sob indisponibilidade continua para QA integrado, sem alteração global dos retries.

Os dados diários exigem data/fuso de origem coerentes, snapshot oficial real e presença dos IDs dos logs próprios no dia. O treino versionado pode usar seu ID confirmado; o caminho legado consulta dono, chave de origem e tipo de treino. Sem essa prova, o dia fica indisponível, preservando os totais confirmados e as frases elegíveis. O loader usa as metas oficiais disponíveis no momento da consulta; isso não constitui uma reconstrução imutável do perfil histórico.

A qualificação do consumidor contém39casos, incluindo o cliente Supabase real com transporte controlado, contrato literal de RPC, filtros de propriedade, decimais canônicos, replay, concorrência CAS, commit incerto e PT/EN. Typecheck e lint dos arquivos alterados passaram. A suíte admin completa passou com3785testes após atualizar um emulador antigo de status para o contrato comum já implantado; o primeiro resultado3784PASS/1FAIL foi preservado. Nenhuma nova publicação, migration, chamada a contas reais ou alteração no iPhone pertence a esse incremento.

## Contrato da preparação

`@mpp/agent/registration-feedback` exporta `prepareRegistrationFeedback`. Recebe registro confirmado, identidade da conta/registro, idioma e fatos oficiais do mesmo dia. Não grava refeição, não recalcula meta nem amplia o orçamento de comida pelo exercício. A projeção pública usa whitelist; não transporta listas de outros registros, pendências, medicamentos ou suplementos do estado diário.

A saída contém números, linhas localizadas, comentário alimentar/incentivo opcionais e os dois recibos privados de seleção, quando for refeição. `steps` contém cada recibo e seu cursor seguinte, permitindo provar as duas transições no mesmo commit. O cursor é compartilhado com o Flow e avança sequencialmente entre comentário e incentivo; treino usa apenas incentivo aprovado. Nenhum efeito global, relógio, rede ou LLM. A preparação nova é determinística; replay durável pertence ao consumidor, que deve consultar seu recibo antes de selecionar novamente.

Os quatro totais vêm de `proposal.totals`, já calculados e confirmados pelo writer existente. Não ressomar itens em JavaScript ou SQL: `0.1 + 0.2` pode divergir do total decimal canônico `0.3`. Propostas históricas sem os totais válidos deixam o feedback indisponível, preservando a confirmação; não devem consumir uma frase nem provocar backfill.

Rótulos Q42 ficam centralizados em `REGISTRATION_FEEDBACK_CALORIE_LABELS`. Percentuais têm uma casa; 1785/2900 resulta em61,6%, preservando a divergência declarada do exemplo61,5%. Sem meta, não fabricar percentual. Sem comentário elegível, números e incentivo. O banco atual só tem português: a apresentação numérica tem inglês, sem tradução inventada das frases. Não aparecem orçamento14d, diasacimameta, bloco de hipertrofia ou comentário LLM do C61.

## Persistência C5c local

`20261024131247_flow_shared_phrase_registration_feedback.sql` adiciona três campos privados em `users`, recibos privados por registro e quatro RPCs exclusivos do backend. O commit da educação verifica propriedade, status confirmado, hash da proposta, CAS e transições; grava recibo e cursor juntos. Replay resolve o recibo antes dos parâmetros atuais de seleção. A projeção pública valida chaves, tipos e números em profundidade.

`read_flow_shared_phrase_cursor` separa revisão comum e revisão legada das mensagens. O modo `legacy` importa o cursor antigo validado; `shared` permite revisão comum positiva e âncora Flow nula quando o primeiro evento foi C13. Os RPCs C5a e seus namespaces continuam presentes. O reset existente apaga os recibos por cascade da proposta e limpa os campos comuns por trigger, inclusive quando a revisão legada ainda é zero.

A qualificação local usou as206migrations reais anteriores em uma instância Supabase nativa descartável:41assertions SQL, regressão C5a, payload real do módulo com dia completo e decimais canônicos, e duas conexões PostgreSQL concorrentes. Foram observados bloqueios reais para repetição do mesmo registro e disputa Flow × registro; nenhuma duplicação ou perda de seleção. Esses testes não representam sessões GoTrue, staging ou QA no iPhone.

### Aplicação e baseline de staging em24/10/2026

No projeto `xitugspwfxkcluxvrdeg`, o arquivo local `20261024131247_flow_shared_phrase_registration_feedback.sql` foi aplicado como registro de histórico `20261024141757`, nome `c13_shared_phrase_registration_feedback_20261024`. As nove funções foram comparadas por hash do corpo, com ACL/RLS e trigger conferidos. Essa diferença de timestamp é do registro pelo conector; **não reaplicar a migration somente porque o número do arquivo difere do histórico**. Conferir esse vínculo e o estado aplicado antes de qualquer ferramenta de sincronização.

O servidor canônico `performe-ai-staging-bff.vercel.app` usa a baseline comum `90e6ad92173ef8aed004e1f5cad422ea68ed7691`, deployment `dpl_AjveiZwKQ35VyNGdvAK9Q8Hufn1p` (Preview, `gru1`). Os testes de QA A/B usaram dois eventos reais de status determinístico, replay e reabertura do histórico. O banco confirmou um único avanço por evento e isolamento; o replay no endereço canônico preservou o cursor. Isso qualifica a baseline comum com C13 desligado, sem provar a integração de educação nas confirmações ou o iPhone.

## Ordem obrigatória de integração

- Migration aditiva e baseline comum já qualificadas no staging. Preservar essa baseline antes de conectar C13 às confirmações.
- Preservar uma baseline de retorno comum compatível. A primeira publicação do novo Flow já adota estado comum; depois disso o BFF antigo não é um rollback completo, mesmo com C13 desligado.
- Campo opcional nas confirmações de refeição/treino e reabertura, preservando sucesso quando feedback falha.
- Decoder/tela PT/EN no iOS, ownership/session guards e QA real. Sem ativar a persona/rotas legadas do WhatsApp.
