// Run from an installed workspace: node scripts/mobile/generate-feedback-v2-ios-fixtures.mjs
// Synthetic public facts only. Rebuild expected native output using the pinned canonical TS reader.
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = fileURLToPath(new URL('../../', import.meta.url))
const require = createRequire(new URL('../../packages/agent/package.json', import.meta.url))
const ts = require('typescript')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'feedback-v2-ios-fixtures-'))
const sourcePath = 'supabase/tests/fixtures/mobile_registration_feedback_v2_contract.sql'
const rendererPath = 'packages/agent/src/registration-feedback-v2.ts'
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const sha256 = (value) => createHash('sha256').update(value).digest('hex')
try {
  fs.writeFileSync(path.join(temporary, 'package.json'), JSON.stringify({ type: 'module' }))
  fs.mkdirSync(path.join(temporary, 'node_modules'))
  fs.symlinkSync(path.dirname(require.resolve('zod/package.json')), path.join(temporary, 'node_modules/zod'))
  for (const name of ['registration-feedback-v2', 'flow-current-clinical']) {
    const result = ts.transpileModule(read(`packages/agent/src/${name}.ts`), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
    })
    fs.writeFileSync(path.join(temporary, `${name}.js`), result.outputText)
  }
  const { parseRegistrationFeedbackV2, renderRegistrationFeedbackV2 } = await import(
    pathToFileURL(path.join(temporary, 'registration-feedback-v2.js')).href
  )
  const sql = read(sourcePath)
  const cases = [...sql.matchAll(/INSERT INTO feedback_v2_contract_cases VALUES \('([^']+)',\$v2fixture\$(.*?)\$v2fixture\$::jsonb\);/g)]
    .map(([, label, json]) => ({ label, payload: JSON.parse(json) }))
  if (cases.length !== 141) throw new Error('Review changed canonical fixture count before regeneration')
  const base = (locale = 'pt-BR') => structuredClone(cases.find((item) => item.label === `milk_whey/${locale}/false/recomposicao`).payload)
  const add = (label, payload) => cases.push({ label, payload })
  for (const locale of ['pt-BR', 'en']) {
    const units = base(locale)
    units.registration.items = [
      { log_id: 'c2b00000-0000-4000-8000-000000000002', food_name: 'leite integral', quantity_g: 206,
        quantity: { value: 200, unit: 'mL', estimated: true, reference_id: 'fao-infoods-v2-whole-milk-tb' },
        kcal: 126, protein_g: 6.3, carbs_g: 9.5, fat_g: 6.5, nutrition_source: 'canonical_exact' },
      { log_id: 'c2b00000-0000-4000-8000-000000000003', food_name: 'whey protein', quantity_g: 30,
        quantity: { value: 1, unit: 'scoop', estimated: true, reference_id: 'app-household-whey-scoop-v1' },
        kcal: 120, protein_g: 23.6, carbs_g: 4, fat_g: 1.5, nutrition_source: 'canonical_exact' },
    ]
    units.registration.totals = { kcal: 246, protein_g: 29.9, carbs_g: 13.5, fat_g: 8 }
    add(`native/milk-whey-units/${locale}`, units)
    for (const value of [1, 2]) {
      const unit = base(locale)
      unit.registration.items = [{ ...unit.registration.items[0], food_name: 'ovo', quantity_g: 50 * value,
        quantity: { value, unit: 'unit', estimated: true, reference_id: 'app-household-egg-unit-v1' } }]
      unit.education = { status: 'unavailable' }
      add(`native/unit-${value}/${locale}`, unit)
    }
    const scoops = structuredClone(units)
    scoops.registration.items[1].quantity.value = 2
    scoops.registration.items[1].quantity_g = 60
    // Deliberately retain the independently saved canonical totals; never derive them on the client.
    add(`native/plural-scoop/${locale}`, scoops)
  }
  for (const target of ['both', 'calories', 'protein']) {
    const receipt = base()
    if (target !== 'protein') {
      receipt.day.targets.calories_kcal = null
      receipt.day.calorie_percentage = null
      receipt.day.remaining_food_kcal = null
      receipt.day.food_excess_kcal = null
    }
    if (target !== 'calories') {
      receipt.day.targets.protein_g = null
      receipt.day.protein_percentage = null
    }
    add(`native/no-${target}-target`, receipt)
  }
  const workout = structuredClone(cases.find((item) => item.label === 'activity_walking/pt-BR/false/recomposicao').payload)
  workout.registration.duration_min = null
  workout.registration.intensity = null
  workout.registration.estimated_kcal = null
  workout.education = { status: 'unavailable' }
  add('native/workout-unavailable-facts', workout)
  const noEducation = base()
  noEducation.education = { status: 'unavailable' }
  add('native/education-unavailable', noEducation)
  for (const item of cases) {
    item.payload = parseRegistrationFeedbackV2(item.payload, {
      registrationId: item.payload.registration_id, kind: item.payload.registration.kind,
    })
    item.sections = renderRegistrationFeedbackV2(item.payload)
  }
  const metadata = { source: sourcePath, source_sha256: sha256(sql), renderer: rendererPath,
    renderer_sha256: sha256(read(rendererPath)), canonical_cases: 141 }
  const output = `${JSON.stringify(metadata, null, 2).slice(0, -2)},\n  "cases": [\n${cases.map((item) => `    ${JSON.stringify(item)}`).join(',\n')}\n  ]\n}\n`
  fs.writeFileSync(path.join(root, 'apps/ios/BodyFlow/BodyFlowTests/Fixtures/RegistrationFeedbackV2Fixtures.json'), output)
  process.stdout.write(`Generated ${cases.length} native cases (141 canonical SQL + ${cases.length - 141} supplemental)\n`)
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
