# Performe AI — Inteligência artificial e permissões do iPhone

> **DRAFT — PENDING FACTUAL AND LEGAL REVIEW.**
> Rascunho de trabalho, não publicado e não aprovado. Os fatos abaixo foram
> verificados no código em 28/09/2026.

## Onde a inteligência artificial é usada

| Função | O que a IA faz | O que você faz |
|---|---|---|
| Registro de refeição por texto | Separa alimentos e quantidades do texto | Revisa e confirma cada item |
| Registro por foto | Identifica alimentos e estima quantidades na imagem | Revisa a origem da quantidade e confirma |
| Registro por áudio | Transcreve o áudio e depois separa os alimentos | Revisa e confirma |
| Foto de rótulo | Lê a tabela nutricional; o valor só é usado se a leitura for clara e completa | Informa quanto consumiu |
| Importação de plano por foto ou PDF | Lê o documento e monta um rascunho | Revisa campos marcados como incertos e confirma ou descarta |
| Flow | Conversa, consulta seus dados oficiais e propõe planos em rascunho | Decide se confirma uma proposta |

## Limites do Flow nesta versão
- Consulta somente: progresso, métricas, resumo de um período e reavaliação.
- Pode criar propostas de plano de treino ou alimentar. Nenhuma ferramenta do
  Flow confirma um plano.
- Uma mensagem no chat não altera dados de saúde.
- Não indica medicamentos, suplementos ou doses. Itens desse tipo num plano
  proposto pelo Flow ficam bloqueados para confirmação. Num documento
  importado, eles aparecem sinalizados e nunca viram dose sugerida.
- Não diagnostica, não promete cura e não se apresenta como profissional.
- Aceita até 4.000 caracteres por mensagem e até 10 mensagens por minuto.
- O cálculo de metas, balanço e progresso é feito pelo servidor, não pela IA.

## Permissões do iPhone

| Permissão | Quando é pedida | Texto exibido pelo iPhone |
|---|---|---|
| Câmera | Ao fotografar uma refeição ou um plano | "O Performe AI usa a câmera para fotografar a refeição que você quer registrar ou o plano que você quer importar." |
| Microfone | Ao gravar a descrição de uma refeição | "O Performe AI usa o microfone para gravar a descrição da refeição que você quer registrar." |
| Notificações | Para agendar os lembretes da rotina | Texto padrão do iOS |
| Fotos | Não é pedida. A escolha de imagens usa o seletor do sistema, que entrega ao aplicativo só a imagem escolhida | — |

Se você negar a câmera ou o microfone, o aplicativo avisa "Permissão negada.
Autorize o acesso nos Ajustes do iPhone." Os outros meios de registro (texto,
foto da galeria e áudio importado) são opções separadas e continuam
disponíveis. `[PENDENTE — confirmar negar e conceder no iPhone físico]`
As permissões podem ser mudadas a qualquer momento nos Ajustes do iPhone.

O aplicativo não pede localização, contatos, reconhecimento de fala do
sistema, dados do app Saúde nem autorização de rastreamento.
