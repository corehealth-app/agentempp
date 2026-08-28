# CI-3 synthetic Auth identity readback diagnostic and resume authority

**Operation:** `DIAGNOSE_SYNTHETIC_AUTH_READBACK_STOP`

**Mode:** `DIAGNOSTIC_AUTHORING_ONLY`

**Dossier:** `1.6.20`

**Date:** 2026-08-28 UTC

**Outcome:** `RESUME_AUTHORITY_PUBLISHED`

This evidence reconciles the readback STOP from the single authorized
synthetic staging identity creation. It authorizes a later, separate operation
to resume from the existing Auth identity. It does not perform sign-in, change
or delete the Auth user, create domain data, call the BFF, or execute the next
gate.

## 1. Frozen authority and preserved baseline

```text
DOCUMENTATION_BRANCH=codex/better-ahead-rebranding-design
DOCUMENTATION_PARENT=e4159e853e6a5938f4620afdce194eb8dab3232d
DOCUMENTATION_PARENT_TREE=368bc5997933477529e4b982d5d9f918f688519b
DOCUMENTATION_PARENT_SUBJECT=docs(staging): authorize synthetic patient provisioning
IMPLEMENTATION_SHA=e3e1e252b48e42554e75899b950692c05186f60d
IMPLEMENTATION_TREE=a167a6663cb1e476975742bcec51c7207dbcbc26
STAGING_PROJECT_REF=xitugspwfxkcluxvrdeg
```

The manager remained at the exact parent with empty staging, canonical
`25/5/20`, porcelain SHA-256
`455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`
and tracked binary diff SHA-256
`7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`.
The implementation, old staging and dedicated deploy worktrees remained clean
at their documented SHAs. No implementation Git path was changed.

The BFF readback remained one semantic Preview, READY, at the exact
implementation SHA, with one total deployment, zero Production, env
Preview/Production/Development `3/0/0`, project SSO `null`, Project link
absent, Git Integration absent and zero custom domains. Vercel received only
GETs during this diagnostic.

## 2. Original STOP and consumed budgets

The original launcher created exactly one Auth user and then stopped at
`CREDENTIAL_WRITTEN` with `auth_identity_contract_failed`. Its durable state
is `PRESERVED_FOR_DIAGNOSIS`.

```text
AUTH_PREFLIGHT_ATTEMPTS=1/1
AUTH_USER_CREATION_ATTEMPTS=1/1
AUTH_CREATE_SETTLEMENT_ATTEMPTS=0
AUTH_READBACK_ATTEMPTS=1/1
AUTH_USER_DELETE_ATTEMPTS=0
PATIENT_SIGN_IN_ATTEMPTS=0/1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=0/1
PATIENT_BOOTSTRAP_READBACK_ATTEMPTS=0/1
ENTITLEMENT_CREATION_ATTEMPTS=0/1
ENTITLEMENT_READBACK_ATTEMPTS=0/1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=0/1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=0/1
SECOND_AUTH_USER_CREATION=NO
```

The diagnostic added exactly one Admin `listUsers` and one Admin
`getUserById`, plus one official read-only SQL summary. It made zero Auth or
database mutations, zero sign-ins and zero BFF calls.

## 3. Preserved artifacts

All three operation artifacts are regular root-owned files, mode `0600`, link
count one, under the mode-`0700` secrets directory. The provisioning receipt
is absent.

```text
CLAIM_SHA256=f9b0a29a7f8b1da71ff7492a3f2ec4e746a25533570228da9acd41c475be179a
CREDENTIAL_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
RECOVERY_RECEIPT_SHA256=f61700b584b36910ea532bbff429097f3608ec86e1cede22a72cefab7462b44b
PROVISIONING_RECEIPT=ABSENT
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
```

The claim, password-bearing credential and recovery receipt remain preserved
without rewrite. Raw e-mail, password, marker and Auth ID are absent from Git
and from this evidence.

## 4. Diagnostic implementation and tests

