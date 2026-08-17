# Relatorio de Precificacao e Economia Unitaria do Aplicativo Nativo

**Data-base:** 16 de julho de 2026
**Mercados:** Brasil e Estados Unidos
**Canal considerado:** aplicativo nativo iOS/Android, com compras e assinaturas dentro do app
**Fora do calculo:** WhatsApp Cloud e Stripe para compras realizadas dentro das lojas

## 1. Resumo executivo

O produto pode ter uma economia unitaria positiva, mas **nao com o custo de IA observado hoje**.

Nos ultimos 30 dias, a telemetria interna registrou US$ 68,68 de custo de LLM para tres usuarios ativos, ou **US$ 22,89 por usuario/mes**. A projecao dos sete dias mais recentes ficou em US$ 20,97 por usuario/mes. A amostra e pequena e representa usuarios intensivos, mas o custo rastreado, sozinho, ja inviabiliza os precos de entrada discutidos anteriormente.

O cenario sustentavel deste relatorio depende de reduzir o custo variavel total de tecnologia para **US$ 4,00 por usuario ativo/mes**, composto por:

- US$ 3,50 para LLM, visao, OCR e transcricao;
- US$ 0,50 para overages de banco, storage, filas, observabilidade e entrega de notificacoes;
- custos fixos de infraestrutura calculados separadamente.

Essa reducao de aproximadamente 82% em relacao ao custo rastreado atual **ainda nao foi comprovada**. Portanto, os resultados positivos das tabelas sao uma meta de operacao, e nao o retrato financeiro atual.

## 2. Precos de venda usados no modelo

### Brasil

| Plano | Preco cobrado | Equivalente mensal | Desconto contra 12 mensalidades |
|---|---:|---:|---:|
| Mensal | R$ 89,90 | R$ 89,90 | 0% |
| Trimestral | R$ 249,90 | R$ 83,30 | 7,3% |
| Semestral | R$ 449,90 | R$ 74,98 | 16,6% |
| Anual | R$ 799,90 | R$ 66,66 | 25,9% |

### Estados Unidos

| Plano | Preco cobrado | Equivalente mensal | Desconto contra 12 mensalidades |
|---|---:|---:|---:|
| Mensal | US$ 29,99 | US$ 29,99 | 0% |
| Trimestral | US$ 84,99 | US$ 28,33 | 5,5% |
| Semestral | US$ 159,99 | US$ 26,67 | 11,1% |
| Anual | US$ 239,99 | US$ 20,00 | 33,3% |

Esses precos sao uma proposta financeira condicionada ao custo-alvo. A aceitacao comercial precisa ser validada com paywall A/B, conversao, churn e entrevistas; ela nao pode ser concluida apenas pela planilha.

## 3. Custos e reducoes disponiveis

### 3.1 Apple App Store

- Comissao padrao sobre bens e servicos digitais: pode chegar a 30%.
- App Store Small Business Program: **15%** para desenvolvedores elegiveis com ate US$ 1 milhao em proceeds no ano anterior, considerando contas associadas.
- Ao ultrapassar o limite durante o ano, a taxa padrao passa a valer para vendas futuras, conforme as regras do programa.
- Apple Developer Program: **US$ 99 por ano**.
- A reducao de 30% para 15% economiza 15 pontos percentuais da receita bruta vendida pela App Store.

