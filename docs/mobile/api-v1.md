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
    "target_ml": null,
    "status": "tracked_without_target"
  },
  "supplements": { "availability": "not_implemented", "items": [] },
  "medications": { "availability": "not_implemented", "items": [] },
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
    "pending_actions": "pending_registrations_and_meal_pattern",
    "block_7700": "user_progress"
  },
  "calculation_version": "bodyflow.daily-state.v1",
  "updated_at": "2026-07-20T14:02:00.000Z",
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
  especulativo do dia aberto.
- `targets.source`, `consumed.source`, `block_7700.source` e `sources` identificam
  a origem operacional de cada seção.
- Propostas pendentes expõem somente ID, tipo, horário e `meal_type`; texto bruto,
  mídia, IDs de provider e evidências internas não saem do backend.
- Hidratação ainda não possui meta diária de domínio. Suplementos e medicamentos
  ainda não possuem módulo; a resposta declara isso em vez de inventar dados.

`calculation_version` versiona a semântica do agregador. Mudanças aditivas no DTO
podem manter a versão; mudança de fórmula ou significado incrementa a versão.
Quebra de estrutura exige uma nova versão HTTP. O app deve renderizar os números
do backend e usar a versão para telemetria, nunca reimplementar a fórmula.

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

- Não há chat nativo, upload mobile, APNs, StoreKit ou app iOS nesta entrega.
- `persona` não persiste seleção até o Prompt correspondente implementar o domínio.
- `content` não consulta frases educativas nem inventa um CMS sobre tabelas legadas.
- `entitlements` informa assinaturas existentes, mas declara StoreKit indisponível.
- Suplementos, medicamentos e meta quantitativa de hidratação permanecem
  explicitamente indisponíveis no estado diário até seus domínios existirem.
