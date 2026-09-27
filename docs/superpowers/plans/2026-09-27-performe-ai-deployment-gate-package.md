# Performe AI — pacote do próximo gate de implantação (2026-09-27)

Performe AI = produto público; Flow = agente público; BodyFlow = identidade técnica interna preservada.

Este pacote **não executa nada**. Nenhuma configuração de produção foi lida ou alterada para escrevê-lo. Deploy, migration, leitura de produção e uso de provedor pago continuam exigindo autorização explícita do Eduardo, alvo por alvo. M1, M2, M3 e novas dependências continuam **sem** autorização de aplicação.

## 1. O que precisa ir para o backend, e em que ordem

| Ordem | Commit | Conteúdo que precisa estar no ar | Migration |
|---|---|---|---|
| 1 | `026e6c2e` | S1 — autorização das ferramentas na execução (agente). S2 — id das mensagens do Flow mobile por usuário (BFF). | nenhuma |
| 2 | `51f999af` | DTO pendente com `user_kcal` e `nutrition_source` por item (BFF, aditivo). | nenhuma |
| 3 | `63241c38` | 3.1 limite nas retentativas; 3.2 tags achatadas no mobile e resposta vazia = 502; 3.3 turno interrompido; S3 identidade Flow nos geradores (só canal mobile). | nenhuma |

- O admin (`apps/admin`) empacota o agente (`@mpp/agent`) e o `apps/mobile-bff` reexporta as rotas do admin: os três commits sobem juntos no mesmo deploy do BFF de staging, a partir de uma árvore que contenha os três.
- **Ordem obrigatória: backend → verificação → candidata iOS.** Até o BFF com o DTO aditivo estar no ar, o app recebe itens sem proveniência e **bloqueia a edição** de propostas de refeição (comportamento seguro escolhido em `51f999af`); confirmar e cancelar continuam funcionando.
- A candidata iOS só é gerada depois da verificação da seção 2, a partir do commit iOS mais recente (lembretes locais incluídos: `18aacc8c`).

## 2. Verificação depois do backend novo (staging, conta QA dedicada)

1. `GET /api/mobile/v1/pending` de uma proposta de refeição traz, em cada item, as chaves `user_kcal` e `nutrition_source` (valor ou `null`).
2. No app: abrir o editor de uma proposta **sem** valor informado → salvar sem mexer → o `PATCH` não envia `user_kcal`; a proposta mantém o cálculo oficial.
3. Informar kcal (ex.: `180,5` em pt-BR) → salvar → reabrir o editor: o valor volta como "informado por você"; salvar sem mexer mantém o mesmo `user_kcal`.
4. Proposta com 3 itens → editar o primeiro → os itens 2 e 3 voltam na mesma ordem, com quantidades exatas.
5. Flow: uma mensagem normal responde; repetir a mesma `Idempotency-Key` devolve a mesma resposta sem nova cobrança (`Idempotency-Replayed: true`).
6. Flow: pedir "monte meu treino" no app → nenhuma ferramenta `gera_*` executa (evento `pipeline.tool_call_denied` com `{tool, reason, channel}` e sem argumentos).

## 3. A/B autenticado ainda necessário (não feito: sem Supabase local nesta máquina)

Com **duas** contas QA dedicadas (não CI-3), no staging, depois do deploy:

- mesma `Idempotency-Key` nas duas contas → duas conversas independentes, sem 500;
- 11 envios em 1 minuto numa conta → o 11º recebe 429; a outra conta não é afetada;
- retentativa de um turno que falhou → conta no limite; replay de resposta gravada → não conta;
- turno interrompido (derrubar a função durante o provider) → a próxima tentativa com a mesma chave não chama o provider; a seguinte, explícita, executa uma vez;
- lembretes locais: conta A agenda no iPhone → sair → nenhum lembrete de A pendente ou entregue; conta B entra → só os de B; tocar numa notificação antiga de A com B logada não abre nada.

## 4. Escopo de S1/S2/S3 e do bloco Flow runtime que afeta o WhatsApp

