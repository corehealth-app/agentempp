# Code Node — Calcula Avanço User Progress

Código do nó **Code Calcula Avanço** no n8n, responsável por receber o Daily Snapshot salvo + o User Progress atual e calcular os novos valores acumulados para atualização.

---

### Resumo da Lógica

<aside>
🧠

**O que esse Code Node faz:**

Recebe dois inputs — o **Daily Snapshot** (gerado pelo Basic LLM Chain) e o **User Progress atual** (lido do Notion) — e calcula os **novos valores acumulados** para gravar de volta no User Progress.

</aside>

### 1. XP Total

Soma o `xp_earned` do snapshot do dia ao `xp_total` acumulado no User Progress.

**Fórmula:** `newXpTotal = oldXpTotal + xpEarned`

### 2. Level

Compara o `newXpTotal` com uma tabela de thresholds para determinar o nível:

- Level 1: 0 XP
- Level 2: 100 XP
- Level 3: 300 XP
- Level 4: 600 XP
- Level 5: 1.000 XP
- Level 6: 1.500 XP
- Level 7: 2.200 XP
- Level 8: 3.000 XP

### 3. Streak (Sequência de dias ativos)

Calcula a diferença em dias entre [`snapshot.date`](http://snapshot.date) (hoje) e `Last Active Date` do User Progress:

- Se a diferença for **exatamente 1 dia** → incrementa streak (`oldStreak + 1`)
- Qualquer outro valor (0 dias = mesmo dia já contado, 2+ dias = quebra) → reseta para `1`

### 4. Deficit Block & Blocks Completed

Replica a fórmula **Daily Balance** do Notion localmente:

`Balance = Consumed - (Target + Exercise)`

- Resultado **negativo** = déficit do dia (invertido para positivo via `Math.abs`)
- Resultado **positivo** = superávit (ignorado, conta como 0 de déficit)

Acumula no `Deficit Block` do User Progress. Quando atinge **7.700 kcal** (≈ 1 kg de gordura):

- Incrementa `Blocks Completed` em +1
- Reseta `Deficit Block` para o excedente (`totalDeficit - 7700`)

### 5. Peso e BF%

Se o snapshot trouxer `current_weight` ou `current_bf_percent`, atualiza. Caso contrário, mantém os valores anteriores do User Progress.

### 6. Badges

Lê o array JSON de badges existentes e verifica regras:

- **Primeira Semana**: streak ≥ 7
- **Mês de Ferro**: streak ≥ 30
- **Primeiro Bloco**: blocks_completed ≥ 1
- **XP Master**: xp_total ≥ 1.000

Badges são adicionados apenas uma vez (deduplicação via `.includes()`).

---

### Fluxo no n8n

```
Basic LLM Chain → Cria Daily Snapshot → Current User Progress Data Loop [GET] → Code Calcula Avanço → Current User Progress Data [UPDATE]
```

---

### Referência: Daily Balance (fórmula no Notion)

A fórmula `Daily Balance` do Daily Snapshots calcula:

```
if(empty(Calories Consumed),
  empty(),
  Calories Consumed - (Calories Target + if(empty(Exercise Calories), 0, Exercise Calories))
)
```

O resultado é **negativo = déficit**, **positivo = superávit**. O Code Node replica essa lógica para calcular o déficit do dia sem depender de uma segunda leitura ao Notion.

---

### Código (n8n Code Node — formato achatado n8n)

```jsx
// ============================================================
// Code Calcula Avanço — User Progress
// ============================================================
// Recebe:
//   - Output do Basic LLM Chain (daily_snapshot)
//   - Output do Current User Progress Data Loop (registro atual)
// Retorna:
//   - Objeto com os valores calculados para UPDATE no User Progress
// ============================================================
// IMPORTANTE: O nó Notion getAll do n8n retorna properties no
// formato achatado (property_xp_total) e NÃO no formato aninhado
// da Notion API (properties['XP Total'].number).
// ============================================================

// --- Inputs ---
const snapshot = $('Basic LLM Chain').first().json.output.daily_snapshot;
const progress = $('Current User Progress Data Loop').first().json;

// ============================================================
// 1. XP Total
// ============================================================
const xpEarned = snapshot.xp_earned || 0;
const oldXpTotal = progress.property_xp_total || 0;
const newXpTotal = oldXpTotal + xpEarned;

// ============================================================
// 2. Level (tabela de níveis MPP)
// ============================================================
const levelThresholds = [0, 100, 300, 600, 1000, 1500, 2200, 3000];
let newLevel = 1;
for (let i = levelThresholds.length - 1; i >= 0; i--) {
  if (newXpTotal >= levelThresholds[i]) {
    newLevel = i + 1;
    break;
  }
}

// ============================================================
// 3. Streak
// ============================================================
const lastActiveRaw = progress.property_last_active_date;
const today = snapshot.date;
let newStreak = 1;

if (lastActiveRaw) {
  // String() garante compatibilidade caso n8n retorne Date object
  const lastActive = String(lastActiveRaw).substring(0, 10);
  const diffMs = new Date(today) - new Date(lastActive);
  const diffDays = Math.round(diffMs / 86400000);
  const oldStreak = progress.property_current_streak || 0;
  newStreak = diffDays === 1 ? oldStreak + 1 : 1;
}

// ============================================================
// 4. Deficit Block & Blocks Completed
// ============================================================
const consumed = snapshot.calories_consumed || 0;
const target = snapshot.calories_target || 0;
const exercise = snapshot.exercise_calories || 0;
const dailyBalance = consumed - (target + exercise);
const dailyDeficit = Math.abs(Math.min(dailyBalance, 0));

const oldDeficitBlock = progress.property_deficit_block || 0;
const totalDeficitRaw = oldDeficitBlock + dailyDeficit;
const oldBlocks = progress.property_blocks_completed || 0;

let newBlocks = oldBlocks;
let newDeficitBlock = totalDeficitRaw;

if (totalDeficitRaw >= 7700) {
  newBlocks = oldBlocks + 1;
  newDeficitBlock = totalDeficitRaw - 7700;
}

// ============================================================
// 5. Peso e BF% (atualiza só se presente no snapshot)
// ============================================================
const oldWeight = progress.property_current_weight ?? null;
const oldBf = progress.property_current_bf_percent ?? null;
const newWeight = snapshot.current_weight ?? oldWeight;
const newBf = snapshot.current_bf_percent ?? oldBf;

// ============================================================
// 6. Badges
// ============================================================
const badgesRaw = progress.property_badges_earned || '[]';
let badges;
try {
  badges = JSON.parse(badgesRaw);
  if (!Array.isArray(badges)) badges = [];
} catch {
  badges = [];
}

if (newStreak >= 7 && !badges.includes('Primeira Semana')) {
  badges.push('Primeira Semana');
}
if (newStreak >= 30 && !badges.includes('Mês de Ferro')) {
  badges.push('Mês de Ferro');
}
if (newBlocks >= 1 && !badges.includes('Primeiro Bloco')) {
  badges.push('Primeiro Bloco');
}
if (newXpTotal >= 1000 && !badges.includes('XP Master')) {
  badges.push('XP Master');
}

// ============================================================
// 7. Output para o UPDATE
// ============================================================
return [{
  json: {
    xp_total: newXpTotal,
    level: newLevel,
    current_streak: newStreak,
    blocks_completed: newBlocks,
    deficit_block: newDeficitBlock,
    current_weight: newWeight,
    current_bf_percent: newBf,
    last_active_date: today,
    badges_earned: JSON.stringify(badges),
    progress_page_id: progress.id,

    _debug: {
      xp_earned: xpEarned,
      old_xp_total: oldXpTotal,
      daily_balance: dailyBalance,
      daily_deficit: dailyDeficit,
      old_deficit_block: oldDeficitBlock,
      total_deficit_raw: totalDeficitRaw,
      block_completed_today: totalDeficitRaw >= 7700,
      old_streak: progress.property_current_streak || 0,
      old_blocks: oldBlocks
    }
  }
}];
```

---

### Mapeamento: Output do Code → UPDATE User Progress

No nó **Current User Progress Data [UPDATE]**, mapear:

| **Campo Code Node** | **Property Notion (User Progress)** | **Tipo** | **Expressão n8n** |
| --- | --- | --- | --- |
| xp_total | XP Total | number |  `$json.xp_total`  |
| level | Level | number |  `$json.level`  |
| current_streak | Current Streak | number |  `$json.current_streak`  |
| blocks_completed | Blocks Completed | number |  `$json.blocks_completed`  |
| deficit_block | Deficit Block | number |  `$json.deficit_block`  |
| current_weight | Current Weight | number |  `$json.current_weight`  |
| current_bf_percent | Current BF Percent | number |  `$json.current_bf_percent`  |
| last_active_date | Last Active Date | date |  `$json.last_active_date`  |
| badges_earned | Badges Earned | text |  `$json.badges_earned`  |

---

### Notas importantes

<aside>
⚠️

**Relation (User):** O nó Notion do n8n não permite setar properties do tipo `relation`. Para criar o vínculo User no Daily Snapshot e no User Progress, use um **HTTP Request** node com a Notion API diretamente:

```
PATCH https://api.notion.com/v1/pages/{page_id}
Headers:
  Authorization: Bearer {notion_token}
  Notion-Version: 2022-06-28
Body:
{
  "properties": {
    "User": {
      "relation": [{ "id": "notion_page_id_do_usuario" }]
    }
  }
}
```

</aside>

<aside>
💡

**Formato n8n achatado:** O nó Notion `getAll` retorna properties no formato `property_nome_snake_case` (ex: `property_xp_total`), e **não** no formato aninhado da API (`properties['XP Total'].number`). Campos de data podem vir como objetos — sempre usar `String()` antes de `.substring()`.

</aside>

<aside>
🐛

**Debug:** O campo `_debug` no output mostra valores intermediários para validação. Remova ou ignore em produção.

</aside>