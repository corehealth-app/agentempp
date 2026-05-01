# ADR 006 — TACO importada como base nutricional

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

Estimar calorias e macros via LLM tem erro intrínseco de 20-40%. Para um produto de coach nutricional brasileiro, isso compromete confiabilidade. Bases nutricionais comerciais (Calorie Mama, LogMeal) custam ~$0.05-0.15/imagem e têm cobertura fraca de comida brasileira.

## Decisão

Importar a **TACO (Tabela Brasileira de Composição de Alimentos — UNICAMP)** para uma tabela `food_db` no Postgres com:
- Busca por trigram (`pg_trgm`) para fuzzy match de nome
- Embeddings (`pgvector`) para fallback semântico
- Fonte oficial, gratuita, em PT-BR

Pipeline de cálculo:
1. Vision (Gemini Flash) identifica itens + quantidade aproximada
2. Cada item é matched contra `food_db`
3. Macros calculadas determinísticamente a partir da TACO
4. LLM apenas formata a resposta (não calcula)

## Consequências

- **+** Precisão real para comida brasileira
- **+** Custo zero (base pública)
- **+** Resultados reproduzíveis e auditáveis
- **+** UI pode mostrar "estimei via TACO oficial"
- **−** Itens não cobertos pela TACO precisam fallback (gemini estimate ou pergunta ao usuário)
