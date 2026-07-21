# ADR 015 — CMS de conteúdo educativo do BodyFlow

- Status: Accepted
- Data: 2026-07-21
- Decisores: Eduardo

## Contexto

O BodyFlow precisa publicar conteúdo educativo em `pt-BR` e `en-US` sem deploy,
com revisão técnica separada da autoria e controle explícito de publicação. O
app móvel deve receber somente a versão localizada, publicada e elegível para o
paciente, sem acesso direto ao schema editorial, ao `service_role` ou aos paths
do Storage.

Editar uma linha já publicada apagaria a evidência do texto aprovado e poderia
alterar conteúdo vivo antes de nova revisão. Um estado de publicação atualizado
por cron também criaria uma transição operacional desnecessária: a visibilidade
pode ser derivada de `publish_at` no relógio do banco. Capas privadas exigem uma
capacidade curta, mas uma signed URL direta não revalidaria a elegibilidade do
paciente depois de emitida.

## Decisão

1. Uma publicação mantém identidade e slug estáveis. Cada alteração editorial
   cria uma versão numerada imutável depois da submissão. `pt-BR` e `en-US` têm
   fluxos e publicação independentes, sem fallback entre locales.
2. Categoria, tags, destaque, capa e targeting são snapshots da versão. Targets
   de protocolo, plano e personalidade são version-scoped; ausência de valores
   em uma dimensão significa wildcard e dimensões configuradas combinam com AND.
3. `content_editor` cria, edita e submete. `nutrition_admin`, diferente do autor,
   aprova ou rejeita. `master_admin` publica imediatamente, agenda e arquiva. As
   RPCs revalidam o papel canônico e registram auditoria na mesma transação.
4. O estado persistido da versão é `draft`, `in_review`, `approved` ou
   `rejected`. Uma versão aprovada sem `publish_at` não é visível; com horário
   futuro está agendada; com `publish_at` menor ou igual ao relógio do banco pode
   ser exibida. Não existe cron para virar uma versão de agendada para publicada.
5. A versão visível é a versão aprovada mais recente e já vencida para a
   publicação e o locale. Enquanto uma substituição está em rascunho, revisão ou
   aguardando seu horário, a versão viva anterior permanece disponível.
6. Arquivo é uma ação global na publicação. Ele oculta imediatamente todos os
   locales e versões sem apagar histórico, auditoria, estado ou eventos; assim,
   arquivar uma versão nova nunca revela acidentalmente uma versão antiga.
7. Capas ficam no bucket privado `content-covers`. O BFF entrega uma capability
   proxy opaca, autenticada e válida por 300 segundos, vinculada a paciente,
   publicação e versão. Cada leitura revalida usuário, elegibilidade, arquivo,
   versão e capa; bucket e object path não são expostos ao app.
8. O paciente acessa conteúdo somente pelo BFF mobile autenticado. Tabelas e
   RPCs de CMS permanecem internas, com RLS e sem grants para `PUBLIC`, `anon` ou
   `authenticated`; execução e DML de backend ficam restritas ao `service_role`.
9. Eventos de impressão, abertura e conclusão, além de save/unsave, são
   idempotentes. O ledger genérico do BFF protege método, rota e payload, e uma
   event key com hash no banco impede duplicação caso a mutação seja commitada
   antes da conclusão do claim externo.
10. O corpo canônico é Markdown validado e normalizado. HTML, H1, imagens inline,
    embeds e links não HTTPS são rejeitados antes da persistência; o corpo não é
    copiado para logs ou auditoria.

## Consequências

- **+** O texto efetivamente publicado continua reproduzível e ligado à revisão
  e aos atores que o aprovaram.
- **+** Idiomas, targeting e conclusão evoluem por versão sem alterar
  silenciosamente uma versão viva.
- **+** Agendamento não depende de worker, cron ou transição atrasada; todas as
  leituras usam a mesma autoridade temporal do banco.
- **+** O app não recebe credencial privilegiada, tabela interna, bucket, path ou
  URL permanente de capa.
- **+** Retries do HTTP e do banco não duplicam métricas nem alternam estado salvo.
- **−** Cada correção publicada exige um novo fluxo de autoria, revisão e
  publicação por locale.
- **−** A elegibilidade e o proxy de capa adicionam consultas ao BFF e tornam a
  disponibilidade dependente do runtime e do Supabase.
- **−** Uma capability expirada ou uma mudança de elegibilidade exige recarregar
  o DTO para obter outra URL opaca.
- **−** Falta de versão no locale ou segmento correto resulta em ausência de
  conteúdo, pois o sistema falha fechado e não cruza idioma ou targeting.

## Validação

Os contratos, guards, DTOs, queries de visibilidade e migrations foram revisados
localmente nesta etapa. A aplicação das migrations, as SQL suites live, o
canário concorrente do fluxo editorial único, os canários sintéticos e a
validação completa na Supabase Branch de staging permanecem pendentes para a
Task 8. Nenhuma migration foi aplicada, nenhum deploy foi executado e produção
não foi alterada por esta decisão.
