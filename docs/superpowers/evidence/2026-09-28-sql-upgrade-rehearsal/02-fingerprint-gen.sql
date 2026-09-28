-- Generates the fingerprint query from the columns that exist NOW (run it on
-- the pre-M1 baseline). The generated query hashes only those columns, so
-- the same query run after the upgrade proves legacy rows are unchanged.
-- Read-only. LOCAL REHEARSAL ONLY.
SELECT string_agg(
  format(
    'SELECT %L AS table_name, count(*) AS row_count, md5(coalesce(string_agg(row_text, E''\n'' ORDER BY row_text), '''')) AS rows_md5 FROM (SELECT concat_ws(''|'', %s) AS row_text FROM public.%I) s',
    table_name,
    cols,
    table_name
  ),
  E'\nUNION ALL\n' ORDER BY table_name
) || E'\nORDER BY 1;'
FROM (
  SELECT c.table_name, string_agg(format('%I::text', c.column_name), ', ' ORDER BY c.ordinal_position) AS cols
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name IN (
      'users', 'user_profiles', 'media_assets', 'messages',
      'prescriptions', 'training_plans', 'meal_logs', 'daily_snapshots'
    )
  GROUP BY c.table_name
) t;
