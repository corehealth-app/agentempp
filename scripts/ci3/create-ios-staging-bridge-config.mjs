#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { constants as FS_CONSTANTS } from 'node:fs';
import {
  link,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  rm,
  unlink,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const GENERATOR_GIT_PATH = 'scripts/ci3/create-ios-staging-bridge-config.mjs';
const AUTHORITY_PARENT = '9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52';
const AUTHORITY_SUBJECT = 'build(ops): authorize executable CI-3 bridge tooling';
const EXPECTED_IMPLEMENTATION_SHA = 'e3e1e252b48e42554e75899b950692c05186f60d';
const OUTPUT_ROOT = '/root/.config/agentempp/bridges/ci3';
const PRIMARY_DENYLIST = '/root/.config/agentempp/secrets/agentempp-primary-backend.env';
const ENV_RECEIPT_PURPOSE = 'ci3_staging_mobile_bff';
const DEPLOYMENT_RECEIPT_PURPOSE = 'ci3_dedicated_mobile_bff_deployment';
const PROVISIONING_RECEIPT_PURPOSE = 'ci3_synthetic_patient';
const LOCAL_CONFIG_RELATIVE_PATH = 'Library/Application Support/Agentempp/mobile-staging-config.json';
const LOCAL_CREDENTIAL_RELATIVE_PATH = 'Library/Application Support/Agentempp/synthetic-patient.credentials.json';

export const INPUT_PATHS = Object.freeze({
  env: '/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env',
  envReceipt: '/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json',
  deploymentReceipt: '/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json',
  credential: '/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json',
  provisioningReceipt: '/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.receipt.json',
});

const EXPECTED_INPUT_HASHES = Object.freeze({
  env: '6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d',
  envReceipt: '44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978',
  deploymentReceipt: 'f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6',
  credential: 'd36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208',
  provisioningReceipt: '5ed29995fa906d3774384d5a1aa9157516fa9f3e3dd0d320beff138b6aeedfcb',
});

const INPUT_SIZE_LIMITS = Object.freeze({
  env: 16 * 1024,
  envReceipt: 128 * 1024,
  deploymentReceipt: 256 * 1024,
  credential: 64 * 1024,
  provisioningReceipt: 256 * 1024,
});

const ENV_NAMES = Object.freeze([
  'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  'NEXT_PUBLIC_SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
]);

const ENV_RECEIPT_KEYS = Object.freeze([
  'control_plane_pat_persisted',
  'control_plane_source',
  'created_at_utc',
  'database_write',
  'environment',
  'key_created',
  'key_disabled',
  'key_rotated',
  'legacy_key_contract',
  'local_elevated_secret_exposure',
  'preview_branch_verified_via_dashboard_and_api_keys',
  'production_accessed',
  'purpose',
  'rejected_env_local_used',
  'required_permission_verified',
  'schema_version',
  'supabase_parent_project_ref',
  'supabase_project_ref',
  'values_in_argv',
  'values_in_git',
  'values_printed',
  'variables',
]);

const DEPLOYMENT_RECEIPT_KEYS = Object.freeze([
  'api_target_representation',
  'app_paths_manifest_sha256',
  'build_log_sha256',
  'canonical_route_path_stream_sha256',
  'env_development_count',
  'env_metadata',
  'env_preview_count',
  'env_production_count',
  'environment',
  'framework',
  'implementation_sha',
  'implementation_tree',
  'incident_receipt_sha256',
  'mobile_route_count',
  'node',
  'origin_sha256',
  'original_removal_verified',
  'preview_deployment_id_sha256',
  'preview_origin',
  'preview_receipt_sha256',
  'production_deployment_count',
  'project_id_sha256',
  'project_link_absent',
  'public_probes',
  'purpose',
  'ready_state',
  'recovery_authority_sha',
  'removed_original_deployment_id_sha256',
  'root',
  'route_count',
  'schema_version',
  'secret_values_absent',
  'sso_protection',
  'target',
  'team_default_live_state',
  'team_default_mutation_requests',
  'token_absent',
]);

const CREDENTIAL_KEYS = Object.freeze([
  'cleanup_required',
  'created_at',
  'email',
  'environment',
  'expires_at',
  'password',
  'project_ref',
  'schema_version',
  'synthetic_marker',
]);

const PROVISIONING_RECEIPT_KEYS = Object.freeze([
  'actor_id',
  'attempts',
  'auth_reused',
  'auth_user_id',
  'authority_sha',
  'ci3_started',
  'ci4_started',
  'cleanup_deadline',
  'cleanup_deadline_class',
  'cleanup_required',
  'created_at',
  'email_canonicalization',
  'entitlement_id',
  'environment',
  'event_id',
  'expires_at',
  'fixture_counts',
  'grant_at',
  'health_data_absent',
  'id_hashes',
  'implementation_sha',
  'implementation_tree',
  'operation_id',
  'patient_id',
  'primary_live_open',
  'product_production_write',
  'project_ref',
  'purpose',
  'raw_response_absent',
  'request_ids',
  'response_structure_sha256',
  'schema_version',
  'service_role_patient_bearer',
  'state',
  'supabase_http_request_counts',
  'synthetic_marker',
  'token_persisted',
  'vercel_write',
]);

const ATTEMPT_KEYS = Object.freeze([
  'auth_create',
  'auth_create_settlement',
  'auth_delete_rollback',
  'auth_preflight',
  'auth_readback',
  'auth_update',
  'bootstrap_readback',
  'entitlement_grant',
  'entitlement_readback',
  'entitlement_resolution',
  'entitlement_settlement',
  'entitlements_probe',
  'me_probe',
  'rollback_database_transaction',
  'rollback_settlement_read',
  'sign_in',
  'today_probe',
]);

export const RECEIPT_KEYS = Object.freeze([
  'schema_version',
  'purpose',
  'created_at_utc',
  'authority_commit',
  'authority_parent',
  'authority_tree',
  'authority_subject',
  'generator_blob_sha',
  'generator_file_sha256',
  'controller_blob_oid',
  'controller_file_sha256',
  'launcher_blob_oid',
  'launcher_file_sha256',
  'anchor_writer_blob_oid',
  'anchor_writer_file_sha256',
  'authority_tree_manifest_sha256',
  'remote_bundle_generation_id',
  'source_generation_id',
  'source_env_descriptor_identity_sha256',
  'env_source_sha256',
  'env_receipt_sha256',
  'deployment_receipt_sha256',
  'credential_source_path',
  'credential_source_sha256',
  'provisioning_receipt_sha256',
  'output_config_sha256',
  'output_filenames',
  'staging_project_ref',
  'implementation_sha',
  'preview_deployment_count',
  'production_deployment_count',
  'env_preview_count',
  'env_production_count',
  'env_development_count',
  'sso_state',
  'cleanup_deadline',
  'service_role_emitted',
  'token_emitted',
  'raw_values_reported',
  'primary_opened',
  'remote_bundle_immutable',
  'terminal_scan_ids',
]);

export const TERMINAL_SCAN_IDS = Object.freeze([
  'argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime',
]);

export const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  'scripts/ci3/create-ios-staging-bridge-config.mjs',
  'scripts/ci3/create-ios-staging-bridge-config.test.mjs',
  'scripts/ci3/ci3-bridge-controller.mjs',
  'scripts/ci3/ci3-bridge-controller.test.mjs',
  'scripts/ci3/ci3-bridge-launcher.zsh',
  'scripts/ci3/ci3-bridge-launcher.test.mjs',
  'scripts/ci3/ci3-terminal-anchor-writer.swift',
  'scripts/ci3/ci3-terminal-anchor-writer.test.mjs',
]);

export const IMPORTANT_FINDINGS = Object.freeze([
  { id: 'RA1-I-5', reviewer: 'A', architecture: 'terminal receipt anchors every scan and phase hash', test: 'terminal scan receipt binding', receipt_field: 'terminal_scan_receipt_hashes', terminal_gate: 'terminal receipt required' },
  { id: 'A4-I-1', reviewer: 'A', architecture: 'immutable version-addressed terminal evidence root', test: 'phase chains bound to terminal receipt', receipt_field: 'terminal_phase_root_sha256', terminal_gate: 'terminal phase root exact' },
  { id: 'A4-I-3', reviewer: 'A', architecture: 'descriptor-bound immutable local bundle generation', test: 'exact source generation binding', receipt_field: 'local_bundle_generation_hashes', terminal_gate: 'bundle generation exact' },
  { id: 'A5-I-1', reviewer: 'A', architecture: 'capture bytes stay on the same descriptor and inode', test: 'same-descriptor capture generation', receipt_field: 'claim_result_capture_hashes', terminal_gate: 'capture inode exact' },
  { id: 'A5-I-2', reviewer: 'A', architecture: 'Git blob and immutable source hash bind the executed generation', test: 'source replacement before execution rejected', receipt_field: 'generator_blob_sha', terminal_gate: 'Git source generation exact' },
  { id: 'RA0-I-4', reviewer: 'B', architecture: 'simulator gate reobserves typed physical effects', test: 'simulator recovery metadata variations rejected', receipt_field: 'simulator_gate_receipt_hash', terminal_gate: 'simulator effects exact' },
  { id: 'RA0-I-7', reviewer: 'B', architecture: 'each scan surface has an independently failing terminal counter', test: 'terminal scan class leakage rejected', receipt_field: 'terminal_scan_receipt_hashes', terminal_gate: 'all scan classes clean' },
  { id: 'R2-I-2', reviewer: 'B', architecture: 'terminal receipt is the immutable external phase authority', test: 'self-consistent phase rewrite rejected', receipt_field: 'terminal_phase_root_sha256', terminal_gate: 'terminal phase root exact' },
  { id: 'R5-I-1', reviewer: 'B', architecture: 'descriptor-first validation of the immutable bundle generation', test: 'bundle entry replacement rejected', receipt_field: 'local_bundle_generation_hashes', terminal_gate: 'bundle descriptors exact' },
  { id: 'R5-I-2', reviewer: 'B', architecture: 'real /usr/bin/ssh -G effective config hash', test: 'native ssh -G complete output policy', receipt_field: 'ssh_effective_config_sha256', terminal_gate: 'real effective config exact' },
  { id: 'R5-I-3', reviewer: 'B', architecture: 'Git blob hash binds the immutable fetch source generation', test: 'source mutation after preflight rejected', receipt_field: 'generator_blob_sha', terminal_gate: 'Git source generation exact' },
]);

const EXPECTED_FINDING_IDS = Object.freeze([
  'RA1-I-5', 'A4-I-1', 'A4-I-3', 'A5-I-1', 'A5-I-2',
  'RA0-I-4', 'RA0-I-7', 'R2-I-2', 'R5-I-1', 'R5-I-2', 'R5-I-3',
]);

export const TERMINAL_IMPORTANT_FINDING_IDS = Object.freeze([
  ...EXPECTED_FINDING_IDS,
  ...Array.from({ length: 6 }, (_, index) => `RA-FINAL-I-${index + 1}`),
  ...Array.from({ length: 7 }, (_, index) => `RB-FINAL-I-${index + 1}`),
]);

export class BridgeError extends Error {
  constructor(code) {
    super(code);
    this.name = 'BridgeError';
    this.code = code;
  }
}

function fail(code) {
  throw new BridgeError(code);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys, code) {
  if (!isPlainObject(value)) fail(code);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) fail(code);
}

function requireString(value, code) {
  if (typeof value !== 'string' || value.length === 0) fail(code);
  return value;
}

function requireBoolean(value, expected, code) {
  if (typeof value !== 'boolean' || value !== expected) fail(code);
}

