# BodyFlow Mobile API V1

## Estado

- Implementação: `apps/admin/src/app/api/mobile/v1`.
- Runtime: Next.js Route Handlers, Node.js.
- Ambiente validado: Supabase Branch staging `xitugspwfxkcluxvrdeg`.
- Produção: não alterada e não deployada nesta fase.
- Base URL: será definida quando o projeto Vercel de staging for publicado.

## Autenticação

Todas as rotas exigem:

```http
Authorization: Bearer <supabase_access_token>
```

O token precisa representar uma conta paciente com e-mail confirmado. A API
recusa contas administrativas, identidades legadas sem migração explícita e
pacientes `blocked` ou `deleted`. O app nunca recebe a chave `service_role`.

## Envelopes

Sucesso:

```json
{
  "data": {},
  "meta": {
    "api_version": "v1",
    "request_id": "request-id"
  }
}
```

Erro:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Request validation failed",
    "request_id": "request-id",
    "details": {}
  }
}
```

Respostas de paciente usam `Cache-Control: no-store`, `Vary: Authorization` e
`X-Request-Id`. O cliente pode enviar `X-Request-Id` com 8 a 128 caracteres
seguros; caso contrário, o servidor gera um UUID.

## Idempotência

Toda rota `POST`, `PATCH` ou `DELETE` exige:

```http
Idempotency-Key: mobile-<uuid-ou-id-opaco>
```

Rotas com body exigem também `Content-Type: application/json`. Confirmação e
cancelamento sem body continuam exigindo `Idempotency-Key`. O archive de um item
de rotina é uma exceção explícita: `DELETE /supplements/:id` e
`DELETE /medications/:id` exigem o objeto JSON estrito `{}`.
A chave aceita 8 a 128 caracteres em
`A-Z a-z 0-9 . _ : -`.

O escopo é `(patient, key)`. Repetir método, rota e payload normalmente reproduz a resposta
original com `Idempotency-Replayed: true`; a conclusão de onboarding é a exceção
fail-closed e revalida os requisitos legais atuais antes de responder ao replay.
Reutilizar a chave para outra operação
retorna `409 idempotency_key_conflict`. Uma operação simultânea retorna
`409 idempotency_request_in_progress`. O ledger expira em 24 horas e é acessível
somente ao backend.

Exceção: `POST /onboarding/eligibility` exige o cabeçalho, com as mesmas recusas
(`400 missing_idempotency_key`, `400 invalid_idempotency_key`), mas **não guarda
a chave nem a resposta**. A rota não grava nada, a resposta depende só do corpo
e da configuração de cálculo, e o registro guardaria dados corporais da pessoa.
Repetir o pedido recalcula a resposta, sem `Idempotency-Replayed`; a mesma chave
com outro corpo não é conflito.

Um pedido que falha **depois** de a chave ser reservada não some do ledger: o
registro fica guardado como `failed`, com o hash do corpo, pelas mesmas 24
horas (lido em `supabase/migrations/20260720130537_mobile_api_idempotency.sql`;
a função não foi executada para escrever este parágrafo). Repetir o mesmo corpo
com a mesma chave executa de novo; outro corpo com a mesma chave continua sendo
`409 idempotency_key_conflict`. Por isso a recusa de objetivo de
`POST /onboarding` é decidida **antes** da reserva e não deixa registro (ver
"Objetivo fora da regra na conclusão").

## Endpoints

| Método | Rota | Contrato |
|---|---|---|
| `GET` | `/me` | identidade pública do paciente, locale, país e timezone |
| `PATCH` | `/me` | altera `name`, `locale`, `timezone` e/ou país ISO alpha-2 |
| `GET` | `/today` | estado diário oficial, determinístico e versionado |
| `GET` | `/profile` | perfil corporal, rotina, objetivo e onboarding |
| `GET` | `/onboarding` | retorna conclusão server-owned, documentos oficiais atuais e ações auditadas |
| `POST` | `/onboarding` | conclui atomicamente o onboarding com payload completo e `Idempotency-Key`; usuário e horários são derivados pelo backend; na primeira conclusão recusa objetivo fora da regra do cadastro (`422 onboarding_objective_not_eligible`); devolve a mensagem de entrada do objetivo gravado |
| `POST` | `/onboarding/eligibility` | conferência de objetivo no cadastro: quais objetivos podem ser gravados para os dados corporais enviados, com o texto de cada um; não grava nada |
| `GET` | `/protocol` | objetivo atual do perfil, metas do dia como em `/today` e a mensagem de entrada do objetivo; só leitura |
| `GET` | `/plan` | plano de treino ativo e prescrições vigentes |
| `GET` | `/progress` | nível, streak, bloco 7700, peso, BF e reavaliação |
| `GET` | `/history` | histórico próprio; aceita `before` ISO e `limit` 1..100 |
| `POST` | `/registrations/propose` | calcula e cria pending de refeição ou treino |
| `POST` | `/registrations/:id/confirm` | grava deterministicamente o pending aprovado; proposta de refeição criada pelo app é sempre um registro novo e reenviar a confirmação da mesma proposta não duplica (ver "Ciclo do pending") |
| `PATCH` | `/registrations/:id` | recalcula e edita um pending ainda aberto; `409 registration_already_confirmed` se o registro desse pending já foi gravado (ver "Ciclo do pending") |
| `DELETE` | `/registrations/:id` | cancela um pending ainda aberto; `409 registration_already_confirmed` se o registro desse pending já foi gravado (ver "Ciclo do pending") |
| `GET` | `/meal-records/:id` | lê alimento confirmado, conjunto oficial, versão opaca e elegibilidade do dia |
| `PATCH` | `/meal-records/:id` | substitui um alimento confirmado selecionado, com versão e recibo transacional |
| `DELETE` | `/meal-records/:id` | apaga seleção explícita finita de alimentos confirmados, com versão e recibo transacional |
| `GET` | `/pending` | lista pendings válidos do paciente, sem payload interno |
| `GET` | `/coach/persona` | preferência, personalidade efetiva, opções localizadas e estado do mascote |
| `PATCH` | `/coach/persona` | altera a preferência futura para `focus`, `impulse` ou `zen` |
| `GET` | `/content` | feed elegível em `today`, `library` ou `saved` |
| `GET` | `/content/:id` | detalhe elegível com Markdown validado |
| `POST` | `/content/:id/read` | registra impressão, abertura ou conclusão idempotente |
| `POST` | `/content/:id/save` | salva ou remove dos salvos de forma idempotente |
| `GET` | `/entitlements` | assinaturas sanitizadas e estado do billing mobile |
| `POST` | `/media` | cria ativo privado e devolve URL temporária de upload |
| `POST` | `/media/:id/complete` | verifica tipo/tamanho reais e conclui o upload |
| `GET` | `/media/:id` | metadados próprios, resultado e download temporário quando disponível |
| `POST` | `/media/:id/process` | solicita Vision/STT idempotente para um upload concluído |
| `DELETE` | `/media/:id` | remove o objeto físico antes de encerrar o catálogo |
| `GET` | `/devices` | lista instalações iOS próprias sem token APNs |
| `POST` | `/devices` | registra ou atualiza uma instalação iOS e seu token no backend |
| `DELETE` | `/devices/:id` | desativa uma instalação própria sem apagar auditoria |
| `GET` | `/notification-preferences` | lê opt-in, horário silencioso, limite e meta de hidratação |
| `PATCH` | `/notification-preferences` | altera parcialmente preferências validadas |
| `GET` | `/reminders` | lista regras próprias em horário local e dias da semana |
| `POST` | `/reminders` | cria uma regra simples; não aceita cron arbitrário |
| `PATCH` | `/reminders/:id` | altera ou desativa uma regra própria |
| `GET` | `/supplements` | lista suplementos próprios, horários e ocorrências exatas do dia |
| `POST` | `/supplements` | cria suplemento e um ou mais horários atomicamente |
| `PATCH` | `/supplements/:id` | altera item e horários com versão otimista |
| `DELETE` | `/supplements/:id` | arquiva item e desativa lembretes sem apagar histórico |
| `POST` | `/supplements/:id/log` | registra `taken`, `snoozed` ou `skipped` na ocorrência exata |
| `GET` | `/supplements/:id/history` | pagina o histórico append-only por cursor opaco |
| `GET` | `/medications` | lista medicamentos próprios, horários e ocorrências exatas do dia |
| `POST` | `/medications` | cria medicamento após aceite legal da versão vigente |
| `PATCH` | `/medications/:id` | altera item e horários com versão otimista |
| `DELETE` | `/medications/:id` | arquiva item e desativa lembretes sem apagar histórico |
| `POST` | `/medications/:id/log` | registra `taken`, `snoozed` ou `skipped` na ocorrência exata |
| `GET` | `/medications/:id/history` | pagina o histórico append-only por cursor opaco |
| `GET` | `/legal/medication-reminder-disclaimer` | lê a versão legal localizada atualmente exigida |
| `POST` | `/legal/medication-reminder-disclaimer/accept` | aceita exatamente a versão e o hash exibidos |
| `POST` | `/routine/hydration` | soma água atomicamente ao dia local correto |
| `POST` | `/routine/supplements/:id/taken` | wrapper legado; registra somente quando há uma ocorrência elegível única |
| `POST` | `/routine/medications/:id/taken` | wrapper legado; registra somente quando há uma ocorrência elegível única |

Todos os caminhos acima têm o prefixo `/api/mobile/v1`.

### Contrato de onboarding server-owned

`GET /onboarding` retorna o `locale` autoritativo do perfil, a conclusão
reconciliada, o catálogo vigente e somente as ações do ciclo vigente, limitadas
a 16 registros. `completion.completed`
só é `true` quando há `completed_at` oficial e ações exatas para todas as versões
do conjunto de requisitos vigente. Um booleano legado isolado não autentica o
paciente. Ausência do conjunto versionado, catálogo parcial, mais de 16 documentos
ou resposta documental serializada acima de 48.000 bytes falham fechados. O estado
público completo também é limitado a 60.000 bytes, abaixo do limite de 64 KiB do
transporte iOS.

```json
{
  "data": {
    "locale": "pt-BR",
    "completion": { "completed": false, "completed_at": null },
    "requirements": {
      "available": true,
      "blocking_reason": null,
      "documents": []
    },
    "accepted_actions": [],
    "draft": null
  },
  "meta": { "request_id": "...", "api_version": "v1" }
}
```

O novo formato de `POST /onboarding` é identificado pela presença de
`document_actions`. Ele exige o perfil completo, `objective`, `persona`, locale
autoritativo e uma ação explícita para cada documento vigente. O payload não aceita
`user_id`, `onboarding_completed`, horário oficial ou estado de publicação. A
resposta contém `onboarding_completed`, `completed_at`, objetivo, persona, as
ações confirmadas e `protocol_welcome` (ver "Mensagem de entrada do objetivo");
o UUID interno de domínio não integra o contrato público. Uma
nova versão obrigatória devolvida pelo GET exige nova ação explícita e pode ser
reconsentida atomicamente sem reescrever o timestamp da primeira conclusão. Quando
há uma conclusão histórica que precisa de uma versão legal nova, `draft` contém o
perfil e a persona autoritativos já persistidos, sem identificador de usuário; o
iOS abre diretamente a etapa de consentimento, limpa seleções antigas e reenvia os
mesmos dados apenas para a validação atômica de imutabilidade.

Para compatibilidade, o mesmo POST ainda aceita o formato parcial legado e mantém
a resposta `profile + targets`. Esse caminho só salva campos legados seguros:
`onboarding_completed: true` é deliberadamente rejeitado, pois conclusão passou a
ser autoridade exclusiva do backend. Requests novos e legados continuam exigindo
`Idempotency-Key`; uma chave reutilizada com payload diferente retorna
`409 idempotency_key_conflict`. No contrato completo, o retry exato reexecuta a
validação/RPC: pode retornar `409 onboarding_requirements_changed` se o catálogo
vigente mudou depois da primeira resposta.

Erros específicos: `409 onboarding_requirements_changed` solicita novo GET;
`409 onboarding_already_completed` protege perfil já concluído contra reescrita;
`409 onboarding_locale_unsupported`; `422 onboarding_rejected`;
`422 onboarding_objective_not_eligible` (primeira conclusão com objetivo fora da
regra do cadastro: ver "Objetivo fora da regra na conclusão"); e
`503 onboarding_documents_unavailable`. Respostas não incluem detalhes internos do
banco e usam `Cache-Control: no-store` e `Vary: Authorization`.

No ambiente de avaliação, a primeira conclusão pode conceder um acesso de N
dias sem mudar esta resposta: ver "Acesso de avaliação automático". Desligado
por padrão.

### Mensagem de entrada do objetivo

`POST /onboarding`, no formato com `document_actions`, devolve também:

```json
{
  "protocol_welcome": {
    "protocol": "recomposicao",
    "paragraphs": ["Marina, a partir de agora você entra oficialmente na fase de recomposição corporal.\nIsso significa…", "…"]
  }
}
```

- `protocol`: o objetivo **gravado** (o mesmo de `objective`).
- `paragraphs`: o texto de entrada daquele protocolo, no `locale` do pedido
  (`pt-BR` ou `en-US`) e com o `name` do pedido. São 4 parágrafos na
  recomposição e na manutenção e 7 no ganho de massa. Um parágrafo pode trazer
  quebras de linha simples (`\n`); o cliente não divide nem junta parágrafos.
- É montado no servidor depois que a gravação responde (a função SQL não
  mudou). Sai **igual em toda repetição** do mesmo pedido, inclusive no novo
  aceite de termos de uma conta já concluída. Ressalva, anterior a esta
  mudança: um pedido com altura, peso ou gordura de mais de duas casas
  decimais não se repete igual (o banco grava o valor arredondado, a função
  SQL compara com o enviado e a repetição vira `409
  onboarding_already_completed`); o app envia no máximo duas casas.
- No novo aceite de termos (conta que já tinha data de conclusão) o cliente
  **não apresenta** `protocol_welcome` como entrada no objetivo: a pessoa já
  estava nele.
- **Não fica no registro de idempotência**: o que o ledger guarda é a resposta
  sem `protocol_welcome` (o texto leva o nome da pessoa e nunca é lido de volta,
  porque o replay refaz a resposta).
- Os textos, cada edição feita nos textos do cliente e a tradução estão em
  `docs/CALCULO-MPP.md` §10m. Nenhum traz o nome do método nem do médico.
- O formato parcial legado não devolve o campo.

Um cliente que ignora campos desconhecidos continua funcionando.

### Conferência de objetivo no cadastro

`POST /api/mobile/v1/onboarding/eligibility` responde, **sem gravar nada**, quais
objetivos o cadastro pode gravar para os dados corporais informados, pela regra
de `docs/CALCULO-MPP.md` §10. Não exige entitlement (fica sob `/onboarding`).
Exige `Idempotency-Key`, mas não guarda a chave (ver "Idempotência").

Pedido (objeto estrito; qualquer chave a mais → `422 validation_failed`):

```json
{
  "locale": "pt-BR",
  "sex": "masculino",
  "height_cm": 180,
  "weight_kg": 80,
  "body_fat_percent": 19,
  "training_frequency": 2
}
```

- `locale`: `pt-BR` ou `en-US` — o idioma dos textos da resposta.
- `sex`, `height_cm` (100–250), `weight_kg` (30–300), `body_fat_percent`
  (3–60, opcional: ausente = não informada; `null` é recusado) e
  `training_frequency` (inteiro de 0 a 7, musculação por semana): as mesmas
  faixas de `POST /onboarding`, pela mesma definição no contrato.
- Não aceita nome, data de nascimento, objetivo nem identificador.

Antes de decidir, o servidor arredonda altura, peso e gordura a duas casas, como
o banco grava (`numeric`, metade para longe do zero): gordura `19.995` é decidida
como `20.00`. A resposta e o perfil que a conclusão vai gravar não podem
discordar.

Resposta `200`:

```json
{
  "decision": "choice",
  "basis": "body_fat",
  "objective": null,
  "notice": null,
  "options": [
    { "objective": "recomposicao", "status": "available", "reasons": [], "message": [] },
    {
      "objective": "ganho_massa",
      "status": "blocked",
      "reasons": ["gain_training"],
      "message": [
        "O protocolo de ganho de massa muscular exige musculação pelo menos 3 vezes por semana. Sem esse critério, superávit calórico vira gordura. Você informou 2 por semana."
      ]
    },
    { "objective": "manutencao", "status": "available", "reasons": [], "message": [] }
  ]
}
```

| Campo | Valores |
|---|---|
| `decision` | `"assigned"`: a pessoa é colocada em recomposição, sem pergunta. `"choice"`: a pessoa escolhe |
| `basis` | o que decidiu: `"body_fat"` (gordura informada) ou `"bmi"` (sem gordura, o IMC) |
| `objective` | `"recomposicao"` quando `assigned`; `null` quando `choice` |
| `notice` | parágrafos do aviso de recomposição definida quando `assigned`; `null` quando `choice` |
| `options` | sempre os três objetivos, nesta ordem: `recomposicao`, `ganho_massa`, `manutencao` |
| `options[].status` | `"available"` (pode ser gravado), `"blocked"` (a regra barra; `reasons` diz por quê) ou `"not_offered"` (manutenção de quem foi colocado em recomposição) |
| `options[].reasons` | vazio, ou, só em `blocked`, `"gain_composition"` e/ou `"gain_training"`, nessa ordem |
| `options[].message` | parágrafos do texto a mostrar junto da opção; vazio quando não há o que dizer |

Texto do ganho de massa quando `blocked`:

- `assigned`: a frase de bloqueio do cliente, adaptada, citando "seu percentual
  de gordura atual" ou "seu IMC atual" conforme `basis`. Só ela, mesmo quando
  `reasons` também traz `gain_training`.
- `choice`: um parágrafo por motivo, na ordem de `reasons` — o motivo da gordura
  cita o corte aplicado; o da musculação cita o mínimo e o número informado.

Os cortes vêm da configuração de cálculo do servidor (`calc.*`) e aparecem
dentro do texto; o cliente não conhece nem recebe os limiares. A resposta não
devolve nenhum dado corporal do pedido. Nada é escrito em log. O único acesso
ao banco da rota é a leitura de `calc.*`; antes dela roda só a autenticação
comum a todas as rotas.

Erros: `400 missing_idempotency_key`, `400 invalid_idempotency_key`,
`415 unsupported_media_type`, `400 invalid_json`, `422 validation_failed` e
`500 data_access_failed` quando a leitura da configuração de cálculo falha (o
servidor não decide no lugar dela). Leitura que dá certo sem nenhuma linha
`calc.*`, ou com um corte que não guarda número, não é falha: vale o corte
padrão do código (`docs/CALCULO-MPP.md` §10a).

**O que a rota não faz:** não grava nem reserva o objetivo. Quem recusa é a
conclusão: na primeira conclusão, `POST /onboarding` só grava o objetivo que
esta resposta marca `available` (ver "Objetivo fora da regra na conclusão").
O app publicado não chama esta rota.

Código: `apps/admin/src/app/api/mobile/v1/onboarding/eligibility/handler.ts` e
`apps/admin/src/lib/mobile-api/protocol-eligibility-service.ts`. Testes:
`onboarding/eligibility/route.test.ts` (rota inteira sobre um banco que falha em
qualquer escrita) e `protocol-eligibility-service.test.ts`.

### Objetivo fora da regra na conclusão

`POST /onboarding` (formato com `document_actions`) recusa o objetivo que a
regra do cadastro não permite para os dados corporais enviados. Assim a regra
vale mesmo para um cliente que não chamou a conferência.

**Quando acontece.** Só na **primeira conclusão** da conta: quando o perfil
ainda não tem data de conclusão (`user_profiles.onboarding_completed_at` vazio).
É a mesma condição em que a função SQL `complete_mobile_onboarding_atomic` grava
o objetivo. Nesse caso o servidor decide com `sex`, `height_cm`, `weight_kg`,
`body_fat_percent` e `training_frequency` do pedido, exatamente como
`POST /onboarding/eligibility` decide (mesma função, mesmo arredondamento para
o valor que o banco grava, mesma configuração `calc.*`), e só deixa seguir o
objetivo que a conferência marcaria `available`. `blocked` e `not_offered` são
recusados do mesmo jeito. Sono, alimentação e os demais campos não são lidos.

Resposta `422`, sem `details`:

```json
{
  "error": {
    "code": "onboarding_objective_not_eligible",
    "message": "The objective is not available for the data sent",
    "request_id": "request-id"
  }
}
```

- A recusa não traz nenhum dado do pedido, nem o motivo, nem os cortes. Nada é
  escrito em log.
- **Nada é gravado**: a função SQL não é chamada, o perfil e os aceites de
  documentos ficam como estavam, e nenhum acesso de avaliação é concedido.
- **O que o cliente faz:** chama `POST /onboarding/eligibility` de novo com os
  mesmos dados corporais, volta à etapa do objetivo e mostra o que a
  conferência responder (as opções, o aviso e o texto de cada uma). Depois
  reenvia a conclusão com um objetivo `available`.
- A recusa **não cria registro de idempotência**: a conferência roda **antes**
  de a chave ser reservada. A mesma `Idempotency-Key` pode ser reenviada com o
  objetivo corrigido, e repetir o pedido recusado decide de novo (sem
  `Idempotency-Replayed`). É o caminho do app publicado, que reaproveita a
  chave da conclusão depois deste erro: a pessoa volta, toca em outro objetivo
  e conclui com a mesma chave. Se a conferência rodasse depois da reserva, a
  chave ficaria presa ao corpo recusado (registro `failed` com o hash dele) e o
  reenvio corrigido viraria `409 idempotency_key_conflict` por 24 horas.
- Isso vale para a chave que ainda não tinha registro. Uma chave que **já**
  estava presa a outro corpo — por exemplo, por uma conclusão que falhou depois
  da reserva — continua respondendo `409 idempotency_key_conflict` a um corpo
  diferente, como sempre; o `422` desta conferência sai antes disso.

**Quem não passa pela conferência.** Conta que já tem data de conclusão: o novo
aceite de termos e a repetição de um pedido já concluído seguem como antes. O
servidor lê a data, não carrega a configuração de cálculo e entrega o pedido à
função SQL, que continua exigindo só que os dados reenviados sejam iguais aos
gravados. Uma conta que concluiu em ganho de massa ou manutenção fora dos
critérios continua aceitando termos novos, e nenhuma conta existente é movida
ou recusada. Conta concluída que envia outro objetivo continua recebendo
`409 onboarding_already_completed`, nunca este `422`.

**Falha fechada.** Se a data de conclusão do perfil não puder ser lida, ou se a
leitura da configuração de cálculo **falhar**, a resposta é
`500 data_access_failed`: nada é concluído e nada é decidido no lugar da
leitura que faltou. Vale também para a conta já concluída cuja leitura do
perfil falha. "Não puder ser lida" inclui a coluna que volta com algo que não é
data nem vazio (número, texto em branco, texto que não é data): só uma data
lida dispensa a conferência. Como a conferência roda antes da reserva da chave,
a falha também não cria registro de idempotência, e a mesma chave pode ser
reenviada. O `500` pode demorar a sair: as duas leituras são GET, e o cliente
de banco repete um GET que falha por erro de rede antes de desistir (o mesmo
comportamento descrito em "Acesso de avaliação automático"; não foi medido para
estas duas leituras).

Leitura que **dá certo** não é falha, mesmo sem trazer os cortes: se
`global_config` não tiver nenhuma linha `calc.*`, ou se a linha de um corte
guardar algo que não é número, vale o corte padrão do código (20/19, 28/27, 25
e 3; `docs/CALCULO-MPP.md` §10a). É o que o carregador e a regra já faziam, e a
conferência (`POST /onboarding/eligibility`) decide igual, então as duas não
divergem. A diferença é que agora esse corte recusa ou libera cadastros.

Uma ressalva: cada instância guarda as linhas `calc.*` por 60 segundos. Nos 60
segundos seguintes a uma edição de um corte, a instância que responde a
conferência e a que responde a conclusão podem decidir com cortes diferentes (a
conferência marca disponível e a conclusão recusa, ou o contrário). Não editar
cortes enquanto houver cadastro em andamento.

**Ordem das respostas.**

1. Corpo, como antes: `415 unsupported_media_type`, `413 request_too_large`,
   `400 invalid_json`, `422 validation_failed`.
2. Presença e formato da `Idempotency-Key`: `400 missing_idempotency_key`,
   `400 invalid_idempotency_key`. Nada é lido do banco antes disso.
3. Conferência do objetivo: `422 onboarding_objective_not_eligible`, ou
   `500 data_access_failed`.
4. Reserva da chave: `409 idempotency_key_conflict`,
   `409 idempotency_request_in_progress`, ou a repetição de um pedido concluído.
5. Função SQL, com os erros de sempre.

Consequências da ordem, todas em uma **primeira conclusão com objetivo fora da
regra** (com objetivo permitido, e em toda conta com data de conclusão, a
resposta é a de antes):

- o `422` da conferência sai antes de **todas** as recusas da função SQL, não
  só da de conta sem perfil: documento com versão antiga
  (`409 onboarding_requirements_changed`), dados que a função rejeita
  (`422 onboarding_rejected`), documentos indisponíveis
  (`503 onboarding_documents_unavailable`) e conta sem perfil
  (`404 patient_not_found`). Nada é gravado em nenhum dos casos;
- sai também antes dos dois `409` da chave: um pedido fora da regra enviado com
  uma chave já usada por outro corpo, ou em andamento, recebe o `422`.

O pedido chega à função SQL inteiro e sem alteração: o valor arredondado serve
só para decidir.

**Custo.** Uma leitura de `user_profiles` (uma coluna) por conclusão. Na
primeira conclusão, também a leitura de `calc.*`, que cada instância guarda por
60 segundos. O formato parcial legado do mesmo POST não é uma conclusão e não
lê nada disso.

**Casos de borda, declarados em `docs/CALCULO-MPP.md` §10j:**

- A versão do app publicada antes da etapa do app não trata este código: ao
  receber o `422` mostra só "Revise os dados informados.", sem o motivo e sem
  voltar à etapa do objetivo. A pessoa pode voltar por conta própria, tocar em
  outro objetivo e concluir: o app reenvia com a mesma chave e o servidor
  aceita, porque a recusa não criou registro. Esta mudança deve ir ao ar junto
  com a versão do app que chama a conferência.
- Conta antiga marcada como concluída mas sem data de conclusão: a função SQL já
  a trata como primeira conclusão (regrava o protocolo), e a conferência segue a
  função SQL. Se refizer o cadastro com um objetivo fora da regra, recebe `422`
  onde antes concluía. Quantas contas de **produção** estão nessa situação não
  foi contado: conferir antes de publicar.
- Conta sem linha de perfil: a conferência roda do mesmo jeito; com objetivo
  permitido, a resposta é a que a função SQL já dava (`404 patient_not_found`).

Fora desta mudança, e igual antes e depois dela: a conta que passou pelo reset
(`reset_user_conversation_atomic`) fica com o perfil vazio e marcada como não
concluída, mas **mantém a data de conclusão**
(`supabase/migrations/20260928150000_bodyflow_reset_keeps_plans.sql`). Por ter
data, não é conferida, e a função SQL responde
`409 onboarding_already_completed` ao cadastro que ela enviar: ela não consegue
refazer o cadastro pelo app. É um defeito anterior, a tratar em separado
(travado como está em `onboarding/route.test.ts`).

Código: `apps/admin/src/lib/mobile-api/onboarding-eligibility-guard.ts`,
chamado por `apps/admin/src/app/api/mobile/v1/onboarding/handler.ts` antes da
reserva da `Idempotency-Key` e da função SQL. Nenhuma rota nova, nenhuma
migration; a função SQL e o ledger de idempotência não mudaram. Testes:
`onboarding/route.test.ts` (rota inteira, com a função e o carregador reais,
sobre um banco em memória que segue as migrations da função de conclusão e do
ledger de idempotência) e `evaluation-access.test.ts` (conclusão recusada não
concede acesso).

### Objetivo atual

`GET /api/mobile/v1/protocol` é a leitura do objetivo para a tela de Perfil.
Exige entitlement, como `/today` (devolve as metas do dia).

```json
{
  "current_protocol": "recomposicao",
  "targets": { "calories": 1564, "protein_g": 121.5 },
  "welcome": {
    "protocol": "recomposicao",
    "paragraphs": ["Marina, a partir de agora você entra oficialmente na fase de recomposição corporal.\nIsso significa…", "…"]
  }
}
```

- `current_protocol`: o protocolo gravado no perfil (`recomposicao`,
  `ganho_massa` ou `manutencao`), o mesmo de `GET /profile`.
- `targets`: as metas da tela Hoje, lidas do mesmo estado diário de `GET /today`
  (`targets.calories_kcal` e `targets.protein_g`) e não recalculadas: a meta
  gravada na linha de hoje quando o dia já tem uma, senão a calculada do perfil.
  O objeto permanece presente; cada campo é `null` quando `/today` também não
  tem a respectiva meta. No fio, calorias usa `calories` (não `calories_kcal`).
- `welcome`: a mensagem de entrada do protocolo atual, igual à de
  `protocol_welcome`, no idioma da conta (`locale` de `/me`: `pt-BR`, `en-US` ou
  ausente = `pt-BR`) e com o nome da conta. Conta sem nome gravado recebe o
  texto sem o vocativo.
- **Conta sem protocolo** (cadastro ainda não concluído, ou perfil inexistente):
  `200` com `current_protocol: null` e `welcome: null`, como as outras leituras
  respondem o que ainda não existe. `targets` continua sendo o que `/today`
  responde para a conta. A rota não consulta a conclusão do cadastro: informa o
  que o perfil guarda.
- Idioma da conta fora de `pt-BR`/`en-US` → `409 protocol_locale_unsupported`
  (mesma convenção de `onboarding_locale_unsupported` e
  `coach_locale_unsupported`).
- Sem acesso ativo → `402 subscription_required`. Falha de leitura →
  `500 data_access_failed`.
- **Só leitura.** Não existe `POST`, `PATCH` nem campo de troca: a troca de
  objetivo não faz parte desta entrega (`docs/CALCULO-MPP.md` §10).

Código: `apps/admin/src/app/api/mobile/v1/protocol/handler.ts` e
`apps/admin/src/lib/mobile-api/protocol-service.ts`. Testes:
`protocol/route.test.ts` e `protocol-service.test.ts`.

O campo `country_confirmed` de `/me` indica se o país operacional já foi
confirmado. Propostas de refeição retornam `409 country_confirmation_required`
enquanto ele for falso; a API não usa o `BR` provisório de contas novas para
calcular silenciosamente a nutrição de pacientes de outro país. Enviar `country`
em `PATCH /me` confirma o país.

## Estado diário oficial

`GET /today` devolve a visão oficial usada pelo app. O cliente não soma refeições,
não recalcula metas, não incorpora exercício em `remaining_food_kcal` e não projeta
crédito do bloco para um dia ainda aberto.

Estrutura resumida:

```json
{
  "local_date": "2026-07-20",
  "protocol": "recomposicao",
  "targets": {
    "calories_kcal": 1935,
    "protein_g": 148,
    "source": "daily_snapshot",
    "calories_source": "daily_snapshot",
    "protein_source": "daily_snapshot"
  },
  "consumed": {
    "calories_kcal": 1200,
    "protein_g": 90,
    "carbs_g": 110,
    "fat_g": 42,
    "source": "daily_snapshot"
  },
  "remaining_food_kcal": 735,
  "food_excess_kcal": 0,
  "exercise_kcal": 300,
  "daily_balance_kcal": -1535,
  "daily_balance_reference_kcal": 2435,
  "daily_balance_includes_exercise": true,
  "daily_balance_status": "provisional",
  "protein_status": {
    "consumed_g": 90,
    "target_g": 148,
    "remaining_g": 58,
    "percentage": 61,
    "status": "below_target"
  },
  "meals": [],
  "workouts": [],
  "hydration": {
    "consumed_ml": 1500,
    "target_ml": 2200,
    "remaining_ml": 700,
    "percentage": 68,
    "status": "in_progress"
  },
  "supplements": {
    "availability": "available",
    "items": [
      {
        "id": "11111111-1111-4111-8111-111111111111",
        "name": "Creatina",
        "dose_text": "3 g",
        "origin": "professional",
        "reminders_enabled": true,
        "schedules": [
          {
            "id": "11111111-1111-4111-8111-111111111112",
            "local_time": "08:00",
            "weekdays": [0, 1, 2, 3, 4, 5, 6]
          }
        ],
        "occurrences": [
          {
            "reminder_rule_id": "11111111-1111-4111-8111-111111111112",
            "scheduled_for": "2026-07-20T11:00:00.000Z",
            "status": "taken",
            "last_action_at": "2026-07-20T11:05:00.000Z",
            "snoozed_until": null
          }
        ]
      }
    ]
  },
  "medications": {
    "availability": "not_configured",
    "items": []
  },
  "pending_actions": {
    "registrations": [],
    "meal_gaps": {
      "expected": ["cafe", "almoco", "jantar"],
      "registered": ["cafe", "almoco"],
      "skipped": [],
      "open": ["jantar"],
      "reliable": true,
      "source": "personalized_pattern",
      "active_days": 10
    }
  },
  "block_7700": {
    "enabled": true,
    "availability": "available",
    "target_kcal": 7700,
    "current_kcal": 2500,
    "percentage": 32,
    "completed_blocks": 1,
    "total_credited_kcal": 10200,
    "source": "user_progress"
  },
  "completion_status": {
    "status": "pending_information",
    "day_closed": false,
    "has_sufficient_data": null
  },
  "sources": {
    "targets": "daily_snapshot",
    "consumed": "daily_snapshot",
    "exercise": "daily_snapshot",
    "meals": "meal_logs",
    "workouts": "workout_logs",
    "hydration": "daily_snapshot",
    "hydration_target": "notification_preferences",
    "supplements": "routine_items_and_adherence_logs",
    "medications": "routine_items_and_adherence_logs",
    "pending_actions": "pending_registrations_and_meal_pattern",
    "block_7700": "user_progress"
  },
  "calculation_version": "bodyflow.daily-state.v3",
  "updated_at": "2026-07-20T14:05:00.000Z",
  "generated_at": "2026-07-20T15:00:00.000Z"
}
```

Semântica obrigatória:

- `remaining_food_kcal = max(meta - consumido, 0)`. Exercício não aumenta esse
  valor; `food_excess_kcal` informa o excedente de ingestão separadamente.
- `daily_balance_kcal = consumido - gasto do dia`, **por protocolo** (negativo =
  déficit, positivo = superávit; sempre inteiro). Regra dita pelo cliente em
  20/01/2026, 22/02/2026, 23/02/2026 e 09/03/2026; implementada em 2026-10-04 a
  pedido do Eduardo; confirmação do cliente pendente
  (`docs/CALCULO-MPP.md` §2c).
  - `recomposicao`: `consumido - (meta + déficit programado) - exercício`. O
    gasto de referência é `meta + déficit programado` (= BMR × 1,2); o déficit
    programado é o do perfil (`deficit_level`, 500 quando ausente), a mesma
    expressão do fechamento, e só é somado quando o `protocol` publicado é
    `recomposicao`. No exemplo: `1200 - (1935 + 500) - 300 = -1535`
    (antes da v3: `-1035`).
  - `ganho_massa`: `consumido - round(meta ÷ multiplicador)`, **sem** exercício.
    O multiplicador é `calc.ganho_massa_surplus_multiplier` (1,05), lido como
    número mesmo se a linha da configuração o guardar como texto. Meta 2980,
    consumido 541, exercício 322: referência 2838, saldo `-2297` (antes da v3:
    `-2761`). Comendo exatamente a meta, com ou sem treino: `+142`.
  - `manutencao`: `consumido - meta`, **sem** exercício. Meta 3044, consumido
    3044, exercício 400: `0` (antes da v3: `-400`).
  - `protocol` `null`: `consumido - meta - exercício`, como na v2.
  - O protocolo usado é o `protocol` publicado no mesmo payload: o da linha do
    dia quando ela o tem (dia fechado), senão o do perfil. O déficit programado
    é o desse protocolo. Dia fechado em `recomposicao` com o perfil já em
    `ganho_massa` (meta 1843, consumido 2076, exercício 565): `-832` contra
    2343 (antes da revisão de 2026-10-04: `-332` contra 1843).
  - **Dia de troca de protocolo:** a linha do dia guarda a primeira meta do
    dia. Quando essa meta está mais perto da meta que o perfil dá agora em
    OUTRO protocolo do que da meta do `protocol` publicado, o saldo daquele dia
    é o da v2 — `consumido - meta - exercício` — com
    `daily_balance_reference_kcal` = `targets.calories_kcal` e
    `daily_balance_includes_exercise` `true`; o `protocol` publicado não muda.
    Meta 2799 gravada em `ganho_massa`, perfil em `recomposicao` ao meio-dia,
    consumido 2500, sem exercício: `-299` (antes da revisão: `-799` contra
    3299). Um peso novo no dia não dispara isso (`docs/CALCULO-MPP.md` §2c diz
    exatamente o que é comparado). O cliente não precisa detectar o caso: basta
    renderizar os três campos.
- `daily_balance_reference_kcal` (aditivo, v3): o gasto de referência contra o
  qual `daily_balance_kcal` foi medido, **sem** o exercício. Sempre inteiro
  (também com `protocol` `null` e no dia de troca de protocolo); `null` quando
  não há meta.
- `daily_balance_includes_exercise` (aditivo, v3): `true` quando o exercício do
  dia é subtraído além da referência (`recomposicao`, `protocol` `null` e dia
  de troca de protocolo), `false` quando não é (`ganho_massa`, `manutencao`);
  `null` quando não há meta. Um cliente que não conhece o campo deve tratar a
  ausência como `true` (comportamento da v2). No código do app do iPhone
  (commit separado do mesmo dia, 9624cd5; ainda não verificado no aparelho) a
  linha é "Balanço do dia", o valor sai em palavras ("Déficit de N kcal" /
  "Superávit de N kcal") e a legenda vem deste campo (ausente = "Exercício
  incluído"). Um build anterior mostra o rótulo "Déficit líquido" com o número
  cru e a legenda fixa "Exercício incluído", incorreta em `ganho_massa` e
  `manutencao`. Continua aberto no app: o VoiceOver lê o valor duas vezes nessa
  linha; as frases da trilha e do tour sobre o bloco de 7.700 aparecem para
  todo protocolo; o app mostra o número do dia aberto (pendências no §2c do
  `docs/CALCULO-MPP.md`).
- `remaining_food_kcal`, `food_excess_kcal` e `exercise_kcal` **não mudaram** na
  v3: continuam contra a meta, sem exercício, em todo protocolo.
- O saldo é `provisional` durante o dia, `final` após fechamento válido e
  `insufficient_data` quando faltaram dados no fechamento. `GET /today` devolve
  sempre o dia em andamento: o número é do dia aberto e o bloco não recebe
  crédito antes do fechamento.
- `completion_status.status=insufficient_data` descreve qualidade insuficiente da
  informação. Não representa falha, punição ou falta de esforço do paciente.
- `user_skipped` aparece como `complete_with_explicit_skip`, porque a ausência foi
  confirmada pelo paciente.
- O bloco expõe somente `user_progress` já persistido. A API não soma um crédito
  especulativo do dia aberto. Quando `user_progress` não existe ou não pode ser
  comprovido, `availability` e `source` são `unavailable` e os campos de progresso
  são `null`; ausência de registro nunca é apresentada como progresso zero.
- `targets.source`, `consumed.source`, `block_7700.source` e `sources` identificam
  a origem operacional de cada seção.
- Cada item de `meals` é uma linha de `meal_logs` como gravada: `kcal`,
  `quantity_g` e macros são números com até duas casas decimais (ex.: `284.6`)
  e podem ser `null`, assim como `meal_type`. O cliente decodifica como decimal
  opcional e exibe sem arredondar; `null` é "indisponível", nunca `0`.
- Propostas pendentes expõem somente ID, tipo, horário e `meal_type`; texto bruto,
  mídia, IDs de provider e evidências internas não saem do backend.
- A meta de hidratação existe apenas quando foi configurada em
  `notification_preferences`. Sem meta, percentual e restante são `null`, e o
  estado é `not_recorded` ou `tracked_without_target`. Com meta, os estados são
  `not_started`, `in_progress` ou `target_reached`.
- Suplementos e medicamentos mostram somente itens ativos do próprio paciente,
  horários e todas as ocorrências exatas do dia local. Cada ocorrência é
  independente e usa `pending`, `taken`, `snoozed`, `skipped` ou `missed`;
  ausência de item é `not_configured`. A chave interna da ocorrência não é
  exposta, e dose, prescrição ou recomendação não são inferidas.
- Snapshot, refeições e treinos são lidos em uma única consulta relacional. O
  backend revalida a versão escalar do snapshot e também as fontes de meta de
  hidratação, itens de rotina e adesão diária. Se uma escrita concorrente alterar
  qualquer uma dessas fontes, a leitura é repetida uma vez; se continuar mudando,
  a API falha sem devolver dados de versões diferentes.

`calculation_version` versiona a semântica do agregador. Mudanças aditivas no DTO
podem manter a versão; mudança de fórmula ou significado incrementa a versão.
Quebra de estrutura exige uma nova versão HTTP. O app deve renderizar os números
do backend e usar a versão para telemetria, nunca reimplementar a fórmula.

Histórico da versão: `v1` — estado inicial; `v2` — contrato de suplementos e
medicamentos; `v3` (2026-10-04) — fórmula de `daily_balance_kcal` por protocolo
e os campos aditivos `daily_balance_reference_kcal` e
`daily_balance_includes_exercise`. Nenhuma rota, método ou campo existente
mudou de nome ou tipo; o manifesto de rotas do BFF é o mesmo. A v3 volta a v2
desligando `DAY_BALANCE_AGAINST_EXPENDITURE`
(`packages/core/src/engine/balance.ts`) e a constante de versão. A revisão de
2026-10-04 (protocolo efetivo com o déficit dele, dia de troca de protocolo,
referência sempre inteira, multiplicador lido como número) ficou dentro da v3:
nenhum campo novo, e a parte que muda número tem interruptor próprio,
`DAY_BALANCE_DAY_ROW_GUARD`
(`packages/core/src/engine/day-balance-inputs.ts`).

### Elegibilidade do Bloco 7.700 em Hoje e Progresso (Flow C3)

Alteração local de 2026-10-08, sem publicação nem migration. O objetivo atual
oficial é separado do protocolo histórico usado para calcular a energia do dia.

- `GET /today` acrescenta `current_protocol` do perfil já lido. Só os valores
  exatos `recomposicao`, `ganho_massa` e `manutencao` são reconhecidos; ausente
  ou inválido é `null`. `block_7700.enabled` passa a seguir esse campo: somente
  recomposição habilita. `protocol` mantém o significado do dia histórico.
  Nenhuma query nova em Hoje, nenhuma fórmula ou valor energético alterado.
- `GET /progress`, quando `data` existe, conserva os 12 campos persistidos e
  acrescenta `current_protocol: Protocol | null` e `block_7700_enabled: boolean`.
  A leitura seletiva de `user_profiles.current_protocol` e a de `user_progress`
  ocorrem em paralelo, com `user_id` autenticado nas duas. Não se aceita um
  objetivo vindo de body, mensagem ou snapshot para decidir a apresentação.
- Ausência de progresso mantém `data:null`. Perfil ausente/nulo/inválido
  produz `current_protocol:null` e flag `false`. Erro em qualquer query produz
  `500 data_access_failed`, inclusive com progresso ausente; não é fallback de
  objetivo. A rota conserva fechamento sob demanda antes dessas leituras.
- Flag desabilitada não zera saldo, percentual, contagem nem medalha histórica
  na resposta ou banco. O cliente deve esconder as apresentações do bloco.
  Não inferir elegibilidade do saldo ou de `protocol` histórico; servidor antigo
  sem os campos novos não prova elegibilidade. Decoders devem tolerar ausência,
  e app/servidor requerem integração e publicação conjunta para o aceite final.
- As fontes de perfil/progresso não são uma transação nem revalidadas juntas;
  não há garantia de atomicidade entre as leituras. A versão de cálculo continua
  `bodyflow.daily-state.v3`, pois as fórmulas e a energia histórica são iguais.

Oráculos: perfil ganho/snapshot recomposição conserva −832/ref2343/treino
incluído e oculta o bloco; o perfil recomposição com snapshot ganho o habilita
sem mudar a energia histórica. Saldo3850/blocos2/50%/total19250 e os 12 valores
de progresso (XP1240/nível2/seq3/recorde7/peso80/saldo3120/blocos4 e medalhas)
permanecem intactos nos fixtures. Testes: `flow-block-presentation.test.ts`,
`daily-state.test.ts`, `daily-state-service.test.ts`, `progress/route.test.ts`
e os vizinhos de `today`/fechamento concorrente.

Espelhos BFF em `apps/mobile-bff/src/app/api/mobile/v1/{today,progress}/route.ts`
reexportam as rotas oficiais; métodos/auth/envelopes/headers não mudam.
Gates: `verify:routes`, `verify:imports`, testes e build do BFF, e
`verify:build-surface`. Este contrato não comprova UI física nem fecha C3 inteiro.

**Consumo iOS (2026-10-08, alteração local).** Os dois decoders aceitam os
campos aditivos opcionais. A política de apresentação usa somente os dois
campos da mesma resposta: `recomposicao` + flag `true` habilita; `ganho_massa`
ou `manutencao` + flag `false` oculta e explica uma vez; ausência, `null`,
valor inválido ou combinação contraditória oculta sem inferir o objetivo.
Flag com tipo inválido continua erro de decoding, sem coerção.

Hoje oculta o card/nó do bloco; Progresso oculta suas métricas, gráfico,
link de detalhe e somente a medalha literal `Primeiro Bloco`. Os demais
dados e a identidade posicional das medalhas continuam intactos. Séries
antigas não autorizam o gráfico se o progresso atual for `data:null`.
O detalhe direto lê Hoje e publica política e valores como uma unidade;
retry/erro conserva essa unidade, e uma leitura antiga não restaura números
de recomposição após uma leitura atual inelegível. O contexto desconhecido
oferece recuperação sem apresentar números de bloco como válidos.

O tutorial usa o snapshot publicado de Hoje deste shell, sem leitura extra
nem persistência de objetivo. Atualizar fatos conserva oito etapas e posição;
um owner invalidado não atualiza fatos nem grava conclusão na nova sessão da
mesma conta. Preferência de tutorial continua separada dos dados de saúde.
Testes locais: `Block7700EligibilityBoundaryTests`, `Block7700TutorialTests`
e `Block7700EligibilityRenderingTests`, além das suítes vizinhas. Isso não
substitui a suíte integral, o UI runner, staging integrado e o smoke físico.

### Fechamento do dia sob demanda (ambiente de avaliação)

Em produção o dia é fechado pelo worker, de madrugada, e estas rotas só
leem. No ambiente de avaliação (staging) o worker serve só o processamento de
mídia, então nenhum dia fechava e `block_7700`, sequência, XP, nível e medalhas
ficavam parados. Para esse ambiente, `GET /today`, `GET /progress` e a consulta
inteira de status no Flow autenticado (C7, `docs/CALCULO-MPP.md` §10q) podem
fechar os dias passados da conta **antes** de ler. Regras e números:
`docs/CALCULO-MPP.md` §3a.

**Política Flow C3 do fechamento (2026-10-08).** Depois das três travas abaixo,
o wrapper passa a opção interna `block7700Policy: 'flow-recomposition-v1'`.
O fechamento lê o protocolo oficial do perfil: somente recomposição habilita
crédito e nova conquista de bloco. Ganho, manutenção e protocolo ausente ou
desconhecido recebem crédito zero, sem debitar ou normalizar os saldos antigos,
sem apagar medalhas antigas e sem adquirir uma medalha de bloco pendente.
XP, nível, sequência e outras medalhas permanecem. Nenhum DTO, parâmetro do
paciente, RPC ou migration muda. O script de staging aplica a mesma política
após seus filtros em simulação e aplicação; os callers sem opção e o worker
legado preservam o comportamento anterior. Dias já fechados não são refeitos.
Isso altera os números futuros de bloco após o fechamento; **não comprova
ocultação completa do bloco nas telas nem aceitação clínica**. O servidor
compartilhado do BFF importa este mesmo wrapper, sem cópia de rota nova;
verificar `verify:routes`, import closure e build antes de publicar.

**Conferência transacional mobile (2026-10-09, local).** O wrapper também passa
`finalizationFence: 'mobile-current-v1'`. A nova RPC backend-only
`finalize_mobile_daily_close_atomic` confere o fuso oficial, o perfil completo
usado no cálculo, a linha completa devolvida pela escrita condicional e os
campos/versão de progresso usados para calcular o próximo estado. Sob locks,
o relógio do banco decide se a data continua fechável; hora enviada pelo
cliente não autoriza fechar hoje. Mudança de contexto deixa a data pendente,
interrompe a varredura e não gera XP, zeramento de sequência ou telemetria de
fechamento. Somente uma linha realmente fechada é tratada como resolvida.
Ausência de progresso permite criar a linha padrão na mesma transação, sem
adotar ou sobrescrever a inicialização concorrente. Locks de linha são NOWAIT,
advisories são try-lock e a espera residual de conflito unique tem
`lock_timeout` de 2 s; isso não impõe um teto ao pedido HTTP inteiro.
A escrita preparatória do snapshot ocorre antes desta RPC e pode permanecer
na linha ainda aberta quando há recusa. O worker/finalizador legado e os
callers sem opção mantêm o contrato anterior. Migration e servidor devem ser
integrados juntos; testes locais não comprovam publicação no staging.

O caminho sem candidatos também usa uma RPC backend-only,
`reset_mobile_inactive_streak_atomic`: compara fuso, progresso/versão e a
última data fechável pelo relógio do banco antes de zerar a sequência. Uma
mudança de fuso/calendário ou progresso recusa sem evento. A atualização
legada continua igual; esta RPC não inicializa progresso ausente.

**Desligado por padrão.** São necessárias três travas, todas:

| Trava | Onde | Valor |
|---|---|---|
| 1 | variável `MOBILE_DAY_CLOSE_FROM` | primeira data local que pode ser fechada, `YYYY-MM-DD`. Ausente, vazia ou fora do formato = desligado, e **nenhuma consulta é feita** |
| 2 | variável `MOBILE_DAY_CLOSE_PROJECT_REF` | ref(s) de projeto permitidos, separados por vírgula. O ref é lido de `NEXT_PUBLIC_SUPABASE_URL` e precisa estar na lista. O ref de produção é recusado em código, mesmo se listado |
| 3 | a conta | sem número de WhatsApp e com fuso preenchido |

- **Nunca em produção.** As duas variáveis só devem existir no projeto Vercel
  do BFF de staging. Se forem copiadas por engano para um projeto que aponta
  para o banco de produção, a trava 2 recusa.
- **Chamadores exatos.** Today, Progress e o adapter autenticado de status
  Flow; este último somente após o gate de assinatura e a pergunta inteira
  reconhecida. Conversa normal, GET/history, replay publicado/cache HTTP e
  o invólucro comum das50rotas não chamam o fechamento.
- **O formato das respostas não muda.** Nenhum campo novo, nenhuma versão
  nova: os mesmos campos passam a trazer os valores de `user_progress` depois
  do fechamento.
- **Uma leitura que escreve.** Com as travas abertas, o primeiro pedido do dia
  grava em `daily_snapshots`, `user_progress` e `product_events`. Custo por
  pedido em idas ao banco, além da leitura de sempre (contado em
  `day-close-on-request.test.ts`): uma consulta (a conta); mais uma quando
  ontem já fechou; mais cinco, sem escrita, quando não há dia a fechar — ontem
  sem registro, ou só linhas de dia abertas com água, peso, suplemento ou
  medicamento, quantas forem (essas linhas não são visitadas) —, e mais duas
  escritas no pedido em que a sequência é zerada por inatividade; e, por dia
  fechado, até 18 (também entre 00:30 e 04:59 locais; 12 se o dia só tem
  mensagem), mais 3 leituras quando há data sem registro entre o último dia
  fechado e o dia, e mais uma leitura de progresso ao fim do pedido. Um pedido
  fecha no máximo 3 dias (61 idas ao banco para três dias seguidos) e não
  começa outro dia depois de 4 s; o resto fecha no pedido seguinte, em ordem.
- **Os 4 s não são um teto do tempo do pedido.** O limite é conferido só
  entre um dia e o seguinte: um dia em andamento termina e uma leitura em
  curso não é interrompida (nenhuma leitura do fechamento tem prazo de
  cancelamento). O cliente de banco (supabase-js 2.105.1) repete todo GET três
  vezes, esperando 1, 2 e 4 s, em erro de rede ou HTTP 503 ou 520: uma leitura
  do fechamento que falhe assim segura Today, Progress ou o status Flow por
  cerca de 7 s, e depois a rota responde com o que está gravado. HTTP 500 não
  é repetido; a RPC e as escritas também não. Pendência `RC F` em
  `docs/CALCULO-MPP.md` §3a; travado em
  `day-close-and-evaluation-access.read-retry.test.ts` (cliente real, `fetch`
  falso).
- **Falha não derruba o pedido.** Um erro no fechamento é registrado sem dado
  pessoal (`[mobile-api] day_close_failed`, com `request_id` e o nome do erro)
  e a rota responde normalmente com o que está gravado.
- **Não envia nada**: sem mensagem, sem push, sem evento, sem chamada a
  modelo. A agenda de reavaliação de 14 dias não é avançada por este caminho.
- Dia de **hoje** nunca fecha; **ontem** só fecha 30 minutos depois da
  meia-noite no fuso da conta.
- **Ontem fechado a partir das 05:00 locais mantém a meta já gravada no dia**
  (o fechador de produção só fecha ontem até 04:59; um peso registrado hoje
  de manhã não muda a meta de ontem). Entre 00:30 e 04:59 grava a meta do
  perfil, como a produção.
- **Em ordem, sem pular.** Se um dia muda enquanto é fechado (um registro
  retroativo confirmado naquele instante, ou `GET /today` e `GET /progress`
  chegando juntos num dia só com mensagem), o pedido para naquele dia e não
  fecha os posteriores; um pedido seguinte fecha todos, em ordem. O mesmo
  quando, durante o pedido, entra o primeiro registro de um dia ANTERIOR que
  estava vazio: o dia que estava sendo fechado não é finalizado, e o pedido
  seguinte fecha o anterior primeiro (`docs/CALCULO-MPP.md` §3a, regra 9).

Para fechar os dias que já estavam abertos antes de ligar o interruptor, há o
script de operador `scripts/close-open-days.ts` (simulação por padrão; recusa
qualquer banco que não seja o de staging, e recusa URL que não seja https).
Com `MOBILE_DAY_CLOSE_FROM` numa data posterior a esses dias, a API não toca
neles. A partir da raiz do repositório, com `SUPABASE_URL` e
`SUPABASE_SERVICE_ROLE_KEY` de staging já no shell (`tsx` só existe no pacote
`scripts`, por isso `pnpm tsx scripts/...` não inicia):

```
TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from 2026-09-22
```

Código: `apps/admin/src/lib/mobile-api/day-close-on-request.ts`. Testes:
`day-close-on-request.test.ts` (travas e custo por pedido),
`day-close-on-request.concurrent.test.ts` (as duas rotas ao mesmo tempo),
`day-close-and-evaluation-access.read-retry.test.ts` (leitura que falha) e os
`route.test.ts` de `today` e `progress`.
Nenhuma rota nova: esta peça não mudou o manifesto de rotas do BFF (48 na
época; 50 desde a conferência do cadastro e `GET /protocol`).

## Acesso de avaliação automático (ambiente de avaliação)

Sem entitlement, toda rota fora de conta, perfil, onboarding, entitlements,
persona, devices e preferências de notificação responde
`402 subscription_required`. O app não tem tela de compra, então até aqui cada
conta nova dependia de um operador conceder um trial por SQL
(`public.apply_entitlement_event`, `source = 'manual'`). Decisão do dono em
2026-10-05: conta nova no ambiente de teste já nasce com 30 dias de acesso.

Com o interruptor ligado, a **primeira** conclusão de onboarding da conta
(`POST /onboarding` no formato com `document_actions`, logo depois de a RPC
atômica `complete_mobile_onboarding_atomic` responder) concede um trial manual
pela mesma RPC do domínio.

**Desligado por padrão.** São necessárias quatro travas, todas:

| Trava | Onde | Valor |
|---|---|---|
| a | variável `MOBILE_EVALUATION_ACCESS_DAYS` | número de dias de acesso, inteiro de `1` a `90`, só dígitos; espaços nas pontas são ignorados (`" 30 "` vale 30). Ausente, vazia, `0`, `91`, `30.0`, `030` ou qualquer outro texto = desligado, e **nenhuma consulta é feita** |
| b | variável `MOBILE_EVALUATION_ACCESS_PROJECT_REF` | ref(s) de projeto permitidos, separados por vírgula. O ref é lido de `NEXT_PUBLIC_SUPABASE_URL` e precisa estar na lista. O ref de produção é recusado em código, mesmo se listado |
| c | variável `MOBILE_EVALUATION_ACCESS_ACTOR_ID` | uuid do ator de auditoria que o domínio exige em entitlement manual (`actor_id`). Não é segredo. Ausente, fora do formato ou só zeros = desligado |
| d | a conta | nenhum evento em `entitlement_events` (de qualquer chave) e decisão `no_entitlement` em `resolve_user_entitlement`. Acesso vencido ou bloqueado não é renovado, e conta que já tem acesso não é tocada |

O que é gravado, uma vez por conta. Chave, origem, status, plano e ambiente
são os dos quatro trials manuais ativos que já existem em staging (lidos lá em
2026-10-05 — só colunas e enums); o tipo de evento é o de três deles (o quarto
usa `grant`):

| Campo | Valor |
|---|---|
| `entitlement_key` | `bodyflow_full` |
| `source` | `manual` |
| `event_type` | `manual.qa.grant` |
| `status` / `plan` / `environment` | `active` / `trial` / `sandbox` |
| `reason_code` | `closed_evaluation_auto` (é o que distingue esta concessão das manuais) |
| `actor_id` | o uuid da trava c |
| `source_reference` | `closed-evaluation-auto:<id da conta>` |
| `provider_event_id` | `closed-evaluation-auto:<id da conta>:grant` |
| `starts_at` = `occurred_at` | a hora do servidor logo depois da conclusão |
| `access_expires_at` | `starts_at` + N × 24 h |
| `grace_expires_at` / `cancel_at_period_end` | `null` / `false` |

- **Nunca em produção.** As três variáveis só devem existir no projeto Vercel
  do BFF de staging. Se forem copiadas por engano para um projeto que aponta
  para o banco de produção, a trava b recusa.
- **Uma vez só.** Só a primeira conclusão concede: antes de gravar a
  conclusão, a API lê, numa só consulta, `user_profiles.onboarding_completed`,
  que precisa ser `false`, e `onboarding_completed_at`, que precisa estar
  vazio. Conta antiga marcada como concluída e sem data (a coluna da data foi
  criada sem preencher as contas que já existiam) não conta como primeira
  conclusão aqui, embora a RPC grave a data dela nessa hora (corrigido em
  2026-10-05; antes só a data era lida). Reenvio da mesma conclusão, os mesmos
  dados do cadastro com
  outra `Idempotency-Key` e aceite posterior de documentos novos não concedem
  de novo nem mudam o vencimento. Duas primeiras conclusões simultâneas terminam
  em uma concessão: o id do evento é derivado do id da conta e o banco
  responde `duplicate` à segunda.
- **O formato das respostas não muda.** `POST /onboarding` devolve os mesmos
  bytes com o interruptor ligado ou desligado. `GET /entitlements` passa a
  devolver `has_active_access: true`, `status: "active"`, `source: "manual"`,
  `plan: "trial"`, `reason: "valid_entitlement"` e o `access_expires_at`.
- **Custo por conclusão**, com as travas a–c abertas: uma leitura antes da
  conclusão (`user_profiles`); na primeira conclusão, mais uma leitura
  (`entitlement_events`), uma chamada a `resolve_user_entitlement` e a chamada
  a `apply_entitlement_event`. O formato parcial legado do mesmo POST não
  conclui onboarding e não consulta nada. Essas são as consultas da concessão.
  A conferência do objetivo ("Objetivo fora da regra na conclusão") faz as
  dela antes, com o interruptor ligado ou desligado, e uma conclusão que ela
  recusa não concede nada.
- **Falha não derruba o cadastro.** Um erro em qualquer uma dessas consultas é
  registrado sem dado pessoal (`[mobile-api] evaluation_access_failed`, com
  `request_id`, a etapa e o nome do erro) e o onboarding responde normalmente.
  A conta fica criada, sem acesso, e a concessão passa a ser manual. A
  resposta pode demorar: uma das duas leituras (GET) que falhe por erro de
  rede ou HTTP 503 ou 520 é repetida três vezes pelo cliente de banco (1, 2 e
  4 s), e o onboarding só responde depois, cerca de 7 s mais tarde (pendência
  `RC EA` abaixo).
- **Não envia nada**: sem mensagem, sem push, sem evento, sem chamada a
  modelo. O único efeito é a linha em `entitlement_events` e a linha em
  `user_entitlements`.
- **Só o handler do onboarding chama.** As outras rotas, o invólucro comum e
  o serviço de entitlement não conhecem o módulo.

O que não está coberto:

> RC EA — cenário conta que concluiu o onboarding ANTES de o interruptor ser ligado NÃO coberto nesta PR (pendência da audit 2026-10-04). Não recebe nada, nem reenviando a conclusão nem aceitando documentos novos depois: segue dependendo da concessão manual do operador. Vale também para a conta antiga marcada `onboarding_completed = true` com `onboarding_completed_at` nulo (2 contas em staging, contadas em 2026-10-05), que a RPC ainda grava como primeira conclusão. Travado em evaluation-access.test.ts.

> RC EA — cenário acesso vencido (N dias depois) ou bloqueado NÃO coberto nesta PR (pendência da audit 2026-10-04). Não é renovado por este caminho: a conta volta a receber 402 e a renovação é manual. Travado em evaluation-access.test.ts.

> RC EA — cenário compra ou assinatura pelo app NÃO coberto nesta PR (pendência da audit 2026-10-04). Não existe tela nem caminho de compra; `mobile_billing.available` segue `false`.

> RC EA — cenário nova tentativa depois de uma concessão que falhou, ou de uma função encerrada entre a conclusão e a concessão NÃO coberto nesta PR (pendência da audit 2026-10-04). A conta fica criada e sem acesso; reenviar a conclusão não concede (a conta já tem data de conclusão). A falha fica no log `[mobile-api] evaluation_access_failed` e a concessão é manual.

> RC EA — cenário funções `apply_entitlement_event` e `resolve_user_entitlement` REAIS do Postgres NÃO coberto nesta PR (pendência da audit 2026-10-04). Os testes usam um banco em memória que reproduz as duas; nada foi gravado em staging, e a primeira concessão real só acontece depois de ligar o interruptor.

> RC EA — cenário ator de auditoria que não existe NÃO coberto nesta PR (pendência da audit 2026-10-04). `actor_id` não tem chave estrangeira: o código só confere que a variável é um uuid diferente de zero, não que ele seja de um operador cadastrado.

> RC EA — cenário tela do iPhone (primeira tela depois do onboarding vista no aparelho com o interruptor ligado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho nem no simulador.

> RC EA — cenário relógio de outra instância da API atrasado em relação à que concedeu NÃO coberto nesta PR (pendência da audit 2026-10-04). O início do acesso é a hora da instância que concedeu; outra instância com o relógio atrás responde 402 até alcançá-la.

> RC EA — cenário a mesma pessoa criando outra conta (outro e-mail) NÃO coberto nesta PR (pendência da audit 2026-10-04). Cada conta nova que conclui o onboarding recebe os N dias; não há limite por pessoa nem por aparelho.

> RC EA — cenário leitura da concessão que falha por erro de rede ou HTTP 503 ou 520 NÃO coberto nesta PR (pendência da audit 2026-10-04). Nenhuma leitura tem prazo de cancelamento, e o cliente de banco (supabase-js 2.105.1) repete todo GET três vezes, esperando 1, 2 e 4 s: com o interruptor ligado, uma falha dessas na leitura de `user_profiles` (antes da conclusão) ou de `entitlement_events` (depois dela) atrasa a resposta de `POST /onboarding` em cerca de 7 s; a resposta sai com os mesmos bytes e nada é concedido. As duas RPCs (POST) não são repetidas. O atraso é travado no módulo, em day-close-and-evaluation-access.read-retry.test.ts (cliente real, `fetch` falso, erro de rede em cada uma das duas leituras); o handler aguarda as duas chamadas do módulo.

Código: `apps/admin/src/lib/mobile-api/evaluation-access.ts`, chamado só por
`apps/admin/src/app/api/mobile/v1/onboarding/handler.ts`. Testes:
`evaluation-access.test.ts` (handler, idempotência, serviço e repositório
reais sobre um banco em memória),
`day-close-and-evaluation-access.read-retry.test.ts` (leitura que falha) e
`evaluation-access.no-send.test.ts` (o
módulo só importa o invólucro de rota, não chama rede e só faz as duas
leituras e as duas RPCs acima). Nenhuma rota nova e nenhuma migration: esta
peça não mudou o manifesto de rotas do BFF (48 na época; 50 hoje).

## Suplementos, medicamentos e adesão de rotina

Estas rotas são app-first e apenas organizam lembretes e registros informados
pelo paciente. Elas não prescrevem, recomendam, interpretam nem alteram
medicamentos ou doses, e não fazem alegações clínicas sobre suplementos.

### Contrato comum de item e horário

`POST /supplements` e `POST /medications` aceitam o mesmo body estrito:

| Campo | Contrato |
|---|---|
| `name` | texto informado pelo paciente, trim, 1..200 caracteres |
| `dose_text` | texto informado pelo paciente, trim, 1..120 caracteres; não é interpretado |
| `origin` | `user`, `professional`, `protocol` ou `other` |
| `reminders_enabled` | habilita ou suprime push sem remover horários ou adesão manual |
| `schedules` | 1..16 horários lógicos únicos |
| `schedules[].local_time` | `HH:MM` no timezone armazenado do paciente |
| `schedules[].weekdays` | 1..7 dias entre 0 (domingo) e 6 (sábado) |

O servidor ordena e remove repetições dentro de `weekdays`; depois dessa
normalização, dois horários com o mesmo `local_time` e os mesmos dias são
rejeitados. Campos desconhecidos são rejeitados. O timezone e a data local vêm
do perfil autenticado e do relógio do servidor, nunca do body ou da query.
`origin=professional` é apenas metadado descritivo informado pelo paciente; não
comprova autoria ou revisão profissional.

Exemplo completo de criação de suplemento:

```http
POST /api/mobile/v1/supplements
Content-Type: application/json
Idempotency-Key: routine-supplement-create-0001
```

```json
{
  "name": "Creatina",
  "dose_text": "3 g",
  "origin": "professional",
  "reminders_enabled": true,
  "schedules": [
    {
      "local_time": "08:00",
      "weekdays": [0, 1, 2, 3, 4, 5, 6]
    },
    {
      "local_time": "20:00",
      "weekdays": [0, 1, 2, 3, 4, 5, 6]
    }
  ]
}
```

Resposta `201`:

```json
{
  "data": {
    "routine_item_id": "11111111-1111-4111-8111-111111111111",
    "version": 1
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-supplement-0001"
  }
}
```

Item, horários, evento técnico de criação e recibo idempotente são gravados na
mesma transação. Nome e dose não entram no evento técnico nem no recibo.

### Listagem e exemplo completo de suplemento

`GET /supplements` e `GET /medications` aceitam somente
`include_archived=true|false`, com padrão `false`. A resposta é ordenada por
`updated_at DESC, id DESC`; horários são ordenados por hora, dias e ID.
`frequency_summary.times_per_week` é a soma dos dias dos horários ativos, não
uma frequência persistida em paralelo.

Cada horário aplicável ao dia tem uma única `occurrence`. Em dia fora de
`weekdays`, ou quando o horário local não existe numa transição de DST,
`occurrence` é `null`. A identidade interna da ocorrência não é exposta nessa
listagem.

Exemplo completo de `GET /supplements`:

```json
{
  "data": {
    "local_date": "2026-07-22",
    "items": [
      {
        "id": "11111111-1111-4111-8111-111111111111",
        "item_type": "supplement",
        "name": "Creatina",
        "dose_text": "3 g",
        "origin": "professional",
        "reminders_enabled": true,
        "active": true,
        "archived_at": null,
        "version": 1,
        "created_at": "2026-07-22T10:00:00.000Z",
        "updated_at": "2026-07-22T10:00:00.000Z",
        "frequency_summary": {
          "times_per_week": 14
        },
        "schedules": [
          {
            "id": "11111111-1111-4111-8111-111111111112",
            "local_time": "08:00",
            "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "occurrence": {
              "scheduled_for": "2026-07-22T11:00:00.000Z",
              "status": "taken",
              "last_action_at": "2026-07-22T11:03:00.000Z",
              "snoozed_until": null
            }
          },
          {
            "id": "11111111-1111-4111-8111-111111111113",
            "local_time": "20:00",
            "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "occurrence": {
              "scheduled_for": "2026-07-22T23:00:00.000Z",
              "status": "pending",
              "last_action_at": null,
              "snoozed_until": null
            }
          }
        ]
      }
    ]
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-supplement-list-0001"
  }
}
```

### Aceite legal e exemplo completo de medicamento

Antes de criar qualquer medicamento, o app lê o texto localizado da versão
vigente:

```http
GET /api/mobile/v1/legal/medication-reminder-disclaimer
```

```json
{
  "data": {
    "document_key": "medication_reminder_disclaimer",
    "version": "2026-07-22.1",
    "locale": "pt-BR",
    "body": "O BodyFlow apenas organiza lembretes e registros. Ele não prescreve, recomenda nem altera medicamentos ou doses. Siga a orientação do profissional de saúde responsável.",
    "body_hash": "c7990a57fc61c29aa7025c77d4db489caf6f6d780913afeccc79811a287dd5f4",
    "required_from": "2026-07-22T00:00:00.000Z"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-medication-legal-get-0001"
  }
}
```

O aceite envia exatamente a versão e o hash exibidos:

```http
POST /api/mobile/v1/legal/medication-reminder-disclaimer/accept
Content-Type: application/json
Idempotency-Key: medication-legal-accept-0001
```

```json
{
  "accepted": true,
  "version": "2026-07-22.1",
  "body_hash": "c7990a57fc61c29aa7025c77d4db489caf6f6d780913afeccc79811a287dd5f4"
}
```

Resposta `200`:

```json
{
  "data": {
    "document_key": "medication_reminder_disclaimer",
    "version": "2026-07-22.1",
    "accepted_at": "2026-07-22T10:10:00.000Z"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-medication-legal-accept-0001"
  }
}
```

Aceites são append-only e não podem ser editados ou excluídos pela API do
paciente. Versão ou hash que deixou de ser vigente retorna
`409 medication_disclaimer_version_stale`. A criação do medicamento verifica o
aceite vigente dentro da mesma transação que cria item e horários.

Sem aceite, `POST /medications` retorna `428` apenas com a identidade necessária
para recarregar a rota legal, sem texto ou hash:

```json
{
  "error": {
    "code": "medication_disclaimer_required",
    "message": "Medication disclaimer acceptance is required",
    "request_id": "request-medication-create-0001",
    "details": {
      "document_key": "medication_reminder_disclaimer",
      "version": "2026-07-22.1"
    }
  }
}
```

Depois do aceite, exemplo completo de criação:

```http
POST /api/mobile/v1/medications
Content-Type: application/json
Idempotency-Key: routine-medication-create-0001
```

```json
{
  "name": "Medicamento cadastrado",
  "dose_text": "1 comprimido",
  "origin": "professional",
  "reminders_enabled": true,
  "schedules": [
    {
      "local_time": "09:00",
      "weekdays": [0, 1, 2, 3, 4, 5, 6]
    }
  ]
}
```

Resposta `201`:

```json
{
  "data": {
    "routine_item_id": "22222222-2222-4222-8222-222222222221",
    "version": 1
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-medication-0001"
  }
}
```

Exemplo completo de `GET /medications`:

```json
{
  "data": {
    "local_date": "2026-07-22",
    "items": [
      {
        "id": "22222222-2222-4222-8222-222222222221",
        "item_type": "medication",
        "name": "Medicamento cadastrado",
        "dose_text": "1 comprimido",
        "origin": "professional",
        "reminders_enabled": true,
        "active": true,
        "archived_at": null,
        "version": 1,
        "created_at": "2026-07-22T10:15:00.000Z",
        "updated_at": "2026-07-22T10:15:00.000Z",
        "frequency_summary": {
          "times_per_week": 7
        },
        "schedules": [
          {
            "id": "22222222-2222-4222-8222-222222222222",
            "local_time": "09:00",
            "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "occurrence": {
              "scheduled_for": "2026-07-22T12:00:00.000Z",
              "status": "pending",
              "last_action_at": null,
              "snoozed_until": null
            }
          }
        ]
      }
    ]
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-medication-list-0001"
  }
}
```

Nome e dose nos exemplos são dados controlados pelo paciente, não instruções do
BodyFlow.

### Atualização otimista e histórico de horários

`PATCH /supplements/:id` e `PATCH /medications/:id` exigem `expected_version`
positivo e pelo menos um campo mutável entre `name`, `dose_text`, `origin`,
`reminders_enabled` e `schedules`:

```json
{
  "expected_version": 1,
  "reminders_enabled": false,
  "schedules": [
    {
      "local_time": "08:30",
      "weekdays": [1, 2, 3, 4, 5]
    }
  ]
}
```

Resposta `200`:

```json
{
  "data": {
    "routine_item_id": "11111111-1111-4111-8111-111111111111",
    "version": 2
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-patch-0001"
  }
}
```

Versão divergente retorna `409 routine_item_version_conflict` sem alterar item,
horários ou versão. Cada mutação aceita incrementa `version` exatamente uma vez.
Horário lógico inalterado conserva seu ID; horário alterado é desativado e um
novo registro recebe outro ID. A API nunca reescreve a hora ou os dias de uma
regra histórica, de modo que logs antigos continuam referenciando a identidade
original.

### Archive

`DELETE` não remove linhas. Ele exige body `{}`, arquiva item, define
`active=false`, define `reminders_enabled=false`, incrementa a versão e desativa
todos os horários ativos na mesma transação:

```http
DELETE /api/mobile/v1/supplements/11111111-1111-4111-8111-111111111111
Content-Type: application/json
Idempotency-Key: routine-supplement-archive-0001
```

```json
{}
```

Resposta `200`:

```json
{
  "data": {
    "routine_item_id": "11111111-1111-4111-8111-111111111111",
    "version": 3,
    "archived_at": "2026-07-22T18:00:00.000Z"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-archive-0001"
  }
}
```

Itens arquivados somem da listagem padrão; `include_archived=true` os inclui para
telas históricas. Logs, regras desativadas, aceite legal, eventos e entregas
permanecem. Nenhum novo lembrete ou ação ordinária é aceito. O retry da mesma
operação deve reutilizar a mesma `Idempotency-Key` e devolve o resultado original,
inclusive quando a transação de domínio concluiu e o ledger HTTP falhou depois.
Uma chave diferente representa outra mutação; um item já arquivado fica
inacessível e retorna o mesmo `404` opaco.

### Ocorrência exata e ações

Uma ocorrência é identificada internamente por paciente, item/tipo,
`reminder_rule_id` e o instante UTC original `scheduled_for`. O banco deriva uma
chave estável SHA-256 da regra e desse instante. O cliente informa a regra e o
instante original, mas nunca envia `occurrence_key`. Snooze não muda essa
identidade: o follow-up continua ligado ao `scheduled_for` original.

`POST /supplements/:id/log` e `POST /medications/:id/log` aceitam exatamente:

```json
{
  "status": "snoozed",
  "reminder_rule_id": "11111111-1111-4111-8111-111111111113",
  "scheduled_for": "2026-07-22T23:00:00.000Z",
  "occurred_at": "2026-07-22T23:01:00.000Z",
  "snoozed_until": "2026-07-22T23:31:00.000Z"
}
```

Resposta `200`:

```json
{
  "data": {
    "adherence_log_id": "11111111-1111-4111-8111-111111111114",
    "occurrence_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "item_type": "supplement",
    "status": "snoozed"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-log-0001"
  }
}
```

Regras da ação:

- o cliente pode enviar somente `taken`, `snoozed` ou `skipped`;
- `occurred_at` aceita a janela offline de sete dias anteriores e até cinco
  minutos no futuro em relação ao servidor;
- `scheduled_for` não pode estar depois do `occurred_at` efetivo nem apontar
  para uma ocorrência futura ou anterior à ativação histórica da regra;
- `snoozed_until` é obrigatório somente para `snoozed`, deve ser posterior a
  `occurred_at` e cair na mesma data local da ocorrência original;
- os presets de produto são 15, 30 e 60 minutos; horário customizado é aceito se
  cumprir a mesma restrição de data local;
- item, tipo, ownership, regra, weekday, hora local, round-trip DST e intervalo
  de ativação do `scheduled_for` são revalidados contra o snapshot histórico;
- `source`, `occurrence_key`, `missed` e `supersedes_log_id` não são campos de
  entrada;
- a mesma chave e o mesmo payload devolvem o log original; a mesma chave com
  qualquer identidade, status ou instante diferente retorna conflito;
- uma ação em 08:00 nunca resolve a ocorrência das 20:00 do mesmo item.

Os wrappers legados `/routine/supplements/:id/taken` e
`/routine/medications/:id/taken` mantêm o body `{ "occurred_at": "..." }`.
Eles resolvem somente quando existe exatamente uma ocorrência elegível. Zero
candidatos retorna `404`; dois ou mais retornam
`409 routine_occurrence_ambiguous`. O servidor nunca escolhe a mais próxima ou a
primeira silenciosamente. Clientes novos usam `/:id/log`.

### Estados e transições

`pending` é derivado de um horário elegível sem ação e nunca é persistido como
evento falso. A ação append-only mais recente, ordenada por `created_at` e ID,
determina o estado. `occurred_at` preserva o instante reportado para auditoria e
ordenação do histórico, mas não decide qual transição foi anexada por último:

```text
pending -> taken
pending -> skipped
pending -> snoozed -> taken
pending -> snoozed -> skipped
pending -> snoozed -> snoozed
pending -> missed -> taken
```

`skipped` exige ação explícita do paciente; silêncio nunca vira skip. `taken` e
`skipped` são terminais para pedidos ordinários. Depois do fim da data local,
uma ocorrência sem resolução, inclusive um snooze ainda aberto, é lida como
`missed`: nesse estado derivado, `last_action_at` é o fim exato do dia no
timezone do snapshot e `snoozed_until` é `null`. Um finalizador backend persiste
redundantemente um único log `missed` idempotente para auditoria e operação;
atraso desse worker não muda o estado público derivado. Um `taken` ou `skipped`
terminal anexado antes do fim do dia continua terminal depois dele.

O paciente pode corrigir um `missed` automático para `taken` até sete dias após
o fim do dia da ocorrência. A correção cria outro log apontando para o `missed`;
nenhuma linha anterior é alterada ou excluída. O cliente não pode criar
`missed`. Se um `taken` elegível chega depois do fim do dia antes do finalizador,
o backend cria ou reutiliza atomicamente o `missed` singleton e grava o `taken`
como correção vinculada. Mudanças posteriores de timezone, archive ou desativação
não invalidam uma ocorrência que pertencia ao snapshot histórico.

### Histórico por cursor

`GET /supplements/:id/history` e `GET /medications/:id/history` aceitam:

| Query | Regra |
|---|---|
| `limit` | inteiro 1..50; padrão 20 |
| `cursor` | base64url opaco, canônico e limitado a 512 caracteres |

A ordenação keyset é `(occurred_at DESC, id DESC)`. `next_cursor` representa o
último log devolvido somente quando existe outra página. O cliente deve tratar o
cursor como opaco; cursor malformado retorna `422 validation_failed`. A
paginação permanece estável para empates de timestamp pelo ID único.

Exemplo com `missed` e correção append-only:

```json
{
  "data": {
    "items": [
      {
        "id": "11111111-1111-4111-8111-111111111116",
        "routine_item_id": "11111111-1111-4111-8111-111111111111",
        "item_type": "supplement",
        "status": "taken",
        "reminder_rule_id": "11111111-1111-4111-8111-111111111112",
        "scheduled_for": "2026-07-22T11:00:00.000Z",
        "occurred_at": "2026-07-23T12:00:00.000Z",
        "snoozed_until": null,
        "source": "patient",
        "supersedes_log_id": "11111111-1111-4111-8111-111111111115",
        "created_at": "2026-07-23T12:00:01.000Z"
      },
      {
        "id": "11111111-1111-4111-8111-111111111115",
        "routine_item_id": "11111111-1111-4111-8111-111111111111",
        "item_type": "supplement",
        "status": "missed",
        "reminder_rule_id": "11111111-1111-4111-8111-111111111112",
        "scheduled_for": "2026-07-22T11:00:00.000Z",
        "occurred_at": "2026-07-23T03:00:00.000Z",
        "snoozed_until": null,
        "source": "system",
        "supersedes_log_id": null,
        "created_at": "2026-07-23T03:00:01.000Z"
      }
    ],
    "next_cursor": "eyJvY2N1cnJlZEF0IjoiMjAyNi0wNy0yM1QwMzowMDowMC4wMDBaIiwibG9nSWQiOiIxMTExMTExMS0xMTExLTQxMTEtODExMS0xMTExMTExMTExMTUifQ"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-routine-history-0001"
  }
}
```

Histórico de item de outro paciente, ID inexistente e tipo da rota divergente
retornam o mesmo `404 routine_item_not_found`, sem revelar existência.

### Preview privado de push

`GET /notification-preferences` inclui `routine_preview_mode`. Sem linha
persistida, o padrão é `private`:

```json
{
  "data": {
    "push_enabled": true,
    "quiet_hours": null,
    "daily_push_limit": 8,
    "hydration_target_ml": null,
    "routine_preview_mode": "private",
    "created_at": null,
    "updated_at": null
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-notification-preferences-0001"
  }
}
```

`PATCH /notification-preferences` aceita um dos modos:

| Modo | Conteúdo permitido no preview |
|---|---|
| `private` | lembrete genérico de rotina; padrão |
| `name` | somente o nome informado pelo paciente |
| `name_and_dose` | nome e dose textual informados pelo paciente |

Exemplo de patch estrito:

```json
{
  "routine_preview_mode": "name"
}
```

O modo afeta apenas a futura renderização do push. Eventos Inngest e métricas
carregam IDs e timestamps técnicos; a outbox guarda somente o modo controlado,
nunca nome ou dose. Lembretes de medicamento usam template neutro e
`personality=default`, independentemente da persona do coach. Nesta fase,
`queued` significa apenas linha na outbox: não existe envio real ao APNs.

### Idempotência e falhas parciais

Além do ledger HTTP de 24 horas, create/update/archive/aceite mantêm recibo
técnico transacional e ações mantêm unicidade append-only por paciente/chave.
Assim, retry com a mesma chave e payload recupera o resultado mesmo quando a
transação de domínio concluiu mas a finalização do ledger HTTP falhou. O recibo
armazena somente IDs, versão, timestamps de resultado e hash técnico; nunca body
bruto, nome, dose, texto legal ou token.

O cliente deve manter a mesma chave até receber resposta conclusiva. Reutilizar
a chave para método, rota ou payload diferente retorna
`409 idempotency_key_conflict`; pedido simultâneo ainda aberto retorna
`409 idempotency_request_in_progress`. `Idempotency-Replayed: true` identifica
replay atendido pelo ledger HTTP vigente.

### Erros estáveis da rotina

| HTTP | `error.code` | Quando |
|---|---|---|
| `400` | `missing_idempotency_key` | mutação sem header obrigatório |
| `404` | `routine_item_not_found` | item/ocorrência inacessível, inativo, de outro tipo ou de outro paciente |
| `404` | `legal_document_not_available` | não existe texto legal vigente para o locale do paciente |
| `409` | `routine_item_version_conflict` | `expected_version` ficou desatualizado |
| `409` | `routine_schedule_conflict` | rota genérica tentou criar/alterar regra de suplemento/medicamento, ou o repositório/RPC de CRUD do item detectou conflito real de agenda após a validação do request, como concorrência ou conflito de negócio |
| `409` | `routine_occurrence_ambiguous` | wrapper legado encontrou mais de uma ocorrência elegível |
| `409` | `routine_transition_invalid` | ação terminal ou fora de ordem seria reescrita |
| `409` | `idempotency_key_conflict` | chave reutilizada com outra operação ou payload |
| `409` | `idempotency_request_in_progress` | mesma chave ainda está em processamento |
| `409` | `medication_disclaimer_version_stale` | aceite não corresponde à versão/hash legal vigente |
| `415` | `unsupported_media_type` | rota com body sem JSON |
| `422` | `validation_failed` | body/query/cursor estrito inválido, inclusive horários lógicos duplicados detectados pelo schema do item |
| `422` | `occurred_at_out_of_range` | instante fora da janela offline/futuro |
| `422` | `routine_schedule_invalid` | horário inválido ou duplicado do item alcançou e foi rejeitado pela validação defensiva de domínio/storage |
| `422` | `routine_snooze_invalid` | snooze não futuro ou fora da data local original |
| `428` | `medication_disclaimer_required` | criação exige aceite da chave/versão retornadas em `details` |

Razões internas mais específicas de item inativo, tipo divergente e ocorrência
inválida são normalizadas para o `404` acima. O BFF não devolve mensagem SQL,
nome de RPC, existência cross-user, texto legal, nome do item ou dose em erros.

## Conteúdo educativo

As quatro rotas exigem o bearer de um paciente ativo e confirmado. O BFF deriva
`locale`, protocolo, plano e personalidade das fontes canônicas do paciente;
nenhum desses atributos é aceito na query ou no body. Locales suportados são
exatamente `pt-BR` e `en-US`, sem fallback entre idiomas. Ausência de uma versão
publicada no locale exato produz feed vazio ou o mesmo `404` opaco de conteúdo
inexistente.

Uma publicação arquivada fica invisível globalmente. Entre versões publicadas do
mesmo locale cujo `publish_at` já venceu no relógio do banco, vale a de maior
`version`. Assim, uma versão nova publicada imediatamente não volta a ser
substituída por um agendamento mais antigo quando o horário deste vencer. Uma
substituição ainda em rascunho, revisão ou antes do próprio agendamento não
retira a versão viva atual.

### Listagem

`GET /content` aceita somente:

| Query | Valores | Regra |
|---|---|---|
| `surface` | `today`, `library`, `saved` | opcional; padrão `library` |
| `category` | uma categoria do contrato | opcional |
| `limit` | inteiro de 1 a 50 | opcional; padrão `20` |
| `cursor` | string opaca de 1 a 512 caracteres | opcional; usar somente valor emitido pelo servidor |

`locale` não é uma query válida. Parâmetros desconhecidos, repetidos ou fora dos
limites retornam `422 validation_failed`. Um cursor com formato ou payload
inválido também retorna `422 validation_failed`, com o campo `cursor` nos
detalhes. A ordem estável é `publish_at DESC, publication_id DESC`; o cursor
opaco representa esse par.

Semântica das superfícies:

- `today`: somente itens elegíveis com `featured_today=true`;
- `library`: todos os itens atualmente elegíveis;
- `saved`: somente itens elegíveis cujo estado salvo está ativo.

O filtro de categoria é aplicado depois da elegibilidade. Categorias válidas:
`weight_loss`, `hypertrophy`, `nutrition`, `training`, `neuroscience`,
`habit_formation`, `cardiovascular_health`, `hydration`, `supplementation`,
`sleep` e `using_bodyflow`.

Exemplo sem dados reais:

```http
GET /api/mobile/v1/content?surface=library&category=sleep&limit=2 HTTP/1.1
Authorization: Bearer <supabase_access_token>
X-Request-Id: mobile-docs-0001
```

```json
{
  "data": {
    "items": [
      {
        "publication_id": "00000000-0000-4000-8000-000000000101",
        "slug": "rotina-de-sono",
        "locale": "pt-BR",
        "title": "Rotina de sono",
        "excerpt": "Um exemplo sintético de resumo educativo para o aplicativo.",
        "category": "sleep",
        "tags": ["sono", "rotina"],
        "reading_time_minutes": 3,
        "publish_at": "2026-07-21T12:00:00.000Z",
        "featured_today": false,
        "version": 4,
        "saved": true,
        "completed": false,
        "cover": {
          "url": "/api/mobile/v1/content/covers/<capability-opaca>",
          "expires_at": "2026-07-21T12:05:00.000Z"
        }
      }
    ],
    "next_cursor": "<cursor-opaco-ou-null>"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "mobile-docs-0001"
  }
}
```

O DTO de item usa somente `snake_case` e contém exatamente os campos mostrados.
`cover` é `{ "url", "expires_at" }` ou `null`. Bucket e object path nunca saem
do BFF.

### Detalhe

`GET /content/:id` recebe o UUID de `publication_id`. A resposta repete todos os
campos do item do feed e acrescenta somente `body_markdown`:

```http
GET /api/mobile/v1/content/00000000-0000-4000-8000-000000000101 HTTP/1.1
Authorization: Bearer <supabase_access_token>
```

```json
{
  "data": {
    "publication_id": "00000000-0000-4000-8000-000000000101",
    "slug": "rotina-de-sono",
    "locale": "pt-BR",
    "title": "Rotina de sono",
    "excerpt": "Um exemplo sintético de resumo educativo para o aplicativo.",
    "category": "sleep",
    "tags": ["sono", "rotina"],
    "reading_time_minutes": 3,
    "publish_at": "2026-07-21T12:00:00.000Z",
    "featured_today": false,
    "version": 4,
    "saved": true,
    "completed": false,
    "cover": null,
    "body_markdown": "## Exemplo\n\nEste conteúdo sintético existe apenas para documentar o formato do contrato móvel, sem representar orientação real ou dado de paciente."
  },
  "meta": {
    "api_version": "v1",
    "request_id": "<request-id>"
  }
}
```

Publicação ausente, arquivada, futura, de outro locale ou inelegível por segmento
retorna indistintamente `404 content_not_found`. O contrato não revela qual
condição falhou.

### Eventos de leitura

`POST /content/:id/read` exige `Content-Type: application/json`,
`Idempotency-Key` e body JSON estrito, sem campos extras ou chaves duplicadas:

```http
POST /api/mobile/v1/content/00000000-0000-4000-8000-000000000101/read HTTP/1.1
Authorization: Bearer <supabase_access_token>
Content-Type: application/json
Idempotency-Key: mobile-content-open-0001

