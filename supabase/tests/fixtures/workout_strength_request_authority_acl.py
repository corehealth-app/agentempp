"""Source-only generator. No PostgreSQL, subprocess, import of candidate or network."""
import argparse
import hashlib
import json
from pathlib import Path

CASES = (
    ('table', 'private', 'SELECT ON TABLES'),
    ('function', 'public', 'EXECUTE ON FUNCTIONS'),
)


def build(source, expected_sha256):
    raw = source.encode('utf-8')
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        raise ValueError('migration_hash_mismatch')
    lines = source.splitlines(keepends=True)
    statements = [i for i, line in enumerate(lines)
                  if line.strip() and not line.lstrip().startswith('--')]
    first, last = statements[0], statements[-1]
    if lines[first] != 'BEGIN;\n' or lines[last] != 'COMMIT;\n':
        raise ValueError('outer_transaction_not_exact')
    body = ''.join(line for i, line in enumerate(lines) if i not in (first, last))
    restored = body.splitlines(keepends=True)
    restored.insert(first, lines[first])
    restored.insert(last, lines[last])
    if ''.join(restored) != source:
        raise ValueError('transaction_extraction_inverse_mismatch')
    literal = "'" + body.replace("'", "''") + "'"
    outputs = {}
    for kind, schema, privilege in CASES:
        script = (
            '\\set ON_ERROR_STOP on\n'
            'BEGIN;\nSET LOCAL ROLE postgres;\n'
            "SET LOCAL search_path=pg_catalog;\nSET LOCAL TimeZone='UTC';\n"
            "SET LOCAL DateStyle='ISO,YMD';\nSET LOCAL statement_timeout='30s';\n"
            "SET LOCAL lock_timeout='3s';\n"
            'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ' + schema
            + ' GRANT ' + privilege + ' TO c5_local_admin;\n'
            'DO $C59S15_ACL_TEST$\n'
            'DECLARE rejected boolean:=false; actual_state text; actual_message text;\n'
            'BEGIN\n  BEGIN\n    EXECUTE ' + literal + ';\n'
            '  EXCEPTION WHEN OTHERS THEN\n'
            '    GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE, actual_message=MESSAGE_TEXT;\n'
            "    IF actual_state IS DISTINCT FROM '42501' OR actual_message IS DISTINCT FROM 'C59S15_UNEXPECTED_OBJECT_ACL' THEN\n"
            '      RAISE;\n    END IF;\n    rejected:=true;\n  END;\n'
            '  IF NOT rejected THEN\n'
            "    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='C59S15_ASSERT:inherited_"
            + kind + "_acl_must_abort_migration';\n"
            '  END IF;\nEND $C59S15_ACL_TEST$;\n'
            'ROLLBACK;\n\\echo C59S15_INHERITED_' + kind.upper()
            + '_ACL_REJECTED_ROLLBACK_CONFIRMED\n'
        )
        outputs['inherited-' + kind + '-acl.sql'] = script
    proof = {
        'status': 'SOURCE_EXTRACTION_ONLY_NOT_DATABASE_EXECUTION',
        'migration_sha256': expected_sha256,
        'source_bytes': len(raw),
        'body_sha256': hashlib.sha256(body.encode('utf-8')).hexdigest(),
        'body_bytes': len(body.encode('utf-8')),
        'removed_exact_lines': [
            {'source_line_1based': first + 1, 'literal': lines[first]},
            {'source_line_1based': last + 1, 'literal': lines[last]},
        ],
        'inverse_recovers_migration_byte_exact': True,
        'all_other_source_bytes_preserved': True,
        'candidate_import_or_SQL_or_PG_execution': False,
    }
    return outputs, proof


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--migration', required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    migration = Path(args.migration)
    output = Path(args.output_dir)
    if not migration.is_absolute() or not output.is_absolute():
        raise ValueError('absolute_paths_required')
    outputs, proof = build(migration.read_text(encoding='utf-8'), args.expected_sha256)
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    for name, content in outputs.items():
        (output / name).write_text(content, encoding='utf-8')
    (output / 'EXTRACTION-PROOF.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