function requireNonnegativeIntegers(object, code) {
  for (const value of Object.values(object)) {
    if (!Number.isInteger(value) || value < 0) fail(code);
  }
}

function isSha(value, lengths = [40, 64]) {
  return typeof value === 'string' && lengths.includes(value.length) && /^[a-f0-9]+$/.test(value);
}

function jsonBytes(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function gitBlobSha(bytes) {
  const buffer = Buffer.from(bytes);
  return createHash('sha1').update(`blob ${buffer.length}\0`).update(buffer).digest('hex');
}

export function validateAuthorityTreeManifest(entries) {
  if (!Array.isArray(entries) || entries.length !== 13) fail('AUTHORITY_TREE_MANIFEST');
  const paths = new Set();
  for (const entry of entries) {
    exactKeys(entry, ['blob_oid', 'path', 'sha256'], 'AUTHORITY_TREE_MANIFEST');
    if (typeof entry.path !== 'string' || entry.path.length === 0 || entry.path.startsWith('/') || entry.path.includes('..') || paths.has(entry.path)) fail('AUTHORITY_TREE_MANIFEST');
    if (!isSha(entry.blob_oid, [40]) || !isSha(entry.sha256, [64])) fail('AUTHORITY_TREE_MANIFEST');
    paths.add(entry.path);
  }
  return true;
}

export function parseMode(argv) {
  if (!Array.isArray(argv) || argv.length !== 1) fail('MODE_INVALID');
  if (argv[0] === '--self-test') return 'self-test';
  if (argv[0] === '--create') return 'create';
  fail('MODE_INVALID');
}

const PHYSICAL_IDENTITY_FIELDS = Object.freeze(['uid', 'gid', 'mode', 'nlink', 'size', 'mtimeNs', 'dev', 'ino']);

function canonicalExactStatInteger(value, code = 'INPUT_METADATA') {
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'string' && /^-?(?:0|[1-9]\d*)$/.test(value)) return value;
  fail(code);
}

function boundedStatNumber(value, code = 'INPUT_METADATA') {
  let exact;
  if (typeof value === 'bigint') exact = value;
  else if (typeof value === 'number' && Number.isSafeInteger(value)) exact = BigInt(value);
  else if (typeof value === 'string' && /^-?(?:0|[1-9]\d*)$/.test(value)) exact = BigInt(value);
  else fail(code);
  if (exact < 0n || exact > BigInt(Number.MAX_SAFE_INTEGER)) fail(code);
  return Number(exact);
}

function canonicalPhysicalIdentity(metadata, code = 'INPUT_METADATA') {
  if (metadata === null || typeof metadata !== 'object') fail(code);
  return Object.fromEntries(PHYSICAL_IDENTITY_FIELDS.map((field) => [
    field, canonicalExactStatInteger(metadata[field], code),
  ]));
}

export function validateInputMetadata(metadata, expectedUid, expectedGid = 0) {
  const isFile = typeof metadata?.isFile === 'function' ? metadata.isFile() : metadata?.isFile;
  const isSymbolicLink = typeof metadata?.isSymbolicLink === 'function' ? metadata.isSymbolicLink() : metadata?.isSymbolicLink;
  if (!isFile || isSymbolicLink) fail('INPUT_TYPE');
  if (boundedStatNumber(metadata.uid, 'INPUT_OWNER') !== expectedUid
      || boundedStatNumber(metadata.gid, 'INPUT_OWNER') !== expectedGid) fail('INPUT_OWNER');
  if ((boundedStatNumber(metadata.mode, 'INPUT_MODE') & 0o777) !== 0o600) fail('INPUT_MODE');
  if (boundedStatNumber(metadata.nlink, 'INPUT_LINK_COUNT') !== 1) fail('INPUT_LINK_COUNT');
  return true;
}

export function validateParentMetadata(metadata, expectedUid, expectedGid = 0) {
  const isDirectory = typeof metadata?.isDirectory === 'function' ? metadata.isDirectory() : metadata?.isDirectory;
  if (!isDirectory) fail('PARENT_TYPE');
  if (boundedStatNumber(metadata.uid, 'PARENT_OWNER') !== expectedUid
      || boundedStatNumber(metadata.gid, 'PARENT_OWNER') !== expectedGid) fail('PARENT_OWNER');
  if ((boundedStatNumber(metadata.mode, 'PARENT_MODE') & 0o777) !== 0o700) fail('PARENT_MODE');
  return true;
}

export function assertKnownInputPath(candidate) {
  if (candidate === PRIMARY_DENYLIST) fail('PRIMARY_PATH_DENIED');
  if (!Object.values(INPUT_PATHS).includes(candidate)) fail('INPUT_PATH_UNKNOWN');
  return true;
}

export function verifyExpectedHash(bytes, expectedHash) {
  if (!isSha(expectedHash, [64]) || sha256(bytes) !== expectedHash) fail('INPUT_HASH');
  return true;
}

export function assertStableIdentity(before, after) {
  const exactBefore = canonicalPhysicalIdentity(before, 'INPUT_MUTATED');
  const exactAfter = canonicalPhysicalIdentity(after, 'INPUT_MUTATED');
  for (const key of PHYSICAL_IDENTITY_FIELDS) {
    if (exactBefore[key] !== exactAfter[key]) fail('INPUT_MUTATED');
  }
  return true;
}

export function verifyExecutableSnapshot({ after, before, expectedBlobSha, gitBlobBytes, snapshotBytes }) {
  try {
    assertStableIdentity(before, after);
  } catch {
    fail('GENERATOR_SNAPSHOT');
  }
  const committed = Buffer.from(gitBlobBytes);
  const snapshot = Buffer.from(snapshotBytes);
  if (!isSha(expectedBlobSha, [40]) || gitBlobSha(committed) !== expectedBlobSha) fail('GENERATOR_SNAPSHOT');
  if (!committed.equals(snapshot)
      || boundedStatNumber(before?.nlink, 'GENERATOR_SNAPSHOT') !== 1
      || (boundedStatNumber(before?.mode, 'GENERATOR_SNAPSHOT') & 0o777) !== 0o600) fail('GENERATOR_SNAPSHOT');
  return true;
}

export function parseExactEnv(bytes) {
  if (!Buffer.isBuffer(bytes) && !(bytes instanceof Uint8Array)) fail('ENV_SCHEMA');
  const buffer = Buffer.from(bytes);
  if (buffer.length === 0 || buffer.length > INPUT_SIZE_LIMITS.env || buffer.includes(0)) fail('ENV_SCHEMA');
  const text = buffer.toString('utf8');
  const lines = text.endsWith('\n') ? text.slice(0, -1).split('\n') : text.split('\n');
  const parsed = {};
  for (const line of lines) {
    const separator = line.indexOf('=');
    if (separator <= 0) fail('ENV_SCHEMA');
    const name = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (!ENV_NAMES.includes(name) || Object.hasOwn(parsed, name) || value.length === 0 || /[\r\n]/.test(value)) fail('ENV_SCHEMA');
    parsed[name] = value;
  }
  if (Object.keys(parsed).length !== ENV_NAMES.length || ENV_NAMES.some((name) => !Object.hasOwn(parsed, name))) fail('ENV_SCHEMA');
  return parsed;
}

function validateEnvReceipt(receipt, values) {
  exactKeys(receipt, ENV_RECEIPT_KEYS, 'ENV_RECEIPT_SCHEMA');
  if (receipt.schema_version !== 1 || receipt.purpose !== ENV_RECEIPT_PURPOSE || receipt.control_plane_source !== 'existing_authorized_credential') fail('ENV_RECEIPT_STATE');
  if (receipt.environment !== 'staging') fail('ENV_RECEIPT_STATE');
  requireBoolean(receipt.control_plane_pat_persisted, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.database_write, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.key_created, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.key_disabled, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.key_rotated, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.production_accessed, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.rejected_env_local_used, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.values_in_argv, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.values_in_git, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.values_printed, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.legacy_key_contract, false, 'ENV_RECEIPT_STATE');
  requireBoolean(receipt.preview_branch_verified_via_dashboard_and_api_keys, true, 'ENV_RECEIPT_STATE');
  if (receipt.local_elevated_secret_exposure !== 'none' || receipt.required_permission_verified !== 'yes') fail('ENV_RECEIPT_STATE');
  requireString(receipt.supabase_project_ref, 'STAGING_REF_MISMATCH');
  requireString(receipt.supabase_parent_project_ref, 'ENV_RECEIPT_STATE');
  if (receipt.supabase_parent_project_ref === receipt.supabase_project_ref) fail('ENV_RECEIPT_STATE');
  if (!Array.isArray(receipt.variables) || receipt.variables.length !== 3) fail('ENV_RECEIPT_SCHEMA');
  const names = [];
  for (const variable of receipt.variables) {
    exactKeys(variable, ['classification', 'name', 'sha256', 'validated'], 'ENV_RECEIPT_SCHEMA');
    if (!ENV_NAMES.includes(variable.name) || names.includes(variable.name) || variable.validated !== true) fail('ENV_RECEIPT_SCHEMA');
    const expectedClassification = variable.name === 'SUPABASE_SERVICE_ROLE_KEY' ? 'sensitive' : 'public';
    if (variable.classification !== expectedClassification) fail('ENV_RECEIPT_STATE');
    if (variable.sha256 !== sha256(Buffer.from(values[variable.name]))) fail('ENV_VALUE_HASH');
    names.push(variable.name);
  }
  if (ENV_NAMES.some((name) => !names.includes(name))) fail('ENV_RECEIPT_SCHEMA');
}

