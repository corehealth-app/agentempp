# Performe AI — Legal Activation Checklist

STATUS: DRAFT
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

This checklist separates preparation from legal approval and operational activation. `MINUTA TÉCNICA CRIADA: SIM` means only that this draft package exists; it does not pass any gate below.

| Gate | Required evidence | Status |
| --- | --- | --- |
| A — Legal identity | Contracting entity, controller/operator roles, CNPJ, address, seller, brand/domain ownership, support/privacy contacts | NOT PASSED |
| B — Legal review | Review by qualified counsel in every launch jurisdiction | NOT PASSED |
| C — Legal bases | Approved purpose-by-purpose and data-category matrix, including sensitive data | NOT PASSED |
| D — Processors | Verified inventory, roles, regions, subprocessors, contracts/DPA, transfer mechanisms | NOT PASSED |
| E — Retention and rights | Approved retention schedule, deletion, access/export/correction/revocation and incident procedures | NOT PASSED |
| F — Text approval | Named legal/business approvers and retained approval evidence for exact text | NOT PASSED |
| G — Translation review | Legal and linguistic equivalence review after final pt-BR approval | NOT PASSED |
| H — Byte freeze | Exact final UTF-8 bytes frozen for each locale and version | NOT PASSED |
| I — Final hash | SHA-256 calculated from the exact presented bytes; not from these mutable drafts or a URL string | NOT PASSED |
| J — Controlled-origin publication | Approved body or HTTPS URL on an allowlisted, controlled origin; public availability verified | NOT PASSED |
| K — Staging migration | Additive onboarding migration reviewed, backed by a recovery plan, and applied to the exact staging project | NOT PASSED |
| L — Document insertion | Immutable approved document rows inserted with matching identity and publication metadata | NOT PASSED |
| M — Requirement set | Complete atomic locale-specific set published with only supported document keys | NOT PASSED |
| N — BFF deploy | Exact reviewed BFF release deployed and health checked in staging | NOT PASSED |
| O — Release staging E2E | Real login → requirements → explicit actions → persisted server completion → relaunch/reconsent boundaries | NOT PASSED |
| P — UAT | Product/legal copy, accessibility, links, revocation/deletion paths, and user comprehension accepted | NOT PASSED |
| Q — Separate production authorization | Explicit production scope, target IDs, rollback, approvals, and deployment authorization | NOT PASSED |

## Runtime compatibility findings

The requested documentary proposals are not directly insertable:

| Conceptual proposal | Implemented contract | Activation action |
| --- | --- | --- |
| `legal.terms_of_use` | Keys must match `^[a-z][a-z0-9_]{0,99}$`; dots are rejected | Approve a compatible immutable key, for example `legal_terms_of_use`, after contract/product review |
| `legal.privacy_notice` | Same underscore-only rule | Approve a compatible key, for example `legal_privacy_notice` |
| `notice.health_and_flow_ai` | Same underscore-only rule | Approve a compatible key, for example `notice_health_and_flow_ai` |
| `consent.sensitive_health_data` | Same underscore-only rule | Approve a compatible key, for example `consent_sensitive_health_data` |
| `consent.media_processing` | Same underscore-only rule | Decide whether media is an onboarding document at all; current UX recommendation is just-in-time |
| `accept` | `acceptance` | Map only after approval |
| `acknowledge` | `acknowledgement` | Map only after approval |
| `consent` | `consent` | Compatible action value, subject to legal-basis approval |
| locale `en` | `en-US` | Translation/language-market decision and manifest must use the runtime locale |

The current runtime also requires: version matching `^[A-Za-z0-9._-]{1,64}$`; lowercase 64-character SHA-256; purpose matching `^[a-z][a-z0-9_]{0,159}$`; one of embedded body or controlled HTTPS URL; published/effective metadata; a complete requirement set of 1–16 unique keys; exact action identity; no more than 48,000 UTF-8 bytes in the JSON-serialized verified document collection; and no more than 60,000 UTF-8 bytes in the complete serialized public onboarding state. The proposed future version `1.0.0` is only a draft convention until Gate F.

## Activation fail-closed checks

- Never seed these drafts as published documents.
- Never fabricate an approval timestamp, publication timestamp, user action, or completion timestamp.
- Material text change creates a new immutable version; it does not rewrite historical actions.
- Confirm each localized body stays within the individual 12,000-byte limit, the verified collection stays within 48,000 serialized bytes, and the complete public onboarding state stays within 60,000 serialized bytes during byte freeze and staging verification.
- Confirm the controlled-origin allowlist before URL-backed content.
- Confirm whether sensitive-data consent is mandatory for the proposed beta functionality; do not make an optional consent coercively required.
- Keep marketing consent separate, optional, and initially unselected if introduced.
