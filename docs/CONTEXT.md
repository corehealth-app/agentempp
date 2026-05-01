# Context — Agente MPP

> Documento vivo. Atualizar a cada fase e a cada decisão grande.

---

## Cliente e produto

- **Cliente:** CoreHealth (org GitHub: `corehealth-app`)
- **Produto:** Agente MPP — coach nutricional via WhatsApp do método Muscular Power Plant (Dr. Roberto Menescal)
- **Repositório:** https://github.com/corehealth-app/agentempp
- **Owner do código:** CoreHealth (work-for-hire)
- **Pagamento das APIs:** CoreHealth
- **Manutenção pós go-live:** Eduardo (gestao-hub) com acesso permanente
- **Responsabilidade por incidentes em prod:** Eduardo
- **Handover:** treinamento ao final do projeto

---

## Estado atual

- Fase atual: **Fase 0 — Setup**
- Não há usuários em produção
- Não há assinantes pagantes
- Não há dados a preservar
- Sistema legado (n8n + Notion + Chatwoot + Evolution API) será **substituído**, não migrado de dados

---

## Decisões já tomadas

Ver [`adr/`](./adr/). Resumo:

| ADR | Decisão |
|---|---|
| 001 | WhatsApp Cloud API oficial desde o MVP |
| 002 | Saída total do Notion → Postgres + admin UI |
| 003 | Saída total do n8n → código TypeScript com Inngest |
| 004 | TTS híbrido: ElevenLabs (âncoras Dr. Roberto) + Cartesia (operacional) |
| 005 | Gemini 2.0 Flash via OpenRouter para vision |
| 006 | TACO importada como base nutricional |
| 007 | Cálculos e roteamento determinísticos em código |
| 008 | Versionamento imutável de prompts via trigger Postgres |
| 009 | Greenfield — sem migração de dados |
| 010 | Cliente paga APIs, código no GitHub Org dele |

---

## Infraestrutura provisionada

| Serviço | Status | Detalhes |
|---|---|---|
| GitHub repo | ✅ Existe (público) | `corehealth-app/agentempp` — `gestao-hub` precisa de write access |
| Supabase | ✅ Linkado | project_ref `xuxehkhdvjivitduarvb` (plano Free, tier Nano) — sem staging separado por enquanto |
| Vercel | ⏳ Pendente | Conta existe, projeto a criar |
| Stripe | ⏳ Pendente | Conta existe, products a criar |
| WhatsApp Cloud | ⏳ Pendente | Aguardando setup Meta Business |
| OpenRouter | ⏳ Pendente | Pendente |
| Groq | ⏳ Pendente | Pendente |
| ElevenLabs | ⏳ Pendente | Voice ID conhecido: `oArP4WehPe3qjqvCwHNo` |
| Cartesia | ⏳ Pendente | Pendente |
| Inngest | ⏳ Pendente | Pendente |
| Helicone | ⏳ Pendente | Pendente |
| Sentry | ⏳ Pendente | Pendente |

---

## Riscos conhecidos e aceitos

| Risco | Mitigação | Status |
|---|---|---|
| Credenciais Supabase expostas em chat (sessão de setup inicial) | Rotacionar antes do go-live | ⚠️ Aceito temporariamente |
| Sem ambiente staging separado (uma instância de Supabase serve dev e prod) | Criar staging antes de ter usuários reais | ⚠️ Aceito temporariamente |
| Plano Free (sem PITR backup) | Migrar para Pro antes do go-live | ⚠️ Aceito durante desenvolvimento |
| Repo público | Tornar privado quando contiver dados sensíveis ou credenciais | ⚠️ Monitorar |

---

## Próximos passos

### Imediatos (Fase 0)

- [ ] `gestao-hub` ganhar write access no repo `corehealth-app/agentempp`
- [ ] Aplicar migrations 0001-0009 no Supabase
- [ ] Gerar types TypeScript do banco
- [ ] Implementar lógica de domínio em `@mpp/core` com testes
- [ ] Primeiro commit + push

### Fase 1 (Ingestão WhatsApp)

- [ ] Provisionar Meta Business + WhatsApp Cloud API
- [ ] Aprovar 7 templates HSM
- [ ] Implementar `WhatsAppCloudProvider`
- [ ] Edge Function `webhook-whatsapp`
- [ ] Buffer + dedupe

### Fase 2 (Migração de prompts)

- [ ] Script de extração das 88 regras + 6 configs do JSON do n8n
- [ ] Inserção no Postgres
- [ ] View `v_active_prompts` validada

---

## Glossário

- **Bloco 7.700 kcal**: 1 kg de gordura. Marco de progresso na recomposição.
- **MPP**: Muscular Power Plant — método do Dr. Roberto Menescal.
- **HSM**: Highly Structured Message — templates aprovados pela Meta para envio fora da janela de 24h.
- **TACO**: Tabela Brasileira de Composição de Alimentos (UNICAMP).
- **PIT R**: Point-in-Time Recovery — backup contínuo do Postgres no plano Pro.