{
  "event": "opened",
  "origin": "library",
  "version": 4
}
```

- `event`: `impression`, `opened` ou `completed`;
- `origin`: `today`, `library` ou `push`;
- `version`: inteiro de 1 a 2.147.483.647 e igual à versão localizada visível.

`impression` registra a exibição; `opened` atualiza primeira/última abertura;
`completed` marca conclusão da versão atual. Eventos aceitos fora de ordem não
regredem a última abertura, conclusão, versão ou origem já consolidada; uma
abertura atrasada pode apenas antecipar `first_opened_at`. A resposta consolidada
é:

```json
{
  "data": {
    "publication_id": "00000000-0000-4000-8000-000000000101",
    "version": 4,
    "saved": true,
    "completed": false,
    "changed": true,
    "replayed": false
  },
  "meta": {
    "api_version": "v1",
    "request_id": "<request-id>"
  }
}
```

### Salvos

`POST /content/:id/save` possui os mesmos headers e usa body JSON estrito:

```json
{
  "saved": false,
  "version": 4
}
```

O BFF fixa internamente `origin=library`; `origin` enviado pelo cliente é campo
extra e falha na validação. A resposta usa o mesmo DTO de estado de leitura:
`publication_id`, `version`, `saved`, `completed`, `changed` e `replayed`.
Solicitar o estado já vigente é sucesso com `changed=false`, sem novo evento.
Salvar persiste entre revisões; `completed` só é verdadeiro quando a conclusão
se refere à versão localizada atualmente visível. Um save/unsave atrasado é
aceito no ledger, mas não pode regredir o estado consolidado; nesse caso a
resposta devolve o valor efetivo com `changed=false`.

### Elegibilidade e targeting

Targeting pertence à versão aprovada. Protocolo, plano e personalidade são três
dimensões independentes: array vazio na dimensão editorial significa wildcard;
array não vazio exige uma correspondência. As dimensões configuradas combinam
com AND. Paciente sem protocolo, assinatura ativa/trial não expirada ou
personalidade selecionada só corresponde ao wildcard da respectiva dimensão.
`balanced` não é personalidade selecionável para targeting.

### Idempotência de conteúdo

As mutações têm duas camadas:

1. O wrapper mobile exige `Idempotency-Key` de 8 a 128 caracteres na allowlist
   `A-Z a-z 0-9 . _ : -`, com escopo `(patient, key)`, hash do método, rota e
   payload e ledger de 24 horas.
2. As RPCs de evento/save recebem a mesma chave, armazenam seu hash SHA-256 e
   deduplicam por paciente no banco. Isso cobre o caso em que a mutação foi
   commitada, mas o wrapper não conseguiu concluir seu próprio claim.

Retry idêntico no wrapper reproduz status e envelope com o novo `request_id` e
header `Idempotency-Replayed: true`. O campo `data.replayed` descreve o replay da
camada de evento no banco e, por isso, pode continuar `false` quando apenas o
wrapper reproduziu a primeira resposta. Replay reconhecido no banco retorna
`changed=false` e `replayed=true`. Reutilizar a chave com outra operação,
publicação, versão, evento, origem ou valor salvo retorna conflito.

### Capas privadas

`cover.url` é uma capability opaca do proxy BFF, vinculada a paciente,
`publication_id` e `version`, com TTL de 300 segundos. O `GET` dessa URL também
exige bearer. Antes do download, o proxy revalida o mesmo paciente, a
elegibilidade atual, o arquivo global, a versão e a presença da capa. Token
inválido/expirado, troca de usuário, perda de elegibilidade, troca de versão,
objeto ausente ou MIME não permitido retornam o mesmo `404
content_cover_not_found`; nenhum bucket ou path é revelado.

JSON continua com `Cache-Control: no-store` e `Vary: Authorization`. A imagem
válida usa `Cache-Control: private, max-age=<segundos-restantes>`,
`Vary: Authorization`, `X-Content-Type-Options: nosniff`, `X-Request-Id` e o
`Content-Type` validado (`image/jpeg`, `image/png` ou `image/webp`).

### Erros

| HTTP | `error.code` | Quando ocorre |
|---:|---|---|
| `400` | `missing_idempotency_key` | mutação sem `Idempotency-Key` |
| `400` | `invalid_idempotency_key` | chave fora de 8..128 ou da allowlist |
| `400` | `invalid_json` | body ausente, UTF-8/JSON inválido ou chave JSON duplicada |
| `401` | `missing_access_token`, `invalid_access_token` | bearer ausente ou inválido |
| `403` | `email_not_confirmed`, `patient_admin_account_conflict`, `patient_profile_unavailable`, `patient_account_inactive` | identidade não autorizada como paciente ativo |
| `404` | `content_not_found` | detalhe ou mutação não visível, sem divulgar a causa |
| `404` | `content_cover_not_found` | capability/capa indisponível de forma opaca |
| `409` | `identity_migration_required` | identidade legada exige migração revisada |
| `409` | `content_version_changed` | `version` não é mais a versão visível |
| `409` | `idempotency_key_conflict` | chave reutilizada com semântica diferente |
| `409` | `idempotency_request_in_progress` | claim idempotente concorrente ainda aberto |
| `413` | `request_too_large` | body JSON acima de 64 KiB |
| `415` | `unsupported_media_type` | mutação sem `application/json` estrito |
| `422` | `validation_failed` | UUID, query, enum, tipo, campo extra, limite ou cursor inválido |
| `500` | `internal_error` | falha interna opaca |

Falhas de autenticação também podem produzir `500 patient_bootstrap_failed` se
a inicialização do perfil falhar. Todos os erros usam o envelope padrão com
`request_id`; detalhes técnicos, artigo, token, path e identidade do paciente
não aparecem na resposta.

## Coach, mensagens recorrentes e mascote

### Personalidade

`GET /coach/persona` retorna somente o estado público necessário ao app:

```json
{
  "data": {
    "selected": null,
    "effective": "balanced",
    "options": [
      {
        "code": "focus",
        "name": "Focus",
        "description": "Direta, objetiva e respeitosa."
      },
      {
        "code": "impulse",
        "name": "Impulse",
        "description": "Energética, positiva e sem exageros."
      },
      {
        "code": "zen",
        "name": "Zen",
        "description": "Calma, clara e sem julgamento."
      }
    ],
    "mascot": {
      "state": "inactive",
      "changed_at": null
    },
    "contract_version": "bodyflow.coach-persona.v1"
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-id"
  }
}
```

`selected` é `focus`, `impulse`, `zen` ou `null`. Quando não há escolha,
`effective` é `balanced`, o fallback interno neutro. `balanced` nunca aparece em
`options` e não é aceito em escrita. Nomes e descrições seguem o `locale` do
perfil (`pt-BR` ou `en-US`); locale sem catálogo retorna
`409 coach_locale_unsupported`.

`PATCH /coach/persona` exige `Idempotency-Key` e body estrito:

```json
{
  "persona": "focus"
}
```

A identidade vem exclusivamente do bearer token verificado. Campos extras,
`balanced` e valores desconhecidos são rejeitados. Retry idêntico reproduz a
resposta sem escrever novamente. A mudança vale para seleções futuras e não
reescreve mensagens já escolhidas.

### Preferência no prompt conversacional do Flow (C9, 2026-10-08)

Cada contexto de uma nova execução autenticada `mobile_flow` lê somente
`user_id, personality_code` de `user_coach_preferences`, filtrado pelo paciente
autenticado. O owner retornado também precisa coincidir. Os códigos válidos
continuam sendo `focus`, `impulse` e `zen`, pelo enum público existente.

Nos turnos que usam modelo, uma linha de tom entra apenas no bloco variável do
prompt. Prefixo fixo/cache, idioma, ferramentas, fatos, metas, restrições e
confirmações permanecem iguais. Focus é direto sem bronca, Impulse positivo sem
pressão, Zen acolhedor e preciso. Copy e amostras reais ainda têm aceite próprio;
o teste de composição não prova obediência do modelo.

Sem escolha, não se atribui Focus nem outro estilo ao paciente: permanece o tom
base, sem linha adicional. Forma/código/owner inválido ou falha dessa leitura
opcional também não acrescentam estilo, mas são distinguíveis internamente;
diagnóstico usa somente motivos fechados, sem IDs, row ou erro bruto. Leituras
essenciais de usuário/perfil continuam interrompendo a execução quando falham,
inclusive enquanto a leitura opcional está pendente. Não há timeout novo desta
consulta; uma consulta que não conclui continua sujeita ao limite geral do turno.

A preferência não tem cache entre contas/turnos nem escrita de reparo. Uma
execução posterior recebe a escolha atual; replay idempotente e histórico não
recebem personalização retroativa. Respostas determinísticas existentes não
chamam modelo para mudar o tom. O canal legado não consulta essa preferência.
API/UI/catálogo de mensagens recorrentes não mudam. C2 e a comparação das seis
regras live permanecem em seu próprio gate; nenhuma regra clínica foi incluída.

### Seleção determinística

Mensagens recorrentes são escolhidas no PostgreSQL a partir de versões imutáveis
do pack ativo. A seleção exige o mesmo locale e tenta primeiro a personalidade
efetiva; se não houver versão elegível, usa `balanced` no mesmo idioma. As três
variantes elegíveis são rotacionadas por uso menos recente, sob lock transacional,
com chave de evento idempotente, cooldown e limites locais.

O runtime não chama LLM para completar ausência de catálogo. Resultado
`suppressed`, falha do claim ou inexistência de versão elegível retorna `null` ao
caller, que não deve inventar texto alternativo. Se o template escolhido falhar
na renderização, o uso é marcado como falho sem persistir corpo renderizado ou PII
e a resposta também é `null`.

O catálogo possui rendições `in_app`, `push` e `email`, mas a policy de `email`
mantém `delivery_enabled=false`. Push permanece em outbox e não é enviado ao APNs
nesta fase.

### Governança editorial

O admin expõe `/settings/coach-messages`. `content_editor` e `master_admin` podem
ler o catálogo, criar versões imutáveis em packs de rascunho, gerar prévias com
valores sintéticos, comparar versões, validar e clonar o pack ativo. Somente
`master_admin` pode agendar, ativar, arquivar ou restaurar packs.

Uma sugestão assistida acontece apenas após comando editorial explícito, usa como
fonte um grupo aprovado do pack ativo, fica limitada a um grupo de três variantes
e três canais e passa pelo mesmo linter antes de criar versões
`assisted_draft`. Ela nunca publica diretamente. Ativação valida cobertura,
linhagem e hash do snapshot para impedir aprovação de conteúdo que mudou entre a
revisão e o comando.

A rotação mensal significa preparar, revisar e aprovar um novo pack. O scheduler
apenas ativa um pack completo previamente agendado; ele não gera frases nem toma
decisão editorial.

### Limites do mascote

O contrato expõe somente `state` (`inactive`, `reactivating`, `active`,
`evolving` ou `neglected`) e `changed_at`. Sem linha persistida, o estado público
é `inactive`. Não há avatar, animação, asset visual, progressão automática ou
transição inferida por tempo, comportamento, peso ou saúde. Mudanças de estado
dependem de uma operação explícita validada no backend.

## Devices, lembretes e rotina

O registro de device aceita somente iOS, `installation_id` opaco, ambiente APNs
`sandbox` ou `production` e token hexadecimal. O token é normalizado e permanece
em tabela backend-only; respostas, eventos e logs não incluem token nem hash. Uma
instalação desativada continua no histórico e deixa de receber novas entregas. Se
o mesmo device trocar de conta com evidência do mesmo token, o backend desativa a
identidade anterior e cria outra; entregas antigas continuam ligadas ao usuário e
ao device originais.

Preferências suportam opt-in global, início/fim de horário silencioso, limite de
0 a 20 pushes por dia e meta opcional de hidratação entre 250 e 10.000 ml. Início
e fim do horário silencioso devem ser ambos nulos ou ambos presentes. O timezone
canônico vem do perfil do paciente.

Regras genéricas aceitam `local_time` no formato `HH:MM`, dias únicos entre 0
(domingo) e 6 (sábado) e uma das categorias: `meal`, `hydration`, `workout`,
`reevaluation`, `content` ou `reengagement`. Refeição exige `meal_type`; as
demais rejeitam `meal_type` e `routine_item_id`. `GET /reminders` ainda pode
listar regras históricas de categoria `supplement` ou `medication`, mas elas são
somente leitura por esse contrato. `POST /reminders` e `PATCH /reminders/:id`
retornam `409 routine_schedule_conflict` para essas categorias; horários de
suplemento e medicamento são criados e substituídos somente pelos endpoints
versionados do respectivo item.

Hidratação exige `amount_ml` entre 1 e 5.000 e `occurred_at` explícito. A ação
`taken` também exige `occurred_at`. O servidor recusa instantes mais de cinco
minutos no futuro ou sete dias no passado e usa o timezone do paciente para o dia
local. Retry com a mesma `Idempotency-Key` não soma nem registra novamente.

O scheduler Inngest descobre regras vencidas com janela de cinco minutos e emite
`reminder.rule.due` contendo somente `reminderRuleId` e `scheduledFor`. O
worker percorre páginas de 500 regras por cursor determinístico, até o limite
explícito de 20 páginas; se o limite for excedido, a execução falha em vez de
omitir regras. O Postgres faz o claim transacional e consulta preferências,
dispositivo ativo, horário silencioso, limite diário e estado oficial. Os
resultados possíveis são `queued`, `resolved` e `suppressed`, sempre auditáveis e
idempotentes. Claims executados mais de 15 minutos depois do instante esperado são
registrados como `suppressed` com motivo `stale`, sem criar delivery.

Criação ou reativação de lembrete que conflite com outra regra ativa retorna
`409 reminder_conflict`. Referência inválida ou combinação rejeitada por constraint
retorna `422 reminder_invalid`, sem converter erro do paciente em `500`.

Nesta fase, `queued` significa apenas que uma linha foi criada em
`notification_deliveries`. Não existe chamada ao APNs, não há credencial de push
e nenhum registro é marcado como `sent`. A integração futura consumirá essa
outbox sem mudar o contrato de decisão.

## Proposta de refeição

Request:

```json
{
  "kind": "meal",
  "meal_type": "jantar",
  "items": [
    {
      "food_name": "arroz branco cozido",
      "quantity_g": 120
    }
  ],
  "consumed_at": "2026-07-20T20:15:00-04:00"
}
```

O cliente não pode enviar proteína, carboidrato, gordura ou total final. O campo
opcional `user_kcal` é aceito somente quando representa uma kcal explicitamente
informada pelo paciente; o pipeline ainda aplica invariantes físicos e
proveniência canônica.

O servidor calcula os itens via base nutricional, cria um pending de 24 horas e
retorna apenas o DTO necessário para confirmação. Texto bruto, IDs de provider,
evidência de replace, audit warnings e referências internas não são expostos.

Cada item do pending de refeição traz também a proveniência das calorias já
armazenada no pending (campos sempre presentes, possivelmente `null`):

- `user_kcal`: kcal informada pelo paciente para o item, como recebida; `null`
  quando nenhuma foi informada;
- `nutrition_source`: fonte que o servidor efetivamente aplicou. Somente
  `"user_kcal"` significa que `kcal` é o valor do paciente; qualquer outro valor
  (ou `user_kcal` presente com outra fonte, quando o valor informado foi
  recusado por densidade impossível) significa cálculo do servidor.

Para manter uma kcal informada ao editar (`PATCH`), o cliente reenvia o mesmo
`user_kcal`; omiti-lo volta ao cálculo do servidor. `null` não é aceito na
entrada. Um cliente que receba um item sem essas duas chaves (servidor anterior)
não deve presumir que não havia valor informado.

Identificação do alimento (mesmo cálculo do WhatsApp):

- um candidato "X de Y" da base é o alimento X, não Y (`Bolinho de arroz` não
  responde por "arroz"; `Farinha, de mandioca` não responde por "mandioca"),
  salvo quando o paciente nomeou X ou quando X é parte/corte de Y ("peito de
  frango");
- quando o nome não diz o preparo (cru, cozido, grelhado, assado, refogado,
  frito) e a base traz o PRÓPRIO alimento pedido (mesmo núcleo e variedade) em
  preparos cuja energia média varia 50% ou mais (decisão de produto de
  2026-09-28 — feijão carioca cru 329 × cozido 76 kcal/100 g), o servidor não
  escolhe: o item volta com `kcal` 0, `nutrition_source` `"no_match"` e um
  aviso em `warnings` pedindo o preparo. Isso vale antes do histórico do
  paciente e, num nome composto ("frango grelhado com batata doce"), para o
  item inteiro. Editar o nome com o preparo ("Feijão carioca cozido")
  recalcula pela base. Abaixo de 50% (cenoura, peito de frango) não há
  pergunta; outros alimentos que só compartilham uma palavra ("couve manteiga"
  para "manteiga") não contam.
- o alimento que o paciente nomeou precisa aparecer no candidato: adjetivo ou
  variedade em comum não identifica ("café preto" não é "Feijão, preto");
- cada item do pending traz `resolution` (`"resolved"` ou
  `"needs_clarification"`) e `preparation_options` (lista ou `null`). Um item
  `needs_clarification` — fontes `no_match`, `composite_rejected`,
  `category_mismatch`, `protein_mismatch`, sempre com `kcal` 0 — ainda não foi
  calculado. `POST /registrations/:id/confirm` recusa com `422
  registration_unresolved_items` enquanto houver um; nada é gravado e o pending
  continua editável. Zero legítimo (água, bebida zero, `user_kcal` 0) é
  `resolved` e pode ser confirmado.
- nomes do dia a dia (regra M2 — regra geral dita pelo cliente em 06/01/2026
  (manual 4.2), 18/05/2026 e 01/06/2026 (assumir em vez de perguntar); a lista
  de itens NÃO foi confirmada por ele; implementado em 2026-10-04 a pedido do
  Eduardo; confirmação do cliente pendente): o `name` de um item da proposta
  pode voltar como o item ASSUMIDO, diferente do `food_name` enviado. Hoje:
  "leite" → `name` "leite integral"; "whey" → `name` "whey protein em pó". Vale
  só para o nome inteiro ("leite de coco", "leite com whey" e "café com leite"
  seguem as regras acima). O item vem com `nutrition_source` `"canonical_fuzzy"`,
  `resolution` `"resolved"` e sem aviso em `warnings`. O `name` é o texto que o
  app tem para mostrar (a tela do iPhone não foi executada depois desta mudança
  — pendência RC M2), e reenviar esse `name` numa edição resolve para o mesmo
  item. Dois itens enviados que são o mesmo item assumido ("leite" 200 g e "leite integral"
  200 g) voltam como UM item com a quantidade somada (400 g, 244 kcal): a
  proposta pode ter menos itens que o pedido. Nesse caso o `quantity_basis` dos
  itens seguintes ainda é lido por posição e pode vir do item somado (pendência
  RC M2 em `docs/CALCULO-MPP.md` §9f). Se o catálogo do ambiente não tiver a
  linha verificada com os valores da lista, o item segue o cálculo normal e o
  `name` volta como enviado. Nenhum campo novo no contrato.

## Rascunho de refeição (candidatos)

`POST /api/mobile/v1/meal-drafts` (exige `Idempotency-Key` e entitlement; sem
tabela nova: a resposta fica no ledger de idempotência por 24 h).

```json
{ "source": "text", "text": "2 ovos mexidos e 1 pão francês" }
{ "source": "media", "media_asset_id": "<uuid de meal_photo ou audio_note processado>" }
```

Devolve CANDIDATOS para revisão, nunca nutrição:

```json
{
  "source": "text",
  "media_asset_id": null,
  "transcript": null,
  "context_note": null,
  "items": [
    { "candidate_id": "c1-0a1b2c3d", "name": "ovos mexidos", "quantity_g": 100,
      "quantity_basis": "portion_reference", "count": 2, "unit_label": "unidade",
      "confidence": null, "needs_review": true, "review_reason": "estimated_quantity" }
  ],
  "nutrition_label": null,
  "extraction": { "method": "deterministic", "model": null }
}
```

- `quantity_basis`: `stated` (o paciente disse as gramas), `visual_estimate`
  (estimativa do Vision), `portion_reference` (contagem × peso unitário que o
  servidor já usa: ovo 50 g, pão francês 50 g, pão de queijo 30 g, fatia 15 g,
  banana 100 g, maçã 150 g; ml de líquido ≈ g) ou `missing`. Nenhuma grama é
  inventada: sem referência, `quantity_g` é `null` e o app exige a quantidade
  antes de propor. Porção de referência e estimativa visual pedem confirmação.
- Texto: "alimento + gramas" é lido sem provedor. O restante vai a um extrator
  sem ferramentas (quando há chave configurada), cuja saída é tratada como dado
  não confiável — gramas e contagens só valem se estiverem no texto do
  paciente. Sem extrator, o mesmo trecho é lido palavra a palavra; o que não
  puder ser lido volta como item `ambiguous` para o paciente corrigir.
- Áudio: `transcript` mostra o que foi ouvido; os candidatos saem dele.
- Foto: mapeia o resultado do Vision; `nutrition_label.applies_to_candidate_id`
  só vem preenchido quando a associação é inequívoca.
- Erros: `404 media_asset_not_found` (inclui mídia de outro paciente),
  `409 media_not_processed`, `422 media_kind_not_supported`,
  `422 meal_draft_empty`, `502 meal_extraction_failed`.

### Origem na proposta

`POST /registrations/propose` e `PATCH /registrations/:id` aceitam, de forma
opcional e compatível:

```json
{
  "kind": "meal", "meal_type": "lanche",
  "source": { "channel": "gallery", "media_asset_id": "<uuid>" },
  "items": [
    { "food_name": "iogurte natural", "quantity_g": 170,
      "quantity_basis": "visual_estimate", "candidate_id": "c1-0a1b2c3d",
      "use_nutrition_label": true }
  ]
}
```

- `channel`: `text`, `camera`, `gallery`, `audio_recording`, `audio_import`.
  Canais de mídia exigem `media_asset_id`; `text` não aceita.
- A mídia precisa ser do paciente, do tipo do canal e estar processada.
- `use_nutrition_label: true` em no máximo um item, só com foto. O servidor
  relê o rótulo do resultado processado e o aplica somente a esse item
  (`nutrition_source: "product_label"`). Rótulo ausente, de baixa confiança ou
  incompleto recusa a proposta com `422 nutrition_label_not_applicable` — não
  há cálculo silencioso no lugar. O cliente nunca envia macros.
- O pending devolve `source: { channel, media_asset_id }` e, por item,
  `quantity_basis`.

## Peso

`POST /api/mobile/v1/weight` (exige `Idempotency-Key` e entitlement). Depende da
migration `20260928120000_bodyflow_weight_measurement.sql` (M1).

```json
{ "value": 78.4, "unit": "kg", "measured_at": "2026-09-28T08:30:00-03:00" }
```

- `unit`: `kg` ou `lb`. A conversão (× 0,45359237), o arredondamento para duas
  casas e a comparação acontecem no banco; o cliente não envia quilogramas
  calculados nem `user_id`.
- Faixa: 30–300 kg depois da conversão → senão `422 weight_out_of_range`.
- `measured_at`: de 7 dias atrás a 5 minutos no futuro → senão
  `422 measured_at_out_of_range`.

Resposta `201`:

```json
{ "applied": true, "reason": "applied", "weight_kg": 78.4, "measured_at": "2026-09-28T11:30:00+00:00" }
```

O peso oficial continua em `user_profiles.weight_kg` (sem histórico paralelo).
A medição só substitui a atual quando é mais recente:

| Situação | Resultado |
|---|---|
| peso atual sem instante (legado) ou medição mais recente | `applied: true` |
| mesmo instante e mesmo valor (replay, a qualquer tempo) | `applied: false`, `reason: "same_measurement"` |
| mesmo instante e valor diferente | `409 weight_measurement_conflict` |
| medição mais antiga que a atual | `applied: false`, `reason: "older_than_current"` |

`weight_kg` e `measured_at` da resposta são sempre os valores vigentes. Nada é
escrito em `daily_snapshots`, `user_progress` ou no bloco 7.700; metas seguem
os cálculos e jobs existentes. `GET /profile` passa a trazer
`weight_measured_at` (`null` quando o peso é legado ou o banco ainda não tem a
coluna). Escritas legadas (WhatsApp, conclusão do onboarding) passam a datar o
peso no momento da escrita, por trigger, sem mudança de código.

## Mídia privada

O app nunca recebe `service_role` e não possui policy para listar, inserir,
alterar ou excluir diretamente em `storage.objects`. Todo acesso nasce no BFF,
depois da resolução do paciente autenticado. O catálogo `media_assets` é a fonte
canônica de ownership; `storage.objects.owner_id` não é usado como autorização.

Áudio: `POST /media` aceita `duration_ms` (declarado pelo app, pré-filtro) e
recusa acima de 180 000 com `422 audio_too_long`. O worker mede a duração real
pelo contêiner do arquivo antes de qualquer transcrição: acima de 180 s falha
com `audio_too_long`; duração ilegível falha com `audio_duration_unreadable`.
Nos dois casos a transcrição não é chamada.

Tipos aceitos pelo paciente:

| `kind` | MIME aceitos | Limite | Retenção padrão | Download |
|---|---|---:|---:|---:|
| `meal_photo` | JPEG, PNG, WebP, HEIC, HEIF | 15 MiB | 30 dias | 300 s |
| `body_checkin_photo` | JPEG, PNG, WebP, HEIC, HEIF | 15 MiB | 730 dias | 60 s |
| `gym_photo` | JPEG, PNG, WebP, HEIC, HEIF | 15 MiB | 90 dias | 300 s |
| `audio_note` | MP3, M4A/MP4, AAC, WAV, OGG | 25 MiB | 30 dias | 300 s |

`content-covers` também existe como bucket privado, limitado a 10 MiB e sem
expiração automática. Ele pertence ao CMS com RBAC próprio, não ao contrato de
upload do paciente, e só é lido no mobile pelo proxy de capability descrito em
“Conteúdo educativo”. SVG não é aceito.

### Fluxo de upload

1. O app chama `POST /media` com `Idempotency-Key`:

```json
{
  "kind": "meal_photo",
  "mime_type": "image/jpeg",
  "size_bytes": 2048000,
  "context_text": "Jantar: frango grelhado com arroz."
}
```

2. A API cria um caminho imutável e não enumerável e devolve `asset` mais
   `upload.signed_url`. A URL expira em duas horas. Ela já contém a capacidade
   temporária; o app não recebe bucket, caminho interno nem token separado.
3. O app envia os bytes diretamente para `signed_url` usando o `method` e os
   `headers` devolvidos (`PUT`, `Content-Type` declarado e `x-upsert: false`),
   com o mesmo total de bytes declarado. A URL deve permanecer apenas em
   memória e nunca entrar em analytics, crash logs ou telemetria.
4. O app chama `POST /media/:id/complete` com uma nova `Idempotency-Key`.
   O backend consulta os metadados reais no Storage. Divergência de MIME ou
   tamanho remove o objeto, marca falha de upload e retorna `422`. Objeto ausente
   também encerra o pending como falha; indisponibilidade transitória do Storage
   retorna `503` sem alterar o estado. O `422` mutável é replayado pelo ledger.
5. Quando houver análise, o app chama `POST /media/:id/process`. O evento contém
   apenas IDs técnicos; a legenda permanece no catálogo privado e é carregada
   pelo worker junto da foto. Foto e texto formam um único contexto e não viram
   dois registros de refeição.
6. O app consulta `GET /media/:id` até `processed` ou `failed`. A resposta inclui
   `result` somente depois de `processed` e uma URL curta de download apenas nos
   estados em que o objeto já foi validado.

Repetir `POST /media` com a mesma chave nunca cria outro ativo. Como o ledger da
API dura 24 horas e a URL dura duas, um replay regenera somente a URL temporária
quando o ativo ainda está em `pending_upload`. A capacidade assinada não é
persistida no corpo do ledger idempotente.

Estados válidos:

```text
pending_upload -> uploaded -> processing -> processed
       |             |            |
       +----------> failed <-------+
       |             |
       +----------> deleted <------+---- processed
