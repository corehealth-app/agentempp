# Performe AI — desenho integrado C1–C5 da beta funcional (v1.1)

- **Data:** 2026-09-27
- **Estado:** PROPOSTA PARA REVISÃO — nada de C1–C5 foi implementado; nenhuma migration, endpoint ou deploy aplicado.
- **v1.1 (2026-09-27, `FIX_FLOW_AUTHORIZATION_AND_MEAL_INTEGRITY_V1`):** S1, S2 e os achados A/C/D do editor foram corrigidos localmente (ver §0.2 e §6); emendas técnicas em §11. As emendas não autorizam M1, M2, M3 nem a dependência de PDF.
- **Base:** `codex/performe-ai-client-beta-flow-v1` @ `3e796f1560a0d6d01ae2129060a280bceb1fb55f`.
- **Autoridade revalidada** (blobs idênticos aos registrados): dossiê `b4c09e80…:docs/handoffs/2026-08-20-…` blob `d396bbd7…` (sha256 `f0dc6dcd…`), addendum 09-14 `ef97a7be`, spec 09-14 `edc15330`, spec 09-17 `427243d6`, spec 09-19 `09d76d65`, manifesto `9ca2587a`, scanner `7986173f`. Este documento não substitui essa cadeia; ele a complementa com o desenho das capacidades que ainda não existem.
- **Nomes:** Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada.
- **Handoff anterior preservado:** `roberto-beta/approval-package-cd.md` (scratchpad da sessão) não foi alterado.

**Legenda de cada afirmação**

| Marca | Significado |
|---|---|
| **[INSP]** | inspecionado no código/migrations nesta operação, com `arquivo:linha` |
| **[TEST]** | exercitado por teste automatizado ou experimento executado nesta operação |
| **[PROP]** | proposta deste documento — exige aprovação antes de implementar |
| **[DESC]** | ainda desconhecido; como descobrir está indicado |

**Decisões do usuário adotadas (não reabertas):** C1 texto/câmera/galeria/gravação/importação de áudio convergem para proposta revisável com confirmação e persistência reais, valores oficiais no backend; C2 notificações **locais** derivadas de horários oficiais, push remoto fora desta implementação; C3 arquivo original → extração no servidor → rascunho → revisão → confirmação; C4 Flow gera **rascunho**, ativação só por confirmação explícita autenticada, o LLM nunca confirma; C5 peso na fonte oficial existente, sem segundo ledger; conta QA dedicada (sem CI-3). Todo o resto neste documento é **recomendação**.

---

## 0. Pré-requisitos transversais de segurança (valem para C1–C5)

### 0.1 Mapa de camadas (situação atual)

| Camada | Situação | Evidência |
|---|---|---|
| Autenticação | Bearer → `supabase.auth.getUser(token)` (remoto, não JWKS); e-mail confirmado obrigatório; `bootstrap_patient_profile` roda com o JWT do próprio paciente; domínio `users.id` resolvido por `auth_user_id` único; `status='active'` obrigatório | [INSP] `apps/admin/src/lib/mobile-api/supabase-auth.ts:7-46`, `auth.ts:64-108`, migration `20260720020351…:141-216` |
| Autorização no BFF | Wrapper único: serviço → autenticação → entitlement (`bodyflow_full`, exceto `/me`, `/profile`, `/onboarding`, `/entitlements`, `/coach/persona`, `/devices`, `/notification-preferences`) → handler | [INSP] `route.ts:64-89`, `entitlement-service.ts:6-22,58-70` |
| Acesso ao banco | **Todo** serviço mobile usa a chave `service_role` (ignora RLS). O vínculo usuário↔recurso está nas queries do BFF (`.eq('user_id', auth.userId)`) e em `p_user_id` das RPCs, não na RLS | [INSP] `apps/admin/src/lib/supabase/server.ts:36-54`, `route.ts:72` |
| RLS/grants | Clientes (`authenticated`) só leem o próprio dado; sem escrita direta; `media_assets` esconde `object_path`/`processing_result`/`context_text`; buckets privados; nenhuma policy em `storage.objects` no repositório | [INSP] `20260720022441_p0_secure_app_first_rls.sql:9-223`, `20260720153510…:237-270`; policies remotas criadas fora de migrations: [DESC] |
| RPCs privilegiadas | Novas RPCs usam `SECURITY DEFINER` + `private.assert_trusted_backend()` + `p_user_id`. Exceções antigas `SECURITY INVOKER` sem guarda, protegidas só pelo ACL de EXECUTE (service_role): conteúdo, coach, `replace_pending_registration_atomic`, `save_training_plan_atomic` | [INSP] `20260720014221…:7-27`; `20260712001000…:26` |
| Idempotência | Ledger `mobile_api_idempotency` por `(user_id, idempotency_key)`, 24 h, hash do payload validado, 409 `idempotency_key_conflict`/`idempotency_request_in_progress`, aplicado a **todas** as mutações mobile (incluindo `POST /flow/chat`) | [INSP] `idempotency.ts:39-233`, migration `20260720130537…:1-229` |

Um `userId` no path nunca é prova de isolamento: em todos os recursos atuais o id do path é combinado com `auth.userId` [INSP]. A prova de isolamento continua sendo teste A/B.

### 0.2 Achados que precisam de correção antes (ou junto) do primeiro lote

| # | Achado | Evidência | Proposta |
|---|---|---|---|
| S1 | **A allowlist de ferramentas do Flow mobile só filtra os schemas mostrados ao modelo; a execução procura a ferramenta no registro completo.** Se o modelo emitir `gera_treino`/`gera_dieta` no canal mobile, ela executa e grava. Risco atual, não só pré-requisito de C4 | [INSP] `packages/agent/src/pipeline.ts:430-431` (filtra para schemas), `:735-736` (`getToolByName(tc.name)`); `tools.ts:3567-3569` (`ALL_TOOLS.find`) | [PROP] recusar na execução qualquer chamada fora de `filteredTools` e levar o canal no `ToolContext`; teste que prova que o canal mobile não executa `gera_*` mesmo se o modelo pedir. Corrigir antes de qualquer ferramenta nova no Flow. **v1.1: RESOLVIDO localmente** — `authorizeToolCall` antes de qualquer efeito, recusa sanitizada, retry de retratação no canal sem escrita (§11.0). Risco de implantação: no WhatsApp, `allowed_tools` não vazio passa a valer também na execução — exige leitura (somente leitura) da configuração de produção antes de qualquer deploy |
| S2 | `messages.provider_message_id` é único **globalmente** por provedor; o Flow mobile grava ali a `Idempotency-Key` do cliente → a mesma chave usada por dois usuários faz o segundo receber 500 | [INSP] `supabase/migrations/20260711201000_messages_provider_id_unique.sql:5-7`; `flow-chat-service.ts:118-125` (relatório de leitura) | [PROP] no canal `mobile_flow`, gravar `provider_message_id` com prefixo do usuário; sem migration; teste com dois usuários e a mesma chave. **v1.1: RESOLVIDO localmente** com formato `mobile_flow/<user_id>/<key>` e resposta `…/assistant` (`/` fica fora do charset da chave — o formato `<user_id>:<key>` do v1 colidiria); linhas legadas preservadas (§11.0) |
| S3 | Prompts dos geradores de treino/dieta se apresentam como "Dr. Roberto Menescal", o que contradiz a política do canal Flow | [INSP via leitura] `diet-generator.ts:181`, `training-plan-generator.ts:109`; política `pipeline.ts:138-153` [INSP] | [PROP] geradores recebem a persona do canal; o Flow mobile nunca usa a identidade de pessoa real (necessário em C4) |
| S4 | Não há teste de integração do BFF com dois usuários reais; os testes cross-user existentes são SQL (RLS/FK) ou unitários com mocks | relatório de segurança (`supabase/tests/*`, `apps/admin/src/lib/mobile-api/*.test.ts`) | [PROP] harness de integração do BFF contra Supabase local com usuários A/B, usado por todos os C abaixo |
| S5 | Históricos do WhatsApp carregam mensagens de todos os provedores, inclusive `mobile_flow` | [INSP via leitura] `pipeline.ts:2263-2270` | Registrar em C4: um rascunho mencionado no chat mobile pode aparecer no contexto do WhatsApp; o WhatsApp não ganha capacidade de confirmar rascunho |