The temporary helper lived outside Git, was root-owned mode `0700`, and passed
`node --check`. Before it opened any real artifact, 35/35 synthetic cases
passed with zero failed, skipped, todo or network calls. Those cases covered
the closed classification vocabulary, required metadata, server augmentation,
case normalization, confirmation aliases, phone null/empty, provider and
identity errors, ban/delete/admin states and source agreement/disagreement. A
pre-read static review separately proved the fixed output sites and absence of
write call sites.

During the pre-commit coverage audit, after the two real Auth reads had already
completed, it was discovered that the first suite had not named every required
redaction/order case individually. Eleven supplemental synthetic checks then
passed without network or another artifact/Auth read: provider order,
confirmation alias, DB/Admin agreement and disagreement, raw e-mail/ID/marker/
password/metadata redaction, output allowlist and absence of reachable write
APIs. This sequencing difference is recorded as one non-blocking Review B
Minor; it does not retroactively claim those eleven checks ran before the real
read.

```text
DIAGNOSTIC_HELPER_SHA256=71add1da726d5aa38566aa0c8590db6c6d68bb37d63286f168ac0cc413fdc220
DIAGNOSTIC_RESULT_SHA256=6f60d7b509ed56773194459bde4f45462dfc5967175795c3c53679172713ea36
DIAGNOSTIC_PRE_REAL_TESTS=35
DIAGNOSTIC_SUPPLEMENTAL_TESTS=11
DIAGNOSTIC_TESTS_TOTAL=46
FAILED=0
SKIPPED=0
TODO=0
NETWORK_CALLS=0
AUTH_READ_CALLS=2
MUTATIONS=0
RAW_VALUES_REPORTED=NO
```

The preliminary helper matrix was SHA-256
`f5b4a840f2e6bb595b28d055fe70dac51ecf392d97db1d627ced76e149b89fe4`.
After applying the official endpoint-specific semantics described below, the
canonical reconciled stream `<field>\t<classification>\n`, sorted by field, is:

```text
DIAGNOSTIC_MATRIX_SHA256=9ddba9fa79f46f82591a8b031f0c36298fd88394fd9e3edfacd188d24f98e812
```

## 5. Official semantics frozen

The current Supabase Auth docs, Auth changelog, official source and exact local
package were read before classification. The official source was pinned at:

```text
SUPABASE_JS_HEAD=d38e6c5d4aac18146d5379a49b6519db2a44fa5b
SUPABASE_AUTH_HEAD=99090eb6597db8b1bb3a510193526d46b74c4a7d
OFFICIAL_AUTH_SEMANTICS_STREAM_SHA256=14e3a6be89402808e485a87108d7a597bd28616b21c72bc255d8a7d4816cb169
LOCAL_AUTH_JS_SOURCE_STREAM_SHA256=0252913cf3003ec3224243b9f344793a2730a446f861d5c03a00405596b1dd2c
LOCAL_SUPABASE_JS_VERSION=2.105.1
```

The official implementation establishes these material semantics:

- `validateEmail` returns `strings.ToLower(email)` and `NewUser` also stores a
  lowercase e-mail;
- Admin create derives `aud=authenticated` and the default authenticated role;
- Admin create adds `provider=email` and `providers=[email]` to app metadata,
  then merges the operation-controlled app metadata;
- `email_confirm=true` sets the confirmed e-mail timestamp; `confirmed_at` is
  the aggregate e-mail/phone confirmation alias;
- an Admin e-mail create inserts one `email` identity;
- absent phone values may serialize as null, empty or omitted;
- the user object documentation permits provider identity data in
  `user_metadata` when no custom user metadata was supplied;
- Admin GET eagerly loads identities, while offset Admin LIST uses
  `FindUsersInAudience` without eager identity loading; list omission is an
  endpoint projection, not missing database identity;
- JSON key order and array order are not security contracts; required custom
  metadata is compared as an exact typed subset, while documented
  provider/provider-list augmentation is compared separately.

