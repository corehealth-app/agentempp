-- ============================================================================
-- goal_type_enum: adicionar 'peso_kg' (sincroniza drift de prod)
-- ============================================================================
-- Drift descoberto no audit 06-18 (caso Roberto, Discovery agent A):
-- - Migration source 20260501120000_extensions_and_enums.sql:40 cria o enum
--   com SÓ ('BF', 'IMC').
-- - Em prod o enum tem ('BF', 'IMC', 'peso_kg') — peso_kg foi adicionado sem
--   migration tracked. Causa: tool `define_meta_peso` foi criada (2026-06-01)
--   gravando goal_type='peso_kg' diretamente; algum upsert/cast aceitou
--   silenciosamente.
-- - Tipos gerados em packages/db/src/generated/database.ts:2160 só têm BF|IMC
--   — por isso o `as any` nos updates de tools.ts.
--
-- Esta migration é idempotente (IF NOT EXISTS) e serve só pra sincronizar
-- o source-of-truth com prod. Não muda comportamento. Depois disso, vale
-- regenerar os types e remover os 2 `as any` em tools.ts (deixado pra
-- próxima limpeza ACT-1 do plano de prevenção).
-- ============================================================================

ALTER TYPE goal_type_enum ADD VALUE IF NOT EXISTS 'peso_kg';

-- Sanity: verificar que os 3 valores existem após o ALTER.
-- Roda no psql/dashboard mas não dá pra ASSERT em migration plain — só pra
-- referência manual:
--   SELECT enumlabel FROM pg_enum WHERE enumtypid = 'goal_type_enum'::regtype
--   ORDER BY enumsortorder;
-- Esperado: BF, IMC, peso_kg
