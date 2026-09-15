# Performe AI onboarding activation checklist

The technical onboarding implementation remains fail-closed until the product owner supplies and approves the complete metadata below. This file is not a legal draft, publication record, or approval.

For every document required by the approved product policy, provide:

- approved final document content or an HTTPS URL controlled by the product;
- immutable `document_key`;
- immutable version identifier;
- locale (`pt-BR` or `en-US` in the current contract);
- purpose, stated without broadening the approved legal basis;
- required user action: terms acceptance, privacy acknowledgement, or a specific consent;
- effective timestamp;
- publication timestamp and publication status;
- SHA-256 identity of the exact UTF-8 bytes presented to the user;
- responsible approver and evidence of approval, retained outside the application database as required by governance.

For each supported locale, also approve and publish one immutable, versioned
requirement set containing the exact document keys that are mandatory together.
The requirement set is the completeness authority: publishing document rows alone
does not activate onboarding. Every listed key must resolve to one current required
document; partial sets fail closed. The current contract permits at most 16 keys,
12,000 UTF-8 bytes per embedded/fetched body, 2,048 characters per controlled URL,
and 48,000 bytes for the serialized document collection returned to iOS. The
complete public bootstrap is capped at 60,000 bytes, and only the latest atomic
set of up to 16 actions is returned; immutable older actions remain in the
database audit history.

The initial activation decision must identify, at minimum:

- the approved Terms of Service;
- the approved Privacy Policy;
- every additional notice or specific consent required by the approved product policy;
- which documents are mandatory for onboarding completion in each supported locale.

Operational activation remains a separate authorized change. It requires applying
the additive migration, publishing the approved immutable document versions and
their approved requirement set in the same activation window, configuring any
allowed legal-content HTTPS origins, deploying the BFF and iOS build, and running
the external staging E2E. Legacy users whose prior completion lacks current exact
actions must explicitly establish or renew consent; no historical timestamp or
action may be fabricated. None of those operations are performed by the local
implementation task.