No current Auth changelog entry contradicted these semantics.

## 6. Exact root cause

The failed field is exactly `email` in the launcher's strict equality check.
The generated credential contained uppercase characters in its random local
part. Supabase Auth lowercased the complete address before persistence, as its
official source specifies. Sanitized hash comparison proved:

```text
CREDENTIAL_EMAIL_CONTAINS_UPPERCASE=YES
CREDENTIAL_EMAIL_EXACT_HASH_MATCHES_REMOTE=NO
CREDENTIAL_EMAIL_LOWERCASE_HASH_MATCHES_REMOTE=YES
ADMIN_GET_EMAIL_HASH_MATCHES_DATABASE=YES
ADMIN_LIST_EMAIL_HASH_MATCHES_DATABASE=YES
ROOT_CAUSE=CLIENT_EXPECTED_RAW_EMAIL_WHILE_AUTH_CANONICALIZED_EMAIL_TO_LOWERCASE
ROOT_CAUSE_CLASSIFICATION=NORMALIZED_ALIAS_DOCUMENTED
```

The same normalization explains the identity-data e-mail comparison. It does
not indicate a second identity, wrong user or credential corruption.

## 7. Readback inventory and reconciled field matrix

All three identity sources agree after applying documented endpoint and e-mail
normalization semantics:

```text
AUTH_USER_TOTAL=1
SYNTHETIC_AUTH_USER_MATCHES=1
AUTH_ID_HASH_AGREEMENT=YES
AUTH_EMAIL_LOWERCASE_HASH_AGREEMENT=YES
AUTH_IDENTITY_TOTAL=1
AUTH_IDENTITY_PROVIDER=email
PATIENT_TOTAL=0
PROFILE_TOTAL=0
PROGRESS_TOTAL=0
ENTITLEMENT_TOTAL=0
ENTITLEMENT_EVENT_TOTAL=0
STORAGE_MATCH_TOTAL=0
```

| Field | Final classification | Basis |
| --- | --- | --- |
| `id` | `MATCH_REQUIRED` | recovery, Admin GET/LIST and database hash agree |
| `aud`, `role` | `MATCH_REQUIRED` | both are the expected authenticated values |
| `email` | `NORMALIZED_ALIAS_DOCUMENTED` | exact lowercase normalization proven |
| `phone`, `phone_confirmed_at` | `NORMALIZED_NULL_EMPTY_DOCUMENTED` | phone is semantically absent |
| `email_confirmed_at`, `confirmed_at` | `MATCH_REQUIRED` | both confirmation timestamps are present |
| `last_sign_in_at` | `NORMALIZED_NULL_EMPTY_DOCUMENTED` | no sign-in occurred |
| `banned_until`, `deleted_at` | `MATCH_REQUIRED` | both absent |
| `is_anonymous` | `MATCH_REQUIRED` | false |
| `is_sso_user` | `NORMALIZED_NULL_EMPTY_DOCUMENTED` | false/default non-SSO representation |
| required app metadata subset | `MATCH_REQUIRED` | all five typed values exact |
| `provider`, `providers` | `EXTRA_SERVER_OWNED_DOCUMENTED` | e-mail provider augmentation |
| `user_metadata` | `EXTRA_SERVER_OWNED_DOCUMENTED` | first-provider identity data default |
| identity cardinality/provider | `MATCH_REQUIRED` | database and GET prove one e-mail identity |
| LIST identity omission | `NORMALIZED_NULL_EMPTY_DOCUMENTED` | documented non-eager list projection |
| identity e-mail | `NORMALIZED_ALIAS_DOCUMENTED` | same lowercase canonicalization |
| identity/provider ID aliases | `NORMALIZED_ALIAS_DOCUMENTED` | documented e-mail identity representation |
| `created_at`, `updated_at` | `MATCH_REQUIRED` | valid timestamps present |

