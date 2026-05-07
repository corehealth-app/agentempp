# Documentação de Fórmulas — User Profiles

Esta página documenta todas as fórmulas utilizadas na Data Source **User Profiles** do Agente MPP. Cada seção apresenta a fórmula, seu código e a explicação do cálculo no contexto do projeto.

---

## 1. Age (Idade)

**Descrição:** Calcula a idade do usuário em anos a partir da data de nascimento.

<aside>
🎯

**No contexto do MPP:** A idade é essencial para calcular o metabolismo basal (BMR). Pessoas mais velhas têm metabolismo mais lento, então o agente ajusta as metas calóricas automaticamente. O usuário informa apenas a data de nascimento uma vez, e o sistema mantém a idade sempre atualizada.

</aside>

```
if(empty(prop("Birth Date")),
  0,
  dateBetween(now(), prop("Birth Date"), "years")
)
```

**Lógica:**

- Se `Birth Date` estiver vazia, retorna `0`.
- Caso contrário, calcula a diferença em anos entre a data atual (`now()`) e a data de nascimento.

---

## 2. LBM (Lean Body Mass — Massa Magra)

**Descrição:** Calcula a massa magra em kg, descontando o percentual de gordura corporal do peso total.

<aside>
🎯

**No contexto do MPP:** A massa magra representa tudo no corpo exceto gordura (músculos, ossos, órgãos). É a base para cálculos mais precisos de metabolismo e metas. Quando o usuário tem seu percentual de gordura (via bioimpedância ou estimativa), o agente consegue personalizar melhor as recomendações nutricionais.

</aside>

```
if(
  empty(prop("Weight KG")) or empty(prop("Body Fat Percent")),
  empty(),
  /* LBM = Weight × (1 - Body Fat %) */
  round(prop("Weight KG") * (1 - prop("Body Fat Percent") / 100), 2)
)
```

**Lógica:**

- Requer `Weight KG` e `Body Fat Percent` preenchidos.
- Fórmula: **LBM = Peso × (1 − BF% / 100)**
- Resultado arredondado para 2 casas decimais.

---

## 3. IMC (Índice de Massa Corporal)

**Descrição:** Calcula o IMC padrão a partir do peso e altura.

<aside>
🎯

**No contexto do MPP:** O IMC é uma métrica de referência rápida para classificar o peso (abaixo, normal, sobrepeso, obesidade). Embora não seja perfeito (não diferencia músculo de gordura), ajuda o agente a contextualizar a situação inicial do usuário e acompanhar a evolução ao longo do tempo.

</aside>

```
if(
  empty(prop("Weight KG")) or empty(prop("Height CM")) or prop("Height CM") == 0,
  empty(),
  /* BMI = weight in kg / (height in meters)^2 */
  round(prop("Weight KG") / (prop("Height CM") / 100) ^ 2, 1)
)
```

**Lógica:**

- Requer `Weight KG` e `Height CM` válidos (altura ≠ 0).
- Fórmula: **IMC = Peso / (Altura em m)²**
- Resultado arredondado para 1 casa decimal.

---

## 4. BMR Formula (Indicador de Fórmula)

**Descrição:** Indica qual fórmula de BMR está sendo utilizada no cálculo.

<aside>
🎯

**No contexto do MPP:** Este campo é informativo — mostra qual método está sendo usado nos cálculos. Katch-McArdle é mais precisa quando temos o percentual de gordura; Mifflin-St Jeor é usada como fallback. Isso dá transparência ao usuário sobre como suas metas foram calculadas.

</aside>

```
if(not empty(prop("Body Fat Percent")), "Katch-McArdle", "Mifflin-St Jeor")
```

**Lógica:**

- Se `Body Fat Percent` estiver preenchido → usa **Katch-McArdle** (mais precisa com BF%).
- Caso contrário → usa **Mifflin-St Jeor** (baseada em peso, altura, idade e sexo).

---

## 5. BMR (Taxa Metabólica Basal)

**Descrição:** Calcula a taxa metabólica basal em kcal/dia, usando a fórmula mais apropriada para os dados disponíveis.