```

Retry do evento pode retomar a falha com o mesmo `processing_request_id`, e um
novo pedido explícito pode criar outro claim depois que o estado já é `failed`.
Enquanto o ativo está em `processing`, nenhum outro evento toma o claim ativo.
`deleted` é terminal.

### Privacidade, retenção e exclusão

- O path é derivado no servidor de `user_id + asset_id + extensão`; nome original
  do arquivo não é armazenado.
- Antes de Vision/STT, o worker valida a assinatura binária compatível com o
  MIME. Conteúdo disfarçado é rejeitado sem custo de IA.
- `raw_response` do provedor não é persistido. O resultado estruturado fica no
  registro privado do paciente.
- A limpeza de retenção roda em lotes e remove o objeto físico antes de marcar o
  catálogo como `deleted`.
- No purge de conta, o FK `RESTRICT` impede apagar o paciente antes da remoção
  física. O worker remove objetos, apaga o catálogo e só então apaga `users`.
- `DELETE /media/:id` segue a mesma ordem. URLs já emitidas têm TTL máximo de 60
  ou 300 segundos; clientes não devem reutilizá-las nem mantê-las em cache.
- Fotos corporais são tratadas como mídia sensível: bucket separado, TTL de 60
  segundos e nenhuma URL pública permanente.

## Rascunhos de plano (treino e plano alimentar)

Um plano proposto pelo Flow ou lido de um documento é um **rascunho**. Ele só
vira o plano do paciente quando o paciente revisa e confirma no app. Nenhuma
ferramenta do agente confirma; a confirmação do paciente nunca é apresentada
como revisão de um profissional.

| Rota | Efeito |
|---|---|
| `GET /api/mobile/v1/plan-drafts?status=open` | lista os rascunhos abertos do paciente (`open`, `ready_for_review` ou `needs_completion`) |
| `GET /api/mobile/v1/plan-drafts/:id` | conteúdo para revisão |
| `PATCH /api/mobile/v1/plan-drafts/:id` | edição do paciente → nova `payload_version` |
| `POST /api/mobile/v1/plan-drafts/:id/confirm` | **único caminho** de rascunho para plano |
| `DELETE /api/mobile/v1/plan-drafts/:id` | descarta |
| `POST /api/mobile/v1/plan-imports` | começa a leitura de um documento (202) |

Todas exigem bearer e entitlement; as mutações exigem `Idempotency-Key`.
Rascunho de outro paciente responde `404 plan_draft_not_found` em todas.

### Conteúdo

```json
{
  "id": "<uuid>", "domain": "training", "origin": "imported_pdf",
  "status": "needs_completion", "payload_version": 1,
  "payload": { "weekly_schedule": [ { "day": "Treino A", "focus": "Inferiores",
    "duration_min": 60, "exercises": [ { "name": "Leg press", "sets": 3,
    "reps_range": "10", "rest_seconds": null } ] } ] },
  "uncertain_fields": [
    { "pointer": "/weekly_schedule/0/exercises/0/rest_seconds", "reason": "missing" }
  ],
  "unrecognized_segments": ["Tomar creatina 5 g após o treino."],
  "replaces_current_plan": true, "can_confirm": false,
  "notices": ["not_professionally_reviewed", "medications_not_imported"],
  "source_media_asset_id": "<uuid>", "confirmed_plan_id": null,
  "failure_code": null, "created_at": "…", "updated_at": "…",
  "expires_at": "…", "resolved_at": null
}
```

- `status`: `extracting`, `generating`, `needs_completion`, `ready_for_review`,
  `confirmed`, `discarded`, `expired`, `failed`. Um rascunho aberto com
  `expires_at` vencido (30 dias) é lido como `expired`.
- `origin`: `flow_generated`, `imported_photo`, `imported_pdf`.
- `uncertain_fields[].reason`: `missing`, `out_of_range`, `invalid`,
  `not_in_document` (o número não está escrito no documento) e `not_allowed`
  (o texto falava de medicamento, suplemento ou dose e foi retirado do campo).
  Valor ausente ou fora da faixa fica `null`; nada é ajustado, estimado ou
  calculado. Campo opcional vazio ou `null` é tratado como ausente.
- Plano alimentar: alimento e quantidade são obrigatórios; calorias e macros
  são opcionais e só existem quando o documento (ou o gerador) os trouxe.
- `unrecognized_segments`: trechos do documento que não viraram campo, como
  vieram. Medicamento, suplemento e dose nunca viram campo — a regra vale para
  o conteúdo de qualquer campo de texto, venha do documento, do Flow ou da
  edição do paciente: o texto sai do campo (num campo obrigatório, o campo
  fica vazio) e, na importação, volta para esta lista. Quando aparecem,
  `notices` traz `medications_not_imported`.
- `notices` sempre traz `not_professionally_reviewed`.
- `failure_code` (com `status: failed`): `document_without_text` (PDF
  digitalizado — o app pede fotos das páginas), `document_too_long` (mais de
  20 páginas ou 60 000 caracteres), `document_unreadable`,
  `nothing_recognized`, `extraction_failed`.

### Edição

`PATCH` com `{ "payload_version": 1, "payload": { … } }` (corpo até 256 KiB).
Só os campos conhecidos do formato são guardados. Edição incompleta é aceita
e deixa o rascunho em `needs_completion`; completa, `ready_for_review`.
Erros: `409 draft_changed` (a versão não é a atual),
`409 plan_draft_not_reviewable`, `410 plan_draft_expired`.

### Confirmação

`POST …/confirm` com `{ "payload_version": 3 }`.

- exige `ready_for_review`, a versão que o paciente revisou e o conteúdo
  passando inteiro na validação do formato (`422 plan_draft_incomplete`);
- treino: substitui o plano ativo, na mesma transação e sob a mesma trava das
  outras trocas de plano; **não** liga a entrega diária pelo WhatsApp;
- plano alimentar: só insere uma prescrição; as anteriores ficam como estão;
- `409 plan_changed_during_review`: o plano em vigor mudou desde que o
  rascunho nasceu — o paciente revisa de novo (novo rascunho);
- `409 prescribed_plan_protected`: o plano de treino em vigor, ou a
  prescrição mais recente ainda válida, foi feito por um profissional e não é
  substituído por rascunho;
- o plano confirmado guarda a origem (`flow_draft` ou `patient_import`) e, se
  o paciente alterou o conteúdo antes de confirmar, o sufixo `_edited`;
- uma prescrição que apenas venceu durante a revisão não conta como mudança
  de plano;
- repetir a mesma confirmação devolve o mesmo plano (`already_confirmed: true`);
- validade: os gerados seguem a regra dos geradores (treino 6 semanas; plano
  alimentar 1 ou 7 dias); um plano importado não recebe validade.

### Importação de documento

1. `POST /media` com `kind: "plan_document"` (`application/pdf` ou imagem,
   até 20 MiB), upload assinado e `POST /media/:id/complete` como nas outras
   mídias. O documento não tem data automática de exclusão; o paciente o
   apaga com `DELETE /media/:id`.
2. `POST /plan-imports` com `{ "media_asset_id": "<uuid>", "domain":
   "training" | "nutrition" }` → `202 { "draft_id", "status": "extracting" }`.
3. O app consulta `GET /plan-drafts/:id` até sair de `extracting`.

`POST /media/:id/process` recusa documento de plano (`422
media_kind_not_supported`): ele só é lido pela importação. `DELETE /media/:id`
de um documento com rascunho em leitura ou em revisão responde `409
media_in_use_by_plan_draft` — o paciente descarta o rascunho antes.

Um documento é importado uma vez: pedir de novo devolve o rascunho que ele já
gerou e, se a leitura ainda não começou, pede a leitura outra vez (`409 plan_document_already_imported` se for pedido como outro tipo de
plano; `409 plan_document_already_read` se a leitura anterior não deixou
rascunho aberto — o paciente envia o documento de novo). Mídia de outro
paciente: `404 media_asset_not_found`.

O texto do documento é dado: o modelo que o organiza não tem ferramentas, só
os campos conhecidos são aceitos e todo número precisa estar escrito no
documento. Essa conferência garante que o número existe no documento, não que
pertence àquele campo — por isso todo rascunho importado passa pela revisão
do paciente.

### Proposta pelo Flow

#### Apresentação de mensagens antigas (C1, 2026-10-08)

`GET/POST /flow/chat` aplica a projeção pública de métricas conhecidas apenas a
`assistant.content`. O GET mantém a janela, ordem e identificadores; o POST
projeta **após** a idempotência, incluindo respostas antigas guardadas no ledger
HTTP. As rotas espelhadas do BFF reexportam o mesmo handler. Texto do usuário,
metas públicas históricas, timestamps, request IDs, estados e `draft` não mudam.
Não há busca de metas atuais, backfill ou nova escrita de conteúdo/cache.

Se a projeção remove todo o conteúdo técnico, mantém-se o ID com orientação
neutra para Hoje/Perfil, sem alegar falta de metas ou inventar números. Idioma
reconhecível da mensagem é preservado; texto ambíguo usa o locale autenticado.
JSON/envelope/mensagem 2xx malformados retornam erro tipado
`500 flow_response_invalid`; respostas de erro existentes permanecem intactas.
Status, headers de replay/recuperação e metadados externos são preservados;
`Content-Length` antigo é removido ao reserializar. Conteúdo já em memória do
cliente sem nova leitura continua fora desta projeção. Verificação local:
testes do handler/serviço/idempotência e `verify:routes`/`verify:imports` do BFF;
isso não substitui publicação e smoke de staging.

#### Objetivo atual na apresentação Flow (C3/C4, 2026-10-08)

O pipeline do Flow usa o `user_profiles.current_protocol` autenticado para
projetar cópias de regras, RAG, resumo, histórico assistant, tentativas do modelo
e resposta final após reconstrução de cards/rascunhos. A mensagem do usuário
permanece literal. Somente `recomposicao` permite saldo, percentual e contagem
do Bloco 7.700. Ganho/manutenção usam uma única linha explicativa quando dados
de bloco foram retirados. Fonte ausente/inválida não atribui objetivo. O
orçamento de 14 dias e DAM ficam ocultos em **todos** os objetivos, conforme a
decisão C4, até validação clínica; reavaliação em 14 dias permanece visível.

O JSON de `consulta_progresso` conserva XP, nível, sequência, demais conquistas,
valores do dia e energia histórica. Fora da recomposição omite apenas os campos
de bloco e medalhas classificadas como `blocks` na configuração. Isso não
apaga saldo/medalhas persistidos nem altera fórmulas, créditos ou o protocolo
histórico usado no balanço de energia. A portadora de apresentação é interna,
definida pelo servidor; body/query não podem fornecê-la.

`GET/POST /flow/chat` consulta uma vez por requisição somente
`user_profiles.current_protocol`, com `user_id` do paciente autenticado. GET
paraleliza essa leitura com o histórico limitado; POST lê depois da idempotência
e da validação do contrato de sucesso, incluindo replay do serviço e HTTP.
O objetivo não entra no payload/hash nem no corpo salvo do cache. Uma nova
requisição pode projetar a mesma mensagem pelo objetivo atual, conservando ID,
data, estado, draft e metadados. Um conteúdo que nunca foi salvo não é recriado.

Falha dessa leitura retorna `500 data_access_failed`, sem assistant bruto ou
detalhe de consulta. Se o POST já concluiu e guardou sua resposta, esse erro
posterior não desfaz o claim: retry com **a mesma chave e o mesmo payload**
reutiliza o turno salvo e repete a leitura/projeção, sem novo LLM. Isso não é
garantia de cancelamento no servidor, nem se aplica a todo erro de envio.
Perfil ausente/null/inválido difere de erro de leitura e resulta em objetivo
desconhecido seguro. Não há cache global de objetivo nem promessa de snapshot
transacional entre histórico e perfil.

A projeção textual reconhece vocabulário qualificado PT/EN; preserva alergias,
comida, números oficiais, URLs e caminhos. Um link cujo rótulo inteiro seja uma
métrica restrita vira seu destino original legível; rótulos mistos conservam
palavras públicas. Não é uma classificação universal de qualquer prosa ambígua.
O legado/default WhatsApp não recebe essa portadora. O espelho BFF continua
reexportando a rota admin; gates: testes do loader/handler/serviço/idempotência,
`verify:routes`, `verify:imports`, build e `verify:build-surface`.
Conteúdo já residente no cliente sem nova leitura tem gate nativo próprio;
esses testes locais não comprovam publicação, smoke ou aceite clínico.

`POST /flow/chat` responde com `draft: { "id", "domain" } | null`: o rascunho
que aquele turno criou (lido do banco, preso ao paciente e ao turno). O Flow
só tem as ferramentas `propoe_plano_treino` e `propoe_plano_dieta`, com os
mesmos limites dos geradores (treino 1 por 24 h; plano alimentar 2 por 2 h,
somando gerações e propostas). Antes de gerar, a ferramenta confere se há
lugar para guardar a proposta (menos de 20 rascunhos abertos e menos de 3
falhas de gravação na última hora): sem lugar, nada é gerado. `gera_treino`/`gera_dieta` continuam recusadas
no app, e as propostas não existem no WhatsApp.

#### Status determinístico por objetivo (recorte C3/C4, 2026-10-08)

Quando a pergunta pura de status recebe `consulta_progresso` e há snapshot,
o Flow compõe o card com os mesmos valores oficiais do dia. Comida, proteína,
exercício, sequência, nível e XP permanecem iguais. A contagem de blocos
concluídos só aparece quando o objetivo ativo do perfil é recomposição;
ganho/manutenção recebem a explicação “O Bloco 7.700 é exibido apenas na
recomposição corporal.”, uma vez ao final da apresentação.

O adapter desse status Flow não fornece `last14d` ao renderer, inclusive na
reconstrução canônica desse caminho após o loop. Orçamento de 14 dias/DAM fica
oculto nesse caminho até a decisão
documentada do médico. Os valores originais não são zerados ou removidos do
contexto/persistência: não mudam cálculo, crédito, fechamento ou medalhas.
O renderer e compositor compartilhados preservam seus defaults legados.

Esse recorte não muda detector, permissões de ferramentas, consultas, schema,
rotas ou contrato nativo. `/flow/chat` mantém seu espelho BFF e verificadores.
Golden exato de ganho e manutenção com bloco histórico não zero, recomposição
com as mesmas cifras, inputs congelados e trava WhatsApp validam o caminho
local. Copy/publicação/staging permanecem gates próprios. Prompt, JSON de
ferramenta, texto livre, histórico/replay e Hoje/Progresso ainda exigem a
política completa C3/C4; essa correção não fecha esses pacotes. O status
determinístico ainda é em português, como antes (RC PERF-C6).

### Identidade pública do Flow

No app o assistente é o **Flow, do Performe AI**, e nada mais: o nome do
método das regras de cálculo ("MPP", "Muscular Power Plant") e o nome do
médico que o escreveu são referências internas e não chegam à pessoa. Duas
camadas cuidam disso, só no caminho do Flow (`processAuthenticatedMessage`;
a entrada legada do WhatsApp não muda).

1. **A instrução ao modelo é absoluta** (`mobileFlowSystemPolicy`, em
   `packages/agent/src/pipeline.ts`): nunca escrever esses nomes nem "método
   do Dr. …", nem quando a pessoa perguntar; perguntado qual é o método ou
   quem está por trás, o Flow diz que as orientações seguem o programa do
   Performe AI. Antes a regra só proibia citar "espontaneamente".
2. **Uma última barreira determinística** no texto de `POST /flow/chat`
   (`packages/agent/src/flow-public-names.ts`, aplicada a toda forma de um
   turno terminar). É um **vocabulário fechado**: troca só as grafias
   listadas em RC FN-4 e não lê a redação em volta do nome (não existe regra
   de "assinatura" nem de "vocativo").
   - O nome do método vira "Performe AI", menos quando está colado a
     `/ . @ - _` ou a letra ou número: trecho de caminho, de subdomínio ou de
     identificador fica como está. A consulta e a âncora de um endereço
     (`?ref=mpp`, `#mpp`) ainda não: ali a sigla é trocada (limite declarado
     em RC FN-4).
   - O nome do médico só é trocado **quando vem com o sobrenome**: por "Flow"
     logo depois de uma das aberturas de apresentação da lista, por
     "Performe AI" no resto. "Dr. Roberto" ou "Roberto" sem o sobrenome nunca
     são trocados (pode ser a pessoa que usa o app, ou um terceiro: RC FN-7),
     nem outra pessoa com o mesmo sobrenome ("Dra. Roberta Menescal").
   - **Conta com o sobrenome:** quando o nome cadastrado da conta
     (`users.name`, o mesmo que o contexto do Flow já carrega; nenhuma
     consulta a mais) contém "Menescal", sem diferença de maiúscula ou
     acento, o nome do médico não é trocado naquele turno. Os nomes do método
     continuam trocados.

