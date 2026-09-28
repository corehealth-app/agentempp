# Avaliação fechada Performe AI — checklist de fatos e decisões

> **DRAFT — PENDING FACTUAL AND LEGAL REVIEW.** Nenhum item deste pacote está
> aprovado juridicamente, publicado ou aceito. Status do pacote:
> `LEGAL DOCUMENTS: DRAFT_READY / PENDING_FACTS / PENDING_REVIEW`.

Documentos deste diretório:
- `termos-de-uso-avaliacao.pt-BR.md`
- `politica-de-privacidade-avaliacao.pt-BR.md`
- `ia-e-permissoes.pt-BR.md`
- este checklist

Participantes previstos: Eduardo, Roberto e a esposa de Roberto. São três
contas, por 30 dias. Contato: contato@piperhub.com.br, apenas como canal de
contato.

## 1. Fatos verificados no código (28/09/2026)

| Tema | Fato | Evidência |
|---|---|---|
| Fotos | Reenviadas como JPEG novo, sem EXIF, GPS ou dados do aparelho, até 2048 px | `apps/ios/BodyFlow/BodyFlow/Features/Register/Media/MealMediaPreparation.swift` |
| Áudio gravado | Até 180 s, medido também no servidor | `media-service.ts` (`MAX_AUDIO_DURATION_MS`) |
| Áudio importado e PDF | Enviados como estão; metadados não removidos | `MealMediaPreparation.swift`, `PlanImportModel.swift` |
| Retenção de mídia | Foto de refeição e áudio: 30 dias. Documento de plano: sem prazo | `media-service.ts`; job `media-retention-cleanup` a cada hora |
| Conversa do Flow | Guardada em `messages`; telemetria sem o texto | `flow-chat-service.ts`; `MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT = false` |
| Documento de plano | Texto não classificado guardado no rascunho | `plan-document-processing.ts` |
| Respostas de idempotência | Guardadas com validade de 24 h; rotina de limpeza não encontrada | `mobile_api_idempotency` |
| Logs do servidor | Só código de erro e id da requisição | `lib/mobile-api/route.ts` |
| SDKs de terceiros no app | Só supabase-swift e swift-markdown; sem analytics nem relatório de falhas | `project.pbxproj`, `Package.resolved` |
| Notificações | Somente locais; o app não registra token de push | `LocalNotificationCenter.swift` |
| Permissões | Câmera e microfone com texto próprio; galeria pelo seletor do sistema | `Info.plist`, `InfoPlist.xcstrings` |
| Provedores de IA | OpenRouter para Claude Haiku 4.5, Gemini 2.5 Flash, Claude Sonnet 4.6 e o modelo do Flow; Groq Whisper para áudio | `meal-text-extractor.ts`, `runtime-config.ts`, `plan-document-extractor.ts`, `groq.ts` |
| Exclusão de conta | Não existe no app nem na API móvel | `me/route.ts` só tem GET e PATCH |
| Rotina de exclusão existente | Marca o usuário como excluído e apaga mídia e a linha do usuário; não apaga a conta de autenticação | `user-deletion-purger.ts` |
| Redefinição de conversa | Só administrador; mantém planos por padrão; apaga registros de refeição, treino, dia e mensagens | `20260928150000_bodyflow_reset_keeps_plans.sql` |

## 2. Pendências de fato

| # | Pendência | Quem resolve | Impacto |
|---|---|---|---|
| F1 | Helicone recebe dados? Os cabeçalhos são enviados, mas o destino é o OpenRouter | Eduardo, no painel Helicone ou na configuração | Lista de fornecedores |
| F2 | Região do Supabase e da Vercel do staging | Eduardo, nos painéis | Transferência internacional |
| F3 | Retenção e uso para treino nos provedores de IA (OpenRouter e roteamento) | Eduardo | Política seção 6 |
| F4 | Remover metadados de áudio importado e de PDF, ou declarar que são mantidos | Produto | Política 3.4 |
| F5 | Limpeza das respostas de idempotência com mais de 24 h | Engenharia | Política 3.7 e 8 |
| F6 | Procedimento de exclusão a pedido, incluindo a conta de autenticação | Engenharia e jurídico | Política seção 9 |
| F7 | Prazo de guarda de registros, conversas e perfil, e destino ao fim da avaliação | Eduardo e jurídico | Política seção 8; Termos seção 8 |
| F8 | Negar e conceder câmera e microfone no iPhone físico | Gate de dispositivo | `ia-e-permissoes` |

## 3. Decisões jurídicas e de negócio

| # | Decisão | Situação |
|---|---|---|
| D1 | Entidade controladora, CNPJ e endereço | PENDENTE. A entidade futura ainda não existe (ver `../legal-decision-register.md`) |
| D2 | Encarregado de dados | PENDENTE |
| D3 | Base legal por finalidade, incluindo o consentimento do art. 11, I, para dados de saúde | PENDENTE |
| D4 | Forma de registrar a ciência ou o consentimento dos 3 participantes, sem aceite fictício | PENDENTE |
| D5 | Transferência internacional, art. 33 | PENDENTE; depende de F2 e F3 |
| D6 | Registros de acesso: o art. 15 do Marco Civil pede 6 meses para provedor de aplicação com fins econômicos. Aplicabilidade a esta avaliação | PENDENTE |
| D7 | Responsabilidade, lei aplicável e foro nos Termos | PENDENTE |
| D8 | Comunicação de incidente de segurança | PENDENTE |

## 4. Bloqueios para distribuição futura, fora desta avaliação

A App Store Review Guideline 5.1.1(v) exige exclusão de conta dentro do app
quando o app permite criar conta. Esta versão não tem essa função. A
avaliação por instalação direta não passa pela App Store. Qualquer
distribuição, inclusive o TestFlight externo, precisa dela.

## 5. Fontes oficiais consultadas em 28/09/2026

- Lei nº 13.709/2018 (LGPD), portal do Planalto: art. 5º, II; art. 11, I; art. 18; art. 33. `https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm`
- Lei nº 12.965/2014 (Marco Civil da Internet), portal do Planalto: art. 15. `https://www.planalto.gov.br/ccivil_03/_ato2011-2014/2014/lei/l12965.htm`
- Autoridade Nacional de Proteção de Dados (ANPD): `https://www.gov.br/anpd/pt-br`
- Apple App Store Review Guidelines: 1.4.1, 5.1.1, 5.1.2 e 5.1.3. `https://developer.apple.com/app-store/review/guidelines/`

Nenhuma destas fontes foi interpretada como parecer jurídico. A aplicação
delas a este caso depende de revisão jurídica.
