-- ============================================================================
-- engagement_phrases: split picked_count/used_count + jitter LRU inicial
-- ============================================================================
-- Review pós-Fase B 2026-06-13:
--
-- 1) usage_count infla mesmo quando LLM ignora a sugestão (Sonnet 4.5 com
--    contexto saturado costuma ignorar suggestions opcionais). Resultado:
--    LRU empurra frases NUNCA usadas pro topo, e frases que cabem bem no
--    fluxo são penalizadas. Fix: split em picked_count (incrementa sempre
--    no select) e used_count (incrementa só quando substring match na
--    mensagem final do LLM).
--
-- 2) Viés de empate inicial: 200 frases com last_used_at=NULL + ORDER BY
--    ASC NULLS FIRST + Math.random TOP-5 sempre pegava as mesmas 5 IDs
--    iniciais. Fix: distribuir last_used_at NULL em janela aleatória de
--    30d passados (jitter) — todas as 200 viram elegíveis com seed diverso.
-- ============================================================================

ALTER TABLE engagement_phrases ADD COLUMN IF NOT EXISTS used_count integer NOT NULL DEFAULT 0;
ALTER TABLE engagement_phrases RENAME COLUMN usage_count TO picked_count;

-- Jitter inicial (idempotente: só atualiza onde last_used_at IS NULL)
UPDATE engagement_phrases
SET last_used_at = (now() - (random() * interval '30 days'))
WHERE last_used_at IS NULL AND curated_by = 'roberto-2026-06-13';