function validateDeploymentReceipt(receipt) {
  exactKeys(receipt, DEPLOYMENT_RECEIPT_KEYS, 'DEPLOYMENT_RECEIPT_SCHEMA');
  exactKeys(receipt.public_probes, ['attempted', 'forbidden_base', 'mobile', 'passed', 'prior_findings', 'summary_sha256'], 'DEPLOYMENT_RECEIPT_SCHEMA');
  requireNonnegativeIntegers({
    attempted: receipt.public_probes.attempted,
    forbidden_base: receipt.public_probes.forbidden_base,
    mobile: receipt.public_probes.mobile,
    passed: receipt.public_probes.passed,
    prior_findings: receipt.public_probes.prior_findings,
  }, 'DEPLOYMENT_RECEIPT_SCHEMA');
  if (receipt.schema_version !== 1 || receipt.purpose !== DEPLOYMENT_RECEIPT_PURPOSE) fail('DEPLOYMENT_RECEIPT_STATE');
  if (receipt.framework !== 'nextjs' || receipt.node !== '24.14.0' || receipt.root !== 'apps/mobile-bff') fail('DEPLOYMENT_RECEIPT_STATE');
  if (receipt.mobile_route_count !== receipt.route_count || receipt.route_count !== 40) fail('DEPLOYMENT_RECEIPT_STATE');
  if (receipt.public_probes.attempted !== receipt.public_probes.passed
    || receipt.public_probes.attempted !== receipt.public_probes.mobile + receipt.public_probes.forbidden_base + receipt.public_probes.prior_findings) fail('DEPLOYMENT_RECEIPT_STATE');
  for (const key of [
    'app_paths_manifest_sha256', 'build_log_sha256', 'canonical_route_path_stream_sha256',
    'incident_receipt_sha256', 'origin_sha256', 'preview_deployment_id_sha256',
    'preview_receipt_sha256', 'project_id_sha256', 'removed_original_deployment_id_sha256',
  ]) if (!isSha(receipt[key], [64])) fail('DEPLOYMENT_RECEIPT_STATE');
  if (!isSha(receipt.public_probes.summary_sha256, [64]) || !isSha(receipt.implementation_tree, [40]) || !isSha(receipt.recovery_authority_sha, [40])) fail('DEPLOYMENT_RECEIPT_STATE');
  if (!Array.isArray(receipt.env_metadata) || receipt.env_metadata.length !== 3) fail('DEPLOYMENT_RECEIPT_SCHEMA');
  const envMetadataNames = [];
  for (const entry of receipt.env_metadata) {
    exactKeys(entry, ['name', 'target', 'type'], 'DEPLOYMENT_RECEIPT_SCHEMA');
    if (!ENV_NAMES.includes(entry.name) || envMetadataNames.includes(entry.name)) fail('DEPLOYMENT_RECEIPT_SCHEMA');
    if (!Array.isArray(entry.target) || entry.target.length !== 1 || entry.target[0] !== 'preview') fail('ENV_COUNTS');
    requireString(entry.type, 'DEPLOYMENT_RECEIPT_SCHEMA');
    envMetadataNames.push(entry.name);
  }
  if (receipt.environment !== 'staging') fail('DEPLOYMENT_RECEIPT_STATE');
  if (receipt.ready_state !== 'READY') fail('PREVIEW_STATE');
  if (receipt.target !== 'preview') fail('PREVIEW_TARGET');
  if (receipt.production_deployment_count !== 0) fail('PRODUCTION_COUNT');
  if (receipt.env_preview_count !== 3 || receipt.env_production_count !== 0 || receipt.env_development_count !== 0) fail('ENV_COUNTS');
  if (receipt.sso_protection !== null) fail('SSO_STATE');
  if (receipt.implementation_sha !== EXPECTED_IMPLEMENTATION_SHA) fail('IMPLEMENTATION_SHA');
  if (receipt.api_target_representation !== null || receipt.project_link_absent !== true || receipt.original_removal_verified !== true) fail('DEPLOYMENT_RECEIPT_STATE');
  if (receipt.secret_values_absent !== true || receipt.token_absent !== true || receipt.team_default_mutation_requests !== 0) fail('DEPLOYMENT_RECEIPT_STATE');
  let origin;
  try {
    origin = new URL(receipt.preview_origin);
  } catch {
    fail('PREVIEW_ORIGIN');
  }
  if (origin.protocol !== 'https:' || origin.username || origin.password) fail('PREVIEW_ORIGIN');
  if (receipt.origin_sha256 !== sha256(Buffer.from(receipt.preview_origin))) fail('PREVIEW_ORIGIN');
}

function validateCredential(credential) {
  exactKeys(credential, CREDENTIAL_KEYS, 'CREDENTIAL_SCHEMA');
  if (credential.schema_version !== 1 || credential.environment !== 'staging' || credential.cleanup_required !== true || credential.synthetic_marker !== 'ci3-synthetic-patient') fail('CREDENTIAL_STATE');
  for (const key of ['created_at', 'email', 'expires_at', 'password', 'project_ref', 'synthetic_marker']) requireString(credential[key], 'CREDENTIAL_SCHEMA');
}

function validateProvisioningReceipt(receipt, deploymentReceipt) {
  exactKeys(receipt, PROVISIONING_RECEIPT_KEYS, 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.attempts, ATTEMPT_KEYS, 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.fixture_counts, ['auth', 'entitlement', 'event', 'identity', 'patient', 'profile', 'progress', 'storage'], 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.id_hashes, ['auth_user', 'entitlement', 'event', 'patient'], 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.request_ids, ['entitlements', 'me', 'today'], 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.response_structure_sha256, ['entitlements', 'me', 'today'], 'PROVISIONING_RECEIPT_SCHEMA');
  exactKeys(receipt.supabase_http_request_counts, ['patient', 'service'], 'PROVISIONING_RECEIPT_SCHEMA');
  requireNonnegativeIntegers(receipt.attempts, 'PROVISIONING_RECEIPT_SCHEMA');
  requireNonnegativeIntegers(receipt.fixture_counts, 'PROVISIONING_RECEIPT_SCHEMA');
  requireNonnegativeIntegers(receipt.supabase_http_request_counts, 'PROVISIONING_RECEIPT_SCHEMA');
  if (receipt.schema_version !== 1 || receipt.purpose !== PROVISIONING_RECEIPT_PURPOSE || !isSha(receipt.authority_sha, [40])) fail('PROVISIONING_RECEIPT_STATE');
  if (receipt.cleanup_deadline_class !== 'future' || receipt.auth_reused !== true || receipt.synthetic_marker !== 'ci3-synthetic-patient') fail('PROVISIONING_RECEIPT_STATE');
  const expectedAttempts = {
    auth_create: 1, auth_create_settlement: 1, auth_delete_rollback: 0,
    auth_preflight: 1, auth_readback: 1, auth_update: 0, bootstrap_readback: 1,
    entitlement_grant: 1, entitlement_readback: 1, entitlement_resolution: 1,
    entitlement_settlement: 1, entitlements_probe: 1, me_probe: 1,
    rollback_database_transaction: 0, rollback_settlement_read: 0, sign_in: 1,
    today_probe: 1,
  };
  for (const [key, value] of Object.entries(expectedAttempts)) if (receipt.attempts[key] !== value) fail('PROVISIONING_RECEIPT_STATE');
  const expectedFixtureCounts = { auth: 1, entitlement: 1, event: 1, identity: 1, patient: 1, profile: 1, progress: 0, storage: 0 };
  for (const [key, value] of Object.entries(expectedFixtureCounts)) if (receipt.fixture_counts[key] !== value) fail('PROVISIONING_RECEIPT_STATE');
  if (receipt.supabase_http_request_counts.patient !== 3 || receipt.supabase_http_request_counts.service !== 4) fail('PROVISIONING_RECEIPT_STATE');
  if (receipt.implementation_tree !== deploymentReceipt.implementation_tree) fail('IMPLEMENTATION_SHA');
  if (receipt.state !== 'TODAY_VERIFIED') fail('PROVISIONING_STATE');
  if (receipt.environment !== 'staging' || receipt.cleanup_required !== true) fail('PROVISIONING_STATE');
  if (receipt.implementation_sha !== EXPECTED_IMPLEMENTATION_SHA) fail('IMPLEMENTATION_SHA');
  requireBoolean(receipt.primary_live_open, false, 'PRIMARY_LIVE_STATE');
  requireBoolean(receipt.product_production_write, false, 'PRIMARY_LIVE_STATE');
  requireBoolean(receipt.token_persisted, false, 'TOKEN_STATE');
  requireBoolean(receipt.service_role_patient_bearer, false, 'SERVICE_ROLE_BEARER');
  requireBoolean(receipt.vercel_write, false, 'PROVISIONING_STATE');
  requireBoolean(receipt.ci3_started, false, 'PROVISIONING_STATE');
  requireBoolean(receipt.ci4_started, false, 'PROVISIONING_STATE');
  requireBoolean(receipt.health_data_absent, true, 'PROVISIONING_STATE');
  requireBoolean(receipt.raw_response_absent, true, 'PROVISIONING_STATE');
}

export function validateSourceDocuments({ credential, deploymentReceipt, envBytes, envReceipt, now, provisioningReceipt }) {
  const values = parseExactEnv(envBytes);
  validateEnvReceipt(envReceipt, values);
  validateDeploymentReceipt(deploymentReceipt);
  validateCredential(credential);
  validateProvisioningReceipt(provisioningReceipt, deploymentReceipt);

  const stagingRef = envReceipt.supabase_project_ref;
  let supabaseUrl;
  try {
    supabaseUrl = new URL(values.NEXT_PUBLIC_SUPABASE_URL);
  } catch {
    fail('STAGING_REF_MISMATCH');
  }
  if (supabaseUrl.protocol !== 'https:' || !supabaseUrl.hostname.startsWith(`${stagingRef}.`)) fail('STAGING_REF_MISMATCH');
  if (credential.project_ref !== stagingRef || provisioningReceipt.project_ref !== stagingRef) fail('CREDENTIAL_PROJECT');
  if (credential.synthetic_marker !== provisioningReceipt.synthetic_marker) fail('CREDENTIAL_STATE');
  if (credential.expires_at !== provisioningReceipt.cleanup_deadline || provisioningReceipt.expires_at !== provisioningReceipt.cleanup_deadline) fail('CLEANUP_DEADLINE');
  const deadline = Date.parse(provisioningReceipt.cleanup_deadline);
  const current = now instanceof Date ? now.getTime() : Date.parse(now);
  if (!Number.isFinite(deadline) || !Number.isFinite(current) || deadline <= current) fail('CLEANUP_DEADLINE');
  if (deploymentReceipt.implementation_sha !== provisioningReceipt.implementation_sha) fail('IMPLEMENTATION_SHA');

  return Object.freeze({
    cleanupDeadline: provisioningReceipt.cleanup_deadline,
    implementationSha: deploymentReceipt.implementation_sha,
    mobileBffOrigin: deploymentReceipt.preview_origin,
    stagingProjectRef: stagingRef,
    previewDeploymentCount: deploymentReceipt.target === 'preview' && deploymentReceipt.ready_state === 'READY' ? 1 : 0,
    supabaseAnonKey: values.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    supabaseUrl: values.NEXT_PUBLIC_SUPABASE_URL,
  });
}

function validateAuthority(authority) {
  if (!isSha(authority?.commit, [40])) fail('AUTHORITY_COMMIT');
  if (authority.parent !== AUTHORITY_PARENT) fail('AUTHORITY_PARENT');
  if (!isSha(authority.tree, [40])) fail('AUTHORITY_TREE');
  if (authority.subject !== AUTHORITY_SUBJECT) fail('AUTHORITY_SUBJECT');
  if (!isSha(authority.generator_blob_sha, [40, 64])) fail('GENERATOR_BLOB');
  if (!isSha(authority.generator_file_sha256, [64])) fail('GENERATOR_FILE_HASH');
  for (const key of ['controller_blob_oid', 'launcher_blob_oid', 'anchor_writer_blob_oid']) {
    if (!isSha(authority[key], [40])) fail('AUTHORITY_COMPONENTS');
  }
  for (const key of ['controller_file_sha256', 'launcher_file_sha256', 'anchor_writer_file_sha256', 'authority_tree_manifest_sha256', 'source_env_descriptor_identity_sha256']) {
    if (!isSha(authority[key], [64])) fail('AUTHORITY_COMPONENTS');
  }
  if (!/^rb-[a-f0-9]{64}$/.test(authority.remote_bundle_generation_id ?? '') || !/^src-[a-f0-9]{64}$/.test(authority.source_generation_id ?? '')) fail('AUTHORITY_COMPONENTS');
  if (!Number.isFinite(Date.parse(authority.committed_at_utc))) fail('AUTHORITY_COMMIT_TIME');
}

