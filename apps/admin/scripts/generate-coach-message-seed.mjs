import { createHash } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const inputUrl = new URL(
  '../../../content/coach-messages/bodyflow-baseline-v1.json',
  import.meta.url,
)
const defaultOutputUrl = new URL(
  '../../../supabase/migrations/00000000000000_bodyflow_coach_catalog_baseline_v1.sql',
  import.meta.url,
)

const outputArg = process.argv.find((argument) => argument.startsWith('--output='))
const outputPath = outputArg ? outputArg.slice('--output='.length) : fileURLToPath(defaultOutputUrl)

const contextAllowedVariables = {
  onboarding: ['name'],
  meal_pending: ['name', 'meal'],
  registration_confirmed: [
    'name',
    'meal',
    'protein_remaining_g',
    'kcal_remaining',
    'block_progress_percent',
  ],
  error_corrected: ['name', 'meal'],
  hydration: ['name', 'water_remaining_ml'],
  supplement: ['name', 'supplement_name'],
  medication: ['name', 'medication_name'],
  workout: ['name'],
  progress: ['name', 'protein_remaining_g', 'kcal_remaining', 'block_progress_percent'],
  day_incomplete: ['name', 'meal'],
  reevaluation: ['name', 'next_reevaluation_date'],
  reengagement: ['name'],
  trial: ['name', 'trial_days_remaining'],
  paywall: ['name'],
  return_after_abandonment: ['name'],
}

const personalities = ['balanced', 'focus', 'impulse', 'zen']
const contexts = Object.keys(contextAllowedVariables)
const channels = ['in_app', 'push', 'email']
const locales = ['pt-BR', 'en-US']

function sha256(value) {
  return createHash('sha256').update(value).digest('hex')
}

