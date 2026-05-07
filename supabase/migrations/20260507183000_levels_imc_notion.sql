-- Atualiza calc.levels e calc.imc_goal_steps pra valores oficiais Notion MPP.
--
-- Bug: TS DEFAULT_CALC_CONFIG foi atualizado no commit 63f2aea mas DB ainda
-- tinha valores antigos. loadCalcConfig lê DB, não defaults — então valores
-- novos do TS não tinham efeito em produção.
--
-- IMC goal steps:
--   antes: [25, 23, 22, 21]
--   Notion: [30, 25, 23, 22, 21] — paciente com IMC 32 vai pra meta 30 (não 25)
--
-- Levels:
--   antes: 7 níveis com thresholds 0/100/250/500/1000/2000/3500
--   Notion: 8 níveis com 0/100/300/600/1000/1500/2200/3000

UPDATE global_config
SET value = '[30, 25, 23, 22, 21]'::jsonb,
    description = 'Escada oficial Notion: meta IMC desce gradualmente (margem mínima 1 ponto entre IMC atual e meta).'
WHERE key = 'calc.imc_goal_steps';

UPDATE global_config
SET value = $$[
  {"level": 1, "name": "Início", "min": 0, "max": 99},
  {"level": 2, "name": "Constância", "min": 100, "max": 299},
  {"level": 3, "name": "Foco", "min": 300, "max": 599},
  {"level": 4, "name": "Disciplina", "min": 600, "max": 999},
  {"level": 5, "name": "Performance", "min": 1000, "max": 1499},
  {"level": 6, "name": "Domínio", "min": 1500, "max": 2199},
  {"level": 7, "name": "Elite MPP", "min": 2200, "max": 2999},
  {"level": 8, "name": "Lenda MPP", "min": 3000, "max": null}
]$$::jsonb,
    description = 'Escada de níveis oficial Notion MPP: 8 níveis com thresholds 0/100/300/600/1000/1500/2200/3000.'
WHERE key = 'calc.levels';
