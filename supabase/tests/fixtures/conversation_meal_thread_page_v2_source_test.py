# Read-only migration contract guard; not a PostgreSQL parser/runtime substitute.
from pathlib import Path
import re
import unittest


class CompactThreadReaderSource(unittest.TestCase):
    def test_additive_reader_has_only_read_only_function_bodies_and_private_acl(self):
        root = Path(__file__).resolve().parents[2]
        matches = list((root / 'migrations').glob('*_conversation_meal_thread_page_v2.sql'))
        self.assertEqual(len(matches), 1, 'compact v2 migration is missing')
        source = matches[0].read_text()
        self.assertNotIn('CREATE OR REPLACE', source.upper())
        self.assertNotRegex(source.upper(), r'\b(?:ALTER|DROP|TRUNCATE)\s+(?:TABLE|FUNCTION|POLICY)\b')
        bodies = re.findall(r'(?ms)^CREATE FUNCTION ([^(]+).*?^LANGUAGE ([^\n]+) AS \$\$(.*?)^(?:END )?\$\$;', source)
        self.assertEqual(len(bodies), len(re.findall(r'(?m)^CREATE FUNCTION ', source)), 'every new function must have a complete bounded body')
        self.assertGreaterEqual(len(bodies), 2)
        self.assertIn('public.read_conversation_meal_journal_page_v2', source)
        for name, declaration, body in bodies:
            self.assertRegex(declaration, r'\b(?:STABLE|IMMUTABLE)\b')
            # Remove comments and SQL string literals before checking executable DML.
            executable = re.sub(r'--[^\n]*', '', body)
            executable = re.sub(r"'(?:[^']|'')*'", "''", executable)
            self.assertNotRegex(executable.upper(), r'\b(?:INSERT\s+INTO|UPDATE\s+|DELETE\s+FROM|TRUNCATE|FOR\s+(?:UPDATE|SHARE))\b')
        self.assertRegex(source, r'REVOKE ALL ON FUNCTION[\s\S]+FROM PUBLIC,anon,authenticated,service_role;')
        self.assertIn('GRANT EXECUTE ON FUNCTION public.read_conversation_meal_journal_page_v2(uuid,uuid,integer,jsonb) TO service_role;', source)


if __name__ == '__main__':
    unittest.main()