Fonte: [Apple App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) e [Apple Developer Program](https://developer.apple.com/programs/enroll/).

### 3.2 Google Play

- Assinaturas com renovacao automatica: **15%**.
- Para assinaturas, os 15% ja sao a taxa aplicavel no modelo considerado; nao foi aplicada uma segunda reducao de pequeno negocio.
- Conta de desenvolvedor com distribuicao completa: **US$ 25, pagamento unico**.

Fonte: [Google Play service fees](https://support.google.com/googleplay/android-developer/answer/112622?hl=en-GB) e [Google Play developer registration](https://support.google.com/android-developer-console/answer/16640817?hl=en).

### 3.3 RevenueCat

- Gratuito ate **US$ 2.500 de Monthly Tracked Revenue (MTR)**.
- Ao atingir o limite, cobra **1% de toda a receita monitorada no mes**, e nao apenas do excedente.
- No mix deste relatorio, o limite equivale a aproximadamente 96 assinantes americanos ou 175 brasileiros, se cada mercado fosse operado isoladamente.
- Na pratica, a RevenueCat soma a receita rastreada pelo projeto. Se Brasil e EUA estiverem na mesma conta, o limite sera atingido pela receita combinada.

Fonte: [RevenueCat pricing](https://www.revenuecat.com/pricing).

### 3.4 Infraestrutura fixa de referencia

| Componente | Custo mensal considerado | Reducao/faixa gratuita |
|---|---:|---|
| Vercel Pro | US$ 20,00 | Hobby e gratuito, mas nao e o plano indicado para operacao comercial |
| Supabase Pro | US$ 25,00 | Free disponivel para desenvolvimento; Pro inclui o primeiro projeto e creditos de compute |
| Inngest Pro | US$ 99,00 | Hobby inclui 50 mil executions e 5 execucoes concorrentes |
| Apple Developer | US$ 8,25 | Equivalente mensal de US$ 99/ano |
| Google Play | US$ 2,08 | Amortizacao no primeiro ano do pagamento unico de US$ 25 |
| **Total fixo de referencia** | **US$ 154,33/mes** | Antes de overages e ferramentas adicionais |

No cambio de planejamento de R$ 5,50/US$, o total fixo equivale a **R$ 848,83/mes**.

Fontes: [Vercel pricing](https://vercel.com/pricing), [Supabase pricing](https://supabase.com/pricing) e [Inngest pricing](https://www.inngest.com/pricing).

O valor nao inclui dominio, email corporativo, suporte premium, MMP/atribuicao, ferramentas juridicas, contabilidade, folha de pagamento ou equipamentos. Esses itens dependem de contratos e estrutura ainda nao informados.

### 3.5 OpenRouter e modelos de IA

- O OpenRouter informa que repassa o preco do provedor sem markup de inferencia.
- A compra de creditos no pay-as-you-go tem taxa de **5,5%**, com minimo de US$ 0,80.
- A meta de US$ 3,50 de IA por usuario deste relatorio deve incluir essa taxa.

Fonte: [OpenRouter FAQ](https://openrouter.ai/docs/faq).

### 3.6 Reembolsos

Foi usada uma reserva de **4% da receita bruta**. O State of Subscription Apps 2026 da RevenueCat reporta mediana de 4,2% de reembolso para apps com IA. A reserva nao significa que o produto necessariamente tera essa taxa.

Fonte: [RevenueCat State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps-2026-utilities).

### 3.7 CAC

Nao existem campanhas pagas historicas suficientes no projeto para comprovar o CAC. O relatorio usa apenas premissas de planejamento:

- Brasil: **R$ 80 por novo assinante pagante**;
- Estados Unidos: **US$ 60 por novo assinante pagante**;
- para a projecao mensal por volume, o CAC foi distribuido por 12 meses: R$ 6,67 ou US$ 5,00 por assinante/mes.

O CAC real deve incluir midia, criativos, agencia/equipe, influenciadores, comissoes, ferramentas de atribuicao e a parcela de usuarios que instala ou inicia trial, mas nao paga. Como referencia de risco, a RevenueCat informa conversao mediana de apenas 2,9% de download para pagante em Health & Fitness. Isso pode tornar o CAC de midia paga significativamente maior que a premissa.

### 3.8 Suporte e operacao

Foi reservada uma verba equivalente a **5% da receita bruta** para atendimento, operacoes, manutencao e perdas nao classificadas. Essa reserva nao substitui a folha real; salarios e pro-labore sao tratados na analise de break-even.

## 4. Tributacao

### 4.1 Brasil

Software e licenciamento podem ser tributados pelo Anexo III ou V do Simples Nacional, conforme o Fator R:

- Fator R igual ou superior a 28%: Anexo III;
- Fator R inferior a 28%: Anexo V.

Fonte: [Receita Federal sobre o Fator R](https://www8.receita.fazenda.gov.br/simplesnacional/Noticias/NoticiaCompleta.aspx?id=415ad600-7d43-4e55-971b-55df99e95ef3), [Anexo III](https://normas.receita.fazenda.gov.br/sijut2consulta/anexoOutros.action?idArquivoBinario=48432) e [Anexo V](https://normas.receita.fazenda.gov.br/sijut2consulta/anexoOutros.action?idArquivoBinario=48434).

O Fator R nao e um desconto gratuito: para atingir 28%, a empresa precisa ter folha e encargos compativeis. A decisao deve considerar o custo total da folha, nao apenas a reducao do DAS.

Em 2026 ha transicao da reforma tributaria. Para 2027, empresas do Simples terao decisoes adicionais sobre IBS/CBS. O modelo deve ser revisado com contador antes do lancamento e novamente antes de 2027. Fonte: [Receita Federal, orientacoes 2026](https://www.gov.br/receitafederal/pt-br/acesso-a-informacao/acoes-e-programas/programas-e-atividades/reforma-tributaria-do-consumo/orientacoes-2026).

### 4.2 Estados Unidos

Nao e possivel calcular o imposto definitivo sem definir:

- se a venda sera feita por CNPJ brasileiro, LLC ou C-Corp;
- estado de constituicao e nexus;
- tratamento das remessas e do cambio;
- quem reconhece a receita e quais despesas sao dedutiveis.

Para comparacao, as tabelas americanas mostram uma **provisao gerencial de 10% da receita bruta**, mas ela nao representa uma aliquota legal confirmada. Uma C-Corp americana tem imposto federal de 21% sobre lucro tributavel, alem de possiveis impostos estaduais. Fonte: [IRS Publication 542](https://www.irs.gov/publications/p542).

## 5. Economia unitaria por plano

Para tornar os planos comparaveis, esta secao usa o cenario gerencial padrao:

- App Store/Play Store: 15%;
- RevenueCat: 1%;
- reembolsos: 4%;
- suporte e operacao: 5%;
- provisao tributaria: 10%;
- tecnologia variavel: US$ 4/usuario/mes, ou R$ 22 no cambio adotado;
- CAC: R$ 80 ou US$ 60.

O resultado abaixo e margem de contribuicao, nao lucro contabil.

### Brasil

| Plano | Contribuicao mensal com CAC diluido em 12 meses | Primeiro contrato, descontando CAC integral | Renovacao do mesmo plano, sem novo CAC |
|---|---:|---:|---:|
| Mensal | R$ 29,77 | **-R$ 43,56** | R$ 36,44 |
| Trimestral | R$ 25,48 | R$ 16,44 | R$ 96,44 |
| Semestral | R$ 20,07 | R$ 80,44 | R$ 160,44 |
| Anual | R$ 14,66 | R$ 175,94 | R$ 255,94 |

### Estados Unidos

| Plano | Contribuicao mensal com CAC diluido em 12 meses | Primeiro contrato, descontando CAC integral | Renovacao do mesmo plano, sem novo CAC |
|---|---:|---:|---:|
| Mensal | US$ 10,49 | **-US$ 44,51** | US$ 15,49 |
| Trimestral | US$ 9,41 | **-US$ 16,76** | US$ 43,24 |
| Semestral | US$ 8,33 | US$ 19,99 | US$ 79,99 |
| Anual | US$ 4,00 | US$ 47,99 | US$ 107,99 |

O plano mensal pode perder dinheiro na primeira cobranca porque o CAC e reconhecido integralmente. Ele so funciona se a retencao permitir recuperar esse investimento nas renovacoes.

## 6. Premissa de mix para as projecoes de volume

Nao existe historico comercial para comprovar a distribuicao dos planos. Foi usado um mix **apenas ilustrativo**:

- 30% mensal;
- 20% trimestral;
- 20% semestral;
- 30% anual.

Esse mix produz receita media mensal equivalente de:

- **R$ 78,62 por assinante no Brasil**;
- **US$ 26,00 por assinante nos Estados Unidos**.

## 7. Projecao por volume: Brasil

### 7.1 Custos mensais antes do DAS

**Receita e custos percentuais**

| Assinantes | Receita bruta | Lojas 15% | Reembolsos 4% | Suporte 5% | RevenueCat |
|---:|---:|---:|---:|---:|---:|
| 100 | R$ 7.862 | R$ 1.179 | R$ 315 | R$ 393 | R$ 0 |
| 500 | R$ 39.312 | R$ 5.897 | R$ 1.572 | R$ 1.966 | R$ 393 |
| 1.000 | R$ 78.624 | R$ 11.794 | R$ 3.145 | R$ 3.931 | R$ 786 |
| 5.000 | R$ 393.120 | R$ 58.968 | R$ 15.725 | R$ 19.656 | R$ 3.931 |
| 10.000 | R$ 786.240 | R$ 117.936 | R$ 31.450 | R$ 39.312 | R$ 7.862 |

**Tecnologia, aquisicao e resultado**

| Assinantes | Tecnologia | CAC diluido | Infra fixa | Resultado antes do DAS |
|---:|---:|---:|---:|---:|
| 100 | R$ 2.200 | R$ 667 | R$ 849 | R$ 2.260 |
| 500 | R$ 11.000 | R$ 3.333 | R$ 849 | R$ 14.302 |
| 1.000 | R$ 22.000 | R$ 6.667 | R$ 849 | R$ 29.453 |
| 5.000 | R$ 110.000 | R$ 33.333 | R$ 849 | R$ 150.658 |
| 10.000 | R$ 220.000 | R$ 66.667 | R$ 849 | R$ 302.165 |

### 7.2 Resultado depois do Simples Nacional

| Assinantes | Receita anualizada | Aliquota efetiva Anexo III | Sobra Anexo III | Aliquota efetiva Anexo V | Sobra Anexo V |
|---:|---:|---:|---:|---:|---:|
| 100 | R$ 94.349 | 6,00% | **R$ 1.788/mes** | 15,50% | **R$ 1.041/mes** |
| 500 | R$ 471.744 | 9,76% | **R$ 10.465/mes** | 17,40% | **R$ 7.461/mes** |
| 1.000 | R$ 943.488 | 12,22% | **R$ 19.843/mes** | 18,69% | **R$ 14.760/mes** |
| 5.000 | R$ 4.717.440 | Acima do sublimite de ISS | Nao calculado | Acima do sublimite de ISS | Nao calculado |
| 10.000 | R$ 9.434.880 | Fora do Simples | Nao calculado | Fora do Simples | Nao calculado |

Em 2026, o sublimite nacional para recolhimento de ISS dentro do Simples e R$ 3,6 milhoes. Com 5.000 assinantes, o faturamento anualizado ultrapassa esse sublimite e ainda fica muito proximo do teto geral de R$ 4,8 milhoes. O ISS pode precisar ser recolhido fora do DAS, por isso o relatorio nao apresenta uma sobra final sem municipio, CNAE e tratamento contabil definidos. Com 10.000 assinantes, o teto geral tambem e ultrapassado e a empresa precisa ser modelada em outro regime.

Fonte do sublimite: [Comite Gestor do Simples Nacional, sublimite para 2026](https://www8.receita.fazenda.gov.br/simplesnacional/noticias/NoticiaCompleta.aspx%3Fid%3D94c10cc2-7eb5-4ef0-bfb2-5479e72caff8).

## 8. Projecao por volume: Estados Unidos

**Receita e custos percentuais**

| Assinantes | Receita bruta | Lojas 15% | Reembolsos 4% | Suporte 5% | RevenueCat |
|---:|---:|---:|---:|---:|---:|
| 100 | US$ 2.600 | US$ 390 | US$ 104 | US$ 130 | US$ 26 |
| 500 | US$ 12.998 | US$ 1.950 | US$ 520 | US$ 650 | US$ 130 |
| 1.000 | US$ 25.996 | US$ 3.899 | US$ 1.040 | US$ 1.300 | US$ 260 |
| 5.000 | US$ 129.980 | US$ 19.497 | US$ 5.199 | US$ 6.499 | US$ 1.300 |
| 10.000 | US$ 259.960 | US$ 38.994 | US$ 10.398 | US$ 12.998 | US$ 2.600 |

**Tecnologia, aquisicao e resultado**

| Assinantes | Tecnologia | CAC diluido | Infra fixa | Antes de imposto | Apos reserva gerencial de 10% |
|---:|---:|---:|---:|---:|---:|
| 100 | US$ 400 | US$ 500 | US$ 154 | US$ 895 | **US$ 635** |
| 500 | US$ 2.000 | US$ 2.500 | US$ 154 | US$ 5.094 | **US$ 3.794** |
| 1.000 | US$ 4.000 | US$ 5.000 | US$ 154 | US$ 10.343 | **US$ 7.743** |
| 5.000 | US$ 20.000 | US$ 25.000 | US$ 154 | US$ 52.331 | **US$ 39.333** |
| 10.000 | US$ 40.000 | US$ 50.000 | US$ 154 | US$ 104.816 | **US$ 78.820** |

Os valores da ultima coluna nao sao impostos calculados segundo uma entidade americana real. Sao apenas uma reserva para comparacao e devem ser substituidos por modelagem contabil.

## 9. Economia gerada por programas para pequenos negocios

### Apple Small Business Program

Economia mensal de 15 pontos percentuais, caso toda a receita da tabela fosse faturada pela App Store:

| Assinantes | Economia Brasil | Economia EUA |
|---:|---:|---:|
| 100 | R$ 1.179 | US$ 390 |
| 500 | R$ 5.897 | US$ 1.950 |
| 1.000 | R$ 11.794 | US$ 3.899 |
| 5.000 | R$ 58.968 | US$ 19.497 |
| 10.000 | R$ 117.936 | US$ 38.994 |

Essa tabela e um teto teorico de economia. Na pratica, apenas a parcela iOS passa pela Apple, e a elegibilidade depende dos proceeds da App Store e das contas associadas.

### RevenueCat

- Brasil isolado: aproximadamente ate 174 assinantes no mix projetado sem custo da RevenueCat.
- EUA isolado: aproximadamente ate 96 assinantes.
- A partir do limite, a cobranca de 1% incide sobre toda a receita rastreada no mes.

### Simples Nacional e Fator R

A diferenca mensal estimada entre Anexo III e V e:

- 100 assinantes: aproximadamente R$ 747;
- 500 assinantes: aproximadamente R$ 3.004;
- 1.000 assinantes: aproximadamente R$ 5.083.

Essa economia tributaria precisa ser comparada ao custo necessario de folha e encargos para atingir Fator R de 28%.

## 10. Break-even de equipe

Depois dos custos variaveis, CAC diluido e infraestrutura-base, mas antes da folha real, a contribuicao media projetada e:

- Brasil: aproximadamente **R$ 22,44 por assinante/mes** no cenario escalado;
- Estados Unidos: aproximadamente **US$ 7,90 por assinante/mes**.

Usando cambio de R$ 5,50 e uma operacao localizada no Brasil:

| Custo mensal de equipe, contabilidade e pro-labore | Break-even com receita Brasil | Break-even com receita EUA |
|---:|---:|---:|
| R$ 20.000 | aproximadamente 930 assinantes | aproximadamente 480 assinantes |
| R$ 50.000 | aproximadamente 2.267 assinantes | aproximadamente 1.171 assinantes |

Esse calculo nao inclui aumento de impostos decorrente do crescimento nem uma mudanca nas taxas da Apple. Ele serve apenas como sensibilidade operacional.

## 11. Cenario atual versus cenario-alvo

### Custo atual observado

- US$ 22,89 de LLM rastreada por usuario/mes na amostra de 30 dias;
- mais taxa de 5,5% na compra de creditos;
- mais visao/OCR e infraestrutura nao integralmente alocados.

Usando apenas US$ 24,15 como piso operacional por usuario, antes de custos adicionais:

- Brasil: o modelo blended perderia aproximadamente R$ 80 por usuario/mes antes de DAS e infraestrutura fixa;
- EUA: o modelo blended perderia aproximadamente US$ 10 por usuario/mes antes de imposto e infraestrutura fixa.

Portanto, aumentar o volume hoje ampliaria o prejuizo. A escala so melhora o resultado depois que o custo variavel de tecnologia for reduzido e comprovado.

### Condicoes minimas antes de escalar aquisicao

1. Reduzir tecnologia variavel para no maximo US$ 4 por usuario ativo/mes.
2. Medir custo separado para texto, foto, OCR, audio e geracao de planos.
3. Criar limite de custo por usuario e protecao contra uso anormal.
4. Migrar calculos, cards e fluxos previsiveis para codigo deterministico.
5. Usar modelos mais baratos em tarefas simples e modelos avancados somente em excecoes.
6. Medir CAC real por pais, plataforma, campanha e plano.
7. Confirmar regime tributario, Fator R e tratamento contabil das comissoes das lojas.
8. Validar o mix de iOS/Android, pois a elegibilidade Apple altera a margem.
9. Revisar os precos apos 30, 100 e 500 assinantes pagantes.

## 12. Conclusao

No cenario-alvo, os planos semestral e anual financiam melhor o CAC e deixam margem positiva desde o primeiro contrato. Os planos mensais dependem de renovacao para recuperar aquisicao.

O maior risco financeiro atual nao e Supabase, Vercel ou a comissao das lojas. E o custo de LLM por usuario. Os precos propostos so devem ser considerados sustentaveis depois que a meta de US$ 4 por usuario/mes for atingida em producao e validada em uma coorte maior.

Os valores chamados de "sobra" sao margem de contribuicao gerencial. Nao representam lucro liquido contabil e nao substituem validacao de contador no Brasil e nos Estados Unidos.
