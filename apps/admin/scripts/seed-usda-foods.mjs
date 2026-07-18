#!/usr/bin/env node

// Deprecated on 2026-07-18. This script previously asked an LLM to generate
// values "based on USDA" and then stored them as USDA_seed_llm. That is not
// auditable nutritional provenance and must never populate the canonical table.
// Official SR Legacy values now ship through versioned Supabase migrations.

process.stderr.write(
  'seed-usda-foods.mjs is disabled: use the verified USDA FoodData Central migration generator.\n',
)
process.exitCode = 1