O turno grava `llm.flow_internal_name_replaced` em `product_events` só com
contagens e o estágio, nunca com texto: `method_names`, `persona_self` e
`persona_other` (nomes trocados) e `persona_first_name_only` (título +
primeiro nome vistos sem o sobrenome e **não** trocados; o evento é gravado
também quando só este contador é maior que zero). Uma resposta sem nada disso
sai idêntica à que o modelo escreveu e não grava evento.

Exemplos travados (entrada do modelo → o que o app recebe):

| Resposta do modelo | O app recebe |
|---|---|
| `Bom treino, Dr. Roberto!` | igual |
| `Fale com seu médico, o Dr. Roberto Silva.` | igual |
| `Dra. Roberta Menescal` | igual |
| `Bom dia, Roberto Menescal! Vamos registrar o almoço?` | igual, na conta cujo nome contém "Menescal"; `Bom dia, Performe AI! Vamos registrar o almoço?` nas outras |
| `Sou o Dr. Roberto Menescal.` | `Sou o Flow.` |
| `O método foi criado pelo Dr. Roberto Menescal.` | `O método foi criado pelo Performe AI.` |
| `É o M.P.P., sim.` | `É o Performe AI, sim.` |
| `MPP (Muscular Power Plant)` | `Performe AI (Performe AI)` |
| `https://example.com/mpp/guia`, `docs/CALCULO-MPP.md`, `MPP-2`, `@mpp/agent` | iguais |

