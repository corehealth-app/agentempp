# Agente MPP — instruções do projeto

Agente de WhatsApp de coaching nutricional (Dr. Roberto Menescal). Monorepo
pnpm + turbo; Supabase (projeto `xuxehkhdvjivitduarvb`); Inngest; Vercel.

## ⚠️ Regras de cálculo — LEIA ANTES DE MEXER EM QUALQUER FÓRMULA

**[docs/CALCULO-MPP.md](docs/CALCULO-MPP.md) é a fonte de verdade** de como o
agente calcula meta, balanço, bloco 7700 e renderiza o card. Toda regra está
travada por teste. Antes de mudar qualquer cálculo:

1. Leia `docs/CALCULO-MPP.md` e o teste que trava a regra.
2. Um print de paciente **não é** ordem de mudar fórmula — reproduza no banco
   primeiro (consumido, meta, exercício, meal_logs, snapshot) e confronte com o doc.
3. Mudou a regra? Atualize **código + teste + doc** na mesma PR.

**A confusão nº 1 da história deste agente:** misturar os dois balanços.
- **Comida** ("Restam/Excedente" no card) = `consumido − meta`. **SEM exercício.**
- **Bloco/déficit do dia** = `consumido − meta − exercício`. **COM exercício.**
Exercício acelera o bloco, mas NÃO libera comer mais.

## Rodar / validar
- Testes: `pnpm --filter @mpp/agent test` (regras de cálculo travadas aqui).
- Typecheck: `pnpm typecheck`.
- Deploy: `bash scripts/deploy.sh` (vercel --prod + sync Inngest). **Só com
  autorização explícita do Eduardo.**

## Escrita em produção (dado de paciente)
- Backfill/correção de `daily_snapshots`, `meal_logs`, `user_progress` exige
  **autorização explícita do Eduardo nomeando o alvo e os valores**.
- Bloco: sempre recálculo fiel ao closer (`lib/bloco-recompute.ts`), nunca "no olho".
- SQL direto no banco: Management API
  `POST https://api.supabase.com/v1/projects/{ref}/database/query` com
  `SUPABASE_ACCESS_TOKEN` (psql direto é bloqueado; `db push` é arriscado por drift).

## Idioma
Responda sempre em português brasileiro.