---

## 1. C1 — Refeição por texto, câmera, galeria, gravação e importação de áudio

### 1.1 Código existente reaproveitado

- **Proposta → revisão → confirmação** [INSP]: `POST /registrations/propose` (`registration-service.ts:233-249`) calcula no servidor com `calcMealMacros` (sem LLM; ordem: nutrição aprovada, `user_kcal`, bebida zero, correção aprendida, histórico, composto, trigram `food_db`, mediana, estimativa por categoria — `packages/agent/src/meal-pipeline.ts:1421-2405`); `PATCH` reconstrói a proposta (`:251-286`); `confirm` regrava com a nutrição aprovada no pending (`:316-410`, `confirmed-meal.ts:40-72`). Valores oficiais já ficam no backend.
- **Texto estruturado** [INSP][TEST]: `TextMealDetector` (`apps/ios/BodyFlow/BodyFlow/Core/Registration/TextMealDetector.swift:7-91`) — ver §1.7.
- **Pipeline de mídia** [INSP]: `POST /media` (URL assinada de PUT, 2 h calculado localmente) → PUT no Storage → `POST /media/:id/complete` (confere tamanho/MIME reais) → `POST /media/:id/process` (202) → `GET /media/:id` (poll; `result` só quando `processed`); limites 15 MiB imagem / 25 MiB áudio; idempotência em todas as mutações; retenção meal/audio 30 dias com limpeza horária (`media-service.ts:92-309`, `supabase-media.ts:79-215`, `media-retention-cleanup.ts`).
- **O que cada worker devolve** [INSP] (`packages/inngest-functions/src/functions/media-asset-processing.ts:209-273`, `packages/providers/src/vision/gemini.ts:32-147`, `packages/providers/src/stt/groq.ts:11-63`):
  - `meal_photo` → `{ type:'meal', items:[{ name, quantity_g_estimate, confidence 0..1, notes? }], meal_context?, nutrition_label_visible, nutrition_label?, nutrition_label_error? }` — **sem kcal/macros por item**; porções repetidas vêm no nome ("2x ovo frito") com gramas totais; quantidade ilegível vira `0` com `confidence 0`; o prompt manda omitir itens < 0,40.
  - rótulo nutricional (quando visível) → `{ product_name, serving_size_g, per_serving{kcal,protein_g,carbs_g,fat_g}, per_100g{…}, confidence }`.
  - `audio_note` → `{ text, language?, duration?, latencyMs }` — **só transcrição**; nada no caminho mobile transforma transcrição em alimentos.
  - O limiar `vision.meal.confidence_threshold` (padrão 0,6) existe mas **não é aplicado** no caminho mobile (`runtime-config.ts:117-121`).
- **WhatsApp (referência, não reaproveitado diretamente)** [INSP]: quem identifica alimentos e quantidades é o LLM principal via tool calling (`registra_refeicao`, `tools.ts:563-611`); a descrição da ferramenta manda **estimar** quantidade ausente (`tools.ts:578,583,609`). Esse comportamento não serve ao mobile porque inventaria gramas.

### 1.2 Lacunas reais

1. [INSP] Nenhum vínculo entre `media_assets` e `pending_registrations`; `propose` é `.strict()` e não aceita origem nem `media_id`; o DTO pendente descarta `nutrition_source`, `user_kcal`, `display_*` e `sourceContentType` (`contracts.ts:129-159`, `read-model.ts:39-99`).
2. [INSP] Não existe extração de alimentos a partir de texto livre ou transcrição no caminho mobile.
3. [INSP] Nenhum código iOS de câmera, PHPicker, gravação, importação de áudio ou upload; `Info.plist` sem `NSCameraUsageDescription`/`NSMicrophoneUsageDescription`.
4. [INSP] Sem limite de duração de áudio em lugar nenhum (só 25 MiB).
5. [INSP] O editor de proposta edita só o primeiro item e **envia só ele**, apagando os demais itens da proposta ao salvar (achado C, §6).

### 1.3 Desenho recomendado [PROP]

**Fluxo único para as cinco origens**

```
texto / câmera / galeria / gravação / importação
        │
        ▼
(mídia) POST /media → PUT Storage → complete → process → GET até processed
        │
        ▼
POST /meal-drafts  ──►  candidatos (sem nutrição; quantidade com base explícita)
        │                     │
        │          paciente revisa: confirma/edita gramas, remove, adiciona
        ▼
POST /registrations/propose (existente, + source)  ──►  servidor calcula  ──►  revisão da proposta (existente)
        ▼
POST /registrations/:id/confirm (existente)  ──►  meal_logs
```

**Novo endpoint `POST /api/mobile/v1/meal-drafts`** (idempotente, exige entitlement, **sem tabela nova**: a resposta fica no ledger de idempotência por 24 h)

```jsonc
// entrada (strict)
{ "source": "text", "text": "2 ovos mexidos e 1 pão francês" }
{ "source": "media", "media_asset_id": "<uuid>" }

// saída
{
  "source": "text" | "photo" | "audio",
  "media_asset_id": "<uuid>" | null,
  "transcript": "…" | null,            // só áudio: o que foi ouvido, para o paciente conferir
  "context_note": "…" | null,          // meal_context do Vision
  "items": [{
    "name": "ovo mexido",
    "quantity_g": 100 | null,
    "quantity_basis": "stated" | "visual_estimate" | "portion_reference" | "missing",
    "count": 2 | null, "unit_label": "unidade" | null,
    "confidence": 0.82 | null,
    "needs_review": true,
    "review_reason": "low_confidence" | "estimated_quantity" | "missing_quantity" | "ambiguous" | null
  }],
  "nutrition_label": { "product_name": "…", "serving_size_g": 30, "per_serving": {…}, "per_100g": {…}, "confidence": 0.9 } | null,
  "extraction": { "method": "deterministic" | "vision" | "llm_text", "model": "…" | null }
}
```

- **Quem identifica alimentos e quantidades:**
  - Foto: o Vision já identifica; o servidor só **mapeia** `items` → candidatos (sem segunda chamada de LLM): `quantity_g_estimate > 0` → `visual_estimate`; `0` → `missing`; `confidence` abaixo do limiar configurado → `needs_review: low_confidence`; prefixo "2x" vira `count` apenas para exibição (as gramas continuam as do Vision).
  - Texto livre e transcrição: passo 1 determinístico ("alimento + gramas", mesmas regras do cliente); passo 2 só para linhas não reconhecidas: LLM de extração **sem ferramentas**, `temperature 0`, conteúdo do paciente entre tags de dado, schema JSON estrito `{name, count?, unit?, grams_stated?}` e regra "nunca produzir gramas que não foram ditas".
  - Porção de referência: `count + unit` só vira gramas por regra **determinística do servidor**. A fonte são as regras de peso unitário já embutidas em `naturalUnit` para exibição — ovo ≈ 50 g, pão de queijo ≈ 30 g, fatia ≈ 15 g (`meal-pipeline.ts:359-431`) [INSP] — extraídas para `portionReferenceGrams(food, unit)` com os mesmos números, sem acrescentar valores. Sem regra → `missing`.
