CREATE TRIGGER reminder_rules_normalize_and_validate
BEFORE INSERT OR UPDATE OF routine_item_id, category, active, weekdays
ON public.reminder_rules
FOR EACH ROW
EXECUTE FUNCTION private.normalize_and_validate_reminder_rule();

CREATE UNIQUE INDEX reminder_rules_active_logical_unique
ON public.reminder_rules (
  user_id,
  category,
  COALESCE(meal_type, ''),
  COALESCE(routine_item_id, '00000000-0000-0000-0000-000000000000'::uuid),
  local_time,
  weekdays,
  COALESCE(template_key, '')
)
WHERE active;

REVOKE ALL ON FUNCTION private.normalize_and_validate_reminder_rule()
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION private.normalize_and_validate_reminder_rule() IS
  'Canonicalizes reminder weekdays and rejects active rules for inactive routine items.';
