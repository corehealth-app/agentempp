-- ============================================================================
-- Base de conhecimento RAG do método (sub-projeto D — fundação, 2026-05-21)
-- ============================================================================
-- Armazena o método (páginas Notion) em chunks + embeddings (pgvector 1024d),
-- pra recuperação por turno e encolhimento futuro do prompt. DORMENTE: nada
-- consome ainda. Aplicado e validado em prod antes do commit.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.method_chunks (
  id uuid primary key default gen_random_uuid(),
  page_title text not null,
  chunk_index int not null default 0,
  content text not null,
  protocol text,
  embedding vector(1024),
  created_at timestamptz not null default now()
);
ALTER TABLE public.method_chunks ENABLE ROW LEVEL SECURITY;
