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
cancelamento não precisam de JSON, mas continuam exigindo `Idempotency-Key`.
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
| `GET` | `/coach/persona` | estado do módulo; indisponível nesta fase |
| `PATCH` | `/coach/persona` | reservado para `focus`, `impulse` e `zen`; retorna `501` |
| `GET` | `/content` | lista vazia e estado indisponível nesta fase |
| `GET` | `/content/:id` | reservado; retorna `404` até o módulo existir |
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
| `POST` | `/routine/hydration` | soma água atomicamente ao dia local correto |
| `POST` | `/routine/supplements/:id/taken` | registra adesão de suplemento próprio e ativo |
| `POST` | `/routine/medications/:id/taken` | registra adesão de medicamento próprio e ativo |

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
        "id": "supplement-id",
        "name": "Creatina",
        "status": "taken",
        "occurred_at": "2026-07-20T14:05:00.000Z",
        "snoozed_until": null
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
  "calculation_version": "bodyflow.daily-state.v1",
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
- Suplementos e medicamentos mostram somente itens ativos do próprio paciente e
  a ação oficial mais recente do dia local: `taken`, `snoozed`, `skipped`,
  `missed` ou `not_recorded`. Ausência de item é `not_configured`; dose,
  prescrição e recomendação não são inferidas.
- Snapshot, refeições e treinos são lidos em uma única consulta relacional. O
  backend revalida a versão escalar do snapshot e também as fontes de meta de
  hidratação, itens de rotina e adesão diária. Se uma escrita concorrente alterar
  qualquer uma dessas fontes, a leitura é repetida uma vez; se continuar mudando,
  a API falha sem devolver dados de versões diferentes.

`calculation_version` versiona a semântica do agregador. Mudanças aditivas no DTO
podem manter a versão; mudança de fórmula ou significado incrementa a versão.
Quebra de estrutura exige uma nova versão HTTP. O app deve renderizar os números
do backend e usar a versão para telemetria, nunca reimplementar a fórmula.

## Devices, lembretes e rotina

O registro de device aceita somente iOS, `installation_id` opaco, ambiente APNs
`sandbox` ou `production` e token hexadecimal. O token é normalizado e permanece
em tabela backend-only; respostas, eventos e logs não incluem token nem hash. Uma
instalação desativada continua no histórico e deixa de receber novas entregas.

Preferências suportam opt-in global, início/fim de horário silencioso, limite de
0 a 20 pushes por dia e meta opcional de hidratação entre 250 e 10.000 ml. Início
e fim do horário silencioso devem ser ambos nulos ou ambos presentes. O timezone
canônico vem do perfil do paciente.

Regras aceitam `local_time` no formato `HH:MM`, dias únicos entre 0 (domingo) e 6
(sábado) e uma das categorias: `meal`, `hydration`, `supplement`, `medication`,
`workout`, `reevaluation`, `content` ou `reengagement`. Refeição exige
`meal_type`; suplemento e medicamento exigem item de rotina próprio, ativo e do
tipo correspondente. Os demais tipos rejeitam essas referências.

Hidratação exige `amount_ml` entre 1 e 5.000 e `occurred_at` explícito. A ação
`taken` também exige `occurred_at`. O servidor recusa instantes mais de cinco
minutos no futuro ou sete dias no passado e usa o timezone do paciente para o dia
local. Retry com a mesma `Idempotency-Key` não soma nem registra novamente.

O scheduler Inngest descobre regras vencidas com janela de cinco minutos e emite
`reminder.rule.due` contendo somente `reminderRuleId` e `scheduledFor`. O
Postgres faz o claim transacional e consulta preferências, dispositivo ativo,
horário silencioso, limite diário e estado oficial. Os resultados possíveis são
`queued`, `resolved` e `suppressed`, sempre auditáveis e idempotentes.

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
expiração automática, mas não faz parte do contrato de upload do paciente. Ele
fica reservado para o futuro CMS com RBAC próprio. SVG não é aceito.

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
- `persona` não persiste seleção até o Prompt correspondente implementar o domínio.
- `content` não consulta frases educativas nem inventa um CMS sobre tabelas legadas.
- `entitlements` informa assinaturas existentes, mas declara StoreKit indisponível.
- O catálogo mínimo de suplementos e medicamentos é somente leitura nesta fase.
  CRUD, dose, orientação clínica e prescrição permanecem fora do escopo.