- **Exemplo "2 ovos"** (hoje o parser do app recusa, [TEST] `TextMealDetectorTests.swift:16-30`): o passo 2 devolve `{ name:"ovo", count:2, unit:"unidade" }`; a regra existente do ovo (≈ 50 g) dá `quantity_g: 100`, `portion_reference`, `needs_review: true`, exibido como "2 ovos ≈ 100 g (porção de referência — confirme)". Para um alimento sem regra (ex.: "1 prato de feijoada"), `quantity_g: null`, `missing`, e o app **exige** que o paciente informe as gramas antes de propor. Nenhum valor é inventado nos dois casos.
- **Ambiguidade vira revisão, não número:** itens `needs_review` aparecem marcados; itens `missing` bloqueiam o envio até o paciente preencher; `context_note` e a transcrição ficam visíveis.
- **Rótulo nutricional:** o cliente nunca envia macros. Quando a proposta referencia `media_asset_id`, o **servidor** lê `processing_result.nutrition_label` e aplica o caminho existente `attachTrustedVisionNutrition` (`packages/agent/src/trusted-vision-nutrition.ts:72-103`) [INSP].
- **Origem da mídia na proposta:** `propose`/`PATCH` ganham `source` opcional (retrocompatível):
  `{ "channel": "text"|"camera"|"gallery"|"audio_recording"|"audio_import", "media_asset_id": "<uuid>"? }`.
  O servidor valida dono (`findOwned(userId, assetId)`), `kind` compatível e `status='processed'`; grava no jsonb do pending (`sourceContentType = channel`, `source_media_asset_id`). O DTO pendente passa a expor `source` e, por item, `user_kcal` e `nutrition_source` (fecha a lacuna do achado A, §6).
- **Validação/recálculo antes de confirmar:** inalterado — `propose` recalcula tudo no servidor; `confirm` regrava exatamente a nutrição aprovada.

**iOS** [PROP] (paths reais do projeto)

| Componente | Path |
|---|---|
| DTOs de mídia (`MediaAssetSnapshot`, `MediaUploadTicket` com descrição redigida, `MediaProcessingResult` meal/audio/unknown) | `BodyFlow/Core/Media/MediaModels.swift` |
| `/media` sobre o transporte existente (`executeCapability`) | `BodyFlow/Core/Networking/MobileMediaRepository.swift` |
| Transporte de upload separado | `BodyFlow/Core/Networking/StorageUploadTransport.swift` |
| Arquivos temporários | `BodyFlow/Core/Media/MediaStagingStore.swift` |
| `/meal-drafts` | `BodyFlow/Core/Networking/MobileMealDraftRepository.swift` |
| Captura: câmera, PHPicker, gravador, importador de áudio | `BodyFlow/Features/Register/Media/*` |
| Revisão de candidatos | `BodyFlow/Features/Register/MealDraftReviewView.swift` |
| Fases novas no modelo (`uploading → processing → candidates → proposing`) | `BodyFlow/Features/Register/MealRegistrationModel.swift` |

- **Upload:** `URLSession` própria, sem cookies/cache/credenciais; aceita só `https`, host igual ao do `PERFORME_SUPABASE_URL` já configurado no Release e path `/storage/v1/object/upload/sign/…`; envia **somente** os headers que o servidor devolveu (`Content-Type`, `x-upsert`) — **nunca** o bearer do BFF; recusa redirects; `description` redigida; URL assinada e token nunca em log.
- **Galeria:** `PHPickerViewController` (fora do processo, **sem** permissão de biblioteca), filtro imagens, seleção única. Nenhum `NSPhotoLibraryUsageDescription`.
- **Câmera:** `NSCameraUsageDescription` (pt-BR/en em `InfoPlist.xcstrings`), pedido no primeiro uso.
- **Imagem:** reduzir o maior lado para 2048 px, JPEG 0,8, **remover metadados** (EXIF/GPS) na recodificação; HEIC da câmera convertido.
- **Gravação:** `NSMicrophoneUsageDescription`; AAC `.m4a` mono; limite de **180 s** no cliente com contagem visível; interrupção (ligação) encerra e oferece descartar/usar.
- **Importação de áudio:** `UIDocumentPickerViewController` só com os tipos aceitos pelo servidor (m4a/mp4, mp3, wav, aac, ogg); duração ≤ 180 s verificada antes do upload; ≤ 25 MiB.
- **Temporários:** `tmp/performe-media/<uuid>` com proteção `complete`; apagados após `complete`, cancelamento ou falha; varredura no launch e no logout (encadeada ao `SensitiveStateClearing` já existente).
- **Retry:** repetir `POST /media` com a **mesma** chave (o servidor re-assina a URL no replay [INSP] `media/route.ts:23-26`); PUT até 3 vezes com backoff dentro de `expires_at`; `complete`/`process` com chave própria; poll 1-2-3-5 s até 90 s, depois estado "ainda processando" com atualizar manual.
- **Cancelamento:** cancela a tarefa de rede; se o ativo já existe, `DELETE /media/:id` (idempotente); apaga o temporário; nada é proposto.
- **Servidor [PROP]:** checar `duration` da transcrição e falhar com `audio_too_long` acima de 300 s (presença de `duration` no retorno do Groq: [DESC], verificar no primeiro teste pago).

### 1.4 Contratos e dados

- Novo: `POST /meal-drafts`.
- Estendidos: `propose`/`PATCH` com `source`; DTO pendente com `source`, `user_kcal`, `nutrition_source`.
- **Nenhuma migration** (a proposta é jsonb; o ledger de idempotência guarda o rascunho de candidatos).
- Mirror de rotas do `apps/mobile-bff` precisa do novo arquivo e da atualização do contador verificado [INSP via leitura] `apps/mobile-bff/scripts/verify-route-mirror.mjs:6-7`.

### 1.5 Segurança

Autenticação/entitlement existentes; `meal-drafts` e `propose` com `media_asset_id` passam por `findOwned` (404 sem revelar existência); `processing_result` é lido só no servidor; o cliente nunca manda macros; transcrição e `context_note` voltam só ao dono. Testes A/B: B usa `media_asset_id` de A em `meal-drafts` e em `propose` → 404; B nunca vê o rascunho de A (ledger é por usuário [INSP]).

### 1.6 Testes e critério de conclusão

- **Unit iOS:** mapeamento de candidatos; transporte de upload (host fora da allowlist recusado, sem `Authorization`, redirect recusado, descrição redigida); limpeza de temporários; limites de duração; estados do modelo.
- **BFF:** `meal-drafts` (foto, áudio, texto; `missing` nunca recebe gramas; "2 ovos" com e sem referência); `source` validado; DTO pendente com os campos novos; harness A/B (S4).
- **E2E staging:** foto, galeria, gravação e importação com mídia sintética criada para QA, até `meal_logs`, com custo registrado.
- **Device físico (obrigatório, Simulator não cobre):** câmera e microfone concedidos/negados, gravação com interrupção, upload com troca de rede, metadados GPS ausentes no arquivo enviado.
- **Pronto quando** as cinco origens chegam a um `meal_logs` confirmado na conta QA, sem valor inventado, com origem registrada, e o A/B passa.

### 1.7 `TextMealDetector` — o que ele é (e o que não é)

**Não é compreensão de linguagem natural.** É um parser determinístico [INSP] `TextMealDetector.swift:34-78`:

- quebra por nova linha ou `;`, descarta vazias, 1…30 linhas;
- cada linha **precisa** de número + unidade de grama (`g`, `gr`, `grs`, `grama`, `gramas`, `gram`, `grams`, sem diferenciar maiúsculas), decimal com `,` ou `.`, quantidade `> 0` e `≤ 9999`;
- nome = linha sem o trecho número+unidade, sem `-–:,.;` nas pontas, sem "de "/"of " inicial, 1…160 caracteres;
- **uma linha inválida rejeita a mensagem inteira** (`try lines.map(item(from:))`);
- `userKcal` sempre `nil`; o tipo de refeição é só sugestão pelo horário.

Exemplos exercitados por teste [TEST] (`TextMealDetectorTests.swift:8-30`): aceitos `"Arroz integral 120 g"`, `"Frango grelhado 150g"`, `"10,5 g de azeite"`; recusados `"2 ovos"`, `"arroz 12000 g"`, `"   "`, `"120 g"`.

Ele continua como **caminho estruturado offline** (sem custo). Descrições livres ("2 ovos e um pão") não passam por ele: vão para `POST /meal-drafts` (§1.3). Resultados de Vision/STT também não passam por ele.

---

## 2. C2 — Lembretes locais no iPhone

### 2.1 Existente

- **Suplementos/medicamentos — horário oficial** [INSP]: `GET /supplements|/medications` devolve `schedules[{ id (= reminder_rule_id), local_time "HH:MM", weekdays 0..6 (0 = domingo), occurrence{ scheduled_for, status, snoozed_until } }]`, `reminders_enabled`, `active`, `archived_at` (`RoutineModels.swift:22-88`; RPC `list_mobile_routine_items`, `20260722191125…:917-1072`).
- **Demais tipos — só regras criadas pelo paciente** [INSP]: `GET/POST/PATCH /reminders` com categorias `meal` (exige `meal_type`), `hydration`, `workout`, `reevaluation`, `content`, `reengagement`; `supplement`/`medication` recusadas com 409 (usam o contrato do item) (`contracts.ts:254-313`, `routine-service.ts:156-178`).
- **Preferências** [INSP]: `GET /notification-preferences` → `quiet_hours {start,end}` (início inclusivo, fim exclusivo, pode cruzar meia-noite), `daily_push_limit` (padrão 8), `routine_preview_mode` `private|name|name_and_dose` (padrão `private`) (`routine-service.ts:126-154`; `docs/mobile/api-v1.md:928-948`).
- **Fuso** [INSP]: `/me.timezone` resolvido por sessão no `PatientTimeZoneStore` (commit `80b5dcca`).
- **Derivação oficial de ocorrência** [INSP]: `(data local + hora) AT TIME ZONE tz` só se o dia da semana bate; horário inexistente no salto de DST é descartado por ida-e-volta (`20260720201007…:40-99`).
- **Push remoto não envia nada** [INSP]: `providerSendAllowed: false` (`reminder-scheduler.ts:77,196`).
- **iOS** [INSP]: nenhum uso de `UserNotifications`, sem entitlements, sem AppDelegate.

### 2.2 Lacunas

| Tipo exigido | Horário oficial? | Tratamento no desenho |
|---|---|---|
| Suplemento, medicamento | Sim | agenda a partir de `schedules` |
| Refeição, hidratação, treino | Não — só regras do paciente | o app oferece criar a regra via `POST /reminders` (contrato existente) e agenda a partir de `GET /reminders`; **nenhum horário é inventado** (wake/bedtime existem no perfil mas nada deriva lembrete deles [INSP]) |
| Pesagem | Não existe categoria | reutilizar `reevaluation` + `user_progress.next_reevaluation` (existentes): lembrete local na data da reavaliação, no horário da regra `reevaluation` do paciente; sem migration |
| Hidratação | Meta existe, horários não | só regras do paciente; corpo da notificação sem valores |

### 2.3 Desenho [PROP]

- **`BodyFlow/Core/Reminders/LocalReminderPlanner.swift` (puro, testável):** entradas = itens da rotina, regras de `/reminders`, preferências, fuso documentado, agora; saída = ocorrências **individuais não repetidas** com instante absoluto. Regras:
  - pula item inativo, arquivado ou com `reminders_enabled = false`;
  - pula ocorrência de hoje já `taken`/`skipped`; `snoozed` → uma notificação em `snoozed_until`;
  - horário inexistente no DST → descartado (mesma ida-e-volta do servidor);
  - aplica `quiet_hours` e `daily_push_limit` por dia local, prioridade medicamento > suplemento > refeição > hidratação > treino > reavaliação;
  - orçamento de **60** pendentes (limite do iOS é 64) preenchido em ordem de tempo → horizonte variável; no fim do horizonte, uma notificação "Abra o Performe AI para continuar recebendo lembretes".
- **`LocalNotificationScheduler.swift`:** protocolo sobre `UNUserNotificationCenter`; diff por identificador `pai.<hash8 do userId>.<categoria>.<ruleId>.<epochMinuto>`; gatilho `UNCalendarNotificationTrigger` com `DateComponents` completos **no fuso do paciente**; sem ações no lock screen nesta beta (tocar abre o detalhe via `userInfo`).
- **Sincronização:** no início da sessão autenticada, ao voltar ao primeiro plano, após mutações de rotina/lembrete (`FeatureInvalidationCenter`), após resolver `/me`. **Sem background** nesta beta; copy honesta: os lembretes refletem a última sincronização do app.
- **Permissão:** pedida só quando o paciente ativa lembretes; negada → estado explícito com atalho para Ajustes; sem `provisional`, sem time-sensitive, sem alertas críticos.
- **Privacidade no lock screen:** respeita `routine_preview_mode` — `private`: "Lembrete da rotina" / "Toque para ver o que está programado"; `name`: nome digitado pelo paciente; `name_and_dose`: nome + dose digitados. Medicamento sempre neutro, nunca persona. Refeição/hidratação/treino sem números de saúde. Título ≤ 60, corpo ≤ 180, palavras bloqueadas da regra existente (`packages/core/src/coach-messages.ts:84-97`) viram teste da copy.
- **Logout e troca de usuário:** remove pendentes e entregues com o prefixo do usuário, no mesmo encadeamento do `SensitiveStateClearing`.
- **Fuso:** sem fuso documentado, não agenda e mostra "Fuso não definido". Mudança do fuso do aparelho não altera os instantes; mudança em `/me` ressincroniza.
- **Não é mock:** notificações reais; o protocolo só existe para teste.
- **Não prometido:** atualização remota sem abrir o app, alerta infalível, entrega em modo Foco, crítico.

### 2.4 Contratos/dados

Nenhum endpoint novo, nenhuma migration. Usa `/supplements`, `/medications`, `/reminders` (GET/POST/PATCH), `/notification-preferences`, `/me`, `/progress`.

### 2.5 Testes e conclusão

- **Unit:** planner com `America/New_York` (salto e repetição de DST; `America/Sao_Paulo` não tem DST desde 2019), quiet hours cruzando meia-noite, limite diário, orçamento 60 e prioridade, filtros de status, identificadores por usuário, limpeza no logout (scheduler falso).
- **UI:** permissão negada e ativação.
- **Device físico:** entrega real, conteúdo por modo de privacidade no lock screen, persistência após reinício, mudança de horário/fuso.
- **Pronto quando** as seis categorias com horário (oficial ou do paciente) geram notificações reais corretas no aparelho e somem no logout.

---

## 3. C3 + C4 — Rascunho → revisão → confirmação de planos (importados e gerados pelo Flow)

### 3.1 Existente