export function buildBundleArtifacts({ authority, credentialSourcePath, hashes, validated }) {
  validateAuthority(authority);
  if (credentialSourcePath !== INPUT_PATHS.credential) fail('CREDENTIAL_PATH');
  for (const key of ['env_source_sha256', 'env_receipt_sha256', 'deployment_receipt_sha256', 'credential_source_sha256', 'provisioning_receipt_sha256']) {
    if (!isSha(hashes?.[key], [64])) fail('SOURCE_HASH_BINDING');
  }

  const config = {
    schema_version: 1,
    environment: 'staging',
    supabase_url: validated.supabaseUrl,
    supabase_anon_key: validated.supabaseAnonKey,
    mobile_bff_origin: validated.mobileBffOrigin,
    staging_project_ref: validated.stagingProjectRef,
    bridge_authority_sha: authority.commit,
    cleanup_deadline: validated.cleanupDeadline,
  };
  const configBytes = jsonBytes(config);
  const receipt = {
    schema_version: 1,
    purpose: 'VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1',
    created_at_utc: authority.committed_at_utc,
    authority_commit: authority.commit,
    authority_parent: authority.parent,
    authority_tree: authority.tree,
    authority_subject: authority.subject,
    generator_blob_sha: authority.generator_blob_sha,
    generator_file_sha256: authority.generator_file_sha256,
    controller_blob_oid: authority.controller_blob_oid,
    controller_file_sha256: authority.controller_file_sha256,
    launcher_blob_oid: authority.launcher_blob_oid,
    launcher_file_sha256: authority.launcher_file_sha256,
    anchor_writer_blob_oid: authority.anchor_writer_blob_oid,
    anchor_writer_file_sha256: authority.anchor_writer_file_sha256,
    authority_tree_manifest_sha256: authority.authority_tree_manifest_sha256,
    remote_bundle_generation_id: authority.remote_bundle_generation_id,
    source_generation_id: authority.source_generation_id,
    source_env_descriptor_identity_sha256: authority.source_env_descriptor_identity_sha256,
    env_source_sha256: hashes.env_source_sha256,
    env_receipt_sha256: hashes.env_receipt_sha256,
    deployment_receipt_sha256: hashes.deployment_receipt_sha256,
    credential_source_path: credentialSourcePath,
    credential_source_sha256: hashes.credential_source_sha256,
    provisioning_receipt_sha256: hashes.provisioning_receipt_sha256,
    output_config_sha256: sha256(Buffer.from(configBytes)),
    output_filenames: ['mobile-staging-config.json', 'bridge.receipt.json'],
    staging_project_ref: validated.stagingProjectRef,
    implementation_sha: validated.implementationSha,
    preview_deployment_count: validated.previewDeploymentCount,
    production_deployment_count: 0,
    env_preview_count: 3,
    env_production_count: 0,
    env_development_count: 0,
    sso_state: null,
    cleanup_deadline: validated.cleanupDeadline,
    service_role_emitted: false,
    token_emitted: false,
    raw_values_reported: false,
    primary_opened: false,
    remote_bundle_immutable: true,
    terminal_scan_ids: [...TERMINAL_SCAN_IDS],
  };
  exactKeys(receipt, RECEIPT_KEYS, 'RECEIPT_SCHEMA');
  return Object.freeze({ config, configBytes, receipt, receiptBytes: jsonBytes(receipt) });
}

export function verifyFindingCoverage(findings) {
  if (!Array.isArray(findings) || findings.length !== EXPECTED_FINDING_IDS.length) fail('FINDING_COVERAGE');
  const ids = findings.map((finding) => finding?.id);
  if (new Set(ids).size !== ids.length || ids.some((id, index) => id !== EXPECTED_FINDING_IDS[index])) fail('FINDING_COVERAGE');
  for (const finding of findings) {
    exactKeys(finding, ['architecture', 'id', 'receipt_field', 'reviewer', 'terminal_gate', 'test'], 'FINDING_COVERAGE');
    if (!['A', 'B'].includes(finding.reviewer)) fail('FINDING_COVERAGE');
    for (const key of ['architecture', 'test', 'receipt_field', 'terminal_gate']) requireString(finding[key], 'FINDING_COVERAGE');
  }
  return true;
}

function identity(metadata) {
  if (metadata === null || typeof metadata !== 'object'
      || PHYSICAL_IDENTITY_FIELDS.some((field) => typeof metadata[field] !== 'bigint')) fail('INPUT_METADATA');
  return Object.fromEntries(PHYSICAL_IDENTITY_FIELDS.map((field) => [field, metadata[field]]));
}

function identitySha256(metadata) {
  const exact = canonicalPhysicalIdentity(identity(metadata));
  return sha256(Buffer.from([
    `uid=${exact.uid}`, `gid=${exact.gid}`, `mode=${BigInt(exact.mode) & 0o777n}`,
    `nlink=${exact.nlink}`, `size=${exact.size}`, `mtime=${exact.mtimeNs}`,
    `dev=${exact.dev}`, `ino=${exact.ino}`,
  ].join(';')));
}

