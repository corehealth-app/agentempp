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

O escopo é `(patient, key)`. Repetir método, rota e payload reproduz a resposta
original com `Idempotency-Replayed: true`; reutilizar a chave para outra operação
retorna `409 idempotency_key_conflict`. Uma operação simultânea retorna
`409 idempotency_request_in_progress`. O ledger expira em 24 horas e é acessível
somente ao backend.

## Endpoints

| Método | Rota | Contrato |
|---|---|---|
| `GET` | `/me` | identidade pública do paciente, locale, país e timezone |
| `PATCH` | `/me` | altera `name`, `locale`, `timezone` e/ou país ISO alpha-2 |
| `GET` | `/today` | estado diário oficial, determinístico e versionado |
| `GET` | `/profile` | perfil corporal, rotina, objetivo e onboarding |
| `POST` | `/onboarding` | salva dados validados e retorna perfil + metas disponíveis |
| `GET` | `/plan` | plano de treino ativo e prescrições vigentes |
| `GET` | `/progress` | nível, streak, bloco 7700, peso, BF e reavaliação |
| `GET` | `/history` | histórico próprio; aceita `before` ISO e `limit` 1..100 |
| `POST` | `/registrations/propose` | calcula e cria pending de refeição ou treino |
| `POST` | `/registrations/:id/confirm` | grava deterministicamente o pending aprovado |
| `PATCH` | `/registrations/:id` | recalcula e edita um pending ainda aberto |
| `DELETE` | `/registrations/:id` | cancela um pending ainda aberto |
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
  "daily_balance_kcal": -1035,
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
  "calculation_version": "bodyflow.daily-state.v2",
  "updated_at": "2026-07-20T14:05:00.000Z",
  "generated_at": "2026-07-20T15:00:00.000Z"
}
```

Semântica obrigatória:

- `remaining_food_kcal = max(meta - consumido, 0)`. Exercício não aumenta esse
  valor; `food_excess_kcal` informa o excedente de ingestão separadamente.
- `daily_balance_kcal = consumido - meta - exercício`. Esse saldo é
  `provisional` durante o dia, `final` após fechamento válido e
  `insufficient_data` quando faltaram dados no fechamento.
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
- `snoozed_until` é obrigatório somente para `snoozed`, deve ser posterior a
  `occurred_at` e cair na mesma data local da ocorrência original;
- os presets de produto são 15, 30 e 60 minutos; horário customizado é aceito se
  cumprir a mesma restrição de data local;
- item, tipo, ownership, regra, weekday, hora local e round-trip DST do
  `scheduled_for` são revalidados no backend;
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
evento falso. A ação append-only mais recente, ordenada por `occurred_at`,
`created_at` e ID, determina o estado:

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
`missed`. Um finalizador backend persiste redundantemente um único log `missed`
idempotente para auditoria e operação; atraso desse worker não muda o estado
público derivado.

O paciente pode corrigir um `missed` automático para `taken` até sete dias após
o fim do dia da ocorrência. A correção cria outro log apontando para o `missed`;
nenhuma linha anterior é alterada ou excluída. O cliente não pode criar
`missed`.

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

## Mídia privada

O app nunca recebe `service_role` e não possui policy para listar, inserir,
alterar ou excluir diretamente em `storage.objects`. Todo acesso nasce no BFF,
depois da resolução do paciente autenticado. O catálogo `media_assets` é a fonte
canônica de ownership; `storage.objects.owner_id` não é usado como autorização.

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

## Ciclo do pending

1. `propose` calcula e cria um pending; um novo pending cancela o anterior do
   mesmo paciente conforme a regra já existente.
2. `PATCH :id` só funciona em `pending` não expirado e recalcula todo o payload.
3. `confirm` grava primeiro via ferramenta atômica e só então marca `confirmed`.
4. Retry após gravação parcial é deduplicado pelo request key salvo na proposta.
5. `DELETE :id` altera apenas um pending para `cancelled`; não apaga logs já
   confirmados.
6. Estado expirado, editado, cancelado ou concorrente produz erro explícito.

## Limites desta fase

- Não há chat nativo, envio APNs, StoreKit ou app iOS nesta entrega. Os backends de
  mídia, devices, regras e rotina ainda dependem de integração e QA no app nativo.
- `persona` persiste a escolha e seleciona mensagens futuras, mas o app nativo
  ainda precisa implementar a tela e consumir o contrato.
- O mascote é somente estado não visual; assets, animações e regras de evolução
  permanecem fora desta entrega.
- O CMS educativo não inclui tela iOS, campanhas automáticas, comentários,
  busca textual, HTML rico, mídia inline ou geração/publicação por IA.
- `entitlements` informa assinaturas existentes, mas declara StoreKit indisponível.
- Suplementos e medicamentos têm CRUD versionado, `dose_text` controlado pelo
  paciente, múltiplos horários e histórico de adesão. Orientação clínica,
  recomendação de dose e prescrição permanecem fora do escopo.