<aside>
🎯

**No contexto do MPP:** O BMR é a quantidade de calorias que o corpo queima em repouso absoluto (apenas para manter funções vitais). É o ponto de partida para todas as metas calóricas. O agente usa esse valor para calcular quanto o usuário pode comer para perder, manter ou ganhar peso de forma saudável.

</aside>

```
ifs(
  /* Use Katch-McArdle if Body Fat Percent is available */
  not empty(prop("Body Fat Percent")) and not empty(prop("LBM")),
  round(370 + (21.6 * prop("LBM")), 0),
  
  /* Use Mifflin-St Jeor if we have weight, height, age, and sex */
  not empty(prop("Weight KG")) and not empty(prop("Height CM")) and not empty(prop("Age")) and not empty(prop("Sex")),
  ifs(
    prop("Sex") == "Masculino",
    round(10 * prop("Weight KG") + 6.25 * prop("Height CM") - 5 * prop("Age") + 5, 0),
    prop("Sex") == "Feminino",
    round(10 * prop("Weight KG") + 6.25 * prop("Height CM") - 5 * prop("Age") - 161, 0),
    empty()
  ),
  
  /* Missing required fields */
  empty()
)
```

**Lógica:**

- **Katch-McArdle** (com BF%): `BMR = 370 + (21.6 × LBM)`
- **Mifflin-St Jeor** (sem BF%):
    - Masculino: `BMR = 10 × Peso + 6.25 × Altura − 5 × Idade + 5`
    - Feminino: `BMR = 10 × Peso + 6.25 × Altura − 5 × Idade − 161`

---

## 6. Protein Factor (Fator de Proteína)

**Descrição:** Define o multiplicador de proteína (g/kg) baseado no perfil comportamental do usuário.

<aside>
🎯

**No contexto do MPP:** Este é um diferencial do projeto. Em vez de usar um valor fixo de proteína, o agente adapta a recomendação ao perfil comportamental. Usuários com dificuldade de adesão recebem metas mais acessíveis (1.6g/kg), enquanto usuários disciplinados e ativos podem receber metas mais agressivas (até 2.0g/kg). Isso aumenta a chance de sucesso.

</aside>

```
ifs(
  /* Priority 1: Return 1.6 for challenging behavioral factors */
  prop("Hunger Level") == "Muita" or
  prop("Diet History") == "Várias vezes" or
  prop("Routine Stability") == "Desorganizada" or
  prop("Rule Following") == "Difícil",
  1.6,

  /* Priority 2: Low training frequency */
  prop("Training Frequency") < 3,
  1.7,

  /* Priority 3: Optimal profile with high training */
  prop("Hunger Level") == "Pouca" and
  prop("Routine Stability") == "Organizada" and
  prop("Rule Following") == "Fácil" and
  prop("Training Frequency") >= 5,
  2.0,

  /* Priority 4: Optimal profile with moderate-high training */
  prop("Hunger Level") == "Pouca" and
  prop("Routine Stability") == "Organizada" and
  prop("Rule Following") == "Fácil" and
  prop("Training Frequency") >= 4,
  1.9,

  /* Default */
  1.8
)
```

**Lógica (por prioridade):**

| Prioridade | Condição | Fator |
| --- | --- | --- |
| 1 | Perfil comportamental difícil (muita fome, histórico de desistência, rotina desorganizada ou dificuldade em seguir regras) | **1.6** |
| 2 | Frequência de treino < 3 dias/semana | **1.7** |
| 3 | Perfil ótimo + treino ≥ 5 dias/semana | **2.0** |
| 4 | Perfil ótimo + treino ≥ 4 dias/semana | **1.9** |
| Default | Nenhuma das anteriores | **1.8** |

---

## 7. Daily Kcal Goal (Meta Calórica Diária)

**Descrição:** Calcula a meta de calorias diária baseada no protocolo atual do usuário.

<aside>
🎯

