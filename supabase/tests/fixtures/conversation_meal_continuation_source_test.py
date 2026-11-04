"""Bounded lexical regression, not a PostgreSQL parser/qualification substitute."""
from pathlib import Path
import re
import unittest


class ContinuationSourceQuotes(unittest.TestCase):
    def test_every_language_body_uses_a_complete_dollar_delimiter(self):
        source = (Path(__file__).resolve().parents[2] / 'migrations' /
                  '20261104115435_conversation_meal_linked_clarification.sql').read_text()
        declarations = list(re.finditer(r'(?m)^LANGUAGE[^\n]*\bAS\s+([^\n]+)$', source))
        self.assertEqual(len(declarations), len(re.findall(r'(?m)^CREATE (?:OR REPLACE )?FUNCTION ', source)))
        for declaration in declarations:
            delimiter = declaration.group(1)
            self.assertRegex(delimiter, r'^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$$',
                             'incomplete function dollar quote: ' + delimiter)
            self.assertIn(delimiter + ';', source[declaration.end():],
                          'no matching function body closing delimiter')


if __name__ == '__main__':
    unittest.main()
