# Performe AI Legal Draft Package — Implementation Plan

> **For Codex:** Execute this documentation-only plan locally. Do not publish, activate, deploy, migrate remotely, run E2E, invoke providers, or change product code. Create exactly one final local commit after documentary gates pass.

STATUS: DRAFT
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO

**Goal:** Register a bilingual pt-BR/English legal-operational draft package that can be reviewed and completed by qualified legal and business owners before any onboarding activation.

**Architecture:** Keep all draft artifacts under `docs/legal/performe-ai/`. Treat pt-BR as the source draft, English as a semantic translation, and keep legal decisions, processors, retention, activation, and the runtime manifest mapping explicit and separate. The existing server-owned onboarding remains fail-closed and receives no documents from this task.

**Stack:** Markdown documentation; existing TypeScript, Swift, PostgreSQL, and Mobile API contracts are read-only evidence.

## Allowed files

- this plan;
- `docs/legal/performe-ai/README.md`;
- six pt-BR draft documents;
- six matching English draft documents;
- `legal-activation-checklist.md`;
- `legal-decision-register.md`;
- `processor-inventory.template.md`;
- `retention-matrix.template.md`;
- `document-manifest.template.md`.

## Execution

1. Verify the exact clean baseline and read the authoritative dossier, beta documents, activation checklist, migration, API contracts, and iOS action enum.
2. Draft the pt-BR source documents without filling unresolved legal identity, dates, contacts, legal bases, retention, or commercial terms.
3. Produce complete semantic English translations without adding or removing obligations.
4. Record the proposed-to-runtime key/action/locale divergences. Do not change the runtime contract and do not calculate an operational final hash.
5. Populate only evidence-bounded processor candidates; leave legal roles, transfers, contracts, regions, retention, and production use pending where not proven.
6. Run two independent documentary reviews and repository-local scans. Resolve all Critical, Important, and Minor findings before commit.
7. Revalidate the parent, stage only this allowlist, review the staged diff, and create one local commit with subject `docs(legal): add Performe AI beta legal drafts`.

## Definition of done

- All artifacts identify themselves as unapproved, unpublished, inactive drafts.
- pt-BR and English are semantically aligned.
- No legal entity, controller, operator, seller, DPO, address, contact, domain, price, trial, deadline, legal basis, DPA, or deployment state is invented.
- The implemented onboarding contract is described accurately and every proposal divergence is explicit.
- Reviews A and B report Critical 0 and Important 0; scans pass; runtime code is unchanged; Git is clean after the one local commit.
