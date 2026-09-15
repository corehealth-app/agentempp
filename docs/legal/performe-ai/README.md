# Performe AI — Legal Draft Package

STATUS: DRAFT
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

## Purpose and limits

This directory is a professional working package for legal, privacy, product, and operational review. It does not constitute legal advice, certification of compliance, approval by a controller, approval by Apple, publication, effectiveness, or evidence that any user has accepted a document.

The pt-BR documents are currently the source drafts. The English documents are semantic translations and must be revalidated after every legal change to the pt-BR source. Performe AI and Flow are proper names and are not translated.

## Contents

- Terms of Use, Privacy Policy, Health and AI Notice, Sensitive Health Data Consent, Media Processing Notice, and onboarding legal copy in pt-BR and English.
- An activation checklist, unresolved-decision register, processor inventory template, retention matrix template, and document manifest template.

## Relationship to server-owned onboarding

The implemented onboarding obtains current requirements from the trusted backend, presents server-owned document identity and action semantics, and records exact actions only after server validation. In the absence of approved, published, effective documents and a complete requirement set, Release must remain fail-closed.

No file in this directory may be copied into the operational catalog merely because it exists in Git. Draft text, a review comment, a local file hash, or a technical commit is not approval or publication.

## Recommended activation sequence

`legal and business decisions → qualified legal review → text approval → translation review → freeze exact UTF-8 bytes → calculate final runtime hash → publish through a controlled origin or approved embedded body → apply staging migration → insert immutable documents → publish the complete requirement set → deploy BFF/client → Release staging E2E → UAT → separate production authorization`

The detailed gates are in `legal-activation-checklist.md`. This package does not certify conformity with the LGPD and does not mark any legal or operational gate as passed.

## Unresolved identity fields

- `[PENDENTE — ENTIDADE JURÍDICA]` / `[PENDING — LEGAL ENTITY]`
- `[PENDENTE — CNPJ]` / `[PENDING — BRAZILIAN CORPORATE TAX ID (CNPJ)]`
- `[PENDENTE — ENDEREÇO]` / `[PENDING — ADDRESS]`
- `[PENDENTE — E-MAIL DE SUPORTE]` / `[PENDING — SUPPORT EMAIL]`
- `[PENDENTE — CANAL DE PRIVACIDADE]` / `[PENDING — PRIVACY CONTACT CHANNEL]`
- `[PENDENTE — ENCARREGADO/DPO, SE APLICÁVEL]` / `[PENDING — DATA PROTECTION OFFICER/DPO, IF APPLICABLE]`
- `[PENDENTE — DOMÍNIO OFICIAL]` / `[PENDING — OFFICIAL DOMAIN]`
- `[PENDENTE — DATA DE APROVAÇÃO]` / `[PENDING — APPROVAL DATE]`
- `[PENDENTE — DATA DE VIGÊNCIA]` / `[PENDING — EFFECTIVE DATE]`

Historical references to CoreHealth and PIPER AUTOMAÇÕES E INTEGRAÇÕES LTDA / PIPER HUB do not establish which entity is the controller, contracting supplier, App Store seller, brand/domain owner, support contact, privacy contact, or incident-response owner. Those decisions remain open.

## Future legal entity decision

The intended future responsible entity will be a third company that has not yet been incorporated. Its internal-only representation is `[FUTURE LEGAL ENTITY — NOT YET INCORPORATED]`; it has no legal name, CNPJ, or incorporation date today. The placeholder is not a legal person and must never appear in a user-facing or published document.

PIPER AUTOMAÇÕES E INTEGRAÇÕES LTDA. / PiperHub and CoreHealth are not approved as controller, App Store seller, user contracting entity, or legal owner for Performe AI. PIPER/PiperHub may remain a historical provider/developer description where supported by evidence, without assigning a broader role.

Consequently, `REAL USER LEGAL ACTIVATION: BLOCKED`. This block remains until incorporation, role decisions, legal review, approval, and all activation gates are complete. It does not prevent local or strictly isolated synthetic QA testing under a separate authorization. The preparation for such a future test is documented in `synthetic-staging-e2e-readiness.md`; no E2E or remote operation is performed by this package update.
