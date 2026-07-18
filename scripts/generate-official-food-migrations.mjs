#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { createReadStream, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { createInterface } from 'node:readline'

const EXPECTED_USDA_SHA256 = 'b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0'
const EXPECTED_TACO_SHA256 = 'a66b8ec528daeabc63bc2b015fc9bd8c6d76b941c2fc0ed93a4311d449302d14'

// TACO IV's official workbook contains one malformed food label: item 540 is
// literally "L". Its nutrient values cannot be attached to a real food name,
// so importing it would create an unsafe fuzzy-match target. Keep the exclusion
// explicit and fail if the upstream row changes, rather than silently filtering
// arbitrary short names.
const TACO_MALFORMED_ROWS = new Map([[540, 'L']])

function argsFrom(argv) {
  const result = new Map()
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]
    const value = argv[index + 1]
    if (!key?.startsWith('--') || !value) throw new Error(`invalid argument near ${key ?? 'end'}`)
    result.set(key.slice(2), value)
  }
  return result
}

function required(args, name) {
  const value = args.get(name)
  if (!value) throw new Error(`missing --${name}`)
  return value
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

function assertSha(path, expected, label) {
  const actual = sha256(path)
  if (actual !== expected) throw new Error(`${label} checksum mismatch: ${actual}`)
}

function parseCsvLine(line) {
  const fields = []
  let field = ''
  let quoted = false
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index]
    if (char === '"') {
      if (quoted && line[index + 1] === '"') {
        field += '"'
        index += 1
      } else {
        quoted = !quoted
      }
    } else if (char === ',' && !quoted) {
      fields.push(field)
      field = ''
    } else {
      field += char
    }
  }
  fields.push(field.replace(/\r$/, ''))
  return fields
}

async function csvRows(path) {
  const rows = []
  const input = createInterface({ input: createReadStream(path), crlfDelay: Infinity })
  let header = null
  for await (const line of input) {
    const fields = parseCsvLine(line)
    if (!header) {
      header = fields
      continue
    }
    rows.push(Object.fromEntries(header.map((name, index) => [name, fields[index] ?? ''])))
  }
  return rows
}

function decodeXml(value) {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
}

