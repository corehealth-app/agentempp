# Today: disponibilidade de energia por campo no iOS

O leitor numérico anterior continua sendo o padrão. A seleção do build QA usa
`PERFORME_TODAY_ENERGY_REPRESENTATION=field_availability_v1` no Info.plist, junto
de `PERFORME_CURRENT_CLINICAL_RUNTIME=current_clinical_v1` e do binding existente
da prévia: origem exata, projeto, região e recibo fixados pelo produtor do build.
Este incremento não inclui esses valores em um aplicativo distribuído. O QA usa
a composição de conta real já existente; argumentos de teste não concedem acesso.

Só Today envia `day_energy=field_availability_v1`, além da negociação clínica.
Plan, Trends, History e os demais leitores mantêm suas consultas. A seleção não
substitui Auth, lease, geração da sessão ou política clínica; não permite fallback
numérico quando o servidor não entrega a versão solicitada.

`bodyflow.daily-state.v4` exige disponibilidade explícita e relações consistentes
entre status e valores nulos. Exercício desconhecido permanece nulo; zero conhecido
é um valor. Comida, proteína, hidratação e bloco anteriormente consolidado mantêm
seus dados oficiais e suas proteções independentes. O saldo usa exclusivamente o
valor, referência e inclusão de exercício informados pelo servidor; o app não
refaz a fórmula nem aumenta o orçamento alimentar com exercício.

Os codecs v2/v3 de Today conservam o exercício numérico e a semântica histórica
de inclusão quando o campo antigo está ausente. Recibos de registro v1/v2 e o
novo feedback v3 são contratos separados deste leitor. As fixtures deste recorte
são controladas para teste de contrato, sem alegação de observação HTTP real.
