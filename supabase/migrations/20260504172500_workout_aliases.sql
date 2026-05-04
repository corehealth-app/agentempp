-- ============================================================================
-- Workout Aliases — adiciona slugs alternativos comuns
-- ============================================================================
-- LLM pode mandar slugs genéricos ("musculacao", "cardio", "pernas") em vez
-- dos específicos da tabela ("peito_triceps", "perna_completa", etc).
-- Antes caía no fallback "outro" (6 kcal/min) → estimativa imprecisa.
-- Agora cada alias aponta pro kcal/min apropriado.
-- ============================================================================

INSERT INTO workout_types (slug, display_name, category, kcal_per_min, description) VALUES
  -- Musculação genérica
  ('musculacao',     'Musculação (genérico)',     'musculacao',  6.0, 'Quando o tipo específico não foi informado'),
  ('treino_a',       'Treino A',                  'musculacao',  6.0, 'Divisão genérica A'),
  ('treino_b',       'Treino B',                  'musculacao',  6.0, 'Divisão genérica B'),
  ('treino_c',       'Treino C',                  'musculacao',  6.0, 'Divisão genérica C'),
  ('pernas',         'Pernas (alias)',            'musculacao',  7.0, 'Mesmo que perna_completa'),
  ('peito',          'Peito (alias)',             'musculacao',  5.5, 'Mesmo que peito_triceps'),
  ('costas',         'Costas (alias)',            'musculacao',  5.5, 'Mesmo que costas_biceps'),
  ('ombros',         'Ombros (alias)',            'musculacao',  5.0, 'Mesmo que ombro_trapezio'),
  ('biceps_triceps', 'Bíceps e tríceps',          'musculacao',  5.0, 'Treino isolado de braços'),
  ('abdominal',      'Abdominal (alias)',         'musculacao',  4.5, 'Mesmo que abdomen'),
  ('gluteos',        'Glúteos',                   'musculacao',  6.5, 'Treino direcionado'),

  -- Cardio genérico e variações
  ('cardio',         'Cardio (genérico)',         'cardio',      8.0, 'Quando tipo cardio não informado'),
  ('aerobico',       'Aeróbico (alias)',          'cardio',      8.0, 'Termo brasileiro genérico'),
  ('esteira',        'Esteira',                   'cardio',      8.0, 'Geralmente caminhada/corrida moderada'),
  ('spinning',       'Spinning',                  'cardio',      9.0, 'Aula coletiva de bike'),
  ('corrida_leve',   'Corrida leve',              'cardio',      8.0, '~6-8 km/h'),
  ('corrida_intensa','Corrida intensa',           'cardio',     13.0, '~12-15 km/h'),
  ('remo',           'Remo / Remoergômetro',      'cardio',      9.0, 'Aparelho ou aula'),
  ('zumba',          'Zumba',                     'cardio',      7.5, 'Aula de dança'),
  ('danca',          'Dança',                     'cardio',      6.5, 'Recreativa'),

  -- Esportes adicionais
  ('jiu_jitsu',      'Jiu-jitsu (alias)',         'esporte',    10.5, 'Mesmo que luta'),
  ('bjj',            'BJJ (alias)',               'esporte',    10.5, 'Mesmo que luta'),
  ('boxe',           'Boxe (alias)',              'esporte',    10.5, 'Mesmo que luta'),
  ('muay_thai',      'Muay Thai',                 'esporte',    11.0, 'Treino técnico ou rolagem'),
  ('crossfit_wod',   'CrossFit WOD (alias)',      'musculacao',  9.0, 'Mesmo que crossfit'),
  ('funcional',      'Treino funcional (alias)',  'musculacao',  9.0, 'Mesmo que crossfit'),
  ('handstand',      'Handstand / parada de mão', 'musculacao',  6.0, 'Trabalho de calistenia'),
  ('calistenia',     'Calistenia',                'musculacao',  6.5, 'Peso corporal'),
  ('escalada',       'Escalada',                  'esporte',     9.5, 'Boulder ou top rope'),

  -- Mobilidade / leve
  ('pilates_solo',   'Pilates solo (alias)',      'mobilidade',  4.0, 'Mesmo que pilates'),
  ('mobility',       'Mobility / mobilidade',     'mobilidade',  3.0, 'Trabalho de amplitude articular'),
  ('flex',           'Flexibilidade (alias)',     'mobilidade',  2.5, 'Mesmo que alongamento')
ON CONFLICT (slug) DO NOTHING;
