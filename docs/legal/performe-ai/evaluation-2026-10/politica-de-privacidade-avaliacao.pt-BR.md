# Performe AI — Política de Privacidade da avaliação fechada

> **DRAFT — PENDING FACTUAL AND LEGAL REVIEW.**
> Rascunho de trabalho. Não é documento aprovado, não foi publicado, não foi
> aceito por ninguém e não produz efeito. Os trechos marcados `[PENDENTE]`
> dependem de decisão jurídica ou de negócio. Os fatos técnicos foram
> verificados no código em 28/09/2026 (ver `checklist-decisoes.md`).

## 1. Sobre esta avaliação

Esta política descreve como os dados são tratados durante a avaliação fechada
do aplicativo Performe AI, prevista para durar 30 dias a partir de
`[PENDENTE — DATA DE INÍCIO]`.

- Participam somente três pessoas convidadas, cada uma com a sua própria conta.
- O aplicativo é uma versão em desenvolvimento. Ele é instalado diretamente no
  iPhone de cada participante e não está disponível na App Store.
- Os servidores usados são de teste (ambiente de homologação), separados do
  ambiente de produção.

## 2. Quem trata os dados

- Controlador: `[PENDENTE — ENTIDADE JURÍDICA, CNPJ E ENDEREÇO]`.
- Encarregado pelo tratamento de dados pessoais: `[PENDENTE — SE APLICÁVEL]`.
- Canal de contato para esta avaliação: **contato@piperhub.com.br**. O uso
  desse endereço como canal de contato não define, por si só, quem é o
  controlador ou o operador dos dados.

## 3. Dados tratados

### 3.1 Conta
- E-mail e senha. A senha é processada pelo serviço de autenticação (Supabase
  Auth). No iPhone, a sessão fica guardada no Keychain, disponível só com o
  aparelho desbloqueado e sem cópia para outros aparelhos.

### 3.2 Perfil e cadastro inicial
- Nome, idioma, país, fuso horário, sexo, data de nascimento, altura, peso,
  percentual de gordura (opcional), objetivo, nível de atividade, frequência de
  treino, ingestão de água, nível de fome, horário de acordar e de dormir,
  organização da alimentação e estilo preferido do Flow.
- O registro das suas ações sobre os documentos apresentados no cadastro
  (qual documento, versão, idioma e tipo de ação).

### 3.3 Dados de saúde e de rotina (dados pessoais sensíveis)
- Refeições: texto digitado (até 2.000 caracteres), alimentos, quantidades,
  horário e o tipo de refeição.
- Peso, com o instante da medição quando você o informa.
- Hidratação e treinos registrados.
- Rotina e lembretes: categorias, horários e dias. Se você cadastrar itens de
  suplementação ou medicação, o **nome e a dose que você digitar** são
  guardados para exibir a sua rotina.
- Planos de treino e alimentares: os confirmados por você e os rascunhos
  (propostos pelo Flow ou importados de um documento).

Pela Lei Geral de Proteção de Dados (LGPD), dados referentes à saúde são dados
pessoais sensíveis (art. 5º, II).

### 3.4 Fotos, áudios e documentos
- **Fotos de refeição e de plano:** antes do envio, o aplicativo gera uma nova
  imagem JPEG sem os metadados do arquivo original (sem EXIF, sem localização
  GPS e sem dados do aparelho).
- **Áudio gravado no aplicativo:** até 3 minutos.
- **Áudio importado de um arquivo:** enviado como está. `[PENDENTE — os
  metadados do arquivo importado não são removidos nesta versão]`.
- **Documento de plano em PDF:** enviado e guardado como está, inclusive com
  os metadados do arquivo. `[PENDENTE]`
- O texto reconhecido num documento e os trechos que o aplicativo não
  conseguiu classificar ficam guardados junto do rascunho, para você revisar.

### 3.5 Conversas com o Flow
- As mensagens que você envia e as respostas do Flow ficam guardadas no
  histórico da sua conta.
- Os registros de uso do Flow não incluem o texto da conversa.

### 3.6 Biblioteca
- Quais conteúdos foram exibidos, abertos, concluídos ou salvos.

### 3.7 Dados técnicos
- Identificadores de requisição e códigos de erro nos registros do servidor.
  O corpo das requisições não é registrado nos logs.
- Para evitar que uma mesma ação seja gravada duas vezes, a resposta de cada
  operação fica guardada por 24 horas. `[PENDENTE — não foi encontrada a
  rotina que apaga esses registros depois do prazo]`.
- O aplicativo não usa ferramentas de publicidade, de rastreamento, de
  análise de uso de terceiros nem de relatório de falhas.

