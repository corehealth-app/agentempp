# Prepared-food references in app consumption

The existing `consumed-meal-v1` opt-in can use a named prepared-food reference when the person or photo names the whole food without a recipe. This follows the approved approximate, editable prepared-dish policy. It does not change the legacy resolver.

The first prepared reference is bare **farofa**, shown and saved as **farofa de mandioca temperada**. The staging catalogue verified on 13 November 2026 contains `food_db:288`, `TACO4:131`, `Mandioca, farofa, temperada`: 405.69 kcal, 2.06 g protein, 80.30 g carbohydrate and 9.12 g fat per 100 g. The calculator reads the catalogue row again and requires the exact name and those four values. The source file is a guard, never an alternative numeric source. Missing or changed references fail closed.

This is a disclosed reference assumption, not a claim that the user's recipe was identified or that Roberto specified these ingredients. The specific reference remains marked `confirmation_pending`. The returned warning describes the estimate and allows correction. It never emits a `default_cooked` annotation for farofa.

Only the full aliases in `consumed-food-defaults.ts` match, only in Brazil and only with the explicit consumption policy. Explicit variants such as farofa de milho, additions, brands and negations do not lose words to this default. Original-name active personal corrections, approved label nutrition and manual values retain precedence, including an explicit manual zero. Multiple source occurrences retain their calculator input mapping; distinct commands are still distinct consumptions.

Text, processed photos, transcripts and item edits use this same calculator boundary. No recipe, calorie value or user record is added to the database by configuring the reference. Existing historical receipts are not recalculated.