| Mudança | Efeito no WhatsApp |
|---|---|
| S1 — autorização na execução | **Sim.** Onde o prompt ativo do estágio tem `allowed_tools` **não vazio**, a lista passa a limitar também a execução (antes limitava só os schemas mostrados ao modelo). `NULL`/vazio continua = todas as ferramentas. |
| S2 — id das mensagens | Não (só `provider = 'mobile_flow'`). |
| S3 — identidade dos geradores | Não. Os prompts legados de treino e dieta são byte a byte iguais (hash travado em teste); "Flow" só com o canal `mobile_flow` decidido no servidor. |
| 3.1/3.3 — execuções e recuperação | Não (serviço do chat mobile). |
| 3.2 — tags `[BTN:]`/`[LIST:]` | Não. Continuam virando botões/lista no WhatsApp; o achatamento vale só no canal mobile. |

## 5. Configuração a conferir antes de qualquer promoção compartilhada

- **`allowed_tools` de cada estágio ativo** (`v_active_prompts`), em staging e depois em produção (leitura, com autorização): qualquer estágio com lista não vazia que omita uma ferramenta usada no WhatsApp passa a recusá-la. O formulário de admin não lista `reclassifica_refeicao`.
- Chave do provedor do Flow (`OPENROUTER_API_KEY`) no ambiente do BFF de staging — sem ela o Flow responde 502 tipado.
- `maxDuration` da rota do Flow (300 s) menor que a janela "em andamento" do ledger (10 min) — travado em teste; mudar um exige rever o outro.
- iOS: lembretes locais não exigem entitlement, background nem chave no Info.plist; a permissão é pedida só ao ativar.

## 6. Pontos do desenho C1–C5 (v1.1) ainda pendentes

Só o que falta; decisões de produto já tomadas não são repetidas.

- **C1 — mídia.** Contratos `POST /meal-drafts`, `source` em `propose`/`PATCH`, `POST /media` com `plan_document`/PDF e `duration_ms`; leitura da duração do contêiner de áudio antes do STT (dependência a aprovar); M3.
  - **Correção a registrar no §11.1:** o texto diz que, com associação ambígua, o servidor "ignora o rótulo e calcula normalmente (mesma regra do WhatsApp)". O guard atual (`shouldBlockUntrustedNutritionLabelRegistration`, `packages/agent/src/vision-nutrition-guard.ts`) **bloqueia** o registro e pede confirmação de item e porção quando o rótulo não é confiável ou não se associa a um item. A implementação de C1 deve preservar essa proteção: associação ambígua **nunca** passa em silêncio para um cálculo alternativo.
- **C2 — lembretes locais.** Implementado localmente nesta operação (ver a evidência). Pendente: entrega real num iPhone físico (conteúdo por modo de privacidade na tela bloqueada, persistência após reinício, mudança de fuso), que depende de device conectado e autorizado.
- **C3/C4 — planos.** M2 (`plan_drafts` + RLS + RPCs, `private.replace_active_training_plan`, `prescriptions.source_request_key`, FKs compostas); endpoints `plan-drafts`/`plan-imports`; `draft` em `POST /flow/chat`; ferramentas `propoe_plano_*` (não disponibilizadas); dependência de extração de PDF.
- **C5 — peso.** M1 (`weight_measured_at` + `private.apply_weight_measurement` para todos os escritores) e `POST /weight`.
- **S4 — harness A/B autenticado local.** Sem CLI Supabase nesta máquina; não usar containers de outro projeto.
- **Endurecimento opcional (sem pedido de aprovação agora):** o limite de 10 execuções/minuto é garantido no serviço por recontagem depois do registro (nunca passa do limite; pode recusar a mais numa rajada concorrente). Uma checagem atômica exigiria uma RPC nova — contrato mínimo: `claim_mobile_flow_execution(p_user_id, p_provider_message_id, …)` com `pg_advisory_xact_lock` por usuário, contando e registrando na mesma transação.

## 7. Contratos e migrations que ainda exigem aprovação

- Contratos: `POST /meal-drafts`; `source` opcional em `propose`/`PATCH /registrations`; `source` no DTO pendente; `POST /weight`; `GET /plan-drafts`, `GET/PATCH/DELETE /plan-drafts/:id`, `POST /plan-drafts/:id/confirm`; `POST /plan-imports`; `draft` opcional em `POST /flow/chat`; `POST /media` com `plan_document`/PDF e `duration_ms`.
- Migrations: M1, M2, M3.
- Dependências: extração de texto de PDF no servidor; leitura de duração de áudio.
- Já feitos sem migration (não pedem aprovação de schema, só de deploy): S1, S2, S3, DTO `user_kcal`/`nutrition_source`, bloco Flow runtime, C2 (só iOS, contratos existentes).
