-- Installs an inactive scheduler in the existing Performe staging database.
-- The APNs credentials stay on the Vercel worker.
begin;
set local lock_timeout = '5s';

create table private.flow_meal_gap_cron (
  singleton boolean primary key default true check (singleton),
  worker_host text check (
    worker_host ~ '^agentempp-media-worker-staging-[a-z0-9]+-gestao-9664s-projects\.vercel\.app$'
  ),
  dispatch_sha256 text check (dispatch_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz,
  request_id bigint
);
alter table private.flow_meal_gap_cron enable row level security;
revoke all on private.flow_meal_gap_cron from public, anon, authenticated, service_role;
insert into private.flow_meal_gap_cron default values;

create function private.dispatch_flow_meal_gap_cron() returns bigint
language plpgsql set search_path = pg_catalog as $$
declare
  config private.flow_meal_gap_cron%rowtype;
  bypass text;
  token text;
  queued_request_id bigint;
begin
  select * into strict config from private.flow_meal_gap_cron where singleton for update;
  if config.worker_host is null or config.expires_at > clock_timestamp() then
    return null;
  end if;

  -- Same staging Vercel project as the existing media worker. Reuse the
  -- project-scoped protection bypass already authorized for Vault.
  select secret.decrypted_secret into bypass
  from private.conversation_media_processing_transport_v2 transport
  join vault.decrypted_secrets secret on secret.id = transport.secret_id
  where transport.singleton and transport.enabled;
  if bypass is null then
    raise exception 'Flow reminder worker protection unavailable';
  end if;

  token := encode(extensions.gen_random_bytes(32), 'hex');
  select net.http_post(
    url := 'https://' || config.worker_host || '/api/internal/flow-meal-gap',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-vercel-protection-bypass', bypass,
      'x-performe-meal-gap-token', token
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 260000
  ) into strict queued_request_id;
  update private.flow_meal_gap_cron set
    dispatch_sha256 = encode(extensions.digest(token, 'sha256'), 'hex'),
    expires_at = clock_timestamp() + interval '90 seconds',
    request_id = queued_request_id
  where singleton;
  return queued_request_id;
end $$;
revoke all on function private.dispatch_flow_meal_gap_cron() from public, anon, authenticated, service_role;

create function public.claim_flow_meal_gap_cron(p_host text, p_token_sha256 text) returns boolean
language plpgsql security definer set search_path = pg_catalog as $$
begin
  perform private.assert_trusted_backend();
  update private.flow_meal_gap_cron set
    dispatch_sha256 = null,
    expires_at = clock_timestamp() + interval '5 minutes'
  where singleton
    and worker_host = p_host
    and dispatch_sha256 = p_token_sha256
    and expires_at > clock_timestamp();
  return found;
end $$;
revoke all on function public.claim_flow_meal_gap_cron(text, text) from public, anon, authenticated;
grant execute on function public.claim_flow_meal_gap_cron(text, text) to service_role;

commit;
