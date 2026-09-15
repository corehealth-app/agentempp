# Performe AI — Document Manifest Template

STATUS: DRAFT
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

This template separates legal governance metadata from the exact fields supported by the implemented onboarding storage/API. It is not an insertion script or operational manifest.

## Legal governance record — outside the runtime row

| Field | Draft value |
| --- | --- |
| Document title | `[PENDING — APPROVED TITLE]` |
| Source draft path | `[PENDING — SOURCE PATH]` |
| Responsible legal entity/controller | `[PENDING — LEGAL ENTITY/ROLE]` |
| Approval owner | `[PENDING — APPROVAL OWNER]` |
| Approval evidence reference | `[PENDING — APPROVAL EVIDENCE]` |
| Approval date | `[PENDING — APPROVAL DATE]` |
| Translation reviewer/evidence | `[PENDING — TRANSLATION REVIEW]` |
| Legal-basis decision reference | `[PENDING — LEGAL-BASIS DECISION]` |
| Retention/processor decision references | `[PENDING — GOVERNANCE REFERENCES]` |

These fields belong in controlled governance evidence. They are not accepted fields in the current mobile completion payload or columns in `onboarding_legal_documents` unless separately mapped by an approved operational procedure.

## Implemented operational document row

| Implemented field | Constraint / activation value |
| --- | --- |
| `document_key` | 1–100 chars; `^[a-z][a-z0-9_]{0,99}$`; cannot start `dev_`; dotted draft proposals are incompatible |
| `version` | 1–64 chars; `^[A-Za-z0-9._-]{1,64}$`; proposed future `1.0.0` is not approved |
| `locale` | Exactly `pt-BR` or `en-US`; documentary `en` proposal must map to `en-US` |
| `body` | Non-empty embedded body, at most 12,000 UTF-8 bytes; mutually exclusive with `content_url` |
| `content_url` | HTTPS URL, at most 2,048 chars, controlled origin allowlisted by the BFF; mutually exclusive with `body` |
| `content_hash` | Lowercase SHA-256 of exact presented content bytes; for URL content, never hash the URL string |
| `purpose` | 1–160 chars; `^[a-z][a-z0-9_]{0,159}$`; requires legal/product approval |
| `action_type` | Exactly `acceptance`, `acknowledgement`, or `consent` |
| `required` | Boolean; legal/product decision for the applicable requirement set |
| `effective_at` | Approved effective timestamp; `[PENDING — EFFECTIVE DATE]` |
| `publication_status` | Implemented table permits only `published`; drafts must never be inserted |
| `published_at` | Real publication timestamp; must not be fabricated |

The database adds an immutable server-generated `id` and `created_at`. Within each `document_actions` item, the client submits only exact `document_key`, `version`, `locale`, `content_hash`, and `action`; it cannot set purpose, required/publication state, timestamps, user ID, or completion. The surrounding completion payload separately contains the approved onboarding profile fields defined by the runtime contract.

## Implemented requirement-set row

| Field | Constraint / activation value |
| --- | --- |
| `version` | Approved immutable version matching the runtime version regex |
| `locale` | `pt-BR` or `en-US` |
| `document_keys` | 1–16 unique compatible keys; every key must resolve to one current required document |
| `effective_at` | Approved coordinated effective timestamp |
| `publication_status` | `published` only; partial/draft sets are prohibited |
| `published_at` | Real publication timestamp |

The selected documents must also pass two aggregate application-layer limits: the JSON-serialized verified document collection must not exceed 48,000 UTF-8 bytes, and the complete serialized public onboarding state must not exceed 60,000 UTF-8 bytes. Exceeding either limit keeps the flow fail-closed even when every individual row and the requirement set are valid in the database.

## Candidate mapping — not approved

| Draft concept | Candidate runtime key | Candidate runtime action | Status |
| --- | --- | --- | --- |
| Terms of Use | `legal_terms_of_use` | `acceptance` | PENDING APPROVAL |
| Privacy notice | `legal_privacy_notice` | `acknowledgement` | PENDING APPROVAL |
| Health and Flow AI notice | `notice_health_and_flow_ai` | `acknowledgement` | PENDING APPROVAL |
| Sensitive health data | `consent_sensitive_health_data` | `consent` | PENDING LEGAL-BASIS AND REQUIREMENT DECISION |
| Media processing | `consent_media_processing` | `acknowledgement` or another approved explicit-use design | PENDING; recommended just-in-time rather than global onboarding |

No hash in this repository draft is a final runtime document hash.