- `training_plans` [INSP]: **um plano ativo por usuário** (índice único parcial) e idempotência por `source_request_key` (`20260712001000…:1-10`); sem `status`, origem só em `generated_by` (texto livre, padrão `'agent'`).
- `prescriptions` [INSP]: sem `active`/`status`, sem idempotência, várias linhas por usuário (`20260611230000…:9-23`).
- `save_training_plan_atomic` [INSP]: `SECURITY INVOKER`, só `service_role` executa, lock consultivo, idempotente por chave, **desativa o plano ativo** e liga `users.metadata.training_reminders` (entrega diária pelo WhatsApp) (`20260712001000…:12-103`).
- `saveDietPlan`: insert direto, sem idempotência (relatório; `diet-generator.ts:407-431`).
- `gera_treino`/`gera_dieta` **gravam na hora**, sem rascunho (relatório; `tools.ts:3194-3542`).
- `pending_registrations` **não serve**: a RPC de substituição cancela **todas** as pendências do usuário (`20260712205000…:62-67` [INSP]) e o código mobile rejeita tipos além de refeição/treino.
- `GET /plan` [INSP via leitura]: plano de treino ativo + até 10 prescrições válidas; o iOS não decodifica `weekly_schedule`.
- `POST /flow/chat` [INSP via leitura]: exige `Idempotency-Key`; resposta só texto; id da mensagem pode ancorar proposta (precedente `pending_registrations.proposal_msg_id`).
- Extração de documento: **não existe** PDF nem OCR de documento em nenhum pacote; nenhum bucket aceita `application/pdf` (relatório).

### 3.2 Desenho compartilhado [PROP]

**Tabela `plan_drafts`** (migration proposta)

| Coluna | Tipo/regra |
|---|---|
| `id` | uuid PK |
| `user_id` | uuid FK `users`, not null |
| `domain` | `training` \| `nutrition` |
| `origin` | `flow_generated` \| `imported_photo` \| `imported_pdf` |
| `status` | `extracting` \| `generating` \| `ready_for_review` \| `confirmed` \| `discarded` \| `expired` \| `failed` |
| `source_media_asset_id` | uuid null (importação) |
| `source_message_id` | uuid null FK `messages` (Flow) |
| `payload` | jsonb — no schema do domínio (`TrainingDay[]` ou `DietPlan`) |
| `payload_version` | int, incrementa a cada edição |
| `uncertain_fields` | jsonb — ponteiros JSON + motivo |
| `unrecognized_segments` | jsonb — trechos do original não mapeados, **verbatim** |
| `base_active_plan_id` | uuid null — plano ativo quando o rascunho nasceu (detecta conflito) |
| `origin_detail` | jsonb — método, modelo e versão do prompt (nunca texto integral do documento) |
| `request_key` | text; único por `(user_id, request_key)` |
| `created_at`, `expires_at` (30 dias), `resolved_at`, `confirmed_plan_id` | |

RLS ligada, leitura só do próprio paciente, sem escrita por cliente; escrita só por RPCs `SECURITY DEFINER` + `assert_trusted_backend()` + `p_user_id`: `create_plan_draft_atomic`, `update_plan_draft_atomic`, `confirm_plan_draft_atomic`, `discard_plan_draft_atomic`.

**Validação determinística:** o payload passa pelos schemas existentes (`TrainingDay`: dia, foco, duração 10–180, 1–20 exercícios com séries 1–15, descanso 0–600… — `training-plan-generator.ts:24-48`; `DietPlan` — `diet-generator.ts:68-114,169-179`). Valor fora de faixa ou ausente fica **nulo + incerto**, nunca ajustado; campos obrigatórios ausentes bloqueiam a confirmação até o paciente preencher ou remover o item.

**Confirmação** — `POST /plan-drafts/:id/confirm` com `{ payload_version }` + `Idempotency-Key`, chamando `confirm_plan_draft_atomic`:
1. trava o rascunho `WHERE id AND user_id` (`FOR UPDATE`);
2. exige `ready_for_review`, não expirado e `payload_version` igual à revisada (senão 409 `draft_changed`);
3. treino: exige plano ativo atual = `base_active_plan_id` (senão 409 `plan_changed_during_review`); desativa + insere na mesma transação com `generated_by = 'flow_draft' | 'patient_import'` e `source_request_key = 'plan-draft:<id>'`; **não** liga `training_reminders` (evita que um plano confirmado no app dispare entrega pelo WhatsApp) — divergência intencional da RPC atual, documentada;
4. nutrição: insere em `prescriptions`, não mexe nas anteriores;
5. marca `confirmed` + `confirmed_plan_id`; replay devolve o mesmo plano.

**Plano prescrito:** hoje não existe proveniência profissional (`generated_by` só `'agent'`). Proposta: o app sempre mostra "substituir o plano atual" e exige confirmação explícita; `generated_by = 'professional'` fica reservado, e a RPC recusa substituí-lo (409 `prescribed_plan_protected`). Nenhum plano atual tem esse valor.

**Copy obrigatória:** "Você confirmou este plano. Ele não foi revisado por um profissional." — a confirmação nunca é apresentada como revisão clínica.

**Medicamentos e doses:** nenhum rascunho cria ou altera medicamento, suplemento ou dose; trechos assim ficam em `unrecognized_segments` com o aviso "Medicamentos não são importados; converse com seu profissional" (coerente com a spec de rotina, `docs/superpowers/specs/2026-07-22-bodyflow-supplements-medications-routine-design.md:10-12,62,324-326`).

**Endpoints** [PROP]: `GET /plan-drafts?status=ready_for_review`, `GET /plan-drafts/:id`, `PATCH /plan-drafts/:id` (edição do paciente → nova `payload_version`), `POST /plan-drafts/:id/confirm`, `DELETE /plan-drafts/:id`.

### 3.3 C4 — geração pelo Flow

- Pré-requisitos S1 (allowlist na execução) e S3 (persona) resolvidos.
- Ferramentas novas **só de proposta**: `propoe_plano_treino`, `propoe_plano_dieta`. Reutilizam os geradores existentes (mesmas validações e limites: treino 1/24 h, dieta 2/2 h) com persona Flow, e gravam **somente** via `create_plan_draft_atomic` (`origin='flow_generated'`, `source_message_id`). Nunca chamam `saveTrainingPlan`/`saveDietPlan`.
- Allowlist mobile = as 4 de leitura + essas 2. `gera_*` **nunca** entram. WhatsApp permanece como está.
- Idempotência da proposta: a chave do turno do chat já é obrigatória [INSP] → `request_key = '<chave-do-chat>:<ferramenta>'`; replay não duplica rascunho.
- Resposta do `/flow/chat` ganha `draft: { id, domain }` opcional; o app mostra "Revisar proposta" e abre a revisão.
- **O LLM não confirma:** não existe ferramenta de confirmação; confirmar é só `POST /plan-drafts/:id/confirm` pela interface do app, com o bearer do paciente e chave própria.

### 3.4 C3 — importação de foto/PDF

- Mídia: novo `kind` `plan_document`, bucket privado `plan-documents` (20 MiB, PDF + imagens), retenção 90 dias — **migration de `media_assets`/buckets**.
- Worker: ramo `plan_document` no `media-asset-processing` — PDF com camada de texto → texto por **biblioteca de PDF no servidor (dependência nova, aprovação)**; imagem → Vision com prompt novo de transcrição (sem interpretar); depois LLM de estruturação **sem ferramentas**, com o documento entre tags de dado e schema estrito (payload + `uncertain_fields` + `unrecognized_segments`) → `create_plan_draft_atomic(origin='imported_*', source_media_asset_id)`.
- PDF escaneado (sem texto): nesta beta o app pede fotos das páginas (rasterizar PDF exigiria outra dependência pesada).
- Injeção de instruções: nada do documento é executado; o modelo de extração não tem ferramentas; instrução embutida no documento aparece no máximo como texto não reconhecido.
- Endpoint: `POST /plan-imports { media_asset_id, domain: training|nutrition|auto }` → 202 `{ draft_id }` → poll em `GET /plan-drafts/:id`.