async function readFixedInput(kind, expectedUid = 0) {
  const sourcePath = INPUT_PATHS[kind];
  assertKnownInputPath(sourcePath);
  const parentPath = path.dirname(sourcePath);
  const parentBefore = await lstat(parentPath, { bigint: true });
  validateParentMetadata(metadataView(parentBefore), expectedUid);
  const entryBefore = await lstat(sourcePath, { bigint: true });
  validateInputMetadata(metadataView(entryBefore), expectedUid);
  if (entryBefore.size <= 0n || entryBefore.size > BigInt(INPUT_SIZE_LIMITS[kind])) fail('INPUT_SIZE');

  let handle;
  try {
    handle = await open(sourcePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const descriptorBefore = await handle.stat({ bigint: true });
    validateInputMetadata(metadataView(descriptorBefore), expectedUid);
    const bytes = await handle.readFile();
    if (bytes.length <= 0 || bytes.length > INPUT_SIZE_LIMITS[kind]) fail('INPUT_SIZE');
    const descriptorAfter = await handle.stat({ bigint: true });
    assertStableIdentity(identity(descriptorBefore), identity(descriptorAfter));
    const entryAfter = await lstat(sourcePath, { bigint: true });
    assertStableIdentity(identity(descriptorAfter), identity(entryAfter));
    assertStableIdentity(identity(entryBefore), identity(entryAfter));
    const parentAfter = await lstat(parentPath, { bigint: true });
    validateParentMetadata(metadataView(parentAfter), expectedUid);
    assertStableIdentity(identity(parentBefore), identity(parentAfter));
    verifyExpectedHash(bytes, EXPECTED_INPUT_HASHES[kind]);
    return Object.freeze({
      bytes,
      identity_sha256: identitySha256(descriptorAfter),
      sha256: EXPECTED_INPUT_HASHES[kind],
    });
  } catch (error) {
    if (error instanceof BridgeError) throw error;
    fail('INPUT_READ');
  } finally {
    await handle?.close().catch(() => {});
  }
}

function parseJson(bytes, code) {
  try {
    return JSON.parse(Buffer.from(bytes).toString('utf8'));
  } catch {
    fail(code);
  }
}

function gitResult(...args) {
  const result = spawnSync('/usr/bin/git', ['-C', process.cwd(), ...args], {
    env: { PATH: '/usr/bin:/bin' },
    maxBuffer: 64 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0 || result.signal || result.stderr.length !== 0) fail('GIT_AUTHORITY');
  return result.stdout;
}

function gitText(...args) {
  return gitResult(...args).toString('utf8').trim();
}

async function readGitAuthority() {
  const repositoryRoot = gitText('rev-parse', '--show-toplevel');
  if (path.resolve(repositoryRoot) !== path.resolve(process.cwd())) fail('GIT_AUTHORITY');
  const commit = gitText('rev-parse', 'HEAD');
  const committedGeneratorBytes = gitResult('cat-file', 'blob', `${commit}:${GENERATOR_GIT_PATH}`);
  const expectedBlobSha = gitText('rev-parse', `${commit}:${GENERATOR_GIT_PATH}`);
  const expectedSnapshotPath = path.join(OUTPUT_ROOT, '.launchers', commit, path.basename(GENERATOR_GIT_PATH));
  if (path.resolve(SCRIPT_PATH) !== expectedSnapshotPath) fail('GENERATOR_LAUNCHER_REQUIRED');
  let handle;
  let snapshotBytes;
  let descriptorBefore;
  let descriptorAfter;
  try {
    handle = await open(SCRIPT_PATH, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    descriptorBefore = await handle.stat({ bigint: true });
    snapshotBytes = await handle.readFile();
    descriptorAfter = await handle.stat({ bigint: true });
  } catch {
    fail('GENERATOR_SNAPSHOT');
  } finally {
    await handle?.close().catch(() => {});
  }
  validateInputMetadata(metadataView(descriptorBefore), 0, 0);
  verifyExecutableSnapshot({
    after: identity(descriptorAfter), before: identity(descriptorBefore), expectedBlobSha,
    gitBlobBytes: committedGeneratorBytes, snapshotBytes,
  });
  const manifestEntries = AUTHORITY_PATHS.map((gitPath) => {
    const bytes = gitResult('cat-file', 'blob', `${commit}:${gitPath}`);
    const blobOid = gitText('rev-parse', `${commit}:${gitPath}`);
    if (gitBlobSha(bytes) !== blobOid) fail('GIT_AUTHORITY');
    return { path: gitPath, blob_oid: blobOid, sha256: sha256(bytes) };
  });
  validateAuthorityTreeManifest(manifestEntries);
  const manifestSha256 = sha256(Buffer.from(jsonBytes(manifestEntries)));
  const component = (gitPath) => {
    const entry = manifestEntries.find(({ path: candidate }) => candidate === gitPath);
    if (!entry) fail('GIT_AUTHORITY');
    return entry;
  };
  const authority = {
    commit,
    parent: gitText('rev-parse', 'HEAD^'),
    tree: gitText('rev-parse', 'HEAD^{tree}'),
    subject: gitText('show', '-s', '--format=%s', 'HEAD'),
    committed_at_utc: new Date(gitText('show', '-s', '--format=%cI', 'HEAD')).toISOString(),
    generator_blob_sha: expectedBlobSha,
    generator_file_sha256: sha256(snapshotBytes),
    controller_blob_oid: component('scripts/ci3/ci3-bridge-controller.mjs').blob_oid,
    controller_file_sha256: component('scripts/ci3/ci3-bridge-controller.mjs').sha256,
    launcher_blob_oid: component('scripts/ci3/ci3-bridge-launcher.zsh').blob_oid,
    launcher_file_sha256: component('scripts/ci3/ci3-bridge-launcher.zsh').sha256,
    anchor_writer_blob_oid: component('scripts/ci3/ci3-terminal-anchor-writer.swift').blob_oid,
    anchor_writer_file_sha256: component('scripts/ci3/ci3-terminal-anchor-writer.swift').sha256,
    authority_tree_manifest_sha256: manifestSha256,
    remote_bundle_generation_id: null,
    source_generation_id: null,
    source_env_descriptor_identity_sha256: null,
  };
  return authority;
}

async function pathExists(candidate) {
  try {
    return await lstat(candidate, { bigint: true });
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

function metadataView(metadata) {
  const exact = identity(metadata);
  return {
    ...exact,
    isFile: metadata.isFile(), isDirectory: metadata.isDirectory(),
    isSymbolicLink: metadata.isSymbolicLink(),
  };
}

function validatePrivateDirectory(metadata, expectedUid, expectedGid, code = 'EXISTING_BUNDLE_DIVERGENT') {
  const view = metadataView(metadata);
  if (!view.isDirectory || view.isSymbolicLink
      || boundedStatNumber(view.uid, code) !== expectedUid
      || boundedStatNumber(view.gid, code) !== expectedGid
      || (boundedStatNumber(view.mode, code) & 0o777) !== 0o700) fail(code);
}

export async function validateDirectoryChainNoSymlinks(candidate, trustedRoot = path.parse(path.resolve(candidate)).root) {
  const absoluteCandidate = path.resolve(candidate);
  const absoluteRoot = path.resolve(trustedRoot);
  const relative = path.relative(absoluteRoot, absoluteCandidate);
  if (relative.startsWith('..') || path.isAbsolute(relative)) fail('DIRECTORY_CHAIN');
  let current = absoluteRoot;
  for (const component of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, component);
    try {
      const metadata = await lstat(current, { bigint: true });
      if (!metadata.isDirectory() || metadata.isSymbolicLink()) fail('DIRECTORY_CHAIN');
    } catch (error) {
      if (error instanceof BridgeError) throw error;
      if (error?.code === 'ENOENT') return true;
      fail('DIRECTORY_CHAIN');
    }
  }
  return true;
}

export async function readBoundOwnerOnlyFile(
  filename, expectedUid, expectedGid, expectedHash,
  code = 'EXISTING_BUNDLE_DIVERGENT', { lstatFn = lstat, openFn = open } = {},
) {
  let handle;
  try {
    if (typeof lstatFn !== 'function' || typeof openFn !== 'function') fail(code);
    const entryBeforeRaw = await lstatFn(filename, { bigint: true });
    const entryBefore = metadataView(entryBeforeRaw);
    validateInputMetadata(entryBefore, expectedUid, expectedGid);
    handle = await openFn(filename, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const descriptorBefore = metadataView(await handle.stat({ bigint: true }));
    validateInputMetadata(descriptorBefore, expectedUid, expectedGid);
    const bytes = await handle.readFile();
    const descriptorAfter = metadataView(await handle.stat({ bigint: true }));
    assertStableIdentity(descriptorBefore, descriptorAfter);
    const entryAfter = metadataView(await lstatFn(filename, { bigint: true }));
    assertStableIdentity(descriptorAfter, entryAfter);
    assertStableIdentity(entryBefore, entryAfter);
    if (expectedHash && sha256(bytes) !== expectedHash) fail(code);
    return Object.freeze({ bytes, metadata: descriptorAfter });
  } catch (error) {
    if (error instanceof BridgeError) {
      if (error.code === code) throw error;
      fail(code);
    }
    fail(code);
  } finally {
    await handle?.close().catch(() => {});
  }
}

function validatePublishedContract(configBytes, receiptBytes, claim) {
  const code = 'PUBLISHED_CONTRACT';
  const config = parseJson(configBytes, code);
  const receipt = parseJson(receiptBytes, code);
  exactKeys(config, ['bridge_authority_sha', 'cleanup_deadline', 'environment', 'mobile_bff_origin', 'schema_version', 'staging_project_ref', 'supabase_anon_key', 'supabase_url'], code);
  exactKeys(receipt, RECEIPT_KEYS, code);
  if (config.schema_version !== 1 || config.environment !== 'staging' || config.bridge_authority_sha !== receipt.authority_commit) fail(code);
  for (const key of ['cleanup_deadline', 'mobile_bff_origin', 'staging_project_ref', 'supabase_anon_key', 'supabase_url']) requireString(config[key], code);
  let supabaseUrl;
  let mobileBffOrigin;
  try {
    supabaseUrl = new URL(config.supabase_url);
    mobileBffOrigin = new URL(config.mobile_bff_origin);
  } catch {
    fail(code);
  }
  if (supabaseUrl.protocol !== 'https:' || !supabaseUrl.hostname.startsWith(`${config.staging_project_ref}.`) || mobileBffOrigin.protocol !== 'https:') fail(code);
  if (receipt.schema_version !== 1 || receipt.authority_commit !== claim.authority_commit || receipt.purpose !== 'VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1') fail(code);
  if (receipt.authority_parent !== AUTHORITY_PARENT || receipt.authority_parent !== claim.authority_parent
      || receipt.authority_subject !== AUTHORITY_SUBJECT || receipt.authority_subject !== claim.authority_subject
      || !isSha(receipt.authority_tree, [40]) || receipt.authority_tree !== claim.authority_tree) fail(code);
  if (!isSha(receipt.generator_blob_sha, [40]) || receipt.generator_blob_sha !== claim.generator_blob_oid
      || !isSha(receipt.generator_file_sha256, [64]) || receipt.generator_file_sha256 !== claim.generator_file_sha256) fail(code);
  for (const key of ['controller_blob_oid', 'launcher_blob_oid', 'anchor_writer_blob_oid']) {
    if (!isSha(receipt[key], [40]) || receipt[key] !== claim[key]) fail(code);
  }
  for (const key of ['controller_file_sha256', 'launcher_file_sha256', 'anchor_writer_file_sha256', 'authority_tree_manifest_sha256', 'source_env_descriptor_identity_sha256']) {
    if (!isSha(receipt[key], [64]) || receipt[key] !== claim[key]) fail(code);
  }
  if (!/^rb-[a-f0-9]{64}$/.test(receipt.remote_bundle_generation_id) || receipt.remote_bundle_generation_id !== claim.remote_bundle_generation_id) fail(code);
  if (!/^src-[a-f0-9]{64}$/.test(receipt.source_generation_id) || receipt.source_generation_id !== claim.source_generation_id) fail(code);
  if (!Number.isFinite(Date.parse(receipt.created_at_utc)) || receipt.output_config_sha256 !== sha256(configBytes)) fail(code);
  if (JSON.stringify(receipt.output_filenames) !== JSON.stringify(['mobile-staging-config.json', 'bridge.receipt.json'])) fail(code);
  if (receipt.credential_source_path !== INPUT_PATHS.credential || receipt.staging_project_ref !== config.staging_project_ref || receipt.implementation_sha !== EXPECTED_IMPLEMENTATION_SHA) fail(code);
  if (receipt.cleanup_deadline !== config.cleanup_deadline || !Number.isFinite(Date.parse(receipt.cleanup_deadline))) fail(code);
  if (receipt.preview_deployment_count !== 1 || receipt.production_deployment_count !== 0 || receipt.env_preview_count !== 3 || receipt.env_production_count !== 0 || receipt.env_development_count !== 0 || receipt.sso_state !== null) fail(code);
  for (const key of ['service_role_emitted', 'token_emitted', 'raw_values_reported', 'primary_opened']) if (receipt[key] !== false) fail(code);
  if (receipt.remote_bundle_immutable !== true) fail(code);
  if (JSON.stringify(receipt.terminal_scan_ids) !== JSON.stringify(TERMINAL_SCAN_IDS)) fail(code);
  for (const key of ['env_source_sha256', 'env_receipt_sha256', 'deployment_receipt_sha256', 'credential_source_sha256', 'provisioning_receipt_sha256']) {
    if (!isSha(receipt[key], [64]) || receipt[key] !== claim.source_hashes[key]) fail(code);
  }
  return true;
}

async function classifyPublicationVisibility(finalPath, expectedUid, expectedGid, code) {
  const finalMetadata = await pathExists(finalPath);
  if (!finalMetadata) return 'ABSENT';
  validatePrivateDirectory(finalMetadata, expectedUid, expectedGid, code);
  const entries = (await readdir(finalPath)).sort();
  if (JSON.stringify(entries) === JSON.stringify(['mobile-staging-config.json'])) return 'UNPUBLISHED';
  if (JSON.stringify(entries) !== JSON.stringify(['bridge.receipt.json', 'mobile-staging-config.json'])) fail(code);
  try {
    validateInputMetadata(metadataView(await lstat(path.join(finalPath, 'bridge.receipt.json'), { bigint: true })), expectedUid, expectedGid);
  } catch {
    fail(code);
  }
  return 'COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION';
}

export async function inspectPublicationVisibility({ finalPath, expectedUid = process.getuid?.() ?? 0, expectedGid = process.getgid?.() ?? 0 }) {
  if (typeof finalPath !== 'string' || !path.isAbsolute(finalPath)) fail('PUBLICATION_VISIBILITY');
  return classifyPublicationVisibility(finalPath, expectedUid, expectedGid, 'PUBLICATION_VISIBILITY');
}

async function verifyExistingBundle(finalPath, claim, expectedUid, expectedGid, status = 'EXISTS_VERIFIED') {
  const finalBefore = await lstat(finalPath, { bigint: true });
  validatePrivateDirectory(finalBefore, expectedUid, expectedGid);
  const entries = (await readdir(finalPath)).sort();
  if (entries.length !== 2 || entries[0] !== 'bridge.receipt.json' || entries[1] !== 'mobile-staging-config.json') fail('EXISTING_BUNDLE_DIVERGENT');
  const config = await readBoundOwnerOnlyFile(path.join(finalPath, 'mobile-staging-config.json'), expectedUid, expectedGid, claim.config_sha256);
  const receipt = await readBoundOwnerOnlyFile(path.join(finalPath, 'bridge.receipt.json'), expectedUid, expectedGid, claim.receipt_sha256);
  validatePublishedContract(config.bytes, receipt.bytes, claim);
  const finalAfter = await lstat(finalPath, { bigint: true });
  assertStableIdentity(identity(finalBefore), identity(finalAfter));
  return { finalPath, status };
}

async function invokeHook(hooks, name, payload) {
  if (hooks?.[name]) await hooks[name](payload);
}

async function writeExclusiveAndSync(filename, bytes, trace, label) {
  let handle;
  try {
    handle = await open(filename, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW, 0o600);
    await handle.writeFile(bytes);
    await handle.sync();
    trace?.push(`fsync:${label}`);
  } finally {
    await handle?.close().catch(() => {});
  }
}

async function syncDirectory(directory, trace, label) {
  const handle = await open(directory, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
  try {
    await handle.sync();
    trace?.push(`fsync:${label}`);
  } finally {
    await handle.close();
  }
}

function sourceHashesFromReceipt(receipt) {
  const sourceHashes = {
    env_source_sha256: receipt.env_source_sha256,
    env_receipt_sha256: receipt.env_receipt_sha256,
    deployment_receipt_sha256: receipt.deployment_receipt_sha256,
    credential_source_sha256: receipt.credential_source_sha256,
    provisioning_receipt_sha256: receipt.provisioning_receipt_sha256,
  };
  for (const value of Object.values(sourceHashes)) if (!isSha(value, [64])) fail('PUBLISHED_CONTRACT');
  return Object.freeze(sourceHashes);
}

function buildPublicationClaim(authoritySha, configBuffer, receiptBuffer) {
  const receipt = parseJson(receiptBuffer, 'PUBLISHED_CONTRACT');
  const claim = {
    schema_version: 1,
    purpose: 'CI3_REMOTE_BUNDLE_CREATION_CLAIM_V1',
    authority_commit: authoritySha,
    authority_parent: receipt.authority_parent,
    authority_tree: receipt.authority_tree,
    authority_subject: receipt.authority_subject,
    generator_blob_oid: receipt.generator_blob_sha,
    generator_file_sha256: receipt.generator_file_sha256,
    attempt: 1,
    no_retry: true,
    config_sha256: sha256(configBuffer),
    receipt_sha256: sha256(receiptBuffer),
    source_hashes: sourceHashesFromReceipt(receipt),
    controller_blob_oid: receipt.controller_blob_oid,
    controller_file_sha256: receipt.controller_file_sha256,
    launcher_blob_oid: receipt.launcher_blob_oid,
    launcher_file_sha256: receipt.launcher_file_sha256,
    anchor_writer_blob_oid: receipt.anchor_writer_blob_oid,
    anchor_writer_file_sha256: receipt.anchor_writer_file_sha256,
    authority_tree_manifest_sha256: receipt.authority_tree_manifest_sha256,
    remote_bundle_generation_id: receipt.remote_bundle_generation_id,
    source_generation_id: receipt.source_generation_id,
    source_env_descriptor_identity_sha256: receipt.source_env_descriptor_identity_sha256,
  };
  validatePublishedContract(configBuffer, receiptBuffer, claim);
  return claim;
}

function validatePublicationClaim(claim, authoritySha) {
  exactKeys(claim, [
    'anchor_writer_blob_oid', 'anchor_writer_file_sha256', 'attempt', 'authority_commit',
    'authority_parent', 'authority_subject', 'authority_tree',
    'authority_tree_manifest_sha256', 'config_sha256', 'controller_blob_oid',
    'controller_file_sha256', 'launcher_blob_oid', 'launcher_file_sha256',
    'generator_blob_oid', 'generator_file_sha256',
    'no_retry', 'purpose', 'receipt_sha256', 'remote_bundle_generation_id',
    'schema_version', 'source_env_descriptor_identity_sha256', 'source_generation_id',
    'source_hashes',
  ], 'PUBLICATION_CLAIM');
  exactKeys(claim.source_hashes, ['credential_source_sha256', 'deployment_receipt_sha256', 'env_receipt_sha256', 'env_source_sha256', 'provisioning_receipt_sha256'], 'PUBLICATION_CLAIM');
  if (claim.schema_version !== 1 || claim.purpose !== 'CI3_REMOTE_BUNDLE_CREATION_CLAIM_V1'
      || claim.authority_commit !== authoritySha || claim.authority_parent !== AUTHORITY_PARENT
      || claim.authority_subject !== AUTHORITY_SUBJECT || !isSha(claim.authority_tree, [40])
      || claim.attempt !== 1 || claim.no_retry !== true) fail('PUBLICATION_CLAIM');
  for (const value of [claim.config_sha256, claim.receipt_sha256, ...Object.values(claim.source_hashes)]) if (!isSha(value, [64])) fail('PUBLICATION_CLAIM');
  for (const key of ['generator_blob_oid', 'controller_blob_oid', 'launcher_blob_oid', 'anchor_writer_blob_oid']) if (!isSha(claim[key], [40])) fail('PUBLICATION_CLAIM');
  for (const key of ['generator_file_sha256', 'controller_file_sha256', 'launcher_file_sha256', 'anchor_writer_file_sha256', 'authority_tree_manifest_sha256', 'source_env_descriptor_identity_sha256']) if (!isSha(claim[key], [64])) fail('PUBLICATION_CLAIM');
  if (!/^rb-[a-f0-9]{64}$/.test(claim.remote_bundle_generation_id) || !/^src-[a-f0-9]{64}$/.test(claim.source_generation_id)) fail('PUBLICATION_CLAIM');
  return true;
}

async function acquirePublicationClaim({ authoritySha, configBuffer, hooks, outputRoot, receiptBuffer, trace, expectedUid, expectedGid }) {
  const authorityRoot = path.join(outputRoot, authoritySha);
  try { await mkdir(authorityRoot, { mode: 0o700 }); } catch (error) { if (error?.code !== 'EEXIST') throw error; }
  validatePrivateDirectory(await lstat(authorityRoot, { bigint: true }), expectedUid, expectedGid, 'PUBLICATION_CLAIM');
  await validateDirectoryChainNoSymlinks(authorityRoot, outputRoot);
  const existingClaimNames = (await readdir(authorityRoot)).filter((name) => /^rb-[a-f0-9]{64}\.claim\.json$/.test(name));
  if (existingClaimNames.length > 1) fail('PUBLICATION_CLAIM');
  if (existingClaimNames.length === 1) {
    const claimPath = path.join(authorityRoot, existingClaimNames[0]);
    const existing = await readBoundOwnerOnlyFile(claimPath, expectedUid, expectedGid, null, 'PUBLICATION_CLAIM');
    const claim = parseJson(existing.bytes, 'PUBLICATION_CLAIM');
    validatePublicationClaim(claim, authoritySha);
    if (`${claim.remote_bundle_generation_id}.claim.json` !== existingClaimNames[0]) fail('PUBLICATION_CLAIM');
    return { authorityRoot, claim, claimPath, created: false };
  }
  const proposed = buildPublicationClaim(authoritySha, configBuffer, receiptBuffer);
  const claimPath = path.join(authorityRoot, `${proposed.remote_bundle_generation_id}.claim.json`);
  let claimHandle;
  try {
    claimHandle = await open(claimPath, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW, 0o600);
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
    const existing = await readBoundOwnerOnlyFile(claimPath, expectedUid, expectedGid, null, 'PUBLICATION_CLAIM');
    const claim = parseJson(existing.bytes, 'PUBLICATION_CLAIM');
    validatePublicationClaim(claim, authoritySha);
    return { authorityRoot, claim, claimPath, created: false };
  }
  try {
    await claimHandle.writeFile(Buffer.from(jsonBytes(proposed)));
    await claimHandle.sync();
    trace?.push('fsync:claim');
    await syncDirectory(authorityRoot, trace, 'claim-parent');
    await invokeHook(hooks, 'afterClaimFsynced', { claimPath, outputRoot });
    return { authorityRoot, claim: proposed, claimPath, created: true };
  } finally {
    await claimHandle.close().catch(() => {});
  }
}

async function promoteNoReplace(stagingFile, finalFile, expectedHash, expectedUid, expectedGid, hooks, linkedHook) {
  const stagingMetadata = await pathExists(stagingFile);
  const finalMetadata = await pathExists(finalFile);
  if (finalMetadata) {
    if (stagingMetadata && stagingMetadata.dev === finalMetadata.dev && stagingMetadata.ino === finalMetadata.ino) {
      await unlink(stagingFile);
      await readBoundOwnerOnlyFile(finalFile, expectedUid, expectedGid, expectedHash);
      return;
    }
    if (!stagingMetadata) {
      await readBoundOwnerOnlyFile(finalFile, expectedUid, expectedGid, expectedHash);
      return;
    }
    fail('FINAL_PATH_RACE');
  }
  if (!stagingMetadata) fail('CLAIM_CONSUMED_NO_CAPTURE');
  try {
    await link(stagingFile, finalFile);
  } catch (error) {
    if (error?.code === 'EEXIST') fail('FINAL_PATH_RACE');
    throw error;
  }
  await invokeHook(hooks, linkedHook, { finalFile, stagingFile });
  await unlink(stagingFile);
  await readBoundOwnerOnlyFile(finalFile, expectedUid, expectedGid, expectedHash);
}

async function completeInterruptedPromotions(stagingPath, finalPath) {
  if (!await pathExists(stagingPath) || !await pathExists(finalPath)) return;
  for (const filename of ['mobile-staging-config.json', 'bridge.receipt.json']) {
    const stagingFile = path.join(stagingPath, filename);
    const finalFile = path.join(finalPath, filename);
    const staged = await pathExists(stagingFile);
    const final = await pathExists(finalFile);
    if (!staged || !final || staged.dev !== final.dev || staged.ino !== final.ino) continue;
    if (staged.nlink !== 2n || final.nlink !== 2n) fail('STAGING_DIVERGENT');
    await unlink(stagingFile);
  }
}

const publicationLocks = new Map();

async function publishAtomicUnlocked({ authoritySha, configBytes, hooks, outputRoot, receiptBytes, trace, expectedUid, expectedGid }) {
  if (!isSha(authoritySha, [40])) fail('AUTHORITY_COMMIT');
  const configBuffer = Buffer.from(configBytes);
  const receiptBuffer = Buffer.from(receiptBytes);
  const rootMetadata = await lstat(outputRoot, { bigint: true });
  validatePrivateDirectory(rootMetadata, expectedUid, expectedGid, 'OUTPUT_ROOT_METADATA');
  await validateDirectoryChainNoSymlinks(outputRoot, outputRoot);
  const { authorityRoot, claim, claimPath, created: claimCreated } = await acquirePublicationClaim({ authoritySha, configBuffer, hooks, outputRoot, receiptBuffer, trace, expectedUid, expectedGid });
  const finalPath = path.join(authorityRoot, claim.remote_bundle_generation_id);
  const stagingPath = path.join(authorityRoot, `.staging-${claim.remote_bundle_generation_id}`);
  await completeInterruptedPromotions(stagingPath, finalPath);
  let partialFinal = false;
  const initialVisibility = await classifyPublicationVisibility(finalPath, expectedUid, expectedGid, 'EXISTING_BUNDLE_DIVERGENT');
  if (initialVisibility === 'COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION') {
    const existingRootBefore = await lstat(outputRoot, { bigint: true });
    const result = await verifyExistingBundle(finalPath, claim, expectedUid, expectedGid);
    const existingRootAfter = await lstat(outputRoot, { bigint: true });
    assertStableIdentity(identity(existingRootBefore), identity(existingRootAfter));
    await validateDirectoryChainNoSymlinks(finalPath, outputRoot);
    return { ...result, claimPath };
  }
  if (initialVisibility === 'UNPUBLISHED') {
    if (claimCreated) fail('EXISTING_BUNDLE_DIVERGENT');
    await readBoundOwnerOnlyFile(path.join(finalPath, 'mobile-staging-config.json'), expectedUid, expectedGid, claim.config_sha256);
    partialFinal = true;
  }

  const stagingMetadata = await pathExists(stagingPath);
  if (!claimCreated && !stagingMetadata) fail('CLAIM_CONSUMED_NO_CAPTURE');
  if (!stagingMetadata) {
    await mkdir(stagingPath, { mode: 0o700 });
    trace?.push('mkdir:staging');
    await invokeHook(hooks, 'afterStagingCreated', { outputRoot, stagingPath });
    await writeExclusiveAndSync(path.join(stagingPath, 'mobile-staging-config.json'), configBuffer, trace, 'config');
    await writeExclusiveAndSync(path.join(stagingPath, 'bridge.receipt.json'), receiptBuffer, trace, 'receipt');
    await invokeHook(hooks, 'afterFilesFsynced', { stagingPath });
    await syncDirectory(stagingPath, trace, 'staging');
    await invokeHook(hooks, 'afterStagingFsynced', { stagingPath });
  } else {
    validatePrivateDirectory(await lstat(stagingPath, { bigint: true }), expectedUid, expectedGid, 'STAGING_DIVERGENT');
  }

  const stagingConfigPath = path.join(stagingPath, 'mobile-staging-config.json');
  const stagingConfig = await readBoundOwnerOnlyFile(
    await pathExists(stagingConfigPath) ? stagingConfigPath : path.join(finalPath, 'mobile-staging-config.json'),
    expectedUid, expectedGid, claim.config_sha256, 'STAGING_DIVERGENT',
  );
  const stagingReceipt = await readBoundOwnerOnlyFile(path.join(stagingPath, 'bridge.receipt.json'), expectedUid, expectedGid, claim.receipt_sha256, 'STAGING_DIVERGENT');
  validatePublishedContract(stagingConfig.bytes, stagingReceipt.bytes, claim);
  await invokeHook(hooks, 'beforeRename', { finalPath, stagingPath });
  if (!partialFinal) {
    try {
      await mkdir(finalPath, { mode: 0o700 });
    } catch (error) {
      if (error?.code === 'EEXIST') fail('FINAL_PATH_RACE');
      throw error;
    }
  }
  await promoteNoReplace(path.join(stagingPath, 'mobile-staging-config.json'), path.join(finalPath, 'mobile-staging-config.json'), claim.config_sha256, expectedUid, expectedGid, hooks, 'afterConfigLinked');
  await invokeHook(hooks, 'afterConfigPublished', { finalPath, stagingPath });
  await invokeHook(hooks, 'beforeReceiptCommit', { finalPath, stagingPath });
  await promoteNoReplace(path.join(stagingPath, 'bridge.receipt.json'), path.join(finalPath, 'bridge.receipt.json'), claim.receipt_sha256, expectedUid, expectedGid, hooks, 'afterReceiptLinked');
  trace?.push('link:receipt-commit');
  await syncDirectory(finalPath, trace, 'final');
  await invokeHook(hooks, 'afterRename', { finalPath });
  await syncDirectory(authorityRoot, trace, 'parent');
  await verifyExistingBundle(finalPath, claim, expectedUid, expectedGid, claimCreated ? 'CREATED' : 'RECOVERED');
  return { claimPath, finalPath, status: claimCreated ? 'CREATED' : 'RECOVERED' };
}

export async function publishAtomic(options) {
  const rootMetadata = await lstat(options.outputRoot, { bigint: true });
  const expectedUid = options.expectedUid ?? boundedStatNumber(rootMetadata.uid, 'OUTPUT_ROOT');
  const expectedGid = options.expectedGid ?? boundedStatNumber(rootMetadata.gid, 'OUTPUT_ROOT');
  const key = `${path.resolve(options.outputRoot)}:${options.authoritySha}`;
  const previous = publicationLocks.get(key) ?? Promise.resolve();
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  const chain = previous.catch(() => {}).then(() => held);
  publicationLocks.set(key, chain);
  await previous.catch(() => {});
  try {
    return await publishAtomicUnlocked({ ...options, expectedUid, expectedGid });
  } finally {
    release();
    if (publicationLocks.get(key) === chain) publicationLocks.delete(key);
  }
}

async function recoverPublicationIfClaimed({ authoritySha, outputRoot, expectedUid, expectedGid }) {
  const authorityRoot = path.join(outputRoot, authoritySha);
  if (!await pathExists(authorityRoot)) return null;
  validatePrivateDirectory(await lstat(authorityRoot, { bigint: true }), expectedUid, expectedGid, 'PUBLICATION_CLAIM');
  const claimNames = (await readdir(authorityRoot)).filter((name) => /^rb-[a-f0-9]{64}\.claim\.json$/.test(name));
  if (claimNames.length === 0) return null;
  if (claimNames.length !== 1) fail('PUBLICATION_CLAIM');
  const claimPath = path.join(authorityRoot, claimNames[0]);
  const claimFile = await readBoundOwnerOnlyFile(claimPath, expectedUid, expectedGid, null, 'PUBLICATION_CLAIM');
  const claim = parseJson(claimFile.bytes, 'PUBLICATION_CLAIM');
  validatePublicationClaim(claim, authoritySha);
  if (`${claim.remote_bundle_generation_id}.claim.json` !== claimNames[0]) fail('PUBLICATION_CLAIM');
  const finalPath = path.join(authorityRoot, claim.remote_bundle_generation_id);
  const stagingPath = path.join(authorityRoot, `.staging-${claim.remote_bundle_generation_id}`);
  await completeInterruptedPromotions(stagingPath, finalPath);
  const visibility = await classifyPublicationVisibility(finalPath, expectedUid, expectedGid, 'EXISTING_BUNDLE_DIVERGENT');
  if (visibility === 'COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION') return { ...(await verifyExistingBundle(finalPath, claim, expectedUid, expectedGid)), claimPath };
  if (!await pathExists(stagingPath)) fail('CLAIM_CONSUMED_NO_CAPTURE');
  const stagedConfigPath = path.join(stagingPath, 'mobile-staging-config.json');
  const config = await readBoundOwnerOnlyFile(await pathExists(stagedConfigPath) ? stagedConfigPath : path.join(finalPath, 'mobile-staging-config.json'), expectedUid, expectedGid, claim.config_sha256, 'STAGING_DIVERGENT');
  const receipt = await readBoundOwnerOnlyFile(path.join(stagingPath, 'bridge.receipt.json'), expectedUid, expectedGid, claim.receipt_sha256, 'STAGING_DIVERGENT');
  return publishAtomic({ authoritySha, configBytes: config.bytes, expectedGid, expectedUid, outputRoot, receiptBytes: receipt.bytes });
}

function requireSha256(value, code) {
  if (!isSha(value, [64])) fail(code);
}

function requireShaList(values, code) {
  if (!Array.isArray(values) || values.length === 0) fail(code);
  for (const value of values) requireSha256(value, code);
}

export function buildLocalPublicationReceipt({ authoritySha, claimResultHashes, localConfigSha256, localCredentialSha256, remoteReceiptSha256, simulatorGateSha256, sshEffectiveConfigSha256 }) {
  if (!isSha(authoritySha, [40])) fail('LOCAL_PUBLICATION_RECEIPT');
  requireShaList(claimResultHashes, 'LOCAL_PUBLICATION_RECEIPT');
  for (const value of [localConfigSha256, localCredentialSha256, remoteReceiptSha256, simulatorGateSha256, sshEffectiveConfigSha256]) requireSha256(value, 'LOCAL_PUBLICATION_RECEIPT');
  return Object.freeze({
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLICATION_RECEIPT_V1',
    authority_sha: authoritySha,
    remote_receipt_sha256: remoteReceiptSha256,
    local_config_sha256: localConfigSha256,
    local_credential_sha256: localCredentialSha256,
    ssh_effective_config_sha256: sshEffectiveConfigSha256,
    simulator_gate_sha256: simulatorGateSha256,
    claim_result_hashes: [...claimResultHashes],
    terminal_state: 'PRE_TERMINAL',
  });
}

export function buildTerminalReceipt({ authoritySha, installationReceiptSha256, localPublicationReceiptSha256, scanPhaseHashes, simulatorPhaseRootSha256 }) {
  if (!isSha(authoritySha, [40])) fail('TERMINAL_RECEIPT');
  for (const value of [installationReceiptSha256, localPublicationReceiptSha256, simulatorPhaseRootSha256]) requireSha256(value, 'TERMINAL_RECEIPT');
  if (!Array.isArray(scanPhaseHashes) || scanPhaseHashes.length !== TERMINAL_SCAN_IDS.length) fail('TERMINAL_RECEIPT');
  for (let index = 0; index < TERMINAL_SCAN_IDS.length; index += 1) {
    const entry = scanPhaseHashes[index];
    exactKeys(entry, ['claim_sha256', 'id', 'receipt_sha256', 'result_sha256'], 'TERMINAL_RECEIPT');
    if (entry.id !== TERMINAL_SCAN_IDS[index]) fail('TERMINAL_RECEIPT');
    for (const field of ['claim_sha256', 'receipt_sha256', 'result_sha256']) requireSha256(entry[field], 'TERMINAL_RECEIPT');
  }
  return Object.freeze({
    schema_version: 1,
    purpose: 'CI3_TERMINAL_BRIDGE_RECEIPT_V1',
    authority_sha: authoritySha,
    local_publication_receipt_sha256: localPublicationReceiptSha256,
    installation_receipt_sha256: installationReceiptSha256,
    scan_phase_receipts: structuredClone(scanPhaseHashes),
    simulator_phase_root_sha256: simulatorPhaseRootSha256,
    important_ids: [...TERMINAL_IMPORTANT_FINDING_IDS],
    terminal_state: 'TERMINAL_PASS',
  });
}

export function buildTerminalAnchorRecord({
  authoritySha,
  privilegedWriterAuthority,
  privilegedWriterAuthorityBytes,
  privilegedWriterAuthoritySha256,
  terminalAnchorPath,
  terminalReceiptPath,
  terminalReceiptSha256,
}) {
  if (!isSha(authoritySha, [40]) || typeof terminalReceiptPath !== 'string' || !path.isAbsolute(terminalReceiptPath)) fail('TERMINAL_ANCHOR_SCHEMA');
  if (typeof terminalAnchorPath !== 'string' || !path.isAbsolute(terminalAnchorPath)) fail('PRIVILEGED_ANCHOR_WRITER_AUTHORITY');
  validatePrivilegedAnchorWriterAuthority({
    authority: privilegedWriterAuthority,
    authorityBytes: privilegedWriterAuthorityBytes,
    bridgeAuthoritySha: authoritySha,
    expectedSha256: privilegedWriterAuthoritySha256,
  });
  if (privilegedWriterAuthority.anchor_path_sha256 !== sha256(Buffer.from(terminalAnchorPath))) fail('PRIVILEGED_ANCHOR_WRITER_AUTHORITY');
  requireSha256(terminalReceiptSha256, 'TERMINAL_ANCHOR_SCHEMA');
  return Object.freeze({
    schema_version: 1,
    purpose: 'CI3_TERMINAL_AUTHORITY_ANCHOR_V1',
    authority_sha: authoritySha,
    terminal_receipt_path: terminalReceiptPath,
    terminal_receipt_sha256: terminalReceiptSha256,
    append_only: true,
    no_clobber: true,
  });
}

export function validatePrivilegedAnchorWriterAuthority({ authority, authorityBytes, bridgeAuthoritySha, expectedSha256 }) {
  const code = 'PRIVILEGED_ANCHOR_WRITER_AUTHORITY';
  if (!isSha(bridgeAuthoritySha, [40]) || !isSha(expectedSha256, [64])) fail(code);
  const bytes = Buffer.from(authorityBytes ?? []);
  if (sha256(bytes) !== expectedSha256) fail(code);
  const parsed = parseJson(bytes, code);
  const keys = [
    'anchor_path_sha256', 'bridge_authority_sha', 'controller_receipt_sha256',
    'executable_sha256', 'file_mode', 'gid', 'immutable_flag',
    'normal_executor_authorized', 'open_flags', 'purpose', 'schema_version',
    'uid', 'writer_identity_sha256',
  ];
  exactKeys(parsed, keys, code);
  exactKeys(authority, keys, code);
  for (const key of keys) if (parsed[key] !== authority[key]) fail(code);
  if (parsed.schema_version !== 1 || parsed.purpose !== 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1' || parsed.bridge_authority_sha !== bridgeAuthoritySha) fail(code);
  if (parsed.uid !== 0 || parsed.gid !== 0 || parsed.open_flags !== 'O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW' || parsed.file_mode !== '0444' || parsed.immutable_flag !== 'UF_IMMUTABLE' || parsed.normal_executor_authorized !== false) fail(code);
  for (const key of ['anchor_path_sha256', 'controller_receipt_sha256', 'executable_sha256', 'writer_identity_sha256']) requireSha256(parsed[key], code);
  return true;
}

export function verifyExternalTerminalAnchor({ anchorBytes, anchorMetadata, expectedAnchorSha256, expectedPath, terminalReceiptBytes }) {
  requireSha256(expectedAnchorSha256, 'TERMINAL_ANCHOR_HASH');
  if (sha256(anchorBytes) !== expectedAnchorSha256) fail('TERMINAL_ANCHOR_HASH');
  if (anchorMetadata?.uid !== 0 || anchorMetadata?.gid !== 0 || (Number(anchorMetadata?.mode) & 0o777) !== 0o444 || Number(anchorMetadata?.nlink) !== 1 || (Number(anchorMetadata?.flags) & 0x2) !== 0x2) fail('TERMINAL_ANCHOR_IDENTITY');
  const anchor = parseJson(anchorBytes, 'TERMINAL_ANCHOR_SCHEMA');
  exactKeys(anchor, ['append_only', 'authority_sha', 'no_clobber', 'purpose', 'schema_version', 'terminal_receipt_path', 'terminal_receipt_sha256'], 'TERMINAL_ANCHOR_SCHEMA');
  if (anchor.schema_version !== 1 || anchor.purpose !== 'CI3_TERMINAL_AUTHORITY_ANCHOR_V1' || anchor.append_only !== true || anchor.no_clobber !== true || anchor.terminal_receipt_path !== expectedPath) fail('TERMINAL_ANCHOR_SCHEMA');
  if (anchor.terminal_receipt_sha256 !== sha256(terminalReceiptBytes)) fail('TERMINAL_RECEIPT_HASH');
  return true;
}

export function validateMacFetchTrustDescriptor({ descriptor, descriptorBytes, expectedSha256 }) {
  requireSha256(expectedSha256, 'SSH_TRUST_DESCRIPTOR_HASH');
  if (sha256(descriptorBytes) !== expectedSha256) fail('SSH_TRUST_DESCRIPTOR_HASH');
  exactKeys(descriptor, ['alias', 'authority_sha', 'destination_sha256', 'host_key_ed25519_sha256', 'identity_path_sha256', 'identity_public_key_sha256', 'port', 'purpose', 'remote_receipt_sha256', 'schema_version', 'ssh_executable_sha256', 'user'], 'SSH_TRUST_DESCRIPTOR_SCHEMA');
  if (descriptor.schema_version !== 1 || descriptor.purpose !== 'CI3_MAC_FETCH_TRUST_DESCRIPTOR_V1' || !isSha(descriptor.authority_sha, [40]) || descriptor.user !== 'root' || !Number.isInteger(descriptor.port) || descriptor.port < 1 || descriptor.port > 65535 || !/^ci3-authority-[a-f0-9]+$/.test(descriptor.alias)) fail('SSH_TRUST_DESCRIPTOR_SCHEMA');
  for (const key of ['remote_receipt_sha256', 'destination_sha256', 'identity_path_sha256', 'identity_public_key_sha256', 'host_key_ed25519_sha256', 'ssh_executable_sha256']) requireSha256(descriptor[key], 'SSH_TRUST_DESCRIPTOR_SCHEMA');
  return true;
}

export function validateSimulatorGateReceipt(receipt) {
  exactKeys(receipt, ['ack_sha256', 'attempts', 'authority_sha', 'bundle_id', 'config_relative_path', 'container_identity_sha256', 'credential_relative_path', 'device_selection_sha256', 'physical_effects_sha256', 'probe_schema_version', 'probe_sha256', 'purpose', 'runtime_sha256', 'schema_version', 'terminal_state'], 'SIMULATOR_GATE_SCHEMA');
  exactKeys(receipt.attempts, ['consume_probe', 'install_probe', 'launch_probe', 'remove_probe', 'resolve'], 'SIMULATOR_GATE_SCHEMA');
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_SIMULATOR_GATE_RECEIPT_V1' || !isSha(receipt.authority_sha, [40]) || receipt.bundle_id !== 'com.bodyflow.app' || receipt.config_relative_path !== LOCAL_CONFIG_RELATIVE_PATH || receipt.credential_relative_path !== LOCAL_CREDENTIAL_RELATIVE_PATH || receipt.probe_schema_version !== 1 || receipt.terminal_state !== 'SIMULATOR_GATE_PASS') fail('SIMULATOR_GATE_SCHEMA');
  for (const value of Object.values(receipt.attempts)) if (value !== 1) fail('SIMULATOR_GATE_SCHEMA');
  for (const key of ['ack_sha256', 'container_identity_sha256', 'device_selection_sha256', 'physical_effects_sha256', 'probe_sha256', 'runtime_sha256']) requireSha256(receipt[key], 'SIMULATOR_GATE_SCHEMA');
  return true;
}

export function validateInstallationReceipt(receipt) {
  exactKeys(receipt, ['authority_sha', 'config_metadata_sha256', 'config_relative_path', 'config_sha256', 'credential_metadata_sha256', 'credential_relative_path', 'credential_sha256', 'install_executable', 'install_mode', 'physical_readback_sha256', 'purpose', 'schema_version'], 'INSTALL_RECEIPT_SCHEMA');
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_SIMULATOR_INSTALL_RECEIPT_V1' || !isSha(receipt.authority_sha, [40]) || receipt.install_executable !== '/usr/bin/install' || receipt.install_mode !== '0600' || receipt.config_relative_path !== LOCAL_CONFIG_RELATIVE_PATH || receipt.credential_relative_path !== LOCAL_CREDENTIAL_RELATIVE_PATH) fail('INSTALL_RECEIPT_SCHEMA');
  for (const key of ['config_metadata_sha256', 'config_sha256', 'credential_metadata_sha256', 'credential_sha256', 'physical_readback_sha256']) requireSha256(receipt[key], 'INSTALL_RECEIPT_SCHEMA');
  return true;
}

export function sanitizeError(error) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9_]+$/.test(error.code) ? error.code : 'UNEXPECTED';
  return `ERROR ${code}`;
}

async function createBundle() {
  if (process.platform !== 'linux' || process.getuid?.() !== 0) fail('VPS_REQUIRED');
  const authority = await readGitAuthority();
  await validateDirectoryChainNoSymlinks(OUTPUT_ROOT, '/root');
  const outputMetadata = await lstat(OUTPUT_ROOT, { bigint: true });
  validatePrivateDirectory(outputMetadata, 0, 0, 'OUTPUT_ROOT_METADATA');
  const recovered = await recoverPublicationIfClaimed({ authoritySha: authority.commit, expectedGid: 0, expectedUid: 0, outputRoot: OUTPUT_ROOT });
  if (recovered) {
    const receiptFile = await readBoundOwnerOnlyFile(path.join(recovered.finalPath, 'bridge.receipt.json'), 0, 0, null);
    const receipt = parseJson(receiptFile.bytes, 'EXISTING_BUNDLE_DIVERGENT');
    process.stdout.write(`CREATE PASS status=${recovered.status} authority_sha=${authority.commit} config_sha256=${receipt.output_config_sha256}\n`);
    return;
  }
  const sources = {};
  for (const kind of Object.keys(INPUT_PATHS)) sources[kind] = await readFixedInput(kind, 0);
  const validated = validateSourceDocuments({
    credential: parseJson(sources.credential.bytes, 'CREDENTIAL_JSON'),
    deploymentReceipt: parseJson(sources.deploymentReceipt.bytes, 'DEPLOYMENT_JSON'),
    envBytes: sources.env.bytes,
    envReceipt: parseJson(sources.envReceipt.bytes, 'ENV_RECEIPT_JSON'),
    now: new Date(),
    provisioningReceipt: parseJson(sources.provisioningReceipt.bytes, 'PROVISIONING_JSON'),
  });
  const sourceGenerationId = `src-${sha256(Buffer.from(jsonBytes(Object.fromEntries(
    Object.entries(sources).map(([kind, source]) => [kind, source.sha256]),
  ))))}`;
  const remoteBundleGenerationId = `rb-${sha256(Buffer.from(jsonBytes({
    authority_commit: authority.commit,
    authority_tree_manifest_sha256: authority.authority_tree_manifest_sha256,
    source_generation_id: sourceGenerationId,
  })))}`;
  const boundAuthority = {
    ...authority,
    remote_bundle_generation_id: remoteBundleGenerationId,
    source_env_descriptor_identity_sha256: sources.env.identity_sha256,
    source_generation_id: sourceGenerationId,
  };
  const artifacts = buildBundleArtifacts({
    authority: boundAuthority,
    credentialSourcePath: INPUT_PATHS.credential,
    hashes: {
      env_source_sha256: sources.env.sha256,
      env_receipt_sha256: sources.envReceipt.sha256,
      deployment_receipt_sha256: sources.deploymentReceipt.sha256,
      credential_source_sha256: sources.credential.sha256,
      provisioning_receipt_sha256: sources.provisioningReceipt.sha256,
    },
    validated,
  });
  const result = await publishAtomic({
    authoritySha: boundAuthority.commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: OUTPUT_ROOT,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
    expectedUid: 0,
    expectedGid: 0,
  });
  process.stdout.write(`CREATE PASS status=${result.status} authority_sha=${boundAuthority.commit} config_sha256=${artifacts.receipt.output_config_sha256}\n`);
}

async function runSyntheticSelfTest() {
  let checks = 0;
  let root;
  try {
    if (parseMode(['--self-test']) !== 'self-test') fail('SELF_TEST');
    checks += 1;
    if (!verifyFindingCoverage(IMPORTANT_FINDINGS)) fail('SELF_TEST');
    checks += 1;
    validateInputMetadata({ uid: 0, gid: 0, mode: 0o600, nlink: 1, isFile: true }, 0);
    checks += 1;
    validateParentMetadata({ uid: 0, gid: 0, mode: 0o700, isDirectory: true }, 0);
    checks += 1;
    const parsed = parseExactEnv(Buffer.from('NEXT_PUBLIC_SUPABASE_URL=https://synthetic.invalid\nNEXT_PUBLIC_SUPABASE_ANON_KEY=synthetic\nSUPABASE_SERVICE_ROLE_KEY=synthetic\n'));
    if (Object.keys(parsed).length !== 3) fail('SELF_TEST');
    checks += 1;
    root = await mkdtemp(path.join(tmpdir(), 'ci3-versioned-bridge-self-test-'));
    const authoritySha = 'a'.repeat(40);
    const artifacts = buildBundleArtifacts({
      authority: {
        commit: authoritySha,
        parent: AUTHORITY_PARENT,
        tree: 'b'.repeat(40),
        subject: AUTHORITY_SUBJECT,
        committed_at_utc: '2026-08-29T00:00:00.000Z',
        generator_blob_sha: 'c'.repeat(40),
        generator_file_sha256: 'd'.repeat(64),
        controller_blob_oid: '3'.repeat(40),
        controller_file_sha256: '3'.repeat(64),
        launcher_blob_oid: '4'.repeat(40),
        launcher_file_sha256: '4'.repeat(64),
        anchor_writer_blob_oid: '5'.repeat(40),
        anchor_writer_file_sha256: '5'.repeat(64),
        authority_tree_manifest_sha256: '6'.repeat(64),
        remote_bundle_generation_id: `rb-${'7'.repeat(64)}`,
        source_generation_id: `src-${'8'.repeat(64)}`,
        source_env_descriptor_identity_sha256: '9'.repeat(64),
      },
      credentialSourcePath: INPUT_PATHS.credential,
      hashes: {
        env_source_sha256: 'e'.repeat(64),
        env_receipt_sha256: 'f'.repeat(64),
        deployment_receipt_sha256: '0'.repeat(64),
        credential_source_sha256: '1'.repeat(64),
        provisioning_receipt_sha256: '2'.repeat(64),
      },
      validated: {
        cleanupDeadline: '2099-08-29T00:00:00.000Z',
        implementationSha: EXPECTED_IMPLEMENTATION_SHA,
        mobileBffOrigin: 'https://mobile-bff-preview.invalid',
        previewDeploymentCount: 1,
        stagingProjectRef: 'syntheticstagingref',
        supabaseAnonKey: 'synthetic-anon-key',
        supabaseUrl: 'https://syntheticstagingref.supabase.invalid',
      },
    });
    const configBytes = Buffer.from(artifacts.configBytes);
    const receiptBytes = Buffer.from(artifacts.receiptBytes);
    const created = await publishAtomic({ authoritySha, configBytes, outputRoot: root, receiptBytes });
    if (created.status !== 'CREATED') fail('SELF_TEST');
    checks += 1;
    const existing = await publishAtomic({ authoritySha, configBytes, outputRoot: root, receiptBytes });
    if (existing.status !== 'EXISTS_VERIFIED') fail('SELF_TEST');
    checks += 1;
    if (sanitizeError(new BridgeError('SELF_TEST')) !== 'ERROR SELF_TEST') fail('SELF_TEST');
    checks += 1;
    process.stdout.write(`SELF_TEST PASS tests=${checks} network_calls=0\n`);
  } finally {
    if (root) await rm(root, { recursive: true, force: true });
  }
}

async function main() {
  try {
    const mode = parseMode(process.argv.slice(2));
    if (mode === 'self-test') await runSyntheticSelfTest();
    else await createBundle();
  } catch (error) {
    process.stderr.write(`${sanitizeError(error)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) await main();