**No contexto do MPP:** Esta é a meta principal que o agente monitora diariamente. Dependendo do objetivo (recomposição, ganho de massa ou manutenção), o cálculo muda. Para recomposição, aplica um déficit calórico controlado. Para ganho de massa, adiciona um superávit. O agente usa essa meta para dar feedback diário e calcular XP de gamificação.

</aside>

```
lets(
    /* Map activity level text to multiplier values */
    activityMultiplier, ifs(
      prop("Activity Level") == "Sedentario", 1.2,
      prop("Activity Level") == "Leve", 1.375,
      prop("Activity Level") == "Moderado", 1.55,
      prop("Activity Level") == "Alto", 1.725,
      prop("Activity Level") == "Atleta", 1.9,
      1.2 /* Default to sedentary if not specified */
    ),
    /* Calculate daily calorie goal based on protocol */
    ifs(
      /* Recomposition: increase BMR by 20% then subtract deficit */
      prop("Current Protocol") == "Recomposição Corporal",
      round(prop("BMR") * 1.2 - if(empty(prop("Deficit Level")), 500, prop("Deficit Level")), 0),
      
      /* Gain: apply activity multiplier then add 5% surplus */
      prop("Current Protocol") == "Ganho De Massa",
      round(prop("BMR") * activityMultiplier * 1.05, 0),
      
      /* Maintenance or no protocol: BMR * activity level */
      round(prop("BMR") * activityMultiplier, 0)
    )
)
```

**Lógica:**

**Multiplicadores de Atividade:**

| Nível | Multiplicador |
| --- | --- |
| Sedentário | 1.2 |
| Leve | 1.375 |
| Moderado | 1.55 |
| Alto | 1.725 |
| Atleta | 1.9 |

**Cálculo por Protocolo:**

| Protocolo | Fórmula |
| --- | --- |
| Recomposição Corporal | `BMR × 1.2 − Déficit` (padrão: 500 kcal) |
| Ganho de Massa | `BMR × Multiplicador × 1.05` (superávit de 5%) |
| Manutenção | `BMR × Multiplicador` |

---

## 8. Daily Protein Goal (Meta de Proteína Diária)

**Descrição:** Calcula a meta de proteína em gramas baseada no peso e fator de proteína.

<aside>
🎯

**No contexto do MPP:** A proteína é fundamental para preservar massa muscular durante a perda de peso e para construir músculos no ganho de massa. O agente acompanha o consumo diário e recompensa o usuário com XP quando a meta é atingida. A meta é personalizada pelo Protein Factor.

</aside>

```
if(empty(prop("Weight KG")), empty(), prop("Weight KG") * prop("Protein Factor"))
```

**Lógica:**

- Fórmula: **Proteína = Peso × Fator de Proteína**
- O fator varia de 1.6 a 2.0 g/kg conforme perfil comportamental.

---

## 9. Daily Water Goal (Meta de Água Diária)

**Descrição:** Calcula a meta de consumo de água em litros.

<aside>
🎯

**No contexto do MPP:** A hidratação adequada ajuda no metabolismo, na saciedade e na performance física. O agente calcula uma meta proporcional ao peso do usuário (35ml por kg) e pode lembrar o usuário de beber água ao longo do dia.

</aside>

```
if(empty(prop("Weight KG")), empty(), prop("Weight KG") * 0.035)
```

**Lógica:**

- Fórmula: **Água (L) = Peso × 0.035**
- Exemplo: 80 kg → 2.8 litros/dia.

---

## 10. Daily Sleep Goal (Meta de Sono Diário)

**Descrição:** Meta fixa de horas de sono por dia.

<aside>
🎯

**No contexto do MPP:** O sono é um pilar frequentemente negligenciado na saúde. Dormir menos de 7-8 horas prejudica a recuperação muscular, aumenta a fome e dificulta a perda de gordura. O agente monitora o sono reportado e incentiva o usuário a manter uma rotina saudável.

</aside>

```
8
```

**Lógica:**

- Valor fixo: **8 horas**.

---

## 11. Daily Steps Goal (Meta de Passos Diários)

**Descrição:** Meta fixa de passos por dia.

