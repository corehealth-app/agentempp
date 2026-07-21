# ADR 014 — Catálogo determinístico de mensagens do coach

- Status: Accepted
- Data: 2026-07-20
- Decisores: Eduardo

## Contexto

O BodyFlow app-first precisa adaptar o tom do coach sem transformar lembretes e
confirmações recorrentes em chamadas abertas de LLM. O produto também precisa
variar mensagens sem repetição imediata, manter português e inglês separados,
permitir revisão editorial e preservar o texto exato que motivou uma entrega.

Geração em runtime aumentaria latência, custo e variância, além de dificultar
idempotência, auditoria e aprovação de conteúdo. Editar versões já usadas apagaria
a evidência histórica. Uma rotação automática de sinônimos sem revisão poderia
introduzir promessa clínica, culpa, julgamento ou placeholders inválidos.

## Decisão

1. Mensagens recorrentes são rendições determinísticas de um catálogo versionado.
   O runtime seleciona no PostgreSQL e nunca chama LLM como fallback.
2. O catálogo cobre `balanced`, `focus`, `impulse` e `zen`, 15 contextos,
   `in_app`, `push` e `email`, `pt-BR` e `en-US`, com três variantes por
   combinação. `balanced` é fallback interno e não pode ser escolhido pelo
   paciente.
3. A seleção mantém locale exato, tenta a personalidade efetiva e depois
   `balanced`, rotaciona as três variantes por uso menos recente e usa lock,
   cooldown, limite local e chave de evento para ser concorrente e idempotente.
4. `suppressed`, falha ou ausência de versão retorna nenhuma mensagem. O caller
   não inventa texto nem chama outro modelo. Falha de renderização é registrada
   sem corpo de mensagem ou PII.
5. Templates e seu conteúdo são estáveis; cada edição cria uma nova versão
   imutável. O uso referencia a versão exata selecionada.
6. Packs controlam publicação. Um novo ciclo nasce de clone do ativo, recebe
   revisões, passa por lint e validação de cobertura e só pode ser agendado ou
   ativado contra o hash do snapshot revisado.
7. Renovação mensal é um processo editorial, não uma troca cega de sinônimos. O
   scheduler pode ativar apenas um pack completo que já foi aprovado e agendado
   por humano. Ele não gera conteúdo.
8. `content_editor` pode ler, clonar, revisar, pré-visualizar e validar rascunhos.
   `master_admin` também pode agendar, ativar, arquivar e restaurar. Toda ação
   revalida auth e RBAC antes de criar cliente privilegiado.
9. Reescrita assistida é opcional, explícita e limitada a um grupo. Usa somente
   cópia aprovada do pack ativo, saída JSON limitada, temperatura baixa e lint
   completo. O resultado cria `assisted_draft` e exige aprovação humana.
10. O canal `email` existe para manter o contrato editorial completo, mas sua
    policy permanece com `delivery_enabled=false`. Push permanece em outbox até
    existir integração APNs autorizada.
11. O mascote nesta fase é apenas estado persistido com transições explícitas.
    Não há representação visual, progressão temporal automática nem inferência a
    partir de comportamento ou métricas de saúde.

## Integridade e auditoria

- Um índice parcial garante no máximo um pack ativo.
- Ativação e rollback são transacionais e preservam linhagem entre packs.
- O snapshot ordenado de `template_id:template_version_id` recebe SHA-256; uma
  mudança concorrente bloqueia agendamento ou ativação.
- Telemetria guarda IDs técnicos, resultado, personalidade efetiva, tokens,
  custo e latência quando aplicável. Não guarda prompt editorial, corpo gerado,
  mensagem renderizada ou identidade do paciente.
- Tabelas e RPCs internas revogam `PUBLIC`, `anon` e `authenticated`; o app
  paciente acessa preferência e estado apenas pelo BFF autenticado.

## Consequências

- **+** Lembretes recorrentes têm custo de LLM zero, latência previsível e texto
  previamente revisado.
- **+** Retry e concorrência não duplicam uso nem mudam a variante do mesmo
  evento.
- **+** Histórico continua reproduzível porque a versão selecionada é imutável.
- **+** Variação acontece antes de repetição e nunca cruza idioma.
- **+** Refresh mensal é auditável, reversível e separa sugestão de publicação.
- **−** Novos contextos, idiomas ou variáveis exigem ampliar e validar a matriz
  completa do catálogo.
- **−** Falha fechada pode resultar em nenhuma mensagem; observabilidade precisa
  alertar para supressão ou cobertura ausente.
- **−** A console assistida ainda depende de credencial de provedor configurada e
  de revisão humana; sem isso, a edição manual continua sendo o caminho oficial.
- **−** Email, APNs e mascote visual continuam fora desta decisão operacional.

Esta decisão foi validada somente na Supabase Branch de staging
`xitugspwfxkcluxvrdeg`. Não houve deploy, configuração de provider ou alteração
de produção.
