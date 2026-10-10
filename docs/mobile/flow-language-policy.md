# Flow — cartão de linguagem C2

Implementação local de 08/10/2026. Não equivale a publicação, aceite de redação,
validação clínica ou prova de obediência de um modelo real.

## Composição e limites

Somente `processAuthenticatedMessage` / `historyProvider: mobile_flow` usa
`flow-language-policy.ts`. O caminho legado `processMessage` continua com o
loader, regras, consultas, tools e prompts anteriores. Não há alteração de API,
banco, cálculo, preferência persistida, histórico, confirmação ou app iOS.

- Base C8: 2.348 caracteres UTF-16, cabeçalho e separador de fase incluídos, limite de 2.700.
- Fase: apenas o nome do objetivo atual registrado; enum ausente/desconhecido
  não ganha objetivo presumido. Não é decisão de elegibilidade ou troca de fase.
- Situação: anti-repetição somente com saída de assistant no histórico já
  carregado; até 200 caracteres no total, sem copiar falas para essa camada.
- Nota de botão: ausente. O contrato autenticado recebe texto e não prova sua
  origem. Sugestões da interface não autorizam ação nem criam uma nota especial.
- Base/fase vão no prefixo estável. A situação e a preferência C9 permanecem
  variáveis. Focus/Impulse/Zen alteram somente o tom; fatos e confirmações ficam.

A policy de identidade, segurança, rascunhos, confirmação e métricas C1 continua
integral. Os cards não criam agendas, fotos, avisos, resets, comemorações,
registros, ajustes clínicos, promessas de eficácia ou recompensas obrigatórias.

## Leitura e projeção das seis regras conferidas

Fonte: seis `agent_rules` ativas `regras_gerais` do staging
`xitugspwfxkcluxvrdeg`, consultadas sob autorização explícita em 08/10/2026;
fixture interna `c2-staging-reviewed-general-rules-20261008.json` contém essas
versões sem dados de paciente. Os três parâmetros `calc` lidos não autorizam
regras clínicas novas e não entram no cartão.

O Flow continua com duas leituras: config/view e regras. A segunda também traz
slug/tipo para validar tuplas **antes de agregar texto**. Só aplica C2 quando
encontra cada uma das seis versões exatamente uma vez, sem geral desconhecida
ou row malformada. SHA-256 UTF-8 de
`JSON.stringify([slug,tipo,language,topic,content])`, sem normalização. Regras da
fase são preservadas e filtradas pelo idioma como antes, incluindo citações e
separadores dentro do próprio conteúdo.

Se todas as gerais conferidas forem projetadas e não restar regra de fase,
`systemPrompt: ''` é válido: o fallback da view não pode reintroduzi-las.
Com drift/duplicata/ausência/geral nova/falha de leitura, C2 fica **unapplied**:
preserva a composição anterior com as mesmas rows ou a view já lida, sem terceira
consulta; não adiciona base/fase/situação C2. O diagnóstico
`language_card_unapplied` tem somente código, protegido contra falha do logger.
Rejeição da consulta continua sendo erro do turno, como no loader anterior.
Essa compatibilidade não afirma que regras novas estejam adaptadas: exigem nova
revisão explícita, não atualização automática do fingerprint.

| Regra conferida | Destino no Flow |
| --- | --- |
| Persona master | Clareza, acolhimento, cadência e vocativo no cartão; identidade e limites na policy. Credencial profissional, WhatsApp e exemplos de ajuste/foto não importados. |
| Quando mostrar balanço diário | Dados oficiais pertinentes ao pedido/evento confirmado. Abertura automática às06h pertence a mecanismo próprio, não à linguagem. |
| Confirmação de país de residência | Cadastro/localização e contexto existentes; sem DDI, coleta pelo chat ou tool de escrita indisponível. |
| Saudações variadas | Base + situação com histórico; variedade não garante unicidade infinita da sessão. |
| Idioma da resposta | Instrução vigente de idioma/contexto preservada; sem persona profissional definida pelo país ou exposição de fórmulas. |
| Decisões devem ser confirmadas | Policy e fluxos estruturados; não importar exceção histórica de gravação incremental no onboarding ou estimativa por foto. |