### 3.5 iOS [PROP]

`Core/Plan/PlanDraftModels.swift`, `Core/Networking/MobilePlanDraftRepository.swift`, `Features/Plan/PlanDraftReviewView.swift` (compartilhada, seções por domínio, marcadores de incerto, trechos não reconhecidos, confirmar/descartar, conflito), `Features/Plan/PlanImportSourceView.swift` (PHPicker + seletor de PDF), cartão "Revisar proposta" no Flow, e `PlanSnapshot` decodificando `weekly_schedule`.

### 3.6 Segurança e testes

- A/B: B não lê, edita, confirma nem descarta rascunho de A (404); B não importa com mídia de A (404).
- Confirmação: repetida pelo mesmo usuário → idempotente; `payload_version` antigo → 409; plano mudou durante a revisão → 409.
- Agente: prova de que as ferramentas de proposta nunca gravam `training_plans`/`prescriptions` e de que `gera_*` não executa no canal mobile.
- E2E staging com documento sintético de QA; device: seletor de PDF e fotos.
- **Pronto quando** um plano gerado e um importado chegam a ativo só depois da confirmação do paciente, com origem preservada e sem valores inventados.

---

## 4. C5 — Registro de peso pelo app

### 4.1 Existente

- **Fonte oficial = `user_profiles.weight_kg numeric(5,2)`**, um valor corrente por usuário, sem histórico [INSP] (`20260501120100_users_core.sql:37`). Alimenta metas (TMB → meta, `docs/CALCULO-MPP.md:12-18`) e o cálculo de kcal de treino.
- WhatsApp atualiza via `cadastra_dados_iniciais` (upsert, 30–300 kg, sem idempotência, sem data local) (relatório; `tools.ts:66-263`).
- `user_progress.current_weight` e `reevaluations` existem e **nada grava neles** (relatório).
- Metas: a linha do dia no `daily_snapshots` mantém a meta já gravada; o `daily-closer` recalcula a meta do dia fechado com o perfil vivo (relatório; `daily-closer.ts:224,247-266`) — comportamento existente, idêntico para qualquer canal.
- iOS: `WeightCommand` 30…300 kg existe só no demo; linha oculta em conta real (commit `80b5dcca`).

### 4.2 Desenho [PROP]

- **Sem segundo ledger.** Escreve na mesma fonte do WhatsApp.
- Migration mínima: `user_profiles.weight_measured_at timestamptz null` (análogo ao `body_fat_measured_at` já existente) para "mais recente vence".
- RPC `record_weight_atomic(p_user_id, p_weight_kg, p_measured_at, p_idempotency_key)`, `SECURITY DEFINER` + `assert_trusted_backend()`, no molde de `record_hydration_atomic`:
  - valida 30–300 kg e arredonda para 2 casas;
  - aceita `measured_at` de até 7 dias atrás a 5 min no futuro;
  - travamento por usuário;
  - ~~se `p_measured_at < weight_measured_at` → não aplica~~ — **substituído na v1.1 (§11.4)**: aplica só se estritamente mais recente; mesmo instante e mesmo valor = replay sem efeito; mesmo instante e valor diferente = conflito.
- Endpoint `POST /api/mobile/v1/weight` — `{ value, unit: 'kg'|'lb', measured_at }`; conversão de libra no servidor (×0,45359237); resposta com `weight_kg`, `measured_at`, `applied`. Idempotência pelo ledger existente; o replay após 24 h segue a regra de empate da §11.4.
- **Snapshots/bloco:** nada é escrito em `daily_snapshots`, `user_progress` ou no bloco; metas e fechamento seguem os jobs existentes (`CLAUDE.md`: recálculo só pelo closer). Efeito idêntico ao WhatsApp.
- Progresso: mostra "último peso + data" lido de `GET /profile` (não grava `user_progress.current_weight`; tocar `user_progress` exigiria autorização nomeada). Sem tendência (proibida no iOS pelo plano de 29/07).
- iOS: o mesmo parser por idioma do editor de refeição (`MealProposalNumberParser`, §6), unidade explícita.
- Lembrete de pesagem: via C2 (`reevaluation`).

### 4.3 Testes e conclusão

Faixa e arredondamento, `lb`, vírgula, instante antigo não aplica, replay, A/B, `/today` do dia seguinte com a meta recalculada pelo carregador existente, `daily-closer` sem alteração. **Pronto quando** o peso registrado no app aparece no perfil e nas metas do dia seguinte exatamente como pelo WhatsApp.

---

## 5. Contas QA dedicadas [PROP — nenhuma criada]

| Conta | Uso |
|---|---|
| `QA_A` | E2E principal (onboarding concluído, entitlement sandbox com expiração) |
| `QA_B` | adversária de isolamento: tenta acessar ids de A em todos os endpoints |
| `QA_C` | nova, sem onboarding (fluxos de onboarding/consentimento) |

- Criadas **só** no branch de staging, com dados sintéticos e aceites do conjunto `qa-e2e-v1` (que **não** são aprovação jurídica).
- Senhas em arquivos locais `0600`, nunca no repositório, log ou chat; digitação no Simulator pelo usuário.
- Encerramento: revogar entitlement, apagar mídia, desativar contas no fim da beta.
- A identidade CI-3 não é reutilizada.

---

## 6. Achados do editor de refeição

### A — `user_kcal` (CORRIGIDO; item 4 concluído na v1.1)

- **Contrato lido** [INSP]: entrada `user_kcal: z.number().nonnegative().max(20_000).optional()` — ausente = servidor calcula; **`null` é recusado** (`.optional()` sem `.nullable()`); presente = kcal informado pelo paciente, sobrepõe o cálculo e reescala P/C/F (`source: 'user_kcal'`), salvo densidade impossível (`contracts.ts:129-135`; `meal-pipeline.ts:1501-1590`). O pending guarda `user_kcal` e `nutrition_source`, mas o DTO mobile os **descarta** (`read-model.ts:39-54`).
- **Defeito reproduzido por teste** [TEST]: o editor semeava o campo com o kcal do servidor e reenviava como `user_kcal` ao salvar sem mexer (gravaria "informado pelo paciente"); além disso `Decimal(string:)` lia "180,5" como 180 e "   " como 0 ([TEST] experimento e RED).
- **Correção:** valor do servidor somente leitura e separado; campo de substituição opcional e vazio; `user_kcal` omitido (nunca `null`) quando vazio; entrada ambígua ou fora de faixa bloqueia o salvar.
- **v1.1:** o DTO pendente passou a expor `user_kcal` e `nutrition_source` (aditivo, sem migration); o editor preserva um valor que o servidor aplicou, só volta ao cálculo pela ação explícita "Usar cálculo do servidor" e bloqueia a edição quando a resposta não traz a proveniência. **Texto original da lacuna (histórico):** como o DTO não expõe `user_kcal`/`nutrition_source`, o cliente não reconhece um valor manual anterior. Ao reeditar a mesma proposta, o campo abre vazio e salvar sem redigitar volta ao cálculo oficial — comportamento explícito na copy ("Deixe em branco para o servidor calcular"). Correção definitiva = expor os dois campos no DTO pendente (§1.3) e semear o campo a partir de `user_kcal`.

