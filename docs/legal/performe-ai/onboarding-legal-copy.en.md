# ONBOARDING LEGAL MICROCOPY — PERFORME AI

STATUS: DRAFT FOR LEGAL REVIEW — NOT PUBLISHED
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

Approval date: `[PENDING — APPROVAL DATE]`
Effective date: `[PENDING — EFFECTIVE DATE]`

## Proposed copy

| Document/purpose | English microcopy | Conceptual action | Runtime action | Required |
| --- | --- | --- | --- | --- |
| Terms of Use | “I have read and accept the Terms of Use.” | `accept` | `acceptance` | Yes, if approved and included in the requirement set |
| Privacy Policy | “I have read the Privacy Policy.” | `acknowledge` | `acknowledgement` | Yes, if approved and included in the requirement set |
| Health and AI | “I understand Performe AI's and Flow's limitations regarding health and artificial intelligence.” | `acknowledge` | `acknowledgement` | Yes, if approved and included in the requirement set |
| Sensitive data | “I consent to the processing of my health and body data as described.” | `consent` | `consent` | Depends on the approved feature, legal basis, and requirement |

## Presentation rules

- Every action starts unchecked and requires an explicit gesture.
- The screen must provide the full content or controlled HTTPS link corresponding to the exact server-provided version, locale, and hash.
- Do not complete onboarding with a missing document, stale version, mismatched hash, incompatible action, or incomplete requirement set.
- The Privacy Policy is a transparency notice. **“I have read and accept the Privacy Policy” is not recommended**, because it confuses acknowledgement with contractual acceptance or consent.
- Acceptance of the Terms does not replace specific consent.
- Marketing, if introduced later, must remain separate, optional, and initially unchecked. It is not part of this proposed beta scope.
- Photos and audio must use a just-in-time notice and action, not general onboarding, unless a later decision based on the real flow determines otherwise.

## Proposed document keys and divergences

| Proposal | Current compatibility |
| --- | --- |
| `legal.terms_of_use` | Incompatible: runtime rejects dots; unapproved candidate `legal_terms_of_use` |
| `legal.privacy_notice` | Incompatible: unapproved candidate `legal_privacy_notice` |
| `notice.health_and_flow_ai` | Incompatible: unapproved candidate `notice_health_and_flow_ai` |
| `consent.sensitive_health_data` | Incompatible: unapproved candidate `consent_sensitive_health_data` |
| `consent.media_processing` | Incompatible and not approved as an onboarding requirement; technical candidate depends on the just-in-time decision |

Proposed future documentary version: `1.0.0` — **not approved**.
Documentary locales: `pt-BR` and `en`; the implemented runtime accepts `pt-BR` and `en-US`, so the operational English version must use `en-US`.