### 3.8 O que não é coletado
- Localização, contatos, dados do app Saúde (HealthKit) e identificador de
  publicidade.
- O aplicativo não registra o aparelho para notificações remotas nesta
  versão. Os lembretes são agendados no próprio iPhone.

## 4. Para que os dados são usados
- Criar e manter a sua conta.
- Registrar e mostrar a sua alimentação, peso, hidratação, treinos e rotina.
- Calcular o seu dia e o seu progresso no servidor.
- Ler fotos, áudios e documentos para propor registros e planos que você
  revisa e confirma.
- Responder às suas mensagens no Flow.
- Avaliar o funcionamento do aplicativo e corrigir falhas durante a avaliação.

Os dados não são vendidos nem usados para publicidade.

## 5. Bases legais
`[PENDENTE — DEFINIÇÃO JURÍDICA]`. Para dados de saúde, a LGPD admite o
tratamento com consentimento específico e destacado, para finalidades
específicas (art. 11, I), entre outras hipóteses. A escolha da base legal para
cada finalidade depende de revisão jurídica.

## 6. Com quem os dados são compartilhados

Fornecedores de tecnologia que processam dados para o funcionamento do
aplicativo:

| Fornecedor | Para quê | O que recebe |
|---|---|---|
| Supabase | Banco de dados, autenticação e armazenamento de arquivos | Todos os dados da conta |
| Vercel | Hospedagem do servidor do aplicativo | Requisições do aplicativo em trânsito |
| Inngest | Execução de tarefas em segundo plano | Identificadores das tarefas, como o de uma foto a processar |
| OpenRouter | Encaminhamento para modelos de inteligência artificial | Texto da refeição, transcrição de áudio, fotos, documentos de plano e mensagens do Flow |
| Anthropic e Google, via OpenRouter | Modelos de IA: Claude Haiku 4.5 para texto de refeição e estrutura de plano; Gemini 2.5 Flash para fotos; Claude Sonnet 4.6 para rótulos; modelo do Flow definido na configuração | O conteúdo acima, conforme a tarefa |
| Groq | Transcrição de áudio (Whisper) | O áudio da refeição |
| Apple | Exibição dos lembretes agendados no iPhone | Nada é enviado pelo servidor |

`[PENDENTE — o código envia cabeçalhos de um serviço de observabilidade
(Helicone) em algumas chamadas de IA, mas o endereço de destino é o
OpenRouter. Confirmar se esse serviço recebe dados. A importação de documentos
de plano não usa esse serviço.]`

`[PENDENTE — confirmar, com cada fornecedor, a retenção e o uso dos dados
enviados, inclusive se são usados para treinar modelos.]`

## 7. Transferência internacional
`[PENDENTE]`. Os fornecedores de IA acima operam fora do Brasil, e a região
dos servidores de banco e hospedagem não está definida nos arquivos do
projeto. A LGPD só permite a transferência internacional nas hipóteses do
art. 33.

## 8. Por quanto tempo os dados ficam guardados

| Dado | Prazo nesta versão |
|---|---|
| Foto de refeição e áudio | 30 dias; depois a rotina automática apaga o arquivo e o resultado da leitura |
| Documento de plano | Sem exclusão automática; fica até você apagar |
| Registros, planos, conversas e perfil | `[PENDENTE — definir prazo e o destino ao fim da avaliação]` |
| Respostas guardadas para evitar duplicidade | 24 horas previstas; exclusão automática `[PENDENTE]` |

## 9. Seus direitos
Você pode pedir confirmação do tratamento, acesso, correção, anonimização,
bloqueio ou eliminação, portabilidade, informação sobre compartilhamento e
revogação do consentimento, nos termos do art. 18 da LGPD. Os pedidos devem
ser enviados para contato@piperhub.com.br.

**Exclusão de conta:** esta versão **não tem** exclusão de conta dentro do
aplicativo. O pedido é feito pelo e-mail acima. `[PENDENTE — o procedimento
interno ainda precisa cobrir a conta de autenticação, que a rotina automática
atual não apaga.]`

## 10. Segurança
- Comunicação entre aplicativo e servidor por conexão cifrada.
- Arquivos em áreas de armazenamento privadas, acessadas só pelo servidor.
- Cada conta acessa somente os próprios dados.
- Nenhum sistema é totalmente imune a falhas. Em caso de incidente de
  segurança, `[PENDENTE — procedimento de comunicação]`.

## 11. Alterações
Mudanças nesta política durante a avaliação serão comunicadas aos
participantes antes de valer. `[PENDENTE — forma de comunicação]`

Fontes consultadas em 28/09/2026: Lei nº 13.709/2018 (LGPD), no portal do
Planalto; site da Autoridade Nacional de Proteção de Dados (ANPD).
