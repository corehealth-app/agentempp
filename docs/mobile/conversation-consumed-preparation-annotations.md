# Evidência estruturada de cozido padrão

O calculador aceita `preparationAnnotations: 'consumed.preparation.v1'` em
`MealCalculationOptions`. O opt-in é capturado antes do primeiro `await`, junto à
política de consumo e à fonte. Sem ele, a propriedade de resultado fica ausente
e o DTO legado conserva seu formato. Com ele, `MealCalcResult` inclui
`preparation_annotations`, inclusive uma lista vazia quando nada foi assumido.

Cada `ConsumedPreparationAnnotation`, exportado por `@mpp/agent`, contém:

```ts
{
  schema: 'consumed.preparation.v1',
  kind: 'default_cooked',
  input_indexes: [0],
  food_name: 'arroz branco cozido',
  policy: 'consumed-meal-v1',
  reference_id: 'food_db:160'
}
```

A anotação nasce somente no branch que aplicou a política de consumo e leu a
referência verificada correspondente, com os nutrientes esperados. O ID é o da
linha realmente usada. Na preparação conversacional, o epoch SQL de fontes deve
cercar esse lookup e ser revalidado. O nome é o da linha final calculada.
Não é inferida de nome cozido, warning, match fuzzy ou histórico.
O recurso não muda a escolha de alimento nem os valores para obter uma anotação.

Preparo explícito, inclusive cozido, não é uma suposição de preparo. Rótulo ou
nutrição explícita, marca, correção pessoal ativa e remapeamento ativo sem macros
também não produzem essa evidência. Mesmo quando uma nutrição explícita inválida
é rejeitada e o cálculo existente usa o catálogo, ela não é reinterpretada como
prova de que o preparo foi omitido.

Quando nomes do mesmo padrão se agregam, a anotação agrupa somente os índices
originais que realmente receberam a suposição. Por exemplo, `arroz cozido`,
`feijão`, `arroz` podem resultar em uma linha de arroz com índices `[0, 2]`, mas
sua anotação cobre apenas `[2]`. As anotações seguem a ordem final das linhas e
não compartilham os arrays mutáveis de `input_indexes` do resultado. Referência
ausente ou alterada continua gerando indisponibilidade, sem resultado parcial.

Esse retorno é evidência de uma decisão do calculador. Não demonstra consumo,
cobertura semântica integral da fonte original ou autorização de gravação. A
factory real, os recibos completos e a preparação semântica continuam necessários
antes da ativação de qualquer caller público do writer SQL.
