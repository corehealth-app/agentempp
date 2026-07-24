CREATE INDEX entitlement_events_entitlement_id_idx
  ON public.entitlement_events (entitlement_id)
  WHERE entitlement_id IS NOT NULL;