<aside>
🎯

**No contexto do MPP:** Passos diários representam o NEAT (Non-Exercise Activity Thermogenesis) — a energia gasta em atividades do dia-a-dia. 8.500 passos é uma meta alcançável que aumenta significativamente o gasto calórico sem exigir exercícios formais. O agente usa essa métrica para calcular XP e incentivar movimento.

</aside>

```
8500
```

**Lógica:**

- Valor fixo: **8.500 passos**.

---

## 12. Target Weight (Peso Alvo)

**Descrição:** Calcula o peso estimado quando o usuário atingir o percentual de gordura meta.

<aside>
🎯

**No contexto do MPP:** Diferente de "quero pesar X kg", o peso alvo é calculado cientificamente. O agente assume que a massa magra será preservada e calcula quanto o usuário pesará ao atingir seu percentual de gordura desejado. Isso evita metas irrealistas e dá um número concreto para trabalhar.

</aside>

```
if(
  empty(prop("LBM")) or empty(prop("BF Goal")),
  empty(),
  /* Peso Alvo = LBM / (1 - BF Meta / 100) */
  prop("LBM") / (1 - prop("BF Goal") / 100)
)
```

**Lógica:**

- Requer `LBM` e `BF Goal` preenchidos.
- Fórmula: **Peso Alvo = LBM / (1 − BF Meta% / 100)**
- Pressupõe manutenção da massa magra durante o processo.

---

## 13. Fat To Lose KG (Gordura a Perder)

**Descrição:** Calcula quantos quilos de gordura o usuário precisa perder para atingir o peso alvo.

<aside>
🎯

**No contexto do MPP:** Este valor mostra a "distância" até o objetivo. É gordura pura a ser eliminada, não peso total. O agente usa essa informação para contextualizar o progresso do usuário e calcular estimativas de tempo. Exemplo: "Você tem 8kg de gordura para eliminar."

</aside>

```
if(
  not empty(prop("Weight KG")) and not empty(prop("Target Weight")) and prop("Weight KG") > prop("Target Weight"),
  prop("Weight KG") - prop("Target Weight"),
  empty()
)
```

**Lógica:**

- Fórmula: **Gordura a Perder = Peso Atual − Peso Alvo**
- Só retorna valor se peso atual > peso alvo.

---

## 14. Estimated Days (Dias Estimados)

**Descrição:** Estima quantos dias o usuário levará para atingir a meta de gordura.

<aside>
🎯

**No contexto do MPP:** Esta projeção dá ao usuário uma expectativa realista. Baseado no princípio de que 1kg de gordura = ~7.700 kcal, o agente calcula quantos dias seriam necessários mantendo o déficit configurado. Isso ajuda a gerenciar expectativas e manter a motivação com um horizonte claro.

</aside>

```
if(
  empty(prop("Fat To Lose KG")) or prop("Fat To Lose KG") <= 0,
  empty(),
  /* Calculate days: (kg to lose * 7700 kcal/kg) / daily deficit */
  round(
    prop("Fat To Lose KG") * 7700 / 
    if(empty(prop("Deficit Level")), 500, prop("Deficit Level")),
    0
  )
)
```

**Lógica:**

- Usa o princípio de que 1 kg de gordura ≈ 7.700 kcal.
- Fórmula: **Dias = (Gordura a Perder × 7700) / Déficit Diário**
- Déficit padrão: 500 kcal se não especificado.

---

## Resumo das Dependências

```
Birth Date → Age
Weight KG + Body Fat Percent → LBM
Weight KG + Height CM → IMC
LBM (ou Weight/Height/Age/Sex) → BMR
Perfil Comportamental → Protein Factor
BMR + Activity Level + Protocol → Daily Kcal Goal
Weight KG + Protein Factor → Daily Protein Goal
Weight KG → Daily Water Goal
LBM + BF Goal → Target Weight
Weight KG + Target Weight → Fat To Lose KG
Fat To Lose KG + Deficit Level → Estimated Days
```

---

*Documentação gerada em 14/01/2026.*