### C — edição apaga os demais itens [CORRIGIDO na v1.1]

`MealProposalEditorSeed` usa `proposal.items.first` e `saveProposal` envia só esse item; o `PATCH` reconstrói a proposta inteira com o que recebe (`registration-service.ts:251-286`). Com o detector de texto real (várias linhas), editar e salvar **remove** os itens 2…n. A copy "Somente o primeiro item pode ser corrigido nesta versão" não avisa a perda. Teste proposto: proposta com 3 itens → editar o primeiro → corpo do `PATCH` contém os 3. **v1.1:** o `PATCH` reenvia todos os itens na ordem, com quantidade exata e só o `user_kcal` que o servidor aplicou.

### D — quantidade com vírgula truncada [CORRIGIDO na v1.1]

O campo de quantidade ainda usa `Decimal(string:)`: "140,5" vira 140 (experimento executado). Mesmo parser do fix de calorias deve ser aplicado; teste proposto: "140,5" → 140.5; "1.234" → recusado. **v1.1:** parser por idioma (pt-BR/en), sem leitura parcial; ambíguo recusado com erro explícito; calorias fracionárias aceitas (o schema aceita).

---

## 7. O que precisa de aprovação (lista exata)

**Contratos**

1. `POST /meal-drafts` (novo).
2. `propose`/`PATCH /registrations` com `source` opcional (extensão).
3. DTO pendente + `source`, `user_kcal`, `nutrition_source` (extensão).
4. `POST /weight` (novo).
5. `GET /plan-drafts`, `GET/PATCH/DELETE /plan-drafts/:id`, `POST /plan-drafts/:id/confirm` (novos).
6. `POST /plan-imports` (novo).
7. `POST /flow/chat` com `draft` opcional na resposta (extensão).
8. `POST /media` com `kind: plan_document` e `application/pdf` (extensão).

**Migrations**

- M1 `user_profiles.weight_measured_at` + `record_weight_atomic`.
- M2 `plan_drafts` + RLS + 4 RPCs.
- M3 `media_assets` (kind, CHECKs) + bucket `plan-documents` + retenção.

**Agente/worker**

- S1 allowlist na execução.
- S2 chave do Flow por usuário.
- S3 persona nos geradores.
- Ferramentas `propoe_plano_*`.
- Módulo de extração de texto de refeição.
- Ramo `plan_document` no worker.

**Dependência:** biblioteca de extração de texto de PDF no servidor (escolha pelo executor, com licença verificada). Nenhuma dependência nova no iOS.

**Permissões iOS:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, autorização de notificações em tempo de execução. Sem biblioteca de fotos, sem background, sem push.

**Custos:** Vision, STT e LLM de extração/geração dentro dos US$ 15 da rodada técnica. O saldo exige somar o consumo real de **todos** os provedores (OpenRouter e Groq); só há registro de US$ 0,0297 em 17/09 — o restante é [DESC] até a conferência.

---

## 8. Sequência de implementação após aprovação

| Lote | Conteúdo | Depende de | Tamanho |
|---|---|---|---|
| 0 | S1, S2, harness A/B (S4) | aprovação do backend | P |
| 1 | C5 (M1 + RPC + endpoint + iOS); achados C e D; DTO pendente com `user_kcal`/`nutrition_source`/`source` (fecha o item 4 de A) | lote 0 | M |
| 2 | C2 lembretes locais (só iOS, contratos existentes) | nada — pode correr junto do lote 1 | M |
| 3a | C1 infraestrutura de mídia iOS + foto/galeria → candidatos → proposta | lote 1 (DTO) | G |
| 3b | C1 áudio (gravação/importação) + texto livre com extração | 3a; chave OpenRouter/Groq no staging | M |
| 4a | M2 + endpoints + tela de revisão compartilhada | lote 0 | G |
| 4b | C4 ferramentas de proposta + cartão no Flow | 4a + S1 + S3 | M |
| 4c | C3 importação (M3 + dependência PDF + worker) | 4a | G |

**Primeiro lote recomendado:** 0 + 1 + 2. Os três não precisam de dependência nova, só o 0 e o 1 tocam backend, e o 2 é inteiramente iOS.

E2E de qualquer lote com backend depende de deploy do BFF e de migrations no **branch de staging** — ver §9.

---

## 9. Ações externas que dependem do usuário (agrupadas)

- **Acesso técnico**
  - Escopo Vercel `gestao-9664s-projects` no token (deploy do BFF de staging com os endpoints novos).
  - Chaves OpenRouter e Groq válidas no staging.
  - Aprovação para aplicar migrations no branch `xitugspwfxkcluxvrdeg`.
- **Contas QA**
  - Aprovar a criação das três contas dedicadas no staging.
  - Digitar as credenciais no Simulator (takeover).
- **Apple:** inscrição no Apple Developer individual e TestFlight privado. Para testes em device antes disso, alternativa: rodar pelo Xcode com o Apple ID pessoal do Eduardo (provisionamento gratuito, 7 dias) — decisão e login dele.
- **Documentação e consentimento:** documentos reais (privacidade de foto/áudio/saúde) antes de qualquer uso com dados reais. Os aceites QA não valem como aprovação jurídica.
- **Conteúdo:** Biblioteca com autoria e fontes legítimas.
- **Orçamento:** teto da avaliação de 30 dias (separado dos US$ 15).

---

## 10. Ainda desconhecido

- Prompts e modelos de Vision ativos no banco.
- Presença de `duration` no retorno do Groq; limites do Groq.
- Policies de `storage.objects` criadas fora das migrations.
- Se `getUser` recusa usuário banido.
- Se o modelo emite chamadas a ferramentas não declaradas (motivo de S1).
- Dados legados em `user_progress.current_weight`/`reevaluations`.
- Se `DietPlan` pode conter suplementos (a checar na implementação de 4b).
- Consumo real de API/IA fora do registro de 17/09.

---

## 11. Emenda 1 (v1.1, 2026-09-27)

Emendas técnicas pedidas na revisão. Onde contradizem o v1, estas valem; o texto original ficou no lugar, marcado. **Nada aqui autoriza implantar M1, M2, M3 ou a dependência de PDF.**

### 11.0 S1 e S2 — como ficaram (implementado localmente)

- **S1:** `authorizeToolCall(name, filteredTools)` roda antes de qualquer efeito — parse de argumentos, caminho de pending adiado, `execute`, auditoria. A ferramenta só existe para a requisição se estiver na interseção canal ∩ configuração; o registro completo serve só para distinguir `tool_unknown` de `tool_not_authorized`.
  - Recusa: sem argumentos no resumo, nome saneado, evento `pipeline.tool_call_denied` com `{tool, reason, channel}`.
  - Afirmação falsa de gravação num canal sem ferramenta de escrita: o retry pede **retratação** em vez de chamar ferramenta; o nudge de falsa duplicação só diz "registre TODOS" onde registrar é permitido.
  - WhatsApp: `allowed_tools` vazio/NULL continua valendo "todas" (semântica existente); lista não vazia agora limita também a execução. **Antes de qualquer deploy:** conferir (leitura) a configuração de produção; o formulário de admin não lista `reclassifica_refeicao`.
- **S2:** mensagens novas do `mobile_flow` usam `mobile_flow/<user_id>/<key>` e a resposta `…/assistant`, com o `user_id` do contexto autenticado. Linhas legadas (chave pura, resposta `<key>:assistant`) são achadas só para o mesmo usuário e preservadas.
  - Mesma chave com texto diferente → 409 `idempotency_key_conflict`.
  - Inserção concorrente da mesma entrada → 409 `idempotency_request_in_progress`, sem chamar o Flow.
  - Resposta já gravada para o turno → replay; qualquer outra falha marca a entrada como `failed` (nunca fica `processing`).