Travado em
`packages/agent/src/__golden__/audit-10-05-flow-never-names-the-method.test.ts`
(as três perguntas "Qual é o método que vocês usam?", "Isso é o MPP?" e
"Quem é o Dr. Roberto?", e cada frase da decisão de 2026-10-05, pelo pipeline
real com modelo roteirizado) e em
`packages/agent/src/flow-public-names.test.ts`.

> RC FN-1 — cenário resposta do MODELO REAL às três perguntas ("Qual é o método que vocês usam?", "Isso é o MPP?", "Quem é o Dr. Roberto?") NÃO coberto nesta PR (pendência da audit 2026-10-05). O modelo é roteirizado: o golden prova que a instrução absoluta vai no pedido e o que o filtro troca e não troca quando um nome escapa, não que o modelo real obedece nem como ele redige a resposta. Em staging, `llm.flow_internal_name_replaced` conta quantas vezes o filtro agiu (`method_names`, `persona_self`, `persona_other`) e quantas vezes viu título + primeiro nome sem o sobrenome e não trocou (`persona_first_name_only`).

> RC FN-2 — cenário frase SOBRE o médico em terceira pessoa NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro troca nomes, não afirmações nem a redação em volta: "O Dr. Roberto Menescal é o médico que criou o método." chega como "O Performe AI é o médico que criou o método." e "Método MPP (Muscular Power Plant)" chega como "Método Performe AI (Performe AI)". Sem os nomes, mas a frase fica estranha e continua dizendo que há um médico por trás. Travado como pendência no golden.