function stableUuid(key) {
  const bytes = createHash('sha256').update(`bodyflow:${key}`).digest().subarray(0, 16)
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = bytes.toString('hex')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

function sqlText(value) {
  return `'${value.replaceAll("'", "''")}'`
}

function sqlNullableText(value) {
  return value === null ? 'NULL' : sqlText(value)
}

function sqlTextArray(values) {
  return values.length === 0
    ? 'ARRAY[]::text[]'
    : `ARRAY[${values.map(sqlText).join(', ')}]::text[]`
}

function compareRenditions(left, right) {
  return (
    personalities.indexOf(left.personality) - personalities.indexOf(right.personality) ||
    contexts.indexOf(left.context) - contexts.indexOf(right.context) ||
    locales.indexOf(left.locale) - locales.indexOf(right.locale) ||
    left.variant - right.variant ||
    channels.indexOf(left.channel) - channels.indexOf(right.channel)
  )
}

function parseCatalog(source) {
  const catalog = JSON.parse(source)
  if (catalog.schema_version !== 'bodyflow.coach-catalog.v1') {
    throw new Error('Unsupported coach catalog schema version')
  }
  if (catalog.pack?.slug !== 'bodyflow-baseline-v1' || !Array.isArray(catalog.groups)) {
    throw new Error('Invalid baseline coach catalog root')
  }

  const groupKeys = new Set()
  const renditions = []
  for (const group of catalog.groups) {
    if (
      !personalities.includes(group.personality) ||
      !contexts.includes(group.context) ||
      !locales.includes(group.locale) ||
      !Array.isArray(group.variants) ||
      group.variants.length !== 3
    ) {
      throw new Error(`Invalid coach catalog group: ${JSON.stringify(group)}`)
    }

    const groupKey = `${group.personality}:${group.context}:${group.locale}`
    if (groupKeys.has(groupKey)) throw new Error(`Duplicate coach catalog group: ${groupKey}`)
    groupKeys.add(groupKey)

    for (const [index, variant] of group.variants.entries()) {
      if (variant.variant !== index + 1 || !Array.isArray(variant.required_variables)) {
        throw new Error(`Invalid variant ordering for ${groupKey}`)
      }
      const allowed = contextAllowedVariables[group.context]
      if (variant.required_variables.some((variable) => !allowed.includes(variable))) {
        throw new Error(`Unknown required variable for ${groupKey}:v${variant.variant}`)
      }

      for (const channel of channels) {
        const rendition = variant.renditions?.[channel]
        if (!rendition || typeof rendition.body !== 'string' || rendition.body.length === 0) {
          throw new Error(`Missing ${channel} rendition for ${groupKey}:v${variant.variant}`)
        }
        const title = channel === 'push' ? rendition.title : null
        const subject = channel === 'email' ? rendition.subject : null
        if (
          (channel === 'push' && typeof title !== 'string') ||
          (channel === 'email' && typeof subject !== 'string')
        ) {
          throw new Error(`Missing channel heading for ${groupKey}:${channel}:v${variant.variant}`)
        }
        renditions.push({
          personality: group.personality,
          context: group.context,
          channel,
          locale: group.locale,
          variant: variant.variant,
          allowedVariables: allowed,
          requiredVariables: variant.required_variables,
          title,
          subject,
          body: rendition.body,
        })
      }
    }
  }

  if (groupKeys.size !== 120 || renditions.length !== 1080) {
    throw new Error(
      `Expected 120 groups and 1,080 renditions; received ${groupKeys.size} and ${renditions.length}`,
    )
  }

  return { catalog, renditions: renditions.sort(compareRenditions) }
}

function buildSql(source) {
  const sourceSha = sha256(source)
  const { catalog, renditions } = parseCatalog(source)
  const packId = stableUuid(`pack:${catalog.pack.slug}`)

  const templateRows = []
  const versionRows = []
  const entryRows = []

  for (const rendition of renditions) {
    const localeKey = rendition.locale.toLowerCase().replace('-', '_')
    const templateKey = [
      'bodyflow',
      rendition.personality,
      rendition.context,
      rendition.channel,
      localeKey,
      `v${rendition.variant}`,
    ].join('.')
    const templateId = stableUuid(`template:${templateKey}`)
    const versionKey = [
      rendition.title ?? '',
      rendition.subject ?? '',
      rendition.body,
      templateKey,
    ].join('|')
    const contentHash = sha256(versionKey)
    const versionId = stableUuid(`version:${templateKey}:1:${contentHash}`)

    templateRows.push(
      `  (${[
        sqlText(templateId),
        sqlText(templateKey),
        sqlText(rendition.personality),
        sqlText(rendition.context),
        sqlText(rendition.channel),
        sqlText(rendition.locale),
        rendition.variant,
        sqlTextArray(rendition.allowedVariables),
        sqlTextArray(rendition.requiredVariables),
      ].join(', ')})`,
    )

    versionRows.push(
      `  (${[
        sqlText(versionId),
        sqlText(templateId),
        1,
        sqlNullableText(rendition.title),
        sqlNullableText(rendition.subject),
        sqlText(rendition.body),
        sqlText('active'),
        sqlText('seed'),
        sqlText(contentHash),
      ].join(', ')})`,
    )

    entryRows.push(`  (${sqlText(packId)}, ${sqlText(templateId)}, ${sqlText(versionId)})`)
  }

  return `-- Generated by apps/admin/scripts/generate-coach-message-seed.mjs.
-- Source: content/coach-messages/bodyflow-baseline-v1.json
-- Source SHA-256: ${sourceSha}
-- Do not edit this migration by hand; edit the reviewed catalog source instead.

DO $precondition$
BEGIN
  IF EXISTS (SELECT 1 FROM public.coach_content_packs WHERE status = 'active') THEN
    RAISE EXCEPTION 'baseline coach catalog requires no existing active pack'
      USING ERRCODE = '23514';
  END IF;
END;
$precondition$;

INSERT INTO public.coach_content_packs (id, slug, label, status)
VALUES (${sqlText(packId)}, ${sqlText(catalog.pack.slug)}, ${sqlText(catalog.pack.label)}, 'draft');

INSERT INTO public.coach_message_templates (
  id,
  template_key,
  personality_code,
  context,
  channel,
  locale,
  variant,
  allowed_variables,
  required_variables
)
VALUES
${templateRows.join(',\n')};

INSERT INTO public.coach_message_template_versions (
  id,
  template_id,
  version,
  title,
  subject,
  body,
  status,
  provenance,
  content_hash
)
VALUES
${versionRows.join(',\n')};

INSERT INTO public.coach_content_pack_entries (
  pack_id,
  template_id,
  template_version_id
)
VALUES
${entryRows.join(',\n')};

DO $validation$
DECLARE
  v_pack_id constant uuid := ${sqlText(packId)};
BEGIN
  IF (SELECT count(*) FROM public.coach_content_pack_entries WHERE pack_id = v_pack_id) <> 1080
    OR (
      SELECT count(*)
      FROM public.coach_message_template_versions version
      JOIN public.coach_content_pack_entries entry ON entry.template_version_id = version.id
      WHERE entry.pack_id = v_pack_id
        AND version.status = 'active'
        AND version.provenance = 'seed'
    ) <> 1080 THEN
    RAISE EXCEPTION 'generated baseline coach catalog is incomplete'
      USING ERRCODE = '23514';
  END IF;
END;
$validation$;

UPDATE public.coach_content_packs
SET status = 'active',
    effective_at = clock_timestamp(),
    activated_at = clock_timestamp(),
    updated_at = clock_timestamp()
WHERE id = ${sqlText(packId)};
`
}

const source = await readFile(inputUrl, 'utf8')
const sql = buildSql(source)
await writeFile(outputPath, sql, 'utf8')
process.stdout.write(`${sha256(sql)}  ${outputPath}\n`)