- **Ainda pendente (não corrigido):** o ramo de retry de uma entrada falha não passa pelo limite de 10/min; tags `[BTN:]`/`[LIST:]` produzem resposta vazia no mobile. Harness A/B autenticado contra banco local: indisponível nesta máquina (CLI Supabase ausente; os containers em execução são de outro projeto).

### 11.1 C1 — mídia

- **Limite de áudio único no cliente e no servidor: 180 s.**
  - Cliente: corta a gravação em 180 s e recusa importação acima disso antes do upload.
  - `POST /media` [PROP]: aceita `duration_ms` declarado (≤ 180 000) só como pré-filtro, não como prova.
  - Worker [PROP]: mede a duração pelo contêiner do arquivo (cabeçalho m4a/mp4, WAV, MP3) **antes** da transcrição e falha com `audio_too_long` sem chamar o STT. Não depende do `duration` opcional que o STT devolve depois.
  - A leitura de duração exige um parser ou dependência → aprovação junto com as mídias.
- **Rótulo nutricional preso a um único alimento.**
  - Cada candidato de `/meal-drafts` ganha `candidate_id` estável.
  - O rótulo só vem associado (`applies_to_candidate_id`) quando a associação é inequívoca — um item, ou nome compatível.
  - Se o paciente remover ou renomear o candidato, a associação cai e só volta por ação explícita ("usar rótulo neste item").
  - No `propose`, no máximo um item carrega a referência. O servidor relê o rótulo de `processing_result` e aplica só a esse item; se houver ambiguidade, ignora o rótulo e calcula normalmente (mesma regra do WhatsApp, `shouldBlockUntrustedNutritionLabelRegistration`).
- **Porção de referência não vira dado exato.**
  - Gramas de `portion_reference` (regras de exibição de `naturalUnit`) aparecem como "aproximado" e exigem confirmação ativa do paciente por item antes de propor.
  - A proposta registra `quantity_basis`, para a origem ficar visível depois.

### 11.2 C2 — lembretes locais

- **Horizonte real = até a 60ª ocorrência agendada**, mostrado ao paciente ("lembretes agendados até …"). Exemplo: 10 lembretes/dia ≈ 6 dias.
- **Excedente nunca é omitido em silêncio.** O planejador devolve o que ficou de fora com o motivo:
  - orçamento, horário de silêncio, limite diário;
  - horário inexistente (salto de horário de verão);
  - permissão negada, fuso não definido.

  A tela mostra a contagem por motivo, e uma última notificação avisa para abrir o app.
- **Permissão negada:** nada é agendado; aviso persistente com atalho para Ajustes; a lista de horários continua visível no app.
- **Sem promessa de 30 dias:** os lembretes cobrem só o horizonte da última sincronização; a copy diz isso.
- **Prioridade, horário de silêncio e limite diário só afetam a entrega local.** Nunca mudam agenda, dose ou prescrição no servidor; uma ocorrência silenciada continua visível em Hoje/Rotina como "silenciada".

### 11.3 C3/C4 — confirmação de planos

- **Confirmação concorrente de dois rascunhos do mesmo usuário e domínio:**
  - a RPC de confirmação usa o mesmo lock consultivo da troca de plano (`<user_id>:training-plan`; para nutrição, `<user_id>:nutrition-plan`);
  - exige que o plano de referência do rascunho ainda seja o atual;
  - o segundo a confirmar recebe 409 `plan_changed_during_review` e precisa revisar de novo.
- **Coordenação com a RPC existente de troca de plano:** a lógica "desativa + insere" vira uma função interna única (`private.replace_active_training_plan`), usada por `save_training_plan_atomic` (WhatsApp) e pela confirmação do app. A confirmação não liga `training_reminders`. É refatoração de RPC existente — faz parte de M2.
- **Identidade e versão do plano nutricional:** `prescriptions` não tem status nem idempotência. M2 acrescenta `source_request_key` com unicidade por usuário. O conflito usa `base_latest_prescription_id` (a prescrição válida mais recente do tipo quando o rascunho nasceu). A confirmação só insere e nunca altera ou apaga prescrições anteriores.
- **Extração incompleta separada da validação estrita:**
  - o rascunho guarda `extraction_payload` com schema permissivo (campos anuláveis, desconhecidos preservados em `unrecognized_segments`);
  - o `payload` confirmável passa pelo schema estrito só na confirmação;
  - estado `needs_completion` enquanto faltar campo obrigatório.
- **Nenhum rascunho se confirma por decisão do LLM:** confirmar só acontece em `POST /plan-drafts/:id/confirm`, com o token do paciente, `Idempotency-Key` e `payload_version`. A RPC só é executável por `service_role`. Nenhuma ferramenta de agente chama a confirmação, e há teste que garante que nenhuma ferramenta de confirmação fica disponível no canal mobile (a autorização S1 recusa qualquer outra).
- **Origem ligada a recursos do mesmo dono:**
  - chaves estrangeiras compostas `(source_media_asset_id, user_id) → media_assets(id, user_id)` e `(source_message_id, user_id) → messages(id, user_id)`, com os índices únicos necessários (M2);
  - a RPC checa de novo;
  - teste A/B com mídia e mensagem de outro usuário → 404.

### 11.4 C5 — peso

- **Todos os que escrevem `user_profiles.weight_kg`:**
  - WhatsApp `cadastra_dados_iniciais` (upsert direto);
  - onboarding mobile `complete_mobile_onboarding_atomic` (uma vez);
  - `POST /onboarding` parcial legado (via a mesma ferramenta);
  - o `record_weight_atomic` proposto.

  Outros escritores (painel admin, backfills): [DESC], a levantar na implementação.
- **Um único caminho de escrita:** função `private.apply_weight_measurement(p_user_id, p_weight_kg, p_measured_at, p_source)`, chamada por **todos** esses escritores, que grava `weight_kg` e `weight_measured_at` juntos. Assim o "último peso" não diverge por canal. O WhatsApp passa o instante da mensagem.
- **Ordem:**
  - aplica só se `weight_measured_at IS NULL` (valor legado sem data — não é possível provar que ele é mais recente) ou se `p_measured_at > weight_measured_at`;
  - **mesmo instante e mesmo valor** (após converter e arredondar para 2 casas) → sem efeito, `applied:false, reason:'same_measurement'` — cobre replay a qualquer tempo;
  - **mesmo instante e valor diferente** → 409 `weight_measurement_conflict`;
  - **mais antigo** → `applied:false, reason:'older_than_current'`.

  Isto corrige a contradição do v1 entre "não aplica se `<`" e "replay nunca reaplica".
- **Unidade:** `lb` convertida no servidor (×0,45359237) e arredondada **antes** da comparação, para replays em libra coincidirem.
- **Efeitos:** os mesmos do WhatsApp; nada escreve em snapshots, bloco ou `user_progress`.

### 11.5 C3 — limites explícitos

- PDF escaneado (sem camada de texto) não é extraído nesta beta: o app pede fotos das páginas.
- A retenção de 90 dias de `plan-documents` é **proposta**; não é política de dados aprovada e depende dos documentos jurídicos (D5).

### 11.6 S3 — identidade nos geradores

A identidade Flow nos geradores de plano é passada **só pelo caminho do canal mobile**. As ferramentas e geradores do WhatsApp mantêm a persona atual; não há troca global de identidade.