## Mapa da regra Linguagem

Fonte original: 12.245 caracteres; SHA-256
`c4ca4372f1ede2afea92f09b3ff3ad1b1d1e79d79d385de8cc98e113d79d72dc`.
A redação preserva os 24 itens principais e os sete subitens de1.3; condutas
continuam nos mecanismos/pacotes correspondentes, não como comandos gerais.

| Item | Redação do cartão | Conduta/mecanismo separado |
| --- | --- | --- |
| 1.1 | Clareza, acolhimento, firmeza e cadência | Sem identidade profissional |
| 1.2 | Dados oficiais, próximo passo real | Protocolos/metas existentes |
| 1.3a | Conquista confirmada | C5/C13/C17/C51 |
| 1.3b | Contas prontas, escolhas válidas | C7/C13 |
| 1.3c | Capacidade com fatos reais | Sem rótulo disciplinado |
| 1.3d | Próximo passo possível | C6/C25/C47 |
| 1.3e | Escolha, decisão e apoio | Sem retaguarda humana inventada |
| 1.3f | Acolhimento pós-dificuldade | Sem punição/compensação |
| 1.3g | Alternativas reais | C36/C39/C40 |
| 1.4 | Quatro proibições explícitas | Sem transferir cálculos, moralizar, jargão ou terrorismo |
| 1.5 | Tom claro, idioma e limites | Sem credencial ou eficácia neurocientífica |
| 1.6 | Apoio com fatos/contexto | Sem prometer resultado |
| 2.1 | Elogio após confirmação | C5/C13/C17/C51 |
| 2.2 | Escolhas compatíveis | C36–C40 e revisão/confirmar |
| 2.3 | Apoio sem rótulos | Não inferir identidade disciplinada |
| 2.4 | Próximo passo do plano | C6/C25/C47, sem faixas novas |
| 2.5 | Escolha e autonomia | Sem retaguarda inventada |
| 2.6 | Linguagem de próximos passos reais | C15/C45/C46 |
| 2.7 | Variedade contextual | C5; sem unicidade infinita |
| 2.8 | Acolhimento sem culpa | Sem compensação/apagamento |
| 2.9 | Eventos reais explicados | C15/C16/C45/C46 |
| 2.10 | Distinguir medida/estimativa/possibilidade | C6/C25/C26 |
| 2.11 | Metáforas curtas | Sem confundir com fato |
| 2.12 | Frases curtas, uma ideia | Sem carga desnecessária |
| 2.13 | A/B quando válido | Relatos/alergias/dado ausente permitem pergunta aberta |
| 2.14 | Compromisso existente no contexto | C45/C46/C47 |
| 2.15 | Marco confirmado explicado | C3/C17/C18, sem reset/perda prometidos |
| 2.16 | Resumo factual | C52 e reavaliações |
| 2.17 | Flexibilidade sem culpa | Percentual10–15% fora; decisão clínica pendente |
| 2.18 | Convite já confirmado | C20–C24/C55; não criar frequência15dias |

As regras “pergunta específica” e “antes de enviar perguntas automáticas” entram
somente por pertinência, uma pergunta necessária e números oficiais. Checklist
clínico, EPOC, meta de bloco, fotos, treino, comparações e lembretes não são
importados integralmente para C2.

## Nomes públicos e verificação

`Usina muscular` e variantes explícitas de caixa, espaços/NBSP e hífen entram
no vocabulário fechado de `flow-public-names.ts`, projetadas para `Performe AI`.
Termos isolados, nomes de pessoas, URLs/paths/identificadores são preservados
pelos guardas. O account guard continua protegendo o nome da pessoa. Limites
antigos das outras grafias, já declarados nos goldens anteriores, não foram
reclassificados como corrigidos.

A expressão nova aceita a interrogação de prosa (`Usina muscular?`) e protege
intervalos completos de URLs, inclusive query com parênteses e âncora com
dois-pontos, apóstrofos e destinos relativos de links. Esses intervalos são
identificados no texto original antes das projeções antigas, que podem mudar
offsets ou inserir espaços. A proteção pertence somente a essa expressão;
não altera os limites legados das outras projeções.

