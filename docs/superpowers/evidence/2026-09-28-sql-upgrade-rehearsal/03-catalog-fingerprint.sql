-- Catalog fingerprint of the objects M1-M4 touch or create. Two databases
-- with the same output have the same schema for these objects. Read-only.
SELECT 'functions' AS part, md5(string_agg(sig || ' ' || md5(pg_get_functiondef(oid)) || ' ' || coalesce(proacl::text, ''), E'\n' ORDER BY sig))
FROM (
  SELECT p.oid, p.proacl, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
) f
UNION ALL
SELECT 'columns', md5(string_agg(format('%s.%s %s %s %s', table_name, column_name, data_type, is_nullable, coalesce(column_default, '')), E'\n' ORDER BY table_name, column_name))
FROM information_schema.columns WHERE table_schema = 'public'
UNION ALL
SELECT 'constraints', md5(string_agg(conrelid::regclass::text || ' ' || conname || ' ' || pg_get_constraintdef(oid), E'\n' ORDER BY conrelid::regclass::text, conname))
FROM pg_constraint WHERE connamespace = 'public'::regnamespace
UNION ALL
SELECT 'indexes', md5(string_agg(indexdef, E'\n' ORDER BY indexdef))
FROM pg_indexes WHERE schemaname = 'public'
UNION ALL
SELECT 'triggers', md5(string_agg(tgrelid::regclass::text || ' ' || tgname, E'\n' ORDER BY tgrelid::regclass::text, tgname))
FROM pg_trigger WHERE NOT tgisinternal
UNION ALL
SELECT 'table_acl', md5(string_agg(c.relname || ' ' || coalesce(c.relacl::text, '') || ' rls=' || c.relrowsecurity, E'\n' ORDER BY c.relname))
FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
UNION ALL
SELECT 'policies', md5(string_agg(tablename || ' ' || policyname || ' ' || coalesce(qual, '') || ' ' || coalesce(with_check, ''), E'\n' ORDER BY tablename, policyname))
FROM pg_policies WHERE schemaname = 'public'
UNION ALL
SELECT 'buckets', md5(string_agg(id || ' ' || public::text || ' ' || coalesce(file_size_limit::text, '') || ' ' || coalesce(allowed_mime_types::text, ''), E'\n' ORDER BY id))
FROM storage.buckets
ORDER BY 1;
