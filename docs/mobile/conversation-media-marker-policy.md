# Marcadores técnicos de mídia conversacional

Estado: política aprovada expressamente pelo responsável em 13/11/2026.
O aceite não comprova implementação, descarte conectado ou prontidão de release.

## Limite de implantação aprovado em R124

O responsável aprovou preservar as mídias antigas de staging e habilitar a
limpeza automática somente para novas mídias do fluxo qualificado. O banco fixa
um instante de corte e registra a identidade técnica do arquivo quando a nova
autorização de upload é preparada. Arquivo e autorização precisam ser posteriores
ao corte; repetir uma autorização de arquivo antigo não muda sua classificação.

A seleção automática exige essa origem para inscrever ou revisitar uma dívida.
Uma resposta atrasada de upload antigo registra a validade da autorização, sem
apagar seu catálogo ou alterar sua dívida. A exclusão automática de uma conta
com mídia antiga preservada permanece pendente, inclusive quando só resta a
dívida independente. Contas com apenas mídias novas continuam pela verificação
de descarte e barreiras existentes. Não ampliar essa proteção temporária de
staging para uma política permanente de retenção de clientes sem nova decisão.

Esse corte não ativa o agendador, não altera o descarte explícito solicitado
pela pessoa e não comprova a drenagem dos emissores/removers antigos. As regras
clínicas das reavaliações permanecem separadas.

## Conteúdo e finalidade

Fotos e áudios reais continuam sujeitos ao descarte vigente. Ao concluir o
descarte, o conteúdo original e o resultado de processamento devem ser removidos
do catálogo. Pode permanecer no mesmo caminho privado um objeto comum de zero
bytes, acompanhado apenas dos identificadores e estados técnicos mínimos para
impedir que uma autorização antiga recrie o conteúdo apagado.

O marcador não contém imagem, som ou texto. Seus identificadores internos são
pseudônimos, não anônimos. Não pode ser apresentado como mídia disponível, galeria
histórica ou exclusão física completa de todos os metadados. Recibos, números e
auditoria continuam sujeitos às regras de histórico próprias; este aceite não
amplia a retenção de conteúdo nem autoriza cópias adicionais.

## Prazo e proteção

O marcador técnico pode permanecer sem prazo fixo enquanto versões, emissores ou
autorizações antigas puderem atingir aquele caminho. A obrigação técnica de
descarte deve sobreviver à exclusão do catálogo e da conta. Uma inspeção de zero
bytes não prova o encerramento dessas autorizações.

Antes de tratar a proteção como estável, qualificar os emissores e os removers
antigos, inclusive operações em andamento. Uma remoção antiga sem versão não pode
apagar a barreira e permitir que um upload tardio volte a conservar conteúdo.
Erros ou resultados incertos preservam a obrigação; não contam como encerramento.

Remover o marcador e seus resíduos somente depois de comprovar que não há mais
dependência das versões anteriores e que as autorizações e invocações terminaram.
Não remover versões ou serviços clínicos para forçar esse resultado.

## Custo e operação

Usar o Storage e o banco existentes, sem novo serviço ou plano. Observar contagem
de marcadores, visitas de limpeza e uso das cotas atuais. Não declarar custo zero
para operações ou metadados. A limpeza deve ser limitada, com seleção justa e sem
loop de revarredura de marcadores já protegidos; qualquer ativação exige teste da
composição real, além dos testes locais.

## Separação clínica e aceite

Esta política cobre somente mídia conversacional comum. Não altera a retenção de
fotos clínicas de reavaliação, seus consentimentos, prazo de 24 horas ou descarte
ao concluir/descartar. Não altera regras de cálculo, fatos, XP ou consentimento
social. Foto, áudio, exclusão de conta, desempenho, app nativo e distribuição
continuam exigindo suas próprias evidências de QA.

O aceite foi registrado em `TECHNICAL-MARKER-POLICY-ACCEPTED.json` do incremento
R114, vinculado pelo hash à minuta apresentada e à resposta explícita do usuário.

## Caracterização conectada R115

Em 13/11/2026, um único áudio sintético de oito bytes na QA de staging percorreu
emissão real da autorização, descarte pelo app, remoção antiga sem versão do
marcador e envio atrasado pela autorização original. O Storage aceitou esse envio.
Repetir o descarte pela API atual removeu os bytes recriados e restaurou o objeto
de zero bytes; catálogo apagado, resultado nulo, dívida preservada e lease
liberado foram conferidos no banco. Nenhuma refeição, treino ou intake foi criado.

A remoção antiga foi reproduzida por diagnóstico efêmero autenticado, limitado à
sessão e ao asset próprios, posteriormente excluído e conferido como ausente no
provedor. Isso comprova a recuperação pelo descarte explícito, não a execução
agendada nem a drenagem de todos os emissores/removers antigos. O gate R105-REVIEW-1
permanece aberto. A composição real do worker e as operações em andamento ainda
precisam de qualificação antes da liberação de foto/áudio.

Para repetir esse diagnóstico, o SDK Storage instalado expõe o tamanho em
`info().data.size` (`FileObjectV2`), não em `data.metadata.size`. O primeiro
diagnóstico recusou a operação por essa diferença, sem remover o marcador; a
correção tem regressão específica. Os dois Previews auxiliares foram removidos.