O golden `audit-10-08-flow-language-policy.test.ts` usa entrada real do pipeline
com conta/dados sintéticos e modelo roteirizado. O golden
`audit-10-08-flow-usina-public-name.test.ts` cobre a projeção determinística dos
nomes. Cobrem payload, versões, fallback,
fase, limites, prefixo/cache, C9/locale e nomes. Locks de números/histórico e
WhatsApp continuam próprios. Tom/qualidade do modelo real, aceite de redação,
persistência/QA no staging e entrega completa dos protocolos não são provados
por esses testes locais.

## C8 — capacidades atuais e definições educativas

A pergunta inteira “O que você faz?” ou “O que você pode fazer?”, e suas
versões inglesas “What do you do?” / “What can you do?”, recebe uma resposta
estática no idioma da própria pergunta. Acentos, caixa, espaços e pontuação
final .!? são normalizados; relato, sintoma, alergia, instrução ou segunda
pergunta seguem completos no caminho normal. A entrada autenticada continua
passando pelos gates de assinatura, conta, prompt e meia-noite local. O retorno
puro não chama modelo, router ou tool, não faz touch de atividade e não altera
preferências ou saúde. O legado `processMessage`, inclusive com provider
`mobile_flow` declarado no input, não ativa essa resposta.

`flow-capabilities.ts` conserva as 11 famílias da origem, com apenas seis
anunciadas. Recursos parciais não habilitam a promessa de uma família inteira.

| Família anunciada | Implementação e limite |
| --- | --- |
| 1 — Estimativas/metas oficiais | `consulta_metricas` / `renderOfficialTargets`; somente dados disponíveis, sem criar ou mudar meta. |
| 2 — Refeição por texto/foto | `MobileMealDraftRepository` / `MealDraftModel` em Registrar; mídia requer disponibilidade e permissão; revisar e confirmar antes de registrar. |
| 3 — Balanço/resumo do dia | `loadOfficialDailyState` / `renderFlowDayStatus`; registros confirmados e valores oficiais; exercício não aumenta comida restante. |
| 4 — Cardápio | `propoe_plano_dieta` / `confirmPlanDraft`; rascunho em Plano com preferências/restrições; confirmar plano não registra consumo. |
| 8 — Treino | `propoe_plano_treino`; rascunho com dias/equipamentos/nível informados, revisão e confirmação; não registra execução. Desde 2026-10-10 os textos da sugestão são gravados em linguagem simples (vocabulário fechado, números e estrutura intactos, só no Flow): `docs/mobile/api-v1.md`, "Linguagem simples na sugestão de treino do Flow". |
| 9 — Educação no chat | `processAuthenticatedMessage`; assistente de IA, sem substituir avaliação profissional, diagnóstico ou tratamento. |

Receitas completas (5), gordura corporal por foto (6), transições automáticas
(7), relatórios amplos com ajuste automático (10) e dicas proativas (11) ficam
fora dessa lista pública.

HIIT, proteína e EPOC entram uma vez no cartão estável C2, somente com as seis
tuplas conferidas e o canal autenticado. A base foi condensada conservando as
12 obrigações, a linha de quatro proibições, os digests, o fallback integral e
os cartões de fase/situação. A distribuição de proteína em 3–5 refeições é
texto educativo do método, não prescrição individual ou obrigação universal.
EPOC não adiciona uma parcela ao balanço, muda fórmula ou libera calorias.

O golden `audit-10-09-flow-capabilities.test.ts` exercita as entradas reais com
DB/modelo externos sintéticos: perguntas puras/mistas, idioma oposto ao perfil,
A→B→A, isolamento do legado, gates, autorização de tools, regras desconhecidas,
limites UTF-16 e preservação dos valores oficiais. Não prova obediência de um
modelo vivo, persistência no staging ou aceite clínico.

> RC C8 — cenário EPOC variante contado no balanço NÃO coberta nesta PR (pendência da audit 2026-10-07).