> RC FN-3 — cenário nome dentro do RASCUNHO gravado de uma sugestão de plano (o que a tela "Revisar sugestão" mostra) NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro cobre o texto da sugestão que vai para o chat; o rascunho é gravado como o gerador escreveu. O prompt dos geradores no app já proíbe citar método e profissional. Travado como pendência no golden (treino com a regra de progressão citando o método).

> RC FN-4 — cenário nome FORA do vocabulário fechado do filtro NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro troca só estas grafias. Do método, por "Performe AI": "MPP" e "MPPs" em qualquer caixa; as formas em maiúsculas "M.P.P.", "M. P. P." e "M P P"; "Muscular Power Plant" em qualquer caixa, com espaço, espaço não separável, hífen ou nada entre as palavras. Do médico, só com o sobrenome: título opcional (Dr., Dr, Dra., Doutor, Doctor) + primeiro nome opcional (Roberto, Robert) + "Menescal", por "Flow" logo depois de "sou o", "sou", "aqui é o", "aqui é", "me chamo", "meu nome é", "I am", "I'm" ou "this is", e por "Performe AI" no resto. Passam sem troca, de propósito: a grafia colada a / . @ - _ ou a letra ou número, que é trecho de endereço, caminho ou identificador ("https://example.com/mpp/guia", "https://mpp.example.com/guia", "docs/CALCULO-MPP.md", "MPP-2", "@mpp/agent", "mppx", "agentempp", "mpp_mensal_v1", e também "MPP/Muscular Power Plant" e "__MPP__"); outra pessoa com o sobrenome, isto é, "Menescal" logo depois de uma palavra capitalizada que não seja Roberto/Robert ("Dra. Roberta Menescal", "Ana Menescal", e também "Segundo Menescal, …" no começo de frase); e todo o nome do médico quando o nome cadastrado da conta contém "Menescal", sem diferença de maiúscula ou acento (a pessoa pode ser ele; os nomes do método continuam trocados). Passam sem troca por estarem fora da lista: "Menescau", "Dr. Róberto", "m.p.p.", "M P Pereira", "Método do Dr. Fulano"; e a apresentação com outra abertura ("Soy el Dr. Roberto Menescal." vira "Soy el Performe AI.", não "Soy el Flow."). Limites conhecidos, sem correção nesta PR: na consulta ou na âncora de um endereço, e em caminho com barra invertida, a sigla ainda é trocada e o link chega quebrado ("https://example.com/guia?ref=mpp" vira "https://example.com/guia?ref=Performe AI", "https://example.com/guia#mpp" vira "https://example.com/guia#Performe AI", "utm_source=mpp" vira "utm_source=Performe AI"); a sigla seguida de ponto e letra, sem espaço, passa ("É o MPP.Sim"); depois de "não", "nao", "nem", "nunca" ou "jamais" a abertura não conta como apresentação ("Não sou o Dr. Roberto Menescal." vira "Não sou o Performe AI."); o nome do médico colado a / - _ passa inteiro ("Dr. Roberto Menescal/CRM 123", "_Dr. Roberto Menescal_"); e "Menescal" sem uma palavra capitalizada logo antes é trocado mesmo sendo outra pessoa ("Sra. Menescal" vira "Sra. Performe AI"), enquanto qualquer palavra capitalizada logo antes o preserva ("Professor Menescal"). Travado no golden e em `packages/agent/src/flow-public-names.test.ts`.

> RC FN-5 — cenário contexto ENVIADO ao modelo sem "MPP" NÃO coberto nesta PR (pendência da audit 2026-10-05). As regras do banco e os trechos do manual continuam chegando ao Flow com "MPP" e "Muscular Power Plant" no corpo (só a apresentação e o nome do médico já eram trocados). Reescrever essas regras é conteúdo clínico no banco e fica para decisão do dono.

> RC FN-6 — cenário respostas JÁ gravadas no histórico antes desta mudança NÃO coberto nesta PR (pendência da audit 2026-10-05). O filtro age na resposta do turno; uma linha antiga com o nome continua como foi gravada e o app a mostra ao abrir a conversa. Nenhum banco foi lido para saber se existe alguma.

> RC FN-7 — cenário "Flow escreve 'Dr. Roberto' sem o sobrenome" variante NÃO coberta pelo filtro nesta PR (fica só a instrução ao modelo; pendência da audit 2026-10-05). Título e/ou primeiro nome sem "Menescal" ("Dr. Roberto", "Doutor Roberto", "Roberto") nunca são trocados, porque podem ser o nome de quem usa o app ou de outra pessoa: "Bom treino, Dr. Roberto!" e "Fale com seu médico, o Dr. Roberto Silva." chegam como o modelo escreveu. Por isso "O Dr. Roberto é o médico que criou o método." (uma resposta possível a "Quem é o Dr. Roberto?") também chega inteira, com o título e o primeiro nome do médico. O turno só conta a ocorrência de título + primeiro nome em `persona_first_name_only`, sem texto. Travado como pendência no golden.

## Linguagem simples na sugestão de treino do Flow

Desde 2026-10-10 (primeira atualização depois do build 1.0 (3)). Pedido do
dono, nas palavras dele: "quando ele monta o treino, está muito tecnico os
termos usados, precisam ser mais simples para facilitar o entendimento do
usuario". No rascunho gerado para uma conta de teste ele leu "Push/Pull/Legs",
"RPE 8-9", "falha técnica", "progressão linear", "reps", "Compostos primeiro,
isoladores depois", "pegada pronada" e "retração escapular".

Vale só para o app (Flow) e só para a sugestão de TREINO criada por
`propoe_plano_treino`. Nenhuma rota, DTO, esquema, status ou formato de campo
muda: o rascunho tem as mesmas chaves e os mesmos tipos (`rpe_target` continua
texto de até 40 caracteres), e o build 1.0 (3) continua funcionando sem
atualização. A ferramenta legada (`gera_treino`), o prompt legado, o pedido
legado e o plano que ela grava continuam byte a byte iguais. Nenhum número,
limiar ou conduta do método muda; `docs/CALCULO-MPP.md` não foi tocado.

