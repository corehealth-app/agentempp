# Recorded training window

`GET /api/mobile/v1/training/window?clinical_policy=current_clinical_v1[&date=YYYY-MM-DD]`

This additive reader returns `training.window.v1` from existing owned `workout_logs`. No new database objects, registration, estimate, daily closer, reward or model call is involved. The required clinical representation follows existing current-clinical readers. The optional date selects a Monday–Sunday civil week in the official account timezone; omitting it selects the official current date. It does not use the device clock to assign a workout to a day.

The response includes original Auth/domain/epoch identity, timezone, official current and selected dates, week bounds, observation timestamp, current clinical policy, stable source fingerprint and seven ordered days. Each day contains actual saved activity identifiers, type, duration in minutes, estimated kcal, intensity and original timestamp. Nullable facts remain unknown; a plan is never represented as completed. Exercise never increases the food budget.

The repository requests an exact count and at most 1,001 rows. Missing/truncated counts, more than 1,000 records, duplicates, foreign-owner rows, invalid dates/amounts or future timestamps refuse a complete response. Two row captures must match; clinical scope is observed before and after, followed by original Auth and entitlement revalidation. Changed rows, owner, epoch, timezone, current day or policy reject the observation rather than returning mixed facts. The fingerprint is independent of query row order and includes all returned facts.

The iOS reader retains the original Auth generation. Logout/session replacement invalidates it. A changed same-owner epoch/timezone requires an explicit fresh read binding, which conveys no write authority. The Treino tab distinguishes Realizado (Dia/Semana) from the existing Plano. Missing authority displays unavailable/retry rather than an empty confirmed day. Tab changes, refresh, scene activation and existing registration invalidations trigger fresh reads.

The common clinical scope parser/calendar was extracted from the existing nutrition reader without changing its schema or date behavior. The compiled server still contains the same frozen shared nutrition/journal modules; the new read-only training entry is an explicitly enumerated additional consumer. All pre-training 92 route exports and 92/93 route-path inventories remain pinned, as do historical module-body certificates. No writer or worker namespace is newly exposed.

This is one T5 slice. Persistent per-exercise execution (sets/reps/load), sharing, social Jornada, connected staging qualification and distribution are separate remaining gates. Local test success does not establish deployment or Roberto acceptance.
