# Leitura nativa do feedback de registro v2

O iOS possui um consumidor opcional de `registration.feedback.v2` para a confirmação de uma proposta salva. O servidor continua responsável pela seleção de versão, identidade, autorização e origem dos fatos. Este incremento não ativa capability, rota, flag, migração, envio ou writer de registro.

`RegistrationFeedbackSnapshot` despacha explicitamente v1 e v2. O corpo do leitor v1 foi preservado em `RegistrationFeedbackV1Snapshot`, incluindo seus critérios históricos de validade e vínculo. Na confirmação, ambas as versões precisam corresponder ao ID da proposta, ao tipo de registro e ao estado `confirmed`. Versão desconhecida, conteúdo inválido ou vínculo incompatível removem somente o enriquecimento opcional; o registro principal continua disponível.

O leitor v2 exige objetos fechados em todos os níveis, presença dos campos anuláveis, enums conhecidos, números finitos e seguros, datas civis válidas, IDs de logs únicos, limites de quantidade e proveniência. Confere os percentuais IEEE754 e a coerência do bloco para rejeitar recibos inconsistentes. Essa conferência não cria metas, recomputa totais oficiais, estima gasto ou concede crédito. A representação textual usa os fatos salvos e a locale do recibo, em seis seções: confirmação, itens, resumo, dia, bloco e educação.

A educação é validada contra a versão fixa `registration.education.v1`, incluindo template, preferências conhecidas e texto completo. A interface mostra o texto persistido que passou nessa validação; não grava uma nova frase nem usa modelo de IA. Revisões futuras de catálogo precisam manter o leitor da versão histórica.

## Limite do histórico

As superfícies legadas de refeições e esclarecimento de atividade continuam admitindo somente v1. Elas não possuem uma projeção clínica atual autenticada para apresentar v2 com segurança. A rejeição de v2 nessas superfícies preserva os dados principais e não altera o recibo salvo. A futura integração de histórico deverá fornecer essa apresentação atual explicitamente; não deve comparar o ID da proposta com o ID do log nem regenerar o recibo histórico depois de uma edição.

## Qualificação local

`RegistrationFeedbackV2Fixtures.json` contém 141 casos públicos sintéticos da qualificação SQL e 13 complementos: mL, medidas e unidades, singular/plural, metas independentes ausentes e fatos opcionais indisponíveis. Cada caso guarda o resultado do renderizador canônico TypeScript. Os hashes das duas fontes ficam no arquivo gerado.

Com as dependências existentes do workspace instaladas, a regeneração usa:

```sh
node scripts/mobile/generate-feedback-v2-ios-fixtures.mjs
```

O gerador transpila e executa as fontes locais, valida cada recibo e remove seu próprio diretório temporário. Não instala pacotes, não acessa providers e não altera as fontes canônicas.

`RegistrationFeedbackV2Tests` compara os seis textos completos e o round trip de todos os casos, testa objetos extras, campos ausentes, números/tipos inválidos, unidades, metas, proteção clínica, bloco, catálogo educativo, vínculo da confirmação e bloqueio do histórico legado. A prova visual usa uma janela real de aplicativo em simulador para conferir os seis elementos acessíveis. Ela não substitui QA conectado do writer/BFF, um teste físico, TestFlight ou aceite editorial/clínico.
