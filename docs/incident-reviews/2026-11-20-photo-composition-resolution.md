# Photo composition resolution — 20 November 2026

The second photo failure was a new, processed intake, not a stale screenshot.
The strict materializer required a whole catalogue name for `pão francês aberto com ovo frito e cebola` and `pão francês aberto com ovo mexido`. The plain bread alias did not cover either composition. No meal was persisted for that refused intake.

The materializer and consumed-meal calculator now share a bounded ingredient parser. All components must qualify in the verified catalogue before materialization. The original whole name, mass and visual indexes remain intact. The calculator aggregates the existing proportional estimate and exposes total grams, never an inferred number of eggs. V2/V3 presentations explicitly disclose approximate editable ingredient proportions. Individual French-bread, fried-egg, scrambled-egg and onion aliases refer to existing verified TACO/FDC rows; no recipe-specific nutrition values or database migration are introduced.

Whole-item catalogue matches retain precedence. Existing standalone cooked/prepared defaults are not extended silently to recipes. Existing prepared-dish and milk/whey recovery paths retain their policies. Unknown or qualified variants are not reduced to an unrelated known noun; unknown components cannot receive the entire mass through partial redistribution in this new resolver. An unresolved ingredient still requires a targeted answer rather than recording zero.

Regression coverage includes both actual visual descriptions with US and BR context, source-position/mass preservation, generic banana/oats compositions, unknown components, integral/brand qualifiers, milk/whey and prior prepared-food behavior. Test masses are synthetic and are not measurements of Roberto's photo. Native tests cover both feedback versions and linked conversation presentation. The complete build graph retains 383 unique modules and 425 physical copies; four changed complete bodies are recertified without removing global scans or tampering controls.

Release qualification must additionally exercise an actual composed-food photo through the deployed media worker and iOS client, persistence/reopen, correction, and duplicate retry. Passing local tests alone does not certify the distributed build. Customer source media and customer meals must remain untouched.
