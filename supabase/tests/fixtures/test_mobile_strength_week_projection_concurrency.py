"""Local deterministic regression for PostgreSQL JSON timestamps on Python 3.9."""
import datetime
import json
import unittest

from mobile_strength_week_projection_concurrency import finalize_race_result, parse_native_utc_timestamp


class NativeTimestampRegression(unittest.TestCase):
    def test_postgres_five_fractional_digits_on_python_39(self):
        self.assertEqual(
            parse_native_utc_timestamp('2026-10-20T12:00:00.12345+00:00'),
            datetime.datetime(2026, 10, 20, 12, 0, 0, 123450, tzinfo=datetime.timezone.utc),
        )

    def test_zero_through_six_digits_and_both_utc_forms(self):
        for fraction in ('', '.1', '.12', '.123', '.1234', '.12345', '.123456'):
            for zone in ('Z', '+00:00'):
                with self.subTest(fraction=fraction, zone=zone):
                    expected = int(fraction[1:].ljust(6, '0')) if fraction else 0
                    self.assertEqual(
                        parse_native_utc_timestamp('2026-10-20T12:00:00' + fraction + zone),
                        datetime.datetime(2026, 10, 20, 12, 0, 0, expected, tzinfo=datetime.timezone.utc),
                    )

    def test_rejects_unsupported_or_nonfinite_clocks(self):
        for value in (None, 1, 'infinity', '2026-10-20T12:00:00.1234567Z',
                      '2026-10-20T12:00:00-03:00', '2026-02-30T12:00:00Z',
                      '2026-10-20T25:00:00Z'):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_native_utc_timestamp(value)


class CleanupReceiptRegression(unittest.TestCase):
    def test_serialized_result_cannot_claim_verified_after_actor_cleanup_failure(self):
        for field, value in (('reaped', False), ('readers_stopped', False), ('exit_code', 1)):
            with self.subTest(field=field):
                report = {'actor': 'B', 'reaped': True, 'readers_stopped': True, 'exit_code': 0}
                report[field] = value
                receipt = json.loads(json.dumps(finalize_race_result(
                    {'status': 'P7_DURABILITY_RESET_RACES_AND_CLOCK_VERIFIED'}, [report],
                )))
                self.assertEqual(receipt['status'], 'P7_RACES_FAILED_PRESERVED')

    def test_healthy_cleanup_preserves_verified_status(self):
        result = finalize_race_result(
            {'status': 'P7_DURABILITY_RESET_RACES_AND_CLOCK_VERIFIED'},
            [{'actor': 'A', 'reaped': True, 'readers_stopped': True, 'exit_code': 0}],
        )
        self.assertEqual(result['status'], 'P7_DURABILITY_RESET_RACES_AND_CLOCK_VERIFIED')

    def test_missing_reports_cannot_serve_as_reap_evidence(self):
        result = finalize_race_result({'status': 'P7_DURABILITY_RESET_RACES_AND_CLOCK_VERIFIED'}, [])
        self.assertEqual(result['status'], 'P7_RACES_FAILED_PRESERVED')

    def test_original_runtime_failure_survives_cleanup_failure(self):
        failure = {'type': 'TimeoutError', 'label': 'P7_missing_real_advisory_wait'}
        result = finalize_race_result({'status': 'P7_RACES_FAILED_PRESERVED', 'failure': failure}, [])
        self.assertEqual(result['status'], 'P7_RACES_FAILED_PRESERVED')
        self.assertEqual(result['failure'], failure)


if __name__ == '__main__':
    unittest.main()