Desde esta mudança o rascunho de treino do Flow é gravado com as grafias desta
tabela trocadas na criação; a frase de RC FN-3 (o rascunho é gravado como o
gerador escreveu) continua valendo para todo o resto, e RC FN-3 segue aberta.

### Duas camadas

1. **Pedido ao gerador** (`packages/agent/src/training-plan-generator.ts`, só
   os ramos do Flow). As regras do método enviadas ao modelo ficam byte a
   byte. O exemplo de `progression_rule` passa a "Adicione 1 repetição por
   treino. Chegou a 12 repetições com o movimento certo → aumente o peso e
   volte para 6." (os mesmos números 1, 12 e 6); o prompt termina com o bloco
   "COMO ESCREVER", que pede português do dia a dia, sem gíria de academia,
   sem sigla e sem inglês onde existe palavra comum, o nome de exercício que
   as academias do Brasil usam, e diz que os números e os músculos de cada
   dia não mudam; a mensagem pede `notes` e `progression_rule` com até 400
   caracteres (o campo aceita 500) e termina em "Escreva todo texto em
   português simples, para quem nunca treinou.". Mesmo modelo, mesmos
   argumentos e mesmos limites (8000 tokens, 120 s, uma tentativa). É um
   pedido: o modelo pode não obedecer (RC TL-3).
2. **Rede determinística**
   (`packages/agent/src/flow-plain-training-language.ts`). Um vocabulário
   FECHADO aplicado uma vez, dentro de `propoe_plano_treino`, ao rascunho
   candidato ANTES de ele ser avaliado e gravado. O texto do chat é montado do
   rascunho gravado, então o chat e a aba Plano mostram as mesmas palavras. A
   rede troca palavras; não reescreve a frase nem lê o sentido dela (RC
   TL-10). Na dúvida a regra deixa a palavra do gerador: uma troca errada
   ficaria gravada, e a palavra técnica mantida é o que o app já mostrava.

Campos lidos: `notes`, `progression_rule`, `equipment_summary`; por dia `day`
e `focus`; por exercício `name`, `muscle_group`, `reps_range`, `rpe_target`,
`notes`, cada item de `execution_steps` e de `common_mistakes`. Nunca lidos
nem escritos: `plan_type`, `duration_min`, `sets`, `rest_seconds` e qualquer
chave fora dessa lista.

O evento `training.plan_proposed` ganha três números (nenhum texto):
`plain_terms_replaced` (grafias trocadas), `plain_sentences_kept` (frases que
ficaram como o gerador escreveu por causa do limite do campo) e
`plain_fields_kept` (campos de frase única que ficaram como o gerador
escreveu pelo mesmo motivo).

### Regras da rede

