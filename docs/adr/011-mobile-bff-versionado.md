# ADR 011 — BFF mobile versionado em Next.js Route Handlers

- Status: Accepted
- Data: 2026-07-20
- Decisores: Eduardo

## Contexto

O BodyFlow app-first precisa de contratos estáveis para iOS e futuro Android.
O banco e os serviços de domínio existentes são reaproveitáveis, mas o cliente
móvel não pode receber `service_role`, conhecer tabelas internas nem duplicar as
regras determinísticas já usadas pelo agente de WhatsApp.

O repositório já possui um runtime Next.js na Vercel (`apps/admin`), os cálculos
nutricionais e ferramentas em `@mpp/agent`, o motor puro em `@mpp/core` e acesso
tipado ao Supabase em `@mpp/db`. Não há backend HTTP separado que justifique um
novo serviço nesta fase.

## Decisão

1. A API mobile V1 vive em `apps/admin/src/app/api/mobile/v1` como Route
   Handlers Node.js.
2. Cada request valida o bearer token no Supabase Auth, exige e-mail confirmado,
   inicializa o perfil app-first de modo idempotente e resolve o `users.id` por
   `auth_user_id`.
3. Rotas usam DTOs explícitos, envelopes JSON versionados e `Cache-Control:
   no-store`.
4. O `service_role` existe somente no servidor e toda consulta é delimitada pelo
   `user_id` autenticado.
5. Mutações exigem `Idempotency-Key`. O ledger backend-only retém hash canônico
   e resposta por 24 horas; ele nunca armazena o bearer token ou o request bruto.
6. Refeições e treinos reutilizam `@mpp/agent`. Macros finais são calculados no
   servidor, apresentados em pending e preservados na confirmação.
7. WhatsApp e mobile compartilham o adaptador de confirmação em
   `@mpp/agent/confirmed-meal`; o BFF não mantém uma segunda regra nutricional.
8. Persona, publicações e StoreKit mantêm contrato explícito de indisponibilidade
   até seus respectivos módulos serem implementados.

## Consequências

- **+** iOS e Android recebem uma fronteira estável sem acesso direto ao schema.
- **+** Autorização, erros, observabilidade e idempotência ficam centralizados.
- **+** O canal mobile reutiliza as correções nutricionais e transações existentes.
- **+** O BFF pode evoluir internamente sem exigir mudanças no banco exposto ao app.
- **−** `apps/admin` passa a hospedar superfícies administrativas e mobile; limites
  de deploy e observabilidade precisam continuar separados por rota e ambiente.
- **−** A disponibilidade da API depende do runtime Vercel e do Supabase.
- **−** Persona, conteúdo e compra móvel ainda precisam de implementações futuras.

Nenhum deploy foi realizado por esta decisão. A migration e a validação live
desta fase ocorreram somente na Supabase Branch de staging.
