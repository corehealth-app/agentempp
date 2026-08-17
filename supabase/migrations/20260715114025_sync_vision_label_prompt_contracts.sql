-- Keep mutable admin prompts aligned with the non-optional runtime contract.
-- The provider also appends these rules in code, so future prompt edits cannot
-- silently remove nutrition-label routing or multimodal deduplication.

DO $$
BEGIN
  UPDATE public.agent_rules
  SET
    content = rtrim(content) || E'\n\n# CONTRATO RUNTIME VISION CLASSIFIER V1 — prevalece sobre instruções anteriores\nRetorne APENAS uma destas 6 palavras: meal, body, scale, nutrition_label, equipment ou other.\nSe houver um quadro "Nutrition Facts" ou tabela nutricional legível, retorne nutrition_label, mesmo que a imagem também mostre alimento, bebida ou embalagem.',
    updated_at = now()
  WHERE slug = 'vision-classifier'
    AND status = 'active'
    AND content NOT LIKE '%# CONTRATO RUNTIME VISION CLASSIFIER V1%';

  UPDATE public.agent_rules
  SET
    content = rtrim(content) || E'\n\n# CONTRATO RUNTIME VISION MEAL V1 — prevalece sobre instruções anteriores\n- A mensagem/legenda serve para identificar ou corrigir o que está VISÍVEL; não crie itens que existem apenas na legenda. O agente principal processa a legenda separadamente.\n- Se foto e legenda nomearem o mesmo alimento, emita esse alimento uma única vez.\n- Se houver "Nutrition Facts" ou tabela nutricional legível, use nutrition_label_visible=true. Caso contrário, use false.\n- O JSON deve conter exatamente items, meal_context e nutrition_label_visible; cada item deve conter name, quantity_g_estimate e confidence.',
    updated_at = now()
  WHERE slug = 'vision-meal'
    AND status = 'active'
    AND content NOT LIKE '%# CONTRATO RUNTIME VISION MEAL V1%';
END;
$$;