1. Frase a frase, da esquerda para a direita, sobre o texto normalizado para
   NFC. Numa mesma posição vence a grafia mais longa. A frase é relida até
   nada mais mudar: nenhuma saída traz uma grafia da tabela, então uma saída
   nunca é trocada, mas o termo que ficou por causa da vizinha ("Core" em "Leg
   day - Core") é lido sem ela quando a vizinha também era um termo. Texto em
   que nenhuma linha age volta como a mesma sequência de caracteres (sem
   normalizar).
2. Só palavra inteira: a grafia colada a letra, número, "_", "@" ou "-" não é
   o termo (`reps_range`, "Push-up", "Pulldown", "score"). "/", "+",
   parênteses e pontuação NÃO são cola: os dois lados de
   "Isquiotibiais/Glúteos" são lidos. Uma exceção: número colado antes de
   reps/rep ("12reps" vira "12 repetições"). O que conta como letra e como
   número: letra é letra do alfabeto latino, com ou sem acento (A–Z, a–z e
   toda letra até U+024F, inclusive "ª", "º" e "µ"); número é 0–9 ou um de
   "²", "³", "¹", "¼", "½", "¾". Até U+024F isso é exatamente o que o Unicode
   chama de letra e de número (travado caractere a caractere no teste). Depois
   disso nada é cola: "→", "–", "—", "…", aspas curvas e emoji nunca foram, e
   letra ou número de outro alfabeto (grego, cirílico e os demais) deixou de
   ser — "Coreж" é lido como "Core" (RC TL-15). As fronteiras são escritas
   como faixas explícitas, nunca com as classes Unicode de toda letra e de
   todo número: com elas, o primeiro texto do processo com um caractere fora
   do Latin-1 ("→", "–", "…") parava o Node por 4 a 9 segundos enquanto o V8
   compilava a expressão; com as faixas, a rede leva de 50 a 157 ms na
   primeira sugestão de um processo (medido em processo novo, com um build do
   Xcode ao lado) e de 12 a 30 ms nas seguintes. Travado, com teto de 1 s, em
   `packages/agent/src/flow-plain-training-language.first-call.test.ts`.
3. Trecho de endereço é protegido inteiro (esquema "://", "www." ou o alvo de
   um link Markdown).
4. As divisões em inglês não agem dentro de NOME de exercício nem da lista de
   EQUIPAMENTOS. Nos outros campos, Push, Pull, Legs, Upper, Lower e Core
   soltas não agem quando a palavra vizinha, de um lado ou do outro, separada
   só por espaço, está na lista fechada de inglês (abaixo): "Pull Up", "Face
   Pull", "Band Pull Apart" e "Upper back" ficam.
5. "falha" (sozinha ou com técnica, muscular, concêntrica) só depois de "até
   a", "até à", "até", "à", "próximo da", "próximo à", "perto da", "antes
   da". Depois de "até" sem artigo, o artigo entra ("até falha" vira "até a
   última repetição bem feita"). Depois de "à" sozinho não é o termo quando
   segue "de", "do", "da", "dos", "das", "na", "no", "nas", "nos" ou "em"
   ("devida à falha na execução"). "Corrija qualquer falha técnica" e "se a
   técnica falha" não são o termo.
6. composto(s), multiarticular(es), isolador(es), monoarticular(es) e
   uniarticular(es) SOZINHOS só em posição de nome: no início do campo;
   depois de `. ! ? : ; , ( • —` ou quebra de linha; ou logo depois de "o",
   "os", "do", "dos", "no", "nos", "ao", "aos", "pelo", "pelos", "e", "ou",
   "de", "com", "em", "entre", "para". Nunca antes de "por", "pelo", "pela",
   "de", "da", "do", "dos", "das" ("composto por 5 dias") nem de palavra de
   substância (vitamínico, químico, orgânico, ativo, bioativo, natural e os
   plurais: "composto vitamínico"). Depois de qualquer outra palavra ("um
   composto seguro", "treino composto", "priorize compostos") ficam.
   "isolado(s)" sozinho nunca é trocado. As entradas inteiras (exercício ou
   movimento + o adjetivo) agem em qualquer lugar, menos antes de "por",
   "pelo", "pela", "pelos", "pelas".
7. Maiúscula: no início do campo, de uma frase ou de uma linha, a saída segue
   a caixa da primeira letra do que foi trocado; em qualquer outro lugar é
   minúscula. A linha cuja saída muda de gênero ou número leva escritos os
   artigos que troca junto ("as escápulas retraídas" vira "os ombros para
   trás"; "o Upper" vira "a parte de cima do corpo"; "no Legs" vira "nas
   pernas"). Outra palavra que concorde com o termo trocado não é ajustada
   (RC TL-10).
8. Nenhuma linha acrescenta posição do corpo, articulação, direção de
   movimento, carga ou número que a palavra trocada não diga.
9. `rpe_target`: o rótulo repetido sai quando há nota ("RPE 8" vira "8") e o
   "/10" que o gerador escreveu é escrito por extenso ("8/10" vira "8 de
   10"). A escala só é acrescentada a uma nota pura com o sim do dono (D1).
10. Sigla (RPE, PSE, RIR, PPL, MMSS, MMII) só em maiúsculas: "rir" é verbo.
    "PSE" sozinha fica antes de palavra terminada em "a" ou "as" ("PSE
    alta"), que concorda com ela e não com "esforço".
11. RIR e a sua contagem. A sigla liga a contagem à direita ("RIR 2") e o
    texto simples liga à esquerda ("2 repetições de sobra"). Com número de UM
    lado da sigla, esse número é a contagem ("RIR 2", "2 RIR"). Com número dos
    DOIS lados ("Séries de 12 RIR 2", "Semana 1 RIR 3", "2 RIR: 3") não dá
    para saber qual dos dois é a contagem: a sigla fica, nenhuma palavra é
    trocada e nenhum número muda de lugar (RC TL-15). Um número conta como
    lado quando só espaços o separam da sigla; antes dela, também um
    travessão ou hífen ("Semana 1 - RIR 3" fica, porque "Semana 1 - 3
    repetições de sobra" seria lido como a faixa "1 - 3"); depois dela, também
    ":" ou "=". Em "Séries de 12, RIR 2" e em "Séries de 12 (RIR 2)" só há
    número de um lado, e a contagem é o 2. Depois da sigla, uma faixa só é a
    contagem quando está escrita como faixa ("RIR 2-3" vira "2-3 repetições
    de sobra"); com espaços em volta do traço ("RIR 2 - 3 séries") o segundo
    número pode ser outra coisa, então as palavras entram no lugar da sigla e
    nenhum número muda de lugar ("repetições de sobra 2 - 3 séries"). As
    grafias por extenso ("repetições em reserva") são trocadas onde
    estiverem, porque já ligam o número como o texto simples liga.

Limites dos campos. Em texto corrido (`notes` e `progression_rule` 500;
`notes` do exercício e cada passo ou erro 300) as frases são trocadas uma a
uma; se o campo passaria do limite, as ÚLTIMAS frases trocadas voltam à
redação do gerador até caber. Em campo de frase única (`day` 20, `focus` e
`muscle_group` 80, `name` 120, `reps_range` e `rpe_target` 40,
`equipment_summary` 500) o valor do gerador fica inteiro quando o simples não
cabe: o dia "Upper A" continua "Upper A", porque "Parte de cima do corpo A"
tem 24 caracteres. Nada é cortado e o rascunho continua pronto para revisar.

### Tabela ativa

Texto editorial, para o dono ler: uma linha por item, e qualquer linha pode
ser riscada (tirar a linha daqui, de `FLOW_PLAIN_TRAINING_VOCABULARY` e do
literal do teste na mesma mudança). `<nota>` é a nota do esforço ("8", "8-9",
"7.5", "8/10"), colada ou depois de espaço, ":" ou "="; `<n>` é uma contagem
("2", "1-2"). Letras valem com e sem acento, em qualquer caixa (as siglas, só
em maiúsculas).

| Grafias | Vira | Onde age |
| --- | --- | --- |
| `Push/Pull/Legs`; `Push Pull Legs`; `Push-Pull-Legs`; `PPL` | `empurrar/puxar/pernas` | fora de nome de exercício e de equipamento (regra 4) |
| `Upper/Lower`; `Upper-Lower`; `Upper Lower` | `parte de cima/parte de baixo` | fora de nome de exercício e de equipamento (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Full Body`; `Full-Body`; `Fullbody` | `corpo inteiro` | fora de nome de exercício e de equipamento (regra 4) |
| `Upper body` | `parte de cima do corpo` | fora de nome de exercício e de equipamento (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Lower body` | `parte de baixo do corpo` | fora de nome de exercício e de equipamento (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Lower back` | `lombar` | fora de nome de exercício e de equipamento (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Push day` | `dia de empurrar` | fora de nome de exercício e de equipamento (regra 4) |
| `Pull day` | `dia de puxar` | fora de nome de exercício e de equipamento (regra 4) |
| `Leg day`; `Legs day` | `dia de pernas` | fora de nome de exercício e de equipamento (regra 4) |
| `Push` | `empurrar` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4) |
| `Pull` | `puxar` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4) |
| `Legs` | `pernas` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4); troca junto "o" por "as", "do" por "das", "no" por "nas", "ao" por "às", "pelo" por "pelas" |
| `Upper` | `parte de cima do corpo` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Lower` | `parte de baixo do corpo` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4); troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "pelo" por "pela", "um" por "uma" |
| `Core` | `abdômen` | fora de nome de exercício e de equipamento, e nunca ao lado de palavra da lista de inglês (regra 4) |
| `MMSS` | `parte de cima do corpo` | em qualquer texto; troca junto "os" por "a", "dos" por "da", "nos" por "na", "aos" por "à", "pelos" por "pela" |
| `MMII` | `parte de baixo do corpo` | em qualquer texto; troca junto "os" por "a", "dos" por "da", "nos" por "na", "aos" por "à", "pelos" por "pela" |
| `RPE <nota>` | `esforço <nota>` | em qualquer texto; em `rpe_target` fica só a nota (regra 9) |
| `PSE <nota>` | `esforço <nota>` | em qualquer texto; em `rpe_target` fica só a nota (regra 9); troca junto "a" por "o", "da" por "do", "na" por "no", "à" por "ao", "pela" por "pelo", "uma" por "um" |
| `RPE` | `esforço` | em qualquer texto |
| `PSE` | `esforço` | em qualquer texto, menos antes de palavra terminada em "a" ou "as" ("PSE alta"); troca junto "a" por "o", "da" por "do", "na" por "no", "à" por "ao", "pela" por "pelo", "uma" por "um" |
| `RIR <n>`; `<n> RIR` | `<n> repetições de sobra` (com 1: `<n> repetição de sobra`) | em qualquer texto, menos quando há número dos dois lados da sigla ("Séries de 12 RIR 2" fica: regra 11) |
| `RIR`; `repetições em reserva`; `reps em reserva` | `repetições de sobra` | em qualquer texto; a sigla, menos quando há número dos dois lados dela (regra 11) |
| `repetição em reserva`; `rep em reserva` | `repetição de sobra` | em qualquer texto |
| `falha muscular técnica`; `falha técnica muscular`; `falha muscular`; `falha técnica`; `falha concêntrica`; `falha` | `última repetição bem feita` | só depois de "até", "até a", "até à", "à", "próximo da", "próximo à", "perto da", "antes da"; depois de "à" sozinho, não quando segue "de", "do", "da", "na", "no" ou "em" (regra 5) |
| `progressão linear` | `evolução passo a passo` | em qualquer texto |
| `reps` | `repetições` | em qualquer texto; aceita o número colado ("12reps") |
| `rep` | `repetição` | em qualquer texto; aceita o número colado ("12reps") |
| `exercícios compostos`; `movimentos compostos`; `exercícios multiarticulares`; `movimentos multiarticulares` | `exercícios de vários músculos` | em qualquer texto, menos antes de "por", "pelo", "pela", "pelos", "pelas" (regra 6) |
| `exercício composto`; `movimento composto`; `exercício multiarticular`; `movimento multiarticular` | `exercício de vários músculos` | em qualquer texto, menos antes de "por", "pelo", "pela", "pelos", "pelas" (regra 6) |
| `exercícios isolados`; `movimentos isolados`; `exercícios isoladores`; `movimentos isoladores`; `exercícios monoarticulares`; `movimentos monoarticulares`; `exercícios uniarticulares`; `movimentos uniarticulares` | `exercícios de um músculo só` | em qualquer texto, menos antes de "por", "pelo", "pela", "pelos", "pelas" (regra 6) |
| `exercício isolado`; `movimento isolado`; `exercício isolador`; `movimento isolador`; `exercício monoarticular`; `movimento monoarticular`; `exercício uniarticular`; `movimento uniarticular` | `exercício de um músculo só` | em qualquer texto, menos antes de "por", "pelo", "pela", "pelos", "pelas" (regra 6) |
| `compostos`; `multiarticulares` | `exercícios de vários músculos` | só em posição de nome, e nunca antes de "por", "pelo", "pela", "de", "da", "do", "dos", "das" nem de palavra de substância (regra 6) |
| `composto`; `multiarticular` | `exercício de vários músculos` | só em posição de nome, e nunca antes de "por", "pelo", "pela", "de", "da", "do", "dos", "das" nem de palavra de substância (regra 6) |
| `isoladores`; `monoarticulares`; `uniarticulares` | `exercícios de um músculo só` | só em posição de nome, e nunca antes de "por", "pelo", "pela", "de", "da", "do", "dos", "das" nem de palavra de substância (regra 6) |
| `isolador`; `monoarticular`; `uniarticular` | `exercício de um músculo só` | só em posição de nome, e nunca antes de "por", "pelo", "pela", "de", "da", "do", "dos", "das" nem de palavra de substância (regra 6) |
| `pegada pronada` | `pegada por cima` | em qualquer texto |
| `pegada supinada` | `pegada por baixo` | em qualquer texto |
| `retração escapular`; `retração das escápulas`; `retração de escápulas` | `postura de ombros para trás` | em qualquer texto |
| `escápulas retraídas` | `ombros para trás` | em qualquer texto, menos depois de outra palavra terminada em "as" ou antes de "e" ou vírgula mais palavra terminada em "adas" ou "idas"; troca junto "as" por "os", "das" por "dos", "nas" por "nos", "às" por "aos", "pelas" por "pelos", "suas" por "seus" |
| `isquiotibiais` | `músculos de trás da coxa` | em qualquer texto |
| `isquiotibial` | `músculo de trás da coxa` | em qualquer texto |
| `gastrocnêmio e o sóleo`; `sóleo e o gastrocnêmio`; `gastrocnêmio e sóleo`; `sóleo e gastrocnêmio`; `gastrocnêmio/sóleo`; `sóleo/gastrocnêmio`; `gastrocnêmio, sóleo`; `sóleo, gastrocnêmio`; `gastrocnêmio+sóleo`; `sóleo+gastrocnêmio` | `músculos da panturrilha` | em qualquer texto; troca junto "o" por "os", "do" por "dos", "no" por "nos", "ao" por "aos", "pelo" por "pelos" |
| `gastrocnêmios`; `sóleos` | `músculos da panturrilha` | em qualquer texto |
| `gastrocnêmio`; `sóleo` | `músculo da panturrilha` | em qualquer texto |
| `cadeia posterior` | `parte de trás do corpo` | em qualquer texto |
| `cadeia anterior` | `parte da frente do corpo` | em qualquer texto |
| `porção clavicular do peitoral maior`; `porção clavicular do peitoral`; `porção clavicular do peito`; `porção clavicular` | `parte de cima do peito` | em qualquer texto |
| `cabeça longa do tríceps braquial`; `cabeça lateral do tríceps braquial`; `cabeça medial do tríceps braquial`; `cabeça longa do tríceps`; `cabeça lateral do tríceps`; `cabeça medial do tríceps` | `parte de trás do braço` | em qualquer texto |
| `cabeça longa do bíceps braquial`; `cabeça curta do bíceps braquial`; `cabeça longa do bíceps`; `cabeça curta do bíceps` | `parte da frente do braço` | em qualquer texto |

Lista fechada de vizinhas em inglês (regra 4): Up, Ups, Down, Downs, Over,
Overs, Apart, Aparts, Through, Throughs, Around, Press, Presses, Row, Rows,
Jerk, Jerks, Deadlift, Deadlifts, Hold, Holds, Split, Splits, Legged,
Stability, Rack, Racks, Band, Bands, Cable, Cables, Sled, Sleds, Machine,
Machines, Back, Body, Chest, Abs, Arm, Arms, Leg, Face, Trap, Traps, Lat,
Lats, Pec, Pecs, Glute, Glutes, Limb, Limbs, Day, Days, Workout, Workouts,
Training, Session, Sessions, Exercise, Exercises, Movement, Movements,
Routine, Strength, Work.

### O que espera o dono (escrito, testado e DESLIGADO)

Nada abaixo age em produção: `FLOW_PLAIN_TRAINING_OWNER_SWITCHES` é
`{ effortOutOfTen: false, renames: [] }`, e a ferramenta chama a rede sem
outro argumento. Ligar um item é mudar esse literal, com a data do sim do dono
aqui e os textos do golden na mesma mudança.

- **D1 — escala do esforço** (`effortOutOfTen`). A nota de 1 a 10 ganharia a
  escala: `rpe_target` "9" viraria "9 de 10", "8-9" viraria "8-9 de 10", e no
  texto "RPE 8-9" viraria "esforço 8-9 de 10". Nota fora de 1 a 10 ("15") ou
  texto ("moderado") ficaria como veio. É o único acréscimo de número em toda
  a rede, e é número que o gerador não escreveu e que o documento do método
  não define. Hoje a aba Plano mostra "Esforço alvo 9" (RC TL-14). sim do
  dono em: ____
- **D2 — nomes de exercício** (`renames`), um sim por linha. Os dois
  candidatos são nomes usados em academia, sem fonte no repositório:

  | Grafias | Viraria | Onde agiria |
  | --- | --- | --- |
  | `Hip Thrust`; `Hip-Thrust` | `elevação pélvica` | em qualquer texto; troca junto "o" por "a", "do" por "da", "no" por "na", "ao" por "à", "um" por "uma" |
  | `Military press` | `desenvolvimento militar` | em qualquer texto |

  `Hip Thrust`: sim do dono em: ____ · `Military press`: sim do dono em: ____

  "Stiff" e "Leg Press" não têm candidato: a recomendação é manter, porque é
  como a academia e a máquina chamam (uma descrição diria como posicionar o
  joelho, o que o plano não disse). Hoje os quatro nomes ficam como o gerador
  escreveu (RC TL-13).

### O que é garantido

Determinístico, valha o que o modelo escrever, num rascunho de treino que o
Flow cria depois desta mudança:

1. Toda linha da tabela ativa é aplicada, nos campos lidos, sempre que a
   grafia aparece como palavra inteira, dentro das regras 3 a 6, 10 e 11, e o
   texto simples cabe no limite do campo. O que as regras deixam passar de
   propósito está em RC TL-15; o que fica como o gerador escreveu por causa
   do limite, em RC TL-7.
2. O chat e a aba Plano mostram o mesmo texto: o bloco da sugestão no chat é
   montado do rascunho gravado (a única diferença possível continua sendo a
   troca dos nomes internos, que age só no chat: RC FN-3).
3. Números e estrutura são os do gerador: séries, descanso, minutos, tipo do
   plano, número de dias, de exercícios, de passos e de erros, e todo dígito
   de todo texto, na mesma ordem. Nenhum dígito é acrescentado nem retirado.
4. Nenhuma linha acrescenta instrução de execução: a tabela inteira é travada
   como literal no teste.
5. Formato: mesmas chaves e tipos; nenhum campo passa do limite; nada é
   cortado; um rascunho que seria `ready_for_review` continua
   `ready_for_review`.
6. Aplicar o vocabulário duas vezes não muda mais nada.
7. Só no Flow e só no treino: o vocabulário é importado por
   `tools/plan-proposal-tools.ts` e por mais nenhum arquivo, e chamado uma
   vez, dentro de `propoe_plano_treino`. `gera_treino`, `processMessage`, o
   prompt legado, a sugestão de cardápio, a importação de documento, a edição
   feita pela pessoa e o texto livre do chat nunca chegam a ele.
8. Nome de exercício não é trocado e o esforço não ganha escala enquanto o
   dono não disser sim.

O teto do chat. O texto simples é mais longo que o do gerador (o parágrafo de
progressão do cenário relatado cresce 35 caracteres). O chat mostra até 2.000
caracteres da sugestão (1.958 para os blocos): num plano perto desse teto, o
chat perde primeiro o parágrafo "Progressão:" e depois dias inteiros, do fim
para o começo, e termina em '(O restante está em "Revisar sugestão".)'; a aba
Plano continua com tudo. O rascunho real de 2026-09-30 (18 exercícios) passa
de 1.337 para 1.373 caracteres e continua inteiro.

Travado em
`packages/agent/src/__golden__/audit-10-10-flow-workout-plain-language.test.ts`
(o turno relatado, "Nenhuma limitacao e sem prioridade", com os textos exatos
do rascunho gravado em 2026-10-10 16:44:49Z, pela ferramenta real e pelo
pipeline real com modelo roteirizado) e em
`packages/agent/src/flow-plain-training-language.test.ts` (cada regra).

> RC TL-1 — cenário rascunho de treino do Flow de 2026-10-10 16:44:49Z (conta de teste, 5 dias, 29 exercícios) variante os 23 exercícios, o grupo muscular de 3 exercícios e os dias de terça e quinta, cujo texto o arquivo de evidência não traz NÃO coberta nesta PR (pendência da audit 2026-10-10). O fim do chat só está provado no recorte de 3 dias e 6 exercícios: para o turno relatado inteiro o golden é variante próxima. No plano inteiro o texto simples é mais longo (só o parágrafo de progressão cresce 35 caracteres) e o chat pode terminar em '(O restante está em "Revisar sugestão".)' sem o parágrafo de progressão e sem o último dia; a aba Plano continua com tudo. Só a releitura autorizada do rascunho inteiro, fora desta raia, fecha esta linha.

> RC TL-2 — cenário termos "porção clavicular", "cabeça longa do tríceps", "isquiotibiais", "gastrocnêmio", "sóleo", "cadeia posterior" e "Military press" variante a frase exata em que cada um apareceu no rascunho de 2026-10-10 (não está no arquivo de evidência; os seis primeiros são cobertos numa frase de teste, que é variante próxima, inclusive com barra; o sétimo está em RC TL-13) NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-3 — cenário sugestão de treino do Flow variante resposta do MODELO REAL ao pedido de linguagem simples (o modelo é roteirizado nos testes; nenhum turno real rodou com o pedido novo) NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-4 — cenário termo técnico ou nome em inglês variante FORA do vocabulário fechado (por exemplo "peitoral", "quadríceps", "dorsal", "deltoide", "amplitude", "stress", "escápulas" sem "retraídas", "unilateral" e "unilaterais", "pegada neutra", "cabeça longa" sem o músculo, "Upper back", "Pulldown", "Pullover", "Crossover", "drop set") NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-5 — cenário linha do exercício no chat ("• Hip Thrust com Barra — 4×8-12, descanso 90 s") variante a notação séries×repetições, o "s" de segundos e o rótulo "Progressão:" NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-6 — cenário rascunho de treino gravado ANTES desta mudança (inclusive o de 2026-10-10 16:44:49Z no ambiente de teste) e mensagem do chat já gravada variante texto já armazenado, que não é reescrito NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-7 — cenário campo cujo texto simples passaria do limite (observações, progressão e equipamentos 500; observação do exercício, passos e erros 300; nome 120; foco e grupo muscular 80; repetições e esforço 40; dia 20) variante frases ou campo que ficam como o gerador escreveu, por exemplo o dia "Upper A" NÃO coberta nesta PR (pendência da audit 2026-10-10). No campo do dia, "Upper" e "Lower" nunca são trocadas: "Parte de cima do corpo" tem 22 caracteres, "Parte de baixo do corpo" tem 23 e o limite é 20; um plano com os dias "Upper A" e "Lower A" continua com esses dois rótulos em inglês no chat e na aba Plano.

> RC TL-8 — cenário perguntas do Flow ANTES de montar o treino e respostas a dúvidas depois variante texto livre do chat fora do turno da sugestão (inclusive uma pergunta sobre "falha muscular" vinda da descrição do parâmetro compartilhado) NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-9 — cenário sugestão de treino para conta em INGLÊS variante pedido ao gerador e vocabulário só em português NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-10 — cenário frase depois da troca variante redação que continua sem ser do dia a dia, porque a rede troca palavras e não reescreve a frase ("Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo)", "Exercício de vários músculos principal para peitoral", "Panturrilha (músculo da panturrilha)") NÃO coberta nesta PR (pendência da audit 2026-10-10). A concordância com a palavra vizinha também não é ajustada: "12 rep" vira "12 repetição", "MMII fortes" vira "Parte de baixo do corpo fortes" e "Treine a PSE 8" vira "Treine o esforço 8" (o "a" era preposição e foi lido como artigo).

> RC TL-11 — cenário plano importado de foto ou PDF, texto digitado pela pessoa em "Revisar sugestão" e sugestão de cardápio variante texto que não é sugestão de treino escrita pelo Flow, deixado como está de propósito NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-12 — cenário frase de abertura ou de fecho escrita pelo modelo no turno da sugestão de treino variante termo técnico fora do bloco da sugestão NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-13 — cenário nomes de exercício em inglês vistos pelo dono ("Hip Thrust com Barra", "Stiff Unilateral com Halter", "Leg Press 45°") e "Military press" variante troca do nome pela rede determinística, que entra desligada até o dono aprovar cada nome NÃO coberta nesta PR (pendência da audit 2026-10-10). O nome fica como o gerador escreveu; só o pedido ao modelo pede o nome usado nas academias do Brasil.

> RC TL-14 — cenário "Esforço alvo 9" na aba Plano variante explicação da escala da nota ("9 de 10"), que entra desligada até o dono decidir NÃO coberta nesta PR (pendência da audit 2026-10-10). A sigla sai do texto ("RPE 8-9" vira "esforço 8-9"); a nota fica como o gerador escreveu.

> RC TL-15 — cenário grafia do vocabulário fechado variante que a regra deixa passar de propósito (colada a letra, número, "_", "@" ou "-"; sigla em minúsculas, como "rpe" e "rir"; a sigla RIR com número dos dois lados, como "Séries de 12 RIR 2"; "PSE" antes de palavra terminada em "a" ou "as"; as divisões em inglês dentro de nome de exercício ou de equipamento; Push, Pull, Legs, Upper, Lower e Core vizinhas de uma palavra da lista fechada de inglês; "falha" fora de "até", "até a", "à", "próximo da", "próximo à", "perto da", "antes da", e depois de "à" quando segue "de", "do", "da", "na", "no" ou "em"; "composto" e "isolador" depois de uma palavra que não anuncia nome, como um verbo, ou "composto" antes de "por", de "de" e de palavra de substância; "escápulas retraídas" depois de outra palavra terminada em "as" ou antes de "e" ou vírgula mais uma palavra terminada em "adas" ou "idas"; trecho de endereço), composto em inglês com vizinha fora da lista, trocado palavra por palavra em texto corrido ("Core Blaster" vira "abdômen Blaster"), frase trocada pela metade ("Combine compostos e isoladores" vira "Combine compostos e exercícios de um músculo só"), e grafia colada a letra ou número de outro alfabeto, que não conta como cola ("Treino de Coreж" vira "Treino de abdômenж") NÃO coberta nesta PR (pendência da audit 2026-10-10)

> RC TL-16 — cenário turno relatado ("Nenhuma limitacao e sem prioridade", 2026-10-10 16:44:49Z) variante a resposta do modelo na segunda chamada do turno, os argumentos que ele passou à ferramenta e a data de nascimento da conta de teste, que não foram registrados NÃO coberta nesta PR (pendência da audit 2026-10-10). A mensagem não é um pedido único: o turno faz duas chamadas ao modelo. No golden a segunda resposta é roteirizada nas duas formas possíveis (o modelo resume, e o sistema põe a sugestão gravada entre a abertura e o fecho fixos, que é o fecho que a tela mostrou; ou o modelo copia a sugestão), e os argumentos são reconstruídos da conversa.

## Proposta de treino

```json
{
  "kind": "workout",
  "workout_type": "musculacao",
  "duration_min": 40,
  "intensity": "moderada",
  "performed_at": "2026-07-20T18:30:00-04:00"
}
```

As kcal são calculadas no servidor pelo tipo, duração, intensidade e peso do
perfil, com fallback determinístico de 70 kg quando o peso ainda não existe.

`workout_type` é texto livre (1 a 80 caracteres depois do trim). Desde
2026-10-04, só para a consulta da taxa, o servidor normaliza o texto
(minúsculas, sem acento, espaços, hífens e "_" viram um único "_") e o casa com
um slug ativo do catálogo `workout_types` ou, na falta, com o nome de exibição
de um único slug: "Natação", 40 min, moderada, 70 kg → 400 kcal (antes 240). O
`workout_type` devolvido e gravado continua o texto enviado; o formato da
resposta não mudou. Um tipo que o catálogo não tem ("Capoeira") ou escrito com
outra palavra ("Bike") segue na taxa genérica (6,0 kcal/min), sem aviso na
resposta. Proposta, edição e confirmação de treino leem o catálogo uma vez
cada. Se essa leitura falha: um `workout_type` que já está em forma de slug
(minúsculas, sem acento, sem espaço nem hífen, como `musculacao`) é calculado
como antes da mudança; qualquer outro texto responde
`500 workout_calculation_failed`. Regra, números e pendências:
`docs/CALCULO-MPP.md` §2d.

## Edição e exclusão de alimentos confirmados

As rotas `/meal-records/:id` usam um `meal_logs.id` pertencente à conta
autenticada. `/registrations/:id` continua usando `pending_registrations.id` e
recusando alterações de propostas já confirmadas. O DTO e a leitura de `/history`
permanecem iguais.

`GET` devolve somente `record_id`, `scope`, `expected_version`, `item_ids`,
`items`, `local_date`, `timezone`, `day_closed`, `editable` e `edit_block_reason`.
Cada item contém `id`, `food_name`, `quantity_g`, `kcal`, `protein_g`, `carbs_g`,
`fat_g`, `consumed_at`, `meal_type` e `source`, preservando os valores nulos
persistidos. Evidência privada, mídia e contexto completo nunca saem do servidor.
Origem não nula resolve o conjunto pelo proprietário, snapshot e marcador exatos;
origem nula significa apenas o alimento âncora (`scope: "item"`). Não se infere
uma refeição pelo nome, categoria ou horário. Grupos acima de 30 alimentos são
recusados, sem truncar a seleção silenciosamente.

A versão `v1:<sha256>` representa contexto operacional atual, snapshot completo e
linhas completas do grupo. O cliente guarda o token recebido. Somente o dia
local atual, aberto, pode ser alterado; as datas persistidas e horários de
todos os alimentos do grupo devem concordar com o fuso oficial, mesmo quando
a seleção altera apenas um deles. O cache de autenticação não define
o fuso ou o país. Um dia fechado ou diferente continua legível, com
`editable: false` e `MEAL_DAY_NOT_EDITABLE`.

`PATCH` recebe `{expected_version, item_ids: [id], items: [...]}`. Edita somente
o alimento âncora; a resolução existente pode produzir até 30 ingredientes,
respeitando o limite de 30 do conjunto resultante. `DELETE` recebe
`{expected_version, item_ids: [...]}`, de 1 a 30 UUIDs únicos do conjunto oficial.
Ambos exigem `Idempotency-Key`. Não aceitam macros, estado privado, modo de
cálculo ou mudança de dia/categoria enviados pelo cliente.

Mudar apenas a quantidade do mesmo nome normalizado, sem nova `user_kcal`, usa
`reconcilePendingMealEdit` sobre a linha oficial: calorias com uma casa e macros
com duas, preservando fonte, referência, confiança e origem, inclusive nulos e
fontes legadas. Não consulta catálogo ou mídia nesse caminho, nem exige país
confirmado para essa proporção. Nutrientes ausentes não viram zero. A quantidade
precisa caber na precisão persistida de duas casas. Trocar o alimento ou fornecer
uma nova `user_kcal` usa o cálculo existente e exige país oficial confirmado;
esse preparo pode registrar `product_events` fora da transação de gravação.
Não se reconstrói a precisão antiga nem a entrada independente de calorias que
não foi persistida.

A RPC mobile compara linhas completas sob locks, confere relógio após os locks,
substitui UUIDs finitos ou apaga a seleção, recalcula os totais oficiais e conclui
o ledger na mesma transação. Preserva itens restantes, meta, treino, água, XP e
progresso. Apagar o último alimento publica consumo/macros zero; o registro
normal continua proibindo uma lista vazia. Colisões e falhas de conclusão
desfazem a gravação. Um recibo concluído mantém identidade e resultado mesmo
após expiração, remoção do alvo ou mudança de dia/contexto; outras rotas conservam
a política de expiração anterior.

Resposta `200`: envelope habitual `data/meta`; `data` contém somente `record_id`,
`operation` (`updated`/`deleted`), `removed_item_ids`, `new_item_ids`,
`next_record_id` e `snapshot` com `id`, `date`, `calories_consumed`, `protein_g`,
`carbs_g`, `fat_g`, `daily_balance`. No replay, dados originais são mantidos e
somente o request ID atual e o header `Idempotency-Replayed: true` são aplicados.
Um resultado novo deve corresponder ao snapshot preparado; na exclusão, o
próximo registro deve pertencer ao grupo sobrevivente, ou ser nulo se o grupo
ficou vazio. Essas verificações não comparam um replay ao estado atual.
Falha da leitura posterior conserva esse recibo: recuperação usa GET do
`next_record_id`, sem reenviar a mutação. Todos os retornos são `no-store` com
`Vary: Authorization`.

> RC C11 — cenário corrigir refeição de dia já fechado NÃO coberta nesta PR (pendência da audit 2026-10-07).

## Ciclo do pending

1. `propose` calcula e cria um pending; um novo pending cancela o anterior do
   mesmo paciente conforme a regra já existente.
2. `PATCH :id` só funciona em `pending` não expirado e recalcula todo o payload,
   com request key novo. A edição mantém a origem do pending: só o que foi criado
   por `propose` continua sendo confirmado como registro novo (item 5).
3. `confirm` grava primeiro via ferramenta atômica e só então marca `confirmed`.
4. Retry após gravação parcial é deduplicado pelo request key salvo na proposta.
   Se a gravação aconteceu e a marcação `confirmed` falhou, o pending ainda
   aparece como `pending`: um novo `confirm` fecha sem gravar de novo, e um
   `PATCH` ou um `DELETE` também fecha o pending como `confirmed` e responde
   `409 registration_already_confirmed`, sem editar nem cancelar (editar
   trocaria o request key e a refeição seria gravada duas vezes; cancelar
   deixaria o pending `cancelled` com a refeição gravada, e a proposta seguinte
   da mesma refeição a gravaria de novo). O `PATCH` e o `DELETE` de um pending
   que já está `confirmed` respondem o mesmo código. Se a leitura que verifica
   isso falhar, o pedido responde `500 registration_lookup_failed` e o pending
   não muda. O `PATCH` olha a validade antes dessa verificação (`410`); o
   `DELETE` não olha a validade.
   - Refeição: a verificação vale só para pending criado por `propose` (a
     chave dele é o `Idempotency-Key` de uma tentativa, então só o confirm
     dele grava sob ela). Pending de refeição de outra origem (WhatsApp, cuja
     chave é o id da mensagem e pode ter registros de outra refeição da mesma
     mensagem) é editado e cancelado como antes.
   - Treino: vale para qualquer origem, por request key + tipo — a mesma
     idempotência do registro de treino.
   - `registration_already_confirmed` quer dizer "este registro já está
     salvo": o cliente NÃO deve criar outra proposta (como toda confirmação de
     proposta do app soma, uma nova proposta gravaria a mesma refeição de
     novo). O certo é tratar como confirmado; `POST :id/confirm` responde
     `already_confirmed: true` sem gravar. No `DELETE` o código também quer
     dizer que nada foi cancelado nem apagado: o registro continua salvo.
     `registration_not_pending` continua valendo para pending `expired` (e
     para `PATCH`/`confirm` de um `cancelled`), onde criar outra proposta é o
     caminho.
   - O servidor só recusa o pedido; ele não impede uma proposta nova. Uma
     proposta nova da mesma refeição depois da recusa grava a refeição pela
     segunda vez.
   - iPhone: coberto no código do app em commit separado do mesmo dia
     (9624cd5), ainda não verificado no aparelho — um
     `409 registration_already_confirmed` ao editar ou cancelar fecha a
     proposta como confirmada, com a mensagem "Este registro já estava salvo.
     A alteração não foi aplicada.", e "Criar nova proposta" não aparece.
     Nenhum teste de interface do app dirige o 409 (só testes de unidade). Um
     build anterior a esse commit (lido no código, não executado no aparelho)
     não conhece o código: mostra "Não foi possível concluir. Tente
     novamente.", mantém a proposta na tela e "Tentar novamente" reenvia o
     mesmo `PATCH` ou o mesmo `DELETE` (mesma resposta); o botão Confirmar
     recebe `already_confirmed: true` e mostra "Registro confirmado."; nesse
     build quem tocou em Cancelar não é avisado de que a refeição já está
     salva.
5. Refeição criada por `propose`: cada proposta confirmada é um registro novo.
   Repetir a mesma refeição soma — nada é substituído nem descartado, com
   qualquer intervalo. O servidor só mede, em dois eventos internos com
   contagens e ids (sem nome de item):
   `tool.replace_implicit_skipped_additive_confirmation` (mesmos nomes em até
   30 min) e `tool.same_day_duplicate_kept_additive_confirmation` (item idêntico,
   nome e gramas, já presente nessa refeição do dia). Exceções:
   - itens com o mesmo nome dentro de UMA proposta são fundidos pela ferramenta
     (mesmas gramas viram um registro só; nutrição diferente entre as cópias
     faz o `confirm` falhar com `500` até a proposta ser editada);
   - pending que não foi criado por `propose` (WhatsApp) segue, ao ser
     confirmado aqui, as regras do WhatsApp: pode substituir registros recentes
     ou descartar item idêntico (`mobile.registration.implicit_replace` mede a
     substituição);
   - treino: um treino idêntico (tipo e duração) em 6 h é descartado e o
     `confirm` responde `deduped: true`.
   Esta API não edita nem apaga refeição já confirmada: um registro feito por
   engano não pode ser desfeito pelo app.
6. `DELETE :id` altera apenas um pending para `cancelled`; não apaga logs já
   confirmados. Se o registro desse pending já foi gravado, o `DELETE` é
   recusado com `409 registration_already_confirmed` (item 4).
7. Estado expirado, editado, cancelado ou concorrente produz erro explícito.

### Erros do pending

| HTTP | `error.code` | Rota | Quando ocorre | O que o cliente faz |
|---:|---|---|---|---|
| `404` | `registration_not_found` | todas | pending inexistente ou de outro paciente | descartar a proposta |
| `409` | `registration_already_confirmed` | `PATCH`, `DELETE` | o registro desse pending já foi gravado (pending `confirmed`, ou gravado com a marcação pendente — item 4); no `DELETE`, nada foi cancelado | tratar como confirmado; não criar outra proposta. No código do app do iPhone (commit 9624cd5, ainda não verificado no aparelho): fecha a proposta como confirmada com "Este registro já estava salvo. A alteração não foi aplicada."; um build anterior mostra a falha genérica (item 4) |
| `409` | `registration_not_pending` | `PATCH`, `confirm`, `DELETE` | `PATCH` e `confirm`: pending `cancelled` ou `expired`; `DELETE`: pending `expired` (o `cancelled` responde `200`) | criar outra proposta, se ainda houver o que registrar |
| `409` | `registration_update_conflict`, `registration_confirmation_conflict`, `registration_cancel_conflict` | `PATCH`, `confirm`, `DELETE` | o pending mudou durante a operação | reler e tentar de novo |
| `409` | `registration_proposal_invalid` | `confirm` | proposta guardada fora do formato | criar outra proposta |
| `410` | `registration_expired` | `PATCH`, `confirm` | pending passou de `expires_at` | criar outra proposta |
| `422` | `registration_unresolved_items` | `confirm` | item ainda sem cálculo | editar o item |
| `422` | `registration_rejected` | `confirm` | a ferramenta recusou o registro | editar |
| `500` | `registration_lookup_failed` | todas | leitura do pending ou da verificação do item 4 falhou; nada foi alterado | tentar de novo |
| `500` | `registration_confirmation_failed` | `confirm`, `PATCH`, `DELETE` | a gravação pode ter acontecido e a marcação `confirmed` falhou | tentar de novo (deduplicado) |
| `500` | `registration_update_failed`, `registration_cancel_failed` | `PATCH`, `DELETE` | falha ao gravar a edição ou o cancelamento | tentar de novo |

## Limites desta fase

- A conferência de objetivo (`POST /onboarding/eligibility`), o campo
  `protocol_welcome` e `GET /protocol` existem no servidor, mas o app publicado
  ainda não os consome. `POST /onboarding` já recusa, na primeira conclusão, o
  objetivo fora da regra (`422 onboarding_objective_not_eligible`), e o app
  publicado mostra só uma mensagem genérica nesse caso. Não há troca de
  objetivo pelo app.
- Não há chat nativo, envio APNs, StoreKit ou app iOS nesta entrega. Os backends de
  mídia, devices, regras e rotina ainda dependem de integração e QA no app nativo.
- `persona` persiste a escolha e seleciona mensagens futuras, mas o app nativo
  ainda precisa implementar a tela e consumir o contrato.
- O mascote é somente estado não visual; assets, animações e regras de evolução
  permanecem fora desta entrega.
- O CMS educativo não inclui tela iOS, campanhas automáticas, comentários,
  busca textual, HTML rico, mídia inline ou geração/publicação por IA.
- `entitlements` informa assinaturas existentes, mas declara StoreKit indisponível.
  Não há caminho de compra; no ambiente de avaliação o acesso vem de concessão
  manual ou, com o interruptor ligado, da concessão automática da primeira
  conclusão de onboarding ("Acesso de avaliação automático").
- Suplementos e medicamentos têm CRUD versionado, `dose_text` controlado pelo
  paciente, múltiplos horários e histórico de adesão. Orientação clínica,
  recomendação de dose e prescrição permanecem fora do escopo.

### Cliente iOS E3 — candidato local de entrada nos objetivos (2026-10-07)

Ordem do cadastro: boas-vindas → dados corporais → rotina → estilo do Flow → documentos → objetivo → revisão. A conferência só ocorre após todos os documentos exigidos estarem válidos. A decisão e os textos pertencem ao servidor: o cliente não calcula critérios de entrada. Na decisão `assigned`, recomposição aparece marcada como leitura, com aviso integral e detalhe de ganho fechado; em `choice`, somente opções `available` são botões. Os motivos bloqueados ficam visíveis como texto.

Rascunhos retomados conferem os pré-requisitos e buscam uma decisão nova; alterações nos dados invalidam a decisão anterior. Reaceite com `completed_at` histórico mostra apenas documentos/revisão, sem conferência, alteração de objetivo ou mensagem de entrada.

Depois da conclusão confirmada, `protocol_welcome` é apresentado como mensagem do Flow, preservando parágrafos, repetições e quebras de linha. A raiz recebe a conclusão somente no CTA “Ir para Hoje”; o tutorial existente continua pertencendo ao AppShell. Sem mensagem, mantém-se a conclusão imediata. O detalhe de bloqueio e os motivos são recebidos integralmente do servidor; não são textos clínicos locais.

O 422 `onboarding_objective_not_eligible` retorna ao objetivo, pede decisão nova e usa uma chave nova na conclusão seguinte. Uma resposta incerta de conclusão mantém o par chave/corpo original e bloqueia edição enquanto o retry confere esse envio. A interface mostra esse estado explicitamente.

Validação desta etapa é local no simulador e com respostas sintéticas DEBUG, incluindo mensagem de aproximadamente 2.900 caracteres. Não comprova chamada API ao vivo, publicação, aceite visual humano ou protocolos completos. O staging e o cliente publicado continuam exigindo a promoção conjunta autorizada descrita no handoff; E3 entrega somente a entrada. Fechar o app durante a mensagem não a reapresenta automaticamente: leitura posterior em Perfil pertence à E6.

### Cliente iOS E6 — objetivo em Perfil, somente leitura (candidato local)

A entrada “Seu objetivo” consome somente `GET /api/mobile/v1/protocol`, sem envio de dados corporais, escolha ou chave de mutação. Mostra o objetivo armazenado e os números oficiais recebidos; não recalcula, não inventa zero e aceita metas ausentes. A mensagem de entrada abre para leitura integral, com parágrafos e repetições preservados; “Fechar” retorna à consulta, sem concluir cadastro, oferecer tutorial ou trocar o objetivo.

Cada sessão possui seu modelo. Logout invalida leituras pendentes; respostas antigas/canceladas não substituem o estado atual. Atualização conserva o conteúdo e erros oferecem leitura novamente. Sem capacidade, a entrada fica oculta. As variantes sintéticas `--ui-testing-current-objective`, `--ui-testing-current-objective-empty`, `--ui-testing-current-objective-offline` e `--ui-testing-current-objective-long` são restritas a DEBUG; Release usa transporte real ou fica indisponível. Validação ao vivo e publicação permanecem gates próprios.