function sharedStrings(path) {
  const xml = readFileSync(path, 'utf8')
  return [...xml.matchAll(/<si(?:\s[^>]*)?>([\s\S]*?)<\/si>/g)].map((match) =>
    decodeXml(
      [...match[1].matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map((part) => part[1]).join(''),
    ),
  )
}

function worksheetRows(path, strings) {
  const xml = readFileSync(path, 'utf8')
  const rows = []
  for (const rowMatch of xml.matchAll(/<row(?:\s[^>]*)?>([\s\S]*?)<\/row>/g)) {
    const row = {}
    for (const cellMatch of rowMatch[1].matchAll(/<c\s([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attributes = cellMatch[1]
      const reference = attributes.match(/\br="([A-Z]+)\d+"/)?.[1]
      const raw = cellMatch[2].match(/<v>([\s\S]*?)<\/v>/)?.[1]
      if (!reference || raw == null) continue
      row[reference] = /\bt="s"/.test(attributes) ? strings[Number(raw)] : raw
    }
    rows.push(row)
  }
  return rows
}

function tacoNumber(value) {
  if (value == null || value === '') return null
  const normalized = String(value).trim().replace(',', '.')
  if (/^tr$/i.test(normalized)) return 0
  const number = Number(normalized)
  return Number.isFinite(number) ? number : null
}

function nonNegativeTrace(value) {
  if (value == null) return null
  return value < 0 && value >= -0.1 ? 0 : value
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`
}

function sqlNumber(value) {
  if (value == null || !Number.isFinite(value)) return 'NULL'
  return String(Math.round(value * 100) / 100)
}

function normalizedName(value) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
}

function deduplicate(rows, country) {
  const unique = new Map()
  for (const row of rows) {
    const key = `${country}:${normalizedName(row.name)}`
    if (!unique.has(key)) unique.set(key, row)
  }
  return [...unique.values()]
}

function validateCatalogRows(rows, label) {
  const sourceRefs = new Set()
  for (const row of rows) {
    if (
      typeof row.name !== 'string' ||
      row.name.trim().length < 3 ||
      !/[A-Za-z\u00c0-\u024f]/.test(row.name)
    ) {
      throw new Error(`${label} has an invalid food name: ${JSON.stringify(row.name)}`)
    }
    if (!row.sourceRef || sourceRefs.has(row.sourceRef)) {
      throw new Error(`${label} has a missing or duplicate source reference: ${row.sourceRef}`)
    }
    sourceRefs.add(row.sourceRef)

    const bounds = [
      ['kcal', row.kcal, 955],
      ['protein', row.protein, 100],
      ['carbs', row.carbs, 100],
      ['fat', row.fat, 100],
      ['fiber', row.fiber, 100],
    ]
    for (const [field, value, maximum] of bounds) {
      if (value != null && (!Number.isFinite(value) || value < 0 || value > maximum)) {
        throw new Error(`${label} ${row.sourceRef} has invalid ${field}: ${value}`)
      }
    }
    if (row.protein + row.carbs + row.fat > 115) {
      throw new Error(`${label} ${row.sourceRef} has impossible macro mass`)
    }
  }
  return rows
}

function migrationSql({ title, sourceUrl, checksum, source, country, rows }) {
  const chunks = []
  const chunkSize = 250
  for (let offset = 0; offset < rows.length; offset += chunkSize) {
    const values = rows
      .slice(offset, offset + chunkSize)
      .map((row) =>
        [
          sqlText(row.name),
          sqlText(row.category),
          sqlNumber(row.kcal),
          sqlNumber(row.protein),
          sqlNumber(row.carbs),
          sqlNumber(row.fat),
          sqlNumber(row.fiber),
          sqlText(source),
          sqlText(country),
          'true',
          sqlText(row.sourceRef),
        ].join(', '),
      )
    chunks.push(`INSERT INTO public.food_db AS existing (
  name_pt, category, kcal_per_100g, protein_g, carbs_g, fat_g, fiber_g,
  source, country_code, is_verified, source_ref
) VALUES
  (${values.join('),\n  (')})
ON CONFLICT (name_norm, country_code) DO UPDATE SET
  category = EXCLUDED.category,
  kcal_per_100g = EXCLUDED.kcal_per_100g,
  protein_g = EXCLUDED.protein_g,
  carbs_g = EXCLUDED.carbs_g,
  fat_g = EXCLUDED.fat_g,
  fiber_g = EXCLUDED.fiber_g,
  source = EXCLUDED.source,
  is_verified = true,
  source_ref = EXCLUDED.source_ref
WHERE existing.is_verified IS FALSE
   OR existing.source = EXCLUDED.source
   OR existing.source LIKE 'TACO%';`)
  }

  return `-- ${title}
-- Source: ${sourceUrl}
-- Download SHA-256: ${checksum}
-- Generated by scripts/generate-official-food-migrations.mjs.
-- Imported rows: ${rows.length}. Values are per 100 g edible portion.

${chunks.join('\n\n')}
`
}

async function loadUsda(dataDir) {
  const categories = new Map(
    (await csvRows(join(dataDir, 'food_category.csv'))).map((row) => [row.id, row.description]),
  )
  const foods = new Map(
    (await csvRows(join(dataDir, 'food.csv'))).map((row) => [
      row.fdc_id,
      {
        id: Number(row.fdc_id),
        name: row.description,
        category: categories.get(row.food_category_id) ?? 'Uncategorized',
        nutrients: new Map(),
      },
    ]),
  )
  const wanted = new Set(['1003', '1004', '1005', '1008', '1079'])
  for (const row of await csvRows(join(dataDir, 'food_nutrient.csv'))) {
    if (!wanted.has(row.nutrient_id)) continue
    const food = foods.get(row.fdc_id)
    const amount = Number(row.amount)
    if (food && Number.isFinite(amount)) food.nutrients.set(row.nutrient_id, amount)
  }

  return deduplicate(
    [...foods.values()]
      .filter((food) => ['1003', '1004', '1005', '1008'].every((id) => food.nutrients.has(id)))
      .sort((left, right) => left.id - right.id)
      .map((food) => ({
        name: food.name,
        category: food.category,
        kcal: food.nutrients.get('1008'),
        protein: food.nutrients.get('1003'),
        carbs: food.nutrients.get('1005'),
        fat: food.nutrients.get('1004'),
        fiber: food.nutrients.get('1079') ?? null,
        sourceRef: `FDC:${food.id}`,
      })),
    'US',
  )
}

function loadTaco(extractedDir) {
  const strings = sharedStrings(join(extractedDir, 'xl/sharedStrings.xml'))
  const rows = worksheetRows(join(extractedDir, 'xl/worksheets/sheet1.xml'), strings)
  const foods = []
  let category = 'Sem categoria'
  for (const row of rows) {
    const id = Number(row.A)
    if (!Number.isInteger(id)) {
      if (typeof row.A === 'string' && row.A.trim() && !row.B) category = row.A.trim()
      continue
    }
    const name = String(row.B ?? '').trim()
    const kcal = tacoNumber(row.D)
    // TACO contains four analytical/difference residuals between -0.01 g and
    // -0.05 g. They represent a trace after rounding, not negative nutrient
    // mass, so normalize only that narrow range to zero.
    const protein = nonNegativeTrace(tacoNumber(row.F))
    const fat = nonNegativeTrace(tacoNumber(row.G))
    const carbs = nonNegativeTrace(tacoNumber(row.I))
    const fiber = nonNegativeTrace(tacoNumber(row.J))
    const hasRequiredNutrition = ![kcal, protein, fat, carbs].some((value) => value == null)
    if (!name || !hasRequiredNutrition) {
      if (!name && hasRequiredNutrition) {
        throw new Error(`TACO row ${id} has nutrition without a food name`)
      }
      continue
    }
    const malformedName = TACO_MALFORMED_ROWS.get(id)
    if (malformedName != null) {
      if (name !== malformedName) {
        throw new Error(`TACO row ${id} changed: expected malformed name ${malformedName}`)
      }
      continue
    }
    if (name.length < 3 || !/[A-Za-z\u00c0-\u024f]/.test(name)) {
      throw new Error(`TACO row ${id} has an invalid food name: ${JSON.stringify(name)}`)
    }
    foods.push({
      name,
      category,
      kcal,
      protein,
      carbs,
      fat,
      fiber,
      sourceRef: `TACO4:${id}`,
    })
  }
  return deduplicate(foods, 'BR')
}

const args = argsFrom(process.argv.slice(2))
const usdaZip = required(args, 'usda-zip')
const tacoXlsx = required(args, 'taco-xlsx')
assertSha(usdaZip, EXPECTED_USDA_SHA256, 'USDA SR Legacy')
assertSha(tacoXlsx, EXPECTED_TACO_SHA256, 'TACO IV')

const tacoRows = validateCatalogRows(loadTaco(required(args, 'taco-dir')), 'TACO IV')
const usdaRows = validateCatalogRows(await loadUsda(required(args, 'usda-dir')), 'USDA SR Legacy')

writeFileSync(
  required(args, 'taco-out'),
  migrationSql({
    title: 'Official TACO IV food composition catalog',
    sourceUrl: 'https://nepa.unicamp.br/publicacoes/tabela-taco-excel/',
    checksum: EXPECTED_TACO_SHA256,
    source: 'TACO_IV_OFFICIAL_2011',
    country: 'BR',
    rows: tacoRows,
  }),
)

writeFileSync(
  required(args, 'usda-out'),
  migrationSql({
    title: 'Official USDA FoodData Central SR Legacy catalog',
    sourceUrl: 'https://fdc.nal.usda.gov/download-datasets/',
    checksum: EXPECTED_USDA_SHA256,
    source: 'USDA_FDC_SR_LEGACY_2018',
    country: 'US',
    rows: usdaRows,
  }),
)

process.stdout.write(`generated ${tacoRows.length} TACO rows and ${usdaRows.length} USDA rows\n`)