There is no required-field mismatch after canonicalization. Every divergence
belongs to one of the three resume-safe classifications:
`EXTRA_SERVER_OWNED_DOCUMENTED`, `NORMALIZED_ALIAS_DOCUMENTED` or
`NORMALIZED_NULL_EMPTY_DOCUMENTED`.

## 8. Independent reviews

### Review A — Auth semantics

Reviewed create, GET, LIST, `auth.users`, `auth.identities`, provider fields,
confirmation fields, phone representation, metadata subset, role/audience,
endpoint projection and the resume/rollback choice.

```text
REVIEW_A_VERDICT=GO_RESUME_EXISTING_IDENTITY
REVIEW_A_CRITICAL=0
REVIEW_A_IMPORTANT=0
REVIEW_A_MINOR=0
```

### Review B — preservation and recovery

Reviewed artifact physics/hashes, no-clobber state, original and remaining
budgets, zero sign-in/write/probe, zero patient/entitlement/storage, credential
and claim preservation, unchanged deadline, Git/Vercel/primary/CI boundaries
and absence of raw values.

```text
REVIEW_B_VERDICT=GO_RESUME_EXISTING_IDENTITY
REVIEW_B_CRITICAL=0
REVIEW_B_IMPORTANT=0
REVIEW_B_MINOR=1
REVIEW_B_MINOR_1=SUPPLEMENTAL_REDACTION_ORDER_CASES_RAN_AFTER_REAL_READ
```

## 9. Resume authority

The existing identity is valid and must be reused. The later executor starts
at `AUTH_USER_CREATED`; it must compare the credential e-mail to Auth using the
documented lowercase canonical form, while retaining the original credential
bytes and exact Auth ID from the recovery receipt.

The next operation is authorized to consume only the remaining original
budgets in this order:

1. validate the published authority, exact preserved artifacts and current
   one-user/zero-domain-data state;
2. perform exactly one sign-in using the existing credential;
3. perform exactly one authenticated `/me` bootstrap and exact readback;
4. perform exactly one entitlement grant accepted only as `result=applied`,
   then exact entitlement/resolver readback;
5. perform exactly one `/entitlements` probe;
6. perform exactly one `/today` probe;
7. create the provisioning receipt only after complete success.

The later operation may not create a second Auth user; update or delete the
existing Auth user; rewrite the credential; overwrite or remove the claim;
remove or rewrite the recovery receipt; change the cleanup deadline; retry a
consumed gate; mutate Vercel/SSO/deployment/env; open primary/live; start CI-4;
or execute any operation beyond the bounded Today completion.

Original recovery rules remain active for failures after resume. A valid
Auth/patient/entitlement fixture with a later bearer or probe failure is
preserved for diagnosis. Ambiguous grant settlement never authorizes a second
grant or automatic rollback. `TODAY_VERIFIED` still forbids rollback and
cleanup still requires a separate authority by the original deadline.

```text
RESUME_AUTHORITY_STATUS=PUBLISHED_PENDING_COMMIT_IDENTITY
STATE_START=AUTH_USER_CREATED
AUTH_USER_CREATION_ATTEMPTS=1/1_CONSUMED
SECOND_AUTH_USER_CREATION=NO
AUTH_USER_UPDATE_ATTEMPTS=0/0
AUTH_USER_DELETE_ATTEMPTS=0/0
PATIENT_SIGN_IN_ATTEMPTS=0/1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=0/1
ENTITLEMENT_CREATION_ATTEMPTS=0/1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=0/1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=0/1
CREDENTIAL_REWRITE=FORBIDDEN
CLAIM_OVERWRITE_OR_REMOVAL=FORBIDDEN
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
RAW_PII_OR_SECRET_OUTPUT=NO
VERCEL_WRITE=NO
PRIMARY_LIVE_OPEN=NO
CI3_STARTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RESUME_EXISTING_SYNTHETIC_AUTH_IDENTITY_AND_COMPLETE_AUTHENTICATED_TODAY
```

This document publishes authority only. The next gate is not executed here.