## Caracterização conectada R132 — upload retomável

Em 14/11/2026, dois novos arquivos sintéticos de oito bytes da QA de staging
receberam autorizações reais do app, com `upsert: false`. Nenhum processamento
por IA, alimento, treino ou intake foi solicitado nessa rodada.

- Uma sessão TUS aberta antes do descarte retornou `409` ao tentar concluir o
  envio depois da instalação da barreira. O objeto continuou com zero bytes e
  a mesma versão.
- Recriar uma sessão assinada com `x-upsert: true` também terminou em `409`:
  o cabeçalho não permitiu sobrescrever a barreira com aquela autorização.
- Um envio interrompido deixou quatro bytes confirmados pelo `HEAD` do TUS.
  Depois do descarte, retomar a partir do offset quatro foi recusado em `409`.
  A tentativa de manter a primeira conexão aberta sofreu `BrokenPipe`; essa
  observação foi preservada, sem presumir em qual etapa interna o servidor estava.
- A tentativa direta, apenas com o JWT da QA e sem assinatura de upload, foi
  recusada pela política de linha em `403`. As três sessões assinadas admitidas
  terminaram com `HEAD 404`; os dois catálogos ficaram apagados, resultados nulos,
  dívidas preservadas e objetos comuns de zero bytes com suas versões intactas.

A rota TUS assinada observada usa `/storage/v1/upload/resumable/sign`; adicionar
`x-signature` à rota comum não a transforma na rota assinada. A primeira chamada
à rota comum foi recusada antes de admitir uma sessão. Referências primárias:
[uploads retomáveis](https://supabase.com/docs/guides/storage/uploads/resumable-uploads)
e [seleção das rotas e assinatura](https://github.com/supabase/storage/blob/master/src/http/routes/tus/index.ts).
O código público auxilia o diagnóstico; não identifica a revisão hospedada.

Os hashes das 69 mídias anteriores ao corte e das oito autorizações e oito
dívidas antigas preservadas permaneceram iguais aos de referência. A sessão Auth original foi preservada;
apenas a nova sessão e a autorização temporária da QA foram encerradas. As
capacidades locais de upload foram removidas dos artefatos após a conferência.

Isso qualifica esses casos reais de retomada e preservação de barreira, não uma
drenagem global de todos os emissores/removers antigos, nem a remoção física de
resíduos internos do fornecedor. A composição com remoção antiga em andamento
e reparação agendada continua separada; R105-REVIEW-1 e a liberação multimodal
permanecem abertos. Não há alteração de política, bucket, chave ou regra clínica.

## Caracterização conectada R133 — remoção antiga e reparação pelo worker

Em 14/11/2026, um novo áudio fictício de oito bytes da QA recebeu uma autorização
real do app. As funções de exclusão, leitura e atualização do catálogo e remoção
Storage foram extraídas, sem alteração dos seus corpos, do commit antigo
`71d1322e313356ed688775c36cf84f3fbb90cc5c`. Um adaptador diagnóstico local usou o
SDK existente e o banco/Storage de staging, limitados à identidade e ao caminho
desse único arquivo. A leitura antiga foi suspensa depois de observar
`pending_upload`; a API atual então apagou o catálogo e instalou a barreira vazia.

Ao retomar, a remoção antiga sem versão apagou a barreira. Sua atualização de
catálogo recusou o registro já apagado, como previsto pelo filtro antigo. Mesmo
assim, a autorização original de upload ainda permitiu recriar oito bytes no
Storage. A obrigação independente de descarte permaneceu presente.

Uma única invocação manual pela interface oficial da função registrada
`conversation-media-retention-cleanup`, no ambiente `performe-staging`, concluiu
às 17:00:37 UTC. O run `01M7DG1XEP09MRXG3ZKXRVC26A` retornou `swept: 8` e
`issuanceDrain: not_qualified`. São oito obrigações visitadas, não oito arquivos
com conteúdo apagados. A inspeção posterior encontrou o arquivo novo com zero
bytes e nova versão, a dívida preservada e o catálogo apagado com resultado nulo.
Repetir o mesmo upload original retornou `400 Duplicate` e preservou a barreira.

As 69 mídias, oito autorizações e oito dívidas anteriores ao corte mantiveram os
hashes de referência. O áudio antigo de origem incerta continuou com 84.644 bytes
e a mesma versão. Perfil, refeições, treinos, intakes, permissões anteriores e a
sessão original da QA permaneceram inalterados. A permissão e a sessão temporárias
foram encerradas; a cópia local da chave existente e as capacidades locais de
upload foram removidas. Não houve criação ou rotação de chave.

Essa rodada comprova a composição reproduzida com corpos antigos e reparação
pelo worker real registrado. A suspensão ocorreu no adaptador diagnóstico local,
não dentro de uma Function antiga implantada. O acionamento foi manual; não é uma
nova prova do disparo por horário. A drenagem global dos emissores/removers e o
ciclo completo de exclusão de conta continuam abertos, assim como R105-REVIEW-1.
Não houve nova implantação, alteração do agendamento ou liberação multimodal.
