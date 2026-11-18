# Limpeza de mídia no Supabase de staging

Este transporte reduz execuções vazias no Inngest. A implantação e a ativação são estados separados; consulte o checkpoint operacional para saber quais foram verificadas. O plano conversacional completo continua obrigatório.

## Limites

- Projeto permitido: `xitugspwfxkcluxvrdeg`. Endpoint fixo: `/functions/v1/conversation-media-maintenance` nesse projeto.
- Reutiliza `pg_cron`, `pg_net` e Edge Functions do projeto existente. Não cria workspace, projeto, assinatura ou chave de provedor.
- A migration `20261118011828_conversation_media_maintenance_bridge.sql` começa desligada e não agenda nenhum cron. Os quatro predicados são vinculados às versões existentes por hashes de `prosrc`.
- Nenhuma mídia antiga é matriculada em outra política. A referência cozida/nutrição, histórico, recibos, fatos clínicos, pontuação e mensagens não passam por este transporte.
- Os algoritmos continuam sendo os mesmos: mídia privada v2, mídia comum somente do cohort qualificado, fotos de reavaliação e preparação de exclusão de contas com carência de uma hora.

## Autorização e recuperação

Uma consulta por minuto verifica trabalho devido. Sem trabalho, não há chamada Edge nem execução no Inngest. Cada uma das quatro filas tem no máximo um despacho em espera ou em execução. Uma tarefa em espera expira em dois minutos; uma execução tem lease de 65 segundos.

O banco gera uma capacidade aleatória de 256 bits por despacho e guarda somente seu SHA-256 na tabela privada. O valor transitório vai no cabeçalho HTTPS interno do `pg_net`; não contém a chave `service_role`. O Edge usa a credencial que o próprio Supabase disponibiliza no runtime para consumir uma única autorização backend. O cliente do app não recebe nem pode criar autorizações. O corpo HTTP contém apenas `dispatch_id`; dono, bucket e caminho vêm das autoridades existentes no banco.

O corpo é limitado a 256 bytes e cinco segundos. Depois da autorização, todo acesso SDK verifica o destino e recebe o mesmo sinal de cancelamento, com orçamento de 55 segundos. A resposta contém somente estado e contagens. Falha ou resposta perdida deixa as obrigações existentes disponíveis para reconciliação; um despacho antigo não pode concluir outro. Desligar o dispatcher bloqueia novos grants; uma execução já autorizada pode ter iniciado IO, limitado por seu prazo e pelos protocolos de revisão de mídia.

Após um lote concluído, as filas privada e de contas aguardam 15 minutos; a comum aguarda uma hora; a de reavaliação volta no próximo minuto. Falha declarada permite nova tentativa após 30 segundos. Isso evita consultar marcadores vazios a cada minuto. A assinatura ainda desconhecida permanece desconhecida, e o marcador de zero bytes continua preservado.

## Artefato

Execute `node scripts/build-conversation-media-maintenance.mjs /caminho/externo/novo` a partir do repositório. O comando recusa sobrescrever artefatos e produz `index.ts`, `maintenance.js` e `SOURCE-MANIFEST.json`. O bundle fechado contém apenas contratos/algoritmos de limpeza e duas folhas puras já existentes de descarte de reavaliação. Não inclui scheduler Inngest, modelos, fábricas de credenciais ou agentes de conversa. O SDK do entrypoint tem versão fixa, correspondente à instalação verificada.

## Qualificação e troca

1. Conferir projeto, migrations anteriores, hashes, privilégios, mídia protegida e estado dos crons existentes. Aplicar somente a nova migration, desligada.
2. Implantar o artefato fechado na função específica, com autenticação de gateway desligada **somente porque o corpo faz sua própria autenticação por capacidade**. Conferir versão e hash, recusa de pedidos inválidos e autorização desligada, sem efeitos Storage.
3. Qualificar despachos controlados, concorrência, repetição, timeout, Storage real, remoção por versão, marcador vazio, preservação dos legados e descarte com processamento de fotos desligado. Não aceitar mídias privadas pelo app antes de haver limpeza contínua qualificada.
4. Somente então chamar `configure_conversation_media_maintenance(true, 'xitugspwfxkcluxvrdeg')`. Conferir um único cron `performe-conversation-media-maintenance`, ativo, e uma passagem real sem erro.
5. Trocar apenas o worker conversacional de staging para `MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED=true`, verificando o registro no Inngest. Ele deve servir somente os processadores de mídia, incluindo o privado quando habilitado. Nenhum roster antigo ou de produção muda. A configuração OFF conserva as funções e horários anteriores.

Não ativar nenhum dos antigos crons de WhatsApp, engajamento ou fechamento diário. Não usar `db push`, histórico reparado, limpeza global ou remoção Storage sem versão como alternativa.

## Reversão

Antes de desligar uma limpeza já responsável por mídias aceitas, comprovar que outra versão qualificada continuará cumprindo essas obrigações. Preservar o último artefato qualificado para reimplantar a função se necessário. A opção OFF do worker mantém os antigos callbacks, mas não prova que há quota disponível para executá-los.

`configure_conversation_media_maintenance(false, 'xitugspwfxkcluxvrdeg')` desliga somente o dispatcher desta tarefa e remove somente seu cron identificado. Não apaga os quatro registros de controle nem as obrigações, marcadores, tokens de upload, catálogos ou fatos históricos. Conferir o provedor após qualquer troca.

Sem alteração fixa no plano: há consumo medido das cotas existentes de banco, Edge e Storage. Não afirmar custo zero, quota suficiente ou liberação ao Roberto apenas a partir de testes locais ou de uma função publicada.
